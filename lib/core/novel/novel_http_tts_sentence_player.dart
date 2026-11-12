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
/// 默认播放器每句新建一个 media_kit [Player]（播完即 dispose），上层拿不到
/// 实例，导致「暂停 / 继续 / 立即停止」只能等整句播完才生效（表现为点了
/// 暂停还在念）。本句柄由播放器在创建/释放时回填当前实例，上层即可把
/// 控制直接作用在音频进程上。
class MediaKitTtsPlaybackControl implements TtsPlaybackControl {
  Player? _player;

  void attach(Player player) => _player = player;

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
}

/// 返回默认的逐句播放函数。
///
/// [cancelled] 返回 true 时立即中断当前句（返回 false 触发降级/终止）。
/// [control] 提供后可对正在播放的句子做暂停 / 继续 / 停止。
TtsSentencePlayer buildDefaultTtsSentencePlayer({
  required bool Function() cancelled,
  MediaKitTtsPlaybackControl? control,
}) {
  return (Uint8List bytes) async {
    if (cancelled()) return false;
    // 落盘临时 mp3（TTS 服务通常返回 mp3/ogg；扩展名不影响内核解码）。
    final dir = await Directory.systemTemp.createTemp('nexhub_tts_');
    final file = File('${dir.path}/sentence.mp3');
    try {
      await file.writeAsBytes(bytes);
      // 鸿蒙内核默认随包可用（media_kit_libs_ohos）；创建失败由外层 catch 兜底。
      final player = Player();
      control?.attach(player);
      try {
        // 先只加载、不自动播：让 mpv 把文件 demux 完、解码器与音频输出
        // 通道就绪后再显式 play()。直接 open(play: true) 会在输出设备
        // 就绪前推进播放时钟，听感上就是「每句开头被吞掉一小段」。
        await player.open(Media(file.path), play: false);
        // 等解码器探到时长再起播（多数平台 open 返回后仍在校验/建音频
        // 输出通道，此刻 play 会吞掉开头几十毫秒）。拿不到时长就按
        // 超时兜底继续，不阻塞朗读。
        try {
          await player.stream.duration
              .firstWhere((Duration d) => d > Duration.zero)
              .timeout(const Duration(milliseconds: 400));
        } on Object {
          // 超时 / 无时长推送：直接起播。
        }
        // 等待播放完成：轮询 position+state（无原生 completion 事件，
        // 用「不再播放」回调简化处理——音频很短，等待播放状态结束即可）。
        final completer = Completer<bool>();
        player.stream.completed.listen((bool done) {
          if (done && !completer.isCompleted) completer.complete(true);
        });
        player.stream.error.listen((_) {
          if (!completer.isCompleted) completer.complete(false);
        });
        await player.play();
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
      } on Object {
        return false;
      } finally {
        control?.detach(player);
        try {
          await player.dispose();
        } on Object {
          // 忽略释放异常
        }
      }
    } on Object {
      return false;
    } finally {
      try {
        await dir.delete(recursive: true);
      } on Object {
        // 忽略清理失败
      }
    }
  };
}