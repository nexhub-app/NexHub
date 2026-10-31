import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/ai/bing_translation_client.dart';
import 'package:nexhub/core/ai/translation_exception.dart';

class _BingAdapter implements HttpClientAdapter {
  _BingAdapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;
  final List<dynamic> bodies = <dynamic>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    bodies.add(options.data);
    return respond(options);
  }
}

ResponseBody _json(List<Map<String, dynamic>> items) => ResponseBody.fromString(
      jsonEncode(items),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );

ResponseBody _error(int code) => ResponseBody.fromString('', code);

void main() {
  setUp(BingTranslationClient.resetCircuitBreaker);
  tearDown(BingTranslationClient.resetCircuitBreaker);

  test('批量翻译保持输入顺序并回填检测语言一致的原文', () async {
    late _BingAdapter adapter;
    adapter = _BingAdapter((options) {
      final texts = (options.data as List).cast<String>();
      return _json(<Map<String, dynamic>>[
        for (final t in texts)
          <String, dynamic>{
            'detectedLanguage': <String, dynamic>{'language': 'en'},
            'translations': <Map<String, dynamic>>[
              <String, dynamic>{'text': '译:$t', 'to': 'zh-Hans'},
            ],
          },
      ]);
    });
    final client = BingTranslationClient(
      dio: Dio()..httpClientAdapter = adapter,
      delay: (_) async {},
    );
    final result = await client.translate(
      texts: <String>['Hello', 'World'],
      targetLang: '中文',
    );
    expect(result, <String>['译:Hello', '译:World']);
    expect(adapter.bodies.single, <String>['Hello', 'World']);
  });

  test('空串跳过、重复文本去重并还原顺序', () async {
    late _BingAdapter adapter;
    adapter = _BingAdapter((options) {
      final texts = (options.data as List).cast<String>();
      return _json(<Map<String, dynamic>>[
        for (final t in texts)
          <String, dynamic>{
            'translations': <Map<String, dynamic>>[
              <String, dynamic>{'text': '[$t]', 'to': 'zh-Hans'},
            ],
          },
      ]);
    });
    final client = BingTranslationClient(
      dio: Dio()..httpClientAdapter = adapter,
      delay: (_) async {},
    );
    final result = await client.translate(
      texts: <String>['A', '', 'A', 'B'],
      targetLang: 'zh-Hans',
    );
    expect(result, <String>['[A]', '', '[A]', '[B]']);
    expect(adapter.bodies.single, <String>['A', 'B']);
  });

  test('响应条数不一致抛格式异常', () async {
    final client = BingTranslationClient(
      dio: Dio()
        ..httpClientAdapter = _BingAdapter(
          (_) => _json(<Map<String, dynamic>>[
            <String, dynamic>{
              'translations': <Map<String, dynamic>>[
                <String, dynamic>{'text': 'only one', 'to': 'zh-Hans'},
              ],
            },
          ]),
        ),
      delay: (_) async {},
    );
    await expectLater(
      client.translate(texts: <String>['A', 'B'], targetLang: 'zh-Hans'),
      throwsA(isA<TranslationException>()),
    );
  });

  test('429 / 5xx 重试后成功', () async {
    var calls = 0;
    final client = BingTranslationClient(
      dio: Dio()
        ..httpClientAdapter = _BingAdapter((options) {
          calls++;
          if (calls == 1) return _error(429);
          if (calls == 2) return _error(500);
          return _json(<Map<String, dynamic>>[
            <String, dynamic>{
              'translations': <Map<String, dynamic>>[
                <String, dynamic>{'text': '好', 'to': 'zh-Hans'},
              ],
            },
          ]);
        }),
      delay: (_) async {},
    );
    final result = await client.translate(
        texts: <String>['Good'], targetLang: 'zh-Hans');
    expect(result, <String>['好']);
    expect(calls, 3);
  });

  test('4xx 不重试', () async {
    var calls = 0;
    final client = BingTranslationClient(
      dio: Dio()
        ..httpClientAdapter = _BingAdapter((_) {
          calls++;
          return _error(400);
        }),
      delay: (_) async {},
    );
    await expectLater(
      client.translate(texts: <String>['A'], targetLang: 'zh-Hans'),
      throwsA(isA<TranslationException>()),
    );
    expect(calls, 1);
  });

  test('连续 3 次失败后熔断', () async {
    var calls = 0;
    final client = BingTranslationClient(
      dio: Dio()
        ..httpClientAdapter = _BingAdapter((_) {
          calls++;
          return _error(400);
        }),
      delay: (_) async {},
    );
    for (var i = 0; i < 3; i++) {
      await expectLater(
        client.translate(texts: <String>['A'], targetLang: 'zh-Hans'),
        throwsA(isA<TranslationException>()),
      );
    }
    await expectLater(
      client.translate(texts: <String>['B'], targetLang: 'zh-Hans'),
      throwsA(isA<TranslationException>()),
    );
    expect(calls, 3);
    expect(BingTranslationClient.circuitOpen, isTrue);
  });

  test('超长文本切分后顺序拼接', () async {
    late _BingAdapter adapter;
    adapter = _BingAdapter((options) {
      final texts = (options.data as List).cast<String>();
      return _json(<Map<String, dynamic>>[
        for (final t in texts)
          <String, dynamic>{
            'translations': <Map<String, dynamic>>[
              <String, dynamic>{'text': t, 'to': 'zh-Hans'},
            ],
          },
      ]);
    });
    final client = BingTranslationClient(
      dio: Dio()..httpClientAdapter = adapter,
      delay: (_) async {},
    );
    final long = '${'a' * 5000}。${'b' * 5000}';
    final result = await client.translate(
        texts: <String>[long], targetLang: 'zh-Hans');
    expect(result.single, long);
    expect((adapter.bodies.single as List).length, 2);
  });

  test('中英混杂原样回显时按外文源重译并折叠重复片段', () async {
    late _BingAdapter adapter;
    adapter = _BingAdapter((options) {
      final texts = (options.data as List).cast<String>();
      final from = options.queryParameters['from'] as String?;
      if (from == null) {
        // 自动检测：被判定为「已是中文」，原样回显。
        return _json(<Map<String, dynamic>>[
          for (final t in texts)
            <String, dynamic>{
              'detectedLanguage': <String, dynamic>{'language': 'zh-Hans'},
              'translations': <Map<String, dynamic>>[
                <String, dynamic>{'text': t, 'to': 'zh-Hans'},
              ],
            },
        ]);
      }
      // 显式外文源：正常译出（且端点把中文名再译一遍，产生重复片段）。
      return _json(<Map<String, dynamic>>[
        for (final _ in texts)
          <String, dynamic>{
            'translations': <Map<String, dynamic>>[
              <String, dynamic>{'text': '进击的巨人 进击的巨人', 'to': 'zh-Hans'},
            ],
          },
      ]);
    });
    final client = BingTranslationClient(
      dio: Dio()..httpClientAdapter = adapter,
      delay: (_) async {},
    );
    final result = await client.translate(
      texts: <String>['进击的巨人 Attack on Titan', '纯中文标题'],
      targetLang: '中文',
    );
    expect(result, <String>['进击的巨人', '纯中文标题']);
    // 一次自动检测 + 一次显式 from=en 重译；纯中文标题不重试。
    expect(adapter.bodies.length, 2);
    expect(adapter.bodies.last, <String>['进击的巨人 Attack on Titan']);
  });
}
