/// JSON 规则解析器：支持 `$.a.b`、`$["key"]`、`$[index]`、`$.a[*].b`（通配后
/// 接字段）、`$..x`（深度扫描）等 JSONPath 风格取值（对齐 jayway JsonPath 在
/// 书源中的常用子集）。
library;

import 'dart:convert';

import 'rule_analyzer.dart';

class AnalyzeByJson {
  dynamic content;

  AnalyzeByJson(this.content) {
    _cachedSource = content;
    _cachedData = _decode(content);
  }

  /// 解析结果缓存（对齐 legado `AnalyzeByJSonPath` 构造期 `JsonPath.parse`
  /// 一次、后续 `ctx.read` 复用）。旧实现每次取值都 `json.decode` 整页，
  /// 列表页逐条取 8 个字段时等于 N×8 次整页解码。
  dynamic _cachedSource;
  dynamic _cachedData;

  /// 内容被外部直接改写（`content = ...`）时按引用变化重新解析。
  dynamic get _jsonData {
    if (!identical(content, _cachedSource)) {
      _cachedSource = content;
      _cachedData = _decode(content);
    }
    return _cachedData;
  }

  static dynamic _decode(dynamic value) {
    if (value is String) {
      try {
        return json.decode(value);
      } catch (_) {
        return null;
      }
    }
    return value;
  }

  String getString(String rule) {
    if (rule.isEmpty) return '';
    // legado AnalyzeByJSonPath：先用平衡切分处理 `&&`/`||`（`||` 短路、
    // `&&` 换行合并），再对单段做 `{$.rule}` 内嵌替换或 JsonPath 取值。
    final ra = RuleAnalyzer(rule);
    final rules = ra.splitRule(const <String>['&&', '||']);
    if (rules.length > 1) {
      final parts = <String>[];
      for (final rl in rules) {
        final temp = getString(rl);
        if (temp.isNotEmpty) {
          parts.add(temp);
          if (ra.elementsType == '||') break;
        }
      }
      return parts.join('\n');
    }
    final single = rules.isEmpty ? rule : rules[0];
    // legado AnalyzeByJSonPath 的 `{$.` innerRule：URL/字段模板里的单花
    // 括号占位符（`{$.book_id}`）按当前 JSON 求值，替换后整串即结果。
    final inner = _replaceInnerRules(single);
    if (inner != null && inner.isNotEmpty) return inner;
    final result = _resolvePath(single);
    if (result == null) return '';
    if (result is List) {
      return result.map((e) => e.toString()).join('\n');
    }
    return result.toString();
  }

  List<String> getStringList(String rule) {
    if (rule.isEmpty) return [];
    final ra = RuleAnalyzer(rule);
    final rules = ra.splitRule(const <String>['&&', '||', '%%']);
    if (rules.length > 1) {
      final results = <List<String>>[];
      for (final rl in rules) {
        final temp = getStringList(rl);
        if (temp.isNotEmpty) {
          results.add(temp);
          if (ra.elementsType == '||') break;
        }
      }
      final result = <String>[];
      if (results.isNotEmpty) {
        if (ra.elementsType == '%%') {
          for (var i = 0; i < results[0].length; i++) {
            for (final temp in results) {
              if (i < temp.length) result.add(temp[i]);
            }
          }
        } else {
          for (final temp in results) {
            result.addAll(temp);
          }
        }
      }
      return result;
    }
    final single = rules.isEmpty ? rule : rules[0];
    final inner = _replaceInnerRules(single);
    if (inner != null && inner.isNotEmpty) return [inner];
    final result = _resolvePath(single);
    if (result == null) return [];
    if (result is List) {
      return result.map((e) => e.toString()).toList();
    }
    return [result.toString()];
  }

  /// 单花括号占位符（`{$.field}`）替换；无占位符时返回 null。
  /// `{{$.field}}` 由规则层内嵌表达式先行处理，这里跳过前置 `{` 的形态。
  ///
  /// 用平衡扫描而不是单层正则：内层规则本身可以带 `{...}`（如
  /// `{$.outer{...}}`），正则的 `[^{}]` 匹配不到会原样透传给 JSONPath。
  String? _replaceInnerRules(String rule) {
    if (!rule.contains(r'{$.')) return null;
    final out = StringBuffer();
    var replaced = false;
    var i = 0;
    while (i < rule.length) {
      final open = rule.indexOf(r'{$', i);
      if (open < 0) {
        out.write(rule.substring(i));
        break;
      }
      // `{{$.x}}` 属于规则层内嵌表达式：前面是 `{` 时整体跳过两个字符。
      if (open > 0 && rule.codeUnitAt(open - 1) == 0x7B) {
        out.write(rule.substring(i, open + 2));
        i = open + 2;
        continue;
      }
      final end = _findInnerRuleEnd(rule, open);
      if (end < 0) {
        out.write(rule.substring(i));
        break;
      }
      out.write(rule.substring(i, open));
      final v = _resolvePath(rule.substring(open + 1, end - 1));
      replaced = true;
      if (v is List) {
        out.write(v.map((e) => e.toString()).join('\n'));
      } else if (v != null) {
        out.write(v.toString());
      }
      i = end;
    }
    return replaced ? out.toString() : null;
  }

  /// 从 [open]（指向 `{`）起找配对的 `}`，返回 `}` 之后的下标；未闭合返回 -1。
  /// 跳过引号内文本与 `\` 转义，保证 `{$.a["}"]}` 不会被提前截断。
  static int _findInnerRuleEnd(String src, int open) {
    var depth = 0;
    var i = open;
    var quote = 0;
    var escaped = false;
    while (i < src.length) {
      final c = src.codeUnitAt(i);
      if (escaped) {
        escaped = false;
        i++;
        continue;
      }
      if (quote != 0) {
        if (c == 0x5C) {
          escaped = true;
        } else if (c == quote) {
          quote = 0;
        }
        i++;
        continue;
      }
      if (c == 0x22 || c == 0x27) {
        quote = c;
      } else if (c == 0x7B) {
        depth++;
      } else if (c == 0x7D) {
        depth--;
        if (depth == 0) return i + 1;
      }
      i++;
    }
    return -1;
  }

  List<dynamic> getList(String rule) {
    if (rule.isEmpty) return [];
    final ra = RuleAnalyzer(rule);
    final rules = ra.splitRule(const <String>['&&', '||', '%%']);
    if (rules.length > 1) {
      final results = <List<dynamic>>[];
      for (final rl in rules) {
        final temp = getList(rl);
        if (temp.isNotEmpty) {
          results.add(temp);
          if (ra.elementsType == '||') break;
        }
      }
      final result = <dynamic>[];
      if (results.isNotEmpty) {
        if (ra.elementsType == '%%') {
          for (var i = 0; i < results[0].length; i++) {
            for (final temp in results) {
              if (i < temp.length) {
                // legado `temp[i]?.let { result.add(it) }`：null 项跳过，
                // 不能把 null 塞进列表（后续按索引取值会错位）。
                final item = temp[i];
                if (item != null) result.add(item);
              }
            }
          }
        } else {
          for (final temp in results) {
            result.addAll(temp);
          }
        }
      }
      return result;
    }
    final result = _resolvePath(rules.isEmpty ? rule : rules[0]);
    if (result == null) return [];
    if (result is List) return result;
    return [result];
  }

  dynamic getObject(String rule) {
    if (rule.isEmpty) return null;
    return _resolvePath(rule);
  }

  dynamic _resolvePath(String path) {
    final data = _jsonData;
    if (data == null) return null;

    final tokens = _tokenize(path);
    if (tokens.isEmpty) return data;
    return _navigate(data, tokens);
  }

  /// 路径分词：`.field`、`['key']`、`["key"]`、`[index]`、`[*]`、`..`（深扫）。
  static List<_JsonPathToken> _tokenize(String path) {
    final tokens = <_JsonPathToken>[];
    var i = 0;
    final s = path;

    while (i < s.length) {
      final c = s[i];
      if (c == r'$') {
        i += 1;
      } else if (c == '.') {
        if (i + 1 < s.length && s[i + 1] == '.') {
          tokens.add(const _JsonPathToken(_JsonTokenType.deepScan, ''));
          i += 2;
        } else {
          i += 1;
        }
      } else if (c == '[') {
        final end = _findBracketEnd(s, i);
        if (end < 0) break;
        var inner = s.substring(i + 1, end).trim();
        // 过滤器 [?(@.a==1)]：剥掉 ?( ) 外壳，保留表达式（求值期对当前
        // 列表逐项判定）。
        if (inner.startsWith('?')) {
          inner = inner.substring(1).trim();
          if (inner.startsWith('(') && inner.endsWith(')')) {
            inner = inner.substring(1, inner.length - 1).trim();
          }
          tokens.add(_JsonPathToken(_JsonTokenType.filter, inner));
        } else if (inner.endsWith('()') &&
            _jsonPathFunctions.contains(inner.substring(0, inner.length - 2))) {
          tokens.add(_JsonPathToken(
              _JsonTokenType.function,
              inner.substring(0, inner.length - 2)));
        } else if (inner.contains(':') &&
            RegExp(r'^-?\d*\s*:\s*-?\d*(\s*:\s*-?\d+)?$').hasMatch(inner)) {
          // 切片 [start:end:step]，支持负数与省略。
          tokens.add(_JsonPathToken(_JsonTokenType.slice, inner));
        } else if (inner == '*' || inner.isEmpty) {
          tokens.add(const _JsonPathToken(_JsonTokenType.wildcard, ''));
        } else if ((inner.startsWith("'") && inner.endsWith("'")) ||
            (inner.startsWith('"') && inner.endsWith('"'))) {
          tokens.add(_JsonPathToken(
              _JsonTokenType.key, inner.substring(1, inner.length - 1)));
        } else {
          final idx = int.tryParse(inner);
          if (idx != null) {
            tokens.add(_JsonPathToken(_JsonTokenType.arrayIndex, inner));
          } else {
            tokens.add(_JsonPathToken(_JsonTokenType.key, inner));
          }
        }
        i = end + 1;
      } else if (c == '@' || c == ',') {
        // 过滤器表达式（[?(@...)]）等不支持的语法：终止分词，按已知前缀求值。
        break;
      } else {
        var j = i;
        while (j < s.length && s[j] != '.' && s[j] != '[') {
          j += 1;
        }
        var name = s.substring(i, j);
        // 点号通配 `$.items.*` / `$..items.*`：jayway 里 `.*` 是通配符，
        // 此前被当成字面 key "*" → 恒无命中（API 型源目录规则高频写法）。
        if (name == '*') {
          tokens.add(const _JsonPathToken(_JsonTokenType.wildcard, ''));
          i = j;
          continue;
        }
        // 点号函数形态 `$.a.length()` / `$.n.max()`：识别为函数 token
        //（jayway 点号/括号两种写法等价，社区源两种都在用）。
        if (name.endsWith('()') &&
            _jsonPathFunctions
                .contains(name.substring(0, name.length - 2))) {
          tokens.add(_JsonPathToken(_JsonTokenType.function,
              name.substring(0, name.length - 2)));
        } else {
          tokens.add(_JsonPathToken(_JsonTokenType.key, name));
        }
        i = j;
      }
    }
    return tokens;
  }

  /// 括号闭合位置（跳过引号内的 `]`）。
  static int _findBracketEnd(String s, int start) {
    var quote = false;
    var quoteChar = '';
    for (var i = start + 1; i < s.length; i++) {
      final c = s[i];
      if (quote) {
        if (c == quoteChar) quote = false;
      } else if (c == "'" || c == '"') {
        quote = true;
        quoteChar = c;
      } else if (c == ']') {
        return i;
      }
    }
    return -1;
  }

  /// 逐 token 导航：通配符把当前节点集合展开为全部子元素，后续 token 逐个
  /// 作用于每个元素（`$.rows[*].name` → 所有 rows 元素的 name 列表）。
  dynamic _navigate(dynamic root, List<_JsonPathToken> tokens) {
    var current = <dynamic>[root];
    for (final token in tokens) {
      final next = <dynamic>[];
      for (final node in current) {
        switch (token.type) {
          case _JsonTokenType.key:
            _applyKey(node, token.name, next);
          case _JsonTokenType.arrayIndex:
            if (node is List) {
              final raw = int.tryParse(token.name);
              if (raw != null) {
                // jayway 负索引从尾部取（`[-1]` = 最后一项）。
                final idx = raw < 0 ? node.length + raw : raw;
                if (idx >= 0 && idx < node.length) next.add(node[idx]);
              }
            }
          case _JsonTokenType.wildcard:
            if (node is List) {
              next.addAll(node);
            } else if (node is Map) {
              next.addAll(node.values);
            }
          case _JsonTokenType.deepScan:
            _collectAll(node, next);
          case _JsonTokenType.slice:
            if (node is List) _applySlice(node, token.name, next);
          case _JsonTokenType.filter:
            if (node is List) {
              for (final item in node) {
                if (_matchesFilter(item, token.name)) next.add(item);
              }
            } else if (node is Map) {
              for (final item in node.values) {
                if (_matchesFilter(item, token.name)) next.add(item);
              }
            }
          case _JsonTokenType.function:
            _applyFunction(node, token.name, next);
        }
      }
      current = next;
    }
    if (current.isEmpty) return null;
    if (current.length == 1) return current.first;
    return current;
  }

  static void _applyKey(dynamic node, String name, List<dynamic> out) {
    if (node is Map) {
      // 不含该键时不追加 null（深度扫描 `$..field` 会遍历大量无关 Map，
      // 追加 null 会把结果污染成 [null, 值, null, ...]）。
      if (node.containsKey(name)) {
        out.add(node[name]);
      }
    } else if (node is List) {
      // 纯数字键作用在数组上等于下标（`$.items.0`）。
      final idx = int.tryParse(name);
      if (idx != null && idx >= 0 && idx < node.length) {
        out.add(node[idx]);
      } else if (name == 'length' || name == 'size') {
        // `$.data.length` 作用在数组上 → 数组长度（社区源高频写法）。
        out.add(node.length);
      }
    }
  }

  /// 切片：`[start:end:step]`，负数从尾部计，省略走默认（start=0、
  /// end=长度、step=1）；step 为负时反向遍历。
  static void _applySlice(List node, String spec, List<dynamic> out) {
    final parts = spec.split(':');
    int? parse(String s) {
      final t = s.trim();
      return t.isEmpty ? null : int.tryParse(t);
    }

    final n = node.length;
    final rawStart = parse(parts[0]);
    final rawEnd = parts.length > 1 ? parse(parts[1]) : null;
    final rawStep = parts.length > 2 ? parse(parts[2]) : null;
    final step = (rawStep ?? 1) == 0 ? 1 : (rawStep ?? 1);
    int norm(int? v, int def) => (v ?? def) < 0 ? n + (v ?? def) : (v ?? def);
    final start = norm(rawStart, step > 0 ? 0 : n - 1).clamp(0, n);
    final end = norm(rawEnd, step > 0 ? n : -1).clamp(-1, n);
    if (step > 0) {
      for (var i = start; i < end; i += step) {
        out.add(node[i]);
      }
    } else {
      for (var i = start; i > end; i += step) {
        if (i >= 0 && i < n) out.add(node[i]);
      }
    }
  }

  /// 过滤表达式求值：`@.a==1` / `@.a!='x'` / `@.a` / `@.length>2` 等。
  /// 支持 `&&`/`||` 组合（jayway 过滤器布尔语义）与前置 `!` 取反。
  bool _matchesFilter(dynamic item, String expr) {
    final orGroups = _splitFilterExpr(expr, '||');
    for (final group in orGroups) {
      final conj = _splitFilterExpr(group, '&&');
      var all = true;
      for (final term in conj) {
        if (!_matchesFilterSingle(item, term)) {
          all = false;
          break;
        }
      }
      if (all) return true;
    }
    return false;
  }

  /// 按顶层分隔符切分过滤器表达式（引号/括号内不切）。
  static List<String> _splitFilterExpr(String expr, String sep) {
    final parts = <String>[];
    var depth = 0;
    var quote = '';
    var start = 0;
    for (var i = 0; i < expr.length; i++) {
      final c = expr[i];
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
      } else if (depth == 0 && expr.startsWith(sep, i)) {
        parts.add(expr.substring(start, i).trim());
        i += sep.length - 1;
        start = i + 1;
      }
    }
    if (start == 0) return [expr.trim()];
    parts.add(expr.substring(start).trim());
    return parts;
  }

  bool _matchesFilterSingle(dynamic item, String expr) {
    var e = expr.trim();
    if (e.isEmpty) return false;
    // 前置取反：`!(@.a==1)` / `!@.done`。
    if (e.startsWith('!')) {
      e = e.substring(1).trim();
      if (e.startsWith('(') && e.endsWith(')')) {
        e = e.substring(1, e.length - 1).trim();
      }
      return !_matchesFilterSingle(item, e);
    }
    // 操作符识别（先双字符后单字符，避免 >= 被 > 截胡）。
    const ops = ['==', '!=', '>=', '<=', '>', '<'];
    for (final op in ops) {
      final idx = e.indexOf(op);
      if (idx <= 0) continue;
      final leftPath = e.substring(0, idx).trim();
      final rightRaw = e.substring(idx + op.length).trim();
      final left = _resolveInner(item, leftPath);
      return _compare(left, op, rightRaw);
    }
    // 无操作符：路径存在且非空即真（`[?(@.cover)]`）。
    final v = _resolveInner(item, e);
    return v != null && '$v'.isNotEmpty;
  }

  /// 过滤路径求值：`@.a.b` / `@['a']` / `@.length` → 以 item 为根导航。
  dynamic _resolveInner(dynamic item, String path) {
    var p = path.trim();
    if (p.startsWith('@')) p = p.substring(1);
    if (p.isEmpty) return item;
    return _navigate(item, _tokenize(p));
  }

  static bool _compare(dynamic left, String op, String rightRaw) {
    final right = _parseLiteral(rightRaw);
    final ln = num.tryParse('$left');
    final rn = num.tryParse('$right');
    if (ln != null && rn != null) {
      return switch (op) {
        '==' => ln == rn,
        '!=' => ln != rn,
        '>' => ln > rn,
        '<' => ln < rn,
        '>=' => ln >= rn,
        '<=' => ln <= rn,
        _ => false,
      };
    }
    final ls = '$left';
    final rs = right == null ? '' : '$right';
    return switch (op) {
      '==' => ls == rs,
      '!=' => ls != rs,
      '>' => ls.compareTo(rs) > 0,
      '<' => ls.compareTo(rs) < 0,
      '>=' => ls.compareTo(rs) >= 0,
      '<=' => ls.compareTo(rs) <= 0,
      _ => false,
    };
  }

  /// 字面量解析：引号字符串 / 数字 / true / false / null。
  static dynamic _parseLiteral(String raw) {
    final t = raw.trim();
    if ((t.startsWith("'") && t.endsWith("'") && t.length >= 2) ||
        (t.startsWith('"') && t.endsWith('"') && t.length >= 2)) {
      return t.substring(1, t.length - 1);
    }
    if (t == 'true') return true;
    if (t == 'false') return false;
    if (t == 'null') return null;
    return num.tryParse(t) ?? t;
  }

  /// 内建函数：length/size（长度）、min/max/sum/avg（数值聚合）。
  static void _applyFunction(dynamic node, String name, List<dynamic> out) {
    if (node is List) {
      switch (name) {
        case 'length':
        case 'size':
          out.add(node.length);
        case 'min':
        case 'max':
        case 'sum':
        case 'avg':
          final nums = node
              .map((e) => num.tryParse('$e'))
              .whereType<num>()
              .toList();
          if (nums.isEmpty) return;
          switch (name) {
            case 'min':
              out.add(nums.reduce((a, b) => a < b ? a : b));
            case 'max':
              out.add(nums.reduce((a, b) => a > b ? a : b));
            case 'sum':
              out.add(nums.fold<num>(0, (a, b) => a + b));
            case 'avg':
              out.add(nums.fold<num>(0, (a, b) => a + b) / nums.length);
          }
      }
    } else if (node is Map) {
      if (name == 'length' || name == 'size') out.add(node.length);
    } else if (node is String) {
      if (name == 'length') out.add(node.length);
    }
  }

  /// 深度扫描：收集自身与全部后代节点（`$..field` 语义：任意层级的 field）。
  static void _collectAll(dynamic node, List<dynamic> out) {
    out.add(node);
    if (node is Map) {
      for (final v in node.values) {
        _collectAll(v, out);
      }
    } else if (node is List) {
      for (final v in node) {
        _collectAll(v, out);
      }
    }
  }
}

enum _JsonTokenType { key, arrayIndex, wildcard, deepScan, slice, filter, function }

/// jayway 风格内建函数名（`$.a.length()` 等）。
const _jsonPathFunctions = {'length', 'size', 'min', 'max', 'sum', 'avg'};

class _JsonPathToken {
  final _JsonTokenType type;
  final String name;

  const _JsonPathToken(this.type, this.name);
}
