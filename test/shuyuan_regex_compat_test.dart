/// Java→Dart 正则兼容层测试。独立向量套件见 tool/regex_check.dart
/// （`dart tool/regex_check.dart` 无需 Flutter 即可运行）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/regex_compat.dart';

void main() {
  group('Java→Dart 正则兼容', () {
    test('开头内联标志提取为构造参数', () {
      final r = RegexCompat.translate(r'(?i)笔奇部');
      expect(r.pattern, '笔奇部');
      expect(r.caseSensitive, isFalse);
    });

    test(r'\Q..\E 转义为字面量', () {
      expect(RegexCompat.translate(r'\Qa+b(c)\E').pattern, r'a\+b\(c\)');
    });

    test('占有量词降级为贪婪量词', () {
      expect(RegexCompat.translate(r'[0-9]++').pattern, '[0-9]+');
      expect(RegexCompat.translate(r'a*+').pattern, 'a*');
      expect(RegexCompat.translate(r'(a)?+').pattern, '(a)?');
    });

    test(r'\p{In…} 块名映射为码点区间', () {
      expect(
          RegexCompat.translate(r'[\p{InCJKUnifiedIdeographs}]').pattern,
          r'[\u4e00-\u9fff]');
    });

    test('翻译后可编译并匹配', () {
      final r = RegexCompat.translate(r'(?i)笔奇部');
      expect(
        RegExp(r.pattern, caseSensitive: r.caseSensitive)
            .hasMatch('笔奇部ABC'),
        isTrue,
      );
    });

    test('中途标志 / 反向引用保持原样（求值期报错走既有 catch）', () {
      expect(RegexCompat.translate('abc(?i)def').pattern, 'abc(?i)def');
      expect(RegexCompat.translate(r'(a)\1').pattern, r'(a)\1');
      expect(RegexCompat.translate(r'\p{Unknown}').pattern, r'\p{Unknown}');
    });
  });
}
