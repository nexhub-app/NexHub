/// 源编辑全字段页（独立页面）。
///
/// 按顶层 JSON 字段（site / parser / routes / selectors / category /
/// homeSections / filters / antiHotlinking / webviewConfig / comments /
/// network / announcement …）拆成独立可折叠模块卡，并按职能分为
/// 基础字段 / 站点解析 / 路由 / 分类筛选 / 网络与其他五个页签（空页签隐藏）。
/// 模块默认全部折叠（懒加载，展开时才构建该模块的编辑框），点标题展开/
/// 收起，展开过的模块再次折叠不丢编辑。保存时把各模块 JSON 合并回完整
/// 配置，整体覆盖原源。id 锁定；清空模块内容并保存 = 删除该字段。
library;

import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/models/plugin_config.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/app_alert_dialog.dart';
import '../../../core/widgets/app_glass_bar.dart';

/// 源编辑页：接收 [PluginConfig source]，按页签 + 模块折叠编辑全部字段。
class SourceEditScreen extends StatefulWidget {
  final PluginConfig source;

  const SourceEditScreen({super.key, required this.source});

  @override
  State<SourceEditScreen> createState() => _SourceEditScreenState();
}

class _SourceEditScreenState extends State<SourceEditScreen>
    with TickerProviderStateMixin {
  /// 顶层字段有序键（保持源 JSON 原有顺序，新增字段追加尾部）。
  late final List<String> _keys;

  /// 各字段初始值快照：从未展开过的模块保存时直接沿用（视为未编辑）。
  late final Map<String, dynamic> _doc;

  /// 已展开模块的编辑控制器：懒创建（首次展开才生成 JSON 文本），折叠不
  /// 销毁（编辑内容保留，重新展开即恢复）。
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};

  final Set<String> _expanded = <String>{};
  final Set<String> _invalid = <String>{};
  String? _error;

  /// 基础字段页签包含的顶层键（身份/类型/开关类）。
  static const Set<String> _basicKeys = <String>{
    'id', 'name', 'author', 'type', 'responseType', 'useWebview',
    'version', 'deprecated', 'enabled', 'enabledExplore', 'isHidden',
    'stealthMode', 'ageRating', 'engine', 'migrationMessage',
  };

  /// 站点解析页签包含的顶层键（抓取与反爬配置类）。
  static const Set<String> _parseKeys = <String>{
    'site', 'parser', 'selectors', 'antiHotlinking', 'imageTransform',
    'webviewConfig', 'cdn',
  };

  /// 分类筛选页签包含的顶层键。
  static const Set<String> _browseKeys = <String>{
    'category', 'homeSections', 'filters', 'webFavorite',
  };

  /// 当前展示的页签 id 列表（仅含非空页签，空页签隐藏）。
  List<String> _visibleTabs = <String>[];
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    final doc = widget.source.toJson();
    _doc = Map<String, dynamic>.from(doc);
    _keys = List<String>.from(doc.keys);
    _rebuildTabs();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// 顶层键 → 页签 id。未知键（含用户新增字段）归入 advanced。
  String _groupOf(String key) {
    if (_basicKeys.contains(key)) return 'basic';
    if (_parseKeys.contains(key)) return 'parse';
    if (key == 'routes') return 'routes';
    if (_browseKeys.contains(key)) return 'browse';
    return 'advanced';
  }

  /// 计算非空页签；TabController 仅在页签数量变化时重建（保留当前页签）。
  void _rebuildTabs({String? activateKey}) {
    final tabs = <String>[
      if (_keys.any(_basicKeys.contains)) 'basic',
      if (_keys.any(_parseKeys.contains)) 'parse',
      if (_keys.contains('routes')) 'routes',
      if (_keys.any(_browseKeys.contains)) 'browse',
      if (_keys.any((k) => _groupOf(k) == 'advanced')) 'advanced',
    ];
    final previousIndex = _tabController?.index ?? 0;
    if (_tabController == null || _tabController!.length != tabs.length) {
      _tabController?.dispose();
      _tabController = TabController(length: tabs.length, vsync: this);
    }
    _visibleTabs = tabs;
    if (activateKey != null) {
      final target = tabs.indexOf(_groupOf(activateKey));
      if (target >= 0) _tabController!.index = target;
    } else if (previousIndex < tabs.length) {
      _tabController!.index = previousIndex;
    }
  }

  String _tabLabel(AppLocalizations l10n, String tab) => switch (tab) {
        'basic' => l10n.sourceEditTabBasic,
        'parse' => l10n.sourceEditTabParse,
        'routes' => l10n.sourceEditTabRoutes,
        'browse' => l10n.sourceEditTabBrowse,
        _ => l10n.sourceEditTabAdvanced,
      };

  /// 模块编辑控制器（懒创建；美化输出：2 空格缩进，便于阅读与编辑）。
  TextEditingController _controllerFor(String key) {
    return _controllers.putIfAbsent(
      key,
      () => TextEditingController(
        text: const JsonEncoder.withIndent('  ').convert(_doc[key]),
      ),
    );
  }

  /// 展开/收起模块（懒加载：首次展开此刻才创建控制器与编辑框）。
  void _toggleExpanded(String key) {
    AppHaptics.selectionClick();
    setState(() {
      if (!_expanded.remove(key)) _expanded.add(key);
    });
  }

  /// 模块标题摘要：容器/数组显示条目数，字符串截断预览，其余显示字面量。
  /// 已展开模块优先取控制器文本的实时解析结果；未展开取初始值。
  String _summary(AppLocalizations l10n, String key) {
    final controller = _controllers[key];
    Object? value;
    if (controller != null) {
      final text = controller.text.trim();
      if (text.isEmpty) return '';
      try {
        value = jsonDecode(text);
      } on Object {
        return '⚠ ${l10n.sourceEditInvalidJson}';
      }
    } else {
      value = _doc[key];
    }
    if (value is Map) return l10n.sourceEditSectionItems(value.length);
    if (value is List) return l10n.sourceEditSectionItems(value.length);
    if (value is String) {
      return value.length > 60 ? '${value.substring(0, 60)}…' : value;
    }
    return '$value';
  }

  /// 新增顶层字段：独立模块追加到列表尾部并自动展开所在页签。
  Future<void> _addField() async {
    final l10n = AppLocalizations.of(context);
    final nameController = TextEditingController();
    final key = await showDialog<String>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(l10n.sourceEditAddField),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.sourceEditFieldName),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(nameController.text.trim()),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (key == null || key.isEmpty || !mounted) return;
    if (_keys.contains(key)) {
      setState(() => _error = l10n.sourceEditFieldExists);
      return;
    }
    setState(() {
      // 新字段默认空对象（多数顶层字段为 site/network/webviewConfig 等容器）。
      _doc[key] = <String, dynamic>{};
      _keys.add(key);
      _expanded.add(key);
      _controllerFor(key);
      // 新键可能让某个页签从无到有，页签数量变化时控制器会重建并跳转过去。
      _rebuildTabs(activateKey: key);
    });
  }

  /// 保存：合并各模块 JSON → 校验 → 整体替换源。
  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final merged = <String, dynamic>{};
    final invalidKeys = <String>[];
    for (final key in _keys) {
      final controller = _controllers[key];
      // 从未展开 = 从未编辑：直接沿用初始值。
      if (controller == null) {
        merged[key] = _doc[key];
        continue;
      }
      final text = controller.text.trim();
      // 清空 = 删除该字段（id 随后强制回填，不受影响）。
      if (text.isEmpty) continue;
      try {
        merged[key] = jsonDecode(text);
      } on Object {
        invalidKeys.add(key);
      }
    }
    if (invalidKeys.isNotEmpty) {
      setState(() {
        _invalid
          ..clear()
          ..addAll(invalidKeys);
        // 自动展开出错模块，配合输入框 errorText 直接定位问题。
        _expanded.addAll(invalidKeys);
        _error = '${l10n.sourceEditInvalidJson}\n${invalidKeys.join(', ')}';
      });
      return;
    }
    // 锁定 id，避免误改 id 产生重复源或丢失原源。
    merged['id'] = widget.source.id;
    try {
      final config = PluginConfig.fromJson(merged);
      final errors = config.validate();
      if (errors.isNotEmpty) {
        if (mounted) {
          setState(() => _error = '${l10n.sourceEditInvalidJson}\n'
              '${errors.join('\n')}');
        }
        return;
      }
      context.read<SourceRepository>().replaceSource(config);
      if (mounted) {
        // 必须在 pop() 之前捕获 ScaffoldMessenger，pop 后再用 context 访问会
        // 触发「wrong build scope / _dependents.isEmpty」等崩溃。
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.sourceEditSaved)),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => _error = '${l10n.sourceEditInvalidJson}\n$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final tabs = _visibleTabs;
    final tabController = _tabController;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.sourceEdit),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.sourceEditAddField,
            icon: const Icon(Icons.add_rounded),
            onPressed: _addField,
          ),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_rounded),
            label: Text(l10n.save),
          ),
          const SizedBox(width: AppTokens.spaceSm),
        ],
      ),
      body: Padding(
        padding: context.pageInset(AppTokens.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.sourceEditJsonHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppTokens.spaceXs),
            if (tabController != null && tabs.isNotEmpty) ...<Widget>[
              TabBar(
                controller: tabController,
                // MD3「Selected」：页签单选 → tick。
                onTap: (_) => AppHaptics.tick(),
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: <Widget>[
                  for (final tab in tabs) Tab(text: _tabLabel(l10n, tab)),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: tabController,
                  children: <Widget>[
                    for (final tab in tabs)
                      _buildTabKeysList(l10n, theme, tab),
                  ],
                ),
              ),
            ],
            // 错误文本（校验清单/异常详情）可能很长：限高 + 内部滚动，
            // 保证任何内容都不撑爆页面布局。
            if (_error != null) ...<Widget>[
              const SizedBox(height: AppTokens.spaceSm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppTokens.spaceMd),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                    ),
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 某页签下的模块卡列表（TabBarView 按页懒构建）。
  Widget _buildTabKeysList(AppLocalizations l10n, ThemeData theme, String tab) {
    final keys = <String>[
      for (final key in _keys)
        if (_groupOf(key) == tab) key,
    ];
    return ListView.builder(
      itemCount: keys.length,
      itemBuilder: (context, index) =>
          _buildSectionCard(l10n, theme, keys[index]),
    );
  }

  /// 单个字段模块卡：标题行（字段名 + 摘要 + 锁/箭头）+ 懒加载编辑框。
  Widget _buildSectionCard(
    AppLocalizations l10n,
    ThemeData theme,
    String key,
  ) {
    final expanded = _expanded.contains(key);
    final isId = key == 'id';
    return Padding(
      key: ValueKey<String>('section-card-$key'),
      padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
      child: Material(
        color: AppTheme.cardContainer(theme.colorScheme),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            InkWell(
              onTap: () => _toggleExpanded(key),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceMd,
                  vertical: AppTokens.spaceSm,
                ),
                child: Row(
                  children: <Widget>[
                    // 标题与摘要都用 Expanded（紧满分配）：若用 Flexible，
                    // 短文本占不满分配宽度，剩余空隙会堆到行尾把箭头顶离右缘。
                    Expanded(
                      flex: 2,
                      child: Text(
                        key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    if (isId) ...<Widget>[
                      const SizedBox(width: AppTokens.spaceXs),
                      Tooltip(
                        message: l10n.sourceEditIdLocked,
                        child: Icon(
                          Icons.lock_outline_rounded,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(width: AppTokens.spaceSm),
                    Expanded(
                      flex: 3,
                      child: Text(
                        _summary(l10n, key),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: AppTokens.durFast,
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.spaceMd,
                  0,
                  AppTokens.spaceMd,
                  AppTokens.spaceMd,
                ),
                child: TextField(
                  controller: _controllerFor(key),
                  readOnly: isId,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.all(AppTokens.spaceMd),
                    errorText: _invalid.contains(key)
                        ? l10n.sourceEditInvalidJson
                        : null,
                  ),
                  onChanged: (_) {
                    // 修好 JSON 即时清除该模块的错误标记。
                    if (_invalid.remove(key)) setState(() {});
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
