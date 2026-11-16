/// 文本归一化工具：对齐 legado `StringUtils` 中列表/详情共用的小工具。
library;

class StringUtils {
  StringUtils._();

  static final RegExp _numericRegex = RegExp(r'^-?[0-9]+$');

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
