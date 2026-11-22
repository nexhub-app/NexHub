import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_rule.dart';

void main() {
  group('unescapeHtml 命名实体（HTML4 表）', () {
    test('HTML4 命名实体还原', () {
      expect(AnalyzeRule.unescapeHtml('&amp;&lt;&gt;&quot;'), '&<>"');
      expect(AnalyzeRule.unescapeHtml('&copy;'), '©');
      expect(AnalyzeRule.unescapeHtml('&nbsp;'), '\u00A0');
      expect(AnalyzeRule.unescapeHtml('&hellip;'), '…');
      expect(AnalyzeRule.unescapeHtml('&not;it;'), '¬it;');
      expect(AnalyzeRule.unescapeHtml('&AElig;'), 'Æ');
    });

    test('HTML4 取值与 HTML5 不同的实体按 HTML4 码点还原', () {
      expect(AnalyzeRule.unescapeHtml('&lang;'), '\u2329');
      expect(AnalyzeRule.unescapeHtml('&rang;'), '\u232A');
    });

    test('HTML5 专有实体 / 大小写变体 / apos 原样保留', () {
      expect(AnalyzeRule.unescapeHtml('&apos;'), '&apos;');
      expect(AnalyzeRule.unescapeHtml('&COPY;'), '&COPY;');
      expect(AnalyzeRule.unescapeHtml('&Copy;'), '&Copy;');
      expect(AnalyzeRule.unescapeHtml('&NewLine;'), '&NewLine;');
      expect(AnalyzeRule.unescapeHtml('&notit;'), '&notit;');
      expect(AnalyzeRule.unescapeHtml('&amp;notit;'), '&notit;');
      expect(AnalyzeRule.unescapeHtml('&amp;apos;'), '&apos;');
    });

    test('缺分号 / 未知实体原样保留', () {
      expect(AnalyzeRule.unescapeHtml('&amp'), '&amp');
      expect(AnalyzeRule.unescapeHtml('&unknown;'), '&unknown;');
      expect(AnalyzeRule.unescapeHtml('&not'), '&not');
    });
  });

  group('unescapeHtml 数字实体（Apache 语义）', () {
    test('十进制 / 十六进制（含前导零、大写 X）', () {
      expect(AnalyzeRule.unescapeHtml('&#65;'), 'A');
      expect(AnalyzeRule.unescapeHtml('&#00065;'), 'A');
      expect(AnalyzeRule.unescapeHtml('&#x41;'), 'A');
      expect(AnalyzeRule.unescapeHtml('&#X41;'), 'A');
      expect(AnalyzeRule.unescapeHtml('&#x000041;'), 'A');
    });

    test('不映射 CP1252：0x80-0x9F 按原码点还原', () {
      expect(AnalyzeRule.unescapeHtml('&#128;'), '\u0080');
      expect(AnalyzeRule.unescapeHtml('&#150;'), '\u0096');
    });

    test('允许 0 与代理区码点', () {
      expect(AnalyzeRule.unescapeHtml('&#0;'), '\u0000');
      expect(AnalyzeRule.unescapeHtml('&#xd800;'), '\ud800');
      expect(AnalyzeRule.unescapeHtml('&#55296;'), '\ud800');
    });

    test('0x10FFFF 为合法上界', () {
      expect(AnalyzeRule.unescapeHtml('&#x10FFFF;'), '\u{10FFFF}');
      expect(AnalyzeRule.unescapeHtml('&#1114111;'), '\u{10FFFF}');
    });

    test('超过 0x10FFFF 抛 ArgumentError（对齐 IllegalArgumentException）', () {
      expect(() => AnalyzeRule.unescapeHtml('&#x110000;'),
          throwsA(isA<ArgumentError>()));
      expect(() => AnalyzeRule.unescapeHtml('&#x7FFFFFFF;'),
          throwsA(isA<ArgumentError>()));
    });

    test('超出 int32 / int64 的溢出值原样保留（对齐 NumberFormatException）', () {
      expect(AnalyzeRule.unescapeHtml('&#x80000000;'), '&#x80000000;');
      expect(AnalyzeRule.unescapeHtml('&#2147483648;'), '&#2147483648;');
      expect(AnalyzeRule.unescapeHtml('&#9223372036854775808;'),
          '&#9223372036854775808;');
    });

    test('缺分号 / 非数字原样保留', () {
      expect(AnalyzeRule.unescapeHtml('&#65'), '&#65');
      expect(AnalyzeRule.unescapeHtml('&#x41'), '&#x41');
    });

    test('混合文本只替换实体片段', () {
      expect(AnalyzeRule.unescapeHtml('A &amp; B&#33; &apos; C'),
          'A & B! &apos; C');
    });
  });

  group('规则求值链路实体还原', () {
    test('双重转义的 HTML5 专有实体不再二次还原', () {
      final ar = AnalyzeRule()
        ..setContent('<div><p class="x">&amp;COPY; &amp;apos; '
            '&amp;notit;</p></div>');
      expect(ar.getString('.x@text'), '&COPY; &apos; &notit;');
    });

    test('双重转义的 HTML4 实体仍还原一次', () {
      final ar = AnalyzeRule()
        ..setContent('<div><p class="x">&amp;copy; &amp;not;it;</p></div>');
      expect(ar.getString('.x@text'), '© ¬it;');
    });
  });
}
