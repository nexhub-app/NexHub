/// 编排层：跨实例 Cookie 刷新、登录脚本交互重放并落盘。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexhub/core/models/novel_block.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/presentation/shuyuan_browser_screen.dart';
import 'package:nexhub/features/shuyuan/presentation/shuyuan_interactive.dart';
import 'package:nexhub/features/shuyuan/presentation/shuyuan_login_dialog.dart';
import 'package:nexhub/features/shuyuan/presentation/shuyuan_novel_resolver.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeHost implements ShuyuanInteractiveHost {
  @override
  Future<ShuyuanBrowserOutcome?> openBrowser({
    required String url,
    required String title,
    required bool refetchAfterSuccess,
    String html = '',
    PluginConfig? source,
  }) async {
    return const ShuyuanBrowserOutcome(
      html: '<html><body>done</body></html>',
      finalUrl: 'https://login.test/home',
      cookieHeaders: <String, String>{'login.test': 'sid=1'},
    );
  }

  @override
  Future<String?> getVerificationCode(
    String imageUrl, {
    String? title,
    Map<String, String> headers = const <String, String>{},
  }) async =>
      null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ShuyuanSourceContext.resetForTest();
    shuyuanInteractiveHost = _FakeHost();
  });
  tearDown(() => shuyuanInteractiveHost = defaultShuyuanInteractiveHost);

  test('resolver 复用 ctx 时刷新别处落盘的 Cookie', () async {
    var requireCookie = false;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) {
      final cookie = req.headers.value('cookie') ?? '';
      final ok = !requireCookie || cookie.contains('sid=abc');
      req.response
        ..statusCode = ok ? 200 : 403
        ..headers.contentType = ContentType.html
        ..write(ok ? '<div id="c">${req.uri.path}</div>' : 'denied');
      req.response.close();
    });
    final origin = 'http://127.0.0.1:${server.port}';
    final config = ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(
      <String, dynamic>{
        'bookSourceName': 'resolver-cookie',
        'bookSourceUrl': origin,
        'bookSourceType': 0,
        'ruleContent': <String, dynamic>{'content': '#c@html'},
      },
    ));
    final resolver = ShuyuanNovelResolver();
    final first = await resolver.resolve(config, 'content',
        vars: <String, String>{'url': '$origin/a.html'}) as NovelContentResult;
    expect(
      first.blocks.whereType<NovelTextBlock>().map((b) => b.text.trim()),
      contains('/a.html'),
    );

    final writer = await ShuyuanSourceContext.forSource(config.id);
    writer.syncCookies('127.0.0.1', 'sid=abc');
    await writer.persistIfNeeded();
    requireCookie = true;

    final second = await resolver.resolve(config, 'content',
        vars: <String, String>{'url': '$origin/b.html'}) as NovelContentResult;
    expect(
      second.blocks.whereType<NovelTextBlock>().map((b) => b.text.trim()),
      contains('/b.html'),
    );
  });

  testWidgets('URL 登录脚本中的 startBrowserAwait 完成并落盘 Cookie', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold();
      }),
    ));
    final config = ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(
      <String, dynamic>{
        'bookSourceName': 'login-test',
        'bookSourceUrl': 'https://login.test',
        'bookSourceType': 0,
        'loginUrl': '@js:var r = java.startBrowserAwait('
            '"https://login.test/", "登录", false); "ok"',
        'loginUi': <Map<String, dynamic>>[
          <String, dynamic>{'name': 'user', 'type': 'text', 'default': 'u'},
        ],
      },
    ));
    // flutter_js 的 XHR 扩展在创建 JS 运行时时注册一个不可取消的 40ms 周期
    // 定时器；若在 fake-async 区（testWidgets 正文）内首次创建，收尾会报
    // "A Timer is still pending"。这里在真实异步区预热池化引擎，登录脚本
    // 复用同一实例即可绕开。
    await tester.runAsync(() async {
      JsEngine.forSource(config.id).runtime;
    });
    final future = showShuyuanLogin(ctx, config);
    await tester.pumpAndSettle();
    // 登录弹窗的提交按钮是唯一/最后一个 FilledButton（标题文案可能相同）。
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();
    await future;
    await tester.pumpAndSettle();

    final loaded = await ShuyuanSourceContext.forSource(config.id);
    expect(loaded.cookies['sid']?['value'], '1');
  });
}
