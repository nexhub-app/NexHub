/// 小说阅读器 TTS 朗读控制器。
///
/// 封装朗读引擎（Android/iOS/桌面为 flutter_tts，鸿蒙为 CoreSpeechKit），
/// 提供逐段朗读、暂停/恢复/停止、自动翻段功能。
/// 朗读状态通过 [notifyListeners] 广播，阅读器据此更新 UI。
///
/// 多角色朗读（参考 legado_NG 架构按 nexhub 体量裁剪）：
/// - **系统链路逐句读**：整段朗读改为分句朗读，每句前按路由
///   （[NovelTtsRouter].systemVoice）切换系统声音；
/// - **在线链路**：HTTP TTS 走 [NovelHttpTtsPlayer] 滑动窗口管线，
///   音色按路由（httpVoice）解析，音频经 [TtsAudioFileCache] 落盘缓存；
/// - **AI 分镜后台归因**：朗读开始即用本地分句结果开播，AI 归因在后台
///   按章缓存执行，完成后剩余句子自动升级（合成时刻经 provider 查询）；
/// - **跨章续读**：[autoNext] 开启时章末回调 [onChapterFinished]，由
///   阅读器加载下一章并继续朗读。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/novel/novel_http_tts_config.dart';
import '../../../core/novel/novel_edge_tts_engine.dart';
import '../../../core/novel/novel_http_tts_engine.dart';
import '../../../core/novel/novel_http_tts_player.dart';
import '../../../core/novel/novel_http_tts_sentence_player.dart';
import '../../../core/novel/novel_speech_segmenter.dart';
import '../../../core/novel/novel_tts_audio_cache.dart';
import '../../../core/novel/novel_tts_cast_store.dart';
import '../../../core/novel/novel_tts_engine.dart';
import '../../../core/novel/novel_tts_router.dart';
import '../domain/novel_tts_storyboard_service.dart';

enum NovelTtsState {
  stopped,
  playing,
  paused,
}

/// 系统链路的一个待读句（段落号 + 分句结果）。
class _SystemEntry {
  const _SystemEntry(this.paragraphIndex, this.segment);

  final int paragraphIndex;
  final SpeechSegment segment;
}

/// 一次朗读会话的多角色上下文。
class _MultiRoleSession {
  _MultiRoleSession({
    required this.novelId,
    this.chapterId,
    required this.router,
    required this.knownGenders,
  });

  final String novelId;
  final String? chapterId;
  final NovelTtsRouter router;
  final Map<String, String> knownGenders;

  /// AI 分镜结果（后台归因完成后赋值；null = 仍用本地结果）。
  ChapterStoryboard? storyboard;
}

class NovelTtsController extends ChangeNotifier {
  NovelTtsController({NovelTtsEngine Function()? engineFactory})
      : _engineFactory = engineFactory ?? createNovelTtsEngine;

  /// 引擎工厂（测试注入假引擎）。
  final NovelTtsEngine Function() _engineFactory;

  NovelTtsEngine? _tts;
  NovelTtsState _state = NovelTtsState.stopped;
  int _currentIndex = 0;
  List<String> _paragraphs = const <String>[];

  /// 在线引擎的活跃播放会话（朗读中非空，用于取消）。
  NovelHttpTtsPlayer? _onlinePlayer;

  /// 当前会话多角色上下文（null = 单音色模式）。
  _MultiRoleSession? _session;

  /// 会话代次：跨章续读/重新开始递增，防止旧会话回调串台。
  int _sessionGeneration = 0;

  /// 跨章连播开关：章末回调 [onChapterFinished] 而不是停止。
  bool autoNext = false;

  /// 章末回调（[autoNext] 开启时触发；由阅读器翻章续读）。
  Future<void> Function()? onChapterFinished;

  /// 朗读位置推进回调（段落索引变化时触发，阅读器据此持久化进度）。
  void Function(int paragraphIndex)? onProgress;

  /// 系统引擎声音表（名字 → 声音；懒加载）。
  Map<String, NovelTtsVoice>? _systemVoicesByName;

  /// 系统链路待读句列表与当前句下标。
  List<_SystemEntry> _systemEntries = const <_SystemEntry>[];
  int _systemIdx = 0;

  /// 系统链路最近应用的声音名（避免重复 setVoice）。
  String _lastAppliedSystemVoice = '';

  double _rate = 1.0;
  Timer? _sleepTimer;
  Duration? _sleepRemaining;
  bool _backgroundMode = false;

  /// 最近一次朗读错误（阅读器取走后清空）。
  String? _lastError;

  /// 引擎当前是否正在朗读某一句。用于"点按切换段落"时先 [FlutterTts.stop]
  /// 打断旧句、再朗读新句（flutter_tts 4.2.5 无 setQueueMode，用 stop+speak
  /// 模拟 QUEUE_FLUSH，避免旧句播完才接新句——"仍朗读之前的句子"）。
  bool _isSpeaking = false;

  NovelTtsState get state => _state;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _state == NovelTtsState.playing;
  bool get isPaused => _state == NovelTtsState.paused;
  double get rate => _rate;
  Duration? get sleepRemaining => _sleepRemaining;
  bool get hasSleepTimer => _sleepTimer != null;
  bool get backgroundMode => _backgroundMode;

  /// 枚举系统引擎声音（角色面板「系统声音」下拉用）。
  Future<List<NovelTtsVoice>> systemVoices() async {
    await _ensureTts();
    return _tts!.getVoices();
  }

  /// 取走最近一次朗读错误（无错误返回 null）。
  String? takeLastError() {
    final String? error = _lastError;
    _lastError = null;
    return error;
  }

  /// 设置后台朗读开关：true 时应用进入后台仍继续朗读；
  /// false 时进入后台由调用方（AppLifecycle 监听）触发 [pause]。
  void setBackground(bool enabled) {
    if (_backgroundMode == enabled) return;
    _backgroundMode = enabled;
    notifyListeners();
  }

  /// 初始化 TTS 引擎（懒加载）。
  Future<void> _ensureTts() async {
    if (_tts != null) return;
    _tts = _engineFactory();
    // 先挂完成回调，确保初始化任何一步失败也不会漏掉（此前 setQueueMode
    // 在 4.2.5 无原生实现会抛 MissingPluginException，导致回调从未注册、
    // 读完一句即停）。
    _tts!.setCompletionHandler(_onComplete);
    _tts!.setErrorHandler(_onError);
    await _tts!.setLanguage('zh-CN');
    await _tts!.setSpeechRate(_rate);
  }

  /// 构建多角色会话上下文（角色卡 + 路由 + 性别表）。
  Future<_MultiRoleSession?> _buildSession({
    String? novelId,
    String? chapterId,
    NovelTtsSystemSlots? systemSlots,
  }) async {
    final httpCfg = await NovelHttpTtsConfigStore().load();
    final id = novelId ?? '';
    if (id.isEmpty && systemSlots == null) return null;
    List<NovelCastCharacter> characters = const <NovelCastCharacter>[];
    if (id.isNotEmpty) {
      try {
        characters = await NovelTtsCastStore.instance.loadCharacters(id);
      } on Object {
        // 角色卡存储异常不阻断朗读（退化为全局兜底路由）。
        characters = const <NovelCastCharacter>[];
      }
    }
    return _MultiRoleSession(
      novelId: id,
      chapterId: (chapterId ?? '').isNotEmpty ? chapterId : null,
      router: NovelTtsRouter(
        characters: characters,
        httpConfig: httpCfg,
        systemSlots: systemSlots ?? const NovelTtsSystemSlots(),
      ),
      knownGenders: <String, String>{
        for (final c in characters)
          if (c.gender != SpeechGender.unknown) c.name: c.gender,
        for (final c in characters)
          for (final a in c.aliases)
            if (c.gender != SpeechGender.unknown) a: c.gender,
      },
    );
  }

  /// 开始朗读段落列表，从指定索引开始。
  ///
  /// [sleepTimer] 为睡眠定时（分钟）；> 0 时启动后自动开启定时器，
  /// 到时停止朗读。用于 prefs.ttsSleepTimer 持久化恢复。
  ///
  /// [novelId]/[chapterId] 提供时启用多角色：角色卡路由 + AI 分镜后台
  /// 归因（仅在线链路）。优先使用在线 HTTP TTS 引擎（配置启用且有模板）。
  Future<void> speak(List<String> paragraphs,
      {int startIndex = 0,
      int sleepTimer = 0,
      String? novelId,
      String? chapterId,
      NovelTtsSystemSlots? systemSlots,
      bool autoNextChapter = false}) async {
    // 新会话：作废旧在线播放与系统句列表。
    _sessionGeneration++;
    _onlinePlayer?.cancel();
    _onlinePlayer = null;
    _systemEntries = const <_SystemEntry>[];
    // 系统引擎的上一句必须显式 stop：否则点段落跳读 / 换章重读时，
    // 旧句会继续念完（听感上是「两段朗读叠在一起」）。
    if (_tts != null) {
      try {
        await _tts!.stop();
      } on Object {
        // 部分平台未初始化时 stop 抛错，忽略。
      }
    }
    autoNext = autoNextChapter;

    _paragraphs = paragraphs;
    _currentIndex = startIndex.clamp(0, paragraphs.length - 1);
    _lastError = null;
    _state = NovelTtsState.playing;
    notifyListeners();
    await _setAwake(true);
    if (sleepTimer > 0) {
      startSleepTimer(sleepTimer);
    }

    _session = await _buildSession(
        novelId: novelId, chapterId: chapterId, systemSlots: systemSlots);

    // 在线引擎优先（Edge 内置语音或自定义 HTTP 端点）。
    final cfg = await NovelHttpTtsConfigStore().load();
    if (cfg.enabled && (cfg.isEdge || cfg.urlTemplate.isNotEmpty)) {
      await _startOnline(cfg, paragraphs, startIndex: startIndex, chapterId: chapterId);
      return;
    }
    await _ensureTts();
    await _startSystem(paragraphs, startIndex: startIndex, chapterId: chapterId);
  }

  /// 在线链路：滑动窗口管线 + 音频缓存 + 动态角色 provider + 后台 AI 归因。
  Future<void> _startOnline(
    NovelHttpTtsConfig cfg,
    List<String> paragraphs, {
    int startIndex = 0,
    String? chapterId,
  }) async {
    final session = _session;
    final generation = _sessionGeneration;
    final cache = await TtsAudioFileCache.createDefault();
    // Edge 内置语音与自定义 HTTP 端点共用播放管线，仅合成引擎不同。
    final engine = cfg.isEdge
        ? EdgeTtsSynthesisEngine(rate: _rate, cache: cache)
        : HttpTtsPreloader(config: cfg, rate: _rate, cache: cache);
    final control = MediaKitTtsPlaybackControl();
    final player = NovelHttpTtsPlayer(
      config: cfg,
      rate: _rate,
      engine: engine,
      control: control,
      player: buildDefaultTtsSentencePlayer(
        cancelled: () =>
            _state == NovelTtsState.stopped ||
            generation != _sessionGeneration,
        control: control,
      ),
    );
    _onlinePlayer = player;
    // 段落推进 → 阅读器高亮 / 自动跟随滚动（在线链路此前完全不推进
    // `_currentIndex`，高亮永远停在第 0 段，自动跟随也一直往章首滚）。
    player.onParagraphChanged = (int paragraphIndex) {
      if (generation != _sessionGeneration) return;
      if (_state == NovelTtsState.stopped) return;
      if (paragraphIndex == _currentIndex) return;
      _currentIndex = paragraphIndex;
      notifyListeners();
      onProgress?.call(paragraphIndex);
    };
    player.onCompleted = () {
      if (_state == NovelTtsState.stopped ||
          generation != _sessionGeneration) {
        return;
      }
      if (autoNext && onChapterFinished != null) {
        // 保持 playing 态，交给阅读器翻章续读；回调失败由其兜底 stop。
        scheduleMicrotask(() {
          if (_state != NovelTtsState.stopped &&
              generation == _sessionGeneration) {
            onChapterFinished!();
          }
        });
      } else {
        _state = NovelTtsState.stopped;
        _isSpeaking = false;
        notifyListeners();
      }
    };

    // AI 分镜后台归因（无配置/失败静默降级；完成后剩余句自动升级）。
    if (session != null &&
        session.novelId.isNotEmpty &&
        chapterId != null &&
        chapterId.isNotEmpty) {
      final novelId = session.novelId;
      unawaited(() async {
        final storyboard = await NovelTtsStoryboardService()
            .attributeChapter(
                novelId: novelId, chapterId: chapterId, paragraphs: paragraphs);
        if (storyboard != null &&
            generation == _sessionGeneration &&
            _session == session) {
          session.storyboard = storyboard;
        }
      }());
    }

    await player.speak(
      paragraphs,
      startParagraphIndex: startIndex,
      knownGenders: session?.knownGenders ?? const {},
      segmentProvider: session == null
          ? null
          : (unit) => session.storyboard?.segmentFor(unit) ?? unit.segment,
      voiceResolver:
          session == null ? null : (role, gender) => session.router.route(role, gender).httpVoice,
    );
    if (generation == _sessionGeneration) {
      _onlinePlayer = null;
    }
  }

  /// 系统链路：逐句朗读 + 按路由切换系统声音。
  Future<void> _startSystem(
    List<String> paragraphs, {
    int startIndex = 0,
    String? chapterId,
  }) async {
    final session = _session;
    final generation = _sessionGeneration;
    final entries = <_SystemEntry>[];
    for (var p = 0; p < paragraphs.length; p++) {
      if (p < startIndex) continue;
      for (final seg
          in segmentSpeech(paragraphs[p], knownGenders: session?.knownGenders ?? const {})) {
        entries.add(_SystemEntry(p, seg));
      }
    }
    _systemEntries = entries;
    _systemIdx = 0;
    _lastAppliedSystemVoice = '';
    _systemVoicesByName ??= <String, NovelTtsVoice>{
      for (final v in await _tts!.getVoices()) v.name: v,
    };

    // AI 归因后台任务（系统链路同样受益：剩余句的角色/性别升级）。
    if (session != null &&
        session.novelId.isNotEmpty &&
        chapterId != null &&
        chapterId.isNotEmpty) {
      final novelId = session.novelId;
      unawaited(() async {
        final storyboard = await NovelTtsStoryboardService()
            .attributeChapter(
                novelId: novelId, chapterId: chapterId, paragraphs: paragraphs);
        if (storyboard != null &&
            generation == _sessionGeneration &&
            _session == session) {
          session.storyboard = storyboard;
        }
      }());
    }

    if (entries.isEmpty) {
      _onChapterEnd(generation);
      return;
    }
    await _speakSystemCurrent(generation);
  }

  /// 朗读当前系统句（含声音切换）。
  Future<void> _speakSystemCurrent(int generation) async {
    if (generation != _sessionGeneration ||
        _state == NovelTtsState.stopped) {
      return;
    }
    if (_systemIdx < 0 || _systemIdx >= _systemEntries.length) {
      _onChapterEnd(generation);
      return;
    }
    if (_isSpeaking) {
      try {
        await _tts!.stop();
      } on Object {
        // 部分平台 stop 可能抛错，忽略后继续朗读新句。
      }
    }
    final entry = _systemEntries[_systemIdx];
    // AI 分镜升级（合成/朗读时刻动态查询）。
    var segment = entry.segment;
    final storyboard = _session?.storyboard;
    if (storyboard != null) {
      segment = storyboard.segmentFor(TtsSentenceUnit(
        paragraphIndex: entry.paragraphIndex,
        segIndex: _segIndexOf(entry),
        segment: entry.segment,
      ));
    }
    // 声音路由：解析到名字才切换；解析不出保持当前声音。
    final voiceName =
        _session?.router.route(segment.role, segment.gender).systemVoice ?? '';
    if (voiceName.isNotEmpty && voiceName != _lastAppliedSystemVoice) {
      final voice = _systemVoicesByName?[voiceName] ??
          NovelTtsVoice(name: voiceName);
      final ok = await _tts!.setVoice(voice);
      if (ok) _lastAppliedSystemVoice = voiceName;
    }
    if (entry.paragraphIndex != _currentIndex) {
      _currentIndex = entry.paragraphIndex;
      notifyListeners();
      onProgress?.call(_currentIndex);
    }
    _isSpeaking = true;
    // 前导顿号：系统引擎每次 speak 都要"起转"，头几十毫秒的音频会被
    // 丢掉（听感是每句开头少几个字）。前面加一个静默标点，让引擎先处理
    // 标点把起转时间耗掉，正文就能完整读出。
    await _tts!.speak('、${segment.text}');
  }

  /// 句在其段落内的序号（AI 分镜 unitKey 对位用）。
  int _segIndexOf(_SystemEntry entry) {
    var idx = 0;
    for (final e in _systemEntries) {
      if (e.paragraphIndex != entry.paragraphIndex) continue;
      if (identical(e, entry)) return idx;
      idx++;
    }
    return 0;
  }

  /// 章末处理：跨章续读或停止。
  void _onChapterEnd(int generation) {
    if (_state == NovelTtsState.stopped || generation != _sessionGeneration) {
      return;
    }
    if (autoNext && onChapterFinished != null) {
      scheduleMicrotask(() {
        if (_state != NovelTtsState.stopped &&
            generation == _sessionGeneration) {
          onChapterFinished!();
        }
      });
    } else {
      _state = NovelTtsState.stopped;
      _isSpeaking = false;
      _cancelSleepTimer();
      _sleepRemaining = null;
      _setAwake(false);
      notifyListeners();
    }
  }

  /// 暂停朗读。
  ///
  /// 两条链路分别处理：
  /// - 在线链路：直接暂停 media_kit 当前句（保留进度），并让句间不再起播；
  /// - 系统链路：多数平台的原生 TTS `pause` 不可靠（会继续念完），改为
  ///   `stop` 当前句并记住位置，恢复时从该句重读。
  Future<void> pause() async {
    if (_state != NovelTtsState.playing) return;
    if (_onlinePlayer != null) {
      await _onlinePlayer!.pause();
      _state = NovelTtsState.paused;
      _isSpeaking = false;
      notifyListeners();
      return;
    }
    if (_tts == null) return;
    try {
      await _tts!.stop();
    } on Object {
      // 停止失败不阻断状态切换（宁可静音也不继续念）。
    }
    _state = NovelTtsState.paused;
    _isSpeaking = false;
    notifyListeners();
  }

  /// 恢复朗读。
  Future<void> resume() async {
    if (_state != NovelTtsState.paused) return;
    _state = NovelTtsState.playing;
    notifyListeners();
    await _setAwake(true);
    if (_onlinePlayer != null) {
      // 在线链路：接着播完当前句，随后照常推进（不重建会话、不重头念）。
      await _onlinePlayer!.resume();
      return;
    }
    if (_tts == null) return;
    await _speakSystemCurrent(_sessionGeneration);
  }

  /// 停止朗读。
  Future<void> stop() async {
    _sessionGeneration++;
    _onlinePlayer?.cancel();
    _onlinePlayer = null;
    _systemEntries = const <_SystemEntry>[];
    if (_tts == null) {
      _state = NovelTtsState.stopped;
      _isSpeaking = false;
      _cancelSleepTimer();
      _sleepRemaining = null;
      await _setAwake(false);
      notifyListeners();
      return;
    }
    await _tts!.stop();
    _state = NovelTtsState.stopped;
    _isSpeaking = false;
    _cancelSleepTimer();
    _sleepRemaining = null;
    await _setAwake(false);
    notifyListeners();
  }

  /// 朗读下一段。
  Future<void> next() async {
    if (_onlinePlayer != null) return; // 在线链路整章连续，不支持段落跳转
    final nextIdx = _nextParagraphBoundary(_currentIndex, forward: true);
    if (nextIdx == null) return;
    _currentIndex = nextIdx;
    _systemIdx = _firstEntryIndexOfParagraph(nextIdx);
    _state = NovelTtsState.playing;
    notifyListeners();
    await _speakSystemCurrent(_sessionGeneration);
  }

  /// 朗读上一段。
  Future<void> prev() async {
    if (_onlinePlayer != null) return;
    final prevIdx = _nextParagraphBoundary(_currentIndex, forward: false);
    if (prevIdx == null) return;
    _currentIndex = prevIdx;
    _systemIdx = _firstEntryIndexOfParagraph(prevIdx);
    _state = NovelTtsState.playing;
    notifyListeners();
    await _speakSystemCurrent(_sessionGeneration);
  }

  int? _nextParagraphBoundary(int from, {required bool forward}) {
    if (_systemEntries.isEmpty) {
      // 无分段信息（异常态）按段落表兜底。
      final target = forward ? from + 1 : from - 1;
      return (target >= 0 && target < _paragraphs.length) ? target : null;
    }
    if (forward) {
      for (final e in _systemEntries) {
        if (e.paragraphIndex > from) return e.paragraphIndex;
      }
      return null;
    }
    int? result;
    for (final e in _systemEntries) {
      if (e.paragraphIndex >= from) break;
      result = e.paragraphIndex;
    }
    return result;
  }

  int _firstEntryIndexOfParagraph(int paragraphIndex) {
    for (var i = 0; i < _systemEntries.length; i++) {
      if (_systemEntries[i].paragraphIndex == paragraphIndex) return i;
    }
    return 0;
  }

  /// 设置语速（0.5–2.0）。
  Future<void> setRate(double rate) async {
    _rate = rate.clamp(0.5, 2.0);
    await _ensureTts();
    await _tts!.setSpeechRate(_rate);
    notifyListeners();
  }

  /// 启动睡眠定时（分钟；<=0 取消）。到时自动停止朗读。
  void startSleepTimer(int minutes) {
    _cancelSleepTimer();
    if (minutes <= 0) {
      _sleepRemaining = null;
      notifyListeners();
      return;
    }
    _sleepRemaining = Duration(minutes: minutes);
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      final left =
          (_sleepRemaining ?? Duration.zero) - const Duration(seconds: 1);
      if (left <= Duration.zero) {
        _sleepRemaining = null;
        _cancelSleepTimer();
        stop();
      } else {
        _sleepRemaining = left;
        notifyListeners();
      }
    });
    notifyListeners();
  }

  /// 取消睡眠定时。
  void cancelSleepTimer() {
    _sleepRemaining = null;
    _cancelSleepTimer();
    notifyListeners();
  }

  void _cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
  }

  /// 后台保活：朗读时持有唤醒锁，停止时释放（熄屏 / 退后台仍可继续朗读）。
  Future<void> _setAwake(bool on) async {
    try {
      if (on) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } on Object {
      // 部分平台不支持唤醒锁，忽略。
    }
  }

  /// 引擎朗读失败：停止本轮并记录错误，由阅读器提示用户。
  void _onError(String message) {
    if (_state == NovelTtsState.stopped) return;
    _state = NovelTtsState.stopped;
    _isSpeaking = false;
    _lastError = message;
    _cancelSleepTimer();
    _sleepRemaining = null;
    _setAwake(false);
    notifyListeners();
  }

  /// 当前句朗读完毕回调：自动朗读下一句；章末走 [_onChapterEnd]。
  void _onComplete() {
    if (_state != NovelTtsState.playing) return;
    if (_onlinePlayer != null) return; // 在线链路由 player 自行推进
    _isSpeaking = false;
    _systemIdx++;
    if (_systemIdx >= _systemEntries.length) {
      _onChapterEnd(_sessionGeneration);
      return;
    }
    // 完成事件可能由原生在非平台线程回调，延后到事件循环再朗读下一句，
    // 规避 flutter_tts 通道线程告警（shell.cc: The ... channel sent a
    // message ... on a non-platform thread）。再留 ~80ms 间隙：原生引擎
    // 在上一句刚结束时立刻 speak，句首容易被削掉（每句开头缺字）。
    Future<void>.delayed(const Duration(milliseconds: 80),
        () => _speakSystemCurrent(_sessionGeneration));
  }

  @override
  void dispose() {
    _cancelSleepTimer();
    _onlinePlayer?.cancel();
    _onlinePlayer = null;
    _tts?.dispose();
    // dispose 不能 await：异步吞掉平台异常（测试环境无插件通道）。
    WakelockPlus.disable().catchError((Object _) {});
    super.dispose();
  }
}
