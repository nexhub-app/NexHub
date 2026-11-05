/// 云同步服务 —— WebDAV 备份与多端同步。
///
/// 数据范围（spec J.2）：
/// 1. 书源/媒体源/订阅源：book_sources / rss_feeds / article_feeds / sources
/// / source_mirrors / chapter_fetch_times / source_library_* Hive box
/// 2. 书签/收藏/书架：favorites / comic_bookmarks / novel_bookmarks /
/// bangumi_subject_links Hive box
/// 3. 阅读/播放历史与进度：media_watched / media_playback_position /
/// comic_progress / novel_progress / media_progress Hive box
/// 4. 其它：download_tasks / danmaku_cache / settings Hive box
/// 5. 阅读器/播放器偏好：PlayerSettings / ReaderDefaultSettings / LayoutSettings
/// / DanmakuSettings 持久化的 SharedPreferences
///
/// ⚠️ 备份白名单统一从 [kStorageBoxNames] 读取（单一事实源），与 splash
/// 启动时打开的 box 严格 1:1 —— 任何 box 增删只需改 storage_boxes.dart。
///
/// Round 2（完整重设计）能力：
/// - 增量同步：记录每 box 内容 sha256，仅上传变化的 box / 偏好。
/// - 冲突解决：拉取前预览本地与云端冲突项，按 box 选择保留云端或本地。
/// - 状态明细：记录上次备份 / 恢复的时间、成功与否、数据条数、范围。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import '../storage/platform_path_compat.dart';
import '../storage/storage_boxes.dart';
import 'backup_archive.dart';

/// 同步频率
enum SyncFrequency { manual, daily, weekly }

/// 一次同步（备份或恢复）的结果明细，用于「状态明细」展示。
class SyncStatusEntry {
  /// 时间戳（毫秒）；null 表示从未执行。
  final int? timestamp;
  /// 是否成功；null 表示从未执行。
  final bool? success;
  /// 涉及的数据条数（0 表示「无变化」或失败未统计）。
  final int itemCount;
  /// 涉及的 box 名列表（空表示全部 / 无）。
  final List<String> scope;
  /// 是否为「无变化，无需同步」。
  final bool noChanges;

  const SyncStatusEntry({
    this.timestamp,
    this.success,
    this.itemCount = 0,
    this.scope = const <String>[],
    this.noChanges = false,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (timestamp != null) 'timestamp': timestamp,
        if (success != null) 'success': success,
        'itemCount': itemCount,
        'scope': scope,
        'noChanges': noChanges,
      };

  factory SyncStatusEntry.fromJson(Map<String, dynamic> json) => SyncStatusEntry(
        timestamp: json['timestamp'] as int?,
        success: json['success'] as bool?,
        itemCount: (json['itemCount'] as int?) ?? 0,
        scope: (json['scope'] as List?)?.map((e) => e as String).toList() ??
            const <String>[],
        noChanges: (json['noChanges'] as bool?) ?? false,
      );
}

/// 单个冲突项（同一 key 在本地与云端取值不同）。
class SyncConflict {
  final String boxName;
  final BackupCategory category;
  final String key;
  final String localPreview;
  final String remotePreview;

  const SyncConflict({
    required this.boxName,
    required this.category,
    required this.key,
    required this.localPreview,
    required this.remotePreview,
  });
}

/// 冲突预览报告：按 box 归组的冲突列表 + 总数。
class SyncConflictReport {
  final Map<String, List<SyncConflict>> byBox;

  SyncConflictReport({required this.byBox});

  int get total =>
      byBox.values.fold(0, (sum, list) => sum + list.length);
}

/// WebDAV 配置（URL/用户名/密码除外，密码用 secure storage）
class CloudSyncConfig {
  final String url;
  final String username;
  final bool autoSync;
  final SyncFrequency frequency;
  final int? lastSyncTimestamp; // null = never synced

  /// 上次备份（上传）明细。
  final SyncStatusEntry? lastUpload;

  /// 上次恢复（下载）明细。
  final SyncStatusEntry? lastRestore;

  /// 各 box（及 `__prefs__`）的内容 sha256，用于增量同步。
  final Map<String, String>? boxHashes;

  /// 小说导出完成后自动把 EPUB 产物上传到 WebDAV `nexhub/exports/`。
  /// 独立于整包备份的 autoSync（导出上传与备份节奏无关）。
  final bool autoUploadNovelExports;

  const CloudSyncConfig({
    this.url = '',
    this.username = '',
    this.autoSync = false,
    this.frequency = SyncFrequency.manual,
    this.lastSyncTimestamp,
    this.lastUpload,
    this.lastRestore,
    this.boxHashes,
    this.autoUploadNovelExports = false,
  });

  /// 下次自动同步时间戳（毫秒）；不满足自动同步条件时返回 null。
  int? get nextSyncTimestamp {
    if (!autoSync ||
        frequency == SyncFrequency.manual ||
        lastUpload?.timestamp == null) {
      return null;
    }
    final delta = frequency == SyncFrequency.daily
        ? const Duration(days: 1)
        : const Duration(days: 7);
    return lastUpload!.timestamp! + delta.inMilliseconds;
  }

  CloudSyncConfig copyWith({
    String? url,
    String? username,
    bool? autoSync,
    SyncFrequency? frequency,
    int? lastSyncTimestamp,
    SyncStatusEntry? lastUpload,
    SyncStatusEntry? lastRestore,
    Map<String, String>? boxHashes,
    bool? autoUploadNovelExports,
  }) {
    return CloudSyncConfig(
      url: url ?? this.url,
      username: username ?? this.username,
      autoSync: autoSync ?? this.autoSync,
      frequency: frequency ?? this.frequency,
      lastSyncTimestamp: lastSyncTimestamp ?? this.lastSyncTimestamp,
      lastUpload: lastUpload ?? this.lastUpload,
      lastRestore: lastRestore ?? this.lastRestore,
      boxHashes: boxHashes ?? this.boxHashes,
      autoUploadNovelExports:
          autoUploadNovelExports ?? this.autoUploadNovelExports,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'url': url,
        'username': username,
        'autoSync': autoSync,
        'frequency': frequency.name,
        if (lastSyncTimestamp != null)
          'lastSyncTimestamp': lastSyncTimestamp,
        if (lastUpload != null) 'lastUpload': lastUpload!.toJson(),
        if (lastRestore != null) 'lastRestore': lastRestore!.toJson(),
        if (boxHashes != null) 'boxHashes': boxHashes,
        'autoUploadNovelExports': autoUploadNovelExports,
      };

  factory CloudSyncConfig.fromJson(Map<String, dynamic> json) {
    SyncFrequency parseFrequency(String? name) {
      switch (name) {
        case 'daily':
          return SyncFrequency.daily;
        case 'weekly':
          return SyncFrequency.weekly;
        case 'manual':
        default:
          return SyncFrequency.manual;
      }
    }

    SyncStatusEntry? parseStatus(dynamic raw) =>
        raw is Map<String, dynamic> ? SyncStatusEntry.fromJson(raw) : null;

    Map<String, String>? parseHashes(dynamic raw) {
      if (raw is! Map) return null;
      return raw.map((k, v) => MapEntry(k as String, v as String));
    }

    return CloudSyncConfig(
      url: (json['url'] as String?) ?? '',
      username: (json['username'] as String?) ?? '',
      autoSync: (json['autoSync'] as bool?) ?? false,
      frequency: parseFrequency(json['frequency'] as String?),
      lastSyncTimestamp: json['lastSyncTimestamp'] as int?,
      lastUpload: parseStatus(json['lastUpload']),
      lastRestore: parseStatus(json['lastRestore']),
      boxHashes: parseHashes(json['boxHashes']),
      autoUploadNovelExports:
          (json['autoUploadNovelExports'] as bool?) ?? false,
    );
  }
}

class CloudSyncConfigStore {
  static const String _prefsKey = 'cloud_sync_config_v1';
  static const String _passwordKey = 'cloud_sync_webdav_password';

  Future<CloudSyncConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return const CloudSyncConfig();
    try {
      return CloudSyncConfig.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const CloudSyncConfig();
    }
  }

  Future<void> save(CloudSyncConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(config.toJson()));
  }

  Future<String?> loadPassword() async {
    const storage = FlutterSecureStorage();
    return await storage.read(key: _passwordKey);
  }

  Future<void> savePassword(String password) async {
    const storage = FlutterSecureStorage();
    await storage.write(key: _passwordKey, value: password);
  }

  Future<void> clearPassword() async {
    const storage = FlutterSecureStorage();
    await storage.delete(key: _passwordKey);
  }
}

/// 远程 WebDAV 文件项
class _RemoteFile {
  final String name;
  final bool isCollection;

  const _RemoteFile({required this.name, required this.isCollection});
}

/// 导入结果：写入条数 + 被应用的 box 远程哈希（用于更新增量基线）。
class _ImportResult {
  final int appliedItems;
  final Map<String, String> remoteHashes;

  const _ImportResult({this.appliedItems = 0, this.remoteHashes = const {}});
}

/// 云同步服务 —— 基于 WebDAV 的备份与多端同步。
///
/// 使用 dio 手写 WebDAV 操作（MKCOL/PUT/GET/PROPFIND/DELETE），不引入额外的
/// webdav 包。密码使用 [FlutterSecureStorage] 安全存储，配置仅持久化非敏感
/// 字段（URL / 用户名 / 自动同步开关 / 频率 / 状态明细 / 增量哈希）。
class CloudSyncService extends ChangeNotifier {
  static const String _remoteDir = '/nexhub';
  static const int _maxBackups = 5;
  static const String _prefsHashKey = '__prefs__';

  CloudSyncConfig _config = const CloudSyncConfig();
  String? _password;
  bool _syncing = false;
  String? _lastError;

  CloudSyncConfig get config => _config;
  bool get isSyncing => _syncing;
  String? get lastError => _lastError;

  Future<void> init() async {
    final store = CloudSyncConfigStore();
    _config = await store.load();
    _password = await store.loadPassword();
  }

  Future<void> updateConfig(CloudSyncConfig config, String? password) async {
    final store = CloudSyncConfigStore();
    _config = config;
    if (password != null) {
      _password = password;
      await store.savePassword(password);
    }
    await store.save(config);
    notifyListeners();
  }

  /// 构造 Basic Auth header value（含 "Basic " 前缀）。
  String _basicAuth(String username, String password) {
    final creds = base64Encode(utf8.encode('$username:$password'));
    return 'Basic $creds';
  }

  /// 规范化 WebDAV URL，确保以 / 结尾的根路径能正确拼接子路径。
  String _buildUrl(String path) {
    String base = _config.url;
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (path.isEmpty || path == '/') return base;
    if (!path.startsWith('/')) path = '/$path';
    return '$base$path';
  }

  Dio _buildDio({required String username, required String password}) {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
      headers: <String, String>{
        'Authorization': _basicAuth(username, password),
      },
    ));
    return dio;
  }

  /// 测试 WebDAV 连接。返回 (success, latencyMs)。
  Future<(bool, int)> testConnection({
    required String url,
    required String username,
    required String password,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      String base = url;
      while (base.endsWith('/')) {
        base = base.substring(0, base.length - 1);
      }
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: <String, String>{
          'Authorization': _basicAuth(username, password),
        },
      ));
      // 用 PROPFIND Depth: 0 探测根目录，验证凭据与连通性。
      final resp = await dio.request<String>(
        base,
        data: '',
        options: Options(
          method: 'PROPFIND',
          headers: <String, String>{
            'Depth': '0',
            'Content-Type': 'application/xml; charset=utf-8',
          },
          responseType: ResponseType.plain,
          validateStatus: (s) => s != null && s >= 200 && s < 400,
        ),
      );
      stopwatch.stop();
      // 207 Multistatus 是 PROPFIND 的标准成功响应
      final ok = resp.statusCode != null && resp.statusCode! < 400;
      return (ok, stopwatch.elapsedMilliseconds);
    } catch (_) {
      stopwatch.stop();
      return (false, stopwatch.elapsedMilliseconds);
    }
  }

  /// 内容哈希（sha256 hex），用于增量同步基线比对。
  String _sha256(String s) =>
      crypto.sha256.convert(utf8.encode(s)).toString();

  /// 深度相等：对两端 encode 后的结构做 JSON 字符串比对（可靠且无需额外依赖）。
  bool _valuesEqual(dynamic a, dynamic b) => jsonEncode(a) == jsonEncode(b);

  /// 把任意值压成一行预览文本（用于冲突界面展示）。
  String _preview(dynamic v) {
    final s = v is String ? v : jsonEncode(v);
    return s.length > 60 ? '${s.substring(0, 60)}…' : s;
  }

  /// 计算给定 box（及偏好）的当前内容哈希。
  Future<Map<String, String>> _computeHashes(
    Set<String> boxNames,
    bool includePrefs,
  ) async {
    final hashes = <String, String>{};
    for (final name in boxNames) {
      if (Hive.isBoxOpen(name)) {
        final box = Hive.box(name);
        final data = box
            .toMap()
            .map((k, v) => MapEntry(k.toString(), _encodeHiveValue(v)));
        hashes[name] = _sha256(jsonEncode(data));
      }
    }
    if (includePrefs) {
      final prefs = await SharedPreferences.getInstance();
      final prefsData = <String, dynamic>{};
      for (final key in prefs.getKeys()) {
        final v = prefs.get(key);
        if (v != null) prefsData[key] = v;
      }
      hashes[_prefsHashKey] = _sha256(jsonEncode(prefsData));
    }
    return hashes;
  }

  /// 立即同步：导出本地 → 打包 ZIP → 上传到 WebDAV。
  ///
  /// [scope] 为 null 时导出全部；否则只导出选中分类对应的 box（含「设置与偏好」
  /// 时才包含 SharedPreferences）。
  /// 增量：仅上传相对上次同步发生变化的 box / 偏好；无变化则直接成功（标记无变化）。
  Future<bool> syncNow({Set<BackupCategory>? scope}) async {
    if (_syncing) return false;
    if (_config.url.isEmpty || _password == null) {
      _lastError = 'no_config';
      return false;
    }
    _syncing = true;
    _lastError = null;
    notifyListeners();
    final resolvedBoxes =
        scope == null ? kStorageBoxNames.toSet() : resolveBoxNames(scope);
    final includePrefs =
        scope == null || scope.contains(BackupCategory.settings);
    try {
      final prevHashes = _config.boxHashes ?? const <String, String>{};
      final currentHashes = await _computeHashes(resolvedBoxes, includePrefs);

      final changedBoxes = <String>{};
      for (final name in resolvedBoxes) {
        if (prevHashes[name] != currentHashes[name]) changedBoxes.add(name);
      }
      final prefsChanged = includePrefs &&
          prevHashes[_prefsHashKey] != currentHashes[_prefsHashKey];

      if (changedBoxes.isEmpty && !prefsChanged) {
        // 无变化：记录「无变化」状态，保留既有哈希基线。
        final ts = DateTime.now().millisecondsSinceEpoch;
        _config = _config.copyWith(
          lastSyncTimestamp: ts,
          lastUpload: SyncStatusEntry(
            timestamp: ts,
            success: true,
            itemCount: 0,
            scope: resolvedBoxes.toList(),
            noChanges: true,
          ),
        );
        await CloudSyncConfigStore().save(_config);
        _syncing = false;
        notifyListeners();
        return true;
      }

      final archive = await _exportToArchive(
        boxNames: changedBoxes,
        includePrefs: prefsChanged,
      );
      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null) {
        _lastError = 'encode_failed';
        _syncing = false;
        notifyListeners();
        return false;
      }
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filename = 'nexhub-backup-$timestamp.zip';

      final dio = _buildDio(
        username: _config.username,
        password: _password!,
      );
      // 创建远程目录（已存在则忽略 405/409）
      await _ensureRemoteDir(dio);
      // 上传 ZIP
      await dio.put(
        _buildUrl('$_remoteDir/$filename'),
        data: Stream.fromIterable(<List<int>>[zipBytes]),
        options: Options(
          headers: <String, String>{
            'Content-Type': 'application/zip',
            'Content-Length': '${zipBytes.length}',
          },
          validateStatus: (s) => s != null && s >= 200 && s < 300,
        ),
      );
      // 清理旧备份（保留最近 5 份）
      await _cleanupOldBackups(dio);

      // 统计上传条数 + 更新哈希基线
      var itemCount = 0;
      for (final name in changedBoxes) {
        if (Hive.isBoxOpen(name)) itemCount += Hive.box(name).length;
      }
      if (prefsChanged) {
        final prefs = await SharedPreferences.getInstance();
        itemCount += prefs.getKeys().length;
      }
      final newHashes = <String, String>{...prevHashes};
      for (final name in changedBoxes) {
        newHashes[name] = currentHashes[name]!;
      }
      if (prefsChanged) {
        newHashes[_prefsHashKey] = currentHashes[_prefsHashKey]!;
      }

      _config = _config.copyWith(
        lastSyncTimestamp: timestamp,
        lastUpload: SyncStatusEntry(
          timestamp: timestamp,
          success: true,
          itemCount: itemCount,
          scope: changedBoxes.toList(),
        ),
        boxHashes: newHashes,
      );
      await CloudSyncConfigStore().save(_config);
      _syncing = false;
      notifyListeners();
      return true;
    } catch (e) {
      final ts = DateTime.now().millisecondsSinceEpoch;
      _config = _config.copyWith(
        lastSyncTimestamp: ts,
        lastUpload: SyncStatusEntry(
          timestamp: ts,
          success: false,
          scope: resolvedBoxes.toList(),
        ),
      );
      await CloudSyncConfigStore().save(_config);
      _lastError = e is DioException ? 'network' : 'unknown:$e';
      _syncing = false;
      notifyListeners();
      return false;
    }
  }

  /// 预览本地与云端最新备份之间的冲突项（按 box 归组）。
  ///
  /// 返回 null 表示未配置 / 无远程备份 / 出错（详见 [lastError]）。
  Future<SyncConflictReport?> previewConflicts(
      {Set<BackupCategory>? scope}) async {
    if (_config.url.isEmpty || _password == null) {
      _lastError = 'no_config';
      return null;
    }
    try {
      final dio = _buildDio(
        username: _config.username,
        password: _password!,
      );
      final files = await _listRemoteBackups(dio);
      if (files.isEmpty) {
        _lastError = 'no_remote_backup';
        return null;
      }
      files.sort((a, b) => b.name.compareTo(a.name));
      final latest = files.first;
      final resp = await dio.get<List<int>>(
        _buildUrl('$_remoteDir/${latest.name}'),
        options: Options(
          responseType: ResponseType.bytes,
          validateStatus: (s) => s != null && s >= 200 && s < 300,
        ),
      );
      final bytes = Uint8List.fromList(resp.data ?? <int>[]);
      final archive = ZipDecoder().decodeBytes(bytes);
      final hiveFile = archive.findFile('hive_boxes.json');
      if (hiveFile == null) return SyncConflictReport(byBox: const {});
      final remoteRaw =
          jsonDecode(utf8.decode(hiveFile.content as List<int>))
              as Map<String, dynamic>;
      final allowedBoxes =
          scope == null ? null : resolveBoxNames(scope);
      final reverseCat = <String, BackupCategory>{};
      for (final e in kBackupCategoryBoxes.entries) {
        for (final b in e.value) {
          reverseCat[b] = e.key;
        }
      }
      final byBox = <String, List<SyncConflict>>{};
      for (final entry in remoteRaw.entries) {
        final name = entry.key;
        if (allowedBoxes != null && !allowedBoxes.contains(name)) continue;
        final data = entry.value;
        if (data is! Map) continue;
        if (!Hive.isBoxOpen(name)) continue;
        final box = Hive.box(name);
        final remoteData = data.map(
          (k, v) => MapEntry(k.toString(), _encodeHiveValue(v)),
        );
        for (final rk in remoteData.keys) {
          if (!box.containsKey(rk)) continue; // 云端独有，非冲突
          final localEnc = _encodeHiveValue(box.get(rk));
          final remoteEnc = remoteData[rk];
          if (!_valuesEqual(localEnc, remoteEnc)) {
            byBox.putIfAbsent(name, () => <SyncConflict>[]).add(SyncConflict(
              boxName: name,
              category: reverseCat[name] ?? BackupCategory.other,
              key: rk,
              localPreview: _preview(localEnc),
              remotePreview: _preview(remoteEnc),
            ));
          }
        }
      }
      return SyncConflictReport(byBox: byBox);
    } catch (e) {
      _lastError = e is DioException ? 'network' : 'unknown:$e';
      return null;
    }
  }

  /// 从 WebDAV 拉最新 ZIP 并恢复到本地。
  ///
  /// [merge] = true 合并（保留本地其它键）；false 覆盖（先清空目标 box 再写入）。
  /// [scope] 非空时只恢复这些分类对应的 box。
  /// [conflictChoices] 非空（冲突解决模式）：键为 box 名，值为「是否采用云端」。
  /// - true：该 box 整体以云端为准（清空后写入云端数据）。
  /// - false：跳过该 box（保留本地）。
  /// - 未列出：按 [merge] 合并（云端键覆盖本地同键，保留本地独有键）。
  Future<bool> pullRemote({
    bool merge = true,
    Set<BackupCategory>? scope,
    Map<String, bool>? conflictChoices,
  }) async {
    if (_syncing) return false;
    if (_config.url.isEmpty || _password == null) {
      _lastError = 'no_config';
      return false;
    }
    _syncing = true;
    _lastError = null;
    notifyListeners();
    final resolvedBoxes =
        scope == null ? kStorageBoxNames.toSet() : resolveBoxNames(scope);
    try {
      final dio = _buildDio(
        username: _config.username,
        password: _password!,
      );
      final files = await _listRemoteBackups(dio);
      if (files.isEmpty) {
        _lastError = 'no_remote_backup';
        _syncing = false;
        notifyListeners();
        return false;
      }
      // 取最新（按文件名降序，timestamp 大的在前）
      files.sort((a, b) => b.name.compareTo(a.name));
      final latest = files.first;
      final resp = await dio.get<List<int>>(
        _buildUrl('$_remoteDir/${latest.name}'),
        options: Options(
          responseType: ResponseType.bytes,
          validateStatus: (s) => s != null && s >= 200 && s < 300,
        ),
      );
      final bytes = Uint8List.fromList(resp.data ?? <int>[]);
      final archive = ZipDecoder().decodeBytes(bytes);
      final result = await _importFromArchive(
        archive,
        merge: merge,
        categories: scope,
        conflictChoices: conflictChoices,
      );

      // 更新上次恢复状态 + 增量哈希基线
      final ts = DateTime.now().millisecondsSinceEpoch;
      final newHashes = <String, String>{...?_config.boxHashes};
      newHashes.addAll(result.remoteHashes);
      _config = _config.copyWith(
        lastSyncTimestamp: ts,
        lastRestore: SyncStatusEntry(
          timestamp: ts,
          success: true,
          itemCount: result.appliedItems,
          scope: resolvedBoxes.toList(),
        ),
        boxHashes: newHashes,
      );
      await CloudSyncConfigStore().save(_config);
      _syncing = false;
      notifyListeners();
      return true;
    } catch (e) {
      final ts = DateTime.now().millisecondsSinceEpoch;
      _config = _config.copyWith(
        lastSyncTimestamp: ts,
        lastRestore: SyncStatusEntry(
          timestamp: ts,
          success: false,
          scope: resolvedBoxes.toList(),
        ),
      );
      await CloudSyncConfigStore().save(_config);
      _lastError = e is DioException ? 'network' : 'unknown:$e';
      _syncing = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> _ensureRemoteDir(Dio dio) async {
    try {
      await dio.request<void>(
        _buildUrl('$_remoteDir/'),
        data: '',
        options: Options(
          method: 'MKCOL',
          validateStatus: (s) =>
              s != null && (s == 201 || s == 405 || s == 409 || s == 301),
        ),
      );
    } catch (_) {
      // 忽略：目录可能已存在或允许后续 PUT 自动创建
    }
  }

  Future<List<_RemoteFile>> _listRemoteBackups(Dio dio) async {
    const propfindBody = '<?xml version="1.0" encoding="utf-8"?>'
        '<D:propfind xmlns:D="DAV:">'
        '<D:prop><D:displayname/><D:resourcetype/></D:prop>'
        '</D:propfind>';
    try {
      final resp = await dio.request<String>(
        _buildUrl('$_remoteDir/'),
        data: propfindBody,
        options: Options(
          method: 'PROPFIND',
          headers: <String, String>{
            'Depth': '1',
            'Content-Type': 'application/xml; charset=utf-8',
          },
          responseType: ResponseType.plain,
          validateStatus: (s) => s != null && s >= 200 && s < 400,
        ),
      );
      return parsePropfind(resp.data ?? '');
    } catch (_) {
      return <_RemoteFile>[];
    }
  }

  /// 解析 PROPFIND Depth:1 multistatus 响应（static 公开供回归测试覆盖）。
  static List<_RemoteFile> parsePropfind(String body) {
    final files = <_RemoteFile>[];
    if (body.isEmpty) return files;
    try {
      final doc = XmlDocument.parse(body);
      for (final response in doc.findAllElements('response',
          namespace: '*')) {
        final hrefElement = response
            .findElements('href', namespace: '*')
            .firstOrNull;
        if (hrefElement == null) continue;
        // ⚠️ XmlElement.value 恒为 null（xml 6.x 只对文本/属性节点提供 value），
        // 元素文本必须用 innerText —— 误用 .value 会导致远端备份列表恒为空。
        final href = hrefElement.innerText.trim();
        if (href.isEmpty) continue;
        // 解析出最后一段文件名
        final decoded = Uri.decodeFull(href);
        String name = decoded;
        if (decoded.endsWith('/')) {
          continue;
        }
        final lastSlash = decoded.lastIndexOf('/');
        if (lastSlash >= 0 && lastSlash < decoded.length - 1) {
          name = decoded.substring(lastSlash + 1);
        }
        final isCollection = response
                .findElements('propstat', namespace: '*')
                .firstOrNull
                ?.findElements('prop', namespace: '*')
                .firstOrNull
                ?.findElements('resourcetype', namespace: '*')
                .firstOrNull
                ?.findElements('collection', namespace: '*')
                .isNotEmpty ??
            false;
        files.add(_RemoteFile(name: name, isCollection: isCollection));
      }
    } catch (_) {
      // XML 解析失败：返回空列表
    }
    return files;
  }

  Future<void> _cleanupOldBackups(Dio dio) async {
    final files = await _listRemoteBackups(dio);
    final backups = files
        .where((f) =>
            !f.isCollection &&
            f.name.startsWith('nexhub-backup-') &&
            f.name.endsWith('.zip'))
        .toList()
      ..sort((a, b) => b.name.compareTo(a.name)); // 新到旧
    for (var i = _maxBackups; i < backups.length; i++) {
      try {
        await dio.delete(
          _buildUrl('$_remoteDir/${backups[i].name}'),
          options: Options(
            validateStatus: (s) => s != null && s >= 200 && s < 300,
          ),
        );
      } catch (_) {
        // 忽略单个删除失败
      }
    }
  }

  /// 导出指定 box 为 ZIP 归档（hive_boxes.json + 可选 preferences.json）。
  Future<Archive> _exportToArchive({
    required Set<String> boxNames,
    required bool includePrefs,
  }) async {
    final archive = Archive();
    final hiveData = <String, dynamic>{};
    for (final name in boxNames) {
      if (Hive.isBoxOpen(name)) {
        final box = Hive.box(name);
        hiveData[name] = box
            .toMap()
            .map((k, v) => MapEntry(k.toString(), _encodeHiveValue(v)));
      }
    }
    final hiveBytes = Uint8List.fromList(utf8.encode(jsonEncode(hiveData)));
    archive.addFile(ArchiveFile(
      'hive_boxes.json',
      hiveBytes.length,
      hiveBytes,
    ));
    // 2. SharedPreferences → JSON（仅当 includePrefs 时包含）
    if (includePrefs) {
      final prefs = await SharedPreferences.getInstance();
      final prefsData = <String, dynamic>{};
      for (final key in prefs.getKeys()) {
        final v = prefs.get(key);
        if (v != null) prefsData[key] = v;
      }
      final prefsBytes = Uint8List.fromList(utf8.encode(jsonEncode(prefsData)));
      archive.addFile(ArchiveFile(
        'preferences.json',
        prefsBytes.length,
        prefsBytes,
      ));
    }
    return archive;
  }

  dynamic _encodeHiveValue(dynamic v) {
    if (v == null) return null;
    if (v is String || v is num || v is bool) return v;
    if (v is List) return v.map(_encodeHiveValue).toList();
    if (v is Map) {
      return v.map((k, v) => MapEntry(k.toString(), _encodeHiveValue(v)));
    }
    // Hive 自定义对象：尝试 toJson
    try {
      final toJson = (v as dynamic).toJson;
      if (toJson != null) return toJson.call();
    } catch (_) {}
    return v.toString();
  }

  /// 从 ZIP 归档恢复到本地。
  ///
  /// 返回写入条数与被应用 box 的远程哈希（用于更新增量基线）。
  Future<_ImportResult> _importFromArchive(
    Archive archive, {
    required bool merge,
    Set<BackupCategory>? categories,
    Map<String, bool>? conflictChoices,
  }) async {
    var appliedItems = 0;
    final remoteHashes = <String, String>{};
    final allowedBoxes =
        categories == null ? null : resolveBoxNames(categories);
    // 1. 合并 / 覆盖 Hive boxes
    final hiveFile = archive.findFile('hive_boxes.json');
    if (hiveFile != null) {
      final content = hiveFile.content as List<int>;
      final raw = jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
      for (final entry in raw.entries) {
        final name = entry.key;
        if (allowedBoxes != null && !allowedBoxes.contains(name)) continue;
        final data = entry.value;
        if (data is! Map) continue;
        if (!Hive.isBoxOpen(name)) continue;
        final choice = conflictChoices?[name];
        final box = Hive.box(name);
        if (choice == false) continue; // 采用本地：跳过该 box
        if (choice == true) {
          // 采用云端：整体以远程覆盖（清空后写入）
          try {
            await box.clear();
          } on Object {}
          for (final kv in data.entries) {
            try {
              await box.put(kv.key, _decodeHiveValue(kv.value));
              appliedItems++;
            } on Object {}
          }
        } else if (!merge) {
          // 覆盖模式：先清空再写入
          try {
            await box.clear();
          } on Object {}
          for (final kv in data.entries) {
            try {
              await box.put(kv.key, _decodeHiveValue(kv.value));
              appliedItems++;
            } on Object {}
          }
        } else {
          // 合并模式：逐键写入（云端键覆盖本地同键）
          for (final kv in data.entries) {
            try {
              await box.put(kv.key, _decodeHiveValue(kv.value));
              appliedItems++;
            } on Object {}
          }
        }
        // 记录该 box 远程哈希（无论采用哪侧，恢复后本地与远程一致）
        remoteHashes[name] = _sha256(jsonEncode(data));
      }
    }
    // 2. 合并 / 覆盖 SharedPreferences
    final prefsFile = archive.findFile('preferences.json');
    if (prefsFile != null) {
      if (categories != null &&
          !categories.contains(BackupCategory.settings)) {
        return _ImportResult(
            appliedItems: appliedItems, remoteHashes: remoteHashes);
      }
      final content = prefsFile.content as List<int>;
      final raw = jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();
      for (final entry in raw.entries) {
        // 跨平台恢复：外来平台的路径型偏好不写入本机（详见
        // storage/platform_path_compat.dart 的「导入其他平台备份打不开」说明）。
        final dynamic v = normalizeImportedPrefValue(entry.key, entry.value);
        if (v == null) continue;
        try {
          if (v is String) {
            await prefs.setString(entry.key, v);
            appliedItems++;
          } else if (v is int) {
            await prefs.setInt(entry.key, v);
            appliedItems++;
          } else if (v is double) {
            await prefs.setDouble(entry.key, v);
            appliedItems++;
          } else if (v is bool) {
            await prefs.setBool(entry.key, v);
            appliedItems++;
          } else if (v is List) {
            await prefs.setStringList(
                entry.key, v.map((e) => e.toString()).toList());
            appliedItems++;
          }
        } on Object {
          // 跳过无法写入的项
        }
      }
      remoteHashes[_prefsHashKey] = _sha256(jsonEncode(raw));
    }
    return _ImportResult(
        appliedItems: appliedItems, remoteHashes: remoteHashes);
  }

  dynamic _decodeHiveValue(dynamic v) {
    if (v == null) return null;
    if (v is String || v is num || v is bool) return v;
    if (v is List) return v.map(_decodeHiveValue).toList();
    if (v is Map) return v.map((k, v) => MapEntry(k, _decodeHiveValue(v)));
    return v;
  }
}
