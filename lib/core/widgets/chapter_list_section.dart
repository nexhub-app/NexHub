/// 详情页共享章节列表组件（筛选/排序/显示全面增强）。
///
/// 提供"搜索框 + 筛选/排序/显示组合按钮 + 章节 ListTile + 行尾操作按钮"的
/// 统一布局，供唯一详情页 [ContentDetailScreen]（动漫/影视/漫画/小说）复用。
///
/// 行尾三按钮（下载单章 / 书签 / 已读）通过回调按需启用：传入 null 则不渲染。
/// 已读条目自动降低不透明度（[Opacity(0.5)]）。
/// 非默认筛选/排序/显示设置时按钮上显示角标 dot。
library;

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../history/chapter_fetch_time_manager.dart';
import '../models/episode.dart';
import '../settings/detail_appearance_settings.dart';
import '../settings/general_settings.dart';
import '../theme/app_tokens.dart';
import '../theme/app_theme.dart';
import 'app_animations.dart';
import 'app_empty_state.dart';
import 'app_loading_indicator.dart';
import 'app_search_field.dart';
import 'detail_list_filter.dart';
import '../utils/app_haptics.dart';

/// 章节列表区。支持搜索过滤 + 筛选/排序/显示组合 + 可选的线路分组。
class ChapterListSection extends StatefulWidget {
  /// 全部章节（未排序前的原始顺序，通常为源返回顺序）。
  final List<Episode> chapters;

  /// 是否按线路（[Episode.lineName]）分组展示（影视多线路场景）。
  final bool groupByLine;

  /// 点击章节行体。
  final void Function(Episode ep, int originalIndex) onTapChapter;

  /// 下载单章回调（null 时不显示下载按钮）。
  final Future<void> Function(Episode ep, int originalIndex)? onDownloadChapter;

  /// 切换书签回调（null 时不显示书签按钮）。
  final Future<void> Function(Episode ep, int originalIndex)? onToggleBookmark;

  /// 查询某章是否有书签（null 时不显示书签按钮）。
  final bool Function(int originalIndex)? isChapterBookmarked;

  /// 切换已读回调（null 时不显示已读按钮）。
  final Future<void> Function(Episode ep, int originalIndex)? onToggleRead;

  /// 查询某章是否已读（null 时不显示已读按钮）。
  final bool Function(int originalIndex)? isChapterRead;

  /// 查询某章是否已下载（用于下载按钮的图标状态）。
  final bool Function(int originalIndex)? isChapterDownloaded;

  /// 单位词（如"章"或"集"），用于筛选弹窗的排序/显示标签。
  final String unitWord;

  /// 是否多源混合（true 时显示"按来源排序"和"显示来源标题"选项）。
  final bool isMultiSource;

  /// 是否启用网格/列表切换（默认 false；影视类设 true）。
  final bool enableGridMode;

  /// 内容 ID（用于查询每集播放进度，可选）。
  final String? contentId;

  /// 返回某集的播放位置（毫秒），0 表示无记录。null 时不显示进度指示。
  final int Function(int originalIndex)? getPosition;

  /// 是否仍有章节在后台渐进加载中（如长目录多页续抓）。true 时：
  /// - 列表为空则显示"加载中"而非"暂无内容"；
  /// - 列表非空则在末尾追加一个加载指示行，提示用户剩余章节正在补齐。
  final bool loadingMore;

  const ChapterListSection({
    super.key,
    required this.chapters,
    required this.onTapChapter,
    this.groupByLine = false,
    this.onDownloadChapter,
    this.onToggleBookmark,
    this.isChapterBookmarked,
    this.onToggleRead,
    this.isChapterRead,
    this.isChapterDownloaded,
    this.unitWord = '',
    this.isMultiSource = false,
    this.enableGridMode = false,
    this.contentId,
    this.getPosition,
    this.loadingMore = false,
  });

  @override
  State<ChapterListSection> createState() => _ChapterListSectionState();
}

class _ChapterListSectionState extends State<ChapterListSection> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  DetailListQuery _filterQuery = const DetailListQuery();

  /// 网格/列表显示模式（仅当 [ChapterListSection.enableGridMode] 为 true 时可切换）。
  bool _isGridMode = false;

  /// 快捷选集区间（null 表示显示全部）。
  int? _rangeStart;
  static const int _rangeSize = 12;

  /// 当前选中的线路（null 表示全部线路）。仅当 [groupByLine] 且线路数 > 1 时有效。
  String? _selectedLine;

  /// 长列表折叠：默认只渲染前 [_collapseHead] + 后 [_collapseTail] 章，
  /// 中间折叠为"展开"按钮，防止上千章一次性全量渲染导致详情页卡顿。
  /// 用户点击展开后置 true（搜索/筛选/区间选择时不折叠，保证结果完整）。
  bool _chaptersExpanded = false;
  static const int _collapseHead = 20;
  static const int _collapseTail = 20;

  /// 区间 chips 横向滚动控制器（选中后自动居中）。
  final ScrollController _chipScrollCtrl = ScrollController();

  /// 区间 chips 的定位锚点：key = chip 序号（0 = 「全部」，1..n = 各区间）。
  ///
  /// 用真实布局对象定位（[Scrollable.ensureVisible]），取代此前按固定 80px
  /// 估算偏移的做法——chip 宽度随文字（如 `1-12` / `109-120`）变化且还有
  /// 8px 间距，估算值越往后偏差越大，导致选中项不居中、末尾几项滚不到。
  final Map<int, GlobalKey> _chipKeys = <int, GlobalKey>{};

  GlobalKey _chipKey(int index) =>
      _chipKeys.putIfAbsent(index, () => GlobalKey());

  /// 本地首次获取时间（毫秒），key = 章节 [Episode.id]。
  /// 当源未提供 [Episode.updatedAt] 时用作兜底展示，且只在首次加载时记录。
  final Map<String, int> _localFetchTimes = <String, int>{};

  @override
  void initState() {
    super.initState();
    // 监听全局日期格式变更，使选集/章节日期即时跟随设置页修改。
    GeneralSettingsStore.instance.addListener(_onSettingsChanged);
    _loadLocalFetchTimes();
  }

  /// 全局设置（含日期格式）变更时刷新列表，让行内日期即时生效。
  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    GeneralSettingsStore.instance.removeListener(_onSettingsChanged);
    _searchCtrl.dispose();
    _chipScrollCtrl.dispose();
    super.dispose();
  }

  /// 源未提供更新时间时，记录并缓存"本地首次获取时间"，之后不再变动。
  Future<void> _loadLocalFetchTimes() async {
    final contentId = widget.contentId;
    if (contentId == null) return;
    final mgr = ChapterFetchTimeManager();
    final now = DateTime.now().millisecondsSinceEpoch;
    var changed = false;
    for (final ep in widget.chapters) {
      if (ep.updatedAt != null || ep.id.isEmpty) continue;
      final t = await mgr.recordIfAbsent(contentId, ep.id, now);
      if (_localFetchTimes[ep.id] != t) {
        _localFetchTimes[ep.id] = t;
        changed = true;
      }
    }
    if (changed && mounted) setState(() {});
  }

  /// 章节的有效更新时间：优先源提供的 [Episode.updatedAt]，否则用本地首次获取时间。
  DateTime? _effectiveUpdatedAt(int index) {
    final ep = widget.chapters[index];
    if (ep.updatedAt != null) return ep.updatedAt;
    final contentId = widget.contentId;
    if (contentId != null) {
      final t = _localFetchTimes[ep.id];
      if (t != null) return DateTime.fromMillisecondsSinceEpoch(t);
    }
    return null;
  }

  /// 格式化每章更新时间。当天显示 HH:mm（时间显示不受日期格式设置影响）；
  /// 其余日期跟随全局「日期格式」设置，设置页修改后即时生效。
  String _formatChapterDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    }
    return GeneralSettingsStore.instance.settings.dateFormat.format(dt);
  }

  /// 对原始索引列表应用搜索 + 筛选 + 排序 + 区间过滤。
  List<int> _processIndices(List<Episode> source, List<int> indices) {
    var result = indices;

    // 快捷选集区间过滤。区间以「当前子集（整表或单线路）首集」为基准，
    // 这样在按线路分组、且选中某条线路后，区间仍按该线路的集数序号生效，
    // 而非用全局绝对索引（否则单线路子集的索引永远匹配不到区间）。
    if (_rangeStart != null) {
      final base = result.isNotEmpty ? result.first : 0;
      result = result
          .where((i) =>
              i >= base + _rangeStart! && i < base + _rangeStart! + _rangeSize)
          .toList();
    }

    // 搜索过滤
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      result = result
          .where((i) => source[i].title.toLowerCase().contains(q))
          .toList();
    }

    // 筛选过滤
    final f = _filterQuery.filter;
    if (!f.isEmpty) {
      result = result.where((i) {
        if (f.unread &&
            widget.isChapterRead != null &&
            widget.isChapterRead!(i)) {
          return false;
        }
        if (f.downloaded &&
            (widget.isChapterDownloaded == null ||
                !widget.isChapterDownloaded!(i))) {
          return false;
        }
        if (f.bookmarked &&
            (widget.isChapterBookmarked == null ||
                !widget.isChapterBookmarked!(i))) {
          return false;
        }
        return true;
      }).toList();
    }

    // 排序
    final s = _filterQuery.sort;
    if (s.key == DetailSortKey.byIndex) {
      if (s.descending) result = result.reversed.toList();
    } else {
      result.sort((a, b) {
        int cmp;
        switch (s.key) {
          case DetailSortKey.name:
            cmp = source[a].title.compareTo(source[b].title);
            break;
          case DetailSortKey.uploadDate:
            final aDate = _effectiveUpdatedAt(a);
            final bDate = _effectiveUpdatedAt(b);
            if (aDate == null && bDate == null) {
              cmp = 0;
            } else if (aDate == null) {
              cmp = 1;
            } else if (bDate == null) {
              cmp = -1;
            } else {
              cmp = aDate.compareTo(bDate);
            }
            break;
          case DetailSortKey.source:
            final aLine = source[a].lineName ?? '';
            final bLine = source[b].lineName ?? '';
            cmp = aLine.compareTo(bLine);
            break;
          case DetailSortKey.byIndex:
            cmp = 0;
            break;
        }
        return s.descending ? -cmp : cmp;
      });
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    if (widget.chapters.isEmpty) {
      // 后台仍在续抓目录时显示"加载中"，避免误报"暂无内容"。
      if (widget.loadingMore) {
        return const Padding(
          padding: EdgeInsets.all(AppTokens.spaceLg),
          child: Center(child: AppBouncingDots()),
        );
      }
      return Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        child: AppEmptyState(
          icon: Icons.video_library_rounded,
          message: l10n.emptyContent,
        ),
      );
    }

    // 窄屏（< compactBreakpoint）判定用 LayoutBuilder 取实际可用宽度——
    // 与详情页其余部分（content_detail_tabbed_shell 等）保持同一惯例，
    // 桌面 NavigationRail 布局下屏宽判定不准。
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isCompact =
            constraints.maxWidth < AppTokens.compactBreakpoint;
        return _buildChapterList(context, l10n, scheme, isCompact);
      },
    );
  }

  /// 章节列表主体（按线路分组 / 非分组两种布局）。
  ///
  /// [isCompact] 为 true 时列表条目行尾操作按钮收起，改用左右滑动快捷动作
  /// + 长按菜单，保证窄屏下的行内简洁性。
  Widget _buildChapterList(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme scheme,
    bool isCompact,
  ) {
    // 按线路分组
    if (widget.groupByLine) {
      final lines = <String, List<int>>{};
      for (var i = 0; i < widget.chapters.length; i++) {
        final line = widget.chapters[i].lineName ?? l10n.defaultLine;
        lines.putIfAbsent(line, () => <int>[]).add(i);
      }

      // 多线路（>1）时，在选集上方显示线路选择 chips。
      final bool showChips = lines.length > 1;
      // 当前选中线路对应的分组（null = 全部线路）。
      final renderLines = _selectedLine == null
          ? lines
          : (lines.containsKey(_selectedLine)
              ? <String, List<int>>{_selectedLine!: lines[_selectedLine]!}
              : lines);

      // 当前可见集数（决定区间 chips 是否显示）：选中单线时按该线集数，否则按全集数。
      final int viewCount = _selectedLine != null
          ? (lines[_selectedLine]?.length ?? widget.chapters.length)
          : widget.chapters.length;

      final List<Widget> children = <Widget>[
        _buildSearchBar(context, l10n, scheme),
      ];
      if (showChips) {
        children
            .add(_buildLineChips(context, l10n, scheme, lines.keys.toList()));
      }
      // 区间 chips：线路与区间可共存（需求2）。
      children.add(_buildRangeChips(context, l10n, scheme, viewCount));

      for (final entry in renderLines.entries) {
        final processed = _processIndices(widget.chapters, entry.value);
        if (processed.isEmpty) continue;

        // 组内折叠：仅"无搜索/无筛选/无区间/未手动展开"且本组超长时生效，
        // 防止多线路 × 每线成百上千集一次性全量渲染导致详情页卡顿（需求1）。
        final bool groupCollapse = !_chaptersExpanded &&
            _rangeStart == null &&
            _query.isEmpty &&
            _filterQuery.filter.isEmpty &&
            processed.length > _collapseHead + _collapseTail;
        final head =
            groupCollapse ? processed.sublist(0, _collapseHead) : processed;
        final tail = groupCollapse
            ? processed.sublist(processed.length - _collapseTail)
            : const <int>[];
        final hidden = groupCollapse
            ? processed.length - _collapseHead - _collapseTail
            : 0;

        // 仅"全部线路"模式（且显示 chips 时）保留分组标题；选中单线路时由 chip 标明。
        if (showChips && _selectedLine == null) {
          children.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(AppTokens.spaceLg,
                  AppTokens.spaceMd, AppTokens.spaceLg, AppTokens.spaceSm),
              child: Text(
                l10n.episodesWithLine(entry.key),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          );
        }
        // 网格/列表切换：groupByLine 分支此前只渲染列表，导致影视（groupByLine
        // + enableGridMode 同时为 true）下网格按钮点击无反应。这里与下方非分组
        // 路径保持一致，按 _isGridMode 选择网格或列表。
        if (_isGridMode && widget.enableGridMode) {
          children.add(_buildChapterGrid(context, l10n, scheme, head));
        } else {
          children.addAll(_buildChapterTiles(context, l10n, scheme, head,
              isCompact: isCompact));
        }
        if (groupCollapse) {
          children.add(_buildExpandButton(context, l10n, hidden));
          if (_isGridMode && widget.enableGridMode) {
            children.add(_buildChapterGrid(context, l10n, scheme, tail));
          } else {
            children.addAll(_buildChapterTiles(context, l10n, scheme, tail,
                isCompact: isCompact));
          }
        }
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      );
    }

    final indices = _processIndices(
      widget.chapters,
      List<int>.generate(widget.chapters.length, (i) => i),
    );

    // ── 长列表折叠：仅在"无搜索/无筛选/无区间选择/未手动展开"时生效。
    // 默认只渲染前 _collapseHead + 后 _collapseTail 章（各20），中间用
    // "展开剩余 N 章"按钮占位，避免上千个 ListTile 全量渲染导致卡顿。
    final bool collapseActive = !_chaptersExpanded &&
        _rangeStart == null &&
        _query.isEmpty &&
        _filterQuery.filter.isEmpty &&
        indices.length > _collapseHead + _collapseTail;
    final List<int> headIndices =
        collapseActive ? indices.sublist(0, _collapseHead) : indices;
    final List<int> tailIndices = collapseActive
        ? indices.sublist(indices.length - _collapseTail)
        : const <int>[];
    final int hiddenCount =
        collapseActive ? indices.length - _collapseHead - _collapseTail : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildSearchBar(context, l10n, scheme),
        _buildRangeChips(context, l10n, scheme, widget.chapters.length),
        if (indices.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppTokens.spaceLg),
            child: AppEmptyState(
              icon: Icons.search_off_rounded,
              message: l10n.noChaptersFound,
            ),
          )
        else if (_isGridMode && widget.enableGridMode) ...<Widget>[
          _buildChapterGrid(context, l10n, scheme, headIndices),
          if (collapseActive) _buildExpandButton(context, l10n, hiddenCount),
          if (collapseActive)
            _buildChapterGrid(context, l10n, scheme, tailIndices),
        ] else ...<Widget>[
          ..._buildChapterTiles(context, l10n, scheme, headIndices,
              isCompact: isCompact),
          if (collapseActive) _buildExpandButton(context, l10n, hiddenCount),
          if (collapseActive)
            ..._buildChapterTiles(context, l10n, scheme, tailIndices,
                isCompact: isCompact),
        ],
        // 后台仍在续抓目录 → 末尾追加加载指示，提示剩余章节补齐中。
        if (widget.loadingMore)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceMd),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const AppBouncingDots(dotSize: 5),
                const SizedBox(width: AppTokens.spaceSm),
                Text(l10n.loading,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildSearchBar(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme scheme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceLg, vertical: AppTokens.spaceSm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: AppSearchField(
              controller: _searchCtrl,
              hint: l10n.searchChapter,
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          // 筛选/排序/显示组合按钮
          Stack(
            children: <Widget>[
              IconButton(
                tooltip: l10n.filterTitle,
                icon: const Icon(Icons.tune_rounded, size: 22),
                onPressed: () async {
                  final result = await DetailListFilterSheet.show(
                    context,
                    initialQuery: _filterQuery,
                    unitWord: widget.unitWord,
                    isMultiSource: widget.isMultiSource,
                  );
                  if (result != null) {
                    setState(() => _filterQuery = result);
                  }
                },
              ),
              // 非默认设置时显示角标 dot
              if (!_filterQuery.isDefault)
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          // 网格/列表切换
          if (widget.enableGridMode)
            IconButton(
              icon: Icon(
                _isGridMode ? Icons.view_list_rounded : Icons.grid_view_rounded,
                size: 22,
              ),
              tooltip: _isGridMode ? l10n.listView : l10n.gridView,
              onPressed: () => setState(() => _isGridMode = !_isGridMode),
            ),
        ],
      ),
    );
  }

  /// 可横向滚动的 chip 行（区间 chips / 线路 chips 共用）。
  ///
  /// 直接占满父级宽度（修复原先用 [MediaQuery] 屏宽减 padding 手动计算在
  /// 桌面 NavigationRail 下宽度错误的问题），并用 [ShaderMask] 在右缘做
  /// 渐隐淡出，提示被裁切的 chip 可横向滚动，消除「硬切断」的破碎感。
  Widget _buildScrollableChipRow({
    ScrollController? controller,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceLg, vertical: AppTokens.spaceXs),
      child: SizedBox(
        width: double.infinity,
        child: ShaderMask(
          shaderCallback: (Rect bounds) => const LinearGradient(
            colors: <Color>[Colors.white, Colors.white, Colors.transparent],
            stops: <double>[0.0, 0.96, 1.0],
          ).createShader(bounds),
          blendMode: BlendMode.dstIn,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            controller: controller,
            // 末尾留出与渐隐区等宽的滚动余量，避免最后一个 chip 永远压在
            // 淡出边缘下、看起来点不到。
            padding: const EdgeInsetsDirectional.only(end: AppTokens.spaceLg),
            child: Row(children: children),
          ),
        ),
      ),
    );
  }

  /// 快捷选集区间 chips（章节数 > 2 × rangeSize 时显示）。
  ///
  /// 无独立「全部」chip：选中某区间后再次点击同一 chip 即取消选择，
  /// 回到显示全部章节。
  Widget _buildRangeChips(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme scheme,
    int totalCount,
  ) {
    if (totalCount <= _rangeSize * 2) return const SizedBox.shrink();
    final ranges = <int>[];
    for (int i = 0; i < totalCount; i += _rangeSize) {
      ranges.add(i);
    }
    return _buildScrollableChipRow(
      controller: _chipScrollCtrl,
      children: <Widget>[
        for (int i = 0; i < ranges.length; i++) ...<Widget>[
          FilterChip(
            key: _chipKey(i + 1),
            label: Text(
                '${ranges[i] + 1}-${ranges[i] + _rangeSize > totalCount ? totalCount : ranges[i] + _rangeSize}'),
            selected: _rangeStart == ranges[i],
            onSelected: (bool selected) {
              // 再点一次已选中的 chip = 取消选择，回到全部。
              setState(() => _rangeStart = selected ? ranges[i] : null);
              _scrollChipToCenter(i + 1);
            },
          ),
          const SizedBox(width: AppTokens.spaceSm),
        ],
      ],
    );
  }

  /// 将区间 chips 滚动到选中项居中显示。
  ///
  /// 用选中 chip 的真实 RenderBox 定位（[Scrollable.ensureVisible] +
  /// `alignment: 0.5`），首尾项会被框架自动钳制到可滚动边界，因此既能精确
  /// 居中，也不会出现末尾项滚不到、点不着的情况。
  void _scrollChipToCenter(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? ctx = _chipKeys[index]?.currentContext;
      if (ctx == null || !ctx.mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// 多线路选择 chips（仅当 [groupByLine] 且线路数 > 1 时显示在选集上方）。
  ///
  /// 无独立「全部」chip：选中某线路后再次点击同一 chip 即取消选择，
  /// 回到显示全部线路。
  Widget _buildLineChips(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme scheme,
    List<String> lineNames,
  ) {
    return _buildScrollableChipRow(
      children: <Widget>[
        for (final line in lineNames) ...<Widget>[
          ChoiceChip(
            label: Text(line),
            selected: _selectedLine == line,
            onSelected: (bool selected) {
              AppHaptics.selectionClick();
              // 再点一次已选中的 chip = 取消选择，回到全部线路。
              setState(() => _selectedLine = selected ? line : null);
            },
          ),
          const SizedBox(width: AppTokens.spaceSm),
        ],
      ],
    );
  }

  /// 长列表折叠时中间的"展开剩余 N 章"按钮。
  Widget _buildExpandButton(
      BuildContext context, AppLocalizations l10n, int hiddenCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceLg, vertical: AppTokens.spaceXs),
      child: Center(
        child: TextButton.icon(
          onPressed: () => setState(() => _chaptersExpanded = true),
          icon: const Icon(Icons.unfold_more_rounded),
          label: Text(l10n.expandRemainingChapters(hiddenCount)),
        ),
      ),
    );
  }

  /// 网格模式渲染：紧凑卡片（序号 + 标题 + 进度指示）。
  Widget _buildChapterGrid(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme scheme,
    List<int> indices,
  ) {
    final display = _filterQuery.display;
    final String gridId = 'chapgrid-${widget.contentId ?? 'x'}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceLg),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 2.4,
          crossAxisSpacing: AppTokens.spaceSm,
          mainAxisSpacing: AppTokens.spaceSm,
        ),
        itemCount: indices.length,
        itemBuilder: (BuildContext ctx, int gridIndex) {
          final i = indices[gridIndex];
          final ep = widget.chapters[i];
          final bool isRead =
              widget.isChapterRead != null && widget.isChapterRead!(i);
          final bool hasProgress =
              widget.getPosition != null && widget.getPosition!(i) > 0;

          String label = ep.title;
          if (display.number) {
            final numStr = ep.number != null ? '${ep.number}' : '${i + 1}';
            label = '$numStr. ${ep.title}';
          }

          final Widget card = Container(
            decoration: BoxDecoration(
              color: AppTheme.cardContainer(scheme),
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              border: hasProgress
                  ? Border.all(
                      color: scheme.primary.withValues(alpha: 0.5), width: 1.5)
                  : null,
            ),
            child: Stack(
              children: <Widget>[
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.spaceXs, vertical: 2),
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ),
                if (hasProgress)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          );

          final bool hasGridActions = widget.onToggleRead != null ||
              widget.onToggleBookmark != null ||
              widget.onDownloadChapter != null;
          return Entrance(
            onceKey: '$gridId-$i',
            delay: Duration(milliseconds: (gridIndex * 18).clamp(0, 240)),
            child: _GridChapterCell(
              isRead: isRead,
              card: card,
              onTap: () => widget.onTapChapter(ep, i),
              onLongPress: hasGridActions
                  ? () => _showGridChapterMenu(context, ep, i, isRead)
                  : null,
            ),
          );
        },
      ),
    );
  }

  /// 网格卡片长按菜单：已读 / 书签 / 下载单章（按需启用，回调为 null 则不显示对应项）。
  void _showGridChapterMenu(
    BuildContext context,
    Episode ep,
    int i,
    bool isRead,
  ) {
    // MD3「Thunk」：长按呼出章节操作菜单。
    AppHaptics.thunk();
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<Widget> items = <Widget>[
      if (widget.onToggleRead != null)
        ListTile(
          leading: Icon(
            isRead
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
          ),
          title: Text(l10n.chapterRead),
          onTap: () {
            Navigator.of(context).pop();
            widget.onToggleRead!.call(ep, i);
          },
        ),
      if (widget.onToggleBookmark != null)
        ListTile(
          leading: const Icon(Icons.bookmark_rounded),
          title: Text(l10n.chapterBookmark),
          onTap: () {
            Navigator.of(context).pop();
            widget.onToggleBookmark!.call(ep, i);
          },
        ),
      if (widget.onDownloadChapter != null)
        ListTile(
          leading: const Icon(Icons.download_rounded),
          title: Text(l10n.downloadSingleChapter),
          onTap: () {
            Navigator.of(context).pop();
            widget.onDownloadChapter!.call(ep, i);
          },
        ),
    ];
    if (items.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: items,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildChapterTiles(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme scheme,
    List<int> indices, {
    required bool isCompact,
  }) {
    final display = _filterQuery.display;
    final String idKey = widget.contentId ?? 'chap';
    final List<Widget> tiles = <Widget>[];
    for (var pos = 0; pos < indices.length; pos++) {
      final int i = indices[pos];
      final ep = widget.chapters[i];
      final bool isRead =
          widget.isChapterRead != null && widget.isChapterRead!(i);
      final bool hasProgress =
          widget.getPosition != null && widget.getPosition!(i) > 0;

      // 显示序号前缀
      String titleText = ep.title;
      if (display.number) {
        final numStr = ep.number != null ? '${ep.number}' : '${i + 1}';
        titleText = '$numStr. ${ep.title}';
      }

      // 副标题：来源标题（可选）+ 每章更新时间（需求6）
      final List<String> subtitleParts = <String>[];
      if (display.sourceTitle && ep.lineName != null) {
        subtitleParts.add(ep.lineName!);
      }
      final DateTime? effectiveDate = _effectiveUpdatedAt(i);
      if (effectiveDate != null) {
        subtitleParts.add(_formatChapterDate(effectiveDate));
      }
      final String? subtitle =
          subtitleParts.isEmpty ? null : subtitleParts.join(' · ');

      final bool hasSwipeActions = widget.onDownloadChapter != null ||
          widget.onToggleBookmark != null ||
          widget.onToggleRead != null;

      final Widget tile = ListTile(
        leading: widget.isChapterRead != null
            ? Icon(
                isRead
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: isRead ? scheme.primary : scheme.outline,
              )
            : null,
        title: Text(titleText, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: subtitle != null
            ? Text(subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ))
            : null,
        onTap: () => widget.onTapChapter(ep, i),
        // 长按菜单（下载/书签/已读）：网格与列表条目共用；宽屏列表也提供，
        // 窄屏列表同网格一样依赖长按补全操作入口。
        onLongPress: hasSwipeActions
            ? () => _showGridChapterMenu(context, ep, i, isRead)
            : null,
        // 窄屏（isCompact）删去行尾操作按钮保证简洁，操作改由左右滑动
        // 快捷动作提供（见 [_SwipeActionRow]）；宽屏保持原按钮布局。
        trailing: isCompact
            ? (hasProgress
                ? const Padding(
                    padding: EdgeInsets.only(right: AppTokens.spaceXs),
                    child: Icon(
                      Icons.fiber_manual_record_rounded,
                      size: 10,
                    ),
                  )
                : null)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (hasProgress)
                    Padding(
                      padding: const EdgeInsets.only(right: AppTokens.spaceXs),
                      child: Icon(
                        Icons.fiber_manual_record_rounded,
                        size: 10,
                        color: scheme.primary,
                      ),
                    ),
                  if (widget.onDownloadChapter != null)
                    Builder(builder: (BuildContext _) {
                      final bool downloaded =
                          widget.isChapterDownloaded?.call(i) ?? false;
                      return IconButton(
                        icon: Icon(
                          downloaded
                              ? Icons.download_done_rounded
                              : Icons.download_rounded,
                          size: 20,
                          color: downloaded ? scheme.primary : null,
                        ),
                        tooltip: downloaded
                            ? l10n.alreadyDownloaded
                            : l10n.downloadSingleChapter,
                        onPressed: () => widget.onDownloadChapter!(ep, i),
                      );
                    }),
                  if (widget.onToggleBookmark != null)
                    IconButton(
                      icon: Icon(
                        widget.isChapterBookmarked != null &&
                                widget.isChapterBookmarked!(i)
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        size: 20,
                      ),
                      tooltip: l10n.chapterBookmark,
                      onPressed: () => widget.onToggleBookmark!(ep, i),
                    ),
                  if (widget.onToggleRead != null)
                    IconButton(
                      icon: Icon(
                        isRead
                            ? Icons.visibility_rounded
                            : Icons.visibility_rounded,
                        size: 20,
                      ),
                      tooltip: l10n.chapterRead,
                      onPressed: () => widget.onToggleRead!(ep, i),
                    ),
                ],
              ),
      );

      // 已读条目降低不透明度
      final Widget row = isRead ? Opacity(opacity: 0.5, child: tile) : tile;
      tiles.add(
        Entrance(
          onceKey: '$idKey-$i',
          delay: Duration(milliseconds: (pos * 18).clamp(0, 240)),
          // 窄屏且有可用回调时包一层左右滑动快捷动作。
          child: isCompact && hasSwipeActions
              ? _SwipeActionRow(
                  ep: ep,
                  index: i,
                  isRead: isRead,
                  isBookmarked: widget.isChapterBookmarked?.call(i) ?? false,
                  isDownloaded: widget.isChapterDownloaded?.call(i) ?? false,
                  onDownload: widget.onDownloadChapter,
                  onToggleBookmark: widget.onToggleBookmark,
                  onToggleRead: widget.onToggleRead,
                  child: row,
                )
              : row,
        ),
      );
    }
    return tiles;
  }
}

/// 网格章节卡片：点击进入详情；长按弹出操作菜单；按下带轻微缩放反馈（灵动感）。
class _GridChapterCell extends StatefulWidget {
  final bool isRead;
  final Widget card;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _GridChapterCell({
    required this.isRead,
    required this.card,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<_GridChapterCell> createState() => _GridChapterCellState();
}

class _GridChapterCellState extends State<_GridChapterCell> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.94),
      onTapUp: (_) => setState(() => _scale = 1.0),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.isRead
            ? Opacity(opacity: 0.5, child: widget.card)
            : widget.card,
      ),
    );
  }
}

/// 窄屏左右滑动快捷动作容器（仅 [ChapterListSection] 内部使用）。
///
/// 交互设计：
/// - 右滑（向右拖）露出左侧动作 = 切换已读；
/// - 左滑（向左拖）露出右侧动作 = 下载单章 / 切换书签（按回调可用性生成）；
/// - 露出动作后点击图标触发，条目自动弹回原位（不整体滑出移除）；
/// - 完整拖过阈值（80px，超过一个动作槽位）松手直接触发对应动作，
///   与露出点击等效：右滑满滑 = 切换已读；左滑满滑 = 下载单章
///   （无下载回调时为切换书签）。
///
/// 用 [GestureDetector] 水平拖拽 + 自绘动作层，而非 [Dismissible]：
/// Dismissible 的语义是「滑动后移除条目」，与这里「滑出按钮点按执行」
/// 的操作面板语义不符；confirmDismiss 拦截弹回后露出的按钮也不可点击。
class _SwipeActionRow extends StatefulWidget {
  final Episode ep;
  final int index;
  final bool isRead;
  final bool isBookmarked;
  final bool isDownloaded;
  final Future<void> Function(Episode ep, int originalIndex)? onDownload;
  final Future<void> Function(Episode ep, int originalIndex)? onToggleBookmark;
  final Future<void> Function(Episode ep, int originalIndex)? onToggleRead;
  final Widget child;

  const _SwipeActionRow({
    required this.ep,
    required this.index,
    required this.isRead,
    required this.isBookmarked,
    required this.isDownloaded,
    required this.child,
    this.onDownload,
    this.onToggleBookmark,
    this.onToggleRead,
  });

  @override
  State<_SwipeActionRow> createState() => _SwipeActionRowState();
}

class _SwipeActionRowState extends State<_SwipeActionRow> {
  /// 当前水平位移。>0 右滑（露出左侧动作），<0 左滑（露出右侧动作）。
  double _dragExtent = 0;

  /// 单个动作槽位宽度（逻辑像素）。
  static const double _actionExtent = 72.0;

  /// 满滑触发阈值：拖到槽位的 80% 松手 = 直接触发对应动作
  /// （必须小于槽位上限，否则满滑永远够不到阈值）。
  static double get _triggerThreshold => _actionExtent * 0.8;

  /// 按回调可用性构建完整动作池，并按偏好 [pref] 选取。
  ///
  /// 关键：动作池不按方向截断——左滑/右滑都从同一个池里选，方向只决定
  /// 触发哪个设置项（leftSwipeAction / rightSwipeAction）。若按方向预先
  /// 过滤（如左滑只给下载+书签），用户把左滑设为已读时匹配失败会静默
  /// 回落到 first（下载），表现为"设置不生效、恒为下载"。
  ///
  /// 设置的动作没有对应回调（如影视无书签回调）时回落到任一可用动作，
  /// 全无则 null。
  _SwipeAction? _resolveAction(DetailSwipeAction pref) {
    final List<_SwipeAction> available = <_SwipeAction>[
      if (widget.onToggleRead != null)
        _SwipeAction(
          kind: DetailSwipeAction.read,
          icon: widget.isRead
              ? Icons.visibility_off_rounded
              : Icons.visibility_rounded,
          background: widget.isRead ? Colors.blueGrey : Colors.green.shade700,
          onTap: () => widget.onToggleRead!(widget.ep, widget.index),
        ),
      if (widget.onDownload != null)
        _SwipeAction(
          kind: DetailSwipeAction.download,
          icon: widget.isDownloaded
              ? Icons.download_done_rounded
              : Icons.download_rounded,
          background: Colors.blueGrey,
          onTap: () => widget.onDownload!(widget.ep, widget.index),
        ),
      if (widget.onToggleBookmark != null)
        _SwipeAction(
          kind: DetailSwipeAction.bookmark,
          icon: widget.isBookmarked
              ? Icons.bookmark_rounded
              : Icons.bookmark_border_rounded,
          background: Colors.amber.shade700,
          onTap: () => widget.onToggleBookmark!(widget.ep, widget.index),
        ),
    ];
    for (final _SwipeAction a in available) {
      if (a.kind == pref) return a;
    }
    return available.isEmpty ? null : available.first;
  }

  /// 左滑（extent < 0，揭示在条目右侧）触发的动作：读左滑设置项。
  _SwipeAction? get _leftAction => _resolveAction(
      DetailAppearanceStore.instance.settings.leftSwipeAction);

  /// 右滑（extent > 0，揭示在条目左侧）触发的动作：读右滑设置项。
  _SwipeAction? get _rightAction => _resolveAction(
      DetailAppearanceStore.instance.settings.rightSwipeAction);

  void _onDragUpdate(DragUpdateDetails d) {
    // 单次 clamp，区间按两侧动作可用性动态收缩：
    // 两侧都有 → [-72, 72]；只有右滑动作 → [0, 72]；只有左滑动作 → [-72, 0]。
    // 注意不能写成两段 clamp 链（交集恒为 0，条目将无法拖动）。
    final bool leftEnabled = _leftAction != null;
    final bool rightEnabled = _rightAction != null;
    setState(() {
      _dragExtent = (_dragExtent + d.delta.dx).clamp(
        leftEnabled ? -_actionExtent : 0.0,
        rightEnabled ? _actionExtent : 0.0,
      );
    });
  }

  void _onDragEnd(DragEndDetails d) {
    final double v = _dragExtent;
    setState(() => _dragExtent = 0);
    // 满滑与露出点击触发同一动作（方向 → 设置动作一一对应），不存在重复。
    if (v >= _triggerThreshold) {
      final _SwipeAction? a = _rightAction;
      if (a != null) a.onTap();
    } else if (-v >= _triggerThreshold) {
      final _SwipeAction? a = _leftAction;
      if (a != null) a.onTap();
    }
    // 未过阈值：仅回弹，无动作。
  }

  /// 触发动作后执行：先触感反馈，再调用回调。
  void _runAction(VoidCallback action) {
    AppHaptics.click();
    setState(() => _dragExtent = 0);
    action();
  }

  /// 构建单个动作按钮（露出层里的图标块）。
  Widget _buildActionButton(_SwipeAction action, double slotWidth) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _runAction(action.onTap),
      child: Container(
        width: slotWidth,
        height: double.infinity,
        color: action.background,
        alignment: Alignment.center,
        child: Icon(action.icon, color: Colors.white, size: 22),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final _SwipeAction? left = _leftAction;
    final _SwipeAction? right = _rightAction;
    final double extent = _dragExtent;

    // 两侧都无可用动作：直接返回原条目（外层 hasSwipeActions 已过滤回调级
    // 可用性，这里兜底设置动作与回调不匹配的情况）。
    if (left == null && right == null) return widget.child;

    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Stack(
        children: <Widget>[
          // ── 动作层（揭示在条目下方）──────────────────────────
          Positioned.fill(
            child: ClipRect(
              child: Row(
                children: <Widget>[
                  // 右滑动作（揭示在条目左侧，宽度随位移生长）。
                  if (right != null)
                    SizedBox(
                      width: extent.clamp(0.0, _actionExtent),
                      child: extent > 0
                          ? _buildActionButton(
                              right, extent.clamp(0.0, _actionExtent))
                          : null,
                    ),
                  const Spacer(),
                  // 左滑动作（揭示在条目右侧，从右缘向左生长）。
                  if (left != null)
                    SizedBox(
                      width: (-extent).clamp(0.0, _actionExtent),
                      child: extent < 0
                          ? _buildActionButton(
                              left, (-extent).clamp(0.0, _actionExtent))
                          : null,
                    ),
                ],
              ),
            ),
          ),
          // ── 条目层（随拖拽平移，松手回弹）──────────────────────
          AnimatedContainer(
            duration: _dragExtent == 0
                ? const Duration(milliseconds: 180)
                : Duration.zero,
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(_dragExtent, 0, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// 单个滑动动作的描述。
class _SwipeAction {
  /// 动作种类：与设置枚举对齐，用于按用户偏好挑选当前方向的动作。
  final DetailSwipeAction kind;

  final IconData icon;
  final Color background;
  final VoidCallback onTap;

  const _SwipeAction({
    required this.kind,
    required this.icon,
    required this.background,
    required this.onTap,
  });
}
