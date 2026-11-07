/// 统一 HTTP 实例：Cookie 管理、强制隐身（随机延迟 + UA 轮换）、验证感知。
/// 全应用只应有一个 HttpFetcher 实例（spec：headless WebView 加载前把 Cookie 写入共享 CookieManager）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random, max;
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fast_gbk/fast_gbk.dart';
import '../network/model/effective_network_profile.dart';
import '../network/network_config_service.dart';
import '../network/runtime/network_client_builder.dart';
import '../platform/platform_service.dart';
import '../services/config_loader.dart';
import '../settings/advanced_settings.dart';
import '../utils/app_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'cookie_store.dart';
import 'verification_detector.dart';

/// 浏览器指纹档案：UA 与 `Sec-Ch-Ua` 品牌必须配套，否则会自爆（WAF 一秒识破）。
///
/// 每个档案都对应一个真实存在的 Chrome 版本，UA 字符串里的版本号与
/// `Sec-Ch-Ua` 里 `Chromium`/`Not.A.Brand` 的版本号一致。请求时按 host 固定选用
/// 其中一个，避免同一站点前后请求 UA 漂移。
class _BrowserProfile {
  const _BrowserProfile(this.ua, this.secChUa, this.secChUaMobile, this.secChUaPlatform);
  final String ua;
  final String secChUa;
  final String secChUaMobile;
  final String secChUaPlatform;
}

/// 简单的计数信号量：限制同时进行的任务数。
///
/// 用于 HttpFetcher 的请求闸门——同一时刻最多 [_maxConcurrent] 个请求真正发出，
/// 其余排队，避免一次性并发打爆单站触发限流 / IP 封禁。
class _Semaphore {
  _Semaphore(this._max);
  final int _max;
  int _count = 0;
  final List<Completer<void>> _waiters = <Completer<void>>[];

  Future<void> acquire() {
    if (_count < _max) {
      _count++;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      final completer = _waiters.removeAt(0);
      completer.complete();
    } else {
      _count--;
    }
  }
}

class HttpFetcher {
  HttpFetcher._() {
    _buildDio();
  }

  static final HttpFetcher instance = HttpFetcher._();

  /// 调试/特殊网络环境下强制直连（绕过系统代理）。默认 false，不影响正常行为。
  static bool forceDirect = false;

  /// 默认档案 Dio（对应全局有效档案 / `net == null`）。
  late Dio _dio;

  /// 按有效档案签名隔离的 Dio 缓存（源级覆盖用）。
  final Map<String, Dio> _dioByProfile = <String, Dio>{};
  final Map<String, String> _cookieJar = {};

  /// 验证冷却：命中验证的 host 在冷却期内，[_throttleHost] 会延长最小间隔，
  /// 避免「验证期间继续高频打站」触发更严苛的限流 / IP 封禁。
  final Map<String, DateTime> _verifyCooldown = {};

  /// 验证冷却时长：抛出 [VerificationRequiredException] 时给该 host 记入
  /// 「此刻 + 该时长」的冷却，期间后续请求被节流。
  static const Duration _verifyCooldownDuration = Duration(seconds: 20);

  /// 可选代理（如 `127.0.0.1:7890`）。非空时所有 Dio 请求经此代理；
  /// 为 null 时沿用系统/环境代理，保持默认行为。
  static String? proxy;

  /// 会话 Cookie 版本。每次 [syncCookies] 自增并广播，供封面图加载层
  /// （[SourceImage]）在「验证回灌 Cookie」后立刻重取此前因缺 Cookie 而加载
  /// 失败的封面（_guard 等反爬系统对图片同样校验会话，否则返回 403/空）。
  int _cookieVersion = 0;
  final StreamController<int> _cookieVersionController =
      StreamController<int>.broadcast();
  Stream<int> get cookieVersionStream => _cookieVersionController.stream;
  int get cookieVersion => _cookieVersion;

  /// 每域名固定的浏览器指纹档案序号：保证同一站点每次请求用同一套 UA/指纹，
  /// 既轮换了不同站点之间的指纹，又不会在单次会话里自相矛盾。
  final Map<String, int> _hostProfile = {};

  /// 源声明的 User-Agent 按 host 覆盖（如笔趣阁移动端 UA）。
  ///
  /// 书源可能在 header 里声明特定 UA，移动站点加固反爬后会拒绝中心化桌面
  /// UA。直接请求与 WebView 验证、后续重试必须共用同一 UA，否则会话 Cookie
  /// 绑定到不同 UA → 验证死循环。由 [AnalyzeUrl] 在发起请求时按 host 注册，
  /// 作为 [userAgentForUrl] 的最高优先级（仅低于高级设置的全局默认 UA）。
  final Map<String, String> _hostUaOverrides = {};

  /// 注册某 host 的源声明 UA（覆盖中心化指纹 UA）。空 host/UA 直接忽略。
  void registerHostUserAgent(String host, String ua) {
    if (host.isEmpty || ua.isEmpty) return;
    _hostUaOverrides[host] = ua;
  }

  /// 测试专用：暴露 [_mergeHeaders] 的真实结果，用于锁死「宿主级 UA 覆盖必须
  /// 进入实际请求头」这一契约（验证屏/登录屏注册的浏览器 UA 与抓取请求共
  /// 用，cf_clearance 才不会失效）。
  @visibleForTesting
  Map<String, String> debugMergedHeaders({
    String? referer,
    Map<String, String>? extra,
    String? url,
  }) =>
      _mergeHeaders(referer, extra, url);

  /// 测试专用：清除宿主级 UA 覆盖，避免用例间串味。
  @visibleForTesting
  void debugClearHostUserAgents() => _hostUaOverrides.clear();

  static final List<_BrowserProfile> _profiles = const <_BrowserProfile>[
    _BrowserProfile(
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      '"Chromium";v="124", "Google Chrome";v="124", "Not-A.Brand";v="99"',
      '?0',
      '"Windows"',
    ),
    _BrowserProfile(
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36 Edg/123.0.0.0',
      '"Chromium";v="123", "Not.A.Brand";v="99", "Microsoft Edge";v="123"',
      '?0',
      '"Windows"',
    ),
    _BrowserProfile(
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      '"Chromium";v="120", "Google Chrome";v="120", "Not-A.Brand";v="99"',
      '?0',
      '"macOS"',
    ),
  ];

  /// 为某 host 选定（或复用）指纹档案序号。
  int _profileIndexFor(String? host) {
    if (host == null || host.isEmpty) return 0;
    return _hostProfile.putIfAbsent(host, () => _random.nextInt(_profiles.length));
  }

  final Random _random = Random();

  void _buildDio() {
    _dio = _createDio(null);
  }

  /// 按有效档案创建一个配置好的 Dio。
  ///
  /// [profile] 为 null 表示默认档案（运行时用全局有效档案）；否则用该档案。
  /// 客户端构建统一走 [NetworkClientBuilder]，与全局 HttpOverrides 同一路径。
  Dio _createDio(EffectiveNetworkProfile? profile) {
    final dio = Dio()
      // 头名保留原始大小写。**不要去掉**：Dart HttpClient 默认把所有请求头
      // 名小写化（`user-agent`、`host`...），而部分 WAF（实测 hanime1.me 的
      // Cloudflare）把「头名全小写」当作机器人指纹——同一 IP、同一头值，仅
      // 头名小写就稳定 403（curl 发正确大小写的同名头则 200，10+ 次对照
      // 零例外）。preserveHeaderCase 经 BaseOptions → Options.compose 透传到
      // 每个请求（dio ≥5.2），由 IOHttpClientAdapter 原生支持。
      ..options.preserveHeaderCase = true
      // 对齐旧版（AI 修改前可正常解析的版本）：补全浏览器标准请求头。
      // 缺少 Accept / Accept-Language 头时，大量国内站（小说/动漫/漫画）会直接返回 400 空响应。
      ..options.connectTimeout = const Duration(seconds: 15)
      ..options.receiveTimeout = const Duration(seconds: 30);
    dio.options.headers.addAll({
      'User-Agent': _defaultUa(),
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    });

    // 网络日志拦截器（无条件挂载）：请求 / 响应明细走调试级（受「详细日志」
    // 开关控制，避免刷屏）；**异常与错误响应（4xx/5xx/拦截页）走错误级，总是
    // 记录**——这样即使没开详细日志，抓取失败/下载失败也会在运行日志里留痕。
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        AppLog.instance.d('[HTTP] ${options.method} ${options.uri}');
        handler.next(options);
      },
      onResponse: (response, handler) {
        final body = response.data;
        final String bodyDesc;
        if (body is String) {
          bodyDesc = '${body.length} chars';
        } else if (body is List<int>) {
          final b = body;
          // 二进制响应记首 4 字节 hex：一眼区分真图(FFD8/8950/RIFF)与
          // 拦截页/占位图(3C21=<!、7B22={" 等)——定位"下载到 5.8KB 拦截图"。
          final head = b.length >= 4
              ? b.take(4).map((x) => x.toRadixString(16).padLeft(2, '0')).join()
              : (b.isEmpty ? 'empty' : 'short');
          bodyDesc = '${b.length} bytes[0x$head]';
        } else {
          bodyDesc = body == null ? 'empty' : '${body.runtimeType}';
        }
        final int code = response.statusCode ?? 0;
        final String line = '[HTTP] $code '
            '${response.requestOptions.uri} -> $bodyDesc';
        // 4xx/5xx = 请求失败，总是记录（错误级）；2xx/3xx 走调试级。
        if (code >= 400) {
          AppLog.instance.e(line);
        } else {
          AppLog.instance.d(line);
        }
        handler.next(response);
      },
      onError: (DioException e, handler) {
        final String line = '[HTTP!] ${e.requestOptions.method} '
            '${e.requestOptions.uri} -> ${e.type} ${e.message}';
        // 网络异常总是记录（错误级）——不依赖详细日志开关。
        AppLog.instance.e(line);
        handler.next(e);
      },
    ));

    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => _httpClientFor(profile),
    );
    return dio;
  }

  /// 构造某档案的裸 [HttpClient]（= 一个连接池的载体）。
  ///
  /// 独立成方法是为了让 [_dropConnectionPool] 能在**不重建 Dio** 的前提下换掉
  /// 整个连接池——同一工厂产出的新客户端语义与初始完全一致（同样的代理/hosts/
  /// SNI 配置），只是池子是空的。
  HttpClient _httpClientFor(EffectiveNetworkProfile? profile) {
    try {
      final service = NetworkConfigService.instance;
      final effective = profile ?? service.globalProfile;
      final client = NetworkClientBuilder.buildHttpClient(
        effective,
        proxyPassword: service.proxyPassword,
      );
      // 向后兼容：静态 forceDirect / proxy 覆盖（仅对默认档案生效）。
      if (profile == null) {
        if (forceDirect) {
          client.findProxy = (_) => 'DIRECT';
        } else if (proxy != null && proxy!.isNotEmpty) {
          client.findProxy = (_) => 'PROXY $proxy';
        }
      }
      return client;
    } on Object catch (e, st) {
      // 构建档案失败：回退裸客户端（保留自签容忍），保证该源仍可系统直连。
      debugPrint('HttpFetcher._createDio fallback: $e\n$st');
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      return client;
    }
  }

  /// 按有效档案取/建 Dio：
  /// - `p == null` 或与全局档案同签名 → 复用默认 Dio；
  /// - 否则按签名隔离缓存一个源级 Dio。
  Dio _dioFor(EffectiveNetworkProfile? p) {
    if (p == null) return _dio;
    final globalSig = NetworkConfigService.instance.globalProfile.signature;
    if (p.signature == globalSig) return _dio;
    return _dioByProfile.putIfAbsent(p.signature, () => _createDio(p));
  }

  /// 丢弃指定档案的连接池，强制下一次请求重新建连（从而重新解析 hosts 轮转）。
  ///
  /// **为什么必须这么做（真机实证）**：Dart `HttpClient` 的连接池在收到 403 响应
  /// 后**仍认定该 keep-alive 连接可复用**（403 不触发连接失效）。探针实测：4 次
  /// 请求、`connectionFactory` 只被调用 2 次，坏 IP 的连接被反复取回；换
  /// `Connection: close` 请求头也压不住（第 3 次仍命中旧连接）。因此仅靠
  /// `DnsResolver` 的 hosts 轮转游标是**空转**——必须连池子一起换，新连接才会再
  /// 走一次连接工厂、拿到下一个候选 IP。
  ///
  /// 实现要点：**不能对已挂在 Dio 上的 adapter 调 `close()`**——`IOHttpClientAdapter
  /// .close()` 会把内部 `_closed` 置 true，此后该 adapter 的每次 fetch 都直接抛
  /// `StateError`（永久不可用）。正确做法是给 Dio 换上一个全新的 adapter（同一
  /// [_httpClientFor] 工厂 ⇒ 代理/hosts/SNI 语义与初始完全一致，只是池子是空的），
  /// 再把被丢弃的旧 adapter 优雅关闭：不打断正在并发的请求，只是握手后不再复用。
  void _dropConnectionPool(EffectiveNetworkProfile? net) {
    final Dio dio = _dioFor(net);
    // 与 _dioFor 的归一化保持一致：默认 Dio 用 null 档案建客户端，以保留
    // forceDirect / proxy 的向后兼容覆盖分支。
    final globalSig = NetworkConfigService.instance.globalProfile.signature;
    final bool isDefault = net == null || net.signature == globalSig;
    final EffectiveNetworkProfile? profile = isDefault ? null : net;
    final HttpClientAdapter old = dio.httpClientAdapter;
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => _httpClientFor(profile),
    );
    // adapter.close() 默认 force=false = 优雅关闭：空闲连接立即释放，活跃连接
    // 完成本次请求后再关闭（不会像 force=true 那样掐断并发请求）。
    if (old is IOHttpClientAdapter) old.close();
  }

  /// 重建所有 Dio（全局配置变更时调用）：丢弃旧连接池，新配置即时生效。
  void rebuildAll() {
    for (final d in _dioByProfile.values) {
      d.close(force: true);
    }
    _dioByProfile.clear();
    _dio.close(force: true);
    _buildDio();
  }

  /// 运行时切换直连模式（重建全部 Dio 实例）。
  static void setForceDirect(bool value) {
    forceDirect = value;
    instance.rebuildAll();
  }

  /// 运行时切换代理（重建全部 Dio 实例）。
  static void setProxy(String? value) {
    proxy = value;
    instance.rebuildAll();
  }

  /// 返回某 URL 实际使用的 UA（经 [_profileIndexFor] 选定的指纹档案）。
  ///
  /// 全应用唯一真源：WebView 验证、AnalyzeUrl 直连、源 JSON 的 UA 都应调用本
  /// 方法取得，确保「过验证的 UA」与「后续 HTTP 重试的 UA」完全一致，避免 UA
  /// 漂移导致 Cookie 失效 → 验证死循环（幻梦ACG _guard 滑块反复弹的核心根因）。
  String userAgentForUrl(String url) => _uaForHost(Uri.tryParse(url)?.host ?? '');

  /// 取该 host 实际使用的 UA（供调用方在注册/覆盖前查询）。
  String userAgentForHost(String host) => _uaForHost(host);

  /// 按浏览器 referrer-policy 默认行为推导「子资源 Referer」。
  ///
  /// 浏览器加载页面内图片等子资源时：同源 → 发送完整页面 URL；跨域 → 只发送
  /// 页面 origin（strict-origin-when-cross-origin）。部分站点（如按 kid↔章节
  /// 绑定校验 Referer 的 GraphQL 漫画站）必须携带**所属章节页** Referer 才能
  /// 取图，固定 antiHotlinking.referer 无法满足——调用方（阅读器/下载器）在
  /// 已知「图片所属页面 URL」时用本方法推导，取不到返回 null（回退源配置）。
  static String? refererForSubresource(String? pageUrl, String resourceUrl) {
    if (pageUrl == null || pageUrl.isEmpty) return null;
    if (!pageUrl.startsWith('http://') && !pageUrl.startsWith('https://')) {
      return null;
    }
    final Uri? page = Uri.tryParse(pageUrl);
    if (page == null || page.host.isEmpty) return null;
    final Uri? res = Uri.tryParse(resourceUrl);
    if (res == null || res.host.isEmpty) return null;
    final bool sameOrigin = res.scheme == page.scheme &&
        res.host == page.host &&
        res.port == page.port;
    if (sameOrigin) return pageUrl;
    try {
      return page.origin;
    } on Object {
      // origin 对非 http(s) 会抛异常，但上面已过滤；兜底手拼。
      return '${page.scheme}://${page.host}';
    }
  }


  /// 完整浏览器 UA：优先用户配置的全局默认 UA；否则移动系平台（Android /
  /// 鸿蒙）返回与系统浏览器一致的**移动版** UA，其他平台返回内置桌面 UA。
  ///
  /// 供 Cloudflare 验证（turnstile）使用——部分源声明的 UA 极简（如
  /// `Mozilla/5.0`）被 CF 判定为不合法浏览器 → 挑战 600010；而把 Windows 桌面
  /// UA 硬塞给移动 WebView 会造成「声称桌面、实为移动 WebView」的环境矛盾，
  /// 同样触发 600010。移动版 UA 与用户手机上能正常过 turnstile 的系统浏览器
  /// 一致，环境自洽（鸿蒙 ArkWeb 同为移动内核，故共用移动版 UA）。
  String fullBrowserUserAgent() {
    final String custom = _customUa();
    if (custom.isNotEmpty) return custom;
    if (!kIsWeb &&
        (PlatformService.instance.isAndroid ||
            PlatformService.instance.isOHOS)) {
      return _androidBuiltinUa;
    }
    return _defaultBuiltinUa;
  }

  /// Android 移动版 Chrome UA（与用户手机系统 Chrome 一致，能正常过 turnstile）。
  static const String _androidBuiltinUa =
      'Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  /// 高级设置「默认 UA」：非空时全局固定使用该 UA（覆盖指纹档案轮换）。
  String _customUa() => AdvancedSettingsStore.instance.defaultUserAgent;

  /// Dio 基础头的默认 UA（非 gated 请求 / 缺头兜底路径）。
  String _defaultUa() {
    final custom = _customUa();
    return custom.isNotEmpty ? custom : _defaultBuiltinUa;
  }

  static const String _defaultBuiltinUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  String _uaForHost(String host) {
    final custom = _customUa();
    if (custom.isNotEmpty) return custom;
    // 源声明 UA 优先：保证「直连请求 == WebView 验证 == 重试」三处 UA 一致，
    // 避免 Cookie 绑定错位导致的验证死循环（笔趣阁等移动站点）。
    final override = _hostUaOverrides[host];
    if (override != null && override.isNotEmpty) return override;
    return _profiles[_profileIndexFor(host)].ua;
  }

  /// 启动时从 [CookieStore] 回填内存 Cookie jar，避免每次冷启动都重新过验证
  /// （冷启动即丢 Cookie 是「反复验证 → 高频请求 → IP 被封」的首要根因）。
  Future<void> loadPersistedCookies() async {
    try {
      final persisted = await CookieStore.loadDetailed();
      for (final e in persisted.entries) {
        final normalized = _normalizeCookieHeader(e.value['cookie'] ?? '');
        if (normalized.isEmpty) continue;
        _cookieJar[e.key] = normalized;
        // 一并恢复该 host 记录里的 UA：cf_clearance / turnstile 通过态绑定 UA，
        // 冷启动只回灌 Cookie 而让 UA 落到随机指纹档案 → 会话立即失效。
        final ua = e.value['ua'];
        if (ua != null && ua.isNotEmpty) {
          _hostUaOverrides[e.key] = ua;
        }
      }
    } catch (e, st) {
      debugPrint('loadPersistedCookies failed: $e\n$st');
    }
  }

  /// 记录该 host 进入验证冷却（见 [_verifyCooldown] 与 [_throttleHost]）。
  void _markVerification(String url) {
    final host = Uri.tryParse(url)?.host;
    if (host != null && host.isNotEmpty) {
      _verifyCooldown[host] = DateTime.now().add(_verifyCooldownDuration);
    }
  }

  /// 记录验证冷却并抛出 [VerificationRequiredException]（统一入口）。
  Never _recordAndThrowVerify(
    String url,
    Map<String, String>? headers,
    String? body,
    int? statusCode,
  ) {
    _markVerification(url);
    throw VerificationRequiredException(
      url: url,
      headers: headers,
      body: body,
      statusCode: statusCode,
    );
  }

  /// 同 host 最小间隔 + 验证冷却：保证短时间内同一站点不会被高频打爆，
  /// 避免触发限流 / IP 封禁。
  Future<void> _throttleHost(String url) async {
    final host = Uri.tryParse(url)?.host;
    if (host == null || host.isEmpty) return;
    // 严格 per-host 串行队列：把本次请求链接到该 host 上一次请求之后。
    // 原实现的「读时间戳 → await → 写时间戳」没有互斥，并发请求会各自按同一个
    // 旧时间戳算出几乎相同的等待时长，到期后一起放行，形成突发请求。
    // 对突发敏感的站点会以「挂起不响应」回应，表现为 15s 连接超时。
    final Future<void> prev = _hostGates[host] ?? Future<void>.value();
    final Completer<void> done = Completer<void>();
    _hostGates[host] = done.future;
    await prev;
    try {
      final now = DateTime.now();
      var earliest =
          _hostLastSent[host]?.add(Duration(milliseconds: _minHostGapMs)) ?? now;
      final cd = _verifyCooldown[host];
      if (cd != null && cd.isAfter(earliest)) earliest = cd;
      final gap = earliest.difference(DateTime.now()).inMilliseconds;
      if (gap > 0) await Future.delayed(Duration(milliseconds: gap));
      _hostLastSent[host] = DateTime.now();
      // 冷却到期即清理，避免无限堆积。
      if (cd != null && DateTime.now().isAfter(cd)) {
        _verifyCooldown.remove(host);
      }
    } finally {
      if (!done.isCompleted) done.complete();
    }
  }

  /// 测试可见：仅执行同 host 节流 + 冷却等待（不含并发信号量/隐身延迟），
  /// 便于单测断言验证冷却行为。
  Future<void> runGate(String url) => _throttleHost(url);

  /// 测试可见：手动写入某 host 的验证冷却（生产代码由验证异常自动写入）。
  void setVerifyCooldown(String host, DateTime until) {
    _verifyCooldown[host] = until;
  }

  Future<void> _stealthDelay() async {
    // 强制隐身：请求前随机延迟 300~1100ms，降频 + 打散节拍，避免被识别为脚本。
    // 用 Random 而不是时间戳取模（后者可预测、固定间隔更可疑）。
    final ms = 300 + _random.nextInt(800);
    await Future.delayed(Duration(milliseconds: ms));
  }

  /// 并发闸门：限制全局同时发出的请求数，并在同一 host 上强制最小间隔，
  /// 避免一次性并发请求触发站点限流 / IP 封禁（如批量下载、首页多板块并发抓取、
  /// 详情页同时拉取详情+选集+推荐）。
  ///
  /// 流程：① 全局信号量排队（[release] 在请求方法末尾的 finally 中调用）→
  /// ② 同 host 最小间隔（同一站点两次请求至少间隔 [_minHostGapMs]）→
  /// ③ 隐身随机延迟（打散节拍）。
  static const int _maxConcurrent = 3;
  // 连接层瞬时错误（连接重置/超时）最大重试次数：共尝试 [_maxHttpRetries + 1] 次。
  // 针对部分站点对并发/过快请求直接 RST 的观感问题（收藏页/标签搜索偶发空白）。
  static const int _maxHttpRetries = 2;
  // 「服务端挂起」（连接/接收超时）时的重试上限：只补 1 次。
  // 挂起基本等于限流信号，密集重试会延长限流窗口，因此比 RST 更保守。
  static const int _maxThrottledRetries = 1;
  // 「无挑战体的硬 403」最大重试次数：共尝试 [_max403Retries + 1] 次。
  // Cloudflare 等限流/IP 软封禁多为短窗口，短暂退避后重试常常直接放行，
  // 避免单次抖动直接弹验证提示打断浏览。带挑战体（JS 挑战页/滑块）或 401
  // 仍立即上抛走 WebView 验证流程，不在此重试。
  //
  // 这只在「该 host 没有 hosts 候选」时是最终预算；有候选时按候选数自适应
  // （[_retry403Budget]），因为这类 403 往往只能靠换 IP 解决。
  static const int _max403Retries = 2;

  // 403 自适应重试的封顶：退避是 1.5s 递增（1500/3000/4500…），候选再多也不能
  // 让单次抓取无限期挂着——用户宁可看到验证提示，也不要转圈半分钟。
  static const int _max403RetriesCap = 5;
  // 手动跟随重定向的最大跳数（防重定向循环打爆）。
  static const int kMaxRedirects = 5;
  // 同 host 最小间隔：原 500ms，上调到 800ms 进一步降低「短时间内连续请求
  // 同一站点」触发风控 / IP 封禁的概率（首页板块已在 OnlineContentListScreen
  // 内串行化抓取，这里再加一层保险）。
  static const int _minHostGapMs = 800;
  final _Semaphore _requestSemaphore = _Semaphore(_maxConcurrent);
  final Map<String, DateTime> _hostLastSent = <String, DateTime>{};
  // 每个 host 的串行队列尾：新请求挂到尾部，保证同站请求严格一前一后放行。
  final Map<String, Future<void>> _hostGates = <String, Future<void>>{};

  Future<void> _gateRequest(String url, bool stealth) async {
    // 1) 全局并发上限：超过则在此排队，直至有空闲名额（在请求方法 finally 中释放）。
    await _requestSemaphore.acquire();
    // 2) 同 host 最小间隔 + 验证冷却：防止短时间内同一站点被打爆。
    await _throttleHost(url);
    // 3) 隐身随机延迟（打散节拍）。
    if (ConfigLoader.instance.getStealthMode() && stealth) {
      await _stealthDelay();
    }
  }

  Map<String, String> _mergeHeaders(
    String? referer, [
    Map<String, String>? extra,
    String? url,
  ]) {
    // 每次请求实际发出的头。必须显式带上 Accept / Accept-Language：
    // 大量国内站（小说/动漫/漫画）会拒绝缺这些头的请求，直接回 400 空响应。
    // 注意：此处若不写全，会被请求级 Options(headers) 整体覆盖，基础配置的头不生效。
    final host = Uri.tryParse(url ?? '')?.host;
    final profile = _profiles[_profileIndexFor(host)];
    final customUa = _customUa();
    // 宿主级 UA 覆盖（验证屏/登录屏经 [registerHostUserAgent] 注册的完整浏览器
    // UA）必须与 WebView 保持一致：Cloudflare 的 cf_clearance 与 turnstile 通过态
    // 绑定「验证时那个 UA」，一旦抓取请求改用指纹档案 UA，该会话对抓取请求即失效
    // → 每次点击都要求重新验证。此前只有图片/播放器/WebView 走 [userAgentForUrl]
    // 读取覆盖，HTML/JSON 抓取走指纹档案 —— [userAgentForUrl] 注释里承诺的
    // 「直连请求 == WebView 验证 == 重试 三处 UA 一致」从未真正落实。
    final hostUa = host == null ? null : _hostUaOverrides[host];
    final overrideUa = (hostUa != null && hostUa.isNotEmpty) ? hostUa : null;
    final uaIsHostOverride = customUa.isEmpty && overrideUa != null;
    final merged = <String, String>{
      // 浏览器指纹：UA 与 Sec-Ch-Ua 品牌配套，避免自爆。
      // 「默认 UA」非空时用户指定固定 UA，指纹档案的 Sec-Ch-Ua 仍保留
      // （作为配套品牌声明，尽力避免因缺头被 WAF 拦截）。
      // 覆盖 UA 来自 WebView（移动端 Android/桌面 Chromium），与指纹档案的品牌
      // 通常不符；UA 与客户端提示自相矛盾本身就是显眼的自动化特征，故此时
      // 不再声明 Sec-Ch-Ua 三家头。
      'User-Agent': customUa.isNotEmpty
          ? customUa
          : (overrideUa ?? profile.ua),
      if (!uaIsHostOverride) ...<String, String>{
        'Sec-Ch-Ua': profile.secChUa,
        'Sec-Ch-Ua-Mobile': profile.secChUaMobile,
        'Sec-Ch-Ua-Platform': profile.secChUaPlatform,
      },
      // 现代浏览器标准头：WAF/Cloudflare 用这些判定是否真人。缺了极易被拦。
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Accept-Encoding': 'gzip, deflate',
      'Sec-Fetch-Dest': 'document',
      'Sec-Fetch-Mode': 'navigate',
      'Sec-Fetch-Site': 'same-origin',
      'Sec-Fetch-User': '?1',
      'Upgrade-Insecure-Requests': '1',
      'Connection': 'keep-alive',
      // 显式 Host 头（保留大写形态）：SDK 自动推导的 host 头名恒为小写——
      // _updateHostHeader 走 _set 私有路径，不记录 _originalHeaderNames，
      // preserveHeaderCase 管不到它。而头名大小写正是部分 WAF（hanime1.me
      // Cloudflare）的机器人判据之一。显式以 'Host' 为键走通用 set 路径
      // （'host' != 'Host'，字符串比较区分大小写），才会记录原始形态。
      // RAW 抓包已验证该形态可行。
      if (host != null && host.isNotEmpty)
        'Host': _hostHeaderValue(Uri.parse(url!)),
      if (referer != null) 'Referer': referer,
      ...?extra,
    };
    // 回带 Cookie（对齐旧版可解析版本）：站点下发的会话 Cookie 需在后续请求带回，
    // 否则部分 MacCMS/源会拒绝（400）或要求验证。匹配父域/子域。
    final cookie = _cookieHeaderFor(url);
    if (cookie != null) {
      // 调用方显式声明的 Cookie（路由 headers / __fetchHeaders / 脚本请求头）
      // 不能被 jar 静默顶掉——「挑战页内联 JS 写 cookie 后重试」类站点，
      // 该 cookie 只存在于显式头里（服务端从不经 Set-Cookie 下发）。
      // 按 cookie 名合并：jar 在前、显式在后，同名以显式值为准。
      final explicit = merged['Cookie'];
      merged['Cookie'] = (explicit == null || explicit.isEmpty)
          ? cookie
          : _mergeCookieHeader(cookie, explicit);
    }
    return merged;
  }

  /// Host 头值：非默认端口必须带 `:port`（与 SDK `_updateHostHeader` 语义一致：
  /// 默认端口省略，非默认端口 `host:port`）。
  static String _hostHeaderValue(Uri uri) {
    final host = uri.host;
    final port = uri.port;
    final bool defaultPort =
        !uri.hasPort || port == (uri.scheme == 'https' ? 443 : 80);
    return defaultPort ? host : '$host:$port';
  }

  /// 取与 [url] 同域（含父域→子域标准作用域）的已存 Cookie，拼成 `Cookie` 头值。
  ///
  /// 匹配规则：请求 host 等于存储 host，或请求 host 是存储 host 的子域
  /// （存储了 `example.com` 的 cookie，请求 `www.example.com` / `api.example.com`
  /// 会带上——标准 cookie 作用域）。
  ///
  /// **不做**「子域存储 → 父域请求」的反向携带：图床等子域（如
  /// 图片 CDN 子域）的会话/挑战 cookie 若被带到主域 API 请求，Cloudflare
  /// 会判定请求异常而返回验证挑战（400）→ 验证反复失败。登录回灌场景的
  /// cookie 已按域正确落 key（含主域），无需反向匹配。
  String? _cookieHeaderFor(String? url) {
    final host = Uri.tryParse(url ?? '')?.host.toLowerCase();
    if (host == null || host.isEmpty) return null;
    final matched = <String>[];
    _cookieJar.forEach((storedHost, cookie) {
      if (cookie.isEmpty) return;
      final s = storedHost.toLowerCase();
      // 仅标准 cookie 作用域：请求==存储域，或请求是存储域的子域
      //（父域/同域 cookie 才作用于子域请求）。
      // 注意：**不能**反向把「子域存储的 cookie 带到父域请求」——图床等子域
      // （如图片 CDN 子域）的会话/挑战 cookie 若被带到主域 API 请求，
      // Cloudflare 会判定请求异常 → 返回验证挑战（400）→ 验证反复失败。
      // 此前曾加入反向分支造成该回归（9c40fab）。
      if (host == s || host.endsWith('.$s')) {
        matched.add(cookie);
      }
    });
    if (matched.isEmpty) return null;
    return matched.join('; ');
  }

  /// 公开取 Cookie 头：供小说侧 [AnalyzeUrl] 等独立 Dio 复用共享 Cookie 存储。
  ///
  /// 验证系统在 WebView（内置浏览器）里被通过后，会话 Cookie 已通过
  /// [syncCookies] 写入本 jar；直连重试时必须带上才能过验证，否则重试仍撞
  /// 验证页（之前 幻梦ACG「系统安全验证」）返空列表。内部复用父域/子域匹配逻辑。
  String? cookieHeaderForUrl(String? url) => _cookieHeaderFor(url);

  /// 将响应字节按字符集解码为字符串。
  ///
  /// 对齐旧版可解析实现：国内大量漫画/小说/动漫源（含部分国内镜像）
  /// 以 **GBK/GB2312/GB18030** 编码返回正文。若直接用 Dio 的 `ResponseType.plain`
  /// 走 UTF-8 解码，中文会变成乱码（烫疽 类字符），正则选择器匹配不到 → 列表空。
  /// 故统一取字节后：先按 Content-Type / <meta charset> 声明的字符集解码；
  /// 声明为 GBK 系列时直接用 [gbk]（fast_gbk，覆盖 GB2312/GB18030 绝大多数情况）
  /// 解码；未声明或声明 utf-8 时走 UTF-8，并对出现大量替换符（U+FFFD）的疑似
  /// 乱码结果再兜底尝试 GBK，避免漏掉未声明 charset 的站点。
  String _decodeBody(List<int> bytes, String? contentType) {
    if (bytes.isEmpty) return '';
    final charset = _detectCharset(bytes, contentType);
    if (charset != null && _isGbkFamily(charset)) {
      try {
        return gbk.decode(bytes);
      } on Object {
        // GBK 解码失败（极罕见非法序列）→ 退回 UTF-8。
      }
    }
    final utf8Str = utf8.decode(bytes, allowMalformed: true);
    if (_hasReplacementChars(utf8Str)) {
      try {
        final g = gbk.decode(bytes);
        if (!_hasReplacementChars(g)) return g;
      } on Object {
        // 忽略，保留 UTF-8 结果。
      }
    }
    return utf8Str;
  }

  /// 从 Content-Type 头与 <meta> 标签探测字符集声明。
  String? _detectCharset(List<int> bytes, String? contentType) {
    if (contentType != null) {
      final m = RegExp(r'charset=([^\s;]+)', caseSensitive: false)
          .firstMatch(contentType);
      if (m != null) return m.group(1)?.trim();
    }
    // 扫描 head 前若干字节内的 <meta charset=...> / <meta http-equiv=...charset=...>
    final headLen = bytes.length < 2048 ? bytes.length : 2048;
    final headAscii = String.fromCharCodes(
      bytes.sublist(0, headLen).map((b) => b < 128 ? b : 0x20),
    );
    final meta =
        RegExp(r'charset[^\w]*=[^\w]*([a-z0-9_-]+)', caseSensitive: false)
            .firstMatch(headAscii.toLowerCase());
    return meta?.group(1);
  }

  /// 是否为 GBK 系列字符集（GBK/GB2312/GB18030 等），统一用 [gbk] 解码。
  static bool _isGbkFamily(String charset) {
    final c = charset.toLowerCase().replaceAll('_', '-');
    return c == 'gbk' ||
        c == 'gb2312' ||
        c == 'gb-2312' ||
        c == 'gb18030' ||
        c == 'gb_2312' ||
        c == 'csgb2312' ||
        c == 'csiso58bgb231280';
  }

  /// 统计文本中 U+FFFD 替换符数量，超过阈值视为 UTF-8 乱码（疑似非 UTF-8 编码）。
  static bool _hasReplacementChars(String s) {
    var count = 0;
    final limit = s.length < 8000 ? s.length : 8000;
    for (var i = 0; i < limit; i++) {
      if (s.codeUnitAt(i) == 0xFFFD) count++;
      if (count > 5) return true;
    }
    return false;
  }

  /// 取 HTML 文本；命中验证特征抛 [VerificationRequiredException]。
  ///
  /// 内置「瞬时连接错误重试」：部分站点会对并发/过快请求直接 RST
  /// （`Connection reset by peer` / 连接超时），单次失败不代表站点不可达。
  /// 对连接层错误（连接重置、连接/接收/发送超时）自动重试最多 [_maxHttpRetries]
  /// 次并递增退避，显著改善「收藏页/标签搜索偶发空白」类问题；4xx/5xx 与验证
  /// 挑战不在此重试（交由各自逻辑处理）。
  /// 进行中的相同 GET 复用表：URL+Referer+头+网络档案完全一致的并发 GET 只发
  /// 一次。真实场景：详情页 detail/episodes 两个解析器并行抓同一 /voddetail
  /// 页、首页板块与其它入口同时拉同一 latest 路由——同站闸门只是把它们排成
  /// 前后两枪，慢站上首屏耗时直接翻倍。仅重叠窗口内共享（完成即移除），
  /// 后续刷新/翻页语义不受影响。
  final Map<String, Future<String>> _inflightGets = <String, Future<String>>{};

  Future<String> getHtml(
    String url, {
    Map<String, String>? headers,
    String? referer,
    bool stealth = true,
    EffectiveNetworkProfile? net,
  }) async {
    final key = _inflightGetKey(url, referer, headers, net);
    final existing = _inflightGets[key];
    if (existing != null) return existing;
    final future = _getHtmlGated(url, headers, referer, net, stealth);
    _inflightGets[key] = future;
    try {
      return await future;
    } finally {
      // 仅当仍是自己时移除：避免误删后来者注册的复用项。
      if (identical(_inflightGets[key], future)) _inflightGets.remove(key);
    }
  }

  /// [getHtml] 的闸门执行体：全局并发 → 同 host 间隔 → 重试，最后释放信号量。
  Future<String> _getHtmlGated(
    String url,
    Map<String, String>? headers,
    String? referer,
    EffectiveNetworkProfile? net,
    bool stealth,
  ) async {
    await _gateRequest(url, stealth);
    try {
      return await _getHtmlWithRetry(url, headers, referer, net);
    } finally {
      _requestSemaphore.release();
    }
  }

  /// 进行中 GET 复用表的键：URL + Referer + 显式头（排序后拼接）+ 网络档案。
  /// 每次请求实际附带的指纹 UA/Cookie 由 URL 唯一决定，无需入键。
  static String _inflightGetKey(
    String url,
    String? referer,
    Map<String, String>? headers,
    EffectiveNetworkProfile? net,
  ) {
    final h = (headers == null || headers.isEmpty)
        ? ''
        : (headers.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key)))
            .map((e) => '${e.key}=${e.value}')
            .join('&');
    return '$url\n${referer ?? ''}\n${net?.signature ?? ''}\n$h';
  }

  /// [getHtml] 的重试包装：对可重试的连接层错误最多重试 [_maxHttpRetries] 次。
  Future<String> _getHtmlWithRetry(
    String url,
    Map<String, String>? headers,
    String? referer,
    EffectiveNetworkProfile? net,
  ) async {
    DioException? lastErr;
    // 外层循环上限必须能容纳 403 路径的自适应预算：否则重试还没走完 hosts 候选表，
    // 循环先耗尽 → 掉到底部兜底 Exception，丢掉 VerificationRequiredException
    // 的验证语义（调用方就弹不出验证提示了）。
    final int budget403 = _retry403Budget(url, net);
    final int maxAttempts = max(_maxHttpRetries, budget403);
    for (var attempt = 0; attempt <= maxAttempts; attempt++) {
      try {
        return await _getHtmlOnce(url, headers, referer, net);
      } on DioException catch (e) {
        if (!_isRetryableNetworkError(e)) rethrow;
        lastErr = e;
        // 超时（连接/接收超时）= 服务端「挂起不响应」，通常是限流信号：
        // 只再试一次且退避更久，否则短时间连打会把对方的限流窗口撑得更长。
        // RST（connectionError）多是瞬时抖动，可以快速多试。
        final bool throttled = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout;
        final int budget = throttled ? _maxThrottledRetries : _maxHttpRetries;
        if (attempt >= budget) rethrow;
        await Future.delayed(_retryBackoff(attempt, throttled: throttled));
      } on VerificationRequiredException catch (e) {
        // 「无 body 的纯硬 403」= 限流/IP 软封禁的短窗口抖动，无任何可交互
        // 验证要素：短暂退避后重试，让瞬时风控抖动在 HTTP 层自愈，而不是直接
        // 把验证提示甩给用户。非空 body（Cloudflare 挑战页/滑块/WAF 拦截词）
        // 与 401（会话失效）不是重试能解决的，立即上抛走原有验证流程。
        final bool hard403 =
            e.statusCode == 403 && (e.body?.trim().isEmpty ?? true);
        // Cloudflare「Edge IP Restricted」(error 1034)：该边缘 IP 未获本站授权，
        // 是**按 IP 判定**的选路失败——无任何可交互验证要素，用户点验证永远过不
        // 去；但换一个已授权的边缘 IP 即可恢复。源站 hosts 表常抄到会过期的 CF
        // 边缘 IP 快照，坏 IP 的 TCP 是通的（CF 边缘对任何 IP 都完成握手）→ 连接
        // 层判定成功 → 应用层拿到这段 403 文本。因此把它当作可重试的选路失败：
        // 退避后重试，让 DnsResolver 轮转到下一个候选 IP。
        final bool edgeIpRestricted = VerificationDetector.isEdgeIpRestricted(
          statusCode: e.statusCode,
          body: e.body,
        );
        if (!hard403 && !edgeIpRestricted) rethrow;
        // 重试耗尽时把最后一次的 VerificationRequiredException（含冷却已写入）
        // 原样上抛，保住验证语义。
        if (attempt >= budget403) rethrow;
        // 每次失败 _recordAndThrowVerify 都会写入验证冷却（影响后续新请求的
        // 闸门），重试成功恢复后不应让同站请求再被 20s 冷却误伤——循环内在
        // 403 路径上清掉；重试耗尽时最后一次异常的冷却保留生效。
        _clearVerifyCooldown(url);
        if (edgeIpRestricted) {
          debugPrint('HttpFetcher: Cloudflare 1034 (Edge IP Restricted) on '
              '$url — 换 IP 重试 attempt=${attempt + 1}/$budget403');
        }
        // 换 IP 之前必须先换连接池，否则轮转是空转（真机实证与原因见
        // [_dropConnectionPool]）。仅在真的有候选 IP 可换时才付这个代价——
        // 纯限流的硬 403 保留原连接更省一次握手。
        if (_hostCandidateCount(url, net) > 1) _dropConnectionPool(net);
        await Future.delayed(_retry403Backoff(attempt));
      }
    }
    // 不可达：循环耗尽却未成功（理论上不会发生，仅兜底）。
    throw lastErr ?? Exception('HTTP 重试耗尽: $url');
  }

  /// 该 host 在有效档案里的 hosts 候选 IP 数（无档案 / 无匹配 / host 为空时 0）。
  int _hostCandidateCount(String url, EffectiveNetworkProfile? net) {
    final hosts = net?.hosts;
    if (hosts == null || hosts.isEmpty) return 0;
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (host.isEmpty) return 0;
    var count = 0;
    for (final h in hosts) {
      if (h.enabled && h.ip.isNotEmpty && h.host.toLowerCase() == host) count++;
    }
    return count;
  }

  /// 403 路径的自适应重试预算：让重试次数足以走遍该 host 的 hosts 候选。
  ///
  /// hosts 表里的坏 IP（Cloudflare 1034 之类）**只能靠换 IP 解决**，而候选表常
  /// 有 5~8 条、坏的可能占多数（真机实测 `hanime1.me` 8 条里 5 条不可用）。固定
  /// 2 次重试（共 3 次尝试）走不完候选表，用户看到的就是「验证提示反复弹」。
  /// 因此按候选数把预算放宽到「覆盖一轮所有候选」，用 [_max403RetriesCap] 封顶；
  /// 无候选时保持 [_max403Retries]，行为与旧版一致。
  int _retry403Budget(String url, EffectiveNetworkProfile? net) {
    final candidates = _hostCandidateCount(url, net);
    if (candidates <= 1) return _max403Retries;
    final int wanted = candidates - 1;
    return max(
      _max403Retries,
      wanted > _max403RetriesCap ? _max403RetriesCap : wanted,
    );
  }

  /// 403 重试退避时长：限流窗口需要比连接抖动更长的等待，
  /// 递增退避 + 抖动打散节拍（避免同一失败的并发请求同时重试形成新突发）。
  Duration _retry403Backoff(int attempt) {
    const int base = 1500;
    final int jitter = _random.nextInt(800);
    return Duration(milliseconds: base * (attempt + 1) + jitter);
  }

  /// 清除某 host 的验证冷却（403 重试循环内使用：退避节拍由重试逻辑控制，
  /// 不叠加验证冷却）。
  void _clearVerifyCooldown(String url) {
    final host = Uri.tryParse(url)?.host;
    if (host != null && host.isNotEmpty) _verifyCooldown.remove(host);
  }

  /// 公开入口：验证已被自动通过后清除该 host 的验证冷却。
  ///
  /// 供 SilentHtmlCapture 自动点击 MacCMS「继续访问」成功后调用：getHtml 检出
  /// 验证页时 [_recordAndThrowVerify] 已写入冷却，但验证随即在 WebView 会话内
  /// 通过并回灌了 Cookie，不该让同站下一个请求再被冷却闸门拖住（对齐 403 重试
  /// 循环内的清理语义）。
  void clearVerifyCooldownForUrl(String url) => _clearVerifyCooldown(url);

  /// 重试退避时长：带随机抖动打散节拍，避免多请求同时重试形成新的突发。
  Duration _retryBackoff(int attempt, {required bool throttled}) {
    final int base = throttled ? 2500 : 600;
    final int jitter = _random.nextInt(throttled ? 1200 : 400);
    return Duration(milliseconds: base * (attempt + 1) + jitter);
  }

  /// 是否可对连接层瞬时错误重试。
  static bool _isRetryableNetworkError(DioException e) {
    return e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout;
  }

  /// 单次 HTML 抓取 + 解析（不含重试），失败的连接层错误直接抛出由上层重试。
  Future<String> _getHtmlOnce(
    String url,
    Map<String, String>? headers,
    String? referer,
    EffectiveNetworkProfile? net,
  ) async {
    final merged = _mergeHeaders(referer, headers, url);
    final resp = await _dioFor(net).get<List<int>>(
      url,
      options: Options(
        headers: merged,
        responseType: ResponseType.bytes,
        validateStatus: (_) => true,
      ),
    );
    final bytes = resp.data ?? const <int>[];
    if (bytes.isEmpty) {
      if (VerificationDetector.isVerificationRequired(
        statusCode: resp.statusCode,
        body: '',
        headers: _responseHeaders(resp),
      )) {
        _recordAndThrowVerify(url, merged, '', resp.statusCode);
      }
      _checkNonVerificationError(url, resp.statusCode, '');
      _storeCookies(url, resp);
      return '';
    }
    final body = _decodeBody(bytes, resp.headers.value('content-type'));
    if (VerificationDetector.isVerificationRequired(
      statusCode: resp.statusCode,
      body: body,
      headers: _responseHeaders(resp),
    )) {
      _recordAndThrowVerify(url, merged, body, resp.statusCode);
    }
    _checkNonVerificationError(url, resp.statusCode, body);
    _storeCookies(url, resp);
    return body;
  }

  /// 仅探测可达性（供镜像测速）：拿到任何 HTTP 响应（含 4xx/5xx）即视为「可达」，
  /// 仅在 DNS/超时/连接被拒等网络层失败时返回 false。避免根域返回 5xx 被误判为
  /// 「无法连接」（如某类 API 镜像根路径只回 500，但 API 正常）。
  Future<bool> isReachable(
    String url, {
    EffectiveNetworkProfile? net,
    Duration? timeout,
  }) async {
    await _gateRequest(url, false);
    try {
      final resp = await _dioFor(net).get<dynamic>(
        url,
        options: Options(
          headers: _mergeHeaders(null, null, url),
          validateStatus: (_) => true,
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
      );
      return resp.statusCode != null && resp.statusCode! > 0;
    } on DioException {
      return false;
    } finally {
      _requestSemaphore.release();
    }
  }

  /// 取 JSON（自动解析）。
  ///
  /// 请求按 JSON API 语义携带 `Accept: application/json`：部分站点按 Accept
  /// 协商响应——对「文档型」请求（Accept: text/html）返回引号被 HTML 转义
  /// （`&quot;code&quot;: 200`）的 HTML 包裹体，jsonDecode 必然失败，表现为
  /// 「搜索/章节等 JSON 路由恒为空」（同一 URL 用浏览器 XHR 头则返回干净 JSON）。
  /// 调用方传 headers 时仍可覆盖。
  Future<dynamic> getJson(
    String url, {
    Map<String, String>? headers,
    String? referer,
    bool stealth = true,
    EffectiveNetworkProfile? net,
  }) async {
    final text = await getHtml(
      url,
      headers: <String, String>{
        'Accept': 'application/json, text/plain, */*',
        ...?headers,
      },
      referer: referer,
      stealth: stealth,
      net: net,
    );
    return _decodeJson(text);
  }

  /// POST 并返回解析后的 JSON（自动解析响应体）。
  /// 用于 meta 协议的 POST 预取分支（如部分源的 GraphQL 查询）。
  Future<dynamic> postJson(
    String url, {
    Map<String, String>? headers,
    Object? data,
    String? referer,
    bool stealth = true,
    EffectiveNetworkProfile? net,
  }) async {
    final text = await post(
      url,
      headers: <String, String>{
        'Accept': 'application/json, text/plain, */*',
        ...?headers,
      },
      data: data,
      referer: referer,
      stealth: stealth,
      net: net,
    );
    return _decodeJson(text);
  }

  /// GET 并返回解析后的 JSON + 响应头（meta 协议带头变体）。
  ///
  /// 部分站点把播放凭证放在 `Set-Cookie`（如 CloudFront 签名 Cookie），
  /// 仅回 body 的 [getJson] 让脚本永远拿不到 → 播放 403。此变体把响应头
  /// 一并交回（多值头用 `, ` 连接，与 [_responseHeaders] 一致），供解析器
  /// 提取凭证注入播放请求头。站点逻辑仍在源侧，不写死任何站点。
  Future<(dynamic, Map<String, String>)> getJsonWithHeaders(
    String url, {
    Map<String, String>? headers,
    String? referer,
    bool stealth = true,
    EffectiveNetworkProfile? net,
  }) {
    return _jsonWithHeaders(
      url,
      method: 'GET',
      headers: <String, String>{
        'Accept': 'application/json, text/plain, */*',
        ...?headers,
      },
      referer: referer,
      stealth: stealth,
      net: net,
    );
  }

  /// POST 并返回解析后的 JSON + 响应头（[postJson] 的带头变体，用途同上）。
  Future<(dynamic, Map<String, String>)> postJsonWithHeaders(
    String url, {
    Map<String, String>? headers,
    Object? data,
    String? referer,
    bool stealth = true,
    EffectiveNetworkProfile? net,
  }) {
    return _jsonWithHeaders(
      url,
      method: 'POST',
      headers: <String, String>{
        'Accept': 'application/json, text/plain, */*',
        ...?headers,
      },
      data: data,
      referer: referer,
      stealth: stealth,
      net: net,
    );
  }

  /// POST 并返回原始文本 + 响应头（[post] 的带头变体）。用途与带头 JSON 变体
  /// 相同——meta 预取需要响应头（如 3xx 的 Location、播放凭证 Cookie）但响应
  /// 并非 JSON（加密信封文本 / 错误页）时的通道。非 2xx 时与 [post] 同语义
  /// （≥400 抛 HttpStatusException，3xx 不抛——重定向被设计关闭，由源侧
  /// 经响应头自行处理）。
  Future<(String, Map<String, String>)> postTextWithHeaders(
    String url, {
    Map<String, String>? headers,
    Object? data,
    String? referer,
    bool stealth = true,
    EffectiveNetworkProfile? net,
  }) async {
    final (body, respHeaders) = await _jsonWithHeaders(
      url,
      method: 'POST',
      headers: <String, String>{
        'Accept': 'application/json, text/plain, */*',
        ...?headers,
      },
      data: data,
      referer: referer,
      stealth: stealth,
      net: net,
      text: true,
    );
    return (body as String, respHeaders);
  }

  /// [_jsonWithHeaders] 的公共实现：与 [_getHtmlOnce] 同语义的请求路径
  /// （验证检测 / Cookie 存储 / 状态码检查），额外把响应头随 body 交回。
  /// [text] 为 true 时返回原始文本（不 JSON 解析）。
  Future<(dynamic, Map<String, String>)> _jsonWithHeaders(
    String url, {
    required String method,
    Map<String, String>? headers,
    Object? data,
    String? referer,
    bool stealth = true,
    EffectiveNetworkProfile? net,
    bool text = false,
  }) async {
    await _gateRequest(url, stealth);
    try {
      final merged = _mergeHeaders(referer, headers, url);
      final resp = await _dioFor(net).request<List<int>>(
        url,
        data: data,
        options: Options(
          method: method,
          headers: merged,
          responseType: ResponseType.bytes,
          validateStatus: (_) => true,
        ),
      );
      final bytes = resp.data ?? const <int>[];
      final body = _decodeBody(bytes, resp.headers.value('content-type'));
      if (VerificationDetector.isVerificationRequired(
        statusCode: resp.statusCode,
        body: body,
        headers: _responseHeaders(resp),
      )) {
        _recordAndThrowVerify(url, merged, body, resp.statusCode);
      }
      _checkNonVerificationError(url, resp.statusCode, body);
      _storeCookies(url, resp);
      return (text ? body : _decodeJson(body), _responseHeaders(resp));
    } finally {
      _requestSemaphore.release();
    }
  }

  /// POST 表单/JSON，返回 HTML 文本。
  Future<String> post(
    String url, {
    Map<String, String>? headers,
    Object? data,
    String? referer,
    bool stealth = true,
    EffectiveNetworkProfile? net,
  }) async {
    await _gateRequest(url, stealth);
    try {
      final merged = _mergeHeaders(referer, headers, url);
      final resp = await _dioFor(net).post<List<int>>(
        url,
        data: data,
        options: Options(
          headers: merged,
          responseType: ResponseType.bytes,
          validateStatus: (_) => true,
        ),
      );
    final body = _decodeBody(resp.data ?? const <int>[], resp.headers.value('content-type'));
    if (VerificationDetector.isVerificationRequired(
      statusCode: resp.statusCode,
      body: body,
      headers: _responseHeaders(resp),
    )) {
      _recordAndThrowVerify(url, merged, body, resp.statusCode);
    }
    _checkNonVerificationError(url, resp.statusCode, body);
    _storeCookies(url, resp);
    return body;
    } finally {
      _requestSemaphore.release();
    }
  }

  /// PUT 请求，返回 HTML 文本（与 [post] 同构，method=PUT）。
  Future<String> put(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? data,
    String? referer,
    bool stealth = true,
    EffectiveNetworkProfile? net,
  }) async {
    _validateScheme(url);
    await _gateRequest(url, stealth);
    try {
      final merged = _mergeHeaders(referer, headers, url);
      final resp = await _dioFor(net).put<List<int>>(
        url,
        data: data,
        options: Options(
          headers: merged,
          responseType: ResponseType.bytes,
          validateStatus: (_) => true,
        ),
      );
    final body = _decodeBody(resp.data ?? const <int>[], resp.headers.value('content-type'));
    if (VerificationDetector.isVerificationRequired(
      statusCode: resp.statusCode,
      body: body,
      headers: _responseHeaders(resp),
    )) {
      _recordAndThrowVerify(url, merged, body, resp.statusCode);
    }
    _checkNonVerificationError(url, resp.statusCode, body);
    _storeCookies(url, resp);
    return body;
    } finally {
      _requestSemaphore.release();
    }
  }

  /// DELETE 请求，返回 HTML 文本。
  Future<String> delete(
    String url, {
    Map<String, String>? headers,
    String? referer,
    bool stealth = true,
    EffectiveNetworkProfile? net,
  }) async {
    _validateScheme(url);
    await _gateRequest(url, stealth);
    try {
      final merged = _mergeHeaders(referer, headers, url);
      final resp = await _dioFor(net).delete<List<int>>(
        url,
        options: Options(
          headers: merged,
          responseType: ResponseType.bytes,
          validateStatus: (_) => true,
        ),
      );
    final body = _decodeBody(resp.data ?? const <int>[], resp.headers.value('content-type'));
    if (VerificationDetector.isVerificationRequired(
      statusCode: resp.statusCode,
      body: body,
      headers: _responseHeaders(resp),
    )) {
      _recordAndThrowVerify(url, merged, body, resp.statusCode);
    }
    _checkNonVerificationError(url, resp.statusCode, body);
    _storeCookies(url, resp);
    return body;
    } finally {
      _requestSemaphore.release();
    }
  }

  /// 表单（application/x-www-form-urlencoded）POST，返回 HTML 文本。
  /// 对应 JS 沙箱 `context.http.postForm(url, params)`：params 为键值对，
  /// 编码为 `k=v&...` 并以该 Content-Type 发送（部分源视频解析用到）。
  Future<String> postForm(
    String url, {
    Map<String, String>? headers,
    Map<String, String>? data,
    String? referer,
    bool stealth = true,
    EffectiveNetworkProfile? net,
  }) async {
    _validateScheme(url);
    await _gateRequest(url, stealth);
    try {
      final body = (data ?? const <String, String>{})
          .entries
          .map((e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');
    final merged = _mergeHeaders(referer, <String, String>{
      'Content-Type': 'application/x-www-form-urlencoded',
      ...?headers,
    }, url);
    final resp = await _dioFor(net).post<List<int>>(
      url,
      data: body,
      options: Options(
        headers: merged,
        responseType: ResponseType.bytes,
        validateStatus: (_) => true,
      ),
    );
    final respBody = _decodeBody(resp.data ?? const <int>[], resp.headers.value('content-type'));
    if (VerificationDetector.isVerificationRequired(
      statusCode: resp.statusCode,
      body: respBody,
      headers: _responseHeaders(resp),
    )) {
      _recordAndThrowVerify(url, merged, respBody, resp.statusCode);
    }
    _checkNonVerificationError(url, resp.statusCode, respBody);
    _storeCookies(url, resp);
    return respBody;
    } finally {
      _requestSemaphore.release();
    }
  }

  /// 通用 fetch：返回 `{status, headers, body}` 映射（JS 沙箱 http.fetch 桥）。
  Future<Map<String, dynamic>> fetch(
    String url, {
    String method = 'GET',
    Map<String, String>? headers,
    String? body,
    String? referer,
    bool stealth = true,
    EffectiveNetworkProfile? net,
  }) async {
    _validateScheme(url);
    await _gateRequest(url, stealth);
    try {
      final merged = _mergeHeaders(referer, headers, url);
      final resp = await _dioFor(net).request<List<int>>(
        url,
        data: body,
        options: Options(
          method: method,
          headers: merged,
          responseType: ResponseType.bytes,
          validateStatus: (_) => true,
        ),
      );
    final respBody = _decodeBody(resp.data ?? const <int>[], resp.headers.value('content-type'));
    if (VerificationDetector.isVerificationRequired(
      statusCode: resp.statusCode,
      body: respBody,
      headers: _responseHeaders(resp),
    )) {
      _recordAndThrowVerify(url, merged, respBody, resp.statusCode);
    }
    _storeCookies(url, resp);
    final respHeaders = <String, String>{};
    resp.headers.map.forEach((k, v) {
      respHeaders[k] = v.join(', ');
    });
    return <String, dynamic>{
      'status': resp.statusCode ?? 0,
      'headers': respHeaders,
      'body': respBody,
    };
    } finally {
      _requestSemaphore.release();
    }
  }

  /// 取原始字节（不解码）：供需要自行按字符集解码的调用方，如 RSS 解析器按
  /// `<?xml encoding=?>` 声明解码，避免非 UTF-8 feed 乱码（修复）。
  ///
  /// 与 [fetch] 同路径（同 host 节流 / 隐身延迟 / 验证检测 / Cookie 注入 / net 隔离），
  /// 但返回的原始字节（`List<int>`）交给调用方解码，而非走共享 `_decodeBody`。
  /// 返回的映射含 `status`(int) / `headers`(Map<String,String>) / `bytes`(List<int>)。
  /// 304 Not Modified 时 `status` 为 304、`bytes` 为空列表，由调用方复用本地缓存。
  Future<Map<String, dynamic>> fetchBytes(
    String url, {
    String method = 'GET',
    Map<String, String>? headers,
    String? body,
    String? referer,
    bool stealth = true,
    EffectiveNetworkProfile? net,
  }) async {
    _validateScheme(url);
    await _gateRequest(url, stealth);
    try {
      final merged = _mergeHeaders(referer, headers, url);
      final resp = await _dioFor(net).request<List<int>>(
        url,
        data: body,
        options: Options(
          method: method,
          headers: merged,
          responseType: ResponseType.bytes,
          validateStatus: (_) => true,
        ),
      );
      final int status = resp.statusCode ?? 0;
      final bytes = resp.data ?? const <int>[];
      // 验证检测需要字符串 body；RSS 响应体不大，用 utf8(allowMalformed) 近似，
      // 仅作验证特征匹配，不影响返回给调用方的原始字节。
      final probe = bytes.isEmpty ? '' : utf8.decode(bytes, allowMalformed: true);
      if (VerificationDetector.isVerificationRequired(
        statusCode: status,
        body: probe,
        headers: _responseHeaders(resp),
      )) {
        _recordAndThrowVerify(url, merged, probe, status);
      }
      _checkNonVerificationError(url, status, probe);
      _storeCookies(url, resp);
      final respHeaders = <String, String>{};
      resp.headers.map.forEach((k, v) {
        respHeaders[k] = v.join(', ');
      });
      return <String, dynamic>{
        'status': status,
        'headers': respHeaders,
        'bytes': bytes,
      };
    } finally {
      _requestSemaphore.release();
    }
  }

  /// 校验 URL scheme 仅允许 http/https（沙箱安全约束）。
  void _validateScheme(String url) {
    final lower = url.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      throw ArgumentError('URL scheme must be http or https: $url');
    }
  }

  /// 把 Dio 的响应头拍平成 `Map<String,String>`（同名多值用逗号拼接）。
  ///
  /// 验证检测需要**响应头**（如 `Server: Edge/1.1.18` 这类 WAF 签名）；旧代码误把
  /// 请求头传给检测器，导致基于响应头的判断永远失效，这里统一取真实响应头。
  static Map<String, String> _responseHeaders(Response<dynamic> resp) {
    final out = <String, String>{};
    resp.headers.map.forEach((k, v) {
      out[k] = v.join(', ');
    });
    return out;
  }

  /// 验证检测通过后，若状态码仍 ≥ 400（如 404/500/502），抛
  /// [HttpStatusException] 以便上层显示明确错误 + 重试，而非把错误页
  /// body 当成正常响应交给解析器导致静默空列表。
  void _checkNonVerificationError(String url, int? statusCode, String body) {
    final code = statusCode;
    if (code != null && code >= 400) {
      throw HttpStatusException(
        url: url,
        statusCode: code,
        body: body,
      );
    }
  }

  /// 取二进制（视频/图片）。
  ///
  /// [fetchDest]：二进制资产请求的 `Sec-Fetch-Dest`（image/video）。必须显式声明
  /// 为资产而非文档：[_mergeHeaders] 默认的 `Sec-Fetch-Dest: document`（页面导航
  /// 头）会令 WAF 判定「伪装的图片请求」→ 统一返回占位图（如某源的 5.8KB
  /// 拦截图）。在线取图走缓存管理器不发这些头，故正常。
  ///
  /// 重定向处理：关掉 Dio 自动跟随，改为**手动解析 3xx 的 Location 直连**。
  /// 实测部分 CDN（如某源旧 CDN 域切换到新 CDN 域）在 Dio
  /// 自动跟随重定向时会返回 403 拦截页（自动跟随的请求头/指纹被 WAF 判定异常），
  /// 而手动解析 Location 后用同一套头直连最终地址可正常取到图片（200）。
  Future<List<int>> getBytes(String url,
      {Map<String, String>? headers,
      EffectiveNetworkProfile? net,
      String? fetchDest = 'image'}) {
    return _getBytesFollow(url, headers, net, fetchDest, 0);
  }

  /// [getBytes] 的实际实现：手动跟随重定向（最多 [kMaxRedirects] 跳防循环）。
  Future<List<int>> _getBytesFollow(
    String url,
    Map<String, String>? headers,
    EffectiveNetworkProfile? net,
    String? fetchDest,
    int depth,
  ) async {
    final Map<String, String> merged = _mergeHeaders(null, <String, String>{
      ...?headers,
      if (fetchDest != null) 'Sec-Fetch-Dest': fetchDest,
      if (fetchDest != null) 'Sec-Fetch-Mode': 'no-cors',
      // 浏览器加载跨域图片/视频时三个 Sec-Fetch-* 一定齐全；只发 Dest+Mode
      // 而删掉 Site 会构成浏览器永远不会发送的残缺组合，部分 CDN 的 WAF 按
      // 该指纹直接 403（比不带这些头更容易被拒）。
      if (fetchDest != null) 'Sec-Fetch-Site': 'cross-site',
    }, url);
    // 资产请求移除「导航专用头」：浏览器加载图片/视频时不发送这些，留着会被
    // WAF 判定为伪装的图片请求 → 统一返回占位图（某源 5.8KB 拦截图）。
    merged.remove('Sec-Fetch-User');
    merged.remove('Upgrade-Insecure-Requests');
    // 图片请求 Accept 不声明 image/avif：Flutter 内置解码器不支持 AVIF（仅
    // Android 12+ 走系统解码器），协商型 CDN 会按 Accept 返回 AVIF → 在线
    // 解码失败显示重试。与 [comic_download_handler] 的下载头对齐；按扩展名
    // 返回的 CDN 不受 Accept 影响。调用方显式给了 Accept 时尊重调用方。
    if (fetchDest == 'image' && !(headers?.containsKey('Accept') ?? false)) {
      merged['Accept'] =
          'image/webp,image/apng,image/jpeg,image/png,image/*,*/*;q=0.8';
    }
    final resp = await _dioFor(net).get<List<int>>(
      url,
      options: Options(
        headers: merged,
        responseType: ResponseType.bytes,
        validateStatus: (_) => true,
        followRedirects: false,
      ),
    );
    final int code = resp.statusCode ?? 0;
    if (code >= 300 && code < 400 && depth < kMaxRedirects) {
      final String? loc =
          resp.headers.value('location') ?? resp.headers.value('Location');
      if (loc != null && loc.isNotEmpty) {
        final Uri next = Uri.parse(loc).isAbsolute
            ? Uri.parse(loc)
            : Uri.parse(url).resolve(loc);
        return _getBytesFollow(next.toString(), headers, net, fetchDest,
            depth + 1);
      }
    }
    return resp.data ?? const [];
  }

  /// 流式下载字节（分块），用于大文件（视频等）避免整块读入内存 OOM。
  ///
  /// 与 [getBytes] 同策略（手动跟随重定向 / 合并防盗链头 / Cookie 注入），
  /// 但返回逐块 `Stream<Uint8List>`（dio `ResponseType.stream`），调用方边收
  /// 边写盘，内存占用恒定。返回的流**已抛错包装**：网络失败会在流中抛出。
  Stream<Uint8List> getBytesStream(
    String url, {
    Map<String, String>? headers,
    EffectiveNetworkProfile? net,
    String? fetchDest = 'video',
    void Function(Map<String, List<String>> headers)? onHeaders,
    void Function(int statusCode)? onStatusCode,
  }) {
    return _getBytesStreamFollow(url, headers, net, fetchDest, 0,
        onHeaders: onHeaders, onStatusCode: onStatusCode);
  }

  Stream<Uint8List> _getBytesStreamFollow(
    String url,
    Map<String, String>? headers,
    EffectiveNetworkProfile? net,
    String? fetchDest,
    int depth, {
    void Function(Map<String, List<String>> headers)? onHeaders,
    void Function(int statusCode)? onStatusCode,
  }) async* {
    final Map<String, String> merged = _mergeHeaders(null, <String, String>{
      ...?headers,
      if (fetchDest != null) 'Sec-Fetch-Dest': fetchDest,
      if (fetchDest != null) 'Sec-Fetch-Mode': 'no-cors',
      // 浏览器加载跨域图片/视频时三个 Sec-Fetch-* 一定齐全；只发 Dest+Mode
      // 而删掉 Site 会构成浏览器永远不会发送的残缺组合，部分 CDN 的 WAF 按
      // 该指纹直接 403（比不带这些头更容易被拒）。
      if (fetchDest != null) 'Sec-Fetch-Site': 'cross-site',
    }, url);
    // 资产请求移除「导航专用头」（同 [getBytes]）。
    merged.remove('Sec-Fetch-User');
    merged.remove('Upgrade-Insecure-Requests');
    // 图片请求 Accept 不声明 image/avif（同 [getBytes]）：协商型 CDN 会按
    // Accept 返回 AVIF → Flutter 解码失败。调用方显式给了 Accept 时尊重调用方。
    if (fetchDest == 'image' && !(headers?.containsKey('Accept') ?? false)) {
      merged['Accept'] =
          'image/webp,image/apng,image/jpeg,image/png,image/*,*/*;q=0.8';
    }
    final resp = await _dioFor(net).get<ResponseBody>(
      url,
      options: Options(
        headers: merged,
        responseType: ResponseType.stream,
        validateStatus: (_) => true,
        followRedirects: false,
      ),
    );
    final int code = resp.statusCode ?? 0;
    // 判定是否继续跟随 3xx：是 → 本跳的头/状态码不回调（调用方判定用最终响应，
    // 若 302 也回调，DioImageFileService 会按 <200||>=300 抛异常取消订阅，递归
    // 跟随永远走不到 → 图片恒 302 失败）；否（非 3xx，或 3xx 但超深度/无
    // Location 无法跟随）→ 回调本跳的头与状态码（3xx 终点交由调用方判定，
    // 避免 status 悬空为 0）。
    final String? redirectLoc = (code >= 300 && code < 400)
        ? (resp.headers.value('location') ?? resp.headers.value('Location'))
        : null;
    final bool followRedirect = redirectLoc != null &&
        redirectLoc.isNotEmpty &&
        depth < kMaxRedirects;
    if (!followRedirect) {
      onHeaders?.call(resp.headers.map);
      onStatusCode?.call(code);
    }
    if (followRedirect) {
      // 3xx 的响应体用不上，但必须排空并关闭底层流：否则连接不会被归还，
      // 触发 "A resource failed to call close"，连接池占满后新请求会一直
      // 挂起到超时（表现为莫名的 connectionTimeout）。
      final body = resp.data;
      if (body != null) {
        try {
          await body.stream.drain<void>();
        } catch (_) {
          // 排空失败不阻塞后续跳转。
        }
      }
      final Uri next = Uri.parse(redirectLoc).isAbsolute
          ? Uri.parse(redirectLoc)
          : Uri.parse(url).resolve(redirectLoc);
      yield* _getBytesStreamFollow(next.toString(), headers, net, fetchDest,
          depth + 1,
          onHeaders: onHeaders, onStatusCode: onStatusCode);
      return;
    }
    if (resp.data == null) return;
    await for (final chunk in resp.data!.stream) {
      yield Uint8List.fromList(chunk);
    }
  }

  /// 下载文件到本地路径，支持进度回调（[onReceiveProgress] = (已接收, 总大小)）。
  ///
  /// 使用内部 Dio 实例，与 [getBytesStream] 同一网络配置（proxy、interceptor、cookie）。
  /// [net] 为源级有效档案（null → 默认档案）；传入后经源档案的连接工厂解析
  /// （hosts 优先 / DoH / 代理），嗅探结果下载等场景用它跟随源网络覆盖。
  Future<void> downloadFile(
    String url,
    String savePath, {
    Map<String, String>? headers,
    EffectiveNetworkProfile? net,
    void Function(int received, int total)? onReceiveProgress,
    CancelToken? cancelToken,
  }) async {
    await _dioFor(net).download(
      url,
      savePath,
      options: Options(headers: headers),
      onReceiveProgress: onReceiveProgress,
      cancelToken: cancelToken,
    );
  }

  /// 获取默认档案的 Dio 实例（供调用方发送自定义请求）。
  Dio get dio => _dio;

  /// 发送 HEAD 请求获取响应头（主要用于获取 Content-Length）。
  ///
  /// [net] 为源级有效档案（null → 默认档案），语义同 [downloadFile]。
  /// 返回响应头映射；请求失败时抛出异常。
  Future<Map<String, List<String>>> head(
    String url, {
    Map<String, String>? headers,
    EffectiveNetworkProfile? net,
  }) async {
    final resp = await _dioFor(net).head<dynamic>(
      url,
      options: Options(headers: headers),
    );
    return resp.headers.map;
  }

  /// 读取系统 WebView Cookie 存储中某 url 的 Cookie 头（与内嵌 InAppWebView 登录
  /// 共享同一份 cookie）。经原生通道 `nexhub/system_cookie` 直连
  /// `android.webkit.CookieManager.getInstance().getCookie(url)`（iOS 未注册时降级为
  /// null）。这是「登录后轮询系统 CookieManager 取会话」的通用做法，
  /// 比 flutter_inappwebview 的 CookieManager 更可靠（后者在某些版本/配置下与
  /// InAppWebView 不是同一存储，导致「登录了但取不到 cookie」）。
  ///
  /// 返回的即为可直接作为 `Cookie` 请求头的字符串（如 `sessionid=...; cf_clearance=...`）。
  static const MethodChannel _systemCookieChannel =
      MethodChannel('nexhub/system_cookie');

  Future<String?> systemCookieHeader(String url) async {
    try {
      final String? r = await _systemCookieChannel.invokeMethod<String>(
        'getCookieHeader',
        <String, dynamic>{'url': url},
      );
      return r;
    } catch (_) {
      return null;
    }
  }

  /// 将任意 Cookie 文本归一化为标准 `name=value; name=value` 头值。
  ///
  /// 兼容常见粘贴/导出格式：标准 `name=value; name=value`、浏览器「复制为
  /// fetch/PowerShell 头」的 `name: value` 换行格式、以及换行分隔的
  /// `name=value` 列表。解析规则：以 `;` 或换行切条目；每个条目取**首个**
  /// `=` 或 `:` 作键值分隔（值内的 `=`/`:` 保持完整不二次拆分）；丢弃无键名、
  /// 值为空或字面 ``null`` 的条目（如导出里 `igneous: null` 表示该项未设置）。
  /// 对已是标准格式的合法输入幂等，故 WebView/浏览器回灌等已正确格式的调用方
  /// 无需改动。
  String _normalizeCookieHeader(String raw) {
    final sb = StringBuffer();
    for (final seg in raw.split(RegExp(r'[;\n]'))) {
      final s = seg.trim();
      if (s.isEmpty) continue;
      final sep = s.indexOf(RegExp(r'[=:]'));
      if (sep <= 0) continue; // 无键名（纯值/损坏片段）跳过
      final name = s.substring(0, sep).trim();
      final value = s.substring(sep + 1).trim();
      if (name.isEmpty || value.isEmpty) continue;
      if (value.toLowerCase() == 'null') continue; // 字面 null 视为未设置
      if (sb.isNotEmpty) sb.write('; ');
      sb.write('$name=$value');
    }
    return sb.toString();
  }

  /// WebView/粘贴/浏览器回灌等共享入口：把 Cookie 头写入内存 jar 并落盘。
  ///
  /// 写入前先经 [_normalizeCookieHeader] 归一化，避免用户粘贴的非标准格式
  /// （如 `name: value` 换行）被原样存入后，在后续请求里触发
  /// `Invalid HTTP header field value` 并导致整次请求失败、内容解析为空。
  void syncCookies(String host, String cookieHeader) {
    final normalized = _normalizeCookieHeader(cookieHeader);
    if (normalized.isEmpty) return;
    _cookieJar[host] = normalized;
    _cookieVersion++;
    if (!_cookieVersionController.isClosed) {
      _cookieVersionController.add(_cookieVersion);
    }
    // 落盘持久化（TTL 7 天），避免重启后重新验证。UA 一并存，回灌时配套校验。
    unawaited(CookieStore.save(host, normalized, _uaForHost(host)));
  }

  String? getCookieHeader(String host) => _cookieJar[host];

  /// 取某 host 下指定名的 cookie 值（从已存 jar 解析），供源在需要时将登录态
  /// 令牌作为 `Authorization: Bearer` 等请求头发送。
  ///
  /// 例：某源登录下发 `access_token`(JWT) 而非后端 `sessionid`，但
  /// `/api/v2/favorites` 等需鉴权接口只认会话/Bearer，仅作 Cookie 不被接受。
  /// 源只要声明 `comments.login.checkCookie: access_token`，调用方即可取出该值
  /// 拼 `Authorization: Bearer <值>`（见 [ScriptResolver] 的 meta 预取路径）。
  /// 不做任何站点硬编码——完全由源的 checkCookie 配置驱动。
  String? cookieValue(String host, String name) {
    final header = _cookieJar[host.toLowerCase()];
    if (header == null || header.isEmpty) return null;
    for (final part in header.split(';')) {
      final kv = part.trim();
      final eq = kv.indexOf('=');
      if (eq <= 0) continue;
      if (kv.substring(0, eq).trim() == name) return kv.substring(eq + 1).trim();
    }
    return null;
  }

  /// 清除所有 Cookie（缓存清除）。
  void clearCookies() {
    _cookieJar.clear();
    unawaited(CookieStore.clear());
  }

  /// 清除单个 host 的 Cookie（源登出）：内存 jar 与持久化记录一并删除，
  /// 并自增 [cookieVersion] 广播，通知登录态缓存（SourceAuthManager）重新评估。
  void clearCookiesFor(String host) {
    _cookieJar.remove(host);
    _cookieVersion++;
    if (!_cookieVersionController.isClosed) {
      _cookieVersionController.add(_cookieVersion);
    }
    unawaited(CookieStore.delete(host));
  }

  void _storeCookies(String url, Response<dynamic> resp) {
    final setCookie = resp.headers['set-cookie'];
    if (setCookie == null || setCookie.isEmpty) return;
    final baseHost = Uri.tryParse(url)?.host ?? '';
    if (baseHost.isEmpty) return;
    // 按 Set-Cookie 声明的 Domain 归类（未声明则回退请求 host）：
    // 服务器常用 Domain=.example.com 下发 cookie，跨子域登录/抓取若只用请求
    // host 作 key，后续请求到其他子域会因单向下域匹配失配而「登录后不回灌」。
    final Map<String, List<String>> byDomain = <String, List<String>>{};
    for (final c in setCookie) {
      final parts = c.split(';');
      final pair = parts.first.trim();
      if (pair.isEmpty || !pair.contains('=')) continue;
      String? domain;
      for (final p in parts.skip(1)) {
        final t = p.trim();
        if (t.toLowerCase().startsWith('domain=')) {
          final d = t.substring(7).trim().replaceFirst(RegExp(r'^\.'), '');
          if (d.isNotEmpty) domain = d.toLowerCase();
          break;
        }
      }
      byDomain
          .putIfAbsent(domain ?? baseHost.toLowerCase(), () => <String>[])
          .add(pair);
    }
    var changed = false;
    byDomain.forEach((host, pairs) {
      final incoming = pairs.join('; ');
      final existing = _cookieJar[host];
      // 按 cookie 名合并：同名后者覆盖前者，重组为去重后的 header。
      // 旧实现直接字符串拼接（`'$existing; $header'`），导致相同会话 Cookie
      // 永远不相等、无法去重，进而每个响应都自增版本 → 所有源封面无限重载。
      final merged = _mergeCookieHeader(existing, incoming);
      if (merged != existing) {
        _cookieJar[host] = merged;
        changed = true;
        // 落盘持久化（TTL 7 天），避免重启后重新验证。UA 一并存，回灌时配套校验。
        unawaited(CookieStore.save(host, merged, _uaForHost(host)));
      }
    });
    // 仅在 Cookie 实际变化时广播版本，通知封面/图片层用新会话重取；
    // 服务端对每个响应重发相同会话 Cookie 时不再触发无谓重载（修复「所有源图片不停刷新」）。
    if (changed) {
      _cookieVersion++;
      if (!_cookieVersionController.isClosed) {
        _cookieVersionController.add(_cookieVersion);
      }
    }
  }

  /// 按 cookie 名合并新旧 header：同名后者覆盖前者，返回重组后的 header。
  ///
  /// 输入可为空；输出按插入顺序为 `name=value` 以 `; ` 连接。仅保留含 `=` 的
  /// 有效对，忽略 `Expires`/`Path`/`Domain` 等属性（调用方只用 `name=value`）。
  String _mergeCookieHeader(String? existing, String incoming) {
    final merged = <String, String>{};
    void putAll(String? src) {
      if (src == null || src.isEmpty) return;
      for (final part in src.split(';')) {
        final kv = part.trim();
        if (kv.isEmpty || !kv.contains('=')) continue;
        final eq = kv.indexOf('=');
        final name = kv.substring(0, eq).trim();
        final value = kv.substring(eq + 1).trim();
        if (name.isNotEmpty) merged[name] = value;
      }
    }

    putAll(existing);
    putAll(incoming);
    final sb = StringBuffer();
    merged.forEach((name, value) {
      if (sb.isNotEmpty) sb.write('; ');
      sb.write('$name=$value');
    });
    return sb.toString();
  }

  dynamic _decodeJson(String text) {
    // 去除 BOM / 首尾空白；失败时退一步截取首个 { 到末个 }。
    final trimmed = text.trim();
    final Object firstError;
    try {
      return jsonDecode(trimmed);
    } on Object catch (e) {
      firstError = e;
    }
    // HTML 实体反转义重试：部分站点（按 Accept 协商）把 JSON 的引号转义成
    // `&quot;` 等实体后返回，直接解析必败。整段反转义后若恰为合法 JSON 则采用。
    // 仅在直接解析失败后才走此分支，响应本就是合法 JSON 时零影响。
    if (trimmed.contains('&quot;') ||
        trimmed.contains('&#x27;') ||
        trimmed.contains('&#39;')) {
      final unescaped = trimmed
          .replaceAll('&quot;', '"')
          .replaceAll('&#x27;', "'")
          .replaceAll('&#39;', "'")
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&amp;', '&');
      try {
        return jsonDecode(unescaped);
      } on Object {
        // 反转义后仍非整体 JSON：交给下方 {..} 截取兜底（用反转义文本）。
        final start = unescaped.indexOf('{');
        final end = unescaped.lastIndexOf('}');
        if (start >= 0 && end > start) {
          return jsonDecode(unescaped.substring(start, end + 1));
        }
      }
    }
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return jsonDecode(trimmed.substring(start, end + 1));
    }
    // 所有兜底均失败：抛出首次解析的真实异常（保留原始错误信息）。
    throw firstError;
  }
}
