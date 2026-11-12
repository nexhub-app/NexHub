/// 小说阅读器偏好（文档 8.3）。
///
/// 承载字号 / 行距 / 段距 / 边距 / 背景预设索引 / 自定义背景色 /
/// 强调色 / 阴影色 / 翻页动画 / 页眉页脚槽位 / 繁简转换模式 /
/// 自动翻页间隔 / 自定义字体。颜色以索引或十六进制值表示，
/// 由 [resolveBackgroundColor] 统一解析，不在外部硬编码。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../comic/models/reader_preferences.dart'
    show
        PrefsBackend,
        ReaderTapZoneLayout,
        SharedPrefsBackend,
        TapZoneInvert;
import '../theme/reader_tokens.dart';
import 'novel_page_animation.dart';

/// copyWith 哨兵：区分「未传 fontFamily」与「显式传 null」（系统字体）。
class _NovelPrefsFontFamilySentinel {
  const _NovelPrefsFontFamilySentinel();
}

const _NovelPrefsFontFamilySentinel _kNovelPrefsFontFamilySentinel =
    _NovelPrefsFontFamilySentinel();

/// copyWith 哨兵：用于可空的颜色字段（customBgColor / customTextColor /
/// shadowColor / emphasisColor），区分「未传入」与「显式传 null（清除）」。
/// 修复旧版 `x ?? this.x` 无法把颜色清回 null 的问题——例如点击预设背景时
/// 需要真正清除 customBgColor，否则预设不生效。
const Object _kNovelPrefsColorUnset = Object();

/// 阅读偏好存档结构版本。
///
/// 2：`ttsAutoNext`（朗读章末自动续读）默认值由 false 改为 true。旧存档
/// 里存的 false 只是「当时的默认值」，无法与「用户主动关闭」区分，因此
/// 版本 < 2 的存档一律按新默认值读取一次；用户之后的选择会以 v2 写回。
const int kNovelPrefsSchema = 2;

/// copyWith 哨兵：用于可空的字体文件路径字段（customFontPath /
/// titleCustomFontPath），区分「未传入」与「显式传 null（清除文件）」。
const Object _kNovelPrefsPathUnset = Object();

/// 中文排版断行模式。
///
/// - [standard] — Flutter TextPainter 原生折行（现状，宽松）。
/// - [cjkStrict] — 逐字符断行 + 禁首禁尾标点：行首禁排闭合标点
/// （」』）】…、，。！？等），行尾禁排开启标点（（「『等）；
/// 禁则处理采用「悬挂」（行尾标点突出至边距外）优先、放不下整体提前换行。
enum NovelLineBreakMode { standard, cjkStrict;

  static NovelLineBreakMode fromString(String? raw) =>
      raw == 'cjkStrict' ? NovelLineBreakMode.cjkStrict : NovelLineBreakMode.standard;
}

/// 正文两端对齐模式。
///
/// 仅作用于分页模式渲染：[justify] 把不满一行的正文行拉伸到整行宽
/// （末行与标题行除外）；[start] 维持原生左对齐。
enum NovelTextAlignMode { start, justify;

  static NovelTextAlignMode fromString(String? raw) =>
      raw == 'justify' ? NovelTextAlignMode.justify : NovelTextAlignMode.start;
}

/// 下划线样式（扩展）。
enum NovelUnderlineStyle { solid, dashed, wavy, dotted;

  static NovelUnderlineStyle fromString(String? raw) => switch (raw) {
        'dashed' => NovelUnderlineStyle.dashed,
        'wavy' => NovelUnderlineStyle.wavy,
        'dotted' => NovelUnderlineStyle.dotted,
        _ => NovelUnderlineStyle.solid,
      };
}

/// 滚动模式插图展示模式。
///
/// - [banner] — 铺满整行完整显示（按源 style 或全宽），高度自适应。
/// - [card] — 卡片式：按正文宽度比例缩列完整显示，配合 [NovelScrollImageAlign]
/// 做水平对齐，图文混排更接近「图文并排」的观感。
enum NovelScrollImageMode { banner, card;

  static NovelScrollImageMode fromString(String? raw) =>
      raw == 'card' ? NovelScrollImageMode.card : NovelScrollImageMode.banner;
}

/// 滚动模式插图水平对齐（；仅 card 模式生效）。
enum NovelScrollImageAlign { left, center, right;

  static NovelScrollImageAlign fromString(String? raw) => switch (raw) {
        'left' => NovelScrollImageAlign.left,
        'right' => NovelScrollImageAlign.right,
        _ => NovelScrollImageAlign.center,
      };
}

/// 页眉 / 页脚槽位内容类型（文档 8.3，6 种）。
enum NovelHeaderFooterContent {
  none,
  time,
  battery,
  chapterTitle,
  bookName,
  pageNumber,
  progressPercent,
  pageAndProgress,
  timeAndBattery,

  /// 整本页码：跨章累计的全书页位（已读章节数来自本会话分页缓存；
  /// 未全部校准时以「+」标注估算）。
  bookPageNumber;

  static NovelHeaderFooterContent fromString(String? raw) {
    return switch (raw) {
      'time' => time,
      'battery' => battery,
      'chapterTitle' => chapterTitle,
      'bookName' => bookName,
      'pageNumber' => pageNumber,
      'progressPercent' => progressPercent,
      'pageAndProgress' => pageAndProgress,
      'timeAndBattery' => timeAndBattery,
      'bookPageNumber' => bookPageNumber,
      _ => none,
    };
  }

  String l10nKey() => switch (this) {
        NovelHeaderFooterContent.none => 'novelHfNone',
        NovelHeaderFooterContent.time => 'novelHfTime',
        NovelHeaderFooterContent.battery => 'novelHfBattery',
        NovelHeaderFooterContent.chapterTitle => 'novelHfChapterTitle',
        NovelHeaderFooterContent.bookName => 'novelHfBookName',
        NovelHeaderFooterContent.pageNumber => 'novelHfPageNumber',
        NovelHeaderFooterContent.progressPercent => 'novelHfProgressPercent',
        NovelHeaderFooterContent.pageAndProgress => 'novelHfPageAndProgress',
        NovelHeaderFooterContent.timeAndBattery => 'novelHfTimeAndBattery',
        NovelHeaderFooterContent.bookPageNumber => 'novelHfBookPageNumber',
      };
}

/// 章节大标题对齐方式（#7）。hidden = 不显示标题。
enum NovelTitleAlign {
  left,
  center,
  right,
  hidden;

  static NovelTitleAlign fromString(String? raw) {
    return switch (raw) {
      'center' => center,
      'right' => right,
      'hidden' => hidden,
      _ => left,
    };
  }

  String l10nKey() => switch (this) {
        NovelTitleAlign.left => 'novelTitleAlignLeft',
        NovelTitleAlign.center => 'novelTitleAlignCenter',
        NovelTitleAlign.right => 'novelTitleAlignRight',
        NovelTitleAlign.hidden => 'novelTitleAlignHidden',
      };
}

/// 小说阅读器夜间模式跟随策略（项 6）：跟随应用 / 始终夜间 / 始终日间。
enum NovelThemeFollow {
  followApp,
  alwaysDark,
  alwaysLight;

  static NovelThemeFollow fromString(String? raw) {
    return switch (raw) {
      'alwaysDark' => alwaysDark,
      'alwaysLight' => alwaysLight,
      _ => followApp,
    };
  }
}

/// 底部工具栏可选工具项（小说阅读器，最多展示 6 个）。
enum NovelBottomTool {
  toc,
  prevChapter,
  nextChapter,
  nightMode,
  autoPage,
  settings,
  bookmark,
  bookmarkList,
  search,
  tts;

  /// 默认 6 槽顺序（与基准截图一致）。
  static const List<NovelBottomTool> defaults = <NovelBottomTool>[
    NovelBottomTool.toc,
    NovelBottomTool.prevChapter,
    NovelBottomTool.nightMode,
    NovelBottomTool.autoPage,
    NovelBottomTool.settings,
    NovelBottomTool.bookmark,
  ];

  /// 从字符串反序列化（无效值返回 null）。
  static NovelBottomTool? fromString(String? raw) {
    if (raw == null) return null;
    for (final v in NovelBottomTool.values) {
      if (v.name == raw) return v;
    }
    return null;
  }

  String l10nKey() => switch (this) {
        NovelBottomTool.toc => 'toolToc',
        NovelBottomTool.prevChapter => 'toolPrevChapter',
        NovelBottomTool.nextChapter => 'toolNextChapter',
        NovelBottomTool.nightMode => 'toolNightMode',
        NovelBottomTool.autoPage => 'toolAutoPage',
        NovelBottomTool.settings => 'toolSettings',
        NovelBottomTool.bookmark => 'toolBookmark',
        NovelBottomTool.bookmarkList => 'toolBookmarkList',
        NovelBottomTool.search => 'toolSearch',
        NovelBottomTool.tts => 'toolTts',
      };
}

/// 小说阅读器偏好。
class NovelReaderPreferences {
  /// 从自定义字体文件加载后使用的字族名（运行时通过 FontLoader 注册）。
  static const String customLoadedFontFamily = 'nexhubCustomNovelFont';

  /// 标题自定义字体文件加载后使用的字族名（与正文字体文件相互独立）。
  static const String customLoadedTitleFontFamily =
      'nexhubCustomNovelTitleFont';

  /// 已加载过的自定义字族集合，避免重复 load 报错。
  static final Set<String> _loadedFontFamilies = <String>{};

  /// 从字体文件路径加载并注册字族（.ttf / .otf）。[family] 为注册后的字族名，
  /// 渲染时通过 [customFontPath] / [titleCustomFontPath] 间接引用。
  static Future<void> loadCustomFont(String family, String path) async {
    if (_loadedFontFamilies.contains(family)) return;
    final bytes = await File(path).readAsBytes();
    final loader = FontLoader(family);
    loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
    _loadedFontFamilies.add(family);
  }

  /// 字号（sp）。
  final double fontSize;

  /// 行距倍率（1.0 = 紧凑, 2.0 = 宽松）。
  final double lineHeight;

  /// 段距（像素）。
  final double paragraphSpacing;

  /// 左右边距（像素）。
  final double margin;

  /// 背景预设索引（引用 [ReaderTokens.bgPresets]）。
  final int bgPresetIndex;

  /// 自定义背景色（ARGB int 值；null 时使用预设）。
  final int? customBgColor;

  /// 强调色（ARGB int 值；null 时使用 [ReaderTokens.emphasisDefault]）。
  final int? emphasisColor;

  /// 正文自定义文字颜色（ARGB int 值；null 时按背景亮度自动取黑/白）。
  final int? customTextColor;

  /// 文字阴影颜色（ARGB int 值；null 时用正文色的半透明）。
  final int? shadowColor;

  /// 字间距（像素；0 = 默认不额外增距）。
  final double letterSpacing;

  /// 正文加粗（可与斜体/下划线共存）。
  final bool fontBold;

  /// 正文斜体（可与加粗/下划线共存）。
  final bool fontItalic;

  /// 正文下划线（可与加粗/斜体共存）。
  final bool fontUnderline;

  /// 是否在正文顶部显示章节大标题（与正文分开排版）。
  final bool showChapterTitleInBody;

  /// 章节标题字号相对正文的倍率（1.0 = 与正文同大）。
  final double titleFontScale;

  /// 章节标题加粗（默认加粗，与正文样式互不影响）。
  final bool titleBold;

  /// 章节标题颜色（ARGB int；null 时跟随强调色）。
  final int? titleColor;

  /// 是否启用文字阴影。
  final bool shadow;

  /// 翻页动画。
  final NovelPageAnimation pageAnimation;

  /// 页眉左侧槽位。
  final NovelHeaderFooterContent headerLeft;

  /// 页眉右侧槽位。
  final NovelHeaderFooterContent headerRight;

  /// 页脚左侧槽位。
  final NovelHeaderFooterContent footerLeft;

  /// 页脚右侧槽位。
  final NovelHeaderFooterContent footerRight;

  /// 繁简转换模式（'none' / 'traditionalToSimplified' /
  /// 'simplifiedToTraditional'）。
  final String chineseConvert;

  /// 自动翻页间隔（秒；0 = 关闭，常用值 3/5/10/15）。
  final int autoPageInterval;

  /// 自动翻页平滑模式：开启后按像素 / 过渡进度连续推进，
  /// 一整页的推进耗时 = [autoPageInterval] 秒；关闭为定时整页跳转。
  final bool autoPageSmooth;

  /// 音量键翻页（仅 Android）：音量上 = 上一页、音量下 = 下一页；
  /// 滚动模式按视口 80% 滚动。默认关闭。
  final bool volumeKeyPageTurn;

  /// 自定义字体 fontFamily（null = 系统默认，'serif' / 'monospace' 等）。
  final String? fontFamily;

  /// 点击分区方向反转（与漫画共用 [TapZoneInvert] 枚举）。
  final TapZoneInvert tapZoneInvert;

  /// 点击分区布局（FR-4.2，5 布局；与漫画共用 [ReaderTapZoneLayout]）。
  final ReaderTapZoneLayout tapZoneLayout;

  /// 夜间模式跟随策略（项 6）：跟随应用 / 始终夜间 / 始终日间。
  /// 不影响 [bgPresetIndex] / [customBgColor] 的持久值，切回「跟随应用」即恢复。
  final NovelThemeFollow themeFollow;

  /// 底部工具栏槽位（有序，最多 6 个；超出截断）。
  final List<NovelBottomTool> bottomToolbarSlots;

  // ─────────────── 朗读设置 ───────────────
  /// 朗读语速（0.5–2.0，1.0 = 正常）。
  final double ttsSpeechRate;

  /// 朗读定时停止（睡眠定时，分钟；0 = 关闭）。
  final int ttsSleepTimer;

  /// 后台朗读开关：true 时应用进入后台仍继续朗读（需配合 AppLifecycle
  /// 监听，见 `NovelTtsController`）；false 时进入后台即暂停。
  final bool ttsBackground;

  /// 跨章连播开关：一章读完自动加载下一章继续朗读。
  final bool ttsAutoNext;

  /// 记住朗读位置：开启后按书记录「读到第几章第几段」，退出朗读/离开
  /// 阅读器后再点朗读从该处续读；关闭则每次都从当前章开头读。
  final bool ttsRememberPosition;

  /// 系统 TTS 旁白声音名（空 = 引擎默认）。
  final String ttsSystemNarratorVoice;

  /// 系统 TTS 男性角色兜底声音名（空 = 引擎默认）。
  final String ttsSystemMaleVoice;

  /// 系统 TTS 女性角色兜底声音名（空 = 引擎默认）。
  final String ttsSystemFemaleVoice;

  // ─────────────── 字体 / 颜色 / 阴影 / 下划线 ───────────────
  /// 自定义字体文件路径（.ttf / .otf；null = 不指定，用 [fontFamily]）。
  final String? customFontPath;

  /// 文字阴影模糊半径（像素）。
  final double shadowBlur;

  /// 文字阴影 X 偏移（像素）。
  final double shadowOffsetX;

  /// 文字阴影 Y 偏移（像素）。
  final double shadowOffsetY;

  /// 下划线颜色（ARGB int；null = 跟随正文色）。
  final int? underlineColor;

  /// 下划线是否虚线。
  final bool underlineDashed;

  /// 双页模式：翻页模式下横屏/宽屏时左右并排显示两页（每页按半宽分页）。
  /// 滚动模式与竖屏自动失效；仅改变呈现，进度仍以「左页」页码为准。
  final bool twoPageMode;

  /// 下划线线宽（像素）。
  final double underlineThickness;

  /// 下划线虚线实段长（像素；仅 [underlineDashed] 时参考）。
  final double underlineDashLength;

  /// 下划线虚线间隙（像素；仅 [underlineDashed] 时参考）。
  final double underlineDashGap;

  // ─────────────── 标题显示 / 字体 / 分段 ───────────────
  /// 章节标题对齐方式（左 / 中 / 右）。
  final NovelTitleAlign titleAlign;

  /// 标题自定义字体 fontFamily（null = 跟随正文 [fontFamily]）。
  final String? titleFontFamily;

  /// 标题自定义字体文件路径（.ttf / .otf；null = 不指定，用 [titleFontFamily]）。
  final String? titleCustomFontPath;

  /// 标题分段模式：开启后标题分「主行(章名) + 次行(书名)」两行显示。
  final bool titleSegmentMode;

  /// 分段模式下次行字号相对主行的倍率。
  final double titleSubScale;

  /// 分段模式下主行与次行的间距（像素）。
  final double titleSegmentSpacing;

  /// 分段模式下次行的行距倍率。
  final double titleSubLineSpacing;

  /// 标题区上边距（像素）。
  final double titleTopMargin;

  /// 标题区下边距（像素）。
  final double titleBottomMargin;

  // ─────────────── 页眉 / 页脚 ───────────────
  /// 页眉中间槽位。
  final NovelHeaderFooterContent headerCenter;

  /// 页脚中间槽位。
  final NovelHeaderFooterContent footerCenter;

  /// 页眉页脚文字颜色（ARGB int；null = 跟随正文色）。
  final int? headerFooterColor;

  /// 页眉页脚左右边距（像素）。
  final double headerFooterMargin;

  // ─────────────── 滚轮翻页 ───────────────
  /// 鼠标滚轮翻页方向反转：true 时「向上滚 = 下一页」（自然滚动习惯），
  /// false 时「向下滚 = 下一页」（默认，与翻页按钮 / 点击分区一致）。
  /// 仅作用于翻页模式（paged）；滚动模式由底层 Scrollable 接管滚轮。
  final bool scrollWheelInverted;

  // ─────────────── 排版增强 ───────────────
  /// 加粗字重滑块（100–900）：仅 [fontBold] 开启时生效，关闭加粗即恢复
  /// 默认字重。加粗开关与字重只有一个数据源，杜绝「开了开关看不到变化 /
  /// 关了开关关不掉」的双字段覆盖问题。
  final int fontWeightValue;

  /// 正文两端对齐（分页模式）：开启后非末行拉伸到整行宽。
  final NovelTextAlignMode textAlignMode;

  /// 中文逐字断行 + 禁首禁尾标点（cjkStrict）；standard 为原生折行。
  final NovelLineBreakMode lineBreakMode;

  /// 下划线样式：实线 / 虚线 / 波浪 / 点线。dashed 兼容旧 [underlineDashed]。
  final NovelUnderlineStyle underlineStyle;

  // ─────────────── 滚动模式图文增强 ───────────────
  /// 滚动模式插图展示模式：banner 铺满整行 / card 卡片式缩列。
  final NovelScrollImageMode scrollImageMode;

  /// 滚动模式插图水平对齐（card 模式生效）。
  final NovelScrollImageAlign scrollImageAlign;

  // ─────────────── 滚动模式章末接续 ───────────────
  /// 滚动模式章末自动接续下一章（无缝连排）。
  ///
  /// 开启后滚动到章末会把下一章正文直接接在当前章下方，读者可一路向下
  /// 滚动跨章，无需手动翻章；关闭则停在章末（便于看目录/评论）。
  /// 仅作用于滚动模式，翻页模式不受影响。
  final bool scrollAutoNextChapter;

  const NovelReaderPreferences({
    this.fontSize = 18.0,
    this.lineHeight = 1.8,
    this.paragraphSpacing = 16.0,
    this.margin = 24.0,
    this.bgPresetIndex = 2,
    this.customBgColor,
    this.emphasisColor,
    this.customTextColor,
    this.shadowColor,
    this.letterSpacing = 0.0,
    this.fontBold = false,
    this.fontItalic = false,
    this.fontUnderline = false,
    this.showChapterTitleInBody = true,
    this.titleFontScale = 1.5,
    this.titleBold = true,
    this.titleColor,
    this.shadow = false,
    this.pageAnimation = NovelPageAnimation.slide,
    this.headerLeft = NovelHeaderFooterContent.bookName,
    this.headerRight = NovelHeaderFooterContent.time,
    this.footerLeft = NovelHeaderFooterContent.chapterTitle,
    this.footerRight = NovelHeaderFooterContent.pageNumber,
    this.chineseConvert = 'none',
    this.autoPageInterval = 0,
    this.autoPageSmooth = false,
    // 小说阅读器默认开启音量键翻页：实测日志显示默认 false 时进入阅读器会打印
    // "[小说音量键] 已关闭原生拦截"，导致用户按音量键无法翻页。原生
    // MainActivity.dispatchKeyEvent 拦截逻辑本身正确，问题仅在默认偏好关闭。
    // 与漫画阅读器（ReaderPreferences 默认 true）保持一致，提升开箱可用性。
    this.volumeKeyPageTurn = true,
    this.fontFamily,
    this.tapZoneInvert = TapZoneInvert.none,
    this.tapZoneLayout = ReaderTapZoneLayout.lShape,
    this.themeFollow = NovelThemeFollow.followApp,
    this.bottomToolbarSlots = NovelBottomTool.defaults,
    // 朗读
    this.ttsSpeechRate = 1.0,
    this.ttsSleepTimer = 0,
    this.ttsBackground = false,
    this.ttsAutoNext = true,
    this.ttsRememberPosition = true,
    this.ttsSystemNarratorVoice = '',
    this.ttsSystemMaleVoice = '',
    this.ttsSystemFemaleVoice = '',
    // 字体/阴影/下划线
    this.customFontPath,
    this.shadowBlur = 0.5,
    this.shadowOffsetX = 0.5,
    this.shadowOffsetY = 0.5,
    this.underlineColor,
    this.underlineDashed = false,
    this.twoPageMode = false,
    this.underlineThickness = 1.0,
    this.underlineDashLength = 4.0,
    this.underlineDashGap = 2.0,
    // 标题
    this.titleAlign = NovelTitleAlign.left,
    this.titleFontFamily,
    this.titleCustomFontPath,
    this.titleSegmentMode = false,
    this.titleSubScale = 0.8,
    this.titleSegmentSpacing = 8.0,
    this.titleSubLineSpacing = 1.3,
    this.titleTopMargin = 0.0,
    this.titleBottomMargin = 0.0,
    // 页眉页脚
    this.headerCenter = NovelHeaderFooterContent.none,
    this.footerCenter = NovelHeaderFooterContent.none,
    this.headerFooterColor,
    this.headerFooterMargin = 12.0,
    this.scrollWheelInverted = false,
    // 排版增强
    this.fontWeightValue = 700,
    this.textAlignMode = NovelTextAlignMode.start,
    this.lineBreakMode = NovelLineBreakMode.standard,
    this.underlineStyle = NovelUnderlineStyle.solid,
    // 滚动模式图文增强
    this.scrollImageMode = NovelScrollImageMode.banner,
    this.scrollImageAlign = NovelScrollImageAlign.center,
    this.scrollAutoNextChapter = true,
  });

  NovelReaderPreferences copyWith({
    double? fontSize,
    double? lineHeight,
    double? paragraphSpacing,
    double? margin,
    int? bgPresetIndex,
    Object? customBgColor = _kNovelPrefsColorUnset,
    Object? emphasisColor = _kNovelPrefsColorUnset,
    Object? customTextColor = _kNovelPrefsColorUnset,
    Object? shadowColor = _kNovelPrefsColorUnset,
    double? letterSpacing,
    bool? fontBold,
    bool? fontItalic,
    bool? fontUnderline,
    bool? showChapterTitleInBody,
    double? titleFontScale,
    bool? titleBold,
    Object? titleColor = _kNovelPrefsColorUnset,
    bool? shadow,
    NovelPageAnimation? pageAnimation,
    NovelHeaderFooterContent? headerLeft,
    NovelHeaderFooterContent? headerRight,
    NovelHeaderFooterContent? footerLeft,
    NovelHeaderFooterContent? footerRight,
    String? chineseConvert,
    int? autoPageInterval,
    bool? autoPageSmooth,
    bool? volumeKeyPageTurn,
    Object? fontFamily = _kNovelPrefsFontFamilySentinel,
    TapZoneInvert? tapZoneInvert,
    ReaderTapZoneLayout? tapZoneLayout,
    NovelThemeFollow? themeFollow,
    List<NovelBottomTool>? bottomToolbarSlots,
    // 朗读
    double? ttsSpeechRate,
    int? ttsSleepTimer,
    bool? ttsBackground,
    bool? ttsAutoNext,
    bool? ttsRememberPosition,
    String? ttsSystemNarratorVoice,
    String? ttsSystemMaleVoice,
    String? ttsSystemFemaleVoice,
    // 字体/阴影/下划线
    Object? customFontPath = _kNovelPrefsPathUnset,
    double? shadowBlur,
    double? shadowOffsetX,
    double? shadowOffsetY,
    Object? underlineColor = _kNovelPrefsColorUnset,
    bool? underlineDashed,
    bool? twoPageMode,
    double? underlineThickness,
    double? underlineDashLength,
    double? underlineDashGap,
    // 标题
    NovelTitleAlign? titleAlign,
    Object? titleFontFamily = _kNovelPrefsFontFamilySentinel,
    Object? titleCustomFontPath = _kNovelPrefsPathUnset,
    bool? titleSegmentMode,
    double? titleSubScale,
    double? titleSegmentSpacing,
    double? titleSubLineSpacing,
    double? titleTopMargin,
    double? titleBottomMargin,
    // 页眉页脚
    NovelHeaderFooterContent? headerCenter,
    NovelHeaderFooterContent? footerCenter,
    Object? headerFooterColor = _kNovelPrefsColorUnset,
    double? headerFooterMargin,
    bool? scrollWheelInverted,
    // 排版增强
    int? fontWeightValue,
    NovelTextAlignMode? textAlignMode,
    NovelLineBreakMode? lineBreakMode,
    NovelUnderlineStyle? underlineStyle,
    // 滚动模式图文增强
    NovelScrollImageMode? scrollImageMode,
    NovelScrollImageAlign? scrollImageAlign,
    // 滚动模式章末接续
    bool? scrollAutoNextChapter,
  }) {
    return NovelReaderPreferences(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      margin: margin ?? this.margin,
      bgPresetIndex: bgPresetIndex ?? this.bgPresetIndex,
      customBgColor: identical(customBgColor, _kNovelPrefsColorUnset)
          ? this.customBgColor
          : customBgColor as int?,
      emphasisColor: identical(emphasisColor, _kNovelPrefsColorUnset)
          ? this.emphasisColor
          : emphasisColor as int?,
      customTextColor: identical(customTextColor, _kNovelPrefsColorUnset)
          ? this.customTextColor
          : customTextColor as int?,
      shadowColor: identical(shadowColor, _kNovelPrefsColorUnset)
          ? this.shadowColor
          : shadowColor as int?,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      fontBold: fontBold ?? this.fontBold,
      fontItalic: fontItalic ?? this.fontItalic,
      fontUnderline: fontUnderline ?? this.fontUnderline,
      showChapterTitleInBody:
          showChapterTitleInBody ?? this.showChapterTitleInBody,
      titleFontScale: titleFontScale ?? this.titleFontScale,
      titleBold: titleBold ?? this.titleBold,
      titleColor: identical(titleColor, _kNovelPrefsColorUnset)
          ? this.titleColor
          : titleColor as int?,
      shadow: shadow ?? this.shadow,
      pageAnimation: pageAnimation ?? this.pageAnimation,
      headerLeft: headerLeft ?? this.headerLeft,
      headerRight: headerRight ?? this.headerRight,
      footerLeft: footerLeft ?? this.footerLeft,
      footerRight: footerRight ?? this.footerRight,
      chineseConvert: chineseConvert ?? this.chineseConvert,
      autoPageInterval: autoPageInterval ?? this.autoPageInterval,
      autoPageSmooth: autoPageSmooth ?? this.autoPageSmooth,
      volumeKeyPageTurn: volumeKeyPageTurn ?? this.volumeKeyPageTurn,
      // 用哨兵区分「未传入」与「显式传入 null」。
      fontFamily: identical(fontFamily, _kNovelPrefsFontFamilySentinel)
          ? this.fontFamily
          : fontFamily as String?,
      tapZoneInvert: tapZoneInvert ?? this.tapZoneInvert,
      tapZoneLayout: tapZoneLayout ?? this.tapZoneLayout,
      themeFollow: themeFollow ?? this.themeFollow,
      bottomToolbarSlots:
          bottomToolbarSlots ?? this.bottomToolbarSlots,
      // 朗读
      ttsSpeechRate: ttsSpeechRate ?? this.ttsSpeechRate,
      ttsSleepTimer: ttsSleepTimer ?? this.ttsSleepTimer,
      ttsBackground: ttsBackground ?? this.ttsBackground,
      ttsAutoNext: ttsAutoNext ?? this.ttsAutoNext,
      ttsRememberPosition:
          ttsRememberPosition ?? this.ttsRememberPosition,
      ttsSystemNarratorVoice:
          ttsSystemNarratorVoice ?? this.ttsSystemNarratorVoice,
      ttsSystemMaleVoice: ttsSystemMaleVoice ?? this.ttsSystemMaleVoice,
      ttsSystemFemaleVoice: ttsSystemFemaleVoice ?? this.ttsSystemFemaleVoice,
      // 字体/阴影/下划线
      customFontPath: identical(customFontPath, _kNovelPrefsPathUnset)
          ? this.customFontPath
          : customFontPath as String?,
      shadowBlur: shadowBlur ?? this.shadowBlur,
      shadowOffsetX: shadowOffsetX ?? this.shadowOffsetX,
      shadowOffsetY: shadowOffsetY ?? this.shadowOffsetY,
      underlineColor: identical(underlineColor, _kNovelPrefsColorUnset)
          ? this.underlineColor
          : underlineColor as int?,
      underlineDashed: underlineDashed ?? this.underlineDashed,
      twoPageMode: twoPageMode ?? this.twoPageMode,
      underlineThickness: underlineThickness ?? this.underlineThickness,
      underlineDashLength: underlineDashLength ?? this.underlineDashLength,
      underlineDashGap: underlineDashGap ?? this.underlineDashGap,
      // 标题
      titleAlign: titleAlign ?? this.titleAlign,
      titleFontFamily: identical(titleFontFamily, _kNovelPrefsFontFamilySentinel)
          ? this.titleFontFamily
          : titleFontFamily as String?,
      titleCustomFontPath:
          identical(titleCustomFontPath, _kNovelPrefsPathUnset)
              ? this.titleCustomFontPath
              : titleCustomFontPath as String?,
      titleSegmentMode: titleSegmentMode ?? this.titleSegmentMode,
      titleSubScale: titleSubScale ?? this.titleSubScale,
      titleSegmentSpacing: titleSegmentSpacing ?? this.titleSegmentSpacing,
      titleSubLineSpacing: titleSubLineSpacing ?? this.titleSubLineSpacing,
      titleTopMargin: titleTopMargin ?? this.titleTopMargin,
      titleBottomMargin: titleBottomMargin ?? this.titleBottomMargin,
      // 页眉页脚
      headerCenter: headerCenter ?? this.headerCenter,
      footerCenter: footerCenter ?? this.footerCenter,
      headerFooterColor: identical(headerFooterColor, _kNovelPrefsColorUnset)
          ? this.headerFooterColor
          : headerFooterColor as int?,
      headerFooterMargin: headerFooterMargin ?? this.headerFooterMargin,
      scrollWheelInverted: scrollWheelInverted ?? this.scrollWheelInverted,
      // 排版增强
      fontWeightValue: fontWeightValue ?? this.fontWeightValue,
      textAlignMode: textAlignMode ?? this.textAlignMode,
      lineBreakMode: lineBreakMode ?? this.lineBreakMode,
      underlineStyle: underlineStyle ?? this.underlineStyle,
      // 滚动模式图文增强
      scrollImageMode: scrollImageMode ?? this.scrollImageMode,
      scrollImageAlign: scrollImageAlign ?? this.scrollImageAlign,
      // 滚动模式章末接续
      scrollAutoNextChapter:
          scrollAutoNextChapter ?? this.scrollAutoNextChapter,
    );
  }

  /// 以 [base] 为全局默认，仅用本对象中「用户自定义过的字段」覆盖。
  NovelReaderPreferences mergedWith(NovelReaderPreferences base) {
    const def = NovelReaderPreferences();
    return NovelReaderPreferences(
      fontSize: identical(fontSize, def.fontSize) ? base.fontSize : fontSize,
      lineHeight:
          identical(lineHeight, def.lineHeight) ? base.lineHeight : lineHeight,
      paragraphSpacing: identical(paragraphSpacing, def.paragraphSpacing)
          ? base.paragraphSpacing
          : paragraphSpacing,
      margin: identical(margin, def.margin) ? base.margin : margin,
      bgPresetIndex: identical(bgPresetIndex, def.bgPresetIndex)
          ? base.bgPresetIndex
          : bgPresetIndex,
      customBgColor: identical(customBgColor, def.customBgColor)
          ? base.customBgColor
          : customBgColor,
      emphasisColor: identical(emphasisColor, def.emphasisColor)
          ? base.emphasisColor
          : emphasisColor,
      customTextColor: identical(customTextColor, def.customTextColor)
          ? base.customTextColor
          : customTextColor,
      shadowColor: identical(shadowColor, def.shadowColor)
          ? base.shadowColor
          : shadowColor,
      letterSpacing: identical(letterSpacing, def.letterSpacing)
          ? base.letterSpacing
          : letterSpacing,
      fontBold: identical(fontBold, def.fontBold) ? base.fontBold : fontBold,
      fontItalic:
          identical(fontItalic, def.fontItalic) ? base.fontItalic : fontItalic,
      fontUnderline: identical(fontUnderline, def.fontUnderline)
          ? base.fontUnderline
          : fontUnderline,
      showChapterTitleInBody:
          identical(showChapterTitleInBody, def.showChapterTitleInBody)
              ? base.showChapterTitleInBody
              : showChapterTitleInBody,
      titleFontScale: identical(titleFontScale, def.titleFontScale)
          ? base.titleFontScale
          : titleFontScale,
      titleBold:
          identical(titleBold, def.titleBold) ? base.titleBold : titleBold,
      titleColor: identical(titleColor, def.titleColor)
          ? base.titleColor
          : titleColor,
      shadow: identical(shadow, def.shadow) ? base.shadow : shadow,
      pageAnimation: identical(pageAnimation, def.pageAnimation)
          ? base.pageAnimation
          : pageAnimation,
      headerLeft:
          identical(headerLeft, def.headerLeft) ? base.headerLeft : headerLeft,
      headerRight: identical(headerRight, def.headerRight)
          ? base.headerRight
          : headerRight,
      footerLeft:
          identical(footerLeft, def.footerLeft) ? base.footerLeft : footerLeft,
      footerRight: identical(footerRight, def.footerRight)
          ? base.footerRight
          : footerRight,
      chineseConvert: identical(chineseConvert, def.chineseConvert)
          ? base.chineseConvert
          : chineseConvert,
      autoPageInterval: identical(autoPageInterval, def.autoPageInterval)
          ? base.autoPageInterval
          : autoPageInterval,
      autoPageSmooth: identical(autoPageSmooth, def.autoPageSmooth)
          ? base.autoPageSmooth
          : autoPageSmooth,
      fontFamily: fontFamily ?? base.fontFamily,
      tapZoneInvert: identical(tapZoneInvert, def.tapZoneInvert)
          ? base.tapZoneInvert
          : tapZoneInvert,
      tapZoneLayout: identical(tapZoneLayout, def.tapZoneLayout)
          ? base.tapZoneLayout
          : tapZoneLayout,
      themeFollow: identical(themeFollow, def.themeFollow)
          ? base.themeFollow
          : themeFollow,
      bottomToolbarSlots:
          listEquals(bottomToolbarSlots, def.bottomToolbarSlots)
              ? base.bottomToolbarSlots
              : bottomToolbarSlots,
      // 朗读
      ttsSpeechRate: identical(ttsSpeechRate, def.ttsSpeechRate)
          ? base.ttsSpeechRate
          : ttsSpeechRate,
      ttsSleepTimer: identical(ttsSleepTimer, def.ttsSleepTimer)
          ? base.ttsSleepTimer
          : ttsSleepTimer,
      ttsBackground: identical(ttsBackground, def.ttsBackground)
          ? base.ttsBackground
          : ttsBackground,
      ttsAutoNext: identical(ttsAutoNext, def.ttsAutoNext)
          ? base.ttsAutoNext
          : ttsAutoNext,
      ttsRememberPosition:
          identical(ttsRememberPosition, def.ttsRememberPosition)
              ? base.ttsRememberPosition
              : ttsRememberPosition,
      ttsSystemNarratorVoice: ttsSystemNarratorVoice == def.ttsSystemNarratorVoice
          ? base.ttsSystemNarratorVoice
          : ttsSystemNarratorVoice,
      ttsSystemMaleVoice: ttsSystemMaleVoice == def.ttsSystemMaleVoice
          ? base.ttsSystemMaleVoice
          : ttsSystemMaleVoice,
      ttsSystemFemaleVoice: ttsSystemFemaleVoice == def.ttsSystemFemaleVoice
          ? base.ttsSystemFemaleVoice
          : ttsSystemFemaleVoice,
      // 字体/阴影/下划线
      customFontPath: identical(customFontPath, def.customFontPath)
          ? base.customFontPath
          : customFontPath,
      shadowBlur:
          identical(shadowBlur, def.shadowBlur) ? base.shadowBlur : shadowBlur,
      shadowOffsetX: identical(shadowOffsetX, def.shadowOffsetX)
          ? base.shadowOffsetX
          : shadowOffsetX,
      shadowOffsetY: identical(shadowOffsetY, def.shadowOffsetY)
          ? base.shadowOffsetY
          : shadowOffsetY,
      underlineColor: identical(underlineColor, def.underlineColor)
          ? base.underlineColor
          : underlineColor,
      underlineDashed: identical(underlineDashed, def.underlineDashed)
          ? base.underlineDashed
          : underlineDashed,
      twoPageMode: identical(twoPageMode, def.twoPageMode)
          ? base.twoPageMode
          : twoPageMode,
      underlineThickness: identical(underlineThickness, def.underlineThickness)
          ? base.underlineThickness
          : underlineThickness,
      underlineDashLength: identical(underlineDashLength, def.underlineDashLength)
          ? base.underlineDashLength
          : underlineDashLength,
      underlineDashGap: identical(underlineDashGap, def.underlineDashGap)
          ? base.underlineDashGap
          : underlineDashGap,
      // 标题
      titleAlign:
          identical(titleAlign, def.titleAlign) ? base.titleAlign : titleAlign,
      titleFontFamily: identical(titleFontFamily, def.titleFontFamily)
          ? base.titleFontFamily
          : titleFontFamily,
      titleCustomFontPath: identical(titleCustomFontPath, def.titleCustomFontPath)
          ? base.titleCustomFontPath
          : titleCustomFontPath,
      titleSegmentMode: identical(titleSegmentMode, def.titleSegmentMode)
          ? base.titleSegmentMode
          : titleSegmentMode,
      titleSubScale: identical(titleSubScale, def.titleSubScale)
          ? base.titleSubScale
          : titleSubScale,
      titleSegmentSpacing: identical(titleSegmentSpacing, def.titleSegmentSpacing)
          ? base.titleSegmentSpacing
          : titleSegmentSpacing,
      titleSubLineSpacing: identical(titleSubLineSpacing, def.titleSubLineSpacing)
          ? base.titleSubLineSpacing
          : titleSubLineSpacing,
      titleTopMargin: identical(titleTopMargin, def.titleTopMargin)
          ? base.titleTopMargin
          : titleTopMargin,
      titleBottomMargin: identical(titleBottomMargin, def.titleBottomMargin)
          ? base.titleBottomMargin
          : titleBottomMargin,
      // 页眉页脚
      headerCenter: identical(headerCenter, def.headerCenter)
          ? base.headerCenter
          : headerCenter,
      footerCenter: identical(footerCenter, def.footerCenter)
          ? base.footerCenter
          : footerCenter,
      headerFooterColor: identical(headerFooterColor, def.headerFooterColor)
          ? base.headerFooterColor
          : headerFooterColor,
      headerFooterMargin: identical(headerFooterMargin, def.headerFooterMargin)
          ? base.headerFooterMargin
          : headerFooterMargin,
      scrollWheelInverted: identical(scrollWheelInverted, def.scrollWheelInverted)
          ? base.scrollWheelInverted
          : scrollWheelInverted,
      // 排版增强
      fontWeightValue: identical(fontWeightValue, def.fontWeightValue)
          ? base.fontWeightValue
          : fontWeightValue,
      textAlignMode: identical(textAlignMode, def.textAlignMode)
          ? base.textAlignMode
          : textAlignMode,
      lineBreakMode: identical(lineBreakMode, def.lineBreakMode)
          ? base.lineBreakMode
          : lineBreakMode,
      underlineStyle: identical(underlineStyle, def.underlineStyle)
          ? base.underlineStyle
          : underlineStyle,
      // 滚动模式图文增强
      scrollImageMode: identical(scrollImageMode, def.scrollImageMode)
          ? base.scrollImageMode
          : scrollImageMode,
      scrollImageAlign: identical(scrollImageAlign, def.scrollImageAlign)
          ? base.scrollImageAlign
          : scrollImageAlign,
      // 滚动模式章末接续
      scrollAutoNextChapter: identical(
              scrollAutoNextChapter, def.scrollAutoNextChapter)
          ? base.scrollAutoNextChapter
          : scrollAutoNextChapter,
    );
  }

  /// 以 [base] 为底，仅用 [keys] 列出的字段覆盖（显式「本书单独设置」）。
  ///
  /// 与 [mergedWith] 靠「与类默认值比较」推断不同，本方法由调用方显式给出
  /// 用户真正改过的字段名（[NovelReaderPreferencesStore.getOverrideKeys]），
  /// 未列出的字段一律跟随全局默认——保证总设置的修改实时作用于
  /// 没有单独设置该书对应字段的情况。
  NovelReaderPreferences mergedWithKeys(
    NovelReaderPreferences base,
    Iterable<String> keys,
  ) {
    final keySet = keys.toSet();
    if (keySet.isEmpty) return base;
    final selfJson = toJson();
    final mergedJson = <String, dynamic>{...base.toJson()};
    for (final key in keySet) {
      if (selfJson.containsKey(key)) mergedJson[key] = selfJson[key];
    }
    return NovelReaderPreferences.fromJson(mergedJson);
  }

  /// 解析背景色（自定义优先，否则取预设）。
  ///
  /// 夜间快捷开关（[nightMode]）：开启时不再强制单一深灰，而是在**所选**
  /// 预设 / 自定义背景基础上压暗（[ReaderTokens.nightDarkenFactor]），
  /// 既护眼又保留各预设差异（修复「夜间模式下所有预设背景看起来同色」）。
  /// 不影响 [bgPresetIndex] / [customBgColor] 的持久值，切回日间即恢复。
  ///
  /// 自定义背景色 [customBgColor] 优先级次之：用户明确指定颜色时尊重其选择
  /// （同样会在夜间压暗）。否则按 [bgPresetIndex] 取预设。
  Color resolveBackgroundColor(bool isDark) {
    final Color base = customBgColor != null
        ? Color(customBgColor!)
        : ReaderTokens.bgPresets[bgPresetIndex.clamp(0, ReaderTokens.bgPresets.length - 1)];
    // 项 6：夜间跟随策略。followApp 时按应用主题明暗决定；alwaysDark/alwaysLight
    // 强制昼夜；背景预设索引 / 自定义背景的持久值不受影响。
    final bool dark;
    switch (themeFollow) {
      case NovelThemeFollow.followApp:
        dark = isDark;
      case NovelThemeFollow.alwaysDark:
        dark = true;
      case NovelThemeFollow.alwaysLight:
        dark = false;
    }
    if (dark) {
      return Color.lerp(base, Colors.black, ReaderTokens.nightDarkenFactor) ?? base;
    }
    return base;
  }

  /// 解析强调色。
  ///
  /// 墨水屏主题化：选中墨水屏背景预设且未显式自定义强调色时，
  /// 联动使用墨水屏配套强调色（朱批暗红），避免高饱和荧光色破坏纸感。
  Color resolveEmphasisColor() {
    if (emphasisColor != null) return Color(emphasisColor!);
    if (isEInkBackground) return ReaderTokens.eInkEmphasisColor;
    return ReaderTokens.emphasisDefault;
  }

  /// 当前是否处于「墨水屏背景主题」：未自定义背景色且选中的是
  /// 墨水屏预设。仅作为文字 / 强调色联动的判定依据，不改变持久值；
  /// 夜间压暗后的背景由各 resolve 方法按亮度另行回退。
  bool get isEInkBackground =>
      customBgColor == null &&
      bgPresetIndex.clamp(0, ReaderTokens.bgPresets.length - 1) ==
          ReaderTokens.eInkPresetIndex;

  /// 正文文字颜色（[customTextColor] 优先；否则按背景亮度自动取黑/白）。
  ///
  /// 墨水屏主题化：选中墨水屏背景且未自定义文字色时，日间（浅色背景）
  /// 使用炭灰正文色模拟墨水屏观感；夜间压暗后仍回退亮色文字保证可读。
  Color resolveTextColor(Color bg) {
    if (customTextColor != null) return Color(customTextColor!);
    if (bg.computeLuminance() > 0.5 && isEInkBackground) {
      return ReaderTokens.eInkTextColor;
    }
    return bg.computeLuminance() > 0.5
        ? const Color(0xFF1A1A1A)
        : const Color(0xFFE0E0E0);
  }

  /// 文字阴影颜色（[shadowColor] 优先；否则用正文色的半透明）。
  Color resolveShadowColor(Color textColor) {
    if (shadowColor != null) return Color(shadowColor!);
    return textColor.withValues(alpha: 0.3);
  }

  /// 构建正文 [TextStyle]，统一应用字号 / 行距 / 字距 / 字体 / 字重
  /// （[fontBold] 开启时按 [fontWeightValue] 滑块取 100–900 字重）/
  /// 斜体 / 下划线 / 颜色 / 阴影。paged 与 scroll 两种渲染共用，确保所有
  /// 字体样式真实生效且可共存。
  /// [autoTextColor] 为按背景亮度推导的默认色，[customTextColor] 非空时覆盖。
  ///
  /// 下划线：solid 实线走原生 `TextDecoration.underline`；
  /// dashed/wavy/dotted 交由上层 `_NovelPageWidget` 的 `CustomPaint` 自定义
  /// 绘制（原生 `TextDecorationStyle` 不支持自定义段长/间隙/波幅），
  /// 此时本样式不设 decoration。
  TextStyle resolveBodyTextStyle(Color autoTextColor) {
    final Color color =
        customTextColor != null ? Color(customTextColor!) : autoTextColor;
    final bool hasUnderline = fontUnderline;
    // 仅实线下划线走原生 decoration；其余样式由 CustomPaint 绘制。
    final bool nativeUnderline =
        hasUnderline && underlineStyle == NovelUnderlineStyle.solid;
    final FontWeight? weight;
    if (fontBold) {
      // 加粗开启时按字重滑块（100–900）取细粒度字重。
      // 对任意值按最近整百归一，防止旧数据/异常值落到 w900 导致忽粗忽细。
      final v = (fontWeightValue.clamp(100, 900) / 100).round() * 100;
      weight = switch (v) {
        100 => FontWeight.w100,
        200 => FontWeight.w200,
        300 => FontWeight.w300,
        400 => FontWeight.w400,
        500 => FontWeight.w500,
        600 => FontWeight.w600,
        700 => FontWeight.w700,
        800 => FontWeight.w800,
        _ => FontWeight.w900,
      };
    } else {
      weight = null;
    }
    return TextStyle(
      fontSize: fontSize,
      height: lineHeight,
      color: color,
      fontFamily: customFontPath != null ? customLoadedFontFamily : fontFamily,
      fontWeight: weight,
      fontStyle: fontItalic ? FontStyle.italic : null,
      decoration: nativeUnderline ? TextDecoration.underline : null,
      decorationColor: nativeUnderline && underlineColor != null
          ? Color(underlineColor!)
          : null,
      decorationStyle: null,
      decorationThickness: nativeUnderline ? underlineThickness : null,
      letterSpacing: letterSpacing == 0 ? null : letterSpacing,
      shadows: shadow
          ? <Shadow>[
              Shadow(
                color: resolveShadowColor(color),
                offset: Offset(shadowOffsetX, shadowOffsetY),
                blurRadius: shadowBlur,
              ),
            ]
          : null,
    );
  }

  /// 是否需要上层 CustomPaint 绘制非实线下划线（dashed/wavy/dotted）。
  bool get needsCustomUnderlinePaint =>
      fontUnderline && underlineStyle != NovelUnderlineStyle.solid;

  /// 下划线颜色（[underlineColor] 优先；否则跟随正文色）。
  Color? resolveUnderlineColor(Color textColor) {
    if (underlineColor != null) return Color(underlineColor!);
    return textColor;
  }

  /// 章节标题颜色（[titleColor] 优先；否则用强调色，与正文分开）。
  Color resolveTitleColor() {
    if (titleColor != null) return Color(titleColor!);
    return resolveEmphasisColor();
  }

  /// 构建章节大标题 [TextStyle]，与正文样式独立：字号 = 正文字号 ×
  /// [titleFontScale]，可单独加粗、单独配色，继承字体族与阴影。
  TextStyle resolveTitleTextStyle() {
    return TextStyle(
      fontSize: fontSize * titleFontScale,
      height: 1.3,
      color: resolveTitleColor(),
      fontFamily: titleCustomFontPath != null
          ? customLoadedTitleFontFamily
          : (titleFontFamily ??
              (customFontPath != null
                  ? customLoadedFontFamily
                  : fontFamily)),
      fontWeight: titleBold ? FontWeight.bold : FontWeight.w500,
      letterSpacing: letterSpacing == 0 ? null : letterSpacing,
    );
  }

  /// 序列化为 JSON。
  Map<String, dynamic> toJson() => <String, dynamic>{
        // 存档结构版本：用于「新默认值」的一次性迁移（见 [fromJson]）。
        'schema': kNovelPrefsSchema,
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'paragraphSpacing': paragraphSpacing,
        'margin': margin,
        'bgPresetIndex': bgPresetIndex,
        if (customBgColor != null) 'customBgColor': customBgColor,
        if (emphasisColor != null) 'emphasisColor': emphasisColor,
        if (customTextColor != null) 'customTextColor': customTextColor,
        if (shadowColor != null) 'shadowColor': shadowColor,
        'letterSpacing': letterSpacing,
        'fontBold': fontBold,
        'fontItalic': fontItalic,
        'fontUnderline': fontUnderline,
        'showChapterTitleInBody': showChapterTitleInBody,
        'titleFontScale': titleFontScale,
        'titleBold': titleBold,
        if (titleColor != null) 'titleColor': titleColor,
        'shadow': shadow,
        'pageAnimation': pageAnimation.name,
        'headerLeft': headerLeft.name,
        'headerRight': headerRight.name,
        'footerLeft': footerLeft.name,
        'footerRight': footerRight.name,
        'chineseConvert': chineseConvert,
        'autoPageInterval': autoPageInterval,
        'autoPageSmooth': autoPageSmooth,
        'volumeKeyPageTurn': volumeKeyPageTurn,
        if (fontFamily != null) 'fontFamily': fontFamily,
        'tapZoneInvert': tapZoneInvert.name,
        'tapZoneLayout': tapZoneLayout.name,
        'themeFollow': themeFollow.name,
        'bottomToolbarSlots':
            bottomToolbarSlots.map((NovelBottomTool t) => t.name).toList(),
        // 朗读
        'ttsSpeechRate': ttsSpeechRate,
        'ttsSleepTimer': ttsSleepTimer,
        'ttsBackground': ttsBackground,
        'ttsAutoNext': ttsAutoNext,
        'ttsRememberPosition': ttsRememberPosition,
        'ttsSystemNarratorVoice': ttsSystemNarratorVoice,
        'ttsSystemMaleVoice': ttsSystemMaleVoice,
        'ttsSystemFemaleVoice': ttsSystemFemaleVoice,
        // 字体/阴影/下划线
        if (customFontPath != null) 'customFontPath': customFontPath,
        'shadowBlur': shadowBlur,
        'shadowOffsetX': shadowOffsetX,
        'shadowOffsetY': shadowOffsetY,
        if (underlineColor != null) 'underlineColor': underlineColor,
        'underlineDashed': underlineDashed,
        'twoPageMode': twoPageMode,
        'underlineThickness': underlineThickness,
        'underlineDashLength': underlineDashLength,
        'underlineDashGap': underlineDashGap,
        // 标题
        'titleAlign': titleAlign.name,
        if (titleFontFamily != null) 'titleFontFamily': titleFontFamily,
        if (titleCustomFontPath != null)
          'titleCustomFontPath': titleCustomFontPath,
        'titleSegmentMode': titleSegmentMode,
        'titleSubScale': titleSubScale,
        'titleSegmentSpacing': titleSegmentSpacing,
        'titleSubLineSpacing': titleSubLineSpacing,
        'titleTopMargin': titleTopMargin,
        'titleBottomMargin': titleBottomMargin,
        // 页眉页脚
        'headerCenter': headerCenter.name,
        'footerCenter': footerCenter.name,
        if (headerFooterColor != null) 'headerFooterColor': headerFooterColor,
        'headerFooterMargin': headerFooterMargin,
        'scrollWheelInverted': scrollWheelInverted,
        // 排版增强
        'fontWeightValue': fontWeightValue,
        'textAlignMode': textAlignMode.name,
        'lineBreakMode': lineBreakMode.name,
        'underlineStyle': underlineStyle.name,
        // 滚动模式图文增强
        'scrollImageMode': scrollImageMode.name,
        'scrollImageAlign': scrollImageAlign.name,
        'scrollAutoNextChapter': scrollAutoNextChapter,
      };

  /// 从 JSON 反序列化。
  factory NovelReaderPreferences.fromJson(Map<String, dynamic> json) {
    // 旧版存档（无 schema 或 < 2）里的 ttsAutoNext=false 只是历史默认值，
    // 一律按新默认值（true）读取；用户改过之后会以 v2 写回，尊重其选择。
    final int schema = (json['schema'] as num?)?.toInt() ?? 1;
    final bool legacyAutoNext = schema < kNovelPrefsSchema;
    return NovelReaderPreferences(
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 18.0,
      lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.8,
      paragraphSpacing:
          (json['paragraphSpacing'] as num?)?.toDouble() ?? 16.0,
      margin: (json['margin'] as num?)?.toDouble() ?? 24.0,
      bgPresetIndex: json['bgPresetIndex'] as int? ?? 2,
      customBgColor: json['customBgColor'] as int?,
      emphasisColor: json['emphasisColor'] as int?,
      customTextColor: json['customTextColor'] as int?,
      shadowColor: json['shadowColor'] as int?,
      letterSpacing: (json['letterSpacing'] as num?)?.toDouble() ?? 0.0,
      fontItalic: json['fontItalic'] as bool? ?? false,
      fontUnderline: json['fontUnderline'] as bool? ?? false,
      showChapterTitleInBody:
          json['showChapterTitleInBody'] as bool? ?? true,
      titleFontScale: (json['titleFontScale'] as num?)?.toDouble() ?? 1.5,
      titleBold: json['titleBold'] as bool? ?? true,
      titleColor: json['titleColor'] as int?,
      shadow: json['shadow'] as bool? ?? false,
      pageAnimation:
          NovelPageAnimation.fromString(json['pageAnimation'] as String?),
      headerLeft: NovelHeaderFooterContent.fromString(
          json['headerLeft'] as String?),
      headerRight: NovelHeaderFooterContent.fromString(
          json['headerRight'] as String?),
      footerLeft: NovelHeaderFooterContent.fromString(
          json['footerLeft'] as String?),
      footerRight: NovelHeaderFooterContent.fromString(
          json['footerRight'] as String?),
      chineseConvert: json['chineseConvert'] as String? ?? 'none',
      autoPageInterval: (json['autoPageInterval'] as num?)?.toInt() ?? 0,
      autoPageSmooth: json['autoPageSmooth'] as bool? ?? false,
      volumeKeyPageTurn: json['volumeKeyPageTurn'] as bool? ?? false,
      fontFamily: json['fontFamily'] as String?,
      tapZoneInvert: _parseTapZoneInvert(json['tapZoneInvert']),
      tapZoneLayout: _parseTapZoneLayout(json['tapZoneLayout']),
      themeFollow: NovelThemeFollow.fromString(json['themeFollow'] as String?),
      bottomToolbarSlots: _parseBottomToolbarSlots(
          json['bottomToolbarSlots']),
      // 朗读
      ttsSpeechRate: (json['ttsSpeechRate'] as num?)?.toDouble() ?? 1.0,
      ttsSleepTimer: (json['ttsSleepTimer'] as num?)?.toInt() ?? 0,
      ttsBackground: json['ttsBackground'] as bool? ?? false,
      ttsRememberPosition:
          json['ttsRememberPosition'] as bool? ?? true,
      ttsAutoNext: legacyAutoNext
          ? true
          : (json['ttsAutoNext'] as bool? ?? true),
      ttsSystemNarratorVoice: json['ttsSystemNarratorVoice'] as String? ?? '',
      ttsSystemMaleVoice: json['ttsSystemMaleVoice'] as String? ?? '',
      ttsSystemFemaleVoice: json['ttsSystemFemaleVoice'] as String? ?? '',
      // 字体/阴影/下划线
      customFontPath: json['customFontPath'] as String?,
      shadowBlur: (json['shadowBlur'] as num?)?.toDouble() ?? 0.5,
      shadowOffsetX: (json['shadowOffsetX'] as num?)?.toDouble() ?? 0.5,
      shadowOffsetY: (json['shadowOffsetY'] as num?)?.toDouble() ?? 0.5,
      underlineColor: json['underlineColor'] as int?,
      underlineDashed: json['underlineDashed'] as bool? ?? false,
      twoPageMode: json['twoPageMode'] as bool? ?? false,
      underlineThickness:
          (json['underlineThickness'] as num?)?.toDouble() ?? 1.0,
      underlineDashLength:
          (json['underlineDashLength'] as num?)?.toDouble() ?? 4.0,
      underlineDashGap: (json['underlineDashGap'] as num?)?.toDouble() ?? 2.0,
      // 标题
      titleAlign: NovelTitleAlign.fromString(json['titleAlign'] as String?),
      titleFontFamily: json['titleFontFamily'] as String?,
      titleCustomFontPath: json['titleCustomFontPath'] as String?,
      titleSegmentMode: json['titleSegmentMode'] as bool? ?? false,
      titleSubScale: (json['titleSubScale'] as num?)?.toDouble() ?? 0.8,
      titleSegmentSpacing:
          (json['titleSegmentSpacing'] as num?)?.toDouble() ?? 8.0,
      titleSubLineSpacing:
          (json['titleSubLineSpacing'] as num?)?.toDouble() ?? 1.3,
      titleTopMargin: (json['titleTopMargin'] as num?)?.toDouble() ?? 0.0,
      titleBottomMargin:
          (json['titleBottomMargin'] as num?)?.toDouble() ?? 0.0,
      // 页眉页脚
      headerCenter: NovelHeaderFooterContent.fromString(
          json['headerCenter'] as String?),
      footerCenter: NovelHeaderFooterContent.fromString(
          json['footerCenter'] as String?),
      headerFooterColor: json['headerFooterColor'] as int?,
      headerFooterMargin:
          (json['headerFooterMargin'] as num?)?.toDouble() ?? 12.0,
      scrollWheelInverted: json['scrollWheelInverted'] as bool? ?? false,
      // 排版增强
      fontBold: _legacyFontBold(json),
      fontWeightValue:
          ((json['fontWeightValue'] as num?)?.toInt() ?? 700).clamp(100, 900),
      textAlignMode: NovelTextAlignMode.fromString(
          json['textAlignMode'] as String?),
      lineBreakMode: NovelLineBreakMode.fromString(
          json['lineBreakMode'] as String?),
      underlineStyle: NovelUnderlineStyle.fromString(
          json['underlineStyle'] as String?),
      // 滚动模式图文增强
      scrollImageMode: NovelScrollImageMode.fromString(
          json['scrollImageMode'] as String?),
      scrollImageAlign: NovelScrollImageAlign.fromString(
          json['scrollImageAlign'] as String?),
      scrollAutoNextChapter: json['scrollAutoNextChapter'] as bool? ?? true,
    );
  }
}

/// 解析点击分区反转（兼容旧版字符串 'none'/'leftRight'/'all'）。
TapZoneInvert _parseTapZoneInvert(Object? raw) {
  if (raw is String) {
    return TapZoneInvert.values.firstWhere(
      (TapZoneInvert e) => e.name == raw,
      orElse: () => TapZoneInvert.none,
    );
  }
  return TapZoneInvert.none;
}

/// 解析点击分区布局。
ReaderTapZoneLayout _parseTapZoneLayout(Object? raw) {
  if (raw is String) {
    return ReaderTapZoneLayout.values.firstWhere(
      (ReaderTapZoneLayout e) => e.name == raw,
      orElse: () => ReaderTapZoneLayout.lShape,
    );
  }
  return ReaderTapZoneLayout.lShape;
}

/// 解析底部工具栏槽位（无效 / 为空时回退默认）。
List<NovelBottomTool> _parseBottomToolbarSlots(Object? raw) {
  if (raw is List) {
    final parsed = <NovelBottomTool>[];
    for (final item in raw) {
      final t = NovelBottomTool.fromString(item?.toString());
      if (t != null) parsed.add(t);
    }
    if (parsed.isNotEmpty) return parsed;
  }
  return NovelBottomTool.defaults;
}

/// 旧版字重语义迁移：fontWeightValue 曾是「null = 跟随 fontBold 开关、
/// 非空时整体接管渲染」的细粒度字段（阅读器关闭加粗时会写入 400）。
/// 新语义下 fontWeightValue 仅是加粗开启时的滑块值，这里把旧数据统一
/// 折算：权重 >=600 视为加粗，<600 视为未加粗。
bool _legacyFontBold(Map<String, dynamic> json) {
  final rawWeight = (json['fontWeightValue'] as num?)?.toInt();
  if (rawWeight == null) return json['fontBold'] as bool? ?? false;
  return rawWeight >= 600;
}

/// 计算 [next] 相对 [prev] 发生变化的字段名集合（[NovelReaderPreferences.toJson] 键）。
///
/// 列表字段按内容比较，其余用 `==`。弹窗每次改动调用一次，
/// 把差集累积进「本书单独设置」覆盖记录，取代整包落盘后的默认值猜测。
Set<String> novelPrefsChangedKeys(
  NovelReaderPreferences prev,
  NovelReaderPreferences next,
) {
  final a = prev.toJson();
  final b = next.toJson();
  final changed = <String>{};
  for (final entry in b.entries) {
    final av = a[entry.key];
    final bv = entry.value;
    if (av is List && bv is List) {
      if (!listEquals(av, bv)) changed.add(entry.key);
    } else if (av != bv) {
      changed.add(entry.key);
    }
  }
  return changed;
}

/// 小说阅读器偏好存储（按 novelId 持久化）。
class NovelReaderPreferencesStore {
  NovelReaderPreferencesStore({PrefsBackend? backend})
      : _backend = backend ?? const SharedPrefsBackend();

  final PrefsBackend _backend;
  final Map<String, NovelReaderPreferences> _cache = {};

  static const String _prefix = 'novel_prefs_';

  /// 显式「本书单独设置」覆盖记录的 sidecar 键后缀。
  ///
  /// 与偏好本体分开存：本体仍是完整 JSON（兼容旧版/云同步），但合并时只认
  /// 这里列出的字段；未列出的字段实时跟随总设置。
  static const String _overrideSuffix = '#ovr';

  Future<NovelReaderPreferences> get(String novelId) async {
    final cached = _cache[novelId];
    if (cached != null) return cached;
    final raw = await _backend.get('$_prefix$novelId');
    if (raw == null || raw.isEmpty) return const NovelReaderPreferences();
    try {
      return NovelReaderPreferences.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return const NovelReaderPreferences();
    }
  }

  /// 读取本书显式单独设置过的字段名集合。
  ///
  /// 无 sidecar 记录的历史数据按旧规则迁移推断：与类默认值不同的字段视为
  /// 单独设置（维持既有表现，不丢用户已调好的配置）。
  Future<Set<String>> getOverrideKeys(String novelId) async {
    final raw = await _backend.get('$_prefix$novelId$_overrideSuffix');
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return <String>{for (final e in decoded) e.toString()};
        }
      } on Object {
        // 解析失败则回退到旧规则推断。
      }
    }
    final stored = await get(novelId);
    return novelPrefsChangedKeys(const NovelReaderPreferences(), stored);
  }

  /// 保存偏好。[overrideKeys] 非空时同步写入显式覆盖记录；
  /// 传空集合表示清除全部单独设置（恢复本书默认）。
  Future<void> save(
    String novelId,
    NovelReaderPreferences prefs, {
    Set<String>? overrideKeys,
  }) async {
    _cache[novelId] = prefs;
    await _backend.set('$_prefix$novelId', jsonEncode(prefs.toJson()));
    if (overrideKeys != null) {
      await _backend.set('$_prefix$novelId$_overrideSuffix',
          jsonEncode(overrideKeys.toList()..sort()));
    }
  }
}
