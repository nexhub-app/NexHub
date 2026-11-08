/// JS 沙箱桥接层。
///
/// `context` 注入源脚本（仅经此接口，沙箱不可触 Dart 运行时 / 文件系统 / 原生 API）。
/// 宿主能力由 [JsHostBridge] 实现，经 [FlutterJsEngine] 的 message 通道回调。
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../js/js_runtime.dart';
import '../js/js_runtime_factory.dart';

import '../models/plugin_config.dart';
import '../network/model/effective_network_profile.dart';
import '../network/network_config_service.dart';
import '../scraper/http_fetcher.dart';
import '../utils/crypto_utils.dart';
import '../utils/html_utils.dart';
import '../services/config_loader.dart';
import 'image_extractor.dart';
import 'parse_diagnostics.dart';

/// 宿主能力接口（Dart 侧实现，JS 侧经 context 调用）。
abstract class JsHostBridge {
  Future<String> httpGet(String url, {Map<String, String>? headers});
  Future<dynamic> httpGetJson(String url, {Map<String, String>? headers});
  Future<String> httpPost(String url, String body,
      {Map<String, String>? headers});
  Future<String> httpPostForm(String url, Map<String, String> params,
      {Map<String, String>? headers});
  String? query(String html, String selector);
  List<String> queryAll(String html, String selector);
  String? queryAttr(String html, String selector, String attr);
  String? queryXPath(String html, String xpath);
  String? queryHtml(String html, String selector);
  String contentClean(String html);
  String md5(String s);
  String base64Encode(String s);
  String base64Decode(String s);
  String rc4(String data, String key);
  String aesDecrypt(String cipherBase64, String key, String iv);
  String resolveUrl(String relative);
  void log(String msg);

  // ---- crypto extensions  ----
  String sha1(String s);
  String sha256(String s);
  String sha512(String s);
  String hmac(String key, String data, {String algorithm = 'sha256'});
  String hexEncode(List<int> bytes);
  List<int> hexDecode(String hex);
  String aesEcb(String key, String data,
      {bool encrypt = true, String encoding = 'base64'});
  String aesCbc(String key, String data, String iv,
      {bool encrypt = true, String encoding = 'base64'});
  String aesCfb(String key, String data, String iv,
      {bool encrypt = true, String encoding = 'base64'});
  String aesOfb(String key, String data, String iv,
      {bool encrypt = true, String encoding = 'base64'});

  // ---- image (delegates to ImageExtractor) ----
  List<String> extractImagesFromHtml(String html, {String? selector});
  List<String> extractLazyImagesFromHtml(String html, {String? selector});
  bool isValidImageUrl(String url);
  String? guessFormat(String url, {List<int>? bytes});
  List<String> filterImages(List<String> urls, {Map<String, dynamic>? rules});
  List<String> getPageUrls(String html, Map<String, dynamic> config);

  // ---- storage (cross-call persistence, namespaced by sourceId) ----
  String? storageGet(String key);
  void storageSet(String key, String value);
  void storageRemove(String key);

  // ---- http extensions ----
  Future<String> httpPut(String url, String body,
      {Map<String, String>? headers});
  Future<String> httpDelete(String url, {Map<String, String>? headers});
  Future<Map<String, dynamic>> httpFetch(String url,
      {String method = 'GET', Map<String, String>? headers, String? body});

  // ---- utils ----
  Future<void> utilsSetTimeout(int ms);
}

/// JS 引擎抽象（测试可注入 FakeJsEngine）。
abstract class JsEngine {
  JsHostBridge get bridge;
  Future<dynamic> run(String script, String function, List<dynamic> args);
  /// 将路由层传入的附加变量（page/category/keyword 等）注入 JS 的 `context`，
  /// 供脚本自拼 URL 时读取。无此能力的实现（测试桩）可为空操作。
  void injectContext(Map<String, String> vars);
  void dispose();
}

/// 预置给源脚本的 context（JS 侧）。方法经 flutterBridge 回调宿主，Promise 异步返回。
const String _jsContextPrelude = '''
// atob/btoa polyfill：QuickJS 沙箱无浏览器全局，直接调 atob 会 ReferenceError
// 且常被脚本自身 try/catch 吞掉 → 视频解析「静默空」。语义对齐源脚本内嵌版：
// atob 剥离非 base64 字符与尾部 `=` 后宽松解码；btoa 对 >0xFF 码位按 &255 截断
// （浏览器此时抛错，沙箱内宽松更实用）。源脚本自带同名声明会原样覆盖本版，
// 新源可不再内嵌 polyfill（省 ~400 字节/源）。
var __b64a = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
function atob(s){
  s = String(s).replace(/[^A-Za-z0-9+\\/=]/g, '').replace(/=+\$/, '');
  var o = '';
  for (var i = 0; i < s.length; i += 4) {
    var a = __b64a.indexOf(s.charAt(i)), b = __b64a.indexOf(s.charAt(i + 1));
    var c = i + 2 < s.length ? __b64a.indexOf(s.charAt(i + 2)) : -1;
    var d = i + 3 < s.length ? __b64a.indexOf(s.charAt(i + 3)) : -1;
    if (c < 0) c = 0;
    if (d < 0) d = 0;
    o += String.fromCharCode((a << 2) | (b >> 4));
    if (i + 2 < s.length) o += String.fromCharCode(((b & 15) << 4) | (c >> 2));
    if (i + 3 < s.length) o += String.fromCharCode(((c & 3) << 6) | d);
  }
  return o;
}
function btoa(s){
  s = String(s);
  var o = '';
  for (var i = 0; i < s.length; i += 3) {
    var b0 = s.charCodeAt(i) & 255, b1 = s.charCodeAt(i + 1) & 255, b2 = s.charCodeAt(i + 2) & 255;
    var h1 = i + 1 < s.length, h2 = i + 2 < s.length;
    o += __b64a.charAt(b0 >> 2) + __b64a.charAt(((b0 & 3) << 4) | (b1 >> 4));
    o += h1 ? __b64a.charAt(((b1 & 15) << 2) | (b2 >> 6)) : '=';
    o += h2 ? __b64a.charAt(b2 & 63) : '=';
  }
  return o;
}
var __pending = {};
var __execResult = null;
var __execResultResolved = null;
var __pumpMicrotasks = false;
function __resolveBridge(id, value){ if(__pending[id]){ __pending[id].resolve(value); delete __pending[id]; } }
function flutterBridge(method, args){
  var id = 'b_' + Math.random().toString(36).slice(2);
  return new Promise(function(resolve){
    __pending[id] = { resolve: resolve };
    sendMessage('flutterBridge', JSON.stringify({ method: method, args: args, id: id }));
  });
}
var context = {
  http: {
    get: function(url){ return flutterBridge('http.get', [url]); },
    getJson: function(url){ return flutterBridge('http.getJson', [url]); },
    post: function(url, body, headers){ return flutterBridge('http.post', [url, body, headers || null]); },
    postForm: function(url, params, headers){ return flutterBridge('http.postForm', [url, params, headers || null]); },
    put: function(url, body, headers){ return flutterBridge('http.put', [url, body, headers || null]); },
    delete: function(url, headers){ return flutterBridge('http.delete', [url, headers || null]); },
    fetch: function(url, options){ return flutterBridge('http.fetch', [url, options || {}]); }
  },
  dom: {
    query: function(html, sel){ return flutterBridge('dom.query', [html, sel]); },
    queryAll: function(html, sel){ return flutterBridge('dom.queryAll', [html, sel]); },
    queryAttr: function(html, sel, attr){ return flutterBridge('dom.queryAttr', [html, sel, attr]); },
    queryXPath: function(html, xpath){ return flutterBridge('dom.queryXPath', [html, xpath]); },
    queryHtml: function(html, sel){ return flutterBridge('dom.queryHtml', [html, sel]); }
  },
  content: {
    clean: function(html){ return flutterBridge('content.clean', [html]); }
  },
  crypto: {
    md5: function(s){ return flutterBridge('crypto.md5', [s]); },
    base64Encode: function(s){ return flutterBridge('crypto.base64Encode', [s]); },
    base64Decode: function(s){ return flutterBridge('crypto.base64Decode', [s]); },
    rc4: function(data, key){ return flutterBridge('crypto.rc4', [data, key]); },
    sha1: function(s){ return flutterBridge('crypto.sha1', [s]); },
    sha256: function(s){ return flutterBridge('crypto.sha256', [s]); },
    sha512: function(s){ return flutterBridge('crypto.sha512', [s]); },
    hmac: function(key, data, algo){ return flutterBridge('crypto.hmac', [key, data, algo || 'sha256']); },
    hexEncode: function(bytes){ return flutterBridge('crypto.hexEncode', [bytes]); },
    hexDecode: function(hex){ return flutterBridge('crypto.hexDecode', [hex]); },
    aesEcb: function(key, data, encrypt, encoding){ return flutterBridge('crypto.aesEcb', [key, data, encrypt !== false, encoding || 'base64']); },
    aesCbc: function(key, data, iv, encrypt, encoding){ return flutterBridge('crypto.aesCbc', [key, data, iv, encrypt !== false, encoding || 'base64']); },
    aesCfb: function(key, data, iv, encrypt, encoding){ return flutterBridge('crypto.aesCfb', [key, data, iv, encrypt !== false, encoding || 'base64']); },
    aesOfb: function(key, data, iv, encrypt, encoding){ return flutterBridge('crypto.aesOfb', [key, data, iv, encrypt !== false, encoding || 'base64']); },
    aesDecrypt: function(cipher, key, iv){ return flutterBridge('crypto.aesDecrypt', [cipher, key, iv]); }
  },
  image: {
    extractImagesFromHtml: function(html, selector){ return flutterBridge('image.extractImagesFromHtml', [html, selector || null]); },
    extractLazyImagesFromHtml: function(html, selector){ return flutterBridge('image.extractLazyImagesFromHtml', [html, selector || null]); },
    isValidImageUrl: function(url){ return flutterBridge('image.isValidImageUrl', [url]); },
    guessFormat: function(url, bytes){ return flutterBridge('image.guessFormat', [url, bytes || null]); },
    filterImages: function(urls, rules){ return flutterBridge('image.filterImages', [urls, rules || null]); },
    getPageUrls: function(html, config){ return flutterBridge('image.getPageUrls', [html, config || {}]); }
  },
  storage: {
    get: function(key){ return flutterBridge('storage.get', [key]); },
    set: function(key, value){ return flutterBridge('storage.set', [key, value]); },
    remove: function(key){ return flutterBridge('storage.remove', [key]); }
  },
  utils: {
    setTimeout: function(ms){ return flutterBridge('utils.setTimeout', [ms]); }
  },
  url: { resolve: function(rel){ return flutterBridge('url.resolve', [rel]); } },
  log: function(msg){ flutterBridge('log', [msg]); }
};
''';

/// 注入 context.baseUrl（当前激活镜像地址）到 JS 运行时。
String _buildBaseUrlInjection(String baseUrl) {
  final escaped = jsonEncode(baseUrl);
  return 'context.baseUrl = $escaped;';
}

/// Phase3 Strategy C 用的 .then() 注册表达式（提取为常量避免重复构造）。
///
/// 对 __execResult（Promise）附加 .then/.catch，将 JSON 结果写入 __execResultResolved。
/// 配合 _onMessage 中的微任务泵（__pumpMicrotasks 标志），在每次桥接回调后
/// 额外 evaluateAsync 一次空表达式以推动 QuickJS 微任务队列。
const String __execResultThenExpr = '__execResult.then('
    'function(v){ __execResultResolved = JSON.stringify(v); },'
    'function(e){ __execResultResolved = JSON.stringify(null); })';

/// 将分页/分类/关键词等附加变量注入 JS context（供脚本自拼 URL 时使用）。
///
/// 仅注入 `page`/`category`/`keyword` 等合法标识符键；键名含非标识符字符时
/// 替换为下划线，避免构造出非法 JS。值为 JSON 转义字符串，确保任意内容安全。
String _buildContextVarsInjection(Map<String, String> vars) {
  final sb = StringBuffer();
  vars.forEach((k, v) {
    final key = k.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    if (key.isEmpty) return;
    sb.writeln('context.$key = ${jsonEncode(v)};');
  });
  return sb.toString();
}

/// 基于 flutter_js (quickjs) 的真实引擎实现。
class FlutterJsEngine implements JsEngine {
  FlutterJsEngine(this.bridge, {String? baseUrl}) {
    // 运行时按平台分派（鸿蒙用 QuickJS 原生桥，其余平台 flutter_js）。
    // 必须启用 Promise 处理：源脚本（如部分漫画源的 parseList）大量使用
    // `await ctx.http.get(...)`，即异步函数返回 Promise。未启用时 evaluateAsync
    // 不会 await，run() 拿到的只是 `[object Promise]`，导致脚本返回值永远为空
    // → 列表/详情/章节全空。对齐旧版 QuickJsRuntime2(..)..enableHandlePromises()。
    // （FlutterJsRuntime 在构造时内部完成；鸿蒙桥由原生微任务泵承担该语义。）
    _runtime = createJsRuntime();
    _runtime.onMessage('flutterBridge', _onMessage);
    _runtime.evaluate(_jsContextPrelude);
    // 注入 context.baseUrl（当前激活镜像地址）
    if (baseUrl != null && baseUrl.isNotEmpty) {
      _runtime.evaluate(_buildBaseUrlInjection(baseUrl));
    }
  }

  @override
  void injectContext(Map<String, String> vars) {
    if (vars.isEmpty) return;
    _runtime.evaluate(_buildContextVarsInjection(vars));
  }

  @override
  final JsHostBridge bridge;
  late final NexJsRuntime _runtime;

  /// 本实例已完整评估过的脚本（按内容去重）。
  ///
  /// 引擎实例与单次解析同生命周期（ScriptResolver 每次 resolve 新建、finally
  /// dispose）。meta 多跳链的每个 hop 都会以**同一脚本**调用 [run]（入口 +
  /// 各跳 `__processor`，含 webview/暖直连兜底处理器）：若每跳都重放整脚本，
  /// 顶层 `var X='init'` 初始化器会重跑、清掉上一跳写入全局的跨跳状态 →
  /// 多跳链永远拿不到 hop1 数据。同一脚本只在首跳评估一次后，链上经顶层
  /// `var` 共享的状态才符合源编写文档承诺的「同一 JsEngine 内全局持续可见」。
  final Set<String> _loadedScripts = <String>{};

  /// 当前源 ID（生产环境中 bridge 必为 [DartJsHostBridge]，含 source）。
  /// 用于在调试记录本中标记诊断信息归属哪个源。
  String? get _sourceId {
    final b = bridge;
    if (b is DartJsHostBridge) return b.source.id;
    return null;
  }

  void _onMessage(dynamic message) {
    // flutter_js 的 sendMessage 会把消息跨边界投递到 Dart。实际类型取决于
    // flutter_js 版本与平台：可能是 Map（已解析）、String（JSON 编码文本）、
    // 或其他类型（如 int/bool/List）。旧代码用 `message as Map` 强转，
    // String 类型命中时抛 CastError → 被 catchError 静默吞掉 → resolve(null)
    // → 脚本 ctx.http.get 永远返回 null → 空列表。
    //
    // 本方法通过 _decodeBridgeMessage 兼容所有已知类型形态，并在入口处记录
    // 实际收到的类型以便诊断（首次运行后检查 logcat 过滤 [JsContext] 即可）。
    final msgType = message.runtimeType.toString();
    debugPrint('[JsContext] onMessage 收到消息, type=$msgType, value=${message is String ? message.substring(0, message.length.clamp(0, 120)) : message}');
    final m = _decodeBridgeMessage(message);
    if (m == null) {
      debugPrint('[JsContext] ❌ bridge 消息无法解析(type=$msgType), 已忽略。原始值: $message');
      return;
    }
    final method = m['method'] as String? ?? '';
    final args = List<dynamic>.from(m['args'] as List? ?? <dynamic>[]);
    final id = m['id'] as String? ?? '';
    debugPrint('[JsContext] ✅ bridge 解析成功: method=$method, argsCount=${args.length}, id=$id');
    _dispatch(method, args).then((result) {
      _runtime.evaluateAsync(
          '__resolveBridge(${jsonEncode(id)}, ${jsonEncode(result)})');
      // 微任务泵（Phase3 Strategy C）：在桥接回调 resolve 后追加一次空 evaluateAsync，
      // 推动QuickJS微任务队列——使 .then() 链得以传播。仅当 Phase3 开启泵标记时执行，
      // 避免同步脚本的额外开销。（2026-07-19 真机验证：无此泵时 .then() 回调永不触发）
      _pumpMicrotaskQueue();
    }).catchError((Object e, StackTrace st) {
      // 桥接调用抛错（典型：站点反爬 → HttpFetcher 抛
      // VerificationRequiredException / HttpStatusException）时，必须回
      // resolve(null) 而非让 JS 侧 Promise 永久挂起：否则脚本里
      // `await ctx.http.get(...)` 永远不返回 → 10s 超时 → 列表空 / 卡顿，
      // 且 unhandled future error 还会污染隔离边界。解析为 null 后，脚本按
      // 「空内容」优雅降级（如 parseList 收到非 string → 视为 ''），避免崩溃
      // 与无谓超时。脚本自身 try/catch 也能兜住，不会向上抛 SourceResolveException。
      debugPrint('[JsContext] bridge $method 失败，回 resolve(null): $e');
      _runtime.evaluateAsync('__resolveBridge(${jsonEncode(id)}, null)');
      _pumpMicrotaskQueue();
    });
  }

  /// 微任务泵（Phase3 Strategy C 辅助）：当 JS 侧 `__pumpMicrotasks` 标记为 true 时，
  /// 在每次桥接 resolve 后执行一次空 `evaluateAsync`，推动 QuickJS 的微任务队列
  /// 使 `.then()` 回调得以传播。
  ///
  /// 背景（真机日志铁证 2026-07-19T19:31）：
  /// QuickJS/flutter_js 在真机上，`_onMessage` 中 `evaluateAsync('__resolveBridge(...)')`
  /// 虽然解析了 Promise，但后续注册的 `.then()` 链不触发——因为微任务队列未被泵动。
  /// 追加一次空 evaluateAsync 可能在引擎内部触发微任务处理（类似浏览器的
  /// "after a macrotask completes" 行为）。
  void _pumpMicrotaskQueue() {
    // 用 try/catch 包裹：evaluateAsync 在 runtime disposed 后可能抛异常
    // （如 app 切后台/页面销毁时），不应影响正常的 bridge 错误处理路径。
    try {
      _runtime.evaluateAsync(
          'if(__pumpMicrotasks){void 0;}'); // 空表达式，仅推动事件循环
    } on Object {
      /* 泵动失败时静默忽略——不影响功能正确性，只是 .then() 可能延迟到下轮轮询 */
    }
  }

  /// 解析 flutter_js 投递的桥接消息：兼容 Map / JSON String / 其他可序列化类型。
  ///
  /// flutter_js 的 sendMessage 跨边界行为因版本/平台而异：
  /// - 某些版本直接传递已解析的 Map
  /// - 某些版本传递 JSON 编码的 String（旧应用即此形态）
  /// - 极端情况下可能传递 List/int/bool 等其他类型
  ///
  /// 本方法按优先级尝试各种解析策略，确保不遗漏任何有效消息。
  static Map<String, dynamic>? _decodeBridgeMessage(dynamic message) {
    // 1. 已是 Map → 直接使用
    if (message is Map) {
      return message.map((k, v) => MapEntry(k.toString(), v));
    }
    // 2. 是 String → 尝试 JSON 解析
    if (message is String) {
      try {
        final decoded = jsonDecode(message);
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } on Object {
        // 非 JSON 字符串，继续尝试下一种策略
      }
      return null;
    }
    // 3. 其他类型（List/int/bool/自定义对象等）→ 尝试序列化后再解析
    try {
      final encoded = jsonEncode(message);
      final decoded = jsonDecode(encoded);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } on Object {
      // 序列化失败，无法解析
    }
    return null;
  }

  Future<dynamic> _dispatch(String method, List<dynamic> args) {
    switch (method) {
      case 'http.get':
        return bridge.httpGet(args[0] as String);
      case 'http.getJson':
        return bridge.httpGetJson(args[0] as String);
      case 'http.post':
        return bridge.httpPost(
          args[0] as String,
          args[1] as String,
          headers: _headersFromArg(args.length > 2 ? args[2] : null),
        );
      case 'http.postForm':
        return bridge.httpPostForm(
          args[0] as String,
          _stringMapFromArg(args.length > 1 ? args[1] : null),
          headers: _headersFromArg(args.length > 2 ? args[2] : null),
        );
      case 'dom.query':
        return Future<dynamic>.value(
            bridge.query(args[0] as String, args[1] as String));
      case 'dom.queryAll':
        return Future<dynamic>.value(
            bridge.queryAll(args[0] as String, args[1] as String));
      case 'dom.queryAttr':
        return Future<dynamic>.value(bridge.queryAttr(
            args[0] as String, args[1] as String, args[2] as String));
      case 'dom.queryXPath':
        return Future<dynamic>.value(
            bridge.queryXPath(args[0] as String, args[1] as String));
      case 'dom.queryHtml':
        return Future<dynamic>.value(
            bridge.queryHtml(args[0] as String, args[1] as String));
      case 'content.clean':
        return Future<dynamic>.value(bridge.contentClean(args[0] as String));
      case 'crypto.md5':
        return Future<dynamic>.value(bridge.md5(args[0] as String));
      case 'crypto.base64Encode':
        return Future<dynamic>.value(bridge.base64Encode(args[0] as String));
      case 'crypto.base64Decode':
        return Future<dynamic>.value(bridge.base64Decode(args[0] as String));
      case 'crypto.rc4':
        return Future<dynamic>.value(
            bridge.rc4(args[0] as String, args[1] as String));
      case 'crypto.aesDecrypt':
        return Future<dynamic>.value(bridge.aesDecrypt(
            args[0] as String, args[1] as String, args[2] as String));
      case 'url.resolve':
        return Future<dynamic>.value(bridge.resolveUrl(args[0] as String));
      case 'log':
        bridge.log(args[0] as String);
        return Future<dynamic>.value(null);
      // ---- crypto extensions ----
      case 'crypto.sha1':
        return Future<dynamic>.value(bridge.sha1(args[0] as String));
      case 'crypto.sha256':
        return Future<dynamic>.value(bridge.sha256(args[0] as String));
      case 'crypto.sha512':
        return Future<dynamic>.value(bridge.sha512(args[0] as String));
      case 'crypto.hmac':
        return Future<dynamic>.value(bridge.hmac(
          args[0] as String,
          args[1] as String,
          algorithm: (args.length > 2 ? args[2] : null) as String? ?? 'sha256',
        ));
      case 'crypto.hexEncode':
        return Future<dynamic>.value(
            bridge.hexEncode(_byteArrayFromArg(args[0])));
      case 'crypto.hexDecode':
        return Future<dynamic>.value(bridge.hexDecode(args[0] as String));
      case 'crypto.aesEcb':
        return Future<dynamic>.value(bridge.aesEcb(
          args[0] as String,
          args[1] as String,
          encrypt: args.length > 2 ? args[2] as bool : true,
          encoding: (args.length > 3 ? args[3] : null) as String? ?? 'base64',
        ));
      case 'crypto.aesCbc':
        return Future<dynamic>.value(bridge.aesCbc(
          args[0] as String,
          args[1] as String,
          args[2] as String,
          encrypt: args.length > 3 ? args[3] as bool : true,
          encoding: (args.length > 4 ? args[4] : null) as String? ?? 'base64',
        ));
      case 'crypto.aesCfb':
        return Future<dynamic>.value(bridge.aesCfb(
          args[0] as String,
          args[1] as String,
          args[2] as String,
          encrypt: args.length > 3 ? args[3] as bool : true,
          encoding: (args.length > 4 ? args[4] : null) as String? ?? 'base64',
        ));
      case 'crypto.aesOfb':
        return Future<dynamic>.value(bridge.aesOfb(
          args[0] as String,
          args[1] as String,
          args[2] as String,
          encrypt: args.length > 3 ? args[3] as bool : true,
          encoding: (args.length > 4 ? args[4] : null) as String? ?? 'base64',
        ));
      // ---- image ----
      case 'image.extractImagesFromHtml':
        return Future<dynamic>.value(bridge.extractImagesFromHtml(
          args[0] as String,
          selector: _nullableString(args.length > 1 ? args[1] : null),
        ));
      case 'image.extractLazyImagesFromHtml':
        return Future<dynamic>.value(bridge.extractLazyImagesFromHtml(
          args[0] as String,
          selector: _nullableString(args.length > 1 ? args[1] : null),
        ));
      case 'image.isValidImageUrl':
        return Future<dynamic>.value(
            bridge.isValidImageUrl(args[0] as String));
      case 'image.guessFormat':
        return Future<dynamic>.value(bridge.guessFormat(
          args[0] as String,
          bytes: args.length > 1 && args[1] != null
              ? _byteArrayFromArg(args[1])
              : null,
        ));
      case 'image.filterImages':
        return Future<dynamic>.value(bridge.filterImages(
          _stringListFromArg(args[0]),
          rules: _rulesFromArg(args.length > 1 ? args[1] : null),
        ));
      case 'image.getPageUrls':
        return Future<dynamic>.value(bridge.getPageUrls(
          args[0] as String,
          _configFromArg(args.length > 1 ? args[1] : null),
        ));
      // ---- storage ----
      case 'storage.get':
        return Future<dynamic>.value(bridge.storageGet(args[0] as String));
      case 'storage.set':
        bridge.storageSet(args[0] as String, args[1] as String);
        return Future<dynamic>.value(null);
      case 'storage.remove':
        bridge.storageRemove(args[0] as String);
        return Future<dynamic>.value(null);
      // ---- http extensions ----
      case 'http.put':
        return bridge.httpPut(
          args[0] as String,
          args[1] as String,
          headers: _headersFromArg(args.length > 2 ? args[2] : null),
        );
      case 'http.delete':
        return bridge.httpDelete(
          args[0] as String,
          headers: _headersFromArg(args.length > 1 ? args[1] : null),
        );
      case 'http.fetch':
        final opts = (args.length > 1 ? args[1] : null) as Map?;
        return bridge.httpFetch(
          args[0] as String,
          method: opts != null && opts['method'] != null
              ? opts['method'].toString().toUpperCase()
              : 'GET',
          headers: _headersFromArg(opts?['headers']),
          body: opts?['body']?.toString(),
        );
      // ---- utils ----
      case 'utils.setTimeout':
        return bridge.utilsSetTimeout((args[0] as num).toInt());
      default:
        return Future<dynamic>.value(null);
    }
  }

  // ---- dispatch arg helpers ----

  static List<int> _byteArrayFromArg(dynamic v) {
    if (v is List) {
      return v.map((e) => (e as num).toInt()).toList();
    }
    return const <int>[];
  }

  static String? _nullableString(dynamic v) => v?.toString();

  static Map<String, String>? _headersFromArg(dynamic v) {
    if (v == null) return null;
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), val.toString()));
    }
    return null;
  }

  static Map<String, String> _stringMapFromArg(dynamic v) {
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), val.toString()));
    }
    if (v is String) {
      try {
        final decoded = jsonDecode(v);
        if (decoded is Map) {
          return decoded.map((k, val) => MapEntry(k.toString(), val.toString()));
        }
      } on Object {
        // fall through
      }
    }
    return const <String, String>{};
  }

  static List<String> _stringListFromArg(dynamic v) {
    if (v is List) {
      return v.map((e) => e.toString()).toList();
    }
    if (v is String) {
      try {
        final decoded = jsonDecode(v);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList();
        }
      } on Object {
        // fall through
      }
    }
    return const <String>[];
  }

  static Map<String, dynamic>? _rulesFromArg(dynamic v) {
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), val));
    }
    if (v is String) {
      try {
        final decoded = jsonDecode(v);
        if (decoded is Map) {
          return decoded.map((k, val) => MapEntry(k.toString(), val));
        }
      } on Object {
        // fall through
      }
    }
    return null;
  }

  static Map<String, dynamic> _configFromArg(dynamic v) {
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), val));
    }
    if (v is String) {
      try {
        final decoded = jsonDecode(v);
        if (decoded is Map) {
          return decoded.map((k, val) => MapEntry(k.toString(), val));
        }
      } on Object {
        // fall through
      }
    }
    return const <String, dynamic>{};
  }

  @override
  Future<dynamic> run(String script, String function, List<dynamic> args) async {
    debugPrint('[JsContext] run() 开始: function=$function, argsCount=${args.length}, scriptLength=${script.length}');
    if (_loadedScripts.add(script)) {
      final evalRes = await _runtime.evaluateAsync(script);
      if (evalRes.isError) {
        // 语法错误等评估失败不缓存：后续 run 仍会重试评估（对齐旧行为）。
        _loadedScripts.remove(script);
      }
    }
    // 单参时裸传 args.first（如 HTML 字符串），避免脚本收到 ["<html>"] 这种
    // 数组包装——golden 脚本多声明 `function parseX(raw, context)`，期望 raw 为字符串。
    // 多参时逐参内联（各自 jsonEncode 后逗号连接）：meta 单条预取处理器按协议收
    // (响应体, 响应头) 两个独立参数。历史实现把多参整体 jsonEncode 成一个数组
    // 字面量作首参——处理器拿到的永远是包装数组，响应头取不到，且按
    // 「入参=预取结果」写的处理器顶层取不到 data 键而恒空产出。
    // 兼容：针对旧打包形态写过的源应在处理器开头做 Array.isArray 形态归一，
    // 两种引擎形态都能跑。统一追加 context 作为末参（沙箱能力入口）。
    final arg = args.length == 1
        ? jsonEncode(args.first)
        : args.map<String>(jsonEncode).join(',');
    final sid = _sourceId;

    // ══════════════════════════════════════════════════════════
    // 两阶段变量存储策略（v3 · 彻底绕开 evaluateAsync 无法 await Promise 的 bug）
    // ══════════════════════════════════════════════════════════
    //
    // 问题背景（真机日志铁证，2026-07-19T19:04）:
    // flutter_js 的 evaluateAsync 在真机上**无法正确 await 任何顶层 Promise**：
    // - 旧写法 JSON.stringify(asyncFn(...)) → stringResult = "{}"（Promise 被 stringify 吞掉）
    // - v2 写法 (async()=>{await fn(...)})() → stringResult = "Instance of 'Future<dynamic>'"
    // （IIFE 把同步函数也变成 Promise → 同步函数也被搞坏了）
    // - 两者都导致列表/章节全空，即使脚本实际执行正确（实测 found=18/54）
    //
    // 根因：evaluateAsync 内部的消息泵/事件循环在真机环境下无法驱动 JS Promise 解析，
    // 返回的是内部原始表示而非 resolved 值。enableHandlePromises + handlePromise
    // 是仅有的可用异步通道，但它们需要"一个未被消费的 Promise 引用"才能工作。
    //
    // 本策略分三阶段：
    // Phase 1: 执行函数，把返回值（或 Promise）存入全局变量 __execResult
    // → 同步函数：__execResult = 实际值（数组/对象/string/null）
    // → 异步函数：__execResult = Promise（未 resolve）
    // Phase 2: 检测 __execResult 是否为 Promise
    // → 非 Promise → 直接 JSON.stringify → 得到严格 JSON 字符串（完成）
    // → 是 Promise → 返回哨兵 "__ASYNC__"，进入 Phase 3
    // Phase 3: 对 __execResult（Promise）附加 .then/.catch，
    // 将 JSON 化结果存入 __execResultResolved；
    // .then() 本身返回新 Promise → evaluateAsync 拿到它 → handlePromise 等待
    // 落地后读 __execResultResolved → 最终 JSON 字符串
    //
    // 关键优势：
    // - 同步函数完全不碰 Promise / handlePromise（恢复 v1 的正常路径）
    // - 异步函数通过 .then() + handlePromise 专门通道获取结果
    // - 不修改任何源 JSON（纯引擎层修复）

    // ── Phase 1: 执行函数并存储原始返回值 ──
    final phase1 = '(function(){'
        ' try { __execResult = $function($arg, context); }'
        ' catch(e) { __execResult = {__error: String(e)}; }'
        '})()';
    debugPrint('[JsContext] Phase1: 执行 $function 并存储结果');
    ParseDiagnostics.log(sid ?? '', '脚本执行(Phase1): $function()');
    await _runtime.evaluateAsync(phase1);

    // ── Phase 2: 提取 JSON 或检测异步 ──
    //
    // 关键修正（2026-07-19，真机日志铁证）：flutter_js 的 `stringResult` 对 JS 返回的
    // **字符串原值** 不做二次 JSON 编码。即脚本 `return "__ASYNC__"` → `stringResult`
    // 实际为 "__ASYNC__"（**不带引号**）。旧代码误把判定写成 `'"__ASYNC__"'`（带引号），
    // 导致异步分支 `phase2Raw == '"__ASYNC__"'` 永远为 false → Phase3 永不进入 →
    // 详情/章节等异步脚本返回值被当成字面量 "__ASYNC__" → jsonDecode 失败 → 空 List[0]。
    // 现改为同时兼容带/不带引号两种写法，并新增轮询兜底，保证异步通道稳定落地。
    final phase2 = '(function(){'
        ' var r = __execResult;'
        ' if (r && r.__error) return "__ERR__";'
        ' if (r && typeof r.then === "function") return "__ASYNC__";'
        ' if (typeof r === "undefined") r = null;'
        ' return JSON.stringify(r);'
        '})()';
    var res = await _runtime.evaluateAsync(phase2);
    final phase2Raw = res.stringResult;
    debugPrint('[JsContext] Phase2 结果: "${_trunc(phase2Raw)}"');

    final bool isAsync = phase2Raw == '__ASYNC__' ||
        phase2Raw == '"__ASYNC__"' ||
        (res.isPromise ?? false);
    final bool isErr = phase2Raw == '__ERR__' || phase2Raw == '"__ERR__"';

    String resultStr = '';
    if (isErr) {
      debugPrint('[JsContext] Phase2: 脚本执行抛错，回退 null');
      ParseDiagnostics.log(sid ?? '', '⚠️ 脚本执行异常(Phase1 catch)');
      return null;
    } else if (isAsync) {
      // ══════════════════════════════════════════════════════════
      // Phase 3: 多策略异步解析（v4 · 真机验证迭代）
      // ══════════════════════════════════════════════════════════
      //
      // 已确认事实（2026-07-19T19:31 日志铁证）：
      // 1. Phase2 正确检测到 "__ASYNC__"（哨兵修复生效 ✅）
      // 2. Phase3 进入后，evaluateAsync('__execResult.then(...)') 的
      // isPromise=false → handlePromise 无法使用
      // 3. 轮询 __execResultResolved 8 秒全空 → .then() 回调从未触发
      // 4. 根因：QuickJS/flutter_js 的微任务队列不在跨 evaluateAsync
      // 调用间自动传播；_onMessage 中的 __resolveBridge 虽然执行了
      // （parseChapters 的 http.getJson 消息已发出），但 .then() 链
      // 不在后续 evaluateAsync 中被泵动
      //
      // 本版本采用三策略逐级降级：
      // Strategy A: 直接对 __execResult 引用尝试 handlePromise
      // （变量引用可能携带 Promise 标记）
      // Strategy B: 用 async IIFE 重跑函数 + handlePromise
      // （已确认是 async 函数，不会误伤同步路径）
      // Strategy C: .then() 写全局 + _onMessage 微任务泵 + 轮询
      // （最后手段，依赖泵动机制）
      debugPrint('[JsContext] Phase3: 检测到异步函数，启动多策略解析');
      ParseDiagnostics.log(sid ?? '', '⚠️ 异步脚本(Promise), 进入Phase3');

      bool resolved = false;

      // ── Strategy A: 直接 handlePromise on __execResult 变量引用 ──
      // 原理：evaluateAsync('__execResult') 直接读取存储 Promise 的全局变量，
      // 返回的 JsEvalResult 可能标记 isPromise=true（不同于 IIFE 包装后的表达式）。
      // 若成功，handlePromise 会等待 Promise settle 并返回 resolved value 的 stringResult。
      if (!resolved) {
        try {
          final refRes =
              await _runtime.evaluateAsync('__execResult');
          final refIsPromise = refRes.isPromise ?? false;
          debugPrint(
              '[JsContext] Phase3-A: __execResult引用, isPromise=$refIsPromise');
          if (refIsPromise) {
            final done = await _runtime.handlePromise(refRes,
                timeout: const Duration(seconds: 15));
            resultStr = done.stringResult;
            debugPrint(
                '[JsContext] Phase3-A ✅: handlePromise成功, "${_trunc(resultStr)}"');
            ParseDiagnostics.log(
                sid ?? '', '✅ Phase3-A handlePromise成功');
            resolved = true;
          }
        } on Object catch (e) {
          debugPrint('[JsContext] Phase3-A 失败: $e');
        }
      }

      // ── Strategy B: async IIFE 重跑 + handlePromise ──
      // 原理：既然 Phase2 已确认此函数返回 Promise（async function），
      // 可以安全地用 async IIFE 包裹重跑。IIFE 内部 `await` 原函数调用，
      // 然后 JSON.stringify 结果。顶层表达式是 async IIFE 调用→ 返回 Promise →
      // evaluateAsync 有可能将其标记为 isPromise=true（因为这是顶层 async 表达式
      // 而非 .then() 链式调用）。
      // 代价：函数会执行两次（Phase1 已执行过一次）。对于 parseDetail（纯 HTML 解析）
      // 无副作用；对于 parseChapters（发 HTTP API）会产生重复请求——可接受作为 fallback。
      if (!resolved) {
        debugPrint('[JsContext] Phase3-B: async IIFE 重试');
        try {
          final iife = '(async function(){'
              ' try { return JSON.stringify(await $function($arg, context)); }'
              ' catch(e) { return JSON.stringify(null); }'
              '})()';
          final iifeRes = await _runtime.evaluateAsync(iife);
          final iifeIsPromise = iifeRes.isPromise ?? false;
          // flutter_js 的 FFI QuickJS 运行时（quickjs_runtime2）对挂起 Promise
          // 的返回形态：_jsToDart 把 JS Promise 包成 pending Dart Future
          // （wrapper.dart），并把该 Future 的 toString() 写进 stringResult
          // （即 "Instance of 'Future<dynamic>'"），isPromise 恒为 false——
          // 仅凭 isPromise 做闸门会让 handlePromise 永远不可达。handlePromise
          // 对该形态本就有专门分支：await rawResult + 20ms executePendingJob
          // 持续泵动 QuickJS job 队列，settle 后返回值（IIFE 已 JSON.stringify）
          // 即为合法 JSON 字符串。
          final iifeRaw = iifeRes.stringResult ?? '';
          final iifeIsDartFuture = iifeRaw.contains("Instance of 'Future");
          debugPrint(
              '[JsContext] Phase3-B: IIFE结果, isPromise=$iifeIsPromise, dartFuture=$iifeIsDartFuture');
          if (iifeIsPromise || iifeIsDartFuture) {
            final done = await _runtime.handlePromise(iifeRes,
                timeout: const Duration(seconds: 15));
            resultStr = done.stringResult;
            debugPrint(
                '[JsContext] Phase3-B ✅: IIFE+handlePromise成功, "${_trunc(resultStr)}"');
            ParseDiagnostics.log(
                sid ?? '', '✅ Phase3-B IIFE+handlePromise成功');
            resolved = true;
          } else {
            // IIFE 未标记为 Promise 但可能有值（引擎直接解析了？）
            final raw = iifeRaw;
            if (raw.isNotEmpty &&
                raw != 'undefined' &&
                !raw.contains("Instance of 'Future") &&
                !raw.startsWith('[object ')) {
              resultStr = raw;
              debugPrint(
                  '[JsContext] Phase3-B ⚠️: IIFE非Promise但有原始值, "${_trunc(resultStr)}"');
              ParseDiagnostics.log(
                  sid ?? '', '⚠️ Phase3-B IIFE非Promise但取到原始值');
              resolved = true;
            }
          }
        } on Object catch (e) {
          debugPrint('[JsContext] Phase3-B 失败: $e');
        }
      }

      // ── Strategy C: .then() 写全局 + 微任务泵增强轮询 ──
      // 原理：注册 .then() 回调将 JSON 结果写入 __execResultResolved；
      // 同时修改 _onMessage 中 __resolveBridge 后追加空 evaluateAsync 泵动微任务；
      // 最后轮询读取 __execResultResolved（最多 ~12s）。
      // 此策略依赖 C（微任务泵）才能工作，否则与 v3 行为相同（轮询全空）。
      if (!resolved) {
        debugPrint('[JsContext] Phase3-C: .then()+泵动轮询兜底');
        ParseDiagnostics.log(sid ?? '', '⚠️ 进入Phase3-C 兜底');
        // 注册回调
        await _runtime.evaluateAsync(__execResultThenExpr);
        // 启用微任务泵（见 _onMessage 中的 __pumpMicrotasks 标记）
        await _runtime.evaluateAsync('__pumpMicrotasks = true;');
        // 轮询（120次 × 100ms ≈ 12s，比 v3 的 8s 更宽容）
        String? polled;
        for (int i = 0; i < 120; i++) {
          await Future.delayed(const Duration(milliseconds: 100));
          try {
            final rr = (await _runtime
                    .evaluateAsync('__execResultResolved'))
                .stringResult;
            if (rr == 'null') break; // 脚本显式返回 null
            if (rr.isNotEmpty && rr != 'undefined') {
              polled = rr;
              break;
            }
          } on Object {
            /* 忽略读取异常，继续 */
          }
        }
        // 关闭泵（避免后续同步脚本不必要的开销）
        await _runtime.evaluateAsync('__pumpMicrotasks = false;');
        if (polled != null) {
          resultStr = polled;
          debugPrint(
              '[JsContext] Phase3-C ✅: 轮询拿到结果, "${_trunc(resultStr)}"');
          ParseDiagnostics.log(sid ?? '', '✅ Phase3-C 轮询成功');
          resolved = true;
        } else {
          debugPrint('[JsContext] Phase3-C ❌: 轮询仍空（微任务泵可能无效）');
          ParseDiagnostics.log(sid ?? '', '❌ Phase3-C 全策略失败');
        }
      }

      if (!resolved) return null;
    } else {
      // 同步路径：Phase2 已返回严格 JSON 字符串
      resultStr = res.stringResult;
    }

    // ── 最终结果处理 ──
    if (resultStr.isEmpty || resultStr == 'undefined' || resultStr == 'null') {
      debugPrint('[JsContext] run() ⚠️ 返回空结果');
      ParseDiagnostics.log(sid ?? '', '⚠️ 脚本返回空结果');
      return null;
    }

    final preview = resultStr.length > 200
        ? '${resultStr.substring(0, 200)}...(共${resultStr.length}字符)'
        : resultStr;
    debugPrint('[JsContext] run() ✅ 返回结果: $preview');
    try {
      final decoded = jsonDecode(resultStr);
      if (decoded is List) {
        debugPrint('[JsContext] run() 结果为List, 长度=${(decoded as List).length}');
        ParseDiagnostics.log(sid ?? '', '✅ 脚本返回List, 长度=${(decoded as List).length}');
      } else {
        ParseDiagnostics.log(sid ?? '', '✅ 脚本返回: $preview');
      }
      return decoded;
    } on Object {
      ParseDiagnostics.log(
          sid ?? '',
          '⚠️ 返回非JSON: ${resultStr.length > 100 ? resultStr.substring(0, 100) : resultStr}');
      return resultStr;
    }
  }

  /// 截断长字符串用于调试日志（避免刷屏）。
  static String _trunc(String s) =>
      s.length > 120 ? '${s.substring(0, 120)}…(共${s.length}字符)' : s;

  @override
  void dispose() => _runtime.dispose();
}

/// Dart 侧宿主能力实现，绑定到具体源（注入当前激活镜像 / 反盗链 Referer）。
class DartJsHostBridge implements JsHostBridge {
  DartJsHostBridge(this.source);

  final PluginConfig source;

  String get _referer =>
      source.antiHotlinking.referer ?? ConfigLoader.instance.getActiveMirror(source);

  /// 源级网络覆盖档案：每次拓取显式传给 HttpFetcher，使该源的
  /// JS 能力调用走专属代理/DNS 档案（无 Zone）。
  EffectiveNetworkProfile get _net =>
      NetworkConfigService.instance.effectiveFor(source);

  /// 反盗链指定 UA：部分源通过
  /// `antiHotlinking.userAgent` 要求携带特定 UA 才能绕开防盗链。
  /// 注入到请求头后会覆盖 HttpFetcher 默认指纹 UA（extra 在 _mergeHeaders
  /// 末尾展开，优先级最高）。
  Map<String, String>? get _antiHotlinkHeaders {
    final ua = source.antiHotlinking.userAgent;
    if (ua == null || ua.isEmpty) return null;
    return <String, String>{'User-Agent': ua};
  }

  Map<String, String>? _withUa(Map<String, String>? headers) {
    final ah = _antiHotlinkHeaders;
    if (ah == null) return headers;
    return <String, String>{...?headers, ...ah};
  }

  @override
  Future<String> httpGet(String url, {Map<String, String>? headers}) =>
      HttpFetcher.instance.getHtml(url,
          referer: _referer, headers: _withUa(headers), net: _net);

  @override
  Future<dynamic> httpGetJson(String url, {Map<String, String>? headers}) =>
      HttpFetcher.instance.getJson(url,
          referer: _referer, headers: _withUa(headers), net: _net);

  @override
  Future<String> httpPost(String url, String body,
          {Map<String, String>? headers}) =>
      HttpFetcher.instance.post(url,
          data: body,
          referer: _referer,
          headers: _withUa(headers),
          net: _net);

  @override
  String? queryHtml(String html, String selector) =>
      HtmlUtils.queryHtml(html, selector);

  @override
  String contentClean(String html) => HtmlUtils.clean(html);

  @override
  Future<String> httpPostForm(String url, Map<String, String> params,
          {Map<String, String>? headers}) =>
      HttpFetcher.instance.postForm(url,
          data: params,
          referer: _referer,
          headers: _withUa(headers),
          net: _net);

  @override
  String? query(String html, String selector) => HtmlUtils.query(html, selector);

  @override
  List<String> queryAll(String html, String selector) =>
      HtmlUtils.queryAll(html, selector);

  @override
  String? queryAttr(String html, String selector, String attr) =>
      HtmlUtils.queryAttr(html, selector, attr);

  @override
  String? queryXPath(String html, String xpath) =>
      HtmlUtils.query(html, xpath); // HtmlUtils 已支持 `//` 前缀

  @override
  String md5(String s) => CryptoUtils.md5Hex(s);

  @override
  String base64Encode(String s) => CryptoUtils.base64EncodeString(s);

  @override
  String base64Decode(String s) => CryptoUtils.base64DecodeString(s);

  @override
  String rc4(String data, String key) => CryptoUtils.rc4(data, key);

  @override
  String aesDecrypt(String cipherBase64, String key, String iv) =>
      aesCbc(key, cipherBase64, iv, encrypt: false, encoding: 'base64');

  // ---- crypto extensions ----

  @override
  String sha1(String s) => CryptoUtils.sha1Hex(s);

  @override
  String sha256(String s) => CryptoUtils.sha256Hex(s);

  @override
  String sha512(String s) => CryptoUtils.sha512Hex(s);

  @override
  String hmac(String key, String data, {String algorithm = 'sha256'}) =>
      CryptoUtils.hmacHex(key, data, algorithm: algorithm);

  @override
  String hexEncode(List<int> bytes) => CryptoUtils.hexEncode(bytes);

  @override
  List<int> hexDecode(String hex) => CryptoUtils.hexDecode(hex);

  @override
  String aesEcb(String key, String data,
      {bool encrypt = true, String encoding = 'base64'}) {
    final keyBytes = _decodeBytes(key, encoding);
    final dataBytes = _decodeBytes(data, encoding);
    if (encrypt) {
      final cipher = CryptoUtils.aesEcbEncrypt(dataBytes, key: keyBytes);
      return _encodeBytes(cipher, encoding);
    }
    final plain = CryptoUtils.aesEcbDecrypt(dataBytes, key: keyBytes);
    return utf8.decode(plain);
  }

  @override
  String aesCbc(String key, String data, String iv,
      {bool encrypt = true, String encoding = 'base64'}) {
    final keyBytes = _decodeBytes(key, encoding);
    final ivBytes = _decodeBytes(iv, encoding);
    final dataBytes = _decodeBytes(data, encoding);
    if (encrypt) {
      final cipher =
          CryptoUtils.aesCbcEncrypt(dataBytes, key: keyBytes, iv: ivBytes);
      return _encodeBytes(cipher, encoding);
    }
    return CryptoUtils.aesCbcDecrypt(dataBytes, key: keyBytes, iv: ivBytes);
  }

  @override
  String aesCfb(String key, String data, String iv,
      {bool encrypt = true, String encoding = 'base64'}) {
    final keyBytes = _decodeBytes(key, encoding);
    final ivBytes = _decodeBytes(iv, encoding);
    final dataBytes = _decodeBytes(data, encoding);
    if (encrypt) {
      final cipher =
          CryptoUtils.aesCfbEncrypt(dataBytes, key: keyBytes, iv: ivBytes);
      return _encodeBytes(cipher, encoding);
    }
    final plain = CryptoUtils.aesCfbDecrypt(dataBytes, key: keyBytes, iv: ivBytes);
    return utf8.decode(plain);
  }

  @override
  String aesOfb(String key, String data, String iv,
      {bool encrypt = true, String encoding = 'base64'}) {
    final keyBytes = _decodeBytes(key, encoding);
    final ivBytes = _decodeBytes(iv, encoding);
    final dataBytes = _decodeBytes(data, encoding);
    final out =
        CryptoUtils.aesOfbProcess(dataBytes, key: keyBytes, iv: ivBytes);
    if (encrypt) {
      return _encodeBytes(out, encoding);
    }
    return utf8.decode(out);
  }

  /// 按 [encoding]（'base64' 或 'hex'）解码字符串为字节列表。
  List<int> _decodeBytes(String input, String encoding) {
    if (encoding == 'hex') return CryptoUtils.hexDecode(input);
    return CryptoUtils.base64DecodeBytes(input);
  }

  /// 按 [encoding]（'base64' 或 'hex'）编码字节列表为字符串。
  String _encodeBytes(List<int> bytes, String encoding) {
    if (encoding == 'hex') return CryptoUtils.hexEncode(bytes);
    return CryptoUtils.base64EncodeBytes(bytes);
  }

  // ---- image ----

  @override
  List<String> extractImagesFromHtml(String html, {String? selector}) =>
      ImageExtractor.extractLazyImagesFromHtml(html, selector: selector);

  @override
  List<String> extractLazyImagesFromHtml(String html, {String? selector}) =>
      ImageExtractor.extractLazyImagesFromHtml(html, selector: selector);

  @override
  bool isValidImageUrl(String url) => ImageExtractor.isValidImageUrl(url);

  @override
  String? guessFormat(String url, {List<int>? bytes}) =>
      ImageExtractor.guessFormat(url, bytes: bytes);

  @override
  List<String> filterImages(List<String> urls,
      {Map<String, dynamic>? rules}) {
    if (rules == null) return ImageExtractor.filterImages(urls);
    final excludeKeywords = (rules['excludeKeywords'] as List?)
        ?.map((e) => e.toString())
        .toList();
    final allowedFormats = (rules['allowedFormats'] as List?)
        ?.map((e) => e.toString())
        .toList();
    final deduplicate = rules['deduplicate'] as bool?;
    const defaults = ImageFilterRules();
    return ImageExtractor.filterImages(
      urls,
      rules: ImageFilterRules(
        excludeKeywords:
            excludeKeywords ?? defaults.excludeKeywords,
        allowedFormats:
            allowedFormats ?? defaults.allowedFormats,
        deduplicate: deduplicate ?? defaults.deduplicate,
      ),
    );
  }

  @override
  List<String> getPageUrls(String html, Map<String, dynamic> config) {
    final base = ConfigLoader.instance.getActiveMirror(source);
    return ImageExtractor.getPageUrls(html, config, baseUrl: base);
  }

  // ---- storage (namespaced by sourceId, persists across calls) ----

  static final Map<String, Map<String, String>> _storage = {};

  Map<String, String> get _store =>
      _storage.putIfAbsent(source.id, () => <String, String>{});

  @override
  String? storageGet(String key) => _store[key];

  @override
  void storageSet(String key, String value) {
    _store[key] = value;
  }

  @override
  void storageRemove(String key) {
    _store.remove(key);
  }

  // ---- http extensions ----

  @override
  Future<String> httpPut(String url, String body,
          {Map<String, String>? headers}) =>
      HttpFetcher.instance.put(url,
          data: <String, dynamic>{'body': body},
          referer: _referer,
          headers: _withUa(headers),
          net: _net);

  @override
  Future<String> httpDelete(String url, {Map<String, String>? headers}) =>
      HttpFetcher.instance.delete(url,
          referer: _referer, headers: _withUa(headers), net: _net);

  @override
  Future<Map<String, dynamic>> httpFetch(String url,
          {String method = 'GET',
          Map<String, String>? headers,
          String? body}) =>
      HttpFetcher.instance.fetch(url,
          method: method,
          headers: _withUa(headers),
          body: body,
          referer: _referer,
          net: _net);

  // ---- utils ----

  @override
  Future<void> utilsSetTimeout(int ms) {
    // Cap at 10s to respect ScriptResolver's total timeout constraint.
    final capped = ms > 10000 ? 10000 : ms;
    return Future<void>.delayed(Duration(milliseconds: capped));
  }

  @override
  String resolveUrl(String relative) {
    if (relative.startsWith('http://') || relative.startsWith('https://')) {
      return relative;
    }
    final base = ConfigLoader.instance.getActiveMirror(source);
    return Uri.parse(base).resolve(relative).toString();
  }

  @override
  void log(String msg) => debugPrint('[js:${source.id}] $msg');
}

typedef JsEngineFactory = JsEngine Function(PluginConfig source);

/// 默认引擎工厂：生产环境使用 quickjs。
/// 注入 context.baseUrl 为当前激活镜像地址。
JsEngine defaultEngineFactory(PluginConfig source) =>
    FlutterJsEngine(DartJsHostBridge(source),
        baseUrl: ConfigLoader.instance.getActiveMirror(source));
