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

  /// 当前测试宿主「一定不认」的路径（用来构造外来平台值）。
  String foreignPath() => ps.isAndroid
      ? 'ohosdoc:///data/storage/el2/base/haps/entry/files/Download'
      : 'content://com.android.externalstorage.documents/tree/primary%3ADownload';

  test('空路径与相对路径不判为外来', () {
    expect(isPathSupportedOnThisPlatform(''), isTrue);
    expect(isPathSupportedOnThisPlatform('   '), isTrue);
    expect(isPathSupportedOnThisPlatform('Download/novel'), isTrue);
  });

  test('带 scheme 的路径按归属平台判定', () {
    expect(
      isPathSupportedOnThisPlatform('content://tree/primary'),
      ps.isAndroid,
    );
    expect(
      isPathSupportedOnThisPlatform('ohosdoc:///data/storage/el2/base'),
      ps.isOHOS,
    );
  });

  test('盘符与已知沙箱前缀按归属平台判定', () {
    expect(
      isPathSupportedOnThisPlatform(r'C:\Users\me\Downloads'),
      ps.isWindows,
    );
    expect(
      isPathSupportedOnThisPlatform('D:/Downloads'),
      ps.isWindows,
    );
    expect(
      isPathSupportedOnThisPlatform('/storage/emulated/0/Download'),
      ps.isAndroid,
    );
    expect(
      isPathSupportedOnThisPlatform('/data/storage/el2/base/files'),
      ps.isOHOS,
    );
    expect(
      isPathSupportedOnThisPlatform('/var/mobile/Containers/Data/Application'),
      ps.isIOS,
    );
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
