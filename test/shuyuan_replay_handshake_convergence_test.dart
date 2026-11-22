/// 多跳登录握手（HEAD 取 Cookie → WebView 取签名 → API）在确定性重放下的
/// 收敛回归：占位符轮不得污染持久 cache，也不得把占位符 URL 当真实请求发出去。
///
/// 全部使用本地合成站点与合成脚本，不访问任何线上书源。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/analyze/webview_fetcher.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';
import 'package:nexhub/features/shuyuan/model/rule_search.dart';
import 'package:nexhub/features/shuyuan/model/search_book.dart';
import 'package:nexhub/features/shuyuan/web_book/web_book.dart';
import 'package:shared_preferences/shared_preferences.dart';

late HttpServer _server;
late String _base;
var _headHits = 0;
var _apiHits = 0;
var _webviewHits = 0;
final _seenHeaders = <String>[];
const String _signed = 'SYNTHETIC-SIGNATURE';

String _libJs() => 'type = "#t#";\nhost = "${_base}/";\n';

/// 共享登录助手：首轮 HEAD/WebView 返回占位符，真实值在后续重放轮补齐。
const String _loginJs = r'''
try {
  var parts = String(java.hexDecodeToString(result)).split(type);
  var uri = parts[0], t1 = parts[1];
  headers = cache.get(type + 'Headers');
  if (headers == null) {
    headers = {'Referer': host};
    C = java.head(host + 'favicon.ico', headers).cookies();
    e = Object.keys(C)[0];
    headers.Cookie = e + '=' + C[e];
    headers.Secret = java.webView('', host + 'secret', 'signature');
    headers = JSON.stringify({headers: headers});
    cache.put(type + 'Headers', headers, 300);
  }
  if (t1 == '搜索') {
    data = JSON.parse(
        java.ajax(host + 'api/search?q=' + uri + ',' + headers)).data;
  }
  JSON.stringify(data);
} catch (err) {
  '';
}
''';

const String _searchUrl = r'@js:`data:;base64,'
    r'${java.base64Encode("book" + type + "搜索")},{"type":"${type}"}`';

Future<void> _startServer() async {
  _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  _base = 'http://${_server.address.address}:${_server.port}';
  _server.listen((req) {
    final path = req.uri.path;
    if (path == '/favicon.ico') {
      _headHits++;
      req.response
        ..statusCode = 200
        ..headers.add('set-cookie', 'sid=abc; Path=/');
      req.response.close();
      return;
    }
    _apiHits++;
    final cookie = req.headers.value('cookie') ?? '';
    final secret = req.headers.value('secret') ?? '';
    _seenHeaders.add('$path|cookie=$cookie|secret=$secret');
    if (!cookie.contains('sid=abc') || secret != _signed) {
      req.response.statusCode = 401;
      req.response.close();
      return;
    }
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(<String, dynamic>{
        'data': <Map<String, String>>[
          {'name': '合成条目', 'bookUrl': '$_base/book/1'},
        ],
      }));
    req.response.close();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  setUp(() async {
    HttpOverrides.global = null;
    JsEngine.resetPoolForTest();
    ShuyuanSourceContext.resetForTest();
    _headHits = 0;
    _apiHits = 0;
    _webviewHits = 0;
    _seenHeaders.clear();
    await _startServer();
    ShuyuanWebviewFetcher.debugFetchOverride = ({
      String? html,
      String? url,
      String? js,
      int delayMs = 0,
      Map<String, String>? headers,
      String? sourceRegex,
      String? overrideUrlRegex,
    }) async {
      _webviewHits++;
      return ShuyuanWebviewResult(
        html: _signed,
        finalUrl: url ?? '',
        cookieHeaders: const <String, String>{},
      );
    };
  });

  tearDown(() async {
    ShuyuanWebviewFetcher.debugFetchOverride = null;
    await _server.close(force: true);
  });

  test('HEAD→WebView→API 握手在重放轮内收敛，占位符不发真实请求', () async {
    final bookSource = XiaoshuoBookSource(
      bookSourceUrl: '$_base/',
      bookSourceName: '本地多跳握手测试源',
      jsLib: _libJs(),
      loginUrl: _loginJs,
      searchUrl: _searchUrl,
      ruleSearch: SearchRule(
        bookList: r'<js>eval(String(source.loginUrl))</js>$.[*]',
        bookName: r'$.name',
        bookUrl: r'$.bookUrl',
      ),
    );
    final ctx = ShuyuanSourceContext('handshake-convergence')..bindSource(bookSource);

    final results = await ShuyuanSourceContext.run(ctx, () async {
      final webBook = WebBook();
      var out = <SearchBook>[];
      for (var pass = 0; pass < 16; pass++) {
        out = await webBook.searchBook(source: bookSource, key: 'x', page: 1);
        if (ctx.ajaxPending.isEmpty && ctx.webviewPending.isEmpty) break;
        await ShuyuanSourceContext.settleAjax(ctx, bookSource);
        await ShuyuanSourceContext.settleWebview(ctx);
      }
      return out;
    });

    expect(results.map((b) => b.name).toList(), <String>['合成条目']);
    expect(_headHits, 1, reason: 'HEAD 只发一次（重放命中缓存）');
    expect(_apiHits, 1, reason: '占位符轮不发 API，真实轮只发一次');
    expect(_webviewHits, greaterThanOrEqualTo(1));
    for (final h in _seenHeaders) {
      expect(h.contains('__WEBVIEW_'), isFalse, reason: h);
      expect(h.contains('__AJAX_'), isFalse, reason: h);
    }
    // 真值落缓存：后续阶段不再重建签名；脏占位值从不进入缓存。
    final cached = ctx.cache['#t#Headers'];
    expect(cached, isNotNull);
    expect(cached!.contains(_signed), isTrue);
    expect(cached.contains('__WEBVIEW_'), isFalse);
  });
}
