/// RSS 文章附件中的播客音频播放器（-3）。
///
/// 复用应用既有 media_kit 内核（`Player`，音频无需 `VideoController`），
/// 仅为音频类 [RssEnclosure] 提供播放/暂停/进度/切换控件。
/// 多条音频附件时以芯片条切换；视频附件走独立播放器、其余（文件）由详情页
/// 以「打开附件」链接处理，不在此控件内。
///
/// 失败兜底（此前的问题：`Player.open()` 失败被静默吞掉，UI 停在 0:00，
/// 用户只看到「点了播放没反应」，分不清是源挂了还是应用坏了）：
/// - 监听 `Player.stream.error` → 内核报错立即反映到 UI；
/// - 打开后 20s 内时长仍为 0 且未起播 → 也判定失败。防盗链、302 到不支持的
/// 地址、冷门编码等情况都不会抛 error，只表现为「无声无息的 0」；
/// - 失败态给出两条出路：重试、用外部应用打开（交给系统浏览器/播放器）。
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/media/media_kit_network.dart';
import '../../../core/player/player_runtime.dart';
import '../../../core/rss/rss_feed.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/app_haptics.dart';

/// 文章内的播客音频播放控件。
class RssPodcastPlayer extends StatefulWidget {
  final List<RssEnclosure> enclosures;

  /// 文章页地址：作为 Referer 注入音频请求头，绕过防盗链（否则媒体内核
  /// 直连常被 403 / 永远 0:00）。
  final String? pageUrl;

  const RssPodcastPlayer({super.key, required this.enclosures, this.pageUrl});

  @override
  State<RssPodcastPlayer> createState() => _RssPodcastPlayerState();
}

class _RssPodcastPlayerState extends State<RssPodcastPlayer> {
  /// 判定「加载失败」的兜底时限：超过它而时长仍为 0 且未起播即视为失败。
  static const Duration _loadTimeout = Duration(seconds: 20);

  late final Player _player;
  bool _playerReady = false;
  int _index = 0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = false;
  bool _failed = false;

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<String>? _errorSub;
  Timer? _loadTimer;

  /// 仅取音频类附件（MIME / 后缀判定见 [RssEnclosure.isAudio]）。
  List<RssEnclosure> get _audio =>
      widget.enclosures.where((RssEnclosure e) => e.isAudio).toList();

  RssEnclosure get _current => _audio[_index.clamp(0, _audio.length - 1)];

  @override
  void initState() {
    super.initState();
    // 幂等：main 已调用过，重复调用安全（鸿蒙侧自动跳过）。
    PlayerRuntime.ensureInitialized();
    // 鸿蒙内核默认随包可用；用户显式关内核（NEXHUB_OHOS_PLAYER=false）时
    // 创建会抛错，转失败态展示（复用既有 _failed UI）。
    try {
      _player = Player();
      _playerReady = true;
    } on Object {
      _failed = true;
      return;
    }
    // libmpv 自主联网不吃应用代理，须显式注入（否则代理环境音频永远 0:00）。
    applyAppProxyToPlayer(_player);
    _posSub = _player.stream.position.listen((Duration d) {
      if (mounted) setState(() => _position = d);
    });
    _durSub = _player.stream.duration.listen((Duration d) {
      if (!mounted) return;
      // 拿到有效时长即证明媒体可读，撤销失败态与超时计时。
      if (d > Duration.zero) _clearFailure();
      setState(() => _duration = d);
    });
    _playingSub = _player.stream.playing.listen((bool p) {
      if (!mounted) return;
      if (p) _clearFailure();
      setState(() => _playing = p);
    });
    _bufferingSub = _player.stream.buffering.listen((bool b) {
      if (mounted) setState(() => _buffering = b);
    });
    _completedSub = _player.stream.completed.listen((bool c) {
      if (c && mounted) setState(() => _playing = false);
    });
    // 内核报错（解码失败 / 网络被拒 / 协议不支持）立即反映到 UI。
    _errorSub = _player.stream.error.listen((String message) {
      if (!mounted) return;
      _loadTimer?.cancel();
      _loadTimer = null;
      setState(() => _failed = true);
    });
    _openCurrent();
  }

  /// 撤销失败态并停掉超时计时（媒体已成功读取时调用）。
  ///
  /// 只改标志不 [setState]：调用方本就在同一次 setState 流程里，避免嵌套。
  void _clearFailure() {
    _loadTimer?.cancel();
    _loadTimer = null;
    _failed = false;
  }

  void _openCurrent() {
    final List<RssEnclosure> list = _audio;
    if (list.isEmpty) return;
    setState(() {
      _failed = false;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    // 代理注入 + 防盗链头一起上：缺代理则代理环境连不上，缺 Referer/UA 则
    // 防盗链源拒之门外，两者表现都是无声无息的 0:00。
    applyAppProxyToPlayer(_player);
    _player.open(
      Media(
        _current.url,
        httpHeaders: buildMediaHeaders(
          pageUrl: widget.pageUrl,
          mediaUrl: _current.url,
        ),
      ),
      play: false,
    );
    // 兜底计时：部分失败不抛 error，只是永远停在 0 进度——到点仍未拿到时长
    // 且未起播就按失败处理，避免用户对着 0:00 干等。
    _loadTimer?.cancel();
    _loadTimer = Timer(_loadTimeout, () {
      if (!mounted) return;
      if (_duration > Duration.zero || _playing) return;
      setState(() => _failed = true);
    });
  }

  void _select(int i) {
    if (i == _index) return;
    setState(() => _index = i);
    _openCurrent();
  }

  void _togglePlay() {
    if (_playing) {
      _player.pause();
    } else {
      _player.play();
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// 外链兜底：内置内核播不了时交给系统（浏览器 / 外部播放器）。
  Future<void> _openExternally(BuildContext context, String url) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return;
    final AppLocalizations? l10n = AppLocalizations.of(context);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      if (context.mounted && l10n != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.loadFailed)),
        );
      }
    }
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    _loadTimer = null;
    _posSub?.cancel();
    _durSub?.cancel();
    _playingSub?.cancel();
    _bufferingSub?.cancel();
    _completedSub?.cancel();
    _errorSub?.cancel();
    if (_playerReady) _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<RssEnclosure> list = _audio;
    if (list.isEmpty) return const SizedBox.shrink();

    final ColorScheme scheme = Theme.of(context).colorScheme;
    final RssEnclosure current = _current;

    return Card(
      margin: const EdgeInsets.only(top: AppTokens.spaceMd),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.podcasts_rounded, color: scheme.primary),
                const SizedBox(width: AppTokens.spaceSm),
                Expanded(
                  child: Text(
                    current.title ?? current.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            if (list.length > 1) ...<Widget>[
              const SizedBox(height: AppTokens.spaceSm),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    for (int i = 0; i < list.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: AppTokens.spaceXs),
                        child: ChoiceChip(
                          label: Text(list[i].title ?? '音频 ${i + 1}'),
                          selected: i == _index,
                          onSelected: (_) => _select(i),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppTokens.spaceSm),
            Row(
              children: <Widget>[
                IconButton(
                  icon: _buffering
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(_playing
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded),
                  iconSize: 36,
                  color: scheme.primary,
                  onPressed: _togglePlay,
                ),
                Expanded(
                  child: Column(
                    children: <Widget>[
                      Slider(
                        value: _duration.inSeconds > 0
                            ? _position.inSeconds
                                .clamp(0, _duration.inSeconds)
                                .toDouble()
                            : 0,
                        max: _duration.inSeconds > 0
                            ? _duration.inSeconds.toDouble()
                            : 1,
                        onChangeStart: (_) => AppHaptics.light(),
                        onChanged: (double v) =>
                            _player.seek(Duration(seconds: v.toInt())),
                      ),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(_fmt(_position),
                                style: Theme.of(context).textTheme.labelSmall),
                            Text(_fmt(_duration),
                                style: Theme.of(context).textTheme.labelSmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_failed) ...<Widget>[
              const SizedBox(height: AppTokens.spaceSm),
              _buildFailureRow(context, scheme),
            ],
          ],
        ),
      ),
    );
  }

  /// 失败提示行：说明 + 重试 + 外部打开。
  ///
  /// 播不了必须给出口，否则用户只看到 0:00 却无从判断是源的问题还是应用的
  /// 问题——外链按钮至少保证「换条路也能听」。
  Widget _buildFailureRow(BuildContext context, ColorScheme scheme) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.spaceSm),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.error_rounded, size: 18, color: scheme.error),
              const SizedBox(width: AppTokens.spaceXs),
              Expanded(
                child: Text(
                  l10n.rssAudioFailed,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              TextButton.icon(
                onPressed: _openCurrent,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(l10n.retry),
              ),
              const SizedBox(width: AppTokens.spaceXs),
              TextButton.icon(
                onPressed: () => _openExternally(context, _current.url),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(l10n.rssOpenExternally),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
