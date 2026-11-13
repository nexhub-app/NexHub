import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';

import '../../../core/comic/models/reader_preferences.dart';
import '../../../core/utils/app_haptics.dart';

/// 点击区域动作。
enum _TapAction { prev, next, toggle }

/// 单个点击热区（坐标为相对于阅读区的比例 0..1）。
class _Region {
  final double left;
  final double top;
  final double width;
  final double height;
  final _TapAction action;
  const _Region(this.left, this.top, this.width, this.height, this.action);
}

/// 阅读器点击区域覆盖层（文档 7.3）。
///
/// 用一个铺满阅读区的 [Listener] 监听指针 down / up，按抬起坐标命中对应热区
/// 分发到 prev / next / toggle。之所以不用 [GestureDetector]：在 widget 测试中
/// 验证发现，[GestureDetector] 的识别器由 `RawGestureDetector` 内部的
/// `Listener`（deferToChild）在命中测试时喂入指针，而该内部 Listener 在以
/// `SizedBox.expand()` 之类「自身不可命中」的 child 作下层时不会进入命中路径，
/// 导致识别器拿不到指针、单击永远不触发（即便覆盖层几何与 behavior 都正确）。
/// 直接用 [Listener] 的 `onPointerDown` / `onPointerUp` 则稳定可靠。
///
/// 双击（仅切换热区）触发 `onZoom` 缩放，与单击导航互不冲突。支持 5 种布局。
///
/// 在布局之上叠加 [TapZoneInvert] 方向反转：leftRight 反转横向翻页（竖向
/// webtoon 模式下不生效），upDown 反转竖向滚动，all 两者都反转。
class ReaderTapZones extends StatefulWidget {
  final ReaderTapZoneLayout layout;
  final TapZoneInvert tapZoneInvert;
  final bool isVertical; // webtoon / 竖向：prev=上滚，next=下滚
  final bool isWebtoon; // 条漫：拖拽交给原生 ListView 滚动，不在此翻页
  final bool isRTL; // 翻页 RTL：拖拽方向反转
  /// 拖拽（滑动）翻页回调：拖拽超过阈值时调用，[next]=true 下一页 / false 上一页。
  /// 仅翻页模式生效；条漫不触发（交给原生连续滚动）。
  final void Function(bool next)? onDragPage;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToggleUi;
  final VoidCallback? onZoom;

  /// 在指定位置缩放（桌面 Shift+左键 兜底双击缩放）。为 null 时由调用方回退到 [onZoom]。
  final void Function(Offset)? onZoomAt;

  /// 缩放状态读取：放大态（scale > 1）时单指单击不触发翻页 / 导航（手势 bug #4）。
  /// 为 null 时按未放大处理。
  final bool Function()? isZoomed;

  /// 手势交互态读取：当前缩放矩阵 scale 不等于 1.0（既含放大 >1，也含缩小 <1）时，
  /// 单指单击不派发导航（prev/next/toggle）——修复 Bug3「双击缩放三态消失」的根治：
  /// 双击【第一击】若不拦截，会立即派发翻页，[onPrev]/[onNext] 里的 _resetZoom 会把
  /// 0.5x 缩小态清掉，导致三态循环 0.5→2 失效（永远只能缩小）。缩小态同样视为
  /// 「手势交互态」，第一击仅记录点击（供第二击构成双击）而不翻页。
  /// 与 [isZoomed] 的区别：后者（scale > 1.001）继续用于平移 / 拖拽判断，语义不变。
  /// 为 null 时按 [isZoomed] 的结果处理（保持旧行为）。
  final bool Function()? isZoomInteractive;

  /// 双指捏合更新回调：以双指中点为焦点、以起始距离为基准的累计比例 [scaleFactor]
  /// （0 表示尚未达到 2 指，不会回调）。屏幕级手动跟踪指针实现，不依赖每页的
  /// GestureDetector——条漫模式双指落在不同页时依然生效（根治）。
  final void Function(double scaleFactor, Offset focal)? onPinchUpdate;

  /// 双指捏合结束回调（任一指抬起 / 全部抬起时触发一次）。
  final VoidCallback? onPinchEnd;

  /// 放大态单指拖动回调（图片平移）。未放大时不回调（交给底层滚动 / 翻页）。
  final void Function(Offset delta)? onPanUpdate;

  /// 滚轮 / 触控板滚动回调（屏幕级 PointerScrollEvent）。为 null 时不处理，
  /// 事件透传给底层（如条漫未放大时交给 Scrollable 连续滚动）。
  final void Function(PointerScrollEvent event)? onPointerSignal;

  /// 触控板（precision touchpad）捏合更新回调：trackpad 手势是独立事件流
  /// （[PointerPanZoomUpdateEvent]，kind=trackpad），不产生触摸 PointerDown 事件，
  /// 必须走 [Listener.onPointerPanZoomUpdate] 才能收到（桌面触摸板捏合）。
  /// [scale] 为累计缩放比例（相对手势开始）、[focal] 为手势焦点（左上原点局部坐标）。
  final void Function(double scale, Offset focal)? onTrackpadZoom;

  /// 触控板双指平移回调（放大态下平移图片）。[delta] 为自上次事件的增量。
  final void Function(Offset delta)? onTrackpadPan;

  /// 桌面右键回调（弹出图片操作菜单，与长按同款）。为 null 时不响应右键。
  final VoidCallback? onSecondaryTap;

  /// 长按回调（用于弹出图片「保存 / 分享」菜单等）。为 null 时不检测长按。
  final VoidCallback? onLongPress;

  /// 长按回调（带触点坐标， 长按缩放）。非 null 时优先于 [onLongPress]，
  /// 传入按下位置（左上原点坐标），用于「按触点 / 按屏幕中心」的定点缩放。
  final void Function(Offset)? onLongPressAt;

  /// 长按松手回调（长按缩放退出）：长按已触发（[onLongPressAt] / [onLongPress]
  /// 执行过）且手指抬起/取消时调用一次。为 null 时不回调。
  final VoidCallback? onLongPressRelease;

  /// 双击回退回调（单击即时 + 双击回退）：单击翻页【立即】执行，若在
  /// 双击窗口内出现第二次点击，则先撤销前一次单击已触发的翻页（prev/next），
  /// 再执行双击缩放。参数 [next] 为被撤销的单击方向（true=上一击是下一页）。
  /// 中心 toggle 区单击不翻页，无需回退。为 null 时不回退。
  final void Function(bool next)? onUndoPageTurn;

  /// 单击拦截：每次命中热区的单击（含双击 / Shift+点击前的首次抬起）都会先调用，
  /// 返回 true 则吞掉本次单击（不执行 prev/next/toggle、不触发缩放）。
  /// 用于内联设置面板打开时「点阅读区任意处关闭面板」，与小说阅读器行为一致。
  /// 为 null 时不拦截。
  final bool Function()? onTapIntercept;

  /// 互动阅读层点按钩子：中心 / toggle 热区单击、且不在缩放交互态时，以
  /// 全局坐标调用；返回 true 表示宿主已消费（如聚焦 / 收回页面），本次不再
  /// 派发 toggle UI。点击时间 / 位置仍会记录，保证紧随的第二次点击构成双击缩放。
  final bool Function(Offset globalPosition)? onTapAt;

  /// 控制栏区域判定：返回 true 表示该坐标落在顶部/底部控制栏上，此次指针不参与
  /// 热区翻页，交给控制栏自身的按钮处理。避免控制栏展开时点按钮误触发翻页。
  /// 为 null 时不做保护（例如控制栏隐藏的沉浸阅读状态）。
  final bool Function(Offset)? isToolbarRegion;

  /// 是否渲染点击区域预览（彩色块 + 标签）。用于设置页预览，开启时不响应手势。
  final bool showPreview;

  /// 预览标签（key 为 'prev' / 'next' / 'toggle'）。
  final Map<String, String>? previewLabels;

  const ReaderTapZones({
    super.key,
    required this.layout,
    this.tapZoneInvert = TapZoneInvert.none,
    required this.isVertical,
    this.isWebtoon = false,
    this.isRTL = false,
    this.onDragPage,
    required this.onPrev,
    required this.onNext,
    required this.onToggleUi,
    this.onZoom,
    this.onZoomAt,
    this.isZoomed,
    this.isZoomInteractive,
    this.onPinchUpdate,
    this.onPinchEnd,
    this.onPanUpdate,
    this.onPointerSignal,
    this.onTrackpadZoom,
    this.onTrackpadPan,
    this.onSecondaryTap,
      this.onLongPress,
      this.onLongPressAt,
      this.onLongPressRelease,
      this.onUndoPageTurn,
      this.onTapIntercept,
      this.onTapAt,
      this.isToolbarRegion,
      this.showPreview = false,
      this.previewLabels,
  });

  @override
  State<ReaderTapZones> createState() => _ReaderTapZonesState();
}

class _ReaderTapZonesState extends State<ReaderTapZones> {
  int? _activePointer;
  Offset? _downPos;
  DateTime? _downTime;
  bool _downShift = false;

  /// 当前按下的所有指针（用于识别双指等多指手势）。首根落下的指针记为 [_activePointer]
  /// 用于单击/双击/拖拽判定；后续落下的指针把 [_multiTouch] 置真，覆盖层不再派发翻页，
  /// 把缩放手势完全交给底层图片自身的 scale 识别器（修复 「捏合被误判为翻页」）。
  final Set<int> _activePointers = <int>{};
  bool _multiTouch = false;

  /// 双指捏合跟踪（屏幕级，不依赖每页 GestureDetector）：记录每根指针当前位置、
  /// 起始双指距离与中点。≥2 指时按「当前距离 / 起始距离」回调 [widget.onPinchUpdate]。
  final Map<int, Offset> _pinchPoints = <int, Offset>{};
  double? _pinchStartDist;
  Offset? _pinchStartFocal;
  bool _pinching = false;

  /// 放大态单指平移：记录上一帧指针位置，计算增量回调 [widget.onPanUpdate]。
  Offset? _lastPanPos;

  /// 覆盖层实际尺寸（Listener 的父级 LayoutBuilder 测得）。热区命中判定必须用
  /// 此尺寸而非屏幕尺寸 [MediaQuery.sizeOf]：阅读区下方有 AppBar / BottomBar /
  /// 状态栏占位时，屏幕高度 > 阅读区高度，热区按比例算出后整体下移，底部热区
  /// 落在可视区之外，用户点不到。非全屏时尤其明显；全屏沉浸时两尺寸恰好相等
  /// 故 bug 被掩盖。
  Size? _currentSize;

  // 双击检测：记录上一次「已分发的单击」时间与位置。
  DateTime? _lastTapTime;
  Offset? _lastTapPos;

  /// 上一次「已分发」的单击动作（双击窗口内用于「单击即时 + 双击回退」）。
  /// 仅记录真实执行过导航/切换的动作；缩放态、拖拽、拦截等未翻页场景置 null。
  _TapAction? _lastTapAction;

  // 长按检测：按下后启动定时器，到阈值仍未抬起且未明显移动则触发。
  Timer? _longPressTimer;
  bool _longPressFired = false;

  /// 长按已触发且手指仍未抬起（用于松手时回调 [widget.onLongPressRelease]）。
  bool _longPressHeld = false;

  // 单击派发延迟定时器：单击命中后延迟一个双击窗口再派发，若期间出现双击则取消，
  // 从而「双击仅缩放、不触发导航」（手势 bug #5）。为 null 表示无待派发单击。
  Timer? _tapTimer;

  static const double _tapSlop = 18.0; // 移动超过此值不算 tap
  static const Duration _tapTimeout = Duration(milliseconds: 400);
  static const Duration _doubleTapTimeout = Duration(milliseconds: 300);
  static const double _doubleTapSlop = 36.0;
  static const Duration _longPressThreshold = Duration(milliseconds: 500);

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _tapTimer?.cancel();
    super.dispose();
  }

  /// 启动长按定时器（仅在 [widget.onLongPress] 或 [widget.onLongPressAt] 非空时）。
  void _startLongPressTimer(int pointer) {
    if (widget.onLongPress == null && widget.onLongPressAt == null) return;
    _longPressTimer?.cancel();
    _longPressFired = false;
    _longPressHeld = false;
    _longPressTimer = Timer(_longPressThreshold, () {
      if (_activePointer == pointer) {
        _longPressFired = true;
        _longPressHeld = true;
        final pos = _downPos;
        // 长按缩放启动：一次轻震确认进入手势。
        AppHaptics.light();
        if (widget.onLongPressAt != null && pos != null) {
          widget.onLongPressAt!(pos);
        } else {
          widget.onLongPress!();
        }
      }
    });
  }

  /// 指针移动超过 slop 则取消长按（避免拖拽误触发）。
  void _maybeCancelLongPress(Offset pos) {
    final Offset? down = _downPos;
    if (down == null) return;
    if ((pos - down).distance > _tapSlop) {
      _longPressTimer?.cancel();
    }
  }

  List<_Region> _buildRegions() {
    switch (widget.layout) {
      case ReaderTapZoneLayout.leftRight:
        return const <_Region>[
          _Region(0, 0, 0.45, 1, _TapAction.prev),
          _Region(0.45, 0, 0.1, 1, _TapAction.toggle),
          _Region(0.55, 0, 0.45, 1, _TapAction.next),
        ];
      case ReaderTapZoneLayout.lShape:
        // 两个 L 形 + 中心 toggle（与小说 tap_zone_resolver.dart 保持一致）：
        // prev = 左列 + 下中条；next = 右列 + 上中条；toggle = 中心方块。
        return const <_Region>[
          _Region(0, 0, 0.33, 1, _TapAction.prev), // 左列（全高）
          _Region(0.67, 0, 0.33, 1, _TapAction.next), // 右列（全高）
          _Region(0.33, 0, 0.34, 0.33, _TapAction.next), // 上中条
          _Region(0.33, 0.67, 0.34, 0.33, _TapAction.prev), // 下中条
          _Region(0.33, 0.33, 0.34, 0.34, _TapAction.toggle), // 中心
        ];
      case ReaderTapZoneLayout.kindle:
        return const <_Region>[
          _Region(0, 0, 1, 0.15, _TapAction.toggle),
          _Region(0, 0.15, 0.35, 0.85, _TapAction.prev),
          _Region(0.35, 0.15, 0.65, 0.85, _TapAction.next),
        ];
      case ReaderTapZoneLayout.bothSides:
        return const <_Region>[
          _Region(0, 0.15, 0.33, 0.7, _TapAction.next),
          _Region(0.67, 0.15, 0.33, 0.7, _TapAction.next),
          _Region(0.33, 0.7, 0.34, 0.3, _TapAction.prev),
          _Region(0.33, 0, 0.34, 0.15, _TapAction.toggle),
        ];
      case ReaderTapZoneLayout.off:
        return const <_Region>[_Region(0, 0, 1, 1, _TapAction.toggle)];
    }
  }

  Rect _rect(_Region r, double w, double h) =>
      Rect.fromLTWH(r.left * w, r.top * h, r.width * w, r.height * h);

  _TapAction? _actionAt(Offset p, double w, double h) {
    for (final r in _buildRegions()) {
      if (_rect(r, w, h).contains(p)) return r.action;
    }
    return null;
  }

  void _onPointerDown(PointerDownEvent e) {
    // 桌面右键：直接弹出图片操作菜单（保存 / 分享 / 设封面），长按的桌面等价入口（#10）。
    // 不进入单击 / 双击 / 长按流程，避免误触发翻页。
    if (e.kind == PointerDeviceKind.mouse &&
        e.buttons == kSecondaryMouseButton) {
      widget.onSecondaryTap?.call();
      return;
    }
    // 先记录指针位置：第二根手指落下时必须能从 [_pinchPoints] 拿到两根的位置，
    // 才能算出双指起始距离（起始距离用于捏合比例基准）。
    _pinchPoints[e.pointer] = e.localPosition;
    if (_activePointers.isEmpty) {
      // 首根手指：记录用于单击 / 双击 / 拖拽判定的基准数据。
      _activePointer = e.pointer;
      _downPos = e.localPosition;
      _downTime = DateTime.now();
      _downShift = HardwareKeyboard.instance.isShiftPressed;
      _multiTouch = false;
      _longPressFired = false;
      _startLongPressTimer(e.pointer);
    } else {
      // 第二根及以上手指落下：标记多指手势（如双指捏合），取消长按判定。
      _multiTouch = true;
      _longPressTimer?.cancel();
      // 屏幕级捏合开始：记录双指起始距离与中点（根治——不依赖每页 GestureDetector，
      // 条漫模式下双指落在不同页也能识别）。
      _pinching = true;
      final List<Offset> pts = _pinchPoints.values.toList();
      if (pts.length >= 2) {
        _pinchStartDist = (pts[0] - pts[1]).distance;
        _pinchStartFocal = (pts[0] + pts[1]) / 2;
      }
    }
    _activePointers.add(e.pointer);
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_activePointers.isEmpty) return;
    if (!_pinchPoints.containsKey(e.pointer)) return;
    _pinchPoints[e.pointer] = e.localPosition;
    // 双指捏合：以起始距离为基准，回调「当前距离 / 起始距离」累计比例与双指中点
    // （屏幕级坐标，条漫跨页也生效）。
    if (_pinching && _pinchPoints.length >= 2) {
      _longPressTimer?.cancel();
      final List<Offset> pts = _pinchPoints.values.toList();
      final double? start = _pinchStartDist;
      final double dist = (pts[0] - pts[1]).distance;
      if (start != null && start > 0 && _pinchStartFocal != null) {
        final Offset focal = (pts[0] + pts[1]) / 2;
        widget.onPinchUpdate?.call(dist / start, focal);
      }
      return;
    }
    if (_multiTouch) {
      _longPressTimer?.cancel();
      return;
    }
    // 单指：放大态 → 图片平移（增量回调）；未放大 → 交给底层滚动 / 翻页，仅取消长按判定。
    final bool zoomed = widget.isZoomed?.call() ?? false;
    if (zoomed) {
      final Offset pos = e.localPosition;
      final Offset? last = _lastPanPos;
      if (last != null) widget.onPanUpdate?.call(pos - last);
      _lastPanPos = pos;
      // 放大态拖动同样取消长按：移动超过 slop 即按「拖动」处理，不弹长按菜单，
      // 否则长按定时器（500ms）到点会与拖动「打仗」——拖到一半弹菜单。
      _maybeCancelLongPress(pos);
      return;
    }
    _lastPanPos = null;
    _maybeCancelLongPress(e.localPosition);
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _longPressTimer?.cancel();
    _activePointers.remove(e.pointer);
    _pinchPoints.remove(e.pointer);
    _lastPanPos = null;
    if (_pinching && _activePointers.length < 2) {
      _pinching = false;
      _pinchStartDist = null;
      _pinchStartFocal = null;
      widget.onPinchEnd?.call();
    }
    if (_activePointers.isEmpty) {
      _multiTouch = false;
      _activePointer = null;
      _downPos = null;
      _downTime = null;
      _downShift = false;
      _longPressFired = false;
      if (_longPressHeld) {
        _longPressHeld = false;
        widget.onLongPressRelease?.call();
      }
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    _longPressTimer?.cancel();
    _activePointers.remove(e.pointer);
    _pinchPoints.remove(e.pointer);
    _lastPanPos = null;
    // 双指捏合中：任一指抬起 → 捏合结束（回调一次）。
    if (_pinching && _activePointers.length < 2) {
      _pinching = false;
      _pinchStartDist = null;
      _pinchStartFocal = null;
      widget.onPinchEnd?.call();
    }
    // 多指手势（如双指捏合缩放）：覆盖层不派发翻页 / 导航。
    // 只要本次手势曾出现第二根手指，无论抬起哪一根都不触发单击 / 双击 / 拖拽动作。
    if (_multiTouch) {
      if (_activePointers.isEmpty) {
        _multiTouch = false;
        _activePointer = null;
        _downPos = null;
        _downTime = null;
        _downShift = false;
        _longPressFired = false;
        // 长按缩放中落下第二根手指：全部抬起时同样退出。
        if (_longPressHeld) {
          _longPressHeld = false;
          widget.onLongPressRelease?.call();
        }
      }
      return;
    }
    if (_activePointer != e.pointer || _downPos == null || _downTime == null) {
      return;
    }
    final Offset downPos = _downPos!;
    final move = (e.localPosition - downPos).distance;
    final dt = DateTime.now().difference(_downTime!);
    final fired = _longPressFired;
    final held = _longPressHeld;
    _longPressHeld = false;
    _activePointer = null;
    _downPos = null;
    _downTime = null;
    _longPressFired = false;
    final bool shifted = _downShift;
    _downShift = false;
    if (fired) {
      // 长按已触发（菜单 / 长按缩放）：取消可能 pending 的单击派发，避免长按后误翻页。
      _tapTimer?.cancel();
      _lastTapAction = null;
      // 长按缩放：松手退出。
      if (held) widget.onLongPressRelease?.call();
      return;
    }
    // 缩放状态：放大态单指手势交由图片自身的平移 / 捏合处理，覆盖层不再派发翻页 / 导航。
    final bool zoomed = widget.isZoomed?.call() ?? false;
    // 拖拽（滑动）优先：移动超过 slop 视为拖拽，不触发单击导航 / 缩放。
    // 放大态下拖拽由图片平移处理，覆盖层不翻页（手势 bug #4）。
    if (move > _tapSlop) {
      _lastTapAction = null;
      if (!zoomed && !widget.isWebtoon) {
        final double dx = e.localPosition.dx - downPos.dx;
        final double dy = e.localPosition.dy - downPos.dy;
        final bool vertical = widget.isVertical;
        bool next;
        if (vertical) {
          next = dy < 0; // 上滑 = 下一页
          if (widget.tapZoneInvert == TapZoneInvert.upDown ||
              widget.tapZoneInvert == TapZoneInvert.all) {
            next = !next;
          }
        } else {
          // 标准习惯（主流漫画 App）：左到右模式向左滑→下一页；右到左模式向右滑→下一页。
          next = dx < 0;
          if (widget.isRTL) next = !next; // RTL 反转（向右滑=下一页）
          if (widget.tapZoneInvert == TapZoneInvert.leftRight ||
              widget.tapZoneInvert == TapZoneInvert.all) {
            next = !next; // 用户手动反转热区时同步反转拖拽方向
          }
        }
        widget.onDragPage?.call(next);
      }
      return;
    }
    if (dt > _tapTimeout) return;

    // 内联设置面板打开时，任意单击都用来关闭面板（吞掉导航 / 缩放）。
    if (widget.onTapIntercept?.call() ?? false) {
      _tapTimer?.cancel();
      _lastTapAction = null;
      return;
    }

    // 控制栏区域：交给控制栏自身按钮处理，不参与热区翻页，避免点按钮误触发翻页。
    if (widget.isToolbarRegion?.call(e.localPosition) ?? false) {
      _lastTapAction = null;
      return;
    }

    // 桌面 Shift+左键：在点击处缩放（兜底双击缩放），不触发导航 / 双击。
    if (shifted) {
      _lastTapAction = null;
      final at = widget.onZoomAt;
      if (at != null) {
        at(e.localPosition);
      } else {
        widget.onZoom?.call();
      }
      return;
    }

    final size = _currentSize ?? MediaQuery.sizeOf(context);

    // 双击检测优先于热区：双击【任意处】仅缩放、不翻页（验收），不要求命中
    // 热区——否则双击图片中央等热区外位置会无反应（桌面用户反馈「双击缩放没有作用」）。
    final now = DateTime.now();
    final isDouble = _lastTapTime != null &&
        now.difference(_lastTapTime!) <= _doubleTapTimeout &&
        _lastTapPos != null &&
        (_lastTapPos! - e.localPosition).distance <= _doubleTapSlop;
    if (isDouble) {
      // 双击：先撤销前一次单击已触发的翻页（单击即时 + 双击回退），再执行
      // 缩放（仅缩放、抑制本次导航， 手势 bug #5）。中心 toggle 区单击不翻页，
      // [_lastTapAction] 为 toggle 时无需回退。用点击点作锚定（#6）。
      if (_lastTapAction != null && _lastTapAction != _TapAction.toggle) {
        widget.onUndoPageTurn?.call(_lastTapAction == _TapAction.next);
      }
      _tapTimer?.cancel();
      _tapTimer = null;
      _lastTapTime = null;
      _lastTapPos = null;
      _lastTapAction = null;
      final at = widget.onZoomAt;
      if (at != null) {
        at(e.localPosition);
      } else {
        widget.onZoom?.call();
      }
      return;
    }

    final action = _actionAt(e.localPosition, size.width, size.height);
    if (action == null) {
      // 点击落在热区外：不导航，也不与后续点击构成「双击回退」。
      _lastTapAction = null;
      return;
    }

    // 内联设置面板打开时，任意单击都用来关闭面板（吞掉导航 / 缩放）。
    if (widget.onTapIntercept?.call() ?? false) {
      _tapTimer?.cancel();
      _lastTapAction = null;
      return;
    }

    // 控制栏区域：交给控制栏自身按钮处理，不参与热区翻页，避免点按钮误触发翻页。
    if (widget.isToolbarRegion?.call(e.localPosition) ?? false) {
      _lastTapAction = null;
      return;
    }

    // 桌面 Shift+左键：在点击处缩放（兜底双击缩放），不触发导航 / 双击。
    if (shifted) {
      _lastTapAction = null;
      final at = widget.onZoomAt;
      if (at != null) {
        at(e.localPosition);
      } else {
        widget.onZoom?.call();
      }
      return;
    }

    // 手势交互态（scale ≠ 1.0，既含放大 >1 也含缩小 <1）：单指单击不派发导航
    // （也不 toggle UI），避免与图片平移 / 双击缩放打架（#4 / 双击三态循环）。
    // 缩小态（<1）同样视为交互态——这是 Bug3「双击缩放三态消失」的根治：双击
    // 第一击若不拦截，会派发翻页，[onPrev]/[onNext] 的 _resetZoom 把 0.5x 缩放态
    // 清掉，导致三态循环 0.5→2 失效（永远只能缩小）。
    // 但【必须记录本次点击】时间与位置：否则交互态下第 1 击直接 return、不记录，
    // 第 2 击永远构不成双击 → 交互态双击失效。
    final bool interactive = widget.isZoomInteractive?.call() ?? zoomed;
    if (interactive) {
      _lastTapTime = now;
      _lastTapPos = e.localPosition;
      _lastTapAction = null;
      return;
    }

    // 非双击：单击【即时】派发（不再延迟 300ms），并记录本次动作供
    // 双击窗口内的「回退翻页」判定（记【反转后】的真实动作，方向判断才准确）。
    // 若随后出现第二次点击，上面 isDouble 分支会撤销本次翻页并执行缩放。
    _lastTapTime = now;
    _lastTapPos = e.localPosition;
    final _TapAction effective = _effectiveAction(action);
    // 互动阅读层：中心 / toggle 单击优先交给宿主（全局坐标）；消费则吞掉
    // toggle UI，但保留本次点击记录供双击缩放判定。
    if (effective == _TapAction.toggle) {
      final bool consumed = widget.onTapAt?.call(e.position) ?? false;
      if (consumed) {
        _lastTapAction = null;
        return;
      }
    }
    _dispatchEffective(effective);
    _lastTapAction = effective;
  }

  /// 按动作派发（[action] 须为已反转后的有效动作）。
  void _dispatchEffective(_TapAction action) {
    switch (action) {
      case _TapAction.prev:
        widget.onPrev();
      case _TapAction.next:
        widget.onNext();
      case _TapAction.toggle:
        widget.onToggleUi();
    }
  }

  /// 按 [widget.tapZoneInvert] 与 [widget.isVertical] 决定实际触发的动作。
  ///
  /// - 横向模式 + leftRight/all → 反转 prev/next
  /// - 竖向模式 + upDown/all → 反转 prev/next（上下滚动方向反转）
  /// - none → 不反转
  ///
  /// 预览也复用此方法，让彩色块与标签实时反映反转后的真实热区。
  _TapAction _effectiveAction(_TapAction action) {
    if (action == _TapAction.toggle) return action;
    final invert = widget.tapZoneInvert;
    bool shouldInvert = false;
    switch (invert) {
      case TapZoneInvert.none:
        shouldInvert = false;
      case TapZoneInvert.leftRight:
        shouldInvert = !widget.isVertical;
      case TapZoneInvert.upDown:
        shouldInvert = widget.isVertical;
      case TapZoneInvert.all:
        shouldInvert = true;
    }
    if (!shouldInvert) return action;
    return action == _TapAction.prev ? _TapAction.next : _TapAction.prev;
  }

  /// 点击区域预览：彩色块 + 标签，不响应手势。用于设置页。
  Widget _buildPreview() {
    final regions = _buildRegions();
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return Stack(
          children: <Widget>[
            for (final r in regions)
              Positioned(
                left: r.left * w,
                top: r.top * h,
                width: r.width * w,
                height: r.height * h,
                child: Container(
                  color: _previewColor(_effectiveAction(r.action))
                      .withValues(alpha: 0.22),
                  child: Center(
                    child: Text(
                      _previewLabel(_effectiveAction(r.action)),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Color _previewColor(_TapAction a) => switch (a) {
        _TapAction.prev => Colors.blue,
        _TapAction.next => Colors.green,
        _TapAction.toggle => Colors.orange,
      };

  String _previewLabel(_TapAction a) {
    final key = switch (a) {
      _TapAction.prev => 'prev',
      _TapAction.next => 'next',
      _TapAction.toggle => 'toggle',
    };
    return widget.previewLabels?[key] ?? key;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.showPreview) return _buildPreview();
    // 覆盖层铺满父级 Stack；用 translucent（而非 opaque）让它在处理单击 / 双击
    // 热区的同时，把【拖拽 / 滚动】事件透传给底层 PageView / ListView：
    // - opaque 会独占命中，导致翻页滑动、条漫滚动等手势全部失效；
    // - translucent 仍能接收指针（单击照常分发 prev/next/toggle、双击缩放），
    // 同时底层可滚动内容照常响应拖拽。
    //
    // LayoutBuilder 记录自身尺寸到 state，让热区命中使用「覆盖层几何」而非
    // 屏幕尺寸（修复 AppBar/BottomBar 占用高度时点击位置偏移、点不到的问题）。
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final size = constraints.biggest.isFinite
            ? constraints.biggest
            : MediaQuery.sizeOf(ctx);
        // 同尺寸多次 build 时不触发 setState，避免 PointerUp 期间出现 build。
        if (_currentSize != size) {
          _currentSize = size;
        }
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          onPointerSignal: widget.onPointerSignal == null
              ? null
              : (PointerSignalEvent e) {
                  if (e is PointerScrollEvent) {
                    widget.onPointerSignal!(e);
                  }
                },
          onPointerPanZoomUpdate:
              (widget.onTrackpadZoom == null &&
                      widget.onTrackpadPan == null)
                  ? null
                  : (PointerPanZoomUpdateEvent e) {
                      // 触控板捏合：scale 为累计比例（1.0=原始大小）。
                      final double s = e.scale;
                      if ((s - 1.0).abs() > 0.001 &&
                          widget.onTrackpadZoom != null) {
                        widget.onTrackpadZoom!(s, e.localPosition);
                      }
                      // 触控板双指平移：增量回调（放大态平移图片）。
                      if (e.panDelta != Offset.zero &&
                          widget.onTrackpadPan != null) {
                        widget.onTrackpadPan!(e.panDelta);
                      }
                    },
          onPointerPanZoomEnd: widget.onPinchEnd == null
              ? null
              : (_) => widget.onPinchEnd!(),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}
