/// 宽屏（平板 / 桌面窗口）响应式布局工具集。
///
/// 布局只看窗口宽度：桌面窗口与平板横屏在相同宽度下呈现一致的内容排版
/// （用户决策：平板与桌面共用宽屏排版，桌面不另设差异）。
/// 手机档（宽度 ≤ [AppTokens.compactBreakpoint]）行为与历史版本完全一致。
library;

import 'package:material_ui/material_ui.dart';

import '../theme/app_tokens.dart';

/// 布局宽度档位（Material 3 窗口分级，按可用布局宽度判断）。
enum AppWidthClass {
  /// 手机竖屏（< 600）。
  compact,

  /// 手机横屏 / 小平板竖屏（600 – 840）。
  medium,

  /// 平板横屏 / 桌面窗口（≥ 840）。
  expanded,
}

/// 宽屏响应式计算。
abstract final class AppResponsive {
  /// 按布局宽度分档。
  static AppWidthClass widthClassOf(double width) {
    if (width < AppTokens.compactBreakpoint) return AppWidthClass.compact;
    if (width < AppTokens.desktopBreakpoint) return AppWidthClass.medium;
    return AppWidthClass.expanded;
  }

  /// 是否达到双栏详情宽度（≥ [AppTokens.twoPaneBreakpoint]）。
  static bool twoPaneAvailable(double width) =>
      width >= AppTokens.twoPaneBreakpoint;
}

/// [BuildContext] 便捷分档。
extension ResponsiveContext on BuildContext {
  /// 当前布局宽度（跟随最近一层 MediaQuery，窗口或被压缩的布局区）。
  double get layoutWidth => MediaQuery.sizeOf(this).width;

  /// 当前宽度档位。
  AppWidthClass get widthClass => AppResponsive.widthClassOf(layoutWidth);

  /// 是否扩展档（≥ 840，平板横屏 / 桌面窗口）。
  bool get isExpandedWidth => widthClass == AppWidthClass.expanded;

  /// 是否可启用双栏详情（≥ 1120）。
  bool get twoPaneAvailable => AppResponsive.twoPaneAvailable(layoutWidth);
}
