library;

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/plugin_config.dart';
import '../../../core/scraper/collect_api_parser.dart';
import '../../../core/scraper/http_fetcher.dart';
import '../../../core/services/source_library_subscription.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_error_state.dart';
import '../../../core/widgets/app_form_field.dart';
import '../../../core/widgets/app_loading_indicator.dart';
import '../../../core/widgets/app_segmented_tabs.dart';
import '../../../core/widgets/app_url_input_bar.dart';
import 'collect_api_import_screen.dart';
import 'package:nexhub/core/navigation/app_page_route.dart';
import '../../../core/widgets/app_glass_bar.dart';

enum _ImportTab { url, file, json, library }

/// 源导入页：支持 URL / 本地文件 / 手动 JSON 三种方式，校验后保存。
class SourceImportScreen extends StatefulWidget {
  const SourceImportScreen({super.key});

  @override
  State<SourceImportScreen> createState() => _SourceImportScreenState();
}

class _SourceImportScreenState extends State<SourceImportScreen> {
  _ImportTab _tab = _ImportTab.url;
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _jsonController = TextEditingController();
  final TextEditingController _libraryUrlController = TextEditingController();
  final TextEditingController _addLibraryNameController =
      TextEditingController();
  bool _loading = false;
  String? _error;

  /// 解析出的待导入源（批量，可能含小说/媒体/漫画）。
  List<PluginConfig> _previews = const <PluginConfig>[];

  /// 批量模式下勾选导入的源下标集合。
  Set<int> _selectedPreviewIndices = const <int>{};

  bool _collectApiDetected = false;
  String? _pickedFileName;

  /// 因年龄限制被拦截（未进入导入预览）的 18+ 源数量。
  int _ageBlockedCount = 0;

  @override
  void dispose() {
    _urlController.dispose();
    _jsonController.dispose();
    _libraryUrlController.dispose();
    _addLibraryNameController.dispose();
    super.dispose();
  }

  Future<void> _tryParse(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _previews = const <PluginConfig>[];
      _selectedPreviewIndices = const <int>{};
    });
    final repo = context.read<SourceRepository>();
    try {
      // 统一批量解析：支持单源 / JSON 数组（小说+媒体+漫画混排）/
      // 通用书源格式 / 包装对象 / NDJSON / XML，一次导入多种类型。
      // 后台 isolate 解析：大文件（上千源）主线程解析会冻结 UI。
      final list = await SourceRepository.parseMixedSourcesAsync(text);
      final filtered = list.where((c) => !repo.isAgeBlocked(c)).toList();
      _ageBlockedCount = list.length - filtered.length;
      if (mounted) {
        if (filtered.isEmpty) {
          setState(() {
            _error = _ageBlockedCount > 0
                ? AppLocalizations.of(context).ageRestrictionImportMatureBlocked
                : AppLocalizations.of(context).sourceUnrecognized;
            _loading = false;
          });
        } else {
          setState(() {
            _previews = filtered;
            _selectedPreviewIndices = <int>{
              for (int i = 0; i < filtered.length; i++) i
            };
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _importFromUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    if (CollectApiParser.looksLikeCollectApi(url)) {
      if (mounted) setState(() => _collectApiDetected = true);
      return;
    }
    setState(() => _loading = true);
    try {
      final text = await HttpFetcher.instance.getHtml(url);
      await _tryParse(text);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// 库导入：拉取源库清单（manifest），解析其中每个源的 rawUrl 并逐个下载，
  /// 复用与 URL 导入相同的预览 / 勾选 / 保存流程。
  ///
  /// 兼容两种清单形态：
  /// - 官方库 `index.json`：`{"sources":[{id,name,rawUrl,...}]}`，逐条 fetch `rawUrl`；
  /// - 扁平源列表 / 单个源对象：无 `rawUrl` 时直接解析条目本身。
  Future<void> _importLibrary(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _loading = true;
      _error = null;
      _previews = const <PluginConfig>[];
      _selectedPreviewIndices = const <int>{};
    });
    try {
      final text = await HttpFetcher.instance.getHtml(trimmed);
      final dynamic decoded = jsonDecode(text);
      final List<Map<String, dynamic>> entries;
      if (decoded is Map<String, dynamic> && decoded['sources'] is List) {
        entries = (decoded['sources'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else if (decoded is List) {
        entries = decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else {
        entries = const <Map<String, dynamic>>[];
      }

      final List<PluginConfig> out = <PluginConfig>[];
      await Future.wait(entries.map((e) async {
        final rawUrl = e['rawUrl'] as String?;
        if (rawUrl != null && rawUrl.isNotEmpty) {
          try {
            final t = await HttpFetcher.instance.getHtml(rawUrl);
            out.addAll(await SourceRepository.parseMixedSourcesAsync(t));
          } on Object {
            // 单源下载失败不影响其余源
          }
          return;
        }
        // 无 rawUrl：条目本身即一份源配置
        try {
          out.addAll(await SourceRepository.parseMixedSourcesAsync(
            jsonEncode(e),
          ));
        } on Object {
          // 跳过无法解析的条目
        }
      }));

      if (!mounted) return;
      final repo = context.read<SourceRepository>();
      final filtered = out.where((c) => !repo.isAgeBlocked(c)).toList();
      _ageBlockedCount = out.length - filtered.length;
      if (filtered.isEmpty) {
        setState(() {
          _error = _ageBlockedCount > 0
              ? l10n.ageRestrictionImportMatureBlocked
              : l10n.sourceUnrecognized;
          _loading = false;
        });
        return;
      }
      setState(() {
        _previews = filtered;
        _selectedPreviewIndices = <int>{
          for (int i = 0; i < filtered.length; i++) i
        };
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// 订阅一个新源库（按 url 去重），并立即拉取导入其源。
  Future<void> _subscribeLibrary() async {
    final url = _libraryUrlController.text.trim();
    if (url.isEmpty) return;
    final name = _addLibraryNameController.text.trim().isNotEmpty
        ? _addLibraryNameController.text.trim()
        : _deriveNameFromUrl(url);
    final lib = SourceLibrary(
      id: url,
      name: name,
      url: url,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await context.read<SourceLibrarySubscription>().add(lib);
    _libraryUrlController.clear();
    _addLibraryNameController.clear();
    await _importLibrary(url);
  }

  /// 从订阅地址推导默认名称（取 host，去掉 www.）。
  String _deriveNameFromUrl(String url) {
    final host = Uri.tryParse(url)?.host ?? url;
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  /// 外链打开源库主页（如 GitHub 仓库）。
  Future<void> _openHomepage(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    _pickedFileName = result?.files.single.name;
    final text = await File(path).readAsString();
    _jsonController.text = text;
    await _tryParse(text);
  }

  void _retry() {
    if (_tab == _ImportTab.url) {
      _importFromUrl();
    } else if (_tab == _ImportTab.library) {
      _importLibrary(_libraryUrlController.text);
    } else if (_tab == _ImportTab.json) {
      _tryParse(_jsonController.text);
    } else {
      _pickFile();
    }
  }

  void _save() {
    if (_previews.isEmpty) return;
    final selected = _selectedPreviewIndices
        .where((i) => i >= 0 && i < _previews.length)
        .map((i) => _previews[i])
        .toList();
    if (selected.isEmpty) return;
    final repo = context.read<SourceRepository>();
    // 防御：年龄限制开启时，跳过 18+ 源（理论上已在前置预览中过滤）。
    final importable = selected.where((c) => !repo.isAgeBlocked(c)).toList();
    if (importable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)
                .ageRestrictionImportMatureBlocked)),
      );
      return;
    }
    // 批量入库：整批一次持久化 + 一次通知（逐个 addSource 的写盘/通知风暴
    // 在大库导入时冻结主线程）。
    repo.addSources(importable);
    // 必须在 pop() 之前捕获 ScaffoldMessenger 与文案，否则 pop 后 context
    // 正在被拆解，再调用 ScaffoldMessenger.of(context)/AppLocalizations.of(context)
    // 会访问已失效的 element 树，触发「used after being disposed / wrong build
    // scope / _dependents.isEmpty」等崩溃（导入 manga_eh.json 时的实测崩溃）。
    final messenger = ScaffoldMessenger.of(context);
    final resultMsg = AppLocalizations.of(context)
        .sourceImportResult(selected.length, _previews.length);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text(resultMsg)));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.importSource)),
      body: ListView(
        padding: context.pageInset(AppTokens.spaceLg),
        children: <Widget>[
          AppSegmentedTabs<_ImportTab>(
            selected: <_ImportTab>{_tab},
            onSelectionChanged: (Set<_ImportTab> s) =>
                setState(() => _tab = s.first),
            segments: <ButtonSegment<_ImportTab>>[
              ButtonSegment<_ImportTab>(
                  value: _ImportTab.url, label: Text(l10n.sourceImportFromUrl)),
              ButtonSegment<_ImportTab>(
                  value: _ImportTab.file,
                  label: Text(l10n.sourceImportFromFile)),
              ButtonSegment<_ImportTab>(
                  value: _ImportTab.json,
                  label: Text(l10n.sourceImportFromJson)),
              ButtonSegment<_ImportTab>(
                  value: _ImportTab.library,
                  label: Text(l10n.importLibraryTab)),
            ],
          ),
          const SizedBox(height: AppTokens.spaceLg),
          if (_tab == _ImportTab.url) ...<Widget>[
            AppUrlInputBar(
              controller: _urlController,
              hintText: l10n.sourceImportUrlHint,
              submitLabel: l10n.import,
              isLoading: _loading && _tab == _ImportTab.url,
              onSubmit: (_) => _importFromUrl(),
            ),
            if (_collectApiDetected) ...<Widget>[
              const SizedBox(height: AppTokens.spaceMd),
              _collectApiHint(l10n),
            ],
          ] else if (_tab == _ImportTab.file) ...<Widget>[
            FilledButton.icon(
              onPressed: _loading ? null : _pickFile,
              icon: const Icon(Icons.file_open_rounded),
              label: Text(l10n.sourceImportFilePicker),
            ),
            if (_pickedFileName != null) ...<Widget>[
              const SizedBox(height: AppTokens.spaceMd),
              Text(
                _pickedFileName!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ] else if (_tab == _ImportTab.json) ...<Widget>[
            AppFormField(
              label: l10n.sourceImportJsonHint,
              hint: l10n.sourceImportJsonHint,
              controller: _jsonController,
              maxLines: 10,
            ),
            const SizedBox(height: AppTokens.spaceMd),
            FilledButton.icon(
              onPressed:
                  _loading ? null : () => _tryParse(_jsonController.text),
              icon: const Icon(Icons.check_circle_rounded),
              label: Text(l10n.sourceImportValidate),
            ),
          ] else ...<Widget>[
            // 源库订阅（库导入 / 库收藏）：已订阅列表 + 新增订阅
            _buildSubscribedLibraries(l10n, scheme),
            const SizedBox(height: AppTokens.spaceLg),
            _buildAddLibraryCard(l10n, scheme),
          ],
          const SizedBox(height: AppTokens.spaceLg),
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
                  Icon(Icons.lock_rounded,
                      size: 16, color: scheme.onErrorContainer),
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
          _buildPreview(l10n, scheme),
        ],
      ),
    );
  }

  Widget _collectApiHint(AppLocalizations l10n) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.sourceImportCollectApiDetected,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppTokens.spaceMd),
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                AppPageRoute<void>(
                  builder: (_) => const CollectApiImportScreen(),
                ),
              ),
              child: Text(l10n.sourceImportCollectApiRedirect),
            ),
          ],
        ),
      );

  /// 已订阅源库列表（库收藏）：展示每个源库并支持更新导入 / 打开主页 / 取消订阅。
  Widget _buildSubscribedLibraries(AppLocalizations l10n, ColorScheme scheme) {
    final subs = context.watch<SourceLibrarySubscription>();
    final libs = subs.all();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.libraryBookmarks,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppTokens.spaceSm),
          if (libs.isEmpty)
            Text(
              l10n.libraryEmpty,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            ...libs.map((lib) => _buildLibraryCard(lib, l10n, scheme)),
        ],
      ),
    );
  }

  /// 单个源库卡片。
  Widget _buildLibraryCard(
    SourceLibrary lib,
    AppLocalizations l10n,
    ColorScheme scheme,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
      child: AppCard(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(lib.name,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                if (lib.isOfficial)
                  Chip(
                    label: Text(l10n.official),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: AppTokens.spaceXxs),
            Text(
              lib.url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            Wrap(
              spacing: AppTokens.spaceSm,
              runSpacing: AppTokens.spaceXs,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: _loading ? null : () => _importLibrary(lib.url),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(l10n.fetchLibraryAndImport),
                ),
                if (lib.homepage != null)
                  OutlinedButton.icon(
                    onPressed: () => _openHomepage(lib.homepage!),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(l10n.openHomepage),
                  ),
                if (!lib.isOfficial)
                  OutlinedButton.icon(
                    onPressed: () => context
                        .read<SourceLibrarySubscription>()
                        .remove(lib.id),
                    icon: const Icon(Icons.bookmark_remove_rounded, size: 18),
                    label: Text(l10n.unsubscribeLibrary),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 新增源库订阅卡片：填写名称（可选）与订阅地址，订阅后立即拉取导入。
  Widget _buildAddLibraryCard(AppLocalizations l10n, ColorScheme scheme) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.addLibraryTitle,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppTokens.spaceSm),
          TextField(
            controller: _addLibraryNameController,
            decoration: InputDecoration(
              labelText: l10n.libraryNameHint,
              hintText: l10n.libraryNameHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          AppUrlInputBar(
            controller: _libraryUrlController,
            hintText: l10n.libraryUrlHint,
            submitLabel: l10n.subscribeLibrary,
            isLoading: false,
            onSubmit: (_) => _subscribeLibrary(),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(AppLocalizations l10n, ColorScheme scheme) {
    if (_loading) {
      return AppLoadingIndicator(message: l10n.loading);
    }
    if (_error != null) {
      return AppErrorState(
        message: _error!,
        onRetry: _retry,
        retryLabel: l10n.retry,
      );
    }
    if (_previews.isEmpty) return const SizedBox.shrink();

    // 单源：沿用原卡片样式
    if (_previews.length == 1) {
      final c = _previews.first;
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(c.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppTokens.spaceXs),
            Text(
              c.site.baseUrl,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            Chip(
              label: Text(_typeLabel(c.type, l10n)),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(height: AppTokens.spaceSm),
            Row(
              children: <Widget>[
                Icon(Icons.check_circle_rounded,
                    color: scheme.primary, size: 18),
                const SizedBox(width: AppTokens.spaceXs),
                Text(l10n.sourceImportValid),
              ],
            ),
            const SizedBox(height: AppTokens.spaceLg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                child: Text(l10n.save),
              ),
            ),
          ],
        ),
      );
    }

    // 批量：勾选列表 + 按类型导入
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.batchImportHint(_previews.length),
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: AppTokens.spaceSm),
          ..._previews.asMap().entries.map((e) {
            final i = e.key;
            final c = e.value;
            return CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              value: _selectedPreviewIndices.contains(i),
              onChanged: (v) {
                v == true ? AppHaptics.toggleOn() : AppHaptics.toggleOff();
                setState(() {
                  final set = <int>{..._selectedPreviewIndices};
                  if (v == true) {
                    set.add(i);
                  } else {
                    set.remove(i);
                  }
                  _selectedPreviewIndices = set;
                });
              },
              title: Text(c.name),
              subtitle: Text(
                '${c.site.baseUrl}  ·  ${_typeLabel(c.type, l10n)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              controlAffinity: ListTileControlAffinity.leading,
            );
          }),
          const SizedBox(height: AppTokens.spaceMd),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _selectedPreviewIndices.isEmpty ? null : _save,
              child: Text(
                l10n.importSelectedCount(_selectedPreviewIndices.length),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _typeLabel(SourceType type, AppLocalizations l10n) {
    return switch (type) {
      SourceType.novelSource => l10n.sourceTypeNovel,
      SourceType.animeSource => l10n.sourceTypeAnime,
      SourceType.videoSource => l10n.sourceTypeVideo,
      SourceType.audioSource => l10n.sourceTypeAudio,
      SourceType.mangaSource => l10n.sourceTypeManga,
    };
  }
}
