/// 文本归一化工具：对齐 legado `StringUtils` 中列表/详情共用的小工具。
library;

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
  /// `>10000 → N.N万字 / 其余 → N字` 归一；非数字原样返回。
  static String wordCountFormat(String? wc) {
    if (wc == null || wc.isEmpty) return '';
    if (!_numericRegex.hasMatch(wc)) return wc;
    final words = int.tryParse(wc) ?? 0;
    if (words <= 0) return '';
    if (words > 10000) {
      var v = (words / 10000).toStringAsFixed(1);
      if (v.endsWith('.0')) v = v.substring(0, v.length - 2);
      return '$v万字';
    }
    return '$words字';
  }
}
