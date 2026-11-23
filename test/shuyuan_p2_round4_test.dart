/// legado 对等审计第四轮 P2 回归：
/// - R4-5 BookList filter/shouldBreak 钩子（filter 在 kind 之后、字数之前；
///   shouldBreak 逐条收后检查）；
/// - R4-6 ruleBookInfo.relatedBooks 模块加载与 related 路由；
/// - R4-7 formatJs 快照/回写补 wordCount/reviewImg/variable；
/// - R4-9 卷章正文在抓取前短路。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexhub/core/models/media_item.dart';
import 'package:nexhub/core/models/novel_block.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book_chapter.dart';
import 'package:nexhub/features/shuyuan/presentation/shuyuan_novel_resolver.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';
import 'package:nexhub/features/shuyuan/web_book/book_chapter_list.dart';
import 'package:nexhub/features/shuyuan/web_book/book_list.dart';
import 'package:nexhub/features/shuyuan/web_book/related_books.dart';
import 'package:nexhub/features/shuyuan/web_book/web_book.dart';

const _searchHtml = '''
<ul id="list">
  <li class="item">
    <a class="name" href="/book/a.html">书A</a>
    <span class="author">甲</span><span class="kind">玄幻</span>
    <span class="words">12000</span>
  </li>
  <li class="item">
    <a class="name" href="/book/b.html">书B</a>
    <span class="author">乙</span><span class="kind">都市</span>
    <span class="words">8000</span>
  </li>
</ul>''';

XiaoshuoBookSource _listSource() {
  return XiaoshuoBookSource.fromJson(<String, dynamic>{
    'bookSourceUrl': 'https://p4.test',
    'bookSourceName': 'p2-round4',
    'bookSourceType': 0,
    'ruleSearch': <String, dynamic>{
      'bookList': '#list li.item',
      'name': 'a.name@text',
      'author': 'span.author@text',
      'kind': 'span.kind@text',
      // 字数规则带副作用：用于观察 filter 是否在字数求值前短路。
      'wordCount': 'span.words@text@put:{wcRan:"span.words@text"}',
      'bookUrl': 'a.name@href',
    },
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ShuyuanSourceContext.resetForTest();
  });

  group('R4-5 BookList filter/shouldBreak', () {
    test('filter 在 kind 解析之后调用；拒绝条目不求值后续字段', () {
      final source = _listSource();
      final ctx = ShuyuanSourceContext('p2r4-filter')..bindSource(source);
      final calls = <(String, String, String?)>[];
      final books = ShuyuanSourceContext.run(
        ctx,
        () => BookList.analyzeBookList(
          bookSource: source,
          baseUrl: 'https://p4.test/search?q=x',
          body: _searchHtml,
          isSearch: true,
          searchKey: 'x',
          filter: (name, author, kind) {
            calls.add((name, author, kind));
            return name != '书A';
          },
        ),
      );

      expect(books.map((b) => b.name), ['书B']);
      // filter 拿到已解析的 name/author/kind（legado 在 kind 之后调用）。
      expect(calls, <(String, String, String?)>[
        ('书A', '甲', '玄幻'),
        ('书B', '乙', '都市'),
      ]);
      // 被拒绝的条目在字数规则求值前短路：不留下该书变量快照。
      expect(ctx.bookItemVars.keys, ['https://p4.test/book/b.html']);
    });

    test('shouldBreak 按已收条数逐条检查，达标后不再求值后续条目', () {
      final source = _listSource();
      final ctx = ShuyuanSourceContext('p2r4-break')..bindSource(source);
      final sizes = <int>[];
      final books = ShuyuanSourceContext.run(
        ctx,
        () => BookList.analyzeBookList(
          bookSource: source,
          baseUrl: 'https://p4.test/search?q=x',
          body: _searchHtml,
          isSearch: true,
          searchKey: 'x',
          shouldBreak: (size) {
            sizes.add(size);
            return size >= 1;
          },
        ),
      );

      expect(books.map((b) => b.name), ['书A']);
      expect(sizes, [1]);
      // 第二条未被求值（没有第二条的变量快照）。
      expect(ctx.bookItemVars.keys, ['https://p4.test/book/a.html']);
    });

    test('条目被 filter 拒绝时 shouldBreak 仍按当前收数逐条检查', () {
      final source = _listSource();
      final ctx = ShuyuanSourceContext('p2r4-break-reject')..bindSource(source);
      final sizes = <int>[];
      final books = ShuyuanSourceContext.run(
        ctx,
        () => BookList.analyzeBookList(
          bookSource: source,
          baseUrl: 'https://p4.test/search?q=x',
          body: _searchHtml,
          isSearch: true,
          searchKey: 'x',
          filter: (name, author, kind) => false,
          shouldBreak: (size) {
            sizes.add(size);
            return size >= 1;
          },
        ),
      );

      expect(books, isEmpty);
      expect(sizes, [0, 0]);
    });

    test('整页详情回退路径同样应用 filter（书名/作者/分类可见）', () {
      final source = XiaoshuoBookSource.fromJson(<String, dynamic>{
        'bookSourceUrl': 'https://p4.test',
        'bookSourceName': 'p2-round4-detail',
        'bookSourceType': 0,
        'ruleSearch': <String, dynamic>{
          'name': 'h1@text',
          'author': 'span.author@text',
          'kind': 'span.kind@text',
        },
        'ruleBookInfo': <String, dynamic>{
          'name': 'h1@text',
          'author': 'span.author@text',
          'kind': 'span.kind@text',
        },
      });
      const detailHtml = '<h1>详情书</h1><span class="author">丁</span>'
          '<span class="kind">武侠</span>';
      final ctx = ShuyuanSourceContext('p2r4-detail')..bindSource(source);
      final calls = <(String, String, String?)>[];

      List<String> run(bool Function(String, String, String?) filter) {
        calls.clear();
        final books = ShuyuanSourceContext.run(
          ctx,
          () => BookList.analyzeBookList(
            bookSource: source,
            baseUrl: 'https://p4.test/book/9',
            body: detailHtml,
            isSearch: true,
            searchKey: '详情书',
            filter: (name, author, kind) {
              calls.add((name, author, kind));
              return filter(name, author, kind);
            },
          ),
        );
        return books.map((b) => b.name).toList();
      }

      expect(run((n, a, k) => true), ['详情书']);
      expect(calls, <(String, String, String?)>[('详情书', '丁', '武侠')]);

      expect(run((n, a, k) => false), isEmpty);
    });
  });

  group('R4-6 relatedBooks', () {
    late HttpServer server;
    late String base;

    setUp(() async {
      HttpOverrides.global = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://${server.address.host}:${server.port}';
      String listHtml(List<(String, String)> books) => '<ul id="list">'
          '${books.map((b) => '<li class="item">'
              '<a href="$base/book/${b.$1}">${b.$2}</a></li>').join()}'
          '</ul>';
      server.listen((req) {
        final path = req.uri.path;
        void send(String html, [int status = 200]) {
          req.response
            ..statusCode = status
            ..headers.contentType = ContentType.html
            ..write(html);
          req.response.close();
        }

        switch (path) {
          case '/rel/1.html':
            return send(listHtml([
              ('current', '当前书'),
              ('r1', '同类甲'),
              ('r2', '同类乙'),
            ]));
          case '/rel/2.html':
            // 过滤当前书后为空 → 整个模块丢弃。
            return send(listHtml([('current', '当前书')]));
          case '/rel/3.html':
            return send(listHtml([('r3', '标题键书')]));
          case '/rel/redir':
            req.response
              ..statusCode = 302
              ..headers.set(HttpHeaders.locationHeader, '/rel/1.html');
            req.response.close();
            return;
          default:
            return send('', 404);
        }
      });
    });

    tearDown(() => server.close(force: true));

    Map<String, dynamic> relatedSourceJson({String? relatedBooks}) {
      return <String, dynamic>{
        'bookSourceUrl': '$base/',
        'bookSourceName': 'p2-related',
        'bookSourceType': 0,
        'ruleBookInfo': <String, dynamic>{
          'name': 'h1@text',
          'relatedBooks': relatedBooks ??
              jsonEncode(<Map<String, String>>[
                {'key': 'm1', 'title': '同类推荐', 'url': '/rel/1.html'},
                {'title': '只有标题', 'url': '/rel/3.html'},
                {'key': 'empty', 'title': '过滤后为空', 'url': '/rel/2.html'},
                {'key': 'blank', 'title': '空地址', 'url': '   '},
                {
                  'key': 'dead',
                  'title': '失败模块',
                  'url': 'http://127.0.0.1:1/rel',
                },
              ]),
        },
        'ruleExplore': <String, dynamic>{
          'bookList': '#list li.item',
          'name': 'a@text',
          'bookUrl': 'a@href',
        },
      };
    }

    test('模块并行加载：过滤当前书、空模块丢弃、失败模块隔离、key 回退标题', () async {
      final source = XiaoshuoBookSource.fromJson(relatedSourceJson());
      final ctx = ShuyuanSourceContext('p2r4-related')..bindSource(source);
      final modules = await ShuyuanSourceContext.run(
        ctx,
        () => RelatedBooks.load(
          book: XiaoshuoBook(bookUrl: '$base/book/current', name: '当前书'),
          source: source,
        ),
      );

      expect(modules.map((m) => m.title).toList(), ['同类推荐', '只有标题']);
      expect(modules[0].key, 'm1');
      expect(modules[0].url, '/rel/1.html');
      expect(modules[0].resolvedUrl, '$base/rel/1.html');
      expect(modules[0].books.map((b) => b.name).toList(), ['同类甲', '同类乙']);
      // 未声明 key 时回退 title（legado `def.key ?: def.title.orEmpty()`）。
      expect(modules[1].key, '只有标题');
      expect(modules[1].books.map((b) => b.name).toList(), ['标题键书']);
    });

    test('relatedBooks 非法 JSON 返回空模块列表', () async {
      final source = XiaoshuoBookSource.fromJson(
          relatedSourceJson(relatedBooks: 'not-json'));
      final ctx = ShuyuanSourceContext('p2r4-related-bad')..bindSource(source);
      final modules = await ShuyuanSourceContext.run(
        ctx,
        () => RelatedBooks.load(
          book: XiaoshuoBook(bookUrl: '$base/book/current', name: '当前书'),
          source: source,
        ),
      );
      expect(modules, isEmpty);
    });

    test('exploreBookWithResolvedUrl 返回最终地址（重定向后）与列表', () async {
      final source = XiaoshuoBookSource.fromJson(relatedSourceJson());
      final ctx = ShuyuanSourceContext('p2r4-resolved')..bindSource(source);
      final (resolvedUrl, books) = await ShuyuanSourceContext.run(
        ctx,
        () => WebBook().exploreBookWithResolvedUrl(
          source: source,
          url: '/rel/redir',
        ),
      );
      expect(resolvedUrl, '$base/rel/1.html');
      expect(books.map((b) => b.name).toList(), ['当前书', '同类甲', '同类乙']);
    });

    test('relatedBooks 非空时适配器声明 related 路由', () {
      final withRelated = ShuyuanAdapter.toPluginConfig(
          ShuyuanSource.fromJson(relatedSourceJson()));
      expect(withRelated.routes.containsKey('related'), isTrue);

      final withoutRelated = ShuyuanAdapter.toPluginConfig(
          ShuyuanSource.fromJson(<String, dynamic>{
        'bookSourceUrl': 'https://rel.test',
        'bookSourceName': 'p2-related-none',
        'bookSourceType': 0,
        'ruleBookInfo': <String, dynamic>{'name': 'h1@text'},
      }));
      expect(withoutRelated.routes.containsKey('related'), isFalse);
    });

    test('related 路由按模块返回书籍并过滤当前书', () async {
      final cfg = ShuyuanAdapter.toPluginConfig(
          ShuyuanSource.fromJson(relatedSourceJson()));
      final out = await ShuyuanNovelResolver()
          .resolve(cfg, 'related', vars: <String, String>{
        'id': '$base/book/current',
      });
      final items = (out as List).cast<MediaItem>();
      expect(items.map((i) => i.title).toList(), ['同类甲', '同类乙', '标题键书']);
    });
  });

  group('R4-7 formatJs 实体扩展字段', () {
    test('快照可读 wordCount/reviewImg/variable，直改落回章节实体', () {
      final chapter = XiaoshuoBookChapter(
        bookUrl: '',
        url: '/1',
        title: '第一章',
        wordCount: '12000',
        reviewImg: 'https://img.test/x.png',
        variable: '{"a":"b"}',
      );
      chapter.variableMap['a'] = 'b';
      BookChapterList.applyFormatJs([chapter], '''
        chapter.wordCount = chapter.wordCount + '字';
        chapter.reviewImg = 'https://img.test/y.png';
        chapter.variable = '{"a":"c","b":"d"}';
        void 0;
      ''');
      expect(chapter.wordCount, '12000字');
      expect(chapter.reviewImg, 'https://img.test/y.png');
      expect(chapter.variable, '{"a":"c","b":"d"}');
      // `variable` 直改后同步变量表，正文阶段 @get 读到新值。
      expect(chapter.variableMap, <String, String>{'a': 'c', 'b': 'd'});
    });

    test('未修改扩展字段不被回读弄脏（保持 null）', () {
      final chapter = XiaoshuoBookChapter(bookUrl: '', url: '/1', title: '甲');
      BookChapterList.applyFormatJs([chapter], 'null');
      expect(chapter.wordCount, isNull);
      expect(chapter.reviewImg, isNull);
      expect(chapter.variable, isNull);
    });
  });

  group('R4-9 卷章正文抓取前短路', () {
    late HttpServer server;
    late String base;
    var hits = 0;

    setUp(() async {
      HttpOverrides.global = null;
      hits = 0;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://${server.address.host}:${server.port}';
      server.listen((req) {
        hits++;
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write('<div id="c">不该请求的正文</div>');
        req.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    XiaoshuoBookSource volumeSource() => XiaoshuoBookSource.fromJson(
          <String, dynamic>{
            'bookSourceUrl': '$base/',
            'bookSourceName': 'p2-volume',
            'bookSourceType': 0,
            'ruleContent': <String, dynamic>{'content': '#c@text'},
          },
        );

    Future<BookContentResult> fetchVolume(
      XiaoshuoBookSource source,
      XiaoshuoBookChapter chapter,
    ) {
      final ctx = ShuyuanSourceContext('p2r4-volume')..bindSource(source);
      return ShuyuanSourceContext.run(
        ctx,
        () => WebBook().getContent(
          source: source,
          chapterUrl: chapter.url,
          bookChapter: chapter,
          originalBook:
              XiaoshuoBook(bookUrl: '$base/book/1', name: '当前书'),
        ),
      );
    }

    test('卷章（URL 以标题开头）不发请求，直接返回 tag', () async {
      final source = volumeSource();
      final chapter = XiaoshuoBookChapter(
        bookUrl: '$base/book/1',
        url: '第一卷',
        title: '第一卷',
        isVolume: true,
        tag: '卷说明',
      );
      final result = await fetchVolume(source, chapter);
      expect(result.error, isNull);
      expect(result.content, '卷说明');
      expect(result.blocks.length, 1);
      expect((result.blocks.single as NovelTextBlock).text, '卷说明');
      expect(hits, 0, reason: '卷章正文必须在抓取前短路');
    });

    test('卷章 tag 为空时返回空内容且不报错、不发请求', () async {
      final source = volumeSource();
      final chapter = XiaoshuoBookChapter(
        bookUrl: '$base/book/1',
        url: '第二卷',
        title: '第二卷',
        isVolume: true,
      );
      final result = await fetchVolume(source, chapter);
      expect(result.error, isNull);
      expect(result.content, '');
      expect(result.blocks, isEmpty);
      expect(hits, 0);
    });
  });
}
