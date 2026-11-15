/// legado 注入对象（cookie/source/book/cache）的宿主上下文。
///
/// 同步沙箱约定（与 java.* 桥一致）：读走种子——eval 前把上下文快照经
/// `__shuyuanCtx` 绑定注入；写走排空——eval 后统一回写本对象并持久化。
///
/// - `cookie`：per-source cookie **覆盖层**（书源命名空间隔离，见登录三通道
///   设计）；请求时由 AnalyzeUrl 按 host 匹配合并进 Cookie 头，不写全局罐。
/// - `source`：书源标识（getKey=bookSourceUrl）、源变量、登录信息/头。
/// - `book`：书目变量（XiaoshuoBook.variableMap 的 JS 通道）与书目字段快照。
/// - `cache`：CacheManager 等效物，会话级（进程内存），get/put/delete。
library;

import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'analyze_url.dart';
import 'webview_fetcher.dart';
import '../model/book_source.dart';
import '../shuyuan_variable_store.dart';

class ShuyuanSourceContext {
  ShuyuanSourceContext(this.sourceId);

  final String sourceId;

  /// 书源地址（legado `source.key` / `BookSource.getKey`）。
  /// `sourceId` 是本应用的内部主键，脚本里 `source.key` 需要的是书源 URL。
  String bookSourceUrl = '';

  /// per-source cookie 覆盖层：cookieName → {value, host}。
  /// setCookie/removeCookie 写这里；AnalyzeUrl 按 host 后缀匹配合并进
  /// Cookie 请求头（读合并不写回全局罐——三通道隔离红线）。
  final Map<String, Map<String, String>> cookies = {};

  /// source.putLoginInfo/getLoginInfoMap。
  final Map<String, String> loginInfo = {};

  /// source.putLoginHeader/getLoginHeaderMap（登录请求头，随请求合并）。
  final Map<String, String> loginHeader = {};

  /// source 变量（ShuyuanVariableStore 的内存镜像，排空时持久化）。
  final Map<String, String> sourceVars = {};

  /// book 变量（XiaoshuoBook.variableMap 的镜像，按当前书回写）。
  final Map<String, String> bookVars = {};

  /// 书目字段快照（book.name/author/bookUrl 等直读）。
  final Map<String, String> bookInfo = {};

  /// cache.get/put/delete（会话级内存）。
  final Map<String, String> cache = {};

  /// jsLib 预执行内容（书源 source.jsLib）——每引擎实例首次 eval 前执行，
  /// 定义的函数/变量对该源所有后续脚本可见（legado SharedJsScope 等效）。
  String jsLib = '';

  /// java.ajax 确定性重放缓存：完整 ajax URL（含 AnalyzeUrl 选项串）→
  /// 响应体。settle 循环抓取后写入，重放时脚本内 ajax 直出真数据。
  final Map<String, String> ajaxCache = {};

  /// 搜索条目上下文：bookUrl → 搜索响应条目（JSON Map）或 HTML 元素
  /// （API 返回的 URL 字段含 {{\$.field}} 模板时，详情/目录阶段
  /// AnalyzeUrl 求值的根）。
  final Map<String, Object> bookItemContext = {};

  /// 本轮 eval 中脚本发起、尚未满足的 ajax 请求（settle 循环抓取队列）。
  final List<String> ajaxPending = <String>[];

  /// 发现页选项 action 请求宿主打开浏览器（java.startBrowser/openUrl）。
  final List<Map<String, String>> kindBrowserOpens = <Map<String, String>>[];

  /// 发现页选项 action 请求刷新选项栏（java.refreshExplore/reLoginView）。
  bool kindRefreshRequested = false;

  /// 发现页选项 action 请求复制文本（java.copyText）。
  final List<String> copiedTexts = <String>[];

  /// 阶段级页面响应缓存：settle 重放会整段重跑 `_dispatch`，若不缓存，
  /// 同一页会被真实重复抓取 2–4 次（长目录尤其明显）。
  /// key = method|url|body|js|regex；每个解析阶段开始时 [clearStageCaches]。
  final Map<String, String> pageCache = <String, String>{};

  /// 缓存容量按字符数封顶（UTF-16 下约 8MB），超限按插入序淘汰最旧，
  /// 避免长目录（200 页 × 每页几十 KB）把内存顶穿。
  static const int _pageCacheMaxChars = 4 * 1024 * 1024;
  int _pageCacheChars = 0;

  /// 写入页面缓存（单页过大不缓存；超容量淘汰最旧）。
  void pageCachePut(String key, String body) {
    if (body.length > _pageCacheMaxChars) return;
    final prev = pageCache.remove(key);
    if (prev != null) _pageCacheChars -= prev.length;
    pageCache[key] = body;
    _pageCacheChars += body.length;
    while (_pageCacheChars > _pageCacheMaxChars && pageCache.isNotEmpty) {
      final oldest = pageCache.keys.first;
      _pageCacheChars -= pageCache[oldest]!.length;
      pageCache.remove(oldest);
    }
  }

  /// 阶段开始：清空重放相关的全部瞬态缓存（页面 / ajax / webview / 待抓取队列）。
  void clearStageCaches() {
    pageCache.clear();
    _pageCacheChars = 0;
    ajaxCache.clear();
    ajaxPending.clear();
    webviewCache.clear();
    webviewPending.clear();
    webviewArgs.clear();
  }

  // ── java.webView 的确定性重放（与 java.ajax 同款，只是宿主换成无头 WebView）──

  /// 待取源队列：key → [html, url, js]。
  final Map<String, List<String>> webviewArgs = <String, List<String>>{};
  final List<String> webviewPending = <String>[];
  final Map<String, String> webviewCache = <String, String>{};

  /// 抓取 webviewPending 中的页面，写入 [webviewCache]；失败缓存空串避免重试。
  /// 返回本次真正执行的取源次数（缓存命中不算）。
  static Future<int> settleWebview(ShuyuanSourceContext ctx) async {
    var fetched = 0;
    for (final key in List<String>.from(ctx.webviewPending)) {
      if (ctx.webviewCache.containsKey(key)) continue;
      fetched++;
      final args = ctx.webviewArgs[key] ?? const <String>['', '', ''];
      try {
        final html = await ShuyuanWebviewFetcher.fetch(
          html: args.isNotEmpty ? args[0] : null,
          url: args.length > 1 ? args[1] : null,
          js: args.length > 2 ? args[2] : null,
        ).timeout(const Duration(seconds: 45));
        ctx.webviewCache[key] = html ?? '';
      } catch (_) {
        ctx.webviewCache[key] = '';
      }
    }
    ctx.webviewPending.clear();
    return fetched;
  }

  /// 排空时标记：本次 eval 是否有 cookie 写（需持久化）。
  bool cookiesDirty = false;

  /// 排空时标记：源变量有写（需持久化）。
  bool sourceVarsDirty = false;

  // ── 作用域：Zone 传递（异步安全 / 并发隔离） ──
  //
  // 旧实现用静态 List 当栈：`run(ctx, () async {...})` 在 body 返回 Future
  // 的瞬间就 finally pop，第一个 await 之后 current 恒为 null —— JS 种子、
  // 排空回写、cookie 覆盖层、登录头、bookItemContext 全部静默失效；且静态
  // 栈在多源并发时会串上下文。Zone 随异步续体自动传播，两个问题一起解决。
  static const Object _zoneKey = #shuyuanSourceContext;

  static ShuyuanSourceContext? get current =>
      Zone.current[_zoneKey] as ShuyuanSourceContext?;

  /// 在上下文作用域内执行（空上下文直接执行，零开销）。
  static R run<R>(ShuyuanSourceContext? context, R Function() body) {
    if (context == null) return body();
    return runZoned(body, zoneValues: <Object, Object>{_zoneKey: context});
  }

  // ── 种子：注入 JS 的快照（必须深拷贝——若传活引用，JS 直改原表，
  // 排空 diff 恒为零差异，dirty/持久化标志永不触发） ──
  Map<String, dynamic> toSeed() => <String, dynamic>{
        'sourceId': sourceId,
        'sourceKey': bookSourceUrl.isNotEmpty ? bookSourceUrl : sourceId,
        'sourceVars': Map<String, String>.from(sourceVars),
        'bookVars': Map<String, String>.from(bookVars),
        'bookInfo': Map<String, String>.from(bookInfo),
        'cookies': {
          for (final e in cookies.entries)
            e.key: Map<String, String>.from(e.value),
        },
        'loginInfo': Map<String, String>.from(loginInfo),
        'loginHeader': Map<String, String>.from(loginHeader),
        'cache': Map<String, String>.from(cache),
        // ajaxCache 不进种子：它随 settle 轮次单调增长，若每轮都序列化整个
        // 缓存进 JS 源码，长目录会退化成 O(n²)（几十页正文 = 每次 eval
        // 重建数 MB 字符串）。改由 JsEngine 增量推送进 JS 全局 __ajaxCache。
      };

  // ── 排空：JS 写操作日志回放（ops 与 toasts 同款 splice 模式——显式操作
  // 序列，删除/覆盖不依赖状态 diff，规避共享引用与墓碑不可见问题） ──
  void applyOps(List<dynamic> ops) {
    for (final op in ops) {
      if (op is! Map) continue;
      final type = op['op']?.toString() ?? '';
      final a = op['a']?.toString() ?? '';
      final b = op['b']?.toString() ?? '';
      switch (type) {
        case 'setCookie':
          final i = b.indexOf('=');
          if (i <= 0) break;
          cookies[b.substring(0, i).trim()] = {
            'value': b.substring(i + 1),
            'host': _hostOf(a),
          };
          cookiesDirty = true;
        case 'removeCookie':
          final host = _hostOf(a);
          cookies.removeWhere((_, meta) => _hostMatch(
              (meta['host'] ?? '').toLowerCase().trim(), host));
          cookiesDirty = true;
        case 'sourceVar':
          if (sourceVars[a] != b) {
            sourceVars[a] = b;
            sourceVarsDirty = true;
          }
        case 'bookVar':
          bookVars[a] = b;
        case 'cachePut':
          cache[a] = b;
        case 'cacheDel':
          cache.remove(a);
        case 'ajax':
          // 脚本发起的网络请求记录（settle 循环抓取）。按 URL 去重。
          if (!ajaxPending.contains(a)) ajaxPending.add(a);
        case 'browserOpen':
          if (a.isNotEmpty) {
            kindBrowserOpens.add(<String, String>{'url': a, 'title': b});
          }
        case 'refreshKinds':
          kindRefreshRequested = true;
        case 'copyText':
          copiedTexts.add(a);
        case 'webview':
          // 脚本发起的无头 WebView 取源（settle 循环执行）。参数为
          // [html, url, js] 的 JSON 数组，b 里带着。
          if (!webviewPending.contains(a)) {
            webviewPending.add(a);
            try {
              final decoded = jsonDecode(b);
              if (decoded is List) {
                webviewArgs[a] = <String>[
                  for (final e in decoded) e?.toString() ?? '',
                ];
              }
            } catch (_) {}
          }
        case 'loginInfo':
          try {
            final decoded = jsonDecode(a);
            if (decoded is Map) {
              decoded.forEach((k, v) => loginInfo[k.toString()] = v?.toString() ?? '');
            }
          } catch (_) {}
        case 'loginInfoDel':
          loginInfo.remove(a);
        case 'loginHeader':
          try {
            final decoded = jsonDecode(a);
            if (decoded is Map) {
              decoded.forEach((k, v) => loginHeader[k.toString()] = v?.toString() ?? '');
            }
          } catch (_) {}
        case 'loginHeaderDel':
          loginHeader.remove(a);
      }
    }
  }

  /// URL/标签 → host（与 JS 侧 syHost 同口径）。
  static String _hostOf(String url) {
    final s = url.trim();
    final m = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://([^/?#]+)').firstMatch(s);
    var host = m != null
        ? m.group(1)!
        : (s.contains('/') ? s.substring(0, s.indexOf('/')) : s);
    host = host.split('@').last.split(':').first.toLowerCase().trim();
    return host;
  }

  /// host 匹配：cookie 只向「同域或子域」下发（RFC 6265 domain-match）。
  ///
  /// 旧实现用无点边界的 `endsWith`，`evil-example.com` 会被判为命中
  /// `example.com`（把登录 cookie 送给仿冒域），且允许反向匹配把子域
  /// cookie 发给父域。
  @visibleForTesting
  static bool hostMatches(String cookieHost, String requestHost) {
    final ch = cookieHost.toLowerCase().trim();
    final h = requestHost.toLowerCase().trim();
    if (ch.isEmpty || h.isEmpty) return true; // 未记录 host：视为全局
    return h == ch || h.endsWith('.$ch');
  }

  static bool _hostMatch(String cookieHost, String requestHost) =>
      hostMatches(cookieHost, requestHost);

  /// 取 host 匹配的 cookie 覆盖层（后缀匹配：cookie host 或请求 host 任一
  /// 为对方后缀即命中，兼容登录域与站点域不同的情况）。
  Map<String, String> cookiesForHost(String host) {
    final h = host.toLowerCase().trim();
    if (h.isEmpty || cookies.isEmpty) return const {};
    final out = <String, String>{};
    cookies.forEach((name, meta) {
      if (hostMatches(meta['host'] ?? '', h)) {
        out[name] = meta['value'] ?? '';
      }
    });
    return out;
  }

  // ── cookie 覆盖层持久化（per sourceId） ──
  static const String _cookieStoreKey = 'shuyuan_source_cookies_v1';
  static Map<String, Map<String, Map<String, String>>>? _cookieCache;

  /// 创建上下文并装载持久化状态（cookie 覆盖层 + 源变量）。
  ///
  /// 旧实现在 `_loadedSources` 命中时直接返回**空上下文**（无 cookie、
  /// 无变量）——resolver 实例重建后登录态即丢失。SharedPreferences 实例
  /// 自身有缓存，重复读取开销可忽略，这里每次都如实装载。
  static Future<ShuyuanSourceContext> forSource(String sourceId) async {
    final ctx = ShuyuanSourceContext(sourceId);
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cookieStoreKey);
      if (raw != null && raw.isNotEmpty) {
        _cookieCache ??= _decodeCookieStore(raw);
        final mine = _cookieCache![sourceId];
        if (mine != null) ctx.cookies.addAll(mine);
      }
    } catch (_) {}
    // 源变量（源管理里维护的「源变量」）：脚本 source.getVariable 的初值。
    try {
      final vars = await ShuyuanVariableStore.load(sourceId);
      if (vars.isNotEmpty) ctx.sourceVars.addAll(vars);
    } catch (_) {}
    return ctx;
  }

  /// 排空后持久化（仅 dirty 时）：源变量 + cookie 覆盖层。
  ///
  /// 旧实现只落 cookie，`sourceVarsDirty` 写了没人读 —— 脚本里
  /// `source.putVariable` 的写入重启即丢。
  Future<void> persistIfNeeded() async {
    if (sourceVarsDirty) {
      sourceVarsDirty = false;
      try {
        await ShuyuanVariableStore.save(
            sourceId, Map<String, String>.from(sourceVars));
      } catch (_) {}
    }
    if (!cookiesDirty) return;
    cookiesDirty = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      _cookieCache ??= {};
      _cookieCache![sourceId] = {
        for (final e in cookies.entries)
          e.key: {'value': e.value['value'] ?? '', 'host': e.value['host'] ?? ''}
      };
      await prefs.setString(_cookieStoreKey, jsonEncode(_cookieCache));
    } catch (_) {}
  }

  /// 删除源：清除其持久化的 cookie 覆盖层与源变量（源已不存在，
  /// 登录态不应继续留在本地）。
  static Future<void> forget(String sourceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cookieStoreKey);
      if (raw != null && raw.isNotEmpty) {
        _cookieCache = _decodeCookieStore(raw)..remove(sourceId);
        await prefs.setString(_cookieStoreKey, jsonEncode(_cookieCache));
      }
    } catch (_) {}
    try {
      await ShuyuanVariableStore.save(sourceId, const <String, String>{});
    } catch (_) {}
  }

  static Map<String, Map<String, Map<String, String>>> _decodeCookieStore(
      String raw) {
    final out = <String, Map<String, Map<String, String>>>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((src, entries) {
          if (entries is! Map) return;
          final m = <String, Map<String, String>>{};
          entries.forEach((name, meta) {
            if (meta is Map) {
              m[name.toString()] = {
                'value': meta['value']?.toString() ?? '',
                'host': meta['host']?.toString() ?? '',
              };
            }
          });
          out[src.toString()] = m;
        });
      }
    } catch (_) {}
    return out;
  }

  /// settle：抓取 ajaxPending 中未满足的请求写入 ajaxCache（登录脚本等
  /// 非阶段流程复用；resolver 阶段循环委托本方法）。
  /// POST 记录键为 `url||POST||body` 组合（shim 约定），拆分后组装
  /// AnalyzeUrl 选项串发起真实请求。
  ///
  /// 返回**本次真正发起**的请求数（缓存命中不算）：调用方据此判断这一轮
  /// 是否有进展，避免「URL 带随机数」的脚本无限重放。
  static Future<int> settleAjax(
    ShuyuanSourceContext ctx,
    XiaoshuoBookSource source,
  ) async {
    var fetched = 0;
    for (final key in List<String>.from(ctx.ajaxPending)) {
      if (ctx.ajaxCache.containsKey(key)) continue;
      fetched++;
      var url = key;
      String? postBody;
      const marker = '||POST||';
      final markerIdx = key.indexOf(marker);
      if (markerIdx >= 0) {
        url = key.substring(0, markerIdx);
        postBody = key.substring(markerIdx + marker.length);
      }
      try {
        var requestUrl = url;
        if (postBody != null) {
          final bodyOption = '{"method":"POST","body":${jsonEncode(postBody)}}';
          final optIdx = url.indexOf(',{');
          if (optIdx >= 0) {
            try {
              final existing =
                  jsonDecode(url.substring(optIdx + 1)) as Map<String, dynamic>;
              existing['method'] = 'POST';
              existing['body'] = postBody;
              requestUrl = '${url.substring(0, optIdx)},${jsonEncode(existing)}';
            } catch (_) {
              requestUrl = '${url.substring(0, optIdx)},$bodyOption';
            }
          } else {
            requestUrl = '$url,$bodyOption';
          }
        }
        final analyzeUrl = AnalyzeUrl(
          url: requestUrl,
          baseUrl: source.bookSourceUrl,
          source: source,
        );
        final resp = await analyzeUrl
            .getStrResponse()
            .timeout(const Duration(seconds: 45));
        ctx.ajaxCache[key] = resp;
      } catch (_) {
        ctx.ajaxCache[key] = '';
      }
    }
    ctx.ajaxPending.clear();
    return fetched;
  }

  /// 测试隔离。
  static void resetForTest() {
    _cookieCache = null;
  }
}
