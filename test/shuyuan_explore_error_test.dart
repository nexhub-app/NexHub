/// 发现脚本错误可见性：失败不能伪装成「该源无发现页」。
///
/// legado `exploreKinds()` 在脚本异常时生成可见的 ERROR 项；NexHub 的
/// 旧实现把 JS 异常吞成空串，面板只显示「无发现页」。测试覆盖：
/// - 占位符（java.ajax 首轮）导致的 SyntaxError 不应中止重放；
/// - settle 后仍失败 → ExploreKindsResult.error 非空；
/// - 脚本正常返回空列表 → 不是错误。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/presentation/shuyuan_novel_resolver.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';
import 'package:nexhub/features/shuyuan/shuyuan_explore_info_store.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

late HttpServer _server;
late String _base;

Future<void> _startServer() async {
  _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  _base = 'http://${_server.address.host}:${_server.port}';
  _server.listen((req) {
    final body = req.uri.path.endsWith('/ok.json')
        ? '[{"title":"分类A","url":"/a"}]'
        : '';
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(body);
    req.response.close();
  });
}

PluginConfig _config(String exploreUrl, {String path = 's1'}) {
  return ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(<String, dynamic>{
    'bookSourceName': '本地发现错误测试源$path',
    'bookSourceUrl': '$_base/$path/',
    'bookSourceType': 0,
    'enabled': true,
    'exploreUrl': exploreUrl,
  }));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  setUp(() async {
    HttpOverrides.global = null;
    JsEngine.resetPoolForTest();
    ShuyuanExploreInfoStore.resetCacheForTest();
    await _startServer();
  });

  tearDown(() => _server.close(force: true));

  test('脚本异常 → error 非空（不再是 items=[] error=null）', () async {
    final result = await ShuyuanNovelResolver()
        .resolveExploreKinds(_config('@js:notAFunction();'));
    expect(result.items, isEmpty);
    expect(result.error, isNotNull);
  });

  test('ajax 占位符 SyntaxError 不中止重放，真实响应到达后正常出分类', () async {
    final result = await ShuyuanNovelResolver().resolveExploreKinds(
      _config(
        "@js:JSON.parse(java.ajax(baseUrl + 'ok.json'))",
        path: 's2',
      ),
    );
    expect(result.error, isNull);
    expect(result.items.map((e) => e.displayName).toList(), <String>['分类A']);
  });

  test('settle 后仍失败（空响应）→ error 非空', () async {
    final result = await ShuyuanNovelResolver().resolveExploreKinds(
      _config(
        "@js:JSON.parse(java.ajax(baseUrl + 'missing.json'))",
        path: 's3',
      ),
    );
    expect(result.items, isEmpty);
    expect(result.error, isNotNull);
  });

  test('脚本正常返回空列表 → 不是错误', () async {
    final result = await ShuyuanNovelResolver()
        .resolveExploreKinds(_config('@js:JSON.stringify([])', path: 's4'));
    expect(result.items, isEmpty);
    expect(result.error, isNull);
  });
}
