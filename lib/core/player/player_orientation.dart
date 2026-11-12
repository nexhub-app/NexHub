/// 播放器屏幕方向解析（纯函数，便于单元测试）。
library;

import 'package:flutter/services.dart';

import '../settings/player_settings.dart';

/// 根据「锁定方向」设置与视频宽高，解析应锁定的屏幕方向。
///
/// 返回 `null` 表示暂缓：跟随视频模式下宽高尚未就绪，调用方应等待首个
/// 视频尺寸事件后再解析，避免先锁一个方向再切换造成屏幕旋转闪烁。
List<DeviceOrientation>? resolvePlayerOrientations({
  required PlayerLockOrientation mode,
  required bool isPhone,
  int? videoWidth,
  int? videoHeight,
}) {
  // 桌面端（短边 ≥ 600）不锁方向，窗口自由缩放。
  if (!isPhone) return const <DeviceOrientation>[];
  switch (mode) {
    case PlayerLockOrientation.auto:
      return const <DeviceOrientation>[];
    case PlayerLockOrientation.portrait:
      return const <DeviceOrientation>[DeviceOrientation.portraitUp];
    case PlayerLockOrientation.landscape:
      return const <DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ];
    case PlayerLockOrientation.followVideo:
      final int w = videoWidth ?? 0;
      final int h = videoHeight ?? 0;
      if (w <= 0 || h <= 0) return null;
      // 正方形按横屏处理（竖屏锁定会额外浪费上下黑边）。
      return h > w
          ? const <DeviceOrientation>[DeviceOrientation.portraitUp]
          : const <DeviceOrientation>[
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ];
  }
}
