/// CSS / Jsoup 风格规则解析器：支持 `@` 链式选择器、`@text/@html/@owntext` 取值方法、
/// 索引过滤（`.0`、`.0:5`、`[-1,0:2]`）、`tag./class./id.` 前缀及 `&&/||/%%` 复合规则。
library;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'rule_analyzer.dart';
import 'source_rule.dart';

class AnalyzeByJsoup {
  dynamic content;
  final Element _element;

  AnalyzeByJsoup(this.content) : _element = _parse(content);

  static Element _parse(dynamic doc) {
    if (doc is Element) return doc;
    if (doc is Document) return doc.documentElement!;
    if (doc is String) {
      final document = html_parser.parse(doc);
      return document.documentElement!;
    }
    return html_parser.parse('').documentElement!;
  }

  /// jsoup 伪选择器 `:contains(text)` 匹配（`package:html` 的 querySelectorAll
  /// 不支持该伪类，遇到会抛异常）。这里做通用降级：剥离所有 `:contains(...)`
  /// 片段拿到基础 CSS 选择器，先 querySelectorAll，再按元素文本包含过滤。
  /// 这是主流书源格式里最常用的伪选择器（如 `p:contains(作者)`、
  /// `a:contains(下一页)`），支持它可让大量社区书源开箱即用（源即插件）。
  static final RegExp _containsRegex = RegExp(r':contains\(([^)]*)\)');

  /// 安全查询：透明支持 `:has(...)` / `:contains(...)`，其余走标准
  /// querySelectorAll。任何异常（不支持的伪类 / 非法选择器 / 无引号数字
  /// 属性值）都降级处理，避免整条规则失效。
  ///
  /// `:has(...)` 的降级见 [_queryHas]（剥离片段先查宿主、按子元素过滤、
  /// 支持 `+`/`>`/`~`/空格组合器，括号平衡解析在 [_splitHas]）。
  static List<Element> _safeQuery(Element root, String selector) {
    final s = selector.trim();
    if (s.isEmpty) return const [];
    if (s.contains(':has(')) {
      return _queryHas(root, s);
    }
    if (s.contains(':contains(')) {
      return _queryContains(root, s);
    }
    try {
      return root.querySelectorAll(s);
    } catch (_) {
      // 属性值无引号且以数字开头（如 `[color*=008800]`）时，package:html 的
      // CSS 解析器把值当数字 token 抛 FormatException（jsoup 原生
      // 支持）。通用降级：给无引号属性值补引号后重试，仍失败才返回空。
      final repaired = _repairAttrQuotes(s);
      if (repaired != null && repaired != s) {
        try {
          return root.querySelectorAll(repaired);
        } catch (_) {
          return const [];
        }
      }
      return const [];
    }
  }

  /// 元素自身是否命中 CSS 选择器（jsoup `Element.select` 含自身，
  /// package:html `querySelectorAll` 不含）。借父节点查询后按身份比对，
  /// 无父节点（解析根）时无从判断，按不命中处理。
  static bool _matchesSelf(Element el, String selector) {
    final s = selector.trim();
    if (s.isEmpty) return false;
    final parent = el.parent;
    if (parent == null) return false;
    try {
      return parent.querySelectorAll(s).any((e) => identical(e, el));
    } catch (_) {
      return false;
    }
  }

  /// 给选择器中「无引号属性值」补引号：
  /// `[color*=008800]` → `[color*="008800"]`、`[type=text]` → `[type="text"]`。
  /// 已带引号的值（`[href*="soft"]`）不匹配、原样保留；选择器不含属性段时
  /// 返回 null（表示无需修复）。
  static String? _repairAttrQuotes(String selector) {
    if (!selector.contains('[')) return null;
    var changed = false;
    // 只匹配无引号属性值（值不含引号，用「非 ] 非空白」字符类表达），
    // 已带引号的值（如 [href*="soft"]）不会被误伤。
    final repaired = selector.replaceAllMapped(
      RegExp(r'\[([\w-]+)\s*(\*=|^=|\$=|~=|\|=|=)\s*([^\]\s]+)\]'),
      (m) {
        changed = true;
        return '[${m.group(1)}${m.group(2)}"${m.group(3)}"]';
      },
    );
    return changed ? repaired : null;
  }

  /// 提取选择器中第一个 `:has(...)` 的三段（宿主 / inner / 后续组合器）。
  ///
  /// inner 可能嵌套 `:contains(...)` 等带括号的选择器（如
  /// `p:has(strong font:contains(小说简介)) + p`），须按括号平衡扫描
  /// 而非正则 `[^)]*`（后者会在 inner 内层的 `)` 处提前截断）。
  static (String, String, String)? _splitHas(String selector) {
    final start = selector.indexOf(':has(');
    if (start < 0) return null;
    var depth = 0;
    var inQuote = false;
    for (var i = start + 5; i < selector.length; i++) {
      final c = selector[i];
      if (c == "'" || c == '"') {
        inQuote = !inQuote;
        continue;
      }
      if (inQuote) continue;
      if (c == '(') {
        depth++;
      } else if (c == ')') {
        if (depth == 0) {
          return (
            selector.substring(0, start).trim(),
            selector.substring(start + 5, i).trim(),
            selector.substring(i + 1).trim(),
          );
        }
        depth--;
      }
    }
    return null;
  }

  /// 处理含 `:has(...)` 的选择器（支持逗号分组、`:contains` 嵌套与
  /// `+` / `>` / `~` / 空格组合器）。
  ///
  /// 语义（与 jsoup 一致）：`:has(inner)` 修饰其宿主元素，先按
  /// 宿主选择器查出候选，过滤出「包含匹配 inner 的子元素」的宿主；若
  /// `:has(...)` 后还有组合器（如 `p:has(strong) + p`），再对每个宿主
  /// 应用组合器得到目标元素。
  static List<Element> _queryHas(Element root, String selector) {
    final result = <Element>[];
    for (final group in selector.split(',')) {
      var g = group.trim();
      if (g.isEmpty) continue;
      final parts = _splitHas(g);
      if (parts == null) {
        result.addAll(_safeQuery(root, g));
        continue;
      }
      final (before, inner, after) = parts;

      // 宿主元素：before 为空时（`:has` 位于开头）以全部元素为候选。
      List<Element> hosts;
      if (before.isEmpty) {
        hosts = root.querySelectorAll('*');
      } else {
        hosts = _safeQuery(root, before);
      }
      // 过滤出包含匹配 inner 的子元素的宿主（inner 可含 :contains 等，
      // 递归走 _safeQuery 透明处理）。
      if (inner.isNotEmpty) {
        hosts = hosts.where((el) => _safeQuery(el, inner).isNotEmpty).toList();
      }
      result.addAll(_applyAfterCombinator(hosts, after));
    }
    return result;
  }

  /// 对 `:has(...)` 宿主应用其后的组合器（` + p` / ` > p` / ` ~ p` / ` p`），
  /// 无组合器（after 为空）时原样返回宿主。
  static List<Element> _applyAfterCombinator(
      List<Element> hosts, String after) {
    if (after.isEmpty) return hosts;
    final m = RegExp(r'^([\s]*)([>+~]?)([\s]*)(.+)$').firstMatch(after);
    if (m == null) return hosts;
    final comb = m.group(2) ?? '';
    final target = m.group(4)!.trim();
    final out = <Element>[];
    for (final host in hosts) {
      List<Element> candidates;
      switch (comb) {
        case '+':
          final ns = host.nextElementSibling;
          candidates = ns != null ? [ns] : const [];
          break;
        case '>':
          candidates = host.children;
          break;
        case '~':
          // 一般兄弟组合器：父元素 children 中位于 host 之后的全部元素。
          final parent = host.parent;
          if (parent != null) {
            final siblings = parent.children;
            final idx = siblings.indexOf(host);
            candidates = idx >= 0 && idx < siblings.length - 1
                ? siblings.sublist(idx + 1)
                : const <Element>[];
          } else {
            candidates = const <Element>[];
          }
          break;
        default: // 空格：后代元素
          try {
            candidates = host.querySelectorAll('*');
          } catch (_) {
            candidates = const [];
          }
      }
      for (final c in candidates) {
        if (_matchesSelector(c, target)) out.add(c);
      }
    }
    return out;
  }

  /// 判断元素是否匹配选择器。`package:html` 的 Element 无 matches()，
  /// 用「父元素 querySelectorAll 的结果包含该元素」等价判定；选择器含
  /// `:contains(...)` 时降级为「基础选择器命中 + 文本包含」。
  static bool _matchesSelector(Element el, String selector) {
    final parent = el.parent;
    if (parent == null) return false;
    if (selector.contains(':contains(')) {
      final texts = <String>[];
      final base = selector.replaceAllMapped(_containsRegex, (mm) {
        final t = (mm.group(1) ?? '').trim();
        if (t.isNotEmpty) texts.add(t);
        return '';
      }).trim();
      try {
        final els =
            base.isEmpty ? parent.querySelectorAll('*') : parent.querySelectorAll(base);
        return els.contains(el) && texts.every(el.text.contains);
      } catch (_) {
        return false;
      }
    }
    try {
      return parent.querySelectorAll(selector).contains(el);
    } catch (_) {
      return false;
    }
  }

  /// 处理含 `:contains(...)` 的选择器（支持逗号分组与多个 :contains 叠加）。
  static List<Element> _queryContains(Element root, String selector) {
    final result = <Element>[];
    for (final group in selector.split(',')) {
      var g = group.trim();
      if (g.isEmpty) continue;
      final texts = <String>[];
      g = g.replaceAllMapped(_containsRegex, (m) {
        final t = (m.group(1) ?? '').trim();
        if (t.isNotEmpty) texts.add(t);
        return '';
      }).trim();

      List<Element> base;
      if (g.isEmpty) {
        base = root.querySelectorAll('*');
      } else {
        try {
          base = root.querySelectorAll(g);
        } catch (_) {
          base = const [];
        }
      }
      for (final el in base) {
        final text = el.text;
        if (texts.every(text.contains) && !result.contains(el)) {
          result.add(el);
        }
      }
    }
    return result;
  }

  /// 主入口：获取字符串列表，支持 @ 链式选择器。
  List<String> getStringList(String ruleStr) {
    if (ruleStr.isEmpty) return [];

    final sourceRule = SourceRule(ruleStr);
    final elementsRule = sourceRule.elementsRule;

    if (elementsRule.isEmpty) {
      return [_element.text.trim()];
    }

    final ruleAnalyzer = RuleAnalyzer(elementsRule);
    final ruleStrs = ruleAnalyzer.splitRule(['&&', '||', '%%']);
    final results = <List<String>>[];

    for (final ruleStrX in ruleStrs) {
      final temp = sourceRule.isCss
          ? _getResultLastCss(_element, ruleStrX)
          : _getResultList(ruleStrX);

      if (temp.isNotEmpty) {
        results.add(temp);
        if (ruleAnalyzer.elementsType == '||') break;
      }
    }

    if (results.isEmpty) return [];

    final textS = <String>[];
    if (ruleAnalyzer.elementsType == '%%') {
      for (int i = 0; i < results[0].length; i++) {
        for (final temp in results) {
          if (i < temp.length) {
            textS.add(temp[i]);
          }
        }
      }
    } else {
      for (final temp in results) {
        textS.addAll(temp);
      }
    }

    return textS;
  }

  List<String> _getResultList(String ruleStr) {
    if (ruleStr.isEmpty) return [];

    var elements = <Element>[_element];
    final rule = RuleAnalyzer(ruleStr);
    rule.trim();
    final rules = rule.splitRule(['@']);
    final last = rules.length - 1;

    // 无 `@` 的末段规则：legado 语义是「对当前元素取该属性名」
    // （getResultLast 默认 element.attr(lastRule)），`chapterUrl: "href"`、
    // `coverUrl: "src"`、`content` 等社区源常见写法全靠这条生效。
    // 当前元素没有该属性时才回退为纯选择器取 text（兼容 `.bookname` 这类
    // 无 `@text` 的旧式规则）。
    if (last == 0) {
      final r = rules[0].trim();
      final lowerR = r.toLowerCase();
      if (lowerR == 'text' ||
          lowerR == 'textnodes' ||
          lowerR == 'owntext' ||
          lowerR == 'html' ||
          lowerR == 'all') {
        return _getResultLast([_element], r);
      }
      final attr = _element.attributes[r] ?? _element.attributes[lowerR];
      if (attr != null && attr.isNotEmpty) return [attr];
      final selected = _getElementsSingle(_element, r);
      return _getResultLast(selected, 'text');
    }

    for (int i = 0; i < last; i++) {
      final r = rules[i].trim();
      final indexMatch = RegExp(r'^(-?\d+)$').firstMatch(r);
      if (indexMatch != null) {
        final index = int.parse(r);
        final len = elements.length;
        if (index >= 0 && index < len) {
          elements = [elements[index]];
        } else if (index < 0 && len >= -index) {
          elements = [elements[len + index]];
        } else {
          elements = [];
        }
      } else {
        final es = <Element>[];
        for (final elt in elements) {
          es.addAll(_getElementsSingle(elt, r));
        }
        elements = es;
      }
    }

    if (elements.isEmpty) return [];
    return _getResultLast(elements, rules[last]);
  }

  /// 按单步规则获取元素：对齐 legado `ElementsSingle`（下标 + 前缀 + CSS 回退）。
  List<Element> _getElementsSingle(Element temp, String rule) {
    return _ElementsSingle(rule).select(temp);
  }

  /// 按最后一步方法获取结果（text/html/owntext/属性名 等）。
  List<String> _getResultLast(List<Element> elements, String method) {
    final result = <String>[];
    final lowerMethod = method.toLowerCase();

    switch (lowerMethod) {
      case 'text':
        for (final el in elements) {
          final text = el.text.trim();
          if (text.isNotEmpty) result.add(text);
        }
        break;
      case 'textnodes':
        // legado 语义：每个文本节点各占一条结果（非按元素 join 成单串）。
        // getString 输出一致（同为 \n 连接）；差异在 getStringList 粒度与
        // ## 替换的逐条应用（按节点过滤章节号等场景）。
        for (final el in elements) {
          final nodes = el.nodes
              .whereType<Text>()
              .map((n) => (n).text.trim())
              .where((s) => s.isNotEmpty);
          for (final t in nodes) {
            result.add(t);
          }
        }
        break;
      case 'owntext':
        for (final el in elements) {
          final text = el.nodes
              .whereType<Text>()
              .map((n) => n.text.trim())
              .where((s) => s.isNotEmpty)
              .join(' ')
              .trim();
          if (text.isNotEmpty) result.add(text);
        }
        break;
      case 'html':
        for (final el in elements) {
          final clone = el.clone(true);
          clone.querySelectorAll('script').forEach((e) => e.remove());
          clone.querySelectorAll('style').forEach((e) => e.remove());
          final html = clone.innerHtml;
          if (html.isNotEmpty) result.add(html);
        }
        break;
      case 'all':
        for (final el in elements) {
          result.add(el.outerHtml);
        }
        break;
      default:
        // 属性提取
        for (final el in elements) {
          final attr = el.attributes[method] ?? '';
          if (attr.isNotEmpty && !result.contains(attr)) result.add(attr);
        }
        break;
    }
    return result;
  }

  /// CSS 规则带结尾 @ 取值方法。
  List<String> _getResultLastCss(Element element, String ruleStr) {
    final lastAt = ruleStr.lastIndexOf('@');
    if (lastAt < 0) {
      final elements = _safeQuery(element, ruleStr);
      return elements.map((e) => e.text.trim()).where((s) => s.isNotEmpty).toList();
    }
    final selector = ruleStr.substring(0, lastAt).trim();
    final extractMethod = ruleStr.substring(lastAt + 1).trim();
    final elements = _safeQuery(element, selector);
    return _getResultLast(elements, extractMethod);
  }

  /// 获取单个字符串（多结果以换行拼接）。
  String getString(String ruleStr) {
    final list = getStringList(ruleStr);
    if (list.isEmpty) return '';
    if (list.length == 1) return list.first;
    return list.join('\n');
  }

  /// 仅取首个字符串（用于 URL 提取）。
  String getString0(String ruleStr) {
    final list = getStringList(ruleStr);
    return list.isEmpty ? '' : list.first;
  }

  /// 获取元素列表（非字符串）。
  List<dynamic> getElements(String ruleStr) {
    if (ruleStr.isEmpty) return [];

    final sourceRule = SourceRule(ruleStr);
    final elementsRule = sourceRule.elementsRule;

    if (elementsRule.isEmpty) return [_element];

    final ruleAnalyzer = RuleAnalyzer(elementsRule);
    final ruleStrs = ruleAnalyzer.splitRule(['&&', '||', '%%']);
    final elementsList = <List<Element>>[];

    for (final ruleStrX in ruleStrs) {
      final elements = sourceRule.isCss
          ? _getElementsCss(_element, ruleStrX)
          : _getElementsNonCss(ruleStrX);

      if (elements.isNotEmpty) {
        elementsList.add(elements);
        if (ruleAnalyzer.elementsType == '||') break;
      }
    }

    if (elementsList.isEmpty) return [];

    final result = <Element>[];
    if (ruleAnalyzer.elementsType == '%%') {
      for (int i = 0; i < elementsList[0].length; i++) {
        for (final elements in elementsList) {
          if (i < elements.length) {
            result.add(elements[i]);
          }
        }
      }
    } else {
      for (final elements in elementsList) {
        result.addAll(elements);
      }
    }

    return result;
  }

  List<Element> _getElementsCss(Element element, String ruleStr) {
    final lastAt = ruleStr.lastIndexOf('@');
    if (lastAt >= 0) {
      return _safeQuery(element, ruleStr.substring(0, lastAt).trim());
    }
    return _safeQuery(element, ruleStr);
  }

  List<Element> _getElementsNonCss(String ruleStr) {
    if (ruleStr.isEmpty) return [];

    var elements = <Element>[_element];
    final rule = RuleAnalyzer(ruleStr);
    rule.trim();
    final rules = rule.splitRule(['@']);

    for (final r in rules) {
      final es = <Element>[];
      for (final elt in elements) {
        es.addAll(_getElementsSingle(elt, r));
      }
      elements = es;
    }

    return elements;
  }

  dynamic getObject(String rule) {
    if (rule.isEmpty) return null;

    final list = getStringList(rule);
    if (list.isEmpty) return null;
    if (list.length == 1) return list.first;

    try {
      final elements = getElements(rule);
      if (elements.isEmpty) return null;
      final el = elements.first;
      if (el is Element) {
        return {
          'text': el.text.trim(),
          'html': el.innerHtml,
          ...el.attributes,
        };
      }
      return el;
    } catch (_) {
      return list.first;
    }
  }
}

/// legado `AnalyzeByJSoup.ElementsSingle` 的 Dart 移植：
/// - 旧式索引：`a.0` / `tag.li!0` / `tag.div.-1:10:2`（`:` 分隔多个索引）
/// - 新式索引：`tag.div[-1, 3:-2:-10, 2]`、`[8:]`、`[!0]`、`[-1:0]`（反向）
/// - 前缀：`children` / `class.X` / `tag.X` / `id.X` / `text.X`，其余按 CSS
/// 解析顺序、负索引、区间 interval/step、排除 `!` 均按 legado 原语义。
class _ElementsSingle {
  /// 对齐 legado：默认 `.`（选择），无索引的普通规则由 [_findIndexSet]
  /// 末尾显式改写为 `' '`（返回全部元素）。
  String split = '.';
  String beforeRule = '';
  final List<int> indexDefault = <int>[];
  final List<Object> indexes = <Object>[];

  _ElementsSingle(String rule) {
    _findIndexSet(rule);
  }

  List<Element> select(Element temp) {
    List<Element> elements;
    if (beforeRule.isEmpty) {
      elements = temp.children;
    } else {
      final rules = beforeRule.split('.');
      switch (rules[0]) {
        case 'children':
          elements = temp.children;
          break;
        // legado 用 jsoup Collector 取 class/tag，**包含元素自身**：
        // `class.onefourbox@tag.a` 选中 <a> 后，书源再写 `tag.a@href`
        // 即取该 <a> 自身的 href。package:html 的 getElementsByClassName/
        // getElementsByTagName 只查后代，缺自身会导致整类「列表项即目标
        // 标签」的源取不到 URL（2026-11-15 蚂蚁阅读实测）。
        case 'class':
          elements = rules.length > 1
              ? _withSelfByClass(temp, rules[1])
              : const <Element>[];
          break;
        case 'tag':
          elements = rules.length > 1
              ? _withSelfByTag(temp, rules[1])
              : const <Element>[];
          break;
        case 'id':
          elements = _collectById(temp, rules.length > 1 ? rules[1] : '');
          break;
        case 'text':
          elements = _collectContainingOwnText(
              temp, rules.length > 1 ? rules[1] : '');
          break;
        default:
          elements = AnalyzeByJsoup._safeQuery(temp, beforeRule);
          if (AnalyzeByJsoup._matchesSelf(temp, beforeRule)) {
            elements = <Element>[temp, ...elements];
          }
      }
    }

    final len = elements.length;
    final lastIndexes = indexDefault.isNotEmpty
        ? indexDefault.length - 1
        : indexes.length - 1;
    final indexSet = <int>{};

    if (indexes.isEmpty) {
      for (var ix = lastIndexes; ix >= 0; ix--) {
        final it = indexDefault[ix];
        if (it >= 0 && it < len) {
          indexSet.add(it);
        } else if (it < 0 && len >= -it) {
          indexSet.add(it + len);
        }
      }
    } else {
      for (var ix = lastIndexes; ix >= 0; ix--) {
        final item = indexes[ix];
        if (item is _IndexRange) {
          var start = item.start ?? 0;
          if (start < 0) start += len;
          var end = item.end ?? (len - 1);
          if (end < 0) end += len;
          if ((start < 0 && end < 0) || (start >= len && end >= len)) {
            continue;
          }
          if (start >= len) {
            start = len - 1;
          } else if (start < 0) {
            start = 0;
          }
          if (end >= len) {
            end = len - 1;
          } else if (end < 0) {
            end = 0;
          }
          if (start == end || item.step >= len) {
            indexSet.add(start);
            continue;
          }
          final step = item.step > 0
              ? item.step
              : (-item.step < len ? item.step + len : 1);
          if (end > start) {
            for (var i = start; i <= end; i += step) {
              indexSet.add(i);
            }
          } else {
            for (var i = start; i >= end; i -= step) {
              indexSet.add(i);
            }
          }
        } else {
          final it = item as int;
          if (it >= 0 && it < len) {
            indexSet.add(it);
          } else if (it < 0 && len >= -it) {
            indexSet.add(it + len);
          }
        }
      }
    }

    if (split == '!') {
      final result = <Element>[];
      for (var i = 0; i < len; i++) {
        if (!indexSet.contains(i)) result.add(elements[i]);
      }
      return result;
    }
    if (split == '.') {
      final result = <Element>[];
      for (final i in indexSet) {
        if (i >= 0 && i < len) result.add(elements[i]);
      }
      return result;
    }
    return elements;
  }

  /// `class.X[ Y]` 命中自身时置于结果首位（jsoup 含自身的语义）。
  /// 多个类名以空格分隔时为 AND 关系（对齐 jsoup hasClass 的多类支持）。
  static List<Element> _withSelfByClass(Element temp, String classNames) {
    final descendants = temp.getElementsByClassName(classNames);
    final tokens = classNames
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    final classes = temp.classes;
    if (tokens.isNotEmpty && tokens.every(classes.contains)) {
      return <Element>[temp, ...descendants];
    }
    return descendants;
  }

  /// `tag.X` 命中自身时置于结果首位（jsoup 含自身的语义）。
  static List<Element> _withSelfByTag(Element temp, String tag) {
    final descendants = temp.getElementsByTagName(tag);
    if ((temp.localName ?? '').toLowerCase() == tag.trim().toLowerCase()) {
      return <Element>[temp, ...descendants];
    }
    return descendants;
  }

  static List<Element> _collectById(Element root, String id) {
    final result = <Element>[];
    void walk(Element el) {
      if (el.attributes['id'] == id) result.add(el);
      for (final child in el.children) {
        walk(child);
      }
    }

    walk(root);
    return result;
  }

  static String _ownText(Element el) => el.nodes
      .whereType<Text>()
      .map((n) => n.text)
      .join()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static List<Element> _collectContainingOwnText(Element root, String text) {
    final needle = text.toLowerCase();
    final result = <Element>[];
    void walk(Element el) {
      if (_ownText(el).toLowerCase().contains(needle)) result.add(el);
      for (final child in el.children) {
        walk(child);
      }
    }

    walk(root);
    return result;
  }

  /// 解析规则尾部的索引写法，结果写入 [split]/[beforeRule]/[indexDefault]/
  /// [indexes]。逐字符逆向扫描（与 legado 完全一致），遇到非索引用法时
  /// 视为整条 CSS 规则。
  void _findIndexSet(String rule) {
    final rus = rule.trim();
    if (rus.isEmpty) return;

    var len = rus.length;
    int? curInt;
    var curMinus = false;
    final curList = <int?>[];
    var l = '';
    final head = rus[len - 1] == ']';

    if (head) {
      len--;
      while (len-- >= 0) {
        final rl = rus[len];
        if (rl == ' ') continue;
        if (_isDigit(rl)) {
          l = rl + l;
        } else if (rl == '-') {
          curMinus = true;
        } else {
          curInt = l.isEmpty ? null : (curMinus ? -int.parse(l) : int.parse(l));
          if (rl == ':') {
            curList.add(curInt);
          } else {
            if (curList.isEmpty) {
              if (curInt == null) break;
              indexes.add(curInt);
            } else {
              indexes.add(_IndexRange(
                curInt,
                curList.last,
                curList.length == 2 ? (curList.first ?? 1) : 1,
              ));
              curList.clear();
            }
            var sep = rl;
            if (sep == '!') {
              split = '!';
              do {
                sep = rus[--len];
              } while (len > 0 && sep == ' ');
            }
            if (sep == '[') {
              beforeRule = rus.substring(0, len);
              return;
            }
            if (sep != ',') break;
          }
          l = '';
          curMinus = false;
        }
      }
    } else {
      while (len-- >= 0) {
        final rl = rus[len];
        if (rl == ' ') continue;
        if (_isDigit(rl)) {
          l = rl + l;
        } else if (rl == '-') {
          curMinus = true;
        } else {
          if (rl == '!' || rl == '.' || rl == ':') {
            if (l.isNotEmpty) {
              indexDefault.add(curMinus ? -int.parse(l) : int.parse(l));
            }
            if (rl != ':') {
              split = rl;
              beforeRule = rus.substring(0, len);
              return;
            }
          } else {
            break;
          }
          l = '';
          curMinus = false;
        }
      }
    }

    // 无有效索引或解析中断：整条规则按 CSS/前缀规则处理。
    split = ' ';
    beforeRule = rus;
  }

  static bool _isDigit(String c) {
    final code = c.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }
}

class _IndexRange {
  const _IndexRange(this.start, this.end, this.step);

  final int? start;
  final int? end;
  final int step;
}

