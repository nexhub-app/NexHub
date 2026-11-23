/// 第三轮 P1（N1–N7）回归：
/// N1 cache TTL/持久化、N2 refreshJSLib 重执行、N3 enabledCookieJar 总闸、
/// N4 POST 结构化体 Content-Type、N5 WebView 纳入限流、
/// N6 选项头覆盖登录头、N7 非 2xx 正文保留。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexhub/core/scraper/verification_detector.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_url.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/analyze/webview_fetcher.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';

Future<HttpServer> _startServer(
    Future<void> Function(HttpRequest req) handler) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) {
    handler(req);
  });
  return server;
}

String _origin(HttpServer server) =>
    'http://${server.address.address}:${server.port}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  setUp(() {
    HttpOverrides.global = null;
    ShuyuanSourceContext.resetForTest();
    ShuyuanWebviewFetcher.debugFetchOverride = null;
  });
  tearDown(() => ShuyuanWebviewFetcher.debugFetchOverride = null);

  group('N1 cache.put 持久化与 saveTime TTL', () {
    test('cache.put 带 saveTime 落持久通道，forSource 重载可读', () async {
      final ctx = ShuyuanSourceContext('p1-cache-persist');
      final engine = JsEngine();
      ShuyuanSourceContext.run(ctx, () {
        engine.eval("cache.put('tok', 'v1', 300);");
      });
      await ctx.persistIfNeeded();

      final reloaded =
          await ShuyuanSourceContext.forSource('p1-cache-persist');
      expect(reloaded.cache['tok'], 'v1');
      final e2 = JsEngine();
      expect(
        ShuyuanSourceContext.run(reloaded, () => e2.eval("cache.get('tok')")),
        'v1',
      );
    });

    test('saveTime 到期后 cache.get 返回 null，新上下文同样剔除', () async {
      final ctx = ShuyuanSourceContext('p1-cache-expire');
      final engine = JsEngine();
      ShuyuanSourceContext.run(ctx, () {
        engine.eval(
            "cache.put('t', 'v', 1); cache.put('keep', 'k', 300);");
      });
      await ctx.persistIfNeeded();
      await Future<void>.delayed(const Duration(milliseconds: 1100));

      final e2 = JsEngine();
      expect(
        ShuyuanSourceContext.run(
            ctx, () => e2.eval("cache.get('t') === null ? 'NULL' : 'HIT'")),
        'NULL',
      );
      expect(
        ShuyuanSourceContext.run(ctx, () => e2.eval("cache.get('keep')")),
        'k',
      );
      final reloaded =
          await ShuyuanSourceContext.forSource('p1-cache-expire');
      expect(reloaded.cache.containsKey('t'), isFalse);
      expect(reloaded.cache['keep'], 'k');
    });
  });

  group('N2 refreshJSLib', () {
    test('source.refreshJSLib() 后下一轮重新执行 jsLib', () {
      final ctx = ShuyuanSourceContext('p1-js-lib-refresh')
        ..bindSource(XiaoshuoBookSource(
          bookSourceUrl: 'https://lib-refresh.test',
          bookSourceName: 'lib-refresh',
          jsLib: "var __libLoads = "
              "(typeof __libLoads === 'undefined' ? 0 : __libLoads) + 1;",
        ));
      final engine = JsEngine();
      expect(
          ShuyuanSourceContext.run(ctx, () => engine.eval('__libLoads')), '1');
      expect(
          ShuyuanSourceContext.run(ctx, () => engine.eval('__libLoads')), '1');
      expect(
        ShuyuanSourceContext.run(
            ctx, () => engine.eval('source.refreshJSLib()')),
        'true',
      );
      expect(
          ShuyuanSourceContext.run(ctx, () => engine.eval('__libLoads')), '2');
    });
  });

  group('N3 enabledCookieJar 总闸', () {
    late HttpServer server;
    late String origin;
    var seenCookie = '';

    setUp(() async {
      seenCookie = '';
      server = await _startServer((req) async {
        seenCookie = req.headers.value('cookie') ?? '';
        req.response.headers.add('set-cookie', 'srv=1; Path=/');
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write('<html>ok</html>');
        req.response.close();
      });
      origin = _origin(server);
    });
    tearDown(() => server.close(force: true));

    test('关罐：覆盖层不发送、响应 Set-Cookie 不吸收', () async {
      final src = XiaoshuoBookSource(
        bookSourceUrl: origin,
        bookSourceName: 'jar-off',
        enabledCookieJar: false,
      );
      final ctx = await ShuyuanSourceContext.forSource('p1-jar-off')
        ..bindSource(src);
      ctx.cookies['me'] = <String, String>{'value': '1', 'host': '127.0.0.1'};
      final out = await ShuyuanSourceContext.run(
        ctx,
        () => AnalyzeUrl(url: '$origin/x', baseUrl: origin, source: src)
            .getStrResponse(),
      );
      expect(out, contains('ok'));
      expect(seenCookie, isNot(contains('me=1')));
      expect(ctx.cookies.containsKey('srv'), isFalse);
    });

    test('开罐：覆盖层照常发送、响应 Set-Cookie 吸收', () async {
      final src = XiaoshuoBookSource(
        bookSourceUrl: origin,
        bookSourceName: 'jar-on',
      );
      final ctx = await ShuyuanSourceContext.forSource('p1-jar-on')
        ..bindSource(src);
      ctx.cookies['me'] = <String, String>{'value': '1', 'host': '127.0.0.1'};
      await ShuyuanSourceContext.run(
        ctx,
        () => AnalyzeUrl(url: '$origin/x', baseUrl: origin, source: src)
            .getStrResponse(),
      );
      expect(seenCookie, contains('me=1'));
      expect(ctx.cookies['srv']?['value'], '1');
    });

    test('WebView 回写受总闸控制', () async {
      ShuyuanWebviewFetcher.debugFetchOverride = ({
        String? html,
        String? url,
        String? js,
        int delayMs = 0,
        Map<String, String>? headers,
        String? sourceRegex,
        String? overrideUrlRegex,
      }) async {
        return const ShuyuanWebviewResult(
          html: '<div>ok</div>',
          finalUrl: 'https://wv-jar.test/p',
          cookieHeaders: <String, String>{'wv-jar.test': 'sid=xyz'},
        );
      };
      final src = XiaoshuoBookSource.fromJson(<String, dynamic>{
        'bookSourceUrl': 'https://wv-jar.test',
        'bookSourceName': 'wv-jar',
        'bookSourceType': 0,
        'enabledCookieJar': false,
      });
      final ctx = ShuyuanSourceContext('p1-jar-wv-off')..bindSource(src);
      await ShuyuanSourceContext.run(ctx, () async {
        final a = AnalyzeUrl(
          url: 'https://wv-jar.test/p',
          baseUrl: 'https://wv-jar.test',
          source: src,
        );
        a.useWebView = true;
        await a.getStrResponse();
      });
      expect(ctx.cookies.containsKey('sid'), isFalse);
    });
  });

  group('N4 POST 结构化体 Content-Type', () {
    test('JSON 对象/数组补 legado postJson 头（application/json; charset=UTF-8）',
        () {
      final obj = AnalyzeUrl(
        url: 'http://h.test/api,{"method":"POST","body":"{\\"a\\":1}"}',
        baseUrl: 'http://h.test/',
      );
      expect(obj.headerMap['Content-Type'], 'application/json; charset=UTF-8');
      final arr = AnalyzeUrl(
        url: 'http://h.test/api,{"method":"POST","body":"[1,2]"}',
        baseUrl: 'http://h.test/',
      );
      expect(arr.headerMap['Content-Type'], 'application/json; charset=UTF-8');
    });
  });

  group('N5 WebView 纳入限流', () {
    test('webView 分支受 concurrentRate 限速', () async {
      final starts = <DateTime>[];
      ShuyuanWebviewFetcher.debugFetchOverride = ({
        String? html,
        String? url,
        String? js,
        int delayMs = 0,
        Map<String, String>? headers,
        String? sourceRegex,
        String? overrideUrlRegex,
      }) async {
        starts.add(DateTime.now());
        return const ShuyuanWebviewResult(
            html: '<div>ok</div>', finalUrl: '');
      };
      final src = XiaoshuoBookSource.fromJson(<String, dynamic>{
        'bookSourceUrl': 'https://wv-rate-p1.test',
        'bookSourceName': 'wv-rate',
        'bookSourceType': 0,
        'concurrentRate': '1/250',
      });
      final ctx = ShuyuanSourceContext('p1-wv-rate');
      await ShuyuanSourceContext.run(ctx, () async {
        for (var i = 0; i < 2; i++) {
          final a = AnalyzeUrl(
            url: 'https://wv-rate-p1.test/p$i',
            baseUrl: 'https://wv-rate-p1.test',
            source: src,
          );
          a.useWebView = true;
          await a.getStrResponse();
        }
      });
      expect(starts, hasLength(2));
      expect(
        starts[1].difference(starts[0]).inMilliseconds,
        greaterThanOrEqualTo(200),
      );
    });
  });

  group('N6 loginHeader 与选项头次序', () {
    test('HTTP：选项头覆盖登录头，显式 headers 最后', () async {
      final captured = <String, String>{};
      final server = await _startServer((req) async {
        req.headers.forEach((k, v) => captured[k.toLowerCase()] = v.join(','));
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write('OK');
        req.response.close();
      });
      final origin = _origin(server);
      try {
        final src = XiaoshuoBookSource.fromJson(<String, dynamic>{
          'bookSourceUrl': origin,
          'bookSourceName': 'order-http',
          'header': 'X-Source: src',
        });
        final ctx = ShuyuanSourceContext('p1-order-http')..bindSource(src);
        ctx.loginHeader
          ..clear()
          ..addAll(<String, String>{'X-Shared': 'login', 'X-Login': 'yes'});
        final a = AnalyzeUrl(
          url: '$origin/o,{"headers":{"X-Shared":"option"}}',
          baseUrl: origin,
          source: src,
        );
        expect(await ShuyuanSourceContext.run(ctx, () => a.getStrResponse()),
            'OK');
        expect(captured['x-shared'], 'option');
        expect(captured['x-login'], 'yes');
        expect(captured['x-source'], 'src');

        final resolved =
            ShuyuanSourceContext.run(ctx, () => a.resolveRequestHeaders());
        expect(resolved['X-Shared'], 'option');
        expect(resolved['X-Login'], 'yes');
      } finally {
        await server.close(force: true);
      }
    });

    test('WebView：选项头覆盖登录头', () async {
      Map<String, String>? seen;
      ShuyuanWebviewFetcher.debugFetchOverride = ({
        String? html,
        String? url,
        String? js,
        int delayMs = 0,
        Map<String, String>? headers,
        String? sourceRegex,
        String? overrideUrlRegex,
      }) async {
        seen = headers;
        return const ShuyuanWebviewResult(
            html: '<div>ok</div>', finalUrl: '');
      };
      final src = XiaoshuoBookSource.fromJson(<String, dynamic>{
        'bookSourceUrl': 'https://order-wv.test',
        'bookSourceName': 'order-wv',
        'bookSourceType': 0,
      });
      final ctx = ShuyuanSourceContext('p1-order-wv')..bindSource(src);
      ctx.loginHeader['X-Shared'] = 'login';
      await ShuyuanSourceContext.run(ctx, () async {
        final a = AnalyzeUrl(
          url: 'https://order-wv.test/p,{"headers":{"X-Shared":"option"}}',
          baseUrl: 'https://order-wv.test',
          source: src,
        );
        a.useWebView = true;
        await a.getStrResponse();
      });
      expect(seen, isNotNull);
      expect(seen!['X-Shared'], 'option');
    });
  });

  group('N7 非 2xx 响应体保留', () {
    test('404 响应体返回给解析并记录状态码', () async {
      final server = await _startServer((req) async {
        req.response
          ..statusCode = 404
          ..headers.contentType = ContentType.html
          ..write('<html><p>正文-not-found</p></html>');
        req.response.close();
      });
      try {
        final origin = _origin(server);
        final au = AnalyzeUrl(url: '$origin/nf', baseUrl: origin);
        final body = await au.getStrResponse();
        expect(body, contains('正文-not-found'));
        expect(au.lastStatusCode, 404);
      } finally {
        await server.close(force: true);
      }
    });

    test('空体 500 仍抛出（无正文可用）', () async {
      final server = await _startServer((req) async {
        req.response
          ..statusCode = 500
          ..headers.contentType = ContentType.html;
        req.response.close();
      });
      try {
        final origin = _origin(server);
        final au = AnalyzeUrl(url: '$origin/err', baseUrl: origin);
        await expectLater(au.getStrResponse(), throwsA(isA<Exception>()));
      } finally {
        await server.close(force: true);
      }
    });

    test('403 仍走验证异常（不把挑战页当正文）', () async {
      final server = await _startServer((req) async {
        req.response
          ..statusCode = 403
          ..headers.contentType = ContentType.html
          ..write('<html>forbidden</html>');
        req.response.close();
      });
      try {
        final origin = _origin(server);
        final au = AnalyzeUrl(url: '$origin/no', baseUrl: origin);
        await expectLater(au.getStrResponse(),
            throwsA(isA<VerificationRequiredException>()));
      } finally {
        await server.close(force: true);
      }
    });
  });
}
