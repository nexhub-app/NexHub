/// 在线列表「发现页可展开」指示：
/// - 声明了 exploreUrl 的书源判定为可展开，未声明（或空白）不可展开；
/// - 展开指示随状态旋转（折叠 0 圈，展开 0.5 圈）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/core/widgets/explore_affordance.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';

PluginConfig _source(String name, {String? exploreUrl}) {
  return ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(<String, dynamic>{
    'bookSourceName': name,
    'bookSourceUrl': 'https://${name.hashCode}.test',
    'bookSourceType': 0,
    'enabled': true,
    if (exploreUrl != null) 'exploreUrl': exploreUrl,
  }));
}

void main() {
  test('声明了 exploreUrl 的源可展开，未声明/空白不可展开', () {
    expect(sourceHasExplore(_source('可展开', exploreUrl: '分类::/c')), isTrue);
    expect(sourceHasExplore(_source('无发现页')), isFalse);
    expect(sourceHasExplore(_source('空白', exploreUrl: '   ')), isFalse);
  });

  testWidgets('展开指示随状态旋转', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ExploreChevron(expanded: false)),
    ));
    expect(
      tester
          .widget<AnimatedRotation>(find.byType(AnimatedRotation))
          .turns,
      0.0,
    );

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ExploreChevron(expanded: true)),
    ));
    expect(
      tester
          .widget<AnimatedRotation>(find.byType(AnimatedRotation))
          .turns,
      0.5,
    );
  });
}
