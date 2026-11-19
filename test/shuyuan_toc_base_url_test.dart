/// 目录请求基址对齐 legado：`AnalyzeUrl(mUrl = book.tocUrl, baseUrl =
/// book.bookUrl)`。相对 tocUrl 必须按书籍详情页解析，而不是按书源首页
/// 解析（否则相对路径拼到站点根目录，抓到 404/错误页 → 目录恒为 0 章）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book.dart';
import 'package:nexhub/features/shuyuan/web_book/web_book.dart';

XiaoshuoBookSource _source() {
  return XiaoshuoBookSource.fromJson(<String, dynamic>{
    'bookSourceUrl': 'https://toc-base.test',
    'bookSourceName': 'toc-base-test',
    'bookSourceType': 0,
    'ruleToc': <String, dynamic>{
      'chapterList': '#list a',
      'chapterName': 'text',
      'chapterUrl': '@href',
    },
  });
}

Future<HttpServer> _startServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) {
    final body = switch (req.uri.path) {
      '/book/1/list.html' =>
        '<div id="list"><a href="1.html">第1章</a><a href="2.html">第2章</a></div>',
      _ => '',
    };
    req.response
      ..statusCode = body.isEmpty ? 404 : 200
      ..headers.contentType = ContentType.html
      ..write(body);
    req.response.close();
  });
  return server;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('相对 tocUrl 按书籍详情页解析（而非书源首页）', () async {
    final server = await _startServer();
    addTearDown(() => server.close(force: true));
    final base = 'http://${server.address.host}:${server.port}';

    final chapters = await WebBook().getChapterList(
      source: _source(),
      book: XiaoshuoBook(
        bookUrl: '$base/book/1/',
        name: '测试书',
        tocUrl: 'list.html',
      ),
    );

    expect(chapters.map((c) => c.title).toList(), <String>['第1章', '第2章']);
    expect(chapters.map((c) => c.url).toList(),
        <String>['$base/book/1/1.html', '$base/book/1/2.html']);
  });
}
