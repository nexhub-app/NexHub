/// 屏幕亮度兼容层：桌面端没有亮度流/亮度能力时不能抛（旧实现一进阅读器就崩）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:nexhub/core/platform/brightness_compat.dart';

/// 模拟桌面端插件：只有 current，没有亮度流与 set/reset。
class _DesktopLikePlugin {
  double get current => 0.42;
}

void main() {
  test('无亮度流时不抛异常，返回空流', () {
    final compat = BrightnessCompat(plugin: _DesktopLikePlugin());
    expect(compat.onApplicationScreenBrightnessChanged, isA<Stream<double>>());
    expect(
      compat.onApplicationScreenBrightnessChanged.listen((_) {}) is Object,
      isTrue,
    );
  });

  test('current 可用时取到值', () async {
    final compat = BrightnessCompat(plugin: _DesktopLikePlugin());
    expect(await compat.current, 0.42);
  });

  test('完全没有亮度能力时 current 回落 0.5，set/reset 静默', () async {
    final compat = BrightnessCompat(plugin: Object());
    expect(await compat.current, 0.5);
    await compat.setApplicationScreenBrightness(0.8);
    await compat.resetApplicationScreenBrightness();
  });
}
