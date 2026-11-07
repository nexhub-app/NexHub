/// 脚本解析器：执行源内嵌 JS（quickjs 沙箱）。
///
/// 安全约束：沙箱仅经 [JsHostBridge] 调用能力；单函数 >10s 自动终止抛超时；
/// 错误隔离——某源脚本崩溃仅该源返回 [SourceResolveException]，不影响其他源。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/episode.dart';
import '../models/media_item.dart';
import '../models/plugin_config.dart';
import '../network/model/effective_network_profile.dart';
import '../network/network_config_service.dart';
import '../network/runtime/webview_source_network.dart';
import '../scraper/http_fetcher.dart';
import '../scraper/silent_html_capture.dart';
import '../scraper/verification_detector.dart';
import '../auth/source_auth_header.dart';
import '../services/config_loader.dart';
import 'js_context.dart';
import 'parse_diagnostics.dart';
import 'source_resolver.dart';
import 'webview_resolver.dart';

/// 源声明式 CDN 图床发现（与 mirrors 路由同源思路，不写死站点逻辑）。
///
/// 拉取源声明的 CDN 列表端点（形如 `/api/v2/cdn`），并行探活各 server，
/// 选第一个可达的作为图片/缩略图基，注入脚本 `context.cdnImage`/`context.cdnThumb`。
/// 结果按源 id 缓存于内存，避免每次解析重复探活。连通性仍由 App 网络设置负责。
class CdnDiscovery {
  static final Map<String, _CdnBases> _cache = <String, _CdnBases>{};

  /// 解析并返回可达图床基；源未声明 cdn 时返回 null（脚本走旧 i3/t3 回退）。
  ///
  /// 注意：部分站点的图床是固定的 `i1~i4` / `t1~t4` 子域，直接探活这些已知
  /// 图床即可，无需强依赖 `/api/v2/cdn`（该端点在不少网络会稳定超时，且探活失败
  /// 时若回退到被墙的 `i3` 会原地踏步）。`cdn.url` 仅作为「5s 内可达才采用」的
  /// 可选增强：动态拿到图床列表后覆盖默认列表，否则沿用默认。失败一律回退 `i4`/`t4`。
  static Future<_CdnBases?> resolve(
    PluginConfig source,
    String baseUrl,
    EffectiveNetworkProfile net,
  ) async {
    final CdnConfig? cfg = source.cdn;
    if (cfg == null) return null;
    final cached = _cache[source.id];
    if (cached != null) return cached;
    final String host = _hostOf(baseUrl);
    // 固定图床列表，i3 放最后（实测最常被墙）。
    final List<String> imgServers = <String>['i1', 'i2', 'i4', 'i3']
        .map((p) => 'https://$p.$host')
        .toList();
    final List<String> thumbServers = <String>['t1', 't2', 't4', 't3']
        .map((p) => 'https://$p.$host')
        .toList();
    // 可选增强：源声明的 cdn 端点 5s 内可达才采用其列表（避免长等/超时拖慢首屏）。
    if (cfg.url.isNotEmpty) {
      try {
        final endpoint = _expand(cfg.url, baseUrl);
        if (await HttpFetcher.instance.isReachable(
          endpoint,
          net: net,
          timeout: const Duration(milliseconds: 2500),
        )) {
          final data = await HttpFetcher.instance.getJson(
            endpoint,
            referer: baseUrl,
            net: net,
          );
          final img = _asStringList(data[cfg.imageServers]);
          final thumb = _asStringList(data[cfg.thumbServers]);
          if (img.isNotEmpty) {
            imgServers
              ..clear()
              ..addAll(img);
          }
          if (thumb.isNotEmpty) {
            thumbServers
              ..clear()
              ..addAll(thumb);
          }
        }
      } on Object {
        // 忽略：沿用默认图床列表
      }
    }
    final String img =
        await _pickReachable(imgServers, net) ?? (cfg.imageFallback ?? _derive(baseUrl, 'i4'));
    final String thumb = await _pickReachable(thumbServers, net) ??
        (cfg.thumbFallback ?? _derive(baseUrl, 't4'));
    final result = _CdnBases(image: _stripSlash(img), thumb: _stripSlash(thumb));
    _cache[source.id] = result;
    return result;
  }

  /// 并行探活各 server，返回**最快可达**的（按响应延迟升序选优），
  /// 同耗时保持入参顺序偏好（i1 在前）。全部不可达返回 null。
  static Future<String?> _pickReachable(
    List<String> servers,
    EffectiveNetworkProfile net,
  ) async {
    if (servers.isEmpty) return null;
    final latencies = await Future.wait(
        servers.map((s) => _probeLatency(_stripSlash(s), net)));
    final reachable = <int>[];
    for (var i = 0; i < latencies.length; i++) {
      if (latencies[i] != null) reachable.add(i);
    }
    if (reachable.isEmpty) return null;
    reachable.sort((a, b) => latencies[a]!.compareTo(latencies[b]!));
    return _stripSlash(servers[reachable.first]);
  }

  /// 探活单个图床：可达返回耗时（毫秒），不可达/超时返回 null。超时 2.5s。
  static Future<int?> _probeLatency(String server, EffectiveNetworkProfile net) async {
    // 根路径探测：图床根会 404，但只要网络可达（非连接拒绝/超时）即视为可用。
    try {
      final sw = Stopwatch()..start();
      final ok = await HttpFetcher.instance.isReachable(
        '$server/favicon.ico',
        net: net,
        timeout: const Duration(milliseconds: 2500),
      );
      if (!ok) return null;
      return sw.elapsedMilliseconds;
    } on Object {
      return null;
    }
  }

  static List<String> _asStringList(dynamic v) =>
      v is List ? List<String>.from(v.whereType<String>()) : const <String>[];

  static String _hostOf(String baseUrl) {
    var h = baseUrl.split('://')[1];
    h = h.split('/').first;
    return h;
  }

  static String _expand(String url, String baseUrl) {
    if (url.startsWith('http')) return url;
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return '$base${url.startsWith('/') ? url : '/$url'}';
  }

  static String _derive(String baseUrl, String prefix) {
    return 'https://$prefix.${_hostOf(baseUrl)}';
  }

  static String _stripSlash(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;
}

class _CdnBases {
  final String image;
  final String thumb;
  const _CdnBases({required this.image, required this.thumb});
}

class ScriptResolver implements SourceResolver {
  ScriptResolver({this.engineFactory});

  /// 可注入引擎工厂（测试用 FakeJsEngine）。
  final JsEngineFactory? engineFactory;

  @override
  Future<dynamic> resolve(
    PluginConfig source,
    String apiName, {
    Map<String, String> vars = const {},
    void Function(List<dynamic>)? onProgress,
  }) async {
    // 注意：不再对 `useWebview` 源无条件抛 [WebViewHtmlRequest]。
    //
    // 本解析器只会被「脚本型」源（parser.type=='script' 或 hybrid + override
    // 为 script）路由到；声明式 useWebview 源（builtin/xpath/jsonpath/css）由
    // [ResolverRegistry] 直接派发给 [WebViewResolver]，不会进到这里。
    //
    // 之前这里对 useWebview 源一律抛 WebViewHtmlRequest，导致脚本源（如
    // 部分脚本源）每次点源都强制打开内嵌 InAppWebView 渲染后
    // 抽页——而这些源脚本本身通过 `ctx.http.get/getJson` 自行抓取数据、并不
    // 消费回灌的渲染 HTML，于是 WebView 毫无意义，且 InAppWebView 在反爬站点
    // 上加载数秒后直接 native 崩溃（表现即「漫画点击源过几秒钟自动卡崩」）。
    //
    // 正确做法：脚本源直接运行脚本，由脚本内部的 `ctx.http` 自行抓取；若站点
    // 拦截，脚本自身 try/catch 返回空列表，优雅降级而非崩溃。需要渲染后 HTML
    // 的声明式源仍走 WebViewResolver，不在此受影响。
    final factory = engineFactory ?? defaultEngineFactory;
    ParseDiagnostics.clear();
    ParseDiagnostics.log(source.id, 'resolve() 开始: apiName=$apiName, vars=$vars');
    debugPrint('[ScriptResolver] resolve() 开始: source=${source.id}, apiName=$apiName, vars=$vars');
    final engine = factory(source);
    // 注入分页/分类/关键词等到 JS context，供脚本自拼 URL（如某源脚本依赖
    // ctx.page / ctx.category 翻页与分类）。无相关变量的源为空操作，无副作用。
    engine.injectContext(vars);
    final base = ConfigLoader.instance.getActiveMirror(source);
    // 源声明式 CDN 图床发现：探活选可达图床，注入 context.cdnImage/cdnThumb。
    // 失败不影响正常解析（脚本回退 i3/t3 旧行为）。
    try {
      final bases = await CdnDiscovery.resolve(
          source, base, NetworkConfigService.instance.effectiveFor(source));
      if (bases != null) {
        engine.injectContext(<String, String>{
          'cdnImage': bases.image,
          'cdnThumb': bases.thumb,
        });
      }
    } on Object catch (e) {
      debugPrint('[ScriptResolver] CDN 发现跳过(非致命): $e');
    }
    try {
      final url =
          source.resolveRouteUrl(apiName, activeBaseUrl: base, vars: vars);
      final rt = source.responseTypeFor(apiName) ?? 'json';
      ParseDiagnostics.log(source.id, '路由URL=$url (responseType=$rt)');
      debugPrint('[ScriptResolver] 预取: url=$url, responseType=$rt');
      // 预取：多数脚本（如某漫画源）会自行 ctx.http.get 抓取，此处结果常被
      // 忽略；即便站点反爬导致预取抛 VerificationRequiredException，也不应直接
      // 上抛成 SourceResolveException 让列表报错——兜底为空串，交由脚本自抓取。
      dynamic raw;
      // 预取撞验证墙（CF 403）时记下异常：若脚本产出为空则原样重抛，
      // 让验证 UI 流接管（消费预取数据的脚本在空 raw 下必然空产出，
      // 不重抛用户就永远看不到验证入口——真机 /watch 403 案实证）。
      Object? prefetchVerificationError;
      try {
        // 通用：路由级预取也附加源声明式鉴权头（comments.login）。
        // 受保护路由（如源站收藏列表）必须在首次抓取就带令牌，否则 401；
        // 无 login 声明的源 sourceAuthHeader 返回 null，零影响。
        final authHeader = sourceAuthHeader(source);
        raw = rt == 'json'
            ? await engine.bridge.httpGetJson(url, headers: authHeader)
            : await engine.bridge.httpGet(url, headers: authHeader);
        final rawLen = raw is String ? raw.length : (raw is List ? raw.length : -1);
        ParseDiagnostics.log(source.id, '预取成功: 拿到 ${rawLen} 字符/项');
        debugPrint('[ScriptResolver] 预取成功: rawLength=${raw is String ? raw.length : (raw is List ? raw.length : "non-string/list")}');
      } on VerificationRequiredException catch (e) {
        prefetchVerificationError = e;
        ParseDiagnostics.log(source.id, '预取遇到验证墙: $e（脚本产出为空时上抛引导验证）');
        debugPrint('[ScriptResolver] 预取验证墙: $e');
        raw = '';
      } on Object catch (e) {
        ParseDiagnostics.log(source.id, '预取失败(非致命): $e');
        debugPrint('[ScriptResolver] 预取失败(非致命): $e');
        raw = '';
      }
      ParseDiagnostics.log(source.id, '开始执行脚本(入口函数)...');
      debugPrint('[ScriptResolver] 开始执行脚本...');
      final result = await _runScriptWithRaw(source, apiName, raw, engine);
      final count = result is List ? result.length : 0;
      ParseDiagnostics.log(source.id, '脚本执行完成: 返回 ${count} 项 (类型=${result.runtimeType})');
      debugPrint('[ScriptResolver] 脚本执行完成: resultType=${result.runtimeType}, result=${result is List ? "List[${result.length}]" : result}');
      if (count == 0) {
        ParseDiagnostics.log(source.id, '⚠️ 脚本返回空列表！可能是：1) 桥接未通(ctx.http.get 拿不到数据) 2) 页面结构变化 3) 站点反爬');
      }
      // 预取撞验证墙 + 脚本产出为空 → CF/反爬拦截实锤，原样重抛走验证 UI。
      if (count == 0 && prefetchVerificationError != null) {
        ParseDiagnostics.log(source.id, '❌ 预取验证墙 + 空产出 → 上抛验证异常');
        debugPrint('[ScriptResolver] 上抛预取验证墙异常');
        throw prefetchVerificationError;
      }
      // detail 路由兜底：脚本若未返回 detailUrl，或返回了无效占位符 `{}`，
      // 优先用 id 推导（id 是 URL/相对路径时），其次用实际请求 URL 填充，
      // 保证所有脚本源详情页都能显示正确的浏览器按钮（共创式，不针对单个源）。
      if (apiName == 'detail' && result is MediaItem) {
        final du = result.detailUrl;
        if (du == null || du.isEmpty || du.contains('{}')) {
          String? fallback;
          final id = result.id;
          if (id.startsWith('http://') || id.startsWith('https://')) {
            fallback = id;
          } else if (id.startsWith('/')) {
            final base = ConfigLoader.instance.getActiveMirror(source);
            final b =
                base.endsWith('/') ? base.substring(0, base.length - 1) : base;
            fallback = '$b$id';
          } else if (url.isNotEmpty && !url.contains('{}')) {
            fallback = url;
          }
          if (fallback != null && fallback.isNotEmpty) {
            return result.copyWith(detailUrl: fallback);
          }
        }
      }
      return result;
    } on SourceResolveException catch (e) {
      ParseDiagnostics.log(source.id, '❌ 解析异常: ${e.message}');
      rethrow;
    } on WebViewHtmlRequest {
      // 脚本经 meta 协议声明 __webview 且无头渲染失败：原样上抛，供 UI 层
      // 走「抓取本页渲染内容」可见流程（不得包装成 SourceResolveException）。
      rethrow;
    } on VerificationRequiredException {
      // 预取撞验证墙且脚本空产出时重抛（见上方 prefetchVerificationError）：
      // 原样上抛供 UI 层走验证流程，包装成 SourceResolveException 会让
      // 用户永远看不到 CF/登录验证入口。
      rethrow;
    } catch (e) {
      ParseDiagnostics.log(source.id, '❌ 未知异常: $e');
      throw SourceResolveException(
        sourceId: source.id,
        apiName: apiName,
        message: e.toString(),
      );
    } finally {
      engine.dispose();
    }
  }

  /// 渲染后 HTML 回灌入口：UI 层在内嵌 WebView 加载页面、JS 渲染完成后
  /// 取回整页 HTML，调用本方法把 [html] 作为 `raw` 参数喂给脚本入口（替代
  /// 脚本内 `ctx.http.get(url)` 抓未渲染 HTML 的旧路径）。
  ///
  /// 与 [resolve] 共享 [_runScriptWithRaw]（脚本/入口选取 + 执行 + `_toTyped`
  /// 转换），但跳过 `engine.bridge.httpGet/httpGetJson` 抓取步骤；不再触发
  /// [WebViewHtmlRequest]（已由调用方提供渲染后 HTML，避免回灌循环）。
  Future<dynamic> resolveFromHtml(
    PluginConfig source,
    String apiName,
    String html, {
    Map<String, String> vars = const {},
  }) async {
    final factory = engineFactory ?? defaultEngineFactory;
    final engine = factory(source);
    engine.injectContext(vars);
    try {
      return await _runScriptWithRaw(source, apiName, html, engine);
    } on SourceResolveException {
      rethrow;
    } on WebViewHtmlRequest {
      // 与 resolve() 对齐：可见抓取请求原样上抛，不包装成 SourceResolveException。
      rethrow;
    } catch (e) {
      throw SourceResolveException(
        sourceId: source.id,
        apiName: apiName,
        message: e.toString(),
      );
    } finally {
      engine.dispose();
    }
  }

  /// 共用脚本执行 helper：选取脚本/入口、运行（10s 超时）、按 apiName 转换
  /// 类型化结果。供 [resolve]（[raw] 为抓回的 HTML/JSON）与 [resolveFromHtml]
  /// （[raw] 为回灌的 HTML）复用，避免重复实现。
  Future<dynamic> _runScriptWithRaw(
    PluginConfig source,
    String apiName,
    dynamic raw,
    JsEngine engine,
  ) async {
    // 选取脚本与入口函数（考虑 hybrid overrides + golden 覆盖写法）。
    // 入口名优先级：override.function（golden 写法）> override.entrypoints[api]
    // > parser.entrypoints[api] > apiName（直接以 api 名作函数名）。
    final override = source.parser.overrides?[apiName];
    final String script;
    final String entry;
    if (source.parser.type == 'hybrid' && override != null) {
      script = override.script ?? source.parser.script ?? '';
      entry = override.function ??
          override.entrypoints?[apiName] ??
          apiName;
    } else {
      script = source.parser.script ?? '';
      entry = override?.function ??
          source.parser.entrypoints?[apiName] ??
          apiName;
    }
    debugPrint('[ScriptResolver] _runScriptWithRaw: entry=$entry, scriptLength=${script.length}, rawLength=${raw is String ? (raw as String).length : "non-string"}');
    try {
      final rawResult = await engine
          .run(script, entry, <dynamic>[raw])
          .timeout(const Duration(seconds: 10));

      // JS 引擎（flutter_js / QuickJS）的 stringResult 常返回非严格 JSON 的
      // JS 字面量字符串（如 [{id: foo, title: bar}] 键名无引号），导致
      // JsContext 内部 jsonDecode 失败后回退为原始 String。
      // 此处做防御性解码：若结果为 String 且形似 JSON（以 [ 或 { 开头），
      // 尝试 jsonDecode；失败则保持原值交由 _toTyped 处理。
      var result = _decodeEngineResult(rawResult);

      // ══════════════════════════════════════════════════════════
      // Meta→预取→处理 协议（flutter_js 真机无法执行 async function 的解决方案）
      // ══════════════════════════════════════════════════════════
      //
      // 背景：flutter_js 在真机上 evaluateAsync 对任何 Promise/async 均返回
      // "Instance of 'Future<dynamic>'" 字符串，handlePromise/isPromise 全部失效。
      // 唯一能工作的异步通道是桥接自身的 __resolveBridge（解单个 HTTP 请求），
      // 但不传播到脚本级 Promise 返回值。
      //
      // 解决方案：需要异步数据的脚本改为两步同步模式：
      // Step 1 (sync): 脚本提取参数 + 返回 meta 描述符 {__meta:true, __fetchUrl, __processor}
      // Step 2 (Dart): ScriptResolver 检测到 meta → 用源配置(防盗链/UA)在 Dart 侧 HTTP 预取
      // Step 3 (sync): 用预取数据调用处理器函数(__processChapters 等) → 返回最终结果
      //
      // 对已有同步脚本的影响：零。result 不是 Map 或不含 __meta 键时完全跳过。
      //
      // 链式：处理器返回的结果若仍是 meta 描述符，则再走一跳（Step 2→3 循环），
      // 用于「先取 id 再提交」这类两步接口（如收藏要先 GET 作品详情拿 uuid、
      // 再 POST collect）。上限 4 跳，避免脚本写错时反复打站点。
      // 单跳脚本（现有全部源）处理器直接返回数据，循环一次即退出，无副作用。
      var hop = 0;
      const maxMetaHops = 4;
      // meta 预取地址的拼接基准：源激活镜像 base（与路由 URL 同语义）。
      final metaBase = ConfigLoader.instance.getActiveMirror(source);
      while (result is Map &&
          (result as Map<dynamic, dynamic>)['__meta'] == true &&
          ((result as Map<dynamic, dynamic>)['__fetchUrl'] is String ||
              (result as Map<dynamic, dynamic>)['__fetchUrls'] is List) &&
          hop < maxMetaHops) {
        hop++;
        final meta = result as Map<dynamic, dynamic>;
        {
          // 裸块：沿用原单跳处理体的缩进，diff 最小化。
          final rawFetchUrl = meta['__fetchUrl'] as String? ?? '';
          // 根相对路径（/vodplay/1-1-1.html）按路由语义拼到激活镜像 base，
          // 绝对地址仅校验不改动；校验失败返回空串（见 _resolveMetaFetchUrl）。
          final fetchUrl = _resolveMetaFetchUrl(rawFetchUrl, metaBase);
          final processor = meta['__processor'] as String? ?? '';
          // meta 协议扩展字段（通用，仍不写死任何站点逻辑）：
          // __fetchMethod : 'get'(默认) | 'post'
          // __fetchBody : POST body 字符串（通常为 JSON.stringify(query)）
          // __fetchHeaders : 请求头 Map（如 {'Content-Type':'application/json'}）
          // __fetchResponseType : 'json'(默认) | 'text' —— 预取返回原始文本而非 JSON
          // 用于需要 POST 的源（如部分源的 GraphQL），以及需要抓取非 JSON 文本
          // （如加密域名文件）的源。GET 源不受影响。
          final fetchMethod =
              (meta['__fetchMethod'] as String? ?? 'get').toLowerCase();
          final fetchBody = meta['__fetchBody'] as String?;
          // 批量预取：源可给 `__fetchUrls`（字符串数组）代替单个 `__fetchUrl`，
          // 用于「一页只有 N 个入口、真实数据要逐个跟进」的站点（如画廊逐页取图）。
          // 引擎在 Dart 侧并发抓取，结果按输入顺序组成 List<String> 交给
          // `__processor` 同步处理。通用能力，不含任何站点逻辑。
          final rawFetchUrls = (meta['__fetchUrls'] as List?)
                  ?.map((e) => e.toString())
                  .where((e) => e.isNotEmpty)
                  .toList(growable: false) ??
              const <String>[];
          final fetchUrls = rawFetchUrls
              .map((u) => _resolveMetaFetchUrl(u, metaBase))
              .toList(growable: false);
          // 安全校验不通过（非 http(s) 或 localhost/私有等保留地址）→ 原始地址
          // 非空但解析结果为空：终止 meta 链按预取失败降级，绝不发起该请求。
          final unsafeFetch = (rawFetchUrl.isNotEmpty ||
                  rawFetchUrls.isNotEmpty) &&
              fetchUrl.isEmpty &&
              fetchUrls.isEmpty;
          if (unsafeFetch) {
            debugPrint(
                '[ScriptResolver] meta 预取地址被安全校验拒绝: url=$rawFetchUrl urls=$rawFetchUrls');
            ParseDiagnostics.log(source.id,
                '❌ meta预取地址被拒(非http(s)/保留host): $rawFetchUrl');
            result = const <dynamic>[];
            continue;
          }
          final fetchConcurrency =
              (meta['__fetchConcurrency'] as num?)?.toInt() ?? 0;
          final fetchHeaders = <String, String>{};
          final rawHeaders = meta['__fetchHeaders'];
          if (rawHeaders is Map) {
            rawHeaders.forEach((k, v) => fetchHeaders[k.toString()] = v.toString());
          }
          // 通用：按源 `comments.login` 声明附加受保护请求鉴权头。
          // 由 sourceAuthHeader 统一处理两种模式（不写死站点）：
          // - sendTokenAs:"bearer" → Authorization: Bearer <checkCookie 值>
          // - sendTokenAs:"key" → Authorization: <authScheme 默认 Key> <手动 apiKey>
          // 并非所有站点都用 Bearer——部分站点的 v2 API 明确「用 Key <api_key>，
          // 不是 Bearer」（401 报文已证实），故改用 "key" 模式，正确
          // 携带用户在登录面板粘贴的 API Key。完全由源的 login 配置驱动。
          final authHeader = sourceAuthHeader(source);
          if (authHeader != null) {
            fetchHeaders.addAll(authHeader);
          }
          debugPrint(
              '[ScriptResolver] 检测到 meta 协议: method=$fetchMethod, fetch=$fetchUrl, processor=$processor');
          ParseDiagnostics.log(
              source.id, '📡 meta协议($fetchMethod): $apiName → 预取 $fetchUrl');

          // 通用扩展：`__webview: true` → 脚本需要 JS 渲染后的完整页面
          // （plain HTTP 只能拿到未渲染/拒显壳）。先无头 WebView 静默渲染抓取
          // （对齐 WebViewResolver webview-html 模式的「静默优先」体验）：UA 取
          // 源 webviewConfig.extraUserAgent（源声明移动 UA 时按移动浏览器渲染）。
          // 渲染失败或处理器解析仍为空 → 抛 [WebViewHtmlRequest]，由阅读器既有
          // 「抓取本页渲染内容」可见流程回灌重试（resolveFromHtml）。
          final wantsWebview =
              meta['__webview'] == true && fetchUrl.isNotEmpty;
          if (wantsWebview && processor.isNotEmpty) {
            // 源声明 `__webviewScroll: true` → 渲染后逐屏滚动触发懒加载注入
            // （图片由站点 JS 在滚动进视口时才写入 DOM 的页面）。
            final wantsScroll = meta['__webviewScroll'] == true;
            await WebviewSourceNetwork.instance.applyForSource(source);
            String? rendered;
            try {
              rendered = await SilentHtmlCapture.capture(
                fetchUrl,
                headers: fetchHeaders.isNotEmpty ? fetchHeaders : null,
                userAgent: source.webviewConfig.extraUserAgent,
                scrollToLoad: wantsScroll,
              );
            } finally {
              await WebviewSourceNetwork.instance.releaseForSource();
            }
            debugPrint(
                '[ScriptResolver] webview 渲染抓取: url=$fetchUrl, len=${rendered?.length ?? "null"}');
            ParseDiagnostics.log(
                source.id, '📺 webview渲染($apiName): ${rendered?.length ?? 0} 字符');
            if (rendered == null || rendered.isEmpty) {
              // 无头渲染失败（挑战页/加载失败/WebView 不可用）→ 升级可见抓取。
              throw WebViewHtmlRequest(
                sourceId: source.id,
                apiName: apiName,
                url: fetchUrl,
                headers: source.site.headers,
              );
            }
            final processResult = await engine
                .run(script, processor, <dynamic>[rendered])
                .timeout(const Duration(seconds: 10));
            result = _decodeEngineResult(processResult);
            final listLen = result is List ? result.length : 0;
            if (listLen > 0) {
              ParseDiagnostics.log(
                  source.id, '✅ webview渲染解析成功: List[$listLen]');
            } else {
              // 渲染成功但解析仍空 → 先用已暖会话（无头 WebView 已同步 cookie）
              // 再直连抓取一次：部分站点对「带会话的普通 HTTP」返回内嵌完整
              // 数据的服务端变体，而冷请求/无头渲染只拿到懒加载壳。直连结果
              // 交给同一处理器；仍为空才升级可见抓取。
              debugPrint(
                  '[ScriptResolver] webview 渲染后解析为空，尝试暖会话直连兜底');
              ParseDiagnostics.log(source.id, '🔁 webview抽空→暖直连再试: $fetchUrl');
              String? warmHtml;
              try {
                final referer = source.antiHotlinking.referer ?? fetchUrl;
                final net =
                    NetworkConfigService.instance.effectiveFor(source);
                warmHtml = await HttpFetcher.instance.getHtml(
                  fetchUrl,
                  headers: fetchHeaders.isNotEmpty ? fetchHeaders : null,
                  referer: referer,
                  net: net,
                );
              } catch (e) {
                debugPrint('[ScriptResolver] 暖会话直连失败: $e');
              }
              var warmLen = warmHtml?.length ?? 0;
              ParseDiagnostics.log(
                  source.id, '📥 暖直连: $warmLen 字符');
              if (warmHtml != null && warmHtml.isNotEmpty) {
                try {
                  final warmResult = await engine
                      .run(script, processor, <dynamic>[warmHtml])
                      .timeout(const Duration(seconds: 10));
                  final warmDecoded = _decodeEngineResult(warmResult);
                  final warmLen2 =
                      warmDecoded is List ? warmDecoded.length : 0;
                  if (warmLen2 > 0) {
                    result = warmDecoded;
                    ParseDiagnostics.log(
                        source.id, '✅ 暖直连解析成功: List[$warmLen2]');
                  }
                } catch (e) {
                  debugPrint('[ScriptResolver] 暖直连处理器异常: $e');
                }
              }
              if (result is! List || result.isEmpty) {
                // 暖直连也没有结果 → 升级可见抓取。
                debugPrint('[ScriptResolver] 暖直连仍为空，升级可见抓取');
                throw WebViewHtmlRequest(
                  sourceId: source.id,
                  apiName: apiName,
                  url: fetchUrl,
                  headers: source.site.headers,
                );
              }
            }
          } else if (processor.isNotEmpty &&
              (fetchUrl.isNotEmpty || fetchUrls.isNotEmpty)) {
            try {
              // Step 2: Dart 侧预取（使用源的防盗链/UA 配置 + 源级网络覆盖）
              final referer =
                  source.antiHotlinking.referer ??
                      ConfigLoader.instance.getActiveMirror(source);
              final net =
                  NetworkConfigService.instance.effectiveFor(source);
              // 通用扩展：源可通过 __fetchResponseType 指定预取返回原始文本
              // （默认 "json"）。用于需要抓取非 JSON 文本（如加密配置/域名文件）
              // 的源，避免把站点逻辑写死进 Dart。镜像页自动获取 JM 域名即其一例。
              final fetchResponseType =
                  (meta['__fetchResponseType'] as String? ?? 'json').toLowerCase();
              final bool batch = fetchUrls.isNotEmpty;
              // 单条预取的 JSON 分支改用带头变体：部分站点把播放凭证放在
              // 响应头（如 Set-Cookie 的 CloudFront 签名三件套），仅回 body
              // 会让源侧脚本永远拿不到 → 播放 403。响应头作为处理器第二
              // 参数交回（现有单参处理器零影响；批量路径保持原语义）。
              dynamic apiJson;
              Map<String, String> respHeaders = const <String, String>{};
              if (batch) {
                apiJson = await _fetchMany(
                  urls: fetchUrls,
                  method: fetchMethod,
                  body: fetchBody,
                  headers: fetchHeaders,
                  referer: referer,
                  net: net,
                  responseType: fetchResponseType,
                  limit: fetchConcurrency,
                );
              } else if (fetchMethod == 'post') {
                if (fetchResponseType == 'text') {
                  // text 带头变体：meta 预取的 POST 文本响应同样需要响应头
                  // （3xx 的 Location、播放凭证等），与 JSON 带头变体同语义。
                  (apiJson, respHeaders) =
                      await HttpFetcher.instance.postTextWithHeaders(
                    fetchUrl,
                    data: fetchBody,
                    headers: fetchHeaders.isNotEmpty ? fetchHeaders : null,
                    referer: referer,
                    net: net,
                  );
                } else {
                  (apiJson, respHeaders) =
                      await HttpFetcher.instance.postJsonWithHeaders(
                    fetchUrl,
                    data: fetchBody,
                    headers: fetchHeaders.isNotEmpty ? fetchHeaders : null,
                    referer: referer,
                    net: net,
                  );
                }
              } else if (fetchResponseType == 'text') {
                apiJson = await HttpFetcher.instance.getHtml(
                  fetchUrl,
                  headers: fetchHeaders.isNotEmpty ? fetchHeaders : null,
                  referer: referer,
                  net: net,
                );
              } else {
                (apiJson, respHeaders) =
                    await HttpFetcher.instance.getJsonWithHeaders(
                  fetchUrl,
                  headers: fetchHeaders.isNotEmpty ? fetchHeaders : null,
                  referer: referer,
                  net: net,
                );
              }
              final payloadInfo = apiJson is Map
                  ? 'keys=${(apiJson as Map).keys}'
                  : (apiJson is String
                      ? 'text len=${apiJson.length}'
                      : apiJson.runtimeType.toString());
              final fetchLabel =
                  batch ? '${fetchUrls.length} 个 URL(批量)' : fetchUrl;
              debugPrint('[ScriptResolver] 预取成功: $fetchLabel, $payloadInfo');
              ParseDiagnostics.log(source.id, '✅ 预取成功: $fetchLabel');

              // Step 3: 调用 JS 处理函数（纯同步，传入预取数据；
              // 单条路径附响应头作第二参数，供源提取播放凭证）。
              final processResult = await engine
                  .run(script, processor,
                      batch ? <dynamic>[apiJson] : <dynamic>[apiJson, respHeaders])
                  .timeout(const Duration(seconds: 10));
              result = _decodeEngineResult(processResult);
              debugPrint(
                  '[ScriptResolver] 处理器 $processor 完成: ${result is List ? "List[${(result as List).length}]" : result.runtimeType}');
              ParseDiagnostics.log(
                  source.id,
                  '✅ 处理器$processor完成: ${result is List ? "List[${(result as List).length}]" : result.runtimeType}');
            } on Object catch (e) {
              // 失败时把 401 真实响应体打出来，便于定位「鉴权被读但拒绝」的根因
              // （如收藏接口要 sessionid 而非 Bearer access_token）。
              // VerificationRequiredException / HttpStatusException 都带 body 字段，
              // 但 toString() 只打状态码与 url，故此处单独提取 body。
              String bodyHint = '';
              if (e is VerificationRequiredException &&
                  e.body != null &&
                  e.body!.isNotEmpty) {
                final b = e.body!;
                bodyHint = ' body=${b.length > 400 ? '${b.substring(0, 400)}…' : b}';
              } else if (e is HttpStatusException &&
                  e.body != null &&
                  e.body!.isNotEmpty) {
                final b = e.body!;
                bodyHint = ' body=${b.length > 400 ? '${b.substring(0, 400)}…' : b}';
              }
              debugPrint('[ScriptResolver] meta 预取/处理失败: $e$bodyHint');
              ParseDiagnostics.log(source.id, '❌ meta协议失败: $e$bodyHint');
              result = []; // 优雅降级为空列表
            }
          }
        }
      }

      debugPrint('[ScriptResolver] _runScriptWithRaw ✅ 完成: ${result is List ? "List[${(result as List).length}]" : result.runtimeType}');
      return _toTyped(apiName, result, sourceId: source.id);
    } on TimeoutException {
      throw SourceResolveException(
        sourceId: source.id,
        apiName: apiName,
        message: 'script timeout (>10s)',
      );
    }
  }

  /// meta 协议的批量预取：并发抓取 [urls]，按输入顺序返回响应列表。
  ///
  /// 用途：某些站点「一页只给出 N 个入口，真实数据要逐个跟进」（如画廊页只给
  /// 缩略图链接、原图要进每个页面取）。脚本侧逐个 await 会触发几十次桥接往返，
  /// 且容易撞上脚本执行超时；改为在 Dart 侧并发抓取后一次性交回脚本同步处理。
  ///
  /// 容错：单个 URL 失败时该位置填 `null`（不中断整批），由脚本决定降级策略
  /// （跳过 / 保留占位）。源可通过 `__fetchConcurrency` 限制并发（默认 6，
  /// 上限 16），避免对站点造成突发压力。
  static Future<List<dynamic>> _fetchMany({
    required List<String> urls,
    required String method,
    String? body,
    required Map<String, String> headers,
    required String referer,
    required EffectiveNetworkProfile net,
    required String responseType,
    int limit = 0,
  }) async {
    final concurrency = limit <= 0
        ? _defaultFetchConcurrency
        : limit.clamp(1, _maxFetchConcurrency);
    final results = List<dynamic>.filled(urls.length, null, growable: false);
    var cursor = 0;
    final workers = <Future<void>>[];
    final effectiveHeaders = headers.isEmpty ? null : headers;
    for (var i = 0; i < concurrency && i < urls.length; i++) {
      workers.add(() async {
        while (true) {
          final index = cursor++;
          if (index >= urls.length) return;
          final url = urls[index];
          try {
            results[index] = method == 'post'
                ? (responseType == 'text'
                    ? await HttpFetcher.instance.post(
                        url,
                        data: body,
                        headers: effectiveHeaders,
                        referer: referer,
                        net: net,
                      )
                    : await HttpFetcher.instance.postJson(
                        url,
                        data: body,
                        headers: effectiveHeaders,
                        referer: referer,
                        net: net,
                      ))
                : (responseType == 'text'
                    ? await HttpFetcher.instance.getHtml(
                        url,
                        headers: effectiveHeaders,
                        referer: referer,
                        net: net,
                      )
                    : await HttpFetcher.instance.getJson(
                        url,
                        referer: referer,
                        headers: effectiveHeaders,
                        net: net,
                      ));
          } on Object catch (e) {
            debugPrint('[ScriptResolver] 批量预取失败($index/$url): $e');
          }
        }
      }());
    }
    await Future.wait(workers);
    return results;
  }

  /// 批量预取的默认并发数与硬上限。
  static const int _defaultFetchConcurrency = 6;
  static const int _maxFetchConcurrency = 16;

  /// meta 预取地址解析（通用，不写死站点逻辑）：
  ///
  /// 脚本返回的 `__fetchUrl` / `__fetchUrls` 常是根相对路径（如
  /// `/vodplay/1-1-1.html`）——与路由 URL 同语义拼接到源激活镜像 base 上；
  /// 绝对地址（含 scheme 相对 `//host/x`）经 Uri.resolve 原样保留。
  ///
  /// 返回空串表示「原始地址非空但未通过安全校验」（调用方按本跳失败降级）。
  /// 校验对齐 Mimosa 安全约束：仅允许 http/https，host 拒绝 localhost、
  /// 环回、私有与保留地址。
  static String _resolveMetaFetchUrl(String raw, String base) {
    final url = raw.trim();
    if (url.isEmpty) return url;
    final lower = url.toLowerCase();
    final String resolved;
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      resolved = url;
    } else {
      final b = base.endsWith('/') ? base : '$base/';
      final parsed = Uri.tryParse(url);
      final baseUri = Uri.tryParse(b);
      if (parsed == null || baseUri == null) return url; // 畸形交由下游失败
      resolved = baseUri.resolveUri(parsed).toString();
    }
    return _isSafeHttpUrl(resolved) ? resolved : '';
  }

  /// 测试可见：锁死 meta 预取地址「相对拼接 + 安全校验」契约。
  @visibleForTesting
  static String debugResolveMetaFetchUrl(String raw, String base) =>
      _resolveMetaFetchUrl(raw, base);

  /// SSRF 防护：仅接受 http/https，且 host 不是 localhost/环回/私有/保留地址。
  /// 普通域名不在静态层判断（DNS 解析侧限制超出本层职责）。
  static bool _isSafeHttpUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    if ((scheme != 'http' && scheme != 'https') || host.isEmpty) return false;
    if (host == 'localhost' || host.endsWith('.localhost')) return false;
    // IPv4-mapped IPv6（::ffff:127.0.0.1）先还原成 IPv4 再判。
    if (host.startsWith('::ffff:') && host.contains('.')) {
      return _isSafeIPv4(host.substring(7));
    }
    final addr = InternetAddress.tryParse(host);
    if (addr == null) return true; // 域名主机名，静态层放行
    if (addr.type == InternetAddressType.IPv4) return _isSafeIPv4(addr.address);
    // IPv6：`::`（未指定）、`::1`（环回）、fe80::/10（链路本地）、
    // fc00::/7（唯一本地）、ff00::/8（组播）一律拒绝。
    if (host == '::' || host == '::1') return false;
    final first = int.tryParse(host.split(':').first, radix: 16);
    if (first == null) return true;
    return !((first & 0xffc0) == 0xfe80 ||
        (first & 0xfe00) == 0xfc00 ||
        (first & 0xff00) == 0xff00);
  }

  /// IPv4 保留段判定：未指定(0/8)、环回(127/8)、私有(10/8、172.16/12、
  /// 192.168/16)、链路本地(169.254/16)、CGNAT(100.64/10)、文档段与组播/保留。
  static bool _isSafeIPv4(String address) {
    final o =
        address.split('.').map((e) => int.tryParse(e) ?? -1).toList();
    if (o.length != 4 || o.any((e) => e < 0 || e > 255)) return false;
    bool r(int v, int lo, int hi) => v >= lo && v <= hi;
    return !(o[0] == 0 ||
        o[0] == 10 ||
        o[0] == 127 ||
        (o[0] == 169 && o[1] == 254) ||
        (o[0] == 172 && r(o[1], 16, 31)) ||
        (o[0] == 192 && o[1] == 168) ||
        (o[0] == 100 && r(o[1], 64, 127)) ||
        (o[0] == 192 && o[1] == 0 && o[2] == 2) ||
        (o[0] == 198 && o[1] == 51 && o[2] == 100) ||
        (o[0] == 203 && o[1] == 0 && o[2] == 113) ||
        o[0] >= 224);
  }

  /// JS 引擎返回值的防御性解码。
  ///
  /// flutter_js / QuickJS 的 stringResult 可能是：
  /// - 严格 JSON → JsContext 内部已 jsonDecode，直接得到 List/Map
  /// - 非 JSON 的 JS 字面量 String（键名无引号）→ 内部 jsonDecode 失败回退为 String
  /// - 空值 / 基本类型
  ///
  /// 本方法处理第二种情况：String 且形似 JSON 时再尝试一次解码（含容错）。
  static dynamic _decodeEngineResult(dynamic raw) {
    if (raw is List || raw is Map) return raw;
    if (raw is! String || raw.isEmpty) return raw;
    final trimmed = raw.trim();
    if (!trimmed.startsWith('[') && !trimmed.startsWith('{')) return raw;
    try {
      return jsonDecode(trimmed);
    } on FormatException {
      // 严格 JSON 解析失败，尝试修正常见非 JSON 模式后重试
      try {
        return _lenientJsonDecode(trimmed);
      } on Object {
        debugPrint('[ScriptResolver] ⚠️ 引擎结果无法解码为JSON, 长度=${raw.length}, 前100字符: ${raw.length > 100 ? raw.substring(0, 100) : raw}');
        return raw;
      }
    }
  }

  /// 宽松 JSON 解码：尝试修复 JS 字面量中常见的非严格格式问题。
  ///
  /// 仅处理脚本返回的最常见模式：[{id: val, title: "str", ...}]
  /// 即键名无双引号 / 单引号包裹的值等。不做完整 JS 表达式解析。
  static dynamic _lenientJsonDecode(String input) {
    // 给无引号的键名加双引号: {id: → {"id":
    var fixed = input.replaceAllMapped(
      RegExp(r'(?<=[{\s,])([a-zA-Z_][a-zA-Z0-9_]*)\s*:'),
      (m) => '"${m[1]}":',
    );
    // 给单引号字符串值换成双引号: 'value' → "value"
    fixed = fixed.replaceAllMapped(
      RegExp(r"'([^']*)'"),
      (m) => '"${m[1]}"',
    );
    return jsonDecode(fixed);
  }

  dynamic _toTyped(String apiName, dynamic result, {String? sourceId}) {
    if (result == null) {
      return apiName == 'detail' ? null : <MediaItem>[];
    }
    switch (apiName) {
      case 'detail':
        return _toItem(result, fallbackSourceId: sourceId);
      case 'episodes':
      case 'chapters':
        return _toEpisodes(result);
      case 'images':
        return _toImages(result);
      case 'video':
        return _toVideo(result);
      case 'mirrors':
        // 源自建的「镜像列表」路由：返回 [{name,domain,baseUrl}] 原样透传，
        // 供镜像页自动获取，不做 MediaItem 强转（源即插件，不写死站点逻辑）。
        return _toRawList(result);
      case 'folders':
        // 网络收藏文件夹列表：返回 [{title,url,value,...}]，同样是「原样透传」
        // 给 UI 自己解释的结构，绝不能套 MediaItem 强转（否则 `e is Map` 恒 false、
        // 文件夹列表永远为空 → 切换条/列表都不显示）。
        return _toRawList(result);
      default:
        return _toItems(result, sourceId: sourceId);
    }
  }

  /// 把脚本返回的镜像列表原样透传（元素为含 name/domain/baseUrl 的 Map）。
  List<dynamic> _toRawList(dynamic result) {
    if (result is! List) return const [];
    return result.whereType<Map<dynamic, dynamic>>().toList();
  }

  List<MediaItem> _toItems(dynamic result, {String? sourceId}) {
    if (result is! List) return const [];
    return [for (final e in result) if (e is Map) _toItem(e, fallbackSourceId: sourceId)];
  }

  MediaItem _toItem(dynamic m, {String? fallbackSourceId}) {
    final map = m as Map<dynamic, dynamic>;
    final detailUrl = _str(map['detailUrl']).isNotEmpty
        ? _str(map['detailUrl'])
        : _str(map['detail']);
    // 脚本返回值通常不含 sourceId（由 ScriptResolver 从当前源自动注入）；
    // 若脚本显式返回了 sourceId 则优先使用，否则用调用方传入的 fallback。
    final sid = _str(map['sourceId']).isNotEmpty
        ? _str(map['sourceId'])
        : (fallbackSourceId ?? '');
    return MediaItem(
      id: _str(map['id']),
      title: _str(map['title']),
      coverUrl: _str(map['cover']),
      detailUrl: detailUrl,
      sourceId: sid,
      description: _str(map['description']),
      author: _str(map['author']),
      // 解析导演/主演，供「按导演/主演检索」客户端过滤使用（小说/漫画源通常为空，无害）。
      director: _str(map['director']).isNotEmpty ? _str(map['director']) : null,
      actors: _str(map['actors']).isNotEmpty ? _str(map['actors']) : null,
      status: _str(map['status']),
      tags: _tags(map['tags']),
      updatedAt: _parseDateTime(map['updatedAt']),
      wordCount: _str(map['wordCount']).isNotEmpty ? _str(map['wordCount']) : null,
      // 详情页解析出的作者/标签落地页链接，供"点作者/标签即检索"使用（源侧提供）。
      authorUrl: _str(map['authorUrl']).isNotEmpty ? _str(map['authorUrl']) : null,
      tagUrls: _tagUrls(map['tagUrls']),
    );
  }

  List<Episode> _toEpisodes(dynamic result) {
    if (result is! List) return const [];
    return [
      for (final e in result)
        if (e is Map)
          Episode(
            id: _str(e['id']),
            title: _str(e['title']),
            url: _str(e['url']),
            updatedAt: _parseDateTime(e['updatedAt']),
            number: _parseInt(e['number']),
          ),
    ];
  }

  VideoResult _toVideo(dynamic result) {
    if (result is Map) {
      final url = _str(result['url']);
      // 源可返回多条线路（key 为 `urls` 或 `lines`，元素可为字符串或
      // {url,name,headers} 对象）；非空时播放器「线路」面板即可切换。
      final lines = _toVideoLines(result['urls'] ?? result['lines']);
      // 顶层 `headers`：源返回的播放凭证头（Cookie / Referer / UA 等）。
      // VideoResult 模型本就支持（fromJson 同样在解析），播放器打开媒体时
      // 会随 mpv 请求携带；此前漏透传导致动态 Cookie 类源播放 403。
      final headers = _strMapFrom(result['headers']);
      return VideoResult(
        url: url,
        type: _strOrNull(result['type']),
        headers: headers,
        lines: lines,
      );
    }
    return VideoResult(url: _str(result));
  }

  /// 将脚本返回的 `urls` / `lines` 数组解析为 [VideoLine] 列表（无效项跳过）。
  List<VideoLine> _toVideoLines(dynamic value) {
    if (value is! List) return const <VideoLine>[];
    final out = <VideoLine>[];
    for (final e in value) {
      if (e is String) {
        final u = e.trim();
        if (u.isNotEmpty) {
          out.add(VideoLine(name: '线路 ${out.length + 1}', url: u));
        }
      } else if (e is Map) {
        final u = _str(e['url']).trim();
        if (u.isNotEmpty) {
          final name = _str(e['name']).isNotEmpty
              ? _str(e['name'])
              : '线路 ${out.length + 1}';
          // 行级 `headers`：单线路地址需要独立凭证时由源提供（通用能力）。
          out.add(VideoLine(name: name, url: u, headers: _strMapFrom(e['headers'])));
        }
      }
    }
    return out;
  }

  /// 把脚本返回的 `headers`（Map 或 JSON 字符串）归一为 Map<String, String>。
  Map<String, String>? _strMapFrom(dynamic v) {
    if (v is Map) {
      final out = <String, String>{
        for (final e in v.entries)
          if (e.value != null && e.value.toString().isNotEmpty)
            e.key.toString(): e.value.toString(),
      };
      return out.isEmpty ? null : out;
    }
    return null;
  }

  /// 漫画图片列表（脚本可返回 `['url', ...]` 或 `[{ url }, ...]`）。
  List<String> _toImages(dynamic result) {
    if (result is! List) return const [];
    return <String>[
      for (final e in result)
        if (e is Map) _str(e['url']) else _str(e),
    ].where((s) => s.isNotEmpty).toList();
  }

  String _str(dynamic v) => v?.toString() ?? '';
  String? _strOrNull(dynamic v) => v?.toString();

  /// 把脚本返回的日期/时间戳解析成 [DateTime]。支持 ISO 字符串、毫秒/秒级时间戳。
  DateTime? _parseDateTime(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is int) {
      // 毫秒级时间戳通常 > 1e12；秒级则乘 1000
      if (v > 9999999999) return DateTime.fromMillisecondsSinceEpoch(v);
      return DateTime.fromMillisecondsSinceEpoch(v * 1000);
    }
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  /// 把脚本返回的数字解析成 [int]。
  int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  List<String>? _tags(dynamic v) {
    if (v == null) return null;
    if (v is List) {
      return v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    final s = v.toString();
    if (s.isEmpty) return null;
    return s.split(RegExp(r'[,，/、|\s]+')).where((t) => t.isNotEmpty).toList();
  }

  /// 与 [_tags] 类似，但专用于详情页解析出的"标签落地页链接"列表（不拆分、原样保留 URL）。
  List<String>? _tagUrls(dynamic v) {
    if (v == null) return null;
    if (v is! List) return null;
    final list = v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    return list.isEmpty ? null : list;
  }
}
