/// 书源交互式重放的应用内浏览器（startBrowserAwait / 登录 URL）。
///
/// 完成时回传 outerHTML、最终地址与相关域 Cookie；Cookie 只交给调用方
/// 写入 per-source 覆盖层，不直接写全局 HttpFetcher jar。
library;

import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../../../core/models/plugin_config.dart';
import '../../../core/network/runtime/webview_source_network.dart';
import '../../../core/platform/platform_service.dart';
import '../../../core/scraper/http_fetcher.dart';
import '../../../core/theme/app_tokens.dart';
import '../analyze/webview_cookie_reader.dart';
import '../analyze/webview_fetcher.dart';

class ShuyuanBrowserOutcome {
  const ShuyuanBrowserOutcome({
    required this.html,
    this.finalUrl = '',
    this.cookieHeaders = const <String, String>{},
  });

  final String html;
  final String finalUrl;

  /// host → `name=value; ...`（只含该域可回放的 Cookie）。
  final Map<String, String> cookieHeaders;
}

class ShuyuanBrowserScreen extends StatefulWidget {
  const ShuyuanBrowserScreen({
    super.key,
    required this.url,
    this.html = '',
    this.title = '',
    this.source,
  });

  final String url;
  final String html;
  final String title;
  final PluginConfig? source;

  /// data: URL → 可注入 WebView 的 HTML（WebView2 禁止顶层 data: 导航）。
  static String? dataUrlToHtml(String url) =>
      ShuyuanWebviewFetcher.dataUrlToHtml(url);

  /// 最终地址兜底：注入 HTML 的页面经 `loadData` 落地时，Windows 实现会丢弃
  /// `baseUrl`（`NavigateToString`），`getUrl()` 因此返回 `about:blank`，对
  /// 调用方没有意义。空值或 `about` scheme 时回退到打开的 URL；真实的 http(s)
  /// 跳转地址保持原样。
  static String resolveFinalUrl(String? reported, String requested) {
    final raw = (reported ?? '').trim();
    if (raw.isEmpty) return requested;
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.scheme.toLowerCase() == 'about') return requested;
    return raw;
  }

  @override
  State<ShuyuanBrowserScreen> createState() => _ShuyuanBrowserScreenState();
}

class _ShuyuanBrowserScreenState extends State<ShuyuanBrowserScreen> {
  InAppWebViewController? _controller;
  WebViewEnvironment? _env;
  bool _envReady = false;
  Future<void>? _applyFuture;

  bool get _supported =>
      PlatformService.instance.isAndroid ||
      PlatformService.instance.isIOS ||
      PlatformService.instance.isWindows;

  String? get _inlineHtml {
    if (widget.html.trim().isNotEmpty) return widget.html;
    return ShuyuanBrowserScreen.dataUrlToHtml(widget.url);
  }

  String get _baseUrl {
    if (widget.url.startsWith('http://') ||
        widget.url.startsWith('https://')) {
      return widget.url;
    }
    return 'about:blank';
  }

  String? get _userAgent {
    try {
      final ua = HttpFetcher.instance.userAgentForUrl(_baseUrl);
      return ua.isEmpty ? null : ua;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    final source = widget.source;
    if (source == null) {
      _env = WebviewSourceNetwork.instance.activeEnvironment;
      _envReady = true;
    } else {
      _applyFuture =
          WebviewSourceNetwork.instance.applyForSource(source).then((_) {
        if (!mounted) return;
        setState(() {
          _env = WebviewSourceNetwork.instance.activeEnvironment;
          _envReady = true;
        });
      });
    }
  }

  @override
  void dispose() {
    if (widget.source != null) {
      final apply = _applyFuture;
      if (apply != null) {
        unawaited(apply.whenComplete(
          () => WebviewSourceNetwork.instance.releaseForSource(),
        ));
      } else {
        unawaited(WebviewSourceNetwork.instance.releaseForSource());
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title.trim().isEmpty
            ? l10n.bookSourceLogin
            : widget.title),
      ),
      body: !_supported
          ? Center(child: Text(l10n.webViewNotAvailable))
          : !_envReady
              ? const Center(child: CircularProgressIndicator())
              : InAppWebView(
                  webViewEnvironment: _env,
                  initialUrlRequest: URLRequest(
                    url: WebUri(
                        _inlineHtml == null ? widget.url : 'about:blank'),
                  ),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    userAgent: _userAgent,
                  ),
                  onWebViewCreated: (controller) {
                    _controller = controller;
                    final inline = _inlineHtml;
                    if (inline != null) {
                      controller.loadData(
                        data: inline,
                        mimeType: 'text/html',
                        encoding: 'utf8',
                        baseUrl: WebUri(_baseUrl),
                      );
                    }
                  },
                  onJsAlert: (controller, request) async =>
                      JsAlertResponse(handledByClient: true),
                  onJsConfirm: (controller, request) async =>
                      JsConfirmResponse(handledByClient: true),
                ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceMd),
          child: FilledButton(
            onPressed: _finish,
            child: Text(l10n.doneButton),
          ),
        ),
      ),
    );
  }

  Future<void> _finish() async {
    if (!_supported) {
      Navigator.of(context).pop();
      return;
    }
    final controller = _controller;
    var html = '';
    var finalUrl = widget.url;
    var cookieHeaders = const <String, String>{};
    if (controller != null) {
      try {
        html = await controller.getHtml() ?? '';
      } catch (_) {}
      try {
        finalUrl = ShuyuanBrowserScreen.resolveFinalUrl(
          (await controller.getUrl())?.toString(),
          widget.url,
        );
      } catch (_) {}
      cookieHeaders = await _readCookieHeaders(controller, finalUrl);
    }
    if (!mounted) return;
    Navigator.of(context).pop(ShuyuanBrowserOutcome(
      html: html,
      finalUrl: finalUrl,
      cookieHeaders: cookieHeaders,
    ));
  }

  /// 读取最终页与起始页相关域的 Cookie 头（host → `name=value; ...`）。
  ///
  /// 分层读取（全页地址 → 站点根 → 全量枚举）与去重细节见
  /// [readWebviewCookieHeaders]；与无头取源共用同一实现。只读：返回给调用方，
  /// 不写入任何全局 Cookie jar。
  Future<Map<String, String>> _readCookieHeaders(
    InAppWebViewController controller,
    String finalUrl,
  ) =>
      readWebviewCookieHeaders(
        manager: CookieManager.instance(webViewEnvironment: _env),
        controller: controller,
        finalUrl: finalUrl,
        startUrl: widget.url,
      );
}
