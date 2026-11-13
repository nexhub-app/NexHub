/// 媒体服务器条目详情页：沉浸式大图头（背景剧照模糊 + 渐变遮罩，
/// 海报 / 标题浮层）+ 播放操作 + 季切换 / 集列表。
///
/// - 电影 → 播放按钮（有续播位置时给「继续播放」+「从头播放」）；
/// - 剧集 → 季切换 + 集列表（缩略图、时长、已看角标、未看完进度条）→
///   点击集直接播放（携带整季列表，播放器内可上下集 / 自动连播）；
///   返回后刷新已看角标与进度（进度只存服务器）；
/// - 含图形字幕（PGS）的集标注「需转码，暂不支持」。
library;

import 'dart:async' show unawaited;
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../core/history/history_manager.dart';
import '../../core/models/plugin_config.dart' show SourceType;
import '../../core/navigation/app_page_route.dart';
import '../../core/network/dio_image_file_service.dart';
import '../../core/services/media_server/media_server_client.dart';
import '../../core/services/media_server/media_server_models.dart';
import '../../core/services/media_server/media_server_session.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/app_haptics.dart';
import '../../core/widgets/app_animations.dart';
import '../../core/widgets/app_shimmer.dart';
import '../../core/widgets/translatable_text.dart';
import 'media_server_widgets.dart';

class MediaServerDetailScreen extends StatefulWidget {
  final MediaServerClientBase client;
  final String itemId;

  const MediaServerDetailScreen({
    super.key,
    required this.client,
    required this.itemId,
  });

  @override
  State<MediaServerDetailScreen> createState() =>
      _MediaServerDetailScreenState();
}

class _MediaServerDetailScreenState extends State<MediaServerDetailScreen> {
  ServerMediaItem? _detail;
  Object? _error;
  bool _loading = true;

  /// 剧集：季列表与当前选中季的集列表。
  List<ServerMediaItem>? _seasons;
  String? _selectedSeasonId;
  List<ServerMediaItem>? _episodes;
  Object? _episodesError;
  bool _episodesLoading = false;

  bool get _isSeries => _detail?.type == 'Series';

  bool get _isBoxSet => _detail?.type == 'BoxSet';

  /// 合集子项（BoxSet 内的电影 / 剧集）。
  List<ServerMediaItem>? _boxSetChildren;
  Object? _boxSetError;

  /// 折叠标题透明度（0 = 展开显示头图，1 = 收起显示标题）。
  final ValueNotifier<double> _titleOpacity = ValueNotifier<double>(0);

  /// 头图展开高度（SliverAppBar expandedHeight 与折叠进度分母）。
  static const double _headerHeight = 340;

  @override
  void initState() {
    super.initState();
    _reload();
    // 进详情即预取 backdrop（头图秒出；磁盘缓存二次进入零等待）。
    // provider 必须与显示端（MediaServerPoster → NexImageCacheManager）同一
    // 缓存管理器：precacheImage 的落盘位置由 provider 决定，用默认管理器预取
    // 会存进另一套缓存目录，显示端查统一缓存时预取等于白做。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      precacheImage(
        CachedNetworkImageProvider(
          widget.client.backdropUrl(widget.itemId),
          headers: widget.client.authHeaders(),
          cacheManager: NexImageCacheManager.instance,
        ),
        context,
      );
    });
  }

  @override
  void dispose() {
    _titleOpacity.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.client.fetchItem(widget.itemId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
      // 写入浏览历史（kind=mediaServer；封面带鉴权头落盘离线可见）。
      unawaited(_recordHistory(detail));
      if (detail.type == 'Series') {
        await _loadSeasons();
      } else if (detail.type == 'BoxSet') {
        await _loadBoxSetChildren(detail.id);
      }
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadSeasons() async {
    try {
      final seasons = await widget.client.fetchSeasons(widget.itemId);
      if (!mounted) return;
      setState(() {
        _seasons = seasons;
        _selectedSeasonId = seasons.isNotEmpty ? seasons.first.id : null;
      });
      await _loadEpisodes();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _episodesError = e);
    }
  }

  Future<void> _loadEpisodes() async {
    final seasonId = _selectedSeasonId;
    if (seasonId == null) return;
    setState(() {
      _episodesLoading = true;
      _episodesError = null;
    });
    try {
      final episodes =
          await widget.client.fetchEpisodes(widget.itemId, seasonId: seasonId);
      if (!mounted) return;
      setState(() {
        _episodes = episodes;
        _episodesLoading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _episodesError = e;
        _episodesLoading = false;
      });
    }
  }

  /// 播放后返回刷新：进度 / 已看角标以服务器为准。
  /// 携带整季集列表 → 播放器内可直接上下集 / 自动连播（零额外请求）。
  Future<void> _play(ServerMediaItem item, {bool fromStart = false}) async {
    AppHaptics.selectionClick();
    await openMediaServerPlayer(
      context,
      client: widget.client,
      item: item,
      playlist: _episodes,
      fromStart: fromStart,
    );
    if (_isSeries) {
      await _loadEpisodes();
    }
    await _reload();
  }

  /// 加载合集子项（BoxSet 内的电影 / 剧集）。
  Future<void> _loadBoxSetChildren(String boxSetId) async {
    try {
      final children = await widget.client.fetchItems(
        parentId: boxSetId,
        includeTypes: const <String>['Movie', 'Series'],
        limit: 200,
      );
      if (!mounted) return;
      setState(() => _boxSetChildren = children.items);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _boxSetError = e);
    }
  }

  // ─────────────── 互动：收藏 / 已看 ───────────────

  /// 写入浏览历史（kind = mediaServer，id/detailUrl 存路由凭据）。
  Future<void> _recordHistory(ServerMediaItem detail) async {
    try {
      final history = context.read<HistoryManager>();
      final localCover =
          await widget.client.downloadCoverToHistory(detail.id);
      final entry = HistoryEntry(
        id: widget.client.contentIdFor(detail),
        title: detail.name,
        coverUrl: widget.client.imageUrl(detail.id, maxWidth: 400),
        sourceId: 'ms:${widget.client.info.id}',
        sourceType: SourceType.animeSource,
        detailUrl: widget.client.contentIdFor(detail),
        viewedAt: DateTime.now().millisecondsSinceEpoch,
        localCoverPath: localCover,
        kind: 'mediaServer',
      );
      await history.addEntryRaw(entry);
    } on Object {
      // 历史不可用不影响详情页。
    }
  }

  /// 收藏切换：乐观更新 + 失败回滚 + 提示。
  Future<void> _toggleFavorite() async {
    final detail = _detail;
    if (detail == null) return;
    final l10n = AppLocalizations.of(context);
    final current = detail.userData?.isFavorite ?? false;
    final target = !current;
    // MD3「Toggle」：收藏开关切换 → tick。
    target ? AppHaptics.toggleOn() : AppHaptics.toggleOff();
    setState(() {
      _detail = detail.copyWith(
        userData: (detail.userData ?? const ServerUserData(played: false))
            .copyWith(isFavorite: target),
      );
    });
    try {
      await widget.client.setFavorite(detail.id, favorite: target);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            target
                ? l10n.mediaServerFavoriteAdded
                : l10n.mediaServerFavoriteRemoved,
          ),
        ),
      );
    } on Object {
      // 失败回滚。
      if (!mounted) return;
      setState(() {
        _detail = detail.copyWith(
          userData: (detail.userData ?? const ServerUserData(played: false))
              .copyWith(isFavorite: current),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.mediaServerOperationFailed('favorite'))),
      );
    }
  }

  /// 已看切换（电影）：乐观更新 + 失败回滚。
  Future<void> _toggleWatched() async {
    final detail = _detail;
    if (detail == null) return;
    final current = detail.userData?.played ?? false;
    final target = !current;
    // MD3「Toggle」：已看开关切换 → tick。
    target ? AppHaptics.toggleOn() : AppHaptics.toggleOff();
    setState(() {
      _detail = detail.copyWith(
        userData: (detail.userData ?? const ServerUserData(played: false))
            .copyWith(
          played: target,
          playbackPositionTicks: target ? null : 0,
        ),
      );
    });
    try {
      if (target) {
        await widget.client.markPlayed(detail.id);
      } else {
        await widget.client.markUnplayed(detail.id);
      }
    } on Object {
      if (!mounted) return;
      setState(() {
        _detail = detail.copyWith(
          userData: (detail.userData ?? const ServerUserData(played: false))
              .copyWith(
            played: current,
            playbackPositionTicks: detail.userData?.playbackPositionTicks,
          ),
        );
      });
    }
  }

  /// 单集已看切换（长按集卡片）：乐观更新 + 失败回滚。
  Future<void> _toggleEpisodeWatched(ServerMediaItem ep) async {
    final episodes = _episodes;
    if (episodes == null) return;
    final current = ep.userData?.played ?? false;
    final target = !current;
    final index = episodes.indexWhere((e) => e.id == ep.id);
    if (index < 0) return;
    // MD3「Toggle」：单集已看开关切换 → tick。
    target ? AppHaptics.toggleOn() : AppHaptics.toggleOff();
    setState(() {
      _episodes = <ServerMediaItem>[
        for (final e in episodes)
          if (e.id == ep.id)
            e.copyWith(
              userData: (e.userData ?? const ServerUserData(played: false))
                  .copyWith(
                played: target,
                playbackPositionTicks: target ? null : 0,
              ),
            )
          else
            e,
      ];
    });
    try {
      if (target) {
        await widget.client.markPlayed(ep.id);
      } else {
        await widget.client.markUnplayed(ep.id);
      }
    } on Object {
      if (!mounted) return;
      setState(() {
        _episodes = episodes;
      });
    }
  }

  /// 整季标记已看：逐集标记（小间隔，友好对待公益服务器）。
  Future<void> _markSeasonWatched() async {
    final episodes = _episodes;
    if (episodes == null) return;
    final targets =
        episodes.where((e) => !(e.userData?.played ?? false)).toList();
    if (targets.isEmpty) return;
    for (final e in targets) {
      try {
        await widget.client.markPlayed(e.id);
      } on Object {
        // 单集失败跳过，继续其余。
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    if (!mounted) return;
    await _loadEpisodes();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(body: _buildBody(context, l10n));
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    if (_loading) return const _DetailSkeleton();
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                l10n.mediaServerLoadFailed('$_error'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppTokens.spaceMd),
              OutlinedButton(
                onPressed: _reload,
                child: Text(l10n.mediaServerRetry),
              ),
            ],
          ),
        ),
      );
    }
    final detail = _detail;
    if (detail == null) return const SizedBox.shrink();
    // SliverAppBar 视差折叠——展开为沉浸式头图，收起后标题渐显。
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis != Axis.vertical) return false;
        final t = (n.metrics.pixels / _headerHeight).clamp(0.0, 1.0);
        if ((t - _titleOpacity.value).abs() > 0.02) _titleOpacity.value = t;
        return false;
      },
      child: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(
            pinned: true,
            expandedHeight: _headerHeight,
            title: ValueListenableBuilder<double>(
              valueListenable: _titleOpacity,
              builder: (_, v, __) => Opacity(
                opacity: v,
                child: AutoTranslatedText(
                  text: detail.name,
                  kind: TranslatableTextKind.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background:
                  _ImmersiveHeader(client: widget.client, detail: detail),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate(<Widget>[
              Entrance(
                onceKey: 'ms_detail_content',
                offset: 16,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.spaceMd,
                    AppTokens.spaceMd,
                    AppTokens.spaceMd,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (!_isBoxSet) ..._actions(context, detail, l10n),
                      if (detail.overview != null &&
                          detail.overview!.isNotEmpty) ...<Widget>[
                        const SizedBox(height: AppTokens.spaceMd),
                        BilingualTranslatedText(
                          text: detail.overview!,
                          kind: TranslatableTextKind.summary,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(height: 1.5),
                        ),
                      ],
                      if (_isBoxSet) ..._boxSetSectionStatic(
                        context,
                        widget.client,
                        _boxSetChildren,
                        _boxSetError,
                      ),
                      if (_isSeries) ..._seriesSection(context, l10n),
                      const SizedBox(height: AppTokens.spaceXl),
                    ],
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  /// 播放按钮组（电影：继续 / 从头；剧集：播放首集或当前季首集）
  /// + 收藏 + 已看切换（电影）。
  List<Widget> _actions(
    BuildContext context,
    ServerMediaItem detail,
    AppLocalizations l10n,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final hasPosition = (detail.userData?.playbackPositionTicks ?? 0) > 0;
    final playTarget = _isSeries ? (_episodes?.firstOrNull ?? detail) : detail;
    final targetHasPosition =
        (playTarget.userData?.playbackPositionTicks ?? 0) > 0;
    final showResume = !_isSeries && hasPosition;
    final showResumeSeries = _isSeries && targetHasPosition;
    final favorited = detail.userData?.isFavorite ?? false;
    final watched = detail.userData?.played ?? false;
    return <Widget>[
      const SizedBox(height: AppTokens.spaceSm),
      Row(
        children: <Widget>[
          Expanded(
            child: FilledButton.icon(
              onPressed: () => _play(playTarget),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(
                (showResume || showResumeSeries)
                    ? l10n.mediaServerResumePlay
                    : l10n.mediaServerPlay,
              ),
            ),
          ),
          const SizedBox(width: AppTokens.spaceSm),
          // 收藏：心形，乐观更新。
          IconButton.filledTonal(
            onPressed: _toggleFavorite,
            tooltip: l10n.mediaServerFavorite,
            icon: Icon(
              favorited
                  ? Icons.favorite_rounded
                  : Icons.favorite_outline_rounded,
              color: favorited ? scheme.error : null,
            ),
          ),
          // 已看切换（电影）。
          if (!_isSeries)
            IconButton.filledTonal(
              onPressed: _toggleWatched,
              tooltip: watched
                  ? l10n.mediaServerMarkUnwatched
                  : l10n.mediaServerMarkWatched,
              icon: Icon(
                watched
                    ? Icons.check_circle_rounded
                    : Icons.check_circle_outline_rounded,
              ),
            ),
        ],
      ),
      if (showResume) ...<Widget>[
        const SizedBox(height: AppTokens.spaceSm),
        OutlinedButton.icon(
          onPressed: () => _play(detail, fromStart: true),
          icon: const Icon(Icons.replay_rounded),
          label: Text(l10n.mediaServerPlayFromStart),
        ),
      ],
    ];
  }

  /// 剧集：季切换 + 集列表。
  List<Widget> _seriesSection(BuildContext context, AppLocalizations l10n) {
    final seasons = _seasons;
    if (seasons == null) {
      return const <Widget>[
        Padding(
          padding: EdgeInsets.all(AppTokens.spaceLg),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    return <Widget>[
      const SizedBox(height: AppTokens.spaceLg),
      if (seasons.length > 1)
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: <Widget>[
              for (final s in seasons)
                Padding(
                  padding: const EdgeInsets.only(right: AppTokens.spaceSm),
                  child: ChoiceChip(
                    label: Text(s.name),
                    selected: s.id == _selectedSeasonId,
                    onSelected: (_) {
                      AppHaptics.selectionClick();
                      setState(() => _selectedSeasonId = s.id);
                      _loadEpisodes();
                    },
                  ),
                ),
            ],
          ),
        ),
      // 整季标记已看：仅当当前季存在未看集时显示。
      if (!_episodesLoading &&
          (_episodes ?? const <ServerMediaItem>[])
              .any((e) => !(e.userData?.played ?? false)))
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _markSeasonWatched,
            icon: const Icon(Icons.done_all_rounded, size: 18),
            label: Text(l10n.mediaServerMarkAllWatched),
          ),
        ),
      if (_episodesLoading)
        const Padding(
          padding: EdgeInsets.all(AppTokens.spaceLg),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_episodesError != null)
        Text(
          l10n.mediaServerLoadFailed('$_episodesError'),
          style: Theme.of(context).textTheme.bodySmall,
        )
      else
        for (final ep in _episodes ?? const <ServerMediaItem>[])
          _EpisodeCard(
            client: widget.client,
            episode: ep,
            onTap: () => _play(ep),
            onLongPress: () => _toggleEpisodeWatched(ep),
          ),
    ];
  }
}

/// 沉浸式大图头：背景剧照模糊 + 双向渐变遮罩，海报 / 标题浮层。
class _ImmersiveHeader extends StatelessWidget {
  final MediaServerClientBase client;
  final ServerMediaItem detail;

  const _ImmersiveHeader({required this.client, required this.detail});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    final runtime = detail.runTimeTicks;
    final subtitleParts = <String>[
      if (detail.productionYear != null) '${detail.productionYear}',
      if (detail.type == 'Series')
        l10n.mediaServerTypeSeries
      else if (detail.type == 'BoxSet')
        l10n.mediaServerTypeBoxSet
      else if (runtime != null && runtime > 0) _formatRuntime(context, runtime),
    ];
    return Stack(
      children: <Widget>[
        // 底层：海报高斯模糊——Backdrop 缺失（实测部分条目无剧照）时的兜底。
        Positioned.fill(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: MediaServerPoster(
              url: client.imageUrl(detail.id, maxWidth: 800),
              headers: client.authHeaders(),
              fit: BoxFit.cover,
            ),
          ),
        ),
        // 顶层：横幅剧照（清晰 backdrop + 朝底色渐变遮罩），
        // 缺失时静默透出底层模糊海报。
        Positioned.fill(
          child: MediaServerPoster(
            url: client.backdropUrl(detail.id),
            headers: client.authHeaders(),
            fit: BoxFit.cover,
            errorPlaceholder: false,
          ),
        ),
        // 渐变遮罩：顶部压暗保证返回键可见，底部收拢到页面底色。
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const <double>[0, 0.35, 1],
                colors: <Color>[
                  scheme.surface.withValues(alpha: 0.55),
                  scheme.surface.withValues(alpha: 0.25),
                  scheme.surface,
                ],
              ),
            ),
          ),
        ),
        // 浮层内容：海报 + 标题（投影保可读）/ 元信息胶囊 chips。
        Container(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.spaceMd,
            AppTokens.spaceXl * 2,
            AppTokens.spaceMd,
            AppTokens.spaceMd,
          ),
          child: SafeArea(
            bottom: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  child: SizedBox(
                    width: 110,
                    height: 165,
                    child: MediaServerPoster(
                      url: client.imageUrl(detail.id, maxWidth: 400),
                      headers: client.authHeaders(),
                      // C4：库网格 → 详情页共享元素过渡（与库页同 tag）。
                      heroTag: 'ms:${detail.id}',
                    ),
                  ),
                ),
                const SizedBox(width: AppTokens.spaceMd),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppTokens.spaceXs),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        // 台标优先：有 ClearLogo 显示台标，
                        // 加载中 / 缺失回退文字标题（带投影）。
                        _ClearLogoTitle(
                          client: client,
                          detail: detail,
                          fallbackStyle: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            shadows: <Shadow>[
                              Shadow(
                                color: scheme.surface.withValues(alpha: 0.8),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                        if (subtitleParts.isNotEmpty) ...<Widget>[
                          const SizedBox(height: AppTokens.spaceSm),
                          Wrap(
                            spacing: AppTokens.spaceXs,
                            runSpacing: AppTokens.spaceXs,
                            children: <Widget>[
                              for (final part in subtitleParts)
                                _HeroChip(label: part),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _formatRuntime(BuildContext context, int ticks) {
    final l10n = AppLocalizations.of(context);
    final totalMinutes = ticks ~/ 10000 ~/ 1000 ~/ 60;
    if (totalMinutes >= 60) {
      return l10n.mediaServerRuntimeHoursMinutes(
        '${totalMinutes ~/ 60}',
        '${totalMinutes % 60}',
      );
    }
    return l10n.mediaServerRuntimeMinutes('$totalMinutes');
  }
}

/// 台标优先的标题：服务器有 ClearLogo 时显示台标图；
/// 加载中 / 缺失回退文字标题（带投影，浅深色主题均可读）。
class _ClearLogoTitle extends StatelessWidget {
  final MediaServerClientBase client;
  final ServerMediaItem detail;
  final TextStyle? fallbackStyle;

  const _ClearLogoTitle({
    required this.client,
    required this.detail,
    required this.fallbackStyle,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 96),
      child: CachedNetworkImage(
        imageUrl: client.logoUrl(detail.id),
        httpHeaders: client.authHeaders(),
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (_, __) => AutoTranslatedText(
            text: detail.name,
            kind: TranslatableTextKind.title,
            style: fallbackStyle),
        errorWidget: (_, __, ___) => AutoTranslatedText(
            text: detail.name,
            kind: TranslatableTextKind.title,
            style: fallbackStyle),
      ),
    );
  }
}

/// 头图元信息胶囊（年份 / 类型 / 时长），圆角 full 对齐基准芯片规范。
class _HeroChip extends StatelessWidget {
  final String label;

  const _HeroChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceSm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppTokens.radiusFull),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

/// 合集子项网格：BoxSet 内的电影 / 剧集，点击进对应详情。
///
/// [children] 为 null 表示子项仍在加载（显示进度圈），空列表表示合集为空。
List<Widget> _boxSetSectionStatic(
  BuildContext context,
  MediaServerClientBase client,
  List<ServerMediaItem>? children,
  Object? error,
) {
  if (error != null) {
    return <Widget>[
      Text(
        AppLocalizations.of(context).mediaServerLoadFailed('$error'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ];
  }
  if (children == null) {
    return const <Widget>[
      Padding(
        padding: EdgeInsets.all(AppTokens.spaceLg),
        child: Center(child: CircularProgressIndicator()),
      ),
    ];
  }
  return <Widget>[
    GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: AppTokens.spaceSm),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 130,
        mainAxisSpacing: AppTokens.spaceSm,
        crossAxisSpacing: AppTokens.spaceSm,
        childAspectRatio: 0.55,
      ),
      itemCount: children.length,
      itemBuilder: (context, i) {
        final item = children[i];
        return GestureDetector(
          onTap: () {
            AppHaptics.selectionClick();
            Navigator.of(context).push(
              AppPageRoute<void>(
                builder: (_) =>
                    MediaServerDetailScreen(client: client, itemId: item.id),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  child: MediaServerPoster(
                    url: client.imageUrl(item.id, maxWidth: 300),
                    headers: client.authHeaders(),
                  ),
                ),
              ),
              const SizedBox(height: AppTokens.spaceXs),
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
              ),
            ],
          ),
        );
      },
    ),
  ];
}

/// 集卡片：缩略图 / 时长 / 已看角标 / 未看完进度条 / PGS 标注。
/// 长按切换已看。
class _EpisodeCard extends StatelessWidget {
  final MediaServerClientBase client;
  final ServerMediaItem episode;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _EpisodeCard({
    required this.client,
    required this.episode,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final userData = episode.userData;
    final played = userData?.played ?? false;
    final ticks = userData?.playbackPositionTicks ?? 0;
    final runtime = episode.runTimeTicks ?? 0;
    final progress = (runtime > 0 && ticks > 0 && !played)
        ? (ticks / runtime).clamp(0.0, 1.0)
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: AppTokens.spaceSm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceSm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Stack(
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                    child: SizedBox(
                      width: 110,
                      height: 62,
                      child: MediaServerPoster(
                        url: client.imageUrl(episode.id, maxWidth: 300),
                        headers: client.authHeaders(),
                      ),
                    ),
                  ),
                  // 集数徽章：缩略图左下角。
                  if (episode.indexNumber != null)
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTokens.spaceXs,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(AppTokens.radiusXs),
                        ),
                        child: Text(
                          'E${episode.indexNumber}',
                          style: textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  if (played)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: CircleAvatar(
                        radius: 10,
                        backgroundColor: scheme.primary,
                        child: Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: AppTokens.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      (episode.parentIndexNumber != null &&
                              episode.indexNumber != null)
                          ? '${episode.parentIndexNumber}'
                              'x${episode.indexNumber.toString().padLeft(2, '0')}'
                              ' ${episode.name}'
                          : episode.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppTokens.spaceXs),
                    if (runtime > 0)
                      Text(
                        l10n.mediaServerRuntimeMinutes(
                          '${runtime ~/ 10000 ~/ 1000 ~/ 60}',
                        ),
                        style: textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    if (progress != null) ...<Widget>[
                      const SizedBox(height: AppTokens.spaceXs),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppTokens.radiusXs),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                          backgroundColor: scheme.surfaceContainerHighest,
                        ),
                      ),
                    ],
                    if (episode.hasGraphicSubtitle) ...<Widget>[
                      const SizedBox(height: AppTokens.spaceXs),
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.subtitles_off_rounded,
                            size: 14,
                            color: scheme.error,
                          ),
                          const SizedBox(width: AppTokens.spaceXs),
                          Expanded(
                            child: Text(
                              l10n.mediaServerPgsSubtitleWarn,
                              style: textTheme.labelSmall
                                  ?.copyWith(color: scheme.error),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 详情加载骨架（MD3 微光占位）：大图头同构 + 文本行。
class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: const <Widget>[
        SizedBox(height: 220, width: double.infinity, child: AppShimmer()),
        Padding(
          padding: EdgeInsets.all(AppTokens.spaceMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AppShimmer(width: 180, height: 22, phase: 0.2),
              SizedBox(height: AppTokens.spaceSm),
              AppShimmer(width: 120, height: 14, phase: 0.35),
              SizedBox(height: AppTokens.spaceLg),
              AppShimmer(height: 44, borderRadius: AppTokens.radiusSm, phase: 0.5),
              SizedBox(height: AppTokens.spaceMd),
              AppShimmer(height: 14, phase: 0.65),
              SizedBox(height: AppTokens.spaceSm),
              AppShimmer(height: 14, width: 260, phase: 0.8),
            ],
          ),
        ),
      ],
    );
  }
}
