import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:provider/provider.dart';
import 'package:saf/saf.dart';
import 'core/locale/locale_controller.dart';
import 'core/navigation/app_navigator.dart';
import 'core/platform/harmony_continuation.dart';
import 'core/platform/platform_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/system_wallpaper_color.dart';
import 'core/theme/theme_controller.dart';
import 'core/download/download_manager.dart';
import 'core/favorites/favorites_manager.dart';
import 'core/history/history_manager.dart';
import 'core/history/media_playback_position_manager.dart';
import 'core/home_widget/home_widget_launcher.dart';
import 'core/home_widget/home_widget_service.dart';
import 'core/settings/general_settings.dart';
import 'core/services/software_announcement_service.dart';
import 'core/widgets/software_announcement_dialog.dart';
import 'core/widgets/app_scroll_behavior.dart';
import 'core/widgets/status_bar_tap_to_top.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'features/home/presentation/home_screen.dart';
import 'features/onboarding/presentation/onboarding_screen.dart';

/// 应用根：Material 3 + 莫奈动态色 + Provider 主题状态 + 统一 l10n。
class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  StreamSubscription<Color?>? _wallpaperSeedSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 鸿蒙壁纸颜色变化由原生通道实时推送；其他平台为空流，
    // Android 的动态色仍由 DynamicColorBuilder 提供。
    _wallpaperSeedSub =
        SystemWallpaperColor.changes.listen(_applyWallpaperSeedIfAvailable);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wallpaperSeedSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 仅在首次取色失败（如启动早期系统服务未就绪）时回前台补读一次；
    // 已取得壁纸主色后不再重复取色——鸿蒙窗口 resumed 事件可能被页面
    // 切换等场景频繁触发。壁纸变化由原生 colorChange 推送。
    if (state != AppLifecycleState.resumed) return;
    if (context.read<ThemeController>().systemDynamicSeed != null) return;
    SystemWallpaperColor.readSeed().then(_applyWallpaperSeedIfAvailable);
  }

  void _applyWallpaperSeedIfAvailable(Color? seed) {
    if (seed != null) _applyWallpaperSeed(seed);
  }

  void _applyWallpaperSeed(Color seed) {
    if (!mounted) return;
    context.read<ThemeController>().setSystemDynamicSeed(seed);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeController controller = context.watch<ThemeController>();
    final LocaleController localeController = context.watch<LocaleController>();
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp(
          title: 'nexhub',
          debugShowCheckedModeBanner: false,
          navigatorKey: AppNavigator.key,
          scrollBehavior: const AppScrollBehavior(),
          // 桥接仍基于框架 flutter/material 的第三方包（flutter_js / inappwebview / media_kit）
          builder: (BuildContext context, Widget? child) {
            // 全局系统栏兜底：导航栏透明 + 图标亮度随主题（详见
            // AppTheme.systemOverlayStyle）。放在 Navigator 之下，
            // 无 AppBar 的页面也能生效；主题切换即时跟随。
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: AppTheme.systemOverlayStyle(Theme.of(context)),
              child: StatusBarTapToTop(
                child: MaterialUiCompatibilityBridge(child: child!),
              ),
            );
          },
          theme: controller.lightTheme(lightDynamic),
          darkTheme: controller.darkTheme(darkDynamic),
          themeMode: controller.mode,
          locale: localeController.effectiveLocale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: const <Locale>[
            Locale('zh'),
            Locale('en'),
          ],
          home: const _AppBootstrap(),
        );
      },
    );
  }
}

/// 首屏闸门（项 8 / 项 9）。
///
/// 位于 [App] 的 [MaterialApp] 之内，故 [Theme] / [AppLocalizations] /
/// 各 Provider 均已就绪：
/// - 未完成首次引导 → 展示 [OnboardingScreen]，走完回调置
/// `GeneralSettings.onboardingCompleted = true` 后切到主界面；
/// - 已完成引导 → 直接进 [HomeScreen]，若有未读软件公告则首帧后弹窗（项 8）。
class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  late bool _onboardingDone =
      GeneralSettingsStore.instance.settings.onboardingCompleted;

  @override
  void initState() {
    super.initState();
    if (_onboardingDone) {
      _maybeShowAnnouncements();
      _maybePromptPublicDownloadDir();
      _consumeContinuation();
      _initHomeWidget();
    }
  }

  /// 桌面卡片：启动数据服务 + 处理「点了卡片进来」的跳转。
  ///
  /// 两者都放到首帧后：需要 Navigator 与各 Provider 就绪；卡片数据服务还要用
  /// context 取当前语言文案。
  void _initHomeWidget() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final HistoryManager history = context.read<HistoryManager>();
      HomeWidgetService.instance.start(
        history: history,
        favorites: context.read<FavoritesManager>(),
        downloads: context.read<DownloadManager>(),
        positions: context.read<MediaPlaybackPositionManager>(),
        localizations: () {
          try {
            return AppLocalizations.of(context);
          } on Object {
            return null;
          }
        },
        theme: () {
          final ThemeData t = Theme.of(context);
          // 整份 ColorScheme 交给卡片：卡片底色要与 AppCard（cardContainer）
          // 同源，颜色不能只取一个 primary 再自己拍脑袋混。
          return (
            isDark: t.brightness == Brightness.dark,
            scheme: t.colorScheme,
          );
        },
      );
      unawaited(HomeWidgetLauncher.consumePending(history: history));
    });
  }

  /// 鸿蒙跨设备接续：首帧后取走暂存快照并打开对应页面。
  /// 未完成引导时先不消费，等引导结束后再触发（见 [_onOnboardingDone]）。
  void _consumeContinuation() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(HarmonyContinuation.consumePending());
    });
  }

  void _onOnboardingDone() {
    GeneralSettingsStore.instance.save(
      GeneralSettingsStore.instance.settings
          .copyWith(onboardingCompleted: true),
    );
    setState(() => _onboardingDone = true);
    _maybeShowAnnouncements();
    _maybePromptPublicDownloadDir();
    _consumeContinuation();
    _initHomeWidget();
  }

  /// 引导用户选择公开下载目录（仅 Android + 尚未设置过目录时）。
  ///
  /// 默认下载目录在 Android 上会落在应用私有外部存储，普通文件管理器看不到
  /// 下载内容。首次进入主界面（首帧后）若仍用默认路径，自动弹出系统目录选择器，
  /// 让用户选一个公开文件夹（如 Download/NexHub），之后下载对其可见。
  /// 用户选过一次（路径变为 content:// 或真实路径）即不再触发。
  Future<void> _maybePromptPublicDownloadDir() async {
    if (!PlatformService.instance.isAndroid) return;
    final manager = context.read<DownloadManager>();
    if (!manager.needsPublicDownloadDir) return;
    // 等首帧构建完成，确保 dialog/picker 的 context 已就绪且叠加在主界面之上。
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final SafDocumentFile? picked = await Saf().pickDirectory();
    if (picked == null || !mounted) return;
    try {
      await manager.setDownloadBasePath(picked.uri);
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('设置下载目录失败：$e')),
      );
    }
  }

  Future<void> _maybeShowAnnouncements() async {
    final service = SoftwareAnnouncementService.instance;
    await service.load();
    final unseen = service.unseen();
    if (unseen.isEmpty || !mounted) return;
    // 等首帧构建完成，确保 dialog 的 context 已就绪且叠加在主界面之上。
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await showSoftwareAnnouncements(context, unseen);
  }

  @override
  Widget build(BuildContext context) {
    if (!_onboardingDone) {
      return OnboardingScreen(onDone: _onOnboardingDone);
    }
    return const HomeScreen();
  }
}
