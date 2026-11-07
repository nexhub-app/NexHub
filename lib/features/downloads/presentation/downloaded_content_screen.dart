/// 已下载内容页 —— 新版设计：支持按类型筛选（全部/小说/媒体/漫画/已删除）。
library;

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/download/download_manager.dart';
import '../../../core/download/download_task.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_cover_image.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_segmented_tabs.dart';
import '../../../core/widgets/layout_picker_button.dart';
import '../../../core/settings/layout_settings.dart';
import '../../../core/utils/app_haptics.dart';
import 'downloaded_group_screen.dart';
import 'package:nexhub/core/navigation/app_page_route.dart';
import 'package:nexhub/core/widgets/app_alert_dialog.dart';
import '../../../core/widgets/app_glass_bar.dart';

enum _DownloadedTab { all, novel, media, comic, archived }

/// 已下载内容页 —— 带类型 Tab 筛选和网格视图。
class DownloadedContentScreen extends StatefulWidget {
  const DownloadedContentScreen({super.key});

  @override
  State<DownloadedContentScreen> createState() =>
      _DownloadedContentScreenState();
}

class _DownloadedContentScreenState extends State<DownloadedContentScreen> {
  _DownloadedTab _tab = _DownloadedTab.all;
  bool _selectMode = false;
  final Set<String> _selectedKeys = <String>{};

  List<DownloadTask> _getFilteredTasks(DownloadManager manager) {
    final completed = manager.completedTasks;
    switch (_tab) {
      case _DownloadedTab.all:
        return completed;
      case _DownloadedTab.novel:
        return completed
            .where((t) => t.sourceType == SourceType.novelSource)
            .toList();
      case _DownloadedTab.media:
        return completed
            .where((t) => t.sourceType == SourceType.animeSource)
            .toList();
      case _DownloadedTab.comic:
        return completed
            .where((t) => t.sourceType == SourceType.mangaSource)
            .toList();
      case _DownloadedTab.archived:
        return manager.archivedTasks;
    }
  }

  /// 把已下载/已归档任务按作品（同源同 contentId）合并为分组，供卡片展示。
  List<DownloadGroup> _getGroupedTasks(DownloadManager manager) {
    final List<DownloadTask> filtered = _getFilteredTasks(manager);
    // 已合并分组已在 DownloadManager 内按可见状态聚合；这里统一走分组入口。
    return _tab == _DownloadedTab.archived
        ? manager.groupedArchived()
        : manager
            .groupedDownloaded()
            .where((g) => filtered.any(
                (t) => t.contentId == g.contentId && t.sourceId == g.sourceId))
            .toList();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final manager = context.watch<DownloadManager>();
    final groups = _getGroupedTasks(manager);
    final isArchivedTab = _tab == _DownloadedTab.archived;
    // 选择模式以「作品分组」为单位（一个 contentId+sourceId 一选），更贴合合并展示。
    final int selectTotal = groups.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectMode
            ? '${_selectedKeys.length} / $selectTotal'
            : l10n.downloadedContent),
        actions: <Widget>[
          if (!_selectMode) ...<Widget>[
            const LayoutPickerButton(),
            // 筛选：与顶部类型 Tab 联动的弹窗式快速筛选（底部弹窗风格）。
            IconButton(
              icon: const Icon(Icons.filter_list_rounded),
              tooltip: l10n.filter,
              onPressed: () => showDownloadedFilterSheet(
                context,
                initial: _tab,
                onApply: (value) => setState(() {
                  _tab = value;
                  _selectMode = false;
                  _selectedKeys.clear();
                }),
              ),
            ),
          ],
          if (_selectMode) ...<Widget>[
            IconButton(
              icon: const Icon(Icons.select_all_rounded),
              tooltip: l10n.selectAll,
              onPressed: () => setState(() {
                _selectedKeys.addAll(groups.map((g) => g.contentId).toSet());
              }),
            ),
            IconButton(
              icon: const Icon(Icons.delete_rounded),
              tooltip: l10n.delete,
              onPressed: _selectedKeys.isEmpty
                  ? null
                  : () => _confirmDelete(context, manager, l10n),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: l10n.cancel,
              onPressed: () => setState(() {
                _selectMode = false;
                _selectedKeys.clear();
              }),
            ),
          ] else if (groups.isNotEmpty && !isArchivedTab) ...<Widget>[
            // Archived tab uses per-card action buttons instead of select mode.
            IconButton(
              icon: const Icon(Icons.checklist_rounded),
              tooltip: l10n.select,
              onPressed: () => setState(() => _selectMode = true),
            ),
          ],
        ],
      ),
      body: Column(
        children: <Widget>[
          // 类型筛选 Tab
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceLg,
              vertical: AppTokens.spaceSm,
            ),
            child: AppSegmentedTabs<_DownloadedTab>(
              selected: <_DownloadedTab>{_tab},
              onSelectionChanged: (Set<_DownloadedTab> s) {
                setState(() {
                  _tab = s.first;
                  _selectMode = false;
                  _selectedKeys.clear();
                });
              },
              segments: <ButtonSegment<_DownloadedTab>>[
                ButtonSegment<_DownloadedTab>(
                    value: _DownloadedTab.all,
                    label: Text(l10n.downloadedTabsAll)),
                ButtonSegment<_DownloadedTab>(
                    value: _DownloadedTab.novel,
                    label: Text(l10n.downloadedTabsNovel)),
                ButtonSegment<_DownloadedTab>(
                    value: _DownloadedTab.media,
                    label: Text(l10n.downloadedTabsMedia)),
                ButtonSegment<_DownloadedTab>(
                    value: _DownloadedTab.comic,
                    label: Text(l10n.downloadedTabsComic)),
                ButtonSegment<_DownloadedTab>(
                    value: _DownloadedTab.archived,
                    label: Text(l10n.downloadedTabsArchived)),
              ],
            ),
          ),

          // 内容区（随布局设置实时变化：网格列数/间距 ↔ 列表模式）
          Expanded(
            child: groups.isEmpty
                ? AppEmptyState(
                    icon: isArchivedTab
                        ? Icons.archive_rounded
                        : Icons.download_done_rounded,
                    message: isArchivedTab
                        ? l10n.archivedEmpty
                        : l10n.emptyDownloaded,
                  )
                : ListenableBuilder(
                    listenable: LayoutSettingsStore.instance,
                    builder: (BuildContext context, _) {
                      final LayoutSettings layout =
                          LayoutSettingsStore.instance.settings;
                      if (layout.layoutMode == LayoutMode.list) {
                        // 列表模式：横向卡片
                        return ListView.separated(
                          padding: context.pageInset(AppTokens.spaceMd),
                          itemCount: groups.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: AppTokens.spaceSm),
                          itemBuilder: (context, i) => _buildCard(
                            groups[i],
                            isArchivedTab,
                            manager,
                            l10n,
                            listMode: true,
                          ),
                        );
                      }
                      // 网格模式：按设置列数/间距渲染，高宽比跟随标题/作者开关
                      return GridView.builder(
                        padding: context.pageInset(AppTokens.spaceMd),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: layout.gridColumns.clamp(1, 8),
                          childAspectRatio: _gridAspectRatio(layout),
                          crossAxisSpacing: layout.gridSpacing,
                          mainAxisSpacing: layout.gridSpacing,
                        ),
                        itemCount: groups.length,
                        itemBuilder: (context, i) => _buildCard(
                          groups[i],
                          isArchivedTab,
                          manager,
                          l10n,
                          listMode: false,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 根据布局设置计算网格卡片高宽比（封面 + 可变文本区）。
  double _gridAspectRatio(LayoutSettings layout) {
    // 封面区域固定占比约 0.65（3:2 封面+文字）
    final baseRatio = 0.65;
    if (layout.showTitle) return baseRatio; // 有标题时标准比例
    if (layout.showAuthor) return 0.72; // 无标题有作者，稍长
    return 0.58; // 全隐藏，更偏方形（接近纯封面）
  }

  /// 已下载页筛选已改为文件底部的 [showDownloadedFilterSheet]（底部弹窗）。

  /// 根据当前选择状态构建已下载卡片（列表/网格模式共用）。
  ///
  /// [group] 为同一部作品的合并分组；选择模式以 contentId 为单位。
  Widget _buildCard(
    DownloadGroup group,
    bool isArchivedTab,
    DownloadManager manager,
    AppLocalizations l10n, {
    required bool listMode,
  }) {
    final bool isSelected = _selectedKeys.contains(group.contentId);
    return _DownloadedCard(
      group: group,
      listMode: listMode,
      selectMode: _selectMode,
      isSelected: isSelected,
      isArchived: isArchivedTab,
      onTap: () {
        if (_selectMode) {
          setState(() {
            if (isSelected) {
              _selectedKeys.remove(group.contentId);
            } else {
              _selectedKeys.add(group.contentId);
            }
          });
        } else if (!isArchivedTab) {
          Navigator.of(context).push(
            AppPageRoute<void>(
              builder: (_) => DownloadedGroupScreen(
                contentId: group.contentId,
                sourceId: group.sourceId,
              ),
            ),
          );
        }
      },
      onLongPress: () {
        if (!_selectMode && !isArchivedTab) {
          AppHaptics.thunk(); // MD3「Thunk」：长按进入多选模式。
          setState(() {
            _selectMode = true;
            _selectedKeys.add(group.contentId);
          });
        }
      },
      onRestore: isArchivedTab
          ? () => _restoreTask(context, manager, l10n, group.contentId)
          : null,
      onDeletePermanently: isArchivedTab
          ? () =>
              _confirmDeletePermanently(context, manager, l10n, group.contentId)
          : null,
    );
  }

  void _confirmDelete(
    BuildContext context,
    DownloadManager manager,
    AppLocalizations l10n,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(l10n.delete),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.deleteConfirm),
            const SizedBox(height: AppTokens.spaceXs),
            Text(
              l10n.archivedHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              for (final id in _selectedKeys) {
                manager.archiveContent(id);
              }
              setState(() {
                _selectMode = false;
                _selectedKeys.clear();
              });
              Navigator.pop(ctx);
            },
            child: Text(l10n.deleteRecordOnly),
          ),
          FilledButton(
            onPressed: () {
              for (final id in _selectedKeys) {
                manager.cancelContent(id, deleteFiles: true);
              }
              setState(() {
                _selectMode = false;
                _selectedKeys.clear();
              });
              Navigator.pop(ctx);
            },
            child: Text(l10n.deleteRecordAndFile),
          ),
        ],
      ),
    );
  }

  /// Restore a single archived work (all its batches) and show a SnackBar confirmation.
  void _restoreTask(
    BuildContext context,
    DownloadManager manager,
    AppLocalizations l10n,
    String contentId,
  ) {
    manager.unarchiveContent(contentId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.restoreSuccess)),
    );
  }

  /// Permanently delete a single archived work (all its batches) with confirmation dialog.
  void _confirmDeletePermanently(
    BuildContext context,
    DownloadManager manager,
    AppLocalizations l10n,
    String contentId,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(l10n.deletePermanently),
        content: Text(l10n.deleteConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              manager.cancelContent(contentId, deleteFiles: true);
              Navigator.pop(ctx);
            },
            child: Text(l10n.deletePermanently),
          ),
        ],
      ),
    );
  }
}

class _DownloadedCard extends StatelessWidget {
  final bool selectMode;
  final bool isSelected;
  final bool isArchived;
  final bool listMode;
  final DownloadGroup group;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onRestore;
  final VoidCallback? onDeletePermanently;

  const _DownloadedCard({
    required this.group,
    required this.selectMode,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    this.isArchived = false,
    this.listMode = false,
    this.onRestore,
    this.onDeletePermanently,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final AppLocalizations l10n = AppLocalizations.of(context);
    // 全部跟随布局设置（与在线浏览页 ContentCard / ListItem 一致）。
    final LayoutSettings layout = LayoutSettingsStore.instance.settings;
    final double radius = layout.coverRadius;

    final Widget body = listMode
        ? Row(
            children: <Widget>[
              SizedBox(
                width: 64,
                height: 90,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    AppCoverImage(
                      coverUrl: group.coverUrl,
                      fit: BoxFit.cover,
                      radius: radius,
                    ),
                    if (isArchived)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer,
                            borderRadius:
                                BorderRadius.circular(AppTokens.radiusXs),
                          ),
                          child: Text(
                            l10n.statusArchived,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: scheme.onSecondaryContainer),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppTokens.spaceSm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (layout.showTitle)
                        Text(
                          group.title,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontSize: layout.titleFontSize),
                          maxLines: layout.titleMaxLines,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const Spacer(),
                      _metaRow(context, scheme, l10n, layout),
                    ],
                  ),
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    AppCoverImage(
                      coverUrl: group.coverUrl,
                      fit: BoxFit.cover,
                      radius: radius,
                    ),
                    if (isArchived)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer,
                            borderRadius:
                                BorderRadius.circular(AppTokens.radiusXs),
                          ),
                          child: Text(
                            l10n.statusArchived,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: scheme.onSecondaryContainer),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (layout.showTitle)
                        Text(
                          group.title,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontSize: layout.titleFontSize),
                          maxLines: layout.titleMaxLines,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const Spacer(),
                      _metaRow(context, scheme, l10n, layout),
                    ],
                  ),
                ),
              ),
            ],
          );

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        children: <Widget>[
          Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius),
            ),
            child: body,
          ),
          if (selectMode && isSelected)
            Positioned(
              top: 4,
              right: 4,
              child: CircleAvatar(
                radius: 12,
                backgroundColor: scheme.primary,
                child: Icon(Icons.check_rounded,
                    size: 16, color: scheme.onPrimary),
              ),
            ),
        ],
      ),
    );
  }

  /// 底部元信息行：归档态显示「恢复 / 彻底删除」操作，普通态显示合并章节数。
  /// 同作品跨多批下载时，额外提示批次数量。
  /// [layout] 用于判断是否显示作者/章节数信息（showAuthor）。
  Widget _metaRow(
      BuildContext context, ColorScheme scheme, AppLocalizations l10n,
      [LayoutSettings? layout]) {
    if (isArchived && onRestore != null && onDeletePermanently != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.restore_rounded),
            tooltip: l10n.restore,
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: onRestore,
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever_rounded),
            tooltip: l10n.deletePermanently,
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: onDeletePermanently,
          ),
        ],
      );
    }
    // showAuthor 关闭时隐藏章节数/作者信息
    if (layout != null && !layout.showAuthor) return const SizedBox.shrink();
    final int chapters = group.chapterTitles.length;
    final String base = group.sourceType == SourceType.mangaSource
        ? l10n.chapterN(chapters)
        : group.sourceType == SourceType.novelSource
            ? l10n.novelChapterN(chapters)
            : l10n.episodeN(chapters);
    final String suffix = group.batches.length > 1
        ? ' · ${l10n.downloadBatches(group.batches.length)}'
        : '';
    return Text(
      '$base$suffix',
      style: Theme.of(context)
          .textTheme
          .labelSmall
          ?.copyWith(color: scheme.onSurfaceVariant),
    );
  }
}

/// 已下载页筛选底部弹窗：与顶部类型 Tab 联动，选中后回写 [_tab]。
///
/// 风格与 [showOnlineFilterSheet] 一致（modal bottom sheet + 单选行 + 应用按钮）。
Future<void> showDownloadedFilterSheet(
  BuildContext context, {
  required _DownloadedTab initial,
  required ValueChanged<_DownloadedTab> onApply,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTokens.radiusLg),
      ),
    ),
    builder: (ctx) => _DownloadedFilterSheet(
      initial: initial,
      onApply: onApply,
    ),
  );
}

class _DownloadedFilterSheet extends StatefulWidget {
  const _DownloadedFilterSheet({
    required this.initial,
    required this.onApply,
  });

  final _DownloadedTab initial;
  final ValueChanged<_DownloadedTab> onApply;

  @override
  State<_DownloadedFilterSheet> createState() => _DownloadedFilterSheetState();
}

class _DownloadedFilterSheetState extends State<_DownloadedFilterSheet> {
  late _DownloadedTab _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  String _label(AppLocalizations l10n, _DownloadedTab tab) => switch (tab) {
        _DownloadedTab.all => l10n.downloadedTabsAll,
        _DownloadedTab.novel => l10n.downloadedTabsNovel,
        _DownloadedTab.media => l10n.downloadedTabsMedia,
        _DownloadedTab.comic => l10n.downloadedTabsComic,
        _DownloadedTab.archived => l10n.downloadedTabsArchived,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppTokens.spaceLg,
          right: AppTokens.spaceLg,
          top: AppTokens.spaceMd,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppTokens.spaceMd,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(l10n.filter, style: theme.textTheme.titleMedium),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              const Divider(),
              _FilterRow(
                label: _label(l10n, _DownloadedTab.all),
                selected: _selected == _DownloadedTab.all,
                onTap: () => setState(() => _selected = _DownloadedTab.all),
              ),
              _FilterRow(
                label: _label(l10n, _DownloadedTab.novel),
                selected: _selected == _DownloadedTab.novel,
                onTap: () => setState(() => _selected = _DownloadedTab.novel),
              ),
              _FilterRow(
                label: _label(l10n, _DownloadedTab.media),
                selected: _selected == _DownloadedTab.media,
                onTap: () => setState(() => _selected = _DownloadedTab.media),
              ),
              _FilterRow(
                label: _label(l10n, _DownloadedTab.comic),
                selected: _selected == _DownloadedTab.comic,
                onTap: () => setState(() => _selected = _DownloadedTab.comic),
              ),
              _FilterRow(
                label: _label(l10n, _DownloadedTab.archived),
                selected: _selected == _DownloadedTab.archived,
                onTap: () =>
                    setState(() => _selected = _DownloadedTab.archived),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    widget.onApply(_selected);
                    Navigator.of(context).maybePop();
                  },
                  child: Text(l10n.filterApply),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 筛选单选行：label + 选中勾。
class _FilterRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = selected ? scheme.primary : scheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppTokens.spaceXs,
          horizontal: AppTokens.spaceSm,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_rounded, size: 18, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}
