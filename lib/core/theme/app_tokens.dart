import 'package:material_ui/material_ui.dart';

/// 统一设计 Token —— 应用中所有颜色、间距、圆角、阴影、时长的**唯一**来源。
///
/// 治理规则（见 docs/DESIGN_SYSTEM.md）：
/// - feature 代码**禁止**硬编码 `Color(0xFF…)`、`EdgeInsets.all(8)` 等魔法数字。
/// - 颜色统一取 `Theme.of(context).colorScheme`（由 seed 生成，深浅色自适应）。
/// - 间距 / 圆角 / 时长取本文件常量。
/// - 随深浅色变化的派生值（阴影、渐变）通过 [AppShadows] / [AppGradients] 取得。
class AppTokens {
  AppTokens._();

  // ─────────────────────── 语义色板（用于生成 ColorScheme / 强调色） ───────────────────────
  /// 保留预设：浅蓝（旧脚手架配色，可选；应用默认主色为 [seedYouthfulPrimary] #0EA5E9）。
  static const Color seedLightBlue = Color(0xFF5B9BD5);

  /// 文档「青春活力」预设主色：蓝青。
  static const Color seedYouthfulPrimary = Color(0xFF0EA5E9);

  /// 文档「青春活力」预设强调：珊瑚。
  static const Color seedYouthfulAccent = Color(0xFFF43F5E);

  // ── 中国传统色预设（设置页「预设颜色」切换）──
  // 色值考据：天水碧/群青/玄色 取自 zhongguose.com；茶红/桃夭/朱殷 站点无对应名，
  // 取郭浩《中国传统色》权威本意值（茶红→茶色 #B35C44、桃夭 #F6BEC8、朱殷 #B93A26）。
  static const Color seedChaHong = Color(0xFFB35C44); // 茶红：赤褐温润，如茶汤（郭浩《中国传统色》#B35C44，站点无"茶红"）
  static const Color seedTaoYao = Color(0xFFF6BEC8); // 桃夭：《诗经》桃之夭夭，娇嫩桃粉（郭浩《中国传统色》#F6BEC8）
  static const Color seedTianShuiBi = Color(0xFFAED9D4); // 天水碧：南唐露染浅碧（zhongguose.com #AED9D4）
  static const Color seedZhuYin = Color(0xFFB93A26); // 朱殷：深朱近殷，庄重赤红（郭浩《中国传统色》#B93A26）
  static const Color seedQunQing = Color(0xFF1772B4); // 群青：青蓝沉静（zhongguose.com #1772b4）
  static const Color seedXuanSe = Color(0xFF1A1A1A); // 玄色：黑中扬赤，天地玄黄之玄（zhongguose.com #1A1A1A，取"玄=黑"释义）
  static const Color seedXuanSeAccent = Color(0xFFC2453B); // 玄色主题强调"赤"（黑中扬赤）
  static const Color xuanSeInk = Color(0xFF0E0E0E); // 玄色主题近黑背景

  /// 可选预设主色（设置页切换 / 自定义取色）。
  /// 每项含 `色值` 与 `中文名`，中文名用于色板 Tooltip 展示。
  static const List<(Color, String)> presetSeeds = <(Color, String)>[
    (seedLightBlue, '浅蓝'),
    (seedYouthfulPrimary, '青春蓝'),
    (Color(0xFF6750A4), '默认紫'), // 默认紫
    (Color(0xFF26A69A), '青绿'),
    (Color(0xFFEF6C00), '橙'),
    (seedChaHong, '茶红'),
    (seedTaoYao, '桃夭'),
    (seedTianShuiBi, '天水碧'),
    (seedZhuYin, '朱殷'),
    (seedQunQing, '群青'),
    (seedXuanSe, '玄色'),
  ];

  // ─────────────────────── 间距（Spacing） ───────────────────────
  static const double spaceNone = 0;

  /// 微间距：徽章内衬、密排文本行间距等 2px 级微调（小于 [spaceXs]）。
  static const double spaceXxs = 2;
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 24;
  static const double space2xl = 32;
  static const double space3xl = 48;

  // ─────────────────────── 圆角（Radius） ───────────────────────
  static const double radiusNone = 0;

  /// 超小圆角：进度条、微型徽章等 4px 级圆角（小于 [radiusSm]）。
  static const double radiusXs = 4;
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 24;
  static const double radiusFull = 999;

  // ─────────────────────── 时长（Durations） ───────────────────────
  static const Duration durFast = Duration(milliseconds: 150);
  static const Duration durBase = Duration(milliseconds: 250);
  /// 弹簧入场时长：比 [durBase] 略长，给回弹过冲留出自然回落时间，更「灵动」。
  static const Duration durSpring = Duration(milliseconds: 420);
  /// 翻页动画统一 450ms（见文档附录 C）。
  static const Duration durPageTurn = Duration(milliseconds: 450);

  /// 慢入场时长：作品卡划入显现等需要从容感的入场，比 [durSpring] 更缓。
  static const Duration durSlow = Duration(milliseconds: 600);

  // ─────────────────────── 组件固定尺寸 ───────────────────────
  static const double coverAspectRatio = 0.7; // 封面宽高比（漫画/小说）

  /// 阅读器设置弹窗最大高度占屏比（小说 / 漫画共用，保证两处高度同步）。
  static const double readerSettingsMaxHeightFactor = 0.85;
  static const double coverRadius = radiusMd;
  static const double iconButtonSize = 40;
  static const double tabBarHeight = 56;
  static const double bottomNavHeight = 68;

  /// 侧边导航栏（Rail）每项固定高度，避免在宽屏把整屏均分导致过散。
  static const double navRailItemHeight = 72;

  /// 侧边导航栏（Rail）固定宽度（≥桌面断点时使用）。
  static const double navRailWidth = 80;

  // ─────────────────────── 毛玻璃（Glass bars） ───────────────────────
  /// 玻璃栏位（侧栏/底栏）高斯模糊强度（sigma）。
  static const double blurSigma = 18;

  /// 玻璃栏位半透明底色不透明度（浅色主题）。
  ///
  /// 值越高栏位越"实"：需保证栏上图标文字对比度，同时让身后的
  /// 滚动内容隐约可见。深色主题背景本就偏暗，用更低的值让模糊更可感。
  static const double glassTintLight = 0.78;
  static const double glassTintDark = 0.60;

  // ─────────────────────── 响应式断点 ───────────────────────
  /// 桌面布局断点（≥ 此宽度使用 NavigationRail）。
  static const double desktopBreakpoint = 840;

  /// 紧凑布局断点（Material 3 compact/medium 分界）。
  /// 宽度 < 此值时详情页头部改用「chips / 按钮下移全宽」的窄屏布局。
  static const double compactBreakpoint = 600;

  /// 双栏详情断点（≥ 此宽度详情在右侧栏打开而非整页路由）。
  /// 1120 = 侧栏 80 + 列表可用 640 + 详情栏最窄 400。
  static const double twoPaneBreakpoint = 1120;
}

/// 阴影 Token（随 ColorScheme 自适应，禁止写死颜色）。
class AppShadows {
  AppShadows._();

  /// 卡片阴影（轻）。
  static List<BoxShadow> card(ColorScheme scheme) => <BoxShadow>[
        BoxShadow(
          color: scheme.shadow.withValues(alpha: 0.08),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  /// 封面阴影（中）。
  static List<BoxShadow> cover(ColorScheme scheme) => <BoxShadow>[
        BoxShadow(
          color: scheme.shadow.withValues(alpha: 0.18),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  /// 悬浮阴影（重）。
  static List<BoxShadow> elevated(ColorScheme scheme) => <BoxShadow>[
        BoxShadow(
          color: scheme.shadow.withValues(alpha: 0.12),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];
}

/// 语义状态色 Token（成功 / 警告 / 失败）。
///
/// Material 3 的 `ColorScheme` 只有 `error`，没有 success / warning 槽位，
/// 因此这三档在此统一定义；feature 代码禁止直接写 `Colors.green` 等。
/// 深浅色各取一档，保证在对应背景上的可读对比度。
class AppStatusColors {
  AppStatusColors._();

  // 每档两个色值：深背景用亮色，浅背景用深色，保证对比度。
  static const Color _okOnLight = Color(0xFF1B873F);
  static const Color _okOnDark = Color(0xFF6EE7A8);
  static const Color _warnOnLight = Color(0xFFB26A00);
  static const Color _warnOnDark = Color(0xFFF6C560);
  static const Color _failOnLight = Color(0xFFB3261E);
  static const Color _failOnDark = Color(0xFFF2B8B5);

  /// 判断目标背景是否为深色。
  ///
  /// [onInverseSurface] 为 true 时表示绘制在 `scheme.inverseSurface` 上
  /// （SnackBar 等反色容器），亮度与应用主题相反。
  static bool _darkBackground(ColorScheme scheme, bool onInverseSurface) {
    final bool appIsDark = scheme.brightness == Brightness.dark;
    return onInverseSurface ? !appIsDark : appIsDark;
  }

  /// 成功 / 健康 / 可用。
  static Color ok(ColorScheme scheme, {bool onInverseSurface = false}) =>
      _darkBackground(scheme, onInverseSurface) ? _okOnDark : _okOnLight;

  /// 警告 / 一般 / 需注意。
  static Color warn(ColorScheme scheme, {bool onInverseSurface = false}) =>
      _darkBackground(scheme, onInverseSurface) ? _warnOnDark : _warnOnLight;

  /// 失败 / 不可用。普通表面复用主题 `error`，与其他错误态保持一致。
  static Color fail(ColorScheme scheme, {bool onInverseSurface = false}) {
    if (!onInverseSurface) return scheme.error;
    return _darkBackground(scheme, true) ? _failOnDark : _failOnLight;
  }

  /// 状态徽章底色：对应状态色的低透明度填充。
  static Color containerOf(Color statusColor) =>
      statusColor.withValues(alpha: 0.12);
}

/// 渐变 Token（随 ColorScheme 自适应）。
class AppGradients {
  AppGradients._();

  /// 表面渐变（顶部 surface → 底部 surfaceContainerHighest）。
  static LinearGradient surface(ColorScheme scheme) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          scheme.surface,
          scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        ],
      );

  /// Hero 渐变（primary → tertiary）。
  static LinearGradient hero(ColorScheme scheme) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[scheme.primary, scheme.tertiary],
      );
}
