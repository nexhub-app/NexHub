/// 编排层重定向基址回归：详情/目录/正文的 `redirectUrl` 取响应最终地址
/// （legado `res.url`）。settle 重放命中阶段缓存时请求地址不含跟随重定向
/// 的结果，若直接用 `analyzeUrl.url` 会把相对链接解析到请求目录。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexhub/core/models/novel_block.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book.dart';
import 'package:nexhub/features/shuyuan/web_book/web_book.dart';

XiaoshuoBookSource _source(String base, Map<String, dynamic> rules) {
  return XiaoshuoBookSource.fromJson(<String, dynamic>{
    'bookSourceUrl': base,
    'bookSourceName': 'redirect-base-test',
    'bookSourceType': 0,
    ...rules,
  });
}

String _textOf(BookContentResult result) => result.blocks
    .whereType<NovelTextBlock>()
    .map((b) => b.text)
    .join('\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late String base;
  late Map<String, int> hits;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    HttpOverrides.global = null;
    hits = <String, int>{};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://${server.address.host}:${server.port}';
    server.listen((req) {
      final path = req.uri.path;
      hits[path] = (hits[path] ?? 0) + 1;
      void redirect(String location) {
        req.response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, location);
        req.response.close();
      }

      void html(String body) {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write(body);
        req.response.close();
      }

      if (path == '/detail') return redirect('/deep/dir/detail.html');
      if (path == '/deep/dir/detail.html') {
        return html('<h1>重定向书</h1>'
            '<a class="toc" href="toc/1.html">目录</a>');
      }
      if (path == '/toc') return redirect('/toc/real/list.html');
      if (path == '/toc/real/list.html') {
        return html('<div id="list">'
            '<a class="c" href="c/1.html">第1章</a></div>');
      }
      if (path == '/content') return redirect('/content/real/page.html');
      if (path == '/content/real/page.html') {
        return html('<p class="txt">第一页</p>'
            '<a class="next" href="next.html">下一页</a>');
      }
      if (path == '/content/real/next.html') {
        return html('<p class="txt">第二页</p>');
      }
      req.response.statusCode = 404;
      req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('详情：重放命中缓存后 tocUrl 仍按最终地址解析', () async {
    final source = _source(base, <String, dynamic>{
      'ruleBookInfo': <String, dynamic>{
        'name': 'h1@text',
        'tocUrl': 'a.toc@href',
      },
    });
    final ctx = ShuyuanSourceContext('detail-redirect')..bindSource(source);
    await ShuyuanSourceContext.run(ctx, () async {
      final first = await WebBook()
          .getBookInfo(source: source, bookUrl: '$base/detail');
      expect(first.tocUrl, '$base/deep/dir/toc/1.html');

      // 重放：同一阶段缓存作用域内的第二次解析（命中缓存，不再发请求）。
      final replay = await WebBook()
          .getBookInfo(source: source, bookUrl: '$base/detail');
      expect(replay.tocUrl, '$base/deep/dir/toc/1.html');
    });
    expect(hits['/detail'], 1);
    expect(hits['/deep/dir/detail.html'], 1);
  });

  test('目录：重放命中缓存后章节相对地址仍按最终地址解析', () async {
    final source = _source(base, <String, dynamic>{
      'ruleToc': <String, dynamic>{
        'chapterList': '#list a.c',
        'chapterName': 'text',
        'chapterUrl': '@href',
      },
    });
    final ctx = ShuyuanSourceContext('toc-redirect')..bindSource(source);
    await ShuyuanSourceContext.run(ctx, () async {
      Future<List<String>> runOnce() async {
        final book = XiaoshuoBook(bookUrl: '$base/book.html', name: '重定向书')
          ..tocUrl = '$base/toc';
        final chapters =
            await WebBook().getChapterList(source: source, book: book);
        return chapters.map((c) => c.url).toList();
      }

      expect(await runOnce(), ['$base/toc/real/c/1.html']);
      expect(await runOnce(), ['$base/toc/real/c/1.html']);
    });
    expect(hits['/toc'], 1);
    expect(hits['/toc/real/list.html'], 1);
  });

  test('正文：重放命中缓存后下一页仍按最终地址解析', () async {
    final source = _source(base, <String, dynamic>{
      'ruleContent': <String, dynamic>{
        'content': 'p.txt@text',
        'nextContentUrl': 'a.next@href',
      },
    });
    final ctx = ShuyuanSourceContext('content-redirect')..bindSource(source);
    await ShuyuanSourceContext.run(ctx, () async {
      Future<String> runOnce() async {
        final book = XiaoshuoBook(bookUrl: '$base/book.html', name: '重定向书')
          ..tocUrl = '$base/toc';
        final result = await WebBook().getContent(
          source: source,
          chapterUrl: '$base/content',
          originalBook: book,
        );
        return _textOf(result);
      }

      final first = await runOnce();
      expect(first, contains('第一页'));
      expect(first, contains('第二页'));

      final replay = await runOnce();
      expect(replay, contains('第一页'));
      expect(replay, contains('第二页'));
    });
    expect(hits['/content'], 1);
    expect(hits['/content/real/page.html'], 1);
    expect(hits['/content/real/next.html'], 1);
  });
}
