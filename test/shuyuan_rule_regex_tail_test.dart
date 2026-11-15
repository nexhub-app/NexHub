/// legado `##match##replace###` 正则替换尾语义回归。
///
/// 两类高频写法此前与 legado 不一致，导致合成封面 URL 整条失效：
/// 1. 四段 `###` = 仅保留「首个匹配子串替换后」的结果（丢弃前后缀）；
/// 2. `@js:代码##match##replace###` 的 `##` 起是替换尾，不能吞进脚本体。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_rule.dart';

AnalyzeRule _rule(String html) => AnalyzeRule()
  ..setContent(html, 'http://www.mayitxt.info/')
  ..setBaseUrl('http://www.mayitxt.info/');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('### 四段形态（replaceFirst）', () {
    const html =
        '<div class="list"><a href="http://www.mayitxt.info/book/83453.html">'
        '斗破苍穹</a></div>';

    test('只保留匹配子串替换结果，丢弃前后缀', () {
      final out = _rule(html).getString(
          r'a.0@href##.+\D((\d+)\d{3})\D##http://img/$2/$1/$1s.jpg###');
      expect(out, 'http://img/83/83453/83453s.jpg');
    });

    test('普通三 ## 形态仍为全串替换（保留前后缀）', () {
      final out = _rule(html).getString(r'a.0@href##book##novel');
      expect(out, 'http://www.mayitxt.info/novel/83453.html');
    });

    test('无匹配时整条为空（legado 行为）', () {
      final out = _rule(html).getString(r'a.0@href##zzz-none##http://img/###');
      expect(out, '');
    });
  });

  group('@js: 与替换尾组合', () {
    const html = '<div class="list"><a href="/book/246813/">书</a></div>';

    test('空脚本 + ## 替换尾：对上一段结果做正则替换', () {
      final out = _rule(html).getString(
          r'a.0@href@js:##\D((\d+)\d{3})\D##http://img/$2/$1/$1s.jpg###');
      expect(out, 'http://img/246/246813/246813s.jpg');
    });

    test('非空脚本 + ## 替换尾：脚本结果再做正则替换', () {
      // `###` 语义仅保留匹配子串的替换结果：'书-ok' 匹配 (ok) → '!'。
      final out = _rule(html)
          .getString(r"a.0@text@js:result+'-ok'##(ok)##!###");
      expect(out, '!');
    });

    test('空脚本无替换尾：透传上一段结果', () {
      final out = _rule(html).getString('a.0@href@js:');
      expect(out, '/book/246813/');
    });
  });
}
