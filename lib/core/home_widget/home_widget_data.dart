/// 桌面卡片（系统级小组件）数据快照。
///
/// 卡片 UI 全部由原生绘制（Android RemoteViews / 鸿蒙 ArkTS Form），Flutter 只
/// 负责算出「要显示什么」，通过原生键值存储交给系统。因此这里的键名就是与原生
/// 约定的存储键名，改动必须同步三处：
///
/// * `android/app/src/main/kotlin/com/nexhub/app/NexHubWidgetProvider.kt`
/// * `ohos/entry/src/main/ets/widget/HomeWidgetStore.ets`
/// * `ohos/entry/src/main/ets/widget/pages/*.ets`
///
/// 一份快照同时喂多种卡片（继续观看 / 追更 / 下载 / 统计 / 总览），各卡只读自己
/// 关心的键，避免为每种卡单独算一遍数据。
///
/// 全部值序列化为字符串：Android SharedPreferences 与鸿蒙 preferences 对数值
/// 类型（Int / Long）处理不一致，统一字符串可避免 ClassCastException。
library;

/// 单条「继续观看」记录（最多保留 3 条，供大卡列表使用）。
class ContinueItem {
  final String title;

  /// 真实进度文案（如「第 12 话 · 共 303 话」「第 5 集 · 已看 12 分钟」）。
  final String subtitle;

  /// 封面本地文件绝对路径；空串表示无封面。
  final String coverPath;

  const ContinueItem({
    required this.title,
    required this.subtitle,
    required this.coverPath,
  });

  static const ContinueItem empty =
      ContinueItem(title: '', subtitle: '', coverPath: '');
}

/// 卡片展示所需的全部数据（一次刷新算一份，整份覆盖写入）。
class HomeWidgetSnapshot {
  /// 快照生成时间（毫秒）。
  final int updatedAt;

  /// 继续观看（最近 3 条，按时间倒序；可为空列表）。
  final List<ContinueItem> continues;

  /// 追更摘要（如「追更 · 收藏 32 部」）。
  final String updateText;

  /// 最近收藏的 3 个标题（追更卡列表用）。
  final List<String> recentFavorites;

  /// 下载摘要（如「下载 · 2 个任务 46%」）与首个活跃任务标题。
  final String downloadText;
  final String downloadTitle;

  /// 本周 / 今日统计。
  final String statsText;
  final String todayText;

  /// 活跃天数与连续天数（如「活跃 5 天 · 连续 3 天」）。
  final String streakText;

  /// 小节标题（由 Dart 按当前语言给出，原生不硬编码文案）。
  final String continueLabel;
  final String updatesLabel;
  final String downloadsLabel;
  final String statsLabel;

  /// 卡片背景图绝对路径（Dart 预渲染好的不透明 PNG）；空串表示无背景。
  final String bgPath;

  /// 近 30 天热力图 PNG 路径；空串表示未生成。
  final String heatmapPath;

  /// 热力图的 Base64 data URI（鸿蒙卡片只能吃这种图片源）。
  final String heatmapUri;

  /// 主题三色，统计卡按统计页的配色分列显示。
  final String colorPrimary;
  final String colorTertiary;
  final String colorSecondary;

  /// 卡片纯色背景（`#AARRGGBB`）。鸿蒙卡片无法接收动态图片，用这个上色；
  /// Android 走背景图，忽略该字段。
  final String bgColor;

  /// 卡片底色（= App 内 `AppTheme.cardContainer`，主题色淡淡染过一层）。
  /// 原生侧没有 ColorScheme，只能吃这个值；它与统计页卡片同源，保证观感一致。
  final String cardBg;

  /// 正文色 / 次要文字色（= onSurface / onSurfaceVariant，App 当前主题）。
  /// 与 [cardBg] 出自同一份快照，对比度始终成立。
  final String textPrimary;
  final String textSecondary;

  /// 浅色 / 深色两套主题层（底色、正文、次要、强调）。
  ///
  /// 鸿蒙 FormAbility 在系统切深浅色时按 colorMode 选用（App 可能没在跑，
  /// 不能依赖它重算）；Android 卡片用当前主题一套，另一套作为切换兜底。
  /// 两套都用 seed 重新生成 —— 色调家族一致，深浅正确性优先于精确复刻。
  final String cardBgLight;
  final String cardBgDark;
  final String textPrimaryLight;
  final String textPrimaryDark;
  final String textSecondaryLight;
  final String textSecondaryDark;
  final String colorPrimaryLight;
  final String colorPrimaryDark;

  /// 浅色 / 深色两套主题色层，由 FormAbility 按系统 colorMode 选用。
  final String bgColorLight;
  final String bgColorDark;

  /// 每条记录的封面缩略图（Base64 data URI，最多 5 条）。
  ///
  /// 鸿蒙卡片只认 `$r()` / `$rawfile()` / Base64 三种图片源，所以封面必须这样传。
  final List<String> coverUris;

  /// 统计类卡片用的原始数值（卡片要放大数字，不能只靠拼好的文案）。
  final int weekMinutes;
  final int todayMinutes;
  final int streakDays;
  final int activeDays;

  /// 分模块本周时长（分钟）。
  final int novelWeek;
  final int comicWeek;
  final int mediaWeek;

  /// 累计时长（小时）、本周会话数、本周日均分钟。
  final int totalHours;
  final int sessions;
  final int dailyAvgMinutes;

  /// 统计补充文案（已含单位，卡片直接显示）。
  final String lifetimeText;
  final String sessionsText;

  /// 本周相对上周的变化文案（如「+12%」「-8%」「持平」）。
  final String trendText;

  /// 趋势方向：'1' 上升 / '0' 持平或下降（卡片据此选箭头与颜色）。
  final String trendUp;

  /// 最近 7 天强度色（`#AARRGGBB`，7 个），给统计卡的色条用。
  final List<String> weekColors;

  /// 统计概览四宫格：作品数 + 四个指标名（与统计页同一套文案）。
  final int workCount;
  final String labelTotal;
  final String labelWorks;
  final String labelSessions;
  final String labelActive;

  /// 模块名（来自 l10n，原生不硬编码）。
  final String labelNovel;
  final String labelComic;
  final String labelMedia;
  final String heatmapCaption;
  final String minuteUnit;
  final String streakCaption;

  /// 空状态标题 / 说明。
  final String emptyTitle;
  final String emptyHint;

  const HomeWidgetSnapshot({
    required this.updatedAt,
    required this.continues,
    required this.updateText,
    required this.recentFavorites,
    required this.downloadText,
    required this.downloadTitle,
    required this.statsText,
    required this.todayText,
    required this.streakText,
    required this.continueLabel,
    required this.updatesLabel,
    required this.downloadsLabel,
    required this.statsLabel,
    required this.bgPath,
    required this.heatmapPath,
    required this.heatmapUri,
    required this.colorPrimary,
    required this.colorTertiary,
    required this.colorSecondary,
    required this.bgColor,
    required this.cardBg,
    required this.textPrimary,
    required this.textSecondary,
    required this.cardBgLight,
    required this.cardBgDark,
    required this.textPrimaryLight,
    required this.textPrimaryDark,
    required this.textSecondaryLight,
    required this.textSecondaryDark,
    required this.colorPrimaryLight,
    required this.colorPrimaryDark,
    required this.bgColorLight,
    required this.bgColorDark,
    required this.coverUris,
    required this.totalHours,
    required this.sessions,
    required this.dailyAvgMinutes,
    required this.lifetimeText,
    required this.sessionsText,
    required this.trendText,
    required this.trendUp,
    required this.weekColors,
    required this.workCount,
    required this.labelTotal,
    required this.labelWorks,
    required this.labelSessions,
    required this.labelActive,
    required this.weekMinutes,
    required this.todayMinutes,
    required this.streakDays,
    required this.activeDays,
    required this.novelWeek,
    required this.comicWeek,
    required this.mediaWeek,
    required this.labelNovel,
    required this.labelComic,
    required this.labelMedia,
    required this.heatmapCaption,
    required this.minuteUnit,
    required this.streakCaption,
    required this.emptyTitle,
    required this.emptyHint,
  });

  /// 第 0 条继续观看（小卡 / 中卡单条展示用）。
  ContinueItem get primary =>
      continues.isEmpty ? ContinueItem.empty : continues.first;

  /// 转成扁平键值（原生侧直接按 key 读，不做 JSON 解析）。
  Map<String, Object?> toMap() {
    final Map<String, Object?> map = <String, Object?>{
      'updated_at': '$updatedAt',
      'has_continue': continues.isEmpty ? '0' : '1',
      'continue_count': '${continues.length}',
      // 兼容键：指向第 0 条，小卡与旧布局直接读这几个。
      'continue_title': primary.title,
      'continue_subtitle': primary.subtitle,
      'continue_cover_path': primary.coverPath,
      'update_text': updateText,
      'download_text': downloadText,
      'download_title': downloadTitle,
      'stats_text': statsText,
      'today_text': todayText,
      'streak_text': streakText,
      'label_continue': continueLabel,
      'label_updates': updatesLabel,
      'label_downloads': downloadsLabel,
      'label_stats': statsLabel,
      'bg_path': bgPath,
      'heatmap_path': heatmapPath,
      'heatmap_b64': heatmapUri,
      'color_primary': colorPrimary,
      'color_tertiary': colorTertiary,
      'color_secondary': colorSecondary,
      'bg_color': bgColor,
      'card_bg': cardBg,
      'text_primary': textPrimary,
      'text_secondary': textSecondary,
      'card_bg_light': cardBgLight,
      'card_bg_dark': cardBgDark,
      'text_primary_light': textPrimaryLight,
      'text_primary_dark': textPrimaryDark,
      'text_secondary_light': textSecondaryLight,
      'text_secondary_dark': textSecondaryDark,
      'color_primary_light': colorPrimaryLight,
      'color_primary_dark': colorPrimaryDark,
      'bg_color_light': bgColorLight,
      'bg_color_dark': bgColorDark,
      'stats_week_minutes': '$weekMinutes',
      'stats_today_minutes': '$todayMinutes',
      'stats_streak_days': '$streakDays',
      'stats_active_days': '$activeDays',
      'novel_week_minutes': '$novelWeek',
      'comic_week_minutes': '$comicWeek',
      'media_week_minutes': '$mediaWeek',
      'label_novel': labelNovel,
      'label_comic': labelComic,
      'label_media': labelMedia,
      'heatmap_caption': heatmapCaption,
      'minute_unit': minuteUnit,
      'streak_caption': streakCaption,
      'stats_total_hours': '$totalHours',
      'stats_sessions': '$sessions',
      'stats_daily_avg': '$dailyAvgMinutes',
      'lifetime_text': lifetimeText,
      'sessions_text': sessionsText,
      'trend_text': trendText,
      'trend_up': trendUp,
      'stats_work_count': '$workCount',
      'label_total': labelTotal,
      'label_works': labelWorks,
      'label_sessions': labelSessions,
      'label_active': labelActive,
      'empty_title': emptyTitle,
      'empty_hint': emptyHint,
    };
    // 固定槽位：原生布局是静态的（Android RemoteViews 无法动态增删行），
    // 多出来的条目在这里截断；Android 大卡只画前 4 条，鸿蒙按条数动态渲染。
    for (int i = 0; i < maxSlots; i++) {
      final ContinueItem item =
          i < continues.length ? continues[i] : ContinueItem.empty;
      map['continue_${i}_title'] = item.title;
      map['continue_${i}_subtitle'] = item.subtitle;
      map['continue_${i}_cover'] = item.coverPath;
      // 卡片能用的图片源：Base64 data URI（文件路径在卡片进程里读不到）。
      map['continue_${i}_cover_b64'] =
          i < coverUris.length ? coverUris[i] : '';
    }
    for (int i = 0; i < 7; i++) {
      map['day_${i}_color'] =
          i < weekColors.length ? weekColors[i] : '#00000000';
    }
    for (int i = 0; i < maxFavoriteSlots; i++) {
      map['favorite_$i'] = i < recentFavorites.length ? recentFavorites[i] : '';
    }
    return map;
  }

  /// 继续观看槽位上限（设置里 3~8，这里按最大值铺满，原生取自己需要的条数）。
  static const int maxSlots = 8;

  /// 最近收藏槽位上限。
  static const int maxFavoriteSlots = 3;
}
