/// viewName 求值面（legado `ExploreKindUiUseCase` → `BaseSource.evalJS`）。
///
/// legado 的 `infoMap` 是 Java Map（InfoMap）：viewName 脚本常写成
/// `infoMap.get('频道')`、`infoMap.containsKey(...)`。若只绑定纯 JS 对象，
/// 这些调用会 TypeError 中断求值，显示名退回 title——与 legado 不一致。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/features/shuyuan/presentation/shuyuan_novel_resolver.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';
import 'package:nexhub/features/shuyuan/shuyuan_explore_info_store.dart';
import 'package:nexhub/features/shuyuan/shuyuan_explore_kinds_store.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _baseUrl = 'https://viewname.test';

PluginConfig _config(String viewName) {
  return ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(<String, dynamic>{
    'bookSourceName': '本地 viewName 测试源',
    'bookSourceUrl': _baseUrl,
    'bookSourceType': 0,
    'enabled': true,
    'exploreUrl': '[{"title":"分类","url":"/a","viewName":'
        '${jsonEncode(viewName)}}]',
  }));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  setUp(() async {
    ShuyuanExploreInfoStore.resetCacheForTest();
    ShuyuanExploreKindsStore.resetCacheForTest();
    await ShuyuanExploreInfoStore.save(_baseUrl, <String, String>{
      'prefix': 'X',
    });
  });

  test('viewName 可调用 infoMap.get', () async {
    final result = await ShuyuanNovelResolver().resolveExploreKinds(
      _config("infoMap.get('prefix') + ' · 标签'"),
    );
    expect(result.error, isNull);
    expect(result.items.single.displayName, 'X · 标签');
  });

  test('viewName 可调用 infoMap.containsKey', () async {
    final result = await ShuyuanNovelResolver().resolveExploreKinds(
      _config("infoMap.containsKey('prefix') ? '有' : '无'"),
    );
    expect(result.error, isNull);
    expect(result.items.single.displayName, '有');
  });

  test('viewName 对 infoMap 的写入回写宿主并落盘', () async {
    final result = await ShuyuanNovelResolver().resolveExploreKinds(
      _config("infoMap.put('touched', '1'); '标签'"),
    );
    expect(result.error, isNull);
    expect(result.items.single.displayName, '标签');
    final saved = await ShuyuanExploreInfoStore.load(_baseUrl);
    expect(saved['touched'], '1',
        reason: 'legado 的 viewName 与 action 共用同一个 live InfoMap');
  });
}
