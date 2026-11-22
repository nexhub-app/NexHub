/// WebView 重放抓取：headers 透传、data: 内联、Cookie 回传、最终 URL。
/// 通过 debugFetchOverride 走确定性路径，不创建真实 WebView。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_url.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/analyze/webview_fetcher.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});
  setUp(() {
    ShuyuanSourceContext.resetForTest();
    ShuyuanWebviewFetcher.debugFetchOverride = null;
  });
  tearDown(() => ShuyuanWebviewFetcher.debugFetchOverride = null);

  test('data: 文本转 HTML、图片包 <img>', () {
    expect(
      ShuyuanWebviewFetcher.dataUrlToHtml(
          'data:text/html;charset=utf-8,%3Cdiv%3Ehi%3C/div%3E'),
      '<div>hi</div>',
    );
    expect(
      ShuyuanWebviewFetcher.dataUrlToHtml('data:image/png;base64,AAAA'),
      startsWith('<html><body><img src="data:image/png;base64,AAAA"'),
    );
    expect(ShuyuanWebviewFetcher.dataUrlToHtml('https://x.test/'), isNull);
  });

  test('AnalyzeUrl useWebView 透传源 header/覆盖层 Cookie 并回写 Cookie', () async {
    Map<String, String>? seen;
    ShuyuanWebviewFetcher.debugFetchOverride = ({
      String? html,
      String? url,
      String? js,
      int delayMs = 0,
      Map<String, String>? headers,
      String? sourceRegex,
      String? overrideUrlRegex,
    }) async {
      seen = headers;
      expect(url, 'https://web.test/page');
      expect(delayMs, 1500);
      return const ShuyuanWebviewResult(
        html: '<html><body><div id="c">渲染正文</div></body></html>',
        finalUrl: 'https://web.test/final',
        cookieHeaders: <String, String>{'web.test': 'sid=xyz; t=1'},
      );
    };
    final ctx = ShuyuanSourceContext('src_wv')
      ..cookies['sid'] = <String, String>{'value': 'old', 'host': 'web.test'};
    final source = XiaoshuoBookSource.fromJson(<String, dynamic>{
      'bookSourceUrl': 'https://web.test',
      'bookSourceName': 'wv-test',
      'bookSourceType': 0,
      'header': '{"X-From":"source"}',
    });
    final out = await ShuyuanSourceContext.run(ctx, () {
      final a = AnalyzeUrl(
        url: 'https://web.test/page',
        baseUrl: 'https://web.test',
        source: source,
      );
      a.useWebView = true;
      a.webViewDelayTime = 1500;
      return a.getStrResponse();
    });
    expect(out, contains('渲染正文'));
    expect(seen?['X-From'], 'source');
    expect(seen?['Cookie'], contains('sid=old'));
    expect(seen?['User-Agent'], isNotNull);
    expect(ctx.cookies['sid']?['value'], 'xyz');
    expect(ctx.cookies['t']?['value'], '1');
  });

  test('源 header 小写 user-agent 大小写不敏感地覆盖宿主 UA', () async {
    Map<String, String>? seen;
    ShuyuanWebviewFetcher.debugFetchOverride = ({
      String? html,
      String? url,
      String? js,
      int delayMs = 0,
      Map<String, String>? headers,
      String? sourceRegex,
      String? overrideUrlRegex,
    }) async {
      seen = headers;
      return const ShuyuanWebviewResult(
        html: '<html><body>ok</body></html>',
        finalUrl: 'https://web.test/page',
      );
    };
    final source = XiaoshuoBookSource.fromJson(<String, dynamic>{
      'bookSourceUrl': 'https://web.test',
      'bookSourceName': 'wv-ua-test',
      'bookSourceType': 0,
      'header': '{"user-agent":"MobileUA/1.0"}',
    });
    final out = await ShuyuanSourceContext.run(
      ShuyuanSourceContext('src_wv_ua'),
      () {
        final a = AnalyzeUrl(
          url: 'https://web.test/page',
          baseUrl: 'https://web.test',
          source: source,
        );
        a.useWebView = true;
        return a.getStrResponse();
      },
    );
    expect(out, contains('ok'));
    expect(seen, isNotNull);
    // 源声明的 UA 必须生效，且不能与宿主 UA 并存两个大小写不同的键。
    final uaKeys = seen!.keys
        .where((k) => k.toLowerCase() == 'user-agent')
        .toList(growable: false);
    expect(uaKeys, hasLength(1));
    expect(seen![uaKeys.single], 'MobileUA/1.0');
  });

  test('settleWebview 带 delay 抓取并同步 Cookie', () async {
    ShuyuanWebviewFetcher.debugFetchOverride = ({
      String? html,
      String? url,
      String? js,
      int delayMs = 0,
      Map<String, String>? headers,
      String? sourceRegex,
      String? overrideUrlRegex,
    }) async {
      expect(delayMs, 800);
      return const ShuyuanWebviewResult(
        html: '<div>wv-body</div>',
        finalUrl: 'https://wv.test/a',
        cookieHeaders: <String, String>{'wv.test': 'k=v'},
      );
    };
    final ctx = ShuyuanSourceContext('src_wv_settle');
    ctx.webviewArgs['wv:1'] = <String>['', 'https://wv.test/a', '', '800'];
    ctx.webviewPending.add('wv:1');
    final fetched = await ShuyuanSourceContext.settleWebview(ctx);
    expect(fetched, 1);
    expect(ctx.webviewCache['wv:1'], '<div>wv-body</div>');
    expect(ctx.cookies['k']?['value'], 'v');
  });
}
