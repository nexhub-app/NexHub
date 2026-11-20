/// 交互动作的宿主抽象与确定性 settle。
///
/// JS 侧首轮只登记 op；这里弹 UI、等待用户完成，把结果写入 per-source
/// 缓存，下一轮重放脚本即可命中。等待时长单独回传，供编排层延长预算。
library;

import 'dart:convert';

import '../../../core/models/plugin_config.dart';
import '../../../core/navigation/app_navigator.dart';
import '../../../core/navigation/app_page_route.dart';
import '../../../core/scraper/http_fetcher.dart';
import '../analyze/analyze_url.dart';
import '../analyze/source_context.dart';
import '../model/book_source.dart';
import 'shuyuan_browser_screen.dart';
import 'shuyuan_verification_code_screen.dart';

abstract class ShuyuanInteractiveHost {
  Future<ShuyuanBrowserOutcome?> openBrowser({
    required String url,
    required String title,
    required bool refetchAfterSuccess,
    String html = '',
    PluginConfig? source,
  });

  Future<String?> getVerificationCode(
    String imageUrl, {
    String? title,
    Map<String, String> headers = const <String, String>{},
  });
}

class _DefaultShuyuanInteractiveHost implements ShuyuanInteractiveHost {
  const _DefaultShuyuanInteractiveHost();

  @override
  Future<ShuyuanBrowserOutcome?> openBrowser({
    required String url,
    required String title,
    required bool refetchAfterSuccess,
    String html = '',
    PluginConfig? source,
  }) async {
    final navigator = AppNavigator.navigator;
    if (navigator == null) return null;
    return navigator.push<ShuyuanBrowserOutcome>(
      AppPageRoute<ShuyuanBrowserOutcome>(
        builder: (_) => ShuyuanBrowserScreen(
          url: url,
          html: html,
          title: title,
          source: source,
        ),
      ),
    );
  }

  @override
  Future<String?> getVerificationCode(
    String imageUrl, {
    String? title,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final navigator = AppNavigator.navigator;
    final context = navigator?.overlay?.context ?? navigator?.context;
    if (context == null) return null;
    return ShuyuanVerificationCodeScreen.show(
      context,
      imageUrl: imageUrl,
      title: title,
      imageHeaders: headers,
    );
  }
}

const ShuyuanInteractiveHost defaultShuyuanInteractiveHost =
    _DefaultShuyuanInteractiveHost();

ShuyuanInteractiveHost shuyuanInteractiveHost = defaultShuyuanInteractiveHost;

String shuyuanBrowserOpenKey(String url, String title, String html) =>
    '$url\u0001$title\u0001$html';

bool hasPendingInteractive(
  ShuyuanSourceContext ctx, {
  bool includeOpenBrowsers = true,
}) {
  if (ctx.browserAwaitPending.isNotEmpty) return true;
  if (ctx.verificationPending.isNotEmpty) return true;
  if (!includeOpenBrowsers) return false;
  for (final open in ctx.kindBrowserOpens) {
    final key = shuyuanBrowserOpenKey(
      open['url'] ?? '',
      open['title'] ?? '',
      open['html'] ?? '',
    );
    if (!ctx.browserOpened.contains(key)) return true;
  }
  return false;
}

class ShuyuanInteractiveSettleResult {
  const ShuyuanInteractiveSettleResult(this.fetched, this.waited);

  final int fetched;
  final Duration waited;
}

Future<ShuyuanInteractiveSettleResult> settleShuyuanInteractive(
  ShuyuanSourceContext ctx,
  XiaoshuoBookSource bookSource, {
  required PluginConfig pluginSource,
  bool openBrowsers = false,
}) async {
  final started = DateTime.now();
  var fetched = 0;

  final awaitKeys = List<String>.from(ctx.browserAwaitPending);
  ctx.browserAwaitPending.clear();
  for (final key in awaitKeys) {
    final args = ctx.browserAwaitArgs[key] ?? const <String>[];
    final url = args.isNotEmpty ? args[0] : '';
    final title = args.length > 1 ? args[1] : '';
    final refetch = args.length > 2 ? args[2] != '0' : true;
    final html = args.length > 3 ? args[3] : '';
    final outcome = await shuyuanInteractiveHost.openBrowser(
      url: url,
      title: title,
      refetchAfterSuccess: refetch,
      html: html,
      source: pluginSource,
    );
    var body = '';
    var code = 0;
    var finalUrl = url;
    if (outcome != null) {
      for (final e in outcome.cookieHeaders.entries) {
        ctx.syncCookies(e.key, e.value);
      }
      if (refetch && url.isNotEmpty) {
        try {
          final analyze = AnalyzeUrl(
            url: url,
            baseUrl: pluginSource.site.baseUrl,
            source: bookSource,
          );
          body = await analyze
              .getStrResponse()
              .timeout(const Duration(seconds: 45));
          code = analyze.lastStatusCode ?? 200;
          finalUrl = analyze.lastFinalUrl ?? url;
        } catch (_) {}
      } else {
        body = outcome.html;
        finalUrl = outcome.finalUrl.isEmpty ? url : outcome.finalUrl;
        code = body.isEmpty ? 0 : 200;
      }
    }
    ctx.browserAwaitCache[key] = jsonEncode(<String, dynamic>{
      'body': body,
      'code': code,
      'url': finalUrl,
    });
    fetched++;
  }

  if (openBrowsers) {
    final opens = List<Map<String, String>>.from(ctx.kindBrowserOpens);
    ctx.kindBrowserOpens.clear();
    for (final open in opens) {
      final url = open['url'] ?? '';
      final title = open['title'] ?? '';
      final html = open['html'] ?? '';
      final key = shuyuanBrowserOpenKey(url, title, html);
      if (!ctx.browserOpened.add(key)) continue;
      final outcome = await shuyuanInteractiveHost.openBrowser(
        url: url,
        title: title,
        refetchAfterSuccess: false,
        html: html,
        source: pluginSource,
      );
      if (outcome != null) {
        for (final e in outcome.cookieHeaders.entries) {
          ctx.syncCookies(e.key, e.value);
        }
      }
      fetched++;
    }
  }

  final codeKeys = List<String>.from(ctx.verificationPending);
  ctx.verificationPending.clear();
  for (final key in codeKeys) {
    final imageUrl = ctx.verificationArgs[key] ?? '';
    if (imageUrl.isEmpty) {
      ctx.verificationCodeCache[key] = '';
      continue;
    }
    final headers = <String, String>{};
    final hostName = Uri.tryParse(imageUrl)?.host.toLowerCase() ?? '';
    if (hostName.isNotEmpty) {
      try {
        headers['User-Agent'] =
            HttpFetcher.instance.userAgentForUrl(imageUrl);
      } catch (_) {}
      final overlay = ctx.cookiesForHost(hostName);
      if (overlay.isNotEmpty) {
        headers['Cookie'] =
            overlay.entries.map((e) => '${e.key}=${e.value}').join('; ');
      }
    }
    final input = await shuyuanInteractiveHost.getVerificationCode(
      imageUrl,
      headers: headers,
    );
    ctx.verificationCodeCache[key] = input ?? '';
    fetched++;
  }

  // 浏览器/登录窗捕获的 Cookie 必须即时落盘：settle 返回后解析器可能复用
  // 缓存的另一 ctx 实例，未落盘的写入既读不到，也会在 dirty 期间让
  // refreshCookiesFromStore 变成 no-op，最终被陈旧快照覆盖。
  await ctx.persistIfNeeded();

  return ShuyuanInteractiveSettleResult(
    fetched,
    DateTime.now().difference(started),
  );
}
