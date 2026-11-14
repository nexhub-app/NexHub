/// 书源变量存储（legado「源变量」等效物）。
///
/// legado 把源级变量存 CacheManager（`sourceVariable_<key>`），供源脚本经
/// `source.getVariable/putVariable` 读写、书源编辑 UI 维护。此处按源
/// PluginConfig.id 存 SharedPreferences JSON map；P1 引擎侧的
/// source 对象通道将直接消费本存储。
///
/// 注意与脚本运行期变量（AnalyzeRule._variables，`java.put/get`）不同：
/// 那是单次解析的临时变量；本存储是持久化的源配置变量。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ShuyuanVariableStore {
  ShuyuanVariableStore._();

  static const String _storageKey = 'shuyuan_source_vars_v1';

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

  static Future<void> _persistAll() async {
    final all = _cache;
    if (all == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(all));
  }

  /// 读取某源的变量表（快照副本）。
  static Future<Map<String, String>> load(String sourceId) async {
    final all = await _loadAll();
    return Map<String, String>.from(all[sourceId] ?? const {});
  }

  /// 整表保存某源变量（空表时清除该源条目）。
  static Future<void> save(String sourceId, Map<String, String> vars) async {
    final all = await _loadAll();
    if (vars.isEmpty) {
      all.remove(sourceId);
    } else {
      all[sourceId] = Map<String, String>.from(vars);
    }
    await _persistAll();
  }

  /// 单键写入（P1 引擎 source.putVariable 通道）。
  static Future<void> put(String sourceId, String key, String value) async {
    final all = await _loadAll();
    all.putIfAbsent(sourceId, () => <String, String>{})[key] = value;
    await _persistAll();
  }

  /// 单键读取（P1 引擎 source.getVariable 通道）。
  static Future<String> get(String sourceId, String key) async {
    final all = await _loadAll();
    return all[sourceId]?[key] ?? '';
  }

  /// 测试隔离用：清空内存缓存。
  static void resetCacheForTest() {
    _cache = null;
  }
}
