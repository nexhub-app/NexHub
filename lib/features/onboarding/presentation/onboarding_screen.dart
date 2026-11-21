/// 首次启动引导页：
/// 1. 欢迎
/// 2. 基础设置（主题模式 / 主题色预览 / 语言）
/// 3. 添加源
/// 4. 关联 Bangumi
/// 5. 授予权限（Android 逐项授权）+ 下载位置
/// 6. 免责声明（必须勾选同意才能开始使用）
///
/// 设计取向：只保留「真正需要配置」的步骤——弹弹play、隐私说明等纯介绍性
/// 页面已移除；主题/语言选择采用紧凑单选行，小屏不溢出；主题色带实时预览；
/// 下载位置与权限放在同一页，首次启动即可确认下载目录，无需再四处找设置。
/// 页面在小屏（手机）上自动紧凑排布并整体可滚动。
///
/// 免责声明固定在最后一页：未勾选同意时「开始使用」置灰，「跳过」也会被带到
/// 该页并提示，确保首次使用一定看过声明。
///
/// 走完（点「开始使用」或「跳过」）后回调 [onDone]，由调用方写入
/// `GeneralSettings.onboardingCompleted = true` 并切换到主界面。
/// 页面所需的 Provider（[ThemeController] / [LocaleController] / [BangumiAuth] /
/// [DownloadManager]）由上层 MultiProvider 注入，可直接取用。
library;

import 'dart:isolate' show Isolate;

import 'package:file_picker/file_picker.dart' hide FilePickerWindows;
import 'package:file_picker/src/windows/file_picker_windows.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:nexhub/core/local/import_permission.dart';
import 'package:nexhub/core/platform/platform_service.dart';
import 'package:nexhub/core/services/bangumi/bangumi_auth.dart';
import 'package:nexhub/core/theme/app_tokens.dart';
import 'package:nexhub/core/theme/theme_controller.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:nexhub/core/locale/locale_controller.dart';
import 'package:nexhub/core/download/download_file_system.dart'
    show defaultDownloadPath, resolveDownloadPath;
import 'package:nexhub/core/download/download_manager.dart';
import 'package:nexhub/core/download/download_settings.dart';
import 'package:nexhub/core/platform/ohos_public_storage.dart' show isOhosDocPath;
import 'package:nexhub/core/platform/ohos_storage_location_sheet.dart';
import 'package:nexhub/core/utils/app_haptics.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:saf/saf.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;

  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _page = 0;
  final Map<Permission, bool> _grantedStatus = <Permission, bool>{};
  bool _statusRefreshed = false;

  /// 免责声明是否已勾选同意；未勾选时无法走完引导。
  bool _disclaimerAgreed = false;

  void _goNext() {
    AppHaptics.selectionClick();
    if (_page < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      return;
    }
    if (!_disclaimerAgreed) {
      _showDisclaimerHint();
      return;
    }
    widget.onDone();
  }

  /// 跳过：未同意免责声明时先跳到声明页并提示，不让用户绕过。
  void _skip() {
    AppHaptics.light();
    if (_disclaimerAgreed) {
      widget.onDone();
      return;
    }
    final int lastPage = _totalPages - 1;
    if (_page != lastPage) {
      _pageController.animateToPage(
        lastPage,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
    _showDisclaimerHint();
  }

  void _showDisclaimerHint() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).onboardingDisclaimerRequired,
          ),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 刷新各权限的当前授予状态。
  Future<void> _refreshGranted() async {
    final models = _permissionModels(AppLocalizations.of(context));
    for (final m in models) {
      try {
        _grantedStatus[m.permission] = (await m.permission.status).isGranted;
      } catch (_) {
        _grantedStatus[m.permission] = false;
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _grantOne(Permission permission) async {
    AppHaptics.light();
    try {
      final PermissionStatus status = await permission.request();
      if (mounted)
        setState(() => _grantedStatus[permission] = status.isGranted);
    } catch (_) {
      // 忽略：个别 ROM 权限请求异常时保持未授权状态。
    }
  }

  /// 权限明细模型（名称/描述/图标/平台权限）。
  List<_PermissionEntry> _permissionModels(AppLocalizations l10n) =>
      <_PermissionEntry>[
        _PermissionEntry(
          title: l10n.onboardingPermissionStorage,
          desc: l10n.onboardingPermissionStorageDesc,
          icon: Icons.folder_rounded,
          permission: Permission.storage,
        ),
        _PermissionEntry(
          title: l10n.onboardingPermissionPhotos,
          desc: l10n.onboardingPermissionPhotosDesc,
          icon: Icons.photo_rounded,
          permission: Permission.photos,
        ),
        _PermissionEntry(
          title: l10n.onboardingPermissionVideos,
          desc: l10n.onboardingPermissionVideosDesc,
          icon: Icons.videocam_rounded,
          permission: Permission.videos,
        ),
        _PermissionEntry(
          title: l10n.onboardingPermissionAudio,
          desc: l10n.onboardingPermissionAudioDesc,
          icon: Icons.audiotrack_rounded,
          permission: Permission.audio,
        ),
      ];

  int get _totalPages =>
      _buildPages(AppLocalizations.of(context), context).length;

  List<_OnboardingPageData> _buildPages(
    AppLocalizations l10n,
    BuildContext context,
  ) {
    return <_OnboardingPageData>[
      _OnboardingPageData(
        icon: Icons.rocket_launch_rounded,
        title: l10n.onboardingWelcomeTitle,
        body: l10n.onboardingWelcomeBody,
      ),
      _OnboardingPageData(
        icon: Icons.tune_rounded,
        title: l10n.onboardingSettingsTitle,
        body: l10n.onboardingSettingsBody,
        customBody: _buildSettingsBody(context, l10n),
      ),
      _OnboardingPageData(
        icon: Icons.extension_rounded,
        title: l10n.onboardingSourcesTitle,
        body: l10n.onboardingSourcesBody,
      ),
      _OnboardingPageData(
        icon: Icons.sync_rounded,
        title: l10n.onboardingBangumiTitle,
        body: l10n.onboardingBangumiBody,
        action: (ctx, loc) => FilledButton.icon(
          onPressed: () {
            AppHaptics.selectionClick();
            // 引导页中直接发起 Bangumi 登录；失败不阻断引导。
            try {
              ctx.read<BangumiAuth>().loginWithOAuth(ctx);
            } catch (_) {
              // 忽略：用户可在设置页稍后登录。
            }
          },
          icon: const Icon(Icons.login_rounded),
          label: Text(loc.onboardingBangumiLogin),
        ),
      ),
      _OnboardingPageData(
        icon: Icons.security_rounded,
        title: l10n.onboardingPermissionTitle,
        body: l10n.onboardingPermissionBody,
        customBody: _buildPermissionBody(context, l10n),
      ),
      _OnboardingPageData(
        icon: Icons.verified_user_rounded,
        title: l10n.onboardingDisclaimerTitle,
        body: l10n.onboardingDisclaimerBody,
        customBody: _buildDisclaimerBody(context, l10n),
      ),
    ];
  }

  // ── 免责声明页（要点列表 + 勾选同意）────────────────────────────────
  Widget _buildDisclaimerBody(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final points = <String>[
      l10n.onboardingDisclaimerPoint1,
      l10n.onboardingDisclaimerPoint2,
      l10n.onboardingDisclaimerPoint3,
      l10n.onboardingDisclaimerPoint4,
      l10n.onboardingDisclaimerPoint5,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(AppTokens.spaceMd),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (int i = 0; i < points.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: i == points.length - 1 ? 0 : AppTokens.spaceSm,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: textTheme.labelSmall?.copyWith(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppTokens.spaceSm),
                      Expanded(
                        child: Text(
                          points[i],
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.spaceXs),
        CheckboxListTile(
          value: _disclaimerAgreed,
          onChanged: (bool? v) {
            AppHaptics.selectionClick();
            setState(() => _disclaimerAgreed = v ?? false);
          },
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          visualDensity: VisualDensity.compact,
          title: Text(
            l10n.onboardingDisclaimerAgree,
            style: textTheme.bodyMedium,
          ),
        ),
        if (!_disclaimerAgreed)
          Padding(
            padding: const EdgeInsets.only(left: AppTokens.spaceXs),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppTokens.spaceXs),
                Expanded(
                  child: Text(
                    l10n.onboardingDisclaimerRequired,
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final pages = _buildPages(l10n, context);
    final isLast = _page == pages.length - 1;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: <Widget>[
          TextButton(
            onPressed: _skip,
            child: Text(l10n.onboardingSkip),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: Column(
          children: <Widget>[
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) =>
                    _buildPage(context, pages[i], l10n),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTokens.spaceLg),
              child: Row(
                children: <Widget>[
                  // 进度圆点
                  Row(
                    children: <Widget>[
                      for (int i = 0; i < pages.length; i++)
                        Container(
                          margin:
                              const EdgeInsets.only(right: AppTokens.spaceXs),
                          width: i == _page ? 22 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == _page
                                ? scheme.primary
                                : scheme.outlineVariant,
                            borderRadius:
                                BorderRadius.circular(AppTokens.radiusFull),
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed:
                        isLast && !_disclaimerAgreed ? null : _goNext,
                    child: Text(isLast
                        ? l10n.onboardingGetStarted
                        : l10n.onboardingNext),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 基础设置页（主题模式 / 主题色预览 / 语言 / 下载位置）──────────────

  Widget _buildSettingsBody(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final themeController = context.read<ThemeController>();
    final localeController = context.read<LocaleController>();
    final labelStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(l10n.onboardingThemeLabel, style: labelStyle),
        const SizedBox(height: AppTokens.spaceSm),
        _OnboardingChoiceRow<ThemeMode>(
          options: <_ChoiceOption<ThemeMode>>[
            _ChoiceOption<ThemeMode>(
              value: ThemeMode.system,
              label: l10n.themeSystem,
              icon: Icons.brightness_auto_rounded,
            ),
            _ChoiceOption<ThemeMode>(
              value: ThemeMode.light,
              label: l10n.themeLight,
              icon: Icons.light_mode_rounded,
            ),
            _ChoiceOption<ThemeMode>(
              value: ThemeMode.dark,
              label: l10n.themeDark,
              icon: Icons.dark_mode_rounded,
            ),
          ],
          selected: themeController.mode,
          onSelected: (ThemeMode m) {
            AppHaptics.selectionClick();
            themeController.setMode(m);
            setState(() {});
          },
        ),
        const SizedBox(height: AppTokens.spaceLg),

        // 主题色（预设种子色，点击即时生效并预览）
        Text(l10n.onboardingThemeColorLabel, style: labelStyle),
        const SizedBox(height: AppTokens.spaceSm),
        Wrap(
          spacing: AppTokens.spaceMd,
          runSpacing: AppTokens.spaceMd,
          children: <Widget>[
            for (final (Color color, String name) in AppTokens.presetSeeds)
              _SeedDot(
                color: color,
                name: name,
                selected: !themeController.useMonet &&
                    themeController.seed.toARGB32() == color.toARGB32(),
                onTap: () {
                  AppHaptics.selectionClick();
                  themeController.setSeed(color);
                  setState(() {});
                },
              ),
          ],
        ),
        const SizedBox(height: AppTokens.spaceLg),

        // 样式预览：随主题模式 / 主色实时变化
        Text(l10n.onboardingThemePreviewLabel, style: labelStyle),
        const SizedBox(height: AppTokens.spaceSm),
        _ThemePreview(theme: Theme.of(context)),
        const SizedBox(height: AppTokens.spaceLg),

        Text(l10n.onboardingLanguageLabel, style: labelStyle),
        const SizedBox(height: AppTokens.spaceSm),
        _OnboardingChoiceRow<LocaleOption>(
          options: <_ChoiceOption<LocaleOption>>[
            _ChoiceOption<LocaleOption>(
              value: LocaleOption.system,
              label: l10n.languageFollowSystem,
            ),
            _ChoiceOption<LocaleOption>(
              value: LocaleOption.chinese,
              label: l10n.languageChinese,
            ),
            _ChoiceOption<LocaleOption>(
              value: LocaleOption.english,
              label: l10n.languageEnglish,
            ),
          ],
          selected: localeController.option,
          onSelected: (LocaleOption o) {
            AppHaptics.selectionClick();
            localeController.setOption(o);
            setState(() {});
          },
        ),
      ],
    );
  }

  Widget _buildPermissionBody(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final models = _permissionModels(l10n);
    final bool anyGranted =
        models.any((m) => _grantedStatus[m.permission] == true);

    // 首次进入权限页时刷新各项授予状态（postFrame 保证 l10n/树就绪）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_statusRefreshed) {
        _statusRefreshed = true;
        _refreshGranted();
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (PlatformService.instance.isAndroid) ...<Widget>[
          // 权限细分：每项可单独授予
          FilledButton.icon(
            onPressed: anyGranted
                ? null
                : () {
                    AppHaptics.light();
                    requestLocalImportPermission();
                    _refreshGranted();
                  },
            icon: Icon(anyGranted
                ? Icons.check_circle_rounded
                : Icons.lock_open_rounded),
            label: Text(l10n.onboardingGrantPermission),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          for (final m in models)
            _PermissionRow(
              title: m.title,
              desc: m.desc,
              icon: m.icon,
              granted: _grantedStatus[m.permission] == true,
              l10n: l10n,
              onTap: () => _grantOne(m.permission),
            ),
        ] else ...<Widget>[
          // 桌面 / 其他平台：无需运行时权限。
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.spaceMd),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.check_circle_rounded, color: scheme.primary),
                const SizedBox(width: AppTokens.spaceSm),
                Flexible(
                  child: Text(
                    l10n.onboardingPermissionNotNeeded,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ],

        // 下载位置（两种平台都提供，避免首次找不到下载目录）。
        const SizedBox(height: AppTokens.spaceMd),
        Text(
          l10n.onboardingDownloadTitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: AppTokens.spaceXs),
        Text(
          l10n.onboardingDownloadBody,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: AppTokens.spaceSm),
        _DownloadPathSection(context: context, l10n: l10n),
      ],
    );
  }

  Widget _buildPage(
    BuildContext context,
    _OnboardingPageData data,
    AppLocalizations l10n,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        // 手机（窄屏）紧凑模式：图标与间距适度缩小，避免挤压。
        final bool compact = constraints.maxWidth < 400;
        const double iconSize = 96;
        final double icon = compact ? 72 : iconSize;
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceXl,
                vertical: AppTokens.spaceLg,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Container(
                    width: icon,
                    height: icon,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                    ),
                    child: Icon(
                      data.icon,
                      size: icon * 0.5,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: AppTokens.spaceLg),
                  Text(
                    data.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: compact ? 20 : null,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  if (data.body.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppTokens.spaceMd),
                    Text(
                      data.body,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (data.customBody != null) ...<Widget>[
                    const SizedBox(height: AppTokens.spaceLg),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: data.customBody!,
                    ),
                  ],
                  if (data.action != null) ...<Widget>[
                    const SizedBox(height: AppTokens.spaceLg),
                    data.action!(context, l10n),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 下载目录选择：Android 走 SAF 树目录；桌面走系统目录选择器（后台 isolate）。
class _DownloadPathSection extends StatefulWidget {
  final BuildContext context;
  final AppLocalizations l10n;

  const _DownloadPathSection({required this.context, required this.l10n});

  @override
  State<_DownloadPathSection> createState() => _DownloadPathSectionState();
}

class _DownloadPathSectionState extends State<_DownloadPathSection> {
  final Saf _saf = Saf();

  Future<void> _pick() async {
    final l10n = widget.l10n;
    if (PlatformService.instance.isOHOS) {
      final String? picked = await showOhosStorageLocationSheet(
        context,
        title: l10n.downloadPath,
        appPrivateLabel: l10n.storageLocationAppPrivate,
        appPrivateHint: l10n.storageLocationAppPrivateHint,
        systemLabel: l10n.storageLocationSystemDownloads,
        systemHint: l10n.storageLocationSystemDownloadsHint,
        systemSelected: isOhosDocPath(
          (await DownloadSettingsStore().load()).downloadPath,
        ),
      );
      if (picked == null || !mounted) return;
      await _save(
        picked.isEmpty ? await defaultDownloadPath() : picked,
        l10n,
      );
      return;
    }
    if (PlatformService.instance.isAndroid) {
      final SafDocumentFile? picked = await _saf.pickDirectory();
      if (picked == null || !mounted) return;
      await _save(picked.uri, l10n);
      return;
    }
    if (!kIsWeb) {
      String? result;
      try {
        result = await Isolate.run<String?>(() {
          FilePicker.platform = FilePickerWindows();
          return FilePicker.platform.getDirectoryPath();
        });
      } catch (_) {
        result = await Isolate.run<String?>(() {
          FilePicker.platform = FilePickerWindows();
          return FilePicker.platform.getDirectoryPath();
        });
      }
      if (result == null || !mounted) return;
      await _save(result, l10n);
    }
  }

  Future<void> _save(String path, AppLocalizations l10n) async {
    if (!mounted) return;
    try {
      await context.read<DownloadManager>().setDownloadBasePath(path);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.downloadPathSet)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.importFailed(e.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<String>(
      future: DownloadSettingsStore()
          .load()
          .then((s) => resolveDownloadPath(s.downloadPath)),
      builder: (context, snap) {
        final String path = snap.data ?? '';
        final String shown = path.startsWith('content://')
            ? Uri.parse(path).pathSegments.isNotEmpty
                ? Uri.decodeComponent(Uri.parse(path).pathSegments.last)
                : path
            : isOhosDocPath(path)
                ? widget.l10n.storageLocationSystemDownloads
                : path;
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceMd,
            vertical: AppTokens.spaceXs,
          ),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.folder_rounded,
                  size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppTokens.spaceSm),
              Expanded(
                child: Text(
                  shown.isEmpty ? path : shown,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
              TextButton(
                onPressed: () {
                  AppHaptics.light();
                  _pick();
                },
                child: Text(widget.l10n.onboardingChooseDownloadPath),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 主题实时预览：按当前主题渲染迷你「界面」，所见即所得。
class _ThemePreview extends StatelessWidget {
  final ThemeData theme;

  const _ThemePreview({required this.theme});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 模拟状态栏 / AppBar
          Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                ),
                child: Icon(Icons.play_arrow_rounded,
                    size: 18, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              Text(
                'NexHub',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Icon(Icons.more_vert_rounded,
                  size: 18, color: scheme.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: AppTokens.spaceMd),
          // 主色卡片
          Container(
            padding: const EdgeInsets.all(AppTokens.spaceSm),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.check_circle_rounded,
                    size: 16, color: scheme.primary),
                const SizedBox(width: AppTokens.spaceXs),
                Expanded(
                  child: Text(
                    'Primary · ${scheme.primary.toARGB32().toRadixString(16).padLeft(8, '0')}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          Row(
            children: <Widget>[
              Expanded(
                child: Container(
                  height: 22,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(AppTokens.radiusXs),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: 0.5,
                      child: Container(
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusXs),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.spaceMd),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceMd,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(AppTokens.radiusFull),
                ),
                child: Text(
                  'Button',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 主题色种子选择圆点。
class _SeedDot extends StatelessWidget {
  final Color color;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  const _SeedDot({
    required this.color,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: name,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radiusFull),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? scheme.onSurface : scheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          child: selected
              ? Icon(Icons.check_rounded, size: 18, color: scheme.onPrimary)
              : null,
        ),
      ),
    );
  }
}

/// 紧凑单选行：三个等宽选项在一行内均分（替代较宽的 SegmentedButton，
/// 小屏手机上不会超出屏幕宽度）。
class _OnboardingChoiceRow<T> extends StatelessWidget {
  final List<_ChoiceOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  const _OnboardingChoiceRow({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: <Widget>[
        for (int i = 0; i < options.length; i++) ...<Widget>[
          Expanded(
            child: ChoiceChip(
              avatar: options[i].icon == null
                  ? null
                  : Icon(options[i].icon, size: 16),
              label: Text(
                options[i].label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium,
              ),
              selected: options[i].value == selected,
              showCheckmark: false,
              onSelected: (bool sel) {
                if (sel) onSelected(options[i].value);
              },
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(vertical: 4),
              selectedColor: scheme.primaryContainer,
              labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
          if (i < options.length - 1) const SizedBox(width: AppTokens.spaceSm),
        ],
      ],
    );
  }
}

class _ChoiceOption<T> {
  final T value;
  final String label;
  final IconData? icon;

  const _ChoiceOption({required this.value, required this.label, this.icon});
}

/// 权限细分行：单条权限的授予状态与单独授权。
class _PermissionRow extends StatelessWidget {
  final String title;
  final String desc;
  final IconData icon;
  final bool granted;
  final AppLocalizations l10n;
  final VoidCallback onTap;

  const _PermissionRow({
    required this.title,
    required this.desc,
    required this.icon,
    required this.granted,
    required this.l10n,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: scheme.primary, size: 22),
        title: Text(title, style: Theme.of(context).textTheme.bodyLarge),
        subtitle: Text(
          desc,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        trailing: granted
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.check_circle_rounded,
                      size: 18, color: scheme.primary),
                  const SizedBox(width: AppTokens.spaceXs),
                  Text(
                    l10n.onboardingPermissionItemGranted,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                        ),
                  ),
                ],
              )
            : TextButton(
                onPressed: onTap,
                child: Text(l10n.onboardingPermissionItemDenied),
              ),
      ),
    );
  }
}

class _PermissionEntry {
  final String title;
  final String desc;
  final IconData icon;
  final Permission permission;

  const _PermissionEntry({
    required this.title,
    required this.desc,
    required this.icon,
    required this.permission,
  });
}

class _OnboardingPageData {
  final IconData icon;
  final String title;
  final String body;
  final Widget? customBody;
  final Widget Function(BuildContext, AppLocalizations)? action;

  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.body,
    this.customBody,
    this.action,
  });
}
