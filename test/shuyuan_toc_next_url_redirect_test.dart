/// 目录分页重定向回归：首页目录请求被 302 到其他路径后，`nextTocUrl`
/// 的相对地址必须按**重定向后的最终地址**解析（legado AnalyzeRule 的
/// isUrl 语义基于 redirectUrl），否则后续目录页全部 404 → 只出首页章节。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book_chapter.dart';
import 'package:nexhub/features/shuyuan/web_book/web_book.dart';

XiaoshuoBookSource _source(String base) {
  return XiaoshuoBookSource.fromJson(<String, dynamic>{
    'bookSourceUrl': base,
    'bookSourceName': 'toc-redirect-test',
    'bookSourceType': 0,
    'ruleToc': <String, dynamic>{
      'chapterList': '#list a.c',
      'chapterName': 'text',
      'chapterUrl': '@href',
      'nextTocUrl': '#list a.next@href',
    },
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late String base;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // flutter_test 的默认 HttpOverrides 会拒绝真实请求。
    HttpOverrides.global = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://${server.address.host}:${server.port}';
    server.listen((req) {
      final path = req.uri.path;
      if (path == '/old/list.html') {
        req.response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, '/new/sub/list.html');
        req.response.close();
        return;
      }
      const bodies = <String, String>{
        '/new/sub/list.html': '<div id="list">'
            '<a class="c" href="1.html">第1章</a>'
            '<a class="c" href="2.html">第2章</a>'
            '<a class="next" href="page2.html">下一页</a></div>',
        '/new/sub/page2.html': '<div id="list">'
            '<a class="c" href="3.html">第3章</a>'
            '<a class="c" href="4.html">第4章</a></div>',
      };
      final body = bodies[path];
      req.response
        ..statusCode = body == null ? 404 : 200
        ..headers.contentType = ContentType.html
        ..write(body ?? '');
      req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('302 重定向后 nextTocUrl 相对地址按最终地址解析', () async {
    final source = _source(base);
    final book = XiaoshuoBook(bookUrl: '$base/detail.html', name: '重定向书')
      ..tocUrl = '$base/old/list.html';
    final ctx = ShuyuanSourceContext('toc-redirect-test')..bindSource(source);
    final List<XiaoshuoBookChapter> chapters = await ShuyuanSourceContext.run(
      ctx,
      () => WebBook().getChapterList(source: source, book: book),
    );

    // 按请求地址 /old/list.html 解析 page2.html → /old/page2.html 404
    // → 只剩首页 2 章。
    expect(
      chapters.map((c) => c.title),
      ['第1章', '第2章', '第3章', '第4章'],
    );
    expect(chapters[2].url, '$base/new/sub/3.html');
  });
}
