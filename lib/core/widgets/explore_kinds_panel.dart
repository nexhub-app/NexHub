/// 发现页来源下方的「选项栏」（legado ExploreKind 面板）。
///
/// 书源 exploreUrl 可声明 url/text/button/toggle/select 五类选项，按 6 栅格
/// 的 flex 规则排布（[layoutExploreKindRows] 逐行对齐 legado 算法）：
/// - url：点击进入对应分类；
/// - button：执行 action 脚本；
/// - text：输入框（600ms 防抖后保存并执行 action）；
/// - toggle：点击在 chars 之间轮换（选中值显示在名称左/右侧）；
/// - select：点击弹出选项菜单。
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../models/explore_kind.dart';
import '../theme/app_tokens.dart';

/// 选项栏面板：加载态 / 错误态 / 选项网格。
class ExploreKindsPanel extends StatelessWidget {
  final ExploreKindsResult? result;
  final bool loading;
  final VoidCallback onRefresh;
  final void Function(ExploreKind kind) onOpenUrl;
  final Future<void> Function(ExploreKind kind, String value) onValueChanged;
  final Future<void> Function(ExploreKind kind) onRunAction;

  const ExploreKindsPanel({
    super.key,
    required this.result,
    required this.loading,
    required this.onRefresh,
    required this.onOpenUrl,
    required this.onValueChanged,
    required this.onRunAction,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (result == null && loading) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
            AppTokens.spaceLg, 0, AppTokens.spaceLg, AppTokens.spaceSm),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: AppTokens.spaceSm),
            Text(l10n.loading, style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }

    final res = result;
    if (res == null) return const SizedBox.shrink();
    if (res.error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
            AppTokens.spaceLg, 0, AppTokens.spaceLg, AppTokens.spaceSm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.error_outline_rounded,
                    size: 16, color: scheme.error),
                const SizedBox(width: AppTokens.spaceXs),
                Expanded(
                  child: Text(l10n.loadFailed,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.error)),
                ),
                TextButton(
                  onPressed: loading ? null : onRefresh,
                  child: Text(l10n.retry),
                ),
              ],
            ),
            Text(
              res.error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    if (res.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
            AppTokens.spaceLg, 0, AppTokens.spaceLg, AppTokens.spaceSm),
        child: Text(l10n.bookSourceNoExplore,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant)),
      );
    }

    final rows = layoutExploreKindRows(res.items);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTokens.spaceLg, 0, AppTokens.spaceLg, AppTokens.spaceSm),
      child: Column(
        children: <Widget>[
          for (var r = 0; r < rows.length; r++) ...<Widget>[
            if (r > 0) const SizedBox(height: AppTokens.spaceSm),
            _buildRow(context, rows[r]),
          ],
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, List<ExploreKindRowItem> row) {
    final totalSpan =
        row.fold<int>(0, (sum, e) => sum + e.span).clamp(0, 6).toInt();
    final trailing = 6 - totalSpan;
    return Row(
      children: <Widget>[
        for (var i = 0; i < row.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: AppTokens.spaceSm),
          Expanded(flex: row[i].span, child: _buildTile(context, row[i].item)),
        ],
        if (trailing > 0) ...<Widget>[
          const SizedBox(width: AppTokens.spaceSm),
          Expanded(flex: trailing, child: const SizedBox.shrink()),
        ],
      ],
    );
  }

  Widget _buildTile(BuildContext context, ExploreKindItem item) {
    final kind = item.kind;
    final scheme = Theme.of(context).colorScheme;
    final error = _kindError(item);
    if (error != null) {
      return _shell(
        context,
        onTap: () => _showErrorDialog(context, error),
        child: _label(context, item.displayName,
            color: scheme.error, icon: Icons.error_outline_rounded),
      );
    }
    switch (kind.recognizedType) {
      case ExploreKindType.text:
        return _ExploreKindTextTile(
          key: ValueKey<String>('kind-text:${kind.title}'),
          item: item,
          onValueChanged: onValueChanged,
          onRunAction: onRunAction,
        );
      case ExploreKindType.toggle:
        return _shell(
          context,
          onTap: () => unawaited(_cycleToggle(kind, item.value)),
          child: _label(
            context,
            _toggleText(kind, item.displayName, item.value),
            icon: Icons.refresh_rounded,
          ),
        );
      case ExploreKindType.select:
        return _shell(
          context,
          onTap: () => _showSelectSheet(context, item),
          child: _label(
            context,
            '${item.displayName} ${item.value}'.trim(),
            icon: Icons.unfold_more_rounded,
          ),
        );
      case ExploreKindType.button:
        return _shell(
          context,
          onTap: () => onRunAction(kind),
          child: _label(context, item.displayName,
              icon: Icons.keyboard_arrow_right_rounded),
        );
      case ExploreKindType.url:
        return _shell(
          context,
          onTap: kind.isBrowsable ? () => onOpenUrl(kind) : null,
          child: _label(context, item.displayName),
        );
      case null:
        return _shell(
          context,
          onTap: null,
          child: _label(context, item.displayName, staticStyle: true),
        );
    }
  }

  Widget _shell(
    BuildContext context, {
    required Widget child,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 42),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceSm, vertical: 6),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }

  Widget _label(
    BuildContext context,
    String text, {
    IconData? icon,
    Color? color,
    bool staticStyle = false,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color ??
                  (staticStyle ? scheme.primary : scheme.onSurface),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (icon != null) ...<Widget>[
          const SizedBox(width: 2),
          Icon(icon, size: 14, color: scheme.outlineVariant),
        ],
      ],
    );
  }

  static String _toggleText(
      ExploreKind kind, String displayName, String value) {
    final left = kind.style.layoutJustifySelf != 'right';
    return left ? '$value$displayName' : '$displayName$value';
  }

  Future<void> _cycleToggle(ExploreKind kind, String current) async {
    final options = _kindOptions(kind);
    final index = options.indexOf(current);
    final next = options[index < 0 ? 0 : (index + 1) % options.length];
    await onValueChanged(kind, next);
    await onRunAction(kind);
  }

  Future<void> _showSelectSheet(
      BuildContext context, ExploreKindItem item) async {
    final options = _kindOptions(item.kind);
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceLg, vertical: AppTokens.spaceSm),
                child: Text(
                  item.displayName,
                  style: Theme.of(sheetContext).textTheme.titleSmall,
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, i) {
                    final label = options[i];
                    final isSelected = label == item.value;
                    return ListTile(
                      dense: true,
                      title: Text(label.isEmpty ? ' ' : label),
                      trailing: isSelected
                          ? const Icon(Icons.check_rounded, size: 20)
                          : null,
                      onTap: () => Navigator.of(context).pop(label),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || selected == item.value) return;
    await onValueChanged(item.kind, selected);
    await onRunAction(item.kind);
  }

  static List<String> _kindOptions(ExploreKind kind) {
    if (kind.chars.isNotEmpty) return kind.chars;
    return const <String>['chars', 'is null'];
  }

  static String? _kindError(ExploreKindItem item) {
    final title = item.kind.title;
    final url = item.kind.url ?? '';
    final lowerTitle = title.toLowerCase();
    if (lowerTitle.startsWith('error:')) return url.isNotEmpty ? url : title;
    if (url.contains('Exception')) return url;
    if (title.contains('Exception')) return title;
    return null;
  }

  void _showErrorDialog(BuildContext context, String message) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.loadFailed),
        content: SingleChildScrollView(child: SelectableText(message)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(MaterialLocalizations.of(dialogContext).closeButtonLabel),
          ),
        ],
      ),
    );
  }
}

/// 输入框类选项：本地即时回显 + 600ms 防抖写入/执行 action（legado 同款）。
class _ExploreKindTextTile extends StatefulWidget {
  final ExploreKindItem item;
  final Future<void> Function(ExploreKind kind, String value) onValueChanged;
  final Future<void> Function(ExploreKind kind) onRunAction;

  const _ExploreKindTextTile({
    super.key,
    required this.item,
    required this.onValueChanged,
    required this.onRunAction,
  });

  @override
  State<_ExploreKindTextTile> createState() => _ExploreKindTextTileState();
}

class _ExploreKindTextTileState extends State<_ExploreKindTextTile> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.item.value);
  final FocusNode _focus = FocusNode();
  Timer? _debounce;

  @override
  void didUpdateWidget(covariant _ExploreKindTextTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && widget.item.value != _controller.text) {
      _controller.text = widget.item.value;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      unawaited(_commit());
    });
  }

  Future<void> _commit() async {
    final kind = widget.item.kind;
    await widget.onValueChanged(kind, _controller.text);
    if ((kind.action ?? '').trim().isNotEmpty) {
      await widget.onRunAction(kind);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: _controller,
      focusNode: _focus,
      onChanged: _onChanged,
      onSubmitted: (_) {
        _debounce?.cancel();
        unawaited(_commit());
      },
      textInputAction: TextInputAction.done,
      style: Theme.of(context).textTheme.bodySmall,
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.item.displayName,
        hintStyle: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: scheme.onSurfaceVariant),
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceSm, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
