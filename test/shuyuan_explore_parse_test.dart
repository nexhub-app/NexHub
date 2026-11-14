/// exploreUrl 结构化解析测试（P1-1 发现页）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';
import 'package:nexhub/features/shuyuan/web_book/web_book.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('JSON 数组 exploreUrl（含多行 @js: 脚本）结构化解析', () async {
    final f = File(r'E:\nexhub\_tmp\sources_sample\read-main\sources\yck-novel.json');
    final data = jsonDecode(f.readAsStringSync().replaceAll('\ufeff', ''));
    Map<String, dynamic>? raw;
    for (final e in (data as List)) {
      if (e is Map<String, dynamic> && '${e['bookSourceName']}'.contains('全免小说')) {
        raw = e;
        break;
      }
    }
    expect(raw, isNotNull);
    final exploreUrl = raw!['exploreUrl'] as String;
    // 外层解码后的 exploreUrl 字符串值内有裸换行（多行 @js: 脚本）。
    expect(exploreUrl.contains('\n'), true);

    final source = ShuyuanSource.fromJson(raw).toBookSource();
    final wb = WebBook();

    final cats = wb.getExploreCategories(source);
    // 期望：结构化解析出真实分类（推荐/完本/人气…），而不是把脚本行拆成分类。
    expect(cats.length, lessThan(60), reason: '不应把脚本行拆成分类：${cats.take(6)}');
    expect(
      cats.any((c) => c.name == '推荐' && c.url.startsWith('@js:')),
      true,
      reason: '推荐分类的 url 应保留 @js: 脚本待抓取期执行',
    );
  });
}
