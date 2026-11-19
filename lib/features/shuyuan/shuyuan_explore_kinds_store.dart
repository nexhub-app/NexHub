/// 发现页选项栏持久缓存（legado `BookSourceExtensions.exploreKinds` 的
/// ACache 持久化等效）。
///
/// 动态 exploreUrl（`@js:` 里发 `java.ajax`）每次展开源都要跑脚本 + 抓取，
/// 网络抖动会让本可正常的源变成「无发现页」。legado 把解析出的 kinds JSON
/// 按源缓存（不过期，手动刷新才重抓），NexHub 对齐该行为：
/// - 键为源标识（bookSourceUrl / source.id），值与 exploreUrl 绑定，
///   源定义变化时旧缓存自动失效；
/// - 脚本失败不写缓存；`refresh: true` 由调用方清除后重抓。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/explore_kind.dart';
import '../../core/utils/app_log.dart';

class ShuyuanExploreKindsStore {
  static const String _prefsKey = 'shuyuan_explore_kinds_v1';

  /// 内存快照（同一会话内多个源复用；写入后同步更新）。
  static Map<String, dynamic>? _cache;

  static Future<Map<String, dynamic>> _loadAll() async {
    final cached = _cache;
    if (cached != null) return cached;
    Object? decoded;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) decoded = jsonDecode(raw);
    } catch (e) {
      AppLog.instance.w('[发现页缓存] 读取失败: $e');
    }
    return _cache = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  }

  /// 读取 [key] 的缓存；exploreUrl 与写入时不一致视为失效（返回 null）。
  static Future<List<ExploreKind>?> load(
    String key, {
    required String exploreUrl,
  }) async {
    final all = await _loadAll();
    final entry = all[key];
    if (entry is! Map) return null;
    if ('${entry['url'] ?? ''}' != exploreUrl) return null;
    final list = entry['kinds'];
    if (list is! List) return null;
    try {
      return <ExploreKind>[
        for (final e in list)
          if (e is Map) ExploreKind.fromJson(Map<String, dynamic>.from(e)),
      ];
    } catch (e) {
      AppLog.instance.w('[发现页缓存] 解析失败: $e');
      return null;
    }
  }

  static Future<void> save(
    String key,
    String exploreUrl,
    List<ExploreKind> kinds,
  ) async {
    final all = await _loadAll();
    all[key] = <String, dynamic>{
      'url': exploreUrl,
      'kinds': <Map<String, dynamic>>[for (final k in kinds) k.toJson()],
    };
    await _flush(all);
  }

  static Future<void> clear(String key) async {
    final all = await _loadAll();
    if (all.remove(key) != null) await _flush(all);
  }

  static Future<void> _flush(Map<String, dynamic> all) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(all));
    } catch (e) {
      AppLog.instance.w('[发现页缓存] 写入失败: $e');
    }
  }

  static void resetCacheForTest() => _cache = null;
}
