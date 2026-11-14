/// 注入对象（cookie/source/book/cache）测试（P1-2）。
///
/// 语义对齐 legado：cookie=per-source 覆盖层（host 匹配）、source=书源
/// 变量与登录信息、book=书目变量、cache=会话缓存；读走种子、写走排空。
library;

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

  JsEngine engine() => JsEngine();

  test('cookie：setCookie/getCookie/getKey/removeCookie 往返', () {
    final ctx = ShuyuanSourceContext('src_1');
    ShuyuanSourceContext.run(ctx, () {
      final e = engine();
      final header = e.eval(
          "cookie.setCookie('https://a.com/x','k1=v1; k2=v2'); "
          "cookie.getCookie('https://a.com/')");
      expect(header, 'k1=v1; k2=v2');
      expect(e.eval("cookie.getKey('https://a.com/','k1')"), 'v1');
      // 覆盖层已写入宿主上下文（cookiesDirty 为瞬态标志，eval 末尾
      // persistIfNeeded 调度持久化后即清零，不断言）。
      expect(ctx.cookies['k1']?['value'], 'v1');
      e.eval("cookie.removeCookie('https://a.com/')");
      // ignore: avoid_print
      print('[诊断] remove后种子cookies=${e.eval('JSON.stringify(globalThis.__shuyuanCtx.cookies)')}');
      // ignore: avoid_print
      print('[诊断] remove后宿主覆盖层=${ctx.cookies}');
      expect(e.eval("cookie.getCookie('https://a.com/')"), '');
      expect(ctx.cookies, isEmpty);
    });
  });

  test('cookie 覆盖层 host 后缀匹配', () {
    final ctx = ShuyuanSourceContext('src_1');
    ctx.cookies['sid'] = {'value': 'xyz', 'host': 'a.com'};
    expect(ctx.cookiesForHost('www.a.com'), {'sid': 'xyz'});
    expect(ctx.cookiesForHost('a.com'), {'sid': 'xyz'});
    expect(ctx.cookiesForHost('other.com'), isEmpty);
  });

  test('source：getKey/变量读写/登录信息', () {
    final ctx = ShuyuanSourceContext('https://src.example.com');
    ShuyuanSourceContext.run(ctx, () {
      final e = engine();
      expect(e.eval('source.getKey()'), 'https://src.example.com');
      expect(
          e.eval("source.putVariable('tk','T1'); source.getVariable('tk')"),
          'T1');
      expect(ctx.sourceVars['tk'], 'T1');
      expect(e.eval("source.setVariable('{\"a\":1}'); source.getVariable(null)"),
          '{"a":1}');
      e.eval("source.putLoginInfo({'user':'u'}); "
          "source.putLoginHeader({'X-Auth':'x'}); "
          "source.getLoginHeaderMap()['X-Auth']");
      expect(ctx.loginInfo['user'], 'u');
      expect(ctx.loginHeader['X-Auth'], 'x');
    });
  });

  test('book：变量读写', () {
    final ctx = ShuyuanSourceContext('src_1');
    ShuyuanSourceContext.run(ctx, () {
      final e = engine();
      expect(e.eval("book.putVariable('bk','BV'); book.getVariable('bk')"),
          'BV');
      expect(ctx.bookVars['bk'], 'BV');
    });
  });

  test('cache：put/get/delete 会话连续', () {
    final ctx = ShuyuanSourceContext('src_1');
    ShuyuanSourceContext.run(ctx, () {
      final e = engine();
      expect(e.eval("cache.put('c','9'); cache.get('c')"), '9');
    });
    // 同一上下文、新一轮 eval：会话缓存连续（种子携带）。
    ShuyuanSourceContext.run(ctx, () {
      final e = engine();
      expect(e.eval("cache.get('c')"), '9');
      expect(e.eval("cache.delete('c'); cache.get('c')"), '');
    });
  });

  test('无活动上下文时不注入种子（对既有脚本零影响）', () {
    final e = engine();
    expect(e.eval('typeof cookie'), 'object'); // 预置对象恒存在
    expect(e.eval('cookie.getCookie("https://a.com/")'), '');
  });
}
