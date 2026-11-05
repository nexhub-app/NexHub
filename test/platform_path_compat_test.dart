/// 跨平台备份导入的路径兼容层：
/// - 判定「路径属于哪个平台」，外来路径（`content://` / `ohosdoc://` / 盘符 /
///   他平台沙箱）在本机没有对应文件系统后端；
/// - 导入时跳过这些偏好，避免下次启动按错平台挑后端（严重时应用打不开）；
/// - 启动自修复把已经写坏的值拉回本机默认。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/platform/platform_service.dart';
import 'package:nexhub/core/storage/platform_path_compat.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final PlatformService ps = PlatformService.instance;

  /// 断言某个路径形态**只**被 [only] 平台接受，其余平台一律拒绝。
  void expectOnly(String path, AppPlatform only) {
    for (final AppPlatform p in AppPlatform.values) {
      expect(
        isPathSupportedOnPlatform(path, p),
        p == only,
        reason: '$path 在 $p 平台判定错误',
      );
    }
  }

  /// 断言所有平台都接受（形态与平台无关）。
  void expectAll(String path) {
    for (final AppPlatform p in AppPlatform.values) {
      expect(
        isPathSupportedOnPlatform(path, p),
        isTrue,
        reason: '$path 在 $p 平台被误判为外来',
      );
    }
  }

  /// 当前测试宿主「一定不认」的路径（用来构造外来平台值）。
  String foreignPath() => ps.isAndroid
      ? 'ohosdoc:///data/storage/el2/base/haps/entry/files/Download'
      : 'content://com.android.externalstorage.documents/tree/primary%3ADownload';

  test('空路径与无关形态全平台可用', () {
    expectAll('');
    expectAll('   ');
    expectAll('Download/novel');
    expectAll('file:///tmp/x');
    expectAll('/tmp/nexhub');
  });

  test('scheme 型路径只被归属平台接受', () {
    expectOnly(
      'content://com.android.externalstorage.documents/tree/primary%3ADownload',
      AppPlatform.android,
    );
    expectOnly(
      'ohosdoc:///storage/Users/currentUser/Download/com.nexhub.nexhub',
      AppPlatform.ohos,
    );
  });

  test('盘符 / UNC 只被 Windows 接受', () {
    expectOnly(r'C:\Users\me\Downloads', AppPlatform.windows);
    expectOnly('D:/Downloads', AppPlatform.windows);
    expectOnly(r'\\NAS\share\Downloads', AppPlatform.windows);
  });

  test('移动端沙箱前缀只被归属平台接受', () {
    expectOnly('/storage/emulated/0/Download', AppPlatform.android);
    expectOnly('/sdcard/NexHub', AppPlatform.android);
    expectOnly('/data/user/0/com.nexhub.app/files', AppPlatform.android);
    expectOnly(
      '/data/storage/el2/base/haps/entry/files/Download',
      AppPlatform.ohos,
    );
    expectOnly(
      '/var/mobile/Containers/Data/Application/ABC/Documents',
      AppPlatform.ios,
    );
  });

  test('本机判定与平台矩阵一致', () {
    expect(isPathSupportedOnThisPlatform('content://tree/primary'),
        ps.isAndroid);
    expect(isPathSupportedOnThisPlatform('ohosdoc:///data/storage/el2/base'),
        ps.isOHOS);
    expect(isPathSupportedOnThisPlatform(r'C:\Users\me\Downloads'),
        ps.isWindows);
    expect(isPathSupportedOnThisPlatform('/storage/emulated/0/Download'),
        ps.isAndroid);
    expect(isPathSupportedOnThisPlatform('/var/mobile/Containers'),
        ps.isIOS);
  });

  test('导入时跳过外来平台的下载目录设置', () {
    final String raw = jsonEncode(<String, dynamic>{
      'downloadPath': foreignPath(),
      'maxConcurrent': 5,
    });
    expect(normalizeImportedPrefValue('download_settings', raw), isNull);
  });

  test('本平台的下载目录设置原样保留', () {
    final String raw = jsonEncode(<String, dynamic>{
      'downloadPath': '',
      'maxConcurrent': 5,
    });
    expect(normalizeImportedPrefValue('download_settings', raw), raw);
  });

  test('导入时跳过外来平台的截图目录', () {
    expect(normalizeImportedPrefValue('screenshot_custom_dir', foreignPath()),
        isNull);
  });

  test('播放器设置只清空截图路径，其余字段保留', () {
    final String raw = jsonEncode(<String, dynamic>{
      'screenshotSavePath': foreignPath(),
      'hardwareDecode': true,
    });
    final dynamic fixed =
        normalizeImportedPrefValue('player_settings_v1', raw);
    expect(fixed, isA<String>());
    final Map<String, dynamic> map =
        jsonDecode(fixed as String) as Map<String, dynamic>;
    expect(map['screenshotSavePath'], isEmpty);
    expect(map['hardwareDecode'], isTrue);
  });

  test('导入时剔除指向外来平台的下载任务', () {
    final String raw = jsonEncode(<dynamic>[
      <String, dynamic>{'id': 'a', 'localPath': foreignPath()},
      <String, dynamic>{'id': 'b', 'localPath': 'Download/novel/a.txt'},
    ]);
    final dynamic fixed = normalizeImportedPrefValue('download_tasks', raw);
    final List<dynamic> kept = jsonDecode(fixed as String) as List<dynamic>;
    expect(kept, hasLength(1));
    expect((kept.single as Map<String, dynamic>)['id'], 'b');
  });

  test('启动自修复把外来路径拉回默认值', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'download_settings': jsonEncode(<String, dynamic>{
        'downloadPath': foreignPath(),
        'maxConcurrent': 6,
      }),
      'screenshot_custom_dir': foreignPath(),
      'data_export_config': jsonEncode(<String, dynamic>{
        'exportFolder': foreignPath(),
      }),
    });

    await repairImportedPlatformPathsOnStartup();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> download = jsonDecode(
      prefs.getString('download_settings')!,
    ) as Map<String, dynamic>;
    expect(download['downloadPath'], isEmpty);
    // 其它与平台无关的字段必须保留（不能整键丢弃）。
    expect(download['maxConcurrent'], 6);
    expect(prefs.getString('screenshot_custom_dir'), isNull);
    final Map<String, dynamic> export = jsonDecode(
      prefs.getString('data_export_config')!,
    ) as Map<String, dynamic>;
    expect(export['exportFolder'], isEmpty);
  });

  test('启动自修复不动本机自己的路径', () async {
    final String local = ps.isWindows ? r'C:\Users\me\Downloads' : '/tmp/nexhub';
    SharedPreferences.setMockInitialValues(<String, Object>{
      'download_settings': jsonEncode(<String, dynamic>{
        'downloadPath': local,
      }),
    });

    await repairImportedPlatformPathsOnStartup();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> download = jsonDecode(
      prefs.getString('download_settings')!,
    ) as Map<String, dynamic>;
    expect(download['downloadPath'], local);
  });
}
