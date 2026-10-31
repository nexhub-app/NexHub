/// 处理「用户点了桌面卡片」后的跳转。
///
/// 原生侧在拉起应用时把待跳转标记暂存（Android 走 Intent extra，鸿蒙走
/// want.parameters），Dart 侧在首帧 / 回前台时取走并导航。
///
/// 支持的目标：
/// * `continue` —— 打开最近一条带进度的内容详情页（继续观看卡）；
/// * `updates`  —— 回首页（追更卡，收藏书架在首页）；
/// * `downloads` —— 打开下载列表页；
/// * `stats`    —— 打开统计页。
library;

import 'package:material_ui/material_ui.dart';

import '../../features/downloads/presentation/download_list_screen.dart';
import '../../features/media/presentation/content_detail_screen.dart';
import '../../features/stats/presentation/stats_overview_screen.dart';
import '../history/history_manager.dart';
import '../models/plugin_config.dart';
import '../navigation/app_navigator.dart';
import 'home_widget_bridge.dart';

class HomeWidgetLauncher {
  HomeWidgetLauncher._();

  /// 取走卡片点击标记并跳转；无标记时直接返回。
  static Future<void> consumePending({required HistoryManager history}) async {
    if (!HomeWidgetBridge.isSupported) return;
    final String? route = await HomeWidgetBridge.takeLaunchRoute();
    if (route == null || route.isEmpty) return;
    final NavigatorState? navigator = await _waitNavigator();
    if (navigator == null) return;
    switch (route) {
      case 'continue':
        await _openContinue(navigator, history);
      case 'updates':
        _popToHome(navigator);
      case 'downloads':
        await _push(navigator, const DownloadListScreen());
      case 'stats':
        await _push(navigator, const StatsOverviewScreen());
      default:
        // 未知目标（未来扩展）静默忽略，避免把用户丢到白屏。
        break;
    }
  }

  static Future<void> _openContinue(
    NavigatorState navigator,
    HistoryManager history,
  ) async {
    final HistoryEntry? entry = _latestEntry(history);
    if (entry == null) return;
    await _push(navigator, ContentDetailScreen(item: entry.toMediaItem()));
  }

  /// 回首页：卡片是从桌面点进来的，栈底就是 HomeScreen，弹回即可。
  static void _popToHome(NavigatorState navigator) {
    navigator.popUntil((Route<dynamic> route) => route.isFirst);
  }

  static Future<void> _push(NavigatorState navigator, Widget page) {
    return navigator.push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  /// 与卡片数据同口径：三类历史里取最近一条（跳过隐藏与媒体服务器条目）。
  static HistoryEntry? _latestEntry(HistoryManager history) {
    HistoryEntry? best;
    for (final SourceType type in SourceType.values) {
      for (final HistoryEntry e in history.historyFor(type)) {
        if (e.hidden) continue;
        if (e.kind == 'mediaServer') continue;
        if (best == null || e.viewedAt > best.viewedAt) best = e;
      }
    }
    return best;
  }

  /// 首帧刚触发时 Navigator 可能还未挂载，短轮询最多 1 秒（同接续恢复的做法）。
  static Future<NavigatorState?> _waitNavigator() async {
    for (int i = 0; i < 20; i++) {
      final NavigatorState? navigator = AppNavigator.navigator;
      if (navigator != null) return navigator;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return null;
  }
}
