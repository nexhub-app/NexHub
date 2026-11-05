/// 下载管理器（文档 /）。
///
/// 核心职责：
/// 1. 管理任务生命周期（addTask / cancel / pause / resume）。
/// 2. 持久化任务列表到 [DownloadStorage]。
/// 3. 每个任务写入 `.meta.json` 到下载目录，用于孤儿恢复。
/// 4. 清除记录精确规则：
/// - `clearAll(false)` → 仅移除未完成任务（逐个 cancel 中止在途下载），
/// 已完成任务保留，已下载内容页立即可读。
/// - `clearAll(true)` → 删文件 + meta.json，所有记录清除。
/// 5. 下载列表页过滤 completed 只显活跃；已下载内容页只显 completed。
///
/// 使用 [ChangeNotifier] 驱动 UI 更新。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../models/episode.dart';
import '../models/media_item.dart';
import '../models/plugin_config.dart';
import '../scraper/http_fetcher.dart';
import '../scraper/media_api_service.dart';
import '../services/source_repository.dart';
import '../services/cloud_sync_service.dart';
import '../services/novel_export_upload_service.dart';
import '../utils/app_log.dart';
import '../platform/platform_service.dart';
import '../platform/background_task.dart';
import '../local/saf_bridge.dart' show normalizeSafTreeUri;
import '../platform/ohos_public_storage.dart'
    show OhosPublicStorage, isOhosDocPath;
import '../novel/novel_chinese_converter.dart';
import '../novel/novel_reader_preferences.dart';
import 'comic_download_handler.dart';
import 'download_file_system.dart';
import 'download_format_preferences.dart';
import 'download_handler.dart';
import 'download_settings.dart';
import 'saf_download_file_system.dart';
import 'ohos_doc_file_system.dart';
import 'download_storage.dart';
import 'download_task.dart';
import 'media_download_handler.dart';
import 'novel_download_handler.dart';

/// 等待队列中的下载项（因达到最大并发而暂存）。
class _QueuedDownload {
  final DownloadTask task;
  final MediaItem item;
  final List<Episode> chapters;

  _QueuedDownload(this.task, this.item, this.chapters);
}

/// 已下载作品分组（同一部书 / 漫画 / 剧集的多次分批下载合并为一）。
///
/// 由 [DownloadManager.groupedDownloaded] / [groupedArchived] 产出，
/// 供「已下载」页与书架「本地」段按作品展示单卡片，避免重复条目。
///
/// 封面 / 标题取各批次中最新值；章节标题为各批次并集（保持插入顺序、去重）；
/// 总章节数为各批次之和；`batches` 保留逐批明细供详情页展开。
class DownloadGroup {
  const DownloadGroup({
    required this.contentId,
    required this.sourceId,
    required this.title,
    required this.coverUrl,
    required this.sourceType,
    required this.format,
    required this.totalChapters,
    required this.batches,
    this.completedAt,
  });

  /// 内容 ID（MediaItem.id）。
  final String contentId;

  /// 源 ID；null 表示本地导入 / 无源。
  final String? sourceId;

  /// 展示标题（取最新批次标题）。
  final String title;

  /// 封面（优先各批次本地封面；均无则回退远程封面 URL）。
  final String? coverUrl;

  /// 源类型（决定默认阅读器分流）。
  final SourceType sourceType;

  /// 下载格式（取最新批次；同一作品分批格式一致）。
  final DownloadFormat format;

  /// 各批次章节总数之和。
  final int totalChapters;

  /// 合并完成时间（取最新批次）。
  final int? completedAt;

  /// 逐批下载任务明细（按创建时间升序）。
  final List<DownloadTask> batches;

  /// 各批次章节标题的并集（去重、保持顺序）。
  List<String> get chapterTitles {
    final List<String> all = <String>[];
    final Set<String> seen = <String>{};
    for (final DownloadTask t in batches) {
      for (final String c in t.chapterTitles) {
        if (seen.add(c)) all.add(c);
      }
    }
    return all;
  }

  /// 以单条任务为首项，构造分组。
  factory DownloadGroup.fromLeadTask(DownloadTask lead) => DownloadGroup(
        contentId: lead.contentId,
        sourceId: lead.sourceId,
        title: lead.title,
        coverUrl: lead.localCoverPath ?? lead.coverUrl,
        sourceType: lead.sourceType,
        format: lead.format,
        totalChapters: lead.totalChapters,
        completedAt: lead.completedAt,
        batches: <DownloadTask>[lead],
      );

  /// 加入一个同作品批次，返回更新后的分组（标题 / 封面 / 总数取最新或求和）。
  DownloadGroup addTask(DownloadTask t) {
    final List<DownloadTask> next = List<DownloadTask>.from(batches)
      ..add(t);
    // 最新创建时间对应的批次优先作为展示来源。
    final DownloadTask newest = next.reduce(
      (a, b) => a.createdAt >= b.createdAt ? a : b,
    );
    return DownloadGroup(
      contentId: contentId,
      sourceId: sourceId,
      title: newest.title,
      coverUrl: newest.localCoverPath ?? newest.coverUrl ?? coverUrl,
      sourceType: sourceType,
      format: newest.format,
      totalChapters: next.fold(0, (s, e) => s + e.totalChapters),
      completedAt: newest.completedAt,
      batches: next,
    );
  }
}

/// 下载管理器——全应用单例（Provider 注入）。
class DownloadManager extends ChangeNotifier {
  DownloadManager({
    required this.storage,
    required this.fs,
    required this.service,
    required this.sourceRepo,
    DownloadFormatPreferences? formatPrefs,
    DownloadSettings? settings,
  })  : _formatPrefs = formatPrefs ?? const DownloadFormatPreferences.defaults(),
        _settings = settings ?? const DownloadSettings.defaults();

  final DownloadStorage storage;
  DownloadFileSystem fs;
  final MediaApiService service;
  final SourceRepository sourceRepo;
  DownloadFormatPreferences _formatPrefs;

  DownloadFormatPreferences get formatPrefs => _formatPrefs;

  /// 下载设置（最大并发 / 线程数 / 路径 / 下载器类型），来自 [DownloadSettingsStore]。
  DownloadSettings _settings;

  /// 当前生效的下载设置。
  DownloadSettings get settings => _settings;

  /// 是否需要引导用户选择公开下载目录。
  ///
  /// 仅 Android：若下载路径未设置（含旧版 `D:/Downloads`，在 Android 上会被
  /// 回退为应用私有外部存储 `Android/data/<pkg>/files/Download`），普通文件
  /// 管理器看不到下载内容。此时应引导用户用 SAF 选一个公开文件夹，使下载
  /// 对文件管理器可见。用户一旦主动设置过（路径变为 `content://` 或真实
  /// 路径）即不再触发。
  bool get needsPublicDownloadDir =>
      PlatformService.instance.isAndroid &&
      isUnsetDownloadPath(_settings.downloadPath);

  /// 正在执行中的下载数量（受 maxConcurrent 约束）。
  int _running = 0;

  /// 因达到最大并发而等待的下载队列。
  final List<_QueuedDownload> _pending = <_QueuedDownload>[];

  /// 因未连接 WiFi 而挂起的下载队列（仅 WiFi 模式下使用）。
  final List<_QueuedDownload> _waitingForWifi = <_QueuedDownload>[];

  /// 暂停令牌：记录用户在下载过程中点击暂停的任务 ID。
  /// [_executeDownload] 完成时会检查此集合，若任务被暂停则保持 paused 状态。
  final Map<String, bool> _pauseTokens = <String, bool>{};

  /// 取消令牌：记录用户点击取消的**进行中**任务 ID。
  ///
  /// `cancel()` 只移除记录，无法终止在途的网络/写盘 Future；处理器通过
  /// [DownloadCancelledCheck] 在每章/每集开始前检查此集合，命中即抛
  /// [DownloadCancelledException] 中止，随后 [_executeDownload] 清理半成品
  /// 且不写 meta.json（修复 132：取消后不再继续下载、重启后不再复活）。
  final Set<String> _cancelledTaskIds = <String>{};

  /// 网络变化订阅（仅 WiFi 模式下监听，用于恢复挂起任务）。
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  /// 内存任务列表。
  final List<DownloadTask> _tasks = [];

  /// 全部任务（只读视图）。
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  /// 直接注入一条已构造的下载任务（不触发下载调度）。
  /// 用于内部从存储恢复，以及单元测试构造聚合场景；正式下载请走 [addTask]。
  void injectTask(DownloadTask task) {
    _tasks.add(task);
    notifyListeners();
  }

  /// 活跃任务（下载列表页使用，排除 completed）。
  List<DownloadTask> get activeTasks =>
      _tasks.where((t) => t.isActive).toList();

  /// 已完成任务（已下载内容页使用，排除已归档）。
  List<DownloadTask> get completedTasks =>
      _tasks.where((t) => t.isCompleted && !t.archived).toList();

  /// 已归档任务（归档 Tab 使用）。
  List<DownloadTask> get archivedTasks =>
      _tasks.where((t) => t.archived).toList();

  /// 作品合并键：同「源 + 内容」视为同一部作品，用于把多次分批下载合并展示。
  ///
  /// 与 [DownloadTask.coverKey] 同源设计，但允许 sourceId 为空时按 contentId 兜底，
  /// 保证「不同源但 contentId 恰好相同」不会误并（各自带 sourceId 时键不同）。
  static String groupKeyFor(DownloadTask t) => '${t.sourceId ?? ''}|${t.contentId}';

  /// 将已完成（未归档）任务按作品合并为一组，供「已下载」页卡片展示。
  ///
  /// 同一部作品（同源同 contentId）跨多次分批下载只显示一张卡片，
  /// 封面 / 标题取最新值，章节数为各批次并集，总章节数为各批次之和。
  List<DownloadGroup> groupedDownloaded() => _groupTasks(
        _tasks.where((t) => t.isCompleted && !t.archived).toList(),
      );

  /// 将已归档任务按作品合并为一组，供「已删除下载」页卡片展示。
  List<DownloadGroup> groupedArchived() =>
      _groupTasks(_tasks.where((t) => t.archived).toList());

  /// 内部：按 [groupKeyFor] 聚合任务为 [DownloadGroup]，保持稳定顺序。
  List<DownloadGroup> _groupTasks(List<DownloadTask> tasks) {
    final List<DownloadGroup> groups = <DownloadGroup>[];
    final Map<String, int> keyToIndex = <String, int>{};
    for (final DownloadTask t in tasks) {
      final String key = groupKeyFor(t);
      final int idx = keyToIndex[key] ?? -1;
      if (idx < 0) {
        groups.add(DownloadGroup.fromLeadTask(t));
        keyToIndex[key] = groups.length - 1;
      } else {
        groups[idx] = groups[idx].addTask(t);
      }
    }
    return groups;
  }

  /// 取某作品（同源同 contentId）的全部批次任务，供分组详情页逐批展示。
  ///
  /// [includeArchived] 为 false 时仅返回未归档批次（「已下载」页进入）；
  /// 为 true 时含已归档批次（「已删除下载」页进入）。
  List<DownloadTask> tasksForContent(
    String contentId,
    String? sourceId, {
    bool includeArchived = false,
  }) {
    final List<DownloadTask> result = _tasks.where((t) {
      if (t.contentId != contentId) return false;
      if (t.sourceId != sourceId) return false;
      if (t.archived) return includeArchived;
      return true;
    }).toList();
    result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return result;
  }

  /// 归档某作品的全部批次（「读后自动删除」/ 选择批量归档用）。
  ///
  /// 仅影响 status==completed 的批次；其余状态（下载中/失败）不动。
  Future<void> archiveContent(String contentId) async {
    var changed = false;
    for (var i = 0; i < _tasks.length; i++) {
      final t = _tasks[i];
      if (t.contentId != contentId || t.status != DownloadStatus.completed) {
        continue;
      }
      _tasks[i] = t.copyWith(
        archived: true,
        archivedAt: DateTime.now().millisecondsSinceEpoch,
      );
      changed = true;
    }
    if (changed) {
      await _persist();
      notifyListeners();
    }
  }

  /// 删除某作品的全部批次（含文件 + meta.json + 共享封面）。
  ///
  /// [deleteFiles] 为 true 才删磁盘文件；false 仅删记录（可被恢复）。
  /// 共享封面在所有被删批次均无引用时才清除（见 [_deleteTaskFiles]）。
  Future<void> cancelContent(String contentId, {bool deleteFiles = true}) async {
    final ids = _tasks
        .where((t) => t.contentId == contentId)
        .map((t) => t.id)
        .toList();
    for (final id in ids) {
      await cancel(id, deleteFiles: deleteFiles);
    }
  }

  /// 恢复某作品的全部已归档批次（归档页「恢复」用）。
  Future<void> unarchiveContent(String contentId) async {
    var changed = false;
    for (var i = 0; i < _tasks.length; i++) {
      final t = _tasks[i];
      if (t.contentId != contentId || !t.archived) continue;
      _tasks[i] = t.copyWith(
        archived: false,
        archivedAt: null,
        status: DownloadStatus.completed,
      );
      changed = true;
    }
    if (changed) {
      await _persist();
      notifyListeners();
    }
  }

  /// 该内容是否存在任何已完成的下载任务。
  ///
  /// 注意：这是「整部内容层面」的粗粒度判断，**不能**用来禁用下载入口——
  /// 用户下过其中几集后它就恒为 true，会导致剩余集永远无法下载。
  /// 判断「是否还有可下载的章节」请用 [downloadedChapterTitles] 逐章比对。
  bool isItemDownloaded(String contentId) =>
      _tasks.any((t) => t.contentId == contentId && t.isCompleted);

  /// 指定内容中已下载完成的章节标题集合（跨多个任务合并）。
  ///
  /// - `completed` 任务：其 [DownloadTask.chapterTitles] 全部计入；
  /// - 进行中 / 暂停任务：按 [DownloadTask.downloadedChapters] 计入已完成的前 N 个
  /// （handler 按选中顺序串行下载）；
  /// - `cancelled` 任务不计入。
  ///
  /// 归档（archived）任务的文件仍在磁盘上，因此同样计入。
  Set<String> downloadedChapterTitles(String contentId) {
    final Set<String> titles = <String>{};
    for (final DownloadTask t in _tasks) {
      if (t.contentId != contentId) continue;
      if (t.status == DownloadStatus.cancelled) continue;
      if (t.isCompleted) {
        titles.addAll(t.chapterTitles);
      } else if (t.downloadedChapters > 0) {
        titles.addAll(t.chapterTitles.take(t.downloadedChapters));
      }
    }
    return titles;
  }

  /// 指定内容中已排入下载队列（含进行中 / 等待中）但尚未完成的章节标题集合。
  ///
  /// 用于选择弹窗避免重复排队同一章。
  Set<String> queuedChapterTitles(String contentId) {
    final Set<String> titles = <String>{};
    for (final DownloadTask t in _tasks) {
      if (t.contentId != contentId || !t.isActive) continue;
      titles.addAll(t.chapterTitles.skip(t.downloadedChapters));
    }
    return titles;
  }

  /// 初始化：从存储加载 + 恢复孤立记录。
  Future<void> init() async {
    _tasks.clear();
    _tasks.addAll(await storage.loadAll());
    _migrateLegacyCancelledToArchived();
    // 孤立记录恢复是「尽力而为」：下载目录可能压根访问不到（外来平台路径 /
    // 原生通道缺失 / 授权被收回）。异常若冒到 splash 初始化，整个应用就只剩
    // 「加载失败」页——导入其他平台备份后的典型表现。这里吞掉并记录日志，
    // 目录恢复可用后下次启动会再扫一遍。
    try {
      await recoverOrphanedDownloads();
      await _recoverLegacyOrphanedFolders();
    } on Object catch (e) {
      AppLog.instance.w('[下载] 启动恢复下载记录失败（已跳过）: $e');
    }
    await _loadSettings();
    _registerConnectivityListener();
    notifyListeners();
  }

  /// 注册网络变化监听：仅 WiFi 模式下，WiFi 恢复后自动重启挂起任务。
  void _registerConnectivityListener() {
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        if (results.contains(ConnectivityResult.wifi)) {
          _resumeWaitingForWifi();
        }
      },
    );
  }

  /// 将因无 WiFi 挂起的任务移回等待队列并重新调度。
  void _resumeWaitingForWifi() {
    if (_waitingForWifi.isEmpty) return;
    _pending.addAll(_waitingForWifi);
    _waitingForWifi.clear();
    _pumpQueue();
  }

  /// 当前是否连接 WiFi。
  Future<bool> _isWifiConnected() async {
    final List<ConnectivityResult> results =
        await Connectivity().checkConnectivity();
    return results.contains(ConnectivityResult.wifi);
  }

  /// 重新加载下载设置（设置页切换「仅 WiFi」后调用，使改动立即生效）。
  ///
  /// 若关闭仅 WiFi，立即重启此前因无 WiFi 挂起的任务。
  Future<void> reloadSettings() async {
    await _loadSettings();
    if (!_settings.wifiOnly && _waitingForWifi.isNotEmpty) {
      _resumeWaitingForWifi();
    }
  }

  /// 更新下载路径并立即生效（无需重启）。
  ///
  /// 持久化到 [DownloadSettingsStore]，并按路径形态重建文件系统根：
  /// - `content://` 树 URI（Android SAF 用户目录）→ 用 [SafFileSystem] 写入，
  /// 使下载真正落到用户指定的系统文件夹（修复 107/108）；
  /// - `ohosdoc://`（鸿蒙公共 Download 目录）→ 用 [OhosDocFileSystem] 经原生
  /// 通道写入（dart:io 无法直接读写该目录）；
  /// - 普通文件路径 → 用 [PathProviderFileSystem] 重建根路径。
  Future<void> setDownloadBasePath(String path) async {
    // pickDirectory 返回规范化 `tree/<id>/document/<id>`（4 段），saf 包的
    // stat/child 对纯 tree（2 段）最稳；统一归一化后持久化，全链路一致。
    final String normalized = path.startsWith('content://')
        ? normalizeSafTreeUri(path)
        : path;
    _settings = _settings.copyWith(downloadPath: normalized);
    await DownloadSettingsStore().save(_settings);
    if (normalized.startsWith('content://')) {
      fs = SafFileSystem(normalized);
    } else if (isOhosDocPath(normalized)) {
      fs = OhosDocFileSystem(normalized);
    } else if (fs is PathProviderFileSystem || fs is OhosDocFileSystem) {
      fs = PathProviderFileSystem(normalized);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
    super.dispose();
  }

  /// 向后兼容：将旧的 status==cancelled 且保留 localPath 的任务迁移为 archived=true。
  ///
  /// 旧版本"仅删记录"会把 completed 任务标记为 cancelled 但保留 localPath，
  /// 新版本语义改为 archived=true + status=completed。
  void _migrateLegacyCancelledToArchived() {
    bool changed = false;
    for (var i = 0; i < _tasks.length; i++) {
      final t = _tasks[i];
      if (t.status == DownloadStatus.cancelled && t.localPath != null) {
        _tasks[i] = t.copyWith(
          status: DownloadStatus.completed,
          archived: true,
          archivedAt: t.completedAt ??
              DateTime.now().millisecondsSinceEpoch,
        );
        changed = true;
      }
    }
    // 持久化由 init() 后续 _persist 调用保证；此处仅修改内存。
    if (changed) {
      // ignore: unawaited_futures
      _persist();
    }
  }

  /// 添加下载任务并启动下载。
  ///
  /// [item] 内容项；[chapters] 章节列表；[chapterIndices] 要下载的章节索引
  /// （null = 全部）。
  Future<DownloadTask> addTask({
    required MediaItem item,
    required List<Episode> chapters,
    List<int>? chapterIndices,
  }) async {
    // 以「源的真实 type」为准派发下载处理器，避免漫画/小说从影视入口进入时
    // item.sourceType 缺失或被错配成 anime，导致被当成视频去嗅探
    // （route not found → 全部下载失败）。sourceId 能查到源时强制采用源的 type；
    // 查不到（如本地导入）才回退到 item.sourceType 或 animeSource。
    final SourceType sourceType = (item.sourceId != null
            ? sourceRepo.getById(item.sourceId!)?.type
            : null) ??
        item.sourceType ??
        SourceType.animeSource;
    final format = _resolveFormat(sourceType);
    // 规范化章节序号：下载文件名用「全局序号」（整本连续、跨批次稳定）命名，
    // 保证分批「单独下载」时各批不会用本地 1..N 互相覆盖（否则第二次下载会
    // 覆盖第一次的文件 → 只能打开一章/一集、内容在管理器里对不上）。
    // number 为 null 的源在此统一补全局序号。
    final selectedChapters = chapterIndices == null
        ? <Episode>[
            for (var i = 0; i < chapters.length; i++)
              chapters[i].copyWith(number: i + 1),
          ]
        : <Episode>[
            for (final gi in chapterIndices)
              chapters[gi].copyWith(number: gi + 1),
          ];

    final now = DateTime.now().millisecondsSinceEpoch;
    // task.id 会用作下载文件名（`${task.id}.cbz/.epub/.jpg`）。item.id 对部分源
    // 是完整 URL（含 `/`、`:`），直接拼进来会被 SAF 路径拆成多级目录，导致
    // 写入/读取路径错乱（下载后打不开）。统一清洗为文件名安全字符。
    // coverKey：同「源 + 内容」的作品共用一张封面（${coverKey}.jpg），
    // 后续批次下载时直接复用，避免重复拉取网络封面（见 [DownloadManager._saveCoverImage]）。
    final coverKey = _computeCoverKey(item);
    // 稳定作品目录：同「源 + 内容」的作品落到同一目录（每部作品一个目录），
    // 多批下载各话/集独立落盘，便于管理与阅读器按序打开。目录层级为
    // `<根>/<类型>/<作品名>`（类型=小说/漫画/媒体，作品名取清洗后的标题），
    // 让用户在文件管理器能直接识别。文件名安全化避免标题含 `/`、`:` 等被
    // 拆成多级目录（见 [_safeTitle] / [_typeDirName]）。
    final String typeDir = _typeDirName(sourceType);
    final String safeTitle = _safeTitle(item.title, item.id);
    final String workDir = fs.join(fs.join(fs.basePath, typeDir), safeTitle);
    final task = DownloadTask(
      id: '${item.sourceId ?? 'local'}_${_safeTaskId(item.id)}_$now',
      title: item.title,
      coverUrl: item.coverUrl,
      sourceType: sourceType,
      sourceId: item.sourceId,
      contentId: item.id,
      format: format,
      chapterTitles: selectedChapters.map((c) => c.title).toList(),
      chapterIds: selectedChapters.map((c) => c.id).toList(),
      totalChapters: selectedChapters.length,
      downloadedChapters: 0,
      status: DownloadStatus.pending,
      createdAt: now,
      coverKey: coverKey,
      // localPath 约定为"作品目录"，供各 handler 在其下按章/集落盘。
      localPath: workDir,
    );

    // 诊断日志：任务创建即输出关键信息（源/格式/落盘目录/章节数），
    // 便于排查「下载列表无内容 / 详情页显示已下载但文件未落盘」类问题。
    AppLog.instance.i('[下载任务创建] ${item.title} (${task.id}, '
        '${selectedChapters.length} 章, 源 ${sourceType.name}, '
        '格式 ${format.label}, 目录 $workDir)');

    _tasks.add(task);
    await _persist();
    await _writeMetaJson(task);
    notifyListeners();

    // 按下载设置调度（受最大同时下载数限制）
    await _loadSettings();
    _scheduleDownload(task, item, selectedChapters);

    return task;
  }

  /// 取消下载。
  ///
  /// [deleteFiles] = true 同时删除磁盘文件 + meta.json；
  /// false 仅从存储移除，保留 meta.json（可恢复）。
  Future<void> cancel(String taskId, {bool deleteFiles = false}) async {
    // 记录是否仍排在等待队列（尚未真正开始执行）——仅排队任务无需取消令牌。
    final bool wasQueued = _pending.any((q) => q.task.id == taskId) ||
        _waitingForWifi.any((q) => q.task.id == taskId);
    // 同时从等待队列移除（若尚未开始执行）
    _pending.removeWhere((q) => q.task.id == taskId);
    _waitingForWifi.removeWhere((q) => q.task.id == taskId);

    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx < 0) return;

    final task = _tasks[idx];
    // 记录取消令牌：在途下载（handler 正在跑）会据此在下一章/集中止，
    // 否则取消后网络与写盘仍在继续（修复 132）。
    // 仅排队/未开始的任务无需令牌（从队列移除即不会再启动）。
    if (!wasQueued &&
        (task.isActive || task.status == DownloadStatus.downloading)) {
      _cancelledTaskIds.add(taskId);
    }
    _tasks[idx] = task.copyWith(status: DownloadStatus.cancelled);

    if (deleteFiles) {
      await _deleteTaskFiles(task);
    }

    // 从活跃列表移除（保留 completed 供历史查看）
    if (!task.isCompleted) {
      _tasks.removeAt(idx);
    }
    await _persist();
    notifyListeners();
  }

  /// 删除一条已完成下载任务（书架「本地」长按菜单用）。
  ///
  /// [deleteFiles] = true 同时删除磁盘文件 + meta.json；false 仅删记录
  /// （下次 [recoverOrphanedDownloads] 可能从 meta.json 恢复）。
  Future<void> removeCompleted(String taskId, {bool deleteFiles = false}) async {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx < 0) return;
    final task = _tasks[idx];
    if (deleteFiles) {
      await _deleteTaskFiles(task);
    }
    _tasks.removeAt(idx);
    await _persist();
    notifyListeners();
  }

  /// 删除某内容（contentId）的全部已完成下载任务（「读后自动删除」用）。
  ///
  /// [deleteFiles] = true 同时删除磁盘文件 + meta.json。
  /// 仅删除 completed 任务；进行中 / 已归档任务不动。
  Future<void> removeItemDownloads(
    String contentId, {
    bool deleteFiles = true,
  }) async {
    final ids = _tasks
        .where((t) => t.contentId == contentId && t.isCompleted)
        .map((t) => t.id)
        .toList();
    for (final id in ids) {
      await removeCompleted(id, deleteFiles: deleteFiles);
    }
  }

  /// 预下载「当前剧集之后」连续的 [count] 个章节位置（「预下载后续剧集」用）。
  ///
  /// 从 [fromIndex] 下一集开始，取连续的 [count] 个章节位置：
  /// 已下载 / 已在队列的跳过不下载，但不向后延伸（即实际下载数 ≤ count）。
  /// 受 [DownloadSettings.maxConcurrent] 队列限制，不会打断已有下载。
  Future<int> preDownloadNextEpisodes({
    required MediaItem item,
    required List<Episode> chapters,
    required int fromIndex,
    required int count,
  }) async {
    if (count <= 0 || chapters.isEmpty) return 0;
    final downloaded = downloadedChapterTitles(item.id);
    final queued = queuedChapterTitles(item.id);
    final indices = <int>[];
    // 从 fromIndex+1 开始取连续 count 个位置，已下载/已排队的跳过但不延伸。
    final end = (fromIndex + 1 + count).clamp(0, chapters.length);
    for (var i = fromIndex + 1; i < end; i++) {
      final title = chapters[i].title;
      if (downloaded.contains(title) || queued.contains(title)) continue;
      indices.add(i);
    }
    if (indices.isEmpty) return 0;
    // 逐段添加：addTask 内部按 maxConcurrent 调度，不会全部立刻并发。
    for (final i in indices) {
      await addTask(item: item, chapters: chapters, chapterIndices: <int>[i]);
    }
    return indices.length;
  }

  /// 重命名已完成下载任务的显示标题（仅改记录中的 title，不动磁盘文件）。
  Future<void> renameCompleted(String taskId, String newTitle) async {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx < 0) return;
    _tasks[idx] = _tasks[idx].copyWith(title: newTitle);
    await _persist();
    notifyListeners();
  }

  /// 暂停下载（旧入口，保留以兼容既有调用）。
  Future<void> pause(String taskId) async {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx < 0) return;
    _tasks[idx] = _tasks[idx].copyWith(status: DownloadStatus.paused);
    await _persist();
    notifyListeners();
  }

  /// 暂停下载任务（项 5）。
  ///
  /// MVP 语义：取消当前下载但保留已下载分片/文件，标记为 `paused`。
  /// 仅对 status == downloading 的任务生效，其他状态不做任何操作。
  ///
  /// 引擎无原生取消能力时，下载 Future 仍会在后台跑完；当其完成时，
  /// [_executeDownload] 会检查 [_pauseTokens] 并保持 `paused` 状态（保留产物文件），
  /// 用户随后可通过 [resumeTask] 将其标记为 completed（若文件已落盘）或重新下载。
  Future<void> pauseTask(String taskId) async {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx < 0) return;
    final task = _tasks[idx];
    if (task.status != DownloadStatus.downloading) return;
    _pauseTokens[taskId] = true;
    _tasks[idx] = task.copyWith(status: DownloadStatus.paused);
    await _persist();
    notifyListeners();
  }

  /// 恢复下载任务（项 5）。
  ///
  /// MVP 语义：从断点续传或重新开始。仅对 status == paused 的任务生效。
  /// 若暂停期间下载已在后台完成（localPath 存在），直接标记为 completed；
  /// 否则标记为 downloading，让在途下载继续或等待重试。
  Future<void> resumeTask(String taskId) async {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx < 0) return;
    final task = _tasks[idx];
    if (task.status != DownloadStatus.paused) return;
    _pauseTokens.remove(taskId);

    // 若下载已在暂停期间完成（localPath 文件存在），直接标记为 completed。
    if (task.localPath != null && await fs.exists(task.localPath!)) {
      _tasks[idx] = task.copyWith(
        status: DownloadStatus.completed,
        downloadedChapters: task.totalChapters,
        completedAt: task.completedAt ??
            DateTime.now().millisecondsSinceEpoch,
      );
    } else {
      _tasks[idx] = task.copyWith(status: DownloadStatus.downloading);
    }
    await _persist();
    notifyListeners();
  }

  /// 重试失败的任务（项 5）。
  ///
  /// 重新从源拉取详情与章节，重置为 pending 并重新调度下载。
  /// 仅对 status == failed 的任务生效；其余状态（含 paused）不处理。
  /// 网络/源异常时仍标记回 failed 并记录错误，不做破坏性操作。
  ///
  /// **只重试原任务选中的章节**：若原任务是「单话/单集」下载，重试时按
  /// [DownloadTask.chapterTitles] 过滤回选中的章节，而不是全量下载
  /// （修复 131：单话下载失败后重试 → 不再下载全内容）。
  Future<void> retryTask(String taskId) async {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx < 0) return;
    final task = _tasks[idx];
    if (task.status != DownloadStatus.failed) return;
    if (task.sourceId == null || task.contentId == null) {
      _updateTask(taskId,
          status: DownloadStatus.failed, error: 'Missing source/content id');
      return;
    }

    final source = sourceRepo.getById(task.sourceId!);
    if (source == null) {
      _updateTask(taskId,
          status: DownloadStatus.failed, error: 'Source not found');
      return;
    }

    try {
      final item = await service.fetchDetail(source, task.contentId!);
      final chapters = await _fetchChaptersForRetry(
        source, item, task.sourceType, idFallback: task.contentId);
      // 过滤回原任务选中的章节（保留全局序号），标题不匹配时兜底全量。
      final List<Episode> retryChapters =
          _selectRetryChapters(chapters, task);
      _tasks[idx] = task.copyWith(
        status: DownloadStatus.pending,
        error: null,
        downloadedChapters: 0,
      );
      await _persist();
      notifyListeners();
      _scheduleDownload(_tasks[idx], item, retryChapters);
    } catch (e) {
      _updateTask(taskId,
          status: DownloadStatus.failed, error: e.toString());
      AppLog.instance.e('[重试失败] ${task.title} (${task.id}): $e');
    }
  }

  /// 从重试抓取到的完整章节列表中，挑选原任务选中的章节。
  ///
  /// 原任务 [DownloadTask.chapterTitles] 记录了选中的章节标题（含「单话/单集」）。
  /// 按标题匹配回选中的章节；一个都匹配不上（站点章节标题已变更）时
  /// 退回全量列表，保证至少能继续下载。
  List<Episode> _selectRetryChapters(
      List<Episode> chapters, DownloadTask task) {
    if (chapters.isEmpty || task.chapterTitles.isEmpty) return chapters;
    final wanted = task.chapterTitles.toSet();
    final List<Episode> matched = <Episode>[];
    for (var i = 0; i < chapters.length; i++) {
      final ch = chapters[i];
      if (wanted.contains(ch.title)) {
        // 保留全局序号（原 addTask 按选中下标 gi+1 编号，这里同样按
        // 完整列表下标编号，保证重试落盘文件名与原批次一致）。
        matched.add(ch.copyWith(number: i + 1));
      }
    }
    return matched.isNotEmpty ? matched : chapters;
  }

  /// 按任务类型拉取章节列表（重试专用）。
  ///
  /// [idFallback]：部分源的 `fetchDetail` 返回的 [MediaItem.id] 为空（解析器未回填
  /// id）。若直接拿它拼章节列表 URL 会得到空 id（如 `vod/detail/id/.html`）→ 404，
  /// 重试必然失败且报错误导。此时回退到原始 [DownloadTask.contentId] 保证 URL 正确。
  Future<List<Episode>> _fetchChaptersForRetry(
    PluginConfig source,
    MediaItem item,
    SourceType sourceType, {
    String? idFallback,
  }) async {
    final String id = item.id.isNotEmpty ? item.id : (idFallback ?? item.id);
    switch (sourceType) {
      case SourceType.novelSource:
        return service.fetchNovelChapters(source, id);
      case SourceType.mangaSource:
        return service.fetchChapters(source, id);
      default:
        return service.fetchEpisodes(source, id, detailUrl: item.detailUrl);
    }
  }

  /// 归档已完成任务——从已下载列表隐藏，但保留磁盘文件可随时恢复。
  ///
  /// 仅对 status==completed 的任务生效。
  Future<void> archive(String taskId) async {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx < 0) return;
    final task = _tasks[idx];
    if (task.status != DownloadStatus.completed) return;
    _tasks[idx] = task.copyWith(
      archived: true,
      archivedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _persist();
    notifyListeners();
  }

  /// 恢复归档任务——重新出现在已下载列表。
  Future<void> unarchive(String taskId) async {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx < 0) return;
    final task = _tasks[idx];
    if (!task.archived) return;
    _tasks[idx] = task.copyWith(
      archived: false,
      archivedAt: null,
      status: DownloadStatus.completed,
    );
    await _persist();
    notifyListeners();
  }

  /// 清除全部记录。
  ///
  /// [deleteFiles] = false → 清空全部任务记录（含已完成）并清存储，不删除磁盘文件；
  /// 随后 [recoverOrphanedDownloads] 从磁盘 meta.json 恢复已完成任务，
  /// 「已下载内容页」继续显示已完成内容；「下载列表页」过滤 completed 后
  /// 不显示已下载记录（下载列表 = 下载队列）。
  /// [deleteFiles] = true → 删文件 + meta.json，所有记录全部清除。
  Future<void> clearAll({required bool deleteFiles}) async {
    if (deleteFiles) {
      // 删除所有任务的磁盘文件 + meta.json
      for (final task in _tasks) {
        await _deleteTaskFiles(task);
      }
      _tasks.clear();
      await storage.clear();
    } else {
      // 清空全部记录（不删文件），再从磁盘恢复已完成任务供已下载内容页显示。
      _tasks.clear();
      await storage.clear();
      await recoverOrphanedDownloads();
      await _recoverLegacyOrphanedFolders();
    }
    notifyListeners();
  }

  /// 从 `.meta.json` 恢复孤立下载记录。
  ///
  /// 扫描下载根目录及其作品子目录（新布局 `根/类型/作品名/*.meta.json`）下的
  /// 所有 `*.meta.json`，验证 `localPath` 文件存在 → 标记为 completed 重建到任务列表。
  Future<void> recoverOrphanedDownloads() async {
    final List<String> metaPaths = await _findMetaJsonPaths();
    for (final metaPath in metaPaths) {
      try {
        final raw = await fs.readString(metaPath);
        final task = DownloadTask.fromJsonString(raw);

        // 避免重复添加
        if (_tasks.any((t) => t.id == task.id)) continue;

        // 验证产物文件/目录是否存在
        if (task.localPath != null && await fs.exists(task.localPath!)) {
          // 旧数据 meta.json 可能无 chapterFilePaths：按类型从 localPath
          // 推导逐章/集路径，保证阅读器可翻话/切集；新数据直接采用持久化值。
          final List<String>? chapterFiles = task.chapterFilePaths ??
              await _deriveChapterFilePaths(task);
          _tasks.add(task.copyWith(
            status: DownloadStatus.completed,
            // 旧数据可能无 coverKey：按 sourceId+contentId 补算，使其并入
            // 同作品分组并正确复用共享封面。
            coverKey: task.coverKey ?? _coverKeyFromTask(task),
            chapterFilePaths: chapterFiles,
            completedAt: task.completedAt ??
                DateTime.now().millisecondsSinceEpoch,
          ));
        }
      } catch (_) {
        // 损坏的 meta.json 跳过
      }
    }
  }

  /// 收集下载根目录与作品子目录下的全部 `*.meta.json` 路径。
  ///
  /// - 根目录：旧布局 `<taskId>.meta.json`（兼容历史数据）；
  /// - 子目录：新布局 `根/类型/作品名/<taskId>.meta.json`。作品目录只下探两层
  /// （类型 → 作品名），避免扫到作品目录内章节产物目录。
  Future<List<String>> _findMetaJsonPaths() async {
    final List<String> out = <String>[];
    final rootEntries = await fs.listFiles(fs.basePath);
    for (final name in rootEntries) {
      if (name.endsWith('.meta.json')) {
        out.add(fs.join(fs.basePath, name));
        continue;
      }
      // 类型子目录（小说/漫画/媒体）下的作品目录。
      final String typeDir = fs.join(fs.basePath, name);
      if (!await fs.exists(typeDir)) continue;
      final List<String> workDirs = await fs.listFiles(typeDir);
      for (final workName in workDirs) {
        final workDir = fs.join(typeDir, workName);
        final List<String> metas = await fs.listFiles(workDir);
        for (final metaName in metas) {
          if (metaName.endsWith('.meta.json')) {
            out.add(fs.join(workDir, metaName));
          }
        }
      }
    }
    return out;
  }

  /// 恢复遗留孤立文件夹/文件（无 .meta.json 的旧数据）。
  ///
  /// 扫描下载目录，对没有对应 .meta.json 的产物文件：
  /// 1. 按扩展名推断类型（.cbz→comic / .epub→novel / .txt→novel / 视频→media）。
  /// 2. 清理标题中的时间戳后缀（如 `Title_1700000000000` → `Title`）。
  /// 3. 查找同目录 `cover.jpg` / `folder.jpg` 作为 coverUrl。
  /// 4. 创建 completed DownloadTask 并写入 meta.json（后续可正常恢复）。
  Future<void> _recoverLegacyOrphanedFolders() async {
    final files = await fs.listFiles(fs.basePath);

    for (final filename in files) {
      // 跳过 meta.json 和封面图片
      if (filename.endsWith('.meta.json')) continue;
      if (filename.endsWith('.jpg') || filename.endsWith('.png')) continue;
      // 跳过类型分类目录（小说/漫画/媒体）：其内容已在
      // [_findMetaJsonPaths] / 作品目录内 meta.json 中处理，避免误当孤立产物。
      if (_typeDirName(SourceType.novelSource) == filename ||
          _typeDirName(SourceType.mangaSource) == filename ||
          _typeDirName(SourceType.animeSource) == filename) {
        continue;
      }

      final filePath = fs.join(fs.basePath, filename);

      // 检查是否已有对应 meta.json（已被 recoverOrphanedDownloads 处理）
      final knownIds = _tasks.map((t) => t.id).toSet();
      final knownPaths = _tasks
          .where((t) => t.localPath != null)
          .map((t) => t.localPath!)
          .toSet();
      if (knownPaths.contains(filePath)) continue;

      // 推断类型和格式
      final inferred = _inferFromFilename(filename);
      if (inferred == null) continue;

      // 检查是否是已知的 task ID（避免重复）
      final taskId = _inferTaskId(filename);
      if (knownIds.contains(taskId)) continue;

      // 清理标题
      final cleanTitle = _cleanTitleTimestamp(inferred.$2);

      // 查找封面
      String? coverUrl;
      final coverPath = fs.join(fs.basePath, '$taskId.jpg');
      if (await fs.exists(coverPath)) {
        coverUrl = coverPath;
      } else {
        // 查找 folder.jpg / cover.jpg
        final folderCover = fs.join(fs.basePath, 'folder.jpg');
        if (await fs.exists(folderCover)) {
          coverUrl = folderCover;
        }
      }

      // 创建恢复任务
      final now = DateTime.now().millisecondsSinceEpoch;
      // 遗留数据无 sourceId，contentId 取文件名（taskId），封面文件即 `${taskId}.jpg`
      // —— 故 coverKey = taskId，与 [_saveCoverImage] 落盘命名一致，合并/复用生效。
      final String? coverKey = coverUrl != null ? taskId : null;
      final task = DownloadTask(
        id: taskId,
        title: cleanTitle,
        sourceType: inferred.$1,
        contentId: taskId,
        format: inferred.$3,
        totalChapters: 1,
        downloadedChapters: 1,
        status: DownloadStatus.completed,
        createdAt: now,
        completedAt: now,
        localPath: filePath,
        coverUrl: coverUrl,
        localCoverPath: coverUrl,
        coverKey: coverKey,
      );

      _tasks.add(task);
      try {
        await _writeMetaJson(task);
      } on Exception catch (e) {
        // 单个异常条目（如用户下载目录里的无关同名文件）不应中断整个
        // 恢复流程乃至应用启动：丢弃该任务，继续处理其余条目。
        _tasks.remove(task);
        assert(() {
          // ignore: avoid_print
          print('[DownloadManager] 恢复遗留产物失败: $filename, $e');
          return true;
        }());
      }
    }

    if (_tasks.isNotEmpty) {
      await _persist();
    }
  }

  /// 从文件名推断 (SourceType, 原始标题, DownloadFormat)。
  (SourceType, String, DownloadFormat)? _inferFromFilename(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.cbz')) {
      return (SourceType.mangaSource, _stripExt(filename), DownloadFormat.cbz);
    }
    if (lower.endsWith('.epub')) {
      return (SourceType.novelSource, _stripExt(filename), DownloadFormat.epub);
    }
    if (lower.endsWith('.txt')) {
      return (SourceType.novelSource, _stripExt(filename), DownloadFormat.txt);
    }
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.ts')) {
      return (SourceType.animeSource, _stripExt(filename), DownloadFormat.video);
    }
    return null;
  }

  /// 移除文件扩展名。
  String _stripExt(String filename) {
    final dot = filename.lastIndexOf('.');
    return dot > 0 ? filename.substring(0, dot) : filename;
  }

  /// 把任意内容 id 清洗为文件名安全字符（task.id 会拼进下载文件名）。
  ///
  /// URL（`https://m.biqubu3.com/book_4656/`）含 `/`、`:`、`?` 等非法文件名字符，
  /// 直接使用会被 SAF 路径按 `/` 拆成多级目录 → 写入/读取错乱。替换规则与
  /// [ComicDownloadHandler._sanitize] 一致；空结果回退 `item`。
  String _safeTaskId(String id) {
    final String clean = id
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
    return clean.isEmpty ? 'item' : clean;
  }

  /// 按媒体类型返回下载分类目录名（中文，便于用户在文件管理器识别）。
  ///
  /// 与「每部作品一个目录」配合，形成 `下载根/类型/作品名/逐话文件` 的层级
  /// （通用离线阅读器的目录组织方式）。
  static String _typeDirName(SourceType type) => switch (type) {
        SourceType.novelSource => '小说',
        SourceType.mangaSource => '漫画',
        SourceType.animeSource => '媒体',
      };

  /// 清洗作品名为安全文件名：仅剔除文件系统非法字符，保留中文与可读性；
  /// 过长截断（≤60 字符），为空时回退到 contentId（同样清洗），仍为空给默认名。
  ///
  /// 与 [_safeTaskId]（用于 task.id/coverKey，倾向全 ASCII 安全）不同，此处
  /// 保留标题中的中文，让用户在文件管理器能直接认出作品。`%` 必须清洗：
  /// Dart `Uri.parse`/`Uri.decodeComponent` 对含裸 `%`（非合法转义）的字符串
  /// 会抛 `Illegal percent encoding in URI`（下载后打开小说/漫画时报错的来源）。
  String _safeTitle(String title, String contentId) {
    final String base = title.isNotEmpty ? title : contentId;
    String clean = base
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll('%', '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (clean.isEmpty) clean = _safeTaskId(contentId);
    if (clean.length > 60) clean = clean.substring(0, 60).trim();
    // 折叠连续空格并整体转下划线尾，避免首尾空格被文件系统吞掉。
    clean = clean.replaceAll(RegExp(r' +'), '_');
    return clean.isEmpty ? '未命名作品' : clean;
  }

  /// 从文件名推断 task ID（取扩展名前的部分）。
  String _inferTaskId(String filename) => _stripExt(filename);

  /// 清理标题中的时间戳后缀（如 `Title_1700000000000` → `Title`）。
  String _cleanTitleTimestamp(String title) {
    return title.replaceAll(RegExp(r'_\d{10,}$'), '').trim();
  }

  /// 更新格式偏好。
  Future<void> setFormatPrefs(DownloadFormatPreferences prefs) async {
    _formatPrefs = prefs;
    final store = DownloadFormatPreferencesStore();
    await store.save(prefs);
    notifyListeners();
  }

  // ── 内部方法 ──────────────────────────────────────────

  DownloadFormat _resolveFormat(SourceType type) {
    return switch (type) {
      SourceType.mangaSource => _formatPrefs.comicFormat,
      SourceType.novelSource => _formatPrefs.novelFormat,
      SourceType.animeSource => DownloadFormat.video,
    };
  }

  // ── 下载调度（受最大同时下载数约束） ──────────────────────────

  /// 从持久化存储重新加载下载设置（供本次及后续调度使用）。
  Future<void> _loadSettings() async {
    try {
      _settings = await DownloadSettingsStore().load();
    } catch (_) {
      // 读取失败则保持现有设置（默认或上次成功值）
    }
  }

  /// 按最大并发限制调度一次下载：立即执行或入队等待。
  void _scheduleDownload(
    DownloadTask task,
    MediaItem item,
    List<Episode> chapters,
  ) {
    if (_running < _settings.maxConcurrent) {
      _startDownload(task, item, chapters);
    } else {
      _pending.add(_QueuedDownload(task, item, chapters));
      notifyListeners();
    }
  }

  /// 启动一次实际下载，完成后从队列补充下一个。
  ///
  /// 仅 WiFi 模式：若未连接 WiFi，任务挂起到 [_waitingForWifi]，
  /// 待网络恢复后由 [_resumeWaitingForWifi] 重新调度；不占用并发额度。
  Future<void> _startDownload(
    DownloadTask task,
    MediaItem item,
    List<Episode> chapters,
  ) async {
    _running++;
    // 鸿蒙：有下载在跑时申请后台保活（dataTransfer），退后台不被冻结。
    // 在首个 await 前持有，队列交接时新任务先持有、旧任务后释放，不会 stop/start 抖动。
    BackgroundTask.acquire();
    if (_settings.wifiOnly && !await _isWifiConnected()) {
      _running--;
      BackgroundTask.release();
      _updateTask(task.id, status: DownloadStatus.waitingForWifi);
      _waitingForWifi.add(_QueuedDownload(task, item, chapters));
      notifyListeners();
      return;
    }
    _updateTask(task.id, status: DownloadStatus.downloading);
    try {
      await _executeDownload(task, item, chapters);
    } finally {
      _running--;
      _pumpQueue();
      BackgroundTask.release();
    }
  }

  /// 从等待队列取出下一个下载（若并发额度允许）。
  void _pumpQueue() {
    while (_pending.isNotEmpty && _running < _settings.maxConcurrent) {
      final next = _pending.removeAt(0);
      _startDownload(next.task, next.item, next.chapters);
    }
    if (_pending.isNotEmpty) notifyListeners();
  }

  Future<void> _executeDownload(
    DownloadTask task,
    MediaItem item,
    List<Episode> chapters,
  ) async {
    try {
      final source = item.sourceId != null
          ? sourceRepo.getById(item.sourceId!)
          : null;

      if (source == null) {
        _updateTask(task.id,
            status: DownloadStatus.failed, error: 'Source not found');
        return;
      }

      // 小说任务：读取该作品的阅读偏好，落盘时应用与阅读器一致的繁简转换
      // （阅读器内开繁→简后，离线缓存与显示保持相同）。
      ChineseConvertMode novelConvertMode = ChineseConvertMode.none;
      if (task.sourceType == SourceType.novelSource) {
        try {
          final novelPrefs = await NovelReaderPreferencesStore().get(
              task.contentId);
          novelConvertMode =
              ChineseConvertMode.fromString(novelPrefs.chineseConvert);
        } on Object {
          // 偏好读取失败按不转换处理，不阻塞下载。
        }
      }

      final handler = _createHandler(task, source, item.title, item.author,
          chapters,
          novelConvertMode: novelConvertMode,
          novelCoverUrl:
              task.sourceType == SourceType.novelSource ? item.coverUrl : null);

      AppLog.instance.i('[下载开始] ${item.title} (${task.id}, '
          '${chapters.length} 章, 格式 ${task.format.label})');

      // 取消检查：开始前命中 → 直接中止（不写盘、不写 meta）。
      if (_cancelledTaskIds.contains(task.id)) {
        await _cleanupCancelledTask(task);
        return;
      }

      final DownloadResult result;
      try {
        result = await handler.download(
          task,
          onProgress: (downloaded, total, chapterProgress) {
            _updateTask(task.id,
                downloadedChapters: downloaded,
                totalChapters: total,
                chapterProgress: chapterProgress);
          },
          isCancelled: () => _cancelledTaskIds.contains(task.id),
        );
      } on DownloadCancelledException {
        // 用户取消：清理半成品，不标记失败/完成，不写 meta.json（修复 132）。
        AppLog.instance.i('[下载取消] ${item.title} (${task.id})');
        await _cleanupCancelledTask(task);
        return;
      }
      final localPath = result.workPath;
      final chapterFiles = result.chapterFilePaths;
      // 与章节文件路径保持平行：本地下载的章节身份以"本轮实际下载的 chapters"
      // 为准（重试时可能是原选中章节的子集），避免 chapterFilePaths 与
      // chapterIds 错位导致阅读器按身份对应章节时张冠李戴。
      final List<String> chapterIdsForRun =
          chapters.map((c) => c.id).toList();

      // 下载完成瞬间又被取消（最后章节与取消竞态）→ 同样按取消处理。
      if (_cancelledTaskIds.contains(task.id)) {
        AppLog.instance.i('[下载取消] ${item.title} (${task.id}) 完成前命中取消');
        await _cleanupCancelledTask(task);
        return;
      }

      // 保存封面（同作品复用已有封面，避免重复下载；落盘于作品目录内 cover.jpg）
      String? localCoverPath;
      if (item.coverUrl != null && item.coverUrl!.startsWith('http')) {
        localCoverPath = await _saveCoverImage(
          task.id,
          task.coverKey,
          item.coverUrl!,
          source: source,
          workDir: task.localPath,
        );
      }

      // 暂停检查：若用户在下载过程中暂停，保留已下载文件但状态保持 paused。
      if (_pauseTokens[task.id] == true) {
        _pauseTokens.remove(task.id);
        final pausedTask = task.copyWith(
          status: DownloadStatus.paused,
          downloadedChapters: task.totalChapters,
          localPath: localPath,
          chapterFilePaths: chapterFiles,
          chapterIds: chapterIdsForRun,
          completedAt: DateTime.now().millisecondsSinceEpoch,
          localCoverPath: localCoverPath,
          coverUrl: localCoverPath ?? item.coverUrl,
        );
        _updateTaskRaw(pausedTask);
        await _writeMetaJson(pausedTask);
        await _persist();
        notifyListeners();
        return;
      }

      final completed = task.copyWith(
        status: DownloadStatus.completed,
        downloadedChapters: task.totalChapters,
        localPath: localPath,
        chapterFilePaths: chapterFiles,
        chapterIds: chapterIdsForRun,
        completedAt: DateTime.now().millisecondsSinceEpoch,
        localCoverPath: localCoverPath,
        coverUrl: localCoverPath ?? item.coverUrl,
      );

      // 封面保存期间又被取消（取消竞态最后一帧）→ 按取消处理，
      // 不写 meta.json，避免重启后孤儿恢复成 completed（修复 132）。
      if (_cancelledTaskIds.contains(task.id)) {
        AppLog.instance.i('[下载取消] ${item.title} (${task.id}) 封面前命中取消');
        await _cleanupCancelledTask(task);
        return;
      }

      _updateTaskRaw(completed);
      await _writeMetaJson(completed);
      await _persist();
      notifyListeners();
      // 小说 EPUB 导出自动上传 WebDAV（开关开启时；best-effort 后台执行，
      // 失败仅记日志，不影响本地下载结果）。TXT 逐章产物不整包上传。
      if (task.sourceType == SourceType.novelSource) {
        unawaited(_maybeUploadNovelExports(completed));
      }
    } catch (e) {
      // 失败即清理半成品（作品目录 / 0 字节封面），避免"只有空文件夹"残留
      // 且没有报错入口（任务错误文本只在下载管理-失败里可见）。
      //
      // ⚠️ 只清理「本次任务」写入的文件，绝不整体删除作品目录：
      // 同一作品多次分批下载共享同一目录，整体删除会把已下载的其他批次
      // 一并清掉 → 文件管理器里"下载的内容消失"（修复 133）。
      try {
        await _deleteTaskPartialOutput(task);
      } catch (_) {
        // 清理失败不影响失败状态记录。
      }
      _updateTask(task.id,
          status: DownloadStatus.failed, error: e.toString());
      AppLog.instance.e('[下载失败] ${task.title} (${task.id}): $e');
    }
  }

  /// 取消后的清理：删除本次任务写入的作品目录（含 meta.json）。
  ///
  /// 注意：[cancel(deleteFiles:false)] 语义是「仅删记录、保留文件可恢复」，
  /// 但**在途任务**的产物是半成品，必须清掉，否则重启后
  /// [recoverOrphanedDownloads] 会把它当 completed 复活（"取消后下载不止"）。
  Future<void> _cleanupCancelledTask(DownloadTask task) async {
    _cancelledTaskIds.remove(task.id);
    await _deleteTaskPartialOutput(task);
    // 保留任务记录为 cancelled 状态（供历史查看），不写 meta.json。
    await _persist();
    notifyListeners();
  }

  /// 小说导出自动上传 WebDAV。读取云同步配置的
  /// `autoUploadNovelExports` 开关，把本次任务的 EPUB 单文件逐个上传到
  /// `nexhub/exports/`。任何失败只记日志（后台旁路，不阻塞下载完成态）。
  Future<void> _maybeUploadNovelExports(DownloadTask completed) async {
    try {
      final cfg = await CloudSyncConfigStore().load();
      if (!cfg.autoUploadNovelExports) return;
      if (cfg.url.isEmpty) return;
      final files = (completed.chapterFilePaths ?? const <String>[])
          .where((f) => f.toLowerCase().endsWith('.epub'))
          .toList(growable: false);
      if (files.isEmpty) return;
      final uploader = NovelExportUploadService();
      for (final f in files) {
        try {
          // 鸿蒙公共目录产物：先落应用缓存为真实文件再上传。
          final String local =
              isOhosDocPath(f) ? await OhosPublicStorage.materialize(f) : f;
          final result = await uploader.uploadFile(local);
          AppLog.instance.i(
              '[导出上传] ${completed.title} → ${result.remoteUrl}');
        } on Object catch (e) {
          AppLog.instance.w('[导出上传失败] ${completed.title}: $e');
        }
      }
    } on Object catch (e) {
      AppLog.instance.w('[导出上传] 配置读取失败: $e');
    }
  }

  /// 删除某任务在作品目录内写入的文件（不含其它批次的共享文件）。
  ///
  /// - 视频/漫画：作品目录（`task.localPath`）内 `NNN.mp4`/`NNN.cbz`/子目录；
  /// - 小说 TXT：`NNNNN_章.txt` + `images/`；EPUB：整本单文件。
  ///
  /// 通过「删除前快照作品目录 → 删除后对比」的思路无法精确区分批次，
  /// 这里按任务元数据删除本次写入产物：封面、meta.json，以及
  /// 视频/漫画作品目录（仅当该目录无其他已完成批次引用时才删整目录）。
  Future<void> _deleteTaskPartialOutput(DownloadTask task) async {
    final String? workDir = task.localPath;
    if (workDir == null || workDir.isEmpty) return;

    // 作品目录仍被其它已完成批次引用 → 只清本任务 meta.json，保留目录。
    if (_workDirStillReferenced(workDir, task.id)) {
      final String metaInWork = fs.join(workDir, '${task.id}.meta.json');
      if (await fs.exists(metaInWork)) await fs.delete(metaInWork);
      return;
    }

    // 无其它批次引用 → 删除整个作品目录（含本次写入的全部文件 + meta.json）。
    if (await fs.exists(workDir)) {
      await fs.delete(workDir);
    }
    // 遗留兜底：个别旧数据仍按 task.id 命名（极少），一并清理避免残留。
    final String partial = fs.join(fs.basePath, task.id);
    if (await fs.exists(partial)) await fs.delete(partial);
    final String partialCover = fs.join(fs.basePath, '${task.id}.jpg');
    if (await fs.exists(partialCover)) await fs.delete(partialCover);
  }

  DownloadHandler _createHandler(
    DownloadTask task,
    PluginConfig source,
    String title,
    String? author,
    List<Episode> chapters, {
    ChineseConvertMode novelConvertMode = ChineseConvertMode.none,
    String? novelCoverUrl,
  }) {
    switch (task.sourceType) {
      case SourceType.mangaSource:
        return ComicDownloadHandler(
          service: service,
          fs: fs,
          source: source,
          comicId: task.contentId,
          chapters: chapters,
          format: task.format,
          concurrency: _settings.threadCount,
        );
      case SourceType.novelSource:
        return NovelDownloadHandler(
          service: service,
          fs: fs,
          source: source,
          novelId: task.contentId,
          chapters: chapters,
          format: task.format,
          bookTitle: title,
          author: author,
          concurrency: _settings.threadCount,
          convertMode: novelConvertMode,
          // 导出附带划线 / 批注附录。
          includeHighlights: true,
          // 导出附带已缓存的章节译文（段落翻译）。
          includeTranslations: true,
          // 全局导出模板（CSS/封面/简介）+ 网络封面（嵌入 EPUB 封面页）。
          coverUrl: novelCoverUrl,
        );
      case SourceType.animeSource:
        return MediaDownloadHandler(
          service: service,
          fs: fs,
          source: source,
          contentId: task.contentId,
          chapters: chapters,
          concurrency: _settings.threadCount,
        );
    }
  }

  /// 计算封面合并键：同「源 + 内容」的作品共用同一张封面文件。
  ///
  /// 形如 `sourceId|contentId`，文件名安全（不带入 `/`、`:` 等）。
  /// 任一为空时回退为 null（该任务封面退化为按 taskId 单独存，互不影响）。
  /// 注意：仅用于封面去重判断，不作为「作品合并」的唯一键（合并键在 UI 层由
  /// [groupKeyFor] 计算，且允许 sourceId 为 null 时按 contentId 兜底）。
  String? _computeCoverKey(MediaItem item) {
    final String source = item.sourceId ?? '';
    final String content = _safeTaskId(item.id);
    if (content.isEmpty || content == 'item') return null;
    final safeSource = source.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return '$safeSource|$content';
  }

  /// 从旧数据（无 [DownloadTask.chapterFilePaths]）按类型推导逐章/集路径。
  ///
  /// 用于 [recoverOrphanedDownloads] 兼容旧版 meta.json。新数据已持久化列表，不走此。
  /// - 视频：扫描作品目录内 `NNN.mp4`/`.ts` 并排序；
  /// - 漫画 cbz：单文件则作为整本（[localPath] 即单章），多话旧结构罕见；
  /// - 漫画 folder：作品目录内按序命名的子目录（话）；
  /// - 小说：整本单文件（[localPath]）。
  Future<List<String>> _deriveChapterFilePaths(DownloadTask task) async {
    final String? root = task.localPath;
    if (root == null || root.isEmpty) return const <String>[];
    switch (task.sourceType) {
      case SourceType.animeSource:
        if (!await fs.exists(root)) return const <String>[];
        final files = await fs.listFiles(root);
        final sorted = files
            .where((f) =>
                f.toLowerCase().endsWith('.mp4') ||
                f.toLowerCase().endsWith('.ts'))
            .toList()
          ..sort();
        return sorted.map((f) => fs.join(root, f)).toList();
      case SourceType.mangaSource:
        // 单 cbz 文件（旧整本）：作为"一话"处理。
        if (root.toLowerCase().endsWith('.cbz')) return <String>[root];
        // 作品目录：内含 NNN.cbz（新逐话）或按序命名的子目录（旧逐话散图）。
        if (!await fs.exists(root)) return const <String>[];
        final entries = await fs.listFiles(root);
        final cbz = entries
            .where((f) => f.toLowerCase().endsWith('.cbz'))
            .toList()
          ..sort();
        if (cbz.isNotEmpty) {
          return cbz.map((f) => fs.join(root, f)).toList();
        }
        final dirs = entries
            .where((f) =>
                !f.toLowerCase().endsWith('.jpg') &&
                !f.toLowerCase().endsWith('.png') &&
                !f.toLowerCase().endsWith('.meta.json'))
            .toList()
          ..sort();
        return dirs.map((f) => fs.join(root, f)).toList();
      case SourceType.novelSource:
        // 新布局：localPath 是作品目录，目录内 `<书名>.epub|.txt` 是产物。
        // 旧布局：localPath 直接是文件（整本单文件）。
        if (root.toLowerCase().endsWith('.epub') ||
            root.toLowerCase().endsWith('.txt')) {
          return <String>[root];
        }
        if (!await fs.exists(root)) return const <String>[];
        final novelFiles = await fs.listFiles(root);
        final novel = novelFiles
            .where((f) =>
                f.toLowerCase().endsWith('.epub') ||
                f.toLowerCase().endsWith('.txt'))
            .toList()
          ..sort();
        return novel.map((f) => fs.join(root, f)).toList();
    }
  }

  /// 由已有任务反推封面合并键（旧数据 / 恢复场景补算 coverKey 用）。
  ///
  /// 与 [_computeCoverKey] 规则一致，但输入为 [DownloadTask] 的 sourceId/contentId。
  String? _coverKeyFromTask(DownloadTask t) {
    final String source = t.sourceId ?? '';
    final String content = _safeTaskId(t.contentId);
    if (content.isEmpty || content == 'item') return null;
    final safeSource = source.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return '$safeSource|$content';
  }

  /// 保存封面：先查同作品已有封面文件，命中则直接复用（不重复下载）。
  ///
  /// [taskId] 用于回退：当 [coverKey] 为空（旧数据 / 无法计算）时仍按原
  /// `${taskId}.jpg` 落盘，保持旧行为。命中共享封面时返回其路径，供
  /// [DownloadTask.localCoverPath] / [DownloadTask.coverUrl] 引用。
  ///
  /// 封面落盘位置：优先 [workDir]（作品目录，下载完成后在 `cover.jpg`，
  /// 同作品多批次共享该目录 → 天然复用去重）；[workDir] 为空（下载前 /
  /// 旧兼容）回退根目录 `${coverKey}.jpg`。
  Future<String?> _saveCoverImage(
    String taskId,
    String? coverKey,
    String url, {
    PluginConfig? source,
    String? workDir,
  }) async {
    final String fileName =
        workDir != null && workDir.isNotEmpty ? 'cover.jpg' : '$coverKey.jpg';
    final String dir = workDir != null && workDir.isNotEmpty
        ? workDir
        : fs.basePath;
    final String existing = fs.join(dir, fileName);
    try {
      // 同作品已有封面：直接复用，不再拉取网络（省流量、避免重复下载）。
      if (await fs.exists(existing)) {
        return existing;
      }
      // 封面与在线 / 章节图同防盗链策略：缺失 Referer 时源 CDN 间歇性 403。
      final Map<String, String> headers = <String, String>{
        ...?source?.fetchHeadersFor(url),
        'Accept': 'image/jpeg,image/png,image/webp,image/gif,*/*;q=0.8',
      };
      final bytes = await HttpFetcher.instance.getBytes(url, headers: headers);
      if (bytes.isEmpty) return null;
      await fs.writeBytes(existing, Uint8List.fromList(bytes));
      return existing;
    } catch (_) {
      return null;
    }
  }

  void _updateTask(
    String taskId, {
    DownloadStatus? status,
    int? downloadedChapters,
    int? totalChapters,
    double? chapterProgress,
    String? error,
  }) {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx < 0) return;
    _tasks[idx] = _tasks[idx].copyWith(
      status: status,
      downloadedChapters: downloadedChapters,
      totalChapters: totalChapters,
      chapterProgress: chapterProgress,
      error: error,
    );
    notifyListeners();
  }

  void _updateTaskRaw(DownloadTask updated) {
    final idx = _tasks.indexWhere((t) => t.id == updated.id);
    if (idx >= 0) {
      _tasks[idx] = updated;
    }
  }

  Future<void> _persist() async {
    await storage.saveAll(_tasks);
  }

  Future<void> _writeMetaJson(DownloadTask task) async {
    // meta.json 放作品目录内（`<localPath>/<task.id>.meta.json`），随作品走，
    // 便于用户整理/迁移整个作品文件夹；无 localPath（下载前）回退下载根目录。
    final String dir = (task.localPath != null && task.localPath!.isNotEmpty)
        ? task.localPath!
        : fs.basePath;
    final metaPath = fs.join(dir, '${task.id}.meta.json');
    try {
      await fs.writeString(metaPath, task.toJsonString());
    } on Exception {
      // 旧布局的 localPath 可以直接是单文件产物（见 注释），此时
      // `<file>/<id>.meta.json` 无法作为目录创建（Windows 抛 errno 183）。
      // meta 退回下载根目录：根布局 `<taskId>.meta.json` 仍能被
      // [_findMetaJsonPaths] 识别，恢复流程不受影响。
      await fs.writeString(
        fs.join(fs.basePath, '${task.id}.meta.json'),
        task.toJsonString(),
      );
    }
  }

  /// 计算某任务封面文件落盘路径（与 [_saveCoverImage] 一致）。
  ///
  /// 有作品目录（[DownloadTask.localPath]）时封面在 `<localPath>/cover.jpg`；
  /// 否则按旧行为退化为 `${task.id}.jpg` / 共享 `${coverKey}.jpg` 于下载根目录。
  /// 供删除时判断是否存在共享引用。
  String _coverFilePath(DownloadTask t) {
    if (t.localPath != null && t.localPath!.isNotEmpty) {
      return fs.join(t.localPath!, 'cover.jpg');
    }
    final String name = t.coverKey != null ? '${t.coverKey}.jpg' : '${t.id}.jpg';
    return fs.join(fs.basePath, name);
  }

  /// 某封面路径是否仍被其它任务引用（避免删共享封面时误删别的批次封面）。
  bool _coverStillReferenced(String path, String selfId) => _tasks.any(
        (t) =>
            t.id != selfId &&
            (t.localCoverPath == path ||
                (t.coverKey != null && _coverFilePath(t) == path)),
      );

  Future<void> _deleteTaskFiles(DownloadTask task) async {
    // 删除 meta.json：优先作品目录内（新布局），回退根目录（旧布局）。
    if (task.localPath != null && task.localPath!.isNotEmpty) {
      final inWork = fs.join(task.localPath!, '${task.id}.meta.json');
      if (await fs.exists(inWork)) {
        await fs.delete(inWork);
      }
    }
    final metaPath = fs.join(fs.basePath, '${task.id}.meta.json');
    if (await fs.exists(metaPath)) {
      await fs.delete(metaPath);
    }
    // 删除作品目录（task.localPath 约定为作品目录：视频/漫画目录，或小说文件）。
    // 仅当无任何其它同作品批次引用该目录时才删，保护"多批下载共享作品目录"。
    if (task.localPath != null &&
        task.localPath!.isNotEmpty &&
        await fs.exists(task.localPath!)) {
      if (!_workDirStillReferenced(task.localPath!, task.id)) {
        await fs.delete(task.localPath!);
      }
    }
    // 遗留兜底：旧数据可能无 localPath 或按 task.id 命名目录。
    final taskDir = fs.join(fs.basePath, task.id);
    if (await fs.exists(taskDir)) {
      await fs.delete(taskDir);
    }
    // 删除封面（仅当无任何其它批次引用该封面文件时才删，保护共享封面）。
    final String coverPath = _coverFilePath(task);
    if (await fs.exists(coverPath) && !_coverStillReferenced(coverPath, task.id)) {
      await fs.delete(coverPath);
    }
    // 遗留兜底：旧布局封面在根目录（coverKey.jpg / taskId.jpg）。
    final String legacyCover =
        fs.join(fs.basePath, '${task.coverKey ?? task.id}.jpg');
    if (legacyCover != coverPath && await fs.exists(legacyCover)) {
      await fs.delete(legacyCover);
    }
  }

  /// 某作品目录是否仍被其它同作品批次引用（避免删共享作品目录时误删别的批次文件）。
  bool _workDirStillReferenced(String path, String selfId) => _tasks.any(
        (t) =>
            t.id != selfId &&
            t.localPath == path &&
            t.status == DownloadStatus.completed,
      );
}
