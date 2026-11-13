part of 'video_player_screen.dart';

extension _VideoScreenshot on _VideoPlayerScreenState {
  /// 抽出 [_takeScreenshot] 的核心实现，供边缘常驻按钮与「更多」菜单共用。
  ///
  /// 使用 media_kit 的 [Player.screenshot] 截取当前帧，
  /// 保存为 PNG 到截图目录（默认 Documents/screenshots 或用户自定义）。
  Future<void> _captureAndSaveScreenshot(AppLocalizations l10n) async {
    try {
      final Uint8List? bytes = await _controller.player.screenshot();
      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.screenshotFailed)),
          );
        }
        return;
      }
      final String fileName =
          'nexhub_${DateTime.now().millisecondsSinceEpoch}.png';
      final String? customDir = _customScreenshotDir;
      final String path;
      if (customDir != null &&
          customDir.isNotEmpty &&
          isOhosDocPath(customDir)) {
        // 鸿蒙公共目录（系统「下载」/Screenshots）：原生写入，返回编码路径
        // 供收藏/分享入口继续解析。
        final String encoded = ohosDocJoin(customDir, fileName);
        await OhosPublicStorage.writeBytes(
          ohosDocToPlainPath(encoded),
          bytes,
        );
        path = encoded;
      } else {
        final Directory baseDir;
        if (customDir != null && customDir.isNotEmpty) {
          baseDir = Directory(customDir);
          if (!await baseDir.exists()) {
            await baseDir.create(recursive: true);
          }
        } else {
          final docDir = await getApplicationDocumentsDirectory();
          baseDir = Directory(p.join(docDir.path, 'screenshots'));
          if (!await baseDir.exists()) {
            await baseDir.create(recursive: true);
          }
        }
        final File file = File(p.join(baseDir.path, fileName));
        await file.writeAsBytes(bytes);
        path = file.path;
      }
      if (mounted) {
        // 截图保存后提供「收藏到图库」快捷入口（统一图片收藏图库）。
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.screenshotSaved),
            action: SnackBarAction(
              label: l10n.imageFavoriteAdd,
              onPressed: () => unawaited(_favoriteScreenshot(path, l10n)),
            ),
          ),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.screenshotFailed}: $e')),
        );
      }
    }
  }

  /// 把刚保存的截图收藏进统一图片图库（来源 = 播放器）。
  Future<void> _favoriteScreenshot(String path, AppLocalizations l10n) async {
    final String label = _episodeTitle.isEmpty
        ? widget.title
        : '${widget.title} · $_episodeTitle';
    final bool added = await ImageFavoriteManager().toggleByUrl(
      source: ImageFavoriteSource.player,
      workId: widget.itemId,
      workTitle: widget.title,
      label: label,
      imageUrl: path,
    );
    // MD3「Toggle」：截图收藏开关切换 → tick。
    added ? AppHaptics.toggleOn() : AppHaptics.toggleOff();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added ? l10n.imageFavoriteAdded : l10n.imageFavoriteRemoved,
        ),
      ),
    );
  }

  /// 选择自定义截图保存目录。
  Future<void> _pickScreenshotDirectory(AppLocalizations l10n) async {
    try {
      String? selected;
      if (PlatformService.instance.isOHOS) {
        // 鸿蒙手机不能选任意文件夹：在应用私有目录与系统「下载」/Screenshots
        // 之间选择（后者一次授权持久有效）。
        selected = await showOhosStorageLocationSheet(
          context,
          title: l10n.screenshotPathSetting,
          appPrivateLabel: l10n.storageLocationAppPrivate,
          appPrivateHint: l10n.screenshotPathDefault,
          systemLabel: l10n.storageLocationSystemScreenshots,
          systemHint: l10n.storageLocationSystemScreenshotsHint,
          systemSelected: isOhosDocPath(_customScreenshotDir ?? ''),
          appendSubdir: 'Screenshots',
        );
      } else {
        selected = await FilePicker.platform.getDirectoryPath(
          dialogTitle: l10n.playerScreenshot,
        );
      }
      if (selected == null || !mounted) return;
      final String dir = selected;
      // 空串代表「应用私有默认目录」：清掉持久化键并回到默认。
      setState(() => _customScreenshotDir = dir.isEmpty ? null : dir);
      try {
        final prefs = await SharedPreferences.getInstance();
        if (dir.isEmpty) {
          await prefs.remove('screenshot_custom_dir');
        } else {
          await prefs.setString('screenshot_custom_dir', dir);
        }
      } on Object {
        // 写入失败不影响功能
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              dir.isEmpty
                  ? l10n.screenshotPathDefault
                  : (isOhosDocPath(dir)
                      ? l10n.storageLocationSystemScreenshots
                      : dir),
            ),
          ),
        );
      }
    } on Object {
      // 用户取消或平台不支持，静默忽略
    }
  }
}
