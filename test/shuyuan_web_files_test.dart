/// 文件类书源（legado bookSourceType=3）：下载地址解析、文件名判定与
/// 下载字节回传的合成 HTTP 回归。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/core/models/web_file_item.dart';
import 'package:nexhub/core/scraper/verification_detector.dart'
    show SourceResolveException;
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/analyze/web_file_naming.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book.dart';
import 'package:nexhub/features/shuyuan/presentation/shuyuan_novel_resolver.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';
import 'package:nexhub/features/shuyuan/web_book/book_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<HttpServer> _startServer(
  Future<void> Function(HttpRequest req) handler,
) async {
  final HttpServer server =
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((HttpRequest req) async {
    try {
      await handler(req);
    } finally {
      await req.response.close();
    }
  });
  return server;
}

PluginConfig _webFileConfig(String origin) {
  return ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(
    <String, dynamic>{
      'bookSourceName': 'web-file-flow',
      'bookSourceUrl': origin,
      'bookSourceType': 3,
      'ruleBookInfo': <String, dynamic>{
        'name': '.book-name@text',
        'author': '.book-author@text',
        'downloadUrls': 'a.dl@href',
      },
    },
  ));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ShuyuanSourceContext.resetForTest();
  });

  group('文件名判定（md3 UrlUtil / AppPattern）', () {
    test('URL 路径名：合法后缀直取，php/html/空段返回 null', () {
      expect(webFileNameFromPath('https://h.test/a/b/书名.txt?x=1'), '书名.txt');
      expect(webFileNameFromPath('https://h.test/a/file.epub#part'), 'file.epub');
      expect(webFileNameFromPath('https://h.test/a/file.php'), isNull);
      expect(webFileNameFromPath('https://h.test/a/file.html'), isNull);
      expect(webFileNameFromPath('https://h.test/a/'), isNull);
      expect(webFileNameFromPath('https://h.test/a/file.中文'), isNull);
    });

    test('Content-Disposition：filename 与 filename*', () {
      expect(
        webFileNameFromContentDisposition('attachment; filename="book.txt"'),
        'book.txt',
      );
      expect(
        webFileNameFromContentDisposition(
            "attachment; filename*=UTF-8''%E4%B9%A6.epub"),
        '书.epub',
      );
      expect(webFileNameFromContentDisposition(null), isNull);
      expect(webFileNameFromContentDisposition('inline'), isNull);
    });

    test('导出名：模板拼接 + 非法字符替换 + 空后缀回退 txt', () {
      expect(
        webBookExportName(bookName: '书:名', author: 'a/b', suffix: 'txt'),
        '书_名 作者：a_b.txt',
      );
      expect(
        webBookExportName(bookName: '书', author: '', suffix: ''),
        '书 作者：.txt',
      );
    });

    test('格式分类与后缀规范化', () {
      expect(isWebBookFile('A.TXT'), isTrue);
      expect(isWebBookFile('a.epub'), isTrue);
      expect(isWebBookFile('a.zip'), isFalse);
      expect(isWebArchiveFile('a.CBZ'), isTrue);
      expect(isWebArchiveFile('a.rar'), isTrue);
      expect(isWebArchiveFile('a.txt'), isFalse);
      expect(webFileSuffixOrExt('x.epub3'), 'epub3');
      expect(webFileSuffixOrExt('x.中文'), 'ext');
      expect(webFileSuffixOrExt('x'), 'ext');
    });

    test('归档内条目展示名去掉 hash 前缀', () {
      expect(webArchiveEntryDisplayName('-42_书名.txt'), '书名.txt');
      expect(webArchiveEntryDisplayName('7_书.epub'), '书.epub');
      expect(webArchiveEntryDisplayName('书名.txt'), '书名.txt');
    });
  });

  group('BookInfo：文件源下载地址', () {
    XiaoshuoBookSource source({String? downloadUrls}) =>
        XiaoshuoBookSource.fromJson(<String, dynamic>{
          'bookSourceName': 'web-file',
          'bookSourceUrl': 'https://x.test',
          'bookSourceType': 3,
          'ruleBookInfo': <String, dynamic>{
            if (downloadUrls != null) 'downloadUrls': downloadUrls,
            'tocUrl': '//ignored',
          },
        });

    test('downloadUrls 按 isUrl 绝对化，且不写 tocUrl', () {
      final XiaoshuoBook book =
          XiaoshuoBook(bookUrl: 'https://x.test/book/1', name: '');
      BookInfo.analyzeBookInfo(
        bookSource: source(downloadUrls: 'a.dl@href'),
        book: book,
        baseUrl: 'https://x.test/book/1',
        redirectUrl: null,
        body: '<a class="dl" href="/f/a.txt">A</a>'
            '<a class="dl" href="/f/b.zip">B</a>',
      );
      expect(book.downloadUrls, <String>[
        'https://x.test/f/a.txt',
        'https://x.test/f/b.zip',
      ]);
      expect(book.tocUrl, isNull);
    });

    test('无下载链接抛 SourceResolveException（md3「下载链接为空」）', () {
      final XiaoshuoBook book =
          XiaoshuoBook(bookUrl: 'https://x.test/book/1', name: '');
      expect(
        () => BookInfo.analyzeBookInfo(
          bookSource: source(),
          book: book,
          baseUrl: 'https://x.test/book/1',
          redirectUrl: null,
          body: '<html></html>',
        ),
        throwsA(isA<SourceResolveException>()),
      );
    });
  });

  group('resolver：webFiles / webFileDownload', () {
    late HttpServer server;
    late String origin;

    setUp(() async {
      server = await _startServer((HttpRequest req) async {
        final String path = req.uri.path;
        if (req.method == 'GET' && path == '/book/1') {
          req.response
            ..statusCode = 200
            ..headers.contentType = ContentType.html
            ..write('<h1 class="book-name">测试书</h1>'
                '<span class="book-author">测试作者</span>'
                '<a class="dl" href="/files/novel.txt">1</a>'
                '<a class="dl" href="/download.php?id=2">2</a>'
                '<a class="dl" href="/go">3</a>'
                '<a class="dl" href="/download.php?id=3">4</a>');
          return;
        }
        if (req.method == 'HEAD' && path == '/download.php') {
          if (req.uri.queryParameters['id'] == '2') {
            req.response
              ..statusCode = 200
              ..headers.set(
                  'content-disposition', 'attachment; filename="second.epub"');
          } else {
            req.response.statusCode = 200;
          }
          return;
        }
        if (req.method == 'HEAD' && path == '/go') {
          req.response
            ..statusCode = 302
            ..headers.set('location', '/files/third.azw3');
          return;
        }
        if (req.method == 'GET' && path == '/files/novel.bin') {
          req.response
            ..statusCode = 200
            ..headers.contentType = ContentType.binary
            ..add(<int>[0, 1, 2, 255, 254, 65]);
          return;
        }
        req.response.statusCode = 404;
      });
      origin = 'http://${server.address.address}:${server.port}';
    });

    tearDown(() => server.close(force: true));

    test('webFiles：路径名 / HEAD 头 / 兜底命名', () async {
      final ShuyuanNovelResolver resolver = ShuyuanNovelResolver();
      final List<WebFileItem> files = await resolver.resolve(
        _webFileConfig(origin),
        'webFiles',
        vars: <String, String>{'id': '$origin/book/1'},
      ) as List<WebFileItem>;
      expect(files.map((WebFileItem f) => f.name), <String>[
        'novel.txt',
        'second.epub',
        'third.azw3',
        '测试书 作者：测试作者.txt',
      ]);
      expect(files.first.url, '$origin/files/novel.txt');
    });

    test('webFileDownload：返回原始字节', () async {
      final ShuyuanNovelResolver resolver = ShuyuanNovelResolver();
      final Uint8List bytes = await resolver.resolve(
        _webFileConfig(origin),
        'webFileDownload',
        vars: <String, String>{'url': '$origin/files/novel.bin'},
      ) as Uint8List;
      expect(bytes, <int>[0, 1, 2, 255, 254, 65]);
    });
  });
}
