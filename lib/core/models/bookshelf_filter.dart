/// 书架筛选状态（文档 + 雷区 18）。
///
/// 三模块书架共用，描述"排序 + 分类 + 状态 + 进度 + 分组"筛选。
/// 不可变值对象，通过 [copyWith] 修改；[isDefault] 用于判断是否显示"已筛选"角标。
library;

import 'package:flutter/foundation.dart';

import 'plugin_config.dart';

/// 排序方式。
enum BookshelfSort {
  /// 按时间倒序（收藏时间 / 浏览时间 / 完成时间）。
  recent,

  /// 按标题字母升序。
  title,

  /// 按作者升序（无作者字段的类型回退标题）。
  author,

  /// 按最新章/最近阅读进度（收藏取 lastRead，历史取 viewedAt，下载取 createdAt，导入取 addedAt）。
  latestChapter,

  /// 按中文书名（收藏取 titleZh，无则回退 title；其它类型直接取 title）。
  titleZh,

  /// 按导演（媒体/动漫专属语义，无字段时回退标题）。
  director,

  /// 按主演（媒体/动漫专属语义，无字段时回退标题）。
  actors,

  /// 手动排序：按用户在书架拖拽保存的自定义顺序。
  manual,
}

/// 各 [SourceType] 书架可用的排序项及其语义。
///
/// - 小说：最近/标题/作者/最新章/中文书名/手动（完整六维）。
/// - 漫画：最近/标题/作者/最新话/手动（无中文书名维度）。
/// - 媒体(动漫)：最近/标题/最新/导演/主演/手动（无作者/中文书名维度，
/// 以导演/主演替代；"最新"随类型在 UI 上呈现为最新章/最新话/最新）。
///
/// 注意：本函数只描述"该类型有哪些排序项"，与布局模式（列表/网格）无关；
/// 手动项是否对当前布局可见由调用方（筛选面板）按 [LayoutMode] 决定。
List<BookshelfSort> availableSortsFor(SourceType type) {
  switch (type) {
    case SourceType.novelSource:
      return const <BookshelfSort>[
        BookshelfSort.recent,
        BookshelfSort.title,
        BookshelfSort.author,
        BookshelfSort.latestChapter,
        BookshelfSort.titleZh,
        BookshelfSort.manual,
      ];
    case SourceType.mangaSource:
      return const <BookshelfSort>[
        BookshelfSort.recent,
        BookshelfSort.title,
        BookshelfSort.author,
        BookshelfSort.latestChapter,
        BookshelfSort.manual,
      ];
    case SourceType.animeSource:
    case SourceType.videoSource:
    case SourceType.audioSource:
      return const <BookshelfSort>[
        BookshelfSort.recent,
        BookshelfSort.title,
        BookshelfSort.latestChapter,
        BookshelfSort.director,
        BookshelfSort.actors,
        BookshelfSort.manual,
      ];
  }
}

/// 进度筛选语义。
enum BookshelfProgress {
  /// 在看（收藏夹中存在于历史记录里的条目）。
  reading,

  /// 未看（收藏夹中尚未出现在历史记录里的条目）。
  notStarted,
}

/// 书架筛选状态。
class BookshelfFilter {
  final BookshelfSort sort;

  /// 状态筛选：null = 全部；否则按 [FavoriteEntry.status] / [HistoryEntry.status]
  /// 原值匹配（如 "连载中" / "已完结"）。
  final String? status;

  /// 分类筛选：null = 全部分类；否则按 [FavoriteEntry.category] /
  /// [HistoryEntry.category] 原值匹配。
  final String? category;

  /// 进度筛选：null = 全部进度；否则按 [BookshelfProgress] 语义过滤。
  /// 仅对收藏/本地子段有意义，历史子段自动全过。
  final BookshelfProgress? progress;

  /// 分组筛选：空集 = 不过滤；多选为并集语义（命中任一分组即显示）。
  /// 可包含哨兵 [kUngroupedId] 表示筛选未分组条目。仅收藏子段有意义。
  final Set<String> groupIds;

  const BookshelfFilter({
    this.sort = BookshelfSort.recent,
    this.status,
    this.category,
    this.progress,
    this.groupIds = const <String>{},
  });

  /// 是否为默认状态（无任何筛选/排序覆盖）。
  bool get isDefault =>
      sort == BookshelfSort.recent &&
      status == null &&
      category == null &&
      progress == null &&
      groupIds.isEmpty;

  BookshelfFilter copyWith({
    BookshelfSort? sort,
    Object? status = _sentinel,
    Object? category = _sentinel,
    Object? progress = _sentinel,
    Set<String>? groupIds,
  }) =>
      BookshelfFilter(
        sort: sort ?? this.sort,
        status: identical(status, _sentinel)
            ? this.status
            : status as String?,
        category: identical(category, _sentinel)
            ? this.category
            : category as String?,
        progress: identical(progress, _sentinel)
            ? this.progress
            : progress as BookshelfProgress?,
        groupIds: groupIds ?? this.groupIds,
      );

  /// 重置为默认状态。
  BookshelfFilter reset() => const BookshelfFilter();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookshelfFilter &&
          other.sort == sort &&
          other.status == status &&
          other.category == category &&
          other.progress == progress &&
          setEquals(other.groupIds, groupIds));

  @override
  int get hashCode =>
      Object.hash(sort, status, category, progress, Object.hashAllUnordered(groupIds));
}

/// 用于区分"未传参"与"显式传 null"的哨兵对象。
const Object _sentinel = Object();
