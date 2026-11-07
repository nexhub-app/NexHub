import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../../../core/comic/models/reader_preferences.dart';
import '../../../core/comic/manga_upscale.dart';
import '../../../core/platform/platform_service.dart';
import '../../settings/presentation/widgets/motion_effects_adjustments.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_alert_dialog.dart';
import '../../../core/widgets/app_animations.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import 'reader_image_filter.dart';
import 'reader_tap_zones.dart';

/// 漫画设置面板内容（[ReaderPreferences] 驱动），供阅读器以「内联面板」形式
/// 直接嵌入阅读界面（桌面端右侧 / 移动端底部）。
///
/// [onClose] 为关闭图标回调（内联场景用它关闭面板）。
/// [sleepTimer] / [onSleepTimerChanged]：会话级睡眠定时（跨类型对齐，
/// 非偏好字段，由阅读器持有 Timer 生命周期，面板仅做选择交互）。
Widget buildComicSettingsSheet({
  required ReaderPreferences initial,
  void Function(ReaderPreferences)? onChanged,
  required VoidCallback onClose,
  ComicSleepTimerState? sleepTimer,
  ValueChanged<ComicSleepTimerState>? onSleepTimerChanged,
}) =>
    _FlatSettingsSheet(
      initial: initial,
      onChanged: onChanged,
      onClose: onClose,
      sleepTimer: sleepTimer,
      onSleepTimerChanged: onSleepTimerChanged,
    );

class _FlatSettingsSheet extends StatefulWidget {
  final ReaderPreferences initial;
  final void Function(ReaderPreferences)? onChanged;
  final VoidCallback onClose;
  final ComicSleepTimerState? sleepTimer;
  final ValueChanged<ComicSleepTimerState>? onSleepTimerChanged;
  const _FlatSettingsSheet({
    required this.initial,
    required this.onChanged,
    required this.onClose,
    this.sleepTimer,
    this.onSleepTimerChanged,
  });

  @override
  State<_FlatSettingsSheet> createState() => _FlatSettingsSheetState();
}

class _FlatSettingsSheetState extends State<_FlatSettingsSheet> {
  late ReaderPreferences _draft;
  final TextEditingController _searchController = TextEditingController();

  /// 最近一次选中的超分档位（不含 off）：关闭开关再打开时恢复该档，
  /// 而不是每次都退回默认档（用户的选择不该被开关抹掉）。
  MangaUpscaleMode _lastUpscaleMode = MangaUpscaleMode.sharpen;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
    if (_draft.upscaleMode.enabled) _lastUpscaleMode = _draft.upscaleMode;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _update(ReaderPreferences next) {
    setState(() => _draft = next);
    widget.onChanged?.call(next);
  }

  /// 是否显示「音量键翻页」设置：Android / 鸿蒙手机（两端都有原生拦截通道，
  /// iOS / 桌面没有）。
  bool get _showVolumeKey =>
      PlatformService.instance.isAndroid || PlatformService.instance.isOHOSPhone;

  // ──────────────────── 构建辅助 ────────────────────

  /// 带标题的设置段（标题 + 子控件）。
  Widget _section(BuildContext context, String label, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          child,
        ],
      ),
    );
  }

  Widget _switchTile(String label, bool value, ValueChanged<bool> onChanged,
      {String? subtitle}) {
    // 统一走设置设计系统的开关行（AppValuePulse + 触感封装）。
    return SettingsSwitchTile(
      title: label,
      subtitle: subtitle,
      value: value,
      onChanged: onChanged,
    );
  }

  String _l(String key) {
    final l10n = AppLocalizations.of(context);
    switch (key) {
      // readingMode
      case 'readerModeSingleLTR':
        return l10n.readerModeSingleLTR;
      case 'readerModeSingleRTL':
        return l10n.readerModeSingleRTL;
      case 'readerModeSingleVertical':
        return l10n.readerModeSingleVertical;
      case 'readerModeWebtoon':
        return l10n.readerModeWebtoon;
      case 'readerModeWebtoonWithGap':
        return l10n.readerModeWebtoonWithGap;
      // orientation
      case 'readerOrientationDefault':
        return l10n.readerOrientationDefault;
      case 'readerOrientationSystem':
        return l10n.readerOrientationSystem;
      case 'readerOrientationPortrait':
        return l10n.readerOrientationPortrait;
      case 'readerOrientationLandscape':
        return l10n.readerOrientationLandscape;
      case 'readerOrientationLockPortrait':
        return l10n.readerOrientationLockPortrait;
      case 'readerOrientationLockLandscape':
        return l10n.readerOrientationLockLandscape;
      case 'readerOrientationReversePortrait':
        return l10n.readerOrientationReversePortrait;
      // background
      case 'readerBgBlack':
        return l10n.readerBgBlack;
      case 'readerBgGray':
        return l10n.readerBgGray;
      case 'readerBgWhite':
        return l10n.readerBgWhite;
      case 'readerBgAuto':
        return l10n.readerBgAuto;
      // tap zone
      case 'readerTapLShape':
        return l10n.readerTapLShape;
      case 'readerTapLeftRight':
        return l10n.readerTapLeftRight;
      case 'readerTapKindle':
        return l10n.readerTapKindle;
      case 'readerTapBothSides':
        return l10n.readerTapBothSides;
      case 'readerTapOff':
        return l10n.readerTapOff;
      // tap invert
      case 'readerTapInvertNone':
        return l10n.readerTapInvertNone;
      case 'readerTapInvertLeftRight':
        return l10n.readerTapInvertLeftRight;
      case 'readerTapInvertUpDown':
        return l10n.readerTapInvertUpDown;
      case 'readerTapInvertAll':
        return l10n.readerTapInvertAll;
      // initial zoom
      case 'readerZoomFitWidth':
        return l10n.readerZoomFitWidth;
      case 'readerZoomFitHeight':
        return l10n.readerZoomFitHeight;
      case 'readerZoomOriginal':
        return l10n.readerZoomOriginal;
      // zoom anchor ()
      case 'readerZoomStartLeft':
        return l10n.readerZoomStartLeft;
      case 'readerZoomStartCenter':
        return l10n.readerZoomStartCenter;
      case 'readerZoomStartRight':
        return l10n.readerZoomStartRight;
      // long-press zoom anchor ()
      case 'readerLongPressAtPress':
        return l10n.readerLongPressAtPress;
      case 'readerLongPressAtCenter':
        return l10n.readerLongPressAtCenter;
      // page animation ()
      case 'readerPageAnimNone':
        return l10n.readerPageAnimNone;
      case 'readerPageAnimSlide':
        return l10n.readerPageAnimSlide;
      case 'readerPageAnimFade':
        return l10n.readerPageAnimFade;
      // clock/battery position ()
      case 'readerClockPosTopLeft':
        return l10n.readerClockPosTopLeft;
      case 'readerClockPosTopRight':
        return l10n.readerClockPosTopRight;
      case 'readerClockPosBottomLeft':
        return l10n.readerClockPosBottomLeft;
      case 'readerClockPosBottomRight':
        return l10n.readerClockPosBottomRight;
      // color profile（ICC 校色近似）
      case 'readerColorProfileNone':
        return l10n.readerColorProfileNone;
      case 'readerColorProfileSrgb':
        return l10n.readerColorProfileSrgb;
      case 'readerColorProfileWarm':
        return l10n.readerColorProfileWarm;
      case 'readerColorProfileCool':
        return l10n.readerColorProfileCool;
      case 'readerColorProfileManga':
        return l10n.readerColorProfileManga;
      case 'readerColorProfilePaper':
        return l10n.readerColorProfilePaper;
      // 图片超分（GPU 实时 shader）
      case 'readerUpscaleOff':
        return l10n.readerUpscaleOff;
      case 'readerUpscaleResample':
        return l10n.readerUpscaleResample;
      case 'readerUpscaleSharpen':
        return l10n.readerUpscaleSharpen;
      default:
        return key;
    }
  }

  // ──────────────────── 各设置的子控件 ────────────────────

  Widget _buildReadingMode() {
    return Wrap(
      spacing: AppTokens.spaceSm,
      runSpacing: AppTokens.spaceSm,
      children: ReadingMode.values.map((m) {
        return ChoiceChip(
          label: Text(_l(m.l10nKey())),
          selected: _draft.readingMode == m,
          onSelected: (_) {
            // 切到竖排 / 长条时双页拆分不再生效，自动关闭。
            final bool compatible =
                m == ReadingMode.singleLTR || m == ReadingMode.singleRTL;
            _update(_draft.copyWith(
              readingMode: m,
              splitDoublePage: compatible ? _draft.splitDoublePage : false,
            ));
          },
        );
      }).toList(),
    );
  }

  Widget _buildBackground() {
    return Wrap(
      spacing: AppTokens.spaceSm,
      runSpacing: AppTokens.spaceSm,
      children: ReaderBackgroundColor.values.map((b) {
        return ChoiceChip(
          label: Text(_l(b.l10nKey())),
          selected: _draft.background == b,
          onSelected: (_) => _update(_draft.copyWith(background: b)),
        );
      }).toList(),
    );
  }

  Widget _buildOrientation() {
    return Wrap(
      spacing: AppTokens.spaceSm,
      runSpacing: AppTokens.spaceSm,
      children: ScreenOrientation.values.map((o) {
        return ChoiceChip(
          label: Text(_l(o.l10nKey())),
          selected: _draft.orientation == o,
          onSelected: (_) => _update(_draft.copyWith(orientation: o)),
        );
      }).toList(),
    );
  }

  Widget _buildTapZone() {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: AppTokens.spaceSm,
          runSpacing: AppTokens.spaceSm,
          children: <ReaderTapZoneLayout>[
            ReaderTapZoneLayout.lShape,
            ReaderTapZoneLayout.leftRight,
            ReaderTapZoneLayout.kindle,
            ReaderTapZoneLayout.bothSides,
            ReaderTapZoneLayout.off,
          ].map((t) {
            return ChoiceChip(
              label: Text(_l(t.l10nKey())),
              selected: _draft.tapZoneLayout == t,
              onSelected: (_) => _update(_draft.copyWith(tapZoneLayout: t)),
            );
          }).toList(),
        ),
        const SizedBox(height: AppTokens.spaceSm),
        Text(l10n.readerTapPreviewHint,
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: AppTokens.spaceXs),
        SizedBox(
          height: 140,
          child: ReaderTapZones(
            showPreview: true,
            layout: _draft.tapZoneLayout,
            tapZoneInvert: _draft.tapZoneInvert,
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
      ],
    );
  }

  Widget _buildTapInvert() {
    return Wrap(
      spacing: AppTokens.spaceSm,
      runSpacing: AppTokens.spaceSm,
      children: TapZoneInvert.values.map((t) {
        return ChoiceChip(
          label: Text(_l(t.l10nKey())),
          selected: _draft.tapZoneInvert == t,
          onSelected: (_) => _update(_draft.copyWith(tapZoneInvert: t)),
        );
      }).toList(),
    );
  }

  Widget _buildInitialZoom() {
    return Wrap(
      spacing: AppTokens.spaceSm,
      runSpacing: AppTokens.spaceSm,
      children: ReaderInitialZoom.values.map((z) {
        return ChoiceChip(
          label: Text(_l(z.l10nKey())),
          selected: _draft.initialZoom == z,
          onSelected: (_) => _update(_draft.copyWith(initialZoom: z)),
        );
      }).toList(),
    );
  }

  /// 缩放锚点：双击 / 长按缩放的锚点来源。
  Widget _buildZoomStart() {
    return Wrap(
      spacing: AppTokens.spaceSm,
      runSpacing: AppTokens.spaceSm,
      children: ZoomStart.values.map((z) {
        return ChoiceChip(
          label: Text(_l(z.l10nKey())),
          selected: _draft.zoomStart == z,
          onSelected: (_) => _update(_draft.copyWith(zoomStart: z)),
        );
      }).toList(),
    );
  }

  /// 长按缩放锚点：按触点 / 按屏幕中心。
  Widget _buildLongPressZoomPosition() {
    return Wrap(
      spacing: AppTokens.spaceSm,
      runSpacing: AppTokens.spaceSm,
      children: LongPressZoomPosition.values.map((p) {
        return ChoiceChip(
          label: Text(_l(p.l10nKey())),
          selected: _draft.longPressZoomPosition == p,
          onSelected: (_) => _update(_draft.copyWith(longPressZoomPosition: p)),
        );
      }).toList(),
    );
  }

  /// 翻页过渡动画：无动画 / 滑入 / 淡入淡出。
  Widget _buildPageAnimation() {
    return Wrap(
      spacing: AppTokens.spaceSm,
      runSpacing: AppTokens.spaceSm,
      children: ReaderPageAnimation.values.map((a) {
        return ChoiceChip(
          label: Text(_l(a.l10nKey())),
          selected: _draft.pageAnimation == a,
          onSelected: (_) => _update(_draft.copyWith(pageAnimation: a)),
        );
      }).toList(),
    );
  }

  /// 自动翻页：开关 + 间隔滑块（仅 paged 模式有意义，条漫自动滚动走
  /// [_buildAutoScroll]）。
  Widget _buildAutoPageTurning() {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _switchTile(l10n.readerAutoPageTurning, _draft.autoPageTurningEnabled,
            (v) {
          // 关闭只切开关、保留间隔；重新开启恢复上次间隔，从未设置过才兜底 5。
          final int cur = _draft.autoPageTurningInterval;
          _update(_draft.copyWith(
            autoPageTurningEnabled: v,
            autoPageTurningInterval: v && cur <= 0 ? 5 : cur,
          ));
        }),
        if (_draft.autoPageTurningEnabled)
          _SliderRow(
            label: l10n.readerAutoPageInterval,
            value: _draft.autoPageTurningInterval.clamp(1, 20).toDouble(),
            min: 1,
            max: 20,
            divisions: 19,
            displayValue: '${_draft.autoPageTurningInterval.clamp(1, 20)}s',
            onChanged: (v) =>
                _update(_draft.copyWith(autoPageTurningInterval: v.round())),
          ),
      ],
    );
  }

  /// 音量键翻页（Android / 鸿蒙）：开关 + 条漫滚动距离滑块。
  Widget _buildVolumeKey() {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _switchTile(l10n.readerVolumeKeyPageTurn, _draft.volumeKeyPageTurn,
            (v) => _update(_draft.copyWith(volumeKeyPageTurn: v))),
        if (_draft.volumeKeyPageTurn)
          _SliderRow(
            label: l10n.readerVolumeKeyDistance,
            value: _draft.volumeKeyPageTurnDistancePercent.toDouble(),
            min: 10,
            max: 100,
            divisions: 18,
            displayValue: '${_draft.volumeKeyPageTurnDistancePercent}%',
            onChanged: (v) => _update(
                _draft.copyWith(volumeKeyPageTurnDistancePercent: v.round())),
          ),
      ],
    );
  }

  /// 睡眠定时（跨类型对齐）：按分钟 / 按话数。会话级状态，由阅读器持有
  /// Timer 生命周期，此处只做选择交互（播放器 picker 同构）。
  Widget _buildSleepTimer() {
    final l10n = AppLocalizations.of(context);
    final ComicSleepTimerState? st = widget.sleepTimer;
    final String summary = switch (st?.mode) {
      ComicSleepTimerMode.minutes => l10n.playerTimerMinutes(st!.value),
      ComicSleepTimerMode.chapters => l10n.readerSleepTimerChapters(st!.value),
      _ => l10n.readerSleepTimerOff,
    };
    return SettingsTile(
      icon: Icons.bedtime_rounded,
      title: l10n.readerSleepTimer,
      subtitle: summary,
      onTap: () => _showSleepTimerPicker(l10n),
    );
  }

  /// 睡眠定时选择底部弹层：关闭 / 预设分钟 / 按话数 / 自定义分钟。
  void _showSleepTimerPicker(AppLocalizations l10n) {
    final ComicSleepTimerState? cur = widget.sleepTimer;
    final bool offSelected = cur == null ||
        (cur.mode != ComicSleepTimerMode.minutes &&
            cur.mode != ComicSleepTimerMode.chapters);
    Widget option({
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return ListTile(
        title: Text(label),
        trailing: selected
            ? Icon(Icons.check_rounded,
                color: Theme.of(context).colorScheme.primary, size: 22)
            : null,
        onTap: onTap,
      );
    }

    // 与设置页「行 + 选中 check」弹层语言一致。
    showModalBottomSheet<void>(
      context: context,
      // 内容行数较多，矮窗口下必须可滚动（否则 RenderFlex 溢出）。
      isScrollControlled: true,
      builder: (BuildContext ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.8,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.spaceLg,
                    AppTokens.spaceMd,
                    AppTokens.spaceLg,
                    AppTokens.spaceSm,
                  ),
                  child: Text(
                    l10n.readerSleepTimer,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                option(
                  label: l10n.readerSleepTimerOff,
                  selected: offSelected,
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onSleepTimerChanged
                        ?.call(const ComicSleepTimerState.off());
                  },
                ),
                for (final m in <int>[15, 30, 45, 60, 90])
                  option(
                    label: l10n.playerTimerMinutes(m),
                    selected: cur?.mode == ComicSleepTimerMode.minutes &&
                        cur?.value == m,
                    onTap: () {
                      Navigator.pop(ctx);
                      widget.onSleepTimerChanged
                          ?.call(ComicSleepTimerState.minutes(m));
                    },
                  ),
                for (final n in <int>[1, 2, 3])
                  option(
                    label: l10n.readerSleepTimerChapters(n),
                    selected: cur?.mode == ComicSleepTimerMode.chapters &&
                        cur?.value == n,
                    onTap: () {
                      Navigator.pop(ctx);
                      widget.onSleepTimerChanged
                          ?.call(ComicSleepTimerState.chapters(n));
                    },
                  ),
                option(
                  label: l10n.playerTimerCustom,
                  selected: false,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showCustomSleepTimerDialog(l10n);
                  },
                ),
                const SizedBox(height: AppTokens.spaceSm),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 自定义分钟输入框（>0 生效）。
  void _showCustomSleepTimerDialog(AppLocalizations l10n) {
    final TextEditingController controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AppAlertDialog(
        title: Text(l10n.readerSleepTimer),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: l10n.playerTimerCustom),
          autofocus: true,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              final m = int.tryParse(controller.text.trim());
              if (m != null && m > 0) {
                Navigator.pop(ctx);
                widget.onSleepTimerChanged
                    ?.call(ComicSleepTimerState.minutes(m));
              }
            },
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }

  /// 时间/电量浮层。
  Widget _buildClockBattery() {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _switchTile(l10n.readerClockBattery, _draft.showClockBattery,
            (v) => _update(_draft.copyWith(showClockBattery: v))),
        if (_draft.showClockBattery) ...<Widget>[
          const SizedBox(height: AppTokens.spaceSm),
          Text(l10n.readerClockPosition,
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppTokens.spaceXs),
          Wrap(
            spacing: AppTokens.spaceSm,
            runSpacing: AppTokens.spaceSm,
            children: ClockBatteryPosition.values.map((p) {
              return ChoiceChip(
                label: Text(_l(p.l10nKey())),
                selected: _draft.clockBatteryPosition == p,
                onSelected: (_) =>
                    _update(_draft.copyWith(clockBatteryPosition: p)),
              );
            }).toList(),
          ),
          _SliderRow(
            label: l10n.readerClockMargin,
            value: _draft.clockBatteryMargin,
            min: 0,
            max: 40,
            divisions: 40,
            displayValue: '${_draft.clockBatteryMargin.round()}',
            onChanged: (v) => _update(_draft.copyWith(clockBatteryMargin: v)),
          ),
          _SliderRow(
            label: l10n.readerClockOpacity,
            value: _draft.clockBatteryOpacity,
            min: 0.1,
            max: 1.0,
            divisions: 9,
            displayValue: _draft.clockBatteryOpacity.toStringAsFixed(1),
            onChanged: (v) => _update(_draft.copyWith(clockBatteryOpacity: v)),
          ),
          _SliderRow(
            label: l10n.readerClockFontSize,
            value: _draft.clockBatteryFontSize,
            min: 10,
            max: 24,
            divisions: 14,
            displayValue: '${_draft.clockBatteryFontSize.round()}',
            onChanged: (v) => _update(_draft.copyWith(clockBatteryFontSize: v)),
          ),
        ],
      ],
    );
  }

  /// 多图/间距（/ /）。
  Widget _buildMultiImageSpacing() {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SliderRow(
          label: l10n.readerPageSpacing,
          value: _draft.readerPageSpacing.toDouble(),
          min: 0,
          max: 50,
          divisions: 50,
          displayValue: '${_draft.readerPageSpacing}',
          onChanged: (v) =>
              _update(_draft.copyWith(readerPageSpacing: v.round())),
        ),
        _SliderRow(
          label: l10n.readerScreenPicNumberPortrait,
          value: _draft.readerScreenPicNumberForPortrait.toDouble(),
          min: 1,
          max: 5,
          divisions: 4,
          displayValue: '${_draft.readerScreenPicNumberForPortrait}',
          onChanged: (v) => _update(
              _draft.copyWith(readerScreenPicNumberForPortrait: v.round())),
        ),
        _SliderRow(
          label: l10n.readerScreenPicNumberLandscape,
          value: _draft.readerScreenPicNumberForLandscape.toDouble(),
          min: 1,
          max: 5,
          divisions: 4,
          displayValue: '${_draft.readerScreenPicNumberForLandscape}',
          onChanged: (v) => _update(
              _draft.copyWith(readerScreenPicNumberForLandscape: v.round())),
        ),
      ],
    );
  }

  /// 自动滚动（条漫）：开关 + 滚动速度倍率滑块。
  Widget _buildAutoScroll() {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _switchTile(l10n.readerAutoScroll, _draft.autoScroll,
            (v) => _update(_draft.copyWith(autoScroll: v))),
        _SliderRow(
          label: l10n.readerScrollSpeed,
          value: _draft.readerScrollSpeed,
          min: 0.5,
          max: 3.0,
          divisions: 25,
          displayValue: '${_draft.readerScrollSpeed.toStringAsFixed(1)}x',
          onChanged: (v) => _update(_draft.copyWith(readerScrollSpeed: v)),
        ),
      ],
    );
  }

  Widget _buildImageFilter() {
    return ReaderImageFilterPanel(
      brightness: _draft.filterBrightness,
      contrast: _draft.filterContrast,
      colorTemp: _draft.filterColorTemp,
      saturation: _draft.filterSaturation,
      hue: _draft.filterHue,
      inverted: _draft.filterInverted,
      grayscale: _draft.filterGrayscale,
      onChanged: (b, c, t, s, h) => _update(_draft.copyWith(
        filterBrightness: b,
        filterContrast: c,
        filterColorTemp: t,
        filterSaturation: s,
        filterHue: h,
      )),
      onInvertedChanged: (v) => _update(_draft.copyWith(filterInverted: v)),
      onGrayscaleChanged: (v) => _update(_draft.copyWith(filterGrayscale: v)),
    );
  }

  /// 图片超分（GPU 实时 shader）：总开关 + 档位选择。
  ///
  /// 档位**自动隐显**：开关打开平滑展开、关闭自动收起（AnimatedSize 高度
  /// 过渡 + 淡入上滑，与卡片折叠手感一致），不用置灰常驻也不生硬跳变。
  /// 冷启动即预加载 shader 资源，避免首次开启时首帧抖动；Web 平台不显示
  /// 该入口（FragmentProgram 不可用，避免给出一个必然无效的开关）。
  Widget _buildUpscale() {
    final l10n = AppLocalizations.of(context);
    if (!MangaUpscaleShader.isSupported) {
      return Text(
        l10n.readerUpscaleDesc,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
    }
    MangaUpscaleShader.warmUp();
    final bool on = _draft.upscaleMode.enabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _switchTile(
          l10n.readerUpscale,
          on,
          (bool v) => _update(_draft.copyWith(
            upscaleMode: v ? _lastUpscaleMode : MangaUpscaleMode.off,
          )),
          subtitle: l10n.readerUpscaleDesc,
        ),
        // 档位自动隐显：开关开启时平滑展开，关闭时自动收起。
        AnimatedSize(
          duration: AppTokens.durBase,
          curve: AppCurves.smooth,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: AppTokens.durBase,
            switchInCurve: AppCurves.smooth,
            switchOutCurve: Curves.easeOutCubic,
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -0.04),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: on
                ? Padding(
                    key: const ValueKey<String>('upscale-modes-open'),
                    padding: const EdgeInsets.only(
                      left: AppTokens.spaceXs,
                      bottom: AppTokens.spaceMd,
                    ),
                    child: Wrap(
                      spacing: AppTokens.spaceSm,
                      runSpacing: AppTokens.spaceSm,
                      children: <MangaUpscaleMode>[
                        MangaUpscaleMode.resample,
                        MangaUpscaleMode.sharpen,
                      ].map((MangaUpscaleMode m) {
                        return ChoiceChip(
                          label: Text(_l(m.l10nKey())),
                          selected: _draft.upscaleMode == m,
                          onSelected: (_) {
                            _lastUpscaleMode = m;
                            _update(_draft.copyWith(upscaleMode: m));
                          },
                        );
                      }).toList(),
                    ),
                  )
                : const SizedBox(
                    key: ValueKey<String>('upscale-modes-closed'),
                    width: double.infinity,
                  ),
          ),
        ),
      ],
    );
  }

  /// 色彩配置（ICC 校色近似）：分段选择色彩矩阵预设。
  Widget _buildColorProfile() {
    return Wrap(
      spacing: AppTokens.spaceSm,
      runSpacing: AppTokens.spaceSm,
      children: ReaderColorProfile.values.map((c) {
        return ChoiceChip(
          label: Text(_l(c.l10nKey())),
          selected: _draft.colorProfile == c,
          onSelected: (_) => _update(_draft.copyWith(colorProfile: c)),
        );
      }).toList(),
    );
  }

  // ──────────────────── 常用设置卡片 ────────────────────

  /// 置顶的「常用设置」卡片：高频快捷项，搜索时隐藏（避免与过滤重叠）。
  Widget _buildCommonCard(AppLocalizations l10n) {
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
                    l10n.readerCommonSettings,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.spaceSm),
              _section(context, l10n.readerMode, _buildReadingMode()),
              _section(context, l10n.readerBackground, _buildBackground()),
              _section(context, l10n.readerOrientation, _buildOrientation()),
              Padding(
                padding: const EdgeInsets.only(bottom: AppTokens.spaceMd),
                child: _SliderRow(
                  label: l10n.readerSideMargin,
                  value: _draft.sideMargin,
                  min: 0.0,
                  max: 0.5,
                  divisions: 50,
                  displayValue: '${(_draft.sideMargin * 100).round()}%',
                  onChanged: (v) => _update(_draft.copyWith(sideMargin: v)),
                ),
              ),
              _switchTile(l10n.readerZoom, _draft.doubleTapZoom,
                  (v) => _update(_draft.copyWith(doubleTapZoom: v))),
              _switchTile(l10n.readerFullscreen, _draft.fullscreen,
                  (v) => _update(_draft.copyWith(fullscreen: v))),
              _switchTile(l10n.readerKeepScreenOn, _draft.keepScreenOn,
                  (v) => _update(_draft.copyWith(keepScreenOn: v))),
              _switchTile(
                  l10n.readerProgressBarOnRight,
                  _draft.progressBarOnRight,
                  (v) => _update(_draft.copyWith(progressBarOnRight: v))),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────── 顶层构建 ────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final q = _searchController.text.trim();

    return Container(
      constraints: BoxConstraints(
        // 上下铺满：设置面板撑满整个视口高度（与小说阅读器弹窗一致）。
        maxHeight: MediaQuery.of(context).size.height,
      ),
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceLg,
        AppTokens.spaceMd,
        AppTokens.spaceLg,
        AppTokens.spaceMd,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 搜索框（固定，不随滚动消失；去掉标题行以扩大内容区）
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: l10n.readerSearchSettings,
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
          // 可滚动内容
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // 常用置顶：最常改的快捷项（搜索时隐藏，避免与过滤重叠）
                  if (q.isEmpty) _buildCommonCard(l10n),

                  // ── 翻页与点击 ────────────────────────────────
                  _buildSettingsGroup(
                    context,
                    l10n.readerGroupPageTap,
                    description: l10n.readerGroupPageTapDesc,
                    leading: Icons.swipe_rounded,
                    initiallyExpanded: true,
                    searchQuery: q,
                    searchTerms: const <String>[
                      '翻页',
                      '点击',
                      '阅读模式',
                      '单页',
                      '竖排',
                      '长条',
                      '条漫',
                      '方向',
                      '屏幕',
                      '横屏',
                      '竖屏',
                      '背景',
                      '侧边距',
                      '缩放',
                      '双击',
                      '点按',
                      '区域',
                      'tap',
                      'webtoon',
                      '方向',
                      'page',
                      '锚点',
                      '长按缩放',
                      '翻页动画',
                      '音量键',
                      '音量',
                      'zoom',
                      'anchor',
                      'fade',
                      'volume',
                      'auto',
                      '双击缩放动画',
                      '初始缩放',
                      '长按缩放锚点',
                      '屏幕方向',
                      '翻页过渡动画',
                      '左右留白',
                      '点击翻转',
                      '点击区域',
                      '双击缩放',
                      '缩放锚点',
                      '动画速度',
                    ],
                    children: <Widget>[
                      _section(context, l10n.readerMode, _buildReadingMode()),
                      _section(
                          context, l10n.readerBackground, _buildBackground()),
                      _section(
                          context, l10n.readerOrientation, _buildOrientation()),
                      _section(context, l10n.readerTapZone, _buildTapZone()),
                      _section(
                          context, l10n.readerTapInvert, _buildTapInvert()),
                      Padding(
                        padding:
                            const EdgeInsets.only(bottom: AppTokens.spaceMd),
                        child: _SliderRow(
                          label: l10n.readerSideMargin,
                          value: _draft.sideMargin,
                          min: 0.0,
                          max: 0.5,
                          divisions: 50,
                          displayValue: '${(_draft.sideMargin * 100).round()}%',
                          onChanged: (v) =>
                              _update(_draft.copyWith(sideMargin: v)),
                        ),
                      ),
                      _switchTile(l10n.readerZoom, _draft.doubleTapZoom,
                          (v) => _update(_draft.copyWith(doubleTapZoom: v))),
                      _section(
                          context, l10n.readerInitialZoom, _buildInitialZoom()),
                      // 缩放锚点
                      _section(
                          context, l10n.readerZoomStart, _buildZoomStart()),
                      // 长按缩放：开启时显示锚点选择
                      _switchTile(
                          l10n.readerLongPressZoom,
                          _draft.enableLongPressToZoom,
                          (v) => _update(
                              _draft.copyWith(enableLongPressToZoom: v))),
                      if (_draft.enableLongPressToZoom)
                        _section(context, l10n.readerLongPressZoomPosition,
                            _buildLongPressZoomPosition()),
                      // 翻页过渡动画
                      _section(context, l10n.readerPageAnimation,
                          _buildPageAnimation()),
                      // 双击缩放动画时长
                      Padding(
                        padding:
                            const EdgeInsets.only(bottom: AppTokens.spaceMd),
                        child: _SliderRow(
                          label: l10n.readerDoubleTapAnimSpeed,
                          value: _draft.doubleTapAnimSpeed.toDouble(),
                          min: 100,
                          max: 1500,
                          divisions: 14,
                          displayValue: '${_draft.doubleTapAnimSpeed}ms',
                          onChanged: (v) => _update(
                              _draft.copyWith(doubleTapAnimSpeed: v.round())),
                        ),
                      ),
                      // 音量键翻页（仅 Android）
                      if (_showVolumeKey) _buildVolumeKey(),
                    ],
                  ),

                  // ── 动态效果（独立分类，默认折叠）──────────────
                  _buildSettingsGroup(
                    context,
                    l10n.motionEffectTitle,
                    description: l10n.motionEffectDesc,
                    leading: Icons.animation_rounded,
                    initiallyExpanded: false,
                    searchQuery: q,
                    searchTerms: const <String>[
                      '动态效果',
                      '动效',
                      '视差',
                      '呼吸',
                      '粒子',
                      '樱花',
                      '预设',
                      'motion',
                    ],
                    children: <Widget>[
                      MotionEffectsAdjustments(
                        settings: _draft.motionEffects,
                        onChanged: (next) =>
                            _update(_draft.copyWith(motionEffects: next)),
                      ),
                    ],
                  ),

                  // ── 画面与滤镜 ────────────────────────────────
                  _buildSettingsGroup(
                    context,
                    l10n.readerGroupViewFilter,
                    description: l10n.readerGroupViewFilterDesc,
                    leading: Icons.tune_rounded,
                    searchQuery: q,
                    searchTerms: const <String>[
                      '亮度',
                      '对比度',
                      '色温',
                      '灰度',
                      '反色',
                      '滤镜',
                      '画面',
                      '颜色',
                      '饱和',
                      '色调',
                      'filter',
                      'brightness',
                      'contrast',
                      '阅读亮度',
                      '色彩配置',
                      '夜览',
                      '夜览强度',
                      '暖色',
                      '盖层',
                      // 图片超分（GPU 实时 shader）
                      '超分',
                      '图片超分',
                      '分辨率',
                      '画质',
                      '增强',
                      '锐化',
                      '重采样',
                      '放大',
                      '清晰',
                      'upscale',
                    ],
                    children: <Widget>[
                      _buildImageFilter(),
                      // 色彩配置（ICC 校色近似）：矩阵预设
                      _section(context, l10n.readerColorProfile,
                          _buildColorProfile()),
                      // 图片超分（GPU 实时 shader）：开关自带标题，不再套 _section
                      // （否则「图片超分」会作为小标题与开关标题重复渲染两遍）。
                      _buildUpscale(),
                      // 阅读亮度：独立于滤镜，控制系统亮度/黑色遮罩。
                      Padding(
                        padding:
                            const EdgeInsets.only(bottom: AppTokens.spaceMd),
                        child: _SliderRow(
                          label: l10n.readerBrightness,
                          value: _draft.readerBrightness,
                          min: -1.0,
                          max: 1.0,
                          divisions: 40,
                          displayValue:
                              _draft.readerBrightness.toStringAsFixed(2),
                          onChanged: (v) =>
                              _update(_draft.copyWith(readerBrightness: v)),
                        ),
                      ),
                      // 夜览暖色盖层（亮度双轨扩展）：独立于阅读亮度。
                      _switchTile(
                          l10n.readerNightLight,
                          _draft.nightLightEnabled,
                          (v) =>
                              _update(_draft.copyWith(nightLightEnabled: v))),
                      if (_draft.nightLightEnabled)
                        Padding(
                          padding:
                              const EdgeInsets.only(bottom: AppTokens.spaceMd),
                          child: _SliderRow(
                            label: l10n.readerNightLightOpacity,
                            value: _draft.nightLightOpacity,
                            min: 0.1,
                            max: 0.85,
                            divisions: 15,
                            displayValue:
                                '${(_draft.nightLightOpacity * 100).round()}%',
                            onChanged: (v) =>
                                _update(_draft.copyWith(nightLightOpacity: v)),
                          ),
                        ),
                    ],
                  ),

                  // ── 进度与显示 ────────────────────────────────
                  _buildSettingsGroup(
                    context,
                    l10n.readerGroupProgress,
                    description: l10n.readerGroupProgressDesc,
                    leading: Icons.timeline_rounded,
                    searchQuery: q,
                    searchTerms: const <String>[
                      '页码',
                      '进度',
                      '进度条',
                      '全屏',
                      '常亮',
                      '旋转',
                      '双页',
                      '分屏',
                      '长按',
                      '防缩',
                      '章节',
                      '过渡',
                      '显示',
                      'page',
                      'fullscreen',
                      'screen',
                      '自动滚动',
                      '滚动速度',
                      'auto scroll',
                      'scroll speed',
                      '自动翻页',
                      '翻页间隔',
                      '首屏单图',
                      '单图',
                      'auto page turn',
                      '章节滑块',
                      'chapter slider',
                      '裁边',
                      '显示页码',
                      '进度条在右侧',
                      '章节导航滑块',
                      '章节过渡',
                      '章分割过渡',
                      '屏幕常亮',
                      '长按菜单',
                      '预加载数量',
                      '防止缩小',
                      '旋转页面',
                      '跨章无缝续读',
                      '双页拆分',
                      '宽屏自动双页',
                      '条漫解码限幅',
                    ],
                    children: <Widget>[
                      _switchTile(l10n.readerCropEdge, _draft.cropEdge,
                          (v) => _update(_draft.copyWith(cropEdge: v))),
                      _switchTile(
                          l10n.readerShowPageNumber,
                          _draft.showPageNumber,
                          (v) => _update(_draft.copyWith(showPageNumber: v))),
                      _switchTile(
                          l10n.readerProgressBarOnRight,
                          _draft.progressBarOnRight,
                          (v) =>
                              _update(_draft.copyWith(progressBarOnRight: v))),
                      _switchTile(
                          l10n.readerShowChapterSlider,
                          _draft.showChapterSlider,
                          (v) =>
                              _update(_draft.copyWith(showChapterSlider: v))),
                      _switchTile(l10n.readerKeepScreenOn, _draft.keepScreenOn,
                          (v) => _update(_draft.copyWith(keepScreenOn: v))),
                      _switchTile(l10n.readerRotatePage, _draft.rotateLandscape,
                          (v) => _update(_draft.copyWith(rotateLandscape: v))),
                      _switchTile(
                          l10n.readerSplitDoublePage, _draft.splitDoublePage,
                          (v) {
                        ReaderPreferences next =
                            _draft.copyWith(splitDoublePage: v);
                        if (v &&
                            _draft.readingMode != ReadingMode.singleLTR &&
                            _draft.readingMode != ReadingMode.singleRTL) {
                          next =
                              next.copyWith(readingMode: ReadingMode.singleLTR);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.readerSplitDoublePageHint),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                        _update(next);
                      }),
                      // 宽屏自动双页：平板横屏 / 桌面宽窗口自动启用跨页（默认关）。
                      _switchTile(
                          l10n.readerAutoDoublePageOnWide,
                          _draft.autoDoublePageOnWide,
                          (v) =>
                              _update(_draft.copyWith(autoDoublePageOnWide: v))),
                      // 首屏单图：双页模式第一章首页单独显示，其后恢复双页。
                      _switchTile(
                          l10n.readerShowSingleImageOnFirstPage,
                          _draft.showSingleImageOnFirstPage,
                          (v) => _update(
                              _draft.copyWith(showSingleImageOnFirstPage: v))),
                      _switchTile(l10n.readerFullscreen, _draft.fullscreen,
                          (v) => _update(_draft.copyWith(fullscreen: v))),
                      _switchTile(
                          l10n.readerLongPressMenu,
                          _draft.showLongPressMenu,
                          (v) =>
                              _update(_draft.copyWith(showLongPressMenu: v))),
                      _switchTile(
                          l10n.readerPreventShrink,
                          _draft.preventShrink,
                          (v) => _update(_draft.copyWith(preventShrink: v))),
                      _switchTile(
                          l10n.readerChapterTransition,
                          _draft.showChapterTransition,
                          (v) => _update(
                              _draft.copyWith(showChapterTransition: v))),
                      _SliderRow(
                        label: l10n.readerPreloadCount,
                        value: _draft.preloadImageCount.toDouble(),
                        min: 1,
                        max: 16,
                        divisions: 15,
                        displayValue: '${_draft.preloadImageCount}',
                        onChanged: (v) => _update(
                            _draft.copyWith(preloadImageCount: v.round())),
                      ),
                      _switchTile(
                          l10n.readerSeamlessReading,
                          _draft.seamlessReading,
                          (v) => _update(_draft.copyWith(seamlessReading: v))),
                      // 章分割/过渡条目仅对 webtoon（条漫）连续模式生效。
                      _switchTile(
                          l10n.readerChapterSeparator,
                          _draft.showChapterSeparator,
                          (v) => _update(
                              _draft.copyWith(showChapterSeparator: v))),
                      // 条漫解码限幅（资源/内存）：连续模式解码位图下采样，
                      // 限制长条漫原图的全尺寸解码内存。
                      _switchTile(
                          l10n.readerWebtoonDecodeLimit,
                          _draft.webtoonLimitDecodeSize,
                          (v) => _update(
                              _draft.copyWith(webtoonLimitDecodeSize: v))),
                      // 自动翻页（paged）：开关 + 间隔。
                      _buildAutoPageTurning(),
                      // 自动滚动（条漫）：开关 + 滚动速度。
                      _buildAutoScroll(),
                      // 漫画翻译：开启后对当前页 OCR+翻译并以气泡覆盖层显示。
                      _switchTile(
                          l10n.comicTranslateSettingLabel,
                          _draft.translationEnabled,
                          (v) =>
                              _update(_draft.copyWith(translationEnabled: v))),
                      // 排版回填：译文以描边文字回填气泡内（自适应字号）。
                      _switchTile(
                        l10n.comicTranslateBackfillLabel,
                        _draft.translationBackfill,
                        subtitle: l10n.comicTranslateBackfillDesc,
                        (v) => _update(_draft.copyWith(translationBackfill: v)),
                      ),
                    ],
                  ),

                  // ── 睡眠定时────────────────────────────
                  _buildSettingsGroup(
                    context,
                    l10n.readerSleepTimer,
                    description: l10n.readerSleepTimerDesc,
                    leading: Icons.bedtime_rounded,
                    searchQuery: q,
                    searchTerms: const <String>[
                      '睡眠',
                      '定时',
                      '暂停',
                      '分钟',
                      '话数',
                      'sleep',
                      'timer',
                      'minute',
                      'chapter',
                    ],
                    children: <Widget>[
                      _buildSleepTimer(),
                    ],
                  ),

                  // ── 浮层（时间/电量）───────────────────────────
                  _buildSettingsGroup(
                    context,
                    l10n.readerGroupOverlay,
                    description: l10n.readerGroupOverlayDesc,
                    leading: Icons.access_time_rounded,
                    searchQuery: q,
                    searchTerms: const <String>[
                      '时间',
                      '电量',
                      '浮层',
                      '时钟',
                      '电池',
                      '位置',
                      '边距',
                      '透明度',
                      '字号',
                      'clock',
                      'battery',
                      'overlay',
                      'time',
                    ],
                    children: <Widget>[
                      _buildClockBattery(),
                    ],
                  ),

                  // ── 多图与间距 ────────────────────────────────
                  _buildSettingsGroup(
                    context,
                    l10n.readerGroupMulti,
                    description: l10n.readerGroupMultiDesc,
                    leading: Icons.grid_view_rounded,
                    searchQuery: q,
                    searchTerms: const <String>[
                      '多图',
                      '间距',
                      '竖屏',
                      '横屏',
                      '每屏',
                      'multi',
                      'spacing',
                      'page',
                      'single',
                      'image',
                      'portrait',
                      'landscape',
                      'screen',
                    ],
                    children: <Widget>[
                      _buildMultiImageSpacing(),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 通用滑块行（标签 + 滑块 + 数值）。
class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String displayValue;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.displayValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // 统一走设置设计系统的滑块行（标签上、primary 值右、全宽滑块、逐档 tick）。
    return SettingsSliderTile(
      label: label,
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      display: displayValue,
      onChanged: onChanged,
    );
  }
}

/// 设置分组卡片（可折叠）。标题 + 可选说明 + 可选图标；搜索时按标题/说明/别名过滤。
///
/// 与小说阅读器 [_buildSettingsGroup] 行为一致：搜索词非空时，仅当组标题、说明或
/// [searchTerms] 命中才显示本组，否则折叠为空白。
///
/// 搜索命中时**强制展开**：只过滤不展开会让「搜到了但看不见」（组标题在、内容
/// 折叠），用户会以为功能不存在——超分入口就踩过这个坑。
Widget _buildSettingsGroup(
  BuildContext context,
  String title, {
  String? description,
  bool initiallyExpanded = false,
  IconData? leading,
  List<String> searchTerms = const <String>[],
  String searchQuery = '',
  required List<Widget> children,
}) {
  final q = searchQuery.trim().toLowerCase();
  final bool searching = q.isNotEmpty;
  if (searching) {
    final hay = <String>[
      title,
      if (description != null) description,
      ...searchTerms,
    ].join(' ').toLowerCase();
    if (!hay.contains(q)) return const SizedBox.shrink();
  }
  // 搜索命中即展开：ExpansionTile 的 initiallyExpanded 只在首帧生效，
  // 因此用 Key 随搜索态变化来重建，确保命中项内容直接可见。
  final bool expanded = searching || initiallyExpanded;
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
          key: ValueKey<String>('settings-group-$title-$expanded'),
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
          initiallyExpanded: expanded,
          title: description == null || description.isEmpty
              ? Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppTokens.spaceXxs),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
          children: children,
        ),
      ),
    ),
  );
}
