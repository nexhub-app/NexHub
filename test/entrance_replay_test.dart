/// Entrance 入场动画重播回归测试。
///
/// 回归背景：`_EntranceState._play` 曾声明为 `late final`，切换 tab 触发
/// [replayEntrances] 重播时在 `_handleReplay` 里二次赋值，抛
/// `LateInitializationError: Field '_play' has already been initialized`
/// （每个已挂载的 Entrance 都抛一次，日志成串报错且重播失效）。
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/widgets/app_animations.dart';

void main() {
  testWidgets('replayEntrances 重播不抛 LateInitializationError',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          children: const <Widget>[
            Entrance(onceKey: 'replay_k1', child: SizedBox(width: 40, height: 40)),
            Entrance(child: SizedBox(width: 40, height: 40)),
          ],
        ),
      ),
    ));
    // 首次挂载播放入场动画并落定。
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 模拟切换 tab 重播：此前 _play 为 late final 时，此处对已初始化的
    // _play 二次赋值抛 LateInitializationError。
    replayEntrances();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('onceKey 已播过的 Entrance 重播时恢复动画显示',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Entrance(
          onceKey: 'replay_k2',
          child: const SizedBox(width: 40, height: 40),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // 重播后应重新进入 FadeTransition 动画（而非直接终态子控件）。
    // （FadeTransition 在 MaterialApp 内部也有，限定在 Entrance 子树内查找。）
    replayEntrances();
    await tester.pump(const Duration(milliseconds: 30));
    final Finder fade = find.descendant(
      of: find.byType(Entrance),
      matching: find.byType(FadeTransition),
    );
    expect(fade, findsOneWidget);
    // 动画从 0 重新开始：此刻透明度应仍在上升途中（远小于 1）。
    final FadeTransition fadeWidget = tester.widget<FadeTransition>(fade);
    expect(fadeWidget.opacity.value, lessThan(0.9));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('长列表大 index 不再触发 Interval begin<=1.0 断言',
      (WidgetTester tester) async {
    // 回归背景：交错偏移量曾直接取 index*0.08，列表第 13 条起 animStart>1.0，
    // Interval 的 `assert(begin <= 1.0)` 每帧抛出，日志被刷屏。
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          children: <Widget>[
            for (var i = 0; i < 40; i++)
              Entrance(
                onceKey: 'long_list_$i',
                index: i,
                child: const SizedBox(width: 40, height: 40),
              ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 重播（走 _ctrl.forward(from: 0)，同样会逐帧求值 Interval）也不应抛。
    replayEntrances();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
