/// 发现/搜索列表解析回归：简介/字数/最新章字段、简介 HTML 归一、
/// 协议相对封面、ruleData 绑定、bookUrl 去重、bookUrlPattern 整串匹配、
/// 发现页复用 ruleSearch，以及合成视频源的发现链路。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';
import 'package:nexhub/features/shuyuan/model/search_book.dart';
import 'package:nexhub/features/shuyuan/web_book/book_list.dart';
import 'package:nexhub/features/shuyuan/web_book/web_book.dart';

XiaoshuoBookSource _source(Map<String, dynamic> json) {
  return XiaoshuoBookSource.fromJson(<String, dynamic>{
    'bookSourceUrl': 'https://list.test',
    'bookSourceName': 'list-test',
    'bookSourceType': 0,
    ...json,
  });
}

const _listHtml = '''
<ul id="list">
  <li class="item">
    <a class="name" href="/book/Alpha.html">Alpha</a>
    <span class="author">作者：甲</span>
    <span class="kind">玄幻</span><span class="kind">热血</span>
    <span class="last">最新章 第9章</span>
    <span class="words">12345</span>
    <div class="intro">第一段&nbsp;文字<br>第二段<span>强调</span></div>
    <img class="cover" src="//cdn.test/a.jpg">
  </li>
  <li class="item">
    <a class="name" href="/book/Beta.html">Beta</a>
    <span class="author">乙</span>
    <span class="words">约十万</span>
    <img class="cover" src="/img/b.jpg">
  </li>
</ul>''';

Future<HttpServer> _startServer(Map<String, String> routes) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) {
    final body = routes[req.uri.path];
    req.response
      ..statusCode = body == null ? 404 : 200
      ..headers.contentType = ContentType.html
      ..write(body ?? '');
    req.response.close();
  });
  return server;
}

/// 列表解析依赖源上下文（`{{book.*}}` 模板经 JS 读取 booksInfo 镜像、
/// 条目变量暂存），生产链路都在 `ShuyuanSourceContext.run` 内调用。
List<SearchBook> _analyze(
  XiaoshuoBookSource source, {
  required String baseUrl,
  required String body,
  bool isSearch = false,
  String? searchKey,
}) {
  final ctx = ShuyuanSourceContext('list-test')..bindSource(source);
  return ShuyuanSourceContext.run(
    ctx,
    () => BookList.analyzeBookList(
      bookSource: source,
      baseUrl: baseUrl,
      body: body,
      isSearch: isSearch,
      searchKey: searchKey,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    // AppLog 读高级设置；单测环境无插件实现，注入空内存实现。
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('BookList 发现/搜索列表字段', () {
    final source = _source(<String, dynamic>{
      'ruleExplore': <String, dynamic>{
        'bookList': '#list li.item',
        'name': 'a.name@text',
        'author': 'span.author@text',
        'kind': 'span.kind@text',
        'lastChapter': 'span.last@text',
        'wordCount': 'span.words@text',
        'intro': 'div.intro@html',
        'coverUrl': 'img.cover@src',
        // ruleData 绑定：URL 模板可用当前条目已解析书名。
        'bookUrl': '/book/{{book.name}}.html',
      },
    });

    test('简介 HTML 归一 / 字数格式化 / 分类合并 / URL 绝对化', () {
      final books = _analyze(
        source,
        baseUrl: 'http://list.test/explore/1.html',
        body: _listHtml,
      );
      expect(books.length, 2);

      final a = books.first;
      expect(a.name, 'Alpha');
      expect(a.author, '甲');
      expect(a.kind, '玄幻,热血');
      expect(a.lastChapter, '最新章 第9章');
      // legado wordCountFormat：>10000 → 万字档；非数字原样。
      expect(a.wordCount, '1.2万字');
      // HtmlFormatter：换行标签成段 + 段首全角缩进 + 实体/标签清理。
      expect(a.intro, '　　第一段 文字\n　　第二段强调');
      // 协议相对封面按页面协议解析（http 页保持 http，不硬编码 https）。
      expect(a.coverUrl, 'http://cdn.test/a.jpg');
      // bookUrl 模板读到当前条目书名（ruleData 全程绑定）。
      expect(a.bookUrl, 'http://list.test/book/Alpha.html');

      expect(books[1].wordCount, '约十万');
      expect(books[1].coverUrl, 'http://list.test/img/b.jpg');
    });

    test('同 bookUrl 条目只保留首次（legado equals 仅比较 bookUrl）', () {
      const dupHtml = '''
<ul id="list">
  <li class="item"><a class="name" href="/book/Same.html">Same</a>
    <span class="last">旧章节</span></li>
  <li class="item"><a class="name" href="/book/Same.html">Same</a>
    <span class="last">新章节</span></li>
</ul>''';
      final books = _analyze(
        source,
        baseUrl: 'http://list.test/explore/1.html',
        body: dupHtml,
      );
      expect(books.length, 1);
      expect(books.single.lastChapter, '旧章节');
    });

    test('ruleExplore 为空时发现页复用 ruleSearch 的 intro/wordCount', () {
      final searchOnly = _source(<String, dynamic>{
        'ruleSearch': <String, dynamic>{
          'bookList': '#list li.item',
          'name': 'a.name@text',
          'bookUrl': 'a.name@href',
          'intro': 'div.intro@text',
          'wordCount': 'span.words@text',
        },
      });
      final books = _analyze(
        searchOnly,
        baseUrl: 'http://list.test/explore/1.html',
        body: _listHtml,
      );
      expect(books.first.intro, contains('第一段'));
      expect(books.first.wordCount, '1.2万字');
    });
  });

  group('bookUrlPattern 整串匹配', () {
    test('仅前缀命中不算详情页，仍按列表解析', () {
      final source = _source(<String, dynamic>{
        'bookUrlPattern': r'https://list\.test',
        'ruleSearch': <String, dynamic>{
          'bookList': '#list li.item',
          'name': 'a.name@text',
          'bookUrl': 'a.name@href',
        },
      });
      final books = _analyze(
        source,
        baseUrl: 'https://list.test/list?q=1',
        body: _listHtml,
        isSearch: true,
        searchKey: 'Alpha',
      );
      // 旧实现 hasMatch 会把该列表页误判为详情页 → 0 本。
      expect(books.map((b) => b.name), ['Alpha', 'Beta']);
    });

    test('整串命中时按详情页解析并回填简介/字数/目录', () {
      final source = _source(<String, dynamic>{
        'bookUrlPattern': r'https://list\.test/book/\d+',
        'ruleSearch': <String, dynamic>{
          'bookList': '#list li.item',
          'name': 'a.name@text',
        },
        'ruleBookInfo': <String, dynamic>{
          'name': 'h1.title@text',
          'author': 'span.author@text',
          'intro': 'div.intro@html',
          'wordCount': 'span.words@text',
          'coverUrl': 'img.cover@src',
          'tocUrl': 'a.toc@href',
        },
      });
      const detailHtml = '''
<h1 class="title">详情书</h1>
<span class="author">丙</span>
<div class="intro">简介一<br>简介二</div>
<span class="words">20000</span>
<img class="cover" src="//cdn.test/d.jpg">
<a class="toc" href="/book/1/">目录</a>''';
      final books = _analyze(
        source,
        baseUrl: 'https://list.test/book/1',
        body: detailHtml,
        isSearch: true,
        searchKey: '详情书',
      );
      expect(books.length, 1);
      final b = books.single;
      expect(b.name, '详情书');
      expect(b.intro, '　　简介一\n　　简介二');
      expect(b.wordCount, '2万字');
      expect(b.coverUrl, 'https://cdn.test/d.jpg');
      expect(b.tocUrl, 'https://list.test/book/1/');
      expect(b.type, 0);
    });
  });

  group('SearchBook', () {
    test('equals/hashCode 仅按 bookUrl', () {
      final a = SearchBook(bookUrl: 'u1', name: 'A', lastChapter: 'x');
      final b = SearchBook(bookUrl: 'u1', name: 'B', lastChapter: 'y');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('合成视频源发现链路（本地服务）', () {
    late HttpServer server;
    late String base;

    tearDown(() => server.close(force: true));

    test('exploreBook 分页占位、字段映射、分类名不覆盖已解析简介', () async {
      server = await _startServer(<String, String>{
        '/explore/1.html': '''
<ul id="list">
  <li class="item"><a href="http://x.test/v/1.html">剧集一</a>
    <p class="intro">简介甲</p><span class="words">9999</span></li>
  <li class="item"><a href="http://x.test/v/2.html">剧集二</a>
    <img class="cover" src="//cdn.test/v.jpg"></li>
</ul>''',
      });
      base = 'http://${server.address.host}:${server.port}';
      final source = XiaoshuoBookSource.fromJson(<String, dynamic>{
        'bookSourceUrl': '$base/',
        'bookSourceName': 'video-test',
        'bookSourceType': 4,
        'exploreUrl': '[{"title":"剧集","url":"/explore/{{page}}.html"}]',
        'ruleExplore': <String, dynamic>{
          'bookList': '#list li.item',
          'name': 'a@text',
          'bookUrl': 'a@href',
          'intro': 'p.intro@text',
          'wordCount': 'span.words@text',
          'coverUrl': 'img.cover@src',
        },
      });

      final ctx = ShuyuanSourceContext('explore-net-test')..bindSource(source);
      final books = await ShuyuanSourceContext.run(
        ctx,
        () => WebBook().exploreBook(source: source, page: 1),
      );

      expect(books.length, 2);
      expect(books[0].type, 4);
      expect(books[0].wordCount, '9999字');
      expect(books[0].intro, '简介甲');
      // 无简介的条目用分类名占位（NexHub 发现页展示来源分类）。
      expect(books[1].intro, '剧集');
      expect(books[1].coverUrl, 'http://cdn.test/v.jpg');
    });
  });
}
