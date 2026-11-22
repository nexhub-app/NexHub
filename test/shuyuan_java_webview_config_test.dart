/// E1 JS API 面回归（legado JsExtensions）：
/// - `java.webViewGetSource` / `java.webViewGetOverrideUrl` 与 `java.webView`
///   共用无头重放通道，嗅探正则分别落在 settle 的 args[5]（sourceRegex）与
///   args[6]（overrideUrlRegex），delayTime 落 args[3]；
/// - 嗅探正则参与缓存键：同页面不同嗅探目标互不命中；
/// - `java.getReadBookConfig` / `java.getThemeConfig` 返回 legado 形状的
///   JSON 串（字段齐全，JSON.parse 可用）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/analyze/webview_fetcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  setUp(() {
    ShuyuanSourceContext.resetForTest();
    ShuyuanWebviewFetcher.debugFetchOverride = null;
  });
  tearDown(() => ShuyuanWebviewFetcher.debugFetchOverride = null);

  JsEngine engine() => JsEngine();

  group('java.webViewGetSource', () {
    test('登记 [html,url,js,delay,"",sourceRegex,""]，回填后重放命中', () {
      final ctx = ShuyuanSourceContext('wvs_test');
      final e = engine();
      // JS 里 `\\.` 才保留正则中的反斜杠（`\.` 是 JS 字符串的恒等转义）。
      const call = r"java.webViewGetSource('', 'https://v.test/p', 'var x=1', "
          r"'https?://v\\.test/.*\\.mp4', true, 1200)";
      const pattern = r'https?://v\.test/.*\.mp4';
      ShuyuanSourceContext.run(ctx, () {
        expect(e.eval(call), startsWith('__WEBVIEW_SRC_'));
        expect(ctx.webviewPending, hasLength(1));
        final args = ctx.webviewArgs[ctx.webviewPending.single]!;
        expect(args[0], '');
        expect(args[1], 'https://v.test/p');
        expect(args[2], 'var x=1');
        expect(args[3], '1200');
        expect(args[4], '');
        expect(args[5], pattern);
        expect(args[6], '');

        ctx.webviewCache[ctx.webviewPending.single] = 'https://v.test/a.mp4';
        expect(e.eval(call), 'https://v.test/a.mp4');
        // 缓存命中后不再排队。
        expect(ctx.webviewPending, hasLength(1));
      });
    });

    test('省略 cacheFirst/delayTime 时 delay 记 0', () {
      final ctx = ShuyuanSourceContext('wvs_defaults');
      ShuyuanSourceContext.run(ctx, () {
        engine().eval("java.webViewGetSource('', 'https://v.test/p', '', 'x')");
        final args = ctx.webviewArgs[ctx.webviewPending.single]!;
        expect(args[3], '0');
        expect(args[5], 'x');
      });
    });

    test('空 html 与空 url 返回空串且不排队', () {
      final ctx = ShuyuanSourceContext('wvs_empty');
      ShuyuanSourceContext.run(ctx, () {
        expect(engine().eval("java.webViewGetSource('', '', '', 'x')"), '');
        expect(ctx.webviewPending, isEmpty);
      });
    });

    test('settleWebview 透传 sourceRegex 与 delay，结果写回缓存', () async {
      final ctx = ShuyuanSourceContext('wvs_settle');
      const pattern = r'https?://v\.test/.*\.mp4';
      String? seenSource;
      String? seenOverride;
      int? seenDelay;
      ShuyuanWebviewFetcher.debugFetchOverride = ({
        String? html,
        String? url,
        String? js,
        int delayMs = 0,
        Map<String, String>? headers,
        String? sourceRegex,
        String? overrideUrlRegex,
      }) async {
        seenSource = sourceRegex;
        seenOverride = overrideUrlRegex;
        seenDelay = delayMs;
        return const ShuyuanWebviewResult(
            html: 'https://v.test/a.mp4', finalUrl: '');
      };
      final e = engine();
      const call = r"java.webViewGetSource('', 'https://v.test/p', '', "
          r"'https?://v\\.test/.*\\.mp4', false, 500)";
      ShuyuanSourceContext.run(
          ctx, () => expect(e.eval(call), startsWith('__WEBVIEW_SRC_')));
      final key = ctx.webviewPending.single;
      expect(await ShuyuanSourceContext.settleWebview(ctx), 1);
      expect(seenSource, pattern);
      expect(seenOverride, isNull);
      expect(seenDelay, 500);
      expect(ctx.webviewCache[key], 'https://v.test/a.mp4');
      expect(ShuyuanSourceContext.run(ctx, () => e.eval(call)),
          'https://v.test/a.mp4');
    });
  });

  group('java.webViewGetOverrideUrl', () {
    test('登记 [html,url,js,delay,"","",overrideUrlRegex]', () {
      final ctx = ShuyuanSourceContext('wvo_test');
      ShuyuanSourceContext.run(ctx, () {
        engine().eval(r"java.webViewGetOverrideUrl('', 'https://v.test/p', '', "
            r"'https://v\\.test/go.*', true, 0)");
        final args = ctx.webviewArgs[ctx.webviewPending.single]!;
        expect(args.length, 7);
        expect(args[5], '');
        expect(args[6], r'https://v\.test/go.*');
      });
    });

    test('settleWebview 透传 overrideUrlRegex', () async {
      final ctx = ShuyuanSourceContext('wvo_settle');
      const pattern = r'https://v\.test/go.*';
      String? seenSource;
      String? seenOverride;
      ShuyuanWebviewFetcher.debugFetchOverride = ({
        String? html,
        String? url,
        String? js,
        int delayMs = 0,
        Map<String, String>? headers,
        String? sourceRegex,
        String? overrideUrlRegex,
      }) async {
        seenSource = sourceRegex;
        seenOverride = overrideUrlRegex;
        return const ShuyuanWebviewResult(
            html: 'https://v.test/go/1', finalUrl: '');
      };
      final e = engine();
      const call = r"java.webViewGetOverrideUrl('', 'https://v.test/p', '', "
          r"'https://v\\.test/go.*')";
      ShuyuanSourceContext.run(
          ctx, () => expect(e.eval(call), startsWith('__WEBVIEW_OVR_')));
      final key = ctx.webviewPending.single;
      await ShuyuanSourceContext.settleWebview(ctx);
      expect(seenSource, isNull);
      expect(seenOverride, pattern);
      expect(ctx.webviewCache[key], 'https://v.test/go/1');
    });
  });

  test('嗅探正则参与缓存键：同页面不同目标（含普通 webView）互不命中', () {
    final ctx = ShuyuanSourceContext('wv_keys');
    ShuyuanSourceContext.run(ctx, () {
      final e = engine();
      e.eval("java.webViewGetSource('', 'https://v.test/p', '', 'a.*')");
      e.eval("java.webViewGetSource('', 'https://v.test/p', '', 'b.*')");
      e.eval("java.webView('', 'https://v.test/p', '')");
      expect(ctx.webviewPending, hasLength(3));
      expect(ctx.webviewPending.toSet(), hasLength(3));
    });
  });

  group('阅读/主题配置', () {
    test('getReadBookConfig 返回 legado 字段形状的 JSON 串', () {
      final cfg = jsonDecode(engine().eval('java.getReadBookConfig()')) as Map;
      expect(cfg['textSize'], 20);
      expect(cfg['bgStr'], '#EEEEEE');
      expect(cfg['bgStrNight'], '#000000');
      expect(cfg['lineSpacingExtra'], 12);
      expect(cfg['paragraphSpacing'], 2);
      expect(cfg['paragraphIndent'], '\u3000\u3000');
      expect(cfg['textColor'], '#3E3D3B');
      expect(cfg['textAccentColor'], '#834E00');
      expect(cfg['titleMode'], 0);
      expect(cfg.containsKey('titleSizeRelative'), isTrue);
    });

    test('getThemeConfig 返回主题 JSON 串', () {
      final theme = jsonDecode(engine().eval('java.getThemeConfig()')) as Map;
      expect(theme['themeName'], 'MD3-Day');
      expect(theme['isNightTheme'], isFalse);
      expect(theme['primaryColor'], '#795548');
      expect(theme['backgroundColor'], '#F5F5F5');
      expect(theme.containsKey('backgroundImgPath'), isTrue);
      expect(theme['backgroundImgBlur'], 0);
    });
  });
}
