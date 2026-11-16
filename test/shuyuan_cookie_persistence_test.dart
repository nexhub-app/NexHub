/// 响应 Set-Cookie 的按源持久化与回放（legado OkHttp CookieManager 对等）：
/// 服务端在首个 API 响应里下发会话 cookie，后续请求不带该 cookie 即返回空
/// 数据。引擎必须把 Set-Cookie 写进 per-source 覆盖层，并在同阶段 settle
/// 重放与跨阶段（分类/详情）请求里自动回放，否则发现页/分类页列表为空。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/presentation/shuyuan_novel_resolver.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';

String _exploreScript(String local) => '''
@js:(function(){
  var tags = JSON.parse(java.ajax('$local/api/tags'));
  var list = JSON.parse(java.ajax('$local/api/list'));
  var cats = [{"title":"全部","url":"$local/api/list"}];
  for (var i = 0; i < tags.groups.length; i++) {
    cats.push({"title": tags.groups[i], "url": "$local/api/list?tag=" + tags.groups[i]});
  }
  if (list.books.length > 0) {
    cats.push({"title": list.books[0].title, "url": "$local/api/list"});
  }
  return JSON.stringify(cats);
})()
''';

PluginConfig _source(String local) =>
    ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(<String, dynamic>{
      'bookSourceName': 'Cookie测试源',
      'bookSourceUrl': local,
      'bookSourceType': 0,
      'enabled': true,
      'header': '{"User-Agent":"Mozilla/5.0 (Linux; Android 13)"}',
      'exploreUrl': _exploreScript(local),
      'ruleExplore': <String, dynamic>{
        'bookList': r'$.books[*]',
        'name': r'$.title',
        'bookUrl': r'$.url',
      },
    }));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ShuyuanSourceContext.resetForTest();
    JsEngine.resetPoolForTest();
  });

  tearDown(() {
    JsEngine.resetPoolForTest();
  });

  group('applyResponseCookies（Set-Cookie 解析）', () {
    test('Domain 属性优先并去前导点；缺省落在请求 host', () {
      final ctx = ShuyuanSourceContext('cookie-unit');
      ctx.applyResponseCookies(
        'https://a.example.com/page',
        <String>['sid=1; Domain=.Example.com; Path=/; Max-Age=3600'],
      );
      ctx.applyResponseCookies(
        'https://a.example.com/page',
        <String>['token=abc; Path=/'],
      );

      expect(ctx.cookies['sid']!['host'], 'example.com');
      expect(ctx.cookies['token']!['host'], 'a.example.com');
      expect(ctx.cookiesForHost('sub.example.com'), containsPair('sid', '1'));
      // 无 Domain 的 cookie 不外泄给非域匹配 host。
      expect(ctx.cookiesForHost('unrelated.test'), isEmpty);
    });

    test('同名后到者覆盖，Max-Age<=0 删除', () {
      final ctx = ShuyuanSourceContext('cookie-unit');
      ctx.applyResponseCookies(
          'https://site.test/', <String>['sid=old; Path=/']);
      ctx.applyResponseCookies(
          'https://site.test/', <String>['sid=new; Path=/']);
      expect(ctx.cookiesForHost('site.test'), containsPair('sid', 'new'));

      ctx.applyResponseCookies(
          'https://site.test/', <String>['sid=; Max-Age=0; Path=/']);
      expect(ctx.cookiesForHost('site.test'), isEmpty);
    });
  });

  test('发现→分类跨阶段回放服务端下发的会话 cookie', () async {
    final listCookies = <String?>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final local = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      final path = req.uri.path;
      if (path == '/api/tags') {
        req.response.headers.contentType =
            ContentType('application', 'json', charset: 'utf-8');
        // 持久 cookie + 会话 cookie（无 Max-Age）：两者都必须回放。
        req.response.headers
            .add('set-cookie', 'sid=ok; Path=/; Max-Age=3600');
        req.response.headers.add('set-cookie', 'vsid=xyz; Path=/');
        req.response.write(jsonEncode(<String, dynamic>{
          'groups': <String>['groupA'],
        }));
      } else if (path == '/api/list') {
        final cookie = req.headers.value('cookie');
        listCookies.add(cookie);
        req.response.headers.contentType =
            ContentType('application', 'json', charset: 'utf-8');
        final authed = cookie != null && cookie.contains('sid=ok');
        req.response.write(jsonEncode(<String, dynamic>{
          'books': authed
              ? <dynamic>[
                  <String, dynamic>{'title': '条目一', 'url': '$local/book/1'},
                  <String, dynamic>{'title': '条目二', 'url': '$local/book/2'},
                ]
              : <dynamic>[],
        }));
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });

    try {
      final cfg = _source(local);
      final resolver = ShuyuanNovelResolver();

      // 发现页：脚本内两次 java.ajax——第二次（列表）依赖第一次（标签）响应
      // 下发的 cookie，同阶段 settle 回放必须生效。
      final entries = await resolver.resolveExploreCategories(cfg);
      expect(entries.map((e) => e.title), contains('全部'));
      // 第二次调用拿到了数据（标题来自列表接口）。
      expect(entries.map((e) => e.title), contains('条目一'));
      expect(listCookies.first, contains('sid=ok'));

      // 分类页：独立阶段请求，必须带上上一阶段服务端下发的 cookie。
      final items = await resolver.resolve(
        cfg,
        'explore',
        vars: <String, String>{'category': '$local/api/list', 'page': '1'},
      );
      expect(items, isA<List<dynamic>>());
      expect((items as List).length, 2);

      expect(listCookies, isNotEmpty);
      expect(listCookies.last, contains('sid=ok'));
      expect(listCookies.last, contains('vsid=xyz'));
    } finally {
      await server.close(force: true);
    }
  });
}
