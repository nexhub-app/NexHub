import 'package:material_ui/material_ui.dart';

import '../../features/media/presentation/content_detail_screen.dart';
import '../models/media_item.dart';
import '../widgets/two_pane_detail.dart';
import 'app_page_route.dart';

/// 全局 Navigator 入口（供无 BuildContext 的深链 / 接续跳转使用）。
///
/// 在 [MaterialApp.navigatorKey] 注册；[key] 在 MaterialApp 挂载后可用。
class AppNavigator {
  AppNavigator._();

  static final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();

  static NavigatorState? get navigator => key.currentState;

  /// 统一详情页打开入口。
  ///
  /// 所有内容详情（漫画 / 小说 / 影视统一详情页）的跳转都经此函数：
  /// - 窄屏 / 推入式页面 / 深链冷启动前：整页路由（原行为）；
  /// - 宽屏（窗口 ≥ twoPaneBreakpoint）且当前处于根路由（首页可见）：
  ///   在右侧详情栏打开而非整页路由，列表不跳页、返回手势先关栏。
  ///
  /// 仅根路由承接双栏：从搜索 / 在线列表等推入式页面打开时，详情栏被该
  /// 路由盖住不可见，故保持整页路由（推入式页面自身的双栏由后续批次承载）。
  ///
  /// 深链（无 BuildContext）走 [openContentDetailViaNavigator]。
  static void openContentDetail(
    BuildContext context, {
    required MediaItem item,
    String? heroTag,
  }) {
    final NavigatorState nav = Navigator.of(context);
    if (!nav.canPop() &&
        TwoPaneDetailController.maybeOpenPane(item: item, heroTag: heroTag)) {
      return;
    }
    nav.push(
      AppPageRoute<void>(
        builder: (_) => ContentDetailScreen(item: item, heroTag: heroTag),
      ),
    );
  }

  /// [openContentDetail] 的深链变体：仅有 [NavigatorState] 时使用。
  static void openContentDetailViaNavigator(
    NavigatorState navigator, {
    required MediaItem item,
    String? heroTag,
  }) {
    if (!navigator.canPop() &&
        TwoPaneDetailController.maybeOpenPane(item: item, heroTag: heroTag)) {
      return;
    }
    navigator.push(
      AppPageRoute<void>(
        builder: (_) => ContentDetailScreen(item: item, heroTag: heroTag),
      ),
    );
  }
}
