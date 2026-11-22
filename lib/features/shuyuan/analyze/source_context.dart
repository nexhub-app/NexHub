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
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:meta/meta.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/scraper/http_fetcher.dart';
import '../../../core/utils/app_log.dart';
import 'analyze_url.dart';
import 'concurrent_rate_limiter.dart';
import 'java_extensions.dart';
import 'webview_fetcher.dart';
import '../model/book_source.dart';
import '../shuyuan_variable_store.dart';

class ShuyuanSourceContext {
  ShuyuanSourceContext(this.sourceId);

  final String sourceId;

  /// 书源地址（legado `source.key` / `BookSource.getKey`）。
  /// `sourceId` 是本应用的内部主键，脚本里 `source.key` 需要的是书源 URL。
  String bookSourceUrl = '';

  /// legado `source.<field>` 只读属性快照（bookSourceName/Comment/Type/
  /// header/loginUrl 等）。脚本里 `source.bookSourceComment`（共享签名代
  /// 码）、`source.loginUrl` 等用法直接读配置字段。
  final Map<String, dynamic> sourceMeta = {};

  /// 装填源上下文：源 URL + jsLib + `source.<field>` 属性快照。
  void bindSource(XiaoshuoBookSource bs) {
    bookSourceUrl = bs.bookSourceUrl;
    jsLib = bs.jsLib ?? '';
    sourceMeta
      ..clear()
      ..addAll(<String, dynamic>{
        'bookSourceUrl': bs.bookSourceUrl,
        'bookSourceName': bs.bookSourceName,
        'bookSourceGroup': bs.bookSourceGroup ?? '',
        'bookSourceType': bs.bookSourceType,
        'bookSourceComment': bs.bookSourceComment ?? '',
        'header': bs.header ?? '',
        'loginUrl': bs.loginUrl ?? '',
        'jsLib': bs.jsLib ?? '',
        'customOrder': bs.customOrder,
        'lastUpdateTime': bs.lastUpdateTime,
        'weight': bs.weight,
      });
  }

  /// per-source cookie 覆盖层：cookieName → {value, host}。
  /// setCookie/removeCookie 写这里；AnalyzeUrl 按 host 后缀匹配合并进
  /// Cookie 请求头（读合并不写回全局罐——三通道隔离红线）。
  final Map<String, Map<String, String>> cookies = {};

  /// 已做过 412 根域种子 Cookie 预处理的站点根（URL 形态，按上下文去重）。
  /// 不随阶段缓存清空：Cookie 已落库，后续阶段不会再次触发 412。
  final Set<String> cookiePrimedRoots = <String>{};

  /// source.putLoginInfo/getLoginInfoMap。
  final Map<String, String> loginInfo = {};

  /// source.putLoginHeader/getLoginHeaderMap（登录请求头，随请求合并）。
  final Map<String, String> loginHeader = {};

  /// legado `getLoginHeader()` 的原样字符串（书源可写入非 JSON 私有格式，
  /// 例如以 `#` 前缀区分命名空间，由脚本自行解析）。
  String loginHeaderRaw = '';

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

  /// 搜索/发现阶段 `@put:{k:rule}`、java.put 写入的变量：bookUrl → {k: v}。
  /// legado 这些变量存在书对象的 variableMap 上随书走；NexHub 各阶段只传
  /// bookUrl，故按书暂存，详情/目录/正文阶段注入书的 variableMap 后
  /// `@get:{k}` / java.get 才能取到（如宜搜的 gid/nid 签名参数）。
  final Map<String, Map<String, String>> bookItemVars = {};

  /// 本轮 eval 中脚本发起、尚未满足的 ajax 请求（settle 循环抓取队列）。
  final List<String> ajaxPending = <String>[];

  /// `org.jsoup.Jsoup.connect(...).execute().bodyAsBytes()` 的重放缓存：
  /// 完整请求键 → 原始响应的 base64（不按文本解码，保留二进制密文）。
  /// 与 [ajaxCache] 同款增量推送（不进种子，防长目录 O(n²)）。
  final Map<String, String> ajaxBytesCache = <String, String>{};
  final List<String> ajaxBytesPending = <String>[];

  /// 响应元数据重放缓存：请求键 → `{code, url, headers}`（JSON）。
  /// `java.connect/get/post/head` 返回对象的 `code()/headers()/header()`/
  /// `cookies()`/`url()` 及 `.raw().request().url()` 都从它取值；与
  /// [ajaxCache] 同款增量推送，不进种子。
  final Map<String, String> ajaxMetaCache = <String, String>{};

  /// 发现页选项 action 请求宿主打开浏览器（java.startBrowser/openUrl）。
  final List<Map<String, String>> kindBrowserOpens = <Map<String, String>>[];

  /// java.open(name,url,title,origin) 请求队列（事件回调的登录/搜索/发现
  /// 入口）。由回调执行方在求值结束后排空并交给对应 UI 宿主。
  final List<Map<String, String>> openRequests = <Map<String, String>>[];

  /// `java.startBrowserAwait` 的确定性重放：键 → [url,title,refetch,html]；
  /// 宿主 settle 弹浏览器后把响应写入 [browserAwaitCache]（JSON 载荷）。
  final Map<String, List<String>> browserAwaitArgs = <String, List<String>>{};
  final List<String> browserAwaitPending = <String>[];
  final Map<String, String> browserAwaitCache = <String, String>{};

  /// `java.getVerificationCode`：键 → 图片 URL；输入值 → 缓存。
  final Map<String, String> verificationArgs = <String, String>{};
  final List<String> verificationPending = <String>[];
  final Map<String, String> verificationCodeCache = <String, String>{};

  /// 文件/归档族（unzipFile / getZipStringContent / readTxtFile 文本解码）
  /// 的本地运算待办与结果：运算键 → JSON 载荷/结果。settle 时同步执行
  /// （package:archive + fast_gbk），不占网络预算，结果供下一轮重放命中。
  final Map<String, String> fileOpArgs = <String, String>{};
  final List<String> fileOpPending = <String>[];
  final Map<String, String> fileOpResults = <String, String>{};

  /// 本阶段已打开过的 startBrowser 动作（url\ttitle\thtml），跨重放轮去重。
  final Set<String> browserOpened = <String>{};

  /// 发现页选项 action 请求刷新选项栏（java.refreshExplore/reLoginView）。
  bool kindRefreshRequested = false;

  /// 目录抓取前的 preUpdateJs 请求重新解析详情页以更新 tocUrl
  /// （legado AnalyzeRule.refreshTocUrl；目录地址定期更新的源依赖）。
  bool bookInfoRefreshRequested = false;

  /// 发现页选项 action 请求复制文本（java.copyText）。
  final List<String> copiedTexts = <String>[];

  /// 补数回放期间的 toast 暂存。首轮 `java.ajax` 返回占位符会让脚本
  /// 走 catch 提示分支；legado 的 ajax 是阻塞真实请求，不存在这种中间
  /// 态，故中间轮提示不弹给用户，最终轮再统一放行。
  bool deferFeedback = false;
  final List<({String msg, bool long})> deferredToasts =
      <({String msg, bool long})>[];

  /// 结束暂存并送达最后一轮产生的 toast（中间轮的已在下一轮开始前清掉）。
  void flushDeferredToasts() {
    deferFeedback = false;
    if (deferredToasts.isEmpty) return;
    final sink = JavaFeedback.onToast;
    for (final t in deferredToasts) {
      if (sink != null) {
        sink(t.msg, long: t.long);
      } else {
        AppLog.instance.i('[书源toast] ${t.msg}');
      }
    }
    deferredToasts.clear();
  }

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

  /// 移除单个页面缓存条目（loginCheck 重取同一地址前调用：legado 的
  /// `java.getStrResponse()` 是真实请求，不能被本阶段首取的缓存顶掉）。
  void pageCacheRemove(String key) {
    final prev = pageCache.remove(key);
    if (prev != null) _pageCacheChars -= prev.length;
  }

  /// 阶段开始：清空重放相关的全部瞬态缓存（页面 / ajax / webview / 待抓取队列）。
  void clearStageCaches() {
    pageCache.clear();
    _pageCacheChars = 0;
    ajaxCache.clear();
    ajaxPending.clear();
    ajaxBytesCache.clear();
    ajaxBytesPending.clear();
    ajaxMetaCache.clear();
    webviewCache.clear();
    webviewPending.clear();
    webviewArgs.clear();
    browserAwaitCache.clear();
    browserAwaitPending.clear();
    browserAwaitArgs.clear();
    verificationCodeCache.clear();
    verificationPending.clear();
    verificationArgs.clear();
    fileOpResults.clear();
    fileOpPending.clear();
    fileOpArgs.clear();
    browserOpened.clear();
  }

  // ── java.webView 的确定性重放（与 java.ajax 同款，只是宿主换成无头 WebView）──

  /// 待取源队列：key → [html, url, js]。
  final Map<String, List<String>> webviewArgs = <String, List<String>>{};
  final List<String> webviewPending = <String>[];
  final Map<String, String> webviewCache = <String, String>{};

  /// 抓取 webviewPending 中的页面，写入 [webviewCache]；失败同样缓存空串，
  /// 让占位符就地解析为 `''`（非 null 即命中），不会重复排队。
  ///
  /// 返回**本次真正发起**的取源次数（与 [settleAjax] 同口径，无论成功与否，
  /// 缓存命中不算）：调用方据此判断这一轮是否有进展。抓取失败也已把空串写进
  /// 缓存、占位符就此消解，必须算作进展——若只计成功数，全失败的一轮会被当成
  /// 零进展提前退出，把占位符轮次的 `out`（含 `__WEBVIEW_n__` 或空页）当结果。
  ///
  /// [deadline] 非空时是整轮 settle 的硬预算：耗尽后剩余取源直接按失败缓存
  /// （空串），不再逐个发起——否则 N 个慢页串行 × 45s 超时会把阅读器转圈
  /// 拖到分钟级，且调用方在 settle 期间没有任何中断点。
  static Future<int> settleWebview(
    ShuyuanSourceContext ctx, {
    DateTime? deadline,
  }) async {
    if (ctx.webviewPending.isEmpty) return 0;
    final keys = List<String>.from(ctx.webviewPending);
    ctx.webviewPending.clear();
    var fetched = 0;
    for (final key in keys) {
      if (deadline != null && !DateTime.now().isBefore(deadline)) {
        ctx.webviewCache[key] = '';
        fetched++;
        continue;
      }
      final args = ctx.webviewArgs[key] ?? const <String>[];
      final html = args.isNotEmpty ? args[0] : '';
      final url = args.length > 1 ? args[1] : '';
      final js = args.length > 2 ? args[2] : '';
      final delayMs = args.length > 3 ? int.tryParse(args[3]) ?? 0 : 0;
      final resultJson = args.length > 4 ? args[4] : '';
      final sourceRegex = args.length > 5 ? args[5] : '';
      final overrideUrlRegex = args.length > 6 ? args[6] : '';
      final headers = <String, String>{};
      final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
      if (host.isNotEmpty) {
        try {
          headers['User-Agent'] =
              HttpFetcher.instance.userAgentForUrl(url);
        } catch (_) {}
        final overlay = ctx.cookiesForHost(host);
        if (overlay.isNotEmpty) {
          headers['Cookie'] =
              overlay.entries.map((e) => '${e.key}=${e.value}').join('; ');
        }
      }
      // 与 settleAjax 一致：先计尝试再抓取，失败也必须算这一轮有进展。
      fetched++;
      // legado BackstageWebView 在 onPageFinished 里先把上一段结果写进
      // window.result，再执行规则 JS；重放宿主用同一次求值等效实现。
      final jsCode =
          resultJson.isEmpty ? js : 'window.result = $resultJson;\n$js';
      try {
        final result = await ShuyuanWebviewFetcher.fetch(
          html: html,
          url: url,
          js: jsCode,
          delayMs: delayMs,
          headers: headers,
          sourceRegex: sourceRegex.isEmpty ? null : sourceRegex,
          overrideUrlRegex: overrideUrlRegex.isEmpty ? null : overrideUrlRegex,
        ).timeout(const Duration(seconds: 45));
        ctx.webviewCache[key] = result?.html ?? '';
        if (result != null) {
          for (final e in result.cookieHeaders.entries) {
            ctx.syncCookies(e.key, e.value);
          }
        }
      } catch (_) {
        ctx.webviewCache[key] = '';
      }
    }
    // 捕获的 Cookie 必须落盘：仅留在内存时，另一个实例（解析器缓存 ctx /
    // 登录窗）既读不到，且本实例 cookiesDirty 期间 refreshCookiesFromStore
    // 是 no-op，后续排空会把陈旧快照写回存储覆盖别处写入的登录态。
    // persistIfNeeded 在无写时为 no-op，无需条件保护。
    await ctx.persistIfNeeded();
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
        'sourceMeta': Map<String, dynamic>.from(sourceMeta),
        'bookVars': Map<String, String>.from(bookVars),
        'bookInfo': Map<String, String>.from(bookInfo),
        'cookies': {
          for (final e in cookies.entries)
            e.key: Map<String, String>.from(e.value),
        },
        'loginInfo': Map<String, String>.from(loginInfo),
        'loginHeader': Map<String, String>.from(loginHeader),
        'loginHeaderRaw': loginHeaderRaw,
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
        case 'bookField':
          bookInfo[a] = b;
        case 'concurrentRate':
          // source.putConcurrent / java.putConcurrent：运行期调整并发率。
          ConcurrentRateLimiter.updateConcurrentRate(
              bookSourceUrl.isNotEmpty ? bookSourceUrl : sourceId, a);
        case 'open':
          // java.open(name,url,title,origin)：宿主 UI 请求（登录/搜索/发现），
          // 由回调调用方在求值结束后排空执行。载荷为 JSON 数组。
          try {
            final decoded = jsonDecode(a);
            if (decoded is List && decoded.isNotEmpty) {
              openRequests.add(<String, String>{
                'name': decoded[0]?.toString() ?? '',
                'url': decoded.length > 1 ? decoded[1]?.toString() ?? '' : '',
                'title':
                    decoded.length > 2 ? decoded[2]?.toString() ?? '' : '',
                'origin':
                    decoded.length > 3 ? decoded[3]?.toString() ?? '' : '',
              });
            }
          } catch (_) {}
        case 'cachePut':
          // 占位符值（本轮未回填的 ajax/webview 结果）不能落持久缓存：
          // 脚本常把取数结果拼进 headers 再 cache.put，一旦把带
          // `__WEBVIEW_n__` 的脏值存下来，后续重放轮会命中它而不再重建
          // （legado 的桥是同步的，缓存里只会出现真实响应）。
          if (!_hasReplayPlaceholderValue(b)) cache[a] = b;
        case 'cacheDel':
          cache.remove(a);
        case 'ajax':
          // 脚本发起的网络请求记录（settle 循环抓取）。按 URL 去重。
          if (!ajaxPending.contains(a)) ajaxPending.add(a);
        case 'ajaxBytes':
          // bodyAsBytes 的二进制重放请求（同一 URL 可能同时被记录为
          // 'ajax'，settle 按并集抓取一次、双缓存填充）。
          if (!ajaxBytesPending.contains(a)) ajaxBytesPending.add(a);
        case 'browserOpen':
          var title = b;
          var html = '';
          try {
            final decoded = jsonDecode(b);
            if (decoded is List) {
              title = decoded.isNotEmpty ? '${decoded[0] ?? ''}' : '';
              html = decoded.length > 1 ? '${decoded[1] ?? ''}' : '';
            }
          } catch (_) {}
          kindBrowserOpens.add(<String, String>{
            'url': a,
            'title': title,
            'html': html,
          });
        case 'browserAwait':
          // startBrowserAwait：a=键，b=[url, title, refetch, html]。
          if (!browserAwaitPending.contains(a)) {
            browserAwaitPending.add(a);
            try {
              final decoded = jsonDecode(b);
              if (decoded is List) {
                browserAwaitArgs[a] = <String>[
                  for (final e in decoded) e?.toString() ?? '',
                ];
              }
            } catch (_) {}
          }
        case 'verificationCode':
          // getVerificationCode：a=键，b=图片 URL。
          if (!verificationPending.contains(a)) {
            verificationPending.add(a);
            verificationArgs[a] = b;
          }
        case 'fileOp':
          // 文件/归档族本地运算（unzipFile / getZipStringContent /
          // readTxtFile 文本解码）：a=运算键，b=JSON 载荷，settle 同步执行。
          if (!fileOpPending.contains(a)) {
            fileOpPending.add(a);
            fileOpArgs[a] = b;
          }
        case 'refreshKinds':
          kindRefreshRequested = true;
        case 'refreshTocUrl':
          bookInfoRefreshRequested = true;
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
            var decoded = jsonDecode(a);
            if (decoded is String) {
              try {
                decoded = jsonDecode(decoded);
              } catch (_) {}
            }
            if (decoded is Map) {
              loginInfo
                ..clear()
                ..addAll(<String, String>{
                  for (final e in decoded.entries)
                    e.key.toString(): e.value?.toString() ?? '',
                });
            }
          } catch (_) {}
        case 'loginInfoDel':
          if (a.isEmpty) {
            loginInfo.clear();
          } else {
            loginInfo.remove(a);
          }
        case 'loginHeader':
          try {
            final decoded = jsonDecode(a);
            if (decoded is String) {
              // legado putLoginHeader(String)：原样保存；getLoginHeaderMap()
              // 再按 JSON 解析（非 JSON 文本解析失败即视为无请求头）。
              loginHeaderRaw = decoded;
              loginHeader.clear();
              try {
                final parsed = jsonDecode(decoded);
                if (parsed is Map) {
                  parsed.forEach((k, v) =>
                      loginHeader[k.toString()] = v?.toString() ?? '');
                }
              } catch (_) {}
            } else if (decoded is Map) {
              loginHeader
                ..clear()
                ..addAll(<String, String>{
                  for (final e in decoded.entries)
                    e.key.toString(): e.value?.toString() ?? '',
                });
              loginHeaderRaw = jsonEncode(loginHeader);
            }
          } catch (_) {}
        case 'loginHeaderDel':
          loginHeaderRaw = '';
          loginHeader.clear();
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

  /// 响应 Set-Cookie 写入覆盖层（legado `CookieManager.saveResponse` 对等：
  /// OkHttp 拦截器对每个响应按域保存、后续请求自动回放）。
  ///
  /// 旧实现只读不写：服务端在首个响应下发的会话 cookie（鉴权/防爬握手）
  /// 全部丢失，后续 API/列表请求不带 cookie → 服务端按未授权返回空数据，
  /// 表现为「发现页和分类页都解析不到内容」。
  ///
  /// Domain 属性优先（去前导点）；缺省落在请求 host。Max-Age<=0 依浏览器
  /// 语义删除同名 cookie。Path 不参与键控（与 legado 一致：只要域匹配就回放）。
  void applyResponseCookies(String requestUrl, List<String>? setCookies) {
    if (setCookies == null || setCookies.isEmpty) return;
    final reqHost = _hostOf(requestUrl);
    var changed = false;
    for (final raw in setCookies) {
      final header = raw.trim();
      if (header.isEmpty) continue;
      final segments = header.split(';');
      final pair = segments.first;
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final name = pair.substring(0, eq).trim();
      final value = pair.substring(eq + 1).trim();
      if (name.isEmpty) continue;

      var host = reqHost;
      var maxAge = 0;
      var hasMaxAge = false;
      for (var i = 1; i < segments.length; i++) {
        final seg = segments[i];
        final sep = seg.indexOf('=');
        final key =
            (sep >= 0 ? seg.substring(0, sep) : seg).trim().toLowerCase();
        final val = sep >= 0 ? seg.substring(sep + 1).trim() : '';
        if (key == 'domain' && val.isNotEmpty) {
          host = val.toLowerCase().replaceFirst(RegExp(r'^\.+'), '');
        } else if (key == 'max-age') {
          final parsed = int.tryParse(val);
          if (parsed != null) {
            maxAge = parsed;
            hasMaxAge = true;
          }
        }
      }

      if (hasMaxAge && maxAge <= 0) {
        if (cookies.remove(name) != null) changed = true;
        continue;
      }
      final prev = cookies[name];
      if (prev == null || prev['value'] != value || prev['host'] != host) {
        cookies[name] = {'value': value, 'host': host};
        changed = true;
      }
    }
    if (changed) cookiesDirty = true;
  }

  /// 交互浏览器 / WebView 捕获的 Cookie 回灌（只写 per-source 覆盖层）。
  void syncCookies(String host, String header) {
    final h = host.toLowerCase().trim();
    if (h.isEmpty || header.trim().isEmpty) return;
    var changed = false;
    for (final part in header.split(';')) {
      final eq = part.indexOf('=');
      if (eq <= 0) continue;
      final name = part.substring(0, eq).trim();
      final value = part.substring(eq + 1).trim();
      if (name.isEmpty) continue;
      final prev = cookies[name];
      if (prev == null || prev['value'] != value || prev['host'] != h) {
        cookies[name] = <String, String>{'value': value, 'host': h};
        changed = true;
      }
    }
    if (changed) cookiesDirty = true;
  }

  /// 登录窗/交互浏览器可能由另一个 ctx 实例写入并落盘；解析前刷新一次。
  /// 本实例有未落盘写入时跳过（内存写优先，避免被旧盘值覆盖）。
  Future<void> refreshCookiesFromStore() async {
    if (cookiesDirty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cookieStoreKey);
      if (raw == null || raw.isEmpty) return;
      _cookieCache = _decodeCookieStore(raw);
      final mine = _cookieCache![sourceId];
      if (mine == null) return;
      for (final e in mine.entries) {
        final prev = cookies[e.key];
        if (prev == null ||
            prev['value'] != e.value['value'] ||
            prev['host'] != e.value['host']) {
          cookies[e.key] = Map<String, String>.from(e.value);
        }
      }
    } catch (_) {}
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

  /// 已装载的 cookie 覆盖层（同步，供图片头钩子判断是否需要走慢路径）。
  static Map<String, Map<String, String>> persistedCookiesFor(
      String sourceId) {
    final mine = _cookieCache?[sourceId];
    if (mine == null || mine.isEmpty) return const {};
    return mine;
  }

  /// 启动期预读 cookie 覆盖层：图片头钩子是同步调用（取图期无法 await），
  /// 未预热时只会看到空覆盖层，登录后的 Cookie 不会进图片请求。
  static Future<void> warmCookieCache() async {
    if (_cookieCache != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cookieStoreKey);
      if (raw != null && raw.isNotEmpty) {
        _cookieCache ??= _decodeCookieStore(raw);
      }
    } catch (_) {}
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
  ///
  /// [deadline] 语义同 [settleWebview]：整轮预算耗尽后剩余请求按失败缓存，
  /// 保证调用方等待有上界。
  static Future<int> settleAjax(
    ShuyuanSourceContext ctx,
    XiaoshuoBookSource source, {
    DateTime? deadline,
  }) async {
    var fetched = 0;
    // bodyAsBytes 与 java.ajax 可能记录同一 URL：按并集各抓一次，
    // 依各自的待办标志分别填充文本/二进制缓存。
    final keys = <String>[
      ...ctx.ajaxPending,
      for (final k in ctx.ajaxBytesPending)
        if (!ctx.ajaxPending.contains(k)) k,
    ];
    // 含未回填占位符的请求键（如签名/请求头里嵌着 `__WEBVIEW_n__`）本轮
    // 一律不发：字面占位符打到站点只会拿到错误响应并写进缓存。直接丢弃
    // 待办，让下一轮用已回填的依赖重新构造真实 URL。
    keys.removeWhere(_hasReplayPlaceholderValue);
    ctx.ajaxPending.removeWhere(_hasReplayPlaceholderValue);
    ctx.ajaxBytesPending.removeWhere(_hasReplayPlaceholderValue);
    for (final key in keys) {
      final wantBody = ctx.ajaxPending.contains(key);
      final wantBytes = ctx.ajaxBytesPending.contains(key);
      if (wantBody && ctx.ajaxCache.containsKey(key)) continue;
      if (wantBytes && ctx.ajaxBytesCache.containsKey(key)) continue;
      fetched++;
      if (deadline != null && !DateTime.now().isBefore(deadline)) {
        if (wantBody) ctx.ajaxCache[key] = _ajaxFailureText('请求超时');
        if (wantBytes) ctx.ajaxBytesCache[key] = '';
        ctx.ajaxMetaCache[key] = jsonEncode(<String, dynamic>{
          'code': 0,
          'url': key,
          'headers': const <String, List<String>>{},
        });
        continue;
      }
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
        if (wantBody) ctx.ajaxCache[key] = resp;
        if (wantBytes) {
          final bytes = analyzeUrl.lastResponseBytes ??
              Uint8List.fromList(utf8.encode(resp));
          ctx.ajaxBytesCache[key] = base64Encode(bytes);
        }
        ctx.ajaxMetaCache[key] = jsonEncode(<String, dynamic>{
          'code': analyzeUrl.lastStatusCode ?? 200,
          'url': analyzeUrl.lastFinalUrl ?? analyzeUrl.url,
          'headers': analyzeUrl.lastResponseHeaders ?? const <String, List<String>>{},
        });
      } catch (e) {
        if (wantBody) ctx.ajaxCache[key] = _ajaxFailureText(e);
        if (wantBytes) ctx.ajaxBytesCache[key] = '';
        ctx.ajaxMetaCache[key] = jsonEncode(<String, dynamic>{
          'code': 0,
          'url': url,
          'headers': const <String, List<String>>{},
        });
      }
    }
    ctx.ajaxPending.clear();
    ctx.ajaxBytesPending.clear();
    // 文件/归档族本地运算（解压/取包内条目/文本解码）：纯本地同步，
    // 不占网络预算；计入 fetched 让调用方的重放循环继续一轮。
    fetched += _settleFileOps(ctx);
    return fetched;
  }

  /// legado `java.ajax` 失败口径：catch 后返回 `e.stackTraceStr`（异常类名 +
  /// 消息 + 栈帧），源常以 `startsWith("java")` 判定失败；失败缓存写空串会
  /// 让这类源把失败当成功继续解析。
  static const String ajaxFailurePrefix = 'java.lang.Exception: ';

  static String _ajaxFailureText(Object error) {
    final msg = error.toString();
    return '$ajaxFailurePrefix$msg\n'
        '\tat io.legado.app.model.analyzeRule.AnalyzeUrl.getStrResponseAwait(AnalyzeUrl.kt)';
  }

  static int _settleFileOps(ShuyuanSourceContext ctx) {
    if (ctx.fileOpPending.isEmpty) return 0;
    final keys = List<String>.from(ctx.fileOpPending);
    ctx.fileOpPending.clear();
    for (final key in keys) {
      final raw = ctx.fileOpArgs.remove(key) ?? '';
      ctx.fileOpResults[key] = _runFileOp(key, raw);
    }
    return keys.length;
  }

  static const Set<String> _textExtensions = <String>{
    'txt', 'text', 'html', 'htm', 'xml', 'json', 'js', 'css', 'csv', 'md',
    'log', 'nfo',
  };

  static bool _looksLikeText(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return true;
    return _textExtensions.contains(name.substring(dot + 1).toLowerCase());
  }

  /// 文本解码（legado readTxtFile/EncodingDetect 的实用近似）：显式 GBK 系
  /// → GBK；显式其他 → UTF-8 容错；未显式 → 严格 UTF-8 成功即用，失败回落
  /// GBK，再失败按 UTF-8 容错（替换不可解码字节，不抛错）。
  static String _decodeTextFile(List<int> bytes, String? charsetName) {
    final lower = (charsetName ?? '').toLowerCase().replaceAll('_', '-');
    if (lower == 'gbk' ||
        lower == 'gb-2312' ||
        lower == 'gb2312' ||
        lower == 'gb18030') {
      try {
        return gbk.decode(bytes);
      } catch (_) {}
      return utf8.decode(bytes, allowMalformed: true);
    }
    if (lower.isNotEmpty && lower != 'utf-8' && lower != 'utf8') {
      return utf8.decode(bytes, allowMalformed: true);
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      try {
        return gbk.decode(bytes);
      } catch (_) {
        return utf8.decode(bytes, allowMalformed: true);
      }
    }
  }

  /// 执行一条文件族运算。键前缀约定：
  /// - `uz:<folder>:<contentHash>`：载荷 `[zipBase64]` → `{条目名: {b,t}}`；
  /// - `zc:<contentHash>:<entry>|<charset>`：载荷 `[zipBase64, entry, charset]`
  ///   → `{b,t}`（未命中条目 → `{}`）；
  /// - `tx:<contentHash>|<charset>`：载荷 `[bytesBase64, charset]` → `{t}`。
  static String _runFileOp(String key, String raw) {
    var payload = const <dynamic>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) payload = decoded;
    } catch (_) {}
    String arg(int i) =>
        i < payload.length ? '${payload[i] ?? ''}' : '';
    try {
      if (key.startsWith('uz:')) {
        final bytes = base64Decode(arg(0));
        final archive = ZipDecoder().decodeBytes(bytes, verify: false);
        final entries = <String, Map<String, String>>{};
        for (final f in archive) {
          if (!f.isFile) continue;
          final data = f.content as List<int>;
          entries[f.name] = <String, String>{
            'b': base64Encode(data),
            if (_looksLikeText(f.name)) 't': _decodeTextFile(data, null),
          };
        }
        return jsonEncode(entries);
      }
      if (key.startsWith('zc:')) {
        final bytes = base64Decode(arg(0));
        final entry = arg(1);
        final archive = ZipDecoder().decodeBytes(bytes, verify: false);
        for (final f in archive) {
          if (!f.isFile || f.name != entry) continue;
          final data = f.content as List<int>;
          return jsonEncode(<String, String>{
            'b': base64Encode(data),
            't': _decodeTextFile(data, arg(2)),
          });
        }
        return '{}';
      }
      if (key.startsWith('tx:')) {
        final bytes = base64Decode(arg(0));
        return jsonEncode(<String, String>{
          't': _decodeTextFile(bytes, arg(1)),
        });
      }
    } catch (_) {}
    return '{}';
  }

  /// 测试隔离。
  static void resetForTest() {
    _cookieCache = null;
  }
}

/// 重放占位符（`__AJAX_n__` / `__WEBVIEW_n__`）：脚本在宿主取数前拿到的
/// 临时返回值。含占位符的内容不完整，不能持久化，也不能作为真实请求发出。
bool _hasReplayPlaceholderValue(String v) =>
    v.contains('__AJAX_') || v.contains('__WEBVIEW_');
