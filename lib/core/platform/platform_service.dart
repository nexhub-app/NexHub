/// 平台能力抽象层（规格）。
///
/// 所有平台相关判定（桌面/移动/Web/HarmonyOS NEXT）与未来平台分支统一收敛于此，
/// feature 与 core 业务代码不得直接写 `Platform.isXxx` / `defaultTargetPlatform` 分支。
/// 新增平台（如 HarmonyOS NEXT / Flutter-OH）只改本文件与 `pubspec.yaml` 的
/// `dependency_overrides`，无需散落到各业务模块。
///
/// 两条轴：
/// - 能力轴 [isMobile]：触屏 / 移动系交互（SystemChrome、相册、WebView、震动）。
/// - 形态轴 [isDesktopForm]：窗口 / 鼠标键盘交互（滚动条、阅读器窗口全屏、视频 PiP）。
/// 鸿蒙 PC 属于「移动平台能力 + 桌面交互形态」，两条轴必须分开判断。
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException;

/// 应用运行平台枚举。
enum AppPlatform {
  android,
  ios,
  windows,
  macos,
  linux,
  web,
  ohos,
}

/// 平台能力查询（单例）。
///
/// 所有判定均以 [kIsWeb] 优先守卫，避免 Web 平台访问 `dart:io` 的 [Platform] 抛错。
class PlatformService {
  PlatformService._();

  /// 单例。
  ///
  /// 不再是 const：新增了启动期写入的 [_ohosDeviceType]。
  static final PlatformService instance = PlatformService._();

  static const MethodChannel _channel = MethodChannel('nexhub/device_form');

  /// 鸿蒙设备形态（`deviceInfo.deviceType`）：`phone` / `tablet` / `2in1` / ...
  ///
  /// null = 未初始化或获取失败，此时 [isOHOSPC]/[isOHOSTablet] 为 false、按手机形态回退。
  String? _ohosDeviceType;

  /// 启动期读取鸿蒙设备形态；非鸿蒙立即返回。
  ///
  /// Dart 入口可能略早于应用级插件注册，`MissingPluginException` 时短暂重试；
  /// 其他异常（通道未实现 / 平台拒绝）直接放弃，按手机回退，不阻塞启动。
  Future<void> initializeFormFactor() async {
    if (!isOHOS) return;
    for (int i = 0; i < 3 && _ohosDeviceType == null; i++) {
      try {
        _ohosDeviceType =
            await _channel.invokeMethod<String>('getDeviceType');
        return;
      } on MissingPluginException {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      } on Object {
        return;
      }
    }
  }

  /// 是否为 Web（[Platform] 不可用）。
  bool get isWeb => kIsWeb;

  /// 是否为 Windows 桌面。
  bool get isWindows => !kIsWeb && Platform.isWindows;

  /// 是否为 Android。
  bool get isAndroid => !kIsWeb && Platform.isAndroid;

  /// 是否为 iOS。
  bool get isIOS => !kIsWeb && Platform.isIOS;

  /// 是否为 macOS。
  bool get isMacOS => !kIsWeb && Platform.isMacOS;

  /// 是否为 Linux。
  bool get isLinux => !kIsWeb && Platform.isLinux;

  /// 是否为 HarmonyOS NEXT（Flutter-OH）。
  ///
  /// 鸿蒙 Flutter fork 的 `Platform.operatingSystem` 返回 `'ohos'`。
  /// Web 平台访问 `Platform` 会抛错，故以 [kIsWeb] 守卫。
  bool get isOHOS => !kIsWeb && Platform.operatingSystem == 'ohos';

  /// 是否为鸿蒙 PC（2in1）。
  ///
  /// 只有启动期成功读到 `deviceType == '2in1'` 才为 true；未知一律按手机回退。
  bool get isOHOSPC => isOHOS && _ohosDeviceType == '2in1';

  /// 是否为鸿蒙平板（MatePad 等原生平板设备）。
  ///
  /// 只有启动期成功读到 `deviceType == 'tablet'` 才为 true；未知一律按手机回退。
  /// 平板仍属移动能力轴（触屏 / SystemChrome），宽屏布局由响应式断点负责。
  bool get isOHOSTablet => isOHOS && _ohosDeviceType == 'tablet';

  /// 是否为鸿蒙手机 / 平板。
  bool get isOHOSPhone => isOHOS && !isOHOSPC;

  /// 能力轴：触屏 / 移动系交互（相册、WebView、震动、移动端手势等）。
  ///
  /// 鸿蒙 PC 不在此列：它需要桌面形态的窗口与滚动行为，但仍是鸿蒙平台
  /// （平台级分支继续用 [isOHOS]）。
  bool get isMobile => isAndroid || isIOS || isOHOSPhone;

  /// 当前平台枚举（用于 UI 自适应与路由决策）。
  AppPlatform get current {
    if (isWeb) return AppPlatform.web;
    if (isOHOS) return AppPlatform.ohos;
    if (isWindows) return AppPlatform.windows;
    if (isAndroid) return AppPlatform.android;
    if (isIOS) return AppPlatform.ios;
    if (isMacOS) return AppPlatform.macos;
    return AppPlatform.linux;
  }

  /// 形态轴：传统桌面窗口（窗口管理 / 滚动条 / 悬浮窗）。
  bool get isDesktop => isWindows || isMacOS || isLinux;

  /// 形态轴（含鸿蒙 PC）：桌面式交互（滚动条、鼠标键盘、阅读器窗口全屏）。
  bool get isDesktopForm => isDesktop || isOHOSPC;
}
