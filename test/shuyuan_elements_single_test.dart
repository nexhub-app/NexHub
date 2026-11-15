/// legado `AnalyzeByJSoup.ElementsSingle` 索引/前缀语义回归：
/// `.N` 后缀、`:` 多索引、`!` 排除、`[start:end:step]` 区间、`[-1:0]` 反向、
/// `children/class/tag/id/text` 前缀。对应社区源最高频的规则写法。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_jsoup.dart';

String _html() {
  final buf = StringBuffer('<html><body><div id="list" class="box">');
  for (var i = 0; i < 10; i++) {
    final id = i == 0 ? ' id="special"' : '';
    buf.write('<li$id class="item c$i">item$i<span>sub$i</span></li>');
  }
  buf.write('<p class="note">作者：张三</p>');
  buf.write('</div></body></html>');
  return buf.toString();
}

AnalyzeByJsoup _analyzer() => AnalyzeByJsoup(_html());

void main() {
  test('旧式单索引 a.0 / a.-1 / a.0:2', () {
    final a = _analyzer();
    expect(a.getStringList('li.0@text'), ['item0sub0']);
    expect(a.getStringList('li.-1@text'), ['item9sub9']);
    expect(a.getStringList('li.0:2@text'), ['item0sub0', 'item2sub2']);
  });

  test('旧式排除 a!0', () {
    final a = _analyzer();
    final list = a.getStringList('li!0@text');
    expect(list.length, 9);
    expect(list.first, 'item1sub1');
  });

  test('括号索引 [8:] / [!0] / [-1, 2]', () {
    final a = _analyzer();
    expect(a.getStringList('li[8:]@text'), ['item8sub8', 'item9sub9']);
    expect(a.getStringList('li[!0]@text').length, 9);
    expect(a.getStringList('li[-1, 2]@text'), ['item9sub9', 'item2sub2']);
  });

  test('区间步长 [0:9:3] 与反向 [-1:0]', () {
    final a = _analyzer();
    expect(a.getStringList('li[0:9:3]@text'),
        ['item0sub0', 'item3sub3', 'item6sub6', 'item9sub9']);
    final rev = a.getStringList('li[-1:0]@text');
    expect(rev.length, 10);
    expect(rev.first, 'item9sub9');
    expect(rev.last, 'item0sub0');
  });

  test('前缀 tag./class./children./id.', () {
    final a = _analyzer();
    expect(a.getStringList('tag.li.1@text'), ['item1sub1']);
    expect(a.getStringList('class.item.2@text'), ['item2sub2']);
    expect(a.getStringList('id.special.0@text'), ['item0sub0']);
    final children = a.getStringList('#list > .item.3@text');
    expect(children, ['item3sub3']);
  });

  test('text. 前缀按 ownText 包含匹配', () {
    final a = _analyzer();
    expect(a.getStringList('text.作者@text'), ['作者：张三']);
  });

  test('无 @ 取值方法的纯选择器取 text', () {
    final a = _analyzer();
    expect(a.getStringList('li.5'), ['item5sub5']);
  });
}
