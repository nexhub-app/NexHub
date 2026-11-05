/// 全局替换（正文净化）规则仓库。
///
/// 规则全局一套，随包内置一批默认规则，
/// 每条规则可限定「仅本书 / 仅本源」；每本书只保留一个总开关。
/// 旧版按书籍存储的规则在首次打开该书时自动迁移为「仅本书」规则。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../comic/models/reader_preferences.dart';
import 'novel_replace_rule.dart';

class NovelReplaceRuleStore {
  NovelReplaceRuleStore._({PrefsBackend? backend})
      : _backend = backend ?? const SharedPrefsBackend();

  static final NovelReplaceRuleStore _instance = NovelReplaceRuleStore._();

  factory NovelReplaceRuleStore() => _instance;

  /// 测试用：使用独立后端，避免读到真实存档。
  @visibleForTesting
  static NovelReplaceRuleStore withBackend(PrefsBackend backend) =>
      NovelReplaceRuleStore._(backend: backend);

  static const String _rulesKey = 'novel_replace_rules_global_v1';
  static const String _bookEnabledPrefix = 'novel_replace_book_enabled_v1::';
  static const String _legacyRulesPrefix = 'novel_replace_rules_v1::';
  static const String _legacyMarkPrefix = 'novel_replace_rules_migrated_v1::';
  static const String _assetPath = 'assets/novel/replace_rules.json';

  final PrefsBackend _backend;

  NovelReplaceRuleSet? _cached;
  List<NovelReplaceRule>? _builtInsCache;
  final Set<String> _legacyChecked = {};

  /// 读取全局规则集合。首次运行（无存档）时播种内置规则。
  ///
  /// 用户把规则全部删空后不会自动加回——只有「恢复内置规则」才会补。
  Future<NovelReplaceRuleSet> load({bool refresh = false}) async {
    final cached = _cached;
    if (!refresh && cached != null) return cached;

    NovelReplaceRuleSet? set;
    final raw = await _backend.get(_rulesKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          set = NovelReplaceRuleSet.fromJson(decoded);
        }
      } catch (_) {
        set = null;
      }
    }
    if (set == null) {
      set = NovelReplaceRuleSet(
        bookId: NovelReplaceRuleSet.globalId,
        enabled: true,
        rules: await builtIns(),
      );
      await save(set);
    }
    _cached = set;
    return set;
  }

  /// 保存全局规则集合（持久化 + 更新缓存）。
  Future<void> save(NovelReplaceRuleSet set) async {
    await _backend.set(_rulesKey, jsonEncode(set.toJson()));
    _cached = set;
  }

  /// 清空内存缓存（外部改动存档后调用）。
  void invalidate() {
    _cached = null;
  }

  /// 本书是否启用净化（默认启用）。
  Future<bool> isBookEnabled(String bookId) async {
    if (bookId.isEmpty) return true;
    final raw = await _backend.get('$_bookEnabledPrefix$bookId');
    return raw != '0';
  }

  /// 设置本书净化开关。
  Future<void> setBookEnabled(String bookId, bool enabled) async {
    if (bookId.isEmpty) return;
    await _backend.set('$_bookEnabledPrefix$bookId', enabled ? '1' : '0');
  }

  /// 补充缺失的内置规则，返回新增条数（已有同 id 规则不动）。
  Future<int> restoreBuiltIns() async {
    final set = await load();
    final existing = set.rules.map((r) => r.id).toSet();
    var maxOrder = _maxOrder(set.rules);
    var added = 0;
    for (final rule in await builtIns()) {
      if (existing.contains(rule.id)) continue;
      maxOrder += 10;
      set.rules.add(rule.copyWith(order: maxOrder));
      added++;
    }
    if (added > 0) await save(set);
    return added;
  }

  /// 把旧版「按书籍存储」的规则迁移成全局规则里的「仅本书」条目。
  ///
  /// 只在首次打开该书时执行一次；返回是否发生了迁移。
  Future<bool> migrateLegacy(String bookId, String bookName) async {
    if (bookId.isEmpty) return false;
    if (_legacyChecked.contains(bookId)) return false;
    _legacyChecked.add(bookId);
    final markKey = '$_legacyMarkPrefix$bookId';
    if (await _backend.get(markKey) == '1') return false;

    final raw = await _backend.get('$_legacyRulesPrefix$bookId');
    if (raw == null || raw.isEmpty) {
      await _backend.set(markKey, '1');
      return false;
    }

    NovelReplaceRuleSet? legacy;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        legacy = NovelReplaceRuleSet.fromJson(decoded);
      }
    } catch (_) {
      legacy = null;
    }
    await _backend.set(markKey, '1');
    if (legacy == null || legacy.rules.isEmpty) return false;

    final set = await load();
    final existing = set.rules.map((r) => r.id).toSet();
    var maxOrder = _maxOrder(set.rules);
    var migrated = false;
    for (final rule in legacy.rules) {
      if (existing.contains(rule.id)) continue;
      maxOrder += 10;
      set.rules.add(rule.copyWith(
        applyTo: 'book',
        applyToValue: bookId,
        applyToLabel: bookName,
        isBuiltIn: false,
        order: maxOrder,
      ));
      migrated = true;
    }
    if (migrated) {
      await save(set);
      // 旧版整本关闭过净化 → 沿用为本书关闭。
      if (!legacy.enabled) await setBookEnabled(bookId, false);
    }
    return migrated;
  }

  /// 随包内置的默认规则（首次运行播种 / 手动恢复时使用）。
  Future<List<NovelReplaceRule>> builtIns() async {
    final cached = _builtInsCache;
    if (cached != null) return [for (final r in cached) r.copyWith()];
    List<NovelReplaceRule> rules = const [];
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final decoded = jsonDecode(raw);
      final list = decoded is Map<String, dynamic>
          ? decoded['rules'] as List?
          : decoded as List?;
      rules = [
        for (final item in list ?? const [])
          if (item is Map<String, dynamic>)
            NovelReplaceRule.fromJson(item).copyWith(isBuiltIn: true),
      ];
    } catch (_) {
      // 资源缺失（例如被裁剪的构建）时保持空列表，界面仍可手动添加规则。
      rules = const [];
    }
    _builtInsCache = rules;
    return [for (final r in rules) r.copyWith()];
  }

  static int _maxOrder(List<NovelReplaceRule> rules) {
    var max = 0;
    for (final rule in rules) {
      if (rule.order > max) max = rule.order;
    }
    return max;
  }
}
