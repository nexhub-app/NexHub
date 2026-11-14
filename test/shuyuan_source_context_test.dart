/// 注入对象（cookie/source/book/cache）测试（P1-2）。
///
/// 语义对齐 legado：cookie=per-source 覆盖层（host 匹配）、source=书源
/// 变量与登录信息、book=书目变量、cache=会话缓存；读走种子、写走排空。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/concurrent_rate_limiter.dart';
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

  // ── 作用域不变量：必须跨 await 存活（旧实现静态栈在首个 await 后即 pop，
  //    导致 JS 种子/排空、cookie 覆盖层、登录头、bookItemContext 全部失效）──
  group('作用域 run()', () {
    test('跨 await 仍然可见，结束后清理', () async {
      final ctx = ShuyuanSourceContext('scope-test');

      final seen = await ShuyuanSourceContext.run(ctx, () async {
        await Future<void>.delayed(Duration.zero);
        return ShuyuanSourceContext.current;
      });

      expect(seen, same(ctx));
      expect(ShuyuanSourceContext.current, isNull);
    });

    test('JS 求值在 await 之后仍能读到种子', () async {
      final ctx = ShuyuanSourceContext('scope-async');
      ctx.loginInfo['user'] = 'u1';

      final value = await ShuyuanSourceContext.run(ctx, () async {
        await Future<void>.delayed(Duration.zero);
        return engine().eval('source.getLoginInfoMap().user');
      });

      expect(value, 'u1');
    });

    test('并发不同源互不串上下文', () async {
      final a = ShuyuanSourceContext('source-a');
      final b = ShuyuanSourceContext('source-b');

      final results = await Future.wait(<Future<String?>>[
        ShuyuanSourceContext.run(a, () async {
          await Future<void>.delayed(const Duration(milliseconds: 8));
          return ShuyuanSourceContext.current?.sourceId;
        }),
        ShuyuanSourceContext.run(b, () async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
          return ShuyuanSourceContext.current?.sourceId;
        }),
      ]);

      expect(results, <String>['source-a', 'source-b']);
    });
  });

  group('cookie host 匹配（domain-match）', () {
    test('同域 / 子域命中', () {
      expect(
          ShuyuanSourceContext.hostMatches('example.com', 'example.com'), isTrue);
      expect(ShuyuanSourceContext.hostMatches('example.com', 'm.example.com'),
          isTrue);
    });

    test('父域不下发（子域 cookie 不能发给父域）', () {
      expect(ShuyuanSourceContext.hostMatches('m.example.com', 'example.com'),
          isFalse);
    });

    test('仿冒域不命中（旧实现的裸后缀匹配会命中）', () {
      expect(
          ShuyuanSourceContext.hostMatches('example.com', 'evil-example.com'),
          isFalse);
      expect(ShuyuanSourceContext.hostMatches('example.com', 'notexample.com'),
          isFalse);
      expect(ShuyuanSourceContext.hostMatches('e.com', 'evil.com'), isFalse);
    });

    test('空 host 视为全局', () {
      expect(ShuyuanSourceContext.hostMatches('', 'example.com'), isTrue);
      expect(ShuyuanSourceContext.hostMatches('example.com', ''), isTrue);
    });

    test('覆盖层按 domain-match 合并', () {
      final ctx = ShuyuanSourceContext('src_host');
      ctx.cookies['sid'] = {'value': 'v', 'host': 'a.com'};
      expect(ctx.cookiesForHost('www.a.com'), {'sid': 'v'});
      expect(ctx.cookiesForHost('a.com'), {'sid': 'v'});
      expect(ctx.cookiesForHost('nota.com'), isEmpty);
      expect(ctx.cookiesForHost('evil-a.com'), isEmpty);
    });
  });

  // ── java.ajax 的确定性重放：宿主抓到的响应经增量推送进 JS 全局缓存，
  //    重放时命中直出；缓存不随每轮 ctx 种子重灌（长目录 O(n²) 的根因）──
  group('ajax 重放缓存', () {
    test('增量推送后命中，重置后回到占位符', () {
      final e = engine();
      final ctx = ShuyuanSourceContext('ajax-test');
      ctx.ajaxCache['https://x.test/a'] = 'HELLO';

      ShuyuanSourceContext.run(ctx, () {
        expect(e.eval("java.ajax('https://x.test/a')"), 'HELLO');
      });

      ctx.ajaxCache['https://x.test/b'] = 'WORLD';
      ShuyuanSourceContext.run(ctx, () {
        expect(
            e.eval("java.ajax('https://x.test/a') + java.ajax('https://x.test/b')"),
            'HELLOWORLD');
      });

      e.resetReplayCaches();
      // 重置是成对的：JS 全局 + 宿主表一起清（与 resolver 阶段开始一致）。
      ctx.ajaxCache.clear();
      ShuyuanSourceContext.run(ctx, () {
        ctx.ajaxPending.clear();
        final out = e.eval("java.ajax('https://x.test/a')");
        expect(out.startsWith('__AJAX_'), isTrue);
        expect(ctx.ajaxPending, contains('https://x.test/a'));
      });
    });

    test('缓存不写入 __shuyuanCtx 种子（避免每轮整表序列化）', () {
      final e = engine();
      final ctx = ShuyuanSourceContext('ajax-seed-test');
      ctx.ajaxCache['https://x.test/big'] = 'x' * 4096;

      ShuyuanSourceContext.run(ctx, () {
        expect(e.eval('JSON.stringify(__shuyuanCtx.ajaxCache === undefined)'),
            'true');
        expect(e.eval("java.ajax('https://x.test/big').length"), '4096');
      });
    });
  });

  // ── 阶段级页面缓存：settle 重放复用同一页，容量按字符数封顶 ──
  group('阶段缓存', () {
    test('页面缓存超容量按插入序淘汰最旧', () {
      final ctx = ShuyuanSourceContext('pc-test');
      final big = 'x' * (1024 * 1024); // 复用同一实例，不额外占内存
      for (var i = 0; i < 5; i++) {
        ctx.pageCachePut('k$i', big);
      }
      expect(ctx.pageCache.containsKey('k0'), isFalse);
      expect(ctx.pageCache.containsKey('k4'), isTrue);
    });

    test('clearStageCaches 同时清页面 / ajax / 待抓取队列', () {
      final ctx = ShuyuanSourceContext('pc-test2');
      ctx.pageCachePut('k', 'v');
      ctx.ajaxCache['a'] = 'b';
      ctx.ajaxPending.add('a');

      ctx.clearStageCaches();

      expect(ctx.pageCache, isEmpty);
      expect(ctx.ajaxCache, isEmpty);
      expect(ctx.ajaxPending, isEmpty);
    });

    test('超大单页不缓存', () {
      final ctx = ShuyuanSourceContext('pc-test3');
      ctx.pageCachePut('huge', 'y' * (4 * 1024 * 1024 + 1));
      expect(ctx.pageCache, isEmpty);
    });
  });

  group('cacheFile / readTxtFile', () {
    test('首轮占位 + 待抓取，缓存回填后读出内容', () {
      final e = engine();
      final ctx = ShuyuanSourceContext('cf-test');
      const js = "java.readTxtFile(java.cacheFile('https://x.test/sign.js'))";

      ShuyuanSourceContext.run(ctx, () {
        final first = e.eval(js);
        expect(first.startsWith('__AJAX_'), isTrue);
        expect(ctx.ajaxPending, contains('https://x.test/js'));

        // 模拟宿主抓取
        ctx.ajaxCache['https://x.test/sign.js'] = 'var a=1;';
        expect(e.eval(js), 'var a=1;');
      });
    });

    test('直接传 URL 也能按内容抓取', () {
      final e = engine();
      final ctx = ShuyuanSourceContext('cf-url');
      ShuyuanSourceContext.run(ctx, () {
        ctx.ajaxCache['https://x.test/direct.js'] = 'console.log(1);';
        expect(e.eval("java.readTxtFile('https://x.test/direct.js')"),
            'console.log(1);');
      });
    });
  });

  group('java.webView 重放', () {
    test('首轮占位 + 记录待取源，宿主回填后命中', () {
      final e = engine();
      final ctx = ShuyuanSourceContext('wv-test');

      ShuyuanSourceContext.run(ctx, () {
        final first =
            e.eval("java.webView('', 'https://x.test/a', 'document.title')");
        expect(first.startsWith('__WEBVIEW_'), isTrue);
        expect(ctx.webviewPending, hasLength(1));
        expect(ctx.webviewArgs.values.first[1], 'https://x.test/a');

        // 模拟宿主无头取源完成
        ctx.webviewCache[ctx.webviewPending.first] = '<html>OK</html>';
        expect(
            e.eval("java.webView('', 'https://x.test/a', 'document.title')"),
            '<html>OK</html>');
      });
    });

    test('空参数返回空串，不记录请求', () {
      final e = engine();
      final ctx = ShuyuanSourceContext('wv-empty');
      ShuyuanSourceContext.run(ctx, () {
        expect(e.eval("java.webView('', '', '')"), '');
        expect(ctx.webviewPending, isEmpty);
      });
    });
  });

  group('concurrentRate 限速', () {    test('单值速率：连续两次请求按间隔等待', () async {
      const key = 'unit-test-rate-source';
      final sw = Stopwatch()..start();
      await ConcurrentRateLimiter.gate('80', key);
      await ConcurrentRateLimiter.gate('80', key);
      sw.stop();
      // 定时器精度与 CI 负载留余量，断言放宽到 50ms。
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(50));
    });

    test('未声明或非法速率直接放行', () async {
      final sw = Stopwatch()..start();
      await ConcurrentRateLimiter.gate(null, 'k1');
      await ConcurrentRateLimiter.gate('', 'k2');
      await ConcurrentRateLimiter.gate('abc', 'k3');
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(50));
    });
  });
}
