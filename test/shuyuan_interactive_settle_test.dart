/// 交互 settle：startBrowserAwait refetch 语义、验证码、startBrowser 去重、
/// 等待时长回传（预算延长依据）。全部走 fake host，不弹真实 UI。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';
import 'package:nexhub/features/shuyuan/presentation/shuyuan_browser_screen.dart';
import 'package:nexhub/features/shuyuan/presentation/shuyuan_interactive.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeHost implements ShuyuanInteractiveHost {
  _FakeHost(this.outcome);

  final ShuyuanBrowserOutcome? outcome;
  final List<String> opened = <String>[];
  String? code;
  Map<String, String>? imageHeaders;

  @override
  Future<ShuyuanBrowserOutcome?> openBrowser({
    required String url,
    required String title,
    required bool refetchAfterSuccess,
    String html = '',
    PluginConfig? source,
  }) async {
    opened.add(url);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return outcome;
  }

  @override
  Future<String?> getVerificationCode(
    String imageUrl, {
    String? title,
    Map<String, String> headers = const <String, String>{},
  }) async {
    imageHeaders = headers;
    return code;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  late HttpServer server;
  late String origin;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write('<div id="c">refetch-body</div>');
      req.response.close();
    });
    origin = 'http://127.0.0.1:${server.port}';
  });

  tearDownAll(() => server.close(force: true));
  tearDown(() => shuyuanInteractiveHost = defaultShuyuanInteractiveHost);

  ({XiaoshuoBookSource bookSource, PluginConfig plugin}) sources(String url) {
    final json = <String, dynamic>{
      'bookSourceUrl': url,
      'bookSourceName': 'settle-test',
      'bookSourceType': 0,
      'ruleContent': <String, dynamic>{'content': '#c@html'},
    };
    final raw = ShuyuanSource.fromJson(json);
    return (
      bookSource: raw.toBookSource(),
      plugin: ShuyuanAdapter.toPluginConfig(raw),
    );
  }

  test('refetch=true 重新请求 URL，Cookie 同步进覆盖层', () async {
    final host = _FakeHost(ShuyuanBrowserOutcome(
      html: '<div>ignored</div>',
      finalUrl: '$origin/final',
      cookieHeaders: const <String, String>{'127.0.0.1': 'sid=x'},
    ));
    shuyuanInteractiveHost = host;
    final ctx = ShuyuanSourceContext('src_settle_refetch');
    ctx.browserAwaitArgs['ba:1'] = <String>['$origin/page', '登录', '1', ''];
    ctx.browserAwaitPending.add('ba:1');
    final pair = sources(origin);
    final result = await settleShuyuanInteractive(
      ctx,
      pair.bookSource,
      pluginSource: pair.plugin,
    );
    expect(result.fetched, 1);
    expect(result.waited.inMilliseconds, greaterThanOrEqualTo(120));
    final payload = jsonDecode(ctx.browserAwaitCache['ba:1']!) as Map;
    expect(payload['code'], 200);
    expect('${payload['body']}', contains('refetch-body'));
    expect(ctx.cookies['sid']?['value'], 'x');
  });

  test('settle 结束把捕获的 Cookie 落盘（新 ctx 可从存储读回）', () async {
    final host = _FakeHost(const ShuyuanBrowserOutcome(
      html: '<div>outer</div>',
      cookieHeaders: <String, String>{'example.com': 'sid=abc'},
    ));
    shuyuanInteractiveHost = host;
    final ctx = ShuyuanSourceContext('src_settle_persist');
    ctx.browserAwaitArgs['ba:p'] = <String>['$origin/page', '登录', '0', ''];
    ctx.browserAwaitPending.add('ba:p');
    final pair = sources(origin);
    await settleShuyuanInteractive(ctx, pair.bookSource,
        pluginSource: pair.plugin);
    expect(ctx.cookies['sid']?['value'], 'abc');

    // 仅在内存里不算数：新建 ctx（解析器实例重建/跨实例复用）必须能读回。
    // 修复前 settle 从不 persistIfNeeded → 存储为空 → 这里读不到。
    final fresh = ShuyuanSourceContext('src_settle_persist');
    await fresh.refreshCookiesFromStore();
    expect(fresh.cookiesForHost('example.com'), containsPair('sid', 'abc'));
  });

  test('refetch=false 使用 outerHTML；取消返回空壳', () async {
    final host = _FakeHost(ShuyuanBrowserOutcome(
      html: '<div>outer</div>',
      finalUrl: '$origin/home',
    ));
    shuyuanInteractiveHost = host;
    final ctx = ShuyuanSourceContext('src_settle_outer');
    ctx.browserAwaitArgs['ba:2'] = <String>['$origin/page', '登录', '0', ''];
    ctx.browserAwaitPending.add('ba:2');
    final pair = sources(origin);
    await settleShuyuanInteractive(ctx, pair.bookSource,
        pluginSource: pair.plugin);
    final payload = jsonDecode(ctx.browserAwaitCache['ba:2']!) as Map;
    expect(payload['body'], '<div>outer</div>');
    expect(payload['url'], '$origin/home');

    shuyuanInteractiveHost = _FakeHost(null);
    final ctx2 = ShuyuanSourceContext('src_settle_cancel');
    ctx2.browserAwaitArgs['ba:3'] = <String>['$origin/page', '登录', '1', ''];
    ctx2.browserAwaitPending.add('ba:3');
    await settleShuyuanInteractive(ctx2, pair.bookSource,
        pluginSource: pair.plugin);
    final empty = jsonDecode(ctx2.browserAwaitCache['ba:3']!) as Map;
    expect(empty['body'], '');
    expect(empty['code'], 0);
  });

  test('验证码 host 收到的图片头含 UA 与覆盖层 Cookie', () async {
    final host = _FakeHost(null)..code = 'C9';
    shuyuanInteractiveHost = host;
    final ctx = ShuyuanSourceContext('src_settle_vc')
      ..cookies['sid'] = <String, String>{'value': 'v', 'host': '127.0.0.1'};
    ctx.verificationArgs['vc:1'] = '$origin/c.png';
    ctx.verificationPending.add('vc:1');
    final pair = sources(origin);
    await settleShuyuanInteractive(ctx, pair.bookSource,
        pluginSource: pair.plugin);
    expect(ctx.verificationCodeCache['vc:1'], 'C9');
    expect(host.imageHeaders?['Cookie'], contains('sid=v'));
    expect(host.imageHeaders?['User-Agent'], isNotNull);
  });

  test('startBrowser 仅登录模式打开，且跨轮去重', () async {
    final host = _FakeHost(const ShuyuanBrowserOutcome(
      html: '<div></div>',
      cookieHeaders: <String, String>{'127.0.0.1': 'a=b'},
    ));
    shuyuanInteractiveHost = host;
    final ctx = ShuyuanSourceContext('src_settle_open');
    ctx.kindBrowserOpens.add(<String, String>{
      'url': '$origin/login',
      'title': '登录',
      'html': '',
    });
    final pair = sources(origin);
    expect(hasPendingInteractive(ctx), isTrue);
    await settleShuyuanInteractive(ctx, pair.bookSource,
        pluginSource: pair.plugin, openBrowsers: true);
    await settleShuyuanInteractive(ctx, pair.bookSource,
        pluginSource: pair.plugin, openBrowsers: true);
    expect(host.opened, <String>['$origin/login']);
    expect(ctx.cookies['a']?['value'], 'b');
  });
}
