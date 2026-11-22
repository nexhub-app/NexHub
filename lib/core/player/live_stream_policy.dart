/// 直播流播放策略：mpv 缓存配方 + 直播协议判定。
///
/// 点播配方（[DemuxerCacheProfile]）追求「拖动余量与抗波动」，对直播流
/// 恰恰有害：120s 预读 + 80s 缓冲重启迟滞意味着一次缓冲事件后播放位置
/// 会落后直播边缘最多数十秒；`force-seekable=yes` 让用户能对直播流发起
/// 必然卡死的 seek。直播配方反向取值：小缓存快贴边缘、迟滞取秒级避免
/// 「停一下缓冲一下」的锯齿，同时禁用强制可拖动。
///
/// 直播流识别：mpv 对直播 HLS（无 `EXT-X-ENDLIST`）/ 裸 TS 流不上报时长，
/// 表现为 `duration` 恒为 0 而位置在推进——播放器侧据此判定；本文件额外
/// 提供 open 前即可判定的协议前缀（rtsp / rtmp 等天生直播协议）。
library;

/// 直播流播放策略（纯静态，便于单测）。
abstract final class LiveStreamPolicy {
  /// open 前即可认定为直播的协议前缀（小写比较）。
  ///
  /// m3u8 既可能是点播也可能是直播，不在此列，交给播放中探测。
  static const List<String> _liveSchemes = <String>[
    'rtsp://',
    'rtmp://',
    'rtp://',
    'udp://',
    'srt://',
    'mms://',
  ];

  /// 地址是否为天生直播协议（open 前判定；仅 http(s)/file 类地址返回 false）。
  static bool isLiveProtocolUrl(String url) {
    final lower = url.toLowerCase();
    return _liveSchemes.any(lower.startsWith);
  }

  /// 前向缓存秒数上限（mpv `cache-secs`）。直播要低延迟：只预读 4 秒，
  /// 缓冲恢复后快速贴回直播边缘。
  static const double cacheSecs = 4;

  /// 缓冲重启迟滞（mpv `demuxer-hysteresis-secs`）。点播取 80s 防锯齿，
  /// 直播流码率恒定，1s 低水位即可让 demuxer 持续平滑拉流。
  static const double hysteresisSecs = 1;

  /// 前向缓存字节预算（mpv `demuxer-max-bytes`）。4 秒 1080p 约 2MB，
  /// 取 16MiB 封顶足够。
  static const int maxBytes = 16 * 1024 * 1024;

  /// 后向缓存字节预算（mpv `demuxer-max-back-bytes`）。直播不 seek，
  /// 无需保留回看缓冲，只留少量应对短暂回跳。
  static const int maxBackBytes = 4 * 1024 * 1024;

  /// 探测直播的最短观察窗口（秒）：open 后 position 推进且 duration
  /// 仍为 0 持续超过该时长 → 判定为直播。取 3s 平衡误判（慢速点播
  /// 元数据晚到）与起播体验。
  static const Duration detectWindow = Duration(seconds: 3);
}
