import 'package:material_ui/material_ui.dart';

import '../../theme/app_tokens.dart';
import '../../utils/app_haptics.dart';

/// 视频播放器进度条。
///
/// 基于 [Slider] + [SliderTheme] 实现，拖动时在上方显示时间气泡。
/// 已播放部分以主色高亮，未播放部分以淡色轨道表示。
class SeekBar extends StatefulWidget {
  const SeekBar({
    super.key,
    required this.position,
    required this.duration,
    this.onSeek,
    this.onDragStart,
    this.onDragEnd,
  });

  /// 当前播放位置。
  final Duration position;

  /// 媒体总时长。
  final Duration duration;

  /// 拖动结束时的回调。
  final ValueChanged<Duration>? onSeek;

  /// 开始拖动进度条（控制栏租约，拖动期间禁止自动隐藏）。
  final VoidCallback? onDragStart;

  /// 结束拖动进度条（释放租约后重启自动隐藏倒计时）。
  final VoidCallback? onDragEnd;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  bool _dragging = false;
  double _dragValue = 0;

  double get _maxValue {
    final ms = widget.duration.inMilliseconds;
    return ms > 0 ? ms.toDouble() : 1;
  }

  double get _currentValue {
    if (_dragging) return _dragValue;
    return widget.position.inMilliseconds.toDouble().clamp(0, _maxValue);
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) return '$h:$mm:$ss';
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dragDuration = Duration(milliseconds: _dragValue.round());

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                // 指定 padding 后轨道铺满控件宽度（默认左右各让出 24dp
                // overlay 半径，窄屏上显得两端很空）；6dp 恰好容下拇指。
                padding: const EdgeInsets.symmetric(horizontal: 6),
                activeTrackColor: scheme.primary,
                inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.2),
                thumbColor: scheme.primary,
                overlayColor: scheme.primary.withValues(alpha: 0.12),
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
                trackShape: _FullTrackShape(),
              ),
              child: Slider(
                value: _currentValue,
                min: 0,
                max: _maxValue,
                onChangeStart: (double v) {
                  AppHaptics.light();
                  widget.onDragStart?.call();
                  setState(() {
                    _dragging = true;
                    _dragValue = v;
                  });
                },
                onChanged: (double v) {
                  setState(() => _dragValue = v);
                },
                onChangeEnd: (double v) {
                  setState(() => _dragging = false);
                  widget.onDragEnd?.call();
                  widget.onSeek?.call(Duration(milliseconds: v.round()));
                },
              ),
            ),
            if (_dragging)
              Positioned(
                left: _thumbLeft(
                  constraints.maxWidth,
                  _dragValue / _maxValue,
                ),
                top: -AppTokens.space2xl,
                child: _TimeBubble(
                  text: _formatDuration(dragDuration),
                  color: scheme.primary,
                ),
              ),
          ],
        );
      },
    );
  }

  /// 根据拖动比例计算气泡左侧偏移，保证不溢出轨道边界。
  double _thumbLeft(double trackWidth, double fraction) {
    const double thumbRadius = 6;
    const double bubbleHalf = 24;
    final x = trackWidth * fraction;
    return (x - bubbleHalf).clamp(thumbRadius, trackWidth - bubbleHalf * 2);
  }
}

/// 拖动时显示的时间气泡。
class _TimeBubble extends StatelessWidget {
  const _TimeBubble({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceSm,
        vertical: AppTokens.spaceXs,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// 自定义轨道形状：让活动轨道仅在已播放部分着色（而非默认从中间分界）。
class _FullTrackShape extends RoundedRectSliderTrackShape {
  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );
  }
}
