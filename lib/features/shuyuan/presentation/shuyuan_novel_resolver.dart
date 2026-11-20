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

import '../../../core/models/category_entry.dart';
import '../../../core/models/episode.dart';
import '../../../core/models/explore_kind.dart';
import '../../../core/models/media_item.dart';
import '../../../core/models/novel_block.dart'
    show NovelBlock, NovelImageBlock, NovelMediaBlock, NovelTextBlock;
import 'package:meta/meta.dart';

import '../../../core/models/plugin_config.dart';
import '../../../core/resolver/source_resolver.dart';
import '../../../core/resolver/resolver_registry.dart';
import '../../../core/resolver/webview_resolver.dart';
import '../../../core/scraper/verification_detector.dart';
import '../web_book/book_chapter_list.dart';
import '../web_book/book_content.dart';
import '../web_book/book_info.dart';
import '../web_book/book_list.dart';
import '../model/book_source.dart';
import '../model/search_book.dart';
import '../model/xiaoshuo_book.dart';
import '../model/xiaoshuo_book_chapter.dart';
import '../analyze/js_engine.dart';
import '../analyze/analyze_rule.dart';
import '../analyze/analyze_url.dart';
import '../analyze/source_context.dart';
import '../shuyuan_adapter.dart';
import '../shuyuan_explore_info_store.dart';
import '../shuyuan_explore_kinds_store.dart';
import '../web_book/web_book.dart';

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

  XiaoshuoBook _seedFromSearchBook(SearchBook sb) {
    return XiaoshuoBook(
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
    );
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
    return _contexts[source.id] ??= await ShuyuanSourceContext.forSource(
      source.id,
    );
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

    return ShuyuanSourceContext.run(ctx, () async {
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
        final deadline = DateTime.now().add(_replayBudget);
        dynamic out;
        for (var pass = 0; pass < _maxReplayPasses; pass++) {
          ctx.ajaxPending.clear();
          ctx.webviewPending.clear();
          ctx.deferFeedback = true;
          ctx.deferredToasts.clear();
          try {
            out = await _dispatch(source, bookSource, apiName, vars,
                onProgress: onProgress);
          } on Object {
            if (_hasPendingReplay(ctx) && _replayAllowed(pass, deadline)) {
              final fetched = await _settleReplay(ctx, bookSource);
              if (fetched > 0) continue;
            }
            rethrow;
          }
          if (!_hasPendingReplay(ctx)) return out;
          if (!_replayAllowed(pass, deadline)) break;
          final fetched = await _settleReplay(ctx, bookSource);
          if (fetched == 0) break;
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
    XiaoshuoBookSource bookSource,
  ) =>
      ShuyuanSourceContext.settleAjax(ctx, bookSource);

  /// 本轮是否还有等待宿主处理的请求（ajax 走 HTTP，webview 走无头渲染）。
  bool _hasPendingReplay(ShuyuanSourceContext ctx) =>
      ctx.ajaxPending.isNotEmpty || ctx.webviewPending.isNotEmpty;

  /// 一次性补齐两类重放请求；返回本轮新抓取的条目数（0 = 无进展）。
  Future<int> _settleReplay(
    ShuyuanSourceContext ctx,
    XiaoshuoBookSource bookSource,
  ) async {
    var fetched = await _fetchAjaxPending(ctx, bookSource);
    fetched += await ShuyuanSourceContext.settleWebview(ctx);
    return fetched;
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
        final books = BookList.analyzeBookList(
          bookSource: bookSource,
          baseUrl: bookSource.bookSourceUrl,
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
        // 目录：用 [BookChapterList] 解析渲染后 HTML（与 [WebBook.getChapterList]
        // 首页批次同口径，逐章连续编号以支持上下章导航）。
        final id = vars['id'] ?? vars['detailUrl'] ?? '';
        final book = XiaoshuoBook(bookUrl: id, name: '');
        final chapters = BookChapterList.analyzeChapterList(
          bookSource: bookSource,
          book: book,
          baseUrl: id,
          redirectUrl: id,
          body: html,
        );
        return <Episode>[
          for (var i = 0; i < chapters.length; i++)
            Episode(id: '$i', title: chapters[i].title, url: chapters[i].url),
        ];
      case 'content':
        // 正文：用 [BookContent] 解析渲染后 HTML（与 [WebBook.getContent] 同口径，
        // 声明式 ruleContent 而非脚本 override——书源渲染路径一致）。正文分页跟随
        // 在渲染路径下不做（WebView 取回的已是单页渲染结果），绝大多数章节单页。
        final chapterUrl = vars['url'] ?? vars['chapter'] ?? '';
        final book = XiaoshuoBook(bookUrl: '', name: '');
        final blocks = BookContent.analyzeContent(
          bookSource: bookSource,
          book: book,
          bookChapter: XiaoshuoBookChapter(bookUrl: '', url: chapterUrl),
          baseUrl: chapterUrl,
          redirectUrl: chapterUrl,
          body: html,
          mediaSource: bookSource.bookSourceType == 1 ||
              bookSource.bookSourceType == 4,
        );
        if (blocks.isEmpty) {
          throw SourceResolveException(
            sourceId: source.id,
            apiName: 'content',
            message: '正文渲染后解析为空',
          );
        }
        return blocks;
      case 'video':
        // 视频/音频源播放直链：渲染后 HTML 取正文规则里的媒体 URL。
        final videoChapterUrl = vars['url'] ?? vars['chapter'] ?? '';
        final videoBlocks = BookContent.analyzeContent(
          bookSource: bookSource,
          book: XiaoshuoBook(bookUrl: '', name: ''),
          bookChapter:
              XiaoshuoBookChapter(bookUrl: '', url: videoChapterUrl),
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
        return VideoResult(
          url: renderedAnalyze.url,
          headers: renderedAnalyze.resolveRequestHeaders(),
        );
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
    // 静态声明（文本 / JSON）不需要 JS 运行时，直接同步解析。
    if (!_exploreNeedsJs(exploreUrl)) {
      return _toCategoryEntries(
          _webBook.getExploreCategories(bookSource, infoMap: infoMap));
    }
    final ctx = await _contextFor(source);
    ctx.bindSource(bookSource);
    return ShuyuanSourceContext.run(ctx, () async {
      ctx.clearStageCaches();
      JsEngine.resetReplayCachesFor(source.id);
      final deadline = DateTime.now().add(_exploreCategoryBudget);
      ctx.deferredToasts.clear();
      ctx.deferFeedback = true;
      try {
        var entries = _toCategoryEntries(
            _webBook.getExploreCategories(bookSource, infoMap: infoMap));
        for (var pass = 0; pass < _maxReplayPasses; pass++) {
          if (!_hasPendingReplay(ctx)) break;
          if (!_replayAllowed(pass, deadline)) break;
          final fetched = await _settleReplay(ctx, bookSource);
          if (fetched == 0) break;
          entries = _toCategoryEntries(
              _webBook.getExploreCategories(bookSource, infoMap: infoMap));
        }
        return entries
            .where((e) =>
                !e.id.contains('__AJAX_') && !e.id.contains('__WEBVIEW_'))
            .toList(growable: false);
      } finally {
        ctx.flushDeferredToasts();
      }
    });
  }

  /// 解析发现页完整选项栏（legado ExploreKind）：url/text/button/toggle/
  /// select 全部保留，toggle/select 的值从持久化 infoMap 恢复（缺省时写入
  /// kind.default 或 chars 首项），viewName 逐项求值。
  ///
  /// 动态 exploreUrl / viewName 可发 `java.ajax`，沿用与发现分类相同的
  /// 占位符重放：每轮抓取未满足请求后重跑，直到无新请求或预算耗尽。
  /// 成功结果按源持久缓存（legado ACache 等效）；[refresh] 强制重抓。
  @override
  Future<ExploreKindsResult> resolveExploreKinds(
    PluginConfig source, {
    bool refresh = false,
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
          return ExploreKindsResult(items: items, infoMap: infoMap);
        }
        JsEngine.resetReplayCachesFor(source.id);
        final deadline = DateTime.now().add(_exploreCategoryBudget);
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
              }
              return built.result;
            }
            if (!_replayAllowed(pass, deadline)) return built.result;
            final fetched = await _settleReplay(ctx, bookSource);
            // 抓取失败/无进展：保留错误态，不写缓存（下次打开仍会重试）。
            if (fetched == 0) return built.result;
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
      await ShuyuanExploreInfoStore.save(infoKey, infoMap);
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
        final resolved = await _resolveKindViewName(
            source, viewName, infoMap,
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
    final wrapped = '(function () {\n$_infoMapCompatJs'
        '  return eval(${jsonEncode(viewName)});\n'
        '})()';
    final out = engine.eval(
      wrapped,
      bindings: <String, dynamic>{
        'infoMap': Map<String, String>.from(infoMap),
        'baseUrl': baseUrl,
      },
    );
    engine.takeJavaVars();
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
        final deadline = DateTime.now().add(_exploreCategoryBudget);
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
            final fetched = await _settleReplay(ctx, bookSource);
            if (fetched == 0) break;
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
    final page = int.tryParse(vars['page'] ?? '1') ?? 1;

    // PTCMS 动态筛选：源在 `filters` 中声明 文库(list)/题材(tags)/进度(finish)/
    // 字数(size)/排序(order) 五个维度。任一被选中即按站点 URL 模板拼装分类页
    // 并抓取；全空则回退到默认发现页（分类 Tab / 全量）。
    //
    // 关键：绝不能给未选维度塞默认值（否则会强制「连载 / 30万字以上 / 最新更新」
    // 等，把用户想看的「全部」也限死）。未选维度直接省略对应路径段，站点即视为
    // 不限定该维度；用户显式选「全部」(value=`all`/空) 也等同省略。
    final list = (vars['list']?.trim()) ?? '';
    final tags = (vars['tags']?.trim()) ?? '';
    final finish = _ptcmsSeg(vars['finish']);
    final size = _ptcmsSeg(vars['size']);
    final order = _ptcmsSeg(vars['order']);
    if (list.isNotEmpty ||
        tags.isNotEmpty ||
        finish != null ||
        size != null ||
        order != null) {
      final buf = StringBuffer(
          '${bookSource.bookSourceUrl}/index.php/book/category');
      if (list.isNotEmpty) buf.write('/list/$list');
      if (tags.isNotEmpty) buf.write('/tags/$tags');
      if (finish != null) buf.write('/finish/$finish');
      if (size != null) buf.write('/size/$size');
      if (order != null) buf.write('/order/$order');
      final books = await _webBook.exploreCategory(
        source: bookSource,
        categoryUrl: buf.toString(),
        page: page,
      );
      return _mapAndSeedBooks(books, source);
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
    final categories = _webBook.getExploreCategories(bookSource);
    if (categories.isEmpty) return <MediaItem>[];
    Object? firstError;
    for (final category in categories.take(_exploreHomeFallbackLimit)) {
      try {
        final books = await _webBook.exploreCategory(
          source: bookSource,
          categoryUrl: category.url,
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

  /// PTCMS 筛选段取值：
  /// - 未选（null）/ 选「全部」(`all`/空) → 返回 null，省略该路径段（站点视为
  /// 不限定该维度）；
  /// - 其余 → 原值（如文库 id、题材 id、finish/1|2、size/1..5、order/addtime/shits）。
  static String? _ptcmsSeg(String? raw) {
    if (raw == null) return null;
    final t = raw.trim();
    if (t.isEmpty || t == 'all') return null;
    return t;
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
      // 渐进批次：逐页把章节转为 Episode 后回传上层（首屏快显 + 后台续抓）。
      // 卷条目（isVolume）没有可读 URL（仅占位符），列表层无卷分隔形态，
      // 作为 Episode 会变成点不开的「章节」并挤占首章，故整体跳过。
      onBatch: (batch) {
        final playable = batch.where((c) => !c.isVolume);
        onProgress?.call(playable
            .map((c) => Episode(
                  id: '${c.index}',
                  title: c.title,
                  url: c.url,
                ))
            .toList());
      },
    );
    final isComic = source.type == SourceType.mangaSource;
    return chapters
        .where((c) => !c.isVolume)
        .map((c) => Episode(
              // 漫画模块：阅读器以 chapterId=Episode.id 回传 fetchImages，
              // id 须存章节 URL（小说模块 id 为序号、URL 走 url 字段）。
              id: isComic ? c.url : '${c.index}',
              title: c.title,
              url: c.url,
            ))
        .toList();
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
    final result = await _webBook.getContent(
      source: bookSource,
      chapterUrl: chapterUrl,
    );
    return imageUrlsFromBlocks(result.blocks);
  }

  /// 从图文块收集图片 URL：插图块直取；纯 URL 文本行兜底。
  @visibleForTesting
  static List<String> imageUrlsFromBlocks(List<NovelBlock> blocks) {
    final urls = <String>[];
    for (final b in blocks) {
      if (b is NovelImageBlock && b.url.trim().isNotEmpty) {
        urls.add(b.url.trim());
      }
    }
    if (urls.isNotEmpty) return urls;
    for (final b in blocks) {
      if (b is NovelTextBlock) {
        final newline = String.fromCharCode(10);
        for (final line in b.text.split(newline)) {
          final t = line.trim();
          if (t.startsWith('http://') || t.startsWith('https://')) {
            urls.add(t);
          }
        }
      }
    }
    return urls;
  }

  // ── 正文 ──
  Future<List<NovelBlock>> _handleContent(
    PluginConfig source,
    XiaoshuoBookSource bookSource,
    Map<String, String> vars,
  ) async {
    final chapterUrl = vars['url'] ?? vars['chapter'] ?? '';
    if (chapterUrl.isEmpty) {
      throw ArgumentError('content requires vars["url"]');
    }
    final result = await _webBook.getContent(
      source: bookSource,
      chapterUrl: chapterUrl,
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
    final srcTypeRaw =
        (source.selectors?['xiaoshuo'] as Map<String, dynamic>?)
            ?['bookSourceType'];
    final srcType =
        srcTypeRaw is int ? srcTypeRaw : int.tryParse('$srcTypeRaw') ?? 0;
    if (srcType == 1 || srcType == 4) {
      final kind = srcType == 1 ? 'audio' : 'video';
      final mediaUrl = _normalizeMediaUrl(
        _firstMediaLine(result.content.trim()) ??
            _extractMediaUrl(result.blocks),
        chapterUrl,
      );
      return <NovelBlock>[
        NovelMediaBlock(mediaUrl ?? '', kind: kind),
      ];
    }
    // 图文块列表（文本段 + 插图），保留解析层给出的原始顺序，
    // 供阅读器图文混排显示。
    return result.blocks;
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
    final result = await _webBook.getContent(
      source: bookSource,
      chapterUrl: chapterUrl,
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
    );
  }

  // ── 模型转换 ──
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
    final isoLike = RegExp(r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?');
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
