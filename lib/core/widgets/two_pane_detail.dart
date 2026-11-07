// 宽屏双栏详情（平板 / 桌面窗口）：列表 | 详情 同屏。
//
// 形态：宿主（首页宽屏分支 / 搜索页）在内容区右侧常驻一个「详情栏」，宽度
// 默认约为窗口的 38%，可拖拽分隔条自由调整（钳制保证列表侧可用）；左缘
// 发丝线分界。所有详情入口经 AppNavigator.openContentDetail 统一判定——
// 窄屏 / 无宿主处整页路由（原行为），设置开关开启 + 有宿主作用域 + 窗口
// 宽 >= 1120 时在详情栏内打开（列表不跳页，返回手势先关栏）。
//
// 全局单份详情状态：跨 tab、跨推入式页面返回首页后详情延续；窗口缩到
// 阈值以下或设置关闭时由宿主自动收起。手机档与窄窗口行为与历史版本一致。
library;

import 'package:material_ui/material_ui.dart';

import '../../features/media/presentation/content_detail_screen.dart';
import '../models/media_item.dart';
import '../platform/platform_service.dart';
import '../settings/detail_appearance_settings.dart';
import '../theme/app_tokens.dart';

/// 双栏详情全局控制器（单例）。
///
/// 详情入口经 [maybeOpenPane] 判定：设置开关开启 + 调用方祖先链上有宿主
/// 作用域（[TwoPaneDetailScope]）+ 窗口宽 >= [AppTokens.twoPaneBreakpoint]
/// 才开栏；否则入口回退整页路由（原行为）。
class TwoPaneDetailController extends ChangeNotifier {
  TwoPaneDetailController._();

  /// 全局单例。
  static final TwoPaneDetailController instance = TwoPaneDetailController._();

  MediaItem? _item;
  String? _heroTag;

  /// 每次 open / close 自增。pane 以 ValueKey(generation) 整树重建，
  /// 避免上一个详情的标签页 / 滚动位置串到下一个详情。
  int _generation = 0;

  /// 详情栏宽度（用户拖拽值；0 = 未拖拽过，按窗口 38% 默认）。
  /// 独立于 ChangeNotifier：拖拽帧频通知只重建分隔条与详情栏本身，
  /// 不重建整个宿主 Row（列表侧子树不变）。
  final ValueNotifier<double> paneWidth = ValueNotifier<double>(0);

  /// 详情栏是否打开。
  bool get isOpen => _item != null;

  /// 当前详情条目（open 后非空）。
  MediaItem? get item => _item;

  /// 当前详情条目的 heroTag（可能为 null）。
  String? get heroTag => _heroTag;

  /// 打开序号（pane 重建 key 用）。
  int get generation => _generation;

  /// 详情栏设置开关（设置 → 外观与语言 → 详情页外观 → 双栏详情）。
  static bool get settingEnabled =>
      DetailAppearanceStore.instance.settings.twoPaneDetailEnabled;

  /// 双栏形态闸门：桌面 / 2in1 全可用；触屏设备按最短边判平板
  /// （≥600 为平板才可用）——手机即使因显示缩放导致逻辑宽度很大，
  /// 最短边仍小于 600，绝不会开双栏（用户决策：双栏不在手机端显示）。
  static bool formFactorAllows(Size size) {
    if (PlatformService.instance.isDesktopForm) {
      return true;
    }
    return size.shortestSide >= 600;
  }

  /// 尝试在右侧详情栏打开 [item]。
  ///
  /// 条件：设置开关开启 + 形态为桌面 / 平板（非手机）+ 祖先链上有
  /// [TwoPaneDetailScope] + 窗口宽 >= 阈值。返回 true = 已由双栏承接
  /// （调用方无需再路由）；false = 回退整页路由（原行为）。
  bool open({
    required BuildContext context,
    required MediaItem item,
    String? heroTag,
  }) {
    if (!settingEnabled) {
      return false;
    }
    final Size size = MediaQuery.sizeOf(context);
    if (!formFactorAllows(size)) {
      return false;
    }
    if (TwoPaneDetailScope.of(context) == null) {
      return false;
    }
    if (size.width < AppTokens.twoPaneBreakpoint) {
      return false;
    }
    _item = item;
    _heroTag = heroTag;
    _generation++;
    notifyListeners();
    return true;
  }

  /// 静态便捷判定：双栏可承接则开栏并返回 true，否则 false。
  ///
  /// 供 AppNavigator.openContentDetail 整页路由前判定。
  static bool maybeOpenPane({
    required BuildContext context,
    required MediaItem item,
    String? heroTag,
  }) {
    return instance.open(context: context, item: item, heroTag: heroTag);
  }

  /// 关闭详情栏。
  void close() {
    if (!isOpen) {
      return;
    }
    _item = null;
    _heroTag = null;
    _generation++;
    notifyListeners();
  }

  /// 按当前窗口宽计算详情栏实际宽度：用户拖拽值优先，未拖拽过取窗口 38%，
  /// 钳制在 [400, 窗口-520]（保证列表侧保留可用宽度）。
  double paneWidthFor(double windowWidth) {
    final double requested =
        paneWidth.value > 0 ? paneWidth.value : windowWidth * 0.38;
    final double maxW = (windowWidth - 520).clamp(400.0, double.infinity);
    return requested.clamp(400.0, maxW);
  }

  /// 拖拽更新详情栏宽度（[dx] 为分隔条横向位移，向左拖 = 加宽）。
  void dragPaneWidth(double dx, double windowWidth) {
    final double current = paneWidthFor(windowWidth);
    paneWidth.value = current - dx;
  }
}

/// 宿主作用域：标记「当前祖先链可承载双栏详情」。
///
/// 由 [TwoPaneDetailHost] 自动挂载；[of] 返回 null = 祖先链无宿主，详情
/// 入口回退整页路由。open 判定用 getInherited（事件期查询，不注册依赖）。
class TwoPaneDetailScope extends InheritedWidget {
  const TwoPaneDetailScope({super.key, required super.child});

  @override
  bool updateShouldNotify(InheritedWidget oldWidget) => false;

  /// 向上查宿主作用域（不注册依赖，供事件期判定）。
  static TwoPaneDetailScope? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TwoPaneDetailScope>();
}

/// 双栏详情宿主（首页宽屏分支 / 搜索页用）。
///
/// 包裹整页（含 AppBar）或页面 body：窗口宽 >= 阈值且有详情打开时把内容
/// 压缩到左侧、右侧渲染 [TwoPaneDetailPane]，中间为可拖拽分隔条；系统返回
/// 先关栏再退页；窗口缩到阈值以下或设置关闭时自动收起（帧后 close，避免
/// build 期间 notifyListeners）。
class TwoPaneDetailHost extends StatelessWidget {
  const TwoPaneDetailHost({super.key, required this.child});

  /// 左侧内容（页面原有内容）。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final TwoPaneDetailController controller = TwoPaneDetailController.instance;
    return TwoPaneDetailScope(
      child: ListenableBuilder(
        listenable: controller,
        builder: (BuildContext context, _) {
          final double width = MediaQuery.sizeOf(context).width;
          final bool hostable = width >= AppTokens.twoPaneBreakpoint;
          // 窗口缩到阈值以下，或用户在设置里关掉双栏：帧后收起
          // （build 期间不能 notifyListeners）。
          if ((!hostable || !TwoPaneDetailController.settingEnabled) &&
              controller.isOpen) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              controller.close();
            });
          }
          return PopScope(
            canPop: !controller.isOpen,
            onPopInvokedWithResult: (bool didPop, Object? result) {
              if (!didPop && controller.isOpen) {
                controller.close();
              }
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(child: child),
                if (controller.isOpen) ...<Widget>[
                  _TwoPaneDivider(controller: controller, windowWidth: width),
                  TwoPaneDetailPane(controller: controller, windowWidth: width),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 可拖拽分隔条：横向拖动自由调整详情栏宽度。
///
/// 视觉：默认细灰线，悬停 / 拖拽时浮现主题色并加宽，光标切换为左右调整态。
/// 拖拽经 ValueNotifier 只重建分隔条与详情栏，不惊动列表侧。
class _TwoPaneDivider extends StatefulWidget {
  const _TwoPaneDivider({required this.controller, required this.windowWidth});

  final TwoPaneDetailController controller;
  final double windowWidth;

  @override
  State<_TwoPaneDivider> createState() => _TwoPaneDividerState();
}

class _TwoPaneDividerState extends State<_TwoPaneDivider> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _active = true),
      onExit: (_) => setState(() => _active = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _active = true),
        onHorizontalDragUpdate: (DragUpdateDetails d) {
          widget.controller.dragPaneWidth(d.delta.dx, widget.windowWidth);
        },
        onHorizontalDragEnd: (_) => setState(() => _active = false),
        onHorizontalDragCancel: () => setState(() => _active = false),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: _active ? 3 : 1,
            height: double.infinity,
            color: _active
                ? scheme.primary.withValues(alpha: 0.55)
                : scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

/// 右侧详情栏容器。
///
/// 承载 ContentDetailScreen（embedded 模式：返回钮关栏而非路由返回）。
/// 宽度 = [TwoPaneDetailController.paneWidthFor]（默认窗口 38%，可拖拽），
/// ValueListenableBuilder 监听宽度变化只重建本栏，不惊动列表侧。
class TwoPaneDetailPane extends StatelessWidget {
  const TwoPaneDetailPane({
    super.key,
    required this.controller,
    required this.windowWidth,
  });

  final TwoPaneDetailController controller;

  /// 全窗口宽度（拖拽钳制与默认宽计算用）。
  final double windowWidth;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final MediaItem? item = controller.item;
    if (item == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<double>(
      valueListenable: controller.paneWidth,
      builder: (BuildContext context, double _, Widget? __) {
        final double paneWidth = controller.paneWidthFor(windowWidth);
        return SizedBox(
          width: paneWidth,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(
                left: BorderSide(color: scheme.outlineVariant, width: 0.5),
              ),
            ),
            child: ContentDetailScreen(
              key: ValueKey<String>('two-pane-detail-${controller.generation}'),
              item: item,
              heroTag: controller.heroTag,
              embedded: true,
              onClose: controller.close,
            ),
          ),
        );
      },
    );
  }
}
