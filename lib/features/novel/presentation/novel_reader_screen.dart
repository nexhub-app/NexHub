import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:nexhub/core/local/saf_bridge.dart';
import 'package:nexhub/core/local/text_encoding.dart';
import 'package:nexhub/core/local/local_content_manager.dart'
    show isDocUri;
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../../core/platform/brightness_compat.dart';
import '../../../core/platform/harmony_continuation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/comic/models/reader_preferences.dart'
    show ReaderTapZoneLayout, TapZoneInvert;
import '../../../core/comic/image_favorite_manager.dart';
import '../../../core/novel/novel_replace_rule.dart' show NovelReplaceRuleSet;
import '../../../core/novel/novel_replace_rule_store.dart'
    show NovelReplaceRuleStore;
import '../../../core/novel/novel_highlight_rule.dart'
    show NovelHighlightRuleSet;
import '../../../core/novel/novel_rule_cache.dart' show NovelRuleCache;
import '../../../core/novel/novel_replace_rule_screen.dart'
    show NovelReplaceRuleScreen;
import '../../../core/favorites/favorites_manager.dart';
import '../../../core/history/history_manager.dart';
import '../../../core/history/media_watched_manager.dart';
import '../../../core/models/episode.dart';
import '../../../core/models/media_item.dart';
import '../../../core/models/novel_block.dart';
import '../../../core/utils/app_log.dart';
import '../../../core/utils/volume_key_listener.dart';
import '../../../core/platform/platform_service.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/download/download_manager.dart';
import '../../../core/download/local_to_online.dart';
import '../../../core/novel/novel_page_animation.dart';
import '../../../core/novel/novel_progress_conflict.dart';
import '../../../core/novel/novel_progress_manager.dart';
import '../../../core/novel/novel_tts_progress_store.dart';
import '../../../core/novel/novel_reader_preferences.dart';
import '../../../core/novel/novel_tts_router.dart' show NovelTtsSystemSlots;
import '../../../core/novel/novel_pre_download_preferences.dart';
import '../../../core/novel/novel_pre_downloader.dart';
import '../../../core/services/novel_highlight_sync_service.dart';
import 'novel_selection_ai_dialog.dart';
import '../../../core/reader/tap_zone_resolver.dart';
import '../../../core/reader/reading_queue_store.dart';
import '../../../core/widgets/reading_queue_sheet.dart'
    show openReadingQueueSheet;
import '../../../core/settings/general_settings.dart';
import '../../../core/settings/reader_default_settings.dart';
import '../../../core/scraper/media_api_service.dart';
import '../../../core/scraper/verification_detector.dart';
import '../../../core/services/novel_progress_sync_service.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/async_session.dart';
import '../../../core/player/audio_playback_service.dart';
import '../../../core/stats/reading_session_recorder.dart';
import '../../../core/stats/stats_models.dart';
import '../../../core/stats/stats_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/reader_tokens.dart';
import '../../../core/widgets/app_loading_indicator.dart';
import '../../../core/widgets/chapter_list_sheet.dart';
import '../../../core/widgets/highlight_text.dart' show searchHitSpans;
import '../../../core/widgets/detail_action_utils.dart';
import '../../../core/widgets/web_favorite_action.dart';
import '../../../core/widgets/source_image.dart';
import '../../../core/widgets/translatable_text.dart';
import '../../../core/widgets/tolerant_long_press.dart';
import '../../../core/novel/novel_chinese_converter.dart';
import '../../verification/presentation/webview_verification_screen.dart';
import '../../../core/resolver/webview_resolver.dart';
import '../../../core/local/local_novel_parser.dart';
import '../../../core/local/portable_book_parser.dart'
    show PortableBookParser, isPortableBookFile;
import '../../../core/novel/novel_content_edit_manager.dart';
import '../../../core/novel/novel_translation_manager.dart';
import '../../../core/novel/novel_toc_store.dart';
import '../../../core/utils/app_haptics.dart';
import 'novel_animated_page_view.dart';
import 'novel_bookmark_manager.dart';
import 'novel_in_book_search_sheet.dart';
import 'novel_note_manager.dart';
import 'novel_paginator.dart';
import 'novel_selection_controller.dart';
import '../../../core/novel/novel_highlight_manager.dart';
import 'novel_tts_controller.dart';
import 'novel_tts_cast_sheet.dart';
import 'package:nexhub/core/widgets/app_alert_dialog.dart';
import 'package:flutter/services.dart';
import '../domain/novel_summary_service.dart';
import '../domain/novel_summary_settings.dart';
import '../domain/novel_polish_service.dart';
import '../domain/novel_prescan_service.dart';
import '../domain/novel_translation_fingerprint.dart';
import '../domain/novel_translation_service.dart';
import '../domain/novel_illustration_service.dart';
import '../../../core/ai/glossary_manager.dart';
import '../../../core/ai/translation_exception.dart';
import '../../../core/ai/translation_options_store.dart';
import '../../../core/novel/novel_prescan_manager.dart';
import '../../settings/presentation/settings_ai_screen.dart';
import '../../settings/presentation/translation_glossary_screen.dart';
// 内容编辑：正文编辑持久化管理器（Hive `novel_content_edits`）。

/// 小说阅读器（Phase 4 — Task 19/20）。
///
/// 支持文本分页、6 种翻页动画（none/slide/scroll/fade/cover/simulation）、
/// 点击区域翻页（左 1/3 = 上一页 / 中 1/3 = 切换 UI / 右 1/3 = 下一页）、
/// 左侧 1/3 竖向拖拽亮度调节、内联设置面板（桌面右侧 ~360px / 移动底部 ~55%）、
/// 章节导航、进度自动保存。
///
/// 本地模式（Task .B.3）：传入 [localTextPath]（TXT）或 [localEpubPath]（EPUB）
/// 时进入本地模式，跳过在线源解析，直接读取本地文本文件（兼容 UTF-8 BOM / UTF-8 /
/// latin1；EPUB 经 [LocalNovelParser] 解析章节）。本地模式下隐藏切换章节 / 切换源 /
/// WebView / 书内搜索等在线专属 UI，保留翻页动画、TTS、书签笔记（用
/// [novelId] = `'local_${file.path.hashCode}'`）。调用方需将 [novelId] 设为
/// `'local_${file.path.hashCode}'`，[chapters] 传空列表。
///
/// 聚合本地模式（B 阶段）：传入 [localChapterPaths]（多文件绝对路径列表，每个文件 =
/// 一章）时同样进入本地模式，但保留目录/上下章导航；[chapters] 为对应的合成章节列表
/// （每文件一章），按索引读取对应文件。与单文件本地模式的区别仅在于支持多章节切换。
class NovelReaderScreen extends StatefulWidget {
  final String novelId;
  final String title;
  final String sourceId;
  final List<Episode> chapters;
  final int initialChapterIndex;

  /// 本地模式：本地 TXT 文件路径（跳过在线源解析，直接读取）。
  final String? localTextPath;

  /// 本地模式：本地 EPUB 文件路径（经 [LocalNovelParser] 解析为章节后渲染）。
  final String? localEpubPath;

  /// 本地聚合模式（B 阶段）：文件夹导入，多文件合成一整本，每个文件 = 一章。
  /// 传文件绝对路径列表；[chapters] 为对应的合成章节（每文件一章）。
  /// 与 [localTextPath]/[localEpubPath] 互斥，优先于单文件本地模式。
  final List<String>? localChapterPaths;

  /// 详情页 URL（用于收藏时透传，避免历史/收藏详情灰屏）。
  final String? detailUrl;

  /// 封面 URL（用于收藏时透传，避免收藏书架缺封面）。
  final String? coverUrl;

  /// 是否恢复上次阅读进度：true 时从 [NovelProgressManager] 加载保存的
  /// chapterIndex / currentPage；false 时使用 [initialChapterIndex]（详情页
  /// 章节列表点击场景）。默认 true（与本地模式等场景保持原行为兼容）。
  final bool restoreProgress;

  /// 跨设备接续：进入时直接落到的页码 / 章内字符偏移（优先于本地进度）。
  final int? initialPage;
  final int? initialCharOffset;

  const NovelReaderScreen({
    super.key,
    required this.novelId,
    required this.title,
    required this.sourceId,
    required this.chapters,
    this.initialChapterIndex = 0,
    this.localTextPath,
    this.localEpubPath,
    this.localChapterPaths,
    this.detailUrl,
    this.coverUrl,
    this.restoreProgress = true,
    this.initialPage,
    this.initialCharOffset,
  });

  @override
  State<NovelReaderScreen> createState() => _NovelReaderScreenState();
}

/// TTS 播放状态流（供通知栏会话订阅）。
///
/// 以 [NovelTtsController] 的 listener 广播 isPlaying 变化：仅在有变化时推送
/// （段落切换等无关事件不触发通知刷新）；onCancel 时解除监听。
Stream<bool> _ttsPlayingStream(NovelTtsController tts) {
  return Stream<bool>.multi((StreamController<bool> controller) {
    bool last = tts.isPlaying;
    controller.add(last);
    void listener() {
      final bool now = tts.isPlaying;
      if (now == last) return;
      last = now;
      controller.add(now);
    }

    tts.addListener(listener);
    controller.onCancel = () => tts.removeListener(listener);
  });
}

/// 朗读睡眠定时选择（分钟；0 = 关闭）。
/// 预设 0/15/30/45/60/90 分钟，并提供「自定义」可输入任意分钟数
/// （满足「自定义朗读时间」需求）。返回选中的分钟数（null = 取消）。
/// 库级私有函数：既被 [_NovelReaderScreenState] 的朗读栏调用，
/// 也被 [_NovelInlineSettings] 设置面板调用（二者不在同一类层级）。
Future<int?> _pickSleepMinutes({
  required BuildContext context,
  required AppLocalizations l10n,
  required int current,
}) async {
  const List<int> presets = <int>[0, 15, 30, 45, 60, 90];
  bool customActive = current > 0 && !presets.contains(current);
  int? customValue = customActive ? current : null;
  final int? result = await showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx2, setDialogState) => AppAlertDialog(
        title: Text(l10n.ttsSleepTimer),
        content: SingleChildScrollView(
          child: RadioGroup<int>(
            groupValue: customActive ? -1 : current,
            // MD3「Selected」：单选选中 → tick。预设项直接以所选分钟数关闭
            // 对话框；「自定义」项转入输入态。
            onChanged: (v) {
              AppHaptics.tick();
              if (v == -1) {
                setDialogState(() => customActive = true);
              } else {
                Navigator.of(ctx).pop(v);
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final m in presets)
                  RadioListTile<int>(
                    title: Text(m == 0 ? l10n.ttsSleepOff : l10n.minuteUnit(m)),
                    value: m,
                  ),
                RadioListTile<int>(
                  title: Text(l10n.ttsSleepCustom),
                  value: -1,
                ),
                if (customActive)
                  Padding(
                    padding: const EdgeInsets.only(
                        top: AppTokens.spaceSm,
                        left: AppTokens.spaceMd,
                        right: AppTokens.spaceMd),
                    child: TextField(
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.ttsSleepCustomMinutes,
                        suffixText: l10n.minuteUnit(1),
                      ),
                      onChanged: (v) => setDialogState(
                          () => customValue = int.tryParse(v.trim())),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(
              customActive ? (customValue ?? 0) : current,
            ),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    ),
  );
  return result;
}

/// 在独立 isolate 解析 EPUB（bug 116）：返回可序列化扁平结构，主线程再重组为
/// [LocalNovelBook]（[compute] 不支持自定义类的跨 isolate 传输）。
Future<List<dynamic>> _parseEpubIsolate(String path) async {
  final book = await LocalNovelParser.parseEpub(path);
  return <dynamic>[
    book.title,
    book.author,
    book.coverPath,
    <List<dynamic>>[
      for (final c in book.chapters) <dynamic>[c.title, c.content],
    ],
  ];
}

/// 在独立 isolate 解析单文件 TXT 为**章节结构**（/）：读取 + 解码 +
/// 行级章节切分（[LocalNovelParser.splitTxtChapters]，不依赖空行分段，
/// 单换行分隔的 TXT 也能正确分章；英文章节名/拼写数字亦命中）。
/// 返回可序列化章节列表：每个元素为 `[title, blocks]`，blocks 内元素为
/// `[0, text]`（文本段）或 `[1, imagePath]`（下载器占位的本地插图）。
///
/// 参数为 `(path, fallback)` 记录：[path] 是**实际要读取的文件**（SAF 下载内容经
/// [resolveSafUri] 落盘后的缓存路径）；[fallback] 是源文件的标题（去扩展名）。
/// 二者分离是关键：下载的单章 TXT 正文通常不含「第X章」标题行，`splitTxtChapters`
/// 会落到 `fallbackTitle` 兜底；若像旧实现那样用 `basename(path)` 当兜底，标题就会
/// 显示成缓存文件名（`saf_<hash>`），即「标签变成 saf 的内容」。
Future<List<dynamic>> _parseTxtChaptersIsolate(
    (String path, String fallback) args) async {
  final path = args.$1;
  final bytes = await File(path).readAsBytes();
  var text = decodeTextBytes(bytes);
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final chapters =
      LocalNovelParser.splitTxtChapters(text, fallbackTitle: args.$2);
  // 段落 → 可序列化字符串：下载器内联插图以 [kNexhubImgMarker] 占位行写入，
  // 原样保留，交由主线程 build 阶段（_loadLocalText 的 singleTxt 分支）识别为
  // 本地插图 [NovelImageBlock]；不再包成 [0,para]/[1,img] 块——消费端
  // `List<String>.from(c[1])` 与 build 循环均按纯字符串处理，否则会触发
  // `type 'List<dynamic>' is not a subtype of type 'String'`。
  return <dynamic>[
    for (final ch in chapters)
      <dynamic>[
        ch.title,
        <dynamic>[for (final para in ch.content) para]
      ],
  ];
}

/// 聚合本地模式的章节排序方式（见 [_NovelReaderScreenState._aggMode]）。
enum _AggChapterMode { fileExpanded, epubLast, collapsed }

/// 在独立 isolate 解析便携文档（Mobi/PDF 文本层）为章节结构，
/// 返回形状与 [_parseTxtChaptersIsolate] 一致（`[title, [para,…]]` 列表）。
Future<List<dynamic>> _parsePortableIsolate(String path) async {
  final book = await PortableBookParser.parse(path);
  return <dynamic>[
    <dynamic>[
      book.title,
      <dynamic>[for (final c in book.chapters[0].content) c]
    ],
  ];
}

class _NovelReaderScreenState extends State<NovelReaderScreen>
    with WidgetsBindingObserver {
  final NovelReaderPreferencesStore _store = NovelReaderPreferencesStore();

  /// 本书显式单独设置过的字段名（[NovelReaderPreferences.toJson] 键）。
  /// 只有这些字段覆盖全局默认，其余实时跟随总设置。
  Set<String> _overrideKeys = <String>{};
  final NovelProgressManager _progress = NovelProgressManager();

  /// 下载管理器（initState 缓存引用，dispose 阶段 context 已不可用）。
  DownloadManager? _downloadManager;

  /// 收藏管理器（dispose 阶段查排除分类用）。
  FavoritesManager? _favorites;
  final NovelBookmarkManager _bookmarks = NovelBookmarkManager();
  final BrightnessCompat _brightnessPlugin = BrightnessCompat();

  /// 选区控制器：维护活动选区与已存划线的章节全局偏移锚点，
  /// 并负责渲染层（[_NovelPageWidget]）的实时刷新。
  final NovelSelectionController _selectionController =
      NovelSelectionController();

  /// 选区工具条是否可见（长按选区结束后显示）。
  bool _showSelectionToolbar = false;

  /// 长按选区手势进行中（按下到松手之间）：用于阻止翻页拖拽抢走长按指针，
  /// 避免「长按选中一闪即逝」被横向翻页手势打断。
  bool _longPressEngaged = false;

  /// 刚由长按确认选区的时刻（null = 无待吞 tap）。用于吞掉长按松手后**极短
  /// 窗口内**（[_kSelectionTapSinkWindow]）跟随的 tap-up，避免误清空刚建立的
  /// 选区；窗口之外的点击照常收起工具条——否则会吞掉用户退出工具栏的第一下
  /// （表现为「要点两下才退出」）。
  DateTime? _selectionJustConfirmedAt;

  /// 长按确认选区后，允许吞掉紧随 tap 的时间窗口。
  static const Duration _kSelectionTapSinkWindow = Duration(milliseconds: 250);

  /// 划线色板（ARGB，含 50% 透明度，与活动选区同调）。
  static const List<int> _highlightPalette = <int>[
    0x80FFFF00,
    0x8000FF00,
    0x8080C0FF,
    0x80FF80AB,
  ];
  final GlobalKey<NovelAnimatedPageViewState> _pageKey =
      GlobalKey<NovelAnimatedPageViewState>();

  late NovelReaderPreferences _prefs;
  int _chapterIndex = 0;

  /// 本地加载代次守卫：快速翻章 / 初始与切换并发时，丢弃过期结果，
  /// 避免较慢的初始解析覆盖已切换的章节（表现为「切换章还是同一章」）。
  final AsyncSession _loadSession = AsyncSession();
  int _savedPage = 0;

  /// 待恢复的「章内字符偏移」。
  ///
  /// 进入阅读器时若存档带有字符偏移，则优先用偏移恢复阅读位置，
  /// 而非页码——因为页码随字号/边距/排版变化而漂移，字符偏移恒定。
  /// 该值在 [_buildReader] 分页就绪后消费一次并清 null；为 null 时回退页码。
  int? _savedCharOffset;

  /// 网络拉取的原始图文块（未做繁简转换）。
  List<NovelBlock> _rawParagraphs = const <NovelBlock>[];

  /// 跨设备接续持有者 token（null = 未注册，如本地书 / 无源）。
  Object? _continuationToken;

  /// 实际渲染的图文块（应用繁简转换 + 替换规则后）。
  List<NovelBlock> _paragraphs = const <NovelBlock>[];

  /// 当前书籍的净化规则（全局一套，惰性加载，在 [_loadChapter] 中填充）。
  NovelReplaceRuleSet? _replaceRuleSet;

  /// 本书是否启用净化（阅读器内可单独关闭，默认开启）。
  bool _replaceBookEnabled = true;

  /// 当前书籍的高亮规则（惰性加载，在 [_loadChapter] 中填充）。
  NovelHighlightRuleSet? _highlightRuleSet;

  /// 内容编辑：正文编辑持久化管理器 + 「当前章是否被编辑过」标记
  /// （控制菜单「内容编辑 / 恢复原文」入口与已编辑角标）。
  final NovelContentEditManager _contentEdits = NovelContentEditManager();
  bool _currentChapterEdited = false;

  /// 朗读用段落文本：**与正文块一一对应**（插图块占位为空串）。
  ///
  /// 早前这里直接跳过插图块，导致「文本索引」与「正文块索引」在有插图的
  /// 章节里错位：朗读高亮 / 点段落跳读 / 自动定位全都指到错误的段落。
  /// 现在保持同长（空串不参与分句），索引即正文块索引，各处比对一致。
  List<String> get _paragraphTexts => <String>[
        for (final b in _paragraphs) b is NovelTextBlock ? b.text : '',
      ];
  NovelPaginationResult? _pagination;

  /// 当前 [_pagination] 对应的章节下标。用于检测「跨章后分页是否需刷新」：
  /// 相邻两章页数可能相同，仅比较页数长度无法触发刷新（会残留上一章的分页）。
  int _paginationChapterIndex = -1;

  /// 分页缓存签名：仅当影响分页的输入（正文版本 / 偏好版本 / 章节下标 / 可用
  /// 尺寸 / 系统字号缩放 / 文字方向 / 章节标题 / 书名）真正变化时才重新分页。
  /// 否则直接在 build（含翻页动画每帧触发的父层重建、_onPageChanged 触发的重建）
  /// 中复用缓存，避免整章重新分页造成的卡顿，也避免翻页动画被重型计算抢占而
  /// 看起来「无动画」。
  String? _paginationSig;

  /// 偏好版本号：任何阅读设置（字号/行距/段距/边距/字体/标题样式…）变化都自增，
  /// 作为分页缓存签名的一部分，确保改设置后分页立即刷新。
  int _prefsVersion = 0;

  /// 整本分页校准：本会话内已见过的「章节 → 页数」缓存。每次某章完成
  /// 分页即记录；整本页码 tip 由它跨章累计（会话级，不持久化——页数随
  /// 排版偏好与屏幕尺寸变化，跨会话复用反而失真）。
  final Map<int, int> _chapterPageCounts = <int, int>{};

  /// 双页模式：当前章是否以双页呈现（与最近一次分页的判定一致，
  /// 由 build 的 LayoutBuilder 按偏好 + 宽高比计算后写入）。
  bool _twoPageActive = false;

  /// 双页模式两页间的中缝宽度（逻辑像素）。
  static const double _kTwoPageGutter = 16;

  /// 计算整本页码文案：
  /// - 全部章节数已知 → `第 X 页 / 共 Y 页`（精确校准）；
  /// - 部分已知 → `全书第 X+ 页`（`+` 表示后续章节尚未校准，估算值）；
  /// - 无任何分页数据 → 空串（槽位退化为空）。
  String _bookPageLabelFor(int page) {
    if (_chapterPageCounts.isEmpty) return '';
    var before = 0;
    for (final e in _chapterPageCounts.entries) {
      if (e.key < _chapterIndex) before += e.value;
    }
    final x = before + page + 1;
    final totalChapters = _effectiveChapters.length;
    var totalPages = 0;
    for (final e in _chapterPageCounts.entries) {
      totalPages += e.value;
    }
    final bool allKnown =
        totalChapters > 0 && _chapterPageCounts.length >= totalChapters;
    return allKnown ? '第 $x 页 / 共 $totalPages 页' : '全书第 $x+ 页';
  }

  bool _loading = true;
  String? _error;
  bool _isResolveError = false;

  /// 正文抓取撞验证（如 Cloudflare 临时挑战）时记录异常：错误视图的重试
  /// 按钮改走验证页（回灌 Cookie 后重载本章），而非死错误无验证入口。
  VerificationRequiredException? _verificationError;

  /// 正文抓取被反爬拦截且源声明 useWebview 时记录 [WebViewHtmlRequest]：错误
  /// 视图提供「抓取本章渲染内容」入口，打开真浏览器取回渲染后 HTML 回灌解析，
  /// 而非走无效的手动 Cookie 验证（Dart HTTP 的 TLS 指纹被 Cloudflare 拒）。
  WebViewHtmlRequest? _htmlCaptureRequest;

  /// 本地单文件（EPUB / TXT）：整本解析一次后缓存的章节列表，以及对应的
  /// 章节导航列表（供目录/上下章）。逐章加载：`_loadLocalText` 每次
  /// 只把 [_localParsedChapters] 中当前章节的段落装进分页，翻章时重新分页
  /// 当前章，与在线小说阅读体验一致。
  /// TXT 走 [LocalNovelParser.splitTxtChapters] 行级切分（/）。
  List<LocalNovelChapter>? _localParsedChapters;
  List<Episode>? _parsedChapterEpisodes;

  /// 打开本地单文件（EPUB / TXT）时保存的进度章节（解析完成后才应用，
  /// 因为解析前还不知道章节总数）。
  int? _restoreParsedChapterIndex;

  /// 聚合本地模式（多文件合成一本）的章节排序方式：
  /// - [fileExpanded]：按文件名顺序，EPUB 内部章节在其文件位置就地展开；
  /// - [epubLast]：TXT 文件章节在前，EPUB 内部章节统一排最后；
  /// - [collapsed]：每文件一章（EPUB 不展开，保留原行为）。
  ///
  /// 阅读时可在顶栏「更多」菜单随时切换，切换后重建目录并回到当前章节。
  _AggChapterMode _aggMode = _AggChapterMode.fileExpanded;

  /// 聚合模式构建后的完整章节目录（TXT 每文件一章 + EPUB 展开内部章节）。
  /// null 表示尚未构建（首次加载章节前由 [_ensureAggregatedChapters] 异步构建）。
  List<Episode>? _expandedChapters;

  /// 聚合模式已解析的 EPUB 缓存（path -> 整本），展开目录与逐章读取共用。
  final Map<String, LocalNovelBook> _aggEpubBooks = <String, LocalNovelBook>{};

  /// 聚合模式已解析的 TXT 缓存（path -> 整本），展开内部章节与逐章读取共用。
  /// 与 [_aggEpubBooks] 同构，实现「TXT 目录导入内部章节细化（和 epub 一样）」。
  final Map<String, LocalNovelBook> _aggTxtBooks = <String, LocalNovelBook>{};

  /// 聚合模式 TXT 章节路由：episode.id -> (文件 path, 内部章节下标 ci)。
  /// ci = -1 表示整文件（无内部章节）。用精确字符串匹配路由，规避文件路径含
  /// 分隔符导致的解析歧义；续读进度按 index 存储，合成 id 不影响续读。
  final Map<String, (String, int)> _aggTxtEpisodeMeta =
      <String, (String, int)>{};
  bool _aggBuilding = false;

  /// 是否为本地文件模式（Task .B.3）。
  bool get _isLocalMode =>
      widget.localTextPath != null ||
      widget.localEpubPath != null ||
      widget.localChapterPaths != null;

  /// 跨设备接续快照：书标识 + 当前章 + 页码 / 字符偏移。
  Map<String, Object?>? _buildContinuationSnapshot() {
    final List<Episode> chapters = _effectiveChapters;
    if (chapters.isEmpty) return null;
    final int idx = _chapterIndex.clamp(0, chapters.length - 1);
    final ({List<Map<String, dynamic>> items, int start})? window =
        HarmonyContinuation.encodeChapterWindow(chapters, idx);
    final int page = _currentPage < 0 ? 0 : _currentPage;
    return <String, Object?>{
      'type': 'novel',
      'title': widget.title,
      'sourceId': widget.sourceId,
      'contentId': widget.novelId,
      'chapterIndex': idx,
      'episode': chapters[idx].toJson(),
      if (window != null) 'episodes': window.items,
      if (window != null) 'episodeStart': window.start,
      'page': page,
      if (_pagination != null) 'charOffset': _charOffsetForPage(page),
      if (widget.detailUrl != null) 'detailUrl': widget.detailUrl,
      if (widget.coverUrl != null) 'coverUrl': widget.coverUrl,
    };
  }

  /// 本地聚合模式（B 阶段）：多个文本/EPUB 文件合成一整本，每个文件 = 一章。
  bool get _isAggregatedLocal =>
      widget.localChapterPaths != null && widget.localChapterPaths!.isNotEmpty;

  /// 实际可用的章节列表：聚合本地用构建后的展开目录（EPUB 拆成多章），
  /// 单 EPUB 用解析出的章节，其余用传入的 [widget.chapters]。
  List<Episode> get _effectiveChapters {
    if (_isAggregatedLocal && _expandedChapters != null) {
      return _expandedChapters!;
    }
    return widget.chapters.isNotEmpty
        ? widget.chapters
        : (_parsedChapterEpisodes ?? const <Episode>[]);
  }

  ScrollController? _scrollController;

  /// 滚动模式「无缝连排」的章节缓冲段（按章节升序）。
  ///
  /// 滚动模式下恒有至少一段（当前章）；开启
  /// [NovelReaderPreferences.scrollAutoNextChapter] 时，临近段末会自动把
  /// 下一章正文追加到列表尾部，读者可以一路向下滚跨章，不必手动翻章。
  /// 翻页模式不使用该缓冲。
  final List<_NovelScrollSegment> _scrollSegments = <_NovelScrollSegment>[];

  /// 各段在扁平列表中的起始下标（末项 = 总项数）。
  final List<int> _scrollSegStarts = <int>[0];

  /// 正在追加下一章段（防重入，同时驱动列表尾部加载提示）。
  bool _scrollAppending = false;

  /// 最近一次追加失败的章节下标与时间：尾部提供「点击重试」，并做请求退避
  /// （避免用户在章末轻微滚动时反复发起失败的抓取）。
  int _scrollAppendFailedFor = -1;
  DateTime? _scrollAppendFailedAt;

  /// 滚动连排是否生效：滚动模式 + 用户开启「章末自动接续」。
  bool get _scrollAutoNextEnabled =>
      _prefs.pageAnimation.isScroll && _prefs.scrollAutoNextChapter;

  int _currentPage = 0;
  bool _uiVisible = false;
  int _contentVersion = 0;

  /// 搜索关键词（用于正文高亮）。搜索跳转后设置，3 秒后清除。
  String? _searchKeyword;

  /// 正则搜索模式下的已编译表达式（正文高亮用；普通子串搜索为 null）。
  RegExp? _searchRegex;
  Timer? _searchHighlightTimer;

  /// scroll 模式下当前滚动比例（0..1），用于同步底部进度滑条。
  double _scrollFraction = 0;

  /// 是否正在把视图恢复到保存的页码（滚动模式）。
  ///
  /// 恢复期间的滚动位置是过渡值（通常为 0），照常写盘会把上次的阅读位置
  /// 冲成第一页 —— 这是「记住阅读进度没作用」的根因之一。
  bool _restoringPage = false;

  // ─────────────────────── 亮度手势 ───────────────────────
  double _brightness = 0.5;
  double? _brightnessDragStart;
  double _brightnessDragDelta = 0;
  bool _showBrightnessIndicator = false;
  StreamSubscription<double>? _brightnessSub;
  bool _brightnessChangedByUs = false;

  // ─────────────────────── 下滑切书签手势 ───────────────────────
  /// 下滑书签手势进行中（页面随指下移的视觉反馈）。
  bool _bookmarkSwipeActive = false;

  /// 本次下滑手势已被取消（上滑回拖到阈值之上）：松手不落盘、不移除书签。
  bool _bookmarkSwipeCancelled = false;

  /// 手势待定态：已开始但方向尚未确定（可能横向翻页误触，需方向判定）。
  bool _bookmarkSwipePending = false;

  /// 手势累计纵向位移（向下为正，px）。
  double _bookmarkSwipeDy = 0;

  /// 手势累计横向位移（方向判定用）。
  double _bookmarkSwipeDx = 0;

  /// 触发落盘所需的下滑距离（屏高比例）。
  static const double _bookmarkSwipeThresholdRatio = 0.18;

  /// 判定「主导章」时允许的顶部容差（像素）：段首滚到视口上沿附近即算
  /// 进入该章，避免浮点误差导致跨界瞬间来回抖动。
  static const double _kScrollChapterAnchorSlack = 2.0;

  /// 连排列表尾部提示项（加载中 / 全书完 / 重试）的固定高度。
  ///
  /// 固定高度有两个用途：避免状态切换时列表高度抖动；末段章内比例换算
  /// 时从内容总高里扣掉它，保证滚到章末正好 100%。
  static const double _kScrollFooterHeight = 88.0;

  /// 向下切主导章所需的「越过段首」距离（像素）。
  ///
  /// 不留死区的话，手指停在章界附近时主导章会在两章之间来回判定，
  /// 底部进度条随之在 100% / 0% 之间跳动（表现为「进度回弹」）。
  static const double _kScrollChapterHysteresis = 24.0;

  /// 判定：下滑手势（dy > 0）且纵向位移明显大于横向（absY > absX * 1.5
  /// 的通用判定比例），由亮度手势（仅左 1/3 屏生效）之外的区域触发。
  /// 滚动模式不启用——滚动本身即纵向手势，会与列表滚动冲突。
  bool get _bookmarkSwipeEnabled => !_prefs.pageAnimation.isScroll;

  // ─────────────────────── 页眉/页脚 time/battery ───────────────────────
  String _currentTime = '';
  int _batteryLevel = -1; // -1 = unknown
  late final Timer _timeTimer;
  StreamSubscription<BatteryState>? _batterySubscription;

  // ─────────────────────── 内联设置面板 ───────────────────────
  bool _showInlineSettings = false;

  // ─────────────────────── 设置搜索（常用置顶 + 过滤） ───────────────────────
  final TextEditingController _settingsSearchController =
      TextEditingController();

  // ─────────────────────── 自动翻页 ───────────────────────
  Timer? _autoPageTimer;
  bool _autoPagePaused = false;

  /// 章节加载锁：防止快速连续按上一页/下一页触发并发章节切换
  /// （导致 _currentPage 被多次设为哨兵值 -1，累加后显示为 -2/-3 等负数）。
  bool _chapterLoading = false;

  // ─────────────────────── 收藏状态 ───────────────────────
  bool _isFav = false;

  // ─────────────────────── TTS 朗读 ───────────────────────
  final NovelTtsController _tts = NovelTtsController();

  // ── 朗读通知栏控制：audio_service 会话代次与标题快照 ──────────
  /// 当前 TTS 会话的 attach 代次；null = 未挂载通知栏会话。
  int? _ttsAudioToken;

  /// 上次 attach 时的通知标题（章节/作品变化时刷新媒体条目）。
  String? _ttsAudioTitle;

  // ── 阅读中预下载后续章节 ─────────────────────────
  final NovelPreDownloader _preDownloader = NovelPreDownloader();

  /// 预下载配置快照（initState 加载；设置页修改后重进阅读器生效）。
  NovelPreDownloadPreferences _preDownloadPrefs =
      const NovelPreDownloadPreferences();

  /// 已触发过预下载的章节索引（每章只触发一次）。
  int _preDownloadTriggeredFor = -1;

  /// 本地读完自动接续在线（无缝）：防重入标志。
  bool _localToOnlineTriggered = false;

  /// 滚动模式 TTS 跟随：当前朗读段挂此 key，帧后 ensureVisible 滚到可视区。
  final GlobalKey _ttsParagraphKey = GlobalKey();

  // ─────────────────────── 笔记 ───────────────────────
  final NovelNoteManager _notes = NovelNoteManager();

  // ── 全书预扫描：章节摘要 + 全书概述（后台可续） ──────────────
  final NovelPrescanManager _prescanManager = NovelPrescanManager();
  final ValueNotifier<NovelPrescanUi> _prescanUi =
      ValueNotifier<NovelPrescanUi>(const NovelPrescanUi());

  /// 预扫描取消标记（离开阅读器 / 重开时中断当前批次，已完成章已落盘）。
  bool _prescanCancelled = false;

  MediaApiService get _service => context.read<MediaApiService>();
  SourceRepository get _repo => context.read<SourceRepository>();
  PluginConfig? get _source => _repo.getById(widget.sourceId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tts.addListener(_onTtsChanged);
    _chapterIndex = widget.initialChapterIndex;
    _prefs = const NovelReaderPreferences();
    // 读后自动删除：dispose 阶段判定「读完」用（context 已不可用，先缓存引用）。
    try {
      _downloadManager = context.read<DownloadManager>();
    } on Object {
      _downloadManager = null;
    }
    // 排除分类判定同样在 dispose 阶段使用，缓存引用。
    try {
      _favorites = context.read<FavoritesManager>();
    } on Object {
      _favorites = null;
    }
    _initBrightness();
    _initTimeAndBattery();
    _init();
    // 跨设备接续：在线书籍注册快照（本地文件对端无法重现，不参与）。
    if (!_isLocalMode && widget.sourceId.isNotEmpty) {
      _continuationToken =
          HarmonyContinuation.attach(_buildContinuationSnapshot);
    }
    // 阅读时长统计：进入阅读器即开始，dispose 时一次性结算。
    if (widget.sourceId.isNotEmpty) {
      final initialTitle = widget.chapters.isNotEmpty &&
              widget.initialChapterIndex >= 0 &&
              widget.initialChapterIndex < widget.chapters.length
          ? widget.chapters[widget.initialChapterIndex].title
          : null;
      unawaited(ReadingSessionRecorder.instance.begin(
        workId: widget.novelId,
        sourceId: widget.sourceId,
        type: StatsMediaType.novel,
        title: widget.title,
        coverUrl: widget.coverUrl,
        lastChapterTitle: initialTitle,
      ));
    }
    // 划线/笔记云同步：启动时静默拉取合并（远端新划线并入本地，
    // 并入后刷新本章渲染）；best-effort，失败不阻塞阅读。
    unawaited(
        _syncHighlightsWithCloud(refreshOnApplied: true));
  }

  /// 划线/笔记 WebDAV 同步（启动 pull 合并 / 退后台与退出 push 共用
  /// 同一「合并后上传」语义），best-effort 不阻塞阅读器。
  Future<void> _syncHighlightsWithCloud({bool refreshOnApplied = false}) async {
    try {
      final result = await NovelHighlightSyncService().syncOne(widget.novelId);
      if (refreshOnApplied && result.appliedFromRemote > 0) {
        await _reloadHighlightsForChapter();
      }
    } on Object {
      // 云同步 best-effort：失败静默。
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 应用进入后台/被回收时立即落盘当前阅读位置，避免进度丢失
    // （尤其翻章后那次落盘尚未完成即被切后台的场景）。
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _persistProgressNow();
      // 云同步增强：退后台即细粒度（逐书文件）静默上传当前进度，
      // 多端「暂停即同步」；云端领先时不覆盖（防回退），失败静默。
      unawaited(_pushProgressToCloud());
      // 划线/笔记同样退后台即同步（合并后上传，远端新增不丢）。
      unawaited(_syncHighlightsWithCloud());
    }
    // TTS 后台朗读开关：关闭时应用进入后台即暂停朗读；
    // 开启时保持朗读（wakelock_plus 已持有唤醒锁）。
    if (state == AppLifecycleState.paused &&
        !_tts.backgroundMode &&
        _tts.isPlaying) {
      _tts.pause();
      if (mounted) setState(() {});
    }
  }

  void _initTimeAndBattery() {
    _updateTime();
    _timeTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _updateTime(),
    );
    _fetchBatteryLevel();
    _batterySubscription = Battery().onBatteryStateChanged.listen(
          (_) => _fetchBatteryLevel(),
        );
  }

  void _updateTime() {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    if (mounted) setState(() => _currentTime = '$hour:$minute');
  }

  // battery_plus 6.x: BatteryState is an enum without a level field, so we
  // refetch the level via [Battery.batteryLevel] whenever the state changes.
  Future<void> _fetchBatteryLevel() async {
    try {
      final level = await Battery().batteryLevel;
      if (mounted) setState(() => _batteryLevel = level);
    } on Object {
      // Some platforms may not support battery level; leave as -1.
    }
  }

  Future<void> _initBrightness() async {
    try {
      final defaults = await ReaderDefaultSettingsStore().load();
      _brightness = defaults.novelBrightness.clamp(0.0, 1.0);
      await _brightnessPlugin.setApplicationScreenBrightness(_brightness);
    } on Object {
      _brightness = 0.5;
    }
    _brightnessSub = _brightnessPlugin.onApplicationScreenBrightnessChanged.listen(
      (double value) {
        if (!_brightnessChangedByUs && mounted) {
          setState(() => _brightness = value);
        }
        _brightnessChangedByUs = false;
      },
      onError: (Object _) {},
    );
    if (mounted) setState(() {});
  }

  Future<void> _init() async {
    final defaults = await ReaderDefaultSettingsStore().load();
    // 显式覆盖合并：只有用户单独设置过的字段覆盖全局默认，其余实时跟随总设置。
    _overrideKeys = await _store.getOverrideKeys(widget.novelId);
    _prefs = (await _store.get(widget.novelId))
        .mergedWithKeys(defaults.toNovelReaderPreferences(), _overrideKeys);
    // 迁移：自动翻页不应在进入阅读器时默认启动。
    // 之前误将默认值改为 30 导致已持久化数据残留非零值；
    // 无论具体数值是多少，一律重置为 0（关闭），由用户手动开启。
    // 仅做内存修正，不再整包落盘——旧实现会把合并结果全量写回，
    // 使所有继承字段被误判为「本书单独设置」、从此脱离总设置。
    if (_prefs.autoPageInterval > 0) {
      _prefs = _prefs.copyWith(autoPageInterval: 0);
    }
    // 音量键翻页：偏好加载完成后按需挂载原生拦截。
    unawaited(_syncVolumeKey());
    // 预下载配置加载（静态方法内部 try/catch，失败回落默认）。
    _preDownloadPrefs = await NovelPreDownloadPreferences.load();
    // 重新注册自定义字体文件（正文 / 标题），否则重启后字体不生效。
    await _loadCustomFontsIfNeeded();
    final saved = await _progress.get(widget.novelId);
    // 本地模式只有单「章」（整个文件），saved.chapterIndex 恒为 0；
    // 在线模式需校验 chapterIndex 落在 chapters 范围内。
    // restoreProgress=false 时（详情页章节列表明确点选）忽略保存值。
    if (widget.restoreProgress && saved != null) {
      // 单文件本地书（EPUB / TXT）：解析前不知道章节总数，先记住章节下标，
      // 解析完成后应用（见 _loadLocalText）；同时记住页码。
      if (_isLocalMode &&
          (widget.localEpubPath != null || widget.localTextPath != null)) {
        _restoreParsedChapterIndex = saved.chapterIndex;
        _savedPage = saved.currentPage;
        _savedCharOffset = saved.charOffset;
      } else {
        final within = saved.chapterIndex < _effectiveChapters.length;
        if (within) {
          _chapterIndex = saved.chapterIndex;
          _savedPage = saved.currentPage;
          _savedCharOffset = saved.charOffset;
        }
      }
    }
    // 跨设备接续：对端带入的页码 / 字符偏移优先于本地保存的进度
    // （本机可能没有这本书的历史进度）。
    if (widget.initialPage != null || widget.initialCharOffset != null) {
      _savedPage = widget.initialPage ?? 0;
      _savedCharOffset = widget.initialCharOffset;
    }
    _refreshFavorite();
    await _notes.init();
    if (mounted) setState(() {});
    if (_isLocalMode) {
      await _loadLocalText(
          restorePage: _savedCharOffset != null ? 0 : _savedPage);
    } else {
      await _loadChapter(
        _chapterIndex,
        restorePage: _savedCharOffset != null ? 0 : _savedPage,
      );
    }
  }

  /// 若用户选择了自定义字体文件（正文 / 标题），在启动与翻章前重新注册字族，
  /// 否则重启后字体不生效。已加载过的字族会被 [NovelReaderPreferences] 跳过。
  Future<void> _loadCustomFontsIfNeeded() async {
    if (_prefs.customFontPath != null) {
      await NovelReaderPreferences.loadCustomFont(
        NovelReaderPreferences.customLoadedFontFamily,
        _prefs.customFontPath!,
      );
    }
    if (_prefs.titleCustomFontPath != null) {
      await NovelReaderPreferences.loadCustomFont(
        NovelReaderPreferences.customLoadedTitleFontFamily,
        _prefs.titleCustomFontPath!,
      );
    }
  }

  /// 构建聚合本地模式的完整章节目录：TXT 每文件一章；EPUB 解析内部章节并按
  /// 当前排序模式展开（id 编码为 `<epubUri>|<内部索引>`）。首次加载章节前调用
  /// （[_loadLocalText] 聚合分支），构建结果缓存于 [_expandedChapters]。
  Future<void> _ensureAggregatedChapters() async {
    if (_expandedChapters != null || !_isAggregatedLocal) return;
    if (_aggBuilding) return; // 防重入
    _aggBuilding = true;
    try {
      final paths = widget.localChapterPaths!;
      // 1) 展开：txt 每文件一章；epub 拆成内部 N 章（id = '<uri>|<ci>'）。
      final all = <Episode>[];
      for (final path in paths) {
        if (path.toLowerCase().endsWith('.epub')) {
          LocalNovelBook? book = _aggEpubBooks[path];
          if (book == null) {
            final local = await resolveSafUri(path);
            final raw = await compute(_parseEpubIsolate, local);
            book = LocalNovelBook(
              title: raw[0] as String,
              author: raw[1] as String?,
              coverPath: raw[2] as String?,
              chapters: <LocalNovelChapter>[
                for (final c in raw[3] as List)
                  LocalNovelChapter(
                    title: c[0] as String,
                    content: List<String>.from(c[1] as List),
                  ),
              ],
            );
            _aggEpubBooks[path] = book;
          }
          if (book.chapters.isEmpty) {
            // 空 epub 兜底为单章（标题=文件名），避免目录缺项。
            all.add(Episode(
              id: path,
              title: _chapterTitleFor(path),
              url: '',
              number: all.length + 1,
            ));
          } else {
            for (var ci = 0; ci < book.chapters.length; ci++) {
              all.add(Episode(
                id: '$path|$ci',
                title: book.chapters[ci].title,
                url: '',
                number: all.length + 1,
              ));
            }
          }
        } else {
          // TXT 与 EPUB 同构：解析整本并按内部章节展开（TXT 目录导入章节细化
          // 「和 epub 一样」）。无内部章节的纯文本兜底为单章（标题=文件名）。
          LocalNovelBook? book = _aggTxtBooks[path];
          if (book == null) {
            final local = await resolveSafUri(path);
            // fallback 用源文件标题（而非缓存路径 basename），避免下载的正文无标题
            // 行时章节标题显示成 `saf_<hash>`（「标签变成 saf 的内容」）。
            final raw = await compute(
                _parseTxtChaptersIsolate, (local, _chapterTitleFor(path)));
            book = LocalNovelBook(
              title: _chapterTitleFor(path),
              author: null,
              coverPath: null,
              chapters: <LocalNovelChapter>[
                for (final c in raw)
                  LocalNovelChapter(
                    title: c[0] as String,
                    content: List<String>.from(c[1] as List),
                  ),
              ],
            );
            _aggTxtBooks[path] = book;
          }
          if (book.chapters.isEmpty) {
            final id = '$path#-1';
            all.add(Episode(
              id: id,
              title: _chapterTitleFor(path),
              url: '',
              number: all.length + 1,
            ));
            _aggTxtEpisodeMeta[id] = (path, -1);
          } else {
            for (var ci = 0; ci < book.chapters.length; ci++) {
              final id = '$path#$ci';
              all.add(Episode(
                id: id,
                title: book.chapters[ci].title.isEmpty
                    ? _chapterTitleFor(path)
                    : book.chapters[ci].title,
                url: '',
                number: all.length + 1,
              ));
              _aggTxtEpisodeMeta[id] = (path, ci);
            }
          }
        }
      }
      // 2) 按排序模式调整顺序。
      List<Episode> ordered;
      switch (_aggMode) {
        case _AggChapterMode.fileExpanded:
          ordered = all; // 构造顺序=文件顺序，epub 章节已在其文件位置展开
        case _AggChapterMode.epubLast:
          ordered = <Episode>[
            ...all.where((e) => !e.id.contains('|')),
            ...all.where((e) => e.id.contains('|')),
          ];
        case _AggChapterMode.collapsed:
          ordered = <Episode>[
            for (final path in paths)
              Episode(
                id: path,
                title: _chapterTitleFor(path),
                url: '',
                number: 0,
              ),
          ];
      }
      // 3) 重新编号。
      _expandedChapters = <Episode>[
        for (var i = 0; i < ordered.length; i++)
          ordered[i].copyWith(number: i + 1),
      ];
    } finally {
      _aggBuilding = false;
    }
    if (mounted) setState(() {});
  }

  /// 本地章节标题：SAF content:// 文件 URI 先还原真实文件名再去扩展名。
  String _chapterTitleFor(String path) {
    final rawName = isDocUri(path) ? safBaseName(path) : path;
    final t = p.basenameWithoutExtension(rawName);
    return t.isEmpty ? path : t;
  }

  /// 本地模式读取文件并分页（与 local_media_viewer._readTextFile 相同的读取方式）。
  ///
  /// - TXT（[localTextPath]）：整文件作为扁平段落列表。
  /// - EPUB（[localEpubPath]）：经 [LocalNovelParser.parseEpub] 解析为章节，
  /// 章节标题与正文段落统一展平为 [NovelTextBlock]，复用同一套分页/渲染路径。
  Future<void> _loadLocalText({int restorePage = 0, bool keepTts = false}) async {
    // 与 [_loadChapter] 一致：用户跳章先停朗读（TTS 自身续章传 [keepTts]）。
    if (!keepTts && _tts.state != NovelTtsState.stopped) {
      await _tts.stop();
    }
    final int token = _loadSession.next();
    if (mounted) setState(() => _loading = true);
    _stopAutoPage();
    try {
      final List<NovelBlock> blocks;
      // 聚合本地模式：按展开目录取当前章节（TXT 文件 / EPUB 内部章节）；
      // 其余本地模式取固定文件。
      String? localPath;
      var isEpub = false;
      // 聚合模式 TXT 章节：resolveSafUri 会把 localPath 覆盖为缓存路径 `saf_<hash>`,
      // 这里在覆盖前记住源文件标题，供 1047 分支做 fallback（避免标题成 saf 内容）。
      String? sourceTitle;
      if (widget.localChapterPaths != null &&
          widget.localChapterPaths!.isNotEmpty) {
        await _ensureAggregatedChapters();
        final chs = _effectiveChapters;
        if (chs.isEmpty) {
          if (!_loadSession.isValid(token)) return;
          setState(() {
            _rawParagraphs = const <NovelBlock>[];
            _paragraphs = const <NovelBlock>[];
            _loading = false;
            _error = AppLocalizations.of(context).localFileLoadFailed;
          });
          return;
        }
        final ep = chs[_chapterIndex.clamp(0, chs.length - 1)];
        final sepIdx = ep.id.indexOf('|');
        if (sepIdx >= 0) {
          // EPUB 内部章节（展开模式）：从缓存整本取该章内容直接渲染。
          final book = _aggEpubBooks[ep.id.substring(0, sepIdx)];
          final ci = int.tryParse(ep.id.substring(sepIdx + 1)) ?? 0;
          if (book == null || book.chapters.isEmpty) {
            if (!_loadSession.isValid(token)) return;
            setState(() {
              _rawParagraphs = const <NovelBlock>[];
              _paragraphs = const <NovelBlock>[];
              _loading = false;
              _error = AppLocalizations.of(context).localFileLoadFailed;
            });
            return;
          }
          final ch = book.chapters[ci.clamp(0, book.chapters.length - 1)];
          final List<NovelBlock> epubBlocks = <NovelBlock>[
            if (ch.title.isNotEmpty) NovelTextBlock(ch.title, isHeading: true),
            for (final p in ch.content)
              if (p.trim().isNotEmpty) NovelTextBlock(p),
          ];
          await _ensurePurgeRules();
          if (!_loadSession.isValid(token)) return;
          setState(() {
            _rawParagraphs = epubBlocks;
            _paragraphs = _applyConvert(epubBlocks);
            _loading = false;
            _error = null;
            _contentVersion++;
          });
          _setupControllers(restorePage: restorePage);
          return;
        }
        // TXT 内部章节（聚合目录导入，和 EPUB 一样按内部章节展开）：从缓存解析
        // 书取指定内部章节渲染；ci = -1 表示整文件（无内部章节，如 collapsed 模式），
        // 展平全部内部章节。精确字符串匹配路由，规避文件路径含分隔符的歧义。
        final txtMeta = _aggTxtEpisodeMeta[ep.id];
        if (txtMeta != null) {
          final book = _aggTxtBooks[txtMeta.$1];
          if (book == null || book.chapters.isEmpty) {
            if (!_loadSession.isValid(token)) return;
            setState(() {
              _rawParagraphs = const <NovelBlock>[];
              _paragraphs = const <NovelBlock>[];
              _loading = false;
              _error = AppLocalizations.of(context).localFileLoadFailed;
            });
            return;
          }
          final List<NovelBlock> txtBlocks;
          if (txtMeta.$2 < 0) {
            txtBlocks = <NovelBlock>[
              for (final ch in book.chapters) ...<NovelBlock>[
                if (ch.title.isNotEmpty)
                  NovelTextBlock(ch.title, isHeading: true),
                for (final p in ch.content)
                  if (p.trim().isNotEmpty)
                    p.startsWith(kNexhubImgMarker) &&
                            p
                                .substring(kNexhubImgMarker.length)
                                .trim()
                                .isNotEmpty
                        ? NovelImageBlock(
                            p.substring(kNexhubImgMarker.length).trim(),
                            source: _source,
                          )
                        : NovelTextBlock(p),
              ],
            ];
          } else {
            final ch =
                book.chapters[txtMeta.$2.clamp(0, book.chapters.length - 1)];
            txtBlocks = <NovelBlock>[
              if (ch.title.isNotEmpty)
                NovelTextBlock(ch.title, isHeading: true),
              for (final p in ch.content)
                if (p.trim().isNotEmpty)
                  p.startsWith(kNexhubImgMarker) &&
                          p.substring(kNexhubImgMarker.length).trim().isNotEmpty
                      ? NovelImageBlock(
                          p.substring(kNexhubImgMarker.length).trim(),
                          source: _source,
                        )
                      : NovelTextBlock(p),
            ];
          }
          await _ensurePurgeRules();
          if (!_loadSession.isValid(token)) return;
          setState(() {
            _rawParagraphs = txtBlocks;
            _paragraphs = _applyConvert(txtBlocks);
            _loading = false;
            _error = null;
            _contentVersion++;
          });
          _setupControllers(restorePage: restorePage);
          return;
        }
        localPath = ep.id;
        isEpub = ep.id.toLowerCase().endsWith('.epub');
        sourceTitle = _chapterTitleFor(ep.id);
      } else if (widget.localEpubPath != null) {
        localPath = widget.localEpubPath;
        isEpub = true;
      } else {
        localPath = widget.localTextPath;
      }
      // 单文件（EPUB / TXT）翻章时已缓存解析结果，无需再读文件；
      // 其余情况 SAF 落缓存再读。
      final bool singleEpub = widget.localEpubPath != null && isEpub;
      final bool singleTxt = widget.localTextPath != null && !isEpub;
      final bool localParsed =
          (singleEpub || singleTxt) && _localParsedChapters != null;
      if (!localParsed) {
        localPath = await resolveSafUri(localPath!);
      }
      if (localPath == null) return;
      if (isEpub) {
        if (singleEpub) {
          // 单 EPUB（localEpubPath）：整本解析一次并缓存，之后逐章切片，
          // 翻页/滚动只在本章内进行（与在线小说一致的阅读体验）。
          if (!localParsed) {
            // 首次打开时在独立 isolate 解析整本（bug 116）。
            final raw = await compute(_parseEpubIsolate, localPath);
            if (!mounted) return;
            final book = LocalNovelBook(
              title: raw[0] as String,
              author: raw[1] as String?,
              coverPath: raw[2] as String?,
              chapters: <LocalNovelChapter>[
                for (final c in raw[3] as List)
                  LocalNovelChapter(
                    title: c[0] as String,
                    content: List<String>.from(c[1] as List),
                  ),
              ],
            );
            if (book.chapters.isEmpty) {
              if (!_loadSession.isValid(token)) return;
              setState(() {
                _rawParagraphs = const <NovelBlock>[];
                _paragraphs = const <NovelBlock>[];
                _loading = false;
                _error = AppLocalizations.of(context).localFileLoadFailed;
              });
              return;
            }
            _localParsedChapters = book.chapters;
            _parsedChapterEpisodes = <Episode>[
              for (var ci = 0; ci < book.chapters.length; ci++)
                Episode(
                  id: '$ci',
                  title: book.chapters[ci].title,
                  url: '',
                  number: ci + 1,
                ),
            ];
            // 进度恢复：解析完成后才知道章节总数，这里应用保存的章节下标。
            final restoreIdx = _restoreParsedChapterIndex;
            if (restoreIdx != null &&
                restoreIdx >= 0 &&
                restoreIdx < _localParsedChapters!.length) {
              _chapterIndex = restoreIdx;
            }
            _restoreParsedChapterIndex = null;
          }
          final chapters = _localParsedChapters!;
          final ci = _chapterIndex.clamp(0, chapters.length - 1);
          _chapterIndex = ci;
          final ch = chapters[ci];
          blocks = <NovelBlock>[
            // 章节标题标记为 heading：渲染层用大字号+居中+加粗，一眼看到分界。
            if (ch.title.isNotEmpty) NovelTextBlock(ch.title, isHeading: true),
            for (final p in ch.content)
              if (p.trim().isNotEmpty) NovelTextBlock(p),
          ];
        } else {
          // 聚合模式里的 EPUB 文件：每个文件 = 一章，整文件解析后展平
          //（保持原行为，不缓存切片）。
          final raw = await compute(_parseEpubIsolate, localPath);
          if (!mounted || !_loadSession.isValid(token)) return;
          final book = LocalNovelBook(
            title: raw[0] as String,
            author: raw[1] as String?,
            coverPath: raw[2] as String?,
            chapters: <LocalNovelChapter>[
              for (final c in raw[3] as List)
                LocalNovelChapter(
                  title: c[0] as String,
                  content: List<String>.from(c[1] as List),
                ),
            ],
          );
          if (book.chapters.isEmpty) {
            if (!_loadSession.isValid(token)) return;
            setState(() {
              _rawParagraphs = const <NovelBlock>[];
              _paragraphs = const <NovelBlock>[];
              _loading = false;
              _error = AppLocalizations.of(context).localFileLoadFailed;
            });
            return;
          }
          blocks = <NovelBlock>[
            for (final ch in book.chapters) ...<NovelBlock>[
              if (ch.title.isNotEmpty)
                NovelTextBlock(ch.title, isHeading: true),
              for (final p in ch.content)
                if (p.trim().isNotEmpty) NovelTextBlock(p),
            ],
          ];
        }
      } else if (singleTxt) {
        // 单 TXT（localTextPath）：行级章节切分并缓存（/，段落仅以
        // 单换行分隔的文件也能正确分章），逐章切片加载，与单 EPUB 同构。
        if (!localParsed) {
          // fallback 用源文件标题（localTextPath），而非 resolveSafUri 后的缓存
          // 路径 basename——否则无标题行的 TXT 章节会显示 `saf_<hash>`。
          final raw = isPortableBookFile(widget.localTextPath!)
              ? await compute(_parsePortableIsolate, localPath)
              : await compute(_parseTxtChaptersIsolate,
                  (localPath, _chapterTitleFor(widget.localTextPath!)));
          if (!mounted) return;
          final parsed = <LocalNovelChapter>[
            for (final c in raw)
              LocalNovelChapter(
                title: c[0] as String,
                content: List<String>.from(c[1] as List),
              ),
          ];
          if (parsed.isEmpty) {
            if (!_loadSession.isValid(token)) return;
            setState(() {
              _rawParagraphs = const <NovelBlock>[];
              _paragraphs = const <NovelBlock>[];
              _loading = false;
              _error = AppLocalizations.of(context).localFileLoadFailed;
            });
            return;
          }
          _localParsedChapters = parsed;
          _parsedChapterEpisodes = <Episode>[
            for (var ci = 0; ci < parsed.length; ci++)
              Episode(
                id: '$ci',
                title: parsed[ci].title,
                url: '',
                number: ci + 1,
              ),
          ];
          // 进度恢复：解析完成后才知道章节总数，这里应用保存的章节下标。
          final restoreIdx = _restoreParsedChapterIndex;
          if (restoreIdx != null &&
              restoreIdx >= 0 &&
              restoreIdx < parsed.length) {
            _chapterIndex = restoreIdx;
          }
          _restoreParsedChapterIndex = null;
        }
        final chapters = _localParsedChapters!;
        final ci = _chapterIndex.clamp(0, chapters.length - 1);
        _chapterIndex = ci;
        final ch = chapters[ci];
        blocks = <NovelBlock>[
          if (ch.title.isNotEmpty) NovelTextBlock(ch.title, isHeading: true),
          for (final para in ch.content)
            if (para.trim().isNotEmpty)
              // 下载器占位行 → 本地插图；其余为正文段。
              para.startsWith(kNexhubImgMarker) &&
                      para.substring(kNexhubImgMarker.length).trim().isNotEmpty
                  ? NovelImageBlock(
                      para.substring(kNexhubImgMarker.length).trim(),
                      source: _source,
                    )
                  : NovelTextBlock(para),
        ];
      } else {
        // 聚合模式的 TXT 章节文件：每个文件本身即一章；为满足「和 epub 一样」
        // 的章节细化需求，文件内部仍按行级规则二次切分为子章节
        // （splitTxtChapters：仅命中「第X章/节/回/卷…」等标题才切，无标题则
        // 整文件作为单章，不会误拆单章内容），子章节标题作为 heading、插图标记
        // 转为本地插图——与 epub 聚合分支同构。大 TXT 仍放独立 isolate 解析。
        // fallback 用源文件标题（sourceTitle 已记录，覆盖前 ep.id 为源文件路径），
        // 避免章节标题显示 `saf_<hash>`（「标签变成 saf 的内容」）。
        final raw = await compute(
            _parseTxtChaptersIsolate, (localPath, sourceTitle ?? 'chapter'));
        if (!mounted || !_loadSession.isValid(token)) return;
        if (raw.isEmpty) {
          if (!_loadSession.isValid(token)) return;
          setState(() {
            _rawParagraphs = const <NovelBlock>[];
            _paragraphs = const <NovelBlock>[];
            _loading = false;
            _error = AppLocalizations.of(context).localFileLoadFailed;
          });
          return;
        }
        final chapters = <LocalNovelChapter>[
          for (final c in raw)
            LocalNovelChapter(
              title: c[0] as String,
              content: List<String>.from(c[1] as List),
            ),
        ];
        blocks = <NovelBlock>[
          for (final ch in chapters) ...<NovelBlock>[
            if (ch.title.isNotEmpty) NovelTextBlock(ch.title, isHeading: true),
            for (final para in ch.content)
              if (para.trim().isNotEmpty)
                // 下载器占位行 → 本地插图；其余为正文段。
                para.startsWith(kNexhubImgMarker) &&
                        para
                            .substring(kNexhubImgMarker.length)
                            .trim()
                            .isNotEmpty
                    ? NovelImageBlock(
                        para.substring(kNexhubImgMarker.length).trim(),
                        source: _source,
                      )
                    : NovelTextBlock(para),
          ],
        ];
      }
      await _ensurePurgeRules();
      if (!_loadSession.isValid(token)) return;
      setState(() {
        _rawParagraphs = blocks;
        _paragraphs = _applyConvert(blocks);
        _loading = false;
        _error = null;
        _contentVersion++;
      });
      _setupControllers(restorePage: restorePage);
    } on Object catch (e) {
      AppLog.instance.eWithStack(
          '[小说加载失败] ${widget.title} (epub=${widget.localEpubPath != null}, '
          'txt=${widget.localTextPath != null})',
          e);
      if (!_loadSession.isValid(token) || !mounted) return;
      setState(() {
        _isResolveError = false;
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 刷新收藏状态。
  void _refreshFavorite() {
    final fav = context.read<FavoritesManager>();
    _isFav = fav.isFavorite(widget.novelId, SourceType.novelSource);
  }

  /// 切换收藏。
  Future<void> _toggleFavorite() async {
    final l10n = AppLocalizations.of(context);
    final fav = context.read<FavoritesManager>();
    final wasFavorite = _isFav;
    final item = MediaItem(
      id: widget.novelId,
      title: widget.title,
      sourceId: widget.sourceId,
      sourceType: SourceType.novelSource,
      detailUrl: widget.detailUrl,
      coverUrl: widget.coverUrl,
    );
    await fav.toggleFavorite(item);
    if (mounted) {
      setState(() => _isFav = !wasFavorite);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(wasFavorite ? l10n.favoriteRemoved : l10n.favoriteAdded),
        ),
      );
    }
  }

  /// 收藏按钮入口：源声明网络收藏时弹「本地/网络」双选项，否则直接本地收藏。
  Future<void> _onFavoritePressed() async {
    final MediaItem item = MediaItem(
      id: widget.novelId,
      title: widget.title,
      sourceId: widget.sourceId,
      sourceType: SourceType.novelSource,
      detailUrl: widget.detailUrl,
      coverUrl: widget.coverUrl,
    );
    final PluginConfig? source =
        context.read<SourceRepository>().getById(widget.sourceId);
    if (source == null) {
      await _toggleFavorite();
      return;
    }
    await showFavoriteSheet(
      context: context,
      source: source,
      item: item,
      toggleLocalFavorite: _toggleFavorite,
    );
  }

  /// 清除当前小说的阅读进度（三点菜单入口）。
  Future<void> _clearReadingProgress() async {
    final l10n = AppLocalizations.of(context);
    await _progress.clear(widget.novelId);
    // 朗读位置一并清掉，否则「清除进度」后点朗读仍会从旧位置续读。
    await NovelTtsProgressStore.instance.clear(widget.novelId);
    if (mounted) {
      setState(() {
        _chapterIndex = 0;
        _currentPage = 0;
        _savedPage = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.readingProgressCleared)),
      );
      if (_isLocalMode) {
        await _loadLocalText();
      } else {
        await _loadChapter(_chapterIndex);
      }
    }
  }

  /// 重载当前章节（三点菜单入口）。
  Future<void> _reloadChapter() async {
    await _loadChapter(_chapterIndex);
  }

  /// 切换 TTS 朗读（三点菜单入口）。
  Future<void> _toggleTts() async {
    if (_tts.isPlaying) {
      await _tts.stop();
    } else if (_tts.isPaused) {
      await _tts.resume();
    } else {
      await _startTtsFromParagraph();
    }
    if (mounted) setState(() {});
  }

  /// 从章首起朗读（多角色上下文 + 跨章回调注入；与旧行为一致从第 0 段开始）。
  Future<void> _startTtsFromParagraph() async {
    _tts.setBackground(_prefs.ttsBackground);
    await _tts.setRate(_prefs.ttsSpeechRate);
    // 续读上次的朗读位置（同一章内才续；跨章从当前章章首开始，
    // 避免用户已经在别的章阅读却被拽回上次朗读的位置）。
    int startIndex = 0;
    try {
      if (_prefs.ttsRememberPosition) {
        final NovelTtsPosition? saved =
            await NovelTtsProgressStore.instance.get(widget.novelId);
        if (saved != null &&
            saved.chapterIndex == _chapterIndex &&
            _paragraphs.isNotEmpty) {
          startIndex = saved.paragraphIndex.clamp(0, _paragraphs.length - 1);
        }
      }
    } on Object {
      // 读取失败按章首处理。
    }
    if (!mounted) return;
    await _speakChapter(startIndex, sleepTimer: _prefs.ttsSleepTimer);
  }

  /// 朗读推进到新段落：持久化位置（退出/重进后据此续读）。
  void _onTtsProgress(int paragraphIndex) {
    if (!_prefs.ttsRememberPosition) return;
    unawaited(NovelTtsProgressStore.instance
        .save(widget.novelId, _chapterIndex, paragraphIndex));
  }

  /// 以多角色上下文朗读当前章（跨章续读复用）。
  Future<void> _speakChapter(int startIndex, {int sleepTimer = 0}) async {
    _tts.onChapterFinished = _prefs.ttsAutoNext ? _onTtsChapterFinished : null;
    _tts.onProgress = _onTtsProgress;
    await _tts.speak(
      _paragraphTexts,
      startIndex: startIndex,
      sleepTimer: sleepTimer,
      novelId: widget.novelId,
      chapterId: _currentChapterId,
      systemSlots: NovelTtsSystemSlots(
        narrator: _prefs.ttsSystemNarratorVoice,
        male: _prefs.ttsSystemMaleVoice,
        female: _prefs.ttsSystemFemaleVoice,
      ),
      autoNextChapter: _prefs.ttsAutoNext,
    );
  }

  /// 当前章 id（AI 分镜缓存键；本地无章节时为空）。
  String? get _currentChapterId {
    final chapters = _effectiveChapters;
    if (_chapterIndex < 0 || _chapterIndex >= chapters.length) return null;
    final id = chapters[_chapterIndex].id;
    return id.isEmpty ? null : id;
  }

  /// 打开「角色与声音」面板（内联设置朗读组入口）。
  Future<void> _showTtsCastSheet() async {
    await showNovelTtsCastSheet(
      context: context,
      novelId: widget.novelId,
      chapterId: _currentChapterId,
      paragraphs: _paragraphTexts,
      prefs: _prefs,
      onPrefsChanged: _onPrefsChanged,
      tts: _tts,
    );
  }

  /// 朗读章末自动续下一章（跨章连播）。
  Future<void> _onTtsChapterFinished() async {
    final chapters = _effectiveChapters;
    if (_chapterIndex >= chapters.length - 1) {
      await _tts.stop();
      return;
    }
    final int target = _chapterIndex + 1;
    // 连排缓冲里已经有下一章：直接切段续读，不重新抓取、不重建缓冲，
    // 视图随朗读继续向下滚（真正的「无缝」跨章朗读）。
    final _NovelScrollSegment? nextSeg = _segmentByChapter(target);
    if (nextSeg != null) {
      setState(() {
        _chapterIndex = target;
        _paragraphs = nextSeg.blocks;
        _rawParagraphs = nextSeg.rawBlocks;
        _pagination = null;
        _paginationSig = null;
        _currentPage = 0;
      });
      _bindSelection();
      unawaited(_reloadHighlightsForChapter());
      _saveProgress(0);
      _maybePreDownload();
      if (!mounted || _tts.state == NovelTtsState.stopped) return;
      if (_chapterIndex != target) return;
      await _speakChapter(0);
      return;
    }
    // 尚未连排：先推进章节指针再加载。`_loadChapter` 只负责取正文、不改
    // `_chapterIndex`，而控制器重建 / 进度落盘 / 朗读缓存键都以它为准。
    if (_chapterLoading) {
      // 有并发加载（用户刚跳章）：稍等一次，仍忙则停止朗读，避免状态错位。
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (_chapterLoading) {
        await _tts.stop();
        return;
      }
    }
    _chapterIndex = target;
    _currentPage = 0;
    try {
      if (_isLocalMode) {
        await _loadLocalText(keepTts: true);
      } else {
        await _loadChapter(target, keepTts: true);
      }
    } on Object {
      // 加载失败（网络等）：停止朗读，避免停在无声播放态。
      await _tts.stop();
      return;
    }
    if (!mounted || _tts.state == NovelTtsState.stopped) return;
    if (_chapterIndex != target) return; // 加载期间用户手动跳章
    await _speakChapter(0);
  }

  /// 把当前作品加入待读队列（三点菜单入口）。
  Future<void> _addCurrentToReadingQueue() async {
    final l10n = AppLocalizations.of(context);
    await ReadingQueueStore().add(QueuedReading(
      sourceType: SourceType.novelSource,
      sourceId: widget.sourceId,
      itemId: widget.novelId,
      title: widget.title,
      coverUrl: widget.coverUrl,
      detailUrl: widget.detailUrl,
      initialChapterIndex: _chapterIndex,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.readingQueueAdded)),
    );
  }

  /// 导出当前书全部划线与笔记为 Markdown 文件（临时目录），经系统分享
  /// 面板保存 / 发送（Obsidian 等笔记软件可直接导入）。按章节分组，
  /// 划线用引用块、笔记用 💭 前缀，与导出时间一起写入文件头。
  Future<void> _exportHighlightsMarkdown() async {
    final highlights = await NovelHighlightManager().listFor(widget.novelId);
    final notes = await _notes.notesForNovel(widget.novelId);
    final entries = <_MergedNoteEntry>[
      for (final n in notes)
        _MergedNoteEntry(
          chapterIndex: n.chapterIndex,
          chapterTitle: n.chapterTitle,
          quote: n.selectedText,
          note: n.note,
          createdAt: n.createdAt,
          isHighlightNote: false,
          deleteKey: n.id,
        ),
      for (final h in highlights)
        _MergedNoteEntry(
          chapterIndex: h.chapterIndex,
          chapterTitle: h.chapterTitle,
          quote: h.quote,
          note: h.note ?? '',
          createdAt: h.createdAt,
          isHighlightNote: true,
          deleteKey: h.key,
        ),
    ]..sort((a, b) {
        final byChapter = a.chapterIndex.compareTo(b.chapterIndex);
        return byChapter != 0 ? byChapter : a.createdAt.compareTo(b.createdAt);
      });
    final l10n = AppLocalizations.of(context);
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.highlightEmpty)),
      );
      return;
    }
    final now = DateTime.now();
    final buf = StringBuffer()
      ..writeln('# 《${widget.title}》划线笔记')
      ..writeln()
      ..writeln('> NexHub 导出于 ${now.year}-${_pad(now.month)}-'
          '${_pad(now.day)} · 共 ${entries.length} 条')
      ..writeln();
    var lastChapter = -1;
    for (final e in entries) {
      if (e.chapterIndex != lastChapter) {
        lastChapter = e.chapterIndex;
        buf
          ..writeln('## ${l10n.chapterN(e.chapterIndex + 1)} · '
              '${e.chapterTitle}')
          ..writeln();
      }
      if (e.quote.isNotEmpty) {
        for (final line in e.quote.split('\n')) {
          buf.writeln('> $line');
        }
        buf.writeln();
      }
      if (e.note.isNotEmpty) {
        buf
          ..writeln('${e.isHighlightNote ? '💭' : '📝'} ${e.note}')
          ..writeln();
      }
    }
    final safeTitle = widget.title.replaceAll(RegExp(r'[\\/:*?"<>|\r\n]'), '_');
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path,
        'nexhub_notes_${now.millisecondsSinceEpoch}.md'));
    await file.writeAsString(buf.toString(), flush: true);
    if (!mounted) return;
    await Share.shareXFiles(
      <XFile>[
        XFile(
          file.path,
          mimeType: 'text/markdown',
          name: '《$safeTitle》划线笔记-'
              '${now.year}${_pad(now.month)}${_pad(now.day)}.md',
        ),
      ],
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.notesExported(entries.length))),
    );
  }

  /// 笔记 / 标记列表弹窗顶部标题栏（右侧为 Markdown 导出入口）。
  Widget _buildNotesSheetHeader(AppLocalizations l10n, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.file_download_outlined, size: 18),
            label: Text(l10n.notesExport),
            onPressed: _exportHighlightsMarkdown,
          ),
        ],
      ),
    );
  }

  /// 显示笔记列表（三点菜单），包含独立笔记与划线摘录笔记。
  Future<void> _showNoteList() async {
    final notes = await _notes.notesForNovel(widget.novelId);
    final highlights = await NovelHighlightManager().listFor(widget.novelId);
    final highlightNotes =
        highlights.where((h) => h.note != null && h.note!.isNotEmpty).toList();
    final merged = <_MergedNoteEntry>[
      for (final n in notes)
        _MergedNoteEntry(
          chapterIndex: n.chapterIndex,
          chapterTitle: n.chapterTitle,
          quote: n.selectedText,
          note: n.note,
          createdAt: n.createdAt,
          isHighlightNote: false,
          deleteKey: n.id,
        ),
      for (final h in highlightNotes)
        _MergedNoteEntry(
          chapterIndex: h.chapterIndex,
          chapterTitle: h.chapterTitle,
          quote: h.quote,
          note: h.note!,
          createdAt: h.createdAt,
          isHighlightNote: true,
          deleteKey: h.key,
        ),
    ];
    merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85),
            child: merged.isEmpty
                ? Center(child: Text(l10n.noNotes))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _buildNotesSheetHeader(l10n, l10n.notesSheetTitle),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: merged.length,
                          itemBuilder: (_, i) {
                      final entry = merged[i];
                      return ListTile(
                        leading: Icon(
                          entry.isHighlightNote
                              ? Icons.highlight_alt_rounded
                              : Icons.notes_rounded,
                          size: 20,
                          color: entry.isHighlightNote
                              ? Theme.of(ctx).colorScheme.primary
                              : null,
                        ),
                        title: Text(
                          '${l10n.chapterN(entry.chapterIndex + 1)} · ${entry.chapterTitle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                if (entry.quote.isNotEmpty)
                                  Expanded(
                                    child: Text(
                                      entry.quote,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(ctx)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ),
                                Text(
                                  _formatTimestamp(entry.createdAt),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(ctx)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.4),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              entry.note,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            IconButton(
                              icon:
                                  const Icon(Icons.edit_note_rounded, size: 20),
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                if (entry.isHighlightNote) {
                                  // 划线笔记：通过 highlight key 查找并编辑
                                  NovelHighlightManager()
                                      .getByKey(entry.deleteKey)
                                      .then((hl) {
                                    if (hl != null && mounted)
                                      _editHighlightNote(hl);
                                  });
                                } else {
                                  // 独立笔记：暂不支持编辑（可删除后重建）
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            AppLocalizations.of(context)
                                                .noteEditUnsupported)),
                                  );
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_rounded, size: 20),
                              onPressed: () {
                                if (entry.isHighlightNote) {
                                  NovelHighlightManager()
                                      .remove(entry.deleteKey);
                                } else {
                                  _notes.removeNote(entry.deleteKey);
                                }
                                Navigator.of(ctx).pop();
                                _showNoteList();
                              },
                            ),
                          ],
                        ),
                        onTap: () {
                          if (entry.chapterIndex != _chapterIndex) {
                            _chapterIndex = entry.chapterIndex;
                            _loadChapter(_chapterIndex);
                          }
                          Navigator.of(ctx).pop();
                        },
                      );
                        },
                      ),
                        ),
                    ],
                  ),
              ),
        );
      },
    );
  }

  /// 显示标记列表（划线列表），支持查看、编辑笔记、删除、跳转
  /// （Phase 2 /，参照 [_showNoteList] 模式）。
  /// 同章+同引文+同效果的标记自动合并（保留最新颜色和笔记）。
  Future<void> _showHighlightList() async {
    final highlights = await NovelHighlightManager().listFor(widget.novelId);
    // 合并：同章+同引文+同效果 → 保留最新的一条
    final merged = <String, NovelHighlight>{};
    for (final h in highlights) {
      final key = '${h.chapterIndex}::${h.quote}::${h.effect}';
      final existing = merged[key];
      if (existing == null || h.createdAt > existing.createdAt) {
        merged[key] = h;
      }
    }
    final list = merged.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            ),
            child: list.isEmpty
                ? Center(child: Text(l10n.highlightEmpty))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _buildNotesSheetHeader(l10n, l10n.highlightList),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                      final h = list[i];
                      final swatch = Color(h.color);
                      final isUnderline = h.effect != 'bg';
                      return ListTile(
                        leading: isUnderline
                            ? Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: swatch.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Icon(
                                  Icons.format_underline_rounded,
                                  size: 16,
                                  color: swatch,
                                ),
                              )
                            : Container(
                                width: 4,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: swatch,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                        title: Text(
                          '${l10n.chapterN(h.chapterIndex + 1)} · ${h.chapterTitle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              h.quote,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (h.note != null && h.note!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  h.note!,
                                  maxLines: 5,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontStyle: FontStyle.italic,
                                    color: Theme.of(ctx)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.7),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            IconButton(
                              icon: const Icon(Icons.edit_note_rounded),
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                _editHighlightNote(h);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_rounded),
                              onPressed: () async {
                                await NovelHighlightManager().remove(h.key);
                                if (!mounted) return;
                                Navigator.of(ctx).pop();
                                _showHighlightList();
                              },
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          if (h.chapterIndex != _chapterIndex) {
                            _chapterIndex = h.chapterIndex;
                            _loadChapter(_chapterIndex);
                          }
                          // 使用搜索关键词跳转到选中文本位置
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              _searchKeyword = h.quote;
                              _searchRegex = null;
                              _startSearchHighlightTimer();
                              // 在分页模式下尝试跳转到包含引文的页面
                              if (!_prefs.pageAnimation.isScroll &&
                                  _pagination != null) {
                                _jumpToQuote(h.quote);
                              }
                            }
                          });
                        },
                      );
                        },
                      ),
                        ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  /// 编辑单条划线的笔记（Phase 2 / 摘录）。
  Future<void> _editHighlightNote(NovelHighlight hl) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: hl.note ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.highlightEditNote),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                hl.quote,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: l10n.highlightNoteHint,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(l10n.highlightSave),
          ),
        ],
      ),
    );
    if (result == null) return;
    await NovelHighlightManager().update(key: hl.key, note: result);
    await _reloadHighlightsForChapter();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.highlightSave)),
      );
    }
  }

  /// 滚动模式正文是否处于 TTS 朗读态（TTS 态不拦截长按选区）。
  bool _ttsActiveForBody() => _tts.state != NovelTtsState.stopped;

  /// 滚动模式长按起始：选中整块（章节全局偏移范围）。
  ///
  /// 块为整段多行文本，精确折行 x 命中留待后续；先满足「滚动模式可划线」。
  void _onSelLongPressStartScroll(int blockIndex, String text) {
    // MD3「Thunk」：长按开始文本选择。
    AppHaptics.thunk();
    _longPressEngaged = true;
    final start = _selectionController.globalOffsetForBlock(
      _paragraphs,
      blockIndex,
      0,
    );
    final end = start + text.length;
    _selectionController.setSelecting(true);
    _selectionController.setSelectionAnchor(start);
    _selectionController.setSelection(start, end);
  }

  /// 滚动模式长按结束：解除选区激活；有选区则显示工具条。
  void _onSelLongPressEndScroll() {
    _longPressEngaged = false;
    _selectionController.setSelecting(false);
    _selectionController.setSelectionAnchor(null);
    if (_selectionController.hasSelection && mounted) {
      _selectionJustConfirmedAt = DateTime.now();
      setState(() => _showSelectionToolbar = true);
    }
  }

  @override
  void dispose() {
    // 跨设备接续：退场后本页不再作为接续来源。
    final Object? continuationToken = _continuationToken;
    if (continuationToken != null) {
      _continuationToken = null;
      HarmonyContinuation.detach(continuationToken);
    }
    // 离开阅读器中断预扫描（已完成章节已逐批落盘，重进可续扫）。
    _prescanCancelled = true;
    _prescanUi.dispose();
    // 退出阅读器前兜底落盘当前阅读位置（不依赖 context，见 _persistProgressNow）。
    // 进度此前仅在阅读中写入，若翻章后的那次落盘尚未完成即被 pop，重进会
    // 回放上一章末页；此处保证最后所在页/章被持久化。
    _persistProgressNow();
    // 退出时把当前书进度静默上传到 WebDAV（best-effort；未配置/
    // 网络失败/云端领先均静默忽略，不阻塞退出）。
    unawaited(_pushProgressToCloud());
    // 划线/笔记退出时同样静默同步（与进度同点位）。
    unawaited(_syncHighlightsWithCloud());
    // 退出时一次性结算本次阅读会话（commit 内部 best-effort）。
    if (widget.sourceId.isNotEmpty) {
      unawaited(ReadingSessionRecorder.instance.commit(
        workId: widget.novelId,
        sourceId: widget.sourceId,
        type: StatsMediaType.novel,
        title: widget.title,
        coverUrl: widget.coverUrl,
        source: SessionSource.novelReader,
      ));
    }
    // 读后自动删除：读完（进度到最后一章）时清理该内容已下载文件。
    unawaited(_maybeAutoDeleteDownloaded());
    WidgetsBinding.instance.removeObserver(this);
    // 音量键翻页：退出阅读器恢复系统默认音量键行为。
    unawaited(_volumeKeyListener.stop());
    _timeTimer.cancel();
    _batterySubscription?.cancel();
    _autoPageTimer?.cancel();
    _scrollController?.dispose();
    _brightnessSub?.cancel();
    // 异步方法，异常在后续微任务抛出，同步 try/catch 抓不到；用 .catchError 兜底，
    // 避免「Uncaught zone error」在 release 下升级为进程崩溃。
    _brightnessPlugin.resetApplicationScreenBrightness().catchError((Object _) {});
    _tts.removeListener(_onTtsChanged);
    // 退出阅读器释放通知栏媒体会话（若朗读仍在后台，系统通知随之移除）。
    if (_ttsAudioToken != null) {
      AudioPlaybackService.instance.detach(_ttsAudioToken!);
      _ttsAudioToken = null;
      _ttsAudioTitle = null;
    }
    _tts.dispose();
    _settingsSearchController.dispose();
    _searchHighlightTimer?.cancel();
    super.dispose();
  }

  /// 读完自动删除（小说版）：最后一章已读且设置开启时清理下载。
  Future<void> _maybeAutoDeleteDownloaded() async {
    try {
      final dm = _downloadManager;
      if (dm == null || !dm.settings.autoDeleteAfterRead) return;
      final groupIds = _favorites?.groupIdsOf(
            widget.novelId,
            SourceType.novelSource,
          ) ??
          const <String>[];
      if (dm.settings.isExcludedFromAutoDeleteGroups(groupIds)) return;
      final p = await _progress.get(widget.novelId);
      if (p == null || p.totalChapters == null) return;
      if (p.chapterIndex + 1 < p.totalChapters!) return;
      await dm.removeItemDownloads(widget.novelId, deleteFiles: true);
    } on Object {
      // best-effort。
    }
  }

  // ─────────────────────── 自动翻页 ───────────────────────

  /// 是否启用了自动翻页（间隔 > 0 即视为启用）。
  bool get _autoPageEnabled => _prefs.autoPageInterval > 0;

  /// 根据当前偏好与暂停状态启停定时器。
  void _applyAutoPage() {
    _autoPageTimer?.cancel();
    _autoPageTimer = null;
    if (!_autoPageEnabled || _autoPagePaused) return;
    if (_paragraphs.isEmpty) return;
    final interval = _prefs.autoPageInterval;
    if (_prefs.autoPageSmooth) {
      // 像素级平滑：50ms 一帧按比例推进，一整页耗时 = interval 秒。
      // 滚动模式直接推进滚动像素；翻页模式驱动过渡进度（advanceAutoPage）。
      const int tickMs = 50;
      final double deltaPerTick = tickMs / (interval * 1000);
      _autoPageTimer = Timer.periodic(
        const Duration(milliseconds: tickMs),
        (_) => _autoPageTick(deltaPerTick),
      );
    } else {
      _autoPageTimer = Timer.periodic(
        Duration(seconds: interval),
        (_) => _goNextPage(),
      );
    }
  }

  /// 平滑自动翻页单帧推进。
  void _autoPageTick(double delta) {
    if (_loading || _chapterLoading || !_autoPageEnabled || _autoPagePaused) {
      return;
    }
    if (_prefs.pageAnimation.isScroll) {
      final sc = _scrollController;
      if (sc == null || !sc.hasClients) return;
      final pos = sc.position;
      if (pos.maxScrollExtent <= 0) return;
      if (sc.offset >= pos.maxScrollExtent - 0.5) {
        // 已到本章底：进入下一章（切章会按项目约束停止自动翻页）。
        _goNextChapter();
        return;
      }
      final double px = pos.viewportDimension * delta;
      sc.jumpTo(
        (sc.offset + px).clamp(0.0, pos.maxScrollExtent).toDouble(),
      );
      return;
    }
    _pageKey.currentState?.advanceAutoPage(delta);
  }

  /// 完全停止自动翻页（切章 / dispose 时调用）。
  void _stopAutoPage() {
    _autoPageTimer?.cancel();
    _autoPageTimer = null;
  }

  /// 暂停 / 恢复自动翻页（运行时切换，不影响偏好）。
  void _toggleAutoPagePause() {
    setState(() => _autoPagePaused = !_autoPagePaused);
    if (_autoPagePaused) {
      // 平滑模式下中止半程过渡，避免停留在过渡画面。
      _pageKey.currentState?.cancelAutoTurn();
    }
    _applyAutoPage();
  }

  // ─────────────────────── 书签 ───────────────────────

  /// 在当前章节+页添加书签（可附带备注）。
  Future<void> _addBookmark() async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    // 本地模式无 chapters，用占位 chapterId/title 保存书签。
    // 单 EPUB（已解析出章节）按真实章节记录，目录跳回书签可精确定位。
    final String chapterId;
    final String chapterTitle;
    final String chapterLabel;
    final chapters = _effectiveChapters;
    if (_isLocalMode && _parsedChapterEpisodes == null) {
      chapterId = 'local';
      chapterTitle = '';
      chapterLabel = l10n.localFileLabel;
    } else {
      if (chapters.isEmpty) return;
      final chapter = chapters[_chapterIndex.clamp(0, chapters.length - 1)];
      chapterId = chapter.id;
      chapterTitle = chapter.title;
      chapterLabel = l10n.novelChapterProgress(
        chapter.number ?? (_chapterIndex + 1),
        chapters.length,
      );
    }
    final TextEditingController noteCtl = TextEditingController();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AppAlertDialog(
          title: Text(l10n.addBookmark),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                chapterLabel,
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: AppTokens.spaceSm),
              TextField(
                controller: noteCtl,
                decoration: InputDecoration(
                  labelText: l10n.bookmarkNoteHint,
                  hintText: l10n.bookmarkNoteHint,
                  border: const OutlineInputBorder(),
                ),
                maxLines: 3,
                textInputAction: TextInputAction.done,
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.confirm),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      noteCtl.dispose();
      return;
    }
    final String note = noteCtl.text.trim();
    noteCtl.dispose();
    final bm = NovelBookmark(
      novelId: widget.novelId,
      chapterIndex: _chapterIndex,
      chapterId: chapterId,
      chapterTitle: chapterTitle,
      page: _currentPage,
      note: note.isEmpty ? null : note,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _bookmarks.add(bm);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.bookmarkAdded)),
    );
  }

  /// 打开书签列表 sheet；选中后跳转，长按删除。
  Future<void> _showBookmarkList() async {
    final list = await _bookmarks.listFor(widget.novelId);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.noBookmarks)),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceMd,
                    vertical: AppTokens.spaceSm,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l10n.bookmarkList,
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (BuildContext c, int i) {
                      final bm = list[i];
                      final String pageSub = l10n.pageIndicator(
                          bm.page + 1, _pagination?.pages.length ?? 1);
                      final List<String> subParts = <String>[pageSub];
                      if (bm.note != null && bm.note!.isNotEmpty) {
                        subParts.add(bm.note!);
                      }
                      return ListTile(
                        leading: _buildBookmarkLeading(bm),
                        title: Text(bm.chapterTitle.isEmpty
                            ? l10n.novelChapterN(bm.chapterIndex + 1)
                            : bm.chapterTitle),
                        subtitle: Text(
                          subParts.join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_rounded),
                          tooltip: l10n.deleteBookmark,
                          onPressed: () async {
                            await _bookmarks.remove(bm.key);
                            if (!ctx.mounted) return;
                            Navigator.of(ctx).pop();
                            _showBookmarkList();
                          },
                        ),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _jumpToBookmark(bm);
                        },
                        // 长按弹出角标图操作（自定义 / 恢复默认）。
                        onLongPress: () => _showBadgeActions(ctx, bm),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 书签列表角标：自定义图优先，加载失败/未设置回退默认图标。
  Widget _buildBookmarkLeading(NovelBookmark bm) {
    final path = bm.iconPath;
    if (path == null || path.isEmpty) return const Icon(Icons.bookmark_rounded);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      child: Image.file(
        File(path),
        width: 28,
        height: 28,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.bookmark_rounded),
      ),
    );
  }

  /// 角标图操作菜单：自定义 / 恢复默认；操作完成后刷新列表。
  Future<void> _showBadgeActions(
      BuildContext sheetCtx, NovelBookmark bm) async {
    // MD3「Thunk」：长按呼出书签操作菜单。
    AppHaptics.thunk();
    final l10n = AppLocalizations.of(sheetCtx);
    final String? action = await showModalBottomSheet<String>(
      context: sheetCtx,
      builder: (BuildContext c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.image_rounded),
              title: Text(l10n.bookmarkBadgeCustom),
              onTap: () => Navigator.of(c).pop('custom'),
            ),
            if (bm.iconPath != null && bm.iconPath!.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.refresh_rounded),
                title: Text(l10n.bookmarkBadgeReset),
                onTap: () => Navigator.of(c).pop('reset'),
              ),
          ],
        ),
      ),
    );
    if (action == null) return;
    if (action == 'custom') {
      await _pickBadgeImage(bm);
    } else if (action == 'reset') {
      await _bookmarks.setBadge(bm.key, null);
    }
    // 刷新书签列表（与删除后的重建流程一致）。
    if (!mounted) return;
    _showBookmarkList();
  }

  /// 选图并复制到应用目录后设为书签角标。取消选图为无操作。
  Future<void> _pickBadgeImage(NovelBookmark bm) async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      final path = result?.files.single.path;
      if (path == null || path.isEmpty) return;
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'novel_badges'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final dest = p.join(dir.path,
          '${DateTime.now().millisecondsSinceEpoch}${p.extension(path)}');
      await File(path).copy(dest);
      await _bookmarks.setBadge(bm.key, dest);
    } on Object {
      // 选图 / 复制失败静默忽略
    }
  }

  /// 跳转到指定书签。
  void _jumpToBookmark(NovelBookmark bm) {
    // 本地模式只有单「章」，chapterIndex 恒为 0；仅校验非负即可。
    if (_isLocalMode) {
      if (bm.chapterIndex < 0) return;
      if (_prefs.pageAnimation.isScroll) {
        final sc = _scrollController;
        if (sc != null && sc.hasClients) {
          final h = sc.position.viewportDimension;
          sc.jumpTo((bm.page * h).clamp(0.0, sc.position.maxScrollExtent));
        }
      } else {
        _pageKey.currentState?.jumpToPage(bm.page);
      }
      setState(() => _currentPage = bm.page);
      return;
    }
    if (bm.chapterIndex < 0 || bm.chapterIndex >= widget.chapters.length) {
      return;
    }
    if (bm.chapterIndex == _chapterIndex) {
      // 同章节：仅切页。
      if (_prefs.pageAnimation.isScroll) {
        final sc = _scrollController;
        if (sc != null && sc.hasClients) {
          final h = sc.position.viewportDimension;
          sc.jumpTo((bm.page * h).clamp(0.0, sc.position.maxScrollExtent));
        }
      } else {
        _pageKey.currentState?.jumpToPage(bm.page);
      }
      setState(() => _currentPage = bm.page);
      return;
    }
    _chapterIndex = bm.chapterIndex;
    _loadChapter(_chapterIndex, restorePage: bm.page);
  }

  /// 段落翻译：双语对照面板（缓存优先展示，可整章翻译并持久化）。
  Future<void> _showTranslationSheet() async {
    final paragraphs = <String>[
      for (final b in _paragraphs)
        if (b is NovelTextBlock && !b.isHeading && b.text.trim().isNotEmpty)
          b.text,
    ];
    final chapter = widget.chapters[_chapterIndex];
    // 目标语言取自翻译配置页（NovelSummarySettings）。
    final targetLang =
        await NovelSummarySettings.instance.getTranslationTargetLanguage();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NovelTranslationSheet(
        novelId: widget.novelId,
        chapterId: chapter.id,
        chapterTitle: chapter.title,
        chapterIndex: _chapterIndex,
        paragraphs: paragraphs,
        targetLanguage: targetLang,
        previousChapterId:
            _chapterIndex > 0 ? widget.chapters[_chapterIndex - 1].id : null,
        manager: NovelTranslationManager(),
        prescanManager: _prescanManager,
        prescanUi: _prescanUi,
        onStartPrescan: _startPrescan,
      ),
    );
    if (mounted) setState(() {});
  }

  /// 全书预扫描：对每章开头生成 1–2 句摘要，全部完成后汇总全书概述。
  ///
  /// 按批落盘（断点续扫）：离开阅读器 / 再次进入后重开即从缺摘要章节继续；
  /// 作品更新（章节列表变化）时按 chapterId 保留仍有效的摘要、概述重算。
  Future<void> _startPrescan() async {
    if (_prescanUi.value.running) return;
    final source = _source;
    if (source == null) return;
    final lang =
        await NovelSummarySettings.instance.getTranslationTargetLanguage();
    final cfg = await NovelSummarySettings.instance.getTranslationConfig();
    if (cfg.baseUrl.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context).novelTranslateNoApi)),
        );
      }
      return;
    }
    _prescanCancelled = false;
    _prescanUi.value = NovelPrescanUi(
      running: true,
      done: 0,
      total: widget.chapters.length,
      ready: _prescanUi.value.ready,
    );
    try {
      await _prescanManager.init();
      final existing = await _prescanManager.load(widget.novelId, lang: lang);
      NovelPrescanData data = existing != null
          ? _prescanManager.mergeWithCurrentChapters(
              existing: existing,
              novelTitle: widget.title,
              currentChapters: <({String id, String title})>[
                for (final c in widget.chapters) (id: c.id, title: c.title),
              ],
            )
          : NovelPrescanData(
              novelId: widget.novelId,
              lang: lang,
              novelTitle: widget.title,
              chapters: const <NovelPrescanChapterSummary>[],
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            );
      await _prescanManager.save(data);
      final summarizer = NovelPrescanService();
      final pending = <Episode>[
        for (final c in widget.chapters)
          if (data.summaryFor(c.id) == null) c,
      ];
      for (var i = 0;
          i < pending.length;
          i += NovelPrescanService.chaptersPerBatch) {
        if (_prescanCancelled || !mounted) return;
        final end =
            (i + NovelPrescanService.chaptersPerBatch).clamp(0, pending.length);
        final batch = pending.sublist(i, end);
        final inputs = <PrescanChapterInput>[];
        for (final c in batch) {
          final head = await _loadChapterHead(c, source);
          inputs.add(
              PrescanChapterInput(chapterId: c.id, title: c.title, head: head));
        }
        try {
          final summaries = await summarizer.summarizeChapters(
            cfg: cfg,
            lang: lang,
            items: inputs,
          );
          data = data.copyWith(
            chapters: <NovelPrescanChapterSummary>[
              ...data.chapters,
              for (var k = 0; k < batch.length; k++)
                NovelPrescanChapterSummary(
                  chapterId: batch[k].id,
                  title: batch[k].title,
                  summary: summaries[k],
                ),
            ],
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          );
          // 逐批落盘——中断后从缺摘要章节续扫。
          await _prescanManager.save(data);
        } on Object catch (e) {
          AppLog.instance.w('[预扫描] 批量摘要失败，已保留已完成章节: $e');
          _prescanUi.value = _prescanUi.value.copyWithRunning(false);
          return;
        }
        _prescanUi.value = _prescanUi.value.copyWith(
          done: data.chapters.length,
          total: widget.chapters.length,
        );
      }
      // 章节摘要齐了 → 生成全书概述。
      if (data.overview == null && data.chapters.isNotEmpty) {
        final overview = await summarizer.bookOverview(
          cfg: cfg,
          lang: lang,
          novelTitle: widget.title,
          chapterSummaries: <String>[
            for (final c in data.chapters) c.summary,
          ],
        );
        data = data.copyWith(
          overview: overview,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        await _prescanManager.save(data);
      }
      _prescanUi.value = NovelPrescanUi(
        running: false,
        done: data.chapters.length,
        total: widget.chapters.length,
        ready: data.overview != null,
      );
    } on Object catch (e) {
      AppLog.instance.w('[预扫描] 失败: $e');
      _prescanUi.value = _prescanUi.value.copyWithRunning(false);
    }
  }

  /// 取一章开头片段（优先预下载缓存，失败返回空串——摘要退化为仅依据章节名）。
  Future<String> _loadChapterHead(Episode chapter, PluginConfig source) async {
    try {
      final List<NovelBlock>? cached =
          await _preDownloader.cached(widget.novelId, chapter.id);
      final List<NovelBlock> blocks = cached ??
          await _service.fetchNovelContent(
            source,
            novelId: widget.novelId,
            chapterUrl: chapter.url,
          );
      final buf = StringBuffer();
      for (final b in blocks) {
        if (b is NovelTextBlock && !b.isHeading && b.text.trim().isNotEmpty) {
          buf.writeln(b.text.trim());
          if (buf.length >= 400) break;
        }
      }
      final s = buf.toString().trim();
      return s.length > 400 ? s.substring(0, 400) : s;
    } on Object {
      return '';
    }
  }

  /// AI 章节配图：云端生成一张本章插图，落盘后以插图占位行追加进
  /// 内容编辑记录并重载（图文混排显示；重复生成覆盖旧图）。
  Future<void> _generateAiIllustration() async {
    final l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(l10n.novelAiIllustrate),
        content: Text(l10n.novelAiIllustrateConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.novelAiIllustrating)),
    );
    try {
      final chapter = widget.chapters[_chapterIndex];
      final excerpt = <String>[
        for (final b in _rawParagraphs)
          if (b is NovelTextBlock && b.text.trim().isNotEmpty) b.text,
      ].join('\n');
      final path = await NovelIllustrationService().generateAndSave(
        novelId: widget.novelId,
        chapterId: chapter.id,
        chapterTitle: chapter.title,
        excerpt: excerpt,
      );
      // 追加到内容编辑记录（无编辑则从当前原文初始化），复用 覆盖管线。
      final existing = await _contentEdits.load(widget.novelId, chapter.id);
      final baseText = NovelContentEditManager.encodeBlocksToEditableText(
        existing?.blocks ?? _rawParagraphs,
      );
      final newText =
          '$baseText\n\n${NovelIllustrationService.markerLineFor(path)}';
      await _contentEdits.save(NovelContentEdit(
        novelId: widget.novelId,
        chapterId: chapter.id,
        chapterIndex: _chapterIndex,
        chapterTitle: chapter.title,
        blocks: NovelContentEditManager.parseEditableText(newText),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.novelAiIllustrateDone)),
      );
      unawaited(_loadChapter(_chapterIndex, restorePage: _currentPage));
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.novelAiIllustrateFailed}: $e')),
      );
    }
  }

  // ─────────────────────── 数据加载 ───────────────────────

  /// 内容编辑：若本章存在读者编辑记录则返回编辑块列表（并置已编辑标记），
  /// 否则原样返回抓取结果。
  Future<List<NovelBlock>> _applyContentEditOverride(
    String chapterId,
    List<NovelBlock> fetched,
  ) async {
    try {
      final edit = await _contentEdits.load(widget.novelId, chapterId);
      final bool edited = edit != null && edit.blocks.isNotEmpty;
      if (mounted && edited != _currentChapterEdited) {
        setState(() => _currentChapterEdited = edited);
      }
      return edited ? edit!.blocks : fetched;
    } on Object {
      // 编辑数据损坏时按无编辑处理，不影响正常阅读。
      return fetched;
    }
  }

  /// 内容编辑：弹出整章正文编辑框。图片块以 `@@NEXHUB_IMG@@url` 占位行、
  /// 标题块以 `@@NEXHUB_TITLE@@` 前缀行呈现；保存后按「整章覆盖」语义落盘
  /// （Hive `novel_content_edits`），随后重载本章使编辑生效。
  Future<void> _showContentEditor() async {
    final l10n = AppLocalizations.of(context);
    final String? editedText = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => _NovelContentEditDialog(
        initialText:
            NovelContentEditManager.encodeBlocksToEditableText(_rawParagraphs),
        hintText: l10n.novelContentEditHint,
      ),
    );
    if (editedText == null || !mounted) return;

    final List<NovelBlock> blocks =
        NovelContentEditManager.parseEditableText(editedText);
    if (blocks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.novelContentEditEmpty)),
      );
      return;
    }
    final chapter = widget.chapters[_chapterIndex];
    await _contentEdits.save(
      NovelContentEdit(
        novelId: widget.novelId,
        chapterId: chapter.id,
        chapterIndex: _chapterIndex,
        chapterTitle: chapter.title,
        blocks: blocks,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.novelContentEditSaved)),
    );
    await _loadChapter(_chapterIndex, restorePage: _currentPage);
  }

  /// 内容编辑：移除本章的编辑记录并重载（恢复源站原文）。
  Future<void> _restoreOriginalContent() async {
    final l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(l10n.novelContentEditRestore),
        content: Text(l10n.novelContentEditRestoreConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _contentEdits.remove(
        widget.novelId, widget.chapters[_chapterIndex].id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.novelContentEditRestored)),
    );
    await _loadChapter(_chapterIndex, restorePage: _currentPage);
  }

  Future<void> _loadChapter(int index,
      {int restorePage = 0, bool keepTts = false}) async {
    // 防并发：章节加载期间忽略新的切章请求（快速连按上一页/下一页时）。
    if (_chapterLoading) return;
    _chapterLoading = true;
    // 用户跳章（目录 / 书签 / 搜索 / 上一章下一章）：先停朗读再加载，
    // 否则旧章的朗读会一直念到章末（听感像「跳转后还在念上一章」）。
    // TTS 自身跨章续读传 [keepTts] 跳过。
    if (!keepTts && _tts.state != NovelTtsState.stopped) {
      await _tts.stop();
    }
    if (mounted) setState(() => _loading = true);
    // 切换章节时必须取消自动翻页定时器（项目约束）。
    _stopAutoPage();
    try {
      final source = _repo.getById(widget.sourceId);
      if (source == null)
        throw Exception('source not found: ${widget.sourceId}');
      final chapter = widget.chapters[index];
      final List<NovelBlock> paragraphs;
      // 命中预下载缓存（离线/已预取章节）则跳过网络抓取，直接渲染。
      final List<NovelBlock>? cached =
          await _preDownloader.cached(widget.novelId, chapter.id);
      if (cached != null) {
        paragraphs = cached;
      } else {
        paragraphs = await _service.fetchNovelContent(
          source,
          novelId: widget.novelId,
          chapterUrl: chapter.url,
        );
      }
      if (!mounted) {
        _chapterLoading = false;
        return;
      }
      // 内容编辑：本章存在读者编辑记录时以编辑块整体覆盖抓取结果
      // （替换规则 / 繁简转换仍在其后照常应用）。
      final List<NovelBlock> effective =
          await _applyContentEditOverride(chapter.id, paragraphs);
      // 加载净化规则（全局一套；首次打开时把旧版书籍级规则迁移过来）+ 本书开关。
      await _ensurePurgeRules(refresh: true);
      _highlightRuleSet =
          await NovelRuleCache().getHighlightRules(widget.novelId);
      setState(() {
        _rawParagraphs = effective;
        _paragraphs = _applyConvert(effective);
        _loading = false;
        _error = null;
        _verificationError = null;
        _contentVersion++;
      });
      _setupControllers(restorePage: restorePage);
      // 章节加载完成、分页就绪后检查一次预下载（单页章 / 直达章末场景，
      // 不依赖用户翻页也能触发；postFrame 等 LayoutBuilder 算出分页）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _maybePreDownload();
        // 把后续 1~2 章正文后台填入 _preDownloader 缓存，使下次翻页在
        // _loadChapter 处命中 cached() 而跳过主线程 fetchNovelContent（含
        // flutter_js 同步解析），消除「网络翻页卡顿」。
        _warmNextChapterCache();
      });
      // 不在此处对哨兵值 -1 调用 _saveProgress（会存入非法页码）。
      // 合法的页码会在 _buildReader 哨兵校正后，由后续翻页/渲染自动保存；
      // 若 restorePage ≥ 0 则正常记录进度。
      if (restorePage >= 0) _saveProgress(restorePage);
    } on WebViewHtmlRequest catch (e) {
      // 反爬拦截且源声明 useWebview：记录请求，由错误视图提供「抓取本章渲染
      // 内容」入口（打开真浏览器取回渲染 HTML 回灌），而非无效的手动验证流程。
      if (mounted) {
        setState(() {
          _isResolveError = false;
          _verificationError = null;
          _htmlCaptureRequest = e;
          _error = e.toString();
          _loading = false;
        });
      }
    } on VerificationRequiredException catch (e) {
      // 验证拦截：记录异常供错误视图提供"去验证"入口，修复"验证完成后
      // 正文仍无法显示"的阅读器侧断链（此前落入通用分支成死错误）。
      if (mounted) {
        setState(() {
          _isResolveError = false;
          _verificationError = e;
          _error = e.toString();
          _loading = false;
        });
      }
    } on SourceResolveException catch (e) {
      if (mounted) {
        setState(() {
          _isResolveError = true;
          _verificationError = null;
          _error = e.message;
          _loading = false;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _isResolveError = false;
          _verificationError = null;
          _error = e.toString();
          _loading = false;
        });
      }
    }
    _chapterLoading = false;
  }

  /// 用 WebView 取回的渲染后 HTML 重抓本章正文（源声明 useWebview 的反爬回灌路径）。
  ///
  /// 与 [_loadChapter] 仅差在把 [renderedHtml] 透传给 [MediaApiService
  /// .fetchNovelContent]，从而走 [ShuyuanNovelResolver.resolveRenderedHtml]
  /// 的 content 分支直接解析渲染 HTML，不再发起会被 Cloudflare 拒绝的直连请求。
  Future<void> _loadChapterWithRenderedHtml(
    int index,
    String renderedHtml, {
    int restorePage = 0,
  }) async {
    if (_chapterLoading) return;
    _chapterLoading = true;
    if (mounted) setState(() => _loading = true);
    _stopAutoPage();
    try {
      final source = _repo.getById(widget.sourceId);
      if (source == null)
        throw Exception('source not found: ${widget.sourceId}');
      if (index < 0 || index >= widget.chapters.length) {
        throw Exception('chapter index out of range: $index');
      }
      final chapter = widget.chapters[index];
      final paragraphs = await _service.fetchNovelContent(
        source,
        novelId: widget.novelId,
        chapterUrl: chapter.url,
        renderedHtml: renderedHtml,
      );
      if (!mounted) {
        _chapterLoading = false;
        return;
      }
      // 内容编辑：同 [_loadChapter]，渲染 HTML 抓取结果同样可被编辑覆盖。
      final List<NovelBlock> effectiveEdited =
          await _applyContentEditOverride(chapter.id, paragraphs);
      setState(() {
        _rawParagraphs = effectiveEdited;
        _paragraphs = _applyConvert(effectiveEdited);
        _loading = false;
        _error = null;
        _verificationError = null;
        _htmlCaptureRequest = null;
        _contentVersion++;
      });
      _setupControllers(restorePage: restorePage);
      if (restorePage >= 0) _saveProgress(restorePage);
    } on VerificationRequiredException catch (e) {
      if (mounted) {
        setState(() {
          _isResolveError = false;
          _verificationError = e;
          _htmlCaptureRequest = null;
          _error = e.toString();
          _loading = false;
        });
      }
    } on SourceResolveException catch (e) {
      if (mounted) {
        setState(() {
          _isResolveError = true;
          _verificationError = null;
          _htmlCaptureRequest = null;
          _error = e.message;
          _loading = false;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _isResolveError = false;
          _verificationError = null;
          _htmlCaptureRequest = null;
          _error = e.toString();
          _loading = false;
        });
      }
    }
    _chapterLoading = false;
  }

  /// 按当前繁简转换模式转换图文块：仅文本块做转换，插图块原样保留。
  List<NovelBlock> _applyConvert(List<NovelBlock> input) {
    // 1. 应用替换规则（书籍级替换规则引擎，排版期编译缓存）。
    List<NovelBlock> replaced = input;
    final replaceRules = _replaceRuleSet;
    if (replaceRules != null &&
        replaceRules.enabled &&
        _replaceBookEnabled &&
        replaceRules.rules.isNotEmpty) {
      final purged = <NovelBlock>[];
      for (final b in input) {
        if (b is NovelTextBlock) {
          final text = replaceRules.apply(
            b.text,
            // 章节标题块走「标题」范围，正文块走「正文」范围。
            scopeFilter: b.isHeading ? 'title' : 'content',
            bookId: widget.novelId,
            sourceId: widget.sourceId,
          );
          // 整段被规则清空（广告行）→ 直接丢掉，避免正文里留下空行。
          if (text.trim().isEmpty && b.text.trim().isNotEmpty) continue;
          purged.add(NovelTextBlock(text, isHeading: b.isHeading));
        } else {
          purged.add(b);
        }
      }
      replaced = purged;
    }
    // 2. 应用繁简转换。
    final mode = ChineseConvertMode.fromString(_prefs.chineseConvert);
    if (mode == ChineseConvertMode.none) return replaced;
    return [
      for (final b in replaced)
        if (b is NovelTextBlock)
          NovelTextBlock(convertChinese(b.text, mode))
        else
          b,
    ];
  }

  /// 加载全局净化规则（含旧版书籍级规则迁移）。
  /// [refresh] 为 true 时从存档重新取一次（规则可能在设置页被改过）。
  Future<void> _ensurePurgeRules({bool refresh = false}) async {
    if (_replaceRuleSet != null && !refresh) return;
    final store = NovelReplaceRuleStore();
    await store.migrateLegacy(widget.novelId, widget.title);
    _replaceRuleSet = await store.load();
    _replaceBookEnabled = await store.isBookEnabled(widget.novelId);
  }

  /// 净化规则变更后重新加载并重排当前章（保持阅读位置）。
  Future<void> _reloadPurgeRules() async {
    final store = NovelReplaceRuleStore();
    final rules = await store.load(refresh: true);
    final bookEnabled = await store.isBookEnabled(widget.novelId);
    if (!mounted) return;
    _replaceRuleSet = rules;
    _replaceBookEnabled = bookEnabled;
    _refreshConvert();
  }

  /// 重新应用繁简转换（在 [NovelReaderPreferences.chineseConvert] 变更后调用）。
  void _refreshConvert() {
    final next = _applyConvert(_rawParagraphs);
    if (next.length == _paragraphs.length) {
      bool same = true;
      for (int i = 0; i < next.length; i++) {
        if (next[i] != _paragraphs[i]) {
          same = false;
          break;
        }
      }
      if (same) return;
    }
    setState(() {
      _paragraphs = next;
      _contentVersion++;
    });
    _setupControllers(restorePage: _currentPage);
  }

  void _setupControllers({int restorePage = 0}) {
    _scrollController?.dispose();
    _scrollController = null;
    _currentPage = restorePage;
    _scrollFraction = 0;

    if (_prefs.pageAnimation.isScroll) {
      _scrollController = ScrollController();
      _scrollController!.addListener(_onScrollChanged);
      // 章节内容换了（或偏好重排）：连排缓冲重置为「当前章单段」，
      // 后续滚到段末再按需追加下一章。
      _resetScrollSegments();
      // 滚动模式此前只把 _currentPage 赋成 restorePage，却从未把滚动位置挪
      // 过去，视图始终停在开头。这里按「等效页码 ↔ 滚动比例」恢复位置，
      // 与 [_onScrollChanged] 的保存逻辑严格对称。
      _restoreScrollPosition(restorePage);
    } else {
      _resetScrollSegments();
    }
    // paged 模式由 NovelAnimatedPageView 内部管理页状态；
    // _contentVersion 变更会触发 widget 重建并使用 initialPage。
    if (mounted) setState(() {});
  }

  /// 重置滚动连排缓冲为「当前章单段」。
  ///
  /// 章节内容替换（切章 / 本地解析完成 / 偏好重排）后调用，保证缓冲与
  /// [_paragraphs] 同源；后续滚到段末再按需追加下一章。
  void _resetScrollSegments() {
    _scrollSegments.clear();
    _scrollSegStarts
      ..clear()
      ..add(0);
    _scrollAppending = false;
    _scrollAppendFailedFor = -1;
    _scrollAppendFailedAt = null;
    if (!_prefs.pageAnimation.isScroll) return;
    final chs = _effectiveChapters;
    if (chs.isEmpty || _paragraphs.isEmpty) return;
    final int idx = _chapterIndex.clamp(0, chs.length - 1);
    final String title = chs[idx].title;
    _scrollSegments.add(
      _NovelScrollSegment(
        chapterIndex: idx,
        title: title,
        blocks: _paragraphs,
        rawBlocks: _rawParagraphs,
        showTitle: _prefs.showChapterTitleInBody && title.isNotEmpty,
      ),
    );
    _rebuildScrollStarts();
  }

  /// 重建各段在扁平列表中的起始下标（末项 = 总项数）。
  void _rebuildScrollStarts() {
    _scrollSegStarts
      ..clear()
      ..add(0);
    for (final seg in _scrollSegments) {
      _scrollSegStarts.add(_scrollSegStarts.last + seg.itemCount);
    }
  }

  _NovelScrollSegment? _segmentByChapter(int chapterIndex) {
    for (final seg in _scrollSegments) {
      if (seg.chapterIndex == chapterIndex) return seg;
    }
    return null;
  }

  /// 段首在滚动坐标系（内容坐标，不随滚动变化）中的位置。
  double? _segmentTopPixels(_NovelScrollSegment seg, ScrollPosition pos) {
    final BuildContext? ctx = seg.anchorKey.currentContext;
    final RenderObject? ro = ctx?.findRenderObject();
    if (ro is RenderBox && ro.attached && ro.hasSize) {
      final double top = pos.pixels + ro.localToGlobal(Offset.zero).dy;
      seg.lastTopPixels = top;
      return top;
    }
    // 段首项被列表回收（滚出缓存区）时用最近一次测量值兜底。
    return seg.lastTopPixels;
  }

  /// 段高（像素）：相邻段段首差分；末段用内容总高推算。
  double? _segmentHeight(_NovelScrollSegment seg, ScrollPosition pos) {
    final double? top = _segmentTopPixels(seg, pos);
    if (top == null) return seg.knownHeight;
    final _NovelScrollSegment? next = _segmentByChapter(seg.chapterIndex + 1);
    if (next != null) {
      final double? nextTop = _segmentTopPixels(next, pos);
      if (nextTop != null && nextTop > top) {
        final double h = nextTop - top;
        seg.knownHeight = h;
        return h;
      }
      // 下一段刚追加、尚未完成首帧测量：用上一次已知段高兜底。
      // 绝不能退回「内容总高 - 段首」（会把下一章高度算进本章，导致
      // 章内比例被严重低估、进度被写错）。
      return seg.knownHeight;
    }
    // 真·末段：用内容总高推算，但必须扣掉列表底部留白与尾部提示项，
    // 否则章末比例永远差一截（到不了 100%）。
    final double contentH = pos.maxScrollExtent +
        pos.viewportDimension -
        _prefs.margin -
        _kScrollFooterHeight;
    final double h = contentH - top;
    if (h <= 0) return seg.knownHeight;
    seg.knownHeight = h;
    return h;
  }

  /// 视口顶部所在章段（「主导章」）。
  int? _dominantScrollChapter(ScrollPosition pos) {
    int? best;
    for (final seg in _scrollSegments) {
      final double? top = _segmentTopPixels(seg, pos);
      if (top == null) continue;
      if (top <= pos.pixels + _kScrollChapterAnchorSlack) {
        best = seg.chapterIndex;
      }
    }
    return best;
  }

  /// 章内滚动比例（0..1）。
  ///
  /// 单段时等价于原始的「offset / maxScrollExtent」；连排多段时按段内
  /// 位置换算，保证底部进度条与阅读位置仍是「本章进度」而非整条缓冲的
  /// 比例（跨章后归零，符合直觉）。
  ///
  /// **分母用「可滚动距离」（段高 − 视口高）而不是段高**：滚动位置记的是
  /// 视口顶部，只有视口底部顶到段末才算读完该章；用段高当分母会导致
  /// 章末最多只到 ~85%，永远到不了 100%。
  ///
  /// [chapterIndex] 可显式指定要换算的章（默认当前章）：主导章切换的
  /// 瞬间需要「按新章」先算出比例再去改状态。无法测量时沿用上一次比例，
  /// 避免用整条缓冲的全局比例把章内进度写小（表现为进度条回弹）。
  double _chapterScrollRatio(ScrollPosition pos, {int? chapterIndex}) {
    final int target = chapterIndex ?? _chapterIndex;
    final double max = pos.maxScrollExtent;
    if (max <= 0) return 0;
    // 滚到列表最底＝读完（末章末页 / 已无更多内容）：直接给 100%，
    // 不再依赖段高测量精度。
    if (pos.pixels >= max - 1) return 1.0;
    if (_scrollSegments.length <= 1) {
      // 单章（无后续段）时列表尾部还有「底部留白 + 尾项」，滚到章末并不
      // 等于滚到 maxScrollExtent；分母扣掉这两段空白，章末才能到 100%。
      final double scrollable =
          max - _prefs.margin - _kScrollFooterHeight;
      if (scrollable <= 1) return 1.0;
      return (pos.pixels / scrollable).clamp(0.0, 1.0);
    }
    final _NovelScrollSegment? seg = _segmentByChapter(target);
    if (seg == null) return _scrollFraction;
    final double? top = _segmentTopPixels(seg, pos);
    if (top == null) return _scrollFraction;
    // 段高内部优先「相邻段段首差分」，退而用上次已知段高，末段扣留白。
    final double? height = _segmentHeight(seg, pos);
    if (height == null || height <= 0) return _scrollFraction;
    final double scrollable = height - pos.viewportDimension;
    if (scrollable <= 1) return 1.0; // 整章不到一屏：看到即读完
    final double ratio =
        ((pos.pixels - top) / scrollable).clamp(0.0, 1.0);
    // 读到 98.5% 以上即视为本章读完：显示层四舍五入不该把「已到章末」
    // 呈现成 99%，也避免最后几像素的测量误差让进度卡在 99%。
    return ratio >= 0.985 ? 1.0 : ratio;
  }

  /// 临近段末时追加下一章（提前约一屏半准备，接缝处不空窗）。
  void _maybeAppendNextSegment(ScrollPosition pos) {
    if (!_scrollAutoNextEnabled || _scrollAppending) return;
    if (_scrollSegments.isEmpty) return;
    if (!pos.hasContentDimensions || !pos.hasViewportDimension) return;
    final chs = _effectiveChapters;
    final int last = _scrollSegments.last.chapterIndex;
    if (last >= chs.length - 1) return;
    if (_segmentByChapter(last + 1) != null) return;
    // 失败退避：同一章 10 秒内不重复自动请求（重试入口由尾部提示提供）。
    if (_scrollAppendFailedFor == last + 1) {
      final DateTime? at = _scrollAppendFailedAt;
      if (at == null ||
          DateTime.now().difference(at) < const Duration(seconds: 10)) {
        return;
      }
    }
    final double remain = pos.maxScrollExtent - pos.pixels;
    // 提前量必须小于列表的预构建范围（cacheExtent 600），否则新追加的
    // 章段首帧不会被构建，拿不到段首位置 → 章内比例算不出来、进度卡住。
    if (remain > pos.viewportDimension * 0.5) return;
    unawaited(_appendNextScrollSegment());
  }

  /// 抓取并追加下一章为新的滚动段（列表尾部增长，不扰动当前位置）。
  Future<void> _appendNextScrollSegment() async {
    if (_scrollAppending) return;
    if (!_scrollAutoNextEnabled || _scrollSegments.isEmpty) return;
    final chs = _effectiveChapters;
    final int next = _scrollSegments.last.chapterIndex + 1;
    if (next >= chs.length) return;
    if (_segmentByChapter(next) != null) return;
    _scrollAppending = true;
    if (mounted) setState(() {});
    try {
      final List<NovelBlock>? blocks = await _blocksForChapterIndex(next);
      if (blocks == null || !mounted) return;
      final List<NovelBlock> effective =
          await _applyContentEditOverride(chs[next].id, blocks);
      if (!mounted) return;
      final String title = chs[next].title;
      setState(() {
        _scrollSegments.add(
          _NovelScrollSegment(
            chapterIndex: next,
            title: title,
            blocks: _applyConvert(effective),
            rawBlocks: effective,
            showTitle: _prefs.showChapterTitleInBody && title.isNotEmpty,
          ),
        );
        _rebuildScrollStarts();
        _scrollAppendFailedFor = -1;
        _scrollAppendFailedAt = null;
      });
      // 追加后帧末重算一次章内比例：新段段首此时已完成布局，
      // 段高可测，比例不必等到用户下一次滚动才更新（否则进度像卡住）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ScrollController? ctrl = _scrollController;
        if (ctrl == null || !ctrl.hasClients) return;
        final double frac = _chapterScrollRatio(ctrl.position);
        if ((frac - _scrollFraction).abs() < 0.005) return;
        _scrollFraction = frac;
        if (_uiVisible) setState(() {});
      });
    } on Object catch (e) {
      // 追加失败不影响当前章阅读：不弹错，尾部提示提供重试入口。
      _scrollAppendFailedFor = next;
      _scrollAppendFailedAt = DateTime.now();
      AppLog.instance.w('[小说连排] 追加第 ${next + 1} 章失败: $e');
    } finally {
      _scrollAppending = false;
      if (mounted) setState(() {});
    }
  }

  /// 取指定章节的正文块（不改变当前阅读状态）。
  Future<List<NovelBlock>?> _blocksForChapterIndex(int index) async {
    final chs = _effectiveChapters;
    if (index < 0 || index >= chs.length) return null;
    final Episode ep = chs[index];
    if (_isLocalMode) return _localBlocksForChapter(index);
    final source = _repo.getById(widget.sourceId);
    if (source == null) return null;
    final List<NovelBlock>? cached =
        await _preDownloader.cached(widget.novelId, ep.id);
    if (cached != null) return cached;
    return _service.fetchNovelContent(
      source,
      novelId: widget.novelId,
      chapterUrl: ep.url,
    );
  }

  /// 本地模式取指定章节的正文块（纯内存切片）。
  ///
  /// 覆盖「聚合模式 EPUB/TXT 内部章节」与「单文件 EPUB/TXT 逐章切片」；
  /// 聚合 collapsed 模式（每文件一章、文件未解析缓存）返回 null，即该
  /// 形态下不参与连排（需要读盘解析，留给显式翻章）。
  List<NovelBlock>? _localBlocksForChapter(int index) {
    final chs = _effectiveChapters;
    if (index < 0 || index >= chs.length) return null;
    final Episode ep = chs[index];
    // 聚合模式 EPUB 内部章节：整本已缓存，直接切片。
    final int sep = ep.id.indexOf('|');
    if (sep >= 0) {
      final LocalNovelBook? book = _aggEpubBooks[ep.id.substring(0, sep)];
      final int ci = int.tryParse(ep.id.substring(sep + 1)) ?? 0;
      if (book == null || book.chapters.isEmpty) return null;
      final LocalNovelChapter ch =
          book.chapters[ci.clamp(0, book.chapters.length - 1)];
      return <NovelBlock>[
        if (ch.title.isNotEmpty) NovelTextBlock(ch.title, isHeading: true),
        for (final p in ch.content)
          if (p.trim().isNotEmpty) NovelTextBlock(p),
      ];
    }
    // 聚合模式 TXT 内部章节：整本已缓存，按路由切片。
    final (String, int)? meta = _aggTxtEpisodeMeta[ep.id];
    if (meta != null) {
      final LocalNovelBook? book = _aggTxtBooks[meta.$1];
      if (book == null || book.chapters.isEmpty) return null;
      final int ci = meta.$2;
      if (ci < 0) {
        return <NovelBlock>[
          for (final ch in book.chapters) ...<NovelBlock>[
            if (ch.title.isNotEmpty)
              NovelTextBlock(ch.title, isHeading: true),
            for (final p in ch.content)
              if (p.trim().isNotEmpty) _localBlockFromLine(p),
          ],
        ];
      }
      final LocalNovelChapter ch =
          book.chapters[ci.clamp(0, book.chapters.length - 1)];
      return <NovelBlock>[
        if (ch.title.isNotEmpty) NovelTextBlock(ch.title, isHeading: true),
        for (final p in ch.content)
          if (p.trim().isNotEmpty) _localBlockFromLine(p),
      ];
    }
    // 单文件（EPUB / TXT）：解析结果已在内存，按章切片。
    final List<LocalNovelChapter>? parsed = _localParsedChapters;
    if (parsed == null || parsed.isEmpty) return null;
    final LocalNovelChapter ch =
        parsed[index.clamp(0, parsed.length - 1)];
    return <NovelBlock>[
      if (ch.title.isNotEmpty) NovelTextBlock(ch.title, isHeading: true),
      for (final p in ch.content)
        if (p.trim().isNotEmpty) _localBlockFromLine(p),
    ];
  }

  /// 本地正文行 → 块（下载器占位行还原为本地插图）。
  NovelBlock _localBlockFromLine(String line) {
    if (line.startsWith(kNexhubImgMarker)) {
      final String url = line.substring(kNexhubImgMarker.length).trim();
      if (url.isNotEmpty) return NovelImageBlock(url, source: _source);
    }
    return NovelTextBlock(line);
  }

  /// 滚动停稳后把「主导章」同步为当前章（选区 / 进度 / 预下载跟随）。
  ///
  /// 只在滚动结束触发，避免滚动过程中 setState 重建整棵阅读器（掉帧），
  /// 也避免分页在滚动中被同步重算。
  void _settleScrollChapter() {
    if (!mounted || !_scrollAutoNextEnabled) return;
    if (_scrollSegments.length <= 1) return;
    // 朗读中不切主导章：TTS 内部段落索引与朗读进度仍按启动时的章节维护，
    // 此时切换会让高亮 / 跳转索引错位（章末续读由 TTS 自己的回调处理）。
    if (_tts.state != NovelTtsState.stopped) return;
    final sc = _scrollController;
    if (sc == null || !sc.hasClients) return;
    final int? idx = _dominantScrollChapter(sc.position);
    if (idx == null || idx == _chapterIndex) return;
    final _NovelScrollSegment? seg = _segmentByChapter(idx);
    if (seg == null) return;
    // 向下切章留死区：段首刚碰到视口上沿时不切，要求真正滚过去一点，
    // 避免手指停在章界时主导章反复切换、进度条 100%↔0% 来回跳。
    if (idx > _chapterIndex) {
      final double? top = _segmentTopPixels(seg, sc.position);
      if (top != null && top > sc.position.pixels - _kScrollChapterHysteresis) {
        return;
      }
    }
    // 先按「新章」算出段内比例，切章瞬间进度条不归零（否则表现为
    // 「翻回上一章进度恒为 0%」）。
    final double ratio = _chapterScrollRatio(sc.position, chapterIndex: idx);
    setState(() {
      _chapterIndex = idx;
      _paragraphs = seg.blocks;
      _rawParagraphs = seg.rawBlocks;
      // 分页随章变化，交给 LayoutBuilder 用新正文重算。
      _pagination = null;
      _paginationSig = null;
      _currentPage = 0;
      _scrollFraction = ratio;
    });
    _bindSelection();
    unawaited(_reloadHighlightsForChapter());
    _maybePreDownload();
    _warmNextChapterCache();
    // 分页就绪后再把「章内实际页码」算准并落盘 / 刷新进度条。
    // 切章瞬间不写 page 0：那会把存档覆盖成本章首页，且与旧章页号错配
    // （退出时 _persistProgressNow 会拿新章 + 旧页号写盘）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ScrollPosition? pos = _scrollController?.position;
      if (pos == null) return;
      if (_paginationChapterIndex != _chapterIndex) return;
      final int total = _pagination?.pages.length ?? 0;
      final double liveRatio = _chapterScrollRatio(pos);
      final int page = total > 0
          ? (liveRatio * (total - 1)).round().clamp(0, total - 1)
          : 0;
      final bool changed = page != _currentPage ||
          (liveRatio - _scrollFraction).abs() > 0.005;
      if (changed) {
        setState(() {
          _currentPage = page;
          _scrollFraction = liveRatio;
        });
      }
      // 章号已经变了，存档必须跟上（否则退出重进会回到上一章末尾）。
      _saveProgress(page);
    });
  }

  /// 连排列表尾项：加载下一章提示 / 全书读完提示。
  Widget _buildScrollFooter(Color bg, Color textColor) {
    final l10n = AppLocalizations.of(context);
    final chs = _effectiveChapters;
    final int last =
        _scrollSegments.isEmpty ? -1 : _scrollSegments.last.chapterIndex;
    final bool atEnd = last >= chs.length - 1;
    final Widget child;
    if (_scrollAppending) {
      child = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _prefs.resolveTextColor(bg).withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(width: AppTokens.spaceSm),
          Text(
            l10n.novelScrollEndLoading,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: _prefs.resolveTextColor(bg)),
          ),
        ],
      );
    } else if (_scrollAppendFailedFor == last + 1) {
      // 下一章抓取失败：给出可点重试入口（失败不退避时不自动重发）。
      child = TextButton.icon(
        onPressed: () {
          _scrollAppendFailedFor = -1;
          _scrollAppendFailedAt = null;
          unawaited(_appendNextScrollSegment());
        },
        icon: const Icon(Icons.refresh_rounded, size: 16),
        label: Text(
          l10n.novelScrollEndRetry,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _prefs.resolveTextColor(bg).withValues(alpha: 0.75),
              ),
        ),
      );
    } else if (atEnd && _scrollSegments.isNotEmpty) {
      child = Text(
        l10n.novelScrollEndOfBook,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: _prefs.resolveTextColor(bg).withValues(alpha: 0.6)),
      );
    } else {
      child = const SizedBox.shrink();
    }
    // 固定高度的占位，避免「加载中 ↔ 读完」切换时列表高度抖动。
    return SizedBox(
      height: _kScrollFooterHeight,
      child: Center(child: child),
    );
  }

  /// scroll 模式滚动监听：记录阅读位置 + 更新 [_scrollFraction] 同步底部滑条。
  /// 仅在 UI 可见时刷新（隐藏时无需重绘）。
  void _onScrollChanged() {
    // 恢复进度期间的过渡位置不回写，避免冲掉存档。
    if (_restoringPage) return;
    final sc = _scrollController;
    if (sc == null || !sc.hasClients) return;
    // 临近章末先把下一章追加进来（无缝连排）。
    _maybeAppendNextSegment(sc.position);
    double frac = _chapterScrollRatio(sc.position);
    // 同章内防回退：图片加载等布局变化会让段首位置漂移，章内比例随之
    // 往回跳几个百分点（表现为「进度条回弹」）。只吸收**小幅**回落；
    // 跨章、追加下一章这类真实语义变化会让比例大幅下降，必须放行，
    // 否则进度会永远卡在上一个值上不动。
    if (sc.position.userScrollDirection != ScrollDirection.forward) {
      final double drop = _scrollFraction - frac;
      if (drop > 0 && drop < 0.05) frac = _scrollFraction;
    }
    // 滚动模式此前完全不保存阅读位置（只有分页模式的 _onPageChanged 会存），
    // 退出重进永远回到第一页。这里把滚动比例换算成与分页模式同语义的
    // 「等效页码」后写盘，两种模式互相切换也不会错位。
    final int total = _pagination?.pages.length ?? 0;
    if (total > 1) {
      final int idx = (frac * (total - 1)).round().clamp(0, total - 1);
      if (idx != _currentPage) {
        _currentPage = idx;
        _saveProgress(idx);
        // 滚动模式进度越过阈值同样触发预下载（每章一次）。
        if (mounted) _maybePreDownload();
      }
    }
    if ((frac - _scrollFraction).abs() < 0.005) return;
    _scrollFraction = frac;
    if (mounted && _uiVisible) setState(() {});
  }

  /// scroll 模式恢复滚动位置到「等效页码」[page]。
  ///
  /// 分页结果 [_pagination] 由 `LayoutBuilder` 在 layout 阶段才算出，
  /// ListView 的 `maxScrollExtent` 也要等首屏布局完成，所以这里带重试
  /// （最多约 2.4 秒）；超时放弃并解除写盘封锁，不影响正常阅读。
  /// [page] 为负表示哨兵「本章最后一页」，直接滚到底。
  void _restoreScrollPosition(int page) {
    if (page == 0) return;
    _restoringPage = true;
    int attempts = 0;
    void tryJump() {
      if (!mounted) {
        _restoringPage = false;
        return;
      }
      final ScrollController? sc = _scrollController;
      final int total = _pagination?.pages.length ?? 0;
      final bool ready = sc != null &&
          sc.hasClients &&
          sc.position.maxScrollExtent > 0 &&
          (page < 0 || total > 1);
      if (!ready) {
        if (attempts++ >= 20) {
          _restoringPage = false;
          return;
        }
        Future<void>.delayed(const Duration(milliseconds: 120), tryJump);
        return;
      }
      final double max = sc.position.maxScrollExtent;
      final double target =
          (page < 0 ? max : (page / (total - 1)) * max).clamp(0.0, max);
      sc.jumpTo(target);
      if (page >= 0) _currentPage = page;
      // 同步进度条比例：恢复期间 [_onScrollChanged] 被封锁，不主动刷新的话
      // 底部滑条会停在 0%（表现为「翻回上一章进度恒为 0」）。
      if (mounted) {
        setState(() {
          _scrollFraction = max > 0 ? (target / max).clamp(0.0, 1.0) : 0.0;
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoringPage = false;
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => tryJump());
  }

  void _onPageChanged(int idx) {
    // 恢复进度期间的过渡页码不回写，避免冲掉存档。
    if (_restoringPage) return;
    // 防御：page view 在极端时序下可能回调负数（如拖拽越界），
    // 直接丢弃非法值，避免 _currentPage 被污染为 -1/-2/-3。
    if (idx < 0) return;
    if (idx == _currentPage) return;
    // 翻页时收起选区工具条并清空活动选区。
    if (_showSelectionToolbar) {
      _selectionController.clearSelection();
      _showSelectionToolbar = false;
    }
    _currentPage = idx;
    _saveProgress(idx);
    // 阅读进度越过阈值时触发后台预下载后续章节（每章一次）。
    if (mounted) _maybePreDownload();
    // 翻页后刷新底部进度条 / 页码（底部栏位于 ListenableBuilder(_tts) 内，
    // 翻页不经由 _tts 通知，必须主动 setState 才能实时更新进度。
    if (mounted) setState(() {});
  }

  /// 当前章阅读进度越过阈值时，把后续 N 章加入正式下载（DownloadManager：
  /// 下载列表可见 + 本地文件落地，离线可读；与漫画自动下载同机制）。
  /// 每章只触发一次；开始/失败均有 SnackBar 可见反馈。
  void _maybePreDownload() {
    if (!_preDownloadPrefs.enabled) return;
    if (_isLocalMode) return;
    final int currentIdx = _chapterIndex;
    if (_preDownloadTriggeredFor == currentIdx) return;
    final int total = _pagination?.pages.length ?? 0;
    if (total <= 0) return;
    final int percent = (((_currentPage + 1) / total) * 100).round();
    if (percent < _preDownloadPrefs.thresholdPercent) return;
    _preDownloadTriggeredFor = currentIdx;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final DownloadManager? dm = _downloadManager;
    if (dm == null) return;
    // 无后续章节可下：直接视为已处理。
    if (widget.chapters.length <= currentIdx + 1) return;
    // 已有该作品活跃下载批次（进行中/等待/暂停）则跳过，避免重复入队；
    // 已完成/失败/取消批次不阻塞（手动下过前几章后新章仍能自动下）。
    final bool hasActive = dm.tasks.any(
      (t) => t.contentId == widget.novelId && t.isActive,
    );
    if (hasActive) return;
    final MediaItem item = MediaItem(
      id: widget.novelId,
      title: widget.title,
      sourceId: widget.sourceId,
      sourceType: SourceType.novelSource,
      coverUrl: widget.coverUrl,
      detailUrl: widget.detailUrl,
    );
    // 过滤已下载 / 已排队章节：预下载 = 下载接下来「未下载」的 N 章。
    final Set<String> downloaded = dm.downloadedChapterTitles(widget.novelId);
    final Set<String> queued = dm.queuedChapterTitles(widget.novelId);
    final int count = _preDownloadPrefs.count;
    final List<int> indices = <int>[
      for (int i = currentIdx + 1; i < widget.chapters.length; i++)
        if (!downloaded.contains(widget.chapters[i].title) &&
            !queued.contains(widget.chapters[i].title))
          i,
    ];
    if (indices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.preDownloadDone(0))),
      );
      return;
    }
    final int pick = indices.length > count
        ? indices.sublist(0, count).toList().length
        : indices.length;
    final List<int> selected = indices.take(count).toList();
    AppLog.instance.i(
      '[小说预下载] 入队 novel=${widget.novelId} '
      'chapter=$currentIdx page=$_currentPage total=$total 待下=$pick',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.preDownloadStarted(selected.length))),
    );
    unawaited(dm
        .addTask(
      item: item,
      chapters: widget.chapters,
      chapterIndices: selected,
    )
        .then((_) {
      // 成功入队：下载进度在下载管理可见，不再重复提示。
    }).catchError((Object e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.preDownloadFailedHint)),
        );
      }
    }));
  }

  /// 章节加载完成后，后台把后续 1~2 章正文填入 [_preDownloader] 的内存 /
  /// Hive 缓存。这样下一次翻页在 [_loadChapter] 处命中 [cached()] 而跳过主线程
  /// 的 fetchNovelContent（含 flutter_js 同步解析），消除「网络翻页卡顿」。
  ///
  /// 与 [_maybePreDownload] 的落盘下载相互独立：本方法只填缓存、不写本地文件、
  /// 不出 SnackBar、不受预下载总开关限制（纯为翻页流畅度服务；总带宽约等于把
  /// 抓取时机提前，并不额外消耗）。[_preDownloader.preDownload] 自带内存 / 在途 /
  /// 落地三重去重，重复调用安全。
  void _warmNextChapterCache() {
    if (_isLocalMode) return;
    final source = _repo.getById(widget.sourceId);
    if (source == null) return;
    final int nextIdx = _chapterIndex + 1;
    if (nextIdx >= widget.chapters.length) return;
    unawaited(_preDownloader.preDownload(
      service: _service,
      source: source,
      novelId: widget.novelId,
      chapters: widget.chapters,
      startIndex: nextIdx,
      count: 2,
    ));
  }

  /// 把当前分页结果注入选区控制器，并异步加载本章已存划线（重新解析定位）。
  ///
  /// 仅在分页真正变化时（`sigChanged`）于帧后调用，避免在 build 期间
  /// 触发控制器通知（会触发 "setState during build"）。
  void _bindSelection() {
    if (_prefs.pageAnimation.isScroll) {
      // 滚动模式：直接用章节 blocks 注入（与分页同源，文本流一致）。
      _selectionController.setBlocks(_paragraphs);
    } else {
      final p = _pagination;
      if (p == null) return;
      _selectionController.setPagination(p);
    }
    _reloadHighlightsForChapter();
  }

  Future<void> _reloadHighlightsForChapter() async {
    final chs = _effectiveChapters;
    if (_chapterIndex < 0 || _chapterIndex >= chs.length) {
      _selectionController.setPersistedHighlights(const <NovelHighlight>[]);
      return;
    }
    final list = await NovelHighlightManager()
        .listForChapter(widget.novelId, _chapterIndex);
    if (!mounted) return;
    _selectionController.setPersistedHighlights(list);
  }

  /// 选区工具条：复制 / 整段 / 划线色板 / 问AI / 分享。
  ///
  /// 宽屏放得下时按钮等宽均分；窄屏改横向滑动（固定按钮宽 + 回弹物理，
  /// 滑动有「灵动」回弹手感）。Material 铺满到屏幕底（SafeArea 在其内），
  /// 避免系统导航栏区域露出未着色的空白条。
  Widget _buildSelectionToolbar() {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final buttons = <Widget>[
      _selToolbarButton(
        icon: Icons.copy_rounded,
        label: l10n.selectionCopy,
        onPressed: _selCopy,
      ),
      _selToolbarButton(
        icon: Icons.subject_rounded,
        label: l10n.selectionParagraph,
        onPressed: _selParagraph,
      ),
      _selToolbarButton(
        icon: Icons.palette_rounded,
        label: l10n.selectionHighlight,
        onPressed: () => _showColorPicker(),
      ),
      _selToolbarButton(
        icon: Icons.format_underline_rounded,
        label: l10n.selectionUnderline,
        onPressed: () => _showUnderlinePicker(),
      ),
      _selToolbarButton(
        icon: Icons.edit_note_rounded,
        label: l10n.selectionNote,
        onPressed: () => _selHighlightWithNote(),
      ),
      _selToolbarButton(
        icon: Icons.translate_rounded,
        label: l10n.selectionTranslate,
        onPressed: _selTranslate,
      ),
      _selToolbarButton(
        icon: Icons.auto_awesome_rounded,
        label: l10n.selectionAskAi,
        onPressed: _askAiAboutSelection,
      ),
      _selToolbarButton(
        icon: Icons.share_rounded,
        label: l10n.selectionShare,
        onPressed: () => _selShare(),
      ),
    ];
    const hPad = AppTokens.spaceXs;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Material(
        elevation: 8,
        color: cs.surface,
        child: SafeArea(
          top: false,
          bottom: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 全部按钮按固定宽排开的总宽 ≤ 可用宽 → 等宽均分；否则滑动。
              final canFit = constraints.maxWidth >=
                  buttons.length * 64.0 + hPad * 2;
              if (canFit) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: hPad,
                    vertical: AppTokens.spaceXs,
                  ),
                  child: Row(
                    children: <Widget>[
                      for (final b in buttons) Expanded(child: b),
                    ],
                  ),
                );
              }
              return ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  // 鼠标/触控笔也可拖动滑动（默认仅触摸），回弹物理带灵动手感。
                  dragDevices: const <PointerDeviceKind>{
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.stylus,
                    PointerDeviceKind.trackpad,
                  },
                  physics: const BouncingScrollPhysics(),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: hPad,
                    vertical: AppTokens.spaceXs,
                  ),
                  child: Row(children: buttons),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 显示高亮颜色选择器弹窗（背景高亮效果），点击色块直接落盘。
  Future<void> _showColorPicker() async {
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Color customColor = const Color(0x80FFFF00);
          return AlertDialog(
            title: Text(l10n.selectionHighlight),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // 预选色板
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: _highlightPalette.map((c) {
                    return GestureDetector(
                      onTap: () {
                        Navigator.of(ctx).pop(c);
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(ctx)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                // 自定义颜色
                Text(l10n.customColor, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 8),
                SizedBox(
                  width: 200,
                  child: _SimpleColorSlider(
                    value: customColor.toARGB32(),
                    onChanged: (c) {
                      customColor = Color(c);
                    },
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () =>
                      Navigator.of(ctx).pop(customColor.toARGB32()),
                  child: Text(l10n.customColorApply),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l10n.cancel),
              ),
            ],
          );
        },
      ),
    );
    if (result != null) {
      await _selHighlight(result);
    }
  }

  /// 显示划线样式+颜色选择器弹窗，先选样式再选颜色，确认后落盘。
  Future<void> _showUnderlinePicker() async {
    final l10n = AppLocalizations.of(context);
    HighlightEffect selectedEffect = HighlightEffect.underline;
    int selectedColor = _highlightPalette.first;
    final result = await showDialog<MapEntry<int, HighlightEffect>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text(l10n.selectionUnderline),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // 样式选择
                  Text(l10n.underlineStyle,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final eff in [
                        HighlightEffect.underline,
                        HighlightEffect.wavy,
                        HighlightEffect.dotted
                      ])
                        ChoiceChip(
                          label: Text(_effectLabel(eff, l10n),
                              style: const TextStyle(fontSize: 12)),
                          selected: eff == selectedEffect,
                          onSelected: (_) =>
                              setDialogState(() => selectedEffect = eff),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 颜色选择
                  Text(l10n.underlineColor,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: _highlightPalette.map((c) {
                      return GestureDetector(
                        onTap: () => setDialogState(() => selectedColor = c),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: c == selectedColor
                                  ? Theme.of(ctx).colorScheme.primary
                                  : Theme.of(ctx)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.3),
                              width: c == selectedColor ? 3 : 1,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  // 自定义颜色滑块
                  Text(l10n.customColor, style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  // 颜色预览
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Color(selectedColor),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Theme.of(ctx)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.3)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 200,
                    child: _SimpleColorSlider(
                      value: selectedColor,
                      onChanged: (c) => setDialogState(() => selectedColor = c),
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx)
                    .pop(MapEntry(selectedColor, selectedEffect)),
                child: Text(l10n.confirm),
              ),
            ],
          );
        },
      ),
    );
    if (result != null) {
      await _selHighlight(result.key, effect: result.value.name);
    }
  }

  /// 划线效果的中文标签。
  String _effectLabel(HighlightEffect eff, AppLocalizations l10n) {
    switch (eff) {
      case HighlightEffect.underline:
        return l10n.underlineStyleSolid;
      case HighlightEffect.wavy:
        return l10n.underlineStyleWavy;
      case HighlightEffect.dotted:
        return l10n.underlineStyleDotted;
      default:
        return eff.name;
    }
  }

  Widget _selToolbarButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    final cs = Theme.of(context).colorScheme;
    // 固定宽度：横向滑动工具条下不再互相挤压（窄屏超出部分可滑动）。
    return SizedBox(
      width: 64,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: cs.onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 16),
            const SizedBox(height: 1),
            Text(label,
                style: const TextStyle(fontSize: 9),
                overflow: TextOverflow.ellipsis,
                maxLines: 1),
          ],
        ),
      ),
    );
  }

  void _selCopy() {
    final quote = _selectionController.quote;
    if (quote.isEmpty) return;
    Clipboard.setData(ClipboardData(text: quote));
    _selectionController.clearSelection();
    setState(() {
      _showSelectionToolbar = false;
      _uiVisible = true; // 恢复控制面板
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).selectionCopied)),
    );
  }

  /// 划词翻译：把当前选中文本交给小说翻译管线（术语表/风格与整章翻译
  /// 共用同一套配置），弹窗展示原文与译文。
  Future<void> _selTranslate() async {
    final quote = _selectionController.quote;
    if (quote.isEmpty) return;
    _selectionController.clearSelection();
    setState(() {
      _showSelectionToolbar = false;
      _uiVisible = true; // 恢复控制面板
    });
    await showDialog<void>(
      context: context,
      builder: (_) => _SelectionTranslateDialog(
        text: quote,
        novelId: widget.novelId,
      ),
    );
  }

  /// 选区问 AI：携带当前章节上下文与选中文本打开轻量问答对话框。
  Future<void> _askAiAboutSelection() async {
    final quote = _selectionController.quote;
    if (quote.isEmpty) return;
    _selectionController.clearSelection();
    setState(() {
      _showSelectionToolbar = false;
      _uiVisible = true; // 恢复控制面板
    });
    final chs = _effectiveChapters;
    final chapterTitle = (_chapterIndex >= 0 && _chapterIndex < chs.length)
        ? chs[_chapterIndex].title
        : '';
    final chapterText = _paragraphs.join('\n');
    await showDialog<void>(
      context: context,
      builder: (_) => NovelSelectionAiDialog(
        bookTitle: widget.title,
        chapterTitle: chapterTitle,
        chapterText: chapterText,
        selection: quote,
      ),
    );
  }

  /// 格式化时间戳为可读字符串（如 "2024-01-15 14:30"）。
  String _formatTimestamp(int ms) {
    if (ms <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  /// 分享选区为带书封的渐变文艺卡（Phase 3 /）。
  ///
  /// 先预热书封（失败则用渐变占位），再弹预览 Dialog（含 RepaintBoundary），
  /// 用户点「分享」时把卡片栅格化为 PNG 临时文件经 [Share.shareXFiles] 分享。
  /// 支持自定义封面图片（从相册选择）。
  Future<void> _selShare() async {
    final quote = _selectionController.quote;
    if (quote.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    final chs = _effectiveChapters;
    final chapterTitle = (_chapterIndex >= 0 && _chapterIndex < chs.length)
        ? chs[_chapterIndex].title
        : '';
    String? cover = widget.coverUrl;
    // 预热书封，避免卡片渲染时图未就绪导致空白。
    if (cover != null && cover.isNotEmpty) {
      try {
        await precacheImage(NetworkImage(cover), context);
      } on Object {
        // 占位渐变兜底
      }
    }
    if (!mounted) return;
    final shareKey = GlobalKey();
    if (!mounted) return;
    final isMobile = MediaQuery.of(context).size.width < 600;
    double coverScale = 1.0; // 封面缩放比例
    // 用 StatefulBuilder 使自定义封面选择后实时更新预览
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          contentPadding: EdgeInsets.zero,
          content: SingleChildScrollView(
            child: RepaintBoundary(
              key: shareKey,
              child: _NovelShareCard(
                quote: quote,
                title: widget.title,
                chapterTitle: chapterTitle,
                coverUrl: cover,
                compact: isMobile,
                coverScale: coverScale,
              ),
            ),
          ),
          actions: <Widget>[
            // 封面大小调节滑块
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.photo_size_select_small_rounded, size: 16),
                  Expanded(
                    child: Slider(
                      value: coverScale,
                      min: 0.3,
                      max: 1.5,
                      divisions: 12,
                      onChangeStart: (_) => AppHaptics.light(),
                      onChanged: (v) => setDialogState(() => coverScale = v),
                    ),
                  ),
                  const Icon(Icons.photo_size_select_large_rounded, size: 16),
                ],
              ),
            ),
            // 三个按钮一排：更换封面 | 取消 | 分享
            OverflowBar(
              alignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                TextButton.icon(
                  icon: const Icon(Icons.image_rounded, size: 18),
                  label: Text(l10n.shareChangeCover),
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.image,
                      withData: true,
                    );
                    if (result != null && result.files.isNotEmpty) {
                      final bytes = result.files.first.bytes;
                      if (bytes != null) {
                        final dir = await getTemporaryDirectory();
                        final tempFile = File(
                          '${dir.path}/nexhub_share_cover_${DateTime.now().millisecondsSinceEpoch}.png',
                        );
                        await tempFile.writeAsBytes(bytes);
                        cover = tempFile.path;
                        if (ctx.mounted) setDialogState(() {});
                      }
                    }
                  },
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(l10n.cancel),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await _captureAndShare(shareKey, l10n);
                  },
                  child: Text(l10n.selectionShare),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 把 [shareKey] 对应的卡片栅格化为 PNG 并分享。
  Future<void> _captureAndShare(
      GlobalKey shareKey, AppLocalizations l10n) async {
    try {
      final boundary =
          shareKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File(
        p.join(dir.path,
            'nexhub_share_${DateTime.now().millisecondsSinceEpoch}.png'),
      );
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await Share.shareXFiles(
        <XFile>[XFile(file.path)],
        text:
            '${widget.title} · ${_effectiveChapters.length > _chapterIndex && _chapterIndex >= 0 ? _effectiveChapters[_chapterIndex].title : ''}',
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.shareFailed)),
        );
      }
    }
  }

  /// 把活动选区扩展到整段（按锚点所在段落的章内全局起止偏移）。
  void _selParagraph() {
    final controller = _selectionController;
    if (!controller.hasSelection) return;
    final para = controller.paragraphIndexAt(controller.selectionStart!);
    if (para == null) return;
    final range = controller.paragraphGlobalRange(para);
    if (range == null) return;
    controller.setSelectionRange(range.start, range.end);
  }

  /// 落盘当前活动选区为一条划线，返回新建的划线（不刷新 / 不收工具条）。
  Future<NovelHighlight?> _persistSelectionAsHighlight(int color,
      {String effect = 'bg'}) async {
    final controller = _selectionController;
    final quote = controller.quote;
    if (quote.isEmpty) return null;
    final ctx = controller.context();
    final chs = _effectiveChapters;
    final chapterId = (_chapterIndex >= 0 && _chapterIndex < chs.length)
        ? chs[_chapterIndex].id
        : 'unknown';
    final chapterTitle = (_chapterIndex >= 0 && _chapterIndex < chs.length)
        ? chs[_chapterIndex].title
        : '';
    final hl = NovelHighlight(
      novelId: widget.novelId,
      chapterIndex: _chapterIndex,
      chapterId: chapterId,
      chapterTitle: chapterTitle,
      quote: quote,
      contextBefore: ctx.before,
      contextAfter: ctx.after,
      color: color,
      effect: effect,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    // 新的覆盖旧的：删除同章+同引文+同效果的旧标记
    final existing = await NovelHighlightManager().listFor(widget.novelId);
    final dupKey = '${_chapterIndex}::${quote}::${effect}';
    for (final e in existing) {
      if ('${e.chapterIndex}::${e.quote}::${e.effect}' == dupKey) {
        await NovelHighlightManager().remove(e.key);
      }
    }
    await NovelHighlightManager().add(hl);
    return hl;
  }

  /// 落盘当前活动选区为一条划线，并刷新渲染。
  Future<void> _selHighlight(int color, {String effect = 'bg'}) async {
    final hl = await _persistSelectionAsHighlight(color, effect: effect);
    if (hl == null) return;
    // 直接添加已解析划线到控制器，跳过重定位（确保即时显示）。
    final controller = _selectionController;
    if (controller.hasSelection) {
      controller.addResolvedHighlight(
        controller.selectionStart!,
        controller.selectionEnd!,
        color,
        hl.key,
        effect: HighlightEffect.values.firstWhere(
          (e) => e.name == effect,
          orElse: () => HighlightEffect.bg,
        ),
      );
    }
    _selectionController.clearSelection();
    if (mounted)
      setState(() {
        _showSelectionToolbar = false;
        _uiVisible = true;
      });
  }

  /// 落盘为划线后立即打开笔记编辑（Phase 2 / 摘录）。
  Future<void> _selHighlightWithNote() async {
    final hl = await _persistSelectionAsHighlight(_highlightPalette.first);
    if (hl == null) return;
    await _reloadHighlightsForChapter();
    _selectionController.clearSelection();
    if (mounted)
      setState(() {
        _showSelectionToolbar = false;
        _uiVisible = true;
      });
    if (!mounted) return;
    await _editHighlightNote(hl);
  }

  /// 计算某页在章内的「起始字符偏移」（累计文本行长度，忽略插图）。
  ///
  /// 与 [_pageForCharOffset] 互为逆运算：保存时把当前页映射成偏移，
  /// 恢复时把偏移映射回页码。仅统计文本行长度，因为分页器的行文本并集
  /// 等于章内文本流，偏移对字号/边距/排版变化恒定。
  int _charOffsetForPage(int pageIndex) {
    final pages = _pagination?.pages;
    if (pages == null || pages.isEmpty) return 0;
    final p = pageIndex.clamp(0, pages.length - 1);
    var offset = 0;
    for (var i = 0; i < p; i++) {
      for (final item in pages[i]) {
        if (item is NovelTextLineItem) {
          offset += item.line.text.length;
        }
      }
    }
    return offset;
  }

  /// 把章内字符偏移映射回页码（二分查找，O(页数) 预计算 + O(log 页数)）。
  ///
  /// 返回首个「起始字符偏移 ≤ [offset]」的页；[offset] ≤ 0 回退首页，
  /// 越界回退末页。与 [_charOffsetForPage] 对称，保证换排版后回到同一处文字。
  int _pageForCharOffset(int offset) {
    final pages = _pagination?.pages;
    if (pages == null || pages.isEmpty) return 0;
    if (offset <= 0) return 0;
    // 预计算每页起始偏移：starts[k] = 第 k 页首字符在章内文本流中的累计偏移。
    // 必须覆盖到末页（k = length-1），否则末页偏移在二分时只能命中倒数第二页。
    final starts = <int>[0];
    var acc = 0;
    for (var i = 0; i < pages.length - 1; i++) {
      for (final item in pages[i]) {
        if (item is NovelTextLineItem) acc += item.line.text.length;
      }
      starts.add(acc); // starts[i+1] = 第 i+1 页起始偏移
    }
    starts.add(acc); // 末页起始偏移，使二分可命中末页本身
    // 二分找最后一个 starts[k] ≤ offset。
    var lo = 0;
    var hi = starts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (starts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo.clamp(0, pages.length - 1);
  }

  void _saveProgress(int page) {
    // 本地模式无 chapters，用占位 chapterId 保存进度。
    // 单 EPUB（已解析出章节）按真实章节保存，重开后能恢复到原章节原页。
    final String chapterId;
    String? chapterTitle;
    if (_isLocalMode && !_isAggregatedLocal && _parsedChapterEpisodes == null) {
      chapterId = 'local';
    } else {
      final chapters = _effectiveChapters;
      if (chapters.isEmpty) return;
      final idx = _chapterIndex.clamp(0, chapters.length - 1);
      chapterId = chapters[idx].id;
      chapterTitle = chapters[idx].title;
    }
    final int? charOff = _pagination != null ? _charOffsetForPage(page) : null;
    _progress.save(
      widget.novelId,
      chapterId,
      page,
      _chapterIndex,
      // 附带章内字符偏移，使进度在字号/边距/排版变化时仍回到同一处文字。
      charOffset: charOff,
      totalChapters: (!_isLocalMode ||
              _isAggregatedLocal ||
              _parsedChapterEpisodes != null)
          ? _effectiveChapters.length
          : null,
    );
    // 更新收藏条目的 lastRead 时间戳（收藏切换不丢 lastRead）
    try {
      context.read<FavoritesManager>().updateLastRead(
            widget.novelId,
            SourceType.novelSource,
          );
    } catch (_) {
      // FavoritesManager 不可用时静默忽略。
    }
    // 写浏览历史：让「历史」Tab 看到最近读到的章节标题，
    // 续读/继续阅读入口可基于 lastChapter 精确定位。
    try {
      final history = context.read<HistoryManager>();
      final item = MediaItem(
        id: widget.novelId,
        title: widget.title,
        sourceId: widget.sourceId,
        sourceType: SourceType.novelSource,
        coverUrl: widget.coverUrl,
        detailUrl: widget.detailUrl,
      );
      unawaited(history.addHistory(
        item,
        lastChapter: chapterTitle,
        sourceType: SourceType.novelSource,
      ));
    } catch (_) {
      // HistoryManager 不可用时静默忽略。
    }
    // 章节阅读进度达到「已看」阈值时标记该章已读（每章仅标记一次）。
    _maybeMarkChapterWatched(page);
  }

  /// 退出/切后台时立即落盘当前阅读位置（不依赖 [context]）。
  ///
  /// 普通 [_saveProgress] 会读写 FavoritesManager/HistoryManager，dispose 后
  /// context 已失效会抛错；本方法只写 [NovelProgressManager]，避免该问题。
  /// 用于修复「翻到某章首页退出重进却回到上一章末页」：进度此前仅在阅读中
  /// 写入，翻章后的那次异步落盘若未及时完成（或被 mounted 守卫丢弃），
  /// 重进会回放上次会话的旧位置。
  void _persistProgressNow() {
    // 内容尚未就绪（加载失败/初次进入未完成）时不写盘，避免用空状态覆盖
    // 已有的有效进度。
    if (_paragraphs.isEmpty) return;
    final chapters = _effectiveChapters;
    if (chapters.isEmpty) return;
    final idx = _chapterIndex.clamp(0, chapters.length - 1);
    final total = _pagination?.pages.length ?? 0;
    final page = (_currentPage < 0 && total > 0)
        ? total - 1
        : _currentPage.clamp(0, total > 0 ? total - 1 : 0);
    unawaited(_progress.save(
      widget.novelId,
      chapters[idx].id,
      page,
      idx,
      charOffset: _pagination != null ? _charOffsetForPage(page) : null,
      totalChapters: _effectiveChapters.length,
    ));
  }

  /// 把当前书阅读进度静默上传到 WebDAV（best-effort）。
  ///
  /// 触发点：阅读器退出（dispose）；云端领先时不覆盖（防回退），
  /// 本地领先/无远端记录时上传。未配置云同步 / 网络失败静默返回 false。
  Future<bool> _pushProgressToCloud() async {
    try {
      final chapters = _effectiveChapters;
      if (chapters.isEmpty || _paragraphs.isEmpty) return false;
      final idx = _chapterIndex.clamp(0, chapters.length - 1);
      final total = _pagination?.pages.length ?? 0;
      final page = (_currentPage < 0 && total > 0)
          ? total - 1
          : _currentPage.clamp(0, total > 0 ? total - 1 : 0);
      return await NovelProgressSyncService().pushOne(
        widget.novelId,
        NovelProgressPoint(
          novelId: widget.novelId,
          chapterIndex: idx,
          charOffset: _pagination != null ? _charOffsetForPage(page) : null,
          page: page,
        ),
      );
    } on Object {
      return false;
    }
  }

  /// 章节阅读进度达到「已看」阈值时标记当前章已读。
  ///
  /// 阈值取自 [GeneralSettingsStore.watchedThresholdPercent]（默认 90）。
  /// 已读章节由 [MediaWatchedManager] 统一记录（与详情页 isRead 共用），
  /// `markWatched` 本身幂等，此处额外用 `isWatched` 跳过已读章节。
  void _maybeMarkChapterWatched(int page) {
    if (_isLocalMode) return; // 本地模式只有单「章」，不标记已读。
    final total = _pagination?.pages.length ?? 0;
    if (total <= 0) return;
    final ratio = (page + 1) / total;
    final threshold = GeneralSettingsStore.instance.watchedThresholdPercent;
    if (!progressReachesWatchedThreshold(ratio, threshold)) return;
    try {
      final watched = context.read<MediaWatchedManager>();
      if (watched.isWatched(widget.novelId, _chapterIndex)) return;
      unawaited(watched.markWatched(widget.novelId, _chapterIndex));
    } catch (_) {
      // Manager 不可用时静默忽略。
    }
  }

  // ─────────────────────── 导航 ───────────────────────

  /// 音量键翻页（Android / 鸿蒙）：音量上 = 上一页、音量下 = 下一页，
  /// 翻页/滚动模式均生效（复用 [_goNextPage]/[_goPrevPage] 的模式分派）。
  final VolumeKeyListener _volumeKeyListener = VolumeKeyListener();

  /// 按偏好挂载/卸载音量键原生拦截。调用点：[_init]、[_onPrefsChanged]
  /// （偏好变化后即时生效）、dispose（恢复系统默认音量键行为）、
  /// TTS 状态变化（朗读中不拦截，音量键恢复系统调音量）。
  Future<void> _syncVolumeKey() async {
    final bool ttsActive = _tts.state != NovelTtsState.stopped;
    // 音量键拦截走原生通道（Android dispatchKeyEvent / 鸿蒙 inputConsumer），
    // 其它平台无实现。
    final bool want = _prefs.volumeKeyPageTurn &&
        (PlatformService.instance.isAndroid ||
            PlatformService.instance.isOHOSPhone) &&
        !ttsActive;
    try {
      if (want) {
        await _volumeKeyListener.start(
          onVolumeDown: _goNextPage,
          onVolumeUp: _goPrevPage,
        );
        AppLog.instance.i('[小说音量键] 已开启原生拦截（音量下=下一页/音量上=上一页）');
      } else {
        await _volumeKeyListener.stop();
        AppLog.instance.i('[小说音量键] 已关闭原生拦截'
            '${ttsActive ? '（朗读中，音量键用于调节音量）' : ''}');
      }
    } on Object catch (e) {
      // 原生通道未就绪/订阅异常：不阻塞阅读，写日志便于实机排查。
      AppLog.instance.e('[小说音量键] 同步失败: $e');
    }
  }

  void _goNextPage() {
    if (_loading || _chapterLoading) return;
    if (_prefs.pageAnimation.isScroll) {
      _scrollByPage(1);
      return;
    }
    _pageKey.currentState?.nextPage();
  }

  void _goPrevPage() {
    if (_loading || _chapterLoading) return;
    if (_prefs.pageAnimation.isScroll) {
      _scrollByPage(-1);
      return;
    }
    _pageKey.currentState?.previousPage();
  }

  void _scrollByPage(int dir) {
    final sc = _scrollController;
    if (sc == null || !sc.hasClients) return;
    final h = sc.position.viewportDimension;
    final target = (sc.offset + dir * h)
        .clamp(0.0, sc.position.maxScrollExtent)
        .toDouble();
    sc.animateTo(target, duration: AppTokens.durFast, curve: Curves.easeInOut);
  }

  void _goNextChapter() {
    final total = _effectiveChapters.length;
    if (_chapterIndex < total - 1) {
      _chapterIndex++;
      // 翻到下一章即同步落盘「新章节 · 首页」，不等章节内容异步加载完成。
      // 否则若此时退出（route pop），那次依赖 fetched/mounted 的落盘可能
      // 未执行，重进会回放上一章末页（见 _persistProgressNow）。
      _currentPage = 0;
      _saveProgress(0);
      if (_isLocalMode) {
        _loadLocalText();
      } else {
        _loadChapter(_chapterIndex);
      }
      return;
    }
    // 本地模式读完最后一章：无缝接入在线内容继续阅读。
    if (_isLocalMode) {
      unawaited(_continueOnlineLocal());
    }
  }

  /// 本地内容读完自动接续在线（无缝）：抓在线目录 → 定位续读点 →
  /// pushReplacement 替换为在线阅读器。失败时提示并允许重试。
  Future<void> _continueOnlineLocal() async {
    if (_localToOnlineTriggered) return;
    _localToOnlineTriggered = true;
    final bool switched = await continueOnlineAfterLocal(
      context,
      sourceType: SourceType.novelSource,
      contentId: widget.novelId,
      title: widget.title,
      sourceId: widget.sourceId,
      localChapters: _effectiveChapters,
      localLastIndex: _chapterIndex,
    );
    // 切换未发生（无在线源 / 已是最新 / 抓取失败）：复位触发位以便重试。
    if (!switched && mounted) {
      setState(() => _localToOnlineTriggered = false);
    }
  }

  void _goPrevChapter({bool toLastPage = false}) {
    if (_chapterIndex > 0) {
      _chapterIndex--;
      // 同步把目标页写进内存：上一章首页(0) 或上一章末页(哨兵 -1，由
      // _buildReader 的哨兵校正落盘)，保证翻章过程中状态一致、退出能正确回放。
      _currentPage = toLastPage ? -1 : 0;
      if (_isLocalMode) {
        _loadLocalText(restorePage: toLastPage ? -1 : 0);
      } else {
        _loadChapter(_chapterIndex, restorePage: toLastPage ? -1 : 0);
      }
    }
  }

  /// 按 TTS 状态同步通知栏媒体会话（audio_service）。
  ///
  /// - 朗读中（playing / paused）：attach 会话并注册播放/暂停/上句/下句回调，
  /// 标题随章节变化刷新；暂停保持会话（通知栏可恢复）。
  /// - 停止：detach 会话、移除通知（播放页仍在栈上，下次朗读重新 attach）。
  ///
  /// 由 [_onTtsChanged] 统一驱动（state / currentIndex 变化都会触发）。
  void _syncTtsAudioService() {
    final bool stopped = _tts.state == NovelTtsState.stopped;
    final List<Episode> chs = _effectiveChapters;
    final String chapterTitle =
        chs.isEmpty ? '' : chs[_chapterIndex.clamp(0, chs.length - 1)].title;
    final String title =
        chapterTitle.isEmpty ? widget.title : '${widget.title} · $chapterTitle';
    if (stopped) {
      if (_ttsAudioToken != null) {
        AudioPlaybackService.instance.detach(_ttsAudioToken!);
        _ttsAudioToken = null;
        _ttsAudioTitle = null;
      }
      return;
    }
    if (_ttsAudioToken == null || _ttsAudioTitle != title) {
      _ttsAudioToken = AudioPlaybackService.instance.attach(
        AudioPlaybackSession(
          id: 'tts:${widget.novelId}',
          title: title,
          artist: widget.title,
          // TTS 无进度概念：不提供 position/duration 流，通知栏不显示进度条。
          playingStream: _ttsPlayingStream(_tts),
          onPlay: () => _tts.resume(),
          onPause: () => _tts.pause(),
          onSeek: (_) async {}, // 无进度，seek 为 no-op。
          onNext: () => _tts.next(),
          onPrev: () => _tts.prev(),
        ),
      );
      _ttsAudioTitle = title;
    }
  }

  /// TTS 状态变化回调（currentIndex / state 变化）。
  ///
  /// - 高亮：build 直接读取 `_tts.currentIndex`，随本回调的 [setState] 自动刷新。
  /// - 自动定位：翻页模式下，朗读进度推进到某段落时，自动把页面翻到该段落所在页
  /// （"自动定位到朗读的页面"）；滚动模式段落连续排版，交给高亮与用户手势。
  void _onTtsChanged() {
    if (!mounted) return;
    final String? ttsError = _tts.takeLastError();
    if (ttsError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).ttsPlaybackFailed)),
      );
    }
    // 通知栏会话同步（stopped 时 detach、playing/paused 时 attach/刷新标题）。
    _syncTtsAudioService();
    // TTS 朗读中音量键恢复系统调音量（不翻页），状态变化时重新同步拦截。
    unawaited(_syncVolumeKey());
    if (_tts.state == NovelTtsState.stopped) return;
    if (_tts.state != NovelTtsState.playing) {
      // 暂停：只刷新 UI（暂停图标 / 按钮），不跟随滚动。
      setState(() {});
      return;
    }
    final int idx = _tts.currentIndex;
    final pages = _pagination?.pages;
    if (pages == null || pages.isEmpty) return;
    if (_prefs.pageAnimation.isScroll) {
      // 滚动模式：刷新高亮 + 自动滚动跟随当前朗读段，
      // 由 itemBuilder 挂 _ttsParagraphKey 的段定位。
      setState(() {});
      _scheduleTtsParagraphScroll();
      return;
    }
    int? target;
    for (int i = 0; i < pages.length; i++) {
      if (pages[i].any((item) =>
          item is NovelTextLineItem && item.line.paragraphIndex == idx)) {
        target = i;
        break;
      }
    }
    if (target != null && target != _currentPage) {
      _pageKey.currentState?.jumpToPage(target);
    }
    // 高亮随 currentIndex 变化刷新（即使未翻页也要重绘选中段）。
    setState(() {});
  }

  /// 滚动模式 TTS 跟随：帧后把当前朗读段滚动到可视区
  /// （约视口上 1/3，留出下文空间），随朗读进度自动滚动适应语速。
  void _scheduleTtsParagraphScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_tts.state != NovelTtsState.playing) return;
      final BuildContext? paragraphCtx = _ttsParagraphKey.currentContext;
      if (paragraphCtx == null) return;
      try {
        Scrollable.ensureVisible(
          paragraphCtx,
          alignment: 0.3,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
      } on Object {
        // ensureVisible 失败（如正在重建）忽略，下一段切换会再次触发。
      }
    });
  }

  /// TTS 模式下点击某一段落：跳转到该段落开始朗读。
  void _onParagraphTapped(int globalParagraphIndex) {
    if (_paragraphs.isEmpty) return;
    final clamped = globalParagraphIndex.clamp(0, _paragraphs.length - 1);
    // 找到该段落属于哪一页（通过分页数据）。
    final pages = _pagination?.pages;
    if (pages != null) {
      for (int i = 0; i < pages.length; i++) {
        if (pages[i].any((item) =>
            item is NovelTextLineItem && item.line.paragraphIndex == clamped)) {
          if (i != _currentPage) {
            _pageKey.currentState?.jumpToPage(i);
          }
          break;
        }
      }
    }
    // 从点击的段落重新开始 TTS 朗读。
    // 必须走 [_speakChapter]：它负责注入跨章续读回调与 autoNext，
    // 直接调 `_tts.speak` 会让「点段落起播」的会话永远不跨章。
    _tts.setBackground(_prefs.ttsBackground);
    _tts.setRate(_prefs.ttsSpeechRate);
    unawaited(_speakChapter(clamped, sleepTimer: _prefs.ttsSleepTimer));
    setState(() {});
  }

  void _toggleUi() {
    setState(() {
      _uiVisible = !_uiVisible;
      if (!_uiVisible) _showInlineSettings = false;
      // 显示控制面板时自动收起选区工具条，避免被底栏遮挡。
      if (_uiVisible && _showSelectionToolbar) {
        _selectionController.clearSelection();
        _showSelectionToolbar = false;
      }
    });
  }

  void _toggleInlineSettings() {
    setState(() => _showInlineSettings = !_showInlineSettings);
  }

  /// 滑块拖动中的轻量预览：只更新内存 [_prefs]，不 setState / 不重分页 /
  /// 不落盘——长章节整章重分页与偏好落盘都是重操作，逐拖动帧触发会连续
  /// 阻塞 UI 线程（「长内容设置字号卡退」的根因）。松手由 [_onPrefsChanged]
  /// 一次性应用（重分页 + 落盘）。滑块拇指/数值标签由 [_SliderRow] 本地
  /// 状态驱动，无需父级重建。
  void _onPrefsPreview(NovelReaderPreferences next) {
    _prefs = next;
  }

  Future<void> _onPrefsChanged(NovelReaderPreferences next) async {
    final animationChanged = next.pageAnimation != _prefs.pageAnimation;
    final convertChanged = next.chineseConvert != _prefs.chineseConvert;
    final autoPageChanged = next.autoPageInterval != _prefs.autoPageInterval;
    final volumeKeyChanged = next.volumeKeyPageTurn != _prefs.volumeKeyPageTurn;
    // 章末自动接续开关切换：关掉后要把已经拼进列表的后续章段收回，
    // 否则仍停留在「已接续」的位置却不再跟随主导章，选区/进度会错位。
    final autoNextChanged =
        next.scrollAutoNextChapter != _prefs.scrollAutoNextChapter;
    // 记录本次真正改动的字段为「本书单独设置」，未动过的字段继续跟随总设置。
    _overrideKeys.addAll(novelPrefsChangedKeys(_prefs, next));
    _prefs = next;
    if (volumeKeyChanged) {
      // 音量键开关即时生效。
      unawaited(_syncVolumeKey());
    }
    // 任何阅读设置变化都使分页缓存失效（字号/行距/段距/边距/字体等不会 bump
    // _contentVersion，但会影响分页高度，必须靠 _prefsVersion 触发重新分页）。
    _prefsVersion++;
    await _store.save(widget.novelId, next, overrideKeys: _overrideKeys);
    if (convertChanged && _rawParagraphs.isNotEmpty) {
      _refreshConvert();
    } else if (animationChanged && _paragraphs.isNotEmpty) {
      _contentVersion++;
      _setupControllers(restorePage: _currentPage);
    } else {
      if (autoNextChanged && _prefs.pageAnimation.isScroll) {
        // 收回已追加的后续章段：按「当前章内比例」把视图恢复到同一处，
        // 并在恢复期间封锁进度写盘——否则 jumpTo 会先把页码记成 0，
        // 表现为「一切换开关进度就丢了」。
        final ScrollController? sc = _scrollController;
        final double ratio = (sc != null && sc.hasClients)
            ? _chapterScrollRatio(sc.position)
            : _scrollFraction;
        _resetScrollSegments();
        _restoringPage = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            _restoringPage = false;
            return;
          }
          final ScrollController? sc2 = _scrollController;
          if (sc2 != null && sc2.hasClients) {
            final double max = sc2.position.maxScrollExtent;
            sc2.jumpTo((ratio * max).clamp(0.0, max));
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _restoringPage = false;
          });
        });
      }
      if (mounted) setState(() {});
    }
    if (autoPageChanged) {
      // 间隔变更后若之前已暂停，保持暂停；否则按新间隔重启。
      _applyAutoPage();
    }
  }

  // ─────────────────────── 点击区域（FR-4.2 五布局） ───────────────────────

  void _onTapUp(TapUpDetails details, Size size) {
    if (_showInlineSettings) {
      _toggleInlineSettings();
      return;
    }
    // 选区工具条可见时，点按任意处收起工具条并清空选区。
    if (_showSelectionToolbar) {
      // 吞掉长按松手后极短窗口内（250ms）紧随的那次 tap-up，避免刚建立的
      // 选区被误清空（闪一下）；窗口之外的点击是用户主动收起，照常清空——
      // 否则会吞掉用户退出工具栏的第一下，表现为「要点两下才退出」。
      final DateTime? sinkAt = _selectionJustConfirmedAt;
      if (sinkAt != null &&
          DateTime.now().difference(sinkAt) < _kSelectionTapSinkWindow) {
        _selectionJustConfirmedAt = null;
        return;
      }
      _selectionJustConfirmedAt = null;
      _selectionController.clearSelection();
      setState(() => _showSelectionToolbar = false);
      return;
    }
    final action = TapZoneResolver.resolve(
      layout: _prefs.tapZoneLayout,
      invert: _prefs.tapZoneInvert,
      isVertical: _prefs.pageAnimation.isScroll,
      pos: details.localPosition,
      size: size,
    );
    switch (action) {
      case TapZoneAction.toggle:
        _toggleUi();
      case TapZoneAction.prev:
        _goPrevPage();
      case TapZoneAction.next:
        _goNextPage();
    }
  }

  /// 显示点按区域预览弹窗：半透明展示当前布局的各区域及对应操作。
  void _showTapZonePreview(AppLocalizations l10n) {
    final layout = _prefs.tapZoneLayout;
    final invert = _prefs.tapZoneInvert;
    final isVertical = _prefs.pageAnimation.isScroll;

    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder:
              (BuildContext ctx2, Function(void Function()) setDialogState) {
            return AppAlertDialog(
              title: Text(l10n.tapZonePreview),
              content: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 280, maxHeight: 420),
                child: _TapZonePreviewOverlay(
                  layout: layout,
                  invert: invert,
                  isVertical: isVertical,
                  l10n: l10n,
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ─────────────────────── 亮度手势 ───────────────────────

  void _onBrightnessDragStart(DragStartDetails d) {
    final w = context.size?.width ?? MediaQuery.sizeOf(context).width;
    if (d.globalPosition.dx >= w / 3) return;
    _brightnessDragStart = _brightness;
    _brightnessDragDelta = 0;
    setState(() => _showBrightnessIndicator = true);
  }

  void _onBrightnessDragUpdate(DragUpdateDetails d) {
    if (_brightnessDragStart == null) return;
    _brightnessDragDelta += d.delta.dy;
    final h = MediaQuery.sizeOf(context).height;
    final next =
        (_brightnessDragStart! + (-_brightnessDragDelta / h)).clamp(0.0, 1.0);
    _setBrightness(next);
  }

  void _onBrightnessDragEnd(DragEndDetails d) {
    _brightnessDragStart = null;
    _brightnessDragDelta = 0;
    if (mounted) setState(() => _showBrightnessIndicator = false);
  }

  Future<void> _setBrightness(double value) async {
    _brightness = value;
    _brightnessChangedByUs = true;
    if (mounted) setState(() {});
    try {
      await _brightnessPlugin.setApplicationScreenBrightness(value);
    } on Object {
      // 部分平台可能不支持亮度调节，静默忽略。
    }
  }

  // ─────────────────────── 下滑切书签手势 ───────────────────────

  /// 下滑起点：仅分页模式启用；左 1/3 屏留给亮度手势。
  /// 方向判定延后到 update（DragStartDetails 无 velocity，且纵向拖拽在手势
  /// 竞技场中被横向翻页识别器让出时才回调——此时已是纵向手势，只需防误触）。
  void _onBookmarkSwipeStart(DragStartDetails d) {
    if (!_bookmarkSwipeEnabled) return;
    final w = context.size?.width ?? MediaQuery.sizeOf(context).width;
    if (d.globalPosition.dx < w / 3) return; // 与亮度手势区域互斥
    _bookmarkSwipePending = true;
    _bookmarkSwipeActive = false;
    _bookmarkSwipeCancelled = false;
    _bookmarkSwipeDy = 0;
    _bookmarkSwipeDx = 0;
    // 预取当前位置是否已有书签：决定本次下滑是添加还是取消（提示条文案同步）。
    unawaited(_refreshQuickBookmarkState());
  }

  void _onBookmarkSwipeUpdate(DragUpdateDetails d) {
    if (!_bookmarkSwipePending && !_bookmarkSwipeActive) return;
    final dx = d.delta.dx;
    final dy = d.delta.dy;
    if (!_bookmarkSwipeActive) {
      // 待定态：累计方向，直到明确「纵向且向下」才激活（判定：
      // dy > 0 且 absY > absX * ratio，页面随指下移）。
      _bookmarkSwipeDx += dx;
      _bookmarkSwipeDy += dy;
      if (_bookmarkSwipeDx.abs() > _bookmarkSwipeDy.abs() * 2) {
        // 横向主导 → 用户实际想翻页，放弃。
        _bookmarkSwipePending = false;
        _bookmarkSwipeActive = false;
        _bookmarkSwipeCancelled = false;
        _bookmarkSwipeDy = 0;
        _bookmarkSwipeDx = 0;
        return;
      }
      // 尚未过阈值时上滑回到原位即取消（允许反悔，回到原点）。
      if (_bookmarkSwipeDy <= 0) {
        _bookmarkSwipePending = false;
        _bookmarkSwipeActive = false;
        _bookmarkSwipeCancelled = true;
        _bookmarkSwipeDy = 0;
        _bookmarkSwipeDx = 0;
        if (mounted) setState(() {});
        return;
      }
      if (_bookmarkSwipeDy > 0 &&
          _bookmarkSwipeDy > _bookmarkSwipeDx.abs() * 1.5) {
        _bookmarkSwipeActive = true;
        _bookmarkSwipeCancelled = false;
        if (mounted) setState(() {});
        return;
      }
      return;
    }
    // 激活态：累计位移（含向上回拖，dy 可能变负）；回拖到阈值线之上即取消。
    _bookmarkSwipeDy = _bookmarkSwipeDy + dy;
    final h = MediaQuery.sizeOf(context).height;
    final threshold = h * _bookmarkSwipeThresholdRatio;
    _bookmarkSwipeCancelled = _bookmarkSwipeDy < threshold;
    if (mounted) setState(() {});
  }

  void _onBookmarkSwipeEnd(DragEndDetails d) async {
    if (!_bookmarkSwipePending && !_bookmarkSwipeActive) return;
    final h = MediaQuery.sizeOf(context).height;
    final threshold = h * _bookmarkSwipeThresholdRatio;
    final reached = _bookmarkSwipeActive &&
        _bookmarkSwipeDy >= threshold &&
        !_bookmarkSwipeCancelled;
    _bookmarkSwipePending = false;
    _bookmarkSwipeActive = false;
    _bookmarkSwipeCancelled = false;
    _bookmarkSwipeDy = 0;
    _bookmarkSwipeDx = 0;
    if (mounted) setState(() {});
    if (reached) {
      await _addBookmarkQuick();
    }
  }

  /// 快捷切换（修订）：当前位置已有书签时下滑即取消该书签，
  /// 否则跳过备注弹窗直接保存当前页书签（与工具栏「加书签」弹窗路径
  /// 区分；下滑是快捷操作，打断弹窗反而碍事）。
  Future<void> _addBookmarkQuick() async {
    final l10n = AppLocalizations.of(context);
    // 已有同章同页书签 → 取消之。
    final existing = await _bookmarks.listFor(widget.novelId);
    NovelBookmark? hit;
    for (final b in existing) {
      if (b.chapterIndex == _chapterIndex && b.page == _currentPage) {
        hit = b;
        break;
      }
    }
    if (hit != null) {
      await _bookmarks.remove(hit.key);
      if (!mounted) return;
      setState(() => _currentPosHasBookmark = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.novelBookmarkRemoved)),
      );
      return;
    }
    final String chapterId;
    final String chapterTitle;
    final chapters = _effectiveChapters;
    if (_isLocalMode && _parsedChapterEpisodes == null) {
      chapterId = 'local';
      chapterTitle = '';
    } else {
      if (chapters.isEmpty) return;
      final chapter = chapters[_chapterIndex.clamp(0, chapters.length - 1)];
      chapterId = chapter.id;
      chapterTitle = chapter.title;
    }
    final bm = NovelBookmark(
      novelId: widget.novelId,
      chapterIndex: _chapterIndex,
      chapterId: chapterId,
      chapterTitle: chapterTitle,
      page: _currentPage,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _bookmarks.add(bm);
    if (!mounted) return;
    setState(() => _currentPosHasBookmark = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.bookmarkAdded)),
    );
  }

  /// 当前章节页是否已有快捷书签（决定下滑提示与行为：添加 / 取消）。
  bool _currentPosHasBookmark = false;

  /// 异步刷新 [_currentPosHasBookmark]（手势开始时预取，Hive 缓存读取很快）。
  Future<void> _refreshQuickBookmarkState() async {
    final list = await _bookmarks.listFor(widget.novelId);
    if (!mounted) return;
    final has = list
        .any((b) => b.chapterIndex == _chapterIndex && b.page == _currentPage);
    if (has != _currentPosHasBookmark) {
      setState(() => _currentPosHasBookmark = has);
    }
  }

  /// 下滑切书签：顶部提示条。手势进行中显示「继续下滑添加书签」，
  /// 超过阈值后变「松开添加书签」。覆盖在页面上方（页面已随指下移露出背景）。
  Widget _buildBookmarkSwipeHint(Color bg, Color textColor) {
    final h = MediaQuery.sizeOf(context).height;
    final threshold = h * _bookmarkSwipeThresholdRatio;
    final ready = _bookmarkSwipeDy >= threshold;
    final l10n = AppLocalizations.of(context);
    return Positioned(
      top: 16 + _bookmarkSwipeDy,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceMd,
              vertical: AppTokens.spaceXs,
            ),
            decoration: BoxDecoration(
              color: bg.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  ready
                      ? (_currentPosHasBookmark
                          ? Icons.bookmark_remove_rounded
                          : Icons.bookmark_added_rounded)
                      : Icons.bookmark_add_rounded,
                  size: 18,
                  color: ready
                      ? const Color(0xFF16A34A)
                      : textColor.withValues(alpha: 0.7),
                ),
                const SizedBox(width: AppTokens.spaceXs),
                Text(
                  ready
                      ? (_currentPosHasBookmark
                          ? l10n.novelSwipeReleaseRemove
                          : l10n.novelSwipeRelease)
                      : l10n.novelSwipeKeepGoing,
                  style: TextStyle(fontSize: 13, color: textColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────── 构建 ───────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = _prefs.resolveBackgroundColor(isDark);
    final textColor = _prefs.resolveTextColor(bg);
    final l10n = AppLocalizations.of(context);

    // TTS 状态变化时重建 Stack：TTS 激活时底部栏内嵌朗读控件（避免重叠）。
    return Scaffold(
      backgroundColor: bg,
      body: ListenableBuilder(
        listenable: _tts,
        builder: (BuildContext context, Widget? _) {
          final ttsActive = _tts.state != NovelTtsState.stopped;
          return Stack(
            children: <Widget>[
              _buildContent(l10n, bg, textColor),
              if (_uiVisible)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _buildTopBar(l10n, bg),
                ),
              if (_uiVisible)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _buildBottomBar(l10n, bg, ttsActive: ttsActive),
                ),
              if (_showBrightnessIndicator) _buildBrightnessIndicator(l10n),
              if (_showInlineSettings)
                _buildInlineSettings(l10n, bg, textColor),
            ],
          );
        },
      ),
    );
  }

  /// TTS 内联控件（嵌入底部栏第二行，替代独立 TTS 栏，避免重叠）。
  /// 包含：上一句/暂停-停止/下一句/睡眠/后台 + 语速滑块。
  Widget _buildTtsControlsInline(AppLocalizations l10n, Color bg) {
    final remaining = _tts.sleepRemaining;
    final rate = _tts.rate;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.skip_previous_rounded, size: 20),
              tooltip: l10n.ttsPrevSentence,
              visualDensity: VisualDensity.compact,
              onPressed: () => _tts.prev(),
              padding: const EdgeInsets.all(AppTokens.spaceXs),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            IconButton(
              icon: Icon(
                  _tts.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 20),
              tooltip: l10n.ttsPauseOrResume,
              visualDensity: VisualDensity.compact,
              onPressed: () {
                if (_tts.isPlaying) {
                  _tts.pause();
                } else {
                  _tts.resume();
                }
              },
              padding: const EdgeInsets.all(AppTokens.spaceXs),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            IconButton(
              icon: const Icon(Icons.stop_rounded, size: 20),
              tooltip: l10n.ttsExit,
              visualDensity: VisualDensity.compact,
              onPressed: () => _tts.stop(),
              padding: const EdgeInsets.all(AppTokens.spaceXs),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            IconButton(
              icon: const Icon(Icons.skip_next_rounded, size: 20),
              tooltip: l10n.ttsNextSentence,
              visualDensity: VisualDensity.compact,
              onPressed: () => _tts.next(),
              padding: const EdgeInsets.all(AppTokens.spaceXs),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            IconButton(
              icon: const Icon(Icons.timer_rounded, size: 18),
              tooltip: l10n.ttsSleepTimer,
              visualDensity: VisualDensity.compact,
              onPressed: _showSleepTimerPicker,
              padding: const EdgeInsets.all(AppTokens.spaceXs),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            IconButton(
              icon: Icon(
                  _tts.backgroundMode
                      ? Icons.headset_rounded
                      : Icons.headset_off_rounded,
                  size: 18),
              tooltip: l10n.novelTtsBackground,
              visualDensity: VisualDensity.compact,
              onPressed: () {
                final next = !_tts.backgroundMode;
                _tts.setBackground(next);
                _onPrefsChanged(_prefs.copyWith(ttsBackground: next));
              },
              padding: const EdgeInsets.all(AppTokens.spaceXs),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
        Row(
          children: <Widget>[
            const Icon(Icons.speed_rounded, size: 16),
            const SizedBox(width: AppTokens.spaceXs),
            Expanded(
              child: Slider(
                value: rate,
                min: 0.5,
                max: 2.0,
                divisions: 30,
                onChangeStart: (_) => AppHaptics.light(),
                onChanged: (v) => _tts.setRate(v),
              ),
            ),
            SizedBox(
              width: 38,
              child: Text(
                '${rate.toStringAsFixed(1)}x',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
        if (remaining != null)
          Padding(
            padding: const EdgeInsets.only(top: AppTokens.spaceXxs),
            child: Text(
              l10n.ttsSleepRemaining(
                remaining.inMinutes,
                remaining.inSeconds % 60,
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  /// 睡眠定时选择（#5）：0 关闭 / 预设 / 自定义分钟。朗读控制栏入口。
  Future<void> _showSleepTimerPicker() async {
    final l10n = AppLocalizations.of(context);
    final picked = await _pickSleepMinutes(
      context: context,
      l10n: l10n,
      current: _tts.sleepRemaining?.inMinutes ?? 0,
    );
    if (picked != null && mounted) {
      _tts.startSleepTimer(picked);
      // 与设置面板一致：写回 _prefs（持久化），避免重启后丢失。
      _onPrefsChanged(_prefs.copyWith(ttsSleepTimer: picked));
    }
  }

  Widget _buildContent(AppLocalizations l10n, Color bg, Color textColor) {
    if (_loading) {
      // 加载态底色用当前背景色，避免深色模式下白色底板刺眼（项 7 双保险）。
      return Container(
          color: bg, child: const Center(child: AppLoadingIndicator()));
    }
    if (_error != null) {
      // 验证拦截态：重试按钮改走验证页，完成后重载本章（Cookie 已回灌）。
      final verifyError = _verificationError;
      if (verifyError != null && !_isLocalMode) {
        return _CenterMessage(
          icon: Icons.error_rounded,
          message: l10n.errorVerification,
          onRetry: () async {
            final shouldRetry = await navigateToVerification(
              context,
              url: verifyError.url,
              exception: verifyError,
            );
            if (!mounted || !shouldRetry) return;
            setState(() => _verificationError = null);
            await _loadChapter(_chapterIndex, restorePage: _currentPage);
          },
        );
      }
      // 反爬拦截态（源声明 useWebview）：打开真浏览器抓取本章渲染后 HTML 回灌解析。
      final captureRequest = _htmlCaptureRequest;
      if (captureRequest != null && !_isLocalMode) {
        return _CenterMessage(
          icon: Icons.error_rounded,
          message: l10n.captureHint,
          onRetry: () async {
            final outcome = await navigateToHtmlCapture(
              context,
              request: captureRequest,
            );
            if (!mounted || outcome?.hasRenderedHtml != true) return;
            await _loadChapterWithRenderedHtml(
              _chapterIndex,
              outcome!.renderedHtml!,
              restorePage: _currentPage,
            );
          },
        );
      }
      return _CenterMessage(
        icon: Icons.error_rounded,
        message: _isLocalMode
            ? l10n.localFileLoadFailed
            : (_isResolveError ? l10n.resolveFailed(_error!) : l10n.loadFailed),
        onRetry: _isLocalMode
            ? () => _loadLocalText(restorePage: _currentPage)
            : () => _loadChapter(_chapterIndex, restorePage: _currentPage),
      );
    }
    if (_paragraphs.isEmpty) {
      return _CenterMessage(
          icon: Icons.article_rounded, message: l10n.noContent);
    }
    return _buildReader(bg, textColor);
  }

  Widget _buildReader(Color bg, Color textColor) {
    // 正文页眉/标题取「实际章节列表」：单 EPUB 用解析出的章节，其余用传入章节，
    // 保证本地 EPUB 也能在正文显示当前章节标题（修复「分章后看不到章名」）。
    final bodyChapters = _effectiveChapters;
    final String chapterTitleForBody = bodyChapters.isEmpty
        ? ''
        : bodyChapters[_chapterIndex.clamp(0, bodyChapters.length - 1)].title;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        // 分页缓存签名：仅在这些输入真正变化时重新分页，否则复用上一次结果。
        // 关键：翻页动画每帧只触发 NovelAnimatedPageView 自身重建（其 State 内的
        // setState），不会重建到这里；但 _onPageChanged → setState 与
        // FavoritesManager 通知都会触发本 reader 重建 → 若每次都重新分页整章，
        // 会在翻页瞬间产生明显卡顿，并使翻页动画被重型计算抢占、看起来「无动画」。
        final scaler = MediaQuery.textScalerOf(context);
        final dir = Directionality.of(context);
        // 双页模式：翻页模式 + 用户开启 + 宽屏（宽 > 高）时生效——
        // 每页按半宽排版，屏幕左右并排显示两页（对齐实体书摊开形态）。
        final bool twoPage = _prefs.twoPageMode &&
            !_prefs.pageAnimation.isScroll &&
            constraints.maxWidth > constraints.maxHeight;
        final sig =
            '$_contentVersion|$_prefsVersion|$_chapterIndex|${w.round()}x${h.round()}|$scaler|$dir|$chapterTitleForBody|${widget.title}|two=$twoPage';
        final bool sigChanged = _paginationSig != sig;
        final int prevChapterIndex = _paginationChapterIndex;
        if (_pagination == null || sigChanged) {
          // 双页时按半宽减中缝分页；单页沿用全宽。
          final BoxConstraints layoutConstraints = twoPage
              ? BoxConstraints(
                  maxWidth: (constraints.maxWidth - _kTwoPageGutter) / 2,
                  maxHeight: constraints.maxHeight,
                )
              : constraints;
          _pagination = NovelPaginator.paginate(
            blocks: _paragraphs,
            constraints: layoutConstraints,
            prefs: _prefs,
            context: context,
            chapterTitle: chapterTitleForBody,
            bookName: widget.title,
          );
          _paginationSig = sig;
          _paginationChapterIndex = _chapterIndex;
          _twoPageActive = twoPage;
          // 本章页数入整本校准缓存（覆盖旧值——同章重新分页以新值为准）。
          _chapterPageCounts[_chapterIndex] = _pagination!.pages.length;
          // 分页真正变化时（章节 / 偏好 / 尺寸），帧后注入选区控制器并加载划线。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _paginationChapterIndex == _chapterIndex) {
              _bindSelection();
            }
          });
        }

        // 章内字符偏移恢复（抗字号/边距/排版变化）。
        // 仅在有待恢复偏移且分页已就绪时执行一次；用偏移把阅读位置
        // 重新映射成当前分页下的页码（或滚动模式的等效页），而非旧的页码。
        // 消费后立即清 null，避免后续 build（如旋转屏幕）重复跳页。
        if (_savedCharOffset != null) {
          final resolved = _pageForCharOffset(_savedCharOffset!);
          _currentPage = resolved;
          if (_prefs.pageAnimation.isScroll) {
            _restoreScrollPosition(resolved);
          }
          // 用当前分页（已就绪）与当前章节，把恢复出的位置重新落盘。
          // 否则若本次进入未触发任何翻页事件（initial page / 纯恢复），
          // 持久化进度会停留在上次会话的旧值，退出重进会回放旧位置
          //（表现为「翻到首页 → 重进却落到上一章末页」）。
          _saveProgress(resolved);
          _savedCharOffset = null;
          // 搜索跳转到达：命中页此刻才渲染就绪，现在启动高亮计时器
          // （普通进度恢复时无关键词，不会走到这里）。
          if (_searchKeyword != null || _searchRegex != null) {
            _startSearchHighlightTimer();
          }
        }

        // 检测分页结果是否变化（跨章/改偏好/旋转屏幕时变化）。
        // _pagination 可能在本帧的 layout 阶段才被 LayoutBuilder 赋值，
        // 而 _buildProgressSlider 已在 build 阶段读取了旧值。需要 schedule 一帧
        // 让进度条重建以获取最新分页数据（详见 _loadChapter 时序注释）。
        // 注意：相邻两章页数可能相同，仅比较页数长度不够，必须同时检测章节下标变化，
        // 否则会残留上一章的分页（总页数/当前页显示正确但内容错位）。
        // 这里用「缓存前的旧章节下标」判断跨章，并用 sigChanged 覆盖「同章但
        // 改了字号/边距等导致分页变化」的情况，确保进度条/分页始终与最新输入一致。
        final chapterChanged = prevChapterIndex != _chapterIndex;
        final paginationChanged = chapterChanged || sigChanged;

        if (_pagination!.isEmpty) {
          return _CenterMessage(
            icon: Icons.article_rounded,
            message: AppLocalizations.of(context).noContent,
          );
        }

        final pages = _pagination!.pages;
        // 哨兵值：restorePage=-1 表示「恢复到本章最后一页」（上一页越界时）。
        if (_currentPage < 0 && pages.isNotEmpty) {
          _currentPage = pages.length - 1;
          // 上一章末页（回上一话）也要落盘，否则退出后该位置丢失，
          // 重进会回放更早的存档（表现为「回到上一章末页」失效）。
          _saveProgress(_currentPage);
        }
        // 同步校正：如果当前页超出范围（比如跨章后 page view 通过
        // didUpdateWidget 重置了 internal index 但未回调 onPageChanged），
        // 强制对齐到合法范围。
        if (_currentPage >= pages.length && pages.isNotEmpty) {
          _currentPage = pages.length - 1;
        }
        final bodyChapters2 = _effectiveChapters;
        final chapterTitle = bodyChapters2.isEmpty
            ? ''
            : bodyChapters2[_chapterIndex.clamp(0, bodyChapters2.length - 1)]
                .title;

        // 分页数据变化时 schedule 一帧刷新，让底部进度条获取最新的
        // total/pages/currentPage（LayoutBuilder 的 builder 在 layout 阶段执行，
        // 晚于 _buildProgressSlider 的 build 阶段读取）。
        if (paginationChanged && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        }

        // 下滑切书签：手势进行中页面随指下移（露出上方背景），
        // 顶部显示提示条；松手超过阈值即落盘书签并复位。
        final double swipeDy = _bookmarkSwipeActive ? _bookmarkSwipeDy : 0;
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(0, swipeDy),
                child: Builder(builder: (context) {
                  // 双页：呈现层把「页」映射为「跨页（spread）」——一个屏幕位
                  // 显示左右两页；进度/存档仍以左页页码为准（onPageChanged 处换算）。
                  final bool twoPage = _twoPageActive && pages.length > 1;
                  final int displayCount =
                      twoPage ? (pages.length + 1) ~/ 2 : pages.length;
                  final int initialDisplay = twoPage
                      ? (_currentPage ~/ 2).clamp(0, displayCount - 1)
                      : _currentPage;
                  Widget buildSinglePage(BuildContext ctx, int p) {
                    final page = pages[p];
                    return _NovelPageWidget(
                      lines: page,
                      prefs: _prefs,
                      bg: bg,
                      textColor: textColor,
                      animation: _prefs.pageAnimation,
                      chapterTitle: chapterTitle,
                      bookName: widget.title,
                      pageIndex: p,
                      totalPages: pages.length,
                      time: _currentTime,
                      batteryLevel: _batteryLevel,
                      headerCenter: _prefs.headerCenter,
                      footerCenter: _prefs.footerCenter,
                      headerFooterColor: _prefs.headerFooterColor,
                      headerFooterMargin: _prefs.headerFooterMargin,
                      ttsCurrentIndex: _tts.currentIndex,
                      ttsActive: _tts.state != NovelTtsState.stopped,
                      searchKeyword: _searchKeyword,
                      searchRegex: _searchRegex,
                      onParagraphTap: _onParagraphTapped,
                      onImageTap: (url, src) =>
                          _showImageViewer(url, src ?? _source),
                      source: _source,
                      bookPageLabel: (p2) => _bookPageLabelFor(p2),
                      selectionController: _selectionController,
                      onSelectionConfirmed: () {
                        if (mounted) {
                          _selectionJustConfirmedAt = DateTime.now();
                          setState(() {
                            _showSelectionToolbar = true;
                            _uiVisible = false; // 显示工具栏时隐藏控制面板
                          });
                        }
                      },
                      onSelectionActiveChanged: (engaged) {
                        // 长按选区激活期间置位 _longPressEngaged，使翻页手势让出指针，
                        // 避免选区拖拽被翻页抢走（「长按一闪即逝」的根因）。
                        // 注意：这里绝不能 setState——置位字段后拖拽手势经
                        // `selectionActive` 闭包读取的是最新字段值，无需重建；而一旦
                        // setState 重建整棵阅读器树，pageBuilder 会重新构建每个文本行
                        // 的 RawGestureDetector，识别器被替换、进行中的长按即刻中断
                        // （表现：选中闪一下就消失）。
                        _longPressEngaged = engaged;
                      },
                    );
                  }

                  return NovelAnimatedPageView(
                    key: _pageKey,
                    contentVersion: _contentVersion,
                    animation: _prefs.pageAnimation,
                    pageCount: displayCount,
                    initialPage: initialDisplay,
                    background: bg,
                    selectionActive: () =>
                        _longPressEngaged ||
                        _selectionController.hasSelection ||
                        _selectionController.isSelecting,
                    pageBuilder: (BuildContext ctx, int displayIndex) {
                      if (!twoPage) return buildSinglePage(ctx, displayIndex);
                      final int left = displayIndex * 2;
                      final int right = left + 1;
                      return Row(
                        children: <Widget>[
                          Expanded(
                            child: left < pages.length
                                ? buildSinglePage(ctx, left)
                                : Container(color: bg), // 奇数页末跨页的右侧留空
                          ),
                          const SizedBox(width: _kTwoPageGutter),
                          Expanded(
                            child: right < pages.length
                                ? buildSinglePage(ctx, right)
                                : Container(color: bg),
                          ),
                        ],
                      );
                    },
                    scrollBuilder: _prefs.pageAnimation.isScroll
                        ? (BuildContext ctx) =>
                            _buildScrollContent(bg, textColor)
                        : null,
                    onPageChanged: twoPage
                        ? (int spreadIdx) {
                            // 双页以「左页」作为当前逻辑页（与漫画双页语义一致）。
                            _onPageChanged(
                                (spreadIdx * 2).clamp(0, pages.length - 1));
                          }
                        : _onPageChanged,
                    onRequestNextChapter: _goNextChapter,
                    onRequestPrevChapter: () =>
                        _goPrevChapter(toLastPage: true),
                    onTapUp: _onTapUp,
                    onVerticalDragStart: _onBrightnessDragStart,
                    onVerticalDragUpdate: _onBrightnessDragUpdate,
                    onVerticalDragEnd: _onBrightnessDragEnd,
                    // 下滑切书签：主区域纵向下滑（滚动模式由
                    // animated_page_view 内部 _isScroll 判断自动禁用）。
                    onBookmarkSwipeStart: _onBookmarkSwipeStart,
                    onBookmarkSwipeUpdate: _onBookmarkSwipeUpdate,
                    onBookmarkSwipeEnd: _onBookmarkSwipeEnd,
                    scrollWheelInverted: _prefs.scrollWheelInverted,
                  );
                }),
              ),
            ),
            if (_bookmarkSwipeActive) _buildBookmarkSwipeHint(bg, textColor),
            if (_showSelectionToolbar) _buildSelectionToolbar(),
          ],
        );
      },
    );
  }

  Widget _buildScrollContent(Color bg, Color textColor) {
    final sc = _scrollController;
    if (sc == null) return const SizedBox.shrink();

    // 连排缓冲为空（非滚动模式 / 章节尚未就绪）时回退到「当前章单段」，
    // 避免渲染空列表。
    if (_scrollSegments.isEmpty) _resetScrollSegments();
    final List<_NovelScrollSegment> segments = _scrollSegments;
    if (_scrollSegStarts.length != segments.length + 1) {
      _rebuildScrollStarts();
    }
    // 列表项 = 所有段的正文项 + 尾部提示项（加载下一章 / 全书读完）。
    final int itemCount = _scrollSegStarts.last + 1;

    return GestureDetector(
      // 滚动模式：点按空白处收起选区工具条或切换控制面板。
      onTap: () {
        if (_showSelectionToolbar) {
          // 吞掉长按松手后极短窗口内（250ms）紧随的那次 tap，避免误清空
          // 刚建立的选区（闪一下）；窗口之外照常收起（点一下即退）。
          final DateTime? sinkAt = _selectionJustConfirmedAt;
          if (sinkAt != null &&
              DateTime.now().difference(sinkAt) < _kSelectionTapSinkWindow) {
            _selectionJustConfirmedAt = null;
            return;
          }
          _selectionJustConfirmedAt = null;
          _selectionController.clearSelection();
          if (mounted) setState(() => _showSelectionToolbar = false);
        } else {
          _toggleUi();
        }
      },
      child: NotificationListener<ScrollEndNotification>(
        // 滚动停稳后再结算「主导章」：滚动中切章会重建整棵阅读器并同步
        // 重算分页，必然掉帧，因此只在停稳时做一次。
        onNotification: (ScrollEndNotification n) {
          _settleScrollChapter();
          return false;
        },
        child: ListView.builder(
          controller: sc,
          padding: EdgeInsets.symmetric(
            horizontal: _prefs.margin,
            vertical: _prefs.margin,
          ),
          // 预构建视口外一段内容，滚动/插图撑高时减少白屏与掉帧。
          scrollCacheExtent: ScrollCacheExtent.pixels(600),
          itemCount: itemCount,
          itemBuilder: (BuildContext ctx, int i) {
            // 尾部提示项（加载中 / 全书读完）。
            if (i >= _scrollSegStarts.last) {
              return _buildScrollFooter(bg, textColor);
            }
            // 定位所在段与段内偏移。
            int si = 0;
            while (si + 1 < segments.length &&
                _scrollSegStarts[si + 1] <= i) {
              si++;
            }
            final _NovelScrollSegment seg = segments[si];
            final int local = i - _scrollSegStarts[si];
            final bool showTitle = seg.showTitle && seg.blocks.isNotEmpty;
            // 只有「主导章」（当前章）参与选区 / 朗读高亮 / 章内搜索，
            // 其余段按普通正文渲染，避免跨章索引错位。
            final bool isActive = seg.chapterIndex == _chapterIndex;
            if (showTitle && local == 0) {
              return KeyedSubtree(
                key: seg.anchorKey,
                child: _buildChapterTitleWidget(
                  _prefs,
                  seg.title,
                  widget.title,
                ),
              );
            }
            final int idx = showTitle ? local - 1 : local;
            if (idx < 0 || idx >= seg.blocks.length) {
              return const SizedBox.shrink();
            }
            final block = seg.blocks[idx];
            // 段首落在首个正文块（不显示章标题时）也需挂锚点，
            // 供滚动位置判定复用。
            final Key? anchorKey =
                (!showTitle && local == 0) ? seg.anchorKey : null;
            // 插图块：滚动模式图文混排，固定比例缩略显示，点开看大图。
            // banner 模式铺满整行（按源 style 或全宽，高度自适应）；
            // card 模式按正文宽 72% 卡片式缩列 + [scrollImageAlign] 水平对齐。
            if (block is NovelImageBlock) {
              final double bodyW =
                  MediaQuery.of(ctx).size.width - _prefs.margin * 2;
              // banner 模式自适应完整显示（按图片真实宽高比撑高，
              // 加载前以 2:1 占位）；card 模式按正文宽 72% 卡片式缩列 +
              // [scrollImageAlign] 水平对齐。两种模式均不再裁切。
              final bool card =
                  _prefs.scrollImageMode == NovelScrollImageMode.card;
              final Widget image = card
                  ? SourceImage(
                      url: block.url,
                      source: block.source ?? _source,
                      width: bodyW * 0.72,
                      fit: BoxFit.fitWidth,
                      radius: 8,
                    )
                  : _AdaptiveScrollImage(
                      url: block.url,
                      source: block.source ?? _source,
                      width: bodyW,
                    );
              final Widget aligned = card
                  ? Align(
                      alignment: switch (_prefs.scrollImageAlign) {
                        NovelScrollImageAlign.left => Alignment.centerLeft,
                        NovelScrollImageAlign.right => Alignment.centerRight,
                        NovelScrollImageAlign.center => Alignment.center,
                      },
                      child: image,
                    )
                  : image;
              final Widget imageItem = Padding(
                padding: EdgeInsets.only(bottom: _prefs.paragraphSpacing),
                child: GestureDetector(
                  onTap: () =>
                      _showImageViewer(block.url, block.source ?? _source),
                  child: aligned,
                ),
              );
              return anchorKey == null
                  ? imageItem
                  : KeyedSubtree(key: anchorKey, child: imageItem);
            }
            final String text = block is NovelTextBlock ? block.text : '';
            // 章节标题块：居中 + 大字号 + 加粗 + 加大上下间距，让滚动浏览时
            // 一眼能看到「第N章」的章节分界（本地 EPUB 修复）。
            final isHeading = block is NovelTextBlock && block.isHeading;
            final baseStyle = _prefs.resolveBodyTextStyle(textColor);
            final headingStyle = isHeading
                ? baseStyle.copyWith(
                    fontSize: (baseStyle.fontSize ?? 16) * 1.4,
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                  )
                : baseStyle;
            final Widget bodyText = _buildHighlightedBodyText(
              text,
              baseStyle,
              headingStyle,
              isHeading,
            );
            // 滚动模式选区：非 TTS 态文本块包长按手势，复用与分页同源的
            // 章节全局字符偏移坐标系（[NovelSelectionController.setBlocks]）。
            // 块为整段多行文本，Phase 4 长按直接选整块（精确折行 x 命中留待后续），
            // 拖拽扩选由工具条「整段」按钮覆盖（与分页行内限制一致）。
            // TTS 态：当前朗读段高亮强调 + 点按段落跳转朗读 +
            // 自动滚动跟随（段挂 key，_onTtsChanged 帧后 ensureVisible）。
            final Widget wrapped;
            if (isActive && _ttsActiveForBody()) {
              final bool isCurrent = idx == _tts.currentIndex;
              final Widget textWidget = isCurrent
                  ? Container(
                      decoration: BoxDecoration(
                        color:
                            _prefs.resolveTextColor(bg).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppTokens.radiusXs),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      child: bodyText,
                    )
                  : bodyText;
              final Widget tappable = GestureDetector(
                behavior: HitTestBehavior.translucent,
                excludeFromSemantics: true,
                onTap: () => _onParagraphTapped(idx),
                child: isCurrent
                    ? KeyedSubtree(key: _ttsParagraphKey, child: textWidget)
                    : textWidget,
              );
              wrapped = tappable;
            } else if (isActive) {
              // 滚动模式选区：长按手势识别器必须「稳定」，不能包在监听
              // selectionController 的 AnimatedBuilder 内——否则 setSelection
              // 触发的 notifyListeners 会重建 RawGestureDetector、新建识别器，
              // 进行中的长按被打断（表现为「长按闪一下」）。这里把识别器放在
              // 外层（StatefulWidget 稳定持有识别器实例），仅内层文本随选区
              // 变化重建。
              final Widget selected = _StableLongPressDetector(
                onLongPressStart: (_) => _onSelLongPressStartScroll(idx, text),
                onLongPressEnd: _onSelLongPressEndScroll,
                child: AnimatedBuilder(
                  animation: _selectionController,
                  builder: (ctx, _) {
                    final spans = _selectionController.blockSpans(
                      _paragraphs,
                      idx,
                      text,
                    );
                    return spans.isEmpty
                        ? bodyText
                        : buildSelectionRichText(
                            text,
                            isHeading ? headingStyle : baseStyle,
                            spans,
                            softWrap: true,
                          );
                  },
                ),
              );
              wrapped = selected;
            } else {
              // 非主导段：纯文本渲染（选区 / 朗读 / 章内搜索都只对当前章有效）。
              wrapped = bodyText;
            }
            final Widget content = Padding(
              padding: EdgeInsets.only(
                top: isHeading ? _prefs.paragraphSpacing * 2 : 0,
                bottom: isHeading
                    ? _prefs.paragraphSpacing * 2
                    : _prefs.paragraphSpacing,
              ),
              child: wrapped,
            );
            return anchorKey == null
                ? content
                : KeyedSubtree(key: anchorKey, child: content);
          },
        ),
      ),
    );
  }

  /// 构建正文文本（带搜索关键词高亮；正则模式按表达式匹配）。
  Widget _buildHighlightedBodyText(
    String text,
    TextStyle baseStyle,
    TextStyle headingStyle,
    bool isHeading,
  ) {
    final style = isHeading ? headingStyle : baseStyle;
    // 滚动模式正文两端对齐（与分页模式 justify 语义一致）；
    // 标题行恒居中（章节分界视觉），其余正文按 [NovelTextAlignMode] 取
    // 自然左对齐或 justify。原生 TextAlign.justify 对整段多行文本生效，
    // 与分页模式的逐行字距均摊策略各自独立（两模式渲染路径不同）。
    final align = isHeading
        ? TextAlign.center
        : (_prefs.textAlignMode == NovelTextAlignMode.justify
            ? TextAlign.justify
            : TextAlign.start);
    final spans = searchHitSpans(
      text: text,
      query: _searchKeyword,
      regex: _searchRegex,
      hitStyle: style.copyWith(
        backgroundColor:
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
        fontWeight: FontWeight.w700,
      ),
    );
    if (spans == null) {
      return Text(text, style: style, textAlign: align);
    }
    return Text.rich(
      TextSpan(style: style, children: spans),
      textAlign: align,
    );
  }

  /// 全屏查看插图：支持缩放/平移，防盗链 headers 由 [SourceImage] 注入。
  void _showImageViewer(String url, PluginConfig? source) {
    if (url.isEmpty) return;
    final List<Episode> chs = _effectiveChapters;
    final String chapterTitle =
        chs.isEmpty ? '' : chs[_chapterIndex.clamp(0, chs.length - 1)].title;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        // 插图大图查看器带「收藏入统一图库」按钮（来源 = 小说）。
        builder: (BuildContext ctx) => _NovelImageFavoriteViewer(
          url: url,
          source: source,
          workId: widget.novelId,
          workTitle: widget.title,
          label: chapterTitle,
        ),
      ),
    );
  }

  /// 顶栏标题：两行——书名 + 「第N章/共M章 · 章名」。
  /// 本地模式无章节列表，第二行显示「本地文件」。
  Widget _buildTopBarTitle(AppLocalizations l10n, Episode? chapter) {
    const TextStyle titleStyle = TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 15,
    );
    final TextStyle subStyle = TextStyle(
      fontSize: 11.5,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    if (_isLocalMode) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          ),
          Text(
            l10n.localFileLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: subStyle,
          ),
        ],
      );
    }
    final int total = widget.chapters.length;
    final int current = chapter?.number ?? (_chapterIndex + 1);
    final String chapterName = chapter?.title ?? '';
    final String sub = total > 0
        ? '${l10n.novelChapterProgress(current, total)}'
            '${chapterName.isNotEmpty ? ' · $chapterName' : ''}'
        : chapterName;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: titleStyle,
        ),
        if (sub.isNotEmpty)
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: subStyle,
          ),
      ],
    );
  }

  Widget _buildTopBar(AppLocalizations l10n, Color bg) {
    final barChapters = _effectiveChapters;
    final chapter = barChapters.isEmpty
        ? null
        : barChapters[_chapterIndex.clamp(0, barChapters.length - 1)];
    final String? chapterUrl = chapter?.url;
    final String? absoluteChapterUrl =
        (chapterUrl != null && chapterUrl.isNotEmpty)
            ? (_source != null && _source!.site.baseUrl.isNotEmpty
                ? _source!.site.baseUrl + chapterUrl
                : chapterUrl)
            : null;
    // 渐变背景容器铺到屏幕最顶端（含状态栏 / 刘海区），SafeArea 只包住 Row 内容
    // 负责避让安全区（与漫画阅读器 _buildTopBar 同款修法）。
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            bg.withValues(alpha: 0.95),
            bg.withValues(alpha: 0)
          ],
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMd,
        vertical: AppTokens.spaceSm,
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: _buildTopBarTitle(l10n, chapter),
            ),
            // 收藏按钮
            IconButton(
              icon: Icon(_isFav
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded),
              tooltip: l10n.favorite,
              onPressed: _onFavoritePressed,
            ),
            // 重载本章（在线重载当前章节；本地重新读取文本）
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: l10n.reloadChapter,
              onPressed: () {
                if (_isLocalMode) {
                  _loadLocalText();
                } else {
                  _reloadChapter();
                }
              },
            ),
            // 清除阅读记录（回到本书开头）
            IconButton(
              icon: const Icon(Icons.cleaning_services_rounded),
              tooltip: l10n.clearReadingProgress,
              onPressed: _clearReadingProgress,
            ),
            // 其余工具（目录 / 自动翻页 / 设置 / 书签 / 夜间 / 搜索）已移至底部工具栏，
            // 可在「配置底部按钮」中自定义；顶栏仅保留返回 / 标题 / 收藏 / 更多。
            // 三点菜单：WebView 打开章节 / 浏览器打开 / 分享 / 书签列表 /
            // 配置底部工具栏 / 笔记 / 翻页动画
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: l10n.moreActions,
              onSelected: (String value) {
                switch (value) {
                  case 'webview':
                    if (absoluteChapterUrl != null) {
                      openInAppBrowser(context, absoluteChapterUrl,
                          source: _source);
                    }
                  case 'browser':
                    if (absoluteChapterUrl != null) {
                      openInExternalBrowser(context, absoluteChapterUrl);
                    }
                  case 'share':
                    if (absoluteChapterUrl != null) {
                      shareContent(
                        context,
                        '${widget.title} - ${chapter?.title ?? ''}',
                        absoluteChapterUrl,
                      );
                    }
                  case 'bookmarkList':
                    _showBookmarkList();
                  case 'summary':
                    _showReadingOverview();
                  case 'translate':
                    _showTranslationSheet();
                  case 'aiIllustration':
                    _generateAiIllustration();
                  case 'contentEdit':
                    _showContentEditor();
                  case 'contentEditRestore':
                    _restoreOriginalContent();
                  case 'configureBottomToolbar':
                    _showBottomToolbarConfig();
                  case 'notes':
                    _showNoteList();
                  case 'highlights':
                    _showHighlightList();
                  case 'pageAnimation':
                    _showPageAnimationPicker();
                  case 'aggSort':
                    _showAggChapterModePicker();
                  case 'addToReadingQueue':
                    _addCurrentToReadingQueue();
                  case 'readingQueue':
                    openReadingQueueSheet(context);
                }
              },
              itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
                // WebView / 浏览器 / 分享：本地模式无在线 URL，隐藏。
                if (!_isLocalMode) ...<PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'webview',
                    enabled: absoluteChapterUrl != null,
                    child: ListTile(
                      leading: const Icon(Icons.public_rounded),
                      title: Text(l10n.openInAppBrowser),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'browser',
                    enabled: absoluteChapterUrl != null,
                    child: ListTile(
                      leading: const Icon(Icons.open_in_new_rounded),
                      title: Text(l10n.openInBrowser),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'share',
                    enabled: absoluteChapterUrl != null,
                    child: ListTile(
                      leading: const Icon(Icons.share_rounded),
                      title: Text(l10n.share),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                  const PopupMenuDivider(),
                ],
                // 待读队列：加入队列 / 打开队列（非本地模式才显示）。
                if (!_isLocalMode) ...<PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'addToReadingQueue',
                    child: ListTile(
                      leading: const Icon(Icons.playlist_add_rounded),
                      title: Text(l10n.readingQueueAdd),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'readingQueue',
                    child: ListTile(
                      leading: const Icon(Icons.playlist_play_rounded),
                      title: Text(l10n.readingQueueOpen),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                ],
                // 书签列表
                PopupMenuItem<String>(
                  value: 'bookmarkList',
                  child: ListTile(
                    leading: const Icon(Icons.bookmark_border_rounded),
                    title: Text(l10n.novelMenuBookmarkList),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                // 阅读速览（总结本章内容：离线摘要 / 云端 AI）
                PopupMenuItem<String>(
                  value: 'summary',
                  child: ListTile(
                    leading: const Icon(Icons.insights_rounded),
                    title: Text(l10n.novelReadingSummary),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                // AI 章节配图（云端生图；聚合本地模式不提供）
                if (!_isAggregatedLocal)
                  PopupMenuItem<String>(
                    value: 'aiIllustration',
                    child: ListTile(
                      leading: const Icon(Icons.auto_awesome_rounded),
                      title: Text(l10n.novelAiIllustrate),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                // 聚合本地模式：章节排序（EPUB 展开位置）
                if (_isAggregatedLocal) ...<PopupMenuEntry<String>>[
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(
                    value: 'aggSort',
                    child: ListTile(
                      leading: const Icon(Icons.swap_vert_rounded),
                      title: Text(l10n.chapterSortMode),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                ],
                // 内容编辑：直接修改本章正文并持久化（聚合本地模式除外——
                // 本地书正文来自文件本身，覆盖语义不适用）。已编辑时追加
                // 「恢复原文」入口并在标题旁显示角标。
                if (!_isAggregatedLocal) ...<PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'contentEdit',
                    child: ListTile(
                      leading: const Icon(Icons.edit_rounded),
                      title: Text(l10n.novelContentEdit),
                      trailing: _currentChapterEdited
                          ? Text(
                              l10n.novelContentEditBadge,
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            )
                          : null,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                  if (_currentChapterEdited)
                    PopupMenuItem<String>(
                      value: 'contentEditRestore',
                      child: ListTile(
                        leading: const Icon(Icons.restore_rounded),
                        title: Text(l10n.novelContentEditRestore),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                ],
                // 配置底部工具栏
                PopupMenuItem<String>(
                  value: 'configureBottomToolbar',
                  child: ListTile(
                    leading: const Icon(Icons.tune_rounded),
                    title: Text(l10n.novelMenuConfigureToolbar),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                const PopupMenuDivider(),
                // 划线列表（/ Phase 2）
                PopupMenuItem<String>(
                  value: 'highlights',
                  child: ListTile(
                    leading: const Icon(Icons.format_color_fill_rounded),
                    title: Text(l10n.highlightList),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                // 笔记列表
                PopupMenuItem<String>(
                  value: 'notes',
                  child: ListTile(
                    leading: const Icon(Icons.edit_note_rounded),
                    title: Text(l10n.noteList),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                // 翻页动画快捷：弹出 6 种动画选择。
                PopupMenuItem<String>(
                  value: 'pageAnimation',
                  child: ListTile(
                    leading: const Icon(Icons.auto_stories_rounded),
                    title: Text(l10n.novelPageAnimation),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(AppLocalizations l10n, Color bg,
      {bool ttsActive = false}) {
    // 渐变背景容器铺到屏幕最底端（含导航条区），SafeArea 只包住 Column 内容
    // 负责避让安全区（与漫画阅读器同款修法）。top:false——底栏不含状态栏高度。
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: <Color>[
            bg.withValues(alpha: 0.95),
            bg.withValues(alpha: 0)
          ],
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMd,
        vertical: AppTokens.spaceSm,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _buildProgressSlider(l10n),
            const SizedBox(height: AppTokens.spaceXs),
            if (ttsActive)
              _buildTtsControlsInline(l10n, bg)
            else
              _buildBottomToolbar(l10n),
          ],
        ),
      ),
    );
  }

  // ─────────────────────── 章内进度滑条 ───────────────────────

  Widget _buildProgressSlider(AppLocalizations l10n) {
    final total = _pagination?.pages.length ?? 0;
    final isScroll = _prefs.pageAnimation.isScroll;
    // 翻页按钮可用性：章内有可翻页 OR 存在相邻章。
    // 用户需求：即使本章只有一页，上一页/下一页仍应可用——分别去往
    // 上一章最后一页 / 下一章第一页（由 page view 边界回调处理，连贯翻页）。
    // 本地模式（单文件无章间导航）或加载中则禁用按钮避免竞态。
    // 单 EPUB（已解析出章节）按真实章节数启用章间导航。
    final bool hasPrev = !_loading && (_currentPage > 0 || _chapterIndex > 0);
    final bool hasNext = !_loading &&
        (_currentPage < total - 1 ||
            _chapterIndex < _effectiveChapters.length - 1 ||
            // 本地模式末页时允许按钮可点（触发下一章/在线续读）。
            _isLocalMode);
    // 滑块仅在多页时允许拖动跳页；单页时禁用（无跳页意义）但保留布局。
    final bool sliderInteractive = isScroll || total > 1;
    final int divisions = total > 1 ? total - 1 : 1;
    double value;
    String leftLabel;
    String rightLabel;
    if (isScroll) {
      value = _scrollFraction.clamp(0.0, 1.0);
      leftLabel = '${(value * 100).round()}%';
      rightLabel = '';
    } else {
      value = total > 1 ? _currentPage / (total - 1) : 0.0;
      // 防护：_currentPage 可能在章节切换瞬间为哨兵值 -1（toLastPage），
      // clamp 到合法范围避免闪现 "0"。
      final displayPage = _currentPage.clamp(0, total > 0 ? total - 1 : 0);
      leftLabel = '${displayPage + 1}';
      rightLabel = total > 0 ? '$total' : '';
    }
    return Row(
      children: <Widget>[
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          tooltip: l10n.prevPage,
          visualDensity: VisualDensity.compact,
          onPressed: hasPrev ? _goPrevPage : null,
        ),
        SizedBox(
          width: 32,
          child: Text(
            leftLabel,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0.0, 1.0),
            divisions: divisions,
            onChangeStart: sliderInteractive ? (_) => AppHaptics.light() : null,
            onChanged: sliderInteractive
                ? (v) {
                    if (isScroll) {
                      setState(() => _scrollFraction = v);
                    } else {
                      // paged 模式拖动即跳页（实时）。
                      final target =
                          (v * (total - 1)).round().clamp(0, total - 1);
                      if (target != _currentPage) {
                        _pageKey.currentState?.jumpToPage(target);
                      }
                    }
                  }
                : null,
            onChangeEnd: isScroll ? (v) => _onSeekScroll(v) : null,
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            rightLabel,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded),
          tooltip: l10n.nextPage,
          visualDensity: VisualDensity.compact,
          onPressed: hasNext ? _goNextPage : null,
        ),
      ],
    );
  }

  /// scroll 模式：按拖动比例跳转到对应滚动位置。
  ///
  /// 连排多段时 [fraction] 是「本章内比例」，按段首 + 段高换算成绝对像素，
  /// 保证拖动进度条只在当前章内跳转（与原单章语义一致）。
  void _onSeekScroll(double fraction) {
    final sc = _scrollController;
    if (sc == null || !sc.hasClients) return;
    final ScrollPosition pos = sc.position;
    double target = fraction * pos.maxScrollExtent;
    if (_scrollSegments.length <= 1) {
      // 单章：章末在 maxScrollExtent 之前（尾部还有留白与尾项）。
      final double scrollable =
          pos.maxScrollExtent - _prefs.margin - _kScrollFooterHeight;
      target = fraction * (scrollable > 1 ? scrollable : pos.maxScrollExtent);
    } else {
      final _NovelScrollSegment? seg = _segmentByChapter(_chapterIndex);
      if (seg != null) {
        final double? top = _segmentTopPixels(seg, pos);
        final double? height = _segmentHeight(seg, pos);
        if (top != null && height != null && height > 0) {
          target = top + fraction * height;
        }
      }
    }
    sc.animateTo(
      target.clamp(0.0, pos.maxScrollExtent),
      duration: AppTokens.durFast,
      curve: Curves.easeInOut,
    );
  }

  // ─────────────────────── 底部工具栏 ───────────────────────

  Widget _buildBottomToolbar(AppLocalizations l10n) {
    // #3：书签列表与「配置底部工具栏」齿轮已从底部工具栏移除，仅保留用户
    // 可配置的槽位。配置入口移至内联设置面板（见 _NovelInlineSettings）。
    final slots = _prefs.bottomToolbarSlots.take(6).where((tool) {
      if (tool == NovelBottomTool.bookmarkList) return false;
      // 本地模式无章节导航时隐藏 toc / prevChapter / nextChapter。
      // 聚合本地模式（多文件合成一整本）与单 EPUB（已解析出章节）保留。
      final hasChapters =
          _isAggregatedLocal || (_parsedChapterEpisodes?.isNotEmpty ?? false);
      if (_isLocalMode && !hasChapters) {
        return tool != NovelBottomTool.toc &&
            tool != NovelBottomTool.prevChapter &&
            tool != NovelBottomTool.nextChapter;
      }
      return true;
    }).toList();
    // 注意：无需在此包裹 ListenableBuilder(_tts)，因为父级 build() 已经用
    // ListenableBuilder(_tts) 包裹了整个 Stack（含本栏），_tts 状态变更时
    // 整个底部栏都会自动重建，TTS 图标（record_voice_over / stop）随之刷新。
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: <Widget>[
        for (final tool in slots) _buildToolButton(l10n, tool),
      ],
    );
  }

  Widget _buildToolButton(AppLocalizations l10n, NovelBottomTool tool) {
    return IconButton(
      icon: Icon(_toolIcon(tool)),
      tooltip: _toolLabel(l10n, tool),
      visualDensity: VisualDensity.compact,
      onPressed: () => _onToolTap(tool),
    );
  }

  IconData _toolIcon(NovelBottomTool tool) {
    final isNight = _prefs.themeFollow == NovelThemeFollow.alwaysDark;
    switch (tool) {
      case NovelBottomTool.toc:
        return Icons.toc_rounded;
      case NovelBottomTool.prevChapter:
        return Icons.skip_previous_rounded;
      case NovelBottomTool.nextChapter:
        return Icons.skip_next_rounded;
      case NovelBottomTool.nightMode:
        // 夜间开启时用实心月，关闭时用描边。
        return isNight ? Icons.dark_mode_rounded : Icons.light_mode_rounded;
      case NovelBottomTool.autoPage:
        return _autoPageEnabled
            ? (_autoPagePaused ? Icons.play_arrow_rounded : Icons.pause_rounded)
            : Icons.play_circle_rounded;
      case NovelBottomTool.settings:
        return Icons.tune_rounded;
      case NovelBottomTool.bookmark:
        return Icons.bookmark_add_rounded;
      case NovelBottomTool.bookmarkList:
        return Icons.bookmarks_rounded;
      case NovelBottomTool.search:
        return Icons.search_rounded;
      case NovelBottomTool.tts:
        return _tts.isPlaying
            ? Icons.stop_rounded
            : Icons.record_voice_over_rounded;
    }
  }

  String _toolLabel(AppLocalizations l10n, NovelBottomTool tool) {
    switch (tool) {
      case NovelBottomTool.toc:
        return l10n.toolToc;
      case NovelBottomTool.prevChapter:
        return l10n.toolPrevChapter;
      case NovelBottomTool.nextChapter:
        return l10n.toolNextChapter;
      case NovelBottomTool.nightMode:
        return l10n.toolNightMode;
      case NovelBottomTool.autoPage:
        return l10n.toolAutoPage;
      case NovelBottomTool.settings:
        return l10n.toolSettings;
      case NovelBottomTool.bookmark:
        return l10n.toolBookmark;
      case NovelBottomTool.bookmarkList:
        return l10n.toolBookmarkList;
      case NovelBottomTool.search:
        return l10n.toolSearch;
      case NovelBottomTool.tts:
        return _tts.isPlaying ? l10n.stopReading : l10n.toolTts;
    }
  }

  void _onToolTap(NovelBottomTool tool) {
    switch (tool) {
      case NovelBottomTool.toc:
        _showChapterList();
      case NovelBottomTool.prevChapter:
        _goPrevChapter();
      case NovelBottomTool.nextChapter:
        _goNextChapter();
      case NovelBottomTool.nightMode:
        _toggleNightMode();
      case NovelBottomTool.autoPage:
        if (_autoPageEnabled) {
          _toggleAutoPagePause();
        } else {
          // 未启用自动翻页时，打开设置面板让用户设定间隔。
          _toggleInlineSettings();
        }
      case NovelBottomTool.settings:
        _toggleInlineSettings();
      case NovelBottomTool.bookmark:
        _addBookmark();
      case NovelBottomTool.bookmarkList:
        _showBookmarkList();
      case NovelBottomTool.search:
        _showInBookSearch();
      case NovelBottomTool.tts:
        _toggleTts();
    }
  }

  /// 夜间快捷切换：在「跟随应用」与「始终夜间」间切换（项 6）。
  /// 背景预设不变；其余（始终日间）由设置面板三选一控制。
  void _toggleNightMode() {
    final next = _prefs.themeFollow == NovelThemeFollow.alwaysDark
        ? NovelThemeFollow.followApp
        : NovelThemeFollow.alwaysDark;
    _onPrefsChanged(_prefs.copyWith(themeFollow: next));
  }

  /// 缓存本书到本地（离线阅读）：复用全局 [DownloadManager] 提交整本下载任务。
  /// 本地模式（localTextPath）无在线源，入口已禁用；章节为空则提示。
  Future<void> _startNovelDownload({List<int>? selectedIndices}) async {
    final l10n = AppLocalizations.of(context);
    if (widget.chapters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.emptyContent)),
      );
      return;
    }
    final dl = context.read<DownloadManager>();
    // 逐章比对：只缓存尚未下载的章节；全部下载完成才提示「已下载」。
    // 旧实现用 isItemDownloaded（下过任意一章即为 true）整体拦截，
    // 导致部分缓存后无法补齐剩余章节。selectedIndices 非空时直接采用
    // （来自「缓存」弹窗的自定义勾选），否则默认补齐未下载章节。
    final Set<String> downloadedTitles =
        dl.downloadedChapterTitles(widget.novelId);
    final List<int> indices = selectedIndices ??
        <int>[
          for (int i = 0; i < widget.chapters.length; i++)
            if (!downloadedTitles.contains(widget.chapters[i].title)) i
        ];
    if (indices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.alreadyDownloaded)),
      );
      return;
    }
    final item = MediaItem(
      id: widget.novelId,
      title: widget.title,
      sourceId: widget.sourceId,
      sourceType: SourceType.novelSource,
      coverUrl: widget.coverUrl,
      detailUrl: widget.detailUrl,
    );
    await dl.addTask(
      item: item,
      chapters: widget.chapters,
      chapterIndices: indices,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.downloadStarted)),
      );
    }
  }

  /// 缓存章节多选弹窗：默认勾选「尚未缓存」的章节，用户可任意勾选 / 取消
  /// （含全选 / 全不选），确认后只缓存选中章节。已缓存章节用图标标记但不
  /// 强制勾选——用户可重复缓存以补齐缺失。
  Future<void> _showCacheChaptersDialog() async {
    final l10n = AppLocalizations.of(context);
    final dl = context.read<DownloadManager>();
    final Set<String> downloaded = dl.downloadedChapterTitles(widget.novelId);
    final chapters = widget.chapters;
    final selected = <bool>[
      for (final c in chapters) !downloaded.contains(c.title)
    ];

    final List<int>? indices = await showDialog<List<int>?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final picked = selected.where((e) => e).length;
          return AlertDialog(
            title: Text(l10n.cacheChaptersTitle),
            content: SizedBox(
              width: double.maxFinite,
              height: MediaQuery.of(ctx).size.height * 0.6,
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      TextButton(
                        onPressed: () => setSt(() {
                          for (var i = 0; i < selected.length; i++) {
                            selected[i] = true;
                          }
                        }),
                        child: Text(l10n.selectAll),
                      ),
                      TextButton(
                        onPressed: () => setSt(() {
                          for (var i = 0; i < selected.length; i++) {
                            selected[i] = false;
                          }
                        }),
                        child: Text(l10n.deselectAll),
                      ),
                      const Spacer(),
                      Text(l10n.cacheSelectedCount(picked)),
                    ],
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: chapters.length,
                      itemBuilder: (_, i) {
                        final done = downloaded.contains(chapters[i].title);
                        return CheckboxListTile(
                          title: Text(
                            chapters[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          value: selected[i],
                          onChanged: (v) {
                            v == true
                                ? AppHaptics.toggleOn()
                                : AppHaptics.toggleOff();
                            setSt(() => selected[i] = v ?? false);
                          },
                          secondary: done
                              ? const Icon(Icons.cloud_done_rounded, size: 18)
                              : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(<int>[
                  for (var i = 0; i < selected.length; i++)
                    if (selected[i]) i
                ]),
                child: Text(l10n.cacheSelected),
              ),
            ],
          );
        },
      ),
    );
    if (indices != null && indices.isNotEmpty && mounted) {
      await _startNovelDownload(selectedIndices: indices);
    }
  }

  /// 恢复本书默认设置：清除单独设置记录，当前会话直接应用全局默认，
  /// 与下次打开时的合并结果保持一致（旧实现停留在类默认值且未清覆盖记录）。
  Future<void> _resetBookPrefs() async {
    final l10n = AppLocalizations.of(context);
    _overrideKeys = <String>{};
    await _store.save(
      widget.novelId,
      const NovelReaderPreferences(),
      overrideKeys: _overrideKeys,
    );
    NovelReaderPreferences restored = const NovelReaderPreferences();
    try {
      final defaults = await ReaderDefaultSettingsStore().load();
      restored = defaults.toNovelReaderPreferences();
    } on Object {
      // 全局默认加载失败时退回类默认值。
    }
    setState(() => _prefs = restored);
    // 排版相关默认可能变化：使分页缓存失效并重建控制器（同 _onPrefsChanged）。
    _prefsVersion++;
    _contentVersion++;
    if (_paragraphs.isNotEmpty) {
      _setupControllers(restorePage: _currentPage);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.novelResetBookDone)),
      );
    }
  }

  /// 翻页动画快捷选择（更多菜单入口）：弹窗列出 6 种动画，选中即应用。
  Future<void> _showPageAnimationPicker() async {
    final l10n = AppLocalizations.of(context);
    final current = _prefs.pageAnimation;
    final picked = await showDialog<NovelPageAnimation>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(l10n.novelPageAnimation),
        content: SingleChildScrollView(
          child: Wrap(
            spacing: AppTokens.spaceSm,
            runSpacing: AppTokens.spaceSm,
            children: <Widget>[
              for (final anim in NovelPageAnimation.values)
                ChoiceChip(
                  label: Text(_animLabel(anim, l10n)),
                  selected: anim == current,
                  onSelected: (_) => Navigator.of(ctx).pop(anim),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) {
      _onPrefsChanged(_prefs.copyWith(pageAnimation: picked));
    }
  }

  /// 打开章节列表（顶栏与底部工具栏共用）。传入本书书签章节，供目录内书签标记与筛选。
  Future<void> _showChapterList() async {
    final bookmarks = await _bookmarks.listFor(widget.novelId);
    final bookmarkedChapters = bookmarks.map((b) => b.chapterIndex).toSet();
    // 与详情页共享目录源：把当前快照写回（保留更长），再读取「更完整」的那份，
    // 这样阅读器目录能实时反映详情页渐进加载出的完整目录。
    final tocStore = context.read<NovelTocStore>();
    final chapters = _effectiveChapters;
    tocStore.setChapters(widget.sourceId, widget.novelId, chapters);
    // 回写「已见章节数」，书架新章角标随查看目录清除。
    if (chapters.isNotEmpty) {
      unawaited(context.read<FavoritesManager>().updateLastSeenChapters(
          widget.novelId, SourceType.novelSource, chapters.length));
    }
    // 本地书目录智能分卷分组：以最近的「卷/部」级标题作为分节名（TXT 行级
    // 切分保留了卷标题章；无任何卷级标题时返回 null，目录保持平铺）。
    final sections = _isLocalMode ? _computeVolumeSections(chapters) : null;
    final index = await showChapterList(
      context,
      chapters,
      _chapterIndex,
      bookmarkedIndices: bookmarkedChapters,
      sectionOf: sections == null
          ? null
          : (int i) => i >= 0 && i < sections.length ? sections[i] : null,
    );
    if (index != null && index != _chapterIndex && mounted) {
      _chapterIndex = index;
      if (_isLocalMode) {
        // 本地（聚合多文件 / 单 EPUB）：切换到该章并重新分页当前章。
        await _loadLocalText();
      } else {
        _loadChapter(_chapterIndex);
      }
    }
  }

  /// 计算本地书的分卷分节名（目录智能分类）：每章归属其之前最近的
  /// 「卷/部」级标题（[LocalNovelParser.isVolumeTitle]），卷标题章自身
  /// 开启新分节。全书无任何卷级标题时返回 null（目录保持平铺）；首个
  /// 卷标题之前的章节不归属任何分节（无分节头）。
  List<String?>? _computeVolumeSections(List<Episode> chapters) {
    if (chapters.isEmpty) return null;
    final sections = List<String?>.filled(chapters.length, null);
    String? current;
    var hasVolume = false;
    for (var i = 0; i < chapters.length; i++) {
      final title = chapters[i].title;
      if (LocalNovelParser.isVolumeTitle(title)) {
        current = title.trim();
        hasVolume = true;
      }
      sections[i] = current;
    }
    return hasVolume ? sections : null;
  }

  // ─────────────────────── 阅读速览 ───────────────────────

  /// 秒数 → 本地化时长文案（X 小时 Y 分钟 / X 小时 / Y 分钟）。
  String _formatReadDuration(AppLocalizations l10n, int seconds) {
    if (seconds <= 0) return l10n.novelDurationMin(0);
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0 && m > 0) return l10n.novelDurationHourMin(h, m);
    if (h > 0) return l10n.novelDurationHour(h);
    return l10n.novelDurationMin(m);
  }

  /// 阅读总结（统计摘要卡）：进度 / 当前位置 / 累计与今日阅读时长 /
  /// 阅读次数 / 按历史均速预估的读完剩余时长 / 本章字数。
  /// 统计数据来自阅读会话记录（本地无源书可能无统计数据，降级隐藏该组）。
  /// 阅读数据（统计卡）：进度 / 当前位置 / 累计与今日阅读时长 /
  /// 阅读次数 / 读完剩余预估 / 本章字数。无统计数据时降级提示。
  Widget _buildReadingStatsWidget(AppLocalizations l10n) {
    final chapters = _effectiveChapters;
    final total = chapters.length;
    final read = total > 0 ? _chapterIndex + 1 : 0;

    WorkReadingStats? stats;
    DailyReadingStats? today;
    try {
      stats = StatsRepository.instance.statsFor(
        workId: widget.novelId,
        sourceId: widget.sourceId.isEmpty ? null : widget.sourceId,
        type: StatsMediaType.novel,
      );
      final now = DateTime.now();
      final range = StatsRepository.instance.dailyForRange(now, now);
      today = range.isEmpty ? null : range.first;
    } on Object {
      stats = null;
      today = null;
    }

    String? remaining;
    if (stats != null &&
        stats.totalDurationSec > 0 &&
        read > 0 &&
        total > read) {
      final avgPerChapter = stats.totalDurationSec / read;
      final remainingSec = (avgPerChapter * (total - read)).round();
      remaining =
          l10n.novelSummaryRemaining(_formatReadDuration(l10n, remainingSec));
    }

    final curChars = _paragraphs.fold<int>(
        0, (sum, b) => sum + (b is NovelTextBlock ? b.text.trim().length : 0));

    final chapterTitle = chapters.isNotEmpty
        ? chapters[_chapterIndex.clamp(0, chapters.length - 1)].title
        : '';
    final pages = _pagination?.pages.length ?? 0;
    final page = pages > 0 ? _currentPage.clamp(0, pages - 1) + 1 : 0;

    final theme = Theme.of(context);
    Widget row(String label, String value, {IconData? icon}) => ListTile(
          dense: true,
          leading: icon != null ? Icon(icon, size: 20) : null,
          title: Text(label),
          trailing: Text(
            value,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (total > 0) ...<Widget>[
          row(
            l10n.novelSummaryProgress(read, total),
            total > 0 ? '${(read / total * 100).toStringAsFixed(0)}%' : '',
            icon: Icons.timeline_rounded,
          ),
          if (chapterTitle.isNotEmpty && pages > 0)
            row(
              l10n.novelSummaryPosition(chapterTitle, page, pages),
              '',
              icon: Icons.menu_book_rounded,
            ),
          row(l10n.novelSummaryCurrentChars(curChars), '',
              icon: Icons.text_fields_rounded),
        ],
        if (stats != null && stats.totalDurationSec > 0) ...<Widget>[
          const Divider(
              height: 1,
              indent: AppTokens.spaceLg,
              endIndent: AppTokens.spaceLg),
          row(
            l10n.novelSummaryTotalRead,
            _formatReadDuration(l10n, stats.totalDurationSec),
            icon: Icons.schedule_rounded,
          ),
          if (today != null && today.novelDurationSec > 0)
            row(
              l10n.novelSummaryToday,
              _formatReadDuration(l10n, today.novelDurationSec),
              icon: Icons.today_rounded,
            ),
          row(
            l10n.novelSummarySessionsValue(stats.sessionCount),
            '',
            icon: Icons.repeat_rounded,
          ),
          if (remaining != null)
            row(remaining, '', icon: Icons.hourglass_bottom_rounded),
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceLg, vertical: AppTokens.spaceSm),
            child: Text(
              l10n.novelSummaryNoStats,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
        const SizedBox(height: AppTokens.spaceSm),
      ],
    );
  }

  /// 阅读速览（改名 + 重定位）：总结「当前章节内容」。
  /// - 离线摘要：本地抽取式，无需网络/配置，秒出。
  /// - 云端总结：调用用户配置的 OpenAI 兼容 /chat/completions 接口。
  /// 底部保留「阅读数据」统计卡（见 [_buildReadingStatsWidget]）。
  Future<void> _showReadingOverview() async {
    final l10n = AppLocalizations.of(context);
    final service = NovelSummaryService();
    final settings = NovelSummarySettings.instance;

    // 当前章正文（仅文本块拼接）。
    final chapterText =
        _paragraphs.whereType<NovelTextBlock>().map((b) => b.text).join('\n');

    final NovelOverviewMode initialMode = await settings.getMode();

    // 离线摘要同步计算，进入即展示。
    final String localResult = chapterText.trim().isNotEmpty
        ? service.localSummary(
            chapterText,
            maxSentences: adaptiveMaxSentences(chapterText.length),
          )
        : '';

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheetCtx) {
        return SafeArea(
          child: _ReadingOverviewPanel(
            l10n: l10n,
            service: service,
            settings: settings,
            initialMode: initialMode,
            chapterText: chapterText,
            localResult: localResult,
            statsWidget: _buildReadingStatsWidget(l10n),
          ),
        );
      },
    );
  }

  /// 聚合本地模式：切换章节排序方式（EPUB 内部章节的展开位置）。
  /// 切换后重建展开目录并回到当前章节（目录结构变化，页码按新章节重分）。
  Future<void> _showAggChapterModePicker() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showModalBottomSheet<_AggChapterMode>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppTokens.spaceMd),
              child: Text(
                l10n.chapterSortMode,
                style: Theme.of(sheetCtx).textTheme.titleMedium,
              ),
            ),
            RadioGroup<_AggChapterMode>(
              groupValue: _aggMode,
              onChanged: (v) => Navigator.of(sheetCtx).pop(v),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  RadioListTile<_AggChapterMode>(
                    value: _AggChapterMode.fileExpanded,
                    title: Text(l10n.aggModeFileExpanded),
                  ),
                  RadioListTile<_AggChapterMode>(
                    value: _AggChapterMode.epubLast,
                    title: Text(l10n.aggModeEpubLast),
                  ),
                  RadioListTile<_AggChapterMode>(
                    value: _AggChapterMode.collapsed,
                    title: Text(l10n.aggModeCollapsed),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTokens.spaceSm),
          ],
        ),
      ),
    );
    if (picked != null && picked != _aggMode && mounted) {
      setState(() {
        _aggMode = picked;
        _expandedChapters = null;
      });
      await _loadLocalText();
    }
  }

  /// 构建本地模式的章节正文块 loader（供书内搜索按章拉取）。
  ///
  /// - 单文件（EPUB/TXT）：直接从已整本解析的 [_localParsedChapters] 切片；
  /// - 聚合导入（localChapterPaths）：按 [_effectiveChapters] 的展开目录逐章
  /// 路由（EPUB 内部章 / TXT 内部章 / 整文件），缓存未命中时按需解析文件。
  ///
  /// 块结构与渲染路径（[_loadLocalText]）保持同构（标题 heading + 插图标记
  /// 转换），使搜索的章内字符偏移与分页偏移同口径。
  Future<List<NovelBlock>> Function(int)? _localSearchChapterLoader() {
    if (!_isLocalMode) return null;
    if (_isAggregatedLocal) {
      return (int ci) async {
        final chs = _effectiveChapters;
        if (ci < 0 || ci >= chs.length) return const <NovelBlock>[];
        return _localBlocksForAggEpisode(chs[ci]);
      };
    }
    final parsed = _localParsedChapters;
    if (parsed == null || parsed.isEmpty) return null;
    return (int ci) async {
      if (ci < 0 || ci >= parsed.length) return const <NovelBlock>[];
      return _localBlocksForParsedChapter(parsed[ci]);
    };
  }

  /// 单文件模式：由已解析章节构建正文块（与 [_loadLocalText] 渲染块同构）。
  List<NovelBlock> _localBlocksForParsedChapter(LocalNovelChapter ch) {
    return <NovelBlock>[
      if (ch.title.isNotEmpty) NovelTextBlock(ch.title, isHeading: true),
      for (final para in ch.content)
        if (para.trim().isNotEmpty) _localParagraphToBlock(para),
    ];
  }

  /// 段落 → 正文块：下载器插图占位行转本地插图，其余为文本段。
  NovelBlock _localParagraphToBlock(String para) {
    final img = para.startsWith(kNexhubImgMarker)
        ? para.substring(kNexhubImgMarker.length).trim()
        : '';
    if (img.isNotEmpty) {
      return NovelImageBlock(img, source: _source);
    }
    return NovelTextBlock(para);
  }

  /// 聚合模式：按 episode.id 路由取该章正文块。
  ///
  /// - `path|ci`：EPUB 内部章节；
  /// - `_aggTxtEpisodeMeta[id]`：TXT 内部章节（ci<0 为整文件展平）；
  /// - 其余（collapsed 模式的整文件章）：按扩展名整书展平。
  Future<List<NovelBlock>> _localBlocksForAggEpisode(Episode ep) async {
    final sepIdx = ep.id.indexOf('|');
    if (sepIdx >= 0) {
      final path = ep.id.substring(0, sepIdx);
      final ci = int.tryParse(ep.id.substring(sepIdx + 1)) ?? 0;
      final book = await _aggBookForPath(path, isEpub: true);
      if (book == null || book.chapters.isEmpty) return const <NovelBlock>[];
      final ch = book.chapters[ci.clamp(0, book.chapters.length - 1)];
      return _localBlocksForParsedChapter(ch);
    }
    final txtMeta = _aggTxtEpisodeMeta[ep.id];
    if (txtMeta != null) {
      final book = await _aggBookForPath(txtMeta.$1, isEpub: false);
      if (book == null || book.chapters.isEmpty) return const <NovelBlock>[];
      if (txtMeta.$2 < 0) {
        // 整文件（无内部章节）：展平全部内部章节（与渲染路径一致）。
        return <NovelBlock>[
          for (final ch in book.chapters) ..._localBlocksForParsedChapter(ch),
        ];
      }
      final ch = book.chapters[txtMeta.$2.clamp(0, book.chapters.length - 1)];
      return _localBlocksForParsedChapter(ch);
    }
    // collapsed 模式：episode.id 即文件路径，整书展平（EPUB 走展平、TXT 走
    // 内部章节展平——与 [_loadLocalText] 对应分支同构）。
    final isEpub = ep.id.toLowerCase().endsWith('.epub');
    final book = await _aggBookForPath(ep.id, isEpub: isEpub);
    if (book == null || book.chapters.isEmpty) return const <NovelBlock>[];
    return <NovelBlock>[
      for (final ch in book.chapters) ..._localBlocksForParsedChapter(ch),
    ];
  }

  /// 聚合模式按需取整本书（优先命中已有缓存，未缓存则现场解析）。
  Future<LocalNovelBook?> _aggBookForPath(String path,
      {required bool isEpub}) async {
    if (isEpub) {
      var book = _aggEpubBooks[path];
      if (book != null) return book;
      final local = await resolveSafUri(path);
      if (local == null) return null;
      final raw = await compute(_parseEpubIsolate, local);
      book = LocalNovelBook(
        title: raw[0] as String,
        author: raw[1] as String?,
        coverPath: raw[2] as String?,
        chapters: <LocalNovelChapter>[
          for (final c in raw[3] as List)
            LocalNovelChapter(
              title: c[0] as String,
              content: List<String>.from(c[1] as List),
            ),
        ],
      );
      _aggEpubBooks[path] = book;
      return book;
    }
    var book = _aggTxtBooks[path];
    if (book != null) return book;
    final local = await resolveSafUri(path);
    if (local == null) return null;
    final raw = await compute(
        _parseTxtChaptersIsolate, (local, _chapterTitleFor(path)));
    book = LocalNovelBook(
      title: _chapterTitleFor(path),
      author: null,
      coverPath: null,
      chapters: <LocalNovelChapter>[
        for (final c in raw)
          LocalNovelChapter(
            title: c[0] as String,
            content: List<String>.from(c[1] as List),
          ),
      ],
    );
    _aggTxtBooks[path] = book;
    return book;
  }

  /// 打开书内搜索（顶栏与底部工具栏共用；本地模式可用）。
  Future<void> _showInBookSearch() async {
    // 源不存在且非本地模式时直接提示。
    if (_source == null && !_isLocalMode) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.sourceNotFound)),
        );
      }
      return;
    }
    // 本地模式：等待加载完成后再打开搜索
    if (_isLocalMode && _loading) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.loading)),
        );
      }
      return;
    }
    final chapters = _effectiveChapters;
    if (chapters.isEmpty) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.emptyContent)),
        );
      }
      return;
    }
    // 本地模式：按需加载章节正文块的 loader（单文件与聚合导入统一走此路径，
    // 修复聚合导入（localChapterPaths）下本地内容不进搜索导致全书搜索无结果）。
    final localLoader = _localSearchChapterLoader();
    try {
      final tocStore = context.read<NovelTocStore>();
      tocStore.setChapters(widget.sourceId, widget.novelId, chapters);
      // 与目录一致，回写「已见章节数」。
      if (chapters.isNotEmpty) {
        unawaited(context.read<FavoritesManager>().updateLastSeenChapters(
            widget.novelId, SourceType.novelSource, chapters.length));
      }
      final result = await showNovelInBookSearchSheet(
        context: context,
        chapters: chapters,
        currentChapterIndex: _chapterIndex,
        service: _service,
        source: _isLocalMode ? null : _source,
        novelId: widget.novelId,
        // 搜索与屏显用同一繁简口径：正文转换后匹配，繁文书也能用简体关键词搜到。
        convertMode: ChineseConvertMode.fromString(_prefs.chineseConvert),
        localChapterLoader: localLoader,
      );
      if (result == null || !mounted) return;
      // 设置搜索关键词高亮（普通模式为关键词、正则模式为表达式）。
      // 计时器延迟到「命中页渲染就绪」后再启动：跨章命中要经历网络
      // 拉取 + 分页，慢网下若在点击瞬间启动，高亮会在页面渲染完成前
      // 就被清除（表现为跳转后看不到任何强调）。
      _searchHighlightTimer?.cancel();
      _searchKeyword = result.keyword;
      _searchRegex = result.regex;
      if (result.chapterIndex != _chapterIndex) {
        // 跨章：携带命中偏移加载目标章，分页就绪后由 恢复路径把偏移
        // 映射回页码（_buildReader 消费 _savedCharOffset 时启动计时器），
        // 落到命中页。
        _savedCharOffset = result.charOffset;
        _chapterIndex = result.chapterIndex;
        _loadChapter(_chapterIndex);
        return;
      }
      // 同章：分页已就绪，直接把偏移映射成页码跳转（与书签跳页同构）。
      final resolved = _pageForCharOffset(result.charOffset);
      if (_prefs.pageAnimation.isScroll) {
        final sc = _scrollController;
        if (sc != null && sc.hasClients) {
          final h = sc.position.viewportDimension;
          sc.jumpTo((resolved * h).clamp(0.0, sc.position.maxScrollExtent));
        }
      } else {
        _pageKey.currentState?.jumpToPage(resolved);
      }
      setState(() => _currentPage = resolved);
      _saveProgress(resolved);
      _startSearchHighlightTimer();
    } catch (e, st) {
      // 兜底：避免未预期异常（如源/存储异常）在手势回调中未被捕获导致阅读器整体卡退。
      debugPrint('[novel_reader] 书内搜索失败: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('搜索失败：$e')),
        );
      }
    }
  }

  /// 启动/重启搜索高亮计时器：3 秒后清除正文中的搜索命中强调。
  ///
  /// 在「命中页真正渲染就绪」时调用（同章跳页后 / 跨章偏移恢复消费时），
  /// 而非点击搜索结果瞬间——跨章命中要经历网络拉取 + 分页，慢网下若在
  /// 点击时启动，高亮会在页面渲染完成前就被清除。
  void _startSearchHighlightTimer() {
    _searchHighlightTimer?.cancel();
    _searchHighlightTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _searchKeyword = null;
          _searchRegex = null;
        });
      }
    });
  }

  /// 跳转到包含引文文本的页面（分页模式）。
  void _jumpToQuote(String quote) {
    final pages = _pagination?.pages;
    if (pages == null || quote.isEmpty) return;
    for (var p = 0; p < pages.length; p++) {
      final page = pages[p];
      final buf = StringBuffer();
      for (final item in page) {
        if (item is NovelTextLineItem) buf.write(item.line.text);
      }
      if (buf.toString().contains(quote)) {
        _pageKey.currentState?.jumpToPage(p);
        break;
      }
    }
  }

  /// 底部工具栏配置 sheet：勾选 / 排序槽位（最多 6 个）。
  Future<void> _showBottomToolbarConfig() async {
    final l10n = AppLocalizations.of(context);
    // 书签列表为固定按钮，不进入可配置列表。
    List<NovelBottomTool> working = List<NovelBottomTool>.of(
        _prefs.bottomToolbarSlots)
      ..removeWhere((NovelBottomTool t) => t == NovelBottomTool.bookmarkList);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetCtx) {
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setSheetState) {
            final hidden = NovelBottomTool.values
                .where((NovelBottomTool t) =>
                    t != NovelBottomTool.bookmarkList && !working.contains(t))
                .toList();
            return SafeArea(
              child: Container(
                height: MediaQuery.sizeOf(ctx).height * 0.6,
                padding: const EdgeInsets.all(AppTokens.spaceMd),
                child: Column(
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          l10n.bottomToolbarConfigTitle,
                          style: Theme.of(ctx).textTheme.titleMedium,
                        ),
                        Row(
                          children: <Widget>[
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: Text(MaterialLocalizations.of(ctx)
                                  .cancelButtonLabel),
                            ),
                            FilledButton(
                              onPressed: () {
                                _onPrefsChanged(_prefs.copyWith(
                                    bottomToolbarSlots: working));
                                Navigator.of(ctx).pop();
                              },
                              child: Text(
                                  MaterialLocalizations.of(ctx).okButtonLabel),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Divider(),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(l10n.slotsShown,
                          style: Theme.of(ctx).textTheme.bodySmall),
                    ),
                    Expanded(
                      child: working.isEmpty
                          ? Center(child: Text(l10n.slotsHidden))
                          : ReorderableListView(
                              buildDefaultDragHandles: false,
                              onReorderItem: (int oldI, int newI) {
                                setSheetState(() {
                                  final item = working.removeAt(oldI);
                                  working.insert(newI, item);
                                });
                              },
                              children: <Widget>[
                                for (int i = 0; i < working.length; i++)
                                  ListTile(
                                    key: ValueKey<String>(working[i].name),
                                    leading: Icon(_toolIcon(working[i])),
                                    title: Text(_toolLabel(l10n, working[i])),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        IconButton(
                                          icon: const Icon(Icons.close_rounded),
                                          tooltip: MaterialLocalizations.of(ctx)
                                              .deleteButtonTooltip,
                                          onPressed: () => setSheetState(
                                              () => working.removeAt(i)),
                                        ),
                                        ReorderableDragStartListener(
                                          index: i,
                                          child: const Icon(
                                              Icons.drag_handle_rounded),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    if (hidden.isNotEmpty) ...<Widget>[
                      const Divider(),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(l10n.slotsHidden,
                            style: Theme.of(ctx).textTheme.bodySmall),
                      ),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          for (final t in hidden)
                            ActionChip(
                              label: Text(_toolLabel(l10n, t)),
                              avatar: Icon(_toolIcon(t), size: 18),
                              onPressed: working.length >= 6
                                  ? null
                                  : () => setSheetState(() => working.add(t)),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ─────────────────────── 亮度指示器 ───────────────────────

  Widget _buildBrightnessIndicator(AppLocalizations l10n) {
    final percent = (_brightness * 100).round();
    return Center(
      child: Container(
        padding: const EdgeInsets.all(AppTokens.spaceXl),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.brightness_6_rounded,
              color: Colors.white,
              size: 32,
            ),
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              '$percent%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppTokens.spaceXs),
            Text(
              l10n.novelBrightness,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────── 内联设置面板 ───────────────────────

  Widget _buildInlineSettings(
      AppLocalizations l10n, Color bg, Color textColor) {
    final isDesktop =
        MediaQuery.sizeOf(context).width >= AppTokens.desktopBreakpoint;

    final panel = Material(
      // 面板外壳 = 阅读纸色（原设计，与阅读页融为一体，不随主题染色）；
      // 强调色只留给面板内的卡片。
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: _NovelInlineSettings(
        prefs: _prefs,
        brightness: _brightness,
        onChanged: _onPrefsChanged,
        onPreview: _onPrefsPreview,
        onBrightnessChanged: _setBrightness,
        onClose: _toggleInlineSettings,
        onCache: _isLocalMode ? null : _showCacheChaptersDialog,
        onResetBook: _resetBookPrefs,
        onConfigureToolbar: _showBottomToolbarConfig,
        tts: _tts,
        searchController: _settingsSearchController,
        onSearchChanged: (_) => setState(() {}),
        onShowTapZonePreview: () => _showTapZonePreview(l10n),
        novelId: widget.novelId,
        novelName: widget.title,
        sourceId: widget.sourceId,
        sourceName: _source?.name ?? '',
        onPurgeChanged: _reloadPurgeRules,
        // 预下载配置保存后刷新阅读器内的快照，触发判定即时生效。
        onPreDownloadChanged: () async {
          _preDownloadPrefs = await NovelPreDownloadPreferences.load();
        },
        // AI 功能组：速览 / 翻译 / 配图入口。
        onOpenSummary: _showReadingOverview,
        onTranslate: _showTranslationSheet,
        onGenerateIllustration: _generateAiIllustration,
        // 多角色朗读：角色与声音面板入口。
        onOpenTtsCast: _showTtsCastSheet,
      ),
    );

    if (isDesktop) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: panel,
        ),
      );
    }
    return Align(
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        heightFactor: 0.55,
        child: panel,
      ),
    );
  }
}

/// 居中的提示信息（错误 / 空）。

/// 滚动模式「无缝连排」的单个章节段。
///
/// 一个段承载一章的正文块与排版元信息，多个段按章节升序拼在同一条
/// [ListView] 里，形成「滚到底即可继续读下一章」的连续正文。
class _NovelScrollSegment {
  _NovelScrollSegment({
    required this.chapterIndex,
    required this.title,
    required this.blocks,
    required this.rawBlocks,
    required this.showTitle,
  });

  /// 章节目录下标（[_NovelReaderScreenState._effectiveChapters] 的下标）。
  final int chapterIndex;

  /// 章节标题（段首标题项 / 页脚显示）。
  final String title;

  /// 已应用净化规则与繁简转换的正文块（渲染用）。
  final List<NovelBlock> blocks;

  /// 抓取到的原始正文块（切回该章时回填 `_rawParagraphs`，供重新转换）。
  final List<NovelBlock> rawBlocks;

  /// 是否在段首渲染章节大标题。
  final bool showTitle;

  /// 段首锚点：用于按视口位置判定「当前主导章」与段内滚动比例。
  ///
  /// 首项为标题项；不显示标题时挂在第一个正文块上。
  final GlobalKey anchorKey = GlobalKey();

  /// 最近一次测量到的段首内容坐标（= 滚动像素 + 视口 dy）。
  ///
  /// 内容坐标不随滚动变化，因此列表把段首项回收（RenderObject 失联）后
  /// 仍可用它判定段位置；仅在图片加载等导致段高变化时轻微失真，下一次
  /// 测量即修正。
  double? lastTopPixels;

  /// 最近一次测得的段高（像素）。
  ///
  /// 相邻段段首只有一端被列表构建时测不出差值，用该缓存兜底——否则章内
  /// 比例会退回上一次的旧值再跳变（表现为进度条回弹）。
  double? knownHeight;

  int get itemCount => blocks.length + (showTitle ? 1 : 0);
}

/// 阅读速览面板：模式切换（离线/云端）+ 章节内容摘要 + 云端 API 设置 +
/// 阅读数据统计（折叠于底部）。独立 StatefulWidget 便于管理输入框与生成态。
class _ReadingOverviewPanel extends StatefulWidget {
  const _ReadingOverviewPanel({
    required this.l10n,
    required this.service,
    required this.settings,
    required this.initialMode,
    required this.chapterText,
    required this.localResult,
    required this.statsWidget,
  });

  final AppLocalizations l10n;
  final NovelSummaryService service;
  final NovelSummarySettings settings;
  final NovelOverviewMode initialMode;
  final String chapterText;
  final String localResult;
  final Widget statsWidget;

  @override
  State<_ReadingOverviewPanel> createState() => _ReadingOverviewPanelState();
}

class _ReadingOverviewPanelState extends State<_ReadingOverviewPanel> {
  late NovelOverviewMode _mode;
  bool _generating = false;
  String? _apiResult;
  String? _apiError;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  Future<void> _setMode(NovelOverviewMode m) async {
    if (m == _mode) return;
    setState(() => _mode = m);
    await widget.settings.setMode(m);
  }

  /// 跳转 AI 配置页（速览模式 / 通用与速览接口统一在 AI 配置页管理）。
  void _openAiSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsAiScreen()),
    );
  }

  Future<void> _generate() async {
    // 统一读取「速览」功能级配置（独立接口优先，回落通用 AI 配置）。
    final cfg = await widget.settings.getSummaryConfig();
    if (cfg.baseUrl.trim().isEmpty) {
      setState(() {
        _apiError = widget.l10n.overviewApiMissing;
      });
      return;
    }
    setState(() {
      _generating = true;
      _apiError = null;
      _apiResult = null;
    });
    try {
      final r = await widget.service.cloudSummary(widget.chapterText, cfg);
      if (!mounted) return;
      setState(() {
        _apiResult = r;
        _generating = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _apiError = '${widget.l10n.overviewApiError}：$e';
        _generating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppTokens.spaceMd, AppTokens.spaceMd,
          AppTokens.spaceMd, AppTokens.spaceLg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.novelReadingSummary, style: theme.textTheme.titleLarge),
          const SizedBox(height: AppTokens.spaceMd),
          // 总结方式切换。
          SegmentedButton<NovelOverviewMode>(
            segments: <ButtonSegment<NovelOverviewMode>>[
              ButtonSegment<NovelOverviewMode>(
                value: NovelOverviewMode.local,
                label: Text(l10n.overviewModeLocal),
              ),
              ButtonSegment<NovelOverviewMode>(
                value: NovelOverviewMode.api,
                label: Text(l10n.overviewModeApi),
              ),
            ],
            selected: <NovelOverviewMode>{_mode},
            onSelectionChanged: (s) => _setMode(s.first),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          Text(l10n.overviewChapterSummary, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppTokens.spaceSm),
          // 摘要内容。
          if (_mode == NovelOverviewMode.local)
            if (widget.localResult.isEmpty)
              Text(
                l10n.overviewEmpty,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              )
            else
              SelectableText(widget.localResult,
                  style: theme.textTheme.bodyMedium)
          else if (_generating)
            const Padding(
              padding: EdgeInsets.all(AppTokens.spaceMd),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_apiResult != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SelectableText(_apiResult!, style: theme.textTheme.bodyMedium),
                const SizedBox(height: AppTokens.spaceSm),
                Wrap(
                  spacing: AppTokens.spaceSm,
                  children: <Widget>[
                    TextButton.icon(
                      onPressed: _generate,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(l10n.overviewRetry),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _apiResult!));
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: Text(l10n.overviewCopy),
                    ),
                  ],
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (_apiError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
                    child: Text(
                      _apiError!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                FilledButton.icon(
                  onPressed: _generate,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: Text(l10n.overviewGenerate),
                ),
              ],
            ),
          // AI 配置入口（接口与速览配置统一在 AI 配置页管理）。
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _openAiSettings,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: Text(l10n.aiSettingsTitle),
            ),
          ),
          // 阅读数据（保留原统计卡）。
          ExpansionTile(
            title: Text(l10n.statsOverviewTitle),
            initiallyExpanded: true,
            children: <Widget>[widget.statsWidget],
          ),
        ],
      ),
    );
  }
}

class _CenterMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final VoidCallback? onRetry;
  const _CenterMessage(
      {required this.icon, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: AppTokens.spaceMd),
            Text(message, style: Theme.of(context).textTheme.bodyMedium),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: AppTokens.spaceMd),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(AppLocalizations.of(context).retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 章节大标题渲染（#7）：支持左 / 中 / 右对齐与「隐藏」；分段模式下主行(章名) +
/// 次行(书名) 两行。paged 与 scroll 两种模式共用，保证排版一致。
Widget _buildChapterTitleWidget(
  NovelReaderPreferences prefs,
  String chapterTitle,
  String bookName,
) {
  if (!prefs.showChapterTitleInBody ||
      prefs.titleAlign == NovelTitleAlign.hidden ||
      chapterTitle.isEmpty) {
    return const SizedBox.shrink();
  }
  final mainStyle = prefs.resolveTitleTextStyle();
  final cross = switch (prefs.titleAlign) {
    NovelTitleAlign.left => CrossAxisAlignment.start,
    NovelTitleAlign.center => CrossAxisAlignment.center,
    NovelTitleAlign.right => CrossAxisAlignment.end,
    NovelTitleAlign.hidden => CrossAxisAlignment.start,
  };
  final textAlign = switch (prefs.titleAlign) {
    NovelTitleAlign.left => TextAlign.left,
    NovelTitleAlign.center => TextAlign.center,
    NovelTitleAlign.right => TextAlign.right,
    NovelTitleAlign.hidden => TextAlign.left,
  };
  Widget titleBlock;
  if (prefs.titleSegmentMode) {
    final subStyle = mainStyle.copyWith(
      fontSize: (mainStyle.fontSize ?? 18) * prefs.titleSubScale,
      height: prefs.titleSubLineSpacing,
    );
    titleBlock = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: cross,
      children: <Widget>[
        AutoTranslatedText(
          text: chapterTitle,
          kind: TranslatableTextKind.title,
          style: mainStyle,
          textAlign: textAlign,
        ),
        SizedBox(height: prefs.titleSegmentSpacing),
        Text(
          bookName,
          style: subStyle,
          textAlign: textAlign,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  } else {
    titleBlock = AutoTranslatedText(
      text: chapterTitle,
      kind: TranslatableTextKind.title,
      style: mainStyle,
      textAlign: textAlign,
    );
  }
  // SizedBox(width: double.infinity) 让 titleBlock 占满父宽度，
  // 确保 titleAlign = center / right 时 Column / Text 真正居中 / 右对齐
  // （父级 Column 是 crossAxisAlignment.start，不占满宽度会导致对齐失效）。
  return Padding(
    padding: EdgeInsets.only(
      top: prefs.titleTopMargin,
      bottom: prefs.titleBottomMargin,
    ),
    child: SizedBox(
      width: double.infinity,
      child: titleBlock,
    ),
  );
}

/// 页眉 / 页脚槽位内容的本地化标签（#8）。
String _hfContentLabel(NovelHeaderFooterContent c, AppLocalizations l10n) {
  switch (c) {
    case NovelHeaderFooterContent.none:
      return l10n.novelHfNone;
    case NovelHeaderFooterContent.time:
      return l10n.novelHfTime;
    case NovelHeaderFooterContent.battery:
      return l10n.novelHfBattery;
    case NovelHeaderFooterContent.chapterTitle:
      return l10n.novelHfChapterTitle;
    case NovelHeaderFooterContent.bookName:
      return l10n.novelHfBookName;
    case NovelHeaderFooterContent.pageNumber:
      return l10n.novelHfPageNumber;
    case NovelHeaderFooterContent.progressPercent:
      return l10n.novelHfProgressPercent;
    case NovelHeaderFooterContent.pageAndProgress:
      return l10n.novelHfPageAndProgress;
    case NovelHeaderFooterContent.timeAndBattery:
      return l10n.novelHfTimeAndBattery;
    case NovelHeaderFooterContent.bookPageNumber:
      return l10n.novelHfBookPageNumber;
  }
}

/// 自定义虚线下划线文字：当 [NovelReaderPreferences.underlineDashed]
/// 开启时，用 [CustomPaint] 在每行文字基线下方按 `dashLength` / `dashGap`
/// 绘制虚线，弥补原生 `TextDecorationStyle.dashed` 不支持自定义段长/间隙
/// 的不足。
class _DashedUnderlineText extends StatelessWidget {
  final String text;
  final TextStyle style;

  /// 下划线样式（扩展：wavy / dotted 走本组件自定义绘制）。
  final NovelUnderlineStyle underlineStyle;
  final double dashLength;
  final double dashGap;
  final double thickness;
  final Color? color;

  const _DashedUnderlineText({
    required this.text,
    required this.style,
    this.underlineStyle = NovelUnderlineStyle.dashed,
    required this.dashLength,
    required this.dashGap,
    required this.thickness,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints constraints) {
        final TextPainter painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.left,
          textScaler: MediaQuery.textScalerOf(ctx),
        )..layout(maxWidth: constraints.maxWidth);
        final List<LineMetrics> lines = painter.computeLineMetrics();
        final Size painterSize = Size(painter.width, painter.height);
        return Stack(
          children: <Widget>[
            Text(text, style: style),
            Positioned(
              left: 0,
              top: 0,
              child: CustomPaint(
                size: painterSize,
                painter: _DashedUnderlinePainter(
                  style: underlineStyle,
                  lines: lines,
                  dashLength: dashLength <= 0 ? 1.0 : dashLength,
                  dashGap: dashGap <= 0 ? 0.0 : dashGap,
                  thickness: thickness <= 0 ? 1.0 : thickness,
                  color: color ?? style.color ?? const Color(0xFF000000),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 把活动选区 / 已存划线背景合并成富文本。
///
/// 逐字符记录背景色，再按相同背景色连续段合并为 [TextSpan]。
/// 分页模式下每行是单行视觉行，[softWrap]=false+[maxLines]=1；
/// 滚动模式下为整段文字，应传 [softWrap]=true 且不设 maxLines。
Widget buildSelectionRichText(
  String text,
  TextStyle base,
  List<HighlightSpan> spans, {
  bool softWrap = false,
  int? maxLines,
  TextOverflow overflow = TextOverflow.clip,
}) {
  final n = text.length;
  // 逐字符效果信息：背景色 + 装饰样式 + 划线颜色（独立存储，可同时存在）
  final List<int?> bg = List<int?>.filled(n, null);
  final List<HighlightEffect?> effects = List<HighlightEffect?>.filled(n, null);
  final List<int?> uc = List<int?>.filled(n, null); // underline color
  // 先铺已存划线（低优先级），再覆盖活动选区（高优先级）。
  for (final s in spans.where((s) => !s.isActive)) {
    for (var i = s.start; i < s.end && i < n; i++) {
      if (s.effect == HighlightEffect.bg) {
        bg[i] = s.color;
      } else {
        // 划线效果：存储效果类型和颜色（不设背景色）
        effects[i] = s.effect;
        uc[i] = s.color;
      }
    }
  }
  for (final s in spans.where((s) => s.isActive)) {
    for (var i = s.start; i < s.end && i < n; i++) {
      if (s.effect == HighlightEffect.bg) {
        bg[i] = s.color;
      } else {
        effects[i] = s.effect;
        uc[i] = s.color;
      }
    }
  }
  final children = <TextSpan>[];
  var i = 0;
  while (i < n) {
    final c = bg[i];
    final eff = effects[i];
    final underlineColor = uc[i];
    var j = i + 1;
    while (
        j < n && bg[j] == c && effects[j] == eff && uc[j] == underlineColor) {
      j++;
    }
    TextStyle? style;
    if (c != null) {
      style = base.copyWith(backgroundColor: Color(c));
    }
    if (eff != null && eff != HighlightEffect.bg) {
      final decoration = TextDecoration.underline;
      final decorationStyle = switch (eff) {
        HighlightEffect.underline => TextDecorationStyle.solid,
        HighlightEffect.wavy => TextDecorationStyle.wavy,
        HighlightEffect.dotted => TextDecorationStyle.dotted,
        _ => TextDecorationStyle.solid,
      };
      final baseStyle = style ?? base;
      style = baseStyle.copyWith(
        decoration: decoration,
        decorationStyle: decorationStyle,
        decorationColor:
            Color(underlineColor ?? 0x80FF0000).withValues(alpha: 0.8),
        decorationThickness: 1.5,
      );
    }
    children.add(
      TextSpan(
        text: text.substring(i, j),
        style: style,
      ),
    );
    i = j;
  }
  return Text.rich(
    TextSpan(style: base, children: children),
    softWrap: softWrap,
    maxLines: maxLines,
    overflow: overflow,
  );
}

class _DashedUnderlinePainter extends CustomPainter {
  /// 下划线样式：dashed / wavy / dotted。
  final NovelUnderlineStyle style;
  final List<LineMetrics> lines;
  final double dashLength;
  final double dashGap;
  final double thickness;
  final Color color;

  _DashedUnderlinePainter({
    required this.style,
    required this.lines,
    required this.dashLength,
    required this.dashGap,
    required this.thickness,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;
    // 基线下方偏移：约字号 × 0.18，与 Flutter 原生下划线位置接近。
    final double underlineOffset =
        lines.isNotEmpty ? (lines.first.height * 0.18).clamp(1.0, 4.0) : 2.0;
    final double step = dashLength + dashGap;
    for (final LineMetrics line in lines) {
      final double y = line.baseline + underlineOffset;
      final double lineEnd = line.left + line.width;
      switch (style) {
        case NovelUnderlineStyle.wavy:
          // 波浪线：正弦半波折线，波幅 ≈ max(2, 字号×0.12)，波长 = dashLength。
          final amp = lines.isNotEmpty
              ? (lines.first.height * 0.10).clamp(2.0, 4.0)
              : 3.0;
          final wl = dashLength <= 0 ? 6.0 : dashLength * 2;
          final path = ui.Path();
          var x = line.left;
          path.moveTo(x, y);
          var up = true;
          while (x < lineEnd) {
            final nx = (x + wl).clamp(line.left, lineEnd);
            path.quadraticBezierTo(
              (x + nx) / 2,
              up ? y - amp : y + amp,
              nx,
              y,
            );
            up = !up;
            x = nx;
          }
          canvas.drawPath(path, paint);
        case NovelUnderlineStyle.dotted:
          // 点线：以 dashLength 为点径、dashGap 为间隔画圆点。
          final r = (dashLength <= 0 ? 1.0 : dashLength) / 2;
          final dotPaint = Paint()
            ..color = color
            ..style = PaintingStyle.fill;
          double x = line.left + r;
          while (x < lineEnd) {
            canvas.drawCircle(Offset(x, y), r, dotPaint);
            x += r * 2 + (dashGap <= 0 ? 2.0 : dashGap);
          }
        case NovelUnderlineStyle.solid || NovelUnderlineStyle.dashed:
          // 实线段序列（dashed 按 dashLength/dashGap；solid 单段铺满）。
          double x = line.left;
          while (x < lineEnd) {
            final double segEnd = (x + dashLength).clamp(line.left, lineEnd);
            canvas.drawLine(Offset(x, y), Offset(segEnd, y), paint);
            x += step;
          }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedUnderlinePainter old) {
    return old.style != style ||
        old.dashLength != dashLength ||
        old.dashGap != dashGap ||
        old.thickness != thickness ||
        old.color != color ||
        old.lines.length != lines.length;
  }
}

/// 两端对齐单行文本。
///
/// 分页模式下每行已是精确测量的视觉行，但行宽通常略小于可用宽度；
/// justify 模式把「剩余空间」均摊到字符间隙，使左右两端对齐。
/// 用 [TextPainter] 测自然宽后按 [FittedBox]-free 方案逐字布局：
/// 仅当文本 ≥2 字符且确有剩余空间时启用拉伸，否则退化为普通 Text。
class _JustifiedLineText extends StatelessWidget {
  final String text;
  final TextStyle baseStyle;

  /// 目标行宽（分页时的正文可用宽度）。
  final double targetWidth;

  const _JustifiedLineText({
    required this.text,
    required this.baseStyle,
    required this.targetWidth,
  });

  @override
  Widget build(BuildContext context) {
    if (text.length < 2 || targetWidth <= 0) {
      return Text(text, style: baseStyle, softWrap: false, maxLines: 1);
    }
    return LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints constraints) {
        final dir = Directionality.of(ctx);
        final scaler = MediaQuery.textScalerOf(ctx);
        final tp = TextPainter(
          text: TextSpan(text: text, style: baseStyle),
          textDirection: dir,
          textScaler: scaler,
        )..layout(maxWidth: double.infinity);
        final naturalW = tp.maxIntrinsicWidth;
        final lineHeight = tp.height;
        tp.dispose();
        // 剩余空间不足 0.5px 或超宽（不应发生，断行已保证）时不拉伸。
        final extra = constraints.maxWidth - naturalW;
        if (extra < 0.5) {
          return Text(text, style: baseStyle, softWrap: false, maxLines: 1);
        }
        // 字符间隙均摊：(n-1) 个间隙。
        final gap = extra / (text.length - 1);
        return SizedBox(
          width: constraints.maxWidth,
          child: CustomPaint(
            size: Size(constraints.maxWidth, lineHeight),
            painter: _JustifiedLinePainter(
              text: text,
              style: baseStyle,
              direction: dir,
              scaler: scaler,
              gap: gap,
            ),
          ),
        );
      },
    );
  }
}

/// 两端对齐行绘制器：逐字符按均摊间隙排布。
class _JustifiedLinePainter extends CustomPainter {
  final String text;
  final TextStyle style;
  final TextDirection direction;
  final TextScaler scaler;
  final double gap;

  _JustifiedLinePainter({
    required this.text,
    required this.style,
    required this.direction,
    required this.scaler,
    required this.gap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final tp = TextPainter(
      textDirection: direction,
      textScaler: scaler,
    );
    double x = 0;
    for (var i = 0; i < text.length; i++) {
      tp.text = TextSpan(text: text[i], style: style);
      tp.layout(maxWidth: double.infinity);
      tp.paint(canvas, Offset(x, 0));
      x += tp.maxIntrinsicWidth + gap;
    }
    tp.dispose();
  }

  @override
  bool shouldRepaint(covariant _JustifiedLinePainter old) =>
      old.text != text || old.gap != gap || old.style != style;
}

/// 单页小说内容（含页眉页脚）。
class _NovelPageWidget extends StatelessWidget {
  final List<NovelPageItem> lines;
  final NovelReaderPreferences prefs;
  final Color bg;
  final Color textColor;
  final NovelPageAnimation animation;
  final String chapterTitle;
  final String bookName;
  final int pageIndex;
  final int totalPages;
  final String time;
  final int batteryLevel;
  final NovelHeaderFooterContent headerCenter;
  final NovelHeaderFooterContent footerCenter;
  final int? headerFooterColor;
  final double headerFooterMargin;

  /// TTS 当前朗读段落索引（-1 表示未朗读 / TTS 未启动）。
  final int ttsCurrentIndex;

  /// TTS 是否处于激活状态（playing 或 paused）。
  final bool ttsActive;

  /// 点击段落回调：传入段落在 paragraphs 中的全局索引。
  /// TTS 模式下点击某行时回调：返回该行所属段落下标。
  /// （TextColumn 精确字符坐标保留在 NovelLine.charLefts 中，
  /// 供未来长按选区等场景使用；tap 时默认命中段落首字符即可。）
  final void Function(int paragraphIndex)? onParagraphTap;

  /// 插图点击回调：打开大图查看器（传入图片 URL 与书源）。
  final void Function(String url, PluginConfig? source)? onImageTap;

  /// 当前章节所属书源（插图块未携带 source 时，作为防盗链 headers 兜底）。
  final PluginConfig? source;

  /// 书内搜索关键词（非空且行内命中时，正文行渲染为高亮富文本）。
  final String? searchKeyword;

  /// 正则搜索模式下的已编译表达式（与 [searchKeyword] 二选一生效，
  /// 非空时优先按正则匹配高亮）。
  final RegExp? searchRegex;

  /// 选区控制器：渲染活动选区 + 已存划线背景。
  final NovelSelectionController selectionController;

  /// 长按选区结束后（有非空选区）回调，用于显示工具条。
  final VoidCallback? onSelectionConfirmed;

  /// 长按选区激活状态变化回调（开始 = true / 结束 = false），由阅读器 State
  /// 用以置位 [_longPressEngaged]，使翻页手势在选区拖拽期间让出指针。
  final void Function(bool engaged)? onSelectionActiveChanged;

  /// 整本页码：给定章内页码，返回跨章累计的全书页位文案
  /// （由阅读器状态基于会话分页缓存计算；null/空串表示不可用）。
  final String Function(int page)? bookPageLabel;

  const _NovelPageWidget({
    required this.lines,
    this.onImageTap,
    this.source,
    required this.selectionController,
    this.onSelectionConfirmed,
    this.onSelectionActiveChanged,
    required this.prefs,
    required this.bg,
    required this.textColor,
    required this.animation,
    required this.chapterTitle,
    required this.bookName,
    required this.pageIndex,
    required this.totalPages,
    required this.time,
    required this.batteryLevel,
    required this.headerCenter,
    required this.footerCenter,
    required this.headerFooterColor,
    required this.headerFooterMargin,
    this.ttsCurrentIndex = -1,
    this.ttsActive = false,
    this.searchKeyword,
    this.searchRegex,
    this.onParagraphTap,
    this.bookPageLabel,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = prefs.resolveBodyTextStyle(textColor);
    // 章节标题样式：与分页测量共用 [NovelPaginator.headingStyleOf]——
    // 两处样式必须逐字段一致，否则标题行会按不同字宽断行/计高，
    // 表现为右侧字符被裁或页底溢出（「字符显示不全」）。
    final headingStyle = NovelPaginator.headingStyleOf(textStyle);

    // 页眉页脚颜色：自定义优先，否则跟随正文色半透明。
    final hfColor = headerFooterColor != null
        ? Color(headerFooterColor!)
        : textColor.withValues(alpha: 0.5);
    final headerFooterStyle = TextStyle(
      fontSize: 12,
      color: hfColor,
      fontFamily: prefs.customFontPath != null
          ? NovelReaderPreferences.customLoadedFontFamily
          : prefs.fontFamily,
    );

    final progress = totalPages > 0 ? (pageIndex + 1) / totalPages : 0.0;

    return Container(
      color: bg,
      // 仅纵向用正文边距；页眉页脚用各自的 [headerFooterMargin]，正文用
      // [prefs.margin]，互不干扰（#8）。
      padding: EdgeInsets.symmetric(vertical: prefs.margin),
      child: Column(
        // stretch：强制正文滚动区占满整页宽度。否则 Column 默认 center 会让
        // SingleChildScrollView 收缩包裹到内容宽度并被水平居中，实际左右留白
        // 变成 margin + 剩余空间的一半，随每页最长行宽漂移（边距不守设定值）。
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: headerFooterMargin),
            child: _buildHeaderFooter(
              prefs.headerLeft,
              headerCenter,
              prefs.headerRight,
              headerFooterStyle,
              chapterTitle,
              bookName,
              pageIndex,
              totalPages,
              progress,
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Expanded(
            // LayoutBuilder 作为 Expanded 的直接子节点，拿到的是「有界」的滚动区高度
            // （由外层 Expanded 约束）。SingleChildScrollView 内部 Column 是无界高度，
            // 因此插图绝不能用 Expanded（会抛 "RenderFlex unbounded" 并使整页崩溃）；
            // 这里用具体高度的 SizedBox 承载插图，既填满滚动区又不触发 flex 崩溃。
            child: LayoutBuilder(
              builder: (BuildContext ctx, BoxConstraints scrollC) {
                final double scrollH = scrollC.maxHeight;
                final double imgW = scrollC.maxWidth - prefs.margin * 2;
                return SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  clipBehavior: Clip.hardEdge,
                  padding: EdgeInsets.symmetric(horizontal: prefs.margin),
                  // 注意：此处不再用 AnimatedBuilder(selectionController) 包裹——
                  // 否则选区变化会重建整页、连带重建每行 RawGestureDetector，长按
                  // 进行中即被打断（「长按闪一下」）。选区高亮改由 _buildLine 内
                  // 的局部 AnimatedBuilder 处理，只重绘本行文本。
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // 章节大标题仅在第一页顶部渲染（#7，含对齐 / 分段模式）。
                      if (pageIndex == 0)
                        _buildChapterTitleWidget(
                          prefs,
                          chapterTitle,
                          bookName,
                        ),
                      ..._buildPageLines(
                          context, headingStyle, textStyle, imgW, scrollH),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: headerFooterMargin),
            child: _buildHeaderFooter(
              prefs.footerLeft,
              footerCenter,
              prefs.footerRight,
              headerFooterStyle,
              chapterTitle,
              bookName,
              pageIndex,
              totalPages,
              progress,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建单行文本（按行渲染）：搜索高亮 + TTS 高亮 + 点击跳转。
  ///
  /// 每行已是适配宽度的视觉行，首行自带 `　　` 缩进；段距由上层在
  /// [isLastLine] 后统一添加，这里只负责单行的文字与高亮。
  Widget _buildLine(
    BuildContext context,
    NovelLine line,
    TextStyle textStyle, {
    required int lineIndexInPage,
    double? targetWidth,
  }) {
    final isCurrent = ttsActive && line.paragraphIndex == ttsCurrentIndex;
    // 选区背景（活动选区 + 已存划线）：优先于搜索高亮渲染（优先级
    // 活动选区 > 已存高亮 > 搜索）。仅当本行确有选区/划线时才走富文本路径，
    // 否则保持原渲染（搜索 / 虚线下划线 / 纯文本），不影响分页测量。
    final Widget? searchHit =
        _buildSearchHighlight(context, line.text, textStyle);
    // 两端对齐：仅分页模式（本 Widget 即分页页）、正文非标题行、
    // 非段末行时生效——把不满一行的行按「字距均摊」拉伸
    // 到整行宽（与原生 textAlign: justify 视觉等价，且不受单行富文本
    // justify 失效影响）。末行/标题/高亮行保持自然排版。
    // 选区渲染移入下方 AnimatedBuilder：长按选区时只重建本行文本、不重建外层
    // RawGestureDetector，否则识别器被重建、长按进行中即被打断（「长按闪一下」）。
    final bool justifyLineBase =
        prefs.textAlignMode == NovelTextAlignMode.justify &&
            !line.isHeading &&
            !line.isLastLine &&
            searchHit == null &&
            !(prefs.fontUnderline && prefs.needsCustomUnderlinePaint);
    final Widget baseWidget;
    if (searchHit != null) {
      baseWidget = searchHit;
    } else if (prefs.needsCustomUnderlinePaint) {
      baseWidget = _DashedUnderlineText(
        text: line.text,
        style: textStyle,
        underlineStyle: prefs.underlineStyle == NovelUnderlineStyle.solid
            ? NovelUnderlineStyle.dashed
            : prefs.underlineStyle,
        dashLength: prefs.underlineDashLength,
        dashGap: prefs.underlineDashGap,
        thickness: prefs.underlineThickness,
        color: prefs.resolveUnderlineColor(textColor),
      );
    } else if (justifyLineBase) {
      baseWidget = _JustifiedLineText(
        text: line.text,
        baseStyle: textStyle,
        targetWidth: targetWidth ?? 0,
      );
    } else {
      baseWidget = Text(
        line.text,
        style: textStyle,
        // 每行已是按宽度精确测量出的单行文本，禁止再次折行/省略，
        // 保证渲染与分页器测量一致（按行排版）。
        softWrap: false,
        maxLines: 1,
        overflow: TextOverflow.clip,
      );
    }

    final content = AnimatedBuilder(
      animation: selectionController,
      builder: (ctx, _) {
        final selSpans =
            selectionController.lineSpans(pageIndex, lineIndexInPage);
        final Widget tw = selSpans.isNotEmpty
            ? buildSelectionRichText(line.text, textStyle, selSpans)
            : baseWidget;
        return isCurrent
            ? Container(
                decoration: BoxDecoration(
                  color: prefs.resolveTextColor(bg).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTokens.radiusXs),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: tw,
              )
            : tw;
      },
    );

    // TTS 激活时，点按任意行即跳转到该段落开始朗读（按所属段落）。
    // 仅 TTS 激活才包裹手势：非朗读态下点按文本照常由外层翻页。
    //
    // 用 onTap（而非 onLongPress）：朗读场景下「点哪读哪」是主交互，用户期望
    // 轻点段落即跳转；长按反而难发现。内层 TapGestureRecognizer 与外层 onTapUp
    // 同在嵌套竞技场中，内层命中即胜出、外层 onTapUp 不再触发——因此点文本不会
    // 翻页、也不会切换 UI，只跳转朗读位置；点边距/留白仍走外层翻页。该包裹仅在
    // ttsActive 时存在，故非朗读态点击文本照常播放翻页动画（旧「翻页动画消失」问题
    // 不复现）。
    //
    // excludeFromSemantics:true —— 不为每行生成无障碍语义节点。朗读时文本由 TTS
    // 引擎直接发声，逐行语义节点既冗余，又会在每段切换时随整页重建被反复创建/销毁，
    // 导致无障碍树（AXTree）节点堆积，触发 "will not be in the tree" 刷屏；排除后
    // 该问题消除，且不影响朗读与手势响应。
    if (ttsActive && onParagraphTap != null) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        excludeFromSemantics: true,
        onTap: () => onParagraphTap!.call(line.paragraphIndex),
        child: content,
      );
    }
    return content;
  }

  /// 把本页所有行构建为 Widget 列表（含文本行的长按选区手势与插图渲染）。
  ///
  /// 文本行在非 TTS 态下包裹长按选区手势（长按=选区，短按仍由外层翻页手势
  /// 处理——二者在竞技场自然分离）；TTS 态下不包裹，避免与「点哪读哪」的
  /// 段落跳转冲突。
  List<Widget> _buildPageLines(
    BuildContext context,
    TextStyle headingStyle,
    TextStyle textStyle,
    double imgW,
    double scrollH,
  ) {
    final List<Widget> result = <Widget>[];
    for (var li = 0; li < lines.length; li++) {
      final item = lines[li];
      if (item is NovelTextLineItem) {
        final Widget line = _buildLine(
          context,
          item.line,
          item.line.isHeading ? headingStyle : textStyle,
          lineIndexInPage: li,
          targetWidth: imgW,
        );
        final Widget wrapped = !ttsActive
            ? _StableLongPressDetector(
                onLongPressStart: (d) => _onSelLongPressStart(li, d),
                onLongPressMoveUpdate: (d) => _onSelLongPressMove(li, d),
                onLongPressEnd: _onSelLongPressEnd,
                child: line,
              )
            : line;
        result.add(wrapped);
        if (item.line.isLastLine) {
          result.add(SizedBox(height: prefs.paragraphSpacing));
        }
      } else if (item is NovelImageItem) {
        // 翻页模式插图独占一页：占满可用高度居中显示。点按即打开大图查看器
        // （与滚动模式一致）；长按同样可打开，二者不冲突（长按不会触发 onTap）。
        result.add(
          SizedBox(
            width: imgW,
            height: scrollH,
            child: GestureDetector(
              onTap: () => onImageTap?.call(item.image.url, item.image.source),
              onLongPress: () =>
                  onImageTap?.call(item.image.url, item.image.source),
              child: SourceImage(
                url: item.image.url,
                source: item.image.source ?? source,
                width: imgW,
                height: scrollH,
                fit: BoxFit.contain,
                decodeCapWidthPx: 1600,
              ),
            ),
          ),
        );
      }
    }
    return result;
  }

  /// 长按选区起始：记录锚点全局偏移并标记选区激活（让翻页手势让出指针）。
  void _onSelLongPressStart(int lineIndexInPage, LongPressStartDetails d) {
    // MD3「Thunk」：长按开始文本选择。
    AppHaptics.thunk();
    final item = lines[lineIndexInPage];
    if (item is! NovelTextLineItem) return;
    final ci = item.line.hitTestCharOffset(d.localPosition.dx);
    final global = selectionController.globalOffsetFor(
      pageIndex,
      lineIndexInPage,
      ci,
    );
    onSelectionActiveChanged?.call(true);
    selectionController.setSelecting(true);
    selectionController.setSelectionAnchor(global);
    // 长按即选中锚点所在的「词/句」（标点/空白切分），拖拽时由 move 重定义选区。
    final word = selectionController.wordRangeAt(global);
    if (word != null) selectionController.setSelection(word.start, word.end);
  }

  /// 长按拖拽中：以锚点为起点、当前落点为终点更新活动选区。
  ///
  /// Phase 0 仅支持行内选区：纵向移出本行时 [hitTestCharOffset] 自然夹紧到
  /// 行首/行尾；跨行整段由工具条「整段」按钮覆盖。
  void _onSelLongPressMove(int lineIndexInPage, LongPressMoveUpdateDetails d) {
    final anchor = selectionController.selectionAnchor;
    if (anchor == null) return;
    final item = lines[lineIndexInPage];
    if (item is! NovelTextLineItem) return;
    final ci = item.line.hitTestCharOffset(d.localPosition.dx);
    final global = selectionController.globalOffsetFor(
      pageIndex,
      lineIndexInPage,
      ci,
    );
    // 关键：手指轻微抖动时 hitTest 会命中同一个字符（global == anchor），
    // 若直接 setSelection(anchor, anchor) 会走 a==b → clearSelection，
    // 把长按刚建立的整词/句选区清空（真机「工具栏不出现」的根因：
    // longPressStart hasSel=true → move 微抖 → clearSelection → end hasSel=false）。
    // 仅在落点确实变化时才更新选区，微抖动保持原选区不动。
    if (global == anchor) return;
    selectionController.setSelection(anchor, global);
  }

  /// 长按结束：解除选区激活；若有非空选区则通知外层显示工具条。
  void _onSelLongPressEnd() {
    onSelectionActiveChanged?.call(false);
    selectionController.setSelecting(false);
    selectionController.setSelectionAnchor(null);
    if (selectionController.hasSelection) {
      onSelectionConfirmed?.call();
    }
  }

  /// 搜索关键词命中行 → 高亮富文本；未命中返回 null（走原渲染路径）。
  ///
  /// [searchRegex] 非空时按正则匹配（优先），否则按关键词大小写不敏感
  /// 子串匹配。行文本与分页测量逐字一致，Text.rich 仅给命中片段附加
  /// 背景色/加粗，约束保持 softWrap:false + 单行 + clip，不影响按行排版。
  Widget? _buildSearchHighlight(
    BuildContext context,
    String text,
    TextStyle textStyle,
  ) {
    final spans = searchHitSpans(
      text: text,
      query: searchKeyword,
      regex: searchRegex,
      hitStyle: textStyle.copyWith(
        backgroundColor:
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
        fontWeight: FontWeight.w700,
      ),
    );
    if (spans == null) return null;
    return Text.rich(
      TextSpan(style: textStyle, children: spans),
      // 与未命中行的 Text 约束一致：不折行/不省略，保证渲染与测量相同。
      softWrap: false,
      maxLines: 1,
      overflow: TextOverflow.clip,
    );
  }

  Widget _buildHeaderFooter(
    NovelHeaderFooterContent left,
    NovelHeaderFooterContent center,
    NovelHeaderFooterContent right,
    TextStyle style,
    String chapter,
    String book,
    int page,
    int total,
    double progress,
  ) {
    String resolve(NovelHeaderFooterContent c) {
      return switch (c) {
        NovelHeaderFooterContent.none => '',
        NovelHeaderFooterContent.time => time,
        NovelHeaderFooterContent.battery =>
          batteryLevel >= 0 ? '$batteryLevel%' : '',
        NovelHeaderFooterContent.chapterTitle => chapter,
        NovelHeaderFooterContent.bookName => book,
        NovelHeaderFooterContent.pageNumber => '${page + 1}/$total',
        NovelHeaderFooterContent.progressPercent =>
          '${(progress * 100).round()}%',
        NovelHeaderFooterContent.pageAndProgress =>
          '${page + 1}/$total  ${(progress * 100).round()}%',
        NovelHeaderFooterContent.timeAndBattery =>
          '${time}${batteryLevel >= 0 ? '  $batteryLevel%' : ''}',
        NovelHeaderFooterContent.bookPageNumber =>
          bookPageLabel?.call(page) ?? '',
      };
    }

    final leftText = resolve(left);
    final centerText = resolve(center);
    final rightText = resolve(right);

    // 中间槽位为空（none 或空串）时退化为左右两槽，保持 spaceBetween。
    if (center == NovelHeaderFooterContent.none || centerText.isEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Flexible(
            child:
                Text(leftText, style: style, overflow: TextOverflow.ellipsis),
          ),
          Flexible(
            child:
                Text(rightText, style: style, overflow: TextOverflow.ellipsis),
          ),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Expanded(
          child: Text(leftText, style: style, overflow: TextOverflow.ellipsis),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceSm),
          child: Text(centerText,
              style: style,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis),
        ),
        Expanded(
          child: Text(rightText,
              style: style,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

/// 内联设置面板（桌面右侧 ~360px / 移动底部 ~55%）。
///
/// 包含字号 / 行距 / 段距 / 边距滑块、翻页动画选择、背景预设、文字阴影开关、
/// 亮度滑块。所有变更即时生效并持久化。

/// 点按区域预览覆盖层：在对话框内半透明展示当前布局的各点击分区，
/// 用不同颜色区分 prev / next / toggle 操作区域，并标注中文标签。
class _TapZonePreviewOverlay extends StatelessWidget {
  final ReaderTapZoneLayout layout;
  final TapZoneInvert invert;
  final bool isVertical;
  final AppLocalizations l10n;

  const _TapZonePreviewOverlay({
    required this.layout,
    required this.invert,
    required this.isVertical,
    required this.l10n,
  });

  // 各操作对应的颜色（半透明）。
  static const Color _prevColor = Color(0x332196F3); // 蓝
  static const Color _nextColor = Color(0x334CAF50); // 绿
  static const Color _toggleColor = Color(0x33FF9800); // 橙

  String _labelFor(TapZoneAction action) {
    switch (action) {
      case TapZoneAction.prev:
        return l10n.tapZonePrev;
      case TapZoneAction.next:
        return l10n.tapZoneNext;
      case TapZoneAction.toggle:
        return l10n.tapZoneToggle;
    }
  }

  Color _colorFor(TapZoneAction action) {
    switch (action) {
      case TapZoneAction.prev:
        return _prevColor;
      case TapZoneAction.next:
        return _nextColor;
      case TapZoneAction.toggle:
        return _toggleColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 跟随容器自适应：窄屏下对话框宽度不足 280 时按实际宽度缩放，避免预览被截断。
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final double w =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 280;
        final double h =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 420;
        final regions = _resolvedRegions(w, h);
        return ClipRect(
          child: Stack(
            children: <Widget>[
              // 背景网格（模拟阅读页面）
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                ),
              ),
              // 各区域色块 + 标签
              for (final entry in regions)
                Positioned.fromRect(
                  rect: entry.key,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _colorFor(entry.value),
                      border: Border.all(
                        color: _colorFor(entry.value).withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(AppTokens.radiusXs),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _labelFor(entry.value),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _colorFor(entry.value).withValues(alpha: 1.0),
                        shadows: <Shadow>[
                          Shadow(
                            color: Colors.white.withValues(alpha: 0.8),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 解析当前设置下的有效区域（考虑反转），返回 [Rect → Action] 映射。
  /// [w] / [h] 为预览区域实际尺寸（随容器自适应，避免窄屏下被截断）。
  List<MapEntry<Rect, TapZoneAction>> _resolvedRegions(double w, double h) {
    // 原始区域定义（来自 TapZoneResolver._regions 的逻辑副本）。
    final raw = _rawRegions(layout);
    final result = <MapEntry<Rect, TapZoneAction>>[];
    for (final r in raw) {
      final action = TapZoneResolver.resolve(
        layout: layout,
        invert: invert,
        isVertical: isVertical,
        pos: Offset(r.left + r.width / 2, r.top + r.height / 2),
        size: const Size(1, 1),
      );
      result.add(MapEntry(
        Rect.fromLTWH(r.left * w, r.top * h, r.width * w, r.height * h),
        action,
      ));
    }
    return result;
  }

  /// 返回原始区域列表（比例坐标 0..1），同 TapZoneResolver._regions。
  static List<_RawRegion> _rawRegions(ReaderTapZoneLayout layout) {
    switch (layout) {
      case ReaderTapZoneLayout.leftRight:
        return const <_RawRegion>[
          _RawRegion(0, 0, 0.45, 1), // prev
          _RawRegion(0.45, 0, 0.1, 1), // toggle
          _RawRegion(0.55, 0, 0.45, 1), // next
        ];
      case ReaderTapZoneLayout.lShape:
        // 两个 L 形 + 中心 toggle（与 TapZoneResolver 保持一致）。
        return const <_RawRegion>[
          _RawRegion(0, 0, 0.33, 1), // prev 左列（全高）
          _RawRegion(0.67, 0, 0.33, 1), // next 右列（全高）
          _RawRegion(0.33, 0, 0.34, 0.33), // next 上中条
          _RawRegion(0.33, 0.67, 0.34, 0.33), // prev 下中条
          _RawRegion(0.33, 0.33, 0.34, 0.34), // toggle 中心
        ];
      case ReaderTapZoneLayout.kindle:
        return const <_RawRegion>[
          _RawRegion(0, 0, 1, 0.15), // toggle (顶部)
          _RawRegion(0, 0.15, 0.35, 0.85), // prev (左侧)
          _RawRegion(0.35, 0.15, 0.65, 0.85), // next (右侧)
        ];
      case ReaderTapZoneLayout.bothSides:
        return const <_RawRegion>[
          _RawRegion(0, 0.15, 0.33, 0.7), // next (左上)
          _RawRegion(0.67, 0.15, 0.33, 0.7), // next (右上)
          _RawRegion(0.33, 0.7, 0.34, 0.3), // prev (底部中间)
          _RawRegion(0.33, 0, 0.34, 0.15), // toggle (顶部)
        ];
      case ReaderTapZoneLayout.off:
        return const <_RawRegion>[_RawRegion(0, 0, 1, 1)]; // 全 toggle
    }
  }
}

/// 原始区域（比例坐标 0..1），仅用于预览渲染。
class _RawRegion {
  final double left, top, width, height;
  const _RawRegion(this.left, this.top, this.width, this.height);
}

// ───────────────── 内联设置弹窗搜索关键词 ─────────────────
/// 各设置组的搜索关键词（组标题 + 组内全部具体设置项标题的关键词）。
/// `hasSearchMatch` 与 `_buildSettingsGroup` 共用同一份常量，保证
/// 「是否有组命中」的判定与实际组过滤完全一致；补充关键词即可让
/// 内联弹窗里任意具体设置项（如「预下载」「标题加粗」「双击缩放」）
/// 通过搜索直达对应分组。
const List<String> _kNovelSecColorTerms = <String>[
  '颜色',
  '背景',
  '亮度',
  '夜间',
  '文字色',
  '强调色',
  '背景色',
  '正文颜色',
  '自定义背景色',
  '跟随背景',
  '自动配色',
  '标题色',
];
const List<String> _kNovelSecTextTerms = <String>[
  '字号',
  '行距',
  '段距',
  '边距',
  '字距',
  '字体大小',
  '行高',
  '段落',
];
const List<String> _kNovelSecFontTerms = <String>[
  '粗体',
  '斜体',
  '下划线',
  '字体',
  '字体文件',
  '字族',
  '字重',
  '加粗',
  '自定义字体',
  '等宽',
  '衬线',
  '系统',
  '100-900',
];
const List<String> _kNovelSecTypographyTerms = <String>[
  '对齐',
  '两端对齐',
  '断行',
  '中文',
  '禁则',
  '下划线',
  '实线',
  '虚线',
  '波浪',
  '点线',
  '插图',
  '滚动',
  '图片',
  '通栏',
  '卡片',
  '排版',
  '逐字断行',
  '原生折行',
  '插图对齐',
  '居中',
  '靠左',
  '靠右',
  '卡片式',
  '对齐方式',
  '下划线样式',
  '波浪线',
  '自然',
  '接续',
  '下一章',
  '连排',
  '章末',
];
const List<String> _kNovelSecTitleTerms = <String>[
  '章节标题',
  '标题',
  '位置',
  '字体',
  '分段',
  '字号',
  '显示',
  '加粗',
  '颜色',
  '边距',
  '上边距',
  '下边距',
  '强调色',
  '倍数',
  '倍率',
  '行距',
  '间距',
  '分段模式',
  '对齐',
  '隐藏',
];
const List<String> _kNovelSecHeaderFooterTerms = <String>[
  '页眉',
  '页脚',
  '时间',
  '电量',
  '页数',
  '进度',
  '左侧',
  '右侧',
  '中间',
  '颜色',
  '边距',
];
const List<String> _kNovelSecShadowUnderlineTerms = <String>[
  '阴影',
  '下划线',
  '颜色',
  '虚线',
  '阴影色',
  '文字阴影',
  '模糊',
  '半径',
  '偏移',
  '水平',
  '垂直',
  '线宽',
  '实线段长',
  '间隙',
  '比例',
  '自动',
  '半透明',
];
const List<String> _kNovelSecPageTerms = <String>[
  '翻页',
  '动画',
  '点击',
  '自动翻页',
  '手势',
  '分区',
  '间隔',
  '平滑',
  '双页',
  '模式',
  '滚轮',
  '反转',
  '点击区域',
  '翻转',
  '音量键',
  '预览',
  '点按',
  '左右',
  '上下',
  '全部',
  '关闭',
];
const List<String> _kNovelSecTtsTerms = <String>[
  '朗读',
  '语速',
  '睡眠',
  '后台',
  '语音',
  '定时',
  '剩余',
  '分钟',
  '秒',
];
const List<String> _kNovelSecMiscTerms = <String>[
  '简繁',
  '替换',
  '净化',
  '正则',
  '缓存',
  '恢复',
  '配置',
  '工具栏',
  '转换',
  '繁简转换',
  '繁转简',
  '简转繁',
  '不转换',
  '预下载',
  '章节数',
  '阈值',
  '恢复默认',
  '本书',
  '替换规则',
];
const List<String> _kNovelSecAiTerms = <String>[
  'ai',
  '速览',
  '总结',
  '摘要',
  '翻译',
  '双语',
  '配图',
  '生图',
  '云端',
  '离线',
  'gpt',
  '模型',
  '接口',
  '密钥',
];

class _NovelInlineSettings extends StatelessWidget {
  final NovelReaderPreferences prefs;
  final double brightness;
  final ValueChanged<NovelReaderPreferences> onChanged;
  final ValueChanged<NovelReaderPreferences>? onPreview;
  final ValueChanged<double> onBrightnessChanged;
  final VoidCallback onClose;
  final VoidCallback? onCache;
  final VoidCallback? onResetBook;
  final VoidCallback? onConfigureToolbar;
  final NovelTtsController tts;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback? onShowTapZonePreview;
  final String novelId;
  final String novelName;
  /// 当前源 id / 名称：用于配置「仅本源」净化规则。
  final String sourceId;
  final String sourceName;
  /// 净化规则变更后的回调（重新应用规则并保持阅读位置）。
  final VoidCallback? onPurgeChanged;

  /// 预下载配置保存后的回调（阅读器刷新快照，触发判定即时效）。
  final VoidCallback? onPreDownloadChanged;
  // ── AI 功能组入口回调（打开速览 / 翻译 / 生成配图）──
  final VoidCallback? onOpenSummary;
  final VoidCallback? onTranslate;
  final VoidCallback? onGenerateIllustration;

  /// 多角色朗读：打开「角色与声音」面板。
  final VoidCallback? onOpenTtsCast;

  const _NovelInlineSettings({
    required this.prefs,
    required this.brightness,
    required this.onChanged,
    this.onPreview,
    required this.onBrightnessChanged,
    required this.onClose,
    this.onCache,
    this.onResetBook,
    this.onConfigureToolbar,
    required this.tts,
    required this.searchController,
    required this.onSearchChanged,
    this.onShowTapZonePreview,
    required this.novelId,
    required this.novelName,
    this.sourceId = '',
    this.sourceName = '',
    this.onPurgeChanged,
    this.onPreDownloadChanged,
    this.onOpenSummary,
    this.onTranslate,
    this.onGenerateIllustration,
    this.onOpenTtsCast,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final q = searchController.text.trim().toLowerCase();
    bool groupMatches(String title, List<String> terms) {
      if (q.isEmpty) return true;
      final hay = <String>[title, ...terms].join(' ').toLowerCase();
      return hay.contains(q);
    }

    final bool hasSearchMatch = groupMatches(
            l10n.novelSectionColor, _kNovelSecColorTerms) ||
        groupMatches(l10n.novelSectionText, _kNovelSecTextTerms) ||
        groupMatches(l10n.novelSectionFont, _kNovelSecFontTerms) ||
        groupMatches(l10n.novelTypographyGroup, _kNovelSecTypographyTerms) ||
        groupMatches(l10n.novelSectionTitle, _kNovelSecTitleTerms) ||
        groupMatches(
            l10n.novelSectionHeaderFooter, _kNovelSecHeaderFooterTerms) ||
        groupMatches(
            l10n.novelSectionShadowUnderline, _kNovelSecShadowUnderlineTerms) ||
        groupMatches(l10n.novelSectionPage, _kNovelSecPageTerms) ||
        groupMatches(l10n.novelSectionTts, _kNovelSecTtsTerms) ||
        groupMatches(l10n.novelSectionMisc, _kNovelSecMiscTerms) ||
        groupMatches(l10n.novelSectionAi, _kNovelSecAiTerms);
    return Material(
      color: Colors.transparent,
      child: Column(
        children: <Widget>[
          // 搜索行：搜索框 + 底部工具栏配置入口并置，为内容区省出标题行空间。
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceLg,
              vertical: AppTokens.spaceSm,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: searchController,
                    onChanged: onSearchChanged,
                    decoration: InputDecoration(
                      hintText: l10n.novelSettingsSearch,
                      prefixIcon: const Icon(Icons.search_rounded),
                      isDense: true,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                if (onConfigureToolbar != null) ...<Widget>[
                  const SizedBox(width: AppTokens.spaceSm),
                  IconButton(
                    icon: const Icon(Icons.view_module_rounded),
                    tooltip: l10n.configureBottomToolbar,
                    onPressed: onConfigureToolbar,
                  ),
                ],
              ],
            ),
          ),
          // 可滚动内容
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppTokens.spaceLg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // 常用置顶：最常改的快捷项（搜索时隐藏，避免与过滤重叠）
                  if (searchController.text.trim().isEmpty)
                    _buildCommonCard(context, l10n),

                  // ── 颜色与背景组 ──
                  _buildSettingsGroup(
                    context,
                    l10n.novelSectionColor,
                    searchQuery: searchController.text,
                    leading: Icons.palette_rounded,
                    searchTerms: _kNovelSecColorTerms,
                    children: <Widget>[
                      // 亮度（从「翻页与交互」组上移，最常调）
                      _SliderRow(
                        label: l10n.novelBrightness,
                        value: brightness,
                        min: 0.0,
                        max: 1.0,
                        divisions: 20,
                        onChanged: onBrightnessChanged,
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      // 夜间模式跟随策略（项 6）：三选一
                      _buildThemeFollowSelector(
                          context, l10n, prefs, onChanged),
                      const SizedBox(height: AppTokens.spaceMd),
                      // 背景预设
                      Text(l10n.readerBackground,
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          for (int i = 0;
                              i < ReaderTokens.bgPresets.length;
                              i++)
                            ChoiceChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: _swatchColor(
                                          ReaderTokens.bgPresets[i]),
                                      border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline
                                            .withValues(alpha: 0.6),
                                      ),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(_bgLabel(i, l10n)),
                                ],
                              ),
                              selected: prefs.bgPresetIndex == i &&
                                  prefs.customBgColor == null,
                              onSelected: (_) => onChanged(prefs.copyWith(
                                bgPresetIndex: i,
                                customBgColor: null,
                              )),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      // 自定义背景色
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.customBgColor),
                        trailing: GestureDetector(
                          onTap: () async {
                            // 修复：确认式取色（OK/Cancel），仅用户点确定时写回，避免非手势 pop 崩溃。
                            Color? pickedColor;
                            final Color initial = prefs.customBgColor != null
                                ? Color(prefs.customBgColor!)
                                : ReaderTokens.bgPresets[prefs.bgPresetIndex
                                    .clamp(
                                        0, ReaderTokens.bgPresets.length - 1)];
                            final color = await showDialog<Color>(
                              context: context,
                              builder: (ctx) => StatefulBuilder(
                                builder: (ctx2, setDialogState) =>
                                    AppAlertDialog(
                                  title: Text(l10n.customBgColor),
                                  content: SingleChildScrollView(
                                    child: ColorPicker(
                                      pickerColor: pickedColor ?? initial,
                                      onColorChanged: (c) =>
                                          setDialogState(() => pickedColor = c),
                                    ),
                                  ),
                                  actions: <Widget>[
                                    TextButton(
                                      onPressed: () => Navigator.of(ctx).pop(),
                                      child: Text(
                                        MaterialLocalizations.of(ctx)
                                            .cancelButtonLabel,
                                      ),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.of(ctx)
                                          .pop(pickedColor ?? initial),
                                      child: Text(
                                        MaterialLocalizations.of(ctx)
                                            .okButtonLabel,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                            if (color != null) {
                              onChanged(prefs.copyWith(
                                  customBgColor: color.toARGB32()));
                            }
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: _swatchColor(prefs.customBgColor != null
                                  ? Color(prefs.customBgColor!)
                                  : ReaderTokens.bgPresets[prefs.bgPresetIndex
                                      .clamp(0,
                                          ReaderTokens.bgPresets.length - 1)]),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                              borderRadius:
                                  BorderRadius.circular(AppTokens.radiusSm),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      // 正文颜色（自定义；可清除为跟随背景）
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.novelTextColor),
                        subtitle: prefs.customTextColor == null
                            ? Text(l10n.novelTextColorFollowBg)
                            : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (prefs.customTextColor != null)
                              IconButton(
                                icon: const Icon(Icons.backspace_rounded),
                                tooltip: l10n.novelTextColorFollowBg,
                                onPressed: () => onChanged(
                                    prefs.copyWith(customTextColor: null)),
                              ),
                            GestureDetector(
                              onTap: () async {
                                // 修复：确认式取色（OK/Cancel），仅用户点确定时写回，避免非手势 pop 崩溃。
                                Color? pickedColor;
                                final Color initial =
                                    prefs.customTextColor != null
                                        ? Color(prefs.customTextColor!)
                                        : const Color(0xFF1A1A1A);
                                final color = await showDialog<Color>(
                                  context: context,
                                  builder: (ctx) => StatefulBuilder(
                                    builder: (ctx2, setDialogState) =>
                                        AppAlertDialog(
                                      title: Text(l10n.novelTextColor),
                                      content: SingleChildScrollView(
                                        child: ColorPicker(
                                          pickerColor: pickedColor ?? initial,
                                          onColorChanged: (c) => setDialogState(
                                              () => pickedColor = c),
                                        ),
                                      ),
                                      actions: <Widget>[
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(),
                                          child: Text(
                                            MaterialLocalizations.of(ctx)
                                                .cancelButtonLabel,
                                          ),
                                        ),
                                        FilledButton(
                                          onPressed: () => Navigator.of(ctx)
                                              .pop(pickedColor ?? initial),
                                          child: Text(
                                            MaterialLocalizations.of(ctx)
                                                .okButtonLabel,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                                if (color != null) {
                                  onChanged(prefs.copyWith(
                                      customTextColor: color.toARGB32()));
                                }
                              },
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: prefs.customTextColor != null
                                      ? Color(prefs.customTextColor!)
                                      : const Color(0xFF1A1A1A),
                                  border: Border.all(
                                    color:
                                        Theme.of(context).colorScheme.outline,
                                  ),
                                  borderRadius:
                                      BorderRadius.circular(AppTokens.radiusSm),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      // 强调色（从「字体文件」组移入；可清除为默认）
                      _colorTile(
                        context: context,
                        l10n: l10n,
                        title: l10n.novelEmphasisColor,
                        subtitle: prefs.emphasisColor == null
                            ? l10n.novelEmphasisColorAuto
                            : null,
                        current: prefs.emphasisColor,
                        fallback: ReaderTokens.emphasisDefault,
                        onPicked: (c) =>
                            onChanged(prefs.copyWith(emphasisColor: c)),
                        onClear: () =>
                            onChanged(prefs.copyWith(emphasisColor: null)),
                        clearTooltip: l10n.novelEmphasisColorAuto,
                      ),
                    ],
                  ),
                  // ── 文字组 ──
                  _buildSettingsGroup(
                    context,
                    l10n.novelSectionText,
                    initiallyExpanded: true,
                    searchQuery: searchController.text,
                    leading: Icons.text_fields_rounded,
                    searchTerms: _kNovelSecTextTerms,
                    children: <Widget>[
                      _SliderRow(
                        label: l10n.novelFontSize,
                        value: prefs.fontSize,
                        min: 12,
                        max: 32,
                        divisions: 20,
                        unit: 'sp',
                        onChanged: (v) =>
                            onPreview?.call(prefs.copyWith(fontSize: v)),
                        onChangeEnd: (v) =>
                            onChanged(prefs.copyWith(fontSize: v)),
                      ),
                      _SliderRow(
                        label: l10n.novelLineHeight,
                        value: prefs.lineHeight,
                        min: 1.2,
                        max: 3.0,
                        divisions: 18,
                        onChanged: (v) =>
                            onPreview?.call(prefs.copyWith(lineHeight: v)),
                        onChangeEnd: (v) =>
                            onChanged(prefs.copyWith(lineHeight: v)),
                      ),
                      _SliderRow(
                        label: l10n.novelParagraphSpacing,
                        value: prefs.paragraphSpacing,
                        min: 4,
                        max: 48,
                        divisions: 22,
                        unit: 'px',
                        onChanged: (v) => onPreview
                            ?.call(prefs.copyWith(paragraphSpacing: v)),
                        onChangeEnd: (v) =>
                            onChanged(prefs.copyWith(paragraphSpacing: v)),
                      ),
                      _SliderRow(
                        label: l10n.novelMargin,
                        value: prefs.margin,
                        min: 8,
                        max: 64,
                        divisions: 14,
                        unit: 'px',
                        onChanged: (v) =>
                            onPreview?.call(prefs.copyWith(margin: v)),
                        onChangeEnd: (v) =>
                            onChanged(prefs.copyWith(margin: v)),
                      ),
                      _SliderRow(
                        label: l10n.novelLetterSpacing,
                        value: prefs.letterSpacing,
                        min: 0,
                        max: 8,
                        divisions: 16,
                        unit: 'px',
                        onChanged: (v) =>
                            onPreview?.call(prefs.copyWith(letterSpacing: v)),
                        onChangeEnd: (v) =>
                            onChanged(prefs.copyWith(letterSpacing: v)),
                      ),
                    ],
                  ),
                  // ── 字体样式组 ──
                  _buildSettingsGroup(
                    context,
                    l10n.novelSectionFont,
                    searchQuery: searchController.text,
                    leading: Icons.font_download_rounded,
                    searchTerms: _kNovelSecFontTerms,
                    children: <Widget>[
                      // 字体样式（加粗 / 斜体 / 下划线，可共存）
                      Text(l10n.novelFontStyle,
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          FilterChip(
                            label: Text(l10n.fontBold),
                            // 加粗是唯一开关：开启后按下方字重滑块渲染，
                            // 关闭即恢复默认字重，可随时关掉。
                            selected: prefs.fontBold,
                            onSelected: (v) =>
                                onChanged(prefs.copyWith(fontBold: v)),
                          ),
                          FilterChip(
                            label: Text(l10n.fontItalic),
                            selected: prefs.fontItalic,
                            onSelected: (v) =>
                                onChanged(prefs.copyWith(fontItalic: v)),
                          ),
                          FilterChip(
                            label: Text(l10n.fontUnderline),
                            selected: prefs.fontUnderline,
                            onSelected: (v) =>
                                onChanged(prefs.copyWith(fontUnderline: v)),
                          ),
                        ],
                      ),
                      // 加粗字重滑块（100–900）：仅加粗开启时显示并生效。
                      // divisions 取 8 使滑块停在整百档位，与 resolveBodyTextStyle
                      // 的 switch 精确匹配，避免中间值落到 default 的 w900。
                      if (prefs.fontBold) ...<Widget>[
                        const SizedBox(height: AppTokens.spaceSm),
                        _SliderRow(
                          label: l10n.novelFontWeightFine,
                          value: prefs.fontWeightValue.toDouble(),
                          min: 100,
                          max: 900,
                          divisions: 8,
                          unit: '',
                          onChanged: (v) => onPreview?.call(
                              prefs.copyWith(fontWeightValue: v.round())),
                          onChangeEnd: (v) => onChanged(
                              prefs.copyWith(fontWeightValue: v.round())),
                        ),
                      ],
                      // 自定义字体
                      const SizedBox(height: AppTokens.spaceMd),
                      Text(l10n.customFont,
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          ChoiceChip(
                            label: Text(l10n.fontSystem),
                            selected: prefs.fontFamily == null,
                            onSelected: (_) =>
                                onChanged(prefs.copyWith(fontFamily: null)),
                          ),
                          ChoiceChip(
                            label: Text(l10n.fontSerif),
                            selected: prefs.fontFamily == 'serif',
                            onSelected: (_) =>
                                onChanged(prefs.copyWith(fontFamily: 'serif')),
                          ),
                          ChoiceChip(
                            label: Text(l10n.fontMonospace),
                            selected: prefs.fontFamily == 'monospace',
                            onSelected: (_) => onChanged(
                                prefs.copyWith(fontFamily: 'monospace')),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      _fontFileTile(
                        context: context,
                        l10n: l10n,
                        title: false,
                      ),
                    ],
                  ),
                  // ── 排版样式组（与总设置页「排版增强」同步）──
                  _buildSettingsGroup(
                    context,
                    l10n.novelTypographyGroup,
                    searchQuery: searchController.text,
                    leading: Icons.format_align_left_rounded,
                    initiallyExpanded: true,
                    searchTerms: _kNovelSecTypographyTerms,
                    children: <Widget>[
                      // 对齐方式（与总设置同步；仅分页模式两端对齐生效）
                      Text(l10n.novelTextAlignMode,
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          ChoiceChip(
                            label: Text(l10n.novelTextAlignStart),
                            selected:
                                prefs.textAlignMode == NovelTextAlignMode.start,
                            onSelected: (_) => onChanged(prefs.copyWith(
                                textAlignMode: NovelTextAlignMode.start)),
                          ),
                          ChoiceChip(
                            label: Text(l10n.novelTextAlignJustify),
                            selected: prefs.textAlignMode ==
                                NovelTextAlignMode.justify,
                            onSelected: (_) => onChanged(prefs.copyWith(
                                textAlignMode: NovelTextAlignMode.justify)),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      // 中文断行模式
                      Text(l10n.novelLineBreakMode,
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          ChoiceChip(
                            label: Text(l10n.novelLineBreakStandard),
                            selected: prefs.lineBreakMode ==
                                NovelLineBreakMode.standard,
                            onSelected: (_) => onChanged(prefs.copyWith(
                                lineBreakMode: NovelLineBreakMode.standard)),
                          ),
                          ChoiceChip(
                            label: Text(l10n.novelLineBreakCjkStrict),
                            selected: prefs.lineBreakMode ==
                                NovelLineBreakMode.cjkStrict,
                            onSelected: (_) => onChanged(prefs.copyWith(
                                lineBreakMode: NovelLineBreakMode.cjkStrict)),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      // 下划线样式
                      Text(l10n.novelUnderlineStyle,
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          for (final s in NovelUnderlineStyle.values)
                            ChoiceChip(
                              label: Text(switch (s) {
                                NovelUnderlineStyle.solid =>
                                  l10n.novelUnderlineStyleSolid,
                                NovelUnderlineStyle.dashed =>
                                  l10n.novelUnderlineStyleDashed,
                                NovelUnderlineStyle.wavy =>
                                  l10n.novelUnderlineStyleWavy,
                                NovelUnderlineStyle.dotted =>
                                  l10n.novelUnderlineStyleDotted,
                              }),
                              selected: prefs.underlineStyle == s,
                              onSelected: (_) =>
                                  onChanged(prefs.copyWith(underlineStyle: s)),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      // 滚动插图样式
                      Text(l10n.novelScrollImageMode,
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          ChoiceChip(
                            label: Text(l10n.novelScrollImageModeBanner),
                            selected: prefs.scrollImageMode ==
                                NovelScrollImageMode.banner,
                            onSelected: (_) => onChanged(prefs.copyWith(
                                scrollImageMode: NovelScrollImageMode.banner)),
                          ),
                          ChoiceChip(
                            label: Text(l10n.novelScrollImageModeCard),
                            selected: prefs.scrollImageMode ==
                                NovelScrollImageMode.card,
                            onSelected: (_) => onChanged(prefs.copyWith(
                                scrollImageMode: NovelScrollImageMode.card)),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      // 插图对齐（仅 card 模式生效）
                      Text(l10n.novelScrollImageAlign,
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          ChoiceChip(
                            label: Text(l10n.novelScrollImageAlignLeft),
                            selected: prefs.scrollImageAlign ==
                                NovelScrollImageAlign.left,
                            onSelected: (_) => onChanged(prefs.copyWith(
                                scrollImageAlign: NovelScrollImageAlign.left)),
                          ),
                          ChoiceChip(
                            label: Text(l10n.novelScrollImageAlignCenter),
                            selected: prefs.scrollImageAlign ==
                                NovelScrollImageAlign.center,
                            onSelected: (_) => onChanged(prefs.copyWith(
                                scrollImageAlign:
                                    NovelScrollImageAlign.center)),
                          ),
                          ChoiceChip(
                            label: Text(l10n.novelScrollImageAlignRight),
                            selected: prefs.scrollImageAlign ==
                                NovelScrollImageAlign.right,
                            onSelected: (_) => onChanged(prefs.copyWith(
                                scrollImageAlign: NovelScrollImageAlign.right)),
                          ),
                        ],
                      ),
                      // 章末自动接续：滚动模式滚到章末无缝拼接下一章正文。
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.novelScrollAutoNextChapter),
                        subtitle: Text(l10n.novelScrollAutoNextChapterHint),
                        value: prefs.scrollAutoNextChapter,
                        onChanged: (v) {
                          v == true
                              ? AppHaptics.toggleOn()
                              : AppHaptics.toggleOff();
                          onChanged(prefs.copyWith(scrollAutoNextChapter: v));
                        },
                      ),
                    ],
                  ),
                  // ── 章节标题组 ──
                  _buildSettingsGroup(
                    context,
                    l10n.novelSectionTitle,
                    searchQuery: searchController.text,
                    leading: Icons.title_rounded,
                    searchTerms: _kNovelSecTitleTerms,
                    children: <Widget>[
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.novelShowChapterTitle),
                        value: prefs.showChapterTitleInBody,
                        onChanged: (v) {
                          v == true
                              ? AppHaptics.toggleOn()
                              : AppHaptics.toggleOff();
                          onChanged(prefs.copyWith(showChapterTitleInBody: v));
                        },
                      ),
                      if (prefs.showChapterTitleInBody) ...<Widget>[
                        Text(
                          l10n.novelTitlePosition,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: AppTokens.spaceXs),
                        Wrap(
                          spacing: AppTokens.spaceSm,
                          runSpacing: AppTokens.spaceSm,
                          children: <Widget>[
                            for (final a in NovelTitleAlign.values)
                              ChoiceChip(
                                label: Text(_titleAlignLabel(a, l10n)),
                                selected: prefs.titleAlign == a,
                                onSelected: (_) =>
                                    onChanged(prefs.copyWith(titleAlign: a)),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppTokens.spaceMd),
                        _SliderRow(
                          label: l10n.novelTitleFontScale,
                          value: prefs.titleFontScale,
                          min: 1.0,
                          max: 2.5,
                          divisions: 15,
                          onChanged: (v) => onPreview
                              ?.call(prefs.copyWith(titleFontScale: v)),
                          onChangeEnd: (v) =>
                              onChanged(prefs.copyWith(titleFontScale: v)),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.novelTitleBold),
                          value: prefs.titleBold,
                          onChanged: (v) {
                            v == true
                                ? AppHaptics.toggleOn()
                                : AppHaptics.toggleOff();
                            onChanged(prefs.copyWith(titleBold: v));
                          },
                        ),
                        _fontFileTile(
                          context: context,
                          l10n: l10n,
                          title: true,
                        ),
                        const Divider(height: 1),
                        const SizedBox(height: AppTokens.spaceSm),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.novelTitleSegmentMode),
                          value: prefs.titleSegmentMode,
                          onChanged: (v) {
                            v == true
                                ? AppHaptics.toggleOn()
                                : AppHaptics.toggleOff();
                            onChanged(prefs.copyWith(titleSegmentMode: v));
                          },
                        ),
                        if (prefs.titleSegmentMode) ...<Widget>[
                          _SliderRow(
                            label: l10n.novelTitleSubScale,
                            value: prefs.titleSubScale,
                            min: 0.4,
                            max: 1.5,
                            divisions: 22,
                            onChanged: (v) => onPreview
                                ?.call(prefs.copyWith(titleSubScale: v)),
                            onChangeEnd: (v) =>
                                onChanged(prefs.copyWith(titleSubScale: v)),
                          ),
                          _SliderRow(
                            label: l10n.novelTitleSegmentSpacing,
                            value: prefs.titleSegmentSpacing,
                            min: 0,
                            max: 32,
                            divisions: 32,
                            unit: 'px',
                            onChanged: (v) => onPreview
                                ?.call(prefs.copyWith(titleSegmentSpacing: v)),
                            onChangeEnd: (v) => onChanged(
                                prefs.copyWith(titleSegmentSpacing: v)),
                          ),
                          _SliderRow(
                            label: l10n.novelTitleSubLineSpacing,
                            value: prefs.titleSubLineSpacing,
                            min: 1.0,
                            max: 2.5,
                            divisions: 30,
                            onChanged: (v) => onPreview
                                ?.call(prefs.copyWith(titleSubLineSpacing: v)),
                            onChangeEnd: (v) => onChanged(
                                prefs.copyWith(titleSubLineSpacing: v)),
                          ),
                          _SliderRow(
                            label: l10n.novelTitleTopMargin,
                            value: prefs.titleTopMargin,
                            min: 0,
                            max: 48,
                            divisions: 48,
                            unit: 'px',
                            onChanged: (v) => onPreview
                                ?.call(prefs.copyWith(titleTopMargin: v)),
                            onChangeEnd: (v) =>
                                onChanged(prefs.copyWith(titleTopMargin: v)),
                          ),
                          _SliderRow(
                            label: l10n.novelTitleBottomMargin,
                            value: prefs.titleBottomMargin,
                            min: 0,
                            max: 48,
                            divisions: 48,
                            unit: 'px',
                            onChanged: (v) => onPreview
                                ?.call(prefs.copyWith(titleBottomMargin: v)),
                            onChangeEnd: (v) =>
                                onChanged(prefs.copyWith(titleBottomMargin: v)),
                          ),
                        ],
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.novelTitleColor),
                          subtitle: prefs.titleColor == null
                              ? Text(l10n.novelTitleColorAuto)
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              if (prefs.titleColor != null)
                                IconButton(
                                  icon: const Icon(Icons.backspace_rounded),
                                  tooltip: l10n.novelTitleColorAuto,
                                  onPressed: () => onChanged(
                                      prefs.copyWith(titleColor: null)),
                                ),
                              GestureDetector(
                                onTap: () async {
                                  // 修复：确认式取色（OK/Cancel），仅用户点确定时写回，避免非手势 pop 崩溃。
                                  Color? pickedColor;
                                  final Color initial = prefs.titleColor != null
                                      ? Color(prefs.titleColor!)
                                      : ReaderTokens.emphasisDefault;
                                  final color = await showDialog<Color>(
                                    context: context,
                                    builder: (ctx) => StatefulBuilder(
                                      builder: (ctx2, setDialogState) =>
                                          AppAlertDialog(
                                        title: Text(l10n.novelTitleColor),
                                        content: SingleChildScrollView(
                                          child: ColorPicker(
                                            pickerColor: pickedColor ?? initial,
                                            onColorChanged: (c) =>
                                                setDialogState(
                                                    () => pickedColor = c),
                                          ),
                                        ),
                                        actions: <Widget>[
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(ctx).pop(),
                                            child: Text(
                                              MaterialLocalizations.of(ctx)
                                                  .cancelButtonLabel,
                                            ),
                                          ),
                                          FilledButton(
                                            onPressed: () => Navigator.of(ctx)
                                                .pop(pickedColor ?? initial),
                                            child: Text(
                                              MaterialLocalizations.of(ctx)
                                                  .okButtonLabel,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                  if (color != null) {
                                    onChanged(prefs.copyWith(
                                        titleColor: color.toARGB32()));
                                  }
                                },
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: prefs.titleColor != null
                                        ? Color(prefs.titleColor!)
                                        : ReaderTokens.emphasisDefault,
                                    border: Border.all(
                                      color:
                                          Theme.of(context).colorScheme.outline,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                        AppTokens.radiusSm),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  // ── 页眉页脚组 ──
                  _buildSettingsGroup(
                    context,
                    l10n.novelSectionHeaderFooter,
                    searchQuery: searchController.text,
                    leading: Icons.view_headline_rounded,
                    searchTerms: _kNovelSecHeaderFooterTerms,
                    children: <Widget>[
                      _buildHfSlotPicker(
                        context: context,
                        l10n: l10n,
                        l10n.novelHeaderLeft,
                        prefs.headerLeft,
                        (v) => onChanged(prefs.copyWith(headerLeft: v)),
                      ),
                      _buildHfSlotPicker(
                        context: context,
                        l10n: l10n,
                        l10n.novelHeaderCenter,
                        prefs.headerCenter,
                        (v) => onChanged(prefs.copyWith(headerCenter: v)),
                      ),
                      _buildHfSlotPicker(
                        context: context,
                        l10n: l10n,
                        l10n.novelHeaderRight,
                        prefs.headerRight,
                        (v) => onChanged(prefs.copyWith(headerRight: v)),
                      ),
                      const Divider(height: 1),
                      const SizedBox(height: AppTokens.spaceSm),
                      _buildHfSlotPicker(
                        context: context,
                        l10n: l10n,
                        l10n.novelFooterLeft,
                        prefs.footerLeft,
                        (v) => onChanged(prefs.copyWith(footerLeft: v)),
                      ),
                      _buildHfSlotPicker(
                        context: context,
                        l10n: l10n,
                        l10n.novelFooterCenter,
                        prefs.footerCenter,
                        (v) => onChanged(prefs.copyWith(footerCenter: v)),
                      ),
                      _buildHfSlotPicker(
                        context: context,
                        l10n: l10n,
                        l10n.novelFooterRight,
                        prefs.footerRight,
                        (v) => onChanged(prefs.copyWith(footerRight: v)),
                      ),
                      const Divider(height: 1),
                      const SizedBox(height: AppTokens.spaceSm),
                      _colorTile(
                        context: context,
                        l10n: l10n,
                        title: l10n.novelHeaderFooterColor,
                        subtitle: prefs.headerFooterColor == null
                            ? l10n.novelTextColorFollowBg
                            : null,
                        current: prefs.headerFooterColor,
                        fallback: const Color(0xFF1A1A1A),
                        onPicked: (c) =>
                            onChanged(prefs.copyWith(headerFooterColor: c)),
                        onClear: () =>
                            onChanged(prefs.copyWith(headerFooterColor: null)),
                        clearTooltip: l10n.novelTextColorFollowBg,
                      ),
                      _SliderRow(
                        label: l10n.novelHeaderFooterMargin,
                        value: prefs.headerFooterMargin,
                        min: 0,
                        max: 48,
                        divisions: 48,
                        unit: 'px',
                        onChanged: (v) => onPreview
                            ?.call(prefs.copyWith(headerFooterMargin: v)),
                        onChangeEnd: (v) =>
                            onChanged(prefs.copyWith(headerFooterMargin: v)),
                      ),
                    ],
                  ),
                  // ── 阴影与下划线组 ──
                  _buildSettingsGroup(
                    context,
                    l10n.novelSectionShadowUnderline,
                    searchQuery: searchController.text,
                    leading: Icons.format_color_text_rounded,
                    searchTerms: _kNovelSecShadowUnderlineTerms,
                    children: <Widget>[
                      // 文字阴影开关（从「颜色与背景」组移入）
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.novelTextShadow),
                        value: prefs.shadow,
                        onChanged: (v) {
                          v == true
                              ? AppHaptics.toggleOn()
                              : AppHaptics.toggleOff();
                          onChanged(prefs.copyWith(shadow: v));
                        },
                      ),
                      // 阴影颜色（仅在开启阴影时可调；可清除为跟随正文色）
                      if (prefs.shadow)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.novelShadowColor),
                          subtitle: prefs.shadowColor == null
                              ? Text(l10n.novelShadowColorAuto)
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              if (prefs.shadowColor != null)
                                IconButton(
                                  icon: const Icon(Icons.backspace_rounded),
                                  tooltip: l10n.novelShadowColorAuto,
                                  onPressed: () => onChanged(
                                      prefs.copyWith(shadowColor: null)),
                                ),
                              GestureDetector(
                                onTap: () async {
                                  // 修复：确认式取色（OK/Cancel），仅用户点确定时写回，避免非手势 pop 崩溃。
                                  Color? pickedColor;
                                  final Color initial =
                                      prefs.shadowColor != null
                                          ? Color(prefs.shadowColor!)
                                          : const Color(0x4D000000);
                                  final color = await showDialog<Color>(
                                    context: context,
                                    builder: (ctx) => StatefulBuilder(
                                      builder: (ctx2, setDialogState) =>
                                          AppAlertDialog(
                                        title: Text(l10n.novelShadowColor),
                                        content: SingleChildScrollView(
                                          child: ColorPicker(
                                            pickerColor: pickedColor ?? initial,
                                            onColorChanged: (c) =>
                                                setDialogState(
                                                    () => pickedColor = c),
                                          ),
                                        ),
                                        actions: <Widget>[
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(ctx).pop(),
                                            child: Text(
                                              MaterialLocalizations.of(ctx)
                                                  .cancelButtonLabel,
                                            ),
                                          ),
                                          FilledButton(
                                            onPressed: () => Navigator.of(ctx)
                                                .pop(pickedColor ?? initial),
                                            child: Text(
                                              MaterialLocalizations.of(ctx)
                                                  .okButtonLabel,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                  if (color != null) {
                                    onChanged(prefs.copyWith(
                                        shadowColor: color.toARGB32()));
                                  }
                                },
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: prefs.shadowColor != null
                                        ? Color(prefs.shadowColor!)
                                        : const Color(0x4D000000),
                                    border: Border.all(
                                      color:
                                          Theme.of(context).colorScheme.outline,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                        AppTokens.radiusSm),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (prefs.shadow) ...<Widget>[
                        _SliderRow(
                          label: l10n.novelShadowBlur,
                          value: prefs.shadowBlur,
                          min: 0,
                          max: 8,
                          divisions: 32,
                          unit: 'px',
                          onChanged: (v) =>
                              onPreview?.call(prefs.copyWith(shadowBlur: v)),
                          onChangeEnd: (v) =>
                              onChanged(prefs.copyWith(shadowBlur: v)),
                        ),
                        _SliderRow(
                          label: l10n.novelShadowOffsetX,
                          value: prefs.shadowOffsetX,
                          min: -8,
                          max: 8,
                          divisions: 32,
                          unit: 'px',
                          onChanged: (v) =>
                              onPreview?.call(prefs.copyWith(shadowOffsetX: v)),
                          onChangeEnd: (v) =>
                              onChanged(prefs.copyWith(shadowOffsetX: v)),
                        ),
                        _SliderRow(
                          label: l10n.novelShadowOffsetY,
                          value: prefs.shadowOffsetY,
                          min: -8,
                          max: 8,
                          divisions: 32,
                          unit: 'px',
                          onChanged: (v) =>
                              onPreview?.call(prefs.copyWith(shadowOffsetY: v)),
                          onChangeEnd: (v) =>
                              onChanged(prefs.copyWith(shadowOffsetY: v)),
                        ),
                      ],
                      const Divider(height: 1),
                      const SizedBox(height: AppTokens.spaceSm),
                      // fontUnderline 开关已移至「字体样式」组，
                      // 这里保留下划线颜色 / 线宽 / 段长 / 间隙；
                      // 下划线样式（solid/dashed/wavy/dotted）已独立到「排版样式」组。
                      if (prefs.fontUnderline) ...<Widget>[
                        _colorTile(
                          context: context,
                          l10n: l10n,
                          title: l10n.novelUnderlineColor,
                          subtitle: prefs.underlineColor == null
                              ? l10n.novelUnderlineColorAuto
                              : null,
                          current: prefs.underlineColor,
                          fallback: const Color(0xFF1A1A1A),
                          onPicked: (c) =>
                              onChanged(prefs.copyWith(underlineColor: c)),
                          onClear: () =>
                              onChanged(prefs.copyWith(underlineColor: null)),
                          clearTooltip: l10n.novelUnderlineColorAuto,
                        ),
                        _SliderRow(
                          label: l10n.novelUnderlineThickness,
                          value: prefs.underlineThickness,
                          min: 0.5,
                          max: 6,
                          divisions: 22,
                          unit: 'px',
                          onChanged: (v) => onPreview
                              ?.call(prefs.copyWith(underlineThickness: v)),
                          onChangeEnd: (v) =>
                              onChanged(prefs.copyWith(underlineThickness: v)),
                        ),
                        if (prefs.underlineStyle ==
                            NovelUnderlineStyle.dashed) ...<Widget>[
                          _SliderRow(
                            label: l10n.novelUnderlineDashLength,
                            value: prefs.underlineDashLength,
                            min: 1,
                            max: 16,
                            divisions: 30,
                            unit: 'px',
                            onChanged: (v) => onPreview
                                ?.call(prefs.copyWith(underlineDashLength: v)),
                            onChangeEnd: (v) => onChanged(
                                prefs.copyWith(underlineDashLength: v)),
                          ),
                          _SliderRow(
                            label: l10n.novelUnderlineDashGap,
                            value: prefs.underlineDashGap,
                            min: 0,
                            max: 16,
                            divisions: 32,
                            unit: 'px',
                            onChanged: (v) => onPreview
                                ?.call(prefs.copyWith(underlineDashGap: v)),
                            onChangeEnd: (v) =>
                                onChanged(prefs.copyWith(underlineDashGap: v)),
                          ),
                        ],
                      ],
                    ],
                  ),
                  // ── 翻页与交互组 ──
                  _buildSettingsGroup(
                    context,
                    l10n.novelSectionPage,
                    searchQuery: searchController.text,
                    leading: Icons.gesture_rounded,
                    searchTerms: _kNovelSecPageTerms,
                    children: <Widget>[
                      // 翻页动画
                      Text(l10n.novelPageAnimation,
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          for (final anim in NovelPageAnimation.values)
                            ChoiceChip(
                              label: Text(_animLabel(anim, l10n)),
                              selected: prefs.pageAnimation == anim,
                              onSelected: (_) => onChanged(
                                  prefs.copyWith(pageAnimation: anim)),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      // 点击分区布局（FR-4.2，5 布局）
                      Row(
                        children: <Widget>[
                          Text(l10n.readerTapZone,
                              style: Theme.of(context).textTheme.bodyMedium),
                          const Spacer(),
                          TextButton(
                            onPressed: onShowTapZonePreview,
                            child: Text(l10n.tapZonePreview),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          for (final layout in ReaderTapZoneLayout.values)
                            ChoiceChip(
                              label: Text(_tapLayoutLabel(l10n, layout)),
                              selected: prefs.tapZoneLayout == layout,
                              onSelected: (_) => onChanged(
                                  prefs.copyWith(tapZoneLayout: layout)),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      // 点击分区方向反转（FR-4.2）
                      Text(l10n.readerTapInvert,
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          for (final invert in TapZoneInvert.values)
                            ChoiceChip(
                              label: Text(_tapInvertLabel(l10n, invert)),
                              selected: prefs.tapZoneInvert == invert,
                              onSelected: (_) => onChanged(
                                  prefs.copyWith(tapZoneInvert: invert)),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      // 双页模式：翻页模式宽屏左右并排两页（与总设置同步）。
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.novelTwoPageMode),
                        subtitle: Text(l10n.novelTwoPageModeDesc),
                        value: prefs.twoPageMode,
                        onChanged: (v) {
                          v == true
                              ? AppHaptics.toggleOn()
                              : AppHaptics.toggleOff();
                          onChanged(prefs.copyWith(twoPageMode: v));
                        },
                      ),
                      // 自动翻页间隔
                      Text(l10n.autoPageInterval,
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          for (final v in const <int>[0, 3, 5, 10, 15])
                            ChoiceChip(
                              label: Text(v == 0 ? l10n.autoPageOff : '${v}s'),
                              selected: prefs.autoPageInterval == v,
                              onSelected: (_) => onChanged(
                                  prefs.copyWith(autoPageInterval: v)),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      // 平滑自动翻页：按像素/过渡进度连续推进整页。
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.autoPageSmooth),
                        value: prefs.autoPageSmooth,
                        onChanged: (v) {
                          v == true
                              ? AppHaptics.toggleOn()
                              : AppHaptics.toggleOff();
                          onChanged(prefs.copyWith(autoPageSmooth: v));
                        },
                      ),
                      // 鼠标滚轮翻页方向反转（仅翻页模式生效；滚动模式由底层滚动接管）
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.novelWheelInverted),
                        value: prefs.scrollWheelInverted,
                        onChanged: (v) {
                          v == true
                              ? AppHaptics.toggleOn()
                              : AppHaptics.toggleOff();
                          onChanged(prefs.copyWith(scrollWheelInverted: v));
                        },
                      ),
                      // 音量键翻页（Android / 鸿蒙手机有原生音量键拦截通道）。
                      if (PlatformService.instance.isAndroid ||
                          PlatformService.instance.isOHOSPhone)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.readerVolumeKeyPageTurn),
                          value: prefs.volumeKeyPageTurn,
                          onChanged: (v) {
                            v == true
                                ? AppHaptics.toggleOn()
                                : AppHaptics.toggleOff();
                            onChanged(prefs.copyWith(volumeKeyPageTurn: v));
                          },
                        ),
                    ],
                  ),
                  // ── 朗读组 ──
                  _buildSettingsGroup(
                    context,
                    l10n.novelSectionTts,
                    searchQuery: searchController.text,
                    leading: Icons.record_voice_over_rounded,
                    searchTerms: _kNovelSecTtsTerms,
                    children: <Widget>[
                      ListenableBuilder(
                        listenable: tts,
                        builder: (BuildContext ctx, Widget? _) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            _SliderRow(
                              label: l10n.ttsRate,
                              value: tts.rate,
                              min: 0.5,
                              max: 2.0,
                              divisions: 30,
                              onChanged: (v) {
                                tts.setRate(v);
                                onPreview
                                    ?.call(prefs.copyWith(ttsSpeechRate: v));
                              },
                              onChangeEnd: (v) =>
                                  onChanged(prefs.copyWith(ttsSpeechRate: v)),
                            ),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.timer_rounded),
                              title: Text(l10n.ttsSleepTimer),
                              subtitle: tts.sleepRemaining != null
                                  ? Text(l10n.ttsSleepRemaining(
                                      tts.sleepRemaining!.inMinutes,
                                      tts.sleepRemaining!.inSeconds % 60))
                                  : null,
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => _pickSleepTimer(
                                context: context,
                                l10n: l10n,
                              ),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(l10n.novelTtsBackground),
                              value: prefs.ttsBackground,
                              onChanged: (v) {
                                v == true
                                    ? AppHaptics.toggleOn()
                                    : AppHaptics.toggleOff();
                                onChanged(prefs.copyWith(ttsBackground: v));
                              },
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(l10n.ttsAutoNext),
                              subtitle: Text(l10n.ttsAutoNextDesc),
                              value: prefs.ttsAutoNext,
                              onChanged: (v) {
                                v == true
                                    ? AppHaptics.toggleOn()
                                    : AppHaptics.toggleOff();
                                onChanged(prefs.copyWith(ttsAutoNext: v));
                              },
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(l10n.ttsRememberPosition),
                              subtitle: Text(l10n.ttsRememberPositionDesc),
                              value: prefs.ttsRememberPosition,
                              onChanged: (v) {
                                v == true
                                    ? AppHaptics.toggleOn()
                                    : AppHaptics.toggleOff();
                                onChanged(prefs
                                    .copyWith(ttsRememberPosition: v));
                              },
                            ),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading:
                                  const Icon(Icons.theater_comedy_rounded),
                              title: Text(l10n.ttsCastTitle),
                              subtitle: Text(l10n.ttsCastSubtitle),
                              trailing:
                                  const Icon(Icons.chevron_right_rounded),
                              onTap: onOpenTtsCast,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // ── 高级组 ──
                  _buildSettingsGroup(
                    context,
                    l10n.novelSectionMisc,
                    searchQuery: searchController.text,
                    leading: Icons.tune_rounded,
                    searchTerms: _kNovelSecMiscTerms,
                    children: <Widget>[
                      // 繁简转换
                      Text(l10n.chineseConverter,
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          ChoiceChip(
                            label: Text(l10n.noConvert),
                            selected: prefs.chineseConvert == 'none',
                            onSelected: (_) => onChanged(
                                prefs.copyWith(chineseConvert: 'none')),
                          ),
                          ChoiceChip(
                            label: Text(l10n.traditionalToSimplified),
                            selected: prefs.chineseConvert ==
                                'traditionalToSimplified',
                            onSelected: (_) => onChanged(prefs.copyWith(
                                chineseConvert: 'traditionalToSimplified')),
                          ),
                          ChoiceChip(
                            label: Text(l10n.simplifiedToTraditional),
                            selected: prefs.chineseConvert ==
                                'simplifiedToTraditional',
                            onSelected: (_) => onChanged(prefs.copyWith(
                                chineseConvert: 'simplifiedToTraditional')),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      const Divider(height: 1),
                      const SizedBox(height: AppTokens.spaceMd),
                      // 正文净化（全局替换规则，本书可单独开关）
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.cleaning_services_rounded),
                        title: Text(l10n.novelPurgeTitle),
                        subtitle: Text(l10n.novelPurgeDesc),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => NovelReplaceRuleScreen(
                                bookId: novelId,
                                bookName: novelName,
                                sourceId: sourceId,
                                sourceName: sourceName,
                              ),
                            ),
                          );
                          onPurgeChanged?.call();
                        },
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      // 阅读中预下载：开关/阈值/数量配置弹窗。
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.download_for_offline_rounded),
                        title: Text(l10n.novelSectionPreDownload),
                        subtitle: Text(l10n.preDownloadEnabled),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _showPreDownloadDialog(context, l10n),
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      // 缓存本书到本地（离线阅读）
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.download_rounded),
                        title: Text(l10n.novelCacheBook),
                        onTap: onCache,
                      ),
                      // 恢复本书默认设置（清除按书覆盖，回到全局默认）
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.restart_alt_rounded),
                        title: Text(l10n.novelResetBookPrefs),
                        onTap: onResetBook,
                      ),
                    ],
                  ),
                  // ── AI 功能组（章节速览 / 翻译 / AI 配图入口，可搜索）──
                  _buildSettingsGroup(
                    context,
                    l10n.novelSectionAi,
                    searchQuery: searchController.text,
                    leading: Icons.auto_awesome_rounded,
                    searchTerms: _kNovelSecAiTerms,
                    children: <Widget>[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.insights_rounded),
                        title: Text(l10n.novelAiOpenSummary),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: onOpenSummary,
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.translate_rounded),
                        title: Text(l10n.novelAiOpenTranslation),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: onTranslate,
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.auto_awesome_rounded),
                        title: Text(l10n.novelAiIllustrate),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: onGenerateIllustration,
                      ),
                    ],
                  ),
                  if (searchController.text.trim().isNotEmpty &&
                      !hasSearchMatch)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: AppTokens.spaceLg),
                      child: Center(
                        child: Column(
                          children: <Widget>[
                            Icon(Icons.search_off_rounded,
                                size: 40, color: Theme.of(context).hintColor),
                            const SizedBox(height: AppTokens.spaceSm),
                            Text(
                              l10n.novelSettingsNoResult,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 预下载配置弹窗（开关 / 触发阈值 / 章节数），保存后通知阅读器。
  Future<void> _showPreDownloadDialog(
      BuildContext context, AppLocalizations l10n) async {
    final NovelPreDownloadPreferences initial =
        await NovelPreDownloadPreferences.load();
    if (!context.mounted) return;
    NovelPreDownloadPreferences? draft;
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx2, StateSetter setDialogState) {
          draft ??= initial;
          final NovelPreDownloadPreferences d = draft!;
          return AppAlertDialog(
            title: Text(l10n.novelSectionPreDownload),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.preDownloadEnabled),
                    value: d.enabled,
                    onChanged: (v) {
                      v == true
                          ? AppHaptics.toggleOn()
                          : AppHaptics.toggleOff();
                      setDialogState(() => draft = draft!.copyWith(enabled: v));
                    },
                  ),
                  if (d.enabled) ...<Widget>[
                    const SizedBox(height: AppTokens.spaceSm),
                    _SliderRow(
                      label: l10n.preDownloadThreshold,
                      value: d.thresholdPercent.toDouble(),
                      min: 50,
                      max: 99,
                      divisions: 49,
                      onChanged: (v) => setDialogState(() =>
                          draft = draft!.copyWith(thresholdPercent: v.round())),
                    ),
                    _SliderRow(
                      label: l10n.preDownloadCount,
                      value: d.count.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      onChanged: (v) => setDialogState(
                          () => draft = draft!.copyWith(count: v.round())),
                    ),
                  ],
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  NovelPreDownloadPreferences.save(draft!);
                  onPreDownloadChanged?.call();
                },
                child: Text(l10n.ok),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 常用置顶卡片：字号 / 亮度 / 背景 / 夜间 / 翻页动画 快捷入口。
  Widget _buildCommonCard(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceMd),
      child: Material(
        color: AppTheme.cardContainer(theme.colorScheme),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.star_rounded,
                      size: 22, color: theme.colorScheme.primary),
                  const SizedBox(width: AppTokens.spaceSm),
                  Text(
                    l10n.novelSettingsCommon,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.spaceSm),
              _SliderRow(
                label: l10n.novelFontSize,
                value: prefs.fontSize,
                min: 12,
                max: 32,
                divisions: 20,
                unit: 'sp',
                onChanged: (v) => onPreview?.call(prefs.copyWith(fontSize: v)),
                onChangeEnd: (v) => onChanged(prefs.copyWith(fontSize: v)),
              ),
              _SliderRow(
                label: l10n.novelBrightness,
                value: brightness,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                onChanged: onBrightnessChanged,
              ),
              const SizedBox(height: AppTokens.spaceSm),
              Text(l10n.readerBackground, style: theme.textTheme.bodyMedium),
              const SizedBox(height: AppTokens.spaceXs),
              Wrap(
                spacing: AppTokens.spaceSm,
                runSpacing: AppTokens.spaceSm,
                children: <Widget>[
                  for (int i = 0; i < ReaderTokens.bgPresets.length; i++)
                    ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: ReaderTokens.bgPresets[i],
                              border: Border.all(
                                color: theme.colorScheme.outline
                                    .withValues(alpha: 0.6),
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(_bgLabel(i, l10n)),
                        ],
                      ),
                      selected: prefs.bgPresetIndex == i &&
                          prefs.customBgColor == null,
                      onSelected: (_) => onChanged(prefs.copyWith(
                        bgPresetIndex: i,
                        customBgColor: null,
                      )),
                    ),
                ],
              ),
              const SizedBox(height: AppTokens.spaceSm),
              _buildThemeFollowSelector(context, l10n, prefs, onChanged),
              const SizedBox(height: AppTokens.spaceSm),
              Text(l10n.novelPageAnimation, style: theme.textTheme.bodyMedium),
              const SizedBox(height: AppTokens.spaceXs),
              Wrap(
                spacing: AppTokens.spaceSm,
                runSpacing: AppTokens.spaceSm,
                children: <Widget>[
                  for (final anim in NovelPageAnimation.values)
                    ChoiceChip(
                      label: Text(_animLabel(anim, l10n)),
                      selected: prefs.pageAnimation == anim,
                      onSelected: (_) =>
                          onChanged(prefs.copyWith(pageAnimation: anim)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 颜色选择瓦片：点击色块弹出取色器，右侧有「清除（恢复默认）」按钮。
  /// 预览色块：夜间模式下在原始色基础上压暗，与 [NovelReaderPreferences
  /// .resolveBackgroundColor] 的夜间处理保持一致，做到「所见即所得」。
  Color _swatchColor(Color c) {
    if (prefs.themeFollow != NovelThemeFollow.alwaysDark) return c;
    return Color.lerp(c, Colors.black, ReaderTokens.nightDarkenFactor) ?? c;
  }

  /// 夜间模式跟随策略三选一（项 6）：跟随应用 / 始终夜间 / 始终日间。
  Widget _buildThemeFollowSelector(
    BuildContext context,
    AppLocalizations l10n,
    NovelReaderPreferences prefs,
    void Function(NovelReaderPreferences) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(l10n.nightMode, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: AppTokens.spaceXs),
        Wrap(
          spacing: AppTokens.spaceSm,
          runSpacing: AppTokens.spaceSm,
          children: <Widget>[
            for (final f in NovelThemeFollow.values)
              ChoiceChip(
                label: Text(_themeFollowLabel(f, l10n)),
                selected: prefs.themeFollow == f,
                onSelected: (_) => onChanged(prefs.copyWith(themeFollow: f)),
              ),
          ],
        ),
      ],
    );
  }

  String _themeFollowLabel(NovelThemeFollow f, AppLocalizations l10n) =>
      switch (f) {
        NovelThemeFollow.followApp => l10n.novelThemeFollowApp,
        NovelThemeFollow.alwaysDark => l10n.novelThemeFollowDark,
        NovelThemeFollow.alwaysLight => l10n.novelThemeFollowLight,
      };

  Widget _colorTile({
    required BuildContext context,
    required AppLocalizations l10n,
    required String title,
    String? subtitle,
    required int? current,
    required Color fallback,
    required ValueChanged<int> onPicked,
    required VoidCallback onClear,
    required String clearTooltip,
  }) {
    final displayed = Color(current ?? fallback.toARGB32());
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          GestureDetector(
            onTap: () async {
              // 修复：确认式取色（OK/Cancel），仅用户点确定时写回；
              // onColorChanged 同步写入局部变量，避免滑块回弹。
              Color? pickedColor;
              final Color initial = displayed;
              final result = await showDialog<Color>(
                context: context,
                builder: (ctx) => StatefulBuilder(
                  builder: (BuildContext ctx2, StateSetter setDialogState) {
                    return AppAlertDialog(
                      title: Text(title),
                      content: SingleChildScrollView(
                        child: ColorPicker(
                          pickerColor: pickedColor ?? initial,
                          onColorChanged: (c) =>
                              setDialogState(() => pickedColor = c),
                        ),
                      ),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: Text(
                            MaterialLocalizations.of(ctx).cancelButtonLabel,
                          ),
                        ),
                        FilledButton(
                          onPressed: () =>
                              Navigator.of(ctx).pop(pickedColor ?? initial),
                          child: Text(
                            MaterialLocalizations.of(ctx).okButtonLabel,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              );
              if (result != null) onPicked(result.toARGB32());
            },
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: displayed,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_rounded),
            tooltip: clearTooltip,
            onPressed: onClear,
          ),
        ],
      ),
    );
  }

  /// 字体文件选择瓦片：从本机选取 .ttf/.otf 字体并加载（[title]=true 时作用于标题字体）。
  Widget _fontFileTile({
    required BuildContext context,
    required AppLocalizations l10n,
    required bool title,
  }) {
    final currentPath =
        title ? prefs.titleCustomFontPath : prefs.customFontPath;
    final label = title ? l10n.novelTitleFontFile : l10n.novelChooseFontFile;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.font_download_rounded),
      title: Text(label),
      subtitle: currentPath != null
          ? Text(l10n
              .novelFontFileCurrent(currentPath.split(RegExp(r'[/\\]')).last))
          : null,
      trailing: currentPath != null
          ? IconButton(
              icon: const Icon(Icons.delete_rounded),
              tooltip: l10n.novelClearFontFile,
              onPressed: () => onChanged(
                title
                    ? prefs.copyWith(titleCustomFontPath: null)
                    : prefs.copyWith(customFontPath: null),
              ),
            )
          : null,
      onTap: () async {
        String? path;
        try {
          if (PlatformService.instance.isAndroid) {
            // 读外部字体文件可能需要存储权限；被拒也继续尝试（部分设备用系统选择器即可）。
            try {
              await Permission.storage.request();
            } on Object {
              // 忽略权限请求异常
            }
          }
          final result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: <String>['ttf', 'otf'],
          );
          path = result?.files.single.path;
        } on Object {
          path = null;
        }
        if (path == null || !context.mounted) return;
        try {
          await NovelReaderPreferences.loadCustomFont(
            title
                ? NovelReaderPreferences.customLoadedTitleFontFamily
                : NovelReaderPreferences.customLoadedFontFamily,
            path!,
          );
          onChanged(
            title
                ? prefs.copyWith(titleCustomFontPath: path)
                : prefs.copyWith(customFontPath: path),
          );
        } on Object {
          // 加载失败静默忽略
        }
      },
    );
  }

  /// 页眉/页脚单槽内容选择器：点按弹出单选菜单（无/书名/标题/时间/电量/页数/进度…）。
  Widget _buildHfSlotPicker(
    String label,
    NovelHeaderFooterContent value,
    ValueChanged<NovelHeaderFooterContent> onChanged, {
    required BuildContext context,
    required AppLocalizations l10n,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Text(_hfContentLabel(value, l10n)),
      onTap: () async {
        final picked = await showDialog<NovelHeaderFooterContent>(
          context: context,
          builder: (ctx) => AppAlertDialog(
            title: Text(label),
            content: SingleChildScrollView(
              child: RadioGroup<NovelHeaderFooterContent>(
                groupValue: value,
                onChanged: (v) => Navigator.of(ctx).pop(v),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (final c in NovelHeaderFooterContent.values)
                      RadioListTile<NovelHeaderFooterContent>(
                        title: Text(_hfContentLabel(c, l10n)),
                        value: c,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }

  /// 标题对齐方式标签（左/中/右/隐藏）。
  String _titleAlignLabel(NovelTitleAlign a, AppLocalizations l10n) {
    return switch (a) {
      NovelTitleAlign.left => l10n.novelTitleAlignLeft,
      NovelTitleAlign.center => l10n.novelTitleAlignCenter,
      NovelTitleAlign.right => l10n.novelTitleAlignRight,
      NovelTitleAlign.hidden => l10n.novelTitleAlignHidden,
    };
  }

  /// 朗读睡眠定时选择（分钟；0 = 关闭）。
  /// 预设 0/15/30/45/60/90 分钟，并提供「自定义」可输入任意分钟数
  /// （满足「自定义朗读时间」需求）。返回选中的分钟数（null = 取消）。
  /// 朗读睡眠定时选择（分钟；0 = 关闭）。设置面板入口。
  Future<void> _pickSleepTimer({
    required BuildContext context,
    required AppLocalizations l10n,
  }) async {
    final picked = await _pickSleepMinutes(
      context: context,
      l10n: l10n,
      current: tts.sleepRemaining?.inMinutes ?? 0,
    );
    if (picked == null) return;
    // 同时写回 prefs（持久化）并启动 controller 定时器，
    // 修复 Bug-3：选了不写回 prefs 导致重启后丢失。
    tts.startSleepTimer(picked);
    onChanged(prefs.copyWith(ttsSleepTimer: picked));
  }

  String _bgLabel(int index, AppLocalizations l10n) {
    return switch (index) {
      0 => l10n.readerBgBlack,
      1 => l10n.readerBgDarkGray,
      2 => l10n.readerBgWhite,
      3 => l10n.readerBgEyeCare,
      4 => l10n.readerBgParchment,
      5 => l10n.readerBgWarmLinen,
      6 => l10n.readerBgLightBrown,
      7 => l10n.readerBgBeanGreen,
      8 => l10n.readerBgMint,
      9 => l10n.readerBgApricot,
      10 => l10n.readerBgGrayBlue,
      11 => l10n.readerBgEInk,
      _ => l10n.readerBgWhite,
    };
  }
}

/// 翻页动画标签（与漫画共用 l10n key）。
String _animLabel(NovelPageAnimation anim, AppLocalizations l10n) {
  return switch (anim) {
    NovelPageAnimation.none => l10n.novelAnimNone,
    NovelPageAnimation.slide => l10n.novelAnimSlide,
    NovelPageAnimation.scroll => l10n.novelAnimScroll,
    NovelPageAnimation.fade => l10n.novelAnimFade,
    NovelPageAnimation.cover => l10n.novelAnimCover,
    NovelPageAnimation.simulation => l10n.novelAnimSimulation,
  };
}

/// 点击分区布局的本地化标签（与漫画共用 l10n key）。
String _tapLayoutLabel(AppLocalizations l10n, ReaderTapZoneLayout layout) {
  switch (layout) {
    case ReaderTapZoneLayout.lShape:
      return l10n.readerTapLShape;
    case ReaderTapZoneLayout.leftRight:
      return l10n.readerTapLeftRight;
    case ReaderTapZoneLayout.kindle:
      return l10n.readerTapKindle;
    case ReaderTapZoneLayout.bothSides:
      return l10n.readerTapBothSides;
    case ReaderTapZoneLayout.off:
      return l10n.readerTapOff;
  }
}

/// 点击分区方向反转的本地化标签（与漫画共用 l10n key）。
String _tapInvertLabel(AppLocalizations l10n, TapZoneInvert invert) {
  switch (invert) {
    case TapZoneInvert.none:
      return l10n.readerTapInvertNone;
    case TapZoneInvert.leftRight:
      return l10n.readerTapInvertLeftRight;
    case TapZoneInvert.upDown:
      return l10n.readerTapInvertUpDown;
    case TapZoneInvert.all:
      return l10n.readerTapInvertAll;
  }
}

/// 设置面板可折叠分组（-C）：标题一行 + 可展开内容，内置箭头动画。
/// 去掉 ExpansionTile 默认的上下分割线，样式与设置面板统一。
Widget _buildSettingsGroup(
  BuildContext context,
  String title, {
  bool initiallyExpanded = false,
  IconData? leading,
  List<String> searchTerms = const <String>[],
  String searchQuery = '',
  required List<Widget> children,
}) {
  // 搜索过滤：query 非空时，仅当组标题或别名命中才显示本组。
  final q = searchQuery.trim().toLowerCase();
  if (q.isNotEmpty) {
    final hay = <String>[title, ...searchTerms].join(' ').toLowerCase();
    if (!hay.contains(q)) return const SizedBox.shrink();
  }
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.only(bottom: AppTokens.spaceMd),
    child: Material(
      color: AppTheme.cardContainer(theme.colorScheme),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceMd,
            vertical: AppTokens.spaceXs,
          ),
          leading: leading == null
              ? null
              : Icon(leading, size: 22, color: theme.colorScheme.primary),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppTokens.spaceMd,
            0,
            AppTokens.spaceMd,
            AppTokens.spaceMd,
          ),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          initiallyExpanded: initiallyExpanded,
          title: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          children: children,
        ),
      ),
    ),
  );
}

/// 通用滑块行。
///
/// 拖动期间滑块与数值标签由本地状态驱动（不依赖父级重建，父级可只在
/// 松手时应用），[onChanged] 逐帧回调用于轻量预览，[onChangeEnd] 在松手
/// 时回调一次用于重操作提交（长章节整章重分页必须走这里，逐帧触发会
/// 连续阻塞 UI——「设置字号卡退」的根因）。
class _SliderRow extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String? unit;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    this.unit,
    required this.onChanged,
    this.onChangeEnd,
  });

  @override
  State<_SliderRow> createState() => _SliderRowState();
}

class _SliderRowState extends State<_SliderRow> {
  /// 拖动中的本地值（null = 未在拖动，显示父级值）。
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final double v = _dragValue ?? widget.value;
    // 视觉与设置设计系统的 SettingsSliderTile 对齐：标签在上一行、
    // 当前值 primary 加粗右对齐、滑块全宽；拖动本地值/松手提交逻辑保留。
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceXs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.label,
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              Text(
                widget.unit != null
                    ? '${v.toStringAsFixed(v < 10 ? 1 : 0)}${widget.unit}'
                    : v.toStringAsFixed(1),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ],
          ),
          Slider(
            value: v,
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            onChangeStart: (_) => AppHaptics.light(),
            onChanged: (nv) {
              setState(() => _dragValue = nv);
              widget.onChanged(nv);
            },
            onChangeEnd: (nv) {
              setState(() => _dragValue = null);
              widget.onChangeEnd?.call(nv);
            },
          ),
        ],
      ),
    );
  }
}

/// 滚动模式自适应插图（修订）：解码前按 2:1 占位（与旧缩略高度一致，
/// 避免列表跳动），拿到自然尺寸后按图片真实宽高比撑高完整显示（fitWidth
/// 不裁切）。修复「插图显示不全、要点开才能看全」。解码宽度限幅防大图卡顿。
class _AdaptiveScrollImage extends StatefulWidget {
  final String url;
  final PluginConfig? source;
  final double width;

  const _AdaptiveScrollImage({
    required this.url,
    required this.source,
    required this.width,
  });

  @override
  State<_AdaptiveScrollImage> createState() => _AdaptiveScrollImageState();
}

class _AdaptiveScrollImageState extends State<_AdaptiveScrollImage> {
  double? _ratio; // 高/宽；null = 尚未解码，按 2:1 占位。

  @override
  Widget build(BuildContext context) {
    final double h =
        _ratio != null ? widget.width * _ratio! : widget.width * 0.5;
    return SourceImage(
      url: widget.url,
      source: widget.source,
      width: widget.width,
      height: h,
      fit: BoxFit.fitWidth,
      radius: 8,
      decodeCapWidthPx: 1600,
      onImageInfo: (double w, double imgH) {
        if (!mounted || w <= 0 || imgH <= 0) return;
        final double r = imgH / w;
        if ((r - (_ratio ?? -1)).abs() > 0.001) {
          setState(() => _ratio = r);
        }
      },
    );
  }
}

/// 稳定长按选区手势容器：把 [RawGestureDetector] 及其识别器工厂封装成
/// StatefulWidget，**在 State 生命周期内持有同一份 gestures 配置实例**。
///
/// 为什么需要稳定实例：翻页动画期间 [NovelAnimatedPageView] 每帧重建、页面
/// 文本行随之外层 Widget 重建。若每次 build 都新建 `GestureRecognizerFactory`
/// 实例，`RawGestureDetector` 的 `didUpdateWidget → _syncAll` 虽会复用同 type
/// 识别器，但 `initializer` 每次重新绑定回调，且依赖 Element 位置完全稳定；
/// 一旦子树结构抖动（行数变化 / 动画期间 from/to 双页并存），识别器配置即被
/// 篡改/重建，进行中的长按被中途打断（表现：「选中闪一下就消失」）。
///
/// 这里 gestures map 只在 [initState] 创建一次并缓存，`initializer` 内回调经
/// [widget] 间接读取最新配置（组件重建时拿到的是新 widget 的新回调），
/// 识别器实例与配置在长按期间保持恒定。
class _StableLongPressDetector extends StatefulWidget {
  const _StableLongPressDetector({
    required this.onLongPressStart,
    this.onLongPressMoveUpdate,
    required this.onLongPressEnd,
    required this.child,
  });

  final void Function(LongPressStartDetails d)? onLongPressStart;
  final void Function(LongPressMoveUpdateDetails d)? onLongPressMoveUpdate;
  final VoidCallback? onLongPressEnd;
  final Widget child;

  @override
  State<_StableLongPressDetector> createState() =>
      _StableLongPressDetectorState();
}

class _StableLongPressDetectorState extends State<_StableLongPressDetector> {
  late final Map<Type, GestureRecognizerFactory> _gestures;

  @override
  void initState() {
    super.initState();
    // 只创建一次：识别器实例恒定，长按期间外层如何重建都不会被替换/重置。
    // 识别器用公共大容忍版（core/widgets/tolerant_long_press.dart）：
    // 40px 预接受容忍，手指自然抖动不打断长按。
    _gestures = <Type, GestureRecognizerFactory>{
      TolerantLongPressGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<TolerantLongPressGestureRecognizer>(
        () => TolerantLongPressGestureRecognizer(),
        // initializer 每次 _syncAll 都会执行；回调读取 widget 最新配置，
        // 因此组件重建（换行/换块）后长按仍绑定到新的行/块。
        (TolerantLongPressGestureRecognizer instance) {
          instance.onLongPressStart = (d) => widget.onLongPressStart?.call(d);
          instance.onLongPressMoveUpdate =
              (d) => widget.onLongPressMoveUpdate?.call(d);
          instance.onLongPressEnd = (_) => widget.onLongPressEnd?.call();
        },
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: _gestures,
      child: widget.child,
    );
  }
}

/// 分享卡片：带书封的渐变文艺卡（Phase 3 /）。
///
/// 1080×1440（3:4）竖卡（桌面端完整尺寸，手机端紧凑版）：顶部书封 + 渐变叠层，
/// 中部引文大字号，底部书名 / 章节 / 落款。书封缺省时用渐变占位。
/// 供 [RepaintBoundary] 栅格化分享。
class _NovelShareCard extends StatelessWidget {
  const _NovelShareCard({
    required this.quote,
    required this.title,
    required this.chapterTitle,
    this.coverUrl,
    this.compact = false,
    this.coverScale = 1.0,
  });

  final String quote;
  final String title;
  final String chapterTitle;
  final String? coverUrl;
  final bool compact;
  final double coverScale;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final double w = compact ? 360 : 1080;
    final double h = compact ? 480 : 1440;
    final double p = compact ? 24 : 72;
    final double coverH = (compact ? 170 : 520) * coverScale;
    final double titleFontSize = compact ? 18 : 40;
    final double quoteFontSize = compact ? 16 : 38;
    final double metaFontSize = compact ? 13 : 30;
    final double brandFontSize = compact ? 14 : 28;
    final double radius = compact ? 12 : 24;
    final double quotePadding = compact ? 16 : 40;
    final double spacing = compact ? 16 : 48;
    final double gap = compact ? 12 : 40;
    final double coverTitleLeft = compact ? 12 : 32;
    final double coverTitleBottom = compact ? 10 : 28;
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[
        cs.primary.withValues(alpha: 0.85),
        cs.primaryContainer.withValues(alpha: 0.95),
        cs.surface,
      ],
    );
    final Widget cover = (coverUrl != null && coverUrl!.isNotEmpty)
        ? (coverUrl!.startsWith('http://') || coverUrl!.startsWith('https://')
            ? Image.network(
                coverUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  decoration: BoxDecoration(gradient: gradient),
                ),
              )
            : Image.file(
                File(coverUrl!),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  decoration: BoxDecoration(gradient: gradient),
                ),
              ))
        : Container(decoration: BoxDecoration(gradient: gradient));
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[cs.surface, cs.surfaceContainerHighest],
        ),
      ),
      padding: EdgeInsets.all(p),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 书封 + 渐变叠层
          ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Stack(
              children: <Widget>[
                SizedBox(
                  width: double.infinity,
                  height: coverH,
                  child: cover,
                ),
                Container(
                  width: double.infinity,
                  height: coverH,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.55),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: coverTitleLeft,
                  bottom: coverTitleBottom,
                  right: coverTitleLeft,
                  child: Text(
                    title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.w700,
                      shadows: const <Shadow>[
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: spacing),
          // 引文
          Expanded(
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.all(quotePadding),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(
                  color: cs.outline.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                quote,
                style: TextStyle(
                  fontSize: quoteFontSize,
                  height: 1.7,
                  color: cs.onSurface,
                  fontFamily: 'serif',
                ),
                maxLines: 12,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          SizedBox(height: gap),
          // 章节 + 落款
          if (chapterTitle.isNotEmpty)
            Text(
              chapterTitle,
              style: TextStyle(
                fontSize: metaFontSize,
                color: cs.onSurface.withValues(alpha: 0.75),
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (chapterTitle.isNotEmpty) SizedBox(height: compact ? 4 : 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                '—— 摘自《$title》',
                style: TextStyle(
                  fontSize: metaFontSize,
                  color: cs.onSurface.withValues(alpha: 0.6),
                  fontStyle: FontStyle.italic,
                ),
              ),
              Text(
                'NexHub',
                style: TextStyle(
                  fontSize: brandFontSize,
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 合并笔记条目（独立笔记 + 划线摘录笔记），用于笔记列表统一展示。
class _MergedNoteEntry {
  final int chapterIndex;
  final String chapterTitle;
  final String quote;
  final String note;
  final int createdAt;
  final bool isHighlightNote;

  /// 用于删除操作的实际 key（独立笔记用 NovelNote.id，划线笔记用 highlight.key）。
  final String deleteKey;

  const _MergedNoteEntry({
    required this.chapterIndex,
    required this.chapterTitle,
    required this.quote,
    required this.note,
    required this.createdAt,
    required this.isHighlightNote,
    required this.deleteKey,
  });
}

/// 划词翻译对话框：复用小说整章翻译管线翻译单条选中文本。
class _SelectionTranslateDialog extends StatefulWidget {
  final String text;
  final String novelId;

  const _SelectionTranslateDialog({
    required this.text,
    required this.novelId,
  });

  @override
  State<_SelectionTranslateDialog> createState() =>
      _SelectionTranslateDialogState();
}

class _SelectionTranslateDialogState extends State<_SelectionTranslateDialog> {
  String? _result;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final translated = await NovelTranslationService()
          .translateParagraphs(<String>[widget.text], workId: widget.novelId);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _result = translated.isNotEmpty ? translated.first : '';
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.selTranslateTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: _loading
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(l10n.askAiThinking),
                ],
              )
            : _error != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('${l10n.selTranslateFailed}\n$_error'),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _run,
                          child: Text(l10n.selTranslateRetry),
                        ),
                      ),
                    ],
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          l10n.selTranslateSource,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(widget.text),
                        const SizedBox(height: 16),
                        Text(
                          l10n.selTranslateResult,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          _result ?? '',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                height: 1.5,
                              ),
                        ),
                      ],
                    ),
                  ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}

/// 简易颜色滑块：直接操作 int 颜色值，滑块拖动实时更新。
class _SimpleColorSlider extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _SimpleColorSlider({
    required this.value,
    required this.onChanged,
  });

  @override
  State<_SimpleColorSlider> createState() => _SimpleColorSliderState();
}

class _SimpleColorSliderState extends State<_SimpleColorSlider> {
  late double _r;
  late double _g;
  late double _b;
  late double _a;

  @override
  void initState() {
    super.initState();
    _fromColor(widget.value);
  }

  @override
  void didUpdateWidget(_SimpleColorSlider old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _fromColor(widget.value);
    }
  }

  void _fromColor(int color) {
    final c = Color(color);
    _r = c.r;
    _g = c.g;
    _b = c.b;
    _a = c.a;
  }

  int get _currentValue =>
      Color.from(alpha: _a, red: _r, green: _g, blue: _b).toARGB32();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _slider(
            'R',
            _r,
            (v) => setState(() {
                  _r = v;
                  widget.onChanged(_currentValue);
                })),
        _slider(
            'G',
            _g,
            (v) => setState(() {
                  _g = v;
                  widget.onChanged(_currentValue);
                })),
        _slider(
            'B',
            _b,
            (v) => setState(() {
                  _b = v;
                  widget.onChanged(_currentValue);
                })),
        _slider(
            'A',
            _a,
            (v) => setState(() {
                  _a = v;
                  widget.onChanged(_currentValue);
                })),
      ],
    );
  }

  Widget _slider(String label, double value, ValueChanged<double> onChanged) {
    return Row(
      children: <Widget>[
        SizedBox(
            width: 16,
            child: Text(label, style: const TextStyle(fontSize: 11))),
        Expanded(
          child: Slider(
            value: value,
            min: 0.0,
            max: 1.0,
            divisions: 255,
            onChangeStart: (_) => AppHaptics.light(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
            width: 36,
            child: Text(
              (value * 255).round().toString(),
              style: const TextStyle(fontSize: 10),
              textAlign: TextAlign.right,
            )),
      ],
    );
  }
}

/// 小说插图大图查看器（统一图片收藏图库）。
///
/// 黑底 + InteractiveViewer 缩放；AppBar 提供「收藏 / 取消收藏」按钮，收藏写入
/// 与漫画共用的 Hive `image_favorites` box（来源 = novel，按 URL 去重）。
class _NovelImageFavoriteViewer extends StatefulWidget {
  final String url;
  final PluginConfig? source;
  final String workId;
  final String workTitle;
  final String label;

  const _NovelImageFavoriteViewer({
    required this.url,
    this.source,
    required this.workId,
    required this.workTitle,
    required this.label,
  });

  @override
  State<_NovelImageFavoriteViewer> createState() =>
      _NovelImageFavoriteViewerState();
}

class _NovelImageFavoriteViewerState extends State<_NovelImageFavoriteViewer> {
  final ImageFavoriteManager _manager = ImageFavoriteManager();
  bool? _isFavorite;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final bool fav = await _manager.isFavoriteByUrl(widget.url);
    if (mounted) setState(() => _isFavorite = fav);
  }

  Future<void> _toggleFavorite() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool added = await _manager.toggleByUrl(
      source: ImageFavoriteSource.novel,
      workId: widget.workId,
      workTitle: widget.workTitle,
      label: widget.label,
      imageUrl: widget.url,
    );
    if (!mounted) return;
    setState(() => _isFavorite = added);
    if (added) {
      // 收藏即缓存到本地（取消收藏时才删文件，清理缓存不清理）。
      unawaited(_manager.attachLocalCache(widget.url));
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added ? l10n.imageFavoriteAdded : l10n.imageFavoriteRemoved,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: <Widget>[
          IconButton(
            tooltip: AppLocalizations.of(context).imageFavoriteAdd,
            icon: Icon(
              _isFavorite == true
                  ? Icons.star_rounded
                  : Icons.star_border_rounded,
              color: Colors.white,
            ),
            onPressed: _toggleFavorite,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (BuildContext ctx, BoxConstraints c) => InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Center(
            child: SourceImage(
              url: widget.url,
              source: widget.source,
              width: c.maxWidth,
              height: c.maxHeight,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}

/// 预扫描的 UI 状态快照（阅读器 → 翻译面板经 [ValueNotifier] 共享）。
class NovelPrescanUi {
  final bool running;
  final int done;
  final int total;

  /// 全书概述是否已生成（生成后翻译自动注入作品语境）。
  final bool ready;

  const NovelPrescanUi({
    this.running = false,
    this.done = 0,
    this.total = 0,
    this.ready = false,
  });

  NovelPrescanUi copyWith(
          {bool? running, int? done, int? total, bool? ready}) =>
      NovelPrescanUi(
        running: running ?? this.running,
        done: done ?? this.done,
        total: total ?? this.total,
        ready: ready ?? this.ready,
      );

  NovelPrescanUi copyWithRunning(bool running) => copyWith(running: running);
}

/// 段落翻译双语面板：原文/译文逐段对照；缓存命中直接展示，
/// 「翻译本章」走云端 AI（批量优先、分块回退），完成后持久化缓存。
/// 可触发全书预扫描（章节摘要+全书概述），翻译时自动注入作品语境。
class _NovelTranslationSheet extends StatefulWidget {
  const _NovelTranslationSheet({
    required this.novelId,
    required this.chapterId,
    required this.chapterTitle,
    this.chapterIndex,
    required this.paragraphs,
    required this.targetLanguage,
    required this.manager,
    this.previousChapterId,
    this.prescanManager,
    this.prescanUi,
    this.onStartPrescan,
  });

  final String novelId;
  final String chapterId;
  final String chapterTitle;

  /// 章节序号（术语首次出现章节标记用，可空）。
  final int? chapterIndex;
  final List<String> paragraphs;

  /// 翻译目标语言（取自翻译配置页；兼作缓存 lang 标记）。
  final String targetLanguage;
  final NovelTranslationManager manager;

  /// 前一章 id（缓存存在时取其尾部译文作为本章衔接上下文）。
  final String? previousChapterId;

  /// 全书预扫描（null 时隐藏预扫描入口，如测试环境）。
  final NovelPrescanManager? prescanManager;
  final ValueNotifier<NovelPrescanUi>? prescanUi;
  final VoidCallback? onStartPrescan;

  @override
  State<_NovelTranslationSheet> createState() => _NovelTranslationSheetState();
}

class _NovelTranslationSheetState extends State<_NovelTranslationSheet> {
  List<String>? _translations;
  bool _translating = false;
  String? _progress;
  String _progressTotal = '';
  String? _error;

  /// 断点续译：未完成章节的分块检查点（空串位 = 待译段）。
  List<String>? _checkpoint;

  /// 防竞态：重试续译时旧任务的检查点回调不再落盘。
  int _runSeq = 0;

  // ── 多阶段质量：润色（独立槽位，可对照切换）──
  List<String>? _polished;
  bool _showPolished = false;
  bool _polishing = false;
  String? _polishProgress;
  bool _polishEnabled = false;

  /// 自动提取术语的累计结果（本次翻译会话；重译时清零）。
  int _extractedTerms = 0;
  int _extractedConflicts = 0;

  /// 当前缓存的输入指纹与过期状态（旧缓存无指纹时不做判断）。
  String? _cachedFingerprint;
  bool _stale = false;

  /// 精译模式开关（全局持久化，默认关）。
  bool _refined = false;

  @override
  void initState() {
    super.initState();
    _loadCache();
    widget.prescanUi?.addListener(_onPrescanChanged);
  }

  /// 展示用的译文变体（润色结果存在且被选中时用润色列表）。
  List<String>? get _displayTranslations =>
      _showPolished && _polished != null ? _polished : _translations;

  Future<void> _polish() async {
    if (_polishing || _translations == null) return;
    setState(() {
      _polishing = true;
      _polishProgress = null;
      _error = null;
    });
    try {
      final settings = NovelSummarySettings.instance;
      final cfg = await settings.getTranslationConfig();
      if (cfg.baseUrl.trim().isEmpty) {
        throw const TranslationException('未配置云端 AI 接口');
      }
      var glossary = const <GlossaryEntry>[];
      try {
        glossary = await GlossaryManager()
            .effectiveEntries(widget.novelId, widget.targetLanguage);
      } on Object {
        // 术语表不可用时按无术语润色。
      }
      final result = await NovelPolishService().polishParagraphs(
        cfg: cfg,
        lang: widget.targetLanguage,
        sources: widget.paragraphs,
        translations: _translations!,
        glossary: glossary,
        onProgress: (done, total) {
          if (mounted) {
            setState(() => _polishProgress = '$done/$total');
          }
        },
      );
      await widget.manager.savePolished(NovelChapterTranslation(
        novelId: widget.novelId,
        chapterId: widget.chapterId,
        chapterTitle: widget.chapterTitle,
        lang: widget.targetLanguage,
        translations: result,
        sources: widget.paragraphs,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
      if (mounted) {
        setState(() {
          _polished = result;
          _showPolished = true;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _polishing = false);
    }
  }

  void _onPrescanChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.prescanUi?.removeListener(_onPrescanChanged);
    super.dispose();
  }

  bool get _hasCheckpoint =>
      _checkpoint != null && _checkpoint!.any((t) => t.isEmpty);

  Future<void> _loadCache() async {
    // 精译开关（读取失败按默认关闭）。
    try {
      final refined = await TranslationOptionsStore().getRefinedEnabled();
      if (mounted) setState(() => _refined = refined);
    } on Object {
      // 保持默认。
    }
    final cached = await widget.manager.load(
      widget.novelId,
      widget.chapterId,
      lang: widget.targetLanguage,
    );
    if (cached != null) {
      final stale = await NovelTranslationFingerprint.isStale(
        cachedFingerprint: cached.fingerprint,
        workId: widget.novelId,
        lang: widget.targetLanguage,
        sources: widget.paragraphs,
      );
      if (mounted) {
        setState(() {
          _translations = cached.translations;
          _cachedFingerprint = cached.fingerprint;
          _stale = stale;
        });
      }
      return;
    }
    // 无完整缓存时读取分块检查点，展示已完成段并提供「继续翻译」。
    final partial = await widget.manager.loadCheckpoint(
      widget.novelId,
      widget.chapterId,
      lang: widget.targetLanguage,
    );
    if (partial != null && mounted) {
      setState(() => _checkpoint = partial.translations);
    }
    // 润色结果与功能开关（重进面板恢复对照切换）。
    try {
      final polished = await widget.manager.loadPolished(
        widget.novelId,
        widget.chapterId,
        lang: widget.targetLanguage,
      );
      final enabled = await TranslationOptionsStore().getPolishEnabled();
      if (mounted) {
        setState(() {
          _polished = polished?.translations;
          _polishEnabled = enabled;
        });
      }
    } on Object {
      // 润色状态读取失败不影响面板。
    }
    // 打开面板时同步预扫描状态（此前会话已生成的概述立即显示注入标记）。
    final prescanManager = widget.prescanManager;
    if (prescanManager != null && widget.prescanUi != null) {
      try {
        final data = await prescanManager.load(
          widget.novelId,
          lang: widget.targetLanguage,
        );
        if (data?.overview != null &&
            !widget.prescanUi!.value.ready &&
            mounted) {
          widget.prescanUi!.value = widget.prescanUi!.value.copyWith(
            ready: true,
            done: data!.chapters.length,
            total: data.chapters.length,
          );
        }
      } on Object {
        // 预扫描状态读取失败不影响面板。
      }
    }
  }

  Future<void> _translate({bool resume = false}) async {
    if (_translating) return;
    final seq = ++_runSeq;
    setState(() {
      _translating = true;
      _error = null;
      _progress = null;
      _extractedTerms = 0;
      _extractedConflicts = 0;
    });
    final existing = resume && _checkpoint != null
        ? List<String>.of(_checkpoint!)
        : const <String>[];
    // 作品语境（全书概述 + 本章前情摘要）注入 system prompt。
    String? bookContext;
    try {
      final prescan = await (widget.prescanManager ?? NovelPrescanManager())
          .load(widget.novelId, lang: widget.targetLanguage);
      bookContext =
          NovelPrescanManager.novelBookContext(prescan, widget.chapterId);
    } on Object {
      bookContext = null; // 语境读取失败不影响翻译。
    }
    // 前章已缓存译文 → 本章开头的指代与语气衔接上下文。
    var previousContext = <({String source, String translation})>[];
    final prevChapterId = widget.previousChapterId;
    if (prevChapterId != null) {
      try {
        final prev = await widget.manager.load(
          widget.novelId,
          prevChapterId,
          lang: widget.targetLanguage,
        );
        final sources = prev?.sources;
        if (prev != null && sources != null) {
          previousContext = <({String source, String translation})>[
            for (var i = 0;
                i < sources.length && i < prev.translations.length;
                i++)
              if (sources[i].trim().isNotEmpty &&
                  prev.translations[i].trim().isNotEmpty)
                (source: sources[i], translation: prev.translations[i]),
          ];
        }
      } on Object {
        // 前章未译或读取失败：按无跨章上下文翻译。
      }
    }
    try {
      final result = await NovelTranslationService(
        targetLanguage: widget.targetLanguage,
      ).translateParagraphs(
        widget.paragraphs,
        workId: widget.novelId,
        existing: existing,
        bookContext: bookContext,
        previousChapterContext: previousContext,
        chapterId: widget.chapterId,
        chapterTitle: widget.chapterTitle,
        chapterIndex: widget.chapterIndex,
        // 术语提取逐块累计，完成后在面板内展示并可直接进入裁决。
        onGlossaryExtracted: (summary) {
          if (!mounted || seq != _runSeq || summary.isEmpty) return;
          setState(() {
            _extractedTerms += summary.changed;
            _extractedConflicts += summary.conflicts;
          });
        },
        // 每个分块完成即落盘检查点，中断后可从断点续译。
        onChunkPersisted: (snapshot) {
          if (seq != _runSeq) return;
          _checkpoint = snapshot;
          widget.manager.saveCheckpoint(NovelChapterTranslation(
            novelId: widget.novelId,
            chapterId: widget.chapterId,
            chapterTitle: widget.chapterTitle,
            lang: widget.targetLanguage,
            translations: snapshot,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ));
        },
        onProgress: (done, total) {
          if (mounted) {
            setState(() {
              _progress = '$done';
              _progressTotal = '$total';
            });
          }
        },
      );
      final fingerprint = await NovelTranslationFingerprint.computeForWork(
        workId: widget.novelId,
        lang: widget.targetLanguage,
        sources: widget.paragraphs,
      );
      await widget.manager.save(NovelChapterTranslation(
        novelId: widget.novelId,
        chapterId: widget.chapterId,
        chapterTitle: widget.chapterTitle,
        lang: widget.targetLanguage,
        translations: result,
        sources: widget.paragraphs,
        fingerprint: fingerprint,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
      // 完整译文已落盘，检查点使命完成；旧润色结果随重译失效。
      await widget.manager.clearCheckpoint(
        widget.novelId,
        widget.chapterId,
        lang: widget.targetLanguage,
      );
      await widget.manager.clearPolished(
        widget.novelId,
        widget.chapterId,
        lang: widget.targetLanguage,
      );
      if (mounted) {
        setState(() {
          _translations = result;
          _checkpoint = null;
          _polished = null;
          _showPolished = false;
          _cachedFingerprint = fingerprint;
          _stale = false;
        });
      }
    } on Object catch (e) {
      // 归一化后的可读文案；已完成分块保留在检查点，可重试续译。
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  /// 预扫描行：入口按钮 / 进度 / 完成标记。
  Widget _prescanRow(AppLocalizations l10n, ColorScheme scheme) {
    if (widget.onStartPrescan == null || widget.prescanUi == null) {
      return const SizedBox.shrink();
    }
    final ui = widget.prescanUi!.value;
    if (ui.running) {
      return Padding(
        padding: const EdgeInsets.only(
            left: AppTokens.spaceMd,
            right: AppTokens.spaceMd,
            bottom: AppTokens.spaceXs),
        child: Row(
          children: <Widget>[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppTokens.spaceSm),
            Expanded(
              child: Text(
                l10n.prescanProgress(ui.done, ui.total),
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }
    if (ui.ready) {
      return Padding(
        padding: const EdgeInsets.only(
            left: AppTokens.spaceMd,
            right: AppTokens.spaceMd,
            bottom: AppTokens.spaceXs),
        child: Row(
          children: <Widget>[
            Icon(Icons.auto_stories_rounded, size: 14, color: scheme.primary),
            const SizedBox(width: AppTokens.spaceXs),
            Text(
              l10n.prescanReady,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(
            left: AppTokens.spaceMd, bottom: AppTokens.spaceXs),
        child: TextButton.icon(
          onPressed: widget.onStartPrescan,
          icon: const Icon(Icons.travel_explore_rounded, size: 16),
          label: Text(l10n.prescanStart, style: const TextStyle(fontSize: 12)),
        ),
      ),
    );
  }

  /// 润色行：润色按钮（带进度）/ 已润色时初译/润色切换。
  Widget _polishRow(AppLocalizations l10n, ColorScheme scheme) {
    if (_polished != null) {
      return Padding(
        padding: const EdgeInsets.only(
            left: AppTokens.spaceMd,
            right: AppTokens.spaceMd,
            bottom: AppTokens.spaceXs),
        child: SegmentedButton<bool>(
          segments: <ButtonSegment<bool>>[
            ButtonSegment<bool>(
              value: false,
              label: Text(l10n.translationVariantOriginal),
            ),
            ButtonSegment<bool>(
              value: true,
              label: Text(l10n.translationVariantPolished),
            ),
          ],
          selected: <bool>{_showPolished},
          onSelectionChanged: (s) => setState(() => _showPolished = s.first),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(
            left: AppTokens.spaceMd, bottom: AppTokens.spaceXs),
        child: _polishing
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: AppTokens.spaceSm),
                  Text(
                    _polishProgress ?? l10n.novelTranslating,
                    style:
                        TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              )
            : TextButton.icon(
                onPressed: _polish,
                icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                label: Text(l10n.polishAction,
                    style: const TextStyle(fontSize: 12)),
              ),
      ),
    );
  }

  Future<void> _openGlossary() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TranslationGlossaryScreen(workId: widget.novelId),
      ),
    );
    if (!mounted) return;
    await _refreshStale();
  }

  /// 术语页返回后重算：裁决策略可能改变本章实际命中的术语。
  Future<void> _refreshStale() async {
    final cached = _cachedFingerprint;
    if (cached == null || cached.isEmpty || _translations == null) {
      if (mounted) setState(() => _stale = false);
      return;
    }
    final stale = await NovelTranslationFingerprint.isStale(
      cachedFingerprint: cached,
      workId: widget.novelId,
      lang: widget.targetLanguage,
      sources: widget.paragraphs,
    );
    if (mounted) setState(() => _stale = stale);
  }

  /// 切换精译开关：持久化并重算缓存过期状态（开关改变指纹输入）。
  Future<void> _toggleRefined(bool v) async {
    setState(() => _refined = v);
    try {
      await TranslationOptionsStore().setRefinedEnabled(v);
    } on Object {
      // 持久化失败不影响本次会话内的开关状态。
    }
    await _refreshStale();
  }

  /// 精译开关行：三稿合成，标注成本（默认关）。
  Widget _refinedRow(AppLocalizations l10n, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(
          left: AppTokens.spaceMd,
          right: AppTokens.spaceMd,
          bottom: AppTokens.spaceXs),
      child: Row(
        children: <Widget>[
          Icon(Icons.auto_awesome_rounded, size: 14, color: scheme.primary),
          const SizedBox(width: AppTokens.spaceXs),
          Expanded(
            child: Text(
              l10n.translationRefinedMode,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          SizedBox(
            height: 32,
            child: Switch(
              value: _refined,
              onChanged: _translating ? null : (v) => _toggleRefined(v),
            ),
          ),
        ],
      ),
    );
  }

  /// 缓存过期提示：输入已变化时建议重译，不自动删除旧译文。
  Widget _staleRow(AppLocalizations l10n, ColorScheme scheme) {
    if (!_stale || _translations == null || _translating) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(
          left: AppTokens.spaceMd,
          right: AppTokens.spaceMd,
          bottom: AppTokens.spaceXs),
      child: Row(
        children: <Widget>[
          Icon(Icons.update_rounded, size: 14, color: scheme.tertiary),
          const SizedBox(width: AppTokens.spaceXs),
          Expanded(
            child: Text(
              l10n.translationStaleNotice,
              style: TextStyle(fontSize: 12, color: scheme.tertiary),
            ),
          ),
          TextButton(
            onPressed: () => _translate(),
            child: Text(
              l10n.novelTranslateRetranslate,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// 自动提取结果行：收录/冲突计数 + 直达作品术语表裁决。
  Widget _glossaryExtractRow(AppLocalizations l10n, ColorScheme scheme) {
    if (_extractedTerms == 0 && _extractedConflicts == 0) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(
          left: AppTokens.spaceMd,
          right: AppTokens.spaceMd,
          bottom: AppTokens.spaceXs),
      child: Row(
        children: <Widget>[
          Icon(Icons.menu_book_rounded, size: 14, color: scheme.primary),
          const SizedBox(width: AppTokens.spaceXs),
          Expanded(
            child: Text(
              l10n.glossaryExtractedNotice(
                  _extractedTerms, _extractedConflicts),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: _openGlossary,
            child: Text(l10n.glossaryExtractedOpen,
                style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppTokens.spaceMd),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      l10n.novelParagraphTranslate,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.glossaryTitle,
                    onPressed: _openGlossary,
                    icon: const Icon(Icons.menu_book_rounded, size: 20),
                  ),
                  FilledButton.icon(
                    onPressed: _translating || widget.paragraphs.isEmpty
                        ? null
                        : () => _translate(
                            resume: _translations == null && _hasCheckpoint),
                    icon: _translating
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.translate_rounded, size: 18),
                    label: Text(_translations == null
                        ? (_hasCheckpoint
                            ? l10n.novelTranslateResume
                            : l10n.novelTranslateAction)
                        : l10n.novelTranslateRetranslate),
                  ),
                ],
              ),
            ),
            if (_translating && _progress != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppTokens.spaceXs),
                child: Text(
                    l10n.novelTranslateProgress(_progress!, _progressTotal),
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ),
            if (!_translating && _translations == null && _hasCheckpoint)
              Padding(
                padding: const EdgeInsets.only(bottom: AppTokens.spaceXs),
                child: Text(
                  l10n.novelTranslateResumable(
                    _checkpoint!.where((t) => t.isNotEmpty).length,
                    widget.paragraphs.length,
                  ),
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ),
            _refinedRow(l10n, scheme),
            _staleRow(l10n, scheme),
            _prescanRow(l10n, scheme),
            _glossaryExtractRow(l10n, scheme),
            // 润色入口与初译/润色对照切换。
            if (!_translating && _translations != null && _polishEnabled)
              _polishRow(l10n, scheme),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(
                    bottom: AppTokens.spaceXs,
                    left: AppTokens.spaceMd,
                    right: AppTokens.spaceMd),
                child: Text(
                  _error!,
                  style: TextStyle(fontSize: 12, color: scheme.error),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: (_displayTranslations == null && !_hasCheckpoint)
                  ? Center(
                      child: Text(
                        _translating
                            ? l10n.novelTranslating
                            : l10n.novelTranslateHint,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(AppTokens.spaceMd),
                      itemCount: widget.paragraphs.length,
                      itemBuilder: (context, i) {
                        final t = i <
                                (_displayTranslations ??
                                        _checkpoint ??
                                        const <String>[])
                                    .length
                            ? (_displayTranslations ??
                                _checkpoint ??
                                const <String>[])[i]
                            : '';
                        return Padding(
                          padding:
                              const EdgeInsets.only(bottom: AppTokens.spaceMd),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(widget.paragraphs[i],
                                  style: const TextStyle(
                                      fontSize: 14, height: 1.5)),
                              const SizedBox(height: AppTokens.spaceXs),
                              Text(
                                t.isEmpty ? '…' : t,
                                style: TextStyle(
                                    fontSize: 14,
                                    height: 1.5,
                                    color: scheme.primary),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 整章正文编辑对话框。
///
/// 控制器由本 State 持有：待对话框（含退场动画）完全卸载后才释放，避免在
/// 退场动画期间释放仍被 [EditableText] 使用的控制器，触发「used after
/// being disposed」并连锁引发 build scope 崩溃。取消返回 null，确认返回
/// 编辑后的全文。
class _NovelContentEditDialog extends StatefulWidget {
  const _NovelContentEditDialog({
    required this.initialText,
    required this.hintText,
  });

  final String initialText;
  final String hintText;

  @override
  State<_NovelContentEditDialog> createState() =>
      _NovelContentEditDialogState();
}

class _NovelContentEditDialogState extends State<_NovelContentEditDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.novelContentEdit),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.55,
        child: TextField(
          controller: _controller,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: const TextStyle(fontSize: 14, height: 1.5),
          decoration: InputDecoration(
            hintText: widget.hintText,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(l10n.confirm),
        ),
      ],
    );
  }
}
