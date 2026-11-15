/// 发现页选项栏的持久化状态（legado `infoMap_<bookSourceUrl>` 等效物）。
///
/// toggle/select 的选中项、text 输入内容存在这里；exploreUrl / viewName /
/// action 脚本求值时都以 `infoMap` 绑定注入。legado 以书源 URL 为键，本实现
/// 同样如此（不用内部 PluginConfig.id，保证书源迁移后状态仍可用）。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ShuyuanExploreInfoStore {
  ShuyuanExploreInfoStore._();

  static const String _storageKey = 'shuyuan_explore_info_v1';

  static Map<String, Map<String, String>>? _cache;

  static Future<Map<String, Map<String, String>>> _loadAll() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      _cache = <String, Map<String, String>>{};
      return _cache!;
    }
    try {
      final decoded = jsonDecode(raw);
      final out = <String, Map<String, String>>{};
      if (decoded is Map) {
        decoded.forEach((k, v) {
          if (v is Map) {
            out[k.toString()] = {
              for (final e in v.entries)
                e.key.toString(): e.value?.toString() ?? '',
            };
          }
        });
      }
      _cache = out;
    } catch (_) {
      _cache = <String, Map<String, String>>{};
    }
    return _cache!;
  }

  static Future<Map<String, String>> load(String sourceKey) async {
    final all = await _loadAll();
    return Map<String, String>.from(all[sourceKey] ?? const {});
  }

  static Future<void> save(String sourceKey, Map<String, String> infoMap) async {
    final all = await _loadAll();
    if (infoMap.isEmpty) {
      all.remove(sourceKey);
    } else {
      all[sourceKey] = Map<String, String>.from(infoMap);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(all));
  }

  /// 测试隔离用：清空内存缓存。
  static void resetCacheForTest() {
    _cache = null;
  }
}
