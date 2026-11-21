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
      onPageChanged: (int page) => _audioPageIndex.value = page,
      onSelectEpisode: (int index) => unawaited(_changeEpisode(index)),
      onSeek: (Duration position) => unawaited(_controller.seek(position)),
    );
  }

  /// 音频模式底部控制栏：刻度进度条 + 两端时间 + 单行传输键。
  ///
  /// 仅在封面主页（页码 1）显示：滑到列表/歌词页时淡出并不拦截手势，
  /// 因此横滑切页时底栏不会跟随。传输行按空间感排布——中央 72dp 播放键
  /// 最大，两侧切集键次之，最外侧定时/倍速最小，整体垂直居中对齐；
  /// 左右等宽槽夹住播放键，暂停键水平严格居中。
  Widget _buildAudioBottomBar(AppLocalizations l10n) {
    final bool hasPrev = widget.episodes != null && _episodeIndex > 0;
    final bool hasNext =
        widget.episodes != null && _episodeIndex < widget.episodes!.length - 1;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final AudioPlayButtonColorMode colorMode =
        _playerSettings.audioPlayButtonColorMode;
    final Color? solidColor = colorMode == AudioPlayButtonColorMode.solid
        ? (_playerSettings.audioPlayButtonColor == 0
            ? scheme.primaryContainer
            : Color(_playerSettings.audioPlayButtonColor))
        : null;
    const TextStyle timeStyle = TextStyle(color: Colors.white54, fontSize: 11);

    Widget playButton({ColorScheme? coverPalette}) => _AudioPlayButton(
          key: const Key('player_audio_play_pause'),
          playing: _isPlaying,
          palette: coverPalette,
          customColor: solidColor,
          tooltip: _isPlaying ? l10n.pause : l10n.play,
          onTap: () {
            _cancelAutoNextCountdown();
            _togglePlayPause();
          },
        );

    // 封面取色模式：复用封面调色板缓存异步取色，未就绪时回退主题配色。
    final Widget transportPlay = colorMode == AudioPlayButtonColorMode.cover
        ? FutureBuilder<ColorScheme?>(
            future: _audioCoverPalette(widget.coverUrl?.trim() ?? ''),
            builder: (BuildContext context, AsyncSnapshot<ColorScheme?> snap) =>
                playButton(coverPalette: snap.data),
          )
        : playButton();

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: ValueListenableBuilder<int>(
        valueListenable: _audioPageIndex,
        builder: (BuildContext context, int page, Widget? child) {
          final bool visible = page == 1;
          return IgnorePointer(
            ignoring: !visible,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: child,
            ),
          );
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
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
              bottom:
                  MediaQuery.of(context).padding.bottom + AppTokens.spaceMd,
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
                  padding: const EdgeInsets.only(
                    top: AppTokens.spaceXl,
                    bottom: AppTokens.spaceXl,
                  ),
                  // 左右等宽槽夹住播放键：暂停键严格居中；左组向右靠、
                  // 右组向左靠，层级由中心向两侧递减（72 → 48 → 22）。
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: <Widget>[
                            _AudioUtilityButton(
                              key: const Key('player_sleep_timer'),
                              icon: Icons.timer_outlined,
                              label: l10n.playerTimer,
                              tooltip: l10n.playerTimer,
                              onTap: () => _showSleepTimerPicker(l10n),
                            ),
                            _AudioTransportButton(
                              key: const Key('player_prev_ep'),
                              icon: Icons.skip_previous_rounded,
                              tooltip: l10n.playerPreviousEpisode,
                              onTap: hasPrev ? _goPrevEpisode : null,
                            ),
                          ],
                        ),
                      ),
                      transportPlay,
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: <Widget>[
                            _AudioTransportButton(
                              key: const Key('player_next_ep'),
                              icon: Icons.skip_next_rounded,
                              tooltip: l10n.playerNextEpisode,
                              onTap: hasNext ? _goNextEpisode : null,
                            ),
                            _AudioUtilityButton(
                              key: const Key('player_quick_speed'),
                              icon: Icons.speed_rounded,
                              label: '${_controller.playbackSpeed}x',
                              tooltip: l10n.playerPlaybackSpeed,
                              onTap: () => _showSpeedPicker(l10n),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
  final ValueChanged<int> onPageChanged;
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
    required this.onPageChanged,
    required this.onSelectEpisode,
    required this.onSeek,
  });

  @override
  State<_AudioSurface> createState() => _AudioSurfaceState();
}

class _AudioSurfaceState extends State<_AudioSurface> {
  late final PageController _pager = PageController(initialPage: 1);
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
    if (!_pager.hasClients) return;
    _pager.animateToPage(
      2,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  /// 页面上/下留白：顶部让出返回栏；封面页底部让出控制栏（约 216dp），
  /// 列表/歌词页无控制栏，只留安全区。
  EdgeInsets _pagePadding(
    BuildContext context, {
    bool leaveControlsSpace = true,
  }) {
    final MediaQueryData media = MediaQuery.of(context);
    return EdgeInsets.only(
      top: media.padding.top + 72,
      bottom: media.padding.bottom +
          (leaveControlsSpace ? 216 : AppTokens.spaceXl),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = <Widget>[
      _buildEpisodePage(context),
      _buildCoverPage(context),
      _buildLyricsPage(context),
    ];
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        _buildBackground(context),
        PageView(
          controller: _pager,
          onPageChanged: widget.onPageChanged,
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
    final EdgeInsets padding =
        _pagePadding(context, leaveControlsSpace: false);
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
      child: _hasLyrics
          ? AudioLyricsView(
              key: const Key('player_audio_lyrics_page'),
              lines: widget.lyrics,
              positionStream: widget.positionStream,
              initialPosition: widget.initialPosition,
              onSeekMs: (int ms) =>
                  widget.onSeek(Duration(milliseconds: ms)),
            )
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.lyrics_outlined,
                    size: 42,
                    color: Colors.white38,
                  ),
                  const SizedBox(height: AppTokens.spaceSm),
                  Text(
                    l10n.audioLyricsEmptyHint,
                    key: const Key('player_audio_lyrics_empty'),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
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
      padding: _pagePadding(context, leaveControlsSpace: false),
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

  /// 封面取色模式下的封面调色板；null 时用应用主题配色。
  final ColorScheme? palette;

  /// 纯色模式下的自定义容器色；非 null 时优先于 [palette]/主题。
  final Color? customColor;
  final VoidCallback onTap;

  const _AudioPlayButton({
    super.key,
    required this.playing,
    required this.tooltip,
    this.palette,
    this.customColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ColorScheme tones = palette ?? scheme;
    final Color container = customColor ??
        (playing ? tones.primaryContainer : tones.secondaryContainer);
    final Color content = customColor != null
        ? (ThemeData.estimateBrightnessForColor(customColor!) == Brightness.dark
            ? Colors.white
            : Colors.black87)
        : (playing ? tones.onPrimaryContainer : tones.onSecondaryContainer);
    return Tooltip(
      message: tooltip,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.fastOutSlowIn,
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: container,
          shape: BoxShape.circle,
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Colors.black38,
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
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
        // 固定 48 图标槽：与传输键同高，图标中线落在行中线上；
        // 文字悬挂在图标下方，不参与行内垂直对齐，左右按钮宽度对称。
        child: SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: <Widget>[
              Icon(icon, size: 22, color: Colors.white70),
              Positioned(
                top: 36,
                left: -8,
                right: -8,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    height: 1.2,
                  ),
                ),
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
  static const Duration _idleRecenterDelay = Duration(seconds: 3);

  final ScrollController _scroll = ScrollController();
  Timer? _idleTimer;
  bool _userScrolling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _centerCurrent(animate: false));
  }

  @override
  void didUpdateWidget(covariant _AudioEpisodeList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex ||
        !identical(oldWidget.episodes, widget.episodes)) {
      _idleTimer?.cancel();
      _idleTimer = null;
      if (!_userScrolling) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _centerCurrent();
        });
      }
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// 把当前集滚到视口垂直中线；静置态下同时是空间感缩放的最大行。
  void _centerCurrent({bool animate = true}) {
    if (!mounted || !_scroll.hasClients || widget.episodes.isEmpty) return;
    if (_scroll.position.viewportDimension <= 0) return;
    final int current =
        widget.currentIndex.clamp(0, widget.episodes.length - 1);
    final double target = (widget.padding.top +
            AppTokens.spaceMd +
            current * _itemExtent +
            _itemExtent / 2 -
            _scroll.position.viewportDimension / 2)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    if (!animate) {
      _scroll.jumpTo(target);
      return;
    }
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 520),
      curve: Curves.fastOutSlowIn,
    );
  }

  /// 用户拖动/甩动结束后静置数秒回中；程序化滚动不触发。
  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _userScrolling = true;
      _idleTimer?.cancel();
      _idleTimer = null;
    } else if (notification is ScrollEndNotification && _userScrolling) {
      _userScrolling = false;
      _idleTimer?.cancel();
      _idleTimer = Timer(_idleRecenterDelay, () {
        _idleTimer = null;
        _centerCurrent();
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.episodes.isEmpty) {
      final AppLocalizations l10n = AppLocalizations.of(context);
      return Padding(
        padding: EdgeInsets.only(
          top: widget.padding.top,
          bottom: widget.padding.bottom,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.queue_music_rounded,
                size: 42,
                color: Colors.white38,
              ),
              const SizedBox(height: AppTokens.spaceSm),
              Text(
                l10n.audioEpisodesEmptyHint,
                key: const Key('player_audio_episodes_empty'),
                style: const TextStyle(color: Colors.white54, fontSize: 15),
              ),
              if (widget.fallbackTitle.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: AppTokens.spaceXs),
                Text(
                  widget.fallbackTitle,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      );
    }
    final int current =
        widget.currentIndex.clamp(0, widget.episodes.length - 1);
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: ListView.builder(
        controller: _scroll,
        itemExtent: _itemExtent,
        padding: EdgeInsets.only(
          top: widget.padding.top + AppTokens.spaceMd,
          bottom: widget.padding.bottom + AppTokens.spaceMd,
          left: AppTokens.spaceLg,
          right: AppTokens.spaceLg,
        ),
        itemCount: widget.episodes.length,
        itemBuilder: (BuildContext context, int index) {
          final bool selected = index == current;
          final String title = widget.episodes[index].title;
          // 空间感：越靠近视口垂直中线越大，向上下两端递减；当前集略加成。
          return AnimatedBuilder(
            animation: _scroll,
            builder: (BuildContext context, Widget? child) => Transform.scale(
              scale: (_scaleFor(index) + (selected ? 0.1 : 0)).clamp(0.0, 1.1),
              child: child,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Material(
                color: selected
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: selected ? null : () => widget.onSelect(index),
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
            ),
          );
        },
      ),
    );
  }

  /// 行中心距视口垂直中线的远近 → 缩放比例（中线 1.0，两端约 0.72）。
  double _scaleFor(int index) {
    if (!_scroll.hasClients) return 1;
    final double viewport = _scroll.position.viewportDimension;
    if (viewport <= 0) return 1;
    final double itemCenter = widget.padding.top +
        AppTokens.spaceMd +
        index * _itemExtent +
        _itemExtent / 2 -
        _scroll.offset;
    final double distance =
        ((itemCenter - viewport / 2).abs() / (viewport / 2)).clamp(0.0, 1.0);
    return 1 - 0.28 * distance;
  }
}
