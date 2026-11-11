/// 在线 TTS 播放管线（滑动窗口版）。
///
/// 流程：段落 → [segmentSpeech] 分句（本地角色/性别）→ 并发合成
/// （worker 池，上限 [NovelHttpTtsConfig.concurrency]）→ **按句序**播放，
/// 首句合成完即开播、后续边播边合成（替代旧版「整章合成完才播」）。
///
/// 多角色动态路由：每句在**合成时刻**经 [TtsSegmentProvider]（AI 归因
/// provider，可空）解析最终角色与性别、经 [TtsVoiceResolver]（路由器，
/// 可空）解析音色——AI 归因在朗读开始后后台完成时，剩余未合成句子自动
/// 使用新结果，无需重启朗读。
///
/// 失败语义（与旧版一致）：单句合成失败按配置静音占位跳过或立即终止；
/// 连续失败达 [NovelHttpTtsConfig.maxConsecutiveFailures] 终止剩余。
library;

import 'dart:async';
import 'dart:typed_data';

import 'novel_http_tts_config.dart';
import 'novel_http_tts_engine.dart';
import 'novel_speech_segmenter.dart';

/// 句播放控制接口（暂停 / 继续 / 立即停止）。
///
/// 由具体播放器实现（默认实现基于 media_kit，见
/// `novel_http_tts_sentence_player.dart`）。抽象成接口是为了让本文件保持
/// 无原生依赖，便于纯 Dart 单测。
abstract class TtsPlaybackControl {
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
}

/// 单句播放结果：成功 / 跳过（静音占位）/ 终止（连续失败达阈值）。
enum TtsSentenceOutcome {
  /// 播放成功（或成功并入队列）。
  played,

  /// 合成失败且配置静音占位：跳过继续。
  skipped,

  /// 合成失败且配置禁止占位（或已达连续失败阈值）：终止本轮。
  aborted,
}

/// 按句播放回调：给定预合成的音频字节，返回该句是否播放成功
/// （回调内部实现实际播放：media_kit / 系统播放器等）。
typedef TtsSentencePlayer = Future<bool> Function(Uint8List bytes);

/// 一条待合成句（带段落/句序号，供 AI 归因 provider 对位）。
class TtsSentenceUnit {
  const TtsSentenceUnit({
    required this.paragraphIndex,
    required this.segIndex,
    required this.segment,
  });

  /// 所属段落下标（与输入 paragraphs 对齐）。
  final int paragraphIndex;

  /// 段内句序号。
  final int segIndex;

  final SpeechSegment segment;
}

/// 合成时刻的段级解析器：输入本地分句结果，返回最终段（AI 归因完成后
/// 由 provider 内部切换数据源，角色与性别都可被升级）。
typedef TtsSegmentProvider = SpeechSegment Function(TtsSentenceUnit unit);

/// 音色解析器：角色 + 性别 → HTTP voice id。
typedef TtsVoiceResolver = String Function(String role, String gender);

/// 在线 TTS 播放控制器（与播放内核解耦，核心调度可单测）。
class NovelHttpTtsPlayer {
  NovelHttpTtsPlayer({
    required this.config,
    required this.player,
    this.rate = 1.0,
    this.control,
    TtsSynthesisEngine? engine,
  }) : engine = engine ?? HttpTtsPreloader(config: config, rate: rate);

  final NovelHttpTtsConfig config;
  final TtsSentencePlayer player;
  final double rate;
  final TtsSynthesisEngine engine;

  /// 当前句播放控制（可选）：让暂停 / 继续 / 立即停止作用在音频进程上。
  final TtsPlaybackControl? control;

  /// 全部段落播完回调（自动续章 的触发点）。
  void Function()? onCompleted;

  /// 当前句索引（调试 / UI 高亮）。
  int currentIndex = 0;

  bool _cancelled = false;

  /// 暂停态：句间暂停时不再起播下一句，等待 [resume]。
  bool _paused = false;

  bool get paused => _paused;

  /// 暂停：当前句立即止声（保留进度），后续句不再起播。
  Future<void> pause() async {
    if (_cancelled) return;
    _paused = true;
    await control?.pause();
  }

  /// 继续：从暂停处接着播完当前句，然后照常推进。
  Future<void> resume() async {
    if (_cancelled) return;
    _paused = false;
    await control?.resume();
  }

  /// 连续合成失败句数（成功复位；达阈值后 worker 不再领取新句）。
  int _consecutiveFailures = 0;

  bool get _halted => _consecutiveFailures >= config.maxConsecutiveFailures;

  /// 取消本轮朗读（停止后续合成与播放，并立即停掉正在播的音频）。
  void cancel() {
    _cancelled = true;
    _paused = false;
    unawaited(control?.stop());
  }

  /// 朗读一组段落（[startParagraphIndex] 起的段落参与合成，之前的跳过——
  /// 章中开始朗读时不重读前文）。
  Future<void> speak(
    List<String> paragraphs, {
    int startParagraphIndex = 0,
    Map<String, String> knownGenders = const <String, String>{},
    TtsSegmentProvider? segmentProvider,
    TtsVoiceResolver? voiceResolver,
  }) async {
    _cancelled = false;
    currentIndex = 0;
    _consecutiveFailures = 0;

    // 1) 分句（本地角色 + 性别推断）。
    final units = <TtsSentenceUnit>[];
    for (var p = 0; p < paragraphs.length; p++) {
      if (p < startParagraphIndex) continue;
      var segIdx = 0;
      for (final seg
          in segmentSpeech(paragraphs[p], knownGenders: knownGenders)) {
        units.add(TtsSentenceUnit(
            paragraphIndex: p, segIndex: segIdx++, segment: seg));
      }
    }
    if (units.isEmpty) {
      // 整章无内容（且从头开始）视为播完，触发续章；跳读导致的无句则
      // 静默结束（调用方传入的区间有误，不应连锁翻章）。
      if (startParagraphIndex <= 0) onCompleted?.call();
      return;
    }

    SpeechSegment segmentOf(TtsSentenceUnit u) =>
        segmentProvider?.call(u) ?? u.segment;
    String roleOf(TtsSentenceUnit u) => segmentOf(u).role;
    String voiceOf(TtsSentenceUnit u) =>
        voiceResolver?.call(roleOf(u), segmentOf(u).gender) ??
        config.voiceForRole(roleOf(u));

    // 2) 并发合成（worker 池）+ 按序播放。
    // completers 预先建满：worker 领句即 complete，播放循环按序 await，
    // 两端互不等待对方推进（首句就绪即开播）。
    final results = <Completer<TtsSynthesisResult>>[
      for (var i = 0; i < units.length; i++) Completer<TtsSynthesisResult>(),
    ];
    var nextIndex = 0;

    Future<void> workerLoop() async {
      while (!_cancelled) {
        final i = nextIndex++;
        if (i >= units.length) return;
        if (_halted) {
          results[i].complete(
              TtsSynthesisResult(bytes: null, role: roleOf(units[i])));
          continue;
        }
        final u = units[i];
        TtsSynthesisResult r;
        try {
          r = await engine.synthesize(
              text: u.segment.text, voice: voiceOf(u), role: roleOf(u));
        } on Object {
          r = TtsSynthesisResult(bytes: null, role: roleOf(u));
        }
        if (_cancelled) return;
        results[i].complete(r);
      }
    }

    final workerCount = config.concurrency.clamp(1, 8);
    final workers = <Future<void>>[
      for (var w = 0; w < workerCount && w < units.length; w++) workerLoop(),
    ];

    // 3) 按句序播放。
    var aborted = false;
    for (var i = 0; i < units.length; i++) {
      if (_cancelled) return;
      // 暂停态：当前句已被 control.pause 止声，句间不再起播下一句。
      while (_paused && !_cancelled) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      if (_cancelled) return;
      currentIndex = i;
      final bytes = (await results[i].future).bytes;
      if (bytes == null) {
        _consecutiveFailures++;
        if (!config.silentPlaceholderOnFailure || _halted) {
          aborted = true;
          break;
        }
        continue;
      }
      _consecutiveFailures = 0;
      final ok = await player(bytes);
      if (_cancelled) return;
      if (!ok) {
        // 播放失败按合成失败同策略降级。
        _consecutiveFailures++;
        if (!config.silentPlaceholderOnFailure || _halted) {
          aborted = true;
          break;
        }
      }
    }
    if (aborted) return;
    // 合成 worker 与播放循环共享 cancel 位；正常走完时等 workers 收尾，
    // 防止泄漏未完成的 dio 请求（cancel 时由调用方生命周期兜底）。
    if (!_cancelled) {
      try {
        await Future.wait<void>(workers);
      } on Object {
        // worker 异常已在内部转为失败结果，这里只是收尾。
      }
    }
    onCompleted?.call();
  }
}
