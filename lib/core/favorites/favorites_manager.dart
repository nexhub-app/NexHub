/// 收藏管理器（文档）。
///
/// 三模块共用，按 [SourceType] 隔离收藏列表。
/// 持久化到 [PrefsBackend]，UI 通过 [ChangeNotifier] 驱动。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../comic/models/reader_preferences.dart';
import '../models/media_item.dart';
import '../models/plugin_config.dart';
import '../storage/file_prefs_backend.dart';
import '../utils/app_log.dart';
import 'favorite_group.dart';

/// 收藏条目——精简版 MediaItem，只保留书架展示所需字段。
class FavoriteEntry {
  final String id;
  final String title;
  final String? coverUrl;
  final String? sourceId;
  final SourceType sourceType;
  final String? author;

  /// 中文书名（中文书名排序用）。多数作品 title 即中文名，本字段用于
  /// 「原书名 + 中文译名」并存的外语源作品；为空时排序回退到 [title]。
  final String? titleZh;

  /// 导演（媒体/动漫专属排序用）。来自 [MediaItem.director]，多数源无此字段，
  /// 排序时空值回退到 [title]。
  final String? director;

  /// 主演（媒体/动漫专属排序用）。来自 [MediaItem.actors]，空值回退到 [title]。
  final String? actors;

  final String? detailUrl;
  final int favoritedAt;

  /// 最后阅读时间（毫秒），0 表示未读过（收藏切换不丢 dateAdded/lastRead）。
  final int lastRead;

  /// 源站最新章/更新时间（毫秒，「最新章」排序用；0=未知）。
  /// 来自详情页解析的 updatedAt（小说源的 updateTime 字段），进详情页时回填。
  final int updatedAt;

  /// 上次查看目录时的章节总数（新章提示用；0=未记录）。
  /// 详情页/阅读器加载目录时回写；当前目录总数超过该值即视为「有新章」。
  final int lastSeenChapterCount;

  /// 分类（取自 MediaItem.tags 首项），用于书架筛选。
  final String? category;

  /// 状态（连载中 / 已完结），用于书架筛选。
  final String? status;

  /// 所属分组 id 列表（多分组标签），空表示未分组。
  final List<String> groupIds;

  /// 本地评分（0=未评，1-10），随 Bangumi 同步推送为 rate。
  final int myRating;

  /// 本地短评，随 Bangumi 同步推送为 comment。
  final String? myComment;

  const FavoriteEntry({
    required this.id,
    required this.title,
    required this.sourceType,
        this.coverUrl,
        this.sourceId,
        this.author,
        this.titleZh,
        this.director,
        this.actors,
        this.detailUrl,
        required this.favoritedAt,
    this.lastRead = 0,
    this.updatedAt = 0,
    this.lastSeenChapterCount = 0,
    this.category,
    this.status,
    this.groupIds = const <String>[],
    this.myRating = 0,
    this.myComment,
  });

  factory FavoriteEntry.fromMediaItem(MediaItem item,
          {int? favoritedAt, SourceType? sourceType}) =>
      FavoriteEntry(
        id: item.id,
        title: item.title,
        coverUrl: item.coverUrl,
        sourceId: item.sourceId,
        sourceType:
            sourceType ?? item.sourceType ?? SourceType.animeSource,
        author: item.author,
        titleZh: item.title,
        director: item.director,
        actors: item.actors,
        detailUrl: item.detailUrl,
        favoritedAt: favoritedAt ?? DateTime.now().millisecondsSinceEpoch,
        lastRead: 0,
        updatedAt: item.updatedAt?.millisecondsSinceEpoch ?? 0,
        lastSeenChapterCount: 0,
        category: item.tags?.isNotEmpty == true ? item.tags!.first : null,
        status: item.status,
      );

  /// 返回一个更新了 lastRead 的副本。
  FavoriteEntry withLastRead(int timestamp) => FavoriteEntry(
        id: id,
        title: title,
        coverUrl: coverUrl,
        sourceId: sourceId,
        sourceType: sourceType,
        author: author,
        titleZh: titleZh,
        director: director,
        actors: actors,
        detailUrl: detailUrl,
        favoritedAt: favoritedAt,
        lastRead: timestamp,
        updatedAt: updatedAt,
        lastSeenChapterCount: lastSeenChapterCount,
        category: category,
        status: status,
        groupIds: groupIds,
        myRating: myRating,
        myComment: myComment,
      );

  /// 返回一个更新了 coverUrl 的副本（用于"设为书架封面"）。
  FavoriteEntry withCoverUrl(String? newCoverUrl) => FavoriteEntry(
        id: id,
        title: title,
        coverUrl: newCoverUrl,
        sourceId: sourceId,
        sourceType: sourceType,
        author: author,
        titleZh: titleZh,
        director: director,
        actors: actors,
        detailUrl: detailUrl,
        favoritedAt: favoritedAt,
        lastRead: lastRead,
        updatedAt: updatedAt,
        lastSeenChapterCount: lastSeenChapterCount,
        category: category,
        status: status,
        groupIds: groupIds,
        myRating: myRating,
        myComment: myComment,
      );

  /// 返回一个更新了所属模块桶的副本（导入旧数据归一化用）。
  FavoriteEntry withSourceType(SourceType type) => FavoriteEntry(
        id: id,
        title: title,
        coverUrl: coverUrl,
        sourceId: sourceId,
        sourceType: type,
        author: author,
        titleZh: titleZh,
        director: director,
        actors: actors,
        detailUrl: detailUrl,
        favoritedAt: favoritedAt,
        lastRead: lastRead,
        updatedAt: updatedAt,
        lastSeenChapterCount: lastSeenChapterCount,
        category: category,
        status: status,
        groupIds: groupIds,
        myRating: myRating,
        myComment: myComment,
      );

  /// 返回一个更新了 groupIds 的副本（分组指定面板调用）。
  FavoriteEntry withGroupIds(List<String> newGroupIds) => FavoriteEntry(
        id: id,
        title: title,
        coverUrl: coverUrl,
        sourceId: sourceId,
        sourceType: sourceType,
        author: author,
        titleZh: titleZh,
        director: director,
        actors: actors,
        detailUrl: detailUrl,
        favoritedAt: favoritedAt,
        lastRead: lastRead,
        updatedAt: updatedAt,
        lastSeenChapterCount: lastSeenChapterCount,
        category: category,
        status: status,
        groupIds: List<String>.unmodifiable(newGroupIds),
        myRating: myRating,
        myComment: myComment,
      );

  /// 返回一个更新了本地评分 / 短评的副本（Bangumi 绑定面板调用）。
  FavoriteEntry withBangumiMeta({int? myRating, String? myComment}) =>
      FavoriteEntry(
        id: id,
        title: title,
        coverUrl: coverUrl,
        sourceId: sourceId,
        sourceType: sourceType,
        author: author,
        titleZh: titleZh,
        director: director,
        actors: actors,
        detailUrl: detailUrl,
        favoritedAt: favoritedAt,
        lastRead: lastRead,
        updatedAt: updatedAt,
        lastSeenChapterCount: lastSeenChapterCount,
        category: category,
        status: status,
        groupIds: groupIds,
        myRating: myRating ?? this.myRating,
        myComment: myComment ?? this.myComment,
      );

  /// 返回一个更新了「源站最新章时间」的副本（最新章排序，详情页回填）。
  FavoriteEntry withUpdatedAt(int millis) => FavoriteEntry(
        id: id,
        title: title,
        coverUrl: coverUrl,
        sourceId: sourceId,
        sourceType: sourceType,
        author: author,
        titleZh: titleZh,
        director: director,
        actors: actors,
        detailUrl: detailUrl,
        favoritedAt: favoritedAt,
        lastRead: lastRead,
        updatedAt: millis,
        lastSeenChapterCount: lastSeenChapterCount,
        category: category,
        status: status,
        groupIds: groupIds,
        myRating: myRating,
        myComment: myComment,
      );

  /// 返回一个更新了「已见章节数」的副本（新章提示，目录加载回写）。
  FavoriteEntry withLastSeenChapterCount(int count) => FavoriteEntry(
        id: id,
        title: title,
        coverUrl: coverUrl,
        sourceId: sourceId,
        sourceType: sourceType,
        author: author,
        titleZh: titleZh,
        director: director,
        actors: actors,
        detailUrl: detailUrl,
        favoritedAt: favoritedAt,
        lastRead: lastRead,
        updatedAt: updatedAt,
        lastSeenChapterCount: count,
        category: category,
        status: status,
        groupIds: groupIds,
        myRating: myRating,
        myComment: myComment,
      );

  MediaItem toMediaItem() => MediaItem(
        id: id,
        title: title,
        coverUrl: coverUrl,
        sourceId: sourceId,
        sourceType: sourceType,
        author: author,
        director: director,
        actors: actors,
        detailUrl: detailUrl,
        tags: category != null ? <String>[category!] : null,
        status: status,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'coverUrl': coverUrl,
        'sourceId': sourceId,
        'sourceType': sourceType.apiName,
        'author': author,
        'titleZh': titleZh,
        'director': director,
        'actors': actors,
        'detailUrl': detailUrl,
        'favoritedAt': favoritedAt,
        'lastRead': lastRead,
        'updatedAt': updatedAt,
        'lastSeenChapterCount': lastSeenChapterCount,
        'category': category,
        'status': status,
        'groupIds': groupIds,
        'myRating': myRating,
        'myComment': myComment,
      };

  factory FavoriteEntry.fromJson(Map<String, dynamic> json) => FavoriteEntry(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        coverUrl: json['coverUrl'] as String?,
        sourceId: json['sourceId'] as String?,
        sourceType:
            SourceType.parse(json['sourceType'] as String?) ?? SourceType.animeSource,
        author: json['author'] as String?,
        titleZh: json['titleZh'] as String?,
        director: json['director'] as String?,
        actors: json['actors'] as String?,
        detailUrl: json['detailUrl'] as String?,
        favoritedAt: json['favoritedAt'] as int? ?? 0,
        lastRead: json['lastRead'] as int? ?? 0,
        updatedAt: json['updatedAt'] as int? ?? 0,
        lastSeenChapterCount: json['lastSeenChapterCount'] as int? ?? 0,
        category: json['category'] as String?,
        status: json['status'] as String?,
        groupIds:
            (json['groupIds'] as List?)?.cast<String>() ?? const <String>[],
        myRating: json['myRating'] as int? ?? 0,
        myComment: json['myComment'] as String?,
      );
}

/// 收藏管理器——全应用单例（Provider 注入）。
class FavoritesManager extends ChangeNotifier {
  FavoritesManager({PrefsBackend? backend})
      // 默认走独立文件存储：收藏整列表 JSON 可达数百 KB，shared_preferences
      // 底层「轻量级偏好存储」在鸿蒙对大字符串值落盘不可靠且失败静默
      // （历史记录曾因此重启丢失）。
      : _backend = backend ?? FilePrefsBackend();

  final PrefsBackend _backend;
  static const String _key = 'favorites_v1';
  static const String _groupsKey = 'favorite_groups_v1';

  final Map<SourceType, List<FavoriteEntry>> _cache = {};

  /// 本次启动是否加载失败。失败时内存状态不完整（其他模块桶为空），
  /// 任何全量覆盖写盘都会把磁盘上的好数据冲掉——「收藏后清后台重进
  /// 收藏消失」的典型链条正是「启动读失败当空 → 随后回写空列表」。
  /// 因此加载失败期间 [_persist]/[_persistGroups] 拒绝写盘，
  /// 宁可本次会话改动不落盘（重启后磁盘数据仍可恢复）。
  bool _loadFailed = false;

  /// 持久化桶：视频/音频源与影视源共用媒体桶（见 [SourceType.mediaBucket]），
  /// 保证媒体书架/分组能查到它们，条目不会落进无人查询的孤儿桶。
  List<FavoriteEntry>? _bucket(SourceType type) => _cache[type.mediaBucket];

  /// 分组列表（内存态，按 sortOrder 排序后缓存）。
  final List<FavoriteGroup> _groups = <FavoriteGroup>[];

  /// 一次性迁移：旧版本收藏存于 shared_preferences，其底层对大字符串值
  /// 落盘不可靠（鸿蒙 dataPreferences 失败静默）。文件后端不存在而旧值
  /// 还在时搬过来，之后以文件为准（旧键保留不动，作兜底）。
  Future<void> _migrateLegacy(String key) async {
    try {
      final legacy = await const SharedPrefsBackend().get(key);
      if (legacy != null && legacy.isNotEmpty) {
        await _backend.set(key, legacy);
        AppLog.instance
            .i('[收藏] 已从偏好存储迁移到独立文件（$key，${legacy.length} 字节）');
      }
    } on Object catch (e) {
      AppLog.instance.w('[收藏] 迁移旧偏好存储失败（$key）: $e');
    }
  }

  /// 加载持久化数据（收藏 + 分组）。
  ///
  /// 任何加载失败（读取异常 / 数据损坏）都置 [_loadFailed] 并跳过解析，
  /// 本次运行暂停写盘防覆盖；磁盘数据保住，下次启动仍可恢复。
  Future<void> init() async {
    try {
      String? raw = await _backend.get(_key);
      if (raw == null && _backend is FilePrefsBackend) {
        await _migrateLegacy(_key);
        raw = await _backend.get(_key);
      }
      if (raw != null) {
        try {
          final list = jsonDecode(raw) as List<dynamic>;
          for (final item in list) {
            final entry = FavoriteEntry.fromJson(item as Map<String, dynamic>);
            _cache
                .putIfAbsent(entry.sourceType, () => <FavoriteEntry>[])
                .add(entry);
          }
          AppLog.instance.i('[收藏] 加载 ${list.length} 条');
        } on Object catch (e) {
          // 损坏数据：视为加载失败（后端已尽力回退备份），拒绝后续写盘。
          AppLog.instance.e('[收藏] 数据解析失败，按加载失败处理: $e');
          rethrow;
        }
      }
      String? rawGroups = await _backend.get(_groupsKey);
      if (rawGroups == null && _backend is FilePrefsBackend) {
        await _migrateLegacy(_groupsKey);
        rawGroups = await _backend.get(_groupsKey);
      }
      if (rawGroups != null) {
        try {
          final list = jsonDecode(rawGroups) as List<dynamic>;
          final maps = list.cast<Map<String, dynamic>>();
          // 统计每个分组在各模块下的条目数，用于旧数据（无 sourceType）的智能归类。
          final Map<String, Map<SourceType, int>> groupTypeCounts =
              <String, Map<SourceType, int>>{};
          for (final entries in _cache.values) {
            for (final entry in entries) {
              for (final gid in entry.groupIds) {
                (groupTypeCounts[gid] ??= <SourceType, int>{})
                    .update(entry.sourceType, (c) => c + 1, ifAbsent: () => 1);
              }
            }
          }
          _groups
            ..clear()
            ..addAll(maps.map((Map<String, dynamic> m) {
              final FavoriteGroup g = FavoriteGroup.fromJson(m);
              // 旧分组数据无 sourceType：按条目归属智能判定所属模块。
              // 跨模块共享的分组归到条目最多的模块；无条目归属则默认影视。
              if (!m.containsKey('sourceType')) {
                final Map<SourceType, int>? counts = groupTypeCounts[g.id];
                SourceType resolved = SourceType.animeSource;
                int best = -1;
                if (counts != null) {
                  for (final MapEntry<SourceType, int> e in counts.entries) {
                    if (e.value > best) {
                      best = e.value;
                      resolved = e.key;
                    }
                  }
                }
                return g.copyWith(sourceType: resolved);
              }
              return g;
            }));
          _groups.sortByOrder();
          AppLog.instance.i('[收藏] 分组加载 ${maps.length} 个');
        } on Object catch (e) {
          AppLog.instance.e('[收藏] 分组数据解析失败，按加载失败处理: $e');
          rethrow;
        }
      }
      _loadFailed = false;
    } on Object catch (e) {
      _loadFailed = true;
      AppLog.instance.e('[收藏] 启动加载失败，本次运行暂停写盘以防覆盖磁盘数据: $e');
    }
    notifyListeners();
  }

  /// 获取某模块的收藏列表（按收藏时间倒序）。
  List<FavoriteEntry> favoritesFor(SourceType type) =>
      List.unmodifiable(_bucket(type)?.reversed.toList() ?? const <FavoriteEntry>[]);

  /// 获取某模块的收藏列表（按收藏时间倒序），并排除「仅属于隐藏分类」的条目。
  ///
  /// 用于收藏书架的「全部」视图：隐藏分类既不在分类栏也不在筛选中可见，
  /// 因此「全部」应等价于「所有可见分类 + 未分组」的并集。
  ///
  /// 注意：Bangumi 同步、分组指派、绑定面板等场景仍需完整列表，请用
  /// [favoritesFor] 而非本方法。
  List<FavoriteEntry> visibleFavoritesFor(SourceType type) {
    final visibleGroupIds = groupsFor(type).map((g) => g.id).toSet();
    return favoritesFor(type)
        .where((e) =>
            e.groupIds.isEmpty || e.groupIds.any(visibleGroupIds.contains))
        .toList();
  }

  /// 是否已收藏。
  bool isFavorite(String contentId, SourceType type) =>
      _bucket(type)?.any((e) => e.id == contentId) ?? false;

  /// 切换收藏状态。重新收藏时保留原始 favoritedAt（不丢 dateAdded）。
  ///
  /// [type] 显式指定归属模块：条目自身缺 `sourceType`（脚本源解析的 MediaItem
  /// 均为 null）时，调用方（详情页）按源配置反查出的类型才是正确归属——
  /// 若不传而走 `item.sourceType` 兜底 animeSource，会把漫画/小说收藏进动漫
  /// 书架，且详情页图标按正确类型查询永远不亮（表现为「无法收藏」）。
  Future<void> toggleFavorite(MediaItem item, {SourceType? type}) async {
    final t = (type ?? item.sourceType ?? SourceType.animeSource).mediaBucket;
    final list = _cache.putIfAbsent(t, () => <FavoriteEntry>[]);

    final idx = list.indexWhere((e) => e.id == item.id);
    if (idx >= 0) {
      // 取消收藏：保留原 favoritedAt 和 lastRead，以便重新收藏时不丢
      final old = list[idx];
      _removedFavoriteCache[item.id] = old;
      list.removeAt(idx);
    } else {
      // 检查是否有刚被移除的缓存（保留原 favoritedAt + lastRead）
      final cached = _removedFavoriteCache.remove(item.id);
      if (cached != null) {
        // 重新收藏：保留原 favoritedAt 和 lastRead，但更新封面/作者等字段
        list.add(FavoriteEntry.fromMediaItem(item,
            favoritedAt: cached.favoritedAt, sourceType: t));
        // 保留 lastRead + groupIds（fromMediaItem 会重置）
        final newIdx = list.length - 1;
        list[newIdx] = list[newIdx]
            .withLastRead(cached.lastRead)
            .withGroupIds(cached.groupIds);
      } else {
        list.add(FavoriteEntry.fromMediaItem(item, sourceType: t));
      }
    }
    await _persist();
    notifyListeners();
  }

  /// 更新某收藏条目的 lastRead 时间戳（阅读器内调用）。
  Future<void> updateLastRead(String contentId, SourceType type) async {
    final list = _bucket(type);
    if (list == null) return;
    final idx = list.indexWhere((e) => e.id == contentId);
    if (idx < 0) return;
    list[idx] = list[idx].withLastRead(DateTime.now().millisecondsSinceEpoch);
    await _persist();
    notifyListeners();
  }

  /// 更新某收藏条目的「已见章节数」（新章提示，详情页/阅读器目录加载回写）。
  ///
  /// 仅更新已存在条目；[count] 非正数时为无操作。回写后书架上
  /// 「当前目录总数 > 已见数」的新章角标即消失。
  Future<void> updateLastSeenChapters(
    String contentId,
    SourceType type,
    int count,
  ) async {
    if (count <= 0) return;
    final list = _bucket(type);
    if (list == null) return;
    final idx = list.indexWhere((e) => e.id == contentId);
    if (idx < 0) return;
    if (list[idx].lastSeenChapterCount == count) return;
    list[idx] = list[idx].withLastSeenChapterCount(count);
    await _persist();
    notifyListeners();
  }

  /// 更新某收藏条目的「源站最新章时间」（最新章排序，详情页刷新回填）。
  ///
  /// 仅更新已存在条目（不自动创建）；[updatedAtMs] 非正数或与现值相同
  /// 时为无操作。
  Future<void> updateUpdatedAt(
    String contentId,
    SourceType type,
    int updatedAtMs,
  ) async {
    if (updatedAtMs <= 0) return;
    final list = _bucket(type);
    if (list == null) return;
    final idx = list.indexWhere((e) => e.id == contentId);
    if (idx < 0) return;
    if (list[idx].updatedAt == updatedAtMs) return;
    list[idx] = list[idx].withUpdatedAt(updatedAtMs);
    await _persist();
    notifyListeners();
  }

  /// 更新某收藏条目的本地评分 / 短评（Bangumi 绑定面板调用）。
  Future<bool> updateBangumiMeta(
    String contentId,
    SourceType type, {
    int? myRating,
    String? myComment,
  }) async {
    final list = _bucket(type);
    if (list == null) return false;
    final idx = list.indexWhere((e) => e.id == contentId);
    if (idx < 0) return false;
    list[idx] =
        list[idx].withBangumiMeta(myRating: myRating, myComment: myComment);
    await _persist();
    notifyListeners();
    return true;
  }

  /// 更新某收藏条目的封面 URL（"设为书架封面"调用）。
  Future<bool> updateCover(
    String contentId,
    SourceType type,
    String? newCoverUrl,
  ) async {
    final list = _bucket(type);
    if (list == null) return false;
    final idx = list.indexWhere((e) => e.id == contentId);
    if (idx < 0) return false;
    list[idx] = list[idx].withCoverUrl(newCoverUrl);
    await _persist();
    notifyListeners();
    return true;
  }

  /// 已移除收藏的临时缓存（key=contentId），用于重新收藏时保留原 favoritedAt/lastRead。
  /// 仅内存态，应用重启后不保留。
  final Map<String, FavoriteEntry> _removedFavoriteCache = {};

  /// 移除收藏。
  Future<void> removeFavorite(String contentId, SourceType type) async {
    final list = _bucket(type);
    if (list == null) return;
    list.removeWhere((e) => e.id == contentId);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    if (_loadFailed) {
      // 内存列表不完整（部分桶未加载），全量覆盖会把磁盘好数据冲掉。
      AppLog.instance.e('[收藏] 跳过写盘：本次启动加载失败，防覆盖保护生效');
      return;
    }
    final all = <Map<String, dynamic>>[];
    for (final list in _cache.values) {
      all.addAll(list.map((e) => e.toJson()));
    }
    try {
      await _backend.set(_key, jsonEncode(all));
    } on Object catch (e) {
      AppLog.instance.e('[收藏] 写盘失败（${all.length} 条）: $e');
      rethrow;
    }
  }

  /// Export all favorites as a JSON-serializable list.
  List<Map<String, dynamic>> exportToJson() {
    final all = <Map<String, dynamic>>[];
    for (final list in _cache.values) {
      all.addAll(list.map((e) => e.toJson()));
    }
    return all;
  }

  /// Import favorites from a parsed JSON list (merge, dedup by id).
  Future<void> importFromList(List<dynamic> items) async {
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      final parsed = FavoriteEntry.fromJson(item);
      final entry = parsed.sourceType == parsed.sourceType.mediaBucket
          ? parsed
          : parsed.withSourceType(parsed.sourceType.mediaBucket);
      final list =
          _cache.putIfAbsent(entry.sourceType, () => <FavoriteEntry>[]);
      if (list.any((e) => e.id == entry.id)) continue;
      list.add(entry);
    }
    await _persist();
    notifyListeners();
  }

  // ────────────────────── 分组 API ──────────────────────

  /// 某模块下的分组（按 sortOrder 升序，不可变视图）。
  /// [includeHidden] 为 true 时一并返回隐藏分组（用于「分类管理」面板）。
  List<FavoriteGroup> groupsFor(SourceType type,
      {bool includeHidden = false}) {
    final List<FavoriteGroup> result = _groups
        .where((g) => g.sourceType.mediaBucket == type.mediaBucket && (includeHidden || !g.hidden))
        .toList()
      ..sortByOrder();
    return List.unmodifiable(result);
  }

  /// 按 id 查分组（不存在返回 null）。
  FavoriteGroup? groupById(String id) {
    for (final g in _groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// 某分组下的收藏条目总数（仅统计同模块）。
  int entryCountInGroup(String groupId, {required SourceType type}) {
    final list = _bucket(type);
    if (list == null) return 0;
    return list.where((e) => e.groupIds.contains(groupId)).length;
  }

  /// 某收藏条目所属的分组 id 列表（多分组标签；未收藏返回空列表）。
  /// 用于「读后自动删除」按收藏分类判断是否排除。
  List<String> groupIdsOf(String contentId, SourceType type) {
    final list = _bucket(type);
    if (list == null) return const <String>[];
    final int idx = list.indexWhere((e) => e.id == contentId);
    if (idx < 0) return const <String>[];
    return list[idx].groupIds;
  }

  /// 创建分组（限定模块内重名校验）。重名（trim 后）拒绝并返回 null。
  Future<FavoriteGroup?> createGroup(String name,
      {required SourceType type}) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    if (_groups.any((g) => g.sourceType.mediaBucket == type.mediaBucket && g.name == trimmed)) {
      return null;
    }
    final group = FavoriteGroup(
      id: FavoriteGroup.newId(),
      name: trimmed,
      sourceType: type.mediaBucket,
      sortOrder: _nextSortOrder(type),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _groups.add(group);
    await _persistGroups();
    notifyListeners();
    return group;
  }

  /// 模块内下一个排序序号（同模块现有最大 sortOrder + 1，空则 0）。
  int _nextSortOrder(SourceType type) {
    int max = -1;
    for (final g in _groups) {
      if (g.sourceType.mediaBucket == type.mediaBucket && g.sortOrder > max) max = g.sortOrder;
    }
    return max + 1;
  }

  /// 重命名分组。重名 / 空名 / 分组不存在时返回 false。
  /// 重名校验限定在同模块内进行。
  Future<bool> renameGroup(String id, String name) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    final int idx = _groups.indexWhere((g) => g.id == id);
    if (idx < 0) return false;
    final SourceType type = _groups[idx].sourceType;
    if (_groups.any(
        (g) => g.id != id && g.sourceType.mediaBucket == type.mediaBucket && g.name == trimmed)) {
      return false;
    }
    _groups[idx] = _groups[idx].copyWith(name: trimmed);
    await _persistGroups();
    notifyListeners();
    return true;
  }

  /// 删除分组：级联从同模块条目的 groupIds 中移除该 id，条目本身保留。
  Future<void> deleteGroup(String id) async {
    final int idx = _groups.indexWhere((g) => g.id == id);
    if (idx < 0) return;
    final SourceType type = _groups[idx].sourceType;
    _groups.removeAt(idx);
    bool entriesChanged = false;
    final list = _bucket(type);
    if (list != null) {
      for (int i = 0; i < list.length; i++) {
        if (list[i].groupIds.contains(id)) {
          list[i] = list[i].withGroupIds(
              list[i].groupIds.where((g) => g != id).toList());
          entriesChanged = true;
        }
      }
    }
    await _persistGroups();
    if (entriesChanged) await _persist();
    notifyListeners();
  }

  /// 按给定 id 顺序重排分组（仅作用于同模块；未出现的同模块 id 排在末尾）。
  Future<void> reorderGroups(List<String> orderedIds,
      {required SourceType type}) async {
    final Map<String, int> order = <String, int>{
      for (int i = 0; i < orderedIds.length; i++) orderedIds[i]: i,
    };
    for (final g in _groups.where((x) => x.sourceType == type)) {
      final int? pos = order[g.id];
      if (pos != null) {
        final int idx = _groups.indexWhere((x) => x.id == g.id);
        _groups[idx] = g.copyWith(sortOrder: pos);
      }
    }
    // 归一化同模块 sortOrder 为连续序号
    final List<FavoriteGroup> ordered = _groups
        .where((g) => g.sourceType.mediaBucket == type.mediaBucket)
        .toList()
      ..sortByOrder();
    for (int i = 0; i < ordered.length; i++) {
      final int idx = _groups.indexWhere((x) => x.id == ordered[i].id);
      _groups[idx] = ordered[i].copyWith(sortOrder: i);
    }
    await _persistGroups();
    notifyListeners();
  }

  /// 切换分组的隐藏状态。隐藏后不显示在分类栏 / 筛选，
  /// 但「分类管理」面板中仍可见并可恢复。
  Future<void> setGroupHidden(String id, bool hidden) async {
    final int idx = _groups.indexWhere((g) => g.id == id);
    if (idx < 0) return;
    _groups[idx] = _groups[idx].copyWith(hidden: hidden);
    await _persistGroups();
    notifyListeners();
  }

  /// 设置某收藏条目的分组（覆盖式，自动过滤不存在的分组 id）。
  Future<bool> setEntryGroups(
    String contentId,
    SourceType type,
    List<String> groupIds,
  ) async {
    final list = _bucket(type);
    if (list == null) return false;
    final int idx = list.indexWhere((e) => e.id == contentId);
    if (idx < 0) return false;
    final Set<String> valid = _groups
        .where((g) => g.sourceType.mediaBucket == type.mediaBucket)
        .map((g) => g.id)
        .toSet();
    list[idx] = list[idx]
        .withGroupIds(groupIds.where(valid.contains).toList());
    await _persist();
    notifyListeners();
    return true;
  }

  Future<void> _persistGroups() async {
    if (_loadFailed) {
      AppLog.instance.e('[收藏] 跳过分组写盘：本次启动加载失败，防覆盖保护生效');
      return;
    }
    try {
      await _backend.set(
          _groupsKey, jsonEncode(_groups.map((g) => g.toJson()).toList()));
    } on Object catch (e) {
      AppLog.instance.e('[收藏] 分组写盘失败（${_groups.length} 个）: $e');
      rethrow;
    }
  }

  /// Export all groups as a JSON-serializable list.
  List<Map<String, dynamic>> exportGroups() =>
      _groups.map((g) => g.toJson()).toList();

  /// Import groups from a parsed JSON list (merge, dedup by id & name).
  Future<void> importGroups(List<dynamic> items) async {
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      final group = FavoriteGroup.fromJson(item);
      if (group.id.isEmpty || group.name.isEmpty) continue;
      if (_groups.any((g) =>
          g.id == group.id ||
          (g.name == group.name && g.sourceType == group.sourceType))) {
        continue;
      }
      _groups.add(group);
    }
    _groups.sortByOrder();
    await _persistGroups();
    notifyListeners();
  }
}

extension on List<FavoriteGroup> {
  /// 按 sortOrder 升序排序（同序号按创建时间兼容）。
  void sortByOrder() => sort((a, b) {
        final int c = a.sortOrder.compareTo(b.sortOrder);
        return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
      });
}
