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

import '../../../core/models/category_entry.dart';
import '../../../core/models/episode.dart';
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
import '../analyze/source_context.dart';
import '../shuyuan_adapter.dart';
import '../web_book/web_book.dart';

class ShuyuanNovelResolver
    implements SourceResolver, RenderedHtmlCapable, ExploreCategoriesCapable {
  ShuyuanNovelResolver();

  final WebBook _webBook = WebBook();

  /// 每源运行时上下文（cookie 覆盖层/源变量/登录信息/缓存），注入对象
  /// （cookie/source/book/cache）的宿主侧。按源 id 缓存。
  final Map<String, ShuyuanSourceContext> _contexts = {};

  Future<ShuyuanSourceContext> _contextFor(PluginConfig source) async {
    return _contexts[source.id] ??= await ShuyuanSourceContext.forSource(
      source.id,
    );
  }

  /// 重放轮次上限（安全阀）：正常多跳脚本 3–6 轮即收敛。
  static const int _maxReplayPasses = 16;

  /// 单阶段重放总时长预算。
  static const Duration _replayBudget = Duration(seconds: 120);

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
    // jsLib 预执行内容随作用域下发（引擎首次 eval 前执行）。
    ctx.jsLib = bookSource.jsLib ?? '';

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
        return await _handleChapterList(source, bookSource, vars,
            onProgress: onProgress);
      case 'content':
        return await _handleContent(source, bookSource, vars);
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
    ctx.jsLib = bookSource.jsLib ?? '';
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
        return books
            .map((sb) => _searchBookToMediaItem(sb, source.id))
            .toList();
      case 'detail':
        // 详情页：用 [BookInfo] 解析渲染后 HTML（与 [WebBook.getBookInfo] 同口径）。
        final id = vars['id'] ?? vars['detailUrl'] ?? '';
        final book = XiaoshuoBook(bookUrl: id, name: '');
        BookInfo.analyzeBookInfo(
          bookSource: bookSource,
          book: book,
          baseUrl: id,
          redirectUrl: id,
          body: html,
        );
        return _xiaoshuoBookToMediaItem(book, source.id);
      case 'toc':
      case 'chapters':
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
        );
        if (blocks.isEmpty) {
          throw SourceResolveException(
            sourceId: source.id,
            apiName: 'content',
            message: '正文渲染后解析为空',
          );
        }
        return blocks;
      default:
        return resolve(source, apiName, vars: vars);
      }
    });
  }

  // ── 发现分类解析 ──
  /// 解析书源 exploreUrl 为分类列表（支持 `名称::URL` 多行 / JSON 数组 /
  /// `<js>` 动态生成），供在线浏览页生成分类 Tab。此前静态正则解析会跳过
  /// 含 `<js>` 的 exploreUrl，这类源一个分类 Tab 都没有。
  @override
  List<CategoryEntry> resolveExploreCategories(PluginConfig source) {
    final shuyuanSource = ShuyuanAdapter.fromPluginConfig(source);
    if (shuyuanSource == null) return const <CategoryEntry>[];
    final bookSource = shuyuanSource.toBookSource();
    // 同步入口：已装载的上下文直接用；未装载则用轻量内存上下文
    // （源变量持久化装载走异步 resolve 链路）。
    final ctx = _contexts[source.id] ?? ShuyuanSourceContext(source.id);
    // 分类解析也可能求值 exploreUrl 里的 @js：从干净缓存开始。
    ctx.clearStageCaches();
    JsEngine.resetReplayCachesFor(source.id);
    return ShuyuanSourceContext.run(ctx, () {
      return _webBook
          .getExploreCategories(bookSource)
          .map((e) => CategoryEntry(
                id: e.url,
                title: e.name.isNotEmpty ? e.name : e.url,
              ))
          .toList();
    });
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
    return results.map((sb) => _searchBookToMediaItem(sb, source.id)).toList();
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
      return books.map((b) => _xiaoshuoBookToMediaItem(b, source.id)).toList();
    }

    final categoryUrl = vars['category'];

    if (categoryUrl != null && categoryUrl.isNotEmpty) {
      final books = await _webBook.exploreCategory(
        source: bookSource,
        categoryUrl: categoryUrl,
        page: page,
      );
      return books.map((b) => _xiaoshuoBookToMediaItem(b, source.id)).toList();
    }

    // 没指定分类时，走全量发现页。书源未配置 exploreUrl（纯搜索源，无发现页）
    // 时优雅返回空列表，避免把「书源未配置 exploreUrl」当作错误刷红屏/
    // 空态误导用户（真实网络错误仍会正常抛出由上层重试）。
    if (bookSource.exploreUrl == null || bookSource.exploreUrl!.isEmpty) {
      return <MediaItem>[];
    }

    // 首页 latest 板块（未指定分类）：只取第一个分类，而非逐个抓取全部分类
    // 再合并。此前串行抓取全部分类（同 host 限流下可达数十秒），首页长时间
    // 停留在加载态，用户感知即「页面没有内容」；分类 Tab 已提供完整分类浏览。
    final categories = _webBook.getExploreCategories(bookSource);
    if (categories.isEmpty) return <MediaItem>[];
    final books = await _webBook.exploreCategory(
      source: bookSource,
      categoryUrl: categories.first.url,
      page: page,
    );
    return books.map((b) => _xiaoshuoBookToMediaItem(b, source.id)).toList();
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
    final book = await _webBook.getBookInfo(source: bookSource, bookUrl: id);
    return _xiaoshuoBookToMediaItem(book, source.id);
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
    // WebBook.getChapterList 需要 XiaoshuoBook 来获取 tocUrl；用 bookUrl=id 构造。
    final book = XiaoshuoBook(bookUrl: id, name: '');
    final chapters = await _webBook.getChapterList(
      source: bookSource,
      book: book,
      // 渐进批次：逐页把章节转为 Episode 后回传上层（首屏快显 + 后台续抓）。
      onBatch: (batch) {
        onProgress?.call(batch
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
      String? mediaUrl;
      for (final b in result.blocks) {
        if (b is NovelTextBlock) {
          final nl = String.fromCharCode(10);
          for (final line in b.text.split(nl)) {
            final t = line.trim();
            if (t.startsWith('http://') || t.startsWith('https://')) {
              mediaUrl = t;
              break;
            }
          }
          if (mediaUrl != null) break;
        }
      }
      final kind = srcType == 1 ? 'audio' : 'video';
      return <NovelBlock>[
        NovelMediaBlock(mediaUrl ?? '', kind: kind),
      ];
    }
    // 图文块列表（文本段 + 插图），保留解析层给出的原始顺序，
    // 供阅读器图文混排显示。
    return result.blocks;
  }

  // ── 模型转换 ──
  MediaItem _searchBookToMediaItem(SearchBook sb, String sourceId) {
    return MediaItem(
      id: sb.bookUrl,
      title: sb.name,
      coverUrl: sb.coverUrl,
      detailUrl: sb.bookUrl,
      sourceId: sourceId,
      sourceType: SourceType.novelSource,
      author: sb.author.isNotEmpty ? sb.author : null,
      tags: sb.kind
          ?.split(RegExp(r'[,\s]+'))
          .where((s) => s.trim().isNotEmpty)
          .map((s) => s.trim())
          .toList(),
    );
  }

  MediaItem _xiaoshuoBookToMediaItem(XiaoshuoBook book, String sourceId) {
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
      sourceId: sourceId,
      sourceType: SourceType.novelSource,
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
