/// WebBook 门面：对外暴露搜索/发现/详情/目录/正文五类 API，
/// 内部组合 [AnalyzeUrl]（URL 模板与抓取）+ 静态分析器（BookList/BookInfo/
/// BookChapterList/BookContent）执行规则解析。
///
/// 与旧版相比，移除了 NovelResolverRegistry/BuiltinNovelResolver 间接层，
/// 直接基于 XiaoshuoHttp/AnalyzeUrl + 静态分析方法实现，便于在新项目架构下复用。
library;

import 'dart:convert';

import '../../../core/models/novel_block.dart';
import '../../../core/novel/novel_chinese_converter.dart';
import '../analyze/analyze_rule.dart';
import '../analyze/analyze_url.dart';
import '../model/book_source.dart';
import '../model/search_book.dart';
import '../model/xiaoshuo_book.dart';
import '../model/xiaoshuo_book_chapter.dart';
import 'book_chapter_list.dart';
import 'book_content.dart';
import 'book_info.dart';
import 'book_list.dart';
import '../analyze/source_context.dart';
import 'web_book_types.dart';

export 'web_book_types.dart';

class WebBook {
  /// 搜索书籍：按 `source.searchUrl` 模板抓取并通过 `ruleSearch` 解析。
  ///
  /// 简繁转换：用户输入简体却搜繁体源（或反之）时，自动以另一字形补搜一次并
  /// 合并去重，避免「同书异形」漏检。原文与转换结果相同（纯 ASCII / 已统一）
  /// 时只搜一次，不额外加压。
  Future<List<SearchBook>> searchBook({
    required XiaoshuoBookSource source,
    required String key,
    int page = 1,
  }) async {
    final searchUrl = source.searchUrl;
    if (searchUrl == null || searchUrl.isEmpty) {
      throw Exception('书源未配置 searchUrl');
    }

    // 收集与原文不同的字形变体（通常至多 1 个：简→繁 或 繁→简）。
    final variants = <String>{
      convertChinese(key, ChineseConvertMode.simplifiedToTraditional),
      convertChinese(key, ChineseConvertMode.traditionalToSimplified),
    }.where((k) => k != key && k.isNotEmpty).toList();

    final merged = <SearchBook>[
      ...await _searchOnce(source, searchUrl, key, page),
    ];
    for (final k in variants) {
      try {
        merged.addAll(await _searchOnce(source, searchUrl, k, page));
      } on Object {
        // 单个变体失败不影响主结果。
      }
    }

    // 按 bookUrl 去重（保留首次出现）。
    final seen = <String>{};
    final result = <SearchBook>[];
    for (final b in merged) {
      if (seen.contains(b.bookUrl)) continue;
      seen.add(b.bookUrl);
      result.add(b);
    }
    return result;
  }

  /// 以单个关键字执行一次单源搜索（[searchBook] 的原子单元）。
  Future<List<SearchBook>> _searchOnce(
    XiaoshuoBookSource source,
    String searchUrl,
    String key,
    int page,
  ) async {
    final analyzeUrl = AnalyzeUrl(
      url: searchUrl,
      baseUrl: source.bookSourceUrl,
      source: source,
      key: key,
      page: page,
    );

    final body = await analyzeUrl.getStrResponse();
    if (body.isEmpty) return <SearchBook>[];

    return BookList.analyzeBookList(
      bookSource: source,
      baseUrl: analyzeUrl.url,
      body: body,
      isSearch: true,
      searchKey: key,
    );
  }

  /// 解析书源的发现分类列表（基于 `exploreUrl` 多级 URL 字符串）。
  List<ExploreCategory> getExploreCategories(XiaoshuoBookSource source) {
    final exploreUrl = source.exploreUrl;
    if (exploreUrl == null || exploreUrl.isEmpty) {
      return <ExploreCategory>[];
    }

    final urlEntries = _parseExploreEntries(exploreUrl);
    return urlEntries
        .map((e) => ExploreCategory(
              name: e.name.isNotEmpty ? e.name : e.url,
              url: e.url,
            ))
        .toList();
  }


  /// 当前源上下文中 bookUrl 对应的搜索条目（{{\$.field}} 模板求值根）。
  Object? _bookItemContext(String bookUrl) =>
      ShuyuanSourceContext.current?.bookItemContext[bookUrl];

  /// 抓取发现页（按分类 URL 列表逐个请求并合并结果）。
  Future<List<XiaoshuoBook>> exploreBook({
    required XiaoshuoBookSource source,
    int page = 1,
  }) async {
    final exploreUrl = source.exploreUrl;
    if (exploreUrl == null || exploreUrl.isEmpty) {
      throw Exception('书源未配置 exploreUrl');
    }

    // 先解析 exploreUrl（JSON 数组 / @js: / 多行文本），失败回退整串单条目。
    var urlEntries = _parseExploreEntries(exploreUrl);
    if (urlEntries.isEmpty) {
      final trimmed = exploreUrl.trim();
      if (trimmed.isNotEmpty) {
        urlEntries = [UrlEntry(name: '', url: trimmed)];
      }
    }
    if (urlEntries.isEmpty) {
      throw Exception('无法解析书源分类，请检查书源配置');
    }

    final allBooks = <XiaoshuoBook>[];
    for (final entry in urlEntries) {
      try {
        final books = await exploreCategory(
          source: source,
          categoryUrl: entry.url,
          page: page,
        );
        for (final book in books) {
          // 发现页分类名附加到 intro 以便展示来源分类
          if (entry.name.isNotEmpty) {
            book.intro = entry.name;
          }
          allBooks.add(book);
        }
      } catch (_) {
        continue;
      }
    }
    return allBooks;
  }

  /// 抓取指定分类 URL 的书籍列表。
  Future<List<XiaoshuoBook>> exploreCategory({
    required XiaoshuoBookSource source,
    required String categoryUrl,
    int page = 1,
  }) async {
    final analyzeUrl = AnalyzeUrl(
      url: categoryUrl,
      baseUrl: source.bookSourceUrl,
      source: source,
      page: page,
    );

    final body = await analyzeUrl.getStrResponse();
    if (body.isEmpty) return <XiaoshuoBook>[];

    BookList.setCurrentCategoryName('');

    final searchBooks = BookList.analyzeBookList(
      bookSource: source,
      baseUrl: analyzeUrl.url,
      body: body,
      isSearch: false,
    );

    return searchBooks
        .map((sb) => XiaoshuoBook(
              bookUrl: sb.bookUrl,
              name: sb.name,
              author: sb.author,
              coverUrl: sb.coverUrl,
              kind: sb.kind,
              lastChapter: sb.lastChapter,
              type: sb.type,
            ))
        .toList();
  }

  /// 获取书籍详情：抓取 `bookUrl` 并通过 `ruleBookInfo` 解析。
  Future<XiaoshuoBook> getBookInfo({
    required XiaoshuoBookSource source,
    required String bookUrl,
  }) async {
    final analyzeUrl = AnalyzeUrl(
      url: bookUrl,
      baseUrl: source.bookSourceUrl,
      source: source,
      // ruleData 贯通：API 返回的 URL 字段含 {{\$.field}} 模板时，
      // 以搜索阶段暂存的条目为求值根。
      itemContext: _bookItemContext(bookUrl),
    );

    final body = await analyzeUrl.getStrResponse();

    final book = XiaoshuoBook(bookUrl: bookUrl, name: '');
    BookInfo.analyzeBookInfo(
      bookSource: source,
      book: book,
      baseUrl: analyzeUrl.url,
      redirectUrl: analyzeUrl.url,
      body: body,
    );
    return book;
  }

  /// 获取章节目录：根据书籍的 `tocUrl`（缺省时回退到 `bookUrl`）抓取并解析。
  ///
  /// **目录分页跟随**：部分站点（如笔趣阁移动站）将章节目录拆成多页
  /// （`/book_N/`、`/book_N/index_2.html`…）。若书源声明了
  /// `ruleToc.nextTocUrl`，本方法会沿"下一页"链接继续抓取后续目录页，
  /// 合并全部章节。带访问去重与最大页数上限（默认 200 页），杜绝死循环。
  ///
  /// **渐进式分批回调 [onBatch]**：超长书（如诡秘之主 1416 章）目录可达 70+ 页，
  /// 串行抓完需多次网络请求。为避免调用方整页被阻塞，本方法在解析完**首页**
  /// 后立即通过 [onBatch] 回传首批章节，之后每抓完一页目录再回传该页增量；
  /// 最终仍返回合并后的完整列表（供调用方做最终校正）。上层据此可实现
  /// "首屏快显前若干章 + 底部加载中 + 后台续抓"的体验。每个批次的章节
  /// [XiaoshuoBookChapter.index] 已被重编号为**全局连续序号**（0 起），便于
  /// 上层按 id 去重合并。
  Future<List<XiaoshuoBookChapter>> getChapterList({
    required XiaoshuoBookSource source,
    required XiaoshuoBook book,
    void Function(List<XiaoshuoBookChapter>)? onBatch,
  }) async {
    final tocRule = source.getTocRule();
    var tocUrl = (book.tocUrl != null && book.tocUrl!.isNotEmpty)
        ? book.tocUrl!
        : book.bookUrl;

    // 兜底：上层直接请求目录而未先解析详情（book.tocUrl 为空）时，先用
    // 详情页解析出 tocUrl 再抓目录。否则会把详情页 URL 当目录页请求——
    // HTML 源详情页不含目录元素、API 源详情接口不含 rows，目录必然为空
    // （「无法解析到章节目录」的主因之一：detail 已解析出 tocUrl 但未随
    // MediaItem 传给目录请求，book 是新建的，tocUrl 丢失）。
    if (book.tocUrl == null || book.tocUrl!.isEmpty) {
      try {
        final detailBook = await getBookInfo(
          source: source,
          bookUrl: book.bookUrl,
        );
        if (detailBook.tocUrl != null && detailBook.tocUrl!.isNotEmpty) {
          tocUrl = detailBook.tocUrl!;
        }
        // 顺带回填详情字段（书名/作者/简介/封面），阅读器顶部信息更完整。
        if (book.name.isEmpty) book.name = detailBook.name;
        if (book.author.isEmpty) book.author = detailBook.author;
        if (book.intro == null || book.intro!.isEmpty) {
          book.intro = detailBook.intro;
        }
        if (book.coverUrl == null || book.coverUrl!.isEmpty) {
          book.coverUrl = detailBook.coverUrl;
        }
      } catch (_) {
        // 详情页解析失败时维持原行为（用 bookUrl 当 tocUrl），
        // 不因兜底失败阻断目录请求。
      }
    }

    final analyzeUrl = AnalyzeUrl(
      url: tocUrl,
      baseUrl: source.bookSourceUrl,
      source: source,
      itemContext: _bookItemContext(book.bookUrl),
    );

    final body = await analyzeUrl.getStrResponse();
    if (body.isEmpty) return <XiaoshuoBookChapter>[];

    final allChapters = BookChapterList.analyzeChapterList(
      bookSource: source,
      book: book,
      baseUrl: analyzeUrl.url,
      redirectUrl: analyzeUrl.url,
      body: body,
    );

    // 首页批次：先回传已解析的首页章节，让上层即时渲染（无需等后续分页）。
    if (allChapters.isNotEmpty) {
      for (var i = 0; i < allChapters.length; i++) {
        allChapters[i].index = i;
      }
      onBatch?.call(List<XiaoshuoBookChapter>.from(allChapters));
    }

    // 目录分页跟随：若声明了 nextTocUrl 且当前页有"下一页"链接，继续抓取。
    final nextTocRule = tocRule.nextTocUrl;
    if (nextTocRule != null && nextTocRule.isNotEmpty && allChapters.isNotEmpty) {
      final visited = <String>{analyzeUrl.url};
      var currentUrl = analyzeUrl.url;
      var currentBody = body;
      // 目录分页上限：部分超长书（如诡秘之主 1416 章）目录可达 70+ 页。
      // 已有 visited 去重防死循环，上限仅作安全阀。原 20 对长书严重不足（只能
      // 解析约 400 章），提升到 200 覆盖 4000 章以内的任何书籍。
      const maxTocPages = 200;

      for (var i = 0; i < maxTocPages; i++) {
        final nextUrl = _extractNextTocUrl(currentBody, currentUrl, nextTocRule);
        if (nextUrl.isEmpty || visited.contains(nextUrl)) break;
        visited.add(nextUrl);

        // 分页抓取失败时仅停止翻页，保留已解析的首页/前几页章节，
        // 不让单页异常拖垮整个目录。
        final String pageBody;
        final AnalyzeUrl pageAnalyze;
        try {
          pageAnalyze = AnalyzeUrl(
            url: nextUrl,
            baseUrl: source.bookSourceUrl,
            source: source,
          );
          pageBody = await pageAnalyze.getStrResponse();
        } catch (_) {
          break;
        }
        if (pageBody.isEmpty) break;

        final pageChapters = BookChapterList.analyzeChapterList(
          bookSource: source,
          book: book,
          baseUrl: pageAnalyze.url,
          redirectUrl: pageAnalyze.url,
          body: pageBody,
        );
        if (pageChapters.isEmpty) break;

        // 本页增量批次：以全局连续序号重编号后再回传，避免与已回传批次的
        // index（Episode.id）冲突导致上层合并时覆盖。
        final startIdx = allChapters.length;
        for (var i = 0; i < pageChapters.length; i++) {
          pageChapters[i].index = startIdx + i;
        }
        allChapters.addAll(pageChapters);
        onBatch?.call(List<XiaoshuoBookChapter>.from(pageChapters));
        currentUrl = pageAnalyze.url;
        currentBody = pageBody;
      }

      // 兜底重编号（增量批次已保证连续，此处仅为安全网）。
      for (var i = 0; i < allChapters.length; i++) {
        allChapters[i].index = i;
      }
    }

    return allChapters;
  }

  /// 获取章节正文：抓取 `chapterUrl` 并通过 `ruleContent` 解析。
  ///
  /// **正文分页跟随**（双模式）：许多站点把单章正文拆成多页
  /// （`xxx.html`、`xxx_2.html`…）。若书源声明了 `ruleContent.nextContentUrl`：
  /// - **串行模式**：规则每页命中单个"下一页"链接时，逐页跟随抓取并拼接，
  /// 直到没有下一页为止；
  /// - **并发模式**：规则一次命中多个"下一页"链接（分页条全量选择器）时，
  /// 按声明顺序 ≤4 并发抓取并保序拼接。
  ///
  /// 为避免误把"下一章"链接当成"下一页"（二者在部分站点的最后一页共用同一
  /// 元素），仅当下一页 URL 与当前页属于**同一章**（目录相同、去掉 `_N` 分页
  /// 后缀后的文件名相同）时才继续跟随；并带访问去重与最大页数上限（30），
  /// 杜绝死循环。此为通用引擎能力，对所有分页书源生效。
  Future<BookContentResult> getContent({
    required XiaoshuoBookSource source,
    required String chapterUrl,
    XiaoshuoBook? originalBook,
  }) async {
    final contentRule = source.getContentRule();
    final book = originalBook ?? XiaoshuoBook(bookUrl: '', name: '');

    final firstAnalyze = AnalyzeUrl(
      url: chapterUrl,
      baseUrl: source.bookSourceUrl,
      source: source,
    );

    // ruleContent.sourceRegex：响应体预过滤（legado 语义，命中组为正文源）。
    final firstBody =
        await firstAnalyze.getStrResponse(sourceRegex: contentRule.sourceRegex);
    if (firstBody.isEmpty) {
      return BookContentResult(content: '', error: '正文为空');
    }

    final List<NovelBlock> blocks = <NovelBlock>[];
    final firstContent = BookContent.analyzeContent(
      bookSource: source,
      book: book,
      bookChapter: XiaoshuoBookChapter(bookUrl: '', url: chapterUrl),
      baseUrl: firstAnalyze.url,
      redirectUrl: firstAnalyze.url,
      body: firstBody,
    );
    blocks.addAll(firstContent);

    final nextRule = contentRule.nextContentUrl;
    if (nextRule != null && nextRule.isNotEmpty) {
      // 章节根：起始 chapterUrl 即为本章第 1 页，同章后续页必为
      // `<根>_<数字>` / `<根>-<数字>` / `<根>/<数字>` 形式（见 _isNextPageOfChapter）。
      final chapterRoot = _chapterRootOf(firstAnalyze.url);
      final visited = <String>{chapterUrl, firstAnalyze.url};
      const maxPages = 30;

      // 多页并发模式：规则一次命中多个"下一页"链接（如分页条全量
      // 选择器返回整组页码链接）时，按声明顺序并发抓取（≤4 并发）并保序
      // 拼接。任一子页失败/为空即停止追加（只保留连续前缀，避免正文中段
      // 缺页）；并发子页不再继续提取下页，与串行循环互斥。
      final batchUrls = _extractNextContentUrls(firstBody, firstAnalyze.url, nextRule)
          .where((u) =>
              !visited.contains(u) &&
              _isNextPageOfChapter(chapterRoot, u, firstAnalyze.url))
          .take(maxPages - 1)
          .toList(growable: false);
      if (batchUrls.length > 1) {
        visited.addAll(batchUrls);
        // 多页并发模式：在并发 worker 内「取回即解析」，让同步 HTML 解析
        // 与同批其他页的网络请求重叠，缩短整章就绪的墙钟时间，并避免「先并发取回
        // 全部、再主线程串行解析」造成的长时间连续阻塞（→ 翻页/切章卡顿）。
        // 每页解析失败（task 抛错 → 池置 null）或正文为空则停止追加（保留连续前缀）。
        final pages = await mapOrderedPool<List<NovelBlock>>(
          batchUrls,
          4,
          (url) async {
            final analyze = AnalyzeUrl(
              url: url,
              baseUrl: source.bookSourceUrl,
              source: source,
            );
            final body = await analyze.getStrResponse();
            if (body.isEmpty) return const <NovelBlock>[];
            return BookContent.analyzeContent(
              bookSource: source,
              book: book,
              bookChapter: XiaoshuoBookChapter(bookUrl: '', url: analyze.url),
              baseUrl: analyze.url,
              redirectUrl: analyze.url,
              body: body,
            );
          },
        );
        for (final pageContent in pages) {
          if (pageContent == null) break;
          if (pageContent.isEmpty) break;
          blocks.addAll(pageContent);
        }
      } else {
        // 串行跟随模式：逐页提取单个"下一页"并抓取，直到没有下一页为止。
        var currentUrl = firstAnalyze.url;
        var currentBody = firstBody;
        for (var i = 0; i < maxPages; i++) {
          final nextUrl =
              _extractNextContentUrl(currentBody, currentUrl, nextRule);
          if (nextUrl.isEmpty || visited.contains(nextUrl)) break;
          if (!_isNextPageOfChapter(chapterRoot, nextUrl, currentUrl)) break;
          visited.add(nextUrl);

          final pageAnalyze = AnalyzeUrl(
            url: nextUrl,
            baseUrl: source.bookSourceUrl,
            source: source,
          );
          final pageBody = await pageAnalyze.getStrResponse();
          if (pageBody.isEmpty) break;

          final pageContent = BookContent.analyzeContent(
            bookSource: source,
            book: book,
            bookChapter: XiaoshuoBookChapter(bookUrl: '', url: nextUrl),
            baseUrl: pageAnalyze.url,
            redirectUrl: pageAnalyze.url,
            body: pageBody,
          );
          if (pageContent.isEmpty) break;

          blocks.addAll(pageContent);
          currentUrl = pageAnalyze.url;
          currentBody = pageBody;
        }
      }
    }

    if (blocks.isEmpty) {
      return BookContentResult(content: '', error: '解析失败');
    }

    // 各子页已在 BookContent.analyzeContent 内完成清洗 / 缩进 / 去广告，
    // 拼接后即为最终正文；此处不再二次归一化（避免重复缩进叠加）。
    return BookContentResult(blocks: blocks);
  }

  /// 从当前页正文中提取"下一页"绝对 URL；无下一页时返回空串。
  String _extractNextContentUrl(String body, String baseUrl, String rule) {
    try {
      final analyzeRule = AnalyzeRule()
        ..setContent(body, baseUrl)
        ..setBaseUrl(baseUrl)
        ..setRedirectUrl(baseUrl);
      final url = analyzeRule.getString(rule, isUrl: true).trim();
      // isUrl 规则命中为空时会回退返回 baseUrl，视为"无下一页"。
      if (url.isEmpty || url == baseUrl) return '';
      return url;
    } catch (_) {
      return '';
    }
  }

  /// 从当前页正文中提取全部"下一页"候选绝对 URL（多页并发模式）。
  ///
  /// 规则一次命中多个链接（如分页条全量选择器）时逐条过滤：空串、
  /// 回退 baseUrl、非 http(s) 占位链接（javascript:void(0)/# 等）均剔除。
  List<String> _extractNextContentUrls(
      String body, String baseUrl, String rule) {
    try {
      final analyzeRule = AnalyzeRule()
        ..setContent(body, baseUrl)
        ..setBaseUrl(baseUrl)
        ..setRedirectUrl(baseUrl);
      final raw = analyzeRule.getStringList(rule, isUrl: true);
      final out = <String>[];
      for (final u in raw) {
        final t = u.trim();
        if (t.isEmpty || t == baseUrl) continue;
        final lower = t.toLowerCase();
        if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
          continue;
        }
        if (!out.contains(t)) out.add(t);
      }
      return out;
    } catch (_) {
      return const <String>[];
    }
  }

  /// 有界并发池：对 [urls] 并发执行 [task]，结果**按输入顺序**返回；
  /// 单项抛错对应位为 null，不影响其他项。[limit] 为最大并发数。
  ///
  /// 静态纯调度逻辑（网络经 [task] 注入），便于单测保序性与并发上限。
  static Future<List<T?>> mapOrderedPool<T>(
    List<String> urls,
    int limit,
    Future<T> Function(String url) task,
  ) async {
    final results = List<T?>.filled(urls.length, null);
    if (urls.isEmpty) return results;
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < urls.length) {
        final i = cursor++;
        try {
          results[i] = await task(urls[i]);
        } on Object {
          results[i] = null;
        }
      }
    }

    final workerCount = limit < 1
        ? 1
        : (limit > urls.length ? urls.length : limit);
    await Future.wait(
      <Future<void>>[for (var w = 0; w < workerCount; w++) worker()],
    );
    return results;
  }

  /// 从当前目录页中提取"下一页"绝对 URL；无下一页时返回空串。
  ///
  /// 逻辑与 [_extractNextContentUrl] 一致，但语义上用于目录分页跟随。
  String _extractNextTocUrl(String body, String baseUrl, String rule) {
    try {
      final analyzeRule = AnalyzeRule()
        ..setContent(body, baseUrl)
        ..setBaseUrl(baseUrl)
        ..setRedirectUrl(baseUrl);
      final url = analyzeRule.getString(rule, isUrl: true).trim();
      if (url.isEmpty || url == baseUrl) return '';
      // 目录只有一页时，"下一页"常是占位链接（javascript:void(0)、#、空锚点），
      // 必须过滤，否则会被当成合法分页 URL 抓取而抛 "Invalid URL"。
      final lower = url.toLowerCase();
      if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
        return '';
      }
      return url;
    } catch (_) {
      return '';
    }
  }

  /// 计算章节根：host + path（去扩展名）。作为「本章第 1 页」的唯一标识。
  ///
  /// 起始 chapterUrl 一定是本章第 1 页（来自目录），因此其去扩展名后的
  /// host+path 即章节根 X；同章后续页的 URL 必然是 `X` 追加 `_N`/`-N`/`/N`。
  String _chapterRootOf(String url) {
    try {
      final u = Uri.parse(url);
      var path = u.path;
      final dot = path.lastIndexOf('.');
      final slash = path.lastIndexOf('/');
      if (dot > slash) path = path.substring(0, dot); // 去扩展名
      return '${u.host}$path';
    } catch (_) {
      return url;
    }
  }

  /// 判断 [nextUrl] 是否为章节根 [chapterRoot] 的「后续分页」。
  ///
  /// 仅当 nextUrl 去扩展名后 == `chapterRoot` 追加 `[-_/]<数字>`（可叠加多级，
  /// 如第 3 页 `X_2_3` 或 `X_3`）时为真。这样既能命中 `X.html→X_2.html`
  /// 的真实分页，又能可靠拒绝「下一章」——即使下一章的 URL 尾号只差 1
  /// （如 `..._3574.html`→`..._3573.html`），因为它不是 `X` 的前缀扩展。
  /// 通用规则，不含任何站点/域名硬编码。
  ///
  /// 另有 **query 参数分页**（`?file=...&page=2` 形式，host+path 与本章第 1 页
  /// 相同、页码在 query 中）：当 [nextUrl] 与当前页 URL [currentUrl] 同
  /// host+path、URL 不同、且 nextUrl 的 query 含页码参数（page/p 等）时，
  /// 视为同章分页放行。「下一章」的 path 必与本章不同，不会误入此分支。
  bool _isNextPageOfChapter(String chapterRoot, String nextUrl,
      [String? currentUrl]) {
    try {
      final u = Uri.parse(nextUrl);
      var path = u.path;
      final dot = path.lastIndexOf('.');
      final slash = path.lastIndexOf('/');
      if (dot > slash) path = path.substring(0, dot);
      final next = '${u.host}$path';
      if (next == chapterRoot) {
        return _isQueryPagination(currentUrl, nextUrl);
      }
      final esc = RegExp.escape(chapterRoot);
      return RegExp('^$esc([-_/]\\d+)+\$').hasMatch(next);
    } catch (_) {
      return false;
    }
  }

  /// query 参数分页判定：仅当 [nextUrl] 与 [currentUrl] 同 host+path、URL 不同、
  /// 且 nextUrl 的 query 含页码参数（page/p/pageIndex 等常见键）时视为同章
  /// 分页。当前页无页码参数（第 1 页）或页码不同均放行；两页 URL 相同
  /// （自循环）或 nextUrl 无页码参数则拒绝。
  static bool _isQueryPagination(String? currentUrl, String nextUrl) {
    if (currentUrl == null || currentUrl.isEmpty) return false;
    final cur = Uri.tryParse(currentUrl);
    final next = Uri.tryParse(nextUrl);
    if (cur == null || next == null) return false;
    if (cur.host != next.host || cur.path != next.path) return false;
    if (cur.toString() == next.toString()) return false;
    final nextPage = _pageParamOf(next.queryParameters);
    if (nextPage == null) return false;
    final curPage = _pageParamOf(cur.queryParameters);
    return curPage == null || curPage != nextPage;
  }

  /// 从 query 参数中提取页码值（page / p / pageIndex / page_num 等常见键）。
  static String? _pageParamOf(Map<String, String> params) {
    const keys = ['page', 'p', 'pageIndex', 'pageindex', 'page_num', 'pageno', 'pn'];
    for (final k in keys) {
      final v = params[k];
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  /// 兼容旧调用：从详情页取封面 URL。
  Future<String?> fetchCoverFromDetail({
    required XiaoshuoBookSource source,
    required String bookUrl,
  }) async {
    if (bookUrl.isEmpty || !bookUrl.startsWith('http')) return null;
    try {
      final book = await getBookInfo(source: source, bookUrl: bookUrl);
      final coverUrl = book.coverUrl;
      if (coverUrl != null && coverUrl.isNotEmpty) {
        return coverUrl;
      }
    } catch (_) {}
    return null;
  }

  /// 解析 exploreUrl 为分类条目。支持三种形态（对齐 legado 语义）：
  /// ① JSON 数组：条目 `{title|name, url, style?}`——url 可为 `@js:`/`<js>`
  ///    脚本（抓取期由 AnalyzeUrl.analyzeJs 带 page 绑定执行出最终 URL），
  ///    空 url 条目是分组标题行（legado 样式行）→ 跳过；
  /// ② 整体 `@js:`/`<js>` 脚本：执行结果再按行解析；
  /// ③ 多行 `名称::URL` 文本。
  /// 此前 JSON 数组走正则抽字段，url 含多行 @js: 脚本时正则截断 → 一条源
  /// 解析出 84 个垃圾分类（2026-11-14 全免小说实测），故改为结构化解码。
  /// 修复「曾被二次转义」的 exploreUrl JSON：字符串值内出现裸换行/回车
  /// （外层 JSON 解码后，url 字段里的多行 @js: 脚本带着真实换行），严格
  /// JSON 解码必败。扫描字符串边界（处理 \" 转义），仅把字符串内的裸
  /// 换行/回车转义为 \n / \r，其余原样保留。
  static String _repairJsonRawNewlines(String s) {
    // 注意：StringBuffer 构造参数是初始内容而非容量，传数字会把长度前缀
    // 写进输出（曾致 "22788[..." → JSON 解析在字符 6 处失败）。
    final out = StringBuffer();
    var inString = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '"') {
        // 统计前缀反斜杠数：偶数为真实字符串边界，奇数为转义引号。
        var bs = 0;
        var j = i - 1;
        while (j >= 0 && s[j] == '\\') {
          bs++;
          j--;
        }
        if (bs.isEven) inString = !inString;
        out.write(c);
      } else if (inString && (c == '\n' || c == '\r')) {
        out.write(c == '\n' ? r'\n' : r'\r');
      } else {
        out.write(c);
      }
    }
    return out.toString();
  }

  List<UrlEntry> _parseExploreEntries(String exploreUrl) {
    final trimmed = exploreUrl.trim();
    if (trimmed.startsWith('[')) {
      try {
        final decoded = jsonDecode(_repairJsonRawNewlines(trimmed));
        if (decoded is List) {
          final entries = <UrlEntry>[];
          for (final e in decoded) {
            if (e is! Map) continue;
            final t = e['title'] ?? e['name'];
            final title = t == null ? '' : t.toString().trim();
            final u = e['url'];
            final url = u == null ? '' : u.toString().trim();
            if (title.isEmpty || url.isEmpty) continue;
            entries.add(UrlEntry(name: title, url: url));
          }
          if (entries.isNotEmpty) return entries;
        }
      } catch (_) {
        // 非法 JSON：回退到文本行解析。
      }
    }
    return parseMultiLevelUrls(exploreUrl);
  }
}
