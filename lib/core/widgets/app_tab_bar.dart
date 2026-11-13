import 'package:material_ui/material_ui.dart';
import '../theme/app_tokens.dart';
import '../utils/app_haptics.dart';

/// 顶部 Tab 项定义（图标 + 文字，文字来自 l10n）。
class AppTabItem {
  final IconData icon;
  final String label; // 来自 l10n
  const AppTabItem({required this.icon, required this.label});
}

/// 顶部 TabBar 唯一真源：图标在上、文字在下、选中下划线指示器。
///
/// [compact] 为紧凑模式：**只显示文字**（无图标）、按下划线宽度收缩、指示器
/// 更细，用于二级页面里的「分类」页签（如源库查看页的小说/媒体/漫画），避免
/// 一整条大图标 Tab 压掉内容区的可视高度。默认（false）保持全局大 Tab 版式。
class AppTabBar extends StatelessWidget implements PreferredSizeWidget {
  final TabController controller;
  final List<AppTabItem> items;
  final bool compact;
  const AppTabBar({
    super.key,
    required this.controller,
    required this.items,
    this.compact = false,
  });

  /// 紧凑高度：纯文字 Tab 的行高 46 + 指示器 2（与 TabBar 内部
  /// `_kTabHeight + indicatorWeight` 精确对齐，超出会被裁切）。
  static const double _compactHeight = 48;

  @override
  Size get preferredSize =>
      Size.fromHeight(compact ? _compactHeight : AppTokens.tabBarHeight);

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextStyle? compactLabel =
        compact ? Theme.of(context).textTheme.labelLarge : null;
    return TabBar(
      controller: controller,
      // MD3「Selected」：页签单选 → tick。
      onTap: (_) => AppHaptics.tick(),
      dividerColor: scheme.outlineVariant,
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.onSurfaceVariant,
      labelStyle: compactLabel,
      unselectedLabelStyle: compactLabel,
      labelPadding:
          compact ? const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd) : null,
      indicatorSize: compact ? TabBarIndicatorSize.label : TabBarIndicatorSize.tab,
      indicator: UnderlineTabIndicator(
        borderSide:
            BorderSide(color: scheme.primary, width: compact ? 2 : 3),
        // 圆角处理，使下划线更像「灵动」小药丸。
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        insets: EdgeInsets.symmetric(
          horizontal: compact ? AppTokens.spaceSm : AppTokens.spaceLg,
        ),
      ),
      tabs: compact
          ? items.map((AppTabItem e) => Tab(text: e.label)).toList()
          : items
              .map((AppTabItem e) => Tab(icon: Icon(e.icon), text: e.label))
              .toList(),
    );
  }
}
