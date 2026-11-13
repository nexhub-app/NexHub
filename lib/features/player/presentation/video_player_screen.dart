import 'dart:async';
import 'dart:convert';

import 'package:canvas_danmaku/canvas_danmaku.dart' as cd;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' show AudioTrack;
import 'package:nexhub/generated/app_localizations.dart';
import 'package:hive/hive.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/async_session.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/danmaku/bilibili_danmaku_service.dart';
import '../../../core/comic/image_favorite_manager.dart';
import '../../../core/danmaku/danmaku_repository.dart';
import '../../../core/danmaku/danmaku_settings.dart';
import '../../../core/danmaku/danmaku_settings_store.dart';
import '../../../core/danmaku/danmaku_source.dart';
import '../../../core/danmaku/dandanplay_service.dart';
import '../../../core/danmaku/dandanplay_auth.dart';
import '../../../core/download/download_manager.dart';
import '../../../core/favorites/favorites_manager.dart';
import '../../../core/async_session.dart';
import '../../../core/history/media_playback_position_manager.dart';
import '../../../core/history/media_watched_manager.dart';
import '../../../core/models/episode.dart';
import '../../../core/models/media_item.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/player/player_controller.dart';
import '../../../core/player/demuxer_cache_policy.dart';
import '../../../core/player/player_capability.dart';
import '../../../core/player/player_orientation.dart';
import '../../../core/player/audio_playback_service.dart';
import '../../../core/player/pip_actions_bridge.dart';
import '../../../core/player/play_queue_store.dart';
import '../../../core/player/subtitle_translation_controller.dart';
import '../../../core/navigation/app_page_route.dart';
import '../../../core/platform/harmony_continuation.dart';
import '../../../core/settings/general_settings.dart';
import '../../../core/settings/player_settings.dart';
import '../../../core/player/widgets/seek_bar.dart';
import '../../../core/resolver/builtin_resolver.dart'
    show clearResolvedVideoCache;
import '../../../core/resolver/webview_resolver.dart';
import '../../../core/scraper/media_api_service.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/services/media_server/media_server_models.dart';
import '../../../core/services/media_server/media_server_session.dart';
import '../../../core/services/media_server/media_server_settings.dart';
import '../../../core/stats/reading_session_recorder.dart';
import '../../../core/stats/stats_models.dart';
import '../../../core/stats/stats_repository.dart';
import '../../../core/widgets/web_favorite_action.dart';
import '../../verification/presentation/webview_verification_screen.dart';
import '../../../core/settings/danmaku_config.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/app_log.dart';
import '../../../core/local/local_content_manager.dart' show isDocUri;
import '../../../core/local/saf_bridge.dart' show resolveSafVideoFile;
import '../../../core/widgets/app_error_state.dart';
import '../../../core/player/player_runtime.dart';
import '../../../core/platform/ohos_public_storage.dart'
    show OhosPublicStorage, isOhosDocPath, ohosDocJoin, ohosDocToPlainPath;
import '../../../core/platform/ohos_storage_location_sheet.dart';
import '../../../core/platform/platform_service.dart';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:file_picker/file_picker.dart';
import 'package:cast/cast.dart';
import 'package:floating/floating.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../core/platform/brightness_compat.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/widgets/danmaku.dart';
import '../../../core/widgets/danmaku_overlay.dart';
import '../cast/cast_service.dart';
import 'danmaku_settings_sheet.dart';
import 'danmaku_source_sheet.dart';
import 'danmaku_match_sheet.dart';
import 'subtitle_panel.dart';
import 'translated_subtitle_overlay.dart';
import 'package:nexhub/core/widgets/app_alert_dialog.dart';
part 'video_player_gestures.dart';
part 'video_player_lines.dart';
part 'video_player_more_menu.dart';
part 'video_player_cast_pip.dart';
part 'video_player_sleep_timer.dart';
part 'video_player_info_stats.dart';
part 'video_player_screenshot.dart';
part 'video_player_danmaku_input.dart';
part 'video_player_widgets.dart';

/// 发送弹幕时可选择的预设颜色（与主流弹幕站一致）。
const List<Color> _danmakuPresetColors = <Color>[
  Colors.white,
  Colors.red,
  Colors.orange,
  Colors.yellow,
  Color(0xFF00E676), // 绿
  Color(0xFF40C4FF), // 青
  Colors.blue,
  Colors.purple,
  Color(0xFFFF4081), // 粉
];

/// 视频播放页（Phase 5）。
///
/// - 从源解析真实可播放地址（[MediaApiService.fetchVideoUrl]）
/// - [PlayerController] + [MediaKitBackend] 提供播放内核
/// - 自定义控件：播放/暂停/进度/锁定/连播/解码模式/音频通道/画面比例
/// - 弹幕覆盖层按视频进度注入（[DanmakuController] + [DanmakuOverlay]）
/// - 弹幕来源：弹弹play（签名 + 搜索匹配）→ Bilibili fallback
///
/// 本地模式（Task .B.2）：传入 [localUri] 时进入本地模式，跳过在线源解析，
/// 直接用 [Player] + [VideoController] 打开本地文件。本地模式下隐藏切换线路 /
/// 下一集等在线专属按钮，保留弹幕（可选）、进度记忆（用 [itemId] =
/// `'local_${file.path.hashCode}'`）、播放器设置。调用方需将 [itemId] 设为
/// `'local_${file.path.hashCode}'`，[episode] 可用文件名构造占位 Episode。
class VideoPlayerScreen extends StatefulWidget {
  final String title;
  final Episode episode;
  final String sourceId;
  final String itemId;

  /// 可选：全集列表（用于自动连播与上下集切换）。
  final List<Episode>? episodes;

  /// 可选：初始剧集索引（在 [episodes] 中的位置）。
  final int? initialEpisodeIndex;

  /// 可选：切集回调（外部刷新详情页状态时使用）。
  final ValueChanged<Episode>? onEpisodeChange;

  /// 可选：收藏类型（用于播放器内收藏按钮）。若提供则顶栏显示收藏按钮。
  final SourceType? favoriteType;

  /// 本地模式：本地视频文件路径（跳过在线源解析，直接打开）。
  final String? localUri;

  /// 直链播放地址（视频嗅探器等场景）：非空时跳过在线源解析，直接播放该 URL。
  final String? directUrl;

  /// 直链播放请求头（防盗链 Referer / UA 等；仅 [directUrl] 模式使用）。
  final Map<String, String>? directHeaders;

  /// 详情页 URL（用于收藏时透传，避免历史/收藏详情灰屏）。
  final String? detailUrl;

  /// 是否恢复上次播放位置（默认 true）。
  ///
  /// 由全局「记住播放/阅读位置」开关门控：关闭时打开即从头播放，
  /// 不跳到上次进度。
  final bool restoreProgress;

  /// 封面 URL（用于收藏时透传，避免收藏书架缺封面）。
  final String? coverUrl;

  /// 接续恢复：跳到指定播放位置（毫秒）。非空时覆盖本地保存的进度。
  final int? initialPositionMs;

  /// 接续恢复：起播后是否播放（对端暂停状态原样迁移）。
  final bool initialPlaying;

  /// 媒体服务器播放控制器：非空时为媒体服务器直连播放——
  /// 进度只上报服务器（不写本地历史 box，§2.5）、续播 seek 用服务器进度、
  /// 弹幕入口隐藏、退出兜底上报 Stopped 并按 ≥90% 标记已看；
  /// 持有整季播放列表，驱动播放器内上下集切换 / 选集 / 自动连播
  /// （切集时按需协商新集直连地址）。
  final MediaServerPlayback? mediaServerPlayback;

  const VideoPlayerScreen({
    super.key,
    required this.title,
    required this.episode,
    required this.sourceId,
    required this.itemId,
    this.episodes,
    this.initialEpisodeIndex,
    this.onEpisodeChange,
    this.favoriteType,
    this.localUri,
    this.directUrl,
    this.directHeaders,
    this.detailUrl,
    this.coverUrl,
    this.restoreProgress = true,
    this.initialPositionMs,
    this.initialPlaying = true,
    this.mediaServerPlayback,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen>
    with WidgetsBindingObserver {
  // 注意：_controller 不在 initState 同步创建，而是在 _init() 中、等上一次播放器
  // 原生释放完成后再创建。否则新 Player 的 mpv 上下文会与尚未释放的旧 surface
  // 重叠，连续多次打开会在第三次冲突杀进程（Lost connection to device）。
  late final PlayerController _controller;
  bool _controllerCreated = false;
  bool _playingBeforeBackground = false; // 进后台前是否在播放（用于回前台恢复）
  VideoController? _videoController;

  final DanmakuController _danmakuController = DanmakuController();
  final GlobalKey<DanmakuOverlayState> _danmakuKey =
      GlobalKey<DanmakuOverlayState>();
  DanmakuSettings _danmakuSettings = const DanmakuSettings();
  DanmakuRepository? _danmakuRepo;
  bool _danmakuOn = true;

  /// 视频实时翻译控制器（视频实时翻译功能）：字幕轨文本轮询翻译 +
  /// 无字幕时画面 OCR 兜底，译文由 [TranslatedSubtitleOverlay] 渲染。
  final SubtitleTranslationController _subtitleTranslator =
      SubtitleTranslationController();

  /// 是否为本地文件 / 直链模式（跳过在线源解析，直接打开给定地址）。
  bool get _isDirectMode => widget.localUri != null || widget.directUrl != null;

  /// 是否为媒体服务器播放（进度只走服务器、弹幕入口隐藏）。
  bool get _isMediaServer => widget.mediaServerPlayback != null;

  /// 当前集的上报会话（媒体服务器播放；切集时重建）。
  MediaServerPlaybackSession? _serverSession;

  /// 当前集最近一次协商结果（音轨选择的数据源）。
  PlaybackInfoResult? _serverLastInfo;

  /// 转码流当前音轨序号（null = 服务器默认）。
  int? _serverAudioStreamIndex;

  /// 当前弹幕源（持久化到 SharedPreferences，键 `danmaku_source`）。
  DanmakuSourceType _danmakuSource = DanmakuSourceType.dandanplay;

  /// SharedPreferences 中保存弹幕源选择的键。
  static const String _kDanmakuSourceKey = 'danmaku_source';

  /// #6 -#6: 自定义弹幕 URL（持久化键 `danmaku_custom_url`）。
  String _customDanmakuUrl = '';

  /// #6 -#6: SharedPreferences 中保存自定义 URL 的键。
  static const String _kDanmakuCustomUrlKey = 'danmaku_custom_url';

  /// 旧方案遗留键（文件 + SharedPreferencesAsync）。仅用于一次性迁移，
  /// 迁移后播放器统一写入与全局页共用的 `danmaku_display_settings_v1`。
  static const String _kLegacyDanmakuSettingsKey = 'danmaku_settings';

  /// 每集手动 / 即时匹配得到的 dandanplay episodeId 覆盖（键 = 剧集 id）。
  /// 用于自动匹配失败时的兜底，以及用户从「手动匹配」面板指定。
  final Map<String, int> _dandanOverride = <String, int>{};

  /// Current playable URL (used for sharing).
  String? _playUrl;

  /// 自定义截图保存目录（空 = 默认 Documents/screenshots）。
  String? _customScreenshotDir;

  /// 当前播放地址所需的 HTTP 请求头（反盗链 Referer / UA 等），
  /// 与解析抓取 m3u8 文本时一致；打开地址（mpv 拉分片）必须带上，
  /// 否则 CDN 返回 403、解不出帧、画面全黑。
  Map<String, String>? _playHeaders;

  /// Sleep timer for auto-pausing playback.
  Timer? _sleepTimer;

  /// 当前按分钟定时的分钟数（面板回显选中态；按集数模式见 _sleepEpisodesRemaining）。
  int? _sleepTimerMinutes;

  /// 睡眠定时「按集数」模式：再播 N 集后暂停（0 = 未启用）。
  /// 与按分钟模式互斥，跨集保留（配合 ）；播完一集递减，归零暂停。
  int _sleepEpisodesRemaining = 0;

  /// 自动连播倒计时：播完一集后按设置的秒数延迟连播，期间底部
  /// SnackBar 实时显示剩余秒数并可取消；0（未配置）时保持立即连播。
  Timer? _autoNextCountdownTimer;

  /// 倒计时剩余秒数（SnackBar 内容实时刷新用）。
  final ValueNotifier<int> _autoNextCountdownLeft = ValueNotifier<int>(0);

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<void>? _stallSub;
  StreamSubscription<String>? _decodeFallbackSub;

  /// 标记 widget 已进入 deactivate/dispose 流程。仅用 [mounted] 不够：
  /// Flutter 在 deactivate() 阶段元素已「失活」但 [mounted] 仍为 true，此时
  /// 访问依赖 InheritedWidget 的 [AppLocalizations.of]/[ScaffoldMessenger.of]
  /// 会抛「Looking up a deactivated widget's ancestor is unsafe」。
  /// 因此在 stall/position/completed 等异步回调入口用此标记二次兜底，
  /// 彻底避免播放在后台/退场瞬间的崩溃。
  bool _disposed = false;

  /// 下一集是否已预解析（进度>80% 时后台拉取地址写入 VideoSourceCache）。
  /// 切集时重置为 false。
  bool _nextEpisodePreloaded = false;

  /// 本次会话内已自动标记「已看」的剧集索引，避免对同一集重复触发
  /// `MediaWatchedManager.markWatched`（每集仅标记一次）。
  final Set<int> _watchedMarkedEpisodes = <int>{};

  Duration _position = Duration.zero;

  /// 可信的「最近一次非零播放位置」。用于重连时恢复到断流前的进度，
  /// 避免 open() 重置后若 [_position] 被瞬时的 0 位置事件覆盖而从头播放。
  Duration _lastGoodPosition = Duration.zero;

  /// 重连（stall 恢复）进行中标记，防止 stall 事件重入导致多次重连叠加。
  bool _reconnecting = false;

  /// 自动重连次数上限。超过后不再自动重连，改为提示用户手动重试，
  /// 避免「重连失败→又卡顿→又重连」的死循环。
  static const int _kMaxReconnectAttempts = 3;

  /// 已尝试的自动重连次数。达到上限后置位 [_reconnectExhausted]。
  int _reconnectAttempts = 0;

  /// 自动重连已耗尽：置位后由 UI 展示「视频链接已失效，点击重试」，用户手动触发
  /// 重新解析并重新打开播放器（拿到未过期的新直链）。
  bool _reconnectExhausted = false;

  // ─────────────── 缓存策略降级 / 分级重试 ───────────────

  /// demuxer 缓存档位解析器（移动网络 / 低内存自动降级）。
  final DemuxerCachePolicyResolver _cachePolicyResolver =
      DemuxerCachePolicyResolver();

  /// 网络变化订阅（蜂窝 ↔ Wi-Fi 切换时重算缓存档位）。
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  // ─────────────────────── 多源自动选源 / 故障回退 ───────────────────────

  /// 按「源 + 剧集」记忆用户手动选过的线路名（手动选源记忆）。
  final LineSelectionStore _lineStore = LineSelectionStore();

  /// 是否开启自动选线路（来自 PlayerSettings.autoSelectLine，_init 加载）。
  bool _autoSelectLine = true;

  /// 本集会话内已尝试过（含已失败）的候选线路索引。故障回退时只轮换未尝试过的，
  /// 避免反复跳回已确认不可用的线路形成死循环。
  final Set<int> _triedLineIndices = <int>{};

  /// 已持有「可直接播放直链」的候选线路索引。索引 0 永远是刚解析出的当前线路；
  /// 其它线路初始只是剧集页地址，经 [_resolveLineUrl] 重新解析后会加入本集合，
  /// 之后切回该线路无需再解析。
  final Set<int> _resolvedLineIndices = <int>{0};

  /// 当前会话在 [AudioPlaybackService] 的代次 token。
  /// 进集/切集 attach 刷新通知、dispose 时 detach（token 不符则忽略，
  /// 兼容 pushReplacement 跨作品换页时旧页迟到 detach）。
  int _bgToken = 0;

  /// 跨作品播放队列持久化。
  final PlayQueueStore _queueStore = PlayQueueStore();

  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _uiVisible = true;
  bool _isFav = false;

  /// 控制层（顶栏 / 底栏 / 中央按钮）自动隐藏计时器。
  ///
  /// 修复「视频已开始播放但暂停键 / 控制条一直挂在画面上」：播放中若约
  /// [_kUiAutoHide] 无任何交互，则自动隐藏控制层；暂停 / 锁定 / 用户点击时
  /// 重新显示并重置计时。
  Timer? _uiHideTimer;

  /// 控制层自动隐藏延时。
  static const Duration _kUiAutoHide = Duration(seconds: 4);

  /// 控制栏隐藏租约计数：拖动进度 / 打开菜单时递增，禁止自动隐藏；
  /// 释放归零后重启自动隐藏倒计时。
  int _panelHoldCount = 0;

  /// 持有控制栏：禁止自动隐藏（拖动进度条 / 菜单打开期间调用）。
  void _acquirePanelHold() {
    _panelHoldCount++;
    _uiHideTimer?.cancel();
  }

  /// 释放控制栏持有：计数归零且播放中时重启自动隐藏倒计时。
  void _releasePanelHold() {
    _panelHoldCount = (_panelHoldCount - 1).clamp(0, 1 << 30);
    if (_panelHoldCount == 0) {
      _scheduleUiHide();
    }
  }

  // ─────────────────────── 播放器设置（PlayerSettings 消费） ───────────────────────
  /// 全局播放器默认设置。_init 中从 PlayerSettingsStore 加载并应用到底层播放器。
  PlayerSettings _playerSettings = const PlayerSettings();

  /// 横滑 seek 倍率（来自 PlayerSettings.seekMultiplier，0.5/1.0/2.0）。
  double _seekMultiplierFactor = 1.0;

  // ─────────────────────── 视频比例 → 屏幕方向 ───────────────────────
  /// 当前视频宽高（媒体元数据上报；null/0 表示尚未就绪）。
  int? _videoWidth;
  int? _videoHeight;

  /// 本次媒体是否已按「跟随视频」自动判定过方向（每个媒体只判定一次，切集重置）。
  bool _autoOrientationApplied = false;

  /// 手动旋转覆盖的方向（null = 未覆盖）。会话内有效，不写持久化。
  List<DeviceOrientation>? _manualOrientationOverride;

  StreamSubscription<int?>? _videoWidthSub;
  StreamSubscription<int?>? _videoHeightSub;

  /// 订阅视频宽高事件，供「跟随视频」方向判定使用。
  /// 每次 _init 创建新 Player 时重新绑定（旧 Player 的流随旧控制器作废）。
  void _bindVideoOrientationTracking() {
    _videoWidthSub?.cancel();
    _videoHeightSub?.cancel();
    _videoWidth = null;
    _videoHeight = null;
    _autoOrientationApplied = false;
    _videoWidthSub = _controller.player.stream.width.listen((int? w) {
      if (_disposed) return;
      _videoWidth = (w != null && w > 0) ? w : null;
      unawaited(_maybeApplyVideoOrientation());
    });
    _videoHeightSub = _controller.player.stream.height.listen((int? h) {
      if (_disposed) return;
      _videoHeight = (h != null && h > 0) ? h : null;
      unawaited(_maybeApplyVideoOrientation());
    });
  }

  /// 宽高就绪后按「跟随视频」判定一次横竖屏；手动旋转过则不再自动判定。
  Future<void> _maybeApplyVideoOrientation() async {
    if (_disposed || !mounted) return;
    final int? w = _videoWidth;
    final int? h = _videoHeight;
    if (w == null || h == null) return;
    if (_autoOrientationApplied || _manualOrientationOverride != null) return;
    if (_playerSettings.lockOrientation != PlayerLockOrientation.followVideo) {
      return;
    }
    final bool isPhone = MediaQuery.of(context).size.shortestSide < 600;
    final List<DeviceOrientation>? orients = resolvePlayerOrientations(
      mode: PlayerLockOrientation.followVideo,
      isPhone: isPhone,
      videoWidth: w,
      videoHeight: h,
    );
    if (orients == null) return;
    _autoOrientationApplied = true;
    _controller.setBaseOrientations(orients);
    if (!isPhone || !PlatformService.instance.isMobile) return;
    try {
      await SystemChrome.setPreferredOrientations(orients);
    } on Object {
      // 平台不支持，忽略。
    }
  }

  /// 手动旋转（底部栏按钮）：锁到与当前方向相反的方向，会话内覆盖自动判定。
  Future<void> _rotateOrientation() async {
    final bool isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final List<DeviceOrientation> orients = isPortrait
        ? const <DeviceOrientation>[
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]
        : const <DeviceOrientation>[DeviceOrientation.portraitUp];
    _manualOrientationOverride = orients;
    _controller.setBaseOrientations(orients);
    if (!PlatformService.instance.isMobile) return;
    try {
      await SystemChrome.setPreferredOrientations(orients);
    } on Object {
      // 平台不支持，忽略。
    }
  }

  // ─────────────────────── 解析进度条（功能3） ───────────────────────
  /// 解析进度 notifier（null=隐藏）。放 State 而非 PlayerController：_initFuture
  /// 转圈帧时 _controller 尚未创建，State 级 notifier 可安全在加载态渲染。
  final ValueNotifier<double?> _resolveProgress = ValueNotifier<double?>(null);

  // ─────────────────────── 缓冲加载动画（功能2） ───────────────────────
  bool _isBuffering = false;
  StreamSubscription<bool>? _bufferingSub;

  /// 实时缓冲网速文本（缓冲时显示在转圈下方；null = 不可用）。
  String? _bufferingSpeedText;

  /// 网速轮询定时器（仅缓冲期间运行，500ms 读一次 mpv `cache-speed`）。
  Timer? _speedProbeTimer;

  /// 开始轮询网速：读 mpv `cache-speed`（KB/s）格式化为 MB/s 显示。
  /// 平台不支持（返回 null）时保持隐藏，不影响播放。
  void _startSpeedProbe() {
    _stopSpeedProbe();
    _speedProbeTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_disposed || !mounted) return;
      unawaited(_probeCacheSpeed());
    });
    unawaited(_probeCacheSpeed());
  }

  Future<void> _probeCacheSpeed() async {
    try {
      final String? raw = await _controller.backend.getProperty('cache-speed');
      if (_disposed || !mounted) return;
      if (raw == null || raw.isEmpty) {
        if (_bufferingSpeedText != null) {
          setState(() => _bufferingSpeedText = null);
        }
        return;
      }
      final double kbps = double.tryParse(raw.trim()) ?? 0;
      final String text = kbps >= 1024
          ? '${(kbps / 1024).toStringAsFixed(1)} MB/s'
          : '${kbps.round()} KB/s';
      if (_bufferingSpeedText != text) {
        setState(() => _bufferingSpeedText = text);
      }
    } on Object {
      // 属性读取失败（平台不支持）静默忽略。
    }
  }

  void _stopSpeedProbe() {
    _speedProbeTimer?.cancel();
    _speedProbeTimer = null;
    if (_bufferingSpeedText != null) {
      _bufferingSpeedText = null;
    }
  }

  /// 播放状态订阅：订阅底层 playing 流同步 [_isPlaying]，
  /// 避免「视频已开始播放但中央大播放按钮仍显示」「缓冲转圈不消失」等 UI 滞后。
  StreamSubscription<bool>? _playingSub;

  /// 暂停事件去抖：mpv 暂停→播放瞬间可能抖出瞬态 false，延迟确认防误闪。
  Timer? _playingFalseDebounce;

  /// 「播放自动全屏」每媒体一次的闸：打开新媒体（进播放器 / 切集）时重置，
  /// 起播后首次 playing=true 触发进入全屏；此后暂停续播不再强制进入。
  bool _autoFullscreenDone = false;

  /// 应用播放/暂停态到 UI（playingStream 事件确认后调用）。
  void _applyPlayingState(bool p) {
    if (!mounted) return;
    setState(() {
      _isPlaying = p;
      // 暂停时控制层常显（用户需要看到播放键 / 进度条）。
      // PiP 小窗内例外：小窗放不下控制层，强制显示会铺满整个小窗。
      if (!p && !_inPip) _uiVisible = true;
    });
    // 鸿蒙 PiP 控制面板的播放/暂停按钮图标随实际播放态同步（Android 通道
    // 无此需求——动作列表进入时下发；该调用在 Android 原生侧无实现，静默无效）。
    if (PlatformService.instance.isOHOS) {
      // 动态调用：官方 floating 无此方法（鸿蒙适配 fork 新增），仅鸿蒙分支会执行。
      unawaited((Floating() as dynamic).updatePipControlStatus(playing: p));
    }
    // 播放 → 启动自动隐藏倒计时；暂停 → 取消倒计时保持常显。
    if (p) {
      _scheduleUiHide();
    } else {
      _uiHideTimer?.cancel();
    }
  }

  /// 播放自动全屏：起播即进入全屏（沿用原全屏按钮语义——锁定横屏 + 沉浸式）。
  /// 每次打开新媒体只触发一次；PiP 小窗（Android 系统 PiP / 桌面 PiP）内不
  /// 触发，避免在小窗中切换方向 / 隐藏系统 UI。
  void _autoEnterFullscreenIfNeeded() {
    if (_autoFullscreenDone) return;
    _autoFullscreenDone = true;
    if (_inPip || _desktopPipActive) return;
    if (_controller.isFullscreen) return;
    unawaited(_controller.toggleFullscreen());
  }

  // ─────────────────────── 长按倍速（功能4） ───────────────────────
  /// 长按加速前的原倍速，松手恢复。
  double _speedBeforeLongPress = 1.0;

  // ─────────────────────── 手势 / 亮度 / 音量（+ 视频还原） ───────────────────────

  /// 当前手势轴（横滑 / 左竖滑 / 右竖滑），锁定后直到 onEnd 才重置。
  _GestureAxis _dragAxis = _GestureAxis.none;

  /// 手势起点系统亮度（0..1），用于左竖滑按 delta 计算新亮度。
  double _dragStartBrightness = 0;

  /// 手势起点播放器音量（0..100），用于右竖滑按 delta 计算新音量。
  double _dragStartVolume = 50;

  /// 横滑 seek 预览目标时间，松手后跳转。
  Duration _seekPreview = Duration.zero;

  /// 横滑起点指针全局 Y，用于计算拖动中的垂直位移。
  double _seekDragStartY = 0;

  /// 横滑过程中指针相对起点的垂直位移（上滑取消 seek，超阈值标记取消）。
  ///
  /// 注意：不能累加 dragUpdate.delta.dy——HorizontalDragGestureRecognizer
  /// 传给回调的 delta 被框架按主轴过滤为 Offset(dx, 0)，dy 恒为 0，累加它
  /// 会让取消判定永远不触发。只能用 globalPosition.dy 与起点的差值。
  double _seekDragVerticalDelta = 0;

  /// 本次横滑是否已被上滑取消（松手不跳转）。
  bool _seekDragCancelled = false;

  /// 本次拖动是否已给过取消震动（仅首次进入取消态震动一次）。
  bool _seekDragCancelledFeedback = false;

  /// 上滑判定阈值（逻辑像素）：横滑中垂直位移超过该值视为「上滑取消」。
  /// 24px ≈ 0.6cm 物理位移，保留对自然抖动的防误触。
  /// （此前降阈值无效——旧实现累加的 delta.dy 恒为 0，与阈值大小无关，
  /// 见 [_seekDragVerticalDelta] 注释。）
  static const double _kSeekCancelThreshold = 24;

  /// 上次双击的时刻（防抖：双击后 600ms 内屏蔽单击，防三分区误触）。
  DateTime _lastDoubleTapAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 连续双击累积次数（10s→20s→30s，900ms 无后续双击或换方向则重置）。
  int _doubleTapCount = 1;

  /// 双击方向（-1 快退 / 1 快进 / 0 中间播放暂停）。
  int _doubleTapDirection = 0;

  /// 当前系统亮度缓存（init 时从 [ScreenBrightness.instance.application] 读取）。
  double _brightness = 0.5;

  /// 手势指示器当前展示的内容（任一非 null 即显示对应数值）。
  String? _gestureIndicatorText;

  /// 手势指示器可见性（[AnimatedOpacity] 驱动）。
  bool _gestureIndicatorVisible = false;

  /// 手势指示器自动淡出计时器（约 800ms）。
  Timer? _gestureIndicatorTimer;

  /// 上次自动保存播放位置的时间（节流，每 5 秒存一次）。
  DateTime _lastPositionSaveAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 媒体服务器进度上报节流状态（仅 [VideoPlayerScreen.mediaServerSession]
  /// 非空时使用）：上次心跳时间 / 上次暂停态 / 上报位置，用于检测 seek 跳变。
  DateTime _lastServerReportAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _lastServerPaused = false;
  int _lastServerReportedMs = 0;

  /// 上次 setState 刷新 UI 的时间：position 流约 4–10Hz，整页重建
  /// 开销大（含 Marquee / SeekBar / 手势层）；节流到 ~250ms 后 UI 仍平滑，
  /// 但重建频率显著下降。
  DateTime? _lastPositionUiAt;

  // ── 跳过片头片尾（按作品记忆，经 EpisodePlayerSettingsStore）──

  /// 片头结束点（秒，null = 未设置）。位置进入 [2s, opEnd-1s] 显示
  /// 「跳过片头」按钮；开启自动跳过时直接 seek 过去。
  int? _skipOpEndSec;

  /// 片尾开始点（秒，null = 未设置）。位置进入 [edStart, edStart+8s] 显示
  /// 「跳过片尾」按钮。
  int? _skipEdStartSec;

  /// 自动跳过开关（与片头/片尾点一起按作品持久化）。
  bool _skipAuto = false;

  /// 本集是否已跳过片头/片尾（手动或自动，防止重复跳/循环跳）。
  bool _opSkippedThisEpisode = false;
  bool _edSkippedThisEpisode = false;

  /// 播放位置管理器缓存。
  ///
  /// deactivate 之后 context 已失活，dispose 里再调 `context.read` 会抛
  /// 「Looking up a deactivated widget's ancestor is unsafe」并被 catch 吞掉，
  /// 导致退出前最后 ≤5s 的进度丢失。因此 _init 阶段（context 有效时）读取并
  /// 缓存到 State 字段，[_maybeSavePosition] / [_saveCurrentPosition] 一律走
  /// 缓存引用写盘，dispose 期也能可靠保存。
  MediaPlaybackPositionManager? _positionManager;

  /// 当前集「续播位置恢复」是否已完成（成功 seek / 无记录 / 放弃）。
  ///
  /// 修复「记住播放进度没作用」：媒体刚 open 时会立刻推送 position=0 的事件，
  /// 若此时就允许写盘，上一次的存档会被 0 覆盖，之后再怎么恢复也拿不到值。
  /// 因此恢复完成前一律不保存位置。切集时重置为 false。
  bool _positionRestoreDone = false;

  /// 跨设备接续持有者 token（null = 未注册，如本地 / 直链播放）。
  Object? _continuationToken;

  /// 当前剧集索引（若有全集列表）。
  late int _episodeIndex;

  /// 切集代次守卫：快速连播 / 手动切集并发时，丢弃过期切换，
  /// 避免较慢的解析/打开覆盖已切换的集（表现为「切集还是同一集」）。
  final AsyncSession _loadSession = AsyncSession();

  /// 当前选中的播放线路名（来自 [Episode.lineName]）。由 [widget.episode]
  /// 初始化，切换剧集时跟随新 ep 同步。
  /// 详情页 chips（全部/天堂/精品/暴风/量子）选中后，`_openContent` 传入的
  /// `ep.lineName` 就是该选择，本字段在播放器内跟踪并驱动"播放线路"面板
  /// 的选中态；线路面板里点线路只切换要显示的集分组，不立即解析。
  String? _selectedLine;

  late Future<void> _initFuture;

  final CastService _castService = CastService();
  bool _isCasting = false;

  // 投屏位置同步与断开事件订阅。
  StreamSubscription<Duration>? _castPositionSub;
  StreamSubscription<Object>? _castErrorSub;
  Duration _castPosition = Duration.zero;

  /// 键盘焦点节点（键盘快捷键）。
  final FocusNode _focusNode = FocusNode();

  /// 屏幕亮度插件实例（手势调节系统亮度）。
  final BrightnessCompat _brightnessPlugin = BrightnessCompat();

  /// 进入 PiP 时的播放位置（退出时若进度被系统回收则续播）。
  Duration _pipEnterPosition = Duration.zero;

  /// 是否处于系统 PiP 中：进出事件由原生 onPictureInPictureModeChanged
  /// 经 nexhub/pip_events 推送（pip:enabled / pip:disabled）。
  bool _inPip = false;

  /// 桌面 PiP 模式（改用 window_manager）：隐藏标题栏 + 缩小窗口置顶播放。
  bool _desktopPipActive = false;

  /// 进入桌面 PiP 前保存的窗口状态（位置 / 大小 / 最大化 / 标题），退出时恢复。
  Offset _savedWindowPos = Offset.zero;
  Size _savedWindowSize = const Size(1280, 720);
  bool _savedWindowMaximized = false;
  String _savedWindowTitle = 'nexhub';

  /// 桌面 PiP 进出串行化：异步期间再次点击直接忽略，防止把 PiP 小窗尺寸
  /// 存成「原始尺寸」或恢复到中间态。
  bool _pipSwitching = false;

  /// PiP 窗口动作点击订阅（`action:<id>` 事件）。
  StreamSubscription<String>? _pipActionSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 首帧后把默认弹幕设置（字号/不透明度/区域）同步到弹幕层，
    // 否则覆盖层会沿用 canvas_danmaku 的默认值（区域=全屏、字号=16）。
    // 注意：此时 _controller 尚未创建（在 _init 中等旧播放器释放后才建），
    // _applyDanmakuOption 内部读取 _controller.playbackSpeed 已用 try/catch 兜底。
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyDanmakuOption());
    _episodeIndex = widget.initialEpisodeIndex ?? 0;
    // 详情页 chips 选中的线路名会透传到 widget.episode.lineName（chips
    // 过滤后的 ep 副本），未提供时退化为 null 表示"未分组 / 全部"。
    _selectedLine = widget.episode.lineName;
    _initFuture = _init();
    // 跨设备接续：在线播放注册快照（本地文件 / 直链 / 媒体服务器对端无法重现）。
    if (!_isDirectMode && !_isMediaServer && widget.sourceId.isNotEmpty) {
      _continuationToken =
          HarmonyContinuation.attach(_buildContinuationSnapshot);
    }
    // 阅读/观看时长统计 —— 仅在有效 sourceId 时启用（本地模式不计入跨源时长）。
    if (widget.sourceId.isNotEmpty) {
      unawaited(ReadingSessionRecorder.instance.begin(
        workId: widget.itemId,
        sourceId: widget.sourceId,
        type: StatsMediaType.media,
        title: widget.title,
        coverUrl: widget.coverUrl,
        lastChapterTitle: widget.episode.id,
      ));
    }
  }

  /// 后台播放：进后台不主动暂停，依赖前台媒体服务保活；回到前台若
  /// 此前在播且被视频表面销毁误暂停，则恢复播放。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!_controllerCreated) return;
    if (state == AppLifecycleState.paused) {
      _playingBeforeBackground = _controller.isPlaying;
    } else if (state == AppLifecycleState.resumed) {
      if (_playingBeforeBackground && !_controller.isPlaying) {
        unawaited(_controller.play());
      }
      _playingBeforeBackground = false;
    }
  }

  /// PlayerController 状态变更（字幕显隐 / 全屏 / 音量 / 线路）触发 UI 重建。
  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// 为视频结果附加播放所需请求头（Referer / UA 等），与源反盗链配置一致。
  ///
  /// 直连解析的视频会由 [builtin_resolver] 的 [_withVideoHeaders] 自动附加头；
  /// 但 WebView 抽取路径拿到的是裸直链，需在此补齐，否则 CDN 返回 403 黑屏。
  Map<String, String> _videoHeadersFor(PluginConfig source) {
    final ah = source.antiHotlinking;
    final headers = <String, String>{};
    if (ah.userAgent != null && ah.userAgent!.isNotEmpty) {
      headers['User-Agent'] = ah.userAgent!;
    }
    final referer = ah.referer ?? source.site.baseUrl;
    if (referer != null && referer.isNotEmpty) {
      headers['Referer'] = referer;
    }
    if (ah.headers != null) headers.addAll(ah.headers!);
    return headers;
  }

  /// 解析视频地址。
  ///
  /// 默认「自动嗅探优先」：直接加载剧集播放页，靠通用嗅探链路
  /// （JS 钩子 fetch/XHR/HTMLMediaElement/MediaSource + 网络拦截 + DOM 扫描）
  /// 捕获网站真实视频直链——不依赖源写死的 selectors/script，适配加密 player、
  /// MacCMS 等手动解析失败的站点。捕获到 http 直链即作为解析结果返回。
  ///
  /// 嗅探未捕获到直链（超时/页面不自动播放等）时，回退到源声明的手动解析：
  /// - webview-html：弹出内嵌 WebView 取回渲染 HTML 回填重试；
  /// - video 路由 `webview` + jsExtractor：弹出 WebView 执行脚本抽到真实直链；
  /// - 普通 selectors/script：离线解析。
  Future<VideoResult> _resolveVideoWithCapture(
    MediaApiService service,
    PluginConfig source,
    String episodeUrl, {
    String? renderedHtml,
  }) async {
    // 解析进度条（功能3）：仅最外层调用写入进度，递归（renderedHtml 非空）不重复写。
    final isOuter = renderedHtml == null;
    if (isOuter) _resolveProgress.value = 0.05;
    try {
      // 0) 脚本型视频路由（hybrid + video override type=='script'）脚本自带
      // 确定性解析（直连抓播放页 + 字符串抽取），无需 WebView 嗅探。
      // 优先走脚本：省去嗅探最坏 12s 的等待，也避开 Windows 内嵌浏览器
      // 频繁创建/销毁的崩溃高发区（Lost connection to device）。
      // 脚本失败（站点改版/网络异常）再落回下方通用嗅探链路，安全网不丢。
      if (isOuter &&
          source.parser.type == 'hybrid' &&
          source.parser.overrides?['video']?.type == 'script') {
        if (isOuter) _resolveProgress.value = 0.5;
        try {
          final scriptResult = await service.fetchVideoUrl(source, episodeUrl);
          // 脚本「成功返回但产出空直链」（meta 预取失败/站点改版）同样视为
          // 解析失败：直接 open('') 必然黑屏报错，落回下方嗅探链路才有救。
          if (scriptResult.url.isNotEmpty) return scriptResult;
        } on Object {
          // 脚本解析失败 → 落回嗅探优先的通用流程（下方步骤 1/2）。
        }
      }
      // 1) 自动嗅探优先（网站视频通用捕获，与源无关）
      final pageUrl = _absolutePageUrl(source, episodeUrl);
      if (pageUrl != null) {
        try {
          final outcome = await navigateToSnifferCapture(
            context,
            url: pageUrl,
            // 15s：慢链路（MacCMS 播放页 → 跨域播放器 iframe → hls.js）
            // 实测可到 10s+，12s 会把本可命中的嗅探掐死在 iframe 加载期；
            // 捕获即提前返回，不会拖慢正常页面。
            timeout: const Duration(seconds: 15),
            autoPopOnTimeout: true,
          );
          if (outcome?.hasExtractedUrl == true &&
              outcome!.extractedUrl != null) {
            return _capturedVideoResult(source, outcome);
          }
        } on Object {
          // 嗅探自身异常（如 WebView 不可用），落回手动解析
        }
      }
      if (isOuter) _resolveProgress.value = 0.5;
      // 2) 嗅探未命中 → 回退源声明的手动解析
      try {
        return await service.fetchVideoUrl(source, episodeUrl,
            renderedHtml: renderedHtml);
      } on WebViewHtmlRequest catch (e) {
        if (!mounted) rethrow;
        final outcome = await navigateToHtmlCapture(context, request: e);
        if (outcome?.hasRenderedHtml == true) {
          return _resolveVideoWithCapture(
            service,
            source,
            episodeUrl,
            renderedHtml: outcome!.renderedHtml,
          );
        }
        if (outcome?.hasExtractedUrl == true && outcome!.extractedUrl != null) {
          return _capturedVideoResult(source, outcome);
        }
        throw Exception('video capture cancelled');
      } on WebViewExtractionRequest catch (e) {
        if (!mounted) rethrow;
        final outcome = await navigateToExtraction(context, request: e);
        if (outcome?.hasExtractedUrl == true && outcome!.extractedUrl != null) {
          return _capturedVideoResult(source, outcome);
        }
        throw Exception('video extraction cancelled');
      }
    } finally {
      if (isOuter) _resolveProgress.value = null;
    }
  }

  /// 将 WebView 抽取 / 嗅探回传的裸直链包装为可播放结果（补齐防盗链头）。
  ///
  /// 头优先级：源 antiHotlinking 配置（含 site.baseUrl 兜底的 Referer）优先；
  /// 仅当配置未产出 Referer 时，才用嗅探捕获时记录的 [WebViewExtractionOutcome.extractedReferer]。
  VideoResult _capturedVideoResult(
      PluginConfig source, WebViewExtractionOutcome outcome) {
    final url = outcome.extractedUrl!;
    final type = url.toLowerCase().contains('m3u8') ? 'm3u8' : null;
    final headers = _videoHeadersFor(source);
    final ref = outcome.extractedReferer;
    if (ref != null && ref.isNotEmpty) {
      // 抽取直链与源站不同域时（第三方解析站/CDN），源站防盗链 Referer 对该域
      // 无效甚至致 403（解析站按 Referer 白名单校验分片请求）——改用捕获页面
      // 自身的 Referer，与浏览器在该页直接播放时的请求头一致。
      final urlHost = Uri.tryParse(url)?.host ?? '';
      final sourceHost = Uri.tryParse(source.site.baseUrl ?? '')?.host ?? '';
      final refHost = Uri.tryParse(ref)?.host ?? '';
      final crossHost = urlHost.isNotEmpty &&
          sourceHost.isNotEmpty &&
          urlHost != sourceHost &&
          refHost.isNotEmpty;
      if (crossHost || !headers.containsKey('Referer')) {
        headers['Referer'] = ref;
      }
    }
    return VideoResult(
      url: url,
      type: type,
      headers: headers.isNotEmpty ? headers : null,
    );
  }

  /// 把剧集 URL 解析为绝对页面地址（相对路径按源 baseUrl 补全；无法补全返回 null）。
  String? _absolutePageUrl(PluginConfig source, String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final base = source.site.baseUrl;
    if (base == null || base.isEmpty) return null;
    return Uri.tryParse(base)?.resolve(url).toString();
  }

  /// 打开媒体后起播。跨设备接续恢复对端的暂停状态时不自动播放。
  void _startPlayback() {
    if (widget.initialPlaying) {
      unawaited(_controller.play());
    }
  }

  /// 跨设备接续快照：内容标识 + 当前集 + 播放位置/状态。
  ///
  /// 仅在在线播放（有 sourceId）且播放器已创建时注册，见 [initState]。
  Map<String, Object?>? _buildContinuationSnapshot() {
    if (!_controllerCreated || _disposed) return null;
    final List<Episode>? episodes = widget.episodes;
    final Episode current = (episodes != null &&
            _episodeIndex >= 0 &&
            _episodeIndex < episodes.length)
        ? episodes[_episodeIndex]
        : widget.episode;
    final ({List<Map<String, dynamic>> items, int start})? window =
        HarmonyContinuation.encodeChapterWindow(episodes, _episodeIndex);
    return <String, Object?>{
      'type': 'video',
      'title': widget.title,
      'sourceId': widget.sourceId,
      'contentId': widget.itemId,
      'chapterIndex': _episodeIndex,
      'episode': current.toJson(),
      if (window != null) 'episodes': window.items,
      if (window != null) 'episodeStart': window.start,
      'positionMs': _position.inMilliseconds,
      'playing': _isPlaying,
      if (widget.detailUrl != null) 'detailUrl': widget.detailUrl,
      if (widget.coverUrl != null) 'coverUrl': widget.coverUrl,
    };
  }

  Future<void> _init() async {
    // 鸿蒙阶段 4 前无播放内核（media_kit/libmpv）：不得创建 Player 与
    // VideoController（原生库缺失会异常），直接走统一错误页展示降级提示。
    if (!PlayerRuntime.available) {
      throw const PlayerUnavailableException();
    }
    // 本次打开视为一次新的「播放自动全屏」机会（手动重试路径复用 _init）。
    _autoFullscreenDone = false;
    // 缓存播放位置管理器引用：context 仅在页面存活期有效，dispose 时
    // 已失活无法 context.read；提前缓存后保存进度在任何时刻（含退出瞬间）可靠。
    try {
      _positionManager = context.read<MediaPlaybackPositionManager>();
    } on Object {
      _positionManager = null;
    }

    // 优先恢复弹幕相关持久化设置（源选择 / 显示设置 / 自定义 URL）。
    // 必须放在视频打开之前：一旦视频解析或打开抛异常，_init 后续代码不会执行，
    // 设置就会永远停留在默认值，表现为「退出重进无法保持」。
    await _loadDanmakuSourcePref();

    // 加载全局播放器默认设置（解码/音频/比例/倍速/音量/方向/手势等）。
    // 在创建 Player 之前加载，创建后立即应用到底层播放器。
    await _loadPlayerSettings();

    // 记录当前作品为「最近播放」，用于启动恢复「继续上次」。
    // 媒体服务器条目不进本地记录体系（§2.5）。
    if (!_isMediaServer) {
      unawaited(_persistCurrentEpisode(_episodeIndex));
    }

    // 创建 Player + VideoController 并打开媒体。
    // 关键：先等待上一次播放器的原生 VideoOutput 释放完成（见 PlayerController.pendingDisposal），
    // 再把「新 Player」创建出来。Player 的 mpv 上下文与原生视频纹理是崩溃高发点，
    // 必须保证「旧播放器完全销毁」先于「新播放器创建」，否则连续多次打开会在
    // 第三次冲突杀进程（Lost connection to device）。
    // 重试路径：上一次 _init 已创建播放器但中途失败（如 open 超时），旧实例
    // 尚未释放。先释放旧实例（写入 pendingDisposal），再等其原生释放完成后再建新实例，
    // 避免旧 Player 泄漏、及「新建 surface 与旧 surface 冲突」崩溃。
    // 关键：先等待上一次播放器的原生 VideoOutput 释放完成，再把「新 Player」
    // 创建出来。Player 的 mpv 上下文与原生视频纹理是崩溃高发点，必须保证
    // 「旧播放器完全销毁」先于「新播放器创建」，否则连续多次打开会在第三次
    // 冲突杀进程（Lost connection to device）。
    // releaseActive 相比原 pendingDisposal 更强：退场动画期间旧页 dispose()
    // 可能尚未执行（_pendingDisposal 未就绪），此时仍会强制释放活跃旧实例并
    // 等待其销毁完成，杜绝「退出后快速重进」时新旧 surface 并发冲突。
    if (_controllerCreated) {
      _controller.removeListener(_onControllerChanged);
      _controller.dispose();
      _controllerCreated = false;
      _videoController = null;
    }
    await PlayerController.releaseActive();
    if (_disposed) return;
    _controller = PlayerController();
    _controller.addListener(_onControllerChanged);
    _controllerCreated = true;
    _videoController = VideoController(_controller.player);
    // 视频宽高 → 方向判定（跟随视频模式）绑定到新控制器。
    _bindVideoOrientationTracking();
    // 视频实时翻译：绑定新控制器（恢复持久化开关；进行中的翻译状态随旧实例失效）。
    unawaited(_subtitleTranslator.attach(_controller));

    // 同步当前系统亮度（手势起点基准）与播放器音量（PlayerController.volume）。
    try {
      _brightness = await _brightnessPlugin.current;
    } on Object {
      _brightness = 0.5;
    }
    try {
      _controller.volume = _controller.player.state.volume;
      _dragStartVolume = _controller.volume;
    } on Object {
      // 取底层音量失败，沿用默认 50。
    }

    // 应用全局播放器默认设置（解码/音频/比例/倍速/音量/方向/手势/字幕样式）。
    // 这是让 PlayerSettings 13 个字段真正生效的「地基」调用。
    await _applyPlayerSettings();

    // 按当前网络 / 设备内存应用 demuxer 缓存档位，并订阅网络变化
    // （蜂窝 ↔ Wi-Fi 切换时即时升降档，无需重开播放器）。
    unawaited(_applyDemuxerCachePolicy());
    _connectivitySub?.cancel();
    _connectivitySub = _cachePolicyResolver.onConnectivityChanged.listen((_) {
      if (_disposed) return;
      unawaited(_applyDemuxerCachePolicy());
    });

    if (_isDirectMode) {
      // 本地 / 直链模式：跳过在线源解析，直接打开给定地址。
      // 直链带防盗链请求头（嗅探到的 m3u8 常需 Referer，缺了会被 CDN 403）。
      String direct = widget.directUrl ?? widget.localUri!;
      // SAF / content:// 文档 URI 不能直接交给 media_kit（mpv 读不了 content://
      // 会既不报错也不完成 → UI 无限转圈）。统一在此落为应用私有真实文件再打开，
      // 这样「下载页」（编码 SAF 路径）与「浏览页」（file_picker 的 content://）
      // 走同一可靠路径。
      if (isDocUri(direct)) {
        try {
          direct = await resolveSafVideoFile(direct);
          AppLog.instance.i('[本地视频打开] SAF/content 已解析为真实文件：$direct');
        } on Object catch (e) {
          AppLog.instance.eWithStack('[本地视频打开] SAF 解析失败：$direct', e);
          throw Exception('无法读取该文件（SAF 解析失败，可能下载未完成或目录权限失效）');
        }
      }
      final headers =
          (widget.directUrl != null && widget.directHeaders?.isNotEmpty == true)
              ? widget.directHeaders
              : null;
      _playUrl = direct;
      _playHeaders = headers;
      // 本地文件：media_kit 打开裸绝对路径偶尔会既不报错也不完成（UI 无限转圈）。
      // 加超时兜底，把"卡死"变成明确错误，让用户能看到原因而非一直转圈。
      final stopwatch = Stopwatch()..start();
      AppLog.instance.i('[本地视频打开] 调用 media_kit.open：$direct');
      _controller.openReadyTimeout = _readyTimeout;
      try {
        await _controller
            .open(direct, headers: headers)
            .timeout(const Duration(seconds: 30));
      } on TimeoutException {
        AppLog.instance.e('[本地视频打开超时] 30s 内 media_kit 未载入：$direct');
        throw Exception('本地视频打开超时（media_kit 未能在 30 秒内载入，'
            '可能是文件位置 media_kit 无法读取）');
      }
      // 直链 / 本地模式打开后自动播放（与在线分支对齐，修复「打开即暂停」）。
      _startPlayback();
      // 分级超时等待元数据，超时自动 re-open 一次自愈。
      unawaited(_retryOpenOnceIfStalled());
      AppLog.instance.i('[本地视频打开] media_kit.open 完成，'
          '耗时 ${stopwatch.elapsedMilliseconds}ms');
    } else {
      final repo = context.read<SourceRepository>();
      final service = context.read<MediaApiService>();
      final source = repo.getById(widget.sourceId);
      if (source == null) {
        throw Exception('source not found: ${widget.sourceId}');
      }

      // 解析视频地址（自动处理渲染后抽取）
      final video =
          await _resolveVideoWithCapture(service, source, widget.episode.url);
      String playUrl = video.url;
      Map<String, String>? playHeaders = video.headers;
      _playUrl = playUrl;
      _playHeaders = playHeaders;

      // 由解析结果构造播放线路：源提供多线路（video.lines）时使用，
      // 否则以单线路 url 兜底为「线路 1」。播放页「选集 / 线路」面板据此切换。
      if (video.url.isNotEmpty) {
        _controller.lines = _buildLines(video);
        _controller.currentLineIndex = 0;
        // 重置本集会话内的选路状态（索引 0 永远是当前刚解析出的直链）。
        _resolvedLineIndices
          ..clear()
          ..add(0);
        _triedLineIndices.clear();
        // 手动记忆的线路优先：用户此前为本集选过某线路，进集直接用它。
        final memName = await _lineStore.getSelectedLine(
            widget.sourceId, widget.episode.id);
        if (memName != null) {
          final idx = _indexOfLineName(memName);
          if (idx != null && idx != 0) {
            final resolved = await _resolveLineUrl(idx);
            if (resolved != null) {
              _controller.lines[idx] = resolved;
              _resolvedLineIndices.add(idx);
              playUrl = resolved.url;
              playHeaders = resolved.headers;
              _controller.currentLineIndex = idx;
            }
          }
        }
        _playUrl = playUrl;
        _playHeaders = playHeaders;
      }

      await _controller.open(playUrl, headers: playHeaders);
      // 解析成功后自动开始播放
      _startPlayback();
      // 分级超时等待元数据（媒体服务器 30s），超时自动 re-open 一次自愈。
      unawaited(_retryOpenOnceIfStalled());
    }

    // 退页守卫：open() 期间可能已退场，后续订阅 / 弹幕加载 / setState 须在
    // _disposed 复查后执行，避免对失活元素调用 setState。
    if (_disposed || !mounted) return;

    // 恢复上次播放位置（续读进度跨章节恢复）。
    // 不 await：[_seekWhenReady] 需要等底层 duration 就绪（可能 1~10 秒），
    // 阻塞 _init 会让整页一直转圈。恢复完成前 [_positionRestoreDone] 为 false，
    // 位置写盘被挡住，不存在「被 0 覆盖」的竞态。
    // 关闭「记住播放/阅读位置」时不再恢复上次进度，直接从头播放；
    // 但仍置位 [_positionRestoreDone]，允许本集继续保存进度（仅不跳转）。
    // 媒体服务器：先构建当前集会话（续播恢复要读它），再开始上报
    // （Start；随后由位置流驱动心跳）。
    if (_isMediaServer) {
      final pb = widget.mediaServerPlayback!;
      final info = pb.initialInfo;
      if (info != null) {
        _serverLastInfo = info;
        _serverAudioStreamIndex = null;
        _serverSession = MediaServerPlaybackSession(
          client: pb.client,
          itemId: pb.current.id,
          playSessionId: info.playSessionId,
          initialPositionTicks: pb.fromStart
              ? 0
              : (pb.current.userData?.playbackPositionTicks ?? 0),
          runTimeTicks: info.runTimeTicks ?? pb.current.runTimeTicks,
          playMethod: info.playMethod,
        );
        unawaited(
          _serverSession!.start(positionMs: _serverSession!.initialPositionMs),
        );
      }
    }
    if (widget.restoreProgress || widget.initialPositionMs != null) {
      unawaited(_restoreSavedPosition());
    } else {
      _positionRestoreDone = true;
      _lastPositionSaveAt = DateTime.now();
    }

    // 监听播放状态
    _positionSub = _controller.positionStream.listen(_onPositionChanged);
    _completedSub = _controller.completedStream.listen(_onCompleted);
    // 监听 stall（卡顿）事件：提示并自动重连
    _stallSub = _controller.stallStream.listen((_) => _onStall());
    // 监听解码自动降级（花屏 / 硬解失败自愈）：提示并 re-open 生效
    _decodeFallbackSub =
        _controller.decodeFallbackStream.listen(_onDecodeFallback);
    // 监听缓冲状态：缓冲中显示加载动画（功能2）+ 实时网速。
    _bufferingSub = _controller.bufferingStream.listen((b) {
      if (_disposed || !mounted) return;
      setState(() => _isBuffering = b);
      // 缓冲开始轮询 mpv cache-speed 显示网速，结束停止。
      if (b) {
        _startSpeedProbe();
      } else {
        _stopSpeedProbe();
      }
    });
    // 播放状态同步：底层播放/暂停时同步 [_isPlaying]，驱动中央大播放按钮、
    // 底栏播放图标、缓冲指示器收敛。修复「视频已自动播放但 UI 仍显示暂停态」
    // 及「_togglePlayPause 首次点击行为反了」的问题。
    // 注意 mpv 在暂停→播放瞬间（伴随缓冲）可能先抖出一个瞬态 false，直接消费
    // 会让中央播放键误判「又暂停了」而闪现播放图标——false 事件延迟 250ms
    // 确认，期间恢复播放则视为抖动丢弃。
    _playingSub = _controller.playingStream.listen((p) {
      if (_disposed || !mounted) return;
      if (p) {
        _playingFalseDebounce?.cancel();
        _applyPlayingState(true);
        // 播放自动全屏（每媒体一次；暂停续播 / 重连续播不重复触发）。
        _autoEnterFullscreenIfNeeded();
        return;
      }
      _playingFalseDebounce?.cancel();
      _playingFalseDebounce = Timer(const Duration(milliseconds: 250), () {
        if (_disposed || !mounted || _controller.isPlaying) return;
        _applyPlayingState(false);
      });
    });
    // 兜底同步一次当前播放态：playingStream 是广播流，若在 open()/play() 之后
    // 才订阅，可能错过已发出的 true，导致「实际在播放但 UI 停在暂停态」。
    if (mounted && _controller.isPlaying != _isPlaying) {
      setState(() => _isPlaying = _controller.isPlaying);
      if (_isPlaying) _scheduleUiHide();
    }
    // 兜底补触发播放自动全屏：订阅前已起播时流的 true 已错过，此处按当前
    // 实际播放态补一次（闸保证每媒体只进一次全屏）。
    if (mounted && _controller.isPlaying) _autoEnterFullscreenIfNeeded();

    // 初始化弹幕仓库（弹幕源选择已在 _init 开头恢复）
    _initDanmakuRepository();

    // 读取自定义截图保存目录
    try {
      final prefs = await SharedPreferences.getInstance();
      _customScreenshotDir = prefs.getString('screenshot_custom_dir');
    } on Object {
      // 读取失败，使用默认路径
    }
    // 退页守卫：await SharedPreferences 期间可能已退场。
    if (_disposed || !mounted) return;

    // 尝试加载弹幕（本地 / 直链模式无剧集元数据，跳过自动匹配；
    // 用户仍可通过弹幕源面板切换到自定义 URL 手动加载）。
    if (!_isDirectMode) {
      _loadDanmaku();
    }

    // 刷新收藏状态（顶栏收藏按钮）
    _refreshFavorite();

    // 注册后台媒体通知（播放/暂停/进度/锁屏控制）。
    _attachBackgroundPlayback();

    if (mounted) setState(() {});
    // 关键：_initFuture 完成后 FutureBuilder 才会渲染播放器 UI（含弹幕覆盖层），
    // 覆盖层此刻才真正挂载。用 postFrameCallback 把「套用弹幕显示设置」延到这一帧之后，
    // 确保 _danmakuKey.currentState 非空、保存的字号/不透明度/区域真正生效。
    // 否则（如 _init 开头调度的 apply）会在转圈帧触发、覆盖层尚未挂载而被 `?.` 短路，
    // 导致重进时弹幕用默认设置（表现为「设置不对」）。
    if (mounted) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _applyDanmakuOption());
    }
  }

  /// 加载播放器设置：全局默认 + 该剧集单独覆盖（覆盖字段优先）。
  /// 同时读取跳过片头/片尾区间（独立于 PlayerSettings 字段，单独
  /// 存在该剧集覆盖存储里）。
  Future<void> _loadPlayerSettings() async {
    try {
      final global = await PlayerSettingsStore().load();
      _playerSettings =
          await EpisodePlayerSettingsStore().loadMerged(global, widget.itemId);
    } on Object {
      _playerSettings = const PlayerSettings();
    }
    // 自动选线路开关（来自全局 + 剧集覆盖合并结果）。
    _autoSelectLine = _playerSettings.autoSelectLine;
    try {
      final overrides =
          await EpisodePlayerSettingsStore().loadOverrides(widget.itemId);
      _skipOpEndSec = (overrides['skipOpEndSec'] as num?)?.toInt();
      _skipEdStartSec = (overrides['skipEdStartSec'] as num?)?.toInt();
      _skipAuto = overrides['skipAuto'] as bool? ?? false;
    } on Object {
      // 读取失败按未设置处理，不影响播放。
    }
  }

  /// 把 [PlayerSettings] 应用到底层播放器与 UI 状态。
  ///
  /// 这是让"播放器设置页"字段真正生效的地基调用：解码/音频/比例/倍速/音量/
  /// 连播/方向锁定/seek 倍率/字幕样式。长按倍速与双击行为开关在对应手势处读取。
  Future<void> _applyPlayerSettings() async {
    final s = _playerSettings;
    try {
      await _controller.setHwdec(_decodeModeToMpv(s.decodeMode));
      await _controller.setAudioChannel(_audioChannelToMpv(s.audioChannel));
      await _controller.setAspectRatio(_aspectRatioToMpv(s.aspectRatio));
      // 超分辨率 shader 档位（资产部署 + glsl-shaders 注入，off 清空）。
      await _controller.setUpscaleShader(s.upscaleShader);
      if (s.defaultVolume >= 0 && s.defaultVolume <= 100) {
        await _controller.setVolume(s.defaultVolume);
        _dragStartVolume = _controller.volume;
      }
      _controller.autoPlayNext = s.autoPlayNext;
      if (s.playbackSpeed > 0) {
        await _controller.setPlaybackSpeed(s.playbackSpeed);
      }
      // 字幕样式全局默认打通：字号/边框/阴影/颜色/位置/ASS/偏移/显隐
      // 全部应用到底层播放器，使设置页「字幕」组的默认值真正生效。
      await _controller.setSubtitleFontSize(s.subtitleFontSize);
      await _controller.setSubtitleBorderSize(s.subtitleBorderSize);
      await _controller.setSubtitleScale(s.subtitleScale);
      await _controller.setSubtitleShadowOffset(s.subtitleShadowOffset);
      await _controller.setSubtitleColor(s.subtitleColor);
      await _controller.setSubtitleBorderColor(s.subtitleBorderColor);
      await _controller.setSubtitleShadowColor(s.subtitleShadowColor);
      await _controller.setSubtitlePosition(s.subtitlePosition);
      await _controller.setSubtitleAssOverride(s.subtitleAssMode);
      await _controller.setSubtitleDelay(
        Duration(milliseconds: s.subtitleDelayMs),
      );
      await _controller.setSubtitleVisible(s.subtitleVisible);
      await _applyLockOrientation(s.lockOrientation);
      _seekMultiplierFactor = _seekMultiplierToFactor(s.seekMultiplier);
    } on Object {
      // 部分属性设置失败（如平台不支持）不影响播放，忽略。
    }
  }

  Future<void> _applyLockOrientation(PlayerLockOrientation o) async {
    // 桌面端（短边 ≥ 600）不强制方向，窗口自由调整（项 3：仅手机自动横屏）。
    final bool isPhone = MediaQuery.of(context).size.shortestSide < 600;
    // 本次会话已手动旋转过：以手动方向为准（设置改动 / 重试不夺回方向）。
    final List<DeviceOrientation>? orients = _manualOrientationOverride ??
        resolvePlayerOrientations(
          mode: o,
          isPhone: isPhone,
          videoWidth: _videoWidth,
          videoHeight: _videoHeight,
        );
    // 跟随视频且宽高未就绪：先不锁方向，等首个视频尺寸事件后再应用，
    // 避免先锁错方向再旋转造成闪烁。
    if (orients == null) {
      _controller.setBaseOrientations(const <DeviceOrientation>[]);
      return;
    }
    // 记录全屏切换时应用/恢复的方向（进入全屏沿用此方向，不再写死横屏）。
    _controller.setBaseOrientations(orients);
    if (!isPhone || !PlatformService.instance.isMobile) return;
    try {
      await SystemChrome.setPreferredOrientations(orients);
    } on Object {
      // 平台不支持，忽略。
    }
  }

  static String _decodeModeToMpv(DecodeMode m) {
    switch (m) {
      case DecodeMode.auto:
        return 'auto';
      case DecodeMode.sw:
        return 'sw';
      case DecodeMode.hw:
        return 'hw';
      case DecodeMode.hwPlus:
        return 'hw+';
    }
  }

  static String _audioChannelToMpv(AudioChannel c) {
    switch (c) {
      case AudioChannel.auto:
        return 'auto';
      case AudioChannel.stereo:
        return 'stereo';
      case AudioChannel.mono:
        return 'mono';
    }
  }

  static String _aspectRatioToMpv(PlayerAspectRatio a) {
    switch (a) {
      case PlayerAspectRatio.defaultRatio:
        return 'default';
      case PlayerAspectRatio.ratio43:
        return '4:3';
      case PlayerAspectRatio.ratio169:
        return '16:9';
      case PlayerAspectRatio.fill:
        return 'fill';
    }
  }

  static double _seekMultiplierToFactor(SeekMultiplier m) {
    switch (m) {
      case SeekMultiplier.half:
        return 0.5;
      case SeekMultiplier.normal:
        return 1.0;
      case SeekMultiplier.double:
        return 2.0;
    }
  }

  /// 双击中央：切换播放/暂停（功能1）。
  void _togglePlayPause() {
    if (_controller.isLocked) return;
    if (_controller.isPlaying) {
      unawaited(_controller.pause());
      // 暂停：取消自动隐藏并让控制层常显，用户能立刻看到播放键。
      // PiP 小窗内例外：小窗放不下控制层，保持隐藏（画面重叠的根源）。
      _uiHideTimer?.cancel();
      if (mounted && !_inPip) {
        setState(() {
          _isPlaying = false;
          _uiVisible = true;
        });
      }
    } else {
      unawaited(_controller.play());
      if (mounted) setState(() => _isPlaying = true);
      _scheduleUiHide();
    }
    // PiP 窗口内播放/暂停后刷新动作图标（播放↔暂停）。
    if (_inPip) {
      unawaited(_configurePipActions(AppLocalizations.of(context)));
    }
  }

  /// 长按开始：切到自定义倍速（功能4，受 longPressSpeedUp 开关控制）。
  void _onLongPressSpeedStart() {
    // MD3「Thunk」：长按进入倍速模式。
    AppHaptics.thunk();
    if (_controller.isLocked) return;
    if (!_playerSettings.longPressSpeedUp) return;
    _speedBeforeLongPress = _controller.playbackSpeed;
    final target = _playerSettings.longPressSpeed;
    if (target > 0 && target != _speedBeforeLongPress) {
      unawaited(_controller.setPlaybackSpeed(target));
      _showGestureIndicator('${target}x');
    }
  }

  /// 长按结束：恢复原倍速。
  void _onLongPressSpeedEnd() {
    if (!_playerSettings.longPressSpeedUp) return;
    if (_controller.playbackSpeed != _speedBeforeLongPress) {
      unawaited(_controller.setPlaybackSpeed(_speedBeforeLongPress));
    }
  }

  /// 写入该剧集的单独设置覆盖字段（播放器内弹窗/快捷行修改的音画参数）。
  ///
  /// 只记录用户实际改过的字段；未改过的项继续跟随全局默认。
  /// 持久化失败不影响本次播放。
  Future<void> _saveEpisodeSetting(String field, Object? value) async {
    try {
      await EpisodePlayerSettingsStore().setField(widget.itemId, field, value);
    } on Object {
      // 忽略持久化异常。
    }
  }

  /// 清除该剧集的单独设置，恢复跟随全局默认。
  Future<void> _resetEpisodeSettings() async {
    try {
      await EpisodePlayerSettingsStore().clearOverrides(widget.itemId);
      _playerSettings = await PlayerSettingsStore().load();
    } on Object {
      _playerSettings = const PlayerSettings();
    }
    if (mounted) setState(() {});
    await _applyPlayerSettings();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context).playerResetEpisodeSettingsDone),
        ),
      );
    }
  }

  /// 从 SharedPreferences 读取弹幕源选择。
  Future<void> _loadDanmakuSourcePref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(_kDanmakuSourceKey);
      if (name != null) {
        _danmakuSource = DanmakuSourceType.values.firstWhere(
          (e) => e.name == name,
          orElse: () => DanmakuSourceType.dandanplay,
        );
      }
      // #6 -#6: 同步加载自定义 URL。
      _customDanmakuUrl = prefs.getString(_kDanmakuCustomUrlKey) ?? '';
      // 恢复弹幕显示设置：与全局「弹幕显示设置」页共用同一存储（单一数据源）。
      _danmakuSettings = await _loadDanmakuSettings();
      debugPrint('[_loadDanmakuSourcePref] 已恢复弹幕显示设置: '
          'area=${_danmakuSettings.area} fontSize=${_danmakuSettings.fontSize} '
          'opacity=${_danmakuSettings.opacity} lineHeight=${_danmakuSettings.lineHeight} '
          'duration=${_danmakuSettings.duration}');
      // 覆盖层在首帧才会挂载，而 _init 此刻尚未结束、_danmakuKey.currentState
      // 仍为空，直接调用 apply 会被 `?.` 短路成空操作。改为延到下一帧
      // （覆盖层必然已挂载）再同步到渲染层，彻底解决「退出重进无法保持」。
      if (mounted) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _applyDanmakuOption());
      }
    } on Object catch (e, st) {
      debugPrint('[_loadDanmakuSourcePref] 读取弹幕设置失败: $e\n$st');
    }
  }

  /// 弹幕显示设置存储：与全局「弹幕显示设置」页共用同一实例，单一数据源。
  /// 底层走 [DanmakuDisplaySettingsStore] → SharedPreferences.getInstance()，稳定可靠。
  final DanmakuDisplaySettingsStore _danmakuSettingsStore =
      DanmakuDisplaySettingsStore();

  /// 加载弹幕显示设置：优先读取与全局页共用的存储；若该存储为空，
  /// 尝试从旧方案（文件 / SharedPreferencesAsync）一次性迁移，避免历史设置丢失。
  Future<DanmakuSettings> _loadDanmakuSettings() async {
    if (await _danmakuSettingsStore.hasData()) {
      return _danmakuSettingsStore.load();
    }
    final legacy = await _readLegacyDanmakuSettings();
    if (legacy != null) {
      await _danmakuSettingsStore.save(legacy);
      return legacy;
    }
    return _danmakuSettingsStore.load();
  }

  /// 读取旧方案保存的弹幕设置（仅用于一次性迁移，迁移后清理文件）。
  Future<DanmakuSettings?> _readLegacyDanmakuSettings() async {
    // 旧方案主写文件 danmaku_settings.json。
    try {
      final file = File(
          '${(await getApplicationSupportDirectory()).path}/danmaku_settings.json');
      if (await file.exists()) {
        final decoded =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final s = DanmakuSettings.fromJson(decoded);
        await file.delete().catchError((Object _) {});
        return s;
      }
    } on Object catch (e, st) {
      debugPrint('[_readLegacyDanmakuSettings] 读旧文件失败: $e\n$st');
    }
    // 旧方案兼容副本：SharedPreferencesAsync 键 danmaku_settings。
    try {
      final sp = SharedPreferencesAsync();
      final raw = await sp.getString(_kLegacyDanmakuSettingsKey);
      if (raw != null && raw.isNotEmpty) {
        // 读后即删：迁移只发生一次，避免旧键永久残留。
        await sp.remove(_kLegacyDanmakuSettingsKey);
        return DanmakuSettings.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
      }
    } on Object catch (e, st) {
      debugPrint(
          '[_readLegacyDanmakuSettings] 读旧 SharedPreferences 失败: $e\n$st');
    }
    return null;
  }

  /// 持久化弹幕显示设置：写入与全局「弹幕显示设置」页共用的存储
  /// （key `danmaku_display_settings_v1`，SharedPreferences.getInstance()）。
  Future<void> _saveDanmakuSettings() async {
    try {
      await _danmakuSettingsStore.save(_danmakuSettings);
      debugPrint('[_saveDanmakuSettings] 已保存弹幕显示设置: '
          'area=${_danmakuSettings.area} fontSize=${_danmakuSettings.fontSize} '
          'opacity=${_danmakuSettings.opacity} lineHeight=${_danmakuSettings.lineHeight} '
          'duration=${_danmakuSettings.duration}');
    } on Object catch (e, st) {
      debugPrint('[_saveDanmakuSettings] 保存失败: $e\n$st');
    }
  }

  void _initDanmakuRepository() {
    try {
      final cacheBox = Hive.box<dynamic>('danmaku_cache');
      final configStore = DanmakuConfigStore();
      _danmakuRepo = DanmakuRepository(
        dandanplay: DandanplayService(configStore: configStore),
        bilibili: BilibiliDanmakuService(),
        cacheBox: cacheBox,
      );
    } on Object {
      // Hive box 未打开或服务不可用，静默降级（无弹幕）。
      _danmakuRepo = null;
    }
  }

  /// 解析当前集的 dandanplay episodeId。
  ///
  /// 优先级：剧集预填值 → 已缓存的手动/即时匹配结果 → 若源为 dandanplay 则按
  /// 「番剧名 + 集名」即时 match 并缓存。返回 null 表示无法获得（如源为 bilibili）。
  Future<int?> _resolveDandanId(Episode ep) async {
    final pre = ep.dandanplayEpisodeId ?? _dandanOverride[ep.id];
    if (pre != null) return pre;
    if (_danmakuSource != DanmakuSourceType.dandanplay) return null;
    if (_danmakuRepo == null) return null;
    final id = await _danmakuRepo!.matchEpisode(
      '${widget.title} ${ep.title}',
      animeTitle: widget.title,
    );
    if (id != null) _dandanOverride[ep.id] = id;
    return id;
  }

  /// 加载当前集弹幕（首载入口， 统一走 [_loadDanmakuFor]）。
  Future<void> _loadDanmaku() => _loadDanmakuFor(widget.episode);

  /// 加载指定剧集弹幕（首载 / 切集共用）。
  ///
  /// 与旧的 `_loadDanmakuForEpisode` 相比补齐了与首载 [_loadDanmaku] 对称的
  /// 行为：自定义 URL 源为空时清空跳过、凭据未配置时给出提示，不再静默失败。
  Future<void> _loadDanmakuFor(Episode ep) async {
    if (_danmakuRepo == null) return;
    // 关闭弹幕源：清空并跳过加载。
    if (_danmakuSource == DanmakuSourceType.off) {
      _danmakuController.clear();
      return;
    }
    // 自定义 URL 源且 URL 为空时，清空并跳过。
    if (_danmakuSource == DanmakuSourceType.customUrl &&
        _customDanmakuUrl.isEmpty) {
      _danmakuController.clear();
      return;
    }
    try {
      final dandanId = await _resolveDandanId(ep);
      final items = await _danmakuRepo!.getDanmaku(
        sourceId: widget.sourceId,
        episodeId: ep.id,
        dandanplayEpisodeId:
            _danmakuSource == DanmakuSourceType.bilibili ? null : dandanId,
        bilibiliCid: _danmakuSource == DanmakuSourceType.dandanplay
            ? null
            : ep.bilibiliCid,
        bangumiId: ep.bangumiId,
        danmakuUrl: _danmakuSource == DanmakuSourceType.customUrl
            ? _customDanmakuUrl
            : ep.danmakuUrl,
      );
      // 过滤并转换为 DanmakuItem
      final filtered = items
          .where((i) => !_danmakuSettings.shouldFilter(i.text))
          .map((i) => i.toDanmakuItem())
          .toList();
      // 退页守卫：await 网络期间可能已退出（deactivate 置 _disposed 后
      // mounted 仍为 true，不能仅凭 mounted 判断），退出后不再写弹幕层。
      if (_disposed || !mounted) return;
      _danmakuController.setItems(filtered);
    } on Object catch (e) {
      // 凭据未配置时给出提示，其余错误静默忽略（首载 / 切集行为一致）。
      final msg = e.toString();
      if (msg.contains('credentials not configured') && mounted && !_disposed) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.danmakuLoadFailed),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _onPositionChanged(Duration position) {
    if (!mounted || _disposed) return;
    _position = position;
    // 记录可信的非零进度：open() 重置或缓冲瞬间可能产生 0 位置事件，
    // 不能据此把恢复点清零（避免重连后从头播放）。
    if (position > Duration.zero) _lastGoodPosition = position;
    if (_duration == Duration.zero) {
      _duration = _controller.duration;
    }
    // 自动跳过片头/片尾（未开启或未设置时为空操作）。
    _maybeAutoSkip(position);
    // 视频实时翻译：节流轮询字幕文本 / OCR 兜底（内部自带节流与去重）。
    _subtitleTranslator.onPositionTick(position);
    // 注入弹幕
    if (_danmakuOn) {
      final adjusted = position +
          Duration(milliseconds: (_danmakuSettings.timeOffset * 1000).round());
      _danmakuController.tick(adjusted);
    }
    // 预解析下一集（进度>80% 触发，后台拉地址写入 VideoSourceCache）
    _maybePreloadNextEpisode();
    // 节流保存播放位置（每 5 秒）
    _maybeSavePosition();
    // 媒体服务器：进度心跳上报（约 10s 一次，暂停 / seek 跳变立即补报）。
    _maybeReportServerProgress();
    // 达到「已看」阈值时自动标记当前集
    _maybeMarkWatched();
    // setState 节流：position 流 ~4-10Hz，全量重建开销大。
    // 弹幕注入 / 进度写盘 / 预解析不受此节流影响（各自已有守卫或节流）。
    final now = DateTime.now();
    if (_lastPositionUiAt == null ||
        now.difference(_lastPositionUiAt!) >=
            const Duration(milliseconds: 250)) {
      _lastPositionUiAt = now;
      if (mounted) setState(() {});
    }
  }

  /// 节流保存播放位置：每 5 秒写一次到 MediaPlaybackPositionManager。
  void _maybeSavePosition() {
    // 续播恢复完成前禁止写盘，避免刚 open 时的 position=0 覆盖旧存档。
    if (!_positionRestoreDone) return;
    final now = DateTime.now();
    if (now.difference(_lastPositionSaveAt) < const Duration(seconds: 5)) {
      return;
    }
    _lastPositionSaveAt = now;
    // 用 _init 阶段缓存的引用：不依赖 context，任何时刻（含 dispose 期）可写。
    final mgr = _positionManager;
    if (mgr == null) return;
    if (_isMediaServer) {
      // 进度双写：本地命名空间 ms:<serverId>:<workId>（服务器上报另行走会话）。
      unawaited(mgr.savePosition(
        widget.mediaServerPlayback!.currentContentId,
        _episodeIndex,
        _position.inMilliseconds,
      ));
      return;
    }
    unawaited(mgr.savePosition(
        widget.itemId, _episodeIndex, _position.inMilliseconds));
  }

  /// 播放进度达到「已看」阈值时自动标记当前集已看（每集仅标记一次）。
  ///
  /// 阈值取自 [GeneralSettingsStore.watchedThresholdPercent]（默认 90）。
  /// 用本地 [_watchedMarkedEpisodes] 集合避免每帧读取 Manager / 重复标记。
  void _maybeMarkWatched() {
    final durationMs = _duration.inMilliseconds;
    if (durationMs <= 0) return;
    if (_watchedMarkedEpisodes.contains(_episodeIndex)) return;
    final ratio = _position.inMilliseconds / durationMs;
    final threshold = GeneralSettingsStore.instance.watchedThresholdPercent;
    if (!progressReachesWatchedThreshold(ratio, threshold)) return;
    _watchedMarkedEpisodes.add(_episodeIndex);
    if (_isMediaServer) {
      // 进度双写：本地已看（命名空间）+ 服务器已看由会话 ≥90% 上报。
      try {
        context.read<MediaWatchedManager>().markWatched(
              widget.mediaServerPlayback!.currentContentId,
              _episodeIndex,
            );
      } on Object {
        // Manager 不可用时静默忽略。
      }
      return;
    }
    try {
      final watched = context.read<MediaWatchedManager>();
      unawaited(watched.markWatched(widget.itemId, _episodeIndex));
      // 读后自动删除：已到最后一集且整部已看集数达到总集数。
      if (widget.episodes != null &&
          _episodeIndex == widget.episodes!.length - 1) {
        unawaited(_maybeAutoDeleteDownloads(watched));
      }
    } on Object {
      // Manager 不可用时静默忽略。
    }
  }

  // ─────────────────────── 跳过片头/片尾 ───────────────────────

  /// 是否显示「跳过片头」悬浮按钮：设置过片头结束点、位置在
  /// (1s, opEnd-1s) 且本集未跳过。位置上限留 1s 缓冲避免临门一点还弹按钮。
  bool get _showSkipOpButton {
    final opEnd = _skipOpEndSec;
    if (opEnd == null || opEnd <= 3 || _opSkippedThisEpisode) return false;
    final posSec = _position.inSeconds;
    return posSec > 1 && posSec < opEnd - 1;
  }

  /// 是否显示「跳过片尾」悬浮按钮：设置过片尾开始点、位置落在
  /// [edStart, edStart+8s) 且本集未跳过。
  bool get _showSkipEdButton {
    final edStart = _skipEdStartSec;
    if (edStart == null || _edSkippedThisEpisode) return false;
    final posSec = _position.inSeconds;
    return posSec >= edStart && posSec < edStart + 8;
  }

  /// 自动跳过片头/片尾：进入区间且本集未跳过时直接 seek 越过。
  /// 片头要求位置 > 2s 才触发：开局即跳会吞掉「以停顿/回忆开场」的作品，
  /// 也避免续播恢复落在片头内时反复跳。
  void _maybeAutoSkip(Duration position) {
    if (!_skipAuto) return;
    final posSec = position.inSeconds;
    final opEnd = _skipOpEndSec;
    if (opEnd != null &&
        opEnd > 3 &&
        !_opSkippedThisEpisode &&
        posSec > 2 &&
        posSec < opEnd - 1) {
      _skipIntro();
      return;
    }
    final edStart = _skipEdStartSec;
    final durSec = _duration.inSeconds;
    if (edStart != null &&
        durSec > 0 &&
        edStart < durSec - 5 &&
        !_edSkippedThisEpisode &&
        posSec >= edStart &&
        posSec < edStart + 8) {
      _skipOutro();
    }
  }

  /// 跳过片头：seek 到片头结束点。
  void _skipIntro() {
    final opEnd = _skipOpEndSec;
    if (opEnd == null) return;
    _opSkippedThisEpisode = true;
    unawaited(_controller.seek(Duration(seconds: opEnd)));
    if (mounted) setState(() {});
  }

  /// 跳过片尾：seek 到片尾前（触底后由完成事件接续连播/下一集）。
  void _skipOutro() {
    if (_duration <= Duration.zero) return;
    _edSkippedThisEpisode = true;
    unawaited(_controller.seek(_duration - const Duration(milliseconds: 200)));
    if (mounted) setState(() {});
  }

  /// 「分:秒」格式化（供跳过设置对话框展示当前值）。
  String _fmtMmSs(int? seconds) {
    if (seconds == null || seconds < 0) return '';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// 解析「分:秒」或纯秒数文本；非法/为空返回 null（= 未设置）。
  int? _parseMmSs(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final colon = t.indexOf(':');
    int? value;
    if (colon < 0) {
      value = int.tryParse(t);
    } else {
      final m = int.tryParse(t.substring(0, colon));
      final s = int.tryParse(t.substring(colon + 1));
      if (m != null && s != null) value = m * 60 + s;
    }
    if (value == null || value < 0) return null;
    return value;
  }

  /// 跳过片头/片尾设置对话框：片头结束点 / 片尾开始点（分:秒，
  /// 可一键取当前播放位置）+ 自动跳过开关；按作品持久化。
  Future<void> _showSkipSettings() async {
    final l10n = AppLocalizations.of(context);
    final opCtl = TextEditingController(text: _fmtMmSs(_skipOpEndSec));
    final edCtl = TextEditingController(text: _fmtMmSs(_skipEdStartSec));
    var auto = _skipAuto;
    final saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogCtx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setDlg) => AppAlertDialog(
          // 弹窗占据更多屏幕宽度与高度（垂直边距收紧），内容显示区域更大。
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          // 紧凑按钮栏：降低「取消/保存」栏自身高度，把垂直空间让给内容区。
          actionsPadding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
          title: Text(
            l10n.playerSkipOpEd,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          // 手机适配：内容用 SingleChildScrollView 包裹，避免窄屏下「使用当前」
          // 按钮 / 开关与输入行挤压重叠；自动跳过用 Row+Switch 替代占宽的
          // SwitchListTile，减少横向溢出风险。
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: opCtl,
                        decoration: InputDecoration(
                          labelText: l10n.playerSkipOpEndLabel,
                          labelStyle: const TextStyle(fontSize: 13),
                        ),
                        keyboardType: TextInputType.datetime,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        opCtl.text = _fmtMmSs(_position.inSeconds);
                      },
                      child: Text(l10n.playerSkipUseCurrent,
                          style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.spaceSm),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: edCtl,
                        decoration: InputDecoration(
                          labelText: l10n.playerSkipEdStartLabel,
                          labelStyle: const TextStyle(fontSize: 13),
                        ),
                        keyboardType: TextInputType.datetime,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        edCtl.text = _fmtMmSs(_position.inSeconds);
                      },
                      child: Text(l10n.playerSkipUseCurrent,
                          style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.spaceSm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        l10n.playerSkipAuto,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    Switch(
                      value: auto,
                      onChanged: (v) {
                        v == true
                            ? AppHaptics.toggleOn()
                            : AppHaptics.toggleOff();
                        setDlg(() => auto = v);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.spaceSm),
                Text(
                  l10n.playerSkipHint,
                  style:
                      Theme.of(ctx).textTheme.bodySmall?.copyWith(fontSize: 12),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 28),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 28),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
    opCtl.dispose();
    edCtl.dispose();
    if (saved != true || !mounted) return;
    final opEnd = _parseMmSs(opCtl.text);
    final edStart = _parseMmSs(edCtl.text);
    // 合法性钳制：片头必须 ≥ 5s；片尾开始必须距结尾 ≥ 5s（否则无意义）。
    final durSec = _duration.inSeconds;
    final safeOp = (opEnd != null && opEnd >= 5) ? opEnd : null;
    final safeEd = (edStart != null && durSec > 0 && edStart < durSec - 5)
        ? edStart
        : (edStart != null && durSec <= 0 && edStart >= 30 ? edStart : null);
    setState(() {
      _skipOpEndSec = safeOp;
      _skipEdStartSec = safeEd;
      _skipAuto = auto;
      _opSkippedThisEpisode = false;
      _edSkippedThisEpisode = false;
    });
    unawaited(_saveEpisodeSetting('skipOpEndSec', safeOp));
    unawaited(_saveEpisodeSetting('skipEdStartSec', safeEd));
    unawaited(_saveEpisodeSetting('skipAuto', auto));
  }

  /// 读后自动删除：看完整个作品后清理其已下载文件（受排除分类限制）。
  Future<void> _maybeAutoDeleteDownloads(MediaWatchedManager watched) async {
    try {
      final dm = context.read<DownloadManager>();
      final s = dm.settings;
      if (!s.autoDeleteAfterRead) return;
      final type = widget.favoriteType ?? SourceType.animeSource;
      // 排除按「收藏分类」判断：作品所属收藏分组命中排除列表则不删。
      final groupIds =
          context.read<FavoritesManager>().groupIdsOf(widget.itemId, type);
      if (s.isExcludedFromAutoDeleteGroups(groupIds)) return;
      final episodes = widget.episodes;
      if (episodes == null || episodes.isEmpty) return;
      if (watched.watchedCount(widget.itemId) < episodes.length) return;
      await dm.removeItemDownloads(widget.itemId, deleteFiles: true);
    } on Object {
      // 下载管理器不可用时静默忽略。
    }
  }

  /// 恢复上次播放位置：从 MediaPlaybackPositionManager 读取并 seek。
  ///
  /// 完成（含「无记录」「恢复失败」）后置位 [_positionRestoreDone]，此后才允许
  /// 自动保存位置。媒体服务器播放：进度只存服务器，seek 目标取会话携带的
  /// 服务器进度（不读本地历史，§2.5）。
  Future<void> _restoreSavedPosition() async {
    try {
      if (_isMediaServer) {
        final session = _serverSession;
        var savedMs = session?.initialPositionMs ?? 0;
        if (savedMs <= 0) {
          // 服务器无进度（新集）→ 本地命名空间兜底。
          try {
            final mgr = context.read<MediaPlaybackPositionManager>();
            savedMs = mgr.getPosition(
              widget.mediaServerPlayback!.currentContentId,
              _episodeIndex,
            );
          } on Object {
            // Manager 不可用时按无进度处理。
          }
        }
        if (widget.restoreProgress && savedMs > 5000) {
          await _seekWhenReady(Duration(milliseconds: savedMs));
        }
        return;
      }
      // 跨设备接续带入的位置优先于本地保存的进度。
      final int? initialMs = widget.initialPositionMs;
      if (initialMs != null && initialMs > 5000) {
        await _seekWhenReady(Duration(milliseconds: initialMs));
        return;
      }
      final mgr = context.read<MediaPlaybackPositionManager>();
      final savedMs = mgr.getPosition(widget.itemId, _episodeIndex);
      if (savedMs > 5000) {
        // 超过 5 秒才恢复，避免片头闪现
        await _seekWhenReady(Duration(milliseconds: savedMs));
      }
    } on Object {
      // Manager 不可用时静默忽略。
    } finally {
      _positionRestoreDone = true;
      _lastPositionSaveAt = DateTime.now();
    }
  }

  /// 等媒体真正就绪后再 seek，并校验一次实际落点。
  ///
  /// 根因：`player.open()` 返回时底层往往还没完成 demux（`duration` 仍为 0），
  /// 此刻调用 `seek` 会被 mpv 静默丢弃——表现为「记住的播放进度没有作用」。
  /// 这里先等 `durationStream` 给出非零时长（最多 10 秒），再 seek；随后延迟
  /// 校验实际位置，偏差超过 3 秒说明首次 seek 被吞，补发一次。
  Future<void> _seekWhenReady(Duration target) async {
    if (_controller.duration <= Duration.zero) {
      try {
        await _controller.durationStream
            .firstWhere((Duration d) => d > Duration.zero)
            // 按来源分级超时（原固定 10s 对媒体服务器冷启动不够）。
            .timeout(_readyTimeout);
      } on Object {
        // 超时或流异常：仍尝试 seek 一次，失败也不影响正常播放。
      }
    }
    if (_disposed || !mounted) return;
    final Duration dur = _controller.duration;
    // 目标越界（换源后时长变短 / 已接近片尾）则放弃恢复，避免直接跳到结尾。
    if (dur > Duration.zero && target >= dur - const Duration(seconds: 5)) {
      return;
    }
    await _controller.seek(target);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (_disposed || !mounted) return;
    final Duration diff = _controller.position - target;
    if (diff.abs() > const Duration(seconds: 3)) {
      await _controller.seek(target);
    }
  }

  /// 媒体服务器进度上报：约 10s 心跳；暂停态变化或位置跳变（seek）立即补报。
  void _maybeReportServerProgress() {
    final session = _serverSession;
    if (session == null || !_positionRestoreDone) return;
    final now = DateTime.now();
    final posMs = _position.inMilliseconds;
    final paused = !_isPlaying;
    final jumped = (posMs - _lastServerReportedMs).abs() > 10000;
    final due =
        now.difference(_lastServerReportAt) >= const Duration(seconds: 10);
    if (!due && paused == _lastServerPaused && !jumped) return;
    _lastServerReportAt = now;
    _lastServerPaused = paused;
    _lastServerReportedMs = posMs;
    unawaited(session.reportProgress(positionMs: posMs, paused: paused));
  }

  /// 媒体服务器会话内重协商（码率切换 / 转码切音轨）：
  /// 结算当前会话 → 按新参数 PlaybackInfo → 换源续播（保持当前进度）。
  Future<void> _reopenMediaServerStream({
    int? maxBitrate,
    int? audioStreamIndex,
  }) async {
    final pb = widget.mediaServerPlayback;
    if (pb == null) return;
    final l10n = AppLocalizations.of(context);
    final token = _loadSession.next();
    final oldSession = _serverSession;
    _serverSession = null;
    if (oldSession != null) {
      unawaited(oldSession.stop(positionMs: _position.inMilliseconds));
    }
    _positionRestoreDone = false;
    final keepPositionMs = _position.inMilliseconds;
    PlaybackInfoResult info;
    try {
      info = await pb.client.createPlaybackInfo(
        pb.current.id,
        maxStreamingBitrate: maxBitrate,
        audioStreamIndex: audioStreamIndex,
      );
    } on Object catch (e) {
      if (!_loadSession.isValid(token)) return;
      _positionRestoreDone = true;
      _safeSnackBar(l10n.mediaServerOperationFailed('$e'));
      return;
    }
    if (!_loadSession.isValid(token)) return;
    _serverLastInfo = info;
    _serverAudioStreamIndex = audioStreamIndex;
    _playUrl = info.playUrl;
    _playHeaders = info.headers;
    _controller.openReadyTimeout = _readyTimeout;
    await _controller.open(info.playUrl, headers: info.headers);
    _controller.play();
    unawaited(_retryOpenOnceIfStalled());
    if (!_loadSession.isValid(token)) return;
    _serverSession = MediaServerPlaybackSession(
      client: pb.client,
      itemId: pb.current.id,
      playSessionId: info.playSessionId,
      initialPositionTicks: keepPositionMs * 10000,
      runTimeTicks: info.runTimeTicks ?? pb.current.runTimeTicks,
      playMethod: info.playMethod,
    );
    unawaited(_restoreSavedPosition());
    unawaited(_serverSession!.start(positionMs: keepPositionMs));
  }

  /// 码率档位显示名。
  String _bitrateLabel(AppLocalizations l10n, MediaServerBitrateTier tier) {
    switch (tier) {
      case MediaServerBitrateTier.auto:
        return l10n.mediaServerBitrateAuto;
      case MediaServerBitrateTier.original:
        return l10n.mediaServerBitrateOriginal;
      case MediaServerBitrateTier.m20:
        return '20 Mbps';
      case MediaServerBitrateTier.m10:
        return '10 Mbps';
      case MediaServerBitrateTier.m8:
        return '8 Mbps';
      case MediaServerBitrateTier.m4:
        return '4 Mbps';
      case MediaServerBitrateTier.m2:
        return '2 Mbps';
      case MediaServerBitrateTier.m1:
        return '1 Mbps';
      case MediaServerBitrateTier.p720:
        return l10n.mediaServerBitrate720p;
    }
  }

  /// 码率档位选择（more_menu / 管理页共用交互）。
  Future<void> _pickServerBitrate(
      BuildContext ctx, AppLocalizations l10n) async {
    final settings = MediaServerPlaybackSettings.instance;
    await settings.load();
    final picked = await showDialog<MediaServerBitrateTier>(
      context: ctx,
      builder: (dialogCtx) => SimpleDialog(
        title: Text(l10n.mediaServerBitrateTier),
        children: <Widget>[
          RadioGroup<MediaServerBitrateTier>(
            groupValue: settings.tier,
            onChanged: (v) => Navigator.of(dialogCtx).pop(v),
            child: Column(
              children: <Widget>[
                for (final t in MediaServerBitrateTier.values)
                  RadioListTile<MediaServerBitrateTier>(
                    value: t,
                    title: Text(_bitrateLabel(l10n, t)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked == null || picked == settings.tier) return;
    await settings.setTier(picked);
    if (ctx.mounted) Navigator.of(ctx).pop();
    if (!mounted) return;
    await _reopenMediaServerStream(maxBitrate: picked.maxBitrate);
  }

  /// 音轨显示名（mpv 轨道：标题 / 语言拼接）。
  String _audioTrackLabel(AudioTrack t) {
    final parts = <String>[
      if (t.title != null && t.title!.isNotEmpty) t.title!,
      if (t.language != null && t.language!.isNotEmpty) t.language!,
    ];
    return parts.isEmpty ? t.id : parts.join(' · ');
  }

  /// 播放方式显示名（统计面板用）。
  String _serverPlayMethodLabel(AppLocalizations l10n) {
    switch (_serverSession?.playMethod) {
      case MediaServerPlayMethod.directPlay:
        return l10n.mediaServerPlayMethodDirect;
      case MediaServerPlayMethod.directStream:
        return l10n.mediaServerPlayMethodDirectStream;
      case MediaServerPlayMethod.transcode:
        return l10n.mediaServerPlayMethodTranscode;
      case null:
        return '—';
    }
  }

  /// 音轨选择（more_menu）：转码流走服务器音轨重协商；直连走 mpv 内部切换。
  Future<void> _pickServerAudioTrack(
    BuildContext ctx,
    AppLocalizations l10n,
  ) async {
    final isTranscode =
        _serverSession?.playMethod == MediaServerPlayMethod.transcode;
    if (isTranscode) {
      final streams =
          _serverLastInfo?.audioStreams ?? const <ServerMediaStream>[];
      if (streams.isEmpty) return;
      final picked = await showModalBottomSheet<int>(
        context: ctx,
        isScrollControlled: true,
        builder: (sheetCtx) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetCtx).size.height * 0.6,
            ),
            child: ListView(
              shrinkWrap: true,
              children: <Widget>[
                for (final s in streams)
                  ListTile(
                    leading:
                        (_serverAudioStreamIndex ?? _defaultAudioIndex()) ==
                                s.index
                            ? const Icon(Icons.check_rounded)
                            : null,
                    title: Text(s.label()),
                    onTap: () => Navigator.of(sheetCtx).pop(s.index),
                  ),
              ],
            ),
          ),
        ),
      );
      if (picked == null || !mounted) return;
      if (ctx.mounted) Navigator.of(ctx).pop();
      await _reopenMediaServerStream(audioStreamIndex: picked);
      return;
    }
    final tracks = _controller.audioTracks
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    if (tracks.isEmpty) return;
    final current = _controller.currentAudioTrack;
    final picked = await showModalBottomSheet<AudioTrack>(
      context: ctx,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.6,
          ),
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              for (final t in tracks)
                ListTile(
                  leading: identical(t, current)
                      ? const Icon(Icons.check_rounded)
                      : null,
                  title: Text(_audioTrackLabel(t)),
                  onTap: () => Navigator.of(sheetCtx).pop(t),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _controller.setAudioTrack(picked);
    if (mounted) setState(() {});
  }

  int? _defaultAudioIndex() {
    final streams =
        _serverLastInfo?.audioStreams ?? const <ServerMediaStream>[];
    for (final s in streams) {
      if (s.isDefault) return s.index;
    }
    return streams.isNotEmpty ? streams.first.index : null;
  }

  /// 当前音轨显示名（more_menu 副标题）。
  String _currentAudioTrackSubtitle(AppLocalizations l10n) {
    if (_serverSession?.playMethod == MediaServerPlayMethod.transcode) {
      final streams =
          _serverLastInfo?.audioStreams ?? const <ServerMediaStream>[];
      if (streams.isEmpty) return '-';
      final idx = _serverAudioStreamIndex ?? _defaultAudioIndex();
      for (final s in streams) {
        if (s.index == idx) return s.label();
      }
      return '-';
    }
    final t = _controller.currentAudioTrack;
    if (t == null) return '-';
    return _audioTrackLabel(t);
  }

  /// 播完事件：媒体服务器上报 Stopped 并标记已看（服务器端持久化，§2.5）。
  void _onCompleted(bool completed) {
    if (!mounted || _disposed) return;
    if (!completed) return;
    if (_isMediaServer) {
      final session = _serverSession;
      if (session != null) {
        unawaited(
          session.stop(
            positionMs: _position.inMilliseconds,
            completed: true,
          ),
        );
      }
      // 进度双写：本地进度清除 + 本地已看标记（命名空间）。
      try {
        final contentId = widget.mediaServerPlayback!.currentContentId;
        context
            .read<MediaPlaybackPositionManager>()
            .clearPosition(contentId, _episodeIndex);
        unawaited(
          context
              .read<MediaWatchedManager>()
              .markWatched(contentId, _episodeIndex),
        );
      } on Object {
        // Manager 不可用时静默忽略。
      }
      return;
    }
    // 播完清除该集播放位置，避免下次续播已看完的集
    try {
      final mgr = context.read<MediaPlaybackPositionManager>();
      unawaited(mgr.clearPosition(widget.itemId, _episodeIndex));
    } on Object {
      // Manager 不可用时静默忽略。
    }
    // 睡眠定时「按集数」模式：播完本集递减；归零则暂停、不连播。
    // 仅当还有下一集可播时生效（最后一集播完本身就不连播，无需拦截）。
    if (_sleepEpisodesRemaining > 0 &&
        widget.episodes != null &&
        _episodeIndex < widget.episodes!.length - 1) {
      _sleepEpisodesRemaining--;
      if (_sleepEpisodesRemaining == 0) {
        _controller.pause();
        // UI 同步（同 ）：暂停后控制层常显，避免流事件延迟导致仍显播放态。
        _uiHideTimer?.cancel();
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _uiVisible = true;
          });
          try {
            final l10n = AppLocalizations.of(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.playerTimerEpisodesFired)),
            );
          } on Object {
            // context 已失活，忽略提示。
          }
        }
        return;
      }
    }
    // 自动连播（可配置倒计时，倒计时期间可取消）
    final bool hasNextInWork =
        widget.episodes != null && _episodeIndex < widget.episodes!.length - 1;
    if (_controller.autoPlayNext && hasNextInWork) {
      final countdown = _playerSettings.autoPlayCountdownSeconds;
      if (countdown > 0) {
        _startAutoNextCountdown(countdown);
      } else {
        _goNextEpisode();
      }
      return;
    }
    // 跨作品连播：当前作品已无下一集（或本就无剧集列表），
    // 尝试从播放队列取下一部作品续播（沿用 autoPlayNext 开关与倒计时）。
    if (_controller.autoPlayNext) {
      unawaited(_maybePlayNextWork());
    }
  }

  /// 启动自动连播倒计时：SnackBar 实时显示剩余秒数并提供「取消」，
  /// 归零后播放下一集。期间控制层常显，便于用户看清提示。
  void _startAutoNextCountdown(int seconds) {
    _cancelAutoNextCountdown();
    _autoNextCountdownLeft.value = seconds;
    _uiHideTimer?.cancel();
    if (mounted) {
      setState(() => _uiVisible = true);
      try {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              duration: Duration(seconds: seconds + 1),
              // 3.38 起带 action 的 SnackBar 默认常驻（persist 隐式为 true），
              // 显式关闭以恢复「到时自动消失」，避免手动切集/退出后残留。
              persist: false,
              content: ValueListenableBuilder<int>(
                valueListenable: _autoNextCountdownLeft,
                builder: (BuildContext ctx, int left, Widget? child) =>
                    Text(l10n.playerAutoNextCountdown(left)),
              ),
              action: SnackBarAction(
                label: l10n.cancel,
                onPressed: _cancelAutoNextCountdown,
              ),
            ),
          );
      } on Object {
        // context 已失活则只走静默倒计时。
      }
    }
    _autoNextCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = _autoNextCountdownLeft.value - 1;
      if (left > 0) {
        _autoNextCountdownLeft.value = left;
        return;
      }
      _cancelAutoNextCountdown();
      if (!mounted || _disposed) return;
      try {
        // 倒计时归零切集前撤下提示条，避免盖住切集提示。
        ScaffoldMessenger.of(context).clearSnackBars();
      } on Object {
        // context 已失活则忽略。
      }
      _goNextEpisode();
    });
  }

  /// 取消自动连播倒计时（用户点「取消」/ 手动切集 / 退出播放器）。
  void _cancelAutoNextCountdown() {
    _autoNextCountdownTimer?.cancel();
    _autoNextCountdownTimer = null;
    if (_autoNextCountdownLeft.value != 0) {
      _autoNextCountdownLeft.value = 0;
    }
  }

  void _goNextEpisode() {
    if (widget.episodes == null ||
        _episodeIndex >= widget.episodes!.length - 1) {
      return;
    }
    _changeEpisode(_episodeIndex + 1);
  }

  // ───────────────────────── 播放队列（跨作品） ─────────────────────────

  /// 把「当前正在播放的作品」封装为队列条目（用于加入队列 / 记录最近播放）。
  QueuedWork _currentAsQueuedWork([int? index]) {
    final int idx = index ?? _episodeIndex;
    String? epId;
    String? epTitle;
    if (widget.episodes != null && idx >= 0 && idx < widget.episodes!.length) {
      final ep = widget.episodes![idx];
      epId = ep.id;
      epTitle = ep.title;
    }
    return QueuedWork(
      sourceId: widget.sourceId,
      itemId: widget.itemId,
      title: widget.title,
      coverUrl: widget.coverUrl,
      sourceType: widget.favoriteType ?? SourceType.animeSource,
      detailUrl: widget.detailUrl,
      localUri: widget.localUri,
      directUrl: widget.directUrl,
      episodeId: epId,
      episodeTitle: epTitle,
      episodeIndex: idx,
    );
  }

  /// 记录当前作品为「最近播放」（启动恢复）。best-effort，不阻塞播放。
  Future<void> _persistCurrentEpisode(int index) async {
    if (_disposed) return;
    try {
      await _queueStore.setCurrent(_currentAsQueuedWork(index));
    } on Object {
      // 持久化失败不影响播放。
    }
  }

  Future<void> _addCurrentToQueue() async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    try {
      await _queueStore.add(_currentAsQueuedWork());
      if (!mounted) return;
      _safeSnackBar(l10n.playerQueueAdded);
    } on Object catch (e) {
      AppLog.instance.e('[播放队列] 加入队列失败: $e');
      if (!mounted) return;
      _safeSnackBar(l10n.playerQueueLoadFailed);
    }
  }

  Future<void> _playCurrentNext() async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    try {
      await _queueStore.insertNext(_currentAsQueuedWork());
      if (!mounted) return;
      _safeSnackBar(l10n.playerQueuePlayNextAdded);
    } on Object catch (e) {
      AppLog.instance.e('[播放队列] 下一部播放失败: $e');
      if (!mounted) return;
      _safeSnackBar(l10n.playerQueueLoadFailed);
    }
  }

  /// 当前作品末集播完且开启了自动连播：从队列取第一部续播。
  Future<void> _maybePlayNextWork() async {
    if (!mounted || _disposed) return;
    final queue = await _queueStore.getQueue();
    if (queue.isEmpty) return;
    final next = queue.first;
    final seconds = _playerSettings.autoPlayCountdownSeconds;
    if (seconds > 0) {
      _showNextWorkCountdown(next, seconds);
      return;
    }
    await _replaceWithQueuedWork(next, queue);
  }

  /// 跨作品连播倒计时（复用自动连播倒计时机制，提示下一部作品名）。
  void _showNextWorkCountdown(QueuedWork next, int seconds) {
    _cancelAutoNextCountdown();
    _autoNextCountdownLeft.value = seconds;
    _uiHideTimer?.cancel();
    if (mounted) {
      setState(() => _uiVisible = true);
      try {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              duration: Duration(seconds: seconds + 1),
              // 3.38 起带 action 的 SnackBar 默认常驻（persist 隐式为 true），
              // 显式关闭以恢复「到时自动消失」，避免手动切集/退出后残留。
              persist: false,
              content: ValueListenableBuilder<int>(
                valueListenable: _autoNextCountdownLeft,
                builder: (BuildContext c, int left, Widget? child) =>
                    Text('${l10n.playerAutoNextWork(next.title)} ($left)'),
              ),
              action: SnackBarAction(
                label: l10n.cancel,
                onPressed: _cancelAutoNextCountdown,
              ),
            ),
          );
      } on Object {
        // context 已失活则只走静默倒计时。
      }
    }
    _autoNextCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = _autoNextCountdownLeft.value - 1;
      if (left > 0) {
        _autoNextCountdownLeft.value = left;
        return;
      }
      _cancelAutoNextCountdown();
      if (!mounted || _disposed) return;
      try {
        ScaffoldMessenger.of(context).clearSnackBars();
      } on Object {
        // ignore
      }
      unawaited(_queueStore.getQueue().then((q) {
        if (q.isEmpty) return;
        unawaited(_replaceWithQueuedWork(q.first, q));
      }));
    });
  }

  /// 用队列里的下一部作品替换当前播放页（跨作品连播核心）。
  ///
  /// 重新抓取该作品的剧集列表（源即插件：由源解析器决定，不在此硬编码），
  /// 定位起始集后 pushReplacement 新播放页；队列中的该作品移除并写入「最近播放」。
  Future<void> _replaceWithQueuedWork(
      QueuedWork w, List<QueuedWork> queue) async {
    if (!mounted || _disposed) return;
    late final AppLocalizations l10n;
    try {
      l10n = AppLocalizations.of(context);
    } on Object {
      return;
    }
    // 从队列移除该作品（成为当前播放）。
    final remaining = queue.where((e) => e.itemId != w.itemId).toList();
    await _queueStore.setQueue(remaining);
    await _queueStore.setCurrent(w);

    // 本地/直连视频：无源可重抓，直接带路径重开播放页（无需按源拉剧集）。
    if (w.localUri != null || w.directUrl != null) {
      if (!mounted || _disposed) return;
      await Navigator.of(context).pushReplacement(
        AppPageRoute<void>(
          builder: (_) => VideoPlayerScreen(
            title: w.title,
            episode: Episode(
              id: w.itemId,
              title: w.title,
              url: w.localUri ?? w.directUrl ?? '',
            ),
            sourceId: '',
            itemId: w.itemId,
            localUri: w.localUri,
            directUrl: w.directUrl,
            coverUrl: w.coverUrl,
            favoriteType: w.sourceType,
            restoreProgress: true,
          ),
        ),
      );
      return;
    }

    // 抓取剧集列表。
    _safeSnackBar(l10n.playerQueueLoading(w.title));
    try {
      final repo = context.read<SourceRepository>();
      final service = context.read<MediaApiService>();
      final source = repo.getById(w.sourceId);
      if (source == null) {
        _safeSnackBar(l10n.playerQueueLoadFailed);
        return;
      }
      final episodes = await service.fetchEpisodes(
        source,
        w.itemId,
        title: w.title,
        detailUrl: w.detailUrl,
      );
      if (!mounted || _disposed) return;
      if (episodes.isEmpty) {
        _safeSnackBar(l10n.playerQueueNoEpisodes);
        return;
      }
      int startIndex = w.episodeIndex.clamp(0, episodes.length - 1);
      if (w.episodeId != null) {
        final idx = episodes.indexWhere((e) => e.id == w.episodeId);
        if (idx >= 0) startIndex = idx;
      }
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        AppPageRoute<void>(
          builder: (_) => VideoPlayerScreen(
            title: w.title,
            episode: episodes[startIndex],
            sourceId: w.sourceId,
            itemId: w.itemId,
            episodes: episodes,
            initialEpisodeIndex: startIndex,
            favoriteType: w.sourceType,
            detailUrl: w.detailUrl,
            coverUrl: w.coverUrl,
            restoreProgress: true,
          ),
        ),
      );
    } on Object {
      if (mounted) _safeSnackBar(l10n.playerQueueLoadFailed);
    }
  }

  /// 从队列管理面板「继续上次」：打开持久化的最近作品（不在队列中时仅作当前恢复）。
  Future<void> _resumeLastWork(QueuedWork w) async {
    if (!mounted || _disposed) return;
    await _replaceWithQueuedWork(w, await _queueStore.getQueue());
  }

  /// 播放队列管理面板：列出待播队列，支持重排 / 删除 / 清空；
  /// 顶部若有与当前不同的「最近播放」作品，提供「继续上次」恢复入口。
  Future<void> _showQueueSheet(AppLocalizations l10n) async {
    final queue = await _queueStore.getQueue();
    final current = await _queueStore.getCurrent();
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        // 局部可变副本，便于重排 / 删除即时刷新。
        List<QueuedWork> local = List<QueuedWork>.from(queue);
        final bool showResume =
            current != null && current.itemId != widget.itemId;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85),
            child: StatefulBuilder(
              builder: (BuildContext bctx, StateSetter setStateLocal) {
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.all(AppTokens.spaceMd),
                        child: Text(l10n.playerQueue,
                            style: Theme.of(ctx).textTheme.titleMedium),
                      ),
                      if (showResume)
                        ListTile(
                          leading: const Icon(Icons.play_circle_fill_rounded),
                          title:
                              Text(l10n.playerQueueResumeLast(current!.title)),
                          onTap: () {
                            Navigator.pop(ctx);
                            unawaited(_resumeLastWork(current));
                          },
                        ),
                      if (local.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(AppTokens.spaceMd),
                          child: Text(l10n.playerQueueEmpty),
                        ),
                      for (int i = 0; i < local.length; i++)
                        _queueItemTile(
                          l10n,
                          local[i],
                          i,
                          local.length,
                          (int from, int to) {
                            setStateLocal(() {
                              final item = local.removeAt(from);
                              local.insert(to, item);
                            });
                            unawaited(_queueStore.move(from, to));
                          },
                          () {
                            setStateLocal(() => local.removeAt(i));
                            unawaited(_queueStore.removeAt(i));
                          },
                        ),
                      if (local.isNotEmpty)
                        ListTile(
                          leading: const Icon(Icons.delete_sweep_rounded),
                          title: Text(l10n.playerQueueCleared),
                          onTap: () {
                            setStateLocal(() => local.clear());
                            unawaited(_queueStore.clear());
                          },
                        ),
                      const SizedBox(height: AppTokens.spaceSm),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _queueItemTile(
    AppLocalizations l10n,
    QueuedWork w,
    int index,
    int total,
    void Function(int from, int to) onMove,
    VoidCallback onRemove,
  ) {
    return ListTile(
      leading: w.coverUrl != null
          ? Image.network(w.coverUrl!,
              width: 40,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(Icons.movie_rounded))
          : const Icon(Icons.movie_rounded),
      title: Text(w.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: w.episodeTitle != null
          ? Text(w.episodeTitle!, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.arrow_upward_rounded),
            tooltip: l10n.playerQueueMoveUp,
            onPressed: index > 0 ? () => onMove(index, index - 1) : null,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_downward_rounded),
            tooltip: l10n.playerQueueMoveDown,
            onPressed:
                index < total - 1 ? () => onMove(index, index + 1) : null,
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: l10n.playerQueueRemove,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }

  /// 预解析下一集：当前集播放进度>80% 时后台拉取下一集地址，
  /// 命中 [VideoSourceCache] 后 `_changeEpisode` 切集时秒切。
  /// 每集只触发一次，切集时重置。
  void _maybePreloadNextEpisode() {
    if (_nextEpisodePreloaded) return;
    if (widget.episodes == null || _duration == Duration.zero) return;
    if (_episodeIndex >= widget.episodes!.length - 1) return;
    // 进度 > 80% 触发
    if (_position.inMilliseconds <= _duration.inMilliseconds * 0.8) return;
    _nextEpisodePreloaded = true;
    final repo = context.read<SourceRepository>();
    final service = context.read<MediaApiService>();
    final source = repo.getById(widget.sourceId);
    if (source == null) return;
    final nextEp = widget.episodes![_episodeIndex + 1];
    // 后台拉取，结果由 BuiltinResolver 写入 VideoSourceCache；不 await、不阻塞 UI。
    unawaited(
      service
          .fetchVideoUrl(source, nextEp.url)
          .catchError((_) => const VideoResult(url: '', type: 'unknown')),
    );
    // 预下载后续剧集：设置开启（>0）且进度跨过 80% 时，自动排队
    // 尚未下载的后续 N 集（不打断已有下载队列）。
    try {
      final dm = context.read<DownloadManager>();
      final count = dm.settings.preDownloadCount;
      final type = widget.favoriteType;
      if (count > 0 && type != null) {
        final episodes = widget.episodes;
        if (episodes != null && _episodeIndex < episodes.length - 1) {
          final item = MediaItem(
            id: widget.itemId,
            title: widget.title,
            sourceId: widget.sourceId,
            sourceType: type,
            detailUrl: widget.detailUrl,
            coverUrl: widget.coverUrl,
          );
          unawaited(dm.preDownloadNextEpisodes(
            item: item,
            chapters: episodes,
            fromIndex: _episodeIndex,
            count: count,
          ));
        }
      }
    } on Object {
      // 下载管理器不可用时静默忽略。
    }
  }

  /// Stall（卡顿）处理：弹 SnackBar 提示并自动重新 open 当前地址恢复播放。
  void _onStall() {
    if (!mounted || _disposed) return;
    // 重连进行中或已耗尽：不再重复发起重连（避免重复提示 / 死循环）。
    if (_reconnecting || _reconnectExhausted) return;
    // seek / 重连 seek 后的重新缓冲属正常现象，宽限期内忽略，避免误判卡顿触发
    // 重连（重连会从头播放）。统一用 PlayerController 的 seekGracePeriod 作为唯一标准，
    // 否则两侧窗口不一致会导致「慢速 seek 缓冲 >3s 但 <15s」时仍被误判。
    if (_controller.isWithinSeekGrace) return;
    // 异步 stall 回调可能在 widget 失活后到达：deactivate 虽已置 _disposed 并取消
    // 订阅，但事件可能已排队；此时访问 context（AppLocalizations / ScaffoldMessenger）
    // 会抛「deactivated widget」未捕获异常。用 try 兜底，避免崩溃。
    try {
      final l10n = AppLocalizations.of(context);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.playerStallDetected),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      // context 已失活，忽略。
    }
    unawaited(_reconnect());
  }

  /// 解码自动降级回调（PlayerController 检测到硬解异常后已切换 hwdec）：
  /// 提示用户并 re-open 当前地址——mpv 的 hwdec 属性对已在播的解码器
  /// 不一定即时生效，重新 open 才能确保新解码路径落地。
  void _onDecodeFallback(String mode) {
    if (!mounted || _disposed) return;
    try {
      final l10n = AppLocalizations.of(context);
      final String label = switch (mode) {
        'hw+' => l10n.playerDecodeHwPlus,
        'sw' => l10n.playerDecodeSw,
        _ => mode,
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.playerDecodeFallback(label)),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (_) {
      // context 已失活，忽略提示。
    }
    // 降级仅对本次会话生效，不写回全局 PlayerSettings。
    final url = _playUrl;
    if (url == null || url.isEmpty || _reconnecting) return;
    _reconnecting = true;
    unawaited(() async {
      try {
        await _reopenAndResume(url, _playHeaders, _lastGoodPosition);
      } on Object {
        // 重开失败静默忽略，stall 检测会接管后续恢复。
      } finally {
        _reconnecting = false;
      }
    }());
  }

  /// 手动切换解码模式：设置 hwdec 后 re-open 当前地址。
  ///
  /// 与 [_onDecodeFallback] 同理——mpv 的 hwdec 属性对已在播的解码器
  /// 不一定即时生效，不 re-open 的话用户手动切“软解”形同虚设。
  Future<void> _applyHwdecAndReopen(String mode) async {
    if (_disposed || mode == _controller.currentHwdec) return;
    await _controller.setHwdec(mode);
    final url = _playUrl;
    if (url == null || url.isEmpty || _reconnecting) return;
    _reconnecting = true;
    try {
      await _reopenAndResume(url, _playHeaders, _lastGoodPosition);
    } on Object {
      // 重开失败静默忽略，stall 检测会接管后续恢复。
    } finally {
      _reconnecting = false;
    }
  }

  /// 重新 open 当前播放地址恢复播放。
  ///
  /// 关键点：
  /// 1) 重连前用 [_lastGoodPosition]（可信非零进度）作为恢复点；open() 会把播放器重置到
  /// 起点且短暂的 position 事件可能为 0，若直接用 [_position] 可能被瞬间的 0 覆盖而从头播放。
  /// 2) open 后 m3u8 元数据可能尚未就绪，立即 seek 会落空；故先 [_waitUntilReady] 等元数据，
  /// 再采用「seek + 短暂等待 + 校验，接近 0 则重试」的稳健策略。
  /// 3) 重连的 seek 经 [PlayerController.seek] 更新 lastSeekAt，使重连后的重新缓冲处于 seek
  /// 宽限期内，避免「重连→卡顿→再重连」的死循环。
  /// 自动重连（stall 恢复）。
  ///
  /// 关键修复（修正前一轮）：前一轮改为"中途重建播放器"反而必现黑屏（进度对但无画面），
  /// 且浏览器对同一链接 seek 正常，说明问题在播放器实例需 re-open 自愈而非重建；故改为
  /// 同实例 stop() + open() + 稳健 seek 恢复。
  ///
  /// 为防止无限循环，限制自动重连次数 [_kMaxReconnectAttempts]；耗尽后不再自动重连，
  /// 由 UI 展示「视频链接已失效，点击重试」，用户手动触发（会重新解析拿到未过期的新直链）。
  Future<void> _reconnect() async {
    if (_reconnecting || _reconnectExhausted || _disposed) return;
    _reconnecting = true;
    _reconnectAttempts++;
    try {
      final url = _playUrl;
      final headers = _playHeaders;
      if (url == null || url.isEmpty) return;
      await _reopenAndResume(url, headers, _lastGoodPosition);
    } on Object {
      // 重开失败，受 max attempts 限制，不会无限循环。
    } finally {
      _reconnecting = false;
      if (_reconnectAttempts >= _kMaxReconnectAttempts &&
          !_reconnectExhausted) {
        // 故障回退：当前线路重连耗尽，仍有未尝试的候选线路则自动切换下一条，
        // 而非直接弹「链接失效」让用户手点。所有候选都试过才放弃。
        final failedIndex = _controller.currentLineIndex;
        _triedLineIndices.add(failedIndex);
        final next = _autoSelectLine ? _nextUntriedLine() : null;
        if (next != null) {
          _reconnectExhausted = false;
          _reconnectAttempts = 0;
          final fromName = _controller.lines[failedIndex].name;
          final toName = _controller.lines[next].name;
          unawaited(_switchActiveLine(next, remember: false));
          if (mounted) {
            try {
              _safeSnackBar(AppLocalizations.of(context)
                  .playerLineFailover(fromName, toName));
            } on Object {
              // context 已失活，忽略。
            }
          }
        } else {
          _reconnectExhausted = true;
          if (mounted) setState(() {});
        }
      }
    }
  }

  /// 在同一 Player 实例上重新打开并恢复到 [resumeAt]。
  ///
  /// 不走"中途 dispose/recreate 播放器"：实测重建 VideoController 会导致黑屏
  /// （进度对但无画面），且浏览器对同一链接 seek 正常，说明问题不在 URL/服务端，
  /// 而在播放器实例需通过 re-open 自愈。故先 stop() 清空可能卡死的播放状态，
  /// 再 open + 等元数据就绪 + 稳健 seek 回断流点并播放。流订阅与 stall 检测沿用同一
  /// 实例，无需重新绑定；倍速/解码/比例等 player 级属性也自然保留。
  Future<void> _reopenAndResume(
    String url,
    Map<String, String>? headers,
    Duration resumeAt,
  ) async {
    // 清空可能卡死的播放状态，避免 open() 在异常态下无法重新拉流。
    try {
      await _controller.player.stop();
    } on Object {
      // stop 失败忽略，open 仍会重建当前媒体。
    }
    await _controller.open(url, headers: headers);
    // 按来源分级超时等元数据（媒体服务器 30s / 直链 6s / 本地 5s）。
    await _waitUntilReady(_readyTimeout);
    // 稳健 seek：open 后首帧/分片可能未到位，校验位置，接近 0 则重试。
    for (var attempt = 0; attempt < 6; attempt++) {
      await _controller.seek(resumeAt);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (resumeAt <= Duration.zero) break;
      final cur = _controller.position;
      if (cur > Duration.zero && cur >= resumeAt - const Duration(seconds: 3)) {
        break;
      }
    }
    await _controller.play();
  }

  /// 用户手动重试：重新解析拿到未过期的新直链，再重新打开播放器恢复播放。
  ///
  /// 自动重连耗尽（[_kMaxReconnectAttempts]）后，旧签名直链多半已失效，必须重新解析；
  /// 解析可能弹出 WebView 验证，故仅由用户主动触发，不自动进行。
  Future<void> _manualRetry() async {
    if (_disposed) return;
    _reconnectExhausted = false;
    _reconnectAttempts = 0;
    if (mounted) setState(() {});
    String? url = _playUrl;
    Map<String, String>? headers = _playHeaders;
    if (!_isDirectMode) {
      try {
        // 重试前清空视频地址缓存——缓存里可能存着已过期的签名直链，
        // 不清会导致反复拿到旧 URL 而「假死」；清空后重新解析拿到新链接。
        clearResolvedVideoCache();
        final repo = context.read<SourceRepository>();
        final service = context.read<MediaApiService>();
        final source = repo.getById(widget.sourceId);
        if (source != null) {
          final video = await _resolveVideoWithCapture(
              service, source, widget.episode.url);
          if (video.url.isNotEmpty) {
            url = video.url;
            headers = video.headers;
            _playUrl = video.url;
            _playHeaders = video.headers;
          }
        }
      } on Object {
        // 重新解析失败（如需要人工验证），沿用旧地址继续尝试。
      }
    }
    if (url == null || url.isEmpty) return;
    _reconnecting = true;
    try {
      await _reopenAndResume(url, headers, _lastGoodPosition);
    } on Object {
      // 重开失败，静默忽略。
    } finally {
      _reconnecting = false;
    }
  }

  /// 等待播放器元数据就绪（duration 变为正数），超时返回 false。
  ///
  /// open() 之后 m3u8 需要重新拉取 playlist 与首段分片，元数据就绪前 seek 会失效，
  /// 因此重连恢复前先等到 duration 已知（或超时兜底）。
  Future<bool> _waitUntilReady(Duration timeout) async {
    if (_controller.duration > Duration.zero) return true;
    final completer = Completer<bool>();
    late final StreamSubscription<Duration> sub;
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(false);
    });
    sub = _controller.durationStream.listen((d) {
      if (d > Duration.zero && !completer.isCompleted) {
        completer.complete(true);
      }
    });
    final result = await completer.future;
    timer.cancel();
    await sub.cancel();
    return result;
  }

  /// 按媒体来源分级的就绪等待超时。
  ///
  /// 源解析的媒体服务器（CMS / P2P 分发，冷启动慢）30s；直链网络地址 6s；
  /// 本地文件 5s。供 [_waitUntilReady] / [_seekWhenReady] 与 controller
  /// 的 `openReadyTimeout` 统一取值。
  Duration get _readyTimeout {
    if (!_isDirectMode) return const Duration(seconds: 30);
    // 媒体服务器：公益机首包慢，元数据就绪等待放宽到 30s；配合自愈重开
    // 最多两轮（约 60s+），仍不出画才会停在错误提示。
    if (_isMediaServer) return const Duration(seconds: 30);
    final url = _playUrl ?? '';
    final isNetwork = url.startsWith('http://') || url.startsWith('https://');
    return isNetwork ? const Duration(seconds: 6) : const Duration(seconds: 5);
  }

  /// open 后元数据未就绪的自愈重开。
  ///
  /// 常规源重开一次；媒体服务器（公益机慢速首包）最多重开两轮——
  /// 每轮按 [_readyTimeout] 等待，总计约 60s+ 后才放弃自愈。
  /// 切集 / 重连会推进 [_loadSession] 代次，使过期 token 的重试短路，
  /// 避免误重试新地址；重连进行中（[_reconnecting]）也跳过。
  Future<void> _retryOpenOnceIfStalled() async {
    final maxAttempts = _isMediaServer ? 2 : 1;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final token = _loadSession.current;
      final ready = await _waitUntilReady(_readyTimeout);
      if (ready || _disposed || _reconnecting || !_loadSession.isValid(token)) {
        return;
      }
      final url = _playUrl;
      if (url == null || url.isEmpty) return;
      // 媒体服务器：重开前先探针流地址——把「Cloudflare 质询拦截 /
      // 服务器不可达」变成可行动的明确报错，而不是无限加载。
      if (_isMediaServer) {
        final probe = await widget.mediaServerPlayback!.client.probeStreamUrl(
          url,
        );
        if (_disposed || !_loadSession.isValid(token)) return;
        if (probe.isChallenge) {
          _controller.pause();
          if (mounted) {
            _safeSnackBar(
              AppLocalizations.of(context).mediaServerBlockedByChallenge,
            );
          }
          return;
        }
        if (probe.networkError) {
          _controller.pause();
          if (mounted) {
            _safeSnackBar(AppLocalizations.of(context).mediaServerUnreachable);
          }
          return;
        }
      }
      _controller.openReadyTimeout = _readyTimeout;
      AppLog.instance.w(
        '[] open 后 ${_readyTimeout.inSeconds}s 元数据未就绪，'
        '自愈重开（$attempt/$maxAttempts）：$url',
      );
      try {
        await _reopenAndResume(url, _playHeaders, _lastGoodPosition);
      } on Object {
        // 重开失败交给 stall 检测 / 手动重试。
      }
    }
  }

  /// resolve 当前网络 / 设备条件并应用到 mpv demuxer 缓存。
  Future<void> _applyDemuxerCachePolicy() async {
    try {
      final bool metered = await _cachePolicyResolver.isMeteredNetwork();
      final bool lowMem = await _cachePolicyResolver.isLowMemoryDevice();
      final profile = await _cachePolicyResolver.resolve();
      await _controller.applyDemuxerCacheProfile(profile);
      AppLog.instance.i(
        '[播放缓存] 档位=${profile.name}（计费网络=$metered，低内存=$lowMem）',
      );
      // 一次性回读实际解码器：软/硬解是「播放卡顿」类反馈的首要排查项
      // （鸿蒙若 mpv 硬解后端缺失会静默回退软解），延迟数秒等 demuxer 就绪。
      Future<void>.delayed(const Duration(seconds: 5), () async {
        try {
          final String? hwdec =
              await _controller.backend.getProperty('hwdec-current');
          AppLog.instance.i('[播放解码] hwdec-current=${hwdec ?? '未知'}');
        } on Object {
          // 属性查询失败不影响播放。
        }
      });
    } on Object {
      // 解析或应用失败保持现状（后端默认标准档），不影响播放。
    }
  }

  void _goPrevEpisode() {
    if (_episodeIndex <= 0) return;
    _changeEpisode(_episodeIndex - 1);
  }

  Future<void> _changeEpisode(int index) async {
    if (widget.episodes == null ||
        index < 0 ||
        index >= widget.episodes!.length) {
      return;
    }
    // 手动切集取消进行中的连播倒计时（倒计时归零触发的切集除外，
    // 归零路径先取消再切，此处只会拦到用户手动操作）。
    _cancelAutoNextCountdown();
    // 代次守卫：快速连播 / 手动切集并发时，丢弃过期切换，避免旧集覆盖新集。
    final int token = _loadSession.next();
    // 睡眠定时跨集保留：切集不取消定时器——用户设的「30 分钟后暂停」
    // 在连播场景下应继续生效，否则换集后定时被静默清除。仅「关闭定时」
    // （_showSleepTimerPicker 的关闭项）与退出播放器（dispose）才取消。
    // 保存当前集播放位置
    _saveCurrentPosition();
    // 新一集的续播恢复尚未开始：先关闸，防止新媒体 open 时的 position=0
    // 覆盖这一集原有的存档。
    _positionRestoreDone = false;
    // 记录切集前的索引，切集失败时回滚，避免界面停在「新集」但画面仍是旧集。
    final int oldIndex = _episodeIndex;
    setState(() {
      _episodeIndex = index;
      _position = Duration.zero;
      _nextEpisodePreloaded = false;
      _lastPositionSaveAt = DateTime.fromMillisecondsSinceEpoch(0);
      // 切集重置重连状态：上一集的重连耗尽不应影响本集。
      _reconnectExhausted = false;
      _reconnectAttempts = 0;
      // 新的一集重新允许跳过片头/片尾。
      _opSkippedThisEpisode = false;
      _edSkippedThisEpisode = false;
      // 新一集恢复「播放自动全屏」资格。
      _autoFullscreenDone = false;
      // 新一集重新按视频比例判定横竖（跟随视频模式；手动旋转覆盖保留）。
      _videoWidth = null;
      _videoHeight = null;
      _autoOrientationApplied = false;
    });

    final ep = widget.episodes![index];
    widget.onEpisodeChange?.call(ep);
    // 跟随新 ep 的 lineName 同步（详情页 chips 选定后保持同一线路）。
    _selectedLine = ep.lineName;

    // 媒体服务器切集：结算当前集会话 → 协商新集直连地址（慢速服务器可能
    // 数秒，播放器已有缓冲态）→ 换源开播 → 重建会话并按服务器进度续播。
    if (_isMediaServer) {
      final pb = widget.mediaServerPlayback!;
      final oldSession = _serverSession;
      _serverSession = null;
      if (oldSession != null) {
        unawaited(oldSession.stop(positionMs: _position.inMilliseconds));
      }
      PlaybackInfoResult info;
      try {
        info = await pb.resolveAt(index);
      } on Object catch (e) {
        if (!_loadSession.isValid(token)) return;
        // 协商失败：回滚索引，停留在当前集（画面未动）。
        setState(() => _episodeIndex = oldIndex);
        _positionRestoreDone = true;
        final l10n = AppLocalizations.of(context);
        _safeSnackBar(l10n.mediaServerOperationFailed('$e'));
        return;
      }
      if (!_loadSession.isValid(token)) return;
      final target = pb.current;
      _serverLastInfo = info;
      _serverAudioStreamIndex = null;
      _playUrl = info.playUrl;
      _playHeaders = info.headers;
      _controller.openReadyTimeout = _readyTimeout;
      await _controller.open(info.playUrl, headers: info.headers);
      _controller.play();
      // 分级超时等待元数据，超时自动 re-open 一次自愈。
      unawaited(_retryOpenOnceIfStalled());
      _danmakuController.clear();
      _danmakuController.reset();
      if (!_loadSession.isValid(token)) return;
      _serverSession = MediaServerPlaybackSession(
        client: pb.client,
        itemId: target.id,
        playSessionId: info.playSessionId,
        initialPositionTicks: target.userData?.playbackPositionTicks ?? 0,
        runTimeTicks: info.runTimeTicks ?? target.runTimeTicks,
        playMethod: info.playMethod,
      );
      unawaited(_restoreSavedPosition());
      unawaited(
        _serverSession!.start(positionMs: _serverSession!.initialPositionMs),
      );
      return;
    }

    // 本地 / 直链多集模式：直接打开该集本地文件，跳过在线源解析与换源。
    // 合并为一部的本地视频（folderPaths 每文件=一集）依赖此分支实现上下集切换。
    if (_isDirectMode) {
      String direct = ep.url;
      if (isDocUri(direct)) {
        try {
          direct = await resolveSafVideoFile(direct);
          AppLog.instance.i('[本地视频切集] SAF/content 已解析为真实文件：$direct');
        } on Object catch (e) {
          AppLog.instance.eWithStack('[本地视频切集] SAF 解析失败：$direct', e);
        }
      }
      _playUrl = direct;
      _playHeaders = null;
      if (!_loadSession.isValid(token)) return;
      await _controller.open(direct);
      _controller.play();
      // 分级超时等待元数据，超时自动 re-open 一次自愈。
      unawaited(_retryOpenOnceIfStalled());
      _danmakuController.clear();
      _danmakuController.reset();
      // 重新加载弹幕（使用新剧集 ID）
      _loadDanmakuForEpisode(ep);
      // 恢复新剧集的上次播放位置（关闭记住位置时跳过，但需开闸以允许本集保存进度）
      if (widget.restoreProgress) {
        await _restoreSavedPosition();
      } else {
        _positionRestoreDone = true;
        _lastPositionSaveAt = DateTime.now();
      }
      return;
    }

    final repo = context.read<SourceRepository>();
    final service = context.read<MediaApiService>();
    final source = repo.getById(widget.sourceId);
    if (source == null) return;

    try {
      final video = await _resolveVideoWithCapture(service, source, ep.url);
      String playUrl = video.url;
      Map<String, String>? playHeaders = video.headers;
      _playUrl = playUrl;
      _playHeaders = playHeaders;
      // 切集后刷新线路列表（源提供多线路时直接使用 video.lines）。
      if (video.url.isNotEmpty) {
        _controller.lines = _buildLines(video);
        _controller.currentLineIndex = 0;
        // 重置本集选路状态；手动记忆的线路优先。
        _resolvedLineIndices
          ..clear()
          ..add(0);
        _triedLineIndices.clear();
        final memName =
            await _lineStore.getSelectedLine(widget.sourceId, ep.id);
        if (memName != null) {
          final idx = _indexOfLineName(memName);
          if (idx != null && idx != 0) {
            final resolved = await _resolveLineUrl(idx);
            if (resolved != null) {
              _controller.lines[idx] = resolved;
              _resolvedLineIndices.add(idx);
              playUrl = resolved.url;
              playHeaders = resolved.headers;
              _controller.currentLineIndex = idx;
            }
          }
        }
        _playUrl = playUrl;
        _playHeaders = playHeaders;
      }
      if (!_loadSession.isValid(token)) return;
      await _controller.open(playUrl, headers: playHeaders);
      // 切集后自动播放
      _controller.play();
      // 分级超时等待元数据（媒体服务器 30s），超时自动 re-open 一次自愈。
      unawaited(_retryOpenOnceIfStalled());
      _danmakuController.clear();
      _danmakuController.reset();
      // 重新加载弹幕（使用新剧集 ID）
      _loadDanmakuForEpisode(ep);
      // 恢复新剧集的上次播放位置（关闭记住位置时跳过，但需开闸以允许本集保存进度）
      if (widget.restoreProgress) {
        await _restoreSavedPosition();
      } else {
        _positionRestoreDone = true;
        _lastPositionSaveAt = DateTime.now();
      }
    } on Object catch (e) {
      // 切集失败：界面若停在「新集」但画面仍是旧集，须回滚索引并提示，
      // 避免用户误以为已切换成功。
      AppLog.instance.eWithStack('[切集失败] index=$index', e);
      if (!_loadSession.isValid(token)) return;
      if (mounted) {
        setState(() => _episodeIndex = oldIndex);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
              content: Text(
                  AppLocalizations.of(context)!.playerEpisodeSwitchFailed)),
        );
      }
      // 切集失败也需开闸，否则该集永远不再保存进度。
      _positionRestoreDone = true;
    }
    // 切集后更新「最近播放」的起始集（成功=新集，失败回滚=旧集）。
    if (mounted) {
      unawaited(_persistCurrentEpisode(_episodeIndex));
    }
    // 切集成功刷新后台通知（标题/上下集按钮）。
    if (_positionRestoreDone) _attachBackgroundPlayback();
  }

  /// 把当前播放会话注册到系统媒体通知（后台播放 / 锁屏控制）。
  ///
  /// 使用当前集标题 + 作品名构建 [MediaItem]，并把控制器的播放/暂停/seek/
  /// 上/下一集回调转发给 [AudioPlaybackService]。attach 内部按代次自增，
  /// 返回的 token 供 dispose 时 detach 校验。Windows/Web 不支持时服务层
  /// 静默降级为无操作（不影响前台播放）。
  void _attachBackgroundPlayback() {
    if (!_controllerCreated) return;
    final int epIndex = _episodeIndex;
    final String title = _currentEpisodeTitle();
    // 当前集 ID：切集后须用当前集而非初始集（widget.episode 不可变），
    // 否则通知栏 MediaItem.id 不刷新、跨集不更新标题关联。
    final String currentEpId = (widget.episodes != null &&
            epIndex >= 0 &&
            epIndex < widget.episodes!.length)
        ? widget.episodes![epIndex].id
        : widget.episode.id;
    final bool hasNext = widget.episodes != null &&
        epIndex >= 0 &&
        epIndex < widget.episodes!.length - 1;
    final bool hasPrev = widget.episodes != null && epIndex > 0;
    _bgToken = AudioPlaybackService.instance.attach(AudioPlaybackSession(
      id: '${widget.sourceId}::$currentEpId',
      title: title,
      artist: widget.title,
      positionStream: _controller.positionStream,
      durationStream: _controller.durationStream,
      playingStream: _controller.playingStream,
      onPlay: () => _controller.play(),
      onPause: () => _controller.pause(),
      onSeek: (Duration p) => _controller.seek(p),
      onNext: hasNext ? () async => _goNextEpisode() : null,
      onPrev: hasPrev ? () => _changeEpisode(epIndex - 1) : null,
    ));
  }

  /// 当前集标题（切集后随 [_episodeIndex] 变化）。
  String _currentEpisodeTitle() {
    if (widget.episodes != null &&
        _episodeIndex >= 0 &&
        _episodeIndex < widget.episodes!.length) {
      return widget.episodes![_episodeIndex].title;
    }
    return widget.episode.title;
  }

  /// 保存当前集播放位置到 MediaPlaybackPositionManager。
  /// 退出时保存当前集播放位置到 MediaPlaybackPositionManager。
  /// 媒体服务器：进度双写——本地命名空间落盘 + 服务器上报由调用方处理。
  void _saveCurrentPosition() {
    if (_isMediaServer) {
      final mgr = _positionManager;
      if (mgr == null) return;
      unawaited(mgr.savePosition(
        widget.mediaServerPlayback!.currentContentId,
        _episodeIndex,
        _position.inMilliseconds,
      ));
      return;
    }
    // 与 [_maybeSavePosition] 同理：恢复未完成时（如加载中就退出）不写盘，
    // 否则会把上次的续播点抹成 0。
    if (!_positionRestoreDone) return;
    // 用 _init 阶段缓存的引用：dispose 期 context 已失活，
    // 不能再用 context.read（会被 catch 吞掉导致最后一段进度丢失）。
    final mgr = _positionManager;
    if (mgr == null) return;
    unawaited(mgr.savePosition(
        widget.itemId, _episodeIndex, _position.inMilliseconds));
  }

  /// 切集弹幕加载：与首载 [_loadDanmaku] 统一走共用加载逻辑，
  /// 保证凭据提示 / 自定义 URL 空值跳过行为一致。
  Future<void> _loadDanmakuForEpisode(Episode ep) => _loadDanmakuFor(ep);

  void _toggleDanmaku() {
    setState(() => _danmakuOn = !_danmakuOn);
    if (!_danmakuOn) {
      _danmakuKey.currentState?.clear();
    }
  }

  void _toggleUi() {
    // PiP 小窗内不响应显隐切换：小窗放不下控制层，弹出即铺满画面。
    if (_inPip) return;
    // 双击后 600ms 内屏蔽单击，防止双击手势的尾随单击误触显隐控制栏。
    if (DateTime.now().difference(_lastDoubleTapAt) <
        const Duration(milliseconds: 600)) {
      return;
    }
    setState(() => _uiVisible = !_uiVisible);
    if (_uiVisible) {
      _scheduleUiHide();
    } else {
      _uiHideTimer?.cancel();
    }
  }

  /// 启动 / 重启控制层自动隐藏倒计时。
  ///
  /// 仅在「正在播放」时生效：暂停、锁定态或已隐藏时不安排隐藏，避免用户
  /// 暂停后找不到播放键。
  void _scheduleUiHide() {
    _uiHideTimer?.cancel();
    if (_disposed || !mounted) return;
    // 拖动进度 / 菜单打开期间持有控制栏，不安排自动隐藏。
    if (_panelHoldCount > 0) return;
    if (!_isPlaying) return;
    _uiHideTimer = Timer(_kUiAutoHide, () {
      if (_disposed || !mounted) return;
      // 二次校验：倒计时期间可能已暂停 / 已手动隐藏 / 新持有租约。
      if (_panelHoldCount > 0 || !_isPlaying || !_uiVisible) return;
      setState(() => _uiVisible = false);
    });
  }

  /// 任意指针按下时延长控制层停留时间（不改变可见性，仅重置倒计时）。
  ///
  /// 挂在播放器最外层 [Listener] 上：即便点击被底栏按钮消费，祖先 Listener
  /// 仍会收到 pointer down，从而实现「操作中控制条不消失」。
  void _bumpUiHideTimer() {
    if (!_uiVisible) return;
    _scheduleUiHide();
  }

  // 单击显隐控制栏统一由 GestureDetector.onTap → _toggleUi 处理；
  // 双击分区（中=播放/暂停·左=快退·右=快进）见 onDoubleTapDown。

  void _toggleLock() {
    _controller.toggleLock();
    // 延迟 setState 到当前事件帧结束后，避免在手势回调栈中
    // 销毁控制层子 widget（如 TextField / FocusNode）导致异常。
    if (mounted) {
      Future<void>.microtask(() {
        if (mounted) setState(() {});
      });
    }
  }

  // ─────────────────────── 手势 / 亮度 / 音量（视频还原） ───────────────────────

  void _safeSnackBar(String message) {
    try {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
    } on Object {
      // context 已失活，忽略。
    }
  }

  void _refreshFavorite() {
    final type = widget.favoriteType;
    if (type == null) return;
    try {
      final fav = context.read<FavoritesManager>();
      _isFav = fav.isFavorite(widget.itemId, type);
    } on Object {
      // FavoritesManager 不可用时静默忽略。
    }
  }

  /// 切换收藏状态（顶栏收藏按钮）。
  Future<void> _toggleFavorite() async {
    final type = widget.favoriteType;
    if (type == null) return;
    final l10n = AppLocalizations.of(context);
    final fav = context.read<FavoritesManager>();
    final wasFavorite = _isFav;
    final item = MediaItem(
      id: widget.itemId,
      title: widget.title,
      sourceId: widget.sourceId,
      sourceType: type,
      detailUrl: widget.detailUrl,
      coverUrl: widget.coverUrl,
    );
    // MD3「Toggle」：收藏开关切换 → tick。
    wasFavorite ? AppHaptics.toggleOff() : AppHaptics.toggleOn();
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
    final type = widget.favoriteType;
    if (type == null) {
      await _toggleFavorite();
      return;
    }
    final MediaItem item = MediaItem(
      id: widget.itemId,
      title: widget.title,
      sourceId: widget.sourceId,
      sourceType: type,
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

  // ─────────────────────── 键盘快捷键 ───────────────────────

  Future<void> _onSeek(Duration position) async {
    await _controller.seek(position);
    // 弹幕游标拨回目标位置附近（只重放窗口内弹幕），与 tick 用同一时间基准
    // （含 timeOffset），避免 seek 回看时把整条时间轴的弹幕一次性灌进屏幕。
    final adjusted = position +
        Duration(milliseconds: (_danmakuSettings.timeOffset * 1000).round());
    _danmakuController.resetTo(adjusted);
    setState(() => _position = position);
  }

  /// 打开弹幕设置面板（底部 modal bottom sheet）。
  Future<void> _openDanmakuSettings() async {
    // 面板打开期间持有控制栏，禁止自动隐藏。
    _acquirePanelHold();
    try {
      await DanmakuSettingsSheet.show(
        context,
        settings: _danmakuSettings,
        onChanged: (next) {
          setState(() => _danmakuSettings = next);
          _applyDanmakuOption();
          unawaited(_saveDanmakuSettings());
        },
        onMatch: _openDanmakuMatch,
      );
    } finally {
      _releasePanelHold();
    }
  }

  /// 打开「手动匹配弹幕」面板，用户搜索番剧并选定集数后应用到当前集。
  Future<void> _openDanmakuMatch() async {
    if (_danmakuRepo == null) return;
    final id = await DanmakuMatchSheet.show(
      context,
      repo: _danmakuRepo!,
      initialKeyword: widget.title,
      currentEpisodeId: widget.episode.id,
    );
    if (id != null) {
      _dandanOverride[widget.episode.id] = id;
      _danmakuController.clear();
      _danmakuController.reset();
      _loadDanmaku();
    }
  }

  void _openDanmakuSource() async {
    // MD3「Thunk」：长按打开弹幕源设置。
    AppHaptics.thunk();
    // 面板打开期间持有控制栏，禁止自动隐藏。
    _acquirePanelHold();
    try {
      await DanmakuSourceSheet.show(
        context,
        currentSource: _danmakuSource,
        currentCustomUrl: _customDanmakuUrl,
        onChanged: (next) async {
          if (next == _danmakuSource) return;
          setState(() => _danmakuSource = next);
          // 持久化用户选择。
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_kDanmakuSourceKey, next.name);
          } on Object {
            // 写入失败静默忽略。
          }
          // 清空并重新加载弹幕。
          _danmakuController.clear();
          _danmakuController.reset();
          _loadDanmaku();
        },
        onCustomUrl: (url) async {
          setState(() {
            _customDanmakuUrl = url;
            _danmakuSource = DanmakuSourceType.customUrl;
          });
          // 持久化 URL 和源选择。
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_kDanmakuCustomUrlKey, url);
            await prefs.setString(
                _kDanmakuSourceKey, DanmakuSourceType.customUrl.name);
          } on Object {
            // 写入失败静默忽略。
          }
          _danmakuController.clear();
          _danmakuController.reset();
          _loadDanmaku();
        },
      );
    } finally {
      _releasePanelHold();
    }
  }

  /// 倍速选择面板（底部弹出，点击即生效）。
  void _showSpeedPicker(AppLocalizations l10n) {
    const speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];
    final current = _controller.playbackSpeed;

    // 面板打开期间持有控制栏，禁止自动隐藏。
    _acquirePanelHold();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        final mq = MediaQuery.of(ctx);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: mq.size.height * 0.85),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(AppTokens.spaceMd),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          l10n.playerPlaybackSpeed,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        '${current}x',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                      const SizedBox(width: AppTokens.spaceSm),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    shrinkWrap: true,
                    children: speeds
                        .map((s) => ListTile(
                              dense: true,
                              title: Center(child: Text('${s}x')),
                              // 选中态统一：primary 色 check（与设置页弹层一致）。
                              trailing: (s == current)
                                  ? Icon(Icons.check_rounded,
                                      color: Theme.of(ctx).colorScheme.primary)
                                  : null,
                              onTap: () {
                                unawaited(_controller.setPlaybackSpeed(s));
                                _playerSettings =
                                    _playerSettings.copyWith(playbackSpeed: s);
                                unawaited(
                                    _saveEpisodeSetting('playbackSpeed', s));
                                _applyDanmakuOption();
                                Navigator.pop(ctx);
                              },
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: AppTokens.spaceSm),
              ],
            ),
          ),
        );
      },
    )
        // 面板关闭后释放控制栏租约。
        .whenComplete(_releasePanelHold);
  }

  /// 功能5：选择长按自定义倍速值（更多菜单入口）。
  Future<void> _pickLongPressSpeed(BuildContext ctx) async {
    const options = <double>[1.5, 2.0, 2.5, 3.0];
    final selected = await showModalBottomSheet<double>(
      context: ctx,
      isScrollControlled: true,
      builder: (BuildContext sheetCtx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetCtx).size.height * 0.85),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ...options.map((s) => ListTile(
                      dense: true,
                      title: Center(child: Text('${s}x')),
                      trailing: s == _playerSettings.longPressSpeed
                          ? Icon(Icons.check_rounded,
                              color: Theme.of(sheetCtx).colorScheme.primary)
                          : null,
                      onTap: () => Navigator.pop(sheetCtx, s),
                    )),
                const SizedBox(height: AppTokens.spaceSm),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected != null) {
      setState(() {
        _playerSettings = _playerSettings.copyWith(longPressSpeed: selected);
      });
      await _saveEpisodeSetting('longPressSpeed', selected);
    }
  }

  void _applyDanmakuOption() {
    if (!mounted || _disposed) return;
    // _controller 在 initState 同步创建，正常非空；但为防止极端时序下
    // playbackSpeed 读取抛异常（release 下未捕获即崩进程），此处做兜底。
    double speed = 1.0;
    try {
      speed = _controller.playbackSpeed;
    } on Object {
      // 读取失败则回退到 1.0（speed 已初始化为此值）。
    }
    final effectiveDuration = _danmakuSettings.effectiveDuration(speed);
    final option = cd.DanmakuOption(
      duration: effectiveDuration,
      fontSize: _danmakuSettings.fontSize,
      opacity: _danmakuSettings.opacity,
      area: _danmakuSettings.area,
      lineHeight: _danmakuSettings.lineHeight,
      hideTop: _danmakuSettings.hideTop,
      hideBottom: _danmakuSettings.hideBottom,
      hideScroll: _danmakuSettings.hideScroll,
    );
    try {
      _danmakuKey.currentState?.updateOption(option);
    } on Object catch (e, st) {
      debugPrint('[_applyDanmakuOption] updateOption 失败（已忽略）: $e\n$st');
    }
  }

  void deactivate() {
    // 关键：deactivate 阶段元素已失活但 mounted 仍为 true，必须在此切断
    // stall/position/completed 流订阅并置位 _disposed，否则退场瞬间流回调
    // 仍可能访问 context（InheritedWidget）触发「deactivated widget」崩溃。
    _disposed = true;
    _positionSub?.cancel();
    _completedSub?.cancel();
    _stallSub?.cancel();
    _decodeFallbackSub?.cancel();
    _bufferingSub?.cancel();
    _playingSub?.cancel();
    _playingFalseDebounce?.cancel();
    _pipActionSub?.cancel();
    _pipActionSub = null;
    _videoWidthSub?.cancel();
    _videoHeightSub?.cancel();
    // 关闭可能残留的 SnackBar：其退出动画的 AnimationController 在 widget 失活后
    // 仍会 tick，并尝试访问已销毁的 Scaffold 祖先 → 抛「deactivated widget」
    // （见用户日志 AnimationController#...for SnackBar）。deactivate 阶段 context
    // 仍有效，用 maybeOf 安全隐藏（ScaffoldMessenger.of 会抛同一异常）。
    // 必须在 super.deactivate() 前调用（之后 element 即从树中摘下）。
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 跨设备接续：退场后本页不再作为接续来源。
    final Object? continuationToken = _continuationToken;
    if (continuationToken != null) {
      _continuationToken = null;
      HarmonyContinuation.detach(continuationToken);
    }
    // 退出时保存最后播放位置（媒体服务器改走会话 Stopped 上报）。
    _saveCurrentPosition();
    if (_isMediaServer) {
      final session = _serverSession;
      if (session != null) {
        unawaited(
          session.stop(positionMs: _position.inMilliseconds),
        );
      }
    }
    // 退出时一次性结算本次会话的观看时长（commit 内部 best-effort）。
    // 媒体服务器条目不进本地统计体系（§2.5）。
    if (widget.sourceId.isNotEmpty && !_isMediaServer) {
      unawaited(ReadingSessionRecorder.instance.commit(
        workId: widget.itemId,
        sourceId: widget.sourceId,
        type: StatsMediaType.media,
        title: widget.title,
        coverUrl: widget.coverUrl,
        lastChapterTitle: widget.episode.id,
        source: SessionSource.mediaPlayer,
      ));
    }
    // 兜底保存弹幕显示设置（滑块即时保存之外，确保离开页面必定落盘）。
    unawaited(_saveDanmakuSettings());
    // 视频实时翻译：解绑播放器（保留持久化偏好，下次进入自动恢复）。
    _subtitleTranslator.detach();
    _sleepTimer?.cancel();
    _speedProbeTimer?.cancel();
    // 退出播放器取消连播倒计时并释放通知器。
    _cancelAutoNextCountdown();
    _autoNextCountdownLeft.dispose();
    // 退出播放器清按集睡眠计数（仅"关定时/退出"才取消，切集保留）。
    _sleepEpisodesRemaining = 0;
    _gestureIndicatorTimer?.cancel();
    _uiHideTimer?.cancel();
    _positionSub?.cancel();
    _completedSub?.cancel();
    _stallSub?.cancel();
    _decodeFallbackSub?.cancel();
    _bufferingSub?.cancel();
    _playingSub?.cancel();
    _playingFalseDebounce?.cancel();
    _pipActionSub?.cancel();
    _pipActionSub = null;
    _videoWidthSub?.cancel();
    _videoHeightSub?.cancel();
    // 退出播放器取消网络变化订阅（缓存档位随播放器生命周期）。
    unawaited(_connectivitySub?.cancel());
    _connectivitySub = null;
    // 退出播放器清空 PiP 窗口动作（避免下次进入残留旧动作）。
    // 退出时 PiP 已结束（PiP 模式不会触发 dispose），安全清理。
    unawaited(PipActionsBridge.instance.clearActions());
    _resolveProgress.dispose();
    unawaited(_castService.disconnect());
    _focusNode.dispose();
    // _controller 可能未创建（如 _init 在创建前就抛异常退出），需判空避免
    // LateInitializationError。正常情况下 _init 成功后 _controllerCreated 为 true。
    if (_controllerCreated) {
      _controller.removeListener(_onControllerChanged);
    }
    // 关键：释放视频渲染层。VideoController 在 media_kit_video 2.0.1 没有 dispose()
    // 方法——它的原生 VideoOutput（media_kit 纹理）由底层 Player.dispose() 通过 release
    // 回调统一释放。PlayerController.dispose() 会把该释放的 Future 记入静态
    // PlayerController._pendingDisposal；下一次进入播放器时 _init 会 await
    // PlayerController.pendingDisposal，确保「旧播放器销毁」先于「新播放器创建」，
    // 避免退出重进时新旧 surface 冲突（Lost connection to device）。
    _videoController = null;
    // 退出播放器注销后台媒体通知（token 校验防止误清跨作品换页的新会话）。
    AudioPlaybackService.instance.detach(_bgToken);
    if (_controllerCreated) {
      _controller.dispose();
    }
    // 还原系统亮度（避免退出后保留手势调节值）。
    // 注意：resetScreenBrightness 是异步方法，其 PlatformException 在后续微任务抛出，
    // 同步 try/catch 捕获不到，会形成「Uncaught zone error」；故用 .catchError 兜底。
    _brightnessPlugin
        .resetApplicationScreenBrightness()
        .catchError((Object _) {});
    // 仍在桌面 PiP 时直接退出播放器（返回/Esc/路由替换），兜底恢复
    // 窗口原状（标题栏/尺寸/位置/最大化/置顶），否则小窗状态会残留到其他页面。
    if (_desktopPipActive) {
      unawaited(_exitDesktopPip());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<void>(
        future: _initFuture,
        builder: (BuildContext c, AsyncSnapshot<void> snap) {
          if (snap.connectionState != ConnectionState.done) {
            // 初始化转圈期间叠加解析进度条（功能3），让用户看到"找视频地址"的进度。
            return Stack(
              children: <Widget>[
                const Center(child: CircularProgressIndicator()),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ValueListenableBuilder<double?>(
                    valueListenable: _resolveProgress,
                    builder: (BuildContext _, double? v, Widget? __) {
                      if (v == null) return const SizedBox.shrink();
                      return LinearProgressIndicator(
                        value: v >= 0 ? v : null,
                        minHeight: 3,
                        backgroundColor: Colors.white24,
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.white),
                      );
                    },
                  ),
                ),
              ],
            );
          }
          if (snap.hasError || _videoController == null) {
            // 本地 / 直链模式直接打开失败（如 media_kit 打开超时、文件不可读）
            // 时，展示具体错误而非"视频已失效"，让用户能看懂原因并重试。
            final bool unavailable = snap.error is PlayerUnavailableException;
            final String msg = unavailable
                ? l10n.playerOhosUnsupported
                : (_isDirectMode && snap.error != null)
                    ? snap.error.toString()
                    : l10n.playerVideoExpired;
            return _buildErrorPage(
              AppErrorState(
                message: msg,
                // 注意：setState 的回调必须是 void，不能写 `() => _initFuture = _init()`
                // （赋值表达式会返回 _init() 这个 Future，触发「setState callback returned a Future」崩溃）。
                // 内核不可用（鸿蒙降级）时重试必然失败，不提供重试按钮。
                onRetry: unavailable
                    ? null
                    : () {
                        setState(() {
                          _initFuture = _init();
                        });
                      },
              ),
            );
          }
          return _buildPlayer(l10n);
        },
      ),
    );
  }

  /// 错误页（解析 / 抽取失败、链接失效）：黑底错误态 + 顶部返回栏。
  ///
  /// 错误页没有控制层，而播放器常以全屏沉浸方式打开（桌面端尤其没有系统
  /// 返回手势），不提供显式返回入口时用户只能杀应用——顶部保留一条仅含
  /// 返回键的半透明渐变栏（样式对齐播放顶栏）。
  Widget _buildErrorPage(Widget child) {
    return Stack(
      children: <Widget>[
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Colors.black54, Colors.transparent],
              ),
            ),
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
            child: Row(
              children: <Widget>[
                IconButton(
                  key: const Key('player_error_back'),
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  visualDensity: VisualDensity.compact,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                  padding: const EdgeInsets.all(7),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlayer(AppLocalizations l10n) {
    // 自动重连耗尽：展示「视频链接已失效，点击重试」覆盖层，由用户手动触发
    // 重新解析 + 重新打开播放器（拿到未过期的新直链）。
    if (_reconnectExhausted) {
      return _buildErrorPage(
        AppErrorState(message: l10n.playerVideoExpired, onRetry: _manualRetry),
      );
    }
    // 包裹 Focus 以响应键盘快捷键。
    // pipMode：Android 系统 PiP 或桌面 PiP——小窗内抑制完整控制层
    // （顶栏/底栏/中央按钮/边缘按钮/弹幕），桌面 PiP 换用紧凑控件层。
    final bool pipMode = _inPip || _desktopPipActive;
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      // 最外层 Listener：任何指针按下（含被底栏按钮消费的点击）都会经过祖先
      // 命中路径，用来重置控制层自动隐藏倒计时，保证「操作过程中控制条不消失」。
      child: Listener(
        onPointerDown: (_) => _bumpUiHideTimer(),
        // 桌面 PiP：鼠标移入窗口显示紧凑控件，移出收起（播放中）。
        child: MouseRegion(
          onEnter: _desktopPipActive ? (_) => _pipHoverEnter() : null,
          onExit: _desktopPipActive ? (_) => _pipHoverExit() : null,
          child: Stack(
            children: <Widget>[
              // 视频画面 + 手势系统（双击 中=播放/暂停·左=快退·右=快进 / 左竖滑亮度 / 右竖滑音量 / 横滑 seek 预览）
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                // 功能1：单击显隐控制栏。
                onTap: _toggleUi,
                // 桌面 PiP 模式：拖动视频区域任意处 = 移动窗口（窗口已隐藏标题栏，
                // 这是 PiP 小窗的移动入口）；此时横滑 seek / 竖滑亮度音量停用。
                onPanStart: _desktopPipActive
                    ? (DragStartDetails _) => _pipDragWindow()
                    : null,
                // 功能4：长按切自定义倍速，松手恢复（受 longPressSpeedUp 开关控制）。
                onLongPressStart: (_) => _onLongPressSpeedStart(),
                onLongPressEnd: (_) => _onLongPressSpeedEnd(),
                // 双击：左=快退 10s；中=播放/暂停；右=快进 10s（锁定态忽略）。
                // 连续双击同方向累加（10s→20s→30s，900ms 无后续双击或
                // 换方向则重置），指示器按累加秒数显示。
                onDoubleTapDown: (TapDownDetails d) {
                  if (_controller.isLocked) return;
                  // 双击跳转 / 暂停：轻震确认已识别为双击。
                  AppHaptics.light();
                  final width = context.size?.width ?? 0;
                  final dx = d.localPosition.dx;
                  final int direction =
                      dx < width / 3 ? -1 : (dx > width * 2 / 3 ? 1 : 0);
                  final now = DateTime.now();
                  // 900ms 无后续双击或方向变化 → 重置计数；同方向连击 → 累加（上限 3 次）。
                  if (now.difference(_lastDoubleTapAt) >
                          const Duration(milliseconds: 900) ||
                      direction != _doubleTapDirection) {
                    _doubleTapCount = 1;
                    _doubleTapDirection = direction;
                  } else {
                    _doubleTapCount = (_doubleTapCount + 1).clamp(1, 3);
                  }
                  _lastDoubleTapAt = now;
                  if (direction < 0) {
                    final seconds = 10 * _doubleTapCount;
                    unawaited(_seekBy(Duration(seconds: -seconds)));
                    _showGestureIndicator('-${seconds}s');
                  } else if (direction > 0) {
                    final seconds = 10 * _doubleTapCount;
                    unawaited(_seekBy(Duration(seconds: seconds)));
                    _showGestureIndicator('+${seconds}s');
                  } else {
                    // 中间三分之一：播放/暂停
                    _togglePlayPause();
                  }
                },
                onVerticalDragStart: _desktopPipActive
                    ? null
                    : (DragStartDetails d) {
                        if (_controller.isLocked) return;
                        final width = context.size?.width ?? 1;
                        _dragAxis = d.localPosition.dx < width / 2
                            ? _GestureAxis.verticalLeft
                            : _GestureAxis.verticalRight;
                        _dragStartBrightness = _brightness;
                        _dragStartVolume = _controller.volume;
                      },
                onVerticalDragUpdate: _desktopPipActive
                    ? null
                    : (DragUpdateDetails d) {
                        if (_controller.isLocked) return;
                        if (_dragAxis == _GestureAxis.none) return;
                        final height = context.size?.height ?? 1;
                        // 上滑为正（增量），下滑为负
                        final delta = -d.delta.dy / height;
                        if (_dragAxis == _GestureAxis.verticalLeft) {
                          unawaited(
                              _setBrightness(_dragStartBrightness + delta));
                        } else if (_dragAxis == _GestureAxis.verticalRight) {
                          unawaited(_setVolume(_dragStartVolume + delta * 100));
                        }
                      },
                onVerticalDragEnd: _desktopPipActive
                    ? null
                    : (_) {
                        _dragAxis = _GestureAxis.none;
                      },
                onHorizontalDragStart: _desktopPipActive
                    ? null
                    : (DragStartDetails d) {
                        if (_controller.isLocked) return;
                        _dragAxis = _GestureAxis.horizontal;
                        _seekPreview = _position;
                        // 记录起点 Y 并重置上滑取消状态。
                        _seekDragStartY = d.globalPosition.dy;
                        _seekDragVerticalDelta = 0;
                        _seekDragCancelled = false;
                        _seekDragCancelledFeedback = false;
                      },
                onHorizontalDragUpdate: _desktopPipActive
                    ? null
                    : (DragUpdateDetails d) {
                        if (_controller.isLocked) return;
                        if (_dragAxis != _GestureAxis.horizontal) return;
                        // 计算相对起点的垂直位移，超过阈值 → 取消本次 seek
                        // （松手不跳转）。delta.dy 恒为 0（框架按主轴过滤，见字段
                        // 注释），必须用指针全局 Y 与起点的差值。
                        _seekDragVerticalDelta =
                            d.globalPosition.dy - _seekDragStartY;
                        if (!_seekDragCancelled &&
                            _seekDragVerticalDelta.abs() >
                                _kSeekCancelThreshold) {
                          _seekDragCancelled = true;
                        }
                        if (_seekDragCancelled) {
                          // 取消态：预览目标强制复位为当前进度——双保险，即使松手
                          // 路径意外 seek 也会回到原位，保证「上滑取消不跳转」。
                          _seekPreview = _position;
                          // 首次进入取消态时给一次轻微震动，让「已取消」可被触觉感知
                          //（仅图标常显时用户可能未察觉状态已切换）。
                          if (!_seekDragCancelledFeedback) {
                            _seekDragCancelledFeedback = true;
                            AppHaptics.medium();
                          }
                          // 取消态持续显示提示（重置计时器，松手前保持可见），
                          // 同时明确渲染取消图标，解决「上滑没有取消图标」的问题。
                          _showGestureIndicator(l10n.playerSeekCancel);
                          return;
                        }
                        final width = context.size?.width ?? 1;
                        final delta = d.delta.dx / width;
                        final next = _seekPreview +
                            Duration(
                                seconds: (delta *
                                        _duration.inSeconds *
                                        _seekMultiplierFactor)
                                    .round());
                        _seekPreview = next < Duration.zero
                            ? Duration.zero
                            : (next > _duration ? _duration : next);
                        _showGestureIndicator(
                            '${_formatDuration(_seekPreview)} / ${_formatDuration(_duration)}');
                      },
                onHorizontalDragEnd: _desktopPipActive
                    ? null
                    : (_) {
                        if (_controller.isLocked) {
                          _dragAxis = _GestureAxis.none;
                          return;
                        }
                        if (_dragAxis == _GestureAxis.horizontal) {
                          // 上滑取消后松手不跳转，进度停在原位置。
                          if (!_seekDragCancelled) {
                            unawaited(_controller.seek(_seekPreview));
                          }
                        }
                        _dragAxis = _GestureAxis.none;
                        // 拖拽结束（含取消态）：隐藏指示器并复位取消状态。
                        _gestureIndicatorTimer?.cancel();
                        if (mounted) {
                          setState(() => _gestureIndicatorVisible = false);
                        }
                        _seekDragCancelled = false;
                        _seekDragCancelledFeedback = false;
                        _seekDragVerticalDelta = 0;
                      },
                child: Center(
                  child: _buildVideoSurface(),
                ),
              ),

              // 弹幕覆盖层（PiP 小窗内停用：小窗里弹幕不可读，白白消耗 60fps
              // 绘制，是 PiP 卡顿的显著负载来源之一）。
              Positioned.fill(
                child: IgnorePointer(
                  child: DanmakuOverlay(
                    key: _danmakuKey,
                    enabled: _danmakuOn && !pipMode,
                    controller: _danmakuController,
                  ),
                ),
              ),

              // 视频实时翻译字幕覆盖层（PiP 小窗 / 锁定态停用；译文显示于
              // 底部，控制栏可见时抬高避让。整层 IgnorePointer 不影响手势）。
              if (!pipMode && !_controller.isLocked)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: _uiVisible ? 132 : 36,
                  child: IgnorePointer(
                    child: Center(
                      child: TranslatedSubtitleOverlay(
                          controller: _subtitleTranslator),
                    ),
                  ),
                ),

              // 桌面 PiP 紧凑控件层（悬停/点按显示）：关闭、播放/暂停、进度条。
              if (_desktopPipActive) _buildDesktopPipControls(l10n),

              // 中央手势指示器（锁定态 / PiP 小窗不显示）
              if (!_controller.isLocked && !pipMode) _buildGestureIndicator(),

              // 跳过片头/片尾悬浮按钮（右下角，控制栏显示时抬高避让）。
              if (!_controller.isLocked && !pipMode && _showSkipOpButton)
                Positioned(
                  right: AppTokens.spaceLg,
                  bottom: _uiVisible ? 96 : 28,
                  child: _SkipChip(
                      label: l10n.playerSkipOp,
                      icon: Icons.fast_forward_rounded,
                      onTap: _skipIntro),
                ),
              if (!_controller.isLocked && !pipMode && _showSkipEdButton)
                Positioned(
                  right: AppTokens.spaceLg,
                  bottom: _uiVisible ? 96 : 28,
                  child: _SkipChip(
                      label: l10n.playerSkipEd,
                      icon: Icons.fast_forward_rounded,
                      onTap: _skipOutro),
                ),

              // 功能2：缓冲加载动画（播放中缓冲时显示中央转圈）+ 实时网速。
              if (_isBuffering && !_controller.isLocked)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const SizedBox(
                        width: 56,
                        height: 56,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white70),
                        ),
                      ),
                      // 缓冲时显示实时网速（mpv cache-speed，平台不支持则隐藏）。
                      if (_bufferingSpeedText != null)
                        Padding(
                          padding:
                              const EdgeInsets.only(top: AppTokens.spaceSm),
                          child: Text(
                            _bufferingSpeedText!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

              // 功能3：解析进度条（顶部细进度条，类似网站加载条）。
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ValueListenableBuilder<double?>(
                  valueListenable: _resolveProgress,
                  builder: (BuildContext _, double? v, Widget? __) {
                    if (v == null) return const SizedBox.shrink();
                    return LinearProgressIndicator(
                      value: v >= 0 ? v : null,
                      minHeight: 3,
                      backgroundColor: Colors.white24,
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.white),
                    );
                  },
                ),
              ),

              // 左边缘锁定按钮（控制层可见时显示；锁定时仍作为解锁入口）。
              // 纵向与画面正中的播放钮同高（Alignment.center），横向错开不遮挡。
              if (_uiVisible && !pipMode)
                Positioned(
                  left: AppTokens.spaceLg,
                  top: 0,
                  bottom: 0,
                  child: Align(
                    alignment: Alignment.center,
                    child: _ControlButton(
                      key: const Key('player_lock_edge'),
                      icon: _controller.isLocked
                          ? Icons.lock_rounded
                          : Icons.lock_open_rounded,
                      tooltip: _controller.isLocked
                          ? l10n.playerUnlock
                          : l10n.playerLock,
                      onTap: _toggleLock,
                    ),
                  ),
                ),

              // 右边缘截图按钮（控制层可见时显示；锁定态 / PiP 小窗隐藏，避免误触）
              if (_uiVisible && !_controller.isLocked && !pipMode)
                Positioned(
                  right: AppTokens.spaceLg,
                  top: 0,
                  bottom: 0,
                  child: Align(
                    alignment: Alignment.center,
                    child: _ControlButton(
                      key: const Key('player_screenshot_edge'),
                      icon: Icons.camera_alt_rounded,
                      tooltip: l10n.playerScreenshot,
                      onTap: () => unawaited(_captureAndSaveScreenshot(l10n)),
                    ),
                  ),
                ),

              // 控制层（未锁定且不在 PiP 小窗时显示；桌面 PiP 用紧凑控件层）
              if (!_controller.isLocked) ...<Widget>[
                // 顶栏（_buildTopBar 自身已返回 Positioned，无需再包一层，否则嵌套
                // Positioned 触发「Incorrect use of ParentDataWidget」并使视频区塌缩为 0）
                if (_uiVisible && !pipMode) _buildTopBar(l10n),

                // 底栏
                if (_uiVisible && !pipMode) _buildBottomBar(l10n),

                // 中央播放/暂停按钮：由 _isPlaying/_uiVisible 驱动的状态机——
                // 暂停态常显（毛玻璃+呼吸光环），播放/暂停切换有图标形变动画
                // （暂停→播放：暂停符号弹出后淡出；播放→暂停：弹性入场）。
                // 两侧逐帧按钮（暂停时显示）：固定三槽位 Row，中央按钮恒居
                // 中间槽位——不能用条件子树切换，否则其 State 被重建、形变
                // 动画（依赖跨状态保持挂载）会被打断。
                if (!pipMode)
                  Align(
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _FrameStepButton(
                          key: const Key('player_prev_frame'),
                          visible: !_isPlaying && _uiVisible,
                          backward: true,
                          tooltip: l10n.playerPreviousFrame,
                          onTap: () =>
                              unawaited(_controller.frameStep(backward: true)),
                        ),
                        _CenterPlayButton(
                          key: const Key('player_play_pause'),
                          isPlaying: _isPlaying,
                          uiVisible: _uiVisible,
                          onToggle: () {
                            // 用户手动重播则取消进行中的连播倒计时。
                            _cancelAutoNextCountdown();
                            _controller.play();
                            setState(() => _isPlaying = true);
                          },
                        ),
                        _FrameStepButton(
                          key: const Key('player_next_frame'),
                          visible: !_isPlaying && _uiVisible,
                          backward: false,
                          tooltip: l10n.playerNextFrame,
                          onTap: () =>
                              unawaited(_controller.frameStep(backward: false)),
                        ),
                      ],
                    ),
                  ),
              ],

              // 控制栏隐藏时底部保留细进度条（可开关，设置页 player.bottomProgress）。
              // 常驻显示当前播放位置，不拦截点击（IgnorePointer），方便全屏沉浸时看进度。
              if (!_uiVisible &&
                  _playerSettings.showBottomProgress &&
                  _duration > Duration.zero)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: LinearProgressIndicator(
                      value:
                          (_position.inMilliseconds / _duration.inMilliseconds)
                              .clamp(0.0, 1.0),
                      minHeight: 2.5,
                      backgroundColor: Colors.white24,
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 按当前画面比例构建视频表面（修复「比例设置不生效」）。
  ///
  /// 原实现把 Video 固定塞进 16:9 容器，4:3 / fill 只改了 mpv 侧
  /// `video-aspect-override`，容器比例不变导致视觉不生效（fill 时上下黑边
  /// 依旧）。现由比例设置直接驱动容器：
  /// - default：容器铺满（SizedBox.expand），Video 内部 contain 按视频原始比例
  /// 居中显示，无多余黑边；
  /// - 4:3 / 16:9：固定比例容器 + contain，黑边被裁剪到容器外侧；
  /// - fill：容器铺满 + BoxFit.fill 拉伸填满（与 mpv keepaspect=no 双保险）。
  Widget _buildVideoSurface() {
    final String ratio = _controller.currentAspectRatio;
    final Widget video = Video(
      controller: _videoController!,
      controls: NoVideoControls,
      fit: ratio == 'fill' ? BoxFit.fill : BoxFit.contain,
    );
    switch (ratio) {
      case '4:3':
        return Center(child: AspectRatio(aspectRatio: 4 / 3, child: video));
      case '16:9':
        return Center(child: AspectRatio(aspectRatio: 16 / 9, child: video));
      default:
        return SizedBox.expand(child: video);
    }
  }

  Widget _buildTopBar(AppLocalizations l10n) {
    // 顶栏按钮统一紧凑尺寸（默认 IconButton 为 48px 触控区，一排五个太占宽）。
    Widget topBarBtn({
      Key? key,
      required IconData icon,
      Color? color,
      String? tooltip,
      VoidCallback? onPressed,
    }) =>
        IconButton(
          key: key,
          icon: Icon(icon, color: color ?? Colors.white, size: 20),
          tooltip: tooltip,
          onPressed: onPressed,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          padding: const EdgeInsets.all(7),
        );

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Colors.black54, Colors.transparent],
          ),
        ),
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top,
          left: AppTokens.spaceXs,
          right: AppTokens.spaceXs,
        ),
        child: Row(
          children: <Widget>[
            topBarBtn(
              key: const Key('player_back'),
              icon: Icons.arrow_back_rounded,
              onPressed: () => Navigator.of(context).pop(),
            ),
            // 滚动媒体名 + 集数（长标题自动横向滚动）
            Expanded(
              child: _MarqueeText(
                text: _episodeTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // 投屏（鸿蒙经原生 @ohos.net.mdns 发现，见 cast_service.dart）
            topBarBtn(
              key: const Key('player_cast'),
              icon: Icons.cast_rounded,
              color: _isCasting ? Colors.amber : Colors.white,
              tooltip: l10n.playerCast,
              onPressed: () => _showCastSheet(l10n),
            ),
            // 字幕
            topBarBtn(
              key: const Key('player_subtitle'),
              icon: _controller.subtitleVisible
                  ? Icons.subtitles_rounded
                  : Icons.subtitles_rounded,
              tooltip: l10n.playerSubtitle,
              onPressed: () => SubtitlePanel.show(
                context,
                controller: _controller,
                defaults: _playerSettings,
                translator: _subtitleTranslator,
                videoPath: _playUrl,
              ),
            ),
            // 收藏按钮（顶栏收藏，仅 favoriteType 提供时显示）
            if (widget.favoriteType != null)
              topBarBtn(
                key: const Key('player_favorite'),
                icon: _isFav
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: _isFav ? Colors.redAccent : Colors.white,
                tooltip: l10n.favorite,
                onPressed: _onFavoritePressed,
              ),
            // 更多（已瘦身：解码 / 音频 / 媒体信息 / 外部播放 / 定时关闭 / 分享 / PiP / 连播）
            topBarBtn(
              key: const Key('player_more'),
              icon: Icons.more_vert_rounded,
              tooltip: l10n.playerMore,
              onPressed: () => _showMoreMenu(l10n),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(AppLocalizations l10n) {
    final hasPrev = widget.episodes != null && _episodeIndex > 0;
    final hasNext =
        widget.episodes != null && _episodeIndex < widget.episodes!.length - 1;
    final bool showRotate = PlatformService.instance.isMobile;

    // 底栏按钮统一尺寸 40dp（与 _ControlButton / _DanmakuToggle 一致），
    // 用于自然宽度估算与窄屏等比缩放。
    const double btn = 40;
    const TextStyle timeStyle = TextStyle(color: Colors.white, fontSize: 12);
    const TextStyle durationStyle =
        TextStyle(color: Colors.white54, fontSize: 12);

    // 上一集 / 下一集：与横屏一致，仅在有相邻集时显示。
    final Widget? prevButton = hasPrev
        ? _ControlButton(
            key: const Key('player_prev_ep'),
            icon: Icons.skip_previous_rounded,
            tooltip: l10n.playerPreviousEpisode,
            onTap: _goPrevEpisode,
          )
        : null;
    // 播放 / 暂停
    final Widget playButton = _ControlButton(
      key: const Key('player_play_pause_bottom'),
      icon: _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
      tooltip: _isPlaying ? l10n.pause : l10n.play,
      onTap: () {
        // 用户手动重播则取消进行中的连播倒计时。
        _cancelAutoNextCountdown();
        if (_isPlaying) {
          _controller.pause();
        } else {
          _controller.play();
        }
        setState(() => _isPlaying = !_isPlaying);
      },
    );
    // 下一集（不可用时隐藏，同上）
    final Widget? nextButton = hasNext
        ? _ControlButton(
            key: const Key('player_next_ep'),
            icon: Icons.skip_next_rounded,
            tooltip: l10n.playerNextEpisode,
            onTap: _goNextEpisode,
          )
        : null;
    // 弹幕区域（开关 + 发送[开时] + 设置[开时]）
    // 媒体服务器内容无弹幕源，入口隐藏（§2.5）。
    final Widget danmakuArea = _DanmakuToggle(
      key: const Key('player_danmaku_area'),
      isOn: _danmakuOn,
      l10n: l10n,
      onToggle: _toggleDanmaku,
      onSend: _showDanmakuInput,
      onSettings: _openDanmakuSettings,
      onLongPressSettings: _openDanmakuSource,
    );
    // 倍速（弹出选择面板）
    final Widget speedButton = _ControlButton(
      key: const Key('player_quick_speed'),
      icon: Icons.speed_rounded,
      tooltip: '${l10n.playerPlaybackSpeed} ${_controller.playbackSpeed}x',
      onTap: () => _showSpeedPicker(l10n),
    );
    // 比例（循环 default / 4:3 / 16:9 / fill）
    final Widget aspectButton = _ControlButton(
      key: const Key('player_quick_aspect'),
      icon: Icons.aspect_ratio_rounded,
      tooltip: l10n.playerAspectRatio,
      onTap: () {
        const ratios = <String>['default', '4:3', '16:9', 'fill'];
        final cur = _controller.currentAspectRatio;
        final idx = ratios.indexOf(cur);
        final next = ratios[(idx + 1) % ratios.length];
        unawaited(_controller.setAspectRatio(next));
        _playerSettings = _playerSettings.copyWith(
          aspectRatio: PlayerAspectRatio.values.firstWhere(
            (e) => _aspectRatioToMpv(e) == next,
            orElse: () => PlayerAspectRatio.defaultRatio,
          ),
        );
        unawaited(_saveEpisodeSetting(
          'aspectRatio',
          _playerSettings.aspectRatio.name,
        ));
      },
    );

    final List<Widget> utilityButtons = <Widget>[
      speedButton,
      aspectButton,
      // 手动旋转：自动判定失误时的兜底（仅手机端；桌面窗口自由缩放无需旋转）。
      if (showRotate)
        _ControlButton(
          key: const Key('player_rotate'),
          icon: Icons.screen_rotation_rounded,
          tooltip: l10n.playerRotateScreen,
          onTap: () => unawaited(_rotateOrientation()),
        ),
      // 选集：本地合并多集（每文件=一集）也显示；单集 / 无全集列表时隐藏。
      if (widget.episodes != null && widget.episodes!.length > 1)
        _ControlButton(
          key: const Key('player_quick_episodes'),
          icon: Icons.video_library_rounded,
          tooltip: l10n.playerEpisodes,
          onTap: () => _showLineSheet(l10n),
        ),
    ];

    // 与横屏一致的按钮顺序：上一集 播放 下一集 | 弹幕 …… 倍速 比例 旋转 选集；
    // 时间放在进度条两端，控件行只留固定 40dp 的按钮，宽度可精确计算。
    // 窄屏放不下时左右两组按同一系数等比缩小，按钮尺寸始终一致。
    // （无全屏按钮：起播自动进入全屏，桌面可用 F 键手动切换。）
    final int transportCount =
        1 + (prevButton != null ? 1 : 0) + (nextButton != null ? 1 : 0);
    final int danmakuCount = _isMediaServer ? 0 : (_danmakuOn ? 3 : 1);
    final double leftNatural = btn * (transportCount + danmakuCount);
    final double rightNatural = btn * utilityButtons.length;
    final Widget controlsRow = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double gap = AppTokens.spaceSm;
        // 极窄屏时左右两组按同一系数等比收缩，按钮尺寸始终一致。
        final double need = leftNatural + rightNatural + gap;
        final double scale = constraints.maxWidth >= need
            ? 1.0
            : (constraints.maxWidth / need).clamp(0.0, 1.0);
        Widget fit(Widget child, double naturalWidth) {
          if (naturalWidth <= 0) return const SizedBox.shrink();
          if (scale >= 0.999) return child;
          // FittedBox(BoxFit.fill) + 等比目标盒 = 精确统一缩放；
          // 目标盒宽高同比，BoxFit.fill 不会变形。
          return SizedBox(
            width: naturalWidth * scale,
            height: btn * scale,
            child: FittedBox(
              fit: BoxFit.fill,
              child: SizedBox(
                width: naturalWidth,
                height: btn,
                child: child,
              ),
            ),
          );
        }

        return Row(
          children: <Widget>[
            fit(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (prevButton != null) prevButton,
                  playButton,
                  if (nextButton != null) nextButton,
                  if (!_isMediaServer) danmakuArea,
                ],
              ),
              leftNatural,
            ),
            const Spacer(),
            fit(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: utilityButtons,
              ),
              rightNatural,
            ),
          ],
        );
      },
    );

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: <Color>[Colors.black54, Colors.transparent],
          ),
        ),
        padding: EdgeInsets.only(
          left: AppTokens.spaceMd,
          right: AppTokens.spaceMd,
          bottom: MediaQuery.of(context).padding.bottom + 2,
          top: 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 解析二级进度（加载态可见，复用 State 级 _resolveProgress）
            ValueListenableBuilder<double?>(
              valueListenable: _resolveProgress,
              builder: (BuildContext _, double? v, Widget? __) {
                if (v == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppTokens.spaceXs),
                  child: LinearProgressIndicator(
                    value: v >= 0 ? v : null,
                    minHeight: 2,
                    backgroundColor: Colors.white24,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                );
              },
            ),
            // 进度条独占一行，时间分别放在进度条两端。
            Row(
              children: <Widget>[
                Text(
                  _formatDuration(_position),
                  style: timeStyle,
                ),
                const SizedBox(width: AppTokens.spaceSm),
                Expanded(
                  child: SeekBar(
                    position: _position,
                    duration: _duration,
                    onSeek: _onSeek,
                    // 拖动期间持有控制栏，防止自动隐藏打断拖拽。
                    onDragStart: _acquirePanelHold,
                    onDragEnd: _releasePanelHold,
                  ),
                ),
                const SizedBox(width: AppTokens.spaceSm),
                Text(
                  _formatDuration(_duration),
                  style: durationStyle,
                ),
              ],
            ),
            controlsRow,
          ],
        ),
      ),
    );
  }

  String get _episodeTitle {
    final ep = widget.episodes != null && widget.episodes!.isNotEmpty
        ? widget.episodes![_episodeIndex.clamp(0, widget.episodes!.length - 1)]
        : widget.episode;
    return '${widget.title} · ${ep.title}';
  }

  // ─────────────────────── 选集 / 线路面板（FR-3.4） ───────────────────────

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) return '$h:$mm:$ss';
    return '$mm:$ss';
  }

  Future<void> _playInExternal(AppLocalizations l10n) async {
    final url = _playUrl ?? widget.episode.url;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorParse)));
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        messenger
            .showSnackBar(SnackBar(content: Text(l10n.browseNetworkConnect)));
      }
    } on Object {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.errorNetwork)));
      }
    }
  }
}

/// 弹幕开关区域组件：根据开关状态显示不同 UI。
///
/// **开启时**：高亮背景 + 实心图标 + 发送按钮 + 设置按钮
/// **关闭时**：透明背景 + 空心图标（仅开关）
