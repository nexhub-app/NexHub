/// JS 沙箱引擎：执行书源内嵌的 `@js` / `<js>` 脚本。
///
/// 运行时按平台分派（lib/core/js/js_runtime_factory.dart）：安卓/桌面走
/// flutter_js（QuickJS/JavaScriptCore），鸿蒙走随 HAP 打包的 QuickJS 原生桥。
/// 全局 `java` 对象由 java_extensions.dart 预置（P0 第一梯队：纯计算族），
/// toast/log/put 经排空协议回传宿主。
library;

import 'dart:convert';

import '../../../core/js/js_runtime.dart';
import '../../../core/js/js_runtime_factory.dart';

import '../../../core/novel/novel_chinese_converter.dart';
import '../../../core/utils/app_log.dart';
import 'java_extensions.dart';
import 'source_context.dart';

class JsEngine {
  NexJsRuntime? _runtime;

  /// 是否已注入全局预置脚本（繁简转换 t2s()/s2t() + java.* 第一梯队）。
  bool _preludeInjected = false;

  /// 上一轮 eval 中 `java.put` 写入的变量（takeJavaVars 取走并清空）。
  Map<String, String> _lastJavaVars = const {};

  /// 已预执行的 jsLib 内容（同引擎同内容去重）。
  String? _jsLibApplied;

  /// 已推送进 JS 全局的重放缓存键（增量同步用，避免整表重灌）。
  final Set<String> _syncedAjaxKeys = <String>{};
  final Set<String> _syncedAjaxBytesKeys = <String>{};
  final Set<String> _syncedAjaxMetaKeys = <String>{};
  final Set<String> _syncedWebviewKeys = <String>{};

  // ── 按源复用 ──
  //
  // 书源解析是「一源多阶段、一阶段多规则」的密集调用：搜索列表逐条目、
  // 目录逐页、正文逐章都会求值规则。旧实现每个 AnalyzeRule 新建一个
  // JsEngine → 重建 QuickJS 运行时 + 重跑三段预置脚本（~40KB），且从不
  // dispose（原生句柄泄漏）。这里按 sourceId 池化，上限 [_poolLimit]，
  // 超限淘汰最早创建的实例（先摘出池再 dispose，避免自引用死循环）。
  static const int _poolLimit = 8;
  static final Map<String, JsEngine> _pool = <String, JsEngine>{};

  /// 取（或创建）某书源专属引擎；[sourceId] 为空时返回独立实例（不池化）。
  static JsEngine forSource(String? sourceId) {
    if (sourceId == null || sourceId.isEmpty) return JsEngine();
    final exist = _pool[sourceId];
    if (exist != null) return exist;
    if (_pool.length >= _poolLimit) {
      final oldest = _pool.keys.first;
      _pool.remove(oldest)?.dispose();
    }
    final engine = JsEngine();
    _pool[sourceId] = engine;
    return engine;
  }

  /// 清空某源 JS 侧重放缓存；该源还没有池化引擎时为空操作（不新建）。
  static void resetReplayCachesFor(String sourceId) {
    _pool[sourceId]?.resetReplayCaches();
  }

  /// 丢弃某源引擎（源删除/重载时调用）。
  static void evict(String sourceId) {
    _pool.remove(sourceId)?.dispose();
  }

  /// 测试隔离：释放全部池化引擎。
  static void resetPoolForTest() {
    final engines = List<JsEngine>.from(_pool.values);
    _pool.clear();
    for (final engine in engines) {
      engine.dispose();
    }
  }

  NexJsRuntime get runtime {
    if (_runtime == null) {
      _runtime = createJsRuntime();
      _injectPrelude();
    }
    return _runtime!;
  }

  /// 注入全局预置脚本：繁简转换（`t2s/s2t`）+ java.* 第一梯队桥
  /// （[javaExtensionsJsPrelude]，定义全局 `java` 对象）。
  /// QuickJS 同一运行时的全局声明跨 eval 持久，注入一次即可。
  void _injectPrelude() {
    if (_preludeInjected) return;
    _preludeInjected = true;
    try {
      final result = _runtime!.evaluate(chineseConverterJsPrelude);
      if (result.isError) {
        AppLog.instance.w(
            '[书源JS] 繁简转换预置脚本注入失败: ${result.stringResult}');
      }
    } catch (e) {
      AppLog.instance.w('[书源JS] 繁简转换预置脚本注入异常: $e');
    }
    try {
      final result = _runtime!.evaluate(javaExtensionsJsPrelude);
      if (result.isError) {
        AppLog.instance.w('[书源JS] java.* 桥预置脚本注入失败: ${result.stringResult}');
      }
    } catch (e) {
      AppLog.instance.w('[书源JS] java.* 桥预置脚本注入异常: $e');
    }
    try {
      final result = _runtime!.evaluate(sourceContextJsPrelude);
      if (result.isError) {
        AppLog.instance.w(
            '[书源JS] 注入对象预置脚本注入失败: ${result.stringResult}');
      }
    } catch (e) {
      AppLog.instance.w('[书源JS] 注入对象预置脚本注入异常: $e');
    }
  }

  /// 取走上一轮 eval 中脚本经 `java.put` 写入的变量（取后清空）。
  /// 仅变量表持有方（AnalyzeRule）需要调用；未调用即丢弃。
  Map<String, String> takeJavaVars() {
    final taken = _lastJavaVars;
    _lastJavaVars = const {};
    return taken;
  }

  /// 把宿主已抓取、JS 侧还没有的 ajax 响应增量推给全局 `__ajaxCache`。
  ///
  /// 只推新增键：一轮 settle 通常只填 1–N 个请求，避免把整表重新序列化
  /// 进 JS 源码（旧实现把 ajaxCache 放进每轮 ctx 种子，长目录 O(n²)）。
  void _pushAjaxDeltas(Map<String, String> cache) {
    _pushDeltas('__ajaxCache', cache, _syncedAjaxKeys);
  }

  /// `bodyAsBytes` 的二进制重放（base64）同样增量推送。
  void _pushAjaxBytesDeltas(Map<String, String> cache) {
    _pushDeltas('__ajaxBytesCache', cache, _syncedAjaxBytesKeys);
  }

  /// 响应元数据（状态码/响应头/最终 URL）同样增量推送。
  void _pushAjaxMetaDeltas(Map<String, String> cache) {
    _pushDeltas('__ajaxMetaCache', cache, _syncedAjaxMetaKeys);
  }

  /// `java.webView` 的重放结果（整页 HTML）同样增量推送。
  void _pushWebviewDeltas(Map<String, String> cache) {
    _pushDeltas('__webviewCache', cache, _syncedWebviewKeys);
  }

  void _pushDeltas(
    String globalName,
    Map<String, String> cache,
    Set<String> synced,
  ) {
    if (cache.isEmpty) return;
    final delta = <String, String>{};
    for (final entry in cache.entries) {
      if (synced.add(entry.key)) delta[entry.key] = entry.value;
    }
    if (delta.isEmpty) return;
    try {
      runtime.evaluate(
          'Object.assign(globalThis.$globalName || '
          '(globalThis.$globalName = Object.create(null)), ${jsonEncode(delta)});');
    } catch (_) {
      // 推送失败：撤销标记，下一轮重试。
      for (final key in delta.keys) {
        synced.remove(key);
      }
    }
  }

  /// 清空 JS 侧重放缓存（ajax + webview）。每个解析阶段开始时调用，
  /// 配合宿主 `ctx.clearStageCaches()`，防止缓存跨阶段无限增长。
  void resetReplayCaches() {
    _syncedAjaxKeys.clear();
    _syncedAjaxBytesKeys.clear();
    _syncedAjaxMetaKeys.clear();
    _syncedWebviewKeys.clear();
    if (_runtime == null) return;
    try {
      _runtime!.evaluate(
          'globalThis.__ajaxCache = Object.create(null);'
          'globalThis.__ajaxBytesCache = Object.create(null);'
          'globalThis.__ajaxMetaCache = Object.create(null);'
          'globalThis.__webviewCache = Object.create(null);');
    } catch (_) {}
  }

  /// 开始一轮 java 规则桥重放：清空 JS 侧规则缓存/待办并递增根内容版本。
  /// 缓存只在一次宿主规则求值的多轮重放内有效（跨求值内容不同，不能复用）。
  void resetRuleReplay() {
    if (_runtime == null) return;
    try {
      _runtime!.evaluate('globalThis.__javaRuleReset && globalThis.__javaRuleReset();');
    } catch (_) {}
  }

  /// 一轮重放开始：根内容版本归零，使脚本内 setContent 的缓存键跨轮稳定。
  void beginRuleRound() {
    if (_runtime == null) return;
    try {
      _runtime!
          .evaluate('globalThis.__javaRuleRound && globalThis.__javaRuleRound();');
    } catch (_) {}
  }

  /// 取走本轮 JS 记录的 java 规则桥待办（setContent/getString 等，按调用顺序）。
  List<Map<String, dynamic>> takeRuleOps() {
    if (_runtime == null) return const [];
    try {
      final r = _runtime!.evaluate(
          'globalThis.__javaRuleDrain ? globalThis.__javaRuleDrain() : "[]"');
      if (r.isError) return const [];
      final decoded = jsonDecode(r.stringResult);
      if (decoded is! List) return const [];
      return decoded.whereType<Map>().map(Map<String, dynamic>.from).toList();
    } catch (_) {
      return const [];
    }
  }

  /// 把宿主求值结果写回 JS 侧规则缓存，供重放脚本命中。
  void fillRuleCache(Map<String, String> values) {
    if (values.isEmpty) return;
    try {
      // __javaRuleFill(json) 接收 JSON 文本，须再编码一层成 JS 字符串字面量
      // （直接把 JSON 对象字面量传进去会走 JSON.parse(object) → SyntaxError）。
      runtime.evaluate(
          'globalThis.__javaRuleFill && '
          'globalThis.__javaRuleFill(${jsonEncode(jsonEncode(values))});');
    } catch (_) {}
  }

  /// 执行 [jsStr]，绑定 [bindings] 为 JS 全局变量。
  ///
  /// 返回值规整（对齐书源脚本语义）：
  /// - 脚本异常 / 返回 `undefined` / `null` → 空串（书源表达式里无意义，
  /// 避免 URL 等场景出现字面量 "null"）；
  /// - QuickJS 把整数表达式返回为 double（`19.0`）时去掉小数位；
  /// - 其余按字符串原样返回。
  ///
  /// 执行失败记录到运行日志（设置 → 高级 → 运行日志），便于真机排查
  /// 「书源 JS 规则不生效」类问题（脚本摘要 + 错误信息）。
  String eval(String jsStr, {Map<String, dynamic>? bindings}) {
    try {
      final result = _evaluatePrepared(jsStr, bindings);
      if (result.isError) {
        AppLog.instance.w('[书源JS] 执行失败: ${_brief(jsStr)} → ${result.stringResult}');
        return '';
      }
      var s = result.stringResult;
      if (s == 'null' || s == 'undefined' || s.isEmpty) return '';
      // 整数结果带 .0（QuickJS 按 double 返回）时规整，避免 URL 拼接出错。
      if (s.length > 2 && RegExp(r'^-?\d+\.0+$').hasMatch(s)) {
        s = s.substring(0, s.indexOf('.'));
      }
      return s;
    } catch (e) {
      AppLog.instance.w('[书源JS] 执行异常: ${_brief(jsStr)} → $e');
      return '';
    }
  }

  /// 元素提取专用求值：返回 JS 完成值的 **结构化** 形态（List/Map/String）。
  ///
  /// [eval] 只回传 `stringResult`，对象数组会被字符串化成
  /// `[object Object],...`，规则层拿不到数组（JS 目录/列表规则全失效）。
  /// 这里用 `JSON.stringify(eval(...))` 取回 JSON；脚本含顶层 `return`
  /// （eval 不接受）或结果无法序列化时，退回 [eval] 的字符串结果。
  dynamic evalStructured(String jsStr, {Map<String, dynamic>? bindings}) {
    try {
      final wrapped = 'JSON.stringify(eval("${_escapeJs(jsStr)}"))';
      final result = _evaluatePrepared(wrapped, bindings);
      if (result.isError) return eval(jsStr, bindings: bindings);
      final s = result.stringResult;
      if (s.isEmpty || s == 'null' || s == 'undefined') return null;
      try {
        return jsonDecode(s);
      } on FormatException {
        return eval(jsStr, bindings: bindings);
      }
    } catch (e) {
      AppLog.instance.w('[书源JS] 结构化求值异常: ${_brief(jsStr)} → $e');
      return null;
    }
  }

  /// 注入上下文/绑定后执行脚本并排空 java 桥（[eval]/[evalStructured] 共用）。
  NexJsEvalResult _evaluatePrepared(
      String jsStr, Map<String, dynamic>? bindings) {
    // 注入对象上下文种子（cookie/source/book/cache）：活动作用域存在时
    // 每轮 eval 注入快照，写回经排空协议（__shuyuanCtx.c）落回宿主。
    final activeCtx = ShuyuanSourceContext.current;
    if (activeCtx != null) {
      runtime.evaluate(
          'var __shuyuanCtx = ${_toJsValue(activeCtx.toSeed())};');
      // ajax / webview 重放缓存增量推送（不进 ctx 种子，避免每轮整表序列化）。
      _pushAjaxDeltas(activeCtx.ajaxCache);
      _pushAjaxBytesDeltas(activeCtx.ajaxBytesCache);
      _pushAjaxMetaDeltas(activeCtx.ajaxMetaCache);
      _pushWebviewDeltas(activeCtx.webviewCache);
      // jsLib 预执行（按源，同引擎同内容只执行一次）：书源自定义函数/
      // 变量对所有后续脚本可见（legado SharedJsScope 等效）。
      // jsLib 为 JSON 对象时（`{"name":"https://.../lib.js"}`）按 legado
      // SharedJsScope：逐个下载绝对 URL 的脚本后依序执行；下载走确定性
      // 重放（本轮登记 ajaxPending 返回占位，settle 抓取后下轮真正执行）。
      if (activeCtx.jsLib.isNotEmpty && _jsLibApplied != activeCtx.jsLib) {
        if (activeCtx.jsLib.trimLeft().startsWith('{')) {
          final urls = _jsLibUrls(activeCtx.jsLib);
          if (urls != null) {
            var allReady = true;
            for (final u in urls) {
              if (!activeCtx.ajaxCache.containsKey(u)) {
                allReady = false;
                if (!activeCtx.ajaxPending.contains(u)) {
                  activeCtx.ajaxPending.add(u);
                }
              }
            }
            if (allReady) {
              for (final u in urls) {
                final code = activeCtx.ajaxCache[u] ?? '';
                if (code.isEmpty) continue;
                final r = runtime.evaluate(code);
                if (r.isError) {
                  AppLog.instance.w('[书源JS] jsLib 下载脚本执行失败 $u: ${r.stringResult}');
                }
              }
              _jsLibApplied = activeCtx.jsLib;
            }
          } else {
            _jsLibApplied = activeCtx.jsLib;
            final r = runtime.evaluate(activeCtx.jsLib);
            if (r.isError) {
              AppLog.instance.w('[书源JS] jsLib 执行失败: ${r.stringResult}');
            }
          }
        } else {
          _jsLibApplied = activeCtx.jsLib;
          final r = runtime.evaluate(activeCtx.jsLib);
          if (r.isError) {
            AppLog.instance.w('[书源JS] jsLib 执行失败: ${r.stringResult}');
          }
        }
      }
    }
    if (bindings != null) {
      for (final entry in bindings.entries) {
        // `java` 由 java_extensions 预置对象提供（全局函数桥），
        // 宿主传入的字符串占位绑定一律跳过，避免覆盖。
        if (entry.key == 'java') continue;
        runtime.evaluate('var ${entry.key} = ${_toJsValue(entry.value)};');
      }
    }
    // 经直接 eval 求值：每次调用获得独立词法环境，顶层 `let/const/class`
    // 不再残留在全局。引擎按源池化，目录类规则（每章一条，企鹅浏览的
    // `let data = …; let option = …`）第二次求值原本整段报
    // `SyntaxError: redeclaration` → 章节 URL 全部为空。legado 的 Rhino
    // 每次 eval 也是新脚本作用域；`var`/function 仍挂全局（跨规则共享，
    // 与 legado SharedJsScope 等效）。完成值语义不变（eval 的完成值）。
    final result = runtime.evaluate('eval(${jsonEncode(jsStr)})');
    // 排空必须先于一切早退（isError 也一样）：脚本中途抛错（ajax 占位符
    // 下游解析失败）同样产生 ajax 记录，settle 循环依赖它暖缓存重试；
    // 完成值 undefined/null 的纯写脚本同样产生写操作（2026-11-14 实测）。
    if (jsStr.contains('java.') || ShuyuanSourceContext.current != null) {
      _drainJavaBridge();
    }
    return result;
  }

  /// eval 成功后统一排空 java.* 桥的三类宿主交互：
  /// toast/longToast → [JavaFeedback.onToast]（缺省运行日志）、
  /// log/logType → 运行日志、put → [_lastJavaVars]（由变量表持有方取走）。
  void _drainJavaBridge() {
    Map<String, dynamic>? payload;
    try {
      final r = runtime.evaluate(javaDrainExpr);
      if (!r.isError && r.stringResult.isNotEmpty) {
        final decoded = jsonDecode(r.stringResult);
        if (decoded is Map<String, dynamic>) payload = decoded;
      }
    } catch (_) {
      return;
    }
    if (payload == null) return;
    final toasts = payload['t'];
    if (toasts is List) {
      for (final t in toasts) {
        if (t is Map) {
          final msg = t['msg']?.toString() ?? '';
          final long = t['long'] == true;
          if (msg.isEmpty) continue;
          final sink = JavaFeedback.onToast;
          if (sink != null) {
            sink(msg, long: long);
          } else {
            AppLog.instance.i('[书源toast] $msg');
          }
        }
      }
    }
    final logs = payload['l'];
    if (logs is List) {
      for (final l in logs) {
        final msg = l?.toString() ?? '';
        if (msg.isEmpty) continue;
        final sink = JavaFeedback.onLog;
        if (sink != null) {
          sink(msg);
        } else {
          AppLog.instance.d('[书源log] $msg');
        }
      }
    }
    final vars = payload['v'];
    if (vars is Map) {
      // 注入对象写操作（__syop_* 前缀，JSON 序列化的 op 记录）先行剥离，
      // 回放到活动上下文；其余进入 _lastJavaVars 供变量表持有方取走。
      final syops = <Map<String, dynamic>>[];
      final cleanVars = <String, String>{};
      var hadSyop = false;
      vars.forEach((k, v) {
        final key = k.toString();
        if (key.startsWith('__syop_')) {
          hadSyop = true;
          try {
            final decoded = jsonDecode(v?.toString() ?? '');
            if (decoded is Map<String, dynamic>) syops.add(decoded);
          } catch (_) {}
          return;
        }
        if (v != null) cleanVars[key] = v.toString();
      });
      _lastJavaVars = cleanVars;
      if (hadSyop) {
        // 已读即删：即使本轮没有活动上下文（op 只能丢弃），也必须从 JS 侧
        // __javaVars 清掉。旧实现只在 syops 非空时清理，ctx 为空时 op 残留
        // 在全局对象里，会在「下一次恰好有 ctx」的排空里被迟到重放
        // （表现为 cookie / 源变量莫名晚一步写入）。
        runtime.evaluate(
            'if (globalThis.__javaVars) { for (var k in globalThis.__javaVars) '
            '{ if (String(k).indexOf("__syop_") === 0) '
            'delete globalThis.__javaVars[k]; } }');
      }
      final ctx = ShuyuanSourceContext.current;
      if (ctx != null && syops.isNotEmpty) {
        ctx.applyOps(syops);
        // 持久化（fire-and-forget：下一轮种子取内存镜像）。
        ctx.persistIfNeeded();
      }
    }
  }

  String evalWithResult(String jsStr, {Map<String, dynamic>? bindings}) {
    return eval(jsStr, bindings: bindings);
  }

  /// 截断脚本为单行摘要（日志用，避免长脚本刷屏）。
  static String _brief(String js) {
    final oneLine = js.replaceAll('\n', ' ').trim();
    return oneLine.length > 140 ? '${oneLine.substring(0, 140)}…' : oneLine;
  }

  String _toJsValue(dynamic value) {
    if (value == null) return 'null';
    if (value is String) return '"${_escapeJs(value)}"';
    if (value is num) return value.toString();
    if (value is bool) return value.toString();
    if (value is List) {
      final items = value.map(_toJsValue).join(',');
      return '[$items]';
    }
    if (value is Map) {
      final entries = value.entries.map((e) => '"${_escapeJs(e.key.toString())}":${_toJsValue(e.value)}').join(',');
      return '{$entries}';
    }
    return '"${_escapeJs(value.toString())}"';
  }

  String _escapeJs(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t')
        // JS 行分隔符/段分隔符（正文等文本可能含，直接放入 JS 字符串字面量
        // 会触发 SyntaxError，须按 \u 转义）。
        .replaceAll('\u2028', '\\u2028')
        .replaceAll('\u2029', '\\u2029');
  }

  /// jsLib JSON 对象（`{"name":"https://host/lib.js"}`）里的绝对脚本 URL。
  /// 解析失败返回 null（按普通 JS 内容处理）。
  static List<String>? _jsLibUrls(String lib) {
    try {
      final decoded = jsonDecode(lib);
      if (decoded is! Map) return null;
      final urls = <String>[];
      for (final v in decoded.values) {
        final s = v?.toString() ?? '';
        if (s.startsWith('http://') || s.startsWith('https://')) {
          urls.add(s);
        }
      }
      return urls;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    // 若本实例仍挂在按源池里，一并摘除，避免池中留下已释放的引擎。
    _pool.removeWhere((_, engine) => identical(engine, this));
    _runtime?.dispose();
    _runtime = null;
    // 运行时重建后需重新注入预置脚本。
    _preludeInjected = false;
    _jsLibApplied = null;
    _syncedAjaxKeys.clear();
    _syncedAjaxBytesKeys.clear();
    _syncedAjaxMetaKeys.clear();
    _syncedWebviewKeys.clear();
  }
}
