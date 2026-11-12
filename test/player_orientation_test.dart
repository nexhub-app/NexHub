// player_orientation_test：播放器方向解析纯函数 + 方向设置默认值/序列化。
//
// 完整播放页方向锁定依赖 media_kit 原生库与系统方向调用，测试环境不可用；
// 故将「模式 + 视频宽高 → 应锁方向」抽成纯函数单测，覆盖跟随视频判定与
// 尺寸未就绪时的暂缓语义。
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/player/player_orientation.dart';
import 'package:nexhub/core/settings/player_settings.dart';

void main() {
  group('resolvePlayerOrientations', () {
    const List<DeviceOrientation> landscape = <DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ];

    test('非手机端不锁方向', () {
      for (final PlayerLockOrientation mode in PlayerLockOrientation.values) {
        expect(
          resolvePlayerOrientations(
            mode: mode,
            isPhone: false,
            videoWidth: 1080,
            videoHeight: 1920,
          ),
          isEmpty,
          reason: 'desktop should never lock orientation (mode=$mode)',
        );
      }
    });

    test('auto 不锁方向（跟随系统）', () {
      expect(
        resolvePlayerOrientations(
          mode: PlayerLockOrientation.auto,
          isPhone: true,
          videoWidth: 1080,
          videoHeight: 1920,
        ),
        isEmpty,
      );
    });

    test('portrait 锁竖屏', () {
      expect(
        resolvePlayerOrientations(
          mode: PlayerLockOrientation.portrait,
          isPhone: true,
          videoWidth: 1920,
          videoHeight: 1080,
        ),
        <DeviceOrientation>[DeviceOrientation.portraitUp],
      );
    });

    test('landscape 锁横屏', () {
      expect(
        resolvePlayerOrientations(
          mode: PlayerLockOrientation.landscape,
          isPhone: true,
          videoWidth: 1080,
          videoHeight: 1920,
        ),
        landscape,
      );
    });

    test('followVideo：竖视频锁竖屏', () {
      expect(
        resolvePlayerOrientations(
          mode: PlayerLockOrientation.followVideo,
          isPhone: true,
          videoWidth: 1080,
          videoHeight: 1920,
        ),
        <DeviceOrientation>[DeviceOrientation.portraitUp],
      );
    });

    test('followVideo：横视频锁横屏', () {
      expect(
        resolvePlayerOrientations(
          mode: PlayerLockOrientation.followVideo,
          isPhone: true,
          videoWidth: 1920,
          videoHeight: 1080,
        ),
        landscape,
      );
    });

    test('followVideo：正方形按横屏处理', () {
      expect(
        resolvePlayerOrientations(
          mode: PlayerLockOrientation.followVideo,
          isPhone: true,
          videoWidth: 1080,
          videoHeight: 1080,
        ),
        landscape,
      );
    });

    test('followVideo：宽高未就绪返回 null（暂缓，不锁错方向）', () {
      expect(
        resolvePlayerOrientations(
          mode: PlayerLockOrientation.followVideo,
          isPhone: true,
        ),
        isNull,
      );
      expect(
        resolvePlayerOrientations(
          mode: PlayerLockOrientation.followVideo,
          isPhone: true,
          videoWidth: 0,
          videoHeight: 0,
        ),
        isNull,
      );
    });
  });

  group('PlayerSettings.lockOrientation', () {
    test('默认跟随视频', () {
      expect(
        const PlayerSettings().lockOrientation,
        PlayerLockOrientation.followVideo,
      );
    });

    test('JSON 往返保留跟随视频', () {
      const settings =
          PlayerSettings(lockOrientation: PlayerLockOrientation.followVideo);
      final restored = PlayerSettings.fromJson(settings.toJson());
      expect(restored.lockOrientation, PlayerLockOrientation.followVideo);
    });

    test('缺失 / 非法值回退到跟随视频', () {
      expect(
        PlayerSettings.fromJson(const <String, dynamic>{})
            .lockOrientation,
        PlayerLockOrientation.followVideo,
      );
      expect(
        PlayerSettings.fromJson(<String, dynamic>{
          'lockOrientation': 'not-a-mode',
        }).lockOrientation,
        PlayerLockOrientation.followVideo,
      );
    });
  });
}
