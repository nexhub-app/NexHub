/// Bangumi 同步编排服务（推送为主 + 空缺回拉的双向同步）。
///
/// 流程：遍历启用类型下的收藏 → 解析 subject 绑定 → 读远端收藏 →
/// 空缺回拉（本地无评分/短评而远端有则写回本地）→ 判定收藏状态 →
/// （动漫）增量标记已看集 / （书籍）推送阅读进度 ep_status →
/// PATCH 部分更新（未收藏回退 POST）。
/// 单条失败记日志不中断整体；token 失效（401）时终止本轮。
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../comic/comic_progress_manager.dart';
import '../../comic/models/reader_preferences.dart';
import '../../favorites/favorites_manager.dart';
import '../../history/media_watched_manager.dart';
import '../../models/plugin_config.dart';
import '../../novel/novel_progress_manager.dart';
import 'bangumi_auth.dart';
import 'bangumi_client.dart';
import 'bangumi_models.dart';
import 'subject_link_store.dart';

/// Bangumi 同步服务——全应用单例（Provider 注入）。
class BangumiSyncService extends ChangeNotifier {
  BangumiSyncService({
    required BangumiClient client,
    required BangumiAuth auth,
    required SubjectLinkStore linkStore,
    required FavoritesManager favorites,
    required MediaWatchedManager watched,
    ComicProgressManager? comicProgress,
    NovelProgressManager? novelProgress,
    PrefsBackend? backend,
  })  : _client = client,
        _auth = auth,
        _linkStore = linkStore,
        _favorites = favorites,
        _watched = watched,
        _comicProgress = comicProgress ?? ComicProgressManager(),
        _novelProgress = novelProgress ?? NovelProgressManager(),
        _backend = backend ?? const SharedPrefsBackend() {
    // 桥接：让 UI 订阅 SyncService 也能感知到 Auth 登录/登出。
    // 之前订阅 SyncService 的页面（如 settings_bangumi_screen）只读 auth 字段
    // 而不订阅 Auth 本身，logout 后 UI 不刷新——通过 addListener 转发即可。
    _auth.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _auth.removeListener(notifyListeners);
    super.dispose();
  }

  static const String _lastSyncKey = 'bangumi_last_sync';
  static const String _syncAnimeKey = 'bangumi_sync_anime';
  static const String _syncMangaKey = 'bangumi_sync_manga';
  static const String _syncNovelKey = 'bangumi_sync_novel';
  static const String _privateKey = 'bangumi_private';
  static const String _tagsKey = 'bangumi_tags';

  final BangumiClient _client;
  final BangumiAuth _auth;
  final SubjectLinkStore _linkStore;
  final FavoritesManager _favorites;
  final MediaWatchedManager _watched;
  final ComicProgressManager _comicProgress;
  final NovelProgressManager _novelProgress;
  final PrefsBackend _backend;

  bool _isSyncing = false;
  int? _lastSyncAt;
  List<SyncLogItem> _lastLog = const <SyncLogItem>[];
  final Map<SourceType, bool> _typeEnabled = <SourceType, bool>{
    SourceType.animeSource: true,
    SourceType.mangaSource: true,
    SourceType.novelSource: true,
  };
  bool _privateEnabled = false;
  bool _tagsEnabled = false;

  bool get isSyncing => _isSyncing;

  /// 上次同步时间（毫秒），null 表示从未同步。
  int? get lastSyncAt => _lastSyncAt;

  /// 上一轮同步日志。
  List<SyncLogItem> get lastLog => List.unmodifiable(_lastLog);

  BangumiAuth get auth => _auth;

  SubjectLinkStore get linkStore => _linkStore;

  BangumiClient get client => _client;

  /// 加载持久化状态（上次同步时间 + 类型开关 + 私有/标签开关）。
  Future<void> init() async {
    final rawLast = await _backend.get(_lastSyncKey);
    _lastSyncAt = int.tryParse(rawLast ?? '');
    _typeEnabled[SourceType.animeSource] =
        (await _backend.get(_syncAnimeKey)) != '0';
    _typeEnabled[SourceType.mangaSource] =
        (await _backend.get(_syncMangaKey)) != '0';
    _typeEnabled[SourceType.novelSource] =
        (await _backend.get(_syncNovelKey)) != '0';
    _privateEnabled = (await _backend.get(_privateKey)) == '1';
    _tagsEnabled = (await _backend.get(_tagsKey)) == '1';
    notifyListeners();
  }

  /// 某类型是否启用同步。
  bool typeEnabled(SourceType type) => _typeEnabled[type] ?? true;

  /// 设置类型开关。
  Future<void> setTypeEnabled(SourceType type, bool enabled) async {
    _typeEnabled[type] = enabled;
    final key = switch (type) {
      SourceType.animeSource ||
      SourceType.videoSource ||
      SourceType.audioSource =>
        _syncAnimeKey,
      SourceType.mangaSource => _syncMangaKey,
      SourceType.novelSource => _syncNovelKey,
    };
    await _backend.set(key, enabled ? '1' : '0');
    notifyListeners();
  }

  /// 新建收藏是否设为私有（仅影响首次创建，不改动远端已有收藏）。
  bool get privateEnabled => _privateEnabled;

  Future<void> setPrivateEnabled(bool enabled) async {
    _privateEnabled = enabled;
    await _backend.set(_privateKey, enabled ? '1' : '0');
    notifyListeners();
  }

  /// 是否将本地收藏分组名作为标签合并推送。
  bool get tagsEnabled => _tagsEnabled;

  Future<void> setTagsEnabled(bool enabled) async {
    _tagsEnabled = enabled;
    await _backend.set(_tagsKey, enabled ? '1' : '0');
    notifyListeners();
  }

  /// 立即同步全部启用类型的收藏。
  ///
  /// 未登录抛 [StateError]；返回本轮日志（同 [lastLog]）。
  Future<List<SyncLogItem>> syncAll() async {
    if (!_auth.isLoggedIn) {
      throw StateError('not logged in');
    }
    if (_isSyncing) return lastLog;
    _isSyncing = true;
    notifyListeners();
    final log = <SyncLogItem>[];
    try {
      outer:
      for (final type in SourceType.values) {
        if (!typeEnabled(type)) continue;
        for (final entry in _favorites.favoritesFor(type)) {
          try {
            log.add(await _syncEntry(entry));
          } on BangumiApiException catch (e) {
            log.add(SyncLogItem(
              title: entry.title,
              status: SyncLogStatus.failed,
              detail: e.message,
            ));
            // token 失效时后续请求必然失败，终止本轮。
            if (e.isUnauthorized) break outer;
          } on Object catch (e) {
            log.add(SyncLogItem(
              title: entry.title,
              status: SyncLogStatus.failed,
              detail: e.toString(),
            ));
          }
        }
      }
      _lastSyncAt = DateTime.now().millisecondsSinceEpoch;
      await _backend.set(_lastSyncKey, '$_lastSyncAt');
    } finally {
      _lastLog = log;
      _isSyncing = false;
      notifyListeners();
    }
    return lastLog;
  }

  /// 同步单个内容条目（详情页一键同步入口）。
  ///
  /// 未登录抛 [StateError]；条目未收藏或正在同步中返回 null；
  /// 失败不抛出，统一封装为 [SyncLogStatus.failed] 日志项。
  ///
  /// [watchedEpisodes]（动漫，1 起）：手动指定已看集数，覆盖本地观看记录；
  /// 传 null 时回退到 [_watched] 本地集合自动计算。
  /// [watchedChapters]（书籍，1 起）：手动指定已读章节数（Bangumi ep_status）；
  /// 传 null 时回退到 [_bookProgress] 自动计算。
  Future<SyncLogItem?> syncOne(
    String contentId,
    SourceType sourceType, {
    int? watchedEpisodes,
    int? watchedChapters,
  }) async {
    if (!_auth.isLoggedIn) {
      throw StateError('not logged in');
    }
    if (_isSyncing) return null;
    final entry = _favorites
        .favoritesFor(sourceType)
        .where((e) => e.id == contentId)
        .firstOrNull;
    if (entry == null) return null;
    _isSyncing = true;
    notifyListeners();
    SyncLogItem item;
    try {
      item = await _syncEntry(
        entry,
        watchedEpisodes: watchedEpisodes,
        watchedChapters: watchedChapters,
      );
    } on BangumiApiException catch (e) {
      item = SyncLogItem(
        title: entry.title,
        status: SyncLogStatus.failed,
        detail: e.message,
      );
    } on Object catch (e) {
      item = SyncLogItem(
        title: entry.title,
        status: SyncLogStatus.failed,
        detail: e.toString(),
      );
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
    return item;
  }

  /// 同步单个收藏条目。
  ///
  /// [watchedEpisodes]（动漫，1 起）：手动指定已看集数，覆盖本地观看记录；
  /// 传 null 时回退到 [_watched] 本地集合自动计算。
  /// [watchedChapters]（书籍，1 起）：手动指定已读章节数（Bangumi ep_status）；
  /// 传 null 时回退到 [_bookProgress] 自动计算。
  Future<SyncLogItem> _syncEntry(
    FavoriteEntry entry, {
    int? watchedEpisodes,
    int? watchedChapters,
  }) async {
    final result =
        await _linkStore.resolve(entry.id, entry.title, entry.sourceType);
    final link = result.link;
    if (link == null) {
      return SyncLogItem(
        title: entry.title,
        status: SyncLogStatus.pendingBind,
      );
    }

    // 远端收藏只读一次，后续回拉与推送判定共用。
    final remote = await _client.fetchUserCollection(link.subjectId);
    // 空缺回拉：本地未评分/无短评而远端有值时写回本地。
    entry = await _pullBackMeta(entry, remote);

    // 状态判定 + 动漫增量标集 / 书籍阅读进度。
    int desiredType;
    int? epStatus;
    if (entry.sourceType == SourceType.animeSource) {
      // 手动指定已看集数时生成 0..N-1 索引列表，否则回退本地观看记录。
      final watchedIndexes = (watchedEpisodes != null && watchedEpisodes > 0)
          ? List.generate(watchedEpisodes, (i) => i)
          : _watched.watchedList(entry.id);
      if (watchedIndexes.isEmpty) {
        desiredType = BangumiCollectionType.wish;
      } else {
        final episodes = await _client.fetchEpisodes(link.subjectId);
        // 本地 episodeIndex i（0 起）→ 第 i+1 个本篇；越界的多余集跳过。
        final episodeIds = <int>[
          for (final i in watchedIndexes)
            if (i >= 0 && i < episodes.length) episodes[i].id,
        ];
        desiredType = (episodes.isNotEmpty &&
                episodeIds.length >= episodes.length)
            ? BangumiCollectionType.collect
            : BangumiCollectionType.doing;
        // 先建收藏再标已看集（Bangumi 要求条目已在收藏中才能标记剧集）。
        final pushed = await _pushCollection(entry, link, desiredType, remote);
        // 增量标集：先读远端章节收藏，只标记尚未「看过」的差集。
        final remoteEps = await _client.fetchCollectedEpisodes(link.subjectId);
        final diff = <int>[
          for (final id in episodeIds)
            if (remoteEps[id] != 2) id,
        ];
        await _client.markEpisodesWatched(link.subjectId, diff);
        return SyncLogItem(
          title: entry.title,
          status: (pushed || diff.isNotEmpty)
              ? SyncLogStatus.success
              : SyncLogStatus.skipped,
        );
      }
    } else {
      // 漫画 / 小说：阅读进度 → ep_status（书籍类条目可写完成度）；
      // 读到末章（总章数已知）则判定为读过。
      if (watchedChapters != null && watchedChapters >= 0) {
        // 手动指定已读章节数（0 表示尚未开始阅读）。
        epStatus = watchedChapters;
        final progress = await _bookProgress(entry);
        final total = progress?.$2;
        desiredType = (total != null && total > 0 && epStatus >= total)
            ? BangumiCollectionType.collect
            : (epStatus > 0
                ? BangumiCollectionType.doing
                : BangumiCollectionType.wish);
      } else {
        final progress = await _bookProgress(entry);
        if (progress == null) {
          desiredType = entry.lastRead > 0
              ? BangumiCollectionType.doing
              : BangumiCollectionType.wish;
        } else {
          epStatus = progress.$1;
          final total = progress.$2;
          desiredType = (total != null && total > 0 && epStatus >= total)
              ? BangumiCollectionType.collect
              : BangumiCollectionType.doing;
        }
      }
    }
    final pushed =
        await _pushCollection(entry, link, desiredType, remote, epStatus: epStatus);
    return SyncLogItem(
      title: entry.title,
      status: pushed ? SyncLogStatus.success : SyncLogStatus.skipped,
    );
  }

  /// 空缺回拉：仅在本地为空而远端有值时写回，本地已有值以本地为准。
  ///
  /// 返回写回后的条目副本（供后续推送判定使用最新值）。
  Future<FavoriteEntry> _pullBackMeta(
    FavoriteEntry entry,
    BangumiUserCollection? remote,
  ) async {
    if (remote == null) return entry;
    final bool needRate = entry.myRating <= 0 && remote.rate > 0;
    final localComment = entry.myComment?.trim() ?? '';
    final bool needComment =
        localComment.isEmpty && remote.comment.isNotEmpty;
    if (!needRate && !needComment) return entry;
    await _favorites.updateBangumiMeta(
      entry.id,
      entry.sourceType,
      myRating: needRate ? remote.rate : null,
      myComment: needComment ? remote.comment : null,
    );
    return entry.withBangumiMeta(
      myRating: needRate ? remote.rate : null,
      myComment: needComment ? remote.comment : null,
    );
  }

  /// 书籍阅读进度：(已读章节数 = chapterIndex+1, 总章数)；无记录返回 null。
  Future<(int, int?)?> _bookProgress(FavoriteEntry entry) async {
    switch (entry.sourceType) {
      case SourceType.mangaSource:
        final p = await _comicProgress.get(entry.id);
        if (p == null) return null;
        return (p.chapterIndex + 1, p.totalChapters);
      case SourceType.novelSource:
        final p = await _novelProgress.get(entry.id);
        if (p == null) return null;
        return (p.chapterIndex + 1, p.totalChapters);
      case SourceType.animeSource:
      case SourceType.videoSource:
      case SourceType.audioSource:
        return null;
    }
  }

  /// 本地收藏分组名 → Bangumi 标签（去空白，Bangumi 标签不含空格）。
  List<String> _localTags(FavoriteEntry entry) => <String>[
        for (final id in entry.groupIds)
          if (_favorites.groupById(id) != null)
            _favorites.groupById(id)!.name.replaceAll(RegExp(r'\s+'), ''),
      ]..removeWhere((t) => t.isEmpty);

  /// 状态推进序（想看 < 在看 < 看过）；搁置/抛弃视为远端最高优先，不覆盖。
  static int _rank(int type) => switch (type) {
        BangumiCollectionType.wish => 0,
        BangumiCollectionType.doing => 1,
        BangumiCollectionType.collect => 2,
        _ => 3,
      };

  /// 推送收藏变更：已收藏时 PATCH 仅携带变化字段，未收藏时 POST 创建；
  /// 无变化不发请求，返回是否已推送。
  Future<bool> _pushCollection(
    FavoriteEntry entry,
    SubjectLink link,
    int desiredType,
    BangumiUserCollection? remote, {
    int? epStatus,
  }) async {
    // 手动状态覆盖（绑定面板选定）优先于自动判定。
    final int? forced = link.forcedType;
    final int effectiveType = forced ?? desiredType;

    final rate = entry.myRating.clamp(0, 10);
    final comment = entry.myComment?.trim() ?? '';
    // 仅在状态推进（不降级）、手动覆盖、或评分/短评/进度/标签有变化时才推。
    final bool typeChanged = remote == null ||
        (forced != null
            ? remote.type != forced
            : _rank(effectiveType) > _rank(remote.type));
    final bool rateChanged = rate > 0 && rate != (remote?.rate ?? 0);
    final bool commentChanged =
        comment.isNotEmpty && comment != (remote?.comment ?? '');
    // 进度只增不减（远端更靠前时不回退）。
    final bool epChanged =
        epStatus != null && epStatus > (remote?.epStatus ?? 0);

    // 标签合并推送：远端 ∪ 本地分组名，仅有新增才推，不丢用户远端手动标签。
    List<String>? tagsToPush;
    if (_tagsEnabled) {
      final localTags = _localTags(entry);
      if (localTags.isNotEmpty) {
        final remoteTags = remote?.tags ?? const <String>[];
        final merged = <String>{...remoteTags, ...localTags};
        if (merged.length > remoteTags.length) tagsToPush = merged.toList();
      }
    }

    if (!typeChanged &&
        !rateChanged &&
        !commentChanged &&
        !epChanged &&
        tagsToPush == null) {
      return false;
    }

    // 不降级：远端状态更靠前时保留远端状态，仅更新其余字段。
    final int typeToPush = (remote != null &&
            forced == null &&
            _rank(remote.type) > _rank(effectiveType))
        ? remote.type
        : effectiveType;

    if (remote == null) {
      // 首次创建：全量字段 + 私有开关（仅影响新建，不改远端存量）。
      await _client.updateCollection(
        link.subjectId,
        CollectionPayload(
          type: typeToPush,
          rate: rate,
          comment: comment.isNotEmpty ? comment : null,
          epStatus: epStatus,
          tags: tagsToPush,
          private: _privateEnabled ? true : null,
        ),
      );
    } else {
      // 已收藏：PATCH 部分更新，仅携带变化字段（404 竞态时 client 回退 POST）。
      await _client.patchCollection(
        link.subjectId,
        CollectionPayload(
          type: typeChanged ? typeToPush : null,
          rate: rateChanged ? rate : 0,
          comment: commentChanged ? comment : null,
          epStatus: epChanged ? epStatus : null,
          tags: tagsToPush,
        ),
      );
    }
    return true;
  }

  /// 从 Bangumi 导入：拉取远端收藏列表，按标题相似度为本地未绑定收藏
  /// 自动建立绑定（不新建本地收藏），并顺带空缺回拉评分/短评。
  ///
  /// 未登录抛 [StateError]；返回本轮日志（success=已绑定，skipped=无匹配）。
  Future<List<SyncLogItem>> importFromBangumi() async {
    if (!_auth.isLoggedIn) {
      throw StateError('not logged in');
    }
    if (_isSyncing) return lastLog;
    _isSyncing = true;
    notifyListeners();
    final log = <SyncLogItem>[];
    try {
      // 用户名以 /v0/me 实时结果为准（旧版本地存的可能是昵称）。
      final me = await _client.fetchMe();
      // 远端收藏按 subject_type 缓存，漫画/小说共用 book 列表只拉一次。
      final remoteByType = <int, List<BangumiUserCollection>>{};
      Future<List<BangumiUserCollection>> remoteFor(int subjectType) async =>
          remoteByType[subjectType] ??= await _client.fetchUserCollections(
            me.username,
            subjectType: subjectType,
          );

      // 已占用 subject 不重复绑定到多个本地条目。
      final usedSubjects = <int>{};
      outer:
      for (final type in SourceType.values) {
        if (!typeEnabled(type)) continue;
        for (final entry in _favorites.favoritesFor(type)) {
          try {
            if (await _linkStore.get(entry.id) != null) continue;
            final candidates = <BangumiUserCollection>[
              for (final st in SubjectLinkStore.searchTypesFor(type))
                ...await remoteFor(st),
            ];
            BangumiUserCollection? best;
            double bestScore = 0;
            for (final c in candidates) {
              if (usedSubjects.contains(c.subjectId)) continue;
              final score = math.max(
                bangumiTitleSimilarity(entry.title, c.subjectName),
                bangumiTitleSimilarity(entry.title, c.subjectNameCn),
              );
              if (score > bestScore) {
                bestScore = score;
                best = c;
              }
            }
            if (best == null ||
                bestScore < SubjectLinkStore.highConfidence) {
              log.add(SyncLogItem(
                title: entry.title,
                status: SyncLogStatus.skipped,
              ));
              continue;
            }
            usedSubjects.add(best.subjectId);
            await _linkStore.put(
                entry.id, SubjectLink(subjectId: best.subjectId));
            // 列表项自带 rate/comment，顺带空缺回拉免额外请求。
            await _pullBackMeta(entry, best);
            log.add(SyncLogItem(
              title: entry.title,
              status: SyncLogStatus.success,
              detail: '#${best.subjectId}',
            ));
          } on BangumiApiException catch (e) {
            log.add(SyncLogItem(
              title: entry.title,
              status: SyncLogStatus.failed,
              detail: e.message,
            ));
            if (e.isUnauthorized) break outer;
          } on Object catch (e) {
            log.add(SyncLogItem(
              title: entry.title,
              status: SyncLogStatus.failed,
              detail: e.toString(),
            ));
          }
        }
      }
    } finally {
      _lastLog = log;
      _isSyncing = false;
      notifyListeners();
    }
    return lastLog;
  }
}
