/// 播放器设置子页 —— 默认解码/音频/比例/速度/字幕等全局默认值。
///
/// 持久化到 SharedPreferences（key: `player_settings_v1`）。
library;

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/platform/ohos_public_storage.dart' show isOhosDocPath;
import '../../../core/platform/ohos_storage_location_sheet.dart';
import '../../../core/platform/platform_service.dart';
import '../../../core/settings/player_settings.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_glass_bar.dart';
import 'widgets/settings_widgets.dart';
import 'widgets/settings_search_target.dart';

/// 播放器设置页面。
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
      builder: (ctx) => AlertDialog(
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.playerSettingsTitle)),
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
                    children: <Widget>[
                      SettingsSegmentedTile<DecodeMode>(
                        key: const ValueKey<String>('player.decodeMode'),
                        title: l10n.playerDefaultDecodeMode,
                        selected: <DecodeMode>{_settings.decodeMode},
                        onSelectionChanged: (s) =>
                            _update(_settings.copyWith(decodeMode: s.first)),
                        segments: <ButtonSegment<DecodeMode>>[
                          ButtonSegment<DecodeMode>(
                              value: DecodeMode.auto,
                              label: Text(l10n.playerDecodeAuto)),
                          ButtonSegment<DecodeMode>(
                              value: DecodeMode.sw,
                              label: Text(l10n.playerDecodeSw)),
                          ButtonSegment<DecodeMode>(
                              value: DecodeMode.hw,
                              label: Text(l10n.playerDecodeHw)),
                          ButtonSegment<DecodeMode>(
                              value: DecodeMode.hwPlus,
                              label: Text(l10n.playerDecodeHwPlus)),
                        ],
                      ),
                      SettingsSegmentedTile<AudioChannel>(
                        key: const ValueKey<String>('player.audioChannel'),
                        title: l10n.playerDefaultAudioChannel,
                        selected: <AudioChannel>{_settings.audioChannel},
                        onSelectionChanged: (s) =>
                            _update(_settings.copyWith(audioChannel: s.first)),
                        segments: <ButtonSegment<AudioChannel>>[
                          ButtonSegment<AudioChannel>(
                              value: AudioChannel.auto,
                              label: Text(l10n.playerDecodeAuto)),
                          ButtonSegment<AudioChannel>(
                              value: AudioChannel.stereo,
                              label: Text(l10n.playerAudioStereo)),
                          ButtonSegment<AudioChannel>(
                              value: AudioChannel.mono,
                              label: Text(l10n.playerAudioMono)),
                        ],
                      ),
                      SettingsSegmentedTile<PlayerAspectRatio>(
                        key: const ValueKey<String>('player.aspectRatio'),
                        title: l10n.playerDefaultAspectRatio,
                        selected: <PlayerAspectRatio>{_settings.aspectRatio},
                        onSelectionChanged: (s) =>
                            _update(_settings.copyWith(aspectRatio: s.first)),
                        segments: <ButtonSegment<PlayerAspectRatio>>[
                          ButtonSegment<PlayerAspectRatio>(
                              value: PlayerAspectRatio.defaultRatio,
                              label: Text(l10n.playerAspectDefault)),
                          ButtonSegment<PlayerAspectRatio>(
                              value: PlayerAspectRatio.ratio43,
                              label: Text(l10n.playerAspect43)),
                          ButtonSegment<PlayerAspectRatio>(
                              value: PlayerAspectRatio.ratio169,
                              label: Text(l10n.playerAspect169)),
                          ButtonSegment<PlayerAspectRatio>(
                              value: PlayerAspectRatio.fill,
                              label: Text(l10n.playerAspectFill)),
                        ],
                      ),
                      // 超分辨率 shader 默认档位（播放器内可按剧集单独覆盖）
                      SettingsSegmentedTile<UpscaleShaderMode>(
                        key: const ValueKey<String>('player.upscaleShader'),
                        title: l10n.playerUpscaleShader,
                        selected: <UpscaleShaderMode>{_settings.upscaleShader},
                        onSelectionChanged: (s) =>
                            _update(_settings.copyWith(upscaleShader: s.first)),
                        segments: <ButtonSegment<UpscaleShaderMode>>[
                          ButtonSegment<UpscaleShaderMode>(
                              value: UpscaleShaderMode.off,
                              label: Text(l10n.playerUpscaleShaderOff)),
                          ButtonSegment<UpscaleShaderMode>(
                              value: UpscaleShaderMode.performance,
                              label: Text(l10n.playerUpscaleShaderPerformance)),
                          ButtonSegment<UpscaleShaderMode>(
                              value: UpscaleShaderMode.quality,
                              label: Text(l10n.playerUpscaleShaderQuality)),
                        ],
                      ),
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
                      SettingsSwitchTile(
                        key: const ValueKey<String>('player.autoplay'),
                        title: l10n.playerDefaultAutoPlay,
                        value: _settings.autoPlayNext,
                        onChanged: (v) =>
                            _update(_settings.copyWith(autoPlayNext: v)),
                      ),
                      // 自动连播倒计时（播完弹「N 秒后播放下一集」可取消）。
                      if (_settings.autoPlayNext)
                        SettingsChoiceChips<int>(
                          title: l10n.playerAutoPlayCountdown,
                          selected: _settings.autoPlayCountdownSeconds,
                          onSelected: (v) => _update(
                              _settings.copyWith(autoPlayCountdownSeconds: v)),
                          options: <SettingsChoiceChipData<int>>[
                            SettingsChoiceChipData<int>(
                                value: 0, label: l10n.playerCountdownImmediate),
                            const SettingsChoiceChipData<int>(
                                value: 3, label: '3s'),
                            const SettingsChoiceChipData<int>(
                                value: 5, label: '5s'),
                            const SettingsChoiceChipData<int>(
                                value: 10, label: '10s'),
                            const SettingsChoiceChipData<int>(
                                value: 15, label: '15s'),
                          ],
                        ),
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
                      // 颜色选择行
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: AppTokens.spaceXs),
                        child: Wrap(
                          spacing: AppTokens.spaceSm,
                          runSpacing: AppTokens.spaceXs,
                          children: <Widget>[
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
                      ),
                      // 位置选择
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: AppTokens.spaceXs),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Padding(
                              padding: const EdgeInsets.only(
                                  bottom: AppTokens.spaceSm),
                              child: Text(
                                l10n.subtitlePosition,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            SegmentedButton<String>(
                              segments: const <ButtonSegment<String>>[
                                ButtonSegment(value: 'top', label: Text('Top')),
                                ButtonSegment(
                                    value: 'center', label: Text('Center')),
                                ButtonSegment(
                                    value: 'bottom', label: Text('Bottom')),
                              ],
                              selected: <String>{_settings.subtitlePosition},
                              onSelectionChanged: (Set<String> s) {
                                _update(_settings.copyWith(
                                    subtitlePosition: s.first));
                              },
                              showSelectedIcon: false,
                              style: ButtonStyle(
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: WidgetStateProperty.all(
                                  const EdgeInsets.symmetric(
                                      horizontal: AppTokens.spaceSm),
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // ASS/SSA 覆盖模式
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: AppTokens.spaceXs),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              l10n.subtitleAssOverride,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            DropdownButton<String>(
                              elevation: 0,
                              borderRadius:
                                  BorderRadius.circular(AppTokens.radiusMd),
                              value: _settings.subtitleAssMode,
                              items: const <DropdownMenuItem<String>>[
                                DropdownMenuItem(
                                    value: 'yes', child: Text('Yes')),
                                DropdownMenuItem(
                                    value: 'no', child: Text('No')),
                                DropdownMenuItem(
                                    value: 'strip', child: Text('Strip')),
                                DropdownMenuItem(
                                    value: 'force', child: Text('Force')),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  _update(
                                      _settings.copyWith(subtitleAssMode: v));
                                }
                              },
                              underline: Container(),
                              iconSize: 18,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
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
                    children: <Widget>[
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
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
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
                    children: <Widget>[
                      SettingsSegmentedTile<PlayerLockOrientation>(
                        key: const ValueKey<String>('player.orientation'),
                        title: l10n.playerDefaultOrientation,
                        selected: <PlayerLockOrientation>{
                          _settings.lockOrientation
                        },
                        onSelectionChanged: (s) => _update(
                            _settings.copyWith(lockOrientation: s.first)),
                        // 四段较长：关闭选中对勾 + 允许横向滚动，窄屏不溢出。
                        showSelectedIcon: false,
                        scrollable: true,
                        segments: <ButtonSegment<PlayerLockOrientation>>[
                          ButtonSegment<PlayerLockOrientation>(
                              value: PlayerLockOrientation.followVideo,
                              label: Text(l10n.playerOrientationFollowVideo)),
                          ButtonSegment<PlayerLockOrientation>(
                              value: PlayerLockOrientation.auto,
                              label: Text(l10n.playerOrientationAuto)),
                          ButtonSegment<PlayerLockOrientation>(
                              value: PlayerLockOrientation.portrait,
                              label: Text(l10n.playerOrientationPortrait)),
                          ButtonSegment<PlayerLockOrientation>(
                              value: PlayerLockOrientation.landscape,
                              label: Text(l10n.playerOrientationLandscape)),
                        ],
                      ),
                      SettingsSegmentedTile<SeekMultiplier>(
                        key: const ValueKey<String>('player.gestureSeek'),
                        title: l10n.playerGestureSeekMultiplier,
                        selected: <SeekMultiplier>{_settings.seekMultiplier},
                        onSelectionChanged: (s) => _update(
                            _settings.copyWith(seekMultiplier: s.first)),
                        segments: <ButtonSegment<SeekMultiplier>>[
                          ButtonSegment<SeekMultiplier>(
                              value: SeekMultiplier.half,
                              label: Text(l10n.playerSeekHalf)),
                          ButtonSegment<SeekMultiplier>(
                              value: SeekMultiplier.normal,
                              label: Text(l10n.playerSeekNormal)),
                          ButtonSegment<SeekMultiplier>(
                              value: SeekMultiplier.double,
                              label: Text(l10n.playerSeekDouble)),
                        ],
                      ),
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
                ],
              ),
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}
