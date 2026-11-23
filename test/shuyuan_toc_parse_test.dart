/// 目录解析回归：逐条字段求值（卷/VIP/付费/更新时间）、URL 兜底、
/// `-` 前缀翻转（单页与多页）、formatJs 绑定、preUpdateJs 前置时序。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book_chapter.dart';
import 'package:nexhub/features/shuyuan/web_book/book_chapter_list.dart';
import 'package:nexhub/features/shuyuan/web_book/web_book.dart';

XiaoshuoBookSource _source(Map<String, dynamic> toc) {
  return XiaoshuoBookSource.fromJson(<String, dynamic>{
    'bookSourceUrl': 'https://toc.test',
    'bookSourceName': 'toc-test',
    'bookSourceType': 0,
    'ruleToc': toc,
  });
}

XiaoshuoBook _book(String bookUrl) =>
    XiaoshuoBook(bookUrl: bookUrl, name: '测试书');

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    // AppLog.d 读高级设置；单测环境无插件实现，注入空内存实现。
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('BookChapterList 逐条解析', () {
    const html = '''
<div id="list">
  <span class="vol" data-v="true" data-time="2024-01">第一卷</span>
  <a href="/book/1.html" data-time="01-01">第1章 起始</a>
  <a href="/book/2.html" data-vip="true">第2章 进阶</a>
  <a href="/book/3.html"></a>
</div>''';

    final source = _source(<String, dynamic>{
      'chapterList': '#list .vol, #list a',
      'chapterName': 'text',
      'chapterUrl': '@href',
      'isVolume': '@data-v',
      'isVip': '@data-vip',
      'isPay': '@data-pay',
      'updateTime': '@data-time',
    });

    test('字段映射 / URL 绝对化 / 卷占位 / 空标题跳过', () {
      final chapters = BookChapterList.analyzeChapterList(
        bookSource: source,
        book: _book('https://toc.test/book/'),
        baseUrl: 'https://toc.test/book/',
        redirectUrl: 'https://toc.test/book/',
        body: html,
      );
      // 空标题条目（第4个 a）被丢弃；卷 + 两章保留。
      expect(chapters.length, 3);
      expect(chapters[0].title, '第一卷');
      expect(chapters[0].isVolume, isTrue);
      // legado getString(isUrl=true) 对空 URL 结果回落 baseUrl（urlRule 缺失
      // 才会留空并走 title+index 占位），此处与 legado 同值。
      expect(chapters[0].url, 'https://toc.test/book/');
      expect(chapters[0].tag, '2024-01');
      expect(chapters[1].title, '第1章 起始');
      expect(chapters[1].url, 'https://toc.test/book/1.html');
      expect(chapters[1].tag, '01-01');
      expect(chapters[2].isVip, isTrue);
      expect(chapters[2].index, 2);
    });

    test('非卷条目 URL 缺失时回落 baseUrl（不丢章）', () {
      final chapters = BookChapterList.analyzeChapterList(
        bookSource: source,
        book: _book('https://toc.test/book/'),
        baseUrl: 'https://toc.test/book/',
        redirectUrl: 'https://toc.test/book/',
        body: '<div id="list"><a>无链接章节</a></div>',
      );
      expect(chapters.length, 1);
      expect(chapters.single.url, 'https://toc.test/book/');
    });
  });

  group('`-` 前缀翻转', () {
    const html = '<div id="list"><a href="/1">甲</a><a href="/2">乙</a>'
        '<a href="/3">丙</a></div>';
    final base = _source(<String, dynamic>{
      'chapterList': '#list a',
      'chapterName': 'text',
      'chapterUrl': '@href',
    });
    final reversed = _source(<String, dynamic>{
      'chapterList': '-#list a',
      'chapterName': 'text',
      'chapterUrl': '@href',
    });

    List<XiaoshuoBookChapter> parse(XiaoshuoBookSource s,
        {bool applyReverse = true}) {
      return BookChapterList.analyzeChapterList(
        bookSource: s,
        book: _book('https://toc.test/'),
        baseUrl: 'https://toc.test/',
        redirectUrl: 'https://toc.test/',
        body: html,
        applyReverse: applyReverse,
      );
    }

    test('默认（单页/直调）保持 legado 翻转语义', () {
      expect(parse(base).map((c) => c.title), ['甲', '乙', '丙']);
      expect(parse(reversed).map((c) => c.title), ['丙', '乙', '甲']);
    });

    test('分页调用方传 applyReverse=false 时保持解析顺序', () {
      expect(parse(reversed, applyReverse: false).map((c) => c.title),
          ['甲', '乙', '丙']);
    });
  });

  test('formatJs 在合并后单次执行：绑定 chapter.title 与 1 起 index', () {
    final source = _source(<String, dynamic>{
      'chapterList': '#list a',
      'chapterName': 'text',
      'chapterUrl': '@href',
      'formatJs': "chapter.title + '#' + index",
    });
    final chapters = BookChapterList.analyzeChapterList(
      bookSource: source,
      book: _book('https://toc.test/'),
      baseUrl: 'https://toc.test/',
      redirectUrl: 'https://toc.test/',
      body: '<div id="list"><a href="/1">甲</a><a href="/2">乙</a></div>',
    );
    // 解析阶段不执行 formatJs（legado 在整份目录定型后才跑）。
    expect(chapters.map((c) => c.title), ['甲', '乙']);
    BookChapterList.applyFormatJs(chapters, source.getTocRule().formatJs);
    expect(chapters.map((c) => c.title), ['甲#1', '乙#2']);
  });

  test('formatJs 的 gInt 整轮只初始化一次，脚本内自增跨章节延续', () {
    final chapters = [
      XiaoshuoBookChapter(bookUrl: '', url: '/1', title: '甲'),
      XiaoshuoBookChapter(bookUrl: '', url: '/2', title: '乙'),
      XiaoshuoBookChapter(bookUrl: '', url: '/3', title: '丙'),
    ];
    BookChapterList.applyFormatJs(chapters, "gInt++ + ':' + title");
    expect(chapters.map((c) => c.title), ['0:甲', '1:乙', '2:丙']);
  });

  group('WebBook.getChapterList 网络链路', () {
    late HttpServer server;
    late String base;

    tearDown(() => server.close(force: true));

    Future<List<XiaoshuoBookChapter>> fetch(
      XiaoshuoBookSource source,
      XiaoshuoBook book, {
      bool runPerJs = false,
    }) async {
      final ctx = ShuyuanSourceContext('toc-net-test')..bindSource(source);
      return ShuyuanSourceContext.run(
        ctx,
        () => WebBook().getChapterList(
            source: source, book: book, runPerJs: runPerJs),
      );
    }

    test('preUpdateJs 在目录请求前执行（改 tocUrl + 写变量）', () async {
      server = await _startServer(<String, String>{
        '/wrong.html': '<div id="list"></div>',
        '/real.html': '<div id="list"><a href="/c/1.html">第一章</a>'
            '<a href="/c/2.html">第二章</a></div>',
      });
      base = 'http://${server.address.host}:${server.port}';
      final source = _source(<String, dynamic>{
        'preUpdateJs': "book.tocUrl = '$base/real.html'; "
            "java.put('tocVar', 'V1');",
        'chapterList': '#list a',
        'chapterName': 'text',
        'chapterUrl': '@href',
      });
      final book = _book('$base/detail.html')..tocUrl = '$base/wrong.html';
      final chapters = await fetch(source, book, runPerJs: true);
      // 若 preUpdateJs 在解析后才跑，请求会落在 wrong.html → 0 章。
      expect(chapters.map((c) => c.title), ['第一章', '第二章']);
      expect(book.variableMap['tocVar'], 'V1');
    });

    test('preUpdateJs 默认（runPerJs=false）不执行', () async {
      server = await _startServer(<String, String>{
        '/wrong.html': '<div id="list"></div>',
        '/real.html': '<div id="list"><a href="/c/1.html">第一章</a></div>',
      });
      base = 'http://${server.address.host}:${server.port}';
      final source = _source(<String, dynamic>{
        'preUpdateJs': "book.tocUrl = '$base/real.html';",
        'chapterList': '#list a',
        'chapterName': 'text',
        'chapterUrl': '@href',
      });
      final book = _book('$base/detail.html')..tocUrl = '$base/wrong.html';
      await expectLater(
          fetch(source, book), throwsA(isA<TocEmptyException>()));
      expect(book.tocUrl, '$base/wrong.html');
    });

    test('多页目录 + `-` 前缀：合并后整列表反转（页序也反转）', () async {
      server = await _startServer(<String, String>{
        '/toc1.html': '<div id="list">'
            '<a class="c" href="/c1">A1</a><a class="c" href="/c2">A2</a>'
            '<a class="next" href="/toc2.html">下一页</a></div>',
        '/toc2.html': '<div id="list">'
            '<a class="c" href="/c3">B1</a><a class="c" href="/c4">B2</a>'
            '</div>',
      });
      base = 'http://${server.address.host}:${server.port}';
      final source = _source(<String, dynamic>{
        'chapterList': '-#list a.c',
        'chapterName': 'text',
        'chapterUrl': '@href',
        'nextTocUrl': '#list a.next@href',
      });
      final chapters = await fetch(
        source,
        _book('$base/detail.html')..tocUrl = '$base/toc1.html',
      );
      expect(chapters.map((c) => c.title), ['B2', 'B1', 'A2', 'A1']);
      expect(chapters.map((c) => c.index), [0, 1, 2, 3]);
    });

    test('多页目录 formatJs 在合并倒序后单次执行（gInt 不逐页重置）', () async {
      server = await _startServer(<String, String>{
        '/toc1.html': '<div id="list">'
            '<a class="c" href="/c1">A1</a><a class="c" href="/c2">A2</a>'
            '<a class="next" href="/toc2.html">下一页</a></div>',
        '/toc2.html': '<div id="list">'
            '<a class="c" href="/c3">B1</a><a class="c" href="/c4">B2</a>'
            '</div>',
      });
      base = 'http://${server.address.host}:${server.port}';
      final source = _source(<String, dynamic>{
        'chapterList': '-#list a.c',
        'chapterName': 'text',
        'chapterUrl': '@href',
        'nextTocUrl': '#list a.next@href',
        'formatJs': "gInt++ + ':' + title",
      });
      final chapters = await fetch(
        source,
        _book('$base/detail.html')..tocUrl = '$base/toc1.html',
      );
      expect(chapters.map((c) => c.title),
          ['0:B2', '1:B1', '2:A2', '3:A1']);
    });

    test('目录分页并发跟随下载线程设置（threadCount=1 严格串行）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'download_settings': jsonEncode(<String, dynamic>{'threadCount': 1}),
      });
      var inFlight = 0;
      var peak = 0;
      final local = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      local.listen((req) async {
        inFlight++;
        if (inFlight > peak) peak = inFlight;
        // 响应慢于同 host 最小间隔（800ms）：若并发池 >1，第二页会在第一页
        // 未完成时发出 → peak 2；严格串行则 peak 恒为 1。
        await Future<void>.delayed(const Duration(milliseconds: 1000));
        final n = int.parse(
            RegExp(r'^/toc(\d+)\.html$').firstMatch(req.uri.path)!.group(1)!);
        final links = StringBuffer('<a class="c" href="/c$n">T$n</a>');
        if (n == 1) {
          for (var i = 2; i <= 5; i++) {
            links.write('<a class="next" href="/toc$i.html">P$i</a>');
          }
        }
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write('<div id="list">$links</div>');
        await req.response.close();
        inFlight--;
      });
      try {
        final origin = 'http://${local.address.host}:${local.port}';
        final source = _source(<String, dynamic>{
          'chapterList': '#list a.c',
          'chapterName': 'text',
          'chapterUrl': '@href',
          'nextTocUrl': '#list a.next@href',
        });
        final chapters = await fetch(
          source,
          _book('$origin/detail.html')..tocUrl = '$origin/toc1.html',
        );
        expect(chapters.map((c) => c.title),
            ['T1', 'T2', 'T3', 'T4', 'T5']);
        expect(peak, 1);
      } finally {
        await local.close(force: true);
      }
    });
  });
}
