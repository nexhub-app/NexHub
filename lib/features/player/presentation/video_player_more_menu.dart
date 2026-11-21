part of 'video_player_screen.dart';

/// 更多菜单声明式条目。
///
/// 菜单项不再是命令式堆叠的 [ListTile]，而是带显隐谓词的数据描述：
/// - [requiresCapability]：内核能力要求（`PlayerCapability`），后端不支持时隐藏，
/// 适配多内核 / 平台降级（NoOp、Web 无 mpv 属性能力）；
/// - [visibilityPredicate]：与能力无关的运行时显隐条件（如直链模式无下一集）。
/// 渲染前统一过滤，交互逻辑（开关 / 下拉 / 弹层）保留在 [builder] 内。
class _PlayerMenuEntry {
  const _PlayerMenuEntry({
    required this.builder,
    this.requiresCapability,
    this.visibilityPredicate,
    this.dividerBefore = false,
  });

  /// 构建条目 UI（入参为弹层的 BuildContext，用于 pop 关闭）。
  final Widget Function(BuildContext ctx) builder;

  /// 需要的内核能力；null 表示不依赖 mpv 属性系能力。
  final PlayerCapability? requiresCapability;

  /// 额外显隐条件；null 表示始终可见。
  final bool Function()? visibilityPredicate;

  /// 是否在本条目前插入分隔线（播放队列分组）。
  final bool dividerBefore;
}

extension _VideoMoreMenu on _VideoPlayerScreenState {
  void _showMoreMenu(AppLocalizations l10n) {
    // 菜单打开期间持有控制栏，禁止自动隐藏；关闭后释放。
    _acquirePanelHold();
    // 按内核能力 + 运行时条件过滤声明式条目。
    final capabilities = _controller.backend.capabilities;
    bool visible(_PlayerMenuEntry e) =>
        (e.requiresCapability == null ||
            capabilities.contains(e.requiresCapability)) &&
        (e.visibilityPredicate?.call() ?? true);
    final List<_PlayerMenuEntry> entries =
        _buildMoreMenuEntries(l10n).where(visible).toList(growable: false);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _menuHeader(l10n),
                // 条目 leading 图标统一 primary（与 SettingsTile 约定一致）。
                IconTheme.merge(
                  data: IconThemeData(
                    color: Theme.of(ctx).colorScheme.primary,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (final _PlayerMenuEntry entry in entries) ...<Widget>[
                        if (entry.dividerBefore) const Divider(height: 1),
                        entry.builder(ctx),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppTokens.spaceSm),
              ],
            ),
          ),
        ),
      ),
    )
        // 菜单关闭后释放控制栏租约，重启自动隐藏倒计时。
        .whenComplete(_releasePanelHold);
  }

  /// 构建全部菜单条目（未过滤，渲染时按能力 / 条件显隐）。
  List<_PlayerMenuEntry> _buildMoreMenuEntries(AppLocalizations l10n) {
    final PluginConfig? callbackSource = _callbackSource;
    final bool shuyuanSource = callbackSource?.selectors?['xiaoshuo'] is Map;
    final bool hasCustomButton =
        callbackSource != null && shuyuanHasCustomButton(callbackSource);
    return <_PlayerMenuEntry>[
      // ── 书源事件（legado 视频播放器菜单）：复制播放地址 / 自定义按钮 ──
      _PlayerMenuEntry(
        visibilityPredicate: () => shuyuanSource,
        builder: (BuildContext ctx) => ListTile(
          leading: const Icon(Icons.link_rounded),
          title: Text(l10n.sourceCopyPlayUrl),
          onTap: () {
            Navigator.of(ctx).pop();
            unawaited(_copyPlayUrl());
          },
        ),
      ),
      _PlayerMenuEntry(
        visibilityPredicate: () => hasCustomButton,
        builder: (BuildContext ctx) => ListTile(
          leading: const Icon(Icons.extension_rounded),
          title: Text(l10n.sourceCustomButton),
          onTap: () {
            Navigator.of(ctx).pop();
            unawaited(_runCustomButton());
          },
        ),
      ),
      // ── 媒体服务器（仅该来源显示）：码率档位 + 音轨 ──
      _PlayerMenuEntry(
        visibilityPredicate: () => _isMediaServer,
        builder: (BuildContext ctx) => ListTile(
          leading: const Icon(Icons.speed_rounded),
          title: Text(l10n.mediaServerBitrateTier),
          subtitle: Text(
            _bitrateLabel(l10n, MediaServerPlaybackSettings.instance.tier),
          ),
          onTap: () => _pickServerBitrate(ctx, l10n),
        ),
      ),
      _PlayerMenuEntry(
        visibilityPredicate: () => _isMediaServer,
        builder: (BuildContext ctx) => ListTile(
          leading: const Icon(Icons.graphic_eq_rounded),
          title: Text(l10n.mediaServerAudioTrack),
          subtitle: Text(_currentAudioTrackSubtitle(l10n)),
          onTap: () => _pickServerAudioTrack(ctx, l10n),
        ),
      ),
      // 自动连播（本地 / 直链模式无下一集，隐藏）
      _PlayerMenuEntry(
        visibilityPredicate: () => !_isDirectMode,
        builder: (BuildContext ctx) => ListTile(
          leading: Icon(
            _controller.autoPlayNext
                ? Icons.play_circle_rounded
                : Icons.play_circle_rounded,
          ),
          title: Text(l10n.playerAutoPlayNext),
          trailing: Switch(
            value: _controller.autoPlayNext,
            onChanged: (v) {
              v == true ? AppHaptics.toggleOn() : AppHaptics.toggleOff();
              setState(() {
                _controller.autoPlayNext = v;
                _playerSettings = _playerSettings.copyWith(autoPlayNext: v);
              });
              unawaited(_saveEpisodeSetting('autoPlayNext', v));
              Navigator.pop(ctx);
            },
          ),
        ),
      ),
      // 功能5：长按手势设置（开关 + 自定义倍速值）
      _PlayerMenuEntry(
        builder: (BuildContext ctx) => ListTile(
          leading: Icon(_playerSettings.longPressSpeedUp
              ? Icons.fast_forward_rounded
              : Icons.fast_forward_rounded),
          title: Text(l10n.playerLongPressSpeedUp),
          trailing: Switch(
            value: _playerSettings.longPressSpeedUp,
            onChanged: (v) {
              v == true ? AppHaptics.toggleOn() : AppHaptics.toggleOff();
              setState(() {
                _playerSettings = _playerSettings.copyWith(longPressSpeedUp: v);
              });
              unawaited(_saveEpisodeSetting('longPressSpeedUp', v));
              Navigator.pop(ctx);
            },
          ),
        ),
      ),
      _PlayerMenuEntry(
        builder: (BuildContext ctx) => ListTile(
          leading: const Icon(Icons.speed_rounded),
          title: Text(l10n.playerLongPressSpeed),
          subtitle: Text('${_playerSettings.longPressSpeed}x'),
          enabled: _playerSettings.longPressSpeedUp,
          onTap: () {
            Navigator.pop(ctx);
            unawaited(_pickLongPressSpeed(context));
          },
        ),
      ),
      // 画中画（从顶栏移入更多菜单）。floating 社区版支持 Android + 鸿蒙
      // （鸿蒙可用性由插件运行时检测，不可用时点击提示降级）。
      _PlayerMenuEntry(
          builder: (BuildContext ctx) => ListTile(
            leading: const Icon(Icons.picture_in_picture_rounded),
            title: Text(l10n.playerPip),
            onTap: () {
              Navigator.pop(ctx);
              _togglePip(l10n);
            },
          ),
        ),
      // 解码模式（hwdec 属 mpv 属性系能力，Web / NoOp 后端隐藏）
      _PlayerMenuEntry(
        requiresCapability: PlayerCapability.hwdec,
        builder: (BuildContext ctx) => ListTile(
          leading: const Icon(Icons.memory_rounded),
          title: Text(l10n.playerDecodeMode),
          subtitle: Text(_hwdecLabel(l10n, _controller.currentHwdec)),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () {
            Navigator.pop(ctx);
            _showPlayerOptionSheet(
              l10n: l10n,
              title: l10n.playerDecodeMode,
              current: _controller.currentHwdec,
              options: <(String, String)>[
                ('auto', l10n.playerDecodeAuto),
                ('sw', l10n.playerDecodeSw),
                ('hw', l10n.playerDecodeHw),
                // hw+（auto-copy）绕开硬解直通纹理路径，是花屏设备的首选。
                (
                  'hw+',
                  '${l10n.playerDecodeHwPlus} · ${l10n.playerDecodeHwPlusHint}'
                ),
              ],
              onPick: (String v) {
                // 与自动降级一致：设完 hwdec 后必须 re-open，否则对已在播的
                // 解码器不生效（用户切“软解”看不到任何变化）。
                unawaited(_applyHwdecAndReopen(v));
                _playerSettings = _playerSettings.copyWith(
                  decodeMode: DecodeMode.values.firstWhere(
                    (e) => e.name == v || (e.name == 'hwPlus' && v == 'hw+'),
                    orElse: () => DecodeMode.auto,
                  ),
                );
                unawaited(_saveEpisodeSetting(
                  'decodeMode',
                  _playerSettings.decodeMode.name,
                ));
              },
            );
          },
        ),
      ),
      // 超分辨率 shader 档位（无清晰度源时提升观感）
      _PlayerMenuEntry(
        requiresCapability: PlayerCapability.upscaleShader,
        builder: (BuildContext ctx) => ListTile(
          leading: const Icon(Icons.auto_awesome_rounded),
          title: Text(l10n.playerUpscaleShader),
          subtitle: Text(_upscaleLabel(l10n, _playerSettings.upscaleShader)),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () {
            Navigator.pop(ctx);
            _showPlayerOptionSheet(
              l10n: l10n,
              title: l10n.playerUpscaleShader,
              current: _playerSettings.upscaleShader.name,
              options: <(String, String)>[
                ('off', l10n.playerUpscaleShaderOff),
                ('performance', l10n.playerUpscaleShaderPerformance),
                ('quality', l10n.playerUpscaleShaderQuality),
              ],
              onPick: (String v) {
                final mode = UpscaleShaderMode.values.firstWhere(
                  (e) => e.name == v,
                  orElse: () => UpscaleShaderMode.off,
                );
                // glsl-shaders 运行时替换，即时生效无需 re-open。
                unawaited(_controller.setUpscaleShader(mode));
                _playerSettings = _playerSettings.copyWith(upscaleShader: mode);
                unawaited(_saveEpisodeSetting('upscaleShader', mode.name));
              },
            );
          },
        ),
      ),
      // 音频通道
      _PlayerMenuEntry(
        requiresCapability: PlayerCapability.audioChannel,
        builder: (BuildContext ctx) => ListTile(
          leading: const Icon(Icons.graphic_eq_rounded),
          title: Text(l10n.playerAudioChannel),
          subtitle:
              Text(_audioChannelLabel(l10n, _controller.currentAudioChannel)),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () {
            Navigator.pop(ctx);
            _showPlayerOptionSheet(
              l10n: l10n,
              title: l10n.playerAudioChannel,
              current: _controller.currentAudioChannel,
              options: <(String, String)>[
                ('auto', l10n.playerDecodeAuto),
                ('auto-safe', l10n.playerAudioAutoProtect),
                ('stereo', l10n.playerAudioStereo),
                ('mono', l10n.playerAudioMono),
                ('reverse-stereo', l10n.playerAudioReverseStereo),
              ],
              onPick: (String v) {
                unawaited(_controller.setAudioChannel(v));
                _playerSettings = _playerSettings.copyWith(
                  audioChannel: AudioChannel.values.firstWhere(
                    (e) => e.name == v,
                    orElse: () => AudioChannel.auto,
                  ),
                );
                unawaited(_saveEpisodeSetting(
                  'audioChannel',
                  _playerSettings.audioChannel.name,
                ));
              },
            );
          },
        ),
      ),
      _PlayerMenuEntry(
        builder: (BuildContext ctx) => ListTile(
          leading: const Icon(Icons.bedtime_rounded),
          title: Text(l10n.playerTimer),
          onTap: () {
            Navigator.pop(ctx);
            _showSleepTimerPicker(l10n);
          },
        ),
      ),
      // #4 -#4: 媒体信息（mpv 只读属性查询）
      _PlayerMenuEntry(
        requiresCapability: PlayerCapability.propertyQuery,
        builder: (BuildContext ctx) => ListTile(
          leading: const Icon(Icons.info_rounded),
          title: Text(l10n.mediaInfo),
          onTap: () {
            Navigator.pop(ctx);
            _showMediaInfo(l10n);
          },
        ),
      ),
      // 播放统计（实际软/硬解状态、编码、掉帧等，1s 刷新）
      _PlayerMenuEntry(
        requiresCapability: PlayerCapability.propertyQuery,
        builder: (BuildContext ctx) => ListTile(
          leading: const Icon(Icons.query_stats_rounded),
          title: Text(l10n.playerStats),
          onTap: () {
            Navigator.pop(ctx);
            _showPlaybackStats(l10n);
          },
        ),
      ),
      // #4 -#4: 外部播放
      _PlayerMenuEntry(
        builder: (BuildContext ctx) => ListTile(
          leading: const Icon(Icons.open_in_new_rounded),
          title: Text(l10n.playExternal),
          onTap: () {
            Navigator.pop(ctx);
            _playInExternal(l10n);
          },
        ),
      ),
      // #4 -#4: 分享（复用 _share）
      _PlayerMenuEntry(
        builder: (BuildContext ctx) => ListTile(
          leading: const Icon(Icons.share_rounded),
          title: Text(l10n.share),
          onTap: () {
            Navigator.pop(ctx);
            _share(l10n);
          },
        ),
      ),
      // 截图保存路径设置。
      _PlayerMenuEntry(
        builder: (BuildContext ctx) => ListTile(
          leading: const Icon(Icons.folder_open_rounded),
          title: Text(l10n.screenshotPathSetting),
          subtitle: Text(
            _customScreenshotDir == null || _customScreenshotDir!.isEmpty
                ? l10n.screenshotPathDefault
                : (isOhosDocPath(_customScreenshotDir!)
                    ? l10n.storageLocationSystemScreenshots
                    : _customScreenshotDir!),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () {
            Navigator.pop(ctx);
            _pickScreenshotDirectory(l10n);
          },
        ),
      ),
      // 跳过片头/片尾设置
      _PlayerMenuEntry(
        builder: (BuildContext ctx) => ListTile(
          leading: const Icon(Icons.skip_next_rounded),
          title: Text(l10n.playerSkipOpEd),
          subtitle: (_skipOpEndSec != null || _skipEdStartSec != null)
              ? Text(
                  '${_fmtMmSs(_skipOpEndSec)} / ${_fmtMmSs(_skipEdStartSec)}'
                  '${_skipAuto ? ' · ${l10n.playerSkipAuto}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          onTap: () {
            Navigator.pop(ctx);
            unawaited(_showSkipSettings());
          },
        ),
      ),
      // 重置该视频的单独设置（恢复跟随全局默认）
      _PlayerMenuEntry(
        builder: (BuildContext ctx) => ListTile(
          leading: const Icon(Icons.settings_backup_restore_rounded),
          title: Text(l10n.playerResetEpisodeSettings),
          onTap: () {
            Navigator.pop(ctx);
            unawaited(_resetEpisodeSettings());
          },
        ),
      ),
      // ── 播放队列（跨作品）──
      _PlayerMenuEntry(
        dividerBefore: true,
        builder: (BuildContext ctx) => ListTile(
          leading: const Icon(Icons.playlist_add_rounded),
          title: Text(l10n.playerAddToQueue),
          onTap: () {
            Navigator.pop(ctx);
            unawaited(_addCurrentToQueue());
          },
        ),
      ),
      _PlayerMenuEntry(
        builder: (BuildContext ctx) => ListTile(
          leading: const Icon(Icons.playlist_play_rounded),
          title: Text(l10n.playerPlayNext),
          onTap: () {
            Navigator.pop(ctx);
            unawaited(_playCurrentNext());
          },
        ),
      ),
      _PlayerMenuEntry(
        builder: (BuildContext ctx) => ListTile(
          leading: const Icon(Icons.queue_music_rounded),
          title: Text(l10n.playerQueue),
          onTap: () {
            Navigator.pop(ctx);
            unawaited(_showQueueSheet(l10n));
          },
        ),
      ),
    ];
  }

  /// 与设置页「行 + 选中 check」弹层同款的播放器单选弹层。
  Future<void> _showPlayerOptionSheet({
    required AppLocalizations l10n,
    required String title,
    required String current,
    required List<(String, String)> options,
    required ValueChanged<String> onPick,
  }) async {
    // 弹层打开期间持有控制栏，禁止自动隐藏。
    _acquirePanelHold();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.spaceLg,
                    AppTokens.spaceMd,
                    AppTokens.spaceLg,
                    AppTokens.spaceSm,
                  ),
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                for (final (String value, String label) in options)
                  ListTile(
                    title: Text(label),
                    trailing: value == current
                        ? Icon(Icons.check_rounded,
                            color: Theme.of(ctx).colorScheme.primary)
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      onPick(value);
                    },
                  ),
                const SizedBox(height: AppTokens.spaceSm),
              ],
            ),
          ),
        ),
      ),
      // 弹层关闭后释放控制栏租约。
    ).whenComplete(_releasePanelHold);
  }

  String _hwdecLabel(AppLocalizations l10n, String v) => switch (v) {
        'sw' => l10n.playerDecodeSw,
        'hw' => l10n.playerDecodeHw,
        'hw+' => l10n.playerDecodeHwPlus,
        _ => l10n.playerDecodeAuto,
      };

  String _upscaleLabel(AppLocalizations l10n, UpscaleShaderMode m) =>
      switch (m) {
        UpscaleShaderMode.performance => l10n.playerUpscaleShaderPerformance,
        UpscaleShaderMode.quality => l10n.playerUpscaleShaderQuality,
        _ => l10n.playerUpscaleShaderOff,
      };

  String _audioChannelLabel(AppLocalizations l10n, String v) => switch (v) {
        'auto-safe' => l10n.playerAudioAutoProtect,
        'stereo' => l10n.playerAudioStereo,
        'mono' => l10n.playerAudioMono,
        'reverse-stereo' => l10n.playerAudioReverseStereo,
        _ => l10n.playerDecodeAuto,
      };

  Widget _menuHeader(AppLocalizations l10n) {
    return Padding(
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
              l10n.playerPlayInfo,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          // 投屏入口（打开设备选择面板）。
          IconButton(
            icon: Icon(Icons.cast_rounded,
                color:
                    _isCasting ? Theme.of(context).colorScheme.primary : null),
            tooltip: l10n.cast,
            onPressed: () {
              Navigator.pop(context);
              _showCastSheet(l10n);
            },
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}
