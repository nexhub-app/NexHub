/// 阅读/主题配置桥：把宿主实时阅读偏好交给书源引擎。
///
/// 书源脚本的 `java.getReadBookConfig()/getThemeConfig()/getThemeMode()`
/// 对应 legado 的当前阅读设置（源常按 `bgStr`/`textSize` 生成配图或字体
/// 参数）。NexHub 的阅读偏好是「每书一份 + 全局默认」，只存在于阅读器
/// 状态里；此桥由阅读器在偏好加载/变更时写入，书源上下文构造时继承，
/// 避免核心引擎反向依赖 UI。
///
/// 只写「能确定的字段」：未写入的字段由书源预置脚本回落到 legado 默认值
/// 后再合并注入值，保证脚本 JSON.parse 后字段齐全。
library;

import 'dart:convert';
import 'dart:ui' show Color;

import 'novel_reader_preferences.dart';

class ReaderConfigBridge {
  ReaderConfigBridge._();

  /// legado `ReadBookConfig` 形态的 JSON（部分字段）。
  static String readConfigJson = '';

  /// legado `ThemeConfig` 形态的 JSON（部分字段）。
  static String themeConfigJson = '';

  /// `day` / `night`（legado `getThemeMode`）。
  static String themeMode = '';

  /// 阅读器偏好变化时调用：[appIsDark] 为应用外观明暗，[accent] 为强调色。
  static void updateFromPrefs(
    NovelReaderPreferences prefs, {
    bool appIsDark = false,
    Color? accent,
  }) {
    final Color bg = prefs.resolveBackgroundColor(appIsDark);
    final Color fg = prefs.resolveTextColor(bg);
    // 阅读器自身的夜间判定：以解析后的背景亮度为准（themeFollow 可能强制
    // 昼夜，与应用外观不一致）。
    final bool night = bg.computeLuminance() < 0.5;
    final int textSize = prefs.fontSize.round();
    readConfigJson = jsonEncode(<String, Object?>{
      'name': 'NexHub',
      'bgStr': _hex(bg),
      'bgStrNight': _hex(bg),
      'bgType': 0,
      'bgTypeNight': 0,
      'textColor': _hex(fg),
      'textColorNight': _hex(fg),
      'textSize': textSize,
      'lineSpacingExtra':
          (textSize * (prefs.lineHeight - 1)).clamp(0, 200).round(),
      'paragraphSpacing': prefs.paragraphSpacing.round(),
      'paddingLeft': prefs.margin.round(),
      'paddingRight': prefs.margin.round(),
      'paddingTop': prefs.margin.round(),
      'paddingBottom': prefs.margin.round(),
      'letterSpacing': prefs.letterSpacing,
      'textBold': prefs.fontBold ? 700 : 400,
      'textItalic': prefs.fontItalic,
      'textShadow': prefs.shadow,
      'shadowRadius': prefs.shadowBlur,
      'shadowDx': prefs.shadowOffsetX,
      'shadowDy': prefs.shadowOffsetY,
      'textFont': prefs.fontFamily ?? '',
      'titleFont': prefs.titleFontFamily ?? '',
    });
    themeConfigJson = jsonEncode(<String, Object?>{
      'themeName': night ? 'NexHub-Dark' : 'NexHub-Day',
      'isNightTheme': night,
      'accentColor': _hex(accent ?? fg),
      'backgroundColor': _hex(bg),
      'backgroundImgPath': null,
      'backgroundImgBlur': 0,
    });
    themeMode = night ? 'night' : 'day';
  }

  /// 清空（退出阅读器/重置偏好时用；空值让引擎回落默认）。
  static void clear() {
    readConfigJson = '';
    themeConfigJson = '';
    themeMode = '';
  }

  /// `#RRGGBB`（legado 配置里的颜色是三位/六位十六进制串）。
  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
