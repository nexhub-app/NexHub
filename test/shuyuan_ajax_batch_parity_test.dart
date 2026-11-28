/// java.ajax 批量族对等（审计 U25 / U26 / U37 / U24）：
/// - `ajax(List)` 取首元素；
/// - `ajaxAll` 任一项失败整批抛错；
/// - `ajaxTestAll` 逐项 timeout + isTest 负 callTime；
/// - 每次 ajaxAll 是独立批次（不合并并发窗口）；
/// - `org.jsoup.Jsoup.connect` 消费 timeout/followRedirects/maxBodySize/
///   ignoreHttpErrors 与表单编码。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  setUp(() {
    ShuyuanSourceContext.resetForTest();
  });

  test('ajax(List) 只取首元素，不把列表拼成字符串', () {
    final ctx = ShuyuanSourceContext('ajax_list')
      ..ajaxCache['https://x.com/first'] = 'FIRST';
    ShuyuanSourceContext.run(ctx, () {
      final e = JsEngine();
      expect(e.eval("java.ajax(['https://x.com/first','https://x.com/second'])"),
          'FIRST');
      expect(ctx.ajaxPending, isEmpty, reason: '第二个 URL 不应被登记请求');
    });
  });

  test('ajaxAll 任一项失败整批抛错（不返回部分结果）', () {
    final ctx = ShuyuanSourceContext('ajax_all_fail')
      ..ajaxCache['https://x.com/ok'] = 'OK'
      ..ajaxCache['https://x.com/bad'] = 'java.lang.Exception: boom'
      ..ajaxMetaCache['https://x.com/bad'] = jsonEncode(<String, dynamic>{
        'code': 0,
        'url': 'https://x.com/bad',
        'headers': const <String, List<String>>{},
        'e': true,
        'em': 'Failed host lookup: x.com',
      });
    ShuyuanSourceContext.run(ctx, () {
      final e = JsEngine();
      final out = e.eval("var r;"
          "try { r = java.ajaxAll(['https://x.com/ok','https://x.com/bad']);"
          " r = 'NO_THROW'; } catch (err) { r = 'CAUGHT:' + err.message; }"
          "r");
      expect(out, startsWith('CAUGHT:'));
      expect(out, contains('Failed host lookup'));
    });
  });

  test('两次 ajaxAll 记为两个独立批次', () {
    final ctx = ShuyuanSourceContext('ajax_batch_ids');
    ShuyuanSourceContext.run(ctx, () {
      final e = JsEngine();
      e.eval("java.ajaxAll(['https://x.com/a']);"
          "java.ajaxAll(['https://x.com/b'])");
      expect(ctx.ajaxBatchIds.length, 2);
      expect(ctx.ajaxBatchIds['https://x.com/a'], isNot(''),
          reason: '批编号不能为空');
      expect(ctx.ajaxBatchIds['https://x.com/a'],
          isNot(ctx.ajaxBatchIds['https://x.com/b']),
          reason: '两次 ajaxAll 不能合并成一个并发窗口');
    });
  });

  test('ajaxTestAll 连接失败返回负 callTime 且 code 仍为 200', () async {
    // 先占一个端口再关闭，拿到「连接被拒」的地址。
    final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close(force: true);
    final url = 'http://127.0.0.1:$port/none';
    final source = XiaoshuoBookSource.fromJson(<String, dynamic>{
      'bookSourceUrl': 'http://127.0.0.1:$port',
      'bookSourceName': 'test-all',
    });
    final ctx = ShuyuanSourceContext('ajax_test_all')..bindSource(source);
    await ShuyuanSourceContext.run(ctx, () async {
      final e = JsEngine();
      final first = e.eval("java.ajaxTestAll(['$url'], 1500)[0].callTime()");
      expect(int.parse(first), 0, reason: '首轮只有占位符，callTime 未定');
      await ShuyuanSourceContext.settleAjax(ctx, source,
          deadline: DateTime.now().add(const Duration(seconds: 10)));
      final second = e.eval("var r = java.ajaxTestAll(['$url'], 1500)[0];"
          "r.code() + '|' + String(r.callTime)");
      final parts = second.split('|');
      expect(parts.first, '200', reason: 'isTest 失败项 code 仍是 200');
      expect(int.parse(parts.last), lessThan(0),
          reason: 'isTest 失败项 callTime 为负错误码');
    });
  });

  test('Jsoup.connect 消费 maxBodySize / ignoreHttpErrors', () {
    final ctx = ShuyuanSourceContext('jsoup_opts');
    ShuyuanSourceContext.run(ctx, () {
      final e = JsEngine();
      // 首轮登记请求，拿到真实请求键（含选项串）。
      e.eval("org.jsoup.Jsoup.connect('https://x.com/big').execute()");
      final key = ctx.ajaxPending.first;
      ctx.ajaxCache[key] = '0123456789';
      ctx.ajaxMetaCache[key] = jsonEncode(<String, dynamic>{
        'code': 404,
        'url': 'https://x.com/big',
        'headers': const <String, List<String>>{},
      });
      // 重新建引擎以推送新增缓存（同引擎会按增量推送，这里直接用同一个也行）。
      final e2 = JsEngine();
      expect(
          e2.eval("org.jsoup.Jsoup.connect('https://x.com/big')"
              ".maxBodySize(4).ignoreHttpErrors(true).execute().body()"),
          '0123');
      final thrown = e2.eval("var r;"
          "try { org.jsoup.Jsoup.connect('https://x.com/big').get(); r = 'NO_THROW'; }"
          " catch (err) { r = 'CAUGHT:' + err.message; } r");
      expect(thrown, startsWith('CAUGHT:'));
      expect(thrown, contains('404'));
    });
  });

  test('Jsoup.connect 的 timeout / followRedirects 进入请求选项', () {
    final ctx = ShuyuanSourceContext('jsoup_timeout');
    ShuyuanSourceContext.run(ctx, () {
      final e = JsEngine();
      e.eval("org.jsoup.Jsoup.connect('https://x.com/t')"
          ".timeout(1234).followRedirects(false).execute()");
      final key = ctx.ajaxPending.first;
      expect(ctx.ajaxTimeouts[key], 1234);
      expect(key, contains('"followRedirects":false'));
    });
  });
}
