/// 远端 jsLib 省略「家族式」全局助手（put/login/name/n/k/l）时的兼容回归：
/// 部分书源的 loginUrl/exploreUrl 脚本直接调用这些助手（历史上由旧版
/// jsLib 提供），现行远端 jsLib 不再声明。缺失时脚本在登录数据初始化处
/// 抛 ReferenceError，源变量永不写入，发现页分类/选项解析为 0。
/// 兼容定义必须只在未定义时兜底，且 jsLib 自带实现始终优先。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/presentation/shuyuan_novel_resolver.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';
import 'package:nexhub/features/shuyuan/shuyuan_explore_info_store.dart';
import 'package:nexhub/features/shuyuan/shuyuan_explore_kinds_store.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

late HttpServer _server;
late String _base;

const String _libJs = r'''
function Reload(u) {
  return java.importScript(u);
}
function Get(k) {
  var raw = String(source.getVariable());
  if (!raw) { throw new Error('Get: source variable empty'); }
  var m = JSON.parse(raw);
  if (m[k] == null) { throw new Error('Get: missing ' + k); }
  return m[k];
}
''';

const String _loginJs = '''
try {
  var data = JSON.parse(String(source.getVariable()));
  if (data == null) { missing; }
} catch (e) {
  put({cat: '\u5206\u7c7b\u7532', urls: ['https://a.example']});
}
''';

Future<void> _startServer() async {
  _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  _base = 'http://${_server.address.host}:${_server.port}';
  _server.listen((req) {
    final path = req.uri.path;
    final body = switch (path) {
      '/lib.js' => _libJs,
      '/login.js' => _loginJs,
      _ => null,
    };
    if (body != null) {
      final bytes = utf8.encode(body);
      req.response
        ..statusCode = 200
        ..headers.contentType =
            ContentType('application', 'javascript', charset: 'utf-8')
        ..add(bytes);
    } else {
      req.response.statusCode = 404;
    }
    req.response.close();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  setUp(() async {
    HttpOverrides.global = null;
    JsEngine.resetPoolForTest();
    ShuyuanExploreInfoStore.resetCacheForTest();
    ShuyuanExploreKindsStore.resetCacheForTest();
    await _startServer();
  });

  tearDown(() => _server.close(force: true));

  test('远端 jsLib 缺省 put 时发现页仍能初始化源变量并产出分类', () async {
    final cfg = ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(<String, dynamic>{
      'bookSourceName': '本地家族助手兼容测试源',
      'bookSourceUrl': '$_base/site/',
      'bookSourceType': 0,
      'enabled': true,
      'jsLib': '{"main":"$_base/lib.js"}',
      'loginUrl': "eval(String(Reload('$_base/login.js')));",
      'exploreUrl': '<js>\n'
          "eval(String(source.loginUrl));\n"
          "var title = String(Get('cat'));\n"
          "JSON.stringify([{title: title, url: '/c1'}]);\n"
          '</js>',
      'ruleExplore': <String, dynamic>{
        'bookList': '#list li.item',
        'name': 'a@text',
        'bookUrl': 'a@href',
      },
    }));

    final resolver = ShuyuanNovelResolver();
    final cats = await resolver.resolveExploreCategories(cfg);
    expect(
      cats.map((c) => '${c.title}|${c.id}').toList(),
      <String>['分类甲|/c1'],
    );
  });
}
