/// 发现页选项栏持久缓存（legado `BookSourceExtensions.exploreKinds` 的
/// ACache 持久化等效）。
///
/// 动态 exploreUrl（`@js:` 里发 `java.ajax`）每次展开源都要跑脚本 + 抓取，
/// 网络抖动会让本可正常的源变成「无发现页」。legado 把解析出的 kinds JSON
/// 按源缓存（不过期，手动刷新才重抓），NexHub 对齐该行为：
/// - 键为源标识（bookSourceUrl / source.id），值与 exploreUrl 绑定，
///   源定义变化时旧缓存自动失效；
/// - 条目带引擎语义版本：解析/脚本兼容修复后升级版本号，旧条目按未命中
///   处理，避免历史坏结果（如 jsLib 解析失败时的脚本兜底项）被永久回放；
/// - 脚本失败不写缓存；`refresh: true` 由调用方清除后重抓。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/explore_kind.dart';
import '../../core/utils/app_log.dart';

class ShuyuanExploreKindsStore {
  static const String _prefsKey = 'shuyuan_explore_kinds_v1';

  /// 条目格式/引擎语义版本。JS 运行时或兼容层的修复可能改变同一
  /// exploreUrl 的求值结果，升级时递增即可让旧缓存整体失效一次。
  static const int _schemaVersion = 2;

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
    if (entry['v'] != _schemaVersion) return null;
    if ('${entry['url'] ?? ''}' != exploreUrl) return null;
    final list = entry['kinds'];
    if (list is! List) return null;
    try {
      final kinds = <ExploreKind>[
        for (final e in list)
          if (e is Map) ExploreKind.fromJson(Map<String, dynamic>.from(e)),
      ];
      // legado 视空白缓存为未命中（重新跑脚本）；历史版本可能把一次网络
      // 抖动产生的空数组固化下来，这里一并按未命中处理以实现自愈。
      if (kinds.isEmpty) return null;
      return kinds;
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
    if (kinds.isEmpty) {
      // 空结果不落盘（下次展开重跑脚本），并清掉可能的旧条目。
      if (all.remove(key) != null) await _flush(all);
      return;
    }
    all[key] = <String, dynamic>{
      'v': _schemaVersion,
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
