/// 动态发现页（远端 jsLib + importScript）重放恢复回归。
///
/// 对齐 legado 三处语义：
/// 1. `SharedJsScope`：jsLib 下载失败不缓存 scope，后续 eval/下次展开重试；
/// 2. `JsExtensions.importScript`：内容为空/获取失败抛错，脚本中断呈现错误态，
///    不产生“成功但零分类”的结果；
/// 3. `exploreKinds` 的 ACache 只接受非空解析结果（空白视为未命中重跑）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/explore_kind.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/presentation/shuyuan_novel_resolver.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';
import 'package:nexhub/features/shuyuan/shuyuan_explore_info_store.dart';
import 'package:nexhub/features/shuyuan/shuyuan_explore_kinds_store.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

late HttpServer _server;
late String _base;
var _libHealthy = true;
var _exploreHealthy = true;

const String _libJs = r'''
var original = {urls: ['https://a.example']};
function Reload(u) {
  return java.importScript(u);
}
function Get(k) {
  var v = JSON.parse(String(source.getVariable()));
  return v[k];
}
''';

const String _exploreJs = r'''
try {
  JSON.parse(source.getVariable());
} catch (e) {
  put(original);
}
var title = '分类-' + Get('urls').length;
JSON.stringify([{title: title, url: '/x'}]);
''';

Future<void> _startServer() async {
  _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  _base = 'http://${_server.address.host}:${_server.port}';
  _server.listen((req) {
    final body = switch (req.uri.path) {
      '/lib.js' => _libHealthy ? _libJs : '',
      '/explore.js' => _exploreHealthy ? _exploreJs : '',
      _ => null,
    };
    if (body != null) {
      req.response
        ..statusCode = 200
        ..headers.contentType =
            ContentType('application', 'javascript', charset: 'utf-8')
        ..add(utf8.encode(body));
    } else {
      req.response.statusCode = 404;
    }
    req.response.close();
  });
}

PluginConfig _source(String name) =>
    ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(<String, dynamic>{
      'bookSourceName': name,
      'bookSourceUrl': '$_base/site/',
      'bookSourceType': 0,
      'enabled': true,
      'jsLib': '{"main":"$_base/lib.js"}',
      'exploreUrl': '<js>\n'
          "eval(String(Reload('$_base/explore.js')));\n"
          '</js>',
    }));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  setUp(() async {
    HttpOverrides.global = null;
    JsEngine.resetPoolForTest();
    ShuyuanExploreInfoStore.resetCacheForTest();
    ShuyuanExploreKindsStore.resetCacheForTest();
    _libHealthy = true;
    _exploreHealthy = true;
    await _startServer();
  });

  tearDown(() => _server.close(force: true));

  test('jsLib 下载为空不固化：恢复后下次展开重新下载并解析', () async {
    _libHealthy = false;
    final cfg = _source('jsLib 失败恢复测试源');
    final resolver = ShuyuanNovelResolver();
    final first = await resolver.resolveExploreKinds(cfg);
    expect(first.items, isEmpty);
    expect(first.error, isNotNull);

    _libHealthy = true;
    final second = await resolver.resolveExploreKinds(cfg);
    expect(second.error, isNull);
    expect(second.items.map((e) => e.kind.title).toList(), <String>['分类-1']);
  });

  test('importScript 取回空内容视为失败：不缓存空分类，恢复后重算', () async {
    _exploreHealthy = false;
    final cfg = _source('importScript 空内容恢复测试源');
    final resolver = ShuyuanNovelResolver();
    final first = await resolver.resolveExploreKinds(cfg);
    expect(first.items, isEmpty);
    expect(first.error, isNotNull,
        reason: '空脚本内容必须呈现错误态，而不是成功零分类');

    _exploreHealthy = true;
    final second = await resolver.resolveExploreKinds(cfg);
    expect(second.error, isNull);
    expect(second.items.map((e) => e.kind.title).toList(), <String>['分类-1']);
  });

  test('空发现分类不写入持久缓存（空白缓存视为未命中）', () async {
    await ShuyuanExploreKindsStore.save('k', 'rule', const <ExploreKind>[]);
    final loaded = await ShuyuanExploreKindsStore.load('k', exploreUrl: 'rule');
    expect(loaded, isNull);
  });
}
