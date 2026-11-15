/// 书架筛选面板（文档 + 雷区 18）。
///
/// 由 [LibraryShell] 的筛选按钮唤起（替代原"功能暂未实现"桩），
/// 提供「排序 + 分类 + 状态 + 进度」四段筛选，点"应用"回传新的 [BookshelfFilter]。
library;

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../favorites/favorite_group.dart';
import '../models/bookshelf_filter.dart';
import '../models/plugin_config.dart';
import '../settings/layout_settings.dart';
import '../theme/app_tokens.dart';
import '../utils/app_haptics.dart';
import 'app_animations.dart';

/// 唤起书架筛选底部面板，返回用户确认后的筛选状态；取消则返回 null。
///
/// [sourceType] 决定可排序项（小说 6 项 / 漫画 5 项 / 媒体 6 项），"手动"项
/// 是否展示由当前布局模式（列表/网格）决定，因此本面板直接读取
/// [LayoutSettingsStore] 的当前布局。
Future<BookshelfFilter?> showBookshelfFilterSheet(
  BuildContext context, {
  required BookshelfFilter initialFilter,
  required List<String> categories,
  required SourceType sourceType,
  List<FavoriteGroup> groups = const <FavoriteGroup>[],
}) {
  return showModalBottomSheet<BookshelfFilter>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTokens.radiusLg),
      ),
    ),
    builder: (BuildContext ctx) => _BookshelfFilterSheet(
      initialFilter: initialFilter,
      categories: categories,
      sourceType: sourceType,
      groups: groups,
    ),
  );
}

class _BookshelfFilterSheet extends StatefulWidget {
  final BookshelfFilter initialFilter;
  final List<String> categories;
  final SourceType sourceType;
  final List<FavoriteGroup> groups;

  const _BookshelfFilterSheet({
    required this.initialFilter,
    required this.categories,
    required this.sourceType,
    required this.groups,
  });

  @override
  State<_BookshelfFilterSheet> createState() => _BookshelfFilterSheetState();
}

class _BookshelfFilterSheetState extends State<_BookshelfFilterSheet> {
  late BookshelfFilter _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
  }

  /// 切换分组 id 的选中态（多选并集语义，与分组栏共享同一状态）。
  void _toggleGroup(String id) {
    final Set<String> next = Set<String>.of(_filter.groupIds);
    if (!next.remove(id)) next.add(id);
    setState(() => _filter = _filter.copyWith(groupIds: next));
  }

  /// 按当前 [SourceType] 映射排序项文案。"最新"语义随类型变化：
  /// 小说=最新章、漫画=最新话、媒体(动漫)=最新。
  String _sortLabel(BookshelfSort sort, AppLocalizations l10n) {
    switch (sort) {
      case BookshelfSort.recent:
        return l10n.sortRecent;
      case BookshelfSort.title:
        return l10n.sortTitle;
      case BookshelfSort.author:
        return l10n.sortAuthor;
      case BookshelfSort.latestChapter:
        switch (widget.sourceType) {
          case SourceType.animeSource:
          case SourceType.videoSource:
          case SourceType.audioSource:
            return l10n.sortLatestUpdate;
          case SourceType.mangaSource:
            return l10n.sortLatestMangaChapter;
          case SourceType.novelSource:
            return l10n.sortLatestChapter;
        }
      case BookshelfSort.titleZh:
        return l10n.sortTitleZh;
      case BookshelfSort.director:
        return l10n.sortDirector;
      case BookshelfSort.actors:
        return l10n.sortActors;
      case BookshelfSort.manual:
        return l10n.sortManual;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

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
            _Handle(),
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              l10n.filterTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppTokens.spaceMd),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _Section(
                      label: l10n.sortBy,
                      children: <Widget>[
                        for (final BookshelfSort s in availableSortsFor(widget.sourceType))
                          // 「手动」仅在列表布局下有意义（网格拖拽为长按手势），故隐藏。
                          if (s != BookshelfSort.manual ||
                              LayoutSettingsStore.instance.settings.layoutMode ==
                                  LayoutMode.list)
                            _ChoiceChip(
                              label: _sortLabel(s, l10n),
                              selected: _filter.sort == s,
                              onSelected: (_) => setState(() => _filter =
                                  _filter.copyWith(sort: s)),
                            ),
                      ],
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    _Section(label: l10n.filterByStatus, children: <Widget>[
                      _ChoiceChip(
                        label: l10n.allLabel,
                        selected: _filter.status == null,
                        onSelected: (_) => setState(() =>
                            _filter = _filter.copyWith(status: null)),
                      ),
                      _ChoiceChip(
                        label: l10n.statusOngoing,
                        selected: _filter.status == l10n.statusOngoing,
                        onSelected: (_) => setState(() => _filter =
                            _filter.copyWith(status: l10n.statusOngoing)),
                      ),
                      _ChoiceChip(
                        label: l10n.statusCompleted,
                        selected: _filter.status == l10n.statusCompleted,
                        onSelected: (_) => setState(() => _filter =
                            _filter.copyWith(status: l10n.statusCompleted)),
                      ),
                    ]),
                    if (widget.categories.length > 1) ...<Widget>[
                      const SizedBox(height: AppTokens.spaceMd),
                      _Section(label: l10n.filterByCategory, children: <
                          Widget>[
                        _ChoiceChip(
                          label: l10n.allLabel,
                          selected: _filter.category == null,
                          onSelected: (_) => setState(() =>
                              _filter = _filter.copyWith(category: null)),
                        ),
                        ...widget.categories.map(
                          (String c) => _ChoiceChip(
                            label: c,
                            selected: _filter.category == c,
                            onSelected: (_) => setState(() =>
                                _filter = _filter.copyWith(category: c)),
                          ),
                        ),
                      ]),
                    ],
                    if (widget.groups.isNotEmpty) ...<Widget>[
                      const SizedBox(height: AppTokens.spaceMd),
                      _Section(label: l10n.filterByGroup, children: <Widget>[
                        _ChoiceChip(
                          label: l10n.groupAll,
                          selected: _filter.groupIds.isEmpty,
                          onSelected: (_) => setState(() => _filter = _filter
                              .copyWith(groupIds: const <String>{})),
                        ),
                        _ChoiceChip(
                          label: l10n.groupUngrouped,
                          selected:
                              _filter.groupIds.contains(kUngroupedId),
                          onSelected: (_) => _toggleGroup(kUngroupedId),
                        ),
                        ...widget.groups.map(
                          (FavoriteGroup g) => _ChoiceChip(
                            label: g.name,
                            selected: _filter.groupIds.contains(g.id),
                            onSelected: (_) => _toggleGroup(g.id),
                          ),
                        ),
                      ]),
                    ],
                    const SizedBox(height: AppTokens.spaceMd),
                    _Section(label: l10n.filterByProgress, children: <Widget>[
                      _ChoiceChip(
                        label: l10n.allLabel,
                        selected: _filter.progress == null,
                        onSelected: (_) => setState(() =>
                            _filter = _filter.copyWith(progress: null)),
                      ),
                      _ChoiceChip(
                        label: l10n.progressReading,
                        selected:
                            _filter.progress == BookshelfProgress.reading,
                        onSelected: (_) => setState(() => _filter =
                            _filter.copyWith(
                                progress: BookshelfProgress.reading)),
                      ),
                      _ChoiceChip(
                        label: l10n.progressNotStarted,
                        selected: _filter.progress ==
                            BookshelfProgress.notStarted,
                        onSelected: (_) => setState(() => _filter =
                            _filter.copyWith(
                                progress: BookshelfProgress.notStarted)),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppTokens.spaceMd),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _filter = _filter.reset()),
                    child: Text(l10n.filterReset),
                  ),
                ),
                const SizedBox(width: AppTokens.spaceSm),
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_filter),
                    child: Text(l10n.filterApply),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(bottom: AppTokens.spaceXs),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String label;
  final List<Widget> children;

  const _Section({required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: AppTokens.spaceXs),
        Wrap(
          spacing: AppTokens.spaceSm,
          runSpacing: AppTokens.spaceXs,
          children: children,
        ),
      ],
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (v) {
        AppHaptics.selectionClick();
        onSelected(v);
      },
    );
  }
}
