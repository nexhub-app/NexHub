import 'dart:math' as math;
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/widgets/app_animations.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../../../core/models/episode.dart';
import '../../../core/models/novel_block.dart';
import '../../../core/scraper/media_api_service.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/novel/novel_chinese_converter.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/highlight_text.dart' show searchHitSpans;

/// 书内搜索结果项。
class InBookSearchResult {
  final int chapterIndex;
  final String chapterTitle;
  final String snippet;

  /// 命中位置在章内的字符偏移：命中前所有文本块长度累计 + 块内命中下标。
  /// 与阅读器分页偏移同源（`_charOffsetForPage` 口径），跳转时用它
  /// 反查命中所在页，而非只落到章节首页。
  final int charOffset;

  /// 搜索关键词（用于结果列表高亮显示匹配文本）。
  final String keyword;

  /// 正则模式下的已编译表达式（正文/结果高亮用；普通模式为 null）。
  /// 非空时 [keyword] 为正则源文本，高亮按正则匹配而非子串包含。
  final RegExp? regex;

  const InBookSearchResult({
    required this.chapterIndex,
    required this.chapterTitle,
    required this.snippet,
    required this.charOffset,
    required this.keyword,
    this.regex,
  });
}

/// 书内搜索模式。
enum InBookSearchScope {
  /// 仅当前章节。
  currentChapter,
  /// 全书。
  wholeBook,
  /// 当前章及之后。
  fromCurrent,
  /// 自定义起止章。
  range;
}

/// 全书搜索并发拉取数：章节串行逐个 `await` 在千章书上极慢，按小并发
/// 并行拉取（过高并发易触发源限流）。
const int _kSearchConcurrency = 6;

/// 单次搜索结果条数上限：常见词全书命中可能上千条，全部入列会让列表
/// 构建卡顿，截断到该值即停止收集。
const int _kMaxResults = 300;

/// 搜索中止信号（sheet 已关闭 / 发起新搜索时终止进行中的拉取）。
class _SearchAborted implements Exception {
  const _SearchAborted();
}

/// 简易并行 for：按 [concurrency] 并发执行 [task]，任一 task 抛出即整体中止。
Future<void> _parallelFor(
  int concurrency,
  List<int> items,
  Future<void> Function(int) task,
) async {
  if (concurrency < 1) concurrency = 1;
  if (items.isEmpty) return;
  final queue = List<int>.from(items);
  Future<void> worker() async {
    while (queue.isNotEmpty) {
      await task(queue.removeLast());
    }
  }

  final count = concurrency < items.length ? concurrency : items.length;
  await Future.wait(<Future<void>>[for (var i = 0; i < count; i++) worker()]);
}

/// 书内搜索底部抽屉。
///
/// 支持「当前章 / 全书 / 当前章之后 / 起止章」范围切换；可开启正则搜索；
/// 全书搜索按小并发并行拉取 + 章节结果缓存（重复搜索不重抓）；结果**实时**
/// 随章节命中流式插入（非搜完才显示）；搜索中可「暂停 / 继续」。
///
/// [localChapterLoader] 为本地模式的章节正文块按需加载器（参数为章下标，
/// 与 [chapters] 对齐）。非空时跳过网络拉取，直接在本机内容中搜索。
Future<InBookSearchResult?> showNovelInBookSearchSheet({
  required BuildContext context,
  required List<Episode> chapters,
  required int currentChapterIndex,
  required MediaApiService service,
  required PluginConfig? source,
  required String novelId,
  required ChineseConvertMode convertMode,
  Future<List<NovelBlock>> Function(int chapterIndex)? localChapterLoader,
}) {
  return showModalBottomSheet<InBookSearchResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _InBookSearchSheet(
      chapters: chapters,
      currentChapterIndex: currentChapterIndex,
      service: service,
      source: source,
      novelId: novelId,
      convertMode: convertMode,
      localChapterLoader: localChapterLoader,
    ),
  );
}

class _InBookSearchSheet extends StatefulWidget {
  const _InBookSearchSheet({
    required this.chapters,
    required this.currentChapterIndex,
    required this.service,
    required this.source,
    required this.novelId,
    required this.convertMode,
    this.localChapterLoader,
  });

  final List<Episode> chapters;
  final int currentChapterIndex;
  final MediaApiService service;
  final PluginConfig? source;
  final String novelId;

  /// 与阅读器一致的繁简转换模式：正文与关键字均按该模式转换后再匹配，
  /// 保证「屏显简体、原文繁体」时也能用简体关键字搜到（正则模式不转换关键字）。
  final ChineseConvertMode convertMode;

  /// 本地模式的章节正文块按需加载器（参数为章下标，与 [chapters] 对齐）。
  /// 非空时跳过网络拉取，直接在本机内容中搜索（单文件与聚合导入均支持）。
  final Future<List<NovelBlock>> Function(int chapterIndex)? localChapterLoader;

  @override
  State<_InBookSearchSheet> createState() => _InBookSearchSheetState();
}

class _InBookSearchSheetState extends State<_InBookSearchSheet> {
  final TextEditingController _controller = TextEditingController();
  InBookSearchScope _scope = InBookSearchScope.currentChapter;
  List<InBookSearchResult> _results = const <InBookSearchResult>[];
  bool _searching = false;

  /// 已搜索章数 / 总章数（搜索中显示进度）。
  int _searchedCount = 0;
  int _totalCount = 0;

  /// 章节正文缓存（章下标 → 块列表）：sheet 存活期内重复搜索不重抓。
  final Map<int, List<NovelBlock>> _chapterCache = <int, List<NovelBlock>>{};

  /// 搜索代号：发起新搜索时自增，旧搜索的异步回调据此中止。
  int _generation = 0;

  /// 正则模式开关。
  bool _useRegex = false;

  /// 起止章范围（[InBookSearchScope.range] 时生效）。
  int? _rangeStart;
  int? _rangeEnd;

  /// 暂停状态与恢复信号：暂停时 worker 在拉取下一章前挂起，恢复后继续。
  bool _paused = false;
  Completer<void>? _resumeCompleter;

  /// 最近搜索关键词（最新在前，全局共享，最多 10 条）。
  static const String _kHistoryPrefKey = 'novel_inbook_search_history';
  static const int _kHistoryMax = 10;
  List<String> _history = const <String>[];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kHistoryPrefKey);
      if (list != null && list.isNotEmpty && mounted) {
        setState(() => _history = list.take(_kHistoryMax).toList());
      }
    } on Object {
      // 历史读取失败不影响搜索。
    }
  }

  /// 记录一次搜索关键词（去重置顶，超限截尾）并持久化。
  Future<void> _pushHistory(String keyword) async {
    final next = <String>[
      keyword,
      ..._history.where((k) => k != keyword),
    ].take(_kHistoryMax).toList();
    if (mounted) setState(() => _history = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kHistoryPrefKey, next);
    } on Object {
      // 持久化失败只影响下次进入的历史展示。
    }
  }

  Future<void> _clearHistory() async {
    setState(() => _history = const <String>[]);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kHistoryPrefKey, const <String>[]);
    } on Object {
      // 忽略。
    }
  }

  @override
  void dispose() {
    // 恢复挂起的 worker，使其检查 _generation 后退出，避免闭sheet 后悬挂。
    _resumeCompleter?.complete();
    _generation++; // 让进行中的搜索在下一个 await 点退出。
    _controller.dispose();
    super.dispose();
  }

  /// 计算本次搜索的章下标列表（按范围）。
  List<int> _chapterIndicesForScope() {
    final total = widget.chapters.length;
    switch (_scope) {
      case InBookSearchScope.currentChapter:
        return <int>[widget.currentChapterIndex];
      case InBookSearchScope.wholeBook:
        return List<int>.generate(total, (i) => i);
      case InBookSearchScope.fromCurrent:
        return <int>[
          for (var i = widget.currentChapterIndex; i < total; i++) i
        ];
      case InBookSearchScope.range:
        final s = (_rangeStart ?? 1).clamp(1, total) - 1;
        final e = (_rangeEnd ?? total).clamp(1, total) - 1;
        final lo = s.clamp(0, e);
        return <int>[for (var i = lo; i <= e; i++) i];
    }
  }

  Future<void> _search() async {
    final keywordSrc = _controller.text.trim();
    if (keywordSrc.isEmpty) return;
    if (widget.source == null && widget.localChapterLoader == null) return;
    final int gen = ++_generation;
    _paused = false;
    _resumeCompleter = null;

    // 正则模式：编译表达式（非法则中止并提示）；不转换关键字。
    // 普通模式：关键字按阅读器转换模式同步转换，与正文转换后匹配。
    RegExp? regex;
    String pattern;
    if (_useRegex) {
      try {
        regex = RegExp(keywordSrc, caseSensitive: false);
        pattern = keywordSrc;
      } on Object {
        if (mounted) {
          setState(() => _searching = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context).searchRegexInvalid)),
          );
        }
        return;
      }
    } else {
      pattern = convertChinese(keywordSrc, widget.convertMode);
    }
    unawaited(_pushHistory(keywordSrc));

    setState(() {
      _searching = true;
      _results = const <InBookSearchResult>[];
      _searchedCount = 0;
    });

    final chapterIndices = _chapterIndicesForScope();
    _totalCount = chapterIndices.length;

    // 章下标 → 该章命中列表：并行拉取乱序完成，按章序归并保证结果有序。
    final byChapter = <int, List<InBookSearchResult>>{};
    var collected = 0; // 已收集命中总数（达上限即停止收集）

    // 实时刷新结果列表（按章序归并 byChapter）。
    void refreshResults() {
      if (!mounted || gen != _generation) return;
      setState(() {
        _results = <InBookSearchResult>[
          for (final ci in chapterIndices)
            ...byChapter[ci] ?? const <InBookSearchResult>[],
        ];
      });
    }

    try {
      await _parallelFor(_kSearchConcurrency, chapterIndices, (ci) async {
        if (gen != _generation || !mounted) throw const _SearchAborted();
        // 暂停：在拉取下一章前挂起，恢复后继续（保持 _generation 一致性）。
        if (_paused) {
          final c = _resumeCompleter;
          if (c != null) await c.future;
        }
        if (gen != _generation || !mounted) throw const _SearchAborted();
        if (collected >= _kMaxResults) throw const _SearchAborted();
        final chapter = widget.chapters[ci];
        List<NovelBlock>? blocks = _chapterCache[ci];
        if (blocks == null) {
          final loader = widget.localChapterLoader;
          if (loader != null) {
            // 本地模式（单文件 / 聚合导入）：按需加载章节正文块，跳过网络拉取。
            try {
              blocks = await loader(ci);
              _chapterCache[ci] = blocks;
            } on Object {
              // 跳过加载失败的章节。
              return;
            }
          } else {
            try {
              final nextChapterUrl = ci + 1 < widget.chapters.length
                  ? widget.chapters[ci + 1].url
                  : null;
              blocks = await widget.service.fetchNovelContent(
                widget.source!,
                novelId: widget.novelId,
                chapterUrl: chapter.url,
                nextChapterUrl: nextChapterUrl,
              );
              _chapterCache[ci] = blocks;
            } on Object {
              // 跳过拉取失败的章节。
              return;
            }
          }
        }
        if (gen != _generation || !mounted) throw const _SearchAborted();
        final hits = _matchChapter(
          ci,
          chapter.title,
          blocks,
          pattern,
          regex,
          _kMaxResults - collected,
        );
        if (hits.isNotEmpty) byChapter[ci] = hits;
        collected += hits.length;
        if (mounted && gen == _generation) {
          setState(() => _searchedCount++);
          refreshResults(); // 实时插入本章命中
        }
      });
    } on _SearchAborted {
      // 发起新搜索 / 关闭面板 / 结果达上限 / 暂停后取消：丢弃余量，正常归并。
    } finally {
      // 暂停态下不收尾（保持搜索中）；否则收尾。
      if (!_paused) {
        if (mounted && gen == _generation) {
          setState(() {
            _searching = false;
            _results = <InBookSearchResult>[
              for (final ci in chapterIndices)
                ...byChapter[ci] ?? const <InBookSearchResult>[],
            ];
          });
        } else {
          _searching = false;
        }
      }
    }
  }

  /// 暂停 / 继续切换。
  void _togglePause() {
    if (!_searching) return;
    if (_paused) {
      _paused = false;
      _resumeCompleter?.complete();
      _resumeCompleter = null;
      setState(() {});
    } else {
      _paused = true;
      _resumeCompleter = Completer<void>();
      setState(() {});
    }
  }

  /// 在一章块列表内做全量匹配（段内一词多现逐条命中），并计算章内字符
  /// 偏移（与阅读器分页偏移同口径：仅累计文本块，插图不计）。
  /// [pattern] 为匹配串；[regex] 非空时按正则匹配（[pattern] 即正则源）。
  /// [limit] 为本次可收集的命中上限。
  List<InBookSearchResult> _matchChapter(
    int chapterIndex,
    String chapterTitle,
    List<NovelBlock> blocks,
    String pattern,
    RegExp? regex,
    int limit,
  ) {
    final hits = <InBookSearchResult>[];
    var offset = 0;
    for (final block in blocks) {
      if (block is! NovelTextBlock) continue;
      final para = convertChinese(block.text, widget.convertMode);
      if (regex != null) {
        for (final m in regex.allMatches(para)) {
          final start = (m.start - 20).clamp(0, para.length);
          final end = (m.end + 20).clamp(0, para.length);
          hits.add(InBookSearchResult(
            chapterIndex: chapterIndex,
            chapterTitle: chapterTitle,
            snippet:
                '${start > 0 ? '...' : ''}${para.substring(start, end)}${end < para.length ? '...' : ''}',
            charOffset: offset + m.start,
            keyword: pattern,
            regex: regex,
          ));
          if (hits.length >= limit) return hits;
        }
      } else {
        var idx = para.indexOf(pattern);
        while (idx >= 0) {
          final start = (idx - 20).clamp(0, para.length);
          final end = (idx + pattern.length + 20).clamp(0, para.length);
          hits.add(InBookSearchResult(
            chapterIndex: chapterIndex,
            chapterTitle: chapterTitle,
            snippet:
                '${start > 0 ? '...' : ''}${para.substring(start, end)}${end < para.length ? '...' : ''}',
            charOffset: offset + idx,
            keyword: pattern,
          ));
          if (hits.length >= limit) return hits;
          idx = para.indexOf(pattern, idx + pattern.length);
        }
      }
      offset += para.length;
    }
    return hits;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final sheetHeight = isLandscape ? 0.85 : 0.7;
    return AppSheetBody(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: math.max(MediaQuery.of(context).viewInsets.bottom,
            MediaQuery.paddingOf(context).bottom),
        ),
        child: DraggableScrollableSheet(
          initialChildSize: sheetHeight,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          expand: false,
          builder: (ctx, scrollController) => Column(
            children: <Widget>[
              // ───── 搜索栏 ─────
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.spaceMd,
                  AppTokens.spaceMd,
                  AppTokens.spaceMd,
                  AppTokens.spaceXs,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          hintText: l10n.searchInBook,
                          prefixIcon: const Icon(Icons.search_rounded),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _search(),
                      ),
                    ),
                    const SizedBox(width: AppTokens.spaceSm),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      onPressed: _searching ? null : _search,
                      child: Text(l10n.search),
                    ),
                  ],
                ),
              ),
              // ───── 范围选择 ─────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      _buildScopeChip(l10n.currentChapter, InBookSearchScope.currentChapter),
                      const SizedBox(width: AppTokens.spaceXs),
                      _buildScopeChip(l10n.searchScopeAll, InBookSearchScope.wholeBook),
                      const SizedBox(width: AppTokens.spaceXs),
                      _buildScopeChip(l10n.searchScopeFromHere, InBookSearchScope.fromCurrent),
                      const SizedBox(width: AppTokens.spaceXs),
                      _buildScopeChip(l10n.searchScopeRange, InBookSearchScope.range),
                      const SizedBox(width: AppTokens.spaceSm),
                      // 正则开关
                      Text(l10n.searchUseRegex, style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(width: 4),
                      SizedBox(
                        height: 24,
                        child: Switch(
                          value: _useRegex,
                          onChanged: (v) {
                            v == true ? AppHaptics.toggleOn() : AppHaptics.toggleOff();
                            setState(() => _useRegex = v);
                          },
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
                    // ───── 起止章范围输入 ─────
              if (_scope == InBookSearchScope.range)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.spaceMd, AppTokens.spaceXs, AppTokens.spaceMd, 0,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '起始章',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          onChanged: (v) => _rangeStart = int.tryParse(v),
                        ),
                      ),
                      const SizedBox(width: AppTokens.spaceSm),
                      Expanded(
                        child: TextField(
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '结束章',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          onChanged: (v) => _rangeEnd = int.tryParse(v),
                        ),
                      ),
                    ],
                  ),
                ),
              // ───── 最近搜索 ─────
              if (!_searching &&
                  _controller.text.isEmpty &&
                  _history.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.spaceMd, AppTokens.spaceXs, AppTokens.spaceMd, 0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              l10n.recentSearches,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.clear_all_rounded, size: 18),
                            tooltip: l10n.clearHistory,
                            onPressed: _clearHistory,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: AppTokens.spaceXs,
                        runSpacing: AppTokens.spaceXs,
                        children: <Widget>[
                          for (final kw in _history)
                            InputChip(
                              label: Text(
                                kw,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onPressed: () {
                                _controller.text = kw;
                                _search();
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _searching && _results.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _paused
                                    ? l10n.searchPaused
                                    : l10n.searchProgress(
                                        _searchedCount, _totalCount),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 28,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                ),
                                onPressed: _togglePause,
                                icon: Icon(
                                  _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                                  size: 16,
                                ),
                                label: Text(
                                  _paused ? l10n.searchResume : l10n.searchPause,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : _results.isEmpty
                        ? Center(child: Text(l10n.noSearchResults))
                        : Column(
                            children: <Widget>[
                              // 搜索中时在顶部显示进度条
                              if (_searching)
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppTokens.spaceMd,
                                    vertical: AppTokens.spaceXs,
                                  ),
                                  child: Row(
                                    children: <Widget>[
                                      SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      const SizedBox(width: AppTokens.spaceSm),
                                      Expanded(
                                        child: Text(
                                          _paused
                                              ? l10n.searchPaused
                                              : l10n.searchProgress(
                                                  _searchedCount, _totalCount),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ),
                                      SizedBox(
                                        height: 26,
                                        child: FilledButton.icon(
                                          style: FilledButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 8),
                                          ),
                                          onPressed: _togglePause,
                                          icon: Icon(
                                            _paused
                                                ? Icons.play_arrow_rounded
                                                : Icons.pause_rounded,
                                            size: 14,
                                          ),
                                          label: Text(
                                            _paused
                                                ? l10n.searchResume
                                                : l10n.searchPause,
                                            style: const TextStyle(fontSize: 11),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              // 结果列表
                              Expanded(
                                child: ListView.separated(
                                  controller: scrollController,
                                  itemCount: _results.length,
                                  separatorBuilder: (_, __) => const Divider(
                                      height: 1, indent: AppTokens.spaceMd),
                                  itemBuilder: (_, i) {
                                    final r = _results[i];
                                    return ListTile(
                                      dense: true,
                                      visualDensity: VisualDensity.compact,
                                      title: Text(
                                        '${l10n.chapterN(r.chapterIndex + 1)} · ${r.chapterTitle}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: _buildHighlightedText(
                                          r.snippet,
                                          r.keyword,
                                          Theme.of(context).colorScheme.primary,
                                          regex: r.regex,
                                        ),
                                      ),
                                      onTap: () => Navigator.of(context).pop(r),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建带关键词高亮的富文本（普通模式按子串包含、正则模式按表达式匹配）。
  Widget _buildHighlightedText(
    String text,
    String keyword,
    Color highlightColor, {
    RegExp? regex,
  }) {
    final spans = searchHitSpans(
      text: text,
      query: keyword,
      regex: regex,
      hitStyle: TextStyle(
        backgroundColor: highlightColor.withValues(alpha: 0.3),
        fontWeight: FontWeight.w600,
      ),
    );
    if (spans == null) {
      return Text(text, maxLines: 2, overflow: TextOverflow.ellipsis);
    }
    return Text.rich(
      TextSpan(
        style: Theme.of(context).textTheme.bodySmall,
        children: spans,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// 构建范围选择芯片（适配手机紧凑布局）。
  Widget _buildScopeChip(String label, InBookSearchScope scope) {
    final selected = _scope == scope;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => setState(() => _scope = scope),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }
}
