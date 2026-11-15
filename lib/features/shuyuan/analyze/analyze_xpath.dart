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
import 'package:xpath_selector/xpath_selector.dart';
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
      return _queryNodes(rules.isEmpty ? rule : rules.first)
          .nodes
          .map((n) => n.node)
          .toList();
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
    final result = HtmlXPath.node(_root).query(expr);
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

  XPathResult<Node> _queryNodes(String xpath) {
    var expr = xpath.trim();
    final w = _matchFunctionWrapper(expr);
    if (w != null) expr = w.$2.trim();
    return HtmlXPath.node(_root).query(_normalizeExpr(expr));
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
