/// 源评论登录：内嵌 WebView 完成登录，结束后手动回灌 Cookie。
///
/// 采用内嵌 [InAppWebView]（应用内网页视图）。用户在视图内完成登录后：
/// - 手动回灌：点击底部浮动按钮「获取 Cookie」，从 WebView 共享 Cookie 存储
/// 读取该源相关域的 Cookie 并同步到 [HttpFetcher]（内存 jar + CookieStore 落盘），
/// 随后关闭页面、由调用方经 SourceAuthManager.refreshLoginState 重新评估登录态。
/// Cookie 回灌只由用户手动触发，页面加载过程中不做任何自动捕获。
/// - 点击时短重试：Android 的 WebView 把登录响应里的 `set-cookie` 异步提交到
/// 系统 `CookieManager`，单次读取常常早于刷新。点击后在 ~2.5s 内做最多 6 次
/// 短重试容忍刷新延迟；仍是手动触发、非后台轮询，登录态未变不会持续重载。
///
/// 桌面端（InAppWebView 不可用）回退为提示使用「粘贴 Cookie」方式。
library;

import 'dart:async';
import 'dart:developer';

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/widgets/app_alert_dialog.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/platform/platform_service.dart';
import '../../../core/scraper/http_fetcher.dart';
import '../../../core/network/runtime/webview_source_network.dart';
import '../../../core/theme/app_tokens.dart';

/// 源登录「内嵌网页」页面。返回 `true` 表示 Cookie 已同步、应重新评估登录态。
class WebViewLoginScreen extends StatefulWidget {
  final PluginConfig source;

  const WebViewLoginScreen({super.key, required this.source, this.startUrl});

  /// 登录起始 URL 覆盖（legado 书源 loginUrl 为独立 URL 时传入；
  /// 缺省用媒体源 comments.login.url）。
  final String? startUrl;

  @override
  State<WebViewLoginScreen> createState() => _WebViewLoginScreenState();
}

class _WebViewLoginScreenState extends State<WebViewLoginScreen> {
  @override
  void initState() {
    super.initState();
    // 源声明的 UA 可能极简/与 WebView 环境不符（例如只有 `Mozilla/5.0`），
    // 且与能过 turnstile 的 WebView 默认 Android UA 不一致 → CF 600010。
    // 登录前把相关 host 钉为完整浏览器 UA（Android 移动版），登录页与回灌后
    // 的抓取请求同 UA，cf_clearance 才有效。
    _applyFullBrowserUa();
    // 让登录 WebView 跟随源网络覆盖（hosts/DoH/手动代理）：在线浏览/嗅探/验证
    // 兜底均已接入，本页此前漏接 → 登录页直连系统 DNS 命中污染（Android）或
    // 挂不上 --proxy-server 环境（Windows），整页加载失败。best-effort，
    // apply 失败时照常打开 WebView（_env 为 null，等同旧行为）。
    _applyFuture = WebviewSourceNetwork.instance
        .applyForSource(widget.source)
        .then((_) {
      if (!mounted) return;
      setState(() {
        _env = WebviewSourceNetwork.instance.activeEnvironment;
        _envReady = true;
      });
    });
  }

  @override
  void dispose() {
    final apply = _applyFuture;
    if (apply != null) {
      // dispose 先于 apply 完成时，等 apply 落地（含引用计数自增）后再释放。
      unawaited(apply.whenComplete(
        () => WebviewSourceNetwork.instance.releaseForSource(),
      ));
    }
    super.dispose();
  }

  /// 把本源登录涉及的 host（登录地址 + 站点主域）UA 覆盖为完整浏览器 UA。
  void _applyFullBrowserUa() {
    try {
      final String ua = HttpFetcher.instance.fullBrowserUserAgent();
      final String? loginHost =
          Uri.tryParse(widget.source.comments?.login?.url ?? '')?.host;
      final String? baseHost = Uri.tryParse(widget.source.site.baseUrl)?.host;
      final Set<String> hosts = <String>{};
      if (loginHost != null && loginHost.isNotEmpty) hosts.add(loginHost);
      if (baseHost != null && baseHost.isNotEmpty) hosts.add(baseHost);
      for (final h in hosts) {
        HttpFetcher.instance.registerHostUserAgent(h, ua);
      }
    } catch (_) {
      // UA 覆盖失败不影响登录主流程。
    }
  }

  /// 当前页面地址（onLoadStop 同步维护；getUrl() 是 Future 不能同步用）。
  String? _currentPageUrl;

  /// WebView 控制器：登录完成后直接读它的实时 Cookie 存储（比系统等异步刷新
  /// 更即时），避免「点获取 Cookie 时 set-cookie 还没提交到系统 CookieManager」。
  InAppWebViewController? _controller;

  /// 防止浮动按钮重复 pop。
  bool _popped = false;

  /// WebView2 环境（Windows --proxy-server 跟随）；其余平台 / 无覆盖时为 null。
  WebViewEnvironment? _env;

  /// 网络跟随就绪前不创建 WebView：env 是创建期参数后补无效（Windows），
  /// Android 也避免首屏请求抢在 ProxyController 覆盖生效前直连污染 DNS。
  bool _envReady = false;

  /// applyForSource 的在途 Future：dispose 时先等它完成再 release，保证引用
  /// 计数严格配对（apply 在 `_refCount++` 前返回时 release 会空转）。
  Future<void>? _applyFuture;

  CommentsLoginConfig? get _login => widget.source.comments?.login;

  String get _loginUrl => widget.startUrl ?? _login?.url ?? '';

  /// 是否支持内嵌网页（移动端 + Windows；Windows 经引擎 B 的 WebView2
  /// --proxy-server 环境跟随打开，见 [WebviewSourceNetwork]）。桌面其余端/Web
  /// 回退「粘贴 Cookie」提示。
  bool get _supported =>
      PlatformService.instance.isAndroid ||
      PlatformService.instance.isIOS ||
      PlatformService.instance.isWindows;

  /// Cookie 存储读取器：Windows 登录 WebView 挂在 --proxy-server 的 WebView2
  /// 环境上，其 cookie 存储与默认环境隔离——读取必须绑定同一环境，否则读到空
  /// 存储（「WebView 里已登录但取不到 Cookie」的根因）。移动端 activeEnvironment
  /// 为 null，与全局共享存储行为完全一致。
  CookieManager _cookieManager() => CookieManager.instance(
        webViewEnvironment: WebviewSourceNetwork.instance.activeEnvironment,
      );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.sourceLogin)),
      body: !_supported
          ? _buildUnsupported(l10n)
          // 网络跟随就绪前不创建 WebView（env 是创建期参数）。apply 为
          // best-effort，失败也会置 _envReady（_env 为 null → 等同旧行为）。
          : (_envReady
              ? _buildWebView(l10n)
              : const Center(child: CircularProgressIndicator())),
      floatingActionButton: _supported
          ? FloatingActionButton.extended(
              onPressed: _onGetCookie,
              icon: const Icon(Icons.cookie_rounded),
              label: Text(l10n.getCookie),
            )
          : null,
    );
  }

  /// 内嵌网页视图：用站点 baseUrl 的 UA 登录（与后续抓取一致，避免会话绑定到
  /// 不同 UA 被判失效）。
  Widget _buildWebView(AppLocalizations l10n) {
    final String ua = HttpFetcher.instance.userAgentForUrl(
      widget.source.site.baseUrl,
    );
    return InAppWebView(
      // 网络/代理环境跟随：本页 initState 已 applyForSource（源登录此前漏接，
      // 登录页一直没跟随 hosts），构造时挂上 apply 结果环境（Windows）；
      // Android 经 ProxyController 全局覆盖，此处保持 null 即可。
      webViewEnvironment: _env,
      initialUrlRequest: URLRequest(url: WebUri(_loginUrl)),
      initialSettings: InAppWebViewSettings(userAgent: ua),
      onWebViewCreated: (controller) => _controller = controller,
      onLoadStop: (_, url) {
        if (url != null) _currentPageUrl = url.toString();
        // 不做任何自动捕获：Cookie 回灌只由用户点「获取 Cookie」手动触发
        // （用户明确要求——自动抓取会在未登录时把公开页 cookie 也灌进来）。
      },
    );
  }

  /// 浮动按钮：「获取 Cookie」——读取 WebView 共享 Cookie 并回灌一次，随后退出。
  ///
  /// 取不到登录态 Cookie 时不退出页面，而是弹出诊断弹窗，直接列出系统 Cookie
  /// 存储里本源相关 cookie 的「名@域」（不含值），便于确认「WebView 里已登录但
  /// 系统存储读不到」的根因，而不是只给一句模糊提示。
  Future<void> _onGetCookie() async {
    final ok = await _syncCookies();
    if (!mounted) return;
    if (ok) {
      if (!_popped) {
        _popped = true;
        Navigator.of(context).pop(true);
      }
    } else {
      final AppLocalizations l10n = AppLocalizations.of(context);
      final summary = await _cookieDiagnosisSummary();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AppAlertDialog(
          title: Text(l10n.cookieNotFoundHint),
          content: SingleChildScrollView(child: Text(summary)),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.ok),
            ),
          ],
        ),
      );
    }
  }

  /// 桌面/Web 回退：提示使用「粘贴 Cookie」方式登录。
  Widget _buildUnsupported(AppLocalizations l10n) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.web_asset_off_rounded,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppTokens.spaceMd),
            Text(
              l10n.webviewLoginUnsupported,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 本次登录涉及的目标地址：当前页面（跳转后的实际域）+ 登录页 + 站点主域。
  List<Uri> _targetUris() {
    final uris = <String, Uri>{};
    void add(String? url) {
      final uri = Uri.tryParse(url ?? '');
      if (uri != null && uri.host.isNotEmpty) uris[uri.host] = uri;
    }

    add(_currentPageUrl);
    add(_loginUrl);
    add(widget.source.site.baseUrl);
    for (final d in widget.source.network?.cookieDomains ?? const <String>[]) {
      final h = d.startsWith('.') ? d.substring(1) : d;
      if (h.isNotEmpty) add('https://$h');
    }
    return uris.values.toList();
  }

  /// 从 WebView 共享 Cookie 存储取回各相关域的 Cookie 并回灌到 [HttpFetcher]
  /// （内存 jar + CookieStore 落盘）。
  ///
  /// 外层 [_syncCookies] 做最多 6 次短重试（每次间隔 ~500ms，约 2.5s），容忍 Android
  /// 把登录响应里的 `set-cookie` 异步提交到系统 CookieManager 的刷新延迟（单次点击
  /// 常早于刷新，导致「登录了但点获取 Cookie 取不到 / 仍显示未登录」——旧版靠
  /// 2s 轮询能取到正是因为这个延迟）。每次尝试内部按优先级读取：
  /// ① 实时控制器 Cookie：直接读 [InAppWebViewController] 当前 WebView 的存储，
  /// 最即时，登录刚完成即可拿到会话；
  /// ② 系统 CookieManager 直读：经原生通道 `nexhub/system_cookie` 读
  /// `android.webkit.CookieManager.getCookie(url)`（对齐常见原生客户端
  /// 登录后轮询系统 CookieManager 的做法）；
  /// ③ flutter_inappwebview CookieManager 逐域兜底；
  /// ④ 全量 [getAllCookies] 兜底：覆盖登录页停在子域 / Path 非 / 等情况。
  /// 读取**不早退**：任一路径拿到即用 [HttpFetcher.syncCookies] 回灌；随后按
  /// checkCookie 键名判定本次是否已拿到登录态 Cookie（命中才视为成功、退出重试），
  /// 避免只拿到 cf_clearance 却漏掉会话而被误判未登录。
  Future<bool> _syncCookies() async {
    const int maxAttempts = 6;
    const Duration retryGap = Duration(milliseconds: 500);
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      if (await _readOnce(attempt)) return true;
      if (attempt < maxAttempts - 1) {
        await Future<void>.delayed(retryGap);
      }
    }
    return false;
  }

  /// 单次尝试：按 ①~④ 优先级读取各相关域 Cookie 并回灌，返回 jar 中是否已出现
  /// 声明为登录态的 checkCookie 键（如 `sessionid`）。
  ///
  /// [attempt] 仅用于诊断日志（标记第几次重试），不影响读取逻辑。
  Future<bool> _readOnce(int attempt) async {
    // 目标域集合（当前页 / 登录页 / 站点主域），用于圈定「本源相关」范围，
    // 避免把 Cloudflare 挑战域等无关 cookie 回灌到 jar。
    final List<Uri> targets = _targetUris();
    final Set<String> targetHosts = targets
        .map((u) => u.host.toLowerCase())
        .where((h) => h.isNotEmpty)
        .toSet();

    /// 解析 cookie 归属 host：Domain 优先；为空（host-only cookie）时归入目标主域，
    /// 否则会被旧实现 `if (d == null) continue` 漏掉。
    String? hostForCookie(Cookie c) {
      final String? d = c.domain;
      if (d != null && d.isNotEmpty) {
        return (d.startsWith('.') ? d.substring(1) : d).toLowerCase();
      }
      return targetHosts.isNotEmpty ? targetHosts.first : null;
    }

    bool isRelated(String host) => targetHosts.any((th) =>
        host == th || host.endsWith('.$th') || th.endsWith('.$host'));

    void ingest(Uri uri, String? header) {
      if (header != null && header.isNotEmpty) {
        HttpFetcher.instance.syncCookies(uri.host, header);
      }
    }

    // ① 实时控制器 Cookie（读该 WebView 实例自己的存储，最即时）。
    final InAppWebViewController? ctl = _controller;
    if (ctl != null) {
      for (final uri in targets) {
        try {
          final cookies = await _cookieManager().getCookies(
            url: WebUri('${uri.scheme}://${uri.host}'),
            webViewController: ctl,
          );
          log(
            'cookie-sync[尝试${attempt + 1}] 控制器[${uri.host}]=${cookies.length}个',
            name: 'nexhub',
          );
          final header = cookies
              .where((c) => c.value != null && c.value.toString().isNotEmpty)
              .map((c) => '${c.name}=${c.value}')
              .join('; ');
          ingest(uri, header);
        } catch (_) {
          // 单域失败不阻断其余域。
        }
      }
    }
    if (_jarHasLoginCookie()) return true;

    // ② 系统 CookieManager 直读（原生通道）。
    for (final uri in targets) {
      try {
        final header = await HttpFetcher.instance
            .systemCookieHeader('${uri.scheme}://${uri.host}');
        log(
          'cookie-sync[尝试${attempt + 1}] 系统[${uri.host}]=${header == null ? "null" : (header.isEmpty ? "空" : "len=${header.length}")}',
          name: 'nexhub',
        );
        ingest(uri, header);
      } catch (_) {
        // 单域失败不阻断其余域。
      }
    }
    if (_jarHasLoginCookie()) return true;

    // ③ flutter_inappwebview CookieManager 逐域兜底。
    for (final uri in targets) {
      try {
        final cookies = await _cookieManager().getCookies(
          url: WebUri('${uri.scheme}://${uri.host}'),
        );
        final header = cookies
            .where((c) => c.value != null && c.value.toString().isNotEmpty)
            .map((c) => '${c.name}=${c.value}')
            .join('; ');
        ingest(uri, header);
      } catch (_) {
        // 单域失败不阻断其余域。
      }
    }
    if (_jarHasLoginCookie()) return true;

    // ④ 全量兜底：按 host 分组后整组回灌（覆盖登录页停在子域 / Path 非 / 等情况）。
    try {
      final List<Cookie> all = await _cookieManager().getAllCookies();
      final Map<String, List<Cookie>> byHost = <String, List<Cookie>>{};
      for (final Cookie c in all) {
        final String? host = hostForCookie(c);
        if (host == null || host.isEmpty) continue;
        if (!isRelated(host)) continue;
        byHost.putIfAbsent(host, () => <Cookie>[]).add(c);
      }
      byHost.forEach((host, list) {
        final header = list
            .where((c) => c.value != null && c.value.toString().isNotEmpty)
            .map((c) => '${c.name}=${c.value}')
            .join('; ');
        if (header.isNotEmpty) {
          HttpFetcher.instance.syncCookies(host, header);
        }
      });
    } catch (_) {
      // getAllCookies 不支持时忽略，①②③ 已兜底。
    }

    return _jarHasLoginCookie();
  }

  /// jar 中是否出现声明为登录态的 checkCookie 键（精确或前缀匹配，如某源
  /// 的 `sessionid`；配置若写 `session` 也能靠前缀命中）。命中才视为本次取 Cookie
  /// 成功，避免只拿到 cf_clearance 却漏掉会话而被误判未登录。
  bool _jarHasLoginCookie() {
    final key = widget.source.comments?.login?.checkCookie;
    if (key == null || key.isEmpty) return false;
    final pattern = RegExp('(^|;\\s*)${RegExp.escape(key)}=');
    for (final uri in _targetUris()) {
      final header = HttpFetcher.instance.getCookieHeader(uri.host);
      if (header == null || header.isEmpty) continue;
      if (pattern.hasMatch(header)) return true;
      for (final part in header.split(';')) {
        final eq = part.indexOf('=');
        if (eq <= 0) continue;
        final name = part.substring(0, eq).trim();
        if (name == key || name.startsWith(key)) return true;
      }
    }
    return false;
  }

  /// 取 Cookie 失败时的屏上诊断：用 Android 已实现的 [CookieManager.getCookies]
  /// 按域枚举本登录涉及的各目标地址的 cookie（含「名@域」，不含值），并对比系统原生通道，
  /// 以确认「WebView 里已登录但系统存储读不到」的根因。
  ///
  /// 注意：`getAllCookies` 在 flutter_inappwebview 的 Android 实现里是 UnimplementedError
  /// （系统 `android.webkit.CookieManager` 没有 getAllCookies API），所以枚举只能按域。
  Future<String> _cookieDiagnosisSummary() async {
    final buf = StringBuffer();
    buf.writeln('WebView 控制器: ${_controller != null ? "已就绪" : "为空（无法读实时 Cookie）"}');
    buf.writeln('期望登录态 cookie 键: ${widget.source.comments?.login?.checkCookie ?? "(未声明)"}');
    buf.writeln('--- 系统 Cookie 存储探测（按域）---');
    final List<Uri> targets = _targetUris();
    int totalShown = 0;
    for (final Uri uri in targets) {
      // ① 插件 getCookies(url) —— Android 已实现，返回该 url 的 cookie 列表
      try {
        final List<Cookie> cookies = await _cookieManager().getCookies(
          url: WebUri('${uri.scheme}://${uri.host}'),
        );
        if (cookies.isEmpty) {
          buf.writeln('${uri.host}: （无）');
        } else {
          buf.writeln('${uri.host} (${cookies.length} 个):');
          for (final Cookie c in cookies) {
            buf.writeln('  • ${c.name}@${c.domain ?? "host-only"} (path=${c.path ?? "/"})');
            totalShown++;
          }
        }
      } catch (e) {
        buf.writeln('${uri.host}: 读取失败 $e');
      }
      // ② 对比：系统原生通道（nexhub/system_cookie）
      try {
        final String? raw = await HttpFetcher.instance
            .systemCookieHeader('${uri.scheme}://${uri.host}');
        buf.writeln('  ↳ 系统通道[${uri.host}]: ${raw == null ? "null" : (raw.isEmpty ? "空" : "len=${raw.length}")}');
      } catch (e) {
        buf.writeln('  ↳ 系统通道失败: $e');
      }
    }
    if (totalShown == 0) {
      buf.writeln('');
      buf.writeln('⚠ 系统存储里没有任何该站点相关的 cookie。');
      buf.writeln('  最可能的根因：登录其实没真正完成（Cloudflare Turnstile 拦了表单），');
      buf.writeln('  请确认 WebView 里能看到你的用户名/已登录标识，而不是只看到公开首页。');
    }
    buf.writeln('--- 本源 jar（回灌目标）---');
    for (final String h in targets.map((u) => u.host).toSet()) {
      final String? v = HttpFetcher.instance.getCookieHeader(h);
      buf.writeln('jar[$h]: ${v == null ? "空" : "含sessionid=${v.contains('sessionid=')} (len=${v.length})"}');
    }
    return buf.toString();
  }
}
