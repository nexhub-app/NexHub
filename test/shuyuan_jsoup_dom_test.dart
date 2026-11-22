/// org.jsoup.Jsoup.parse 与最小 DOM/CSS 选择器互操作测试。
///
/// 书源脚本（发现页/列表/目录/正文的 @js: 规则）大量使用 Rhino 直调
/// jsoup：`Jsoup.parse(html).select(...).get(i).text()/attr()`。QuickJS
/// 沙箱需提供同形 API。全部断言基于合成 HTML，不访问网络。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/web_book/web_book_types.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _html = '''
<html><body>
<div id="main" class="box list">
  <ul class="items">
    <li class="item" data-id="1"><a href="/a"> 标题 <b>一</b> </a></li>
    <li class="item hot" data-id="2"><a href="/b">标题二</a></li>
  </ul>
  <p>段落 <span>文本</span></p>
</div>
</body></html>
''';

String _doc() => 'var doc = org.jsoup.Jsoup.parse(${jsonEncode(_html)});\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  setUp(ShuyuanSourceContext.resetForTest);

  test('Jsoup.parse + select/get/first/size/text/attr', () {
    final e = JsEngine();
    final d = _doc();
    expect(e.eval("${d}doc.select('li.item a').size()"), '2');
    expect(e.eval("${d}doc.select('li.item a').get(0).text()"), '标题 一');
    expect(e.eval("${d}doc.select('a').first().attr('href')"), '/a');
    expect(e.eval("${d}doc.select('a').get(1).attr('href')"), '/b');
    expect(e.eval("${d}doc.select('a').get(0).attr('missing')"), '');
    expect(e.eval("${d}doc.select('li').get(1).text()"), '标题二');
    expect(e.eval("${d}doc.select('p').text()"), '段落 文本');
    expect(e.eval("${d}doc.select('li.item').eachText().join('|')"),
        '标题 一|标题二');
  });

  test('CSS：id/class/属性/组合器/伪类', () {
    final e = JsEngine();
    final d = _doc();
    expect(e.eval("${d}doc.select('#main .item.hot').attr('data-id')"), '2');
    expect(e.eval("${d}doc.select('ul > li:nth-child(2)').size()"), '1');
    expect(e.eval("${d}doc.select('li:first-child').attr('data-id')"), '1');
    expect(e.eval("${d}doc.select('li:last-child').attr('data-id')"), '2');
    expect(
        e.eval("${d}doc.select('li[data-id=2] a').text()"), '标题二');
    expect(e.eval("${d}doc.select('li[data-id^=1]').size()"), '1');
    expect(e.eval("${d}doc.select('a[href*=b]').size()"), '1');
    expect(e.eval("${d}doc.select('a[href\$=/b]').size()"), '1');
    expect(e.eval("${d}doc.select('li:not(.hot)').size()"), '1');
    expect(e.eval("${d}doc.select('li:contains(标题二)').size()"), '1');
    expect(e.eval("${d}doc.select('li:eq(1)').attr('data-id')"), '2');
    expect(
        e.eval("${d}doc.select('li:first-child + li').attr('data-id')"),
        '2');
    expect(
        e.eval("${d}doc.select('ul li, p span').size()"), '3');
  });

  test('Element/Elements：html/outerHtml/parent/hasClass/forEach', () {
    final e = JsEngine();
    final d = _doc();
    expect(e.eval("${d}doc.select('a').first().html().indexOf('<b>一</b>') >= 0"),
        'true');
    expect(
        e.eval(
            "${d}doc.select('a').first().outerHtml().indexOf('href=\"/a\"') >= 0"),
        'true');
    expect(e.eval("${d}doc.select('a').first().parent().tagName()"), 'li');
    expect(e.eval("${d}doc.select('li').get(1).hasClass('hot')"), 'true');
    expect(
        e.eval('${d}var n=0; doc.select("li.item").forEach('
            'function(el){ n += el.select("a").size(); }); n'),
        '2');
    expect(e.eval("${d}doc.select('li.item a').get(0).ownText()"), '标题');
  });

  test('Element.remove 后文档中不再命中', () {
    final e = JsEngine();
    final d = _doc();
    expect(
        e.eval('${d}doc.select("li").get(1).remove();'
            'doc.select("li").size()'),
        '1');
  });

  test('parseBodyFragment 与 Packages.org.jsoup.Jsoup.parse', () {
    final e = JsEngine();
    expect(
        e.eval(
            'org.jsoup.Jsoup.parseBodyFragment("<span class=\\"x\\">片段</span>")'
            '.select("span.x").text()'),
        '片段');
    expect(
        e.eval(
            'Packages.org.jsoup.Jsoup.parse("<div><i>A</i></div>")'
            '.select("i").text()'),
        'A');
  });

  test('connect().get() 与 java.get().parse() 返回可查询 Document', () {
    final ctx = ShuyuanSourceContext('src_jsoup_doc')
      ..ajaxCache['https://x.com/page'] = _html
      // Jsoup connect / java.get(url) 走替换头语义：不叠加源头，且不跟随
      // 重定向（选项串随键保留）。
      ..ajaxCache['https://x.com/page,{"_syHeaderMode":"replace"}'] = _html
      ..ajaxCache['https://x.com/page,'
              '{"followRedirects":false,"_syHeaderMode":"replace"}'] = _html;
    ShuyuanSourceContext.run(ctx, () {
      final e = JsEngine.forSource(ctx.sourceId);
      expect(
          e.eval('org.jsoup.Jsoup.connect("https://x.com/page")'
              '.get().select("li.item").size()'),
          '2');
      expect(
          e.eval('java.get("https://x.com/page").parse()'
              '.select("a").first().text()'),
          '标题 一');
      e.dispose();
    });
  });

  test('发现脚本：java.ajax 响应经 Jsoup.parse 生成分类', () {
    final ctx = ShuyuanSourceContext('src_jsoup_explore')
      ..ajaxCache['https://x.com/list'] = '''
<html><body><div class="nav">
<a class="cat" href="/c/1">玄幻</a><a class="cat" href="/c/2">都市</a>
</div></body></html>''';
    ShuyuanSourceContext.run(ctx, () {
      const js = '''
var doc = org.jsoup.Jsoup.parse(java.ajax("https://x.com/list"));
var out = [];
doc.select("a.cat").forEach(function (a) {
  out.push({title: a.text(), url: a.attr("href")});
});
JSON.stringify(out);
''';
      final kinds = parseExploreKinds('@js:$js');
      expect(kinds.map((k) => k.title).toList(), <String>['玄幻', '都市']);
      expect(kinds[1].url, '/c/2');
    });
  });
}
