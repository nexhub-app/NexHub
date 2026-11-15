/// 下载管理设置页 —— 新版设计，所有设置持久化到 SharedPreferences。
///
/// 包含：下载列表/已下载入口、最大下载数、线程数、路径、下载器类型、格式设置。
/// 项 12/13：下载器选择 / 漫画格式 / 小说格式改为弹窗选择，移除子页入口。
library;

import 'dart:io' show Directory;
import 'dart:isolate' show Isolate;
// 用于在后台 isolate 里手动初始化 FilePicker.platform（late static 是
// isolate-private，主 isolate 的初始化不会传到新 isolate）。
// web 目标不构建本文件，可不加 if 分支。
import 'package:file_picker/file_picker.dart' hide FilePickerWindows;
import 'package:file_picker/src/windows/file_picker_windows.dart';
import 'package:saf/saf.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/download/download_format_preferences.dart';
import '../../../core/download/download_file_system.dart'
    show defaultDownloadPath, resolveDownloadPath;
import '../../../core/download/download_manager.dart';
import '../../../core/platform/ohos_public_storage.dart' show isOhosDocPath;
import '../../../core/platform/ohos_storage_location_sheet.dart';
import '../../../core/platform/platform_service.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/download/download_settings.dart';
import '../../../core/download/download_task.dart';
import '../../../core/favorites/favorite_group.dart';
import '../../../core/favorites/favorites_manager.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/theme/app_tokens.dart';
import '../../downloads/presentation/download_list_screen.dart';
import '../../downloads/presentation/downloaded_content_screen.dart';
import '../../../core/widgets/app_glass_bar.dart';
import 'package:nexhub/core/navigation/app_page_route.dart';
import 'widgets/settings_widgets.dart';
import 'widgets/settings_search_target.dart';

/// 下载管理主页面。
class SettingsDownloadScreen extends StatelessWidget {
  const SettingsDownloadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.downloadManagementTitle)),
      body: SettingsAutoScroll(
        child: ListView(
          padding: context.pageInset(AppTokens.spaceLg),
          children: <Widget>[
            // ── 下载列表 ──
            SettingsGroup(
              header: l10n.downloadListTab,
              children: <Widget>[
                SettingsTile(
                  key: const ValueKey<String>('download.list'),
                  icon: Icons.download_rounded,
                  title: l10n.downloadListTitle,
                  subtitle: l10n.downloads,
                  onTap: () => Navigator.of(context).push(
                    AppPageRoute<void>(
                      builder: (_) => const DownloadListScreen(),
                    ),
                  ),
                ),
                SettingsTile(
                  key: const ValueKey<String>('download.downloaded'),
                  icon: Icons.download_done_rounded,
                  title: l10n.downloadedContent,
                  onTap: () => Navigator.of(context).push(
                    AppPageRoute<void>(
                      builder: (_) => const DownloadedContentScreen(),
                    ),
                  ),
                ),
              ],
            ),

            // ── 下载设置 ──
            SettingsGroup(
              header: l10n.downloadSettingsTitle,
              children: <Widget>[
                // 最大同时下载数
                KeyedSubtree(
                  key: const ValueKey<String>('download.concurrent'),
                  child: _MaxConcurrentSetting(),
                ),

                // 线程数
                KeyedSubtree(
                  key: const ValueKey<String>('download.thread'),
                  child: _ThreadCountSetting(),
                ),

                // 下载路径
                KeyedSubtree(
                  key: const ValueKey<String>('download.path'),
                  child: _DownloadPathSetting(),
                ),

                // 下载器类型（项 12：弹窗选择）
                KeyedSubtree(
                  key: const ValueKey<String>('download.downloaderType'),
                  child: _DownloaderTypeSetting(),
                ),

                // 仅 WiFi 下载（需求 4：开关）
                KeyedSubtree(
                  key: const ValueKey<String>('download.wifiOnly'),
                  child: _WifiOnlySetting(),
                ),

                // 读后自动删除（开关）
                KeyedSubtree(
                  key: const ValueKey<String>('download.autoDelete'),
                  child: _AutoDeleteSetting(),
                ),

                // 自动删除排除分类（多选）
                KeyedSubtree(
                  key: const ValueKey<String>('download.autoDeleteExclude'),
                  child: _AutoDeleteExcludeSetting(),
                ),

                // 预下载后续剧集（0-5）
                KeyedSubtree(
                  key: const ValueKey<String>('download.preDownload'),
                  child: _PreDownloadSetting(),
                ),

                // 漫画格式（项 13：弹窗选择）
                KeyedSubtree(
                  key: const ValueKey<String>('download.comicFormat'),
                  child: _ComicFormatSetting(),
                ),

                // 小说格式（项 13：弹窗选择）
                KeyedSubtree(
                  key: const ValueKey<String>('download.novelFormat'),
                  child: _NovelFormatSetting(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// 可复用组件 —— 禁止复制粘贴重复实现
// ════════════════════════════════════════════════════════════════════════════════

/// 最大同时下载数设置项（持久化）。
class _MaxConcurrentSetting extends StatefulWidget {
  @override
  State<_MaxConcurrentSetting> createState() => _MaxConcurrentSettingState();
}

class _MaxConcurrentSettingState extends State<_MaxConcurrentSetting> {
  int _value = 3;
  final DownloadSettingsStore _store = DownloadSettingsStore();

  @override
  void initState() {
    super.initState();
    _store.load().then((s) {
      if (mounted) setState(() => _value = s.maxConcurrent);
    });
  }

  Future<void> _save(int value) async {
    final current = await _store.load();
    await _store.save(current.copyWith(maxConcurrent: value));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsTile(
      icon: Icons.sync_rounded,
      title: l10n.maxConcurrentDownloads,
      subtitle: '$_value',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.remove_circle_rounded, size: 20),
            onPressed: _value > 1
                ? () {
                    setState(() => _value--);
                    _save(_value);
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_rounded, size: 20),
            onPressed: _value < 10
                ? () {
                    setState(() => _value++);
                    _save(_value);
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

/// 线程数设置项（持久化）。
class _ThreadCountSetting extends StatefulWidget {
  @override
  State<_ThreadCountSetting> createState() => _ThreadCountSettingState();
}

class _ThreadCountSettingState extends State<_ThreadCountSetting> {
  int _value = 4;
  final DownloadSettingsStore _store = DownloadSettingsStore();

  @override
  void initState() {
    super.initState();
    _store.load().then((s) {
      if (mounted) setState(() => _value = s.threadCount);
    });
  }

  Future<void> _save(int value) async {
    final current = await _store.load();
    await _store.save(current.copyWith(threadCount: value));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsTile(
      icon: Icons.layers_rounded,
      title: l10n.threadCount,
      subtitle: '$_value',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.remove_circle_rounded, size: 20),
            onPressed: _value > 1
                ? () {
                    setState(() => _value--);
                    _save(_value);
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_rounded, size: 20),
            onPressed: _value < 16
                ? () {
                    setState(() => _value++);
                    _save(_value);
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

/// 下载路径设置项（持久化 + 目录选择器）。
class _DownloadPathSetting extends StatefulWidget {
  @override
  State<_DownloadPathSetting> createState() => _DownloadPathSettingState();
}

class _DownloadPathSettingState extends State<_DownloadPathSetting> {
  String _path = '';
  String _displayName = '';
  final DownloadSettingsStore _store = DownloadSettingsStore();
  final Saf _saf = Saf();

  @override
  void initState() {
    super.initState();
    _store.load().then((s) async {
      // 未设置（空串 / 旧版 D:/Downloads）时展示平台默认目录，而不是
      // 让设置项空白或显示不存在的 D 盘路径。
      final String path = await resolveDownloadPath(s.downloadPath);
      if (!mounted) return;
      setState(() => _path = path);
      // content:// 树 URI 显示系统文件夹名而非裸 URI。
      if (path.startsWith('content://')) {
        _saf.stat(path).then((doc) {
          if (mounted && doc != null) setState(() => _displayName = doc.name);
        });
      }
    });
  }

  Future<void> _pickPath() async {
    final l10n = AppLocalizations.of(context);

    // 鸿蒙：不支持任意文件夹选择；在「应用私有目录」与系统「下载」目录
    // （Download/<bundleName>，一次授权持久有效）之间选择。
    if (PlatformService.instance.isOHOS) {
      final String? picked = await showOhosStorageLocationSheet(
        context,
        title: l10n.downloadPath,
        appPrivateLabel: l10n.storageLocationAppPrivate,
        appPrivateHint: l10n.storageLocationAppPrivateHint,
        systemLabel: l10n.storageLocationSystemDownloads,
        systemHint: l10n.storageLocationSystemDownloadsHint,
        systemSelected: isOhosDocPath(_path),
      );
      if (picked == null || !mounted) return;
      final String applied =
          picked.isEmpty ? await defaultDownloadPath() : picked;
      try {
        setState(() {
          _path = applied;
          _displayName = picked.isEmpty
              ? ''
              : l10n.storageLocationSystemDownloads;
        });
        await context.read<DownloadManager>().setDownloadBasePath(applied);
        if (mounted) {
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
      return;
    }

    // Android：file_picker 没有可用的目录选择器，改用系统 SAF 目录选择器
    // （ACTION_OPEN_DOCUMENT_TREE），返回 content:// 树 URI，权限默认持久化。
    if (PlatformService.instance.isAndroid) {
      final SafDocumentFile? picked = await _saf.pickDirectory();
      if (picked == null || !mounted) return;
      try {
        setState(() {
          _path = picked.uri;
          _displayName = picked.name;
        });
        await context.read<DownloadManager>().setDownloadBasePath(picked.uri);
        if (mounted) {
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
      return;
    }

    // 仅当当前路径真实存在时才作为初始目录；Windows 上路径分隔符也要用 \。
    String? initialDir;
    if (_path.isNotEmpty && !_path.startsWith('content://')) {
      final d = Directory(_path);
      if (d.existsSync()) initialDir = d.absolute.path;
    }
    // file_picker 在 Windows 上是主线程同步弹 COM 对话框，会卡死 UI；
    // 放到后台 isolate 跑，UI 保持响应。
    // 鸿蒙例外：桌面分支硬编码 FilePickerWindows（加载 ole32.dll 会崩溃），且
    // 后台 isolate 无法使用 MethodChannel → 主 isolate 走插件注册的 FilePickerIO。
    String? result;
    if (PlatformService.instance.isOHOS) {
      result = await FilePicker.platform.getDirectoryPath(
        initialDirectory: initialDir,
      );
      if (result == null && initialDir != null) {
        result = await FilePicker.platform.getDirectoryPath();
      }
    } else {
      try {
        result = await Isolate.run<String?>(() {
          // FilePicker._instance 是 isolate-private late，主 isolate 初始化不
          // 会同步到新 isolate —— 必须在这里显式赋值。
          FilePicker.platform = FilePickerWindows();
          return FilePicker.platform.getDirectoryPath(
            initialDirectory: initialDir,
          );
        });
      } catch (_) {
        // file_picker_windows 对 initialDirectory 的解析较脆弱（例如
        // SHCreateItemFromParsingName 报 E_INVALIDARG）。退回不带初始目录再试。
        result = await Isolate.run<String?>(() {
          FilePicker.platform = FilePickerWindows();
          return FilePicker.platform.getDirectoryPath();
        });
      }
    }
    if (result == null || !mounted) return;
    final String picked = result;
    try {
      setState(() {
        _path = picked;
        _displayName = '';
      });
      // 持久化并通过 DownloadManager 立即生效（无需重启）。
      await context.read<DownloadManager>().setDownloadBasePath(picked);
      if (mounted) {
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
    final l10n = AppLocalizations.of(context);
    final String subtitle = _displayName.isNotEmpty
        ? _displayName
        : (isOhosDocPath(_path)
            ? l10n.storageLocationSystemDownloads
            : _path);
    return SettingsTile(
      icon: Icons.folder_rounded,
      title: l10n.downloadPath,
      subtitle: subtitle,
      onTap: _pickPath,
    );
  }
}

/// 下载器类型设置项（项 12：弹窗选择，持久化）。
class _DownloaderTypeSetting extends StatefulWidget {
  @override
  State<_DownloaderTypeSetting> createState() => _DownloaderTypeSettingState();
}

class _DownloaderTypeSettingState extends State<_DownloaderTypeSetting> {
  DownloaderType _type = DownloaderType.internal;
  final DownloadSettingsStore _store = DownloadSettingsStore();

  @override
  void initState() {
    super.initState();
    _store.load().then((s) {
      if (mounted) setState(() => _type = s.downloaderType);
    });
  }

  Future<void> _save(DownloaderType type) async {
    final current = await _store.load();
    await _store.save(current.copyWith(downloaderType: type));
  }

  String _label(AppLocalizations l10n) => switch (_type) {
        DownloaderType.internal => l10n.downloaderInternal,
        DownloaderType.external => l10n.downloaderExternal,
      };

  Future<void> _showDialog(AppLocalizations l10n) async {
    final selected = await showDialog<DownloaderType>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.downloaderSelectTitle),
        children: <Widget>[
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, DownloaderType.internal),
            child: Row(
              children: <Widget>[
                Icon(
                  _type == DownloaderType.internal
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: _type == DownloaderType.internal
                      ? Theme.of(ctx).colorScheme.primary
                      : Theme.of(ctx).colorScheme.outline,
                ),
                const SizedBox(width: AppTokens.spaceSm),
                const Icon(Icons.system_update_rounded, size: 20),
                const SizedBox(width: AppTokens.spaceXs),
                Text(l10n.downloaderInternal),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, DownloaderType.external),
            child: Row(
              children: <Widget>[
                Icon(
                  _type == DownloaderType.external
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: _type == DownloaderType.external
                      ? Theme.of(ctx).colorScheme.primary
                      : Theme.of(ctx).colorScheme.outline,
                ),
                const SizedBox(width: AppTokens.spaceSm),
                const Icon(Icons.open_in_new_rounded, size: 20),
                const SizedBox(width: AppTokens.spaceXs),
                Text(l10n.downloaderExternal),
              ],
            ),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _type = selected);
    await _save(selected);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_label(l10n))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsTile(
      icon: Icons.cloud_download_rounded,
      title: l10n.downloaderType,
      subtitle: _label(l10n),
      onTap: () => _showDialog(l10n),
    );
  }
}

/// 仅 WiFi 下载开关（持久化）。
///
/// 开启后由 [DownloadManager] 在启动下载前检查网络，
/// 未连接 WiFi 时任务挂起并等待网络恢复。
class _WifiOnlySetting extends StatefulWidget {
  @override
  State<_WifiOnlySetting> createState() => _WifiOnlySettingState();
}

class _WifiOnlySettingState extends State<_WifiOnlySetting> {
  bool _value = false;
  final DownloadSettingsStore _store = DownloadSettingsStore();

  @override
  void initState() {
    super.initState();
    _store.load().then((s) {
      if (mounted) setState(() => _value = s.wifiOnly);
    });
  }

  Future<void> _save(bool value) async {
    final current = await _store.load();
    await _store.save(current.copyWith(wifiOnly: value));
    // 立即让下载管理器读取新设置，使开关即时生效。
    try {
      context.read<DownloadManager>().reloadSettings();
    } on Object {
      // 管理器缺失时忽略，下次启动会重新读取。
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsTile(
      icon: Icons.wifi_rounded,
      title: l10n.downloadWifiOnly,
      subtitle: l10n.downloadWifiOnlyHint,
      trailing: Switch(
        value: _value,
        onChanged: (v) {
          v == true ? AppHaptics.toggleOn() : AppHaptics.toggleOff();
          setState(() => _value = v);
          _save(v);
        },
      ),
    );
  }
}

/// 读后自动删除开关（持久化）。
///
/// 开启后，影视看完 / 漫画小说读完（进度到最后一章）时，
/// 由阅读器/播放器调用 [DownloadManager.removeItemDownloads] 清理该内容的
/// 已下载文件（排除模块见 [_AutoDeleteExcludeSetting]）。
class _AutoDeleteSetting extends StatefulWidget {
  @override
  State<_AutoDeleteSetting> createState() => _AutoDeleteSettingState();
}

class _AutoDeleteSettingState extends State<_AutoDeleteSetting> {
  bool _value = false;
  final DownloadSettingsStore _store = DownloadSettingsStore();

  @override
  void initState() {
    super.initState();
    _store.load().then((s) {
      if (mounted) setState(() => _value = s.autoDeleteAfterRead);
    });
  }

  Future<void> _save(bool value) async {
    final current = await _store.load();
    await _store.save(current.copyWith(autoDeleteAfterRead: value));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsTile(
      icon: Icons.delete_sweep_rounded,
      title: l10n.downloadAutoDelete,
      subtitle: l10n.downloadAutoDeleteHint,
      trailing: Switch(
        value: _value,
        onChanged: (v) {
          v == true ? AppHaptics.toggleOn() : AppHaptics.toggleOff();
          setState(() => _value = v);
          _save(v);
        },
      ),
    );
  }
}

/// 自动删除排除分类（多选收藏分类：跨模块的收藏分组）。
class _AutoDeleteExcludeSetting extends StatefulWidget {
  @override
  State<_AutoDeleteExcludeSetting> createState() =>
      _AutoDeleteExcludeSettingState();
}

class _AutoDeleteExcludeSettingState extends State<_AutoDeleteExcludeSetting> {
  List<String> _excluded = const <String>[];
  final DownloadSettingsStore _store = DownloadSettingsStore();

  @override
  void initState() {
    super.initState();
    _store.load().then((s) {
      if (mounted) {
        setState(() => _excluded = s.autoDeleteExcludeGroupIds);
      }
    });
  }

  String _subtitle(AppLocalizations l10n, FavoritesManager fav) {
    if (_excluded.isEmpty) return l10n.downloadAutoDeleteExcludeNone;
    final names = <String>[];
    for (final id in _excluded) {
      final g = fav.groupById(id);
      if (g != null) names.add(g.name);
    }
    if (names.isEmpty) return l10n.downloadAutoDeleteExcludeNone;
    return names.join(' · ');
  }

  Future<void> _showPicker(AppLocalizations l10n, FavoritesManager fav) async {
    final scheme = Theme.of(context).colorScheme;
    // 跨模块收集可见分组（媒体 / 漫画 / 小说），供统一多选。
    final groups = <FavoriteGroup>[
      ...fav.groupsFor(SourceType.animeSource),
      ...fav.groupsFor(SourceType.mangaSource),
      ...fav.groupsFor(SourceType.novelSource),
    ];

    Widget option(FavoriteGroup g) {
      final selected = _excluded.contains(g.id);
      final moduleLabel = switch (g.sourceType) {
        SourceType.animeSource ||
        SourceType.videoSource ||
        SourceType.audioSource =>
          l10n.navMedia,
        SourceType.mangaSource => l10n.navComic,
        SourceType.novelSource => l10n.navNovel,
      };
      return ListTile(
        leading: Icon(
          selected ? Icons.check_circle_rounded : Icons.label_rounded,
          color: selected ? scheme.primary : scheme.outline,
        ),
        title: Text(
          g.name,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? scheme.primary : null,
          ),
        ),
        subtitle: Text(moduleLabel),
        trailing: Icon(
          selected
              ? Icons.check_circle_rounded
              : Icons.radio_button_unchecked_rounded,
          color: selected ? scheme.primary : scheme.outline,
        ),
        onTap: () {
          setState(() {
            if (selected) {
              _excluded = _excluded.where((e) => e != g.id).toList();
            } else {
              _excluded = <String>[..._excluded, g.id];
            }
          });
        },
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(AppTokens.spaceMd),
                  child: Text(
                    l10n.downloadAutoDeleteExclude,
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
                const Divider(height: 1),
                if (groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(AppTokens.spaceLg),
                    child: Text(
                      l10n.noGroupsHint,
                      textAlign: TextAlign.center,
                      style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  )
                else
                  ...groups.map(option),
                Padding(
                  padding: const EdgeInsets.all(AppTokens.spaceMd),
                  child: FilledButton(
                    onPressed: () async {
                      final current = await _store.load();
                      await _store.save(current.copyWith(
                        autoDeleteExcludeGroupIds: _excluded,
                      ));
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    },
                    child: Text(l10n.confirm),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fav = context.watch<FavoritesManager>();
    return SettingsTile(
      icon: Icons.filter_alt_rounded,
      title: l10n.downloadAutoDeleteExclude,
      subtitle: _subtitle(l10n, fav),
      onTap: () => _showPicker(l10n, fav),
    );
  }
}

/// 预下载后续内容数（0-25，0 = 关闭）。
class _PreDownloadSetting extends StatefulWidget {
  @override
  State<_PreDownloadSetting> createState() => _PreDownloadSettingState();
}

class _PreDownloadSettingState extends State<_PreDownloadSetting> {
  int _value = 0;
  final DownloadSettingsStore _store = DownloadSettingsStore();

  @override
  void initState() {
    super.initState();
    _store.load().then((s) {
      if (mounted) setState(() => _value = s.preDownloadCount);
    });
  }

  Future<void> _save(int value) async {
    final current = await _store.load();
    await _store.save(current.copyWith(preDownloadCount: value));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsTile(
      icon: Icons.download_for_offline_rounded,
      title: l10n.downloadPreDownload,
      subtitle: _value == 0
          ? l10n.downloadPreDownloadOff
          : l10n.downloadEpisodesCount(_value),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.remove_circle_rounded, size: 20),
            onPressed: _value > 0
                ? () {
                    setState(() => _value--);
                    _save(_value);
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_rounded, size: 20),
            onPressed: _value < 25
                ? () {
                    setState(() => _value++);
                    _save(_value);
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

/// 漫画格式设置项（项 13：BottomSheet 选择，持久化）。
class _ComicFormatSetting extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final prefs = context.watch<DownloadManager>().formatPrefs;

    String subtitle(DownloadFormat f) => switch (f) {
          DownloadFormat.cbz => l10n.comicFormatCbz,
          DownloadFormat.jpg => l10n.comicFormatJpg,
          DownloadFormat.png => l10n.comicFormatPng,
          DownloadFormat.folder => l10n.formatFolder,
          _ => l10n.comicFormatCbz,
        };

    return SettingsTile(
      icon: Icons.auto_stories_rounded,
      title: l10n.comicFormatSelectTitle,
      subtitle: subtitle(prefs.comicFormat),
      onTap: () => _showSheet(context, prefs, l10n),
    );
  }

  Future<void> _showSheet(
    BuildContext context,
    DownloadFormatPreferences prefs,
    AppLocalizations l10n,
  ) async {
    final manager = context.read<DownloadManager>();
    final scheme = Theme.of(context).colorScheme;

    Widget option(DownloadFormat fmt, String label, IconData icon) {
      final selected = prefs.comicFormat == fmt;
      return ListTile(
        leading: Icon(icon, color: selected ? scheme.primary : null),
        title: Text(label,
            style: TextStyle(
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? scheme.primary : null)),
        trailing: selected
            ? Icon(Icons.check_circle_rounded, color: scheme.primary)
            : Icon(Icons.radio_button_unchecked_rounded, color: scheme.outline),
        onTap: () {
          manager.setFormatPrefs(
            prefs.copyWith(comicFormat: fmt),
          );
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(label)),
          );
        },
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(AppTokens.spaceMd),
                  child: Text(
                    l10n.comicFormatSelectTitle,
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
                const Divider(height: 1),
                option(DownloadFormat.jpg, l10n.comicFormatJpg,
                    Icons.image_rounded),
                option(DownloadFormat.png, l10n.comicFormatPng,
                    Icons.photo_rounded),
                option(DownloadFormat.cbz, l10n.comicFormatCbz,
                    Icons.archive_rounded),
                const SizedBox(height: AppTokens.spaceSm),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 小说格式设置项（项 13：BottomSheet 选择，持久化）。
class _NovelFormatSetting extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final prefs = context.watch<DownloadManager>().formatPrefs;

    String subtitle(DownloadFormat f) => switch (f) {
          DownloadFormat.epub => l10n.novelFormatEpub,
          DownloadFormat.txt => l10n.novelFormatTxt,
          _ => l10n.novelFormatEpub,
        };

    return SettingsTile(
      icon: Icons.menu_book_rounded,
      title: l10n.novelFormatSelectTitle,
      subtitle: subtitle(prefs.novelFormat),
      onTap: () => _showSheet(context, prefs, l10n),
    );
  }

  Future<void> _showSheet(
    BuildContext context,
    DownloadFormatPreferences prefs,
    AppLocalizations l10n,
  ) async {
    final manager = context.read<DownloadManager>();
    final scheme = Theme.of(context).colorScheme;

    Widget option(DownloadFormat fmt, String label, IconData icon) {
      final selected = prefs.novelFormat == fmt;
      return ListTile(
        leading: Icon(icon, color: selected ? scheme.primary : null),
        title: Text(label,
            style: TextStyle(
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? scheme.primary : null)),
        trailing: selected
            ? Icon(Icons.check_circle_rounded, color: scheme.primary)
            : Icon(Icons.radio_button_unchecked_rounded, color: scheme.outline),
        onTap: () {
          manager.setFormatPrefs(
            prefs.copyWith(novelFormat: fmt),
          );
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(label)),
          );
        },
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(AppTokens.spaceMd),
                  child: Text(
                    l10n.novelFormatSelectTitle,
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
                const Divider(height: 1),
                option(DownloadFormat.txt, l10n.novelFormatTxt,
                    Icons.description_rounded),
                option(DownloadFormat.epub, l10n.novelFormatEpub,
                    Icons.book_rounded),
                const SizedBox(height: AppTokens.spaceSm),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
