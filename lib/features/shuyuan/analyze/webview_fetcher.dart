/// 书源 `java.webView(html, url, js)` 的宿主实现（无头 WebView）。
///
/// 同步沙箱内开不了 WebView，故走与 `java.ajax` 相同的「确定性重放」：
/// 脚本首轮记录参数并拿占位符；宿主在此真正加载页面（或注入 html）、
/// 执行 js，回传渲染后的整页 HTML；重放时脚本直接拿到结果。
///
/// 隔离原则：**不改** [SilentHtmlCapture]（验证/媒体源共用，改动风险高），
/// 这里只服务书源脚本。任何失败都返回 null（脚本拿到空串），
/// 不抛异常、不影响既有流程；平台不支持 WebView 时同样静默返回 null。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class ShuyuanWebviewFetcher {
  ShuyuanWebviewFetcher._();

  static const Duration _loadTimeout = Duration(seconds: 20);
  static const Duration _renderSettle = Duration(milliseconds: 1200);
  static const Duration _jsSettle = Duration(milliseconds: 600);

  /// 桌面 UA：无头环境没有真实 UA，显式钉一个，避免站点按 UA 返回移动壳。
  static const String _defaultUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  /// 加载 [url] 或注入 [html]（二者至少一个），可选执行 [js]，
  /// 返回渲染后的整页 HTML；失败返回 null。
  static Future<String?> fetch({
    String? html,
    String? url,
    String? js,
    int delayMs = 0,
  }) async {
    final data = html ?? '';
    final pageUrl = (url ?? '').trim();
    final hasHtml = data.trim().isNotEmpty;
    final hasUrl = pageUrl.isNotEmpty;
    if (!hasHtml && !hasUrl) return null;

    HeadlessInAppWebView? webview;
    final created = Completer<InAppWebViewController>();
    final loaded = Completer<void>();
    try {
      webview = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri(hasUrl ? pageUrl : 'about:blank'),
        ),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          userAgent: hasUrl ? null : _defaultUa,
        ),
        onWebViewCreated: (controller) {
          if (!created.isCompleted) created.complete(controller);
        },
        onLoadStop: (controller, uri) {
          if (!loaded.isCompleted) loaded.complete();
        },
        // headless 无 UI：站点的 alert/confirm 必须接管，否则阻塞 JS 队列。
        onJsAlert: (controller, request) async =>
            JsAlertResponse(handledByClient: true),
        onJsConfirm: (controller, request) async =>
            JsConfirmResponse(handledByClient: true),
      );
      await webview.run();
      final controller = await created.future.timeout(_loadTimeout);

      if (hasHtml) {
        // html 直投：baseUrl 决定相对链接/请求的基准（没有 url 时用 about:blank）。
        // flutter_inappwebview 6.x 的接口名是 loadData（不是 loadDataWithBaseURL）。
        await controller.loadData(
          data: data,
          mimeType: 'text/html',
          encoding: 'utf8',
          baseUrl: WebUri(hasUrl ? pageUrl : 'about:blank'),
        );
        await Future<void>.delayed(_renderSettle);
      } else {
        await loaded.future.timeout(_loadTimeout, onTimeout: () {});
        await Future<void>.delayed(_renderSettle);
      }

      // legado BackstageWebView delayTime：页面加载后额外等待源声明时长
      // （基础等待已由 _renderSettle 覆盖，此处只叠加额外部分）。
      if (delayMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }

      String? jsResult;
      if (js != null && js.trim().isNotEmpty) {
        try {
          final raw = await controller.evaluateJavascript(source: js);
          jsResult = _normalizeJsResult(raw);
        } on Object catch (e) {
          debugPrint('[书源webView] js 执行失败(忽略): $e');
        }
        await Future<void>.delayed(_jsSettle);
      }

      // legado BackstageWebView：带 js 时返回 evaluateJavascript 的结果
      // （unescapeJson + 去引号），而非整页 HTML。此前恒返回 getHtml，
      // `java.webView(html,url,"JSON.stringify(...)")` 型源拿不到数据。
      if (jsResult != null && jsResult.isNotEmpty) return jsResult;

      final out = await controller.getHtml();
      if (out == null || out.isEmpty) return null;
      return out;
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

  /// 对齐 legado unescapeJson：字符串结果可能被 JSON 再编码一层
  /// （`"<div>..."` 或 `\"` 转义），先解一层引号再反转义。
  static String _normalizeJsResult(Object? raw) {
    if (raw == null) return '';
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
