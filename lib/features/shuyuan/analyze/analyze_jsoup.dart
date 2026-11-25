/// CSS / Jsoup 风格规则解析器：支持 `@` 链式选择器、`@text/@html/@owntext` 取值方法、
/// 索引过滤（`.0`、`.0:5`、`[-1,0:2]`）、`tag./class./id.` 前缀及 `&&/||/%%` 复合规则。
library;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'rule_analyzer.dart';
import 'source_rule.dart';
import 'string_utils.dart';

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

  // ---- jsoup 取值语义（legado AnalyzeByJSoup 依赖） ----
  //
  // legado 用 jsoup 的 `Element.text()/ownText()/attr()/getElementsByClass()`
  // 取值，package:html 的同名能力语义不同，这里按 jsoup 实测行为逐项对齐：
  //  - `text()`：ASCII 空白（含 &nbsp;）折叠为单空格；块级元素与 `<br>`
  //    在进入时补一个空格，块级元素后紧跟文本节点时在离开时也补一个；
  //    script/style 内容不参与；pre/plaintext/title/textarea 保留原始空白；
  //    U+3000 原样保留，末尾按 ASCII 修剪。
  //  - `ownText()`：只取直接文本节点（同样折叠），`<br>` 补空格，子元素忽略。
  //  - `attr()`：属性名大小写不敏感。
  //  - `class.X`：类名大小写不敏感、含自身；`tag.X`：标签名大小写不敏感、含自身。
  static const Set<String> _jsoupBlockTags = {
    'address', 'applet', 'article', 'aside', 'audio', 'blockquote', 'body',
    'canvas', 'caption', 'center', 'col', 'colgroup', 'dd', 'del', 'details',
    'dir', 'div', 'dl', 'dt', 'fieldset', 'figcaption', 'figure', 'footer',
    'form', 'frame', 'frameset', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'head',
    'header', 'hgroup', 'hr', 'html', 'ins', 'li', 'link', 'listing', 'main',
    'marquee', 'math', 'menu', 'meta', 'nav', 'noframes', 'noscript', 'ol',
    'p', 'plaintext', 'pre', 'script', 'section', 'style', 'svg', 'table',
    'tbody', 'td', 'template', 'tfoot', 'th', 'thead', 'title', 'tr', 'ul',
    'video',
  };

  static const Set<String> _jsoupPreserveTags = {
    'pre',
    'plaintext',
    'title',
    'textarea',
  };

  static bool _isJsoupActualWhitespace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D || c == 0xA0;

  // Java `Character.isWhitespace` 的近似（class 属性分词用）。
  static bool _isJavaWhitespace(int c) =>
      c == 0x20 || (c >= 0x09 && c <= 0x0D) || c == 0x1C || c == 0x1D ||
      c == 0x1E || c == 0x1F;

  /// jsoup `StringUtil.normaliseWhitespace`：空白连段折叠为单空格，不修剪。
  static String _normaliseJsoupWhitespace(String text) {
    final buf = StringBuffer();
    var lastWasWs = false;
    for (final c in text.codeUnits) {
      if (_isJsoupActualWhitespace(c)) {
        if (lastWasWs) continue;
        buf.write(' ');
        lastWasWs = true;
      } else {
        buf.writeCharCode(c);
        lastWasWs = false;
      }
    }
    return buf.toString();
  }

  /// jsoup `Element.text()`（legado `getResultLast("text")`）。
  static String _jsoupText(Element root) {
    final out = _JsoupTextBuf();
    void walk(Element el) {
      final name = (el.localName ?? '').toLowerCase();
      final isBlock = _jsoupBlockTags.contains(name);
      if (!out.isEmpty && out.last != 0x20 && (isBlock || name == 'br')) {
        out.write(' ');
      }
      if (name != 'script' && name != 'style') {
        final preserve = _jsoupPreserveTags.contains(name);
        for (final node in el.nodes) {
          if (node is Text) {
            preserve ? out.write(node.text) : out.writeNormalised(node.text);
          } else if (node is Element) {
            walk(node);
          }
        }
      }
      if (isBlock && !out.isEmpty && out.last != 0x20 && _nextSiblingIsText(el)) {
        out.write(' ');
      }
    }

    walk(root);
    return StringUtils.trimAscii(out.toString());
  }

  static bool _nextSiblingIsText(Element el) {
    final parent = el.parentNode;
    if (parent == null) return false;
    final nodes = parent.nodes;
    final index = nodes.indexOf(el);
    return index >= 0 && index + 1 < nodes.length && nodes[index + 1] is Text;
  }

  /// jsoup `Element.ownText()`（legado `getResultLast("ownText")`）。
  static String _jsoupOwnText(Element el) {
    final out = _JsoupTextBuf();
    final preserve =
        _jsoupPreserveTags.contains((el.localName ?? '').toLowerCase());
    for (final node in el.nodes) {
      if (node is Text) {
        preserve ? out.write(node.text) : out.writeNormalised(node.text);
      } else if (node is Element &&
          (node.localName ?? '').toLowerCase() == 'br' &&
          !out.isEmpty &&
          out.last != 0x20) {
        out.write(' ');
      }
    }
    return StringUtils.trimAscii(out.toString());
  }

  /// jsoup `Element.data()`：拼接 script/style 的数据节点内容。
  static String _jsoupData(Element root) {
    final buf = StringBuffer();
    void walk(Element el) {
      for (final node in el.nodes) {
        if (node is! Element) continue;
        final name = (node.localName ?? '').toLowerCase();
        if (name == 'script' || name == 'style') {
          buf.write(node.text);
        } else {
          walk(node);
        }
      }
    }

    walk(root);
    return buf.toString();
  }

  /// jsoup `Element.attr()`：属性名大小写不敏感，缺失返回空串。
  static String _attrJsoup(Element el, String name) {
    final direct = el.attributes[name];
    if (direct != null) return direct;
    if (name.isEmpty) return '';
    final lower = name.toLowerCase();
    for (final entry in el.attributes.entries) {
      if (entry.key.toString().toLowerCase() == lower) return entry.value;
    }
    return '';
  }

  /// jsoup `Element.hasClass()`：大小写不敏感；类名整体等于 class 属性
  /// 或等于其中单个分词均命中。
  static bool _hasClassJsoup(Element el, String className) {
    if (className.isEmpty) return false;
    final attr = _attrJsoup(el, 'class');
    if (attr.isEmpty || attr.length < className.length) return false;
    final want = className.toLowerCase();
    if (attr.length == className.length) return attr.toLowerCase() == want;
    var inClass = false;
    var start = 0;
    for (var i = 0; i < attr.length; i++) {
      if (_isJavaWhitespace(attr.codeUnitAt(i))) {
        if (inClass) {
          if (i - start == className.length &&
              attr.substring(start, i).toLowerCase() == want) {
            return true;
          }
          inClass = false;
        }
      } else if (!inClass) {
        inClass = true;
        start = i;
      }
    }
    return inClass &&
        attr.length - start == className.length &&
        attr.substring(start).toLowerCase() == want;
  }

  /// jsoup `Element.getElementsByClass()`：文档序遍历、含自身。
  static List<Element> _collectByClass(Element root, String className) {
    final result = <Element>[];
    void walk(Element el) {
      if (_hasClassJsoup(el, className)) result.add(el);
      for (final child in el.children) {
        walk(child);
      }
    }

    walk(root);
    return result;
  }

  /// jsoup `Element.getElementsByTag()`：标签名大小写不敏感、含自身。
  static List<Element> _collectByTag(Element root, String tag) {
    final name = tag.trim().toLowerCase();
    final result = <Element>[];
    void walk(Element el) {
      if ((el.localName ?? '').toLowerCase() == name) result.add(el);
      for (final child in el.children) {
        walk(child);
      }
    }

    walk(root);
    return result;
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
    if (_needsExtended(s)) {
      return _queryExtended(root, s);
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
    if (_needsExtended(s) || s.contains(':has(')) {
      return _matchesSelector(el, s);
    }
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
    for (final group in _splitTopLevel(selector, ',')) {
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
        hosts = hosts.where((el) => _hasMatch(el, inner)).toList();
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
      // after 可能仍是多段选择器（`> li:nth-child(1) > a`）：第一段在
      // candidates（已应用首个组合器）上过滤，后续段继续按组合器展开。
      final segs = _splitCombinators(target);
      if (segs.length <= 1) {
        for (final c in candidates) {
          if (_matchesSelector(c, target)) out.add(c);
        }
      } else {
        final (b0, c0) = _parseCompound(segs.first.$2.trim());
        final filtered = <Element>[];
        for (final c in candidates) {
          if (b0.isNotEmpty && !_matchesBase(c, b0)) continue;
          if (c0.isNotEmpty && !_matchConds(c, c0)) continue;
          filtered.add(c);
        }
        out.addAll(_advance(filtered, segs, 1));
      }
    }
    return out;
  }

  /// 判断元素是否匹配选择器。`package:html` 的 Element 无 matches()，
  /// 用「父元素 querySelectorAll 的结果包含该元素」等价判定；选择器含
  /// `:contains(...)` 时降级为「基础选择器命中 + 文本包含」。
  static bool _matchesSelector(Element el, String selector) {
    final s = selector.trim();
    if (s.isEmpty) return false;
    final parent = el.parent;
    if (parent == null) return false;
    if (s.contains(':has(')) {
      return _queryHas(parent, s).any((e) => identical(e, el));
    }
    if (_needsExtended(s)) {
      return _queryExtended(parent, s).any((e) => identical(e, el));
    }
    if (s.contains(':contains(')) {
      final texts = <String>[];
      final base = selector.replaceAllMapped(_containsRegex, (mm) {
        final t = (mm.group(1) ?? '').trim();
        if (t.isNotEmpty) texts.add(t);
        return '';
      }).trim();
      try {
        final els =
            base.isEmpty ? parent.querySelectorAll('*') : parent.querySelectorAll(base);
        if (!els.contains(el)) return false;
        final text = _jsoupText(el);
        return texts.every(text.contains);
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
        final text = _jsoupText(el);
        if (texts.every(text.contains) && !result.contains(el)) {
          result.add(el);
        }
      }
    }
    return result;
  }

  // ── jsoup 扩展伪选择器兼容层 ──────────────────────────────────────────
  // package:html 的 querySelectorAll 不支持 jsoup Selector 的扩展伪类：
  // :nth-child / :nth-last-child / :nth-of-type / :nth-last-of-type 返回空，
  // :nth-child(an+b) 直接抛 UnimplementedError，:eq/:gt/:lt/:containsOwn/
  // :matches/:matchesOwn/:empty 同理；旧实现被 _safeQuery 的 catch 吞掉，
  // 表现为规则「命中 0 元素」（目录/搜索列表为空）。这里按 jsoup 语义用
  // 「基础 CSS 查询 + 条件过滤」实现等价能力。

  static final RegExp _aliasPseudoRegex = RegExp(r':(?:first|last)(?![\w-])');

  static bool _needsExtended(String selector) {
    final lower = selector.toLowerCase();
    return lower.contains(':nth-child(') ||
        lower.contains(':nth-last-child(') ||
        lower.contains(':nth-of-type(') ||
        lower.contains(':nth-last-of-type(') ||
        lower.contains(':eq(') ||
        lower.contains(':gt(') ||
        lower.contains(':lt(') ||
        lower.contains(':matches(') ||
        lower.contains(':matchesown(') ||
        lower.contains(':containsown(') ||
        lower.contains(':empty') ||
        _aliasPseudoRegex.hasMatch(lower);
  }

  /// 查询含扩展伪类的选择器（支持逗号分组与 ` ` / `>` / `+` / `~` 组合器）。
  ///
  /// 每段复合选择器拆成「基础 CSS + 伪类条件」：基础部分尽量交给
  /// package:html 原生查询（保留其性能与标准 CSS 能力），条件部分逐元素
  /// 按 jsoup 语义过滤（:eq 为同级 0 起索引，:nth-child 为 1 起序号）。
  static List<Element> _queryExtended(Element root, String selector) {
    final result = <Element>[];
    for (final rawGroup in _splitTopLevel(selector, ',')) {
      final group = rawGroup.trim();
      if (group.isEmpty) continue;
      final segs = _splitCombinators(group);
      if (segs.isEmpty) continue;
      final (headComb, headRaw) = segs.first;
      if (headComb.isNotEmpty) continue; // 相对选择器由 :has 路径处理
      final head = headRaw.trim();
      if (head.isEmpty) continue;
      final (base, conds) = _parseCompound(head);
      var current = _queryDescendants(root, base);
      if (conds.isNotEmpty) {
        current = current.where((e) => _matchConds(e, conds)).toList();
      }
      current = _advance(current, segs, 1);
      for (final el in current) {
        if (!result.any((e) => identical(e, el))) result.add(el);
      }
    }
    return result;
  }

  /// 从第 [from] 段开始继续按组合器展开并应用伪类条件。
  static List<Element> _advance(
      List<Element> start, List<(String, String)> segs, int from) {
    var current = start;
    for (var i = from; i < segs.length; i++) {
      if (current.isEmpty) return current;
      final (comb, raw) = segs[i];
      final compound = raw.trim();
      if (compound.isEmpty) return const [];
      final (base, conds) = _parseCompound(compound);
      var candidates = _expandFrom(current, comb.isEmpty ? ' ' : comb, base);
      if (conds.isNotEmpty) {
        candidates = candidates.where((e) => _matchConds(e, conds)).toList();
      }
      current = candidates;
    }
    return current;
  }

  /// 基础 CSS 查询（空基础 = 全部后代），异常时降级补属性引号后重试。
  static List<Element> _queryDescendants(Element root, String base) {
    if (base.isEmpty) return root.querySelectorAll('*');
    try {
      return root.querySelectorAll(base);
    } catch (_) {
      final repaired = _repairAttrQuotes(base);
      if (repaired != null && repaired != base) {
        try {
          return root.querySelectorAll(repaired);
        } catch (_) {}
      }
      return const [];
    }
  }

  /// 从当前元素集合按组合器展开候选（基础 CSS 命中判断）。
  static List<Element> _expandFrom(
      List<Element> current, String comb, String base) {
    final out = <Element>[];
    void take(List<Element> els) {
      if (base.isEmpty) {
        out.addAll(els);
        return;
      }
      for (final e in els) {
        if (_matchesBase(e, base)) out.add(e);
      }
    }

    for (final host in current) {
      switch (comb) {
        case '>':
          take(host.children);
          break;
        case '+':
          final ns = host.nextElementSibling;
          if (ns != null) take([ns]);
          break;
        case '~':
          final parent = host.parent;
          if (parent != null) {
            final siblings = parent.children;
            final idx = siblings.indexOf(host);
            if (idx >= 0 && idx < siblings.length - 1) {
              take(siblings.sublist(idx + 1));
            }
          }
          break;
        default:
          take(_queryDescendants(host, base));
      }
    }
    return out;
  }

  static bool _matchesBase(Element el, String base) {
    if (base.isEmpty) return true;
    final parent = el.parent;
    if (parent == null) return false;
    try {
      return parent.querySelectorAll(base).any((e) => identical(e, el));
    } catch (_) {
      return false;
    }
  }

  /// 应用伪类条件列表（全部满足才算命中）。
  static bool _matchConds(Element el, List<_PseudoCond> conds) {
    for (final cond in conds) {
      final arg = cond.arg.trim();
      switch (cond.name) {
        case 'nth-child':
          final p = _position(el);
          if (p == null || !_nthMatch(p.$1 + 1, arg)) return false;
          break;
        case 'nth-last-child':
          final p = _position(el);
          if (p == null || !_nthMatch(p.$2 - p.$1, arg)) return false;
          break;
        case 'nth-of-type':
          final p = _typedPosition(el);
          if (p == null || !_nthMatch(p.$1 + 1, arg)) return false;
          break;
        case 'nth-last-of-type':
          final p = _typedPosition(el);
          if (p == null || !_nthMatch(p.$2 - p.$1, arg)) return false;
          break;
        case 'eq':
        case 'gt':
        case 'lt':
          final p = _position(el);
          final idx = _resolveIndex(int.tryParse(arg), p?.$2 ?? 0);
          if (p == null || idx == null) return false;
          if (cond.name == 'eq' && p.$1 != idx) return false;
          if (cond.name == 'gt' && p.$1 <= idx) return false;
          if (cond.name == 'lt' && p.$1 >= idx) return false;
          break;
        case 'contains':
          if (!_jsoupText(el)
              .toLowerCase()
              .contains(_unquote(arg).toLowerCase())) {
            return false;
          }
          break;
        case 'containsown':
          if (!_jsoupOwnText(el)
              .toLowerCase()
              .contains(_unquote(arg).toLowerCase())) {
            return false;
          }
          break;
        case 'matches':
          if (!_regexMatch(arg, _jsoupText(el))) return false;
          break;
        case 'matchesown':
          if (!_regexMatch(arg, _jsoupOwnText(el))) return false;
          break;
        case 'empty':
          if (el.nodes.isNotEmpty) return false;
          break;
        case 'not':
          if (_querySingleMatch(el, arg)) return false;
          break;
        case 'has':
          if (!_hasMatch(el, arg)) return false;
          break;
        default:
          break;
      }
    }
    return true;
  }

  /// `:has(inner)`：inner 可为后代选择器，也支持 `>` / `+` / `~` 相对写法。
  static bool _hasMatch(Element el, String inner) {
    var t = inner.trim();
    if (t.isEmpty) return false;
    if (t.startsWith('>')) {
      final rest = t.substring(1).trim();
      if (rest.isEmpty) return el.children.isNotEmpty;
      return el.children.any((c) => _matchesSelector(c, rest));
    }
    if (t.startsWith('+')) {
      final rest = t.substring(1).trim();
      final ns = el.nextElementSibling;
      return ns != null && (rest.isEmpty || _matchesSelector(ns, rest));
    }
    if (t.startsWith('~')) {
      final rest = t.substring(1).trim();
      final parent = el.parent;
      if (parent == null) return false;
      final idx = parent.children.indexOf(el);
      if (idx < 0) return false;
      return parent.children
          .sublist(idx + 1)
          .any((c) => rest.isEmpty || _matchesSelector(c, rest));
    }
    return _safeQuery(el, t).isNotEmpty;
  }

  /// 元素在同级中的位置（0 起索引, 同级总数）。
  static (int, int)? _position(Element el) {
    final parent = el.parent;
    if (parent == null) return null;
    final idx = parent.children.indexOf(el);
    if (idx < 0) return null;
    return (idx, parent.children.length);
  }

  /// 元素在同标签同级中的位置（nth-of-type 语义）。
  static (int, int)? _typedPosition(Element el) {
    final parent = el.parent;
    if (parent == null) return null;
    final peers =
        parent.children.where((e) => e.localName == el.localName).toList();
    final idx = peers.indexOf(el);
    if (idx < 0) return null;
    return (idx, peers.length);
  }

  static int? _resolveIndex(int? n, int count) {
    if (n == null) return null;
    return n < 0 ? count + n : n;
  }

  /// CSS `an+b` 语义（1 起序号）：支持数字 / odd / even / `2n+1` / `-n+2`。
  static bool _nthMatch(int pos, String raw) {
    final arg = raw.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    if (arg.isEmpty) return false;
    if (arg == 'odd') return pos.isOdd;
    if (arg == 'even') return pos.isEven;
    final anb = RegExp(r'^([+-]?\d*)n([+-]\d+)?$').firstMatch(arg);
    if (anb != null) {
      final aStr = anb.group(1) ?? '';
      final a = aStr.isEmpty || aStr == '+'
          ? 1
          : (aStr == '-' ? -1 : int.parse(aStr));
      final b = int.tryParse(anb.group(2) ?? '0') ?? 0;
      if (a == 0) return pos == b;
      final diff = pos - b;
      return diff % a == 0 && diff ~/ a >= 0;
    }
    final n = int.tryParse(arg);
    return n != null && pos == n;
  }

  static String _unquote(String s) {
    if (s.length >= 2 &&
        ((s.startsWith('"') && s.endsWith('"')) ||
            (s.startsWith("'") && s.endsWith("'")))) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }

  static bool _regexMatch(String pattern, String text) {
    try {
      return RegExp(_unquote(pattern)).hasMatch(text);
    } catch (_) {
      return text.contains(_unquote(pattern));
    }
  }

  static bool _querySingleMatch(Element el, String selector) {
    final parent = el.parent;
    if (parent == null) return false;
    if (_needsExtended(selector)) {
      return _queryExtended(parent, selector).any((e) => identical(e, el));
    }
    if (selector.contains(':has(')) {
      return _queryHas(parent, selector).any((e) => identical(e, el));
    }
    try {
      return parent.querySelectorAll(selector).any((e) => identical(e, el));
    } catch (_) {
      return false;
    }
  }

  /// 括号/引号/属性段感知的顶层分割（用于逗号分组）。
  static List<String> _splitTopLevel(String s, String separators) {
    final out = <String>[];
    final buf = StringBuffer();
    var depth = 0;
    var bracket = 0;
    var quote = '';
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (quote.isNotEmpty) {
        buf.write(c);
        if (c == quote) quote = '';
        continue;
      }
      if (c == '"' || c == "'") {
        quote = c;
        buf.write(c);
        continue;
      }
      if (c == '(') depth++;
      if (c == ')') depth--;
      if (c == '[') bracket++;
      if (c == ']') bracket--;
      if (depth == 0 && bracket == 0 && separators.contains(c)) {
        out.add(buf.toString());
        buf.clear();
        continue;
      }
      buf.write(c);
    }
    out.add(buf.toString());
    return out;
  }

  /// 按顶层 ` ` / `>` / `+` / `~` 拆分为 (组合器, 复合选择器) 序列。
  /// 首段的组合器为空串，其余段缺省为后代组合器（` `）。
  static List<(String, String)> _splitCombinators(String group) {
    final out = <(String, String)>[];
    final buf = StringBuffer();
    var depth = 0;
    var bracket = 0;
    var quote = '';
    var comb = '';

    void flush() {
      final c = comb.isNotEmpty ? comb : (out.isEmpty ? '' : ' ');
      out.add((c, buf.toString()));
      buf.clear();
      comb = '';
    }

    for (var i = 0; i < group.length; i++) {
      final c = group[i];
      if (quote.isNotEmpty) {
        buf.write(c);
        if (c == quote) quote = '';
        continue;
      }
      if (c == '"' || c == "'") {
        quote = c;
        buf.write(c);
        continue;
      }
      if (c == '(') depth++;
      if (c == ')') depth--;
      if (c == '[') bracket++;
      if (c == ']') bracket--;
      if (depth == 0 && bracket == 0) {
        if (c == '>' || c == '+' || c == '~') {
          if (buf.isNotEmpty) flush();
          comb = c;
          continue;
        }
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
          if (buf.isNotEmpty) flush();
          continue;
        }
      }
      buf.write(c);
    }
    if (buf.isNotEmpty) flush();
    return out;
  }

  /// 拆分复合选择器：剥离扩展伪类为条件，其余部分保留给原生 CSS。
  static (String, List<_PseudoCond>) _parseCompound(String compound) {
    final base = StringBuffer();
    final conds = <_PseudoCond>[];
    var i = 0;
    final nameChar = RegExp(r'[\w-]');
    while (i < compound.length) {
      final c = compound[i];
      if (c == '[') {
        var depth = 0;
        var quote = '';
        while (i < compound.length) {
          final ch = compound[i];
          base.write(ch);
          if (quote.isNotEmpty) {
            if (ch == quote) quote = '';
          } else if (ch == '"' || ch == "'") {
            quote = ch;
          } else if (ch == '[') {
            depth++;
          } else if (ch == ']') {
            depth--;
            if (depth == 0) {
              i++;
              break;
            }
          }
          i++;
        }
        continue;
      }
      if (c != ':') {
        base.write(c);
        i++;
        continue;
      }
      if (i + 1 < compound.length && compound[i + 1] == ':') {
        final start = i;
        i += 2;
        while (i < compound.length && nameChar.hasMatch(compound[i])) {
          i++;
        }
        base.write(compound.substring(start, i));
        continue;
      }
      final nameStart = i + 1;
      var j = nameStart;
      while (j < compound.length && nameChar.hasMatch(compound[j])) {
        j++;
      }
      if (j == nameStart) {
        base.write(c);
        i++;
        continue;
      }
      final name = compound.substring(nameStart, j).toLowerCase();
      if (j < compound.length && compound[j] == '(') {
        var depth = 0;
        var quote = '';
        var k = j;
        for (; k < compound.length; k++) {
          final ch = compound[k];
          if (quote.isNotEmpty) {
            if (ch == quote) quote = '';
            continue;
          }
          if (ch == '"' || ch == "'") {
            quote = ch;
            continue;
          }
          if (ch == '(') depth++;
          if (ch == ')') {
            depth--;
            if (depth == 0) break;
          }
        }
        final closed = k < compound.length;
        final arg = closed ? compound.substring(j + 1, k) : '';
        final end = closed ? k + 1 : compound.length;
        switch (name) {
          case 'nth-child':
          case 'nth-last-child':
          case 'nth-of-type':
          case 'nth-last-of-type':
          case 'eq':
          case 'gt':
          case 'lt':
          case 'matches':
          case 'matchesown':
          case 'contains':
          case 'containsown':
          case 'has':
            conds.add(_PseudoCond(name, arg));
            i = end;
            break;
          case 'not':
            if (_needsExtended(arg)) {
              conds.add(_PseudoCond('not', arg));
              i = end;
            } else {
              base.write(compound.substring(i, end));
              i = end;
            }
            break;
          default:
            base.write(compound.substring(i, end));
            i = end;
        }
        continue;
      }
      switch (name) {
        case 'empty':
          conds.add(const _PseudoCond('empty', ''));
          i = j;
          break;
        case 'first':
          conds.add(const _PseudoCond('eq', '0'));
          i = j;
          break;
        case 'last':
          conds.add(const _PseudoCond('eq', '-1'));
          i = j;
          break;
        default:
          base.write(compound.substring(i, j));
          i = j;
      }
    }
    return (base.toString(), conds);
  }

  /// 主入口：获取字符串列表，支持 @ 链式选择器。
  /// [dedupe] 为 false 时属性提取保留重复值。
  ///
  /// 默认去重对齐 legado（`getResultLast` 的 `!result.contains(attr)`），
  /// 但「按序号与另一条规则对齐取值」的场景（段号、赞数这类与条目一一对应
  /// 的字段）必须保留重复：6 条段评的 `data-p` 是 0,0,2,2,4,4，去重后只剩
  /// 3 个值，后续按序号对齐就全乱了。
  List<String> getStringList(String ruleStr, {bool dedupe = true}) {
    if (ruleStr.isEmpty) return [];

    final sourceRule = SourceRule(ruleStr);
    final elementsRule = sourceRule.elementsRule;

    if (elementsRule.isEmpty) {
      // legado：空规则返回 `element.data()`（script/style 数据节点内容）。
      return [_jsoupData(_element)];
    }

    final ruleAnalyzer = RuleAnalyzer(elementsRule);
    final ruleStrs = ruleAnalyzer.splitRule(['&&', '||', '%%']);
    final results = <List<String>>[];

    for (final ruleStrX in ruleStrs) {
      final temp = sourceRule.isCss
          ? _getResultLastCss(_element, ruleStrX, dedupe: dedupe)
          : _getResultList(ruleStrX, dedupe: dedupe);

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

  List<String> _getResultList(String ruleStr, {bool dedupe = true}) {
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
      final attr = _attrJsoup(_element, r);
      if (attr.isNotEmpty) return [attr];
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
    return _getResultLast(elements, rules[last], dedupe: dedupe);
  }

  /// 按单步规则获取元素：对齐 legado `ElementsSingle`（下标 + 前缀 + CSS 回退）。
  List<Element> _getElementsSingle(Element temp, String rule) {
    return _ElementsSingle(rule).select(temp);
  }

  /// 按最后一步方法获取结果（text/html/owntext/属性名 等）。
  List<String> _getResultLast(List<Element> elements, String method,
      {bool dedupe = true}) {
    final result = <String>[];
    final lowerMethod = method.toLowerCase();

    switch (lowerMethod) {
      case 'text':
        for (final el in elements) {
          final text = _jsoupText(el);
          if (text.isNotEmpty) result.add(text);
        }
        break;
      case 'textnodes':
        // legado getResultLast("textNodes")：同一元素的文本节点用 "\n"
        // 合并为一条结果；空节点跳过，元素整体为空则不产出。
        // jsoup TextNode.text() 会折叠空白，再按 ASCII 修剪。
        for (final el in elements) {
          final tn = <String>[];
          for (final node in el.nodes.whereType<Text>()) {
            final text =
                StringUtils.trimAscii(_normaliseJsoupWhitespace(node.text));
            if (text.isNotEmpty) tn.add(text);
          }
          if (tn.isNotEmpty) result.add(tn.join('\n'));
        }
        break;
      case 'owntext':
        for (final el in elements) {
          final text = _jsoupOwnText(el);
          if (text.isNotEmpty) result.add(text);
        }
        break;
      case 'html':
        // legado：移除 script/style 后取 Elements.outerHtml()（所有命中
        // 元素的外层 HTML 拼成一条结果，含元素自身标签）。克隆后再改，
        // 避免污染后续规则复用同一 DOM。
        {
          final buf = StringBuffer();
          for (final el in elements) {
            final clone = el.clone(true);
            clone.querySelectorAll('script').forEach((e) => e.remove());
            clone.querySelectorAll('style').forEach((e) => e.remove());
            buf.write(clone.outerHtml);
          }
          final html = buf.toString();
          if (html.isNotEmpty) result.add(html);
        }
        break;
      case 'all':
        {
          final buf = StringBuffer();
          for (final el in elements) {
            buf.write(el.outerHtml);
          }
          final html = buf.toString();
          if (html.isNotEmpty) result.add(html);
        }
        break;
      default:
        // 属性提取：空值与重复值跳过（legado getResultLast else 分支）。
        // jsoup `attr()` 属性名大小写不敏感。
        for (final el in elements) {
          final attr = _attrJsoup(el, method);
          if (attr.trim().isEmpty) continue;
          if (dedupe && result.contains(attr)) continue;
          result.add(attr);
        }
        break;
    }
    return result;
  }

  /// CSS 规则带结尾 @ 取值方法。
  List<String> _getResultLastCss(Element element, String ruleStr,
      {bool dedupe = true}) {
    final lastAt = ruleStr.lastIndexOf('@');
    if (lastAt < 0) {
      final elements = _safeQuery(element, ruleStr);
      return elements
          .map(_jsoupText)
          .where((s) => s.isNotEmpty)
          .toList();
    }
    final selector = ruleStr.substring(0, lastAt).trim();
    final extractMethod = ruleStr.substring(lastAt + 1).trim();
    final elements = _safeQuery(element, selector);
    return _getResultLast(elements, extractMethod, dedupe: dedupe);
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
          'text': _jsoupText(el),
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

/// 扩展伪类条件（名称统一小写，参数为括号原文）。
class _PseudoCond {
  final String name;
  final String arg;
  const _PseudoCond(this.name, this.arg);
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
        // legado 用 jsoup Collector 取 class/tag，**包含元素自身**且类名/
        // 标签名大小写不敏感：`class.onefourbox@tag.a` 选中 <a> 后，书源
        // 再写 `tag.a@href` 即取该 <a> 自身的 href。
        case 'class':
          elements = rules.length > 1
              ? AnalyzeByJsoup._collectByClass(temp, rules[1])
              : const <Element>[];
          break;
        case 'tag':
          elements = rules.length > 1
              ? AnalyzeByJsoup._collectByTag(temp, rules[1])
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

  static List<Element> _collectContainingOwnText(Element root, String text) {
    final needle = text.toLowerCase();
    final result = <Element>[];
    void walk(Element el) {
      if (AnalyzeByJsoup._jsoupOwnText(el).toLowerCase().contains(needle)) {
        result.add(el);
      }
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

/// 逐字符累积的文本缓冲，记录末字符以复用 jsoup 的「末位空格」判定。
class _JsoupTextBuf {
  final StringBuffer _buf = StringBuffer();
  int last = -1;

  bool get isEmpty => last == -1;

  void write(String s) {
    if (s.isEmpty) return;
    _buf.write(s);
    last = s.codeUnitAt(s.length - 1);
  }

  void writeNormalised(String s) {
    var i = 0;
    while (i < s.length) {
      if (AnalyzeByJsoup._isJsoupActualWhitespace(s.codeUnitAt(i))) {
        if (last != 0x20 && last != -1) write(' ');
        i++;
      } else {
        var j = i + 1;
        while (j < s.length &&
            !AnalyzeByJsoup._isJsoupActualWhitespace(s.codeUnitAt(j))) {
          j++;
        }
        write(s.substring(i, j));
        i = j;
      }
    }
  }

  @override
  String toString() => _buf.toString();
}

