/// 宽屏双栏详情（平板 / 桌面窗口）：列表 | 详情 同屏。
///
/// 形态：HomeScreen 宽屏分支在导航栏右侧常驻一个「详情栏」，宽度约为窗口
/// 的 38%（400–560）。所有详情入口经 [AppNavigator.openContentDetail] 统一
/// 判定——窄屏整页路由（原行为），宽屏改为在详情栏内打开（列表不跳页，
/// 返回手势先关栏）。桌面窗口与平板横屏共用同一套判定（用户决策：平板与
/// 桌面共用宽屏排版）。
///
/// 手机档 / 分屏 / 悬浮窗（窗口宽 < 1120）行为与历史版本完全一致。
library;

import 'package:material_ui/material_ui.dart';

import '../../features/media/presentation/content_detail_screen.dart';
import '../models/media_item.dart';
import '../theme/app_tokens.dart';

/// 双栏详情全局控制器（单例）。
///
/// 宿主（HomeScreen 宽屏分支）在 build 时通过 [updateHost] 上报「当前是否
/// 具备双栏条件与窗口宽度」；各详情入口经 [maybeOpenPane] 判定。全局单份：
/// 跨 tab 共享、切 tab 不关闭；窗口缩到阈值以下由宿主负责收起。
class TwoPaneDetailController extends ChangeNotifier {
  TwoPaneDetailController._();

  /// 全局单例。
  static final TwoPaneDetailController instance = TwoPaneDetailController._();

  MediaItem? _item;
  String? _heroTag;

  /// 每次 open 自增：pane 内以 ValueKey(generation) 强制换内容时整树重建，
  /// 避免「上一个详情的状态（标签页 / 滚动位置）串到下一个详情」。
  int _generation = 0;

  /// 宿主是否在场（HomeScreen 宽屏分支已挂载）。
  bool _hostActive = false;

  /// 宿主上报的窗口宽度（取宿主侧全窗口宽，不随列表/详情栏压缩变化）。
  double _hostWindowWidth = 0;

  /// 详情栏是否打开。
  bool get isOpen => _item != null;

  /// 当前详情条目（open 后非空）。
  MediaItem? get item => _item;

  /// 当前详情条目的 heroTag（可能为 null）。
  String? get heroTag => _heroTag;

  /// 打开序号（pane 重建 key 用）。
  int get generation => _generation;

  /// 宿主上报：宽屏分支挂载状态与窗口宽度（build 期间调用，无通知副作用）。
  void updateHost({required bool active, required double windowWidth}) {
    _hostActive = active;
    _hostWindowWidth = windowWidth;
  }

  /// 宿主上报窗口宽度变化（窄屏分支也调用，保持判定最新）。
  void updateHostWidth(double windowWidth) {
    _hostWindowWidth = windowWidth;
    _hostActive = false;
  }

  /// 尝试在右侧详情栏打开 [item]。
  ///
  /// 返回 true = 已由双栏承接（调用方无需再路由）；false = 当前不具备双栏
  /// 条件（窄窗口 / 宿主不在场），调用方走整页路由（原行为）。
  bool open({required MediaItem item, String? heroTag}) {
    if (!_hostActive ||
        _hostWindowWidth < AppTokens.twoPaneBreakpoint) {
      return false;
    }
    _item = item;
    _heroTag = heroTag;
    _generation++;
    notifyListeners();
    return true;
  }

  /// 静态便捷判定：双栏可承接则开栏并返回 true，否则 false（不产生副作用）。
  ///
  /// 供 [AppNavigator.openContentDetail] 等入口先判定再路由。
  static bool maybeOpenPane({required MediaItem item, String? heroTag}) {
    return instance.open(item: item, heroTag: heroTag);
  }

  /// 关闭详情栏。
  void close() {
    if (!isOpen) return;
    _item = null;
    _heroTag = null;
    _generation++;
    notifyListeners();
  }
}

/// 右侧详情栏容器。
///
/// 承载 [ContentDetailScreen]（embedded 模式：返回钮关栏而非路由返回）。
/// 左缘发丝线与内容区分界；背景随主题 surface。
class TwoPaneDetailPane extends StatelessWidget {
  const TwoPaneDetailPane({
    super.key,
    required this.controller,
    required this.windowWidth,
  });

  final TwoPaneDetailController controller;

  /// 全窗口宽度（用于计算详情栏宽 = 窗口 38%，400–560）。
  final double windowWidth;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double paneWidth =
        (windowWidth * 0.38).clamp(400.0, 560.0);
    final MediaItem? item = controller.item;
    if (item == null) return const SizedBox.shrink();
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
  }
}
