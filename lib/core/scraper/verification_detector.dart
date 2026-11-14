/// 验证检测与异常定义。
///
/// 任一拦截路径（详情/播放/浏览/搜索/预加载/headless）命中验证特征时，
/// HttpFetcher 抛出 [VerificationRequiredException]；需要 WebView 过验证时
/// WebViewResolver 抛出 [WebViewRequiredException]。上层据此弹验证页并同步 Cookie 后重试。
library;

/// 需要网页验证（401/403/Cloudflare/CAPTCHA/滑块）。
class VerificationRequiredException implements Exception {
  final String url;
  final Map<String, String>? headers;
  final String? body;
  final int? statusCode;

  /// 该请求的 URL 选项声明了 webView:true（legado useWebView 语义）——
  /// 上层据此优先走 WebView 渲染回灌而非直连重试。
  final bool preferWebView;

  const VerificationRequiredException({
    required this.url,
    this.headers,
    this.body,
    this.statusCode,
    this.preferWebView = false,
  });

  @override
  String toString() =>
      'VerificationRequiredException(status=$statusCode, url=$url)';
}

/// 该源/路由需要走 WebView（headless 加载 + 过验证/取 HTML）。
class WebViewRequiredException implements Exception {
  final String url;
  final Map<String, String>? headers;

  const WebViewRequiredException(this.url, {this.headers});

  @override
  String toString() => 'WebViewRequiredException(url=$url)';
}

/// 单个源解析失败（错误隔离用，不影响其他源）。
class SourceResolveException implements Exception {
  final String sourceId;
  final String apiName;
  final String message;

  const SourceResolveException({
    required this.sourceId,
    required this.apiName,
    required this.message,
  });

  @override
  String toString() =>
      'SourceResolveException($sourceId/$apiName): $message';
}

/// HTTP 4xx/5xx 错误（非验证类）。
///
/// HttpFetcher 在通过验证检测后，若状态码仍 ≥ 400（如 404/500/502），
/// 抛出此异常以便上层显示明确错误 + 重试，而非把错误页 body 当成正常
/// 响应交给解析器，导致静默空列表。
class HttpStatusException implements Exception {
  final String url;
  final int statusCode;
  final String? body;

  const HttpStatusException({
    required this.url,
    required this.statusCode,
    this.body,
  });

  @override
  String toString() => 'HttpStatusException($statusCode, url=$url)';
}

class VerificationDetector {
  VerificationDetector._();

  /// 主动挑战标记：仅出现在真正的验证/反爬挑战页（5秒盾、滑块、CAPTCHA、
  /// Cloudflare 真实「Just a moment」页），正常内容页绝不会出现。命中即判为验证页。
  ///
  /// 注意：避免把整段域名作为特征——源站正常页面里也会在
  /// URL/脚本/链接中出现自己的域名，会导致整站正常响应被误判为验证页，
  /// 进而触发验证循环（用户看到「需要验证」但验证完仍打不开）。相关源的
  /// 滑块验证页已经通过 `/_guard/html.js` / `/_guard/slide.js` 精确识别。
  static const List<String> _activeChallengeMarkers = <String>[
    '__cf_chl',
    'cf-chl-',
    'input[type=password]',
    '/_guard/html.js',
    '/_guard/slide.js',
    'slider_html',
    'challenge-form',
    'challenge-stage',
    // Cloudflare「Managed Challenge / 5 秒盾 / Just a moment」等待页特征：
    // 这类页以 200 返回、body 含下方字符串，但站点正常内容绝不会出现，故作为
    // 主动挑战标记直接判验证页（对齐 Han1mePlus 的 isCloudflareResponse 判定）。
    'just a moment',
    'attention required',
    'verify you are human',
    'checking your browser',
    // MacCMS「系统安全验证」拦截页（233动漫等 MacCMS 站搜索/筛选路由触发，
    // 正文只有「因访问过多，请点击下方【继续访问】」弹窗）：mx-mac_msg_jump 是
    // 该模板专有的弹窗容器类，verify_submit 是「继续访问」按钮类，verify_check
    // 是页内联脚本的 AJAX 接口名。三者只出现在验证页模板中——实测 233dm 的
    // 首页/搜索结果/详情页正文 0 命中，正常内容页不会误伤。不认出来会把验证页
    // HTML 当真实内容缓存解析 → 列表永远 0 条且不弹验证。
    'mx-mac_msg_jump',
    'verify_submit',
    'verify_check',
  ];

  /// 被动 CF 标记：Cloudflare 为「每一个」经它代理的页面注入（包括正常内容页，
  /// 例如 `/cdn-cgi/challenge-platform/scripts/jsd/main.js` 这段 bot 检测脚本）。
  /// 部分站点的正常 200 大页面（47–62KB）就包含它。单凭它命中会误伤 →
  /// 验证死循环。因此被动标记只在 body「极短（真实挑战页通常只有几 KB 的等待/
  /// 重定向壳）」时才结合判定，正常大内容页直接放行。
  static const List<String> _passiveCfMarkers = <String>[
    'cf-ray',
    'challenge-platform',
  ];

  /// 验证码「组件」标记（CAPTCHA/滑块挂件）。组件既可出现在真挑战页（整页就是
  /// 一个验证表单，壳体极小），也可以作为正常功能挂在内容页上——hanime1.me
  /// 登录态 watch 页（190KB）评论区就有 hCaptcha 发帖验证组件，真机曾因该页
  /// 命中 data-sitekey 被判「验证墙」→ 脚本预取 rawLength=0 → video/episodes
  /// 解析不出。组件 ≠ 挑战：与被动 CF 标记同语义——仅「极短壳」时结合判定，
  /// 正常大页放行（真实挑战页 g-recaptcha/turnstile 整页壳都远小于 8KB）。
  static const List<String> _captchaWidgetMarkers = <String>[
    'g-recaptcha',
    'turnstile',
    'data-sitekey',
  ];

  /// WAF/反爬「拦截应答」的精确 body 特征：整段 body 去掉首尾空白后**全字匹配**
  /// （大小写不敏感）才算命中。
  ///
  /// 背景：部分站点挂在「Edge WAF」后面（响应头 Server 形如
  /// `Edge/1.1.18`）。当它判定请求疑似机器人时，会返回 HTTP 200，但 body 只有一个
  /// 极短的拦截词——实测就是 `closed`。旧逻辑只认 Cloudflare/滑块特征，于是把
  /// `closed` 当成「正常内容」丢给解析器 → 解析出 0 条 → 用户只看到空白列表，
  /// 永远不会弹验证页。
  ///
  /// 为什么用「全字匹配」而不是 contains：正常网页/JSON 永远不会「整段只有一个
  /// closed」，全字匹配几乎不可能误伤真实内容；而 contains('closed') 会把任何正常
  /// 页面里出现的 closed 一词（如「已完结 closed」）误判为验证页，触发验证死循环。
  static const Set<String> _wafBlockBodies = <String>{
    'closed',
  };

  /// 已知 WAF 的 Server 响应头签名（小写子串匹配）。
  ///
  /// 仅作为「辅助信号」：单看 Server 头不足以判定验证（同一个 WAF 放行后也用这个
  /// Server 头发正常内容）。只有当 body 同时「短且不像正常内容」时才结合它判定，
  /// 覆盖「拦截词有变化 / body 为空」等 `_wafBlockBodies` 没枚举到的变体。
  static const List<String> _wafServerSignatures = <String>[
    'edge/1.1',
  ];

  /// Cloudflare「Edge IP Restricted」(error 1034) 特征。
  ///
  /// 语义：**该边缘 IP 未获本站授权**——请求确实到了 Cloudflare，但命中的这台
  /// 边缘服务器不属于本域名的接入 IP 集合，CF 直接以 403 拒绝，响应体是一段
  /// 纯文本错误页（实测≈2.3KB gzip / 17B～7.4KB 明文，标题 `Edge IP Restricted`）。
  ///
  /// 关键区别：这**不是**需要用户交互的反爬挑战（无 5 秒盾、无滑块、无 CAPTCHA），
  /// 用户点验证也永远过不去；但它是**按 IP 判定**的，换一个已授权的边缘 IP 即可
  /// 恢复。因此调用方应把它当作「可重试的选路失败」——换 IP 重试——而不是弹
  /// 验证页。
  ///
  /// 背景：源站 hosts 表常从社区配置抄一份会过期的 CF 边缘 IP 快照，其中部分
  /// IP 早已不在该域名的接入集合里；连接层只要 TCP 通则判定成功（CF 边缘对任何
  /// IP 都会完成握手），坏 IP 于是被长期误用。
  static const List<String> _edgeIpRestrictedMarkers = <String>[
    'error code: 1034',
    'edge ip restricted',
  ];

  /// 该响应是否为 Cloudflare「Edge IP Restricted」(1034) —— 按 IP 授权判定，
  /// 换 IP 可恢复，不应弹交互式验证。
  static bool isEdgeIpRestricted({int? statusCode, String? body}) {
    if (statusCode != 403 || body == null || body.isEmpty) return false;
    // 该错误页体积极小；先按长度闸门排除正常大页面，避免正常 403 页（含同名字样
    // 的文章/评论）被误判。实测最大 7.4KB 明文，留 8 倍余量到 64KB。
    if (body.length > 64 * 1024) return false;
    final lower = body.toLowerCase();
    return _edgeIpRestrictedMarkers.any((f) => lower.contains(f.toLowerCase()));
  }

  /// 检查顺序：403/401 先于「无 body」；503 解码 body 后看挑战特征；
  /// 200 + 主动挑战标记 / (被动CF标记 + 极短壳) / WAF 拦截应答 也判。
  static bool isVerificationRequired({
    required int? statusCode,
    required String? body,
    Map<String, String>? headers,
  }) {
    final code = statusCode;
    if (code == 401 || code == 403) return true;
    // 注意：403 中的 CF「Edge IP Restricted」(1034) 也会走到这里（true）——
    // 保持「403 一律需要处理」的语义不变，但调用方可先用 [isEdgeIpRestricted]
    // 区分「换 IP 可自愈」与「需要用户交互」，对它做选路重试而非弹验证页。
    if (code == 503) {
      // 503 本身已是强挑战信号：CF 的 503 挑战页含被动标记且体积极小，
      // 不做长度闸门，避免漏判。
      return _hasActiveChallenge(body ?? '') ||
          _hasPassiveCf(body ?? '') ||
          _isWafBlock(body, headers);
    }
    if (code == 200) {
      // 主动挑战标记（仅真实挑战页有）→ 直接判。
      if (body != null && _hasActiveChallenge(body)) return true;
      // 被动 CF 标记（正常页也有）→ 仅当 body 极短（挑战壳）时才判，
      // 放行部分源 47–62KB 的正常大页面。
      if (body != null &&
          _hasPassiveCf(body) &&
          _isLikelyChallengeShell(body)) {
        // 短页但结构完整（非空标题 + 图片/导航链接）是真实内容页，不是挑战壳：
        // 某些站点章节页本就只有几 KB（正文图片经 JS 懒加载，如嗶哩漫画 ~7.7KB），
        // 若按「被动标记 + 短壳」误判会把真章节页当验证页抛异常 → 图片永远解析
        // 失败。真正的 CF 等待页（Just a moment / Attention Required）含主动
        // 挑战标记，已在上方分支被拦截，不会走到这里。
        if (!_looksLikeRealContentPage(body)) return true;
      }
      if (_isWafBlock(body, headers)) return true;
    }
    return false;
  }

  static bool _hasActiveChallenge(String body) {
    final lower = body.toLowerCase();
    return _activeChallengeMarkers
        .any((f) => lower.contains(f.toLowerCase()));
  }

  static bool _hasPassiveCf(String body) {
    final lower = body.toLowerCase();
    return _passiveCfMarkers.any((f) => lower.contains(f.toLowerCase())) ||
        _captchaWidgetMarkers.any((f) => lower.contains(f.toLowerCase()));
  }

  /// 真实 CF 挑战页特征：体积极小（仅为「等待 5 秒 / 重定向」壳，通常 < 8KB），
  /// 不像正常大内容（部分源正常页 47–62KB，远超过阈值，不会误伤）。
  ///
  /// 仅作为「被动 CF 标记」的辅助闸门：body 既含被动标记又极短 → 才判为挑战。
  static bool _isLikelyChallengeShell(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return false;
    return trimmed.length <= 8192;
  }

  /// 小体积但结构完整的真实内容页判定：非空 `<title>` 文本，且至少含一个
  /// `<img>` 标签或 3 个 `<a>` 链接。
  ///
  /// 误伤代价分析：真正的 CF 挑战页（Just a moment / Attention Required /
  /// verify you are human）均含主动挑战标记，在更早的分支已被拦截，不会走到
  /// 这里。本豁免最坏情况是把「伪装成内容页的挑战壳」交给解析器 → 解析 0 条
  /// → 空列表（与完全不做检测一致），不会触发验证死循环。
  static bool _looksLikeRealContentPage(String body) {
    final titleMatch = RegExp(
      r'<title[^>]*>([^<]{1,300})</title',
      caseSensitive: false,
    ).firstMatch(body);
    if (titleMatch == null) return false;
    if (titleMatch.group(1)!.trim().isEmpty) return false;
    final lower = body.toLowerCase();
    if (lower.contains('<img')) return true;
    var anchors = 0;
    var idx = lower.indexOf('<a ');
    while (idx >= 0) {
      anchors++;
      if (anchors >= 3) return true;
      idx = lower.indexOf('<a ', idx + 3);
    }
    return false;
  }

  /// 判断是否为 WAF/反爬「拦截应答」（应走内置浏览器过验证，而非当空内容）。
  ///
  /// 两条命中路径：
  /// 1) body 去空白后全字命中 [_wafBlockBodies]（如整段就是 `closed`）；
  /// 2) 响应头 Server 命中已知 WAF 签名，且 body「短且不像正常内容」
  /// （极短、且不是以 `{`/`[`/`<` 开头的 JSON/HTML）——覆盖拦截词变体或空 body。
  static bool _isWafBlock(String? body, Map<String, String>? headers) {
    final trimmed = (body ?? '').trim();
    final lower = trimmed.toLowerCase();
    if (_wafBlockBodies.contains(lower)) return true;

    final server = _serverHeader(headers);
    if (server != null &&
        _wafServerSignatures.any((s) => server.contains(s))) {
      // Server 头是已知 WAF：仅当 body 短且不像正常 JSON/HTML 才判为拦截，
      // 避免把「同一 WAF 放行后返回的正常大响应」误伤。
      if (trimmed.length <= 32 &&
          !trimmed.startsWith('{') &&
          !trimmed.startsWith('[') &&
          !trimmed.startsWith('<')) {
        return true;
      }
    }
    return false;
  }

  /// 大小写不敏感地取 Server 响应头（Dio 的 header key 可能是任意大小写）。
  static String? _serverHeader(Map<String, String>? headers) {
    if (headers == null) return null;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'server') {
        return entry.value.toLowerCase();
      }
    }
    return null;
  }
}
