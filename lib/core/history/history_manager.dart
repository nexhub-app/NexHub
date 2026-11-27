/// 浏览历史管理器（文档 书架历史记录 Tab）。
///
/// 三模块共用，按 [SourceType] 隔离。
/// 每模块保留最近 [maxPerModule] 条，超出自动淘汰。
/// 持久化到 [PrefsBackend]，UI 通过 [ChangeNotifier] 驱动。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../comic/models/reader_preferences.dart';
import '../models/media_item.dart';
import '../models/plugin_config.dart';
import '../scraper/http_fetcher.dart';
import '../services/config_loader.dart';
import '../storage/file_prefs_backend.dart';
import '../utils/app_log.dart';

/// 历史条目——记录最近浏览的内容。
class HistoryEntry {
  final String id;
  final String title;
  final String? coverUrl;
  final String? sourceId;
  final SourceType sourceType;
  final String? detailUrl;
  final int viewedAt;
  final String? lastChapter; // 最后阅读的章节/集标题

  /// 分类（取自 MediaItem.tags 首项），用于书架筛选。
  final String? category;

  /// 状态（连载中 / 已完结），用于书架筛选。
  final String? status;

  /// 导演（媒体/动漫专属排序用）。来自 [MediaItem.director]，空值排序回退到 [title]。
  final String? director;

  /// 主演（媒体/动漫专属排序用）。来自 [MediaItem.actors]，空值排序回退到 [title]。
  final String? actors;

  /// 封面本地缓存路径（离线可见）。写入历史时异步下载远程封面落盘，
  /// 优先于 [coverUrl] 使用；为空时回退远程 [coverUrl]。
  final String? localCoverPath;

  /// 软删除标记（历史 hidden 列）。
  ///
  /// 为 true 表示该条目被「清历史」隐藏：不出现在书架历史列表，但条目本身
  /// 与进度仍保留，用户重新进入该作品（详情/阅读器记录浏览）时自动复原为 false。
  final bool hidden;

  /// 条目来源体系：`'mediaServer'` = 媒体服务器条目
  /// （[detailUrl] 存路由凭据 `ms:<serverId>:<itemId>`）；null = 旧条目。
  final String? kind;

  /// 封面下载失败标记。启动回填/写入历史时下载封面失败（源失效、断网等）
  /// 即置位并持久化，后续启动回填不再重试——否则不可达源的封面每次启动
  /// 都会整批重发注定失败的请求。用户重新浏览该作品时条目经
  /// [HistoryEntry.fromMediaItem] 重建，标记自动复位。
  final bool coverFetchFailed;

  const HistoryEntry({
    required this.id,
    required this.title,
    required this.sourceType,
    this.coverUrl,
    this.sourceId,
    this.detailUrl,
    required this.viewedAt,
    this.lastChapter,
    this.category,
    this.status,
    this.director,
    this.actors,
    this.localCoverPath,
    this.hidden = false,
    this.kind,
    this.coverFetchFailed = false,
  });

  factory HistoryEntry.fromMediaItem(
    MediaItem item, {
    String? lastChapter,
    SourceType? sourceType,
  }) =>
      HistoryEntry(
        id: item.id,
        title: item.title,
        coverUrl: item.coverUrl,
        sourceId: item.sourceId,
        sourceType: sourceType ?? item.sourceType ?? SourceType.animeSource,
        detailUrl: item.detailUrl,
        viewedAt: DateTime.now().millisecondsSinceEpoch,
        lastChapter: lastChapter,
        category: item.tags?.isNotEmpty == true ? item.tags!.first : null,
        status: item.status,
        director: item.director,
        actors: item.actors,
      );

  MediaItem toMediaItem() => MediaItem(
        id: id,
        title: title,
        coverUrl: coverUrl,
        sourceId: sourceId,
        sourceType: sourceType,
        detailUrl: detailUrl,
        tags: category != null ? <String>[category!] : null,
        status: status,
        director: director,
        actors: actors,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'coverUrl': coverUrl,
        'sourceId': sourceId,
        'sourceType': sourceType.apiName,
        'detailUrl': detailUrl,
        'viewedAt': viewedAt,
        'lastChapter': lastChapter,
        'category': category,
        'status': status,
        'director': director,
        'actors': actors,
        'localCoverPath': localCoverPath,
        'hidden': hidden,
        if (kind != null) 'kind': kind,
        // 失败标记低频且非默认值，仅置位时落盘，避免膨胀全部条目。
        if (coverFetchFailed) 'coverFetchFailed': true,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        coverUrl: json['coverUrl'] as String?,
        sourceId: json['sourceId'] as String?,
        sourceType:
            SourceType.parse(json['sourceType'] as String?) ?? SourceType.animeSource,
        detailUrl: json['detailUrl'] as String?,
        viewedAt: json['viewedAt'] as int? ?? 0,
        lastChapter: json['lastChapter'] as String?,
        category: json['category'] as String?,
        status: json['status'] as String?,
        director: json['director'] as String?,
        actors: json['actors'] as String?,
        localCoverPath: json['localCoverPath'] as String?,
        // 旧数据无 hidden 字段时按 false（可见）解析，保证向后兼容。
        hidden: json['hidden'] as bool? ?? false,
        kind: json['kind'] as String?,
        coverFetchFailed: json['coverFetchFailed'] as bool? ?? false,
      );

  HistoryEntry copyWith({String? localCoverPath, bool? hidden, bool? coverFetchFailed, SourceType? sourceType}) => HistoryEntry(
        id: id,
        title: title,
        coverUrl: coverUrl,
        sourceId: sourceId,
        sourceType: sourceType ?? this.sourceType,
        detailUrl: detailUrl,
        viewedAt: viewedAt,
        lastChapter: lastChapter,
        category: category,
        status: status,
        director: director,
        actors: actors,
        localCoverPath: localCoverPath ?? this.localCoverPath,
        hidden: hidden ?? this.hidden,
        coverFetchFailed: coverFetchFailed ?? this.coverFetchFailed,
      );
}

/// 历史管理器——全应用单例（Provider 注入）。
class HistoryManager extends ChangeNotifier {
  HistoryManager({
    PrefsBackend? backend,
    this.maxPerModule = 50,
  }) : _backend = backend ?? FilePrefsBackend();

  final PrefsBackend _backend;
  final int maxPerModule;
  static const String _key = 'history_v1';

  final Map<SourceType, List<HistoryEntry>> _cache = {};

  /// 持久化桶：视频/音频源与影视源共用媒体桶（见 [SourceType.mediaBucket]），
  /// 保证媒体书籍架/历史能查到它们，条目不会落进无人查询的孤儿桶。
  List<HistoryEntry>? _bucket(SourceType type) => _cache[type.mediaBucket];

  /// 加载持久化数据。
  ///
  /// 外层兜底捕获：文件后端读失败（含备份回退后仍失败）会抛异常，
  /// 这里按「本次无数据」继续启动，不让启动流程崩掉。
  Future<void> init() async {
    try {
      String? raw = await _backend.get(_key);
      if (raw == null && _backend is FilePrefsBackend) {
        // 一次性迁移：旧版本历史存于 shared_preferences，其底层「轻量级
        // 偏好存储」对数百 KB 的大字符串值落盘不可靠（鸿蒙 dataPreferences
        // 失败静默），历史因此重启丢失。文件后端不存在而旧值还在时搬过来，
        // 之后以文件为准（旧键保留不动，作兜底）。
        try {
          raw = await const SharedPrefsBackend().get(_key);
          if (raw != null) {
            await _backend.set(_key, raw);
            AppLog.instance.i('[历史] 已从偏好存储迁移到独立文件（${raw.length} 字节）');
          }
        } on Object catch (e) {
          AppLog.instance.w('[历史] 迁移旧偏好存储失败: $e');
        }
      }
      if (raw != null) {
        try {
          final list = jsonDecode(raw) as List<dynamic>;
          for (final item in list) {
            final entry = HistoryEntry.fromJson(item as Map<String, dynamic>);
            _cache
                .putIfAbsent(entry.sourceType, () => <HistoryEntry>[])
                .add(entry);
          }
          AppLog.instance.i('[历史] 加载 ${list.length} 条');
        } on Object catch (e) {
          // 损坏数据忽略（后端已尽力回退备份），记录便于定位。
          AppLog.instance.w('[历史] 数据解析失败（已忽略）: $e');
        }
      }
    } on Object catch (e) {
      AppLog.instance.e('[历史] 启动加载失败，本次按无数据继续: $e');
    }
    notifyListeners();
    // 回填缺封面条目的本地缓存，确保离线可见。
    unawaited(_backfillMissingCovers());
  }

  /// 获取某模块的历史列表（按浏览时间倒序）。
  ///
  /// 过滤掉已软删除（[HistoryEntry.hidden] == true）的条目，使其不再出现在
  /// 书架/历史列表中。被隐藏的条目仍保留在内部缓存中（进度不丢），
  /// 可经 [findById] 取到；用户重新进入该作品后自动复原可见。
  List<HistoryEntry> historyFor(SourceType type) {
    final list = _bucket(type);
    if (list == null) return const <HistoryEntry>[];
    return List.unmodifiable(
      list.reversed.where((e) => !e.hidden).toList(),
    );
  }

  /// 查找指定 id 的历史条目（按内容 sourceType + id 唯一定位）。
  ///
  /// 找不到时返回 null。详情页用来取最近一次的浏览时间（[HistoryEntry.viewedAt]），
  /// 作为"上次阅读"提示的相对时间锚点。
  HistoryEntry? findById(String contentId, {SourceType? sourceType}) {
    if (sourceType != null) {
      final list = _bucket(sourceType);
      if (list == null) return null;
      for (final e in list) {
        if (e.id == contentId) return e;
      }
      return null;
    }
    for (final list in _cache.values) {
      for (final e in list) {
        if (e.id == contentId) return e;
      }
    }
    return null;
  }

  /// 添加/更新浏览记录。
  ///
  /// [sourceType] 显式指定所属模块，优先于 [MediaItem.sourceType]（后者为可空，
  /// 缺失时会错误回退到 [SourceType.animeSource]，把记录混进影视历史桶）。
  /// 各模块详情页应传入自身的固定类型，确保历史严格按模块隔离。
  Future<void> addHistory(
    MediaItem item, {
    String? lastChapter,
    SourceType? sourceType,
  }) async {
    // 无痕模式：该源已开启无痕则不记录浏览历史（进度记忆不受影响）。
    final sid = item.sourceId;
    if (sid != null &&
        sid.isNotEmpty &&
        ConfigLoader.instance.isIncognitoBySourceId(sid)) {
      return;
    }
    final type =
        (sourceType ?? item.sourceType ?? SourceType.animeSource).mediaBucket;
    final list = _cache.putIfAbsent(type, () => <HistoryEntry>[]);

    // 旧记录（去重 + 元数据继承源）：本地/下载入口重建的条目缺封面等
    // 元数据，需要从旧条目补全（见 [_mergeFromPrevious]）。
    final prevIdx = list.indexWhere((e) => e.id == item.id);
    final HistoryEntry? prev = prevIdx >= 0 ? list[prevIdx] : null;
    if (prevIdx >= 0) list.removeAt(prevIdx);

    // 添加到末尾（最新的在后面，读取时 reversed）。
    // 新条目经 fromMediaItem 构建，hidden 恒为 false——因此已软删除（被清历史）
    // 的条目在用户重新进入该作品（详情/阅读器记录浏览）时会自动复原可见
    // （重读自动复原），进度与阅读位置不受影响。
    final fresh = HistoryEntry.fromMediaItem(
      item,
      lastChapter: lastChapter,
      sourceType: type,
    );
    final entry =
        prev == null ? fresh : _mergeFromPrevious(fresh, prev);
    list.add(entry);

    // 超出上限淘汰
    while (list.length > maxPerModule) {
      list.removeAt(0);
    }

    await _persist();
    notifyListeners();
    // 离线封面缓存（best-effort，不阻塞 UI）。
    unawaited(_cacheCoverFor(entry));
  }

  /// 用旧条目补全新条目缺失的字段（仅补空，不覆盖新值）。
  ///
  /// 从本地书架/下载作品打开时，阅读器只带 id/title/sourceId，条目经
  /// fromMediaItem 重建会把旧记录的封面、详情链接等整体抹掉——典型症状：
  /// 下载作品在本地书架有封面、历史 Tab 只剩首字占位图（两边只能显示一个）。
  /// 这里对缺失字段回退旧值：
  /// - 封面：新条目无 coverUrl 时继承旧的 [HistoryEntry.coverUrl] 与
  ///   [HistoryEntry.localCoverPath]（及失败墓碑，防启动回填重试死链）；
  ///   新条目带封面（在线浏览）时走正常缓存流程，localCoverPath 置空。
  /// - 详情链接 / 分类 / 状态 / 导演 / 主演 / 最近章节：仅在新值为空时继承，
  ///   供历史 Tab 副标题、书架筛选与详情页回跳使用。
  HistoryEntry _mergeFromPrevious(HistoryEntry fresh, HistoryEntry prev) {
    final bool noCover = fresh.coverUrl == null || fresh.coverUrl!.isEmpty;
    return HistoryEntry(
      id: fresh.id,
      title: fresh.title,
      coverUrl: noCover ? (fresh.coverUrl ?? prev.coverUrl) : fresh.coverUrl,
      sourceId: (fresh.sourceId?.isNotEmpty ?? false)
          ? fresh.sourceId
          : prev.sourceId,
      sourceType: fresh.sourceType,
      detailUrl: fresh.detailUrl ?? prev.detailUrl,
      viewedAt: fresh.viewedAt,
      lastChapter: fresh.lastChapter ?? prev.lastChapter,
      category: fresh.category ?? prev.category,
      status: fresh.status ?? prev.status,
      director: fresh.director ?? prev.director,
      actors: fresh.actors ?? prev.actors,
      localCoverPath: noCover ? prev.localCoverPath : null,
      // 重读自动复原可见（与 fromMediaItem 的 hidden=false 语义一致）。
      hidden: false,
      coverFetchFailed: noCover && prev.coverFetchFailed,
    );
  }

  /// 写入预构建的历史条目（媒体服务器等外部体系用）。
  ///
  /// 去重 / 上限淘汰 / 持久化与 [addHistory] 一致；封面缓存由调用方负责
  /// （媒体服务器海报需带鉴权头下载，[HistoryEntry.localCoverPath] 预置后
  /// 不会触发通用封面下载）。
  Future<void> addEntryRaw(
    HistoryEntry entry, {
    SourceType type = SourceType.animeSource,
  }) async {
    final bucketType = type.mediaBucket;
    final list = _cache.putIfAbsent(bucketType, () => <HistoryEntry>[]);
    list.removeWhere((e) => e.id == entry.id);
    list.add(entry.sourceType == bucketType
        ? entry
        : entry.copyWith(sourceType: bucketType));
    while (list.length > maxPerModule) {
      list.removeAt(0);
    }
    await _persist();
    notifyListeners();
  }

  /// 删除 contentId 以 [prefix] 开头的历史条目（删除媒体服务器时的联动清理）。
  Future<void> removeByContentIdPrefix(String prefix) async {
    var changed = false;
    for (final type in _cache.keys.toList()) {
      final list = _cache[type]!;
      final before = list.length;
      list.removeWhere((e) => e.id.startsWith(prefix));
      if (list.length != before) changed = true;
    }
    if (changed) {
      await _persist();
      notifyListeners();
    }
  }

  /// 异步将远程封面下载到本地缓存目录 `history_covers/`，并回写
  /// [HistoryEntry.localCoverPath]（离线可见）。任何失败均静默忽略，
  /// 不影响历史功能；失败同时置 [HistoryEntry.coverFetchFailed]，
  /// 启动回填不再对同一封面反复重试。
  Future<void> _cacheCoverFor(HistoryEntry entry) async {
    final url = entry.coverUrl;
    if (url == null || url.isEmpty || !url.startsWith('http')) return;
    // 已有本地缓存且文件真实存在，跳过下载。
    if (entry.localCoverPath != null) {
      final existing = File(entry.localCoverPath!);
      if (await existing.exists()) return;
      // 文件已丢失（被清理/不存在），继续重新下载。
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final coverDir = Directory(p.join(dir.path, 'history_covers'));
      await coverDir.create(recursive: true);
      final ext = _extFromUrl(url);
      // 文件名带模块前缀命名空间：媒体源与漫画源大量使用纯数字 id，
      // 两模块不同作品撞同 id 时若共用文件名，封面会互相串图
      // （漫画历史里出现媒体海报、媒体历史里出现漫画封面）。
      final target = File(p.join(coverDir.path,
          '${entry.sourceType.apiName}_${entry.id.hashCode}_cover$ext'));
      if (await target.exists()) {
        // 已缓存：直接回写路径，避免重复下载。
        _replaceEntryInCache(entry.copyWith(localCoverPath: target.path));
        await _persist();
        notifyListeners();
        return;
      }
      final bytes = await HttpFetcher.instance.getBytes(url);
      if (bytes.isEmpty) {
        await _markCoverFetchFailed(entry);
        return;
      }
      await target.writeAsBytes(bytes);
      _replaceEntryInCache(entry.copyWith(localCoverPath: target.path));
      await _persist();
      notifyListeners();
    } on Object {
      // 封面缓存失败不影响历史功能；打标防下次启动回填重试。
      await _markCoverFetchFailed(entry);
    }
  }

  /// 封面下载失败打标（幂等）：回写缓存并持久化，启动回填据此跳过。
  Future<void> _markCoverFetchFailed(HistoryEntry entry) async {
    if (entry.coverFetchFailed) return;
    _replaceEntryInCache(entry.copyWith(coverFetchFailed: true));
    await _persist();
  }

  /// 启动时回填缺封面条目的本地缓存（离线可见）。
  ///
  /// 遍历所有已加载的历史条目，对无本地缓存（或缓存文件已丢失）的远程封面
  /// 重新下载；已缓存的有效条目跳过；[HistoryEntry.coverFetchFailed] 置位
  /// 的条目跳过（源失效等确定性失败，重试只会每次启动重发注定失败的请求）。
  /// 任何失败均静默忽略，不影响历史功能。
  Future<void> _backfillMissingCovers() async {
    // 先快照再遍历：_cacheCoverFor 回写会经 _replaceEntryInCache 对 _cache
    // 中的 List 原地赋值（list[idx] = updated）。在 await 异步间隙内直接
    // for-in 同一 List 会抛「Concurrent modification during iteration」
    // 未捕获异常并崩掉 isolate（启动时历史条目越多越易触发）。
    // 快照持有的是元素引用，遍历安全；回写只影响原 List 不影响快照。
    final snapshot = <HistoryEntry>[
      for (final list in _cache.values) ...list,
    ];
    for (final entry in snapshot) {
      if (entry.coverFetchFailed) continue;
      await _cacheCoverFor(entry);
    }
  }

  void _replaceEntryInCache(HistoryEntry updated) {
    final list = _bucket(updated.sourceType);
    if (list == null) return;
    final idx = list.indexWhere((e) => e.id == updated.id);
    if (idx >= 0) list[idx] = updated;
  }

  String _extFromUrl(String url) {
    final withoutQuery = url.split('?').first;
    final ext = p.extension(withoutQuery);
    if (ext.isEmpty) return '.jpg';
    return ext.length <= 5 ? ext : '.jpg';
  }

  /// 清除某模块的历史（软删除）。
  ///
  /// 不再物理删除条目，而是将本模块全部条目批量置 [HistoryEntry.hidden] = true：
  /// 条目从书架/历史列表消失（[historyFor] 已过滤），但进度与数据保留，
  /// 用户重新进入该作品（详情/阅读器记录浏览）时自动复原可见。
  Future<void> clearHistory(SourceType type) async {
    await hideAll(type);
  }

  /// 批量软删除某模块全部历史（等价 [clearHistory]，命名更直白）。
  ///
  /// 与 [clearAll]（物理清空）语义区分：本方法保留条目与进度，仅隐藏。
  Future<void> hideAll(SourceType type) async {
    final list = _bucket(type);
    if (list == null || list.isEmpty) return;
    for (var i = 0; i < list.length; i++) {
      list[i] = list[i].copyWith(hidden: true);
    }
    await _persist();
    notifyListeners();
  }

  /// 软删除单条历史记录（按内容 id 定位，置 [HistoryEntry.hidden] = true）。
  ///
  /// [sourceType] 显式指定所属模块时只在该模块内操作（更精确）；不传则在
  /// 所有模块中查找匹配 id 的条目。与 [removeHistory]（物理删除）区分。
  Future<void> markHidden(String contentId, {SourceType? sourceType}) async {
    var touched = false;
    if (sourceType != null) {
      touched = _hideEntryInList(_bucket(sourceType), contentId);
    } else {
      for (final list in _cache.values) {
        touched = _hideEntryInList(list, contentId) || touched;
      }
    }
    if (!touched) return;
    await _persist();
    notifyListeners();
  }

  bool _hideEntryInList(List<HistoryEntry>? list, String contentId) {
    if (list == null) return false;
    var touched = false;
    for (var i = 0; i < list.length; i++) {
      if (list[i].id == contentId && !list[i].hidden) {
        list[i] = list[i].copyWith(hidden: true);
        touched = true;
      }
    }
    return touched;
  }

  /// 复原（取消软删除）单条历史记录：置 [HistoryEntry.hidden] = false。
  ///
  /// 用户在详情/阅读器重新进入该作品时调用，使条目重新出现在书架历史列表。
  /// 注：阅读器/详情页本就会调用 [addHistory]，新增条目 hidden 恒为 false，
  /// 已覆盖"重读自动复原"；本方法供需要在不动浏览记录的情况下复原的场景使用。
  Future<void> restore(String contentId, {SourceType? sourceType}) async {
    var touched = false;
    if (sourceType != null) {
      touched = _restoreEntryInList(_bucket(sourceType), contentId);
    } else {
      for (final list in _cache.values) {
        touched = _restoreEntryInList(list, contentId) || touched;
      }
    }
    if (!touched) return;
    await _persist();
    notifyListeners();
  }

  bool _restoreEntryInList(List<HistoryEntry>? list, String contentId) {
    if (list == null) return false;
    var touched = false;
    for (var i = 0; i < list.length; i++) {
      if (list[i].id == contentId && list[i].hidden) {
        list[i] = list[i].copyWith(hidden: false);
        touched = true;
      }
    }
    return touched;
  }

  /// 删除单条历史记录（按内容 id 定位）。
  ///
  /// [sourceType] 显式指定所属模块时只在该模块内删除（更精确）；
  /// 不传则在所有模块中删除匹配 id 的记录。删除后自动持久化并通知 UI。
  Future<void> removeHistory(String contentId, {SourceType? sourceType}) async {
    if (sourceType != null) {
      _bucket(sourceType)?.removeWhere((e) => e.id == contentId);
    } else {
      for (final list in _cache.values) {
        list.removeWhere((e) => e.id == contentId);
      }
    }
    await _persist();
    notifyListeners();
  }

  /// 物理清空全部历史（保留的「物理清空」选项）。
  ///
  /// 与软删除（[clearHistory] / [hideAll]）不同：本方法直接删除所有条目，
  /// 进度与数据一并清除，不可恢复。谨慎调用。
  Future<void> clearAll() async {
    _cache.clear();
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final all = <Map<String, dynamic>>[];
    for (final list in _cache.values) {
      all.addAll(list.map((e) => e.toJson()));
    }
    await _backend.set(_key, jsonEncode(all));
  }

  /// Export all history as a JSON-serializable list.
  List<Map<String, dynamic>> exportToJson() {
    final all = <Map<String, dynamic>>[];
    for (final list in _cache.values) {
      all.addAll(list.map((e) => e.toJson()));
    }
    return all;
  }

  /// Import history from a parsed JSON list (merge, dedup by id).
  Future<void> importFromList(List<dynamic> items) async {
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      final entry = HistoryEntry.fromJson(item);
      final list =
          _cache.putIfAbsent(entry.sourceType, () => <HistoryEntry>[]);
      if (list.any((e) => e.id == entry.id)) continue;
      list.add(entry);
    }
    await _persist();
    notifyListeners();
  }
}
