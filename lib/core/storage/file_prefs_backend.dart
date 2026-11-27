/// 基于独立 JSON 文件的持久化后端（[PrefsBackend] 实现）。
///
/// 用途：单键数据量大的场景（如浏览历史整包 JSON，可达数百 KB）。
/// shared_preferences 底层是「轻量级偏好存储」，对大字符串值的落盘
/// 可靠性/容量在部分平台（鸿蒙 dataPreferences）不受保证且失败静默；
/// 文件直写没有此约束，也便于用户侧直接查看/备份。
///
/// 原子性：先写 `<key>.json.tmp` 再改名覆盖，写一半被杀不会留下损坏数据。
/// 备份：覆盖前把当前主文件复制为 `<key>.json.bak`（上一成功版本）；
/// 主文件读失败时自动回退备份，避免把「读失败」当成「无数据」后又被
/// 空列表覆盖（收藏/历史重启丢失的典型链条）。
/// 并发：同一键的写入串行执行，避免共用临时文件互相踩（见 [set]）。
/// 错误策略：不存在返回 null；主文件读失败回退备份，双失败抛异常；
/// 写失败向上抛出由调用方记录。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../comic/models/reader_preferences.dart' show PrefsBackend;
import '../utils/app_log.dart';

class FilePrefsBackend implements PrefsBackend {
  FilePrefsBackend({String? dirName}) : _dirName = dirName ?? 'prefs_files';

  final String _dirName;

  Directory? _cachedDir;

  /// 每个键的写入队列（见 [set]）。
  final Map<String, Future<void>> _writeQueues = {};

  Future<Directory> _dir() async {
    final cached = _cachedDir;
    if (cached != null) return cached;
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, _dirName));
    await dir.create(recursive: true);
    _cachedDir = dir;
    return dir;
  }

  /// 键名转安全文件名（`history_v1` 等本就安全，此处兜底特殊字符）。
  static String _safeName(String key) =>
      key.replaceAll(RegExp(r'[^\w.-]'), '_');

  Future<File> _fileFor(String key) async {
    final dir = await _dir();
    return File(p.join(dir.path, '${_safeName(key)}.json'));
  }

  /// 上一成功版本的备份文件（覆盖前留存，供读失败回退）。
  Future<File> _backupFor(String key) async {
    final dir = await _dir();
    return File(p.join(dir.path, '${_safeName(key)}.json.bak'));
  }

  @override
  Future<String?> get(String key) async {
    final File file;
    try {
      file = await _fileFor(key);
      if (!await file.exists()) return null;
    } on Object catch (e) {
      AppLog.instance.e('文件偏好目录访问失败（$key）: $e');
      rethrow;
    }
    try {
      return await file.readAsString();
    } on Object catch (e) {
      // 主文件存在但读失败（落盘静默失败留下的损坏文件等）：
      // 回退上一成功版本，绝不把「读失败」当成「无数据」。
      AppLog.instance.w('文件偏好主文件读取失败，尝试回退备份（$key）: $e');
      try {
        final bak = await _backupFor(key);
        if (!await bak.exists()) throw StateError('备份文件不存在');
        final text = await bak.readAsString();
        AppLog.instance
            .w('文件偏好已回退到备份（$key，${text.length} 字节），下次写入将重建主文件');
        return text;
      } on Object catch (e2) {
        AppLog.instance.e('文件偏好主文件与备份均读取失败（$key）: $e2');
        rethrow;
      }
    }
  }

  /// 同一键的写入必须串行：并发写共用 `<key>.json.tmp`，交错时先完成者
  /// 会把 tmp 改名走，后完成者 rename 失败且兜底清理会删到已不存在的 tmp；
  /// 串行还保证后调用的快照最后落盘，不会被更旧的快照覆盖。
  @override
  Future<void> set(String key, String value) {
    final prev = _writeQueues[key] ?? Future<void>.value();
    final next = prev.then(
      (_) => _write(key, value),
      // 前一次写入失败不应阻塞后续写入。
      onError: (Object _) => _write(key, value),
    );
    _writeQueues[key] = next;
    return next;
  }

  Future<void> _write(String key, String value) async {
    final file = await _fileFor(key);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(value, flush: true);
    // rename 前取长度作为写后校验基准（rename 后 tmp 已不存在）。
    final int expected = await tmp.length();
    try {
      // 覆盖前把当前主文件留存为备份：若新内容后续损坏（读失败），
      // 仍是可回退的上一成功版本。首次写入没有旧版本，直接复制 tmp
      // 做双份落盘——两份独立写入同时损坏的概率远低于单份。
      if (await file.exists()) {
        await file.copy('${file.path}.bak');
      } else {
        await tmp.copy('${file.path}.bak');
      }
      await tmp.rename(file.path);
    } on Object {
      // 跨设备/占用导致改名失败时退化为直接覆盖。
      await file.writeAsString(value, flush: true);
      try {
        if (await tmp.exists()) await tmp.delete();
      } on Object catch (e) {
        // 数据已落盘，临时文件清不掉不值得让写入失败。
        AppLog.instance.w('文件偏好($key) 清理临时文件失败: $e');
      }
      return;
    }
    // 写后校验：rename 成功但长度不符说明落盘未完整生效（部分 ROM
    // 落盘不可靠），以失败上报让调用方记录——此时主文件可能已损坏，
    // 但备份仍是上一成功版本，下次读取可回退。
    final int actual = await file.length();
    if (actual != expected) {
      throw StateError(
          '文件偏好($key) 写后校验失败：期望 $expected 字节，实际 $actual 字节');
    }
  }
}
