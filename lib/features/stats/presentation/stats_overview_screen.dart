/// 统计页 —— 分模块展示阅读/观看时长（阶段 B++，仿 Animetail 风格）。
///
/// - 顶部三段 Tab（媒体 / 漫画 / 小说），切换各模块统计。
/// - AppBar 两个动作：搜索（过滤当前 Tab 的作品）、热力图（弹窗展示日级时长）。
/// - 主体三段卡（**Animetail 风格**：段标题加粗左对齐 + 卡片加大圆角 +
/// 每项 大数字 + 下方图标 + 小标签）：
/// - **总览**：总时长 / 作品数 / 会话次数。
/// - **活跃**：近 7 天活跃 / 近 30 天活跃 / 活跃天数。
/// - **节奏**：平均会话时长 / 最长单日 / 当前连续。
/// - 作品列表：每行 名称 + 最后阅读时间 + 总时长；长按可清除该作品统计。
///
/// 数据全部来自 [StatsRepository.instance]（ChangeNotifier 单例），
/// 通过 [ListenableBuilder] 自动刷新 —— 阅读器 commit 后本页即时更新。
library;

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/app_alert_dialog.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/stats/stats_models.dart';
import '../../../core/stats/stats_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_animations.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_cover_image.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../core/widgets/app_segmented_tabs.dart';
import '../../../core/widgets/progress_card.dart' show formatRelativeTime;
import '../../../core/utils/app_haptics.dart';
import 'heatmap_sheet.dart';
import 'trend_chart.dart';
import '../../../core/widgets/app_glass_bar.dart';

/// 统计页（从设置主页「统计」入口进入）。
class StatsOverviewScreen extends StatefulWidget {
  const StatsOverviewScreen({super.key});

  @override
  State<StatsOverviewScreen> createState() => _StatsOverviewScreenState();
}

class _StatsOverviewScreenState extends State<StatsOverviewScreen> {
  StatsMediaType _type = StatsMediaType.novel;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _searching = false;

  /// 趋势折线图窗口（天）。
  int _trendDays = 30;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 当前 Tab 的作品列表（按最后阅读时间倒序）。
  ///
  /// 过滤隐藏源与年龄限制拦截源的记录：这些源在书架/搜索/源管理里都不可见，
  /// 统计页若照常列出，等于把它们的作品名与阅读时长暴露出来。
  List<WorkReadingStats> _list(SourceRepository sources) {
    final all = StatsRepository.instance
        .statsBy(_type)
        .where((s) => _sourceVisible(sources, s.sourceId))
        .toList();
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where((s) =>
            (s.title?.toLowerCase().contains(q) ?? false) ||
            s.workId.toLowerCase().contains(q))
        .toList();
  }

  /// 该作品的来源是否对用户可见。
  bool _sourceVisible(SourceRepository sources, String? sourceId) {
    final id = sourceId?.trim() ?? '';
    if (id.isEmpty) return true;
    final config = sources.getById(id);
    // 源已删除/未加载：保留历史统计，避免数据凭空消失。
    if (config == null) return true;
    if (config.isHidden) return false;
    return !sources.isAgeBlocked(config);
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchController.clear();
        _query = '';
      }
    });
  }

  Future<void> _openHeatmap() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) => HeatmapSheet(initialType: _type),
    );
  }

  /// 把秒数格式化为「h 时 m 分 / m 分 s 秒 / s 秒」（l10n 键承载单位）。
  String _formatDuration(AppLocalizations l10n, int seconds) {
    if (seconds < 0) seconds = 0;
    if (seconds < 60) return l10n.statsDurSec(seconds);
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      if (m == 0) return l10n.statsDurHours(h);
      return l10n.statsDurHm(h, m);
    }
    return l10n.statsDurMs(m, s);
  }

  Future<void> _confirmClear(WorkReadingStats stat) async {
    // MD3「Thunk」：长按清空统计（破坏性确认）。
    AppHaptics.thunk();
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(l10n.statsClearTitle),
        content: Text(
          l10n.statsClearBody(stat.title ?? stat.workId),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.statsClearConfirm),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await StatsRepository.instance.removeWork(
        workId: stat.workId,
        sourceId: stat.sourceId,
        type: stat.type,
      );
    }
  }

  /// 通用分段卡：标题 + 3 个指标项（Animetail 风格）。
  Widget _buildSection({
    required String title,
    required List<({String value, String label, Color color, IconData icon})>
        items,
    required String entranceKey,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.spaceXs,
              0,
              AppTokens.spaceXs,
              AppTokens.spaceMd,
            ),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Entrance(
            onceKey: entranceKey,
            child: AppCard(
              padding: const EdgeInsets.symmetric(
                vertical: AppTokens.spaceXl,
                horizontal: AppTokens.spaceLg,
              ),
              child: Row(
                children: <Widget>[
                  for (final it in items)
                    _StatMetric(
                      value: it.value,
                      label: it.label,
                      color: it.color,
                      icon: it.icon,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 总览段：总时长 / 作品数 / 会话次数。
  Widget _buildOverviewSection(
      AppLocalizations l10n, List<WorkReadingStats> list) {
    final scheme = Theme.of(context).colorScheme;
    var totalSec = 0;
    var sessions = 0;
    for (final s in list) {
      totalSec += s.totalDurationSec;
      sessions += s.sessionCount;
    }
    return _buildSection(
      title: l10n.statsSectionOverview,
      entranceKey: 'stats_section_overview',
      items: <({String value, String label, Color color, IconData icon})>[
        (
          value: _formatDuration(l10n, totalSec),
          label: l10n.statsTotalDuration,
          color: scheme.primary,
          icon: Icons.timer_rounded,
        ),
        (
          value: '${list.length}',
          label: l10n.statsWorkCount,
          color: scheme.tertiary,
          icon: Icons.menu_book_rounded,
        ),
        (
          value: '$sessions',
          label: l10n.statsSessionCount,
          color: scheme.secondary,
          icon: Icons.repeat_rounded,
        ),
      ],
    );
  }

  /// 活跃段：近 7 天 / 近 30 天 / 活跃天数（当前模块下整个历史）。
  ///
  /// 近 7/30 天按传入的可见列表统计，与下方作品列表口径一致；活跃天数来自
  /// 日聚合（按天存总量、无来源维度），只能按模块整体计算。
  Widget _buildActivitySection(
      AppLocalizations l10n, List<WorkReadingStats> list) {
    final scheme = Theme.of(context).colorScheme;
    final repo = StatsRepository.instance;
    final now = DateTime.now();
    final cutoff7 =
        now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    final cutoff30 =
        now.subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    var days7 = 0;
    var days30 = 0;
    for (final s in list) {
      if (s.lastReadAtMs >= cutoff30) days30 += 1;
      if (s.lastReadAtMs >= cutoff7) days7 += 1;
    }
    // 活跃天数：扫描当前模块下所有有数据的「日」（从首条 lastReadAtMs 到今）。
    var activeDays = 0;
    if (list.isNotEmpty) {
      var minMs = list.first.lastReadAtMs;
      for (final s in list) {
        if (s.lastReadAtMs > 0 && s.lastReadAtMs < minMs) {
          minMs = s.lastReadAtMs;
        }
      }
      if (minMs > 0) {
        final start = DateTime.fromMillisecondsSinceEpoch(minMs);
        final dailys = repo.dailyForRange(start, now);
        for (final d in dailys) {
          final s = switch (_type) {
            StatsMediaType.media => d.mediaDurationSec,
            StatsMediaType.comic => d.comicDurationSec,
            StatsMediaType.novel => d.novelDurationSec,
          };
          if (s > 0) activeDays += 1;
        }
      }
    }
    return _buildSection(
      title: l10n.statsSectionActivity,
      entranceKey: 'stats_section_activity',
      items: <({String value, String label, Color color, IconData icon})>[
        (
          value: '$days7',
          label: l10n.stats7dActive,
          color: scheme.primary,
          icon: Icons.calendar_view_week_rounded,
        ),
        (
          value: '$days30',
          label: l10n.stats30dActive,
          color: scheme.tertiary,
          icon: Icons.calendar_month_rounded,
        ),
        (
          value: '$activeDays',
          label: l10n.statsActiveDays,
          color: scheme.secondary,
          icon: Icons.local_fire_department_rounded,
        ),
      ],
    );
  }

  /// 节奏段：平均会话 / 最长单日 / 当前连续。
  ///
  /// 平均会话按可见列表的时长÷会话次数计算；最长单日与连续天数来自日聚合，
  /// 同样只能按模块整体计算。
  Widget _buildPaceSection(
      AppLocalizations l10n, List<WorkReadingStats> list) {
    final scheme = Theme.of(context).colorScheme;
    final repo = StatsRepository.instance;
    var totalSec = 0;
    var totalSessions = 0;
    for (final s in list) {
      totalSec += s.totalDurationSec;
      totalSessions += s.sessionCount;
    }
    final avg = totalSessions == 0 ? 0 : totalSec ~/ totalSessions;
    // 最长单日：扫描当前模块整年每日。
    final now = DateTime.now();
    var maxSec = 0;
    for (var m = 1; m <= 12; m++) {
      final monthStart = DateTime(now.year, m, 1);
      maxSec = [maxSec, repo.monthlyMaxDaily(monthStart, _type)].reduce(
        (a, b) => a > b ? a : b,
      );
    }
    final streak = repo.currentStreak(_type);
    return _buildSection(
      title: l10n.statsSectionPace,
      entranceKey: 'stats_section_pace',
      items: <({String value, String label, Color color, IconData icon})>[
        (
          value: _formatDuration(l10n, avg),
          label: l10n.statsAvgSession,
          color: scheme.primary,
          icon: Icons.av_timer_rounded,
        ),
        (
          value: _formatDuration(l10n, maxSec),
          label: l10n.statsMaxDaily,
          color: scheme.tertiary,
          icon: Icons.emoji_events_rounded,
        ),
        (
          value: '$streak',
          label: l10n.statsStreak,
          color: scheme.secondary,
          icon: Icons.whatshot_rounded,
        ),
      ],
    );
  }

  /// 趋势段：近 7 / 30 天每日时长折线（当前 Tab 类型过滤）。
  Widget _buildTrendSection(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final repo = StatsRepository.instance;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(Duration(days: _trendDays - 1));
    final secs = <int>[
      for (final d in repo.dailyForRange(start, today))
        switch (_type) {
          StatsMediaType.media => d.mediaDurationSec,
          StatsMediaType.comic => d.comicDurationSec,
          StatsMediaType.novel => d.novelDurationSec,
        },
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.spaceXs,
              0,
              AppTokens.spaceXs,
              AppTokens.spaceMd,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    l10n.statsSectionTrend,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                SizedBox(
                  width: 168,
                  child: AppSegmentedTabs<int>(
                    selected: <int>{_trendDays},
                    onSelectionChanged: (Set<int> s) {
                      if (s.isEmpty) return;
                      setState(() => _trendDays = s.first);
                    },
                    segments: <ButtonSegment<int>>[
                      ButtonSegment(value: 7, label: Text(l10n.statsTrend7d)),
                      ButtonSegment(value: 30, label: Text(l10n.statsTrend30d)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Entrance(
            onceKey: 'stats_section_trend',
            child: AppCard(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spaceLg,
                AppTokens.spaceXl,
                AppTokens.spaceLg,
                AppTokens.spaceMd,
              ),
              child: TrendChart(
                dailySec: secs,
                startDate: start,
                lineColor: scheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(AppLocalizations l10n) {
    return AnimatedSize(
      duration: AppTokens.durBase,
      curve: AppCurves.smooth,
      alignment: Alignment.topCenter,
      child: _searching
          ? Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spaceLg,
                AppTokens.spaceXs,
                AppTokens.spaceLg,
                AppTokens.spaceXs,
              ),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.statsSearchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                  ),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTokens.radiusFull),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }

  /// 单个作品行（封面 + 名称 + 最后阅读 + 总时长）。
  Widget _buildWorkTile(
      WorkReadingStats stat, AppLocalizations l10n, int index) {
    final name = stat.title?.isNotEmpty == true ? stat.title! : stat.workId;
    final readAt = stat.lastReadAtMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(stat.lastReadAtMs)
        : null;
    return Entrance(
      onceKey: 'stats_item_${stat.boxKey}',
      index: index,
      child: AppListTile(
        leading: AppCoverImage(
          coverUrl: stat.coverUrl,
          title: name,
          width: 48,
          height: 64,
          radius: AppTokens.radiusSm,
        ),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: readAt == null
            ? null
            : Text(
                '${l10n.statsLastRead} · '
                '${formatRelativeTime(l10n, readAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        trailing: Text(
          _formatDuration(l10n, stat.totalDurationSec),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
        ),
        onLongPress: () => _confirmClear(stat),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // watch：隐藏源 / 年龄限制开关变化时立即重新过滤列表。
    final sources = context.watch<SourceRepository>();
    final list = _list(sources);
    return AppShrinkTitleScaffold(
      title: Text(l10n.statsOverviewTitle),
      actions: <Widget>[
        IconButton(
          tooltip: l10n.statsSearchHint,
          icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
          onPressed: _toggleSearch,
        ),
        IconButton(
          tooltip: l10n.statsHeatmap,
          icon: const Icon(Icons.grid_view_rounded),
          onPressed: _openHeatmap,
        ),
      ],
      body: ListenableBuilder(
        listenable: StatsRepository.instance,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spaceLg,
                AppTokens.spaceSm,
                AppTokens.spaceLg,
                0,
              ),
              child: AppSegmentedTabs<StatsMediaType>(
                selected: <StatsMediaType>{_type},
                onSelectionChanged: (Set<StatsMediaType> s) {
                  if (s.isEmpty) return;
                  setState(() => _type = s.first);
                },
                segments: <ButtonSegment<StatsMediaType>>[
                  ButtonSegment(
                    value: StatsMediaType.novel,
                    label: Text(l10n.navNovel),
                    icon: const Icon(Icons.menu_book_rounded),
                  ),
                  ButtonSegment(
                    value: StatsMediaType.media,
                    label: Text(l10n.navMedia),
                    icon: const Icon(Icons.movie_rounded),
                  ),
                  ButtonSegment(
                    value: StatsMediaType.comic,
                    label: Text(l10n.navComic),
                    icon: const Icon(Icons.auto_stories_rounded),
                  ),
                ],
              ),
            ),
            _buildSearchField(l10n),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  AppTokens.spaceLg,
                  AppTokens.spaceXs,
                  AppTokens.spaceLg,
                  AppTokens.spaceXl + context.glassBarBottomInset,
                ),
                children: <Widget>[
                  _buildOverviewSection(l10n, list),
                  _buildActivitySection(l10n, list),
                  _buildPaceSection(l10n, list),
                  _buildTrendSection(l10n),
                  if (list.isEmpty)
                    _EmptyState(l10n: l10n)
                  else
                    for (var i = 0; i < list.length; i++) ...<Widget>[
                      _buildWorkTile(list[i], l10n, i),
                      if (i < list.length - 1)
                        const SizedBox(height: AppTokens.spaceXs),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 三段式分段里的单个指标项：大数字 + 图标 + 标签 + 强调色（Animetail 风格）。
class _StatMetric extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final IconData icon;

  const _StatMetric({
    required this.value,
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AppValuePulse(
            trigger: value,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
          const SizedBox(height: AppTokens.spaceXs),
          Icon(icon, size: 20, color: color.withValues(alpha: 0.85)),
          const SizedBox(height: AppTokens.spaceXs),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// 空态：当前 Tab 无任何统计记录。
class _EmptyState extends StatelessWidget {
  final AppLocalizations l10n;

  const _EmptyState({required this.l10n});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = AppStatusColors.ok(scheme);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceXl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.insights_rounded,
            size: 56,
            color: AppStatusColors.containerOf(accent),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          Text(
            l10n.statsNoRecords,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
