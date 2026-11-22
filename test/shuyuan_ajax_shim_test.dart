/// java.ajax 网络族 shim 测试（P1-3）：记录 + 占位符 + 缓存重放。
/// 含 loginCheck 协议（P2-1）：result 种子改写与透传。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  setUp(() {
    ShuyuanSourceContext.resetForTest();
  });

  test('ajax 首轮记录请求并返回占位符', () {
    final ctx = ShuyuanSourceContext('src_1');
    ShuyuanSourceContext.run(ctx, () {
      final e = JsEngine();
      final out = e.eval("java.ajax('https://x.com/token')");
      expect(RegExp(r'^__AJAX_\d+__$').hasMatch(out), true, reason: out);
      expect(ctx.ajaxPending, ['https://x.com/token']);
    });
  });

  test('缓存命中后 ajax 直出真响应（重放语义）', () {
    final ctx = ShuyuanSourceContext('src_1')..ajaxCache['https://x.com/a'] = 'BODY';
    ShuyuanSourceContext.run(ctx, () {
      final e = JsEngine();
      expect(e.eval("java.ajax('https://x.com/a')"), 'BODY');
      expect(ctx.ajaxPending, isEmpty, reason: '缓存命中不产生待抓取请求');
    });
  });

  test('connect 返回 StrResponse 形态对象（body()/code()）', () {
    final ctx = ShuyuanSourceContext('src_1')..ajaxCache['https://x.com/b'] = 'OK';
    ShuyuanSourceContext.run(ctx, () {
      final e = JsEngine();
      expect(e.eval("java.connect('https://x.com/b').body()"), 'OK');
      // 完成值经引擎规整为字符串。
      expect(e.eval("java.connect('https://x.com/b').code()"), '200');
    });
  });

  test('ajaxAll 批量记录并返回响应数组', () {
    final ctx = ShuyuanSourceContext('src_1')..ajaxCache['https://x.com/1'] = 'R1';
    ShuyuanSourceContext.run(ctx, () {
      final e = JsEngine();
      final out = e.eval(
          "r=java.ajaxAll(['https://x.com/1','https://x.com/2']); r[0].body() + '|' + r[1].body()");
      // 缓存命中的 x.com/1 不递增占位符编号（编号仅作占位标记）。
      expect(out, 'R1|__AJAX_1__');
      expect(ctx.ajaxPending, contains('https://x.com/2'));
    });
  });

  test('loginCheck 协议：result 种子可改写（code==500 判未登录）', () {
    final e = JsEngine();
    const status = 200;
    const body = '请先登录后再操作';
    final nl = String.fromCharCode(10);
    final wrapped = 'var result = {code: $status, body: ${jsonEncode(body)}};$nl'
        'JSON.stringify((function(){${nl}if (result.body.indexOf("登录") >= 0) '
        '{ result.code = 500; }${nl}return result;})())';
    final decoded = jsonDecode(e.eval(wrapped));
    expect(decoded['code'], 500);
  });

  test('loginCheck 协议：未改写时透传原状态码', () {
    final e = JsEngine();
    const status = 200;
    final nl = String.fromCharCode(10);
    final wrapped = 'var result = {code: $status, body: "normal"};$nl'
        'JSON.stringify((function(){${nl}return result;})())';
    final decoded = jsonDecode(e.eval(wrapped));
    expect(decoded['code'], 200);
  });

  test('post 记录组合键（url||POST||body），空 body 不降级为 GET', () {
    final ctx = ShuyuanSourceContext('src_1');
    ShuyuanSourceContext.run(ctx, () {
      final e = JsEngine();
      e.eval("java.post('https://x.com/p','a=1&b=2')");
      // java.post 走 legado Jsoup 口径：不跟随重定向（302 Location 是脚本
      // 要的答案），选项串在 POST 标记之前，且请求头按 headerMapF 替换。
      expect(ctx.ajaxPending, [
        'https://x.com/p,'
            '{"followRedirects":false,"_syHeaderMode":"replace"}'
            '||POST||a=1&b=2'
      ]);
      e.eval("java.post('https://x.com/p2','',{})");
      expect(ctx.ajaxPending.last,
          'https://x.com/p2,'
          '{"followRedirects":false,"_syHeaderMode":"replace"}||POST||');
    });
  });

  test('connect 的 header 参数（JSON 字符串）合进 URL 选项', () {
    final ctx = ShuyuanSourceContext('src_1');
    ShuyuanSourceContext.run(ctx, () {
      final e = JsEngine();
      e.eval("java.connect('https://x.com/a', "
          "JSON.stringify({'Referer':'https://r.example'}))");
      expect(ctx.ajaxPending, [
        'https://x.com/a,{"headers":{"Referer":"https://r.example"},'
            '"_syHeaderMode":"replace"}'
      ]);
    });
  });

  test('header 参数与 URL 选项 headers 合并（选项优先，legado 语义）', () {
    final ctx = ShuyuanSourceContext('src_1');
    ShuyuanSourceContext.run(ctx, () {
      final e = JsEngine();
      e.eval("java.connect('https://x.com/a,{\"headers\":{\"UA\":\"opt\"}}', "
          "JSON.stringify({UA:'arg',Ref:'r'}))");
      final key = ctx.ajaxPending.single;
      final opts = jsonDecode(key.substring(key.indexOf(',{') + 1)) as Map;
      expect(opts['headers'], {'UA': 'opt', 'Ref': 'r'});
    });
  });

  test('get(url, headers) 发送 headers 且不带重定向', () {
    final ctx = ShuyuanSourceContext('src_1');
    ShuyuanSourceContext.run(ctx, () {
      final e = JsEngine();
      e.eval("java.get('https://x.com/g', {'X-A':'1'})");
      final key = ctx.ajaxPending.single;
      final opts = jsonDecode(key.substring(key.indexOf(',{') + 1)) as Map;
      expect(opts['headers'], {'X-A': '1'});
      expect(opts['followRedirects'], false);
      expect(opts['_syHeaderMode'], 'replace');
    });
  });

  test('响应元数据重放：code/header/headers/cookies/url/raw', () {
    final ctx = ShuyuanSourceContext('src_1')
      ..ajaxCache['https://x.com/m'] = 'BODY'
      ..ajaxMetaCache['https://x.com/m'] = jsonEncode({
        'code': 302,
        'url': 'https://x.com/final',
        'headers': {
          'Location': ['https://x.com/next'],
          'Set-Cookie': ['sid=abc; Path=/', 'uid=7; Path=/'],
        },
      });
    ShuyuanSourceContext.run(ctx, () {
      final e = JsEngine();
      expect(e.eval("java.connect('https://x.com/m').code()"), '302');
      expect(e.eval("java.connect('https://x.com/m').header('Location')"),
          'https://x.com/next');
      expect(e.eval("java.connect('https://x.com/m').headers().get('location')"),
          'https://x.com/next');
      expect(e.eval("java.connect('https://x.com/m').url()"),
          'https://x.com/final');
      expect(e.eval("java.connect('https://x.com/m').raw().request().url()"),
          'https://x.com/final');
      expect(e.eval("String(java.connect('https://x.com/m').cookies())"),
          '{sid=abc, uid=7}');
    });
  });

  test('StrResponse.body 属性式读取（String(res.body)）取正文', () {
    final ctx = ShuyuanSourceContext('src_1')..ajaxCache['https://x.com/bp'] = 'TXT';
    ShuyuanSourceContext.run(ctx, () {
      final e = JsEngine();
      expect(e.eval("String(java.connect('https://x.com/bp').body)"), 'TXT');
    });
  });

  test('跨 eval 重放：首轮占位 → 暖缓存 → 二轮真数据', () {
    final ctx = ShuyuanSourceContext('src_1');
    ShuyuanSourceContext.run(ctx, () {
      final e = JsEngine();
      // 模拟顶点小说（优）搜索脚本形态（@js: 前缀由规则层剥离，此处为
      // 剥离后的脚本体）：ajax 取页面 → 正则提取 → 拼 URL。
      const script = "a=java.ajax('https://x.com/entry');\n"
          "tk=a.match(/token=([^&]+)/)[1];\n"
          "'https://x.com/search?tk='+tk;";
      // 首轮：ajax 返回占位符，下游 match 解析失败（脚本报错）——这正是
      // settle 循环的重试触发条件（异常 + 有未满足请求）。
      final pass1 = e.eval(script);
      expect(pass1, '');
      expect(ctx.ajaxPending, ['https://x.com/entry']);
      // 宿主 settle：抓取并暖缓存。
      ctx.ajaxCache['https://x.com/entry'] = 'xxxtoken=T99&yyy';
      ctx.ajaxPending.clear();
      // 重放（新 eval，同脚本——确定性重放）：ajax 直出真响应。
      final pass2 = e.eval(script);
      expect(pass2, 'https://x.com/search?tk=T99');
      expect(ctx.ajaxPending, isEmpty);
    });
  });
}
