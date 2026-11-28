/// 文本归一化工具：对齐 legado `StringUtils` 中列表/详情共用的小工具。
library;

import 'dart:typed_data';

class StringUtils {
  StringUtils._();

  static final RegExp _numericRegex = RegExp(r'^-?[0-9]+$');

  // legado AppPattern.nameRegex/authorRegex 的 Java `\s` 语义：仅 ASCII 空白
  // （Dart `\s` 额外含 U+3000，直接用会多删全角空格内容）。
  // Java `.` 默认不跨行（行终止符 \n \r \u0085 \u2028 \u2029），
  // 不能用 Dart `[\s\S]*`，否则作者尾巴会吞掉后续行。
  static final RegExp _bookNameRegex = RegExp(
      r'[ \t\n\x0B\f\r]+作[ \t\n\x0B\f\r]*者[^\n\r\u0085\u2028\u2029]*|'
      r'[ \t\n\x0B\f\r]+[^ \t\n\x0B\f\r]+[ \t\n\x0B\f\r]+著');
  static final RegExp _bookAuthorRegex = RegExp(
      r'^[ \t\n\x0B\f\r]*作[ \t\n\x0B\f\r]*者[:： \t\n\x0B\f\r]+|'
      r'[ \t\n\x0B\f\r]+著');

  /// legado `BookHelp.formatBookName`：剥离作者尾巴后按
  /// `trim { it <= ' ' }`（ASCII 空白）修剪，保留全角空格。
  static String formatBookName(String name) {
    if (name.isEmpty) return name;
    return trimAscii(name.replaceAll(_bookNameRegex, ''));
  }

  /// legado `BookHelp.formatBookAuthor`。
  static String formatBookAuthor(String author) {
    if (author.isEmpty) return author;
    return trimAscii(author.replaceAll(_bookAuthorRegex, ''));
  }

  static String trimAscii(String s) {
    var start = 0;
    var end = s.length;
    while (start < end && s.codeUnitAt(start) <= 0x20) {
      start++;
    }
    while (end > start && s.codeUnitAt(end - 1) <= 0x20) {
      end--;
    }
    return s.substring(start, end);
  }

  /// legado `StringUtils.wordCountFormat(String?)`：纯数字时按
  /// `>10000 → DecimalFormat("#.#") + 万字 / 其余 → N字` 归一；非数字原样
  /// 返回。基准用 `words * 1.0f / 10000f.toDouble()`（Float→Double）再交给
  /// `DecimalFormat("#.#")`（最多 1 位小数、去掉末尾 `.0`、**HALF_EVEN**
  /// 舍入），所以这里用 float32 还原精度、按银行家舍入取一位小数——
  /// 旧实现的 `toStringAsFixed(1)` 是 HALF_UP，`12500` 会得到 `1.3万字`
  /// 而基准是 `1.2万字`。
  static String wordCountFormat(String? wc) {
    if (wc == null || wc.isEmpty) return '';
    if (!_numericRegex.hasMatch(wc)) return wc;
    final words = int.tryParse(wc);
    if (words == null) return '';
    if (words <= 0) return '';
    if (words <= 10000) return '$words字';
    final asFloat = Float32List(1)..[0] = words.toDouble();
    return '${_formatOneDecimal(asFloat[0] / 10000.0)}万字';
  }

  /// `DecimalFormat("#.#")` 的一位小数格式（HALF_EVEN，无 trailing zero）。
  ///
  /// 按双精度数的**最短十进制表示**做舍入（Java `DecimalFormat` 也是按
  /// 十进制数字位处理），不能先乘 10 再比较二进制差值——`1.05` 在二进制
  /// 里略大于 1.05，乘法版会错误进位成 `1.1`。
  static String _formatOneDecimal(double v) {
    var s = v.toString();
    if (s.contains('e') || s.contains('E')) s = v.toStringAsFixed(6);
    final dot = s.indexOf('.');
    if (dot < 0) return s;
    final intPart = s.substring(0, dot);
    final frac = s.substring(dot + 1);
    if (frac.isEmpty) return intPart;
    final first = frac.codeUnitAt(0) - 0x30;
    final rest = frac.length > 1 ? frac.substring(1) : '';
    var roundUp = false;
    if (rest.isNotEmpty) {
      final r0 = rest.codeUnitAt(0) - 0x30;
      if (r0 > 5) {
        roundUp = true;
      } else if (r0 == 5) {
        // 恰好半个单位且后面没有非零尾数 → HALF_EVEN（取偶）。
        final hasTail = rest.length > 1 &&
            rest.substring(1).split('').any((c) => c != '0');
        roundUp = hasTail || first.isOdd;
      }
    }
    var digit = first;
    if (roundUp) {
      digit = first + 1;
      if (digit >= 10) return '${int.parse(intPart) + 1}';
    }
    if (digit == 0) return intPart;
    return '$intPart.$digit';
  }
}
