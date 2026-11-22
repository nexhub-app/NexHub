part of 'video_player_screen.dart';

/// 视频手势坐标轴状态机：避免横滑（seek）与竖滑（亮度 / 音量）冲突。
///
/// 一旦 [onVerticalDragStart] / [onHorizontalDragStart] 判定方向，即锁定该轴
/// 直到对应 `onEnd` 重置回 [none]，update 期间不切换轴。
enum _GestureAxis { none, horizontal, verticalLeft, verticalRight }

extension _VideoGestures on _VideoPlayerScreenState {
  /// 相对当前播放位置 seek 指定偏移（负值快退，正值快进），自动 clamp 到 [0, _duration]。
  Future<void> _seekBy(Duration offset) async {
    if (_duration == Duration.zero) return;
    final target = _position + offset;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > _duration ? _duration : target);
    await _onSeek(clamped);
  }

  /// 设置系统亮度（0..1）并刷新手势指示器。
  Future<void> _setBrightness(double v) async {
    final clamped = v.clamp(0.0, 1.0);
    final l10n = AppLocalizations.of(context);
    _brightness = clamped;
    try {
      await _brightnessPlugin.setApplicationScreenBrightness(clamped);
    } on Object {
      // 平台不支持时静默忽略。
    }
    _showGestureIndicator('${l10n.playerBrightness}: ${(clamped * 100).round()}%');
  }

  /// 设置播放器音量（0..100，经 PlayerController 透传）并刷新手势指示器。
  Future<void> _setVolume(double v) async {
    final l10n = AppLocalizations.of(context);
    await _controller.setVolume(v);
    _showGestureIndicator(
        '${l10n.playerVolume}: ${_controller.volume.round()}%');
  }

  /// 显示手势指示器约 800ms 后自动淡出。
  ///
  /// 多次连续触发会重置计时器，指示器保持显示直到最后一次触发后 800ms。
  void _showGestureIndicator(String text) {
    _gestureIndicatorTimer?.cancel();
    setState(() {
      _gestureIndicatorText = text;
      _gestureIndicatorVisible = true;
    });
    // 取消态（横滑上滑取消 seek）需常显直到松手，不被 800ms 计时隐藏，
    // 否则手指停住后「已取消快进」图标消失，用户误以为取消未生效。
    if (_seekDragCancelled) return;
    _gestureIndicatorTimer = Timer(const Duration(milliseconds: 800), () {
      if (_seekDragCancelled) return;
      if (mounted) {
        setState(() => _gestureIndicatorVisible = false);
      }
    });
  }

  /// 中央手势指示器浮层：显示双击 ±10s / 亮度 % / 音量 % / 横滑 seek 目标时间。
  ///
  /// 横滑 seek 上滑取消时（[_seekDragCancelled]）渲染红色背景 + 取消图标，
  /// 让「取消」状态一目了然（反馈增强）。
  Widget _buildGestureIndicator() {
    final bool cancelled = _seekDragCancelled;
    return IgnorePointer(
      child: Center(
        child: AnimatedOpacity(
          opacity: _gestureIndicatorVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceMd,
              vertical: AppTokens.spaceSm,
            ),
            decoration: BoxDecoration(
              color: cancelled
                  ? Colors.red.withValues(alpha: 0.78)
                  : Colors.black54,
              borderRadius: BorderRadius.circular(AppTokens.spaceSm),
            ),
            child: cancelled
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.cancel_rounded, color: Colors.white, size: 28),
                      const SizedBox(height: 4),
                      Text(
                        _gestureIndicatorText ?? '',
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ],
                  )
                : Text(
                    _gestureIndicatorText ?? '',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────── 截图（边缘按钮 + 菜单共用） ───────────────────────

  /// 抽出 [_takeScreenshot] 的核心实现，供边缘常驻按钮与「更多」菜单共用。
  ///
  /// 使用 media_kit 的 [Player.screenshot] 截取当前帧，
  /// 保存为 PNG 到截图目录（默认 Documents/screenshots 或用户自定义）。

  /// 处理键盘事件：空格=播放/暂停，左右=seek ±10s，逗号/句号=逐帧步进，
  /// F=全屏，M=静音。返回 `KeyEventResult.handled` 表示已处理，否则 `ignored`。
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // 仅响应 key down（避免重复触发），且锁定时不响应（除解锁外）。
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      if (_controller.isLocked) return KeyEventResult.handled;
      // 用户手动重播则取消进行中的连播倒计时。
      _cancelAutoNextCountdown();
      if (_isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
      }
      setState(() {
        _isPlaying = !_isPlaying;
        // 暂停时控制层常显，播放时重启自动隐藏倒计时。
        if (!_isPlaying) _uiVisible = true;
      });
      if (_isPlaying) {
        _scheduleUiHide();
      } else {
        _uiHideTimer?.cancel();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_controller.isLocked) return KeyEventResult.handled;
      // 直播流（duration 恒 0）不支持 seek：左移会跳到缓冲区边缘之外卡死。
      if (_duration == Duration.zero) return KeyEventResult.handled;
      final target = (_position - const Duration(seconds: 10));
      final clamped = target < Duration.zero ? Duration.zero : target;
      unawaited(_onSeek(clamped));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (_controller.isLocked) return KeyEventResult.handled;
      // 直播流不支持 seek：duration 为 0 时旧逻辑会把目标 clamp 到 0
      // （seek 到头打死播放）。
      if (_duration == Duration.zero) return KeyEventResult.handled;
      final target = (_position + const Duration(seconds: 10));
      final clamped = target > _duration ? _duration : target;
      unawaited(_onSeek(clamped));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.comma) {
      if (_controller.isLocked) return KeyEventResult.handled;
      // 逐帧后退：mpv 命令自带「先暂停再步进」，播放中按下即转暂停态。
      unawaited(_controller.frameStep(backward: true));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.period) {
      if (_controller.isLocked) return KeyEventResult.handled;
      unawaited(_controller.frameStep(backward: false));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      // 全屏切换即使在锁定状态也允许（与播放器 UI 解耦）。
      unawaited(_controller.toggleFullscreen());
      setState(() {});
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM) {
      if (_controller.isLocked) return KeyEventResult.handled;
      unawaited(_controller.toggleMute());
      setState(() {});
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}
