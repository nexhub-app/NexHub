/// 详情/正文链路 legado 对等回归：
/// - BookInfo 的 baseUrl/redirectUrl 分工、目录回落与 tocHtml 缓存、
///   书名/作者 legado 正则归一；
/// - BookContent 的恒缩进、完整实体反转义、图块 URL 实体与 URL 选项保留、
///   标题图片剥离、subContent 后处理语义、replaceRegex 的 chapter 绑定；
/// - WebBook.getContent 的多页串行跟随、nextChapterUrl 停止点与 subContent
///   追加（本地 HTTP，合成页面）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexhub/core/models/novel_block.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_rule.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';
import 'package:nexhub/features/shuyuan/model/rule_content.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book_chapter.dart';
import 'package:nexhub/features/shuyuan/web_book/book_content.dart';
import 'package:nexhub/features/shuyuan/web_book/book_info.dart';
import 'package:nexhub/features/shuyuan/web_book/web_book.dart';

XiaoshuoBookSource _source({
  Map<String, dynamic>? info,
  Map<String, dynamic>? content,
  int bookSourceType = 0,
}) {
  return XiaoshuoBookSource.fromJson(<String, dynamic>{
    'bookSourceUrl': 'https://src.test',
    'bookSourceName': 'parity-test',
    'bookSourceType': bookSourceType,
    if (info != null) 'ruleBookInfo': info,
    if (content != null) 'ruleContent': content,
  });
}

XiaoshuoBook _book(String bookUrl) =>
    XiaoshuoBook(bookUrl: bookUrl, name: '', author: '');

XiaoshuoBookChapter _chapter(String url) =>
    XiaoshuoBookChapter(bookUrl: 'https://src.test/book/1.html', url: url);

Future<HttpServer> _startServer(
  Map<String, String> routes, {
  Map<String, String> redirects = const <String, String>{},
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) {
    final location = redirects[req.uri.path];
    if (location != null) {
      req.response
        ..statusCode = 302
        ..headers.set(HttpHeaders.locationHeader, location);
      req.response.close();
      return;
    }
    final body = routes[req.uri.path];
    req.response
      ..statusCode = body == null ? 404 : 200
      ..headers.contentType = ContentType.html
      ..write(body ?? '');
    req.response.close();
  });
  return server;
}

String _origin(HttpServer server) =>
    'http://${server.address.address}:${server.port}';

List<String> _texts(List<NovelBlock> blocks) => <String>[
      for (final b in blocks)
        if (b is NovelTextBlock) b.text,
    ];

List<String> _images(List<NovelBlock> blocks) => <String>[
      for (final b in blocks)
        if (b is NovelImageBlock) b.url,
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('BookInfo 对等', () {
    test('书名/作者按 legado nameRegex/authorRegex 归一', () {
      final source = _source(info: <String, dynamic>{
        'name': '#name@text',
        'author': '#author@text',
      });
      final book = _book('https://src.test/book/1.html');
      BookInfo.analyzeBookInfo(
        bookSource: source,
        book: book,
        baseUrl: 'https://src.test/book/1.html',
        redirectUrl: 'https://src.test/book/1.html',
        body: '<div id="name">书名 作者：张三</div>'
            '<span id="author">作者：李四 著</span>',
      );
      expect(book.name, '书名');
      expect(book.author, '李四');
    });

    test('legado trim 仅去 ASCII 空白：全角空格保留', () {
      final source = _source(info: <String, dynamic>{
        'name': "@js:'书名\u3000'",
        'author': "@js:'\u3000作者甲'",
      });
      final book = _book('https://src.test/book/1.html');
      BookInfo.analyzeBookInfo(
        bookSource: source,
        book: book,
        baseUrl: 'https://src.test/book/1.html',
        redirectUrl: 'https://src.test/book/1.html',
        body: '<html></html>',
      );
      expect(book.name, '书名\u3000');
      expect(book.author, '\u3000作者甲');
    });

    test('tocUrl 相对地址按重定向后的最终地址解析，空规则回落 baseUrl', () {
      final withToc = _source(info: <String, dynamic>{
        'tocUrl': '#toc@href',
      });
      final book = _book('http://orig.test/book/9.html');
      BookInfo.analyzeBookInfo(
        bookSource: withToc,
        book: book,
        baseUrl: 'http://orig.test/book/9.html',
        redirectUrl: 'http://m.orig.test/book/9.html',
        body: '<a id="toc" href="/toc/1">目录</a>',
      );
      // legado：tocUrl 走 getString(isUrl=true) →
      // getAbsoluteURL(redirectUrl, str)，即按响应最终地址解析。
      expect(book.tocUrl, 'http://m.orig.test/toc/1');

      final noToc = _source(info: <String, dynamic>{'name': '#n@text'});
      final book2 = _book('http://orig.test/book/9.html');
      const body = '<div id="n">B</div>';
      BookInfo.analyzeBookInfo(
        bookSource: noToc,
        book: book2,
        baseUrl: 'http://orig.test/book/9.html',
        redirectUrl: 'http://m.orig.test/book/9.html',
        body: body,
      );
      // legado：tocUrl 回落到请求前 baseUrl（不是重定向后的地址），
      // 且二者相等时缓存详情响应体为 tocHtml。
      expect(book2.tocUrl, 'http://orig.test/book/9.html');
      expect(book2.tocHtml, body);
    });
  });

  group('BookContent 对等', () {
    test('未声明 replaceRegex 也按 legado 每段补两个全角空格', () {
      final source = _source(content: <String, dynamic>{
        'content': '#c@html',
      });
      final blocks = BookContent.analyzeContent(
        bookSource: source,
        book: _book('https://src.test/book/1.html'),
        bookChapter: _chapter('https://src.test/c/1.html'),
        baseUrl: 'https://src.test/c/1.html',
        redirectUrl: 'https://src.test/c/1.html',
        body: '<div id="c">第一段<br>第二段</div>',
      );
      expect(_texts(blocks), <String>['　　第一段', '　　第二段']);
    });

    test('完整 HTML4 实体反转义 + legado 空白归一', () {
      final source = _source(content: <String, dynamic>{
        'content': '#c@html',
      });
      final blocks = BookContent.analyzeContent(
        bookSource: source,
        book: _book('https://src.test/book/1.html'),
        bookChapter: _chapter('https://src.test/c/1.html'),
        baseUrl: 'https://src.test/c/1.html',
        redirectUrl: 'https://src.test/c/1.html',
        body: '<div id="c">甲&amp;乙<br>丙&nbsp;丁&copy;&thinsp;</div>',
      );
      expect(_texts(blocks), <String>['　　甲&乙', '　　丙 丁©']);
    });

    test('插图 URL：实体反转义 + URL 选项原样保留', () {
      final source = _source(content: <String, dynamic>{
        'content': '#c@html',
      });
      final blocks = BookContent.analyzeContent(
        bookSource: source,
        book: _book('https://src.test/book/1.html'),
        bookChapter: _chapter('https://src.test/c/1.html'),
        baseUrl: 'https://src.test/c/1.html',
        redirectUrl: 'https://src.test/c/1.html',
        body: '<div id="c">文字'
            '<img src="https://cdn.test/a.jpg?x=1&amp;y=2">'
            '<img src="https://cdn.test/b.jpg,{&quot;headers&quot;:'
            '{&quot;Referer&quot;:&quot;https://x&quot;}}">'
            '</div>',
      );
      expect(_images(blocks), <String>[
        'https://cdn.test/a.jpg?x=1&y=2',
        'https://cdn.test/b.jpg,{"headers":{"Referer":"https://x"}}',
      ]);
    });

    test('标题规则剥离尾部图片地址；仅图片时保留原标题', () {
      final chapter = _chapter('https://src.test/c/1.html')..title = '旧标题';
      final ar = AnalyzeRule()..setContent('x');
      BookContent.applyChapterTitle(
        ar,
        ContentRule(title: "@js:'第1章'+'https://img.test/i.jpg'"),
        chapter,
      );
      expect(chapter.title, '第1章');

      BookContent.applyChapterTitle(
        ar,
        ContentRule(title: "@js:'https://img.test/i.jpg'"),
        chapter,
      );
      expect(chapter.title, '第1章');
    });

    test('replaceRegex JS 分支保留 chapter 绑定', () {
      final chapter = _chapter('https://src.test/c/1.html')..title = '章节A';
      final ar = AnalyzeRule(chapter: chapter)..setContent('章节A正文');
      final out = BookContent.applyReplaceRules(
        '章节A正文',
        "@js:result.replace(chapter.title, 'B')",
        analyzeRule: ar,
      );
      expect(out, 'B正文');
    });

    test('subContent 与正文一起整章后处理：只替换一次并统一缩进', () {
      final ar = AnalyzeRule()..setContent('x');
      final appended = BookContent.extractAppendedBlocks(
        content: '附加段落',
        baseUrl: 'https://src.test/c/1.html',
        redirectUrl: 'https://src.test/c/1.html',
      );
      // 提取阶段不做替换/缩进，统一交给整章后处理。
      expect(_texts(appended), <String>['附加段落']);

      final finalized = BookContent.finalizeChapter(
        blocks: <NovelBlock>[
          const NovelTextBlock('正文页一'),
          ...appended,
        ],
        contentRule: ContentRule(replaceRegex: '附加##追加'),
        analyzeRule: ar,
        mediaSource: false,
      );
      expect(_texts(finalized), <String>['　　正文页一', '　　追加段落']);
    });

    test('整章 replaceRegex 在全部页拼接后执行（跨页规则可命中）', () {
      const content = '第一页尾\n第二页头';
      final ar = AnalyzeRule()..setContent(content);
      final finalized = BookContent.finalizeChapter(
        blocks: const <NovelBlock>[
          NovelTextBlock('第一页尾'),
          NovelTextBlock('第二页头'),
        ],
        contentRule: ContentRule(
          replaceRegex: "@js:result.replace('页尾\\n第二页头', '合并')",
        ),
        analyzeRule: ar,
        mediaSource: false,
      );
      // 逐页替换时两页各自孤立，跨页表达式不可能命中。
      expect(_texts(finalized), <String>['　　第一合并']);
    });

    test('legado `##` 替换形态：整章正则 + 反转义 + 空行也缩进', () {
      final ar = AnalyzeRule()..setContent('x');
      final finalized = BookContent.finalizeChapter(
        blocks: const <NovelBlock>[
          NovelTextBlock('第1段'),
          NovelTextBlock(''),
          NovelTextBlock('第 2 段&amp;尾'),
        ],
        contentRule: ContentRule(replaceRegex: r'##\d+##'),
        analyzeRule: ar,
        mediaSource: false,
      );
      expect(_texts(finalized),
          <String>['　　第段', '　　', '　　第  段&尾']);
    });

    test('块级标签（div/hr/hN/article）转换行，行内空格不折叠', () {
      final source = _source(content: <String, dynamic>{'content': '#c@html'});
      final blocks = BookContent.analyzeContent(
        bookSource: source,
        book: _book('https://src.test/b'),
        bookChapter: _chapter('https://src.test/c/1.html'),
        baseUrl: 'https://src.test/c/1.html',
        redirectUrl: 'https://src.test/c/1.html',
        body: '<div id="c">甲  乙<div>丙</div><hr>'
            '<article>丁</article><h2>戊</h2>己</div>',
      );
      expect(_texts(blocks).map((t) => t.trim()),
          <String>['甲  乙', '丙', '丁', '戊', '己']);
    });
  });

  group('WebBook 详情/正文网络链路', () {
    late HttpServer serverA;
    late HttpServer serverB;

    tearDown(() async {
      await serverA.close(force: true);
      await serverB.close(force: true);
    });

    test('详情重定向：tocUrl 相对解析用最终响应地址', () async {
      serverB = await _startServer(<String, String>{
        '/m/detail.html': '<a id="toc" href="/toc">目录</a>',
      });
      final originB = _origin(serverB);
      serverA = await _startServer(
        <String, String>{},
        redirects: <String, String>{'/detail.html': '$originB/m/detail.html'},
      );
      final originA = _origin(serverA);
      final source = _source(info: <String, dynamic>{
        'name': '#name@text',
        'tocUrl': '#toc@href',
      });
      final book = await WebBook().getBookInfo(
        source: source,
        bookUrl: '$originA/detail.html',
      );
      expect(book.tocUrl, '$originB/toc');
    });

    test('多页正文：同章串行跟随，nextChapterUrl 处停止，subContent 追加', () async {
      final paths = <String>[];
      final routes = <String, String>{
        '/c1.html': '<div id="c">第一页</div>'
            '<a class="next" href="/c1_2.html">下一页</a>'
            '<div id="sub">附加页</div>',
        '/c1_2.html': '<div id="c">第二页</div>'
            '<a class="next" href="/c1_3.html">下一页</a>',
        '/c1_3.html': '<div id="c">下一章正文</div>',
      };
      final server =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        paths.add(req.uri.path);
        final body = routes[req.uri.path];
        req.response
          ..statusCode = body == null ? 404 : 200
          ..headers.contentType = ContentType.html
          ..write(body ?? '');
        req.response.close();
      });
      serverA = server;
      serverB = await _startServer(<String, String>{});
      final origin = _origin(server);
      final source = _source(content: <String, dynamic>{
        'content': '#c@html',
        'nextContentUrl': 'a.next@href',
        'subContent': '#sub@text',
      });
      final book = _book('$origin/book.html')..tocUrl = '$origin/toc.html';
      final result = await WebBook().getContent(
        source: source,
        chapterUrl: '$origin/c1.html',
        originalBook: book,
        nextChapterUrl: '$origin/c1_3.html',
      );
      expect(_texts(result.blocks),
          <String>['　　第一页', '　　第二页', '　　附加页']);
      expect(result.error, isNull);
      // 下一页地址等于 nextChapterUrl 时必须停止，不能抓取下一章。
      expect(paths, isNot(contains('/c1_3.html')));
      expect(paths, containsAllInOrder(<String>['/c1.html', '/c1_2.html']));
    });

    test('音频源 subContent 存歌词变量，不并入正文', () async {
      serverA = await _startServer(<String, String>{
        '/a1.html': '<div id="c">音频直链</div><div id="sub">歌词段</div>',
      });
      serverB = await _startServer(<String, String>{});
      final origin = _origin(serverA);
      final source = _source(bookSourceType: 1, content: <String, dynamic>{
        'content': '#c@text',
        'subContent': '#sub@text',
      });
      final result = await WebBook().getContent(
        source: source,
        chapterUrl: '$origin/a1.html',
        originalBook: _book('$origin/book.html'),
      );
      expect(_texts(result.blocks), <String>['音频直链']);
      expect(result.lyric, '歌词段');
    });

    test('图片源忽略 subContent（md3 仅在线小说追加）', () async {
      serverA = await _startServer(<String, String>{
        '/i1.html': '<div id="c">图集说明</div><div id="sub">附加页</div>',
      });
      serverB = await _startServer(<String, String>{});
      final origin = _origin(serverA);
      final source = _source(bookSourceType: 2, content: <String, dynamic>{
        'content': '#c@text',
        'subContent': '#sub@text',
      });
      final result = await WebBook().getContent(
        source: source,
        chapterUrl: '$origin/i1.html',
        originalBook: _book('$origin/book.html'),
      );
      expect(_texts(result.blocks), <String>['　　图集说明']);
      expect(result.lyric, isNull);
    });

    test('并发正文分页 HTTP 错误状态页按空内容并入（U11：非异常）', () async {
      final paths = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        paths.add(req.uri.path);
        final body = switch (req.uri.path) {
          '/b1.html' => '<div id="c">第一页</div>'
              '<a class="n" href="/b2.html">N</a>'
              '<a class="n" href="/b3.html">N</a>',
          '/b2.html' => '<div id="c">第二页</div>',
          _ => null,
        };
        req.response
          ..statusCode = body == null ? 404 : 200
          ..headers.contentType = ContentType.html
          ..write(body ?? '');
        req.response.close();
      });
      serverA = server;
      serverB = await _startServer(<String, String>{});
      final origin = _origin(server);
      final source = _source(content: <String, dynamic>{
        'content': '#c@html',
        'nextContentUrl': 'a.n@href',
      });
      // U11 对齐后：HTTP 错误状态是「响应」而非异常（legado OkHttpUtils
      // 原样交规则层）——b3 为 404 空页贡献空内容，整章不失败。mapAsync
      // 的异常传播由 web_book_content_pool_test 直接锁定。
      final result = await WebBook().getContent(
        source: source,
        chapterUrl: '$origin/b1.html',
        originalBook: _book('$origin/book.html'),
      );
      final text = result.content;
      expect(text, contains('第一页'));
      expect(text, contains('第二页'));
      expect(paths, containsAll(<String>['/b1.html', '/b2.html', '/b3.html']));
    });
  });
}
