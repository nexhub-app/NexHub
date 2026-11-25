/// 段尾行内挂件：源自带的「内嵌可点击图标」（legado `<img src="url,{style,click}">`）。
///
/// 源用一张内嵌小图（多为 SVG 段评气泡）挂在段落末尾，点击执行脚本打开
/// 源自带的页面。NexHub 不解析图片本身（Flutter 不解 SVG），改为渲染等价
/// 的内置图标并执行源脚本——视觉统一、无新依赖，点击行为与源一致。
library;

import 'package:flutter/material.dart';

import 'package:nexhub/generated/app_localizations.dart';

import '../../../core/theme/app_tokens.dart';

class NovelInlineActionGlyph extends StatelessWidget {
  const NovelInlineActionGlyph({
    super.key,
    required this.onTap,
    this.icon = Icons.forum_rounded,
    this.compact = true,
  });

  final VoidCallback? onTap;
  final IconData icon;

  /// 紧凑形态（正文行内，16px）；false 时 22px（面板/详情用）。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color fg = scheme.primary;
    final double height = compact ? 16 : 22;
    final double size = compact ? 11 : 14;
    return Semantics(
      button: onTap != null,
      label: AppLocalizations.of(context).novelReviewBubbleLabel(0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: height,
          width: height,
          decoration: BoxDecoration(
            color: fg.withValues(alpha: compact ? 0.10 : 0.16),
            borderRadius: BorderRadius.circular(height / 2),
            border: Border.all(color: fg.withValues(alpha: 0.45), width: 0.8),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: size, color: fg),
        ),
      ),
    );
  }
}

/// 段尾挂件占位宽度（`WidgetSpan` 前置间隔用）。
const double kNovelInlineGlyphGap = AppTokens.spaceXs;
