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
  /// - 窄屏 / 无宿主处（推入式未承载页 / 深链冷启动）：整页路由（原行为）；
  /// - 宽屏（窗口 ≥ twoPaneBreakpoint）且祖先链有双栏宿主作用域（首页宽屏
  ///   分支或承载双栏的推入式列表页）：在右侧详情栏打开，列表不跳页。
  ///
  /// 判定与打开动作集中在 [TwoPaneDetailController.maybeOpenPane]。
  ///
  /// 深链（无 BuildContext）走 [openContentDetailViaNavigator]。
  static void openContentDetail(
    BuildContext context, {
    required MediaItem item,
    String? heroTag,
  }) {
    if (TwoPaneDetailController.maybeOpenPane(
      context: context,
      item: item,
      heroTag: heroTag,
    )) {
      return;
    }
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => ContentDetailScreen(item: item, heroTag: heroTag),
      ),
    );
  }

  /// [openContentDetail] 的深链变体：仅有 [NavigatorState] 时使用。
  ///
  /// 深链冷启动时栈上无宿主作用域，恒为整页路由（与历史行为一致）。
  static void openContentDetailViaNavigator(
    NavigatorState navigator, {
    required MediaItem item,
    String? heroTag,
  }) {
    navigator.push(
      AppPageRoute<void>(
        builder: (_) => ContentDetailScreen(item: item, heroTag: heroTag),
      ),
    );
  }
}
