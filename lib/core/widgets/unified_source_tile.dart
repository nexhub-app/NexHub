import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import '../models/plugin_config.dart';
import '../theme/app_tokens.dart';
import '../utils/app_haptics.dart';
import 'app_icon_button.dart';

/// 源列表统一项（源管理页复用）。所有可见字符串来自 l10n。
class UnifiedSourceTile extends StatelessWidget {
  final String name;
  final String? url;
  final bool enabled;
  final bool deprecated;
  final bool isHidden;
  final bool useMoreMenu; // 源管理页：把操作收进「更多」菜单（其他页面保持内联）
  final String moreMenuTooltip; // 来自 l10n（「更多操作」）
  final String deprecatedLabel; // 来自 l10n
  final String mirrorSettingsTooltip; // 来自 l10n
  final String hideTooltip; // 来自 l10n
  final String unhideTooltip; // 来自 l10n
  final String editTooltip; // 来自 l10n
  final String varsTooltip; // 来自 l10n（书源变量编辑）
  final String deleteTooltip; // 来自 l10n
  final String migrateTooltip; // 来自 l10n
  final String networkOverrideTooltip; // 来自 l10n（「网络覆盖」）
  final String loginTooltip; // 来自 l10n（「源登录」）
  final String incognitoTooltip; // 来自 l10n（「无痕模式」）
  final String incognitoOnLabel; // 来自 l10n（「已无痕」，菜单项开启态文字）
  final bool isIncognito; // 该源是否已开启无痕
  final SourceAgeRating? ageRating; // 年龄分级（null/未声明不显示）
  final bool showNotLoggedIn; // 源需登录但尚未登录（显示「未登录」徽章）
  final VoidCallback? onTap;
  final VoidCallback? onMirrorSettings;
  final VoidCallback? onHide;
  final VoidCallback? onEdit;
  final VoidCallback? onVars;
  final VoidCallback? onDelete;
  final VoidCallback? onMigrate;
  final VoidCallback? onNetworkOverride; // 网络覆盖（走代理/自定义 Hosts 等）
  final VoidCallback? onLogin;
  final ValueChanged<bool>? onIncognitoToggle; // 切换无痕模式
  final ValueChanged<bool>? onToggle;
  const UnifiedSourceTile({
    super.key,
    required this.name,
    this.url,
    this.enabled = true,
    this.deprecated = false,
    this.isHidden = false,
    this.useMoreMenu = false,
    this.moreMenuTooltip = '',
    required this.deprecatedLabel,
    required this.mirrorSettingsTooltip,
    this.hideTooltip = '',
    this.unhideTooltip = '',
    this.editTooltip = '',
    this.varsTooltip = '',
    this.deleteTooltip = '',
    this.migrateTooltip = '',
    this.networkOverrideTooltip = '',
    this.loginTooltip = '',
    this.incognitoTooltip = '',
    this.incognitoOnLabel = '',
    this.isIncognito = false,
    this.ageRating,
    this.showNotLoggedIn = false,
    this.onTap,
    this.onMirrorSettings,
    this.onHide,
    this.onEdit,
    this.onVars,
    this.onDelete,
    this.onMigrate,
    this.onNetworkOverride,
    this.onLogin,
    this.onIncognitoToggle,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    // 标题独占一行（窄屏不再被 age/未登录 徽章挤压而截断）；徽章换行到标题下方。
    final Widget titleWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          name,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isHidden ? scheme.onSurfaceVariant : null,
              ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (ageRating != null || showNotLoggedIn) ...<Widget>[
          const SizedBox(height: AppTokens.spaceXxs),
          Wrap(
            spacing: AppTokens.spaceXs,
            runSpacing: AppTokens.spaceXxs,
            children: <Widget>[
              if (ageRating != null) _ageChip(context, scheme),
              if (showNotLoggedIn) _notLoggedInChip(context, scheme),
            ],
          ),
        ],
      ],
    );
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isHidden
              ? scheme.surfaceContainerHighest
              : scheme.primaryContainer,
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(
              color: isHidden
                  ? scheme.onSurfaceVariant
                  : scheme.onPrimaryContainer,
            ),
          ),
        ),
        title: titleWidget,
        trailing: _buildTrailing(scheme),
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: AppTokens.spaceLg),
      ),
    );
  }

  /// 年龄分级徽章：general=中性灰 / teen=琥珀 / mature=红（与设置页一致）。
  Widget _ageChip(BuildContext context, ColorScheme scheme) {
    final l10n = AppLocalizations.of(context);
    final (Color bg, Color fg, String label) = switch (ageRating!) {
      SourceAgeRating.general => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        l10n.ageRatingGeneral,
      ),
      SourceAgeRating.teen => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        l10n.ageRatingTeen,
      ),
      SourceAgeRating.mature => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        l10n.ageRatingMature,
      ),
    };
    return Chip(
      label: Text(label),
      backgroundColor: bg,
      labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      side: BorderSide.none,
    );
  }

  /// 未登录徽章（项 2）：源声明了登录入口但当前未登录时显示。
  Widget _notLoggedInChip(BuildContext context, ColorScheme scheme) {
    final l10n = AppLocalizations.of(context);
    return Chip(
      label: Text(l10n.sourceNotLoggedIn),
      backgroundColor: scheme.errorContainer,
      labelStyle: Theme.of(context)
          .textTheme
          .labelSmall
          ?.copyWith(color: scheme.onErrorContainer),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      side: BorderSide.none,
    );
  }

  /// 弃用徽章（两种模式共用）：点击触发迁移提示。
  Widget _deprecatedChip(ColorScheme scheme) => Padding(
        padding: const EdgeInsets.only(right: AppTokens.spaceSm),
        child: InkWell(
          onTap: onMigrate,
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          child: Chip(
            label: Text(deprecatedLabel,
                style: TextStyle(color: scheme.onErrorContainer, fontSize: 11)),
            backgroundColor: scheme.errorContainer,
            visualDensity: VisualDensity.compact,
          ),
        ),
      );

  bool get _hasMenuActions =>
      onMirrorSettings != null ||
      onEdit != null ||
      onVars != null ||
      onDelete != null ||
      onHide != null ||
      onMigrate != null ||
      onNetworkOverride != null ||
      onLogin != null ||
      onIncognitoToggle != null;

  PopupMenuEntry<String> _menuItem(
    String value,
    IconData icon,
    String text,
  ) =>
      PopupMenuItem<String>(
        value: value,
        child: Row(
          children: <Widget>[
            Icon(icon, size: 20),
            const SizedBox(width: AppTokens.spaceSm),
            Text(text),
          ],
        ),
      );

  List<PopupMenuEntry<String>> _buildMenuItems(BuildContext context) =>
      <PopupMenuEntry<String>>[
        if (onMirrorSettings != null)
          _menuItem('mirror', Icons.settings_ethernet_rounded, mirrorSettingsTooltip),
        if (onNetworkOverride != null)
          _menuItem('network', Icons.lan_rounded, networkOverrideTooltip),
        if (onLogin != null)
          _menuItem('login', Icons.login_rounded, loginTooltip),
        if (onIncognitoToggle != null)
          _menuItem(
              'incognito',
              Icons.privacy_tip_rounded,
              isIncognito ? incognitoOnLabel : incognitoTooltip),
        if (onEdit != null) _menuItem('edit', Icons.edit_rounded, editTooltip),
        if (onVars != null) _menuItem('vars', Icons.tune_rounded, varsTooltip),
        if (onDelete != null)
          _menuItem('delete', Icons.delete_rounded, deleteTooltip),
        if (onHide != null)
          _menuItem('hide', isHidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
              isHidden ? unhideTooltip : hideTooltip),
        if (onMigrate != null)
          _menuItem('migrate', Icons.upgrade_rounded, migrateTooltip),
      ];

  void _onMenuSelected(String value) {
    switch (value) {
      case 'mirror':
        onMirrorSettings?.call();
        break;
      case 'network':
        onNetworkOverride?.call();
        break;
      case 'login':
        onLogin?.call();
        break;
      case 'incognito':
        onIncognitoToggle?.call(!isIncognito);
        break;
      case 'edit':
        onEdit?.call();
        break;
      case 'vars':
        onVars?.call();
        break;
      case 'delete':
        onDelete?.call();
        break;
      case 'hide':
        onHide?.call();
        break;
      case 'migrate':
        onMigrate?.call();
        break;
    }
  }

  /// 右侧操作区。
  /// - [useMoreMenu]=true（源管理页）：开关保留，其余操作收进「更多」菜单；
  /// - 否则：保持原来的内联图标按钮（其他页面复用，行为不变）。
  Widget _buildTrailing(ColorScheme scheme) {
    if (useMoreMenu) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (deprecated) _deprecatedChip(scheme),
          if (onToggle != null)
            Switch(
              value: enabled,
              onChanged: (v) {
                v == true ? AppHaptics.toggleOn() : AppHaptics.toggleOff();
                onToggle!(v);
              },
            ),
          if (_hasMenuActions)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: scheme.onSurfaceVariant),
              tooltip: moreMenuTooltip,
              itemBuilder: _buildMenuItems,
              onSelected: _onMenuSelected,
            ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (deprecated) _deprecatedChip(scheme),
        if (onEdit != null)
          AppIconButton(
            icon: Icons.edit_rounded,
            tooltip: editTooltip,
            onPressed: onEdit,
          ),
        if (onDelete != null)
          AppIconButton(
            icon: Icons.delete_rounded,
            tooltip: deleteTooltip,
            onPressed: onDelete,
          ),
        if (onHide != null)
          AppIconButton(
            icon: isHidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
            tooltip: isHidden ? unhideTooltip : hideTooltip,
            onPressed: onHide,
          ),
        if (onMirrorSettings != null)
          AppIconButton(
            icon: Icons.settings_ethernet_rounded,
            tooltip: mirrorSettingsTooltip,
            onPressed: onMirrorSettings,
          ),
        if (onToggle != null)
          Switch(
            value: enabled,
            onChanged: (v) {
              v == true ? AppHaptics.toggleOn() : AppHaptics.toggleOff();
              onToggle!(v);
            },
          ),
      ],
    );
  }
}
