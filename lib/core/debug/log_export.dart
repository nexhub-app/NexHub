/// 日志导出 / 打包工具（发给开发者用）。
///
/// 把日志正文连同环境信息头（应用版本、平台、导出时间）写入临时文件后
/// 交给系统：
/// - 鸿蒙：分享链路在真机不可靠，走 [FileExporter] 系统「另存为」对话框；
/// - 其它平台（Android / iOS / 桌面）：`share_plus` 拉起系统分享面板，
///   用户可直接把日志文件经微信 / QQ 等发给开发者，绕开剪贴板长文本
///   粘贴截断的问题。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../platform/file_exporter.dart';
import '../platform/platform_service.dart';

/// 日志导出（静态工具类）。
class LogExport {
  LogExport._();

  /// 导出日志文件。
  ///
  /// [kind] 用于文件名与信息头区分（如 `crash` / `runtime`），
  /// [content] 为日志正文（不含信息头）。
  ///
  /// 返回是否成功：`true` = 已拉起分享面板或已保存；`false` = 失败或
  /// 用户在「另存为」对话框取消（调用方对 `false` 静默即可）。
  static Future<bool> export({
    required String kind,
    required String content,
  }) async {
    if (content.isEmpty) return false;
    try {
      final String header = await _header(kind);
      final String body = '$header\n$content\n';
      final String fileName =
          'nexhub_${kind}_log_${_stamp(DateTime.now())}.txt';

      // 鸿蒙：系统「另存为」（用户取消返回 null）。
      if (PlatformService.instance.isOHOS) {
        final String? saved = await FileExporter.saveTextFile(
          fileName: fileName,
          content: body,
        );
        return saved != null;
      }

      // 其它平台：临时文件 + 系统分享。文件交给系统后由系统清理，
      // 不主动删除（分享面板可能仍在读取）。
      final Directory dir = await getTemporaryDirectory();
      final File file = File('${dir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsString(body, flush: true);
      await Share.shareXFiles(<XFile>[XFile(file.path)]);
      return true;
    } catch (e) {
      debugPrint('[LogExport] 导出失败: $e');
      return false;
    }
  }

  /// 环境信息头：键值对用英文中性表述，正文原样附后。
  static Future<String> _header(String kind) async {
    String version = 'unknown';
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      version = info.buildNumber.isEmpty
          ? info.version
          : '${info.version}+${info.buildNumber}';
    } catch (_) {
      // 版本获取失败不阻塞导出。
    }
    String platform = 'unknown';
    try {
      final String os = PlatformService.instance.isOHOS
          ? 'ohos'
          : Platform.operatingSystem;
      platform = '$os ${Platform.operatingSystemVersion}';
    } catch (_) {
      // 同上。
    }
    final DateTime now = DateTime.now().toLocal();
    return <String>[
      'NexHub $kind log export',
      'appVersion: $version',
      'platform: $platform',
      'exportedAt: ${now.year}-${_pad(now.month)}-${_pad(now.day)} '
          '${_pad(now.hour)}:${_pad(now.minute)}:${_pad(now.second)}',
      '----------------------------------------',
    ].join('\n');
  }

  /// 文件名安全时间戳：`20261127_212400`。
  static String _stamp(DateTime t) =>
      '${t.year}${_pad(t.month)}${_pad(t.day)}_'
      '${_pad(t.hour)}${_pad(t.minute)}${_pad(t.second)}';

  static String _pad(int v) => v.toString().padLeft(2, '0');
}
