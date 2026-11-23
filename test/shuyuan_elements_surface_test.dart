/// jsoup 集合面回归（legado 对等审计 P1-13 补面）：
/// - 沙箱 DOM：Element.siblingElements/siblings/elementSiblingIndex、
///   nextElementSiblings/previousElementSiblings、hasText/data/class 变更；
///   Elements.next/nextAll/prev/prevAll（含查询过滤）、hasClass/hasText/val、
///   asList/contains、attr/hasAttr/eachAttr/eachText 的 jsoup 语义；
/// - 规则桥包装：java.getElements/getElement 返回的 Elements 同形方法，
///   树遍历经「根 HTML + 路径」在沙箱内复原 DOM 上下文（parent/parents/
///   siblings/next/prev 等），跨列表 contains 按节点同一性判定。
/// 全部断言基于合成 HTML，不访问网络。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_rule.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _sandboxHtml = '''
<html><head><title>T</title>
<script>var x=1;</script></head><body>
<div id="main">
  <ul class="list">
    <li class="item" data-id="1">一</li>
    <li class="item" data-id="2">二</li>
    <li class="item hot" data-id="3">三</li>
  </ul>
  <p class="tail" id="tail-id">尾</p>
  <span class="empty">  </span>
</div>
</body></html>
''';

const _nestedHtml = '''
<html><body><ul class="outer">
  <li class="item" data-id="1">一</li>
  <li class="item" data-id="2">二
    <ul class="sub"><li class="item" data-id="21">二一</li></ul>
  </li>
  <li class="item" data-id="3">三</li>
</ul></body></html>
''';

String _doc(String html) =>
    'var doc = org.jsoup.Jsoup.parse(${jsonEncode(html)});\n';

const _ruleHtml = '''
<html><body>
<div class="list">
  <ul class="items">
    <li class="item" data-id="1"><a href="/a">甲</a></li>
    <li class="item hot" data-id="2"><a href="/b">乙</a></li>
    <li class="item" data-id="3"><a href="/c">丙</a></li>
    <li class="item" data-id="4">丁<ul class="sub"><li class="item" data-id="41">丁一</li></ul></li>
  </ul>
  <p class="tail" id="tail-id">尾</p>
</div>
</body></html>
''';

AnalyzeRule _rule() => AnalyzeRule()
  ..setContent(_ruleHtml)
  ..setBaseUrl('https://x.test/');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  setUp(ShuyuanSourceContext.resetForTest);

  group('沙箱 DOM 集合面', () {
    test('next/nextAll/prev/prevAll（含查询过滤、prev 逆文档序）', () {
      final e = JsEngine();
      final d = _doc(_sandboxHtml);
      expect(
          e.eval('${d}doc.select("li").next().eachAttr("data-id").join(",")'),
          '2,3');
      expect(e.eval('${d}doc.select("li").nextAll().size()'), '3');
      expect(
          e.eval('${d}doc.select("li").prev().eachAttr("data-id").join(",")'),
          '1,2');
      expect(
          e.eval('${d}doc.select("li").prevAll().eachAttr("data-id").join(",")'),
          '1,2,1');
      expect(e.eval('${d}doc.select("li.item").next("li.hot").size()'), '1');
      expect(
          e.eval('${d}doc.select("li.hot").prevAll("li.item")'
              '.eachAttr("data-id").join(",")'),
          '2,1');
    });

    test('Element 兄弟族：siblings/siblingIndex/ElementSiblings', () {
      final e = JsEngine();
      final d = _doc(_sandboxHtml);
      expect(e.eval('${d}doc.select("li").get(1).siblings().size()'), '2');
      expect(
          e.eval('${d}doc.select("li").get(1).siblingElements()'
              '.eachAttr("data-id").join(",")'),
          '1,3');
      expect(
          e.eval('${d}doc.select("li").get(1).elementSiblingIndex()'), '1');
      expect(e.eval('${d}doc.select("li").get(1).siblingIndex()'), '1');
      expect(
          e.eval('${d}doc.select("li").first().nextElementSiblings()'
              '.eachAttr("data-id").join(",")'),
          '1,2,3');
      expect(
          e.eval('${d}doc.select("li").get(1).previousElementSiblings()'
              '.eachAttr("data-id").join(",")'),
          '2,1');
      expect(
          e.eval('${d}doc.select("li").get(1).firstElementSibling()'
              '.attr("data-id")'),
          '1');
      expect(
          e.eval('${d}doc.select("li").get(1).lastElementSibling()'
              '.attr("data-id")'),
          '3');
      expect(
          e.eval('${d}doc.select("ul").first().firstElementChild()'
              '.attr("data-id")'),
          '1');
    });

    test('文本/属性集合语义：hasText/eachText/eachAttr/attr/hasAttr/text', () {
      final e = JsEngine();
      final d = _doc(_sandboxHtml);
      expect(e.eval('${d}doc.select("script").first().hasText()'), 'false');
      expect(e.eval('${d}doc.select("script").first().data()'), 'var x=1;');
      expect(e.eval('${d}doc.select("p").first().hasText()'), 'true');
      expect(e.eval('${d}doc.select("span.empty").hasText()'), 'false');
      expect(e.eval('${d}doc.select("p, span.empty").eachText().length'), '1');
      expect(e.eval('${d}doc.select("li, p").eachAttr("data-id").length'), '3');
      expect(e.eval('${d}doc.select("p, li").attr("id")'), 'tail-id');
      expect(e.eval('${d}doc.select("p, li").hasAttr("id")'), 'true');
      expect(e.eval('${d}doc.select("li").text()'), '一 二 三');
      expect(e.eval('${d}doc.select("li").asList().length'), '3');
      expect(
          e.eval('${d}doc.select("li").contains(doc.select("li").first())'),
          'true');
      expect(e.eval('${d}doc.select("li").removeAttr("data-id")'
          '.hasAttr("data-id")'), 'false');
    });

    test('class 变更与 val（链式返回 Elements/Element）', () {
      final e = JsEngine();
      final d = _doc(_sandboxHtml);
      expect(e.eval('${d}doc.select("li").addClass("z").hasClass("z")'),
          'true');
      expect(
          e.eval('${d}doc.select("li").first().addClass("x").hasClass("x")'),
          'true');
      expect(e.eval('${d}doc.select("li").removeClass("item")'
          '.hasClass("item")'), 'false');
      expect(e.eval('${d}doc.select("li.hot").first().toggleClass("hot")'
          '.hasClass("hot")'), 'false');
      expect(e.eval('${d}var s=doc.select("li").first();'
          's.val("v7"); s.val()'), 'v7');
    });

    test('parents().contains 去重嵌套列表（源站常见循环）', () {
      final e = JsEngine();
      final d = _doc(_nestedHtml);
      const loop = '''
var lr = doc.select('li.item');
for (var c = lr.first(), v = 1; v < lr.size(); v++) {
  if (lr.get(v).parents().contains(c)) { lr.remove(v); v--; }
  else c = lr.get(v);
}
lr.size();''';
      expect(e.eval('$d$loop'), '3');
    });
  });

  group('规则桥 Elements 包装集合面', () {
    test('select/selectFirst/eq/not/has/is 与读取方法', () {
      final r = _rule();
      expect(r.getString("@js:java.getElements('li.item').select('a').size()"),
          '3');
      expect(
          r.getString(
              "@js:java.getElements('li.item').selectFirst('a').text()"),
          '甲');
      expect(r.getString("@js:java.getElements('li.item').eq(1).text()"), '乙');
      expect(r.getString("@js:java.getElements('li.item').not('.hot').size()"),
          '4');
      expect(r.getString("@js:java.getElements('li.item').has('a').size()"),
          '3');
      expect(r.getString("@js:java.getElements('li.item').is('.hot')"),
          'true');
      expect(
          r.getString("@js:java.getElements('li.item')"
              ".eachAttr('data-id').join(',')"),
          '1,2,3,4,41');
      expect(
          r.getString("@js:java.getElements('li.item, .tail').attr('id')"),
          'tail-id');
      expect(
          r.getString("@js:java.getElements('li.item').hasAttr('data-id')"),
          'true');
      expect(r.getString("@js:java.getElements('li.item').hasClass('hot')"),
          'true');
      expect(r.getString("@js:java.getElements('li.item').hasText()"), 'true');
      expect(r.getString("@js:java.getElements('a').eachText().length"), '3');
      expect(
          r.getString("@js:java.getElements('li.item').html().split('\\n')"
              '.length'),
          '5');
    });

    test('getElement 树遍历：parent/parents/siblings/兄弟下标', () {
      final r = _rule();
      expect(r.getString("@js:java.getElement('li.hot').parent().tagName()"),
          'ul');
      expect(
          r.getString("@js:java.getElement('li.hot').parents().size()"), '4');
      expect(
          r.getString("@js:java.getElement('li.hot').parents()"
              ".select('div.list').size()"),
          '1');
      expect(r.getString("@js:java.getElement('li.hot').siblings().size()"),
          '3');
      expect(
          r.getString("@js:java.getElement('li.hot').siblingIndex()"), '1');
      expect(
          r.getString(
              "@js:java.getElement('li.hot').previousElementSibling().text()"),
          '甲');
      expect(
          r.getString(
              "@js:java.getElement('li.item').nextElementSibling()"
              ".select('a').attr('href')"),
          '/b');
      expect(
          r.getString(
              "@js:java.getElement('li.hot').nextElementSiblings().size()"),
          '3');
      expect(
          r.getString("@js:java.getElement('li.hot').data()"), '');
      expect(r.getString("@js:java.getElement('li.hot').val()"), '');
    });

    test('Elements 遍历族：next/nextAll/prevAll/parents', () {
      final r = _rule();
      expect(
          r.getString(
              "@js:java.getElements('li.item').next().eachAttr('data-id')"
              ".join(',')"),
          '2,3,4');
      expect(r.getString("@js:java.getElements('li.item').nextAll().size()"),
          '6');
      expect(
          r.getString("@js:java.getElements('li.hot').prevAll()"
              ".eachAttr('data-id').join(',')"),
          '1');
      expect(
          r.getString("@js:java.getElements('li.hot').prevAll('li.item')"
              ".eachAttr('data-id').join(',')"),
          '1');
      expect(r.getString("@js:java.getElements('li.item').parents().size()"),
          '6');
      expect(
          r.getString("@js:java.getElements('li.item').parents()"
              ".hasClass('list')"),
          'true');
      expect(
          r.getString(
              "@js:java.getElement('ul.items').select('li.item').size()"),
          '5');
      expect(
          r.getString("@js:java.getElement('ul.items').children().size()"),
          '4');
    });

    test('parents().contains 去重嵌套列表（节点同一性跨列表）', () {
      final r = _rule();
      const loop = '''
var lr = java.getElements('li.item');
for (var c = lr.first(), v = 1; v < lr.size(); v++) {
  if (lr.get(v).parents().contains(c)) { lr.remove(v); v--; }
  else c = lr.get(v);
}
lr.size();''';
      expect(r.getString('@js:$loop'), '4');
    });
  });
}
