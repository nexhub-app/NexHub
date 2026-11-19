/// 目录页地址定期更新类书源：preUpdateJs 内修改 `book.bookUrl` 后调用
/// `java.refreshTocUrl()` 应重新解析详情页并采用更新后的 tocUrl。
/// 对齐 legado `AnalyzeRule.refreshTocUrl()` → `WebBook.getBookInfoAwait`：
/// 该调用只在目录抓取前的 preUpdateJs 中有效，刷新详情目的是更新 book.tocUrl。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/presentation/shuyuan_novel_resolver.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';
import 'package:nexhub/features/shuyuan/shuyuan_explore_info_store.dart';
import 'package:nexhub/features/shuyuan/shuyuan_explore_kinds_store.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

late HttpServer _server;
late String _base;
final List<String> _detailHits = <String>[];

Future<void> _startServer() async {
  _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  _base = 'http://${_server.address.host}:${_server.port}';
  _server.listen((req) {
    final path = req.uri.path;
    String body;
    if (path == '/book/1/') {
      _detailHits.add(req.uri.query);
      body = '<html><body><div id="info">测试书</div></body></html>';
    } else if (path == '/toc1.html') {
      body = '<div id="list"></div>';
    } else if (path == '/toc2.html') {
      body = '<div id="list"><a href="c1.html">第2章</a></div>';
    } else {
      req.response.statusCode = 404;
      req.response.close();
      return;
    }
    final bytes = utf8.encode(body);
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..add(bytes);
    req.response.close();
  });
}

PluginConfig _config() {
  final tocRule = "<js>String(book.bookUrl).indexOf('v=2') >= 0 "
      "? '$_base/toc2.html' : '$_base/toc1.html'</js>";
  return ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(<String, dynamic>{
    'bookSourceName': '本地 tocUrl 刷新测试源',
    'bookSourceUrl': '$_base/site/',
    'bookSourceType': 0,
    'enabled': true,
    'ruleBookInfo': <String, dynamic>{
      'tocUrl': tocRule,
    },
    'ruleToc': <String, dynamic>{
      'chapterList': '#list a',
      'chapterName': 'text',
      'chapterUrl': '@href',
      'preUpdateJs': "book.bookUrl = String(book.bookUrl) + '?v=2'; "
          'java.refreshTocUrl();',
    },
    'ruleExplore': <String, dynamic>{
      'bookList': '#list li.item',
      'name': 'a@text',
      'bookUrl': 'a@href',
    },
  }));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  setUp(() async {
    HttpOverrides.global = null;
    JsEngine.resetPoolForTest();
    ShuyuanExploreInfoStore.resetCacheForTest();
    ShuyuanExploreKindsStore.resetCacheForTest();
    _detailHits.clear();
    await _startServer();
  });

  tearDown(() => _server.close(force: true));

  test('preUpdateJs 修改 bookUrl 并 refreshTocUrl 后采用新 tocUrl', () async {
    final resolver = ShuyuanNovelResolver();
    final out = await resolver.resolve(
      _config(),
      'chapters',
      vars: <String, String>{'id': '$_base/book/1/'},
    );
    final list = (out as List).cast<dynamic>();
    expect(
      list.map((e) => (e as dynamic).title).toList(),
      <String>['第2章'],
    );
    // 详情页被重新解析一次（refreshTocUrl → getBookInfoAwait）。
    expect(_detailHits.length, greaterThanOrEqualTo(2));
    expect(_detailHits.any((q) => q.contains('v=2')), isTrue);
  });
}
