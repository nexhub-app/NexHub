/// 替换规则模型：正文净化规则（正则 / 纯文本替换）。
///
/// 规则全局共享，按 order 排序；[scope] 决定作用位置（标题/正文/全部），
/// [applyTo] 决定生效对象（全部书籍 / 仅某本书 / 仅某个源），
/// [isRegex] 切换正则/纯文本替换，书籍级开关见 NovelReplaceRuleStore。
library;

class NovelReplaceRule {
  final String id;
  String name;

  /// 内置规则的名称键（界面按当前语言翻译；为空则用 [name] 或匹配内容兜底）。
  String nameKey;
  String group;
  String pattern;
  String replacement;

  /// 作用位置：'all' | 'title' | 'content'。
  String scope;

  /// 生效对象：'all' | 'book' | 'source'。
  String applyTo;

  /// 生效对象的标识（bookId 或 sourceId），[applyTo] 为 'all' 时为空。
  String applyToValue;

  /// 生效对象的展示名（书名 / 源名），仅用于界面展示。
  String applyToLabel;

  /// 是否为随包内置的默认规则（界面显示「内置」标记）。
  bool isBuiltIn;
  bool isEnabled;
  bool isRegex;
  int timeoutMilliseconds;
  int order;

  NovelReplaceRule({
    String? id,
    this.name = '',
    this.nameKey = '',
    this.group = '',
    this.pattern = '',
    this.replacement = '',
    this.scope = 'content',
    this.applyTo = 'all',
    this.applyToValue = '',
    this.applyToLabel = '',
    this.isBuiltIn = false,
    this.isEnabled = true,
    this.isRegex = true,
    this.timeoutMilliseconds = 3000,
    this.order = 0,
  }) : id = id ?? _uuid();

  static String _uuid() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'nameKey': nameKey,
        'group': group,
        'pattern': pattern,
        'replacement': replacement,
        'scope': scope,
        'applyTo': applyTo,
        'applyToValue': applyToValue,
        'applyToLabel': applyToLabel,
        'isBuiltIn': isBuiltIn,
        'isEnabled': isEnabled,
        'isRegex': isRegex,
        'timeoutMilliseconds': timeoutMilliseconds,
        'order': order,
      };

  factory NovelReplaceRule.fromJson(Map<String, dynamic> json) => NovelReplaceRule(
        id: json['id'] as String?,
        name: json['name'] as String? ?? '',
        nameKey: json['nameKey'] as String? ?? '',
        group: json['group'] as String? ?? '',
        pattern: json['pattern'] as String? ?? '',
        replacement: json['replacement'] as String? ?? '',
        scope: json['scope'] as String? ?? 'content',
        applyTo: json['applyTo'] as String? ?? 'all',
        applyToValue: json['applyToValue'] as String? ?? '',
        applyToLabel: json['applyToLabel'] as String? ?? '',
        isBuiltIn: json['isBuiltIn'] as bool? ?? false,
        isEnabled: json['isEnabled'] as bool? ?? true,
        isRegex: json['isRegex'] as bool? ?? true,
        timeoutMilliseconds: json['timeoutMilliseconds'] as int? ?? 3000,
        order: json['order'] as int? ?? 0,
      );

  NovelReplaceRule copyWith({
    String? name,
    String? nameKey,
    String? group,
    String? pattern,
    String? replacement,
    String? scope,
    String? applyTo,
    String? applyToValue,
    String? applyToLabel,
    bool? isBuiltIn,
    bool? isEnabled,
    bool? isRegex,
    int? timeoutMilliseconds,
    int? order,
  }) =>
      NovelReplaceRule(
        id: id,
        name: name ?? this.name,
        nameKey: nameKey ?? this.nameKey,
        group: group ?? this.group,
        pattern: pattern ?? this.pattern,
        replacement: replacement ?? this.replacement,
        scope: scope ?? this.scope,
        applyTo: applyTo ?? this.applyTo,
        applyToValue: applyToValue ?? this.applyToValue,
        applyToLabel: applyToLabel ?? this.applyToLabel,
        isBuiltIn: isBuiltIn ?? this.isBuiltIn,
        isEnabled: isEnabled ?? this.isEnabled,
        isRegex: isRegex ?? this.isRegex,
        timeoutMilliseconds: timeoutMilliseconds ?? this.timeoutMilliseconds,
        order: order ?? this.order,
      );

  /// 检查规则是否有效（pattern 非空）。
  bool isValid() => pattern.isNotEmpty;

  /// 当前规则是否命中这本书 / 这个源。
  bool matches(String bookId, String sourceId) {
    switch (applyTo) {
      case 'book':
        return applyToValue.isNotEmpty && applyToValue == bookId;
      case 'source':
        return applyToValue.isNotEmpty && applyToValue == sourceId;
      default:
        return true;
    }
  }

  /// 编译后的正则（按 pattern 记忆，正文按段落调用时避免重复编译）。
  RegExp? get compiledRegex {
    if (!isRegex || pattern.isEmpty) return null;
    if (_compiledFor == pattern) return _compiled;
    try {
      _compiled = RegExp(pattern, multiLine: true);
    } on FormatException {
      _compiled = null;
    }
    _compiledFor = pattern;
    return _compiled;
  }

  RegExp? _compiled;
  String? _compiledFor;

  @override
  String toString() => 'NovelReplaceRule($name)';
}

/// 替换规则集合：全局一套规则 + 总开关。
class NovelReplaceRuleSet {
  /// 全局规则集合使用的固定 id（持久化键的一部分）。
  static const String globalId = 'global';

  final String bookId;
  bool enabled;
  List<NovelReplaceRule> rules;

  NovelReplaceRuleSet({
    required this.bookId,
    this.enabled = true,
    List<NovelReplaceRule>? rules,
  }) : rules = rules ?? [];

  Map<String, dynamic> toJson() => {
        'bookId': bookId,
        'enabled': enabled,
        'rules': rules.map((r) => r.toJson()).toList(),
      };

  factory NovelReplaceRuleSet.fromJson(Map<String, dynamic> json) =>
      NovelReplaceRuleSet(
        bookId: json['bookId'] as String? ?? globalId,
        enabled: json['enabled'] as bool? ?? true,
        rules: (json['rules'] as List?)
                ?.map((e) => NovelReplaceRule.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  /// 已启用的规则数。
  int get enabledCount => rules.where((r) => r.isEnabled && r.isValid()).length;

  /// 对文本应用所有命中的替换规则。
  /// [scopeFilter] 限制规则作用位置（'content' / 'title'）；
  /// [bookId] / [sourceId] 用于过滤「仅本书 / 仅本源」的规则。
  String apply(
    String text, {
    String scopeFilter = 'content',
    String bookId = '',
    String sourceId = '',
  }) {
    if (!enabled || rules.isEmpty) return text;
    final sorted = [...rules.where((r) => r.isEnabled && r.isValid())]
      ..sort((a, b) => a.order.compareTo(b.order));
    var result = text;
    for (final rule in sorted) {
      if (rule.scope != 'all' && rule.scope != scopeFilter) continue;
      if (!rule.matches(bookId, sourceId)) continue;
      if (rule.isRegex) {
        final re = rule.compiledRegex;
        if (re == null) continue;
        result = result.replaceAll(re, rule.replacement);
      } else {
        result = result.replaceAll(rule.pattern, rule.replacement);
      }
    }
    return result;
  }
}
