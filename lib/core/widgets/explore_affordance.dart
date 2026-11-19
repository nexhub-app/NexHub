/// 在线列表「发现页可展开」的可发现性与展开指示。
///
/// 书源声明了 exploreUrl 才有选项栏可展开；该判定与指示独立成轻量组件，
/// 避免 UI 集成测试被整棵媒体依赖图牵连。
library;

import 'package:material_ui/material_ui.dart';

import '../models/plugin_config.dart';

/// 书源是否声明了 exploreUrl（有发现页选项栏可展开）。
bool sourceHasExplore(PluginConfig source) {
  final xiaoshuo = source.selectors?['xiaoshuo'];
  if (xiaoshuo is! Map) return false;
  final v = xiaoshuo['exploreUrl'];
  return v is String && v.trim().isNotEmpty;
}

/// 源行尾部的展开指示：折叠态朝下，展开态旋转 180°。
class ExploreChevron extends StatelessWidget {
  final bool expanded;

  const ExploreChevron({super.key, required this.expanded});

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: expanded ? 0.5 : 0,
      duration: const Duration(milliseconds: 180),
      child: Icon(
        Icons.expand_more_rounded,
        size: 20,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
