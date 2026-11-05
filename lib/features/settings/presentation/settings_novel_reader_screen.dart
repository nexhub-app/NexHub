/// 小说阅读器设置子页 —— 小说阅读默认（全局默认值，打开小说时兜底生效）。
///
/// 持久化到 SharedPreferences（key: `reader_default_settings_v1`）。
library;

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:media_kit/media_kit.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../../../core/comic/models/reader_preferences.dart';
import '../../../core/novel/novel_edge_tts_engine.dart';
import '../../../core/novel/novel_http_tts_config.dart';
import '../../../core/novel/novel_tts_audio_cache.dart';
import '../../../core/novel/novel_page_animation.dart';
import '../../../core/novel/novel_pre_download_preferences.dart';
import '../../../core/novel/novel_reader_preferences.dart';
import '../../../core/novel/novel_replace_rule_screen.dart';
import '../../../core/platform/platform_service.dart';
import '../../../core/settings/reader_default_settings.dart';
import '../../../core/novel/novel_export_template.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/reader_tokens.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/app_alert_dialog.dart';
import '../../../core/widgets/app_animations.dart';
import '../../manga/presentation/reader_tap_zones.dart';
import '../../../core/widgets/app_glass_bar.dart';
import 'widgets/settings_widgets.dart';
import 'widgets/settings_search_target.dart';

/// 小说阅读器默认设置页面。
class SettingsNovelReaderScreen extends StatefulWidget {
  const SettingsNovelReaderScreen({super.key});

  @override
  State<SettingsNovelReaderScreen> createState() =>
      _SettingsNovelReaderScreenState();
}

class _SettingsNovelReaderScreenState extends State<SettingsNovelReaderScreen> {
  final ReaderDefaultSettingsStore _store = ReaderDefaultSettingsStore();
  late ReaderDefaultSettings _settings;
  bool _loaded = false;

  /// 阅读中预下载配置（独立于 [_settings] 聚合，直接读写）。
  NovelPreDownloadPreferences _preDownload =
      const NovelPreDownloadPreferences();

  /// 在线 HTTP TTS 配置（独立持久化，直接读写）。
  NovelHttpTtsConfig _httpTts = const NovelHttpTtsConfig();

  /// 朗读音频缓存条数（惰性统计）。
  int _ttsCacheCount = 0;

  /// EPUB 导出模板（全局配置，直接读写）。
  NovelExportTemplate _exportTemplate = const NovelExportTemplate();
  final TextEditingController _exportCssController = TextEditingController();
  final TextEditingController _exportIntroController = TextEditingController();
  Timer? _exportSaveDebounce;

  @override
  void initState() {
    super.initState();
    _settings = const ReaderDefaultSettings();
    _store.load().then((s) {
      if (mounted) {
        setState(() {
          _settings = s;
          _loaded = true;
        });
      }
    });
    NovelPreDownloadPreferences.load().then((p) {
      if (mounted) setState(() => _preDownload = p);
    });
    NovelHttpTtsConfigStore().load().then((c) {
      if (mounted) setState(() => _httpTts = c);
    });
    TtsAudioFileCache.createDefault().then((cache) async {
      final (count, _) = await cache.stats();
      if (mounted) setState(() => _ttsCacheCount = count);
    });
    NovelExportTemplateStore.instance.load().then((t) {
      if (!mounted) return;
      _exportCssController.text = t.customCss;
      _exportIntroController.text = t.intro;
      setState(() => _exportTemplate = t);
    });
  }

  @override
  void dispose() {
    _exportSaveDebounce?.cancel();
    _exportCssController.dispose();
    _exportIntroController.dispose();
    _stopVoicePreview();
    super.dispose();
  }

  /// 更新导出模板（开关类立即落盘）。
  void _updateExportTemplate(NovelExportTemplate next) {
    setState(() => _exportTemplate = next);
    NovelExportTemplateStore.instance.save(next);
  }

  /// 文本字段防抖保存（停顿 600ms 后写入）。
  void _saveExportTemplateDebounced() {
    _exportSaveDebounce?.cancel();
    _exportSaveDebounce = Timer(const Duration(milliseconds: 600), () {
      NovelExportTemplateStore.instance.save(
        _exportTemplate.copyWith(
          customCss: _exportCssController.text,
          intro: _exportIntroController.text,
        ),
      );
    });
  }

  void _update(ReaderDefaultSettings next) {
    setState(() => _settings = next);
    _store.save(next);
  }

  void _updatePreDownload(NovelPreDownloadPreferences next) {
    setState(() => _preDownload = next);
    NovelPreDownloadPreferences.save(next);
  }

  /// 保存在线 TTS 配置。
  void _updateHttpTts(NovelHttpTtsConfig next) {
    setState(() => _httpTts = next);
    NovelHttpTtsConfigStore().save(next);
  }

  /// 分区内小节标题（与设置卡片其它分组标题样式一致）。
  Widget _label(String text) {
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .bodyMedium
          ?.copyWith(fontWeight: FontWeight.w500),
    );
  }

  /// Edge 模式音色选择：内置音色下拉（含空选项「跟随默认」；
  /// 当前值不在内置表时追加原值项，避免自由填写的 id 丢失显示）+
  /// 试听按钮（合成一句样例并播放）。
  ///
  /// 样式：弹层无阴影 + 圆角，输入框边框同步圆角。
  Widget _edgeVoiceField({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final items = <String>[...kEdgeTtsVoices.keys];
    if (value.isNotEmpty && !kEdgeTtsVoices.containsKey(value)) {
      items.insert(0, value);
    }
    final previewVoice = value.isEmpty ? kEdgeTtsDefaultVoice : value;
    final previewing = _previewingVoice == previewVoice;
    return Row(
      children: <Widget>[
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: value,
            elevation: 0,
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            decoration: InputDecoration(
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              ),
            ),
            items: <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(
                value: '',
                child: Text(l10n.httpTtsVoiceFollowDefault),
              ),
              for (final id in items)
                DropdownMenuItem<String>(
                  value: id,
                  child: Text(kEdgeTtsVoices[id] ?? id),
                ),
            ],
            onChanged: (v) => onChanged(v ?? ''),
          ),
        ),
        IconButton(
          tooltip: l10n.httpTtsVoicePreview,
          onPressed: () => _previewEdgeVoice(previewVoice),
          icon: previewing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  previewing
                      ? Icons.stop_rounded
                      : Icons.play_arrow_rounded,
                  color: previewing ? cs.primary : null,
                ),
        ),
      ],
    );
  }

  /// 试听播放器与当前试听音色（null = 无试听进行中）。
  Player? _previewPlayer;
  String? _previewingVoice;

  /// 停止并清理当前试听（切音色 / 离开页面时调用）。
  Future<void> _stopVoicePreview() async {
    final p = _previewPlayer;
    _previewPlayer = null;
    if (mounted) setState(() => _previewingVoice = null);
    if (p != null) {
      try {
        await p.dispose();
      } on Object {
        // 播放器已释放时忽略。
      }
    }
  }

  /// 试听音色：合成一句样例（走 Edge 在线合成 + 缓存），media_kit 播放。
  /// 再点同音色 = 停止；点其他音色 = 停旧播新。
  Future<void> _previewEdgeVoice(String voiceId) async {
    if (_previewingVoice == voiceId) {
      await _stopVoicePreview();
      return;
    }
    final l10n = AppLocalizations.of(context);
    await _stopVoicePreview();
    setState(() => _previewingVoice = voiceId);
    Player? player;
    try {
      final engine = EdgeTtsSynthesisEngine();
      final result = await engine.synthesize(
        text: l10n.httpTtsVoicePreviewSample,
        voice: voiceId,
        role: 'preview',
      );
      final bytes = result.bytes;
      if (bytes == null || !mounted) {
        setState(() => _previewingVoice = null);
        return;
      }
      final dir = await Directory.systemTemp.createTemp('nexhub_tts_preview_');
      final file = File('${dir.path}/preview.mp3');
      await file.writeAsBytes(bytes);
      player = Player();
      _previewPlayer = player;
      await player.open(Media(file.path));
      final done = Completer<void>();
      late final StreamSubscription<bool> sub;
      sub = player.stream.completed.listen((d) {
        if (d && !done.isCompleted) done.complete();
      });
      final errSub = player.stream.error.listen((_) {
        if (!done.isCompleted) done.complete();
      });
      await done.future.timeout(const Duration(seconds: 15), onTimeout: () {});
      await sub.cancel();
      await errSub.cancel();
      try {
        await dir.delete(recursive: true);
      } on Object {
        // 临时目录清理失败不影响功能。
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.httpTtsVoicePreviewFail)),
        );
      }
    } finally {
      if (player != null && _previewPlayer == player) {
        _previewPlayer = null;
      }
      try {
        await player?.dispose();
      } on Object {
        // 忽略重复释放。
      }
      if (mounted && _previewingVoice == voiceId) {
        setState(() => _previewingVoice = null);
      }
    }
  }

  /// 解析「角色=音色」多行文本为映射（忽略空行/无=行）。
  static Map<String, String> _parseVoiceMap(String raw) {
    final result = <String, String>{};
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      final role = trimmed.substring(0, eq).trim();
      final voice = trimmed.substring(eq + 1).trim();
      if (role.isNotEmpty && voice.isNotEmpty) {
        result[role] = voice;
      }
    }
    return result;
  }

  // ── 标签辅助函数 ──

  String _pageAnimLabel(AppLocalizations l10n, NovelPageAnimation anim) {
    return switch (anim) {
      NovelPageAnimation.none => l10n.novelAnimNone,
      NovelPageAnimation.slide => l10n.novelAnimSlide,
      NovelPageAnimation.scroll => l10n.novelAnimScroll,
      NovelPageAnimation.fade => l10n.novelAnimFade,
      NovelPageAnimation.cover => l10n.novelAnimCover,
      NovelPageAnimation.simulation => l10n.novelAnimSimulation,
    };
  }

  String _tapZoneInvertLabel(AppLocalizations l10n, TapZoneInvert inv) {
    return switch (inv) {
      TapZoneInvert.none => l10n.readerTapInvertNone,
      TapZoneInvert.leftRight => l10n.readerTapInvertLeftRight,
      TapZoneInvert.upDown => l10n.readerTapInvertUpDown,
      TapZoneInvert.all => l10n.readerTapInvertAll,
    };
  }

  String _bgPresetLabel(AppLocalizations l10n, int index) {
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

  String _themeFollowLabel(AppLocalizations l10n, NovelThemeFollow v) {
    return switch (v) {
      NovelThemeFollow.followApp => l10n.novelThemeFollowApp,
      NovelThemeFollow.alwaysDark => l10n.novelThemeFollowDark,
      NovelThemeFollow.alwaysLight => l10n.novelThemeFollowLight,
    };
  }

  String _titleAlignLabel(AppLocalizations l10n, NovelTitleAlign a) {
    return switch (a) {
      NovelTitleAlign.left => l10n.novelTitleAlignLeft,
      NovelTitleAlign.center => l10n.novelTitleAlignCenter,
      NovelTitleAlign.right => l10n.novelTitleAlignRight,
      NovelTitleAlign.hidden => l10n.novelTitleAlignHidden,
    };
  }

  String _hfContentLabel(AppLocalizations l10n, NovelHeaderFooterContent c) {
    return switch (c) {
      NovelHeaderFooterContent.none => l10n.novelHfNone,
      NovelHeaderFooterContent.time => l10n.novelHfTime,
      NovelHeaderFooterContent.battery => l10n.novelHfBattery,
      NovelHeaderFooterContent.chapterTitle => l10n.novelHfChapterTitle,
      NovelHeaderFooterContent.bookName => l10n.novelHfBookName,
      NovelHeaderFooterContent.pageNumber => l10n.novelHfPageNumber,
      NovelHeaderFooterContent.progressPercent => l10n.novelHfProgressPercent,
      NovelHeaderFooterContent.pageAndProgress => l10n.novelHfPageAndProgress,
      NovelHeaderFooterContent.timeAndBattery => l10n.novelHfTimeAndBattery,
      NovelHeaderFooterContent.bookPageNumber => l10n.novelHfBookPageNumber,
    };
  }

  String _tapLayoutLabel(AppLocalizations l10n, ReaderTapZoneLayout layout) {
    return switch (layout) {
      ReaderTapZoneLayout.lShape => l10n.readerTapLShape,
      ReaderTapZoneLayout.leftRight => l10n.readerTapLeftRight,
      ReaderTapZoneLayout.kindle => l10n.readerTapKindle,
      ReaderTapZoneLayout.bothSides => l10n.readerTapBothSides,
      ReaderTapZoneLayout.off => l10n.readerTapOff,
    };
  }

  String _bottomToolLabel(AppLocalizations l10n, NovelBottomTool tool) {
    return switch (tool) {
      NovelBottomTool.toc => l10n.toolToc,
      NovelBottomTool.prevChapter => l10n.toolPrevChapter,
      NovelBottomTool.nextChapter => l10n.toolNextChapter,
      NovelBottomTool.nightMode => l10n.toolNightMode,
      NovelBottomTool.autoPage => l10n.toolAutoPage,
      NovelBottomTool.settings => l10n.toolSettings,
      NovelBottomTool.bookmark => l10n.toolBookmark,
      NovelBottomTool.bookmarkList => l10n.toolBookmarkList,
      NovelBottomTool.search => l10n.toolSearch,
      NovelBottomTool.tts => l10n.toolTts,
    };
  }

  // ── 颜色选择器辅助 ──

  Future<int?> _pickColor(BuildContext context, Color initial, String title) {
    Color? picked;
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) => AppAlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: picked ?? initial,
              onColorChanged: (c) => setDialogState(() => picked = c),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop((picked ?? initial).toARGB32()),
              child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
            ),
          ],
        ),
      ),
    );
  }

  /// 颜色方块小部件。
  Widget _colorSwatch(Color color) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
    );
  }

  /// 颜色选择器行（带清除按钮）。
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
    return SettingsTile(
      title: title,
      subtitle: subtitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (current != null)
            IconButton(
              icon: const Icon(Icons.backspace_rounded),
              tooltip: clearTooltip,
              onPressed: onClear,
            ),
          GestureDetector(
            onTap: () async {
              final color = await _pickColor(
                context,
                current != null ? Color(current) : fallback,
                title,
              );
              if (color != null) onPicked(color);
            },
            child: _colorSwatch(current != null ? Color(current) : fallback),
          ),
        ],
      ),
    );
  }

  /// 字体文件选择器行。
  Widget _fontFileTile({
    required BuildContext context,
    required AppLocalizations l10n,
    required bool isTitle,
  }) {
    final currentPath = isTitle
        ? _settings.novelTitleCustomFontPath
        : _settings.novelCustomFontPath;
    final label = isTitle ? l10n.novelTitleFontFile : l10n.novelChooseFontFile;
    return SettingsTile(
      icon: Icons.font_download_rounded,
      title: label,
      subtitle: currentPath != null
          ? l10n.novelFontFileCurrent(currentPath.split(RegExp(r'[/\\]')).last)
          : null,
      trailing: currentPath != null
          ? IconButton(
              icon: const Icon(Icons.delete_rounded),
              tooltip: l10n.novelClearFontFile,
              onPressed: () => _update(
                isTitle
                    ? _settings.copyWith(novelTitleCustomFontPath: null)
                    : _settings.copyWith(novelCustomFontPath: null),
              ),
            )
          : null,
      onTap: () async {
        String? path;
        try {
          if (PlatformService.instance.isAndroid) {
            try {
              // ignore: depend_on_referenced_packages
              // await Permission.storage.request();
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
            isTitle
                ? NovelReaderPreferences.customLoadedTitleFontFamily
                : NovelReaderPreferences.customLoadedFontFamily,
            path,
          );
          _update(
            isTitle
                ? _settings.copyWith(novelTitleCustomFontPath: path)
                : _settings.copyWith(novelCustomFontPath: path),
          );
        } on Object {
          // 加载失败静默忽略
        }
      },
    );
  }

  /// 页眉/页脚单槽内容选择器。
  Widget _buildHfSlotPicker(
    String label,
    NovelHeaderFooterContent value,
    ValueChanged<NovelHeaderFooterContent> onChanged, {
    required BuildContext context,
    required AppLocalizations l10n,
  }) {
    return SettingsTile(
      title: label,
      trailing: Text(_hfContentLabel(l10n, value)),
      onTap: () async {
        final picked = await showDialog<NovelHeaderFooterContent>(
          context: context,
          builder: (ctx) => AppAlertDialog(
            title: Text(label),
            content: SingleChildScrollView(
              child: RadioGroup<NovelHeaderFooterContent>(
                groupValue: value,
                onChanged: (v) {
                  AppHaptics.tick(); // MD3「Selected」：单选选中 → tick。
                  Navigator.of(ctx).pop(v);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (final c in NovelHeaderFooterContent.values)
                      RadioListTile<NovelHeaderFooterContent>(
                        title: Text(_hfContentLabel(l10n, c)),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.novelReaderSettingsTitle),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.restore_rounded),
            tooltip: l10n.restoreDefault,
            onPressed: _confirmReset,
          ),
        ],
      ),
      body: _loaded
          ? SettingsAutoScroll(
              child: ListView(
                padding: context.pageInset(AppTokens.spaceLg),
                children: <Widget>[
                  // ── 常用设置（置顶快捷项，与阅读器内联面板对齐）──
                  SettingsCard(
                    key: const ValueKey<String>('novel.common'),
                    title: l10n.novelSettingsCommon,
                    initiallyExpanded: false,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.22),
                    children: <Widget>[
                      // 字号
                      SettingsSliderTile(
                        label: l10n.novelFontSize,
                        value: _settings.novelFontSize,
                        min: 12,
                        max: 32,
                        divisions: 20,
                        display:
                            '${_settings.novelFontSize.toStringAsFixed(0)} sp',
                        onChanged: (v) =>
                            _update(_settings.copyWith(novelFontSize: v)),
                      ),
                      // 亮度
                      SettingsSliderTile(
                        label: l10n.novelBrightness,
                        value: _settings.novelBrightness,
                        min: 0.0,
                        max: 1.0,
                        divisions: 20,
                        display:
                            '${(_settings.novelBrightness * 100).round()}%',
                        onChanged: (v) =>
                            _update(_settings.copyWith(novelBrightness: v)),
                      ),
                      // 背景预设
                      Text(l10n.readerBackground,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500)),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          for (int i = 0;
                              i < ReaderTokens.bgPresets.length;
                              i++)
                            AppValuePulse(
                              trigger: _settings.novelBgPresetIndex == i &&
                                  _settings.novelCustomBgColor == null,
                              from: 0.9,
                              child: ChoiceChip(
                                label: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Container(
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: ReaderTokens.bgPresets[i],
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
                                    Text(_bgPresetLabel(l10n, i)),
                                  ],
                                ),
                                selected: _settings.novelBgPresetIndex == i &&
                                    _settings.novelCustomBgColor == null,
                                onSelected: (_) {
                                  AppHaptics.selectionClick();
                                  _update(
                                    _settings.copyWith(
                                      novelBgPresetIndex: i,
                                      novelCustomBgColor: null,
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                      // 夜间模式跟随
                      Text(l10n.nightMode,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500)),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          for (final f in NovelThemeFollow.values)
                            AppValuePulse(
                              trigger: NovelThemeFollow.values.firstWhere(
                                    (e) => e.name == _settings.novelThemeFollow,
                                    orElse: () => NovelThemeFollow.followApp,
                                  ) ==
                                  f,
                              from: 0.9,
                              child: ChoiceChip(
                                label: Text(_themeFollowLabel(l10n, f)),
                                selected: NovelThemeFollow.values.firstWhere(
                                      (e) =>
                                          e.name == _settings.novelThemeFollow,
                                      orElse: () => NovelThemeFollow.followApp,
                                    ) ==
                                    f,
                                onSelected: (_) {
                                  AppHaptics.selectionClick();
                                  _update(_settings.copyWith(
                                      novelThemeFollow: f.name));
                                },
                              ),
                            ),
                        ],
                      ),
                      // 翻页动画
                      Text(l10n.novelPageAnimation,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500)),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          for (final anim in NovelPageAnimation.values)
                            AppValuePulse(
                              trigger: _settings.novelPageAnimation == anim,
                              from: 0.9,
                              child: ChoiceChip(
                                label: Text(_pageAnimLabel(l10n, anim)),
                                selected: _settings.novelPageAnimation == anim,
                                onSelected: (_) {
                                  AppHaptics.selectionClick();
                                  _update(_settings.copyWith(
                                      novelPageAnimation: anim));
                                },
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),

                  // ── 1. 阅读基础 ──
                  SettingsCard(
                    key: const ValueKey<String>('novel.text'),
                    initiallyExpanded: false,
                    index: 0,
                    title: l10n.novelSectionText,
                    children: <Widget>[
                      SettingsSliderTile(
                        label: l10n.novelFontSize,
                        value: _settings.novelFontSize,
                        min: 12,
                        max: 32,
                        divisions: 20,
                        display:
                            '${_settings.novelFontSize.toStringAsFixed(0)} sp',
                        onChanged: (v) =>
                            _update(_settings.copyWith(novelFontSize: v)),
                      ),
                      SettingsSliderTile(
                        label: l10n.novelLineHeight,
                        value: _settings.novelLineHeight,
                        min: 1.2,
                        max: 3.0,
                        divisions: 18,
                        display: _settings.novelLineHeight.toStringAsFixed(1),
                        onChanged: (v) =>
                            _update(_settings.copyWith(novelLineHeight: v)),
                      ),
                      SettingsSliderTile(
                        label: l10n.novelParagraphSpacing,
                        value: _settings.novelParagraphSpacing,
                        min: 4,
                        max: 48,
                        divisions: 22,
                        display:
                            '${_settings.novelParagraphSpacing.toStringAsFixed(0)} px',
                        onChanged: (v) => _update(
                            _settings.copyWith(novelParagraphSpacing: v)),
                      ),
                      SettingsSliderTile(
                        label: l10n.novelMargin,
                        value: _settings.novelMargin,
                        min: 8,
                        max: 64,
                        divisions: 28,
                        display:
                            '${_settings.novelMargin.toStringAsFixed(0)} px',
                        onChanged: (v) =>
                            _update(_settings.copyWith(novelMargin: v)),
                      ),
                      SettingsSliderTile(
                        label: l10n.novelLetterSpacing,
                        value: _settings.novelLetterSpacing,
                        min: 0,
                        max: 8,
                        divisions: 16,
                        display:
                            '${_settings.novelLetterSpacing.toStringAsFixed(0)} px',
                        onChanged: (v) =>
                            _update(_settings.copyWith(novelLetterSpacing: v)),
                      ),
                    ],
                  ),

                  // ── 2. 字体样式 ──
                  SettingsCard(
                    key: const ValueKey<String>('novel.font'),
                    initiallyExpanded: false,
                    index: 1,
                    title: l10n.novelSectionFont,
                    children: <Widget>[
                      Text(l10n.novelFontStyle,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500)),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          FilterChip(
                            label: Text(l10n.fontBold),
                            // 加粗是唯一开关：开启后按字重滑块渲染，关闭即恢复
                            // 默认字重，不再有第二个可覆盖它的字重字段。
                            selected: _settings.novelFontBold,
                            onSelected: (v) {
                              AppHaptics.selectionClick();
                              _update(_settings.copyWith(novelFontBold: v));
                            },
                          ),
                          FilterChip(
                            label: Text(l10n.fontItalic),
                            selected: _settings.novelFontItalic,
                            onSelected: (v) {
                              AppHaptics.selectionClick();
                              _update(_settings.copyWith(novelFontItalic: v));
                            },
                          ),
                          FilterChip(
                            label: Text(l10n.fontUnderline),
                            selected: _settings.novelFontUnderline,
                            onSelected: (v) {
                              AppHaptics.selectionClick();
                              _update(
                                  _settings.copyWith(novelFontUnderline: v));
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      // 正文字体族（与阅读器面板对齐：系统 / 衬线 / 等宽）
                      Text(l10n.customFont,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500)),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          AppValuePulse(
                            trigger: _settings.novelFontFamily == null,
                            from: 0.9,
                            child: ChoiceChip(
                              label: Text(l10n.fontSystem),
                              selected: _settings.novelFontFamily == null,
                              onSelected: (_) {
                                AppHaptics.selectionClick();
                                _update(
                                    _settings.copyWith(novelFontFamily: null));
                              },
                            ),
                          ),
                          AppValuePulse(
                            trigger: _settings.novelFontFamily == 'serif',
                            from: 0.9,
                            child: ChoiceChip(
                              label: Text(l10n.fontSerif),
                              selected: _settings.novelFontFamily == 'serif',
                              onSelected: (_) {
                                AppHaptics.selectionClick();
                                _update(_settings.copyWith(
                                    novelFontFamily: 'serif'));
                              },
                            ),
                          ),
                          AppValuePulse(
                            trigger: _settings.novelFontFamily == 'monospace',
                            from: 0.9,
                            child: ChoiceChip(
                              label: Text(l10n.fontMonospace),
                              selected:
                                  _settings.novelFontFamily == 'monospace',
                              onSelected: (_) {
                                AppHaptics.selectionClick();
                                _update(_settings.copyWith(
                                    novelFontFamily: 'monospace'));
                              },
                            ),
                          ),
                        ],
                      ),
                      _fontFileTile(
                        context: context,
                        l10n: l10n,
                        isTitle: false,
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      // 加粗字重滑块（100–900）：仅加粗开启时显示并生效。
                      // divisions 取 8 使滑块停在 100/200/.../900 整百档位，
                      // 与 resolveBodyTextStyle 的 switch 精确匹配，避免 150/250 等
                      // 中间值落到 default 的 w900 导致字重忽粗忽细。
                      SettingsExpand(
                        visible: _settings.novelFontBold,
                        child: SettingsSliderTile(
                          key: const ValueKey<String>('novel.fontWeightFine'),
                          label: l10n.novelFontWeightFine,
                          value: _settings.novelFontWeightValue.toDouble(),
                          min: 100,
                          max: 900,
                          divisions: 8,
                          display: '${_settings.novelFontWeightValue}',
                          onChanged: (v) => _update(_settings.copyWith(
                              novelFontWeightValue: v.round())),
                        ),
                      ),
                    ],
                  ),

                  // ── 2b. 排版增强──
                  SettingsCard(
                    key: const ValueKey<String>('novel.typography'),
                    initiallyExpanded: false,
                    index: 1,
                    title: l10n.novelTypographyGroup,
                    children: <Widget>[
                      // 对齐方式。
                      Text(l10n.novelTextAlignMode,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500)),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          for (final m in NovelTextAlignMode.values)
                            AppValuePulse(
                              trigger: _settings.novelTextAlignMode == m.name,
                              from: 0.9,
                              child: ChoiceChip(
                                label: Text(m == NovelTextAlignMode.justify
                                    ? l10n.novelTextAlignJustify
                                    : l10n.novelTextAlignStart),
                                selected:
                                    _settings.novelTextAlignMode == m.name,
                                onSelected: (_) {
                                  AppHaptics.selectionClick();
                                  _update(_settings.copyWith(
                                      novelTextAlignMode: m.name));
                                },
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      // 中文断行模式。
                      Text(l10n.novelLineBreakMode,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500)),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          for (final m in NovelLineBreakMode.values)
                            AppValuePulse(
                              trigger: _settings.novelLineBreakMode == m.name,
                              from: 0.9,
                              child: ChoiceChip(
                                label: Text(m == NovelLineBreakMode.cjkStrict
                                    ? l10n.novelLineBreakCjkStrict
                                    : l10n.novelLineBreakStandard),
                                selected:
                                    _settings.novelLineBreakMode == m.name,
                                onSelected: (_) {
                                  AppHaptics.selectionClick();
                                  _update(_settings.copyWith(
                                      novelLineBreakMode: m.name));
                                },
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      // 下划线样式。
                      Text(l10n.novelUnderlineStyle,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500)),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          for (final s in NovelUnderlineStyle.values)
                            AppValuePulse(
                              trigger: _settings.novelUnderlineStyle == s.name,
                              from: 0.9,
                              child: ChoiceChip(
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
                                selected:
                                    _settings.novelUnderlineStyle == s.name,
                                onSelected: (_) {
                                  AppHaptics.selectionClick();
                                  _update(_settings.copyWith(
                                      novelUnderlineStyle: s.name));
                                },
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      // 滚动模式图文样式（插图展示模式 + 水平对齐）。
                      Text(l10n.novelScrollImageMode,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500)),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          for (final m in NovelScrollImageMode.values)
                            AppValuePulse(
                              trigger: _settings.novelScrollImageMode == m.name,
                              from: 0.9,
                              child: ChoiceChip(
                                label: Text(m == NovelScrollImageMode.card
                                    ? l10n.novelScrollImageModeCard
                                    : l10n.novelScrollImageModeBanner),
                                selected:
                                    _settings.novelScrollImageMode == m.name,
                                onSelected: (_) {
                                  AppHaptics.selectionClick();
                                  _update(_settings.copyWith(
                                      novelScrollImageMode: m.name));
                                },
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      // 滚动插图水平对齐（仅 card 模式视觉生效）。
                      Text(l10n.novelScrollImageAlign,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500)),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          for (final a in NovelScrollImageAlign.values)
                            AppValuePulse(
                              trigger:
                                  _settings.novelScrollImageAlign == a.name,
                              from: 0.9,
                              child: ChoiceChip(
                                label: Text(switch (a) {
                                  NovelScrollImageAlign.left =>
                                    l10n.novelScrollImageAlignLeft,
                                  NovelScrollImageAlign.right =>
                                    l10n.novelScrollImageAlignRight,
                                  NovelScrollImageAlign.center =>
                                    l10n.novelScrollImageAlignCenter,
                                }),
                                selected:
                                    _settings.novelScrollImageAlign == a.name,
                                onSelected: (_) {
                                  AppHaptics.selectionClick();
                                  _update(_settings.copyWith(
                                      novelScrollImageAlign: a.name));
                                },
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),

                  // ── 3. 颜色与背景 ──
                  SettingsCard(
                    key: const ValueKey<String>('novel.color'),
                    initiallyExpanded: false,
                    index: 2,
                    title: l10n.novelSectionColor,
                    children: <Widget>[
                      // 夜间模式跟随
                      Text(l10n.nightMode,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500)),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          for (final f in NovelThemeFollow.values)
                            ChoiceChip(
                              label: Text(_themeFollowLabel(l10n, f)),
                              selected: NovelThemeFollow.values.firstWhere(
                                    (e) => e.name == _settings.novelThemeFollow,
                                    orElse: () => NovelThemeFollow.followApp,
                                  ) ==
                                  f,
                              onSelected: (_) {
                                AppHaptics.selectionClick();
                                _update(_settings.copyWith(
                                    novelThemeFollow: f.name));
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      // 背景预设
                      Text(l10n.readerBackground,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500)),
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
                                      color: ReaderTokens.bgPresets[i],
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
                                  Text(_bgPresetLabel(l10n, i)),
                                ],
                              ),
                              selected: _settings.novelBgPresetIndex == i &&
                                  _settings.novelCustomBgColor == null,
                              onSelected: (_) {
                                AppHaptics.selectionClick();
                                _update(
                                  _settings.copyWith(
                                    novelBgPresetIndex: i,
                                    novelCustomBgColor: null,
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      // 自定义背景色
                      _colorTile(
                        context: context,
                        l10n: l10n,
                        title: l10n.customBgColor,
                        current: _settings.novelCustomBgColor,
                        fallback: ReaderTokens.bgPresets[_settings
                            .novelBgPresetIndex
                            .clamp(0, ReaderTokens.bgPresets.length - 1)],
                        onPicked: (c) =>
                            _update(_settings.copyWith(novelCustomBgColor: c)),
                        onClear: () => _update(
                            _settings.copyWith(novelCustomBgColor: null)),
                        clearTooltip: l10n.novelBgWhite,
                      ),
                      // 正文颜色
                      _colorTile(
                        context: context,
                        l10n: l10n,
                        title: l10n.novelTextColor,
                        subtitle: _settings.novelCustomTextColor == null
                            ? l10n.novelTextColorFollowBg
                            : null,
                        current: _settings.novelCustomTextColor,
                        fallback: const Color(0xFF1A1A1A),
                        onPicked: (c) => _update(
                            _settings.copyWith(novelCustomTextColor: c)),
                        onClear: () => _update(
                            _settings.copyWith(novelCustomTextColor: null)),
                        clearTooltip: l10n.novelTextColorFollowBg,
                      ),
                      // 强调色
                      _colorTile(
                        context: context,
                        l10n: l10n,
                        title: l10n.novelEmphasisColor,
                        subtitle: _settings.novelEmphasisColor == null
                            ? l10n.novelEmphasisColorAuto
                            : null,
                        current: _settings.novelEmphasisColor,
                        fallback: ReaderTokens.emphasisDefault,
                        onPicked: (c) =>
                            _update(_settings.copyWith(novelEmphasisColor: c)),
                        onClear: () => _update(
                            _settings.copyWith(novelEmphasisColor: null)),
                        clearTooltip: l10n.novelEmphasisColorAuto,
                      ),
                    ],
                  ),

                  // ── 4. 阴影与下划线 ──
                  SettingsCard(
                    key: const ValueKey<String>('novel.shadowUnderline'),
                    initiallyExpanded: false,
                    index: 3,
                    title: l10n.novelSectionShadowUnderline,
                    children: <Widget>[
                      SettingsSwitchTile(
                        title: l10n.novelTextShadow,
                        value: _settings.novelShadow,
                        onChanged: (v) =>
                            _update(_settings.copyWith(novelShadow: v)),
                      ),
                      SettingsExpand(
                        visible: _settings.novelShadow,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _colorTile(
                              context: context,
                              l10n: l10n,
                              title: l10n.novelShadowColor,
                              subtitle: _settings.novelShadowColor == null
                                  ? l10n.novelShadowColorAuto
                                  : null,
                              current: _settings.novelShadowColor,
                              fallback: const Color(0x4D000000),
                              onPicked: (c) => _update(
                                  _settings.copyWith(novelShadowColor: c)),
                              onClear: () => _update(
                                  _settings.copyWith(novelShadowColor: null)),
                              clearTooltip: l10n.novelShadowColorAuto,
                            ),
                            SettingsSliderTile(
                              label: l10n.novelShadowBlur,
                              value: _settings.novelShadowBlur,
                              min: 0,
                              max: 8,
                              divisions: 32,
                              display:
                                  '${_settings.novelShadowBlur.toStringAsFixed(1)} px',
                              onChanged: (v) => _update(
                                  _settings.copyWith(novelShadowBlur: v)),
                            ),
                            SettingsSliderTile(
                              label: l10n.novelShadowOffsetX,
                              value: _settings.novelShadowOffsetX,
                              min: -8,
                              max: 8,
                              divisions: 32,
                              display:
                                  '${_settings.novelShadowOffsetX.toStringAsFixed(1)} px',
                              onChanged: (v) => _update(
                                  _settings.copyWith(novelShadowOffsetX: v)),
                            ),
                            SettingsSliderTile(
                              label: l10n.novelShadowOffsetY,
                              value: _settings.novelShadowOffsetY,
                              min: -8,
                              max: 8,
                              divisions: 32,
                              display:
                                  '${_settings.novelShadowOffsetY.toStringAsFixed(1)} px',
                              onChanged: (v) => _update(
                                  _settings.copyWith(novelShadowOffsetY: v)),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      const SizedBox(height: AppTokens.spaceSm),
                      SettingsExpand(
                        visible: _settings.novelFontUnderline,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _colorTile(
                              context: context,
                              l10n: l10n,
                              title: l10n.novelUnderlineColor,
                              subtitle: _settings.novelUnderlineColor == null
                                  ? l10n.novelUnderlineColorAuto
                                  : null,
                              current: _settings.novelUnderlineColor,
                              fallback: const Color(0xFF1A1A1A),
                              onPicked: (c) => _update(
                                  _settings.copyWith(novelUnderlineColor: c)),
                              onClear: () => _update(_settings.copyWith(
                                  novelUnderlineColor: null)),
                              clearTooltip: l10n.novelUnderlineColorAuto,
                            ),
                            SettingsSliderTile(
                              label: l10n.novelUnderlineThickness,
                              value: _settings.novelUnderlineThickness,
                              min: 0.5,
                              max: 6,
                              divisions: 22,
                              display:
                                  '${_settings.novelUnderlineThickness.toStringAsFixed(1)} px',
                              onChanged: (v) => _update(_settings.copyWith(
                                  novelUnderlineThickness: v)),
                            ),
                            // 「虚线」开关直接改写下划线样式：勾选切到 dashed、取消回到
                            // solid。旧 bool 字段 underlineDashed 已是死副本（渲染只认
                            // style），仅保留兼容读取，不再写入。
                            SettingsSwitchTile(
                              title: l10n.novelUnderlineDashed,
                              value: _settings.novelUnderlineStyle ==
                                  NovelUnderlineStyle.dashed.name,
                              onChanged: (v) => _update(_settings.copyWith(
                                  novelUnderlineStyle: v
                                      ? NovelUnderlineStyle.dashed.name
                                      : NovelUnderlineStyle.solid.name)),
                            ),
                            SettingsExpand(
                              visible: _settings.novelUnderlineStyle ==
                                  NovelUnderlineStyle.dashed.name,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  SettingsSliderTile(
                                    label: l10n.novelUnderlineDashLength,
                                    value: _settings.novelUnderlineDashLength,
                                    min: 1,
                                    max: 16,
                                    divisions: 30,
                                    display:
                                        '${_settings.novelUnderlineDashLength.toStringAsFixed(0)} px',
                                    onChanged: (v) => _update(_settings
                                        .copyWith(novelUnderlineDashLength: v)),
                                  ),
                                  SettingsSliderTile(
                                    label: l10n.novelUnderlineDashGap,
                                    value: _settings.novelUnderlineDashGap,
                                    min: 0,
                                    max: 16,
                                    divisions: 32,
                                    display:
                                        '${_settings.novelUnderlineDashGap.toStringAsFixed(0)} px',
                                    onChanged: (v) => _update(_settings
                                        .copyWith(novelUnderlineDashGap: v)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // ── 5. 章节标题 ──
                  SettingsCard(
                    key: const ValueKey<String>('novel.title'),
                    initiallyExpanded: false,
                    index: 4,
                    title: l10n.novelSectionTitle,
                    children: <Widget>[
                      SettingsSwitchTile(
                        title: l10n.novelShowChapterTitle,
                        value: _settings.novelShowChapterTitleInBody,
                        onChanged: (v) => _update(
                            _settings.copyWith(novelShowChapterTitleInBody: v)),
                      ),
                      SettingsExpand(
                        visible: _settings.novelShowChapterTitleInBody,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(l10n.novelTitlePosition,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w500)),
                            const SizedBox(height: AppTokens.spaceXs),
                            Wrap(
                              spacing: AppTokens.spaceSm,
                              runSpacing: AppTokens.spaceSm,
                              children: <Widget>[
                                for (final a in NovelTitleAlign.values)
                                  ChoiceChip(
                                    label: Text(_titleAlignLabel(l10n, a)),
                                    selected: NovelTitleAlign.values.firstWhere(
                                          (e) =>
                                              e.name ==
                                              _settings.novelTitleAlign,
                                          orElse: () => NovelTitleAlign.left,
                                        ) ==
                                        a,
                                    onSelected: (_) {
                                      AppHaptics.selectionClick();
                                      _update(_settings.copyWith(
                                          novelTitleAlign: a.name));
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: AppTokens.spaceMd),
                            SettingsSliderTile(
                              label: l10n.novelTitleFontScale,
                              value: _settings.novelTitleFontScale,
                              min: 1.0,
                              max: 2.5,
                              divisions: 15,
                              display:
                                  '${_settings.novelTitleFontScale.toStringAsFixed(1)}x',
                              onChanged: (v) => _update(
                                  _settings.copyWith(novelTitleFontScale: v)),
                            ),
                            SettingsSwitchTile(
                              title: l10n.novelTitleBold,
                              value: _settings.novelTitleBold,
                              onChanged: (v) => _update(
                                  _settings.copyWith(novelTitleBold: v)),
                            ),
                            _fontFileTile(
                              context: context,
                              l10n: l10n,
                              isTitle: true,
                            ),
                            const Divider(height: 1),
                            const SizedBox(height: AppTokens.spaceSm),
                            SettingsSwitchTile(
                              title: l10n.novelTitleSegmentMode,
                              value: _settings.novelTitleSegmentMode,
                              onChanged: (v) => _update(
                                  _settings.copyWith(novelTitleSegmentMode: v)),
                            ),
                            SettingsExpand(
                              visible: _settings.novelTitleSegmentMode,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  SettingsSliderTile(
                                    label: l10n.novelTitleSubScale,
                                    value: _settings.novelTitleSubScale,
                                    min: 0.4,
                                    max: 1.5,
                                    divisions: 22,
                                    display:
                                        '${_settings.novelTitleSubScale.toStringAsFixed(1)}x',
                                    onChanged: (v) => _update(_settings
                                        .copyWith(novelTitleSubScale: v)),
                                  ),
                                  SettingsSliderTile(
                                    label: l10n.novelTitleSegmentSpacing,
                                    value: _settings.novelTitleSegmentSpacing,
                                    min: 0,
                                    max: 32,
                                    divisions: 32,
                                    display:
                                        '${_settings.novelTitleSegmentSpacing.toStringAsFixed(0)} px',
                                    onChanged: (v) => _update(_settings
                                        .copyWith(novelTitleSegmentSpacing: v)),
                                  ),
                                  SettingsSliderTile(
                                    label: l10n.novelTitleSubLineSpacing,
                                    value: _settings.novelTitleSubLineSpacing,
                                    min: 1.0,
                                    max: 2.5,
                                    divisions: 30,
                                    display: _settings.novelTitleSubLineSpacing
                                        .toStringAsFixed(1),
                                    onChanged: (v) => _update(_settings
                                        .copyWith(novelTitleSubLineSpacing: v)),
                                  ),
                                  SettingsSliderTile(
                                    label: l10n.novelTitleTopMargin,
                                    value: _settings.novelTitleTopMargin,
                                    min: 0,
                                    max: 48,
                                    divisions: 48,
                                    display:
                                        '${_settings.novelTitleTopMargin.toStringAsFixed(0)} px',
                                    onChanged: (v) => _update(_settings
                                        .copyWith(novelTitleTopMargin: v)),
                                  ),
                                  SettingsSliderTile(
                                    label: l10n.novelTitleBottomMargin,
                                    value: _settings.novelTitleBottomMargin,
                                    min: 0,
                                    max: 48,
                                    divisions: 48,
                                    display:
                                        '${_settings.novelTitleBottomMargin.toStringAsFixed(0)} px',
                                    onChanged: (v) => _update(_settings
                                        .copyWith(novelTitleBottomMargin: v)),
                                  ),
                                ],
                              ),
                            ),
                            _colorTile(
                              context: context,
                              l10n: l10n,
                              title: l10n.novelTitleColor,
                              subtitle: _settings.novelTitleColor == null
                                  ? l10n.novelTitleColorAuto
                                  : null,
                              current: _settings.novelTitleColor,
                              fallback: ReaderTokens.emphasisDefault,
                              onPicked: (c) => _update(
                                  _settings.copyWith(novelTitleColor: c)),
                              onClear: () => _update(
                                  _settings.copyWith(novelTitleColor: null)),
                              clearTooltip: l10n.novelTitleColorAuto,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // ── 6. 页眉页脚 ──
                  SettingsCard(
                    key: const ValueKey<String>('novel.headerFooter'),
                    initiallyExpanded: false,
                    index: 5,
                    title: l10n.novelSectionHeaderFooter,
                    children: <Widget>[
                      _buildHfSlotPicker(
                        l10n.novelHeaderLeft,
                        NovelHeaderFooterContent.values.firstWhere(
                          (e) => e.name == _settings.novelHeaderLeft,
                          orElse: () => NovelHeaderFooterContent.bookName,
                        ),
                        (v) => _update(
                            _settings.copyWith(novelHeaderLeft: v.name)),
                        context: context,
                        l10n: l10n,
                      ),
                      _buildHfSlotPicker(
                        l10n.novelHeaderCenter,
                        NovelHeaderFooterContent.values.firstWhere(
                          (e) => e.name == _settings.novelHeaderCenter,
                          orElse: () => NovelHeaderFooterContent.none,
                        ),
                        (v) => _update(
                            _settings.copyWith(novelHeaderCenter: v.name)),
                        context: context,
                        l10n: l10n,
                      ),
                      _buildHfSlotPicker(
                        l10n.novelHeaderRight,
                        NovelHeaderFooterContent.values.firstWhere(
                          (e) => e.name == _settings.novelHeaderRight,
                          orElse: () => NovelHeaderFooterContent.time,
                        ),
                        (v) => _update(
                            _settings.copyWith(novelHeaderRight: v.name)),
                        context: context,
                        l10n: l10n,
                      ),
                      const Divider(height: 1),
                      const SizedBox(height: AppTokens.spaceSm),
                      _buildHfSlotPicker(
                        l10n.novelFooterLeft,
                        NovelHeaderFooterContent.values.firstWhere(
                          (e) => e.name == _settings.novelFooterLeft,
                          orElse: () => NovelHeaderFooterContent.chapterTitle,
                        ),
                        (v) => _update(
                            _settings.copyWith(novelFooterLeft: v.name)),
                        context: context,
                        l10n: l10n,
                      ),
                      _buildHfSlotPicker(
                        l10n.novelFooterCenter,
                        NovelHeaderFooterContent.values.firstWhere(
                          (e) => e.name == _settings.novelFooterCenter,
                          orElse: () => NovelHeaderFooterContent.none,
                        ),
                        (v) => _update(
                            _settings.copyWith(novelFooterCenter: v.name)),
                        context: context,
                        l10n: l10n,
                      ),
                      _buildHfSlotPicker(
                        l10n.novelFooterRight,
                        NovelHeaderFooterContent.values.firstWhere(
                          (e) => e.name == _settings.novelFooterRight,
                          orElse: () => NovelHeaderFooterContent.pageNumber,
                        ),
                        (v) => _update(
                            _settings.copyWith(novelFooterRight: v.name)),
                        context: context,
                        l10n: l10n,
                      ),
                      const Divider(height: 1),
                      const SizedBox(height: AppTokens.spaceSm),
                      _colorTile(
                        context: context,
                        l10n: l10n,
                        title: l10n.novelHeaderFooterColor,
                        subtitle: _settings.novelHeaderFooterColor == null
                            ? l10n.novelTextColorFollowBg
                            : null,
                        current: _settings.novelHeaderFooterColor,
                        fallback: const Color(0xFF1A1A1A),
                        onPicked: (c) => _update(
                            _settings.copyWith(novelHeaderFooterColor: c)),
                        onClear: () => _update(
                            _settings.copyWith(novelHeaderFooterColor: null)),
                        clearTooltip: l10n.novelTextColorFollowBg,
                      ),
                      SettingsSliderTile(
                        label: l10n.novelHeaderFooterMargin,
                        value: _settings.novelHeaderFooterMargin,
                        min: 0,
                        max: 48,
                        divisions: 48,
                        display:
                            '${_settings.novelHeaderFooterMargin.toStringAsFixed(0)} px',
                        onChanged: (v) => _update(
                            _settings.copyWith(novelHeaderFooterMargin: v)),
                      ),
                    ],
                  ),

                  // ── 7. 翻页与手势 ──
                  SettingsCard(
                    key: const ValueKey<String>('novel.page'),
                    initiallyExpanded: false,
                    index: 6,
                    title: l10n.novelSectionPage,
                    children: <Widget>[
                      // 双页模式：翻页模式下宽屏左右并排两页。
                      SettingsSwitchTile(
                        key: const ValueKey<String>('novel.twoPage'),
                        title: l10n.novelTwoPageMode,
                        subtitle: l10n.novelTwoPageModeDesc,
                        value: _settings.novelTwoPageMode,
                        onChanged: (v) =>
                            _update(_settings.copyWith(novelTwoPageMode: v)),
                      ),
                      // 亮度
                      SettingsSliderTile(
                        label: l10n.novelBrightness,
                        value: _settings.novelBrightness,
                        min: 0.0,
                        max: 1.0,
                        divisions: 20,
                        display:
                            '${(_settings.novelBrightness * 100).round()}%',
                        onChanged: (v) =>
                            _update(_settings.copyWith(novelBrightness: v)),
                      ),
                      // 翻页动画（胶囊式快捷选择）
                      Text(l10n.novelPageAnimation,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500)),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          for (final anim in NovelPageAnimation.values)
                            ChoiceChip(
                              label: Text(_pageAnimLabel(l10n, anim)),
                              selected: _settings.novelPageAnimation == anim,
                              onSelected: (_) {
                                AppHaptics.selectionClick();
                                _update(_settings.copyWith(
                                    novelPageAnimation: anim));
                              },
                            ),
                        ],
                      ),
                      // 音量键翻页（Android / 鸿蒙生效）
                      SettingsSwitchTile(
                        key: const ValueKey<String>('comic.volumePageTurn'),
                        title: l10n.readerVolumeKeyPageTurn,
                        value: _settings.novelVolumeKeyPageTurn,
                        onChanged: (v) => _update(
                            _settings.copyWith(novelVolumeKeyPageTurn: v)),
                      ),
                      // 点击分区布局（胶囊式快捷选择）
                      Text(l10n.readerTapZone,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500)),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          for (final layout in ReaderTapZoneLayout.values)
                            ChoiceChip(
                              label: Text(_tapLayoutLabel(l10n, layout)),
                              selected: ReaderTapZoneLayout.values.firstWhere(
                                    (e) =>
                                        e.name == _settings.novelTapZoneLayout,
                                    orElse: () => ReaderTapZoneLayout.lShape,
                                  ) ==
                                  layout,
                              onSelected: (_) {
                                AppHaptics.selectionClick();
                                _update(_settings.copyWith(
                                    novelTapZoneLayout: layout.name));
                              },
                            ),
                        ],
                      ),
                      Row(
                        children: <Widget>[
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => _showTapZonePreview(context, l10n),
                            icon:
                                const Icon(Icons.visibility_rounded, size: 18),
                            label: Text(l10n.tapZonePreview),
                          ),
                        ],
                      ),
                      // 点击区域翻转
                      SettingsChoiceChips<TapZoneInvert>(
                        title: l10n.readerTapInvert,
                        selected: _settings.novelTapZoneInvert,
                        onSelected: (v) =>
                            _update(_settings.copyWith(novelTapZoneInvert: v)),
                        options: TapZoneInvert.values
                            .map((v) => SettingsChoiceChipData<TapZoneInvert>(
                                  value: v,
                                  label: _tapZoneInvertLabel(l10n, v),
                                ))
                            .toList(),
                      ),
                      // 自动翻页间隔
                      Text(l10n.autoPageInterval,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500)),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          for (final v in const <int>[0, 3, 5, 10, 15])
                            ChoiceChip(
                              label: Text(v == 0 ? l10n.autoPageOff : '${v}s'),
                              selected: _settings.novelAutoPageInterval == v,
                              onSelected: (_) {
                                AppHaptics.selectionClick();
                                _update(_settings.copyWith(
                                    novelAutoPageInterval: v));
                              },
                            ),
                        ],
                      ),
                      // 平滑自动翻页：按像素/过渡进度连续推进整页。
                      SettingsSwitchTile(
                        key: const ValueKey<String>('novel.autoPageSmooth'),
                        title: l10n.autoPageSmooth,
                        value: _settings.novelAutoPageSmooth,
                        onChanged: (v) =>
                            _update(_settings.copyWith(novelAutoPageSmooth: v)),
                      ),
                      const Divider(height: 1),
                      const SizedBox(height: AppTokens.spaceSm),
                      // 鼠标滚轮翻页方向反转（仅翻页模式生效；滚动模式由底层滚动接管）
                      SettingsSwitchTile(
                        key: const ValueKey<String>('novel.wheelInverted'),
                        title: l10n.novelWheelInverted,
                        value: _settings.novelScrollWheelInverted,
                        onChanged: (v) => _update(
                            _settings.copyWith(novelScrollWheelInverted: v)),
                      ),
                    ],
                  ),

                  // ── 8. 底部工具栏 ──
                  SettingsCard(
                    key: const ValueKey<String>('novel.toolbar'),
                    initiallyExpanded: false,
                    index: 7,
                    title: l10n.novelSectionToolbar,
                    children: <Widget>[
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          for (final tool in NovelBottomTool.values)
                            FilterChip(
                              label: Text(_bottomToolLabel(l10n, tool)),
                              selected: _settings.novelBottomToolbarSlots
                                  .contains(tool.name),
                              onSelected: (selected) {
                                AppHaptics.selectionClick();
                                final slots = List<String>.from(
                                    _settings.novelBottomToolbarSlots);
                                if (selected) {
                                  slots.add(tool.name);
                                } else {
                                  slots.remove(tool.name);
                                }
                                _update(_settings.copyWith(
                                    novelBottomToolbarSlots: slots));
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      TextButton.icon(
                        icon: const Icon(Icons.restore_rounded),
                        label: Text(l10n.restoreDefault),
                        onPressed: () {
                          _update(_settings.copyWith(
                            novelBottomToolbarSlots: NovelBottomTool.defaults
                                .map((t) => t.name)
                                .toList(),
                          ));
                        },
                      ),
                    ],
                  ),

                  // ── 9. 朗读设置 ──
                  SettingsCard(
                    key: const ValueKey<String>('novel.tts'),
                    initiallyExpanded: false,
                    index: 8,
                    title: l10n.novelSectionTts,
                    children: <Widget>[
                      SettingsSliderTile(
                        label: l10n.ttsRate,
                        value: _settings.novelTtsSpeechRate,
                        min: 0.5,
                        max: 2.0,
                        divisions: 30,
                        display:
                            '${_settings.novelTtsSpeechRate.toStringAsFixed(1)}x',
                        onChanged: (v) =>
                            _update(_settings.copyWith(novelTtsSpeechRate: v)),
                      ),
                      Text(l10n.ttsSleepTimer,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500)),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          for (final v in const <int>[0, 15, 30, 45, 60, 90])
                            ChoiceChip(
                              label:
                                  Text(v == 0 ? l10n.autoPageOff : '${v}min'),
                              selected: _settings.novelTtsSleepTimer == v,
                              onSelected: (_) {
                                AppHaptics.selectionClick();
                                _update(
                                    _settings.copyWith(novelTtsSleepTimer: v));
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      SettingsSwitchTile(
                        title: l10n.novelTtsBackground,
                        value: _settings.novelTtsBackground,
                        onChanged: (v) =>
                            _update(_settings.copyWith(novelTtsBackground: v)),
                      ),
                      SettingsSwitchTile(
                        title: l10n.ttsAutoNext,
                        subtitle: l10n.ttsAutoNextDesc,
                        value: _settings.novelTtsAutoNext,
                        onChanged: (v) =>
                            _update(_settings.copyWith(novelTtsAutoNext: v)),
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      const Divider(height: 1),
                      const SizedBox(height: AppTokens.spaceMd),
                      // 在线 HTTP TTS 引擎配置。
                      SettingsSwitchTile(
                        key: const ValueKey<String>('novel.ttsEnable'),
                        title: l10n.httpTtsEnable,
                        subtitle: l10n.httpTtsEnableDesc,
                        value: _httpTts.enabled,
                        onChanged: (v) =>
                            _updateHttpTts(_httpTts.copyWith(enabled: v)),
                      ),
                      if (_httpTts.enabled) ...<Widget>[
                        // 在线语音来源：内置 Edge 语音 / 自定义 HTTP 端点。
                        _label(l10n.httpTtsProvider),
                        const SizedBox(height: AppTokens.spaceXs),
                        SegmentedButton<String>(
                          segments: <ButtonSegment<String>>[
                            ButtonSegment<String>(
                              value: 'edge',
                              label: Text(l10n.httpTtsProviderEdge),
                            ),
                            ButtonSegment<String>(
                              value: 'custom',
                              label: Text(l10n.httpTtsProviderCustom),
                            ),
                          ],
                          selected: <String>{_httpTts.provider},
                          onSelectionChanged: (Set<String> s) {
                            if (s.isEmpty) return;
                            var next = _httpTts.copyWith(provider: s.first);
                            // 切到 Edge 时补默认音色（引擎虽有回退，
                            // 显式配置便于查看与修改）。
                            if (s.first == 'edge' &&
                                next.defaultVoice.trim().isEmpty) {
                              next = next.copyWith(
                                  defaultVoice: 'zh-CN-XiaoxiaoNeural');
                            }
                            _updateHttpTts(next);
                          },
                        ),
                        if (_httpTts.isEdge) ...<Widget>[
                          const SizedBox(height: AppTokens.spaceSm),
                          Text(
                            l10n.httpTtsEdgeHint,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: AppTokens.spaceSm),
                          _edgeVoiceField(
                            label: l10n.httpTtsDefaultVoice,
                            value: _httpTts.defaultVoice,
                            onChanged: (v) => _updateHttpTts(
                                _httpTts.copyWith(defaultVoice: v)),
                          ),
                        ] else ...<Widget>[
                          _label(l10n.httpTtsUrlTemplate),
                          const SizedBox(height: AppTokens.spaceXs),
                          TextField(
                            controller: TextEditingController(
                                text: _httpTts.urlTemplate),
                            decoration: const InputDecoration(
                              hintText:
                                  'https://tts.example/api?text={text}&voice={voice}',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (v) => _updateHttpTts(
                                _httpTts.copyWith(urlTemplate: v)),
                          ),
                          const SizedBox(height: AppTokens.spaceSm),
                          _label(l10n.httpTtsDefaultVoice),
                          const SizedBox(height: AppTokens.spaceXs),
                          TextField(
                            controller: TextEditingController(
                                text: _httpTts.defaultVoice),
                            decoration: const InputDecoration(
                              hintText: 'xiaoyun',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (v) => _updateHttpTts(
                                _httpTts.copyWith(defaultVoice: v)),
                          ),
                        ],
                        const SizedBox(height: AppTokens.spaceSm),
                        _label(l10n.ttsCastNarratorVoice),
                        const SizedBox(height: AppTokens.spaceXs),
                        if (_httpTts.isEdge)
                          _edgeVoiceField(
                            label: l10n.ttsCastNarratorVoice,
                            value: _httpTts.narratorVoice,
                            onChanged: (v) => _updateHttpTts(
                                _httpTts.copyWith(narratorVoice: v)),
                          )
                        else
                          TextField(
                            controller: TextEditingController(
                                text: _httpTts.narratorVoice),
                            decoration: InputDecoration(
                              hintText: _httpTts.defaultVoice.isEmpty
                                  ? null
                                  : _httpTts.defaultVoice,
                              isDense: true,
                              border: const OutlineInputBorder(),
                            ),
                            onSubmitted: (v) => _updateHttpTts(
                                _httpTts.copyWith(narratorVoice: v)),
                          ),
                        const SizedBox(height: AppTokens.spaceSm),
                        _label(l10n.ttsCastMaleVoice),
                        const SizedBox(height: AppTokens.spaceXs),
                        if (_httpTts.isEdge)
                          _edgeVoiceField(
                            label: l10n.ttsCastMaleVoice,
                            value: _httpTts.maleVoice,
                            onChanged: (v) => _updateHttpTts(
                                _httpTts.copyWith(maleVoice: v)),
                          )
                        else
                          TextField(
                            controller: TextEditingController(
                                text: _httpTts.maleVoice),
                            decoration: InputDecoration(
                              hintText: _httpTts.defaultVoice.isEmpty
                                  ? null
                                  : _httpTts.defaultVoice,
                              isDense: true,
                              border: const OutlineInputBorder(),
                            ),
                            onSubmitted: (v) => _updateHttpTts(
                                _httpTts.copyWith(maleVoice: v)),
                          ),
                        const SizedBox(height: AppTokens.spaceSm),
                        _label(l10n.ttsCastFemaleVoice),
                        const SizedBox(height: AppTokens.spaceXs),
                        if (_httpTts.isEdge)
                          _edgeVoiceField(
                            label: l10n.ttsCastFemaleVoice,
                            value: _httpTts.femaleVoice,
                            onChanged: (v) => _updateHttpTts(
                                _httpTts.copyWith(femaleVoice: v)),
                          )
                        else
                          TextField(
                            controller: TextEditingController(
                                text: _httpTts.femaleVoice),
                            decoration: InputDecoration(
                              hintText: _httpTts.defaultVoice.isEmpty
                                  ? null
                                  : _httpTts.defaultVoice,
                              isDense: true,
                              border: const OutlineInputBorder(),
                            ),
                            onSubmitted: (v) => _updateHttpTts(
                                _httpTts.copyWith(femaleVoice: v)),
                          ),
                        const SizedBox(height: AppTokens.spaceSm),
                        _label(l10n.httpTtsVoiceMap),
                        const SizedBox(height: AppTokens.spaceXs),
                        TextField(
                          controller: TextEditingController(
                              text: _httpTts.voiceByRole.entries
                                  .map((e) => '${e.key}=${e.value}')
                                  .join('\n')),
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: '小明=xiaoming\n旁白=xiaoyun',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (v) => _updateHttpTts(_httpTts.copyWith(
                              voiceByRole: _parseVoiceMap(v))),
                        ),
                        const SizedBox(height: AppTokens.spaceXs),
                        Text(l10n.ttsCastVoiceMapHint,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                        const SizedBox(height: AppTokens.spaceMd),
                        SettingsSliderTile(
                          key: const ValueKey<String>('novel.ttsConcurrency'),
                          label: l10n.httpTtsConcurrency,
                          value: _httpTts.concurrency.toDouble(),
                          min: 1,
                          max: 8,
                          divisions: 7,
                          display: '${_httpTts.concurrency}',
                          onChanged: (v) => _updateHttpTts(
                              _httpTts.copyWith(concurrency: v.round())),
                        ),
                        SettingsSliderTile(
                          key: const ValueKey<String>('novel.ttsMaxFailures'),
                          label: l10n.httpTtsMaxFailures,
                          value: _httpTts.maxConsecutiveFailures.toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          display: '${_httpTts.maxConsecutiveFailures}',
                          onChanged: (v) => _updateHttpTts(_httpTts.copyWith(
                              maxConsecutiveFailures: v.round())),
                        ),
                        SettingsSwitchTile(
                          key: const ValueKey<String>('novel.ttsSilent'),
                          title: l10n.httpTtsSilentPlaceholder,
                          subtitle: l10n.httpTtsSilentPlaceholderDesc,
                          value: _httpTts.silentPlaceholderOnFailure,
                          onChanged: (v) => _updateHttpTts(
                              _httpTts.copyWith(silentPlaceholderOnFailure: v)),
                        ),
                        const SizedBox(height: AppTokens.spaceSm),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.cleaning_services_rounded),
                          title: Text(l10n.ttsCacheClear),
                          subtitle: _ttsCacheCount > 0
                              ? Text(l10n.ttsCacheCount(_ttsCacheCount))
                              : Text(l10n.ttsCacheEmpty),
                          onTap: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final cache =
                                await TtsAudioFileCache.createDefault();
                            final removed = await cache.clear();
                            if (!mounted) return;
                            setState(() => _ttsCacheCount = 0);
                            messenger.showSnackBar(
                              SnackBar(
                                  content:
                                      Text(l10n.ttsCacheCleared(removed))),
                            );
                          },
                        ),
                      ],
                    ],
                  ),

                  // ── 10. 其他 ──
                  SettingsCard(
                    key: const ValueKey<String>('novel.misc'),
                    initiallyExpanded: false,
                    index: 9,
                    title: l10n.novelSectionMisc,
                    children: <Widget>[
                      // 繁简转换（与阅读器面板「其他」组对齐）
                      Text(l10n.chineseConverter,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500)),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          AppValuePulse(
                            trigger: _settings.novelChineseConversion ==
                                NovelChineseConversion.none,
                            from: 0.9,
                            child: ChoiceChip(
                              label: Text(l10n.noConvert),
                              selected: _settings.novelChineseConversion ==
                                  NovelChineseConversion.none,
                              onSelected: (_) {
                                AppHaptics.selectionClick();
                                _update(_settings.copyWith(
                                    novelChineseConversion:
                                        NovelChineseConversion.none));
                              },
                            ),
                          ),
                          AppValuePulse(
                            trigger: _settings.novelChineseConversion ==
                                NovelChineseConversion.traditionalToSimplified,
                            from: 0.9,
                            child: ChoiceChip(
                              label: Text(l10n.traditionalToSimplified),
                              selected: _settings.novelChineseConversion ==
                                  NovelChineseConversion
                                      .traditionalToSimplified,
                              onSelected: (_) {
                                AppHaptics.selectionClick();
                                _update(_settings.copyWith(
                                    novelChineseConversion:
                                        NovelChineseConversion
                                            .traditionalToSimplified));
                              },
                            ),
                          ),
                          AppValuePulse(
                            trigger: _settings.novelChineseConversion ==
                                NovelChineseConversion.simplifiedToTraditional,
                            from: 0.9,
                            child: ChoiceChip(
                              label: Text(l10n.simplifiedToTraditional),
                              selected: _settings.novelChineseConversion ==
                                  NovelChineseConversion
                                      .simplifiedToTraditional,
                              onSelected: (_) {
                                AppHaptics.selectionClick();
                                _update(_settings.copyWith(
                                    novelChineseConversion:
                                        NovelChineseConversion
                                            .simplifiedToTraditional));
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // ── 10b. 阅读中预下载（跨类型对齐）──
                  SettingsCard(
                    key: const ValueKey<String>('novel.predownload'),
                    initiallyExpanded: false,
                    index: 10,
                    title: l10n.novelSectionPreDownload,
                    children: <Widget>[
                      SettingsSwitchTile(
                        key: const ValueKey<String>('novel.preDownload'),
                        title: l10n.preDownloadEnabled,
                        value: _preDownload.enabled,
                        onChanged: (v) => _updatePreDownload(
                            _preDownload.copyWith(enabled: v)),
                      ),
                      if (_preDownload.enabled) ...<Widget>[
                        SettingsSliderTile(
                          key: const ValueKey<String>(
                              'novel.preDownloadThreshold'),
                          label: l10n.preDownloadThreshold,
                          value: _preDownload.thresholdPercent.toDouble(),
                          min: 50,
                          max: 99,
                          divisions: 49,
                          display: '${_preDownload.thresholdPercent}%',
                          onChanged: (v) => _updatePreDownload(_preDownload
                              .copyWith(thresholdPercent: v.round())),
                        ),
                        SettingsSliderTile(
                          key: const ValueKey<String>('novel.preDownloadCount'),
                          label: l10n.preDownloadCount,
                          value: _preDownload.count.toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          display: '${_preDownload.count}',
                          onChanged: (v) => _updatePreDownload(
                              _preDownload.copyWith(count: v.round())),
                        ),
                      ],
                    ],
                  ),

                  // ── 10c. 正文净化（全局替换规则，内置常用规则）──
                  SettingsCard(
                    key: const ValueKey<String>('novel.purge'),
                    initiallyExpanded: false,
                    index: 11,
                    title: l10n.novelPurgeTitle,
                    children: <Widget>[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.cleaning_services_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(l10n.novelPurgeTitle),
                        subtitle: Text(l10n.novelPurgeDesc),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const NovelReplaceRuleScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // ── 10d. 导出模板（EPUB 自定义样式/封面/简介）──
                  SettingsCard(
                    key: const ValueKey<String>('novel.exportTemplate'),
                    initiallyExpanded: false,
                    index: 12,
                    title: l10n.novelExportTemplate,
                    children: <Widget>[
                      Text(l10n.novelExportTemplateDesc,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                      const SizedBox(height: AppTokens.spaceSm),
                      SettingsSwitchTile(
                        key: const ValueKey<String>('novel.exportCover'),
                        title: l10n.novelExportIncludeCover,
                        value: _exportTemplate.includeCover,
                        onChanged: (v) => _updateExportTemplate(
                            _exportTemplate.copyWith(includeCover: v)),
                      ),
                      SettingsSwitchTile(
                        key: const ValueKey<String>('novel.exportIntro'),
                        title: l10n.novelExportIncludeIntro,
                        value: _exportTemplate.includeIntro,
                        onChanged: (v) => _updateExportTemplate(
                            _exportTemplate.copyWith(includeIntro: v)),
                      ),
                      _labeled(
                          l10n.novelExportCss,
                          TextField(
                            controller: _exportCssController,
                            maxLines: 5,
                            style: const TextStyle(
                                fontSize: 12, fontFamily: 'monospace'),
                            decoration: InputDecoration(
                              hintText: l10n.novelExportCssHint,
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (_) => _saveExportTemplateDebounced(),
                          )),
                      _labeled(
                          l10n.novelExportIntro,
                          TextField(
                            controller: _exportIntroController,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText: l10n.novelExportIntroHint,
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (_) => _saveExportTemplateDebounced(),
                          )),
                    ],
                  ),
                ],
              ),
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _labeled(String label, Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceXs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500)),
          const SizedBox(height: AppTokens.spaceXs),
          child,
        ],
      ),
    );
  }

  /// 点击分区布局实时预览弹窗（复用漫画侧 [ReaderTapZones] 可视化组件）。
  void _showTapZonePreview(BuildContext context, AppLocalizations l10n) {
    final layout = ReaderTapZoneLayout.values.firstWhere(
      (e) => e.name == _settings.novelTapZoneLayout,
      orElse: () => ReaderTapZoneLayout.lShape,
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(l10n.tapZonePreview),
        content: SizedBox(
          height: 240,
          child: ReaderTapZones(
            showPreview: true,
            layout: layout,
            tapZoneInvert: _settings.novelTapZoneInvert,
            isVertical: false,
            previewLabels: <String, String>{
              'prev': l10n.tapPreviewPrev,
              'next': l10n.tapPreviewNext,
              'toggle': l10n.tapPreviewToggle,
            },
            onPrev: () {},
            onNext: () {},
            onToggleUi: () {},
          ),
        ),
      ),
    );
  }

  void _confirmReset() {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(l10n.restoreDefault),
        content: Text(l10n.novelResetConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _update(const ReaderDefaultSettings());
            },
            child: Text(l10n.restoreDefault),
          ),
        ],
      ),
    );
  }
}
