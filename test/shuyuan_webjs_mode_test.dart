/// `@webjs:` 后台 WebView 规则回归测试。
///
/// 对照 legado AnalyzeRule.splitSourceRule / getWebJsResult：
/// - JS 扫描后再扫 WebJS，前后缀规则共享同一扫描起点；
/// - 求值在宿主 WebView 重放：注入 `window.result`（上一段结果的 JSON），
///   执行脚本体并把返回串作为本段结果；
/// - getStringList 先按 JSON 字符串数组解析，失败回退原串；
/// - getElement/getElements 按 JSON 对象/对象数组解析。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_rule.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/analyze/source_rule.dart';
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

  group('splitSourceRule @webjs', () {
    test('前缀规则与 WebJs 段分离，前后缀各就位', () {
      final rules = AnalyzeRule()
          .splitSourceRule('#list@webjs:document.body.innerText');
      expect(rules, hasLength(2));
      expect(rules[0].mode, Mode.defaultMode);
      expect(rules[0].rule, '#list');
      expect(rules[1].mode, Mode.webJs);
      expect(rules[1].rule, 'document.body.innerText');
    });

    test('单独 WebJs 段', () {
      final rules = AnalyzeRule().splitSourceRule('@webjs:document.title');
      expect(rules.single.mode, Mode.webJs);
      expect(rules.single.rule, 'document.title');
    });

    test('大小写不敏感且脚本可含换行', () {
      final rules =
          AnalyzeRule().splitSourceRule('@WEBJS:var a = 1;\nreturn a;');
      expect(rules.single.mode, Mode.webJs);
      expect(rules.single.rule, contains('return a;'));
    });
  });

  group('WebJs 宿主重放', () {
    test('首次求值登记待抓取，params 携带内容/baseUrl/脚本/resultJson', () {
      final ctx = ShuyuanSourceContext('src_webjs');
      final ar = AnalyzeRule()
        ..setContent('<div id="t">第一章</div>', 'https://src.test/book/1');
      final out = ShuyuanSourceContext.run(
          ctx, () => ar.getString('#t@webjs:window.result + "!"'));
      expect(out, '');
      expect(ctx.webviewPending, hasLength(1));
      final args = ctx.webviewArgs[ctx.webviewPending.single]!;
      expect(args[0], '<div id="t">第一章</div>');
      expect(args[1], 'https://src.test/book/1');
      expect(args[2], 'window.result + "!"');
      expect(args[3], '0');
      expect(args[4], '"第一章"');
      expect(args[5], '');
      expect(args[6], '');
    });

    test('settleWebview 注入 window.result 并把返回串写回缓存', () async {
      final ctx = ShuyuanSourceContext('src_webjs_settle');
      String? seenJs;
      ShuyuanWebviewFetcher.debugFetchOverride = ({
        String? html,
        String? url,
        String? js,
        int delayMs = 0,
        Map<String, String>? headers,
        String? sourceRegex,
        String? overrideUrlRegex,
      }) async {
        seenJs = js;
        return const ShuyuanWebviewResult(
            html: '章节正文', finalUrl: 'https://src.test/book/1');
      };
      final ar = AnalyzeRule()
        ..setContent('<div id="t">第一章</div>', 'https://src.test/book/1');
      ShuyuanSourceContext.run(
          ctx, () => ar.getString('#t@webjs:window.result.length'));
      expect(await ShuyuanSourceContext.settleWebview(ctx), 1);
      expect(seenJs, contains('window.result = "第一章";'));
      final out = ShuyuanSourceContext.run(
          ctx, () => ar.getString('#t@webjs:window.result.length'));
      expect(out, '章节正文');
    });

    test('settleWebview 透传 sourceRegex/overrideUrlRegex', () async {
      final ctx = ShuyuanSourceContext('src_webjs_sniff');
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
            html: 'https://src.test/b.js', finalUrl: '');
      };
      ctx.webviewArgs['wv:sniff'] = <String>[
        '<html></html>',
        'https://src.test/',
        '',
        '0',
        '',
        r'https?://src\.test/.*\.js',
        '',
      ];
      ctx.webviewPending.add('wv:sniff');
      expect(await ShuyuanSourceContext.settleWebview(ctx), 1);
      expect(seenSource, r'https?://src\.test/.*\.js');
      expect(seenOverride, isNull);
      expect(ctx.webviewCache['wv:sniff'], 'https://src.test/b.js');
    });

    test('同一规则重放命中缓存，不重复排队', () async {
      final ctx = ShuyuanSourceContext('src_webjs_cached');
      final ar = AnalyzeRule()
        ..setContent('<div id="t">甲</div>', 'https://src.test/x');
      ShuyuanSourceContext.run(ctx, () => ar.getString('#t@webjs:1+1+1'));
      final key = ctx.webviewPending.single;
      ctx.webviewPending.clear();
      ctx.webviewCache[key] = '乙';
      expect(
          ShuyuanSourceContext.run(
              ctx, () => ar.getString('#t@webjs:1+1+1')),
          '乙');
      expect(ctx.webviewPending, isEmpty);
    });
  });

  group('WebJs 结果解析', () {
    test('getStringList：JSON 字符串数组按数组展开', () async {
      final ctx = ShuyuanSourceContext('src_webjs_list');
      ShuyuanWebviewFetcher.debugFetchOverride = ({
        String? html,
        String? url,
        String? js,
        int delayMs = 0,
        Map<String, String>? headers,
        String? sourceRegex,
        String? overrideUrlRegex,
      }) async =>
          const ShuyuanWebviewResult(html: '["a","b"]', finalUrl: '');
      final ar = AnalyzeRule()..setContent('<p>x</p>', 'https://src.test/');
      expect(
          ShuyuanSourceContext.run(ctx, () => ar.getStringList('@webjs:1+1+1')),
          isEmpty);
      await ShuyuanSourceContext.settleWebview(ctx);
      expect(
          ShuyuanSourceContext.run(ctx, () => ar.getStringList('@webjs:1+1+1')),
          ['a', 'b']);
    });

    test('getStringList：非 JSON 数组回退原串并按换行切分', () async {
      final ctx = ShuyuanSourceContext('src_webjs_list_raw');
      ShuyuanWebviewFetcher.debugFetchOverride = ({
        String? html,
        String? url,
        String? js,
        int delayMs = 0,
        Map<String, String>? headers,
        String? sourceRegex,
        String? overrideUrlRegex,
      }) async => const ShuyuanWebviewResult(
          html: '甲\n乙', finalUrl: '');
      final ar = AnalyzeRule()..setContent('<p>x</p>', 'https://src.test/');
      ShuyuanSourceContext.run(ctx, () => ar.getStringList('@webjs:1+1+1'));
      await ShuyuanSourceContext.settleWebview(ctx);
      expect(
          ShuyuanSourceContext.run(ctx, () => ar.getStringList('@webjs:1+1+1')),
          ['甲', '乙']);
    });

    test('getElement：JSON 对象解析', () async {
      final ctx = ShuyuanSourceContext('src_webjs_el');
      ShuyuanWebviewFetcher.debugFetchOverride = ({
        String? html,
        String? url,
        String? js,
        int delayMs = 0,
        Map<String, String>? headers,
        String? sourceRegex,
        String? overrideUrlRegex,
      }) async => const ShuyuanWebviewResult(
          html: '{"name":"甲","url":"/a"}', finalUrl: '');
      final ar = AnalyzeRule()..setContent('<p>x</p>', 'https://src.test/');
      ShuyuanSourceContext.run(ctx, () => ar.getElement('@webjs:1+1+1'));
      await ShuyuanSourceContext.settleWebview(ctx);
      final el =
          ShuyuanSourceContext.run(ctx, () => ar.getElement('@webjs:1+1+1'));
      expect(el, isA<Map>());
      expect(el['name'], '甲');
    });

    test('getElements：JSON 对象数组解析', () async {
      final ctx = ShuyuanSourceContext('src_webjs_els');
      ShuyuanWebviewFetcher.debugFetchOverride = ({
        String? html,
        String? url,
        String? js,
        int delayMs = 0,
        Map<String, String>? headers,
        String? sourceRegex,
        String? overrideUrlRegex,
      }) async => const ShuyuanWebviewResult(
          html: '[{"name":"甲"},{"name":"乙"}]', finalUrl: '');
      final ar = AnalyzeRule()..setContent('<p>x</p>', 'https://src.test/');
      ShuyuanSourceContext.run(ctx, () => ar.getElements('@webjs:1+1+1'));
      await ShuyuanSourceContext.settleWebview(ctx);
      final els =
          ShuyuanSourceContext.run(ctx, () => ar.getElements('@webjs:1+1+1'));
      expect(els, hasLength(2));
      expect((els[0] as Map)['name'], '甲');
      expect((els[1] as Map)['name'], '乙');
    });
  });
}
