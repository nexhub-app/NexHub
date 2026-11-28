/// Java → Dart 正则兼容层。
///
/// Legado 书源的规则/替换写的是 Java 正则，Dart RegExp 的差异点：
/// - `(?i)` 等内联标志（Dart 只能在构造参数里传，且不支持中途切换）；
/// - `\Q...\E` 字面量段；
/// - 占有量词 `X++ / X*+ / X?+ / X{m,n}+`；
/// - 原子分组 `(?>…)`；
/// - `\p{In…}` / `\p{Is…}` 块名（Dart 完全没有 `\p`）；
/// - 反向引用 `\1`：Dart 不支持，**无法翻译**——保持原样，求值时抛错并由
///   调用方的 catch 走空结果（与旧行为一致，不因翻译引入新错误）。
///
/// 策略：能忠实翻译的翻译（语义与 Java 完全一致），翻不了的保持原样——
/// 由 RegExp 编译期报错、调用方 catch 兜底，**不再静默降级语义**
/// （审计 R23：占有/原子此前降级为贪婪/非捕获，匹配结果会在回溯路径上
/// 偏离 Java）。
///
/// 忠实翻译的构造（全部**不新增捕获组**，`$N`/命名组号不变）：
/// - `X*+` → `(?:X)*(?!X)`：贪心吃完后断言「X 在此不匹配」，使量化段
///   无法回溯让位——回溯到更短轮次时断言必失败（X 在边界处可匹配），
///   整体匹配随之失败，与占有语义一致。
/// - `X++` → `(?:X)+(?!X)`，同上。
/// - `X?+` → `(?:X|(?!X))`：X 可匹配时提交一次且不可让位（回溯到空分支
///   会被 `(?!X)` 拦住——分支一已证明 X 在起点可匹配）；X 不可匹配时取
///   零宽分支，与占有量词的零轮语义一致。
/// - `X{n,}+` → `X{n}(?:X)*(?!X)`（仅当 X 无捕获组；有捕获组时保持原样）。
/// - `(?>U*)` / `(?>U+)` / `(?>U?)` / `(?>U{n,})` → 对应占有形式。
/// - `(?>X)` 且 X 内无任何量词与顶层分支 → `(?:X)`（单一解析路径，原子性
///   不产生可观察差异）。
library;

/// 翻译结果：pattern 已就地改写，标志位转成 RegExp 构造参数。
class RegexCompatResult {
  const RegexCompatResult(
    this.pattern, {
    this.caseSensitive = true,
    this.dotAll = false,
    this.multiLine = false,
  });

  final String pattern;
  final bool caseSensitive;
  final bool dotAll;
  final bool multiLine;
}

class RegexCompat {
  RegexCompat._();

  /// 仅识别**开头**的内联标志组（Java 支持中途切换，Dart 不支持；
  /// 中途出现的 `(?i)` 保持原样，交由求值期报错——与旧行为一致）。
  static final RegExp _leadingFlags = RegExp(r'^\(\?([ismxu]+)\)');

  /// `\Q…\E` 之外需要转义的正则特殊字符。
  static final RegExp _specials = RegExp(r'[\\^$*+?.()|\[\]{}]');

  /// 量化符 `{n}` / `{n,}` / `{n,m}`（贪婪形态）。
  static final RegExp _braceQuantifier = RegExp(r'^\{(\d+)(,(\d*)?)?\}');

  /// 常见 Unicode 块（Java `\p{In…}` / `\p{Is…}` 写法）→ 码点区间。
  static const Map<String, String> _blocks = <String, String>{
    'InCJKUnifiedIdeographs': r'\u4e00-\u9fff',
    'IsCJKUnifiedIdeographs': r'\u4e00-\u9fff',
    'Han': r'\u4e00-\u9fff',
    'InCJKCompatibilityIdeographs': r'\uf900-\ufaff',
    'IsCJKCompatibilityIdeographs': r'\uf900-\ufaff',
    'InHiragana': r'\u3040-\u309f',
    'IsHiragana': r'\u3040-\u309f',
    'InKatakana': r'\u30a0-\u30ff',
    'IsKatakana': r'\u30a0-\u30ff',
    'InHalfwidthandFullwidthForms': r'\uff00-\uffef',
    'InHalfwidthAndFullwidthForms': r'\uff00-\uffef',
    'InCJKSymbolsandPunctuation': r'\u3000-\u303f',
    'InGeneralPunctuation': r'\u2000-\u206f',
  };

  /// 翻译 [source]。永不返回 null、永不抛错；无法忠实翻译的构造原样保留，
  /// 由 RegExp 编译期报错并走调用方兜底。
  static RegexCompatResult translate(String source) {
    var pattern = source;
    var caseSensitive = true;
    var dotAll = false;
    var multiLine = false;

    final fm = _leadingFlags.firstMatch(pattern);
    if (fm != null) {
      final flags = fm.group(1)!;
      if (flags.contains('i')) caseSensitive = false;
      if (flags.contains('s')) dotAll = true;
      if (flags.contains('m')) multiLine = true;
      pattern = pattern.substring(fm.end);
    }

    pattern = _translateQuote(pattern);
    pattern = _translatePossessiveAndAtomic(pattern);
    pattern = pattern.replaceAllMapped(
        RegExp(r'\\p\{(In|Is)?([^}]+)\}', caseSensitive: false), (m) {
      final name = m.group(2)!;
      return _blocks[name] ?? _blocks['In$name'] ?? m.group(0)!;
    });

    return RegexCompatResult(
      pattern,
      caseSensitive: caseSensitive,
      dotAll: dotAll,
      multiLine: multiLine,
    );
  }

  /// `\Q…\E` → 转义后的字面量（`\E` 缺省时直到串尾都是字面量）。
  static String _translateQuote(String p) {
    if (!p.contains(r'\Q')) return p;
    final buf = StringBuffer();
    var i = 0;
    while (true) {
      final start = p.indexOf(r'\Q', i);
      if (start < 0) {
        buf.write(p.substring(i));
        break;
      }
      buf.write(p.substring(i, start));
      final end = p.indexOf(r'\E', start + 2);
      final literal =
          end < 0 ? p.substring(start + 2) : p.substring(start + 2, end);
      buf.write(_escapeSpecial(literal));
      if (end < 0) break;
      i = end + 2;
    }
    return buf.toString();
  }

  static String _escapeSpecial(String s) =>
      s.replaceAllMapped(_specials, (m) => '\\${m.group(0)!}');

  // ---------------------------------------------------------------------------
  // 占有量词与原子组的忠实翻译
  // ---------------------------------------------------------------------------

  /// 单趟扫描：处理 `(?>…)` 原子组与 `*+ / ++ / ?+ / {n,}+` 占有量词。
  ///
  /// 采用「待定单元」机制：最近一个可量化单元（字面字符 / 转义序列 /
  /// 字符类 / 分组）先不写入输出，紧随其后的量化符决定是原样输出（贪婪/
  /// 惰性）、还是重写为占有等价形式。
  static String _translatePossessiveAndAtomic(String p) {
    if (!p.contains('+') && !p.contains('(?>')) return p;
    final out = StringBuffer();
    // 待定单元：[源串起点, 已翻译文本]。null 表示当前无可量化单元。
    var pendingStart = -1;
    var pendingText = '';

    void flush() {
      if (pendingStart >= 0) {
        out.write(pendingText);
        pendingStart = -1;
        pendingText = '';
      }
    }

    var i = 0;
    while (i < p.length) {
      final c = p[i];
      if (c == r'\') {
        flush();
        final end = i + 2 <= p.length ? i + 2 : p.length;
        pendingStart = i;
        pendingText = p.substring(i, end);
        i = end;
        continue;
      }
      if (c == '[') {
        flush();
        final end = _skipCharClass(p, i);
        pendingStart = i;
        pendingText = p.substring(i, end);
        i = end;
        continue;
      }
      if (c == '(') {
        if (p.startsWith('(?>', i)) {
          flush();
          i = _translateAtomicGroup(p, i, out);
          // 原子组输出后无可量化单元（其后若跟量化符，组已按原样保留，
          // 交给编译期报错路径）。
          continue;
        }
        // 普通分组：先递归翻译组内（组内可能含占有量词/嵌套原子组），
        // 整组作为待定单元。
        flush();
        final close = _matchGroupClose(p, i);
        if (close < 0) {
          // 括号不平衡：原样保留剩余内容（编译期报错路径）。
          out.write(p.substring(i));
          return out.toString();
        }
        final inner = p.substring(i + 1, close);
        pendingStart = i;
        pendingText = '(${_translatePossessiveAndAtomic(inner)})';
        i = close + 1;
        continue;
      }
      if (c == '*' || c == '+' || c == '?') {
        final next = i + 1 < p.length ? p[i + 1] : '';
        if (next == '+') {
          // 占有量词。
          if (pendingStart < 0) {
            // 无可量化单元（异常写法）：原样保留，走编译期报错。
            out.write(c);
            out.write('+');
            i += 2;
            continue;
          }
          out.write(_emitPossessive(pendingText, c));
          pendingStart = -1;
          pendingText = '';
          i += 2;
          continue;
        }
        // 贪婪/惰性：单元 + 量化符原样输出。
        flush();
        out.write(c);
        if (next == '?') {
          out.write('?');
          i += 2;
          continue;
        }
        i++;
        continue;
      }
      if (c == '{') {
        final m = _braceQuantifier.firstMatch(p.substring(i));
        if (m == null) {
          // 非量化符的字面 `{`。
          flush();
          pendingStart = i;
          pendingText = c;
          i++;
          continue;
        }
        final qEnd = i + m.end;
        final next = qEnd < p.length ? p[qEnd] : '';
        final isPossessive = next == '+';
        final lowerBound = m.group(1)!;
        // group(3) 为空串表示 `{n,}`（无上界）；非空表示 `{n,m}`。
        final upper = m.group(3);
        final hasUpper = upper != null && upper.isNotEmpty;
        if (isPossessive) {
          if (!hasUpper &&
              pendingStart >= 0 &&
              !_containsCaptures(pendingText)) {
            if (m.group(2) == null) {
              // `{n}+`：精确次数本就无可让位轮次，占有与贪婪等价。
              out.write(pendingText);
              out.write('{$lowerBound}');
            } else {
              // `{n,}+` → `X{n}X*(?!X)`。
              out.write(pendingText);
              out.write('{$lowerBound}');
              out.write('(?:');
              out.write(pendingText);
              out.write(')*(?!');
              out.write(_stripCaptures(pendingText));
              out.write(')');
            }
          } else {
            // `{n,m}+` 或单元含捕获组：无法忠实翻译，原样保留
            //（堆叠量化符走编译期报错，不静默降级）。
            flush();
            out.write(p.substring(i, qEnd + 1));
          }
          pendingStart = -1;
          pendingText = '';
          i = qEnd + 1;
          continue;
        }
        flush();
        out.write(p.substring(i, qEnd));
        i = qEnd;
        continue;
      }
      // 普通字符：一个可量化单元。
      flush();
      pendingStart = i;
      pendingText = c;
      i++;
    }
    flush();
    return out.toString();
  }

  /// 翻译 `(?>…)` 原子组（[p] 的 [start] 指向 `(`），结果写入 [out]，
  /// 返回扫描继续位置（闭合 `)` 之后）。
  static int _translateAtomicGroup(String p, int start, StringBuffer out) {
    final close = _matchGroupClose(p, start);
    if (close < 0) {
      out.write(p.substring(start));
      return p.length;
    }
    final inner = p.substring(start + 3, close);
    final after = close + 1 < p.length ? p[close + 1] : '';
    final followedByQuant =
        (after == '*' || after == '+' || after == '?') ||
            (after == '{' &&
                _braceQuantifier.firstMatch(p.substring(close + 1)) != null);

    if (followedByQuant) {
      // 量化符作用在原子组整体：Java 语义是「每轮迭代内部原子」，
      // Dart 无法等价表达，原样保留（编译期报错）。
      out.write(p.substring(start, close + 1));
      return close + 1;
    }

    // `(?>U*)` / `(?>U+)` / `(?>U?)` / `(?>U{n,})` → 占有形式。
    final quant = _trailingQuantifier(inner);
    if (quant != null) {
      final unit = inner.substring(0, quant.$1);
      out.write(_emitPossessive(unit, quant.$2, brace: quant.$3));
      return close + 1;
    }

    // 内部无任何量词与分支：单一解析路径，原子性与非捕获组等价。
    if (!_containsQuantifierOrAlternation(inner)) {
      out.write('(?:');
      out.write(inner);
      out.write(')');
      return close + 1;
    }

    // 其余（顶层分支、嵌套量词等）：无法忠实翻译，原样保留。
    out.write(p.substring(start, close + 1));
    return close + 1;
  }

  /// 生成占有量词的 Dart 等价文本（[unit] 为待定单元的已翻译文本）。
  ///
  /// [brace] 非 null 表示 `{n,}` 下界形态（此时 [kind] 忽略）。
  static String _emitPossessive(String unit, String kind, {String? brace}) {
    final stripped = _stripCaptures(unit);
    if (brace != null) {
      // `X{n,}+` → `X{n}(?:X)*(?!X)`
      return '$unit$brace(?:$unit)*(?!$stripped)';
    }
    switch (kind) {
      case '*':
        // `X*+` → `X*(?!X)`
        return '$unit*(?!$stripped)';
      case '+':
        // `X++` → `X+(?!X)`
        return '$unit+(?!$stripped)';
      default:
        // `X?+` → `(?:X|(?!X))`
        return '(?:$unit|(?!$stripped))';
    }
  }

  /// 内串末尾是否是「顶层单个量化符」；是则返回
  /// `(量化符前单元长度, 量化符种类, {n,} 文本或 null)`。
  static (int, String, String?)? _trailingQuantifier(String s) {
    if (s.isEmpty) return null;
    final last = s[s.length - 1];
    if (last == '*' || last == '+' || last == '?') {
      // 转义的 `\*` 等：量化符前一位是 `\` 则是字面量。
      if (s.length >= 2 && s[s.length - 2] == r'\') return null;
      // 前一位也是量化符（stacked `a**`、惰性 `a*?`/`a??`）：复杂形态，不翻。
      final prev = s[s.length - 2];
      if (s.length >= 2 &&
          (prev == '*' || prev == '+' || prev == '?')) {
        return null;
      }
      return (s.length - 1, last, null);
    }
    if (last == '}') {
      // 尾部 `{n,}`（禁止 `{n,m}`：有上界的占有量词无法用断言形态表达）。
      var depth = 0;
      for (var j = s.length - 1; j >= 0; j--) {
        final ch = s[j];
        if (ch == '}') {
          depth++;
          continue;
        }
        if (ch == '{') {
          depth--;
          if (depth == 0) {
            final m =
                _braceQuantifier.firstMatch(s.substring(j));
            if (m == null || m.end != s.length - j) return null;
            if (m.group(2) != null) return null; // 有上界
            return (j, '', s.substring(j));
          }
        }
        if (ch == ']') {
          // 扫到字符类闭合，说明 `{` 在类外……这里简单起见放弃。
          return null;
        }
      }
      return null;
    }
    return null;
  }

  /// 是否含有未转义、不在字符类内的量词或分支字符（`* + ? { |`）。
  static bool _containsQuantifierOrAlternation(String s) {
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if (c == r'\') {
        i += 2;
        continue;
      }
      if (c == '[') {
        i = _skipCharClass(s, i);
        continue;
      }
      if (c == '*' || c == '+' || c == '?' || c == '{' || c == '|') {
        return true;
      }
      i++;
    }
    return false;
  }

  /// 是否含有捕获组（普通 `(` 与命名组 `(?<name>`；`(?:`/`(?=`/`(?!` 不算）。
  static bool _containsCaptures(String s) {
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if (c == r'\') {
        i += 2;
        continue;
      }
      if (c == '[') {
        i = _skipCharClass(s, i);
        continue;
      }
      if (c == '(') {
        if (i + 1 < s.length && s[i + 1] == '?') {
          if (i + 3 < s.length &&
              s[i + 2] == '<' &&
              s[i + 3] != '=' &&
              s[i + 3] != '!') {
            return true; // 命名捕获
          }
          i += 2;
          continue;
        }
        return true; // 普通捕获组
      }
      i++;
    }
    return false;
  }

  /// 捕获组 → 非捕获（用于断言副本：断言内的分组永不参与捕获，剥离后
  /// 组号不漂移）。命名捕获同样剥为 `(?:`。
  static String _stripCaptures(String s) {
    if (!s.contains('(')) return s;
    final out = StringBuffer();
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if (c == r'\') {
        final end = i + 2 <= s.length ? i + 2 : s.length;
        out.write(s.substring(i, end));
        i = end;
        continue;
      }
      if (c == '[') {
        final end = _skipCharClass(s, i);
        out.write(s.substring(i, end));
        i = end;
        continue;
      }
      if (c == '(') {
        if (i + 1 < s.length && s[i + 1] == '?') {
          if (i + 3 < s.length &&
              s[i + 2] == '<' &&
              s[i + 3] != '=' &&
              s[i + 3] != '!') {
            final gt = s.indexOf('>', i + 3);
            if (gt > 0) {
              out.write('(?:');
              i = gt + 1;
              continue;
            }
          }
          out.write(s.substring(i, i + 2));
          i += 2;
          continue;
        }
        out.write('(?:');
        i++;
        continue;
      }
      out.write(c);
      i++;
    }
    return out.toString();
  }

  /// 跳过字符类：[start] 指向 `[`，返回 `]` 之后的位置（未闭合则串尾）。
  static int _skipCharClass(String p, int start) {
    var i = start + 1;
    if (i < p.length && p[i] == '^') i++;
    if (i < p.length && p[i] == ']') i++; // 首个 `]` 是字面量成员
    while (i < p.length) {
      if (p[i] == r'\') {
        i += 2;
        continue;
      }
      if (p[i] == ']') return i + 1;
      i++;
    }
    return p.length;
  }

  /// 找与 [start]（指向 `(`）配对的 `)`，返回其位置；未闭合返回 -1。
  static int _matchGroupClose(String p, int start) {
    var depth = 0;
    var i = start;
    while (i < p.length) {
      final c = p[i];
      if (c == r'\') {
        i += 2;
        continue;
      }
      if (c == '[') {
        i = _skipCharClass(p, i);
        continue;
      }
      if (c == '(') {
        depth++;
        i++;
        continue;
      }
      if (c == ')') {
        depth--;
        if (depth == 0) return i;
        i++;
        continue;
      }
      i++;
    }
    return -1;
  }
}
