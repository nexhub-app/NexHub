import 'package:material_ui/material_ui.dart';
import '../theme/app_tokens.dart';

/// 带动效的搜索框：聚焦时边框变主色、加粗、底色轻微上染，平滑过渡。
///
/// 内部用 [AnimatedContainer] 提供可动画的描边（[TextField] 自带的
/// focusedBorder 是瞬切不平滑的），配合焦点监听实现「聚焦高亮」灵动反馈。
///
/// 用法：把原本的 `TextField(... InputDecoration(border: OutlineInputBorder()))`
/// 换成 `AppSearchField(controller: ..., hint: ..., onChanged: ...)` 即可。
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    this.controller,
    this.focusNode,
    this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.textInputAction = TextInputAction.search,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hint;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final TextInputAction? textInputAction;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focused = _focus.hasFocus;
    _focus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() => _focused = _focus.hasFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color borderColor = _focused ? scheme.primary : scheme.outline;
    return AnimatedContainer(
      duration: AppTokens.durFast,
      curve: Curves.easeOutCubic,
      // 强制撑满可用宽度：组件自身不带宽度时，在默认 crossAxisAlignment
      // 居中的 Column 里会收缩为内容宽并整框居中，提示文字表现为「居中」
      // （2026-11-21 源管理列表实测）。现有使用点均为有界宽度，不受影响。
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: borderColor, width: _focused ? 2 : 1),
        // 聚焦时整框轻微上染主色，失焦还原，过渡平滑。
        color: _focused
            ? scheme.primary.withValues(alpha: 0.06)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        autofocus: widget.autofocus,
        // 显式锁定对齐：文字水平靠左、垂直居中（双保险，防止任何继承/
        // 主题行为把它变成居中排版）。
        textAlign: TextAlign.start,
        textAlignVertical: TextAlignVertical.center,
        textInputAction: widget.textInputAction,
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: widget.prefixIcon,
          suffixIcon: widget.suffixIcon,
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceSm,
            vertical: AppTokens.spaceXs + 4,
          ),
        ),
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
      ),
    );
  }
}
