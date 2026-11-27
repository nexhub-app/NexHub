import 'package:material_ui/material_ui.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'app_animations.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../../core/theme/app_tokens.dart';
import '../models/episode.dart';

/// 显示章节目录底部面板，返回选中的章节索引；取消返回 null。
///
/// 增强功能（向后兼容漫画调用）：
/// - [enableSearch]：章节标题搜索，支持正则（[regexSearch] 切换）。
/// - [bookmarkedIndices]：若提供，则在对应章节显示书签标记，并提供"仅看书签"过滤
/// （书签的"增/删"在小说阅读器底栏完成，此处负责查看/筛选/跳转）。
/// - [sectionOf]：章节 → 分节名（如「第一卷」）。提供时在分节切换处渲染
/// 分节头（本地 TXT 智能分卷分组用）；返回 null 表示该章不归属任何分节。
/// - 定位当前 / 置顶 / 置底 快捷按钮。
Future<int?> showChapterList(
  BuildContext context,
  List<Episode> chapters,
  int currentIndex, {
  bool enableSearch = true,
  Set<int>? bookmarkedIndices,
  String? Function(int chapterIndex)? sectionOf,
}) =>
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ChapterListBody(
        chapters: chapters,
        currentIndex: currentIndex,
        enableSearch: enableSearch,
        bookmarkedIndices: bookmarkedIndices,
        sectionOf: sectionOf,
      ),
    );

class _ChapterListBody extends StatefulWidget {
  final List<Episode> chapters;
  final int currentIndex;
  final bool enableSearch;
  final Set<int>? bookmarkedIndices;
  final String? Function(int chapterIndex)? sectionOf;

  const _ChapterListBody({
    required this.chapters,
    required this.currentIndex,
    this.enableSearch = true,
    this.bookmarkedIndices,
    this.sectionOf,
  });

  @override
  State<_ChapterListBody> createState() => _ChapterListBodyState();
}

/// 当前章在目录视口中的对齐位置：0 = 贴顶，其余给上方留出上下文。
const double _kLocateAlignment = 0.3;

class _ChapterListBodyState extends State<_ChapterListBody> {
  /// 按**条目下标**（而非估算像素偏移）定位：行高可变（带线名/分节头）时
  /// 估算会随章节数累积漂移，下标定位始终精确。
  final ItemScrollController _itemScroll = ItemScrollController();
  final TextEditingController _searchController = TextEditingController();
  bool _regex = false;
  String _query = '';
  bool _bookmarksOnly = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 当前可见（经搜索/书签过滤后）的章节索引列表。
  List<int> get _visibleIndexes {
    final result = <int>[];
    for (int i = 0; i < widget.chapters.length; i++) {
      if (_bookmarksOnly && widget.bookmarkedIndices != null) {
        if (!widget.bookmarkedIndices!.contains(i)) continue;
      }
      if (_query.isNotEmpty) {
        final title = widget.chapters[i].title;
        final matches = _regex
            ? _safeRegexMatch(_query, title)
            : title.toLowerCase().contains(_query.toLowerCase());
        if (!matches) continue;
      }
      result.add(i);
    }
    return result;
  }

  /// 正则匹配；非法正则退化为不区分大小写子串匹配，避免崩溃。
  bool _safeRegexMatch(String pattern, String text) {
    try {
      return RegExp(pattern, caseSensitive: false).hasMatch(text);
    } catch (_) {
      return text.toLowerCase().contains(pattern.toLowerCase());
    }
  }

  /// 当前章在可见列表中的行号；被筛选隐藏（或索引越界）时为 null。
  int? _currentRow(List<int> visible) {
    final int pos = visible.indexOf(widget.currentIndex);
    return pos < 0 ? null : pos;
  }

  /// 定位到当前阅读章。被搜索/书签筛选挡住时先清空筛选再定位，
  /// 避免出现「点了没反应」。
  void _locateCurrent() {
    final int? row = _currentRow(_visibleIndexes);
    if (row == null) {
      if (_query.isEmpty && !_bookmarksOnly) return;
      setState(() {
        _query = '';
        _bookmarksOnly = false;
        _searchController.clear();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final int? restored = _currentRow(_visibleIndexes);
        if (restored != null) _jumpToRow(restored);
      });
      return;
    }
    _jumpToRow(row);
  }

  /// 实际跳转：筛选变化会重建列表状态，可能尚未挂载，重试至挂载（最多 3 帧）。
  void _jumpToRow(int row, {int attempt = 0}) {
    if (!mounted) return;
    if (!_itemScroll.isAttached) {
      if (attempt >= 3) return;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _jumpToRow(row, attempt: attempt + 1),
      );
      return;
    }
    _itemScroll.jumpTo(index: row, alignment: row == 0 ? 0 : _kLocateAlignment);
  }

  void _scrollToTop() {
    if (_itemScroll.isAttached) _itemScroll.jumpTo(index: 0);
  }

  void _scrollToBottom() {
    final int count = _visibleIndexes.length;
    // alignment=1 会被最大滚动距离夹到真正的底部。
    if (_itemScroll.isAttached && count > 0) {
      _itemScroll.jumpTo(index: count - 1, alignment: 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.of(context).size.height * 0.7;
    final visible = _visibleIndexes;
    final int? currentRow = _currentRow(visible);

    return AppSheetBody(
      child: SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceLg, vertical: AppTokens.spaceMd),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.chapterList,
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ),
            if (widget.enableSearch || widget.bookmarkedIndices != null)
              _buildToolbar(l10n),
            const Divider(height: 1),
            Expanded(
              child: visible.isEmpty
                  ? Center(child: Text(l10n.noSearchResults))
                  : ScrollablePositionedList.builder(
                      // 筛选条件变化时重建列表状态：新结果从头展示，
                      // 也避免条目数骤减后停留在越界下标。
                      key: ValueKey<String>('$_query|$_bookmarksOnly|$_regex'),
                      itemCount: visible.length,
                      itemScrollController: _itemScroll,
                      // 首帧即按条目下标精确对位当前章，不再靠行高估算。
                      initialScrollIndex: currentRow ?? 0,
                      initialAlignment: (currentRow ?? 0) == 0
                          ? 0
                          : _kLocateAlignment,
                      itemBuilder: (BuildContext ctx, int i) {
                        final idx = visible[i];
                        final chapter = widget.chapters[idx];
                        final isCurrent = idx == widget.currentIndex;
                        final isBookmarked =
                            widget.bookmarkedIndices?.contains(idx) ?? false;
                        // 分节头：该章分节名与前一个可见章不同（或为首项）
                        // 时渲染。null 分节（未归属任何卷）不渲染头。
                        final sectionOf = widget.sectionOf;
                        String? header;
                        if (sectionOf != null) {
                          final cur = sectionOf(idx);
                          if (cur != null &&
                              (i == 0 || sectionOf(visible[i - 1]) != cur)) {
                            header = cur;
                          }
                        }
                        final tile = ListTile(
                        leading: isCurrent
                            ? Icon(
                                Icons.play_arrow_rounded,
                                color: theme.colorScheme.primary,
                              )
                            : (isBookmarked
                                ? Tooltip(
                                    message: l10n.bookmarkedHint,
                                    child: Icon(
                                      Icons.bookmark_rounded,
                                      size: 18,
                                      color: theme.colorScheme.primary,
                                    ),
                                  )
                                : null),
                          title: Text(
                            chapter.title,
                            style: isCurrent
                                ? TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  )
                                : null,
                          ),
                          subtitle: (chapter.lineName != null &&
                                  chapter.lineName!.isNotEmpty)
                              ? Text(chapter.lineName!)
                              : null,
                          selected: isCurrent,
                          onTap: () => Navigator.of(context).pop(idx),
                        );
                        if (header == null) return tile;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                AppTokens.spaceLg,
                                AppTokens.spaceMd,
                                AppTokens.spaceLg,
                                AppTokens.spaceXs,
                              ),
                              child: Text(
                                header,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            tile,
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildToolbar(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppTokens.spaceLg, AppTokens.spaceSm, AppTokens.spaceLg, AppTokens.spaceXs),
      child: Column(
        children: <Widget>[
          if (widget.enableSearch)
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: l10n.searchChapter,
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                      ),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                IconButton(
                  tooltip: l10n.regexSearch,
                  isSelected: _regex,
                  color: _regex ? Theme.of(context).colorScheme.primary : null,
                  icon: const Icon(Icons.alternate_email_rounded),
                  onPressed: () => setState(() => _regex = !_regex),
                ),
              ],
            ),
          const SizedBox(height: AppTokens.spaceXs),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              ActionChip(
                label: Text(l10n.locateCurrent),
                onPressed: _locateCurrent,
              ),
              ActionChip(
                label: Text(l10n.scrollToTop),
                onPressed: _scrollToTop,
              ),
              ActionChip(
                label: Text(l10n.scrollToBottom),
                onPressed: _scrollToBottom,
              ),
              if (widget.bookmarkedIndices != null)
                FilterChip(
                  label: Text(l10n.filterBookmarked),
                  selected: _bookmarksOnly,
                  onSelected: (bool v) => setState(() => _bookmarksOnly = v),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
