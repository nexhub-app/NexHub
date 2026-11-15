/// XPath 规则引擎回归：谓词、位置、属性、text()、并集、顶层函数、
/// `&&`/`||`/`%%` 复合规则、表格片段补壳。对齐 legado AnalyzeByXPath 语义。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_xpath.dart';

const _html = '''
<html><body>
<div id="list" class="box"><ul>
<li class="item"><a href="/a1">标题一</a></li>
<li class="item"><a href="/a2">标题二</a></li>
<li class="item x"><a href="/a3">标题三</a></li>
</ul></div>
<p class="intro">  简介
<i>斜体</i>  尾部 </p>
</body></html>''';

void main() {
  test('属性 / text() / 元素文本', () {
    final a = AnalyzeByXPath(_html);
    expect(a.getStringList('//div[@id="list"]//li/a/@href'),
        ['/a1', '/a2', '/a3']);
    expect(a.getString('//li[2]/a/text()'), '标题二');
    expect(a.getString('//li[1]/a'), '标题一');
    expect(a.getStringList('//p[@class="intro"]/text()'), ['简介 斜体 尾部']);
  });

  test('谓词：contains / starts-with / position / last', () {
    final a = AnalyzeByXPath(_html);
    expect(a.getStringList('//li[contains(@class,"x")]/a/@href'), ['/a3']);
    expect(a.getStringList('//li[starts-with(@class,"item")]/a/@href'),
        ['/a1', '/a2', '/a3']);
    expect(a.getString('//li[position()=2]/a/text()'), '标题二');
    expect(a.getStringList('//li[last()]/a/@href'), ['/a3']);
  });

  test('并集 | 与顶层 normalize-space/string', () {
    final a = AnalyzeByXPath(_html);
    expect(
        a.getStringList('//li[1]/a/@href | //p/text()'), ['/a1', '简介 斜体 尾部']);
    expect(a.getString('normalize-space(//p/text())'), '简介 斜体 尾部');
    expect(a.getString('string(//li[3]/a/text())'), '标题三');
  });

  test('绝对路径与属性缺失不误取文本', () {
    final a = AnalyzeByXPath(_html);
    expect(a.getString('//div[@id="list"]/ul/li[1]/a'), '标题一');
    final frag = AnalyzeByXPath(
        '<li><a href="/only">A</a><a>无链接</a></li>');
    expect(frag.getStringList('//li//a/@href'), ['/only']);
  });

  test('表格片段补壳（td/tr）', () {
    final td = AnalyzeByXPath(
        '<td><a href="/c1">章节一</a></td><td><a href="/c2">章节二</a></td>');
    expect(td.getStringList('//td/a/@href'), ['/c1', '/c2']);

    final tr = AnalyzeByXPath(
        '<tr><td><a href="/r1">R1</a></td></tr><tr><td><a href="/r2">R2</a></td></tr>');
    expect(tr.getStringList('//tr[2]//a/@href'), ['/r2']);
  });

  test('复合规则：&& 拼接、|| 短路、%% 交错', () {
    final a = AnalyzeByXPath(_html);
    expect(a.getStringList('//li[1]/a/@href && //li[2]/a/@href'),
        ['/a1', '/a2']);
    expect(a.getStringList('//li[@class="none"]/a/@href || //li[3]/a/@href'),
        ['/a3']);
    expect(a.getStringList('//li[1]/a/@href && //li[2]/a/@href %% '
        '//li[3]/a/@href'), ['/a1', '/a2', '/a3']);
    expect(a.getString('//li[1]/a/text() && //li[2]/a/text()'), '标题一\n标题二');
  });

  test('元素列表输入（链式规则）', () {
    final a = AnalyzeByXPath(_html);
    final nodes = a.getElements('//li');
    expect(nodes.length, 3);
    final chained = AnalyzeByXPath(nodes);
    expect(chained.getStringList('//a/@href'), ['/a1', '/a2', '/a3']);
  });
}
