/// 桌面卡片数据聚合与刷新调度。
///
/// 卡片本身由系统（原生 UI）绘制，Flutter 只在合适的时机把「最新一份快照」
/// 推给原生。刷新时机：
///
/// * App 启动（首帧后）一次；
/// * 切后台 / 回前台各一次；
/// * 历史变化（进详情页、换集）与播放位置变化 —— 防抖 3 秒，保证「刚看完一集
///   回到桌面」时卡片上的进度是真的，而不是几天前的旧章节；
/// * 下载任务状态变化 —— 防抖 1.5 秒 + 推送时限频。
///
/// 不做后台定时刷新：与 RSS 更新检查保持一致（纯前台），避免唤醒耗电与被源站
/// 限流。
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../generated/app_localizations.dart';
import '../comic/comic_progress_manager.dart';
import '../download/download_manager.dart';
import '../favorites/favorites_manager.dart';
import '../history/history_manager.dart';
import '../history/media_playback_position_manager.dart';
import '../models/plugin_config.dart';
import '../novel/novel_progress_manager.dart';
import '../stats/stats_models.dart';
import '../stats/stats_repository.dart';
import '../theme/app_theme.dart';
import '../utils/app_log.dart';
import 'home_widget_background.dart';
import 'home_widget_bridge.dart';
import 'home_widget_data.dart';
import 'home_widget_heatmap.dart';
import 'home_widget_launcher.dart';
import 'home_widget_settings.dart';
import 'home_widget_thumb.dart';

class HomeWidgetService with WidgetsBindingObserver {
  HomeWidgetService._();

  static final HomeWidgetService instance = HomeWidgetService._();

  HistoryManager? _history;
  FavoritesManager? _favorites;
  DownloadManager? _downloads;
  MediaPlaybackPositionManager? _positions;

  /// 文案提供者。页面销毁后取不到 l10n 时返回 null，本次刷新直接跳过。
  AppLocalizations? Function()? _localizations;

  /// 主题快照（深浅色 + 整份 ColorScheme），背景图与卡片底色合成要用。
  ({bool isDark, ColorScheme scheme}) Function()? _theme;

  bool _started = false;
  bool _refreshing = false;
  bool _refreshQueued = false;

  /// 最近一次成功推送的时间，用于推送节流。
  int _lastPushMs = 0;

  /// 上一份成功推送的快照（用于判断哪些字段真的变了）。
  HomeWidgetSnapshot? _lastSnapshot;

  Timer? _downloadDebounce;
  Timer? _progressDebounce;

  /// 启动服务：注册监听并立即刷新一次。
  ///
  /// 幂等；重复调用只更新依赖，不重复注册监听。
  void start({
    required HistoryManager history,
    required FavoritesManager favorites,
    required DownloadManager downloads,
    required MediaPlaybackPositionManager positions,
    required AppLocalizations? Function() localizations,
    required ({bool isDark, ColorScheme scheme}) Function() theme,
  }) {
    _history = history;
    _favorites = favorites;
    _downloads = downloads;
    _positions = positions;
    _localizations = localizations;
    _theme = theme;
    if (_started) {
      unawaited(refresh());
      return;
    }
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _downloads?.addListener(_onDownloadsChanged);
    // 历史与播放位置是最能反映「看到哪」的两个信号：进详情页会写历史，
    // 播放器换集 / 拖动进度会写位置。任一变化都在 3 秒后重算一次卡片。
    _history?.addListener(_onProgressChanged);
    _positions?.addListener(_onProgressChanged);
    // 外观设置变化（背景/模糊/透明度/条数）要立刻反映到卡片。
    HomeWidgetSettingsStore.instance.addListener(_onProgressChanged);
    unawaited(refresh());
    // 卡片可能在本应用首帧之后才被系统创建（onAddForm 晚于首次刷新），
    // 2.5 秒后补推一次，避免用户看到「卡片已添加但内容空白」。
    Timer(const Duration(milliseconds: 2500), () {
      unawaited(refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 切后台时刷新：此时「刚看完的内容」进度已落盘，桌面卡片立即可见最新状态。
    if (state == AppLifecycleState.paused || state == AppLifecycleState.resumed) {
      unawaited(refresh());
    }
    // App 已在后台时点卡片 → 原生暂存目标 → 回前台消费。
    // 取走即清空，与首帧的消费不会重复跳转。
    if (state == AppLifecycleState.resumed) {
      final HistoryManager? history = _history;
      if (history != null) {
        unawaited(HomeWidgetLauncher.consumePending(history: history));
      }
    }
  }

  void _onDownloadsChanged() {
    // 下载进度回调非常密集（每个分片一次），统一延迟到安静后 1.5 秒再算。
    _downloadDebounce?.cancel();
    _downloadDebounce = Timer(const Duration(milliseconds: 1500), () {
      unawaited(refresh());
    });
  }

  void _onProgressChanged() {
    // 播放器保存位置的频率可达每几秒一次；卡片不需要那么灵，防抖 3 秒。
    _progressDebounce?.cancel();
    _progressDebounce = Timer(const Duration(seconds: 3), () {
      unawaited(refresh());
    });
  }

  /// 重新计算并推送快照。
  ///
  /// 并发保护：正在计算时只置一个「再算一次」标记，避免短时间内重复计算。
  Future<void> refresh() async {
    if (!_started || !HomeWidgetBridge.isSupported) return;
    if (_refreshing) {
      _refreshQueued = true;
      return;
    }
    _refreshing = true;
    try {
      // 取文案也放进 try：页面销毁后 context lookup 会抛错，等同「本次跳过」。
      final AppLocalizations? l10n = _localizations?.call();
      if (l10n == null) return;
      final HomeWidgetSnapshot snapshot = await _buildSnapshot(l10n);
      final int now = DateTime.now().millisecondsSinceEpoch;
      final HomeWidgetSnapshot? last = _lastSnapshot;
      if (last != null) {
        final Set<String> changed = _changedKeys(last, snapshot);
        // 内容没变就不写盘（切前后台很频繁，没必要每次覆盖同一份数据）。
        if (changed.isEmpty) return;
        // 只有下载进度在动时限频 60 秒：鸿蒙对 updateForm 有每日次数配额，
        // Android 侧频繁写盘也没意义——卡片上的百分比抖动肉眼无感。
        if (changed.length == 1 &&
            changed.contains('download_text') &&
            now - _lastPushMs < 60000) {
          return;
        }
      }
      _lastPushMs = now;
      _lastSnapshot = snapshot;
      await HomeWidgetBridge.push(snapshot);
    } on Object catch (e, st) {
      AppLog.instance.w('[桌面卡片] 刷新失败: $e\n$st');
    } finally {
      _refreshing = false;
      if (_refreshQueued) {
        _refreshQueued = false;
        // 下一次事件循环再算，保证读到刚写入的进度。
        unawaited(Future<void>.delayed(
          const Duration(milliseconds: 300),
          refresh,
        ));
      }
    }
  }

  /// 两份快照之间变化的键（忽略仅表示生成时间的 `updated_at`）。
  Set<String> _changedKeys(HomeWidgetSnapshot a, HomeWidgetSnapshot b) {
    final Map<String, Object?> before = a.toMap()..remove('updated_at');
    final Map<String, Object?> after = b.toMap()..remove('updated_at');
    final Set<String> changed = <String>{};
    for (final String key in before.keys) {
      if (before[key] != after[key]) changed.add(key);
    }
    return changed;
  }

  Future<HomeWidgetSnapshot> _buildSnapshot(AppLocalizations l10n) async {
    final HomeWidgetSettings settings = HomeWidgetSettingsStore.instance.settings;
    final List<ContinueItem> continues =
        await _pickContinues(l10n, settings.continueLimit);
    final int favoriteCount = _favoriteCount();
    final List<String> recentFavorites = _recentFavoriteTitles(3);
    final (int activeCount, int percent, String firstTitle) =
        _downloadSummary();
    final (int weekMinutes, int todayMinutes) = _minutes();
    final (int activeDays, int streak) = _activity();
    final (int novelWeek, int comicWeek, int mediaWeek) = _moduleMinutes();
    final ({bool isDark, ColorScheme scheme}) theme = _theme?.call() ??
        (isDark: false, scheme: const ColorScheme.light(primary: Color(0xFF0EA5E9)));
    // 背景图由 Flutter 预渲染（含模糊与透明度），原生只当图片显示。
    final String? bgPath = await HomeWidgetBackground.ensure(
      mode: settings.background,
      coverPath: continues.isEmpty ? null : continues.first.coverPath,
      blurSigma: settings.blurSigma,
      opacity: settings.opacity,
      isDark: theme.isDark,
      themeColor: theme.scheme.primary,
      // 卡片底色与 App 内 AppCard 同源（主色微染），保证观感一致。
      cardBg: AppTheme.cardContainer(theme.scheme),
    );
    // 每条记录的封面：转成 Base64 data URI（鸿蒙卡片只吃这种图片源）。
    final List<String> coverUris = <String>[];
    for (int i = 0; i < continues.length && i < 5; i++) {
      coverUris.add(await HomeWidgetThumb.dataUri(continues[i].coverPath));
    }
    final (int totalHours, int sessions, int dailyAvg) = _extraStats();
    final (String trendText, String trendUp) = _trend(l10n);
    final List<String> weekColors =
        _weekColors(theme.scheme.primary, theme.isDark);
    // 热力图：当月打卡月历（7 列周一~周日、月首偏移），PNG 透明底。
    final DateTime now = DateTime.now();
    final String? heatmapPath = await HomeWidgetHeatmap.ensure(
      monthDailyMinutes: _monthDailyMinutes(now),
      today: now.day,
      weekdayLabels: <String>[
        l10n.weekdayMon,
        l10n.weekdayTue,
        l10n.weekdayWed,
        l10n.weekdayThu,
        l10n.weekdayFri,
        l10n.weekdaySat,
        l10n.weekdaySun,
      ],
      legendLess: l10n.statsHeatmapLess,
      legendMore: l10n.statsHeatmapMore,
      themeColor: theme.scheme.primary,
      isDark: theme.isDark,
    );
    // 另一亮度的兜底套：系统在 App 没运行时切深浅色，卡片进程只能拿
    // 预先存好的两套。用当前主色作 seed 重生成，色调家族一致。
    final ColorScheme otherScheme = ColorScheme.fromSeed(
      seedColor: theme.scheme.primary,
      brightness: theme.isDark ? Brightness.light : Brightness.dark,
    );
    final ColorScheme lightScheme =
        theme.isDark ? otherScheme : theme.scheme;
    final ColorScheme darkScheme =
        theme.isDark ? theme.scheme : otherScheme;

    return HomeWidgetSnapshot(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      continues: continues,
      updateText: favoriteCount > 0
          ? l10n.homeWidgetUpdates(favoriteCount)
          : l10n.homeWidgetUpdatesIdle,
      recentFavorites: recentFavorites,
      downloadText: activeCount > 0
          ? l10n.homeWidgetDownloads(activeCount, percent)
          : l10n.homeWidgetDownloadsIdle,
      downloadTitle: firstTitle,
      statsText: weekMinutes > 0
          ? l10n.homeWidgetWeek(weekMinutes)
          : l10n.homeWidgetWeekIdle,
      todayText: todayMinutes > 0
          ? l10n.homeWidgetToday(todayMinutes)
          : l10n.homeWidgetTodayIdle,
      streakText: l10n.homeWidgetStreak(activeDays, streak),
      continueLabel: l10n.homeWidgetContinueLabel,
      updatesLabel: l10n.homeWidgetUpdatesLabel,
      downloadsLabel: l10n.homeWidgetDownloadsLabel,
      statsLabel: l10n.homeWidgetStatsLabel,
      bgPath: bgPath ?? '',
      bgColor: _bgColors(settings, theme).light,
      bgColorLight: _bgColors(settings, theme).light,
      bgColorDark: _bgColors(settings, theme).dark,
      // 与统计页卡片同源的底色（主色微染），原生直接用这个值铺卡。
      cardBg: _hex(AppTheme.cardContainer(theme.scheme)),
      textPrimary: _hex(theme.scheme.onSurface),
      textSecondary: _hex(theme.scheme.onSurfaceVariant),
      cardBgLight: _hex(AppTheme.cardContainer(lightScheme)),
      cardBgDark: _hex(AppTheme.cardContainer(darkScheme)),
      textPrimaryLight: _hex(lightScheme.onSurface),
      textPrimaryDark: _hex(darkScheme.onSurface),
      textSecondaryLight: _hex(lightScheme.onSurfaceVariant),
      textSecondaryDark: _hex(darkScheme.onSurfaceVariant),
      colorPrimaryLight: _hex(lightScheme.primary),
      colorPrimaryDark: _hex(darkScheme.primary),
      coverUris: coverUris,
      totalHours: totalHours,
      sessions: sessions,
      dailyAvgMinutes: dailyAvg,
      lifetimeText: l10n.widgetLifetimeHours(totalHours),
      sessionsText: l10n.widgetWeekSessions(sessions),
      trendText: trendText,
      trendUp: trendUp,
      colorPrimary: _hex(theme.scheme.primary),
      // 统计页三项配色是 primary / tertiary / secondary 轮转，这里给真值，
      // 卡片三项指标才和统计页同一套颜色。
      colorTertiary: _hex(theme.scheme.tertiary),
      colorSecondary: _hex(theme.scheme.secondary),
      weekColors: weekColors,
      workCount: _workCount(),
      labelTotal: l10n.statsTotalDuration,
      labelWorks: l10n.statsWorkCount,
      labelSessions: l10n.statsSessionCount,
      labelActive: l10n.statsActiveDays,
      heatmapPath: heatmapPath ?? '',
      heatmapUri: HomeWidgetHeatmap.lastBase64,
      weekMinutes: weekMinutes,
      todayMinutes: todayMinutes,
      streakDays: streak,
      activeDays: activeDays,
      novelWeek: novelWeek,
      comicWeek: comicWeek,
      mediaWeek: mediaWeek,
      labelNovel: l10n.navNovel,
      labelComic: l10n.navComic,
      labelMedia: l10n.navMedia,
      heatmapCaption: l10n.widgetHeatmapCaption,
      minuteUnit: l10n.widgetMinuteUnit,
      streakCaption: l10n.widgetStreakCaption,
      emptyTitle: l10n.homeWidgetEmptyTitle,
      emptyHint: l10n.homeWidgetEmptyHint,
    );
  }

  /// 取最近 N 条「继续观看」，副标题用**真实进度**而不是历史里的旧章节名。
  ///
  /// 历史只在进入详情页时写入，播放器内换集不会更新它；进度管理器才是「看到哪」
  /// 的唯一真相，所以副标题优先按进度拼装，取不到时回退历史记录。
  /// 媒体服务器（Emby/Jellyfin）条目跳过：其详情页需要服务器登录态。
  Future<List<ContinueItem>> _pickContinues(
    AppLocalizations l10n,
    int limit,
  ) async {
    final HistoryManager? history = _history;
    if (history == null) return const <ContinueItem>[];
    final List<HistoryEntry> entries = <HistoryEntry>[];
    for (final SourceType type in SourceType.values) {
      for (final HistoryEntry e in history.historyFor(type)) {
        if (e.hidden) continue;
        if (e.kind == 'mediaServer') continue;
        entries.add(e);
      }
    }
    entries.sort((HistoryEntry a, HistoryEntry b) => b.viewedAt - a.viewedAt);
    final List<HistoryEntry> picked = entries.take(limit).toList();
    return Future.wait(picked.map((HistoryEntry e) async {
      return ContinueItem(
        title: e.title,
        subtitle: await _progressText(e, l10n),
        coverPath: e.localCoverPath ?? '',
      );
    }));
  }

  /// 单条作品的进度文案。
  Future<String> _progressText(HistoryEntry e, AppLocalizations l10n) async {
    final String fallback = e.lastChapter ?? '';
    try {
      switch (e.sourceType) {
        case SourceType.animeSource:
          final MediaPlaybackPositionManager? positions = _positions;
          if (positions == null) return fallback;
          final int index = positions.getLastEpisode(e.id);
          if (index < 0) return fallback;
          final int minutes =
              (positions.getPosition(e.id, index) / 60000).round();
          return minutes > 0
              ? l10n.homeWidgetEpisodeProgress(index + 1, minutes)
              : l10n.homeWidgetEpisodeWatched(index + 1);
        case SourceType.mangaSource:
          final ReadingProgress? p = await ComicProgressManager().get(e.id);
          if (p == null) return fallback;
          final int total = p.totalChapters ?? 0;
          return total > 0
              ? l10n.homeWidgetChapterProgress(p.chapterIndex + 1, total)
              : l10n.homeWidgetChapterProgressOpen(p.chapterIndex + 1);
        case SourceType.novelSource:
          final NovelReadingProgress? p =
              await NovelProgressManager().get(e.id);
          if (p == null) return fallback;
          final int total = p.totalChapters ?? 0;
          return total > 0
              ? l10n.homeWidgetChapterProgress(p.chapterIndex + 1, total)
              : l10n.homeWidgetChapterProgressOpen(p.chapterIndex + 1);
      }
    } on Object {
      // 进度读取失败（存储未就绪等）不阻塞卡片：退回历史里的章节名。
      return fallback;
    }
  }

  int _favoriteCount() {
    final FavoritesManager? favorites = _favorites;
    if (favorites == null) return 0;
    var total = 0;
    for (final SourceType type in SourceType.values) {
      total += favorites.visibleFavoritesFor(type).length;
    }
    return total;
  }

  /// 最近收藏的 N 个标题（追更卡列表用；收藏列表本身按收藏时间倒序）。
  List<String> _recentFavoriteTitles(int limit) {
    final FavoritesManager? favorites = _favorites;
    if (favorites == null) return const <String>[];
    final List<String> titles = <String>[];
    for (final SourceType type in SourceType.values) {
      for (final FavoriteEntry e in favorites.visibleFavoritesFor(type)) {
        titles.add(e.title);
      }
    }
    return titles.take(limit).toList();
  }

  /// 返回（活跃任务数, 整体完成百分比, 首个活跃任务标题）。
  (int, int, String) _downloadSummary() {
    final DownloadManager? downloads = _downloads;
    if (downloads == null) return (0, 0, '');
    final active = downloads.activeTasks;
    if (active.isEmpty) return (0, 0, '');
    var done = 0;
    var total = 0;
    for (final task in active) {
      total += task.totalChapters;
      done += task.downloadedChapters;
    }
    final int percent = total > 0 ? ((done * 100) / total).round() : 0;
    return (active.length, percent, active.first.title);
  }

  /// 近 7 天与今天（含）的阅读 + 观看分钟数。
  (int, int) _minutes() {
    final DateTime now = DateTime.now();
    final List<DailyReadingStats> days = StatsRepository.instance
        .dailyForRange(now.subtract(const Duration(days: 6)), now);
    final String todayKey = DailyReadingStats.dayKeyFromTimestamp(
      now.millisecondsSinceEpoch,
    );
    var weekSeconds = 0;
    var todaySeconds = 0;
    for (final DailyReadingStats d in days) {
      final int sec =
          d.mediaDurationSec + d.comicDurationSec + d.novelDurationSec;
      weekSeconds += sec;
      if (d.day == todayKey) todaySeconds = sec;
    }
    return ((weekSeconds / 60).round(), (todaySeconds / 60).round());
  }

  /// 返回（近 7 天活跃天数, 当前连续天数）。连续天数取三模块最大值。
  (int, int) _activity() {
    final DateTime now = DateTime.now();
    final List<DailyReadingStats> days = StatsRepository.instance
        .dailyForRange(now.subtract(const Duration(days: 6)), now);
    var activeDays = 0;
    for (final DailyReadingStats d in days) {
      if (d.mediaDurationSec + d.comicDurationSec + d.novelDurationSec > 0) {
        activeDays++;
      }
    }
    final StatsRepository repo = StatsRepository.instance;
    final int streak = <int>[
      repo.currentStreak(StatsMediaType.media),
      repo.currentStreak(StatsMediaType.comic),
      repo.currentStreak(StatsMediaType.novel),
    ].reduce((int a, int b) => a > b ? a : b);
    return (activeDays, streak);
  }

  /// 累计时长（小时）、本周会话数、本周日均分钟 —— 与统计页口径一致。
  (int, int, int) _extraStats() {
    final DateTime now = DateTime.now();
    final List<DailyReadingStats> days = StatsRepository.instance
        .dailyForRange(now.subtract(const Duration(days: 6)), now);
    var weekSeconds = 0;
    var sessions = 0;
    for (final DailyReadingStats d in days) {
      weekSeconds +=
          d.mediaDurationSec + d.comicDurationSec + d.novelDurationSec;
      sessions += d.sessionCount;
    }
    final int total = StatsRepository.instance.totalDurationSec();
    return ((total / 3600).round(), sessions, (weekSeconds / 60 / 7).round());
  }

  /// Color → `#AARRGGBB`。
  String _hex(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

  /// 作品数：三类历史里去重后的条目数（与统计页「作品数」口径接近）。
  int _workCount() {
    final HistoryManager? history = _history;
    if (history == null) return 0;
    final Set<String> ids = <String>{};
    for (final SourceType type in SourceType.values) {
      for (final HistoryEntry e in history.historyFor(type)) {
        if (e.kind == 'mediaServer') continue;
        ids.add('${e.sourceType.name}:${e.id}');
      }
    }
    return ids.length;
  }

  /// 本周相对上周的时长变化（同为 7 天窗口）。
  (String, String) _trend(AppLocalizations l10n) {
    final DateTime now = DateTime.now();
    final List<DailyReadingStats> thisWeek = StatsRepository.instance
        .dailyForRange(now.subtract(const Duration(days: 6)), now);
    final List<DailyReadingStats> lastWeek = StatsRepository.instance
        .dailyForRange(
      now.subtract(const Duration(days: 13)),
      now.subtract(const Duration(days: 7)),
    );
    int sum(List<DailyReadingStats> days) {
      var total = 0;
      for (final DailyReadingStats d in days) {
        total += d.mediaDurationSec + d.comicDurationSec + d.novelDurationSec;
      }
      return total;
    }

    final int current = sum(thisWeek);
    final int previous = sum(lastWeek);
    if (previous == 0) {
      return (current > 0 ? l10n.widgetTrendNew : l10n.widgetTrendFlat, '1');
    }
    final int percent = ((current - previous) * 100 / previous).round();
    if (percent == 0) return (l10n.widgetTrendFlat, '0');
    final String text =
        percent > 0 ? l10n.widgetTrendUp(percent) : l10n.widgetTrendDown(-percent);
    return (text, percent > 0 ? '1' : '0');
  }

  /// 最近 7 天的强度色：时长越久越接近主题色，0 分钟给极淡底。
  List<String> _weekColors(Color primary, bool isDark) {
    final List<int> minutes = _dailyMinutes();
    final List<int> last7 =
        minutes.length >= 7 ? minutes.sublist(minutes.length - 7) : minutes;
    final int maxMinutes = last7.isEmpty
        ? 0
        : last7.reduce((int a, int b) => a > b ? a : b);
    final List<String> out = <String>[];
    for (final int m in last7) {
      final double alpha = m <= 0 || maxMinutes <= 0
          ? (isDark ? 0.14 : 0.10)
          : (0.30 + 0.65 * (m / maxMinutes)).clamp(0.30, 0.95);
      // 半透明：叠在卡片底色上，深浅色都能看。
      final Color c = primary.withValues(alpha: alpha);
      out.add('#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}');
    }
    return out;
  }

  /// 卡片主题色层，浅色/深色各一套（`#AARRGGBB`，**半透明**）。
  ///
  /// 为什么两套：系统切深浅色时 Flutter 不一定会重算，所以由 FormExtensionAbility
  /// 的 onConfigurationUpdate 按当前 colorMode 选一套重推卡片 —— 这样不依赖 App 运行。
  ({String light, String dark}) _bgColors(
    HomeWidgetSettings settings,
    ({bool isDark, ColorScheme scheme}) theme,
  ) {
    if (settings.background == WidgetBackgroundMode.none) {
      return (light: '#00000000', dark: '#00000000');
    }
    // 深色下主题色浓度略低，避免整卡偏亮。
    final double base = 0.12 + settings.opacity * 0.43;
    final String l =
        _hex(theme.scheme.primary.withValues(alpha: base.clamp(0.0, 0.6)));
    final String d = _hex(
      theme.scheme.primary.withValues(alpha: (base * 0.72).clamp(0.0, 0.5)),
    );
    return (light: l, dark: d);
  }

  /// 当月每日分钟数（index = 日期 - 1，长度 = 当月天数），热力图月历用。
  List<int> _monthDailyMinutes(DateTime now) {
    final int daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final List<DailyReadingStats> days =
        StatsRepository.instance.dailyForRange(DateTime(now.year, now.month, 1), now);
    final Map<String, DailyReadingStats> byDay = <String, DailyReadingStats>{
      for (final DailyReadingStats d in days) d.day: d,
    };
    return <int>[
      for (int i = 1; i <= daysInMonth; i++)
        () {
          final DateTime t = DateTime(now.year, now.month, i);
          final DailyReadingStats? d =
              byDay[DailyReadingStats.dayKeyFromTimestamp(t.millisecondsSinceEpoch)];
          if (d == null) return 0;
          return (d.mediaDurationSec + d.comicDurationSec + d.novelDurationSec) ~/ 60;
        }(),
    ];
  }

  /// 本周分模块时长（小说, 漫画, 影视），单位分钟。
  (int, int, int) _moduleMinutes() {
    final DateTime now = DateTime.now();
    final List<DailyReadingStats> days = StatsRepository.instance
        .dailyForRange(now.subtract(const Duration(days: 6)), now);
    var novel = 0;
    var comic = 0;
    var media = 0;
    for (final DailyReadingStats d in days) {
      novel += d.novelDurationSec;
      comic += d.comicDurationSec;
      media += d.mediaDurationSec;
    }
    return ((novel / 60).round(), (comic / 60).round(), (media / 60).round());
  }

  /// 近 30 天每日总分钟数（按日期升序，最后一格是今天）。
  /// 近 7 天每日分钟数（周趋势色条用，按日期升序，最后一格是今天）。
  List<int> _dailyMinutes() {
    final DateTime now = DateTime.now();
    final List<DailyReadingStats> days = StatsRepository.instance
        .dailyForRange(now.subtract(const Duration(days: 29)), now);
    final Map<String, DailyReadingStats> byDay = <String, DailyReadingStats>{
      for (final DailyReadingStats d in days) d.day: d,
    };
    const int span = 30;
    final List<int> out = <int>[];
    for (int i = span - 1; i >= 0; i--) {
      final DateTime t = now.subtract(Duration(days: i));
      final String key =
          DailyReadingStats.dayKeyFromTimestamp(t.millisecondsSinceEpoch);
      final DailyReadingStats? d = byDay[key];
      final int sec = d == null
          ? 0
          : d.mediaDurationSec + d.comicDurationSec + d.novelDurationSec;
      out.add((sec / 60).round());
    }
    return out;
  }
}
