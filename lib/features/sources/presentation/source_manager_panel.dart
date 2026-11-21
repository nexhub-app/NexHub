/// 单模块源管理面板（升级版）。
///
/// 用于各模块首页的「源」区块，提供：
/// - 源列表（[UnifiedSourceTile] 更多菜单，含 开关/编辑/删除/隐藏/镜像设置）
/// - 本地导入：选择文件 或 选择文件夹（递归扫描 json/txt/xml）→ 预览勾选 → 确认导入
/// - 空状态时引导「选择文件夹导入」与「采集 API 导入」
///
/// 仅显示 [filterType] 对应的源（不含三模块 Tab）。
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/models/plugin_config.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/unified_source_tile.dart';
import '../../../core/widgets/app_glass_bar.dart';
import 'source_login_screen.dart';
import 'source_mirror_screen.dart';
import 'package:nexhub/core/navigation/app_page_route.dart';
import 'package:nexhub/core/widgets/app_alert_dialog.dart';
import '../../../core/local/folder_import.dart';
import '../../../core/local/local_content_manager.dart' show isAndroidSafUri;
import '../../../core/platform/platform_service.dart';
import '../../../core/local/saf_bridge.dart'
    show listFolderSourceFilesSaf, readSourceText, safBaseName;
import '../../../core/utils/app_haptics.dart';
import '../../../core/utils/app_log.dart';

/// 本地导入预览项。
class _ImportPreviewItem {
  final String path;
  final String fileName;
  final PluginConfig? config;
  final bool isValid;
  final String? error;

  _ImportPreviewItem({
    required this.path,
    required this.fileName,
    this.config,
    this.isValid = false,
    this.error,
  });
}

/// 单模块源管理面板。
class SourceManagerPanel extends StatefulWidget {
  final SourceType filterType;

  const SourceManagerPanel({
    super.key,
    required this.filterType,
  });

  @override
  State<SourceManagerPanel> createState() => _SourceManagerPanelState();
}

class _SourceManagerPanelState extends State<SourceManagerPanel> {
  List<_ImportPreviewItem> _previewItems = <_ImportPreviewItem>[];
  Set<int> _selectedPreviewIndices = <int>{};
  bool _previewMode = false;
  int _skippedByTypeCount = 0;

  /// 因年龄限制被拦截（未进入本地导入预览）的 18+ 源数量。
  int _ageBlockedCount = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_previewMode) return _buildImportPreview(l10n);

    final SourceRepository repo = context.watch<SourceRepository>();
    final List<PluginConfig> sources = repo.all
        .where((PluginConfig c) =>
            c.type.mediaBucket == widget.filterType.mediaBucket)
        .where((c) => !repo.isAgeBlocked(c))
        .toList();

    return ListView(
      padding: context.pageInset(AppTokens.spaceMd),
      children: <Widget>[
        _buildImportBar(l10n),
        const SizedBox(height: AppTokens.spaceMd),
        if (sources.isEmpty)
          AppEmptyState(
            icon: Icons.extension_rounded,
            message: l10n.sourceListEmpty,
            actionLabel: l10n.selectFolder,
            onAction: _pickLocalFolder,
          )
        else
          ...sources.map((s) => _buildSourceTile(l10n, s)),
      ],
    );
  }

  /// 将 SourceType 映射为本地化分类标签。
  String _typeLabel(SourceType type, AppLocalizations l10n) {
    switch (type) {
      case SourceType.novelSource:
        return l10n.sourceCategoryNovel;
      case SourceType.animeSource:
        return l10n.sourceCategoryMedia;
      case SourceType.videoSource:
        return l10n.sourceTypeVideo;
      case SourceType.audioSource:
        return l10n.sourceTypeAudio;
      case SourceType.mangaSource:
        return l10n.sourceCategoryComic;
    }
  }

  /// 顶部「本地导入」操作条（选择文件 / 选择文件夹）。
  Widget _buildImportBar(AppLocalizations l10n) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        child: Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.file_present_rounded),
                label: Text(l10n.localImportPickFile),
                onPressed: _previewMode ? null : _pickLocalFile,
              ),
            ),
            const SizedBox(width: AppTokens.spaceSm),
            // 鸿蒙手机：目录选择接口不可用（已知缺陷 U2），隐藏文件夹导入入口，
            // 源 JSON 走「选择文件」逐个导入；鸿蒙 PC 已支持目录导入。
            if (!PlatformService.instance.isOHOSPhone)
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.folder_rounded),
                  label: Text(l10n.selectFolder),
                  onPressed: _previewMode ? null : _pickLocalFolder,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 单个源的列表项（更多菜单含完整操作）。
  Widget _buildSourceTile(AppLocalizations l10n, PluginConfig s) {
    final repo = context.read<SourceRepository>();
    return UnifiedSourceTile(
      name: s.name,
      url: s.site.baseUrl,
      enabled: s.isEnabled,
      deprecated: s.isDeprecated,
      ageRating: s.ageRating,
      isHidden: s.isHidden,
      deprecatedLabel: l10n.deprecated,
      mirrorSettingsTooltip: l10n.mirrorSettings,
      hideTooltip: l10n.sourceHide,
      unhideTooltip: l10n.sourceShowHidden,
      editTooltip: l10n.sourceEdit,
      deleteTooltip: l10n.sourceDelete,
      useMoreMenu: true,
      moreMenuTooltip: l10n.moreActions,
      loginTooltip: l10n.sourceLogin,
      onLogin: s.comments?.supportsLogin == true
          ? () => Navigator.of(context).push(
                AppPageRoute<void>(
                  builder: (_) => SourceLoginScreen(source: s),
                ),
              )
          : null,
      onToggle: (bool value) => repo.setEnabled(s.id, value),
      onMirrorSettings: () => Navigator.of(context).push(
        AppPageRoute<void>(builder: (_) => SourceMirrorScreen(source: s)),
      ),
      onHide: () => repo.setHidden(s.id, !s.isHidden),
      onEdit: () => _showEditDialog(s),
      onDelete: () => _showDeleteConfirm(s),
    );
  }

  // ── 本地导入：选择 ───────────────────────────────────────────────

  Future<void> _pickLocalFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['json', 'txt', 'xml'],
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    _processPickedPaths(
      result.files.map((f) => f.path).whereType<String>().toList(),
    );
  }

  Future<void> _pickLocalFolder() async {
    // Android 必须用 FolderImport.pick（内部走 saf.pickDirectory 拿 content:// tree URI）；
    // 鸿蒙 PC 走系统目录选择并复制进沙箱；其余平台为真实路径。
    final dirPath = await FolderImport.pick(context);
    if (dirPath == null || dirPath.isEmpty) return;
    List<String> files;
    try {
      if (isAndroidSafUri(dirPath)) {
        files = await listFolderSourceFilesSaf(dirPath);
      } else {
        files = <String>[];
        final dir = Directory(dirPath);
        await for (final entity
            in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            final ext = p.extension(entity.path).toLowerCase();
            if (ext == '.json' || ext == '.txt' || ext == '.xml') {
              files.add(entity.path);
            }
          }
        }
      }
    } on Object catch (e, st) {
      AppLog.instance.eWithStack('[源面板导入] 文件夹扫描失败 $dirPath', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).folderScanFailed)),
        );
      }
      return;
    }
    if (files.isEmpty) {
      AppLog.instance.w('[源面板导入] 扫描为空 dirPath=$dirPath');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).noLocalSource)),
        );
      }
      return;
    }
    _processPickedPaths(files);
  }

  Future<void> _processPickedPaths(List<String> paths) async {
    final repo = context.read<SourceRepository>();
    final items = <_ImportPreviewItem>[];
    int skippedByType = 0;
    _ageBlockedCount = 0;
    for (final path in paths) {
      final fileName =
          isAndroidSafUri(path) ? safBaseName(path) : p.basename(path);
      try {
        final raw = await readSourceText(path);
        // 统一批量解析：支持小说(通用书源格式)源，且一个文件可含多个源。
        // 后台 isolate 解析：大文件主线程解析会冻结 UI。
        final configs = await SourceRepository.parseMixedSourcesAsync(raw);
        if (configs.isEmpty) {
          items.add(_ImportPreviewItem(
            path: path,
            fileName: fileName,
            isValid: false,
            error: AppLocalizations.of(context).sourceUnrecognized,
          ));
        } else {
          for (final c in configs) {
            // 单模块面板：只导入本模块类型，其他类型直接忽略。
            if (c.type != widget.filterType) {
              skippedByType++;
              continue;
            }
            // 年龄限制开启时，18+ 源不可导入
            if (repo.isAgeBlocked(c)) {
              _ageBlockedCount++;
              continue;
            }
            items.add(_ImportPreviewItem(
              path: path,
              fileName: fileName,
              config: c,
              isValid: true,
            ));
          }
        }
      } on Object catch (e) {
        AppLog.instance.e('[源面板导入] 读取/解析失败 $fileName: $e');
        items.add(_ImportPreviewItem(
          path: path,
          fileName: fileName,
          isValid: false,
          error: e.toString(),
        ));
      }
    }
    if (!mounted) return;

    // 过滤后没有任何可导入源（文件里全是其他类型）→ 提示并退出。
    if (items.isEmpty && skippedByType > 0) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.importNoMatchingType(
            _typeLabel(widget.filterType, l10n),
            skippedByType,
          )),
        ),
      );
      return;
    }

    setState(() {
      _previewItems = items;
      _selectedPreviewIndices = <int>{
        for (int i = 0; i < items.length; i++)
          if (items[i].isValid) i,
      };
      _previewMode = true;
      _skippedByTypeCount = skippedByType;
    });
  }

  // ── 本地导入：预览 + 确认 ─────────────────────────────────────────

  Widget _buildImportPreview(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: context.pageInset(AppTokens.spaceMd),
      children: <Widget>[
        if (_ageBlockedCount > 0)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: AppTokens.spaceSm),
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceMd,
              vertical: AppTokens.spaceSm,
            ),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.lock_rounded, size: 16, color: scheme.onErrorContainer),
                const SizedBox(width: AppTokens.spaceXs),
                Expanded(
                  child: Text(
                    l10n.ageBlockedImportHint(_ageBlockedCount),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: l10n.back,
              onPressed: () => setState(() {
                _previewMode = false;
                _previewItems = <_ImportPreviewItem>[];
                _selectedPreviewIndices = <int>{};
                _skippedByTypeCount = 0;
              }),
            ),
            Expanded(
              child: Text(
                l10n.importPreviewTitle(_previewItems.length),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton(
              onPressed: _previewItems.isEmpty
                  ? null
                  : () => setState(() {
                        _selectedPreviewIndices =
                            <int>{for (int i = 0; i < _previewItems.length; i++) i};
                      }),
              child: Text(l10n.selectAll),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.spaceSm),
        // 单模块面板：导入时自动忽略其他类型源，这里给出提示。
        if (_skippedByTypeCount > 0)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: AppTokens.spaceSm),
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceMd,
              vertical: AppTokens.spaceSm,
            ),
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.5),
            child: Row(
              children: <Widget>[
                Icon(Icons.filter_alt_rounded, size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: AppTokens.spaceXs),
                Expanded(
                  child: Text(
                    l10n.importTypeFiltered(_skippedByTypeCount),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          ),
        if (_previewItems.isEmpty)
          AppEmptyState(
            icon: Icons.folder_open_rounded,
            message: l10n.localImportHint,
          )
        else
          ..._previewItems.asMap().entries.map((e) {
            final i = e.key;
            final item = e.value;
            return CheckboxListTile(
              value: _selectedPreviewIndices.contains(i),
              onChanged: item.isValid
                  ? (v) {
                      AppHaptics.selectionClick();
                      setState(() {
                        if (v == true) {
                          _selectedPreviewIndices.add(i);
                        } else {
                          _selectedPreviewIndices.remove(i);
                        }
                      });
                    }
                  : null,
              title: Text(item.fileName),
              subtitle: item.isValid
                  ? Text(item.config?.name ?? item.fileName)
                  : Text(item.error ?? l10n.sourceImportInvalid,
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
              controlAffinity: ListTileControlAffinity.leading,
            );
          }),
        const SizedBox(height: AppTokens.spaceMd),
        FilledButton.icon(
          icon: const Icon(Icons.check_rounded),
          label: Text(l10n.confirmImport),
          onPressed: _selectedPreviewIndices.isEmpty ? null : _confirmImport,
        ),
      ],
    );
  }

  Future<void> _confirmImport() async {
    final l10n = AppLocalizations.of(context);
    final repo = context.read<SourceRepository>();
    final total = _selectedPreviewIndices.length;
    // 批量入库：整批一次持久化 + 一次通知（逐个 addSource 的写盘/通知
    // 风暴在大库导入时冻结主线程）。
    final configs = _selectedPreviewIndices
        .where((i) => i >= 0 && i < _previewItems.length)
        .map((i) => _previewItems[i])
        .where((item) => item.isValid && item.config != null)
        .map((item) => item.config!)
        .toList();
    final success =
        configs.isEmpty ? 0 : repo.addSources(configs);
    if (!mounted) return;
    setState(() {
      _previewMode = false;
      _previewItems = <_ImportPreviewItem>[];
      _selectedPreviewIndices = <int>{};
      _skippedByTypeCount = 0;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.sourceImportResult(success, total))),
    );
  }

  // ── 单源操作：编辑 / 删除 ─────────────────────────────────────────

  void _showEditDialog(PluginConfig s) {
    final l10n = AppLocalizations.of(context);
    final nameCtrl = TextEditingController(text: s.name);
    final urlCtrl = TextEditingController(text: s.site.baseUrl);
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AppAlertDialog(
        title: Text(l10n.sourceEdit),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextFormField(
                controller: nameCtrl,
                decoration: InputDecoration(labelText: l10n.sourceName),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l10n.requiredHint : null,
              ),
              const SizedBox(height: AppTokens.spaceSm),
              TextFormField(
                controller: urlCtrl,
                decoration: InputDecoration(labelText: l10n.sourceBaseUrl),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l10n.requiredHint : null,
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              final ok = context.read<SourceRepository>().updateSource(
                    s.id,
                    name: nameCtrl.text.trim(),
                    baseUrl: urlCtrl.text.trim(),
                  );
              Navigator.of(dialogContext).pop();
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.sourceEditFailed)),
                );
              }
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(PluginConfig s) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AppAlertDialog(
        title: Text(l10n.deleteConfirmTitle),
        content: Text(l10n.deleteConfirmContent(s.name)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              final ok =
                  context.read<SourceRepository>().removeSource(s.id);
              Navigator.of(dialogContext).pop();
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.sourceDeleteFailed)),
                );
              }
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }
}
