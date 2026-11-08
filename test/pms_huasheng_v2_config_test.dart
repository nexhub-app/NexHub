/// 花生短剧 v2 修复批次：分类筛选接口化 + 视频多候选择优（离线确定性验证）。
///
/// 站点无关的本质规律（沉淀口径，不含真实域名）：
/// - 站点导航可能只有一个类型，真实浏览维度藏在分类页筛选面板（年份/排序），
///   走站内筛选接口（searchtype 形态查询串）而非 /zywtype/ 目录页；
/// - 可选筛选参数用 `{param?}` 占位：缺省/空值整段移除，中文值自动编码；
/// - 播放页 m3u8 路径里的分辨率标签（/1080/）与真实分片码率无关
///   （同页可验：720 档分片码率低于 1080 档），取址脚本只能以标签作
///   同页多候选间的相对择优依据；单候选时即为站方上限。
///
/// 运行（需真 QuickJS DLL 在 PATH）：
/// PATH="/c/Users/yukai/AppData/Local/Pub/Cache/hosted/pub.flutter-io.cn/flutter_js-0.8.7/windows/shared:$PATH" \
///   flutter test test/pms_huasheng_v2_config_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/core/resolver/js_context.dart';

class _StaticBridge implements JsHostBridge {
  const _StaticBridge();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PluginConfig _config() {
  final json = jsonDecode(
    File('plugins/builtin/pms_huasheng.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  return PluginConfig.fromJson(json);
}

FlutterJsEngine _engine() {
  final engine = FlutterJsEngine(
    const _StaticBridge(),
    baseUrl: 'https://www.zywest263.com',
  );
  engine.injectContext(<String, String>{
    'url': 'https://www.zywest263.com/zywplay/94558-0-0.html',
    'baseUrl': 'https://www.zywest263.com',
  });
  return engine;
}

String _videoScript() => _config().parser!.overrides!['video']!.script!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ============================================================
  // 一、配置层：分类路由筛选接口化 + filters 块
  // ============================================================
  group('config v2', () {
    test('版本号必须 +1，否则覆盖不了已装副本', () {
      expect(_config().version, greaterThan(1));
    });

    test('category 路由走筛选接口，可选参数带 ? 后缀', () {
      final url = _config().routes['category']!.url;
      expect(url, contains('searchtype=5'));
      expect(url, contains('tid={category}'));
      expect(url, contains('year={year?}'));
      expect(url, contains('order={order?}'));
    });

    test('resolveRouteUrl：无筛选值时可选段整段移除，不留空参数', () {
      final url = _config().resolveRouteUrl(
        'category',
        activeBaseUrl: 'https://www.zywest263.com',
        vars: const {'page': '1', 'category': '27'},
      );
      expect(url, 'https://www.zywest263.com/search.html?page=1&searchtype=5&tid=27');
      expect(url, isNot(contains('year=')));
      expect(url, isNot(contains('order=')));
    });

    test('resolveRouteUrl：年份/排序选中值代入；空串值整段移除', () {
      final base = <String, String>{'page': '2', 'category': '27'};
      final withYear = _config().resolveRouteUrl(
        'category',
        activeBaseUrl: 'https://www.zywest263.com',
        vars: {...base, 'year': '2025'},
      );
      expect(withYear, contains('&year=2025'));
      expect(withYear, isNot(contains('order=')));

      final bothEmpty = _config().resolveRouteUrl(
        'category',
        activeBaseUrl: 'https://www.zywest263.com',
        vars: {...base, 'year': '', 'order': ''},
      );
      expect(bothEmpty, isNot(contains('year=')));
      expect(bothEmpty, isNot(contains('order=')));

      final withOrder = _config().resolveRouteUrl(
        'category',
        activeBaseUrl: 'https://www.zywest263.com',
        vars: {...base, 'order': 'hit'},
      );
      expect(withOrder, contains('&order=hit'));
      expect(withOrder, isNot(contains('year=')));
    });

    test('filters 块：年份 15 档 + 排序 3 档，param 对得上路由占位符', () {
      final filters = _config().filters!;
      expect(filters.route, 'category');
      expect(filters.groups, hasLength(2));

      final year = filters.groups.firstWhere((g) => g.id == 'year');
      expect(year.param, 'year');
      // 全部 + 2013~2026
      expect(year.options, hasLength(15));
      expect(year.options.first.value, isEmpty);
      expect(year.options.map((o) => o.value), contains('2013'));
      expect(year.options.map((o) => o.value), contains('2026'));

      final order = filters.groups.firstWhere((g) => g.id == 'order');
      expect(order.param, 'order');
      expect(order.options.map((o) => o.value), containsAll(['', 'time', 'hit']));
    });

    test('热播板块：复用 category 路由并固定 order=hit', () {
      final sections = _config().homeSections!;
      final hot = sections.firstWhere((s) => s.id == 'hot');
      expect(hot.route, 'category');
      expect(hot.params, containsPair('category', '27'));
      expect(hot.params, containsPair('order', 'hit'));
      final url = _config().resolveRouteUrl(
        'category',
        activeBaseUrl: 'https://www.zywest263.com',
        vars: {'page': '1', ...hot.params},
      );
      expect(url, contains('&order=hit'));
    });
  });

  // ============================================================
  // 二、视频层：真 QuickJS 跑 parseVideo
  // ============================================================
  group('parseVideo (real QuickJS)', () {
    test('真实播放页快照：唯一明文地址原样返回', () async {
      final html =
          File('test/fixtures/huasheng_play.html').readAsStringSync();
      final out = await _engine()
          .run(_videoScript(), 'parseVideo', <dynamic>[html]) as String;
      expect(
        out,
        'https://cdn.yddsha2.com/m3u87/share/11305613/11487671/20261108/001612/1080/master.m3u8',
      );
    });

    test('多候选：低清在前也选高分辨率标签（旧正则恒取第一个）', () async {
      const html = "<html><script>var a='https://cdn.example/v/720/master.m3u8'"
          ",'https://cdn.example/v/1080/master.m3u8';</script></html>";
      final out = await _engine()
          .run(_videoScript(), 'parseVideo', <dynamic>[html]) as String;
      expect(out, 'https://cdn.example/v/1080/master.m3u8');
    });

    test('多候选：同标签时 m3u8 优先于 mp4', () async {
      const html = "x 'https://cdn.example/v/ep.mp4' "
          "'https://cdn.example/v/ep/master.m3u8' y";
      final out = await _engine()
          .run(_videoScript(), 'parseVideo', <dynamic>[html]) as String;
      expect(out, 'https://cdn.example/v/ep/master.m3u8');
    });

    test('无明文地址时回退 player_aaaa（encrypt=2 base64 解码）', () async {
      // base64('https://cdn.example/v/ep.mp4')
      const enc = 'aHR0cHM6Ly9jZG4uZXhhbXBsZS92L2VwLm1wNA==';
      const html =
          'var player_aaaa={"url":"$enc","encrypt":2,"from":"example"};';
      final out = await _engine()
          .run(_videoScript(), 'parseVideo', <dynamic>[html]) as String;
      expect(out, 'https://cdn.example/v/ep.mp4');
    });
  });
}
