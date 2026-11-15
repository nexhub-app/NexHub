/// XPath 规则解析器：基于 xpath_selector 的 XPath 1.0 引擎。
///
/// 覆盖 legado 书源常用写法：`//`、`/` 路径、`[n]`/`[last()]`/`[contains()]`/
/// `[starts-with()]`/`[position()]` 谓词、`@attr`、`text()`、`|` 并集、
/// `normalize-space()`/`string()` 顶层函数包装，以及 `&&`/`||`/`%%` 复合规则。
///
/// 旧实现只认 `/tag`、`//tag`、`/@attr`、`/text()` 四种形态，且输出
/// package:xml 节点（与 JSoup 分支的 package:html DOM 不互通，链式规则
/// 会解析为空）。xpath_selector 直接运行在 package:html DOM 上，
/// 输出的 Element 可继续被 AnalyzeByJsoup / 内嵌表达式消费。
library;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

import 'rule_analyzer.dart';

class AnalyzeByXPath {
  dynamic content;

  AnalyzeByXPath(this.content);

  late final Node _root = _parse(content);

  static Node _parse(dynamic doc) {
    if (doc is Document) return doc;
    if (doc is Node) return doc;
    if (doc is List) {
      // 元素列表（如上一级 XPath/CSS 结果）：拼成虚拟根，保证 `//` 语义
      // 等价于 legado 的 `JXDocument.create(Elements)`。
      final buf = StringBuffer('<div>');
      for (final item in doc) {
        if (item is Element) {
          buf.write(item.outerHtml);
        } else if (item is Node) {
          buf.write(item.toString());
        } else {
          buf.write(item);
        }
      }
      buf.write('</div>');
      return html_parser.parse(buf.toString());
    }
    var html = doc?.toString() ?? '';
    // 与 legado strToJXDocument 一致：残缺表格片段补全外壳，避免解析器
    // 丢弃 <td>/<tr> 节点导致 `//td` 规则落空。
    if (html.endsWith('</td>')) html = '<tr>$html</tr>';
    if (html.endsWith('</tr>') || html.endsWith('</tbody>')) {
      html = '<table>$html</table>';
    }
    return html_parser.parse(html);
  }

  String getString(String rule) {
    if (rule.isEmpty) return '';
    return _getStringList(rule, percent: false).join('\n');
  }

  List<String> getStringList(String rule) {
    if (rule.isEmpty) return [];
    return _getStringList(rule);
  }

  List<dynamic> getElements(String rule) {
    if (rule.isEmpty) return [];
    return _getNodes(rule);
  }

  List<String> _getStringList(String rule, {bool percent = true}) {
    final split = percent ? ['&&', '||', '%%'] : ['&&', '||'];
    final analyzer = RuleAnalyzer(rule);
    final rules = analyzer.splitRule(split);
    if (rules.length <= 1) {
      return _valuesOf(rules.isEmpty ? rule : rules.first);
    }

    final results = <List<String>>[];
    for (final sub in rules) {
      final temp = _getStringList(sub, percent: percent);
      if (temp.isNotEmpty) {
        results.add(temp);
        if (analyzer.elementsType == '||') break;
      }
    }
    if (results.isEmpty) return [];

    final merged = <String>[];
    if (analyzer.elementsType == '%%') {
      for (var i = 0; i < results.first.length; i++) {
        for (final temp in results) {
          if (i < temp.length) merged.add(temp[i]);
        }
      }
    } else {
      for (final temp in results) {
        merged.addAll(temp);
      }
    }
    return merged;
  }

  List<dynamic> _getNodes(String rule) {
    final analyzer = RuleAnalyzer(rule);
    final rules = analyzer.splitRule(['&&', '||', '%%']);
    if (rules.length <= 1) {
      return _queryNodes(rules.isEmpty ? rule : rules.first);
    }

    final results = <List<dynamic>>[];
    for (final sub in rules) {
      final temp = _getNodes(sub);
      if (temp.isNotEmpty) {
        results.add(temp);
        if (analyzer.elementsType == '||') break;
      }
    }
    if (results.isEmpty) return [];

    final merged = <dynamic>[];
    if (analyzer.elementsType == '%%') {
      for (var i = 0; i < results.first.length; i++) {
        for (final temp in results) {
          if (i < temp.length) merged.add(temp[i]);
        }
      }
    } else {
      for (final temp in results) {
        merged.addAll(temp);
      }
    }
    return merged;
  }

  List<String> _valuesOf(String xpath) {
    var expr = xpath.trim();
    String? wrapper;
    final w = _matchFunctionWrapper(expr);
    if (w != null) {
      wrapper = w.$1;
      expr = w.$2.trim();
    }
    expr = _normalizeExpr(expr);
    final attrOnly = _isAttrOnly(expr);
    final result = _query(expr);
    if (result == null) return <String>[];
    final valueOnly = _isValueOnly(expr);
    final values = <String>[];
    for (var i = 0; i < result.nodes.length; i++) {
      final attr = i < result.attrs.length ? result.attrs[i] : null;
      var value = attr ?? (valueOnly ? null : result.nodes[i].text);
      if (value == null) continue;
      if (wrapper == 'normalize-space') {
        value = value.replaceAll(RegExp(r'\s+'), ' ');
      } else if (attrOnly) {
        // 属性值原样保留，仅去首尾空白。
      } else {
        // jsoup Element.text() 语义：空白折叠，避免源站格式化换行污染结果。
        value = value.replaceAll(RegExp(r'\s+'), ' ');
      }
      value = value.trim();
      if (value.isEmpty) continue;
      values.add(value);
      if (wrapper == 'string') break;
    }
    return values;
  }

  List<dynamic> _queryNodes(String xpath) {
    var expr = xpath.trim();
    final w = _matchFunctionWrapper(expr);
    if (w != null) expr = w.$2.trim();
    final result = _query(_normalizeExpr(expr));
    return result?.nodes ?? const <Node>[];
  }

  /// 查询执行：xpath_selector 对部分谓词（`[@attr]`、`[not(@attr)]`、
  /// `[tag]`、`and @attr` 组合）直接抛 UnsupportedError。这里先原样执行；
  /// 失败时把「末级步骤」上的不支持谓词从表达式移除，再对结果节点做等价
  /// 后置过滤（中间步骤谓词无法后置过滤，仅移除避免整条规则归零）。
  ({List<Node> nodes, List<dynamic> attrs})? _query(String expr) {
    try {
      final r = HtmlXPath.node(_root).query(expr);
      return (
        nodes: r.nodes.map((n) => n.node).toList(),
        attrs: r.attrs,
      );
    } catch (_) {}
    final translated = _translatePredicates(expr);
    if (translated != null) {
      try {
        final r = HtmlXPath.node(_root).query(translated.expr);
        var nodes = r.nodes.map((n) => n.node).toList();
        var attrs = r.attrs;
        if (translated.filters.isNotEmpty) {
          final keep = <int>[];
          for (var i = 0; i < nodes.length; i++) {
            if (translated.filters.every((f) => f(nodes[i]))) keep.add(i);
          }
          nodes = [for (final i in keep) nodes[i]];
          attrs = attrs.length == r.nodes.length
              ? [for (final i in keep) attrs[i]]
              : attrs;
        }
        return (nodes: nodes, attrs: attrs);
      } catch (_) {}
    }
    // 最后兜底：去掉全部谓词，至少返回路径命中的节点。
    final stripped = _stripAllPredicates(expr);
    if (stripped != expr) {
      try {
        final r = HtmlXPath.node(_root).query(stripped);
        return (
          nodes: r.nodes.map((n) => n.node).toList(),
          attrs: r.attrs,
        );
      } catch (_) {}
    }
    return null;
  }

  /// 谓词翻译：保留 xpath_selector 支持的谓词，移除不支持的谓词；若该
  /// 谓词位于末级步骤，则生成后置过滤器（对原始谓词文本求值）。
  ({String expr, List<bool Function(Node)> filters})? _translatePredicates(
      String expr) {
    final out = StringBuffer();
    final filters = <bool Function(Node)>[];
    var i = 0;
    var changed = false;
    while (i < expr.length) {
      final c = expr[i];
      if (c != '[') {
        out.write(c);
        i++;
        continue;
      }
      final end = _predicateEnd(expr, i);
      if (end < 0) return null;
      final pred = expr.substring(i + 1, end);
      if (_predicateSupported(pred)) {
        out.write(expr.substring(i, end + 1));
      } else {
        changed = true;
        if (_isLastStep(expr, end + 1)) {
          final p = pred.trim();
          filters.add((node) => _predMatches(node, p));
        }
      }
      i = end + 1;
    }
    if (!changed) return null;
    return (expr: out.toString(), filters: filters);
  }

  /// 谓词右边界（方括号平衡、忽略引号内括号）。
  static int _predicateEnd(String s, int open) {
    var depth = 0;
    var quote = '';
    for (var i = open; i < s.length; i++) {
      final c = s[i];
      if (quote.isNotEmpty) {
        if (c == '\\') {
          i++;
        } else if (c == quote) {
          quote = '';
        }
        continue;
      }
      if (c == "'" || c == '"') {
        quote = c;
      } else if (c == '[') {
        depth++;
      } else if (c == ']') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  /// 谓词之后是否还有路径步骤（`]/a`、`]//*` 等）；尾部 `/text()`、
  /// `/@attr` 不算新步骤。
  static bool _isLastStep(String s, int afterClose) {
    var rest = s.substring(afterClose).trim();
    rest = rest.replaceFirst(RegExp(r'^/(text\(\)|@[\w-]+)\s*$'), '');
    return !rest.contains('/');
  }

  /// xpath_selector 已验证支持的谓词形态（临时探针
  /// test/_tmp_xpath_probe_test.dart，2026-11-15）：
  /// `[n]`、`[last()]`、`[@a="v"]`、`[contains(...)]`、`[starts-with(...)]`、
  /// 多谓词串联、`and`/`or` 连接的受支持子表达式、`not(...)`。
  static bool _predicateSupported(String pred) {
    var p = pred.trim();
    if (p.isEmpty) return true;
    if (RegExp(r'^\d+$').hasMatch(p)) return true;
    if (p == 'last()') return true;
    // 顶层 and/or 拆分：全部子句支持才算支持。
    final orParts = _splitTopLevel(p, ' or ');
    if (orParts.length > 1) {
      return orParts.every(_predicateSupported);
    }
    final andParts = _splitTopLevel(p, ' and ');
    if (andParts.length > 1) {
      return andParts.every(_predicateSupported);
    }
    if (p.startsWith('!(') && p.endsWith(')')) {
      return _predicateSupported(p.substring(2, p.length - 1));
    }
    if (RegExp(r'^not\(').hasMatch(p) && p.endsWith(')')) {
      return _predicateSupported(p.substring(4, p.length - 1));
    }
    if (RegExp(r'^(contains|starts-with|ends-with|text)\(').hasMatch(p)) {
      return true;
    }
    // `@a="v"` / `@a!="v"` / 数值比较。
    if (RegExp(r'''^@[\w-]+\s*(=|!=|>=|<=|>|<)\s*("[^"]*"|'[^']*'|-?\d+(\.\d+)?)$''')
        .hasMatch(p)) {
      return true;
    }
    return false;
  }

  static List<String> _splitTopLevel(String s, String sep) {
    final parts = <String>[];
    var depth = 0;
    var quote = '';
    var start = 0;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (quote.isNotEmpty) {
        if (c == '\\') {
          i++;
        } else if (c == quote) {
          quote = '';
        }
        continue;
      }
      if (c == "'" || c == '"') {
        quote = c;
      } else if (c == '(' || c == '[') {
        depth++;
      } else if (c == ')' || c == ']') {
        depth--;
      } else if (depth == 0 && s.startsWith(sep, i)) {
        parts.add(s.substring(start, i).trim());
        i += sep.length - 1;
        start = i + 1;
      }
    }
    if (start == 0) return [s.trim()];
    parts.add(s.substring(start).trim());
    return parts;
  }

  /// 后置过滤：对节点求值 XPath 1.0 常用谓词子集。
  static bool _predMatches(Node node, String pred) {
    var p = pred.trim();
    if (p.isEmpty) return true;
    final orParts = _splitTopLevel(p, ' or ');
    if (orParts.length > 1) {
      return orParts.any((e) => _predMatches(node, e));
    }
    final andParts = _splitTopLevel(p, ' and ');
    if (andParts.length > 1) {
      return andParts.every((e) => _predMatches(node, e));
    }
    if (RegExp(r'^not\([\s\S]*\)$').hasMatch(p)) {
      return !_predMatches(node, p.substring(4, p.length - 1));
    }
    final attrOnly = RegExp(r'^@([\w-]+)$').firstMatch(p);
    if (attrOnly != null && node is Element) {
      return node.attributes.containsKey(attrOnly.group(1));
    }
    if (node is! Element) return false;
    final eq = RegExp(
            r'''^@([\w-]+)\s*(=|!=)\s*("[^"]*"|'[^']*')$''')
        .firstMatch(p);
    if (eq != null) {
      final v = node.attributes[eq.group(1)!] ?? '';
      final lit = eq.group(3)!.substring(1, eq.group(3)!.length - 1);
      return eq.group(2) == '=' ? v == lit : v != lit;
    }
    final fn = RegExp(
            r'''^(contains|starts-with|ends-with)\(\s*@([\w-]+)\s*,\s*("[^"]*"|'[^']*')\s*\)$''')
        .firstMatch(p);
    if (fn != null) {
      final v = node.attributes[fn.group(2)!];
      if (v == null) return false;
      final lit = fn.group(3)!.substring(1, fn.group(3)!.length - 1);
      return switch (fn.group(1)) {
        'contains' => v.contains(lit),
        'starts-with' => v.startsWith(lit),
        _ => v.endsWith(lit),
      };
    }
    final tag = RegExp(r'^([\w-]+)$').firstMatch(p);
    if (tag != null) {
      return node.children.any((e) => e.localName == tag.group(1));
    }
    // 无法求值的形态：放行（宁可多取，不因谓词整条归零）。
    return true;
  }

  static String _stripAllPredicates(String expr) {
    final out = StringBuffer();
    var i = 0;
    while (i < expr.length) {
      if (expr[i] == '[') {
        final end = _predicateEnd(expr, i);
        if (end < 0) {
          out.write(expr.substring(i));
          break;
        }
        i = end + 1;
        continue;
      }
      out.write(expr[i]);
      i++;
    }
    return out.toString();
  }

  /// 语法糖归一：`[position()=N]` → `[N]`（xpath_selector 不支持等值
  /// position 比较，但支持 `[N]`/`[last()]` 与 `>`/`<` 比较）。
  static String _normalizeExpr(String expr) {
    return expr.replaceAllMapped(
      RegExp(r'\[\s*position\(\)\s*=\s*(\d+|last\(\))\s*\]'),
      (m) => '[${m.group(1)}]',
    );
  }

  /// 表达式是否为纯属性取值（`@attr` 结尾），用于区分属性值/文本值的
  /// 空白处理策略。
  static bool _isAttrOnly(String expr) {
    final branches = _splitUnion(expr);
    if (branches.isEmpty) return false;
    for (final branch in branches) {
      final b = branch.trim().replaceAll(RegExp(r'/+$'), '');
      final slash = b.lastIndexOf('/');
      final step = slash >= 0 ? b.substring(slash + 1) : b;
      if (!step.startsWith('@')) return false;
    }
    return true;
  }

  /// 顶层 `normalize-space(...)` / `string(...)` 包装识别：
  /// 返回 (函数名, 内层表达式)，要求括号平衡且恰好包裹整串。
  static (String, String)? _matchFunctionWrapper(String expr) {
    final m = RegExp(r'^\s*(normalize-space|string)\s*\(').firstMatch(expr);
    if (m == null) return null;
    final open = m.end - 1;
    var depth = 0;
    var inSingle = false;
    var inDouble = false;
    for (var i = open; i < expr.length; i++) {
      final c = expr[i];
      if (c == "'" && !inDouble) {
        inSingle = !inSingle;
      } else if (c == '"' && !inSingle) {
        inDouble = !inDouble;
      } else if (!inSingle && !inDouble) {
        if (c == '(') {
          depth++;
        } else if (c == ')') {
          depth--;
          if (depth == 0) {
            if (expr.substring(i + 1).trim().isNotEmpty) return null;
            return (m.group(1)!, expr.substring(open + 1, i));
          }
        }
      }
    }
    return null;
  }

  /// 表达式是否以取值步结尾（`@attr` 或函数如 `text()`）。
  /// 并集表达式要求每个分支都是取值步，否则按元素选择处理。
  static bool _isValueOnly(String expr) {
    final branches = _splitUnion(expr);
    for (final branch in branches) {
      final b = branch.trim().replaceAll(RegExp(r'/+$'), '');
      if (b.isEmpty) return false;
      final slash = b.lastIndexOf('/');
      final step = slash >= 0 ? b.substring(slash + 1) : b;
      if (!step.startsWith('@') && !step.endsWith('()')) return false;
    }
    return branches.isNotEmpty;
  }

  static List<String> _splitUnion(String expr) {
    final parts = <String>[];
    var depth = 0;
    var inSingle = false;
    var inDouble = false;
    var start = 0;
    for (var i = 0; i < expr.length; i++) {
      final c = expr[i];
      if (c == "'" && !inDouble) {
        inSingle = !inSingle;
      } else if (c == '"' && !inSingle) {
        inDouble = !inDouble;
      } else if (!inSingle && !inDouble) {
        if (c == '[' || c == '(') depth++;
        if (c == ']' || c == ')') depth--;
        if (c == '|' && depth == 0) {
          parts.add(expr.substring(start, i));
          start = i + 1;
        }
      }
    }
    parts.add(expr.substring(start));
    return parts;
  }
}
