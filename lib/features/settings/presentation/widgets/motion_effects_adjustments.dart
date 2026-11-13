/// 动态效果完整调节面板（共享组件）。
///
/// 三处复用，由调用方决定 [settings] / [onChanged] 写到哪一层：
/// - 动态效果设置详情页（全局默认仓库）；
/// - 漫画阅读设置页「动态效果」卡片（全局默认仓库）；
/// - 阅读器内联面板「动态效果」分组（本书会话草稿）。
///
/// 包含全部调节项：主开关、快速预设、条漫渲染时机、画质滑杆（帧率 /
/// 循环时长 / 分辨率上限）、四组逐效果开关与参数滑杆。
library;

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../../../../core/comic/models/motion_effect_settings.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/app_haptics.dart';
import 'settings_widgets.dart';

/// 动态效果调节面板。受控组件：[settings] 变化经 [onChanged] 回传新值。
class MotionEffectsAdjustments extends StatelessWidget {
  const MotionEffectsAdjustments({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final MotionEffectSettings settings;
  final ValueChanged<MotionEffectSettings> onChanged;

  // ── 文案映射 ──

  static String _groupLabel(AppLocalizations l10n, String group) {
    return switch (group) {
      MotionEffectCatalog.groupAmbient => l10n.motionGroupAmbient,
      MotionEffectCatalog.groupParticles => l10n.motionGroupParticles,
      MotionEffectCatalog.groupLight => l10n.motionGroupLight,
      MotionEffectCatalog.groupManga => l10n.motionGroupManga,
      _ => group,
    };
  }

  static String _effectLabel(AppLocalizations l10n, MotionEffectSpec spec) {
    return switch (spec.kind) {
      'parallax' => l10n.motionFxParallax,
      'breathing' => l10n.motionFxBreathing,
      'slowPush' => l10n.motionFxSlowPush,
      'heartbeat' => l10n.motionFxHeartbeat,
      'toneShift' => l10n.motionFxToneShift,
      'vignette' => l10n.motionFxVignette,
      'ambient' => l10n.motionFxAmbient,
      'dust' => l10n.motionFxDust,
      'rain' => l10n.motionFxRain,
      'snow' => l10n.motionFxSnow,
      'sakura' => l10n.motionFxSakura,
      'leaves' => l10n.motionFxLeaves,
      'bubbles' => l10n.motionFxBubbles,
      'fireflies' => l10n.motionFxFireflies,
      'embers' => l10n.motionFxEmbers,
      'meteors' => l10n.motionFxMeteors,
      'fog' => l10n.motionFxFog,
      'smoke' => l10n.motionFxSmoke,
      'flame' => l10n.motionFxFlame,
      'godRays' => l10n.motionFxGodRays,
      'lightSweep' => l10n.motionFxLightSweep,
      'shimmer' => l10n.motionFxShimmer,
      'starlight' => l10n.motionFxStarlight,
      'lightning' => l10n.motionFxLightning,
      'impactFlash' => l10n.motionFxImpactFlash,
      'speedLines' => l10n.motionFxSpeedLines,
      'focusLines' => l10n.motionFxFocusLines,
      'screenTone' => l10n.motionFxScreenTone,
      'mangaShake' => l10n.motionFxMangaShake,
      'impactRings' => l10n.motionFxImpactRings,
      'brushStreak' => l10n.motionFxBrushStreak,
      'moodScript' => l10n.motionFxMoodScript,
      _ => spec.kind,
    };
  }

  static String _paramLabel(AppLocalizations l10n, MotionParamSpec p) {
    return switch (p.labelKey) {
      'motionParamAmplitude' => l10n.motionParamAmplitude,
      'motionParamPeriod' => l10n.motionParamPeriod,
      'motionParamVerticalRatio' => l10n.motionParamVerticalRatio,
      'motionParamPushFrac' => l10n.motionParamPushFrac,
      'motionParamBeats' => l10n.motionParamBeats,
      'motionParamIntensity' => l10n.motionParamIntensity,
      'motionParamShift' => l10n.motionParamShift,
      'motionParamStrength' => l10n.motionParamStrength,
      'motionParamCount' => l10n.motionParamCount,
      'motionParamSpeed' => l10n.motionParamSpeed,
      'motionParamOpacity' => l10n.motionParamOpacity,
      'motionParamAngle' => l10n.motionParamAngle,
      'motionParamSize' => l10n.motionParamSize,
      'motionParamSpin' => l10n.motionParamSpin,
      'motionParamGlow' => l10n.motionParamGlow,
      'motionParamLengthFrac' => l10n.motionParamLengthFrac,
      'motionParamBlobs' => l10n.motionParamBlobs,
      'motionParamPuffs' => l10n.motionParamPuffs,
      'motionParamTongues' => l10n.motionParamTongues,
      'motionParamRows' => l10n.motionParamRows,
      'motionParamStrikes' => l10n.motionParamStrikes,
      'motionParamFlashes' => l10n.motionParamFlashes,
      'motionParamPulses' => l10n.motionParamPulses,
      'motionParamLines' => l10n.motionParamLines,
      'motionParamSpacing' => l10n.motionParamSpacing,
      'motionParamDensity' => l10n.motionParamDensity,
      'motionParamShakes' => l10n.motionParamShakes,
      'motionParamRings' => l10n.motionParamRings,
      'motionParamStreaks' => l10n.motionParamStreaks,
      'motionParamHeightFrac' => l10n.motionParamHeightFrac,
      _ => p.key,
    };
  }

  /// 预设文案映射（详情页 / 设置卡片 / 内联面板共用）。
  static String presetLabel(AppLocalizations l10n, MotionEffectPreset preset) {
    return switch (preset.labelKey) {
      'motionPresetClassic' => l10n.motionPresetClassic,
      'motionPresetSakura' => l10n.motionPresetSakura,
      'motionPresetNightRain' => l10n.motionPresetNightRain,
      'motionPresetStarryNight' => l10n.motionPresetStarryNight,
      'motionPresetBattle' => l10n.motionPresetBattle,
      _ => preset.id,
    };
  }

  /// 预设是否为当前生效组合（效果集合一致且无参数覆盖）。
  static bool presetSelected(MotionEffectSettings m, MotionEffectPreset preset) {
    if (m.paramOverrides.isNotEmpty) return false;
    final a = m.effects.toSet();
    final b = preset.effects.toSet();
    return a.length == b.length && a.containsAll(b);
  }

  /// 参数当前值显示（int 整数；小数按步进定小数位）。
  static String _paramDisplay(MotionParamSpec p, num v) {
    if (p.isInt) return v.round().toString();
    final int digits = p.step >= 1
        ? 0
        : p.step >= 0.1
            ? 1
            : p.step >= 0.01
                ? 2
                : 3;
    return v.toDouble().toStringAsFixed(digits);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final MotionEffectSettings m = settings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 主开关
        SettingsSwitchTile(
          key: const ValueKey<String>('motion.enabled'),
          title: l10n.motionEffectEnabled,
          subtitle: l10n.motionEffectEnabledDesc,
          value: m.enabled,
          onChanged: (v) => onChanged(m.copyWith(enabled: v)),
        ),
        // 开发阶段警示：开关关闭时同样展示，先告知风险。
        const SizedBox(height: AppTokens.spaceXs),
        _DevStageBanner(text: l10n.motionEffectDevWarning),
        SettingsExpand(
          visible: m.enabled,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: AppTokens.spaceMd),
              // 互动阅读层（翻页单页模式）
              SettingsSwitchTile(
                key: const ValueKey<String>('motion.interactiveReader'),
                title: l10n.motionInteractiveTitle,
                subtitle: l10n.motionInteractiveDesc,
                value: m.interactiveReaderEnabled,
                onChanged: (v) =>
                    onChanged(m.copyWith(interactiveReaderEnabled: v)),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              // 快速预设
              _chipSection(
                context,
                l10n.motionPresets,
                MotionEffectCatalog.presets.map((p) {
                  return ChoiceChip(
                    label: Text(presetLabel(l10n, p)),
                    selected: presetSelected(m, p),
                    onSelected: (_) {
                      AppHaptics.selectionClick();
                      onChanged(m.copyWith(
                        effects: p.effects,
                        paramOverrides: const {},
                      ));
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              // 条漫渲染时机
              _chipSection(
                context,
                l10n.motionWebtoonModeTitle,
                <Widget>[
                  ChoiceChip(
                    label: Text(l10n.motionWebtoonModeDwell),
                    selected: m.webtoonRenderMode ==
                        MotionWebtoonRenderMode.dwell,
                    onSelected: (_) {
                      AppHaptics.selectionClick();
                      onChanged(m.copyWith(
                          webtoonRenderMode: MotionWebtoonRenderMode.dwell));
                    },
                  ),
                  ChoiceChip(
                    label: Text(l10n.motionWebtoonModeFollow),
                    selected: m.webtoonRenderMode ==
                        MotionWebtoonRenderMode.follow,
                    onSelected: (_) {
                      AppHaptics.selectionClick();
                      onChanged(m.copyWith(
                          webtoonRenderMode: MotionWebtoonRenderMode.follow));
                    },
                  ),
                ],
              ),
              Text(
                l10n.motionWebtoonModeHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              Text(
                l10n.motionEffectCountHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              // 画质与流畅度
              Text(
                l10n.motionQuality,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: AppTokens.spaceSm),
              SettingsSliderTile(
                label: l10n.motionFps,
                value: m.fps.toDouble(),
                min: 6,
                max: 24,
                divisions: 18,
                display: '${m.fps} fps',
                onChanged: (v) => onChanged(m.copyWith(fps: v.round())),
              ),
              SettingsSliderTile(
                label: l10n.motionDuration,
                value: m.durationSec,
                min: 2,
                max: 6,
                divisions: 8,
                display: '${m.durationSec.toStringAsFixed(1)} s',
                onChanged: (v) => onChanged(m.copyWith(
                    durationSec: double.parse(v.toStringAsFixed(1)))),
              ),
              SettingsSliderTile(
                label: l10n.motionResolution,
                value: m.maxDimension.toDouble(),
                min: 480,
                max: 1080,
                divisions: 15,
                display: '${m.maxDimension}px',
                onChanged: (v) =>
                    onChanged(m.copyWith(maxDimension: (v / 40).round() * 40)),
              ),
              Text(
                l10n.motionQualityHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              // 四组效果：每种独立开关 + 展开参数
              for (final entry in MotionEffectCatalog.grouped.entries) ...<Widget>[
                SettingsCard(
                  key: ValueKey<String>('motion.group.${entry.key}'),
                  title: _groupLabel(l10n, entry.key),
                  initiallyExpanded: false,
                  children: <Widget>[
                    for (final MotionEffectSpec spec in entry.value) ...<Widget>[
                      SettingsSwitchTile(
                        key: ValueKey<String>('motion.${spec.kind}'),
                        title: _effectLabel(l10n, spec),
                        value: m.effects.contains(spec.kind),
                        onChanged: (v) =>
                            onChanged(m.withEffectEnabled(spec.kind, v)),
                      ),
                      SettingsExpand(
                        visible: m.effects.contains(spec.kind) &&
                            spec.params.isNotEmpty,
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: <Widget>[
                            for (final MotionParamSpec p in spec.params)
                              SettingsSliderTile(
                                label: _paramLabel(l10n, p),
                                value: m.paramValue(spec, p).toDouble(),
                                min: p.min,
                                max: p.max,
                                divisions: ((p.max - p.min) / p.step).round(),
                                display:
                                    _paramDisplay(p, m.paramValue(spec, p)),
                                onChanged: (v) => onChanged(m.withParam(
                                  spec.kind,
                                  p.key,
                                  p.isInt
                                      ? v.round()
                                      : double.parse(v.toStringAsFixed(3)),
                                )),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppTokens.spaceSm),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _chipSection(BuildContext context, String label, List<Widget> chips) {
    return Column(
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
}

/// 开发阶段警示条（图标 + 文案，低饱和警示底色）。
///
/// 动态效果主开关旁的常驻提示：不随开关状态隐藏，说明功能成熟度与风险。
class _DevStageBanner extends StatelessWidget {
  const _DevStageBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color warn = AppStatusColors.warn(scheme);

    return Container(
      key: const ValueKey<String>('motion.devStageBanner'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMd,
        vertical: AppTokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: AppStatusColors.containerOf(warn),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.science_outlined, size: 16, color: warn),
          const SizedBox(width: AppTokens.spaceSm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: warn, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
