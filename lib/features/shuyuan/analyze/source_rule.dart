/// 单条书源规则解析（`@css/@xpath/@json/@js` + `##` 正则替换）。
library;

/// 规则模式：默认（CSS/默认）、XPath、JSON、JS、正则。
enum Mode {
  defaultMode,
  xpath,
  json,
  js,
  regex,
}

class SourceRule {
  String rule = '';
  String elementsRule = '';
  Mode mode;
  String replaceRegex = '';
  String replacement = '';
  bool replaceFirst = false;
  final Map<String, String> putMap = {};

  bool isCss = false;

  /// 原始规则（`##` 分割前）。含 `{{...}}` 内嵌表达式时，`##` 可能出现在
  /// 表达式内部（如 `{{$.tag##\\|##、}}`），构造期不能提前分割，须等
  /// 内嵌表达式替换完成后再分割（由规则引擎求值期处理）。
  String rawRule = '';

  /// 是否含 `{{...}}` / `@get:{...}` 内嵌表达式（求值期需替换）。
  bool hasInnerRule = false;

  /// 模板模式：首个 `{{...}}` 位于规则开头、或其前置文本不含 `##` 时，
  /// 内嵌表达式全部替换后的整串即为最终结果（不再走选择器/JSON 解析）。
  /// 通用书源格式的 URL 模板与字段模板（`{{$.a}}分` 等）即此语义。
  bool templateMode = false;

  SourceRule(String ruleStr, [this.mode = Mode.defaultMode, bool isJson = false]) {
    _init(ruleStr, isJson);
  }

  void _init(String ruleStr, bool isJson) {
    if (mode == Mode.js || mode == Mode.regex) {
      rule = ruleStr;
      elementsRule = ruleStr;
      // 对齐 legado makeUpRule 语义：@js: 脚本体里的 {{...}} / @get:{...}
      // 内嵌表达式同样要在求值期先展开（{{$.bid}} 等以 $. / @ / // 开头的
      // 内嵌路由规则引擎对当前上下文求值，其余按 JS 求值），然后再执行
      // 脚本。此前 js 段在此提前返回、内嵌检测被跳过，脚本带着字面量
      // {{$.bid}} 执行 → 签名/参数类 JSON 源全部失配（2026-11-14 实测）。
      // js 段不做 ## 正则分割、无模板模式（脚本体非选择器语义）。
      if (mode == Mode.js) {
        rawRule = ruleStr;
        hasInnerRule = _firstInnerRuleIndex(ruleStr) != null;
      }
      return;
    }

    // 前缀匹配对齐通用书源格式语义：大小写不敏感、冒号后不要求空格
    // （社区源普遍写 `@css:.item` 而非 `@css: .item`，此前要求空格导致
    // 无空格形式整条规则失效 → 列表解析为空）。
    final lower = ruleStr.toLowerCase();
    if (lower.startsWith('@css:')) {
      mode = Mode.defaultMode;
      isCss = true;
      rule = ruleStr.substring(5);
    } else if (lower.startsWith('@xpath:')) {
      mode = Mode.xpath;
      rule = ruleStr.substring(7);
    } else if (lower.startsWith('@json:')) {
      mode = Mode.json;
      rule = ruleStr.substring(6);
    } else if (lower.startsWith('@js:')) {
      mode = Mode.js;
      rule = ruleStr.substring(4);
    } else if (ruleStr.startsWith('@@')) {
      mode = Mode.defaultMode;
      isCss = true;
      rule = ruleStr.substring(2);
    } else if (isJson || ruleStr.startsWith('\$.') || ruleStr.startsWith('\$[')) {
      mode = Mode.json;
      rule = ruleStr;
    } else if (ruleStr.startsWith('/')) {
      mode = Mode.xpath;
      rule = ruleStr;
    } else {
      // 对齐 legado：默认模式统一走 ElementsSingle（含 `.N` 下标、`tag./class./
      // id./text./children` 前缀、CSS 回退），只有显式 `@css:`/`@@` 才是纯 CSS。
      // 旧启发式把 `a.0` 判成 CSS，导致 593/735 部源的关键规则整条失效。
      rule = ruleStr;
    }

    rule = _splitPutRule(rule);
    elementsRule = rule;

    // 内嵌表达式检测：`{{...}}`（规则/JS 表达式）与 `@get:{...}`（变量引用）。
    // 含内嵌表达式时 `##` 分割延迟到替换完成后（表达式内部可含 `##` 正则）。
    rawRule = rule;
    final firstInner = _firstInnerRuleIndex(rule);
    hasInnerRule = firstInner != null;
    if (hasInnerRule) {
      // 首个内嵌表达式位于开头、或前置文本不含 ## → 模板模式。
      final prefix = rule.substring(0, firstInner);
      templateMode = prefix.trim().isEmpty || !prefix.contains('##');
    } else {
      _splitRegex(rule);
    }
  }

  /// 首个内嵌表达式的起始位置；无则返回 null。
  static int? _firstInnerRuleIndex(String ruleStr) {
    int? min;
    final getMatch = RegExp(r'@get:\{').firstMatch(ruleStr);
    if (getMatch != null) min = getMatch.start;
    final jsMatch = RegExp(r'\{\{').firstMatch(ruleStr);
    if (jsMatch != null && (min == null || jsMatch.start < min)) {
      min = jsMatch.start;
    }
    return min;
  }

  String _splitPutRule(String ruleStr) {
    // legado 标准写法是 `@put:{k:"rule"}`（无括号）；历史实现与部分源
    // 写成 `@put:({k:"rule"})`。两种都要认，否则标准写法整条变量链失效。
    final putPattern = RegExp(r'@put:(?:\((\{[^}]+?\})\)|(\{[^}]+?\}))',
        caseSensitive: false);
    var vRuleStr = ruleStr;
    var match = putPattern.firstMatch(vRuleStr);
    while (match != null) {
      vRuleStr = vRuleStr.replaceFirst(match.group(0)!, '');
      final jsonStr = match.group(1) ?? match.group(2) ?? '';
      try {
        final decoded = _parseJsonMap(jsonStr);
        putMap.addAll(decoded);
      } catch (_) {}
      match = putPattern.firstMatch(vRuleStr);
    }
    return vRuleStr;
  }

  void _splitRegex(String ruleStr) {
    final parts = ruleStr.split('##');
    rule = parts[0].trim();
    if (parts.length > 1) replaceRegex = parts[1];
    if (parts.length > 2) replacement = parts[2];
    if (parts.length > 3) replaceFirst = true;
  }

  static Map<String, String> _parseJsonMap(String jsonStr) {
    final result = <String, String>{};
    final inner = jsonStr.trim();
    if (!inner.startsWith('{') || !inner.endsWith('}')) return result;

    final content = inner.substring(1, inner.length - 1);
    final pairs = _splitJsonPairs(content);
    for (final pair in pairs) {
      final colonIndex = pair.indexOf(':');
      if (colonIndex > 0) {
        final key = pair.substring(0, colonIndex).trim().replaceAll('"', '');
        final value = pair.substring(colonIndex + 1).trim().replaceAll('"', '');
        result[key] = value;
      }
    }
    return result;
  }

  static List<String> _splitJsonPairs(String content) {
    final pairs = <String>[];
    int depth = 0;
    int start = 0;
    bool inString = false;

    for (int i = 0; i < content.length; i++) {
      final c = content[i];
      if (c == '"') {
        inString = !inString;
      } else if (!inString) {
        if (c == '{' || c == '[') {
          depth++;
        } else if (c == '}' || c == ']') {
          depth--;
        } else if (c == ',' && depth == 0) {
          pairs.add(content.substring(start, i).trim());
          start = i + 1;
        }
      }
    }
    if (start < content.length) {
      pairs.add(content.substring(start).trim());
    }
    return pairs;
  }
}
