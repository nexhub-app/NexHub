/// 桌面卡片的个性化设置（背景、模糊、不透明度、继续观看条数）。
///
/// 持久化到 SharedPreferences（key: `home_widget_settings_v1`），
/// 复用 [PrefsBackend] 抽象以便测试注入；与 [GeneralSettingsStore] 同一套写法。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../comic/models/reader_preferences.dart';
import '../utils/app_log.dart';

/// 卡片背景来源。
enum WidgetBackgroundMode {
  /// 用最近在看的作品封面（模糊后铺满）。
  cover,

  /// 主题色渐变。
  theme,

  /// 无背景（纯卡片底色）。
  none;

  static WidgetBackgroundMode parse(String? raw) {
    return switch (raw) {
      'theme' => WidgetBackgroundMode.theme,
      'none' => WidgetBackgroundMode.none,
      _ => WidgetBackgroundMode.cover,
    };
  }
}

/// 卡片外观与条数设置（不可变，改一项就整份重存）。
class HomeWidgetSettings {
  final WidgetBackgroundMode background;

  /// 背景模糊强度（0–40，0 = 不模糊）。
  final double blurSigma;

  /// 背景不透明度（0.2–1.0，越低越贴近卡片底色）。
  final double opacity;

  /// 继续观看保留条数（3–8）。
  final int continueLimit;

  const HomeWidgetSettings({
    this.background = WidgetBackgroundMode.cover,
    this.blurSigma = 18,
    this.opacity = 0.85,
    this.continueLimit = 4,
  });

  HomeWidgetSettings copyWith({
    WidgetBackgroundMode? background,
    double? blurSigma,
    double? opacity,
    int? continueLimit,
  }) {
    return HomeWidgetSettings(
      background: background ?? this.background,
      blurSigma: blurSigma ?? this.blurSigma,
      opacity: opacity ?? this.opacity,
      continueLimit: continueLimit ?? this.continueLimit,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'background': background.name,
        'blurSigma': blurSigma,
        'opacity': opacity,
        'continueLimit': continueLimit,
      };

  factory HomeWidgetSettings.fromJson(Map<String, dynamic> json) {
    final double blur = (json['blurSigma'] as num?)?.toDouble() ?? 18;
    final double alpha = (json['opacity'] as num?)?.toDouble() ?? 0.85;
    final int limit = (json['continueLimit'] as num?)?.toInt() ?? 4;
    return HomeWidgetSettings(
      background: WidgetBackgroundMode.parse(json['background'] as String?),
      blurSigma: blur.clamp(0, 40).toDouble(),
      opacity: alpha.clamp(0.2, 1.0).toDouble(),
      continueLimit: limit.clamp(3, 8),
    );
  }
}

/// 全局设置仓库（单例 + ChangeNotifier）。
class HomeWidgetSettingsStore extends ChangeNotifier {
  static const String _key = 'home_widget_settings_v1';

  final PrefsBackend _backend;
  HomeWidgetSettings _settings = const HomeWidgetSettings();
  bool _loaded = false;

  HomeWidgetSettingsStore({PrefsBackend? backend})
      : _backend = backend ?? const SharedPrefsBackend();

  static HomeWidgetSettingsStore? _instance;
  static HomeWidgetSettingsStore get instance {
    _instance ??= HomeWidgetSettingsStore();
    if (!_instance!._loaded) {
      _instance!.load();
    }
    return _instance!;
  }

  HomeWidgetSettings get settings => _settings;
  bool get loaded => _loaded;

  Future<void> load() async {
    try {
      final String? raw = await _backend.get(_key);
      if (raw != null && raw.isNotEmpty) {
        _settings = HomeWidgetSettings.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map<dynamic, dynamic>),
        );
      }
    } on Object catch (e) {
      AppLog.instance.w('[桌面卡片] 读取设置失败: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> save(HomeWidgetSettings next) async {
    _settings = next;
    _loaded = true;
    notifyListeners();
    try {
      await _backend.set(_key, jsonEncode(next.toJson()));
    } on Object catch (e) {
      AppLog.instance.w('[桌面卡片] 保存设置失败: $e');
    }
  }

  Future<void> setBackground(WidgetBackgroundMode mode) =>
      save(_settings.copyWith(background: mode));

  Future<void> setBlurSigma(double value) =>
      save(_settings.copyWith(blurSigma: value.clamp(0, 40).toDouble()));

  Future<void> setOpacity(double value) =>
      save(_settings.copyWith(opacity: value.clamp(0.2, 1.0).toDouble()));

  Future<void> setContinueLimit(int value) =>
      save(_settings.copyWith(continueLimit: value.clamp(3, 8)));
}
