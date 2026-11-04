/// Bing 翻译与详情页自动翻译开关（SharedPreferences + ChangeNotifier）。
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TranslationFeatureFlags extends ChangeNotifier {
  TranslationFeatureFlags._();

  static final TranslationFeatureFlags instance = TranslationFeatureFlags._();

  static const String _kBingEnabled = 'translation_bing_enabled_v1';
  static const String _kBingFirst = 'translation_bing_first_v1';
  static const String _kAutoTitle = 'translation_auto_title_v1';
  static const String _kAutoTags = 'translation_auto_tags_v1';
  static const String _kAutoSummary = 'translation_auto_summary_v1';
  static const String _kAutoComments = 'translation_auto_comments_v1';

  bool bingEnabled = true;
  bool bingFirst = true;
  bool autoTitle = true;
  bool autoTags = true;
  bool autoSummary = true;
  bool autoComments = true;

  bool _loaded = false;
  Future<void>? _loading;

  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    final loading = _loading ??= _load();
    // 平台通道 / 存储偶发不可用时不能让失败 future 常驻：否则后续
    // ensureLoaded 永远拿到同一个 error，详情页标题、标签、简介的自动翻译
    // 会一直「哑火」且没有任何日志。
    return loading.catchError((Object _) {
      _loading = null;
    });
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    bingEnabled = p.getBool(_kBingEnabled) ?? true;
    bingFirst = p.getBool(_kBingFirst) ?? true;
    autoTitle = p.getBool(_kAutoTitle) ?? true;
    autoTags = p.getBool(_kAutoTags) ?? true;
    autoSummary = p.getBool(_kAutoSummary) ?? true;
    autoComments = p.getBool(_kAutoComments) ?? true;
    _loaded = true;
    notifyListeners();
  }

  /// 设置页保存后重新读取并通知监听者。
  Future<void> reload() async {
    _loaded = false;
    _loading = null;
    await ensureLoaded();
  }

  Future<void> update({
    bool? bingEnabled,
    bool? bingFirst,
    bool? autoTitle,
    bool? autoTags,
    bool? autoSummary,
    bool? autoComments,
  }) async {
    final p = await SharedPreferences.getInstance();
    if (bingEnabled != null) {
      this.bingEnabled = bingEnabled;
      await p.setBool(_kBingEnabled, bingEnabled);
    }
    if (bingFirst != null) {
      this.bingFirst = bingFirst;
      await p.setBool(_kBingFirst, bingFirst);
    }
    if (autoTitle != null) {
      this.autoTitle = autoTitle;
      await p.setBool(_kAutoTitle, autoTitle);
    }
    if (autoTags != null) {
      this.autoTags = autoTags;
      await p.setBool(_kAutoTags, autoTags);
    }
    if (autoSummary != null) {
      this.autoSummary = autoSummary;
      await p.setBool(_kAutoSummary, autoSummary);
    }
    if (autoComments != null) {
      this.autoComments = autoComments;
      await p.setBool(_kAutoComments, autoComments);
    }
    _loaded = true;
    notifyListeners();
  }
}
