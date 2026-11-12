import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../models/episode.dart';
import '../platform/platform_service.dart';
import '../settings/player_settings.dart' show UpscaleShaderMode;
import 'anime4k_shaders.dart';
import 'demuxer_cache_policy.dart';
import 'media_kit_backend.dart';
import 'subtitle_memory_store.dart';
import 'video_player_backend.dart';

/// 播放统计快照（mpv 只读属性），供「播放统计」面板与软/硬解诊断使用。
class PlayerStats {
  const PlayerStats({
    this.hwdecCurrent,
    this.videoCodec,
    this.videoFormat,
    this.width,
    this.height,
    this.frameDropCount,
    this.decoderFrameDropCount,
    this.videoBitrate,
    this.cacheBufferingState,
  });

 /// 实际生效的解码器（mpv `hwdec-current`）：
 /// `no`=软解，`mediacodec`/`mediacodec-copy`/`d3d11va` 等=硬解，null=未知。
  final String? hwdecCurrent;

 /// 视频编码描述（mpv `video-codec`）。
  final String? videoCodec;

 /// 像素格式（mpv `video-format`）。
  final String? videoFormat;

 /// 视频宽度（mpv `width`）。
  final int? width;

 /// 视频高度（mpv `height`）。
  final int? height;

 /// 渲染层掉帧数（mpv `frame-drop-count`）。
  final int? frameDropCount;

 /// 解码层掉帧数（mpv `decoder-frame-drop-count`）。
  final int? decoderFrameDropCount;

 /// 视频码率 bps（mpv `video-bitrate`）。
  final int? videoBitrate;

 /// 缓冲进度 0–100（mpv `cache-buffering-state`）。
  final int? cacheBufferingState;

 /// 是否硬件解码中（`hwdec-current` 非空且非 `no`）。
  bool get isHardwareDecoding =>
      hwdecCurrent != null && hwdecCurrent != 'no' && hwdecCurrent!.isNotEmpty;

 /// 是否软件解码中（`hwdec-current` 明确为 `no`）。
  bool get isSoftwareDecoding => hwdecCurrent == 'no';

 /// 是否一项数据都没拿到（平台不支持或尚未开始解码）。
  bool get isEmpty =>
      hwdecCurrent == null &&
      videoCodec == null &&
      videoFormat == null &&
      width == null &&
      height == null;

 /// 从 mpv 属性名→原始字符串的映射构造（解析失败的字段置 null）。
  factory PlayerStats.fromProperties(Map<String, String?> props) {
    int? parseInt(String? raw) =>
        raw == null ? null : int.tryParse(raw.trim());
  // video-bitrate 可能带小数（bps），先按 double 解再取整。
    int? parseNum(String? raw) => raw == null
        ? null
        : double.tryParse(raw.trim())?.round();
    return PlayerStats(
      hwdecCurrent: props['hwdec-current'],
      videoCodec: props['video-codec'],
      videoFormat: props['video-format'],
      width: parseInt(props['width']),
      height: parseInt(props['height']),
      frameDropCount: parseInt(props['frame-drop-count']),
      decoderFrameDropCount: parseInt(props['decoder-frame-drop-count']),
      videoBitrate: parseNum(props['video-bitrate']),
      cacheBufferingState: parseNum(props['cache-buffering-state']),
    );
  }
}

/// 视频播放器控制器。
///
/// 封装 [MediaKitBackend]（持有底层 [Player]），对外暴露播放控制、状态流、
/// 锁定、倍速、解码 / 音频 / 比例切换与自动连播等能力，作为 Provider 层
/// ChangeNotifier 供 UI 绑定。
class PlayerController extends ChangeNotifier {
  PlayerController({Player? player})
      : _backend = MediaKitBackend(player ?? Player()) {
    _initStallDetection();
    _initDecodeFallbackDetection();
  // 登记为「当前活跃实例」，供下一次创建新 Player 前强制释放（见 releaseActive）。
    _activeInstance = this;
  }

  final MediaKitBackend _backend;

 /// 底层 Player 是否已触发过释放（幂等标记，避免 dispose 与 releaseActive
 /// 各触发一次 player.dispose()）。
  bool _released = false;

 /// 自动连播开关。
  bool autoPlayNext = true;

 /// 自动连播回调，由外部（剧集管理器）注入。
  VoidCallback? onAutoPlayNext;

 /// 播放器锁定状态，锁定后禁用手势与控制栏交互。
  bool isLocked = false;

 /// 当前倍速。
  double playbackSpeed = 1.0;

 /// 当前音量（0–100，透传底层 [Player.setVolume]）。
  double volume = 50;

 /// 当前媒体可用的播放线路列表（FR-3.4）。
 /// 解析结果含多线路 URL 时由播放器入口填充；为空表示仅单线路或本地/直链模式。
  List<VideoLine> lines = const <VideoLine>[];

 /// 当前选中的播放线路索引（FR-3.4）。
  int currentLineIndex = 0;

 /// 切换线路时由调用方注入的新线路（已解析）。仅一次 selectLine 生效，
 /// 用于解决"全集 N 条线路切换需各自重新解析"：调用方先 resolve 新 ep.url
 /// 并包装为 [VideoLine] 传入，避免在 PlayerController 内持有源/服务依赖。
  VideoLine? _pendingLine;
  void setPendingLine(VideoLine line) {
    _pendingLine = line;
  }

 // ─────────────────────── 静音 / 全屏 ───────────────────────

 /// 是否静音。
  bool _isMuted = false;
  bool get isMuted => _isMuted;

 /// 静音前的音量（取消静音时恢复），默认 100。
  double _volumeBeforeMute = 100.0;

 /// 是否处于全屏模式（横屏锁定 + 沉浸式）。
  bool _isFullscreen = false;
  bool get isFullscreen => _isFullscreen;

 /// 退出全屏后恢复的方向（由播放页按「锁定方向」设置 / 视频比例注入；
 /// 默认自动跟随）。全屏切换进出都应用此方向（项 3 协调）。
  List<DeviceOrientation> _baseOrientations = const <DeviceOrientation>[];
  void setBaseOrientations(List<DeviceOrientation> o) => _baseOrientations = o;

 /// 切换静音：静音时缓存当前音量；取消静音时恢复。
  Future<void> toggleMute() async {
    if (_isMuted) {
      await _backend.player.setVolume(_volumeBeforeMute);
      _isMuted = false;
    } else {
   // 缓存当前音量（不低于 0），再静音。
      final cur = _backend.player.state.volume;
      if (cur > 0) _volumeBeforeMute = cur;
      await _backend.player.setVolume(0);
      _isMuted = true;
    }
    notifyListeners();
  }

 /// 切换全屏：进入时应用当前有效方向（由播放页按锁定方向 / 视频比例注入，
 /// 不再写死横屏）+ 隐藏系统 UI；退出时还原同一方向 + 恢复系统 UI。
  Future<void> toggleFullscreen() async {
    _isFullscreen = !_isFullscreen;
    try {
      // 方向锁定与系统 UI 模式仅对移动形态有意义；桌面 / 鸿蒙 PC 不产生系统调用。
      if (PlatformService.instance.isMobile) {
        await SystemChrome.setPreferredOrientations(_baseOrientations);
        await SystemChrome.setEnabledSystemUIMode(
          _isFullscreen
              ? SystemUiMode.immersiveSticky
              : SystemUiMode.edgeToEdge,
        );
      }
    } on Object {
   // 测试环境或当前平台不支持，忽略。
    }
    notifyListeners();
  }

 /// Seek 宽限期：seek（或重连后的 seek）后该时长内不触发 stall（卡顿）检测，
 /// 也不视为需要重连。取较大值以覆盖慢速 CDN 的 seek 重新缓冲——m3u8 重新拉取
 /// 分片可能耗时数秒到十几秒，宽限期过短会误判卡顿、触发重连并导致进度清零。
 /// 此常量是 seek 宽限的「唯一标准」，UI 侧 (_onStall) 通过 [isWithinSeekGrace] 复用，
 /// 避免两侧窗口不一致造成「慢速 seek 缓冲」时仍被误判。
 /// 取值偏长（60s）：慢速 CDN 跳到较远进度点后，m3u8 重新拉取该处分片可能耗时十几到几十秒，
 /// 浏览器对同一链接 seek 能正常缓冲即佐证服务端无问题；宽限期过短会在缓冲未完成时误判卡顿
 /// 并触发重连，反而打断缓冲、形成「重连→缓冲→再重连」死循环。
  static const Duration seekGracePeriod = Duration(seconds: 60);

 /// Stall 超时：播放中位置超过该时长未推进则判定为卡顿。
  final Duration _stallTimeout = const Duration(seconds: 10);

 /// 是否仍处于 seek 宽限期内（seek / 重连 seek 后的重新缓冲期间，不应触发重连）。
 /// 供 UI 侧复用以保持与 [_checkStall] 同一判定标准。
  bool get isWithinSeekGrace {
    final now = DateTime.now();
    return now.difference(_lastSeekAt) < seekGracePeriod;
  }

 // ─────────────────────── Stall 检测 ───────────────────────
  StreamSubscription<Duration>? _stallPositionSub;
  StreamSubscription<bool>? _stallPlayingSub;
  Timer? _stallCheckTimer;
  Duration _lastStallPosition = Duration.zero;
  DateTime _lastPositionAdvancedAt = DateTime.now();
  DateTime _lastSeekAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isPlayingForStall = false;
  final StreamController<void> _stallController =
      StreamController<void>.broadcast();

 /// Stall（卡顿）事件流：播放中位置超时未推进（超过 [_stallTimeout]）
 /// 且已过 seek 宽限期（[seekGracePeriod]）时触发一次，UI 可据此提示
 /// 并自动重连。
  Stream<void> get stallStream => _stallController.stream;

  void _initStallDetection() {
    _stallPositionSub = _backend.player.stream.position.listen((pos) {
      if (pos != _lastStallPosition) {
        _lastStallPosition = pos;
        _lastPositionAdvancedAt = DateTime.now();
      }
    });
    _stallPlayingSub = _backend.player.stream.playing.listen((playing) {
      _isPlayingForStall = playing;
      if (playing) {
        _lastPositionAdvancedAt = DateTime.now();
      }
    });
    _stallCheckTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _checkStall(),
    );
  }

  void _checkStall() {
    if (!_isPlayingForStall || _stallController.isClosed) return;
    final now = DateTime.now();
  // seek 宽限期内不检测（覆盖慢速 CDN 的重新缓冲）
    if (now.difference(_lastSeekAt) < seekGracePeriod) return;
  // 位置未推进超过 stallTimeout → 触发 stall
    if (now.difference(_lastPositionAdvancedAt) >= _stallTimeout) {
      _stallController.add(null);
   // 重置基准，避免连续重复触发；待位置再次推进后重新计时
      _lastPositionAdvancedAt = now;
    }
  }

 // ────────── 解码异常自动降级（花屏 / 硬解初始化失败自愈） ──────────

  StreamSubscription<PlayerLog>? _decodeLogSub;
  final StreamController<String> _decodeFallbackController =
      StreamController<String>.broadcast();

 /// 解码自动降级事件流：发生降级时推送新的应用层解码模式（'hw+' / 'sw'）。
 /// UI 据此提示用户并 re-open 当前地址使新 hwdec 对已在播的解码器生效。
  Stream<String> get decodeFallbackStream => _decodeFallbackController.stream;

 /// 本会话内是否已发生过自动降级（auto → hw+ 后置位，允许继续降到 sw；
 /// 用户手动切换解码模式时重置，手动选择不参与自动降级链）。
  bool _autoDowngraded = false;

 /// 上次自动降级时刻；冷却期内忽略后续触发，避免同一批错误日志连续降两级。
  DateTime _lastDecodeFallbackAt = DateTime.fromMillisecondsSinceEpoch(0);

 /// 降级冷却期：re-open 后旧解码器的残留错误日志不应立即再触发下一级。
  static const Duration decodeFallbackCooldown = Duration(seconds: 30);

  void _initDecodeFallbackDetection() {
    try {
      _decodeLogSub = _backend.player.stream.log.listen((PlayerLog log) {
        if (isHwdecFailureLog(log.level, log.text)) {
          unawaited(_maybeAutoDowngrade());
        }
      });
    } catch (_) {
   // 当前平台无 mpv 日志流（如 Web），自动降级不可用，忽略。
    }
  }

 /// 判定一条 mpv 日志是否属于硬解失败 / 解码异常（自动降级触发条件）。
 ///
 /// 纯函数，便于单测覆盖（构造 PlayerController 需要原生 libmpv）。
  @visibleForTesting
  static bool isHwdecFailureLog(String level, String text) {
    final t = text.toLowerCase();
    if (t.contains('could not initialize hardware decoding')) return true;
    if (t.contains('failed to initialize decoder')) return true;
    final lv = level.toLowerCase();
    if ((lv == 'error' || lv == 'fatal') && t.contains('hwdec')) return true;
    return false;
  }

 /// 自动降级链：auto → hw+（auto-copy，绕开 mediacodec 直通纹理，修花屏首选）
 /// → sw（纯软解兜底）。仅对默认 auto 模式自动降级；用户手动选定的
 /// hw / hw+ / sw 是明确意图，不自动改动。返回 null 表示不降级。
  @visibleForTesting
  static String? nextFallbackHwdec(String current, {required bool autoDowngraded}) {
    switch (current) {
      case 'auto':
        return 'hw+';
      case 'hw+':
    // 仅当 hw+ 是上一步自动降级的结果时才继续降到 sw。
        return autoDowngraded ? 'sw' : null;
      default:
        return null;
    }
  }

  Future<void> _maybeAutoDowngrade() async {
    final now = DateTime.now();
    if (now.difference(_lastDecodeFallbackAt) < decodeFallbackCooldown) return;
    final next =
        nextFallbackHwdec(currentHwdec, autoDowngraded: _autoDowngraded);
    if (next == null) return;
    _lastDecodeFallbackAt = now;
    _autoDowngraded = true;
  // 直接走后端，不走公开 setHwdec（那会被视作手动切换而重置降级链）。
    await _backend.setHwdec(next);
    if (!_decodeFallbackController.isClosed) {
      _decodeFallbackController.add(next);
    }
    notifyListeners();
  }

 // ────────── 播放统计（软/硬解诊断） ──────────

 /// 「播放统计」面板读取的 mpv 只读属性清单。
  static const List<String> statsProperties = <String>[
    'hwdec-current',
    'video-codec',
    'video-format',
    'width',
    'height',
    'frame-drop-count',
    'decoder-frame-drop-count',
    'video-bitrate',
    'cache-buffering-state',
  ];

 /// 查询当前播放统计快照（实际软/硬解状态、编码、分辨率、掉帧等）。
 ///
 /// 平台不支持或尚未开始解码时各字段为 null（[PlayerStats.isEmpty]）。
  Future<PlayerStats> queryStats() async {
    final props = <String, String?>{};
    for (final name in statsProperties) {
      props[name] = await _backend.getProperty(name);
    }
    return PlayerStats.fromProperties(props);
  }

 /// 暴露底层后端（供 Video 控件获取 [Player]）。
  VideoPlayerBackend get backend => _backend;

 /// 暴露底层 [Player] 实例。
  Player get player => _backend.player;

 // ─────────────────────── 播放控制 ───────────────────────

 /// 打开媒体地址。
 ///
 /// [headers] 透传给 mpv 的 HTTP 请求头（反盗链 Referer / UA 等），
 /// 必须与抓取 m3u8 文本时一致，否则 CDN 返回 403、解不出帧。
  Future<void> open(String url, {Map<String, String>? headers}) async {
  // 本地裸文件绝对路径（非 http / 非 file:// / 非 content://）补 `file://`
  /// 前缀：media_kit 底层 mpv 在某些 Android 构建下会把裸绝对路径当相对路径
  /// 或未知协议处理，导致 `player.open` 既不报错也不完成（UI 无限转圈）。
  /// 网络地址 / 已带 scheme 的地址保持原样。
    final openUrl = _normalizeOpenUrl(url);
  // HLS 地址强制 `demuxer-lavf-format=hls`，跳过内容探测；
  // 须在 open 前设置（demuxer 打开时读取）。
    try {
      await _backend.prepareDemuxerForUrl(openUrl);
    } on Object {
   // 后端不支持（NoOp / Web 降级），忽略。
    }
    await _backend.player.open(Media(openUrl, httpHeaders: headers));
  // 记录当前媒体 URL，异步恢复字幕记忆（不阻塞打开，失败静默）。
    _subtitleMediaUrl = url;
    unawaited(_restoreSubtitles());
  }

 /// 把本地裸路径归一化为 `file://` URI，便于 media_kit/mpv 稳定打开。
  static String _normalizeOpenUrl(String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  if (url.startsWith('file://')) return url;
  if (url.startsWith('content://')) {
   // 到这一步还拿到 content:// 说明上层 SAF 解析漏了（书架/下载直传），
   // 绝不能把它交给 media_kit——mpv 读不了 content:// 会"瞬间打开成功"
   // 但实际什么都没加载（UI 无限转圈且无任何错误）。直接抛明确错误。
      throw ArgumentError(
    'content:// 不能直接交给 media_kit：请先经 SAF 解析为真实文件',
      );
    }
  return 'file://$url';
  }

 /// 继续播放。
  Future<void> play() async {
    await _backend.player.play();
  }

 /// 暂停播放。
  Future<void> pause() async {
    await _backend.player.pause();
  }

 /// 跳转到指定位置。
  Future<void> seek(Duration position) async {
    _lastSeekAt = DateTime.now();
    await _backend.player.seek(position);
  }

 /// 逐帧步进：前进（默认）或后退一帧。
 ///
 /// mpv 内核走原生 `frame-step` / `frame-back-step` 命令——自带「先暂停
 /// 再步进」语义，且按容器真实帧率精确走帧；playing 状态经既有流同步回 UI。
 /// 非 mpv 内核（Web 等）或命令执行失败时，回退为按 1/24 秒的近似帧长 seek。
  Future<void> frameStep({bool backward = false}) async {
    final PlatformPlayer? platform = _backend.player.platform;
    if (platform is NativePlayer) {
      try {
        await platform
            .command(<String>[backward ? 'frame-back-step' : 'frame-step']);
        return;
      } on Object {
      // 命令失败（如无视频轨）落回下方近似 seek，不向上抛。
      }
    }
    final Duration step = Duration(milliseconds: 1000 ~/ 24);
    final Duration position = _backend.player.state.position;
    final Duration target = backward ? position - step : position + step;
    final Duration clamped = target < Duration.zero
        ? Duration.zero
        : (target > _backend.player.state.duration
            ? _backend.player.state.duration
            : target);
    await seek(clamped);
  }


 /// 设置音量（0–100，自动 clamp），透传底层 [Player.setVolume]。
  Future<void> setVolume(double v) async {
    final clamped = v.clamp(0.0, 100.0);
    volume = clamped;
    await _backend.player.setVolume(clamped);
    notifyListeners();
  }

 // ─────────────────────── 播放线路（FR-3.4） ───────────────────────

 /// 切换到指定播放线路。
 ///
 /// 更新 [currentLineIndex] 并通过 [_openCurrentLine] 重新打开对应 URL；
 /// 越界索引静默忽略。本地 / 直链模式 [lines] 为空，调用方不应触发。
 ///
 /// 切换前可调用 [setPendingLine] 注入已解析的新线路（用于跨线路重新解析
 /// 场景，如详情页 chips 切换多 lineName），[_openCurrentLine] 会优先使用
 /// 注入的线路而忽略该索引处的旧值。
 ///
 /// 切换成功后按切换前的播放位置恢复，避免换线后从头播放。
  Future<void> selectLine(int index) async {
    if (index < 0 || index >= lines.length) return;
  // 记录切换前的播放位置（open() 会重置播放器状态）。
    final Duration resumeAt = _backend.player.state.position;
    currentLineIndex = index;
    notifyListeners();
    await _openCurrentLine();
    if (resumeAt > Duration.zero) {
      await _restorePositionAfterOpen(resumeAt);
    }
  }

 /// 重新打开媒体后恢复到 [target]。
 ///
 /// open() 返回时底层往往尚未完成 demux（duration 仍为 0），立即 seek 会被
 /// mpv 静默丢弃；先等 duration 就绪（最多 8 秒）再 seek，并延迟校验实际
 /// 落点，偏差超过 3 秒补发一次。seek 经 [seek] 入口更新重连宽限期，避免
 /// 换线后的重新缓冲被 stall 检测误判为卡顿。
  Future<void> _restorePositionAfterOpen(Duration target) async {
    if (_backend.player.state.duration <= Duration.zero) {
      try {
        await _backend.player.stream.duration
            .firstWhere((Duration d) => d > Duration.zero)
            .timeout(openReadyTimeout);
      } on Object {
    // 超时或流异常：仍尝试 seek 一次，失败也不影响播放。
      }
    }
    await seek(target);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final Duration cur = _backend.player.state.position;
    if ((cur - target).abs() > const Duration(seconds: 3)) {
      await seek(target);
    }
  }

 /// 重新打开当前选中线路的 URL（复用现有 `_player.open(Media(url))` 入口）。
 ///
 /// 若已通过 [setPendingLine] 注入新线路，则用注入的 line 替换 [lines]
 /// 中当前索引的项并清除注入标记（仅一次生效），用于"切换线路前已重新解析
 /// 完成"的场景；否则按 [lines] 中现有 URL 打开（兜底，常见于初次解析已
 /// 通过 [VideoResult.lines] 提供全部线路的情况）。
  Future<void> _openCurrentLine() async {
    if (lines.isEmpty) return;
    final pending = _pendingLine;
    if (pending != null) {
      _pendingLine = null;
      lines[currentLineIndex] = pending;
    }
    final line = lines[currentLineIndex];
    if (line.url.isEmpty) return;
    final openUrl = _normalizeOpenUrl(line.url);
    await _backend.player.open(Media(openUrl, httpHeaders: line.headers));
  }

 // ─────────────────────── 状态流 ───────────────────────

 /// 播放位置流。
  Stream<Duration> get positionStream => _backend.player.stream.position;

 /// 媒体时长流。
  Stream<Duration> get durationStream => _backend.player.stream.duration;

 /// 播放状态流。
  Stream<bool> get playingStream => _backend.player.stream.playing;

 /// 播放完成流。
  Stream<bool> get completedStream => _backend.player.stream.completed;

 /// 缓冲状态流（true=正在缓冲/加载中）。用于 UI 显示加载动画。
  Stream<bool> get bufferingStream => _backend.player.stream.buffering;

 // ─────────────────────── 瞬时状态 ───────────────────────

 /// 当前播放位置。
  Duration get position => _backend.player.state.position;

 /// 媒体总时长。
  Duration get duration => _backend.player.state.duration;

 /// 是否正在播放。
  bool get isPlaying => _backend.player.state.playing;

 /// 是否播放完成。
  bool get isCompleted => _backend.player.state.completed;

 /// 是否正在缓冲（加载中）。
  bool get isBuffering => _backend.player.state.buffering;

 // ─────────────────────── 锁定 ───────────────────────

 /// 切换播放器锁定状态。
  void toggleLock() {
    isLocked = !isLocked;
    notifyListeners();
  }

 // ─────────────────────── 倍速 ───────────────────────

 /// 设置播放倍速。
  Future<void> setPlaybackSpeed(double speed) async {
    playbackSpeed = speed;
    await _backend.player.setRate(speed);
    notifyListeners();
  }

 // ─────────────────────── 字幕 ───────────────────────

 /// 可用字幕轨道列表（实时快照，来自底层 [Player.state.tracks]）。
  List<SubtitleTrack> get subtitleTracks =>
      _backend.player.state.tracks.subtitle;

 /// 用户选中的字幕轨道（偏好，关闭显示时仍保留以便恢复）。
  SubtitleTrack? _currentSubtitleTrack;
  SubtitleTrack? get currentSubtitleTrack => _currentSubtitleTrack;

 /// 字幕偏移（限制在 ±5s）。
  Duration _subtitleDelay = Duration.zero;
  Duration get subtitleDelay => _subtitleDelay;

 /// 字幕显示开关。
  bool _subtitleVisible = false;
  bool get subtitleVisible => _subtitleVisible;

 /// 可用轨道变更流（含音频 / 视频 / 字幕）。
  Stream<Tracks> get tracksStream => _backend.player.stream.tracks;

 /// 当前选中轨道变更流。
  Stream<Track> get trackStream => _backend.player.stream.track;

 /// 设置字幕轨道。传 null 关闭字幕并清除偏好。
 ///
 /// 外部字幕（[SubtitleTrack.uri]）会被记入 [_externalSubtitleUris]，
 /// 供 字幕记忆按视频持久化与恢复。
  Future<void> setSubtitleTrack(SubtitleTrack? track) async {
    if (track == null) {
      await _backend.player.setSubtitleTrack(SubtitleTrack.no());
      _currentSubtitleTrack = null;
      _subtitleVisible = false;
    } else {
      await _backend.player.setSubtitleTrack(track);
      _currentSubtitleTrack = track;
      _subtitleVisible = true;
   // 外部字幕：track.uri 为布尔「是否来自 URI」标志，路径存在 track.id。
      if (track.uri) {
        final String path = track.id;
        if (!_externalSubtitleUris.contains(path)) {
          _externalSubtitleUris = List<String>.from(_externalSubtitleUris)
            ..add(path);
        }
      }
    }
    notifyListeners();
  }

 /// 设置字幕偏移，自动限制在 -5s~+5s（通过 mpv `sub-delay` 属性生效）。
  Future<void> setSubtitleDelay(Duration delay) async {
    final ms = delay.inMilliseconds.clamp(-5000, 5000);
    _subtitleDelay = Duration(milliseconds: ms);
    try {
      final platform = _backend.player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty(
          'sub-delay',
          (ms / 1000.0).toStringAsFixed(3),
        );
      }
    } catch (_) {
   // 当前平台不支持 mpv 属性设置（如 Web），忽略。
    }
    notifyListeners();
  }

  // ─────────────────────── 音轨 ───────────────────────

  /// 可用音轨列表（实时快照，来自底层 [Player.state.tracks]）。
  List<AudioTrack> get audioTracks => _backend.player.state.tracks.audio;

  /// 当前选中的音轨。
  AudioTrack? _currentAudioTrack;
  AudioTrack? get currentAudioTrack => _currentAudioTrack;

  /// 切换音轨（直连 / DirectStream 下由 mpv 内部切换，即时生效）。
  Future<void> setAudioTrack(AudioTrack track) async {
    await _backend.player.setAudioTrack(track);
    _currentAudioTrack = track;
    notifyListeners();
  }

 /// 切换字幕显示开关。关闭时记住当前轨道，开启时恢复。
  Future<void> setSubtitleVisible(bool visible) async {
    if (visible == _subtitleVisible) return;
    if (visible) {
      final track = _currentSubtitleTrack;
      if (track != null) {
        await _backend.player.setSubtitleTrack(track);
      }
      _subtitleVisible = true;
    } else {
      await _backend.player.setSubtitleTrack(SubtitleTrack.no());
      _subtitleVisible = false;
    }
    notifyListeners();
  }

 // ─────────────────────── 字幕样式（mpv sub-* 属性） ───────────────────────

 /// 设置字幕属性（透传 mpv sub-* 键值对）。
 ///
 /// 平台不支持时（如 Web）静默忽略。
  Future<void> _setSubProperty(String name, String value) async {
    try {
      final platform = _backend.player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty(name, value);
      }
    } catch (_) {
   // 当前平台不支持 mpv 属性设置，忽略。
    }
  }

 /// 字幕字体名称（如 "Sans", "Serif"）。
  Future<void> setSubtitleFont(String font) async {
    await _setSubProperty('sub-font', font);
    notifyListeners();
  }

 /// 字号（像素值，如 "28", "36"）。
  Future<void> setSubtitleFontSize(double size) async {
    await _setSubProperty('sub-font-size', size.toStringAsFixed(1));
    notifyListeners();
  }

 /// 字幕颜色（BGR 十六进制，如 "FFFFFF"=白, "00FFFF"=黄）。
  Future<void> setSubtitleColor(String color) async {
    await _setSubProperty('sub-color', color);
    notifyListeners();
  }

 /// 字幕边框颜色（BGR 十六进制）。
  Future<void> setSubtitleBorderColor(String color) async {
    await _setSubProperty('sub-border-color', color);
    notifyListeners();
  }

 /// 字幕边框宽度（像素值）。
  Future<void> setSubtitleBorderSize(double size) async {
    await _setSubProperty('sub-border-size', size.toStringAsFixed(1));
    notifyListeners();
  }

 /// 字幕阴影颜色（BGR 十六进制）。
  Future<void> setSubtitleShadowColor(String color) async {
    await _setSubProperty('sub-shadow-color', color);
    notifyListeners();
  }

 /// 字幕阴影偏移（像素值）。
  Future<void> setSubtitleShadowOffset(double offset) async {
    await _setSubProperty('sub-shadow-offset', offset.toStringAsFixed(1));
    notifyListeners();
  }

 /// 字幕缩放比例（如 "1.5" 放大 50%）。
  Future<void> setSubtitleScale(double scale) async {
    await _setSubProperty('sub-scale', scale.toStringAsFixed(2));
    notifyListeners();
  }

 /// 字幕垂直位置（"top", "center", "bottom" 或 0-100 百分比）。
  Future<void> setSubtitlePosition(String pos) async {
    await _setSubProperty('sub-pos', pos);
    notifyListeners();
  }

 /// 是否覆盖 ASS/SSA 样式（"yes"/"no"/"strip"/"force"）。
  Future<void> setSubtitleAssOverride(String mode) async {
    await _setSubProperty('sub-ass-override', mode);
    notifyListeners();
  }

 // ─────────────────────── 字幕记忆 ───────────────────────

 /// 当前媒体 URL（字幕记忆 key），在 [open] 时写入。
  String? _subtitleMediaUrl;

 /// 已加载的外部字幕 URI 列表（持久化，切集互不干扰）。
  List<String> _externalSubtitleUris = const <String>[];

 /// 字幕样式字段（运行时镜像面板状态，供记忆落盘与面板初始化读取）。
 /// 默认值与字幕面板的有效回落值保持一致（字幕面板字号回落 28.0）。
  double _subFontSize = 28.0;
  double _subScale = 1.0;
  double _subBorderSize = 1.5;
  double _subShadowOffset = 2.0;
  String _subColor = 'FFFFFF';
  String _subBorderColor = '000000';
  String _subShadowColor = '000000';
  String _subPosition = 'bottom';
  String _subAssMode = 'yes';

  final SubtitleMemoryStore _subtitleMemoryStore = SubtitleMemoryStore();

 /// 内置激活轨道恢复订阅（轨道列表异步就绪后匹配一次）。
  StreamSubscription<Tracks>? _activeTrackRestoreSub;
  Timer? _activeTrackRestoreTimer;

 // —— 样式读取（供字幕面板初始化，反映已恢复的记忆）——
  double get subFontSize => _subFontSize;
  double get subScale => _subScale;
  double get subBorderSize => _subBorderSize;
  double get subShadowOffset => _subShadowOffset;
  String get subColor => _subColor;
  String get subBorderColor => _subBorderColor;
  String get subShadowColor => _subShadowColor;
  String get subPosition => _subPosition;
  String get subAssMode => _subAssMode;

 /// 打开视频后恢复字幕记忆。
 ///
 /// 读取按 URL 记忆的字幕状态并应用；无记忆时尝试本地同名字幕自动加载。
 /// 任何步骤失败均静默忽略，绝不阻断播放。
  Future<void> _restoreSubtitles() async {
    final url = _subtitleMediaUrl;
    if (url == null || url.isEmpty) return;
    final SubtitleMemory? mem = await _subtitleMemoryStore.load(url);
    if (mem == null) {
   // 无记忆：字段保持默认，并尝试同名字幕自动加载。
      await _tryAutoLoadSameNameSubtitle(url);
      return;
    }

  // 样式字段 + 应用到 mpv
    _subFontSize = mem.fontSize;
    _subScale = mem.scale;
    _subBorderSize = mem.borderSize;
    _subShadowOffset = mem.shadowOffset;
    _subColor = mem.color;
    _subBorderColor = mem.borderColor;
    _subShadowColor = mem.shadowColor;
    _subPosition = mem.position;
    _subAssMode = mem.assMode;
    _applySubtitleStyleToMpv();

  // 偏移（限制在 ±5s）
    _subtitleDelay = Duration(
      milliseconds: mem.delayMs.clamp(-5000, 5000).toInt(),
    );

  // 外部字幕：逐个加载（setSubtitleTrack 会记入列表并设当前轨道）
    _externalSubtitleUris = const <String>[];
    for (final String uri in mem.externalSubtitleUris) {
      await setSubtitleTrack(SubtitleTrack.uri(uri));
    }

  // 激活轨道（仅当记忆为「可见」时才真正选入 mpv）
    final String? activeId = mem.activeTrackId;
    if (mem.visible) {
      if (activeId != null && _externalSubtitleUris.contains(activeId)) {
        await setSubtitleTrack(SubtitleTrack.uri(activeId));
      } else if (activeId != null) {
    // 内置轨道：轨道列表异步就绪后匹配一次
        _restoreBuiltinTrack(activeId);
      }
   // 其余情况：外部字幕已在上面的循环中被选为当前（最后一条），保持即可
    } else {
   // 不可见：关闭 mpv 字幕输出，但保留 _currentSubtitleTrack 以便面板开关重新启用
      await _backend.player.setSubtitleTrack(SubtitleTrack.no());
    }

  // 最终以记忆的可见性为准（外部字幕循环内会被置 true，此处纠正回 mem.visible）
    _subtitleVisible = mem.visible;

    notifyListeners();
  }

 /// 把当前样式字段推到 mpv（sub-* 属性）。平台不支持时静默忽略。
  void _applySubtitleStyleToMpv() {
    unawaited(_setSubProperty('sub-font-size', _subFontSize.toStringAsFixed(1)));
    unawaited(_setSubProperty('sub-scale', _subScale.toStringAsFixed(2)));
    unawaited(
      _setSubProperty('sub-border-size', _subBorderSize.toStringAsFixed(1)),
    );
    unawaited(
      _setSubProperty('sub-shadow-offset', _subShadowOffset.toStringAsFixed(1)),
    );
    unawaited(_setSubProperty('sub-color', _subColor));
    unawaited(_setSubProperty('sub-border-color', _subBorderColor));
    unawaited(_setSubProperty('sub-shadow-color', _subShadowColor));
    unawaited(_setSubProperty('sub-pos', _subPosition));
    unawaited(_setSubProperty('sub-ass-override', _subAssMode));
  }

 /// 内置激活轨道恢复：订阅轨道列表，匹配到 [id] 即选中并取消订阅；
 /// 6 秒仍未就绪则放弃，避免订阅泄漏。
  void _restoreBuiltinTrack(String id) {
    _activeTrackRestoreSub?.cancel();
    _activeTrackRestoreTimer?.cancel();
    _activeTrackRestoreSub = _backend.player.stream.tracks.listen((Tracks tracks) {
      for (final SubtitleTrack t in tracks.subtitle) {
        if (t.id == id) {
          unawaited(setSubtitleTrack(t));
          _activeTrackRestoreSub?.cancel();
          _activeTrackRestoreSub = null;
          _activeTrackRestoreTimer?.cancel();
          _activeTrackRestoreTimer = null;
          break;
        }
      }
    });
    _activeTrackRestoreTimer = Timer(const Duration(seconds: 6), () {
      _activeTrackRestoreSub?.cancel();
      _activeTrackRestoreSub = null;
      _activeTrackRestoreTimer = null;
    });
  }

 /// 本地视频：在同目录查找同名 .srt/.vtt/.ass/.ssa 并自动加载。
 ///
 /// 分区存储（scoped storage）下目录列举可能失败或返回空，全部静默忽略。
  Future<void> _tryAutoLoadSameNameSubtitle(String url) async {
    String? path;
  if (url.startsWith('file://')) {
   path = url.substring('file://'.length);
  } else if (!url.startsWith('http://') &&
    !url.startsWith('https://') &&
    !url.startsWith('content://')) {
      path = url;
    }
    if (path == null || path.isEmpty) return;
    try {
      final File file = File(path);
      final Directory dir = file.parent;
      final String base = file.uri.pathSegments.isEmpty
          ? path
          : file.uri.pathSegments.last;
      final int dot = base.lastIndexOf('.');
      if (dot <= 0) return;
      final String name = base.substring(0, dot);
      const List<String> exts = <String>['srt', 'vtt', 'ass', 'ssa'];
      for (final String ext in exts) {
        final File candidate = File('${dir.path}/$name.$ext');
        if (await candidate.exists()) {
          await setSubtitleTrack(SubtitleTrack.uri(candidate.path));
          await saveSubtitleState();
          return;
        }
      }
    } on Object {
   // 分区存储 / 权限问题静默忽略。
    }
  }

 /// 持久化当前字幕状态到字幕记忆。字幕面板每次变更后调用。
  Future<void> saveSubtitleState() async {
    final String? url = _subtitleMediaUrl;
    if (url == null || url.isEmpty) return;
    final SubtitleMemory mem = SubtitleMemory(
      externalSubtitleUris: _externalSubtitleUris,
      activeTrackId: _currentSubtitleTrack?.id,
      visible: _subtitleVisible,
      delayMs: _subtitleDelay.inMilliseconds,
      fontSize: _subFontSize,
      scale: _subScale,
      borderSize: _subBorderSize,
      shadowOffset: _subShadowOffset,
      color: _subColor,
      borderColor: _subBorderColor,
      shadowColor: _subShadowColor,
      position: _subPosition,
      assMode: _subAssMode,
    );
    await _subtitleMemoryStore.save(url, mem);
  }

 // ─────────────────────── 后端能力委托 ───────────────────────

 /// 设置硬件解码模式（委托后端）。手动切换会重置自动降级链：
 /// 用户重新选 auto 后若再次检测到解码异常，降级链从头开始。
  Future<void> setHwdec(String mode) async {
    _autoDowngraded = false;
    await _backend.setHwdec(mode);
    notifyListeners();
  }

 /// 设置音频通道（委托后端）。
  Future<void> setAudioChannel(String channel) async {
    await _backend.setAudioChannel(channel);
    notifyListeners();
  }

 /// 设置画面比例（委托后端）。
  Future<void> setAspectRatio(String ratio) async {
    await _backend.setAspectRatio(ratio);
    notifyListeners();
  }

 // ────────── 超分辨率 shader ──────────

  UpscaleShaderMode _upscaleShader = UpscaleShaderMode.off;

 /// 当前超分辨率档位。
  UpscaleShaderMode get upscaleShader => _upscaleShader;

 /// 设置超分辨率 shader 档位。
 ///
 /// 部署预设文件到应用目录后经 mpv `glsl-shaders` 注入，运行时即时生效、
 /// 无需重开；off 或部署失败（如 Web 无文件系统）传空串清空。
  Future<void> setUpscaleShader(UpscaleShaderMode mode) async {
    _upscaleShader = mode;
    try {
      await _backend.setUpscaleShaders(
        await Anime4kShaderCatalog.mpvShaderList(mode),
      );
    } on Object {
   // 后端不支持（NoOp 降级）或属性设置失败，忽略。
    }
    notifyListeners();
  }

 // ────────── demuxer 缓存降级 ──────────

 /// 应用 demuxer 缓存档位（移动网络 / 低内存降级）。
 ///
 /// 后端不支持（NoOp / Web 降级）时静默忽略。运行时可反复调用，
 /// 网络切换时由播放器侧重新 resolve 后再次应用。
  Future<void> applyDemuxerCacheProfile(DemuxerCacheProfile profile) async {
    try {
      await _backend.setDemuxerCacheBudget(
        profile.maxBytes,
        profile.maxBackBytes,
        profile.cacheSecs,
        profile.hysteresisSecs,
      );
    } on Object {
   // 后端不支持（NoOp 降级），忽略。
    }
  }

 // ────────── 分级就绪超时 ──────────

 /// open 后元数据就绪等待超时（[_restorePositionAfterOpen] 使用）。
 ///
 /// 播放器侧按来源分级设置：源解析的媒体服务器 30s、直链网络 6s、
 /// 本地文件 5s；默认 8s 与历史行为一致。
  Duration openReadyTimeout = const Duration(seconds: 8);

 /// 当前解码模式。
  String get currentHwdec => _backend.currentHwdec;

 /// 当前音频通道。
  String get currentAudioChannel => _backend.currentAudioChannel;

 /// 当前画面比例。
  String get currentAspectRatio => _backend.currentAspectRatio;

 /// 当前仍活跃的播放器实例（构造时登记，dispose / 被 [releaseActive] 释放时清空）。
  static PlayerController? _activeInstance;

 /// 串行化用：上一次 [Player.dispose()] 的 Future。播放器页面创建新 [VideoController]
 /// 前会等待它，确保旧原生 VideoOutput（media_kit 纹理）释放完成，避免退出重进时
 /// 新旧 surface 冲突（Lost connection to device）。
  static Future<void>? _pendingDisposal;

 /// 供播放器页面 await：若上一次播放器仍在异步释放，则等待其完成；否则立即返回。
  static Future<void> get pendingDisposal =>
      _pendingDisposal ?? Future<void>.value();

 /// 释放仍活跃的旧播放器并等待其底层 [Player] 完全销毁后返回。
 ///
 /// 退出播放器时旧页面进入退场动画，其 `dispose()`（触发 [_pendingDisposal]）
 /// 要等动画结束才执行；若此时用户快速重进，新页面创建 [Player] 会与尚未销毁
 /// 的旧 mpv 实例并发，引发原生 surface 冲突（Lost connection to device）。
 /// 因此在创建新 [Player] 前调用本方法：无论旧页 dispose 是否已执行，都强制
 /// 释放活跃旧实例并等待其销毁完成，再返回。
  static Future<void> releaseActive() async {
    final active = _activeInstance;
    if (active != null && !active._released) {
      active._released = true;
      _activeInstance = null;
      final disposeFuture = active._backend.player.dispose();
      _pendingDisposal = disposeFuture;
      await disposeFuture;
    }
    final pending = _pendingDisposal;
    if (pending != null) {
      await pending;
    }
  }

  @override
  void dispose() {
    _stallCheckTimer?.cancel();
    _stallPositionSub?.cancel();
    _stallPlayingSub?.cancel();
    _stallController.close();
    _decodeLogSub?.cancel();
    _decodeFallbackController.close();
  // 取消字幕记忆恢复订阅。
    _activeTrackRestoreSub?.cancel();
    _activeTrackRestoreTimer?.cancel();
  // 退出时始终还原方向与系统 UI。
  // 无论是否经过全屏切换，进入播放页时 _applyLockOrientation 可能已锁定方向
  // （横屏 / 竖屏 / 跟随视频），必须在此无条件解除。
  // 桌面 / 鸿蒙 PC 从未改动方向与系统 UI，无需复位。
    if (PlatformService.instance.isMobile) {
      try {
        SystemChrome.setPreferredOrientations(<DeviceOrientation>[]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      } on Object {
     // 测试环境忽略。
      }
    }
    super.dispose();
    if (identical(_activeInstance, this)) _activeInstance = null;
    if (!_released) {
      _released = true;
   // 触发底层 Player.dispose()（含原生 VideoOutput 释放）并记下其 Future，
   // 供下一次进入播放器时 await，避免新旧 surface 冲突。
      _pendingDisposal = _backend.player.dispose();
    }
  }
}
