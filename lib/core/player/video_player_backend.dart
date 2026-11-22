import 'player_capability.dart';

/// 视频播放后端抽象。
///
/// 定义硬件解码、音频通道与画面比例等后端可调能力的统一接口，
/// 具体实现由 [MediaKitBackend]（基于 media_kit / mpv）提供。
///
/// 扩展：[capabilities] 集供调用方探测后端能力，避免运行时
/// UnsupportedError；[NoOpPlayerBackend] 作为降级占位。
abstract class VideoPlayerBackend {
  /// 后端支持的能力集合。
  Set<PlayerCapability> get capabilities => const <PlayerCapability>{};

  /// 设置硬件解码模式：auto/sw/hw/hw+。
  ///
  /// 默认实现抛出 [UnsupportedError]，子类按需覆写。
  Future<void> setHwdec(String mode) async {
    throw UnsupportedError('setHwdec is not supported by this backend');
  }

  /// 设置音频通道：auto/stereo/mono。
  ///
  /// 默认实现抛出 [UnsupportedError]，子类按需覆写。
  Future<void> setAudioChannel(String channel) async {
    throw UnsupportedError('setAudioChannel is not supported by this backend');
  }

  /// 设置画面比例：default/4:3/16:9/fill。
  ///
  /// 默认实现抛出 [UnsupportedError]，子类按需覆写。
  Future<void> setAspectRatio(String ratio) async {
    throw UnsupportedError('setAspectRatio is not supported by this backend');
  }

  /// 设置 GLSL 用户 shader 列表（mpv `glsl-shaders`， 超分辨率）。
  ///
  /// 传入空字符串表示清空（关闭超分辨率）。
  Future<void> setUpscaleShaders(String shaders) async {
    throw UnsupportedError('setUpscaleShaders is not supported by this backend');
  }

  /// 应用 demuxer 缓存档位（字节预算 + 秒数上限 + 缓冲迟滞，缓存策略降级）。
  ///
  /// 默认实现抛出 [UnsupportedError]，子类按需覆写。
  Future<void> setDemuxerCacheBudget(
    int maxBytes,
    int maxBackBytes,
    double cacheSecs,
    double hysteresisSecs,
  ) async {
    throw UnsupportedError('setDemuxerCacheBudget is not supported by this backend');
  }

  /// open 前按地址准备 demuxer 格式（HLS 强制 hls）。
  ///
  /// 默认实现抛出 [UnsupportedError]，子类按需覆写。
  Future<void> prepareDemuxerForUrl(String url) async {
    throw UnsupportedError('prepareDemuxerForUrl is not supported by this backend');
  }

  /// 切换直播流模式（小缓存快贴边缘 + 禁用强制可拖动）。
  ///
  /// `true` 应用直播配方、`false` 恢复点播默认；播放中探测到直播流时
  /// 运行时调用。默认实现空操作（降级后端无 mpv 属性能力），子类按需覆写。
  Future<void> setLiveStreamMode(bool enabled) async {}

  /// 读取后端只读属性（如 mpv 的 `hwdec-current`）。
  ///
  /// 默认实现返回 null（不支持查询），子类按需覆写。
  Future<String?> getProperty(String name) async => null;

  /// 当前解码模式。
  String get currentHwdec;

  /// 当前音频通道。
  String get currentAudioChannel;

  /// 当前画面比例。
  String get currentAspectRatio;
}
