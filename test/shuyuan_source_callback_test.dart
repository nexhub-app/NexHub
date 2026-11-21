/// 书源事件回调（legado `SourceCallBack` / `callBackJs`）回归。
///
/// 对照 md3：
/// - 门控：源未开启 eventListener 或 callBackJs 为空 → noCall（默认动作）；
/// - 返回值口径：真值 → 不执行默认动作；假值（空 / "null" / false|no|not|0|0.0）
///   → 执行默认动作；脚本异常 → 只记日志，默认动作也不执行；
/// - 绑定：event / result / book / chapter（含 VIP/已购标记）；
/// - 宿主动作：java.open 登录/搜索/发现请求、java.copyText、java.putConcurrent；
/// - CopyTocUrl 的 result 由书对象 tocUrl 补齐（详情阶段缓存）。
///
/// 全部使用合成源与本地 HTTP 页面，不访问任何真实站点。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/core/resolver/resolver_registry.dart';
import 'package:nexhub/core/scraper/media_api_service.dart';
import 'package:nexhub/features/shuyuan/analyze/concurrent_rate_limiter.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/model/source_callback_result.dart';
import 'package:nexhub/features/shuyuan/presentation/shuyuan_callback_host.dart';
import 'package:nexhub/features/shuyuan/presentation/shuyuan_novel_resolver.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';

const String _origin = 'https://src.test';

PluginConfig _sourceOf({
  String? callBackJs,
  bool eventListener = true,
  bool customButton = false,
  Map<String, dynamic>? bookInfo,
}) {
  return ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(<String, dynamic>{
    'bookSourceName': 'callback-test',
    'bookSourceUrl': _origin,
    'bookSourceType': 0,
    'eventListener': eventListener,
    'customButton': customButton,
    'ruleContent': <String, dynamic>{
      'content': '#c@text',
      if (callBackJs != null) 'callBackJs': callBackJs,
    },
    if (bookInfo != null) 'ruleBookInfo': bookInfo,
  }));
}

Future<SourceCallbackResult> _run(
  MediaApiService service,
  PluginConfig source,
  String event, {
  String? result,
  String bookUrl = '$_origin/book/1',
  String bookName = '合成书',
  String? chapterUrl,
}) {
  return service.runSourceCallback(
    source,
    event,
    bookUrl: bookUrl,
    bookName: bookName,
    chapterUrl: chapterUrl,
    chapterTitle: chapterUrl == null ? null : '第七章',
    chapterIndex: chapterUrl == null ? null : 6,
    chapterVip: chapterUrl != null,
    result: result,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late MediaApiService service;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ShuyuanSourceContext.resetForTest();
    JsEngine.resetPoolForTest();
    registerShuyuanResolver(ShuyuanNovelResolver.new);
    service = MediaApiService(ResolverRegistry.instance);
  });

  Future<(HttpServer, String)> startServer(Map<String, String> routes) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) {
      final body = routes[req.uri.path];
      req.response
        ..statusCode = body == null ? 404 : 200
        ..headers.contentType = ContentType.html
        ..write(body ?? '');
      req.response.close();
    });
    return (server, 'http://127.0.0.1:${server.port}');
  }

  group('门控（md3 callBackBtn noCall）', () {
    test('未开启 eventListener：不执行脚本，按默认动作处理', () async {
      final PluginConfig source = _sourceOf(callBackJs: '"true"', eventListener: false);
      expect(service.canRunSourceCallback(source), isFalse);
      final r = await _run(service, source, 'clickCustomButton');
      expect(r.runDefault, isTrue);
      expect(r.value, '');
    });

    test('callBackJs 为空：不执行脚本，按默认动作处理', () async {
      final PluginConfig source = _sourceOf(callBackJs: '   ');
      expect(service.canRunSourceCallback(source), isFalse);
      final r = await _run(service, source, 'clickCustomButton');
      expect(r.runDefault, isTrue);
    });

    test('eventListener + callBackJs 齐全：可执行', () async {
      final PluginConfig source = _sourceOf(callBackJs: '"true"');
      expect(service.canRunSourceCallback(source), isTrue);
      final r = await _run(service, source, 'clickCustomButton');
      expect(r.runDefault, isFalse);
      expect(r.value, 'true');
    });

    test('非书源配置：不可执行', () {
      const PluginConfig plain = PluginConfig(
        id: 'plain',
        name: 'plain',
        type: SourceType.novelSource,
        site: SiteConfig(
          domain: 'plain.example',
          baseUrl: 'http://plain.example',
        ),
        parser: ParserConfig(type: 'builtin'),
      );
      expect(service.canRunSourceCallback(plain), isFalse);
    });

    test('customButton 显隐开关（md3 BookSource.customButton）', () {
      expect(shuyuanHasCustomButton(_sourceOf(customButton: true)), isTrue);
      expect(shuyuanHasCustomButton(_sourceOf()), isFalse);
      expect(shuyuanHasEventListener(_sourceOf()), isTrue);
      expect(
        shuyuanHasEventListener(_sourceOf(eventListener: false)),
        isFalse,
      );
    });
  });

  group('返回值口径（md3 String?.isTrue）', () {
    final Map<String, bool> cases = <String, bool>{
      "''": true,
      "'null'": true,
      "'false'": true,
      "'FALSE'": true,
      "'no'": true,
      "'not'": true,
      "'0'": true,
      "'0.0'": true,
      '0': true,
      "'' + Math.round(0.0)": true,
      "'true'": false,
      "'1'": false,
      "'0.1'": false,
      "'yes'": false,
      "' paid '": false,
      'true': false,
      'null': true,
      'undefined': true,
    };
    cases.forEach((String js, bool runDefault) {
      test('返回 $js → runDefault=$runDefault', () async {
        final PluginConfig source = _sourceOf(callBackJs: js);
        final r = await _run(service, source, 'clickCustomButton');
        expect(r.runDefault, runDefault, reason: js);
        expect(r.error, isNull, reason: js);
      });
    });
  });

  group('脚本异常（md3 只记日志，默认动作不执行）', () {
    test('运行期异常：error 非空且 runDefault=false', () async {
      final r = await _run(
        service,
        _sourceOf(callBackJs: 'throw new Error("boom")'),
        'clickCustomButton',
      );
      expect(r.error, contains('boom'));
      expect(r.runDefault, isFalse);
      expect(r.value, '');
    });

    test('语法错误：error 非空且 runDefault=false', () async {
      final r = await _run(
        service,
        _sourceOf(callBackJs: 'var x = ;'),
        'clickCustomButton',
      );
      expect(r.error, isNotNull);
      expect(r.runDefault, isFalse);
    });
  });

  group('事件绑定', () {
    test('event 变量为当前事件名', () async {
      final r = await _run(
        service,
        _sourceOf(callBackJs: 'event'),
        'longClickCustomButton',
      );
      expect(r.value, 'longClickCustomButton');
    });

    test('result 变量透传（CopyBookUrl/CopyPlayUrl 的默认文本）', () async {
      final r = await _run(
        service,
        _sourceOf(callBackJs: 'result + "#" + event'),
        'clickCopyBookUrl',
        result: '$_origin/book/1',
      );
      expect(r.value, '$_origin/book/1#clickCopyBookUrl');
    });

    test('book/chapter 绑定含阅读上下文与 VIP 标记', () async {
      final r = await _run(
        service,
        _sourceOf(
          callBackJs:
              '[event, book.name, book.bookUrl, chapter.title, chapter.url, '
              'chapter.index, chapter.isVip, chapter.isPay].join("|")',
        ),
        'saveRead',
        chapterUrl: '$_origin/c/7.html',
      );
      expect(
        r.value,
        'saveRead|合成书|$_origin/book/1|第七章|$_origin/c/7.html|6|true|false',
      );
    });

    test('book.author 由调用方透传', () async {
      final r = await service.runSourceCallback(
        _sourceOf(callBackJs: 'book.author'),
        'addBookShelf',
        bookUrl: '$_origin/book/2',
        bookName: '合成书',
        author: '合成作者',
      );
      expect(r.value, '合成作者');
    });
  });

  group('宿主动作队列', () {
    test('java.open 记录登录/搜索/发现请求（含 origin）', () async {
      final r = await _run(
        service,
        _sourceOf(
          callBackJs: 'java.open("login"); '
              'java.open("search", "关键词", "标题", "$_origin"); '
              'java.open("explore", "$_origin/e", "发现"); '
              '"done"',
        ),
        'clickCustomButton',
      );
      expect(r.value, 'done');
      expect(r.openRequests, hasLength(3));
      expect(r.openRequests[0]['name'], 'login');
      expect(r.openRequests[0]['url'], '');
      expect(r.openRequests[1]['name'], 'search');
      expect(r.openRequests[1]['url'], '关键词');
      expect(r.openRequests[1]['title'], '标题');
      expect(r.openRequests[1]['origin'], _origin);
      expect(r.openRequests[2]['name'], 'explore');
      expect(r.openRequests[2]['url'], '$_origin/e');
      expect(r.openRequests[2]['title'], '发现');
      expect(r.openRequests[2]['origin'], '', reason: 'origin 缺省为空，宿主回退当前源');
    });

    test('java.copyText 按调用顺序收集', () async {
      final r = await _run(
        service,
        _sourceOf(callBackJs: 'java.copyText("甲"); java.copyText("乙"); "false"'),
        'clickCustomButton',
      );
      expect(r.copiedTexts, <String>['甲', '乙']);
      expect(r.runDefault, isTrue);
    });

    test('java.putConcurrent 生效到限速器（key=书源 URL）', () async {
      final r = await _run(
        service,
        _sourceOf(
          callBackJs: 'java.putConcurrent("5/1000"); '
              'java.getKey()',
        ),
        'clickCustomButton',
      );
      expect(r.value, _origin);
      expect(
        ConcurrentRateLimiter.effectiveRate(null, _origin),
        '5/1000',
      );
    });
  });

  group('CopyTocUrl 的 result 由书对象补齐', () {
    test('详情解析后 tocUrl 回填到回调 result', () async {
      final (server, origin) = await startServer(<String, String>{
        '/book/9.html':
            '<h1>合成书</h1><a class="toc" href="/toc/9.html">目录</a>',
      });
      final PluginConfig source = _sourceOf(
        callBackJs: 'result',
        bookInfo: <String, dynamic>{
          'name': 'h1@text',
          'tocUrl': 'a.toc@href',
        },
      );
      final detailUrl = '$origin/book/9.html';
      final item = await service.fetchDetail(source, detailUrl);
      expect(item.extra?['tocUrl'], isNotEmpty,
          reason: '详情条目需透传 tocUrl 供默认动作使用');

      final r = await service.runSourceCallback(
        source,
        'clickCopyTocUrl',
        bookUrl: detailUrl,
        bookName: item.title,
      );
      expect(r.tocUrl, isNotEmpty);
      expect(r.tocUrl, endsWith('/toc/9.html'));
      expect(r.value, r.tocUrl);
      await server.close(force: true);
    });

    test('无缓存书的 tocUrl 为空', () async {
      final r = await _run(
        service,
        _sourceOf(callBackJs: 'result'),
        'clickCopyTocUrl',
        bookUrl: '$_origin/book/unknown',
      );
      expect(r.tocUrl, isEmpty);
      expect(r.runDefault, isTrue);
    });
  });

  group('脚本可读源身份', () {
    test('java.getKey 返回书源 URL', () async {
      final r = await _run(
        service,
        _sourceOf(callBackJs: 'java.getKey()'),
        'clickCustomButton',
      );
      expect(r.value, _origin);
    });
  });
}
