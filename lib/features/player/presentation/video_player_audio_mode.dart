part of 'video_player_screen.dart';

/// 封面色缓存：同一封面 URL 只取色一次（`ColorScheme.fromImageProvider`
/// 走 Material 的图片取色量化，结果随图片缓存复用）。
final Map<String, Future<ColorScheme?>> _audioCoverPaletteCache =
    <String, Future<ColorScheme?>>{};

Future<ColorScheme?> _loadAudioCoverPalette(String url) async {
  try {
    return await ColorScheme.fromImageProvider(
      provider: NetworkImage(url),
      brightness: Brightness.dark,
    );
  } catch (_) {
    return null;
  }
}

Future<ColorScheme?> _audioCoverPalette(String url) {
  if (url.isEmpty) return Future<ColorScheme?>.value(null);
  final Future<ColorScheme?>? cached = _audioCoverPaletteCache[url];
  if (cached != null) return cached;
  if (_audioCoverPaletteCache.length >= 16) {
    _audioCoverPaletteCache.clear();
  }
  final Future<ColorScheme?> future = _loadAudioCoverPalette(url);
  _audioCoverPaletteCache[url] = future;
  return future;
}

/// 音频模式界面：封面 / 歌词 / 播放列表三页横向切换。
///
/// 仅做呈现层分流：播放内核、后台音频服务、队列、进度记忆与歌词解析
/// 全部复用现有管线；视频专属控件（锁定/截图/画面比例/弹幕/字幕/PiP 等）
/// 由各处 `_audioMode` 门控隐藏。
extension _VideoAudioMode on _VideoPlayerScreenState {
  bool get _audioMode => widget.isAudio;

  Widget _buildAudioSurface() {
    final Episode ep = widget.episodes != null && widget.episodes!.isNotEmpty
        ? widget.episodes![_episodeIndex.clamp(0, widget.episodes!.length - 1)]
        : widget.episode;
    return _AudioSurface(
      key: _audioSurfaceKey,
      coverUrl: widget.coverUrl,
      album: widget.title,
      episodeTitle: ep.title,
      episodes: widget.episodes ?? const <Episode>[],
      currentIndex: _episodeIndex,
      playing: _isPlaying,
      lyrics: _lyricLines,
      positionStream: _controller.positionStream,
      initialPosition: _position,
      backgroundMode: _playerSettings.audioBackgroundMode,
      backgroundColor: Color(_playerSettings.audioBackgroundColor),
      onSelectEpisode: (int index) => unawaited(_changeEpisode(index)),
      onSeek: (Duration position) => unawaited(_controller.seek(position)),
    );
  }

  /// 音频模式底部控制栏：刻度进度条 + 两端时间 + 传输键 + 工具行。
  ///
  /// 与视频底栏分离：音频没有自动隐藏、没有中央播放钮，进度直接拖动提交，
  /// 避免音频页出现视频式 seek 预览与加载转圈。
  Widget _buildAudioBottomBar(AppLocalizations l10n) {
    final bool hasPrev = widget.episodes != null && _episodeIndex > 0;
    final bool hasNext =
        widget.episodes != null && _episodeIndex < widget.episodes!.length - 1;
    final bool hasEpisodes = (widget.episodes?.length ?? 0) > 1;
    const TextStyle timeStyle = TextStyle(color: Colors.white54, fontSize: 11);

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: <Color>[Colors.black54, Colors.transparent],
          ),
        ),
        padding: EdgeInsets.only(
          left: AppTokens.spaceXl,
          right: AppTokens.spaceXl,
          top: AppTokens.spaceSm,
          bottom: MediaQuery.of(context).padding.bottom + AppTokens.spaceSm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _AudioProgressSlider(
              position: _position,
              duration: _duration,
              onSeek: _onSeek,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(_formatDuration(_position), style: timeStyle),
                Text(_formatDuration(_duration), style: timeStyle),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.spaceLg, bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  _AudioTransportButton(
                    key: const Key('player_prev_ep'),
                    icon: Icons.skip_previous_rounded,
                    tooltip: l10n.playerPreviousEpisode,
                    onTap: hasPrev ? _goPrevEpisode : null,
                  ),
                  _AudioPlayButton(
                    key: const Key('player_audio_play_pause'),
                    playing: _isPlaying,
                    tooltip: _isPlaying ? l10n.pause : l10n.play,
                    onTap: () {
                      _cancelAutoNextCountdown();
                      _togglePlayPause();
                    },
                  ),
                  _AudioTransportButton(
                    key: const Key('player_next_ep'),
                    icon: Icons.skip_next_rounded,
                    tooltip: l10n.playerNextEpisode,
                    onTap: hasNext ? _goNextEpisode : null,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceLg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  _AudioUtilityButton(
                    key: const Key('player_quick_speed'),
                    icon: Icons.speed_rounded,
                    label: '${_controller.playbackSpeed}x',
                    tooltip: l10n.playerPlaybackSpeed,
                    onTap: () => _showSpeedPicker(l10n),
                  ),
                  if (_lyricLines.isNotEmpty)
                    _AudioUtilityButton(
                      key: const Key('player_audio_lyrics'),
                      icon: Icons.lyrics_rounded,
                      label: l10n.playerLyric,
                      tooltip: l10n.playerLyric,
                      onTap: () =>
                          _audioSurfaceKey.currentState?.showLyricsPage(),
                    ),
                  if (hasEpisodes)
                    _AudioUtilityButton(
                      key: const Key('player_quick_episodes'),
                      icon: Icons.queue_music_rounded,
                      label: l10n.playerEpisodes,
                      tooltip: l10n.playerEpisodes,
                      onTap: () =>
                          _audioSurfaceKey.currentState?.showEpisodesPage(),
                    ),
                  _AudioUtilityButton(
                    key: const Key('player_sleep_timer'),
                    icon: Icons.timer_outlined,
                    label: l10n.playerTimer,
                    tooltip: l10n.playerTimer,
                    onTap: () => _showSleepTimerPicker(l10n),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioSurface extends StatefulWidget {
  final String? coverUrl;
  final String album;
  final String episodeTitle;
  final List<Episode> episodes;
  final int currentIndex;
  final bool playing;
  final List<AudioLyricLine> lyrics;
  final Stream<Duration> positionStream;
  final Duration initialPosition;
  final AudioBackgroundMode backgroundMode;
  final Color backgroundColor;
  final ValueChanged<int> onSelectEpisode;
  final ValueChanged<Duration> onSeek;

  const _AudioSurface({
    super.key,
    required this.coverUrl,
    required this.album,
    required this.episodeTitle,
    required this.episodes,
    required this.currentIndex,
    required this.playing,
    required this.lyrics,
    required this.positionStream,
    required this.initialPosition,
    required this.backgroundMode,
    required this.backgroundColor,
    required this.onSelectEpisode,
    required this.onSeek,
  });

  @override
  State<_AudioSurface> createState() => _AudioSurfaceState();
}

class _AudioSurfaceState extends State<_AudioSurface> {
  late final PageController _pager = PageController(initialPage: 1);
  int _page = 1;
  ColorScheme? _palette;
  String _paletteUrl = '';

  bool get _hasLyrics => widget.lyrics.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _refreshPalette();
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _AudioSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverUrl != widget.coverUrl ||
        oldWidget.backgroundMode != widget.backgroundMode) {
      _refreshPalette();
    }
    if (!_hasLyrics && _page == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pager.hasClients) _pager.jumpToPage(1);
      });
    }
  }

  void _refreshPalette() {
    final String url = widget.coverUrl?.trim() ?? '';
    _paletteUrl = url;
    _palette = null;
    if (url.isEmpty || widget.backgroundMode != AudioBackgroundMode.cover) {
      return;
    }
    unawaited(_audioCoverPalette(url).then((ColorScheme? scheme) {
      if (!mounted || _paletteUrl != url || scheme == null) return;
      setState(() => _palette = scheme);
    }));
  }

  /// 底部歌词按钮快捷跳转（左滑同效果）。
  void showLyricsPage() {
    if (!_hasLyrics || !_pager.hasClients) return;
    _pager.animateToPage(
      2,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  /// 底部选集按钮快捷跳转（右滑同效果）。
  void showEpisodesPage() {
    if (!_pager.hasClients) return;
    _pager.animateToPage(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  /// 页面上/下留白：顶部让出返回栏，底部让出控制栏（约 216dp）。
  EdgeInsets _pagePadding(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    return EdgeInsets.only(
      top: media.padding.top + 72,
      bottom: media.padding.bottom + 216,
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = <Widget>[
      _buildEpisodePage(context),
      _buildCoverPage(context),
      if (_hasLyrics) _buildLyricsPage(context),
    ];
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        _buildBackground(context),
        PageView(
          controller: _pager,
          onPageChanged: (int page) => setState(() => _page = page),
          children: pages,
        ),
      ],
    );
  }

  Widget _buildBackground(BuildContext context) {
    if (widget.backgroundMode == AudioBackgroundMode.solid) {
      return ColoredBox(color: widget.backgroundColor);
    }
    final ColorScheme tones = widget.backgroundMode == AudioBackgroundMode.cover
        ? (_palette ?? Theme.of(context).colorScheme)
        : Theme.of(context).colorScheme;
    const Color base = Color(0xFF0B0B10);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color.alphaBlend(tones.primary.withValues(alpha: 0.55), base),
            Color.alphaBlend(
              tones.primaryContainer.withValues(alpha: 0.38),
              const Color(0xFF111116),
            ),
            const Color(0xFF07070B),
          ],
          stops: const <double>[0.0, 0.55, 1.0],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }

  Widget _buildCoverPage(BuildContext context) {
    final EdgeInsets padding = _pagePadding(context);
    final String album = widget.album.trim().isEmpty
        ? widget.episodeTitle.trim()
        : widget.album.trim();
    final String chapter = widget.episodeTitle.trim();
    final bool showChapter = chapter.isNotEmpty && chapter != album;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double availableWidth = math.max(0, constraints.maxWidth - 48);
        final double availableHeight =
            math.max(0, constraints.maxHeight - padding.vertical);
        // 边长取可用宽度与 0.55×可用高度中的较小值：封面尽量大，
        // 同时给下方书名/章节名留出空间。
        final double coverSize =
            math.min(availableWidth, availableHeight * 0.55).clamp(96.0, 480.0);
        return Padding(
          padding: padding.copyWith(
            left: AppTokens.spaceXl,
            right: AppTokens.spaceXl,
          ),
          child: Column(
            children: <Widget>[
              AudioCoverArt(coverUrl: widget.coverUrl, size: coverSize),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        album,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                      if (showChapter) ...<Widget>[
                        const SizedBox(height: AppTokens.spaceXs),
                        Text(
                          chapter,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLyricsPage(BuildContext context) {
    final EdgeInsets padding = _pagePadding(context);
    return Padding(
      padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
      child: AudioLyricsView(
        key: const Key('player_audio_lyrics_page'),
        lines: widget.lyrics,
        positionStream: widget.positionStream,
        initialPosition: widget.initialPosition,
        onSeekMs: (int ms) => widget.onSeek(Duration(milliseconds: ms)),
      ),
    );
  }

  Widget _buildEpisodePage(BuildContext context) {
    return _AudioEpisodeList(
      key: const Key('player_audio_episode_list'),
      episodes: widget.episodes,
      fallbackTitle: widget.episodeTitle,
      currentIndex: widget.currentIndex,
      playing: widget.playing,
      padding: _pagePadding(context),
      onSelect: widget.onSelectEpisode,
    );
  }
}

/// 音频进度条：刻度轨道 + 拖动放大轨道、松手提交（不显示拖拽预览气泡）。
class _AudioProgressSlider extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  const _AudioProgressSlider({
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  @override
  State<_AudioProgressSlider> createState() => _AudioProgressSliderState();
}

class _AudioProgressSliderState extends State<_AudioProgressSlider> {
  bool _dragging = false;
  double _fraction = 0;
  double _width = 1;

  double get _positionFraction {
    final int total = widget.duration.inMilliseconds;
    if (total <= 0) return 0;
    return (widget.position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  @override
  void initState() {
    super.initState();
    _fraction = _positionFraction;
  }

  @override
  void didUpdateWidget(covariant _AudioProgressSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 拖动期间不让播放进度覆盖预览位置。
    if (!_dragging) _fraction = _positionFraction;
  }

  void _updatePreview(double dx) {
    setState(() => _fraction = (dx / _width).clamp(0.0, 1.0));
  }

  void _commit() {
    setState(() => _dragging = false);
    if (widget.duration <= Duration.zero) return;
    widget.onSeek(
      Duration(
        milliseconds:
            (_fraction * widget.duration.inMilliseconds).round().clamp(
                  0,
                  widget.duration.inMilliseconds,
                ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _width = math.max(1, constraints.maxWidth);
        final double fraction = _dragging ? _fraction : _positionFraction;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (DragStartDetails d) {
            setState(() {
              _dragging = true;
              _fraction = (d.localPosition.dx / _width).clamp(0.0, 1.0);
            });
          },
          onHorizontalDragUpdate: (DragUpdateDetails d) =>
              _updatePreview(d.localPosition.dx),
          onHorizontalDragEnd: (_) => _commit(),
          onHorizontalDragCancel: () => setState(() => _dragging = false),
          child: SizedBox(
            height: 18,
            child: AnimatedScale(
              scale: _dragging ? 1.35 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.fastOutSlowIn,
              child: SizedBox(
                width: double.infinity,
                child: CustomPaint(
                  painter: _AudioProgressPainter(fraction: fraction),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AudioProgressPainter extends CustomPainter {
  final double fraction;

  const _AudioProgressPainter({required this.fraction});

  @override
  void paint(Canvas canvas, Size size) {
    final double centerY = size.height / 2;
    final RRect track = RRect.fromRectAndRadius(
      Rect.fromLTRB(0, centerY - 1, size.width, centerY + 1),
      const Radius.circular(1),
    );
    canvas.save();
    canvas.clipRRect(track);
    final Paint tick = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (double x = 0; x <= size.width; x += 4) {
      canvas.drawLine(Offset(x, centerY - 1), Offset(x, centerY + 1), tick);
    }
    final double progressX = size.width * fraction.clamp(0.0, 1.0);
    if (progressX > 0) {
      final Paint active = Paint()
        ..color = Colors.white
        ..strokeWidth = 2;
      canvas.drawLine(Offset(0, centerY), Offset(progressX, centerY), active);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AudioProgressPainter oldDelegate) =>
      oldDelegate.fraction != fraction;
}

class _AudioTransportButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _AudioTransportButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(
        icon,
        size: 30,
        color: onTap == null ? Colors.white24 : Colors.white,
      ),
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    );
  }
}

/// 中央播放/暂停键：72dp 圆形容器 + 播放态颜色与图标形变。
class _AudioPlayButton extends StatelessWidget {
  final bool playing;
  final String tooltip;
  final VoidCallback onTap;

  const _AudioPlayButton({
    super.key,
    required this.playing,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color container =
        playing ? scheme.primaryContainer : scheme.secondaryContainer;
    final Color content =
        playing ? scheme.onPrimaryContainer : scheme.onSecondaryContainer;
    return Tooltip(
      message: tooltip,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.fastOutSlowIn,
        width: 72,
        height: 72,
        decoration: BoxDecoration(color: container, shape: BoxShape.circle),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.fastOutSlowIn,
                switchOutCurve: Curves.fastOutSlowIn,
                transitionBuilder:
                    (Widget child, Animation<double> animation) =>
                        ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  key: ValueKey<bool>(playing),
                  size: 36,
                  color: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 工具行按钮：图标 + 小字标签（倍速 / 歌词 / 选集 / 定时）。
class _AudioUtilityButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  const _AudioUtilityButton({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceSm,
            vertical: AppTokens.spaceXxs,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 22, color: Colors.white70),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AudioEpisodeList extends StatefulWidget {
  final List<Episode> episodes;
  final String fallbackTitle;
  final int currentIndex;
  final bool playing;
  final EdgeInsets padding;
  final ValueChanged<int> onSelect;

  const _AudioEpisodeList({
    super.key,
    required this.episodes,
    required this.fallbackTitle,
    required this.currentIndex,
    required this.playing,
    required this.padding,
    required this.onSelect,
  });

  @override
  State<_AudioEpisodeList> createState() => _AudioEpisodeListState();
}

class _AudioEpisodeListState extends State<_AudioEpisodeList> {
  static const double _itemExtent = 68;

  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: math.max(0, widget.currentIndex - 2) * _itemExtent,
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool empty = widget.episodes.isEmpty;
    final int count = empty ? 1 : widget.episodes.length;
    final int current =
        empty ? 0 : widget.currentIndex.clamp(0, widget.episodes.length - 1);
    return ListView.builder(
      controller: _scroll,
      itemExtent: _itemExtent,
      padding: EdgeInsets.only(
        top: widget.padding.top + AppTokens.spaceMd,
        bottom: widget.padding.bottom + AppTokens.spaceMd,
        left: AppTokens.spaceLg,
        right: AppTokens.spaceLg,
      ),
      itemCount: count,
      itemBuilder: (BuildContext context, int index) {
        final bool selected = index == current;
        final String title =
            empty ? widget.fallbackTitle : widget.episodes[index].title;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Material(
            color: selected
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: empty || selected ? null : () => widget.onSelect(index),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: AppTokens.spaceSm,
                ),
                child: Row(
                  children: <Widget>[
                    // 当前集前置播放状态图标；非当前集不显示序号。
                    if (selected) ...<Widget>[
                      Icon(
                        widget.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: AppTokens.spaceSm),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.white70,
                          fontSize: 15,
                          height: 1.35,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
