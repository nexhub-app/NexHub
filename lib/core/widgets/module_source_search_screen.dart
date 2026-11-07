/// 模块源搜索页（文档 搜索统一）。
///
/// 搜索不区分「聚合/单源」两种模式：以勾选源为准，勾选了哪些源就搜哪些源
/// （详情页跳转默认只勾选当前源；常规进入默认全选）。各勾选源并发检索，
/// 结果逐源到达即展示，不再等全部源搜完才显示。
/// 影视模块的媒体服务器作为一种可选源并列在源勾选条里，勾选才参与搜索。
/// 小说/媒体/漫画三模块共用，布局偏好与书架/设置页共用 [LayoutSettingsStore] 单例。
/// 输入过程不触发检索，回车/搜索键提交后才跨源搜索。
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/download/download_manager.dart';
import '../../../core/download/download_task.dart';
import '../../../core/local/local_content_manager.dart';
import '../../../core/models/media_item.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/scraper/media_api_service.dart';
import '../../../core/scraper/verification_navigator.dart';
import '../../../core/services/config_loader.dart';
import '../../../core/settings/layout_settings.dart';
import '../../../core/widgets/layout_picker_button.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_loading_indicator.dart';
import '../../features/media_server/media_server_search_section.dart';
import '../../../core/comic/comic_progress_manager.dart';
import '../../../core/history/media_watched_manager.dart';
import '../../../core/novel/novel_chinese_converter.dart';
import '../../../core/novel/novel_progress_manager.dart';
import '../../../core/settings/reader_default_settings.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_cover_image.dart';
import '../../../core/widgets/content_card.dart';
import '../../../core/widgets/highlight_text.dart';
import '../../../core/widgets/module_search_screen.dart';
import '../../features/verification/presentation/verification_handler.dart';

/// 搜索范围枚举已移除：搜索一律按源勾选集执行，不再区分聚合/单源。

class ModuleSourceSearchScreen extends StatefulWidget {
  final SourceType sourceType;
  final String title;
  final String? initialQuery;
  /// 定向搜索字段（author/tag/actor/director）；null 表示通用关键词搜索。
  final String? searchField;
  /// 直达地址：调用方已取得的真实页面链接（如详情页抓取到的作者/标签落地页），
  /// 非空时进入直达模式，直接用它检索并信任返回结果。
  final String? extractedUrl;
  /// 进入时默认只勾选该源（如从详情页跳转搜索，默认只搜当前这个源）。
  final bool startSingle;
  /// 配合 [startSingle] 预勾选的源 id。
  final String? initialSourceId;
  final void Function(MediaItem item, String? heroTag) onItemTap;

  const ModuleSourceSearchScreen({
    super.key,
    required this.sourceType,
    required this.title,
    this.initialQuery,
    this.searchField,
    this.extractedUrl,
    this.startSingle = false,
    this.initialSourceId,
    required this.onItemTap,
  });

  @override
  State<ModuleSourceSearchScreen> createState() =>
      _ModuleSourceSearchScreenState();
}

class _ModuleSourceSearchScreenState extends State<ModuleSourceSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _grid = true;
  /// 网络源搜索进行中：结果逐源到达即插入列表，全部源落定后置 false。
  bool _loading = false;
  List<MediaItem> _results = const <MediaItem>[];
  /// 已展示结果的 id 集合：逐源追加/翻页合并时按 id 去重。
  final Set<String> _resultIds = <String>{};
  /// 源勾选条滚动控制器，桌面端滚轮/拖动可横滚。
  final ScrollController _sourceScrollController = ScrollController();
  /// 详情页预勾选源 chip 的 key，供 [Scrollable.ensureVisible] 定位。
  final GlobalKey _selectedSourceKey = GlobalKey();

  /// 勾选参与搜索的源 id 集合（多选；空集=不搜网络源）。
  final Set<String> _checkedSourceIds = <String>{};
  /// 勾选集是否已按入口初始化（详情页单源 / 常规全选），只初始化一次。
  bool _selectionInitialized = false;
  /// 媒体服务器是否参与本次搜索（仅影视模块；作为可选源与普通源并列勾选）。
  bool _mediaServerChecked = false;
  /// 进度计算缓存（按 "id#list" / "id#showProgress" 维度），避免列表/网格重复计算。
  final Map<String, Future<double?>> _progressFutures =
      <String, Future<double?>>{};
  /// 当前字段筛选（null=关键词；tags/author/director/actors/title）。
  String? _searchField;
  /// 未勾选任何源时的提示标记。
  bool _needSource = false;
  /// 已加载页码（从 1 开始）。源路由声明了 `{page}` 时滚动触底自动翻页，
  /// 修复「搜索不全（还有下一页）」——此前搜索恒定只取第 1 页。
  int _page = 1;
  /// 仍可能有下一页的源 id 集合（非空才展示/触发「加载更多」）。
  final Set<String> _sourcesWithMore = <String>{};
  /// 追加加载中标记（避免滚动回调重复触发）。
  bool _loadingMore = false;
  /// 搜索代际：每次新搜索递增；过期搜索的迟到结果按代际丢弃，防止串台。
  int _searchGen = 0;
  /// 小说模块繁简转换：按全局阅读偏好的转换方向，仅作用于
  /// 搜索结果的标题/作者展示与本地匹配归一，不改写入库/收藏的原始数据。
  ChineseConvertMode _novelConvertMode = ChineseConvertMode.none;
  /// 单源搜索简繁兜底（扩展）：首搜为空、用简↔繁互转关键词命中后，
  /// 记录实际生效关键词，后续翻页沿用，避免「下一页又回到原词导致结果错位」。
  String? _networkKeyword;
  /// 验证弹窗串行链：并发多源搜索同时命中验证时排队逐个处理，避免弹窗叠加。
  Future<void> _verificationChain = Future<void>.value();

  @override
  void initState() {
    super.initState();
    // 与书架/设置页共用同一 LayoutSettingsStore 单例，布局全局统一。
    _grid = LayoutSettingsStore.instance.settings.layoutMode == LayoutMode.grid;
    LayoutSettingsStore.instance.addListener(_onLayoutStoreChanged);
    _searchField = widget.searchField;
    // 小说模块读取全局繁简转换偏好，用于结果标题/作者展示转换。
    if (widget.sourceType == SourceType.novelSource) {
      ReaderDefaultSettingsStore()
          .load()
          .then((ReaderDefaultSettings s) {
        if (!mounted) return;
        setState(() {
          _novelConvertMode = switch (s.novelChineseConversion) {
            NovelChineseConversion.traditionalToSimplified =>
              ChineseConvertMode.traditionalToSimplified,
            NovelChineseConversion.simplifiedToTraditional =>
              ChineseConvertMode.simplifiedToTraditional,
            NovelChineseConversion.none => ChineseConvertMode.none,
          };
        });
      });
    }
    // 直达模式：调用方已提供真实页面地址（如详情页抓取到的作者/标签落地页），
    // 直接带入搜索，跳过关键词输入与客户端收窄（服务端已按该页过滤；
    // 见 _fetchSourcePage 内对 widget.extractedUrl 的使用）。
    // 详情页跳转搜索：默认只勾选当前源（勾选集初始化见 _ensureSelectionInit）。
    // 从详情页进入搜索：预勾选源 chip 自动滚入可视区域。
    if (widget.startSingle && widget.initialSourceId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final srcs = context.read<SourceRepository>().byType(widget.sourceType);
        final idx = srcs.indexWhere((s) => s.id == widget.initialSourceId);
        if (idx < 0) return;
        final ctx = _selectedSourceKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.5,
            duration: const Duration(milliseconds: 250),
          );
        }
      });
    }
    final String? q = widget.initialQuery;
    if (q != null && q.isNotEmpty) {
      _controller.text = q;
      _doSearch(q);
    }
  }

  /// 订阅全局布局单例：书架/设置页或本页弹窗改动布局时，即时刷新网格/列表。
  void _onLayoutStoreChanged() {
    if (mounted) {
      setState(() {
        _grid = LayoutSettingsStore.instance.settings.layoutMode == LayoutMode.grid;
      });
    }
  }

  /// 按全局小说转换偏好转换展示文本（标题/作者/高亮关键词）。
  String _convText(String? text) {
    if (text == null ||
        text.isEmpty ||
        _novelConvertMode == ChineseConvertMode.none) {
      return text ?? '';
    }
    return convertChinese(text, _novelConvertMode);
  }

  @override
  void dispose() {
    LayoutSettingsStore.instance.removeListener(_onLayoutStoreChanged);
    _controller.dispose();
    _sourceScrollController.dispose();
    super.dispose();
  }

  /// 按入口初始化源勾选集（只执行一次）：
  /// - 详情页跳转（[ModuleSourceSearchScreen.startSingle]）：仅勾选预选源，
  ///   媒体服务器不参与——修复「单源搜索也弹媒体服务器」；
  /// - 常规进入：默认全选（等价原聚合搜索口径），影视模块媒体服务器默认参与，
  ///   用户可随时取消勾选。
  void _ensureSelectionInit(List<PluginConfig> sources) {
    if (_selectionInitialized) return;
    _selectionInitialized = true;
    if (widget.startSingle && widget.initialSourceId != null) {
      _checkedSourceIds
        ..clear()
        ..add(widget.initialSourceId!);
      _mediaServerChecked = false;
      return;
    }
    _checkedSourceIds
      ..clear()
      ..addAll(sources.map((s) => s.id));
    _mediaServerChecked = widget.sourceType == SourceType.animeSource;
  }

  Future<void> _doSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      if (mounted) {
        setState(() {
          _results = const <MediaItem>[];
          _resultIds.clear();
          _loading = false;
          _needSource = false;
          _sourcesWithMore.clear();
        });
      }
      return;
    }

    final sourceRepo = context.read<SourceRepository>();
    final sources = sourceRepo.byType(widget.sourceType);
    _ensureSelectionInit(sources);
    final checked =
        sources.where((s) => _checkedSourceIds.contains(s.id)).toList();
    final bool mediaServerActive =
        widget.sourceType == SourceType.animeSource && _mediaServerChecked;
    // 一个源都没勾选（且媒体服务器未勾选）：提示先勾选，不发起请求。
    if (checked.isEmpty && !mediaServerActive) {
      if (mounted) {
        setState(() {
          _results = const <MediaItem>[];
          _resultIds.clear();
          _loading = false;
          _needSource = true;
          _sourcesWithMore.clear();
        });
      }
      return;
    }
    final int gen = ++_searchGen;
    // 本地内容（导入 + 已下载）即时匹配，先入列表；网络结果由各源
    // 并发检索、先完成先并入（_runSourceSearch）。
    final localResults = _searchLocalContent(trimmed);
    setState(() {
      _loading = checked.isNotEmpty;
      _needSource = false;
      _page = 1;
      _networkKeyword = null;
      _sourcesWithMore.clear();
      _results = List<MediaItem>.of(localResults);
      _resultIds
        ..clear()
        ..addAll(localResults.map((e) => e.id));
    });
    if (checked.isEmpty) return;
    // 简繁兜底仅在勾选单个源时启用（与原单源搜索口径一致）。
    final bool cnFallback = checked.length == 1;
    await Future.wait(<Future<int>>[
      for (final source in checked)
        _runSourceSearch(
          source,
          trimmed,
          gen,
          page: 1,
          cnFallback: cnFallback,
        ),
    ]);
    if (!mounted || gen != _searchGen) return;
    setState(() => _loading = false);
  }

  /// 单个源的一次检索（第 [page] 页）：完成后立即把结果并入列表并刷新，
  /// 实现多源结果「逐源同步展示」而非全部搜完才显示。返回本次新增条数。
  ///
  /// 过期搜索（代际不符）的结果直接丢弃，不污染当前列表。
  Future<int> _runSourceSearch(
    PluginConfig source,
    String keyword,
    int gen, {
    required int page,
    bool cnFallback = false,
  }) async {
    try {
      List<MediaItem> items = await _fetchSourcePage(source, keyword, page);
      // 简繁兜底：单源首搜为空时，用简↔繁互转关键词再试一次；命中则后续
      // 翻页沿用转换后关键词（_networkKeyword），避免翻页与首搜错位。
      if (cnFallback && page == 1 && items.isEmpty) {
        final alt = _alternativeChineseKeyword(keyword);
        if (alt != null && alt != keyword) {
          final retried = await _fetchSourcePage(source, alt, page);
          if (retried.isNotEmpty) {
            items = retried;
            if (gen == _searchGen) _networkKeyword = alt;
          }
        }
      }
      if (!mounted || gen != _searchGen) return 0;
      int added = 0;
      setState(() {
        if (page == 1) {
          if (items.isNotEmpty && _sourcePaged(source)) {
            _sourcesWithMore.add(source.id);
          }
        } else if (items.isEmpty) {
          _sourcesWithMore.remove(source.id);
        }
        final fresh =
            items.where((it) => !_resultIds.contains(it.id)).toList();
        added = fresh.length;
        _resultIds.addAll(fresh.map((e) => e.id));
        _results = <MediaItem>[..._results, ...fresh];
      });
      return added;
    } catch (_) {
      // 单个源失败不影响其他源。
      return 0;
    }
  }

  /// 该源的搜索路由 URL 是否声明了 `{page}` 占位符。
  /// 只有声明了的源才参与「加载更多」，避免对无分页源重复拉同一页。
  bool _sourcePaged(PluginConfig source) => source.routes.entries.any(
        (r) =>
            r.key.toLowerCase().contains('search') &&
            r.value.url.contains('{page}'),
      );

  /// 滚动触底追加下一页：仍可能有下一页的源并发拉取，结果逐源并入。
  Future<void> _loadMore() async {
    if (_loadingMore || _loading || _sourcesWithMore.isEmpty) return;
    final sourceRepo = context.read<SourceRepository>();
    final targets = sourceRepo
        .byType(widget.sourceType)
        .where((s) =>
            _checkedSourceIds.contains(s.id) &&
            _sourcesWithMore.contains(s.id))
        .toList();
    if (targets.isEmpty) return;
    // 简繁兜底命中后，后续翻页沿用转换后的关键词（见首搜处的 _networkKeyword 赋值）。
    final keyword = _networkKeyword ?? _controller.text.trim();
    if (keyword.isEmpty) return;
    setState(() => _loadingMore = true);
    final int gen = _searchGen;
    final int next = _page + 1;
    final counts = await Future.wait(<Future<int>>[
      for (final source in targets)
        _runSourceSearch(source, keyword, gen, page: next),
    ]);
    if (!mounted || gen != _searchGen) return;
    setState(() {
      _loadingMore = false;
      // 各源第 next 页都为空（无新增）→ 停止翻页；否则记录页码继续。
      if (counts.fold<int>(0, (a, b) => a + b) > 0) _page = next;
    });
  }

  /// 单源搜索简繁兜底：返回 [kw] 的简↔繁互转变体；若与原文相同（纯 ASCII/
  /// 已统一）则返回 null（无需再搜一次，避免无谓加压）。
  String? _alternativeChineseKeyword(String kw) {
    if (kw.isEmpty) return null;
    final trad = convertChinese(kw, ChineseConvertMode.simplifiedToTraditional);
    if (trad != kw) return trad;
    final simp = convertChinese(kw, ChineseConvertMode.traditionalToSimplified);
    if (simp != kw) return simp;
    return null;
  }

  /// 拉取单个源第 [page] 页的搜索结果。
  ///
  /// 只负责一个源，由 [_runSourceSearch] 并发调度并逐源展示。字段路由、
  /// 直达地址、验证重试等口径与原跨源循环实现一致；直达地址与验证抽取
  /// 到的真实地址只在该源内部流转，不外溢到其他源。
  Future<List<MediaItem>> _fetchSourcePage(
    PluginConfig source,
    String keyword,
    int page,
  ) async {
    // 翻页请求：未声明 {page} 的源第 2 页起跳过（重复拉第 1 页毫无意义）。
    if (page > 1 && !_sourcePaged(source)) return const <MediaItem>[];
    final mediaService = context.read<MediaApiService>();
    String? extractedUrl = widget.extractedUrl;
    String? renderedHtml;
    // 字段路由选择：选了字段时，按候选路由名依次探测该源声明了哪个源端字段
    // 路由（同时兼容两套命名：searchByAuthor / authorSearch 等，方便社区源自由
    // 命名而无需改应用）。命中则走源端字段检索（服务端已按字段过滤，直接采用）；
    // 都未命中则回退通用 search，并在下方做客户端按字段收窄。
    final String? searchField = _searchField;
    final List<String> routeCandidates = searchField == null
        ? const <String>['search']
        : _routeKeysForField(searchField);
    String routeKey = 'search';
    bool usedFieldRoute = false;
    if (searchField != null) {
      for (final cand in routeCandidates) {
        if (source.routes.containsKey(cand)) {
          routeKey = cand;
          usedFieldRoute = cand != 'search';
          break;
        }
      }
    }
    // 直达模式：调用方已给真实页面地址，强制走该源的字段路由（如
    // authorSearch / tagSearch），并信任其返回结果、跳过客户端收窄。
    if (extractedUrl != null && extractedUrl.isNotEmpty) {
      final fieldRouteCandidates = searchField != null
          ? _routeKeysForField(searchField)
          : const <String>['search'];
      for (final cand in fieldRouteCandidates) {
        if (source.routes.containsKey(cand)) {
          routeKey = cand;
          break;
        }
      }
      usedFieldRoute = true;
    }
    List<MediaItem> narrow(List<MediaItem> items) {
      // 走了源端字段路由（如 authorSearch / tagSearch）时，服务端已按字段
      // 检索，直接采用返回结果；仅当回退到通用 search 时才在客户端按字段收窄，
      // 且收窄为空则回退原关键词结果（非破坏性），避免"检索无结果"的错觉。
      if (searchField != null && !usedFieldRoute) {
        final filtered = items
            .where((it) => it.matchesQuery(keyword, field: searchField))
            .toList();
        return filtered.isEmpty ? items : filtered;
      }
      return items;
    }

    try {
      final items = await mediaService.fetchApiResults(
        source,
        routeKey,
        extractedUrl: extractedUrl,
        renderedHtml: renderedHtml,
        vars: <String, String>{
          'keyword': keyword,
          'page': '$page',
        },
      );
      return narrow(items);
    } catch (e) {
      if (!VerificationNavigator.isVerificationError(e)) {
        // 单个源失败不影响其他源。
        return const <MediaItem>[];
      }
      if (!mounted) return const <MediaItem>[];
      // 验证异常：跳验证后重试该源（验证弹窗经串行链排队，避免并发多源
      // 同时命中验证时弹窗叠加）。
      List<MediaItem> retryItems = const <MediaItem>[];
      final bool handled = await _serializeVerification<bool>(() {
        return VerificationNavigator.handleVerificationAndRetry(
          context,
          e,
          () async {
            final retried = await mediaService.fetchApiResults(
              source,
              routeKey,
              extractedUrl: extractedUrl,
              renderedHtml: renderedHtml,
              vars: <String, String>{
                'keyword': keyword,
                'page': '$page',
              },
            );
            retryItems = narrow(retried);
          },
          verifyHandler: handleVerificationRequest,
          onExtracted: (url) => extractedUrl = url,
          onRenderedHtml: (html) => renderedHtml = html,
        );
      });
      // 验证未通过：该源无结果，不影响其他源。
      return handled ? retryItems : const <MediaItem>[];
    }
  }

  /// 验证弹窗串行链：同一时刻只处理一个验证弹窗，处理完再放行下一个。
  Future<T> _serializeVerification<T>(Future<T> Function() action) {
    final Future<void> prev = _verificationChain;
    final Completer<void> gate = Completer<void>();
    _verificationChain = gate.future;
    return prev.then((_) => action()).whenComplete(() => gate.complete());
  }

  /// 搜索字段 → 源端路由键映射。
  ///
  /// 源若声明了对应 `searchByXxx` 路由，搜索页/详情页就会直接调用它，
  /// 实现真正的源端按字段检索（而非仅客户端过滤）。未知字段回退通用 `search`。
  // 每个字段返回一组候选源端路由名（按优先级）。同时兼容两套命名习惯：
  // 规范名 searchByXxx 与社区常见的 xxxSearch，方便不同来源的源无需改应用即可命中。
  static List<String> _routeKeysForField(String field) {
    switch (field) {
      case 'author':
        return const <String>['searchByAuthor', 'authorSearch'];
      case 'tags':
        return const <String>['searchByTag', 'tagSearch'];
      case 'director':
        return const <String>['searchByDirector', 'directorSearch'];
      case 'actors':
        return const <String>['searchByActor', 'actorSearch'];
      case 'title':
        return const <String>['searchByWork', 'workSearch'];
      default:
        return const <String>['search'];
    }
  }

  /// 本地内容搜索：导入记录 + 已下载作品，按标题/作者匹配关键词，
  /// 转成与网络结果同构的 [MediaItem]（extra 携带 localPath/filePaths，
  /// 供调用方本地打开）。与网络搜索的匹配语义一致（忽略大小写与空白）。
  /// 小说模块额外做繁简双向归一：关键词与标题统一转简体后比对，
  /// 繁体关键词也能命中简体书名，反之亦然。
  List<MediaItem> _searchLocalContent(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const <MediaItem>[];
    final qNorm = q.replaceAll(RegExp(r'\s+'), '');
    final bool isNovel = widget.sourceType == SourceType.novelSource;
    // 双向归一基准：查询转简体后的规范化形式（仅小说模块使用）。
    final String? qSimp = isNovel
        ? convertChinese(q, ChineseConvertMode.traditionalToSimplified)
            .toLowerCase()
            .replaceAll(RegExp(r'\s+'), '')
        : null;

    bool titleMatches(String title) {
      final normTitle = title.toLowerCase().replaceAll(RegExp(r'\s+'), '');
      if (normTitle.contains(qNorm)) return true;
      if (qSimp == null || qSimp.isEmpty || qSimp == qNorm) return false;
      final titleSimp = convertChinese(
              title, ChineseConvertMode.traditionalToSimplified)
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), '');
      return titleSimp.contains(qSimp);
    }

    final results = <MediaItem>[];

    // 1. 导入的本地内容（按模块映射可搜 kind；漫画含 images 与 pdf）。
    final kinds = _kindsForSourceType(widget.sourceType);
    final localManager = context.read<LocalContentManager>();
    for (final e in localManager.items) {
      if (!kinds.contains(e.kind)) continue;
      if (!titleMatches(e.title)) continue;
      results.add(MediaItem(
        id: e.id,
        title: e.title,
        author: e.author,
        coverUrl: e.coverUrl,
        sourceId: '',
        sourceType: widget.sourceType,
        extra: <String, dynamic>{
          'isLocal': true,
          'localPath': e.path,
          'localKind': e.kind.name,
          'filePaths': e.filePaths,
        },
      ));
    }

    // 2. 已下载作品（同源同内容合并取最新批次，与书架「本地」段一致）。
    final downloadManager = context.read<DownloadManager>();
    final byContent = <String, DownloadTask>{};
    for (final t in downloadManager.completedTasks) {
      if (t.sourceType != widget.sourceType) continue;
      if (!titleMatches(t.title)) continue;
      final key = '${t.sourceId ?? ''}|${t.contentId}';
      final prev = byContent[key];
      if (prev == null || t.createdAt >= prev.createdAt) byContent[key] = t;
    }
    for (final t in byContent.values) {
      results.add(MediaItem(
        id: t.contentId,
        title: t.title,
        coverUrl: t.localCoverPath ?? t.coverUrl,
        sourceId: t.sourceId,
        sourceType: widget.sourceType,
        extra: <String, dynamic>{
          'isLocal': true,
          if (t.localPath != null && t.localPath!.isNotEmpty)
            'localPath': t.localPath,
          'localKind': _kindForFormat(t.format)?.name,
          if (t.chapterFilePaths != null && t.chapterFilePaths!.isNotEmpty)
            'filePaths': t.chapterFilePaths!,
        },
      ));
    }
    return results;
  }

  /// 模块类型 → 可搜索的本地媒体 kind（与书架「本地」段口径一致）。
  static List<LocalMediaKind> _kindsForSourceType(SourceType type) =>
      switch (type) {
        SourceType.mangaSource => [LocalMediaKind.images, LocalMediaKind.pdf],
        SourceType.novelSource => [LocalMediaKind.text],
        SourceType.animeSource => [LocalMediaKind.video],
      };

  /// 下载格式 → 本地媒体 kind（null 表示该格式无本地阅读路径）。
  static LocalMediaKind? _kindForFormat(DownloadFormat f) => switch (f) {
        DownloadFormat.cbz => LocalMediaKind.images,
        DownloadFormat.folder => LocalMediaKind.images,
        DownloadFormat.jpg => LocalMediaKind.images,
        DownloadFormat.png => LocalMediaKind.images,
        DownloadFormat.epub => LocalMediaKind.text,
        DownloadFormat.txt => LocalMediaKind.text,
        DownloadFormat.video => LocalMediaKind.video,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // 布局切换已移入 header 区域（显眼分段按钮），AppBar 不再放图标。
    return ModuleSearchScreen(
      title: widget.title,
      searchController: _controller,
      onQueryChanged: _doSearch,
      hint: l10n.search,
      isGrid: _grid,
      onLayoutChanged: (v) {
        setState(() => _grid = v);
      },
      gridTooltip: l10n.gridView,
      listTooltip: l10n.listView,
      layoutButton: const LayoutPickerButton(),
      results: _buildResults(context, l10n),
      sourceType: widget.sourceType,
      header: _buildHeader(context, l10n),
      // 无痕模式：仅勾选单个源且该源已开启无痕时跳过搜索历史记录；
      // 多源/媒体服务器搜索恒记录。
      shouldRecordSearch: () {
        final checked = context
            .read<SourceRepository>()
            .byType(widget.sourceType)
            .where((s) => _checkedSourceIds.contains(s.id))
            .toList();
        if (checked.length == 1 &&
            ConfigLoader.instance.isIncognito(checked.first)) {
          return false;
        }
        return true;
      },
    );
  }

  /// 搜索页头部控件（与搜索框 padding 一致）。
  ///
  /// 行1：源勾选条 [ 全选/全不选 | 各源勾选 chip | 媒体服务器（仅影视） ]
  ///      —— 不再区分聚合/单源，勾选了哪些源就搜哪些源；
  /// 行2：字段筛选胶囊(全部/标签/作者/导演/主演/作品)。
  Widget _buildHeader(BuildContext context, AppLocalizations l10n) {
    final sourceRepo = context.read<SourceRepository>();
    final sources = sourceRepo.byType(widget.sourceType);
    _ensureSelectionInit(sources);
    final bool hasMediaServer = widget.sourceType == SourceType.animeSource;
    final int itemCount = sources.length + 1 + (hasMediaServer ? 1 : 0);

    return Padding(
      // 与搜索框的 EdgeInsets.symmetric(horizontal: spaceLg) 完全对齐
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ── 行1：源勾选条（桌面端滚轮/拖动可横滚）──
          SizedBox(
            height: 40,
            child: Listener(
              onPointerSignal: (signal) {
                if (signal is PointerScrollEvent &&
                    _sourceScrollController.hasClients) {
                  final offset = signal.scrollDelta.dx;
                  if (offset != 0) {
                    _sourceScrollController.jumpTo(
                      (_sourceScrollController.offset - offset).clamp(
                        0,
                        _sourceScrollController.position.maxScrollExtent,
                      ),
                    );
                  }
                }
              },
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: <PointerDeviceKind>{
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                    PointerDeviceKind.stylus,
                  },
                ),
                child: ListView.separated(
                  controller: _sourceScrollController,
                  scrollDirection: Axis.horizontal,
                  itemCount: itemCount,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppTokens.spaceXs),
                  itemBuilder: (_, i) {
                    if (i == 0) return _selectAllChip(l10n, sources);
                    final int idx = i - 1;
                    if (hasMediaServer && idx == sources.length) {
                      return _mediaServerChip(l10n);
                    }
                    final s = sources[idx];
                    return FilterChip(
                      key: (widget.startSingle &&
                              s.id == widget.initialSourceId)
                          ? _selectedSourceKey
                          : null,
                      label: Text(s.name),
                      selected: _checkedSourceIds.contains(s.id),
                      onSelected: (bool value) {
                        AppHaptics.selectionClick();
                        setState(() {
                          if (value) {
                            _checkedSourceIds.add(s.id);
                          } else {
                            _checkedSourceIds.remove(s.id);
                          }
                        });
                        _doSearch(_controller.text);
                      },
                    );
                  },
                ),
              ),
            ),
          ),

          // ── 行2：字段筛选胶囊（按模块类型显示对应字段）──
          // 小说/漫画：标签 + 作者（无导演/主演概念）
          // 媒体（影视）：标签 + 导演 + 主演（无"作者"概念）
          const SizedBox(height: AppTokens.spaceSm),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _fieldEntries(l10n).length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: AppTokens.spaceXs),
              itemBuilder: (_, i) {
                final entry = _fieldEntries(l10n)[i];
                return _fieldPill(entry.$1, entry.$2);
              },
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
        ],
      ),
    );
  }

  /// 「全选 / 全不选」快捷 chip：一键勾选/清空全部源（含媒体服务器）。
  Widget _selectAllChip(AppLocalizations l10n, List<PluginConfig> sources) {
    final bool allChecked =
        _checkedSourceIds.containsAll(sources.map((s) => s.id)) &&
            (widget.sourceType != SourceType.animeSource ||
                _mediaServerChecked);
    return ActionChip(
      label: Text(allChecked ? l10n.deselectAll : l10n.selectAll),
      onPressed: () {
        AppHaptics.selectionClick();
        setState(() {
          if (allChecked) {
            _checkedSourceIds.clear();
            _mediaServerChecked = false;
          } else {
            _checkedSourceIds
              ..clear()
              ..addAll(sources.map((s) => s.id));
            if (widget.sourceType == SourceType.animeSource) {
              _mediaServerChecked = true;
            }
          }
        });
        _doSearch(_controller.text);
      },
    );
  }

  /// 媒体服务器源 chip（仅影视模块）：作为可选源与普通源并列，勾选才参与
  /// 搜索，不再无条件插入结果顶部。
  Widget _mediaServerChip(AppLocalizations l10n) {
    return FilterChip(
      avatar: const Icon(Icons.dns_rounded, size: 16),
      label: Text(l10n.mediaServerSettings),
      selected: _mediaServerChecked,
      onSelected: (bool value) {
        AppHaptics.selectionClick();
        setState(() => _mediaServerChecked = value);
        _doSearch(_controller.text);
      },
    );
  }

  Widget _fieldPill(String label, String? field) {
    final selected = _searchField == field;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        AppHaptics.selectionClick();
        setState(() => _searchField = field);
        _doSearch(_controller.text);
      },
    );
  }

  /// 按模块类型返回字段筛选胶囊列表。
  ///
  /// - 小说/漫画：全部 / 标签 / 作者 / 作品（无导演/主演概念）
  /// - 媒体（影视）：全部 / 标签 / 导演 / 主演 / 作品（无"作者"概念）
  List<(String, String?)> _fieldEntries(AppLocalizations l10n) {
    // 基础项：全部 + 标签 + 作品
    final base = <(String, String?)>[
      (l10n.allLabel, null),
      (l10n.tagLabel, 'tags'),
    ];
    switch (widget.sourceType) {
      case SourceType.novelSource:
      case SourceType.mangaSource:
        return <(String, String?)>[
          ...base,
          (l10n.searchFieldAuthor, 'author'),
          (l10n.searchFieldWork, 'title'),
        ];
      case SourceType.animeSource:
        return <(String, String?)>[
          ...base,
          (l10n.searchFieldDirector, 'director'),
          (l10n.searchFieldActor, 'actors'),
          (l10n.searchFieldWork, 'title'),
        ];
    }
  }

  Widget _buildResults(BuildContext context, AppLocalizations l10n) {
    if (_needSource) {
      return AppEmptyState(
          icon: Icons.source_rounded, message: l10n.searchSelectSource);
    }

    Widget mainBody;
    if (_results.isEmpty) {
      // 搜索中且尚无任何结果 → 全屏加载；全部源落定仍为空 → 空态。
      mainBody = _loading
          ? const Center(child: AppLoadingIndicator())
          : AppEmptyState(
              icon: Icons.search_rounded, message: l10n.emptySearch);
    } else {
      // 结果逐源到达即插入列表；仍有源在搜/翻页追加时底部细进度条提示。
      mainBody = NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (_sourcesWithMore.isNotEmpty &&
              !_loading &&
              !_loadingMore &&
              n.metrics.extentAfter < 400 &&
              n.metrics.maxScrollExtent > 0) {
            _loadMore();
          }
          return false;
        },
        child: Column(
          children: <Widget>[
            Expanded(child: _grid ? _buildGrid(context) : _buildList(context)),
            if (_loading || _loadingMore)
              const LinearProgressIndicator(minHeight: 2),
          ],
        ),
      );
    }

    // 影视模块：媒体服务器作为可选源参与搜索——勾选才在结果顶部展示该段。
    if (widget.sourceType != SourceType.animeSource || !_mediaServerChecked) {
      return mainBody;
    }
    final query = _convText(_controller.text).trim();
    if (query.isEmpty) return mainBody;
    return Column(
      children: <Widget>[
        MediaServerSearchSection(query: query),
        Expanded(child: mainBody),
      ],
    );
  }

  Widget _buildGrid(BuildContext context) {
    final layout = LayoutSettingsStore.instance.settings;
    final l10n = AppLocalizations.of(context);
    final cross = layout.gridColumns;
    final spacing = layout.gridSpacing;
    final width = MediaQuery.of(context).size.width;
    final itemW =
        (width - AppTokens.spaceLg * 2 - spacing * (cross - 1)) / cross;

    // 文本区高度：标题(可多行) + 作者 + 进度条 + 来源 + 间距，避免裁切/溢出。
    // 网格间距/圆角/字号/标题行数/作者/进度均同步跟随全局布局设置。
    final double textH =
        (layout.showTitle ? layout.titleMaxLines * (layout.titleFontSize + 6) : 0.0) +
        (layout.showAuthor ? 18.0 : 0.0) +
        (layout.showProgress && layout.progressDisplay == ProgressDisplayMode.bar
            ? 9.0
            : 0.0) +
        14.0 + // 来源(meta) 通常存在
        12.0; // 间距

    return GridView.builder(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cross,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        childAspectRatio: itemW / (itemW / AppTokens.coverAspectRatio + textH),
      ),
      itemCount: _results.length,
      itemBuilder: (_, i) {
        final item = _results[i];
        final source =
            context.read<SourceRepository>().getById(item.sourceId ?? '');
        final String progKey = '${item.id}#${layout.showProgress}';
        final future = _progressFutures.putIfAbsent(
          progKey,
          () => layout.showProgress
              ? _computeProgress(item)
              : Future<double?>.value(null),
        );
        // 本地结果（导入/下载）无在线源，meta 显示「本地」标识。
        final bool isLocal = item.extra?['isLocal'] == true;
        return FutureBuilder<double?>(
          future: future,
          builder: (ctx, snap) => ContentCard(
            coverUrl: item.coverUrl,
            source: source,
            title: _convText(item.title),
            subtitle: _convText(item.author),
            meta: isLocal ? l10n.subTabLocal : source?.name,
            progress: snap.data,
            width: itemW,
            heroTag: 'search-${item.id}',
            highlightQuery: _convText(_controller.text),
            onTap: () => widget.onItemTap(item, 'search-${item.id}'),
          ),
        );
      },
    );
  }

  Widget _buildList(BuildContext context) {
    final layout = LayoutSettingsStore.instance.settings;
    final l10n = AppLocalizations.of(context);
    final isCompact = layout.listStyle == ListLayoutStyle.compact;
    return ListView.separated(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppTokens.spaceMd),
      itemBuilder: (_, i) {
        final item = _results[i];
        final source =
            context.read<SourceRepository>().getById(item.sourceId ?? '');
        final bool isLocal = item.extra?['isLocal'] == true;
        return AppCard(
          onTap: () => widget.onItemTap(item, 'search-${item.id}-list'),
          padding: EdgeInsets.zero,
          child: ListTile(
            contentPadding: EdgeInsets.symmetric(
              horizontal: AppTokens.spaceMd,
              vertical: isCompact ? AppTokens.spaceXs : AppTokens.spaceSm,
            ),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(layout.coverRadius.toDouble()),
              child: SizedBox(
                width: isCompact ? 40 : 56,
                height: isCompact ? 56 : 78,
                child: AppCoverImage(
                  coverUrl: item.coverUrl,
                  source: source,
                  title: item.title,
                  width: isCompact ? 40 : 56,
                  height: isCompact ? 56 : 78,
                  heroTag: 'search-${item.id}-list',
                  radius: layout.coverRadius,
                ),
              ),
            ),
            title: layout.showTitle
                ? HighlightText(
                    text: _convText(item.title),
                    query: _convText(_controller.text),
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(fontSize: layout.titleFontSize),
                    maxLines: layout.titleMaxLines,
                    overflow: TextOverflow.ellipsis,
                  )
                : null,
            subtitle: layout.showAuthor
                ? Text(
                    <String?>[
                      _convText(item.author),
                      if (isLocal) l10n.subTabLocal else source?.name,
                    ].where((s) => s != null && s.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  )
                : null,
            trailing: layout.showProgress
                ? FutureBuilder<double?>(
                    future: _progressFutures.putIfAbsent(
                      '${item.id}#list',
                      () => _computeProgress(item),
                    ),
                    builder: (ctx, snap) {
                      final double? p = snap.data;
                      if (p == null || p <= 0) {
                        return const SizedBox.shrink();
                      }
                      return Text(
                        '${(p * 100).round()}%',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      );
                    },
                  )
                : const Icon(Icons.chevron_right_rounded),
            onTap: () => widget.onItemTap(item, 'search-${item.id}-list'),
          ),
        );
      },
    );
  }

  /// 计算某内容的进度值（0.0..1.0），供列表/网格「显示进度」开关使用。
  ///
  /// 与 online_content_list_screen 逻辑一致：影视用已看集数比例，小说/漫画用
  /// 已读章节占比；未缓存总章数时以极小进度标记「已开始」。
  Future<double?> _computeProgress(MediaItem item) async {
    final SourceType? type = item.sourceType;
    if (type == SourceType.animeSource) {
      try {
        final watchedMgr = context.read<MediaWatchedManager>();
        final watched = watchedMgr.watchedCount(item.id);
        if (watched > 0 &&
            item.episodeCount != null &&
            item.episodeCount! > 0) {
          return (watched / item.episodeCount!).clamp(0.0, 1.0);
        }
      } on Object {/* 忽略 */}
    }
    if (type == SourceType.novelSource) {
      try {
        final p = await NovelProgressManager().get(item.id);
        if (p != null) {
          if (p.totalChapters != null && p.totalChapters! > 0) {
            return ((p.chapterIndex + 1) / p.totalChapters!)
                .clamp(0.0, 1.0);
          }
          if (p.chapterIndex > 0) return 0.02;
        }
      } on Object {/* 忽略 */}
    }
    if (type == SourceType.mangaSource) {
      try {
        final p = await ComicProgressManager().get(item.id);
        if (p != null) {
          if (p.totalChapters != null && p.totalChapters! > 0) {
            return ((p.chapterIndex + 1) / p.totalChapters!)
                .clamp(0.0, 1.0);
          }
          if (p.chapterIndex > 0) return 0.02;
        }
      } on Object {/* 忽略 */}
    }
    return null;
  }
}
