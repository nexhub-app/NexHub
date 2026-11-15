/// 正则规则解析器：从内容中按正则提取字符串/分组数组。
///
/// 规则写的是 Java 正则（legado allInOne 语法），经 [RegexCompat.translate]
/// 转成 Dart RegExp：内联标志 / \Q..\E / 占有量词 / \p{In…} 就地翻译；
/// 默认**不开** dotAll（与 legado 一致，需要跨行用 `(?s)`）。
///
/// 语义对齐 legado AnalyzeByRegex：
/// - 多段规则以 `&&` 分隔；非末段先把全部命中拼回文本再交给下一段；
/// - 末段 `getElement` 返回首个命中的「整串+全部分组」数组，
///   `getElements` 返回每个命中的分组数组（含空分组）。
library;

import 'regex_compat.dart';

class AnalyzeByRegex {
  static RegExp _compile(String rule) {
    final compat = RegexCompat.translate(rule);
    return RegExp(
      compat.pattern,
      caseSensitive: compat.caseSensitive,
      dotAll: compat.dotAll,
      multiLine: compat.multiLine,
    );
  }

  static List<String> _splitRules(String rule) =>
      rule.split('&&').map((r) => r.trim()).where((r) => r.isNotEmpty).toList();

  static String getString(String content, String rule) {
    if (rule.isEmpty || content.isEmpty) return '';
    try {
      final match = _compile(rule).firstMatch(content);
      if (match != null) {
        if (match.groupCount > 0) {
          return match.group(1) ?? match.group(0) ?? '';
        }
        return match.group(0) ?? '';
      }
    } catch (_) {}
    return '';
  }

  static List<String> getStringList(String content, String rule) {
    if (rule.isEmpty || content.isEmpty) return [];
    final results = <String>[];
    try {
      for (final match in _compile(rule).allMatches(content)) {
        final group =
            match.groupCount > 0 ? match.group(1) : match.group(0);
        if (group != null && group.isNotEmpty) {
          results.add(group);
        }
      }
    } catch (_) {}
    return results;
  }

  /// 首个命中的分组数组（`[0]`=整串，`[N]`=第 N 组，未参与匹配为空串）。
  static List<String>? getElement(String content, String rule) {
    final rules = _splitRules(rule);
    if (rules.isEmpty) return null;
    return _getElement(content, rules, 0);
  }

  static List<String>? _getElement(String res, List<String> rules, int index) {
    RegExp regex;
    Match? first;
    try {
      regex = _compile(rules[index]);
      first = regex.firstMatch(res);
    } catch (_) {
      return null;
    }
    if (first == null) return null;
    if (index + 1 == rules.length) {
      return [
        for (var i = 0; i <= first.groupCount; i++) first.group(i) ?? '',
      ];
    }
    final buf = StringBuffer();
    for (final m in regex.allMatches(res)) {
      buf.write(m.group(0) ?? '');
    }
    return _getElement(buf.toString(), rules, index + 1);
  }

  /// 每次命中的分组数组列表（空命中返回空列表）。
  static List<List<String>> getElements(String content, String rule) {
    final rules = _splitRules(rule);
    if (rules.isEmpty) return [];
    return _getElements(content, rules, 0);
  }

  static List<List<String>> _getElements(
      String res, List<String> rules, int index) {
    RegExp regex;
    Match? first;
    try {
      regex = _compile(rules[index]);
      first = regex.firstMatch(res);
    } catch (_) {
      return [];
    }
    if (first == null) return [];
    if (index + 1 == rules.length) {
      final books = <List<String>>[];
      for (final m in regex.allMatches(res)) {
        books.add([
          for (var i = 0; i <= m.groupCount; i++) m.group(i) ?? '',
        ]);
      }
      return books;
    }
    final buf = StringBuffer();
    for (final m in regex.allMatches(res)) {
      buf.write(m.group(0) ?? '');
    }
    return _getElements(buf.toString(), rules, index + 1);
  }
}
