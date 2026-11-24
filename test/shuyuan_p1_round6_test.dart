/// 对等扫描 P1 收口（B1/C2/N1/N2）回归：
/// B1 URL 内 `{{...}}` 按代码语义平衡扫描（表达式里含 `}}` 不再被截断）、
/// C2 单页入口的 replaceRegex 输入形态与 legado 一致（已剥标签/已解实体）、
/// N1 登录表单值与登录请求头跨上下文持久化、
/// N2 整章装配（subContent → title → 整章替换）对渲染回灌入口同样生效。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexhub/core/models/novel_block.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_rule.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_url.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book_chapter.dart';
import 'package:nexhub/features/shuyuan/web_book/book_content.dart';

XiaoshuoBookSource _source({Map<String, dynamic>? content}) {
  return XiaoshuoBookSource.fromJson(<String, dynamic>{
    'bookSourceUrl': 'https://src.test',
    'bookSourceName': 'p1-round6',
    'bookSourceType': 0,
    if (content != null) 'ruleContent': content,
  });
}

XiaoshuoBook _book(String url) => XiaoshuoBook(bookUrl: url, name: '书');

XiaoshuoBookChapter _chapter(String url) =>
    XiaoshuoBookChapter(bookUrl: 'https://src.test/book/1.html', url: url);

List<String> _texts(List<NovelBlock> blocks) => <String>[
      for (final b in blocks)
        if (b is NovelTextBlock) b.text,
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('B1 URL 内 {{}} 平衡扫描', () {
    test('表达式内含 }} 时整体求值（不再被首个 }} 截断）', () {
      final au = AnalyzeUrl(
        url: 'https://h.test/api?n={{"}}".length == 2 ? "ok" : "no"}}',
        baseUrl: 'https://h.test/',
      );
      expect(au.url, 'https://h.test/api?n=ok');
    });

    test('嵌套对象字面量完整求值', () {
      final au = AnalyzeUrl(
        url: 'https://h.test/api?n={{(function(){return {a:{b:1}};})()'
            '.a.b === 1 ? "ok" : "no"}}',
        baseUrl: 'https://h.test/',
      );
      expect(au.url, 'https://h.test/api?n=ok');
    });

    test('相邻占位符与普通文本各自展开', () {
      final au = AnalyzeUrl(
        url: 'https://h.test/s?a={{page}}&b=x{{page}}y',
        baseUrl: 'https://h.test/',
        page: 3,
      );
      expect(au.url, 'https://h.test/s?a=3&b=x3y');
    });
  });

  group('C2 单页入口的 replaceRegex 输入形态', () {
    test('替换输入已剥标签、已解实体（legado formatKeepImg 口径）', () {
      final source = _source(content: <String, dynamic>{
        'content': '#c@html',
        // 实体已还原成 `&` 的形态才命中；旧实现把 `&amp;` 原文喂给规则。
        'replaceRegex': '甲&乙##命中',
      });
      final blocks = BookContent.analyzeContent(
        bookSource: source,
        book: _book('https://src.test/book/1.html'),
        bookChapter: _chapter('https://src.test/c/1.html'),
        baseUrl: 'https://src.test/c/1.html',
        redirectUrl: 'https://src.test/c/1.html',
        body: '<div id="c">甲&amp;乙<br>丙</div>',
      );
      expect(_texts(blocks), <String>['　　命中', '　　丙']);
    });

    test('单页入口与整章入口结果一致（同一条后处理链路）', () {
      final source = _source(content: <String, dynamic>{
        'content': '#c@html',
        'replaceRegex': '广告##',
      });
      const body = '<div id="c"><p>正文一</p><p>广告</p></div>';
      final single = BookContent.analyzeContent(
        bookSource: source,
        book: _book('https://src.test/book/1.html'),
        bookChapter: _chapter('https://src.test/c/1.html'),
        baseUrl: 'https://src.test/c/1.html',
        redirectUrl: 'https://src.test/c/1.html',
        body: body,
      );
      final paged = BookContent.analyzeContent(
        bookSource: source,
        book: _book('https://src.test/book/1.html'),
        bookChapter: _chapter('https://src.test/c/1.html'),
        baseUrl: 'https://src.test/c/1.html',
        redirectUrl: 'https://src.test/c/1.html',
        body: body,
        deferChapterPostProcess: true,
      );
      final finalized = BookContent.finalizeChapter(
        blocks: paged,
        contentRule: source.getContentRule(),
        analyzeRule: AnalyzeRule()..setContent(body),
        mediaSource: false,
      );
      expect(_texts(single), _texts(finalized));
    });
  });

  group('N2 整章装配（渲染回灌入口）', () {
    test('subContent 追加正文并统一走整章缩进', () async {
      final source = _source(content: <String, dynamic>{
        'content': '#c@html',
        'subContent': '#sub@text',
      });
      const body = '<div id="c">正文</div><div id="sub">附加段落</div>';
      final blocks = BookContent.analyzeContent(
        bookSource: source,
        book: _book('https://src.test/book/1.html'),
        bookChapter: _chapter('https://src.test/c/1.html'),
        baseUrl: 'https://src.test/c/1.html',
        redirectUrl: 'https://src.test/c/1.html',
        body: body,
        deferChapterPostProcess: true,
      );
      expect(_texts(blocks), <String>['正文']);

      final assembly = await BookContent.assembleChapter(
        bookSource: source,
        book: _book('https://src.test/book/1.html'),
        bookChapter: _chapter('https://src.test/c/1.html'),
        firstBody: body,
        baseUrl: 'https://src.test/c/1.html',
        redirectUrl: 'https://src.test/c/1.html',
        blocks: blocks,
        mediaSource: false,
      );
      expect(_texts(assembly.blocks), <String>['　　正文', '　　附加段落']);
    });
  });

  group('N1 登录信息持久化', () {
    test('登录表单值与登录头跨上下文保留', () async {
      final ctx = await ShuyuanSourceContext.forSource('n1-source');
      ctx.loginInfo['username'] = 'reader';
      ctx.loginHeader['Authorization'] = 'Bearer t';
      ctx.loginHeaderRaw = '{"Authorization":"Bearer t"}';
      ctx.loginDirty = true;
      await ctx.persistIfNeeded();

      final again = await ShuyuanSourceContext.forSource('n1-source');
      expect(again.loginInfo['username'], 'reader');
      expect(again.loginHeader['Authorization'], 'Bearer t');
      expect(again.loginHeaderRaw, '{"Authorization":"Bearer t"}');
      expect(ShuyuanSourceContext.hasPersistedLoginHeaderFor('n1-source'),
          isTrue);
    });

    test('删除源后登录信息不再残留', () async {
      final ctx = await ShuyuanSourceContext.forSource('n1-forget');
      ctx.loginInfo['k'] = 'v';
      ctx.loginDirty = true;
      await ctx.persistIfNeeded();
      await ShuyuanSourceContext.forget('n1-forget');
      final again = await ShuyuanSourceContext.forSource('n1-forget');
      expect(again.loginInfo, isEmpty);
    });
  });
}
