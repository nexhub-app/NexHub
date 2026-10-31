/// Bing Edge 免费翻译客户端。
///
/// 非公开端点、无 SLA：批量上限保守取值，网络/超时/429/5xx 重试，
/// 连续失败触发 5 分钟熔断。所有异常归一化为 [TranslationException]。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../utils/app_log.dart';
import 'translation_exception.dart';
import 'translation_language.dart';

class BingTranslationClient {
  BingTranslationClient({
    Dio? dio,
    Future<void> Function(Duration)? delay,
  })  : _dio = dio ?? Dio(),
        _delay = delay ?? Future<void>.delayed;

  final Dio _dio;
  final Future<void> Function(Duration) _delay;

  static const String endpoint =
      'https://edge.microsoft.com/translate/translatetext';
  static const int maxBatchItems = 80;
  static const int maxBatchChars = 12000;
  static const int maxItemChars = 8000;

  static const int _maxRetries = 2;
  static const int _failuresToTrip = 3;
  static const Duration _cooldown = Duration(minutes: 5);

  static int _consecutiveFailures = 0;
  static DateTime? _openUntil;

  /// 测试时钟注入点。
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// 清空熔断状态（测试用）。
  @visibleForTesting
  static void resetCircuitBreaker() {
    _consecutiveFailures = 0;
    _openUntil = null;
    clock = DateTime.now;
  }

  /// 当前是否处于熔断冷却期；冷却结束自动复位。
  static bool get circuitOpen {
    final until = _openUntil;
    if (until == null) return false;
    if (clock().isBefore(until)) return true;
    _openUntil = null;
    _consecutiveFailures = 0;
    return false;
  }

  /// 翻译文本列表；返回与输入等长（空串原样返回）。
  Future<List<String>> translate({
    required List<String> texts,
    required String targetLang,
    String? fromLang,
  }) async {
    if (texts.isEmpty) return const <String>[];
    final target = TranslationLanguage.bingCode(targetLang);
    if (target == null) {
      throw const TranslationException('目标语言暂不支持 Bing 免费翻译');
    }
    if (circuitOpen) {
      throw const TranslationException('Bing 免费翻译暂时不可用，请稍后重试');
    }

    final result = List<String>.filled(texts.length, '');
    final unique = <String, List<int>>{};
    for (var i = 0; i < texts.length; i++) {
      final text = texts[i];
      if (text.trim().isEmpty) continue;
      unique.putIfAbsent(text, () => <int>[]).add(i);
    }
    if (unique.isEmpty) return result;

    final uniqueTexts = unique.keys.toList(growable: false);
    final pieces = <_Piece>[];
    for (var owner = 0; owner < uniqueTexts.length; owner++) {
      for (final part in _splitLongText(uniqueTexts[owner])) {
        pieces.add(_Piece(owner, part));
      }
    }
    final ownerParts = <List<String>>[
      for (var i = 0; i < uniqueTexts.length; i++) <String>[],
    ];
    try {
      for (final batch in _buildBatches(pieces)) {
        final translations = await _postBatch(
          <String>[for (final p in batch) p.text],
          target,
          fromLang,
        );
        for (var i = 0; i < batch.length; i++) {
          ownerParts[batch[i].owner].add(translations[i]);
        }
      }
    } on TranslationException {
      _recordFailure();
      rethrow;
    } on DioException catch (e) {
      _recordFailure();
      AppLog.instance.w('[Bing翻译] 请求失败: $e');
      final code = e.response?.statusCode;
      throw TranslationException(
        code == 429 ? '请求过于频繁，请稍后重试' : 'Bing 免费翻译暂时不可用，请稍后重试',
        kind: code == 429 ? TranslationKind.rateLimit : TranslationKind.other,
      );
    } on Object catch (e) {
      _recordFailure();
      AppLog.instance.w('[Bing翻译] 请求失败: $e');
      throw const TranslationException('Bing 免费翻译暂时不可用，请稍后重试');
    }

    _consecutiveFailures = 0;
    _openUntil = null;
    for (var owner = 0; owner < uniqueTexts.length; owner++) {
      final joined = ownerParts[owner].join();
      if (joined.trim().isEmpty) {
        throw const TranslationException('Bing 返回内容为空');
      }
      for (final index in unique[uniqueTexts[owner]]!) {
        result[index] = joined;
      }
    }
    await _retryMixedEchoes(result, texts, targetLang, target);
    return result;
  }

  Iterable<List<_Piece>> _buildBatches(List<_Piece> pieces) sync* {
    var batch = <_Piece>[];
    var chars = 0;
    for (final piece in pieces) {
      if (batch.isNotEmpty &&
          (batch.length >= maxBatchItems ||
              chars + piece.text.length > maxBatchChars)) {
        yield batch;
        batch = <_Piece>[];
        chars = 0;
      }
      batch.add(piece);
      chars += piece.text.length;
    }
    if (batch.isNotEmpty) yield batch;
  }

  List<String> _splitLongText(String text) {
    if (text.length <= maxItemChars) return <String>[text];
    final out = <String>[];
    var start = 0;
    while (text.length - start > maxItemChars) {
      final limit = start + maxItemChars;
      var cut = limit;
      final floor = (limit - 1000).clamp(start + 1, limit);
      for (var i = limit; i > floor; i--) {
        final c = text[i - 1];
        if (c == '\n' ||
            c == '。' ||
            c == '！' ||
            c == '？' ||
            c == '.' ||
            c == '!' ||
            c == '?' ||
            c == '；' ||
            c == ';') {
          cut = i;
          break;
        }
      }
      out.add(text.substring(start, cut));
      start = cut;
    }
    if (start < text.length) out.add(text.substring(start));
    return out;
  }

  Future<List<String>> _postBatch(
    List<String> texts,
    String target,
    String? fromLang,
  ) async {
    var attempt = 0;
    while (true) {
      try {
        final resp = await _dio.post<dynamic>(
          endpoint,
          queryParameters: <String, dynamic>{
            'to': target,
            'isEnterpriseClient': 'false',
            if (fromLang != null && fromLang.isNotEmpty) 'from': fromLang,
          },
          options: Options(
            contentType: Headers.jsonContentType,
            sendTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
          ),
          data: texts,
        );
        return _parse(resp.data, texts);
      } on DioException catch (e) {
        if (!_retryable(e) || attempt >= _maxRetries) rethrow;
        await _delay(Duration(milliseconds: attempt == 0 ? 500 : 1500));
        attempt++;
      }
    }
  }

  List<String> _parse(dynamic data, List<String> sources) {
    dynamic decoded = data;
    if (decoded is String) {
      try {
        decoded = jsonDecode(decoded);
      } on Object {
        throw const TranslationException('Bing 返回格式异常');
      }
    }
    if (decoded is! List || decoded.length != sources.length) {
      throw const TranslationException('Bing 返回格式异常');
    }
    final out = <String>[];
    for (var i = 0; i < decoded.length; i++) {
      final item = decoded[i];
      if (item is! Map) {
        throw const TranslationException('Bing 返回格式异常');
      }
      final translations = item['translations'];
      final text = translations is List &&
              translations.isNotEmpty &&
              translations.first is Map
          ? (translations.first as Map)['text'] as String?
          : null;
      if (text == null || text.trim().isEmpty) {
        throw const TranslationException('Bing 返回内容为空');
      }
      // 检测语言等于目标语言时不再无条件回填原文：中英混杂文本会被判成
      // 「已是中文」而原样回显，看起来像「翻不出来」。统一交由
      // [_retryMixedEchoes] 按混排情况决定是否用外文源重译。
      out.add(text);
    }
    return out;
  }

  /// 混杂文本回显补救：中英 / 中日混排常被判为目标语言而原样返回，
  /// 这里显式指定外文源语言重译一次，并折叠重复片段。
  ///
  /// 只在「结果与原文完全一致」且「文本确实混排」时触发，避免多余请求；
  /// 重译仍无变化（或失败）时保留原结果，由上层决定是否走 AI 兜底。
  Future<void> _retryMixedEchoes(
    List<String> result,
    List<String> sources,
    String targetLang,
    String targetCode,
  ) async {
    final byFrom = <String, List<int>>{};
    for (var i = 0; i < sources.length; i++) {
      final source = sources[i];
      if (source.trim().isEmpty) continue;
      if (result[i].trim().isEmpty) continue;
      if (!_isEcho(source, result[i])) continue;
      if (!TranslationLanguage.isMixedLanguage(source, targetLang)) continue;
      final from = TranslationLanguage.foreignSourceCode(source, targetLang);
      if (from == null) continue;
      byFrom.putIfAbsent(from, () => <int>[]).add(i);
    }
    for (final entry in byFrom.entries) {
      try {
        final translated = await _postBatch(
          <String>[for (final i in entry.value) sources[i]],
          targetCode,
          entry.key,
        );
        for (var k = 0; k < entry.value.length; k++) {
          final index = entry.value[k];
          final text = _collapseRepeatedParts(translated[k]).trim();
          if (text.isEmpty) continue;
          if (_isEcho(sources[index], text)) continue;
          result[index] = text;
        }
      } on Object catch (e) {
        AppLog.instance.w('[Bing翻译] 混杂文本重译失败: $e');
      }
    }
  }

  static final RegExp _compareNoise =
      RegExp(r'''[\s\.,!?;:，。！？；：、…—–\-_"'“”‘’()（）\[\]【】《》]+''');

  /// 忽略空白/标点/大小写后是否与原文完全相同（即「原样回显」）。
  static bool _isEcho(String source, String translation) {
    final a = source.toLowerCase().replaceAll(_compareNoise, '');
    if (a.isEmpty) return false;
    return a == translation.toLowerCase().replaceAll(_compareNoise, '');
  }

  /// 折叠紧邻重复的片段：「进击的巨人 进击的巨人」→「进击的巨人」。
  ///
  /// 显式源语言改译时，端点常把已有中文名再译一遍，产生重复片段。
  static String _collapseRepeatedParts(String text) {
    if (text.contains('\n')) return text;
    final parts = text.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length < 2) return text;
    final out = <String>[];
    for (final part in parts) {
      if (out.isNotEmpty && _isEcho(out.last, part)) continue;
      out.add(part);
    }
    return out.join(' ');
  }

  static bool _retryable(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return true;
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode ?? 0;
        return code == 429 || code >= 500;
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
        return false;
      default:
        return false;
    }
  }

  static void _recordFailure() {
    _consecutiveFailures++;
    if (_consecutiveFailures >= _failuresToTrip) {
      _openUntil = clock().add(_cooldown);
      AppLog.instance.w('[Bing翻译] 连续失败 $_consecutiveFailures 次，熔断 5 分钟');
    }
  }
}

class _Piece {
  const _Piece(this.owner, this.text);

  final int owner;
  final String text;
}
