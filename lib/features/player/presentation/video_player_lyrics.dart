part of 'video_player_screen.dart';

/// 内嵌歌词（音频源 LRC）：时间轴高亮 + 跟随播放位置自动滚动。
extension _VideoLyrics on _VideoPlayerScreenState {
  void _showLyricsSheet(AppLocalizations l10n) {
    final List<AudioLyricLine> lines = _lyricLines;
    if (lines.isEmpty) return;
    _acquirePanelHold();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) => _LyricsSheet(
        title: l10n.playerLyric,
        lines: lines,
        positionStream: _controller.positionStream,
        initialPosition: _position,
      ),
    ).whenComplete(_releasePanelHold);
  }
}

class _LyricsSheet extends StatefulWidget {
  final String title;
  final List<AudioLyricLine> lines;
  final Stream<Duration> positionStream;
  final Duration initialPosition;

  const _LyricsSheet({
    required this.title,
    required this.lines,
    required this.positionStream,
    required this.initialPosition,
  });

  @override
  State<_LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<_LyricsSheet> {
  static const double _lineExtent = 48;

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
      final double target = (index * _lineExtent -
              (_scroll.position.viewportDimension - _lineExtent) / 2)
          .clamp(0.0, _scroll.position.maxScrollExtent);
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
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
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spaceLg,
                AppTokens.spaceMd,
                AppTokens.spaceSm,
                AppTokens.spaceSm,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                controller: _scroll,
                itemExtent: _lineExtent,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceLg,
                  vertical: AppTokens.spaceSm,
                ),
                itemCount: widget.lines.length,
                itemBuilder: (BuildContext context, int index) {
                  final bool active = index == _activeIndex;
                  return Center(
                    child: Text(
                      widget.lines[index].text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: active
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                        fontWeight: active ? FontWeight.w600 : null,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
