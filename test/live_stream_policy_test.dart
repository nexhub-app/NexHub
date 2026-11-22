// live_stream_policy_test：直播流协议判定 + 直播缓存配方数值合法性。
//
// 直播判定在播放中依赖 mpv 状态轮询（测试环境无原生 libmpv，不可单测），
// open 前的协议判定与配方常量是纯 Dart，抽出单测防止回归。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/player/live_stream_policy.dart';

void main() {
  group('LiveStreamPolicy.isLiveProtocolUrl', () {
    test('天生直播协议前缀判定为直播', () {
      expect(LiveStreamPolicy.isLiveProtocolUrl('rtsp://cam.local/stream'),
          isTrue);
      expect(
          LiveStreamPolicy.isLiveProtocolUrl('rtmp://live.example.com/app'),
          isTrue);
      expect(LiveStreamPolicy.isLiveProtocolUrl('rtp://239.1.1.1:5000'),
          isTrue);
      expect(LiveStreamPolicy.isLiveProtocolUrl('udp://@239.1.1.1:5000'),
          isTrue);
      expect(LiveStreamPolicy.isLiveProtocolUrl('srt://host:9000'), isTrue);
      expect(LiveStreamPolicy.isLiveProtocolUrl('mms://host/stream'), isTrue);
    });

    test('大小写不敏感', () {
      expect(LiveStreamPolicy.isLiveProtocolUrl('RTSP://CAM/STREAM'), isTrue);
      expect(LiveStreamPolicy.isLiveProtocolUrl('Rtmp://Live/App'), isTrue);
    });

    test('http(s) 与本地地址不是天生直播协议（交给播放中探测）', () {
      expect(
          LiveStreamPolicy.isLiveProtocolUrl(
              'https://cdn.example.com/live/master.m3u8'),
          isFalse);
      expect(
          LiveStreamPolicy.isLiveProtocolUrl(
              'http://media.example.com/video.mp4'),
          isFalse);
      expect(LiveStreamPolicy.isLiveProtocolUrl('/storage/emulated/0/a.mp4'),
          isFalse);
      expect(LiveStreamPolicy.isLiveProtocolUrl('file:///tmp/a.mp4'), isFalse);
      expect(LiveStreamPolicy.isLiveProtocolUrl(''), isFalse);
    });

    test('前缀之外的同名子串不误判', () {
      // 'partsp://' / 'extra://rtsp://x' 等不是直播协议前缀。
      expect(LiveStreamPolicy.isLiveProtocolUrl('artsp://x'), isFalse);
      expect(LiveStreamPolicy.isLiveProtocolUrl('https://x/rtsp://y'),
          isFalse);
    });
  });

  group('LiveStreamPolicy 直播配方', () {
    test('迟滞小于前向缓存秒数（避免 demuxer 水位倒挂）', () {
      expect(LiveStreamPolicy.hysteresisSecs,
          lessThan(LiveStreamPolicy.cacheSecs));
    });

    test('配方显著小于点播标准档（直播要低延迟）', () {
      // 点播标准档 cache-secs=120s / 32MiB；直播必须明显更小。
      expect(LiveStreamPolicy.cacheSecs, lessThan(30));
      expect(LiveStreamPolicy.maxBytes, lessThan(32 * 1024 * 1024));
      expect(LiveStreamPolicy.maxBackBytes, lessThan(32 * 1024 * 1024));
    });

    test('探测窗口合理（≥2s 防误判，≤10s 不拖慢就绪判定）', () {
      expect(LiveStreamPolicy.detectWindow.inSeconds, inInclusiveRange(2, 10));
    });
  });
}
