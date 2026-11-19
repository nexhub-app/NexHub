/// 目录规则 JS 返回对象数组时的字段直读回归：legado AnalyzeRule 对
/// NativeObject/LinkedTreeMap 内容按「字段名直读」取值（如 chapterName
/// `text`、chapterUrl `href`），不看页面体是否为 JSON。HTML 页面上由 JS
/// 组装对象的源，此前落入 CSS 引擎 → 标题/链接恒空 → 整页 0 章。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book_chapter.dart';
import 'package:nexhub/features/shuyuan/web_book/book_chapter_list.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('HTML 页面上 JS 目录返回对象数组，chapterName/Url 按字段名直读', () {
    final source = XiaoshuoBookSource.fromJson(<String, dynamic>{
      'bookSourceUrl': 'https://toc-js-object.test',
      'bookSourceName': 'toc-js-object-test',
      'bookSourceType': 0,
      'ruleToc': <String, dynamic>{
        // 合成脚本：不依赖真实站点，仅验证对象数组 → 字段直读链路。
        'chapterList': '<js>'
            'var out = [];'
            'for (var i = 1; i <= 2; i++) {'
            '  out.push({text: "第" + i + "章", href: "/c/" + i + ".html",'
            '            volume: i == 1});'
            '}'
            'out'
            '</js>',
        'chapterName': 'text',
        'chapterUrl': 'href',
        'isVolume': 'volume',
      },
    });

    final List<XiaoshuoBookChapter> chapters =
        BookChapterList.analyzeChapterList(
      bookSource: source,
      book: XiaoshuoBook(bookUrl: 'https://toc-js-object.test/book/1/',
          name: '对象数组书'),
      baseUrl: 'https://toc-js-object.test/book/1/',
      redirectUrl: 'https://toc-js-object.test/book/1/',
      // 非 JSON 页面体：JS 规则从 HTML 组装对象（真实站点的常见写法）。
      body: '<html><body><div class="chapters"></div></body></html>',
    );

    expect(chapters.map((c) => c.title), ['第1章', '第2章']);
    expect(chapters.map((c) => c.url), [
      'https://toc-js-object.test/c/1.html',
      'https://toc-js-object.test/c/2.html',
    ]);
    expect(chapters.first.isVolume, isTrue);
    expect(chapters[1].isVolume, isFalse);
  });
}
