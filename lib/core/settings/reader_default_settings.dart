/// 阅读器默认设置模型（全局默认值，阅读时可临时覆盖）。
///
/// 持久化到 SharedPreferences（key: `reader_default_settings_v1`），
/// 复用 [PrefsBackend] 抽象以便测试注入。
library;

import 'dart:convert';

import '../comic/models/reader_preferences.dart';
import '../comic/models/motion_effect_settings.dart';
import '../comic/manga_upscale.dart';
import '../novel/novel_page_animation.dart';
import '../novel/novel_reader_preferences.dart';

/// 解析闪光颜色（容错：非法字符串回退黑）。
/// 注意：reader_preferences.dart 中的同名私有函数对本库不可见，这里本地实现一份。
ReaderFlashColor _parseFlashColor(Object? raw) {
  if (raw is String) {
    return ReaderFlashColor.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => ReaderFlashColor.black,
    );
  }
  return ReaderFlashColor.black;
}

/// 解析长按缩放锚点（容错：非法字符串回退 press）。
LongPressZoomPosition _parseLongPressZoomPosition(Object? raw) {
  if (raw is String) {
    return LongPressZoomPosition.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => LongPressZoomPosition.press,
    );
  }
  return LongPressZoomPosition.press;
}

/// 解析缩放锚点（容错：非法字符串回退 center）。
ZoomStart _parseZoomStart(Object? raw) {
  if (raw is String) {
    return ZoomStart.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => ZoomStart.center,
    );
  }
  return ZoomStart.center;
}

/// 解析翻页过渡动画（容错：非法字符串回退 slide）。
ReaderPageAnimation _parsePageAnimation(Object? raw) {
  if (raw is String) {
    return ReaderPageAnimation.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => ReaderPageAnimation.slide,
    );
  }
  return ReaderPageAnimation.slide;
}

/// 解析时间/电量浮层位置（容错：非法字符串回退 top）。
ClockBatteryPosition _parseClockBatteryPosition(Object? raw) {
  if (raw is String) {
    // 兼容旧数据：top → topLeft, bottom → bottomLeft
    final String mapped = switch (raw) {
      'top' => 'topLeft',
      'bottom' => 'bottomLeft',
      _ => raw,
    };
    return ClockBatteryPosition.values.firstWhere(
      (e) => e.name == mapped,
      orElse: () => ClockBatteryPosition.topLeft,
    );
  }
  return ClockBatteryPosition.topLeft;
}

/// 解析色彩配置预设（容错：非法字符串回退 none）。
/// 注意：reader_preferences.dart 中的同名私有函数对本库不可见，这里本地实现一份。
ReaderColorProfile _parseColorProfile(Object? raw) {
  if (raw is String) {
    return ReaderColorProfile.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => ReaderColorProfile.none,
    );
  }
  return ReaderColorProfile.none;
}

/// 解析 E-Ink 刷新样式（容错：非法字符串回退 white）。
/// 注意：reader_preferences.dart 中的同名私有函数对本库不可见，这里本地实现一份。
ReaderEInkRefreshStyle _parseEInkRefreshStyle(Object? raw) {
  if (raw is String) {
    return ReaderEInkRefreshStyle.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => ReaderEInkRefreshStyle.white,
    );
  }
  return ReaderEInkRefreshStyle.white;
}

/// 小说默认简繁转换（项 2）。
enum NovelChineseConversion {
  none,
  traditionalToSimplified,
  simplifiedToTraditional
}

/// 漫画默认初始缩放（项 2）。
enum ComicInitialZoom { fitWidth, fitHeight, original }

/// 漫画默认双击缩放倍率（项 2）。
enum ComicDoubleTapZoom { x2, x3 }

/// 漫画默认滚轮方向（项 2）。
enum ComicScrollWheel { natural, inverted }

/// 阅读器默认设置。
class ReaderDefaultSettings {
  final ReadingMode readingMode;
  final bool doubleTapZoom;
  final double novelFontSize;
  final double novelLineHeight;
  final double novelTtsSpeechRate;
  final NovelChineseConversion novelChineseConversion;
  final ReaderTapZoneLayout comicTapZoneLayout;
  final ReaderBackgroundColor comicBackground;
  final ScreenOrientation comicOrientation;
  final double comicSideMargin;
  final bool comicFlashEnabled;
  final int comicFlashTime;
  final int comicFlashInterval;
  final ReaderFlashColor comicFlashColor;
  final ComicInitialZoom comicInitialZoom;
  final ComicDoubleTapZoom comicDoubleTapZoom;
  final ComicScrollWheel comicScrollWheel;

  /// 漫画：鼠标滚轮作用（缩放页面或翻页），仅翻页模式生效；条漫模式忽略。
  final MouseWheelAction comicMouseWheelAction;

  /// 漫画：打开阅读器时是否自动进入全屏。
  final bool comicFullscreen;

  /// 漫画：是否显示长按图片菜单。
  final bool comicShowLongPressMenu;

  /// 漫画：图片灰度滤镜开关。
  final bool comicGrayscale;

  /// 漫画：锁定防止缩小（缩到小于适配宽时回弹到适配宽）。
  final bool comicPreventShrink;

  /// 漫画：章节切换时显示过渡标题卡。
  final bool comicChapterTransition;

  /// 漫画：预加载图片数量（范围 1–16，默认 4）。
  final int comicPreloadImageCount;

  /// 漫画：跨章无缝续读（章末/章首直接续读相邻章，复用预载缓存，不重建章节）。
  final bool comicSeamlessReading;

  /// 漫画：段式连续模型下段与段之间是否插入「章分割/过渡」条目（章节标题卡）。
  /// 仅对 webtoon（条漫）连续模式生效。
  final bool comicShowChapterSeparator;

  /// 漫画：是否显示章节导航滑块（阅读器左缘的竖向章节拖动条）。
  /// 仅多章节作品显示；关闭后阅读器不再显示该滑块。
  final bool comicShowChapterSlider;

  /// 漫画：条漫解码限幅（资源/内存）：连续模式解码位图下采样，
  /// 限制长条漫原图的全尺寸解码内存。此前只有阅读器弹窗可配，补全局默认。
  final bool comicWebtoonLimitDecodeSize;

  /// 漫画：鼠标滚轮滚动速度倍率（webtoon 连续滚动增量 × 本值），范围 0.5–3.0，默认 1.0。
  final double comicReaderScrollSpeed;

  /// 漫画：音量键翻页开关（Android 拦截音量上/下翻页；其他平台并入键盘）。
  final bool comicVolumeKeyPageTurn;

  /// 漫画：音量键在 webtoon（条漫）模式下的竖向滚动步长（占视口高度百分比），范围 10–100，默认 40。
  final int comicVolumeKeyPageTurnDistancePercent;

  /// 漫画：长按缩放开关：开启后长按图片进入 1.75x 缩放；关闭时保持长按弹菜单。
  final bool comicEnableLongPressToZoom;

  /// 漫画：长按缩放锚点：[press]=按触点，[center]=按屏幕中心。
  final LongPressZoomPosition comicLongPressZoomPosition;

  /// 漫画：双击 / 长按缩放锚点来源：left / center / right。
  final ZoomStart comicZoomStart;

  /// 漫画：自动翻页开关。与 [comicAutoPageTurningInterval] 分开存储：
  /// 关闭开关不清零间隔，重新开启时恢复上次设置的间隔。
  final bool comicAutoPageTurningEnabled;

  /// 漫画：自动翻页间隔（秒），范围 1–20；0=从未设置（开启开关时按 5 兜底）。
  /// 仅 [comicAutoPageTurningEnabled] 开启时生效。paged 模式定时自动翻页。
  final int comicAutoPageTurningInterval;

  /// 漫画：自动滚动开关（webtoon 平滑自动滚动，速度随 [comicReaderScrollSpeed]）。
  final bool comicAutoScroll;

  /// 漫画：paged 翻页过渡动画：none=瞬切 / slide=滑入 / fade=淡入淡出。
  final ReaderPageAnimation comicPageAnimation;

  /// 漫画：页面动态效果（comic_motion：主开关 + 逐效果开关 + 参数覆盖 +
  /// 全局质量）。翻页与条漫滚动模式均生效。
  final MotionEffectSettings comicMotionEffects;

  /// 漫画：双击缩放动画时长（毫秒），默认 500。
  final int comicDoubleTapAnimSpeed;

  /// 漫画：webtoon 相邻页间距（像素），范围 0–50，默认 0。
  final int comicReaderPageSpacing;

  /// 漫画：首屏单图：双页模式第一章第一页单独显示。
  final bool comicShowSingleImageOnFirstPage;

  /// 漫画：时间/电量浮层。
  final bool comicShowClockBattery;
  final ClockBatteryPosition comicClockBatteryPosition;
  final double comicClockBatteryMargin;
  final double comicClockBatteryOpacity;
  final double comicClockBatteryFontSize;

  /// 漫画：系统亮度：-1.0~1.0，0=不干预；正值写系统、负值遮罩。
  final double comicReaderBrightness;

  /// 漫画：夜览暖色盖层（亮度双轨扩展）：独立开关 + 暖色不透明度（0.1–0.85）。
  final bool comicNightLightEnabled;
  final double comicNightLightOpacity;

  /// 漫画：图片色彩配置预设（ICC 校色近似）。
  final ReaderColorProfile comicColorProfile;

  /// 漫画：图片超分档位（GPU 实时 shader：off / resample / sharpen）。
  final MangaUpscaleMode comicUpscaleMode;

  /// 漫画：E-Ink 刷新：墨水屏防残影，按翻页间隔自动全屏闪烁。
  final bool comicEinkRefreshEnabled;
  final int comicEinkRefreshInterval;
  final int comicEinkRefreshDuration;
  final ReaderEInkRefreshStyle comicEinkRefreshStyle;

  /// 漫画：自动收藏（漫画）：打开作品即加入收藏。
  final bool comicIsAutoFavorite;

  /// 漫画：阅读中自动下载后续章节。
  final bool comicAutoDownloadChapters;

  /// 漫画：跳章过滤。
  final bool comicSkipReadChapters;
  final bool comicSkipFilteredChapters;
  final bool comicSkipDuplicateChapters;

  /// 漫画：每屏多图 gallery：竖/横屏一屏堆叠张数，1–5，默认 1。
  final int comicReaderScreenPicNumberForPortrait;
  final int comicReaderScreenPicNumberForLandscape;

  // ── 小说补充（来自小说阅读面板，项 1）──
  final double novelParagraphSpacing;
  final double novelMargin;
  final bool novelShadow;
  final int novelBgPresetIndex;
  final TapZoneInvert novelTapZoneInvert;
  final NovelPageAnimation novelPageAnimation;

  // ── 小说补充 v2（与 NovelReaderPreferences 对齐）──
  final double novelBrightness;
  final int? novelCustomBgColor;
  final int? novelCustomTextColor;
  final int? novelEmphasisColor;
  final double novelLetterSpacing;
  final bool novelFontBold;
  final bool novelFontItalic;
  final bool novelFontUnderline;
  final String? novelFontFamily;
  final String? novelCustomFontPath;
  final List<String> novelBottomToolbarSlots;
  final String novelTapZoneLayout;
  final int novelAutoPageInterval;

  /// 小说自动翻页平滑模式（映射到 NovelReaderPreferences.autoPageSmooth）。
  final bool novelAutoPageSmooth;

  /// 小说音量键翻页（仅 Android 生效；映射到
  /// NovelReaderPreferences.volumeKeyPageTurn）。默认开启。
  final bool novelVolumeKeyPageTurn;
  final String novelThemeFollow;
  final int? novelShadowColor;
  final double novelShadowBlur;
  final double novelShadowOffsetX;
  final double novelShadowOffsetY;
  final int? novelUnderlineColor;
  final bool novelUnderlineDashed;
  /// 小说： 双页模式（翻页模式宽屏左右并排两页）。
  final bool novelTwoPageMode;
  final double novelUnderlineThickness;
  final double novelUnderlineDashLength;
  final double novelUnderlineDashGap;
  final bool novelShowChapterTitleInBody;
  final String novelTitleAlign;
  final double novelTitleFontScale;
  final bool novelTitleBold;
  final String? novelTitleFontFamily;
  final String? novelTitleCustomFontPath;
  final bool novelTitleSegmentMode;
  final double novelTitleSubScale;
  final double novelTitleSegmentSpacing;
  final double novelTitleSubLineSpacing;
  final double novelTitleTopMargin;
  final double novelTitleBottomMargin;
  final int? novelTitleColor;
  final String novelHeaderLeft;
  final String novelHeaderRight;
  final String novelHeaderCenter;
  final String novelFooterLeft;
  final String novelFooterRight;
  final String novelFooterCenter;
  final int? novelHeaderFooterColor;
  final double novelHeaderFooterMargin;
  final bool novelTtsBackground;

  /// 跨章连播默认值：一章读完自动续读下一章。
  final bool novelTtsAutoNext;
  final int novelTtsSleepTimer;

  /// 小说：鼠标滚轮翻页方向反转（仅翻页模式生效；滚动模式由底层滚动接管）。
  final bool novelScrollWheelInverted;

  // ── 小说补充 v3（排版增强，与 NovelReaderPreferences 对齐）──
  /// 加粗字重滑块（100–900，仅加粗开启时生效）。
  final int novelFontWeightValue;

  /// 正文对齐方式（'start' / 'justify'）。
  final String novelTextAlignMode;

  /// 中文断行模式（'standard' / 'cjkStrict'）。
  final String novelLineBreakMode;

  /// 下划线样式（'solid' / 'dashed' / 'wavy' / 'dotted'）。
  final String novelUnderlineStyle;

  // ── 小说补充 v4（滚动模式图文增强）──
  /// 滚动模式插图展示模式（'banner' / 'card'）。
  final String novelScrollImageMode;

  /// 滚动模式插图水平对齐（'left' / 'center' / 'right'）。
  final String novelScrollImageAlign;

  // ── 漫画补充（来自漫画阅读面板，项 1）──
  final double comicFilterBrightness;
  final double comicFilterContrast;
  final double comicFilterColorTemp;
  final bool comicFilterInverted;
  final TapZoneInvert comicTapZoneInvert;

  /// 漫画：裁边（去除图片四周留白）。
  final bool comicCropEdge;

  /// 漫画：显示页码。
  final bool comicShowPageNumber;

  /// 漫画：进度条在右侧竖向显示。
  final bool comicProgressBarOnRight;

  /// 漫画：屏幕常亮（阻止息屏）。
  final bool comicKeepScreenOn;

  /// 漫画：页面旋转时强制横屏。
  final bool comicRotateLandscape;

  /// 漫画：双页拆分。
  final bool comicSplitDoublePage;

  /// 漫画：滤镜饱和度（范围 -1.0~1.0，0.0 为不变）。
  final double comicFilterSaturation;

  /// 漫画：滤镜色相旋转（范围 -1.0~1.0，0.0 为不变）。
  final double comicFilterHue;

  const ReaderDefaultSettings({
    this.readingMode = ReadingMode.singleLTR,
    this.doubleTapZoom = true,
    this.novelFontSize = 18.0,
    this.novelLineHeight = 1.8,
    this.novelTtsSpeechRate = 1.0,
    this.novelChineseConversion = NovelChineseConversion.none,
    this.comicTapZoneLayout = ReaderTapZoneLayout.lShape,
    this.comicBackground = ReaderBackgroundColor.black,
    this.comicOrientation = ScreenOrientation.defaultMode,
    this.comicSideMargin = 0.0,
    this.comicFlashEnabled = false,
    this.comicFlashTime = 120,
    this.comicFlashInterval = 0,
    this.comicFlashColor = ReaderFlashColor.black,
    this.comicInitialZoom = ComicInitialZoom.fitWidth,
    this.comicDoubleTapZoom = ComicDoubleTapZoom.x2,
    this.comicScrollWheel = ComicScrollWheel.natural,
    this.comicMouseWheelAction = MouseWheelAction.zoom,
    this.comicFullscreen = true,
    this.comicShowLongPressMenu = true,
    this.comicGrayscale = false,
    this.comicPreventShrink = false,
    this.comicChapterTransition = false,
    this.comicPreloadImageCount = 4,
    this.comicSeamlessReading = true,
    this.comicShowChapterSeparator = true,
    this.comicShowChapterSlider = true,
    this.comicWebtoonLimitDecodeSize = true,
    this.comicReaderScrollSpeed = 1.0,
    this.comicVolumeKeyPageTurn = false,
    this.comicVolumeKeyPageTurnDistancePercent = 40,
    this.comicEnableLongPressToZoom = false,
    this.comicLongPressZoomPosition = LongPressZoomPosition.press,
    this.comicZoomStart = ZoomStart.center,
    this.comicAutoPageTurningEnabled = false,
    this.comicAutoPageTurningInterval = 0,
    this.comicAutoScroll = false,
    this.comicPageAnimation = ReaderPageAnimation.slide,
    this.comicMotionEffects = const MotionEffectSettings(),
    this.comicDoubleTapAnimSpeed = 500,
    this.comicReaderPageSpacing = 0,
    this.comicShowSingleImageOnFirstPage = false,
    this.comicShowClockBattery = false,
    this.comicClockBatteryPosition = ClockBatteryPosition.topLeft,
    this.comicClockBatteryMargin = 8.0,
    this.comicClockBatteryOpacity = 0.8,
    this.comicClockBatteryFontSize = 12.0,
    this.comicReaderBrightness = 0.0,
    this.comicNightLightEnabled = false,
    this.comicNightLightOpacity = 0.4,
    this.comicColorProfile = ReaderColorProfile.none,
    this.comicUpscaleMode = MangaUpscaleMode.off,
    this.comicEinkRefreshEnabled = false,
    this.comicEinkRefreshInterval = 10,
    this.comicEinkRefreshDuration = 200,
    this.comicEinkRefreshStyle = ReaderEInkRefreshStyle.white,
    this.comicIsAutoFavorite = false,
    this.comicAutoDownloadChapters = false,
    this.comicSkipReadChapters = false,
    this.comicSkipFilteredChapters = false,
    this.comicSkipDuplicateChapters = false,
    this.comicReaderScreenPicNumberForPortrait = 1,
    this.comicReaderScreenPicNumberForLandscape = 1,
    this.novelParagraphSpacing = 16.0,
    this.novelMargin = 24.0,
    this.novelShadow = false,
    this.novelBgPresetIndex = 2,
    this.novelTapZoneInvert = TapZoneInvert.none,
    this.novelPageAnimation = NovelPageAnimation.slide,
    this.novelBrightness = 0.5,
    this.novelCustomBgColor,
    this.novelCustomTextColor,
    this.novelEmphasisColor,
    this.novelLetterSpacing = 0.0,
    this.novelFontBold = false,
    this.novelFontItalic = false,
    this.novelFontUnderline = false,
    this.novelFontFamily,
    this.novelCustomFontPath,
    this.novelBottomToolbarSlots = const <String>['toc', 'prevChapter', 'nightMode', 'autoPage', 'settings', 'bookmark'],
    this.novelTapZoneLayout = 'lShape',
    this.novelAutoPageInterval = 0,
    this.novelAutoPageSmooth = false,
    this.novelVolumeKeyPageTurn = true,
    this.novelThemeFollow = 'followApp',
    this.novelShadowColor,
    this.novelShadowBlur = 0.5,
    this.novelShadowOffsetX = 0.5,
    this.novelShadowOffsetY = 0.5,
    this.novelUnderlineColor,
    this.novelUnderlineDashed = false,
    this.novelTwoPageMode = false,
    this.novelUnderlineThickness = 1.0,
    this.novelUnderlineDashLength = 4.0,
    this.novelUnderlineDashGap = 2.0,
    this.novelShowChapterTitleInBody = true,
    this.novelTitleAlign = 'left',
    this.novelTitleFontScale = 1.5,
    this.novelTitleBold = true,
    this.novelTitleFontFamily,
    this.novelTitleCustomFontPath,
    this.novelTitleSegmentMode = false,
    this.novelTitleSubScale = 0.8,
    this.novelTitleSegmentSpacing = 8.0,
    this.novelTitleSubLineSpacing = 1.3,
    this.novelTitleTopMargin = 0.0,
    this.novelTitleBottomMargin = 0.0,
    this.novelTitleColor,
    this.novelHeaderLeft = 'bookName',
    this.novelHeaderRight = 'time',
    this.novelHeaderCenter = 'none',
    this.novelFooterLeft = 'chapterTitle',
    this.novelFooterRight = 'pageNumber',
    this.novelFooterCenter = 'none',
    this.novelHeaderFooterColor,
    this.novelHeaderFooterMargin = 12.0,
    this.novelTtsBackground = false,
    this.novelTtsAutoNext = true,
    this.novelTtsSleepTimer = 0,
    this.novelScrollWheelInverted = false,
    // 排版增强
    this.novelFontWeightValue = 700,
    this.novelTextAlignMode = 'start',
    this.novelLineBreakMode = 'standard',
    this.novelUnderlineStyle = 'solid',
    // 滚动模式图文增强
    this.novelScrollImageMode = 'banner',
    this.novelScrollImageAlign = 'center',
    this.comicFilterBrightness = 0.0,
    this.comicFilterContrast = 0.0,
    this.comicFilterColorTemp = 0.0,
    this.comicFilterInverted = false,
    this.comicTapZoneInvert = TapZoneInvert.none,
    this.comicCropEdge = false,
    this.comicShowPageNumber = true,
    this.comicProgressBarOnRight = true,
    this.comicKeepScreenOn = false,
    this.comicRotateLandscape = false,
    this.comicSplitDoublePage = false,
    this.comicFilterSaturation = 0.0,
    this.comicFilterHue = 0.0,
  });

  ReaderDefaultSettings copyWith({
    ReadingMode? readingMode,
    bool? doubleTapZoom,
    double? novelFontSize,
    double? novelLineHeight,
    double? novelTtsSpeechRate,
    NovelChineseConversion? novelChineseConversion,
    ReaderTapZoneLayout? comicTapZoneLayout,
    ReaderBackgroundColor? comicBackground,
    ScreenOrientation? comicOrientation,
    double? comicSideMargin,
    bool? comicFlashEnabled,
    int? comicFlashTime,
    int? comicFlashInterval,
    ReaderFlashColor? comicFlashColor,
    ComicInitialZoom? comicInitialZoom,
    ComicDoubleTapZoom? comicDoubleTapZoom,
    ComicScrollWheel? comicScrollWheel,
    MouseWheelAction? comicMouseWheelAction,
    bool? comicFullscreen,
    bool? comicShowLongPressMenu,
    bool? comicGrayscale,
    bool? comicPreventShrink,
    bool? comicChapterTransition,
    int? comicPreloadImageCount,
    bool? comicSeamlessReading,
    bool? comicShowChapterSeparator,
    bool? comicShowChapterSlider,
    bool? comicWebtoonLimitDecodeSize,
    double? comicReaderScrollSpeed,
    bool? comicVolumeKeyPageTurn,
    int? comicVolumeKeyPageTurnDistancePercent,
    bool? comicEnableLongPressToZoom,
    LongPressZoomPosition? comicLongPressZoomPosition,
    ZoomStart? comicZoomStart,
    bool? comicAutoPageTurningEnabled,
    int? comicAutoPageTurningInterval,
    bool? comicAutoScroll,
    ReaderPageAnimation? comicPageAnimation,
    MotionEffectSettings? comicMotionEffects,
    int? comicDoubleTapAnimSpeed,
    int? comicReaderPageSpacing,
    bool? comicShowSingleImageOnFirstPage,
    bool? comicShowClockBattery,
    ClockBatteryPosition? comicClockBatteryPosition,
    double? comicClockBatteryMargin,
    double? comicClockBatteryOpacity,
    double? comicClockBatteryFontSize,
    double? comicReaderBrightness,
    bool? comicNightLightEnabled,
    double? comicNightLightOpacity,
    ReaderColorProfile? comicColorProfile,
    MangaUpscaleMode? comicUpscaleMode,
    bool? comicEinkRefreshEnabled,
    int? comicEinkRefreshInterval,
    int? comicEinkRefreshDuration,
    ReaderEInkRefreshStyle? comicEinkRefreshStyle,
    bool? comicIsAutoFavorite,
    bool? comicAutoDownloadChapters,
    bool? comicSkipReadChapters,
    bool? comicSkipFilteredChapters,
    bool? comicSkipDuplicateChapters,
    int? comicReaderScreenPicNumberForPortrait,
    int? comicReaderScreenPicNumberForLandscape,
    double? novelParagraphSpacing,
    double? novelMargin,
    bool? novelShadow,
    int? novelBgPresetIndex,
    TapZoneInvert? novelTapZoneInvert,
    NovelPageAnimation? novelPageAnimation,
    double? novelBrightness,
    int? novelCustomBgColor,
    int? novelCustomTextColor,
    int? novelEmphasisColor,
    double? novelLetterSpacing,
    bool? novelFontBold,
    bool? novelFontItalic,
    bool? novelFontUnderline,
    String? novelFontFamily,
    String? novelCustomFontPath,
    List<String>? novelBottomToolbarSlots,
    String? novelTapZoneLayout,
    int? novelAutoPageInterval,
    bool? novelAutoPageSmooth,
    bool? novelVolumeKeyPageTurn,
    String? novelThemeFollow,
    int? novelShadowColor,
    double? novelShadowBlur,
    double? novelShadowOffsetX,
    double? novelShadowOffsetY,
    int? novelUnderlineColor,
    bool? novelUnderlineDashed,
    bool? novelTwoPageMode,
    double? novelUnderlineThickness,
    double? novelUnderlineDashLength,
    double? novelUnderlineDashGap,
    bool? novelShowChapterTitleInBody,
    String? novelTitleAlign,
    double? novelTitleFontScale,
    bool? novelTitleBold,
    String? novelTitleFontFamily,
    String? novelTitleCustomFontPath,
    bool? novelTitleSegmentMode,
    double? novelTitleSubScale,
    double? novelTitleSegmentSpacing,
    double? novelTitleSubLineSpacing,
    double? novelTitleTopMargin,
    double? novelTitleBottomMargin,
    int? novelTitleColor,
    String? novelHeaderLeft,
    String? novelHeaderRight,
    String? novelHeaderCenter,
    String? novelFooterLeft,
    String? novelFooterRight,
    String? novelFooterCenter,
    int? novelHeaderFooterColor,
    double? novelHeaderFooterMargin,
    bool? novelTtsBackground,
    bool? novelTtsAutoNext,
    int? novelTtsSleepTimer,
    bool? novelScrollWheelInverted,
    // 排版增强
    int? novelFontWeightValue,
    String? novelTextAlignMode,
    String? novelLineBreakMode,
    String? novelUnderlineStyle,
    // 滚动模式图文增强
    String? novelScrollImageMode,
    String? novelScrollImageAlign,
    double? comicFilterBrightness,
    double? comicFilterContrast,
    double? comicFilterColorTemp,
    bool? comicFilterInverted,
    TapZoneInvert? comicTapZoneInvert,
    bool? comicCropEdge,
    bool? comicShowPageNumber,
    bool? comicProgressBarOnRight,
    bool? comicKeepScreenOn,
    bool? comicRotateLandscape,
    bool? comicSplitDoublePage,
    double? comicFilterSaturation,
    double? comicFilterHue,
  }) =>
      ReaderDefaultSettings(
        readingMode: readingMode ?? this.readingMode,
        doubleTapZoom: doubleTapZoom ?? this.doubleTapZoom,
        novelFontSize: novelFontSize ?? this.novelFontSize,
        novelLineHeight: novelLineHeight ?? this.novelLineHeight,
        novelTtsSpeechRate:
            novelTtsSpeechRate ?? this.novelTtsSpeechRate,
        novelChineseConversion:
            novelChineseConversion ?? this.novelChineseConversion,
        comicTapZoneLayout: comicTapZoneLayout ?? this.comicTapZoneLayout,
        comicBackground: comicBackground ?? this.comicBackground,
        comicOrientation: comicOrientation ?? this.comicOrientation,
        comicSideMargin: comicSideMargin ?? this.comicSideMargin,
        comicFlashEnabled: comicFlashEnabled ?? this.comicFlashEnabled,
        comicFlashTime: comicFlashTime ?? this.comicFlashTime,
        comicFlashInterval: comicFlashInterval ?? this.comicFlashInterval,
        comicFlashColor: comicFlashColor ?? this.comicFlashColor,
        comicInitialZoom: comicInitialZoom ?? this.comicInitialZoom,
        comicDoubleTapZoom: comicDoubleTapZoom ?? this.comicDoubleTapZoom,
        comicScrollWheel: comicScrollWheel ?? this.comicScrollWheel,
        comicMouseWheelAction:
            comicMouseWheelAction ?? this.comicMouseWheelAction,
        comicFullscreen: comicFullscreen ?? this.comicFullscreen,
        comicShowLongPressMenu:
            comicShowLongPressMenu ?? this.comicShowLongPressMenu,
        comicGrayscale: comicGrayscale ?? this.comicGrayscale,
        comicPreventShrink: comicPreventShrink ?? this.comicPreventShrink,
        comicChapterTransition:
            comicChapterTransition ?? this.comicChapterTransition,
        comicPreloadImageCount:
            comicPreloadImageCount ?? this.comicPreloadImageCount,
        comicSeamlessReading:
            comicSeamlessReading ?? this.comicSeamlessReading,
        comicShowChapterSeparator:
            comicShowChapterSeparator ?? this.comicShowChapterSeparator,
        comicShowChapterSlider:
            comicShowChapterSlider ?? this.comicShowChapterSlider,
        comicWebtoonLimitDecodeSize:
            comicWebtoonLimitDecodeSize ?? this.comicWebtoonLimitDecodeSize,
        comicReaderScrollSpeed:
            comicReaderScrollSpeed ?? this.comicReaderScrollSpeed,
        comicVolumeKeyPageTurn:
            comicVolumeKeyPageTurn ?? this.comicVolumeKeyPageTurn,
        comicVolumeKeyPageTurnDistancePercent:
            comicVolumeKeyPageTurnDistancePercent ??
                this.comicVolumeKeyPageTurnDistancePercent,
        comicEnableLongPressToZoom:
            comicEnableLongPressToZoom ?? this.comicEnableLongPressToZoom,
        comicLongPressZoomPosition:
            comicLongPressZoomPosition ?? this.comicLongPressZoomPosition,
        comicZoomStart: comicZoomStart ?? this.comicZoomStart,
        comicAutoPageTurningEnabled:
            comicAutoPageTurningEnabled ?? this.comicAutoPageTurningEnabled,
        comicAutoPageTurningInterval:
            comicAutoPageTurningInterval ?? this.comicAutoPageTurningInterval,
        comicAutoScroll: comicAutoScroll ?? this.comicAutoScroll,
        comicPageAnimation: comicPageAnimation ?? this.comicPageAnimation,
      comicMotionEffects: comicMotionEffects ?? this.comicMotionEffects,
        comicDoubleTapAnimSpeed:
            comicDoubleTapAnimSpeed ?? this.comicDoubleTapAnimSpeed,
        comicReaderPageSpacing:
            comicReaderPageSpacing ?? this.comicReaderPageSpacing,
        comicShowSingleImageOnFirstPage: comicShowSingleImageOnFirstPage ??
            this.comicShowSingleImageOnFirstPage,
        comicShowClockBattery:
            comicShowClockBattery ?? this.comicShowClockBattery,
        comicClockBatteryPosition:
            comicClockBatteryPosition ?? this.comicClockBatteryPosition,
        comicClockBatteryMargin:
            comicClockBatteryMargin ?? this.comicClockBatteryMargin,
        comicClockBatteryOpacity:
            comicClockBatteryOpacity ?? this.comicClockBatteryOpacity,
        comicClockBatteryFontSize:
            comicClockBatteryFontSize ?? this.comicClockBatteryFontSize,
        comicReaderBrightness:
            comicReaderBrightness ?? this.comicReaderBrightness,
        comicNightLightEnabled:
            comicNightLightEnabled ?? this.comicNightLightEnabled,
        comicNightLightOpacity:
            comicNightLightOpacity ?? this.comicNightLightOpacity,
        comicColorProfile: comicColorProfile ?? this.comicColorProfile,
        comicUpscaleMode: comicUpscaleMode ?? this.comicUpscaleMode,
        comicEinkRefreshEnabled:
            comicEinkRefreshEnabled ?? this.comicEinkRefreshEnabled,
        comicEinkRefreshInterval:
            comicEinkRefreshInterval ?? this.comicEinkRefreshInterval,
        comicEinkRefreshDuration:
            comicEinkRefreshDuration ?? this.comicEinkRefreshDuration,
        comicEinkRefreshStyle:
            comicEinkRefreshStyle ?? this.comicEinkRefreshStyle,
        comicIsAutoFavorite:
            comicIsAutoFavorite ?? this.comicIsAutoFavorite,
        comicAutoDownloadChapters:
            comicAutoDownloadChapters ?? this.comicAutoDownloadChapters,
        comicSkipReadChapters:
            comicSkipReadChapters ?? this.comicSkipReadChapters,
        comicSkipFilteredChapters:
            comicSkipFilteredChapters ?? this.comicSkipFilteredChapters,
        comicSkipDuplicateChapters:
            comicSkipDuplicateChapters ?? this.comicSkipDuplicateChapters,
        comicReaderScreenPicNumberForPortrait:
            comicReaderScreenPicNumberForPortrait ??
                this.comicReaderScreenPicNumberForPortrait,
        comicReaderScreenPicNumberForLandscape:
            comicReaderScreenPicNumberForLandscape ??
                this.comicReaderScreenPicNumberForLandscape,
        novelParagraphSpacing:
            novelParagraphSpacing ?? this.novelParagraphSpacing,
        novelMargin: novelMargin ?? this.novelMargin,
        novelShadow: novelShadow ?? this.novelShadow,
        novelBgPresetIndex:
            novelBgPresetIndex ?? this.novelBgPresetIndex,
        novelTapZoneInvert:
            novelTapZoneInvert ?? this.novelTapZoneInvert,
        novelPageAnimation: novelPageAnimation ?? this.novelPageAnimation,
        novelBrightness: novelBrightness ?? this.novelBrightness,
        novelCustomBgColor: novelCustomBgColor ?? this.novelCustomBgColor,
        novelCustomTextColor: novelCustomTextColor ?? this.novelCustomTextColor,
        novelEmphasisColor: novelEmphasisColor ?? this.novelEmphasisColor,
        novelLetterSpacing: novelLetterSpacing ?? this.novelLetterSpacing,
        novelFontBold: novelFontBold ?? this.novelFontBold,
        novelFontItalic: novelFontItalic ?? this.novelFontItalic,
        novelFontUnderline: novelFontUnderline ?? this.novelFontUnderline,
        novelFontFamily: novelFontFamily ?? this.novelFontFamily,
        novelCustomFontPath: novelCustomFontPath ?? this.novelCustomFontPath,
        novelBottomToolbarSlots:
            novelBottomToolbarSlots ?? this.novelBottomToolbarSlots,
        novelTapZoneLayout: novelTapZoneLayout ?? this.novelTapZoneLayout,
        novelAutoPageInterval:
            novelAutoPageInterval ?? this.novelAutoPageInterval,
        novelAutoPageSmooth: novelAutoPageSmooth ?? this.novelAutoPageSmooth,
        novelVolumeKeyPageTurn:
            novelVolumeKeyPageTurn ?? this.novelVolumeKeyPageTurn,
        novelThemeFollow: novelThemeFollow ?? this.novelThemeFollow,
        novelShadowColor: novelShadowColor ?? this.novelShadowColor,
        novelShadowBlur: novelShadowBlur ?? this.novelShadowBlur,
        novelShadowOffsetX: novelShadowOffsetX ?? this.novelShadowOffsetX,
        novelShadowOffsetY: novelShadowOffsetY ?? this.novelShadowOffsetY,
        novelUnderlineColor:
            novelUnderlineColor ?? this.novelUnderlineColor,
        novelUnderlineDashed:
            novelUnderlineDashed ?? this.novelUnderlineDashed,
        novelTwoPageMode: novelTwoPageMode ?? this.novelTwoPageMode,
        novelUnderlineThickness:
            novelUnderlineThickness ?? this.novelUnderlineThickness,
        novelUnderlineDashLength:
            novelUnderlineDashLength ?? this.novelUnderlineDashLength,
        novelUnderlineDashGap:
            novelUnderlineDashGap ?? this.novelUnderlineDashGap,
        novelShowChapterTitleInBody:
            novelShowChapterTitleInBody ?? this.novelShowChapterTitleInBody,
        novelTitleAlign: novelTitleAlign ?? this.novelTitleAlign,
        novelTitleFontScale:
            novelTitleFontScale ?? this.novelTitleFontScale,
        novelTitleBold: novelTitleBold ?? this.novelTitleBold,
        novelTitleFontFamily:
            novelTitleFontFamily ?? this.novelTitleFontFamily,
        novelTitleCustomFontPath:
            novelTitleCustomFontPath ?? this.novelTitleCustomFontPath,
        novelTitleSegmentMode:
            novelTitleSegmentMode ?? this.novelTitleSegmentMode,
        novelTitleSubScale: novelTitleSubScale ?? this.novelTitleSubScale,
        novelTitleSegmentSpacing:
            novelTitleSegmentSpacing ?? this.novelTitleSegmentSpacing,
        novelTitleSubLineSpacing:
            novelTitleSubLineSpacing ?? this.novelTitleSubLineSpacing,
        novelTitleTopMargin:
            novelTitleTopMargin ?? this.novelTitleTopMargin,
        novelTitleBottomMargin:
            novelTitleBottomMargin ?? this.novelTitleBottomMargin,
        novelTitleColor: novelTitleColor ?? this.novelTitleColor,
        novelHeaderLeft: novelHeaderLeft ?? this.novelHeaderLeft,
        novelHeaderRight: novelHeaderRight ?? this.novelHeaderRight,
        novelHeaderCenter: novelHeaderCenter ?? this.novelHeaderCenter,
        novelFooterLeft: novelFooterLeft ?? this.novelFooterLeft,
        novelFooterRight: novelFooterRight ?? this.novelFooterRight,
        novelFooterCenter: novelFooterCenter ?? this.novelFooterCenter,
        novelHeaderFooterColor:
            novelHeaderFooterColor ?? this.novelHeaderFooterColor,
        novelHeaderFooterMargin:
            novelHeaderFooterMargin ?? this.novelHeaderFooterMargin,
        novelTtsBackground: novelTtsBackground ?? this.novelTtsBackground,
        novelTtsAutoNext: novelTtsAutoNext ?? this.novelTtsAutoNext,
        novelTtsSleepTimer: novelTtsSleepTimer ?? this.novelTtsSleepTimer,
        novelScrollWheelInverted:
            novelScrollWheelInverted ?? this.novelScrollWheelInverted,
    // 排版增强
    novelFontWeightValue: novelFontWeightValue ?? this.novelFontWeightValue,
    novelTextAlignMode: novelTextAlignMode ?? this.novelTextAlignMode,
    novelLineBreakMode: novelLineBreakMode ?? this.novelLineBreakMode,
    novelUnderlineStyle: novelUnderlineStyle ?? this.novelUnderlineStyle,
    // 滚动模式图文增强
    novelScrollImageMode:
        novelScrollImageMode ?? this.novelScrollImageMode,
    novelScrollImageAlign:
        novelScrollImageAlign ?? this.novelScrollImageAlign,
        comicFilterBrightness:
            comicFilterBrightness ?? this.comicFilterBrightness,
        comicFilterContrast:
            comicFilterContrast ?? this.comicFilterContrast,
        comicFilterColorTemp:
            comicFilterColorTemp ?? this.comicFilterColorTemp,
        comicFilterInverted:
            comicFilterInverted ?? this.comicFilterInverted,
        comicTapZoneInvert:
            comicTapZoneInvert ?? this.comicTapZoneInvert,
        comicCropEdge: comicCropEdge ?? this.comicCropEdge,
        comicShowPageNumber: comicShowPageNumber ?? this.comicShowPageNumber,
        comicProgressBarOnRight:
            comicProgressBarOnRight ?? this.comicProgressBarOnRight,
        comicKeepScreenOn: comicKeepScreenOn ?? this.comicKeepScreenOn,
        comicRotateLandscape:
            comicRotateLandscape ?? this.comicRotateLandscape,
        comicSplitDoublePage:
            comicSplitDoublePage ?? this.comicSplitDoublePage,
        comicFilterSaturation:
            comicFilterSaturation ?? this.comicFilterSaturation,
        comicFilterHue: comicFilterHue ?? this.comicFilterHue,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        // 存档结构版本（见 [ReaderDefaultSettings.fromJson] 的迁移说明）。
        'schema': kNovelPrefsSchema,
        'readingMode': readingMode.name,
        'doubleTapZoom': doubleTapZoom,
        'novelFontSize': novelFontSize,
        'novelLineHeight': novelLineHeight,
        'novelTtsSpeechRate': novelTtsSpeechRate,
        'novelChineseConversion': novelChineseConversion.name,
        'comicTapZoneLayout': comicTapZoneLayout.name,
        'comicBackground': comicBackground.name,
        'comicOrientation': comicOrientation.name,
        'comicSideMargin': comicSideMargin,
        'comicFlashEnabled': comicFlashEnabled,
        'comicFlashTime': comicFlashTime,
        'comicFlashInterval': comicFlashInterval,
        'comicFlashColor': comicFlashColor.name,
        'comicInitialZoom': comicInitialZoom.name,
        'comicDoubleTapZoom': comicDoubleTapZoom.name,
        'comicScrollWheel': comicScrollWheel.name,
        'comicMouseWheelAction': comicMouseWheelAction.name,
        'comicFullscreen': comicFullscreen,
        'comicShowLongPressMenu': comicShowLongPressMenu,
        'comicGrayscale': comicGrayscale,
        'comicPreventShrink': comicPreventShrink,
        'comicChapterTransition': comicChapterTransition,
        'comicPreloadImageCount': comicPreloadImageCount,
        'comicSeamlessReading': comicSeamlessReading,
        'comicShowChapterSeparator': comicShowChapterSeparator,
        'comicShowChapterSlider': comicShowChapterSlider,
        'comicWebtoonLimitDecodeSize': comicWebtoonLimitDecodeSize,
        'comicReaderScrollSpeed': comicReaderScrollSpeed,
        'comicVolumeKeyPageTurn': comicVolumeKeyPageTurn,
        'comicVolumeKeyPageTurnDistancePercent':
            comicVolumeKeyPageTurnDistancePercent,
        'comicEnableLongPressToZoom': comicEnableLongPressToZoom,
        'comicLongPressZoomPosition': comicLongPressZoomPosition.name,
        'comicZoomStart': comicZoomStart.name,
        'comicAutoPageTurningEnabled': comicAutoPageTurningEnabled,
        'comicAutoPageTurningInterval': comicAutoPageTurningInterval,
        'comicAutoScroll': comicAutoScroll,
        'comicPageAnimation': comicPageAnimation.name,
        'comicMotionEffects': comicMotionEffects.toJson(),
        'comicDoubleTapAnimSpeed': comicDoubleTapAnimSpeed,
        'comicReaderPageSpacing': comicReaderPageSpacing,
        'comicShowSingleImageOnFirstPage': comicShowSingleImageOnFirstPage,
        'comicShowClockBattery': comicShowClockBattery,
        'comicClockBatteryPosition': comicClockBatteryPosition.name,
        'comicClockBatteryMargin': comicClockBatteryMargin,
        'comicClockBatteryOpacity': comicClockBatteryOpacity,
        'comicClockBatteryFontSize': comicClockBatteryFontSize,
        'comicReaderBrightness': comicReaderBrightness,
        'comicNightLightEnabled': comicNightLightEnabled,
        'comicNightLightOpacity': comicNightLightOpacity,
        'comicColorProfile': comicColorProfile.name,
        'comicUpscaleMode': comicUpscaleMode.name,
        'comicEinkRefreshEnabled': comicEinkRefreshEnabled,
        'comicEinkRefreshInterval': comicEinkRefreshInterval,
        'comicEinkRefreshDuration': comicEinkRefreshDuration,
        'comicEinkRefreshStyle': comicEinkRefreshStyle.name,
        'comicIsAutoFavorite': comicIsAutoFavorite,
        'comicAutoDownloadChapters': comicAutoDownloadChapters,
        'comicSkipReadChapters': comicSkipReadChapters,
        'comicSkipFilteredChapters': comicSkipFilteredChapters,
        'comicSkipDuplicateChapters': comicSkipDuplicateChapters,
        'comicReaderScreenPicNumberForPortrait':
            comicReaderScreenPicNumberForPortrait,
        'comicReaderScreenPicNumberForLandscape':
            comicReaderScreenPicNumberForLandscape,
        'novelParagraphSpacing': novelParagraphSpacing,
        'novelMargin': novelMargin,
        'novelShadow': novelShadow,
        'novelBgPresetIndex': novelBgPresetIndex,
        'novelTapZoneInvert': novelTapZoneInvert.name,
        'novelPageAnimation': novelPageAnimation.name,
        'novelBrightness': novelBrightness,
        if (novelCustomBgColor != null) 'novelCustomBgColor': novelCustomBgColor,
        if (novelCustomTextColor != null) 'novelCustomTextColor': novelCustomTextColor,
        if (novelEmphasisColor != null) 'novelEmphasisColor': novelEmphasisColor,
        'novelLetterSpacing': novelLetterSpacing,
        'novelFontBold': novelFontBold,
        'novelFontItalic': novelFontItalic,
        'novelFontUnderline': novelFontUnderline,
        if (novelCustomFontPath != null) 'novelCustomFontPath': novelCustomFontPath,
        if (novelFontFamily != null) 'novelFontFamily': novelFontFamily,
        'novelBottomToolbarSlots': novelBottomToolbarSlots,
        'novelTapZoneLayout': novelTapZoneLayout,
        'novelAutoPageInterval': novelAutoPageInterval,
        'novelAutoPageSmooth': novelAutoPageSmooth,
        'novelVolumeKeyPageTurn': novelVolumeKeyPageTurn,
        'novelThemeFollow': novelThemeFollow,
        if (novelShadowColor != null) 'novelShadowColor': novelShadowColor,
        'novelShadowBlur': novelShadowBlur,
        'novelShadowOffsetX': novelShadowOffsetX,
        'novelShadowOffsetY': novelShadowOffsetY,
        if (novelUnderlineColor != null) 'novelUnderlineColor': novelUnderlineColor,
        'novelUnderlineDashed': novelUnderlineDashed,
        'novelTwoPageMode': novelTwoPageMode,
        'novelUnderlineThickness': novelUnderlineThickness,
        'novelUnderlineDashLength': novelUnderlineDashLength,
        'novelUnderlineDashGap': novelUnderlineDashGap,
        'novelShowChapterTitleInBody': novelShowChapterTitleInBody,
        'novelTitleAlign': novelTitleAlign,
        'novelTitleFontScale': novelTitleFontScale,
        'novelTitleBold': novelTitleBold,
        if (novelTitleFontFamily != null) 'novelTitleFontFamily': novelTitleFontFamily,
        if (novelTitleCustomFontPath != null) 'novelTitleCustomFontPath': novelTitleCustomFontPath,
        'novelTitleSegmentMode': novelTitleSegmentMode,
        'novelTitleSubScale': novelTitleSubScale,
        'novelTitleSegmentSpacing': novelTitleSegmentSpacing,
        'novelTitleSubLineSpacing': novelTitleSubLineSpacing,
        'novelTitleTopMargin': novelTitleTopMargin,
        'novelTitleBottomMargin': novelTitleBottomMargin,
        if (novelTitleColor != null) 'novelTitleColor': novelTitleColor,
        'novelHeaderLeft': novelHeaderLeft,
        'novelHeaderRight': novelHeaderRight,
        'novelHeaderCenter': novelHeaderCenter,
        'novelFooterLeft': novelFooterLeft,
        'novelFooterRight': novelFooterRight,
        'novelFooterCenter': novelFooterCenter,
        if (novelHeaderFooterColor != null) 'novelHeaderFooterColor': novelHeaderFooterColor,
        'novelHeaderFooterMargin': novelHeaderFooterMargin,
        'novelTtsBackground': novelTtsBackground,
        'novelTtsAutoNext': novelTtsAutoNext,
        'novelTtsSleepTimer': novelTtsSleepTimer,
        'novelScrollWheelInverted': novelScrollWheelInverted,
        // 排版增强
        // 排版增强
        'novelFontWeightValue': novelFontWeightValue,
        'novelTextAlignMode': novelTextAlignMode,
        'novelLineBreakMode': novelLineBreakMode,
        'novelUnderlineStyle': novelUnderlineStyle,
        // 滚动模式图文增强
        'novelScrollImageMode': novelScrollImageMode,
        'novelScrollImageAlign': novelScrollImageAlign,
        'comicFilterBrightness': comicFilterBrightness,
        'comicFilterContrast': comicFilterContrast,
        'comicFilterColorTemp': comicFilterColorTemp,
        'comicFilterInverted': comicFilterInverted,
        'comicTapZoneInvert': comicTapZoneInvert.name,
        'comicCropEdge': comicCropEdge,
        'comicShowPageNumber': comicShowPageNumber,
        'comicProgressBarOnRight': comicProgressBarOnRight,
        'comicKeepScreenOn': comicKeepScreenOn,
        'comicRotateLandscape': comicRotateLandscape,
        'comicSplitDoublePage': comicSplitDoublePage,
        'comicFilterSaturation': comicFilterSaturation,
        'comicFilterHue': comicFilterHue,
      };

  factory ReaderDefaultSettings.fromJson(Map<String, dynamic> json) {
    // 旧版（无 schema）里的 novelTtsAutoNext=false 只是历史默认值，
    // 一律按新默认值（true）读取；用户改过后会以 v2 写回。
    final int schema = (json['schema'] as num?)?.toInt() ?? 1;
    final bool legacyAutoNext = schema < kNovelPrefsSchema;
    ReadingMode mode = ReadingMode.singleLTR;
    if (json['readingMode'] is String) {
      mode = ReadingMode.values.firstWhere(
        (e) => e.name == json['readingMode'],
        orElse: () => ReadingMode.singleLTR,
      );
    }
    NovelChineseConversion chineseConv = NovelChineseConversion.none;
    if (json['novelChineseConversion'] is String) {
      chineseConv = NovelChineseConversion.values.firstWhere(
        (e) => e.name == json['novelChineseConversion'],
        orElse: () => NovelChineseConversion.none,
      );
    }
    ReaderTapZoneLayout comicTap = ReaderTapZoneLayout.lShape;
    if (json['comicTapZoneLayout'] is String) {
      comicTap = ReaderTapZoneLayout.values.firstWhere(
        (e) => e.name == json['comicTapZoneLayout'],
        orElse: () => ReaderTapZoneLayout.lShape,
      );
    }
    ReaderBackgroundColor comicBg = ReaderBackgroundColor.black;
    if (json['comicBackground'] is String) {
      comicBg = ReaderBackgroundColor.values.firstWhere(
        (e) => e.name == json['comicBackground'],
        orElse: () => ReaderBackgroundColor.black,
      );
    }
    ScreenOrientation comicOrient = ScreenOrientation.defaultMode;
    if (json['comicOrientation'] is String) {
      comicOrient = ScreenOrientation.values.firstWhere(
        (e) => e.name == json['comicOrientation'],
        orElse: () => ScreenOrientation.defaultMode,
      );
    }
    ComicInitialZoom comicZoom = ComicInitialZoom.fitWidth;
    if (json['comicInitialZoom'] is String) {
      comicZoom = ComicInitialZoom.values.firstWhere(
        (e) => e.name == json['comicInitialZoom'],
        orElse: () => ComicInitialZoom.fitWidth,
      );
    }
    ComicDoubleTapZoom comicDoubleTap = ComicDoubleTapZoom.x2;
    if (json['comicDoubleTapZoom'] is String) {
      comicDoubleTap = ComicDoubleTapZoom.values.firstWhere(
        (e) => e.name == json['comicDoubleTapZoom'],
        orElse: () => ComicDoubleTapZoom.x2,
      );
    }
    ComicScrollWheel comicWheel = ComicScrollWheel.natural;
    if (json['comicScrollWheel'] is String) {
      comicWheel = ComicScrollWheel.values.firstWhere(
        (e) => e.name == json['comicScrollWheel'],
        orElse: () => ComicScrollWheel.natural,
      );
    }
    TapZoneInvert novelInvert = TapZoneInvert.none;
    if (json['novelTapZoneInvert'] is String) {
      novelInvert = TapZoneInvert.values.firstWhere(
        (e) => e.name == json['novelTapZoneInvert'],
        orElse: () => TapZoneInvert.none,
      );
    }
    NovelPageAnimation novelAnim = NovelPageAnimation.slide;
    if (json['novelPageAnimation'] is String) {
      novelAnim = NovelPageAnimation.values.firstWhere(
        (e) => e.name == json['novelPageAnimation'],
        orElse: () => NovelPageAnimation.slide,
      );
    }
    TapZoneInvert comicInvert = TapZoneInvert.none;
    if (json['comicTapZoneInvert'] is String) {
      comicInvert = TapZoneInvert.values.firstWhere(
        (e) => e.name == json['comicTapZoneInvert'],
        orElse: () => TapZoneInvert.none,
      );
    }
    MouseWheelAction comicWheelAction = MouseWheelAction.zoom;
    if (json['comicMouseWheelAction'] is String) {
      comicWheelAction = MouseWheelAction.values.firstWhere(
        (e) => e.name == json['comicMouseWheelAction'],
        orElse: () => MouseWheelAction.zoom,
      );
    }
    return ReaderDefaultSettings(
      readingMode: mode,
      doubleTapZoom: json['doubleTapZoom'] as bool? ?? true,
      novelFontSize:
          (json['novelFontSize'] as num?)?.toDouble() ?? 18.0,
      novelLineHeight:
          (json['novelLineHeight'] as num?)?.toDouble() ?? 1.8,
      novelTtsSpeechRate:
          (json['novelTtsSpeechRate'] as num?)?.toDouble() ?? 1.0,
      novelChineseConversion: chineseConv,
      comicTapZoneLayout: comicTap,
      comicBackground: comicBg,
      comicOrientation: comicOrient,
      comicSideMargin: (json['comicSideMargin'] as num?)?.toDouble() ?? 0.0,
      comicFlashEnabled: json['comicFlashEnabled'] as bool? ?? false,
      comicFlashTime: (json['comicFlashTime'] as num?)?.toInt() ?? 120,
      comicFlashInterval: (json['comicFlashInterval'] as num?)?.toInt() ?? 0,
      comicFlashColor: _parseFlashColor(json['comicFlashColor']),
      comicInitialZoom: comicZoom,
      comicDoubleTapZoom: comicDoubleTap,
      comicScrollWheel: comicWheel,
      comicMouseWheelAction: comicWheelAction,
      comicFullscreen: json['comicFullscreen'] as bool? ?? true,
      comicShowLongPressMenu:
          json['comicShowLongPressMenu'] as bool? ?? true,
      comicGrayscale: json['comicGrayscale'] as bool? ?? false,
      comicPreventShrink: json['comicPreventShrink'] as bool? ?? false,
      comicChapterTransition:
          json['comicChapterTransition'] as bool? ?? false,
      comicPreloadImageCount:
          ((json['comicPreloadImageCount'] as num?)?.toInt() ?? 4)
              .clamp(1, 16),
      comicSeamlessReading:
          json['comicSeamlessReading'] as bool? ?? true,
      comicShowChapterSeparator:
          json['comicShowChapterSeparator'] as bool? ?? true,
      comicShowChapterSlider:
          json['comicShowChapterSlider'] as bool? ?? true,
      comicWebtoonLimitDecodeSize:
          json['comicWebtoonLimitDecodeSize'] as bool? ?? true,
      comicReaderScrollSpeed:
          ((json['comicReaderScrollSpeed'] as num?)?.toDouble() ?? 1.0)
              .clamp(0.5, 3.0),
      comicVolumeKeyPageTurn:
          json['comicVolumeKeyPageTurn'] as bool? ?? false,
      comicVolumeKeyPageTurnDistancePercent:
          ((json['comicVolumeKeyPageTurnDistancePercent'] as num?)?.toInt() ??
                  40)
              .clamp(10, 100),
      comicEnableLongPressToZoom:
          json['comicEnableLongPressToZoom'] as bool? ?? false,
      comicLongPressZoomPosition: _parseLongPressZoomPosition(
          json['comicLongPressZoomPosition']),
      comicZoomStart: _parseZoomStart(json['comicZoomStart']),
      comicAutoPageTurningInterval:
          ((json['comicAutoPageTurningInterval'] as num?)?.toInt() ?? 0)
              .clamp(0, 20),
      // 迁移：旧数据没有独立开关字段，interval > 0 即视为开启。
      comicAutoPageTurningEnabled:
          json['comicAutoPageTurningEnabled'] as bool? ??
              (((json['comicAutoPageTurningInterval'] as num?)?.toInt() ?? 0) >
                  0),
      comicAutoScroll: json['comicAutoScroll'] as bool? ?? false,
      comicPageAnimation:
          _parsePageAnimation(json['comicPageAnimation']),
          comicMotionEffects:
              MotionEffectSettings.fromJson(json['comicMotionEffects']),
      comicDoubleTapAnimSpeed:
          ((json['comicDoubleTapAnimSpeed'] as num?)?.toInt() ?? 500)
              .clamp(100, 1500),
      comicReaderPageSpacing:
          ((json['comicReaderPageSpacing'] as num?)?.toInt() ?? 0)
              .clamp(0, 50),
      comicShowSingleImageOnFirstPage:
          json['comicShowSingleImageOnFirstPage'] as bool? ?? false,
      comicShowClockBattery:
          json['comicShowClockBattery'] as bool? ?? false,
      comicClockBatteryPosition:
          _parseClockBatteryPosition(json['comicClockBatteryPosition']),
      comicClockBatteryMargin:
          (json['comicClockBatteryMargin'] as num?)?.toDouble() ?? 8.0,
      comicClockBatteryOpacity:
          ((json['comicClockBatteryOpacity'] as num?)?.toDouble() ?? 0.8)
              .clamp(0.1, 1.0),
      comicClockBatteryFontSize:
          (json['comicClockBatteryFontSize'] as num?)?.toDouble() ?? 12.0,
      comicReaderBrightness:
          ((json['comicReaderBrightness'] as num?)?.toDouble() ?? 0.0)
              .clamp(-1.0, 1.0),
      comicNightLightEnabled:
          json['comicNightLightEnabled'] as bool? ?? false,
      comicNightLightOpacity:
          ((json['comicNightLightOpacity'] as num?)?.toDouble() ?? 0.4)
              .clamp(0.1, 0.85),
      comicColorProfile: _parseColorProfile(json['comicColorProfile']),
      comicUpscaleMode: parseMangaUpscaleMode(json['comicUpscaleMode']),
      comicEinkRefreshEnabled:
          json['comicEinkRefreshEnabled'] as bool? ?? false,
      comicEinkRefreshInterval:
          ((json['comicEinkRefreshInterval'] as num?)?.toInt() ?? 10)
              .clamp(1, 50),
      comicEinkRefreshDuration:
          ((json['comicEinkRefreshDuration'] as num?)?.toInt() ?? 200)
              .clamp(50, 1000),
      comicEinkRefreshStyle:
          _parseEInkRefreshStyle(json['comicEinkRefreshStyle']),
      comicIsAutoFavorite: json['comicIsAutoFavorite'] as bool? ?? false,
      comicAutoDownloadChapters:
          json['comicAutoDownloadChapters'] as bool? ?? false,
      comicSkipReadChapters:
          json['comicSkipReadChapters'] as bool? ?? false,
      comicSkipFilteredChapters:
          json['comicSkipFilteredChapters'] as bool? ?? false,
      comicSkipDuplicateChapters:
          json['comicSkipDuplicateChapters'] as bool? ?? false,
      comicReaderScreenPicNumberForPortrait:
          ((json['comicReaderScreenPicNumberForPortrait'] as num?)?.toInt() ??
                  1)
              .clamp(1, 5),
      comicReaderScreenPicNumberForLandscape:
          ((json['comicReaderScreenPicNumberForLandscape'] as num?)?.toInt() ??
                  1)
              .clamp(1, 5),
      novelParagraphSpacing:
          (json['novelParagraphSpacing'] as num?)?.toDouble() ?? 16.0,
      novelMargin: (json['novelMargin'] as num?)?.toDouble() ?? 24.0,
      novelShadow: json['novelShadow'] as bool? ?? false,
      novelBgPresetIndex: json['novelBgPresetIndex'] as int? ?? 2,
      novelTapZoneInvert: novelInvert,
      novelPageAnimation: novelAnim,
      novelBrightness:
          (json['novelBrightness'] as num?)?.toDouble() ?? 0.5,
      novelCustomBgColor: json['novelCustomBgColor'] as int?,
      novelCustomTextColor: json['novelCustomTextColor'] as int?,
      novelEmphasisColor: json['novelEmphasisColor'] as int?,
      novelLetterSpacing:
          (json['novelLetterSpacing'] as num?)?.toDouble() ?? 0.0,
      novelFontBold: json['novelFontBold'] as bool? ?? false,
      novelFontItalic: json['novelFontItalic'] as bool? ?? false,
      novelFontUnderline: json['novelFontUnderline'] as bool? ?? false,
      novelCustomFontPath: json['novelCustomFontPath'] as String?,
      novelFontFamily: json['novelFontFamily'] as String?,
      novelBottomToolbarSlots:
          (json['novelBottomToolbarSlots'] as List?)?.cast<String>() ??
              <String>['toc', 'prevChapter', 'nightMode', 'autoPage', 'settings', 'bookmark'],
      novelTapZoneLayout:
          json['novelTapZoneLayout'] as String? ?? 'lShape',
      novelAutoPageInterval:
          (json['novelAutoPageInterval'] as num?)?.toInt() ?? 0,
      novelAutoPageSmooth: json['novelAutoPageSmooth'] as bool? ?? false,
      novelVolumeKeyPageTurn:
          json['novelVolumeKeyPageTurn'] as bool? ?? true,
      novelThemeFollow:
          json['novelThemeFollow'] as String? ?? 'followApp',
      novelShadowColor: json['novelShadowColor'] as int?,
      novelShadowBlur:
          (json['novelShadowBlur'] as num?)?.toDouble() ?? 0.5,
      novelShadowOffsetX:
          (json['novelShadowOffsetX'] as num?)?.toDouble() ?? 0.5,
      novelShadowOffsetY:
          (json['novelShadowOffsetY'] as num?)?.toDouble() ?? 0.5,
      novelUnderlineColor: json['novelUnderlineColor'] as int?,
      novelUnderlineDashed:
          json['novelUnderlineDashed'] as bool? ?? false,
      novelTwoPageMode: json['novelTwoPageMode'] as bool? ?? false,
      novelUnderlineThickness:
          (json['novelUnderlineThickness'] as num?)?.toDouble() ?? 1.0,
      novelUnderlineDashLength:
          (json['novelUnderlineDashLength'] as num?)?.toDouble() ?? 4.0,
      novelUnderlineDashGap:
          (json['novelUnderlineDashGap'] as num?)?.toDouble() ?? 2.0,
      novelShowChapterTitleInBody:
          json['novelShowChapterTitleInBody'] as bool? ?? true,
      novelTitleAlign:
          json['novelTitleAlign'] as String? ?? 'left',
      novelTitleFontScale:
          (json['novelTitleFontScale'] as num?)?.toDouble() ?? 1.5,
      novelTitleBold: json['novelTitleBold'] as bool? ?? true,
      novelTitleFontFamily: json['novelTitleFontFamily'] as String?,
      novelTitleCustomFontPath:
          json['novelTitleCustomFontPath'] as String?,
      novelTitleSegmentMode:
          json['novelTitleSegmentMode'] as bool? ?? false,
      novelTitleSubScale:
          (json['novelTitleSubScale'] as num?)?.toDouble() ?? 0.8,
      novelTitleSegmentSpacing:
          (json['novelTitleSegmentSpacing'] as num?)?.toDouble() ?? 8.0,
      novelTitleSubLineSpacing:
          (json['novelTitleSubLineSpacing'] as num?)?.toDouble() ?? 1.3,
      novelTitleTopMargin:
          (json['novelTitleTopMargin'] as num?)?.toDouble() ?? 0.0,
      novelTitleBottomMargin:
          (json['novelTitleBottomMargin'] as num?)?.toDouble() ?? 0.0,
      novelTitleColor: json['novelTitleColor'] as int?,
      novelHeaderLeft:
          json['novelHeaderLeft'] as String? ?? 'bookName',
      novelHeaderRight:
          json['novelHeaderRight'] as String? ?? 'time',
      novelHeaderCenter:
          json['novelHeaderCenter'] as String? ?? 'none',
      novelFooterLeft:
          json['novelFooterLeft'] as String? ?? 'chapterTitle',
      novelFooterRight:
          json['novelFooterRight'] as String? ?? 'pageNumber',
      novelFooterCenter:
          json['novelFooterCenter'] as String? ?? 'none',
      novelHeaderFooterColor: json['novelHeaderFooterColor'] as int?,
      novelHeaderFooterMargin:
          (json['novelHeaderFooterMargin'] as num?)?.toDouble() ?? 12.0,
      novelTtsBackground:
          json['novelTtsBackground'] as bool? ?? false,
      novelTtsAutoNext:
          legacyAutoNext ? true : (json['novelTtsAutoNext'] as bool? ?? true),
      novelTtsSleepTimer:
          (json['novelTtsSleepTimer'] as num?)?.toInt() ?? 0,
      novelScrollWheelInverted:
          json['novelScrollWheelInverted'] as bool? ?? false,
      // 排版增强
      novelFontWeightValue:
          ((json['novelFontWeightValue'] as num?)?.toInt() ?? 700)
              .clamp(100, 900),
      novelTextAlignMode:
          json['novelTextAlignMode'] as String? ?? 'start',
      novelLineBreakMode:
          json['novelLineBreakMode'] as String? ?? 'standard',
      novelUnderlineStyle:
          json['novelUnderlineStyle'] as String? ?? 'solid',
      // 滚动模式图文增强
      novelScrollImageMode:
          json['novelScrollImageMode'] as String? ?? 'banner',
      novelScrollImageAlign:
          json['novelScrollImageAlign'] as String? ?? 'center',
      comicFilterBrightness:
          (json['comicFilterBrightness'] as num?)?.toDouble() ?? 0.0,
      comicFilterContrast:
          (json['comicFilterContrast'] as num?)?.toDouble() ?? 0.0,
      comicFilterColorTemp:
          (json['comicFilterColorTemp'] as num?)?.toDouble() ?? 0.0,
      comicFilterInverted: json['comicFilterInverted'] as bool? ?? false,
      comicTapZoneInvert: comicInvert,
      comicCropEdge: json['comicCropEdge'] as bool? ?? false,
      comicShowPageNumber: json['comicShowPageNumber'] as bool? ?? true,
      comicProgressBarOnRight:
          json['comicProgressBarOnRight'] as bool? ?? true,
      comicKeepScreenOn: json['comicKeepScreenOn'] as bool? ?? false,
      comicRotateLandscape: json['comicRotateLandscape'] as bool? ?? false,
      comicSplitDoublePage: json['comicSplitDoublePage'] as bool? ?? false,
      comicFilterSaturation:
          (json['comicFilterSaturation'] as num?)?.toDouble() ?? 0.0,
      comicFilterHue: (json['comicFilterHue'] as num?)?.toDouble() ?? 0.0,
    );
  }

  // ── 桥接：把全局默认映射为漫画运行时偏好（让设置页默认值在打开漫画时生效）──
  static const Map<ComicInitialZoom, ReaderInitialZoom> _comicZoomMap =
      <ComicInitialZoom, ReaderInitialZoom>{
    ComicInitialZoom.fitWidth: ReaderInitialZoom.fitWidth,
    ComicInitialZoom.fitHeight: ReaderInitialZoom.fitHeight,
    ComicInitialZoom.original: ReaderInitialZoom.original,
  };

  static const Map<ComicDoubleTapZoom, double> _comicDoubleTapMap =
      <ComicDoubleTapZoom, double>{
    ComicDoubleTapZoom.x2: 2.0,
    ComicDoubleTapZoom.x3: 3.0,
  };

  static const Map<ComicScrollWheel, bool> _comicWheelMap =
      <ComicScrollWheel, bool>{
    ComicScrollWheel.natural: false,
    ComicScrollWheel.inverted: true,
  };

  ReaderPreferences toReaderPreferences() {
    return ReaderPreferences(
      readingMode: readingMode,
      doubleTapZoom: doubleTapZoom,
      orientation: comicOrientation,
      background: comicBackground,
      tapZoneLayout: comicTapZoneLayout,
      tapZoneInvert: comicTapZoneInvert,
      minScale: 1.0,
      maxScale: 4.0,
      filterBrightness: comicFilterBrightness,
      filterContrast: comicFilterContrast,
      filterColorTemp: comicFilterColorTemp,
      filterInverted: comicFilterInverted,
      sideMargin: comicSideMargin,
      flashEnabled: comicFlashEnabled,
      flashTime: comicFlashTime,
      flashInterval: comicFlashInterval,
      flashColor: comicFlashColor,
      initialZoom: _comicZoomMap[comicInitialZoom] ?? ReaderInitialZoom.fitWidth,
      doubleTapZoomScale: _comicDoubleTapMap[comicDoubleTapZoom] ?? 2.0,
      scrollWheelInverted: _comicWheelMap[comicScrollWheel] ?? false,
      mouseWheelAction: comicMouseWheelAction,
      fullscreen: comicFullscreen,
      showLongPressMenu: comicShowLongPressMenu,
      filterGrayscale: comicGrayscale,
      preventShrink: comicPreventShrink,
      showChapterTransition: comicChapterTransition,
      cropEdge: comicCropEdge,
      showPageNumber: comicShowPageNumber,
      progressBarOnRight: comicProgressBarOnRight,
      keepScreenOn: comicKeepScreenOn,
      rotateLandscape: comicRotateLandscape,
      splitDoublePage: comicSplitDoublePage,
      filterSaturation: comicFilterSaturation,
      filterHue: comicFilterHue,
      preloadImageCount: comicPreloadImageCount,
      seamlessReading: comicSeamlessReading,
      showChapterSeparator: comicShowChapterSeparator,
      showChapterSlider: comicShowChapterSlider,
      webtoonLimitDecodeSize: comicWebtoonLimitDecodeSize,
      readerScrollSpeed: comicReaderScrollSpeed,
      volumeKeyPageTurn: comicVolumeKeyPageTurn,
      volumeKeyPageTurnDistancePercent:
          comicVolumeKeyPageTurnDistancePercent,
      enableLongPressToZoom: comicEnableLongPressToZoom,
      longPressZoomPosition: comicLongPressZoomPosition,
      zoomStart: comicZoomStart,
      autoPageTurningEnabled: comicAutoPageTurningEnabled,
      autoPageTurningInterval: comicAutoPageTurningInterval,
      autoScroll: comicAutoScroll,
      pageAnimation: comicPageAnimation,
      motionEffects: comicMotionEffects,
      doubleTapAnimSpeed: comicDoubleTapAnimSpeed,
      readerPageSpacing: comicReaderPageSpacing,
      showSingleImageOnFirstPage: comicShowSingleImageOnFirstPage,
      showClockBattery: comicShowClockBattery,
      clockBatteryPosition: comicClockBatteryPosition,
      clockBatteryMargin: comicClockBatteryMargin,
      clockBatteryOpacity: comicClockBatteryOpacity,
      clockBatteryFontSize: comicClockBatteryFontSize,
      readerBrightness: comicReaderBrightness,
      nightLightEnabled: comicNightLightEnabled,
      nightLightOpacity: comicNightLightOpacity,
      colorProfile: comicColorProfile,
      upscaleMode: comicUpscaleMode,
      einkRefreshEnabled: comicEinkRefreshEnabled,
      einkRefreshInterval: comicEinkRefreshInterval,
      einkRefreshDuration: comicEinkRefreshDuration,
      einkRefreshStyle: comicEinkRefreshStyle,
      isAutoFavorite: comicIsAutoFavorite,
      autoDownloadChapters: comicAutoDownloadChapters,
      skipReadChapters: comicSkipReadChapters,
      skipFilteredChapters: comicSkipFilteredChapters,
      skipDuplicateChapters: comicSkipDuplicateChapters,
      readerScreenPicNumberForPortrait: comicReaderScreenPicNumberForPortrait,
      readerScreenPicNumberForLandscape:
          comicReaderScreenPicNumberForLandscape,
    );
  }

  // ── 桥接：把全局默认映射为小说运行时偏好 ──
  NovelReaderPreferences toNovelReaderPreferences() {
    return NovelReaderPreferences(
      fontSize: novelFontSize,
      lineHeight: novelLineHeight,
      paragraphSpacing: novelParagraphSpacing,
      margin: novelMargin,
      bgPresetIndex: novelBgPresetIndex,
      customBgColor: novelCustomBgColor,
      customTextColor: novelCustomTextColor,
      emphasisColor: novelEmphasisColor,
      letterSpacing: novelLetterSpacing,
      fontBold: novelFontBold,
      fontItalic: novelFontItalic,
      fontUnderline: novelFontUnderline,
      fontFamily: novelFontFamily,
      customFontPath: novelCustomFontPath,
      shadow: novelShadow,
      shadowColor: novelShadowColor,
      shadowBlur: novelShadowBlur,
      shadowOffsetX: novelShadowOffsetX,
      shadowOffsetY: novelShadowOffsetY,
      pageAnimation: novelPageAnimation,
      chineseConvert: novelChineseConversion.name,
      tapZoneInvert: novelTapZoneInvert,
      tapZoneLayout: ReaderTapZoneLayout.values.firstWhere(
        (e) => e.name == novelTapZoneLayout,
        orElse: () => ReaderTapZoneLayout.lShape,
      ),
      themeFollow: NovelThemeFollow.values.firstWhere(
        (e) => e.name == novelThemeFollow,
        orElse: () => NovelThemeFollow.followApp,
      ),
      bottomToolbarSlots: novelBottomToolbarSlots.map((s) => NovelBottomTool.fromString(s) ?? NovelBottomTool.toc).toList(),
      autoPageInterval: novelAutoPageInterval,
      autoPageSmooth: novelAutoPageSmooth,
      volumeKeyPageTurn: novelVolumeKeyPageTurn,
      // 下划线
      underlineColor: novelUnderlineColor,
      underlineDashed: novelUnderlineDashed,
      twoPageMode: novelTwoPageMode,
      underlineThickness: novelUnderlineThickness,
      underlineDashLength: novelUnderlineDashLength,
      underlineDashGap: novelUnderlineDashGap,
      // 标题
      showChapterTitleInBody: novelShowChapterTitleInBody,
      titleAlign: NovelTitleAlign.values.firstWhere(
        (e) => e.name == novelTitleAlign,
        orElse: () => NovelTitleAlign.left,
      ),
      titleFontScale: novelTitleFontScale,
      titleBold: novelTitleBold,
      titleFontFamily: novelTitleFontFamily,
      titleCustomFontPath: novelTitleCustomFontPath,
      titleSegmentMode: novelTitleSegmentMode,
      titleSubScale: novelTitleSubScale,
      titleSegmentSpacing: novelTitleSegmentSpacing,
      titleSubLineSpacing: novelTitleSubLineSpacing,
      titleTopMargin: novelTitleTopMargin,
      titleBottomMargin: novelTitleBottomMargin,
      titleColor: novelTitleColor,
      // 页眉页脚
      headerLeft: NovelHeaderFooterContent.values.firstWhere(
        (e) => e.name == novelHeaderLeft,
        orElse: () => NovelHeaderFooterContent.bookName,
      ),
      headerRight: NovelHeaderFooterContent.values.firstWhere(
        (e) => e.name == novelHeaderRight,
        orElse: () => NovelHeaderFooterContent.time,
      ),
      headerCenter: NovelHeaderFooterContent.values.firstWhere(
        (e) => e.name == novelHeaderCenter,
        orElse: () => NovelHeaderFooterContent.none,
      ),
      footerLeft: NovelHeaderFooterContent.values.firstWhere(
        (e) => e.name == novelFooterLeft,
        orElse: () => NovelHeaderFooterContent.chapterTitle,
      ),
      footerRight: NovelHeaderFooterContent.values.firstWhere(
        (e) => e.name == novelFooterRight,
        orElse: () => NovelHeaderFooterContent.pageNumber,
      ),
      footerCenter: NovelHeaderFooterContent.values.firstWhere(
        (e) => e.name == novelFooterCenter,
        orElse: () => NovelHeaderFooterContent.none,
      ),
      headerFooterColor: novelHeaderFooterColor,
      headerFooterMargin: novelHeaderFooterMargin,
      // TTS
      ttsSpeechRate: novelTtsSpeechRate,
      ttsBackground: novelTtsBackground,
      ttsAutoNext: novelTtsAutoNext,
      ttsSleepTimer: novelTtsSleepTimer,
      scrollWheelInverted: novelScrollWheelInverted,
      // 排版增强
      fontWeightValue: novelFontWeightValue,
      textAlignMode: NovelTextAlignMode.values.firstWhere(
        (e) => e.name == novelTextAlignMode,
        orElse: () => NovelTextAlignMode.start,
      ),
      lineBreakMode: NovelLineBreakMode.values.firstWhere(
        (e) => e.name == novelLineBreakMode,
        orElse: () => NovelLineBreakMode.standard,
      ),
      underlineStyle: NovelUnderlineStyle.values.firstWhere(
        (e) => e.name == novelUnderlineStyle,
        orElse: () => NovelUnderlineStyle.solid,
      ),
      // 滚动模式图文增强
      scrollImageMode: NovelScrollImageMode.values.firstWhere(
        (e) => e.name == novelScrollImageMode,
        orElse: () => NovelScrollImageMode.banner,
      ),
      scrollImageAlign: NovelScrollImageAlign.values.firstWhere(
        (e) => e.name == novelScrollImageAlign,
        orElse: () => NovelScrollImageAlign.center,
      ),
    );
  }
}

/// 阅读器默认设置持久化存储（key: `reader_default_settings_v1`）。
class ReaderDefaultSettingsStore {
  static const String _key = 'reader_default_settings_v1';

  final PrefsBackend _backend;

  ReaderDefaultSettingsStore({PrefsBackend? backend})
      : _backend = backend ?? const SharedPrefsBackend();

  Future<ReaderDefaultSettings> load() async {
    final raw = await _backend.get(_key);
    if (raw == null || raw.isEmpty) return const ReaderDefaultSettings();
    try {
      return ReaderDefaultSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } on Object {
      return const ReaderDefaultSettings();
    }
  }

  Future<void> save(ReaderDefaultSettings settings) async {
    await _backend.set(_key, jsonEncode(settings.toJson()));
  }
}
