/// legado `AnalyzeByJSoup` 取值语义回归（jsoup 实测行为）：
/// `text()` 空白折叠/块级与 `<br>` 边界空格/script-style 跳过/pre 保留/
/// U+3000 保留，`textNodes` 归一，`ownText` 直接文本，`attr()` 大小写不敏感，
/// `class./tag./text.` 前缀大小写不敏感且含自身。全部基于合成 HTML。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:nexhub/features/shuyuan/analyze/analyze_jsoup.dart';

const _html = '''
<html><body>
<div id="ws">a   b<span>c	d</span></div>
<div id="blocks"><p>a</p><p>b</p></div>
<div id="mixed"><p>a</p><span>x</span></div>
<div id="br">a<br>b</div>
<div id="script">a<script>var x=1;</script>b</div>
<div id="style">a<style>p{}</style>b</div>
<div id="u3000">\u3000a\u3000\u3000b\u3000</div>
<div id="nbsp">a&nbsp;b</div>
<div id="pre"><pre>a   b</pre>x</div>
<div id="textarea"><textarea>  t  b  </textarea></div>
<p id="hasline">Line One
Line Two</p>
<p id="own">a<br>b<span>c</span>d</p>
<div id="cases" class="Book One">one</div>
<div id="book2" class="x book">two</div>
<ul id="tagcase"><li class="IT em">x</li></ul>
<p id="owntext-p">hello<span>world</span></p>
<a id="attr" HREF="/x" Data-ID="7">x</a>
</body></html>
''';

AnalyzeByJsoup _analyzer() => AnalyzeByJsoup(_html);

void main() {
  test('@text 空白折叠与块级/<br> 边界空格', () {
    final a = _analyzer();
    expect(a.getStringList('#ws@text'), ['a bc d']);
    expect(a.getStringList('#blocks@text'), ['a b']);
    // jsoup 只在块级元素后「紧跟文本节点」时补尾部空格。
    expect(a.getStringList('#mixed@text'), ['ax']);
    expect(a.getStringList('#br@text'), ['a b']);
  });

  test('@text 跳过 script/style 内容但保留边界空格', () {
    final a = _analyzer();
    expect(a.getStringList('#script@text'), ['a b']);
    expect(a.getStringList('#style@text'), ['a b']);
    expect(a.getStringList('#script script@text'), isEmpty);
  });

  test('@text 保留 U+3000、折叠 &nbsp;、保留 pre/textarea 原始空白', () {
    final a = _analyzer();
    expect(a.getStringList('#u3000@text'), ['\u3000a\u3000\u3000b\u3000']);
    expect(a.getStringList('#nbsp@text'), ['a b']);
    expect(a.getStringList('#pre@text'), ['a   b x']);
    expect(a.getStringList('#textarea@text'), ['t  b']);
  });

  test('@textNodes 按 jsoup 折叠后逐节点换行合并', () {
    final a = AnalyzeByJsoup(
        '<html><body><div id="tn">x   y<span>z</span>w\tq</div></body></html>');
    expect(a.getStringList('#tn@textNodes'), ['x y\nw q']);
  });

  test('@ownText 只取直接文本节点，<br> 补空格', () {
    final a = _analyzer();
    expect(a.getStringList('#own@ownText'), ['a bd']);
    expect(a.getStringList('#own@text'), ['a bcd']);
    expect(a.getStringList('#owntext-p@ownText'), ['hello']);
  });

  test('属性取值大小写不敏感', () {
    final a = _analyzer();
    expect(a.getStringList('#attr@HREF'), ['/x']);
    expect(a.getStringList('#attr@href'), ['/x']);
    expect(a.getStringList('#attr@DATA-ID'), ['7']);
    expect(a.getStringList('#attr@missing'), isEmpty);
  });

  test('class. 前缀大小写不敏感、整体类名等价、含自身', () {
    final a = _analyzer();
    expect(a.getStringList('class.BOOK@text'), ['one', 'two']);
    expect(a.getStringList('class.Book One@text'), ['one']);

    final doc = html_parser.parse(
        '<html><body><div class="self">own<span>kid</span></div></body></html>');
    final div = doc.querySelector('.self')!;
    expect(AnalyzeByJsoup(div).getStringList('class.self@text'), ['ownkid']);
  });

  test('tag. 前缀大小写不敏感', () {
    final a = _analyzer();
    expect(a.getStringList('tag.LI.0@text'), ['x']);
  });

  test('text. 前缀大小写不敏感且忽略子元素文本', () {
    final a = _analyzer();
    // 仅 p#owntext-p 的 ownText 为 "hello"（子元素 span 的 world 不算）。
    expect(a.getStringList('text.HELLO@text'), ['helloworld']);
    expect(a.getStringList('text.world@text'), ['world']);
  });

  test(':contains 按 jsoup 归一化后的文本匹配', () {
    final a = _analyzer();
    expect(a.getStringList('p:contains(Line One)@text'), ['Line One Line Two']);
  });

  test('空 CSS 规则返回 script/style 数据节点（jsoup data()）', () {
    final a = AnalyzeByJsoup('<html><head><style>p{color:red}</style></head>'
        '<body><script>var x=1;</script>t</body></html>');
    expect(a.getStringList('@css:'), ['p{color:red}var x=1;']);
  });
}
