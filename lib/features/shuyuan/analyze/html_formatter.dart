/// HTML → 纯文本格式化：对齐 legado `HtmlFormatter.format`（详情/发现/搜索
/// 简介字段使用）。换行类标签转段落后插入全角缩进，其余标签剥离。
library;

class HtmlFormatter {
  HtmlFormatter._();

  static final RegExp _nbsp = RegExp(r'(&nbsp;)+');
  static final RegExp _esp = RegExp(r'(&ensp;|&emsp;)');
  static final RegExp _noPrint =
      RegExp('(&thinsp;|&zwnj;|&zwj;|\u2009|\u200C|\u200D)');
  static final RegExp _wrapHtml =
      RegExp(r'</?(?:div|p|br|hr|h\d|article|dd|dl)[^>]*>');
  static final RegExp _comment = RegExp(r'<!--[^>]*-->');
  static final RegExp _otherHtml = RegExp(r'</?[a-zA-Z]+(?=[ >])[^<>]*>');
  // 对齐 Java `\s`（仅 ASCII 空白）：Dart `\s` 含 U+3000，直接用会多删
  // 全角缩进/全角空格。
  static final RegExp _indent1 =
      RegExp(r'[ \t\n\x0B\f\r]*\n+[ \t\n\x0B\f\r]*');
  static final RegExp _indent2 = RegExp(r'^[\n \t\x0B\f\r]+');
  static final RegExp _last = RegExp(r'[\n \t\x0B\f\r]+$');

  /// legado `HtmlFormatter.format(html)`：段首统一两个全角空格。
  static String format(String? html) {
    if (html == null || html.isEmpty) return '';
    const paragraphIndent = '　　';
    return html
        // Dart 的 HTML 解析器会把实体直接解码成字符（Jsoup innerHtml 则
        // 保留 &nbsp; 实体），两种形态都归一，输出才与 legado 一致。
        .replaceAll('\u00A0', ' ')
        .replaceAll('\u2002', ' ')
        .replaceAll('\u2003', ' ')
        .replaceAll(_nbsp, ' ')
        .replaceAll(_esp, ' ')
        .replaceAll(_noPrint, '')
        .replaceAll(_wrapHtml, '\n')
        .replaceAll(_comment, '')
        .replaceAll(_otherHtml, '')
        .replaceAll(_indent1, '\n$paragraphIndent')
        .replaceAll(_indent2, paragraphIndent)
        .replaceAll(_last, '');
  }

  /// legado `HtmlFormatter.format(html).take(5000)`（简介字段）。
  static String formatIntro(String? html) {
    final text = format(html);
    return text.length > 5000 ? text.substring(0, 5000) : text;
  }
}
