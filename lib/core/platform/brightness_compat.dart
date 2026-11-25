import 'package:screen_brightness/screen_brightness.dart';

/// 屏幕亮度 API 兼容层。
///
/// 官方 `screen_brightness` 暴露 `setScreenBrightness` / `resetScreenBrightness` /
/// `onScreenBrightnessChanged`（系统级亮度）；鸿蒙适配 fork 改名为
/// `setApplicationScreenBrightness` / `resetApplicationScreenBrightness` /
/// `onApplicationScreenBrightnessChanged`（应用窗口级亮度）。
///
/// 两套依赖的方法名不同，但同一份应用代码需要在官方 SDK 与鸿蒙 SDK 下都能编译，
/// 因此这里用运行时探测：优先应用级（鸿蒙 fork），方法不存在时回退系统级（官方包）。
class BrightnessCompat {
  /// [plugin] 仅供测试注入（生产走默认 `ScreenBrightness()`）。
  BrightnessCompat({Object? plugin}) : _impl = plugin ?? ScreenBrightness();

  final dynamic _impl;

  /// 设置亮度（0..1）。鸿蒙走应用窗口级，其余平台回退系统级；
  /// 平台完全没有该能力时静默忽略（桌面阅读器不因调亮度崩）。
  Future<void> setApplicationScreenBrightness(double value) async {
    if (await _tryInvoke('setApplicationScreenBrightness', <Object?>[value])) {
      return;
    }
    await _tryInvoke('setScreenBrightness', <Object?>[value]);
  }

  /// 恢复系统原亮度。
  Future<void> resetApplicationScreenBrightness() async {
    if (await _tryInvoke('resetApplicationScreenBrightness', const <Object?>[])) {
      return;
    }
    await _tryInvoke('resetScreenBrightness', const <Object?>[]);
  }

  /// 调用插件方法：不存在 / 平台未实现时返回 false（调用方继续回退）。
  Future<bool> _tryInvoke(String name, List<Object?> args) async {
    try {
      final dynamic fn = switch (name) {
        'setApplicationScreenBrightness' =>
          (_impl as dynamic).setApplicationScreenBrightness,
        'setScreenBrightness' => (_impl as dynamic).setScreenBrightness,
        'resetApplicationScreenBrightness' =>
          (_impl as dynamic).resetApplicationScreenBrightness,
        'resetScreenBrightness' => (_impl as dynamic).resetScreenBrightness,
        _ => null,
      };
      if (fn is! Function) return false;
      final Object? r = Function.apply(fn, args);
      if (r is Future) await r;
      return true;
    } on NoSuchMethodError {
      return false;
    } on Object {
      return false;
    }
  }

  /// 当前系统亮度；平台不支持时回落 0.5（不抛）。
  Future<double> get current async {
    try {
      final Object? v = await (_impl as dynamic).current;
      if (v is num) return v.toDouble();
    } on Object {
      // 桌面端 / 无亮度能力设备：静默回落。
    }
    return 0.5;
  }

  /// 亮度变化事件流。
  ///
  /// 桌面端（Windows / Linux / macOS）的官方包既没有应用级也没有系统级的
  /// 亮度流（`screen_brightness_windows` 只实现 set/current），旧实现在回退
  /// 分支上直接抛 `NoSuchMethodError`，阅读器一进就崩。
  /// 这里按「能力探测」处理：两套 API 都没有时返回**空流**，UI 照常工作，
  /// 只是不再跟随系统亮度变化。
  Stream<double> get onApplicationScreenBrightnessChanged {
    final Object? appLevel = _tryGet('onApplicationScreenBrightnessChanged');
    if (appLevel is Stream) return appLevel.cast<double>();
    final Object? systemLevel = _tryGet('onScreenBrightnessChanged');
    if (systemLevel is Stream) return systemLevel.cast<double>();
    return const Stream<double>.empty();
  }

  /// 探测动态属性；不存在（NoSuchMethodError）或异常时返回 null。
  Object? _tryGet(String name) {
    try {
      switch (name) {
        case 'onApplicationScreenBrightnessChanged':
          return (_impl as dynamic).onApplicationScreenBrightnessChanged;
        case 'onScreenBrightnessChanged':
          return (_impl as dynamic).onScreenBrightnessChanged;
        case 'current':
          return (_impl as dynamic).current;
        default:
          return null;
      }
    } on NoSuchMethodError {
      return null;
    } on Object {
      return null;
    }
  }
}
