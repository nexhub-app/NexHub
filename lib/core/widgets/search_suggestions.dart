/// Search suggestions shown when the search field is focused and empty.
///
/// Renders two vertically stacked sections: recent search history (chips,
/// clearable via a confirm dialog) and hot search keywords (chips, refreshed
/// from the remote feed). Tapping any chip invokes [onKeywordTap].
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../models/plugin_config.dart';
import '../search/hot_search_keywords.dart';
import '../search/search_history_store.dart';
import '../theme/app_tokens.dart';
import '../utils/app_haptics.dart';
import 'package:nexhub/core/widgets/app_alert_dialog.dart';

/// A focus-triggered suggestions panel with history + hot keywords.
class SearchSuggestions extends StatefulWidget {
  final SourceType sourceType;
  final SearchHistoryStore historyStore;

  /// Called when the user taps a history or hot keyword chip.
  final ValueChanged<String> onKeywordTap;

  const SearchSuggestions({
    super.key,
    required this.sourceType,
    required this.historyStore,
    required this.onKeywordTap,
  });

  @override
  State<SearchSuggestions> createState() => _SearchSuggestionsState();
}

class _SearchSuggestionsState extends State<SearchSuggestions> {
  Future<List<String>>? _historyFuture;
  HotSearchKeywords get _hotKeywords => HotSearchKeywords.instance;

  @override
  void initState() {
    super.initState();
    _historyFuture = widget.historyStore.load();
    _hotKeywords.addListener(_onHotKeywordsChanged);
    unawaited(_hotKeywords.load());
  }

  void _onHotKeywordsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _hotKeywords.removeListener(_onHotKeywordsChanged);
    super.dispose();
  }

  Future<void> _confirmClear() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AppAlertDialog(
        content: Text(l10n.clearSearchHistoryConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.historyStore.clear();
      if (mounted) {
        setState(() {
          _historyFuture = widget.historyStore.load();
        });
      }
    }
  }

  /// 长按历史胶囊：确认后删除该条历史。
  Future<void> _confirmRemoveEntry(String keyword) async {
    // MD3「Thunk」：长按删除搜索历史（破坏性确认）。
    AppHaptics.thunk();
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AppAlertDialog(
        content: Text(l10n.deleteSearchHistoryConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.historyStore.remove(keyword);
      if (mounted) {
        setState(() {
          _historyFuture = widget.historyStore.load();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final TextStyle? titleStyle = theme.textTheme.titleSmall;
    final TextStyle? hintStyle = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceLg,
        vertical: AppTokens.spaceMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // --- Search history section ---
          FutureBuilder<List<String>>(
            future: _historyFuture,
            builder: (BuildContext context, AsyncSnapshot<List<String>> snapshot) {
              final List<String> history = snapshot.data ?? const <String>[];
              final bool loading =
                  snapshot.connectionState != ConnectionState.done;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(l10n.searchHistoryTitle, style: titleStyle),
                      ),
                      if (history.isNotEmpty)
                        TextButton.icon(
                          onPressed: _confirmClear,
                          icon: const Icon(Icons.delete_rounded, size: 18),
                          label: Text(l10n.clearSearchHistory),
                        ),
                    ],
                  ),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
                      child: SizedBox(
                        height: 24,
                        width: 24,
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else if (history.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppTokens.spaceSm,
                      ),
                      child: Text(l10n.noSearchHistory, style: hintStyle),
                    )
                  else
                    _ChipWrap(
                      keywords: history,
                      onTap: widget.onKeywordTap,
                      onLongPress: _confirmRemoveEntry,
                    ),
                ],
              );
            },
          ),
          const Divider(height: AppTokens.spaceLg * 2),
          // --- Hot search section ---
          Text(l10n.hotSearch, style: titleStyle),
          _buildHotKeywords(l10n, hintStyle),
        ],
      ),
    );
  }

  /// 热词区：本地兜底数据就绪前显示加载态；之后同步读仓库，
  /// 远程刷新到达时经监听器自动重建。
  Widget _buildHotKeywords(AppLocalizations l10n, TextStyle? hintStyle) {
    if (!_hotKeywords.bootstrapped) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
        child: SizedBox(
          height: 24,
          width: 24,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    final List<String> keywords = _hotKeywords.forModule(widget.sourceType);
    if (keywords.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
        child: Text(l10n.noHotSearch, style: hintStyle),
      );
    }
    return _ChipWrap(keywords: keywords, onTap: widget.onKeywordTap);
  }
}

class _ChipWrap extends StatelessWidget {
  const _ChipWrap({
    required this.keywords,
    required this.onTap,
    this.onLongPress,
  });

  final List<String> keywords;
  final ValueChanged<String> onTap;

  /// 长按单个胶囊的回调（历史胶囊传删除确认；热搜胶囊不传）。
  final ValueChanged<String>? onLongPress;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
        child: Wrap(
          spacing: AppTokens.spaceSm,
          runSpacing: AppTokens.spaceSm,
          children: keywords
              .map((String k) => GestureDetector(
                    // ActionChip 无 onLongPress 参数；长按语义由外层
                    // GestureDetector 提供（历史胶囊长按=删除确认，
                    // 需按住约半秒不松手、不滑动）。
                    onLongPress:
                        onLongPress == null ? null : () => onLongPress!(k),
                    child: ActionChip(
                      label: Text(k),
                      onPressed: () => onTap(k),
                    ),
                  ))
              .toList(growable: false),
        ),
      );
}
