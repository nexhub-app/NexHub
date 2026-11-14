/// WebView 验证页面（文档 验证流程）。
///
/// 当 [VerificationRequiredException] 被捕获时，UI 层导航到此页面。
/// 用户在浏览器中完成验证（Cloudflare / CAPTCHA / 滑块），返回后点击
/// 「已完成验证，重试」按钮，由调用方重试原始请求。
///
/// 在支持 WebView 的移动平台上可后续扩展为内嵌 WebView + Cookie 同步；
/// 当前实现使用 [url_launcher] 打开系统浏览器作为通用回退方案。
///
/// 增强：当传入 [WebViewExtractionRequest] 时切换为内嵌 [InAppWebView]
/// 模式，加载页面让用户完成验证，再点击「用此页抽取」按钮执行 [jsExtractor]
/// 脚本抽取真实地址回传给调用方；抽取失败时回退到 [url_launcher] 手动流程。
///
/// 嗅探兜底（源视频路由通用）：内嵌 WebView 在文档起始注入嗅探钩子
/// （见 [SnifferBridge]），以「网络拦截 + DOM 检测 + API 钩子」捕获视频地址；
/// 当 [jsExtractor] 主链路未解出地址时，自动回退到已捕获的首个可播放视频地址
/// （仅作兜底，不改动既有解析主链路）。
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/resolver/webview_resolver.dart';
import '../../../core/scraper/http_fetcher.dart';
import '../../../core/network/runtime/webview_source_network.dart';
import '../../../core/scraper/verification_detector.dart';
import '../../../core/sniffer/sniffer_bridge.dart' show SnifferBridge;
import '../../../core/sniffer/sniffer_engine.dart' show SnifferEngine;
import '../../../core/sniffer/sniffer_models.dart' show SniffFilter;
import '../../../core/theme/app_tokens.dart';
import '../../browser/presentation/http_browser_screen.dart';
import 'package:nexhub/core/navigation/app_page_route.dart';

/// 验证结果。
enum VerificationResult {
  /// 用户表示已完成验证，需要重试。
  done,

  /// 用户取消。
  cancelled,
}

/// 嗅探兜底解析出的最佳可播放目标（记录类型）。
///
/// [mode] 为 'http'（真实直链，可交给外部播放器）或 'webview'（仅 blob/mse，只能在页内播放）。
typedef _SnifferPlay = ({String mode, String url, String ref});

/// WebView 抽取/验证流程的最终结果。
///
/// 调用方优先判断 [extractedUrl] 是否非空：非空则直接用作解析结果，
/// 否则按 [result] 决定是否重试原始请求。
class WebViewExtractionOutcome {
  final VerificationResult result;
  final String? extractedUrl;
  final String? renderedHtml;

  /// 抽取地址配套的防盗链 Referer（嗅探捕获时记录；可空）。
  final String? extractedReferer;

  const WebViewExtractionOutcome({
    required this.result,
    this.extractedUrl,
    this.renderedHtml,
    this.extractedReferer,
  });

  /// 用户已完成验证并希望重试。
  bool get shouldRetry => result == VerificationResult.done;

  /// 是否成功抽取到地址。
  bool get hasExtractedUrl => extractedUrl != null && extractedUrl!.isNotEmpty;

  /// 是否成功取回渲染后 HTML。
  bool get hasRenderedHtml => renderedHtml != null && renderedHtml!.isNotEmpty;
}

/// WebView 验证页面。
///
/// [verificationUrl] 是触发验证的 URL；[onRetry] 是验证完成后回调。
/// [extractionRequest] 非空时启用 内嵌抽取流程。
/// [htmlRequest] 非空时启用「渲染后抽取」流程（取回整页渲染 HTML）。
class WebViewVerificationScreen extends StatefulWidget {
  final String verificationUrl;
  final VerificationRequiredException? exception;
  final WebViewExtractionRequest? extractionRequest;
  final WebViewHtmlRequest? htmlRequest;

  /// 嗅探解析模式：加载 [verificationUrl]（剧集播放页），仅靠嗅探链路
  /// （JS 钩子 + 网络拦截 + DOM 扫描）捕获真实视频地址，捕获到即自动回传。
  /// 用于常规解析（selectors/script）失败后的通用兜底，与源无关。
  final bool snifferMode;

  /// 嗅探解析模式加载页面用的请求头（可空）。
  final Map<String, String>? snifferHeaders;

  /// 嗅探解析超时时长（默认 20s）。作为「首选」解析（[snifferAutoPopOnTimeout]=true）
  /// 时建议调短，让未捕获到直链的源更快回退到手动解析。
  final Duration? snifferTimeout;

  /// 嗅探作为「首选」解析（而非最后兜底）时，超时后自动回传（不展示等待/取消界面），
  /// 让上层回退到源声明的手动解析。默认 false（兜底模式展示等待界面）。
  final bool snifferAutoPopOnTimeout;

  const WebViewVerificationScreen({
    super.key,
    required this.verificationUrl,
    this.exception,
    this.extractionRequest,
    this.htmlRequest,
    this.snifferMode = false,
    this.snifferHeaders,
    this.snifferTimeout,
    this.snifferAutoPopOnTimeout = false,
  });

  @override
  State<WebViewVerificationScreen> createState() =>
      _WebViewVerificationScreenState();
}

class _WebViewVerificationScreenState extends State<WebViewVerificationScreen> {
  bool _browserOpened = false;
  InAppWebViewController? _webViewController;

  /// 重定向加载完成哨兵：[_runExtraction] 跳转到外域播放器页后，用此 completer
  /// 等待该页 `onLoadStop`，再执行抽取脚本。flutter_inappwebview v6 的
  /// [InAppWebViewController] 无 `addOnLoadStopCallback`，故复用控件
  /// `onLoadStop` 回调驱动（见下方 InAppWebView 构造处的 onLoadStop）。
  Completer<void>? _loadStopCompleter;
  bool _pageLoaded = false;
  bool _extracting = false;
  String? _extractionError;

  /// 页内沉浸式播放模式：当嗅探仅捕获到 blob/mediasource（无法在 WebView 外播放）时，
  /// 切换为「页面即播放器」——保持 WebView 可见，由页内 MSE 播放器直接播放。
  bool _webviewPlayMode = false;

  /// 嗅探兜底：文档起始注入的钩子脚本（加载完成后非空，失败为空字符串）。
  String? _hookJs;

  /// 嗅探引擎。抽取/HTML 模式用进程级共享实例（结果跨屏累积可复用）；
  /// 嗅探解析模式用独立实例——共享实例可能残留其他站点的旧捕获，
  /// 会导致「自动回传」拿到不属于本集的地址。
  late final SnifferEngine _snifferEngine =
      widget.snifferMode ? SnifferEngine() : SnifferEngine.shared;

  /// 嗅探桥接器：注入 JS 钩子 + 注册 handler + onLoadResource 兜底。
  late final SnifferBridge _snifferBridge = SnifferBridge(_snifferEngine);

  /// 嗅探解析模式：是否已回传（防 onUpdate 多次触发重复 pop）。
  bool _snifferPopped = false;

  /// 当前页面地址（onLoadStop 同步维护；getUrl() 是 Future 不能同步用）。
  String? _currentPageUrl;

  /// 嗅探解析模式：超时提示计时器（超时仅提示，不强制退出）。
  Timer? _snifferTimeout;

  /// 嗅探解析模式：是否已超时（切换底栏文案，并放开 blob 页内播放兜底）。
  bool _snifferTimedOut = false;

  /// 是否启用 内嵌抽取流程。
  bool get _hasExtractionRequest => widget.extractionRequest != null;

  /// 是否启用「渲染后抽取」流程（取回整页渲染 HTML）。
  bool get _hasHtmlRequest => widget.htmlRequest != null;

  @override
  void initState() {
    super.initState();
    // CF turnstile 拒绝极简 UA（许多源声明如 `Mozilla/5.0`）→ 挑战 600010 无法
    // 通过。把验证域的 UA 钉为完整浏览器 UA（验证页 WebView 与回灌后的抓取
    // 请求同 UA，cf_clearance 才有效），源注册的极简 UA 被覆盖。
    _applyFullBrowserUa();
    _loadHook();
    if (widget.snifferMode) {
      _snifferEngine.onUpdate = _onSnifferModeUpdate;
      _snifferTimeout =
          Timer(widget.snifferTimeout ?? const Duration(seconds: 20), () {
        if (!mounted || _snifferPopped) return;
        if (widget.snifferAutoPopOnTimeout) {
          // 首选嗅探超时：自动回传，让上层回退到手动解析（不阻塞用户）。
          _snifferPopped = true;
          Navigator.of(context).pop(
            WebViewExtractionOutcome(result: VerificationResult.cancelled),
          );
          return;
        }
        setState(() => _snifferTimedOut = true);
        // 超时后若仅捕获到 blob/mse，退而求其次进入页内播放。
        final target = _resolveSnifferPlay();
        if (target != null && target.mode == 'webview') {
          setState(() => _webviewPlayMode = true);
        }
      });
    }
  }

  @override
  void dispose() {
    _snifferTimeout?.cancel();
    if (widget.snifferMode) _snifferEngine.onUpdate = null;
    super.dispose();
  }

  /// 嗅探解析模式：每次捕获更新时检查是否已有真实直链，有则立即回传。
  void _onSnifferModeUpdate() {
    if (!mounted || _snifferPopped) return;
    final target = _resolveSnifferPlay();
    if (target == null || target.mode != 'http') return;
    _snifferPopped = true;
    Navigator.of(context).pop(
      WebViewExtractionOutcome(
        result: VerificationResult.done,
        extractedUrl: target.url,
        extractedReferer:
            target.ref.isNotEmpty ? target.ref : widget.verificationUrl,
      ),
    );
  }

  /// 把验证域 host 的 UA 钉为完整浏览器 UA（覆盖源声明的极简 UA）。
  ///
  /// Cloudflare turnstile 会把仅含 `Mozilla/5.0` 的 UA 判定为不合法浏览器而
  /// 拒绝（600010）。验证页 WebView 与回灌后的抓取请求必须共享同一 UA，
  /// 否则下发的 cf_clearance 绑定验证时 UA、对抓取请求无效 → 反复验证。
  void _applyFullBrowserUa() {
    try {
      final String? host = Uri.tryParse(widget.verificationUrl)?.host;
      if (host == null || host.isEmpty) return;
      HttpFetcher.instance.registerHostUserAgent(
        host,
        HttpFetcher.instance.fullBrowserUserAgent(),
      );
    } catch (_) {
      // UA 覆盖失败不影响主流程。
    }
  }

  /// 加载嗅探钩子脚本（本地 asset，近乎瞬时）。失败时置空字符串，
  /// 此时仍保留 [onLoadResource] 被动兜底，不阻断主流程。
  Future<void> _loadHook() async {
    try {
      final js = await rootBundle.loadString('assets/sniffer/sniffer_hook.js');
      if (mounted) setState(() => _hookJs = js);
    } catch (_) {
      if (mounted) setState(() => _hookJs = '');
    }
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.tryParse(widget.verificationUrl);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (mounted) {
        setState(() => _browserOpened = true);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).webViewNotAvailable),
          ),
        );
      }
    }
  }

  /// 打开内置浏览器完成验证。
  ///
  /// 内置浏览器在「用此页完成验证」时会将最新 Cookie 同步到 [HttpFetcher]；
  /// 返回 `true` 时直接以 [VerificationResult.done] 结束，触发上层重试。
  Future<void> _openInternalBrowser() async {
    final used = await Navigator.of(context).push<bool>(
      AppPageRoute<bool>(
        builder: (_) => HttpBrowserScreen(
          initialUrl: widget.verificationUrl,
          verifyMode: true,
        ),
      ),
    );
    if (used == true && mounted) {
      // HttpBrowserScreen 已同步最新 Cookie，直接返回 done 触发重试。
      Navigator.of(context).pop(VerificationResult.done);
    }
  }

  void _finish() {
    // 同步 Cookie（best-effort：外部浏览器 Cookie 无法直接读取，
    // 但如果验证基于 IP/服务端 session，重试时 HttpFetcher 自带 Cookie 可能已够用）。
    final host = Uri.tryParse(widget.verificationUrl)?.host;
    if (host != null && widget.exception?.headers != null) {
      // 将已有 Cookie 头写回 HttpFetcher 以保留已有会话。
      final cookieHeader = widget.exception!.headers?['Cookie'] ??
          widget.exception!.headers?['cookie'];
      if (cookieHeader != null) {
        HttpFetcher.instance.syncCookies(host, cookieHeader);
      }
    }
    Navigator.of(context).pop(VerificationResult.done);
  }

  /// Cookie 存储读取器：Windows 验证 WebView 挂在 --proxy-server 的 WebView2
  /// 环境上，其 cookie 存储与默认环境隔离——读取必须绑定同一环境，否则读到
  /// 空存储，cf_clearance 永远回灌不到 HttpFetcher → 验证通过后仍反复弹验证。
  /// 移动端 activeEnvironment 为 null，与全局共享存储行为一致。
  CookieManager _cookieManager() => CookieManager.instance(
        webViewEnvironment: WebviewSourceNetwork.instance.activeEnvironment,
      );

  /// 同步内嵌 WebView 的 Cookie 到 HttpFetcher（best-effort，跨域父域匹配）。
  Future<void> _syncWebviewCookies() async {
    try {
      final uri = Uri.tryParse(widget.verificationUrl);
      if (uri == null) return;
      final cookies = await _cookieManager().getCookies(
        url: WebUri('${uri.scheme}://${uri.host}'),
      );
      if (cookies.isEmpty) return;
      final cookieHeader = cookies
          .where((c) => c.value.isNotEmpty)
          .map((c) => '${c.name}=${c.value}')
          .join('; ');
      if (cookieHeader.isNotEmpty) {
        HttpFetcher.instance.syncCookies(uri.host, cookieHeader);
      }
    } catch (_) {
      // Cookie 读取失败不影响主流程。
    }
  }

  /// 执行 jsExtractor 脚本并解析回传地址。
  ///
  /// 兼容三种返回格式：原始 URL 字符串、JSON 对象（含 url/src/video 字段）、
  /// JSON 数组（取第一个有效 URL）。失败时返回 null 并设置 [_extractionError]。
  ///
  /// 通用重定向能力：jsExtractor 可返回 `webview:<url>` 前缀的指令，表示真实
  /// 地址需先在内嵌 WebView 中加载该 URL（例如 MacCMS 加密站需跳到解析中转
  /// 域，才能由站点自带解密函数解出直链）。此时自动加载目标页并再次执行同一
  /// jsExtractor（深度上限防呆），直到返回非前缀地址。向后兼容：无此前缀时
  /// 行为不变。
  Future<void> _runExtraction({int depth = 0, int attempt = 0}) async {
    final controller = _webViewController;
    final request = widget.extractionRequest;
    if (controller == null || request == null) return;
    setState(() {
      _extracting = true;
      _extractionError = null;
    });
    try {
      // 先同步 Cookie，让重试时 HttpFetcher 带上验证后的会话。
      await _syncWebviewCookies();
      final raw = await controller.evaluateJavascript(
        source: request.jsExtractor,
      );
      // 处理 `webview:` 前缀重定向（见 [_asRedirect]）。
      final redirect = _asRedirect(raw);
      if (redirect != null) {
        if (depth >= 3) {
          // 重定向超限：先尝试嗅探兜底，再报错。
          if (_trySnifferFallback()) return;
          if (mounted) {
            setState(() {
              _extracting = false;
              _extractionError = '抽取重定向次数过多，请检查源脚本';
            });
          }
          return;
        }
        final completer = Completer<void>();
        _loadStopCompleter = completer;
        await controller.loadUrl(
          urlRequest: URLRequest(url: WebUri(redirect)),
        );
        try {
          await completer.future.timeout(const Duration(seconds: 20));
        } finally {
          _loadStopCompleter = null;
        }
        return _runExtraction(depth: depth + 1, attempt: 0);
      }
      final extracted = _parseExtractedResult(raw);
      if (extracted != null && extracted.isNotEmpty) {
        if (mounted) {
          Navigator.of(context).pop(
            WebViewExtractionOutcome(
              result: VerificationResult.done,
              extractedUrl: extracted,
            ),
          );
        }
        return;
      }
      // 在解析中转域（已重定向，depth>=1）上，站点自带 decrypt() 可能尚未就绪
      // （脚本异步加载 / 域名锁校验），稍后重试同一页，避免误报「抽取失败」。
      if (depth >= 1 && attempt < 8) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (!mounted) return;
        return _runExtraction(depth: depth, attempt: attempt + 1);
      }
      // 嗅探兜底：jsExtractor 未抽到地址时，回退到钩子已捕获的首个视频地址
      // （典型如 MacCMS 加密站——player 直接注入 <video>/blob 直链，脚本抽不到
      // 但网络/DOM 层已拿到）。仅作兜底，不改动既有解析主链路。
      if (_trySnifferFallback()) return;
      // 抽取脚本返回空值或无法识别的格式，且嗅探也无收获。
      if (mounted) {
        setState(() {
          _extracting = false;
          _extractionError = AppLocalizations.of(context).extractNoResult;
        });
      }
    } catch (e) {
      // 抽取脚本抛异常：先尝试嗅探兜底，再回退到手动验证流程。
      if (_trySnifferFallback()) return;
      if (mounted) {
        setState(() {
          _extracting = false;
          _extractionError =
              '${AppLocalizations.of(context).extractFailed}: $e';
        });
      }
    }
  }

  /// 若 [raw] 是 `webview:<url>` 形式的重定向指令则返回目标 URL，否则 null。
  ///
  /// 同时兼容 evaluateJavascript 可能把字符串包成 JSON（带外层引号）的情况。
  String? _asRedirect(dynamic raw) {
    if (raw is! String) return null;
    var s = raw.trim();
    if (s.startsWith('"') && s.endsWith('"')) {
      try {
        final decoded = jsonDecode(s);
        if (decoded is String) s = decoded;
      } catch (_) {
        // 保留原字符串继续判断。
      }
    }
    if (s.startsWith('webview:')) {
      final target = s.substring('webview:'.length).trim();
      if (target.startsWith('http://') || target.startsWith('https://')) {
        return target;
      }
    }
    return null;
  }

  /// 解析 jsExtractor 返回值，兼容字符串/JSON 对象/JSON 数组三种格式。
  String? _parseExtractedResult(dynamic result) {
    if (result == null) return null;
    // 1. 字符串：直接当作 URL，或尝试 JSON 解码。
    if (result is String) {
      final trimmed = result.trim();
      if (trimmed.isEmpty) return null;
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        return trimmed;
      }
      try {
        final decoded = jsonDecode(trimmed);
        return _parseExtractedResult(decoded);
      } catch (_) {
        return null;
      }
    }
    // 2. List：递归取第一个有效 URL。
    if (result is List) {
      for (final item in result) {
        final parsed = _parseExtractedResult(item);
        if (parsed != null && parsed.isNotEmpty) return parsed;
      }
      return null;
    }
    // 3. Map：按常见字段优先级取值。
    if (result is Map) {
      const keys = <String>['url', 'src', 'video', 'file', 'source', 'link'];
      for (final key in keys) {
        final value = result[key];
        if (value is String && value.startsWith('http')) return value;
        if (value is List || value is Map) {
          final parsed = _parseExtractedResult(value);
          if (parsed != null && parsed.isNotEmpty) return parsed;
        }
      }
      return null;
    }
    return null;
  }

  /// 解析当前捕获结果中的「最佳可播放目标」。
  ///
  /// 优先级：
  /// 1. 真实 http(s) 直链（可在 WebView 外直接交给播放器）；
  /// 2. 仅 blob:/mediasource:/mse（无直链，只能在当前 WebView 页内播放）。
  /// 返回 null 表示无任何可播放目标。
  _SnifferPlay? _resolveSnifferPlay() {
    String? pageUrl;
    final videos = _snifferEngine.filtered(SniffFilter.video);
    for (final m in videos) {
      final u = m.url;
      if (u.startsWith('http://') || u.startsWith('https://')) {
        // 真实直链优先：可直接交给外部播放器。
        return (mode: 'http', url: u, ref: m.referer ?? '');
      }
      // blob:/mediasource:/mse —— 只能在当前页面内播放，记录页面地址备用。
      // 注意 getUrl() 是 Future，不能同步 toString；用 onLoadStop 维护的地址。
      pageUrl ??= _currentPageUrl ?? widget.verificationUrl;
    }
    if (pageUrl != null) {
      return (mode: 'webview', url: pageUrl, ref: '');
    }
    return null;
  }

  /// 嗅探兜底统一入口：
  /// - 捕获到真实 http(s) 直链 → 立即 pop 回传播放页；
  /// - 仅捕获到 blob/mediasource → 进入页内沉浸式播放模式（不出错）；
  /// - 无任何可播放目标 → 返回 false（由调用方显示抽取失败）。
  ///
  /// 集中处理 [_runExtraction] 的「脚本空 / 脚本异常 / 重定向超限」与 [_captureHtml]
  /// 的「渲染 HTML 无 video」等全部源视频解析失败分支，使嗅探成为通用兜底。
  bool _trySnifferFallback() {
    final target = _resolveSnifferPlay();
    if (target == null) return false;
    if (target.mode == 'http') {
      if (mounted) {
        Navigator.of(context).pop(
          WebViewExtractionOutcome(
            result: VerificationResult.done,
            extractedUrl: target.url,
            extractedReferer:
                target.ref.isNotEmpty ? target.ref : widget.verificationUrl,
          ),
        );
      }
      return true;
    }
    // webview 模式：保持 WebView 可见，由页内播放器直接播放（不弹错）。
    if (mounted) {
      setState(() => _webviewPlayMode = true);
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // 嗅探兜底钩子加载中：先占位，确保 WebView 创建时钩子脚本已就位。
    // 钩子为本地产 asset 读取，通常在一帧内完成。
    if (_hookJs == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.verificationRequired)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    // 嗅探解析模式：常规解析失败后的通用兜底（优先级最高，独占使用）。
    if (widget.snifferMode) {
      return _buildSnifferScaffold(context, l10n);
    }
    // 渲染后抽取：优先于 JS 抽取（二者不会同时出现）。
    if (_hasHtmlRequest) {
      return _buildHtmlCaptureScaffold(context, l10n);
    }
    // 有抽取请求时切换为内嵌 WebView 抽取视图。
    if (_hasExtractionRequest) {
      return _buildExtractionScaffold(context, l10n);
    }
    return _buildLegacyScaffold(context, l10n);
  }

  /// 嗅探解析视图：加载剧集播放页，纯靠嗅探链路捕获视频地址，捕获到自动回传。
  ///
  /// 与抽取视图的区别：无 jsExtractor、无手动抽取按钮——页面正常播放视频的
  /// 过程本身就会触发钩子/网络层捕获；捕获到 http 直链即 pop（见
  /// [_onSnifferModeUpdate]），仅 blob/mse 且超时则转页内播放。
  Widget _buildSnifferScaffold(BuildContext context, AppLocalizations l10n) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.snifferResolveTitle),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(
            const WebViewExtractionOutcome(
              result: VerificationResult.cancelled,
            ),
          ),
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Stack(
              children: <Widget>[
                InAppWebView(
                  // Windows 代理环境跟随（验证页由 apply 窗口打开）。
                  webViewEnvironment:
                      WebviewSourceNetwork.instance.activeEnvironment,
                  initialUrlRequest: URLRequest(
                    url: WebUri(widget.verificationUrl),
                    headers: widget.snifferHeaders,
                  ),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    mediaPlaybackRequiresUserGesture: false,
                    useShouldOverrideUrlLoading: true,
                    useShouldInterceptRequest: true,
                    useOnLoadResource: true,
                    // 过验证的 UA 必须与后续 HttpFetcher 重试的 UA 完全一致，
                    // 否则反爬把 Cookie 绑定到 UA+IP，UA 漂移→Cookie 失效→验证死循环。
                    userAgent: HttpFetcher.instance
                        .userAgentForUrl(widget.verificationUrl),
                  ),
                  initialUserScripts: _hookJs != null && _hookJs!.isNotEmpty
                      ? UnmodifiableListView<UserScript>(
                          <UserScript>[SnifferBridge.userScript(_hookJs!)],
                        )
                      : null,
                  onWebViewCreated: (controller) {
                    _webViewController = controller;
                    _snifferBridge.attach(controller);
                  },
                  shouldOverrideUrlLoading:
                      (controller, navigationAction) async {
                    return NavigationActionPolicy.ALLOW;
                  },
                  onLoadResource: (controller, resource) =>
                      _snifferBridge.onResource(resource.url?.toString()),
                  shouldInterceptRequest: (controller, request) async {
                    final h = request.headers;
                    final ref =
                        h == null ? null : (h['referer'] ?? h['Referer']);
                    _snifferBridge.onRequest(request.url.toString(), ref);
                    return null;
                  },
                  onLoadStop: (controller, url) async {
                    if (url != null) _currentPageUrl = url.toString();
                    if (!_pageLoaded && mounted) {
                      setState(() => _pageLoaded = true);
                    }
                    // MacCMS「系统安全验证」自动通过（详见 _autoClickMacCmsVerify）。
                    await _autoClickMacCmsVerify(controller);
                    await _snifferBridge.deepScan();
                  },
                ),
                if (!_pageLoaded)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
          _webviewPlayMode
              ? _buildWebviewPlayBar(context, l10n, scheme)
              : Container(
                  padding: EdgeInsets.fromLTRB(
                    AppTokens.spaceMd,
                    AppTokens.spaceSm,
                    AppTokens.spaceMd,
                    AppTokens.spaceMd + MediaQuery.paddingOf(context).bottom,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    border: Border(
                      top: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      if (!_snifferTimedOut) ...<Widget>[
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: AppTokens.spaceSm),
                      ],
                      Expanded(
                        child: Text(
                          _snifferTimedOut
                              ? l10n.snifferResolveTimeout
                              : l10n.snifferResolving,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(
                          const WebViewExtractionOutcome(
                            result: VerificationResult.cancelled,
                          ),
                        ),
                        child: Text(l10n.cancel),
                      ),
                    ],
                  ),
                ),
        ],
      ),
    );
  }

  /// 内嵌抽取视图：InAppWebView 加载页面 + 底部「用此页抽取」操作栏。
  Widget _buildExtractionScaffold(BuildContext context, AppLocalizations l10n) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) return;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.verificationRequired),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(
              const WebViewExtractionOutcome(
                result: VerificationResult.cancelled,
              ),
            ),
          ),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.open_in_browser_rounded),
              tooltip: l10n.openInBrowser,
              onPressed: _openInBrowser,
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            Expanded(
              child: Stack(
                children: <Widget>[
                  InAppWebView(
                    // Windows 代理环境跟随（验证页由 apply 窗口打开）。
                    webViewEnvironment:
                        WebviewSourceNetwork.instance.activeEnvironment,
                    initialUrlRequest: URLRequest(
                      url: WebUri(widget.verificationUrl),
                      headers: widget.extractionRequest?.headers,
                    ),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      mediaPlaybackRequiresUserGesture: false,
                      useShouldOverrideUrlLoading: true,
                      useShouldInterceptRequest: true,
                      // 插件默认 false：不开这个开关 onLoadResource 永远不回调。
                      useOnLoadResource: true,
                      // 过验证的 UA 必须与后续 HttpFetcher 重试的 UA 完全一致，
                      // 否则反爬把 Cookie 绑定到 UA+IP，UA 漂移→Cookie 失效→验证死循环。
                      userAgent: HttpFetcher.instance
                          .userAgentForUrl(widget.verificationUrl),
                    ),
                    initialUserScripts: _hookJs != null && _hookJs!.isNotEmpty
                        ? UnmodifiableListView<UserScript>(
                            <UserScript>[SnifferBridge.userScript(_hookJs!)],
                          )
                        : null,
                    onWebViewCreated: (controller) {
                      _webViewController = controller;
                      _snifferBridge.attach(controller);
                    },
                    shouldOverrideUrlLoading:
                        (controller, navigationAction) async {
                      return NavigationActionPolicy.ALLOW;
                    },
                    onLoadResource: (controller, resource) =>
                        _snifferBridge.onResource(resource.url?.toString()),
                    shouldInterceptRequest: (controller, request) async {
                      final h = request.headers;
                      final ref =
                          h == null ? null : (h['referer'] ?? h['Referer']);
                      _snifferBridge.onRequest(request.url.toString(), ref);
                      return null;
                    },
                    onLoadStop: (controller, url) async {
                      if (url != null) _currentPageUrl = url.toString();
                      if (!_pageLoaded && mounted) {
                        setState(() => _pageLoaded = true);
                      }
                      // 页面加载完成后立即同步 Cookie，确保后续抽取与会话一致。
                      await _syncWebviewCookies();
                      // MacCMS「系统安全验证」自动通过（详见 _autoClickMacCmsVerify）。
                      await _autoClickMacCmsVerify(controller);
                      // 若正在等待重定向页加载（抽取多级跳转），用此 completer 放行。
                      // v6 无 controller.addOnLoadStopCallback，复用本回调驱动。
                      if (_loadStopCompleter != null &&
                          !_loadStopCompleter!.isCompleted) {
                        _loadStopCompleter!.complete();
                      }
                      // 嗅探兜底：DOM 深度扫描（<video>/<source>/player_ 全局）。
                      await _snifferBridge.deepScan();
                    },
                  ),
                  if (!_pageLoaded)
                    const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),
            // 底部操作栏：抽取模式 or 页内沉浸式播放模式（blob/mse 兜底）。
            _webviewPlayMode
                ? _buildWebviewPlayBar(context, l10n, scheme)
                : Container(
                    padding: EdgeInsets.fromLTRB(
                      AppTokens.spaceMd,
                      AppTokens.spaceSm,
                      AppTokens.spaceMd,
                      AppTokens.spaceMd + MediaQuery.paddingOf(context).bottom,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      border: Border(
                        top: BorderSide(
                          color: scheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (_extractionError != null)
                          Padding(
                            padding: const EdgeInsets.only(
                                bottom: AppTokens.spaceSm),
                            child: Text(
                              _extractionError!,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: scheme.error,
                                  ),
                            ),
                          ),
                        if (_extracting)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: AppTokens.spaceSm),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                                const SizedBox(width: AppTokens.spaceSm),
                                Text(l10n.extracting),
                              ],
                            ),
                          )
                        else
                          FilledButton.icon(
                            onPressed: _pageLoaded ? _runExtraction : null,
                            icon: const Icon(Icons.auto_fix_high_rounded),
                            label: Text(l10n.extractFromPage),
                          ),
                        const SizedBox(height: AppTokens.spaceSm),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                l10n.extractHint,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppTokens.spaceSm),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(
                            const WebViewExtractionOutcome(
                              result: VerificationResult.done,
                            ),
                          ),
                          child: Text(l10n.verificationDone),
                        ),
                      ],
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  /// 页内沉浸式播放模式底部栏：当前 WebView 即播放器（blob/mse 无法在 WebView 外播放）。
  Widget _buildWebviewPlayBar(
      BuildContext context, AppLocalizations l10n, ColorScheme scheme) {
    final pageUrl =
        _webViewController?.getUrl()?.toString() ?? widget.verificationUrl;
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppTokens.spaceMd,
        AppTokens.spaceSm,
        AppTokens.spaceMd,
        AppTokens.spaceMd + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border(
          top: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
            child: Text(
              l10n.snifferInPagePlaying,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.primary,
                  ),
            ),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.copy_rounded),
                  label: Text(l10n.snifferCopyPageLink),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: pageUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.snifferCopy)),
                    );
                  },
                ),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: l10n.close,
                onPressed: () => Navigator.of(context).pop(
                  const WebViewExtractionOutcome(
                    result: VerificationResult.cancelled,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceXs),
          Text(
            l10n.snifferInPageHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  /// 渲染后抽取视图：InAppWebView 加载页面 + 底部「抓取本页渲染内容」操作栏。
  ///
  /// 与 JS 抽取不同，这里不执行脚本，而是等页面 JS 渲染完成后调用
  /// `controller.getHtml()` 取回完整 HTML，交回调用方用既有选择器解析。
  Widget _buildHtmlCaptureScaffold(
      BuildContext context, AppLocalizations l10n) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) return;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.verificationRequired),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(
              const WebViewExtractionOutcome(
                result: VerificationResult.cancelled,
              ),
            ),
          ),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.open_in_browser_rounded),
              tooltip: l10n.openInBrowser,
              onPressed: _openInBrowser,
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            Expanded(
              child: Stack(
                children: <Widget>[
                  InAppWebView(
                    // Windows 代理环境跟随（验证页由 apply 窗口打开）。
                    webViewEnvironment:
                        WebviewSourceNetwork.instance.activeEnvironment,
                    initialUrlRequest: URLRequest(
                      url: WebUri(widget.verificationUrl),
                      headers: widget.htmlRequest?.headers,
                    ),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      mediaPlaybackRequiresUserGesture: false,
                      useShouldOverrideUrlLoading: true,
                      useShouldInterceptRequest: true,
                      // 插件默认 false：不开这个开关 onLoadResource 永远不回调。
                      useOnLoadResource: true,
                      // 过验证的 UA 必须与后续 HttpFetcher 重试的 UA 完全一致，
                      // 否则反爬把 Cookie 绑定到 UA+IP，UA 漂移→Cookie 失效→验证死循环。
                      userAgent: HttpFetcher.instance
                          .userAgentForUrl(widget.verificationUrl),
                    ),
                    initialUserScripts: _hookJs != null && _hookJs!.isNotEmpty
                        ? UnmodifiableListView<UserScript>(
                            <UserScript>[SnifferBridge.userScript(_hookJs!)],
                          )
                        : null,
                    onWebViewCreated: (controller) {
                      _webViewController = controller;
                      _snifferBridge.attach(controller);
                    },
                    shouldOverrideUrlLoading:
                        (controller, navigationAction) async {
                      return NavigationActionPolicy.ALLOW;
                    },
                    onLoadResource: (controller, resource) =>
                        _snifferBridge.onResource(resource.url?.toString()),
                    shouldInterceptRequest: (controller, request) async {
                      final h = request.headers;
                      final ref =
                          h == null ? null : (h['referer'] ?? h['Referer']);
                      _snifferBridge.onRequest(request.url.toString(), ref);
                      return null;
                    },
                    onLoadStop: (controller, url) async {
                      if (url != null) _currentPageUrl = url.toString();
                      if (!_pageLoaded && mounted) {
                        setState(() => _pageLoaded = true);
                      }
                      // 页面加载完成后立即同步 Cookie，确保后续解析与会话一致。
                      await _syncWebviewCookies();
                      // MacCMS「系统安全验证」自动通过（详见 _autoClickMacCmsVerify）。
                      await _autoClickMacCmsVerify(controller);
                      // 嗅探兜底：DOM 深度扫描（<video>/<source>/player_ 全局）。
                      await _snifferBridge.deepScan();
                    },
                  ),
                  if (!_pageLoaded)
                    const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(
                AppTokens.spaceMd,
                AppTokens.spaceSm,
                AppTokens.spaceMd,
                AppTokens.spaceMd + MediaQuery.paddingOf(context).bottom,
              ),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                border: Border(
                  top: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (_extractionError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
                      child: Text(
                        _extractionError!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.error,
                            ),
                      ),
                    ),
                  if (_extracting)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: AppTokens.spaceSm),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: AppTokens.spaceSm),
                          Text(l10n.capturing),
                        ],
                      ),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _pageLoaded ? _captureHtml : null,
                      icon: const Icon(Icons.auto_fix_high_rounded),
                      label: Text(l10n.captureFromPage),
                    ),
                  const SizedBox(height: AppTokens.spaceSm),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          l10n.captureHint,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.spaceSm),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(
                      const WebViewExtractionOutcome(
                        result: VerificationResult.done,
                      ),
                    ),
                    child: Text(l10n.verificationDone),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 取回渲染后的整页 HTML 并回传。
  ///
  /// 先同步 Cookie，再调用 `controller.getHtml()` 拿到 JS 渲染完成后的完整
  /// HTML，交由调用方用既有选择器解析（修复「列表由 JS 动态渲染、静态抓取为空」）。
  /// MacCMS「系统安全验证」自动通过：当前页带「继续访问」按钮
  /// （`.verify_submit`，233动漫等 MacCMS 站搜索/筛选路由的拦截页）时自动点击。
  /// 站点自带 JS 会计算 token POST verify_check 后 `location.reload()` 出真实
  /// 内容，reload 会再次回调 onLoadStop。点击失败（jQuery 迟到等）不影响流程，
  /// 用户仍可手动点击——站点原按钮一直在。
  Future<void> _autoClickMacCmsVerify(InAppWebViewController controller) async {
    try {
      final clicked = await controller.evaluateJavascript(
        source:
            "(function(){var b=document.querySelector('.verify_submit');"
            'if(!b){return false;}b.click();return true;})()',
      );
      final hit = clicked == true || clicked == 'true';
      if (hit) {
        debugPrint(
          '[WebViewVerification] 检测到 MacCMS 系统安全验证页，已自动点击继续访问',
        );
      }
    } on Object {
      // JS 执行失败不影响既有流程：保留用户手动点击兜底。
    }
  }

  Future<void> _captureHtml() async {
    final controller = _webViewController;
    if (controller == null) return;
    setState(() {
      _extracting = true;
      _extractionError = null;
    });
    try {
      await _syncWebviewCookies();
      // webJs（legado URL 选项）：页面内执行取值脚本，返回值即响应体
      //（书源 URL 选项声明时由 resolver 经 WebViewHtmlRequest.js 传入）。
      final webJs = widget.htmlRequest?.js;
      if (webJs != null && webJs.trim().isNotEmpty) {
        var text = (await controller.evaluateJavascript(source: webJs))
            ?.toString()
            .trim() ??
            '';
        // 兼容 evaluateJavascript 把字符串包成 JSON（带外层引号）的情况。
        if (text.startsWith('"') && text.endsWith('"')) {
          try {
            final decoded = jsonDecode(text);
            if (decoded is String) text = decoded;
          } catch (_) {}
        }
        if (text.isNotEmpty && text != 'null' && mounted) {
          Navigator.of(context).pop(
            WebViewExtractionOutcome(
              result: VerificationResult.done,
              renderedHtml: text,
            ),
          );
          return;
        }
      }
      final html = await controller.getHtml();
      // 守卫：当前仍是验证/挑战页时回灌只会让选择器解析出 0 条并被缓存成
      // 「正常内容」（MacCMS 系统安全验证页实测 5KB、结构完整）。此时不 pop，
      // 顺带再点一次「继续访问」，提示用户等页面出真实内容后再抓取。
      if (html != null &&
          html.isNotEmpty &&
          VerificationDetector.isVerificationRequired(
            statusCode: 200,
            body: html,
          )) {
        await _autoClickMacCmsVerify(controller);
        if (mounted) {
          setState(() {
            _extracting = false;
            _extractionError = AppLocalizations.of(context).verificationRequired;
          });
        }
        return;
      }
      if (html != null && html.isNotEmpty) {
        if (mounted) {
          Navigator.of(context).pop(
            WebViewExtractionOutcome(
              result: VerificationResult.done,
              renderedHtml: html,
            ),
          );
        }
        return;
      }
      // 渲染 HTML 无 video 标签：尝试嗅探兜底（钩子已注入同一 WebView）。
      if (_trySnifferFallback()) return;
      if (mounted) {
        setState(() {
          _extracting = false;
          _extractionError = AppLocalizations.of(context).extractNoResult;
        });
      }
    } catch (e) {
      // getHtml 抛异常：先尝试嗅探兜底，再回退到手动验证流程。
      if (_trySnifferFallback()) return;
      if (mounted) {
        setState(() {
          _extracting = false;
          _extractionError =
              '${AppLocalizations.of(context).extractFailed}: $e';
        });
      }
    }
  }

  /// 原有 url_launcher 手动验证视图（保留不动）。
  Widget _buildLegacyScaffold(BuildContext context, AppLocalizations l10n) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) return;
        // 返回 cancelled
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.verificationRequired),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () =>
                Navigator.of(context).pop(VerificationResult.cancelled),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.spaceXl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.verified_user_rounded,
                  size: 72,
                  color: scheme.primary.withValues(alpha: 0.7),
                ),
                const SizedBox(height: AppTokens.spaceLg),
                Text(
                  l10n.verificationRequired,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppTokens.spaceMd),
                Text(
                  l10n.verificationHint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                // 显示需要验证的 URL（截断显示）
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceMd,
                    vertical: AppTokens.spaceSm,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                  ),
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Text(
                    widget.verificationUrl,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                        ),
                  ),
                ),
                const SizedBox(height: AppTokens.spaceXl),
                FilledButton.icon(
                  onPressed: _openInBrowser,
                  icon: const Icon(Icons.open_in_browser_rounded),
                  label: Text(l10n.openInBrowser),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                FilledButton.tonalIcon(
                  onPressed: _openInternalBrowser,
                  icon: const Icon(Icons.travel_explore_rounded),
                  label: Text(l10n.openInternalBrowser),
                ),
                if (_browserOpened) ...<Widget>[
                  const SizedBox(height: AppTokens.spaceMd),
                  FilledButton.tonalIcon(
                    onPressed: _finish,
                    icon: const Icon(Icons.check_circle_rounded),
                    label: Text(l10n.verificationDone),
                  ),
                ],
                const SizedBox(height: AppTokens.spaceLg),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(VerificationResult.cancelled),
                  child: Text(l10n.cancel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 便捷方法：导航到验证页面并等待结果。
///
/// 返回 `true` 表示用户已完成验证并希望重试。
Future<bool> navigateToVerification(
  BuildContext context, {
  required String url,
  VerificationRequiredException? exception,
}) async {
  // 需要验证时直接打开应用内浏览器（InAppWebView）过验证，省去先在提示页点
  // 「打开内置浏览器」的手动步骤（用户诉求：自动打开验证页验证）。WebView 处于
  // verifyMode：一旦页面加载到真实（非挑战）页，自动把会话 Cookie 同步回
  // HttpFetcher 并关闭返回 true 触发重试；用户也可手动点菜单「用此页完成验证」。
  // exception 仅 legacy 提示页曾用到，此处不再需要。
  final used = await Navigator.of(context).push<bool>(
    AppPageRoute<bool>(
      builder: (_) => HttpBrowserScreen(initialUrl: url, verifyMode: true),
    ),
  );
  return used == true;
}

/// 便捷方法：导航到抽取页面并等待结果。
///
/// 调用方优先判断 [WebViewExtractionOutcome.hasExtractedUrl]：
/// - 命中则直接使用 [WebViewExtractionOutcome.extractedUrl] 作为解析结果。
/// - 未命中且 [WebViewExtractionOutcome.shouldRetry] 时，回退到重试原始请求。
/// - 返回 null 表示用户取消。
Future<WebViewExtractionOutcome?> navigateToExtraction(
  BuildContext context, {
  required WebViewExtractionRequest request,
}) async {
  return Navigator.of(context).push<WebViewExtractionOutcome>(
    AppPageRoute<WebViewExtractionOutcome>(
      builder: (_) => WebViewVerificationScreen(
        verificationUrl: request.url,
        exception: null,
        extractionRequest: request,
      ),
    ),
  );
}

/// 嗅探解析便捷方法：加载剧集播放页，纯靠嗅探链路捕获真实视频地址。
///
/// 可作为「首选」解析（[autoPopOnTimeout]=true，[timeout] 调短）也可作「最后兜底」。
/// 捕获到 http 直链自动回传（[WebViewExtractionOutcome.extractedUrl] +
/// [WebViewExtractionOutcome.extractedReferer]）；返回 null 表示用户取消。
Future<WebViewExtractionOutcome?> navigateToSnifferCapture(
  BuildContext context, {
  required String url,
  Map<String, String>? headers,
  Duration? timeout,
  bool autoPopOnTimeout = false,
}) async {
  return Navigator.of(context).push<WebViewExtractionOutcome>(
    AppPageRoute<WebViewExtractionOutcome>(
      builder: (_) => WebViewVerificationScreen(
        verificationUrl: url,
        exception: null,
        snifferMode: true,
        snifferHeaders: headers,
        snifferTimeout: timeout,
        snifferAutoPopOnTimeout: autoPopOnTimeout,
      ),
    ),
  );
}

/// 渲染后抽取便捷方法：导航到 WebView 渲染页面，取回整页渲染 HTML 并等待结果。
///
/// 调用方优先判断 [WebViewExtractionOutcome.hasRenderedHtml]：
/// - 命中则直接用 [WebViewExtractionOutcome.renderedHtml] 复用源选择器解析。
/// - 返回 null 表示用户取消。
Future<WebViewExtractionOutcome?> navigateToHtmlCapture(
  BuildContext context, {
  required WebViewHtmlRequest request,
}) async {
  return Navigator.of(context).push<WebViewExtractionOutcome>(
    AppPageRoute<WebViewExtractionOutcome>(
      builder: (_) => WebViewVerificationScreen(
        verificationUrl: request.url,
        exception: null,
        htmlRequest: request,
      ),
    ),
  );
}
