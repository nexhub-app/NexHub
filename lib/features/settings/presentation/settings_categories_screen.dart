/// 分类管理页（阶段）—— 管理动漫/漫画/小说三模块的收藏分类。
///
/// - 顶部三段 Tab（媒体 / 漫画 / 小说），切换各自模块的分类。
/// - 列表：拖拽排序 + 重命名 + 删除（二次确认，仅解除关联不删条目）+ 显隐。
/// - 底部「新建分类」按钮；长按行可进入重命名 / 删除（同现有分组管理面板）。
///
/// 数据来自 [FavoritesManager]（`favorite_groups_v1`），分类即收藏分组
/// （[FavoriteGroup] 多分组标签模型，与站点题材 [FavoriteEntry.category] 区分）。
library;

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/favorites/favorite_group.dart';
import '../../../core/favorites/favorites_manager.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/app_alert_dialog.dart';
import '../../../core/widgets/app_animations.dart';
import '../../../core/widgets/app_glass_bar.dart';
import '../../../core/widgets/app_segmented_tabs.dart';
import '../../../core/widgets/favorite_group_manage_sheet.dart'
    show promptGroupName;

/// 分类管理页（从设置主页「分类管理」入口进入）。
class SettingsCategoriesScreen extends StatefulWidget {
  const SettingsCategoriesScreen({super.key});

  @override
  State<SettingsCategoriesScreen> createState() =>
      _SettingsCategoriesScreenState();
}

class _SettingsCategoriesScreenState extends State<SettingsCategoriesScreen> {
  SourceType _type = SourceType.novelSource;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final manager = context.watch<FavoritesManager>();
    final groups = manager.groupsFor(_type, includeHidden: true);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.categoriesManageTitle)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.spaceLg,
              AppTokens.spaceSm,
              AppTokens.spaceLg,
               0,
            ),
            child: AppSegmentedTabs<SourceType>(
              selected: <SourceType>{_type},
              onSelectionChanged: (Set<SourceType> s) {
                if (s.isEmpty) return;
                setState(() => _type = s.first);
              },
              segments: <ButtonSegment<SourceType>>[
                ButtonSegment<SourceType>(
                  value: SourceType.novelSource,
                  label: Text(l10n.navNovel),
                  icon: const Icon(Icons.menu_book_rounded),
                ),
                ButtonSegment<SourceType>(
                  value: SourceType.animeSource,
                  label: Text(l10n.navMedia),
                  icon: const Icon(Icons.movie_rounded),
                ),
                ButtonSegment<SourceType>(
                  value: SourceType.mangaSource,
                  label: Text(l10n.navComic),
                  icon: const Icon(Icons.auto_stories_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Expanded(
            child: groups.isEmpty
                ? _EmptyState(l10n: l10n)
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    onReorderStart: (_) => AppHaptics.thunk(),
padding: EdgeInsets.fromLTRB(
                      AppTokens.spaceLg,
                      AppTokens.spaceXs,
                      AppTokens.spaceLg,
                      AppTokens.spaceLg + context.glassBarBottomInset,
                    ),
                    itemCount: groups.length,
                    onReorderItem: (oldIndex, newIndex) {
                      final ids = groups.map((g) => g.id).toList();
                      final moved = ids.removeAt(oldIndex);
                      ids.insert(newIndex, moved);
                      manager.reorderGroups(ids, type: _type);
                    },
                    itemBuilder: (ctx, i) {
                      final g = groups[i];
                      return Entrance(
                        key: ValueKey<String>(g.id),
                        onceKey: 'category_item_${g.id}',
                        index: i,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: ReorderableDragStartListener(
                            index: i,
                            child: const Icon(Icons.drag_handle_rounded),
                          ),
                          title: Text(
                            g.hidden
                                ? '${g.name}（${l10n.categoryHidden}）'
                                : g.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: g.hidden
                                ? Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    )
                                : null,
                          ),
                          subtitle: Text(l10n.groupItemCount(
                              manager.entryCountInGroup(g.id, type: _type))),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: Icon(
                                  g.hidden
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                ),
                                tooltip: g.hidden
                                    ? l10n.showCategory
                                    : l10n.hideCategory,
                                onPressed: () => manager
                                    .setGroupHidden(g.id, !g.hidden),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.edit_rounded),
                                tooltip: l10n.renameGroup,
                                onPressed: () => _rename(context, g),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.delete_rounded),
                                tooltip: l10n.deleteGroup,
                                onPressed: () => _delete(context, g),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.spaceLg,
              AppTokens.spaceXs,
              AppTokens.spaceLg,
              AppTokens.spaceLg,
            ),
            child: FilledButton.icon(
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.newGroup),
              onPressed: () => _create(context),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final manager = context.read<FavoritesManager>();
    final name = await promptGroupName(
      context,
      title: l10n.newGroup,
      sourceType: _type,
    );
    if (name == null) return;
    await manager.createGroup(name, type: _type);
  }

  Future<void> _rename(BuildContext context, FavoriteGroup group) async {
    final l10n = AppLocalizations.of(context);
    final manager = context.read<FavoritesManager>();
    final name = await promptGroupName(
      context,
      title: l10n.renameGroup,
      initialName: group.name,
      sourceType: _type,
    );
    if (name == null || name == group.name) return;
    await manager.renameGroup(group.id, name);
  }

  Future<void> _delete(BuildContext context, FavoriteGroup group) async {
    final l10n = AppLocalizations.of(context);
    final manager = context.read<FavoritesManager>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(l10n.deleteGroup),
        // 明确告知仅解除关联，收藏条目本身保留。
        content: Text(l10n.deleteGroupConfirm(group.name)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (ok == true) await manager.deleteGroup(group.id);
  }
}

/// 空态：当前模块没有任何分类。
class _EmptyState extends StatelessWidget {
  final AppLocalizations l10n;

  const _EmptyState({required this.l10n});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.space2xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.folder_open_rounded,
              size: 56,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: AppTokens.spaceMd),
            Text(
              l10n.noGroups,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}