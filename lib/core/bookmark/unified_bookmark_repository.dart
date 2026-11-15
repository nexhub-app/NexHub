/// 统一章节书签抽象（详情页重构 Phase 1）。
///
/// 漫画走 [ComicBookmarkManager]（Hive box `comic_bookmarks`），
/// 小说走 [NovelBookmarkManager]（Hive box `novel_bookmarks`）；
/// 两者字段几乎一致，仅小说多一个必填 `page`。影视无章节书签概念。
///
/// 重构前 `ComicDetailScreen` / `NovelDetailScreen` 各自维护一份
/// `_bookmarkedIndices` + `_loadBookmarks()` + `_toggleBookmark()`，
/// 逐字重复。这里收敛为一个接口，单一详情页按 [SourceType] 取实现，
/// 影视返回 null → 章节行自动不渲染书签按钮（[ChapterListSection]
/// 对 null 回调本就跳过渲染）。
library;

import '../comic/comic_bookmark_manager.dart';
import '../models/episode.dart';
import '../models/plugin_config.dart';
import '../../features/novel/presentation/novel_bookmark_manager.dart';

/// 章节书签仓库。
abstract class UnifiedBookmarkRepository {
  const UnifiedBookmarkRepository();

  /// 读取该内容的全部书签章节索引（失败返回空集合，不抛出）。
  Future<Set<int>> loadIndices(String contentId);

  /// 为指定章节新增一条书签。
  Future<void> add(String contentId, Episode chapter, int index);

  /// 删除指定章节的**全部**书签（一章可能有多条，统一清除）。
  Future<void> removeAt(String contentId, int index);

  /// 切换书签：已存在则清除，否则新增。返回操作后是否处于「已书签」状态。
  ///
  /// [currentlyBookmarked] 由调用方传入本地缓存判断结果，避免每次重读 Hive。
  Future<bool> toggle(
    String contentId,
    Episode chapter,
    int index, {
    required bool currentlyBookmarked,
  }) async {
    if (currentlyBookmarked) {
      await removeAt(contentId, index);
      return false;
    }
    await add(contentId, chapter, index);
    return true;
  }

  /// 按源类型构造实现；影视源无章节书签，返回 null。
  static UnifiedBookmarkRepository? forType(SourceType type) {
    return switch (type) {
      SourceType.mangaSource => ComicBookmarkRepository(),
      SourceType.novelSource => NovelBookmarkRepository(),
      SourceType.animeSource ||
      SourceType.videoSource ||
      SourceType.audioSource =>
        null,
    };
  }
}

/// 漫画章节书签实现。
class ComicBookmarkRepository extends UnifiedBookmarkRepository {
  ComicBookmarkRepository({ComicBookmarkManager? manager})
      : _manager = manager ?? ComicBookmarkManager();

  final ComicBookmarkManager _manager;

  @override
  Future<Set<int>> loadIndices(String contentId) async {
    try {
      final list = await _manager.listFor(contentId);
      return list.map((ComicBookmark b) => b.chapterIndex).toSet();
    } on Object {
      return <int>{};
    }
  }

  @override
  Future<void> add(String contentId, Episode chapter, int index) async {
    await _manager.add(
      ComicBookmark(
        comicId: contentId,
        chapterIndex: index,
        chapterId: chapter.id,
        chapterTitle: chapter.title,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  @override
  Future<void> removeAt(String contentId, int index) async {
    final list = await _manager.listFor(contentId);
    for (final b in list) {
      if (b.chapterIndex == index) {
        await _manager.remove(b.key);
      }
    }
  }
}

/// 小说章节书签实现（[NovelBookmark.page] 在详情页固定为 0，
/// 章节内精确页码由阅读器写入）。
class NovelBookmarkRepository extends UnifiedBookmarkRepository {
  NovelBookmarkRepository({NovelBookmarkManager? manager})
      : _manager = manager ?? NovelBookmarkManager();

  final NovelBookmarkManager _manager;

  @override
  Future<Set<int>> loadIndices(String contentId) async {
    try {
      final list = await _manager.listFor(contentId);
      return list.map((NovelBookmark b) => b.chapterIndex).toSet();
    } on Object {
      return <int>{};
    }
  }

  @override
  Future<void> add(String contentId, Episode chapter, int index) async {
    await _manager.add(
      NovelBookmark(
        novelId: contentId,
        chapterIndex: index,
        chapterId: chapter.id,
        chapterTitle: chapter.title,
        page: 0,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  @override
  Future<void> removeAt(String contentId, int index) async {
    final list = await _manager.listFor(contentId);
    for (final b in list) {
      if (b.chapterIndex == index) {
        await _manager.remove(b.key);
      }
    }
  }
}
