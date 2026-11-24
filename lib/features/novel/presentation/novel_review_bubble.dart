/// 段评气泡：段尾的「有段评」标记（内置样式，不依赖可换肤的气泡包）。
///
/// 设计约束：
/// - **不参与正文排版测量**：滚动模式作为行内 `WidgetSpan`（自由排版，追加
///   不改变行宽约束）；分页模式作为行末 `Positioned` 浮层（分页测量在上游
///   已完成，气泡只做视觉标记，不会引起重排）；
/// - 视觉克制：低饱和描边 + 条数，颜色跟随主题主色；
/// - 点击 = 打开只看本段的段评面板。
library;

import 'package:flutter/material.dart';

import 'package:nexhub/generated/app_localizations.dart';

import '../../../core/theme/app_tokens.dart';

class NovelReviewBubble extends StatelessWidget {
  const NovelReviewBubble({
    super.key,
    required this.count,
    this.onTap,
    this.compact = true,
  });

  /// 本段段评条数（≤0 时不渲染）。
  final int count;

  final VoidCallback? onTap;

  /// 紧凑形态（正文行内用，16px 高）；false 时给面板/详情用（22px）。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color fg = scheme.primary;
    final double height = compact ? 16 : 22;
    final double fontSize = compact ? 10 : 12;
    return Semantics(
      button: onTap != null,
      label: AppLocalizations.of(context).novelReviewBubbleLabel(count),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: height,
          constraints: BoxConstraints(minWidth: height),
          padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 6),
          decoration: BoxDecoration(
            color: fg.withValues(alpha: compact ? 0.10 : 0.16),
            borderRadius: BorderRadius.circular(height / 2),
            border: Border.all(color: fg.withValues(alpha: 0.45), width: 0.8),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.forum_rounded, size: fontSize + 1, color: fg),
              const SizedBox(width: AppTokens.spaceXs / 2),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: fontSize,
                  height: 1.0,
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
