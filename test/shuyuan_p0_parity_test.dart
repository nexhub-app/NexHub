/// P0 对等收官回归（第二轮审计）：章变量跨阶段贯通、空目录异常、
/// SearchBook.infoHtml 免抓取、正文阶段 chapter 对象延续。
///
/// 全部使用合成页面 / 本地 HTTP，不访问真实站点。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexhub/core/models/novel_block.dart';
import 'package:nexhub/core/resolver/resolver_registry.dart';
import 'package:nexhub/core/scraper/media_api_service.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_rule.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';
import 'package:nexhub/features/shuyuan/model/search_book.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book_chapter.dart';
import 'package:nexhub/features/shuyuan/presentation/shuyuan_novel_resolver.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';
import 'package:nexhub/features/shuyuan/web_book/book_chapter_list.dart';
import 'package:nexhub/features/shuyuan/web_book/book_list.dart';
import 'package:nexhub/features/shuyuan/web_book/web_book.dart';

XiaoshuoBookSource _tocSource(String origin, Map<String, dynamic> toc) {
  return XiaoshuoBookSource.fromJson(<String, dynamic>{
    'bookSourceUrl': origin,
    'bookSourceName': 'p0-toc',
    'bookSourceType': 0,
    'ruleToc': toc,
  });
}

Future<(HttpServer, String, List<String>)> _startServer(
  Map<String, String> routes,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final requests = <String>[];
  server.listen((req) {
    requests.add(req.uri.toString());
    final body = routes[req.uri.path];
    req.response
      ..statusCode = body == null ? 404 : 200
      ..headers.contentType = ContentType.html
      ..write(body ?? '');
    req.response.close();
  });
  return (server, 'http://127.0.0.1:${server.port}', requests);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    registerShuyuanResolver(ShuyuanNovelResolver.new);
  });

  group('P0-1 章变量归属', () {
    test('目录逐章 @put 落到本章 variableMap，不跨章串扰', () {
      final source = _tocSource('https://toc.test', <String, dynamic>{
        'chapterList': '#list a',
        'chapterName': '@text',
        // legado: 每次求值都是独立 BookChapter，java.get 读不到上一章的 put。
        'chapterUrl': '@href@js:var prior = java.get("seen"); '
            'java.put("seen", chapter.title); '
            'java.put("prior", prior); result',
      });
      final chapters = BookChapterList.analyzeChapterList(
        bookSource: source,
        book: XiaoshuoBook(bookUrl: 'https://toc.test/book/', name: '书'),
        baseUrl: 'https://toc.test/book/',
        redirectUrl: 'https://toc.test/book/',
        body: '<div id="list"><a href="/c1">甲</a><a href="/c2">乙</a></div>',
      );
      expect(chapters.map((c) => c.title), ['甲', '乙']);
      expect(chapters[0].variableMap['seen'], '甲');
      expect(chapters[0].variableMap['prior'], '');
      expect(chapters[1].variableMap['seen'], '乙');
      // 若 @put 落在规则层变量表，第二章会读到第一章的 seen。
      expect(chapters[1].variableMap['prior'], '');
    });

    test('AnalyzeRule.put 有章节时写章节，无章节时写规则层', () {
      final ch = XiaoshuoBookChapter(bookUrl: 'b', url: 'u', title: '旧名');
      final rule = AnalyzeRule(chapter: ch);
      rule.put('k', 'v');
      expect(ch.variableMap['k'], 'v');
      expect(rule.variables.containsKey('k'), isFalse);
      // legado `put` 只写变量表：`title` 没有特殊处理，不得回写章节标题
      //（章节标题由 ruleContent.title 改写；detail 见 P2 轮 B3）。
      rule.put('title', '新名');
      expect(ch.title, '旧名');
      expect(ch.variableMap['title'], '新名');

      final bare = AnalyzeRule();
      bare.put('k', 'v');
      expect(bare.variables['k'], 'v');
    });

    test('JS 直改 chapter.variableMap 回写本章对象', () {
      final ch = XiaoshuoBookChapter(bookUrl: 'b', url: 'u', title: '章');
      final rule = AnalyzeRule(chapter: ch)
        ..setContent('<div id="c">正文</div>');
      final out =
          rule.getString('@js:chapter.variableMap["js"] = "yes"; "ok"');
      expect(out, 'ok');
      expect(ch.variableMap['js'], 'yes');
    });
  });

  group('P0-3 空目录', () {
    test('目录页无章节元素 → TocEmptyException', () async {
      final (server, origin, _) = await _startServer(<String, String>{
        '/empty': '<div id="list"></div>',
      });
      addTearDown(() => server.close(force: true));
      final source = _tocSource(origin, <String, dynamic>{
        'chapterList': '#list a',
        'chapterName': 'text',
        'chapterUrl': '@href',
      });
      final ctx = ShuyuanSourceContext('p0-toc-empty')..bindSource(source);
      await expectLater(
        ShuyuanSourceContext.run(
          ctx,
          () => WebBook().getChapterList(
            source: source,
            book: XiaoshuoBook(bookUrl: '$origin/empty', name: '书'),
          ),
        ),
        throwsA(isA<TocEmptyException>()),
      );
    });

    test('目录响应体为空 → TocEmptyException', () async {
      final (server, origin, _) =
          await _startServer(<String, String>{'/blank': ''});
      addTearDown(() => server.close(force: true));
      final source = _tocSource(origin, <String, dynamic>{
        'chapterList': '#list a',
        'chapterName': 'text',
        'chapterUrl': '@href',
      });
      final ctx = ShuyuanSourceContext('p0-toc-blank')..bindSource(source);
      await expectLater(
        ShuyuanSourceContext.run(
          ctx,
          () => WebBook().getChapterList(
            source: source,
            book: XiaoshuoBook(bookUrl: '$origin/blank', name: '书'),
          ),
        ),
        throwsA(isA<TocEmptyException>()),
      );
    });

    test('WebView 回灌的目录为空 → TocEmptyException', () async {
      final source = ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(
        <String, dynamic>{
          'bookSourceName': 'p0-rendered-empty',
          'bookSourceUrl': 'https://rendered.test',
          'bookSourceType': 0,
          'ruleToc': <String, dynamic>{
            'chapterList': '#list a',
            'chapterName': 'text',
            'chapterUrl': '@href',
          },
        },
      ));
      final service = MediaApiService(ResolverRegistry.instance);
      await expectLater(
        service.fetchNovelChapters(
          source,
          'https://rendered.test/book/1',
          renderedHtml: '<div id="list"></div>',
        ),
        throwsA(isA<TocEmptyException>()),
      );
    });
  });

  group('P0-2 SearchBook.infoHtml', () {
    test('列表基址即书籍地址时整页响应存入 infoHtml', () {
      final source = XiaoshuoBookSource.fromJson(<String, dynamic>{
        'bookSourceUrl': 'https://search.test',
        'bookSourceName': 'p0-search',
        'bookSourceType': 0,
        'ruleSearch': <String, dynamic>{
          'bookList': '#list li.item',
          'name': 'a.n@text',
          'bookUrl': 'a.n@href',
        },
      });
      const html = '<ul id="list"><li class="item">'
          '<a class="n" href="/book/1">书一</a></li></ul>';
      final books = BookList.analyzeBookList(
        bookSource: source,
        baseUrl: 'https://search.test/book/1',
        body: html,
        isSearch: true,
      );
      expect(books.single.bookUrl, 'https://search.test/book/1');
      expect(books.single.infoHtml, html);
    });

    test('bookUrlPattern 命中详情页时整页响应存入 infoHtml', () {
      final source = XiaoshuoBookSource.fromJson(<String, dynamic>{
        'bookSourceUrl': 'https://search.test',
        'bookSourceName': 'p0-search',
        'bookSourceType': 0,
        'bookUrlPattern': '.*/book/1',
        'ruleSearch': <String, dynamic>{
          'bookList': '.never-hit',
          'name': 'a.n@text',
        },
        'ruleBookInfo': <String, dynamic>{
          'name': 'h1.t@text',
          'author': '.au@text',
        },
      });
      const html = '<h1 class="t">详情书</h1><span class="au">作者甲</span>';
      final books = BookList.analyzeBookList(
        bookSource: source,
        baseUrl: 'https://search.test/book/1',
        body: html,
        isSearch: true,
      );
      expect(books.single.name, '详情书');
      expect(books.single.infoHtml, html);
    });

    test('toBook 携带 infoHtml（瞬态，不参与序列化）', () {
      final sb = SearchBook(
        bookUrl: 'https://b.test/1',
        name: '书',
        infoHtml: '<h1>详情</h1>',
      );
      expect(sb.toBook().bookInfoHtml, '<h1>详情</h1>');
      expect(sb.toJson().containsKey('infoHtml'), isFalse);
    });

    test('getBookInfo 复用 infoHtml：零网络请求完成详情解析', () async {
      final (server, origin, requests) =
          await _startServer(<String, String>{});
      addTearDown(() => server.close(force: true));
      final source = XiaoshuoBookSource.fromJson(<String, dynamic>{
        'bookSourceUrl': origin,
        'bookSourceName': 'p0-info',
        'bookSourceType': 0,
        'ruleBookInfo': <String, dynamic>{
          'name': 'h1.t@text',
          'author': '.au@text',
        },
      });
      const html = '<h1 class="t">解析书名</h1><span class="au">作者乙</span>';
      final seed = XiaoshuoBook(bookUrl: '$origin/book/1', name: '')
        ..bookInfoHtml = html;
      final book = await WebBook().getBookInfo(
        source: source,
        bookUrl: '$origin/book/1',
        seedBook: seed,
      );
      expect(identical(book, seed), isTrue);
      expect(book.name, '解析书名');
      expect(book.author, '作者乙');
      expect(requests, isEmpty);
    });
  });

  group('P0-1 正文阶段 chapter 贯通（端到端）', () {
    test('目录 @put 的变量与 index 在正文阶段可见', () async {
      final (server, origin, _) = await _startServer(<String, String>{
        '/toc': '<div id="list"><a href="/c1">甲</a><a href="/c2">乙</a></div>',
        '/c1': '<div id="c">一</div>',
        '/c2': '<div id="c">二</div>',
      });
      addTearDown(() => server.close(force: true));
      final cfg = ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(
        <String, dynamic>{
          'bookSourceName': 'p0-e2e',
          'bookSourceUrl': origin,
          'bookSourceType': 0,
          'ruleToc': <String, dynamic>{
            'chapterList': '#list a',
            'chapterName': '@text',
            'chapterUrl': '@href@js:java.put("ct", chapter.title); result',
          },
          'ruleContent': <String, dynamic>{
            'content': '@js:chapter.variableMap["ct"] + "|" + chapter.index',
          },
        },
      ));
      final service = MediaApiService(ResolverRegistry.instance);
      final episodes = await service.fetchNovelChapters(cfg, '$origin/toc');
      expect(episodes.map((e) => e.title), ['甲', '乙']);

      final result = await service.fetchNovelContentDetailed(
        cfg,
        novelId: '$origin/toc',
        chapterUrl: episodes[1].url,
        chapterTitle: episodes[1].title,
      );
      final text = result.blocks
          .whereType<NovelTextBlock>()
          .map((b) => b.text)
          .join();
      expect(text, contains('乙|1'));
    });
  });
}
