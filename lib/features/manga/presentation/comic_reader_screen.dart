import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart' show Ticker;
import 'package:nexhub/core/local/archive_extractor.dart';
import 'package:nexhub/core/local/local_content_manager.dart'
    show isDocUri, isImageFile;
import 'package:nexhub/core/local/saf_bridge.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:comic_motion/comic_motion.dart'
    show MemoryPipelineResult, MotionCancelToken, processBytesInBackground;
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import '../../../core/platform/brightness_compat.dart';
import '../../../core/platform/harmony_continuation.dart';
import '../../../core/platform/window_service.dart';

import '../../../core/utils/app_haptics.dart';
import '../../../core/scraper/http_fetcher.dart';
import '../../../core/comic/comic_bookmark_manager.dart';
import '../../../core/comic/comic_progress_manager.dart';
import '../../../core/comic/image_favorite_manager.dart';
import '../../../core/comic/models/reader_preferences.dart';
import '../../../core/comic/manga_upscale.dart';
import '../../../core/widgets/manga_upscaled_image.dart';
import '../../../core/comic/reader_image_cache_policy.dart';
import '../../../core/theme/reader_tokens.dart';
import '../../../core/navigation/app_page_route.dart';
import '../../../core/utils/app_log.dart';
import '../../../core/utils/volume_key_listener.dart';
import '../../../core/platform/platform_service.dart';
import '../../../core/comic/models/motion_effect_settings.dart';
import 'package:comic_motion_flutter/comic_motion_flutter.dart'
    show MotionGifView;
import 'package:comic_motion_flutter/reader.dart'
    show InteractivePageLayer, InteractivePageLayerState;
import 'reader_settings_sheet.dart';
import '../../../core/settings/general_settings.dart';
import '../../../core/settings/reader_default_settings.dart';
import '../../../core/favorites/favorites_manager.dart';
import '../../../core/history/history_manager.dart';
import '../../../core/history/media_watched_manager.dart';
import '../../../core/models/episode.dart';
import '../../../core/models/media_item.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/download/download_manager.dart';
import '../../../core/download/local_to_online.dart';
import '../../../core/download/download_settings.dart';
import '../../../core/async_session.dart';
import '../../../core/reader/reading_queue_store.dart';
import '../../../core/widgets/reading_queue_sheet.dart'
    show openReadingQueueSheet;
import '../../../core/scraper/media_api_service.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/stats/reading_session_recorder.dart';
import '../../../core/stats/stats_models.dart';
import '../../../core/stats/stats_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/natural_sort.dart';
import '../../../core/widgets/app_loading_indicator.dart';
import '../../../core/widgets/chapter_list_sheet.dart';
import '../../../core/widgets/comment_section.dart';
import '../../../core/comments/comment_api_service.dart';
import '../../../core/widgets/detail_action_utils.dart';
import '../../../core/widgets/web_favorite_action.dart';
import '../../../core/resolver/webview_resolver.dart';
import '../../../core/widgets/source_image.dart';
import '../../../core/local/pdf_util.dart';
import '../../verification/presentation/webview_verification_screen.dart';
import 'reader_image_actions.dart';
import 'reader_image_filter.dart';
import 'reader_tap_zones.dart';
import 'image_favorite_gallery_screen.dart';
import 'comic_translation_controller.dart';
import 'comic_translation_overlay.dart';

/// 段式连续模型（跨章无缝续读）的段。
///
/// 每个段 = 一个章节，被拍平到连续列表中。
/// 仅 webtoon（条漫）连续模式 + [ReaderPreferences.seamlessReading] 开启时使用。
class _SeamSegment {
  final int chapterIndex;
  final int pageCount;
  final String title;

  /// 本段首个页条目在扁平列表中的起始偏移（含其前导章分割条目）。
  /// 由 [_rebuildSeam] 计算，供扁平索引 ↔ (章, 页) 双向换算。
  final int startOffset;

  const _SeamSegment({
    required this.chapterIndex,
    required this.pageCount,
    required this.title,
    this.startOffset = 0,
  });

  /// 本段最后一个页条目的扁平索引（不含章分割条目）。
  int get endFlatIndex => startOffset + pageCount - 1;
}

/// 段式连续模型重锚后的落点（跨章无缝续读）。
enum _SeamAdvanceTarget {
  /// 保持视口：重锚前视口内同一内容钉回原屏幕位置（滚动越界触发）。
  keep,

  /// 跳到新当前段首页（「下一章」按钮/快捷键）。
  first,

  /// 跳到新当前段末页（「上一章」按钮/快捷键）。
  last,
}

/// 漫画阅读器（Phase 4）。
///
/// 支持 5 种阅读模式、点击区域布局、双击/滚轮缩放、进度自动保存、
/// 末页前预加载下一章。复用统一 Token 与 [ReaderPreferences]。
///
/// 本地模式（Task .B.1）：传入 [localImages] 或 [localCbzPath] 时进入本地模式，
/// 跳过在线源解析，直接渲染本地图片。本地模式下隐藏章节列表 / WebView / 分享等
/// 在线专属 UI，保留书签、进度、点击区域、图像滤镜。调用方需将 [comicId] 设为
/// `'local_${file.path.hashCode}'` 以隔离本地与在线进度。
///
/// 聚合本地模式（B 阶段）：传入 [localArchivePaths]（多归档文件列表，每个文件 =
/// 一话）时进入本地模式但保留章节列表/上下话导航；阅读器按 [chapterIndex] 解压对应
/// 归档取图。与单文件本地模式区别仅在于支持多话切换。
/// 动态效果缓存条目：渲染结果 + 是否完整画质。
///
/// 实时跟随模式两阶段渲染：滚动中先入快速版条目（[full] = false），
/// 停止后的完整画质轮把条目升级为 full（重渲染替换），完整条目永不降级。
class _MotionCacheEntry {
  const _MotionCacheEntry(this.result, this.full);

  final MemoryPipelineResult result;
  final bool full;
}

/// 条漫动态效果的可见条目选取（纯函数，可单测）。
///
/// [items] 为 SPL 位置快照（视口比例坐标）；选取「自身可见比例 ≥
/// [minVisibleFraction]」的条目（正在被阅读的页），按索引升序、最多
/// [maxCount] 条返回。短图一屏多张时多页同时动；长条图取视口内的那一张。
@visibleForTesting
List<int> webtoonMotionFlatIndices(
  List<({int index, double leading, double trailing})> items, {
  double minVisibleFraction = 0.6,
  int maxCount = 4,
}) {
  final List<int> picked = <int>[];
  for (final item in items) {
    final double height = item.trailing - item.leading;
    if (height <= 0) continue;
    final double visible =
        (item.trailing > 1 ? 1 : item.trailing) -
            (item.leading < 0 ? 0 : item.leading);
    if (visible / height < minVisibleFraction) continue;
    picked.add(item.index);
  }
  picked.sort();
  if (picked.length > maxCount) {
    picked.removeRange(maxCount, picked.length);
  }
  return picked;
}

class ComicReaderScreen extends StatefulWidget {
  final String comicId;
  final String title;
  final String sourceId;
  final List<Episode> chapters;
  final int initialChapterIndex;

  /// 本地模式：直接传入本地图片路径列表（跳过在线源解析）。
  final List<String>? localImages;

  /// 本地模式：传入本地 CBZ/ZIP 文件路径，阅读器内部解压取图。
  final String? localCbzPath;

  /// 本地模式：传入本地 PDF 文件路径，阅读器内部逐页渲染成图片。
  final String? localPdfPath;

  /// 本地聚合模式（B 阶段）：文件夹导入，多归档文件合成一整部，每个文件 = 一话。
  /// 传归档文件绝对路径列表（cbz/zip/pdf）；[chapters] 为对应合成章节（每文件一话）。
  /// 阅读器按 [chapterIndex] 解压对应归档取图。与 [localImages]/[localCbzPath] 互斥。
  final List<String>? localArchivePaths;

  /// 本地下载聚合模式：每部作品一个目录（聚合式布局），每话一个图片子目录
  /// （folder/jpg/png 下载格式产物）。传子目录路径列表，下标对齐 [chapters]
  /// （每目录 = 一话）。阅读器按 [chapterIndex] 收集对应目录内图片。与
  /// [localImages]/[localCbzPath]/[localArchivePaths] 互斥。
  final List<String>? localChapterDirs;

  /// 是否用已保存的阅读进度恢复章节/页码。
  /// - true（默认）：从书架/历史「继续阅读」进入时恢复上次进度；
  /// - false：从详情页明确选择某话进入时，以 [initialChapterIndex] 为准。
  final bool restoreProgress;

  /// 跨设备接续：在另一台设备上恢复到的页码（优先级高于本地存档）。
  final int? initialPage;

  /// 详情页 URL（用于收藏时透传，避免历史/收藏详情灰屏）。
  final String? detailUrl;

  /// 封面 URL（用于收藏时透传，避免收藏书架缺封面）。
  final String? coverUrl;

  const ComicReaderScreen({
    super.key,
    required this.comicId,
    required this.title,
    required this.sourceId,
    required this.chapters,
    this.initialChapterIndex = 0,
    this.localImages,
    this.localCbzPath,
    this.localPdfPath,
    this.localArchivePaths,
    this.localChapterDirs,
    this.restoreProgress = true,
    this.initialPage,
    this.detailUrl,
    this.coverUrl,
  });

  @override
  State<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends State<ComicReaderScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final ReaderPreferencesStore _store = ReaderPreferencesStore();
  final ComicProgressManager _progress = ComicProgressManager();

  /// 下载管理器（initState 缓存引用，dispose 阶段 context 已不可用）。
  DownloadManager? _downloadManager;
  FavoritesManager? _favorites;

  /// 跨设备接续快照订阅句柄（dispose 时解绑）。
  Object? _continuationToken;
  final TransformationController _zoomController = TransformationController();

  /// 顶部 / 底部控制栏与点击热区覆盖层的全局键：用于 [ReaderTapZones.isToolbarRegion]
  /// 回调里把指针坐标换算到全局，判定是否落在控制栏上（点在按钮上不触发翻页）。
  final GlobalKey _topBarKey = GlobalKey();
  final GlobalKey _bottomBarKey = GlobalKey();
  final GlobalKey _tapZonesKey = GlobalKey();

  /// 互动阅读层：page URL → 叠加层状态，供 [ReaderTapZones.onTapAt] 转发
  /// 中心点按。仅翻页单页模式为当前页建键。
  final Map<String, GlobalKey<InteractivePageLayerState>> _interactiveKeys =
      <String, GlobalKey<InteractivePageLayerState>>{};

  late ReaderPreferences _prefs;
  int _chapterIndex = 0;
  int _savedPage = 0;

  /// 每章最后一次读到的页（key = 章节索引）。随每次翻页即时更新并异步持久化到
  /// [ComicProgressManager.saveChapterPage]，供「回到上一话」恢复到离开页而非
  /// 固定首页/末页（连续阅读）。内存缓存提供同步读取（切章回调内不能用 await）。
  final Map<int, int> _chapterPageCache = <int, int>{};

  /// 是否正在把视图恢复到保存的页码。
  ///
  /// 恢复期间滚动回调产生的页码是「过渡值」（通常是 0），若照常写盘会把
  /// 上次的阅读位置冲掉 —— 这是「记住阅读进度没作用」的根因之一。
  bool _restoringPage = false;

  List<String> _images = const <String>[];
  bool _loading = true;
  String? _error;
  PluginConfig? _source;

  /// 章节加载令牌：每次发起加载自增，仅最新请求的加载结果会被应用，
  /// 避免快速翻章时旧章节覆盖新章节（竞态导致「显示的章节与 _chapterIndex 不一致」）。
  final AsyncSession _loadSession = AsyncSession();
  final Map<int, List<String>> _preload = <int, List<String>>{};

  /// 正在预加载的章节下标集合（防止同一章重复发起请求）。
  final Set<int> _preloading = <int>{};

  /// 图片 URL → Referer（取图反盗链用）。
  ///
  /// 部分站点按「图片 ↔ 所属章节页」绑定校验 Referer（如 GraphQL 漫画源的
  /// /api/image/{kid} 只认 `章节页 URL`，固定 antiHotlinking.referer 返回 400）。
  /// 加载/预载章节时按浏览器 referrer-policy 推导并登记（同源发完整章节页
  /// URL、跨域发 origin，见 [HttpFetcher.refererForSubresource]）。
  final Map<String, String> _urlReferers = <String, String>{};

  /// 渲染后抽取请求（webview-html 模式，部分脚本源的
  /// images 脚本路由）：非 null 时显示「抓取本页渲染内容」引导，抓取后回填
  /// 渲染 HTML 重试（修复 useWebview 脚本源「漫画图片解析不到内容」）。
  WebViewHtmlRequest? _htmlCaptureRequest;

  /// 按章节缓存渲染后 HTML：每个章节 images 路由 URL 不同，需分别抓取回灌。
  final Map<int, String> _renderedHtmlByChapter = <int, String>{};

  PageController? _pageController;
  ItemScrollController? _itemScrollController;
  ItemPositionsListener? _itemPositionsListener;

  /// 条漫模式待恢复的页码（_setupControllers 设置，_buildWebtoon 首次渲染后清除）。
  int? _pendingWebtoonRestore;

  /// 条漫单步翻页的滚动结果检查定时器：滚动动画结束后比对位置，
  /// 若画面未移动（已被边界夹紧）则换章。用定时器而非滚动 Future，
  /// 因为列表在切章/重建期间可能不再调度新帧，使 Future 永不完成而永久哑火。
  Timer? _webtoonStepTimer;

  /// 条漫「先落首页 → 加载完成后滚动到底」的收尾定时器（回到上一话时使用）。
  Timer? _webtoonRestoreTimer;

  /// 「回到上一话末页」的尺寸稳定轮询定时器：回到上一话首帧后启动，
  /// 每 ~80ms 检查末页项尺寸是否已稳定，稳定后再滚动到底。
  Timer? _webtoonLastPageTimer;

  /// 轮询超时兜底定时器：3s 内末页尺寸仍未稳定也强制滚动收尾，避免卡死。
  Timer? _webtoonLastPageTimeout;

  /// 回到上一话末页两段式：是否已执行「跳到底部」(阶段 1)。跳到底部后列表被夹在底部，
  /// 随图片加载内容变高、滚位移自动跟随到底；此后再等 maxScrollExtent 稳定即整章加载完。
  bool _webtoonPhaseJumped = false;

  /// 轮询期间由滚动通知实时捕获的列表最大滚动范围（图片加载会让其增长）。
  /// 连续多次不变即整章图片已加载完、高度不再增长，可作为「到底」的可靠信号。
  double? _webtoonMaxExtent;

  /// 上一轮读到的 maxScrollExtent，用于两两比对是否稳定。
  double? _webtoonPrevExtent;

  /// maxScrollExtent 连续不变的计数，达到阈值即判定整章已加载完。
  int _webtoonExtentStableCount = 0;

  /// 条漫列表的相对像素滚动控制器，用于「回到上一话末页」的精确落点补差。
  /// 按项对齐的 API 只能指定目标项「顶边」落在视口的哪个比例位置，无法表达
  /// 「末页底边贴视口底」；故先按项建立锚点，再用像素级补差收尾。
  ScrollOffsetController? _webtoonOffsetController;

  /// 本话内已加载完成的图片 URL 集合（阅读器级，跨 item 回收重建存活）。
  /// SPL 懒加载会在 item 滚出 cacheExtent 后销毁其 State；反向滚回重建时
  /// `MangaPageImage._imageLoaded`（State 局部）已丢失，若图片真实高度 ≠ 占位
  /// 高度（屏宽×1.5），已缓存图片会重新走「占位→真实」的高度突变，偏移错位
  /// 即表现为反向翻页回弹/闪烁。这里按 URL 记录加载状态，重建 item 直接按
  /// 真实高度渲染，彻底消除方向反转时的高度突变。切章（_setupControllers）清空。
  final Set<String> _webtoonLoadedUrls = <String>{};

  /// 真实图片自然尺寸缓存（URL → 原始像素宽高）。条漫占位高与放大态纵向平移
  /// 夹取均优先用此处的真实高度估算；未命中（该图从未加载过）回退经验值。
  /// 与 [_webtoonLoadedUrls] 同理，切章（_setupControllers）清空。
  final Map<String, Size> _realImageDims = <String, Size>{};

  /// 由滚动通知实时捕获的视口高度，用于把 itemTrailingEdge（比例）换算成像素差。
  double? _webtoonViewport;

  /// 条漫模式待执行的「滚动到本章末页」标记：回到上一话时置位，
  /// 由 [_buildWebtoon] 首帧后消费。
  bool _pendingWebtoonScrollToLast = false;

  /// 条漫切章重建列表时的首帧对齐系数（keep 无缝重锚写入）。
  /// 列表以 ValueKey('webtoon-章') 挂载，seam 重锚切章必然换 key → SPL State
  /// 整体重建，新列表首帧按 initialScrollIndex + initialAlignment 落位。若不传
  /// 对齐系数（默认 0 = 页顶贴视口顶），而 keep 重锚的真实位置常在页面中部
  /// （edge 为负），首帧与 post-frame jumpTo 钉回的位置差可达大半页，表现为
  /// 「闪一下」。传入后首帧即最终位置，jumpTo 成为同参 no-op，无中间帧。
  double? _pendingWebtoonInitialAlignment;

  /// 条漫边界拖拽累计位移（像素）：正=持续拖出底部，负=持续拖出顶部。
  /// 超过 [_kChapterOverscroll] 即换章，松手或重新开始滚动时清零。
  double _overscrollAccum = 0;

  /// 边界拖拽换章阈值（像素）。本地聚合/在线 seam 无邻段时，翻到章首/章末
  /// 靠此阈值触发换章；阈值过大（原 160px）在窄屏上需要拖很远，感知为
  /// 「翻到首页就翻不了上一话」。降至 80px（约 2cm）平衡防误触与响应性。
  static const double _kChapterOverscroll = 80;

  /// 判定「item 已按真实图片尺寸布局」的最小高度（视口高度归一化）。
  /// 图片未加载时每条 item 仅是占位小高度（约几十像素 ≈ 0.05 视口），而真实漫画页
  /// 在 fitWidth/fitHeight/cropEdge 下通常 ≥ 0.5 视口。用于区分占位期与真实布局，
  /// 避免在整章「缩成一屏」的占位状态下误判到底 / 误判尺寸已稳定。
  static const double _kMinRealItemHeight = 0.3;

  int _currentPageValue = 0;

  /// 当前页（逻辑单页索引）。赋值时同步广播到 [_currentPageNotifier]，
  /// 底栏滑条 / 页码标签以 ValueListenableBuilder 局部刷新——自动滚动期间
  /// 页码切换不再触发整屏 setState（见 [_onWebtoonScroll] 触顶卡顿修复）。
  final ValueNotifier<int> _currentPageNotifier = ValueNotifier<int>(0);
  int get _currentPage => _currentPageValue;
  set _currentPage(int v) {
    _currentPageValue = v;
    _currentPageNotifier.value = v;
    // 漫画翻译开启时，翻到新页自动触发该页 OCR+翻译（内部有缓存/去重守卫，
    // 高频调用无副作用；webtoon 滚动中反复触发同一页直接命中状态检查返回）。
    if (_prefs.translationEnabled &&
        _images.isNotEmpty &&
        v >= 0 &&
        v < _images.length) {
      unawaited(_translation.ensureTranslated(
        _images[v],
        chapterKey: _translationChapterKey,
        pageIndex: v,
      ));
    }
  }

  /// 翻译缓存键的章节部分：优先章节 id（在线源），本地模式回退章索引。
  String get _translationChapterKey {
    if (!_isLocalMode &&
        _chapterIndex >= 0 &&
        _chapterIndex < widget.chapters.length) {
      final id = widget.chapters[_chapterIndex].id;
      if (id.isNotEmpty) return id;
    }
    return 'ch$_chapterIndex';
  }

  /// 同步翻译开关到控制器（设置面板 / 全局偏好变化时调用）。
  void _syncTranslation() {
    unawaited(_translation.setEnabled(_prefs.translationEnabled));
    if (_prefs.translationEnabled) {
      // 开关刚打开：立即翻译当前页（翻页 setter 只在翻页时触发）。
      final String? url = _currentPageImageUrl;
      if (url != null) {
        unawaited(_translation.ensureTranslated(
          url,
          chapterKey: _translationChapterKey,
          pageIndex: _currentPage,
        ));
      }
    }
  }

  /// 翻译失败重试（覆盖层错误徽标 → [MangaPageImage.translationRetry]）：
  /// 按 URL 反查页码后重新发起。
  void _translationRetryPage(String url) {
    final int idx = _images.indexOf(url);
    if (idx < 0) return;
    unawaited(_translation.retry(
      url,
      chapterKey: _translationChapterKey,
      pageIndex: idx,
    ));
  }

  /// 长按 / 右键菜单「翻译本页 / 关闭翻译」：toggle 当前书翻译开关并落盘
  ///（与底栏工具栏同款持久化路径），开关打开时立即对当前页发起翻译。
  Future<void> _toggleCurrentPageTranslation() async {
    final next =
        _prefs.copyWith(translationEnabled: !_prefs.translationEnabled);
    await _applySettings(next, persist: true);
  }

  bool _uiVisible = false;

  /// 是否实际进入了桌面 OS 全屏（[_requestOsFullscreen(true)] 成功）。退出时仅当
  /// 确曾进入才延迟离开全屏（避免无谓的 setFullScreen(false) 窗口样式重建，也避免
  /// 在从未全屏（如测试环境）时留下 pending 的零时长定时器）。
  bool _osFullscreenEntered = false;
  bool _isFav = false;
  bool _showInlineSettings = false;

  /// 章节书签管理器与当前章书签状态（章节书签）。
  final ComicBookmarkManager _bookmarks = ComicBookmarkManager();
  bool _chapterBookmarked = false;

  /// 图片收藏管理器与当前页图片收藏状态（图片收藏图库）。
  final ImageFavoriteManager _imageFavMgr = ImageFavoriteManager();
  bool _isPageImageFav = false;

  /// 漫画翻译控制器（漫画翻译功能）：开关跟随 [_prefs.translationEnabled]，
  /// 翻页时对当前页触发 OCR+翻译，译文由 [MangaPageImage] 内嵌覆盖层渲染。
  /// initState 显式构造（源配置异步加载后经 updateSource 补传）。
  late final ComicTranslationController _translation;

  // ── 时间 / 电量浮层──
  String _currentTime = '';
  int _batteryLevel = -1; // -1 = unknown
  Timer? _timeTimer;
  StreamSubscription<Object?>? _batterySubscription;

  // ── 系统亮度双轨──
  final BrightnessCompat _brightnessPlugin = BrightnessCompat();

  /// 是否为负亮度（压暗 + 黑遮罩）模式，避免两轨互相覆盖。
  bool _dimBrightnessActive = false;

  /// 已触发自动下载的章节索引：每章仅触发一次，避免翻页重复入队。
  int _autoDownloadTriggeredChapter = -1;

  /// 本地读完自动接续在线（无缝）：防重入标志。
  bool _localToOnlineTriggered = false;

  // ── 三层设置覆盖──
  /// 设备/会话层运行时覆盖：优先级最高、退出阅读器不持久化。
  ///
  /// null 表示无设备层覆盖（回落 [ReaderPreferences.mergedWithKeys] 后的作品层 [_prefs]）。
  /// 内联设置面板的即时预览（onChanged）写入本层；关闭面板时再提交到作品层持久化。
  ReaderPreferences? _devicePrefs;

  /// 本书显式单独设置过的字段名（[ReaderPreferences.toJson] 键）。
  /// 只有这些字段覆盖全局默认，其余实时跟随总设置。
  final Set<String> _overrideKeys = <String>{};

  /// 三层覆盖后的实际生效偏好：设备层非空取设备层，否则取作品层。
  ReaderPreferences get _effectivePrefs =>
      getReaderSetting(_prefs, _devicePrefs, (p) => p);

  // ── 章节导航滑块──
  /// 拖动章节滑块时预览的章节索引（null = 未在拖动）。
  int? _sliderPreviewChapter;

  /// 整体是否处于放大状态（共享 [_zoomController] 的 scale > 1）。用于在放大时
  /// 关闭底层 PageView / ListView 的滚动手势，避免「放大图片拖动平移」与「翻页 /
  /// 滚动」在手势竞技场里互相抢手势、导致两种行为都失灵。未放大时恢复原生手势。
  bool _zoomed = false;

  /// 每页旋转的 quarterTurns（0/1/2/3），仅在用户主动旋转时记录。
  final Map<int, int> _pageRotations = <int, int>{};

  /// 段式连续模型（跨章无缝续读）下的段列表，按阅读顺序排列。
  ///
  /// 仅 webtoon（条漫）连续模式 + [ReaderPreferences.seamlessReading] 开启时使用；
  /// 其余情况保持空列表，走传统「整章加载」路径。重建见 [_rebuildSeam]。
  List<_SeamSegment> _seam = const <_SeamSegment>[];

  /// 段式连续扁平列表的总条目数（含章分割/过渡条目）。
  /// 由 [_rebuildSeam] 计算，供 [_buildWebtoonList] 确定 itemCount。
  int _seamItemCount = 0;

  /// 段式连续模型下，扁平索引 → 真实页面索引的映射 list。
  /// 长度为 [_seamItemCount]；分隔条目处值为 -1。
  List<int> _seamPageMap = const <int>[];

  /// 段式连续模型下，扁平列表的图片 URL 列表（含分隔条目的占位空串）。
  /// 与 [_seamPageMap] 长度一致，供 [_buildWebtoonList] 扁平渲染。
  List<String> _seamImages = const <String>[];

  /// 重锚段式连续模型的「当前段」时置位，避免滚动回调在重锚期间级联重入
  /// （重锚 = 交换 [_images]/[_preload] + 重建 [_seam] + 平移视口）。
  bool _seamReanchoring = false;

  /// 重锚 paged 段式连续模型（章末过渡卡 / 章首衔接）时置位，避免重锚期间
  /// 级联重入（重锚 = 交换 [_images]/[_preload] + 重建 PageController + 定位）。
  bool _pagedReanchoring = false;

  /// 进度保存防抖定时器，合并频繁翻页产生的写入。
  Timer? _saveProgressDebounce;

  /// 防抖窗口内待落盘的页码：dispose 时若仍有 pending 写入未执行，立即 flush，
  /// 避免「翻页后 1s 内退出」导致进度未落盘、下次回退（数据丢失 bug）。
  int? _pendingSavePage;

  /// 阅读器键盘焦点节点：用于捕获桌面键盘快捷键（方向键翻页 / F11 全屏等）。
  final FocusNode _readerFocus = FocusNode();

  /// 翻页闪光动画控制器与覆盖层状态。
  late final AnimationController _flashController;

  /// E-Ink 刷新：按翻页间隔累计的页数计数器与上次计入的页码。
  int _einkPageCount = 0;
  int _einkLastPage = -1;

  /// 当前注册到 [_flashController] 的监听器引用：重播闪光前用 removeListener
  /// 摘除旧监听，避免 clearListeners（受保护成员不可用）。
  VoidCallback? _flashListener;
  double _flashOpacity = 0.0;
  Color _flashColor = Colors.black;

  /// 闪光覆盖层是否处于播放中。渲染条件据此判断，与 [_prefs.flashEnabled] 解耦：
  /// E-Ink 定期刷新在普通闪光关闭时也能全屏闪烁清残影（此前被
  /// `if (_prefs.flashEnabled)` 吞掉导致「没有作用」）。
  bool _flashLayerActive = false;

  // ── 翻页过渡动画 + 双击缩放动画 ──────────────────────────

  /// 双击 / 长按缩放动画控制器（[ReaderPreferences.doubleTapAnimSpeed] 毫秒）。
  /// 动画期间 [_zoomAnimating] 为 true，抑制其他手势写入缩放矩阵，避免抖动。
  AnimationController? _zoomAnimController;

  /// 缩放动画进行中标志：动画期间忽略双击 / 平移 / 方向键缩放请求。
  bool _zoomAnimating = false;

  /// 当前缩放动画的目标矩阵：中断/连点时先定格到目标态再继续，保证三态循环不卡死。
  /// 翻页时 [_resetZoom] 也会清空此值，避免翻页后残留目标导致双击无反应。
  Matrix4? _zoomAnimTarget;

  /// 缩放动画当前挂载的监听（每轮动画先移除旧监听再挂新监听，避免累积泄漏）。
  void Function()? _zoomAnimTick;
  void Function(AnimationStatus)? _zoomAnimStatus;

  /// paged 模式 [ReaderPageAnimation.fade] 过渡用的页面透明度（1=不透明）。
  /// 翻页后从 0 淡入到 1，用 AnimatedOpacity 驱动，不改变 PageView 翻页结构。
  double _pageFadeOpacity = 1.0;
  Timer? _pageFadeTimer;

  // ── 页面动态效果（comic_motion 引擎，paged 模式）──────────────────

  /// 动态效果渲染结果缓存（URL → GIF + 首帧）。会话内小容量 LRU：
  /// 翻回已渲染页零等待；上限 [_motionCacheMax] 控制内存占用。
  final Map<String, _MotionCacheEntry> _motionCache =
      <String, _MotionCacheEntry>{};

  /// 驻留防抖定时器：翻页停留超过该时长才派发渲染（快速翻页不触发）。
  Timer? _motionDebounce;

  /// 在途渲染任务的取消令牌：翻页离开 / 设置变更 / 退出即取消。
  MotionCancelToken? _motionToken;

  /// 在途渲染的 URL（同页任务防重复派发）。
  String? _motionJobUrl;

  /// 在途渲染任务的画质（true = 完整画质）：完整轮接管后快速轮让位。
  bool _motionJobFull = true;

  /// 实时跟随快速轮定时器（200ms）：滚动中先出快速版。
  Timer? _motionFollowTimer;

  /// 渲染队列世代号：每次重估调度自增，旧世代循环自行退出，
  /// 避免「快速轮 / 完整轮 / 旧页面」多队列互相顶撞。
  int _motionJobsEpoch = 0;

  /// 动态效果缓存上限（条数；每项 GIF + 首帧约 1–4MB）。
  static const int _motionCacheMax = 4;

  /// 动态效果驻留时长（毫秒）：翻页后停留多久才开始渲染当前屏。
  static const int _motionDwellMs = 800;

  /// 实时跟随模式的调度延迟（毫秒）：短防抖合并连续滚动事件，
  /// 同时配合在途任务取消，让渲染始终追着当前视野。
  static const int _motionFollowMs = 200;

  // ── 音量键翻页（Android / 鸿蒙）────────────────────────────

  /// 原生音量键拦截器（Android onKeyDown 方案）：彻底消费按键事件，阻止系统音量条。
  final VolumeKeyListener _volumeKeyListener = VolumeKeyListener();

  // ── 自动滚动 / 自动翻页 + 后台暂停 ───────────────────────

  /// 自动翻页定时器（paged 模式，间隔 [_prefs.autoPageTurningInterval] 秒）。
  Timer? _autoPageTurnTimer;

  /// 最近一次创建自动翻页定时器时使用的间隔（秒）：间隔变化时据此重建定时器，
  /// 保证「自动翻页间隔」修改后即时生效（否则定时器只在首次创建时按旧间隔翻页）。
  int? _lastAutoPageInterval;

  /// 自动滚动 Ticker（webtoon 模式，vsync 对齐平滑滚动）。
  Ticker? _autoScrollTicker;

  /// 自动滚动累计已消耗时长（用于计算单帧 delta，限制单帧最大滚动量）。
  Duration _autoScrollElapsed = Duration.zero;

  /// 自动滚动分块窗口（毫秒）：像素先累积，达到该窗口时长才发起一次
  /// [ScrollOffsetController.animateScroll]，动画时长与窗口一致，速度仍为
  /// `60px/s × readerScrollSpeed`。避免每帧新建/取消 DrivenScrollActivity 造成的
  /// 帧边界抖动（条漫图片顶端到达屏幕顶端时「卡一下」的根治）。
  static const int _autoScrollChunkMs = 120;

  /// 距上次发起自动滚动动画以来累积的待滚动像素（尚未滚动部分）。
  double _autoScrollPendingPx = 0;

  /// 距上次发起自动滚动动画的累计时长（ticker elapsed 相对）。
  Duration _autoScrollChunkElapsed = Duration.zero;

  /// 后台暂停标志：App 进入 paused/inactive/hidden 时置位，resumed 清除。
  bool _autoScrollPaused = false;

  /// 自动滚动 Ticker 是否正在运行（webtoon 模式）。运行期间 [_onWebtoonScroll]
  /// 不做整屏 setState（页码指示由 [_currentPageNotifier] 局部刷新），也跳过
  /// 图片收藏异步刷新，避免自动滚动在页边界处因全量重建而卡顿。
  bool _autoScrolling = false;

  // ── 睡眠定时（跨类型对齐：播放器 / 小说 TTS）────────────────

  /// 按分钟定时：到时暂停阅读（一次性 Timer）。
  Timer? _sleepTimer;

  /// 分钟模式下选定的分钟数（供设置面板回显当前状态）。
  int _sleepMinutes = 0;

  /// 按话数定时剩余计数：进入新章节递减，归零触发暂停。
  int _sleepChaptersRemaining = 0;

  /// 首次章节加载完成前不计数（初始章不是「读完一话」）。
  bool _sleepPrimeLoaded = false;

  /// 当前睡眠定时状态（设置面板回显用）。
  ComicSleepTimerState get _sleepTimerState {
    if (_sleepMinutes > 0) {
      return ComicSleepTimerState.minutes(_sleepMinutes);
    }
    if (_sleepChaptersRemaining > 0) {
      return ComicSleepTimerState.chapters(_sleepChaptersRemaining);
    }
    return const ComicSleepTimerState.off();
  }

  /// 进入一个新章节（读完一话进入下一话）：按话数定时递减。
  /// 首次加载的初始章不计数；分钟模式不参与。
  void _onChapterEntered() {
    if (!_sleepPrimeLoaded) {
      _sleepPrimeLoaded = true;
      return;
    }
    if (_sleepChaptersRemaining <= 0) return;
    _sleepChaptersRemaining--;
    if (_sleepChaptersRemaining <= 0) {
      _fireSleepTimer(AppLocalizations.of(context));
    }
  }

  /// 应用睡眠定时选择（设置面板回调）：分钟 / 话数 / 关闭。
  void _applySleepTimer(ComicSleepTimerState state) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepMinutes = 0;
    _sleepChaptersRemaining = 0;
    switch (state.mode) {
      case ComicSleepTimerMode.off:
        break;
      case ComicSleepTimerMode.minutes:
        _sleepMinutes = state.value;
        _sleepTimer = Timer(Duration(minutes: state.value), () {
          if (mounted) {
            _fireSleepTimer(AppLocalizations.of(context));
          }
        });
        break;
      case ComicSleepTimerMode.chapters:
        _sleepChaptersRemaining = state.value;
        break;
    }
    if (mounted) setState(() {});
  }

  /// 定时触发：暂停自动翻页 / 自动滚动（会话级停止运行，保留偏好开关）并提示。
  void _fireSleepTimer(AppLocalizations l10n) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepMinutes = 0;
    _sleepChaptersRemaining = 0;
    _autoPageTurnTimer?.cancel();
    _autoPageTurnTimer = null;
    _autoScrollTicker?.stop();
    _autoScrollTicker = null;
    _autoScrolling = false;
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.readerSleepTimerFired)),
    );
  }

  /// 把当前作品加入待读队列（顶栏更多菜单入口）。
  Future<void> _addCurrentToReadingQueue() async {
    final l10n = AppLocalizations.of(context);
    await ReadingQueueStore().add(QueuedReading(
      sourceType: SourceType.mangaSource,
      sourceId: widget.sourceId,
      itemId: widget.comicId,
      title: widget.title,
      coverUrl: widget.coverUrl,
      detailUrl: widget.detailUrl,
      initialChapterIndex: _chapterIndex,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.readingQueueAdded)),
    );
  }

  /// 章节切换过渡标题卡状态。
  bool _transitionVisible = false;
  String _transitionTitle = '';
  Timer? _transitionTimer;

  /// 跳章过渡提示状态（2026-08-20 起条漫滚到章末改「直接自动连读」，横幅不再
  /// 有启动入口；字段保留给 _hideSkipTransition 的幂等清除路径，恒为 false）。
  bool _showSkipTransition = false;

  /// 跳章过渡提示的延时跳转定时器（同横幅一并废弃，保留清除路径）。
  Timer? _skipTransitionTimer;

  MediaApiService get _service => context.read<MediaApiService>();
  SourceRepository get _repo => context.read<SourceRepository>();

  /// 是否为本地文件模式（Task .B.1）。
  bool get _isLocalMode =>
      widget.localImages != null ||
      widget.localCbzPath != null ||
      widget.localPdfPath != null ||
      widget.localArchivePaths != null ||
      widget.localChapterDirs != null;

  /// 本地聚合模式（B 阶段）：多归档文件合成一整部，每个文件 = 一话。
  bool get _isAggregatedLocal =>
      widget.localArchivePaths != null && widget.localArchivePaths!.isNotEmpty;

  /// 段式连续模型（跨章无缝续读）是否生效。
  ///
  /// 满足条件：webtoon（条漫）连续模式 + [ReaderPreferences.seamlessReading] 开启 +
  /// 存在相邻章（多章作品；聚合本地/本地下载目录含章节概念，同样支持无缝）。
  /// 单文件本地模式（无章节概念）与 paged 模式不走本模型（paged 走章末过渡卡）。
  bool get _seamActive =>
      _prefs.readingMode.isWebtoon &&
      _prefs.seamlessReading &&
      widget.chapters.length > 1 &&
      widget.localImages == null &&
      widget.localCbzPath == null &&
      widget.localPdfPath == null;

  /// paged 段式连续模型（跨章无缝续读 · paged 分支）是否生效。
  ///
  /// 满足条件：paged 单页/双页模式 + [ReaderPreferences.seamlessReading] 开启 +
  /// 存在相邻章（多章作品；聚合本地/本地下载目录含章节概念，同样支持无缝）。
  /// 单文件本地模式（无章节概念）不走本模型。
  bool get _pagedSeamActive =>
      _prefs.readingMode.isPaged &&
      _prefs.seamlessReading &&
      widget.chapters.length > 1 &&
      widget.localImages == null &&
      widget.localCbzPath == null &&
      widget.localPdfPath == null;

  /// paged 段式连续模型下，章末是否追加「下一章过渡卡」页。
  /// 越过过渡卡即无缝进入下一章首页（见 [_goNextPage] / [_buildPagedNextCard]）。
  bool get _showPagedNextCard =>
      _pagedSeamActive && _chapterIndex < widget.chapters.length - 1;

  /// PDF 临时渲染缓存目录（逐页 JPEG）。退出阅读器时清理。
  String? _pdfCacheDir;

  /// 归档（CBZ/CBR/7z…）解压出的临时目录集合（资源回收）。每次
  /// [extractArchiveImagesToDir] 产生一个按源归档隔离的子目录，退出阅读器时
  /// 整目录递归删除——此前解压产物平铺在系统临时目录、只靠 OS 兜底清理。
  final List<String> _archiveTempDirs = <String>[];

  /// 桌面形态平台（Windows / Linux / macOS / 鸿蒙 PC，非 Web）：启用真窗口全屏 /
  /// 与键盘快捷键。移动端（含鸿蒙手机）走 SystemChrome。
  bool get _isDesktop => PlatformService.instance.isDesktopForm;

  /// 进入阅读器期间上调 Flutter 图片缓存预算（资源/内存）：按设备物理内存
  /// 100–500MB；退出阅读器在 dispose 恢复默认 100MB，不挤占其他页面。
  void _applyImageCacheBudget() {
    unawaited(() async {
      final total = await probeDeviceTotalMemBytes();
      PaintingBinding.instance.imageCache.maximumSizeBytes =
          resolveComicImageCacheBytes(total);
    }());
  }

  @override
  void initState() {
    super.initState();
    // 监听窗口尺寸变化（全屏切换 / 拖动窗口边角）：视口尺寸变化后，缩放矩阵的
    // 平移夹取上界随之改变，若不重算，已放大/已平移的图片在进出全屏时会出现位置
    // 偏移（验收）。didChangeMetrics 里重夹矩阵修复之。
    WidgetsBinding.instance.addObserver(this);
    _translation = ComicTranslationController(comicId: widget.comicId);
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _zoomController.addListener(_onZoomChanged);
    _chapterIndex = widget.initialChapterIndex;
    _prefs = const ReaderPreferences();
    // 读后自动删除：dispose 阶段判定「读完」用（context 已不可用，先缓存引用）。
    try {
      _downloadManager = context.read<DownloadManager>();
    } on Object {
      _downloadManager = null;
    }
    // 排除分类判定同样在 dispose 阶段使用，缓存引用。
    try {
      _favorites = context.read<FavoritesManager>();
    } on Object {
      _favorites = null;
    }
    // 全局键盘监听（F11 / Esc / 方向键等）——不依赖 Focus 焦点，按钮/面板/对话框
    // 抢焦点后快捷键依然有效（F11、Esc 失效的根治）。
    HardwareKeyboard.instance.addHandler(_onGlobalKey);
    _applyImageCacheBudget();
    _init();
    // 跨设备接续：仅在线多章内容参与（本地文件无跨设备语义）。
    if (!_isLocalMode && widget.sourceId.isNotEmpty) {
      _continuationToken = HarmonyContinuation.attach(_buildContinuationSnapshot);
    }
    // 阅读时长统计：进入阅读器即开始，dispose 时一次性结算。
    if (widget.sourceId.isNotEmpty) {
      final initialTitle = widget.chapters.isNotEmpty &&
              widget.initialChapterIndex >= 0 &&
              widget.initialChapterIndex < widget.chapters.length
          ? widget.chapters[widget.initialChapterIndex].title
          : null;
      unawaited(ReadingSessionRecorder.instance.begin(
        workId: widget.comicId,
        sourceId: widget.sourceId,
        type: StatsMediaType.comic,
        title: widget.title,
        coverUrl: widget.coverUrl,
        lastChapterTitle: initialTitle,
      ));
    }
  }

  /// 跨设备接续快照：当前章 + 章节窗口（控制 want 参数体积）+ 页码。
  Map<String, Object?>? _buildContinuationSnapshot() {
    final List<Episode> chapters = widget.chapters;
    if (chapters.isEmpty) return null;
    final int idx = _chapterIndex.clamp(0, chapters.length - 1);
    final ({List<Map<String, dynamic>> items, int start})? window =
        HarmonyContinuation.encodeChapterWindow(chapters, idx);
    return <String, Object?>{
      'type': 'comic',
      'title': widget.title,
      'sourceId': widget.sourceId,
      'contentId': widget.comicId,
      'chapterIndex': idx,
      'episode': chapters[idx].toJson(),
      if (window != null) 'episodes': window.items,
      if (window != null) 'episodeStart': window.start,
      'page': _currentPage < 0 ? 0 : _currentPage,
      if (widget.detailUrl != null) 'detailUrl': widget.detailUrl,
      if (widget.coverUrl != null) 'coverUrl': widget.coverUrl,
    };
  }

  Future<void> _init() async {
    final defaults = await ReaderDefaultSettingsStore().load();
    // 显式覆盖合并：只有用户单独设置过的字段覆盖全局默认，其余实时跟随总设置。
    _overrideKeys.addAll(await _store.getOverrideKeys(widget.comicId));
    _prefs = (await _store.get(widget.comicId))
        .mergedWithKeys(defaults.toReaderPreferences(), _overrideKeys);
    // 进度恢复分两种情形：
    // - restoreProgress=true（「继续阅读」入口）：章 + 页都恢复。
    // - restoreProgress=false（详情页明确点选某话）：不改章，但**若点选的正是上次
    // 在读的那一话，仍恢复页码**。否则「读到第 5 页 → 退出 → 点同一话进来」永远
    // 从第 1 页开始，用户会认为进度根本没保存（数据丢失的实际观感来源）。
    // 受全局「记住阅读位置」开关约束，关闭时不恢复。
    final saved = await _progress.get(widget.comicId);
    // 单文件本地模式（无章节表，章恒为 0）同样恢复到已读页；多章模式要求存档章
    // 在章节表内（列表变短时丢弃旧进度）。此前 `chapterIndex < chapters.length`
    // 在空章节表下恒为 false，本地漫画重进永远从第 1 页开始。
    if (saved != null &&
        (widget.chapters.isEmpty
            ? _isLocalMode
            : saved.chapterIndex < widget.chapters.length)) {
      if (widget.restoreProgress) {
        _chapterIndex = saved.chapterIndex;
        _savedPage = saved.currentPage;
      } else if (saved.chapterIndex == _chapterIndex &&
          GeneralSettingsStore.instance.settings.rememberPosition) {
        _savedPage = saved.currentPage;
      }
      // 恢复按章页码表：回到上一话时恢复到离开页。
      for (final MapEntry<String, int> e in saved.chapterPages.entries) {
        final int? ci = int.tryParse(e.key);
        if (ci != null && ci >= 0 && ci < widget.chapters.length) {
          _chapterPageCache[ci] = e.value;
        }
      }
    }
    // 跨设备接续：接续页码优先于本地存档（另一台设备可能读得更远）。
    if (widget.initialPage != null) {
      _savedPage = widget.initialPage!;
    }
    _syncTranslation();
    _refreshFavorite();
    // 自动收藏（漫画）：打开作品即加入收藏。已收藏跳过，避免 toggle 误移除。
    if (_effectivePrefs.isAutoFavorite &&
        _favorites != null &&
        !_favorites!.isFavorite(widget.comicId, SourceType.mangaSource)) {
      unawaited(_favorites!.toggleFavorite(MediaItem(
        id: widget.comicId,
        title: widget.title,
        sourceId: widget.sourceId,
        sourceType: SourceType.mangaSource,
        detailUrl: widget.detailUrl,
        coverUrl: widget.coverUrl,
      )));
      _isFav = true;
    }
    unawaited(_refreshChapterBookmark());
    // 本地漫画（无章节/无在线源）默认显示控制栏，避免「只有图片没有操控面板」。
    // 联网漫画仍保持沉浸式（点屏切换显隐）。
    if (_isLocalMode) _uiVisible = true;
    if (mounted) setState(() {});
    _applyOrientation();
    // 移动端：进入阅读器即按全屏偏好隐藏状态栏/导航栏（immersiveSticky）。
    // 桌面端不自动 OS 全屏（避免 window_manager 的 setFullScreen 在初始化期
    // 同步调用卡死渲染管道，见 _applyFullscreen 注释）；桌面全屏仅由 F11 /
    // 设置面板开关触发（见 _handleKeyEvent / didUpdateWidget）。
    if (!_isDesktop) _applyFullscreen();
    // 注意：window_manager 的 ensureInitialized 已在 main() 的 runApp 之前完成
    // （运行期再调会冻结渲染管道），此处只管应用状态，不再初始化。
    _applyWakelock();
    // 阅读亮度与时间/电量浮层：初始偏好已就绪。
    _applyBrightness();
    if (_prefs.showClockBattery) _initTimeAndBattery();
    // 初始偏好已就绪：按偏好挂载音量键监听 / 启动自动翻页 / 自动滚动。
    _syncVolumeKey();
    _syncAutoMotion();
    if (_isLocalMode) {
      await _loadLocalImages(restorePage: _savedPage);
    } else {
      await _loadChapter(_chapterIndex, restorePage: _savedPage);
    }
    // 进入阅读器「不自动全屏」：验收 要求进入时不强制 OS 全屏（也避免
    // window_manager 的 setFullScreen 在初始化期同步调用卡死渲染管道）。全屏只在
    // 用户按 F11 / 设置面板开关时切换（见 [_handleKeyEvent] / [didUpdateWidget]）。
  }

  /// 本地模式加载图片：优先使用 [widget.localImages]，否则解压 [widget.localCbzPath]。
  Future<void> _loadLocalImages(
      {int restorePage = 0, bool restoreToLast = false}) async {
    // 聚合本地模式同样需要「代次守卫」：初始加载与快速翻话可能并发，
    // 若不丢弃过期结果，较慢的初始解压会覆盖已切换的话（表现为「切换话还是同一话」）。
    final int token = _loadSession.next();
    if (mounted) setState(() => _loading = true);
    try {
      List<String> imgs;
      // 聚合本地模式：按当前话索引取对应归档解压（PDF 走逐页渲染）。
      if (widget.localArchivePaths != null &&
          widget.localArchivePaths!.isNotEmpty) {
        final archive =
            await resolveSafUri(widget.localArchivePaths![_chapterIndex]);
        if (archive.toLowerCase().endsWith('.pdf')) {
          imgs = await extractPdfPages(archive);
          if (imgs.isNotEmpty) _pdfCacheDir = File(imgs.first).parent.path;
        } else {
          imgs = await _extractCbz(archive);
        }
      } else if (widget.localChapterDirs != null &&
          widget.localChapterDirs!.isNotEmpty) {
        // 本地下载聚合：按当前话索引取对应图片子目录，收集排序后的图片路径。
        final dirPath =
            await resolveSafUri(widget.localChapterDirs![_chapterIndex]);
        imgs = await _gatherDirImages(dirPath);
      } else if (widget.localImages != null && widget.localImages!.isNotEmpty) {
        imgs = List<String>.unmodifiable(widget.localImages!);
      } else if (widget.localPdfPath != null) {
        // PDF：逐页渲染成图片后复用现有看图管线。
        final local = await resolveSafUri(widget.localPdfPath!);
        imgs = await extractPdfPages(local);
        if (imgs.isNotEmpty) _pdfCacheDir = File(imgs.first).parent.path;
      } else if (widget.localCbzPath != null) {
        // SAF 编码路径（content://…␟…）须先落缓存（其余分支同理），否则
        // 解压器 dart:io 直读失败 → "本地文件读取失败"。
        imgs = await _extractCbz(await resolveSafUri(widget.localCbzPath!));
      } else {
        imgs = const <String>[];
      }
      // 期间若又发起了更新的加载（快速翻话 / 初始与切换并发），丢弃本次过期结果。
      if (!mounted || !_loadSession.isValid(token)) return;
      if (imgs.isEmpty) {
        AppLog.instance.w('[漫画加载失败] ${widget.title}: 本地图片为空 '
            '(cbz=${widget.localCbzPath != null}, '
            'pdf=${widget.localPdfPath != null}, '
            'dir=${widget.localImages?.length ?? 0}张)');
        setState(() {
          _images = const <String>[];
          _loading = false;
          _error = AppLocalizations.of(context).localFileLoadFailed;
        });
        return;
      }
      setState(() {
        _images = imgs;
        _loading = false;
        _error = null;
      });
      // 章节图片就绪后刷新当前页图片收藏状态。
      unawaited(_refreshPageImageFav());
      // 进入新章节（睡眠定时按话数计数；首次加载由 _sleepPrimeLoaded 排除）。
      _onChapterEntered();
      // 预载提前（本地聚合）：章节加载完成即预载过滤后的相邻目标章（跳过已读/
      // 被过滤章）。本地解压慢，若等滚到章末才触发预载（_maybePreload），
      // seam 无缝列表常缺邻段 → 章末要手动跳/章首翻不了上一话。此处提前开始
      // 解压，用户滚到边界时邻章通常已就绪，直接无缝衔接。
      _preloadAdjacentTargets();
      // 回到上一话末页时 restoreToLast=true（与在线 [_loadChapter] 对齐）：
      // 翻页模式直接落末页，条漫模式先落首页、首帧后再滚动到底（见 [_loadChapter]）。
      final bool lastPage = restoreToLast && imgs.isNotEmpty;
      final bool deferToLast = lastPage && _prefs.readingMode.isWebtoon;
      final int rp = lastPage && !deferToLast ? imgs.length - 1 : restorePage;
      _setupControllers(restorePage: deferToLast ? 0 : rp);
      if (deferToLast) {
        _pendingWebtoonScrollToLast = true;
      } else {
        _saveProgress(rp);
      }
    } on Object catch (e) {
      AppLog.instance.eWithStack(
          '[漫画加载异常] ${widget.title} (cbz=${widget.localCbzPath != null}, '
          'pdf=${widget.localPdfPath != null})',
          e);
      if (!_loadSession.isValid(token) || !mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 解压漫画归档取图片路径（多格式：ZIP/CBZ、TAR/CBT、7z/CB7、RAR/CBR 含 RAR5）。
  ///
  /// 委托 [extractArchiveImages]（基于 [koni_archive]，纯 Dart 无需原生库），
  /// 使 .cbr/.rar/.7z 等原 [ZipDecoder] 无法处理的格式真正可用。保留自然排序，
  /// 保证页码顺序正确。
  /// SAF 感知：若 [path] 为 Android content:// URI，先经 [resolveSafUri] 落到应用
  /// 缓存再解压（C 阶段：手机端 SAF 文件夹导入）；
  /// 解压产物落在独立子目录并登记到 [_archiveTempDirs]，退出阅读器时整体删除
  /// （资源回收，不再滞留系统临时目录）。
  Future<List<String>> _extractCbz(String path) async {
    final local = await resolveSafUri(path);
    final ex = await extractArchiveImagesToDir(local);
    _archiveTempDirs.add(ex.dir);
    return ex.files;
  }

  /// 收集本地图片子目录内、按文件名排序的图片路径列表（每话一目录的下载产物）。
  ///
  /// SAF content:// 目录 URI 用 [gatherSafImages]；真实路径目录用 dart:io 列目录。
  /// 返回空列表表示该话目录无可读图片（避免「空目录」假完成）。
  Future<List<String>> _gatherDirImages(String dirPath) async {
    if (isDocUri(dirPath)) {
      final list = await gatherSafImages(dirPath);
      return list..sort(naturalCompare);
    }
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return const <String>[];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => isImageFile(f.path))
        .map((f) => f.path)
        .toList()
      ..sort(naturalCompare);
  }

  /// 刷新收藏状态（init 与切换收藏后调用）。
  void _refreshFavorite() {
    final fav = context.read<FavoritesManager>();
    _isFav = fav.isFavorite(widget.comicId, SourceType.mangaSource);
  }

  /// 当前页图片 URL（无图 / 空列表时返回 null）。
  String? get _currentPageImageUrl {
    if (_images.isEmpty) return null;
    final int idx = _currentPage.clamp(0, _images.length - 1);
    final String url = _images[idx];
    return url.isEmpty ? null : url;
  }

  /// 当前章标题（无章节概念时为作品标题）。
  String get _currentChapterTitle {
    // 本地单文件（无章节表）无章节概念；归档/下载目录聚合均有章节表。
    if (_isLocalMode && widget.chapters.isEmpty) return widget.title;
    if (_chapterIndex < widget.chapters.length) {
      final t = widget.chapters[_chapterIndex].title;
      if (t.isNotEmpty) return t;
    }
    return widget.title;
  }

  /// 刷新当前页图片收藏状态（init / 翻页 / 切换后调用）。
  ///
  /// 按图片地址查询（而非位置键）：源站章节/页码列表顺序漂移或经不同入口
  /// 进入时位置键会变，按 URL 判定才能正确还原「已收藏」状态。
  Future<void> _refreshPageImageFav() async {
    final String? url = _currentPageImageUrl;
    if (url == null) return;
    try {
      final bool fav = await _imageFavMgr.isFavoriteByUrl(url);
      if (mounted && fav != _isPageImageFav) {
        setState(() => _isPageImageFav = fav);
      }
    } on Object {
      // Hive 未初始化（测试/启动早期）时静默保持未收藏状态。
    }
  }

  /// 收藏 / 取消收藏当前页图片（顶栏与长按菜单入口）。
  Future<void> _toggleCurrentPageImageFavorite() async {
    final String? url = _currentPageImageUrl;
    if (url == null) return;
    final l10n = AppLocalizations.of(context);
    final bool added;
    try {
      // URL 身份去重：避免章节/页码顺序漂移导致收藏重启后「丢失」。
      added = await _imageFavMgr.toggleComicImage(
        comicId: widget.comicId,
        chapterIndex: _chapterIndex,
        chapterTitle: _currentChapterTitle,
        pageIndex: _currentPage,
        imageUrl: url,
      );
    } on Object {
      // Hive 不可用（测试环境）时静默忽略。
      return;
    }
    if (mounted) {
      setState(() => _isPageImageFav = added);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(added ? l10n.imageFavoriteAdded : l10n.imageFavoriteRemoved),
        ),
      );
    }
    if (added) {
      // 收藏即缓存到本地（取消收藏时才删文件，清理缓存不清理；
      // Referer 用章节页推导值——部分源按图片↔章节页绑定校验）。
      unawaited(_imageFavMgr.attachLocalCache(url, referer: _refererFor(url)));
    }
  }

  /// 打开图片收藏图库（漫画入口仅显示漫画收藏）。
  void _openImageFavoriteGallery() {
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => const ImageFavoriteGalleryScreen(
          sourceFilter: ImageFavoriteSource.comic,
        ),
      ),
    );
  }

  /// 切换收藏状态（顶栏收藏按钮回调）。
  Future<void> _toggleFavorite() async {
    final l10n = AppLocalizations.of(context);
    final fav = context.read<FavoritesManager>();
    final wasFavorite = _isFav;
    final item = MediaItem(
      id: widget.comicId,
      title: widget.title,
      sourceId: widget.sourceId,
      sourceType: SourceType.mangaSource,
      detailUrl: widget.detailUrl,
      coverUrl: widget.coverUrl,
    );
    await fav.toggleFavorite(item);
    if (mounted) {
      setState(() => _isFav = !wasFavorite);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(wasFavorite ? l10n.favoriteRemoved : l10n.favoriteAdded),
        ),
      );
    }
  }

  /// 收藏按钮入口：源声明网络收藏时弹「本地/网络」双选项，否则直接本地收藏。
  Future<void> _onFavoritePressed() async {
    final MediaItem item = MediaItem(
      id: widget.comicId,
      title: widget.title,
      sourceId: widget.sourceId,
      sourceType: SourceType.mangaSource,
      detailUrl: widget.detailUrl,
      coverUrl: widget.coverUrl,
    );
    final PluginConfig? source =
        context.read<SourceRepository>().getById(widget.sourceId);
    if (source == null) {
      await _toggleFavorite();
      return;
    }
    await showFavoriteSheet(
      context: context,
      source: source,
      item: item,
      toggleLocalFavorite: _toggleFavorite,
    );
  }

  /// 收藏按钮弹出菜单：收藏作品 / 收藏当前页图片 / 打开图片收藏图库。
  /// 底栏单个收藏按钮的点击入口（原底栏两个图标 + 顶栏收藏按钮合并而来）。
  void _showFavoriteMenu() {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: Icon(_isFav
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded),
              title: Text(l10n.favorite),
              onTap: () {
                Navigator.of(ctx).pop();
                _onFavoritePressed();
              },
            ),
            // 本地单文件无章节概念时隐藏（与长按菜单「收藏此章」入口置空一致）。
            if (!_isLocalMode || widget.chapters.isNotEmpty)
              ListTile(
                leading: Icon(
                  _chapterBookmarked
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  color: _chapterBookmarked ? Colors.amber : null,
                ),
                title: Text(l10n.readerChapterBookmark),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _toggleChapterBookmark();
                },
              ),
            ListTile(
              leading: Icon(
                _isPageImageFav
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: _isPageImageFav ? Colors.amber : null,
              ),
              title: Text(l10n.readerFavoriteImage),
              onTap: () {
                Navigator.of(ctx).pop();
                _toggleCurrentPageImageFavorite();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: Text(l10n.readerImageFavorite),
              onTap: () {
                Navigator.of(ctx).pop();
                _openImageFavoriteGallery();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 刷新当前章书签状态（init 与翻章后调用）。
  Future<void> _refreshChapterBookmark() async {
    try {
      final bool on = await _bookmarks.hasBookmark(
        widget.comicId,
        _chapterIndex,
      );
      if (mounted) setState(() => _chapterBookmarked = on);
    } on Object {
      // Hive 未初始化（测试/启动早期）或数据损坏时静默保持未书签状态。
    }
  }

  /// 顶栏书签 toggle：已书签则取消，否则添加当前章书签。
  Future<void> _toggleChapterBookmark() async {
    final l10n = AppLocalizations.of(context);
    final chapter =
        widget.chapters.isEmpty ? null : widget.chapters[_chapterIndex];
    final bool added;
    try {
      added = await _bookmarks.toggleChapter(
        widget.comicId,
        _chapterIndex,
        chapterId: chapter?.id ?? '',
        chapterTitle: chapter?.title ?? '',
      );
    } on Object {
      // Hive 不可用（测试环境）时静默忽略。
      return;
    }
    if (!mounted) return;
    setState(() => _chapterBookmarked = added);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added
              ? l10n.readerChapterBookmarked
              : l10n.readerChapterBookmarkRemoved,
        ),
      ),
    );
  }

  /// 已书签章节索引集合（供目录面板过滤/标注）。
  Future<Set<int>> _bookmarkedIndices() async {
    try {
      final list = await _bookmarks.listFor(widget.comicId);
      return list.map((b) => b.chapterIndex).toSet();
    } on Object {
      return const <int>{};
    }
  }

  /// 长按图片菜单「收藏此章」回调：本地单文件无章节概念时入口置空。
  Future<bool> _toggleChapterBookmarkFromMenu() async {
    if (_isLocalMode && widget.chapters.isEmpty) return false;
    await _toggleChapterBookmark();
    return _chapterBookmarked;
  }

  @override
  void dispose() {
    if (_continuationToken != null) {
      HarmonyContinuation.detach(_continuationToken!);
      _continuationToken = null;
    }
    // 兜底提交设备/会话层草稿：设置面板开着直接退出阅读器（返回键 / 关窗）时，
    // 面板内的改动（自动翻页间隔、自动下载开关等）没有经过任何关闭路径提交，
    // 不在此落盘就会全部丢失（「设置完退出重进后消失」的根因）。
    // _store 写 shared_preferences 不依赖 context，dispose 后异步完成是安全的。
    unawaited(_commitDeviceOverride());
    // 停止漫画翻译控制器（进行中的请求结果不再写回状态）。
    _translation.dispose();
    // 退出时一次性结算本次阅读会话（commit 内部 best-effort）。
    if (widget.sourceId.isNotEmpty) {
      unawaited(ReadingSessionRecorder.instance.commit(
        workId: widget.comicId,
        sourceId: widget.sourceId,
        type: StatsMediaType.comic,
        title: widget.title,
        coverUrl: widget.coverUrl,
        source: SessionSource.comicReader,
      ));
    }
    // 读后自动删除：读完（进度到最后一章）时清理该内容已下载文件。
    unawaited(_maybeAutoDeleteDownloaded());
    _zoomController.removeListener(_onZoomChanged);
    _pageController?.dispose();
    _itemPositionsListener?.itemPositions.removeListener(_onWebtoonScroll);
    _zoomController.dispose();
    _flashController.dispose();
    _readerFocus.dispose();
    _currentPageNotifier.dispose();
    _transitionTimer?.cancel();
    _skipTransitionTimer?.cancel();
    // 清理：翻页淡入定时器、自动翻页定时器、自动滚动 Ticker 与音量键监听。
    _pageFadeTimer?.cancel();
    _autoPageTurnTimer?.cancel();
    _autoScrollTicker?.stop();
    // 睡眠定时清理。
    _sleepTimer?.cancel();
    // 停止原生音量键拦截，恢复系统默认音量键行为。
    unawaited(_volumeKeyListener.stop());
    // 移除全局键盘监听（必须在 dispose 里，否则离页后快捷键仍会触发本页翻页）。
    HardwareKeyboard.instance.removeHandler(_onGlobalKey);
    // 数据丢失修复：防抖窗口内若有 pending 写入，先立即落盘再取消定时器——否则
    // 「翻页后 1s 内退出」会丢失本次进度，下次回退到旧页。
    if (_saveProgressDebounce?.isActive ?? false) {
      final page = _pendingSavePage ?? _currentPage;
      _saveProgressDebounce?.cancel();
      _flushPendingProgress(page);
      _pendingSavePage = null;
    } else {
      _saveProgressDebounce?.cancel();
      // 兜底：无 pending 写入的正常退出，无条件把「当前页」再存一次（绝不丢进度）。
      // 不再检查 _restoringPage：恢复期间 _currentPage 保持进入时设定的恢复目标页
      // （滚动/翻页回写已被 _restoringPage 屏蔽，_setupControllers 已赋值），保存它
      // 不会污染存档；而跳过保存会在「退全屏/切屏重锚（_restoringPage 短暂为 true）
      // 后立刻退出」时丢掉全部进度（「阅读位置全部丢失」的直接根因）。
      // 仅 _images 为空（章节还没加载完成）时不存，保留旧存档。
      if (_images.isNotEmpty) {
        _flushPendingProgress(_currentPage);
      }
    }
    _webtoonStepTimer?.cancel();
    _webtoonRestoreTimer?.cancel();
    _webtoonLastPageTimer?.cancel();
    _webtoonLastPageTimeout?.cancel();
    try {
      if (PlatformService.instance.isMobile) {
        SystemChrome.setPreferredOrientations(<DeviceOrientation>[]);
      }
    } on Object {
      // 测试环境忽略。
    }
    try {
      // 退出阅读器：恢复系统 UI 模式（沉浸全屏 → edgeToEdge）。
      if (PlatformService.instance.isMobile) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    } on Object {
      // 测试环境忽略。
    }
    // 桌面端：退出阅读器时离开 OS 全屏，恢复普通窗口。
    // 用 Future.delayed(zero) 推迟到 dispose / 本帧 teardown 完全结束后的下一个
    // 事件循环轮次再执行——在 dispose 调用栈内直接切窗口会与正在拆除的渲染树
    // 抢占平台线程，是此前「退出阅读器画面冻住」的诱因之一。
    if (_isDesktop && _osFullscreenEntered) {
      Future<void>.delayed(Duration.zero, () async {
        try {
          // 仅在确实处于 OS 全屏时才退出——否则 setFullScreen(false) 也会做无谓的
          // 窗口样式重建（SetWindowLongPtr + SetWindowPos），可能触发冻结。
          if (await WindowService.instance.isFullScreen()) {
            await _requestOsFullscreen(false);
          }
        } on Object {
          // 无头 / 测试环境忽略。
        }
      });
    }
    try {
      // 退出阅读器：关闭屏幕常亮。
      WakelockPlus.disable();
    } on Object {
      // 测试环境忽略。
    }
    // 退出时兜底保存偏好，确保设置退出后仍保留。
    unawaited(_store.save(widget.comicId, _prefs, overrideKeys: _overrideKeys));
    // 清理：停止时间/电量浮层，恢复系统原亮度。
    _stopTimeAndBattery();
    _resetBrightness();
    // 退出时清理 PDF 临时渲染缓存（逐页 JPEG），避免占用磁盘。
    if (_pdfCacheDir != null) {
      unawaited(
        Future<void>(() async {
          try {
            await Directory(_pdfCacheDir!).delete(recursive: true);
          } on Object {
            // 缓存清理失败不影响退出。
          }
        }),
      );
    }
    // 资源回收：删除本次会话解压的全部归档临时目录（CBZ/CBR/7z…），
    // 与 PDF 缓存同策略——阅读器退出即不残留磁盘产物。去重后逐个 best-effort 删除。
    if (_archiveTempDirs.isNotEmpty) {
      final dirs = _archiveTempDirs.toSet().toList(growable: false);
      unawaited(
        Future<void>(() async {
          for (final dir in dirs) {
            try {
              await Directory(dir).delete(recursive: true);
            } on Object {
              // 单个目录清理失败不影响其余。
            }
          }
        }),
      );
    }
    // 资源/内存：离开阅读器把 Flutter 图片缓存预算恢复为默认（100MB），
    // 不让阅读期间按设备内存上调的预算（100–500MB）挤占书架/详情页。
    try {
      PaintingBinding.instance.imageCache.maximumSizeBytes =
          kComicImageCacheDefaultBytes;
    } on Object {
      // 测试环境忽略。
    }
    // 动态效果：取消在途渲染与防抖定时器，释放缓存字节。
    _motionDebounce?.cancel();
    _motionFollowTimer?.cancel();
    _motionToken?.cancel();
    _motionCache.clear();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 读完自动删除（漫画版）：最后一章已读且设置开启时清理下载。
  Future<void> _maybeAutoDeleteDownloaded() async {
    try {
      final dm = _downloadManager;
      if (dm == null || !dm.settings.autoDeleteAfterRead) return;
      final groupIds = _favorites?.groupIdsOf(
            widget.comicId,
            SourceType.mangaSource,
          ) ??
          const <String>[];
      if (dm.settings.isExcludedFromAutoDeleteGroups(groupIds)) return;
      final p = await _progress.get(widget.comicId);
      if (p == null || p.totalChapters == null) return;
      if (p.chapterIndex + 1 < p.totalChapters!) return;
      await dm.removeItemDownloads(widget.comicId, deleteFiles: true);
    } on Object {
      // best-effort。
    }
  }

  /// 窗口尺寸变化（全屏切换 / resize）：缩放矩阵平移夹取上界随视口尺寸而变，
  /// 旧矩阵在新视口下会偏移或越界。下一帧重夹一次，修复进出全屏时的位置偏移。
  /// 缩放矩阵是「中心原点」坐标系（见 [MangaPageImage] 的 Transform alignment），
  /// 重夹逻辑与 [MangaPageImageState._clampMatrix] 共用 [_clampZoomMatrix]。
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;
    // 同步置位（必须在 postFrame 之前）：视口尺寸变化时，布局 / 滚动阶段的
    // onPageChanged 会先于帧回调触发并污染 _currentPage（页宽变了，像素偏移对应
    // 到别的页），若等帧回调才屏蔽就来不及了（进度条跳页）。
    final bool wasRestoring = _restoringPage;
    _restoringPage = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final Size vp = MediaQuery.of(context).size;
      final m = _zoomController.value;
      _zoomController.value = _prefs.readingMode.isWebtoon
          ? _clampWebtoonZoomMatrix(
              Matrix4.copy(m), vp, _currentWebtoonContentHeight(vp))
          : _clampZoomMatrix(Matrix4.copy(m), vp);
      // 视口尺寸变化（全屏切换 / 拖窗口边角）后，PageView 的像素偏移对应页索引会
      // 漂移（页宽变了），进度条会跳到别的页。重新把当前页锚回视口。
      if (_images.isNotEmpty) {
        _anchorCurrentPage(_currentPage);
      }
      _restoringPage = wasRestoring;
    });
  }

  /// 退出时的最小化进度落盘：仅写核心进度，避免依赖 context 的衍生写
  /// （收藏 lastRead / 浏览历史 / 已读标记）在 widget 已销毁时抛异常。
  void _flushPendingProgress(int page) {
    if (widget.chapters.isEmpty) return;
    try {
      final chapter = widget.chapters[_chapterIndex];
      _progress.save(
        widget.comicId,
        chapter.id,
        page,
        _chapterIndex,
        totalChapters: widget.chapters.length,
      );
    } on Object {
      // 极端情况下静默忽略，不阻塞退出。
    }
  }

  // ─────────────────────── 数据加载 ───────────────────────

  /// 登记一批图片的取图 Referer（章节页 URL 推导，见 [_urlReferers] 注释）。
  /// best-effort：章节页 URL 非法（本地章节等）时静默跳过。
  void _registerImageReferers(List<String> urls, String chapterPageUrl) {
    for (final String u in urls) {
      final String? referer =
          HttpFetcher.refererForSubresource(chapterPageUrl, u);
      if (referer != null && referer.isNotEmpty) _urlReferers[u] = referer;
    }
  }

  /// 查询某图片 URL 的取图 Referer（未登记返回 null → 回退源 antiHotlinking）。
  String? _refererFor(String imageUrl) => _urlReferers[imageUrl];

  Future<void> _loadChapter(int index,
      {int restorePage = 0, bool restoreToLast = false}) async {
    final int token = _loadSession.next();
    // 翻章后刷新顶栏章节书签状态。
    unawaited(_refreshChapterBookmark());
    if (mounted) setState(() => _loading = true);
    try {
      final source = _repo.getById(widget.sourceId);
      if (source == null)
        throw Exception('source not found: ${widget.sourceId}');
      _source = source;
      // 翻译控制器的防盗链 headers 需要源配置（源异步加载后补传）。
      _translation.updateSource(source);
      final chapter = widget.chapters[index];
      final List<String> imgs = _preload.remove(index) ??
          await _service.fetchImages(
            source,
            comicId: widget.comicId,
            chapterId: chapter.id,
            renderedHtml: _renderedHtmlByChapter[index],
          );
      // 登记本章图片的取图 Referer（章节页 URL 推导，见 _urlReferers 注释）。
      _registerImageReferers(imgs, chapter.url);
      // 翻译控制器 OCR 拉图同源指纹：同步当前章节页 URL 供 Referer 推导。
      _translation.updateChapterPageUrl(chapter.url);
      // 期间若又发起了更新的加载（快速翻章），丢弃本次过期结果，
      // 避免旧章节的图片覆盖到新 _chapterIndex 上导致显示错乱。
      if (!_loadSession.isValid(token) || !mounted) return;
      // 回到上一话末页时 restoreToLast=true。
      // 翻页模式直接把落点设为末页（PageView 首帧即定位，无中间态）。
      // 条漫模式则先落首页、待首帧布局完成后再主动滚动到底：切章瞬间图片尚未
      // 完成布局，此时若直接以末页作为初始索引，后续图片加载引起的高度变化会
      // 让「当前页」的测量回退到倒数几页（表现为进度回弹）。改为加载后主动滚动，
      // 结束时直接赋值末页，不依赖任何测量结果。
      final bool lastPage = restoreToLast && imgs.isNotEmpty;
      final bool deferToLast = lastPage && _prefs.readingMode.isWebtoon;
      final int rp = lastPage && !deferToLast ? imgs.length - 1 : restorePage;
      setState(() {
        _images = imgs;
        _loading = false;
        _error = null;
      });
      // 章节图片就绪后刷新当前页图片收藏状态。
      unawaited(_refreshPageImageFav());
      // 进入新章节（睡眠定时按话数计数；首次加载由 _sleepPrimeLoaded 排除）。
      _onChapterEntered();
      // 预载提前：章节加载完成即预载过滤后的相邻目标章（跳过已读/被过滤章），
      // 让 seam 无缝列表在用户滚到边界前就绪，章末/章首直接无缝衔接。
      _preloadAdjacentTargets();
      // 切章时重置缩放/平移，避免上一话的缩放状态残留到新章（手势 bug）。
      _resetZoom();
      _setupControllers(restorePage: deferToLast ? 0 : rp);
      if (deferToLast) {
        // 首帧后由 _buildWebtoon 消费：滚动到底并在收尾时写入末页进度。
        _pendingWebtoonScrollToLast = true;
      } else {
        _saveProgress(rp);
      }
    } on WebViewHtmlRequest catch (req) {
      // useWebview 脚本源（部分源）需在内嵌 WebView
      // 加载章节页、等待 JS 渲染后取回整页 HTML，再回灌给脚本解析图片。
      // 捕获请求后展示「抓取本页渲染内容」引导，用户触发回填并重试。
      if (!_loadSession.isValid(token) || !mounted) return;
      if (mounted) {
        setState(() {
          _htmlCaptureRequest = req;
          _loading = false;
          _error = null;
        });
      }
    } on Object catch (e) {
      if (!_loadSession.isValid(token) || !mounted) return;
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// 渲染后抽取完成后回填 HTML 并重试抓取当前章节图片（webview-html 源）。
  Future<void> _captureAndRetry() async {
    final req = _htmlCaptureRequest;
    if (req == null || !mounted) return;
    final outcome = await navigateToHtmlCapture(context, request: req);
    if (!mounted) return;
    if (outcome?.hasRenderedHtml == true && outcome!.renderedHtml != null) {
      _renderedHtmlByChapter[_chapterIndex] = outcome.renderedHtml!;
      setState(() => _htmlCaptureRequest = null);
      await _loadChapter(_chapterIndex, restorePage: _currentPage);
    } else {
      // 用户取消或未取到渲染 HTML：退回错误态，可重试或退出。
      if (mounted) {
        setState(() {
          _htmlCaptureRequest = null;
          _error = AppLocalizations.of(context).loadFailed;
          _loading = false;
        });
      }
    }
  }

  void _setupControllers({int restorePage = 0, bool wasDoublePage = false}) {
    // 缓存清理策略：预载图列表与渲染 HTML 缓存此前只增不减，长阅读会话
    // （数百章）会持续吃内存。按当前章保留 ±2 章窗口（seam 无缝续读仅用 ±1，
    // 窗口留一档余量），窗口外的条目直接淘汰；重读时按原路径重新抓取/解压。
    final int lo = _chapterIndex - 2;
    final int hi = _chapterIndex + 2;
    _preload.removeWhere((k, _) => k < lo || k > hi);
    _renderedHtmlByChapter.removeWhere((k, _) => k < lo || k > hi);
    // 段式连续模型依赖 [_images]/[_prefs]/[_preload] 的当前状态：本章数据就绪后
    // （[loadChapter]/[_loadLocalImages] 已写入 [_images]）或偏好变化后（[applySettingsAuto]/
    // [_onPrefsChanged] 已更新 [_prefs]）在此重建扁平列表；paged/非 seamless 时清空 seam。
    _rebuildSeam();
    // 切章/切设置时收起跳章过渡提示并取消延时跳转（此方法末尾已有 setState）。
    _skipTransitionTimer?.cancel();
    _skipTransitionTimer = null;
    _showSkipTransition = false;
    // 旧控制器延迟到下一帧释放：避免旧 PageView 在 dispose→setState 之间
    // 访问已释放控制器导致崩溃/白屏，从而进度条/页码没有更新。
    final PageController? oldPageController = _pageController;
    _pageController = null;
    _itemScrollController = null;
    _itemPositionsListener = null;
    // 双页→单页修正：双页模式下 _currentPage 指向跨页左页（如 20 页的第 18 页），
    // 切回单页后 PageView 实际显示左页（18），但用户感知在右页（19，末页）。
    // 将 restorePage 修正为右页，确保末页点击「下一张」能正确跳下一章。
    if (wasDoublePage && !_isDoublePage && _images.isNotEmpty) {
      final lastLeftPage = ((_images.length - 1) ~/ 2) * 2;
      if (restorePage >= lastLeftPage && restorePage < _images.length) {
        restorePage = _images.length - 1;
      }
    }

    if (_prefs.readingMode.isPaged) {
      // 越界保护：initialPage 必须在 [0, itemCount-1]，否则 PageView 抛异常
      // 导致双页/单页切换后白屏（隐藏崩溃防护）。
      final int maxInitial = (_controllerPageCount - 1).clamp(0, 1 << 30);
      final int initial;
      if (_isDoublePage) {
        initial = _doublePageSpreadFor(restorePage).clamp(0, maxInitial);
      } else if (_isGalleryMode) {
        // 每屏多图：一屏 = N 张图，initial = 屏号（页索引 ÷ N）。
        initial = (restorePage ~/ _galleryCount).clamp(0, maxInitial);
      } else {
        initial = restorePage.clamp(0, maxInitial);
      }
      // 逻辑页码：双页模式取当前跨页左页、gallery 取当前屏首图，与 _onPagedScroll
      // 保持一致，保证进度条 / 保存值与可见页面对齐。
      final int logicalPage;
      if (_isDoublePage) {
        logicalPage =
            _doublePageLeftPageFor(initial).clamp(0, _images.length - 1);
      } else if (_isGalleryMode) {
        logicalPage = (initial * _galleryCount).clamp(0, _images.length - 1);
      } else {
        logicalPage = initial;
      }

      // 每章使用独立 Key（见 _buildPaged / _buildPagedSpread），PageView 会创建
      // 全新的 ScrollPosition，initialPage 必定生效，不再依赖 jumpToPage 强跳。
      // 这彻底消除了「切章后图片停在旧页 / 回上一话末页却回弹到倒数几页」两类问题
      // —— 它们都源于复用旧 ScrollPosition 时 initialPage 被忽略。
      _pageController = PageController(initialPage: initial)
        ..addListener(_onPagedScroll);

      _currentPage = logicalPage;
      // 首帧布局期间（旧控制器残留通知 / 新 position 初始化）屏蔽进度写盘，
      // 防止脏页码冲掉存档。首帧后即可恢复。
      _restoringPage = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // 兜底纠偏：每章已用独立 Key 重建全新 ScrollPosition，initialPage 必定生效，
        // 此处仅在极端布局时序下 position 未停在目标页时，以「瞬时」jumpToPage 纠正。
        // jumpToPage 为瞬时跳转（不经动画），不会产生回弹；且下方 _restoringPage
        // 解除前的通知已被 _onPagedScroll 忽略，不会污染 _currentPage / 存档。
        if (_pageController != null && _pageController!.hasClients) {
          final cur = _pageController!.page?.round() ?? -1;
          if (cur != initial) _pageController!.jumpToPage(initial);
        }
        // 先解除屏蔽再释放旧控制器：确保即便 dispose 抛异常，_restoringPage
        // 也一定复位，否则会永久冻结进度保存与进度条同步。
        _restoringPage = false;
        oldPageController?.dispose();
        if (mounted) setState(() {});
      });
    } else {
      // 条漫模式：使用 ScrollablePositionedList，通过 initialScrollIndex
      // 直接定位到目标页，不再依赖滚动比例估算。
      // 先摘除旧监听器并断开旧列表引用：旧列表在卸载/重布局时会把「上一章页码」
      // 经 _onWebtoonScroll 推过来，而此时 _images 已是新章，旧页码被截断后落到
      // 新章末页，导致进度条显示在末页（实际需要显示首页）。这是进度条错乱的根因。
      _itemPositionsListener?.itemPositions.removeListener(_onWebtoonScroll);
      _itemScrollController = null;
      _itemPositionsListener = null;
      _webtoonOffsetController = null;
      _webtoonViewport = null;
      // 换章后取消上一章遗留的翻页/恢复定时器与边界拖拽累计，
      // 避免旧列表的未决判定误触发换章。
      _webtoonStepTimer?.cancel();
      _webtoonStepTimer = null;
      _webtoonRestoreTimer?.cancel();
      _webtoonRestoreTimer = null;
      _webtoonLastPageTimer?.cancel();
      _webtoonLastPageTimer = null;
      _webtoonLastPageTimeout?.cancel();
      _webtoonLastPageTimeout = null;
      _webtoonPhaseJumped = false;
      _webtoonMaxExtent = null;
      _webtoonPrevExtent = null;
      _webtoonExtentStableCount = 0;
      _pendingWebtoonScrollToLast = false;
      _overscrollAccum = 0;
      // 新话图片 URL 全换，清空加载标记，避免旧话 URL 误判为已加载。
      _webtoonLoadedUrls.clear();
      // 切章/恢复期间屏蔽进度回写：直到 _buildWebtoon 首帧后由 _restoringPage=false
      // 解除。期间任何滚动通知（旧列表残留或初始布局）都不会污染 _currentPage/存档。
      _restoringPage = true;
      _itemScrollController = ItemScrollController();
      _webtoonOffsetController = ScrollOffsetController();
      final listener = ItemPositionsListener.create();
      _itemPositionsListener = listener;
      // 立即注册监听：_restoringPage 期间 _onWebtoonScroll 会早退，初始布局不会污染。
      listener.itemPositions.addListener(_onWebtoonScroll);
      // 用完整值（含 0）作为一次性恢复标记，确保首帧后无论恢复到第几页都解除屏蔽。
      _pendingWebtoonRestore = restorePage;
      _currentPage = restorePage.clamp(0, _images.length - 1);
      oldPageController?.dispose();
    }
    // 动态效果：章节/模式就绪后重估当前屏渲染任务（推迟一帧等控制器挂载）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleMotion();
    });
    if (mounted) setState(() {});
  }

  void _onPagedScroll() {
    // 恢复进度期间的过渡页码不回写，避免冲掉存档。
    if (_restoringPage) return;
    final p = _pageController?.page;
    if (p == null) return;
    if (_controllerPageCount == 0) return;
    final controllerMax = _controllerPageCount - 1;
    final spreadIdx = p.round().clamp(0, controllerMax);
    // 双页模式以跨页的【左页】作为当前逻辑页；gallery 以当前屏【首图】为准。
    // 这样切回单页时不会跳到右页，进度条/保存也更稳定。
    // 章末过渡卡页（多算的一页）钳回章内末页：过渡卡上进度仍显示 100%。
    final int rawIdx;
    if (_isDoublePage) {
      rawIdx = _doublePageLeftPageFor(spreadIdx);
    } else if (_isGalleryMode) {
      rawIdx = spreadIdx * _galleryCount;
    } else {
      rawIdx = spreadIdx;
    }
    final int idx = rawIdx.clamp(0, _images.isEmpty ? 0 : _images.length - 1);
    if (idx != _currentPage) {
      _currentPage = idx;
      _scheduleProgressSave(idx);
      // 索引变化时刷新进度条（页码/滑条），否则点按翻页后进度条不更新。
      if (mounted) setState(() {});
      // 翻页后刷新当前页图片收藏状态。
      unawaited(_refreshPageImageFav());
    }
    _maybePreload(idx);
    // 动态效果：翻页停定后重估当前屏渲染任务（内部有驻留防抖）。
    _scheduleMotion();
  }

  /// 列表中是否存在已按真实图片尺寸布局的项（高度明显大于占位）。
  /// 图片未加载时所有项都是占位小高度（≈0.05 视口），此值为 false；
  /// 一旦任一真实漫画页加载完成（高度 ≥ [_kMinRealItemHeight] 视口），即为 true。
  /// 用于在占位期禁用「到底修正 / 尺寸稳定判据」，避免把「整章缩成一屏」的占位
  /// 布局误当成已滚到底或尺寸已稳定。
  bool _hasRealSizedItem(Iterable<ItemPosition> positions) {
    for (final p in positions) {
      final double h = p.itemTrailingEdge - p.itemLeadingEdge;
      if (h > _kMinRealItemHeight) return true;
    }
    return false;
  }

  void _onWebtoonScroll() {
    // 恢复进度期间的过渡位置不回写，避免冲掉存档。
    if (_restoringPage) return;
    // 重锚段式连续模型（跨章无缝续读）期间，扁平索引与真实索引的对应关系正在
    // 切换，滚动回调在此期间不作任何写入，避免污染进度（见 _rebuildSeam）。
    if (_seamReanchoring) return;
    final listener = _itemPositionsListener;
    if (listener == null) return;
    final positions = listener.itemPositions.value;
    if (positions.isEmpty) return;
    // 仅保留真正在视口内的 item（leadingEdge<1 未完全滚出底部，trailingEdge>0 未完全滚出顶部）。
    final visible = positions
        .where((p) => p.itemLeadingEdge < 1 && p.itemTrailingEdge > 0)
        .toList();
    if (visible.isEmpty) return;
    // 段式连续模型（跨章无缝续读）：扁平列表里每条 item 对应「真实页」或
    // 「章分割/过渡」条目。当前页取视口内最顶部可见项，再经 [_resolveSeamIndex]
    // 映射回真实页索引；分隔条目/邻段页一律先按「读取中页」处理，防止滚动回调在
    // 越界预加载期把越界页码写进当前章存档（由重锚时统一修正）。
    final int flatIdx =
        visible.map((p) => p.index).reduce((a, b) => a < b ? a : b);
    // 跨段边界自动重锚：视口顶部已滚入邻段页条目（而非章分割条目）即无缝切章。
    // 重锚成功后本回调立即返回（重锚期间索引换算不可信，进度由重锚收尾统一写盘）；
    // 未真正重锚（越界/目标未就绪）时回落到常规进度处理。
    if (_seamActive && _seam.isNotEmpty) {
      final _SeamSegment? seg = _seamSegmentAt(flatIdx);
      if (seg != null && seg.chapterIndex > _chapterIndex) {
        // 跳章过滤：滚入下一段时若相邻章应被跳过（已读/被筛选/重复），
        // 不无缝重锚到相邻章，而是直接整章加载到过滤后的目标章，避免条漫下
        // 「跳章过滤不生效」。
        final int? resolved = _resolveChapterTarget(1);
        if (resolved == null || resolved != seg.chapterIndex) {
          if (resolved == null) return;
          _jumpToChapter(resolved);
          return;
        }
        if (_seamAdvance(1)) return;
      } else if (seg != null && seg.chapterIndex < _chapterIndex) {
        final int? resolved = _resolveChapterTarget(-1);
        if (resolved == null || resolved != seg.chapterIndex) {
          if (resolved == null) return;
          _jumpToChapter(resolved);
          return;
        }
        // 从当前章【首页】上翻进上一段：与向下方向一致用 keep 无缝重锚——把视口
        // 钉在原位平滑读入上一话末页，不瞬时 jumpTo 到「离开页/末页」（连续阅读
        // 上翻被瞬间跳走）。显式入口（「上一章」按钮/快捷键/目录点选）仍恢复离开页
        // （见 [_goPrevChapter]），不受影响。
        if (_seamAdvance(-1)) {
          return;
        }
      }
    }
    // 到底修正：最后一项的底边 == 列表内容末端，一旦它不在视口下方（trailingEdge<=1）
    // 就说明已经滚到底、再也滚不动了，当前页必然是末页。窄屏（或末页为短图）时一屏能
    // 容下多张，顶部项会停在 N-2/N-3，仅靠顶部模型永远到不了末页 —— 这里补齐该边界。
    // 未到底时最后一项底边仍在视口下方（trailingEdge>1），不触发，故进度不会提前满格。
    // seam 模式下「最后一项」是扁平列表末条目（可能落在下一段），此时以邻段页为准；
    // 非 seam 模式下回落到真实页末位。
    final int lastIndex = _seamActive && _seamItemCount > 0
        ? _seamItemCount - 1
        : _images.length - 1;
    bool atVeryEnd = false;
    if (lastIndex >= 0 && _hasRealSizedItem(positions)) {
      for (final p in positions) {
        // 容差 2e-3 覆盖 itemTrailingEdge 的像素取整误差（约 0.5px / 视口高）。
        if (p.index == lastIndex && p.itemTrailingEdge <= 1.0 + 2e-3) {
          atVeryEnd = true;
          break;
        }
      }
    }
    // 条漫跳章过滤边界：当前章已是 seam 最后一段（下一章因已读/
    // 被筛选/未预载未纳入无缝列表），无缝列表已到头——滚到章末不再直接整章跳转，
    // 而是显示「下一章：{标题}」过渡提示（短暂停留或点击后跳转），改善连续性感知。
    // 条漫「直接连着读」（参照库语义）：滚到章末、且下一可导航章尚未纳入无缝
    // 列表（预载未完成 / 中间隔着被过滤的已读章）时，不再弹「下一章」横幅等待
    // 点击或 1.8s 延时，直接整章加载目标章（_goNextChapter 内部优先无缝重锚，
    // 失败才整章加载），保证连续阅读不中断。
    // 若已到最后一章（无下一可导航章）则回落常规到底修正路径。
    if (_seamActive &&
        _seam.isNotEmpty &&
        atVeryEnd &&
        _seam.last.chapterIndex == _chapterIndex &&
        _resolveChapterTarget(1) != null) {
      _goNextChapter();
      return;
    } else if (_showSkipTransition) {
      // 用户已滚离章末 / 下一章已纳入无缝列表（条件不再成立）：收起过渡提示并
      // 取消延时跳转，避免横幅停留在已读内容上方或延时到期后误跳章。
      _hideSkipTransition();
    }
    final int idx = _resolveSeamIndex(flatIdx, atVeryEnd: atVeryEnd);
    if (idx != _currentPage) {
      _currentPage = idx;
      _scheduleProgressSave(idx);
      // 自动滚动期间不整屏 setState、不做图片收藏异步刷新：页码指示由
      // [_currentPageNotifier] 驱动的 ValueListenableBuilder 局部刷新（只重建
      // 底栏滑条/页码小部件，不触碰图片列表）。此前每张图顶端触顶都整屏重建，
      // 会在滚动动画进行中打断帧节奏——且条漫图高远超限频窗口，限频也拦不住
      // 每个边界一次的全量重建（「图片顶到屏幕顶端时卡一下」的根因）。
      if (!_autoScrolling) {
        unawaited(_refreshPageImageFav());
        if (mounted) setState(() {});
      }
    }
    _maybePreload(idx);
    // 动态效果：滚动停定（防抖窗口无新滚动）后重估可见页渲染任务。
    // 恢复进度 / seam 重锚期间本回调已提前返回，不会误调度。
    _scheduleMotion();
  }

  /// 防抖进度保存：合并频繁翻页产生的写入，避免高频 IO。
  /// 滚动回调中使用；_jumpToPage / _setupControllers 中仍直接调用 _saveProgress。
  void _scheduleProgressSave(int page) {
    // 每章页码即时记录（不防抖）：离开本章那一帧就写入，供「回到上一话」恢复离开页。
    // 防抖只作用于「最近章+页」单条记录，per-chapter 若也防抖会被后续新章页覆盖丢失。
    final int ci = _chapterIndex;
    _chapterPageCache[ci] = page;
    unawaited(_progress.saveChapterPage(widget.comicId, ci, page));
    // 记录 pending 页码，dispose 时若有未触发的写入可立即 flush（数据丢失修复）。
    _pendingSavePage = page;
    _saveProgressDebounce?.cancel();
    _saveProgressDebounce = Timer(const Duration(seconds: 1), () {
      // 用最新的 _pendingSavePage（而非闭包捕获的入参）触发保存：防抖窗口内
      // 页码若被其它路径更新，仍以最新页码落盘，确保 _maybeAutoDownload 等
      // 依赖最新进度（越过 25%）的判定不会被旧页码卡住（自动下载不触发）。
      final int p = _pendingSavePage ?? page;
      // 防抖到期时若已切章（seam 重锚 / 整章加载），`_chapterIndex` 已是新章——
      // 直接 `_saveProgress(p)` 会把【旧章的页码】写到【新章】名下，造成
      // 「切章后进度错乱/丢失」（重进回退到错误章页）。此时仅把该页补写进
      // 原章的 per-chapter 记录（「回到上一话」仍能恢复离开页），主记录保持新章；
      // 原章进度若已达标，同样补记已读（与进度一致）。
      if (_chapterIndex != ci) {
        unawaited(_progress.saveChapterPage(widget.comicId, ci, p));
        _maybeMarkChapterWatched(p, chapterIndex: ci);
      } else {
        _saveProgress(p);
      }
      _pendingSavePage = null;
    });
  }

  void _maybePreload(int idx) {
    // 本地多章模式（聚合本地 / 本地下载目录）走本地取图预载，其余在线预载。
    final bool localMulti = _isAggregatedLocal ||
        (widget.localChapterDirs != null &&
            widget.localChapterDirs!.isNotEmpty);
    // 接近章末：预加载过滤后的下一章（跳过已读/被过滤/重复章），
    // 末页翻下一张不再等待网络。
    if (idx >= _images.length - _prefs.preloadImageCount) {
      final int? nextTarget = _resolveChapterTarget(1);
      if (nextTarget != null) {
        if (localMulti) {
          unawaited(_preloadChapterLocal(nextTarget));
        } else {
          _preloadChapter(nextTarget);
        }
      }
    }
    // 接近章首：预加载过滤后的上一章（首页翻上一张回到上一话末页不卡顿）。
    if (idx <= _prefs.preloadImageCount - 1) {
      final int? prevTarget = _resolveChapterTarget(-1);
      if (prevTarget != null) {
        if (localMulti) {
          unawaited(_preloadChapterLocal(prevTarget));
        } else {
          _preloadChapter(prevTarget);
        }
      }
    }
  }

  /// 章节加载完成后立即预载过滤后的相邻目标章（上/下各一）。
  ///
  /// 与 [_maybePreload]（滚到章末/章首附近才触发）互补：提前开始本地解压/网络
  /// 拉取，用户滚到边界时邻章通常已进入 [_preload]，seam 无缝列表可直接纳入，
  /// 避免「章末要手动跳 / 章首翻不了上一话」。best-effort：失败静默忽略。
  void _preloadAdjacentTargets() {
    final bool localMulti = _isAggregatedLocal ||
        (widget.localChapterDirs != null &&
            widget.localChapterDirs!.isNotEmpty);
    final int? nextTarget = _resolveChapterTarget(1);
    if (nextTarget != null) {
      if (localMulti) {
        unawaited(_preloadChapterLocal(nextTarget));
      } else {
        _preloadChapter(nextTarget);
      }
    }
    final int? prevTarget = _resolveChapterTarget(-1);
    if (prevTarget != null) {
      if (localMulti) {
        unawaited(_preloadChapterLocal(prevTarget));
      } else {
        _preloadChapter(prevTarget);
      }
    }
  }

  /// 预加载指定章节图片到 [_preload] 缓存（best-effort，失败静默忽略）。
  void _preloadChapter(int index) {
    if (index < 0 || index >= widget.chapters.length) return;
    if (_preload.containsKey(index) || _preloading.contains(index)) return;
    _preloading.add(index);
    final source = _repo.getById(widget.sourceId);
    if (source == null) {
      _preloading.remove(index);
      return;
    }
    _service
        .fetchImages(
          source,
          comicId: widget.comicId,
          chapterId: widget.chapters[index].id,
          renderedHtml: _renderedHtmlByChapter[index],
        )
        .then((imgs) {
          if (!mounted) return;
          _preload[index] = imgs;
          // 预载章图片同样登记 Referer（seam 无缝列表会直接显示邻章图片）。
          _registerImageReferers(imgs, widget.chapters[index].url);
          // 预载完成后重建段式连续模型：邻段条目新近可用。若完成的是【上一章】，
          // 前插会把当前章扁平索引整体后移，需记录锚点并重放以保持视口不跳变
          // （Bug 6：首页向下阅读被误拉回上一话末页）；追加下一章段时重放为同索引。
          if (_seamActive) {
            _rebuildSeamKeepViewport();
            if (mounted) setState(() {});
          }
        })
        .catchError((Object _) {})
        .whenComplete(() => _preloading.remove(index));
  }

  /// 预加载本地模式相邻章节（聚合本地 / 本地下载目录），走与 [_loadLocalImages]
  /// 相同的取图分支，把结果存入 [_preload] 缓存，供段式连续模型无缝续读。
  /// best-effort：失败静默忽略（邻段不入 seam，退化为整章加载）。
  Future<void> _preloadChapterLocal(int index) async {
    if (index < 0 || index >= widget.chapters.length) return;
    if (_preload.containsKey(index) || _preloading.contains(index)) return;
    if (widget.localArchivePaths == null && widget.localChapterDirs == null) {
      return; // 仅聚合本地 / 本地下载目录有相邻章概念。
    }
    _preloading.add(index);
    try {
      List<String> imgs;
      if (widget.localArchivePaths != null &&
          widget.localArchivePaths!.isNotEmpty) {
        final archive = await resolveSafUri(widget.localArchivePaths![index]);
        if (archive.toLowerCase().endsWith('.pdf')) {
          imgs = await extractPdfPages(archive);
        } else {
          imgs = await _extractCbz(archive);
        }
      } else {
        final dirPath = await resolveSafUri(widget.localChapterDirs![index]);
        imgs = await _gatherDirImages(dirPath);
      }
      if (!mounted) return;
      _preload[index] = imgs;
      // 同上：预载【上一章】完成会前插一段并后移当前章扁平索引，需锚点重放保持
      // 视口不跳变（Bug 6）；追加下一章段时重放为同索引（无副作用）。
      if (_seamActive) {
        _rebuildSeamKeepViewport();
        if (mounted) setState(() {});
      }
    } on Object {
      // best-effort：预载失败静默忽略。
    } finally {
      _preloading.remove(index);
    }
  }

  /// 重建段式连续模型（跨章无缝续读）。
  ///
  /// 段 = 当前章 + 已预载的相邻章（上/下各至多 1 段），按阅读顺序拍平为连续列表；
  /// 段与段之间按 [ReaderPreferences.showChapterSeparator] 插入「章分割/过渡」条目。
  /// 计算 [_seam]（各段起始偏移）、[_seamItemCount]（总条目数）与两张扁平映射
  /// （[_seamPageMap] 扁平→页、[_seamImages] 扁平→图片 URL）。
  ///
  /// 非 [_seamActive] 时清空全部 seam 状态，走传统「整章加载」路径。
  void _rebuildSeam() {
    if (!_seamActive) {
      _seam = const <_SeamSegment>[];
      _seamItemCount = 0;
      _seamPageMap = const <int>[];
      _seamImages = const <String>[];
      return;
    }
    final List<_SeamSegment> segments = <_SeamSegment>[];
    // 上一章段：仅当已预载才纳入（未预载则边界回退走整章加载）。段定位用
    // 跳章过滤后的目标章：相邻章会被跳过（已读/被筛除/重复）时，
    // 直接把过滤后的目标章段接在当前章前，条漫向上滚可无缝回到上一未读章。
    final int? resolvedPrev = _resolveChapterTarget(-1);
    if (resolvedPrev != null && resolvedPrev != _chapterIndex) {
      final List<String>? prevImgs = _preload[resolvedPrev];
      if (prevImgs != null && prevImgs.isNotEmpty) {
        segments.add(_SeamSegment(
          chapterIndex: resolvedPrev,
          pageCount: prevImgs.length,
          title: widget.chapters[resolvedPrev].title,
        ));
      }
    }
    // 当前章段：始终存在。
    segments.add(_SeamSegment(
      chapterIndex: _chapterIndex,
      pageCount: _images.length,
      title: widget.chapters[_chapterIndex].title,
    ));
    // 下一章段：仅当已预载才纳入。同上，段定位用过滤后的目标章（跳过已读/
    // 被筛除/重复章），条漫滚到章末直接无缝进入下一未读章，无需点击过渡。
    final int? resolvedNext = _resolveChapterTarget(1);
    if (resolvedNext != null && resolvedNext != _chapterIndex) {
      final List<String>? nextImgs = _preload[resolvedNext];
      if (nextImgs != null && nextImgs.isNotEmpty) {
        segments.add(_SeamSegment(
          chapterIndex: resolvedNext,
          pageCount: nextImgs.length,
          title: widget.chapters[resolvedNext].title,
        ));
      }
    }
    // 计算各段起始偏移 + 两张扁平映射。
    final List<int> pageMap = <int>[];
    final List<String> images = <String>[];
    int acc = 0;
    for (var s = 0; s < segments.length; s++) {
      final _SeamSegment seg = segments[s];
      final List<String> segImgs = seg.chapterIndex == _chapterIndex
          ? _images
          : (_preload[seg.chapterIndex] ?? const <String>[]);
      final bool hasPrev = s > 0;
      if (hasPrev && _prefs.showChapterSeparator) {
        pageMap.add(-1); // 章分割/过渡条目
        images.add('');
        acc += 1;
      }
      final _SeamSegment resolved = _SeamSegment(
        chapterIndex: seg.chapterIndex,
        pageCount: seg.pageCount,
        title: seg.title,
        startOffset: acc,
      );
      segments[s] = resolved;
      for (var p = 0; p < seg.pageCount; p++) {
        pageMap.add(p);
        images.add(segImgs.isEmpty ? '' : segImgs[p]);
      }
      acc += seg.pageCount;
    }
    _seam = segments;
    _seamItemCount = pageMap.length;
    _seamPageMap = pageMap;
    _seamImages = images;
  }

  /// 重建段式连续模型并保持当前视口内容不跳变（Bug 6）。
  ///
  /// 预载【上一章】完成时，[_rebuildSeam] 会把上一章段【前插】到扁平列表前面，
  /// 使当前章所有扁平索引整体后移（偏移 = 上一章页数 + 可能的章分割条目），而滚动
  /// 位置未补偿 → 视口瞬间落到上一章末尾内容，[_onWebtoonScroll] 检测到视口顶部落入
  /// 邻段便触发 [_seamAdvance(-1, last)] 误拉回上一话末页。
  ///
  /// 本方法与 [_seamReloadFromPrefs] 一致：重建前记录当前视口锚点（仅当前章段内的
  /// 页条目有效；落在邻段/章分割条目则不记录，避免锚点错误）→ 重建 → 在 post-frame
  /// 用 [_seamFlatIndexOf] 换算新扁平索引并 jumpTo 把同一内容钉回原屏幕位置。
  /// 重建期间置位 [_seamReanchoring]，屏蔽重建帧内 itemPositions 通知对
  /// 「旧索引 → 上一章段」的误判（与 [_seamAdvance] 的重锚保护一致），补偿落定后解除。
  /// 若只是追加下一章段（结尾追加不影响既有索引），重放为同索引 jumpTo（无副作用）。
  void _rebuildSeamKeepViewport() {
    // 重建前记录当前视口锚点（仅当前章段内记录）。
    final anchor = _seamViewportAnchor();
    int? anchorChapter;
    int? anchorPage;
    if (anchor != null &&
        anchor.flatIdx >= 0 &&
        anchor.flatIdx < _seamPageMap.length) {
      final _SeamSegment? seg = _seamSegmentAt(anchor.flatIdx);
      if (seg != null && seg.chapterIndex == _chapterIndex) {
        final int p = _seamPageMap[anchor.flatIdx];
        if (p >= 0) {
          anchorChapter = seg.chapterIndex;
          anchorPage = p;
        }
      }
    }
    // 重建期间屏蔽滚动回调：前插上一段会使当前章扁平索引整体后移，重建帧内的
    // itemPositions 通知会把「当前章旧索引」误判为「上一章段」→ 触发 _seamAdvance(-1)
    // 误拉回上一话。jumpTo 落定后解除（与 _seamAdvance 的两段式解除一致）。
    _seamReanchoring = true;
    _rebuildSeam();
    final bool replayed = anchorChapter != null && anchorPage != null;
    if (replayed) {
      final isc = _itemScrollController;
      final int flat = _seamFlatIndexOf(anchorChapter, anchorPage);
      final double edge = (anchor?.edge ?? 0.0).clamp(-2.0, 2.0);
      if (isc != null && isc.isAttached && flat >= 0 && flat < _seamItemCount) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !isc.isAttached) return;
          isc.jumpTo(index: flat, alignment: edge);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _seamReanchoring = false;
          });
        });
        return;
      }
    }
    // 锚点落在邻段/章分割条目、换算失败或列表未就绪：无内容可钉，仅短暂屏蔽滚动
    // 回调后解除，避免重建帧内的通知误触发上翻重锚。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _seamReanchoring = false;
    });
  }

  /// 扁平索引 → 所在段（章分割条目返回 null）。
  _SeamSegment? _seamSegmentAt(int flatIdx) {
    if (flatIdx < 0 || flatIdx >= _seamItemCount) return null;
    for (final _SeamSegment seg in _seam) {
      if (flatIdx >= seg.startOffset && flatIdx <= seg.endFlatIndex) {
        return seg;
      }
    }
    return null; // 章分割/过渡条目
  }

  /// (章索引, 页索引) → 扁平索引。当前章段不存在（异常态）时返回其页数（钳到末位）。
  /// 仅供扁平列表的初始落点/重锚换算使用，需在 [_rebuildSeam] 之后调用。
  int _seamFlatIndexOf(int chapterIndex, int page) {
    final _SeamSegment? seg = _seam.isEmpty
        ? null
        : _seam.firstWhere(
            (s) => s.chapterIndex == chapterIndex,
            orElse: () => _seam.first,
          );
    if (seg == null) return 0;
    if (seg.chapterIndex != chapterIndex) {
      // 目标章不在 seam 中：整章加载路径下扁平索引 == 页索引。
      return page.clamp(0, _images.length - 1);
    }
    return (seg.startOffset + page).clamp(0, _seamItemCount - 1);
  }

  /// 段式连续模型下，把「视口内最顶部可见扁平条目」解析为「当前章页码」。
  ///
  /// - 非 seam 模式：扁平索引 == 真实页索引（含到底修正）。
  /// - seam 模式：扁平条目在当前段内 → 页索引；在章分割条目 / 邻段页 → 保持当前页
  /// （越界预加载期不把越界页码写进当前章存档，重锚时统一修正）。
  int _resolveSeamIndex(int flatIdx, {bool atVeryEnd = false}) {
    if (!_seamActive || _seam.isEmpty) {
      final int last = _images.isEmpty ? 0 : _images.length - 1;
      return (atVeryEnd ? last : flatIdx).clamp(0, last);
    }
    final _SeamSegment? seg = _seamSegmentAt(flatIdx);
    if (seg == null) return _currentPage; // 章分割条目
    if (seg.chapterIndex != _chapterIndex) return _currentPage; // 邻段
    final int page = _seamPageMap[flatIdx];
    final int last = _images.isEmpty ? 0 : _images.length - 1;
    return (atVeryEnd ? last : page).clamp(0, last);
  }

  /// 当前视口锚点：视口内最顶部可见项的扁平索引 + 其顶边偏移（视口高度归一化）。
  /// 用于重锚前后把同一内容钉回原屏幕位置（跨章无缝续读的位置保持）。
  ({int flatIdx, double edge})? _seamViewportAnchor() {
    final positions = _itemPositionsListener?.itemPositions.value;
    if (positions == null || positions.isEmpty) return null;
    final visible = positions
        .where((p) => p.itemLeadingEdge < 1 && p.itemTrailingEdge > 0)
        .toList();
    if (visible.isEmpty) return null;
    final first = visible.reduce((a, b) => a.index <= b.index ? a : b);
    return (flatIdx: first.index, edge: first.itemLeadingEdge);
  }

  /// 重锚段式连续模型（跨章无缝续读）：把「当前段」前移/后移到相邻段。
  ///
  /// [dir] = +1 进入下一段（下一章），-1 进入上一段（上一章）。
  /// [reposition] 决定重锚后的落点：
  /// - [_SeamAdvanceTarget.keep]（默认，滚动越界触发）：把重锚前视口内同一内容
  /// 钉回原屏幕位置，位置不跳变；
  /// - first：跳到新当前段首页（用于「下一章」按钮/快捷键）；
  /// - last：跳到新当前段末页（用于「上一章」按钮/快捷键）。
  ///
  /// 返回是否真正执行了重锚（越界/目标未就绪/锚点不合法时返回 false，由调用方
  /// 回退到常规进度处理或整章加载）。
  ///
  /// 执行序列：记录锚点 → 交换 [_images]/[_preload] → 预载新邻段 → 重建 [_seam]
  /// → setState 重建扁平列表 → 首帧后 jumpTo 平移视口 → 末帧解除 [_seamReanchoring]。
  bool _seamAdvance(int dir,
      {_SeamAdvanceTarget reposition = _SeamAdvanceTarget.keep,
      int? targetPage,
      int? targetOverride}) {
    if (_seamReanchoring) return false;
    // 目标章：显式指定（目录点选，不应用跳章过滤）优先；否则沿 [dir] 方向过滤
    // （跳过已读/被过滤/重复章）后的可导航章——条漫连续阅读在「下一章已读」时
    // 直接连到下一未读章。
    final int target =
        targetOverride ?? _resolveChapterTarget(dir) ?? (_chapterIndex + dir);
    if (target < 0 || target >= widget.chapters.length) return false;
    // 重锚目标章的图片必须已就绪（当前章或预载缓存），否则整章加载兜底。
    final List<String> targetImgs = target == _chapterIndex
        ? _images
        : (_preload[target] ?? const <String>[]);
    if (targetImgs.isEmpty) return false;
    final int oldChapter = _chapterIndex;
    // keep：记录当前视口锚点，重锚后把同一内容钉回原位。
    ({int flatIdx, double edge})? anchor;
    int? anchorPage;
    if (reposition == _SeamAdvanceTarget.keep) {
      anchor = _seamViewportAnchor();
      if (anchor == null) return false;
      final _SeamSegment? anchorSeg = _seamSegmentAt(anchor.flatIdx);
      // 仅当锚点确实落在「目标相邻段」的页条目上才重锚；分隔条目/其它段不动作。
      if (anchorSeg == null || anchorSeg.chapterIndex != target) return false;
      anchorPage = _seamPageMap[anchor.flatIdx];
      if (anchorPage < 0) return false;
    }
    _seamReanchoring = true;
    try {
      // 交换章节数据：旧当前章转存预载缓存（成为重锚后的邻段），目标章提升为当前章。
      // 在线/本地聚合/下载目录统一走同一交换：图片列表均为内存字符串列表。
      _preload[oldChapter] = _images;
      _images = targetImgs;
      _chapterIndex = target;
      // 睡眠定时按话数计数（；seam 无缝切章同样算「读完一话进入下一话」）。
      _onChapterEntered();
      // 翻章后刷新顶栏章节书签状态。
      unawaited(_refreshChapterBookmark());
      // 预载新一层的可导航章（沿原方向过滤后的目标；越界时自动忽略）。
      final int? nextTarget = _resolveChapterTarget(dir);
      if (_isAggregatedLocal ||
          (widget.localChapterDirs != null &&
              widget.localChapterDirs!.isNotEmpty)) {
        if (nextTarget != null) {
          unawaited(_preloadChapterLocal(nextTarget));
        }
      } else {
        _preloadChapter(nextTarget ?? (target + dir));
      }
      // 页旋转表仅对当前段有效：重锚后旧段旋转记录不再适用，整表清空。
      _pageRotations.clear();
      _rebuildSeam();
    } on Object {
      // 防御：同步重锚段（交换/预载/重建 seam）异常时立即复位标志——否则
      // _seamReanchoring 永久为 true，滚动回调与后续换章全部静默失效（表现为
      // 「翻到首页后就无法翻上一章」），且后续调用一律 return false 卡死。
      _seamReanchoring = false;
      return false;
    }
    // 重锚落点即当前阅读页：keep = 锚点页（目标章内相对页），first = 首页，last = 末页，
    // targetPage = 显式指定的页（「回到上一话」恢复到离开页）。
    // 提前校正 _currentPage，避免重锚后到滚动回调收敛前这一小段窗口把旧章页码
    // 误当作新章页码写盘（进度/页码在连续模型下正确）。
    final int lastPage = _images.isEmpty ? 0 : _images.length - 1;
    final int page = targetPage ??
        switch (reposition) {
          _SeamAdvanceTarget.keep => (anchorPage ?? 0).clamp(0, lastPage),
          _SeamAdvanceTarget.first => 0,
          _SeamAdvanceTarget.last => lastPage,
        };
    _currentPage = page.clamp(0, lastPage);
    // 重锚后落点换算：keep 保持视口锚点，其余按落点页定位（首页/末页/显式页）。
    final int jumpIndex = reposition == _SeamAdvanceTarget.keep
        ? _seamFlatIndexOf(target, anchorPage ?? 0)
        : _seamFlatIndexOf(target, page);
    final double jumpAlign = reposition == _SeamAdvanceTarget.keep
        ? (anchor?.edge ?? 0.0).clamp(-2.0, 2.0)
        : 0.0;
    // keep 重锚的首帧对齐（见 [_pendingWebtoonInitialAlignment]）：切章换 key
    // 重建列表时直接落在真实阅读位置（常为页面中部），消除「首帧对齐 0 →
    // post-frame jumpTo 钉回」两帧位置差造成的闪帧。
    if (reposition == _SeamAdvanceTarget.keep) {
      _pendingWebtoonInitialAlignment = jumpAlign;
    }
    final isc = _itemScrollController;
    final int token = _loadSession.current;
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_loadSession.isValid(token)) return;
      if (isc != null &&
          isc.isAttached &&
          jumpIndex >= 0 &&
          jumpIndex < _seamItemCount) {
        // jumpTo 为确定性瞬移：重锚后把视口钉到换算出的扁平条目 + 对齐系数，
        // 同一内容回到原屏幕位置（或落到目标章首页/末页）。
        isc.jumpTo(index: jumpIndex, alignment: jumpAlign);
      }
      // 回到上一章（last 落点）：预载图的真实尺寸可能尚未就绪，单次 jumpTo 按
      // 占位高度定位会错位（停在倒数几页/不到底）。复用「两段式滚到底」精确收尾：
      // 轮询末页底边直到贴视口底（与 [_loadLocalImages] restoreToLast 路径一致）。
      // targetPage（显式恢复到离开页）目标图来自预载缓存、尺寸已知，单次 jumpTo 即准，
      // 无需贴底轮询。
      if (reposition == _SeamAdvanceTarget.last && targetPage == null) {
        // 与 [_loadLocalImages] restoreToLast 全程屏蔽一致：轮询/收尾期间滚动回写被
        // _restoringPage 屏蔽（_seamReanchoring 在下一帧即解除，仅靠它不足以盖住
        // 轮询窗口），避免 jumpTo 中间位置被误写进度；_finishWebtoonRestore 收尾时
        // 解除并写末页进度。
        _restoringPage = true;
        _scrollToWebtoonLast(lastPage, token);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _seamReanchoring = false;
        // 重锚落点即当前阅读页：写盘存档（章边界处进度按实际章+页计算）。
        final int page = _currentPage.clamp(0, _images.length - 1);
        _scheduleProgressSave(page);
      });
    });
    return true;
  }

  /// 段式连续模型下单步翻页：目标页在当前段内 → 滚到其扁平索引；
  /// 越界 → 走换章（无缝路径优先，整章加载兜底）。
  /// 返回是否已处理（非 seam 模式下直接返回 false 走原 [_webtoonStep] 逻辑）。
  bool _seamStep(int dir) {
    if (!_seamActive || _seam.isEmpty) return false;
    final isc = _itemScrollController;
    if (isc == null || !isc.isAttached) {
      dir > 0 ? _goNextChapter() : _goPrevChapter();
      return true;
    }
    final int target = _currentPage + dir;
    final int last = _images.length - 1;
    if (target > last) {
      _goNextChapter();
      return true;
    }
    if (target < 0) {
      _goPrevChapter();
      return true;
    }
    final int flatTarget = _seamFlatIndexOf(_chapterIndex, target);
    if (flatTarget < 0 || flatTarget >= _seamItemCount) return false;
    final before = _webtoonScrollAnchor();
    final int token = _loadSession.current;
    isc.jumpTo(index: flatTarget, alignment: 0.0);
    _webtoonStepTimer?.cancel();
    _webtoonStepTimer = Timer(
      AppTokens.durFast + const Duration(milliseconds: 120),
      () {
        _webtoonStepTimer = null;
        if (!mounted || !_loadSession.isValid(token)) return;
        final after = _webtoonScrollAnchor();
        if (before == null || after == null) return;
        final bool stalled = before.index == after.index &&
            (before.edge - after.edge).abs() < 0.002;
        if (!stalled) return;
        dir > 0 ? _goNextChapter() : _goPrevChapter();
      },
    );
    return true;
  }

  /// 偏好或章节结构变化时重建段式连续模型，并校正当前页码/进度。
  /// 供 [_applySettingsAuto] / [_onPrefsChanged] 在 seamlessReading /
  /// showChapterSeparator / readingMode 变化后调用。
  void _seamReloadFromPrefs() {
    if (!_seamActive) {
      _rebuildSeam();
      return;
    }
    // 重建前记录当前视口锚点（章分割显隐变化会平移扁平索引，需重锚保持视口不跳变）。
    final anchor = _seamViewportAnchor();
    int? anchorPage;
    if (anchor != null &&
        anchor.flatIdx >= 0 &&
        anchor.flatIdx < _seamPageMap.length) {
      final _SeamSegment? seg = _seamSegmentAt(anchor.flatIdx);
      if (seg != null && seg.chapterIndex == _chapterIndex) {
        final int p = _seamPageMap[anchor.flatIdx];
        if (p >= 0) anchorPage = p;
      }
    }
    _rebuildSeam();
    _currentPage =
        _currentPage.clamp(0, _images.isEmpty ? 0 : _images.length - 1);
    _scheduleProgressSave(_currentPage);
    if (anchorPage != null) {
      final isc = _itemScrollController;
      final int flat = _seamFlatIndexOf(_chapterIndex, anchorPage);
      final double edge = (anchor?.edge ?? 0.0).clamp(-2.0, 2.0);
      if (isc != null && isc.isAttached && flat >= 0 && flat < _seamItemCount) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && isc.isAttached) {
            isc.jumpTo(index: flat, alignment: edge);
          }
        });
      }
    }
  }

  void _saveProgress(int page) {
    // 单文件本地模式（无章节表，章恒为 0）：主进度同样落盘，供重进恢复到已读页；
    // 章节联动（收藏/历史/已读标记）不适用，跳过。此前直接 return 导致本地漫画
    // 重进永远从第 1 页开始（进度从未保存）。只写主记录一条：saveChapterPage 与
    // save 并发写同一 key 时完成顺序不定，旧值可能覆盖新页码。
    if (widget.chapters.isEmpty) {
      if (!_isLocalMode) return;
      _chapterPageCache[0] = page;
      unawaited(_progress.save(widget.comicId, '', page, 0));
      return;
    }
    // 每章页码即时记录（见 [_scheduleProgressSave] 注释）：直接保存路径同样维护。
    _chapterPageCache[_chapterIndex] = page;
    unawaited(_progress.saveChapterPage(widget.comicId, _chapterIndex, page));
    final chapter = widget.chapters[_chapterIndex];
    _progress.save(
      widget.comicId,
      chapter.id,
      page,
      _chapterIndex,
      totalChapters: widget.chapters.length,
    );
    // 更新收藏条目的 lastRead 时间戳（收藏切换不丢 lastRead）
    try {
      context.read<FavoritesManager>().updateLastRead(
            widget.comicId,
            SourceType.mangaSource,
          );
    } catch (_) {
      // FavoritesManager 不可用时静默忽略。
    }
    // 写浏览历史：仅在详情页 initState 写一次时「lastChapter」恒为 null，
    // 书架历史 Tab 与「继续阅读」入口都看不到进度；这里每次翻页都更新
    // 最近章节标题，让历史 Tab 排序与续读定位都生效。
    try {
      final history = context.read<HistoryManager>();
      final item = MediaItem(
        id: widget.comicId,
        title: widget.title,
        sourceId: widget.sourceId,
        sourceType: SourceType.mangaSource,
        coverUrl: widget.coverUrl,
        detailUrl: widget.detailUrl,
      );
      unawaited(history.addHistory(
        item,
        lastChapter: chapter.title,
        sourceType: SourceType.mangaSource,
      ));
    } catch (_) {
      // HistoryManager 不可用时静默忽略。
    }
    // 章节阅读进度达到「已看」阈值时标记该章已读（每章仅标记一次）。
    _maybeMarkChapterWatched(page);
    // 阅读中自动下载后续章节：进度越过 25% 时后台入队，失败静默。
    _maybeAutoDownload(page);
    // E-Ink 刷新：按翻页间隔累计页数，跨页变化时 +1，达到间隔触发一次全屏闪烁。
    if (_effectivePrefs.einkRefreshEnabled && page != _einkLastPage) {
      _einkLastPage = page;
      _einkPageCount++;
      if (_einkPageCount >= _effectivePrefs.einkRefreshInterval) {
        _einkPageCount = 0;
        _triggerEinkRefresh();
      }
    }
  }

  /// 章节阅读进度达到「已看」阈值时标记该章已读。
  ///
  /// 阈值取自 [GeneralSettingsStore.watchedThresholdPercent]（默认 90）。
  /// 已读章节由 [MediaWatchedManager] 统一记录（与详情页 isRead 共用），
  /// `markWatched` 本身幂等，此处额外用 `isWatched` 跳过已读章节。
  /// [chapterIndex] 可显式指定原章（切章后防抖补记场景，见 [_scheduleProgressSave]）；
  /// 缺省用当前章。目标章图片不在内存（[_preload] 已取走）时无法得知总页数，跳过。
  void _maybeMarkChapterWatched(int page, {int? chapterIndex}) {
    final int ci = chapterIndex ?? _chapterIndex;
    final int total =
        ci == _chapterIndex ? _images.length : (_preload[ci]?.length ?? -1);
    if (total <= 0) return;
    final ratio = (page + 1) / total;
    final threshold = GeneralSettingsStore.instance.watchedThresholdPercent;
    if (!progressReachesWatchedThreshold(ratio, threshold)) return;
    try {
      final watched = context.read<MediaWatchedManager>();
      if (watched.isWatched(widget.comicId, ci)) return;
      unawaited(watched.markWatched(widget.comicId, ci));
    } catch (_) {
      // Manager 不可用时静默忽略。
    }
  }

  /// 阅读中自动下载后续章节。
  ///
  /// 两个触发源，共用同一组前置条件（非本地模式 + 存在后续章节 + 本章进度越过
  /// 25% + 本章尚未触发过 + 该作品没有正在/已激活的下载批次）：
  /// - 阅读器面板的 [ReaderPreferences.autoDownloadChapters] 开启：`chapterIndex+1`
  /// 起的全部后续章节作为单个任务入队；
  /// - 下载设置的「预下载后续内容数」（[DownloadSettings.preDownloadCount] > 0）：
  /// 预下载后续 N 话（与视频播放器同一语义，逐话入队、跳过已下载/已排队）。
  /// 此前漫画阅读器完全忽略该设置——设置里开了预下载，看漫画却什么都不下，
  /// 下载列表始终为空的直接根因。
  /// 任何失败静默忽略，不打断阅读。
  void _maybeAutoDownload(int page) {
    final dm = _downloadManager;
    if (dm == null) return;
    if (_isLocalMode) return; // 本地文件无在线下载概念。
    if (widget.chapters.length <= _chapterIndex + 1) return; // 已是最后一章。
    if (_autoDownloadTriggeredChapter == _chapterIndex) return; // 每章仅一次。
    final total = _images.length;
    if (total <= 0 || (page + 1) / total < 0.25) return; // 未越过 25%。
    // 存在该作品的【活跃】下载批次（进行中/等待/暂停）则跳过，避免重复入队；
    // 已完成/失败/取消的批次不阻塞——否则用户之前手动下过前几话（completed 任务
    // 仍在列表里），后续新话永远无法自动下载（「没有自动下载」的根因）。
    final bool hasActiveTask = dm.tasks.any(
      (t) => t.contentId == widget.comicId && t.isActive,
    );
    if (hasActiveTask) return;
    final item = MediaItem(
      id: widget.comicId,
      title: widget.title,
      sourceId: widget.sourceId,
      sourceType: SourceType.mangaSource,
      coverUrl: widget.coverUrl,
      detailUrl: widget.detailUrl,
    );
    if (_prefs.autoDownloadChapters) {
      // 入队前过滤已下载/已排队章节（与 preDownloadNextEpisodes 同一语义）：
      // 「自动下载后续章节」= 下载接下来【未下载】的话，已下载的不重复下载。
      final Set<String> downloaded = dm.downloadedChapterTitles(widget.comicId);
      final Set<String> queued = dm.queuedChapterTitles(widget.comicId);
      final List<int> indices = <int>[
        for (var i = _chapterIndex + 1; i < widget.chapters.length; i++)
          if (!downloaded.contains(widget.chapters[i].title) &&
              !queued.contains(widget.chapters[i].title))
            i,
      ];
      if (indices.isEmpty) {
        // 后续章节已全部下载/排队：记触发防止重复判定，但不再入队。
        _autoDownloadTriggeredChapter = _chapterIndex;
        return;
      }
      AppLog.instance.i(
        '[漫画自动下载] 触发入队 comic=${widget.comicId} '
        'chapter=$_chapterIndex page=$page total=$total '
        '待下载数=${indices.length}（已过滤下载/排队）',
      );
      _autoDownloadTriggeredChapter = _chapterIndex;
      unawaited(
        dm
            .addTask(
          item: item,
          chapters: widget.chapters,
          chapterIndices: indices,
        )
            .then((_) {
          // 成功入队不提示（非阻塞、静默）。
        }).catchError((Object _) {
          // 失败静默：不打断阅读。
          _autoDownloadTriggeredChapter = -1;
        }),
      );
      return;
    }
    // 预下载路径：从存储重读设置（DownloadManager 缓存的 settings 可能还是启动
    // 时的旧值，设置页热改后不重读会漏触发）。
    AppLog.instance.i(
      '[漫画预下载] 检查 comic=${widget.comicId} '
      'chapter=$_chapterIndex page=$page total=$total',
    );
    _autoDownloadTriggeredChapter = _chapterIndex;
    unawaited(() async {
      final int count;
      try {
        count = (await DownloadSettingsStore().load()).preDownloadCount;
      } on Object {
        return;
      }
      if (count <= 0) return;
      try {
        await dm.preDownloadNextEpisodes(
          item: item,
          chapters: widget.chapters,
          fromIndex: _chapterIndex,
          count: count,
        );
      } on Object {
        // 失败静默：不打断阅读。
        _autoDownloadTriggeredChapter = -1;
      }
    }());
  }

  // ─────────────────────── 导航 ───────────────────────

  /// 翻页时重置共享缩放控制器：所有 MangaPageImage 共用同一个 [_zoomController]，
  /// 若不重置，上一页的缩放 + 平移会原样带到下一页，表现为「位置错乱」（手势 bug）。
  /// 同时清空捏合起手矩阵基准 [_pinchBaseMatrix]——否则放大 → 翻页 → 再捏合时，
  /// 基准残留放大矩阵，`realFactor` 恒为 1 导致捏合无效果。
  void _resetZoom() {
    _pinchBaseMatrix = null;
    // 翻页/切章时结束未完成的缩放动画：否则动画控制器仍在 forward，会在翻页后
    // 继续改写矩阵并残留 _zoomAnimating=true，导致「三态只剩缩小、双击无反应」。
    _stopZoomAnimation();
    _zoomController.value = Matrix4.identity();
    // 切章/翻页时收起跳章过渡提示。
    _hideSkipTransition();
  }

  /// 翻页时保留缩放倍数、仅清平移（用户需求：删除「翻页重置缩放」策略）。
  ///
  /// 所有 MangaPageImage 共享同一个 [_zoomController]，上一页的**平移**会原样带到
  /// 下一页造成位置错乱，故平移必须清零；**缩放倍数**则保留——放大后翻页，下一页
  /// 继续以相同倍数居中显示（与条漫模式「缩放不因翻页重置」的连续阅读习惯对齐）。
  /// 同时结束未完成的缩放动画（动画在翻页后继续 forward 会改写矩阵），并清空
  /// 捏合起手基准，避免下一次捏合时基准残留导致 realFactor 恒为 1。
  void _keepZoomForPageTurn() {
    _pinchBaseMatrix = null;
    _stopZoomAnimation();
    _hideSkipTransition();
    final Matrix4 m = _zoomController.value;
    final double s = m.getMaxScaleOnAxis();
    if (s <= 1.001) {
      _zoomController.value = Matrix4.identity();
    } else {
      // 中心原点坐标系：仅含 scale 的矩阵 = 以视口中心为锚点的同倍数缩放。
      _zoomController.value = Matrix4.identity()..scaleByDouble(s, s, s, 1.0);
    }
  }

  void _goNextPage() {
    // 翻页保留缩放倍数、仅清平移（不再完全重置；条漫模式完全不重置）。
    if (!_prefs.readingMode.isWebtoon) _keepZoomForPageTurn();
    _triggerFlash();
    if (_prefs.readingMode.isWebtoon) {
      _webtoonStep(1);
      return;
    }
    // 翻页过渡动画（fade）：翻页后整页淡入。
    _runPageFade();
    final pc = _pageController;
    if (pc == null || !pc.hasClients) return;
    final total = _controllerPageCount;
    if (total <= 1) {
      _goNextChapter();
      return;
    }
    // paged 段式连续模型（章末过渡卡）：已停在过渡卡页 → 越过即无缝进入下一章首页。
    if (_showPagedNextCard && (pc.page?.round() ?? 0) >= total - 1) {
      _goNextChapter();
      return;
    }
    // 用 _currentPage 做边界判断，避免 pc.page 在控制器重建/恢复期间不稳定。
    // 双页/gallery 模式下 _currentPage 指向屏首（左）页，末页判断：>= 最后一个屏首页。
    final int lastLeftPage;
    if (_isDoublePage) {
      lastLeftPage = _doublePageLeftPageFor(_spreadCount - 1);
    } else if (_isGalleryMode) {
      lastLeftPage = ((_images.length - 1) ~/ _galleryCount) * _galleryCount;
    } else {
      lastLeftPage = _images.length - 1;
    }
    if (_currentPage >= lastLeftPage) {
      // 有过渡卡先翻到过渡卡页，由用户/下一张按钮决定是否进入下一章；
      // 无过渡卡（无缝关闭 / 无下一章）保持旧行为直接换章。
      if (_showPagedNextCard) {
        pc.nextPage(duration: AppTokens.durFast, curve: Curves.easeInOut);
      } else {
        _goNextChapter();
      }
    } else {
      pc.nextPage(duration: AppTokens.durFast, curve: Curves.easeInOut);
    }
  }

  void _goPrevPage() {
    // 同 [_goNextPage]：翻页保留缩放倍数、仅清平移。
    if (!_prefs.readingMode.isWebtoon) _keepZoomForPageTurn();
    _triggerFlash();
    if (_prefs.readingMode.isWebtoon) {
      _webtoonStep(-1);
      return;
    }
    // 翻页过渡动画（fade）：翻页后整页淡入。
    _runPageFade();
    final pc = _pageController;
    if (pc == null || !pc.hasClients) return;
    // 用 _currentPage 做边界判断，避免 pc.page 在控制器重建/恢复期间不稳定。
    if (_currentPage <= 0) {
      _goPrevChapter();
    } else {
      pc.previousPage(duration: AppTokens.durFast, curve: Curves.easeInOut);
    }
  }

  /// 条漫当前滚动位置的锚点：视口内最靠前一项的索引 + 其顶边偏移（视口高度归一化）。
  /// 用于比对一次滚动请求前后画面是否真的移动过。
  ({int index, double edge})? _webtoonScrollAnchor() {
    final positions = _itemPositionsListener?.itemPositions.value;
    if (positions == null || positions.isEmpty) return null;
    final first = positions.reduce((a, b) => a.index <= b.index ? a : b);
    return (index: first.index, edge: first.itemLeadingEdge);
  }

  /// 条漫单步翻页（[dir] = +1 下一页 / -1 上一页）。
  ///
  /// 采用「意图驱动」而非「测量驱动」：先算出想去的目标页，目标越界就直接换章，
  /// 不再要求「当前页」的测量值必须精确等于末页/首页。旧实现把换章闸门绑在测量
  /// 值上，而窄屏（一屏可容纳多张短图）时视口顶部项永远停在倒数几页，闸门就再也
  /// 打不开，表现为末页点击完全没反应。
  ///
  /// 目标未越界时正常滚动，并在动画结束后比对画面是否真的移动过：没动即说明已被
  /// 边界夹紧（内容不足以再滚一页），同样兜底换章。该检查用定时器驱动，必定执行。
  void _webtoonStep(int dir) {
    if (_images.isEmpty) return;
    // 段式连续模型（跨章无缝续读）：扁平索引 ≠ 页索引，单步翻页交由
    // [_seamStep] 换算（含越界无缝重锚），非 seam 走下方传统页索引路径。
    if (_seamActive && _seamStep(dir)) return;
    final int last = _images.length - 1;
    final isc = _itemScrollController;
    // 列表尚未挂载（切章/重建中）时不再静默吞掉操作，直接按方向换章。
    if (isc == null || !isc.isAttached) {
      dir > 0 ? _goNextChapter() : _goPrevChapter();
      return;
    }
    final int target = _currentPage + dir;
    if (target > last) {
      _goNextChapter();
      return;
    }
    if (target < 0) {
      _goPrevChapter();
      return;
    }
    final before = _webtoonScrollAnchor();
    final int token = _loadSession.current;
    // 条漫单步翻页用 jumpTo 确定性瞬移：scrollTo 反向连续调用时 SPL 0.3.8 会因
    // 内部 _scrollOffset 未即时更新产生「回弹/抽搐」（铁律③）。jumpTo 不排队动画、
    // 不与拖拽/上一动画争用 scroll activity，彻底消除反向翻页回弹。
    isc.jumpTo(
      index: target.clamp(0, last),
      alignment: 0.0,
    );
    _webtoonStepTimer?.cancel();
    _webtoonStepTimer = Timer(
      AppTokens.durFast + const Duration(milliseconds: 120),
      () {
        _webtoonStepTimer = null;
        // 章节已切换 / 页面已销毁则放弃本次判定，避免误触发换章。
        if (!mounted || !_loadSession.isValid(token)) return;
        final after = _webtoonScrollAnchor();
        if (before == null || after == null) return;
        // 锚点未变 = 滚动被夹紧（已到边界），此时才换章。比较的是整段动画前后的
        // 位置差，故即便读到的是上一帧布局也不影响结论。
        final bool stalled = before.index == after.index &&
            (before.edge - after.edge).abs() < 0.002;
        if (!stalled) return;
        dir > 0 ? _goNextChapter() : _goPrevChapter();
      },
    );
  }

  /// 翻页闪光：仅在 [ReaderPreferences.flashEnabled] 时触发，延迟
  /// [ReaderPreferences.flashInterval] 毫秒后播放一次。
  void _triggerFlash() {
    final p = _prefs;
    if (!p.flashEnabled || !mounted) return;
    final dur = Duration(milliseconds: p.flashTime);
    Future.delayed(Duration(milliseconds: p.flashInterval), () {
      if (!mounted) return;
      switch (p.flashColor) {
        case ReaderFlashColor.black:
          _runFlash(Colors.black, dur);
        case ReaderFlashColor.white:
          _runFlash(Colors.white, dur);
        case ReaderFlashColor.blackWhite:
          _runFlash(Colors.black, dur, () => _runFlash(Colors.white, dur));
      }
    });
  }

  /// 播放一段「淡入→淡出」的闪光（opacity 0→1→0）。[onDone] 用于黑→白连续闪。
  void _runFlash(Color color, Duration dur, [VoidCallback? onDone]) {
    _flashController.stop();
    _flashController.duration = dur;
    if (_flashListener != null) {
      _flashController.removeListener(_flashListener!);
    }
    _flashListener = () {
      if (mounted) setState(() => _flashOpacity = _flashController.value);
    };
    _flashController.addListener(_flashListener!);
    setState(() {
      _flashColor = color;
      // 置位覆盖层活动标志：E-Ink 定期刷新不依赖 flashEnabled 也能渲染闪烁层。
      _flashLayerActive = true;
    });
    _flashController.forward(from: 0).then((_) {
      _flashController.reverse(from: 1).then((_) {
        if (mounted) {
          setState(() {
            _flashOpacity = 0.0;
            _flashLayerActive = false;
          });
        }
        onDone?.call();
      });
    });
  }

  /// E-Ink 刷新：墨水屏防残影，按翻页间隔自动全屏闪烁一次。
  /// 复用 [_runFlash] 与闪光覆盖层，颜色/时长由 [ReaderPreferences.einkRefreshStyle]
  /// / [ReaderPreferences.einkRefreshDuration] 决定。
  void _triggerEinkRefresh() {
    if (!mounted) return;
    final Color color =
        _effectivePrefs.einkRefreshStyle == ReaderEInkRefreshStyle.black
            ? Colors.black
            : Colors.white;
    _runFlash(
      color,
      Duration(
        milliseconds: _effectivePrefs.einkRefreshDuration.clamp(50, 1000),
      ),
    );
  }

  /// 收起跳章过渡提示并取消延时跳转（未显示时无副作用）。
  /// 保留以兼容横幅 UI 的清除路径；条漫场景横幅已由「直接自动连读」取代，
  /// 不再有启动入口（_showSkipTransition 恒为 false）。
  void _hideSkipTransition() {
    _skipTransitionTimer?.cancel();
    _skipTransitionTimer = null;
    if (_showSkipTransition) {
      setState(() => _showSkipTransition = false);
    }
  }

  void _goNextChapter() {
    // 切章前收起跳章过渡提示（横幅点击 / 延时到期 / 其它入口统一清理）。
    _hideSkipTransition();
    final next = _resolveChapterTarget(1);
    if (next == null) {
      // 本地模式读完最后一话：无缝接入在线继续阅读（失败回落原提示）。
      if (_isLocalMode && widget.sourceId.isNotEmpty) {
        unawaited(_continueOnlineLocal());
        return;
      }
      _showBoundaryHint(AppLocalizations.of(context).readerLastChapterReached);
      return;
    }
    // 目标章（跳过已读/被过滤/重复章后）优先尝试既有无缝/重锚路径，保持体验；
    // 目标章已预载（或恰为当前章）→ 无缝重锚到其首页，不重建章节。
    if (_seamActive) {
      final bool reanchored =
          _seamAdvance(1, reposition: _SeamAdvanceTarget.first);
      if (reanchored) return;
    }
    // paged 段式连续模型（章末过渡卡 / 章首衔接）：目标章已预载 → 直接交换
    // 图片并重锚到新章首页，无白屏、无网络等待。（仅相邻章走过渡卡衔接。）
    if (_pagedSeamActive &&
        next == _chapterIndex + 1 &&
        _pagedAdvance(next, toLast: false)) {
      return;
    }
    // 跳过过滤或相邻章未预载：整章加载目标章。
    _triggerChapterTransition(widget.chapters[next].title);
    _chapterIndex = next;
    if (_isLocalMode) {
      _loadLocalImages();
    } else {
      _loadChapter(_chapterIndex);
    }
  }

  /// 本地内容读完自动接续在线（无缝）：抓在线目录 → 定位续读点 →
  /// pushReplacement 替换为在线阅读器。失败时提示并允许重试。
  Future<void> _continueOnlineLocal() async {
    if (_localToOnlineTriggered) return;
    _localToOnlineTriggered = true;
    final bool switched = await continueOnlineAfterLocal(
      context,
      sourceType: SourceType.mangaSource,
      contentId: widget.comicId,
      title: widget.title,
      sourceId: widget.sourceId,
      localChapters: widget.chapters,
      localLastIndex: _chapterIndex,
    );
    // 切换未发生（无在线源 / 已是最新 / 抓取失败）：复位触发位以便重试。
    if (!switched && mounted) {
      setState(() => _localToOnlineTriggered = false);
    }
  }

  void _goPrevChapter() {
    // 向上切章时收起跳章过渡提示。
    _hideSkipTransition();
    final prev = _resolveChapterTarget(-1);
    if (prev == null) {
      _showBoundaryHint(AppLocalizations.of(context).readerFirstChapterReached);
      return;
    }
    // 回到上一话恢复「上次离开该话时读到的页」（逐章进度记录）；该话无记录则落
    // 末页（保持既有「上一章 → 上一话末尾」语义）。内存缓存同步可读。
    final int? prevPage = _chapterPageCache[prev];
    // 目标章（跳过已读/被过滤/重复章后）优先尝试无缝/重锚路径：目标章已预载 →
    // 无缝重锚到进度页（无记录末页），不重建章节。
    if (_seamActive) {
      final bool reanchored = prevPage != null
          ? _seamAdvance(-1,
              reposition: _SeamAdvanceTarget.first, targetPage: prevPage)
          : _seamAdvance(-1, reposition: _SeamAdvanceTarget.last);
      if (reanchored) return;
    }
    // paged 段式连续模型（章末过渡卡 / 章首衔接）：目标章已预载 → 直接交换
    // 图片并重锚到进度页（无记录则上一章末页），章首翻上一张保持连贯。
    if (_pagedSeamActive &&
        prev == _chapterIndex - 1 &&
        (prevPage != null
            ? _pagedAdvance(prev, toLast: false, page: prevPage)
            : _pagedAdvance(prev, toLast: true))) {
      return;
    }
    // 跳过过滤或相邻章未预载：整章加载目标章。
    _triggerChapterTransition(widget.chapters[prev].title);
    _chapterIndex = prev;
    // 回到上一话：有进度记录 → 恢复到离开页；否则落到【最后一页】（未读过从头读）。
    if (_isLocalMode) {
      if (prevPage != null) {
        _loadLocalImages(restorePage: prevPage);
      } else {
        _loadLocalImages(restorePage: 0, restoreToLast: true);
      }
    } else {
      if (prevPage != null) {
        _loadChapter(_chapterIndex, restorePage: prevPage);
      } else {
        _loadChapter(_chapterIndex, restoreToLast: true);
      }
    }
  }

  // ─────────────────────── 跳章过滤 ───────────────────────

  /// 计算从当前章沿 [dir]（±1）方向的下一个可导航章节索引（应用跳章过滤）。
  ///
  /// 规则（对应设置项，默认全关）：
  /// - [ReaderPreferences.skipReadChapters]：跳过已读章节（`MediaWatchedManager` 已读集合）。
  /// - [ReaderPreferences.skipFilteredChapters]：跳过被筛选章节（空/空白标题的占位条目）。
  /// - [ReaderPreferences.skipDuplicateChapters]：跳过标题重复章节（保留首次出现）。
  ///
  /// 无可用章节时返回 null（由调用方触发边界提示）。
  int? _resolveChapterTarget(int dir) {
    final bool skipRead = _prefs.skipReadChapters;
    final bool skipFiltered = _prefs.skipFilteredChapters;
    final bool skipDuplicate = _prefs.skipDuplicateChapters;
    if (!skipRead && !skipFiltered && !skipDuplicate) {
      final int t = _chapterIndex + dir;
      return (t >= 0 && t < widget.chapters.length) ? t : null;
    }
    final Set<int>? watched = _watchedReadIndices();
    final Set<int> duplicates = _duplicateChapterIndices();
    var i = _chapterIndex + dir;
    while (i >= 0 && i < widget.chapters.length) {
      final bool isRead = skipRead && (watched?.contains(i) ?? false);
      final bool isFiltered = skipFiltered && _isFilteredChapter(i);
      final bool isDuplicate = skipDuplicate && duplicates.contains(i);
      if (!isRead && !isFiltered && !isDuplicate) return i;
      i += dir;
    }
    return null;
  }

  /// 已读章节索引集合（MediaWatchedManager 未注册时返回 null → 不参与已读跳过）。
  Set<int>? _watchedReadIndices() {
    try {
      return context
          .read<MediaWatchedManager>()
          .watchedList(
            widget.comicId,
          )
          .toSet();
    } on Object {
      return null;
    }
  }

  /// 标题重复章节索引集合：保留首次出现的标题，其后同标题章节视为重复。
  Set<int> _duplicateChapterIndices() {
    final Set<String> seen = <String>{};
    final Set<int> dups = <int>{};
    for (int i = 0; i < widget.chapters.length; i++) {
      final String t = widget.chapters[i].title.trim();
      if (seen.contains(t)) {
        dups.add(i);
      } else {
        seen.add(t);
      }
    }
    return dups;
  }

  /// 被筛选章节判定：空 / 纯空白标题的章节视为被筛除的占位条目。
  bool _isFilteredChapter(int index) {
    if (index < 0 || index >= widget.chapters.length) return false;
    return widget.chapters[index].title.trim().isEmpty;
  }

  /// 直接跳转到指定章节（目录面板 / 章节滑块共用）。
  void _jumpToChapter(int index) {
    // 跳章前收起跳章过渡提示。
    _hideSkipTransition();
    if (index < 0 || index >= widget.chapters.length) return;
    if (index == _chapterIndex) return;
    // 相邻章先尝试既有无缝/重锚路径，保持阅读体验。
    // 注意：目录点选是显式目标，不应用跳章过滤（_seamAdvance 内部默认按过滤
    // 目标定位，这里必须传 targetOverride 钉死用户点选的章）。
    if (index == _chapterIndex + 1) {
      if (_seamActive) {
        if (_seamAdvance(1,
            reposition: _SeamAdvanceTarget.first, targetOverride: index)) {
          return;
        }
      }
      if (_pagedSeamActive && _pagedAdvance(index, toLast: false)) return;
    } else if (index == _chapterIndex - 1) {
      // 回上一章：恢复到「上次离开该话时读到的页」；无记录落末页。
      final int? prevPage = _chapterPageCache[index];
      if (_seamActive) {
        if (prevPage != null
            ? _seamAdvance(-1,
                reposition: _SeamAdvanceTarget.first,
                targetPage: prevPage,
                targetOverride: index)
            : _seamAdvance(-1,
                reposition: _SeamAdvanceTarget.last, targetOverride: index)) {
          return;
        }
      }
      if (_pagedSeamActive &&
          (prevPage != null
              ? _pagedAdvance(index, toLast: false, page: prevPage)
              : _pagedAdvance(index, toLast: true))) {
        return;
      }
    }
    _triggerChapterTransition(widget.chapters[index].title);
    _chapterIndex = index;
    // 目录点选之前读过的话（非相邻 / 邻话未预载、seam/paged 重锚不适用）时，
    // 整章加载同样恢复到「上次离开该话时读到的页」（与「上一章」按钮语义一致）；
    // 无记录从首页开始。
    final int? restorePage = _chapterPageCache[index];
    if (_isLocalMode) {
      _loadLocalImages(restorePage: restorePage ?? 0);
    } else {
      _loadChapter(_chapterIndex, restorePage: restorePage ?? 0);
    }
  }

  // ─────────────────────── 章节导航滑块 ───────────────────────

  /// 章节导航滑块：阅读器右缘的竖向拖动条。
  ///
  /// 拖动时按位置换算章节并 haptic 反馈 + 顶部预览当前章节标题；松手跳章。
  /// 仅多章节作品显示（单文件本地无章节概念隐藏）。
  Widget _buildChapterSlider(AppLocalizations l10n) {
    final int total = widget.chapters.length;
    if (total <= 1) return const SizedBox.shrink();
    final int current = _chapterIndex;
    final String label = l10n.chapterN(current + 1);
    final Color scrim = Theme.of(context).colorScheme.surface;
    return Positioned(
      top: 80,
      left: 6,
      bottom: 90,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (_) {
            AppHaptics.selectionClick();
            setState(() => _sliderPreviewChapter = current);
          },
          onVerticalDragUpdate: (d) {
            final double h = MediaQuery.sizeOf(context).height;
            final double t = (d.localPosition.dy / h).clamp(0.0, 1.0);
            final int idx = (t * (total - 1)).round().clamp(0, total - 1);
            if (idx != _sliderPreviewChapter) {
              AppHaptics.selectionClick();
              setState(() => _sliderPreviewChapter = idx);
            }
          },
          onVerticalDragEnd: (_) {
            final int? target = _sliderPreviewChapter;
            setState(() => _sliderPreviewChapter = null);
            if (target != null && target != _chapterIndex) {
              _jumpToChapter(target);
            }
          },
          onVerticalDragCancel: () {
            setState(() => _sliderPreviewChapter = null);
          },
          child: Container(
            width: 34,
            decoration: BoxDecoration(
              color: scrim.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Icon(Icons.drag_handle_rounded,
                    size: 16, color: Colors.white70),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// paged 段式连续模型重锚（跨章无缝续读 · paged 分支）：把「当前章」前移/
  /// 后移到目标相邻章。
  ///
  /// [target] 为目标章索引；[toLast] 决定落点：true = 跳到新章末页（「上一章」），
  /// false = 跳到新章首页（「下一章」）。
  ///
  /// 返回是否真正执行了重锚（越界/目标未预载时返回 false，由调用方回退到整章加载）。
  /// 执行序列：交换 [_images]/[_preload] → 预载新邻章 → 清页旋转表 → 重置缩放 →
  /// [_setupControllers] 以目标页重建 PageController（每章独立 Key，initialPage 必定
  /// 生效，确定性瞬移到目标页，无中间态/无白屏）→ 写盘进度。
  bool _pagedAdvance(int target, {required bool toLast, int? page}) {
    if (_pagedReanchoring) return false;
    if (target < 0 || target >= widget.chapters.length) return false;
    if (target == _chapterIndex) return false;
    final List<String> targetImgs = _preload[target] ?? const <String>[];
    if (targetImgs.isEmpty) return false; // 未预载 → 整章加载兜底。
    _pagedReanchoring = true;
    final int oldChapter = _chapterIndex;
    // 交换章节数据：旧当前章转存预载缓存（成为重锚后的邻段），目标章提升为当前章。
    _preload[oldChapter] = _images;
    _images = targetImgs;
    _chapterIndex = target;
    // 睡眠定时按话数计数（；paged 无缝重锚切章同样算「读完一话进入下一话」）。
    _onChapterEntered();
    // 翻章后刷新顶栏章节书签状态。
    unawaited(_refreshChapterBookmark());
    // 预载新一层的相邻章（越界时自动忽略）。
    final int dir = target > oldChapter ? 1 : -1;
    if (_isAggregatedLocal ||
        (widget.localChapterDirs != null &&
            widget.localChapterDirs!.isNotEmpty)) {
      unawaited(_preloadChapterLocal(target + dir));
    } else {
      _preloadChapter(target + dir);
    }
    // 页旋转表仅对当前章有效：重锚后旧章旋转记录不再适用，整表清空。
    _pageRotations.clear();
    _resetZoom();
    final int last = _images.isEmpty ? 0 : _images.length - 1;
    // 落点：[page] 显式页（回到上一话恢复离开页）优先；否则 toLast=末页、否则首页。
    final int p = (page ?? (toLast ? last : 0)).clamp(0, last);
    _currentPage = p;
    _setupControllers(restorePage: p);
    _scheduleProgressSave(p);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pagedReanchoring = false;
    });
    return true;
  }

  /// 章节边界提示（已是第一话 / 最后一话）。短暂 SnackBar，避免遮挡阅读区。
  void _showBoundaryHint(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1400),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// 判断指针（热区覆盖层局部坐标）是否落在顶部 / 底部控制栏区域内。
  ///
  /// 控制栏展开时，点在按钮上应交给按钮自身处理，不应再触发上一页 / 下一页；
  /// 沉浸阅读（控制栏隐藏）时返回 false，交还全部区域给热区翻页。
  ///
  /// 实现：把指针坐标换算到全局空间，再与各控制栏 Container 的全局包围盒比对
  /// （自动涵盖 SafeArea 内边距，无需手动计算状态栏 / 底部安全区高度）。
  bool _isInToolbarRegion(Offset localPos) {
    if (!_uiVisible) return false;
    final overlayBox = _tapZonesKey.currentContext?.findRenderObject();
    if (overlayBox is! RenderBox) return false;
    final Offset global = overlayBox.localToGlobal(localPos);
    for (final key in <GlobalKey>[_topBarKey, _bottomBarKey]) {
      final box = key.currentContext?.findRenderObject();
      if (box is RenderBox) {
        final Offset topLeft = box.localToGlobal(Offset.zero);
        final rect = Rect.fromLTWH(
          topLeft.dx,
          topLeft.dy,
          box.size.width,
          box.size.height,
        );
        if (rect.contains(global)) return true;
      }
    }
    return false;
  }

  /// 章节切换过渡标题卡：若开启 [ReaderPreferences.showChapterTransition]，
  /// 在章节切换时短暂居中显示章节标题，约 1.2s 后淡出。
  void _triggerChapterTransition(String title) {
    if (!_prefs.showChapterTransition || !mounted) return;
    setState(() {
      _transitionTitle = title;
      _transitionVisible = true;
    });
    _transitionTimer?.cancel();
    _transitionTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _transitionVisible = false);
    });
  }

  /// 双击缩放：三态循环（用户需求，与 photo_view 的 scaleState 循环一致）——
  /// 原样(1x) → 缩小(0.5x) → 放大([ReaderPreferences.doubleTapZoomScale]) →
  /// 恢复原样(1x) → …。preventShrink 打开时跳过缩小态（1x ↔ 放大两态）。
  /// 以 [focal]（视口坐标）或视口中心为锚点；[focal] 为 null 时使用中心。
  ///
  /// 缩小态固定为 0.5x（低于默认 minScale=1.0 = fit），属三态循环的既定行为；
  /// [preventShrink] 仅约束捏合/平移是否回弹到适配尺寸，同时跳过缩小态。
  ///
  /// 实现要点：
  /// - 每次双击【绝对设置】目标矩阵（不乘旧矩阵），直接到达目标态——避免
  /// 「乘旧矩阵」的浮点累积导致循环错乱。
  /// - Transform/AnimatedBuilder 以「视口中心」为原点（等价 alignment: center），
  /// 而 focal 是「左上原点」坐标；[_toTransformAnchor] 负责换算。
  void _toggleZoom([Offset? focal]) {
    // 双击缩放开关：关闭时任何触发路径（双击 / 定点双击 / Shift+左键兜底）均不缩放。
    if (!_prefs.doubleTapZoom) return;
    // 缩放动画进行中：先定格到目标态并结束动画，再进入下一次三态循环——
    // 否则动画未完成（如翻页时 _resetZoom 中断）会留下 _zoomAnimating=true，
    // 后续双击被「忽略新请求」吞掉，表现为「三态只剩缩小、之后双击无反应」。
    if (_zoomAnimating) {
      final Matrix4? t = _zoomAnimTarget;
      _stopZoomAnimation();
      if (t != null) _zoomController.value = Matrix4.copy(t);
    }
    final m = _zoomController.value;
    final cur = m.getMaxScaleOnAxis();
    final Size vp = MediaQuery.of(context).size;
    // 缩放锚点来源（zoomStart）：双击时按设置决定横向锚点位置，
    // 纵轴沿用触点（保留 「按触点」触感，不破坏竖屏 webtoon 语义）。
    final Offset anchor =
        focal == null ? Offset.zero : _anchorFromZoomStart(focal, vp);
    // 三态循环：放大态 → 恢复原样；防缩小时 1x ↔ 放大两态；缩小态 → 放大；
    // 原样 → 缩小（第一次双击，固定 0.5x）。
    final double target;
    if (cur > 1.001) {
      target = 1.0; // 放大态 → 恢复原样
    } else if (_prefs.preventShrink) {
      target = _prefs.doubleTapZoomScale; // 防缩小时 1x ↔ 放大两态
    } else if (cur < 0.999) {
      target = _prefs.doubleTapZoomScale; // 缩小态 → 放大
    } else {
      target = 0.5; // 原样 → 缩小（第一次双击）
    }
    // 绝对设置：translate(anchor*(1-target)) · scale(target)。
    // 推导：中心系坐标 c 变换为 c' = c*t + T；焦点保持不动需 c' = c →
    // T = anchor*(1-target)。webtoon 的 anchor 纵向为 0（纵向滚动交还列表）。
    _animateZoomTo(
      Matrix4.identity()
        ..translateByDouble(
            anchor.dx * (1 - target), anchor.dy * (1 - target), 0.0, 1.0)
        ..scaleByDouble(target, target, target, 1.0),
    );
  }

  /// 缩放矩阵过渡动画（双击缩放动画）。
  ///
  /// 时长取 [ReaderPreferences.doubleTapAnimSpeed]（默认 500ms），并随系统
  /// [MediaQuery.disableAnimations]（减弱动态效果）按比例缩放；系统关闭动画或
  /// 时长 ≤0 时直接瞬切（双击缩放开关为关时由调用方提前返回，动画完全跳过）。
  /// 动画期间置位 [_zoomAnimating]，完成/取消后复位。
  void _animateZoomTo(Matrix4 target) {
    final Matrix4 m = _zoomController.value;
    if (m == target) return;
    if (!_prefs.doubleTapZoom) {
      _zoomController.value = target;
      return;
    }
    final bool sysNoAnim = MediaQuery.of(context).disableAnimations ||
        _prefs.doubleTapAnimSpeed <= 0;
    final int ms = sysNoAnim ? 0 : _prefs.doubleTapAnimSpeed;
    if (ms <= 0) {
      _zoomController.value = target;
      return;
    }
    final AnimationController c =
        _zoomAnimController ??= AnimationController(vsync: this);
    _stopZoomAnimation();
    c.duration = Duration(milliseconds: ms);
    _zoomAnimating = true;
    _zoomAnimTarget = target;
    final Animation<double> curve =
        CurvedAnimation(parent: c, curve: Curves.easeOutCubic);
    final Matrix4Tween tween = Matrix4Tween(begin: m, end: target);
    final Animation<Matrix4> anim = tween.animate(curve);
    void onTick() => _zoomController.value = anim.value;
    void onStatus(AnimationStatus status) {
      if (status != AnimationStatus.completed) {
        // Bug3 修复：forward(from: 0) 在已完成的控制器上设置 value=0 时会触发
        // dismissed 状态通知，若在此提前清理会导致二次动画被扼杀（动画永不推进）。
        // 仅 completed（动画到达 target）才清理；dismissed / 中途取消由
        // _stopZoomAnimation 摘除本监听并复位状态，无需在此处理。
        return;
      }
      _zoomAnimating = false;
      _zoomAnimTarget = null;
      // 动画结束即卸载本轮监听，避免下一轮重复移除。
      c.removeListener(onTick);
      c.removeStatusListener(onStatus);
      if (identical(_zoomAnimTick, onTick)) _zoomAnimTick = null;
      if (identical(_zoomAnimStatus, onStatus)) _zoomAnimStatus = null;
    }

    _zoomAnimTick = onTick;
    _zoomAnimStatus = onStatus;
    c.addListener(onTick);
    c.addStatusListener(onStatus);
    c.forward(from: 0);
  }

  /// 结束当前缩放动画：停止控制器、摘除本轮监听、复位动画状态与目标。
  /// 供双击连点（先定格再继续三态循环）与翻页/切章 [_resetZoom] 调用，
  /// 避免残留 [_zoomAnimating]=true 导致后续双击/手势被永久忽略（三态失效）。
  void _stopZoomAnimation() {
    final AnimationController? c = _zoomAnimController;
    if (c == null) return;
    c.stop();
    if (_zoomAnimTick != null) {
      c.removeListener(_zoomAnimTick!);
      _zoomAnimTick = null;
    }
    if (_zoomAnimStatus != null) {
      c.removeStatusListener(_zoomAnimStatus!);
      _zoomAnimStatus = null;
    }
    _zoomAnimating = false;
    _zoomAnimTarget = null;
  }

  /// 按 [ReaderPreferences.zoomStart] 计算双击缩放锚点。
  /// - [ZoomStart.center]（默认）：沿用触点横坐标（保留 「按触点」锚定）；
  /// - [ZoomStart.left] / [ZoomStart.right]：锚点 x 取视口左右 1/4 / 3/4 处，
  /// 方便放大 2 页跨页时聚焦到对应侧。
  /// 纵轴始终沿用触点 y，返回中心原点坐标系坐标。
  Offset _anchorFromZoomStart(Offset tap, Size vp) {
    final double x = switch (_prefs.zoomStart) {
      ZoomStart.center => tap.dx,
      ZoomStart.left => vp.width * 0.25,
      ZoomStart.right => vp.width * 0.75,
    };
    return _toTransformAnchor(Offset(x, tap.dy), vp);
  }

  /// 长按缩放：开启 [ReaderPreferences.enableLongPressToZoom] 后，
  /// 长按以 [ReaderPreferences.longPressZoomPosition] 为锚点放大到 1.75x。
  /// - [LongPressZoomPosition.press]：按触点放大；
  /// - [LongPressZoomPosition.center]：按屏幕中心放大。
  /// 松手由 [_exitLongPressZoom] 恢复原样（长按与双击为不同手势通道，互不冲突）。
  void _enterLongPressZoom(Offset pos) {
    if (!_prefs.doubleTapZoom) return;
    final Size vp = MediaQuery.of(context).size;
    final Offset focal =
        _prefs.longPressZoomPosition == LongPressZoomPosition.center
            ? Offset(vp.width / 2, vp.height / 2)
            : pos;
    final Offset anchor = _toTransformAnchor(focal, vp);
    _zoomController.value = Matrix4.identity()
      ..translateByDouble(
          anchor.dx * (1 - 1.75), anchor.dy * (1 - 1.75), 0.0, 1.0)
      ..scaleByDouble(1.75, 1.75, 1.75, 1.0);
  }

  /// 长按缩放退出：恢复原样。
  void _exitLongPressZoom() {
    _zoomController.value = Matrix4.identity();
  }

  /// 监听共享 [_zoomController]：放大状态变化时同步 [_zoomed]，使底层 PageView /
  /// ListView 在放大时关闭滚动手势（避免与图片平移手势打架），未放大时恢复。
  void _onZoomChanged() {
    final zoomed = _zoomController.value.getMaxScaleOnAxis() > 1.001;
    if (zoomed != _zoomed && mounted) setState(() => _zoomed = zoomed);
    // 缩放状态变化时清零边缘滑动累计，避免残留累计在新缩放态下误触发。
    _edgeSwipeAccum = Offset.zero;
  }

  /// 打开 / 关闭内联阅读设置面板。
  ///
  /// 与小说阅读器对齐：桌面（宽度 ≥ [AppTokens.desktopBreakpoint]）面板停在
  /// 右侧、移动端停在底部；改动通过 [onChanged] 即时预览并落盘（[_applySettingsAuto]），
  /// 关闭时草稿已应用，无需额外提交。
  void _openSettings() {
    _toggleInlineSettings();
  }

  /// 切换内联设置面板的显隐。
  ///
  /// 关闭时统一提交设备/会话层草稿（[_commitDeviceOverride]）到作品层持久化：
  /// 面板有三种关闭路径（面板内关闭按钮 / Esc / 点阅读区任意处），此前仅按钮
  /// 路径提交，Esc 与点击关闭会丢掉本次会话的全部改动（自动翻页间隔、自动
  /// 下载开关等重开阅读器后回退）。
  void _toggleInlineSettings() {
    final bool closing = _showInlineSettings;
    setState(() => _showInlineSettings = !_showInlineSettings);
    if (closing) {
      unawaited(_commitDeviceOverride());
    }
  }

  /// 设置面板内的改动：即时预览 + 自动保存。
  ///
  /// 仅对「影响系统 UI / 控制器结构」的字段做重应用，避免亮度/滤镜等连续
  /// 滑块拖动时反复重建控制器或切换全屏造成卡顿：
  /// - orientation / fullscreen / keepScreenOn 变化 → 重应用系统 UI；
  /// - readingMode / splitDoublePage 变化 → 重建控制器（paged↔webtoon、单↔双页）。
  ///
  /// 注意：先同步更新 [_prefs]（不单独 setState），再由 [_setupControllers]
  /// 一次性 setState，避免「新 prefs + 旧控制器」的中间帧导致进度条/页码不同步。
  ///
  /// 三层设置覆盖的写入路径：
  /// - [persist] = true：写入作品层并持久化（底栏工具栏等明确落盘的操作），清除设备层；
  /// - [persist] = false：写入设备/会话层（[_devicePrefs]，内联面板即时预览），
  /// 会话内落到 [_prefs] 保证渲染即时生效，关闭面板时经 [_commitDeviceOverride] 提交。
  Future<void> _applySettings(ReaderPreferences next,
      {required bool persist}) async {
    if (!mounted) return;
    final prev = _prefs;
    // 记录本次真正改动的字段为「本书单独设置」，未动过的字段继续跟随总设置。
    // 设备层预览与直接落盘两条路径都走这里，覆盖记录随改动即时累积，
    // 由 [_commitDeviceOverride] / persist 分支一并持久化。
    _overrideKeys.addAll(comicPrefsChangedKeys(prev, next));
    _prefs = next;
    // 漫画翻译开关即时生效（打开时对当前页发起翻译）。
    if (prev.translationEnabled != next.translationEnabled) _syncTranslation();
    if (persist) {
      _devicePrefs = null;
      await _store.save(widget.comicId, next, overrideKeys: _overrideKeys);
    } else {
      _devicePrefs = next;
    }
    if (prev.motionEffects != next.motionEffects) {
      // 动态效果设置变更：重估渲染任务并立即刷新叠加层（关闭即撤下）。
      _scheduleMotion();
      if (mounted) setState(() {});
    }
    _syncVolumeKey();
    _syncAutoMotion();
    if (!prev.autoDownloadChapters && next.autoDownloadChapters) {
      // 面板里刚开启自动下载：若当前已读过本章 >25%，立即检查入队，
      // 不必等下一次翻页保存进度才触发（「开了没反应」的观感来源）。
      _maybeAutoDownload(_currentPage);
    }
    if (prev.orientation != next.orientation) _applyOrientation();
    if (prev.fullscreen != next.fullscreen) _applyFullscreen();
    if (prev.keepScreenOn != next.keepScreenOn) _applyWakelock();
    if (prev.readerBrightness != next.readerBrightness) _applyBrightness();
    if (prev.showClockBattery != next.showClockBattery) {
      if (next.showClockBattery) {
        _initTimeAndBattery();
      } else {
        _stopTimeAndBattery();
      }
    }
    if (prev.readingMode != next.readingMode ||
        prev.splitDoublePage != next.splitDoublePage) {
      if (_images.isNotEmpty) {
        _setupControllers(
          restorePage: _currentPage,
          wasDoublePage: prev.splitDoublePage && prev.readingMode.isPaged,
        );
        return;
      }
    }
    // seamlessReading / showChapterSeparator 变化不重建控制器，但需重建段式连续模型
    // （开启/关闭无缝、显隐章分割条目的即时生效）。
    if (prev.seamlessReading != next.seamlessReading ||
        prev.showChapterSeparator != next.showChapterSeparator) {
      _seamReloadFromPrefs();
    }
    if (mounted) setState(() {});
  }

  /// 设备/会话层预览写入：内联设置面板的 onChanged 回调。
  ///
  /// 写入设备层（退出阅读器前不持久化），但会话内落到 [_prefs] 保证渲染/控制器
  /// 即时预览；关闭面板时由 [_commitDeviceOverride] 提交到作品层持久化。
  Future<void> _applyDeviceOverride(ReaderPreferences next) =>
      _applySettings(next, persist: false);

  /// 提交设备/会话层到作品层并持久化（内联面板关闭时调用），随后清除设备层。
  Future<void> _commitDeviceOverride() async {
    final ReaderPreferences? device = _devicePrefs;
    if (device == null) return;
    _devicePrefs = null;
    await _store.save(widget.comicId, device, overrideKeys: _overrideKeys);
  }

  /// 即时落盘偏好变更（用于底栏快捷工具栏的开关，例如裁剪 / 模式切换）。
  /// 同样避免「新 prefs + 旧控制器」的中间帧。
  Future<void> _onPrefsChanged(ReaderPreferences next) =>
      _applySettings(next, persist: true);

  // ─────────────────────── 音量键翻页 ───────────────────────

  /// 按当前偏好同步音量键监听：Android / 鸿蒙手机且开启 [ReaderPreferences.volumeKeyPageTurn]
  /// 时通过 [VolumeKeyListener] 挂载原生拦截（彻底消费按键事件，阻止系统
  /// 音量条弹出），否则停止并恢复系统默认音量键行为。调用点：[_init]、
  /// [_applySettingsAuto]、[_onPrefsChanged]（偏好变化后即时生效）。
  Future<void> _syncVolumeKey() async {
    // 音量键拦截走原生通道：Android dispatchKeyEvent / 鸿蒙 inputConsumer。
    final bool want = _prefs.volumeKeyPageTurn &&
        (PlatformService.instance.isAndroid ||
            PlatformService.instance.isOHOSPhone);
    if (want) {
      // Bug1 修复：async + try/catch，启动失败（原生通道未就绪/订阅异常）不再被
      // unawaited 静默吞掉，写日志便于实机排查。
      try {
        await _volumeKeyListener.start(
          onVolumeDown: _onVolumeKeyDown,
          onVolumeUp: _onVolumeKeyUp,
        );
      } on Object catch (e) {
        AppLog.instance.e('[音量键] 启动失败: $e');
      }
    } else {
      try {
        await _volumeKeyListener.stop();
      } on Object catch (e) {
        AppLog.instance.e('[音量键] 停止失败: $e');
      }
    }
  }

  /// 音量下键（KEYCODE_VOLUME_DOWN）：下一页 / 向下滚动。
  void _onVolumeKeyDown() {
    _volumeKeyAction(1);
  }

  /// 音量上键（KEYCODE_VOLUME_UP）：上一页 / 向上滚动。
  void _onVolumeKeyUp() {
    _volumeKeyAction(-1);
  }

  /// 音量键动作：翻页模式翻页；条漫模式按 [ReaderPreferences.volumeKeyPageTurnDistancePercent]
  /// 占视口高度的比例滚动（更符合连续滚动阅读习惯）。
  void _volumeKeyAction(int dir) {
    if (_prefs.readingMode.isWebtoon) {
      final ScrollOffsetController? soc = _webtoonOffsetController;
      final double vp = _webtoonViewport ?? MediaQuery.of(context).size.height;
      if (soc != null) {
        final double px =
            vp * _prefs.volumeKeyPageTurnDistancePercent / 100 * dir;
        unawaited(soc
            .animateScroll(
              offset: px,
              duration: const Duration(milliseconds: 120),
            )
            .catchError((Object _) {}));
        return;
      }
      // 无滚动控制器（切章/重建中）时回落到单步翻页。
      _webtoonStep(dir);
      return;
    }
    // 方向映射（Bug1 复核确认无误）：音量下键 = dir +1 = 下一页 / 向下滚动；
    // 音量上键 = dir -1 = 上一页 / 向上滚动。
    if (dir > 0) {
      _goNextPage();
    } else {
      _goPrevPage();
    }
  }

  // ─────────────────── 自动翻页与自动滚动 ───────────────────

  /// 自动滚动基准速度（像素/秒）：乘以 [ReaderPreferences.readerScrollSpeed] 得到
  /// 实际滚动速度（默认 1.0 → 60 px/s，条漫常见阅读节奏）。
  static const double _autoScrollBasePxPerSec = 60.0;

  /// 按当前偏好同步自动翻页定时器（paged）与自动滚动 Ticker（webtoon）。
  /// 后台（[_autoScrollPaused]）或模式不匹配时一律停止。调用点同 [_syncVolumeKey]，
  /// 以及 [didChangeAppLifecycleState] 从后台恢复时。
  void _syncAutoMotion() {
    // 自动翻页：仅翻页模式 + 开关开启 + 间隔 > 0 生效。
    final bool wantPage = _prefs.readingMode.isPaged &&
        _prefs.autoPageTurningEnabled &&
        _prefs.autoPageTurningInterval > 0 &&
        !_autoScrollPaused;
    if (wantPage) {
      if (_autoPageTurnTimer == null ||
          _lastAutoPageInterval != _prefs.autoPageTurningInterval) {
        _autoPageTurnTimer?.cancel();
        _lastAutoPageInterval = _prefs.autoPageTurningInterval;
        _autoPageTurnTimer = Timer.periodic(
          Duration(seconds: _prefs.autoPageTurningInterval),
          (_) => _goNextPage(),
        );
      }
    } else if (_autoPageTurnTimer != null) {
      _autoPageTurnTimer?.cancel();
      _autoPageTurnTimer = null;
      _lastAutoPageInterval = null;
    }
    // 自动滚动：仅条漫模式 + 开关开启生效。
    final bool wantScroll =
        _prefs.readingMode.isWebtoon && _prefs.autoScroll && !_autoScrollPaused;
    if (wantScroll && _autoScrollTicker == null) {
      _autoScrollElapsed = Duration.zero;
      _autoScrollPendingPx = 0;
      _autoScrollChunkElapsed = Duration.zero;
      _autoScrollTicker = createTicker(_onAutoScrollTick)..start();
      _autoScrolling = true;
    } else if (!wantScroll && _autoScrollTicker != null) {
      _autoScrollTicker?.stop();
      _autoScrollTicker = null;
      _autoScrolling = false;
      // 滚动期间跳过了图片收藏异步刷新，停止后按最终页补一次。
      unawaited(_refreshPageImageFav());
    }
  }

  /// 自动滚动单帧回调：像素先累积到 [_autoScrollPendingPx]，每满
  /// [_autoScrollChunkMs] 窗口才发起一次 [ScrollOffsetController.animateScroll]，
  /// 动画时长与窗口一致，速度仍为 `60px/s × readerScrollSpeed`。
  ///
  /// 旧实现每帧调用 animateScroll(offset: px, duration: 16ms)，每帧新建
  /// DrivenScrollActivity 都会取消上一轮活动——条漫图片顶端到达屏幕顶端时帧边界
  /// 抖动（卡一下）。分块累积后 animateScroll 的发起频率降至约 8 次/秒，相邻动画
  /// 自然衔接（窗口时长 ≥ 动画时长），不再有每帧取消的抖动。
  void _onAutoScrollTick(Duration elapsed) {
    if (_autoScrollPaused || !mounted) return;
    final Duration delta = elapsed - _autoScrollElapsed;
    _autoScrollElapsed = elapsed;
    _autoScrollPendingPx += _autoScrollBasePxPerSec *
        _prefs.readerScrollSpeed *
        delta.inMicroseconds /
        1e6;
    _autoScrollChunkElapsed += delta;
    if (_autoScrollChunkElapsed.inMilliseconds < _autoScrollChunkMs) return;
    if (_autoScrollPendingPx <= 0) return;
    final ScrollOffsetController? soc = _webtoonOffsetController;
    if (soc == null) return;
    final double px = _autoScrollPendingPx;
    _autoScrollPendingPx = 0;
    _autoScrollChunkElapsed = Duration.zero;
    unawaited(soc
        .animateScroll(
          offset: px,
          duration: const Duration(milliseconds: _autoScrollChunkMs),
        )
        .catchError((Object _) {}));
  }

  /// 应用前后台切换：后台暂停自动翻页 / 自动滚动，前台恢复（若偏好仍开启）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final bool background = state != AppLifecycleState.resumed;
    // 进程被杀恢复：退后台（paused/detached）时系统随时可能杀掉进程，
    // dispose 兜底不会执行。此刻把防抖中的进度与偏好立即落盘，保证重开应用
    // 能从最后位置继续（章节/页码恢复走既有的 [ComicProgressManager] 存档链路）。
    if (background && !_restoringPage && _images.isNotEmpty) {
      if (_saveProgressDebounce?.isActive ?? false) {
        final page = _pendingSavePage ?? _currentPage;
        _saveProgressDebounce?.cancel();
        _flushPendingProgress(page);
        _pendingSavePage = null;
      } else {
        _flushPendingProgress(_currentPage);
      }
      unawaited(
          _store.save(widget.comicId, _prefs, overrideKeys: _overrideKeys));
      unawaited(_commitDeviceOverride());
    }
    if (_autoScrollPaused == background) return;
    _autoScrollPaused = background;
    if (background) {
      _autoPageTurnTimer?.cancel();
      _autoPageTurnTimer = null;
      _autoScrollTicker?.stop();
      _autoScrollTicker = null;
      _autoScrolling = false;
    } else {
      if (mounted) _syncAutoMotion();
    }
  }

  /// 翻页淡入（[ReaderPageAnimation.fade]）：翻页后透明度 0 → 1 淡入。
  /// 用 [_pageFadeOpacity] 驱动 [AnimatedOpacity]，不改 PageView 翻页结构。
  void _runPageFade() {
    if (!_prefs.readingMode.isPaged ||
        _prefs.pageAnimation != ReaderPageAnimation.fade) {
      return;
    }
    if (!mounted) return;
    _pageFadeTimer?.cancel();
    setState(() => _pageFadeOpacity = 0.0);
    _pageFadeTimer = Timer(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      setState(() => _pageFadeOpacity = 1.0);
      _pageFadeTimer = null;
    });
  }

  // ── 页面动态效果（comic_motion）─────────────────────────────

  /// 当前屏展示的页 URL 集合（动态效果的渲染对象）。
  /// paged 模式 = 当前屏页；webtoon 连续滚动模式 = 视口内「自身可见比例
  /// 足够高」的条目（见 [webtoonMotionFlatIndices]），滚动停止后才渲染。
  List<String> _visiblePageUrls() {
    if (_images.isEmpty || _loading || _error != null) {
      return const <String>[];
    }
    if (_prefs.readingMode.isWebtoon) {
      final positions = _itemPositionsListener?.itemPositions.value;
      if (positions == null || positions.isEmpty) return const <String>[];
      final bool seam = _seamActive && _seamItemCount > 0;
      final flats = webtoonMotionFlatIndices(<({int index, double leading, double trailing})>[
        for (final p in positions)
          if (!seam ||
              p.index < 0 ||
              p.index >= _seamPageMap.length ||
              _seamPageMap[p.index] >= 0)
            (
              index: p.index,
              leading: p.itemLeadingEdge,
              trailing: p.itemTrailingEdge,
            ),
      ]);
      final urls = <String>[];
      for (final f in flats) {
        final String? url = seam
            ? (f >= 0 && f < _seamImages.length ? _seamImages[f] : null)
            : (f >= 0 && f < _images.length ? _images[f] : null);
        if (url != null && !urls.contains(url)) urls.add(url);
      }
      return urls;
    }
    if (_isGalleryMode) {
      final pc = _pageController;
      final int screen = (pc?.page?.round() ?? (_currentPage ~/ _galleryCount))
          .clamp(0, _controllerPageCount - 1);
      final int start = (screen * _galleryCount).clamp(0, _images.length - 1);
      final int end = (start + _galleryCount).clamp(0, _images.length);
      return <String>[for (int i = start; i < end; i++) _images[i]];
    }
    if (_isDoublePage) {
      final pc = _pageController;
      final int spread =
          (pc?.page?.round() ?? _doublePageSpreadFor(_currentPage))
              .clamp(0, _spreadCount - 1);
      final int left = _doublePageLeftPageFor(spread);
      final int end = (left + 2).clamp(0, _images.length);
      return <String>[
        for (int i = left; i < end; i++)
          if (i >= 0) _images[i],
      ];
    }
    return <String>[_images[_currentPage.clamp(0, _images.length - 1)]];
  }

  /// 重估动态效果：主开关开启时，为当前屏页面安排渲染（驻留
  /// [_motionDwellMs] 防抖：paged 翻页停留 / 条漫滚动停止后触发）；
  /// 条件不满足即取消在途任务并撤下叠加层。
  void _scheduleMotion() {
    _motionJobsEpoch++; // 旧世代渲染循环自行退出
    _motionDebounce?.cancel();
    _motionDebounce = null;
    _motionFollowTimer?.cancel();
    _motionFollowTimer = null;
    final bool applicable = _prefs.motionEffects.enabled &&
        _images.isNotEmpty &&
        !_loading &&
        _error == null &&
        // 系统「减弱动态」开启：整体不渲染，保持静态。
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    if (!applicable) {
      _cancelMotionJob();
      return;
    }
    // 条漫渲染时机模式：dwell = 停留渲染（省电默认，停定后一次性出完整画质）；
    // follow = 实时跟随（中断式两阶段）：200ms 快速版先出图，停定后 800ms
    // 完整画质轮升级替换；视野变化的在途任务立即取消，渲染追着当前页。
    final bool follow = _prefs.readingMode.isWebtoon &&
        _prefs.motionEffects.webtoonRenderMode ==
            MotionWebtoonRenderMode.follow;
    if (follow &&
        _motionJobUrl != null &&
        !_visiblePageUrls().contains(_motionJobUrl)) {
      _cancelMotionJob();
    }
    if (follow) {
      _motionFollowTimer = Timer(
        const Duration(milliseconds: _motionFollowMs),
        () => unawaited(_runMotionJobs(full: false)),
      );
    }
    _motionDebounce = Timer(
      const Duration(milliseconds: _motionDwellMs),
      () => unawaited(_runMotionJobs(full: true)),
    );
  }

  /// 取消在途渲染任务（不清缓存：已渲染结果继续复用）。
  void _cancelMotionJob() {
    _motionToken?.cancel();
    _motionToken = null;
    _motionJobUrl = null;
  }

  /// 依序渲染当前屏页面（串行：任何时刻至多一个渲染 isolate）。
  ///
  /// [full] = 完整画质（用户设置）；false = 快速版（实时跟随滚动中，
  /// 见 [MotionEffectSettings.toFastEffectConfig]）。缓存里已有完整画质
  /// 条目永不重渲染；快速条目只在完整轮升级，快速轮不重派已有条目。
  Future<void> _runMotionJobs({required bool full}) async {
    final int epoch = _motionJobsEpoch;
    final List<String> urls = _visiblePageUrls();
    for (final String url in urls) {
      if (!mounted || epoch != _motionJobsEpoch) return;
      // 完整画质任务在途时快速轮让位（滚动已停定，升级优先）。
      if (!full && _motionJobFull && _motionJobUrl != null) return;
      final _MotionCacheEntry? entry = _motionCache[url];
      if (entry != null && (entry.full || !full)) continue;
      await _renderMotionFor(url, full: full);
      // 渲染期间可能已退出阅读器 / 已有新调度：不再继续队列。
      if (!mounted || epoch != _motionJobsEpoch) return;
    }
  }

  /// 渲染单页动态效果：取原始字节 → 后台 isolate 渲染 GIF → 入缓存并展示。
  /// [full] = 完整画质；false = 快速版（实时跟随滚动中）。
  /// 中断式：同页在途任务质量低于本次请求（快速 → 完整升级）时直接中断重派；
  /// 失败静默回退静态显示（不提示不重试，下次驻留重新触发）。
  Future<void> _renderMotionFor(String url, {required bool full}) async {
    // 同页在途且质量不低于本次请求：不重复派发。
    if (_motionJobUrl == url && (_motionJobFull || !full)) return;
    _cancelMotionJob(); // 单任务槽：新任务中断在途（完整轮升级快速任务同理）
    _motionJobUrl = url;
    _motionJobFull = full;
    final token = MotionCancelToken();
    _motionToken = token;
    try {
      final Uint8List? bytes = await resolveSourceImageBytes(
        url: url,
        source: _source,
        refererOverride: _refererFor(url),
      );
      if (token.isCancelled || !mounted || bytes == null) return;
      // 快速翻页/滚动后已不在当前屏：放弃本次渲染（结果无处展示）。
      if (!_visiblePageUrls().contains(url)) return;
      final MemoryPipelineResult result = await processBytesInBackground(
        input: bytes,
        config: full
            ? _prefs.motionEffects.toEffectConfig()
            : _prefs.motionEffects.toFastEffectConfig(),
        includeFirstFrame: true,
        cancelToken: token,
        timeout: const Duration(seconds: 90),
        memoryBudgetMb: 256,
      );
      if (token.isCancelled || !mounted) return;
      if (result.gifBytes == null) return;
      _cacheMotionResult(url, result, full: full);
      // 仍在当前屏 → 重建 itemBuilder 叠加动态层。
      if (_visiblePageUrls().contains(url)) {
        setState(() {});
      }
    } on Object {
      // 引擎异常 / 取消：静默回退静态显示。
    } finally {
      if (identical(_motionToken, token)) _motionToken = null;
      if (_motionJobUrl == url) _motionJobUrl = null;
    }
  }

  /// 渲染结果入缓存（LRU：优先逐出不在当前屏的旧条目；逐出时快速版优先于
  /// 完整版，完整版尽量多留）。
  void _cacheMotionResult(String url, MemoryPipelineResult result,
      {required bool full}) {
    _motionCache.remove(url); // 重插入维持「最近使用」序
    while (_motionCache.length >= _motionCacheMax) {
      final Set<String> visible = _visiblePageUrls().toSet();
      String? victim;
      for (final String k in _motionCache.keys) {
        if (!visible.contains(k)) {
          victim = k;
          if (_motionCache[k]!.full) continue; // 快速版优先逐出
          break;
        }
      }
      victim ??= _motionCache.keys.first;
      _motionCache.remove(victim);
    }
    _motionCache[url] = _MotionCacheEntry(result, full);
  }

  /// 互动阅读层是否作用于当前页：开关开、翻页单页、未旋转（未放大已由
  /// [_withPageMotion] 提前回退）；条漫 / gallery / 双页保持旧叠加。
  bool _interactiveReaderActive(int rotation) {
    return _prefs.motionEffects.interactiveReaderEnabled &&
        _prefs.readingMode.isPaged &&
        !_isGalleryMode &&
        !_isDoublePage &&
        rotation == 0;
  }

  /// 中心 / toggle 热区单击转发给当前页互动层；返回 true 表示已消费
  /// （聚焦或收回页面），热区层不再切换 UI。
  bool _handleInteractiveTap(Offset globalPosition) {
    if (_images.isEmpty) return false;
    final int idx = _currentPage.clamp(0, _images.length - 1);
    final InteractivePageLayerState? state =
        _interactiveKeys[_images[idx]]?.currentState;
    if (state == null) return false;
    return state.handleTap(globalPosition);
  }

  /// 叠加页面动态效果：该页渲染结果已就绪、未放大、开关开启时，在静态页
  /// 之上叠加动效层（同 fit / 同旋转 / 同滤镜，与原图显示矩形对齐；
  /// GIF 与原图同宽高比）。互动开关开启且翻页单页时改用
  /// [InteractivePageLayer]（点按聚焦 / 撕开揭示）；否则保持 [MotionGifView]。
  /// IgnorePointer：动效层不拦截任何手势。
  /// Stack 用 passthrough（paged 视口紧约束 / 条漫高度无界均成立），
  /// 叠加层 [Positioned.fill] 随静态页的显示矩形铺满。
  Widget _withPageMotion(String url, int rotation, Widget page) {
    if (!_prefs.motionEffects.enabled || _zoomed) return page;
    final MemoryPipelineResult? result = _motionCache[url]?.result;
    final Uint8List? gif = result?.gifBytes;
    if (result == null || gif == null) return page;
    // 与静态页同 fit；original（BoxFit.none）用 contain 近似
    // （GIF 已按 maxDimension 缩放，原尺寸铺放会缩小显示）。
    final BoxFit fit = switch (_prefs.initialZoom) {
      ReaderInitialZoom.fitWidth => BoxFit.fitWidth,
      ReaderInitialZoom.fitHeight => BoxFit.fitHeight,
      ReaderInitialZoom.original => BoxFit.contain,
    };
    final Widget overlay = _interactiveReaderActive(rotation)
        ? InteractivePageLayer(
            key: _interactiveKeys.putIfAbsent(
              url,
              () => GlobalKey<InteractivePageLayerState>(),
            ),
            gifBytes: gif,
            firstFramePng: result.firstFramePng,
            // 与静态页同宽高比：按渲染尺寸求 contain 显示矩形，
            // 整页格（T0）与静态页严格对齐（含留白）。
            imageSize: Size(
              result.width.toDouble(),
              result.height.toDouble(),
            ),
            fit: fit,
            pauseWhenNotVisible: true,
          )
        : MotionGifView(
            gifBytes: gif,
            firstFramePng: result.firstFramePng,
            fit: fit,
            pauseWhenNotVisible: true,
          );
    final Widget motion = ReaderImageFiltered(
      brightness: _prefs.filterBrightness,
      contrast: _prefs.filterContrast,
      colorTemp: _prefs.filterColorTemp,
      saturation: _prefs.filterSaturation,
      hue: _prefs.filterHue,
      inverted: _prefs.filterInverted,
      grayscale: _prefs.filterGrayscale,
      colorProfile: _prefs.colorProfile,
      // 滚出视口（双页/每屏多图模式）自动静帧省电，滚回恢复。
      child: overlay,
    );
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        page,
        Positioned.fill(
          child: IgnorePointer(
            child: RotatedBox(
              quarterTurns: rotation,
              child: motion,
            ),
          ),
        ),
      ],
    );
  }

  /// 给当前页旋转 90°（quarterTurns +1，模 4）。
  void _rotateCurrentPage() {
    final idx = _currentPage.clamp(0, _images.length - 1);
    final cur = _pageRotations[idx] ?? 0;
    final next = (cur + 1) % 4;
    setState(() {
      _pageRotations[idx] = next;
      // 单页旋转 + rotateLandscape：强制横屏（仅移动形态）。
      if (PlatformService.instance.isMobile &&
          _prefs.rotateLandscape &&
          next != 0) {
        // 与 _applyOrientation 协同：仅当 orientation 为 default/followSystem 时
        // 才临时切横屏，否则尊重用户锁定的方向。
        if (_prefs.orientation == ScreenOrientation.defaultMode ||
            _prefs.orientation == ScreenOrientation.followSystem) {
          try {
            SystemChrome.setPreferredOrientations(<DeviceOrientation>[
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]);
          } on Object {
            // 测试环境忽略。
          }
        }
      }
    });
  }

  /// 屏幕常亮：按 [ReaderPreferences.keepScreenOn] 启用 / 关闭 wakelock。
  void _applyWakelock() {
    try {
      if (_prefs.keepScreenOn) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
    } on Object {
      // 测试环境忽略。
    }
  }

  // ── 时间 / 电量浮层──

  /// 启动时间/电量浮层的定时刷新与电量监听。仅在开启浮层时调用。
  void _initTimeAndBattery() {
    _updateTime();
    _timeTimer?.cancel();
    _timeTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _updateTime(),
    );
    _fetchBatteryLevel();
    _batterySubscription ??= Battery().onBatteryStateChanged.listen(
          (_) => _fetchBatteryLevel(),
          onError: (Object _) {},
        );
  }

  /// 停止时间/电量浮层的定时刷新与电量监听（关闭浮层 / 退出阅读器时调用）。
  void _stopTimeAndBattery() {
    _timeTimer?.cancel();
    _timeTimer = null;
    _batterySubscription?.cancel();
    _batterySubscription = null;
  }

  void _updateTime() {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    if (mounted && _currentTime != '$hour:$minute') {
      setState(() => _currentTime = '$hour:$minute');
    }
  }

  /// battery_plus 6.x：BatteryState 是枚举（无 level 字段），状态变化时重新取电平。
  Future<void> _fetchBatteryLevel() async {
    try {
      final int level = await Battery().batteryLevel;
      if (mounted && level != _batteryLevel) {
        setState(() => _batteryLevel = level);
      }
    } on Object {
      // 部分平台不支持电量，保持 -1（unknown）。
    }
  }

  // ── 系统亮度双轨──

  /// 应用阅读亮度：
  /// - [readerBrightness] > 0：正值写入系统亮度（0.0–1.0）。
  /// - [readerBrightness] < 0：系统亮度压到最低，并叠加黑色遮罩（透明度随 |值|）。
  /// - 0：不干预系统亮度（退出/关闭时由 [_resetBrightness] 恢复）。
  ///
  /// 写入系统亮度是异步 MethodChannel 调用：部分平台/显示器不支持改系统亮度
  /// （如 Windows 报 "Problem setting monitor brightness"），异常在异步阶段抛出，
  /// 外层 try/catch 捕不到、`unawaited` 也不吞——必须 catchError 兜底静默降级
  /// （UI 遮罩仍生效，仅系统亮度不干预），否则成为 Uncaught zone error。
  void _applyBrightness() {
    // 亮度按三层覆盖后的实际生效值应用（设备层可临时覆盖）。
    final double v = _effectivePrefs.readerBrightness;
    if (v == 0.0) {
      _dimBrightnessActive = false;
      if (mounted) setState(() {});
      return;
    }
    try {
      if (v > 0) {
        _dimBrightnessActive = false;
        // 正值：写入系统亮度（失败静默降级）。
        unawaited(_brightnessPlugin
            .setApplicationScreenBrightness(v.clamp(0.0, 1.0))
            .catchError((Object _) {}));
      } else {
        // 负值：压暗系统亮度 + 黑遮罩。
        _dimBrightnessActive = true;
        unawaited(_brightnessPlugin
            .setApplicationScreenBrightness(0.0)
            .catchError((Object _) {}));
      }
      if (mounted) setState(() {});
    } on Object {
      // 同步异常（如插件缺失）同样静默忽略。
    }
  }

  /// 退出阅读器 / 关闭亮度设置时恢复系统原亮度（异步，失败静默忽略）。
  void _resetBrightness() {
    _dimBrightnessActive = false;
    _brightnessPlugin.resetApplicationScreenBrightness().catchError((Object _) {});
  }

  /// 沉浸全屏：进入阅读器时切到 immersiveSticky；dispose 时恢复 edgeToEdge。
  /// 与 [_applyOrientation] 协同：orientation 改 preferredOrientations，不动 system UI mode。
  ///
  /// 桌面端（Windows / Linux / macOS）[SystemChrome] 的 system UI mode 是 no-op，
  /// 永不进入 OS 全屏；故桌面改用 [window_manager] 直接控制窗口全屏（桌面 bug）。
  /// 桌面端设置 OS 全屏的统一入口。
  ///
  /// window_manager 0.3.9 在 Windows 上的 [SetFullScreen] 内部用**阻塞式**
  /// `::SendMessage(mainWindow, WM_SYSCOMMAND, SC_MAXIMIZE, 0)`（退出走 `PostMessage`，
  /// 异步）实现。若在 UI 线程 / 构建帧内**同步**调用，会卡死渲染管道——表现为
  /// 「画面冻住、只能 resize 恢复」（验收 A / D 的冻结根因）。统一用 [Future.delayed]
  /// 推迟到当前事件循环轮次之后执行，彻底避开帧内阻塞调用。
  Future<void> _requestOsFullscreen(bool on) async {
    await Future.delayed(Duration.zero);
    try {
      await WindowService.instance.setFullScreen(on);
      _osFullscreenEntered = on;
    } on Object {
      // 测试 / headless 环境忽略。
    }
  }

  void _applyFullscreen() {
    try {
      if (_isDesktop) {
        // 桌面：真实 OS 全屏（隐藏标题栏 / 任务栏）。调用点：① 设置面板改 fullscreen
        // 开关（[didUpdateWidget]）；② F11 手动触发（[_toggleFullscreen]）。进入阅读器
        // 不再自动全屏（验收），故 [_init] 不调用本方法，避免 window_manager 的
        // setFullScreen 在初始化期同步调用卡死渲染管道。退阅读器时 [dispose] 延迟离开
        // OS 全屏（setFullScreen 与渲染管道竞争，故用 Future.delayed(zero) 推迟到
        // teardown 之后，避开冻结窗口）。
        //
        // 仅在「目标状态 ≠ 当前状态」时才调用 setFullScreen——window_manager 0.3.9
        // 的退出分支无条件做 SetWindowLongPtr + SetWindowPos 窗口样式重建，无谓调用
        // 会触发冻结（A/D）。
        unawaited(_applyDesktopFullscreen(_prefs.fullscreen));
      } else {
        // 移动端：沉浸全屏（隐藏系统栏）/ 恢复系统栏。
        SystemChrome.setEnabledSystemUIMode(
          _prefs.fullscreen
              ? SystemUiMode.immersiveSticky
              : SystemUiMode.edgeToEdge,
        );
      }
    } on Object {
      // 测试环境 / window_manager 不可用时忽略。
    }
  }

  /// 桌面端按需切换 OS 全屏：目标状态与当前一致时不调用 setFullScreen
  /// （避免 window_manager 0.3.9 无谓的窗口样式重建触发冻结）。
  Future<void> _applyDesktopFullscreen(bool want) async {
    try {
      final bool isFs = await WindowService.instance.isFullScreen();
      if (isFs != want) {
        await _requestOsFullscreen(want);
      }
    } on Object {
      // 测试环境忽略。
    }
  }

  /// 键盘快捷键：方向键 / PageUp·Down 翻页，F11 全屏，Esc 关菜单 / 退出全屏，
  /// 空格切换 UI，+/- 缩放，N·P 切换上一话 / 下一话。
  ///
  /// 不依赖 [Focus] 焦点链：通过 [_onGlobalKey] 用 [HardwareKeyboard] 全局监听，
  /// 无论焦点落在按钮 / 设置面板 / 对话框上，快捷键都始终有效（F11/Esc 失效的根治）。
  /// 仅当焦点在文本输入框内时放行（见 [_onGlobalKey] 的 EditableText 豁免）。
  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    // Esc：优先关闭内联设置面板，否则桌面退出 OS 全屏。
    if (key == LogicalKeyboardKey.escape) {
      if (_showInlineSettings) {
        _toggleInlineSettings();
        return KeyEventResult.handled;
      }
      if (_isDesktop) {
        // 仅在确实处于 OS 全屏时才退全屏：未全屏时调用 setFullScreen(false) 也会
        // 做窗口样式重建（SetWindowLongPtr + SetWindowPos，同步），可能触发冻结
        // （A/D 验收「按 Esc 后画面冻住、只能 resize 恢复」的直接根因之一）。
        unawaited(() async {
          try {
            if (await WindowService.instance.isFullScreen()) {
              await _requestOsFullscreen(false);
            }
          } on Object {
            // 测试环境忽略。
          }
        }());
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    // 全屏仅绑 F11：裸 F 键不再触发（与其他阅读器快捷键冲突且与 F11 重复）。
    if (key == LogicalKeyboardKey.f11) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      setState(() => _uiVisible = !_uiVisible);
      return KeyEventResult.handled;
    }
    // Ctrl+方向键 = 跳章：下/右 = 下一章，上/左 = 上一章。
    if (HardwareKeyboard.instance.isControlPressed &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight)) {
      (key == LogicalKeyboardKey.arrowDown ||
              key == LogicalKeyboardKey.arrowRight)
          ? _goNextChapter()
          : _goPrevChapter();
      return KeyEventResult.handled;
    }

    // 放大态方向键语义：方向键先平移（步长 ≈ 视口 1/3），
    // 平移到底后再翻页/滚动。
    final bool zoomed = _zoomController.value.getMaxScaleOnAxis() > 1.001;
    final bool webtoon = _prefs.readingMode.isWebtoon;

    // 方向键 / WASD / 小键盘 2 4 6 8 / PageUp·Down 翻页（条漫模式下走单步滚动）。
    // WASD 与数字小键盘 2468：W/8/上=上一页或向上滚动，S/2/下=下一页或向下滚动；
    // A/D/4/6 在条漫模式忽略、翻页模式横向翻页。
    // 上（W/8/↑/PageUp）。
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.keyW ||
        key == LogicalKeyboardKey.numpad8 ||
        key == LogicalKeyboardKey.pageUp) {
      if (zoomed) {
        _handleZoomedArrow(0, -1, webtoon);
      } else {
        _goPrevPage();
      }
      return KeyEventResult.handled;
    }
    // 下（S/2/↓/PageDown）。
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.keyS ||
        key == LogicalKeyboardKey.numpad2 ||
        key == LogicalKeyboardKey.pageDown) {
      if (zoomed) {
        _handleZoomedArrow(0, 1, webtoon);
      } else {
        _goNextPage();
      }
      return KeyEventResult.handled;
    }
    // 左（A/4/←）：条漫模式忽略 A/4，但 ← 保留（放大态平移 / 未放大翻页）。
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.keyA ||
        key == LogicalKeyboardKey.numpad4) {
      if (webtoon &&
          (key == LogicalKeyboardKey.keyA ||
              key == LogicalKeyboardKey.numpad4)) {
        return KeyEventResult.ignored;
      }
      if (zoomed) {
        _handleZoomedArrow(-1, 0, webtoon);
      } else {
        _goPrevPage();
      }
      return KeyEventResult.handled;
    }
    // 右（D/6/→）：条漫模式忽略 D/6，但 → 保留。
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyD ||
        key == LogicalKeyboardKey.numpad6) {
      if (webtoon &&
          (key == LogicalKeyboardKey.keyD ||
              key == LogicalKeyboardKey.numpad6)) {
        return KeyEventResult.ignored;
      }
      if (zoomed) {
        _handleZoomedArrow(1, 0, webtoon);
      } else {
        _goNextPage();
      }
      return KeyEventResult.handled;
    }
    // N / P 切换下一话 / 上一话。
    if (key == LogicalKeyboardKey.keyN) {
      _goNextChapter();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyP) {
      _goPrevChapter();
      return KeyEventResult.handled;
    }
    // +/- 缩放（以视口中心为锚点，下限 1x）。
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.numpadAdd) {
      _zoomBy(1.25);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      _zoomBy(0.8);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// [HardwareKeyboard] 全局键盘回调（initState 注册 / dispose 移除）。
  ///
  /// 返回 true = 已消费。唯一豁免：当前焦点在文本输入框（[EditableText]）内时不
  /// 拦截，保证内联设置面板里的数值输入仍能用方向键/空格正常编辑。
  bool _onGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    // Esc 始终由阅读器处理（关面板 / 退出全屏），不做输入框豁免——设置面板开着时按
    // Esc 关闭是明确预期；豁免只针对翻页 / 缩放等导航键，避免干扰输入框的方向键 / 空格编辑。
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      // 栈顶有模态层（章节列表 / 对话框 / 右键菜单等 push 的 route）时，Esc 交还
      // Navigator / Shortcuts 关闭模态层——否则本处把 Esc 吞掉（误触发退全屏），
      // 模态层收不到 Esc 关不掉，且未全屏时误触发窗口样式重建（冻结）。
      final Route<dynamic>? route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) {
        return false;
      }
      return _handleKeyEvent(event) == KeyEventResult.handled;
    }
    final FocusNode? focus = FocusManager.instance.primaryFocus;
    if (focus != null &&
        focus.context != null &&
        focus.context!.findAncestorStateOfType<EditableTextState>() != null) {
      return false;
    }
    return _handleKeyEvent(event) == KeyEventResult.handled;
  }

  /// 切换桌面 OS 全屏（F11 触发）。移动端无 window_manager，忽略。
  ///
  /// 切换前固定当前页，切换期间用 [_restoringPage] 屏蔽滚动 / 翻页回写
  /// （onPageChanged 在视口变宽时会把像素偏移对应到别的页，污染 [_currentPage]
  /// 与存档），切换完成、窗口布局稳定后再把视口重锚回该页——进度条不跳页。
  Future<void> _toggleFullscreen() async {
    if (!_isDesktop) return;
    try {
      final isFs = await WindowService.instance.isFullScreen();
      final int savedPage = _currentPage;
      final bool wasRestoring = _restoringPage;
      _restoringPage = true;
      await _requestOsFullscreen(!isFs);
      if (!mounted) return;
      // 等窗口 resize → 引擎布局稳定后再重锚（SetWindowPos 返回后布局可能未完成）。
      await Future<void>.delayed(const Duration(milliseconds: 60));
      if (!mounted) return;
      _restoringPage = wasRestoring;
      _anchorCurrentPage(savedPage);
    } on Object {
      // 测试环境忽略。
    }
  }

  /// 把视口重锚到第 [page] 页：PageView 用 jumpToPage（翻页模式，含双页 ÷2）、
  /// 条漫用 itemScrollController.jumpTo(index, alignment: 0.0)（页顶钉视口顶，
  /// 确定性瞬移，不排队动画，不会回弹）。无布局客户端时静默跳过。
  void _anchorCurrentPage(int page) {
    if (_images.isEmpty) return;
    final int target = page.clamp(0, _images.length - 1);
    if (_prefs.readingMode.isWebtoon) {
      final isc = _itemScrollController;
      if (isc != null && isc.isAttached) {
        // 段式连续模型下 jumpTo 用扁平索引（页索引经 seam 换算）。
        final int flat = _seamActive && _seamItemCount > 0
            ? _seamFlatIndexOf(_chapterIndex, target)
            : target;
        isc.jumpTo(index: flat, alignment: 0.0);
      }
    } else {
      final pc = _pageController;
      if (pc != null && pc.hasClients) {
        pc.jumpToPage(_isDoublePage ? target ~/ 2 : target);
      }
    }
  }

  /// 以视口中心为锚点的相对缩放（键盘 +/- 使用）。下限 minScale，上限 maxScale。
  void _zoomBy(double factor) {
    final m = _zoomController.value;
    final double cur = m.getMaxScaleOnAxis();
    final double newScale =
        (cur * factor).clamp(_prefs.minScale, _prefs.maxScale);
    final double realFactor = newScale / cur;
    if (realFactor == 1.0) return;
    // 键盘锚点取屏幕中心：左上原点输入换算到中心原点（Transform 系）即 (0,0)。
    _zoomController.value = Matrix4.identity()
      ..scaleByDouble(realFactor, realFactor, realFactor, 1.0)
      ..multiply(m);
  }

  /// 双指捏合（屏幕级，[ReaderTapZones.onPinchUpdate] 回调）。以起手矩阵为基准、
  /// 双指中点为锚点，按累计比例 [scaleFactor] 缩放并夹紧到 [minScale, maxScale]。
  /// 根治：手势在覆盖层统一跟踪（不依赖每页 GestureDetector），条漫模式下
  /// 双指落在不同页也能识别缩放。
  Matrix4? _pinchBaseMatrix;

  void _onPinchUpdate(double scaleFactor, Offset focal) {
    _pinchBaseMatrix ??= Matrix4.copy(_zoomController.value);
    final Matrix4 m = _pinchBaseMatrix!;
    final double cur = m.getMaxScaleOnAxis();
    final double target =
        (cur * scaleFactor).clamp(_prefs.minScale, _prefs.maxScale);
    final double realFactor = cur == 0 ? 1.0 : target / cur;
    if (realFactor == 1.0) return;
    final Size vp = MediaQuery.of(context).size;
    // focal 是左上原点（覆盖层 localPosition），换算到中心原点（Transform 系）。
    final Offset c = _toTransformAnchor(focal, vp);
    final double dx = c.dx * (1 - realFactor);
    final double dy = c.dy * (1 - realFactor);
    _zoomController.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0.0, 1.0)
      ..scaleByDouble(realFactor, realFactor, realFactor, 1.0)
      ..multiply(m);
  }

  void _onPinchEnd() {
    _pinchBaseMatrix = null;
  }

  /// 触控板捏合（桌面）：Windows precision touchpad 的捏合手势走
  /// [PointerPanZoomUpdateEvent]（[ReaderTapZones.onTrackpadZoom] 透传），
  /// [scale] 为累计比例、[focal] 为手势焦点——语义与触摸双指捏合完全一致，
  /// 直接复用 [_onPinchUpdate]（以起手矩阵为基准、锚点换算同一套）。
  void _onTrackpadZoom(double scale, Offset focal) {
    _onPinchUpdate(scale, focal);
  }

  /// 触控板双指平移（放大态下平移图片）：增量语义与单指拖动一致，复用 [_onPanUpdate]。
  void _onTrackpadPan(Offset delta) {
    _onPanUpdate(delta);
  }

  /// 放大态单指拖动（屏幕级，[ReaderTapZones.onPanUpdate] 回调）。
  /// 翻页模式：dx/dy 全转矩阵平移（图片在视口内移动）。
  /// 条漫（外层整体 Transform 渲染级缩放）：dx/dy 全转矩阵平移——放大后拖动
  /// 图片上下左右都能动（pan 语义，用户核心诉求）。放大后的滚动浏览由滚轮
  /// 手动滚动承担（见 [_onPointerScroll]）；列表拖动滚动已被放大态 physics
  /// （NeverScrollableScrollPhysics）禁用，故矩阵平移与列表滚动不会同时发生。
  ///
  /// 当前页在 fitWidth 下的真实布局高度（缩放 1 倍时）：用于 [_clampWebtoonZoomMatrix]
  /// 精确夹取纵向平移。依赖 [_realImageDims] 缓存；该页从未加载过则返回 null
  /// （由夹紧函数回退经验值）。
  double? _currentWebtoonContentHeight(Size vp) {
    if (_images.isEmpty) return null;
    final String url = _images[_currentPage.clamp(0, _images.length - 1)];
    final Size? dims = _realImageDims[url];
    if (dims == null || dims.width <= 0) return null;
    return dims.height * vp.width / dims.width;
  }

  /// 放大态边缘滑动切页：平移被边界夹紧（贴边且继续向边外滑）时，
  /// 累计该方向滑动，超过 [_edgeSwipeThreshold] 触发翻页 / 滚动（webtoon 换章），
  /// 与键盘方向键（[_handleZoomedArrow]）语义一致。
  void _onPanUpdate(Offset delta) {
    if (_zoomController.value.getMaxScaleOnAxis() <= 1.001) return;
    if (delta == Offset.zero) return;
    final Size vp = MediaQuery.of(context).size;
    final bool webtoon = _prefs.readingMode.isWebtoon;
    final Matrix4 m = _zoomController.value;
    final double beforeX = m.getTranslation().x;
    final double beforeY = m.getTranslation().y;
    final Matrix4 moved = Matrix4.copy(m)
      ..leftTranslateByDouble(delta.dx, delta.dy, 0.0, 1.0);
    final Matrix4 clamped = webtoon
        ? _clampWebtoonZoomMatrix(moved, vp, _currentWebtoonContentHeight(vp))
        : _clampZoomMatrix(moved, vp);
    _zoomController.value = clamped;
    final double afterX = clamped.getTranslation().x;
    final double afterY = clamped.getTranslation().y;
    final double panX = afterX - beforeX;
    final double panY = afterY - beforeY;
    // 任一轴发生了实际平移 → 用户不处于「贴边向边外滑」状态，清除累计。
    if (panX.abs() > 0.001 || panY.abs() > 0.001) {
      _edgeSwipeAccum = Offset.zero;
      return;
    }
    // 双向均被夹紧（贴边且继续向边外滑）：累计该方向滑动，超过阈值切页。
    _edgeSwipeAccum += delta;
    final double ax = _edgeSwipeAccum.dx.abs();
    final double ay = _edgeSwipeAccum.dy.abs();
    if (ax > _edgeSwipeThreshold || ay > _edgeSwipeThreshold) {
      final int dir = ax > ay
          ? (_edgeSwipeAccum.dx >= 0 ? 1 : -1)
          : (_edgeSwipeAccum.dy >= 0 ? 1 : -1);
      _edgeSwipeAccum = Offset.zero;
      _arrowPageTurn(dir, 0, webtoon);
    }
  }

  /// 放大态边缘滑动累计：贴边后继续向边外滑的累计距离（像素）。
  Offset _edgeSwipeAccum = Offset.zero;

  /// 边缘滑动切页阈值（像素）：超过即触发一次翻页 / 滚动。
  static const double _edgeSwipeThreshold = 56.0;

  /// 放大态方向键：方向键先按方向平移图片（步长 ≈ 视口 1/3），
  /// 平移到底（矩阵被夹紧、位置不再变化）后再翻页 / 滚动——与放大态边缘滑动切页
  /// 语义一致。条漫纵向同样走矩阵平移（与放大态拖动 [_onPanUpdate] 一致）。
  /// [dx]/[dy] 为方向向量（各取 ±1，互斥）。
  void _handleZoomedArrow(int dx, int dy, bool webtoon) {
    if (_zoomController.value.getMaxScaleOnAxis() <= 1.001) {
      _arrowPageTurn(dx, dy, webtoon);
      return;
    }
    final Size vp = MediaQuery.of(context).size;
    final double stepX = vp.width / 3;
    final double stepY = vp.height / 3;
    final Matrix4 m = _zoomController.value;
    final double beforeX = m.getTranslation().x;
    final double beforeY = m.getTranslation().y;
    final Matrix4 moved = Matrix4.copy(m)
      ..leftTranslateByDouble(dx * stepX, dy * stepY, 0.0, 1.0);
    final Matrix4 clamped = webtoon
        ? _clampWebtoonZoomMatrix(moved, vp, _currentWebtoonContentHeight(vp))
        : _clampZoomMatrix(moved, vp);
    _zoomController.value = clamped;
    final double afterX = clamped.getTranslation().x;
    final double afterY = clamped.getTranslation().y;
    final bool panned =
        (afterX - beforeX).abs() > 0.001 || (afterY - beforeY).abs() > 0.001;
    // 平移被夹紧（已到底）→ 翻页 / 滚动；否则仅平移。
    if (!panned) _arrowPageTurn(dx, dy, webtoon);
  }

  /// 放大态方向键平移到底后的翻页 / 滚动方向映射。
  void _arrowPageTurn(int dx, int dy, bool webtoon) {
    final int dir = dx != 0 ? dx : dy;
    if (webtoon) {
      _webtoonStep(dir); // 越界自动换章。
      return;
    }
    dir > 0 ? _goNextPage() : _goPrevPage();
  }

  /// 滚轮 / 触控板滚动（屏幕级，[ReaderTapZones.onPointerSignal] 透传）。
  /// 条漫（webtoon）：滚轮【始终】交还底层 Scrollable 连续滚动——未放大时滚动
  /// 翻页，放大后滚动浏览全部放大图片（验收诉求「从上到下看完整列」）。缩放
  /// 微调由 Ctrl+滚轮 / 双指捏合 / 双击承担。翻页模式按「鼠标滚轮作用」设置
  /// 缩放或翻页。
  void _onPointerScroll(PointerScrollEvent e) {
    // Ctrl+滚轮 = 缩放：Windows 触控板驱动把「捏合缩放手势」映射为 Ctrl+滚轮
    // （系统设置 → 触控板 → 缩放），非 precision 触控板捏合的通用兼容路径（桌面）。
    if (HardwareKeyboard.instance.isControlPressed) {
      // 消费信号：阻止事件继续传给底层 Scrollable（否则缩放的同时列表也滚动）。
      GestureBinding.instance.pointerSignalResolver.register(e, (_) {});
      final double base = e.scrollDelta.dy < 0 ? 1.1 : 0.9;
      final double factor =
          _prefs.scrollWheelInverted ? (base == 1.1 ? 0.9 : 1.1) : base;
      _zoomAroundScreen(e.localPosition, factor);
      return;
    }
    // 条漫（webtoon）：
    // 消费信号并【手动】滚动列表（ScrollOffsetController.animateScroll），以便应用
    // readerScrollSpeed 滚动速度倍率（速度 2.0 → 滚动距离 2 倍）。放大态
    // 列表拖动已被 physics（NeverScrollableScrollPhysics）禁用，原生 Scrollable 收到
    // 滚轮信号会因 shouldAcceptUserOffset=false 直接丢弃（flutter scrollable.dart:955），
    // 故放大态也必须走此手动路径。
    if (_prefs.readingMode.isWebtoon) {
      GestureBinding.instance.pointerSignalResolver.register(e, (_) {});
      final double dy = e.scrollDelta.dy;
      if (dy != 0.0) {
        // ⚠️ duration 必须 > Duration.zero：Flutter 的 DrivenScrollActivity 断言
        // `duration > Duration.zero`，传 zero 会抛 Uncaught zone error（实测崩溃）。
        // 1ms 满足断言且视觉上≈瞬移；滚轮滚动无拖拽竞争，1ms 动画安全（不回弹）。
        // 异常用 catchError 兜底（unawaited 时 try-catch 捕不到 async 阶段的错误）。
        final ScrollOffsetController? soc = _webtoonOffsetController;
        if (soc != null) {
          unawaited(soc
              .animateScroll(
                offset: dy * _prefs.readerScrollSpeed,
                duration: const Duration(milliseconds: 1),
              )
              .catchError((Object _) {}));
        }
      }
      return;
    }
    // 翻页模式：消费信号阻止底层滚动，按「鼠标滚轮作用」设置缩放或翻页。
    GestureBinding.instance.pointerSignalResolver.register(e, (_) {});
    if (_prefs.mouseWheelAction == MouseWheelAction.page) {
      final bool down = e.scrollDelta.dy > 0;
      final bool next = _prefs.scrollWheelInverted ? !down : down;
      next ? _goNextPage() : _goPrevPage();
      return;
    }
    final double base = e.scrollDelta.dy < 0 ? 1.1 : 0.9;
    final double factor =
        _prefs.scrollWheelInverted ? (base == 1.1 ? 0.9 : 1.1) : base;
    _zoomAroundScreen(e.localPosition, factor);
  }

  /// 以屏幕坐标 [focal]（左上原点）为锚点的相对缩放（滚轮使用）。
  void _zoomAroundScreen(Offset focal, double factor) {
    final m = _zoomController.value;
    final double cur = m.getMaxScaleOnAxis();
    final double newScale =
        (cur * factor).clamp(_prefs.minScale, _prefs.maxScale);
    final double realFactor = newScale / cur;
    if (realFactor == 1.0) return;
    final Size vp = MediaQuery.of(context).size;
    final Offset c = _toTransformAnchor(focal, vp);
    final double dx = c.dx * (1 - realFactor);
    final double dy = c.dy * (1 - realFactor);
    _zoomController.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0.0, 1.0)
      ..scaleByDouble(realFactor, realFactor, realFactor, 1.0)
      ..multiply(m);
  }

  /// 左上原点坐标 → 中心原点坐标（Transform alignment:center 坐标系）。
  /// 翻页模式 item ≈ 视口，换算用半视口。
  /// 条漫：纵向平移归零（浏览交给列表滚动，缩放仅以手势焦点为横向锚），
  /// 锚点 y 取 0 即不产生纵向位移，仅横向以手势 x 为锚。
  Offset _toTransformAnchor(Offset focal, Size vp) {
    if (_prefs.readingMode.isWebtoon) {
      return Offset(focal.dx - vp.width / 2, 0);
    }
    return Offset(focal.dx - vp.width / 2, focal.dy - vp.height / 2);
  }

  /// 章内跳页：paged 用 PageController，webtoon 用 ItemScrollController。
  void _jumpToPage(int target) {
    final total = _images.length;
    if (total == 0) return;
    final t = target.clamp(0, total - 1);
    if (_prefs.readingMode.isWebtoon) {
      // 段式连续模型下 jumpTo 用扁平索引（页索引经 seam 换算）。
      final int flat = _seamActive && _seamItemCount > 0
          ? _seamFlatIndexOf(_chapterIndex, t)
          : t;
      _itemScrollController?.jumpTo(
        index: flat,
        alignment: 0.0,
      );
    } else {
      _pageController?.jumpToPage(_isDoublePage ? (t ~/ 2) : t);
    }
    _currentPage = t;
    _saveProgress(t);
    _maybePreload(t);
    if (mounted) setState(() {});
  }

  void _applyOrientation() {
    // 方向锁定只对移动形态有意义；鸿蒙 PC / 桌面不产生系统调用。
    if (!PlatformService.instance.isMobile) return;
    List<DeviceOrientation>? orient;
    switch (_prefs.orientation) {
      case ScreenOrientation.portrait:
      case ScreenOrientation.lockPortrait:
        orient = const <DeviceOrientation>[DeviceOrientation.portraitUp];
      case ScreenOrientation.landscape:
        orient = const <DeviceOrientation>[
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight
        ];
      case ScreenOrientation.lockLandscape:
        orient = const <DeviceOrientation>[DeviceOrientation.landscapeLeft];
      case ScreenOrientation.reversePortrait:
        orient = const <DeviceOrientation>[DeviceOrientation.portraitDown];
      case ScreenOrientation.defaultMode:
      case ScreenOrientation.followSystem:
        orient = const <DeviceOrientation>[];
    }
    try {
      SystemChrome.setPreferredOrientations(orient);
    } on Object {
      // 测试环境忽略。
    }
  }

  // ─────────────────────── 构建 ───────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = _prefs.resolveBackgroundColor(isDark);
    final l10n = AppLocalizations.of(context);

    return ScrollConfiguration(
      // 全局关闭滚动回弹（橡皮筋）与 overscroll 发光，覆盖 PageView / ListView /
      // 设置面板滚动等所有内部滚动组件。
      behavior: _NoOverscrollBehavior(),
      child: Scaffold(
        backgroundColor: bg,
        body: Focus(
          // 键盘快捷键由 HardwareKeyboard 全局监听（见 initState），不再依赖本节点焦点，
          // 故不设 autofocus / onKeyEvent，避免抢焦点干扰设置面板内的输入控件。
          focusNode: _readerFocus,
          child: Stack(
            children: <Widget>[
              _buildContent(l10n),
              if (!_loading && _error == null && _images.isNotEmpty)
                ReaderTapZones(
                  key: _tapZonesKey,
                  layout: _prefs.tapZoneLayout,
                  tapZoneInvert: _prefs.tapZoneInvert,
                  isVertical: _prefs.readingMode.isWebtoon ||
                      _prefs.readingMode == ReadingMode.singleVertical,
                  isWebtoon: _prefs.readingMode.isWebtoon,
                  isRTL: _prefs.readingMode == ReadingMode.singleRTL,
                  onPrev: _goPrevPage,
                  onNext: _goNextPage,
                  onDragPage: (next) => next ? _goNextPage() : _goPrevPage(),
                  // 双击回退（单击即时 + 双击回退）：双击缩放前撤销前一次
                  // 单击已触发的翻页——上次是下一页则回上一页，反之回下一页。
                  onUndoPageTurn: (next) =>
                      next ? _goPrevPage() : _goNextPage(),
                  onToggleUi: () {
                    setState(() => _uiVisible = !_uiVisible);
                  },
                  onZoom: _toggleZoom,
                  onZoomAt: (pos) => _toggleZoom(pos),
                  // 缩放感知：放大态单指单击不触发翻页/导航（手势 bug）。
                  isZoomed: () =>
                      _zoomController.value.getMaxScaleOnAxis() > 1.001,
                  // 手势交互态（Bug3 根治）：scale ≠ 1.0（含放大与缩小）时单指单击不
                  // 派发翻页，避免双击第一击的翻页把 0.5x 缩放态清掉（三态 0.5→2 失效）。
                  isZoomInteractive: () =>
                      (_zoomController.value.getMaxScaleOnAxis() - 1.0).abs() >
                      0.001,
                  // 屏幕级捏合（根治）：覆盖层统一跟踪双指，条漫跨页也生效。
                  onPinchUpdate: _onPinchUpdate,
                  onPinchEnd: _onPinchEnd,
                  // 放大态单指平移。
                  onPanUpdate: _onPanUpdate,
                  // 滚轮 / 触控板滚动（缩放或翻页）。
                  onPointerSignal: _onPointerScroll,
                  // 触控板捏合 / 双指平移（桌面：precision touchpad 独立事件流）。
                  onTrackpadZoom: _onTrackpadZoom,
                  onTrackpadPan: _onTrackpadPan,
                  // 桌面右键：弹出图片操作菜单（保存 / 分享 / 设封面），与长按同款。
                  onSecondaryTap: (_images.isEmpty)
                      ? null
                      : () => showReaderImageActions(
                            context: context,
                            url: _images[
                                _currentPage.clamp(0, _images.length - 1)],
                            source: _source,
                            referer: _refererFor(_images[
                                _currentPage.clamp(0, _images.length - 1)]),
                            comicId: widget.comicId,
                            sourceType: SourceType.mangaSource,
                            onBookmarkChapter: _toggleChapterBookmarkFromMenu,
                            onFavoriteImage: _toggleCurrentPageImageFavorite,
                            onToggleTranslation: _toggleCurrentPageTranslation,
                            translationEnabled: _prefs.translationEnabled,
                          ),
                  onTapIntercept: () {
                    if (_showInlineSettings) {
                      _toggleInlineSettings();
                      return true;
                    }
                    return false;
                  },
                  // 互动阅读层：中心点按聚焦 / 收回页面；未命中返回 false，
                  // 照常切换 UI。
                  onTapAt: _handleInteractiveTap,
                  onLongPress: (_images.isEmpty ||
                          !_prefs.showLongPressMenu ||
                          _prefs.enableLongPressToZoom)
                      ? null
                      : () {
                          AppHaptics.thunk(); // MD3「Thunk」：长按呼出图片操作菜单。
                          showReaderImageActions(
                            context: context,
                            url: _images[
                                _currentPage.clamp(0, _images.length - 1)],
                            source: _source,
                            referer: _refererFor(_images[
                                _currentPage.clamp(0, _images.length - 1)]),
                            comicId: widget.comicId,
                            sourceType: SourceType.mangaSource,
                            onBookmarkChapter: _toggleChapterBookmarkFromMenu,
                            onFavoriteImage: _toggleCurrentPageImageFavorite,
                            onToggleTranslation: _toggleCurrentPageTranslation,
                            translationEnabled: _prefs.translationEnabled,
                          );
                        },
                  // 长按缩放：开启时长按定点放大 1.75x、松手恢复；
                  // 关闭时由上方 onLongPress 保持「长按弹菜单」行为。
                  onLongPressAt:
                      _prefs.enableLongPressToZoom ? _enterLongPressZoom : null,
                  onLongPressRelease:
                      _prefs.enableLongPressToZoom ? _exitLongPressZoom : null,
                  // 控制栏区域保护：点在顶部/底部控制栏上时交给按钮自身处理，不触发翻页。
                  isToolbarRegion: (pos) => _isInToolbarRegion(pos),
                ),
              // 缩放比例指示（放大 >1.001 时顶部居中显示当前倍数，1.2s 后淡出）。
              // 自包含监听 [_zoomController]（ValueListenableBuilder 只重建徽标本体，
              // 不触发整屏 setState）。
              if (_images.isNotEmpty)
                Positioned(
                  top: MediaQuery.paddingOf(context).top + AppTokens.spaceLg,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: _ZoomFactorBadge(controller: _zoomController),
                    ),
                  ),
                ),
              if (_flashLayerActive)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: _flashColor.withValues(alpha: _flashOpacity),
                    ),
                  ),
                ),
              if (_transitionVisible)
                Center(
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _transitionVisible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Card(
                        color: Colors.black54,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          child: Text(
                            _transitionTitle,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 18),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // 条漫跳章过渡横幅已移除（2026-08-20）：滚到章末由「直接自动连读」
              // 取代（见 _onWebtoonScroll），不再需要点击/延时确认。
              if (_uiVisible)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _buildTopBar(l10n, bg),
                ),
              if (_uiVisible)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _buildBottomBar(l10n),
                ),
              if (_uiVisible && _prefs.progressBarOnRight && _images.isNotEmpty)
                _buildRightProgressBar(l10n),
              if (_uiVisible && _prefs.showClockBattery)
                _buildClockBatteryOverlay(l10n),
              // 章节导航滑块：ui 可见 + 设置开启时显示，拖动预览章节。
              if (_uiVisible &&
                  !_isLocalMode &&
                  _effectivePrefs.showChapterSlider)
                _buildChapterSlider(l10n),
              // 章节导航滑块预览浮层：拖动时在顶部预览章节标题。
              if (_uiVisible && _sliderPreviewChapter != null)
                Positioned(
                  top: 40,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: Card(
                        color: Colors.black54,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          child: Text(
                            _sliderPreviewChapter! < widget.chapters.length
                                ? widget.chapters[_sliderPreviewChapter!].title
                                : '',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_showInlineSettings) _buildInlineSettings(l10n),
              // 亮度双轨的负值遮罩：压暗系统亮度到最低后叠加黑遮罩，
              // 透明度随 |readerBrightness|。置于最上层使整个阅读区域一起变暗，
              // 拖动滑块时即时生效；IgnorePointer 不拦截点击/翻页。
              if (_dimBrightnessActive && _effectivePrefs.readerBrightness < 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: Colors.black.withValues(
                        alpha:
                            (-_effectivePrefs.readerBrightness).clamp(0.0, 1.0),
                      ),
                    ),
                  ),
                ),
              // 夜览暖色盖层（亮度双轨扩展）：独立于
              // [readerBrightness] 的暖色（纸感 0xFF2A1800）半透明覆盖，减少蓝光，
              // 不干预系统亮度；可与负值黑遮罩叠加（偏色 + 压暗）。
              if (_effectivePrefs.nightLightEnabled)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: ReaderTokens.nightLightColor.withValues(
                        alpha:
                            _effectivePrefs.nightLightOpacity.clamp(0.0, 1.0),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────── 内联设置面板 ───────────────────────

  /// 与小说阅读器对齐的内联设置面板：桌面（宽 ≥ [AppTokens.desktopBreakpoint]）
  /// 停靠右侧、移动端停靠底部。点阅读区任意处关闭（见 [ReaderTapZones.onTapIntercept]）。
  Widget _buildInlineSettings(AppLocalizations l10n) {
    final isDesktop =
        MediaQuery.sizeOf(context).width >= AppTokens.desktopBreakpoint;

    final panel = Material(
      elevation: 0,
      // 面板外壳 = 中性表面色（不带强调染色）；强调色只留给面板内的卡片。
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: buildComicSettingsSheet(
        initial: _prefs,
        // 三层覆盖：内联面板即时预览写入设备/会话层（不落盘），
        // 关闭面板时 [_commitDeviceOverride] 提交到作品层持久化。
        onChanged: _applyDeviceOverride,
        onClose: () {
          unawaited(_commitDeviceOverride());
          _toggleInlineSettings();
        },
        // 睡眠定时：会话级状态回显 + 选择回调（阅读器持有 Timer 生命周期）。
        sleepTimer: _sleepTimerState,
        onSleepTimerChanged: _applySleepTimer,
      ),
    );

    if (isDesktop) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: panel,
        ),
      );
    }
    return Align(
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        heightFactor: 0.55,
        child: panel,
      ),
    );
  }

  Widget _buildContent(AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: AppLoadingIndicator());
    }
    // useWebview 脚本源：需先抓取渲染后 HTML 才能解析图片（见 _captureAndRetry）。
    if (_htmlCaptureRequest != null) {
      return _CenterMessage(
        icon: Icons.cloud_download_rounded,
        message: l10n.captureHint,
        onRetry: _captureAndRetry,
      );
    }
    if (_error != null) {
      return _CenterMessage(
        icon: Icons.error_rounded,
        message: _isLocalMode ? l10n.localFileLoadFailed : l10n.loadFailed,
        onRetry: _isLocalMode
            ? () => _loadLocalImages(restorePage: _currentPage)
            : () => _loadChapter(_chapterIndex, restorePage: _currentPage),
      );
    }
    if (_images.isEmpty) {
      return _CenterMessage(
          icon: Icons.image_not_supported_rounded, message: l10n.noImages);
    }
    if (_prefs.readingMode.isWebtoon) return _buildWebtoon();
    final Widget paged = _buildPaged();
    // 翻页过渡动画（fade）：用 AnimatedOpacity 驱动整页淡入（见 [_runPageFade]）。
    if (_prefs.pageAnimation == ReaderPageAnimation.fade) {
      return AnimatedOpacity(
        opacity: _pageFadeOpacity,
        duration: const Duration(milliseconds: 120),
        child: paged,
      );
    }
    return paged;
  }

  /// 双页并排是否生效：仅横排单页模式（LTR/RTL）支持。
  /// 竖排 / 长条模式下「双页拆分」开关会被自动关闭（见设置面板 _buildReadingMode /
  /// _buildSplitDoublePage 的联动），以保证开关始终「有作用」。
  /// 「宽屏自动双页」在横屏且宽度达桌面断点（平板横屏 / 桌面宽窗口）时
  /// 自动启用跨页；竖排 / 长条模式不参与。
  bool get _isDoublePage {
    if (_prefs.readingMode != ReadingMode.singleLTR &&
        _prefs.readingMode != ReadingMode.singleRTL) {
      return false;
    }
    if (_prefs.splitDoublePage) return true;
    if (!_prefs.autoDoublePageOnWide) return false;
    final Size size = MediaQuery.sizeOf(context);
    return size.width > size.height &&
        size.width >= AppTokens.desktopBreakpoint;
  }

  /// 首屏单图：双页模式【第一章】首页单独显示，其后恢复双页。
  /// 仅首章生效：进度条 / 跨页映射（[_doublePageSpreadFor] / [_doublePageLeftPageFor]）
  /// 均按「每章首页为常规跨页」设计，扩展到其它章会造成进度条与跨页计数错位。
  bool get _showFirstPageSingle =>
      _prefs.showSingleImageOnFirstPage && _chapterIndex == 0 && _isDoublePage;

  /// 逻辑单页 → 跨页序号（首屏单图映射）。
  ///
  /// 常规双页：spread = page ~/ 2。首屏单图生效时：第 0 页独占 spread 0，
  /// 其后 spread k（k≥1）承载 (2k-1, 2k) 两页 → page≥1 时 spread = (page+1) ~/ 2。
  int _doublePageSpreadFor(int page) {
    if (!_showFirstPageSingle) return page ~/ 2;
    if (page <= 0) return 0;
    return (page + 1) ~/ 2;
  }

  /// 跨页序号 → 逻辑左页（首屏单图映射）。
  ///
  /// 常规双页：left = spread * 2。首屏单图：spread 0 → 0，spread k（k≥1）→ 2k-1。
  int _doublePageLeftPageFor(int spread) {
    if (!_showFirstPageSingle) return spread * 2;
    if (spread <= 0) return 0;
    return spread * 2 - 1;
  }

  /// 每屏多图 gallery：按当前屏幕方向取竖/横每屏图片数（1–5）。
  /// 测试/无 MediaQuery 环境按竖屏处理。
  int get _galleryCount {
    final MediaQueryData? mq = MediaQuery.maybeOf(context);
    final bool portrait = mq == null || mq.orientation == Orientation.portrait;
    final int n = portrait
        ? _prefs.readerScreenPicNumberForPortrait
        : _prefs.readerScreenPicNumberForLandscape;
    return n.clamp(1, 5);
  }

  /// 每屏多图 gallery 是否生效：paged 模式且每屏图片数 > 1。
  /// 与双页拆分并存时 gallery 优先（见）。
  bool get _isGalleryMode => _prefs.readingMode.isPaged && _galleryCount > 1;

  /// 跨页（spread）数量：双页模式下 PageView 的 itemCount。
  /// 首屏单图生效时，第一页独占一个跨页，其后恢复双页布局。
  int get _spreadCount {
    final int len = _images.length;
    if (_showFirstPageSingle) {
      return len <= 1 ? 1 : 1 + ((len - 1) / 2).ceil();
    }
    return (len / 2).ceil();
  }

  /// 左右留白像素值（sideMargin 占屏宽比例 → 实际像素）。
  double get _sideMarginPx =>
      _prefs.sideMargin * MediaQuery.of(context).size.width;

  /// 跨页（spread）数量：双页模式下 PageView 的 itemCount。
  /// paged 段式连续模型（章末过渡卡）在章末多计 1 页（见 [_showPagedNextCard]）。
  int get _controllerPageCount {
    final int base;
    if (_isGalleryMode) {
      base = (_images.length / _galleryCount).ceil();
    } else if (_isDoublePage) {
      base = _spreadCount;
    } else {
      base = _images.length;
    }
    return base + (_showPagedNextCard ? 1 : 0);
  }

  Widget _buildPaged() {
    if (_isGalleryMode) return _buildPagedGallery();
    if (_isDoublePage) return _buildPagedSpread();
    final pc = _pageController;
    if (pc == null) return const SizedBox.shrink();
    return PageView.builder(
      // 每章独立 Key：确保切章时 PageView 重建为全新 ScrollPosition，
      // 使 PageController 的 initialPage 必定生效，避免图片停在旧页 / 回弹。
      key: ValueKey<int>(_chapterIndex),
      controller: pc,
      // 拖拽翻页统一由覆盖层 ReaderTapZones 的 onDragPage 处理（桌面鼠标拖拽 /
      // 触屏滑动都走这条），故此处禁用 PageView 原生拖拽，避免「两次翻页」冲突。
      // 程序化翻页（_goNextPage / _pageController.animateToPage / 点按热区 / 滚轮）
      // 不受影响。放大时同理禁用，交给图片自身平移。
      physics: const NeverScrollableScrollPhysics(),
      scrollDirection: _prefs.readingMode == ReadingMode.singleVertical
          ? Axis.vertical
          : Axis.horizontal,
      reverse: _prefs.readingMode == ReadingMode.singleRTL,
      // 章末多出的过渡卡页计入 itemCount（见 [_showPagedNextCard]）。
      itemCount: _controllerPageCount,
      itemBuilder: (ctx, i) {
        // paged 段式连续模型（章末过渡卡）：最后多出的一页渲染「下一章」过渡卡。
        if (_showPagedNextCard && i >= _images.length) {
          return _buildPagedNextCard();
        }
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: _sideMarginPx),
          child: _withPageMotion(
            _images[i],
            _pageRotations[i] ?? 0,
            MangaPageImage(
              url: _images[i],
              prefs: _prefs,
              zoomController: _zoomController,
              source: _source,
              refererResolver: _refererFor,
              rotationQuarterTurns: _pageRotations[i] ?? 0,
              cropEdge: _prefs.cropEdge,
              translation: _translation,
              translationRetry: _translationRetryPage,
            ),
          ),
        );
      },
    );
  }

  /// 每屏多图 gallery：paged 模式下每屏纵向堆叠 N 张图（1–5）。
  ///
  /// 每屏 = 一个 PageView 页，翻页以屏为单位。标记进度时取当前屏首图索引。
  /// 与双页拆分并存时 gallery 优先。图片按屏高等比压缩（Column + Expanded）。
  Widget _buildPagedGallery() {
    final pc = _pageController;
    if (pc == null) return const SizedBox.shrink();
    final int n = _galleryCount;
    final int screenCount = _controllerPageCount - (_showPagedNextCard ? 1 : 0);
    return PageView.builder(
      key: ValueKey<String>('gallery-$_chapterIndex'),
      controller: pc,
      physics: const NeverScrollableScrollPhysics(),
      scrollDirection: Axis.vertical,
      itemCount: _controllerPageCount,
      itemBuilder: (ctx, screenIdx) {
        // 章末过渡卡
        if (_showPagedNextCard && screenIdx >= screenCount) {
          return _buildPagedNextCard();
        }
        final int start = screenIdx * n;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: _sideMarginPx),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = start; i < start + n && i < _images.length; i++)
                Expanded(
                  child: _withPageMotion(
                    _images[i],
                    _pageRotations[i] ?? 0,
                    MangaPageImage(
                      url: _images[i],
                      prefs: _prefs,
                      source: _source,
                      refererResolver: _refererFor,
                      rotationQuarterTurns: _pageRotations[i] ?? 0,
                      cropEdge: _prefs.cropEdge,
                      translation: _translation,
                      translationRetry: _translationRetryPage,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 双页并排：仅在 splitDoublePage 且横排单页模式（singleLTR/singleRTL）下使用。
  /// PageController 以「跨页(spread)」为单位，每屏展示两页；[_currentPage] 仍记录逻辑单页索引（取当前跨页的首页）。
  /// paged 段式连续模型（章末过渡卡）在章末多计 1 页（见 [_showPagedNextCard]）。
  Widget _buildPagedSpread() {
    final pc = _pageController;
    if (pc == null) return const SizedBox.shrink();
    final rtl = _prefs.readingMode == ReadingMode.singleRTL;
    return PageView.builder(
      // 每章独立 Key：双页模式同样需要确保切章时 PageView 重建为全新 ScrollPosition。
      key: ValueKey<String>('spread-$_chapterIndex'),
      controller: pc,
      // 拖拽翻页统一由覆盖层处理，禁用 PageView 原生拖拽（避免两次翻页冲突）。
      physics: const NeverScrollableScrollPhysics(),
      scrollDirection: Axis.horizontal,
      reverse: rtl,
      itemCount: _controllerPageCount,
      itemBuilder: (ctx, spreadIdx) {
        // paged 段式连续模型（章末过渡卡）：跨页数之后多出的一页渲染「下一章」过渡卡。
        if (_showPagedNextCard && spreadIdx >= _spreadCount) {
          return _buildPagedNextCard();
        }
        // 首屏单图：第一跨页只放第 0 页，其后恢复双页。
        final bool firstSingle = _showFirstPageSingle && spreadIdx == 0;
        // 跨页左页索引统一经 _doublePageLeftPageFor 计算：首屏单图关闭时
        // spread 0 左页为 0（旧手写 `spreadIdx * 2 - 1` 在此时算出 -1 →
        // `_images[-1]` RangeError 崩溃），开启时 spread 0 为 0、其后为 2k-1。
        final int a = _doublePageLeftPageFor(spreadIdx);
        final int b = a + 1;
        final aImg = _images[a];
        final bImg = !firstSingle && b < _images.length ? _images[b] : null;
        final List<Widget> rowChildren = <Widget>[
          Expanded(
            child: _withPageMotion(
              aImg,
              _pageRotations[a] ?? 0,
              MangaPageImage(
                url: aImg,
                prefs: _prefs,
                zoomController: _zoomController,
                source: _source,
                refererResolver: _refererFor,
                rotationQuarterTurns: _pageRotations[a] ?? 0,
                cropEdge: _prefs.cropEdge,
                translation: _translation,
                translationRetry: _translationRetryPage,
              ),
            ),
          ),
        ];
        if (bImg != null) {
          rowChildren.add(
            Expanded(
              child: _withPageMotion(
                bImg,
                _pageRotations[b] ?? 0,
                MangaPageImage(
                  url: bImg,
                  prefs: _prefs,
                  zoomController: _zoomController,
                  source: _source,
                  refererResolver: _refererFor,
                  rotationQuarterTurns: _pageRotations[b] ?? 0,
                  cropEdge: _prefs.cropEdge,
                  translation: _translation,
                  translationRetry: _translationRetryPage,
                ),
              ),
            ),
          );
        }
        // RTL 阅读顺序为右→左：跨页内两页交换位置（单页奇数尾页不变）。
        if (rtl && rowChildren.length > 1) {
          rowChildren.insert(0, rowChildren.removeLast());
        }
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: _sideMarginPx),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rowChildren,
          ),
        );
      },
    );
  }

  /// paged 段式连续模型（跨章无缝续读 · paged 分支）的「章末过渡卡」页。
  ///
  /// 展示「下一章」标题 + 继续提示；越过该卡（末页再翻一页 / 下一张按钮）即无缝
  /// 进入下一章首页（见 [_goNextPage] / [_goNextChapter]，经 [_pagedAdvance] 重锚）。
  Widget _buildPagedNextCard() {
    final l10n = AppLocalizations.of(context);
    final int nextIndex = _chapterIndex + 1;
    final String? nextTitle = nextIndex < widget.chapters.length
        ? widget.chapters[nextIndex].title
        : null;
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = _prefs.resolveBackgroundColor(dark);
    final Color fg = dark ? Colors.white70 : Colors.black54;
    final Color line = dark ? Colors.white24 : Colors.black26;
    final String label = nextTitle == null || nextTitle.isEmpty
        ? l10n.chapterN(nextIndex + 1)
        : '${l10n.chapterN(nextIndex + 1)} · $nextTitle';
    // 下一章首图预览：已预载时取首图缩略图；未预载则不显示。
    final List<String> nextImgs = _preload[nextIndex] ?? const <String>[];
    final String? nextPreviewUrl = nextImgs.isNotEmpty ? nextImgs.first : null;
    // 章节评论入口：源声明 comments 段时提供「评论」按钮。
    final bool hasComments = !_isLocalMode && _source?.comments != null;
    return Container(
      color: bg,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.menu_book_rounded, color: fg, size: 40),
            const SizedBox(height: 16),
            Text(
              l10n.nextChapter,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: fg,
                fontSize: 14,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: fg,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (nextPreviewUrl != null) ...<Widget>[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                child: SizedBox(
                  height: 140,
                  child: SourceImage(
                    url: nextPreviewUrl,
                    source: _source,
                    refererOverride: _refererFor(nextPreviewUrl),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            // 下一章按钮：点击无缝进入下一章首页。
            InkWell(
              onTap: _goNextChapter,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  l10n.continueReading,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            if (hasComments) ...<Widget>[
              const SizedBox(height: 12),
              // 章节评论入口：弹层内嵌评论区（复用 CommentSection）。
              OutlinedButton.icon(
                onPressed: () => _showChapterComments(
                  l10n,
                  nextIndex < widget.chapters.length
                      ? widget.chapters[nextIndex].id
                      : widget.chapters[_chapterIndex].id,
                ),
                icon: const Icon(Icons.chat_bubble_rounded, size: 16),
                label: Text(l10n.comments),
                style: OutlinedButton.styleFrom(
                  foregroundColor: fg,
                  side: BorderSide(color: line),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 章节评论弹层：源支持章节评论时，以底部弹层内嵌评论区。
  void _showChapterComments(AppLocalizations l10n, String chapterId) {
    final PluginConfig? source = _source;
    if (source == null || source.comments == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (BuildContext _, ScrollController scrollController) =>
            CommentSection(
          source: source,
          contentId: chapterId,
          service: const CommentApiService(),
        ),
      ),
    );
  }

  Widget _buildWebtoon() {
    final isc = _itemScrollController;
    final ipl = _itemPositionsListener;
    if (isc == null || ipl == null) return const SizedBox.shrink();
    // 页间距：优先采用可调的 readerPageSpacing（0–50px，0=不设），
    // 未设时回退 webtoonWithGap 预设间距；普通条漫（webtoon）默认 0 无缝拼接。
    final double gap;
    if (_prefs.readerPageSpacing > 0) {
      gap = _prefs.readerPageSpacing.toDouble();
    } else if (_prefs.readingMode == ReadingMode.webtoonWithGap) {
      gap = AppTokens.spaceMd;
    } else {
      gap = 0.0;
    }
    // 恢复标记消费后回退到 _currentPage（二者在进入本章首帧时一致），避免后续
    // 重建时把 initialScrollIndex 误置 0；didUpdateWidget 虽不重应用该值，仍保持稳健。
    // 段式连续模型（跨章无缝续读）：扁平列表的 initialScrollIndex 是全局
    // 扁平索引（页索引需经 [_seamFlatIndexOf] 换算，前插上一段后不再等于页索引）。
    final int restorePage = _pendingWebtoonRestore ?? _currentPage;
    final restoreIndex = _seamActive && _seamItemCount > 0
        ? _seamFlatIndexOf(_chapterIndex, restorePage)
        : restorePage;
    // keep 无缝重锚写入的首帧对齐系数：一次性消费——仅切章换 key 重建 SPL 的
    // 那一帧需要它，同 key 的后续 rebuild 不会重读 initialAlignment。
    final double restoreAlign = _pendingWebtoonInitialAlignment ?? 0.0;
    _pendingWebtoonInitialAlignment = null;
    // 一次性恢复：仅在本章首次渲染时（_pendingWebtoonRestore 非空）锁定当前页并解除
    // 写盘屏蔽。监听器已在 _setupControllers 注册，此处不再重复添加（避免每次
    // setState 重注册导致重复回调）。恢复标记在此消费，后续重建不再触发。
    if (_pendingWebtoonRestore != null) {
      final target = _pendingWebtoonRestore!;
      final bool toLast = _pendingWebtoonScrollToLast;
      _pendingWebtoonRestore = null;
      _pendingWebtoonScrollToLast = false;
      final int token = _loadSession.current;
      // 进度条即时对齐「即将到达的页」：回到上一话时目标是末页，若沿用 target(=0)
      // 会让整个恢复期（等图加载 + 滚动收尾，约 1~3s）的页码停在第一页，收尾时才
      // 突然跳到末页。此处在 build 期内直接赋值（同帧生效，不触发额外重建），
      // restoreIndex 已于上方取值，不受影响。
      final int expectPage = _images.isEmpty ? 0 : _images.length - 1;
      _currentPage = (toLast ? expectPage : target).clamp(0, expectPage);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_loadSession.isValid(token)) return;
        final int last = _images.isEmpty ? 0 : _images.length - 1;
        if (toLast && last > 0 && isc.isAttached) {
          // 「回到上一话末页」的两段式落点：
          // 阶段 1：等列表里出现真实尺寸的图（图片开始加载）后，先 jumpTo(末页) 把视口
          // 跳到底部。ScrollablePositionedList 在目标未构建时走「双列表切换」按索引
          // 锚定，落点准；之后列表被夹在底部，图片陆续加载使整章变高，滚位移自动跟随到底。
          // 阶段 2：持续轮询「列表最大滚动范围 maxScrollExtent」（由滚动通知实时捕获）
          // 是否稳定——连续多次不变即整章图片已加载完、高度不再增长——再精确滚到底收尾。
          // 此信号直接反映整章内容高度，不受「末项在视口外未被构建」影响，比盯末项边缘可靠。
          // 全程 _restoringPage 保持为 true，中途图片加载的位置抖动不回写，故不回弹。
          // 加 3s 超时兜底，慢网/图片加载失败也不卡死。
          final int lastIdx = last;
          // 段式连续模型下 jumpTo 用扁平索引：末页页索引经 seam 换算（前插上一段后偏移）。
          final int lastFlat = _seamActive && _seamItemCount > 0
              ? _seamFlatIndexOf(_chapterIndex, lastIdx)
              : lastIdx;
          _webtoonPhaseJumped = false;
          _webtoonMaxExtent = null;
          _webtoonPrevExtent = null;
          _webtoonExtentStableCount = 0;
          _webtoonLastPageTimer?.cancel();
          _webtoonLastPageTimer = Timer.periodic(
            const Duration(milliseconds: 80),
            (timer) {
              if (!mounted || !_loadSession.isValid(token)) {
                timer.cancel();
                _webtoonLastPageTimer = null;
                _webtoonLastPageTimeout?.cancel();
                _webtoonLastPageTimeout = null;
                return;
              }
              final positions = ipl.itemPositions.value;
              // 占位期（图片未加载，全是占位小高度）不动作：避免拿「缩成一屏」的假布局去跳。
              // 继续等图片开始加载（列表里出现真实尺寸的图）。
              if (!_hasRealSizedItem(positions)) return;
              if (!_webtoonPhaseJumped) {
                // 阶段 1：把视口瞬移到底部（即时 jumpTo，无动画、不引入回弹）。列表被夹底，
                // 随图片加载内容变高、滚位移自动跟随到底。
                _webtoonPhaseJumped = true;
                isc.jumpTo(index: lastFlat, alignment: 0.0);
                return;
              }
              // 阶段 2：等 maxScrollExtent 连续多次不变（整章高度稳定）再收尾。
              final double? ext = _webtoonMaxExtent;
              if (ext == null) return; // 尚未捕获到滚动范围（极端时序），再等等。
              if (_webtoonPrevExtent != null &&
                  (ext - _webtoonPrevExtent!).abs() < 1.0) {
                _webtoonExtentStableCount += 1;
              } else {
                _webtoonExtentStableCount = 0;
                // 高度仍在增长：用即时 jumpTo 把锚点重新钉在末页，确保视口不被上方
                // 陆续加载的图片顶走。收尾时再补差到「末页底边贴视口底」。
                isc.jumpTo(index: lastFlat, alignment: 0.0);
              }
              _webtoonPrevExtent = ext;
              // 需连续 8 次（约 640ms）不变才认定稳定：图片是分批解码的，批与批之间
              // 常有 300~800ms 空隙，阈值过小会落在空隙里「假稳」而提前收尾。
              if (_webtoonExtentStableCount >= 8) {
                // 整章已稳定：取消轮询与超时，精确滚到底并收尾。
                timer.cancel();
                _webtoonLastPageTimer = null;
                _webtoonLastPageTimeout?.cancel();
                _webtoonLastPageTimeout = null;
                _scrollToWebtoonLast(lastIdx, token);
              }
            },
          );
          // 超时兜底：3s 内未稳定也强制滚动收尾，绝不卡死。
          _webtoonLastPageTimeout?.cancel();
          _webtoonLastPageTimeout = Timer(const Duration(seconds: 3), () {
            _webtoonLastPageTimeout = null;
            if (!mounted || !_loadSession.isValid(token)) return;
            if (_webtoonLastPageTimer == null) return; // 已稳定并滚动，无需兜底。
            _webtoonLastPageTimer?.cancel();
            _webtoonLastPageTimer = null;
            _scrollToWebtoonLast(lastIdx, token);
          });
          return;
        }
        // initialScrollIndex 已在首帧把目标页顶边对齐到视口顶部（末页则夹到最大滚动、
        // 即底部对齐，属标准章末行为），无需再 scrollTo（避免引入额外动画/回弹）。
        // 此处仅同步进度变量并解除屏蔽，此后滚动通知才是用户真实翻页。
        _currentPage = (toLast ? last : target).clamp(0, last);
        // 解除进度回写/存档屏蔽：从此滚动通知才是用户真实翻页。
        _restoringPage = false;
        setState(() {});
      });
    }
    return NotificationListener<ScrollNotification>(
      // 边界拖拽换章：手指在列表顶端/末端继续拖动时，滚动位置被夹紧，多余位移会
      // 以 overscroll 上报。累计超过阈值即换章 —— 这是连续滚动阅读的标准手势，
      // 让换章彻底摆脱对「当前页」测量值的依赖。
      onNotification: _handleWebtoonScrollNotification,
      child: _buildWebtoonList(isc, ipl, restoreIndex, gap, restoreAlign),
    );
  }

  /// 回到上一话末页时，把条漫列表滚动到底（末页底边对齐视口底）并收尾。
  /// [last] 为末页下标，[token] 为本次加载令牌，用于竞态时放弃。整个过程
  /// _restoringPage 保持为 true，收尾时才把当前页赋成末页并解除屏蔽，避免回弹。
  void _scrollToWebtoonLast(int last, int token) {
    final isc = _itemScrollController;
    if (isc == null || !isc.isAttached) {
      // 列表已卸载：直接收尾，不滚动（极端竞态下不会卡死）。
      _finishWebtoonRestore(last, token);
      return;
    }
    // 段式连续模型下 jumpTo / positions 比较均用扁平索引（末页页索引经 seam 换算），
    // 收尾仍以页索引 [last] 为准。
    final int flat = _seamActive && _seamItemCount > 0
        ? _seamFlatIndexOf(_chapterIndex, last)
        : last;
    // 落点方案：用「按项对齐 + 直接计算对齐系数」一次性精确落末页，不做像素级动画。
    // 列表内部以「视口锚点 anchor + 居中 sliver」实现跳转：jumpTo(index, A) 会把
    // index 项的**顶边**放在视口 A 比例处（A=0 视口顶、A=1 视口底）。此前 alignment:1.0
    // 把末页顶边推到视口底、整页被推到屏外，才出现「倒数第二页」；而「末页底贴视口底」
    // 需要 A = 1 − 末页高/视口高——长条漫下 A 为负，但 UnboundedCustomScrollView
    // 支持无界 anchor，负值即把末页顶边推到视口上方、底贴底，是合法的章末终态。
    // 用 jumpTo 而非 animateScroll：jumpTo 是确定性瞬移（无动画、无帧回调排队），
    // 彻底避免「恢复未完成用户就滚动」时活跃动画与拖拽打架产生的回弹。
    isc.jumpTo(index: flat, alignment: 0.0);
    _webtoonRestoreTimer?.cancel();
    int corrections = 0;
    _webtoonRestoreTimer = Timer.periodic(const Duration(milliseconds: 80), (
      timer,
    ) {
      if (!mounted || !_loadSession.isValid(token)) {
        timer.cancel();
        _webtoonRestoreTimer = null;
        return;
      }
      double? leading, trailing;
      final positions = _itemPositionsListener?.itemPositions.value;
      if (positions != null) {
        for (final p in positions) {
          if (p.index == flat) {
            leading = p.itemLeadingEdge;
            trailing = p.itemTrailingEdge;
            break;
          }
        }
      }
      // 视口高度优先用滚动通知实测值，缺失时退回本组件尺寸。
      final double viewport = _webtoonViewport ?? (context.size?.height ?? 0.0);
      if (leading != null && trailing != null && viewport > 0) {
        // itemTrailingEdge 是末页**底边**在视口中的比例，≤1+容差即已贴底：收尾。
        if (trailing <= 1.0 + 2e-3) {
          timer.cancel();
          _webtoonRestoreTimer = null;
          _finishWebtoonRestore(last, token);
          return;
        }
        // 末页高 = (trailing − leading) × 视口高；使末页底贴底的 alignment：
        // A = 1 − 末页高/视口高 = 1 − (trailing − leading)
        // 长条漫下 A 为负（合法），把末页顶边推到视口上方、底贴底。跳定是瞬移，
        // 不排队动画，故不会在用户紧随其后的滚动中造成回弹。
        if (corrections < 6) {
          corrections += 1;
          final double a = 1.0 - (trailing - leading);
          isc.jumpTo(index: flat, alignment: a);
        }
      }
      if (timer.tick >= 18) {
        // 1.5s 兜底：章末内容不足或极端布局下强制收尾，绝不卡死。
        timer.cancel();
        _webtoonRestoreTimer = null;
        _finishWebtoonRestore(last, token);
      }
    });
  }

  /// 回到上一话末页的收尾：把当前页赋成末页、解除屏蔽、写盘。
  void _finishWebtoonRestore(int last, int token) {
    _webtoonRestoreTimer = null;
    if (!mounted || !_loadSession.isValid(token)) return;
    _currentPage = last;
    // 延后一帧再解除 _restoringPage：本方法常由最后一跳 jumpTo 所在帧直接调用，
    // 等本帧布局/绘制结束后再放行，避免用户紧跟其后的滚动与收尾瞬移产生竞态回弹。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_loadSession.isValid(token)) return;
      _restoringPage = false;
      _saveProgress(last);
      setState(() {});
    });
  }

  /// 条漫列表的边界拖拽换章判定。返回 false 让通知继续向上冒泡。
  bool _handleWebtoonScrollNotification(ScrollNotification n) {
    // 实时捕获列表最大滚动范围，供「回到上一话末页」阶段 2 判稳使用（图片加载会让其增长）。
    _webtoonMaxExtent = n.metrics.maxScrollExtent;
    // 同时捕获视口高度：收尾补差需要把 itemTrailingEdge（比例）换算成像素。
    _webtoonViewport = n.metrics.viewportDimension;
    if (n is ScrollStartNotification || n is ScrollEndNotification) {
      // 回到上一话末页的自动滚动过程中，用户主动拖动则放弃自动滚到底（已接管）。
      // 程序滚动动画的 dragDetails 为 null，不会误触发。
      // 收尾阶段的校验轮询（_webtoonRestoreTimer）同样要能被打断，否则用户已接管
      // 拖走后，轮询仍可能把进度强写成末页。
      if (n is ScrollStartNotification &&
          n.dragDetails != null &&
          _restoringPage &&
          (_webtoonLastPageTimer != null || _webtoonRestoreTimer != null)) {
        _webtoonLastPageTimer?.cancel();
        _webtoonLastPageTimer = null;
        _webtoonLastPageTimeout?.cancel();
        _webtoonLastPageTimeout = null;
        _webtoonRestoreTimer?.cancel();
        _webtoonRestoreTimer = null;
        _webtoonPhaseJumped = false;
        _webtoonMaxExtent = null;
        _webtoonPrevExtent = null;
        _webtoonExtentStableCount = 0;
        _restoringPage = false;
      }
      _overscrollAccum = 0;
      return false;
    }
    if (n is! OverscrollNotification) return false;
    // 仅响应手指拖拽产生的越界，忽略惯性滑动的余量，避免快速甩动误换章。
    if (n.dragDetails == null) return false;
    _overscrollAccum += n.overscroll;
    if (_overscrollAccum >= _kChapterOverscroll) {
      _overscrollAccum = 0;
      _goNextChapter();
    } else if (_overscrollAccum <= -_kChapterOverscroll) {
      _overscrollAccum = 0;
      _goPrevChapter();
    }
    return false;
  }

  Widget _buildWebtoonList(
    ItemScrollController isc,
    ItemPositionsListener ipl,
    int restoreIndex,
    double gap,
    double restoreAlign,
  ) {
    final Widget list = PageStorage(
      // 按章节隔离 SPL 的滚动位置存储：SPL 的 _updatePositions 每帧把当前可见项
      // 写入 PageStorage，切章重建（key 变化）时其 initState 优先读 PageStorage
      // 而非 initialScrollIndex → 新章首帧显示旧章位置、随后再被修正，表现为
      // 「先退回再前进」的回弹/抽搐。包一层带章节 key 的 PageStorage 后读写都
      // 隔离在本章内：切章后存储为空，initialScrollIndex（restoreIndex）真正
      // 生效，首帧落点正确，来回换章不再串位。
      key: PageStorageKey('webtoon-$_chapterIndex'),
      // build 内直接 new bucket：PageStorage State 仅在首次 build 时取用
      // （_bucket ??= widget.bucket），key 变化 → 新 State → 取到新实例，
      // 章节间天然隔离；同章 rebuild 复用同一实例，滚动位置仍可安全恢复。
      bucket: PageStorageBucket(),
      child: ScrollablePositionedList.separated(
        key: ValueKey('webtoon-$_chapterIndex'),
        itemScrollController: isc,
        // 相对像素滚动：供「回到上一话末页」收尾时把末页底边精确补到视口底。
        scrollOffsetController: _webtoonOffsetController,
        itemPositionsListener: ipl,
        initialScrollIndex: restoreIndex,
        // keep 无缝重锚的首帧对齐（真实阅读位置常在页面中部，edge 为负）：
        // 切章换 key 重建时直接落在最终位置，避免「首帧对齐 0 → jumpTo 钉回」闪帧。
        initialAlignment: restoreAlign,
        // 连续滚动（条漫）：未放大 ClampingScrollPhysics 平滑滚动、边界夹紧无回弹；
        // 放大态（_zoomed）切 NeverScrollableScrollPhysics：禁【拖动】滚动（拖动
        // 交给外层矩阵平移 = 上下左右都能拖图），滚轮改由 [_onPointerScroll] 手动
        // animateScroll(0 时长瞬移) 滚动列表（Scrollable 因 physics 不再处理滚轮信号）。
        // 注意：physics 必须用 _zoomed（_onZoomChanged 在放大态切换时 setState），
        // 不能直接读 _zoomController.value（list 在 AnimatedBuilder 外构建，不随缩放重建）。
        physics: _zoomed
            ? const NeverScrollableScrollPhysics()
            : const ClampingScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount:
            _seamActive && _seamItemCount > 0 ? _seamItemCount : _images.length,
        separatorBuilder: (_, __) => SizedBox(height: gap),
        itemBuilder: (ctx, i) {
          // 段式连续模型（跨章无缝续读）：扁平列表由「真实页 + 章分割/过渡
          // 条目」组成。章分割条目（页映射为 -1）渲染章节标题卡，越过即进入新段。
          if (_seamActive && _seamItemCount > 0 && _seamPageMap[i] < 0) {
            return _buildSeamSeparator(i, gap);
          }
          final String url =
              _seamActive && _seamItemCount > 0 ? _seamImages[i] : _images[i];
          final int pageIdx =
              _seamActive && _seamItemCount > 0 ? _seamPageMap[i] : i;
          return Container(
            // 条漫（gap==0）相邻图之间常有子像素接缝（"细白条"）：每张图向下重叠 1px
            // 彻底闭合接缝，深浅主题下都不会露出底色线条。带间距模式（gap>0）保持原样。
            // 注意：3.47+ Container.margin 断言拒绝负值（isNonNegative），改用 Transform
            // 位移实现同样效果，避免断言崩溃。
            transform: gap == 0 ? Matrix4.translationValues(0, 1, 0) : null,
            // 页面动态效果（条漫）：滚动停止后对可见页后台渲染并叠加。
            child: _withPageMotion(
              url,
              _pageRotations[pageIdx] ?? 0,
              MangaPageImage(
                url: url,
                prefs: _prefs,
                source: _source,
                refererResolver: _refererFor,
                rotationQuarterTurns: _pageRotations[pageIdx] ?? 0,
                cropEdge: _prefs.cropEdge,
              // 条漫缩放由外层整体 Transform 负责（见下），item 一律恒等——
                // 每页一起放大、间距等比，天然不重叠（复测「每张照片放大导致重叠」）。
                zoomEnabled: () => false,
                // 阅读器级加载记录：item 被 SPL 回收重建后仍按真实高度渲染，
                // 消除「占位→真实」高度突变导致的反向翻页回弹/闪烁。
                urlLoaded: (url) => _webtoonLoadedUrls.contains(url),
                onUrlLoaded: (url) => _webtoonLoadedUrls.add(url),
                // 缓存真实自然尺寸（占位高 / 纵向夹取基于真实高度）。
                onImageInfo: (url, w, h) => _realImageDims[url] = Size(w, h),
                realHeightResolver: (url, maxWidth) {
                  final Size? dims = _realImageDims[url];
                  if (dims == null || dims.width <= 0) return null;
                  // fitWidth 下布局高度 = 自然高 × (视口宽 / 自然宽)。
                  return dims.height * maxWidth / dims.width;
                },
                translation: _translation,
                translationRetry: _translationRetryPage,
              ),
            ),
          );
        },
      ),
    );
    // 条漫整体缩放：把 [_zoomController] 矩阵应用到【整个列表】（缩放作用于整个
    // 滚动列表，结构为「视口裁剪 + 缩放变换 + 显式视口尺寸 + 内部滚动」）。
    //
    // 结构：ClipRect（视口裁剪）→ Transform（缩放矩阵）→ SizedBox.expand（显式
    // 视口尺寸）→ ScrollablePositionedList（内部滚动）。
    // 列表滚动发生在视口内部：滚动把不同图片送进视口，视口整体被 Transform 放大 →
    // 滚动时看到的每一张图都是放大后的版本，可从上到下浏览全部图片。
    //
    // 【为什么不用 InteractiveViewer / 裸 Transform】：
    // - 裸 Transform + AnimatedBuilder：缩放矩阵变化必然 rebuild，画面跟手；
    // Stack 默认 Clip.hardEdge 裁剪视口外溢出（等效下方 ClipRect），属正常视口。
    // - InteractiveViewer：内部 GestureDetector(HitTestBehavior.opaque) 的
    // ScaleGestureRecognizer 会参与手势竞技场、抢走单指拖动 → 放大后列表滚不动
    // （"显示区域只在放大的区域"）；且该版本无 _onTransformationControllerChange，
    // 外部改矩阵后 1x↔0.5x 不触发 rebuild → 缩放画面不刷新、三态循环错乱。
    return AnimatedBuilder(
      animation: _zoomController,
      builder: (context, _) => ClipRect(
        child: Transform(
          transform: _zoomController.value,
          alignment: Alignment.center,
          child: SizedBox.expand(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: _sideMarginPx),
              // 条漫图片区域黑底：相邻图片的子像素缝隙 / 加载跳变瞬间透出黑色
              // 而非用户浅色 bg，消除「细白条」（图片间缝隙背景统一为深色，白条不可见）。
              // 左右留白由外层 Padding 透出 bg。
              child: Container(
                // gap=0（默认条漫）：缝隙黑底消除白条；gap>0（带间距模式）：
                // 间距透出用户 bg，保持设置不被改黑。
                color: gap > 0
                    ? _prefs.resolveBackgroundColor(
                        Theme.of(context).brightness == Brightness.dark)
                    : Colors.black,
                child: list,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 段式连续模型的「章分割/过渡」条目（跨章无缝续读）。
  ///
  /// 渲染为章节标题卡：显示被引入的下一章序号与标题，让读者越过章边界时明确感知
  /// 已进入新章节。分隔条目位于其引入段的紧前方（startOffset == flatIdx + 1）。
  /// 底色与条漫容器一致（gap==0 黑底、gap>0 读者背景），避免透出细白条。
  Widget _buildSeamSeparator(int flatIdx, double gap) {
    final l10n = AppLocalizations.of(context);
    _SeamSegment? next;
    for (final _SeamSegment seg in _seam) {
      if (seg.startOffset == flatIdx + 1) {
        next = seg;
        break;
      }
    }
    next ??= _seam.isEmpty ? null : _seam.first;
    final String label = next == null || next.title.isEmpty
        ? l10n.chapterN((next?.chapterIndex ?? _chapterIndex) + 1)
        : '${l10n.chapterN(next.chapterIndex + 1)} · ${next.title}';
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color bg =
        gap > 0 ? _prefs.resolveBackgroundColor(dark) : Colors.black;
    final Color fg =
        gap > 0 ? (dark ? Colors.white70 : Colors.black54) : Colors.white70;
    final Color line =
        gap > 0 ? (dark ? Colors.white24 : Colors.black26) : Colors.white24;
    return Container(
      transform: gap == 0 ? Matrix4.translationValues(0, 1, 0) : null,
      color: bg,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 40,
            height: 3,
            decoration: BoxDecoration(
              color: line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: fg,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// 时间 / 电量浮层：控制栏可见时显示，随控制栏显隐。
  ///
  /// 位置（[ClockBatteryPosition] 四角）与边距、透明度、字号均由偏好控制；
  /// 电量不可用（-1，部分平台/测试环境）时仅显示时间。
  Widget _buildClockBatteryOverlay(AppLocalizations l10n) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color fg = dark ? Colors.white : Colors.black;
    final String batteryText =
        _batteryLevel < 0 ? '' : l10n.readerClockBatteryPercent(_batteryLevel);
    final String text =
        batteryText.isEmpty ? _currentTime : '$_currentTime  $batteryText';
    final Widget chip = IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: fg,
            fontSize: _prefs.clockBatteryFontSize,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
    final double m = _prefs.clockBatteryMargin;
    final ClockBatteryPosition pos = _prefs.clockBatteryPosition;
    return Positioned(
      top: (pos == ClockBatteryPosition.topLeft ||
              pos == ClockBatteryPosition.topRight)
          ? m
          : null,
      bottom: (pos == ClockBatteryPosition.bottomLeft ||
              pos == ClockBatteryPosition.bottomRight)
          ? m
          : null,
      left: (pos == ClockBatteryPosition.topLeft ||
              pos == ClockBatteryPosition.bottomLeft)
          ? m
          : null,
      right: (pos == ClockBatteryPosition.topRight ||
              pos == ClockBatteryPosition.bottomRight)
          ? m
          : null,
      child: Opacity(
        opacity: _prefs.clockBatteryOpacity.clamp(0.1, 1.0),
        child: chip,
      ),
    );
  }

  Widget _buildTopBar(AppLocalizations l10n, Color bg) {
    final chapter =
        widget.chapters.isEmpty ? null : widget.chapters[_chapterIndex];
    final String? chapterUrl = chapter?.url;
    // 章节链接拼接：源返回相对路径时补 baseUrl；已是绝对 URL（http 开头）
    // 时直接使用，避免拼出 `https://a.comhttps://b.com/...` 的非法地址。
    final String? absoluteChapterUrl =
        (chapterUrl != null && chapterUrl.isNotEmpty)
            ? (chapterUrl.startsWith('http') ||
                    _source == null ||
                    _source!.site.baseUrl.isEmpty
                ? chapterUrl
                : _source!.site.baseUrl + chapterUrl)
            : null;
    // 本地模式标题：文件名 · 本地文件（无章节概念）。
    final String titleText = _isLocalMode
        ? '${widget.title} · ${l10n.localFileLabel}'
        : '${widget.title} · ${l10n.chapterN(_chapterIndex + 1)}'
            '${chapter != null && chapter.title.isNotEmpty ? ' · ${chapter.title}' : ''}';
    // 控制栏底色跟随应用主题（暗色即深色），而非读者背景色：
    // 这样无论读者背景设为黑/白/护眼绿，图标文字都始终与底色形成对比，夜色模式不会看不清。
    final Color scrim = Theme.of(context).colorScheme.surface;
    // 渐变背景容器铺到屏幕最顶端（含状态栏 / 刘海区），SafeArea 只包住 Row 内容
    // 负责避让安全区。此前 SafeArea 包在最外层，背景整体被推到状态栏下方，
    // 最顶端露出一条漫画画面（shortEdges 窗口进刘海后尤为明显）。
    // bottom:false——顶栏不含导航条高度的底部空白。
    return MouseRegion(
      // 桌面端控件光标反馈：控制栏按钮 hover 显示 click 光标。
      cursor: SystemMouseCursors.click,
      child: Container(
        key: _topBarKey,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              scrim.withValues(alpha: 0.95),
              scrim.withValues(alpha: 0)
            ],
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceMd,
          vertical: AppTokens.spaceSm,
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Text(
                  titleText,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.settings_rounded),
                tooltip: l10n.readerSettings,
                onPressed: _openSettings,
              ),
              // 章节列表按钮：本地单文件模式（无章节表）隐藏；多话模式（在线 /
              // 归档聚合 / 下载目录聚合）都保留目录切话入口。
              if (!_isLocalMode || widget.chapters.length > 1)
                IconButton(
                  icon: const Icon(Icons.toc_rounded),
                  tooltip: l10n.chapterList,
                  onPressed: () async {
                    final index = await showChapterList(
                      context,
                      widget.chapters,
                      _chapterIndex,
                      bookmarkedIndices: await _bookmarkedIndices(),
                    );
                    if (index != null && index != _chapterIndex && mounted) {
                      // 统一走 _jumpToChapter：回到之前读的话时恢复到离开页
                      // （_chapterPageCache），且 localChapterDirs 下载聚合模式走
                      // 本地取图而非在线 fetchImages。此前这里手动
                      // `_chapterIndex = index; _loadLocalImages()` /
                      // `_loadChapter()` 不带 restorePage，目录切回已读话永远落
                      // 首页（进度丢失），下载目录模式还误走在线加载。
                      _jumpToChapter(index);
                    }
                  },
                ),
              // WebView / 浏览器 / 分享菜单：本地模式无在线 URL，隐藏。
              if (!_isLocalMode)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded),
                  tooltip: l10n.moreActions,
                  onSelected: (String value) {
                    switch (value) {
                      // 待读队列：不需要章节 URL，先于 webview 守卫处理。
                      case 'addToReadingQueue':
                        _addCurrentToReadingQueue();
                        return;
                      case 'readingQueue':
                        openReadingQueueSheet(context);
                        return;
                    }
                    if (absoluteChapterUrl == null) return;
                    switch (value) {
                      case 'webview':
                        openInAppBrowser(context, absoluteChapterUrl,
                            source: _source);
                      case 'browser':
                        openInExternalBrowser(context, absoluteChapterUrl);
                      case 'share':
                        shareContent(
                          context,
                          '${widget.title} - ${chapter?.title ?? ''}',
                          absoluteChapterUrl,
                        );
                    }
                  },
                  itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
                    // 待读队列：加入队列 / 打开队列。
                    PopupMenuItem<String>(
                      value: 'addToReadingQueue',
                      child: ListTile(
                        leading: const Icon(Icons.playlist_add_rounded),
                        title: Text(l10n.readingQueueAdd),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'readingQueue',
                      child: ListTile(
                        leading: const Icon(Icons.playlist_play_rounded),
                        title: Text(l10n.readingQueueOpen),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem<String>(
                      value: 'webview',
                      enabled: absoluteChapterUrl != null,
                      child: ListTile(
                        leading: const Icon(Icons.public_rounded),
                        title: Text(l10n.openInAppBrowser),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'browser',
                      enabled: absoluteChapterUrl != null,
                      child: ListTile(
                        leading: const Icon(Icons.open_in_new_rounded),
                        title: Text(l10n.openInBrowser),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'share',
                      enabled: absoluteChapterUrl != null,
                      child: ListTile(
                        leading: const Icon(Icons.share_rounded),
                        title: Text(l10n.share),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(AppLocalizations l10n) {
    // 控制栏底色跟随应用主题（暗色即深色），保证图标文字对比度（见 _buildTopBar）。
    final Color scrim = Theme.of(context).colorScheme.surface;
    // 渐变背景容器铺到屏幕最底端（含导航条区），SafeArea 只包住 Column 内容
    // 负责避让安全区（与 _buildTopBar 同款修法）。top:false——底栏不含状态栏高度。
    return MouseRegion(
      // 桌面端控件光标反馈：控制栏按钮 hover 显示 click 光标。
      cursor: SystemMouseCursors.click,
      child: Container(
        key: _bottomBarKey,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: <Color>[
              scrim.withValues(alpha: 0.95),
              scrim.withValues(alpha: 0),
            ],
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceMd,
          vertical: AppTokens.spaceSm,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // 章内进度滑条（仅底横形态；右竖形态由 _buildRightProgressBar 单独覆盖）。
              _buildProgressBar(l10n),
              const SizedBox(height: AppTokens.spaceXs),
              _buildBottomToolbar(l10n),
            ],
          ),
        ),
      ),
    );
  }

  /// 底部横向进度滑条（progressBarOnRight=false 时渲染）。
  /// 左右翻页箭头 + 滑条 + 页码（受 showPageNumber 控制）。
  /// 双页模式下以「跨页」为单位，标签显示当前跨页包含的页码范围。
  Widget _buildProgressBar(AppLocalizations l10n) {
    if (_prefs.progressBarOnRight) return const SizedBox.shrink();
    final bool doubleMode = _isDoublePage;
    final int totalImages = _images.length;
    final int total = doubleMode ? _spreadCount : totalImages;
    return Semantics(
      label: l10n.readerProgress,
      child: Directionality(
        // RTL 模式下滑条方向反转（视觉与翻页方向一致）。
        textDirection: _prefs.readingMode == ReadingMode.singleRTL
            ? TextDirection.rtl
            : TextDirection.ltr,
        // 页码经 notifier 局部刷新：自动滚动期间页码切换只重建滑条/页码行，
        // 不触发整屏 setState（触顶卡顿根治）。按钮为稳定方法引用，重建无副作用。
        child: ValueListenableBuilder<int>(
          valueListenable: _currentPageNotifier,
          builder: (context, page, _) {
            final int currentIndex =
                doubleMode ? _doublePageSpreadFor(page) : page;
            final double value =
                total > 1 ? (currentIndex / (total - 1)).clamp(0.0, 1.0) : 0.0;
            return Row(
              children: <Widget>[
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  tooltip: l10n.prevPage,
                  onPressed: _goPrevPage,
                ),
                Expanded(
                  child: Slider(
                    value: value,
                    onChangeStart: total > 1 ? (_) => AppHaptics.light() : null,
                    onChanged: total > 1
                        ? (v) {
                            final target = doubleMode
                                ? _doublePageLeftPageFor(
                                    (v * (total - 1)).round())
                                : (v * (total - 1)).round();
                            _jumpToPage(target);
                          }
                        : null,
                  ),
                ),
                if (_prefs.showPageNumber)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.spaceSm),
                    child: Text(
                      doubleMode
                          ? _doublePageIndicatorText(
                              l10n, currentIndex, totalImages)
                          : l10n.pageIndicator(
                              totalImages == 0 ? 0 : page + 1,
                              totalImages,
                            ),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  tooltip: l10n.nextPage,
                  onPressed: _goNextPage,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 双页跨页页码标签，例如 1-2 / 10。
  ///
  /// 首屏单图时 spread 从 0 开始为 1 / 2-3 / 4-5…（spread0 只含第 1 页），
  /// 常规双页保持 1-2 / 3-4… 语义；页号从 1 起，末页按 [totalImages] 夹紧。
  String _doublePageIndicatorText(
    AppLocalizations l10n,
    int spreadIndex,
    int totalImages,
  ) {
    final int first = _doublePageLeftPageFor(spreadIndex) + 1;
    final int last =
        spreadIndex == 0 && _showFirstPageSingle ? first : first + 1;
    final int clamped = last.clamp(1, totalImages).toInt();
    return l10n.readerDoublePageIndicator(first, clamped, totalImages);
  }

  /// 双页跨页范围文本（不含总数），例如 1-2。
  ///
  /// 首屏单图时 spread 0/1/2 → 1 / 2-3 / 4-5；常规双页保持 1-2 / 3-4。
  String _doublePageRangeText(int spreadIndex, int totalImages) {
    final int first = _doublePageLeftPageFor(spreadIndex) + 1;
    final int last =
        spreadIndex == 0 && _showFirstPageSingle ? first : first + 1;
    final int clamped = last.clamp(1, totalImages).toInt();
    return '$first-$clamped';
  }

  /// 右侧竖向进度滑条（progressBarOnRight=true 时渲染）。
  /// 靠右 Positioned：上/下翻页箭头 + 顶/底页码 + 旋转 90° 的 Slider。
  /// 双页模式下以「跨页」为单位。
  Widget _buildRightProgressBar(AppLocalizations l10n) {
    final bool doubleMode = _isDoublePage;
    final int totalImages = _images.length;
    final int total = doubleMode ? _spreadCount : totalImages;
    final bool showNum = _prefs.showPageNumber;
    return Positioned(
      right: AppTokens.spaceXs,
      top: 0,
      bottom: 0,
      child: SafeArea(
        child: Center(
          child: Semantics(
            label: l10n.readerProgress,
            // 页码经 notifier 局部刷新（同 [_buildProgressBar]，自动滚动期间
            // 不整屏 setState）。
            child: ValueListenableBuilder<int>(
              valueListenable: _currentPageNotifier,
              builder: (context, page, _) {
                final int currentIndex =
                    doubleMode ? _doublePageSpreadFor(page) : page;
                final double value = total > 1
                    ? (currentIndex / (total - 1)).clamp(0.0, 1.0)
                    : 0.0;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      icon: const Icon(Icons.expand_less_rounded),
                      tooltip: l10n.prevPage,
                      onPressed: _goPrevPage,
                    ),
                    if (showNum)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppTokens.spaceXs,
                        ),
                        child: Text(
                          doubleMode
                              ? _doublePageRangeText(currentIndex, totalImages)
                              : '${totalImages == 0 ? 0 : page + 1}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    SizedBox(
                      // 旋转 90° 后，Slider 的横向宽度变成竖向高度。
                      height: MediaQuery.of(context).size.height * 0.4,
                      child: RotatedBox(
                        quarterTurns: 1,
                        child: Slider(
                          value: value,
                          onChangeStart:
                              total > 1 ? (_) => AppHaptics.light() : null,
                          onChanged: total > 1
                              ? (v) {
                                  final target = doubleMode
                                      ? _doublePageLeftPageFor(
                                          (v * (total - 1)).round())
                                      : (v * (total - 1)).round();
                                  _jumpToPage(target);
                                }
                              : null,
                        ),
                      ),
                    ),
                    if (showNum)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppTokens.spaceXs,
                        ),
                        child: Text(
                          // 与单页模式保持一致：底部始终显示总页数。
                          '$totalImages',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.expand_more_rounded),
                      tooltip: l10n.nextPage,
                      onPressed: _goNextPage,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// 底部快捷工具栏：阅读模式选择 / Spacer / 裁剪 / 旋转 / 设置。
  Widget _buildBottomToolbar(AppLocalizations l10n) {
    return Row(
      children: <Widget>[
        IconButton(
          icon: Icon(_readingModeIcon(_prefs.readingMode)),
          tooltip: l10n.readerMode,
          onPressed: () => _showReadingModePicker(l10n),
        ),
        // 收藏按钮：点击弹出底部菜单（收藏作品 / 收藏当前页图片 / 图片收藏图库）。
        IconButton(
          icon: Icon(
              _isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded),
          tooltip: l10n.favorite,
          onPressed: _showFavoriteMenu,
        ),
        const Spacer(),
        IconButton(
          icon: Icon(
              _prefs.cropEdge ? Icons.crop_rounded : Icons.crop_free_rounded),
          tooltip: l10n.readerCropEdge,
          onPressed: () => _onPrefsChanged(
            _prefs.copyWith(cropEdge: !_prefs.cropEdge),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.rotate_right_rounded),
          tooltip: l10n.readerRotatePage,
          onPressed: _rotateCurrentPage,
        ),
        IconButton(
          icon: const Icon(Icons.tune_rounded),
          tooltip: l10n.readerSettings,
          onPressed: _openSettings,
        ),
      ],
    );
  }

  IconData _readingModeIcon(ReadingMode mode) => switch (mode) {
        ReadingMode.singleLTR => Icons.arrow_forward_rounded,
        ReadingMode.singleRTL => Icons.arrow_back_rounded,
        ReadingMode.singleVertical => Icons.arrow_downward_rounded,
        ReadingMode.webtoon => Icons.view_stream_rounded,
        ReadingMode.webtoonWithGap => Icons.view_agenda_rounded,
      };

  /// 阅读模式选择：弹出白色底部面板，用 ChoiceChip 列出 5 种模式
  ///（用户决策：与小说阅读器一致的形式）。
  void _showReadingModePicker(AppLocalizations l10n) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.spaceLg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(l10n.readerMode,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppTokens.spaceMd),
                  Wrap(
                    spacing: AppTokens.spaceSm,
                    runSpacing: AppTokens.spaceSm,
                    children: ReadingMode.values.map((m) {
                      return ChoiceChip(
                        label: Text(_readingModeLabel(l10n, m)),
                        selected: _prefs.readingMode == m,
                        onSelected: (_) {
                          _onPrefsChanged(_prefs.copyWith(readingMode: m));
                          Navigator.of(ctx).pop();
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _readingModeLabel(AppLocalizations l10n, ReadingMode m) => switch (m) {
        ReadingMode.singleLTR => l10n.readerModeSingleLTR,
        ReadingMode.singleRTL => l10n.readerModeSingleRTL,
        ReadingMode.singleVertical => l10n.readerModeSingleVertical,
        ReadingMode.webtoon => l10n.readerModeWebtoon,
        ReadingMode.webtoonWithGap => l10n.readerModeWebtoonWithGap,
      };
}

/// 居中的提示信息（错误 / 空）。
class _CenterMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final VoidCallback? onRetry;
  const _CenterMessage(
      {required this.icon, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: AppTokens.spaceMd),
            Text(message, style: Theme.of(context).textTheme.bodyMedium),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: AppTokens.spaceMd),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(AppLocalizations.of(context).retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 单页漫画图：支持以指针为中心的双击/滚轮缩放（缩放由外部
/// [zoomController] 统一驱动，便于阅读器在点击区域覆盖层上响应双击缩放）。
///
/// 增强：[rotationQuarterTurns] 让用户对单页 90° 旋转（不影响其他页）；
/// [cropEdge] 为 true 时改用 [BoxFit.cover] / 居中裁切去四周留白（简单版）。

/// 条漫连续模式解码位图的宽上限（像素， 资源/内存 enableResize）。
const int _kWebtoonDecodeCapSide = 2560;

class MangaPageImage extends StatefulWidget {
  final String url;
  final ReaderPreferences prefs;
  final TransformationController? zoomController;
  final PluginConfig? source;

  /// 该页旋转的 quarterTurns（0/1/2/3 = 0°/90°/180°/270°）。
  final int rotationQuarterTurns;

  /// 是否裁边（true 时图片 fit 切换为 cover + 居中对齐，去除四周留白）。
  final bool cropEdge;

  /// 是否应用缩放矩阵（默认恒 true）。条漫模式下**只有当前页放大**（其余页恒等）：
  /// item 高度不随缩放变化，若每页各自放大，相邻页的放大内容会互相重叠
  /// （复测 bug「每张照片放大导致照片重叠」）。返回 false 的 item 用恒等矩阵。
  final bool Function()? zoomEnabled;

  /// 查询某 URL 是否已在本话内加载完成（阅读器级记录，跨 item 回收重建存活）。
  /// SPL 懒加载回收 item 后重建时 `_imageLoaded` 局部状态丢失，若已加载过仍显示
  /// 占位高度会触发「占位→真实」高度突变（反向翻页回弹的根因）。为 null 时仅凭
  /// 局部 `_imageLoaded` 判断（翻页模式等无回收重建场景）。
  final bool Function(String url)? urlLoaded;

  /// 图片加载完成时上报 URL（阅读器据此写入 [_webtoonLoadedUrls]）。
  final void Function(String url)? onUrlLoaded;

  /// 自然尺寸回调（一次）：把解码出的原始宽高回传阅读器，用于缓存真实高度。
  final void Function(String url, double naturalWidth, double naturalHeight)?
      onImageInfo;

  /// 查询某 URL 在给定最大宽度下的真实「适配宽度」布局高度（fitWidth 下
  /// height = naturalHeight × maxWidth / naturalWidth）。命中缓存返回真实值，
  /// 未命中（该图从未加载过）返回 null，由调用方回退经验值。
  final double? Function(String url, double maxWidth)? realHeightResolver;

  /// 查询某图片 URL 的取图 Referer（章节页 URL 推导；null 回退源
  /// antiHotlinking.referer）。部分站点按「图片 ↔ 所属章节页」绑定校验
  /// Referer，固定站点级 Referer 取不到图。
  final String? Function(String url)? refererResolver;

  /// 漫画翻译控制器（漫画翻译功能）。非 null 且开关打开时，在该页图片上
  /// 叠加译文覆盖层（气泡按千分比坐标映射到显示矩形）。
  final ComicTranslationController? translation;

  /// 翻译失败重试回调（覆盖层错误徽标点击；由阅读器按 URL 反查页码后重试）。
  final void Function(String url)? translationRetry;

  const MangaPageImage({
    super.key,
    required this.url,
    required this.prefs,
    this.zoomController,
    this.source,
    this.rotationQuarterTurns = 0,
    this.cropEdge = false,
    this.zoomEnabled,
    this.urlLoaded,
    this.onUrlLoaded,
    this.onImageInfo,
    this.realHeightResolver,
    this.refererResolver,
    this.translation,
    this.translationRetry,
  });

  @override
  State<MangaPageImage> createState() => _MangaPageImageState();
}

class _MangaPageImageState extends State<MangaPageImage> {
  final TransformationController _local = TransformationController();
  TransformationController get _tc => widget.zoomController ?? _local;

  // 条漫占位状态：未加载时 ConstrainedBox 用经验高度占位（保证回上一话滚动估算
  // 准确）；加载完成后置 true，移除占位约束让图片按真实高度显示（消除空白带）。
  bool _imageLoaded = false;

  @override
  void didUpdateWidget(covariant MangaPageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // item 复用时 url 变化（ScrollablePositionedList 回收复用），重置占位状态，
    // 避免沿用旧图高度或错把新图当已加载。
    if (oldWidget.url != widget.url) {
      _imageLoaded = false;
    }
  }

  // 手势（捏合 / 平移 / 滚轮）已全部上提到阅读器屏幕级（ReaderTapZones），
  // 本组件只负责渲染，不再持有缩放手势状态。

  @override
  void dispose() {
    _local.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 初始缩放（initialZoom）+ 裁边（cropEdge）共同决定图片 fit 与尺寸约束。
    // cropEdge 优先：用 BoxFit.cover 居中裁切，去掉页面四周留白（按文档简单版实现）。
    // 非裁边时按 initialZoom 选择适配方式。
    final (BoxFit fit, double? width) = _resolveFit();
    // 条漫 + fitWidth 且非裁边：图片加载完成前 SourceImage 仅含占位符高度（约转圈
    // 图标大小）。ScrollablePositionedList 据此用占位高度估算 maxScrollExtent；当
    // 回滚到某话底部时，视口外的长条图项尚未构建、不加载，任何「高度稳定」判据都会
    // 误以为已稳定，导致 scrollTo 按错误高度计算像素偏移、停在开头而非末页。
    // 对策：给未加载 item 预留接近真实图高的占位高度（屏宽 × 1.5，长条漫经验值），
    // 让列表从一开始估算就准确，回上一话即可一次定位到末页。
    // 图片加载完成（[_imageLoaded]）后**移除**占位约束，按真实图高显示——
    // 这是消除空白带（割裂感）的关键：若保留 ConstrainedBox(minHeight)，当真实图高
    // 偏小（中等长度图）时图片下方会残留 minHeight 空白（加载完成后占位约束移除，
    // 图片按真实高度显示，不残留空白带）。
    final bool reserveWebtoonHeight = widget.prefs.readingMode.isWebtoon &&
        widget.prefs.initialZoom == ReaderInitialZoom.fitWidth &&
        !widget.cropEdge;

    // 加载完成标记合并局部状态与阅读器级记录：SPL 回收 item 后重建时局部
    // _imageLoaded 已丢失，但 URL 级记录仍在——直接按真实高度渲染，避免
    // 已缓存图片重新走「占位→真实」高度突变导致的反向翻页回弹/闪烁。
    final bool showRealHeight =
        (widget.urlLoaded?.call(widget.url) ?? false) || _imageLoaded;

    // 解码限幅（连续模式 enableResize）：条漫模式下把解码位图宽下采样到
    // min(2560, 屏幕物理像素 × 2)——长条漫原图常达数千 px 宽，全尺寸解码一张
    // 可占数十 MB 内存，连续滚动极易触发低机卡顿/OOM。×2 系数为捏合放大保留
    // 一档细节；上限 2560 与常见图片加载器 BaseImageProvider 的限幅一致。paged 单页
    // 模式不限幅（页面数少且需放大细节）。
    int? decodeCapWidthPx;
    if (widget.prefs.readingMode.isWebtoon &&
        widget.prefs.webtoonLimitDecodeSize) {
      final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
      final screenW = MediaQuery.sizeOf(context).width;
      decodeCapWidthPx =
          (screenW * dpr * 2).round().clamp(720, _kWebtoonDecodeCapSide);
    }

    // 超分（GPU 实时 shader）：仅在「单页翻页模式」接管渲染——阅读器为超分
    // 路径持有该页 ImageInfo（引用计数 +1），条漫一屏挂载数十页，逐页长持有会
    // 阻止 Flutter 图片缓存回收解码位图。条漫保持 SourceImage 原样渲染；源图尺寸
    // 超 GPU 纹理上限（超长单图）时由超分 widget 自动回退普通渲染。
    final MangaUpscaleMode upscaleMode = widget.prefs.upscaleMode;
    final bool useUpscale = upscaleMode.enabled &&
        MangaUpscaleShader.isSupported &&
        widget.prefs.readingMode.isPaged;

    final Widget imgSource = useUpscale
        ? _buildUpscaledSource(
            fit: fit,
            width: width,
            decodeCapWidthPx: decodeCapWidthPx,
            mode: upscaleMode,
          )
        : SourceImage(
            url: widget.url,
            source: widget.source,
            refererOverride: widget.refererResolver?.call(widget.url),
            fit: fit,
            width: width,
            decodeCapWidthPx: decodeCapWidthPx,
            placeholder: const Center(child: AppLoadingIndicator()),
            onLoadComplete: () {
              // 先上报阅读器级记录（同帧生效），再更新局部状态。
              widget.onUrlLoaded?.call(widget.url);
              if (mounted) setState(() => _imageLoaded = true);
            },
            onImageInfo: (w, h) => widget.onImageInfo?.call(widget.url, w, h),
          );

    // 仅未加载时占位：加载完成后直接用真实图高，不再受 minHeight 约束。
    // 占位高度优先用缓存的「真实图片高度」（fitWidth 下 naturalHeight × 视口宽 /
    // naturalWidth）；未加载过该图（缓存未命中）才回退经验值（屏宽 × 1.5）。
    final Widget content = (reserveWebtoonHeight && !showRealHeight)
        ? LayoutBuilder(
            builder: (context, constraints) {
              final double? cachedRealH = widget.realHeightResolver
                  ?.call(widget.url, constraints.maxWidth);
              final double ph = cachedRealH ?? constraints.maxWidth * 1.5;
              return ConstrainedBox(
                constraints: BoxConstraints(minHeight: ph),
                child: imgSource,
              );
            },
          )
        : imgSource;

    // 条漫模式（未加载占位时）用顶部对齐，避免实际图高 < minHeight 时图片垂直居中
    // 产生空白。加载完成后 content 已是真实图高，Align 无额外空间、无影响。
    final Widget raw = widget.cropEdge
        ? SizedBox.expand(child: content)
        : (reserveWebtoonHeight && !showRealHeight
            ? Align(alignment: Alignment.topCenter, child: content)
            : Align(alignment: Alignment.center, child: content));
    final img = ReaderImageFiltered(
      brightness: widget.prefs.filterBrightness,
      contrast: widget.prefs.filterContrast,
      colorTemp: widget.prefs.filterColorTemp,
      saturation: widget.prefs.filterSaturation,
      hue: widget.prefs.filterHue,
      inverted: widget.prefs.filterInverted,
      grayscale: widget.prefs.filterGrayscale,
      colorProfile: widget.prefs.colorProfile,
      child: raw,
    );
    // 漫画翻译覆盖层：叠加在滤镜后的图片上、旋转包裹内（页面旋转时译文
    // 跟随图片方向），随缩放矩阵一起变换。不盖住滤镜效果之外的任何手势
    // （气泡层内部 IgnorePointer，仅失败徽标可点重试）。
    final Widget imgWithTranslation = _buildTranslationOverlay(context, img);
    // 旋转包裹在 img 外：仅对该页生效，不影响其他页。
    final rotated = RotatedBox(
      quarterTurns: widget.rotationQuarterTurns,
      child: imgWithTranslation,
    );
    // 把 [_tc] 的矩阵应用到 rotated 上，得到「已缩放/已平移」的最终图像。
    // 必须用 AnimatedBuilder 监听 [_tc]：屏幕级滚轮 / 双击 / 捏合每次改值都会即时
    // 重建 Transform，画面才「跟手」。
    // [rotated] 作为 child 传入并缓存，避免每帧重建图片加载子树。
    //
    // 注意：捏合 / 平移 / 滚轮等手势已全部上提到阅读器屏幕级（ReaderTapZones 覆盖层
    // 统一跟踪，见 ComicReaderScreenState._onPinchUpdate/_onPanUpdate/_onPointerScroll），
    // 本组件只负责渲染——条漫模式下双指落在不同页也能识别缩放（根治），且不再有
    // 每页 GestureDetector 与覆盖层/滚动的手势竞争。
    //
    // 桌面端鼠标光标反馈：图片 hover 显示 click 光标，放大态显示 grab 光标。
    final bool isZoomed = _tc.value.getMaxScaleOnAxis() > 1.001;
    final Widget zoomed = AnimatedBuilder(
      animation: _tc,
      builder: (context, child) {
        // 条漫仅当前页放大（[widget.zoomEnabled] 为 false 的 item 用恒等矩阵），
        // 否则每页各自放大、item 高度不变 → 相邻页内容重叠。
        final bool active = widget.zoomEnabled?.call() ?? true;
        // ClipRect：item 高度不变，放大页内容溢出 item 框时裁剪；放大细节通过
        // 矩阵平移（tx/ty）在框内查看（放大态滚动已禁用，拖拽走 [_onPanUpdate]）。
        return ClipRect(
          child: Transform(
            transform: active ? _tc.value : Matrix4.identity(),
            alignment: Alignment.center,
            child: child,
          ),
        );
      },
      child: rotated,
    );
    // 桌面形态（Windows/macOS/Linux）添加光标反馈。
    if (PlatformService.instance.isDesktopForm) {
      return MouseRegion(
        cursor: isZoomed ? SystemMouseCursors.grab : SystemMouseCursors.click,
        child: zoomed,
      );
    }
    return zoomed;
  }

  /// 超分渲染源：**复用 [SourceImage] 自己的解码结果**，仅把「解码后 → 屏幕」
  /// 这一段换成 GPU shader 绘制。
  ///
  /// 为什么不让超分路径自己建 provider：SourceImage 内部走
  /// `CachedNetworkImage(cacheManager: NexImageCacheManager)`，磁盘缓存键、
  /// 防盗链头（Referer/UA/Cookie）、`.avif→.webp` 降级、指数退避重试、SAF
  /// `content://` 解析全部封装在其内部。外面另起 `NetworkImage`/`FileImage`
  /// 会绕过这些逻辑（缓存键不同 → 重复下载；缺防盗链头 → 403；无重试 → 一次
  /// 失败即空白），所以超分只能接管绘制、不能接管加载。
  Widget _buildUpscaledSource({
    required BoxFit fit,
    required double? width,
    required int? decodeCapWidthPx,
    required MangaUpscaleMode mode,
  }) {
    return _UpscaleSourceGate(
      url: widget.url,
      source: widget.source,
      refererOverride: widget.refererResolver?.call(widget.url),
      fit: fit,
      width: width,
      decodeCapWidthPx: decodeCapWidthPx,
      mode: mode,
      placeholder: const Center(child: AppLoadingIndicator()),
      onLoadComplete: () {
        // 先上报阅读器级记录（同帧生效），再更新局部状态。
        widget.onUrlLoaded?.call(widget.url);
        if (mounted) setState(() => _imageLoaded = true);
      },
      onImageInfo: (double w, double h) =>
          widget.onImageInfo?.call(widget.url, w, h),
    );
  }

  /// 由 [ReaderPreferences.initialZoom] 推导非裁边状态下的图片 fit 与宽度约束。
  /// - fitWidth：按宽度适配（width=∞）。
  /// - fitHeight：按高度适配（width=∞，由父容器高度约束）。
  /// - original：原始像素大小（不加宽高约束，由 InteractiveViewer 裁剪/平移）。
  ///
  /// 裁边（cropEdge）在 [build] 中单独用 [SizedBox.expand] + [BoxFit.cover] 处理，
  /// 不再经过本方法。
  (BoxFit, double?) _resolveFit() {
    switch (widget.prefs.initialZoom) {
      case ReaderInitialZoom.fitWidth:
        return (BoxFit.fitWidth, double.infinity);
      case ReaderInitialZoom.fitHeight:
        return (BoxFit.fitHeight, double.infinity);
      case ReaderInitialZoom.original:
        return (BoxFit.none, null);
    }
  }

  /// 漫画翻译覆盖层：翻译关闭 / 无翻译任务时原样返回 [child]，
  /// 有任务（加载中/完成/失败）时在图片上叠加 [ComicTranslationOverlay]。
  Widget _buildTranslationOverlay(BuildContext context, Widget child) {
    final controller = widget.translation;
    if (controller == null) return child;
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? cached) {
        if (!controller.enabled) return child;
        final state = controller.stateFor(widget.url);
        if (state.status == ComicPageTranslationStatus.idle) return child;
        // 覆盖层按「本页图片 + 当前页索引」重试（章/页键由阅读器闭包提供）。
        return Stack(
          fit: StackFit.passthrough,
          children: <Widget>[
            cached ?? child,
            Positioned.fill(
              child: ComicTranslationOverlay(
                state: state,
                zoom: widget.prefs.initialZoom,
                cropEdge: widget.cropEdge,
                backfill: widget.prefs.translationBackfill,
                onRetry: widget.translationRetry == null
                    ? null
                    : () => widget.translationRetry!(widget.url),
              ),
            ),
          ],
        );
      },
      child: child,
    );
  }
}

/// 缩放比例指示徽标：监听共享 [TransformationController]，放大
/// （>1.001）时显示「2.3×」，停止缩放 1.2s 后淡出；回到 1x 立即隐藏。
/// 经 ValueListenableBuilder 只重建徽标本体，捏合逐帧变化不触发整屏重建。
class _ZoomFactorBadge extends StatefulWidget {
  const _ZoomFactorBadge({required this.controller});

  final TransformationController controller;

  @override
  State<_ZoomFactorBadge> createState() => _ZoomFactorBadgeState();
}

class _ZoomFactorBadgeState extends State<_ZoomFactorBadge> {
  Timer? _hideTimer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onZoomMatrixChanged);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.removeListener(_onZoomMatrixChanged);
    super.dispose();
  }

  void _onZoomMatrixChanged() {
    final zoomed = widget.controller.value.getMaxScaleOnAxis() > 1.001;
    if (!zoomed) {
      _hideTimer?.cancel();
      if (_visible && mounted) setState(() => _visible = false);
      return;
    }
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _visible = false);
    });
    // 首次进入放大态才显示徽标；此后每次矩阵变化都刷新：捏合/滚轮缩放是连续手势，
    // 倍数文本须实时跟随（旧实现仅在 _visible 状态翻转时 setState——既漏了置位，
    // 又使捏合过程中倍数停留在初始值）。
    if (mounted) {
      if (!_visible) _visible = true;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final factor = widget.controller.value.getMaxScaleOnAxis();
    if (factor <= 1.001) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return AnimatedOpacity(
      opacity: _visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${factor.toStringAsFixed(1)}×',
          style: TextStyle(
            color: scheme.onPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// 超分渲染入口：用 [SourceImage] 承担全部加载（磁盘缓存 / 防盗链 / avif 降级 /
/// 重试 / SAF），只截获它解码完成的那张位图，改由 [MangaUpscaledImage] 经 GPU
/// shader 绘制；未解码完成或 shader 不可用时原样显示 [SourceImage]（因此
/// 占位、错误与重试 UI 与不带超分时完全一致，超分开关不改变可用性）。
class _UpscaleSourceGate extends StatefulWidget {
  const _UpscaleSourceGate({
    required this.url,
    required this.source,
    required this.refererOverride,
    required this.mode,
    required this.fit,
    required this.width,
    required this.decodeCapWidthPx,
    required this.placeholder,
    this.onLoadComplete,
    this.onImageInfo,
  });

  final String url;
  final PluginConfig? source;
  final String? refererOverride;
  final MangaUpscaleMode mode;
  final BoxFit fit;
  final double? width;
  final int? decodeCapWidthPx;
  final Widget placeholder;
  final VoidCallback? onLoadComplete;
  final void Function(double width, double height)? onImageInfo;

  @override
  State<_UpscaleSourceGate> createState() => _UpscaleSourceGateState();
}

class _UpscaleSourceGateState extends State<_UpscaleSourceGate> {
  /// SourceImage 解码完成回传的位图（所有权归本 State，替换/销毁时释放）。
  ui.Image? _decoded;
  bool _ready = false;

  void _onDecoded(ui.Image image) {
    if (!mounted) {
      image.dispose();
      return;
    }
    // 去重：SourceImage 的 imageBuilder 每次重建都会回报一次（同一张图的克隆）。
    // 若新克隆与当前持有的是同一底层位图，直接丢弃新克隆即可——否则每次重建都
    // dispose+重建会让 shader 的 sampler 绑定抖动（白闪一帧）。
    final ui.Image? current = _decoded;
    if (current != null && image.isCloneOf(current)) {
      image.dispose();
      return;
    }
    setState(() {
      current?.dispose();
      _decoded = image;
      _ready = true;
    });
  }

  @override
  void didUpdateWidget(covariant _UpscaleSourceGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换图（item 回收复用）时丢弃旧位图，等新图解码回调再驱动。
    if (oldWidget.url != widget.url) {
      _decoded?.dispose();
      _decoded = null;
      _ready = false;
    }
  }

  @override
  void dispose() {
    _decoded?.dispose();
    _decoded = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui.Image? decoded = _decoded;
    // 未解码完成：显示 SourceImage 本体（占位 / 错误 / 重试都在它内部）。
    // 注意此时它仍在加载并解码，解码完成后经 onImageDecoded 通知本 State。
    if (!_ready || decoded == null) {
      return SourceImage(
        url: widget.url,
        source: widget.source,
        refererOverride: widget.refererOverride,
        fit: widget.fit,
        width: widget.width,
        decodeCapWidthPx: widget.decodeCapWidthPx,
        placeholder: widget.placeholder,
        onLoadComplete: widget.onLoadComplete,
        onImageInfo: widget.onImageInfo,
        onImageDecoded: _onDecoded,
      );
    }
    // 已解码：交给超分渲染（同一张位图，无重复下载/解码）。
    return MangaUpscaledImage(
      image: decoded,
      mode: widget.mode,
      fit: widget.fit,
      width: widget.width,
    );
  }
}

/// 缩放矩阵的平移夹取（中心原点坐标系，配合 [MangaPageImage] 的
/// `Transform(alignment: Alignment.center)`）。屏幕侧 [didChangeMetrics] 与
/// [MangaPageImageState] 手势共用，避免两处逻辑漂移。
///
/// - scale ≤ ~1.001：平移清零，图片居中（缩回 1x 不残留起手平移）。
/// - scale > 1：平移夹紧到「图片至少贴合视口」，避免放大后拖出屏幕。
/// 上界以视口尺寸为准（fitWidth / fitHeight 下图片宽高 ≈ 视口），足矣阻止出屏。
Matrix4 _clampZoomMatrix(Matrix4 m, Size vp) {
  final double s = m.getMaxScaleOnAxis();
  if (s <= 1.001) {
    m.setTranslationRaw(0, 0, 0);
    return m;
  }
  final double maxX = (s - 1) * vp.width / 2;
  final double maxY = (s - 1) * vp.height / 2;
  double tx = m.getTranslation().x;
  double ty = m.getTranslation().y;
  tx = tx.clamp(-maxX, maxX);
  ty = ty.clamp(-maxY, maxY);
  m.setTranslationRaw(tx, ty, 0);
  return m;
}

/// 条漫缩放矩阵平移夹取（外层 Transform 围绕视口中心放大整条列表）：
/// 横向按图片宽度（≈ 视口宽 × s）精确夹取、贴边即停；纵向在列表滚动到边界时
/// 转矩阵平移（放大内容的屏幕外部分），精确上界需列表总高，用「视口高 × 缩放
/// 余量」大值兜底——保证放大后能拖到长条图的任意纵向位置。
Matrix4 _clampWebtoonZoomMatrix(Matrix4 m, Size vp,
    [double? realContentHeight]) {
  final double s = m.getMaxScaleOnAxis();
  if (s <= 1.001) {
    m.setTranslationRaw(0, 0, 0);
    return m;
  }
  final double maxX = (s - 1) * vp.width / 2;
  // 纵向：已知当前页真实布局高度（fitWidth 下 height × s）则精确夹取到长条图
  // 任意纵向位置；未知（该页从未加载）回退经验值（视口高 × 8）。
  final double maxY =
      realContentHeight != null && realContentHeight * s > vp.height
          ? (realContentHeight * s - vp.height) / 2
          : (s - 1) * vp.height * 8;
  double tx = m.getTranslation().x;
  double ty = m.getTranslation().y;
  tx = tx.clamp(-maxX, maxX);
  ty = ty.clamp(-maxY, maxY);
  m.setTranslationRaw(tx, ty, 0);
  return m;
}

/// 关闭阅读器内所有滚动组件的「回弹」（橡皮筋）与 overscroll 发光指示器。
///
/// 配合各滚动组件显式声明的 `PageScrollPhysics().applyTo(ClampingScrollPhysics())`，
/// 既保留条漫逐图吸附 / 翻页分页，又在边界夹紧、不再回弹。
class _NoOverscrollBehavior extends ScrollBehavior {
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;
}
