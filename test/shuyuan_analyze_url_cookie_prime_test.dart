/// HTTP 412 反爬风控的通用 Cookie 预处理（对齐浏览器/legado 会话建立方式）：
/// 部分站点的内容接口在缺少站点会话 Cookie 时固定返回 412，而该 Cookie 由
/// 站点首页 `Set-Cookie` 下发。请求方在 412 后先访问站点根域取种子 Cookie，
/// 再原请求重试一次；同一上下文同一站点只做一次，失败不循环。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_url.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';

late HttpServer _server;
late String _origin;
int _homeHits = 0;
int _listHits = 0;
bool _homeSetsCookie = true;

Future<void> _startServer() async {
  _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  _origin = 'http://${_server.address.address}:${_server.port}';
  _server.listen((req) {
    final path = req.uri.path;
    if (path == '/') {
      _homeHits++;
      if (_homeSetsCookie) {
        req.response.headers.add('set-cookie', 'sid=ok; Path=/');
      }
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write('<html>home</html>');
      req.response.close();
      return;
    }
    _listHits++;
    final cookie = req.headers.value('cookie') ?? '';
    if (cookie.contains('sid=ok')) {
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write('{"items":["ok"]}');
    } else {
      req.response
        ..statusCode = 412
        ..headers.contentType = ContentType.html
        ..write('<html>precondition failed</html>');
    }
    req.response.close();
  });
}

XiaoshuoBookSource _source({bool cookieJar = true}) => XiaoshuoBookSource(
      bookSourceUrl: '$_origin/',
      bookSourceName: '本地 412 会话源',
      enabledCookieJar: cookieJar,
    );

Future<String> _fetch(XiaoshuoBookSource src) {
  return AnalyzeUrl(url: '$_origin/api/list', baseUrl: src.bookSourceUrl, source: src)
      .getStrResponse();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  setUp(() async {
    HttpOverrides.global = null;
    ShuyuanSourceContext.resetForTest();
    _homeHits = 0;
    _listHits = 0;
    _homeSetsCookie = true;
    await _startServer();
  });

  tearDown(() => _server.close(force: true));

  test('412 后访问根域取 Cookie，再重试原请求成功', () async {
    final src = _source();
    final ctx = await ShuyuanSourceContext.forSource('cookie-prime-ok');
    final body = await ShuyuanSourceContext.run(ctx, () => _fetch(src));
    expect(body, contains('"ok"'));
    expect(_homeHits, 1);
    expect(_listHits, 2);
  });

  test('种子 Cookie 持久生效，后续请求不再访问根域、不再吃 412', () async {
    final src = _source();
    final ctx = await ShuyuanSourceContext.forSource('cookie-prime-reuse');
    await ShuyuanSourceContext.run(ctx, () => _fetch(src));
    final body = await ShuyuanSourceContext.run(ctx, () => _fetch(src));
    expect(body, contains('"ok"'));
    expect(_homeHits, 1);
    expect(_listHits, 3);
  });

  test('源声明不启用 cookieJar 时不做根域预处理', () async {
    final src = _source(cookieJar: false);
    final ctx = await ShuyuanSourceContext.forSource('cookie-prime-off');
    await expectLater(
      ShuyuanSourceContext.run(ctx, () => _fetch(src)),
      throwsA(isA<Exception>()),
    );
    expect(_homeHits, 0);
    expect(_listHits, 1);
  });

  test('根域未下发 Cookie 时只重试一次即失败，不循环', () async {
    _homeSetsCookie = false;
    final src = _source();
    final ctx = await ShuyuanSourceContext.forSource('cookie-prime-empty');
    await expectLater(
      ShuyuanSourceContext.run(ctx, () => _fetch(src)),
      throwsA(isA<Exception>()),
    );
    expect(_homeHits, 1);
    expect(_listHits, 1);
  });
}
