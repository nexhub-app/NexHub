/// 默认在线 TTS 句播放器：写入临时文件后用 media_kit 播放。
///
/// 实现 [TtsSentencePlayer]：把合成字节落盘到系统临时目录，media_kit
/// `Player` 播放音频文件，等待 completion / error / 主动取消。
/// 单句播完返回 true；失败返回 false（上层按配置降级跳过）。
///
/// 注：media_kit 在 flutter test 环境不可用（无原生内核），因此本文件
/// 不参与纯 Dart 单测——核心调度（分句/预下载/降级）已在
/// `novel_http_tts_player.dart` 覆盖。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';

import 'novel_http_tts_player.dart' show TtsPlaybackControl, TtsSentencePlayer;

/// 播放器取消回调（调用方在停止/退出时触发）。
typedef TtsPlaybackCanceller = Future<void> Function();

/// 基于 media_kit 的句播放控制句柄。
///
/// 每句独立 [Player]（播完即释放），句柄只跟踪「当前正在播的那个」，
/// 让暂停 / 继续 / 立即停止能直接作用在音频进程上。
///
/// 注：曾尝试整段会话复用同一个 Player 想省掉设备初始化，但复用后
/// `completed` / `duration` / `error` 这些广播流会带着上一句的残留值，
/// 反而造成「整句被误判已播完」或「等待时长失效」，实测更差，故维持
/// 每句独立实例。
class MediaKitTtsPlaybackControl implements TtsPlaybackControl {
  Player? _player;

  /// 播放器创建后回填（当前句）。
  void attach(Player player) => _player = player;

  /// 播放器销毁前解绑。
  void detach(Player player) {
    if (identical(_player, player)) _player = null;
  }

  bool get hasActivePlayer => _player != null;

  /// 暂停当前句（保留播放进度，继续时从断点播完）。
  @override
  Future<void> pause() async {
    final Player? p = _player;
    if (p == null) return;
    try {
      await p.pause();
    } on Object {
      // 内核不支持时忽略（退化为「念完当前句」）。
    }
  }

  /// 继续当前句。
  @override
  Future<void> resume() async {
    final Player? p = _player;
    if (p == null) return;
    try {
      await p.play();
    } on Object {
      // 同上。
    }
  }

  /// 立即停止当前句（退出 / 停止朗读时用，避免残留声音）。
  @override
  Future<void> stop() async {
    final Player? p = _player;
    if (p == null) return;
    try {
      await p.stop();
    } on Object {
      // 同上。
    }
  }

  /// 结束会话：等同立即停止当前句（播放器由句播放函数自行释放）。
  @override
  Future<void> dispose() => stop();
}

/// 返回默认的逐句播放函数。
///
/// [cancelled] 返回 true 时立即中断当前句（返回 false 触发降级/终止）。
/// [control] 提供后可复用播放器并支持暂停 / 继续 / 停止。
TtsSentencePlayer buildDefaultTtsSentencePlayer({
  required bool Function() cancelled,
  MediaKitTtsPlaybackControl? control,
}) {
  return (Uint8List bytes) async {
    if (cancelled()) return false;
    // 落盘临时 mp3（TTS 服务通常返回 mp3/ogg；扩展名不影响内核解码）。
    final dir = await Directory.systemTemp.createTemp('nexhub_tts_');
    final file = File('${dir.path}/sentence.mp3');
    // 每句独立播放器：广播流不残留上一句的状态，耗时换正确性。
    final Player player = Player();
    control?.attach(player);
    try {
      // flush: 必须等字节真正落盘再播放。默认不刷盘时播放器可能读到
      // 尚未写完的头部（尤其是刚创建的小文件），开头若干帧解析失败
      // 被跳过 —— 听感正是「起播丢几个字」。
      await file.writeAsBytes(bytes, flush: true);
      // 起播丢帧对策（「预热后重播」）：
      // 每句新建播放器时，音频输出设备要几百毫秒才真正出声，这段时间
      // 相当于把句子开头几个字吞掉（用户感受就是「每段开头丢几个字」）。
      // 做法：先静音起播把设备顶起来，等设备稳定后 seek 回 0 再放开音量
      // ——丢帧发生在静音期间，用户实际听到的是完整句子。
      await player.open(Media(file.path), play: false);
      // 先挂好完成监听（起播前挂，避免短句错过）。
      final Completer<bool> completer = Completer<bool>();
      final StreamSubscription<bool> doneSub =
          player.stream.completed.listen((bool done) {
        if (done && !completer.isCompleted) completer.complete(true);
      });
      final StreamSubscription<String> errSub =
          player.stream.error.listen((_) {
        if (!completer.isCompleted) completer.complete(false);
      });
      try {
        try {
          await player.setVolume(0);
          await player.play();
          // 给音频设备约 200ms 启动时间（覆盖典型起播丢帧窗口）。
          await Future<void>.delayed(const Duration(milliseconds: 200));
          if (!completer.isCompleted) {
            // 回到句首再恢复音量：保证第一个字完整。
            try {
              await player.seek(Duration.zero);
            } on Object {
              // seek 失败就按当前位置继续（部分内核不支持短音频 seek）。
            }
            await player.setVolume(100);
          }
        } on Object {
          // 音量控制不可用：退回直接播放（至少不阻断朗读）。
          try {
            await player.play();
          } on Object {
            // 起播失败交由下方超时兜底。
          }
        }
        final ok = await completer.future.timeout(const Duration(seconds: 60),
            onTimeout: () {
          try {
            player.stop();
          } on Object {
            // 忽略停止异常
          }
          return false;
        });
        return ok;
      } finally {
        await doneSub.cancel();
        await errSub.cancel();
      }
    } on Object {
      return false;
    } finally {
      control?.detach(player);
      try {
        await player.dispose();
      } on Object {
        // 忽略释放异常
      }
      try {
        await dir.delete(recursive: true);
      } on Object {
        // 忽略清理失败
      }
    }
  };
}