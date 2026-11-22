/// 单条书源规则解析（`@css/@xpath/@json/@js` + `##` 正则替换 + `$N` 分组）。
library;

import 'dart:convert';

/// 规则模式：默认（CSS/默认）、XPath、JSON、JS、后台 WebView JS、正则。
enum Mode {
  defaultMode,
  xpath,
  json,
  js,
  webJs,
  regex,
}

/// 规则参数段（对齐 legado `AnalyzeRule.SourceRule.ruleParam/ruleType`）。
///
/// 一条规则会被切成交替的参数段，求值期再拼回：
/// - [literalType]：字面量（选择器、`##` 替换尾等，原样保留）；
/// - `> 0`：`$N` 分组引用，从当前正则命中项的分组数组取 `N` 号元素；
/// - [innerType]：`{{...}}` 内嵌表达式（规则或 JS）；
/// - [getType]：`@get:{key}` 变量引用。
class RuleParam {
  static const int getType = -2;
  static const int innerType = -1;
  static const int literalType = 0;

  final int type;
  final String text;

  const RuleParam(this.type, this.text);

  bool get isGroup => type > 0;
  bool get isLiteral => type == literalType;
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

  /// 原始规则（`##` 分割前，`@put` 剥离后）。
  String rawRule = '';

  /// 是否含 `{{...}}` / `@get:{...}` 内嵌表达式。
  bool hasInnerRule = false;

  /// 模板模式（首个内嵌表达式位于开头、或前置文本不含 `##`）。
  /// 实际求值由 [mode] 提升为 [Mode.regex] 完成（整串替换后即结果）。
  bool templateMode = false;

  /// 参数段（对齐 legado ruleParam）。无 `$N`/内嵌表达式时只含字面量，
  /// [hasParams] 为 false，走构造期已拆好的 [rule]/[replaceRegex] 快路径。
  final List<RuleParam> params = [];

  bool get hasParams => params.any((p) => !p.isLiteral);

  /// evalPattern：内嵌表达式与变量引用（大小写不敏感，不处理嵌套括号，
  /// 与 legado AppPattern 一致）。
  static final RegExp _evalPattern = RegExp(
    r'@get:\{[^}]+?\}|\{\{[\w\W]*?\}\}',
    caseSensitive: false,
  );

  /// `$1`..`$99`（`$0` 在 legado 中按字面量处理，不参与分组取值）。
  static final RegExp _dollarPattern = RegExp(r'\$\d{1,2}');

  SourceRule(String ruleStr, [this.mode = Mode.defaultMode, bool isJson = false]) {
    _init(ruleStr, isJson);
  }

  void _init(String ruleStr, bool isJson) {
    var body = ruleStr;
    if (mode != Mode.js && mode != Mode.regex) {
      // 前缀匹配对齐通用书源格式语义：大小写不敏感、冒号后不要求空格。
      final lower = ruleStr.toLowerCase();
      if (lower.startsWith('@css:')) {
        mode = Mode.defaultMode;
        isCss = true;
        body = ruleStr.substring(5);
      } else if (lower.startsWith('@xpath:')) {
        mode = Mode.xpath;
        body = ruleStr.substring(7);
      } else if (lower.startsWith('@json:')) {
        mode = Mode.json;
        body = ruleStr.substring(6);
      } else if (lower.startsWith('@js:')) {
        mode = Mode.js;
        body = ruleStr.substring(4);
      } else if (ruleStr.startsWith('@@')) {
        // legado AnalyzeRule.SourceRule：`@@` 仅剥前缀，仍是默认模式
        // （ElementsSingle 语义）。只有显式 `@css:` 才是纯 CSS。
        mode = Mode.defaultMode;
        body = ruleStr.substring(2);
      } else if (isJson || ruleStr.startsWith(r'$.') || ruleStr.startsWith(r'$[')) {
        mode = Mode.json;
        body = ruleStr;
      } else if (ruleStr.startsWith('/')) {
        mode = Mode.xpath;
        body = ruleStr;
      } else {
        // 默认模式统一走 ElementsSingle（含 `.N` 下标、`tag./class./id./
        // text./children` 前缀、CSS 回退）。
        body = ruleStr;
      }
    }

    body = _splitPutRule(body);
    rawRule = body;

    var hasToken = false;
    var start = 0;

    // 首个内嵌表达式位于开头、或其前置文本不含 `##` → 整串替换后即结果：
    // legado 将 mode 提升为 Regex（规则文本不再被选择器解析）。
    final first = _evalPattern.firstMatch(body);
    if (first != null &&
        mode != Mode.js &&
        mode != Mode.regex &&
        (first.start == 0 || !body.substring(0, first.start).contains('##'))) {
      mode = Mode.regex;
      templateMode = true;
    }

    for (final match in _evalPattern.allMatches(body)) {
      if (match.start > start) {
        if (_splitRegexGap(body.substring(start, match.start))) hasToken = true;
      }
      final token = match.group(0)!;
      if (token.length > 6 &&
          token.substring(0, 5).toLowerCase() == '@get:') {
        params.add(RuleParam(
            RuleParam.getType, token.substring(6, token.length - 1)));
      } else {
        params.add(RuleParam(
            RuleParam.innerType, token.substring(2, token.length - 2)));
      }
      hasToken = true;
      start = match.end;
    }
    if (body.length > start) {
      if (_splitRegexGap(body.substring(start))) hasToken = true;
    }

    hasInnerRule = params.any((p) => p.type == RuleParam.innerType);

    if (hasToken) {
      // 参数化规则：rule 保留原文，求值期由 makeUp 重建并拆 `##`。
      rule = body;
      elementsRule = body;
    } else {
      // 纯字面量：构造期拆好 `##`，兼容既有快路径。
      params.clear();
      final parts = body.split('##');
      rule = parts[0].trim();
      if (parts.length > 1) replaceRegex = parts[1];
      if (parts.length > 2) replacement = parts[2];
      if (parts.length > 3) replaceFirst = true;
      elementsRule = rule;
    }
  }

  /// 扫描一个非内嵌表达式片段，产出参数段；返回是否命中 `$N` 分组引用。
  /// 只扫描 `##` 前的主规则（替换尾在 legado 中不做分组替换）。
  bool _splitRegexGap(String segment) {
    final head = segment.split('##')[0];
    var sawGroup = false;
    if (mode != Mode.js && mode != Mode.regex && _dollarPattern.hasMatch(head)) {
      mode = Mode.regex;
    }
    var start = 0;
    for (final match in _dollarPattern.allMatches(head)) {
      if (match.start > start) {
        params.add(RuleParam(
            RuleParam.literalType, segment.substring(start, match.start)));
      }
      final raw = match.group(0)!;
      final index = int.parse(raw.substring(1));
      if (index > 0) {
        params.add(RuleParam(index, raw));
        sawGroup = true;
      } else {
        params.add(RuleParam(RuleParam.literalType, raw));
      }
      start = match.end;
    }
    if (segment.length > start) {
      params.add(RuleParam(RuleParam.literalType, segment.substring(start)));
    }
    return sawGroup;
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

  static Map<String, String> _parseJsonMap(String jsonStr) {
    final result = <String, String>{};
    final inner = jsonStr.trim();
    if (!inner.startsWith('{') || !inner.endsWith('}')) return result;

    // 标准 JSON 优先（legado 走 GSON，转义/引号原样还原）；宽容写法
    // （未加引号的键等）落到下方手工解析。
    try {
      final decoded = jsonDecode(inner);
      if (decoded is Map) {
        decoded.forEach((k, v) {
          if (v != null) result[k.toString()] = v.toString();
        });
        return result;
      }
    } catch (_) {}

    final content = inner.substring(1, inner.length - 1);
    final pairs = _splitJsonPairs(content);
    for (final pair in pairs) {
      final colonIndex = _findJsonColon(pair);
      if (colonIndex > 0) {
        var key = pair.substring(0, colonIndex).trim();
        var value = pair.substring(colonIndex + 1).trim();
        key = _unquoteJson(key);
        value = _unquoteJson(value);
        result[key] = value;
      }
    }
    return result;
  }

  static int _findJsonColon(String pair) {
    bool inString = false;
    bool escaped = false;
    for (int i = 0; i < pair.length; i++) {
      final c = pair[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
      } else if (c == '"') {
        inString = true;
      } else if (c == ':') {
        return i;
      }
    }
    return -1;
  }

  /// 去外层引号并还原 JSON 转义（`\"`、`\\`、`\n`、`\uXXXX` 等）。
  static String _unquoteJson(String s) {
    var v = s;
    if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
      v = v.substring(1, v.length - 1);
    }
    if (!v.contains('\\')) return v;
    return v.replaceAllMapped(RegExp(r'\\(u[0-9a-fA-F]{4}|.)'), (m) {
      final e = m.group(1)!;
      switch (e) {
        case 'n':
          return '\n';
        case 't':
          return '\t';
        case 'r':
          return '\r';
        case 'b':
          return '\b';
        case 'f':
          return '\f';
        case '/':
          return '/';
        case '"':
          return '"';
        case '\\':
          return '\\';
        default:
          if (e.length == 5 && e.startsWith('u')) {
            final code = int.tryParse(e.substring(1), radix: 16);
            if (code != null) return String.fromCharCode(code);
          }
          return m.group(0)!;
      }
    });
  }

  static List<String> _splitJsonPairs(String content) {
    final pairs = <String>[];
    int depth = 0;
    int start = 0;
    bool inString = false;
    bool escaped = false;

    for (int i = 0; i < content.length; i++) {
      final c = content[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
      } else if (c == '{' || c == '[') {
        depth++;
      } else if (c == '}' || c == ']') {
        depth--;
      } else if (c == ',' && depth == 0) {
        pairs.add(content.substring(start, i).trim());
        start = i + 1;
      }
    }
    if (start < content.length) {
      pairs.add(content.substring(start).trim());
    }
    return pairs;
  }
}
