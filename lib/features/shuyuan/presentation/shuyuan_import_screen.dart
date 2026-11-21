/// 书源导入页：支持 URL / 本地文件 / JSON 文本三种方式导入书源。
///
/// 解析由 [ShuyuanSourceService] 完成，支持 JSON 数组 / 单对象 / 包装对象 /
/// XML / NDJSON 等常见格式；解析后预览列表，用户确认后批量转换为
/// [PluginConfig] 并写入 [SourceRepository]。
///
/// 规则表达力：`@css` / `@xpath` / `@json` / `@js` + `##` 正则替换（由
/// `lib/features/shuyuan/analyze/` 规则引擎在运行期解析）。
library;

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/services/source_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_error_state.dart';
import '../../../core/widgets/app_loading_indicator.dart';
import '../../../core/widgets/app_url_input_bar.dart';
import '../../../core/utils/app_haptics.dart';
import '../shuyuan_adapter.dart';
import '../shuyuan_source_service.dart';
import '../../../core/widgets/app_glass_bar.dart';

/// 书源导入方式。
enum _ShuyuanImportMode { url, file, json }

/// 书源导入页面。
class ShuyuanImportScreen extends StatefulWidget {
  const ShuyuanImportScreen({super.key});

  @override
  State<ShuyuanImportScreen> createState() => _ShuyuanImportScreenState();
}

class _ShuyuanImportScreenState extends State<ShuyuanImportScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _jsonController = TextEditingController();
  final ShuyuanSourceService _service = ShuyuanSourceService();

  _ShuyuanImportMode _mode = _ShuyuanImportMode.url;

  bool _loading = false;
  String? _error;
  List<ShuyuanSource> _parsed = const <ShuyuanSource>[];
  String? _pickedFileName;

  /// 多选导入：勾选的源 URL 集合（默认全选有效源）。
  final Set<String> _selectedUrls = <String>{};

  @override
  void dispose() {
    _urlController.dispose();
    _jsonController.dispose();
    _service.close();
    super.dispose();
  }

  // ── URL 导入 ──
  Future<void> _fetchFromUrl(String url) async {
    if (url.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _parsed = const <ShuyuanSource>[];
      _selectedUrls.clear();
    });
    try {
      final sources = await _service.fetchSourcesFromUrl(url);
      if (!mounted) return;
      _setParsed(sources);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ── 文件导入 ──
  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['json', 'txt', 'xml'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    _pickedFileName = result?.files.single.name;
    setState(() {
      _loading = true;
      _error = null;
      _parsed = const <ShuyuanSource>[];
      _selectedUrls.clear();
    });
    try {
      final sources = await _service.fetchSourcesFromFile(path);
      if (!mounted) return;
      _setParsed(sources);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ── JSON 文本导入 ──
  Future<void> _parseJson() async {
    final text = _jsonController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _parsed = const <ShuyuanSource>[];
      _selectedUrls.clear();
    });
    try {
      // 后台 isolate 解析：大书源列表（上千源）在主线程解析会冻结 UI。
      final sources = await ShuyuanSourceService.parseSourcesInBackground(text);
      if (!mounted) return;
      _setParsed(sources);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 设置解析结果并默认全选有效源。
  void _setParsed(List<ShuyuanSource> sources) {
    setState(() {
      _parsed = sources;
      _loading = false;
      _selectedUrls.clear();
      // 默认全选「文本类且有效」的书源；音频/图片/视频/文件类（legado
      // bookSourceType 1/2/3/4）在小说阅读器无法解析，预览标为不支持且不勾选。
      for (final s in sources) {
        if (s.isValid && _isNovelSupported(s)) {
          _selectedUrls.add(s.bookSourceUrl);
        }
      }
      if (sources.isEmpty) {
        _error = AppLocalizations.of(context).shuyuanImportParseFailed;
      }
    });
  }

  /// 小说阅读器仅支持文本书源（legado bookSourceType == 0）。
  /// 音频(1)/图片(2)/文件(3)/视频(4) 在小说模块无对应解析管线，导入亦无法使用。
  bool _isNovelSupported(ShuyuanSource s) => s.bookSourceType == 0;

  // ── 批量保存（仅保存勾选项） ──
  void _saveAll() {
    final repo = context.read<SourceRepository>();
    final l10n = AppLocalizations.of(context);
    final configs = _parsed
        .where((s) =>
            s.isValid &&
            _isNovelSupported(s) &&
            _selectedUrls.contains(s.bookSourceUrl))
        .map(ShuyuanAdapter.toPluginConfig)
        .toList();
    if (configs.isEmpty) return;

    // 批量入库：整批一次持久化 + 一次通知。逐个 addSource 时每源都全量
    // 重新序列化写盘并通知，上千源会冻结主线程数十秒甚至被系统杀死。
    final saved = repo.addSources(configs);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.shuyuanImportSuccess(saved))),
      );
      Navigator.of(context).pop(saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.shuyuanImportTitle)),
      body: Column(
        children: <Widget>[
          // 顶部说明
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceLg,
              vertical: AppTokens.spaceSm,
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.info_rounded,
                    size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: AppTokens.spaceXs),
                Expanded(
                  child: Text(
                    l10n.shuyuanImportHint,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          ),

          // 导入方式切换
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceLg,
            ),
            child: SegmentedButton<_ShuyuanImportMode>(
              segments: <ButtonSegment<_ShuyuanImportMode>>[
                ButtonSegment<_ShuyuanImportMode>(
                  value: _ShuyuanImportMode.url,
                  icon: const Icon(Icons.link_rounded, size: 18),
                  label: Text(l10n.shuyuanImportFromUrl),
                ),
                ButtonSegment<_ShuyuanImportMode>(
                  value: _ShuyuanImportMode.file,
                  icon: const Icon(Icons.file_present_rounded, size: 18),
                  label: Text(l10n.shuyuanImportFromFile),
                ),
                ButtonSegment<_ShuyuanImportMode>(
                  value: _ShuyuanImportMode.json,
                  icon: const Icon(Icons.code_rounded, size: 18),
                  label: Text(l10n.shuyuanImportFromJson),
                ),
              ],
              selected: <_ShuyuanImportMode>{_mode},
              onSelectionChanged: (Set<_ShuyuanImportMode> selection) {
                setState(() {
                  _mode = selection.first;
                  _error = null;
                });
              },
            ),
          ),

          const SizedBox(height: AppTokens.spaceMd),

          // 当前模式的输入区
          Expanded(
            child: _buildInputArea(l10n, scheme),
          ),
        ],
      ),
      // 底部「导入选中 N 项」按钮（仅当有勾选的源时显示）
      bottomNavigationBar: _selectedUrls.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.spaceLg),
                child: FilledButton.icon(
                  onPressed: _saveAll,
                  icon: const Icon(Icons.save_alt_rounded),
                  label: Text(
                    l10n.shuyuanImportSelected(_selectedUrls.length),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildInputArea(AppLocalizations l10n, ColorScheme scheme) {
    // 解析出预览列表后：输入区固定在顶部，列表用 builder 懒加载——
    // 大书源文件（上千源）一次性构建全部卡片会长时间冻结 UI 甚至 OOM。
    if (!_loading && _error == null && _parsed.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.spaceLg,
              0,
              AppTokens.spaceLg,
              AppTokens.spaceMd,
            ),
            child: switch (_mode) {
              _ShuyuanImportMode.url => _buildUrlInput(l10n),
              _ShuyuanImportMode.file => _buildFileInput(l10n, scheme),
              _ShuyuanImportMode.json => _buildJsonInput(l10n),
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.spaceLg,
              0,
              AppTokens.spaceLg,
              AppTokens.spaceSm,
            ),
            child: Text(
              l10n.shuyuanImportPreview(_parsed.length),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.fromLTRB(
                AppTokens.spaceLg,
                0,
                AppTokens.spaceLg,
                context.glassBarBottomInset,
              ),
              itemCount: _parsed.length,
              itemBuilder: (BuildContext context, int index) =>
                  _buildSourceCard(_parsed[index], scheme),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppTokens.spaceLg,
        0,
        AppTokens.spaceLg,
        context.glassBarBottomInset,
      ),
      children: <Widget>[
        switch (_mode) {
          _ShuyuanImportMode.url => _buildUrlInput(l10n),
          _ShuyuanImportMode.file => _buildFileInput(l10n, scheme),
          _ShuyuanImportMode.json => _buildJsonInput(l10n),
        },
        const SizedBox(height: AppTokens.spaceLg),
        if (_loading)
          AppLoadingIndicator(message: l10n.shuyuanImportParsing)
        else if (_error != null)
          AppErrorState(
            message: _error!,
            retryLabel: l10n.retry,
            onRetry: () {
              switch (_mode) {
                case _ShuyuanImportMode.url:
                  _fetchFromUrl(_urlController.text.trim());
                  break;
                case _ShuyuanImportMode.file:
                  _pickFile();
                  break;
                case _ShuyuanImportMode.json:
                  _parseJson();
                  break;
              }
            },
          )
        else
          _buildEmptyHint(l10n, scheme),
      ],
    );
  }

  // ── URL 输入 ──
  Widget _buildUrlInput(AppLocalizations l10n) {
    return AppUrlInputBar(
      controller: _urlController,
      hintText: l10n.shuyuanImportUrlHint,
      submitLabel: l10n.shuyuanImportParse,
      isLoading: _loading,
      onSubmit: _fetchFromUrl,
    );
  }

  // ── 文件选择 ──
  Widget _buildFileInput(AppLocalizations l10n, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FilledButton.icon(
          onPressed: _loading ? null : _pickFile,
          icon: const Icon(Icons.file_open_rounded),
          label: Text(l10n.shuyuanImportFilePicker),
        ),
        if (_pickedFileName != null) ...<Widget>[
          const SizedBox(height: AppTokens.spaceSm),
          Text(
            _pickedFileName!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.primary,
                ),
          ),
        ],
      ],
    );
  }

  // ── JSON 文本输入 ──
  Widget _buildJsonInput(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: _jsonController,
          maxLines: 10,
          decoration: InputDecoration(
            hintText: l10n.shuyuanImportJsonHint,
            prefixIcon: const Icon(Icons.code_rounded),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppTokens.spaceSm),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _loading ? null : _parseJson,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(l10n.shuyuanImportParse),
          ),
        ),
      ],
    );
  }

  Widget _buildSourceCard(ShuyuanSource source, ColorScheme scheme) {
    final novelSupported = _isNovelSupported(source);
    final isValid = source.isValid && novelSupported;
    final isSelected = _selectedUrls.contains(source.bookSourceUrl);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
      child: AppCard(
        child: Row(
          children: <Widget>[
            Checkbox(
              value: isSelected,
              onChanged: isValid
                  ? (bool? value) {
                      value == true
                          ? AppHaptics.toggleOn()
                          : AppHaptics.toggleOff();
                      setState(() {
                        if (value == true) {
                          _selectedUrls.add(source.bookSourceUrl);
                        } else {
                          _selectedUrls.remove(source.bookSourceUrl);
                        }
                      });
                    }
                  : null,
            ),
            Icon(
              isValid
                  ? Icons.check_circle_rounded
                  : (novelSupported
                      ? Icons.error_rounded
                      : Icons.block_rounded),
              size: 20,
              color: isValid
                  ? scheme.primary
                  : (novelSupported ? scheme.error : scheme.onSurfaceVariant),
            ),
            const SizedBox(width: AppTokens.spaceSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    source.bookSourceName.isEmpty
                        ? source.bookSourceUrl
                        : source.bookSourceName,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (source.bookSourceUrl.isNotEmpty)
                    Text(
                      source.bookSourceUrl,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (source.bookSourceGroup != null &&
                      source.bookSourceGroup!.isNotEmpty)
                    Text(
                      source.bookSourceGroup!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppTokens.spaceSm),
            Text(
              isValid
                  ? l10n.shuyuanImportValid
                  : (novelSupported
                      ? l10n.shuyuanImportInvalid
                      : l10n.shuyuanImportTypeUnsupported),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isValid
                        ? scheme.primary
                        : (novelSupported
                            ? scheme.error
                            : scheme.onSurfaceVariant),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 空提示 ──
  Widget _buildEmptyHint(AppLocalizations l10n, ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.menu_book_rounded,
              size: 64,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: AppTokens.spaceMd),
            Text(
              l10n.shuyuanImportEmpty,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
