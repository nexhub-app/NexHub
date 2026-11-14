/// 正则规则解析器：从内容中按正则提取字符串/元素列表。
///
/// 规则写的是 Java 正则（legado allInOne 语法），经 [RegexCompat.translate]
/// 转成 Dart RegExp：内联标志 / \Q..\E / 占有量词 / \p{In…} 就地翻译；
/// 默认**不开** dotAll（与 legado 一致，需要跨行用 `(?s)`）。
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

  static String getString(String content, String rule) {
    if (rule.isEmpty || content.isEmpty) return '';
    try {
      final regex = _compile(rule);
      final match = regex.firstMatch(content);
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
      final regex = _compile(rule);
      for (final match in regex.allMatches(content)) {
        if (match.groupCount > 0) {
          final group = match.group(1);
          if (group != null && group.isNotEmpty) {
            results.add(group);
          }
        } else {
          final group = match.group(0);
          if (group != null && group.isNotEmpty) {
            results.add(group);
          }
        }
      }
    } catch (_) {}
    return results;
  }

  static String? getElement(String content, String rule) {
    final rules = rule.split('&&').where((r) => r.trim().isNotEmpty).toList();
    final sList = _getElementsByRules(content, rules);
    return sList.isEmpty ? null : sList.first;
  }

  static List<String> getElements(String content, String rule) {
    final rules = rule.split('&&').where((r) => r.trim().isNotEmpty).toList();
    return _getElementsByRules(content, rules);
  }

  static List<String> _getElementsByRules(String content, List<String> rules) {
    final resultList = <String>[];
    for (final r in rules) {
      try {
        final regex = _compile(r);
        for (final match in regex.allMatches(content)) {
          for (int i = 0; i <= match.groupCount; i++) {
            final group = match.group(i);
            if (group != null) {
              resultList.add(group);
            }
          }
        }
      } catch (_) {}
    }
    return resultList;
  }
}
