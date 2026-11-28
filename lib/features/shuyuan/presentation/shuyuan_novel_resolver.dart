/// 书源解析器：实现 [SourceResolver]，桥接 PluginConfig →
/// XiaoshuoBookSource → WebBook，让书源能被 MediaApiService
/// 统一调度。
///
/// 触发条件：当 PluginConfig.selectors['xiaoshuo'] 为 Map 时（由
/// [ShuyuanAdapter] 写入），ResolverRegistry.find() 返回本解析器。
///
/// API 映射：
/// - `search`：WebBook.searchBook(key=vars['keyword'])
/// - `explore`/`latest`：WebBook.exploreBook / exploreCategory
/// - `detail`：WebBook.getBookInfo(bookUrl=vars['id'])
/// - `toc`/`chapters`：WebBook.getChapterList(book=by id)
/// - `content`：WebBook.getContent(chapterUrl=vars['url'])
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../../core/models/category_entry.dart';
import '../../../core/models/episode.dart';
import '../../../core/models/explore_kind.dart';
import '../../../core/models/media_item.dart';
import '../../../core/models/web_file_item.dart';
import '../../../core/models/novel_block.dart'
    show
        NovelBlock,
        NovelContentResult,
        NovelImageBlock,
        NovelMediaBlock,
        NovelTextBlock;
import 'package:meta/meta.dart';

import '../../../core/models/plugin_config.dart';
import '../../../core/models/source_review.dart';
import '../../../core/novel/novel_pay_result.dart';
import '../../../core/resolver/source_resolver.dart';
import '../../../core/resolver/resolver_registry.dart';
import '../../../core/resolver/webview_resolver.dart';
import '../../../core/scraper/verification_detector.dart';
import '../../../core/utils/app_log.dart';
import '../web_book/book_chapter_list.dart';
import '../web_book/book_content.dart';
import '../web_book/book_info.dart';
import '../web_book/book_list.dart';
import '../web_book/book_review.dart';
import '../model/book_source.dart';
import '../model/search_book.dart';
import '../model/source_callback_result.dart';
import '../model/xiaoshuo_book.dart';
import '../model/xiaoshuo_book_chapter.dart';
import '../analyze/js_engine.dart';
import '../analyze/analyze_rule.dart';
import '../analyze/analyze_url.dart';
import '../analyze/image_decoder.dart';
import '../analyze/source_context.dart';
import '../analyze/web_file_naming.dart';
import '../shuyuan_adapter.dart';
import '../shuyuan_explore_info_store.dart';
import '../shuyuan_explore_kinds_store.dart';
import '../web_book/related_books.dart';
import '../web_book/web_book.dart';
import 'shuyuan_interactive.dart';

class ShuyuanNovelResolver
    implements
        SourceResolver,
        RenderedHtmlCapable,
        ExploreCategoriesCapable,
        ExploreKindsCapable {
  ShuyuanNovelResolver();

  final WebBook _webBook = WebBook();

  /// 每源运行时上下文（cookie 覆盖层/源变量/登录信息/缓存），注入对象
  /// （cookie/source/book/cache）的宿主侧。按源 id 缓存。
  final Map<String, ShuyuanSourceContext> _contexts = {};

  /// 详情阶段解析出的书籍对象（含 ruleBookInfo.tocUrl），供随后打开的目录
  /// 阶段复用——legado 的书对象在详情/加入书架时就已持有 tocUrl，目录请求
  /// 从不回落到详情页 URL。NexHub 各阶段独立调用且只回传 id，若不缓存，
  /// API 型源（宜搜/百度等，目录是独立接口）会把详情接口当目录接口请求，
  /// 章节恒为空。数量很小（只在用户浏览过的书之间滚动）。
  final Map<String, XiaoshuoBook> _bookInfoCache = {};
  static const int _bookInfoCacheLimit = 32;

  void _rememberBookInfo(XiaoshuoBook book) {
    if (book.bookUrl.isEmpty) return;
    _bookInfoCache.remove(book.bookUrl);
    _bookInfoCache[book.bookUrl] = book;
    if (_bookInfoCache.length > _bookInfoCacheLimit) {
      _bookInfoCache.remove(_bookInfoCache.keys.first);
    }
  }

  /// 搜索/发现阶段解析出的书条目，按 bookUrl 暂存，作为详情阶段的解析
  /// 种子：legado 的 Book 对象在搜索→详情链路中持续携带书名字段，详情
  /// 规则解析为空时不会清掉已有值。NexHub 各阶段只回传 id，不暂存时
  /// 详情页会丢失搜索阶段已有的书名/作者/封面（如宜搜 API：搜索有封面，
  /// 详情封面规则缺省 → 详情页无封面）。
  final Map<String, XiaoshuoBook> _searchSeedCache = {};
  static const int _searchSeedCacheLimit = 64;

  void _rememberSearchSeed(XiaoshuoBook book) {
    if (book.bookUrl.isEmpty) return;
    _searchSeedCache.remove(book.bookUrl);
    _searchSeedCache[book.bookUrl] = book;
    if (_searchSeedCache.length > _searchSeedCacheLimit) {
      _searchSeedCache.remove(_searchSeedCache.keys.first);
    }
  }

  XiaoshuoBook? _seedFor(String bookUrl) => _searchSeedCache[bookUrl];

  /// 目录阶段解析出的章节对象（含 index / 目录期 @put 的 variableMap），
  /// 供随后的正文请求复用——legado 的 BookChapter 实体跨阶段携带这些字段，
  /// NexHub 各阶段只回传 URL，不暂存则正文的 `chapter.index/variableMap`
  /// 恒为空壳。按「书 id + 章节 URL」索引，只在最近浏览的书章间滚动。
  final Map<String, XiaoshuoBookChapter> _chapterCache = {};
  static const int _chapterCacheLimit = 4096;

  String _chapterKey(String bookId, String url) => '$bookId\u0000$url';

  void _rememberChapters(String bookId, Iterable<XiaoshuoBookChapter> chapters) {
    if (bookId.isEmpty) return;
    for (final chapter in chapters) {
      if (chapter.url.isEmpty) continue;
      final key = _chapterKey(bookId, chapter.url);
      _chapterCache.remove(key);
      _chapterCache[key] = chapter;
      if (_chapterCache.length > _chapterCacheLimit) {
        _chapterCache.remove(_chapterCache.keys.first);
      }
    }
  }

  XiaoshuoBookChapter? _chapterFor(String bookId, String url) {
    if (bookId.isEmpty || url.isEmpty) return null;
    return _chapterCache[_chapterKey(bookId, url)];
  }

  Iterable<XiaoshuoBookChapter> _cachedChaptersFor(String bookId) {
    final prefix = '$bookId\u0000';
    return _chapterCache.entries
        .where((e) => e.key.startsWith(prefix))
        .map((e) => e.value);
  }

  /// legado BookContent 外层：调用方未传 nextChapterUrl 时，按目录序号取
  /// 下一章（index+1），末章回落到首章（index 0），与 md3 的
  /// `getChapter(index+1) ?: getChapter(0)` 一致。
  @visibleForTesting
  static String nextChapterUrlFallback(
    Iterable<XiaoshuoBookChapter> chapters,
    int index,
  ) {
    String? next;
    String? first;
    for (final c in chapters) {
      if (c.url.isEmpty) continue;
      if (c.index == index + 1) next = c.url;
      if (c.index == 0) first ??= c.url;
    }
    return next ?? first ?? '';
  }

  /// 正文阶段的实际 nextChapterUrl：优先调用方传入，其次按缓存目录兜底。
  String _resolveNextChapterUrl(
    String provided,
    String bookId,
    XiaoshuoBookChapter? current,
  ) {
    if (provided.isNotEmpty) return provided;
    final index = current?.index;
    if (bookId.isEmpty || index == null) return '';
    return nextChapterUrlFallback(_cachedChaptersFor(bookId), index);
  }

  XiaoshuoBook _seedFromSearchBook(SearchBook sb) {
    return XiaoshuoBook(
      bookUrl: sb.bookUrl,
      name: sb.name,
      author: sb.author,
      coverUrl: sb.coverUrl,
      intro: sb.intro,
      kind: sb.kind,
      lastChapter: sb.lastChapter,
      latestChapterTitle: sb.latestChapterTitle,
      tocUrl: sb.tocUrl,
      wordCount: sb.wordCount,
      // legado BookList：搜索/发现响应体在 baseUrl 即书籍地址时存入
      // infoHtml，详情阶段据此免抓取复用（见 WebBook.getBookInfo）。
      bookInfoHtml: sb.infoHtml,
      // legado SearchBook.toBook：目录响应体（整页即书时）随书携带，
      // 目录阶段免二次请求。
      tocHtml: sb.tocHtml,
      type: sb.type,
      // legado：列表阶段写入的变量随书进入详情/目录（@get/java.get 续命）。
    )..variableMap.addAll(sb.variableMap);
  }

  /// 发现/搜索列表 → MediaItem，同时暂存解析种子供详情阶段复用。
  List<MediaItem> _mapAndSeedSearchBooks(
      List<SearchBook> books, PluginConfig source) {
    for (final sb in books) {
      _rememberSearchSeed(_seedFromSearchBook(sb));
    }
    return books.map((sb) => _searchBookToMediaItem(sb, source)).toList();
  }

  List<MediaItem> _mapAndSeedBooks(
      List<XiaoshuoBook> books, PluginConfig source) {
    for (final b in books) {
      _rememberSearchSeed(b);
    }
    return books.map((b) => _xiaoshuoBookToMediaItem(b, source)).toList();
  }

  Future<ShuyuanSourceContext> _contextFor(PluginConfig source) async {
    final ctx = _contexts[source.id] ??= await ShuyuanSourceContext.forSource(
      source.id,
    );
    // 登录窗/交互浏览器可能由另一个 ctx 实例写入并落盘。
    await ctx.refreshCookiesFromStore();
    await ctx.refreshLoginFromStore();
    return ctx;
  }

  /// legado Book.durChapterIndex / durChapterTitle：规则上下文暴露的阅读
  /// 进度字段（脚本里 `book.durChapterIndex` 可读）。调用方经 vars 传入；
  /// 缺省的阶段保持已有值（legado 的 Book 对象跨阶段持久，进度不会因
  /// 一次目录/搜索请求被清零）。
  void _seedReaderProgress(ShuyuanSourceContext ctx, Map<String, String> vars) {
    final index = vars['durChapterIndex'];
    if (index != null) {
      ctx.bookInfo['durChapterIndex'] = '${int.tryParse(index) ?? 0}';
    }
    final title = vars['durChapterTitle'];
    if (title != null) ctx.bookInfo['durChapterTitle'] = title;
  }

  /// 重放轮次上限（安全阀）：正常多跳脚本 3–6 轮即收敛。
  static const int _maxReplayPasses = 16;

  /// 单阶段重放总时长预算。
  static const Duration _replayBudget = Duration(seconds: 120);

  /// 发现分类重放预算：进分类页前的等待，超过则先用已解析结果出 Tab。
  /// 与 [_replayBudget] 对齐：单请求超时就有 45s，预算若同为 45s，一个慢
  /// 请求就会把多跳发现脚本（jsLib→importScript→ajax→…）直接掐死。
  static const Duration _exploreCategoryBudget = Duration(seconds: 120);

  /// 无 category 的发现入口最多尝试的分类数（首个失效/为空时顺延，
  /// 避免全量串行抓取导致首页长时间加载）。
  static const int _exploreHomeFallbackLimit = 3;

  /// 是否还允许继续下一轮重放。
  bool _replayAllowed(int pass, DateTime deadline) =>
      pass + 1 < _maxReplayPasses && DateTime.now().isBefore(deadline);

  @override
  Future<dynamic> resolve(
    PluginConfig source,
    String apiName, {
    Map<String, String> vars = const {},
    void Function(List<dynamic>)? onProgress,
  }) async {
    final shuyuanSource = ShuyuanAdapter.fromPluginConfig(source);
    if (shuyuanSource == null) {
      throw StateError(
        'ShuyuanNovelResolver received a non-shuyuan source: ${source.id}',
      );
    }
    final bookSource = shuyuanSource.toBookSource();
    final ctx = await _contextFor(source);
    // 源 URL / jsLib（引擎首次 eval 前预执行）/ `source.<field>` 快照。
    ctx.bindSource(bookSource);
    _seedReaderProgress(ctx, vars);

    return ShuyuanSourceContext.run(ctx, () async {
      final replayWatch = Stopwatch()..start();
      try {
        // 「确定性重放」：脚本内 java.ajax / java.webView 首轮返回占位符并
        // 记录请求；占位符随结果传播，本循环抓取未满足请求写入缓存后重放。
        //
        // 轮次不设死 4 轮：多跳脚本（ajax→webview→ajax）需要与跳数同量级的
        // 轮次。三个安全阀：最多 [_maxReplayPasses] 轮、总时长 [_replayBudget]、
        // 以及「本轮没有任何新抓取就停」（防止 URL 带随机数的脚本无限重放）。
        //
        // 每个阶段重新开始重放：清空上一阶段/上一本书残留的瞬态缓存
        // （页面响应 / ajax / webview / 待抓取队列 + JS 全局）。只在这里清一次
        // ——循环内每一轮都依赖页面缓存，否则重放会把同一页真实重复抓多次。
        ctx.clearStageCaches();
        JsEngine.resetReplayCachesFor(source.id);
        // 事件回调（callback）允许 startBrowser 真开浏览器；其余阶段不弹。
        final isCallback = apiName == 'callback';
        var deadline = DateTime.now().add(_replayBudget);
        // 面包屑日志（信息级常驻）：定位「一直加载」时，最后一条日志即卡点
        // ——停在派发前说明 JS/正则同步执行卡死；停在 settle 说明网络等待。
        AppLog.instance.i('[书源重放] 开始 api=$apiName '
            '源=${bookSource.bookSourceName}');
        dynamic out;
        for (var pass = 0; pass < _maxReplayPasses; pass++) {
          ctx.ajaxPending.clear();
          ctx.webviewPending.clear();
          ctx.deferFeedback = true;
          ctx.deferredToasts.clear();
          AppLog.instance.i('[书源重放] 轮次=$pass 派发前 '
              '已用时=${replayWatch.elapsedMilliseconds}ms');
          final dispatchWatch = Stopwatch()..start();
          try {
            out = await _dispatch(source, bookSource, apiName, vars,
                onProgress: onProgress);
          } on Object {
            if (_hasPendingReplay(ctx, openBrowsers: isCallback) &&
                _replayAllowed(pass, deadline)) {
              final settled = await _settleReplay(ctx, bookSource, source,
                  deadline: deadline, openBrowsers: isCallback);
              deadline = deadline.add(settled.waited);
              if (settled.fetched > 0) continue;
            }
            rethrow;
          }
          if (!_hasPendingReplay(ctx, openBrowsers: isCallback)) return out;
          AppLog.instance.i('[书源重放] 轮次=$pass 派发完成 '
              '耗时=${dispatchWatch.elapsedMilliseconds}ms '
              '待办 ajax=${ctx.ajaxPending.length} '
              'webview=${ctx.webviewPending.length}');
          if (!_replayAllowed(pass, deadline)) break;
          final settleWatch = Stopwatch()..start();
          final settled = await _settleReplay(ctx, bookSource, source,
              deadline: deadline, openBrowsers: isCallback);
          deadline = deadline.add(settled.waited);
          AppLog.instance.i('[书源重放] 轮次=$pass settle 完成 '
              '抓取=${settled.fetched} 耗时=${settleWatch.elapsedMilliseconds}ms');
          if (settled.fetched == 0) break;
        }
        return out;
      } on VerificationRequiredException catch (e) {
        // 反爬拦截（Cloudflare / 滑块 / 临时挑战）。声明 useWebview 的书源（如
        // 笔趣阁）被站点的 TLS/指纹校验拦截——Dart HTTP 的客户端指纹被拒，手动
        // Cookie 验证无效。改为抛 [WebViewHtmlRequest]，交由 UI 打开真浏览器
        // 取回渲染后 HTML 再回灌源选择器解析；未声明 useWebview 的书源维持原
        // 验证流程（仅影响已显式开启的书源，不影响其它书源）。
        // 源级 useWebview 声明或本次请求 URL 选项 webView:true 均走
        // WebView 渲染回灌（legado useWebView 语义）。
        if (source.useWebview || e.preferWebView) {
          throw WebViewHtmlRequest(
            sourceId: source.id,
            apiName: apiName,
            url: e.url,
            js: e.webJs,
          );
        }
        rethrow;
      } finally {
        // 中间轮的提示已在下一轮开始前清掉；此处放行最终轮的真实反馈。
        AppLog.instance.i('[书源重放] 退出 api=$apiName '
            '耗时=${replayWatch.elapsedMilliseconds}ms');
        ctx.flushDeferredToasts();
      }
    });
  }

  /// 分发到各阶段处理（settle 循环体）。
  Future<dynamic> _dispatch(
    PluginConfig source,
    XiaoshuoBookSource bookSource,
    String apiName,
    Map<String, String> vars, {
    void Function(List<dynamic>)? onProgress,
  }) async {
    switch (apiName) {
      case 'search':
        return await _handleSearch(source, bookSource, vars);
      case 'explore':
        return await _handleExplore(source, bookSource, vars);
      case 'category':
        // 动态筛选 Sheet 可能发 __route='category'（被 MediaApiService 剔除后
        // 不影响源 URL）；本源 routes 不含 'category'，通常已被忽略并沿用原
        // apiName。此处兜底，避免极端情况下抛 UnsupportedError。
        return await _handleExplore(source, bookSource, vars);
      case 'latest':
        return await _handleLatest(source, bookSource, vars);
      case 'detail':
        return await _handleDetail(source, bookSource, vars);
      case 'related':
        return await _handleRelated(source, bookSource, vars);
      case 'toc':
      case 'chapters':
      case 'episodes':
        return await _handleChapterList(source, bookSource, vars,
            onProgress: onProgress);
      case 'content':
        return await _handleContent(source, bookSource, vars);
      case 'video':
        return await _handleVideo(source, bookSource, vars);
      case 'images':
        // 漫画模块的正文路由：书源正文（img 标签/URL 列表）→ 图片 URL 列表。
        return await _handleComicImages(source, bookSource, vars);
      case 'pay':
        return await _handlePayAction(source, bookSource, vars);
      case 'reviews':
        return await _handleReviews(bookSource, vars);
      case 'reviewQuotes':
        return await _handleReviewQuotes(bookSource, vars);
      case 'reviewAction':
        return await _handleReviewAction(bookSource, vars);
      case 'scriptAction':
        return await _handleScriptAction(source, bookSource, vars);
      case 'webFiles':
        return await _handleWebFiles(source, bookSource, vars);
      case 'webFileDownload':
        return await _handleWebFileDownload(source, bookSource, vars);
      case 'callback':
        return await _handleSourceCallback(source, bookSource, vars);
      default:
        throw UnsupportedError(
          'ShuyuanNovelResolver does not support apiName: $apiName',
        );
    }
  }

  /// 抓取脚本 ajax 记录的未满足请求，写入重放缓存；返回真正发起的请求数。
  ///
  /// 实现统一收在 [ShuyuanSourceContext.settleAjax]：此前 resolver 与
  /// source_context 各有一份（POST 选项合并的容错写法已经漂移），
  /// 登录脚本与阶段流程走的是两条不同路径，容易改一处漏一处。
  Future<int> _fetchAjaxPending(
    ShuyuanSourceContext ctx,
    XiaoshuoBookSource bookSource, {
    DateTime? deadline,
  }) =>
      ShuyuanSourceContext.settleAjax(ctx, bookSource, deadline: deadline);

  /// 本轮是否还有等待宿主处理的请求（ajax 走 HTTP，webview 走无头渲染，
  /// 交互式 await/验证码走冻结缓存）。发现阶段不弹 startBrowser；
  /// [openBrowsers] 为 true（事件回调）时 startBrowser 也计入待办。
  bool _hasPendingReplay(ShuyuanSourceContext ctx,
          {bool openBrowsers = false}) =>
      ctx.ajaxPending.isNotEmpty ||
      ctx.fileOpPending.isNotEmpty ||
      ctx.webviewPending.isNotEmpty ||
      hasPendingInteractive(ctx, includeOpenBrowsers: openBrowsers);

  /// 一次性补齐重放请求（ajax / webview / 交互式浏览器与验证码）；
  /// 返回本轮新抓取的条目数（0 = 无进展）与等待时长（供调用方延长预算）。
  ///
  /// [deadline] 透传给 settle：预算耗尽后剩余请求按失败缓存立即消解，
  /// 单个 settle 的等待也有上界（最多一个在途请求的 45s 超时）。
  Future<ShuyuanInteractiveSettleResult> _settleReplay(
    ShuyuanSourceContext ctx,
    XiaoshuoBookSource bookSource,
    PluginConfig source, {
    DateTime? deadline,
    bool openBrowsers = false,
  }) async {
    var fetched = await _fetchAjaxPending(ctx, bookSource, deadline: deadline);
    fetched +=
        await ShuyuanSourceContext.settleWebview(ctx, deadline: deadline);
    // 交互式等待（浏览器/验证码）不计预算：其耗时已通过 waited 反补给调用方，
    // 用户操作时长不可控，这里不能按 deadline 掐断。
    final interactive = await settleShuyuanInteractive(
      ctx,
      bookSource,
      pluginSource: source,
      openBrowsers: openBrowsers,
    );
    // 预算只按「用户交互等待」延长：ajax/webview 抓取本身有各自的 45s 超时，
    // 若把它们耗时也算作返回的 waited，等于每轮免费续期，总预算形同虚设。
    return ShuyuanInteractiveSettleResult(
      fetched + interactive.fetched,
      interactive.waited,
    );
  }

  /// 渲染后 HTML 回灌：WebView 过验证后拿回的整页 HTML 直接走 WebBook 规则解析，
  /// 不再重新发起直连请求（否则会再次撞 Cloudflare）。覆盖 search/explore/latest
  /// （列表类，用 [BookList] 解析）；detail/chapters/content 同样直接解析渲染
  /// HTML，不再回退直连 [resolve]（否则回灌后会再次撞墙，形成「验证→重抓→再验证」
  /// 死循环，正文/目录/详情永远为空）。
  @override
  Future<dynamic> resolveRenderedHtml(
    PluginConfig source,
    String apiName,
    String html, {
    Map<String, String> vars = const {},
  }) async {
    final shuyuanSource = ShuyuanAdapter.fromPluginConfig(source);
    if (shuyuanSource == null) {
      throw StateError(
        'ShuyuanNovelResolver received a non-shuyuan source: ${source.id}',
      );
    }
    final bookSource = shuyuanSource.toBookSource();
    // 与 resolve 同源：走 _contextFor 装载持久化 cookie / 源变量。
    // 旧实现 `?? ShuyuanSourceContext(...)` 直接新建空上下文，
    // WebView 回灌路径永远没有登录态。
    final ctx = await _contextFor(source);
    ctx.bindSource(bookSource);
    _seedReaderProgress(ctx, vars);
    // 渲染回灌同样从干净的重放缓存开始，避免命中上一阶段的旧响应。
    ctx.clearStageCaches();
    JsEngine.resetReplayCachesFor(source.id);
    return ShuyuanSourceContext.run(ctx, () async {
      switch (apiName) {
        case 'search':
        case 'explore':
        case 'category':
        case 'latest':
          final isSearch = apiName == 'search';
          // 列表基址用「渲染页的实际地址」（legado `res.url`）：分类/发现页
          // 常在子路径（`/book/`、`/list/2.html`）下，按源根拼接会把相对
          // 详情链接拼错。宿主回灌时经 `__renderedUrl` 透传，未提供才退回源根。
          final renderBaseUrl = (vars['__renderedUrl'] ?? '').trim();
          final books = BookList.analyzeBookList(
            bookSource: bookSource,
            baseUrl: renderBaseUrl.isNotEmpty
                ? renderBaseUrl
                : bookSource.bookSourceUrl,
            body: html,
            isSearch: isSearch,
            searchKey: isSearch ? (vars['keyword'] ?? vars['key'] ?? '') : null,
          );
          return _mapAndSeedSearchBooks(books, source);
        case 'detail':
          // 详情页：用 [BookInfo] 解析渲染后 HTML（与 [WebBook.getBookInfo] 同口径）。
          // 复用搜索/发现阶段的种子书，详情规则为空时保留列表阶段字段。
          final id = vars['id'] ?? vars['detailUrl'] ?? '';
          final book = _seedFor(id) ?? XiaoshuoBook(bookUrl: id, name: '');
          BookInfo.analyzeBookInfo(
            bookSource: bookSource,
            book: book,
            baseUrl: id,
            redirectUrl: id,
            body: html,
          );
          return _xiaoshuoBookToMediaItem(book, source);
        case 'toc':
        case 'chapters':
        case 'episodes':
          // 目录：用 [BookChapterList] 解析渲染后 HTML，随后走与直连
          // [WebBook.getChapterList] **同一合并层**（审计 M13：去重 →
          // reverseToc 终序 → 全局重编号 → formatJs 单次执行；此前回灌只做
          // 单页 formatJs，卷章占位与「最新章节预览」重复项会混进目录）。
          // 分页跟随/preUpdateJs 属网络获取阶段，回灌（已取得渲染体）不适用。
          final id = vars['id'] ?? vars['detailUrl'] ?? '';
          final book = _seedFor(id) ??
              _bookInfoCache[id] ??
              XiaoshuoBook(bookUrl: id, name: '');
          final pageChapters = BookChapterList.analyzeChapterList(
            bookSource: bookSource,
            book: book,
            baseUrl: id,
            redirectUrl: id,
            body: html,
          );
          if (pageChapters.isEmpty) throw TocEmptyException();
          final listReversed =
              (bookSource.getTocRule().chapterList ?? '').startsWith('-');
          final chapters = _webBook.mergeChapterList(
              bookSource, book, pageChapters,
              listReversed: listReversed);
          _rememberChapters(id, chapters);
          // 卷章占位过滤与直连同一层（volume 条目不进 Episodes，全卷目录
          // 返回空列表，与直连语义一致）。
          final visible = chapters.where((c) => !c.isVolume).toList();
          // 漫画阅读器以 chapterId=Episode.id 回传图片请求，id 须为章节 URL。
          return episodesFromChapters(
            visible,
            isComic: source.type == SourceType.mangaSource,
          );
        case 'images':
          // 漫画图片：渲染后 HTML 直接按正文规则取图（含 WebView 过验证后
          // 的回灌），不再回落 resolve 触发重抓/重复验证。
          final imageChapterUrl = vars['chapterId'] ??
              vars['url'] ??
              vars['chapter'] ??
              vars['cid'] ??
              '';
          if (imageChapterUrl.isEmpty) return <String>[];
          // legado 的 Book/BookChapter 跨阶段存在：渲染回灌同样要带真实实体，
          // 否则 `book.*`、`chapter.variableMap/baseUrl/title` 在图片规则里
          // 退化成空壳（同一源直连漫画正常、过验证后取图失败）。
          final imageBookId = vars['id'] ?? '';
          final imageBook = (imageBookId.isEmpty
                  ? null
                  : (_bookInfoCache[imageBookId] ?? _seedFor(imageBookId))) ??
              XiaoshuoBook(bookUrl: '', name: '');
          final imageChapter = _chapterFor(imageBookId, imageChapterUrl) ??
              XiaoshuoBookChapter(
                bookUrl: imageBook.bookUrl,
                url: imageChapterUrl,
                title: vars['chapterTitle'] ?? '',
              );
          final imageBlocks = BookContent.analyzeContent(
            bookSource: bookSource,
            book: imageBook,
            bookChapter: imageChapter,
            baseUrl: imageChapterUrl,
            redirectUrl: imageChapterUrl,
            body: html,
            processTitle: false,
          );
          return imageUrlsFromBlocks(imageBlocks, baseUrl: imageChapterUrl);
        case 'content':
          // 正文：用 [BookContent] 解析渲染后 HTML（与 [WebBook.getContent] 同口径，
          // 声明式 ruleContent 而非脚本 override——书源渲染路径一致）。正文分页跟随
          // 在渲染路径下不做（WebView 取回的已是单页渲染结果），绝大多数章节单页。
          final chapterUrl = vars['url'] ?? vars['chapter'] ?? '';
          final contentBookId = vars['id'] ?? '';
          final cachedBook = contentBookId.isEmpty
              ? null
              : (_bookInfoCache[contentBookId] ?? _seedFor(contentBookId));
          final book = cachedBook ?? XiaoshuoBook(bookUrl: '', name: '');
          ShuyuanImageDecoder.rememberActiveBook(source.id, book);
          final chapter = _chapterFor(contentBookId, chapterUrl) ??
              XiaoshuoBookChapter(
                bookUrl: book.bookUrl,
                url: chapterUrl,
                title: vars['chapterTitle'] ?? '',
              );
          final isMediaSource = bookSource.bookSourceType == 1 ||
              bookSource.bookSourceType == 4;
          final blocks = BookContent.analyzeContent(
            bookSource: bookSource,
            book: book,
            bookChapter: chapter,
            baseUrl: chapterUrl,
            redirectUrl: chapterUrl,
            body: html,
            mediaSource: isMediaSource,
            // 整章后处理（subContent / title / replaceRegex / 缩进）统一交给
            // assembleChapter：与直连链路同一实现，渲染回灌不再丢附加正文。
            processTitle: false,
            deferChapterPostProcess: true,
          );
          final assembly = await BookContent.assembleChapter(
            bookSource: bookSource,
            book: book,
            bookChapter: chapter,
            firstBody: html,
            baseUrl: chapterUrl,
            redirectUrl: chapterUrl,
            blocks: blocks,
            mediaSource: isMediaSource,
          );
          if (assembly.blocks.isEmpty) {
            throw SourceResolveException(
              sourceId: source.id,
              apiName: 'content',
              message: '正文渲染后解析为空',
            );
          }
          return NovelContentResult(
            assembly.blocks,
            title: chapter.title.isEmpty ? null : chapter.title,
          );
        case 'video':
          // 视频/音频源播放直链：渲染后 HTML 取正文规则里的媒体 URL。
          final videoChapterUrl = vars['url'] ?? vars['chapter'] ?? '';
          final videoBookId = vars['id'] ?? '';
          final videoBook = (videoBookId.isEmpty
                  ? null
                  : (_bookInfoCache[videoBookId] ?? _seedFor(videoBookId))) ??
              XiaoshuoBook(bookUrl: '', name: '');
          final videoChapter =
              _chapterFor(videoBookId, videoChapterUrl) ??
                  XiaoshuoBookChapter(
                    bookUrl: videoBook.bookUrl,
                    url: videoChapterUrl,
                    title: vars['chapterTitle'] ?? '',
                  );
          final videoBlocks = BookContent.analyzeContent(
            bookSource: bookSource,
            book: videoBook,
            bookChapter: videoChapter,
            baseUrl: videoChapterUrl,
            redirectUrl: videoChapterUrl,
            body: html,
            mediaSource: true,
          );
          final renderedUrl = _normalizeMediaUrl(
            _firstMediaLine(videoBlocks
                    .whereType<NovelTextBlock>()
                    .map((b) => b.text)
                    .join('\n')) ??
                _extractMediaUrl(videoBlocks),
            videoChapterUrl,
          );
          if (renderedUrl == null || renderedUrl.isEmpty) {
            throw SourceResolveException(
              sourceId: source.id,
              apiName: 'video',
              message: '渲染后正文未解析到媒体直链',
            );
          }
          final renderedAnalyze = AnalyzeUrl(
            url: renderedUrl,
            baseUrl: bookSource.bookSourceUrl,
            source: bookSource,
          );
          // 音频源（bookSourceType=1）`subContent` 在正文规则里产出 LRC
          // （md3 AudioPlay 同源）；渲染回灌路径没有经过 WebBook.getContent，
          // 需在此补求值一次。视频源（type=4）不产出歌词，保持原行为。
          final String? lyric = bookSource.bookSourceType == 1
              ? await _resolveRenderedLyric(
                  bookSource: bookSource,
                  chapter: videoChapter,
                  book: videoBook,
                  body: html,
                  baseUrl: videoChapterUrl,
                )
              : null;
          return VideoResult(
            url: renderedAnalyze.url,
            headers: renderedAnalyze.resolveRequestHeaders(),
            lyric: lyric,
          );
        case 'webFiles':
          // 文件类书源：用渲染后 HTML 解析详情与下载地址列表（WebView 验证后
          // 回灌，不再回落 resolve 重抓）。
          final webFileId = vars['id'] ?? vars['detailUrl'] ?? '';
          if (webFileId.isEmpty) return const <WebFileItem>[];
          final webFileBook =
              _seedFor(webFileId) ?? XiaoshuoBook(bookUrl: webFileId, name: '');
          BookInfo.analyzeBookInfo(
            bookSource: bookSource,
            book: webFileBook,
            baseUrl: webFileId,
            redirectUrl: webFileId,
            body: html,
          );
          _rememberBookInfo(webFileBook);
          return _webFilesFromBook(source, bookSource, webFileBook);
        default:
          return resolve(source, apiName, vars: vars);
      }
    });
  }

  // ── 发现分类解析 ──
  /// 解析书源 exploreUrl 为分类列表（支持 `名称::URL` 多行 / JSON 数组 /
  /// `<js>` 动态生成），供在线浏览页生成分类 Tab。此前静态正则解析会跳过
  /// 含 `<js>` 的 exploreUrl，这类源一个分类 Tab 都没有。
  ///
  /// 动态分类脚本在 legado 里可直接 `java.ajax`（阻塞拿真实响应）。本实现
  /// 的同步沙箱做不到，走「占位符 + 宿主抓取 + 重放」：与搜索/目录同款
  /// [ShuyuanSourceContext.settleAjax]，脚本重跑时 `java.ajax` 命中缓存
  /// 直出真数据。未 resolve 的占位符分类（断网/请求失败）直接丢弃，避免
  /// 把 `__AJAX_1__` 当 URL 生成假 Tab。
  @override
  Future<List<CategoryEntry>> resolveExploreCategories(
    PluginConfig source,
  ) async {
    final shuyuanSource = ShuyuanAdapter.fromPluginConfig(source);
    if (shuyuanSource == null) return const <CategoryEntry>[];
    final bookSource = shuyuanSource.toBookSource();
    final exploreUrl = bookSource.exploreUrl;
    if (exploreUrl == null || exploreUrl.trim().isEmpty) {
      return const <CategoryEntry>[];
    }
    final infoKey = _exploreInfoKey(source, bookSource);
    final infoMap = await ShuyuanExploreInfoStore.load(infoKey);
    final beforeInfo = Map<String, String>.from(infoMap);
    // 静态声明（文本 / JSON）不需要 JS 运行时，直接同步解析。
    if (!_exploreNeedsJs(exploreUrl)) {
      try {
        return _toCategoryEntries(
            _webBook.getExploreCategories(bookSource, infoMap: infoMap));
      } finally {
        // legado InfoMap：分类脚本对 text/toggle/select 的写入随源持久化。
        // 首页 fallback 与完整选项栏必须共用同一份落盘策略，否则脚本改了
        // 状态下一轮又读到旧值。
        await _saveInfoIfChanged(infoKey, beforeInfo, infoMap);
      }
    }
    final ctx = await _contextFor(source);
    ctx.bindSource(bookSource);
    return ShuyuanSourceContext.run(ctx, () async {
      ctx.clearStageCaches();
      JsEngine.resetReplayCachesFor(source.id);
      var deadline = DateTime.now().add(_exploreCategoryBudget);
      ctx.deferredToasts.clear();
      ctx.deferFeedback = true;
      try {
        var entries = _toCategoryEntries(
            _webBook.getExploreCategories(bookSource, infoMap: infoMap));
        for (var pass = 0; pass < _maxReplayPasses; pass++) {
          if (!_hasPendingReplay(ctx)) break;
          if (!_replayAllowed(pass, deadline)) break;
          final settled =
              await _settleReplay(ctx, bookSource, source, deadline: deadline);
          deadline = deadline.add(settled.waited);
          if (settled.fetched == 0) break;
          entries = _toCategoryEntries(
              _webBook.getExploreCategories(bookSource, infoMap: infoMap));
        }
        return entries
            .where((e) =>
                !e.id.contains('__AJAX_') && !e.id.contains('__WEBVIEW_'))
            .toList(growable: false);
      } finally {
        ctx.flushDeferredToasts();
        await _saveInfoIfChanged(infoKey, beforeInfo, infoMap);
      }
    });
  }

  /// infoMap 有净变化时才落盘（legado `InfoMap.save` 只标脏，写盘发生在
  /// 显式 `saveNow()` 或流程成功结束）；无变化重复写会放大 IO。
  Future<void> _saveInfoIfChanged(
    String infoKey,
    Map<String, String> before,
    Map<String, String> after,
  ) async {
    if (before.length == after.length) {
      var same = true;
      for (final e in after.entries) {
        if (before[e.key] != e.value) {
          same = false;
          break;
        }
      }
      if (same) return;
    }
    await ShuyuanExploreInfoStore.save(infoKey, after);
  }

  /// 解析发现页完整选项栏（legado ExploreKind）：url/text/button/toggle/
  /// select 全部保留，toggle/select 的值从持久化 infoMap 恢复（缺省时写入
  /// kind.default 或 chars 首项），viewName 逐项求值。
  ///
  /// 动态 exploreUrl / viewName 可发 `java.ajax`，沿用与发现分类相同的
  /// 占位符重放：每轮抓取未满足请求后重跑，直到无新请求或预算耗尽。
  /// 成功结果按源持久缓存（legado ACache 等效）；[refresh] 强制重抓。
  ///
  /// 单飞：同一源并发调用只跑一次（legado 按 bookSourceUrl 加 Mutex、锁内
  /// 二次读缓存）；[refresh] 先等在飞请求结束再强制重抓，避免旧结果覆盖新值。
  static final Map<String, Future<ExploreKindsResult>> _exploreKindsInflight =
      <String, Future<ExploreKindsResult>>{};

  @override
  Future<ExploreKindsResult> resolveExploreKinds(
    PluginConfig source, {
    bool refresh = false,
  }) async {
    final key = source.id;
    if (refresh) {
      final inflight = _exploreKindsInflight[key];
      if (inflight != null) {
        try {
          await inflight;
        } catch (_) {}
      }
      return _resolveExploreKindsImpl(source, refresh: true);
    }
    final running = _exploreKindsInflight[key];
    if (running != null) return running;
    final future = _resolveExploreKindsImpl(source, refresh: false);
    _exploreKindsInflight[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_exploreKindsInflight[key], future)) {
        _exploreKindsInflight.remove(key);
      }
    }
  }

  Future<ExploreKindsResult> _resolveExploreKindsImpl(
    PluginConfig source, {
    required bool refresh,
  }) async {
    final shuyuanSource = ShuyuanAdapter.fromPluginConfig(source);
    if (shuyuanSource == null) return const ExploreKindsResult();
    final bookSource = shuyuanSource.toBookSource();
    final exploreUrl = bookSource.exploreUrl;
    if (exploreUrl == null || exploreUrl.trim().isEmpty) {
      return const ExploreKindsResult();
    }
    final infoKey = _exploreInfoKey(source, bookSource);
    final infoMap = await ShuyuanExploreInfoStore.load(infoKey);
    final beforeInfo = Map<String, String>.from(infoMap);
    // infoMap 的落盘时机对齐 legado `InfoMap`：只有流程成功且确有净变化时
    // 才写；失败/部分写入不落盘（旧实现在 finally 无条件 save，失败请求
    // 也会污染持久状态）。
    var infoCommitted = false;
    if (refresh) await ShuyuanExploreKindsStore.clear(infoKey);
    final cached = await ShuyuanExploreKindsStore.load(
      infoKey,
      exploreUrl: exploreUrl,
    );
    final ctx = await _contextFor(source);
    ctx.bindSource(bookSource);
    try {
      return await ShuyuanSourceContext.run(ctx, () async {
        ctx.clearStageCaches();
        if (cached != null) {
          final items =
              await _materializeKinds(source, bookSource, cached, infoMap);
          infoCommitted = true;
          return ExploreKindsResult(items: items, infoMap: infoMap);
        }
        JsEngine.resetReplayCachesFor(source.id);
        var deadline = DateTime.now().add(_exploreCategoryBudget);
        ({ExploreKindsResult result, List<ExploreKind> kinds})? built;
        try {
          for (var pass = 0; pass < _maxReplayPasses; pass++) {
            ctx.ajaxPending.clear();
            ctx.webviewPending.clear();
            ctx.deferFeedback = true;
            ctx.deferredToasts.clear();
            built = await _buildExploreKinds(source, bookSource, infoMap);
            // 脚本报错可能只是占位符（java.ajax 首轮）引起的暂时失败：
            // 仍有待抓取请求时继续重放，settle 后再判定真实错误。
            if (!_hasPendingReplay(ctx)) {
              if (built.result.error == null) {
                await ShuyuanExploreKindsStore.save(
                    infoKey, exploreUrl, built.kinds);
                infoCommitted = true;
              }
              return built.result;
            }
            if (!_replayAllowed(pass, deadline)) return built.result;
            final settled = await _settleReplay(ctx, bookSource, source,
                deadline: deadline);
            deadline = deadline.add(settled.waited);
            // 抓取失败/无进展：保留错误态，不写缓存（下次打开仍会重试）。
            if (settled.fetched == 0) return built.result;
          }
          return built?.result ?? ExploreKindsResult(infoMap: infoMap);
        } finally {
          ctx.flushDeferredToasts();
        }
      });
    } on Object catch (e) {
      return ExploreKindsResult(infoMap: infoMap, error: '$e');
    } finally {
      // toggle/select 默认值与 viewName/action 的 infoMap 变化落盘。
      if (infoCommitted) {
        await _saveInfoIfChanged(infoKey, beforeInfo, infoMap);
      }
    }
  }

  Future<({ExploreKindsResult result, List<ExploreKind> kinds})>
      _buildExploreKinds(
    PluginConfig source,
    XiaoshuoBookSource bookSource,
    Map<String, String> infoMap,
  ) async {
    List<ExploreKind> kinds;
    String? scriptError;
    try {
      kinds = _webBook.getExploreKinds(
        bookSource,
        infoMap: infoMap,
        onScriptError: (e) => scriptError ??= e,
      );
    } on Object catch (e) {
      return (
        result: ExploreKindsResult(infoMap: infoMap, error: '$e'),
        kinds: const <ExploreKind>[],
      );
    }
    if (kinds.isEmpty && scriptError != null) {
      // 对齐 legado `exploreKinds()`：脚本异常生成可见错误项，而不是
      // 伪装成「该源没有发现页」。
      return (
        result: ExploreKindsResult(infoMap: infoMap, error: scriptError),
        kinds: const <ExploreKind>[],
      );
    }
    final items = await _materializeKinds(source, bookSource, kinds, infoMap);
    return (
      result: ExploreKindsResult(items: items, infoMap: infoMap),
      kinds: kinds,
    );
  }

  /// 把解析出的 kinds 变成可渲染条目：补齐 toggle/select 默认值并求值
  /// viewName（缓存命中与网络解析共用）。
  Future<List<ExploreKindItem>> _materializeKinds(
    PluginConfig source,
    XiaoshuoBookSource bookSource,
    List<ExploreKind> kinds,
    Map<String, String> infoMap,
  ) async {
    final items = <ExploreKindItem>[];
    for (final kind in kinds) {
      if (kind.title.isEmpty && !kind.isBrowsable) continue;
      final value = _buildKindValue(kind, infoMap);
      var displayName = kind.title;
      final viewName = kind.viewName?.trim() ?? '';
      if (viewName.isNotEmpty) {
        final resolved = await _resolveKindViewName(source, viewName, infoMap,
            baseUrl: bookSource.bookSourceUrl);
        if (resolved.isNotEmpty) displayName = resolved;
      }
      if (displayName.isEmpty) displayName = kind.url ?? '';
      items.add(ExploreKindItem(
        kind: kind,
        displayName: displayName,
        value: value,
      ));
    }
    return items;
  }

  /// text 取 infoMap 已有值；toggle/select 缺省时写入并返回默认值。
  String _buildKindValue(ExploreKind kind, Map<String, String> infoMap) {
    switch (kind.recognizedType) {
      case ExploreKindType.text:
        return infoMap[kind.title] ?? '';
      case ExploreKindType.toggle:
      case ExploreKindType.select:
        final existing = infoMap[kind.title];
        if (existing != null && existing.isNotEmpty) return existing;
        final options = _kindOptions(kind);
        final fallback = kind.defaultValue?.trim() ?? '';
        final value = fallback.isNotEmpty ? fallback : options.first;
        infoMap[kind.title] = value;
        return value;
      default:
        return '';
    }
  }

  /// toggle/select 的可选值（legado：chars 缺失时用占位文案，不让 UI 崩）。
  static List<String> _kindOptions(ExploreKind kind) {
    if (kind.chars.isNotEmpty) return kind.chars;
    return const <String>['chars', 'is null'];
  }

  /// infoMap 的 Java Map 兼容面（legado 的 infoMap 是 InfoMap/MutableMap）：
  /// viewName/action 脚本会调 get/put/remove/containsKey/save。方法以
  /// 非枚举属性挂载，`JSON.stringify(infoMap)` 仍只输出数据键。
  static const String _infoMapCompatJs = '  '
      'if (infoMap && typeof infoMap === "object") {\n'
      '    var __def = function (n, f) {\n'
      '      try { Object.defineProperty(infoMap, n, {value: f,\n'
      '        enumerable: false, configurable: true, writable: true});'
      ' } catch (e) {}\n'
      '    };\n'
      '    if (typeof infoMap.get !== "function") __def("get", function (k) {\n'
      '      var v = infoMap[String(k)]; return v == null ? null : v; });\n'
      '    if (typeof infoMap.put !== "function") __def("put", function (k, v) {\n'
      '      var key = String(k); var prev = infoMap[key];\n'
      '      infoMap[key] = v == null ? "" : String(v);\n'
      '      return prev == null ? null : prev; });\n'
      '    if (typeof infoMap.set !== "function") __def("set", function (k, v) {\n'
      '      return infoMap.put(k, v); });\n'
      '    if (typeof infoMap.remove !== "function")'
      ' __def("remove", function (k) {\n'
      '      var key = String(k); var prev = infoMap[key]; delete infoMap[key];\n'
      '      return prev == null ? null : prev; });\n'
      '    if (typeof infoMap.containsKey !== "function")'
      ' __def("containsKey", function (k) {\n'
      '      return Object.prototype.hasOwnProperty.call(infoMap, String(k));'
      ' });\n'
      '    if (typeof infoMap.save !== "function")'
      ' __def("save", function () { return null; });\n'
      '    if (typeof infoMap.saveNow !== "function")'
      ' __def("saveNow", function () { return null; });\n'
      '  }\n';

  /// viewName：`'字面量'`（长度 3–19）直接取内容，其余按 JS 求值
  /// （legado ExploreKindUiUseCase.ResolveDisplayName → BaseSource.evalJS，
  /// 脚本可读 `infoMap` 与 `baseUrl`=书源 URL）。
  Future<String> _resolveKindViewName(
    PluginConfig source,
    String viewName,
    Map<String, String> infoMap, {
    required String baseUrl,
  }) async {
    final literal = _literalViewName(viewName);
    if (literal != null) return literal;
    final engine = JsEngine.forSource(source.id);
    // legado 的 viewName 与 action 共用同一个 live InfoMap；NexHub 旧实现把
    // 副本传进脚本，脚本里的 `infoMap.put(...)` 副作用直接丢失。这里同时
    // 回传求值结果与脚本改过的 map，由宿主合并回 [infoMap]。
    final wrapped = '(function () {\n$_infoMapCompatJs'
        '  var __r = eval(${jsonEncode(viewName)});\n'
        '  return JSON.stringify({\n'
        '    r: __r == null ? "" : String(__r),\n'
        '    m: infoMap\n'
        '  });\n'
        '})()';
    final out = engine.eval(
      wrapped,
      bindings: <String, dynamic>{
        'infoMap': Map<String, String>.from(infoMap),
        'baseUrl': baseUrl,
      },
    );
    engine.takeJavaVars();
    try {
      final decoded = jsonDecode(out);
      if (decoded is Map) {
        final m = decoded['m'];
        if (m is Map) {
          m.forEach((k, v) {
            if (v != null) infoMap[k.toString()] = v.toString();
          });
        }
        return '${decoded['r'] ?? ''}';
      }
    } catch (_) {}
    return out;
  }

  static String? _literalViewName(String viewName) {
    if (viewName.length < 3 || viewName.length > 19) return null;
    if (viewName.startsWith("'") && viewName.endsWith("'")) {
      return viewName.substring(1, viewName.length - 1);
    }
    return null;
  }

  /// 持久化单个选项值（text 输入 / toggle、select 选择）。
  @override
  Future<void> setExploreKindValue(
    PluginConfig source,
    String title,
    String value,
  ) async {
    final shuyuanSource = ShuyuanAdapter.fromPluginConfig(source);
    if (shuyuanSource == null) return;
    final bookSource = shuyuanSource.toBookSource();
    final infoKey = _exploreInfoKey(source, bookSource);
    final infoMap = await ShuyuanExploreInfoStore.load(infoKey);
    infoMap[title] = value;
    await ShuyuanExploreInfoStore.save(infoKey, infoMap);
  }

  /// 执行选项 action 脚本。
  ///
  /// 与登录脚本同款 mini-settle：`java.ajax`/`java.webView` 先记占位符，
  /// 宿主抓取后重放；脚本里的 `java.startBrowser/openUrl/refreshExplore/
  /// copyText` 经 syOp 排空回传给 UI 执行。action 对 infoMap 的修改
  /// （`infoMap.put(...)` / 下标赋值）在执行后落盘。
  @override
  Future<ExploreKindActionResult> executeExploreKindAction(
    PluginConfig source,
    ExploreKind kind,
  ) async {
    final action = kind.action?.trim() ?? '';
    if (action.isEmpty) return const ExploreKindActionResult();
    final shuyuanSource = ShuyuanAdapter.fromPluginConfig(source);
    if (shuyuanSource == null) return const ExploreKindActionResult();
    final bookSource = shuyuanSource.toBookSource();
    final infoKey = _exploreInfoKey(source, bookSource);
    final infoMap = await ShuyuanExploreInfoStore.load(infoKey);
    final ctx = await _contextFor(source);
    ctx.bindSource(bookSource);
    final engine = JsEngine.forSource(source.id);
    try {
      return await ShuyuanSourceContext.run(ctx, () async {
        ctx.clearStageCaches();
        engine.resetReplayCaches();
        var deadline = DateTime.now().add(_exploreCategoryBudget);
        try {
          for (var pass = 0; pass < _maxReplayPasses; pass++) {
            ctx.ajaxPending.clear();
            ctx.webviewPending.clear();
            ctx.kindBrowserOpens.clear();
            ctx.kindRefreshRequested = false;
            ctx.copiedTexts.clear();
            ctx.deferFeedback = true;
            ctx.deferredToasts.clear();
            _runKindAction(engine, action, infoMap, bookSource.bookSourceUrl);
            _syncInfoMapFromJs(engine, infoMap);
            if (!_hasPendingReplay(ctx)) break;
            if (!_replayAllowed(pass, deadline)) break;
            final settled = await _settleReplay(ctx, bookSource, source,
                deadline: deadline);
            deadline = deadline.add(settled.waited);
            if (settled.fetched == 0) break;
          }
          return ExploreKindActionResult(
            openRequests: <ExploreKindOpenRequest>[
              for (final open in ctx.kindBrowserOpens)
                if ((open['url'] ?? '').isNotEmpty)
                  ExploreKindOpenRequest(
                    url: open['url']!,
                    title: open['title'] ?? '',
                  ),
            ],
            refreshKinds: ctx.kindRefreshRequested,
            copiedTexts: List<String>.from(ctx.copiedTexts),
          );
        } finally {
          ctx.flushDeferredToasts();
        }
      });
    } finally {
      engine.takeJavaVars();
      await ShuyuanExploreInfoStore.save(infoKey, infoMap);
    }
  }

  /// 执行 action：先给 infoMap 补 Map.put/get/remove/containsKey 兼容方法
  /// （legado 的 infoMap 是 HashMap，脚本常用 `.put`），再 eval 脚本体。
  /// `baseUrl` 与 legado `BaseSource.evalJS` 一致绑定为书源 URL。
  void _runKindAction(
    JsEngine engine,
    String action,
    Map<String, String> infoMap,
    String baseUrl,
  ) {
    final wrapped = '(function () {\n$_infoMapCompatJs'
        '  return eval(${jsonEncode(action)});\n'
        '})()';
    engine.eval(wrapped, bindings: <String, dynamic>{
      'infoMap': Map<String, String>.from(infoMap),
      'baseUrl': baseUrl,
    });
  }

  void _syncInfoMapFromJs(
    JsEngine engine,
    Map<String, String> infoMap,
  ) {
    try {
      final raw = engine.eval('JSON.stringify(infoMap)');
      engine.takeJavaVars();
      if (raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      infoMap
        ..clear()
        ..addAll(<String, String>{
          for (final e in decoded.entries)
            e.key.toString(): e.value?.toString() ?? '',
        });
    } catch (_) {}
  }

  /// infoMap 的持久化键：优先书源 URL（与 legado `infoMap_<key>` 对齐），
  /// 未声明 URL 时退回内部源 id。
  static String _exploreInfoKey(
    PluginConfig source,
    XiaoshuoBookSource bookSource,
  ) {
    final url = bookSource.bookSourceUrl.trim();
    return url.isNotEmpty ? url : source.id;
  }

  /// exploreUrl 是否含需要 JS 求值的片段（整串或分段 `@js:`/`<js>`）。
  /// 前缀忽略大小写（legado `startsWith(..., true)`）。
  static bool _exploreNeedsJs(String exploreUrl) {
    final trimmed = exploreUrl.trim();
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('@js:') || lower.startsWith('<js>')) return true;
    for (final line in trimmed.split(RegExp(r'&&|\n'))) {
      final t = line.trim().toLowerCase();
      if (t.startsWith('@js:') || t.startsWith('<js>')) return true;
    }
    return false;
  }

  List<CategoryEntry> _toCategoryEntries(List<ExploreCategory> entries) {
    return entries
        .map((e) => CategoryEntry(
              id: e.url,
              title: e.name.isNotEmpty ? e.name : e.url,
            ))
        .toList();
  }

  // ── 搜索 ──
  Future<List<MediaItem>> _handleSearch(
    PluginConfig source,
    XiaoshuoBookSource bookSource,
    Map<String, String> vars,
  ) async {
    final keyword = vars['keyword'] ?? vars['key'] ?? vars['title'] ?? '';
    if (keyword.isEmpty) return <MediaItem>[];

    final page = int.tryParse(vars['page'] ?? '1') ?? 1;
    final results = await _webBook.searchBook(
      source: bookSource,
      key: keyword,
      page: page,
    );
    return _mapAndSeedSearchBooks(results, source);
  }

  // ── 发现：按分类 URL 抓取 ──
  Future<List<MediaItem>> _handleExplore(
    PluginConfig source,
    XiaoshuoBookSource bookSource,
    Map<String, String> vars,
  ) async {
    // legado ExploreBooksUseCase（审计 M18）：首页模块 args 以
    // setTemporaryVariable 进入发现请求——`source.getVariable()` 优先读到
    // args，请求结束后丢弃、不写持久源变量。NexHub 的首页板块 params
    // （除 page/__route/category 等路由保留键外）桥接为同一层临时变量。
    const reserved = {'page', '__route', 'category'};
    final moduleArgs = <String, String>{
      for (final e in vars.entries)
        if (!reserved.contains(e.key) && e.value.isNotEmpty) e.key: e.value,
    };
    final ctx = ShuyuanSourceContext.current;
    if (ctx != null && moduleArgs.isNotEmpty) {
      ctx.beginTemporaryVars(moduleArgs);
    }
    try {
      return await _handleExploreInner(source, bookSource, vars);
    } finally {
      if (ctx != null && moduleArgs.isNotEmpty) {
        ctx.endTemporaryVars();
      }
    }
  }

  Future<List<MediaItem>> _handleExploreInner(
    PluginConfig source,
    XiaoshuoBookSource bookSource,
    Map<String, String> vars,
  ) async {
    final page = int.tryParse(vars['page'] ?? '1') ?? 1;

    // 筛选驱动的分类页：URL 结构由源声明（`filters.urlTemplate`），引擎只做
    // 「占位符替换 + 空值省段」，不假设任何站点的路径形状。
    //
    // 关键：绝不能给未选维度塞默认值（否则会强制「连载 / 30万字以上 / 最新更新」
    // 等，把用户想看的「全部」也限死）。未选维度由 [applyFilterTemplate] 直接
    // 省略对应路径段；用户显式选「全部」(`all`/空) 也等同省略。
    final filterTemplate = source.filters?.urlTemplate.trim() ?? '';
    if (filterTemplate.isNotEmpty) {
      final filterVars = <String, String>{
        for (final entry in vars.entries)
          entry.key: entry.value.trim() == 'all' ? '' : entry.value,
      };
      final filterKeys = _filterParamKeys(source.filters);
      final hasSelection =
          filterKeys.any((k) => (filterVars[k] ?? '').isNotEmpty);
      if (hasSelection) {
        final filterUrl =
            applyFilterTemplate(filterTemplate, filterVars);
        if (filterUrl.isNotEmpty) {
          final books = await _webBook.exploreCategory(
            source: bookSource,
            categoryUrl: filterUrl,
            page: page,
            // 筛选地址是运行期拼出的，没有书源 kind.url 的页码规则语义：
            // 地址自身不带页码规则时允许补 page 参数翻页。
            usePageParamFallback: true,
          );
          return _mapAndSeedBooks(books, source);
        }
      }
    }

    final categoryUrl = vars['category'];

    if (categoryUrl != null && categoryUrl.isNotEmpty) {
      final books = await _webBook.exploreCategory(
        source: bookSource,
        categoryUrl: categoryUrl,
        page: page,
      );
      return _mapAndSeedBooks(books, source);
    }

    // 没指定分类时，走全量发现页。书源未配置 exploreUrl（纯搜索源，无发现页）
    // 时优雅返回空列表，避免把「书源未配置 exploreUrl」当作错误刷红屏/
    // 空态误导用户（真实网络错误仍会正常抛出由上层重试）。
    if (bookSource.exploreUrl == null || bookSource.exploreUrl!.isEmpty) {
      return <MediaItem>[];
    }

    // 首页 latest 板块（未指定分类）：legado 的发现页一次只加载一个分类，
    // NexHub 无分类入口时取首个可浏览分类。首个分类失效（断链/拦截）或为空时
    // 继续尝试后续分类，避免首页直接呈现空列表；尝试数有上限，不做全量串行
    // 抓取（同 host 限流下可达数十秒）。拿到首个非空结果即停。
    //
    // 分类列表走 [resolveExploreCategories]（而不是直接调引擎）：动态
    // exploreUrl 需要持久化 infoMap，并在脚本改动后回写——旧实现在这里传
    // 空 Map 且不保存，分类脚本写入的 text/toggle 状态直接丢失。
    final categories = await resolveExploreCategories(source);
    if (categories.isEmpty) return <MediaItem>[];
    Object? firstError;
    for (final category in categories.take(_exploreHomeFallbackLimit)) {
      try {
        final books = await _webBook.exploreCategory(
          source: bookSource,
          categoryUrl: category.id,
          page: page,
        );
        if (books.isNotEmpty) return _mapAndSeedBooks(books, source);
      } on Object catch (e) {
        firstError ??= e;
      }
    }
    // 全部尝试都失败时保留首个错误（验证流程/网络诊断依赖原始异常类型）。
    if (firstError != null) throw firstError;
    return <MediaItem>[];
  }

  /// 源声明的筛选参数名（`filters.groups[].param` 去重）。
  ///
  /// 用于判断「用户是否真的选了某个筛选维度」：只看声明过的参数，
  /// 避免 `page`/`category` 这类内部变量把模板误判为有筛选。
  static Set<String> _filterParamKeys(SourceFilterConfig? filters) {
    if (filters == null) return const <String>{};
    final keys = <String>{};
    for (final g in filters.groups) {
      if (g.param.isNotEmpty) keys.add(g.param);
    }
    for (final list in filters.byCategory.values) {
      for (final g in list) {
        if (g.param.isNotEmpty) keys.add(g.param);
      }
    }
    return keys;
  }

  // ── latest：等同 explore（发现页） ──
  Future<List<MediaItem>> _handleLatest(
    PluginConfig source,
    XiaoshuoBookSource bookSource,
    Map<String, String> vars,
  ) async {
    return _handleExplore(source, bookSource, vars);
  }

  // ── 详情 ──
  Future<MediaItem> _handleDetail(
    PluginConfig source,
    XiaoshuoBookSource bookSource,
    Map<String, String> vars,
  ) async {
    final id = vars['id'] ?? vars['detailUrl'] ?? '';
    if (id.isEmpty) {
      throw ArgumentError('detail requires vars["id"]');
    }
    final book = await _webBook.getBookInfo(
      source: bookSource,
      bookUrl: id,
      seedBook: _seedFor(id),
    );
    _rememberBookInfo(book);
    return _xiaoshuoBookToMediaItem(book, source);
  }

  /// 关联书籍（legado RelatedBooks）：按 `ruleBookInfo.relatedBooks` 声明的
  /// 模块并行探索并过滤当前书。详情页「猜你喜欢」只有单列表形态，此处
  /// 扁平化返回；模块 key/title 的展示形态待 UI 扩展。
  Future<List<MediaItem>> _handleRelated(
    PluginConfig source,
    XiaoshuoBookSource bookSource,
    Map<String, String> vars,
  ) async {
    final id = vars['id'] ?? vars['detailUrl'] ?? '';
    if (id.isEmpty) {
      throw ArgumentError('related requires vars["id"]');
    }
    final book = _bookInfoCache[id] ??
        _seedFor(id) ??
        XiaoshuoBook(bookUrl: id, name: '');
    final modules = await RelatedBooks.load(book: book, source: bookSource);
    return <MediaItem>[
      for (final module in modules)
        ..._mapAndSeedBooks(module.books, source),
    ];
  }

  // ── 章节列表 ──
  Future<List<Episode>> _handleChapterList(
    PluginConfig source,
    XiaoshuoBookSource bookSource,
    Map<String, String> vars, {
    void Function(List<dynamic>)? onProgress,
  }) async {
    final id = vars['id'] ?? vars['detailUrl'] ?? '';
    if (id.isEmpty) {
      throw ArgumentError('chapters requires vars["id"]');
    }
    // getChapterList 依赖 XiaoshuoBook.tocUrl 定位目录（legado 书对象在详情/
    // 加入书架时即已持有）。详情阶段缓存命中则直接用；未命中且源声明了
    // ruleBookInfo.tocUrl（目录是独立接口，如宜搜/百度）时先解析一次详情，
    // 否则目录请求会落到详情页 URL，章节恒为空。tocUrl 为空/详情失败时退回
    // 仅 bookUrl（getChapterList 内部按 bookUrl 解析目录，历史行为）。
    var book = _bookInfoCache[id];
    if (book == null &&
        (bookSource.ruleBookInfo?.tocUrl ?? '').trim().isNotEmpty) {
      try {
        book = await _webBook.getBookInfo(
          source: bookSource,
          bookUrl: id,
          seedBook: _seedFor(id),
        );
        _rememberBookInfo(book);
      } on Object {
        book = null;
      }
    }
    book ??= _seedFor(id) ?? XiaoshuoBook(bookUrl: id, name: '');
    final chapters = await _webBook.getChapterList(
      source: bookSource,
      book: book,
      // 目录入口等价 legado TocViewModel/ReadBookLoadDelegate：更新目录前
      // 执行一次 preUpdateJs。
      runPerJs: true,
      // 渐进批次：逐页把章节转为 Episode 后回传上层（首屏快显 + 后台续抓）。
      // 卷条目（isVolume）没有可读 URL（仅占位符），列表层无卷分隔形态，
      // 作为 Episode 会变成点不开的「章节」并挤占首章，故整体跳过。
      onBatch: (batch) {
        final playable = batch.where((c) => !c.isVolume);
        onProgress?.call(episodesFromChapters(
          playable.toList(),
          isComic: source.type == SourceType.mangaSource,
        ));
      },
    );
    // 正文阶段按章节 URL 复用目录对象（index / variableMap 跨阶段贯通）。
    _rememberChapters(id, chapters);
    return episodesFromChapters(
      chapters.where((c) => !c.isVolume).toList(),
      isComic: source.type == SourceType.mangaSource,
    );
  }

  /// 章节 → Episode 映射。漫画模块：阅读器以 chapterId=Episode.id 回传
  /// fetchImages，id 须存章节 URL（小说模块 id 为序号、URL 走 url 字段）。
  @visibleForTesting
  static List<Episode> episodesFromChapters(
    List<XiaoshuoBookChapter> chapters, {
    required bool isComic,
  }) {
    return [
      for (final c in chapters)
        Episode(
          id: isComic ? c.url : '${c.index}',
          // 展示形态：标题里的换行不带进目录/阅读器（模型保留原始 title）。
          title: c.getDisplayTitle(),
          url: c.url,
          isVip: c.isVip,
          isPay: c.isPay,
        ),
    ];
  }

  /// 漫画 'images' 适配：复用小说正文管线（img 内容 → 插图块），收集
  /// 图片 URL；纯 URL 文本行兜底（URL 列表形态的漫画源）。
  Future<List<String>> _handleComicImages(
    PluginConfig source,
    XiaoshuoBookSource bookSource,
    Map<String, String> vars,
  ) async {
    final chapterUrl = vars['chapterId'] ??
        vars['url'] ??
        vars['chapter'] ??
        vars['cid'] ??
        '';
    if (chapterUrl.isEmpty) return <String>[];
    final bookId = vars['id'] ?? '';
    final cachedChapter = _chapterFor(bookId, chapterUrl);
    final nextChapterUrl = _resolveNextChapterUrl(
      vars['nextChapterUrl'] ?? '',
      bookId,
      cachedChapter,
    );
    final host = Uri.tryParse(chapterUrl)?.host ?? '';
    final watch = Stopwatch()..start();
    AppLog.instance.i('[漫画取图] 开始 源=${bookSource.bookSourceName} '
        '主机=$host');
    try {
      final result = await _webBook.getContent(
        source: bookSource,
        chapterUrl: chapterUrl,
        originalBook: bookId.isEmpty
            ? null
            : (_bookInfoCache[bookId] ?? _seedFor(bookId)),
        bookChapter: cachedChapter,
        nextChapterUrl: nextChapterUrl.isEmpty ? null : nextChapterUrl,
      );
      final urls = imageUrlsFromBlocks(result.blocks, baseUrl: chapterUrl);
      AppLog.instance.i('[漫画取图] 完成 源=${bookSource.bookSourceName} '
          '块=${result.blocks.length} 图=${urls.length} '
          '耗时=${watch.elapsedMilliseconds}ms');
      return urls;
    } on Object catch (e) {
      AppLog.instance.w('[漫画取图] 失败 源=${bookSource.bookSourceName} '
          '耗时=${watch.elapsedMilliseconds}ms: $e');
      rethrow;
    }
  }

  /// 从图文块收集图片 URL：插图块直取；纯文本兜底支持整段 URL 列表
  /// （换行/`&&`/JSON 数组/引号逗号分隔），相对路径按 [baseUrl] 绝对化。
  @visibleForTesting
  static List<String> imageUrlsFromBlocks(
    List<NovelBlock> blocks, {
    String? baseUrl,
  }) {
    final urls = <String>[];
    final seen = <String>{};
    void add(String url) {
      final trimmed = url.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) return;
      urls.add(trimmed);
    }

    for (final b in blocks) {
      if (b is NovelImageBlock && b.url.trim().isNotEmpty) {
        add(b.url);
      }
    }
    if (urls.isNotEmpty) return urls;

    final dataUriPattern =
        RegExp(r'data:image/[a-zA-Z0-9.+_-]+(?:;[a-zA-Z0-9=+_-]+)*,'
            r'[A-Za-z0-9+/=%]+');
    final relativeImagePattern = RegExp(
      r'\.(?:jpe?g|png|webp|gif|bmp|avif|svg)(?:[?#].*)?$',
      caseSensitive: false,
    );
    final hasBase = baseUrl != null && baseUrl.trim().isNotEmpty;

    for (final b in blocks) {
      if (b is! NovelTextBlock) continue;
      var text = AnalyzeRule.unescapeHtml(b.text);
      // data:image 的 payload 可能含逗号/分号，先抽出占位，防被分隔符切碎。
      final dataUris = <String>[];
      text = text.replaceAllMapped(dataUriPattern, (m) {
        dataUris.add(m.group(0)!);
        return '__DATA_URI_${dataUris.length - 1}__';
      });
      text = text.replaceAll('&&', '\n');
      for (final rawToken in text.split(
        RegExp('[\\s,;，；"\'\u201c\u201d\\[\\](){}<>]+'),
      )) {
        var token = rawToken.trim();
        if (token.isEmpty) continue;
        final dataRef = RegExp(r'^__DATA_URI_(\d+)__$').firstMatch(token);
        if (dataRef != null) {
          add(dataUris[int.parse(dataRef.group(1)!)]);
          continue;
        }
        if (token.startsWith('data:image')) {
          add(token);
        } else if (token.startsWith('http://') ||
            token.startsWith('https://')) {
          add(token);
        } else if (token.startsWith('//') ||
            token.startsWith('/') ||
            relativeImagePattern.hasMatch(token)) {
          if (!hasBase) continue;
          if (token.startsWith('javascript:') || token.startsWith('about:')) {
            continue;
          }
          add(AnalyzeRule.absoluteUrl(baseUrl, token));
        }
      }
    }
    return urls;
  }

  // ── 正文 ──
  Future<NovelContentResult> _handleContent(
    PluginConfig source,
    XiaoshuoBookSource bookSource,
    Map<String, String> vars,
  ) async {
    final chapterUrl = vars['url'] ?? vars['chapter'] ?? '';
    if (chapterUrl.isEmpty) {
      throw ArgumentError('content requires vars["url"]');
    }
    // 目录章节名：标题规则的图片尾巴剥离为空时回落到它（legado 用书对象里
    // 的 BookChapter.title，NexHub 由调用方经 vars 传入）。
    final chapterTitle = vars['chapterTitle'] ?? '';
    // legado 的 Book/BookChapter 实体跨阶段存在：正文规则里的 book.* 与
    // chapter.index/variableMap 应延续目录/详情阶段的值。这里按 id 取回
    // 缓存的书籍与章节对象；未命中（如进程重启后的本地目录）退回裸壳。
    final bookId = vars['id'] ?? '';
    final cachedBook = bookId.isEmpty
        ? null
        : (_bookInfoCache[bookId] ?? _seedFor(bookId));
    final cachedChapter = _chapterFor(bookId, chapterUrl);
    // 记下本章书目：展示期图片解码（ruleContent.imageDecode）的 `book`
    // 绑定取这份快照（旧实现恒 null，脚本按 book.* 分支的解密全部走错）。
    ShuyuanImageDecoder.rememberActiveBook(source.id, cachedBook);
    final nextChapterUrl = _resolveNextChapterUrl(
      vars['nextChapterUrl'] ?? '',
      bookId,
      cachedChapter,
    );
    final result = await _webBook.getContent(
      source: bookSource,
      chapterUrl: chapterUrl,
      originalBook: cachedBook,
      bookChapter: cachedChapter,
      nextChapterUrl: nextChapterUrl.isEmpty ? null : nextChapterUrl,
      chapterTitle: chapterTitle.isEmpty ? null : chapterTitle,
    );
    if (result.error != null && result.blocks.isEmpty) {
      throw SourceResolveException(
        sourceId: source.id,
        apiName: 'content',
        message: result.error ?? 'resolve error',
      );
    }
    // 音频/视频源（legado bookSourceType=1/4）：正文规则提取的媒体直链
    // 包装为媒体块（阅读器渲染播放卡片拉起播放器）；legado 对音/视频
    // 不做 htmlFormat，直链即正文。
    final srcTypeRaw = (source.selectors?['xiaoshuo']
        as Map<String, dynamic>?)?['bookSourceType'];
    final srcType =
        srcTypeRaw is int ? srcTypeRaw : int.tryParse('$srcTypeRaw') ?? 0;
    if (srcType == 1 || srcType == 4) {
      final kind = srcType == 1 ? 'audio' : 'video';
      final mediaUrl = _normalizeMediaUrl(
        _firstMediaLine(result.content.trim()) ??
            _extractMediaUrl(result.blocks),
        chapterUrl,
      );
      return NovelContentResult(
        <NovelBlock>[NovelMediaBlock(mediaUrl ?? '', kind: kind)],
        title: result.title,
      );
    }
    // 图文块列表（文本段 + 插图），保留解析层给出的原始顺序，
    // 供阅读器图文混排显示。
    return NovelContentResult(result.blocks, title: result.title);
  }

  // ── 通用脚本动作 ──

  /// 执行源内嵌脚本（正文里 `<img src="url,{click:...}">` 的点击动作）。
  ///
  /// vars：`script`（JS 源码）、`result`（绑定给脚本的图片地址）。
  /// 脚本里的宿主动作（`java.showBrowser` / `startBrowser` / `open`）由
  /// [settleShuyuanInteractive] 落地——与发现页/登录脚本同一条通道。
  Future<bool> _handleScriptAction(
    PluginConfig source,
    XiaoshuoBookSource bookSource,
    Map<String, String> vars,
  ) async {
    final script = (vars['script'] ?? '').trim();
    if (script.isEmpty) return false;
    try {
      final engine = JsEngine.forSource(source.id);
      engine.eval(script, bindings: <String, dynamic>{
        'result': vars['result'] ?? '',
      });
    } catch (e) {
      AppLog.instance.w('[书源动作] 内嵌脚本执行失败: $e');
      return false;
    }
    final ctx = ShuyuanSourceContext.current;
    if (ctx != null) {
      // 排空宿主 UI 动作（浏览器/验证码）；动作本身失败不影响脚本已执行的事实。
      await settleShuyuanInteractive(
        ctx,
        bookSource,
        pluginSource: source,
        openBrowsers: true,
      );
    }
    return true;
  }

  // ── 段评 ──

  /// 段评列表（`ruleReview.reviewUrl`）。
  ///
  /// vars：`id`（书 URL）、`url`/`chapter`（章节 URL）、`chapterTitle`、
  /// `page`（段评分页，缺省 1）。书籍/章节对象沿用详情/目录阶段的缓存，
  /// 规则里的 `book.*`、`chapter.*` 与正文同一口径。
  Future<List<SourceReview>> _handleReviews(
    XiaoshuoBookSource bookSource,
    Map<String, String> vars,
  ) async {
    final chapterUrl = vars['url'] ?? vars['chapter'] ?? '';
    final bookId = vars['id'] ?? '';
    final book =
        (bookId.isEmpty ? null : (_bookInfoCache[bookId] ?? _seedFor(bookId))) ??
            XiaoshuoBook(bookUrl: bookId, name: '');
    final chapter = _chapterFor(bookId, chapterUrl) ??
        (chapterUrl.isEmpty
            ? null
            : XiaoshuoBookChapter(
                bookUrl: book.bookUrl,
                url: chapterUrl,
                title: vars['chapterTitle'] ?? '',
              ));
    final page = int.tryParse(vars['page'] ?? '') ?? 1;
    return BookReview.fetchReviews(
      bookSource: bookSource,
      book: book,
      chapter: chapter,
      baseUrl: chapterUrl.isEmpty ? book.tocUrl ?? book.bookUrl : chapterUrl,
      page: page,
      // 段落锚点：面板从某一段打开时把段号绑给 `{{paragraph}}`。
      paragraph: int.tryParse(vars['paragraph'] ?? ''),
    );
  }

  /// 某条段评的回复列表（`ruleReview.reviewQuoteUrl`）。
  /// vars 额外携带 `review`（正文）与 `reviewContext`（条目上下文 JSON）。
  Future<List<SourceReview>> _handleReviewQuotes(
    XiaoshuoBookSource bookSource,
    Map<String, String> vars,
  ) async {
    final chapterUrl = vars['url'] ?? vars['chapter'] ?? '';
    final bookId = vars['id'] ?? '';
    final book =
        (bookId.isEmpty ? null : (_bookInfoCache[bookId] ?? _seedFor(bookId))) ??
            XiaoshuoBook(bookUrl: bookId, name: '');
    return BookReview.fetchQuotes(
      bookSource: bookSource,
      target: _reviewFromVars(vars),
      book: book,
      chapter: _chapterFor(bookId, chapterUrl),
      baseUrl: chapterUrl.isEmpty ? book.tocUrl ?? book.bookUrl : chapterUrl,
    );
  }

  /// 段评动作：`action` ∈ post/quote/voteUp/voteDown/delete。
  /// vars：`text`（用户输入）、`review`/`reviewContext`（目标条目）。
  Future<bool> _handleReviewAction(
    XiaoshuoBookSource bookSource,
    Map<String, String> vars,
  ) async {
    final chapterUrl = vars['url'] ?? vars['chapter'] ?? '';
    final bookId = vars['id'] ?? '';
    final book =
        (bookId.isEmpty ? null : (_bookInfoCache[bookId] ?? _seedFor(bookId))) ??
            XiaoshuoBook(bookUrl: bookId, name: '');
    final chapter = _chapterFor(bookId, chapterUrl);
    final baseUrl = chapterUrl.isEmpty ? book.tocUrl ?? book.bookUrl : chapterUrl;
    final text = vars['text'] ?? '';
    final paragraph = int.tryParse(vars['paragraph'] ?? '');
    switch (vars['action'] ?? '') {
      case 'post':
        return BookReview.postReview(
          bookSource: bookSource,
          text: text,
          book: book,
          chapter: chapter,
          baseUrl: baseUrl,
          paragraph: paragraph,
        );
      case 'quote':
        return BookReview.postQuote(
          bookSource: bookSource,
          target: _reviewFromVars(vars),
          text: text,
          book: book,
          chapter: chapter,
          baseUrl: baseUrl,
          paragraph: paragraph,
        );
      case 'voteUp':
        return BookReview.vote(
          bookSource: bookSource,
          target: _reviewFromVars(vars),
          up: true,
          book: book,
          chapter: chapter,
          baseUrl: baseUrl,
        );
      case 'voteDown':
        return BookReview.vote(
          bookSource: bookSource,
          target: _reviewFromVars(vars),
          up: false,
          book: book,
          chapter: chapter,
          baseUrl: baseUrl,
        );
      case 'delete':
        return BookReview.deleteReview(
          bookSource: bookSource,
          target: _reviewFromVars(vars),
          book: book,
          chapter: chapter,
          baseUrl: baseUrl,
        );
      default:
        return false;
    }
  }

  /// 从 vars 还原段评条目（跨 isolate/路由只传字符串）。
  SourceReview _reviewFromVars(Map<String, String> vars) {
    final rawContext = vars['reviewContext'] ?? '';
    Map<String, dynamic> context = <String, dynamic>{};
    if (rawContext.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawContext);
        if (decoded is Map) {
          context = <String, dynamic>{
            for (final e in decoded.entries) e.key.toString(): e.value,
          };
        }
      } catch (_) {}
    }
    return SourceReview(
      content: vars['review'] ?? context['content']?.toString() ?? '',
      avatar: context['avatar']?.toString() ?? '',
      postTime: context['postTime']?.toString() ?? '',
      context: context.isEmpty ? null : context,
    );
  }

  // ── 付费动作 ──

  /// 执行书源购买动作（legado `ruleContent.payAction`）。
  ///
  /// 对齐 md3 `ReadBookViewModel.confirmPayAction` /
  /// `MangaReaderActionRepository.payCurrentChapter`：
  /// - 以本章上下文（book/chapter/baseUrl）直接编译执行 payAction；
  /// - 返回绝对 URL → 交给 UI 打开支付页；
  /// - 返回真值 → 视为已购买，UI 清正文缓存后重载；
  /// - 其余（空/false）→ 报错。
  Future<NovelPayResult> _handlePayAction(
    PluginConfig source,
    XiaoshuoBookSource bookSource,
    Map<String, String> vars,
  ) async {
    final payAction = (bookSource.ruleContent?.payAction ?? '').trim();
    if (payAction.isEmpty) {
      throw SourceResolveException(
        sourceId: source.id,
        apiName: 'pay',
        message: 'ruleContent.payAction 未声明',
      );
    }
    final chapterUrl = vars['url'] ?? vars['chapter'] ?? '';
    if (chapterUrl.isEmpty) {
      throw ArgumentError('pay requires vars["url"]');
    }
    final bookUrl = vars['bookUrl'] ?? vars['id'] ?? '';
    // 复用详情/搜索阶段暂存的书对象：payAction 里 `java.get`/`book.*`
    // 读到的变量与 API 型源的签名参数一致（legado 持有同一 Book 对象）。
    final book = _bookInfoCache[bookUrl] ??
        _seedFor(bookUrl) ??
        XiaoshuoBook(bookUrl: bookUrl, name: vars['bookName'] ?? '');
    final chapter = XiaoshuoBookChapter(
      bookUrl: bookUrl,
      url: chapterUrl,
      title: vars['chapterTitle'] ?? '',
      isVip: true,
    );
    final rule = AnalyzeRule(book: book, chapter: chapter)
      ..setBaseUrl(chapterUrl);
    final result = rule.evalJs(payAction, null).trim();
    if (result.startsWith('http://') || result.startsWith('https://')) {
      return NovelPayResult.openUrl(result);
    }
    if (_isLegadoTrue(result)) return NovelPayResult.refreshed();
    throw SourceResolveException(
      sourceId: source.id,
      apiName: 'pay',
      message: 'payAction 返回 $result',
    );
  }

  // ── 事件回调 ──

  /// 执行书源事件回调（legado `SourceCallBack`）。
  ///
  /// 对齐 md3：绑定 `event`/`result`/`book`/`chapter`，`java` 为 BaseSource
  /// （含登录/搜索/发现 UI 面）；返回假值 → 调用方执行默认动作，真值 →
  /// 保持脚本结果，异常 → 仅记录、默认动作也不执行。
  ///
  /// 脚本包在 `eval` 里执行：语法错误/运行期异常在 JS 侧捕获并回传
  /// `{e:...}`，与引擎级失败（空串）一起映射为「异常」。
  Future<SourceCallbackResult> _handleSourceCallback(
    PluginConfig source,
    XiaoshuoBookSource bookSource,
    Map<String, String> vars,
  ) async {
    if (!bookSource.eventListener) {
      // legado SourceCallBack.callBackBtn/callBackBook：未开启事件监听时
      // 不执行 callBackJs，直接走默认动作。
      return const SourceCallbackResult(runDefault: true);
    }
    final jsStr = (bookSource.ruleContent?.callBackJs ?? '').trim();
    if (jsStr.isEmpty) {
      // 无回调脚本：等同未开启事件监听，默认动作照常执行。
      return const SourceCallbackResult(runDefault: true);
    }
    final ctx = ShuyuanSourceContext.current;
    ctx?.openRequests.clear();
    ctx?.copiedTexts.clear();

    final bookUrl = vars['bookUrl'] ?? vars['id'] ?? '';
    final book = _bookInfoCache[bookUrl] ??
        _seedFor(bookUrl) ??
        XiaoshuoBook(bookUrl: bookUrl, name: '');
    if (book.name.isEmpty) book.name = vars['bookName'] ?? '';
    if (book.author.isEmpty) book.author = vars['author'] ?? '';
    final chapterUrl = vars['chapterUrl'] ?? '';
    XiaoshuoBookChapter? chapter;
    if (chapterUrl.isNotEmpty) {
      chapter = XiaoshuoBookChapter(
        bookUrl: bookUrl,
        url: chapterUrl,
        title: vars['chapterTitle'] ?? '',
        index: int.tryParse(vars['chapterIndex'] ?? '') ?? 0,
        isVip: vars['chapterVip'] == '1',
        isPay: vars['chapterPay'] == '1',
      );
    }
    final rule = AnalyzeRule(book: book, chapter: chapter)
      ..setBaseUrl(bookSource.bookSourceUrl);
    const wrapper = '(function () {\n'
        '  try {\n'
        '    var __v = eval(__src);\n'
        "    var __t = __v === undefined || __v === null ? '' : String(__v);\n"
        '    return JSON.stringify({v: __t});\n'
        '  } catch (__e) {\n'
        "    return JSON.stringify({e: String(__e && __e.message ? __e.message : __e)});\n"
        '  }\n'
        '})()';
    // md3 CopyTocUrl 的 result 变量就是 book.tocUrl（详情阶段解析并回填）；
    // 界面调用方拿不到书对象，这里按事件补齐。
    final String? resultText = vars['result'] ??
        ((vars['event'] ?? '') == 'clickCopyTocUrl' ? book.tocUrl : null);
    final raw = rule.evalJs(
      wrapper,
      resultText,
      extraBindings: <String, dynamic>{
        'event': vars['event'] ?? '',
        '__src': jsStr,
      },
    );
    String value = '';
    String? error;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final e = decoded['e'];
        if (e != null) error = e.toString();
        value = decoded['v']?.toString() ?? '';
      } else {
        value = raw;
      }
    } catch (_) {
      // 引擎级失败（AnalyzeRule 吞异常返回空串）：按异常处理——md3 异常
      // 只记日志，默认动作不执行。
      error = raw.trim().isEmpty ? 'callback eval failed' : null;
      if (error == null) value = raw;
    }
    final openRequests =
        ctx == null ? const <Map<String, String>>[] : List.of(ctx.openRequests);
    final copiedTexts =
        ctx == null ? const <String>[] : List.of(ctx.copiedTexts);
    ctx?.openRequests.clear();
    ctx?.copiedTexts.clear();
    return SourceCallbackResult(
      runDefault: error == null && !_isLegadoTrue(value),
      value: value,
      error: error,
      openRequests: openRequests,
      copiedTexts: copiedTexts,
      tocUrl: book.tocUrl ?? '',
    );
  }

  /// legado `String?.isTrue`：空 / "null" 为假；忽略大小写的
  /// `false|no|not|0|0.0` 为假；其余非空值为真。
  /// payAction 与 callBackJs 共用同一口径（md3 两处都调 `isTrue`）。
  static bool _isLegadoTrue(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty || text == 'null') return false;
    return !RegExp(r'^(?:false|no|not|0|0\.0)$', caseSensitive: false)
        .hasMatch(text);
  }

  /// 从正文块（音/视频源的正文规则输出）提取媒体直链。
  ///
  /// legado 对 bookSourceType=1/4 不做 htmlFormat，正文即直链（可能多行），
  /// 这里取第一条 http(s) 行。
  String? _extractMediaUrl(List<NovelBlock> blocks) {
    const nl = '\n';
    for (final b in blocks) {
      if (b is! NovelTextBlock) continue;
      for (final line in b.text.split(nl)) {
        final t = line.trim();
        if (t.startsWith('http://') || t.startsWith('https://')) {
          return t;
        }
      }
    }
    return null;
  }

  /// 正文中的第一条非空行（legado 视频链路把整段正文 trim 后当媒体地址）。
  static String? _firstMediaLine(String text) {
    for (final line in text.split('\n')) {
      final t = line.trim();
      if (t.isNotEmpty) return t;
    }
    return null;
  }

  /// 媒体地址归一：`//host/path` 补章节页协议；相对路径按章节页绝对化
  /// （对齐 legado VideoContentRepository → AnalyzeUrl 之前的处理）。
  static String? _normalizeMediaUrl(String? raw, String chapterUrl) {
    final t = raw?.trim() ?? '';
    if (t.isEmpty) return null;
    if (t.startsWith('http://') || t.startsWith('https://')) return t;
    if (t.startsWith('//')) {
      final scheme = Uri.tryParse(chapterUrl)?.scheme ?? 'https';
      return '$scheme:$t';
    }
    final abs = AnalyzeRule.absoluteUrl(chapterUrl, t);
    return abs.isEmpty ? null : abs;
  }

  /// 视频/音频源（legado bookSourceType=1/4）的播放直链解析。
  ///
  /// 媒体管线（VideoPlayerScreen → MediaApiService.fetchVideoUrl）按 `video`
  /// 路由调用：抓章节页 → 正文规则 → 直链（[VideoResult]）。书源播放页常挂
  /// Cloudflare，验证拦截由上层 verificationHandler 走 WebView 后回灌渲染
  /// HTML（见 [resolveRenderedHtml] 的同名分支）。
  ///
  /// 对照 legado VideoContentRepository.loadMedia：正文 trim 后整段即媒体
  /// 地址（不做 HTML 格式化），再经 AnalyzeUrl 解析 URL 选项（headers/
  /// method 等），把声明型请求头一并带回播放器——拉 m3u8/分片必须带同一
  /// 套 Referer/UA/Cookie，否则 CDN 403 全程黑屏。
  Future<VideoResult> _handleVideo(
    PluginConfig source,
    XiaoshuoBookSource bookSource,
    Map<String, String> vars,
  ) async {
    final chapterUrl = vars['url'] ?? vars['chapter'] ?? '';
    if (chapterUrl.isEmpty) {
      throw ArgumentError('video requires vars["url"]');
    }
    final bookId = vars['id'] ?? '';
    // 实体跨阶段：正文规则里的 `book.*` / `chapter.index|variableMap` 要沿用
    // 详情/目录阶段的值（直连正文与渲染回灌同口径）。
    final cachedBook = bookId.isEmpty
        ? null
        : (_bookInfoCache[bookId] ?? _seedFor(bookId));
    final cachedChapter = _chapterFor(bookId, chapterUrl);
    final chapterTitle = vars['chapterTitle'] ?? '';
    // 正文分页停止保护对所有内容类型一致：调用方未传时按缓存目录取下一章。
    final nextChapterUrl = _resolveNextChapterUrl(
      vars['nextChapterUrl'] ?? '',
      bookId,
      cachedChapter,
    );
    final result = await _webBook.getContent(
      source: bookSource,
      chapterUrl: chapterUrl,
      originalBook: cachedBook,
      bookChapter: cachedChapter,
      nextChapterUrl: nextChapterUrl.isEmpty ? null : nextChapterUrl,
      chapterTitle: chapterTitle.isEmpty ? null : chapterTitle,
    );
    final rawText = result.content.trim();
    if (rawText.startsWith('<')) {
      throw SourceResolveException(
        sourceId: source.id,
        apiName: 'video',
        message: '正文为 DASH/MPD 清单文本，当前播放器不支持该形态',
      );
    }
    final mediaUrl = _normalizeMediaUrl(
      _firstMediaLine(rawText) ?? _extractMediaUrl(result.blocks),
      chapterUrl,
    );
    if (mediaUrl == null || mediaUrl.isEmpty) {
      throw SourceResolveException(
        sourceId: source.id,
        apiName: 'video',
        message: result.error ?? '正文未解析到媒体直链',
      );
    }
    final analyzeUrl = AnalyzeUrl(
      url: mediaUrl,
      baseUrl: bookSource.bookSourceUrl,
      source: bookSource,
    );
    return VideoResult(
      url: analyzeUrl.url,
      headers: analyzeUrl.resolveRequestHeaders(),
      // 歌词只属于音频源（bookSourceType=1）：视频源结果保持原样。
      lyric: bookSource.bookSourceType == 1 ? result.lyric : null,
    );
  }

  /// 渲染回灌路径的音频歌词：在正文解析后求值 `ruleContent.subContent`
  /// （md3 BookContent 外层同款：http 开头先抓取），写入章节变量后回传。
  Future<String?> _resolveRenderedLyric({
    required XiaoshuoBookSource bookSource,
    required XiaoshuoBookChapter chapter,
    required String body,
    required String baseUrl,
    XiaoshuoBook? book,
  }) async {
    final rule = bookSource.getContentRule().subContent;
    if (rule == null || rule.isEmpty) {
      final existing = chapter.getVariable('lyric').trim();
      return existing.isEmpty ? null : existing;
    }
    try {
      final analyzeRule = AnalyzeRule(
          book: book ?? XiaoshuoBook(bookUrl: '', name: ''),
          chapter: chapter)
        ..setContent(body, baseUrl)
        ..setBaseUrl(baseUrl)
        ..setRedirectUrl(baseUrl);
      var text = analyzeRule.getString(rule, unescape: false).trim();
      if (text.toLowerCase().startsWith('http')) {
        text = (await AnalyzeUrl(
          url: text,
          baseUrl: baseUrl,
          source: bookSource,
          chapter: chapter,
        ).getStrResponse())
            .trim();
      }
      if (text.isEmpty) return null;
      chapter.putVariable('lyric', text);
      return text;
    } catch (_) {
      return null;
    }
  }

  // ── 文件类书源（legado bookSourceType=3）──

  /// 下载地址列表（legado BookInfoViewModel.loadWebFile）。
  ///
  /// 详情阶段已把 `ruleBookInfo.downloadUrls` 解析进书对象；缓存未命中时
  /// 拉一次详情页。名字从 URL 路径或 HEAD 响应头解析，失败按
  /// 「书名 作者：作者.后缀」兜底。
  Future<List<WebFileItem>> _handleWebFiles(
    PluginConfig source,
    XiaoshuoBookSource bookSource,
    Map<String, String> vars,
  ) async {
    final id = vars['id'] ?? vars['detailUrl'] ?? '';
    if (id.isEmpty) {
      throw ArgumentError('webFiles requires vars["id"]');
    }
    XiaoshuoBook? book = _bookInfoCache[id];
    if (book == null || (book.downloadUrls?.isEmpty ?? true)) {
      book = await _webBook.getBookInfo(
        source: bookSource,
        bookUrl: id,
        seedBook: _seedFor(id),
      );
      _rememberBookInfo(book);
    }
    return _webFilesFromBook(source, bookSource, book);
  }

  Future<List<WebFileItem>> _webFilesFromBook(
    PluginConfig source,
    XiaoshuoBookSource bookSource,
    XiaoshuoBook book,
  ) async {
    final urls = book.downloadUrls ?? const <String>[];
    if (urls.isEmpty) {
      throw SourceResolveException(
        sourceId: source.id,
        apiName: 'webFiles',
        message: '下载链接为空',
      );
    }
    final String fallbackBase = book.author.trim().isEmpty
        ? book.name
        : '${book.name} 作者：${book.author}';
    final out = <WebFileItem>[];
    for (final String raw in urls) {
      final AnalyzeUrl analyzeUrl = AnalyzeUrl(
        url: raw,
        baseUrl: book.bookUrl,
        source: bookSource,
      );
      final String? resolvedName = await resolveWebFileName(analyzeUrl);
      final String requestType = (analyzeUrl.requestType ?? '').trim();
      final String suffix = requestType.isNotEmpty ? requestType : 'txt';
      out.add(WebFileItem(
        url: raw,
        name: resolvedName ?? '$fallbackBase.$suffix',
      ));
    }
    return out;
  }

  /// 下载选中的文件（字节返回给宿主落盘导入）。
  ///
  /// 原始 URL 在下载时重新求值（legado 对 BookInfoWebFile.url 的处理），
  /// 一次性签名/时间戳参数不会失效；[AnalyzeUrl] 负责源 header、UA、
  /// Cookie 覆盖层与 data: URL。
  Future<Uint8List> _handleWebFileDownload(
    PluginConfig source,
    XiaoshuoBookSource bookSource,
    Map<String, String> vars,
  ) async {
    final rawUrl = vars['url'] ?? '';
    if (rawUrl.isEmpty) {
      throw ArgumentError('webFileDownload requires vars["url"]');
    }
    final AnalyzeUrl analyzeUrl = AnalyzeUrl(
      url: rawUrl,
      baseUrl: bookSource.bookSourceUrl,
      source: bookSource,
    );
    try {
      await analyzeUrl.getStrResponse();
    } on SourceResolveException {
      rethrow;
    } catch (e) {
      throw SourceResolveException(
        sourceId: source.id,
        apiName: 'webFileDownload',
        message: '文件下载失败：$e',
      );
    }
    final Uint8List? bytes = analyzeUrl.lastResponseBytes;
    if (bytes == null || bytes.isEmpty) {
      throw SourceResolveException(
        sourceId: source.id,
        apiName: 'webFileDownload',
        message: '文件下载内容为空',
      );
    }
    return bytes;
  }

  // ── 模型转换 ──

  /// 目录地址随条目透传（`extra.tocUrl`）：CopyTocUrl 的默认动作在源未
  /// 开启事件回调时仍要复制书对象的 tocUrl（md3 `book.tocUrl`）。
  Map<String, dynamic>? _tocExtra(String? tocUrl) =>
      (tocUrl == null || tocUrl.isEmpty)
          ? null
          : <String, dynamic>{'tocUrl': tocUrl};

  MediaItem _searchBookToMediaItem(SearchBook sb, PluginConfig source) {
    return MediaItem(
      id: sb.bookUrl,
      title: sb.name,
      coverUrl: sb.coverUrl,
      detailUrl: sb.bookUrl,
      sourceId: source.id,
      sourceType: source.type,
      author: sb.author.isNotEmpty ? sb.author : null,
      description: sb.intro,
      tags: sb.kind
          ?.split(RegExp(r'[,\s]+'))
          .where((s) => s.trim().isNotEmpty)
          .map((s) => s.trim())
          .toList(),
      wordCount: sb.wordCount,
      extra: _tocExtra(sb.tocUrl),
    );
  }

  MediaItem _xiaoshuoBookToMediaItem(XiaoshuoBook book, PluginConfig source) {
    // 将引擎解析的 updateTime 字符串转为 DateTime。
    DateTime? parsedUpdatedAt;
    if (book.updateTime != null && book.updateTime!.isNotEmpty) {
      parsedUpdatedAt = _parseDateTime(book.updateTime!);
    }

    return MediaItem(
      id: book.bookUrl,
      title: book.name,
      coverUrl: book.coverUrl,
      detailUrl: book.bookUrl,
      sourceId: source.id,
      sourceType: source.type,
      author: book.author.isNotEmpty ? book.author : null,
      description: book.intro,
      status: book.bookStatus,
      tags: book.kind
          ?.split(RegExp(r'[,\s]+'))
          .where((s) => s.trim().isNotEmpty)
          .map((s) => s.trim())
          .toList(),
      updatedAt: parsedUpdatedAt,
      wordCount: book.wordCount,
      extra: _tocExtra(book.tocUrl),
    );
  }

  /// 尝试将日期时间字符串解析为 [DateTime]。
  ///
  /// 支持常见中文小说站格式：
  /// - `2022-11-25 16:27:00`
  /// - `2022-11-25 16:27`
  /// - `2022-11-25`
  /// - `2022/11/25 16:27:00`
  static DateTime? _parseDateTime(String value) {
    final trimmed = value.trim();
    // 尝试标准 ISO 格式
    try {
      return DateTime.parse(trimmed);
    } catch (_) {}

    // 尝试常见中文格式：YYYY-MM-DD HH:mm:ss / YYYY/MM/DD HH:mm:ss
    // 注意：不锚定开头/结尾，以容忍 "时间：2026-05-05 16:22" 这类带前缀的文本。
    final isoLike = RegExp(
        r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?');
    final m = isoLike.firstMatch(trimmed);
    if (m != null) {
      try {
        return DateTime(
          int.parse(m.group(1)!),
          int.parse(m.group(2)!),
          int.parse(m.group(3)!),
          m.group(4) != null ? int.parse(m.group(4)!) : 0,
          m.group(5) != null ? int.parse(m.group(5)!) : 0,
          m.group(6) != null ? int.parse(m.group(6)!) : 0,
        );
      } catch (_) {}
    }
    return null;
  }
}
