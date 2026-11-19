/// 发现页选项「选择后随时可改」与远端 jsLib `Reload` 机制回归：
/// - select 值变更经持久化 infoMap 参与 viewName 求值，连续改选每次生效；
/// - action 内 `infoMap.put(...)` 落盘，`java.refreshExplore()` 回传刷新请求；
/// - jsLib JSON 指向远端脚本时，脚本里的 `Reload`（cache etag + importScript）
///   经确定性重放后产出分类。
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
final Map<String, int> _hits = <String, int>{};

const String _libJs = r'''
function Reload(e) {
  const { java, source, cookie, cache } = this;
  var jskey = java.md5Encode16(e);
  var etag = '';
  try {
    if (cache.get('etagtime' + jskey) && Date.now() - cache.get('etagtime' + jskey) < 600000) {
      etag = cache.get('etag' + jskey) || 'noetag';
    } else {
      etag = String(java.head(e, {}).header('etag'));
      cache.put('etagtime' + jskey, Date.now());
    }
  } catch (err) {
    etag = cache.get('etag' + jskey) || 'noetag';
  }
  if (cache.get('etag' + jskey) && !new RegExp(etag).test(cache.get('etag' + jskey))) {
    cache.delete(jskey);
    etag = String(java.head(e, {}).header('etag'));
    cache.put('etag' + jskey, etag);
    cache.put('etagtime' + jskey, Date.now());
  }
  var res = String(java.importScript(e));
  return res;
}
''';

const String _remoteExploreJs = '''
[
  {"title": "分类甲", "url": "/alpha"},
  {"title": "分类乙", "url": "/beta"}
]
''';

Future<void> _startServer() async {
  _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  _base = 'http://${_server.address.host}:${_server.port}';
  _server.listen((req) {
    final path = req.uri.path;
    _hits[path] = (_hits[path] ?? 0) + 1;
    final body = switch (path) {
      '/lib.js' => _libJs,
      '/explore.js' => _remoteExploreJs,
      _ => null,
    };
    if (path == '/lib.js' || path == '/explore.js') {
      final bytes = utf8.encode(body!);
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType('application', 'javascript',
            charset: 'utf-8')
        ..add(bytes);
    } else {
      req.response.statusCode = 404;
    }
    req.response.close();
  });
}

PluginConfig _config({
  required String exploreUrl,
  String? jsLib,
}) {
  return ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(<String, dynamic>{
    'bookSourceName': '本地选项变更测试源',
    'bookSourceUrl': '$_base/site/',
    'bookSourceType': 0,
    'enabled': true,
    'exploreUrl': exploreUrl,
    if (jsLib != null) 'jsLib': jsLib,
    'ruleExplore': <String, dynamic>{
      'bookList': '#list li.item',
      'name': 'a@text',
      'bookUrl': 'a@href',
    },
  }));
}

String _selectKindsJson({required String action}) {
  return '['
      '{"title":"分类甲","url":"/alpha","viewName":"infoMap.get(\'排序\') + \'标签\'"},'
      '{"title":"排序","type":"select","chars":["默认","最新"],'
      '"default":"默认","action":${_jsonEscape(action)}}'
      ']';
}

String _jsonEscape(String s) {
  final escaped = s
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('\n', '\\n');
  return '"$escaped"';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  setUp(() async {
    HttpOverrides.global = null;
    JsEngine.resetPoolForTest();
    ShuyuanExploreInfoStore.resetCacheForTest();
    ShuyuanExploreKindsStore.resetCacheForTest();
    _hits.clear();
    await _startServer();
  });

  tearDown(() => _server.close(force: true));

  test('select 连续改选每次生效（viewName 跟随 infoMap）', () async {
    final cfg = _config(exploreUrl: _selectKindsJson(action: ''));
    final resolver = ShuyuanNovelResolver();

    final first = await resolver.resolveExploreKinds(cfg);
    expect(first.error, isNull);
    // 首载 displayName 求解早于默认值写入（legado：先 resolve 全部
    // displayName，再 buildKindValues），infoMap 尚无「排序」→ 'null标签'。
    expect(
      first.items.map((e) => '${e.kind.title}|${e.displayName}|${e.value}'),
      <String>['分类甲|null标签|', '排序|排序|默认'],
    );

    await resolver.setExploreKindValue(cfg, '排序', '最新');
    final second = await resolver.resolveExploreKinds(cfg, refresh: true);
    expect(
      second.items.map((e) => '${e.kind.title}|${e.displayName}|${e.value}'),
      <String>['分类甲|最新标签|', '排序|排序|最新'],
    );

    await resolver.setExploreKindValue(cfg, '排序', '默认');
    final third = await resolver.resolveExploreKinds(cfg, refresh: true);
    expect(
      third.items.map((e) => '${e.kind.title}|${e.displayName}|${e.value}'),
      <String>['分类甲|默认标签|', '排序|排序|默认'],
    );
  });

  test('action 内 infoMap.put 落盘并经 refreshExplore 请求刷新', () async {
    final cfg = _config(
      exploreUrl: _selectKindsJson(
          action: "infoMap.put('排序','最新'); java.refreshExplore();"),
    );
    final resolver = ShuyuanNovelResolver();

    final first = await resolver.resolveExploreKinds(cfg);
    expect(first.error, isNull);
    final select = first.items
        .firstWhere((e) => e.kind.title == '排序')
        .kind;

    final result = await resolver.executeExploreKindAction(cfg, select);
    expect(result.refreshKinds, isTrue);

    final refreshed = await resolver.resolveExploreKinds(cfg, refresh: true);
    final selectItem =
        refreshed.items.firstWhere((e) => e.kind.title == '排序');
    expect(selectItem.value, '最新');
    final urlItem = refreshed.items.firstWhere((e) => e.kind.title == '分类甲');
    expect(urlItem.displayName, '最新标签');
  });

  test('action 调用 upLoginData/reLoginView 不中断并触发选项刷新', () async {
    final cfg = _config(
      exploreUrl: _selectKindsJson(
          action: "java.upLoginData({a:1}); java.reLoginView();"),
    );
    final resolver = ShuyuanNovelResolver();

    final first = await resolver.resolveExploreKinds(cfg);
    expect(first.error, isNull);
    final select = first.items
        .firstWhere((e) => e.kind.title == '排序')
        .kind;

    // legado SourceLoginJsExtensions：upLoginData 推登录数据（发现页场景忽略），
    // reLoginView 触发界面重载 → 发现页选项整栏重取。缺失时脚本在
    // upLoginData 处抛 TypeError，后续 reLoginView 永不执行。
    final result = await resolver.executeExploreKindAction(cfg, select);
    expect(result.refreshKinds, isTrue);
  });

  test('远端 jsLib 的 Reload + importScript 产出分类', () async {
    final cfg = _config(
      exploreUrl: "<js>eval(String(Reload('$_base/explore.js')));</js>",
      jsLib: '{"main":"$_base/lib.js"}',
    );
    final resolver = ShuyuanNovelResolver();

    final cats = await resolver.resolveExploreCategories(cfg);
    expect(
      cats.map((c) => '${c.title}|${c.id}').toList(),
      <String>['分类甲|/alpha', '分类乙|/beta'],
    );
    expect(_hits['/lib.js'], isNotNull);
    expect(_hits['/explore.js'], isNotNull);
  });
}
