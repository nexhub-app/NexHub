/// 桌面卡片与原生之间的唯一通道。
///
/// 只做两件事：
/// 1. `update` —— 把 [HomeWidgetSnapshot] 写入原生键值存储并刷新已添加的卡片；
/// 2. `takeLaunchRoute` —— 取走「用户点了卡片」时带过来的待跳转标记。
///
/// 原生实现：
/// * Android `HomeWidgetBridge.kt`（SharedPreferences + AppWidgetManager）
/// * 鸿蒙 `HomeWidgetPlugin.ets`（preferences + formProvider.updateForm）
///
/// 未实现该通道的平台（Windows/macOS/Linux）静默跳过，外层无感。
library;

import 'package:flutter/services.dart' show MethodChannel, MissingPluginException;

import '../platform/platform_service.dart';
import 'home_widget_data.dart';

class HomeWidgetBridge {
  HomeWidgetBridge._();

  static const MethodChannel _channel = MethodChannel('nexhub/home_widget');

  /// 当前平台是否具备桌面卡片能力。
  static bool get isSupported =>
      PlatformService.instance.isAndroid || PlatformService.instance.isOHOS;

  /// 写入最新快照并请求原生刷新卡片。
  ///
  /// 参数包成 `{data: {...}}`：两个原生实现都按具名参数取值，避免整份 Map
  /// 在跨语言边界上被解成不可预期的结构。
  static Future<void> push(HomeWidgetSnapshot snapshot) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('update', <String, Object?>{
        'data': snapshot.toMap(),
      });
    } on MissingPluginException {
      // 原生未注册（旧安装包）：静默降级，不影响应用。
    } on Object {
      // 写入失败（存储异常 / 系统限制）不向 UI 抛错：卡片只是附属信息。
    }
  }

  /// 取走并清空待跳转标记。
  ///
  /// 返回非空表示本次启动/恢复由用户点击卡片触发，值形如 `continue`。
  static Future<String?> takeLaunchRoute() async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('takeLaunchRoute');
    } on Object {
      return null;
    }
  }
}
