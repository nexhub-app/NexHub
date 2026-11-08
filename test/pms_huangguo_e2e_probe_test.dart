/// 黄果短剧（pms_huangguo）端到端探针：latest/category→search→detail→episodes→video 真链路。
///
/// 验证点（2026-11 站点改版后首建）：
/// 1. SSR 分类页声明式选择器（限定 active 面板，排除页首隐藏联想块）；
/// 2. 搜索/详情走 GET JSON API 的 jsonpath 选择器（id 数值化，供 /api/videos/{id} 复用）；
/// 3. 选集走剧集页 ep-grid（data-ep-id 序号）；
/// 4. video 脚本从选集 url 抽 id+集号现取播放接口（直链带时效签名，不可预存）。
///
/// 运行（需真 QuickJS DLL 在 PATH，真实网络）：
/// PATH="/c/Users/yukai/AppData/Local/Pub/Cache/hosted/pub.flutter-io.cn/flutter_js-0.8.7/windows/shared:$PATH" \
///   flutter test test/pms_huangguo_e2e_probe_test.dart
///
/// 仅人工诊断用，不进默认套件（真引擎会泄漏未处理异步错误）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/core/resolver/resolver_registry.dart';
import 'package:nexhub/core/scraper/media_api_service.dart';
import 'package:nexhub/core/utils/image_decrypt_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});
  HttpOverrides.global = null;
  final hiveDir = Directory.systemTemp.createTempSync('pms_huangguo_e2e_hive');
  Hive.init(hiveDir.path);

  final f = File('plugins/zhenguojian/pms_huangguo.json');
  test('source file exists', () {
    expect(f.existsSync(), isTrue);
  });
  if (!f.existsSync()) return;

  final source = PluginConfig.fromJson(
    jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
  );
  final service = MediaApiService(ResolverRegistry.instance);

  test('E2E: latest 分类页声明式解析（active 面板 + 数值 id）', () async {
    final items = await service.fetchApiResults(
      source,
      'latest',
      vars: const {'page': '1'},
    );
    expect(items, isNotEmpty);
    // ignore: avoid_print
    print('[latest] ${items.length} 条, 首条: ${items.first.id} / ${items.first.title}');
    for (final it in items.take(5)) {
      // ignore: avoid_print
      print('  id=${it.id} cover=${it.coverUrl}');
      expect(it.id, matches(RegExp(r'^\d+$')), reason: 'id 必须是数值（detail 路由依赖）');
      expect(it.coverUrl, startsWith('https://'),
          reason: '封面必须是绝对地址（data-src 懒加载属性）');
    }
  });

  test('E2E: category 第二频道 + 翻页零重叠', () async {
    final p1 = await service.fetchApiResults(
      source,
      'category',
      vars: const {'category': 'ai-manju', 'page': '1'},
    );
    expect(p1, isNotEmpty, reason: '第二频道列表必须非空');
    final p2 = await service.fetchApiResults(
      source,
      'category',
      vars: const {'category': 'ai-manju', 'page': '2'},
    );
    expect(p2, isNotEmpty);
    final ids1 = p1.map((e) => e.id).toSet();
    final ids2 = p2.map((e) => e.id).toSet();
    // ignore: avoid_print
    print('[category ai-manju] p1=${p1.length} p2=${p2.length} 重叠=${ids1.intersection(ids2).length}');
    expect(ids1.intersection(ids2), isEmpty, reason: 'page=1/2 条目 id 必须零重叠（路径分页有效性）');
  });

  test('E2E: 封面字节解密（imageTransform 密文→图片魔数）', () async {
    final items = await service.fetchApiResults(
      source,
      'latest',
      vars: const {'page': '1'},
    );
    expect(items, isNotEmpty);
    final coverUrl = items.first.coverUrl;
    expect(coverUrl, isNotNull);
    final url = Uri.parse(coverUrl!);
    expect(
      ImageBytesDecryptRegistry.matchFor(url),
      isNotNull,
      reason: '源 imageTransform 应已按 host 注册解密规则（fromJson 时机）',
    );
    // 真网络拉取原始字节：站方图床 200 照常但返回的是 AES-CBC 密文
    // （Content-Type 谎报 binary/octet-stream），解密后必须出现图片魔数。
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      final response = await request.close();
      expect(response.statusCode, 200);
      final raw = <int>[];
      await for (final chunk in response) {
        raw.addAll(chunk);
      }
      final plain = ImageBytesDecryptRegistry.decrypt(url, Uint8List.fromList(raw));
      final isImage = plain.length > 12 &&
          ((plain[0] == 0xFF && plain[1] == 0xD8 && plain[2] == 0xFF) ||
              (plain[0] == 0x89 && plain[1] == 0x50) ||
              (plain[0] == 0x52 && plain[1] == 0x49 && plain[8] == 0x57));
      // ignore: avoid_print
      print('[cover-decrypt] raw=${raw.length}B head=${raw.take(4).map((b) => b.toRadixString(16).padLeft(2, '0')).join()} '
          'plain=${plain.length}B head=${plain.take(4).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
      expect(isImage, isTrue, reason: '解密后必须是 JPEG/PNG/WebP 魔数');
    } finally {
      client.close();
    }
  });

  test('E2E: search→detail→episodes→video 全链路', () async {
    final hits = await service.fetchApiResults(
      source,
      'search',
      vars: const {'keyword': '妈妈', 'page': '1'},
    );
    expect(hits, isNotEmpty, reason: '中文搜索必须非空');
    // ignore: avoid_print
    print('[search] ${hits.length} 条, 首条: ${hits.first.id} / ${hits.first.title}');
    final target = hits.first;

    final detail = await service.fetchDetail(source, target.id);
    // ignore: avoid_print
    print('[detail] ${detail.id} / ${detail.title} / eps=${detail.episodeCount}');
    expect(detail.title, isNotEmpty);
    expect(detail.id, equals(target.id));

    final eps = await service.fetchEpisodes(source, target.id);
    expect(eps, isNotEmpty, reason: '选集必须非空');
    // ignore: avoid_print
    print('[episodes] ${eps.length} 集: ${eps.take(3).map((e) => '${e.number}:${e.url}').join(' | ')}');
    for (final ep in eps.take(3)) {
      expect(ep.url, contains('/video/${target.id}'));
    }

    final video = await service.fetchVideoUrl(source, eps.first.url);
    // ignore: avoid_print
    print('[video] ${eps.first.url} -> ${video.url}');
    expect(video.url, startsWith('https://'));
    expect(video.url, contains(RegExp(r'\.(m3u8|mp4)')), reason: '直链必须是 m3u8/mp4');
  });
}
