/// AnalyzeUrl 与 legado `AnalyzeUrl`/`NetworkUtils` 的对等回归：
/// GET query / POST form 编码、charset=escape、已编码判定、data:/javascript:
/// 绝对化、baseUrl 端口保留、URL 选项 `type`（hex 响应体）、`bodyJs`、
/// `webViewDelayTime` 解析，以及 discover 列表规则空白回落 ruleSearch。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_url.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';
import 'package:nexhub/features/shuyuan/web_book/book_list.dart';

Future<HttpServer> _startServer({
  Map<String, String> textRoutes = const {},
  Map<String, List<int>> byteRoutes = const {},
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) {
    final bytes = byteRoutes[req.uri.path];
    if (bytes != null) {
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.binary
        ..add(bytes);
      req.response.close();
      return;
    }
    final body = textRoutes[req.uri.path];
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('GET query 编码（legado encodeQueryParams / encodedQuery）', () {
    test('UTF-8：非安全字符逐个编码，安全字符与分页占位符保留', () {
      final au = AnalyzeUrl(
        url: 'http://h.test/s?q={{key}}&safe=a!b&p={{page}}',
        key: '中文 空格',
        page: 2,
        baseUrl: 'http://h.test/',
      );
      expect(
        au.url,
        'http://h.test/s?q=%E4%B8%AD%E6%96%87%20%E7%A9%BA%E6%A0%BC'
        '&safe=a!b&p=2',
      );
    });

    test('charset=gbk：按 GBK 字节编码', () {
      final au = AnalyzeUrl(
        url: 'http://h.test/s?q={{key}},{"charset":"gbk"}',
        key: '中文',
        baseUrl: 'http://h.test/',
      );
      expect(au.url, 'http://h.test/s?q=%D6%D0%CE%C4');
    });

    test('整串已编码（合法 %XX）时原样保留', () {
      final au = AnalyzeUrl(
        url: 'http://h.test/s?q=%E4%B8%AD&a=1',
        baseUrl: 'http://h.test/',
      );
      expect(au.url, 'http://h.test/s?q=%E4%B8%AD&a=1');
    });

    test('charset=escape：JS escape 编码（%uXXXX 小写）', () {
      final au = AnalyzeUrl(
        url: 'http://h.test/s?q={{key}},{"charset":"escape"}',
        key: '中文',
        baseUrl: 'http://h.test/',
      );
      expect(au.url, 'http://h.test/s?q=%u4e2d%u6587');
    });
  });

  group('POST form 编码（legado encodeParams）', () {
    test('无 charset：空格转 +，中文按 UTF-8，补 form Content-Type', () {
      final au = AnalyzeUrl(
        url: 'http://h.test/api,{"method":"POST","body":"q={{key}}&a b=c d"}',
        key: '中文',
        baseUrl: 'http://h.test/',
      );
      expect(au.url, 'http://h.test/api');
      expect(au.body, 'q=%E4%B8%AD%E6%96%87&a+b=c+d');
      expect(au.headerMap['Content-Type'], 'application/x-www-form-urlencoded');
    });

    test('已编码值不重复编码', () {
      final au = AnalyzeUrl(
        url: 'http://h.test/api,{"method":"POST","body":"q=%E4%B8%AD&a=1"}',
        baseUrl: 'http://h.test/',
      );
      expect(au.body, 'q=%E4%B8%AD&a=1');
    });

    test('声明 Content-Type 时不做 form 编码（legado analyzeFields 条件）', () {
      final au = AnalyzeUrl(
        url:
            'http://h.test/api,{"method":"POST","body":"q=中文","headers":{"Content-Type":"text/plain"}}',
        baseUrl: 'http://h.test/',
      );
      expect(au.body, 'q=中文');
      expect(au.headerMap['Content-Type'], 'text/plain');
    });

    test('JSON 请求体原样发送并补 application/json', () {
      final au = AnalyzeUrl(
        url: 'http://h.test/api,{"method":"POST","body":"{\\"q\\":\\"中文\\"}"}',
        baseUrl: 'http://h.test/',
      );
      expect(au.body, '{"q":"中文"}');
      expect(au.headerMap['Content-Type'], 'application/json');
    });
  });

  group('绝对化与 baseUrl（NetworkUtils.getAbsoluteURL/getBaseUrl）', () {
    test('data: 原样保留', () {
      final au = AnalyzeUrl(
        url: 'data:text/plain,hi',
        baseUrl: 'http://h.test/',
      );
      expect(au.url, 'data:text/plain,hi');
    });

    test('javascript: 返回空串', () {
      final au = AnalyzeUrl(
        url: 'javascript:void(0)',
        baseUrl: 'http://h.test/',
      );
      expect(au.url, '');
    });

    test('baseUrl 保留端口', () {
      final au = AnalyzeUrl(
        url: 'http://127.0.0.1:9/a/b?x=1',
        baseUrl: 'http://src.test/',
      );
      expect(au.baseUrl, 'http://127.0.0.1:9');
    });
  });

  group('URL 选项 js 次序（legado analyzeUrl：绝对化 → baseUrl → js）', () {
    test('js 在绝对化后的 URL 上求值，结果不再二次绝对化', () {
      final au = AnalyzeUrl(
        url: "../next,{\"js\":\"result.startsWith('http') ? "
            "result + '/abs' : result + '/rel'\"}",
        baseUrl: 'http://h.test/a/b/',
      );
      expect(au.url, 'http://h.test/a/next/abs');
    });

    test('js 求值前 baseUrl 刷新为绝对化后的源根', () {
      final au = AnalyzeUrl(
        url: 'http://h.test/x,{"js":"result + \'?b=\' + baseUrl"}',
        baseUrl: 'http://other.test/',
      );
      expect(au.url, 'http://h.test/x?b=http://h.test');
    });

    test('相对 URL 的原始 query 不被绝对化提前编码：GBK 仍按源声明', () {
      final au = AnalyzeUrl(
        url: 's?q={{key}},{"charset":"gbk"}',
        key: '中文',
        baseUrl: 'http://h.test/',
      );
      expect(au.url, 'http://h.test/s?q=%D6%D0%CE%C4');
    });
  });

  group('URL 选项消费（legado getStrResponseAwait）', () {
    test('type：响应体为原始字节 hex，且不做文本后处理', () async {
      final server = await _startServer(byteRoutes: {
        '/bin': <int>[0x00, 0x01, 0xab, 0xff],
      });
      try {
        final au = AnalyzeUrl(
          url: '${_origin(server)}/bin,{"type":"audio"}',
          baseUrl: _origin(server),
        );
        expect(au.requestType, 'audio');
        expect(await au.getStrResponse(), '0001abff');
      } finally {
        await server.close(force: true);
      }
    });

    test('data: URI + type：base64 载荷按字节 hex 返回（视频章节 data: 链路）',
        () async {
      // 合成载荷：`<数字>&<数字>`，与视频源章节地址的参数形态一致。
      const raw = '1234567890&9876543210';
      final payload = base64Encode(utf8.encode(raw));
      final expectedHex = utf8
          .encode(raw)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final au = AnalyzeUrl(
        url: 'data:video;base64,$payload,{"type":"c"}',
        baseUrl: 'https://h.test/',
      );
      expect(au.requestType, 'c');
      expect(await au.getStrResponse(), expectedHex);
    });

    test('data: URI（无 type）：base64 载荷解码为文本', () async {
      final payload = base64Encode(utf8.encode('hello 媒体'));
      final au = AnalyzeUrl(url: 'data:text/plain;base64,$payload');
      expect(await au.getStrResponse(), 'hello 媒体');
    });

    test('data: URI：缺失填充的 base64 容错解码', () async {
      // 'ab' → base64 'YWI='，去填充后 'YWI'（Android Base64.DEFAULT 可解）。
      final au = AnalyzeUrl(url: 'data:text/plain;base64,YWI,{"type":"raw"}');
      expect(await au.getStrResponse(), '6162');
    });

    test('bodyJs：响应体作为 result 再过一遍 JS', () async {
      final server = await _startServer(textRoutes: {
        '/js': 'PREFIX:{"a":1}',
      });
      try {
        final au = AnalyzeUrl(
          url: '${_origin(server)}/js,'
              '{"bodyJs":"result.replace(\'PREFIX:\',\'\')"}',
          baseUrl: _origin(server),
        );
        expect(await au.getStrResponse(), '{"a":1}');
      } finally {
        await server.close(force: true);
      }
    });

    test('webViewDelayTime 解析为非负数', () {
      final au = AnalyzeUrl(
        url: 'http://h.test/x,{"webViewDelayTime":1200}',
        baseUrl: 'http://h.test/',
      );
      expect(au.webViewDelayTime, 1200);
      final negative = AnalyzeUrl(
        url: 'http://h.test/x,{"webViewDelayTime":-5}',
        baseUrl: 'http://h.test/',
      );
      expect(negative.webViewDelayTime, 0);
    });
  });

  group('请求头替换语义（legado headerMapF/setHeaders）', () {
    test('替换模式只发显式头：源声明头不叠加，Cookie/自定义头保留', () async {
      final captured = <String, String>{};
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        req.headers.forEach((k, v) => captured[k.toLowerCase()] = v.join(','));
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write('OK');
        req.response.close();
      });
      try {
        final source = XiaoshuoBookSource.fromJson(<String, dynamic>{
          'bookSourceUrl': _origin(server),
          'bookSourceName': 'replacement-headers',
          'header': 'X-Source: src\nX-Shared: source',
        });
        final au = AnalyzeUrl(
          url: '${_origin(server)}/h',
          baseUrl: _origin(server),
          source: source,
          headerMapF: <String, String>{
            'X-Custom': 'c',
            'X-Shared': 'explicit',
            'Cookie': 'sid=1',
          },
        );
        expect(await au.getStrResponse(), 'OK');
        expect(captured['x-source'], isNull);
        expect(captured['x-custom'], 'c');
        expect(captured['x-shared'], 'explicit');
        expect(captured['cookie'], 'sid=1');
        // 声明型请求头同样不再叠加源 header（播放器直链解析共用）。
        expect(au.resolveRequestHeaders()['X-Source'], isNull);
      } finally {
        await server.close(force: true);
      }
    });
  });

  test('发现列表规则为空白串时回落 ruleSearch（legado isNullOrBlank）', () {
    final source = XiaoshuoBookSource.fromJson(<String, dynamic>{
      'bookSourceUrl': 'https://list.test',
      'bookSourceName': 'blank-explore-test',
      'bookSourceType': 0,
      'ruleExplore': <String, dynamic>{'bookList': '  \n '},
      'ruleSearch': <String, dynamic>{
        'bookList': '#list li.item',
        'name': 'a.name@text',
        'bookUrl': 'a.name@href',
      },
    });
    const html = '''
<ul id="list">
  <li class="item"><a class="name" href="/book/A.html">Alpha</a></li>
  <li class="item"><a class="name" href="/book/B.html">Beta</a></li>
</ul>''';
    final ctx = ShuyuanSourceContext('blank-explore-test')..bindSource(source);
    final books = ShuyuanSourceContext.run(
      ctx,
      () => BookList.analyzeBookList(
        bookSource: source,
        baseUrl: 'https://list.test/explore/1.html',
        body: html,
        isSearch: false,
      ),
    );
    expect(books.map((b) => b.name).toList(), <String>['Alpha', 'Beta']);
  });
}
