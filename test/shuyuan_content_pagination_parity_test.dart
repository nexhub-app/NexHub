/// 正文分页对齐 legado BookContent：
/// - 不按「同章 URL 形态」过滤，纯靠已访问集合 + nextChapterUrl 停止；
/// - 串行模式空页照常拼接并继续提取下页；
/// - 无页数上限；
/// - 并发模式任一页失败令整章失败（md3 mapAsync 会传播），但不做连续
///   前缀截断：已发现的后续页仍会被并发请求。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexhub/core/models/novel_block.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book.dart';
import 'package:nexhub/features/shuyuan/web_book/web_book.dart';

XiaoshuoBookSource _source(Map<String, dynamic> content) {
  return XiaoshuoBookSource.fromJson(<String, dynamic>{
    'bookSourceUrl': 'https://pg.test',
    'bookSourceName': 'pagination-test',
    'bookSourceType': 0,
    'ruleContent': content,
  });
}

List<String> _texts(List<NovelBlock> blocks) => <String>[
      for (final b in blocks)
        if (b is NovelTextBlock) b.text,
    ];

Future<HttpServer> _serve(Map<String, String> routes) async {
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
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  late HttpServer server;
  tearDown(() => server.close(force: true));

  Future<List<NovelBlock>> fetch(String url, {String? nextChapterUrl}) async {
    final source = _source(<String, dynamic>{
      'content': '#c@html',
      'nextContentUrl': 'a.next@href',
    });
    final book = XiaoshuoBook(bookUrl: 'https://pg.test/book', name: '')
      ..tocUrl = 'https://pg.test/toc';
    final result = await WebBook().getContent(
      source: source,
      chapterUrl: url,
      originalBook: book,
      nextChapterUrl: nextChapterUrl,
    );
    return result.blocks;
  }

  test('下一页 URL 非「同章形态」也继续跟随（无同章启发式）', () async {
    server = await _serve(<String, String>{
      '/read':
          '<div id="c">第一页</div><a class="next" href="/next/chap-id-2">',
      '/next/chap-id-2':
          '<div id="c">第二页</div><a class="next" href="/x/3">',
      '/x/3': '<div id="c">第三页</div>',
    });
    final origin = 'http://${server.address.address}:${server.port}';
    final blocks = await fetch('$origin/read?book=1&page=1');
    expect(_texts(blocks), <String>['　　第一页', '　　第二页', '　　第三页']);
  });

  test('串行模式空页不终止：继续提取并拼接后续页', () async {
    server = await _serve(<String, String>{
      '/c1.html': '<div id="c">第一页</div>'
          '<a class="next" href="/c2.html">',
      '/c2.html': '<div id="c"></div><a class="next" href="/c3.html">',
      '/c3.html': '<div id="c">第三页</div>',
    });
    final origin = 'http://${server.address.address}:${server.port}';
    final blocks = await fetch('$origin/c1.html');
    expect(_texts(blocks), <String>['　　第一页', '　　第三页']);
  });

  test('串行模式无 30 页上限（31 页全部拼接）', () async {
    final routes = <String, String>{};
    for (var i = 1; i <= 31; i++) {
      routes['/p$i.html'] = '<div id="c">第$i页</div>'
          '${i < 31 ? '<a class="next" href="/p${i + 1}.html">' : ''}';
    }
    server = await _serve(routes);
    final origin = 'http://${server.address.address}:${server.port}';
    final blocks = await fetch('$origin/p1.html');
    expect(_texts(blocks), hasLength(31));
    expect(_texts(blocks).first, '　　第1页');
    expect(_texts(blocks).last, '　　第31页');
  });

  test('并发模式 HTTP 错误状态页按空内容并入，后续页仍被并发拉取（不截断）',
      () async {
    final requested = <String>[];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      requested.add(req.uri.path);
      final routes = <String, String>{
        '/c1.html': '<div id="c">第一页</div>'
            '<a class="next" href="/c2.html"><a class="next" href="/c3.html">'
            '<a class="next" href="/c4.html">',
        '/c3.html': '<div id="c">第三页</div>',
        '/c4.html': '<div id="c">第四页</div>',
      };
      final body = routes[req.uri.path];
      req.response
        ..statusCode = body == null ? 404 : 200
        ..headers.contentType = ContentType.html
        ..write(body ?? '');
      req.response.close();
    });
    final origin = 'http://${server.address.address}:${server.port}';
    // U11 对齐后：HTTP 错误状态是「响应」而非异常（legado OkHttpUtils
    // 原样交规则层）——404 页贡献空内容，整章不失败；同时页列表先整体
    // 展开，后续页不做前缀截断。mapAsync 的异常传播由
    // web_book_content_pool_test 直接锁定（本机代理会对拒绝连接伪造
    // 400 响应，无法在本地模拟网络级失败）。
    final blocks = await fetch('$origin/c1.html');
    expect(_texts(blocks), ['　　第一页', '　　第三页', '　　第四页']);
    expect(requested,
        containsAll(<String>['/c2.html', '/c3.html', '/c4.html']));
  });
}
