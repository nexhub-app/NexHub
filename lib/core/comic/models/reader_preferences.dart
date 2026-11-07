/// 阅读器偏好模型（漫画 / 小说共用）。
///
/// 仅承载「阅读模式 / 方向 / 背景 / 点击区域布局 / 双击缩放」等设置，
/// 颜色以索引形式引用 [ReaderTokens] 预设，绝不在此硬编码 [Color]（治理规则）。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/reader_tokens.dart';
import '../manga_upscale.dart';
import 'motion_effect_settings.dart';

/// 漫画 5 种阅读模式（文档 7.1 最终态，移除旧 double）。
enum ReadingMode {
  singleLTR,
  singleRTL,
  singleVertical,
  webtoon,
  webtoonWithGap;

  /// 是否为连续纵向滚动（webtoon / webtoonWithGap）。
  bool get isWebtoon =>
      this == ReadingMode.webtoon || this == ReadingMode.webtoonWithGap;

  /// 是否为单页翻页（横向/竖向）。
  bool get isPaged => !isWebtoon;

  String l10nKey() => switch (this) {
        ReadingMode.singleLTR => 'readerModeSingleLTR',
        ReadingMode.singleRTL => 'readerModeSingleRTL',
        ReadingMode.singleVertical => 'readerModeSingleVertical',
        ReadingMode.webtoon => 'readerModeWebtoon',
        ReadingMode.webtoonWithGap => 'readerModeWebtoonWithGap',
      };
}

/// 屏幕方向（文档 7.2，替代旧 lockLandscape:bool）。
enum ScreenOrientation {
  defaultMode,
  followSystem,
  portrait,
  landscape,
  lockPortrait,
  lockLandscape,
  reversePortrait;

  String l10nKey() => switch (this) {
        ScreenOrientation.defaultMode => 'readerOrientationDefault',
        ScreenOrientation.followSystem => 'readerOrientationSystem',
        ScreenOrientation.portrait => 'readerOrientationPortrait',
        ScreenOrientation.landscape => 'readerOrientationLandscape',
        ScreenOrientation.lockPortrait => 'readerOrientationLockPortrait',
        ScreenOrientation.lockLandscape => 'readerOrientationLockLandscape',
        ScreenOrientation.reversePortrait => 'readerOrientationReversePortrait',
      };
}

/// 阅读器背景（黑 / 灰 / 白 / 自动）。
enum ReaderBackgroundColor {
  black,
  gray,
  white,
  auto;

  /// 解析为实际颜色索引（auto 回退到白色，由外部结合 brightness 处理）。
  int toPresetIndex() => switch (this) {
        ReaderBackgroundColor.black => 0,
        ReaderBackgroundColor.gray => 1,
        ReaderBackgroundColor.white => 2,
        ReaderBackgroundColor.auto => 2,
      };

  static ReaderBackgroundColor fromIndex(int index) => switch (index) {
        0 => ReaderBackgroundColor.black,
        1 => ReaderBackgroundColor.gray,
        _ => ReaderBackgroundColor.white,
      };

  String l10nKey() => switch (this) {
        ReaderBackgroundColor.black => 'readerBgBlack',
        ReaderBackgroundColor.gray => 'readerBgGray',
        ReaderBackgroundColor.white => 'readerBgWhite',
        ReaderBackgroundColor.auto => 'readerBgAuto',
      };
}

/// 点击区域布局（文档 7.3）。
///
/// 历史上曾有 `defaultLayout`（左 45% prev / 中 10% toggle / 右 45% next），
/// 其几何已并入新的 `leftRight` 布局；`lShape` 成为新的默认布局
/// （用户决策：最终 5 布局 = L形(默认)/kindle/两侧/左右/关闭）。
/// 故枚举只有 5 个值；任何旧数据里 `defaultLayout` 字符串在 [ReaderPreferences.fromJson]
/// 会回退到 `lShape`。
enum ReaderTapZoneLayout {
  /// L 形（默认）：左上=上一页，右下=下一页，其余=切换控件。
  lShape,

  /// 左右：左 45% = 上一页，右 45% = 下一页，中间 10% 条 = 切换控件。
  leftRight,

  /// Kindle：左 35%=上，右 65%=下，上 15% 留空。
  kindle,

  /// 两侧：中上留空、左右=下、中下=上。
  bothSides,

  /// 关闭：整屏点击=切换控件，无翻页热区。
  off;

  String l10nKey() => switch (this) {
        ReaderTapZoneLayout.lShape => 'readerTapLShape',
        ReaderTapZoneLayout.leftRight => 'readerTapLeftRight',
        ReaderTapZoneLayout.kindle => 'readerTapKindle',
        ReaderTapZoneLayout.bothSides => 'readerTapBothSides',
        ReaderTapZoneLayout.off => 'readerTapOff',
      };
}

/// 点击区域方向反转（16.5 表「点击分区 5 布局 + 反色」）。
///
/// 在 [ReaderTapZoneLayout] 选定的布局之上，对 prev/next 命中再做一层方向
/// 反转，适配左撇子或特殊阅读习惯。竖向 webtoon 模式下 `leftRight` 不生效
/// （条漫本就是上下滚动），`upDown` 反转滚动方向。
enum TapZoneInvert {
  /// 不反转。
  none,

  /// 左右反转：prev ↔ next 互换（竖向模式不生效）。
  leftRight,

  /// 上下反转：仅对竖向滚动（webtoon）生效，反向滚动。
  upDown,

  /// 全反转：左右 + 上下都反转。
  all;

  String l10nKey() => switch (this) {
        TapZoneInvert.none => 'readerTapInvertNone',
        TapZoneInvert.leftRight => 'readerTapInvertLeftRight',
        TapZoneInvert.upDown => 'readerTapInvertUpDown',
        TapZoneInvert.all => 'readerTapInvertAll',
      };
}

/// 翻页闪光颜色（漫画阅读器「翻页闪光」设置）。
enum ReaderFlashColor {
  /// 黑屏闪。
  black,

  /// 白屏闪。
  white,

  /// 先黑后白（两段连续闪）。
  blackWhite;

  String l10nKey() => switch (this) {
        ReaderFlashColor.black => 'readerFlashBlack',
        ReaderFlashColor.white => 'readerFlashWhite',
        ReaderFlashColor.blackWhite => 'readerFlashBlackWhite',
      };
}

/// 初始缩放（漫画阅读器「初始缩放」设置）。
enum ReaderInitialZoom {
  /// 适配宽度：图片宽度撑满屏幕宽度（长条漫画常用）。
  fitWidth,

  /// 适配高度：图片高度撑满屏幕高度（单页漫画常用）。
  fitHeight,

  /// 原始大小：按图片真实像素 1:1 显示。
  original;

  String l10nKey() => switch (this) {
        ReaderInitialZoom.fitWidth => 'readerZoomFitWidth',
        ReaderInitialZoom.fitHeight => 'readerZoomFitHeight',
        ReaderInitialZoom.original => 'readerZoomOriginal',
      };
}

/// 解析初始缩放（容错：非法字符串回退 fitWidth）。
ReaderInitialZoom _parseInitialZoom(Object? raw) {
  if (raw is String) {
    return ReaderInitialZoom.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => ReaderInitialZoom.fitWidth,
    );
  }
  return ReaderInitialZoom.fitWidth;
}

/// 图片色彩配置预设（ICC 校色近似）：在手动滤镜（色温/色相/饱和度）之外，
/// 提供一键套用的色彩风格。Flutter 原生 ICC displayProfile 支持有限，此处用
/// 固定的 4x5 颜色矩阵近似常见显示特性（见 [ReaderImageFilter.profileMatrix]）。
enum ReaderColorProfile {
  /// 无（跟随手动滤镜，不叠加预设）。
  none,

  /// sRGB：标准色域，近似中性。
  srgb,

  /// 暖色（纸感）：轻微提暖，适合暖屏/夜读。
  warm,

  /// 冷色：轻微提冷，适合日光屏。
  cool,

  /// 漫画：增艳 + 微暖，线条更跳。
  manga,

  /// 纸感：降饱和 + 微暖，模拟印刷纸质观感。
  paper;

  String l10nKey() => switch (this) {
        ReaderColorProfile.none => 'readerColorProfileNone',
        ReaderColorProfile.srgb => 'readerColorProfileSrgb',
        ReaderColorProfile.warm => 'readerColorProfileWarm',
        ReaderColorProfile.cool => 'readerColorProfileCool',
        ReaderColorProfile.manga => 'readerColorProfileManga',
        ReaderColorProfile.paper => 'readerColorProfilePaper',
      };
}

/// 解析色彩配置预设（容错：非法字符串回退 none）。
ReaderColorProfile _parseColorProfile(Object? raw) {
  if (raw is String) {
    return ReaderColorProfile.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => ReaderColorProfile.none,
    );
  }
  return ReaderColorProfile.none;
}

/// E-Ink 刷新闪烁样式（E-Ink 刷新设置）。
enum ReaderEInkRefreshStyle {
  /// 白闪：全屏白覆盖后淡出（墨水屏清残影常见）。
  white,

  /// 黑闪：全屏黑覆盖后淡出。
  black;

  String l10nKey() => switch (this) {
        ReaderEInkRefreshStyle.white => 'readerEInkRefreshWhite',
        ReaderEInkRefreshStyle.black => 'readerEInkRefreshBlack',
      };
}

/// 解析 E-Ink 刷新样式（容错：非法字符串回退 white）。
ReaderEInkRefreshStyle _parseEInkRefreshStyle(Object? raw) {
  if (raw is String) {
    return ReaderEInkRefreshStyle.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => ReaderEInkRefreshStyle.white,
    );
  }
  return ReaderEInkRefreshStyle.white;
}

/// 解析闪光颜色（容错：非法字符串回退黑）。
ReaderFlashColor _parseFlashColor(Object? raw) {
  if (raw is String) {
    return ReaderFlashColor.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => ReaderFlashColor.black,
    );
  }
  return ReaderFlashColor.black;
}

/// 鼠标滚轮作用（漫画阅读器「鼠标滚轮」设置）。
///
/// - [zoom]：滚轮缩放页面（默认）。
/// - [page]：滚轮翻页（条漫模式下滚轮始终滚动页面，不在此列）。
enum MouseWheelAction {
  /// 滚轮缩放页面。
  zoom,

  /// 滚轮翻页。
  page;

  /// 解析为 l10n key（容错：非法字符串回退 [zoom]）。
  String l10nKey() => switch (this) {
        MouseWheelAction.zoom => 'readerWheelZoom',
        MouseWheelAction.page => 'readerWheelPage',
      };
}

/// 缩放锚点（双击 / 长按缩放的锚点来源）。
enum ZoomStart {
  /// 屏幕左侧（左右 1/4 处）。
  left,

  /// 屏幕中心（默认）。
  center,

  /// 屏幕右侧（左右 3/4 处）。
  right;

  String l10nKey() => switch (this) {
        ZoomStart.left => 'readerZoomStartLeft',
        ZoomStart.center => 'readerZoomStartCenter',
        ZoomStart.right => 'readerZoomStartRight',
      };
}

/// 长按缩放锚点。
enum LongPressZoomPosition {
  /// 按触点放大（默认）。
  press,

  /// 按屏幕中心放大。
  center;

  String l10nKey() => switch (this) {
        LongPressZoomPosition.press => 'readerLongPressAtPress',
        LongPressZoomPosition.center => 'readerLongPressAtCenter',
      };
}

/// 翻页过渡动画：paged 模式翻页时的视觉过渡。
enum ReaderPageAnimation {
  /// 无动画（瞬切）。
  none,

  /// 滑入（默认）。
  slide,

  /// 淡入淡出。
  fade;

  String l10nKey() => switch (this) {
        ReaderPageAnimation.none => 'readerPageAnimNone',
        ReaderPageAnimation.slide => 'readerPageAnimSlide',
        ReaderPageAnimation.fade => 'readerPageAnimFade',
      };
}

/// 时间/电量浮层位置：四角。
enum ClockBatteryPosition {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight;

  String l10nKey() => switch (this) {
        ClockBatteryPosition.topLeft => 'readerClockPosTopLeft',
        ClockBatteryPosition.topRight => 'readerClockPosTopRight',
        ClockBatteryPosition.bottomLeft => 'readerClockPosBottomLeft',
        ClockBatteryPosition.bottomRight => 'readerClockPosBottomRight',
      };
}

/// 解析滚轮作用（容错：非法字符串回退 zoom）。
MouseWheelAction _parseMouseWheelAction(Object? raw) {
  if (raw is String) {
    return MouseWheelAction.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => MouseWheelAction.zoom,
    );
  }
  return MouseWheelAction.zoom;
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

/// 阅读器偏好（按作品持久化）。
class ReaderPreferences {
  final ReadingMode readingMode;
  final bool doubleTapZoom;
  final ScreenOrientation orientation;
  final ReaderBackgroundColor background;
  final ReaderTapZoneLayout tapZoneLayout;
  final TapZoneInvert tapZoneInvert;
  final double minScale;
  final double maxScale;

  /// 图片滤镜：亮度 / 对比度 / 色温，范围 -1.0~1.0，0.0 为不变。
  /// 用 4x5 颜色矩阵实时合成，见 reader_image_filter.dart。
  final double filterBrightness;
  final double filterContrast;
  final double filterColorTemp;

  /// 图片滤镜：饱和度，范围 -1.0~1.0，0.0 为不变；-1 退化为灰度。
  final double filterSaturation;

  /// 图片滤镜：色相旋转，范围 -1.0~1.0，映射到 -180°~180°；0.0 为不变。
  final double filterHue;

  /// 图片反色滤镜（雷区 11）：用 `ColorFilter.mode(Colors.white, BlendMode.difference)`
  /// 实现，避免 matrix 方案在桌面端变全黑的 bug。true 时叠加反色层。
  final bool filterInverted;

  /// 裁边（去除漫画图四周留白，简单版用 BoxFit.cover/居中裁切）。
  final bool cropEdge;

  /// 显示页码（底栏页码 indicator 开关）。
  final bool showPageNumber;

  /// 进度条在右侧竖向显示（false 时改为底部横向）。
  final bool progressBarOnRight;

  /// 屏幕常亮（wakelock_plus：true 时阻止息屏）。
  final bool keepScreenOn;

  /// 单页旋转时强制横屏（与图片旋转 quarterTurns 解耦）。
  final bool rotateLandscape;

  /// 双页拆分（占位字段，精细拼页逻辑属）。
  final bool splitDoublePage;

  /// 宽屏自动双页：横屏且宽度达桌面断点（平板横屏 / 桌面宽窗口）时自动
  /// 启用跨页，与 [splitDoublePage] 任一满足即生效；竖排 / 长条模式不参与。
  final bool autoDoublePageOnWide;

  /// 左右留白（页面左右内边距），取值范围 0.0~0.5，表示占屏幕宽度的比例。
  /// 0 = 无边距；渲染时在图片左右各加 sideMargin * 屏宽 的留白。
  final double sideMargin;

  /// 翻页闪光开关（翻页时屏幕闪一下，缓解长条 / 翻页的视觉跳变）。
  final bool flashEnabled;

  /// 闪光时长（毫秒），仅 [flashEnabled] 时生效。
  final int flashTime;

  /// 闪光延迟（毫秒）：翻页后延迟多久才闪（0 = 立即）。
  final int flashInterval;

  /// 闪光颜色（黑 / 白 / 黑→白）。
  final ReaderFlashColor flashColor;

  /// 初始缩放（fitWidth / fitHeight / original）。
  final ReaderInitialZoom initialZoom;

  /// 打开阅读器时是否自动进入全屏（沉浸式隐藏系统栏）。
  final bool fullscreen;

  /// 是否显示长按图片弹出的菜单（设为封面 / 复制图片等）。
  final bool showLongPressMenu;

  /// 图片灰度滤镜：去色显示，适合彩色漫画转黑白阅读。
  final bool filterGrayscale;

  /// 是否锁定「防止缩小」：缩放到小于适配宽度时回弹到适配宽度（仍可放大）。
  final bool preventShrink;

  /// 是否在章节切换时显示「章节过渡标题卡」。
  final bool showChapterTransition;

  /// 双击缩放的目标倍率（2.0 / 3.0）。
  final double doubleTapZoomScale;

  /// 滚轮缩放方向是否反转（false = 上滚放大；true = 上滚缩小，类天然反向滚动）。
  final bool scrollWheelInverted;

  /// 鼠标滚轮作用：缩放页面（[MouseWheelAction.zoom]）或翻页
  /// （[MouseWheelAction.page]）。**仅翻页模式生效**；条漫模式忽略此项，滚轮按
  /// 上下文自动分派——未放大时滚轮连续滚动长图（翻页），已放大时滚轮缩放微调，
  /// 双击任意处可进入/退出放大态，放大后单指/鼠标拖动平移。
  final MouseWheelAction mouseWheelAction;

  /// 预加载数量：距章末/章首多少页时开始预加载相邻章节（范围 1–16，默认 4）。
  final int preloadImageCount;

  /// 跨章无缝续读：章末/章首直接续读相邻章（复用预载缓存），不重建章节、无白屏。
  /// 关闭时保持传统的「整章加载 + 过渡标题卡」行为。
  final bool seamlessReading;

  /// 条漫（连续模式）解码限幅开关（资源/内存）：开启时把解码位图宽下采样到
  /// `min(2560, 屏幕物理像素 × 2)`，避免超长条漫原图（数千 px 宽）全尺寸解码
  /// 挤爆内存。仅 webtoon 模式生效；paged 单页仍按原图解码保证放大细节。
  final bool webtoonLimitDecodeSize;

  /// 段式连续模型下，段与段之间是否插入「章分割/过渡」条目（章节标题卡）。
  /// 仅对 webtoon（条漫）连续模式生效。
  final bool showChapterSeparator;

  /// 是否显示章节导航滑块：阅读器左缘的竖向章节拖动条。
  /// 仅多章节作品显示；关闭后阅读器不再显示该滑块。
  final bool showChapterSlider;

  /// 鼠标滚轮滚动速度倍率（webtoon 连续滚动增量 × 本值），范围 0.5–3.0，默认 1.0。
  /// paged 模式滚轮翻页行为不受影响。
  final double readerScrollSpeed;

  /// 音量键翻页开关（Android 拦截音量上/下翻页；其他平台并入键盘）。
  final bool volumeKeyPageTurn;

  /// 音量键在 webtoon（条漫）模式下的竖向滚动步长（占视口高度百分比），范围 10–100，默认 40。
  final int volumeKeyPageTurnDistancePercent;

  /// 长按缩放开关：开启后长按图片进入 1.75x 缩放（再长按/松手退出）；
  /// 关闭时保持长按弹菜单行为。
  final bool enableLongPressToZoom;

  /// 长按缩放锚点：[press]=按触点，[center]=按屏幕中心。
  final LongPressZoomPosition longPressZoomPosition;

  /// 双击 / 长按缩放锚点来源：left / center / right。
  final ZoomStart zoomStart;

  /// 自动翻页开关。与 [autoPageTurningInterval] 分开存储：关闭开关
  /// 不清零间隔，重新开启时恢复上次设置的间隔（旧数据 0 时兜底 5）。
  final bool autoPageTurningEnabled;

  /// 自动翻页间隔（秒），范围 1–20；0=从未设置（开启开关时按 5 兜底）。
  /// 仅 [autoPageTurningEnabled] 开启时生效。paged 模式定时自动翻页。
  final int autoPageTurningInterval;

  /// 自动滚动开关（webtoon 平滑自动滚动，速度随 [readerScrollSpeed]）。
  final bool autoScroll;

  /// paged 翻页过渡动画：none=瞬切 / slide=滑入 / fade=淡入淡出。
  final ReaderPageAnimation pageAnimation;

  /// 页面动态效果（comic_motion 引擎投影：主开关 + 逐效果开关 + 参数覆盖
  /// + 全局质量）。翻页与条漫滚动模式均生效；条漫滚动停止后才渲染。
  final MotionEffectSettings motionEffects;

  /// 双击缩放动画时长（毫秒），默认 500。随系统 [MediaQuery.disableAnimations] 比例。
  final int doubleTapAnimSpeed;

  /// webtoon 相邻页间距（像素），范围 0–50，默认 0。
  final int readerPageSpacing;

  /// 首屏单图：双页模式第一章第一页单独显示，其后恢复双页。
  final bool showSingleImageOnFirstPage;

  /// 时间/电量浮层。
  final bool showClockBattery;
  final ClockBatteryPosition clockBatteryPosition;
  final double clockBatteryMargin;
  final double clockBatteryOpacity;
  final double clockBatteryFontSize;

  /// 系统亮度：-1.0~1.0，0=不干预；正值写系统亮度、负值叠加黑色遮罩。
  final double readerBrightness;

  /// 夜览暖色盖层（亮度双轨扩展）：独立于 [readerBrightness] 的开关，
  /// 开启后在阅读区叠加暖色（0xFF2A1800）半透明盖层减少蓝光，不干预系统亮度。
  final bool nightLightEnabled;

  /// 夜览暖色盖层不透明度（0.1–0.85，夜览 toOpacity 范围），默认 0.4。
  final double nightLightOpacity;

  /// 图片色彩配置预设（ICC 校色近似）：none / srgb / warm / cool / manga / paper。
  /// 在手动滤镜之外叠加一层固定色彩矩阵（见 [ReaderImageFilter.profileMatrix]）。
  final ReaderColorProfile colorProfile;

  /// 漫画图片超分档位（GPU 实时 FragmentShader）：off 关闭 / resample 双三次
  /// 重采样 / sharpen 重采样 + 自适应锐化。仅在放大显示时生效；纹理超限
  /// （超长条漫）或 shader 不可用时自动回退普通渲染（见 [MangaUpscaleShader]）。
  final MangaUpscaleMode upscaleMode;

  /// E-Ink 刷新：墨水屏防残影，按翻页间隔自动做一次全屏闪烁清残影。
  final bool einkRefreshEnabled;

  /// E-Ink 刷新间隔（翻页数），范围 1–50，默认 10。每翻过 N 页触发一次刷新。
  final int einkRefreshInterval;

  /// E-Ink 刷新闪烁时长（毫秒），范围 50–1000，默认 200。
  final int einkRefreshDuration;

  /// E-Ink 刷新闪烁样式（white / black）。
  final ReaderEInkRefreshStyle einkRefreshStyle;

  /// 自动收藏（漫画）：打开作品即加入收藏（不重复操作，已收藏跳过）。
  final bool isAutoFavorite;

  /// 阅读中自动下载后续章节：进度越过当前章 25% 时后台入队。
  final bool autoDownloadChapters;

  /// 跳章过滤：下/上一章时跳过已读 / 被筛选 / 标题重复章节。
  final bool skipReadChapters;
  final bool skipFilteredChapters;
  final bool skipDuplicateChapters;

  /// 漫画翻译（漫画翻译功能）：开启后阅读器对当前页自动 OCR+翻译，
  /// 译文以气泡覆盖层渲染在原图上。开关按作品持久化。
  final bool translationEnabled;

  /// 排版回填：开启后译文以「气泡内回填」模式渲染（描边文字 +
  /// 按 bbox 宽度换行 + 字号自适应），关闭时使用半透明覆盖层模式。
  final bool translationBackfill;

  /// 每屏多图 gallery：竖/横屏一屏纵向堆叠张数，1–5，默认 1。
  final int readerScreenPicNumberForPortrait;
  final int readerScreenPicNumberForLandscape;

  const ReaderPreferences({
    this.readingMode = ReadingMode.singleLTR,
    this.doubleTapZoom = true,
    this.orientation = ScreenOrientation.defaultMode,
    this.background = ReaderBackgroundColor.black,
    this.tapZoneLayout = ReaderTapZoneLayout.lShape,
    this.tapZoneInvert = TapZoneInvert.none,
    this.minScale = 1.0,
    this.maxScale = 4.0,
    this.filterBrightness = 0.0,
    this.filterContrast = 0.0,
    this.filterColorTemp = 0.0,
    this.filterSaturation = 0.0,
    this.filterHue = 0.0,
    this.filterInverted = false,
    this.cropEdge = false,
    this.showPageNumber = true,
    this.progressBarOnRight = true,
    this.keepScreenOn = false,
    this.rotateLandscape = false,
    this.splitDoublePage = false,
    this.autoDoublePageOnWide = false,
    this.sideMargin = 0.0,
    this.flashEnabled = false,
    this.flashTime = 120,
    this.flashInterval = 0,
    this.flashColor = ReaderFlashColor.black,
    this.initialZoom = ReaderInitialZoom.fitWidth,
    this.fullscreen = true,
    this.showLongPressMenu = true,
    this.filterGrayscale = false,
    this.preventShrink = false,
    this.showChapterTransition = false,
    this.doubleTapZoomScale = 2.0,
    this.scrollWheelInverted = false,
    this.mouseWheelAction = MouseWheelAction.zoom,
    this.preloadImageCount = 4,
    this.seamlessReading = true,
    this.webtoonLimitDecodeSize = true,
    this.showChapterSeparator = true,
    this.showChapterSlider = true,
    this.readerScrollSpeed = 1.0,
    this.volumeKeyPageTurn = false,
    this.volumeKeyPageTurnDistancePercent = 40,
    this.enableLongPressToZoom = false,
    this.longPressZoomPosition = LongPressZoomPosition.press,
    this.zoomStart = ZoomStart.center,
    this.autoPageTurningEnabled = false,
    this.autoPageTurningInterval = 0,
    this.autoScroll = false,
    this.pageAnimation = ReaderPageAnimation.slide,
    this.motionEffects = const MotionEffectSettings(),
    this.doubleTapAnimSpeed = 500,
    this.readerPageSpacing = 0,
    this.showSingleImageOnFirstPage = false,
    this.showClockBattery = false,
    this.clockBatteryPosition = ClockBatteryPosition.topLeft,
    this.clockBatteryMargin = 8.0,
    this.clockBatteryOpacity = 0.8,
    this.clockBatteryFontSize = 12.0,
    this.readerBrightness = 0.0,
    this.nightLightEnabled = false,
    this.nightLightOpacity = 0.4,
    this.colorProfile = ReaderColorProfile.none,
    this.upscaleMode = MangaUpscaleMode.off,
    this.einkRefreshEnabled = false,
    this.einkRefreshInterval = 10,
    this.einkRefreshDuration = 200,
    this.einkRefreshStyle = ReaderEInkRefreshStyle.white,
    this.isAutoFavorite = false,
    this.autoDownloadChapters = false,
    this.translationEnabled = false,
    this.translationBackfill = false,
    this.skipReadChapters = false,
    this.skipFilteredChapters = false,
    this.skipDuplicateChapters = false,
    this.readerScreenPicNumberForPortrait = 1,
    this.readerScreenPicNumberForLandscape = 1,
  });

  factory ReaderPreferences.fromJson(Map<String, dynamic> json) {
    ReadingMode mode = ReadingMode.singleLTR;
    if (json['readingMode'] is String) {
      mode = ReadingMode.values.firstWhere(
        (e) => e.name == json['readingMode'],
        orElse: () => ReadingMode.singleLTR,
      );
    }
    ScreenOrientation orient = ScreenOrientation.defaultMode;
    if (json['orientation'] is String) {
      orient = ScreenOrientation.values.firstWhere(
        (e) => e.name == json['orientation'],
        orElse: () => ScreenOrientation.defaultMode,
      );
    }
    ReaderBackgroundColor bg = ReaderBackgroundColor.black;
    if (json['background'] is String) {
      bg = ReaderBackgroundColor.values.firstWhere(
        (e) => e.name == json['background'],
        orElse: () => ReaderBackgroundColor.black,
      );
    }
    ReaderTapZoneLayout tap = ReaderTapZoneLayout.lShape;
    if (json['tapZoneLayout'] is String) {
      tap = ReaderTapZoneLayout.values.firstWhere(
        (e) => e.name == json['tapZoneLayout'],
        orElse: () => ReaderTapZoneLayout.lShape,
      );
    }
    TapZoneInvert invert = TapZoneInvert.none;
    if (json['tapZoneInvert'] is String) {
      invert = TapZoneInvert.values.firstWhere(
        (e) => e.name == json['tapZoneInvert'],
        orElse: () => TapZoneInvert.none,
      );
    }
    return ReaderPreferences(
      readingMode: mode,
      doubleTapZoom: json['doubleTapZoom'] as bool? ?? true,
      orientation: orient,
      background: bg,
      tapZoneLayout: tap,
      tapZoneInvert: invert,
      minScale: (json['minScale'] as num?)?.toDouble() ?? 1.0,
      maxScale: (json['maxScale'] as num?)?.toDouble() ?? 4.0,
      filterBrightness:
          (json['filterBrightness'] as num?)?.toDouble() ?? 0.0,
      filterContrast: (json['filterContrast'] as num?)?.toDouble() ?? 0.0,
      filterColorTemp: (json['filterColorTemp'] as num?)?.toDouble() ?? 0.0,
      filterSaturation:
          (json['filterSaturation'] as num?)?.toDouble() ?? 0.0,
      filterHue: (json['filterHue'] as num?)?.toDouble() ?? 0.0,
      filterInverted: json['filterInverted'] as bool? ?? false,
      cropEdge: json['cropEdge'] as bool? ?? false,
      showPageNumber: json['showPageNumber'] as bool? ?? true,
      progressBarOnRight: json['progressBarOnRight'] as bool? ?? true,
      keepScreenOn: json['keepScreenOn'] as bool? ?? false,
      rotateLandscape: json['rotateLandscape'] as bool? ?? false,
      splitDoublePage: json['splitDoublePage'] as bool? ?? false,
      autoDoublePageOnWide: json['autoDoublePageOnWide'] as bool? ?? false,
      sideMargin: (json['sideMargin'] as num?)?.toDouble() ?? 0.0,
      flashEnabled: json['flashEnabled'] as bool? ?? false,
      flashTime: (json['flashTime'] as num?)?.toInt() ?? 120,
      flashInterval: (json['flashInterval'] as num?)?.toInt() ?? 0,
      flashColor: _parseFlashColor(json['flashColor']),
      initialZoom: _parseInitialZoom(json['initialZoom']),
      fullscreen: json['fullscreen'] as bool? ?? true,
      showLongPressMenu: json['showLongPressMenu'] as bool? ?? true,
      filterGrayscale: json['filterGrayscale'] as bool? ?? false,
      preventShrink: json['preventShrink'] as bool? ?? false,
      showChapterTransition: json['showChapterTransition'] as bool? ?? false,
      doubleTapZoomScale:
          (json['doubleTapZoomScale'] as num?)?.toDouble() ?? 2.0,
      scrollWheelInverted: json['scrollWheelInverted'] as bool? ?? false,
      mouseWheelAction: _parseMouseWheelAction(json['mouseWheelAction']),
      preloadImageCount:
          ((json['preloadImageCount'] as num?)?.toInt() ?? 4).clamp(1, 16),
      seamlessReading: json['seamlessReading'] as bool? ?? true,
      webtoonLimitDecodeSize:
          json['webtoonLimitDecodeSize'] as bool? ?? true,
      showChapterSeparator: json['showChapterSeparator'] as bool? ?? true,
      showChapterSlider: json['showChapterSlider'] as bool? ?? true,
      readerScrollSpeed:
          ((json['readerScrollSpeed'] as num?)?.toDouble() ?? 1.0)
              .clamp(0.5, 3.0),
      volumeKeyPageTurn: json['volumeKeyPageTurn'] as bool? ?? false,
      volumeKeyPageTurnDistancePercent:
          ((json['volumeKeyPageTurnDistancePercent'] as num?)?.toInt() ?? 40)
              .clamp(10, 100),
      enableLongPressToZoom:
          json['enableLongPressToZoom'] as bool? ?? false,
      longPressZoomPosition:
          _parseLongPressZoomPosition(json['longPressZoomPosition']),
      zoomStart: _parseZoomStart(json['zoomStart']),
      autoPageTurningInterval:
          ((json['autoPageTurningInterval'] as num?)?.toInt() ?? 0)
              .clamp(0, 20),
      // 迁移：旧数据没有独立开关字段，interval > 0 即视为开启。
      autoPageTurningEnabled: json['autoPageTurningEnabled'] as bool? ??
          (((json['autoPageTurningInterval'] as num?)?.toInt() ?? 0) > 0),
      autoScroll: json['autoScroll'] as bool? ?? false,
      pageAnimation: _parsePageAnimation(json['pageAnimation']),
      motionEffects:
          MotionEffectSettings.fromJson(json['motionEffects']),
      doubleTapAnimSpeed:
          ((json['doubleTapAnimSpeed'] as num?)?.toInt() ?? 500)
              .clamp(100, 1500),
      readerPageSpacing:
          ((json['readerPageSpacing'] as num?)?.toInt() ?? 0).clamp(0, 50),
      showSingleImageOnFirstPage:
          json['showSingleImageOnFirstPage'] as bool? ?? false,
      showClockBattery: json['showClockBattery'] as bool? ?? false,
      clockBatteryPosition:
          _parseClockBatteryPosition(json['clockBatteryPosition']),
      clockBatteryMargin:
          (json['clockBatteryMargin'] as num?)?.toDouble() ?? 8.0,
      clockBatteryOpacity:
          ((json['clockBatteryOpacity'] as num?)?.toDouble() ?? 0.8)
              .clamp(0.1, 1.0),
      clockBatteryFontSize:
          (json['clockBatteryFontSize'] as num?)?.toDouble() ?? 12.0,
      readerBrightness:
          ((json['readerBrightness'] as num?)?.toDouble() ?? 0.0)
              .clamp(-1.0, 1.0),
      nightLightEnabled: json['nightLightEnabled'] as bool? ?? false,
      nightLightOpacity:
          ((json['nightLightOpacity'] as num?)?.toDouble() ?? 0.4)
              .clamp(0.1, 0.85),
      colorProfile: _parseColorProfile(json['colorProfile']),
      upscaleMode: parseMangaUpscaleMode(json['upscaleMode']),
      einkRefreshEnabled: json['einkRefreshEnabled'] as bool? ?? false,
      einkRefreshInterval:
          ((json['einkRefreshInterval'] as num?)?.toInt() ?? 10).clamp(1, 50),
      einkRefreshDuration:
          ((json['einkRefreshDuration'] as num?)?.toInt() ?? 200)
              .clamp(50, 1000),
      einkRefreshStyle: _parseEInkRefreshStyle(json['einkRefreshStyle']),
      isAutoFavorite: json['isAutoFavorite'] as bool? ?? false,
      autoDownloadChapters:
          json['autoDownloadChapters'] as bool? ?? false,
      translationEnabled: json['translationEnabled'] as bool? ?? false,
      translationBackfill: json['translationBackfill'] as bool? ?? false,
      skipReadChapters: json['skipReadChapters'] as bool? ?? false,
      skipFilteredChapters: json['skipFilteredChapters'] as bool? ?? false,
      skipDuplicateChapters: json['skipDuplicateChapters'] as bool? ?? false,
      readerScreenPicNumberForPortrait:
          ((json['readerScreenPicNumberForPortrait'] as num?)?.toInt() ?? 1)
              .clamp(1, 5),
      readerScreenPicNumberForLandscape:
          ((json['readerScreenPicNumberForLandscape'] as num?)?.toInt() ?? 1)
              .clamp(1, 5),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'readingMode': readingMode.name,
        'doubleTapZoom': doubleTapZoom,
        'orientation': orientation.name,
        'background': background.name,
        'tapZoneLayout': tapZoneLayout.name,
        'tapZoneInvert': tapZoneInvert.name,
        'minScale': minScale,
        'maxScale': maxScale,
        'filterBrightness': filterBrightness,
        'filterContrast': filterContrast,
        'filterColorTemp': filterColorTemp,
        'filterSaturation': filterSaturation,
        'filterHue': filterHue,
        'filterInverted': filterInverted,
        'cropEdge': cropEdge,
        'showPageNumber': showPageNumber,
        'progressBarOnRight': progressBarOnRight,
        'keepScreenOn': keepScreenOn,
        'rotateLandscape': rotateLandscape,
        'splitDoublePage': splitDoublePage,
        'autoDoublePageOnWide': autoDoublePageOnWide,
        'sideMargin': sideMargin,
        'flashEnabled': flashEnabled,
        'flashTime': flashTime,
        'flashInterval': flashInterval,
        'flashColor': flashColor.name,
        'initialZoom': initialZoom.name,
        'fullscreen': fullscreen,
        'showLongPressMenu': showLongPressMenu,
        'filterGrayscale': filterGrayscale,
        'preventShrink': preventShrink,
        'showChapterTransition': showChapterTransition,
        'doubleTapZoomScale': doubleTapZoomScale,
        'scrollWheelInverted': scrollWheelInverted,
        'mouseWheelAction': mouseWheelAction.name,
        'preloadImageCount': preloadImageCount,
        'seamlessReading': seamlessReading,
        'webtoonLimitDecodeSize': webtoonLimitDecodeSize,
        'showChapterSeparator': showChapterSeparator,
        'showChapterSlider': showChapterSlider,
        'readerScrollSpeed': readerScrollSpeed,
        'volumeKeyPageTurn': volumeKeyPageTurn,
        'volumeKeyPageTurnDistancePercent': volumeKeyPageTurnDistancePercent,
        'enableLongPressToZoom': enableLongPressToZoom,
        'longPressZoomPosition': longPressZoomPosition.name,
        'zoomStart': zoomStart.name,
        'autoPageTurningEnabled': autoPageTurningEnabled,
        'autoPageTurningInterval': autoPageTurningInterval,
        'autoScroll': autoScroll,
        'pageAnimation': pageAnimation.name,
        'motionEffects': motionEffects.toJson(),
        'doubleTapAnimSpeed': doubleTapAnimSpeed,
        'readerPageSpacing': readerPageSpacing,
        'showSingleImageOnFirstPage': showSingleImageOnFirstPage,
        'showClockBattery': showClockBattery,
        'clockBatteryPosition': clockBatteryPosition.name,
        'clockBatteryMargin': clockBatteryMargin,
        'clockBatteryOpacity': clockBatteryOpacity,
        'clockBatteryFontSize': clockBatteryFontSize,
        'readerBrightness': readerBrightness,
        'nightLightEnabled': nightLightEnabled,
        'nightLightOpacity': nightLightOpacity,
        'colorProfile': colorProfile.name,
        'upscaleMode': upscaleMode.name,
        'einkRefreshEnabled': einkRefreshEnabled,
        'einkRefreshInterval': einkRefreshInterval,
        'einkRefreshDuration': einkRefreshDuration,
        'einkRefreshStyle': einkRefreshStyle.name,
        'isAutoFavorite': isAutoFavorite,
        'autoDownloadChapters': autoDownloadChapters,
        'translationEnabled': translationEnabled,
        'translationBackfill': translationBackfill,
        'skipReadChapters': skipReadChapters,
        'skipFilteredChapters': skipFilteredChapters,
        'skipDuplicateChapters': skipDuplicateChapters,
        'readerScreenPicNumberForPortrait': readerScreenPicNumberForPortrait,
        'readerScreenPicNumberForLandscape': readerScreenPicNumberForLandscape,
      };

  ReaderPreferences copyWith({
    ReadingMode? readingMode,
    bool? doubleTapZoom,
    ScreenOrientation? orientation,
    ReaderBackgroundColor? background,
    ReaderTapZoneLayout? tapZoneLayout,
    TapZoneInvert? tapZoneInvert,
    double? minScale,
    double? maxScale,
    double? filterBrightness,
    double? filterContrast,
    double? filterColorTemp,
    double? filterSaturation,
    double? filterHue,
    bool? filterInverted,
    bool? cropEdge,
    bool? showPageNumber,
    bool? progressBarOnRight,
    bool? keepScreenOn,
    bool? rotateLandscape,
    bool? splitDoublePage,
    bool? autoDoublePageOnWide,
    double? sideMargin,
    bool? flashEnabled,
    int? flashTime,
    int? flashInterval,
    ReaderFlashColor? flashColor,
    ReaderInitialZoom? initialZoom,
    bool? fullscreen,
    bool? showLongPressMenu,
    bool? filterGrayscale,
    bool? preventShrink,
    bool? showChapterTransition,
    double? doubleTapZoomScale,
    bool? scrollWheelInverted,
    MouseWheelAction? mouseWheelAction,
    int? preloadImageCount,
    bool? seamlessReading,
    bool? webtoonLimitDecodeSize,
    bool? showChapterSeparator,
    bool? showChapterSlider,
    double? readerScrollSpeed,
    bool? volumeKeyPageTurn,
    int? volumeKeyPageTurnDistancePercent,
    bool? enableLongPressToZoom,
    LongPressZoomPosition? longPressZoomPosition,
    ZoomStart? zoomStart,
    bool? autoPageTurningEnabled,
    int? autoPageTurningInterval,
    bool? autoScroll,
    ReaderPageAnimation? pageAnimation,
    MotionEffectSettings? motionEffects,
    int? doubleTapAnimSpeed,
    int? readerPageSpacing,
    bool? showSingleImageOnFirstPage,
    bool? showClockBattery,
    ClockBatteryPosition? clockBatteryPosition,
    double? clockBatteryMargin,
    double? clockBatteryOpacity,
    double? clockBatteryFontSize,
    double? readerBrightness,
    bool? nightLightEnabled,
    double? nightLightOpacity,
    ReaderColorProfile? colorProfile,
    MangaUpscaleMode? upscaleMode,
    bool? einkRefreshEnabled,
    int? einkRefreshInterval,
    int? einkRefreshDuration,
    ReaderEInkRefreshStyle? einkRefreshStyle,
    bool? isAutoFavorite,
    bool? autoDownloadChapters,
    bool? translationEnabled,
    bool? translationBackfill,
    bool? skipReadChapters,
    bool? skipFilteredChapters,
    bool? skipDuplicateChapters,
    int? readerScreenPicNumberForPortrait,
    int? readerScreenPicNumberForLandscape,
  }) =>
      ReaderPreferences(
        readingMode: readingMode ?? this.readingMode,
        doubleTapZoom: doubleTapZoom ?? this.doubleTapZoom,
        orientation: orientation ?? this.orientation,
        background: background ?? this.background,
        tapZoneLayout: tapZoneLayout ?? this.tapZoneLayout,
        tapZoneInvert: tapZoneInvert ?? this.tapZoneInvert,
        minScale: minScale ?? this.minScale,
        maxScale: maxScale ?? this.maxScale,
        filterBrightness: filterBrightness ?? this.filterBrightness,
        filterContrast: filterContrast ?? this.filterContrast,
        filterColorTemp: filterColorTemp ?? this.filterColorTemp,
        filterSaturation: filterSaturation ?? this.filterSaturation,
        filterHue: filterHue ?? this.filterHue,
        filterInverted: filterInverted ?? this.filterInverted,
        cropEdge: cropEdge ?? this.cropEdge,
        showPageNumber: showPageNumber ?? this.showPageNumber,
        progressBarOnRight: progressBarOnRight ?? this.progressBarOnRight,
        keepScreenOn: keepScreenOn ?? this.keepScreenOn,
        rotateLandscape: rotateLandscape ?? this.rotateLandscape,
        splitDoublePage: splitDoublePage ?? this.splitDoublePage,
        autoDoublePageOnWide: autoDoublePageOnWide ?? this.autoDoublePageOnWide,
        sideMargin: sideMargin ?? this.sideMargin,
        flashEnabled: flashEnabled ?? this.flashEnabled,
        flashTime: flashTime ?? this.flashTime,
        flashInterval: flashInterval ?? this.flashInterval,
        flashColor: flashColor ?? this.flashColor,
        initialZoom: initialZoom ?? this.initialZoom,
        fullscreen: fullscreen ?? this.fullscreen,
        showLongPressMenu: showLongPressMenu ?? this.showLongPressMenu,
        filterGrayscale: filterGrayscale ?? this.filterGrayscale,
        preventShrink: preventShrink ?? this.preventShrink,
        showChapterTransition:
            showChapterTransition ?? this.showChapterTransition,
        doubleTapZoomScale: doubleTapZoomScale ?? this.doubleTapZoomScale,
        scrollWheelInverted: scrollWheelInverted ?? this.scrollWheelInverted,
        mouseWheelAction: mouseWheelAction ?? this.mouseWheelAction,
        preloadImageCount: preloadImageCount ?? this.preloadImageCount,
        seamlessReading: seamlessReading ?? this.seamlessReading,
        webtoonLimitDecodeSize:
            webtoonLimitDecodeSize ?? this.webtoonLimitDecodeSize,
        showChapterSeparator:
            showChapterSeparator ?? this.showChapterSeparator,
        showChapterSlider:
            showChapterSlider ?? this.showChapterSlider,
        readerScrollSpeed: readerScrollSpeed ?? this.readerScrollSpeed,
        volumeKeyPageTurn: volumeKeyPageTurn ?? this.volumeKeyPageTurn,
        volumeKeyPageTurnDistancePercent:
            volumeKeyPageTurnDistancePercent ??
                this.volumeKeyPageTurnDistancePercent,
        enableLongPressToZoom:
            enableLongPressToZoom ?? this.enableLongPressToZoom,
        longPressZoomPosition:
            longPressZoomPosition ?? this.longPressZoomPosition,
        zoomStart: zoomStart ?? this.zoomStart,
        autoPageTurningEnabled:
            autoPageTurningEnabled ?? this.autoPageTurningEnabled,
        autoPageTurningInterval:
            autoPageTurningInterval ?? this.autoPageTurningInterval,
        autoScroll: autoScroll ?? this.autoScroll,
        pageAnimation: pageAnimation ?? this.pageAnimation,
        motionEffects: motionEffects ?? this.motionEffects,
        doubleTapAnimSpeed: doubleTapAnimSpeed ?? this.doubleTapAnimSpeed,
        readerPageSpacing: readerPageSpacing ?? this.readerPageSpacing,
        showSingleImageOnFirstPage:
            showSingleImageOnFirstPage ?? this.showSingleImageOnFirstPage,
        showClockBattery: showClockBattery ?? this.showClockBattery,
        clockBatteryPosition:
            clockBatteryPosition ?? this.clockBatteryPosition,
        clockBatteryMargin: clockBatteryMargin ?? this.clockBatteryMargin,
        clockBatteryOpacity: clockBatteryOpacity ?? this.clockBatteryOpacity,
        clockBatteryFontSize:
            clockBatteryFontSize ?? this.clockBatteryFontSize,
        readerBrightness: readerBrightness ?? this.readerBrightness,
        nightLightEnabled: nightLightEnabled ?? this.nightLightEnabled,
        nightLightOpacity: nightLightOpacity ?? this.nightLightOpacity,
        colorProfile: colorProfile ?? this.colorProfile,
        upscaleMode: upscaleMode ?? this.upscaleMode,
        einkRefreshEnabled: einkRefreshEnabled ?? this.einkRefreshEnabled,
        einkRefreshInterval: einkRefreshInterval ?? this.einkRefreshInterval,
        einkRefreshDuration: einkRefreshDuration ?? this.einkRefreshDuration,
        einkRefreshStyle: einkRefreshStyle ?? this.einkRefreshStyle,
        isAutoFavorite: isAutoFavorite ?? this.isAutoFavorite,
        autoDownloadChapters:
            autoDownloadChapters ?? this.autoDownloadChapters,
        translationEnabled: translationEnabled ?? this.translationEnabled,
        translationBackfill: translationBackfill ?? this.translationBackfill,
        skipReadChapters: skipReadChapters ?? this.skipReadChapters,
        skipFilteredChapters:
            skipFilteredChapters ?? this.skipFilteredChapters,
        skipDuplicateChapters:
            skipDuplicateChapters ?? this.skipDuplicateChapters,
        readerScreenPicNumberForPortrait: readerScreenPicNumberForPortrait ??
            this.readerScreenPicNumberForPortrait,
        readerScreenPicNumberForLandscape: readerScreenPicNumberForLandscape ??
            this.readerScreenPicNumberForLandscape,
      );

  /// 以 [base] 为底，仅用 [keys] 列出的字段覆盖（显式「本书单独设置」）。
  ///
  /// 由调用方显式给出用户真正改过的字段名
  /// （[ReaderPreferencesStore.getOverrideKeys]），
  /// 未列出的字段一律跟随全局默认。
  ReaderPreferences mergedWithKeys(
    ReaderPreferences base,
    Iterable<String> keys,
  ) {
    final keySet = keys.toSet();
    if (keySet.isEmpty) return base;
    final selfJson = toJson();
    final mergedJson = <String, dynamic>{...base.toJson()};
    for (final key in keySet) {
      if (selfJson.containsKey(key)) mergedJson[key] = selfJson[key];
    }
    return ReaderPreferences.fromJson(mergedJson);
  }

  /// 背景实际颜色（结合深浅色：auto 在浅色主题用白、深色用黑）。
  /// 暗色模式下对所选预设向黑色压暗 [ReaderTokens.nightDarkenFactor]，
  /// 避免白/护眼浅底色在黑夜里刺眼，同时保留各预设间的视觉差异。
  Color resolveBackgroundColor(bool isDark) {
    final Color base;
    if (background == ReaderBackgroundColor.auto) {
      base = isDark ? ReaderTokens.bgPresets[0] : ReaderTokens.bgPresets[2];
    } else {
      base = ReaderTokens.bgPresets[background.toPresetIndex()];
    }
    if (isDark) {
      return Color.lerp(
            base,
            Colors.black,
            ReaderTokens.nightDarkenFactor,
          ) ??
          base;
    }
    return base;
  }
}

/// 三层设置覆盖取值：global（全局默认）→ work（作品）→ device（设备/会话）。
///
/// - [base]：已合并的「全局默认 + 作品」偏好（即 [ReaderPreferences.mergedWithKeys] 结果）；
/// - [device]：当前运行时覆盖层（如按屏幕尺寸/方向的临时偏好，退出阅读器不持久化），
/// 可为 null（表示无设备层覆盖，此时回落 [base]）；
/// - [selector]：按字段取值（`(p) => p.readerBrightness` 等）。
///
/// 优先级：device 非空且该字段在 device 层被设置时取 device；否则取 [base]。
/// 返回类型泛型化，阅读器按字段取用，兼容任意字段类型。
T getReaderSetting<T>(
  ReaderPreferences base,
  ReaderPreferences? device,
  T Function(ReaderPreferences preferences) selector,
) {
  if (device == null) return selector(base);
  return selector(device);
}

/// 漫画睡眠定时模式（跨类型对齐）。
///
/// 会话级状态（不持久化到偏好）：按分钟到时暂停 / 按话数读完 N 话后暂停，
/// 与播放器、小说 TTS 睡眠定时语义对齐。
enum ComicSleepTimerMode { off, minutes, chapters }

/// 漫画睡眠定时状态：设置面板与阅读器之间的双向通信载体。
class ComicSleepTimerState {
  final ComicSleepTimerMode mode;

  /// 有效值：minutes 模式为分钟数，chapters 模式为话数；off 时为 0。
  final int value;

  const ComicSleepTimerState._(this.mode, this.value);

  const ComicSleepTimerState.off()
      : this._(ComicSleepTimerMode.off, 0);

  const ComicSleepTimerState.minutes(int minutes)
      : this._(ComicSleepTimerMode.minutes, minutes);

  const ComicSleepTimerState.chapters(int chapters)
      : this._(ComicSleepTimerMode.chapters, chapters);

  bool get isActive => mode != ComicSleepTimerMode.off;

  @override
  bool operator ==(Object other) =>
      other is ComicSleepTimerState &&
      other.mode == mode &&
      other.value == value;

  @override
  int get hashCode => Object.hash(mode, value);
}

/// 已升级为「仅总设置」的作品层字段（[ReaderPreferences.toJson] 键）。
///
/// 这些设置原本在阅读器弹窗可改，现移除弹窗入口、只在全局设置页配置；
/// 作品层存储加载 / 保存时剥离它们，避免历史弹窗写入的值继续遮蔽总设置。
const Set<String> kComicWorkRemovedSettingKeys = <String>{
  // 自动化组（自动收藏 / 下载 / 跳章过滤）。
  'isAutoFavorite',
  'autoDownloadChapters',
  'skipReadChapters',
  'skipFilteredChapters',
  'skipDuplicateChapters',
  // E-Ink 刷新。
  'einkRefreshEnabled',
  'einkRefreshInterval',
  'einkRefreshDuration',
  'einkRefreshStyle',
  // 鼠标滚轮（桌面）。
  'mouseWheelAction',
  'scrollWheelInverted',
  // 翻页闪光。
  'flashEnabled',
  'flashTime',
  'flashInterval',
  'flashColor',
};

/// 计算 [next] 相对 [prev] 发生变化的字段名集合（[ReaderPreferences.toJson] 键）。
///
/// 列表字段按内容比较，其余用 `==`。设置面板每次改动调用一次，
/// 把差集累积进「本书单独设置」覆盖记录，取代整包落盘后的默认值猜测。
Set<String> comicPrefsChangedKeys(
  ReaderPreferences prev,
  ReaderPreferences next,
) {
  final a = prev.toJson();
  final b = next.toJson();
  final changed = <String>{};
  for (final entry in b.entries) {
    final av = a[entry.key];
    final bv = entry.value;
    if (av is List && bv is List) {
      if (!listEquals(av, bv)) changed.add(entry.key);
    } else if (av is Map && bv is Map) {
      // 嵌套对象（如 motionEffects）无结构相等：序列化后比较。
      if (jsonEncode(av) != jsonEncode(bv)) changed.add(entry.key);
    } else if (av != bv) {
      changed.add(entry.key);
    }
  }
  return changed;
}

Map<String, dynamic> _stripWorkRemovedKeys(Map<String, dynamic> json) =>
    <String, dynamic>{
      for (final entry in json.entries)
        if (!kComicWorkRemovedSettingKeys.contains(entry.key)) entry.key: entry.value,
    };

/// 持久化后端抽象（可注入内存实现用于测试，避免测试依赖原生插件）。
abstract class PrefsBackend {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
}

/// 内存后端（测试用）。
class InMemoryBackend implements PrefsBackend {
  final Map<String, String> _store = {};

  @override
  Future<String?> get(String key) async => _store[key];

  @override
  Future<void> set(String key, String value) async => _store[key] = value;
}

/// 基于 shared_preferences 的后端。
class SharedPrefsBackend implements PrefsBackend {
  const SharedPrefsBackend();

  @override
  Future<String?> get(String key) async =>
      (await _prefs()).getString(key);

  @override
  Future<void> set(String key, String value) async =>
      (await _prefs()).setString(key, value);

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();
}

/// 阅读器偏好存储（按 key 隔离，默认持久化到 shared_preferences）。
class ReaderPreferencesStore {
  ReaderPreferencesStore({PrefsBackend? backend})
      : _backend = backend ?? const SharedPrefsBackend();

  final PrefsBackend _backend;
  final Map<String, ReaderPreferences> _cache = {};

  static const String _prefix = 'reader_prefs_';

  /// 显式「本书单独设置」覆盖记录的 sidecar 键后缀。
  ///
  /// 与偏好本体分开存：本体仍是完整 JSON（兼容旧版/云同步），但合并时只认
  /// 这里列出的字段；未列出的字段实时跟随总设置。
  static const String _overrideSuffix = '#ovr';

  /// 读取某作品偏好（缺省返回默认）。已升级为「仅总设置」的字段在此剥离。
  Future<ReaderPreferences> get(String id) async {
    final cached = _cache[id];
    if (cached != null) return cached;
    final raw = await _backend.get('$_prefix$id');
    if (raw == null) return const ReaderPreferences();
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return const ReaderPreferences();
      final prefs = ReaderPreferences.fromJson(_stripWorkRemovedKeys(json));
      _cache[id] = prefs;
      return prefs;
    } on Object {
      return const ReaderPreferences();
    }
  }

  /// 读取本书显式单独设置过的字段名集合。
  ///
  /// 无 sidecar 记录的历史数据按旧规则迁移推断：与类默认值不同的字段视为
  /// 单独设置（维持既有表现）；已升级为「仅总设置」的字段一律排除。
  Future<Set<String>> getOverrideKeys(String id) async {
    final raw = await _backend.get('$_prefix$id$_overrideSuffix');
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return <String>{for (final e in decoded) e.toString()}
            ..removeAll(kComicWorkRemovedSettingKeys);
        }
      } on Object {
        // 解析失败则回退到旧规则推断。
      }
    }
    final stored = await get(id);
    return comicPrefsChangedKeys(const ReaderPreferences(), stored)
        .difference(kComicWorkRemovedSettingKeys);
  }

  /// 保存偏好：已升级为「仅总设置」的字段不会写入作品层；
  /// [overrideKeys] 非空时同步写入显式覆盖记录（空集合 = 清除全部单独设置）。
  Future<void> save(
    String id,
    ReaderPreferences prefs, {
    Set<String>? overrideKeys,
  }) async {
    _cache[id] = prefs;
    await _backend.set(
      _prefix + id,
      jsonEncode(_stripWorkRemovedKeys(prefs.toJson())),
    );
    if (overrideKeys != null) {
      await _backend.set('$_prefix$id$_overrideSuffix',
          jsonEncode(overrideKeys.toList()..sort()));
    }
  }
}
