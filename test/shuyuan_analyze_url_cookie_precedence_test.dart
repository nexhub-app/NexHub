/// Cookie 优先级（对齐 legado `AnalyzeUrl.setCookie()`）：
/// «urlOption 临时 cookie > 数据库 cookie»。签名类书源把与 Cookie 绑定的
/// 签名头和当时的 Cookie 值一起写进 URL 选项；服务端响应会轮换会话 Cookie，
/// 若让轮换后的新值覆盖显式旧值，服务端按「签名与 Cookie 不一致」拒绝。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_url.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';

late HttpServer _server;
late String _origin;
String _lastCookie = '';

Future<void> _startServer() async {
  _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  _origin = 'http://${_server.address.address}:${_server.port}';
  _server.listen((req) {
    final path = req.uri.path;
    if (path == '/api/rotate') {
      req.response.headers.add('set-cookie', 'tok=NEW; Path=/');
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write('{"ok":1}');
      req.response.close();
      return;
    }
    _lastCookie = req.headers.value('cookie') ?? '';
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.text
      ..write(_lastCookie);
    req.response.close();
  });
}

XiaoshuoBookSource _source() => XiaoshuoBookSource(
      bookSourceUrl: '$_origin/',
      bookSourceName: '本地 Cookie 优先级源',
      enabledCookieJar: true,
    );

Future<String> _fetch(String url, XiaoshuoBookSource src) =>
    AnalyzeUrl(url: url, baseUrl: src.bookSourceUrl, source: src)
        .getStrResponse();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  setUp(() async {
    HttpOverrides.global = null;
    ShuyuanSourceContext.resetForTest();
    _lastCookie = '';
    await _startServer();
  });

  tearDown(() => _server.close(force: true));

  test('显式 Cookie 优先于覆盖层里轮换后的同名 Cookie', () async {
    final src = _source();
    final ctx = await ShuyuanSourceContext.forSource('cookie-precedence-1');
    await ShuyuanSourceContext.run(
        ctx, () => _fetch('$_origin/api/rotate', src));
    // 响应 Set-Cookie 已进入 per-source 覆盖层（tok=NEW）。
    final body = await ShuyuanSourceContext.run(
        ctx,
        () => _fetch(
            '$_origin/api/echo,{"headers":{"Cookie":"tok=OLD"}}', src));
    expect(body, 'tok=OLD');
    expect(_lastCookie, isNot(contains('tok=NEW')));
  });

  test('无显式 Cookie 时覆盖层 Cookie 正常带出', () async {
    final src = _source();
    final ctx = await ShuyuanSourceContext.forSource('cookie-precedence-2');
    await ShuyuanSourceContext.run(
        ctx, () => _fetch('$_origin/api/rotate', src));
    final body = await ShuyuanSourceContext.run(
        ctx, () => _fetch('$_origin/api/echo', src));
    expect(body, contains('tok=NEW'));
  });
}
