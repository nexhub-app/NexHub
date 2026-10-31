/// 外观与语言汇总页：主题 / 配色 / 背景图 / 启动与显示 / 语言。
///
/// Legado MD3 观感：每行一张独立描边小卡（[SettingsTile]），分组小标题
/// （[SettingsGroup]）；单选类设置走底部弹层（与 Legado 的行 + 弹层一致）。
///
/// body 使用 SettingsAutoScroll 包裹，使设置搜索可按 ValueKey 精确定位到
/// 具体的「主题」「配色」「启动」「语言」等组；ListView 内的子项在首帧时
/// 即可被 findContextWithValueKey 命中。
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_fonts.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/theme/palette_style.dart';
import '../../../core/locale/locale_controller.dart';
import '../../../core/settings/detail_appearance_settings.dart';
import '../../../core/settings/general_settings.dart';
import '../../../core/platform/platform_service.dart';
import '../../../core/widgets/app_animations.dart';
import '../../../core/widgets/app_alert_dialog.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/app_glass_bar.dart';
import 'package:nexhub/core/navigation/app_page_route.dart';
import './widgets/settings_widgets.dart';
import './widgets/settings_search_target.dart';
import './settings_hero_screen.dart';
import './settings_widget_screen.dart';
import 'package:nexhub/generated/app_localizations.dart';

class SettingsAppearanceScreen extends StatefulWidget {
  const SettingsAppearanceScreen({super.key});

  @override
  State<SettingsAppearanceScreen> createState() =>
      _SettingsAppearanceScreenState();
}

class _SettingsAppearanceScreenState extends State<SettingsAppearanceScreen> {
  late GeneralSettings _s;

  @override
  void initState() {
    super.initState();
    final store = GeneralSettingsStore.instance;
    _s = store.settings;
    if (!store.loaded) {
      store.load().then((s) {
        if (mounted) setState(() => _s = s);
      });
    }
  }

  void _update(GeneralSettings next) {
    setState(() => _s = next);
    GeneralSettingsStore.instance.save(next);
  }

  void _openColorPicker(
      BuildContext context, ThemeController c, AppLocalizations l10n) {
    Color pickerColor = c.seed;
    showDialog(
      context: context,
      builder: (BuildContext ctx) => AppAlertDialog(
        title: Text(l10n.customColor),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (Color color) => pickerColor = color,
            enableAlpha: false,
          ),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          OutlinedButton(
            onPressed: () {
              c.setSeed(AppTokens.seedYouthfulPrimary);
              Navigator.pop(ctx);
            },
            child: Text(l10n.restoreDefault),
          ),
          FilledButton(
            onPressed: () {
              c.setSeed(pickerColor);
              Navigator.pop(ctx);
            },
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
  }

  /// 底部弹层单选：设置页统一的「行 + 弹层」选择交互（Legado MD3 观感）。
  ///
  /// 选中项右侧 primary 色 check_rounded，其余行无图标——交互/选中态才用 primary。
  Future<void> _showRadioSheet<T>({
    required BuildContext context,
    required String title,
    required List<(T, String)> options,
    required T selected,
    required ValueChanged<T> onSelected,
  }) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
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
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            // 选项多时（调色板风格 9 项）会超过弹层最大高度：
            // Flexible + SingleChildScrollView 让选项区在空间不足时内部滚动，
            // 空间充足时仍随内容收紧（mainAxisSize.min），两态都正确。
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final (T value, String label) in options)
                      ListTile(
                        title: Text(label),
                        trailing: value == selected
                            ? Icon(Icons.check_rounded,
                                color: scheme.primary, size: 22)
                            : null,
                        onTap: () {
                          AppHaptics.tick();
                          Navigator.pop(ctx);
                          onSelected(value);
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppTokens.spaceSm),
          ],
        ),
      ),
    );
  }

  String _modeLabel(AppLocalizations l10n, ThemeMode m) => switch (m) {
        ThemeMode.light => l10n.themeLight,
        ThemeMode.dark => l10n.themeDark,
        ThemeMode.system => l10n.themeSystem,
      };

  String _paletteStyleLabel(AppLocalizations l10n, PaletteStyle s) =>
      switch (s) {
        PaletteStyle.tonalSpot => l10n.paletteStyleTonalSpot,
        PaletteStyle.fidelity => l10n.paletteStyleFidelity,
        PaletteStyle.content => l10n.paletteStyleContent,
        PaletteStyle.neutral => l10n.paletteStyleNeutral,
        PaletteStyle.monochrome => l10n.paletteStyleMonochrome,
        PaletteStyle.vibrant => l10n.paletteStyleVibrant,
        PaletteStyle.expressive => l10n.paletteStyleExpressive,
        PaletteStyle.rainbow => l10n.paletteStyleRainbow,
        PaletteStyle.fruitSalad => l10n.paletteStyleFruitSalad,
      };

  String _launchLabel(AppLocalizations l10n, LaunchTab t) => switch (t) {
        LaunchTab.browse => l10n.navBrowse,
        LaunchTab.novel => l10n.navNovel,
        LaunchTab.media => l10n.navMedia,
        LaunchTab.comic => l10n.navComic,
        LaunchTab.settings => l10n.navSettings,
      };

  String _dateFormatLabel(AppLocalizations l10n, AppDateFormat d) =>
      switch (d) {
        AppDateFormat.defaultFormat => l10n.dateFormatDefault,
        AppDateFormat.mmddyy => l10n.dateFormatMmDdYy,
        AppDateFormat.ddmmyy => l10n.dateFormatDdMmYy,
        AppDateFormat.yyyymmdd => l10n.dateFormatYyyyMmDd,
        AppDateFormat.ddmmmyyyy => l10n.dateFormatDdMmmYyyy,
        AppDateFormat.mmmdd => l10n.dateFormatMmmDd,
        AppDateFormat.yyyyOnly => l10n.dateFormatYyyy,
      };

  String _localeLabel(AppLocalizations l10n, LocaleOption o) => switch (o) {
        LocaleOption.system => l10n.languageFollowSystem,
        LocaleOption.chinese => l10n.languageChinese,
        LocaleOption.english => l10n.languageEnglish,
      };

  /// 窄屏章节列表滑动动作的展示名（设置行 subtitle 用）。
  String _swipeActionLabel(AppLocalizations l10n, DetailSwipeAction a) =>
      switch (a) {
        DetailSwipeAction.download => l10n.swipeActionDownload,
        DetailSwipeAction.bookmark => l10n.swipeActionBookmark,
        DetailSwipeAction.read => l10n.swipeActionRead,
      };

  /// 界面字体当前选择的展示名（设置行 subtitle 用）。
  String _fontLabel(
      AppLocalizations l10n, ThemeController controller, bool isZh) {
    if (controller.appFontId == kAppFontCustomId) {
      return controller.appFontCustomName ?? l10n.appFontCustomDesc;
    }
    return builtInAppFontById(controller.appFontId)?.displayName(isZh) ??
        l10n.appFontFollowSystem;
  }

  /// 「界面字体」选择弹层：内置开源字体逐行用**该字体本身**渲染预览；
  /// 底部为自定义字体（导入 / 当前使用 / 清除）。结构仿 [_showRadioSheet]，
  /// 仅行内容按字体预览定制，无法直接复用泛型单选。
  Future<void> _showFontSheet(
    BuildContext context,
    ThemeController controller,
    AppLocalizations l10n,
    bool isZh,
  ) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final String currentId = controller.appFontId;
    return showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
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
                l10n.appearanceFont,
                style: textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    ListTile(
                      title: Text(l10n.appFontFollowSystem),
                      subtitle: Text(l10n.appFontFollowSystemDesc),
                      trailing: currentId == kAppFontSystemId
                          ? Icon(Icons.check_rounded,
                              color: scheme.primary, size: 22)
                          : null,
                      onTap: () {
                        AppHaptics.tick();
                        Navigator.pop(ctx);
                        controller.setAppFont(kAppFontSystemId);
                      },
                    ),
                    for (final AppFontOption font in kBuiltInAppFonts)
                      ListTile(
                        title: Text(
                          font.displayName(isZh),
                          style: TextStyle(fontFamily: font.family),
                        ),
                        subtitle: Text(
                          l10n.appFontPreviewSample,
                          style: TextStyle(fontFamily: font.family),
                        ),
                        trailing: currentId == font.id
                            ? Icon(Icons.check_rounded,
                                color: scheme.primary, size: 22)
                            : null,
                        onTap: () {
                          AppHaptics.tick();
                          Navigator.pop(ctx);
                          controller.setAppFont(font.id);
                        },
                      ),
                    const Divider(
                      height: 1,
                      thickness: 1,
                      indent: AppTokens.spaceLg,
                      endIndent: AppTokens.spaceLg,
                    ),
                    if (currentId == kAppFontCustomId &&
                        controller.appFontCustomName != null)
                      ListTile(
                        title: Text(
                          controller.appFontCustomName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(l10n.appFontCustomDesc),
                        trailing: Icon(Icons.check_rounded,
                            color: scheme.primary, size: 22),
                      ),
                    ListTile(
                      title: Text(l10n.appFontCustomImport),
                      onTap: () {
                        AppHaptics.tick();
                        Navigator.pop(ctx);
                        _importCustomFont(context, controller, l10n);
                      },
                    ),
                    if (currentId == kAppFontCustomId)
                      ListTile(
                        title: Text(l10n.appFontClearCustom),
                        onTap: () {
                          AppHaptics.tick();
                          Navigator.pop(ctx);
                          controller.clearAppFontCustom();
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppTokens.spaceSm),
          ],
        ),
      ),
    );
  }

  /// 选择 .ttf / .otf 文件并交给 [ThemeController.setAppFontCustom] 复制
  /// 进私有目录注册；失败（文件损坏 / 格式不受支持）弹 SnackBar 提示。
  Future<void> _importCustomFont(
    BuildContext context,
    ThemeController controller,
    AppLocalizations l10n,
  ) async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['ttf', 'otf'],
      );
    } on Object {
      return; // 选择器被打断 / 平台不可用，视为取消。
    }
    if (result == null) return; // 用户取消。
    final String? path = result.files.single.path;
    if (path == null) return; // Web 等无路径平台不支持持久化导入。
    final bool ok = await controller.setAppFontCustom(
      sourcePath: path,
      displayName: result.files.single.name,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.appFontLoadFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeController controller = context.watch<ThemeController>();
    final LocaleController localeController = context.watch<LocaleController>();
    final scheme = Theme.of(context).colorScheme;
    // 字体显示名按界面语言取中 / 英文名（字体名为专有名词，不入 arb）。
    final bool isZh =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'zh';

    return AppShrinkTitleScaffold(
      title: Text(l10n.settingsCatAppearance),
      body: SettingsAutoScroll(
        child: Entrance(
          offset: 10,
          fromScale: 0.985,
          duration: AppTokens.durBase,
          child: ListView(
            padding: context.pageInset(AppTokens.spaceLg),
            children: <Widget>[
              // ── 主题 ──
              SettingsGroup(
                key: const ValueKey<String>('appearance.theme'),
                header: l10n.appearanceThemeSection,
                children: <Widget>[
                  SettingsTile(
                    icon: Icons.brightness_6_rounded,
                    title: l10n.appearanceThemeMode,
                    subtitle: _modeLabel(l10n, controller.mode),
                    onTap: () => _showRadioSheet<ThemeMode>(
                      context: context,
                      title: l10n.appearanceThemeMode,
                      options: <(ThemeMode, String)>[
                        (ThemeMode.light, l10n.themeLight),
                        (ThemeMode.dark, l10n.themeDark),
                        (ThemeMode.system, l10n.themeSystem),
                      ],
                      selected: controller.mode,
                      onSelected: controller.setMode,
                    ),
                  ),
                  // 鸿蒙：dynamic_color 无 ohos 实现，改由应用级原生通道读取
                  // 壁纸主色作莫奈 seed（见 SystemWallpaperColor）；取不到时
                  // 与安卓一样回退默认主题，入口保持可见。
                  SettingsTile(
                    icon: Icons.auto_awesome_rounded,
                    title: l10n.useMonet,
                    trailing: Switch(
                      value: controller.useMonet,
                      onChanged: (bool v) {
                        v ? AppHaptics.toggleOn() : AppHaptics.toggleOff();
                        controller.setUseMonet(v);
                      },
                    ),
                  ),
                  // 界面毛玻璃效果：开关 + 模糊强度 / 不透明度自定义，
                  // 监听通用设置即时生效（侧栏与底栏共用这套参数）。
                  ListenableBuilder(
                    listenable: GeneralSettingsStore.instance,
                    builder: (context, _) {
                      final GeneralSettingsStore store =
                          GeneralSettingsStore.instance;
                      final bool glassOn = store.settings.glassEffectEnabled;
                      const Divider hairline = Divider(
                        height: 1,
                        thickness: 1,
                        indent: AppTokens.spaceLg,
                        endIndent: AppTokens.spaceLg,
                      );
                      return Column(
                        children: <Widget>[
                          SettingsTile(
                            icon: Icons.blur_on_rounded,
                            title: l10n.glassEffectTitle,
                            subtitle: l10n.glassEffectDesc,
                            trailing: Switch(
                              value: glassOn,
                              onChanged: (bool v) {
                                v
                                    ? AppHaptics.toggleOn()
                                    : AppHaptics.toggleOff();
                                store.setGlassEffectEnabled(v);
                              },
                            ),
                          ),
                          if (glassOn) ...<Widget>[
                            hairline,
                            SettingsTile(
                              icon: Icons.blur_linear_rounded,
                              title: l10n.glassBlurStrength,
                              subtitle:
                                  '${store.settings.glassBlurSigma.round()}',
                              trailing: SizedBox(
                                width: 160,
                                child: Slider(
                                  min: 0,
                                  max: 40,
                                  divisions: 8,
                                  value: store.settings.glassBlurSigma
                                      .clamp(0.0, 40.0),
                                  onChanged: store.setGlassBlurSigma,
                                ),
                              ),
                            ),
                            hairline,
                            SettingsTile(
                              icon: Icons.opacity_rounded,
                              title: l10n.glassBarOpacity,
                              subtitle:
                                  '${(store.settings.glassBarOpacity * 100).round()}%',
                              trailing: SizedBox(
                                width: 160,
                                child: Slider(
                                  min: 0.4,
                                  max: 0.95,
                                  divisions: 11,
                                  value: store.settings.glassBarOpacity
                                      .clamp(0.4, 0.95),
                                  onChanged: store.setGlassBarOpacity,
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  // 源管理拖拽排序的「断卡」动效（低配设备可关闭为简化效果）。
                  ListenableBuilder(
                    listenable: GeneralSettingsStore.instance,
                    builder: (context, _) {
                      final GeneralSettingsStore store =
                          GeneralSettingsStore.instance;
                      return SettingsTile(
                        icon: Icons.animation_rounded,
                        title: l10n.sourceDragSplitTitle,
                        subtitle: l10n.sourceDragSplitDesc,
                        trailing: Switch(
                          value: store.settings.sourceDragSplitEffect,
                          onChanged: (bool v) {
                            v ? AppHaptics.toggleOn() : AppHaptics.toggleOff();
                            store.setSourceDragSplitEffect(v);
                          },
                        ),
                      );
                    },
                  ),
                  // 鸿蒙：状态栏点按回顶（引擎转发 CLICK_STATUSBAR，非鸿蒙不显示）。
                  if (PlatformService.instance.isOHOS)
                    ListenableBuilder(
                      listenable: GeneralSettingsStore.instance,
                      builder: (context, _) {
                        final GeneralSettingsStore store =
                            GeneralSettingsStore.instance;
                        return SettingsTile(
                          icon: Icons.vertical_align_top_rounded,
                          title: l10n.statusBarTapToTopTitle,
                          subtitle: l10n.statusBarTapToTopDesc,
                          trailing: Switch(
                            value: store.settings.statusBarTapToTop,
                            onChanged: (bool v) {
                              v
                                  ? AppHaptics.toggleOn()
                                  : AppHaptics.toggleOff();
                              store.setStatusBarTapToTop(v);
                            },
                          ),
                        );
                      },
                    ),
                  SettingsTile(
                    icon: Icons.palette_rounded,
                    title: l10n.paletteStyleTitle,
                    subtitle: _paletteStyleLabel(l10n, controller.paletteStyle),
                    onTap: () => _showRadioSheet<PaletteStyle>(
                      context: context,
                      title: l10n.paletteStyleTitle,
                      options: <(PaletteStyle, String)>[
                        for (final PaletteStyle s in PaletteStyle.values)
                          (s, _paletteStyleLabel(l10n, s)),
                      ],
                      selected: controller.paletteStyle,
                      onSelected: controller.setPaletteStyle,
                    ),
                  ),
                ],
              ),

              // ── 桌面卡片 ──
              SettingsGroup(
                header: l10n.settingsCatWidget,
                children: <Widget>[
                  SettingsTile(
                    icon: Icons.widgets_rounded,
                    title: l10n.settingsCatWidget,
                    subtitle: l10n.settingsCatWidgetDesc,
                    onTap: () {
                      AppHaptics.selectionClick();
                      Navigator.of(context).push(
                        AppPageRoute<void>(
                          builder: (_) => const SettingsWidgetScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),

              // ── 配色 ──
              SettingsGroup(
                key: const ValueKey<String>('appearance.colors'),
                header: l10n.appearanceColorsSection,
                children: <Widget>[
                  // 预设色板：色点直接平铺（取色场景直选比收进弹层更直观），
                  // 作为组卡内的一个区块（上下由发丝分隔线区隔），不再是卡中卡。
                  Padding(
                    padding: const EdgeInsets.all(AppTokens.spaceLg),
                    child: Wrap(
                      spacing: AppTokens.spaceMd,
                      runSpacing: AppTokens.spaceMd,
                      children: AppTokens.presetSeeds.map((preset) {
                        final Color color = preset.$1;
                        final String name = preset.$2;
                        final bool selected =
                            !controller.useMonet && controller.seed == color;
                        return Tooltip(
                          message: name,
                          child: GestureDetector(
                            onTap: () {
                              AppHaptics.selectionClick();
                              controller.setUseMonet(false);
                              controller.setSeed(color);
                            },
                            child: AnimatedContainer(
                              duration: AppTokens.durBase,
                              curve: AppCurves.smooth,
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selected
                                      ? scheme.primary
                                      : scheme.outlineVariant,
                                  width: selected ? 3 : 1,
                                ),
                              ),
                              child: selected
                                  ? Icon(Icons.check_rounded,
                                      color:
                                          ThemeData.estimateBrightnessForColor(
                                                      color) ==
                                                  Brightness.dark
                                              ? Colors.white
                                              : Colors.black,
                                      size: 20)
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  SettingsTile(
                    key: const ValueKey<String>('appearance.customColor'),
                    icon: Icons.colorize_rounded,
                    title: l10n.customColor,
                    trailing: CircleAvatar(
                        backgroundColor: controller.seed, radius: 14),
                    onTap: () => _openColorPicker(context, controller, l10n),
                  ),
                ],
              ),

              // ── 详情页外观（封面取色 / 封面模糊背景） ──
              // 设置存独立仓（DetailAppearanceStore），详情页监听同一仓即时生效。
              ListenableBuilder(
                listenable: DetailAppearanceStore.instance,
                builder: (BuildContext context, _) {
                  final DetailAppearanceStore store =
                      DetailAppearanceStore.instance;
                  final DetailAppearanceSettings s = store.settings;
                  const Divider hairline = Divider(
                    height: 1,
                    thickness: 1,
                    indent: AppTokens.spaceLg,
                    endIndent: AppTokens.spaceLg,
                  );
                  return SettingsGroup(
                    key: const ValueKey<String>(
                        'appearance.detailAppearance'),
                    header: l10n.settingsCatDetailAppearance,
                    children: <Widget>[
                      SettingsTile(
                        icon: Icons.colorize_rounded,
                        title: l10n.detailAppearanceDynamicAccent,
                        subtitle: l10n.detailAppearanceDynamicAccentDesc,
                        trailing: Switch(
                          value: s.dynamicAccentEnabled,
                          onChanged: (bool v) {
                            v ? AppHaptics.toggleOn() : AppHaptics.toggleOff();
                            store.setDynamicAccentEnabled(v);
                          },
                        ),
                      ),
                      SettingsTile(
                        icon: Icons.blur_on_rounded,
                        title: l10n.detailAppearanceBlurredBg,
                        subtitle: l10n.detailAppearanceBlurredBgDesc,
                        trailing: Switch(
                          value: s.blurredBackgroundEnabled,
                          onChanged: (bool v) {
                            v ? AppHaptics.toggleOn() : AppHaptics.toggleOff();
                            store.setBlurredBackgroundEnabled(v);
                          },
                        ),
                      ),
                      // 开启后才展开的模糊强度滑杆（与毛玻璃设置同款交互）。
                      if (s.blurredBackgroundEnabled) ...<Widget>[
                        hairline,
                        SettingsTile(
                          icon: Icons.blur_linear_rounded,
                          title: l10n.detailAppearanceBlurStrength,
                          subtitle:
                              '${s.backgroundBlurSigma.clamp(kDetailBlurSigmaMin, kDetailBlurSigmaMax).round()}',
                          trailing: SizedBox(
                            width: 160,
                            child: Slider(
                              min: kDetailBlurSigmaMin,
                              max: kDetailBlurSigmaMax,
                              divisions: ((kDetailBlurSigmaMax -
                                          kDetailBlurSigmaMin) ~/
                                      5)
                                  .round(),
                              value: s.backgroundBlurSigma
                                  .clamp(kDetailBlurSigmaMin, kDetailBlurSigmaMax),
                              onChanged: store.setBackgroundBlurSigma,
                            ),
                          ),
                        ),
                      ],
                      // 窄屏章节列表滑动动作：左滑 / 右滑各自配置
                      // （语言选择同款底部单选弹窗）。
                      hairline,
                      SettingsTile(
                        key: const ValueKey<String>('appearance.detailLeftSwipe'),
                        icon: Icons.swipe_left_rounded,
                        title: l10n.detailAppearanceLeftSwipe,
                        subtitle:
                            '${l10n.detailAppearanceLeftSwipeDesc} · ${_swipeActionLabel(l10n, s.leftSwipeAction)}',
                        onTap: () => _showRadioSheet<DetailSwipeAction>(
                          context: context,
                          title: l10n.detailAppearanceLeftSwipe,
                          options: <(DetailSwipeAction, String)>[
                            (DetailSwipeAction.download,
                                l10n.swipeActionDownload),
                            (DetailSwipeAction.bookmark,
                                l10n.swipeActionBookmark),
                            (DetailSwipeAction.read, l10n.swipeActionRead),
                          ],
                          selected: s.leftSwipeAction,
                          onSelected: store.setLeftSwipeAction,
                        ),
                      ),
                      SettingsTile(
                        key: const ValueKey<String>(
                            'appearance.detailRightSwipe'),
                        icon: Icons.swipe_right_rounded,
                        title: l10n.detailAppearanceRightSwipe,
                        subtitle:
                            '${l10n.detailAppearanceRightSwipeDesc} · ${_swipeActionLabel(l10n, s.rightSwipeAction)}',
                        onTap: () => _showRadioSheet<DetailSwipeAction>(
                          context: context,
                          title: l10n.detailAppearanceRightSwipe,
                          options: <(DetailSwipeAction, String)>[
                            (DetailSwipeAction.download,
                                l10n.swipeActionDownload),
                            (DetailSwipeAction.bookmark,
                                l10n.swipeActionBookmark),
                            (DetailSwipeAction.read, l10n.swipeActionRead),
                          ],
                          selected: s.rightSwipeAction,
                          onSelected: store.setRightSwipeAction,
                        ),
                      ),
                    ],
                  );
                },
              ),

              // ── 字体 ──
              SettingsGroup(
                key: const ValueKey<String>('appearance.font'),
                header: l10n.appearanceFontSection,
                children: <Widget>[
                  SettingsTile(
                    icon: Icons.font_download_rounded,
                    title: l10n.appearanceFont,
                    subtitle: _fontLabel(l10n, controller, isZh),
                    onTap: () => _showFontSheet(
                        context, controller, l10n, isZh),
                  ),
                ],
              ),

              // ── 背景图（Hero） ──
              SettingsGroup(
                key: const ValueKey<String>('appearance.hero'),
                header: l10n.appearanceHeroSection,
                children: <Widget>[
                  SettingsTile(
                    icon: Icons.image_rounded,
                    title: l10n.heroSettingsTitle,
                    subtitle: l10n.heroEmptyHint,
                    onTap: () => Navigator.of(context).push(
                      AppPageRoute<void>(
                        builder: (_) => const SettingsHeroScreen(),
                      ),
                    ),
                  ),
                ],
              ),

              // ── 启动与显示 ──
              SettingsGroup(
                key: const ValueKey<String>('appearance.startup'),
                header: l10n.appearanceStartupSection,
                children: <Widget>[
                  AnimatedBuilder(
                    animation: GeneralSettingsStore.instance,
                    builder: (_, __) {
                      _s = GeneralSettingsStore.instance.settings;
                      return SettingsTile(
                        icon: Icons.rocket_launch_rounded,
                        title: l10n.launchScreenTitle,
                        subtitle: _launchLabel(l10n, _s.launchTab),
                        onTap: () => _showRadioSheet<LaunchTab>(
                          context: context,
                          title: l10n.launchScreenTitle,
                          options: <(LaunchTab, String)>[
                            for (final LaunchTab t in LaunchTab.values)
                              (t, _launchLabel(l10n, t)),
                          ],
                          selected: _s.launchTab,
                          onSelected: (LaunchTab t) =>
                              _update(_s.copyWith(launchTab: t)),
                        ),
                      );
                    },
                  ),
                  AnimatedBuilder(
                    animation: GeneralSettingsStore.instance,
                    builder: (_, __) {
                      _s = GeneralSettingsStore.instance.settings;
                      return SettingsTile(
                        icon: Icons.calendar_today_rounded,
                        title: l10n.dateFormatTitle,
                        subtitle: _dateFormatLabel(l10n, _s.dateFormat),
                        onTap: () => _showRadioSheet<AppDateFormat>(
                          context: context,
                          title: l10n.dateFormatTitle,
                          options: <(AppDateFormat, String)>[
                            for (final AppDateFormat d in AppDateFormat.values)
                              (d, _dateFormatLabel(l10n, d)),
                          ],
                          selected: _s.dateFormat,
                          onSelected: (AppDateFormat d) =>
                              _update(_s.copyWith(dateFormat: d)),
                        ),
                      );
                    },
                  ),
                ],
              ),

              // ── 语言 ──
              SettingsGroup(
                key: const ValueKey<String>('appearance.language'),
                header: l10n.settingsGroupLanguage,
                children: <Widget>[
                  SettingsTile(
                    icon: Icons.translate_rounded,
                    title: l10n.settingsGroupLanguage,
                    subtitle: _localeLabel(l10n, localeController.option),
                    onTap: () => _showRadioSheet<LocaleOption>(
                      context: context,
                      title: l10n.settingsGroupLanguage,
                      options: <(LocaleOption, String)>[
                        (LocaleOption.system, l10n.languageFollowSystem),
                        (LocaleOption.chinese, l10n.languageChinese),
                        (LocaleOption.english, l10n.languageEnglish),
                      ],
                      selected: localeController.option,
                      onSelected: (LocaleOption o) =>
                          localeController.setOption(o),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
