/// 正文净化（替换规则）管理页面。
///
/// 规则全局一套，随包内置一批默认规则；
/// 从阅读器进入时额外提供「本书净化」总开关，并可把新规则限定为仅本书/仅本源。
library;

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../../core/novel/novel_replace_rule.dart';
import '../../core/novel/novel_replace_rule_store.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_alert_dialog.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_empty_state.dart';
import '../../features/settings/presentation/widgets/settings_widgets.dart';
import '../utils/app_haptics.dart';

/// 开关行：与 [SettingsGroup] 的行内边距对齐（[SettingsSwitchTile] 自带零内边距，
/// 只适合放进已有内边距的 SettingsCard）。
Widget _switchRow({
  required IconData icon,
  required String title,
  String? subtitle,
  required bool value,
  required ValueChanged<bool> onChanged,
}) {
  void toggle(bool next) {
    next ? AppHaptics.toggleOn() : AppHaptics.toggleOff();
    onChanged(next);
  }

  return SettingsTile(
    icon: icon,
    title: title,
    subtitle: subtitle,
    trailing: Switch(value: value, onChanged: toggle),
    onTap: () => toggle(!value),
  );
}

/// 替换规则管理页面入口：设置 → 小说阅读器 → 正文净化；
/// 阅读器内打开时带上书名/源，可配置「仅本书 / 仅本源」规则。
class NovelReplaceRuleScreen extends StatefulWidget {
  final String bookId;
  final String bookName;
  final String sourceId;
  final String sourceName;

  const NovelReplaceRuleScreen({
    super.key,
    this.bookId = '',
    this.bookName = '',
    this.sourceId = '',
    this.sourceName = '',
  });

  @override
  State<NovelReplaceRuleScreen> createState() => _NovelReplaceRuleScreenState();
}

class _NovelReplaceRuleScreenState extends State<NovelReplaceRuleScreen> {
  NovelReplaceRuleSet? _ruleSet;
  bool _bookEnabled = true;
  bool _loading = true;

  bool get _hasBook => widget.bookId.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = NovelReplaceRuleStore();
    final rules = await store.load(refresh: true);
    final bookEnabled =
        _hasBook ? await store.isBookEnabled(widget.bookId) : true;
    if (!mounted) return;
    setState(() {
      _ruleSet = rules;
      _bookEnabled = bookEnabled;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_ruleSet == null) return;
    await NovelReplaceRuleStore().save(_ruleSet!);
  }

  Future<void> _toggleMaster(bool value) async {
    if (_ruleSet == null) return;
    setState(() => _ruleSet!.enabled = value);
    await _save();
  }

  Future<void> _toggleBook(bool value) async {
    setState(() => _bookEnabled = value);
    await NovelReplaceRuleStore().setBookEnabled(widget.bookId, value);
  }

  Future<void> _toggleRule(int index, bool value) async {
    setState(() => _ruleSet!.rules[index].isEnabled = value);
    await _save();
  }

  Future<void> _addRule() async {
    final l10n = AppLocalizations.of(context);
    final result = await Navigator.push<_RuleEditResult>(
      context,
      MaterialPageRoute(
        builder: (_) => _ReplaceRuleEditScreen(
          rule: null,
          bookId: widget.bookId,
          bookName: widget.bookName,
          sourceId: widget.sourceId,
          sourceName: widget.sourceName,
          nextOrder: _nextOrder(),
        ),
      ),
    );
    final rule = result?.rule;
    if (rule == null) return;
    setState(() => _ruleSet!.rules.add(rule));
    await _save();
    if (!mounted) return;
    if (!_ruleSet!.enabled) {
      // 添加了规则但总开关是关的：提示一下，避免以为没生效。
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.novelPurgeMasterOff)),
      );
    }
  }

  Future<void> _editRule(int index) async {
    final l10n = AppLocalizations.of(context);
    final shown = _ruleSet!.rules[index];
    final result = await Navigator.push<_RuleEditResult>(
      context,
      MaterialPageRoute(
        builder: (_) => _ReplaceRuleEditScreen(
          rule: shown,
          displayName: _ruleTitle(l10n, shown),
          bookId: widget.bookId,
          bookName: widget.bookName,
          sourceId: widget.sourceId,
          sourceName: widget.sourceName,
          nextOrder: shown.order,
        ),
      ),
    );
    if (result == null) return;
    if (result.deleted) {
      setState(() => _ruleSet!.rules.removeWhere((r) => r.id == shown.id));
    } else if (result.rule != null) {
      setState(() => _ruleSet!.rules[index] = result.rule!);
    }
    await _save();
  }

  Future<void> _restoreBuiltIns() async {
    final l10n = AppLocalizations.of(context);
    final added = await NovelReplaceRuleStore().restoreBuiltIns();
    final rules = await NovelReplaceRuleStore().load(refresh: true);
    if (!mounted) return;
    setState(() => _ruleSet = rules);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(added > 0
            ? l10n.novelPurgeRestoreAdded(added)
            : l10n.novelPurgeRestoreNone),
      ),
    );
  }

  int _nextOrder() {
    var max = 0;
    for (final rule in _ruleSet!.rules) {
      if (rule.order > max) max = rule.order;
    }
    return max + 10;
  }

  /// 规则标题：内置规则按 nameKey 走本地化，用户规则用自定义名称，
  /// 都没有时退回匹配内容。
  String _ruleTitle(AppLocalizations l10n, NovelReplaceRule rule) {
    if (rule.name.isNotEmpty) return rule.name;
    switch (rule.nameKey) {
      case 'urlOnly':
        return l10n.novelPurgeRuleUrlOnly;
      case 'sitePromo':
        return l10n.novelPurgeRuleSitePromo;
      case 'mobilePromo':
        return l10n.novelPurgeRuleMobilePromo;
      case 'nextPage':
        return l10n.novelPurgeRuleNextPage;
      case 'speed':
        return l10n.novelPurgeRuleSpeed;
      case 'social':
        return l10n.novelPurgeRuleSocial;
      case 'search':
        return l10n.novelPurgeRuleSearch;
      case 'adTag':
        return l10n.novelPurgeRuleAdTag;
      case 'invisible':
        return l10n.novelPurgeRuleInvisible;
      case 'trailingSpace':
        return l10n.novelPurgeRuleTrailingSpace;
      case 'authorPlea':
        return l10n.novelPurgeRuleAuthorPlea;
      case 'chapterEnd':
        return l10n.novelPurgeRuleChapterEnd;
      default:
        return rule.pattern;
    }
  }

  String _positionLabel(AppLocalizations l10n, String scope) {
    switch (scope) {
      case 'title':
        return l10n.novelPurgePositionTitle;
      case 'all':
        return l10n.novelPurgePositionBoth;
      default:
        return l10n.novelPurgePositionContent;
    }
  }

  String _applyToLabel(AppLocalizations l10n, NovelReplaceRule rule) {
    switch (rule.applyTo) {
      case 'book':
        final name =
            rule.applyToLabel.isNotEmpty ? rule.applyToLabel : widget.bookName;
        return name.isEmpty
            ? l10n.novelPurgeApplyToBook
            : '${l10n.novelPurgeApplyToBook} · $name';
      case 'source':
        final name = rule.applyToLabel.isNotEmpty
            ? rule.applyToLabel
            : widget.sourceName;
        return name.isEmpty
            ? l10n.novelPurgeApplyToSource
            : '${l10n.novelPurgeApplyToSource} · $name';
      default:
        return l10n.novelPurgeApplyToAll;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.novelPurgeTitle),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.restore_rounded),
            tooltip: l10n.novelPurgeRestoreBuiltin,
            onPressed: _loading ? null : _restoreBuiltIns,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(l10n),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _addRule,
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.novelPurgeAddRule),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    final rules = _ruleSet!.rules;
    final scheme = Theme.of(context).colorScheme;
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceLg,
        AppTokens.spaceSm,
        AppTokens.spaceLg,
        // 悬浮按钮高度 + 呼吸位，避免最后一条规则被遮住。
        AppTokens.space3xl * 2,
      ),
      // 列表项会被 LookupBoundary 包裹，页面头部自己兜一层透明 Material，
      // 保证空态里的按钮 / 开关仍能找到墨水祖先。
      header: Material(
        type: MaterialType.transparency,
        child: _buildHeader(l10n, rules.length),
      ),
      buildDefaultDragHandles: false,
      // 拖起时的浮卡：只加一层随拖动渐入的投影，卡片自身样式不变。
      proxyDecorator: (Widget child, int index, Animation<double> animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            final double t = Curves.easeOut.transform(animation.value);
            return DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: 0.22 * t),
                    blurRadius: AppTokens.spaceLg * t + AppTokens.spaceXs,
                    offset: Offset(0, AppTokens.spaceSm * t),
                  ),
                ],
              ),
              child: child,
            );
          },
        );
      },
      itemCount: rules.length,
      onReorderItem: (oldIndex, newIndex) {
        setState(() {
          final item = rules.removeAt(oldIndex);
          rules.insert(newIndex, item);
          for (int i = 0; i < rules.length; i++) {
            rules[i].order = (i + 1) * 10;
          }
        });
        _save();
      },
      itemBuilder: (context, index) => _buildRuleItem(l10n, index),
    );
  }

  Widget _buildHeader(AppLocalizations l10n, int total) {
    final rules = _ruleSet!.rules;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 开关组：卡内发丝分隔线由 SettingsGroup 统一渲染。
        SettingsGroup(
          children: <Widget>[
            _switchRow(
              icon: Icons.cleaning_services_rounded,
              title: l10n.novelPurgeMasterSwitch,
              subtitle: l10n.novelPurgeDesc,
              value: _ruleSet!.enabled,
              onChanged: _toggleMaster,
            ),
            if (_hasBook)
              _switchRow(
                icon: Icons.menu_book_rounded,
                title: l10n.novelPurgeBookSwitch,
                subtitle: l10n.novelPurgeBookSwitchDesc,
                value: _bookEnabled,
                onChanged: _toggleBook,
              ),
          ],
        ),
        const SizedBox(height: AppTokens.spaceLg),
        SettingsSection(
          title: l10n.novelPurgeRulesSection,
          description: l10n.novelPurgeRuleCount(_ruleSet!.enabledCount, total),
        ),
        if (total > 1)
          Padding(
            padding: const EdgeInsets.only(
              left: AppTokens.spaceXs,
              bottom: AppTokens.spaceXs,
            ),
            child: Text(
              l10n.novelPurgeReorderHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ),
        if (rules.isEmpty) _buildEmpty(l10n),
      ],
    );
  }

  Widget _buildEmpty(AppLocalizations l10n) => Padding(
        padding: const EdgeInsets.only(top: AppTokens.spaceSm),
        child: AppEmptyState(
          icon: Icons.cleaning_services_rounded,
          message: l10n.novelPurgeEmptyHint,
          actionLabel: l10n.novelPurgeRestoreBuiltin,
          onAction: _restoreBuiltIns,
        ),
      );

  Widget _buildRuleItem(AppLocalizations l10n, int index) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rule = _ruleSet!.rules[index];
    final enabled = rule.isEnabled;
    final subtitle = rule.replacement.isEmpty
        ? rule.pattern
        : '${rule.pattern} → ${rule.replacement}';

    return Padding(
      key: ValueKey<String>(rule.id),
      padding: const EdgeInsets.only(top: AppTokens.spaceSm),
      // 长按整行即可拖动排序（与书源管理页一致），行首不再保留拖拽把手。
      child: ReorderableDelayedDragStartListener(
        index: index,
        child: AppCard(
          padding: EdgeInsets.zero,
          onTap: () {
            AppHaptics.selectionClick();
            _editRule(index);
          },
          child: Row(
            children: <Widget>[
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.spaceLg,
                    AppTokens.spaceMd,
                    AppTokens.spaceSm,
                    AppTokens.spaceMd,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _ruleTitle(l10n, rule),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: enabled ? scheme.onSurface : scheme.outline,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppTokens.spaceXxs),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: scheme.onSurfaceVariant
                              .withValues(alpha: enabled ? 0.9 : 0.55),
                        ),
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      Wrap(
                        spacing: AppTokens.spaceXs,
                        runSpacing: AppTokens.spaceXs,
                        children: <Widget>[
                          if (rule.isBuiltIn)
                            _badge(
                              l10n.novelPurgeBuiltin,
                              scheme.primaryContainer,
                              scheme.onPrimaryContainer,
                            ),
                          _badge(
                            _positionLabel(l10n, rule.scope),
                            scheme.surfaceContainerHighest,
                            scheme.onSurfaceVariant,
                          ),
                          if (rule.applyTo != 'all')
                            _badge(
                              _applyToLabel(l10n, rule),
                              scheme.secondaryContainer,
                              scheme.onSecondaryContainer,
                            ),
                          _badge(
                            rule.isRegex
                                ? l10n.novelPurgeRegex
                                : l10n.novelPurgePlainText,
                            scheme.surfaceContainerHighest,
                            scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  left: AppTokens.spaceXs,
                  right: AppTokens.spaceSm,
                ),
                child: Switch(
                  value: enabled,
                  onChanged: (v) {
                    v ? AppHaptics.toggleOn() : AppHaptics.toggleOff();
                    _toggleRule(index, v);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color background, Color foreground) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceSm,
        vertical: AppTokens.spaceXxs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTokens.radiusXs),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}

/// 编辑页回传结果：保存的规则，或「已删除」。
class _RuleEditResult {
  final NovelReplaceRule? rule;
  final bool deleted;

  const _RuleEditResult.saved(NovelReplaceRule this.rule) : deleted = false;

  const _RuleEditResult.deleted()
      : rule = null,
        deleted = true;
}

/// 替换规则编辑页面。
class _ReplaceRuleEditScreen extends StatefulWidget {
  final NovelReplaceRule? rule;

  /// 列表里展示的标题（内置规则已本地化），用于删除确认文案。
  final String displayName;
  final String bookId;
  final String bookName;
  final String sourceId;
  final String sourceName;
  final int nextOrder;

  const _ReplaceRuleEditScreen({
    this.rule,
    this.displayName = '',
    this.bookId = '',
    this.bookName = '',
    this.sourceId = '',
    this.sourceName = '',
    this.nextOrder = 0,
  });

  @override
  State<_ReplaceRuleEditScreen> createState() => _ReplaceRuleEditScreenState();
}

class _ReplaceRuleEditScreenState extends State<_ReplaceRuleEditScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _patternCtrl;
  late final TextEditingController _replacementCtrl;
  late bool _isRegex;
  late String _scope;
  late String _applyTo;
  late bool _isEnabled;

  bool get _isNew => widget.rule == null;

  @override
  void initState() {
    super.initState();
    final r = widget.rule;
    _nameCtrl = TextEditingController(text: r?.name ?? '');
    _patternCtrl = TextEditingController(text: r?.pattern ?? '');
    _replacementCtrl = TextEditingController(text: r?.replacement ?? '');
    _isRegex = r?.isRegex ?? true;
    _scope = r?.scope ?? 'content';
    _applyTo = r?.applyTo ?? 'all';
    _isEnabled = r?.isEnabled ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _patternCtrl.dispose();
    _replacementCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final l10n = AppLocalizations.of(context);
    final pattern = _patternCtrl.text.trim();
    if (pattern.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.novelPurgePatternRequired)),
      );
      return;
    }
    if (_isRegex) {
      try {
        RegExp(pattern);
      } on FormatException {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.novelPurgePatternInvalid)),
        );
        return;
      }
    }
    final keepExistingScope =
        widget.rule != null && widget.rule!.applyTo == _applyTo;
    final rule = NovelReplaceRule(
      id: widget.rule?.id,
      name: _nameCtrl.text.trim(),
      nameKey: widget.rule?.nameKey ?? '',
      group: widget.rule?.group ?? '',
      pattern: pattern,
      replacement: _replacementCtrl.text,
      isRegex: _isRegex,
      scope: _scope,
      applyTo: _applyTo,
      // 从设置页编辑「仅本书 / 仅本源」规则时没有书籍上下文，
      // 沿用原来的目标，避免把范围悄悄改废。
      applyToValue: keepExistingScope
          ? widget.rule!.applyToValue
          : switch (_applyTo) {
              'book' => widget.bookId,
              'source' => widget.sourceId,
              _ => '',
            },
      applyToLabel: keepExistingScope
          ? widget.rule!.applyToLabel
          : switch (_applyTo) {
              'book' => widget.bookName,
              'source' => widget.sourceName,
              _ => '',
            },
      isBuiltIn: widget.rule?.isBuiltIn ?? false,
      isEnabled: _isEnabled,
      order: widget.nextOrder,
    );
    Navigator.pop(context, _RuleEditResult.saved(rule));
  }

  Future<void> _confirmDelete() async {
    final l10n = AppLocalizations.of(context);
    final rule = widget.rule;
    if (rule == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(l10n.delete),
        content: Text(l10n.novelPurgeDeleteMsg(
          widget.displayName.isNotEmpty
              ? widget.displayName
              : (rule.name.isNotEmpty ? rule.name : rule.pattern),
        )),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      Navigator.pop(context, const _RuleEditResult.deleted());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final canScopeBook = widget.bookId.isNotEmpty;
    final canScopeSource = widget.sourceId.isNotEmpty;
    final scopedName = widget.rule?.applyToLabel ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? l10n.novelPurgeNewTitle : l10n.novelPurgeEditTitle),
        actions: <Widget>[
          if (!_isNew)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              color: scheme.error,
              tooltip: l10n.delete,
              onPressed: _confirmDelete,
            ),
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text(l10n.save),
          ),
          const SizedBox(width: AppTokens.spaceXs),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.spaceLg,
          AppTokens.spaceSm,
          AppTokens.spaceLg,
          AppTokens.space2xl,
        ),
        children: <Widget>[
          SettingsSection(title: l10n.novelPurgeContentSection),
          AppCard(
            padding: const EdgeInsets.all(AppTokens.spaceLg),
            child: Column(
              children: <Widget>[
                TextField(
                  controller: _nameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l10n.novelPurgeRuleName,
                    hintText: l10n.novelPurgeRuleNameHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                TextField(
                  controller: _patternCtrl,
                  minLines: 2,
                  maxLines: 4,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    labelText: l10n.novelPurgePattern,
                    hintText: _isRegex
                        ? l10n.novelPurgePatternHintRegex
                        : l10n.novelPurgePatternHintPlain,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                TextField(
                  controller: _replacementCtrl,
                  minLines: 1,
                  maxLines: 3,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    labelText: l10n.novelPurgeReplacement,
                    hintText: l10n.novelPurgeReplacementHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.spaceLg),
          SettingsGroup(
            header: l10n.novelPurgeOptions,
            children: <Widget>[
              _switchRow(
                icon: Icons.code_rounded,
                title: l10n.novelPurgeUseRegex,
                subtitle: _isRegex
                    ? l10n.novelPurgeUseRegexDescOn
                    : l10n.novelPurgeUseRegexDescOff,
                value: _isRegex,
                onChanged: (v) => setState(() => _isRegex = v),
              ),
              SettingsTile(
                icon: Icons.text_fields_rounded,
                title: l10n.novelPurgePosition,
                trailing: _dropdown<String>(
                  value: _scope,
                  items: <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(
                      value: 'content',
                      child: Text(l10n.novelPurgePositionContent),
                    ),
                    DropdownMenuItem<String>(
                      value: 'title',
                      child: Text(l10n.novelPurgePositionTitle),
                    ),
                    DropdownMenuItem<String>(
                      value: 'all',
                      child: Text(l10n.novelPurgePositionBoth),
                    ),
                  ],
                  onChanged: (v) => setState(() => _scope = v),
                ),
              ),
              if (canScopeBook || canScopeSource)
                SettingsTile(
                  icon: Icons.filter_alt_outlined,
                  title: l10n.novelPurgeApplyTo,
                  trailing: _dropdown<String>(
                    value: _applyTo,
                    items: <DropdownMenuItem<String>>[
                      DropdownMenuItem<String>(
                        value: 'all',
                        child: Text(l10n.novelPurgeApplyToAll),
                      ),
                      if (canScopeBook)
                        DropdownMenuItem<String>(
                          value: 'book',
                          child: Text(l10n.novelPurgeApplyToBook),
                        ),
                      if (canScopeSource)
                        DropdownMenuItem<String>(
                          value: 'source',
                          child: Text(l10n.novelPurgeApplyToSource),
                        ),
                    ],
                    onChanged: (v) => setState(() => _applyTo = v),
                  ),
                )
              else if (_applyTo != 'all')
                // 设置页没有书籍上下文：保留原范围，只展示不可改。
                SettingsTile(
                  icon: Icons.lock_outline_rounded,
                  title: l10n.novelPurgeApplyTo,
                  subtitle: [
                    _applyTo == 'book'
                        ? l10n.novelPurgeApplyToBook
                        : l10n.novelPurgeApplyToSource,
                    if (scopedName.isNotEmpty) scopedName,
                  ].join(' · '),
                ),
              _switchRow(
                icon: Icons.power_settings_new_rounded,
                title: l10n.novelPurgeRuleEnabled,
                value: _isEnabled,
                onChanged: (v) => setState(() => _isEnabled = v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T> onChanged,
  }) {
    return DropdownButton<T>(
      value: value,
      items: items,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      style: Theme.of(context).textTheme.bodyMedium,
      onChanged: (v) {
        if (v != null) {
          AppHaptics.selectionClick();
          onChanged(v);
        }
      },
    );
  }
}
