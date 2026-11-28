/// P1 尾批测试：URL 级规则形态（itemContext 贯通）+ concurrentRate 限速。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_url.dart';
import 'package:nexhub/features/shuyuan/analyze/concurrent_rate_limiter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('AnalyzeUrl itemContext 贯通', () {
    test('{{\$.field}} 以搜索条目为求值根', () {
      final au = AnalyzeUrl(
        url: 'http://x.com/book?bid={{\$.bid}}&src={{\$.sourceId}}',
        itemContext: {'bid': 'B1', 'sourceId': 'S9'},
      );
      expect(au.url, 'http://x.com/book?bid=B1&src=S9');
    });

    test('嵌套字段 {{\$.data.bid}}', () {
      final au = AnalyzeUrl(
        url: 'http://x.com/toc?bid={{\$.data.bid}}',
        itemContext: {
          'data': {'bid': 'B7'},
        },
      );
      expect(au.url, 'http://x.com/toc?bid=B7');
    });

    test('无 itemContext 时规则形态按 JS 求值（未命中结果为空）', () {
      final au = AnalyzeUrl(url: 'http://x.com/toc?bid={{\$.bid}}');
      // `$` 在 JS 桥里已定义但无求值根 → 取不到值（空串），模板被展开。
      // 注意：真正的脚本异常会向上传播（见 AnalyzeUrl 模板 JS 求值口径）。
      expect(au.url.contains('{{'), false);
    });

    test('非规则形态仍走 JS（{{1+2}}）', () {
      final au = AnalyzeUrl(
        url: 'http://x.com/p={{1+2}}',
        itemContext: {'a': 1},
      );
      expect(au.url, 'http://x.com/p=3');
    });
  });

  group('AnalyzeUrl 页数备选写法 <a,b,c>', () {
    test('第 1 页取第 1 段（空段 → 无后缀路径）', () {
      final au = AnalyzeUrl(url: 'http://x.com/index<,_1>.html', page: 1);
      expect(au.url, 'http://x.com/index.html');
    });

    test('第 2 页取第 2 段', () {
      final au = AnalyzeUrl(url: 'http://x.com/index<,_1>.html', page: 2);
      expect(au.url, 'http://x.com/index_1.html');
    });

    test('超出段数取最后一段（legado clamp 语义）', () {
      final au = AnalyzeUrl(url: 'http://x.com/list<,_2,_3>.html', page: 9);
      expect(au.url, 'http://x.com/list_3.html');
    });

    test('多组备选同时展开', () {
      final au = AnalyzeUrl(
        url: 'http://x.com/a<,b><1,2>.html',
        page: 2,
      );
      expect(au.url, 'http://x.com/ab2.html');
    });

    test('<page> 字面量不被当作备选段', () {
      final au = AnalyzeUrl(url: 'http://x.com/list_<page>.html', page: 3);
      expect(au.url, 'http://x.com/list_3.html');
    });
  });

  group('concurrentRate 限速', () {
    test('空规则直接放行', () async {
      final sw = Stopwatch()..start();
      await ConcurrentRateLimiter.gate(null, 'k');
      await ConcurrentRateLimiter.gate('', 'k');
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(50));
    });

    test('"N" 形态：两次请求间隔 ≥ N ms', () async {
      final sw = Stopwatch()..start();
      await ConcurrentRateLimiter.gate('60', 'rate-src-n');
      await ConcurrentRateLimiter.gate('60', 'rate-src-n');
      sw.stop();
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(55));
    });

    test('"limit/interval" 形态：窗口内限流', () async {
      final sw = Stopwatch()..start();
      await ConcurrentRateLimiter.gate('3/100', 'rate-src-l');
      await ConcurrentRateLimiter.gate('3/100', 'rate-src-l');
      await ConcurrentRateLimiter.gate('3/100', 'rate-src-l');
      final thirdAt = sw.elapsedMilliseconds;
      await ConcurrentRateLimiter.gate('3/100', 'rate-src-l');
      sw.stop();
      // 第 4 次应等待到 100ms 窗口放行。
      expect(sw.elapsedMilliseconds - thirdAt, greaterThanOrEqualTo(50));
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(95));
    });

    test('不同源 key 互不影响', () async {
      final sw = Stopwatch()..start();
      await ConcurrentRateLimiter.gate('80', 'rate-a');
      await ConcurrentRateLimiter.gate('80', 'rate-b');
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(50));
    });

    test('并发等待者不一起放行（睡醒后重新判定）', () async {
      final sw = Stopwatch()..start();
      await Future.wait(<Future<void>>[
        for (var i = 0; i < 3; i++)
          ConcurrentRateLimiter.gate('1/80', 'rate-src-burst'),
      ]);
      sw.stop();
      // 1 次/80ms：3 次请求至少跨两个窗口（旧实现在 await 后无条件重置，
      // 3 个等待者会在同一时刻一起放行，总耗时只有一个窗口）。
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(150));
    });
  });

  group('AnalyzeUrl URL 选项 headers / followRedirects / HEAD', () {
    test('headers 字符串（单引号伪 JSON）并入 headerMap', () {
      final au = AnalyzeUrl(
        url: "http://x.com/s,{\"method\":\"POST\","
            "\"headers\":\"{Referer:'https://r.example'}\","
            "\"body\":\"kw=1\"}",
      );
      expect(au.headerMap['Referer'], 'https://r.example');
      expect(au.method, 'POST');
      expect(au.body, 'kw=1');
    });

    test('headers 对象并入 headerMap', () {
      final au = AnalyzeUrl(url: 'http://x.com/s,{"headers":{"X-A":"1"}}');
      expect(au.headerMap, {'X-A': '1'});
    });

    test('followRedirects:false 解析（java.get/post/head 的 Jsoup 口径）', () {
      final au = AnalyzeUrl(url: 'http://x.com/s,{"followRedirects":false}');
      expect(au.followRedirects, false);
    });

    test('method HEAD 解析', () {
      final au = AnalyzeUrl(
          url: 'http://x.com/s,{"method":"HEAD","followRedirects":false}');
      expect(au.method, 'HEAD');
      expect(au.followRedirects, false);
    });
  });
}
