/// WebBook 门面：对外暴露搜索/发现/详情/目录/正文五类 API，
/// 内部组合 [AnalyzeUrl]（URL 模板与抓取）+ 静态分析器（BookList/BookInfo/
/// BookChapterList/BookContent）执行规则解析。
///
/// 与旧版相比，移除了 NovelResolverRegistry/BuiltinNovelResolver 间接层，
/// 直接基于 XiaoshuoHttp/AnalyzeUrl + 静态分析方法实现，便于在新项目架构下复用。
library;

import 'package:meta/meta.dart';

import '../../../core/download/download_settings.dart';
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
    BookListFilter? filter,
    bool Function(int size)? shouldBreak,
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
      ...await _searchOnce(source, searchUrl, key, page,
          filter: filter, shouldBreak: shouldBreak),
    ];
    for (final k in variants) {
      try {
        merged.addAll(await _searchOnce(source, searchUrl, k, page,
            filter: filter, shouldBreak: shouldBreak));
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
    int page, {
    BookListFilter? filter,
    bool Function(int size)? shouldBreak,
  }) async {
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
      // legado searchBookAwait 以 `res.url`（跟随重定向后的最终地址）作为
      // 列表基址：相对链接解析与 bookUrlPattern 匹配都按最终地址进行。
      baseUrl: analyzeUrl.lastFinalUrl ?? analyzeUrl.url,
      body: body,
      isSearch: true,
      searchKey: key,
      filter: filter,
      shouldBreak: shouldBreak,
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
    String? scriptError;
    final kinds = parseExploreKinds(exploreUrl,
        infoMap: infoMap,
        baseUrl: source.bookSourceUrl,
        onScriptError: (error) {
          scriptError = error;
          onScriptError?.call(error);
        });
    if (scriptError != null && kinds.isEmpty) {
      // 对照 legado `BookSourceExtensions`：发现分类脚本异常生成
      // `ERROR:<message>` 条目（不可浏览，UI 显示具体原因）。旧实现只回调
      // 错误并返回空列表，用户看到的是「分类一片空白」。
      return <ExploreKind>[ExploreKind(title: 'ERROR:$scriptError')];
    }
    return kinds;
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

  /// legado `String.withPageParam(page, param)`：运行期地址的参数兜底翻页。
  ///
  /// 只在地址**不带**页码规则时生效（对齐 legado `supportsParamPagination`：
  /// 含 `{{`/`}}`、`<`、内嵌 JS、URL 选项 `,{` 的一律不改写——那些地址自己
  /// 负责页码）。第一页按原地址请求，保证书源直入的首次请求不变。
  @visibleForTesting
  static String withPageParam(
      XiaoshuoBookSource source, String url, int page) {
    if (page <= 1 || url.trim().isEmpty) return url;
    if (url.contains('{{') ||
        url.contains('}}') ||
        url.contains('<') ||
        url.contains('@js:') ||
        url.toLowerCase().contains('<js>') ||
        RegExp(r',\s*\{').hasMatch(url)) {
      return url;
    }
    final param = (source.getExploreRule().pageParam ?? '').trim();
    final name = param.isEmpty ? 'page' : param;
    final hashIndex = url.indexOf('#');
    final base = hashIndex >= 0 ? url.substring(0, hashIndex) : url;
    final fragment = hashIndex >= 0 ? url.substring(hashIndex) : '';
    final pattern = RegExp('([?&])${RegExp.escape(name)}=\\d+');
    final withPage = pattern.hasMatch(base)
        ? base.replaceAllMapped(pattern, (m) => '${m.group(1)}$name=$page')
        : '$base${base.contains('?') ? '&' : '?'}$name=$page';
    return '$withPage$fragment';
  }

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
  ///
  /// [usePageParamFallback] 只对「运行时拼出的地址」启用（如筛选模板）：
  /// 书源 kind.url 这类静态分类地址的页码由规则语法自己处理，不能替它
  /// 追加 `page=` 参数（否则第二页起可能重复首页或命中错误接口）。
  Future<List<XiaoshuoBook>> exploreCategory({
    required XiaoshuoBookSource source,
    required String categoryUrl,
    int page = 1,
    bool usePageParamFallback = false,
  }) async {
    final requestUrl = usePageParamFallback
        ? withPageParam(source, categoryUrl, page)
        : categoryUrl;
    final analyzeUrl = AnalyzeUrl(
      url: requestUrl,
      baseUrl: source.bookSourceUrl,
      source: source,
      page: page,
    );

    var body = await analyzeUrl.getStrResponse();
    body = await analyzeUrl.applyLoginCheck(body);
    if (body.isEmpty) return <XiaoshuoBook>[];

    final searchBooks = BookList.analyzeBookList(
      bookSource: source,
      // 同搜索：legado exploreBookAwait 的列表基址是 `res.url`（最终地址）。
      baseUrl: analyzeUrl.lastFinalUrl ?? analyzeUrl.url,
      body: body,
      isSearch: false,
    );

    return searchBooks.map(_fromSearchBook).toList();
  }

  /// 抓取任意发现页 URL，返回「最终响应地址 + 书籍列表」。
  ///
  /// 对齐 legado `WebBook.exploreBookWithResolvedUrl`：isSearch=false，
  /// 列表规则按最终响应地址解析；[ruleData] 只参与 URL/登录脚本求值
  ///（legado 在列表解析阶段对 Book 规则数据换用空 RuleData，不泄漏进
  /// `{{book.*}}` 列表模板）。
  Future<(String, List<XiaoshuoBook>)> exploreBookWithResolvedUrl({
    required XiaoshuoBookSource source,
    required String url,
    int page = 1,
    XiaoshuoBook? ruleData,
  }) async {
    final analyzeUrl = AnalyzeUrl(
      url: url,
      baseUrl: source.bookSourceUrl,
      source: source,
      page: page,
      ruleData: ruleData,
    );
    var body = await analyzeUrl.getStrResponse();
    body = await analyzeUrl.applyLoginCheck(body);
    final resolvedUrl = analyzeUrl.lastFinalUrl ?? analyzeUrl.url;
    if (body.isEmpty) return (resolvedUrl, <XiaoshuoBook>[]);
    final searchBooks = BookList.analyzeBookList(
      bookSource: source,
      baseUrl: resolvedUrl,
      body: body,
      isSearch: false,
    );
    return (resolvedUrl, searchBooks.map(_fromSearchBook).toList());
  }

  static XiaoshuoBook _fromSearchBook(SearchBook sb) => XiaoshuoBook(
        bookUrl: sb.bookUrl,
        name: sb.name,
        author: sb.author,
        coverUrl: sb.coverUrl,
        intro: sb.intro,
        kind: sb.kind,
        lastChapter: sb.lastChapter,
        tocUrl: sb.tocUrl,
        wordCount: sb.wordCount,
        bookInfoHtml: sb.infoHtml,
        type: sb.type,
      );

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
    final seed = (seedBook != null && seedBook.bookUrl == bookUrl)
        ? seedBook
        : null;
    // legado WebBook.getBookInfoAwait：搜索/发现阶段已把列表响应体存进
    // book.infoHtml 时直接解析，不再请求同一页面（redirectUrl 取 bookUrl）。
    if (seed != null && (seed.bookInfoHtml ?? '').isNotEmpty) {
      BookInfo.analyzeBookInfo(
        bookSource: source,
        book: seed,
        baseUrl: bookUrl,
        redirectUrl: bookUrl,
        body: seed.bookInfoHtml!,
      );
      return seed;
    }

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

    final book = seed ?? XiaoshuoBook(bookUrl: bookUrl, name: '');
    BookInfo.analyzeBookInfo(
      bookSource: source,
      book: book,
      // legado WebBook.getBookInfoAwait：baseUrl 是请求前的书籍 URL，
      // redirectUrl 才是响应最终 URL（tocUrl 兜底/tocHtml 判定依赖前者）。
      baseUrl: bookUrl,
      redirectUrl: analyzeUrl.lastFinalUrl ?? analyzeUrl.url,
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
    bool runPerJs = false,
  }) async {
    // 变量贯通：注入搜索/发现阶段暂存的本书变量（书可能来自详情缓存或
    // 上层裸建，统一按 bookUrl 兜底补齐，供 @get/java.get 求值）。
    final stagedVars = ShuyuanSourceContext.current?.bookItemVars[book.bookUrl];
    if (stagedVars != null && stagedVars.isNotEmpty) {
      stagedVars.forEach((k, v) => book.variableMap.putIfAbsent(k, () => v));
    }
    final tocRule = source.getTocRule();
    // legado WebBook.getChapterListAwait(runPerJs=false)：目录抓取本身不执行
    // preUpdateJs，由调用方决定先跑一次（TocViewModel/ReadBookLoadDelegate
    // 传 true；RefreshTocUseCase 先自跑再传 false）。NexHub 的目录入口
    // （resolver/阅读器刷新）等价于前者，传 runPerJs=true。
    final preUpdateJs = tocRule.preUpdateJs;
    if (runPerJs && preUpdateJs != null && preUpdateJs.isNotEmpty) {
      final ctx = ShuyuanSourceContext.current;
      ctx?.bookInfoRefreshRequested = false;
      try {
        // legado runPreUpdateJs 用 `AnalyzeRule(book, source, true)`：
        // 脚本里的 fromBookInfo 必须为 true，否则按详情分支写法的
        // preUpdateJs 会走错路径。
        final preRule = AnalyzeRule(book: book, fromBookInfo: true);
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
    // legado：`-` 前缀表示 `reverse` 标记，控制"去重前是否反转"与
    // "去重后是否再反转"，由本方法在合并后统一处理，分页解析本身不再翻转。
    final listReversed = (tocRule.chapterList ?? '').startsWith('-');
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
      tocBaseUrl = analyzeUrl.lastFinalUrl ?? analyzeUrl.url;
    }
    // legado getChapterListAwait：响应体缺失（抓取失败/空页）直接抛错，
    // 不能伪装成「0 章」的正常目录。
    if (body.isEmpty) throw TocEmptyException();

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
    // legado 只靠 visited 防循环，没有页数上限；这里保留一个远高于真实目录
    // 的安全阈值（超长书目录实测 70+ 页），命中时显式告警而不是静默截断。
    const maxTocPages = 2000;
    var tocPageLimitHit = false;
    if (firstNextUrls.length == 1) {
      final visited = <String>{tocBaseUrl};
      var nextUrl = firstNextUrls.first;
      var pageCount = 0;
      while (nextUrl.isNotEmpty && !visited.contains(nextUrl)) {
        if (pageCount >= maxTocPages) {
          tocPageLimitHit = true;
          break;
        }
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
          // legado `BookChapterList`：串行分页的 baseUrl 与 redirectUrl 都是
          // nextUrl（请求页），不是响应最终地址——相对章节地址按请求页拼接。
          redirectUrl: nextUrl,
          body: pageBody,
          nextUrlsOut: pageNextUrls,
          applyReverse: false,
        );
        if (pageChapters.isEmpty && pageNextUrls.isEmpty) break;
        appendBatch(pageChapters);
        nextUrl = pageNextUrls.isNotEmpty ? pageNextUrls.first : '';
      }
      if (tocPageLimitHit) {
        AppLog.instance.w('[书源目录] 分页达到安全上限 $maxTocPages 页，已停止：'
            '${source.bookSourceName} / ${source.bookSourceUrl}');
      }
    } else if (firstNextUrls.length > 1) {
      final visited = <String>{tocBaseUrl};
      final urls = <String>[];
      for (final u in firstNextUrls) {
        if (visited.add(u)) urls.add(u);
      }
      final pageResults = await mapOrderedPool<List<XiaoshuoBookChapter>>(
        urls,
        await _downloadThreadCount(),
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
            // legado 并发目录分页：redirectUrl 取响应最终地址（res.url）。
            redirectUrl: pageAnalyze.lastFinalUrl ?? pageAnalyze.url,
            body: pageBody,
            getNextUrl: false,
            applyReverse: false,
          );
        },
        // legado mapAsync：任一分页失败令整个目录失败，不静默丢页。
        propagateErrors: true,
      );
      for (final pages in pageResults) {
        if (pages != null) appendBatch(pages);
      }
    }

    if (allChapters.isNotEmpty) {
      // 对齐 legado：去重前先按 `-` 前缀决定工作顺序（无前缀则整列反转），
      // 再去重（LinkedHashSet 保留工作顺序中的首个同名 URL），最后按
      // `book.reverseToc` 决定是否再反转。两者异或决定最终顺序。
      final working = listReversed ? allChapters : allChapters.reversed;
      final seen = <String>{};
      final deduped = <XiaoshuoBookChapter>[];
      for (final chapter in working) {
        // legado BookChapter equals/hashCode 仅以 url 判等。
        if (seen.add(chapter.url)) {
          deduped.add(chapter);
        }
      }
      final ordered =
          book.reverseToc ? deduped : deduped.reversed.toList();
      for (var i = 0; i < ordered.length; i++) {
        ordered[i].index = i;
      }
      // legado：formatJs 在整份目录合并/去重/倒序/重编号后单次执行，
      // gInt 整轮初始化一次（不随章节重置）。
      BookChapterList.applyFormatJs(ordered, source.getTocRule().formatJs);
      return ordered;
    }

    // legado BookChapterList：合并所有分页后仍为空 → TocEmptyException，
    // 上层据此提示/回退缓存，而不是当作正常空目录。
    throw TocEmptyException();
  }

  /// 获取章节正文：抓取 `chapterUrl` 并通过 `ruleContent` 解析。
  ///
  /// **正文分页跟随**（legado BookContent 语义）：若书源声明了
  /// `ruleContent.nextContentUrl`：
  /// - **串行模式**：首页只命中一个"下一页"链接时逐页跟随并拼接，直到没有
  ///   下一页、URL 已访问过，或与目录下一章地址相同（页内容为空也照常拼接
  ///   并继续提取下页）；
  /// - **并发模式**：首页命中多个链接时按声明顺序 ≤4 并发抓取并保序拼接，
  ///   各页独立取回，不做"连续前缀"截断。
  ///
  /// 去重只依赖已访问 URL 集合与 nextChapterUrl 停止点，不设页数上限——
  /// 与 legado 一致。
  Future<BookContentResult> getContent({
    required XiaoshuoBookSource source,
    required String chapterUrl,
    XiaoshuoBook? originalBook,
    XiaoshuoBookChapter? bookChapter,
    String? nextChapterUrl,
    String? chapterTitle,
  }) async {
    final contentRule = source.getContentRule();
    final book = originalBook ?? XiaoshuoBook(bookUrl: '', name: '');
    // 本章对象贯穿 URL 求值与正文规则：JS 里可读 `chapter.*`（legado
    // AnalyzeUrl/AnalyzeRule 都绑定同一 BookChapter）。目录阶段解析出的
    // 章节对象（含 index/variableMap）由上层透传；缺失时才用裸壳，避免
    // 正文阶段看不到目录期 @put 的变量。
    final chapter = (bookChapter != null && bookChapter.url == chapterUrl)
        ? bookChapter
        : XiaoshuoBookChapter(
            bookUrl: book.bookUrl,
            url: chapterUrl,
            title: chapterTitle ?? '',
          );

    // 对照 legado WebBook.getContentAwait：正文规则为空时直接以章节链接
    // 作为正文（音频/视频源播放页章节即靠此返回直链；旧实现直接报
    // 「正文为空」，视频源整条链路在第一步就断掉）。
    // 判空对齐 Kotlin `isNullOrEmpty()`：只含空白的规则在 Legado 仍会
    // 进入请求与解析，不能按 trim 结果当作空规则。
    if (contentRule.content == null || contentRule.content!.isEmpty) {
      return BookContentResult(
        content: chapterUrl,
        blocks: <NovelBlock>[NovelTextBlock(chapterUrl)],
      );
    }

    // legado WebBook.getContentAwait：一级目录（卷章，URL 为标题占位）在
    // 抓取前短路，直接返回卷说明（tag），不执行正文规则、不发请求。
    // BookContent.analyzeContent 内保留同样守卫作兜底。
    if (chapter.isVolume && chapter.url.startsWith(chapter.title)) {
      final tag = chapter.tag ?? '';
      return BookContentResult(
        content: tag,
        blocks:
            tag.isEmpty ? const <NovelBlock>[] : <NovelBlock>[NovelTextBlock(tag)],
      );
    }

    // 对照 legado WebBook.getContentAwait：章节地址与书籍详情页相同时
    // （整本一页/详情即正文源），详情响应体已缓存进 tocHtml，直接解析。
    final cachedTocHtml = book.tocHtml;
    // legado WebBook：请求与页解析都用 `bookChapter.getAbsoluteURL()`
    // （含 `,{...}` URL 选项段处理），直接 API 传相对地址时也能拼对。
    final absoluteChapterUrl = chapter.getAbsoluteURL();
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
        url: absoluteChapterUrl,
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
      firstBaseUrl = analyzeUrl.lastFinalUrl ?? analyzeUrl.url;
    }
    // legado BookContent：空串 body 照样进页解析——subContent 可以靠 JS 或
    // 常量给出在线正文，早退会把整章直接判空。最终仍为空才在上层报错。
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
      baseUrl: absoluteChapterUrl,
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
      // legado：已访问集合以首页的响应最终地址为种子（不是请求时的
      // chapterUrl），之后只按原始提取串比对。
      final visited = <String>{firstBaseUrl};

      // 多页并发模式：规则一次命中多个"下一页"链接（如分页条全量
      // 选择器返回整组页码链接）时，按声明顺序并发抓取（≤4 并发）并保序
      // 拼接；各页独立取回解析，不因中间页为空/失败而截断后续页。
      final batchUrls = _extractNextContentUrls(
        firstBody,
        chapterUrl,
        firstBaseUrl,
        nextRule,
        book: book,
        chapter: chapter,
        nextChapterUrl: nextChapterUrl,
      );
      if (batchUrls.length > 1) {
        // legado BookContent 并发正文：threadCount.coerceIn(1, 4)。
        final contentThreads = (await _downloadThreadCount()).clamp(1, 4);
        // 并发 worker 内「取回即解析」，让同步 HTML 解析与同批其他页的
        // 网络请求重叠，缩短整章就绪的墙钟时间。
        final pages = await mapOrderedPool<List<NovelBlock>>(
          batchUrls,
          contentThreads,
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
              // legado 并发正文分页：redirectUrl 取响应最终地址（res.url）。
              redirectUrl: analyze.lastFinalUrl ?? analyze.url,
              body: body,
              nextChapterUrl: nextChapterUrl,
              mediaSource: mediaSource,
              processTitle: false,
              deferChapterPostProcess: true,
            );
          },
          // legado mapAsync：任一分页失败令整章失败，不静默丢页。
          propagateErrors: true,
        );
        for (final pageContent in pages) {
          if (pageContent == null) continue;
          blocks.addAll(pageContent);
        }
      } else {
        // 串行跟随模式：逐页提取单个"下一页"并抓取，直到没有下一页 /
        // URL 已访问 / 命中下一章地址。legado 无页数上限，空页也照常
        // 拼接并继续提取下页。
        var currentBaseUrl = chapterUrl;
        var currentRedirectUrl = firstBaseUrl;
        var currentBody = firstBody;
        while (true) {
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
          // legado：下一页与目录中的"下一章"同一地址时停止（最后页的
          // "下一页"元素常指向下一章），基址固定为首页响应地址。
          if (nextChapterUrl != null && nextChapterUrl.isNotEmpty) {
            final absNext =
                AnalyzeRule.absoluteUrl(firstBaseUrl, nextUrl);
            final absChapter =
                AnalyzeRule.absoluteUrl(firstBaseUrl, nextChapterUrl);
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
          // legado `BookContent`：`res.body?.let { … }`——空 body 不追加、不
          // 更新 nextUrl，循环随即结束（旧实现继续对空页求值并再提取下一页，
          // 白白多发请求）。
          if (pageBody.isEmpty) break;

          final pageContent = BookContent.analyzeContent(
            bookSource: source,
            book: book,
            bookChapter: chapter,
            baseUrl: nextUrl,
            // legado 串行正文分页：redirectUrl 取响应最终地址（res.url）。
            redirectUrl: pageAnalyze.lastFinalUrl ?? pageAnalyze.url,
            body: pageBody,
            nextChapterUrl: nextChapterUrl,
            mediaSource: mediaSource,
            processTitle: false,
            deferChapterPostProcess: true,
          );
          blocks.addAll(pageContent);
          currentBaseUrl = nextUrl;
          currentRedirectUrl = pageAnalyze.lastFinalUrl ?? pageAnalyze.url;
          currentBody = pageBody;
        }
      }
    }

    // legado BookContent 外层：全部页拼接后执行 subContent（附加正文/音频
    // 歌词）、title 规则与整章 replaceRegex/缩进（一次）。
    final assembly = await BookContent.assembleChapter(
      bookSource: source,
      book: book,
      bookChapter: chapter,
      firstBody: firstBody,
      baseUrl: chapterUrl,
      redirectUrl: firstBaseUrl,
      blocks: blocks,
      mediaSource: mediaSource,
      nextChapterUrl: nextChapterUrl,
    );
    final finalized = assembly.blocks;
    if (finalized.isEmpty) {
      return BookContentResult(
        content: '',
        title: assembly.title,
        error: firstBody.isEmpty ? '正文为空' : '解析失败',
      );
    }

    return BookContentResult(
      content: _blocksToCompatText(finalized),
      blocks: finalized,
      title: assembly.title,
      lyric: assembly.lyric,
    );
  }

  /// 兼容字段 `BookContentResult.content` 的纯文本拼接：按块顺序把文本段与
  /// 媒体直链以换行连接（legado 门面返回最终 content 字符串；NexHub 新链路
  /// 以 blocks 为主，但直接 API 消费方仍可能读 content）。
  static String _blocksToCompatText(List<NovelBlock> blocks) {
    final buf = StringBuffer();
    void add(String text) {
      if (text.isEmpty) return;
      if (buf.isNotEmpty) buf.write('\n');
      buf.write(text);
    }

    for (final block in blocks) {
      if (block is NovelTextBlock) {
        add(block.text);
      } else if (block is NovelMediaBlock) {
        add(block.url);
      }
    }
    return buf.toString();
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
  /// 单项抛错对应位为 null，不影响其他项（[propagateErrors] 为 true 时
  /// 改为对齐 legado mapAsync：按输入顺序重抛首个异常）。[limit] 为最大并发数。
  ///
  /// 静态纯调度逻辑（网络经 [task] 注入），便于单测保序性与并发上限。
  static Future<List<T?>> mapOrderedPool<T>(
    List<String> urls,
    int limit,
    Future<T> Function(String url) task, {
    bool propagateErrors = false,
  }) async {
    final results = List<T?>.filled(urls.length, null);
    if (urls.isEmpty) return results;
    final errors = List<Object?>.filled(urls.length, null);
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < urls.length) {
        final i = cursor++;
        try {
          results[i] = await task(urls[i]);
        } on Object catch (e) {
          errors[i] = e;
        }
      }
    }

    final workerCount =
        limit < 1 ? 1 : (limit > urls.length ? urls.length : limit);
    await Future.wait(
      <Future<void>>[for (var w = 0; w < workerCount; w++) worker()],
    );
    if (propagateErrors) {
      for (final e in errors) {
        if (e != null) throw e;
      }
    }
    return results;
  }

  /// 并发分页线程数（legado DownloadCacheSettings.threadCount）。
  /// 设置读取失败（未初始化存储）时回退默认值。
  Future<int> _downloadThreadCount() async {
    try {
      final settings = await DownloadSettingsStore().load();
      return settings.threadCount;
    } on Object {
      return const DownloadSettings().threadCount;
    }
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
