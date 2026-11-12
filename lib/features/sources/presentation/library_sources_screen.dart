/// 源库查看页：拉取某个 [SourceLibrary] 的 manifest，列出全部源（按 [SourceType]
/// 分成「小说 / 媒体 / 漫画」页签，未识别类型归「其他」），用户可勾选要导入的源，
/// 点底部「导入选中」一次性写入 [SourceRepository]。
///
/// 与 [SourceImportScreen] 的「库导入」区别：导入时按用户勾选按需抓取 rawUrl，
/// 避免大库全量拉取浪费流量与时间。
///
/// 年龄等级：manifest 通常不声明 `ageRating`（真实等级在各源 JSON 文件里），
/// 因此除「已安装源直接取已装配置的等级」外，还会**后台低并发补抓**未安装条目
/// 的 rawUrl 解析真实等级（结果按 rawUrl 进静态缓存，同一次运行内不重复抓），
/// 解析期间先按 manifest 声明展示；开启年龄限制后，判定为成人 (18+) 的条目
/// 自动从列表隐藏并取消勾选，导入时同样兜底拦截。
library;

import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/models/plugin_config.dart';
import '../../../core/services/cdn_mirror.dart';
import '../../../core/services/source_library_subscription.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_error_state.dart';
import '../../../core/widgets/app_loading_indicator.dart';
import '../../../core/widgets/app_glass_bar.dart';
import '../../../core/widgets/app_tab_bar.dart';

/// 源库查看页：列出库内全部源供用户勾选导入。
class LibrarySourcesScreen extends StatefulWidget {
  final SourceLibrary library;

  const LibrarySourcesScreen({super.key, required this.library});

  @override
  State<LibrarySourcesScreen> createState() => _LibrarySourcesScreenState();
}

class _LibrarySourcesScreenState extends State<LibrarySourcesScreen>
    // 分类页签控制器会随分类集合重建（旧控制器延后一帧销毁），同一时刻可能
    // 存在两个 ticker，故用多 ticker 版本而非 SingleTicker。
    with TickerProviderStateMixin {
  bool _loading = true;
  bool _importing = false;
  String? _error;

  /// manifest 解析出的条目（原始，不含 rawUrl 内容）。
  List<_LibEntry> _entries = const <_LibEntry>[];

  /// 选中的条目下标集合。
  Set<int> _selectedIndices = const <int>{};

  /// 分类页签（按 [SourceType] 归一化后的长词，顺序固定为
  /// 小说 → 媒体 → 漫画 → 其他，仅保留库内实际存在的分类）。
  List<String> _tabTypes = const <String>[];

  /// 分类页签控制器；库内无源（加载中 / 报错 / 空库）时为 null。
  TabController? _tab;

  /// 记住上次停留的页签下标：重载（导入后自动刷新）期间不显示 TabBar，
  /// 重建控制器时据此恢复到原分类，避免每次都跳回第一个页签。
  int _lastTabIndex = 0;

  /// 已安装版本映射（id → 已装 version）；缺失即未安装。用于「源库」展示
  /// 当前版本、标记可更新（库版本 > 已装版本）。
  Map<String, int> _installedVersions = const <String, int>{};

  /// 条目 id → 已解析的年龄等级（manifest 声明 / 已安装源 / 补抓结果）。
  /// 条目缺省按 [SourceAgeRating.general] 处理。
  Map<String, SourceAgeRating> _ageRatings = <String, SourceAgeRating>{};

  /// 后台等级解析的代际号：_load 重新执行时 +1，旧的后台任务据此自我终止。
  int _resolveGen = 0;

  /// rawUrl → 真实年龄等级缓存（进程级，避免重复进页反复抓源 JSON）。
  static final Map<String, SourceAgeRating> _ageRatingCache =
      <String, SourceAgeRating>{};

  /// 条目当前生效的年龄等级。
  SourceAgeRating _ratingOf(_LibEntry e) =>
      _ageRatings[e.id] ?? SourceAgeRating.general;

  /// 年龄限制开启时该条目是否应被隐藏（等级已判定为成人）。
  bool _isEntryHidden(_LibEntry e, SourceRepository repo) =>
      repo.ageRestrictionEnabled && _ratingOf(e).isRestricted;

  /// 是否存在「库版本 > 已装版本」的可更新源（控制 AppBar「一键更新」显示）。
  /// 被年龄限制隐藏的条目不计入。
  bool get _hasUpdatable {
    if (_entries.isEmpty) return false;
    final repo = context.read<SourceRepository>();
    for (int i = 0; i < _entries.length; i++) {
      final e = _entries[i];
      if (_isEntryHidden(e, repo)) continue;
      final ins = _installedVersions[e.id];
      if (ins != null && ins < e.version) return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 进行中的清单拉取（单飞）：被墙/超时时用户容易反复点刷新或反复进出页面，
  /// 复用同一次请求，避免同一地址在日志里刷成一片。
  Future<void>? _inflightLoad;

  /// 拉取库 manifest（单飞包装，见 [_inflightLoad]）。
  Future<void> _load() {
    final existing = _inflightLoad;
    if (existing != null) return existing;
    late final Future<void> future;
    future = _loadOnce().whenComplete(() {
      if (identical(_inflightLoad, future)) _inflightLoad = null;
    });
    _inflightLoad = future;
    return future;
  }

  /// 拉取库 manifest 并解析成 [_LibEntry] 列表（rawUrl 按需再抓）。
  Future<void> _loadOnce() async {
    _resolveGen++; // 终止仍在运行的旧后台等级解析
    final gen = _resolveGen;
    setState(() {
      _loading = true;
      _error = null;
      _entries = const <_LibEntry>[];
      _selectedIndices = const <int>{};
      _ageRatings = <String, SourceAgeRating>{};
    });
    try {
      // jsDelivr 在国内常被墙：清单地址按 jsDelivr → GitHub raw → 国内反代
      // 竞速拉取，任一可达即用；[resolvedBase] 用于解析清单里的相对路径。
      final manifest = await CdnMirror.fetch(widget.library.url);
      final String text = manifest.text;
      final String resolvedBase = manifest.url;
      final dynamic decoded = jsonDecode(text);
      final List<Map<String, dynamic>> raw;
      if (decoded is Map<String, dynamic> && decoded['sources'] is List) {
        raw = (decoded['sources'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else if (decoded is List) {
        raw = decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else {
        raw = const <Map<String, dynamic>>[];
      }
      final entries = <_LibEntry>[];
      for (final e in raw) {
        entries.add(_LibEntry.fromManifest(e, base: resolvedBase));
      }
      // 比对已安装版本，标记可更新；默认只勾选「未安装」或「可更新」的条目，
      // 已是最新的源不预勾选，避免误触「导入选中」重复写库。
      //
      // ⚠️ id 归一化：不同源库的 manifest 写法不一致——
      // 有的用「类型/名称」（如 novel/novel_linovelb），有的只用名称
      // （如 novel_linovelib），有的用 bookSourceUrl（完整 URL）。
      // PluginConfig.id 取的是源 JSON 本身的 id 字段（通常无类型前缀）。
      // 因此比对时需依次尝试：精确匹配 → 去前缀 → 按名称兜底。
      final repo = context.read<SourceRepository>();
      final installed = <String, int>{};
      final selected = <int>{};
      final ageRatings = <String, SourceAgeRating>{};
      for (int i = 0; i < entries.length; i++) {
        final e = entries[i];
        // 等级初值：manifest 声明 > 历史（缓存）补抓结果 > general。
        final cached = e.rawUrl == null ? null : _ageRatingCache[e.rawUrl!];
        ageRatings[e.id] = cached ??
            (e.raw['ageRating'] != null
                ? e.ageRating
                : SourceAgeRating.general);
        // 1) 精确匹配
        var cfg = repo.getById(e.id);
        // 2) 去类型前缀（novel/novel_xxx → novel_xxx）
        if (cfg == null && e.id.contains('/')) {
          cfg = repo.getById(e.id.substring(e.id.lastIndexOf('/') + 1));
        }
        // 3) 按名称兜底（manifest 的 name 与 PluginConfig.name 一致时）
        if (cfg == null && e.name.isNotEmpty) {
          cfg = repo.all.where((c) => c.name == e.name).firstOrNull;
        }
        if (cfg != null) {
          installed[e.id] = cfg.version;
          // 已安装源以其自身配置声明的等级为准（源文件是唯一可信来源）。
          ageRatings[e.id] = cfg.ageRating;
          if (cfg.version < e.version) selected.add(i); // 可更新
        } else {
          selected.add(i); // 未安装 → 默认勾选导入
        }
      }
      // 年龄限制开启时，已判定为成人的条目不预勾选（列表中也会隐藏）。
      if (repo.ageRestrictionEnabled) {
        selected.removeWhere(
          (i) => (ageRatings[entries[i].id] ?? SourceAgeRating.general)
              .isRestricted,
        );
      }
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _installedVersions = installed;
        _selectedIndices = selected;
        _ageRatings = ageRatings;
        _loading = false;
      });
      // 后台补抓未安装且未声明等级的条目，解析真实年龄等级（渐进刷新）。
      unawaited(_resolveMissingRatings(gen, repo));
    } catch (e) {
      if (!mounted) return;
      // 详细原因（DNS/超时/JSON 结构错）只进运行日志：界面上给一句可读提示，
      // 不把 `Bad state: ...` 之类的内部异常串糊到用户脸上。
      debugPrint('[SourceLibrary] manifest 拉取失败 ${widget.library.url}: $e');
      setState(() {
        _error = AppLocalizations.of(context).libraryFetchFailed;
        _loading = false;
      });
    }
  }

  /// 后台补抓未判定等级条目的 rawUrl，解析真实年龄等级。
  ///
  /// 仅处理「未安装 + manifest 未声明 ageRating + 有 rawUrl + 缓存未命中」的
  /// 条目；并发 3，抓到即缓存并渐进刷新 UI；开启年龄限制时把新判定为成人的
  /// 条目从列表隐藏并取消勾选。抓取失败不缓存（下次进页重试），不隐藏
  /// （等级未知时保守显示，导入仍有年龄限制兜底拦截）。
  Future<void> _resolveMissingRatings(
    int gen,
    SourceRepository repo,
  ) async {
    final entries = _entries;
    final pending = <int>[];
    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (e.rawUrl == null || e.rawUrl!.isEmpty) continue;
      if (_ageRatingCache.containsKey(e.rawUrl!)) continue;
      if (_installedVersions.containsKey(e.id)) continue; // 已装源等级可信
      if (e.raw['ageRating'] != null) continue; // manifest 已声明
      pending.add(i);
    }
    final queue = pending.toList(growable: false);
    if (queue.isEmpty) return;
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < queue.length) {
        final i = queue[cursor++];
        final e = entries[i];
        final url = e.rawUrl!;
        SourceAgeRating? rating = _ageRatingCache[url];
        if (rating == null) {
          try {
            final t = (await CdnMirror.fetch(url)).text;
            final cfgs = SourceRepository.parseMixedSources(t);
            if (cfgs.isNotEmpty) {
              rating = _strictestRating(cfgs);
              _ageRatingCache[url] = rating;
            }
          } on Object {
            // 抓取 / 解析失败：等级未知，不缓存不隐藏。
          }
        }
        if (rating == null) continue;
        if (!mounted || gen != _resolveGen) return;
        setState(() {
          _ageRatings[e.id] = rating!;
          if (repo.ageRestrictionEnabled && rating.isRestricted) {
            _selectedIndices = <int>{..._selectedIndices}..remove(i);
          }
        });
      }
    }

    await Future.wait(<Future<void>>[worker(), worker(), worker()]);
  }

  /// 取一组配置中最严格的年龄等级（源文件打包多源时按最保守口径隐藏）。
  static SourceAgeRating _strictestRating(List<PluginConfig> cfgs) {
    var rating = SourceAgeRating.general;
    for (final c in cfgs) {
      if (c.ageRating == SourceAgeRating.mature) return SourceAgeRating.mature;
      if (c.ageRating == SourceAgeRating.teen) rating = SourceAgeRating.teen;
    }
    return rating;
  }

  /// 把选中的条目按需拉取 rawUrl，解析为 [PluginConfig] 后批量入库。
  ///
  /// **更新语义（修复 129）**：网站源文件（rawUrl）发新版后，必须**替换**
  /// 已安装的同源条目，而不是新增一个重复条目。manifest 的 `id` 写法可能与
  /// 源文件实际 `id` 不一致（如 `novel/novel_x` vs `novel_x`），因此导入前
  /// 先用与 [_load] 相同的归一化规则（精确 id → 去前缀 → 按名称）匹配
  /// 已安装源，命中则把解析出的配置 **re-key 到已安装 id** 再入库。
  Future<void> _importSelected() async {
    if (_selectedIndices.isEmpty) return;
    final selected = _selectedIndices
        .where((i) => i >= 0 && i < _entries.length)
        .map((i) => _entries[i])
        .toList();
    setState(() => _importing = true);
    final repo = context.read<SourceRepository>();
    int success = 0;
    int failed = 0;
    int alreadyLatest = 0;
    for (final entry in selected) {
      // 年龄限制兜底：解析后判定为成人的源不导入（列表已隐藏，此处防竞态）。
      if (_isEntryHidden(entry, repo)) continue;
      try {
        List<PluginConfig> parsed = const <PluginConfig>[];
        // 优先用 rawUrl 抓远端源 JSON；若没有 rawUrl 或抓失败，回退用条目本身解析。
        if (entry.rawUrl != null && entry.rawUrl!.isNotEmpty) {
          try {
            final t = (await CdnMirror.fetch(entry.rawUrl!)).text;
            parsed = SourceRepository.parseMixedSources(t);
          } on Object {
            // 抓 rawUrl 失败时回退到条目本身
          }
        }
        if (parsed.isEmpty) {
          parsed = SourceRepository.parseMixedSources(jsonEncode(entry.raw));
        }
        if (parsed.isEmpty) {
          failed++;
          continue;
        }
        // 单个源文件里可能打包了多个源，全部入库（成人源被年龄限制拦截时跳过）。
        for (final cfg in parsed) {
          if (repo.isAgeBlocked(cfg)) continue;
          final applied = _applySourceUpdate(repo, entry, cfg);
          if (applied == _ApplyResult.updated) {
            success++;
          } else if (applied == _ApplyResult.latest) {
            alreadyLatest++;
          } else {
            failed++;
          }
        }
      } on Object {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() => _importing = false);
    // 导入后立即重新拉取 manifest 并比对已装版本（修复 128：源库在应用里
    // 实时更新）——版本徽标/「可更新」标记不再停留在上一次打开的旧状态。
    await _load();
    final l10n = AppLocalizations.of(context);
    final int total = success + failed + alreadyLatest;
    final String msg;
    if (alreadyLatest > 0 && success == 0 && failed == 0) {
      msg = l10n.libraryAllUpToDate;
    } else if (alreadyLatest > 0) {
      msg = l10n.libraryImportResult(success, total, failed) +
          ' · ${l10n.libraryAlreadyLatestCount(alreadyLatest)}';
    } else {
      msg = l10n.libraryImportResult(success, total, failed);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
    if (success > 0) {
      Navigator.of(context).pop();
    }
  }

  /// 入库结果：成功更新 / 已是最新（未变更） / 失败。
  // 注：_ApplyResult 定义为库级私有枚举（见文件底部），Dart 不允许
  // enum 声明在类体内（analyzer 报 enum_in_class）。

  /// 用 [cfg] 更新源库：按与 [_load] 相同的归一化规则匹配已安装源，
  /// 命中则 re-key 到已安装 id 后调用 [SourceRepository.addSource]
  /// （同 id 才能触发「替换」而不是新增重复源）。
  ///
  /// 版本处理：源文件版本 **≥** 已安装版本 → 更新；**<** 已安装版本 →
  /// 视为「已是最新」（manifest 版本可能领先源文件实际版本，直接跳过）。
  _ApplyResult _applySourceUpdate(
    SourceRepository repo,
    _LibEntry entry,
    PluginConfig cfg,
  ) {
    // 1) 精确匹配（含 manifest id 与 cfg.id 相同的常见情况）
    PluginConfig? installed = repo.getById(cfg.id);
    // 2) 去类型前缀：manifest id（novel/novel_x）匹配源文件 id（novel_x）
    if (installed == null && cfg.id.contains('/')) {
      installed = repo.getById(cfg.id.substring(cfg.id.lastIndexOf('/') + 1));
    }
    // 3) 按名称兜底：manifest 条目名称与已安装源名称一致
    if (installed == null && entry.name.isNotEmpty) {
      installed = repo.all.where((c) => c.name == entry.name).firstOrNull;
    }
    if (installed != null && cfg.version < installed.version) {
      return _ApplyResult.latest; // 已装版本更高，无需降级
    }
    // re-key：确保与已安装源同 id，替换而非新增（修复 129）。
    final String effectiveId = installed?.id ?? cfg.id;
    final PluginConfig normalized = installed != null && cfg.id != effectiveId
        ? cfg.copyWith(id: effectiveId)
        : cfg;
    repo.addSource(normalized);
    return _ApplyResult.updated;
  }

  /// 一键更新全部可更新的源：只勾选「库版本 > 已装版本」的条目并立即导入
  /// （被年龄限制隐藏的条目跳过）。
  Future<void> _updateAll() async {
    final repo = context.read<SourceRepository>();
    final updatable = <int>{};
    for (int i = 0; i < _entries.length; i++) {
      final e = _entries[i];
      if (_isEntryHidden(e, repo)) continue;
      final ins = _installedVersions[e.id];
      if (ins != null && ins < e.version) updatable.add(i);
    }
    if (updatable.isEmpty) return;
    setState(() => _selectedIndices = updatable);
    await _importSelected();
  }

  @override
  void dispose() {
    _tab?.dispose();
    super.dispose();
  }

  /// 分类页签：按类型集合变化时重建控制器（尽量保留当前页签），
  /// 库内无源时销毁（此时不显示 TabBar）。
  void _syncTabs(List<String> types) {
    if (_tab != null && _sameTypes(types, _tabTypes)) return;
    final TabController? prev = _tab;
    if (prev != null) _lastTabIndex = prev.index;
    _tab = types.isEmpty
        ? null
        : TabController(
            length: types.length,
            vsync: this,
            initialIndex: _lastTabIndex.clamp(0, types.length - 1),
          );
    _tabTypes = types;
    if (prev != null) {
      // 旧控制器可能仍在播放指示器动画，延后一帧销毁避免断言。
      WidgetsBinding.instance.addPostFrameCallback((_) => prev.dispose());
    }
  }

  static bool _sameTypes(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    // 按类型分组供页签使用。年龄限制开启时，已判定为成人 (18+) 的条目
    // 整行隐藏；某分类被清空则不出页签。
    final repo = context.read<SourceRepository>();
    final groups = <String, List<int>>{};
    for (int i = 0; i < _entries.length; i++) {
      if (_isEntryHidden(_entries[i], repo)) continue;
      groups.putIfAbsent(_canonicalType(_entries[i].type), () => <int>[]).add(i);
    }
    final types = <String>[
      if (groups.containsKey('novelSource')) 'novelSource',
      if (groups.containsKey('animeSource')) 'animeSource',
      if (groups.containsKey('mangaSource')) 'mangaSource',
      if (groups.containsKey('unknown')) 'unknown',
    ];
    _syncTabs(types);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.library.name),
        bottom: (_tab == null || types.length < 2)
            ? null
            : AppTabBar(
                controller: _tab!,
                compact: true,
                items: <AppTabItem>[
                  for (final t in types)
                    AppTabItem(icon: _typeIcon(t), label: _groupLabel(t, l10n)),
                ],
              ),
        actions: <Widget>[
          if (_hasUpdatable)
            IconButton(
              tooltip: l10n.libraryUpdateAll,
              icon: const Icon(Icons.system_update_alt_rounded),
              onPressed: _loading || _importing
                  ? null
                  : () {
                      AppHaptics.light();
                      _updateAll();
                    },
            ),
          IconButton(
            tooltip: l10n.retry,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading || _importing
                ? null
                : () {
                    AppHaptics.selectionClick();
                    _load();
                  },
          ),
        ],
      ),
      body: _buildBody(l10n, scheme, groups, types),
      bottomNavigationBar: _selectedIndices.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.spaceMd),
                child: FilledButton.icon(
                  onPressed: _importing || _selectedIndices.isEmpty
                      ? null
                      : () {
                          // 批量导入属确认类动作，中档双脉冲反馈。
                          AppHaptics.medium();
                          _importSelected();
                        },
                  icon: _importing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_download_rounded),
                  label:
                      Text(l10n.importSelectedCount(_selectedIndices.length)),
                ),
              ),
            ),
    );
  }

  Widget _buildBody(
    AppLocalizations l10n,
    ColorScheme scheme,
    Map<String, List<int>> groups,
    List<String> types,
  ) {
    if (_loading) {
      return AppLoadingIndicator(message: l10n.loading);
    }
    if (_error != null) {
      return AppErrorState(
        message: _error!,
        onRetry: _load,
        retryLabel: l10n.retry,
      );
    }
    // 库内无源，或全部条目都被年龄限制隐藏。
    if (_tab == null || types.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceXl),
          child: Text(
            l10n.libraryEmpty,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // 每个分类一页：整页只有一张连体卡，行间发丝线分隔。
    final pages = <Widget>[
      for (final t in types)
        ListView(
          padding: context.pageInset(AppTokens.spaceMd),
          children: <Widget>[
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  for (int j = 0; j < groups[t]!.length; j++) ...<Widget>[
                    if (j > 0)
                      Divider(
                        height: 1,
                        color: scheme.outlineVariant.withValues(alpha: 0.3),
                      ),
                    _buildRow(groups[t]![j], l10n, scheme),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppTokens.spaceMd),
          ],
        ),
    ];
    // 只有一个分类（如清单里 source type 全缺失）时不显示单个页签，直接铺列表。
    if (pages.length < 2) return pages.first;
    return TabBarView(controller: _tab, children: pages);
  }

  Widget _buildRow(int index, AppLocalizations l10n, ColorScheme scheme) {
    final entry = _entries[index];
    final selected = _selectedIndices.contains(index);
    final installed = _installedVersions[entry.id];
    final updateAvailable = installed != null && installed < entry.version;
    final versionText = installed == null
        ? '库 v${entry.version} · ${l10n.libraryNotInstalled}'
        : l10n.libraryVersion(entry.version, installed);
    return CheckboxListTile(
      value: selected,
      onChanged: (v) {
        v == true ? AppHaptics.toggleOn() : AppHaptics.toggleOff();
        setState(() {
          final s = <int>{..._selectedIndices};
          if (v == true) {
            s.add(index);
          } else {
            s.remove(index);
          }
          _selectedIndices = s;
        });
      },
      controlAffinity: ListTileControlAffinity.leading,
      secondary: updateAvailable
          ? Chip(
              label: Text(
                l10n.libraryUpdateAvailable,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: scheme.onPrimaryContainer),
              ),
              backgroundColor: scheme.primaryContainer,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide.none,
            )
          : null,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceSm,
        vertical: AppTokens.spaceXs,
      ),
      title: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          const SizedBox(width: AppTokens.spaceXs),
          _ageChip(context, scheme, _ratingOf(entry)),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            versionText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: updateAvailable
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                  fontWeight:
                      updateAvailable ? FontWeight.w600 : FontWeight.normal,
                ),
          ),
          Text(
            'id: ${entry.id}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  /// 年龄分级徽章：general=中性灰 / teen=琥珀 / mature=红（与设置页一致）。
  Widget _ageChip(
      BuildContext context, ColorScheme scheme, SourceAgeRating rating) {
    final l10n = AppLocalizations.of(context);
    final (Color bg, Color fg, String label) = switch (rating) {
      SourceAgeRating.general => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
          l10n.ageRatingGeneral,
        ),
      SourceAgeRating.teen => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
          l10n.ageRatingTeen,
        ),
      SourceAgeRating.mature => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          l10n.ageRatingMature,
        ),
    };
    return Chip(
      label: Text(label, style: Theme.of(context).textTheme.labelMedium),
      backgroundColor: bg,
      labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      side: BorderSide.none,
    );
  }

  String _groupLabel(String type, AppLocalizations l10n) {
    switch (type) {
      case 'novelSource':
        return l10n.sourceCategoryNovel;
      case 'animeSource':
        return l10n.sourceCategoryMedia;
      case 'mangaSource':
        return l10n.sourceCategoryComic;
      default:
        return l10n.sourceTypeOther;
    }
  }

  /// 分类页签图标（与「源列表」分类胶囊保持同一套语义）。
  static IconData _typeIcon(String type) {
    switch (type) {
      case 'novelSource':
        return Icons.book_rounded;
      case 'animeSource':
        return Icons.movie_rounded;
      case 'mangaSource':
        return Icons.image_rounded;
      default:
        return Icons.extension_rounded;
    }
  }

  /// 把 manifest 里的 type 字段统一归到三类长词，未知则返回 'unknown'。
  /// 兼容官方短词（`anime`/`manga`/`novel`）、老格式书源词（`bookSource`）
  /// 以及长词（`animeSource`/`mangaSource`/`novelSource`）。
  static String _canonicalType(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    switch (s) {
      case 'anime':
      case 'animeSource':
      case 'media':
        return 'animeSource';
      case 'manga':
      case 'mangaSource':
      case 'comic':
      case 'manhua':
        return 'mangaSource';
      case 'novel':
      case 'novelSource':
      case 'booksource':
      case 'bookSource':
      case 'book':
        return 'novelSource';
      default:
        return 'unknown';
    }
  }
}

/// 入库结果：成功更新 / 已是最新（未变更） / 失败。
enum _ApplyResult { updated, latest, failed }

/// 单条库条目（解析 manifest 后，未抓 rawUrl）。
class _LibEntry {
  final String id;
  final String name;
  final String? rawUrl;
  final String? type;
  final int version;
  final SourceAgeRating ageRating;
  final Map<String, dynamic> raw;

  _LibEntry({
    required this.id,
    required this.name,
    required this.rawUrl,
    required this.type,
    this.version = 1,
    this.ageRating = SourceAgeRating.general,
    required this.raw,
  });

  /// 把 manifest 里的 version 规范为 int（缺省 1）。兼容 int / 数字 / "12" /
  /// "1.3.0"（取首段）。
  static int _coerceVersion(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      final first = v.split('.').first;
      return int.tryParse(first) ?? 1;
    }
    return 1;
  }

  /// 从 manifest 条目构造。
  ///
  /// 字段名尽量宽容：不同社区库的清单写法不一致，除官方的 `rawUrl` 外，
  /// 还兼容 `url` / `file` / `path` / `download`；相对路径按 [base]（index.json
  /// 自身地址）解析成绝对地址，否则按需抓取时会 404。同时解析 `version` 与
  /// `ageRating`，供「源库」展示等级与版本、以及一键更新判断。
  factory _LibEntry.fromManifest(Map<String, dynamic> m, {String? base}) {
    final id = (m['id'] ?? m['bookSourceUrl'] ?? '').toString();
    final name = (m['name'] ?? m['bookSourceName'] ?? id).toString();
    final rawUrl = _resolveRawUrl(m, base);
    final type = (m['type'] ?? m['sourceType']) as String?;
    return _LibEntry(
      id: id,
      name: name,
      rawUrl: rawUrl,
      type: type,
      version: _coerceVersion(m['version']),
      ageRating: SourceAgeRating.parse(m['ageRating']),
      raw: m,
    );
  }

  /// 取出条目里的源文件地址并补全为绝对 URL；没有可用地址时返回 null
  /// （此时条目本身就是一份完整源配置，走回退解析）。
  ///
  /// 注意 `url` / `path` 在「完整源配置」里通常是站点主页而非源文件，
  /// 因此这些备用键只在指向 `.json` 时才当作源文件地址；`rawUrl` 是官方
  /// 清单的约定字段，无条件采用。
  static String? _resolveRawUrl(Map<String, dynamic> m, String? base) {
    String? pick;
    final official = m['rawUrl'];
    if (official is String && official.trim().isNotEmpty) {
      pick = official.trim();
    } else {
      for (final key in const <String>['url', 'file', 'path', 'download']) {
        final v = m[key];
        if (v is! String || v.trim().isEmpty) continue;
        final s = v.trim();
        final pathPart = s.split('?').first.split('#').first.toLowerCase();
        if (!pathPart.endsWith('.json')) continue;
        pick = s;
        break;
      }
    }
    if (pick == null) return null;
    if (pick.startsWith('http://') || pick.startsWith('https://')) return pick;
    final baseUri = base == null ? null : Uri.tryParse(base);
    if (baseUri == null) return null;
    return baseUri.resolve(pick).toString();
  }
}
