/// `<js>…</js>` + JSONPath 组合规则与 JS 数组结果的 legado 对等回归：
/// - legado AnalyzeRule.getElements：JS 段返回字符串（`JSON.stringify` 的
///   列表文本）时原样作为下一段 JSONPath 的输入；NexHub 此前在 JS 段
///   丢弃非 List 结果 → `<js>…</js>$.[*]` 规则恒 0 元素（API 型目录整页为空）；
/// - legado getStringList：JS 返回原生数组时按列表取值；空数组产出空列表。
///   NexHub 此前把空数组字符串化为 `"[]"` 并绝对化成分页 URL，导致多抓一次
///   404 假分页。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_rule.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book_chapter.dart';
import 'package:nexhub/features/shuyuan/web_book/book_chapter_list.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('JS 返回 JSON 字符串 + 尾随 JSONPath：字符串透传给下一段规则', () {
    final source = XiaoshuoBookSource.fromJson(<String, dynamic>{
      'bookSourceUrl': 'https://toc-js-jsonpath.test',
      'bookSourceName': 'toc-js-jsonpath-test',
      'bookSourceType': 0,
      'ruleToc': <String, dynamic>{
        // 合成脚本：模拟 API 型目录源（JS 组装对象数组后 JSON.stringify，
        // 尾随 JSONPath 做条目选择）。
        'chapterList': '<js>'
            'var out = [];'
            'for (var i = 1; i <= 2; i++) {'
            '  out.push({title: "第" + i + "章", url: "/c/" + i + ".html"});'
            '}'
            'result = JSON.stringify(out)'
            '</js>\n'
            r'$.[*]',
        'chapterName': r'$.title',
        'chapterUrl': r'$.url',
      },
    });

    final List<XiaoshuoBookChapter> chapters =
        BookChapterList.analyzeChapterList(
      bookSource: source,
      book: XiaoshuoBook(
          bookUrl: 'https://toc-js-jsonpath.test/book/1/', name: '接口书'),
      baseUrl: 'https://toc-js-jsonpath.test/book/1/',
      redirectUrl: 'https://toc-js-jsonpath.test/book/1/',
      body: '{"data":{"id":1}}',
    );

    expect(chapters.map((c) => c.title), ['第1章', '第2章']);
    expect(chapters.map((c) => c.url), [
      'https://toc-js-jsonpath.test/c/1.html',
      'https://toc-js-jsonpath.test/c/2.html',
    ]);
  });

  test('nextTocUrl 的 JS 返回空数组：不产出分页 URL', () {
    final source = XiaoshuoBookSource.fromJson(<String, dynamic>{
      'bookSourceUrl': 'https://toc-next-empty.test',
      'bookSourceName': 'toc-next-empty-test',
      'bookSourceType': 0,
      'ruleToc': <String, dynamic>{
        'chapterList': r'$.chapters[*]',
        'chapterName': r'$.title',
        'chapterUrl': r'$.url',
        'nextTocUrl': '@js: let list = []; list',
      },
    });

    final nextUrls = <String>[];
    final chapters = BookChapterList.analyzeChapterList(
      bookSource: source,
      book: XiaoshuoBook(
          bookUrl: 'https://toc-next-empty.test/book/1', name: '空分页书'),
      baseUrl: 'https://toc-next-empty.test/book/1',
      redirectUrl: 'https://toc-next-empty.test/book/1',
      body: '{"chapters":[{"title":"第1章","url":"/c/1"}]}',
      nextUrlsOut: nextUrls,
    );

    expect(chapters.length, 1);
    expect(nextUrls, isEmpty);
  });

  test('nextTocUrl 的 JS 返回非空数组：数组条目作为分页 URL', () {
    final source = XiaoshuoBookSource.fromJson(<String, dynamic>{
      'bookSourceUrl': 'https://toc-next-array.test',
      'bookSourceName': 'toc-next-array-test',
      'bookSourceType': 0,
      'ruleToc': <String, dynamic>{
        'chapterList': r'$.chapters[*]',
        'chapterName': r'$.title',
        'chapterUrl': r'$.url',
        'nextTocUrl': '@js: ["https://toc-next-array.test/book/1/p2"]',
      },
    });

    final rule = AnalyzeRule(
      book: XiaoshuoBook(
          bookUrl: 'https://toc-next-array.test/book/1', name: '分页书'),
    )
      ..setContent('{"chapters":[]}', 'https://toc-next-array.test/book/1')
      ..setBaseUrl('https://toc-next-array.test/book/1')
      ..setRedirectUrl('https://toc-next-array.test/book/1');

    expect(
      rule.getStringList(source.getTocRule().nextTocUrl, isUrl: true),
      ['https://toc-next-array.test/book/1/p2'],
    );
  });
}
