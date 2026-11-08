/// 统一内容详情页（详情页重构 Phase 4）。
///
/// 重构前存在三套几乎逐字重复的详情页：
///
/// * `ContentDetailScreen`（影视 / 动漫）
/// * `ComicDetailScreen`（漫画）
/// * `NovelDetailScreen`（小说）
///
/// 三者共 3530 行，差异只有「进度来源 / 书签 / 少量元信息 chip / 少量入口」。
/// 本文件把它们合并为**唯一详情页**，模块差异通过下面两个维度表达：
///
/// 1. [UnifiedProgressRepository] / [UnifiedBookmarkRepository]：按 [SourceType]
/// 分发的进度与书签抽象（见 `core/progress`、`core/bookmark`）。
/// 2. 页内能力开关（[_isAnime] / [_isManga] / [_isNovel]）：控制线路分组、
/// 网格选集、播放位置、渐进目录、TOC 缓存等模块特有行为。
///
/// UI 骨架改用 [ContentDetailTabbedShell]：Hero 大图（滚动收起 + 吸顶）→
/// 标签页（详情 / Bangumi / 选集 / 评论 / 推荐）→ 标签内容。
/// 主操作（续看 / 续读）上移为 Hero 浮层，首屏即可触达。
///
/// 能力对账（重构前 → 重构后一项未减）：
/// 收藏 / 取消收藏 / 收藏后分组、下载（批量弹窗 + 单集）、分享、刷新元数据、
/// 设为书架封面、打开下载管理、封面大图、更新时间、连载状态、题材标签、
/// 导演 / 演员折叠、作者（真实链接优先）、字数、更新至 N 章、系列入口、
/// 续看 / 续读 / 从头开始、已读标记、章节书签、选集筛选排序 / 网格、
/// 播放位置回显、线路分组、Bangumi 卡、评论区、相关推荐、下拉刷新、
/// 验证拦截引导、渲染后抽取（webview-html）、TOC 缓存兜底、渐进目录。
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/bookmark/unified_bookmark_repository.dart';
import '../../../core/download/download_manager.dart';
import '../../../core/download/download_task.dart' show DownloadStatus;
import '../../../core/services/novel_export_upload_service.dart';
import '../../../core/favorites/favorites_manager.dart';
import '../../../core/history/history_manager.dart';
import '../../../core/history/media_watched_manager.dart';
import '../../../core/models/episode.dart';
import '../../../core/models/media_item.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/navigation/app_page_route.dart';
import '../../../core/novel/novel_toc_cache.dart';
import '../../../core/novel/novel_toc_store.dart';
import '../../../core/platform/ohos_public_storage.dart'
    show OhosPublicStorage, isOhosDocPath;
import '../../../core/progress/unified_progress_repository.dart';
import '../../../core/resolver/webview_resolver.dart';
import '../../../core/settings/detail_appearance_settings.dart';
import '../../../core/settings/general_settings.dart';
import '../../../core/services/bangumi/bangumi_sync_service.dart';
import '../../../core/scraper/media_api_service.dart';
import '../../../core/scraper/verification_detector.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/image_accent_extractor.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/app_cover_image.dart';
import '../../../core/widgets/app_error_state.dart';
import '../../../core/widgets/bangumi_full_tab.dart';
import '../../../core/widgets/chapter_list_section.dart';
import '../../../core/widgets/comments_tabbed_section.dart';
import '../../../core/widgets/content_card.dart';
import '../../../core/widgets/content_detail_tabbed_shell.dart';
import '../../../core/widgets/detail_action_utils.dart';
import '../../../core/widgets/download_selection_sheet.dart';
import '../../../core/widgets/favorite_group_assign_sheet.dart';
import '../../../core/widgets/module_source_search_screen.dart';
import '../../../core/widgets/progress_card.dart';
import '../../../core/widgets/translatable_text.dart';
import '../../../core/widgets/source_url_browse_screen.dart';
import '../../../core/widgets/web_favorite_action.dart';
import '../../downloads/presentation/download_list_screen.dart';
import '../../manga/presentation/comic_reader_screen.dart';
import '../../novel/presentation/novel_reader_screen.dart';
import '../../player/presentation/video_player_screen.dart';
import '../../verification/presentation/webview_verification_screen.dart';
import 'series_detail_screen.dart';

/// 唯一内容详情页（动漫 / 影视 / 漫画 / 小说共用）。
class ContentDetailScreen extends StatefulWidget {
  final MediaItem item;
  final String? heroTag;

  /// 双栏详情栏内嵌模式（平板 / 桌面宽窗口）：true 时不作为整页路由存在——
  /// 返回钮与自身 pop 改为回调 [onClose]（宿主收起右栏），系统返回由宿主
  /// 的 PopScope 先行拦截。默认 false 保持整页路由行为。
  final bool embedded;
  final VoidCallback? onClose;

  const ContentDetailScreen({
    super.key,
    required this.item,
    this.heroTag,
    this.embedded = false,
    this.onClose,
  });

  @override
  State<ContentDetailScreen> createState() => _ContentDetailScreenState();
}

class _ContentDetailScreenState extends State<ContentDetailScreen> {
  // ───────────────────────── 数据状态 ─────────────────────────

  /// 关闭详情页：整页路由时 pop（原行为）；双栏内嵌时回调宿主收起右栏。
  void _closeSelf() {
    if (widget.onClose != null) {
      widget.onClose!();
      return;
    }
    Navigator.of(context).maybePop();
  }


  late Future<List<Episode>> _episodesFuture;

  /// 当前应渲染的章节 / 剧集列表。小说走渐进加载时可能先于 Future 完成填充。
  List<Episode> _chapters = const <Episode>[];

  /// 目录是否仍在后台渐进加载（仅小说源会为 true）。
  bool _chaptersLoading = false;

  /// 当前 [_chapters] 是否来自 TOC 缓存兜底（仅小说源）。
  bool _chaptersFromCache = false;

  Future<List<MediaItem>>? _recommendationsFuture;

  /// 验证异常（非 null 时按数据完整度决定「全屏门」还是「警告条」）。
  VerificationRequiredException? _verificationError;

  /// 渲染后抽取请求（webview-html 模式）。
  WebViewHtmlRequest? _htmlCaptureRequest;

  /// 渲染后回灌的整页 HTML（重试抓取时复用源选择器解析）。
  String? _renderedHtml;

  /// detail 路由拉回的完整条目；初始为 [widget.item]。
  late MediaItem _fetchedDetail;

  /// 续读 / 续看索引（-1 表示无记录）。
  int _continueIndex = -1;

  /// 已加书签的章节索引集合（漫画 / 小说）。
  final Set<int> _bookmarkedIndices = <int>{};

  /// 当前详情页对应的小说 sourceId / novelId，用于与 [NovelTocStore] 同步目录。
  String? _tocSourceId;
  String? _tocNovelId;

  // ───────────────────────── 抽象与开关 ─────────────────────────

  /// 源真实类型：决定解析路由与页面能力。
  late SourceType _sourceType;

  /// 收藏 / 历史 / 已读的归属类型。
  ///
  /// 优先用条目自带的 `sourceType`——收藏与历史入库时用的就是它，
  /// 若这里改用源类型会导致「已收藏却查不到」。仅当条目未携带时回退源类型。
  late SourceType _favType;

  late UnifiedProgressRepository _progressRepo;

  /// 章节书签仓库；影视源为 null（无章节书签概念）。
  UnifiedBookmarkRepository? _bookmarkRepo;

  /// Bangumi subjectId 上抛（详情页 Bangumi 标签页解析成功后写入），
  /// 供底栏「同步」按钮按需出现。
  ValueNotifier<int?>? _bangumiSubjectId;

  /// 封面取色控制器（设置 → 详情页外观 → 封面动态强调色）。
  late final DetailAccentController _accentController;

  bool get _isAnime => _sourceType == SourceType.animeSource;
  bool get _isManga => _sourceType == SourceType.mangaSource;
  bool get _isNovel => _sourceType == SourceType.novelSource;
  bool get _isChapterBased => _isManga || _isNovel;

  // 小说渐进目录相关。
  final NovelTocCache _tocCache = NovelTocCache();
  Timer? _chapterThrottleTimer;
  List<Episode> _pendingChapterBatch = const <Episode>[];

  @override
  void initState() {
    super.initState();
    _fetchedDetail = widget.item;
    _resolveTypes();
    _accentController = DetailAccentController();
    _syncAccent();
    _bangumiSubjectId = ValueNotifier<int?>(null);
    _resolveBangumiForSync();
    _progressRepo = UnifiedProgressRepository.of(context, _sourceType);
    _bookmarkRepo = UnifiedBookmarkRepository.forType(_sourceType);
    _load();
    _recordHistory();
    _loadContinueIndex();
    _loadBookmarks();
  }

  @override
  void dispose() {
    _chapterThrottleTimer?.cancel();
    _chapterThrottleTimer = null;
    _bangumiSubjectId?.dispose();
    _accentController.dispose();
    super.dispose();
  }

  /// 当前条目封面变化（初始进入 / detail 回填换封面）后刷新封面取色。
  ///
  /// 「封面或获取的图片」：列表页封面先取色，detail 路由回填了更完整的
  /// 封面后再取一次（结果按 URL 记忆，同一封面不会重复解码）。
  void _syncAccent() {
    final PluginConfig? sourceConfig =
        context.read<SourceRepository>().getById(widget.item.sourceId ?? '');
    _accentController.update(
      coverUrl: _fetchedDetail.coverUrl ?? widget.item.coverUrl,
      source: sourceConfig,
    );
  }

  /// 在上抛 Bangumi subjectId 给底栏「同步」按钮（独立于 Bangumi 标签页，
  /// 保证未访问 Bangumi 标签时按钮也可见）。
  Future<void> _resolveBangumiForSync() async {
    try {
      final svc = Provider.of<BangumiSyncService>(context, listen: false);
      final res = await svc.linkStore.resolve(
        widget.item.id,
        widget.item.title,
        _favType,
      );
      if (mounted && res.link != null) {
        _bangumiSubjectId?.value = res.link!.subjectId;
      }
    } catch (_) {
      // 解析失败不影响主流程；标签页内会再次尝试。
    }
  }

  /// 解析源类型与收藏归属类型。
  void _resolveTypes() {
    SourceType? fromSource;
    final String? sid = widget.item.sourceId;
    if (sid != null && sid.isNotEmpty) {
      try {
        fromSource = context.read<SourceRepository>().getById(sid)?.type;
      } on Object {
        fromSource = null;
      }
    }
    _sourceType =
        fromSource ?? widget.item.sourceType ?? SourceType.animeSource;
    _favType = widget.item.sourceType ?? _sourceType;
  }

  // ───────────────────────── 加载 ─────────────────────────

  void _recordHistory() {
    try {
      context.read<HistoryManager>().addHistory(
            widget.item,
            sourceType: _favType,
          );
    } on Object {
      // HistoryManager 不可用时不影响页面。
    }
  }

  Future<void> _loadContinueIndex() async {
    try {
      final int index = await _progressRepo.loadContinueIndex(widget.item.id);
      if (mounted && index >= 0) {
        setState(() => _continueIndex = index);
      }
    } on Object {
      // 进度读取失败不影响页面。
    }
  }

  Future<void> _loadBookmarks() async {
    final UnifiedBookmarkRepository? repo = _bookmarkRepo;
    if (repo == null) return;
    try {
      final Set<int> indices = await repo.loadIndices(widget.item.id);
      if (mounted) {
        setState(() {
          _bookmarkedIndices
            ..clear()
            ..addAll(indices);
        });
      }
    } on Object {
      // 书签读取失败不影响页面。
    }
  }

  void _load() {
    final SourceRepository repo = context.read<SourceRepository>();
    final MediaApiService service = context.read<MediaApiService>();
    final String? sid = widget.item.sourceId;
    final String id = widget.item.id;
    if (sid == null || sid.isEmpty) {
      _episodesFuture =
          Future<List<Episode>>.error(Exception('item missing source id'));
      return;
    }
    // 记录当前小说的身份，供下方目录更新时写回共享目录源（NovelTocStore）。
    _tocSourceId = sid;
    _tocNovelId = id;
    final PluginConfig? source = repo.getById(sid);
    if (source == null) {
      _episodesFuture =
          Future<List<Episode>>.error(Exception('source not found: $sid'));
      return;
    }

    // 推荐路由：优先 recommend，其次 related；都没有则不渲染推荐标签。
    final String? recommendRoute = source.routes.containsKey('recommend')
        ? 'recommend'
        : (source.routes.containsKey('related') ? 'related' : null);
    _recommendationsFuture = recommendRoute == null
        ? null
        : service.fetchApiResults(
            source,
            recommendRoute,
            vars: <String, String>{'id': id},
          );

    _chapters = const <Episode>[];
    _chaptersFromCache = false;
    _chaptersLoading = _isNovel;

    // 目录 / 剧集抓取：小说额外接入渐进批次回调（超长目录首屏快显）。
    _episodesFuture = switch (_sourceType) {
      SourceType.mangaSource =>
        service.fetchChapters(source, id, renderedHtml: _renderedHtml),
      SourceType.novelSource => service.fetchNovelChapters(
          source,
          id,
          renderedHtml: _renderedHtml,
          onProgress: _throttledChapterBatch,
        ),
      SourceType.animeSource => service.fetchEpisodes(
          source,
          id,
          title: widget.item.title,
          detailUrl: widget.item.detailUrl,
          renderedHtml: _renderedHtml,
        ),
    };

    _episodesFuture.then((List<Episode> list) {
      if (!mounted) return;
      setState(() {
        _chapters = list;
        _chaptersLoading = false;
        _chaptersFromCache = false;
      });
      // 小说：写入 TOC 缓存（fire-and-forget），供下次被验证拦截时兜底；
      // 同时写回共享目录源，使阅读器与详情页目录保持一致。
      if (_isNovel) {
        unawaited(_tocCache.write(sid, id, list));
        _publishToc();
      }
    }).catchError((Object error) {
      if (!mounted) return;
      setState(() => _chaptersLoading = false);
      if (error is WebViewHtmlRequest) {
        setState(() => _htmlCaptureRequest = error);
      } else if (error is VerificationRequiredException) {
        setState(() => _verificationError = error);
      }
      // 小说：当次抓取失败且渐进批次也没抓到 → 读 TOC 缓存兜底回填。
      if (_isNovel && _chapters.isEmpty) {
        unawaited(_backfillFromTocCache(sid, id));
      }
    });

    // detail 路由：补全列表页缺失的元数据。
    if (source.routes.containsKey('detail')) {
      service
          .fetchDetail(
        source,
        id,
        detailUrl: widget.item.detailUrl,
        renderedHtml: _renderedHtml,
      )
          .then((MediaItem detail) {
        if (mounted) {
          setState(() => _fetchedDetail = _mergeDetail(detail));
          _syncAccent();
        }
        // 详情解析出源站更新时间时回填收藏条目，供书架「最新章」排序。
        if (detail.updatedAt != null && mounted) {
          context
              .read<FavoritesManager>()
              .updateUpdatedAt(
                id,
                _favType,
                detail.updatedAt!.millisecondsSinceEpoch,
              );
        }
      }).catchError((Object error) {
        if (!mounted) return;
        if (error is WebViewHtmlRequest) {
          setState(() => _htmlCaptureRequest = error);
        } else if (error is VerificationRequiredException) {
          setState(() => _verificationError = error);
        }
      });
    }
  }

  /// detail 产物与列表条目合并。
  ///
  /// 采集类 API 的 `_itemFromMap` 用 `_s()` 转字段，缺失时得到 `""` 而非
  /// null，`??` 无法兜底。若直接采用 detail 结果，会出现「列表有、进详情
  /// 反而丢」的闪烁。因此逐字段判空回退到列表条目已知值。
  MediaItem _mergeDetail(MediaItem detail) {
    String? pick(String? next, String? fallback) =>
        (next != null && next.isNotEmpty) ? next : fallback;

    return detail.copyWith(
      id: detail.id.isEmpty ? widget.item.id : detail.id,
      sourceId: pick(detail.sourceId, widget.item.sourceId),
      title: detail.title.isEmpty ? widget.item.title : detail.title,
      coverUrl: pick(detail.coverUrl, widget.item.coverUrl),
      description: pick(detail.description, widget.item.description),
      director: pick(detail.director, widget.item.director),
      actors: pick(detail.actors, widget.item.actors),
      author: pick(detail.author, widget.item.author),
      year: pick(detail.year, widget.item.year),
      status: pick(detail.status, widget.item.status),
      wordCount: pick(detail.wordCount, widget.item.wordCount),
      tags: (detail.tags != null && detail.tags!.isNotEmpty)
          ? detail.tags
          : widget.item.tags,
      updatedAt: detail.updatedAt ?? widget.item.updatedAt,
    );
  }

  /// TOC 缓存兜底（仅小说）：回填上次成功抓取的目录。
  Future<void> _backfillFromTocCache(String sourceId, String novelId) async {
    final List<Episode>? cached = await _tocCache.read(sourceId, novelId);
    if (!mounted || cached == null || cached.isEmpty) return;
    // 期间渐进批次 / 重试已有数据，勿覆盖。
    if (_chapters.isNotEmpty) return;
    setState(() {
      _chapters = cached;
      _chaptersFromCache = true;
    });
    _publishToc();
  }

  /// 将当前目录写回共享目录源 [NovelTocStore]，供阅读器侧目录实时同步。
  void _publishToc() {
    if (!mounted) return;
    if (_tocSourceId == null || _tocNovelId == null) return;
    if (!_isNovel) return;
    context.read<NovelTocStore>().setChapters(
      _tocSourceId!,
      _tocNovelId!,
      _chapters,
    );
    // 回写「已见章节数」到收藏条目，书架据此判定/清除新章角标。
    if (_chapters.isNotEmpty) {
      unawaited(context
          .read<FavoritesManager>()
          .updateLastSeenChapters(_tocNovelId!, _favType, _chapters.length));
    }
  }

  /// 从共享目录源取回「更完整」的目录，覆盖当前详情页目录（阅读器侧刷新后回流）。
  void _syncChaptersFromStore() {
    if (!mounted) return;
    if (_tocSourceId == null || _tocNovelId == null) return;
    if (!_isNovel) return;
    final stored = context
        .read<NovelTocStore>()
        .chaptersFor(_tocSourceId!, _tocNovelId!);
    if (stored.length > _chapters.length && mounted) {
      setState(() => _chapters = stored);
    }
  }

  /// 渐进批次节流（仅小说）。
  ///
  /// 超长目录（如 1416 章 / 71 页）每页都会触发 onProgress，逐次 setState
  /// 会导致明显掉帧。这里把批次合并到 300ms 窗口内最多触发一次重建。
  void _throttledChapterBatch(List<Episode> batch) {
    _pendingChapterBatch = <Episode>[..._pendingChapterBatch, ...batch];
    if (_chapterThrottleTimer != null) return;
    _chapterThrottleTimer = Timer(const Duration(milliseconds: 300), () {
      _chapterThrottleTimer = null;
      if (!mounted || _pendingChapterBatch.isEmpty) return;
      final List<Episode> incoming = _pendingChapterBatch;
      _pendingChapterBatch = const <Episode>[];
      setState(() {
        final Map<String, Episode> map = <String, Episode>{
          for (final Episode e in _chapters) e.id: e,
        };
        for (final Episode e in incoming) {
          map[e.id] = e;
        }
        _chapters = map.values.toList();
      });
      _publishToc();
    });
  }

  void _retryAfterVerification() {
    setState(() => _verificationError = null);
    _load();
  }

  Future<void> _retryAfterHtmlCapture(String html) async {
    if (!mounted) return;
    setState(() {
      _htmlCaptureRequest = null;
      _verificationError = null;
      _renderedHtml = html;
    });
    _load();
  }

  void _refreshMetadata() {
    setState(() => _chapters = const <Episode>[]);
    _load();
  }

  Future<void> _onRefresh() async {
    setState(() => _chapters = const <Episode>[]);
    _load();
    try {
      await _episodesFuture;
    } on Object {
      // 错误态由 FutureBuilder / 警告条展示。
    }
  }

  // ───────────────────────── 打开内容 ─────────────────────────

  /// 打开播放器 / 阅读器。
  ///
  /// [restoreProgress]：true 时阅读器恢复上次保存的页/章位置（用于「继续阅读」
  /// 入口）。详情页章节列表点击时为 false（用户明确选择章节，应从该章开始
  /// 翻阅）。漫画之前硬编码 false 导致「继续阅读」永远从章节首页开始，已修复。
  Future<void> _openContent(Episode ep, int index,
      {bool restoreProgress = false}) async {
    final String? sid = widget.item.sourceId;
    if (sid == null || sid.isEmpty) return;
    final String? detailUrl =
        _fetchedDetail.detailUrl ?? widget.item.detailUrl;
    final String? coverUrl = _fetchedDetail.coverUrl ?? widget.item.coverUrl;

    // 全局「记住播放/阅读位置」总开关：关闭时即便从「继续阅读」入口进入也
    // 不恢复进度（从头开始）；明确点选某章节进入时 restoreProgress 本就是
    // false，与全局开关取与后仍为 false，行为不变。
    final bool remember =
        GeneralSettingsStore.instance.settings.rememberPosition;
    final bool effectiveRestore = restoreProgress && remember;

    switch (_sourceType) {
      case SourceType.animeSource:
        // 「已看」由播放器在进度达到阈值时自动标记（见 VideoPlayerScreen），
        // 此处不再进入即标记，避免看几秒便记为已看。
        await Navigator.of(context).push(
          AppPageRoute<void>(
            builder: (_) => VideoPlayerScreen(
              title: widget.item.title,
              episode: ep,
              sourceId: sid,
              itemId: widget.item.id,
              episodes: _chapters.isNotEmpty ? _chapters : null,
              initialEpisodeIndex: index,
              favoriteType: _favType,
              detailUrl: detailUrl,
              coverUrl: coverUrl,
              restoreProgress: remember,
            ),
          ),
        );
      case SourceType.mangaSource:
        await Navigator.of(context).push(
          AppPageRoute<void>(
            builder: (_) => ComicReaderScreen(
              comicId: widget.item.id,
              title: widget.item.title,
              sourceId: sid,
              chapters: _chapters,
              initialChapterIndex: index,
              restoreProgress: effectiveRestore,
              detailUrl: detailUrl,
              coverUrl: coverUrl,
            ),
          ),
        );
      case SourceType.novelSource:
        await Navigator.of(context).push(
          AppPageRoute<void>(
            builder: (_) => NovelReaderScreen(
              novelId: widget.item.id,
              title: widget.item.title,
              sourceId: sid,
              chapters: _chapters,
              initialChapterIndex: index,
              restoreProgress: effectiveRestore,
              detailUrl: detailUrl,
              coverUrl: coverUrl,
            ),
          ),
        );
    }
    // 从阅读器返回后，用共享目录源回流的最新目录刷新详情页（实时同步）。
    if (mounted) _syncChaptersFromStore();
  }

  // ───────────────────────── 收藏 / 下载 / 分享 ─────────────────────────

  Future<void> _toggleFavorite() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final FavoritesManager fav = context.read<FavoritesManager>();
    final bool wasFavorite = fav.isFavorite(widget.item.id, _favType);
    // 显式传入 _favType：脚本源条目缺 sourceType，若让 manager 自行兜底
    // animeSource，会与上方 isFavorite(_favType) 查询的类型不一致，
    // 表现为「详情页点收藏无效」（收藏进了别的书架，图标不亮）。
    await fav.toggleFavorite(widget.item, type: _favType);
    if (!mounted) return;
    if (wasFavorite) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.favoriteRemoved)),
      );
      return;
    }
    // 新增收藏 → 立即弹出分组面板（可直接关闭，留在「未分组」）。
    await showFavoriteGroupAssignSheet(
      context,
      contentId: widget.item.id,
      sourceType: _favType,
    );
  }

  /// 收藏按钮入口：源声明网络收藏时弹「本地/网络」双选项，否则直接本地收藏。
  Future<void> _onFavoritePressed() async {
    final PluginConfig? source =
        context.read<SourceRepository>().getById(widget.item.sourceId ?? '');
    if (source == null) {
      await _toggleFavorite();
      return;
    }
    await showFavoriteSheet(
      context: context,
      source: source,
      item: widget.item,
      toggleLocalFavorite: _toggleFavorite,
    );
  }

  Future<void> _removeFromFavorites() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    await context.read<FavoritesManager>().removeFavorite(
          widget.item.id,
          _favType,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.removeFromFavorites)),
    );
    _closeSelf();
  }

  Future<void> _startDownload() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final DownloadManager dl = context.read<DownloadManager>();
    if (_chapters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.emptyContent)),
      );
      return;
    }
    // 仅当「所有章节都已下载」才拦截；下过部分章节时应能继续挑选剩余章节。
    final Set<String> downloadedTitles =
        dl.downloadedChapterTitles(widget.item.id);
    if (_chapters.every((Episode e) => downloadedTitles.contains(e.title))) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.alreadyDownloaded)),
      );
      return;
    }
    final List<int>? selected = await showDownloadSelectionSheet(
      context: context,
      chapters: _chapters,
      contentId: widget.item.id,
      progress: _progressRepo,
      downloadedTitles: downloadedTitles,
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    await dl.addTask(
      item: widget.item,
      chapters: _chapters,
      chapterIndices: selected,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.downloadStarted)),
    );
  }

  Future<void> _downloadSingle(Episode ep, int index) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    await context.read<DownloadManager>().addTask(
          item: widget.item,
          chapters: _chapters,
          chapterIndices: <int>[index],
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.downloadStarted)),
    );
  }

  /// 同一章节判定：优先按集号，回退到标题。用于多线路场景下归并同名剧集。
  bool _sameChapter(Episode a, Episode b) {
    if (a.number != null && b.number != null) {
      return a.number == b.number;
    }
    return a.title == b.title;
  }

  /// 下载单章；当同一章节存在多条线路（不同 [Episode.lineName]）时，
  /// 先弹出线路选择，再下载用户所选线路。
  Future<void> _pickLineAndDownload(Episode ep, int index) async {
    // 归并同一章节在各线路下的候选，key = 线路名（空串表示默认线路）。
    final Map<String, int> lineToIndex = <String, int>{};
    for (int j = 0; j < _chapters.length; j++) {
      final Episode c = _chapters[j];
      if (_sameChapter(c, ep)) {
        final String line = c.lineName ?? '';
        lineToIndex.putIfAbsent(line, () => j);
      }
    }
    if (lineToIndex.length <= 1) {
      return _downloadSingle(ep, index);
    }

    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? chosen = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        final List<Widget> tiles = <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.spaceLg,
              AppTokens.spaceMd,
              AppTokens.spaceLg,
              4,
            ),
            child: Text(
              l10n.videoSourceLine,
              style: Theme.of(ctx).textTheme.titleSmall,
            ),
          ),
          for (final MapEntry<String, int> entry in lineToIndex.entries)
            ListTile(
              title: Text(entry.key.isEmpty ? l10n.defaultLine : entry.key),
              onTap: () => Navigator.of(ctx).pop(entry.key),
            ),
        ];
        return SafeArea(
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
            child: ListView(shrinkWrap: true, children: tiles),
          ),
        );
      },
    );
    if (chosen == null) return; // 用户取消
    final int? selIndex = lineToIndex[chosen];
    if (selIndex == null) return;
    await _downloadSingle(_chapters[selIndex], selIndex);
  }

  Future<void> _toggleRead(Episode ep, int index) async {
    await _progressRepo.toggleRead(widget.item.id, index);
    if (mounted) setState(() {});
  }

  Future<void> _toggleBookmark(Episode ep, int index) async {
    final UnifiedBookmarkRepository? repo = _bookmarkRepo;
    if (repo == null) return;
    final bool nowBookmarked = await repo.toggle(
      widget.item.id,
      ep,
      index,
      currentlyBookmarked: _bookmarkedIndices.contains(index),
    );
    if (!mounted) return;
    setState(() {
      if (nowBookmarked) {
        _bookmarkedIndices.add(index);
      } else {
        _bookmarkedIndices.remove(index);
      }
    });
  }

  void _share() {
    shareContent(context, widget.item.title, widget.item.detailUrl);
  }

  /// 三点菜单动作。
  ///
  /// 「详情」项已移除——详情现在是一级标签页，再弹一次信息面板属重复入口。
  void _handlePopupAction(String action, AppLocalizations l10n) {
    switch (action) {
      case 'setAsShelfCover':
        unawaited(_setAsShelfCover(l10n));
      case 'openDownloadManager':
        Navigator.of(context).push(
          AppPageRoute<void>(builder: (_) => const DownloadListScreen()),
        );
      case 'uploadToWebdav':
        unawaited(_uploadExportsToWebdav(l10n));
    }
  }

  /// 把本书已下载的 EPUB 导出产物手动上传到 WebDAV `nexhub/exports/`。
  /// 仅小说详情页展示；未配置 WebDAV 时提示先去配置。
  Future<void> _uploadExportsToWebdav(AppLocalizations l10n) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dm = context.read<DownloadManager>();
      final files = <String>[
        for (final t in dm.tasks)
          if (t.contentId == widget.item.id &&
              t.sourceType == SourceType.novelSource &&
              t.status == DownloadStatus.completed)
            ...(t.chapterFilePaths ?? const <String>[])
                .where((f) => f.toLowerCase().endsWith('.epub')),
      ];
      if (files.isEmpty) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.uploadToWebdavNoFiles)),
        );
        return;
      }
      final uploader = NovelExportUploadService();
      if (!await uploader.isConfigured()) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.cloudSyncErrorNoConfig)),
        );
        return;
      }
      var ok = 0;
      for (final f in files) {
        try {
          // 鸿蒙公共目录产物：先落应用缓存为真实文件再上传。
          final String local =
              isOhosDocPath(f) ? await OhosPublicStorage.materialize(f) : f;
          await uploader.uploadFile(local);
          ok++;
        } on Object {
          // 单文件失败继续尝试其余产物；全部失败时在最终提示中体现。
        }
      }
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(ok > 0
            ? '$ok ${l10n.uploadToWebdavDone}'
            : l10n.uploadToWebdavFailed),
      ));
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.uploadToWebdavFailed)),
        );
      }
    }
  }

  /// 将当前封面设为书架封面（更新收藏条目的 coverUrl）。
  Future<void> _setAsShelfCover(AppLocalizations l10n) async {
    final bool ok = await context.read<FavoritesManager>().updateCover(
          _fetchedDetail.id,
          _favType,
          _fetchedDetail.coverUrl,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? l10n.coverUpdated : l10n.coverUpdateFailed)),
    );
  }

  void _showCoverViewer(BuildContext context) {
    final String? coverUrl = _fetchedDetail.coverUrl ?? widget.item.coverUrl;
    if (coverUrl == null || coverUrl.isEmpty) return;
    final String? sid = widget.item.sourceId;
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => _CoverViewerScreen(
          coverUrl: coverUrl,
          title: widget.item.title,
          source: (sid == null || sid.isEmpty)
              ? null
              : context.read<SourceRepository>().getById(sid),
        ),
      ),
    );
  }

  // ───────────────────────── 跳转搜索 / 浏览 ─────────────────────────

  /// 统一搜索：标签 / 作者 / 导演 / 主演 / 作品名 走同一入口。
  ///
  /// 默认仅勾选当前源打开（详情页跳转搜索默认只搜该源），
  /// 用户仍可在搜索页勾选更多源一起搜。
  void _openUnifiedSearch(String query, {String? field, String? extractedUrl}) {
    final String q = query.trim();
    if (q.isEmpty) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? sid = widget.item.sourceId;
    final bool startSingle = sid != null && sid.isNotEmpty;
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => ModuleSourceSearchScreen(
          sourceType: _sourceType,
          title: l10n.search,
          initialQuery: q,
          searchField: field,
          extractedUrl: extractedUrl,
          startSingle: startSingle,
          initialSourceId: sid,
          onItemTap: (MediaItem tapped, String? heroTag) =>
              Navigator.of(context).push(
            AppPageRoute<void>(
              builder: (_) =>
                  ContentDetailScreen(item: tapped, heroTag: heroTag),
            ),
          ),
        ),
      ),
    );
  }

  /// 按真实网址浏览：点作者 / 标签时，若详情页抓到了落地页链接
  /// （如 `/manga-author/pi-ka-pi`），直接把该页当作浏览列表打开，
  /// 绕开站点拼音代号限制，源侧零改动。
  void _openSourceUrl(String seedUrl, String title) {
    final String? sid = widget.item.sourceId;
    if (sid == null || sid.isEmpty) return;
    final PluginConfig? source = context.read<SourceRepository>().getById(sid);
    if (source == null) return;
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => SourceUrlBrowseScreen(
          source: source,
          title: title,
          seedUrl: seedUrl,
          onItemTap: (MediaItem tapped, String? heroTag) =>
              Navigator.of(context).push(
            AppPageRoute<void>(
              builder: (_) =>
                  ContentDetailScreen(item: tapped, heroTag: heroTag),
            ),
          ),
        ),
      ),
    );
  }

  // ───────────────────────── 元信息构造 ─────────────────────────

  /// 元信息 chips。
  ///
  /// 三套详情页的并集，按字段有无自动裁剪：
  /// * 导演 / 主演：名单过长时分组折叠（原影视页能力）
  /// * 作者：有真实链接时打开作者页，否则回退关键词搜索（原漫画页能力）
  /// * 年份 / 字数 / 更新至 N 章（原小说页能力）
  List<Widget> _buildInfoChips(
    MediaItem item,
    AppLocalizations l10n,
    int episodeCount,
  ) {
    return <Widget>[
      _InfoChipsSection(
        item: item,
        l10n: l10n,
        episodeCount: _isNovel ? episodeCount : 0,
        onDirectorTap: (String name) =>
            _openUnifiedSearch(name, field: 'director'),
        onActorTap: (String name) => _openUnifiedSearch(name, field: 'actors'),
        onAuthorTap: (String name, String? url) => (url != null && url.isNotEmpty)
            ? _openSourceUrl(url, '${l10n.authorColon}$name')
            : _openUnifiedSearch(name, field: 'author'),
      ),
    ];
  }

  /// 题材标签 chips：有真实标签链接时打开该标签页，否则回退关键词搜索。
  List<Widget> _buildTags(MediaItem item, AppLocalizations l10n) {
    final List<String>? tags = item.tags;
    if (tags == null || tags.isEmpty) return const <Widget>[];
    final List<String> tagUrls = item.tagUrls ?? const <String>[];
    return <Widget>[
      for (int i = 0; i < tags.length; i++)
        TranslatableTagChip(
          label: tags[i],
          tooltip: l10n.searchByTag,
          onPressed: () =>
              (i < tagUrls.length && tagUrls[i].trim().isNotEmpty)
                  ? _openSourceUrl(
                      tagUrls[i].trim(), '${l10n.tagColon}${tags[i]}')
                  : _openUnifiedSearch(tags[i], field: 'tags'),
        ),
    ];
  }

  /// 进度卡。
  Widget _buildProgressCard(
    AppLocalizations l10n,
    int total,
    int read,
  ) {
    return ProgressCard(
      kind: _progressRepo.kind,
      total: total,
      read: read,
      lastRead: resolveLastRead(
        context: context,
        l10n: l10n,
        contentId: widget.item.id,
        sourceType: _favType,
        chapters: _chapters,
        continueIndex: _continueIndex,
        readCount: read,
        progress: _progressRepo,
      ),
    );
  }

  /// 目录解析失败时的内联错误条（不整页替换，头部照常显示）。
  Widget _buildInlineError(AppLocalizations l10n, Object error) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String msg = error is SourceResolveException
        ? l10n.resolveFailed(error.message)
        : l10n.loadFailed;
    return Padding(
      padding: const EdgeInsets.only(
        left: AppTokens.spaceLg,
        right: AppTokens.spaceLg,
        top: AppTokens.spaceMd,
        bottom: AppTokens.spaceSm,
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_rounded, size: 18, color: scheme.error),
          const SizedBox(width: AppTokens.spaceSm),
          Expanded(
            child: Text(
              msg,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.error),
            ),
          ),
          TextButton(onPressed: () => setState(_load), child: Text(l10n.retry)),
        ],
      ),
    );
  }

  /// 目录不完整警告条（部分加载 / 验证拦截 / 缓存兜底）。
  Widget _buildWarningBanner(AppLocalizations l10n, int loadedCount) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool needsVerify = _verificationError != null;
    return Material(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceLg,
          vertical: AppTokens.spaceMd,
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.warning_amber_rounded,
                size: 18, color: scheme.onTertiaryContainer),
            const SizedBox(width: AppTokens.spaceSm),
            Expanded(
              child: Text(
                l10n.chapterLoadPartial(loadedCount),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onTertiaryContainer),
              ),
            ),
            TextButton(
              onPressed: needsVerify
                  ? () async {
                      final bool shouldRetry = await navigateToVerification(
                        context,
                        url: _verificationError!.url,
                        exception: _verificationError,
                      );
                      if (shouldRetry) _retryAfterVerification();
                    }
                  : () => setState(_load),
              child: Text(needsVerify ? l10n.openInBrowser : l10n.retry),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final MediaItem item = _fetchedDetail;

    // 旧数据兜底：sourceId 缺失（历史 / 收藏入库时未持久化）→ 明确提示。
    if (item.sourceId == null || item.sourceId!.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(item.title)),
        body: AppErrorState(
          message: l10n.contentExpired,
          onRetry: _closeSelf,
          retryLabel: l10n.back,
        ),
      );
    }

    // 渲染后抽取请求 → 「抓取本页渲染内容」引导（webview-html 源）。
    if (_htmlCaptureRequest != null) {
      return Scaffold(
        appBar: AppBar(title: Text(item.title)),
        body: AppErrorState(
          message: l10n.captureHint,
          onRetry: () async {
            final WebViewExtractionOutcome? outcome = await navigateToHtmlCapture(
              context,
              request: _htmlCaptureRequest!,
            );
            if (outcome?.hasRenderedHtml == true) {
              await _retryAfterHtmlCapture(outcome!.renderedHtml!);
            }
          },
          retryLabel: l10n.captureFromPage,
        ),
      );
    }

    // 验证异常：仅在完全无目录可展示时弹全屏门。已有目录（渐进批次或 TOC
    // 缓存回填）时继续渲染主体，由警告条提供「去验证」入口，避免临时挑战
    // 遮蔽可用目录形成「从历史进入必撞验证」的循环。
    if (_verificationError != null && _chapters.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(item.title)),
        body: AppErrorState(
          message: l10n.errorVerification,
          onRetry: () async {
            final bool shouldRetry = await navigateToVerification(
              context,
              url: _verificationError!.url,
              exception: _verificationError,
            );
            if (shouldRetry) _retryAfterVerification();
          },
          retryLabel: l10n.openInBrowser,
        ),
      );
    }

    final Widget page = Scaffold(
      body: FutureBuilder<List<Episode>>(
        future: _episodesFuture,
        builder: (BuildContext context, AsyncSnapshot<List<Episode>> snap) {
          final bool waiting =
              snap.connectionState == ConnectionState.waiting;

          // 等待中且无任何渐进数据 → 加载指示；有渐进数据则直接渲染（首屏快显）。
          if (waiting && _chapters.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          // 完全无数据且已出错 → 全屏错误态。
          //
          // 文案分三档，便于用户判断该「重试」还是「去装源」：
          // 解析异常带原因 > 源已被删除/禁用（sourceNotFound）> 泛化加载失败。
          if (snap.hasError && _chapters.isEmpty) {
            final Object? err = snap.error;
            final bool sourceMissing =
                context.read<SourceRepository>().getById(item.sourceId!) == null;
            final String msg = err is SourceResolveException
                ? l10n.resolveFailed(err.message)
                : (sourceMissing ? l10n.sourceNotFound : l10n.loadFailed);
            return AppErrorState(
              message: msg,
              onRetry: () => setState(_load),
              retryLabel: l10n.retry,
            );
          }

          // 渐进数据优先于 Future 终态（可能更新）。
          final List<Episode> episodes =
              _chapters.isNotEmpty ? _chapters : (snap.data ?? <Episode>[]);
          _chapters = episodes;

          return _buildBody(
            context,
            l10n,
            item,
            episodes: episodes,
            // 有数据时错误降级为内联提示 / 警告条，不覆盖已加载内容。
            inlineError: snap.hasError ? snap.error : null,
          );
        },
      ),
    );

    return _withDetailAppearance(context, page);
  }

  /// 详情页外观（设置 → 详情页外观）：
  ///
  /// 1. **封面动态强调色**——开启且封面取色成功时，用封面色作种子在页内
  ///    重建 ColorScheme（按钮 / 标签页选中 / 徽标等强调色随封面变化）；
  ///    调色板风格与深浅色模式沿用当前主题，「玄色」手工主题不做覆盖。
  /// 2. **封面模糊背景**——由 [ContentDetailTabbedShell] 的 Hero 层直接
  ///    读取设置渲染，这里只负责把两层设置的变更广播接到整页重建。
  Widget _withDetailAppearance(BuildContext context, Widget child) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        DetailAppearanceStore.instance,
        _accentController,
      ]),
      builder: (BuildContext context, _) {
        final DetailAppearanceSettings appearance =
            DetailAppearanceStore.instance.settings;
        final Color? accent = appearance.dynamicAccentEnabled
            ? _accentController.accent
            : null;
        if (accent == null) return child;
        final ThemeController themeController = context.read<ThemeController>();
        // 玄色是精调的手工主题（近黑底 + 赤强调），保持原样不被封面色覆盖。
        if (themeController.isXuanSe) return child;
        final ThemeData base = Theme.of(context);
        final ColorScheme seeded = ColorScheme.fromSeed(
          seedColor: accent,
          brightness: base.colorScheme.brightness,
          dynamicSchemeVariant: themeController.paletteStyle.variant,
        );
        return Theme(
          data: base.copyWith(
            colorScheme: seeded,
            scaffoldBackgroundColor: seeded.surface,
            appBarTheme: base.appBarTheme.copyWith(
              backgroundColor: seeded.surface,
              foregroundColor: seeded.onSurface,
              titleTextStyle: base.appBarTheme.titleTextStyle
                  ?.copyWith(color: seeded.onSurface),
            ),
          ),
          child: child,
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    MediaItem item, {
    required List<Episode> episodes,
    Object? inlineError,
  }) {
    final PluginConfig? source =
        context.read<SourceRepository>().getById(item.sourceId ?? '');
    final FavoritesManager favorites = context.watch<FavoritesManager>();
    final DownloadManager downloadMgr = context.watch<DownloadManager>();
    // 订阅已看变更以驱动重建；实际读取统一走 _progressRepo（同一实例）。
    context.watch<MediaWatchedManager>();

    final bool isFav = favorites.isFavorite(item.id, _favType);
    // 逐章判断下载状态：只有「全部章节都已下载」才算整部下载完成。
    // 此前用 isItemDownloaded（只要下过一集就为 true）禁用下载按钮，
    // 导致下过部分集后剩余集永远无法继续下载。
    final Set<String> downloadedTitles =
        downloadMgr.downloadedChapterTitles(item.id);
    final bool isDl = episodes.isNotEmpty &&
        episodes.every((Episode e) => downloadedTitles.contains(e.title));
    final int readCount = _progressRepo.readCount(item.id);
    final int total = computeTotalEpisodes(episodes);
    final bool hasContinue =
        _continueIndex >= 0 && _continueIndex < episodes.length;

    // 目录不完整：渐进中途失败 / 验证拦截 / 缓存兜底。
    final bool showWarning = episodes.isNotEmpty &&
        (_verificationError != null ||
            _chaptersFromCache ||
            (inlineError != null && _chaptersLoading));

    return ContentDetailTabbedShell(
      coverUrl: item.coverUrl,
      source: source,
      // 双栏详情栏与来源列表卡片同处一个路由子树：若沿用来源卡片的 heroTag，
      // 栏内封面 Hero 与卡片 Hero 同标签同子树，任何路由转场（如推入全屏
      // 播放器）做 Hero 扫描即抛 "multiple heroes share the same tag"，
      // 转场中断时 Hero 子树被整体隐藏——表现为详情栏封面消失。embedded
      // 栏不参与路由转场动画，标签无效且有害，置空。
      heroTag: widget.embedded ? null : widget.heroTag,
      onBack: widget.embedded ? _closeSelf : null,
      title: item.title,
      description: item.description ?? l10n.noDescription,
      updatedAt: item.updatedAt ?? latestEpisodeUpdatedAt(episodes),
      statusText: item.status,
      sourceName: source?.name,
      detailUrl: _fetchedDetail.detailUrl ?? widget.item.detailUrl,
      infoChips: _buildInfoChips(item, l10n, episodes.length),
      tags: _buildTags(item, l10n),
      onCoverTap: () => _showCoverViewer(context),
      onRefresh: _onRefresh,
      fallbackIcon: switch (_sourceType) {
        SourceType.mangaSource => Icons.menu_book_rounded,
        SourceType.novelSource => Icons.auto_stories_rounded,
        SourceType.animeSource => Icons.movie_rounded,
      },
      banner: showWarning ? _buildWarningBanner(l10n, episodes.length) : null,
      appBarActions: <Widget>[
        IconButton(
          icon: Icon(isFav ? Icons.bookmark_rounded : Icons.bookmark_border_rounded),
          tooltip: l10n.subTabFavorite,
          onPressed: _onFavoritePressed,
        ),
        IconButton(
          icon: Icon(isDl ? Icons.download_done_rounded : Icons.download_rounded),
          tooltip: l10n.download,
          // 始终可点：未全部下载时继续挑选剩余章节，已全部下载时
          // 由 _startDownload 给出「已下载」提示。
          onPressed: _startDownload,
        ),
        IconButton(
          icon: const Icon(Icons.share_rounded),
          tooltip: l10n.share,
          onPressed: _share,
        ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: l10n.refreshMetadata,
          onPressed: _refreshMetadata,
        ),
        if (isFav)
          IconButton(
            icon: const Icon(Icons.delete_rounded),
            tooltip: l10n.removeFromFavorites,
            onPressed: _removeFromFavorites,
          ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          tooltip: l10n.moreActions,
          onSelected: (String value) => _handlePopupAction(value, l10n),
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              value: 'setAsShelfCover',
              child: Row(
                children: <Widget>[
                  const Icon(Icons.image_rounded),
                  const SizedBox(width: AppTokens.spaceSm),
                  Text(l10n.setAsShelfCover),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'openDownloadManager',
              child: Row(
                children: <Widget>[
                  const Icon(Icons.folder_open_rounded),
                  const SizedBox(width: AppTokens.spaceSm),
                  Text(l10n.openDownloadManager),
                ],
              ),
            ),
            // 小说已导出的 EPUB 上传到 WebDAV（手动触发）。
            if (_isNovel)
              PopupMenuItem<String>(
                value: 'uploadToWebdav',
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.cloud_upload_rounded),
                    const SizedBox(width: AppTokens.spaceSm),
                    Text(l10n.uploadToWebdav),
                  ],
                ),
              ),
          ],
        ),
      ],
      progressSection: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 有数据但目录抓取报错（且非警告条覆盖的情况）→ 内联提示。
          if (inlineError != null && !showWarning)
            _buildInlineError(l10n, inlineError),
          _buildProgressCard(l10n, total, readCount),
        ],
      ),
      bangumiSection: BangumiFullTab(
        contentId: item.id,
        title: item.title,
        sourceType: _favType,
        subjectIdNotifier: _bangumiSubjectId,
      ),
      actions: <Widget>[
        if (hasContinue)
          FilledButton.icon(
            onPressed: () => _openContent(
                episodes[_continueIndex], _continueIndex,
                restoreProgress: true),
            icon: Icon(_isChapterBased
                ? Icons.auto_stories_rounded
                : Icons.play_arrow_rounded),
            label: Text(
                _isChapterBased ? l10n.continueReading : l10n.continueWatching),
          )
        else
          FilledButton.icon(
            onPressed:
                episodes.isEmpty ? null : () => _openContent(episodes.first, 0),
            icon: Icon(_isChapterBased
                ? Icons.auto_stories_rounded
                : Icons.play_arrow_rounded),
            label: Text(_isChapterBased ? l10n.readChapter : l10n.play),
          ),
        // 系列入口：仅当 detail 路由返回了季列表时显示。
        if (_fetchedDetail.seasons != null &&
            _fetchedDetail.seasons!.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              AppPageRoute<void>(
                builder: (_) => SeriesDetailScreen(series: _fetchedDetail),
              ),
            ),
            icon: const Icon(Icons.tv_rounded),
            label: Text(l10n.seriesTitle),
          ),
      ],
      chaptersTabLabel: _isChapterBased ? l10n.chapterList : l10n.episodeList,
      chaptersTitle: _isChapterBased
          ? l10n.chapterListWithCount(episodes.length)
          : l10n.episodeListWithCount(total),
      chaptersList: ChapterListSection(
        chapters: episodes,
        // 影视：按线路分组 + 显示播放位置；网格模式全部内容类型可用
        // （影视 / 漫画 / 小说），长按菜单共用。
        groupByLine: _isAnime,
        isMultiSource: _isAnime,
        enableGridMode: true,
        getPosition: _isAnime
            ? (int i) => _progressRepo.positionMs(item.id, i)
            : null,
        loadingMore: _chaptersLoading,
        onTapChapter: _openContent,
        onDownloadChapter: _pickLineAndDownload,
        // 已下载的集 / 章节改用「已下载」图标（此前未传该回调，图标恒为未下载态）。
        isChapterDownloaded: (int i) => i >= 0 &&
            i < episodes.length &&
            downloadedTitles.contains(episodes[i].title),
        // 书签：漫画 / 小说独有。
        onToggleBookmark: _bookmarkRepo == null ? null : _toggleBookmark,
        isChapterBookmarked: _bookmarkRepo == null
            ? null
            : (int i) => _bookmarkedIndices.contains(i),
        onToggleRead: _toggleRead,
        isChapterRead: (int i) => _progressRepo.isRead(item.id, i),
        unitWord: switch (_sourceType) {
          SourceType.mangaSource => l10n.unitWordComicChapter,
          SourceType.novelSource => l10n.unitWordChapter,
          SourceType.animeSource => l10n.unitWordEpisode,
        },
        contentId: item.id,
      ),
      // 评论标签拆分为「网站评论」与「Bangumi 吐槽」两个子页（源未声明
      // comments 段时仅展示 Bangumi 吐槽子页），故始终提供评论区。
      commentsSection: CommentsTabbedSection(
        source: source,
        contentId: item.id,
        title: item.title,
        sourceType: _favType,
      ),
      recommendations: _recommendationsFuture == null
          ? null
          : _RecommendationList(future: _recommendationsFuture!),
      bangumiSubjectId: _bangumiSubjectId,
      bangumiContentId: item.id,
      bangumiSourceType: _favType,
    );
  }
}

/// 相关推荐横向列表（抽为独立组件，避免详情页 build 过深）。
class _RecommendationList extends StatelessWidget {
  final Future<List<MediaItem>> future;

  const _RecommendationList({required this.future});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    return FutureBuilder<List<MediaItem>>(
      future: future,
      builder: (BuildContext context, AsyncSnapshot<List<MediaItem>> snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(l10n.recommendations, style: textTheme.titleMedium),
              const SizedBox(height: AppTokens.spaceMd),
              const Center(child: CircularProgressIndicator()),
            ],
          );
        }
        final List<MediaItem>? items = snap.data;
        if (items == null || items.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(l10n.recommendations, style: textTheme.titleMedium),
              const SizedBox(height: AppTokens.spaceMd),
              Text(
                l10n.noRecommendation,
                style: textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        }
        const double cardW = 100;
        const double cardH = cardW / AppTokens.coverAspectRatio + 48;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.recommendations, style: textTheme.titleMedium),
            const SizedBox(height: AppTokens.spaceMd),
            SizedBox(
              height: cardH,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (BuildContext _, int __) =>
                    const SizedBox(width: AppTokens.spaceMd),
                itemBuilder: (BuildContext _, int i) {
                  final MediaItem m = items[i];
                  return ContentCard(
                    coverUrl: m.coverUrl,
                    title: m.title,
                    subtitle: m.author,
                    width: cardW,
                    heroTag: 'rel-${m.id}',
                    onTap: () => Navigator.of(context).push(
                      AppPageRoute<void>(
                        builder: (_) => ContentDetailScreen(
                          item: m,
                          heroTag: 'rel-${m.id}',
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 全屏封面大图查看器：点击关闭，支持双指缩放。
class _CoverViewerScreen extends StatelessWidget {
  final String coverUrl;
  final String title;
  final PluginConfig? source;

  const _CoverViewerScreen({
    required this.coverUrl,
    required this.title,
    this.source,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(l10n.coverViewer),
        backgroundColor: Colors.black54,
        foregroundColor: Colors.white,
      ),
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Center(
          child: InteractiveViewer(
            child: AppCoverImage(
              coverUrl: coverUrl,
              source: source,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}

/// 详情页元信息区：导演 / 主演 / 作者 / 年份 / 字数 / 更新至。
///
/// 三套详情页的并集：
/// * 导演、主演各自成组，超过 [maxInitial] 折叠为「展开 N 位」。
/// * 作者带真实链接时优先跳转源站作者页（[onAuthorTap] 第二参非空）。
/// * 年份 / 字数 / 更新至 N 章为静态 chip。
class _InfoChipsSection extends StatefulWidget {
  final MediaItem item;
  final AppLocalizations l10n;

  /// 大于 0 时渲染「更新至 N 章」（小说）。
  final int episodeCount;

  final void Function(String name) onDirectorTap;
  final void Function(String name) onActorTap;
  final void Function(String name, String? url) onAuthorTap;

  const _InfoChipsSection({
    required this.item,
    required this.l10n,
    required this.episodeCount,
    required this.onDirectorTap,
    required this.onActorTap,
    required this.onAuthorTap,
  });

  @override
  State<_InfoChipsSection> createState() => _InfoChipsSectionState();
}

class _InfoChipsSectionState extends State<_InfoChipsSection> {
  static const int maxInitial = 6;
  bool _directorExpanded = false;
  bool _actorsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final MediaItem item = widget.item;
    final AppLocalizations l10n = widget.l10n;
    final List<String> directors = splitMultiValue(item.director);
    final List<String> actors = splitMultiValue(item.actors);
    final List<String> authors = splitMultiValue(item.author);
    final List<String> authorUrls = item.authorUrl != null
        ? item.authorUrl!.split(',')
        : const <String>[];

    final List<Widget> staticChips = <Widget>[
      for (int i = 0; i < authors.length; i++)
        ActionChip(
          label: Text(authors[i]),
          tooltip: l10n.searchByAuthor,
          onPressed: () => widget.onAuthorTap(
            authors[i],
            i < authorUrls.length ? authorUrls[i].trim() : null,
          ),
        ),
      if (item.year != null && item.year!.isNotEmpty)
        Chip(label: Text(item.year!)),
      if (item.wordCount != null && item.wordCount!.isNotEmpty)
        Chip(label: Text('${l10n.wordCount} ${item.wordCount}')),
      if (widget.episodeCount > 0)
        Chip(label: Text(l10n.updatedTo(widget.episodeCount))),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (directors.isNotEmpty)
          _buildGroup(
            context,
            label: l10n.searchFieldDirector,
            names: directors,
            expanded: _directorExpanded,
            onToggle: () =>
                setState(() => _directorExpanded = !_directorExpanded),
            onTap: widget.onDirectorTap,
            searchTip: l10n.searchByDirector,
          ),
        if (actors.isNotEmpty)
          _buildGroup(
            context,
            label: l10n.searchFieldActor,
            names: actors,
            expanded: _actorsExpanded,
            onToggle: () => setState(() => _actorsExpanded = !_actorsExpanded),
            onTap: widget.onActorTap,
            searchTip: l10n.searchByActor,
          ),
        if (staticChips.isNotEmpty)
          Wrap(
            spacing: AppTokens.spaceSm,
            runSpacing: AppTokens.spaceSm,
            children: staticChips,
          ),
      ],
    );
  }

  Widget _buildGroup(
    BuildContext context, {
    required String label,
    required List<String> names,
    required bool expanded,
    required VoidCallback onToggle,
    required void Function(String) onTap,
    required String searchTip,
  }) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final List<String> shown =
        expanded ? names : names.take(maxInitial).toList();
    final int hiddenCount = names.length - shown.length;
    final List<Widget> chips = <Widget>[
      for (final String name in shown)
        ActionChip(
          label: Text(name),
          tooltip: searchTip,
          onPressed: () => onTap(name),
        ),
    ];
    if (hiddenCount > 0) {
      chips.add(
        TextButton(
          onPressed: onToggle,
          child: Text(
            widget.l10n.expandCount(hiddenCount),
            style: textTheme.labelMedium?.copyWith(color: scheme.primary),
          ),
        ),
      );
    } else if (expanded && names.length > maxInitial) {
      chips.add(
        TextButton(
          onPressed: onToggle,
          child: Text(
            widget.l10n.collapse,
            style: textTheme.labelMedium?.copyWith(color: scheme.primary),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: AppTokens.spaceSm),
            child: Text(
              label,
              style:
                  textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: AppTokens.spaceSm),
          Expanded(
            child: Wrap(
              spacing: AppTokens.spaceSm,
              runSpacing: AppTokens.spaceSm,
              children: chips,
            ),
          ),
        ],
      ),
    );
  }
}
