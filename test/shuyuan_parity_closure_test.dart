/// 书源引擎残余能力面回归：
/// - okhttp3 垫片的 PUT/DELETE/PATCH 与二进制 RequestBody（不再降级 GET /
///   不再按 UTF-8 解码破坏密文）；
/// - java.util.Set 去重语义（HashSet/LinkedHashSet/Set 不再等同 ArrayList）；
/// - `cache.put(key, byte[])` 与 `getByteArray` 的二进制缓存表；
/// - XPath 未知谓词不再默认放行（无等价求值时按不匹配处理）。
/// 全部为合成向量与本地 HTTP，不访问真实站点。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexhub/features/shuyuan/analyze/analyze_url.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_xpath.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';

class _Echo {
  String method = '';
  String path = '';
  List<int> body = const <int>[];
}

Future<HttpServer> _startEcho(_Echo echo) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    echo.method = req.method;
    echo.path = req.uri.path;
    final chunks = <int>[];
    await for (final part in req) {
      chunks.addAll(part);
    }
    echo.body = chunks;
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write('ok');
    await req.response.close();
  });
  return server;
}

String _origin(HttpServer server) =>
    'http://${server.address.address}:${server.port}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ShuyuanSourceContext.resetForTest();
  });

  group('okhttp3 方法与二进制请求体', () {
    test('PUT/DELETE/PATCH 按原方法发出，不再降级 GET', () async {
      final echo = _Echo();
      final server = await _startEcho(echo);
      try {
        final o = _origin(server);
        final put = AnalyzeUrl(
          url: '$o/api,{"method":"PUT","body":"a=1&b=2"}',
          baseUrl: o,
        );
        expect(await put.getStrResponse(), 'ok');
        expect(echo.method, 'PUT');
        expect(echo.path, '/api');
        expect(utf8.decode(echo.body), 'a=1&b=2');

        final del = AnalyzeUrl(url: '$o/gone,{"method":"DELETE"}', baseUrl: o);
        expect(await del.getStrResponse(), 'ok');
        expect(echo.method, 'DELETE');
        expect(echo.body, isEmpty);

        final patch = AnalyzeUrl(
          url: '$o/p,{"method":"PATCH","body":"{\\"n\\":1}"}',
          baseUrl: o,
        );
        expect(await patch.getStrResponse(), 'ok');
        expect(echo.method, 'PATCH');
        expect(utf8.decode(echo.body), '{"n":1}');
      } finally {
        await server.close(force: true);
      }
    });

    test('二进制请求体按原始字节发送（不经 UTF-8 解码回编码）', () async {
      final echo = _Echo();
      final server = await _startEcho(echo);
      try {
        final o = _origin(server);
        const raw = <int>[0, 1, 255, 254, 65, 0];
        final au = AnalyzeUrl(
          url: '$o/bin,{"method":"PUT","_syBodyB64":"${base64Encode(raw)}"}',
          baseUrl: o,
        );
        expect(await au.getStrResponse(), 'ok');
        expect(echo.method, 'PUT');
        expect(echo.body, raw);
      } finally {
        await server.close(force: true);
      }
    });

    test('垫片 PUT 写入 method 选项，二进制体走 base64 通道', () {
      final ctx = ShuyuanSourceContext('src_okhttp_methods');
      ShuyuanSourceContext.run(ctx, () {
        final e = JsEngine();
        e.eval('''
(function(){
  var b = Packages.okhttp3.RequestBody.create("k=v",
      Packages.okhttp3.MediaType.parse("text/plain"));
  var r = new Packages.okhttp3.Request.Builder()
      .url("https://x.test/api").addHeader("X-A","1").put(b).build();
  new Packages.okhttp3.OkHttpClient().newCall(r).execute();
})()''');
        final textKey = ctx.ajaxPending.last;
        expect(textKey, contains('"method":"PUT"'));
        expect(textKey, contains('"body":"k=v"'));
        expect(textKey, isNot(contains('||POST||')));

        e.eval('''
(function(){
  var b = Packages.okhttp3.RequestBody.create(
      Packages.okhttp3.MediaType.parse("application/octet-stream"),
      [0, 1, 255]);
  var r = new Packages.okhttp3.Request.Builder()
      .url("https://x.test/bin").delete(b).build();
  new Packages.okhttp3.OkHttpClient().newCall(r).execute();
})()''');
        final binKey = ctx.ajaxPending.last;
        expect(binKey, contains('"method":"DELETE"'));
        expect(binKey, contains('"_syBodyB64":"${base64Encode(<int>[0, 1, 255])}"'));
        expect(binKey, isNot(contains('"body"')));
      });
    });
  });

  group('java.util.Set 去重语义', () {
    test('HashSet add/contains/remove/iterator 按集合语义', () {
      final e = JsEngine();
      expect(
          e.eval('''
(function(){
  var s = new Packages.java.util.HashSet();
  var a = s.add("x"), b = s.add("x"), c = s.add("y");
  var it = s.iterator(); var walked = [];
  while (it.hasNext()) walked.push(it.next());
  return [a, b, c, s.size(), s.contains("y"), s.remove("x"),
      s.size(), walked.join(","), String(s)].join("|");
})()'''),
          'true|false|true|2|true|true|1|x,y|[y]');
    });

    test('LinkedHashSet 保序、addAll 去重、Set 别名同类', () {
      final e = JsEngine();
      expect(
          e.eval('''
(function(){
  var s = new Packages.java.util.LinkedHashSet();
  s.addAll(["b","a","b"]);
  var t = new Packages.java.util.Set();
  t.add(1); t.add(1);
  return [String(s), s.size(), t.size(),
      String(Packages.java.util.HashSet.getName())].join("|");
})()'''),
          '[b, a]|2|1|java.util.HashSet');
    });

    test('ArrayList 仍允许重复（避免把列表一并去重）', () {
      final e = JsEngine();
      expect(
          e.eval('''
(function(){
  var l = new Packages.java.util.ArrayList();
  l.add("x"); l.add("x");
  return l.size();
})()'''),
          '2');
    });
  });

  group('cache 二进制条目', () {
    test('put(byte[]) → getByteArray 有符号字节，get 取不到文本', () {
      final ctx = ShuyuanSourceContext('src_cache_bytes');
      ShuyuanSourceContext.run(ctx, () {
        final e = JsEngine();
        e.eval('cache.put("bin", [0, 1, 255]);');
        expect(ctx.cacheBytes['bin'], base64Encode(<int>[0, 1, 255]));
        expect(ctx.cache.containsKey('bin'), isFalse);
        expect(ctx.toSeed()['cacheBytes'], containsPair('bin', base64Encode(<int>[0, 1, 255])));

        final out = e.eval('''
(function(){
  var b = cache.getByteArray("bin");
  return [b.length, b[0], b[1], b[2], cache.get("bin") === null,
      cache.getByteArray("missing") === null].join("|");
})()''');
        expect(out, '3|0|1|-1|true|true');
      });
    });

    test('文本 put 覆盖字节条目，delete 同时清两表', () {
      final ctx = ShuyuanSourceContext('src_cache_bytes_mix');
      ShuyuanSourceContext.run(ctx, () {
        final e = JsEngine();
        e.eval('cache.put("k", [1, 2]);');
        expect(ctx.cacheBytes.containsKey('k'), isTrue);
        e.eval('cache.put("k", "text");');
        expect(ctx.cacheBytes.containsKey('k'), isFalse);
        expect(ctx.cache['k'], 'text');
        expect(e.eval('cache.get("k")'), 'text');

        e.eval('cache.put("b2", [3]);');
        e.eval('cache.delete("b2");');
        expect(ctx.cacheBytes.containsKey('b2'), isFalse);
        expect(e.eval('cache.getByteArray("b2") === null'), 'true');
      });
    });
  });

  group('XPath 谓词不静默放行', () {
    const html = '<ul><li class="item">一</li><li class="item">二</li>'
        '<li class="item x">三</li></ul>';

    test('无等价求值的谓词按不匹配处理', () {
      final a = AnalyzeByXPath(html);
      expect(a.getStringList('//li[matches(@class,"item")]'), isEmpty);
    });

    test('受支持谓词仍正常过滤（回归锁）', () {
      final a = AnalyzeByXPath(html);
      expect(a.getStringList('//li[contains(@class,"x")]'), ['三']);
      expect(a.getStringList('//li[@class="item"]'), ['一', '二']);
      expect(a.getStringList('//li[2]'), ['二']);
    });
  });
}
