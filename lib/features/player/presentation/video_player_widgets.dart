part of 'video_player_screen.dart';

class _DanmakuToggle extends StatelessWidget {
  const _DanmakuToggle({
    super.key,
    required this.isOn,
    required this.l10n,
    required this.onToggle,
    this.onSend,
    this.onSettings,
    this.onLongPressSettings,
  });

  final bool isOn;
  final AppLocalizations l10n;
  final VoidCallback onToggle;
  final VoidCallback? onSend;
  final VoidCallback? onSettings;
  final VoidCallback? onLongPressSettings;

  /// 弹幕区紧凑图标按钮：无背景框，触控区 40×40。
  /// compact 密度会把约束下界减 8，故传 48 保证实际 40。
  Widget _miniBtn({
    required IconData icon,
    required Color color,
    required String tooltip,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) =>
      IconButton(
        icon: Icon(icon, color: color, size: 24),
        tooltip: tooltip,
        onPressed: onTap,
        onLongPress: onLongPress,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        padding: EdgeInsets.zero,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 无边框药丸：开启态实心主色图标 + 发送 + 设置；关闭态仅空心开关。
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _miniBtn(
          icon: isOn ? Icons.comment_rounded : Icons.comment_rounded,
          color: isOn ? theme.colorScheme.primary : Colors.white54,
          tooltip: l10n.danmaku,
          onTap: onToggle,
        ),
        if (isOn && onSend != null)
          _miniBtn(
            icon: Icons.send_rounded,
            color: Colors.white70,
            tooltip: l10n.danmakuSend ?? 'Send danmaku',
            onTap: onSend,
          ),
        if (isOn && onSettings != null)
          _miniBtn(
            icon: Icons.tune_rounded,
            color: Colors.white70,
            tooltip: l10n.danmakuSettings,
            onTap: onSettings,
            onLongPress: onLongPressSettings,
          ),
      ],
    );
  }
}

/// 中央播放/暂停按钮：暂停态常显，播放/暂停切换带图标形变动效。
///
/// 由 [isPlaying] / [uiVisible] 驱动的状态机（不再由父级条件挂载）：
/// - **暂停且控制层可见**：完整展示——毛玻璃圆盘 + 细白描边 + 双层错相位
/// 呼吸光环（两圈白环循环扩散淡出）+ 播放三角（光学居中微移），可点击；
/// - **暂停 → 播放**（任何触发路径）：图标即刻形变为暂停符号 ‖，先弹跳
/// 放大再整体淡出缩没——让「状态切换」肉眼可见；
/// - **播放 → 暂停**：elasticOut 弹性入场 + 光环重启；
/// - 控制层隐藏或播放中：完全移出渲染树（SizedBox.shrink），不挡手势。
///
/// 按下时缩至 0.88 并给轻微触感反馈。

class _CenterPlayButton extends StatefulWidget {
  const _CenterPlayButton({
    super.key,
    required this.isPlaying,
    required this.uiVisible,
    required this.onToggle,
  });

  /// 当前播放状态：true = 播放中（按钮处于退出过渡或隐藏）。
  final bool isPlaying;

  /// 控制层是否可见：暂停时若控制层隐藏，按钮同样隐藏。
  final bool uiVisible;

  /// 完整展示（暂停态）时的点击回调（恢复播放）。
  final VoidCallback onToggle;

  @override
  State<_CenterPlayButton> createState() => _CenterPlayButtonState();
}

class _CenterPlayButtonState extends State<_CenterPlayButton>
    with TickerProviderStateMixin {
  late final AnimationController _entrance;
  late final AnimationController _halo;
  late final AnimationController _exit;
  bool _shown = false;
  double _pressScale = 1.0;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    // 呼吸光环：周期循环，扩散 + 淡出，两环相位差半个周期。
    _halo = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _exit = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..addStatusListener((AnimationStatus status) {
        // 退出动画结束后触发一次重建：build 依据 _shown=false 返回
        // SizedBox.shrink，把按钮彻底移出渲染树。没有这次 setState 时，
        // AnimatedBuilder 的完成帧会把 opacity 从 0 回跳到 1（结尾闪现）。
        if (status == AnimationStatus.completed && !_shown && mounted) {
          setState(() {});
        }
      });
    if (!widget.isPlaying && widget.uiVisible) {
      _show();
    }
  }

  @override
  void didUpdateWidget(covariant _CenterPlayButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying == oldWidget.isPlaying &&
        widget.uiVisible == oldWidget.uiVisible) {
      return;
    }
    if (widget.isPlaying) {
      // 暂停 → 播放：暂停图标弹出 + 淡出（build 期间图标随 isPlaying 切换）。
      if (_shown) _dismiss();
    } else if (widget.uiVisible) {
      // 播放 → 暂停（或控制层重新可见）：弹性登场。
      _show();
    } else if (_shown) {
      // 暂停但控制层被隐藏：静默淡出（图标保持播放态不变）。
      _dismiss();
    }
  }

  void _show() {
    _shown = true;
    // reset（而非 stop）：stop 不清零，残留的 _exit.value 会让 settle/pop
    // 缩放系数失真——上一轮退出动画播完后（value=1）再显示会永久卡在
    // 75% 大小，表现为不同路径弹出的按钮尺寸不一致。
    _exit.reset();
    _pressScale = 1.0;
    _entrance.forward(from: 0);
    _halo.repeat();
  }

  void _dismiss() {
    _shown = false;
    _pressScale = 1.0;
    _halo.stop();
    _exit.forward(from: 0);
  }

  @override
  void dispose() {
    _entrance.dispose();
    _halo.dispose();
    _exit.dispose();
    super.dispose();
  }

  /// 单圈光环在进度 [t] (0..1) 时的形态：easeOut 放大 1→1.45，透明度 0.4→0。
  Widget _haloRing(double t) {
    final double scale = 1.0 + 0.45 * Curves.easeOut.transform(t);
    final double opacity = 0.4 * (1.0 - t);
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: opacity),
            width: 1.5,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 隐藏（播放中 / 控制层隐藏）且无过渡动画在进行：完全移出渲染树，
    // 不占命中区域，点击穿透到底层视频手势。
    final bool transitioning = _exit.isAnimating || _entrance.isAnimating;
    if (!_shown && !transitioning) return const SizedBox.shrink();

    return IgnorePointer(
      // 隐藏 / 退出过渡期间不响应点击（连点穿透给视频手势层）。
      ignoring: !_shown,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressScale = 0.88),
        onTapUp: (_) => setState(() => _pressScale = 1.0),
        onTapCancel: () => setState(() => _pressScale = 1.0),
        onTap: () {
          AppHaptics.light();
          widget.onToggle();
        },
        // 外框比按钮大一圈，给扩散光环留出绘制空间（不裁剪）。
        child: SizedBox(
          width: 96,
          height: 96,
          child: AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[_entrance, _halo, _exit]),
            builder: (BuildContext context, Widget? child) {
              final double elastic =
                  Curves.elasticOut.transform(_entrance.value);
              // 退出过渡（仅进行中生效，杜绝残留值失真）：先弹跳放大
              // （sin 半周期），同时后半段淡出并回缩。
              final double e = _exit.value;
              final double animating = _exit.isAnimating ? 1.0 : 0.0;
              final double pop = 1.0 + 0.12 * math.sin(math.pi * e) * animating;
              final double settle =
                  1.0 - 0.25 * Curves.easeIn.transform(e) * animating;
              // 退出动画结束的那一帧 isAnimating 已为 false，若直接给 1.0 会
              // 在被移出树前闪现一下——未展示状态强制透明兜底。
              final double fade =
                  1.0 - Curves.easeIn.transform(Interval(0.3, 1).transform(e));
              final double opacity =
                  _exit.isAnimating ? fade : (_shown ? 1.0 : 0.0);
              return Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: elastic * pop * settle * _pressScale,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      _haloRing(_halo.value),
                      _haloRing((_halo.value + 0.5) % 1.0),
                      child!,
                    ],
                  ),
                ),
              );
            },
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.18),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.35),
                  width: 1.5,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipOval(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  // 播放三角右侧天然留白，向右微移实现光学居中；暂停符号对称。
                  child: Center(
                    child: widget.isPlaying
                        ? const Icon(
                            Icons.pause_rounded,
                            color: Colors.white,
                            size: 30,
                          )
                        : const Padding(
                            padding: EdgeInsets.only(left: 1.5),
                            child: Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 控制按钮（透明背景圆形，紧凑尺寸）。

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.onLongPress,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: Colors.white, size: 24),
      tooltip: tooltip,
      onPressed: onTap,
      onLongPress: onLongPress,
      // 统一 40×40 触控区 + 24 图标：底栏左右两侧按钮尺寸一致，视觉对齐
      // 弹幕区图标；compact 密度会把约束下界减 8，实际尺寸由图标+内边距撑到 40。
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      padding: const EdgeInsets.all(8),
    );
  }
}

/// 逐帧步进按钮（上一帧 / 下一帧）：半透明圆底小圆钮，悬浮于中央大播放键两侧。
///
/// 仅暂停态且控制层可见时显示。隐藏时渲染 SizedBox.shrink 而不是从 Row 中
/// 移除——固定三槽位保证中央播放键的 State 不因子树重排被重建（其暂停→播放
/// 形变动画依赖跨状态保持挂载）。左右对称水平内边距维持中央按钮居中。
class _FrameStepButton extends StatelessWidget {
  const _FrameStepButton({
    super.key,
    required this.visible,
    required this.backward,
    required this.tooltip,
    required this.onTap,
  });

  final bool visible;
  final bool backward;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.black45,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              AppHaptics.light();
              onTap();
            },
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                backward
                    ? Icons.navigate_before_rounded
                    : Icons.navigate_next_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 横向滚动文字（Marquee）：当文本超出可用宽度时自动循环滚动；
/// 文本能完整显示时静止不动（无动画开销）。
///
/// 跳过片头/片尾悬浮按钮：半透明胶囊，浮在画面右下角。

class _SkipChip extends StatelessWidget {
  const _SkipChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.inverseSurface.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 18, color: scheme.onInverseSurface),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: scheme.onInverseSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 用 [SingleChildScrollView] 承载文本，由 [AnimationController] 驱动
/// [_scrollController] 手动滚动；避免 ListView.builder(itemCount:null) 在
/// 顶栏 Row 内触发无限高度布局崩溃。

class _MarqueeText extends StatefulWidget {
  const _MarqueeText({
    required this.text,
    required this.style,
  });

  final String text;
  final TextStyle style;

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  // 必须在 initState（context 仍有效）创建，禁止用 late final 懒初始化——
  // 若文本从未滚动、dispose 时首次访问该字段会现场 createTicker 并读取已失活的
  // TickerMode 祖先，抛「Looking up a deactivated widget's ancestor is unsafe」。
  late AnimationController _animController;

  /// 文本是否需要滚动（测量后确定）。
  bool _scrollable = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..addListener(_onAnimTick);
    // 延迟一帧测量文本宽度，决定是否需要滚动。
    WidgetsBinding.instance.addPostFrameCallback(_measure);
  }

  void _measure(_) {
    final renderer = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    // 容器可用宽度估算（减去返回键 + 右侧图标的大致占用）。
    final maxWidth = MediaQuery.of(context).size.width - 160;
    if (mounted && renderer.width > maxWidth) {
      // 标记需要滚动并启动动画（setState 异步，故动画启动不依赖刚刚写入的 _scrollable）。
      if (mounted) setState(() => _scrollable = true);
      if (!_animController.isAnimating) {
        _animController.repeat();
      }
    }
    // TextPainter 用完即释放：仅测量用，不常驻，避免小规模资源泄漏。
    renderer.dispose();
  }

  void _onAnimTick() {
    if (!_scrollable || !_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return;
    // 滚到末尾（留 40px 间隙）后回环到起点，形成循环滚动。
    final span = max + 40;
    final v = (_animController.value * span) % span;
    _scrollController.jumpTo(v);
  }

  @override
  void didUpdateWidget(covariant _MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _scrollable = false;
      _animController.stop();
      WidgetsBinding.instance.addPostFrameCallback(_measure);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      controller: _scrollController,
      physics: const NeverScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceSm),
        child: Text(widget.text, style: widget.style),
      ),
    );
  }
}
