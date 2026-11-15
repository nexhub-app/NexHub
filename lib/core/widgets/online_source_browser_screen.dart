/// 在线源浏览页 —— 在线 Tab 的入口。
///
/// 展示当前模块所有已配置的源列表（图标 + 名称 + 地址 + 状态），
/// 点击某个源后进入该源的分类/内容浏览页（[OnlineContentListScreen]）。
///
/// 解决「无法浏览在线的源」的问题：用户可在此页直观地看到并选择要浏览的源。
library;

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/models/plugin_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_glass_bar.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/detail_action_utils.dart';
import '../../../core/services/source_repository.dart';

class OnlineSourceBrowserScreen extends StatelessWidget {
  /// 当前模块过滤类型
  final SourceType sourceType;
  final IconData emptyIcon;

  /// 点击某个源时的回调
  final void Function(PluginConfig source) onSourceTap;
  final VoidCallback? onAddSource;
  final VoidCallback? onEnableRecommended;

  /// 列表顶部前置的媒体服务器入口行（每台服务器一个）。
  /// 未配置服务器时传空列表 / null → 完全隐藏（在线列表回到纯源列表）。
  /// 仅需要的模块传入（当前为影视模块）。
  final List<Widget>? mediaServerTiles;

  const OnlineSourceBrowserScreen({
    super.key,
    required this.sourceType,
    this.emptyIcon = Icons.language_rounded,
    required this.onSourceTap,
    this.onAddSource,
    this.onEnableRecommended,
    this.mediaServerTiles,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final repo = context.watch<SourceRepository>();
    final sources = repo.byType(sourceType);
    final tiles = mediaServerTiles ?? const <Widget>[];

    final Widget body;
    if (sources.isEmpty && tiles.isEmpty) {
      body = AppEmptyState(
        icon: emptyIcon,
        message: l10n.emptySources,
        actionLabel: onEnableRecommended != null
            ? l10n.enableRecommendedSources
            : l10n.addSource,
        onAction: onEnableRecommended ?? onAddSource,
        secondaryActionLabel:
            onEnableRecommended != null ? l10n.addSource : null,
        onSecondaryAction: onEnableRecommended != null ? onAddSource : null,
      );
    } else {
      final Widget list = ListView.builder(
        // 行首图标可点：移动端避让玻璃底栏。
        padding:
            const EdgeInsets.all(AppTokens.spaceMd) + context.glassBarInset,
        itemCount: tiles.length + sources.length,
        itemBuilder: (context, i) {
          // 媒体服务器入口行前置（每台服务器一个；未配置时不占位）。
          if (i < tiles.length) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
              child: tiles[i],
            );
          }
          final int idx = i - tiles.length;
          final source = sources[idx];
          // 每行一段与面板同色的底色（常驻面板提供整体圆角，行段在此
          // 之上无缝相融），行间发丝分隔线。
          final bool first = idx == 0;
          final bool last = idx == sources.length - 1;
          return Material(
            color: AppTheme.cardContainer(scheme),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                top: first
                    ? const Radius.circular(AppTokens.radiusLg)
                    : Radius.zero,
                bottom: last
                    ? const Radius.circular(AppTokens.radiusLg)
                    : Radius.zero,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: <Widget>[
                if (!first)
                  const Divider(
                    height: 1,
                    thickness: 1,
                    indent: AppTokens.spaceLg,
                    endIndent: AppTokens.spaceLg,
                  ),
                ListTile(
                  onTap: () => _openSource(context, source),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceLg,
                    vertical: AppTokens.spaceXs,
                  ),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _sourceColor(source.type, scheme)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                    ),
                    child: Icon(
                      _sourceIcon(source.type),
                      color: _sourceColor(source.type, scheme),
                      size: 22,
                    ),
                  ),
                  title: Text(
                    source.name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: AppTokens.spaceXs),
                    child: Row(
                      children: <Widget>[
                        _buildStatusChip(source, scheme, l10n),
                        const SizedBox(width: AppTokens.spaceXs),
                        _buildAgeChip(source, scheme, l10n),
                      ],
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.open_in_new_rounded),
                    tooltip: l10n.openSourceWebsite,
                    onPressed: () => openInAppBrowser(
                        context, source.site.baseUrl,
                        source: source),
                  ),
                ),
              ],
            ),
          );
        },
      );
      // 视口圆角裁剪：滚动中屏幕边缘始终圆滑；卡底只由源行分段自绘——
      // 有源的地方铺色、没有的地方不铺（短列表贴合内容高度）。
      // 媒体服务器入口卡独立于源卡之外，不并入连体卡。
      body = ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        child: list,
      );
    }

    return body;
  }

  Widget _buildStatusChip(
      PluginConfig source, ColorScheme scheme, AppLocalizations l10n) {
    if (!source.isEnabled) {
      return Chip(
        label: Text(l10n.deprecated,
            style: TextStyle(fontSize: 11, color: scheme.error)),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero,
      );
    }
    if (source.isDeprecated) {
      return Chip(
        label: Text(l10n.deprecated,
            style: TextStyle(fontSize: 11, color: scheme.error)),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero,
      );
    }
    final Color healthy = AppStatusColors.ok(scheme);
    return Chip(
      label: Text(l10n.sourceHealthy,
          style: TextStyle(fontSize: 11, color: healthy)),
      backgroundColor: AppStatusColors.containerOf(healthy),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.zero,
    );
  }

  void _openSource(BuildContext context, PluginConfig source) {
    onSourceTap(source);
  }

  /// 年龄分级徽章（item 10）：general=中性灰 / teen=琥珀 / mature=红，与设置页一致。
  Widget _buildAgeChip(
      PluginConfig source, ColorScheme scheme, AppLocalizations l10n) {
    final (Color bg, Color fg, String label) = switch (source.ageRating) {
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
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: bg,
      labelStyle: TextStyle(color: fg, fontSize: 11),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      side: BorderSide.none,
      padding: EdgeInsets.zero,
    );
  }

  static Color _sourceColor(SourceType type, ColorScheme scheme) {
    if (type == SourceType.novelSource) return scheme.primary;
    if (type.isMediaFamily) return scheme.tertiary;
    return scheme.secondary; // mangaSource
  }

  static IconData _sourceIcon(SourceType type) {
    if (type == SourceType.novelSource) return Icons.menu_book_rounded;
    if (type == SourceType.videoSource) return Icons.movie_rounded;
    if (type == SourceType.audioSource) return Icons.headphones_rounded;
    if (type == SourceType.animeSource) return Icons.movie_rounded;
    return Icons.auto_stories_rounded; // mangaSource
  }
}
