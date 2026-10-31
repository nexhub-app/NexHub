import 'package:material_ui/material_ui.dart';

import '../../../core/home_widget/home_widget_settings.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_animations.dart';
import '../../../core/widgets/app_glass_bar.dart';
import '../../../generated/app_localizations.dart';
import './widgets/settings_search_target.dart';
import './widgets/settings_widgets.dart';

/// 桌面卡片个性化设置：背景来源、模糊强度、不透明度、继续观看条数。
///
/// 参数改动即时保存并触发卡片重算（[HomeWidgetSettingsStore] 是 ChangeNotifier，
/// [HomeWidgetService] 监听它）。背景图由 Flutter 预渲染，所以这里改完不依赖
/// 系统刷新，下一次卡片刷新就能看到效果。
class SettingsWidgetScreen extends StatelessWidget {
  const SettingsWidgetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return AppShrinkTitleScaffold(
      title: Text(l10n.settingsCatWidget),
      body: SettingsAutoScroll(
        child: Entrance(
          offset: 10,
          fromScale: 0.985,
          duration: AppTokens.durBase,
          child: ListenableBuilder(
            listenable: HomeWidgetSettingsStore.instance,
            builder: (BuildContext context, _) {
              final HomeWidgetSettingsStore store =
                  HomeWidgetSettingsStore.instance;
              final HomeWidgetSettings s = store.settings;
              Widget check(WidgetBackgroundMode mode) => s.background == mode
                  ? Icon(Icons.check_rounded, color: scheme.primary)
                  : const SizedBox.shrink();
              return ListView(
                padding: context.pageInset(AppTokens.spaceLg),
                children: <Widget>[
                  SettingsGroup(
                    header: l10n.widgetBackgroundSection,
                    children: <Widget>[
                      SettingsTile(
                        icon: Icons.image_rounded,
                        title: l10n.widgetBgCover,
                        subtitle: l10n.widgetBgCoverDesc,
                        trailing: check(WidgetBackgroundMode.cover),
                        onTap: () =>
                            store.setBackground(WidgetBackgroundMode.cover),
                      ),
                      SettingsTile(
                        icon: Icons.gradient_rounded,
                        title: l10n.widgetBgTheme,
                        subtitle: l10n.widgetBgThemeDesc,
                        trailing: check(WidgetBackgroundMode.theme),
                        onTap: () =>
                            store.setBackground(WidgetBackgroundMode.theme),
                      ),
                      SettingsTile(
                        icon: Icons.block_rounded,
                        title: l10n.widgetBgNone,
                        subtitle: l10n.widgetBgNoneDesc,
                        trailing: check(WidgetBackgroundMode.none),
                        onTap: () =>
                            store.setBackground(WidgetBackgroundMode.none),
                      ),
                    ],
                  ),
                  SettingsGroup(
                    header: l10n.widgetTuningSection,
                    children: <Widget>[
                      SettingsTile(
                        icon: Icons.blur_linear_rounded,
                        title: l10n.widgetBlurStrength,
                        subtitle: '${s.blurSigma.round()}',
                        trailing: SizedBox(
                          width: 150,
                          child: Slider(
                            min: 0,
                            max: 40,
                            divisions: 8,
                            value: s.blurSigma.clamp(0.0, 40.0),
                            onChanged: store.setBlurSigma,
                          ),
                        ),
                      ),
                      SettingsTile(
                        icon: Icons.opacity_rounded,
                        title: l10n.widgetOpacity,
                        subtitle: '${(s.opacity * 100).round()}%',
                        trailing: SizedBox(
                          width: 150,
                          child: Slider(
                            min: 0.2,
                            max: 1.0,
                            divisions: 8,
                            value: s.opacity.clamp(0.2, 1.0),
                            onChanged: store.setOpacity,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SettingsGroup(
                    header: l10n.widgetRecordsSection,
                    children: <Widget>[
                      SettingsTile(
                        icon: Icons.list_alt_rounded,
                        title: l10n.widgetContinueLimit,
                        subtitle: l10n.widgetContinueLimitDesc(
                          s.continueLimit,
                        ),
                        trailing: SizedBox(
                          width: 150,
                          child: Slider(
                            min: 3,
                            max: 8,
                            divisions: 5,
                            value: s.continueLimit.toDouble(),
                            onChanged: (double v) =>
                                store.setContinueLimit(v.round()),
                          ),
                        ),
                      ),
                      SettingsTile(
                        icon: Icons.info_outline_rounded,
                        title: l10n.widgetLimitNote,
                        subtitle: l10n.widgetLimitNoteDesc,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
