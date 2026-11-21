import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../core/models/audio_lyric.dart';
import '../../../core/theme/app_tokens.dart';

/// 音频歌词视图：时间轴高亮 + 跟随播放位置自动滚动，点击行跳转。
///
/// 深色背景专用（音频页背景恒定深色），颜色不跟随主题以免低对比。
class AudioLyricsView extends StatefulWidget {
  final List<AudioLyricLine> lines;
  final Stream<Duration> positionStream;
  final Duration initialPosition;

  /// 点击歌词行回传毫秒时间戳（null 时不可点击）。
  final ValueChanged<int>? onSeekMs;

  const AudioLyricsView({
    super.key,
    required this.lines,
    required this.positionStream,
    required this.initialPosition,
    this.onSeekMs,
  });

  @override
  State<AudioLyricsView> createState() => _AudioLyricsViewState();
}

class _AudioLyricsViewState extends State<AudioLyricsView> {
  static const double _lineExtent = 72;
  static const double _listTopPadding = AppTokens.spaceSm;

  final ScrollController _scroll = ScrollController();
  StreamSubscription<Duration>? _positionSub;
  int _activeIndex = -1;

  @override
  void initState() {
    super.initState();
    _activeIndex = _indexFor(widget.initialPosition);
    _positionSub = widget.positionStream.listen(_onPosition);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollToActive(_activeIndex));
  }

  @override
  void didUpdateWidget(covariant AudioLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切集时歌词列表与初始位置会整体替换：重定位高亮并跟随新位置。
    if (!identical(oldWidget.lines, widget.lines) ||
        oldWidget.initialPosition != widget.initialPosition) {
      _activeIndex = _indexFor(widget.initialPosition);
      _scrollToActive(_activeIndex);
    }
    if (!identical(oldWidget.positionStream, widget.positionStream)) {
      _positionSub?.cancel();
      _positionSub = widget.positionStream.listen(_onPosition);
    }
  }

  int _indexFor(Duration position) {
    final int ms = position.inMilliseconds;
    int lo = 0;
    int hi = widget.lines.length - 1;
    int found = -1;
    while (lo <= hi) {
      final int mid = (lo + hi) >> 1;
      if (widget.lines[mid].timestampMs <= ms) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }

  void _onPosition(Duration position) {
    if (!mounted) return;
    final int index = _indexFor(position);
    if (index == _activeIndex) return;
    setState(() => _activeIndex = index);
    _scrollToActive(index);
  }

  void _scrollToActive(int index) {
    if (index < 0 || !_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      // 高亮行停在视口上部约 1/3 处，后续歌词可见量更大。
      final double target = (_listTopPadding +
              index * _lineExtent -
              _scroll.position.viewportDimension * 0.32)
          .clamp(0.0, _scroll.position.maxScrollExtent);
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 520),
        curve: Curves.fastOutSlowIn,
      );
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _scroll,
      itemExtent: _lineExtent,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceLg,
        vertical: _listTopPadding,
      ),
      itemCount: widget.lines.length,
      itemBuilder: (BuildContext context, int index) {
        final bool active = index == _activeIndex;
        // 空间感：越靠近视口垂直中线越大，向上下两端递减；高亮行略加成，
        // 保证停在视口上部 1/3 时仍是最大的一行。
        return AnimatedBuilder(
          animation: _scroll,
          builder: (BuildContext context, Widget? child) => Transform.scale(
            scale: (_scaleFor(index) + (active ? 0.06 : 0)).clamp(0.0, 1.06),
            child: child,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceXs),
            child: InkWell(
              key: ValueKey<int>(index),
              borderRadius: BorderRadius.circular(AppTokens.radiusLg),
              onTap: widget.onSeekMs == null
                  ? null
                  : () => widget.onSeekMs!(widget.lines[index].timestampMs),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceMd,
                  vertical: 7,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.lines[index].text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 19,
                      height: 1.3,
                      color: active ? Colors.white : Colors.white54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 行中心距视口垂直中线的远近 → 缩放比例（中线 1.0，两端约 0.8）。
  double _scaleFor(int index) {
    if (!_scroll.hasClients) return 1;
    final double viewport = _scroll.position.viewportDimension;
    if (viewport <= 0) return 1;
    final double itemCenter = _listTopPadding +
        index * _lineExtent +
        _lineExtent / 2 -
        _scroll.offset;
    final double distance =
        ((itemCenter - viewport / 2).abs() / (viewport / 2)).clamp(0.0, 1.0);
    return 1 - 0.2 * distance;
  }
}
