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

    test('占有量词忠实翻译（断言形态，不新增捕获组）', () {
      expect(RegexCompat.translate(r'[0-9]++').pattern, r'[0-9]+(?![0-9])');
      expect(RegexCompat.translate(r'a*+').pattern, r'a*(?!a)');
      // 捕获组保留原号，断言副本剥捕获。
      expect(RegexCompat.translate(r'(a)?+').pattern, r'(?:(a)|(?!(?:a)))');
      expect(RegexCompat.translate(r'\d*+').pattern, r'\d*(?!\d)');
      expect(RegexCompat.translate(r'a{2,}+').pattern, r'a{2}(?:a)*(?!a)');
      expect(RegexCompat.translate(r'a{2}+').pattern, 'a{2}');
      // 有上界的占有量词无法忠实表达：原样保留（编译期报错走兜底）。
      expect(RegexCompat.translate(r'a{2,5}+').pattern, r'a{2,5}+');
    });

    test('原子组忠实翻译', () {
      // `(?>U*)` ≡ 占有量词。
      expect(RegexCompat.translate(r'(?>a*)').pattern, r'a*(?!a)');
      expect(RegexCompat.translate(r'(?>\d+)b').pattern, r'\d+(?!\d)b');
      expect(RegexCompat.translate(r'(?>a?)b').pattern, r'(?:a|(?!a))b');
      // 内部无量词与分支：等价非捕获组。
      expect(RegexCompat.translate(r'(?>abc)').pattern, '(?:abc)');
      expect(RegexCompat.translate(r'(?>a(b)c)').pattern, '(?:a(b)c)');
      // 顶层分支 / 组后跟量化符：无法忠实表达，原样保留。
      expect(RegexCompat.translate(r'(?>a|b)').pattern, '(?>a|b)');
      expect(RegexCompat.translate(r'(?>a*)+').pattern, '(?>a*)+');
    });

    test('占有语义：不回溯（对拍 Java 行为）', () {
      // Java `a*+a` 在 "aaa" 上失败（占有段不让位）；贪婪降级版会误匹配。
      final possessive =
          RegExp(RegexCompat.translate(r'a*+a').pattern);
      expect(possessive.hasMatch('aaa'), isFalse);
      // 占有与贪婪的可观察差异：`a*+ab` 在 "aaab" 上必须失败——
      // 贪婪 `a*` 会回溯让位后命中（整串），占有不让位。
      expect(RegExp(RegexCompat.translate(r'a*+ab').pattern).hasMatch('aaab'),
          isFalse);
      expect(RegExp(r'a*ab').hasMatch('aaab'), isTrue); // 贪婪对照组
      // 无歧义场景结果与贪婪一致：'b' 前的 a 跑无需让位。
      expect(RegExp(RegexCompat.translate(r'a*+b').pattern).hasMatch('aaab'),
          isTrue);
      // `\d++x`：数字吃满后必须紧跟 x。
      final digits = RegExp(RegexCompat.translate(r'\d++x').pattern);
      expect(digits.hasMatch('123x'), isTrue);
      expect(digits.hasMatch('1234'), isFalse);
      // 捕获组号不变：`((ab)x)*+` 的 $2 仍是 ab（$1 = (ab)x）。
      final m = RegExp(RegexCompat.translate(r'((ab)x)*+y').pattern)
          .firstMatch('abxy');
      expect(m?.group(1), 'abx');
      expect(m?.group(2), 'ab');
      // 原子组 `(?>\d+)x` 对拍。
      final atomic = RegExp(RegexCompat.translate(r'(?>\d+)x').pattern);
      expect(atomic.hasMatch('123x'), isTrue);
      expect(atomic.hasMatch('1234'), isFalse);
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
