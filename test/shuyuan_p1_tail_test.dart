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

    test('无 itemContext 时规则形态按 JS 求值（legado 行为，容错为空）', () {
      final au = AnalyzeUrl(url: 'http://x.com/toc?bid={{\$.bid}}');
      // JS 求值 \$.bid 抛错 → 引擎容错为空串 → bid=（空）。
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
  });
}
