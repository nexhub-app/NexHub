import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import '../../../core/settings/general_settings.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_nav_bar.dart';
import '../../../core/widgets/app_animations.dart';
import '../../../core/widgets/two_pane_detail.dart';
import '../../manga/presentation/comic_home_screen.dart';
import '../../media/presentation/media_home_screen.dart';
import '../../novel/presentation/novel_home_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import 'browse_page.dart';

/// 底部导航顺序：浏览 → 小说 → 媒体 → 漫画 → 设置，默认浏览为首页。
///
/// 桌面端（≥ [AppTokens.desktopBreakpoint]）为原版 [Row] + 侧栏 +
/// [IndexedStack] 布局；移动端使用 [Scaffold] 玻璃底导（`extendBody`
/// 内容延伸到栏后，滚动时从玻璃底栏后穿透）+ [IndexedStack]。
/// [IndexedStack] 保持所有 Tab 页面状态，避免切换时重建。
///
/// 移动端主框架最底层铺一层 [_AmbientSurface] 氛围底：玻璃底栏后面
/// 除滚动穿过的内容外，无内容处透出这层带主题色晕的底色，模糊后仍有层次。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  /// 所有 Tab 页面一次性构建，由 [IndexedStack] 保留状态。
  late final List<Widget> _pages = <Widget>[
    const BrowsePage(),
    const NovelHomeScreen(),
    const MediaHomeScreen(),
    const ComicHomeScreen(),
    const SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // 启动界面设置：默认打开用户指定的首页 Tab（枚举顺序与底部导航一致）。
    _index = GeneralSettingsStore.instance.settings.launchTab.index;
    // 若通用设置尚未加载完成，加载后回写，避免默认值覆盖用户选择。
    if (!GeneralSettingsStore.instance.loaded) {
      GeneralSettingsStore.instance.load().then((s) {
        if (mounted) setState(() => _index = s.launchTab.index);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final double width = MediaQuery.sizeOf(context).width;
    final List<NavigationDestination> destinations = <NavigationDestination>[
      NavigationDestination(
          icon: const Icon(Icons.explore_rounded), label: l10n.navBrowse),
      NavigationDestination(
          icon: const Icon(Icons.menu_book_rounded), label: l10n.navNovel),
      NavigationDestination(
          icon: const Icon(Icons.movie_rounded), label: l10n.navMedia),
      NavigationDestination(
          icon: const Icon(Icons.auto_stories_rounded), label: l10n.navComic),
      NavigationDestination(
          icon: const Icon(Icons.settings_rounded), label: l10n.navSettings),
    ];

    // 双栏详情宿主上报（全局单份控制器，无通知副作用）：宽屏分支在场与否
    // 及窗口宽度，决定各详情入口「开右栏 or 整页路由」。窄屏分支同样上报
    // 宽度并把宿主置为不在场。
    final TwoPaneDetailController paneController =
        TwoPaneDetailController.instance;
    final bool twoPaneHost = width >= AppTokens.twoPaneBreakpoint;
    paneController.updateHost(active: twoPaneHost, windowWidth: width);
    // 窗口缩到阈值以下：帧后收起详情栏（build 期间不能 notifyListeners）。
    if (!twoPaneHost && paneController.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        paneController.close();
      });
    }

    // 桌面端：侧栏为毛玻璃质感——模糊栏后的氛围底色（不穿透内容），
    // 布局保持原版并排（不再叠加分隔线，玻璃栏边缘即分界）。
    // 平板横屏 / 宽窗口（≥ twoPaneBreakpoint）：详情入口改为在右侧详情栏
    // 打开（列表 | 详情 同屏），列表区随栏打开自动收窄；系统返回先关栏。
    if (width >= AppTokens.desktopBreakpoint) {
      return _AmbientSurface(
        child: PopScope(
          canPop: !paneController.isOpen,
          onPopInvokedWithResult: (bool didPop, Object? result) {
            if (!didPop && paneController.isOpen) paneController.close();
          },
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: ListenableBuilder(
              listenable: paneController,
              builder: (BuildContext context, _) => Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  AppNavBar(
                    selectedIndex: _index,
                    onDestinationSelected: (int i) {
                      replayEntrances();
                      setState(() => _index = i);
                    },
                    destinations: destinations,
                  ),
                  Expanded(
                    child: _AnimatedTabView(index: _index, children: _pages),
                  ),
                  if (paneController.isOpen)
                    TwoPaneDetailPane(
                      controller: paneController,
                      windowWidth: width,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 移动端：玻璃底导 + IndexedStack。extendBody 让内容延伸到底栏后面
    // （底栏高度经 MediaQuery 注入 body），滚动时封面等内容从玻璃底栏后
    // 穿过，模糊透视；收尾条目靠各列表的底部避让滚出遮挡区。
    return _AmbientSurface(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: _AnimatedTabView(index: _index, children: _pages),
        bottomNavigationBar: AppNavBar(
          selectedIndex: _index,
          onDestinationSelected: (int i) {
            replayEntrances();
            setState(() => _index = i);
          },
          destinations: destinations,
        ),
      ),
    );
  }
}

/// 玻璃栏位的氛围底色。
///
/// 毛玻璃的本质是「模糊栏位身后已有的像素」：若栏后是单一 surface 纯色，
/// 模糊结果与实色无异。这里在主框架最底层铺一条纵向渐变——主题 surface
/// 上叠加两段主题色晕（上段 primary、下段 tertiary 的淡化过渡），
/// 侧栏通高与移动端底栏都能透出清晰的色彩层次。各 Tab 页面自身不透明，
/// 内容区视觉与原来完全一致。
class _AmbientSurface extends StatelessWidget {
  const _AmbientSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            cs.surface,
            Color.lerp(cs.surface, cs.primaryContainer, 0.5)!,
            cs.surface,
            Color.lerp(cs.surface, cs.tertiaryContainer, 0.45)!,
          ],
          stops: const <double>[0.0, 0.18, 0.5, 1.0],
        ),
      ),
      child: child,
    );
  }
}

/// 底栏 / 侧栏 Tab 内容滑动切换视图。
///
/// 所有 Tab 页面常驻 [Stack]（保留状态）；切换时新页滑入、旧页滑出：
/// - 底部导航（窄屏 < [AppTokens.desktopBreakpoint]）：左右滑动；
/// - 侧边导航（宽屏 ≥ 断点）：上下滑动。
/// 仅渲染当前页 + 上一切换页（[Offstage] 隐藏中间页，优化绘制性能）。
class _AnimatedTabView extends StatefulWidget {
  const _AnimatedTabView({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_AnimatedTabView> createState() => _AnimatedTabViewState();
}

class _AnimatedTabViewState extends State<_AnimatedTabView> {
  int? _oldIndex;

  @override
  void didUpdateWidget(covariant _AnimatedTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _oldIndex = oldWidget.index;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isWide =
        MediaQuery.sizeOf(context).width >= AppTokens.desktopBreakpoint;
    return Stack(
      fit: StackFit.expand,
      children: List<Widget>.generate(widget.children.length, (int i) {
        final bool active = i == widget.index;
        final bool render = active || i == _oldIndex;
        final Offset hidden = isWide
            ? Offset(0, i < widget.index ? -1 : 1)
            : Offset(i < widget.index ? -1 : 1, 0);
        return Offstage(
          offstage: !render,
          child: IgnorePointer(
            ignoring: !active,
            child: AnimatedSlide(
              offset: active ? Offset.zero : hidden,
              duration: AppTokens.durSpring,
              curve: AppCurves.smooth,
              child: widget.children[i],
            ),
          ),
        );
      }),
    );
  }
}

/// 为 StatelessWidget 场景提供统一的占位提示，避免重复代码。
class HomeScreenStateHelper {
  HomeScreenStateHelper._();

  static void showNotImplemented(BuildContext context, String label) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label — ${l10n.loading}')),
    );
  }
}
