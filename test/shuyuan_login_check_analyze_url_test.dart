/// loginCheckJs 的 AnalyzeUrl 门面（legado WebBook：`res = analyzeUrl.evalJS
/// (checkJs, res)`）：检查脚本内 `java.getStrResponse()` 重取当前地址并以其
/// 响应替换结果、`java.headerMap.put` 参与重取、`java.initUrl()` 重新解析
/// URL 模板、返回 code==500 判定未登录；重取走确定性重放且不递归执行检查。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_url.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';

late HttpServer _server;
late String _origin;
final List<String> _hits = <String>[];
final List<String> _tokens = <String>[];
// /wall：首次返回墙页，之后返回真实页
int _wallHits = 0;

Future<void> _startServer() async {
  _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  _origin = 'http://${_server.address.address}:${_server.port}';
  _server.listen((req) {
    final path = req.uri.path;
    _hits.add('$path${req.uri.hasQuery ? '?${req.uri.query}' : ''}');
    _tokens.add(req.headers.value('x-token') ?? '');
    String body;
    switch (path) {
      case '/wall':
        _wallHits++;
        body = _wallHits == 1 ? '<html>请先登录</html>' : '<html>REAL</html>';
      case '/token':
        body = req.headers.value('x-token') == 'abc123'
            ? '<html>REAL</html>'
            : '<html>请先登录</html>';
      case '/api':
        body = req.uri.queryParameters['n'] == '2'
            ? '<html>REAL</html>'
            : '<html>请先登录</html>';
      case '/always-wall':
        body = '<html>请先登录</html>';
      default:
        body = '<html>REAL</html>';
    }
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write(body);
    req.response.close();
  });
}

XiaoshuoBookSource _source(String checkJs) => XiaoshuoBookSource(
      bookSourceUrl: '$_origin/',
      bookSourceName: '本地登录检查源',
      loginCheckJs: checkJs,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  setUp(() async {
    HttpOverrides.global = null;
    ShuyuanSourceContext.resetForTest();
    JsEngine.resetPoolForTest();
    _hits.clear();
    _tokens.clear();
    _wallHits = 0;
    await _startServer();
  });

  tearDown(() => _server.close(force: true));

  test('检查脚本 java.getStrResponse() 重取当前地址并替换响应体', () async {
    final src = _source(r'''
if (/请先登录/.test(result.body())) {
  result = java.getStrResponse();
}
result;
''');
    final ctx = await ShuyuanSourceContext.forSource('lc-refetch');
    final body = await ShuyuanSourceContext.run(
        ctx,
        () => AnalyzeUrl(
              url: '$_origin/wall',
              baseUrl: src.bookSourceUrl,
              source: src,
            ).getStrResponse());
    expect(body, contains('REAL'));
    // 首取 + 一次重取，恰好 2 次请求
    expect(_hits.length, 2);
  });

  test('java.headerMap.put 的请求头参与重取请求', () async {
    final src = _source(r'''
if (!/REAL/.test(result.body())) {
  java.headerMap.put('X-Token', 'abc123');
  result = java.getStrResponse();
}
result;
''');
    final ctx = await ShuyuanSourceContext.forSource('lc-headers');
    final body = await ShuyuanSourceContext.run(
        ctx,
        () => AnalyzeUrl(
              url: '$_origin/token',
              baseUrl: src.bookSourceUrl,
              source: src,
            ).getStrResponse());
    expect(body, contains('REAL'));
    expect(_hits.length, 2);
    expect(_tokens.first, '');
    expect(_tokens.last, 'abc123');
  });

  test('java.initUrl() 按模板重新求值后再重取', () async {
    final src = _source(r'''
if (/请先登录/.test(result.body())) {
  java.initUrl();
  result = java.getStrResponse();
}
result;
''');
    final ctx = await ShuyuanSourceContext.forSource('lc-initurl');
    // 模板 @js 每次求值自增 nonce：构造时 n=1，initUrl 重解析后 n=2。
    final au = AnalyzeUrl(
      url: '$_origin/api?n=@js:result + '
          '((globalThis.__nonce = (globalThis.__nonce || 0) + 1))',
      baseUrl: src.bookSourceUrl,
      source: src,
    );
    expect(au.url, '$_origin/api?n=1');
    final body =
        await ShuyuanSourceContext.run(ctx, () => au.getStrResponse());
    expect(body, contains('REAL'));
    expect(au.ruleUrl, '$_origin/api?n=2');
    expect(_hits, ['/api?n=1', '/api?n=2']);
  });

  test('检查脚本返回 500 判定未登录', () async {
    final src = _source(r'''
/请先登录/.test(result.body()) ? 500 : 200
''');
    final ctx = await ShuyuanSourceContext.forSource('lc-code500');
    await expectLater(
      ShuyuanSourceContext.run(
          ctx,
          () => AnalyzeUrl(
                url: '$_origin/always-wall',
                baseUrl: src.bookSourceUrl,
                source: src,
              ).getStrResponse()),
      throwsA(isA<ShuyuanLoginRequiredException>()),
    );
  });

  test('重取不递归执行 loginCheckJs（请求数有界）', () async {
    final src = _source(r'''
if (/请先登录/.test(result.body())) {
  result = java.getStrResponse();
}
result;
''');
    final ctx = await ShuyuanSourceContext.forSource('lc-no-recurse');
    final body = await ShuyuanSourceContext.run(
        ctx,
        () => AnalyzeUrl(
              url: '$_origin/always-wall',
              baseUrl: src.bookSourceUrl,
              source: src,
            ).getStrResponse());
    expect(body, contains('请先登录'));
    expect(_hits.length, 2);
  });
}
