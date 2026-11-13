/// 书架内容组件（文档 书架 Tab）。
///
/// 在 LibraryShell 的 library 顶部 Tab 下渲染，
/// 根据 sub-tab（本地 / 历史 / 收藏）显示不同数据源：
/// - 本地：DownloadManager.completedTasks（已下载内容）
/// - 历史：HistoryManager（最近浏览）
/// - 收藏：FavoritesManager（收藏夹）
///
/// 三模块共用，通过 [sourceType] 过滤数据，通过 [filter] 应用筛选/排序。
library;

import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import '../download/download_manager.dart';
import '../download/download_task.dart';
import '../favorites/favorite_group.dart';
import '../favorites/favorites_manager.dart';
import '../history/history_manager.dart';
import '../local/local_content_manager.dart';
import '../local/local_content_actions.dart';
import '../models/bookshelf_filter.dart';
import '../models/bookshelf_manual_order.dart';
import '../models/media_item.dart';
import '../models/plugin_config.dart';
import '../services/source_repository.dart';
import '../settings/layout_settings.dart';
import '../utils/chinese_collation.dart';
import '../history/media_watched_manager.dart';
import '../novel/novel_progress_manager.dart';
import '../novel/novel_toc_cache.dart';
import '../comic/comic_progress_manager.dart';
import 'app_card.dart';
import 'app_cover_image.dart';
import 'app_empty_state.dart';
import 'app_glass_bar.dart';
import 'bangumi_bind_sheet.dart';
import 'content_card.dart';
import 'favorite_group_assign_sheet.dart';
import 'library_shell.dart';
import '../reader/reading_queue_store.dart';
import 'reading_queue_sheet.dart';
import '../theme/app_tokens.dart';
import '../utils/app_haptics.dart';
import 'package:nexhub/core/widgets/app_alert_dialog.dart';

class BookshelfContent extends StatelessWidget {
  final SourceType sourceType;
  final LibrarySubTab subTab;
  final IconData emptyIcon;
  final String emptyMessage;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;
  final void Function(MediaItem item)? onItemTap;
  final BookshelfFilter filter;

  const BookshelfContent({
    super.key,
    required this.sourceType,
    required this.subTab,
    required this.emptyIcon,
    required this.emptyMessage,
    required this.filter,
    this.emptyActionLabel,
    this.onEmptyAction,
    this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    switch (subTab) {
      case LibrarySubTab.local:
        return _LocalBookshelf(
          sourceType: sourceType,
          emptyIcon: emptyIcon,
          emptyMessage: emptyMessage,
          emptyActionLabel: emptyActionLabel,
          onEmptyAction: onEmptyAction,
          onItemTap: onItemTap,
          filter: filter,
        );
      case LibrarySubTab.history:
        return _HistoryBookshelf(
          sourceType: sourceType,
          onItemTap: onItemTap,
          filter: filter,
          emptyActionLabel: emptyActionLabel,
          onEmptyAction: onEmptyAction,
        );
      case LibrarySubTab.favorite:
        return _FavoriteBookshelf(
          sourceType: sourceType,
          onItemTap: onItemTap,
          filter: filter,
          emptyActionLabel: emptyActionLabel,
          onEmptyAction: onEmptyAction,
        );
    }
  }

  /// Returns the distinct categories present in the given sub-tab's data.
  ///
  /// - local: actual file extensions present (mp4/mkv/ts、cbz/zip/7z、pdf、
  /// txt/epub、m3u8……), derived from downloaded tasks and imported items.
  /// Coarse labels like `video` are never shown — the label comes from the
  /// real product extension.
  /// - history / favorite: non-null [HistoryEntry.category] /
  /// [FavoriteEntry.category] values
  ///
  /// Used by [LibraryShell.categoryProvider] to populate the filter sheet's
  /// category section. Safe to call outside build (uses [context.read]).
  static List<String> categoriesFor(
    BuildContext context,
    SourceType sourceType,
    LibrarySubTab subTab,
  ) {
    switch (subTab) {
      case LibrarySubTab.local:
        // 分类段只展示「书架里实际存在的格式」，按真实产物扩展名派生
        // （mp4/mkv/ts、cbz/zip/7z、pdf、txt/epub、m3u8……），不展示粗粒度
        // 标签（如 video）。某格式无任何文件时自然不出现 → 配合筛选面板
        // 「选项 ≤1 自动隐藏该段」实现"无该格式则隐藏"。
        final dm = context.read<DownloadManager>();
        final lm = context.read<LocalContentManager>();
        final Set<String> categories = <String>{};
        for (final t
            in dm.completedTasks.where((t) => t.sourceType == sourceType)) {
          final c = _taskCategory(t);
          if (c != null) categories.add(c);
        }
        final importedKinds = _kindsForSourceType(sourceType);
        for (final e in lm.items.where((e) => importedKinds.contains(e.kind))) {
          categories.add(_importedCategory(e));
        }
        final sorted = categories.toList()..sort();
        return sorted;
      case LibrarySubTab.history:
        final manager = context.read<HistoryManager>();
        final categories = _visibleHistory(context.read<SourceRepository>(),
                manager.historyFor(sourceType))
            .map((e) => e.category)
            .whereType<String>()
            .toSet()
            .toList();
        categories.sort();
        return categories;
      case LibrarySubTab.favorite:
        final manager = context.read<FavoritesManager>();
        final categories = manager
            .favoritesFor(sourceType)
            .map((e) => e.category)
            .whereType<String>()
            .toSet()
            .toList();
        categories.sort();
        return categories;
    }
  }
}

// ── 本地（已下载）书架 ──────────────────────────────────

class _LocalBookshelf extends StatelessWidget {
  final SourceType sourceType;
  final IconData emptyIcon;
  final String emptyMessage;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;
  final void Function(MediaItem item)? onItemTap;
  final BookshelfFilter filter;

  const _LocalBookshelf({
    required this.sourceType,
    required this.emptyIcon,
    required this.emptyMessage,
    required this.filter,
    this.emptyActionLabel,
    this.onEmptyAction,
    this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<DownloadManager>();
    final historyManager = context.watch<HistoryManager>();
    final localManager = context.watch<LocalContentManager>();
    final repo = context.read<SourceRepository>();
    var tasks = manager.completedTasks
        .where((t) => t.sourceType == sourceType)
        .toList();

    // 分类筛选：本地段以实际产物格式（下载任务取真实扩展名，导入项取文件扩展名）
    // 作为分类，仅命中所选格式。
    if (filter.category != null) {
      tasks = tasks.where((t) => _taskCategory(t) == filter.category).toList();
    }

    // 进度筛选：cross-ref 历史记录判断是否在看。
    final Set<String> historyIds =
        historyManager.historyFor(sourceType).map((e) => e.id).toSet();
    tasks = tasks.where((t) {
      switch (filter.progress) {
        case BookshelfProgress.reading:
          return historyIds.contains(t.contentId);
        case BookshelfProgress.notStarted:
          return !historyIds.contains(t.contentId);
        case null:
          return true;
      }
    }).toList();

    // 排序。
    _sortTasks(tasks, filter.sort, sourceType);

    // 导入的本地内容（修复）：按 sourceType 映射 LocalMediaKind 后过滤。
    // 漫画源同时接受 images 与 pdf。
    final importedKinds = _kindsForSourceType(sourceType);
    var imported = importedKinds.isEmpty
        ? const <LocalContentEntry>[]
        : localManager.items
            .where((e) => importedKinds.contains(e.kind))
            .toList();
    if (filter.category != null && importedKinds.isNotEmpty) {
      imported = imported
          .where((e) => _importedCategory(e) == filter.category)
          .toList();
    }
    imported = imported.where((e) {
      switch (filter.progress) {
        case BookshelfProgress.reading:
          return historyIds.contains(e.id);
        case BookshelfProgress.notStarted:
          return !historyIds.contains(e.id);
        case null:
          return true;
      }
    }).toList();
    _sortLocalEntries(imported, filter.sort, sourceType);

    final isEmpty = tasks.isEmpty && imported.isEmpty;
    if (isEmpty) {
      return AppEmptyState(
        icon: emptyIcon,
        message: emptyMessage,
        actionLabel: emptyActionLabel,
        onAction: onEmptyAction,
      );
    }

    final List<_BookshelfItem> items = <_BookshelfItem>[];

    // 已下载内容（来自在线源下载）。按作品（同源 + contentId）合并展示单卡片，
    // 与「已下载」页统一：封面 / 标题取最新批次，章节为各批次并集。
    MediaItem itemForTask(DownloadTask t) => MediaItem(
          id: t.contentId,
          title: t.title,
          coverUrl: t.localCoverPath ?? t.coverUrl,
          sourceId: t.sourceId,
          sourceType: sourceType,
          extra: <String, dynamic>{
            if (t.localPath != null && t.localPath!.isNotEmpty)
              'localPath': t.localPath,
            'localKind': _kindForFormat(t.format)?.name,
            // 逐章/集路径：供阅读器按话/集打开与切换（修复"翻话/切集不过去"）。
            if (t.chapterFilePaths != null && t.chapterFilePaths!.isNotEmpty)
              'chapterFilePaths': t.chapterFilePaths!,
          },
        );
    final Map<String, List<DownloadTask>> byContent =
        <String, List<DownloadTask>>{};
    for (final t in tasks) {
      final key = '${t.sourceId ?? ''}|${t.contentId}';
      (byContent[key] ??= <DownloadTask>[]).add(t);
    }
    for (final entry in byContent.entries) {
      final group = entry.value
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final lead = group.reduce((a, b) => a.createdAt >= b.createdAt ? a : b);
      final chapterCount = group.fold(0, (s, e) => s + _localChapterCount(e));
      items.add(_BookshelfItem(
        id: lead.contentId,
        title: lead.title,
        sourceType: sourceType,
        coverUrl: lead.localCoverPath ?? lead.coverUrl,
        source: lead.sourceId != null ? repo.getById(lead.sourceId!) : null,
        onTap: () => onItemTap?.call(itemForTask(lead)),
        // 长按/右键弹出「打开 / 删除」操作菜单（与本地导入项一致）。
        onLongPress: () => showDownloadedEntryActions(
          context,
          lead,
          onOpen: () => onItemTap?.call(itemForTask(lead)),
        ),
        chapterCount: chapterCount,
      ));
    }

    // 导入的本地内容（修复：书架入口补 path 字段）。
    items.addAll(imported.map((e) => _BookshelfItem(
          id: e.id,
          title: e.title,
          sourceType: sourceType,
          coverUrl: e.coverUrl,
          author: e.author,
          onTap: () => onItemTap?.call(MediaItem(
            id: e.id,
            title: e.title,
            author: e.author,
            sourceId: '',
            sourceType: sourceType,
            extra: <String, dynamic>{
              'localPath': e.path,
              'localKind': e.kind.name,
              'filePaths': e.filePaths,
            },
          )),
          // 长按弹出「打开 / 重命名 / 删除」操作菜单（与导入历史列表一致）。
          onLongPress: () => showLocalEntryActions(context, e),
        )));

    return _BookshelfGrid(
      items: items,
      sort: filter.sort,
      sourceType: sourceType,
    );
  }
}

// ── 历史记录书架 ────────────────────────────────────────

/// 历史条目展示层过滤：
/// - 年龄限制：开启时隐藏 R18（mature）源的历史条目，与浏览/搜索入口同一套
///   判定（[SourceRepository.isAgeBlocked]）；
/// - 隐藏源：源在源管理中被隐藏（[PluginConfig.isHidden]）时，其历史条目
///   一并从书架历史隐藏——取消隐藏后条目自动恢复。
///
/// sourceId 为空（本地/导入内容）或源已卸载、无法判定的条目保持可见。
/// 过滤只在展示层生效，不改动持久化数据。
List<HistoryEntry> _visibleHistory(
  SourceRepository repo,
  Iterable<HistoryEntry> entries,
) {
  return entries.where((e) {
    final sid = e.sourceId;
    if (sid == null || sid.isEmpty) return true;
    final cfg = repo.getById(sid);
    if (cfg == null) return true;
    if (cfg.isHidden) return false;
    if (repo.ageRestrictionEnabled && repo.isAgeBlocked(cfg)) return false;
    return true;
  }).toList();
}

class _HistoryBookshelf extends StatelessWidget {
  final SourceType sourceType;
  final void Function(MediaItem item)? onItemTap;
  final BookshelfFilter filter;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;

  const _HistoryBookshelf({
    required this.sourceType,
    required this.filter,
    this.onItemTap,
    this.emptyActionLabel,
    this.onEmptyAction,
  });

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<HistoryManager>();
    // watch 而非 read：年龄限制开关切换（SourceRepository 广播）时历史列表
    // 即时刷新，R18 源条目自动隐藏/恢复。
    final repo = context.watch<SourceRepository>();
    // historyFor() 返回 List.unmodifiable（只读）。后续 _sortHistoryEntries 会
    // 原地 .sort() 修改列表；若不先复制成可变列表，无筛选时排序会抛
    // UnsupportedError，在 release APK 下表现为整屏灰（默认 ErrorWidget）。
    var entries = manager.historyFor(sourceType).toList();
    // 年龄限制开启时自动隐藏 R18 源的历史条目；隐藏源的条目一并隐藏。
    entries = _visibleHistory(repo, entries);

    // 分类筛选。
    if (filter.category != null) {
      entries = entries.where((e) => e.category == filter.category).toList();
    }

    // 状态筛选。
    if (filter.status != null) {
      entries = entries.where((e) => e.status == filter.status).toList();
    }

    // 进度筛选：历史段所有条目均为"在看"，notStarted 时清空。
    if (filter.progress == BookshelfProgress.notStarted) {
      entries = const <HistoryEntry>[];
    }

    // 排序。
    _sortHistoryEntries(entries, filter.sort, sourceType);

    if (entries.isEmpty) {
      return AppEmptyState(
        icon: Icons.history_rounded,
        message: AppLocalizations.of(context).emptyHistory,
        actionLabel: emptyActionLabel,
        onAction: onEmptyAction,
      );
    }

    return _BookshelfGrid(
      items: entries
          .map((e) => _BookshelfItem(
                id: e.id,
                title: e.title,
                sourceType: sourceType,
                coverUrl: e.localCoverPath ?? e.coverUrl,
                source: e.sourceId != null ? repo.getById(e.sourceId!) : null,
                onTap: () => onItemTap?.call(e.toMediaItem()),
                onDelete: () =>
                    manager.removeHistory(e.id, sourceType: sourceType),
              ))
          .toList(),
      sort: filter.sort,
      sourceType: sourceType,
    );
  }
}

// ── 收藏书架 ────────────────────────────────────────────

class _FavoriteBookshelf extends StatelessWidget {
  final SourceType sourceType;
  final void Function(MediaItem item)? onItemTap;
  final BookshelfFilter filter;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;

  const _FavoriteBookshelf({
    required this.sourceType,
    required this.filter,
    this.onItemTap,
    this.emptyActionLabel,
    this.onEmptyAction,
  });

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<FavoritesManager>();
    final historyManager = context.watch<HistoryManager>();
    final repo = context.read<SourceRepository>();
    // favoritesFor() 返回 List.unmodifiable（只读）；同 _HistoryBookshelf，
    // 需先复制成可变列表，否则无筛选时 _sortFavoriteEntries 原地排序会抛
    // UnsupportedError → release 下整屏灰。
    // 基础列表：指定分组时取完整收藏（隐藏分类虽不可从 UI 选中，但兼容此前
    // 已选定的过滤）；「全部」视图取排除「仅属隐藏分类」的可见收藏。
    final List<FavoriteEntry> base = filter.groupIds.isEmpty
        ? manager.visibleFavoritesFor(sourceType)
        : manager.favoritesFor(sourceType);
    var entries = base.toList();

    // 分类筛选。
    if (filter.category != null) {
      entries = entries.where((e) => e.category == filter.category).toList();
    }

    // 状态筛选。
    if (filter.status != null) {
      entries = entries.where((e) => e.status == filter.status).toList();
    }

    // 分组筛选（多选并集：命中任一分组即显示；哨兵 kUngroupedId = 未分组）。
    // 「全部」视图已在取数阶段排除仅属隐藏分类的收藏，此处不再处理。
    if (filter.groupIds.isNotEmpty) {
      entries = entries
          .where((e) =>
              (filter.groupIds.contains(kUngroupedId) && e.groupIds.isEmpty) ||
              e.groupIds.any(filter.groupIds.contains))
          .toList();
    }

    // 进度筛选：cross-ref 历史记录。
    final Set<String> historyIds =
        historyManager.historyFor(sourceType).map((e) => e.id).toSet();
    entries = entries.where((e) {
      switch (filter.progress) {
        case BookshelfProgress.reading:
          return historyIds.contains(e.id);
        case BookshelfProgress.notStarted:
          return !historyIds.contains(e.id);
        case null:
          return true;
      }
    }).toList();

    // 排序。
    _sortFavoriteEntries(entries, filter.sort, sourceType);

    if (entries.isEmpty) {
      return AppEmptyState(
        icon: Icons.favorite_border_rounded,
        message: AppLocalizations.of(context).emptyFavorites,
        actionLabel: emptyActionLabel,
        onAction: onEmptyAction,
      );
    }

    return _BookshelfGrid(
      items: entries
          .map((e) => _BookshelfItem(
                id: e.id,
                title: e.title,
                sourceType: sourceType,
                coverUrl: e.coverUrl,
                source: e.sourceId != null ? repo.getById(e.sourceId!) : null,
                author: e.author,
                lastSeenChapterCount: e.lastSeenChapterCount,
                sourceId: e.sourceId,
                onTap: () => onItemTap?.call(e.toMediaItem()),
                // 长按弹出操作菜单（分组指定 / Bangumi 绑定 / 待读队列，仅收藏书架）。
                onLongPress: () => _showFavoriteActionsMenu(
                  context,
                  contentId: e.id,
                  sourceType: sourceType,
                  item: e.toMediaItem(),
                ),
              ))
          .toList(),
      sort: filter.sort,
      sourceType: sourceType,
    );
  }
}

/// 收藏卡片长按操作菜单：分组指定 / Bangumi 绑定与评分 / 待读队列。
void _showFavoriteActionsMenu(
  BuildContext context, {
  required String contentId,
  required SourceType sourceType,
  required MediaItem item,
}) {
  // MD3「Thunk」：长按呼出操作菜单。
  AppHaptics.thunk();
  final l10n = AppLocalizations.of(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTokens.radiusLg),
      ),
    ),
    builder: (BuildContext ctx) => SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.folder_rounded),
                title: Text(l10n.setGroups),
                onTap: () {
                  Navigator.of(ctx).pop();
                  showFavoriteGroupAssignSheet(
                    context,
                    contentId: contentId,
                    sourceType: sourceType,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.live_tv_rounded),
                title: Text(l10n.bangumiBindAndRate),
                onTap: () {
                  Navigator.of(ctx).pop();
                  showBangumiBindSheet(
                    context,
                    contentId: contentId,
                    sourceType: sourceType,
                  );
                },
              ),
              // 待读队列：加入队列 / 打开队列（仅在线作品；本地作品隐藏）。
              if (item.sourceId != null &&
                  item.sourceId!.isNotEmpty) ...<Widget>[
                ListTile(
                  leading: const Icon(Icons.playlist_add_rounded),
                  title: Text(l10n.readingQueueAdd),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await ReadingQueueStore().add(QueuedReading(
                      sourceType: sourceType,
                      sourceId: item.sourceId!,
                      itemId: item.id,
                      title: item.title,
                      coverUrl: item.coverUrl,
                      detailUrl: item.detailUrl,
                      updatedAt: DateTime.now().millisecondsSinceEpoch,
                    ));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.readingQueueAdded)),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.playlist_play_rounded),
                  title: Text(l10n.readingQueueOpen),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    openReadingQueueSheet(context);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

// ── 排序辅助 ────────────────────────────────────────────

/// 手动排序比较：已排序条目（有索引）在前，按索引升序；未排序条目在后，
/// 以标题作为稳定回退。未加载时 [BookshelfManualOrderStore.indexFor] 会后台加载。
int _manualCompare(
  SourceType type,
  String idA,
  String titleA,
  String idB,
  String titleB,
) {
  final store = BookshelfManualOrderStore.instance;
  final int? ia = store.indexFor(type, idA);
  final int? ib = store.indexFor(type, idB);
  if (ia != null && ib != null) return ia.compareTo(ib);
  if (ia != null) return -1;
  if (ib != null) return 1;
  return titleA.toLowerCase().compareTo(titleB.toLowerCase());
}

void _sortTasks(
  List<DownloadTask> tasks,
  BookshelfSort sort,
  SourceType sourceType,
) {
  switch (sort) {
    case BookshelfSort.recent:
    case BookshelfSort.latestChapter:
      tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    case BookshelfSort.title:
    case BookshelfSort.author:
    case BookshelfSort.titleZh:
    case BookshelfSort.director:
    case BookshelfSort.actors:
      // 下载任务无作者 / 中文书名 / 导演 / 主演字段，均回退标题。
      tasks.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    case BookshelfSort.manual:
      tasks.sort((a, b) => _manualCompare(
          sourceType, a.contentId, a.title, b.contentId, b.title));
  }
}

void _sortLocalEntries(
  List<LocalContentEntry> entries,
  BookshelfSort sort,
  SourceType sourceType,
) {
  switch (sort) {
    case BookshelfSort.recent:
    case BookshelfSort.latestChapter:
      entries.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    case BookshelfSort.title:
    case BookshelfSort.author:
    case BookshelfSort.titleZh:
    case BookshelfSort.director:
    case BookshelfSort.actors:
      // 导入的本地内容无导演 / 主演字段，回退标题。
      entries.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    case BookshelfSort.manual:
      entries.sort(
          (a, b) => _manualCompare(sourceType, a.id, a.title, b.id, b.title));
  }
}

/// 按 [SourceType] 映射到导入内容的 [LocalMediaKind]（可能多个）。
///
/// 漫画源同时接受 `images`（CBZ/图片目录）与 `pdf`（PDF 漫画），小说源接受
/// `text`，影视源接受 `video`。返回空列表表示该 sourceType 无对应导入类型。
List<LocalMediaKind> _kindsForSourceType(SourceType type) => switch (type) {
      SourceType.mangaSource => [LocalMediaKind.images, LocalMediaKind.pdf],
      SourceType.novelSource => [LocalMediaKind.text],
      SourceType.animeSource => [LocalMediaKind.video],
    };

/// 取下载任务首个产物文件的扩展名（不含点，小写）。
///
/// 优先用逐章/集文件 [DownloadTask.chapterFilePaths]（视频为 `001.mp4`、
/// 漫画为 `001.cbz`、小说为整本 `title.txt/.epub`），回退到 [DownloadTask.localPath]。
/// 目录或取不到时返回 null。
String? _firstFileExtension(DownloadTask t) {
  String? candidate;
  if (t.chapterFilePaths != null) {
    for (final fp in t.chapterFilePaths!) {
      if (fp.isNotEmpty) {
        candidate = fp;
        break;
      }
    }
  }
  candidate ??= t.localPath;
  if (candidate == null || candidate.isEmpty) return null;
  final ext = path.extension(candidate);
  return ext.isNotEmpty ? ext.substring(1).toLowerCase() : null;
}

/// 下载任务在分类筛选项中归属的格式标签。
///
/// 优先用实际产物扩展名（粒度最细：mp4/mkv/ts、cbz、epub…）；无扩展名时回退到
/// 下载格式枚举（folder/jpg/png/cbz/epub/txt 等具名格式）。旧版 `video` 下载若
/// 取不到扩展名则不归入任何格式，避免暴露粗粒度 "video" 标签。
String? _taskCategory(DownloadTask t) {
  final ext = _firstFileExtension(t);
  if (ext != null) return ext;
  if (t.format == DownloadFormat.video) return null;
  return t.format.label;
}

/// 导入项在分类筛选项中归属的格式标签：优先用文件扩展名（cbz/zip/7z/pdf/
/// m3u8/mp4…），无扩展名时回退到 [LocalMediaKind] 名称。
String _importedCategory(LocalContentEntry e) {
  final ext = path.extension(e.path).toLowerCase();
  return ext.isNotEmpty ? ext.substring(1) : e.kind.name;
}

/// 按 [DownloadFormat] 映射到 [LocalMediaKind]，用于下载内容点击时透传给
/// onItemTap 的 extra，供阅读器分流。
LocalMediaKind? _kindForFormat(DownloadFormat f) => switch (f) {
      DownloadFormat.cbz => LocalMediaKind.images,
      DownloadFormat.folder => LocalMediaKind.images,
      DownloadFormat.jpg => LocalMediaKind.images,
      DownloadFormat.png => LocalMediaKind.images,
      DownloadFormat.epub => LocalMediaKind.text,
      DownloadFormat.txt => LocalMediaKind.text,
      DownloadFormat.video => LocalMediaKind.video,
    };

void _sortHistoryEntries(
  List<HistoryEntry> entries,
  BookshelfSort sort,
  SourceType sourceType,
) {
  switch (sort) {
    case BookshelfSort.recent:
    case BookshelfSort.latestChapter:
      entries.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
    case BookshelfSort.title:
    case BookshelfSort.author:
    case BookshelfSort.titleZh:
      entries.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    case BookshelfSort.director:
      entries.sort((a, b) => (a.director ?? a.title)
          .toLowerCase()
          .compareTo((b.director ?? b.title).toLowerCase()));
    case BookshelfSort.actors:
      entries.sort((a, b) => (a.actors ?? a.title)
          .toLowerCase()
          .compareTo((b.actors ?? b.title).toLowerCase()));
    case BookshelfSort.manual:
      entries.sort(
          (a, b) => _manualCompare(sourceType, a.id, a.title, b.id, b.title));
  }
}

void _sortFavoriteEntries(
  List<FavoriteEntry> entries,
  BookshelfSort sort,
  SourceType sourceType,
) {
  switch (sort) {
    case BookshelfSort.recent:
      entries.sort((a, b) => b.favoritedAt.compareTo(a.favoritedAt));
    case BookshelfSort.latestChapter:
      // 最新章时间（语义修正）：优先源站更新时间 updatedAt
      // （详情页刷新回填），无记录时回退最后阅读时间、再回退收藏时间。
      int chapterTimeOf(FavoriteEntry e) => e.updatedAt > 0
          ? e.updatedAt
          : (e.lastRead > 0 ? e.lastRead : e.favoritedAt);
      entries.sort((a, b) => chapterTimeOf(b).compareTo(chapterTimeOf(a)));
    case BookshelfSort.title:
    case BookshelfSort.author:
      entries.sort((a, b) => (a.author ?? a.title)
          .toLowerCase()
          .compareTo((b.author ?? b.title).toLowerCase()));
    case BookshelfSort.titleZh:
      // 中文书名按拼音序比较：GBK 一级字库近似拼音序，
      // 替代此前的码元序（码元序对汉字是部首笔画序，不符合直觉）。
      entries.sort((a, b) =>
          compareZhPinyin(a.titleZh ?? a.title, b.titleZh ?? b.title));
    case BookshelfSort.director:
      entries.sort((a, b) => (a.director ?? a.title)
          .toLowerCase()
          .compareTo((b.director ?? b.title).toLowerCase()));
    case BookshelfSort.actors:
      entries.sort((a, b) => (a.actors ?? a.title)
          .toLowerCase()
          .compareTo((b.actors ?? b.title).toLowerCase()));
    case BookshelfSort.manual:
      entries.sort(
          (a, b) => _manualCompare(sourceType, a.id, a.title, b.id, b.title));
  }
}

// ── 网格视图 ────────────────────────────────────────────

/// 本地/下载项的「本地已有章数」：
/// - 逐章产物（漫画/动漫/视频，[DownloadTask.chapterFilePaths] 多文件）→
/// 以实际落盘文件数为准（即真正可在本机阅读的章数）。
/// - 整本单文件（小说 epub/txt，[chapterFilePaths] 仅 1 项或无）→ 回退到
/// 章节总数（整本书已在本机，章数即全量）。
/// 用于未读角标分母，避免把"下载任务记录的章名数"当成本地已有数。
int _localChapterCount(DownloadTask t) {
  final files = t.chapterFilePaths;
  if (files != null && files.length > 1) return files.length;
  return t.chapterTitles.length;
}

class _BookshelfItem {
  final String id;
  final String title;
  final String? coverUrl;
  final String? author;
  final SourceType sourceType;
  final PluginConfig? source;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  /// 长按回调（仅收藏书架传入，弹出分组指定面板）。
  final VoidCallback? onLongPress;

  /// 上次查看目录时的章节总数（新章提示；仅收藏条目传入，0=未记录）。
  final int lastSeenChapterCount;

  /// 源 id（仅收藏/下载段需要：目录缓存与进度按源路由时使用）。
  final String? sourceId;

  final int chapterCount;

  const _BookshelfItem({
    required this.id,
    required this.title,
    required this.sourceType,
    this.coverUrl,
    this.author,
    this.source,
    this.onTap,
    this.onDelete,
    this.onLongPress,
    this.lastSeenChapterCount = 0,
    this.sourceId,
    this.chapterCount = 0,
  });
}

class _BookshelfGrid extends StatefulWidget {
  final List<_BookshelfItem> items;
  final BookshelfSort sort;
  final SourceType sourceType;

  const _BookshelfGrid({
    required this.items,
    required this.sort,
    required this.sourceType,
  });

  @override
  State<_BookshelfGrid> createState() => _BookshelfGridState();
}

class _BookshelfGridState extends State<_BookshelfGrid> {
  late List<_BookshelfItem> _items;

  @override
  void initState() {
    super.initState();
    _items = List<_BookshelfItem>.from(widget.items);
  }

  @override
  void didUpdateWidget(covariant _BookshelfGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 父级每次 build 重新传入已按当前排序排好的 items；手动排序时本组件是展示
    // 真相（拖拽后本地重排并写回存储），与父级按存储索引重排结果一致。
    _items = List<_BookshelfItem>.from(widget.items);
  }

  bool get _manual => widget.sort == BookshelfSort.manual;

  /// 列表手动排序（[ReorderableListView.onReorderItem]，newIndex 已为目标位）。
  void _onReorderItem(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _items.length) return;
    if (newIndex < 0 || newIndex >= _items.length) return;
    setState(() {
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });
    unawaited(BookshelfManualOrderStore.instance
        .applyOrder(widget.sourceType, _items.map((e) => e.id).toList()));
  }

  /// 网格手动排序：拖拽落点重排（SDK 无 ReorderableGridView，用 Draggable+DragTarget）。
  void _onGridDrop(int from, int to) {
    if (from < 0 || from >= _items.length) return;
    if (to < 0 || to >= _items.length) return;
    setState(() {
      final item = _items.removeAt(from);
      final target = to > from ? to - 1 : to;
      _items.insert(target, item);
    });
    unawaited(BookshelfManualOrderStore.instance
        .applyOrder(widget.sourceType, _items.map((e) => e.id).toList()));
  }

  @override
  Widget build(BuildContext context) {
    // 监听布局设置变化，即时刷新网格/列表（与浏览页一致）。
    return ListenableBuilder(
      listenable: LayoutSettingsStore.instance,
      builder: (context, _) {
        final LayoutSettings layout = LayoutSettingsStore.instance.settings;
        if (layout.layoutMode == LayoutMode.list) {
          return _buildList(layout);
        }
        return _buildGrid(layout);
      },
    );
  }

  /// 计算书架条目的阅读/观看进度（0.0–1.0 或 null）。
  ///
  /// 与 [OnlineContentListScreen._computeProgress] 逻辑完全一致：
  /// - 影视/动漫：[MediaWatchedManager] 已看集数 ÷ 总集数。
  /// - 小说：[NovelProgressManager] 已读章节 ÷ 总章数。
  /// - 漫画：[ComicProgressManager] 已读章节 ÷ 总章数。
  Future<double?> _computeProgress(_BookshelfItem item) async {
    try {
      switch (item.sourceType) {
        case SourceType.animeSource:
          try {
            // 书架环境无 Provider context，用默认实例读取。
            final mgr = MediaWatchedManager();
            final watched = mgr.watchedCount(item.id);
            if (watched > 0) {
              // 尝试从 MediaItem 获取总集数（需在调用方透传）；
              // 书架条目暂不携带 episodeCount，故仅返回"已开始"标记进度。
              if (watched > 0) return 0.02;
            }
          } on Object {/* 忽略 */}
          break;
        case SourceType.novelSource:
          final p = await NovelProgressManager().get(item.id);
          if (p != null && p.totalChapters != null && p.totalChapters! > 0) {
            return ((p.chapterIndex + 1) / p.totalChapters!).clamp(0.0, 1.0);
          }
          if (p != null && p.chapterIndex > 0) return 0.02;
          break;
        case SourceType.mangaSource:
          final p = await ComicProgressManager().get(item.id);
          if (p != null && p.totalChapters != null && p.totalChapters! > 0) {
            return ((p.chapterIndex + 1) / p.totalChapters!).clamp(0.0, 1.0);
          }
          if (p != null && p.chapterIndex > 0) return 0.02;
          break;
      }
    } on Object {/* 忽略 */}
    return null;
  }

  /// 网格模式：列数/间距跟随布局设置，卡片显示作者 + 进度。手动排序时切换为
  /// 拖拽重排（LongPressDraggable + DragTarget，SDK 无 ReorderableGridView）。
  Widget _buildGrid(LayoutSettings layout) {
    final int cross = layout.gridColumns.clamp(1, 8);
    final double spacing = layout.gridSpacing.clamp(4, 24);
    final double textH = _textHeight(layout);
    return LayoutBuilder(
      builder: (ctx, c) {
        final double width = c.maxWidth;
        final double itemW =
            (width - AppTokens.spaceMd * 2 - spacing * (cross - 1)) / cross;
        final double coverH = itemW / AppTokens.coverAspectRatio;
        final double ratio = itemW / (coverH + textH);
        final List<Widget> children = <Widget>[
          for (final item in _items)
            KeyedSubtree(
              key: ValueKey<String>(item.id),
              child: _buildCard(ctx, item, layout, itemW),
            ),
        ];
        if (_manual) {
          // SDK 无 ReorderableGridView：用 LongPressDraggable + DragTarget 实现网格拖拽重排。
          return GridView.builder(
            padding: EdgeInsets.fromLTRB(
              AppTokens.spaceMd,
              AppTokens.spaceMd,
              AppTokens.spaceMd,
              AppTokens.spaceMd + MediaQuery.paddingOf(ctx).bottom,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cross,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              childAspectRatio: ratio,
            ),
            itemCount: _items.length,
            itemBuilder: (ctx, i) {
              final item = _items[i];
              final card = _buildCard(ctx, item, layout, itemW);
              return LongPressDraggable<int>(
                data: i,
                delay: const Duration(milliseconds: 200),
                feedback: Material(
                  color: Colors.transparent,
                  child: SizedBox(
                    width: itemW,
                    height: itemW / ratio,
                    child: card,
                  ),
                ),
                childWhenDragging: Opacity(opacity: 0.3, child: card),
                child: DragTarget<int>(
                  onWillAcceptWithDetails: (d) => d.data != i,
                  onAcceptWithDetails: (d) => _onGridDrop(d.data, i),
                  builder: (c, accepted, rejected) => card,
                ),
              );
            },
          );
        }
        return GridView.count(
          crossAxisCount: cross,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          childAspectRatio: ratio,
          padding: EdgeInsets.fromLTRB(
            AppTokens.spaceMd,
            AppTokens.spaceMd,
            AppTokens.spaceMd,
            AppTokens.spaceMd + MediaQuery.paddingOf(ctx).bottom,
          ),
          children: children,
        );
      },
    );
  }

  /// 列表模式：单列横向卡片（封面 + 标题 + 作者）。手动排序时切换为
  /// [ReorderableListView] 支持拖拽重排。
  Widget _buildList(LayoutSettings layout) {
    final bool isCompact = layout.listStyle == ListLayoutStyle.compact;
    if (_manual) {
      // 手动排序：对齐「源管理」拖拽视觉——左侧拖动手柄 + 自定义 decorator。
      // 关闭默认右侧手柄，改用左侧 drag_indicator 图标触发拖拽。
      return ReorderableListView.builder(
        // 行首是拖拽手柄，移动端需避让玻璃底栏保证可点。
        padding: const EdgeInsets.all(AppTokens.spaceMd) + context.glassBarInset,
        itemCount: _items.length,
        onReorderItem: _onReorderItem,
        buildDefaultDragHandles: false,
        onReorderStart: (_) => AppHaptics.thunk(),
        proxyDecorator: _listProxyDecorator,
        itemBuilder: (ctx, i) => KeyedSubtree(
          key: ValueKey<String>(_items[i].id),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              ReorderableDragStartListener(
                index: i,
                child: Padding(
                  padding: const EdgeInsets.only(right: AppTokens.spaceXs),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    size: 20,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.45),
                  ),
                ),
              ),
              Expanded(child: _buildRow(_items[i], layout, isCompact)),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(AppTokens.spaceMd) + context.glassBarInset,
      itemCount: _items.length,
      itemBuilder: (context, i) => _buildRow(_items[i], layout, isCompact),
    );
  }

  /// 列表手动拖拽时的浮起装饰（对齐「源管理」风格）：easeOut 缓动 + 轻微上浮
  /// + 1.04 缩放 + 主色描边 + 双层阴影（主阴影 + 主色辉光），增强"拎起"手感。
  Widget _listProxyDecorator(
    Widget child,
    int index,
    Animation<double> animation,
  ) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final double t = Curves.easeOut.transform(animation.value);
        final double scale = lerpDouble(1.0, 1.04, t)!;
        final ColorScheme scheme = Theme.of(context).colorScheme;
        return Transform.translate(
          offset: Offset(0, -3 * t),
          child: Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: lerpDouble(1.0, 0.97, t)!,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.3 * t),
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: scheme.shadow.withValues(alpha: 0.26 * t),
                      blurRadius: 16 * t + 4,
                      offset: Offset(0, 7 * t + 2),
                    ),
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.12 * t),
                      blurRadius: 28 * t,
                      offset: Offset(0, 3 * t),
                    ),
                  ],
                ),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }

  /// 单卡片（网格模式）：封面 + 标题 + 可选作者 + 进度 + 删除浮钮。
  Widget _buildCard(
    BuildContext ctx,
    _BookshelfItem item,
    LayoutSettings layout,
    double itemW,
  ) {
    return FutureBuilder<(int, bool)?>(
      future: _computeUnreadBadge(ctx, item),
      builder: (ctx0, badgeSnap) {
        final (int unread, bool isNew)? badge = badgeSnap.data;
        return FutureBuilder<double?>(
          future: layout.showProgress
              ? _computeProgress(item)
              : Future<double?>.value(null),
          builder: (ctx2, snap) {
            Widget card = ContentCard(
              coverUrl: item.coverUrl,
              title: item.title,
              subtitle: (layout.showAuthor && item.author != null)
                  ? item.author
                  : null,
              source: item.source,
              onTap: item.onTap,
              width: itemW,
              progress: snap.data,
            );
            // 长按/右键入口（ContentCard 未暴露 onLongPress，外层手势兼容 InkWell）。
            if (item.onLongPress != null) {
              card = GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: item.onLongPress,
                onSecondaryTap: item.onLongPress,
                child: card,
              );
            }
            // 历史记录：右上角悬浮删除按钮（仅历史书架传入 onDelete）。
            return Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                card,
                // 小说收藏未读/新章角标（数字；isNew 红色标识有新章）。
                if (badge != null)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: _buildUnreadBadge(ctx2, badge.$1, badge.$2),
                  ),
                if (item.onDelete != null)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusFull),
                        onTap: () => _confirmDelete(ctx, item),
                        child: Container(
                          padding: const EdgeInsets.all(AppTokens.spaceXs),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .shadow
                                .withValues(alpha: 0.54),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.delete_rounded,
                              size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  /// 未读/新章角标控件：胶囊数字；新章用 error 色。
  Widget _buildUnreadBadge(BuildContext ctx, int count, bool isNew) {
    final scheme = Theme.of(ctx).colorScheme;
    final text = count > 99 ? '99+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceXs + 1, vertical: 1),
      constraints: const BoxConstraints(minWidth: 18),
      decoration: BoxDecoration(
        color: isNew ? scheme.error : scheme.primary,
        borderRadius: BorderRadius.circular(AppTokens.radiusFull),
        border: Border.all(color: scheme.surface, width: 1),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
              color: scheme.onPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 10,
              height: 1.3,
            ),
      ),
    );
  }

  /// 收藏/历史条目的未读/新章角标数据。返回 `(未读数, 是否有新章)`，
  /// null 表示不显示。
  ///
  /// 三模块统一入口：按 [SourceType] 分发到小说 / 漫画 / 影视各自的进度源。
  /// 总数与「已读/已看位置」的取法各模块不同（见各 _compute*Badge 辅助）。
  Future<(int, bool)?> _computeUnreadBadge(
      BuildContext ctx, _BookshelfItem item) async {
    try {
      switch (item.sourceType) {
        case SourceType.novelSource:
          return await _computeNovelBadge(item);
        case SourceType.mangaSource:
          return await _computeComicBadge(item);
        case SourceType.animeSource:
          return await _computeMediaBadge(ctx, item);
      }
    } on Object {
      return null;
    }
  }

  /// 总数 > 已见章节数 ⇒ 有新章（红色）。
  bool _hasNewChapter(int total, int lastSeen) =>
      lastSeen > 0 && total > lastSeen;

  /// 小说：目录缓存优先（最新），进度内 totalChapters 兜底；
  /// unread = total − 已读位置（章节索引 + 1）。
  Future<(int, bool)?> _computeNovelBadge(_BookshelfItem item) async {
    final progress = await NovelProgressManager().get(item.id);
    final readPos = (progress?.chapterIndex ?? -1) + 1; // 0 = 无进度

    // 本地/下载项：总数以「已下载章节数」为准，不能用在线总章数（会远大于
    // 已下载量，导致未读角标显示成整本小说的章节数）。与影视角标对齐。
    if (item.chapterCount > 0) {
      final isNew =
          _hasNewChapter(item.chapterCount, item.lastSeenChapterCount);
      if (readPos > 0) {
        final unread = item.chapterCount - readPos;
        return unread > 0 ? (unread, isNew) : null;
      }
      if (isNew) return (item.chapterCount - item.lastSeenChapterCount, true);
      return null;
    }

    var total = progress?.totalChapters ?? 0;
    final sid = item.sourceId ?? item.source?.id;
    if (sid != null && sid.isNotEmpty) {
      try {
        final cached = await NovelTocCache().read(sid, item.id);
        if (cached != null && cached.length > total) total = cached.length;
      } on Object {/* 目录缓存缺失忽略 */}
    }
    if (total <= 0) return null;
    final isNew = _hasNewChapter(total, item.lastSeenChapterCount);
    if (readPos > 0) {
      final unread = total - readPos;
      return unread > 0 ? (unread, isNew) : null;
    }
    if (isNew) return (total - item.lastSeenChapterCount, true);
    return null;
  }

  /// 漫画：进度来自 [ComicProgressManager]（chapterIndex + totalChapters，
  /// 走 SharedPreferences，无需 init）。逻辑与小说完全对齐。
  Future<(int, bool)?> _computeComicBadge(_BookshelfItem item) async {
    final progress = await ComicProgressManager().get(item.id);
    final readPos = (progress?.chapterIndex ?? -1) + 1; // 0 = 无进度

    // 本地/下载项：总数以「已下载章节数」为准（与小说、影视角标对齐），
    // 否则会误用在线总章数导致未读数被放大。
    if (item.chapterCount > 0) {
      final isNew =
          _hasNewChapter(item.chapterCount, item.lastSeenChapterCount);
      if (readPos > 0) {
        final unread = item.chapterCount - readPos;
        return unread > 0 ? (unread, isNew) : null;
      }
      if (isNew) return (item.chapterCount - item.lastSeenChapterCount, true);
      return null;
    }

    final total = progress?.totalChapters ?? 0;
    if (total <= 0) return null;
    final isNew = _hasNewChapter(total, item.lastSeenChapterCount);
    if (readPos > 0) {
      final unread = total - readPos;
      return unread > 0 ? (unread, isNew) : null;
    }
    if (isNew) return (total - item.lastSeenChapterCount, true);
    return null;
  }

  /// 影视：已看集数来自 [MediaWatchedManager]（应用级单例，Provider 注入），
  /// unread = total − 已看集数。总数优先取书架条目的 chapterCount，
  /// 否则回退到已见集数 lastSeenChapterCount（二者皆缺则不显示，避免误报）。
  Future<(int, bool)?> _computeMediaBadge(
      BuildContext ctx, _BookshelfItem item) async {
    final watcher = _readWatchedManager(ctx);
    if (watcher == null) return null;
    final watched = watcher.watchedCount(item.id);
    final total =
        item.chapterCount > 0 ? item.chapterCount : item.lastSeenChapterCount;
    if (total <= 0) return null;
    final isNew = _hasNewChapter(total, item.lastSeenChapterCount);
    final unread = total - watched;
    if (unread > 0) return (unread, isNew);
    if (isNew) return (total - item.lastSeenChapterCount, true);
    return null;
  }

  /// Provider 容错读取影视已看管理器（未注册时返回 null 而非抛异常）。
  MediaWatchedManager? _readWatchedManager(BuildContext ctx) {
    try {
      return ctx.read<MediaWatchedManager>();
    } on Object {
      return null;
    }
  }

  /// 单行（列表模式）：封面 + 标题 + 作者 + 进度 + 删除按钮。
  Widget _buildRow(_BookshelfItem item, LayoutSettings layout, bool isCompact) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    Widget card = AppCard(
      onTap: item.onTap,
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppTokens.spaceMd,
          vertical: isCompact ? AppTokens.spaceXs : AppTokens.spaceSm,
        ),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(layout.coverRadius.toDouble()),
          child: SizedBox(
            width: isCompact ? 40 : 56,
            height: isCompact ? 56 : 78,
            child: AppCoverImage(
              coverUrl: item.coverUrl,
              source: item.source,
              title: item.title,
              width: isCompact ? 40 : 56,
              height: isCompact ? 56 : 78,
              radius: layout.coverRadius,
            ),
          ),
        ),
        title: layout.showTitle
            ? Text(
                item.title,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(fontSize: layout.titleFontSize),
                maxLines: layout.titleMaxLines,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        subtitle: (layout.showAuthor &&
                item.author != null &&
                item.author!.isNotEmpty)
            ? Text(
                item.author!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (layout.showProgress)
              FutureBuilder<double?>(
                future: _computeProgress(item),
                builder: (ctx, snap) {
                  final double? p = snap.data;
                  if (p == null || p <= 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(right: AppTokens.spaceSm),
                    child: Text(
                      '${(p * 100).round()}%',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  );
                },
              ),
            if (item.onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete_rounded),
                tooltip: AppLocalizations.of(context).delete,
                onPressed: () => _confirmDelete(context, item),
              ),
          ],
        ),
      ),
    );
    // 长按/右键入口（AppCard 未暴露 onLongPress，外层手势兼容）。
    if (item.onLongPress != null) {
      card = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: item.onLongPress,
        onSecondaryTap: item.onLongPress,
        child: card,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
      child: card,
    );
  }

  /// 删除前二次确认（避免误删历史记录）。
  Future<void> _confirmDelete(BuildContext context, _BookshelfItem item) async {
    final l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(l10n.deleteConfirmTitle),
        content: Text(l10n.deleteConfirmContent(item.title)),
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
    if (confirmed == true) item.onDelete?.call();
  }

  /// 根据布局设置计算文本区域高度（标题 + 可选作者），用于反推高宽比。
  double _textHeight(LayoutSettings layout) {
    if (!layout.showTitle && !layout.showAuthor) return 4;
    final double lineHeight = layout.titleFontSize * 1.4;
    var lines = 0.0;
    if (layout.showTitle) lines += layout.titleMaxLines.toDouble();
    if (layout.showAuthor) lines += 1.0;
    return lineHeight * lines + 12;
  }
}
