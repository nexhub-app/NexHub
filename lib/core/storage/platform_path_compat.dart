/// 备份跨平台迁移的路径兼容层。
///
/// 背景：备份 bundle 里的「路径型配置」是**平台绑定**的——Android 的下载目录是
/// `content://` SAF 树 URI，鸿蒙是 `ohosdoc://`，Windows 是盘符路径。把这些值
/// 原样搬到另一平台，启动期会按**本机平台**去挑文件系统后端：
/// 鸿蒙上读到 `content://` 会构造 `SafFileSystem`（`saf` 插件的原生通道在鸿蒙
/// 不存在 → `MissingPluginException`），异常一路冒到 splash 初始化 → 应用停在
/// 「加载失败」页且重试无效，用户表现为**导入其他平台备份后打不开**。
///
/// 两条防线都由本模块提供：
/// 1. 导入过滤 [normalizeImportedPrefValue]：外来平台的路径型偏好不写入本机；
/// 2. 启动自修复 [repairImportedPlatformPathsOnStartup]：已经写坏的历史数据
///    （含旧版本导入的）在下次启动时拉回本机默认值。
///
/// 判定只针对**能确定归属**的路径形态（scheme / 盘符 / 已知沙箱前缀），
/// 本机自己设置的普通路径一律不动（移动硬盘拔掉等临时不可用不算外来）。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../platform/ohos_public_storage.dart' show kOhosDocScheme;
import '../platform/platform_service.dart';
import '../utils/app_log.dart';

/// 下载设置（`DownloadSettingsStore` 的键，内含 `downloadPath`）。
const String _kDownloadSettingsKey = 'download_settings';

/// 数据导入/导出配置（`DataExportConfigStore` 的键，内含 `exportFolder`）。
const String _kDataExportConfigKey = 'data_export_config';

/// 播放器截图目录（Android / 桌面选过自定义目录时存在）。
const String _kScreenshotDirKey = 'screenshot_custom_dir';

/// 播放器总设置（内含 `screenshotSavePath`）。
const String _kPlayerSettingsKey = 'player_settings_v1';

/// 下载任务整列表（历史实现存在偏好里，内含逐任务 `localPath`）。
const String _kDownloadTasksKey = 'download_tasks';

/// 该路径在本机是否**能按本平台的方式打开**。
///
/// 判为 false 的只有「明确属于其他平台」的形态：
/// - `content://`：Android SAF 树 URI；
/// - `ohosdoc://`：鸿蒙公共目录编码路径；
/// - 盘符 / UNC：Windows；
/// - `/storage/`、`/sdcard/`、`/data/user/`、`/data/data/`：Android；
/// - `/data/storage/`：鸿蒙沙箱；
/// - `/var/mobile/`、`/var/containers/`：iOS 沙箱。
///
/// 其余（空、相对路径、无法归类的绝对路径）返回 true —— 交给各平台自己的
/// 可用性判断，不做跨平台臆测。
bool isPathSupportedOnThisPlatform(String path) {
  final String p = path.trim();
  if (p.isEmpty) return true;
  final PlatformService ps = PlatformService.instance;

  if (p.startsWith('content://')) return ps.isAndroid;
  if (p.startsWith(kOhosDocScheme)) return ps.isOHOS;
  if (p.startsWith('file://')) return true; // file URI 与平台无关
  if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(p) || p.startsWith(r'\\')) {
    return ps.isWindows;
  }
  if (p.startsWith('/storage/') ||
      p.startsWith('/sdcard/') ||
      p.startsWith('/mnt/sdcard') ||
      p.startsWith('/data/user/') ||
      p.startsWith('/data/data/')) {
    return ps.isAndroid;
  }
  if (p.startsWith('/data/storage/')) return ps.isOHOS;
  if (p.startsWith('/var/mobile/') ||
      p.startsWith('/private/var/mobile/') ||
      p.startsWith('/var/containers/')) {
    return ps.isIOS;
  }
  return true;
}

/// 把备份里的单个偏好值适配到本机。
///
/// 返回 `null` 表示**跳过该键**（保留本机现值）：宁可少恢复一项设置，也不能
/// 让外来路径把本机拖进「按错平台初始化」的坑。返回值与入参相同表示无需改动。
dynamic normalizeImportedPrefValue(String key, dynamic value) {
  if (value is! String || value.isEmpty) return value;
  try {
    switch (key) {
      case _kDownloadSettingsKey:
        final Object? path = _jsonField(value, 'downloadPath');
        if (path is String && !isPathSupportedOnThisPlatform(path)) {
          AppLog.instance.w('[备份导入] 跳过外来平台的下载目录设置: $path');
          return null;
        }
        return value;
      case _kDataExportConfigKey:
        final Object? folder = _jsonField(value, 'exportFolder');
        if (folder is String && folder.isNotEmpty &&
            !isPathSupportedOnThisPlatform(folder)) {
          AppLog.instance.w('[备份导入] 跳过外来平台的导出目录设置: $folder');
          return null;
        }
        return value;
      case _kScreenshotDirKey:
        if (!isPathSupportedOnThisPlatform(value)) {
          AppLog.instance.w('[备份导入] 跳过外来平台的截图目录设置: $value');
          return null;
        }
        return value;
      case _kPlayerSettingsKey:
        // 播放器设置里只有截图目录与平台绑定，其余（画质 / 弹幕 / 倍速）通用于
        // 全平台：整键丢弃会连带丢一堆偏好，改为只清空该字段。
        final Object? shot = _jsonField(value, 'screenshotSavePath');
        if (shot is String &&
            shot.isNotEmpty &&
            !isPathSupportedOnThisPlatform(shot)) {
          return _rewriteJsonField(value, 'screenshotSavePath', '');
        }
        return value;
      case _kDownloadTasksKey:
        return _filterForeignDownloadTasks(value);
      default:
        return value;
    }
  } on Object catch (e) {
    AppLog.instance.w('[备份导入] 适配偏好 "$key" 失败（按原值写入）: $e');
    return value;
  }
}

/// 启动自修复：把「外来平台路径」拉回本机默认值。
///
/// 覆盖旧版本已经导入过的坏数据（用户升级到带本修复的版本后首次启动即恢复，
/// 无需清数据）。只处理**明确外来**的路径，本机正常配置不受影响。
Future<void> repairImportedPlatformPathsOnStartup() async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  try {
    // 1. 下载目录：清空字段 → 由平台默认目录接管（保留并发数等其它设置）。
    final String? downloadRaw = prefs.getString(_kDownloadSettingsKey);
    if (downloadRaw != null && downloadRaw.isNotEmpty) {
      final Object? path = _jsonField(downloadRaw, 'downloadPath');
      if (path is String &&
          path.isNotEmpty &&
          !isPathSupportedOnThisPlatform(path)) {
        final String fixed =
            _rewriteJsonField(downloadRaw, 'downloadPath', '') ?? '';
        if (fixed.isNotEmpty) {
          await prefs.setString(_kDownloadSettingsKey, fixed);
        }
        AppLog.instance
            .w('[启动自修复] 下载目录 "$path" 不属于本平台，已重置为默认目录');
      }
    }

    // 2. 导出目录。
    final String? exportRaw = prefs.getString(_kDataExportConfigKey);
    if (exportRaw != null && exportRaw.isNotEmpty) {
      final Object? folder = _jsonField(exportRaw, 'exportFolder');
      if (folder is String &&
          folder.isNotEmpty &&
          !isPathSupportedOnThisPlatform(folder)) {
        final String fixed =
            _rewriteJsonField(exportRaw, 'exportFolder', '') ?? '';
        if (fixed.isNotEmpty) {
          await prefs.setString(_kDataExportConfigKey, fixed);
        }
        AppLog.instance
            .w('[启动自修复] 导出目录 "$folder" 不属于本平台，已重置为默认目录');
      }
    }

    // 3. 截图目录：直接删键（未设置即走默认目录）。
    final String? shotDir = prefs.getString(_kScreenshotDirKey);
    if (shotDir != null &&
        shotDir.isNotEmpty &&
        !isPathSupportedOnThisPlatform(shotDir)) {
      await prefs.remove(_kScreenshotDirKey);
      AppLog.instance.w('[启动自修复] 移除外来平台的截图目录: $shotDir');
    }

    // 4. 播放器设置里的截图保存路径。
    final String? playerRaw = prefs.getString(_kPlayerSettingsKey);
    if (playerRaw != null && playerRaw.isNotEmpty) {
      final Object? shot = _jsonField(playerRaw, 'screenshotSavePath');
      if (shot is String &&
          shot.isNotEmpty &&
          !isPathSupportedOnThisPlatform(shot)) {
        final String fixed =
            _rewriteJsonField(playerRaw, 'screenshotSavePath', '') ?? '';
        if (fixed.isNotEmpty) {
          await prefs.setString(_kPlayerSettingsKey, fixed);
        }
        AppLog.instance.w('[启动自修复] 清空外来平台的截图保存路径: $shot');
      }
    }

    // 5. 下载任务：剔除指向外来平台的条目（本地根本不存在那些文件）。
    final String? tasksRaw = prefs.getString(_kDownloadTasksKey);
    if (tasksRaw != null && tasksRaw.isNotEmpty) {
      final String? filtered = _filterForeignDownloadTasks(tasksRaw);
      if (filtered != null && filtered != tasksRaw) {
        await prefs.setString(_kDownloadTasksKey, filtered);
      }
    }
  } on Object catch (e) {
    AppLog.instance.w('[启动自修复] 检查外来平台路径失败（忽略）: $e');
  }
}

// ── JSON 辅助 ────────────────────────────────────────────────────────────

/// 读取 JSON 字符串对象的某字段；解析失败返回 null。
Object? _jsonField(String raw, String field) {
  final Object? decoded = jsonDecode(raw);
  if (decoded is Map) return decoded[field];
  return null;
}

/// 重写 JSON 字符串对象的某字段（其余字段原样保留）；解析失败返回 null。
String? _rewriteJsonField(String raw, String field, Object? value) {
  final Object? decoded = jsonDecode(raw);
  if (decoded is! Map) return null;
  final Map<String, dynamic> out = <String, dynamic>{
    for (final MapEntry<Object?, Object?> e in decoded.entries)
      e.key.toString(): e.value,
  };
  out[field] = value;
  return jsonEncode(out);
}

/// 过滤下载任务列表里 `localPath` 指向外来平台的任务。
///
/// 返回 null 表示无需改动（列表为空 / 解析失败 / 无外来条目）。
String? _filterForeignDownloadTasks(String raw) {
  final Object? decoded = jsonDecode(raw);
  if (decoded is! List) return null;
  final List<dynamic> kept = <dynamic>[];
  var dropped = 0;
  for (final dynamic item in decoded) {
    if (item is Map) {
      final Object? path = item['localPath'];
      if (path is String &&
          path.isNotEmpty &&
          !isPathSupportedOnThisPlatform(path)) {
        dropped++;
        continue;
      }
    }
    kept.add(item);
  }
  if (dropped == 0) return null;
  AppLog.instance.w('[备份导入] 剔除 $dropped 条指向外来平台的下载任务');
  return jsonEncode(kept);
}
