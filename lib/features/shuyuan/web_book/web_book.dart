/// WebBook 门面：对外暴露搜索/发现/详情/目录/正文五类 API，
/// 内部组合 [AnalyzeUrl]（URL 模板与抓取）+ 静态分析器（BookList/BookInfo/
/// BookChapterList/BookContent）执行规则解析。
///
/// 与旧版相比，移除了 NovelResolverRegistry/BuiltinNovelResolver 间接层，
/// 直接基于 XiaoshuoHttp/AnalyzeUrl + 静态分析方法实现，便于在新项目架构下复用。
library;

import '../../../core/models/explore_kind.dart';
import '../../../core/models/novel_block.dart';
import '../../../core/novel/novel_chinese_converter.dart';
import '../../../core/utils/app_log.dart';
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

    var body = await analyzeUrl.getStrResponse();
    body = await analyzeUrl.applyLoginCheck(body);
    if (body.isEmpty) return <SearchBook>[];

    return BookList.analyzeBookList(
      bookSource: source,
      baseUrl: analyzeUrl.url,
      body: body,
      isSearch: true,
      searchKey: key,
    );
  }

  /// 解析书源的发现选项列表（含分类 / 输入框 / 按钮 / 开关 / 下拉）。
  ///
  /// [infoMap] 是发现页选项栏的持久化状态，动态 exploreUrl 脚本以全局
  /// `infoMap` 绑定读取；`baseUrl` 绑定为书源 URL（legado
  /// `BaseSource.evalJS` 语义）。静态声明不需要运行时；JS 动态分类须在
  /// [ShuyuanSourceContext] 作用域内调用，ajax/webview 走重放协议。
  /// 脚本异常经 [onScriptError] 上报，供调用方在分类为空时呈现错误项。
  List<ExploreKind> getExploreKinds(
    XiaoshuoBookSource source, {
    Map<String, String>? infoMap,
    void Function(String error)? onScriptError,
  }) {
    final exploreUrl = source.exploreUrl;
    if (exploreUrl == null || exploreUrl.trim().isEmpty) {
      return const <ExploreKind>[];
    }
    return parseExploreKinds(exploreUrl,
        infoMap: infoMap,
        baseUrl: source.bookSourceUrl,
        onScriptError: onScriptError);
  }

  /// 解析书源的发现分类列表（基于 `exploreUrl` 多级 URL 字符串）。
  ///
  /// 对齐 legado `loadableExploreMainKinds`：只保留可浏览项，并按
  /// (title, url) 去重——同一分类重复声明只生成一个分类 Tab（完整选项栏
  /// 仍由 [getExploreKinds] 提供）。
  List<ExploreCategory> getExploreCategories(
    XiaoshuoBookSource source, {
    Map<String, String>? infoMap,
  }) {
    final seen = <(String, String)>{};
    return <ExploreCategory>[
      for (final k in getExploreKinds(source, infoMap: infoMap))
        if (k.isBrowsable && seen.add((k.title, k.url!)))
          ExploreCategory(
            name: k.title.isNotEmpty ? k.title : k.url!,
            url: k.url!,
          ),
    ];
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
    var urlEntries = <UrlEntry>[
      for (final kind in getExploreKinds(source))
        if (kind.isBrowsable) UrlEntry(name: kind.title, url: kind.url!),
    ];
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
          // 发现页分类名附加到 intro 以便展示来源分类；列表规则已解析出
          // 真实简介时保留简介（legado 不注入分类名，简介优先）。
          if (entry.name.isNotEmpty &&
              (book.intro == null || book.intro!.isEmpty)) {
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

    var body = await analyzeUrl.getStrResponse();
    body = await analyzeUrl.applyLoginCheck(body);
    if (body.isEmpty) return <XiaoshuoBook>[];

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
              intro: sb.intro,
              kind: sb.kind,
              lastChapter: sb.lastChapter,
              tocUrl: sb.tocUrl,
              wordCount: sb.wordCount,
              type: sb.type,
            ))
        .toList();
  }

  /// 获取书籍详情：抓取 `bookUrl` 并通过 `ruleBookInfo` 解析。
  ///
  /// [seedBook] 为搜索/发现阶段解析出的同书条目：legado 的 Book 对象跨
  /// 阶段持续存在，详情规则只覆盖非空字段；本实现各阶段只回传 id，传入
  /// 种子可避免详情页丢失搜索阶段已有的书名/作者/封面（详情规则缺省时）。
  Future<XiaoshuoBook> getBookInfo({
    required XiaoshuoBookSource source,
    required String bookUrl,
    XiaoshuoBook? seedBook,
  }) async {
    final analyzeUrl = AnalyzeUrl(
      url: bookUrl,
      baseUrl: source.bookSourceUrl,
      source: source,
      // ruleData 贯通：API 返回的 URL 字段含 {{\$.field}} 模板时，
      // 以搜索阶段暂存的条目为求值根。
      itemContext: _bookItemContext(bookUrl),
    );

    var body = await analyzeUrl.getStrResponse();
    body = await analyzeUrl.applyLoginCheck(body);

    final book = (seedBook != null && seedBook.bookUrl == bookUrl)
        ? seedBook
        : XiaoshuoBook(bookUrl: bookUrl, name: '');
    BookInfo.analyzeBookInfo(
      bookSource: source,
      book: book,
      // legado WebBook.getBookInfoAwait：baseUrl 是请求前的书籍 URL，
      // redirectUrl 才是响应最终 URL（tocUrl 兜底/tocHtml 判定依赖前者）。
      baseUrl: bookUrl,
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
    // 变量贯通：注入搜索/发现阶段暂存的本书变量（书可能来自详情缓存或
    // 上层裸建，统一按 bookUrl 兜底补齐，供 @get/java.get 求值）。
    final stagedVars = ShuyuanSourceContext.current?.bookItemVars[book.bookUrl];
    if (stagedVars != null && stagedVars.isNotEmpty) {
      stagedVars.forEach((k, v) => book.variableMap.putIfAbsent(k, () => v));
    }
    final tocRule = source.getTocRule();
    // legado WebBook.runPreUpdateJs：**更新目录前**执行 preUpdateJs（可刷新
    // cookie / 通过 java.put 写入变量 / 修改 book.tocUrl），随后目录抓取与
    // 规则求值才能读到这些准备工作。旧实现把它放在目录解析之后当列表后处理，
    // 依赖它准备变量的源目录恒为空。失败不阻断目录流程。
    final preUpdateJs = tocRule.preUpdateJs;
    if (preUpdateJs != null && preUpdateJs.isNotEmpty) {
      final ctx = ShuyuanSourceContext.current;
      ctx?.bookInfoRefreshRequested = false;
      try {
        final preRule = AnalyzeRule(book: book);
        preRule.evalJs(preUpdateJs, null);
        preRule.variables.forEach(book.putVariable);
      } catch (_) {}
      // legado AnalyzeRule.refreshTocUrl：preUpdateJs 内调用时重新解析详情页，
      // 更新 book.tocUrl（「目录地址定期更新」的源靠它在抓目录前换新地址）。
      if (ctx != null && ctx.bookInfoRefreshRequested) {
        ctx.bookInfoRefreshRequested = false;
        try {
          await getBookInfo(
            source: source,
            bookUrl: book.bookUrl,
            seedBook: book,
          );
        } catch (_) {
          // 刷新失败保留原 tocUrl，不阻断目录流程（legado 同样仅记日志）。
        }
      }
    }
    // legado：`-` 前缀表示整张目录需反转（多页时页序一并反转），
    // 由本方法在合并去重后统一处理，分页解析本身不再翻转。
    final reverseToc = (tocRule.chapterList ?? '').startsWith('-');
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
          seedBook: book,
        );
        if (detailBook.tocUrl != null && detailBook.tocUrl!.isNotEmpty) {
          tocUrl = detailBook.tocUrl!;
          // 回填书对象：后续目录阶段复用 tocHtml / strict 条件依赖 tocUrl。
          if (book.tocUrl == null || book.tocUrl!.isEmpty) {
            book.tocUrl = detailBook.tocUrl;
          }
        }
        if (detailBook.tocHtml != null && detailBook.tocHtml!.isNotEmpty) {
          book.tocHtml ??= detailBook.tocHtml;
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
        // 详情阶段 @put/java.put 的变量随书回填（@get 跨阶段依赖）。
        if (detailBook.variableMap.isNotEmpty) {
          book.variableMap.addAll(detailBook.variableMap);
        }
      } catch (_) {
        // 详情页解析失败时维持原行为（用 bookUrl 当 tocUrl），
        // 不因兜底失败阻断目录请求。
      }
    }

    // 对照 legado WebBook.getChapterListAwait：详情阶段目录地址回落到
    // 详情页自身时，详情响应体已缓存进 tocHtml，直接解析，不再重发请求。
    final String tocBaseUrl;
    final String body;
    // legado 条件：仅当详情页本身就是目录页（bookUrl == tocUrl）时复用详情
    // 响应体，避免把详情 HTML 当目录解析（规则必然 0 命中）。
    final cachedTocHtml = book.tocHtml;
    if (cachedTocHtml != null &&
        cachedTocHtml.isNotEmpty &&
        book.bookUrl == book.tocUrl) {
      tocBaseUrl = tocUrl;
      body = cachedTocHtml;
    } else {
      final analyzeUrl = AnalyzeUrl(
        url: tocUrl,
        // legado `AnalyzeUrl(mUrl = book.tocUrl, baseUrl = book.bookUrl)`：
        // 相对目录地址按书籍详情页解析，而非书源首页（否则相对路径拼到
        // 站点根目录 → 404/错误页 → 目录恒空）。
        baseUrl: book.bookUrl,
        source: source,
        ruleData: book,
        itemContext: _bookItemContext(book.bookUrl),
      );
      body = await analyzeUrl.applyLoginCheck(
          await analyzeUrl.getStrResponse());
      tocBaseUrl = analyzeUrl.url;
    }
    if (body.isEmpty) return <XiaoshuoBookChapter>[];

    // 对齐 legado WebBook.getChapterListAwait：整页解析的 baseUrl 是请求
    // 时的 tocUrl（未跟随重定向），redirectUrl 才是最终 URL。
    final firstNextUrls = <String>[];
    final allChapters = BookChapterList.analyzeChapterList(
      bookSource: source,
      book: book,
      baseUrl: tocUrl,
      redirectUrl: tocBaseUrl,
      body: body,
      nextUrlsOut: firstNextUrls,
      applyReverse: false,
    );

    void appendBatch(List<XiaoshuoBookChapter> pageChapters) {
      if (pageChapters.isEmpty) return;
      // 增量批次以全局连续序号重编号，避免与已回传批次的 index
      // （Episode.id）冲突导致上层合并时覆盖。
      final startIdx = allChapters.length;
      for (var i = 0; i < pageChapters.length; i++) {
        pageChapters[i].index = startIdx + i;
      }
      allChapters.addAll(pageChapters);
      onBatch?.call(List<XiaoshuoBookChapter>.from(pageChapters));
    }

    // 首页批次：先回传已解析的首页章节，让上层即时渲染（无需等后续分页）。
    if (allChapters.isNotEmpty) {
      for (var i = 0; i < allChapters.length; i++) {
        allChapters[i].index = i;
      }
      onBatch?.call(List<XiaoshuoBookChapter>.from(allChapters));
    }

    // 目录分页跟随（legado 语义：首页 nextTocUrl 命中 1 条 → 串行跟随，
    // 每条后续页继续提取下一条；命中多条 → 并发抓取所有页，不再继续提取）。
    // 首页章节为空时同样跟随——部分源的首页只有分页导航。
    // 目录分页上限兜底 visited 防死循环（超长书目录可达 70+ 页）。
    const maxTocPages = 200;
    if (firstNextUrls.length == 1) {
      final visited = <String>{tocBaseUrl};
      var nextUrl = firstNextUrls.first;
      var pageCount = 0;
      while (nextUrl.isNotEmpty &&
          !visited.contains(nextUrl) &&
          pageCount < maxTocPages) {
        visited.add(nextUrl);
        pageCount++;

        // 分页抓取失败时仅停止翻页，保留已解析的首页/前几页章节，
        // 不让单页异常拖垮整个目录。
        final String pageBody;
        final AnalyzeUrl pageAnalyze;
        try {
          pageAnalyze = AnalyzeUrl(
            url: nextUrl,
            baseUrl: source.bookSourceUrl,
            source: source,
            ruleData: book,
          );
          pageBody = await pageAnalyze.getStrResponse();
        } catch (_) {
          break;
        }
        if (pageBody.isEmpty) break;

        final pageNextUrls = <String>[];
        final pageChapters = BookChapterList.analyzeChapterList(
          bookSource: source,
          book: book,
          baseUrl: nextUrl,
          redirectUrl: pageAnalyze.url,
          body: pageBody,
          nextUrlsOut: pageNextUrls,
          applyReverse: false,
        );
        if (pageChapters.isEmpty && pageNextUrls.isEmpty) break;
        appendBatch(pageChapters);
        nextUrl = pageNextUrls.isNotEmpty ? pageNextUrls.first : '';
      }
    } else if (firstNextUrls.length > 1) {
      final visited = <String>{tocBaseUrl};
      final urls = <String>[];
      for (final u in firstNextUrls) {
        if (visited.add(u)) urls.add(u);
      }
      final pageResults = await mapOrderedPool<List<XiaoshuoBookChapter>>(
        urls,
        4,
        (url) async {
          final pageAnalyze = AnalyzeUrl(
            url: url,
            baseUrl: source.bookSourceUrl,
            source: source,
            ruleData: book,
          );
          final pageBody = await pageAnalyze.getStrResponse();
          if (pageBody.isEmpty) return const <XiaoshuoBookChapter>[];
          return BookChapterList.analyzeChapterList(
            bookSource: source,
            book: book,
            baseUrl: url,
            redirectUrl: pageAnalyze.url,
            body: pageBody,
            getNextUrl: false,
            applyReverse: false,
          );
        },
      );
      for (final pages in pageResults) {
        if (pages != null) appendBatch(pages);
      }
    }

    if (allChapters.isNotEmpty) {
      // 对齐 legado：多页合并后按「URL + 标题」整体去重，再全局重编号。
      final seen = <String>{};
      final deduped = <XiaoshuoBookChapter>[];
      for (final chapter in allChapters) {
        if (seen.add('${chapter.url}\u0000${chapter.title}')) {
          deduped.add(chapter);
        }
      }
      // legado `-` 前缀：合并、去重后整列表反转（页序与页内顺序一并反转）。
      final ordered = reverseToc ? deduped.reversed.toList() : deduped;
      for (var i = 0; i < ordered.length; i++) {
        ordered[i].index = i;
      }
      return ordered;
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
    String? nextChapterUrl,
    String? chapterTitle,
  }) async {
    final contentRule = source.getContentRule();
    final book = originalBook ?? XiaoshuoBook(bookUrl: '', name: '');
    // 本章对象贯穿 URL 求值与正文规则：JS 里可读 `chapter.*`（legado
    // AnalyzeUrl/AnalyzeRule 都绑定同一 BookChapter）。标题用目录章节名
    // 预置：legado 的标题规则在图片尾巴剥离为空时回落到 `bookChapter.title`。
    final chapter = XiaoshuoBookChapter(
      bookUrl: book.bookUrl,
      url: chapterUrl,
      title: chapterTitle ?? '',
    );

    // 对照 legado WebBook.getContentAwait：正文规则为空时直接以章节链接
    // 作为正文（音频/视频源播放页章节即靠此返回直链；旧实现直接报
    // 「正文为空」，视频源整条链路在第一步就断掉）。
    if (contentRule.content == null || contentRule.content!.trim().isEmpty) {
      return BookContentResult(
        content: chapterUrl,
        blocks: <NovelBlock>[NovelTextBlock(chapterUrl)],
      );
    }

    // 对照 legado WebBook.getContentAwait：章节地址与书籍详情页相同时
    // （整本一页/详情即正文源），详情响应体已缓存进 tocHtml，直接解析。
    final cachedTocHtml = book.tocHtml;
    final String firstBody;
    final String firstBaseUrl;
    if (chapterUrl == book.bookUrl &&
        cachedTocHtml != null &&
        cachedTocHtml.isNotEmpty) {
      firstBody = cachedTocHtml;
      firstBaseUrl = chapterUrl;
    } else {
      final tocBase = (book.tocUrl != null && book.tocUrl!.isNotEmpty)
          ? book.tocUrl!
          : source.bookSourceUrl;
      final analyzeUrl = AnalyzeUrl(
        url: chapterUrl,
        baseUrl: tocBase,
        source: source,
        ruleData: book,
        chapter: chapter,
      );
      // legado getStrResponseAwait(jsStr = ruleContent.webJs, sourceRegex = …)：
      // webJs 在 WebView 路径作为页内取值脚本（Java 直连分支不消费）。
      final fetchWatch = Stopwatch()..start();
      final fetchedBody = await analyzeUrl.getStrResponse(
        jsStr: contentRule.webJs,
        sourceRegex: contentRule.sourceRegex,
      );
      firstBody = await analyzeUrl.applyLoginCheck(fetchedBody);
      AppLog.instance.i('[书源正文] 首页抓取完成 源=${source.bookSourceName} '
          '长度=${firstBody.length} 耗时=${fetchWatch.elapsedMilliseconds}ms');
      firstBaseUrl = analyzeUrl.url;
    }
    if (firstBody.isEmpty) {
      return BookContentResult(content: '', error: '正文为空');
    }

    // 音频(1)/视频(4)源正文即媒体直链，跳过 HTML 格式化（legado 同款）。
    final mediaSource =
        source.bookSourceType == 1 || source.bookSourceType == 4;

    final List<NovelBlock> blocks = <NovelBlock>[];
    final analyzeWatch = Stopwatch()..start();
    final firstContent = BookContent.analyzeContent(
      bookSource: source,
      book: book,
      bookChapter: chapter,
      // legado：baseUrl=章节原始地址，redirectUrl=响应最终地址。
      baseUrl: chapterUrl,
      redirectUrl: firstBaseUrl,
      body: firstBody,
      nextChapterUrl: nextChapterUrl,
      mediaSource: mediaSource,
      // 标题规则在全部页拼接后执行一次（见下方 postRule）；
      // replaceRegex/缩进同样延后到整章 finalizeChapter。
      processTitle: false,
      deferChapterPostProcess: true,
    );
    AppLog.instance.i('[书源正文] 内容规则解析完成 源=${source.bookSourceName} '
        '块=${firstContent.length} 耗时=${analyzeWatch.elapsedMilliseconds}ms');
    blocks.addAll(firstContent);

    final nextRule = contentRule.nextContentUrl;
    if (nextRule != null && nextRule.isNotEmpty) {
      // 章节根：起始 chapterUrl 即为本章第 1 页，同章后续页必为
      // `<根>_<数字>` / `<根>-<数字>` / `<根>/<数字>` 形式（见 _isNextPageOfChapter）。
      final chapterRoot = _chapterRootOf(firstBaseUrl);
      final visited = <String>{chapterUrl, firstBaseUrl};
      const maxPages = 30;

      // 多页并发模式：规则一次命中多个"下一页"链接（如分页条全量
      // 选择器返回整组页码链接）时，按声明顺序并发抓取（≤4 并发）并保序
      // 拼接。任一子页失败/为空即停止追加（只保留连续前缀，避免正文中段
      // 缺页）；并发子页不再继续提取下页，与串行循环互斥。
      final batchUrls = _extractNextContentUrls(
        firstBody,
        chapterUrl,
        firstBaseUrl,
        nextRule,
        book: book,
        chapter: chapter,
        nextChapterUrl: nextChapterUrl,
      )
          .where((u) =>
              !visited.contains(u) &&
              _isNextPageOfChapter(chapterRoot, u, firstBaseUrl))
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
              ruleData: book,
              chapter: chapter,
            );
            final body = await analyze.getStrResponse();
            if (body.isEmpty) return const <NovelBlock>[];
            return BookContent.analyzeContent(
              bookSource: source,
              book: book,
              bookChapter: chapter,
              baseUrl: url,
              redirectUrl: analyze.url,
              body: body,
              nextChapterUrl: nextChapterUrl,
              mediaSource: mediaSource,
              processTitle: false,
              deferChapterPostProcess: true,
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
        var currentBaseUrl = chapterUrl;
        var currentRedirectUrl = firstBaseUrl;
        var currentBody = firstBody;
        for (var i = 0; i < maxPages; i++) {
          final nextUrl = _extractNextContentUrl(
            currentBody,
            currentBaseUrl,
            currentRedirectUrl,
            nextRule,
            book: book,
            chapter: chapter,
            nextChapterUrl: nextChapterUrl,
          );
          if (nextUrl.isEmpty || visited.contains(nextUrl)) break;
          if (!_isNextPageOfChapter(chapterRoot, nextUrl, currentRedirectUrl)) {
            break;
          }
          // legado：下一页与目录中的"下一章"同一地址时停止（最后页的
          // "下一页"元素常指向下一章）。
          if (nextChapterUrl != null && nextChapterUrl.isNotEmpty) {
            final absNext =
                AnalyzeRule.absoluteUrl(currentRedirectUrl, nextUrl);
            final absChapter =
                AnalyzeRule.absoluteUrl(currentRedirectUrl, nextChapterUrl);
            if (absNext == absChapter) break;
          }
          visited.add(nextUrl);

          final pageAnalyze = AnalyzeUrl(
            url: nextUrl,
            baseUrl: source.bookSourceUrl,
            source: source,
            ruleData: book,
            chapter: chapter,
          );
          final pageBody = await pageAnalyze.getStrResponse();
          if (pageBody.isEmpty) break;

          final pageContent = BookContent.analyzeContent(
            bookSource: source,
            book: book,
            bookChapter: chapter,
            baseUrl: nextUrl,
            redirectUrl: pageAnalyze.url,
            body: pageBody,
            nextChapterUrl: nextChapterUrl,
            mediaSource: mediaSource,
            processTitle: false,
            deferChapterPostProcess: true,
          );
          if (pageContent.isEmpty) break;

          blocks.addAll(pageContent);
          currentBaseUrl = nextUrl;
          currentRedirectUrl = pageAnalyze.url;
          currentBody = pageBody;
        }
      }
    }

    // legado BookContent 外层：全部页拼接后执行 subContent（附加正文/音频
    // 歌词）与 title 规则（一次）。subContent 以首页响应为求值内容。
    final postRule = AnalyzeRule(book: book, chapter: chapter)
      ..setContent(firstBody, chapterUrl)
      ..setBaseUrl(chapterUrl)
      ..setRedirectUrl(firstBaseUrl)
      ..setNextChapterUrl(nextChapterUrl);
    final subRule = contentRule.subContent;
    if (subRule != null && subRule.isNotEmpty) {
      try {
        var subContent = postRule.getString(subRule, unescape: false).trim();
        if (subContent.toLowerCase().startsWith('http')) {
          final subAnalyze = AnalyzeUrl(
            url: subContent,
            baseUrl: firstBaseUrl,
            source: source,
            ruleData: book,
            chapter: chapter,
          );
          subContent = await subAnalyze.getStrResponse();
        }
        if (subContent.isNotEmpty) {
          if (mediaSource) {
            chapter.putVariable('lyric', subContent);
          } else {
            blocks.addAll(BookContent.extractAppendedBlocks(
              content: subContent,
              baseUrl: chapterUrl,
              redirectUrl: firstBaseUrl,
            ));
          }
        }
      } catch (_) {}
    }
    final appliedTitle =
        BookContent.applyChapterTitle(postRule, contentRule, chapter);

    // legado BookContent 外层：全部页 + 附加正文拼接后只跑一次
    // replaceRegex，再统一缩进（逐页阶段只做提取/清洗）。
    final finalized = BookContent.finalizeChapter(
      blocks: blocks,
      contentRule: contentRule,
      analyzeRule: postRule,
      mediaSource: mediaSource,
    );
    if (finalized.isEmpty) {
      return BookContentResult(content: '', title: appliedTitle, error: '解析失败');
    }

    // 音频源歌词由 subContent 写入章节变量（md3 同源），随结果回传给播放器。
    final lyricText = chapter.getVariable('lyric').trim();
    return BookContentResult(
      blocks: finalized,
      title: appliedTitle,
      lyric: lyricText.isEmpty ? null : lyricText,
    );
  }

  /// 从当前页正文中提取"下一页"绝对 URL；无下一页时返回空串。
  ///
  /// 分析器绑定书/章/baseUrl/redirectUrl/nextChapterUrl：legado 用页级
  /// AnalyzeRule 求值 nextContentUrl，JS 里可读 `chapter.*` 与
  /// `nextChapterUrl`。
  String _extractNextContentUrl(
    String body,
    String baseUrl,
    String redirectUrl,
    String rule, {
    XiaoshuoBook? book,
    XiaoshuoBookChapter? chapter,
    String? nextChapterUrl,
  }) {
    try {
      final analyzeRule = AnalyzeRule(book: book, chapter: chapter)
        ..setContent(body, baseUrl)
        ..setBaseUrl(baseUrl)
        ..setRedirectUrl(redirectUrl)
        ..setNextChapterUrl(nextChapterUrl);
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
    String body,
    String baseUrl,
    String redirectUrl,
    String rule, {
    XiaoshuoBook? book,
    XiaoshuoBookChapter? chapter,
    String? nextChapterUrl,
  }) {
    try {
      final analyzeRule = AnalyzeRule(book: book, chapter: chapter)
        ..setContent(body, baseUrl)
        ..setBaseUrl(baseUrl)
        ..setRedirectUrl(redirectUrl)
        ..setNextChapterUrl(nextChapterUrl);
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

    final workerCount =
        limit < 1 ? 1 : (limit > urls.length ? urls.length : limit);
    await Future.wait(
      <Future<void>>[for (var w = 0; w < workerCount; w++) worker()],
    );
    return results;
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
    const keys = [
      'page',
      'p',
      'pageIndex',
      'pageindex',
      'page_num',
      'pageno',
      'pn'
    ];
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
}
