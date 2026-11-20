/// 交互式重放协议：startBrowserAwait / getVerificationCode / startBrowser 的
/// JS 侧首轮登记、缓存命中、缓存增量推送。全部合成绑定，不访问网络。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});
  setUp(ShuyuanSourceContext.resetForTest);

  test('startBrowserAwait 首轮登记 op 并返回空响应壳', () {
    final ctx = ShuyuanSourceContext('src_ba');
    ShuyuanSourceContext.run(ctx, () {
      final out = JsEngine().eval(
          'var r = java.startBrowserAwait("https://login.test/", "登录");'
          'r.body() + "|" + r.code() + "|" + r.url();');
      expect(out, '|0|');
      expect(ctx.browserAwaitPending, hasLength(1));
      final key = ctx.browserAwaitPending.single;
      expect(ctx.browserAwaitArgs[key], <String>[
        'https://login.test/',
        '登录',
        '1',
        '',
      ]);
    });
  });

  test('startBrowserAwait 缓存命中时返回 body/code/url/header', () {
    final ctx = ShuyuanSourceContext('src_ba_hit');
    ShuyuanSourceContext.run(ctx, () {
      final engine = JsEngine();
      final first = engine.eval(
          'var r = java.startBrowserAwait("https://login.test/", "登录");'
          'r.body();');
      expect(first, '');
      final key = ctx.browserAwaitPending.single;
      ctx.browserAwaitCache[key] =
          '{"body":"<div>ok</div>","code":200,"url":"https://login.test/home",'
          '"headers":{"content-type":["text/html"]}}';
      final second = engine.eval(
          'var r = java.startBrowserAwait("https://login.test/", "登录");'
          'r.body() + "|" + r.code() + "|" + r.url() + "|" +'
          'r.header("Content-Type");');
      expect(second, '<div>ok</div>|200|https://login.test/home|text/html');
    });
  });

  test('startBrowser 登记 html，refetch=false 进入 args', () {
    final ctx = ShuyuanSourceContext('src_open');
    ShuyuanSourceContext.run(ctx, () {
      JsEngine().eval(
          'java.startBrowser("https://login.test/", "登录", "<html></html>");'
          'var r = java.startBrowserAwait("https://login.test/", "登录", false);'
          'r.body();');
    });
    expect(ctx.kindBrowserOpens.single,
        <String, String>{'url': 'https://login.test/', 'title': '登录', 'html': '<html></html>'});
    expect(ctx.browserAwaitArgs.values.single[2], '0');
  });

  test('getVerificationCode 首轮空串，缓存后重放返回输入值', () {
    final ctx = ShuyuanSourceContext('src_vc');
    ShuyuanSourceContext.run(ctx, () {
      final engine = JsEngine();
      expect(
          engine.eval('java.getVerificationCode("https://img.test/c.png");'),
          '');
      final key = ctx.verificationPending.single;
      expect(ctx.verificationArgs[key], 'https://img.test/c.png');
      ctx.verificationCodeCache[key] = 'A1B2';
      expect(
          engine.eval('java.getVerificationCode("https://img.test/c.png");'),
          'A1B2');
    });
  });

  test('syncCookies 只写覆盖层，refreshCookiesFromStore 读到别处落盘', () async {
    final writer = ShuyuanSourceContext('src_cookie_sync');
    writer.syncCookies('login.test', 'sid=abc; theme=dark');
    expect(writer.cookies['sid']?['host'], 'login.test');
    expect(writer.cookiesDirty, isTrue);
    await writer.persistIfNeeded();

    final reader = ShuyuanSourceContext('src_cookie_sync');
    expect(reader.cookies, isEmpty);
    await reader.refreshCookiesFromStore();
    expect(reader.cookiesForHost('login.test')['sid'], 'abc');
    expect(reader.cookiesForHost('sub.login.test')['theme'], 'dark');
  });
}
