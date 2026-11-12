/// 设置子页公共组件。
///
/// 把散落在播放器 / 阅读器 / 布局 / 弹幕等设置页里重复的
/// "分组标题 + 滑块 + 开关 + 分段单选"代码收敛到一处，统一风格：
/// - [SettingsLeadingIcon]：动态主色图标瓦（入口行 leading）；
/// - [SettingsSection]：分组标题 + 可选说明；
/// - [SettingsCard]：带标题的卡片容器（圆角 + 阴影 + 统一内边距）；
/// - [SettingsSliderTile]：带当前值的滑块；
/// - [SettingsSwitchTile]：开关项；
/// - [SettingsSegmentedTile]：分段单选（SegmentedButton 包装）；
/// - [SettingsChoiceChips]：单选 Chip。
library;

import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../../../core/widgets/app_animations.dart';

/// 动态主色图标瓦：用于设置子页入口行的 leading。
///
/// 背景取 `primaryContainer`、图标取 `onPrimaryContainer`，随用户选择的
/// 种子色（Monet / 预设 / 自定义）实时变化，实现全设置层级色彩统一。
class SettingsLeadingIcon extends StatelessWidget {
  final IconData icon;
  final double iconSize;
  final double containerSize;

  const SettingsLeadingIcon({
    super.key,
    required this.icon,
    this.iconSize = 22,
    this.containerSize = 44,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: containerSize,
      height: containerSize,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Icon(icon, color: scheme.onPrimaryContainer, size: iconSize),
    );
  }
}

/// 分组标题（不含卡片背景）。用于卡片外部的独立小标题。
class SettingsSection extends StatelessWidget {
  final String title;
  final String? description;
  final EdgeInsetsGeometry? padding;

  const SettingsSection({
    super.key,
    required this.title,
    this.description,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding ??
          const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceXs,
            vertical: AppTokens.spaceXs,
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (description != null) ...<Widget>[
            const SizedBox(height: AppTokens.spaceXs),
            Text(
              description!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// 带标题的卡片容器。把所有同类设置项收进一个 [AppCard]，视觉分组更清晰。
///
/// 支持可展开/折叠：传 [expandable] = true（默认）时，标题栏可点击切换
/// 内容区的显示/隐藏，使用 [AnimatedSize] 实现平滑过渡动画。
class SettingsCard extends StatefulWidget {
  final String? title;
  final String? description;
  final List<Widget> children;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;

  /// 是否可展开/折叠（默认 true）。无标题时强制不展开。
  final bool expandable;

  /// 初始状态是否展开（默认 true）。仅在 [expandable] = true 时生效。
  final bool initiallyExpanded;

  /// 交错入场序列索引。传此值后卡片按 index*80ms 延迟入场。
  final int? index;

  const SettingsCard({
    super.key,
    this.title,
    this.description,
    required this.children,
    this.margin,
    this.backgroundColor,
    this.expandable = true,
    this.initiallyExpanded = true,
    this.index,
  });

  @override
  State<SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends State<SettingsCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasTitle = widget.title != null;
    final canExpand = widget.expandable && hasTitle;

    // 标题栏（可点击展开/折叠）
    final List<Widget> columnChildren = <Widget>[];
    if (hasTitle) {
      columnChildren.add(
        InkWell(
          onTap:
              canExpand ? () => setState(() => _expanded = !_expanded) : null,
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceXs),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.title!,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (widget.description != null) ...<Widget>[
                        const SizedBox(height: AppTokens.spaceXs),
                        Text(
                          widget.description!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (canExpand)
                  // 折叠箭头随展开状态平滑旋转（180°），点标题时有「翻开」的灵动感。
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: AppTokens.durBase,
                    curve: AppCurves.smooth,
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      if (canExpand) {
        columnChildren.add(
          AnimatedSize(
            duration: AppTokens.durBase,
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const SizedBox(height: AppTokens.spaceMd),
                      ..._spaced(widget.children, AppTokens.spaceMd),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        );
      } else {
        columnChildren.add(const SizedBox(height: AppTokens.spaceMd));
        columnChildren.add(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _spaced(widget.children, AppTokens.spaceMd),
          ),
        );
      }
    } else {
      // 无标题：直接显示内容，不可展开
      columnChildren.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _spaced(widget.children, AppTokens.spaceMd),
        ),
      );
    }

    // 「灵动」入场：设置卡片淡入 + 轻微上滑。onceKey 用 title 或 widget.key，
    // 保证同一卡片在生命周期内只播一次，避免滚动 / 重建时抖动重播。
    final String? onceKey = widget.title ?? widget.key?.toString();
    // 用 Material 而非 Container+DecoratedBox 承载背景色：内部 ListTile /
    // SwitchListTile 的最近 Material 祖先即本卡片，不会因「DecoratedBox 与
    // 最近 Material 之间夹了带色 DecoratedBox」而触发
    // "background color or ink splashes may be invisible" 断言（设置页洪水）。
    return Entrance(
      onceKey: onceKey,
      index: widget.index,
      offset: 16,
      fromScale: 0.97,
      duration: AppTokens.durSpring,
      child: Container(
        margin:
            widget.margin ?? const EdgeInsets.only(bottom: AppTokens.spaceLg),
        child: Material(
          color: widget.backgroundColor ??
              AppTheme.cardContainer(theme.colorScheme),
          // 柔和填充卡（Legado MD3 观感）：无描边无投影，靠色阶划界。
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: columnChildren,
            ),
          ),
        ),
      ),
    );
  }

  static List<Widget> _spaced(List<Widget> children, double gap) {
    if (children.isEmpty) return children;
    final List<Widget> out = <Widget>[children.first];
    for (var i = 1; i < children.length; i++) {
      out
        ..add(const SizedBox(height: AppTokens.spaceMd))
        ..add(children[i]);
    }
    return out;
  }
}

/// 带当前显示值的滑块。
class SettingsSliderTile extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  const SettingsSliderTile({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  @override
  State<SettingsSliderTile> createState() => _SettingsSliderTileState();
}

/// 有状态以记录拖动中已震过的档位，保证 MD3「逐档一次 tick」。
class _SettingsSliderTileState extends State<SettingsSliderTile> {
  int? _lastStep;

  void _onDrag(double v) {
    final int divisions = widget.divisions;
    if (divisions > 0) {
      final int step =
          ((v - widget.min) / (widget.max - widget.min) * divisions).round();
      if (step != _lastStep) {
        _lastStep = step;
        AppHaptics.tick();
      }
    }
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceXs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Expanded(
                  child: Text(widget.label, style: theme.textTheme.bodyMedium)),
              // 数值变化时轻弹一下，给「正在调」的即时反馈。
              AppValuePulse(
                trigger: widget.display,
                from: 0.7,
                child: Text(
                  widget.display,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ),
            ],
          ),
          Slider(
            value: widget.value,
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            onChanged: _onDrag,
            // MD3「Tick」：拖动跨过每一档刻度轻震一次（单档一次，不高频打扰），
            // 松手再轻震确认。官方规范：滑块按分档逐档 tick。
            onChangeEnd: (_) {
              _lastStep = null;
              AppHaptics.tick();
            },
          ),
        ],
      ),
    );
  }
}

/// 开关项。
class SettingsSwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingsSwitchTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // 切换时整行轻微弹性脉冲（力度收敛，避免大面积晃动）。
    return AppValuePulse(
      trigger: value,
      from: 0.94,
      child: SwitchListTile(
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle!) : null,
        value: value,
        // MD3「Toggle on/off」：开强关弱，与官方开关触感一致。
        onChanged: (v) {
          v ? AppHaptics.toggleOn() : AppHaptics.toggleOff();
          onChanged(v);
        },
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}

/// 分段单选（SegmentedButton 包装）。标题在上、选项在下。
class SettingsSegmentedTile<T extends Object> extends StatelessWidget {
  final String title;
  final String? description;
  final Set<T> selected;
  final void Function(Set<T>) onSelectionChanged;
  final List<ButtonSegment<T>> segments;
  final EdgeInsetsGeometry? margin;

  /// 是否自带卡框（默认 true，与历史行为一致）。传 false 时平铺渲染
  ///（标题小字 + 分段按钮，无 SettingsCard 包裹），用于嵌入已有卡片的
  /// 场景——与卡内其他行（文本框/开关）视觉统一，不出现「卡中卡」。
  final bool boxed;

  /// 选中段是否显示对勾图标（默认 true，MD3 标准行为）。
  /// 段数较多（≥4）时分段按钮宽度吃紧，可关掉对勾避免窄屏溢出。
  final bool showSelectedIcon;

  /// 段数多到窄屏放不下时是否允许横向滚动（默认 false，保持原布局）。
  final bool scrollable;

  const SettingsSegmentedTile({
    super.key,
    required this.title,
    this.description,
    required this.selected,
    required this.onSelectionChanged,
    required this.segments,
    this.margin,
    this.boxed = true,
    this.showSelectedIcon = true,
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    final Widget segmented = AppValuePulse(
      trigger: selected.isEmpty ? null : selected.first,
      from: 0.93,
      child: SegmentedButton<T>(
        selected: selected,
        showSelectedIcon: showSelectedIcon,
        onSelectionChanged: (selection) {
          // MD3「Selected」：单选组选中 → tick。
          AppHaptics.tick();
          onSelectionChanged(selection);
        },
        segments: segments,
      ),
    );
    // 段数多时允许横向滚动：窄屏下不出现 RenderFlex 溢出。
    final Widget segmentedView = scrollable
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: segmented,
          )
        : segmented;
    // 非卡框模式：平铺（标题/说明由本控件渲染，无卡中卡）。
    if (!boxed) {
      return Padding(
        padding: const EdgeInsets.only(top: AppTokens.spaceXxs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: AppTokens.spaceXs),
            segmentedView,
          ],
        ),
      );
    }
    return SettingsCard(
      title: title,
      description: description,
      margin: margin,
      children: <Widget>[segmentedView],
    );
  }
}

/// 单选 Chip 组。
class SettingsChoiceChips<T> extends StatelessWidget {
  final String title;
  final String? description;
  final T selected;
  final void Function(T) onSelected;
  final List<SettingsChoiceChipData<T>> options;
  final EdgeInsetsGeometry? margin;

  /// 是否自带卡框（默认 true，与历史行为一致）。传 false 时只渲染裸 chips
  ///（无 SettingsCard 包裹、无标题/说明），用于嵌入已有卡片的场景——
  /// 否则「卡中卡」会出现两层框。
  final bool boxed;

  const SettingsChoiceChips({
    super.key,
    required this.title,
    this.description,
    required this.selected,
    required this.onSelected,
    required this.options,
    this.margin,
    this.boxed = true,
  });

  @override
  Widget build(BuildContext context) {
    final Widget chips = Wrap(
      spacing: AppTokens.spaceSm,
      runSpacing: AppTokens.spaceXs,
      children: <Widget>[
        for (final opt in options)
          // 选中状态变化时该 Chip 弹一下（选中与取消都有反馈）。
          AppValuePulse(
            trigger: opt.value == selected,
            from: 0.9,
            child: ChoiceChip(
              label: Text(opt.label),
              selected: opt.value == selected,
              onSelected: (_) {
                // MD3「Selected」：chip 选中 → tick。
                AppHaptics.tick();
                onSelected(opt.value);
              },
            ),
          ),
      ],
    );
    // 非卡框模式：裸 chips（标题/说明由外层容器负责），无卡中卡。
    if (!boxed) {
      if (title.isEmpty) return chips;
      return Padding(
        padding: const EdgeInsets.only(top: AppTokens.spaceXxs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: AppTokens.spaceXs),
            chips,
          ],
        ),
      );
    }
    return SettingsCard(
      title: title,
      description: description,
      margin: margin,
      children: <Widget>[chips],
    );
  }
}

/// [SettingsChoiceChips] 的单选项。
class SettingsChoiceChipData<T> {
  final T value;
  final String label;
  const SettingsChoiceChipData({required this.value, required this.label});
}

/// 条件展开区域：依赖开关/选项显隐的子设置项组。
///
/// 包住「开启某开关后才会出现」的一组设置项，[visible] 变化时高度平滑
/// 过渡（[AnimatedSize]）+ 内容淡入上滑（[AnimatedSwitcher]），避免生硬
/// 地"啪"一下出现/消失，与卡片折叠手感一致。
class SettingsExpand extends StatelessWidget {
  final bool visible;
  final Widget child;

  /// 展开时内容区顶部留白（与卡片内其它项拉开距离）。
  final EdgeInsetsGeometry? padding;

  const SettingsExpand({
    super.key,
    required this.visible,
    required this.child,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: AppTokens.durBase,
      curve: AppCurves.smooth,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: AppTokens.durBase,
        switchInCurve: AppCurves.smooth,
        switchOutCurve: Curves.easeOutCubic,
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.04),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: visible
            ? Padding(
                key: const ValueKey<String>('settings-expand-open'),
                padding:
                    padding ?? const EdgeInsets.only(top: AppTokens.spaceMd),
                child: child,
              )
            : const SizedBox(
                key: ValueKey<String>('settings-expand-closed'),
                width: double.infinity,
              ),
      ),
    );
  }
}

/// 设置分组（Legado MD3 观感）：分组小标题 + **一张连体卡**。
///
/// 同一组的设置行合并进同一张圆角卡（「同一类连在一起」），行与行之间
/// 用 outlineVariant 发丝分隔线区隔；卡面比页面底色亮一档
/// （[AppTheme.cardContainer]）。小标题用 primary 强调色，左缘与行内图标对齐；
/// [header] 传 null 则只渲染卡（无标题）。
///
/// 行本身用 [SettingsTile]（不再自带卡底），键（搜索定位 ValueKey）可挂在
/// [SettingsGroup] 或具体行上。
class SettingsGroup extends StatelessWidget {
  final String? header;
  final List<Widget> children;

  const SettingsGroup({super.key, this.header, required this.children});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<Widget> cardChildren = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        cardChildren.add(
          // 发丝分隔线：随主题 outlineVariant，与行内图标左缘对齐后两侧留白。
          const Divider(
            height: 1,
            thickness: 1,
            indent: AppTokens.spaceLg,
            endIndent: AppTokens.spaceLg,
          ),
        );
      }
      cardChildren.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (header != null)
          Padding(
            padding: const EdgeInsets.only(
              left: AppTokens.spaceLg,
              top: AppTokens.spaceLg,
              bottom: AppTokens.spaceSm,
            ),
            child: Text(
              header!,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        Material(
          color: AppTheme.cardContainer(theme.colorScheme),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: cardChildren),
        ),
      ],
    );
  }
}

/// 设置行：组卡内的一行（自身不带卡底，Material 祖先由 [SettingsGroup] 提供）。
///
/// - 行高：有副标题最小 76、无副标题最小 64，内容垂直居中；
/// - 强调色层次：图标与分组小标题同为 primary（Legado 截图的锈棕图标），
/// 标题 onSurface、副标题 onSurfaceVariant、chevron 再浅一档；
/// - [trailing] 缺省且 [onTap] 非空时，自动渲染 chevron_right_rounded；
/// 需要放开关等自定义控件时显式传 [trailing] 且不传 [onTap]。
class SettingsTile extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const SettingsTile({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    final Widget row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: subtitle == null ? 64 : 76),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceLg,
          vertical: AppTokens.spaceMd,
        ),
        child: Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 22, color: scheme.primary),
              const SizedBox(width: AppTokens.spaceLg),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(title, style: text.titleMedium),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: AppTokens.spaceXxs),
                    Text(
                      subtitle!,
                      style: text.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            // chevron 比标题浅一档；仅交互/选中态用 primary 由图标承担。
            if (trailing != null)
              trailing!
            else if (onTap != null)
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
          ],
        ),
      ),
    );

    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}
