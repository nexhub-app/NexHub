/// 统一触觉反馈工具 —— 全部走 Flutter 官方 [HapticFeedback]。
///
/// 2026-09-25 起 Android 端不再走自定义 `nexhub/haptic` 原生通道（原通道
/// 用 Vibrator 组合原语绕过系统「触摸反馈」设置的实现已随本变更删除），
/// 统一使用官方 [HapticFeedback]：Android 上映射到平台官方触感常量
/// （selectionClick / light / medium / heavy），iOS 映射到对应 UI 触觉
/// 生成器，桌面端调用安全无副作用。
///
/// MD3 模式 → 官方 HapticFeedback 对照（m3.material.io/foundations/designing-haptics）：
/// - [tick]：离散刻度/单选（滑块分档、分段按钮、导航项、筛选 chip）→ selectionClick；
/// - [click]：点按确认（按钮、列表项、FAB）→ lightImpact；
/// - [toggleOn] / [toggleOff]：开关、复选框 → selectionClick；
/// - [thunk]：重按（长按开始、拖拽拿起、破坏性操作确认）→ heavyImpact；
/// - [confirm]：任务成功（下载完成、导入成功）→ mediumImpact；
/// - [reject]：任务失败/操作被拒 → heavyImpact；
/// - [gestureThreshold]：手势越阈（下拉刷新触发）→ lightImpact。
///
/// 鸿蒙适配：OHOS 引擎把各常量实现为固定时长的裸震动（selectionClick
/// 100ms、mediumImpact 150ms、heavyImpact 300ms，无振幅控制，见引擎
/// PlatformPlugin.vibrateHapticFeedback），实际手感比 Android 的振幅包络
/// 触感重得多。故在鸿蒙上整体降一档：轻量反馈统一用 lightImpact(25ms)，
/// 确认类用 selectionClick(100ms)，重击类用 mediumImpact(150ms)。
library;

import 'package:flutter/services.dart';

import '../platform/platform_service.dart';

/// 触觉反馈入口。各方法即 MD3 触感语义，实现全部为官方 [HapticFeedback]。
class AppHaptics {
  AppHaptics._();

  static bool get _isOhos => PlatformService.instance.isOHOS;

  /// MD3「Tick」：轻刻度反馈。离散值变化与单选：滑块分档、分段按钮、
  /// 底部导航切换、筛选 chip 选中、翻页。
  static Future<void> tick() => _isOhos
      ? HapticFeedback.lightImpact()
      : HapticFeedback.selectionClick();

  /// MD3「Click」：点按确认。按钮、列表项、图标按钮等常规点按。
  static Future<void> click() => HapticFeedback.lightImpact();

  /// MD3「Toggle on」：开关/复选框切换到开启。
  static Future<void> toggleOn() => _isOhos
      ? HapticFeedback.lightImpact()
      : HapticFeedback.selectionClick();

  /// MD3「Toggle off」：开关/复选框切换到关闭。
  static Future<void> toggleOff() => _isOhos
      ? HapticFeedback.lightImpact()
      : HapticFeedback.selectionClick();

  /// MD3「Thunk」：重击。长按菜单开始、拖拽拿起（重排序）、破坏性操作确认。
  static Future<void> thunk() =>
      _isOhos ? HapticFeedback.mediumImpact() : HapticFeedback.heavyImpact();

  /// MD3「Confirm」：任务成功确认。下载/安装完成、导入/保存成功。
  static Future<void> confirm() => _isOhos
      ? HapticFeedback.selectionClick()
      : HapticFeedback.mediumImpact();

  /// MD3「Reject」：任务失败/操作被拒。下载失败、校验不通过等错误场景。
  static Future<void> reject() =>
      _isOhos ? HapticFeedback.mediumImpact() : HapticFeedback.heavyImpact();

  /// MD3「Gesture threshold」：手势越过触发阈值。下拉刷新开始刷新的一刻。
  static Future<void> gestureThreshold() => HapticFeedback.lightImpact();

  // ── 旧语义兼容（既有调用点渐进迁移到上方 MD3 模式）──────────────

  /// 通用点按/导航反馈 → MD3 [click]。
  static Future<void> selectionClick() => click();

  /// 轻反馈 → MD3 [tick]。
  static Future<void> light() => tick();

  /// 确认类动作 → MD3 [confirm]。
  static Future<void> medium() => confirm();

  /// 重反馈（长按/破坏性）→ MD3 [thunk]。
  static Future<void> heavy() => thunk();
}
