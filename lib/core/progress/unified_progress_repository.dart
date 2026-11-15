/// 统一「续读 / 续看」进度抽象（详情页重构 Phase 1）。
///
/// 重构前 `ContentDetailScreen` / `ComicDetailScreen` / `NovelDetailScreen`
/// 三套详情页各自直接调用底层 Manager：
///
/// * 影视：[MediaPlaybackPositionManager]（最后播放集 + 播放位置）
/// * 漫画：[ComicProgressManager]（chapterIndex + page）
/// * 小说：[NovelProgressManager]（chapterIndex + page）
/// * 已读/已看集合：三者**共用** [MediaWatchedManager]
///
/// 三处逻辑高度重复且已出现行为发散。本文件把差异收敛到一个接口后，
/// 单一详情页只需按 [SourceType] 取对应实现，无需再区分模块。
///
/// 注意：本层只做「读」与「标记已读」，写入阅读位置仍由阅读器/播放器负责，
/// 避免与既有持久化路径产生双写。
library;

import 'package:flutter/widgets.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../comic/comic_progress_manager.dart';
import '../history/history_manager.dart';
import '../history/media_playback_position_manager.dart';
import '../history/media_watched_manager.dart';
import '../models/episode.dart';
import '../models/plugin_config.dart';
import '../novel/novel_progress_manager.dart';
import '../widgets/progress_card.dart';

/// 计算「总章节 / 总集数」。
///
/// 影视源多为多线路镜像（天堂/精品/暴风/量子 4 条线路实为同一批剧集的
/// 不同播放地址），解析器按线路分组后 [episodes] 会包含每条线路的完整副本，
/// 直接取 `length` 会叠加（4×30=120）。因此按 [Episode.lineName] 分组，
/// 取**最大一组**的数量作为总数；漫画/小说无 lineName，退化为列表长度。
int computeTotalEpisodes(List<Episode> episodes) {
  if (episodes.isEmpty) return 0;
  final counts = <String, int>{};
  for (final e in episodes) {
    final key = e.lineName ?? '';
    counts[key] = (counts[key] ?? 0) + 1;
  }
  var max = 0;
  for (final c in counts.values) {
    if (c > max) max = c;
  }
  return max;
}

/// 详情页续读/续看进度仓库。
///
/// 实现按 [SourceType] 分发，见 [UnifiedProgressRepository.of]。
abstract class UnifiedProgressRepository {
  const UnifiedProgressRepository(this._watched);

  /// 已读/已看集合管理器（三种类型共用）。可为 null（Provider 未注册时降级）。
  final MediaWatchedManager? _watched;

  /// 进度卡文案类型（「阅读」还是「观看」）。
  ProgressKind get kind;

  /// 续读/续看索引；无记录返回 -1。
  Future<int> loadContinueIndex(String contentId);

  /// 已读/已看数量。
  int readCount(String contentId) => _watched?.watchedCount(contentId) ?? 0;

  /// 已读/已看索引升序列表。
  List<int> readIndices(String contentId) =>
      _watched?.watchedList(contentId) ?? const <int>[];

  /// 指定索引是否已读/已看。
  bool isRead(String contentId, int index) =>
      _watched?.isWatched(contentId, index) ?? false;

  /// 切换指定索引的已读/已看状态。
  Future<void> toggleRead(String contentId, int index) async {
    await _watched?.toggleWatched(contentId, index);
  }

  /// 幂等标记已读/已看（不会取消）。
  ///
  /// 用于「打开即标记」场景（重构前影视详情页进入播放器时的行为），
  /// 与 [toggleRead] 区分：重复进入同一集不应把它翻回未看。
  Future<void> markRead(String contentId, int index) async {
    await _watched?.markWatched(contentId, index);
  }

  /// 指定集的播放位置（毫秒）。仅影视有意义，其余恒为 0。
  int positionMs(String contentId, int index) => 0;

  /// 按源类型构造对应实现。
  ///
  /// Provider 查找做了容错：某个 Manager 未注册时退化为「无进度」，
  /// 不会让详情页整页崩溃（与重构前 try/catch 行为一致）。
  ///
  /// 注意 [ComicProgressManager] / [NovelProgressManager] **未注册到
  /// Provider**（重构前由各详情页 `State` 直接 `new`，它们是无状态的
  /// SharedPreferences 薄封装）。这里保持同样语义：优先取 Provider，
  /// 取不到就本地实例化，绝不返回 null，否则续读索引会永远是 -1。
  ///
  /// 本方法应在 `State` 中缓存调用结果，不要放进 `build` 反复构造。
  static UnifiedProgressRepository of(BuildContext context, SourceType type) {
    final watched = _tryRead<MediaWatchedManager>(context);
    return switch (type) {
      SourceType.mangaSource => ComicProgressRepository(
          watched,
          _tryRead<ComicProgressManager>(context) ?? ComicProgressManager(),
        ),
      SourceType.novelSource => NovelProgressRepository(
          watched,
          _tryRead<NovelProgressManager>(context) ?? NovelProgressManager(),
        ),
      SourceType.animeSource ||
      SourceType.videoSource ||
      SourceType.audioSource =>
        MediaProgressRepository(
          watched,
          _tryRead<MediaPlaybackPositionManager>(context),
        ),
    };
  }
}

/// 影视：最后播放集优先，其次「最后已看集 + 1」。
class MediaProgressRepository extends UnifiedProgressRepository {
  const MediaProgressRepository(super.watched, this._position);

  final MediaPlaybackPositionManager? _position;

  @override
  ProgressKind get kind => ProgressKind.watching;

  @override
  Future<int> loadContinueIndex(String contentId) async {
    // 优先播放位置管理器记录的最后播放集。
    final lastEp = _position?.getLastEpisode(contentId) ?? -1;
    if (lastEp >= 0) return lastEp;
    // 退化：最后已看集 + 1（越界由调用方裁剪）。
    final list = readIndices(contentId);
    if (list.isNotEmpty) return list.last + 1;
    return -1;
  }

  @override
  int positionMs(String contentId, int index) =>
      _position?.getPosition(contentId, index) ?? 0;
}

/// 漫画：直接取 [ComicProgressManager] 的 chapterIndex。
class ComicProgressRepository extends UnifiedProgressRepository {
  const ComicProgressRepository(super.watched, this._progress);

  final ComicProgressManager? _progress;

  @override
  ProgressKind get kind => ProgressKind.reading;

  @override
  Future<int> loadContinueIndex(String contentId) async {
    final mgr = _progress;
    if (mgr == null) return -1;
    try {
      final p = await mgr.get(contentId);
      return p?.chapterIndex ?? -1;
    } on Object {
      return -1;
    }
  }
}

/// 小说：直接取 [NovelProgressManager] 的 chapterIndex。
class NovelProgressRepository extends UnifiedProgressRepository {
  const NovelProgressRepository(super.watched, this._progress);

  final NovelProgressManager? _progress;

  @override
  ProgressKind get kind => ProgressKind.reading;

  @override
  Future<int> loadContinueIndex(String contentId) async {
    final mgr = _progress;
    if (mgr == null) return -1;
    try {
      final p = await mgr.get(contentId);
      return p?.chapterIndex ?? -1;
    } on Object {
      return -1;
    }
  }
}

/// 组装进度卡「上次阅读/观看」提示。
///
/// 收敛自三套详情页里逐字重复的 `_buildProgressCard` 前半段：
/// 章节标题优先取续读索引，其次取已读集合最后一项；时间取
/// [HistoryManager] 里该内容的 `viewedAt`。任一环节缺失即返回 null
/// （进度卡自动隐藏该行）。
ProgressLastRead? resolveLastRead({
  required BuildContext context,
  required AppLocalizations l10n,
  required String contentId,
  required SourceType sourceType,
  required List<Episode> chapters,
  required int continueIndex,
  required int readCount,
  required UnifiedProgressRepository progress,
}) {
  String? title;
  if (continueIndex >= 0 && continueIndex < chapters.length) {
    title = chapters[continueIndex].title;
  } else if (readCount > 0) {
    final read = progress.readIndices(contentId);
    if (read.isNotEmpty && read.last < chapters.length) {
      title = chapters[read.last].title;
    }
  }
  if (title == null || title.isEmpty) return null;

  final history = _tryRead<HistoryManager>(context);
  if (history == null) return null;
  final entry = history.findById(contentId, sourceType: sourceType);
  if (entry == null || entry.viewedAt <= 0) return null;

  return ProgressLastRead(
    timeText: formatRelativeTime(
      l10n,
      DateTime.fromMillisecondsSinceEpoch(entry.viewedAt),
    ),
    chapterTitle: title,
  );
}

/// Provider 容错读取：未注册时返回 null 而非抛异常。
T? _tryRead<T extends Object>(BuildContext context) {
  try {
    return context.read<T>();
  } on Object {
    return null;
  }
}
