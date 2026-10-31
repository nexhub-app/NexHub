/// 详情页 / 评论等 UI 文本翻译：40ms 聚合批量 + Bing 优先 + AI 兜底。
library;

import 'dart:async';

import '../../features/novel/domain/novel_summary_settings.dart';
import '../utils/app_log.dart';
import 'batch_protocol.dart';
import 'bing_translation_client.dart';
import 'endpoint_router.dart';
import 'text_translation_cache.dart';
import 'translation_exception.dart';
import 'translation_faithfulness.dart';
import 'translation_feature_flags.dart';
import 'translation_language.dart';
import 'vision_translation_client.dart';

class UiTextTranslator {
  UiTextTranslator({
    BingTranslationClient? bing,
    VisionTranslationClient? aiClient,
    TextTranslationCache? cache,
    TranslationFeatureFlags? flags,
  })  : _bing = bing ?? BingTranslationClient(),
        _ai = aiClient ?? VisionTranslationClient(),
        _cache = cache ?? TextTranslationCache(),
        _flags = flags ?? TranslationFeatureFlags.instance;

  static final UiTextTranslator instance = UiTextTranslator();

  final BingTranslationClient _bing;
  final VisionTranslationClient _ai;
  final TextTranslationCache _cache;
  final TranslationFeatureFlags _flags;

  final Map<String, String> _memory = <String, String>{};
  final Map<String, Future<String?>> _inFlight = <String, Future<String?>>{};
  final Map<String, _PendingText> _pending = <String, _PendingText>{};
  Timer? _timer;

  /// 翻译一条文本。
  ///
  /// 自动模式失败返回 null（调用方保留原文）；手动模式失败抛
  /// [TranslationException]（调用方弹 SnackBar）。
  Future<String?> translate(
    String text, {
    required String targetLang,
    bool manual = false,
  }) {
    final source = text.trim();
    if (source.isEmpty) return Future<String?>.value();
    if (!manual && !TranslationLanguage.shouldTranslate(source, targetLang)) {
      return Future<String?>.value();
    }
    final target = TranslationLanguage.bingCode(targetLang) ?? targetLang.trim();
    final key = TextTranslationCache.keyFor(target, source);
    final cached = _memory[key];
    if (cached != null) return Future<String?>.value(cached);
    final running = _inFlight[key];
    if (running != null) {
      if (!manual) return running;
      return running.then(
        (value) => value ??
            (throw const TranslationException('翻译失败，请稍后重试')),
      );
    }
    final completer = Completer<String?>();
    _inFlight[key] = completer.future;
    _pending[key] = _PendingText(
      source: source,
      target: target,
      manual: manual,
      completer: completer,
    );
    _timer ??= Timer(const Duration(milliseconds: 40), () {
      unawaited(_flush());
    });
    return completer.future;
  }

  Future<void> _flush() async {
    _timer = null;
    if (_pending.isEmpty) return;
    final entries = _pending.values.toList(growable: false);
    _pending.clear();
    final groups = <String, List<_PendingText>>{};
    for (final entry in entries) {
      groups.putIfAbsent(entry.target, () => <_PendingText>[]).add(entry);
    }
    for (final group in groups.values) {
      try {
        await _translateGroup(group);
      } on Object catch (e) {
        AppLog.instance.w('[文本翻译] 批处理失败: $e');
        for (final entry in group) {
          if (entry.completer.isCompleted) continue;
          if (entry.manual) {
            entry.completer.completeError(TranslationException.from(e));
          } else {
            entry.completer.complete(null);
          }
        }
      } finally {
        for (final entry in group) {
          _inFlight.remove(TextTranslationCache.keyFor(entry.target, entry.source));
        }
      }
    }
  }

  Future<void> _translateGroup(List<_PendingText> group) async {
    await _flags.ensureLoaded();
    final target = group.first.target;
    final results = <String, String>{};

    for (final entry in group) {
      try {
        final cached = await _cache.get(entry.target, entry.source);
        if (cached != null) {
          _memory[TextTranslationCache.keyFor(entry.target, entry.source)] =
              cached;
          results[entry.source] = cached;
        }
      } on Object {
        // 缓存读失败按未命中处理。
      }
    }

    final remaining = group
        .where((e) => !results.containsKey(e.source))
        .toList(growable: false);
    Object? lastError;

    if (remaining.isNotEmpty && _flags.bingEnabled) {
      try {
        final translated = await _bing.translate(
          texts: <String>[for (final e in remaining) e.source],
          targetLang: target,
        );
        for (var i = 0; i < remaining.length; i++) {
          final text = translated[i].trim();
          if (text.isEmpty) continue;
          // 混杂文本被原样回显（必应判成「已是目标语言」）：不写缓存，
          // 留给下面的 AI 兜底真正译一次，否则会长期卡在「译不出来」。
          if (TranslationLanguage.isMixedLanguage(
                remaining[i].source,
                target,
              ) &&
              TranslationFaithfulness.isSourceEcho(
                remaining[i].source,
                text,
                minLength: 1,
              )) {
            continue;
          }
          results[remaining[i].source] = text;
          await _store(remaining[i], text);
        }
      } on Object catch (e) {
        lastError = e;
        AppLog.instance.w('[文本翻译] Bing 失败，转 AI: $e');
      }
    }

    final unresolved = group
        .where((e) => !results.containsKey(e.source))
        .toList(growable: false);
    if (unresolved.isNotEmpty) {
      final endpoints = await _resolveEndpoints();
      if (endpoints.isNotEmpty) {
        try {
          final translated = await AiEndpointRouter.execute<List<String>>(
            endpoints,
            (cfg) => _ai.translateBatch(
              config: cfg,
              targetLang: TranslationLanguage.readableName(target),
              texts: <String>[for (final e in unresolved) e.source],
              systemPrompt: _systemPrompt(target),
            ),
          );
          for (var i = 0; i < unresolved.length; i++) {
            final text = translated[i].trim();
            if (text.isEmpty) continue;
            results[unresolved[i].source] = text;
            await _store(unresolved[i], text);
          }
        } on Object catch (e) {
          lastError = e;
          AppLog.instance.w('[文本翻译] AI 兜底失败: $e');
        }
      }
    }

    for (final entry in group) {
      if (entry.completer.isCompleted) continue;
      final value = results[entry.source];
      if (value != null) {
        entry.completer.complete(value);
      } else if (entry.manual) {
        entry.completer.completeError(
          lastError is TranslationException
              ? lastError
              : (lastError != null
                  ? TranslationException.from(lastError)
                  : const TranslationException('Bing 与 AI 均不可用，请稍后重试')),
        );
      } else {
        entry.completer.complete(null);
      }
    }
  }

  Future<void> _store(_PendingText entry, String translation) async {
    _memory[TextTranslationCache.keyFor(entry.target, entry.source)] =
        translation;
    try {
      await _cache.put(entry.target, entry.source, translation);
    } on Object {
      // 持久化失败不影响本次展示。
    }
  }

  Future<List<AiEndpointConfig>> _resolveEndpoints() async {
    try {
      final cfgs = await NovelSummarySettings.instance.getTranslationEndpoints();
      return <AiEndpointConfig>[
        for (final c in cfgs)
          if (c.baseUrl.trim().isNotEmpty)
            AiEndpointConfig(
              baseUrl: c.baseUrl,
              apiKey: c.apiKey,
              model: c.model,
            ),
      ];
    } on Object {
      return const <AiEndpointConfig>[];
    }
  }

  static String _systemPrompt(String target) =>
      '你是专业翻译引擎。用户会按 <<<N>>> 编号给出多条文本，'
      '请逐条翻译成${TranslationLanguage.readableName(target)}。'
      '只输出编号和译文，保持条数与顺序一致，不要输出解释。'
      '批量协议格式由 ${BatchProtocol.encode(<String>['示例']).trim()} 约定。';
}

class _PendingText {
  _PendingText({
    required this.source,
    required this.target,
    required this.manual,
    required this.completer,
  });

  final String source;
  final String target;
  final bool manual;
  final Completer<String?> completer;
}
