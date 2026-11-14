/// Java → Dart 正则兼容层。
///
/// Legado 书源的规则/替换写的是 Java 正则，Dart RegExp 的差异点：
/// - `(?i)` 等内联标志（Dart 只能在构造参数里传，且不支持中途切换）；
/// - `\Q...\E` 字面量段；
/// - 占有量词 `X++ / X*+ / X?+ / X{m,n}++`；
/// - 原子分组 `(?>…)`；
/// - `\p{In…}` / `\p{Is…}` 块名（Dart 完全没有 `\p`）；
/// - 反向引用 `\1`：Dart 不支持，**无法翻译**——保持原样，求值时抛错并由
///   调用方的 catch 走空结果（与旧行为一致，不因翻译引入新错误）。
///
/// 策略：能翻的翻，翻不了的保持原样。只做「增量修复」：现在能跑的模式
/// 翻译后语义不变。
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

  /// 翻译 [source]。永不返回 null、永不抛错。
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
    // 占有量词降级为贪婪量词：语义上少了「不回溯」，绝大多数替换场景等价。
    pattern = pattern
        .replaceAll(']++', ']+')
        .replaceAll('}++', '}+')
        .replaceAll('*+', '*')
        .replaceAll('?+', '?')
        .replaceAll('++', '+');
    pattern = pattern.replaceAll('(?>', '(?:');
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
}
