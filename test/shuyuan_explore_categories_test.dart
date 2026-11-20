/// 发现页分类局限收口：
/// - legado `loadableExploreMainKinds` 对 (title, url) 去重（重复声明只出一个 Tab）；
/// - 无 category 的 latest/explore 入口不再死守首个分类：首个分类失效或为空时
///   继续尝试后续分类（有上限），避免首页直接空列表。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/features/shuyuan/analyze/webview_fetcher.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';
import 'package:nexhub/features/shuyuan/presentation/shuyuan_novel_resolver.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';
import 'package:nexhub/features/shuyuan/web_book/web_book.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _listHtml = '''
<ul id="list">
  <li class="item"><a href="/book/Alpha.html">Alpha</a></li>
</ul>''';

late HttpServer _server;
late String _base;
final Map<String, int> _hits = <String, int>{};

Future<void> _startServer() async {
  _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  _base = 'http://${_server.address.host}:${_server.port}';
  _server.listen((req) {
    final path = req.uri.path;
    _hits[path] = (_hits[path] ?? 0) + 1;
    final body = switch (path) {
      '/empty' => '',
      '/ok' => _listHtml,
      '/ok2' => _listHtml,
      _ => null,
    };
    req.response
      ..statusCode = body == null ? 404 : 200
      ..headers.contentType = ContentType.html
      ..write(body ?? '');
    req.response.close();
  });
}

Future<int> _deadPort() async {
  final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final port = probe.port;
  await probe.close(force: true);
  return port;
}

PluginConfig _config(String exploreUrl) {
  return ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(<String, dynamic>{
    'bookSourceName': '本地发现分类测试源',
    'bookSourceUrl': '$_base/',
    'bookSourceType': 0,
    'enabled': true,
    'exploreUrl': exploreUrl,
    'ruleExplore': <String, dynamic>{
      'bookList': '#list li.item',
      'name': 'a@text',
      'bookUrl': 'a@href',
    },
  }));
}

XiaoshuoBookSource _bookSource(String exploreUrl) {
  return XiaoshuoBookSource.fromJson(<String, dynamic>{
    'bookSourceName': 'dedupe-test',
    'bookSourceUrl': 'https://dedupe.test',
    'bookSourceType': 0,
    'exploreUrl': exploreUrl,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  setUp(() async {
    // flutter_test 默认把所有 HttpClient 替换成返回 400 的 mock；发现链路
    // 走真实 dart:io 网络，需要恢复真实实现（同 debug_source_probe_test 范式）。
    HttpOverrides.global = null;
    _hits.clear();
    await _startServer();
  });

  tearDown(() => _server.close(force: true));

  group('发现分类 (title, url) 去重（legado loadableExploreMainKinds）', () {
    test('重复声明只保留一个分类；同名不同 URL 保留', () {
      final categories = WebBook().getExploreCategories(_bookSource(
        '玄幻::/a&&玄幻::/a&&修真::/a&&修真::/b',
      ));
      expect(categories.map((c) => '${c.name}|${c.url}').toList(), <String>[
        '玄幻|/a',
        '修真|/a',
        '修真|/b',
      ]);
    });
  });

  group('无 category 的发现入口', () {
    test('首个分类不可达时继续尝试后续分类，取首个非空结果', () async {
      final deadPort = await _deadPort();
      final cfg = _config(
        '分类一::http://127.0.0.1:$deadPort/dead\n'
        '分类二::$_base/empty\n'
        '分类三::$_base/ok\n'
        '分类四::$_base/ok2',
      );
      final result = await ShuyuanNovelResolver()
          .resolve(cfg, 'explore', vars: <String, String>{'page': '1'});
      final items = (result as List).cast<dynamic>();
      expect(items.length, 1);
      // 拿到首个非空分类即停：后续分类不应被串行抓取。
      expect(_hits['/empty'], 1);
      expect(_hits['/ok'], 1);
      expect(_hits['/ok2'], isNull);
    });

    test('所有分类都失败时仍抛出首个错误（保留验证/网络诊断）', () async {
      final deadPort = await _deadPort();
      final cfg = _config('分类一::http://127.0.0.1:$deadPort/dead');
      await expectLater(
        ShuyuanNovelResolver()
            .resolve(cfg, 'explore', vars: <String, String>{'page': '1'}),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('java.webView 生成的发现分类', () {
    test('首轮占位符经宿主重放后解析出分类', () async {
      final seenUrls = <String>[];
      ShuyuanWebviewFetcher.debugFetchOverride = ({
        String? html,
        String? url,
        String? js,
        int delayMs = 0,
        Map<String, String>? headers,
      }) async {
        seenUrls.add(url ?? '');
        return ShuyuanWebviewResult(
          html: '[{"title":"电影","url":"/film"},'
              '{"title":"剧集","url":"/tv"}]',
          finalUrl: url ?? '',
        );
      };
      addTearDown(() => ShuyuanWebviewFetcher.debugFetchOverride = null);

      final cfg = _config("@js:java.webView('', baseUrl + '/cats', '')");
      final entries =
          await ShuyuanNovelResolver().resolveExploreCategories(cfg);
      expect(
        entries.map((e) => '${e.title}|${e.id}').toList(),
        <String>['电影|/film', '剧集|/tv'],
      );
      expect(seenUrls, hasLength(1));
      expect(seenUrls.single, contains('/cats'));
    });
  });
}
