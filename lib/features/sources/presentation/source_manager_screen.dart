/// 源管理页 —— 新版设计：Tab 式布局（源列表 / 源库 / 网络导入 / 本地导入）。
///
/// 支持按类型过滤，不同模块的源管理不互通。
/// 「源库」Tab 负责订阅第三方源仓库（index.json），并可进入库内挑选单个源导入。
library;

import 'dart:io';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/auth/source_auth_manager.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/settings/general_settings.dart';
import '../../../core/services/config_loader.dart';
import '../../../core/services/source_library_subscription.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/local/folder_import.dart';
import '../../../core/local/local_content_manager.dart' show isAndroidSafUri;
import '../../../core/local/saf_bridge.dart'
    show listFolderSourceFilesSaf, readSourceText, safBaseName;
import '../../../core/utils/app_log.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_glass_bar.dart';
import '../../../core/widgets/app_segmented_tabs.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_url_input_bar.dart';
import '../../../core/widgets/unified_source_tile.dart';
import 'source_import_preview_screen.dart';
import 'source_mirror_screen.dart';
import 'source_network_override_screen.dart';
import 'source_login_screen.dart';
import 'source_edit_screen.dart';
import 'package:nexhub/core/navigation/app_page_route.dart';
import 'package:nexhub/core/widgets/app_alert_dialog.dart';
import 'library_sources_screen.dart';
import 'collect_api_import_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/platform/platform_service.dart';

enum _SourceTab { list, library, network, local }

/// 源管理主页面。
class SourceManagerScreen extends StatefulWidget {
  /// 可选的类型过滤（null = 显示全部类型，用于设置页总入口）。
  final SourceType? filterType;

  /// 嵌入模式：为 [true] 时不包裹 Scaffold/AppBar/FAB，
  /// 仅输出 Tab 栏 + 内容区 Column，供各模块首页的 sourcesBody 使用。
  final bool embedded;

  /// 源列表 tab 顶部前置区块（如影视模块的媒体服务器配置区块）。
  /// 仅 [filterType] 非空的模块内列表生效；null = 无（其他模块不受影响）。
  final Widget? mediaServerSection;

  const SourceManagerScreen({
    super.key,
    this.filterType,
    this.embedded = false,
    this.mediaServerSection,
  });

  @override
  State<SourceManagerScreen> createState() => _SourceManagerScreenState();
}

class _SourceManagerScreenState extends State<SourceManagerScreen>
    with SingleTickerProviderStateMixin {
  _SourceTab _tab = _SourceTab.list;
  // 源列表 3 分类分段当前选中下标（0 小说 / 1 媒体 / 2 漫画）。
  int _category = 0;
  // 行 1（页面模式）下划线页签的指示条控制器：滑动动画归它管，
  // 内容切换仍由 [_tab] 驱动（onTap 与 [_switchTab] 双向同步）。
  late final TabController _modeTabCtrl = TabController(
    length: _SourceTab.values.length,
    vsync: this,
  );
  final TextEditingController _urlController = TextEditingController();

  // ── 长按拖动排序的实时断口跟踪 ──
  // Flutter 拖动时被拖项在列表内是透明占位（SizedBox），其余行平移让位；
  // 断口位置（_insertIndex）是框架内部状态，这里用同一套落点规则镜像
  // 计算，让断口两侧的行圆角随拖动实时更新。落下/取消全部清空。
  final Map<String, GlobalKey> _dragItemKeys = <String, GlobalKey>{};
  List<PluginConfig>? _dragSources; // 拖拽中的源列表（起始顺序）
  // 拖拽断口状态（被拖项起始下标 + 当前断口下标）。用 ValueNotifier 控制
  // 重建范围：拖起与断口变化只重建列表子树，不做整页 setState。
  final ValueNotifier<({int start, int gap})?> _dragGap =
      ValueNotifier<({int start, int gap})?>(null);
  double _pointerY = 0; // 最近一次指针 Y（Listener 记录）
  double _dragRefPointerY = 0; // 拖起时刻指针 Y（位移基准）
  double _dragOriginTopY = 0; // 被拖项起始 top（全局坐标）
  double _dragExtent = 0; // 被拖项高度（即断口宽度）
  Widget? _proxyTile; // 拖起时缓存的浮卡行内容（避免随指针逐帧重建）
  bool _autoScrollQueued = false; // 自动滚动帧回调是否已排队

  // 是否显示隐藏源
  bool _showHidden = false;

  // 网络导入状态
  bool _networkLoading = false;
  String? _networkError;
  PluginConfig? _networkPreview;
  List<String> _validationErrors = <String>[];
  final TextEditingController _collectApiUrlController =
      TextEditingController();

  // 因年龄限制被拦截（未进入导入预览）的 18+ 源数量，用于提示横幅。
  int _importAgeBlockedCount = 0;

  // 本地导入状态
  String? _pickedFileName;

  // 库（library）tab 状态
  final TextEditingController _libraryUrlController = TextEditingController();
  final TextEditingController _libraryNameController = TextEditingController();
  bool _librarySubscribing = false;

  @override
  void dispose() {
    _modeTabCtrl.dispose();
    _dragGap.dispose();
    _urlController.dispose();
    _libraryUrlController.dispose();
    _libraryNameController.dispose();
    _collectApiUrlController.dispose();
    super.dispose();
  }

  /// 程序化切换页面模式（空状态「去导入源」等入口）：同步内容 [_tab]
  /// 与页签指示条位置。
  void _switchTab(_SourceTab t) {
    setState(() => _tab = t);
    _modeTabCtrl.animateTo(t.index);
  }

  // ── 源列表 ──
  List<PluginConfig> _getFilteredSources(SourceRepository repo) {
    var sources = repo.all;
    if (widget.filterType != null) {
      sources = sources.where((c) => c.type == widget.filterType).toList();
    }
    // 隐藏源默认不显示，除非用户开启「显示隐藏源」
    if (!_showHidden) {
      sources = sources.where((c) => !c.isHidden).toList();
    }
    // 年龄限制开启时隐藏 18+ 源（无法管理 / 无法浏览）
    sources = sources.where((c) => !repo.isAgeBlocked(c)).toList();
    return sources;
  }

  /// 按分类 Tab 过滤源（项 7）。
  /// [category] 对应 Tab 索引：0=novel, 1=media, 2=comic。
  List<PluginConfig> _getCategorySources(
    List<PluginConfig> sources,
    int category,
  ) {
    switch (category) {
      case 0:
        return sources.where((c) => c.type == SourceType.novelSource).toList();
      case 1:
        // 媒体 Tab：animeSource（无 type 的旧源默认归 media，但 PluginConfig
        // 强制 type 非空，因此此处无需额外兜底）。
        return sources.where((c) => c.type == SourceType.animeSource).toList();
      case 2:
        return sources.where((c) => c.type == SourceType.mangaSource).toList();
      default:
        return sources;
    }
  }

  // ── 网络导入逻辑 ──
  Future<void> _fetchFromUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    final repo = context.read<SourceRepository>();

    setState(() {
      _networkLoading = true;
      _networkError = null;
      _networkPreview = null;
      _validationErrors = <String>[];
      _importAgeBlockedCount = 0;
    });

    try {
      // 这里需要 HttpFetcher，但为避免循环依赖，用基础的 HttpClient
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(Uri.parse(url));
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      httpClient.close();

      // 统一批量解析：URL 返回合并 JSON（小说+媒体+漫画）也能一次导入。
      final configs = SourceRepository.parseMixedSources(text);

      if (!mounted) return;
      if (configs.isEmpty) {
        setState(() {
          _networkError = AppLocalizations.of(context).sourceUnrecognized;
          _networkLoading = false;
        });
        return;
      }

      // 专属类型页：只保留匹配类型的源，其他类型直接忽略。
      final matched = widget.filterType == null
          ? configs
          : configs.where((c) => c.type == widget.filterType).toList();
      final skippedByType = configs.length - matched.length;

      // 年龄限制开启时，18+ 源不可导入
      final ageBlocked = matched.where((c) => repo.isAgeBlocked(c)).toList();
      final importable = matched.where((c) => !repo.isAgeBlocked(c)).toList();
      _importAgeBlockedCount = ageBlocked.length;

      if (importable.isEmpty) {
        final l10n = AppLocalizations.of(context);
        setState(() {
          _networkError = ageBlocked.isNotEmpty
              ? l10n.ageRestrictionImportMatureBlocked
              : (skippedByType > 0
                  ? l10n.importNoMatchingType(
                      importTypeLabel(widget.filterType!, l10n),
                      skippedByType,
                    )
                  : l10n.sourceUnrecognized);
          _networkLoading = false;
        });
        return;
      }

      if (importable.length == 1) {
        setState(() {
          _networkPreview = importable.first;
          _validationErrors = const <String>[];
          _networkLoading = false;
        });
      } else {
        // 多源：推入独立导入预览页批量勾选，确认后直接入库。
        final items = importable
            .map((c) => ImportPreviewItem(
                  path: '',
                  fileName: url,
                  config: c,
                  type: c.type,
                  isValid: true,
                ))
            .toList();
        if (!mounted) return;
        final selected =
            await Navigator.of(context).push<List<ImportPreviewItem>>(
          AppPageRoute<List<ImportPreviewItem>>(
            builder: (_) => SourceImportPreviewScreen(
              items: items,
              filterType: widget.filterType,
              skippedByTypeCount: skippedByType,
              ageBlockedCount: ageBlocked.length,
            ),
          ),
        );
        if (!mounted) return;
        setState(() => _networkLoading = false);
        if (selected == null || selected.isEmpty) return;
        _importSelected(selected);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _networkError = e.toString();
          _networkLoading = false;
        });
      }
    }
  }

  void _openCollectApiImport() {
    final url = _collectApiUrlController.text.trim();
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => CollectApiImportScreen(
          initialUrl: url.isEmpty ? null : url,
        ),
      ),
    );
  }

  void _saveNetworkSource() {
    if (_networkPreview == null || _validationErrors.isNotEmpty) return;
    context.read<SourceRepository>().addSource(_networkPreview!);
    setState(() {
      _urlController.clear();
      _networkPreview = null;
      _validationErrors = <String>[];
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).sourceImportSaved)),
    );
  }

  // ── 本地导入逻辑（支持文件 + 文件夹 + 预览勾选）──
  Future<void> _pickLocalFile() async {
    // 支持选择单个文件或文件夹
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['json', 'txt', 'xml'],
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;

    _processPickedPaths(
        result.files.map((f) => f.path).whereType<String>().toList());
  }

  /// 选择文件夹导入。
  Future<void> _pickLocalFolder() async {
    // Android 必须用 FolderImport.pick（内部走 saf.pickDirectory 拿 content:// tree URI）；
    // 鸿蒙 PC 走系统目录选择并复制进沙箱；其余平台为真实路径。
    final dirPath = await FolderImport.pick(context);
    if (dirPath == null) {
      AppLog.instance.i('[源导入] 未选择文件夹（picker 返回 null）');
      return;
    }
    // 记录原始路径前缀 + 是否 SAF，便于在「运行日志」定位（之前日志为空的根因：
    // 空结果分支从未打日志，导致静默误报「未找到源文件」）。
    AppLog.instance.i('[源导入] 选目录 raw='
        '${dirPath.length > 90 ? '${dirPath.substring(0, 90)}…' : dirPath} '
        'isSaf=${isAndroidSafUri(dirPath)}');

    // 扫描目录下的所有支持的源文件。
    // Android 上 getDirectoryPath 返回 content:// SAF tree URI，dart:io 的
    // Directory 无法列举/读取，必须走 SAF 枚举；桌面则走真实文件系统。
    List<String> files;
    try {
      if (isAndroidSafUri(dirPath)) {
        files = await listFolderSourceFilesSaf(dirPath);
        AppLog.instance.i('[源导入] SAF 枚举得到 ${files.length} 个源文件');
      } else {
        final dir = Directory(dirPath);
        final exists = await dir.exists();
        AppLog.instance.i('[源导入] 文件系统模式 dir.exists=$exists');
        if (!exists) {
          // 目录不存在/不可访问（安卓分区存储下真实路径常读不到）→ 如实上报，
          // 不再静默 return 造成「未找到源文件」误报。
          AppLog.instance.e('[源导入] 目录不存在或不可访问: $dirPath');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(AppLocalizations.of(context).folderScanFailed)),
            );
          }
          return;
        }
        files = <String>[];
        await for (final entity
            in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            final ext =
                p.extension(entity.path).toLowerCase().replaceFirst('.', '');
            if (const ['json', 'txt', 'xml'].contains(ext)) {
              files.add(entity.path);
            }
          }
        }
        AppLog.instance.i('[源导入] 文件系统枚举得到 ${files.length} 个源文件');
      }
    } on Object catch (e, st) {
      // SAF 列举失败（权限不足 / URI 无效 / SecurityException）必须如实上报，
      // 不能静默当作「未找到源文件」。
      AppLog.instance.eWithStack('[源导入] 文件夹扫描失败 $dirPath', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context).folderScanFailed)),
        );
      }
      return;
    }

    if (files.isEmpty) {
      AppLog.instance.w('[源导入] 扫描结果为空（未找到源文件）dirPath='
          '${dirPath.length > 90 ? '${dirPath.substring(0, 90)}…' : dirPath}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).noLocalSource)),
        );
      }
      return;
    }

    _processPickedPaths(files);
  }

  /// 处理选中的文件路径列表：解析预览 → 弹出勾选对话框 → 导入选中项。
  Future<void> _processPickedPaths(List<String> paths) async {
    final repo = context.read<SourceRepository>();
    final items = <ImportPreviewItem>[];
    _importAgeBlockedCount = 0;
    for (final path in paths) {
      final fileName =
          isAndroidSafUri(path) ? safBaseName(path) : p.basename(path);
      try {
        final text = await readSourceText(path);
        // 统一批量解析：单 PluginConfig / JSON 数组（小说+媒体+漫画混排）/
        // 通用书源格式 / XML 等，一个文件可解析出多个源。
        final configs = SourceRepository.parseMixedSources(text);
        if (configs.isEmpty) {
          items.add(ImportPreviewItem(
            path: path,
            fileName: fileName,
            config: null,
            type: widget.filterType,
            isValid: false,
            error: AppLocalizations.of(context).sourceUnrecognized,
          ));
        } else {
          for (final c in configs) {
            // 年龄限制开启时，18+ 源不可导入
            if (repo.isAgeBlocked(c)) {
              _importAgeBlockedCount++;
              continue;
            }
            items.add(ImportPreviewItem(
              path: path,
              fileName: fileName,
              config: c,
              type: c.type,
              isValid: true,
            ));
          }
        }
      } on Object catch (e) {
        AppLog.instance.e('[源导入] 读取/解析失败 $fileName: $e');
        items.add(ImportPreviewItem(
          path: path,
          fileName: fileName,
          config: null,
          type: null,
          isValid: false,
          error: e.toString(),
        ));
      }
    }

    // 专属类型页（filterType != null）：只保留该类型的源，其他类型直接忽略。
    int skippedByType = 0;
    List<ImportPreviewItem> shownItems = items;
    if (widget.filterType != null) {
      final kept = <ImportPreviewItem>[];
      for (final it in items) {
        if (it.config != null && it.type != widget.filterType) {
          // 有效但类型不符 → 直接忽略，计入跳过数
          skippedByType++;
        } else {
          // 无效（解析失败，用于错误提示）或类型匹配 → 保留
          kept.add(it);
        }
      }
      shownItems = kept;
    }

    if (!mounted) return;

    // 年龄限制：所有可解析源均为 18+ → 直接提示，不进入预览
    if (_importAgeBlockedCount > 0 &&
        shownItems.where((e) => e.isValid).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)
                .ageRestrictionImportMatureBlocked)),
      );
      return;
    }

    if (items.isEmpty) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.sourceUnrecognized)),
      );
      return;
    }

    // 专属类型页：过滤后没有任何可显示源（全部为其他类型）→ 提示并退出预览。
    if (widget.filterType != null && shownItems.isEmpty && skippedByType > 0) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.importNoMatchingType(
            importTypeLabel(widget.filterType!, l10n),
            skippedByType,
          )),
        ),
      );
      return;
    }

    // 推入独立预览页勾选，确认后回传选中项并入库。
    // 页面盖住整个屏幕，外层 FAB / 导航不再需要联动隐藏。
    setState(() => _pickedFileName = null);
    final selected = await Navigator.of(context).push<List<ImportPreviewItem>>(
      AppPageRoute<List<ImportPreviewItem>>(
        builder: (_) => SourceImportPreviewScreen(
          items: shownItems,
          filterType: widget.filterType,
          skippedByTypeCount: skippedByType,
          ageBlockedCount: _importAgeBlockedCount,
        ),
      ),
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    _importSelected(selected);
  }

  /// 确认导入选中的预览项（由独立预览页回传）。
  void _importSelected(List<ImportPreviewItem> selected) {
    int successCount = 0;
    for (final item in selected) {
      try {
        context.read<SourceRepository>().addSource(item.config!);
        successCount++;
      } on Object {/* 单个失败不影响其他 */}
    }

    if (mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.sourceImportResult(successCount, selected.length)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final repo = context.watch<SourceRepository>();
    final filteredSources = _getFilteredSources(repo);

    // 嵌入模式：直接返回 Tab 内容（由外层 LibraryShell 提供 Scaffold/FAB）。
    if (widget.embedded) return _buildBody(l10n, scheme, filteredSources);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.sourceManagementTitle),
        actions: <Widget>[
          IconButton(
            icon: Icon(
              _showHidden
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
            ),
            tooltip: l10n.sourceShowHidden,
            onPressed: () => setState(() => _showHidden = !_showHidden),
          ),
        ],
      ),
      body: _buildBody(l10n, scheme, filteredSources),
    );
  }

  /// 构建主体内容（Tab 栏 + 内容区），供嵌入模式和完整模式共用。
  Widget _buildBody(AppLocalizations l10n, ColorScheme scheme,
      List<PluginConfig> filteredSources) {
    // 顶部 Tab 切换：仅总管理（filterType == null，设置页入口）用下划线
    // 文字页签；分区页面（各模块主页「源」页签嵌入）保留原胶囊分段样式
    // （2026-10-04 定稿：格式互换只做总管理，分区还原）。
    final bool isMaster = widget.filterType == null;
    return Column(
      children: <Widget>[
        if (isMaster)
          Material(
            color: scheme.surface,
            child: TabBar(
              controller: _modeTabCtrl,
              onTap: (int i) {
                AppHaptics.selectionClick();
                if (_tab.index != i) {
                  setState(() => _tab = _SourceTab.values[i]);
                }
              },
              tabs: <Widget>[
                Tab(text: l10n.sourceListTab),
                Tab(text: l10n.libraryBookmarks),
                Tab(text: l10n.networkImportTab),
                Tab(text: l10n.localImportTab),
              ],
            ),
          )
        else ...<Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceLg,
              vertical: AppTokens.spaceSm,
            ),
            child: AppSegmentedTabs<_SourceTab>(
              selected: <_SourceTab>{_tab},
              onSelectionChanged: (sel) {
                if (sel.isNotEmpty) {
                  setState(() => _tab = sel.first);
                }
              },
              segments: <ButtonSegment<_SourceTab>>[
                ButtonSegment<_SourceTab>(
                  value: _SourceTab.list,
                  icon: const Icon(Icons.list_rounded),
                  label: Text(l10n.sourceListTab),
                ),
                ButtonSegment<_SourceTab>(
                  value: _SourceTab.library,
                  icon: const Icon(Icons.cloud_rounded),
                  label: Text(l10n.libraryBookmarks),
                ),
                ButtonSegment<_SourceTab>(
                  value: _SourceTab.network,
                  icon: const Icon(Icons.cloud_download_rounded),
                  label: Text(l10n.networkImportTab),
                ),
                ButtonSegment<_SourceTab>(
                  value: _SourceTab.local,
                  icon: const Icon(Icons.file_present_rounded),
                  label: Text(l10n.localImportTab),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
        ],

        // Tab 内容
        Expanded(
          child: <Widget>[
            _buildListTab(l10n, filteredSources, scheme),
            _buildLibraryTab(l10n, scheme),
            _buildNetworkImportTab(l10n, scheme),
            _buildLocalImportTab(l10n, scheme),
          ][_tab.index],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Tab 1: 源列表
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildListTab(
    AppLocalizations l10n,
    List<PluginConfig> sources,
    ColorScheme scheme,
  ) {
    // 若指定了 filterType（从模块设置页进入），直接显示单列表，不加分类 Tab。
    if (widget.filterType != null) {
      final section = widget.mediaServerSection;
      if (sources.isEmpty) {
        if (section == null) {
          return AppEmptyState(
            icon: Icons.extension_rounded,
            message: l10n.sourceListEmpty,
            actionLabel: l10n.addSource,
            onAction: () => _switchTab(_SourceTab.network),
            secondaryActionLabel: l10n.enableRecommendedSources,
            onSecondaryAction: () => _enableRecommended(l10n),
          );
        }
        // 有前置区块（媒体服务器配置）时，空状态放在区块下方仍可达。
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spaceMd,
                AppTokens.spaceXs,
                AppTokens.spaceMd,
                0,
              ),
              child: section,
            ),
            Expanded(
              child: AppEmptyState(
                icon: Icons.extension_rounded,
                message: l10n.sourceListEmpty,
                actionLabel: l10n.addSource,
                onAction: () => _switchTab(_SourceTab.network),
                secondaryActionLabel: l10n.enableRecommendedSources,
                onSecondaryAction: () => _enableRecommended(l10n),
              ),
            ),
          ],
        );
      }
      return SingleChildScrollView(
        // 媒体服务器区块与源列表并入同一条滚动流：列表 shrinkWrap 撑开、
        // 滚动交给外层，区块不再固定在顶部，而是跟着列表一起滚走。
        child: Column(
          children: <Widget>[
            if (section != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.spaceMd,
                  AppTokens.spaceXs,
                  AppTokens.spaceMd,
                  0,
                ),
                child: section,
              ),
            _buildSourceListView(l10n, sources, scrollsWithParent: true),
          ],
        ),
      );
    }

    // filterType == null（设置页总入口）：3 分类胶囊分段（与页面模式行的
    // 下划线页签互换后的格式），内容按下标直接切换（不再走 TabBarView，
    // 分类间不再支持横滑）。
    return Column(
      children: <Widget>[
        if (sources.isNotEmpty) _buildEnableRecommendedTile(l10n),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceLg,
            vertical: AppTokens.spaceSm,
          ),
          child: AppSegmentedTabs<int>(
            selected: <int>{_category},
            onSelectionChanged: (sel) {
              if (sel.isNotEmpty) {
                setState(() => _category = sel.first);
              }
            },
            segments: <ButtonSegment<int>>[
              ButtonSegment<int>(
                value: 0,
                icon: const Icon(Icons.book_rounded),
                label: Text(l10n.sourceCategoryNovel),
              ),
              ButtonSegment<int>(
                value: 1,
                icon: const Icon(Icons.movie_rounded),
                label: Text(l10n.sourceCategoryMedia),
              ),
              ButtonSegment<int>(
                value: 2,
                icon: const Icon(Icons.image_rounded),
                label: Text(l10n.sourceCategoryComic),
              ),
            ],
          ),
        ),
        Expanded(
          child: <Widget>[
            _buildCategoryList(l10n, _getCategorySources(sources, 0),
                l10n.sourceCategoryNovel),
            _buildCategoryList(l10n, _getCategorySources(sources, 1),
                l10n.sourceCategoryMedia),
            _buildCategoryList(l10n, _getCategorySources(sources, 2),
                l10n.sourceCategoryComic),
          ][_category],
        ),
      ],
    );
  }

  /// 构建单个分类下的源列表（含空状态）。
  Widget _buildCategoryList(
    AppLocalizations l10n,
    List<PluginConfig> sources,
    String categoryLabel,
  ) {
    if (sources.isEmpty) {
      return AppEmptyState(
        icon: Icons.extension_rounded,
        message: l10n.sourceCategoryEmpty(categoryLabel),
        actionLabel: l10n.addSource,
        onAction: () => _switchTab(_SourceTab.network),
      );
    }
    return _buildSourceListView(l10n, sources);
  }

  /// 构建源列表 ListView（复用于单列表与分类 Tab）。
  /// 「设置分组同款强调色连体卡」由各行**分段底色**拼成（首末行补圆角、
  /// 行间发丝分隔线），外层只做视口圆角裁剪——有源的地方铺色、没有的
  /// 地方不铺，滚动中屏幕边缘也始终圆滑。拖拽时连体卡在被拖行处**断开
  /// 成两个圆角卡**，断口随拖动实时跟手（见 [_updateLiveGap]），回落
  /// 融为一体。无拖拽手柄，行内**长按**启动拖动排序。
  ///
  /// [scrollsWithParent] 为 true 时（媒体服务器区块并入滚动流的场景）：
  /// 列表 `shrinkWrap` 撑开全部行 + `NeverScrollableScrollPhysics` 把滚动
  /// 让给外层 [SingleChildScrollView]，自身不再截留手势。
  Widget _buildSourceListView(
    AppLocalizations l10n,
    List<PluginConfig> sources, {
    bool scrollsWithParent = false,
  }) {
    // 监听登录态：源登录/登出后列表实时刷新「未登录」徽章（项 2）。
    final SourceAuthManager auth = context.watch<SourceAuthManager>();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    // 低配开关（默认低配）：关闭「断卡」动效时整表为一张静态强调色卡
    // （首次对话版式），无分段、无断开，仅浮起强调色浮卡。
    final bool lowSpec =
        !GeneralSettingsStore.instance.settings.sourceDragSplitEffect;
    // 断口状态用 ValueNotifier 控制重建范围：拖起与断口变化只重建列表
    // 子树（[_buildReorderableList]），不做整页 setState，长按拖动更顺滑。
    final Widget list = ValueListenableBuilder<({int start, int gap})?>(
      valueListenable: _dragGap,
      builder: (context, drag, _) => _buildReorderableList(
        l10n,
        auth,
        scheme,
        sources,
        scrollsWithParent,
        lowSpec,
        drag,
      ),
    );
    // 视口处理：高配=透明圆角裁剪（滚动中边缘圆滑，卡底由行段自绘）；
    // 低配=整表一张静态强调色圆角卡（首次对话版式），左右 12px 与前置
    // 区块对齐。底栏/安全区避让量必须留在卡外：低配卡底由 Material 铺在
    // 整张列表（含其内边距）之下，避让量若算进列表 padding，最后一行到
    // 底栏之间的无源区域会被整体涂成强调色（鸿蒙等移动端 extendBody
    // 注入的避让高度可达整条底栏）。Listener 记录指针位置驱动断口重算与
    // 边缘自动滚动（[_maybeAutoScroll]）；滚动通知覆盖框架内置自动滚动
    // 场景的断口同步。开关即时生效：监听通用设置，切换后无需重进页面。
    return ListenableBuilder(
      listenable: GeneralSettingsStore.instance,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (PointerDownEvent e) => _pointerY = e.position.dy,
        onPointerMove: (PointerMoveEvent e) {
          _pointerY = e.position.dy;
          _updateLiveGap();
          _maybeAutoScroll();
        },
        // 框架取消拖拽（系统手势等）不走 onReorderEnd，这里兜底复位。
        onPointerCancel: (PointerCancelEvent e) => _endDrag(),
        child: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification n) {
            // 框架内置自动滚动引起的滚动也要同步断口圆角。
            _updateLiveGap();
            return false;
          },
          child: lowSpec
              ? Align(
                  // 外层（Expanded/TabBarView）给的是「必须撑满视口」的紧约束，
                  // 会把 shrinkWrap 的收缩顶回去，导致整卡把末行以下的无源空白
                  // 也裹进卡底色。Align 把约束放松成「至多这么大」，卡即可按
                  // 内容收缩、靠顶对齐；行数超出视口时仍在卡内正常滚动。
                  alignment: Alignment.topCenter,
                  child: Padding(
                    // 顶部留 8px 与媒体服务器等前置区块分开：卡内的顶部留白
                    // 属于卡底色，不构成两张卡之间的间隔。底部避让量加在卡
                    // 外，卡底只包有源的行。
                    padding: const EdgeInsets.fromLTRB(
                          AppTokens.spaceMd,
                          AppTokens.spaceSm,
                          AppTokens.spaceMd,
                          0,
                        ) +
                        context.glassBarInset,
                    child: Material(
                      color: AppTheme.cardContainer(scheme),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: list,
                    ),
                  ),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                  child: list,
                ),
        ),
      ),
      builder: (context, child) => child!,
    );
  }

  /// ReorderableListView 本体。断口状态 [drag] 变化时仅此子树重建，
  /// 断口两侧行的圆角随拖动实时更新（平移映射见内注释）。
  /// [lowSpec] 为 true（默认，设置关闭「断卡」动效）：整表一张静态强调色
  /// 卡（首次对话版式），无分段、无断开，拖动中卡片完全不动。
  Widget _buildReorderableList(
    AppLocalizations l10n,
    SourceAuthManager auth,
    ColorScheme scheme,
    List<PluginConfig> sources,
    bool scrollsWithParent,
    bool lowSpec,
    ({int start, int gap})? drag,
  ) {
    // 断口两侧行的下标（拖拽中由 [_updateLiveGap] 实时更新）。
    // SDK 平移规则：g<d 时 [g,d) 各行下移一格、g>d 时 (d,g) 各行上移一格，
    // 故视觉断口槽位 gapSlot = g<=d ? g : g-1；两侧行按平移映射还原。
    // 未拖拽时 d、g 置 -1（不与任何行下标匹配）。低配模式一律 -1（不动）。
    final int dd = drag?.start ?? -1;
    final int gg = drag?.gap ?? -1;
    final bool dragging = drag != null;
    final int gapSlot = dragging ? (gg <= dd ? gg : gg - 1) : 0;
    final int aboveGapItem =
        (!dragging || lowSpec) ? -1 : (gg > dd + 1 ? gapSlot : gapSlot - 1);
    final int belowGapItem = (!dragging || lowSpec)
        ? -1
        : (gg < dd && gapSlot + 1 <= dd ? gapSlot : gapSlot + 1);
    return ReorderableListView(
      // 低配（默认）：整卡为一张静态强调色卡（首次对话版式），行内容平铺，
      // 卡自身左右 12px 与媒体服务器等前置区块对齐；底栏避让由外层卡片
      // Padding 承担（卡内只留设计留白，避免无源空白被涂成卡底色）。
      // 高配：分段底色在缩进区内拼成整卡，避让量留在列表内供滚动穿透。
      padding: lowSpec
          ? const EdgeInsets.fromLTRB(
              0,
              AppTokens.spaceSm,
              0,
              AppTokens.spaceMd,
            )
          : const EdgeInsets.fromLTRB(
                AppTokens.spaceMd,
                AppTokens.spaceSm,
                AppTokens.spaceMd,
                AppTokens.spaceMd,
              ) +
              context.glassBarInset,
      // 媒体服务器区块场景：列表全部行直接撑开，滚动交给外层容器。
      // 低配整卡模式同理收成内容高度：卡底只包住有源的行，末行以下的
      // 空白区不再被强调色卡裹住（高配行段自绘本就如此）。
      shrinkWrap: scrollsWithParent || lowSpec,
      physics: scrollsWithParent ? const NeverScrollableScrollPhysics() : null,
      // 禁用默认拖动手柄：拖动改由行内长按接管，行首不再被把手占位。
      buildDefaultDragHandles: false,
      // 拖起浮卡：强调色底 + 圆角 + 单层投影（无缩放/位移/描边）。
      // 不能用传入 child：它在拖拽态重建前就被捕获，自带方角行底，会盖住
      // 浮卡样式；这里用同一份配置现建一个无底色行内容。
      proxyDecorator: (Widget child, int index, Animation<double> animation) {
        final Color dragBg = Color.alphaBlend(
          scheme.primaryContainer.withValues(alpha: 0.5),
          AppTheme.cardContainer(scheme),
        );
        return AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            final double t = Curves.easeOut.transform(animation.value);
            return DecoratedBox(
              decoration: BoxDecoration(
                color: dragBg,
                borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                boxShadow: <BoxShadow>[
                  // 阴影随拖拽进度渐入，先快后缓。
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: 0.26 * t),
                    blurRadius: 16 * t + 4,
                    offset: Offset(0, 7 * t + 2),
                  ),
                ],
              ),
              // 拖起时缓存的行内容：代理随指针每帧重建，行内容只建一次。
              // 松手后的回落动画每帧仍会走到这里（_dragGap 已空），故不判空。
              child: _proxyTile ?? child,
            );
          },
        );
      },
      // 拖起：记录被拖项几何与指针基准，断口从起始位开始跟随；落下：
      // 清空，行圆角复位、融回连体卡。全程不整页 setState。
      onReorderStart: (int index) {
        // MD3「Thunk」：拖拽拿起。
        AppHaptics.thunk();
        final Rect? r = _dragItemRect(sources[index].id);
        _proxyTile = _sourceTile(l10n, auth, sources[index]);
        _dragSources = sources;
        _dragOriginTopY = r?.top ?? 0;
        _dragExtent = r?.height ?? 0;
        _dragRefPointerY = _pointerY;
        _dragGap.value = (start: index, gap: index);
      },
      onReorderEnd: (int index) => _endDrag(),
      onReorderItem: (int oldIndex, int newIndex) {
        final ids = sources.map((s) => s.id).toList();
        final moved = ids.removeAt(oldIndex);
        ids.insert(newIndex, moved);
        context.read<SourceRepository>().setSourceOrder(ids);
      },
      children: <Widget>[
        for (final (i, s) in sources.indexed)
          KeyedSubtree(
            // GlobalKey 供拖拽中实时量取行矩形（镜像落点规则用）。
            key: _dragKey(s.id),
            child: lowSpec
                ? // 低配（默认）：行内容平铺在整卡上，无分段底色、无圆角。
                Column(
                    children: <Widget>[
                      if (i > 0)
                        const Divider(
                          height: 1,
                          thickness: 1,
                          indent: AppTokens.spaceLg,
                          endIndent: AppTokens.spaceLg,
                        ),
                      ReorderableDelayedDragStartListener(
                        index: i,
                        child: _sourceTile(l10n, auth, s),
                      ),
                    ],
                  )
                : Container(
                    key: Key(s.id),
                    decoration: BoxDecoration(
                      // 分段底色拼出连体卡；列表内被拖项由框架隐藏为透明占位。
                      color: AppTheme.cardContainer(scheme),
                      borderRadius: BorderRadius.vertical(
                        top: (i == 0 || i == belowGapItem)
                            ? const Radius.circular(AppTokens.radiusLg)
                            : Radius.zero,
                        bottom: (i == sources.length - 1 || i == aboveGapItem)
                            ? const Radius.circular(AppTokens.radiusLg)
                            : Radius.zero,
                      ),
                    ),
                    child: Column(
                      children: <Widget>[
                        // 发丝分隔线随行携带（与设置分组一致），首行无线。
                        if (i > 0)
                          const Divider(
                            height: 1,
                            thickness: 1,
                            indent: AppTokens.spaceLg,
                            endIndent: AppTokens.spaceLg,
                          ),
                        // 长按整行启动拖动；开关/「更多」菜单等控件自身手势
                        // 优先，点击行为不受影响。
                        ReorderableDelayedDragStartListener(
                          index: i,
                          child: _sourceTile(l10n, auth, s),
                        ),
                      ],
                    ),
                  ),
          ),
      ],
    );
  }

  /// 源行内容（列表行与拖拽浮卡共用）：无自带卡底，底色由外层提供。
  Widget _sourceTile(
    AppLocalizations l10n,
    SourceAuthManager auth,
    PluginConfig s,
  ) {
    return UnifiedSourceTile(
      name: s.name,
      url: s.site.baseUrl,
      enabled: s.isEnabled,
      deprecated: s.isDeprecated,
      ageRating: s.ageRating,
      isHidden: s.isHidden,
      // 项 2：仅对声明了登录入口、且当前未登录的源显示「未登录」。
      showNotLoggedIn: s.comments?.supportsLogin == true && !auth.isLoggedIn(s),
      deprecatedLabel: l10n.deprecated,
      mirrorSettingsTooltip: l10n.mirrorSettings,
      hideTooltip: l10n.sourceHide,
      unhideTooltip: l10n.sourceShowHidden,
      editTooltip: l10n.sourceEdit,
      deleteTooltip: l10n.sourceDelete,
      migrateTooltip: l10n.sourceMigrate,
      networkOverrideTooltip: l10n.sourceNetworkOverride,
      loginTooltip: l10n.sourceLogin,
      // 源管理页：操作收进「更多」菜单，更清爽
      useMoreMenu: true,
      moreMenuTooltip: l10n.moreActions,
      isIncognito: ConfigLoader.instance.isIncognito(s),
      incognitoTooltip: l10n.incognitoMode,
      incognitoOnLabel: l10n.incognitoModeOn,
      onIncognitoToggle: (bool value) async {
        await ConfigLoader.instance.setIncognito(s.id, value);
        if (mounted) {
          setState(() {});
          // 明确回显切换结果：无痕开启/关闭后源行外观不变，仅靠菜单项
          // 状态难以确认是否生效。
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(value
                  ? l10n.incognitoOnToast
                  : l10n.incognitoOffToast),
            ),
          );
        }
      },
      onToggle: (bool value) =>
          context.read<SourceRepository>().setEnabled(s.id, value),
      onMirrorSettings: () => Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (_) => SourceMirrorScreen(source: s),
        ),
      ),
      onNetworkOverride: () => Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (_) => SourceNetworkOverrideScreen(source: s),
        ),
      ),
      onLogin: () => Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (_) => SourceLoginScreen(source: s),
        ),
      ),
      onHide: () =>
          context.read<SourceRepository>().setHidden(s.id, !s.isHidden),
      onEdit: () => _showEditDialog(s),
      onDelete: () => _showDeleteConfirm(s),
      onMigrate:
          s.migrationMessage != null ? () => _showMigrateDialog(s) : null,
    );
  }

  GlobalKey _dragKey(String id) => _dragItemKeys.putIfAbsent(id, GlobalKey.new);

  Rect? _dragItemRect(String id) {
    final BuildContext? ctx = _dragItemKeys[id]?.currentContext;
    if (ctx == null) return null;
    final RenderObject? ro = ctx.findRenderObject();
    if (ro is! RenderBox || !ro.attached) return null;
    return ro.localToGlobal(Offset.zero) & ro.size;
  }

  void _endDrag() {
    if (_dragGap.value == null) return;
    _dragSources = null;
    // _proxyTile 不清空：松手后浮卡还有约 250ms 回落动画，期间代理每帧
    // 仍会重建（此时 _dragGap 已空），清空会触发「Null check operator」
    // 崩溃；缓存会在下一次拖起时整体覆盖。
    _dragGap.value = null;
  }

  /// 镜像 SliverReorderableList._dragUpdateItems 的落点规则
  /// （vertical / 非 reverse）：以「浮卡起止边 vs 各行实时矩形」求出
  /// 断口下标，驱动断口两侧行圆角随拖动更新。由拖拽期间的逐帧核对
  /// （[_queueGapCheck]）触发，指针移动与列表自动滚动都覆盖。
  void _updateLiveGap() {
    // 低配模式：不做实时断口（卡片不动，仅拖起/松手时变化）。
    if (!GeneralSettingsStore.instance.settings.sourceDragSplitEffect) {
      return;
    }
    final List<PluginConfig>? sources = _dragSources;
    final ({int start, int gap})? drag = _dragGap.value;
    if (sources == null || drag == null) return;
    final double proxyStart = _dragOriginTopY + (_pointerY - _dragRefPointerY);
    final double proxyEnd = proxyStart + _dragExtent;
    int newIndex = drag.gap;
    for (int i = 0; i < sources.length; i++) {
      if (i == drag.start) {
        // 被拖项的 GlobalKey 已随浮卡重挂载到 Overlay，量不到原始槽位，
        // 直接用拖起时捕获的几何：浮卡末边回到原槽位后半段时断口回起点。
        final double itemMiddle = _dragOriginTopY + _dragExtent / 2;
        final double itemEnd = _dragOriginTopY + _dragExtent;
        if (itemMiddle <= proxyEnd && proxyEnd <= itemEnd) newIndex = i;
        continue;
      }
      final Rect? r = _dragItemRect(sources[i].id);
      if (r == null) continue;
      final double itemStart = r.top;
      final double itemEnd = r.bottom;
      final double itemMiddle = r.top + r.height / 2;
      if (itemStart <= proxyStart && proxyStart <= itemMiddle) {
        // 浮卡起边进入该行前半段：断口换到该行之前。
        newIndex = i;
        break;
      }
      if (itemMiddle <= proxyEnd && proxyEnd <= itemEnd) {
        // 浮卡末边进入该行后半段：断口换到该行之后。
        newIndex = i + 1;
        break;
      }
      if (itemEnd < proxyStart && newIndex < i + 1) {
        newIndex = i + 1;
      } else if (proxyEnd < itemStart && newIndex > i) {
        newIndex = i;
      }
    }
    if (newIndex != drag.gap) {
      _dragGap.value = (start: drag.start, gap: newIndex);
    }
  }

  /// 拖拽自动滚动。正常流程由框架内置的 EdgeDraggingAutoScroller 负责，
  /// 这里只在它失效时接管：内层列表为 NeverScrollable（shrinkWrap 并入
  /// 外层滚动流）时，内置滚动被 physics 门禁停用，改为滚动外层容器。
  /// 指针贴近视口上下边缘时逐帧步进滚动，离开边缘或拖拽结束自动停止。
  void _maybeAutoScroll() {
    if (_autoScrollQueued) return;
    _autoScrollQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoScrollQueued = false;
      if (!mounted || _dragGap.value == null) return;
      // 先用上一帧滚动后的新矩形重算断口，再滚下一步（jumpTo 当帧不重排）。
      _updateLiveGap();
      if (_scrollTowardEdge()) {
        _maybeAutoScroll();
      }
    });
  }

  /// 向指针所在的边缘滚动一步；返回指针是否仍在边缘触发区内。
  bool _scrollTowardEdge() {
    final List<PluginConfig>? sources = _dragSources;
    final int? d = _dragGap.value?.start;
    if (sources == null || d == null || d >= sources.length) return false;
    // 锚点取一个仍在列表内的行：被拖项的 GlobalKey 已随浮卡挂到 Overlay，
    // 那条链上没有滚动容器。
    BuildContext? anchorCtx;
    for (final PluginConfig s in sources) {
      if (s.id == sources[d].id) continue;
      final BuildContext? c = _dragItemKeys[s.id]?.currentContext;
      if (c != null && c.mounted) {
        anchorCtx = c;
        break;
      }
    }
    if (anchorCtx == null) return false;
    ScrollableState? s = Scrollable.maybeOf(anchorCtx);
    // 框架内置自动滚动可用时交给框架（避免双重滚动）。
    if (s != null &&
        (s.resolvedPhysics?.shouldAcceptUserOffset(s.position) ?? true)) {
      return false;
    }
    // 内层不可滚（NeverScrollable）：向外找第一个有可滚行程的容器。
    while (
        s != null && s.position.maxScrollExtent <= s.position.minScrollExtent) {
      s = Scrollable.maybeOf(s.context);
    }
    if (s == null) return false;
    final RenderBox box = s.context.findRenderObject()! as RenderBox;
    final Rect viewport = box.localToGlobal(Offset.zero) & box.size;
    const double edgeZone = 80;
    const double maxStep = 14;
    final double y = _pointerY;
    final double pixels = s.position.pixels;
    double? target;
    if (y < viewport.top + edgeZone && pixels > s.position.minScrollExtent) {
      final double t =
          ((viewport.top + edgeZone - y) / edgeZone).clamp(0.0, 1.0);
      target = pixels - maxStep * t;
    } else if (y > viewport.bottom - edgeZone &&
        pixels < s.position.maxScrollExtent) {
      final double t =
          ((y - (viewport.bottom - edgeZone)) / edgeZone).clamp(0.0, 1.0);
      target = pixels + maxStep * t;
    }
    if (target == null) return false;
    target = target.clamp(
      s.position.minScrollExtent,
      s.position.maxScrollExtent,
    );
    if ((target - pixels).abs() < 0.5) return false;
    s.position.jumpTo(target);
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Tab 4: 库（源库订阅 + 查看库内源 + 自定义导入）
  // ═══════════════════════════════════════════════════════════════════════

  /// 从 URL 推导默认名称（取 host，去掉 www.）。
  String _deriveNameFromUrl(String url) {
    final host = Uri.tryParse(url)?.host ?? url;
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  /// 订阅一个新源库（按 url 去重），订阅后立即打开「查看源」让用户选择要导入的源。
  Future<void> _subscribeLibrary() async {
    final url = _libraryUrlController.text.trim();
    if (url.isEmpty) return;
    final name = _libraryNameController.text.trim().isNotEmpty
        ? _libraryNameController.text.trim()
        : _deriveNameFromUrl(url);
    final lib = SourceLibrary(
      id: url,
      name: name,
      url: url,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    );
    setState(() => _librarySubscribing = true);
    try {
      await context.read<SourceLibrarySubscription>().add(lib);
      _libraryUrlController.clear();
      _libraryNameController.clear();
      if (!mounted) return;
      // 订阅成功后自动跳转到「查看源」页，方便用户立即选源导入。
      await Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (_) => LibrarySourcesScreen(library: lib),
        ),
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).librarySubscribeFailed),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _librarySubscribing = false);
    }
  }

  /// 外链打开源库主页（如 GitHub 仓库）。失败时弹出可复制的 URL 对话框。
  Future<void> _openLibraryHomepage(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.scheme.startsWith('http')) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AppAlertDialog(
          title: Text(uri.host),
          content: SelectableText(url),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(AppLocalizations.of(ctx).ok),
            ),
          ],
        ),
      );
    }
  }

  /// 取消订阅（非官方库）。
  Future<void> _unsubscribeLibrary(SourceLibrary lib) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(l10n.unsubscribeLibrary),
        content: Text(l10n.unsubscribeLibraryConfirm(lib.name)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.unsubscribeLibrary),
          ),
        ],
      ),
    );
    if (ok == true) {
      await context.read<SourceLibrarySubscription>().remove(lib.id);
    }
  }

  Widget _buildLibraryTab(AppLocalizations l10n, ColorScheme scheme) {
    final subs = context.watch<SourceLibrarySubscription>();
    final libs = subs.all();
    return ListView(
      // 文字列表：移动端避让玻璃底栏。
      padding: const EdgeInsets.all(AppTokens.spaceLg) + context.glassBarInset,
      children: <Widget>[
        // 已订阅源库列表
        Text(l10n.libraryBookmarks,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppTokens.spaceSm),
        if (libs.isEmpty)
          AppCard(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.spaceMd),
              child: Text(
                l10n.libraryEmpty,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          )
        else
          ...libs.map((lib) => Padding(
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
                          // 主要操作：查看源 → 进入自定义导入页（可勾选）
                          FilledButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              AppPageRoute<void>(
                                builder: (_) =>
                                    LibrarySourcesScreen(library: lib),
                              ),
                            ),
                            icon: const Icon(Icons.list_alt_rounded, size: 18),
                            label: Text(l10n.viewLibrarySources),
                          ),
                          if (lib.homepage != null)
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _openLibraryHomepage(lib.homepage),
                              icon: const Icon(Icons.open_in_new_rounded,
                                  size: 18),
                              label: Text(l10n.openHomepage),
                            ),
                          if (!lib.isOfficial)
                            OutlinedButton.icon(
                              onPressed: () => _unsubscribeLibrary(lib),
                              icon: const Icon(
                                Icons.bookmark_remove_rounded,
                                size: 18,
                              ),
                              label: Text(l10n.unsubscribeLibrary),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              )),
        const SizedBox(height: AppTokens.spaceLg),

        // 添加新源库订阅
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.spaceMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(l10n.addLibraryTitle,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppTokens.spaceSm),
                TextField(
                  controller: _libraryNameController,
                  decoration: InputDecoration(
                    labelText: l10n.libraryNameHint,
                    hintText: l10n.libraryNameHint,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                    ),
                  ),
                ),
                const SizedBox(height: AppTokens.spaceSm),
                AppUrlInputBar(
                  controller: _libraryUrlController,
                  hintText: l10n.libraryUrlHint,
                  submitLabel: l10n.subscribeLibrary,
                  isLoading: _librarySubscribing,
                  onSubmit: (_) => _subscribeLibrary(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEnableRecommendedTile(AppLocalizations l10n) {
    final repo = context.read<SourceRepository>();
    final hasDisabled = repo.all.any(
      (c) =>
          !c.isDeprecated &&
          !c.id.toLowerCase().contains('example') &&
          !c.isEnabled,
    );
    if (!hasDisabled) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
      child: AppCard(
        onTap: () => _enableRecommended(l10n),
        child: ListTile(
          leading: const Icon(Icons.playlist_add_check_rounded),
          title: Text(l10n.enableRecommendedSources),
          subtitle: Text(l10n.enableRecommendedSourcesHint),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
      ),
    );
  }

  Future<void> _enableRecommended(AppLocalizations l10n) async {
    final count =
        await context.read<SourceRepository>().enableRecommendedSources();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.recommendedSourcesEnabled(count))),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Tab 2: 网络导入
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildNetworkImportTab(AppLocalizations l10n, ColorScheme scheme) {
    return ListView(
      // 文字列表：移动端避让玻璃底栏。
      padding: const EdgeInsets.all(AppTokens.spaceLg) + context.glassBarInset,
      children: <Widget>[
        Text(
          l10n.networkImportHint,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppTokens.spaceMd),

        TextField(
          controller: _urlController,
          decoration: InputDecoration(
            hintText: l10n.networkImportPasteHint,
            prefixIcon: const Icon(Icons.link_rounded),
            border: const OutlineInputBorder(),
            suffixIcon: _networkLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    icon: const Icon(Icons.check_rounded),
                    onPressed: _fetchFromUrl,
                  ),
          ),
          keyboardType: TextInputType.url,
          onSubmitted: (_) => _fetchFromUrl(),
        ),

        const SizedBox(height: AppTokens.spaceLg),
        Text(
          l10n.collectApiImportTitle,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppTokens.spaceMd),
        TextField(
          controller: _collectApiUrlController,
          decoration: InputDecoration(
            hintText: l10n.collectApiUrlHint,
            prefixIcon: const Icon(Icons.cloud_upload_rounded),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.arrow_forward_rounded),
              tooltip: l10n.collectApiImportTitle,
              onPressed: _openCollectApiImport,
            ),
          ),
          keyboardType: TextInputType.url,
          onSubmitted: (_) => _openCollectApiImport(),
        ),

        // 预览区域
        const SizedBox(height: AppTokens.spaceLg),
        if (_networkLoading)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.spaceXl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const CircularProgressIndicator(),
                  const SizedBox(height: AppTokens.spaceMd),
                  Text(l10n.networkImportPasteHint),
                ],
              ),
            ),
          )
        else if (_networkError != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.spaceXl),
              child: Text(
                _networkError!,
                style: TextStyle(color: scheme.error),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else if (_networkPreview != null)
          _buildNetworkPreview(l10n, scheme)
        else
          Center(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.spaceXl),
              child: Text(
                l10n.networkImportPasteHint,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildNetworkPreview(AppLocalizations l10n, ColorScheme scheme) {
    final config = _networkPreview!;
    final isValid = _validationErrors.isEmpty;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(config.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppTokens.spaceSm),
          if (isValid)
            Row(
              children: <Widget>[
                Icon(Icons.check_circle_rounded,
                    color: scheme.primary, size: 18),
                const SizedBox(width: AppTokens.spaceXs),
                Text(l10n.sourceImportValid),
              ],
            )
          else ...<Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.error_rounded, color: scheme.error, size: 18),
                const SizedBox(width: AppTokens.spaceXs),
                Text(l10n.sourceImportInvalid,
                    style: TextStyle(color: scheme.error)),
              ],
            ),
            ..._validationErrors.map(
              (e) => Padding(
                padding: EdgeInsets.only(left: AppTokens.spaceMd, top: 2),
                child: Text('• $e',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.error,
                        )),
              ),
            ),
          ],
          const SizedBox(height: AppTokens.spaceLg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: isValid ? _saveNetworkSource : null,
              child: Text(l10n.save),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Tab 3: 本地导入（文件/文件夹，扫描后推入独立预览页勾选）
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildLocalImportTab(AppLocalizations l10n, ColorScheme scheme) {
    // 默认模式：选择文件或文件夹
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.description_rounded,
              size: 64,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: AppTokens.spaceLg),
            Text(
              l10n.localImportTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppTokens.spaceXs),
            Text(
              l10n.localImportFormats,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTokens.spaceLg),

            // 导入方式：单文件 / 多文件 / 文件夹。
            // 窄屏兜底：两按钮 + 文案在部分手机（小屏/大字体）会横向溢出，
            // 改用 Wrap + Flexible 自动换行，不再固定 Row 单行（修复 130）。
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppTokens.spaceMd,
              runSpacing: AppTokens.spaceSm,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: _pickLocalFile,
                  icon: const Icon(Icons.file_open_rounded, size: 18),
                  label: Text(l10n.selectFile),
                ),
                // 鸿蒙手机：目录选择接口不可用（已知缺陷 U2），隐藏文件夹导入
                // 入口，源 JSON 走「选择文件」逐个导入；鸿蒙 PC 已支持目录导入。
                if (!PlatformService.instance.isOHOSPhone)
                  OutlinedButton.icon(
                    onPressed: _pickLocalFolder,
                    icon: const Icon(Icons.folder_rounded, size: 18),
                    label: Text(l10n.selectFolder),
                  ),
              ],
            ),

            if (_pickedFileName != null) ...<Widget>[
              const SizedBox(height: AppTokens.spaceMd),
              Text(
                _pickedFileName!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.primary,
                    ),
              ),
            ],

            const SizedBox(height: AppTokens.spaceXl),
            Text(
              l10n.localImportHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────── 编辑/删除/迁移 ───────────────────────

  /// 编辑源：打开独立的全字段编辑页（JSON 编辑，可设置所有模块的所有字段）。
  Future<void> _showEditDialog(PluginConfig source) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => SourceEditScreen(source: source),
      ),
    );
  }

  /// 删除源确认对话框。
  Future<void> _showDeleteConfirm(PluginConfig source) async {
    final l10n = AppLocalizations.of(context);
    final repo = context.read<SourceRepository>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(l10n.deleteConfirmTitle),
        content: Text(l10n.deleteConfirmContent(source.name)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = repo.removeSource(source.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(ok ? l10n.sourceDeleted : l10n.sourceDeleteFailed)),
      );
    }
  }

  /// 弃用源迁移提示对话框。
  Future<void> _showMigrateDialog(PluginConfig source) async {
    final l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(l10n.sourceMigrate),
        content: Text(source.migrationMessage ?? l10n.sourceDeprecatedHint),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }
}
