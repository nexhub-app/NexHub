/// 168 影院（pms_168ys）端到端探针：category→search→detail→episodes→video 真链路。
///
/// 运行（需真 QuickJS DLL 在 PATH，真实网络）：
/// PATH="/c/Users/yukai/AppData/Local/Pub/Cache/hosted/pub.flutter-io.cn/flutter_js-0.8.7/windows/shared:$PATH" \
///   flutter test test/pms_168ys_e2e_probe_test.dart
///
/// 仅人工诊断用，不进默认套件（真引擎会泄漏未处理异步错误）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/core/resolver/builtin_resolver.dart';
import 'package:nexhub/core/resolver/resolver_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});
  HttpOverrides.global = null;
  // CookieStore 落盘需要 Hive；测试环境指向临时目录，避免未处理异步错误。
  Hive.init(Directory.systemTemp
      .createTempSync('pms_168ys_e2e_hive')
      .path);

  final f = File('plugins/builtin/pms_168ys.json');
  test('source file exists', () {
    expect(f.existsSync(), isTrue);
  });
  if (!f.existsSync()) return;

  final source = PluginConfig.fromJson(
    jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
  );

  test('E2E: category → search → detail → episodes → video', () async {
    final resolver = const BuiltinResolver();

    // ① 分类列表（修复前 listSel 节点集谓词静默 0 条）
    final items = await resolver.resolve(
      source,
      'category',
      vars: const {'category': 'duanjun', 'page': '1'},
    ) as List<dynamic>;
    // ignore: avoid_print
    print('[category] ${items.length} 条, 首条: '
        '${(items.first as dynamic).id} / ${(items.first as dynamic).title} / '
        '${(items.first as dynamic).coverUrl}');
    expect(items, isNotEmpty, reason: '分类列表必须非空（节点集谓词修复）');
    expect((items.first as dynamic).id, isNotEmpty);
    expect((items.first as dynamic).title, isNotEmpty);
    expect((items.first as dynamic).coverUrl, startsWith('http'));

    // ② 搜索（搜索页与分类页 DOM 形态不同：box 卡片）
    final hits = await resolver.resolve(
      source,
      'search',
      vars: const {'keyword': '重生', 'page': '1'},
    ) as List<dynamic>;
    // ignore: avoid_print
    print('[search] ${hits.length} 条, 首条: '
        '${(hits.first as dynamic).id} / ${(hits.first as dynamic).title}');
    expect(hits, isNotEmpty, reason: '搜索列表必须非空');
    expect((hits.first as dynamic).id, isNotEmpty);

    // ③ 详情
    final firstId = (items.first as dynamic).id as String;
    final detail = await resolver.resolve(
      source,
      'detail',
      vars: {'id': firstId},
    ) as dynamic;
    // ignore: avoid_print
    print('[detail] id=$firstId title=${detail.title} cover=${detail.coverUrl}');
    expect(detail.title, isNotEmpty);
    expect(detail.coverUrl, startsWith('http'));

    // ④ 选集（多线路：lineList/lineName）
    final eps = await resolver.resolve(
      source,
      'episodes',
      vars: {'id': firstId},
    ) as List<dynamic>;
    // ignore: avoid_print
    print('[episodes] ${eps.length} 集: '
        '${eps.map((e) => '${(e as dynamic).lineName}|${(e as dynamic).title}|${(e as dynamic).url}').take(6).join(' , ')}');
    expect(eps, isNotEmpty, reason: '选集必须非空');

    // ⑤ 播放直链（player_aaaa 内嵌配置 + 明文 m3u8）
    final lines = eps
        .map((e) => (e as dynamic).lineName as String?)
        .where((l) => l != null && l.isNotEmpty)
        .toSet();
    expect(lines.length, greaterThanOrEqualTo(2),
        reason: '应解析出至少两条线路，实际: $lines');
    for (final ep in eps.take(2)) {
      final epUrl = (ep as dynamic).url as String;
      expect(epUrl, isNotEmpty);
      final r = await ResolverRegistry.instance
          .find(source, 'video')
          .resolve(source, 'video', vars: {'url': epUrl});
      final videoUrl = r is String ? r : (r as dynamic).url as String?;
      // ignore: avoid_print
      print('[video] $epUrl -> $videoUrl');
      expect(videoUrl, isNotNull);
      expect(videoUrl!.startsWith('http'), isTrue, reason: '直链应为绝对地址');
    }
  });
}
