/// 抖动词表的收敛回归：jsLib 签名用 `Math.random()`、请求 URL 带
/// `java.randomUUID()` 时，确定性重放必须跨轮复现同一 URL/签名。
///
/// legado 的桥是同步的：一次求值只发一次真实请求，随机数不参与重放。
/// NexHub 的占位符重放要求同一脚本的多轮求值产生相同请求键，否则缓存
/// 永不命中——发现页分类与多跳握手在轮次预算内失败（真机表现为选项栏
/// 展开「加载失败」）。这里用本地合成站点锁定：随机源按脚本定种、跨轮
/// 复现，同一求值内仍逐次推进。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/webview_fetcher.dart';
import 'package:nexhub/features/shuyuan/presentation/shuyuan_novel_resolver.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

late HttpServer _server;
late String _base;
var _headHits = 0;
var _apiHits = 0;
var _webviewHits = 0;
const String _signed = 'SIG-OK';

String _libJs() => 'type = "#t#";\n'
    'host = "$_base/";\n'
    'function Secret(e, t) {\n'
    '  return "<html>" + e + ":" + t + ":" + '
    'Math.floor(Math.random() * 1000000000) + "</html>";\n'
    '}\n';

const String _loginJs = r'''
try {
  var parts = String(java.hexDecodeToString(result)).split(type);
  var uri = parts[0], t1 = parts[1];
  headers = cache.get(type + 'Headers');
  if (headers == null) {
    headers = {'Referer': host};
    C = java.head(host + 'favicon.ico', headers).cookies();
    e = Object.keys(C)[0];
    headers.Cookie = e + '=' + C[e];
    headers.Secret = java.webView(Secret(e, C[e]), null, 'Secret');
    headers = JSON.stringify({headers: headers});
    cache.put(type + 'Headers', headers, 300);
  }
  if (t1 == '加载') {
    data = JSON.parse(java.ajax(
        host + 'api/menu?reqId=' + java.randomUUID() + ',' + headers)).data;
  }
  JSON.stringify(data);
} catch (err) {
  '';
}
''';

const String _exploreJs = r'''
eval(String(source.loginUrl));
result = java.hexEncodeToString('menu?' + type + '加载');
var data = eval(String(source.loginUrl));
var out = [];
JSON.parse(data).forEach(function (x) {
  out.push({title: x.name, url: '/c/' + x.name});
});
JSON.stringify(out);
''';

Future<void> _startServer() async {
  _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  _base = 'http://${_server.address.address}:${_server.port}';
  _server.listen((req) {
    final path = req.uri.path;
    if (path == '/favicon.ico') {
      _headHits++;
      req.response
        ..statusCode = 200
        ..headers.add('set-cookie', 'sid=abc; Path=/');
      req.response.close();
      return;
    }
    _apiHits++;
    final cookie = req.headers.value('cookie') ?? '';
    final secret = req.headers.value('secret') ?? '';
    if (path == '/api/menu' &&
        cookie.contains('sid=abc') &&
        secret == _signed) {
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(<String, dynamic>{
          'data': <Map<String, String>>[
            {'name': '分类甲'},
            {'name': '分类乙'},
          ],
        }));
    } else {
      req.response.statusCode = 401;
    }
    req.response.close();
  });
}

PluginConfig _source() =>
    ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(<String, dynamic>{
      'bookSourceName': '抖动收敛测试源',
      'bookSourceUrl': '$_base/site/',
      'bookSourceType': 0,
      'enabled': true,
      'jsLib': _libJs(),
      'loginUrl': _loginJs,
      'exploreUrl': '@js:\n$_exploreJs',
    }));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  setUp(() async {
    HttpOverrides.global = null;
    JsEngine.resetPoolForTest();
    _headHits = 0;
    _apiHits = 0;
    _webviewHits = 0;
    await _startServer();
    ShuyuanWebviewFetcher.debugFetchOverride = ({
      String? html,
      String? url,
      String? js,
      int delayMs = 0,
      Map<String, String>? headers,
    }) async {
      _webviewHits++;
      return ShuyuanWebviewResult(
        html: _signed,
        finalUrl: url ?? '',
        cookieHeaders: const <String, String>{},
      );
    };
  });

  tearDown(() async {
    ShuyuanWebviewFetcher.debugFetchOverride = null;
    await _server.close(force: true);
  });

  test('同一脚本跨次求值的随机序列可复现，单次求值内逐次推进', () {
    final engine = JsEngine();
    const probe = 'Math.random() + "|" + java.randomUUID()';
    final first = engine.eval(probe);
    final second = engine.eval(probe);
    expect(second, first, reason: '重放轮依赖同一脚本的随机序列稳定');

    final uuid = engine.eval('java.randomUUID()');
    expect(engine.eval('java.randomUUID()'), uuid);

    final seq = engine.eval(
        'var a = []; for (var i = 0; i < 3; i++) a.push(java.randomUUID());'
        'a.join("|")');
    expect(seq.split('|').toSet().length, 3, reason: '同轮内多次调用互不相同');
  });

  test('随机签名 + 随机请求 ID 的发现页在重放轮内收敛', () async {
    final cfg = _source();
    final resolver = ShuyuanNovelResolver();
    final result = await resolver.resolveExploreKinds(cfg);

    expect(result.error, isNull, reason: result.error);
    expect(
      result.items.map((e) => e.kind.title).toList(),
      <String>['分类甲', '分类乙'],
    );
    expect(_headHits, 1, reason: 'HEAD 只发一次（重放命中缓存）');
    // 头部缓存写入前后的两条路径各发一次，之后随机键稳定命中。
    expect(_apiHits, lessThanOrEqualTo(2),
        reason: '随机 reqId 必须跨轮复现，不能每轮新发请求');
    expect(_webviewHits, greaterThanOrEqualTo(2));
  });
}
