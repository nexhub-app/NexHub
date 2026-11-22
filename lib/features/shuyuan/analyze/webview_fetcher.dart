/// 书源 WebView 重放抓取：把规则层声明的 UA/Cookie 带进无头页面，
/// 返回正文 HTML、最终 URL 与页面写下的 Cookie。
///
/// Cookie 只回传，不直接写全局 jar；由宿主写入 per-source 覆盖层。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/platform/platform_service.dart';
import 'webview_cookie_reader.dart';

/// WebView 抓取结果。
class ShuyuanWebviewResult {
  const ShuyuanWebviewResult({
    required this.html,
    this.finalUrl = '',
    this.cookieHeaders = const <String, String>{},
  });

  final String html;
  final String finalUrl;

  /// host → `name=value; ...`（只含该域可回放的 Cookie）。
  final Map<String, String> cookieHeaders;
}

class ShuyuanWebviewFetcher {
  ShuyuanWebviewFetcher._();

  /// 测试注入：返回 null 表示模拟失败。
  @visibleForTesting
  static Future<ShuyuanWebviewResult?> Function({
    String? html,
    String? url,
    String? js,
    int delayMs,
    Map<String, String>? headers,
    String? sourceRegex,
    String? overrideUrlRegex,
  })? debugFetchOverride;

  static const Duration _renderSettle = Duration(milliseconds: 1200);
  static const Duration _jsSettle = Duration(milliseconds: 600);
  static const Duration _loadTimeout = Duration(seconds: 45);
  static const String _defaultUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  /// data: URL → 可注入 WebView 的 HTML。
  /// 文本按 percent/base64 解码；图片包成 `<img>`（WebView2 禁止顶层
  /// data: 导航，注入 about:blank 后可正常渲染）。
  static String? dataUrlToHtml(String url) {
    if (!url.startsWith('data:')) return null;
    final comma = url.indexOf(',');
    if (comma <= 5) return null;
    final meta = url.substring(5, comma).toLowerCase();
    final payload = url.substring(comma + 1);
    if (meta.startsWith('image/')) {
      final src = url.replaceAll('"', '%22');
      return '<html><body><img src="$src"></body></html>';
    }
    if (!meta.startsWith('text/html') && !meta.contains('html')) return null;
    try {
      if (meta.endsWith(';base64')) {
        return utf8.decode(base64Decode(payload));
      }
      return Uri.decodeComponent(payload);
    } catch (_) {
      return null;
    }
  }

  static Future<ShuyuanWebviewResult?> fetch({
    String? html,
    String? url,
    String? js,
    int delayMs = 0,
    Map<String, String>? headers,
    String? sourceRegex,
    String? overrideUrlRegex,
  }) async {
    final override = debugFetchOverride;
    if (override != null) {
      return override(
        html: html,
        url: url,
        js: js,
        delayMs: delayMs,
        headers: headers,
        sourceRegex: sourceRegex,
        overrideUrlRegex: overrideUrlRegex,
      );
    }
    if (!PlatformService.instance.isAndroid &&
        !PlatformService.instance.isIOS &&
        !PlatformService.instance.isWindows &&
        !PlatformService.instance.isOHOS) {
      return null;
    }

    var data = html ?? '';
    var pageUrl = (url ?? '').trim();
    final requestHeaders = <String, String>{...?headers};
    String takeHeader(String name) {
      for (final k in requestHeaders.keys.toList()) {
        if (k.toLowerCase() == name.toLowerCase()) {
          return requestHeaders.remove(k) ?? '';
        }
      }
      return '';
    }

    final cookieHeader = takeHeader('Cookie');
    final ua = takeHeader('User-Agent');
    if (data.trim().isEmpty && pageUrl.startsWith('data:')) {
      data = dataUrlToHtml(pageUrl) ?? '';
      if (data.isNotEmpty) pageUrl = '';
    }
    final hasHtml = data.trim().isNotEmpty;
    final startUrl = pageUrl;
    final hasUrl = startUrl.isNotEmpty;
    if (!hasHtml && !hasUrl) return null;

    final cookiePairs = _parseCookieHeader(cookieHeader);
    final directNavigation = hasUrl && cookiePairs.isEmpty;
    // 嗅探模式（legado SnifferWebClient）：任一正则命中即把命中的 URL
    // 作为正文返回，不再执行 JS。
    final sniffing = _nonEmpty(sourceRegex) || _nonEmpty(overrideUrlRegex);
    String? matchedUrl;

    HeadlessInAppWebView? webview;
    final created = Completer<InAppWebViewController>();
    final loaded = Completer<void>();
    try {
      webview = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri(hasHtml || !directNavigation ? 'about:blank' : startUrl),
          headers: directNavigation && requestHeaders.isNotEmpty
              ? requestHeaders
              : null,
        ),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          userAgent: ua.isEmpty ? (hasHtml ? _defaultUa : null) : ua,
          useOnLoadResource: sniffing,
          useShouldOverrideUrlLoading: sniffing,
        ),
        onWebViewCreated: (c) {
          if (!created.isCompleted) created.complete(c);
        },
        onLoadResource: (controller, request) {
          final u = request.url.toString();
          if (!_fullMatch(sourceRegex, u)) return;
          matchedUrl ??= u;
          if (!loaded.isCompleted) loaded.complete();
        },
        shouldOverrideUrlLoading: (controller, action) async {
          final u = action.request.url.toString();
          if (_fullMatch(overrideUrlRegex, u)) {
            matchedUrl ??= u;
            if (!loaded.isCompleted) loaded.complete();
            return NavigationActionPolicy.CANCEL;
          }
          return NavigationActionPolicy.ALLOW;
        },
        onLoadStop: (_, uri) {
          // 带 Cookie 时必须先落 about:blank 再 setCookie，about: 的
          // 加载完成不算目标页就绪，只认 http(s) 导航。
          final scheme = uri?.scheme ?? '';
          if ((scheme == 'http' || scheme == 'https') && !loaded.isCompleted) {
            loaded.complete();
          }
        },
        onReceivedError: (_, request, __) {
          final scheme = request.url.scheme;
          if ((scheme == 'http' || scheme == 'https') && !loaded.isCompleted) {
            loaded.complete();
          }
        },
        // headless 无 UI：站点的 alert/confirm 必须接管，否则阻塞 JS 队列。
        onJsAlert: (controller, request) async =>
            JsAlertResponse(handledByClient: true),
        onJsConfirm: (controller, request) async =>
            JsConfirmResponse(handledByClient: true),
      );
      await webview.run();
      final c = await created.future.timeout(_loadTimeout);

      if (cookiePairs.isNotEmpty) {
        final uri = Uri.tryParse(startUrl);
        if (uri != null && uri.host.isNotEmpty) {
          for (final p in cookiePairs) {
            try {
              await CookieManager.instance().setCookie(
                url: WebUri('${uri.scheme}://${uri.host}'),
                name: p.$1,
                value: p.$2,
              );
            } catch (_) {}
          }
        }
      }

      if (hasHtml) {
        await c.loadData(
          data: data,
          mimeType: 'text/html',
          encoding: 'utf8',
          baseUrl: WebUri(hasUrl ? startUrl : 'about:blank'),
        );
        if (matchedUrl == null) {
          await Future<void>.delayed(_renderSettle);
        }
      } else {
        if (!directNavigation) {
          await c.loadUrl(
            urlRequest: URLRequest(
              url: WebUri(startUrl),
              headers: requestHeaders.isEmpty ? null : requestHeaders,
            ),
          );
        }
        await loaded.future.timeout(_loadTimeout, onTimeout: () {});
        if (matchedUrl == null) {
          await Future<void>.delayed(_renderSettle);
        }
      }

      String? evaluated;
      if (matchedUrl == null) {
        if (delayMs > 0) {
          await Future<void>.delayed(Duration(milliseconds: delayMs));
        }
        final jsCode = (js ?? '').trim();
        if (jsCode.isNotEmpty) {
          try {
            final r = await c.evaluateJavascript(source: jsCode);
            final normalized = _normalizeJsResult(r);
            if (normalized.isNotEmpty) evaluated = normalized;
          } on Object catch (e) {
            debugPrint('[书源webView] js 执行失败(忽略): $e');
          }
          await Future<void>.delayed(_jsSettle);
        }
      }
      final finalUrl =
          matchedUrl ?? (await c.getUrl())?.toString() ?? startUrl;
      final out = matchedUrl ??
          ((evaluated != null && evaluated.isNotEmpty)
              ? evaluated
              : await c.getHtml() ?? '');
      final cookieHeaders = await readWebviewCookieHeaders(
        manager: CookieManager.instance(),
        controller: c,
        finalUrl: finalUrl,
        startUrl: startUrl,
      );
      return ShuyuanWebviewResult(
        html: out,
        finalUrl: finalUrl,
        cookieHeaders: cookieHeaders,
      );
    } on Object catch (e) {
      debugPrint('[书源webView] 无头取源失败: $e');
      return null;
    } finally {
      try {
        await webview?.dispose();
      } on Object {
        // 释放失败不影响已取到的内容。
      }
    }
  }

  static bool _nonEmpty(String? s) => s != null && s.trim().isNotEmpty;

  /// legado `url.matches(regex.toRegex())`：整串匹配（非子串查找）。
  static bool _fullMatch(String? pattern, String input) {
    if (!_nonEmpty(pattern)) return false;
    try {
      return RegExp('^(?:${pattern!.trim()})\$').hasMatch(input);
    } catch (_) {
      return false;
    }
  }

  static List<(String, String)> _parseCookieHeader(String header) {
    final out = <(String, String)>[];
    for (final part in header.split(';')) {
      final eq = part.indexOf('=');
      if (eq <= 0) continue;
      final name = part.substring(0, eq).trim();
      final value = part.substring(eq + 1).trim();
      if (name.isNotEmpty) out.add((name, value));
    }
    return out;
  }

  /// 对齐 legado unescapeJson：字符串结果可能被 JSON 再编码一层
  /// （`"<div>..."` 或 `\"` 转义），先解一层引号再反转义。
  static String _normalizeJsResult(Object? raw) {
    if (raw == null) return '';
    // getElement/getElements 的 @webjs 结果在部分平台已解码为 Map/List，
    // 统一还原成 JSON 文本供规则层按 legado GSON 语义解析。
    if (raw is Map || raw is List) {
      try {
        return jsonEncode(raw);
      } catch (_) {}
    }
    var s = raw.toString();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      try {
        final decoded = jsonDecode(s.replaceAll('\\"', '"'));
        if (decoded is String) s = decoded;
      } catch (_) {
        s = s.substring(1, s.length - 1);
      }
    }
    return s
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\t', '\t')
        .replaceAll(r'\"', '"');
  }
}
