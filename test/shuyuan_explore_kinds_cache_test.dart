/// 发现页选项栏持久缓存（legado ACache exploreKinds 等效）：
/// - 成功解析后按源缓存，二次打开直接回放，不再重放网络脚本；
/// - `refresh: true` 绕过缓存并覆盖；
/// - 脚本失败不写缓存（下次打开仍会重试）；
/// - `exploreUrl` 变化时旧缓存失效；字段完整往返。
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
int _hits = 0;
bool _serveEmpty = false;

Future<void> _startServer() async {
  _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  _base = 'http://${_server.address.host}:${_server.port}';
  _server.listen((req) {
    _hits++;
    final body = _serveEmpty
        ? ''
        : '[{"title":"分类A","url":"/a"},{"title":"开关","type":"toggle",'
            '"chars":["开","关"],"default":"开"}]';
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(body);
    req.response.close();
  });
}

PluginConfig _config(String exploreUrl) {
  return ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(<String, dynamic>{
    'bookSourceName': '本地选项栏缓存测试源',
    'bookSourceUrl': '$_base/cache/',
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
    ShuyuanExploreKindsStore.resetCacheForTest();
    _hits = 0;
    _serveEmpty = false;
    await _startServer();
  });

  tearDown(() => _server.close(force: true));

  test('成功解析后二次打开命中缓存，不再发起网络请求', () async {
    final cfg = _config("@js:JSON.parse(java.ajax(baseUrl + 'cats.json'))");
    final first = await ShuyuanNovelResolver().resolveExploreKinds(cfg);
    expect(first.error, isNull);
    expect(first.items.map((e) => e.displayName).toList(),
        <String>['分类A', '开关']);
    expect(_hits, 1);

    final second = await ShuyuanNovelResolver().resolveExploreKinds(cfg);
    expect(second.error, isNull);
    expect(second.items.map((e) => e.displayName).toList(),
        <String>['分类A', '开关']);
    expect(_hits, 1);
  });

  test('refresh=true 绕过缓存并重新抓取、覆盖缓存', () async {
    final cfg = _config("@js:JSON.parse(java.ajax(baseUrl + 'cats.json'))");
    await ShuyuanNovelResolver().resolveExploreKinds(cfg);
    expect(_hits, 1);

    final refreshed =
        await ShuyuanNovelResolver().resolveExploreKinds(cfg, refresh: true);
    expect(refreshed.error, isNull);
    expect(refreshed.items, hasLength(2));
    expect(_hits, 2);

    // 已覆盖为成功结果：再次打开仍是缓存命中。
    final again = await ShuyuanNovelResolver().resolveExploreKinds(cfg);
    expect(again.items, hasLength(2));
    expect(_hits, 2);
  });

  test('失败结果不写缓存，下次打开会重试', () async {
    _serveEmpty = true;
    final cfg = _config("@js:JSON.parse(java.ajax(baseUrl + 'cats.json'))");
    final first = await ShuyuanNovelResolver().resolveExploreKinds(cfg);
    expect(first.error, isNotNull);
    expect(_hits, 1);

    _serveEmpty = false;
    final second = await ShuyuanNovelResolver().resolveExploreKinds(cfg);
    expect(second.error, isNull);
    expect(second.items, isNotEmpty);
    expect(_hits, 2);
  });

  test('旧格式缓存条目按未命中处理（引擎语义修复后自愈）', () async {
    // 旧版本在 jsLib 解析失败时可能把脚本兜底项写入缓存；条目格式升级后
    // 必须视为未命中，让修复后的引擎重新跑脚本，而不是永久回放坏结果。
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'shuyuan_explore_kinds_v1',
      jsonEncode(<String, dynamic>{
        'k-old': <String, dynamic>{
          'url': 'https://x.test/a',
          'kinds': <Map<String, dynamic>>[
            <String, dynamic>{'title': '旧缓存'},
          ],
        },
      }),
    );
    ShuyuanExploreKindsStore.resetCacheForTest();

    final miss = await ShuyuanExploreKindsStore.load('k-old',
        exploreUrl: 'https://x.test/a');
    expect(miss, isNull);
  });

  test('缓存按 exploreUrl 失效，字段完整往返', () async {
    const kind = ExploreKind(
      title: '开关',
      type: 'toggle',
      action: "java.copyText('x')",
      chars: <String>['开', '关'],
      defaultValue: '关',
      viewName: "infoMap.get('开关')",
      style: ExploreKindStyle(
        layoutFlexGrow: 2,
        layoutWrapBefore: true,
        layoutJustifySelf: 'right',
      ),
    );
    await ShuyuanExploreKindsStore.save(
        'k1', 'https://x.test/a', const <ExploreKind>[kind]);

    final hit = await ShuyuanExploreKindsStore.load('k1',
        exploreUrl: 'https://x.test/a');
    expect(hit, isNotNull);
    final got = hit!.single;
    expect(got.title, '开关');
    expect(got.type, 'toggle');
    expect(got.action, "java.copyText('x')");
    expect(got.chars, <String>['开', '关']);
    expect(got.defaultValue, '关');
    expect(got.viewName, "infoMap.get('开关')");
    expect(got.style.layoutFlexGrow, 2);
    expect(got.style.layoutWrapBefore, isTrue);
    expect(got.style.layoutJustifySelf, 'right');

    final miss = await ShuyuanExploreKindsStore.load('k1',
        exploreUrl: 'https://x.test/b');
    expect(miss, isNull);
  });
}
