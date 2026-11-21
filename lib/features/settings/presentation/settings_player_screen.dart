/// 播放器设置子页 —— 默认解码/音频/比例/速度/字幕等全局默认值。
///
/// 持久化到 SharedPreferences（key: `player_settings_v1`）。
library;

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/platform/ohos_public_storage.dart' show isOhosDocPath;
import '../../../core/platform/ohos_storage_location_sheet.dart';
import '../../../core/platform/platform_service.dart';
import '../../../core/settings/player_settings.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/app_alert_dialog.dart';
import '../../../core/widgets/app_glass_bar.dart';
import 'widgets/settings_widgets.dart';
import 'widgets/settings_search_target.dart';

/// 播放器设置页面。
///
/// 版式对齐漫画阅读器设置页规范：
/// - 分组折叠卡只有**一级**（卡内不再嵌套任何可折叠卡片——历史版本用带
///   卡框的分段/Chip 控件造成「卡中卡」多级折叠）；
/// - 卡内平铺控件：滑块 / 开关 / 带标题的 ChoiceChip 选项组（[_chipSection]）；
/// - 依赖开关或选项显隐的子项用 [SettingsExpand] 平滑展开；
/// - AppBar 提供「恢复默认」（确认弹窗后整体回默认值）。
class SettingsPlayerScreen extends StatefulWidget {
  const SettingsPlayerScreen({super.key});

  @override
  State<SettingsPlayerScreen> createState() => _SettingsPlayerScreenState();
}

class _SettingsPlayerScreenState extends State<SettingsPlayerScreen> {
  final PlayerSettingsStore _store = PlayerSettingsStore();
  late PlayerSettings _settings;
  bool _loaded = false;

  /// 截图目录唯一来源是 SharedPreferences 键 `screenshot_custom_dir`
  /// （播放器运行时只读它）。player_settings_v1.screenshotSavePath 是
  /// 从不被运行时读取的影子字段，本页不再读写，避免双 key 互相过时。
  String _screenshotDir = '';

  Future<void> _pickScreenshotDir() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    String? dir;
    if (PlatformService.instance.isOHOS) {
      final String? picked = await showOhosStorageLocationSheet(
        context,
        title: l10n.screenshotPathSetting,
        appPrivateLabel: l10n.storageLocationAppPrivate,
        appPrivateHint: l10n.screenshotPathDefault,
        systemLabel: l10n.storageLocationSystemScreenshots,
        systemHint: l10n.storageLocationSystemScreenshotsHint,
        systemSelected: isOhosDocPath(_screenshotDir),
        appendSubdir: 'Screenshots',
      );
      if (picked == null) return;
      dir = picked.isEmpty ? null : picked;
    } else {
      dir = await FilePicker.platform.getDirectoryPath();
      if (dir == null) return;
    }
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    if (dir == null || dir.isEmpty) {
      await prefs.remove('screenshot_custom_dir');
    } else {
      await prefs.setString('screenshot_custom_dir', dir);
    }
    if (!mounted) return;
    setState(() => _screenshotDir = dir ?? '');
  }

  /// BGR 十六进制字符串转 Color（mpv 使用 BGR 格式）。
  static Color _bgrToColor(String hex) {
    final val = int.tryParse(hex, radix: 16) ?? 0xFFFFFFFF;
    final r = (val >> 16) & 0xFF;
    final g = (val >> 8) & 0xFF;
    final b = val & 0xFF;
    return Color.fromARGB(255, r, g, b);
  }

  @override
  void initState() {
    super.initState();
    _settings = const PlayerSettings();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait(<Future<dynamic>>[
      _store.load(),
      SharedPreferences.getInstance(),
    ]);
    _settings = results[0] as PlayerSettings;
    final prefs = results[1] as SharedPreferences;
    _screenshotDir = prefs.getString('screenshot_custom_dir') ?? '';
    if (mounted) {
      setState(() => _loaded = true);
    }
  }

  Future<void> _update(PlayerSettings next) async {
    setState(() => _settings = next);
    await _store.save(next);
  }

  // ── 枚举标签方法（ChoiceChip 平铺选项，与漫画阅读器设置页同款）──

  String _decodeModeLabel(AppLocalizations l10n, DecodeMode m) {
    return switch (m) {
      DecodeMode.auto => l10n.playerDecodeAuto,
      DecodeMode.sw => l10n.playerDecodeSw,
      DecodeMode.hw => l10n.playerDecodeHw,
      DecodeMode.hwPlus => l10n.playerDecodeHwPlus,
    };
  }

  String _audioChannelLabel(AppLocalizations l10n, AudioChannel c) {
    return switch (c) {
      AudioChannel.auto => l10n.playerDecodeAuto,
      AudioChannel.stereo => l10n.playerAudioStereo,
      AudioChannel.mono => l10n.playerAudioMono,
    };
  }

  String _aspectRatioLabel(AppLocalizations l10n, PlayerAspectRatio r) {
    return switch (r) {
      PlayerAspectRatio.defaultRatio => l10n.playerAspectDefault,
      PlayerAspectRatio.ratio43 => l10n.playerAspect43,
      PlayerAspectRatio.ratio169 => l10n.playerAspect169,
      PlayerAspectRatio.fill => l10n.playerAspectFill,
    };
  }

  String _upscaleShaderLabel(AppLocalizations l10n, UpscaleShaderMode m) {
    return switch (m) {
      UpscaleShaderMode.off => l10n.playerUpscaleShaderOff,
      UpscaleShaderMode.performance => l10n.playerUpscaleShaderPerformance,
      UpscaleShaderMode.quality => l10n.playerUpscaleShaderQuality,
    };
  }

  String _orientationLabel(AppLocalizations l10n, PlayerLockOrientation o) {
    return switch (o) {
      PlayerLockOrientation.followVideo => l10n.playerOrientationFollowVideo,
      PlayerLockOrientation.auto => l10n.playerOrientationAuto,
      PlayerLockOrientation.portrait => l10n.playerOrientationPortrait,
      PlayerLockOrientation.landscape => l10n.playerOrientationLandscape,
    };
  }

  String _seekMultiplierLabel(AppLocalizations l10n, SeekMultiplier m) {
    return switch (m) {
      SeekMultiplier.half => l10n.playerSeekHalf,
      SeekMultiplier.normal => l10n.playerSeekNormal,
      SeekMultiplier.double => l10n.playerSeekDouble,
    };
  }

  String _audioBackgroundLabel(AppLocalizations l10n, AudioBackgroundMode m) {
    return switch (m) {
      AudioBackgroundMode.cover => l10n.audioBackgroundCover,
      AudioBackgroundMode.theme => l10n.audioBackgroundTheme,
      AudioBackgroundMode.solid => l10n.audioBackgroundSolid,
    };
  }

  /// 播放键配色沿用它同背景一致的三选项文案（封面/主题/纯色）。
  String _audioPlayButtonColorLabel(
      AppLocalizations l10n, AudioPlayButtonColorMode m) {
    return switch (m) {
      AudioPlayButtonColorMode.cover => l10n.audioBackgroundCover,
      AudioPlayButtonColorMode.theme => l10n.audioBackgroundTheme,
      AudioPlayButtonColorMode.solid => l10n.audioBackgroundSolid,
    };
  }

  /// 字幕位置（存储值为 'top' / 'center' / 'bottom'）。
  String _subtitlePositionLabel(AppLocalizations l10n, String p) {
    return switch (p) {
      'top' => l10n.subtitlePosTop,
      'center' => l10n.subtitlePosCenter,
      _ => l10n.subtitlePosBottom,
    };
  }

  /// ASS/SSA 覆盖模式（存储值为 'yes' / 'no' / 'strip' / 'force'）。
  String _assModeLabel(AppLocalizations l10n, String m) {
    return switch (m) {
      'yes' => l10n.subtitleAssYes,
      'no' => l10n.subtitleAssNo,
      'strip' => l10n.subtitleAssStrip,
      _ => l10n.subtitleAssForce,
    };
  }

  /// 字幕颜色选择器（弹出预设颜色网格）。
  Future<void> _pickSubtitleColor({required int kind}) async {
    const colors = <String>[
      'FFFFFF',
      'FFFF00',
      '00FF00',
      '00FFFF',
      'FF0000',
      'FF00FF',
      '0000FF',
      '000000',
    ];
    final l10n = AppLocalizations.of(context);
    final label = kind == 0
        ? l10n.subtitleTextColor
        : kind == 1
            ? l10n.subtitleBorderColorLabel
            : l10n.subtitleShadowColorLabel;
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(label),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colors.map((c) {
            final color = _bgrToColor(c);
            return GestureDetector(
              onTap: () => Navigator.pop(ctx, c),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: Theme.of(ctx).colorScheme.outlineVariant),
                ),
              ),
            );
          }).toList(),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
    if (selected == null) return;
    if (kind == 0) {
      _update(_settings.copyWith(subtitleColor: selected));
    } else if (kind == 1) {
      _update(_settings.copyWith(subtitleBorderColor: selected));
    } else {
      _update(_settings.copyWith(subtitleShadowColor: selected));
    }
  }

  /// 音频模式纯色背景选择器（预设色 + RGB 自定义）。
  Future<void> _pickAudioBackgroundColor() async {
    const List<int> presets = <int>[
      0xFF1C1C24,
      0xFF101820,
      0xFF0F1B2A,
      0xFF14201A,
      0xFF1B1512,
      0xFF201421,
      0xFF2A1B1B,
      0xFF000000,
    ];
    final l10n = AppLocalizations.of(context);
    final int? selected = await showDialog<int>(
      context: context,
      builder: (ctx) => _RgbColorDialog(
        title: l10n.audioBackgroundColorTitle,
        initial: _settings.audioBackgroundColor,
        presets: presets,
      ),
    );
    if (selected == null) return;
    _update(_settings.copyWith(audioBackgroundColor: selected));
  }

  /// 音频播放/暂停键颜色选择器（纯色模式下的自定义色）。
  Future<void> _pickAudioPlayButtonColor() async {
    final l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int initial = _settings.audioPlayButtonColor == 0
        ? scheme.primaryContainer.toARGB32()
        : _settings.audioPlayButtonColor;
    final int? selected = await showDialog<int>(
      context: context,
      builder: (ctx) => _RgbColorDialog(
        title: l10n.audioPlayButtonSolidColorTitle,
        initial: initial,
      ),
    );
    if (selected == null) return;
    _update(_settings.copyWith(audioPlayButtonColor: selected));
  }

  /// 恢复默认（与漫画阅读器设置页同款：AppBar 按钮 → 确认弹窗 → 整体回默认）。
  Future<void> _confirmReset() async {
    final l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(l10n.restoreDefault),
        content: Text(l10n.playerResetConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.restoreDefault),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // 截图目录一并回默认：仅清除指针偏好，不删除任何已保存文件。
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('screenshot_custom_dir');
    if (!mounted) return;
    setState(() => _screenshotDir = '');
    await _update(const PlayerSettings());
  }

  /// 带标题的 ChoiceChip 组（与漫画阅读器设置页同款版式）。
  /// [key] 用于设置搜索「滚动到具体设置」的定位锚点。
  Widget _chipSection(
    BuildContext context,
    String label,
    List<Widget> chips, {
    Key? key,
  }) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w500)),
        const SizedBox(height: AppTokens.spaceSm),
        Wrap(
          spacing: AppTokens.spaceSm,
          runSpacing: AppTokens.spaceSm,
          children: chips,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.playerSettingsTitle),
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
                  // ── 播放核心 ──
                  SettingsCard(
                    key: const ValueKey<String>('player.core'),
                    initiallyExpanded: false,
                    index: 0,
                    title: l10n.playerCoreGroup,
                    description: l10n.playerCoreGroupDesc,
                    children: <Widget>[
                      // 解码方式（4 选项 ChoiceChip）
                      _chipSection(
                        context,
                        l10n.playerDefaultDecodeMode,
                        DecodeMode.values.map((m) {
                          return ChoiceChip(
                            label: Text(_decodeModeLabel(l10n, m)),
                            selected: _settings.decodeMode == m,
                            onSelected: (_) {
                              AppHaptics.selectionClick();
                              _update(_settings.copyWith(decodeMode: m));
                            },
                          );
                        }).toList(),
                        key: const ValueKey<String>('player.decodeMode'),
                      ),
                      const SizedBox(height: AppTokens.spaceMd),

                      // 声道（3 选项 ChoiceChip）
                      _chipSection(
                        context,
                        l10n.playerDefaultAudioChannel,
                        AudioChannel.values.map((c) {
                          return ChoiceChip(
                            label: Text(_audioChannelLabel(l10n, c)),
                            selected: _settings.audioChannel == c,
                            onSelected: (_) {
                              AppHaptics.selectionClick();
                              _update(_settings.copyWith(audioChannel: c));
                            },
                          );
                        }).toList(),
                        key: const ValueKey<String>('player.audioChannel'),
                      ),
                      const SizedBox(height: AppTokens.spaceMd),

                      // 画面比例（4 选项 ChoiceChip）
                      _chipSection(
                        context,
                        l10n.playerDefaultAspectRatio,
                        PlayerAspectRatio.values.map((r) {
                          return ChoiceChip(
                            label: Text(_aspectRatioLabel(l10n, r)),
                            selected: _settings.aspectRatio == r,
                            onSelected: (_) {
                              AppHaptics.selectionClick();
                              _update(_settings.copyWith(aspectRatio: r));
                            },
                          );
                        }).toList(),
                        key: const ValueKey<String>('player.aspectRatio'),
                      ),
                      const SizedBox(height: AppTokens.spaceMd),

                      // 超分辨率 shader 默认档位（播放器内可按剧集单独覆盖）
                      _chipSection(
                        context,
                        l10n.playerUpscaleShader,
                        UpscaleShaderMode.values.map((m) {
                          return ChoiceChip(
                            label: Text(_upscaleShaderLabel(l10n, m)),
                            selected: _settings.upscaleShader == m,
                            onSelected: (_) {
                              AppHaptics.selectionClick();
                              _update(_settings.copyWith(upscaleShader: m));
                            },
                          );
                        }).toList(),
                        key: const ValueKey<String>('player.upscaleShader'),
                      ),
                      const SizedBox(height: AppTokens.spaceMd),

                      // 默认倍速
                      SettingsSliderTile(
                        label: l10n.playerDefaultSpeed,
                        value: _settings.playbackSpeed,
                        min: 0.5,
                        max: 2.0,
                        divisions: 15,
                        display:
                            '${_settings.playbackSpeed.toStringAsFixed(1)}x',
                        onChanged: (v) =>
                            _update(_settings.copyWith(playbackSpeed: v)),
                      ),
                      // 自动连播
                      SettingsSwitchTile(
                        key: const ValueKey<String>('player.autoplay'),
                        title: l10n.playerDefaultAutoPlay,
                        value: _settings.autoPlayNext,
                        onChanged: (v) =>
                            _update(_settings.copyWith(autoPlayNext: v)),
                      ),
                      // 自动连播倒计时（播完弹「N 秒后播放下一集」可取消）：
                      // 依赖开关显隐，平滑展开（不额外嵌套任何折叠）。
                      SettingsExpand(
                        visible: _settings.autoPlayNext,
                        padding: EdgeInsets.zero,
                        child: _chipSection(
                          context,
                          l10n.playerAutoPlayCountdown,
                          <Widget>[
                            ChoiceChip(
                              label: Text(l10n.playerCountdownImmediate),
                              selected: _settings.autoPlayCountdownSeconds == 0,
                              onSelected: (_) {
                                AppHaptics.selectionClick();
                                _update(_settings.copyWith(
                                    autoPlayCountdownSeconds: 0));
                              },
                            ),
                            for (final int v in const <int>[3, 5, 10, 15])
                              ChoiceChip(
                                label: Text('${v}s'),
                                selected:
                                    _settings.autoPlayCountdownSeconds == v,
                                onSelected: (_) {
                                  AppHaptics.selectionClick();
                                  _update(_settings.copyWith(
                                      autoPlayCountdownSeconds: v));
                                },
                              ),
                          ],
                        ),
                      ),
                      // 默认音量
                      SettingsSliderTile(
                        label: l10n.playerDefaultVolume,
                        value: _settings.defaultVolume,
                        min: 0,
                        max: 100,
                        divisions: 20,
                        display: _settings.defaultVolume.toStringAsFixed(0),
                        onChanged: (v) =>
                            _update(_settings.copyWith(defaultVolume: v)),
                      ),
                    ],
                  ),

                  // ── 字幕 ──
                  SettingsCard(
                    key: const ValueKey<String>('player.subtitle'),
                    initiallyExpanded: false,
                    index: 1,
                    title: l10n.playerSubtitleGroup,
                    description: l10n.playerSubtitleGroupDesc,
                    children: <Widget>[
                      SettingsSliderTile(
                        label: l10n.subtitleFontSize,
                        value: _settings.subtitleFontSize,
                        min: 12,
                        max: 60,
                        divisions: 48,
                        display: _settings.subtitleFontSize.toStringAsFixed(0),
                        onChanged: (v) =>
                            _update(_settings.copyWith(subtitleFontSize: v)),
                      ),
                      SettingsSliderTile(
                        label: l10n.subtitleScale,
                        value: _settings.subtitleScale,
                        min: 0.5,
                        max: 3.0,
                        divisions: 50,
                        display: _settings.subtitleScale.toStringAsFixed(2),
                        onChanged: (v) =>
                            _update(_settings.copyWith(subtitleScale: v)),
                      ),
                      SettingsSliderTile(
                        label: l10n.subtitleBorderSize,
                        value: _settings.subtitleBorderSize,
                        min: 0,
                        max: 6,
                        divisions: 12,
                        display:
                            '${_settings.subtitleBorderSize.toStringAsFixed(1)}px',
                        onChanged: (v) =>
                            _update(_settings.copyWith(subtitleBorderSize: v)),
                      ),
                      SettingsSliderTile(
                        label: l10n.subtitleShadowOffset,
                        value: _settings.subtitleShadowOffset,
                        min: 0,
                        max: 12,
                        divisions: 24,
                        display:
                            '${_settings.subtitleShadowOffset.toStringAsFixed(1)}px',
                        onChanged: (v) => _update(
                            _settings.copyWith(subtitleShadowOffset: v)),
                      ),
                      // 颜色（文字 / 边框 / 阴影三色 ActionChip，头像显当前色）
                      _chipSection(
                        context,
                        l10n.subtitleColors,
                        <Widget>[
                          ActionChip(
                            avatar: CircleAvatar(
                              backgroundColor:
                                  _bgrToColor(_settings.subtitleColor),
                              radius: 8,
                            ),
                            label: Text(l10n.subtitleTextColor),
                            onPressed: () => _pickSubtitleColor(kind: 0),
                          ),
                          ActionChip(
                            avatar: CircleAvatar(
                              backgroundColor:
                                  _bgrToColor(_settings.subtitleBorderColor),
                              radius: 8,
                            ),
                            label: Text(l10n.subtitleBorderColorLabel),
                            onPressed: () => _pickSubtitleColor(kind: 1),
                          ),
                          ActionChip(
                            avatar: CircleAvatar(
                              backgroundColor:
                                  _bgrToColor(_settings.subtitleShadowColor),
                              radius: 8,
                            ),
                            label: Text(l10n.subtitleShadowColorLabel),
                            onPressed: () => _pickSubtitleColor(kind: 2),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceMd),

                      // 位置（3 选项 ChoiceChip，本地化文案）
                      _chipSection(
                        context,
                        l10n.subtitlePosition,
                        <String>['top', 'center', 'bottom'].map((p) {
                          return ChoiceChip(
                            label: Text(_subtitlePositionLabel(l10n, p)),
                            selected: _settings.subtitlePosition == p,
                            onSelected: (_) {
                              AppHaptics.selectionClick();
                              _update(_settings.copyWith(subtitlePosition: p));
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: AppTokens.spaceMd),

                      // ASS/SSA 覆盖模式（4 选项 ChoiceChip，替代原 DropdownButton）
                      _chipSection(
                        context,
                        l10n.subtitleAssOverride,
                        <String>['yes', 'no', 'strip', 'force'].map((m) {
                          return ChoiceChip(
                            label: Text(_assModeLabel(l10n, m)),
                            selected: _settings.subtitleAssMode == m,
                            onSelected: (_) {
                              AppHaptics.selectionClick();
                              _update(_settings.copyWith(subtitleAssMode: m));
                            },
                          );
                        }).toList(),
                      ),
                      // 偏移
                      SettingsSliderTile(
                        label: l10n.subtitleOffset,
                        value: _settings.subtitleDelayMs.toDouble(),
                        min: -5000,
                        max: 5000,
                        divisions: 100,
                        display: '${_settings.subtitleDelayMs} ms',
                        onChanged: (v) => _update(
                            _settings.copyWith(subtitleDelayMs: v.round())),
                      ),
                      // 显示字幕
                      SettingsSwitchTile(
                        title: l10n.subtitleShow,
                        value: _settings.subtitleVisible,
                        onChanged: (v) =>
                            _update(_settings.copyWith(subtitleVisible: v)),
                      ),
                    ],
                  ),

                  // ── 截图 ──
                  SettingsCard(
                    key: const ValueKey<String>('player.screenshot'),
                    initiallyExpanded: false,
                    index: 2,
                    title: l10n.playerScreenshotGroup,
                    description: l10n.playerScreenshotGroupDesc,
                    children: <Widget>[
                      // 保存路径：加粗标题 + 当前路径小字 + 文件夹按钮
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: AppTokens.spaceXs),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    l10n.screenshotPathSetting,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(height: AppTokens.spaceXs),
                                  Text(
                                    _screenshotDir.isEmpty
                                        ? l10n.screenshotPathDefault
                                        : (isOhosDocPath(_screenshotDir)
                                            ? l10n
                                                .storageLocationSystemScreenshots
                                            : _screenshotDir),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: AppTokens.spaceSm),
                            IconButton(
                              icon: const Icon(Icons.folder_open_rounded),
                              tooltip: l10n.screenshotPathSetting,
                              onPressed: _pickScreenshotDir,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // ── 手势与控制 ──
                  SettingsCard(
                    key: const ValueKey<String>('player.gesture'),
                    initiallyExpanded: false,
                    index: 3,
                    title: l10n.playerGestureGroup,
                    description: l10n.playerGestureGroupDesc,
                    children: <Widget>[
                      // 屏幕方向（4 选项 ChoiceChip）
                      _chipSection(
                        context,
                        l10n.playerDefaultOrientation,
                        PlayerLockOrientation.values.map((o) {
                          return ChoiceChip(
                            label: Text(_orientationLabel(l10n, o)),
                            selected: _settings.lockOrientation == o,
                            onSelected: (_) {
                              AppHaptics.selectionClick();
                              _update(_settings.copyWith(lockOrientation: o));
                            },
                          );
                        }).toList(),
                        key: const ValueKey<String>('player.orientation'),
                      ),
                      const SizedBox(height: AppTokens.spaceMd),

                      // 快进倍率（3 选项 ChoiceChip）
                      _chipSection(
                        context,
                        l10n.playerGestureSeekMultiplier,
                        SeekMultiplier.values.map((m) {
                          return ChoiceChip(
                            label: Text(_seekMultiplierLabel(l10n, m)),
                            selected: _settings.seekMultiplier == m,
                            onSelected: (_) {
                              AppHaptics.selectionClick();
                              _update(_settings.copyWith(seekMultiplier: m));
                            },
                          );
                        }).toList(),
                        key: const ValueKey<String>('player.gestureSeek'),
                      ),
                      // 长按倍速
                      SettingsSwitchTile(
                        key: const ValueKey<String>('player.longPressSpeed'),
                        title: l10n.playerLongPressSpeedUp,
                        value: _settings.longPressSpeedUp,
                        onChanged: (v) =>
                            _update(_settings.copyWith(longPressSpeedUp: v)),
                      ),
                      SettingsSliderTile(
                        label: l10n.playerLongPressSpeed,
                        value: _settings.longPressSpeed,
                        min: 1.0,
                        max: 3.0,
                        divisions: 8,
                        display:
                            '${_settings.longPressSpeed.toStringAsFixed(1)}x',
                        onChanged: (v) =>
                            _update(_settings.copyWith(longPressSpeed: v)),
                      ),
                      // 隐藏控制栏后底部细进度条（可开关）。
                      SettingsSwitchTile(
                        key: const ValueKey<String>('player.bottomProgress'),
                        title: l10n.playerBottomProgress,
                        value: _settings.showBottomProgress,
                        onChanged: (v) =>
                            _update(_settings.copyWith(showBottomProgress: v)),
                      ),
                      // 自动选线路（按集记忆的线路优先；失败自动轮换候选线路）。
                      SettingsSwitchTile(
                        key: const ValueKey<String>('player.autoSelectLine'),
                        title: l10n.playerAutoSelectLine,
                        value: _settings.autoSelectLine,
                        onChanged: (v) =>
                            _update(_settings.copyWith(autoSelectLine: v)),
                      ),
                    ],
                  ),

                  // ── 音频播放 ──
                  SettingsCard(
                    key: const ValueKey<String>('player.audio'),
                    initiallyExpanded: false,
                    index: 4,
                    title: l10n.playerAudioGroup,
                    description: l10n.playerAudioGroupDesc,
                    children: <Widget>[
                      // 背景风格（3 选项 ChoiceChip）
                      _chipSection(
                        context,
                        l10n.audioBackgroundTitle,
                        AudioBackgroundMode.values.map((m) {
                          return ChoiceChip(
                            label: Text(_audioBackgroundLabel(l10n, m)),
                            selected: _settings.audioBackgroundMode == m,
                            onSelected: (_) {
                              AppHaptics.selectionClick();
                              _update(
                                  _settings.copyWith(audioBackgroundMode: m));
                            },
                          );
                        }).toList(),
                        key: const ValueKey<String>('player.audioBackground'),
                      ),
                      // 纯色背景颜色：选中「纯色」时平滑展开。
                      SettingsExpand(
                        visible: _settings.audioBackgroundMode ==
                            AudioBackgroundMode.solid,
                        padding: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: AppTokens.spaceXs),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  l10n.audioBackgroundColorTitle,
                                  style:
                                      Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                              IconButton(
                                key: const ValueKey<String>(
                                    'player.audioBackgroundColor'),
                                tooltip: l10n.audioBackgroundColorTitle,
                                onPressed: _pickAudioBackgroundColor,
                                icon: Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color:
                                        Color(_settings.audioBackgroundColor),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outlineVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // 播放键配色：与背景风格同样的三选项（封面/主题/纯色）。
                      _chipSection(
                        context,
                        l10n.audioPlayButtonColorTitle,
                        AudioPlayButtonColorMode.values.map((m) {
                          return ChoiceChip(
                            label: Text(_audioPlayButtonColorLabel(l10n, m)),
                            selected:
                                _settings.audioPlayButtonColorMode == m,
                            onSelected: (_) {
                              AppHaptics.selectionClick();
                              _update(_settings.copyWith(
                                  audioPlayButtonColorMode: m));
                            },
                          );
                        }).toList(),
                        key: const ValueKey<String>(
                            'player.audioPlayButtonColorMode'),
                      ),
                      // 纯色按钮颜色：选中「纯色」时平滑展开。
                      SettingsExpand(
                        visible: _settings.audioPlayButtonColorMode ==
                            AudioPlayButtonColorMode.solid,
                        padding: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: AppTokens.spaceXs),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  l10n.audioPlayButtonSolidColorTitle,
                                  style:
                                      Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                              IconButton(
                                key: const ValueKey<String>(
                                    'player.audioPlayButtonColor'),
                                tooltip: l10n.audioPlayButtonSolidColorTitle,
                                onPressed: _pickAudioPlayButtonColor,
                                icon: Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: _settings.audioPlayButtonColor == 0
                                        ? Theme.of(context)
                                            .colorScheme
                                            .primaryContainer
                                        : Color(
                                            _settings.audioPlayButtonColor),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outlineVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}

/// RGB 自定义颜色弹窗：R/G/B 三通道滑块 + 预设色块 + 实时预览。
///
/// 确认返回 ARGB int；取消返回 null。
class _RgbColorDialog extends StatefulWidget {
  final String title;
  final int initial;
  final List<int> presets;

  const _RgbColorDialog({
    required this.title,
    required this.initial,
    this.presets = const <int>[],
  });

  @override
  State<_RgbColorDialog> createState() => _RgbColorDialogState();
}

class _RgbColorDialogState extends State<_RgbColorDialog> {
  late double _r;
  late double _g;
  late double _b;

  @override
  void initState() {
    super.initState();
    _apply(widget.initial);
  }

  void _apply(int argb) {
    final Color c = Color(argb);
    _r = c.r * 255.0;
    _g = c.g * 255.0;
    _b = c.b * 255.0;
  }

  int get _value => Color.from(
        alpha: 1.0,
        red: _r / 255.0,
        green: _g / 255.0,
        blue: _b / 255.0,
      ).toARGB32();

  String get _hex =>
      '#${(_value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppAlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                key: const ValueKey<String>('audio_rgb_preview'),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Color(_value),
                  borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                  border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant),
                ),
              ),
              const SizedBox(width: AppTokens.spaceMd),
              Text(_hex, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          if (widget.presets.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppTokens.spaceMd),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: widget.presets.map((int value) {
                final bool active = value == _value;
                return GestureDetector(
                  key: ValueKey<String>(
                      'audio_color_preset_${value.toRadixString(16)}'),
                  onTap: () {
                    AppHaptics.selectionClick();
                    setState(() => _apply(value));
                  },
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Color(value),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: active
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                        width: active ? 3 : 1,
                      ),
                    ),
                    child: active
                        ? Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: AppTokens.spaceXs),
          _channelSlider('R', _r, (double v) => setState(() => _r = v),
              key: const ValueKey<String>('audio_rgb_slider_r')),
          _channelSlider('G', _g, (double v) => setState(() => _g = v),
              key: const ValueKey<String>('audio_rgb_slider_g')),
          _channelSlider('B', _b, (double v) => setState(() => _b = v),
              key: const ValueKey<String>('audio_rgb_slider_b')),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey<String>('audio_rgb_confirm'),
          onPressed: () => Navigator.of(context).pop(_value),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }

  Widget _channelSlider(
    String label,
    double value,
    ValueChanged<double> onChanged, {
    Key? key,
  }) {
    return Row(
      key: key,
      children: <Widget>[
        SizedBox(
          width: 16,
          child: Text(label, style: Theme.of(context).textTheme.labelMedium),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: 0,
            max: 255,
            divisions: 255,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            value.round().toString(),
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    );
  }
}
