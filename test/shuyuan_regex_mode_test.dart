/// 正则模式（AllInOne `:` 列表规则）与 `$N` 分组引用回归测试。
///
/// 对照 legado AnalyzeByRegex / AnalyzeRule.SourceRule：
/// - 列表规则 `:正则` 的每次命中产出「整串+全部分组」数组；
/// - 字段规则 `$2` / `$3$5` / `$1<js>...</js>` 从分组数组取值并拼接；
/// - 实例内 `:` 列表规则后，后续规则沿用正则模式（legado isRegex）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_jsoup.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_regex.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_rule.dart';
import 'package:nexhub/features/shuyuan/analyze/source_rule.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnalyzeByRegex 分组语义', () {
    test('getElements 每次命中返回整串+全部分组（含空分组）', () {
      final res = AnalyzeByRegex.getElements(
          'A1,B2', r'([A-Z])(\d)?');
      expect(res.length, 2);
      expect(res[0], ['A1', 'A', '1']);
      expect(res[1], ['B2', 'B', '2']);
    });

    test('getElements 空分组保留为空串', () {
      final res = AnalyzeByRegex.getElements('A,B2', r'([A-Z])(\d)?');
      expect(res[0], ['A', 'A', '']);
      expect(res[1], ['B2', 'B', '2']);
    });

    test('非末段规则先拼接全部命中，再交给下一段', () {
      final res = AnalyzeByRegex.getElements(
          'x<a>1</a>y<a>2</a>', r'<a>[\s\S]*?</a>&&<a>(\d)</a>');
      expect(res.length, 2);
      expect(res[0][1], '1');
      expect(res[1][1], '2');
    });

    test('getElement 返回首个命中的分组数组', () {
      final res = AnalyzeByRegex.getElement('id=42;id=43', r'id=(\d+)');
      expect(res, ['id=42', '42']);
    });

    test('无命中返回空', () {
      expect(AnalyzeByRegex.getElements('abc', r'\d+'), isEmpty);
      expect(AnalyzeByRegex.getElement('abc', r'\d+'), isNull);
    });
  });

  group(r'$N 分组引用', () {
    const html = '<ul>'
        '<li><a href="/c/1.html">第1章 起</a><i>vip</i></li>'
        '<li><a href="/c/2.html">第2章 承</a></li>'
        '</ul>';

    test(r'列表规则命中项 + $N 字段规则（legado 目录解析流程）', () {
      final ar = AnalyzeRule()..setContent(html);
      final items = ar.getElements(
          r':<li><a href="([^"]+)">([^<]+)</a>(?:<i>([^<]*)</i>)?</li>');
      expect(items.length, 2);
      expect(items[0], isA<List>());

      final nameRule = ar.splitSourceRule(r'$2');
      final urlRule = ar.splitSourceRule(r'$1');
      final vipRule = ar.splitSourceRule(r'$3');

      ar.setContent(items[0]);
      expect(ar.getStringFromRules(nameRule), '第1章 起');
      expect(ar.getStringFromRules(urlRule), '/c/1.html');
      expect(ar.getStringFromRules(vipRule), 'vip');

      ar.setContent(items[1]);
      expect(ar.getStringFromRules(nameRule), '第2章 承');
      expect(ar.getStringFromRules(urlRule), '/c/2.html');
      expect(ar.getStringFromRules(vipRule), '');
    });

    test(r'多分组拼接 $1$3$5$6', () {
      final ar = AnalyzeRule()..setContent('a-b-c-d-e');
      final items = ar.getElements(r':(a)-(b)-(c)-(d)-(e)');
      ar.setContent(items.first);
      expect(ar.getStringFromRules(ar.splitSourceRule(r'$1$3$5$6$7')),
          'ace');
    });

    test(r'$1<js> 后缀：分组值作为 result 传给 JS 段', () {
      final ar = AnalyzeRule()..setContent('u');
      final items = ar.getElements(r':(u)');
      ar.setContent(items.first);
      final rules = ar.splitSourceRule(r"$1<js>result + '-x'</js>");
      expect(ar.getStringFromRules(rules), 'u-x');
    });

    test(r'$0 不是分组引用，保持字面量', () {
      final ar = AnalyzeRule()..setContent('abc');
      final items = ar.getElements(r':(a)');
      ar.setContent(items.first);
      expect(ar.getStringFromRules(ar.splitSourceRule(r'$0')), r'$0');
    });

    test(r'非列表内容时 $N 保留字面量（legado makeUpRule 行为）', () {
      final ar = AnalyzeRule()..setContent('http://x.com/a');
      expect(ar.getString(r'$1'), r'$1');
    });

    test(r'替换尾中的 $N 交给 ## 正则替换（不做分组拼接）', () {
      final ar = AnalyzeRule()..setContent('u');
      final items = ar.getElements(r':(u)');
      ar.setContent(items.first);
      final rules = ar.splitSourceRule(r'$1##(u)##X$1');
      expect(ar.getStringFromRules(rules), 'Xu');
    });

    test('列表规则以 : 开头才进入正则模式，且实例内后续规则沿用', () {
      final ar = AnalyzeRule()..setContent('abc');
      final items = ar.getElements(r':(\w+)');
      expect(items.first, ['abc', 'abc']);
      // isRegex 沿用：无选择器语义的规则按字面量返回。
      expect(ar.getString('plain'), 'plain');
    });

    test('普通规则以 : 开头（非 allInOne）不触发正则模式', () {
      final ar = AnalyzeRule()..setContent('<div class="a">x</div>');
      final rules = ar.splitSourceRule(':x');
      expect(rules.first.mode, Mode.defaultMode);
    });
  });

  group('JSoup 取值方法对齐', () {
    test('textNodes 按元素换行合并', () {
      const html = '<div id="a">第一行<b>粗</b>第二行</div>'
          '<div id="b">甲<br>乙</div>';
      final analyzer = AnalyzeByJsoup(html);
      final values = analyzer.getStringList('#a@textNodes');
      expect(values, ['第一行\n第二行']);
      final b = analyzer.getStringList('#b@textNodes');
      expect(b, ['甲\n乙']);
    });

    test('html 取 outerHtml（移除 script/style，整体一条）', () {
      const html = '<div id="a"><p>x</p><script>1</script></div>'
          '<div id="b"><style>y</style></div>';
      final analyzer = AnalyzeByJsoup(html);
      final values = analyzer.getStringList('div@html');
      expect(values.length, 1);
      expect(values.first.contains('<div id="a">'), true);
      expect(values.first.contains('<script>'), false);
      expect(values.first.contains('<style>'), false);
      expect(values.first.contains('<p>x</p>'), true);
    });

    test('all 取全部命中元素 outerHtml 拼接', () {
      const html = '<p>a</p><p>b</p>';
      final analyzer = AnalyzeByJsoup(html);
      final values = analyzer.getStringList('p@all');
      expect(values, ['<p>a</p><p>b</p>']);
    });
  });
}
