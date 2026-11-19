/// 补数回放期间的反馈抑制：`java.ajax` 首轮占位符会让脚本走 catch
/// 提示分支，这些 toast 属于宿主补数的中间态；legado 的 ajax 是阻塞
/// 真实请求，不会出现该中间态，因此不应弹给用户。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/features/shuyuan/analyze/java_extensions.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
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
    final body =
        req.uri.path.endsWith('/ok.json') ? '[{"title":"分类A","url":"/a"}]' : '';
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(body);
    req.response.close();
  });
}

PluginConfig _config(String exploreUrl, {String path = 's1'}) {
  return ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(<String, dynamic>{
    'bookSourceName': '本地回放反馈测试源$path',
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
    ShuyuanSourceContext.resetForTest();
    await _startServer();
  });

  tearDown(() => _server.close(force: true));

  test('缓冲开启时 toast 不直接送达，flush 后统一送达', () {
    final seen = <String>[];
    JavaFeedback.onToast = (msg, {bool long = false}) => seen.add(msg);
    addTearDown(() => JavaFeedback.onToast = null);
    final ctx = ShuyuanSourceContext('src_feedback_1');
    ShuyuanSourceContext.run(ctx, () {
      ctx.deferFeedback = true;
      JsEngine().eval("java.toast('中间态')");
      expect(seen, isEmpty);
      expect(ctx.deferredToasts.map((t) => t.msg).toList(), <String>['中间态']);
      ctx.flushDeferredToasts();
    });
    expect(seen, <String>['中间态']);
  });

  test('中间轮（占位符导致 catch）的 toast 不弹给用户', () async {
    final seen = <String>[];
    JavaFeedback.onToast = (msg, {bool long = false}) => seen.add(msg);
    addTearDown(() => JavaFeedback.onToast = null);
    final result = await ShuyuanNovelResolver().resolveExploreKinds(
      _config(
        "@js:(function(){try{return JSON.parse(java.ajax(baseUrl + 'ok.json'))}"
        "catch(e){java.toast('占位中间态');return ''}})()",
        path: 's2',
      ),
    );
    expect(result.error, isNull);
    expect(result.items.map((e) => e.displayName).toList(), <String>['分类A']);
    expect(seen, isEmpty, reason: '首轮占位符引发的提示属于补数中间态');
  });

  test('最终轮真实失败时 toast 正常送达', () async {
    final seen = <String>[];
    JavaFeedback.onToast = (msg, {bool long = false}) => seen.add(msg);
    addTearDown(() => JavaFeedback.onToast = null);
    final result = await ShuyuanNovelResolver().resolveExploreKinds(
      _config(
        "@js:(function(){try{return JSON.parse(java.ajax(baseUrl + 'missing.json'))}"
        "catch(e){java.toast('真实失败');return ''}})()",
        path: 's3',
      ),
    );
    expect(result.error, isNull);
    expect(result.items, isEmpty);
    expect(seen, <String>['真实失败']);
  });
}
