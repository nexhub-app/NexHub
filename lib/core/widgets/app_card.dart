import 'package:material_ui/material_ui.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// 统一卡片容器（柔和填充卡：token 圆角 + 无描边无投影）。点击态可选。
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  /// 覆盖卡底色（默认 surfaceContainerLow，随 ColorScheme 动态取色）。
  final Color? color;
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    // 背景色由 Material 直接承载：ListTile / InkWell 等墨水组件必须嵌在
    // Material **里面**（墨迹才会落在卡面并被圆角裁切）。把 InkWell 包在
    // Material 外层会触发 "No Material widget found" 断言——列表项被
    // LookupBoundary 包裹时尤其明显（如 ReorderableListView 内部）。
    // 柔和填充卡（Legado MD3 观感）：elevation 0，靠色阶与圆角划界，不靠线框。
    final Widget body = Padding(
      padding: padding ?? const EdgeInsets.all(AppTokens.spaceMd),
      child: child,
    );
    return Material(
      color: color ?? AppTheme.cardContainer(scheme),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? body
          : InkWell(
              onTap: onTap,
              // 墨迹与圆角一致；Material 已裁切，这里只负责墨水形状。
              customBorder: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusLg),
              ),
              child: body,
            ),
    );
  }
}
