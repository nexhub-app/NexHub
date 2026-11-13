/// 收藏分组管理面板。
///
/// 由分组栏「管理」入口唤起：列出全部分组（可拖拽重排），
/// 支持重命名 / 删除（二次确认，仅解除关联不删条目）/ 新建分组。
/// 样式对齐 [bookshelf_filter_sheet.dart]（拖条 / 顶圆角 / titleMedium 标题）。
library;

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../favorites/favorite_group.dart';
import '../favorites/favorites_manager.dart';
import '../models/plugin_config.dart';
import '../theme/app_tokens.dart';
import '../utils/app_haptics.dart';
import 'app_alert_dialog.dart';
import 'app_animations.dart';

/// 唤起分组管理底部面板。
Future<void> showFavoriteGroupManageSheet(
  BuildContext context, {
  required SourceType sourceType,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTokens.radiusLg),
      ),
    ),
    builder: (BuildContext ctx) =>
        _GroupManageSheet(sourceType: sourceType),
  );
}

/// 弹出分组名输入对话框（新建 / 重命名共用）。
///
/// [initialName] 非空表示重命名（用于豁免自身重名判定）。
/// 返回用户确认的合法名称；取消返回 null。
Future<String?> promptGroupName(
  BuildContext context, {
  required String title,
  String? initialName,
  required SourceType sourceType,
}) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final FavoritesManager manager = context.read<FavoritesManager>();
  final TextEditingController controller =
      TextEditingController(text: initialName ?? '');
  String? errorText;

  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        void submit() {
          final String name = controller.text.trim();
          if (name.isEmpty) {
            setState(() => errorText = l10n.groupNameEmpty);
            return;
          }
          final bool duplicate = manager
              .groupsFor(sourceType)
              .any((g) => g.name == name && g.name != initialName);
          if (duplicate) {
            setState(() => errorText = l10n.groupNameDuplicate);
            return;
          }
          Navigator.of(ctx).pop(name);
        }

        return AppAlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 20,
            decoration: InputDecoration(
              labelText: l10n.groupName,
              errorText: errorText,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              ),
            ),
            onSubmitted: (_) => submit(),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: submit,
              child: Text(l10n.confirm),
            ),
          ],
        );
      },
    ),
  );
}

class _GroupManageSheet extends StatelessWidget {
  final SourceType sourceType;

  const _GroupManageSheet({required this.sourceType});

  Future<void> _create(BuildContext context) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final FavoritesManager manager = context.read<FavoritesManager>();
    final String? name = await promptGroupName(
      context,
      title: l10n.newGroup,
      sourceType: sourceType,
    );
    if (name == null) return;
    await manager.createGroup(name, type: sourceType);
  }

  Future<void> _rename(BuildContext context, FavoriteGroup group) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final FavoritesManager manager = context.read<FavoritesManager>();
    final String? name = await promptGroupName(
      context,
      title: l10n.renameGroup,
      initialName: group.name,
      sourceType: sourceType,
    );
    if (name == null || name == group.name) return;
    await manager.renameGroup(group.id, name);
  }

  Future<void> _delete(BuildContext context, FavoriteGroup group) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final FavoritesManager manager = context.read<FavoritesManager>();
    final bool? ok = await showDialog<bool>(
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

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final FavoritesManager manager = context.watch<FavoritesManager>();
    final List<FavoriteGroup> groups =
        manager.groupsFor(sourceType, includeHidden: true);

    return AppSheetBody(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.spaceMd,
            AppTokens.spaceSm,
            AppTokens.spaceMd,
            AppTokens.spaceMd,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppTokens.spaceXs),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppTokens.spaceSm),
              Text(l10n.manageGroups, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppTokens.spaceMd),
              if (groups.isEmpty)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: AppTokens.spaceLg),
                  child: Text(
                    l10n.noGroups,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                Flexible(
                  child: ReorderableListView.builder(
                    shrinkWrap: true,
                    buildDefaultDragHandles: false,
                    onReorderStart: (_) => AppHaptics.thunk(),
                    itemCount: groups.length,
                    onReorderItem: (oldIndex, newIndex) {
                      final List<String> ids =
                          groups.map((g) => g.id).toList();
                      final String moved = ids.removeAt(oldIndex);
                      ids.insert(newIndex, moved);
                      manager.reorderGroups(ids, type: sourceType);
                    },
                    itemBuilder: (ctx, i) {
                      final FavoriteGroup g = groups[i];
                      return ListTile(
                        key: ValueKey<String>(g.id),
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
                              ? theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                )
                              : null,
                        ),
                        subtitle: Text(l10n.groupItemCount(
                            manager.entryCountInGroup(g.id, type: sourceType))),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            // 三个操作按钮并排，窄屏下用 compact 密度
                            // 让出宽度给分类名。
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: Icon(g.hidden
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded),
                              tooltip: g.hidden
                                  ? l10n.showCategory
                                  : l10n.hideCategory,
                              onPressed: () =>
                                  manager.setGroupHidden(g.id, !g.hidden),
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
                      );
                    },
                  ),
                ),
              const SizedBox(height: AppTokens.spaceMd),
              FilledButton.icon(
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.newGroup),
                onPressed: () => _create(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
