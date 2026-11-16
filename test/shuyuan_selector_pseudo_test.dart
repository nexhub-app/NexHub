/// jsoup 伪选择器兼容层回归：`:nth-child / :nth-of-type / :eq / :gt / :lt /
/// :containsOwn / :matches / :empty`。package:html 的 querySelectorAll 不支持
/// 这些伪类（部分直接抛 UnimplementedError 被静默吞掉），导致 legado 书源
/// 目录/列表规则大面积「命中 0 元素」。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_jsoup.dart';

String _html() {
  return '''
<html><body>
<div id="list">
  <ul class="toc">
    <li><a href="/1">第一章 开端</a></li>
    <li><a href="/2">第二章 转折</a></li>
    <li><a href="/3">第三章 终局</a></li>
  </ul>
  <ul class="toc">
    <li><a href="/4">第四章 重逢</a></li>
    <li><a href="/5">第五章 尾声</a></li>
  </ul>
  <div id="mixed">
    <a href="/a1">甲</a><span>说明</span><a href="/a2">乙</a><p></p>
  </div>
  <p class="own">作者：李四<span>注</span></p>
</div>
</body></html>
''';
}

AnalyzeByJsoup _a() => AnalyzeByJsoup(_html());

void main() {
  test(':nth-child(n) 子元素序号（1 起）', () {
    expect(_a().getStringList('ul:nth-child(2) > li > a@href'), ['/4', '/5']);
    expect(_a().getStringList('#list > ul:nth-child(1) > li > a@href'),
        ['/1', '/2', '/3']);
    expect(_a().getStringList('li:nth-child(2) > a@text'),
        ['第二章 转折', '第五章 尾声']);
  });

  test(':nth-child(an+b) / odd / even', () {
    expect(_a().getStringList('li:nth-child(2n+1) > a@href'),
        ['/1', '/3', '/4']);
    expect(_a().getStringList('li:nth-child(odd) > a@href'), ['/1', '/3', '/4']);
    expect(_a().getStringList('li:nth-child(even) > a@href'), ['/2', '/5']);
    expect(_a().getStringList('li:nth-child(-n+2) > a@href'),
        ['/1', '/2', '/4', '/5']);
  });

  test(':nth-of-type / :nth-last-child', () {
    expect(_a().getStringList('#mixed > a:nth-of-type(2)@href'), ['/a2']);
    expect(_a().getStringList('#mixed > a:nth-child(2)@href'), isEmpty);
    expect(_a().getStringList('li:nth-last-child(1) > a@href'), ['/3', '/5']);
  });

  test(':eq / :gt / :lt 同级索引（0 起，支持负数）', () {
    expect(_a().getStringList('li:eq(1) > a@href'), ['/2', '/5']);
    expect(_a().getStringList('li:eq(-1) > a@href'), ['/3', '/5']);
    expect(_a().getStringList('li:gt(1) > a@href'), ['/3']);
    expect(_a().getStringList('li:lt(1) > a@href'), ['/1', '/4']);
    expect(_a().getStringList('li:gt(-2) > a@href'), ['/3', '/5']);
  });

  test(':containsOwn 仅匹配自身文本', () {
    expect(_a().getStringList('p:containsOwn(作者)@text'), ['作者：李四注']);
    expect(_a().getStringList('p:containsOwn(注)@text'), isEmpty);
  });

  test(':matches / :matchesOwn 正则', () {
    expect(_a().getStringList('a:matchesOwn(第[一三]章)@href'), ['/1', '/3']);
    expect(_a().getStringList('p:matches(作者)@class'), ['own']);
  });

  test(':empty', () {
    expect(_a().getStringList('#mixed > p:empty@html'), ['<p></p>']);
    expect(_a().getStringList('#mixed > span:empty@html'), isEmpty);
  });

  test('与 :contains / 组合器 / :not 叠加', () {
    expect(_a().getStringList('ul:nth-child(2) li:contains(四) > a@href'),
        ['/4']);
    expect(_a().getStringList('#list > ul:nth-child(1) > li:last-child > a@href'),
        ['/3']);
    expect(_a().getStringList('li:not(:nth-child(2)) > a@href'),
        ['/1', '/3', '/4']);
  });

  test(':has 内嵌 nth 伪类', () {
    expect(_a().getStringList('ul:has(li:nth-child(3)) > li:nth-child(1) > a@href'),
        ['/1']);
  });
}
