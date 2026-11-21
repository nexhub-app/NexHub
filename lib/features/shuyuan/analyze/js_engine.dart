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
import 'js_syntax_compat.dart';
import 'jsoup_dom.dart';
import 'source_context.dart';

/// JS 求值结果：成功时 [error] 为 null；失败时 [value] 为空串、[error]
/// 为 QuickJS 错误文本（供发现脚本等上层以可见错误态呈现，而非静默空）。
class JsEvalOutcome {
  final String value;
  final String? error;

  const JsEvalOutcome(this.value, {this.error});
}

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
  final Set<String> _syncedBrowserAwaitKeys = <String>{};
  final Set<String> _syncedVerificationKeys = <String>{};

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
    // org.jsoup.Jsoup.parse + 最小 DOM/CSS 选择器（Rhino 直调 jsoup 的
    // 脚本面）。依赖上方预置脚本已建立 global.org.jsoup.Jsoup。
    try {
      final result = _runtime!.evaluate(jsoupDomJsPrelude);
      if (result.isError) {
        AppLog.instance.w(
            '[书源JS] jsoup DOM 预置脚本注入失败: ${result.stringResult}');
      }
    } catch (e) {
      AppLog.instance.w('[书源JS] jsoup DOM 预置脚本注入异常: $e');
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

  /// `java.startBrowserAwait` 的宿主响应（JSON 载荷）增量推送。
  void _pushBrowserAwaitDeltas(Map<String, String> cache) {
    _pushDeltas('__browserAwaitCache', cache, _syncedBrowserAwaitKeys);
  }

  /// `java.getVerificationCode` 的用户输入值增量推送。
  void _pushVerificationDeltas(Map<String, String> cache) {
    _pushDeltas('__verificationCodeCache', cache, _syncedVerificationKeys);
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

  /// 清空 JS 侧重放缓存（ajax + webview + 交互）。每个解析阶段开始时调用，
  /// 配合宿主 `ctx.clearStageCaches()`，防止缓存跨阶段无限增长。
  void resetReplayCaches() {
    _syncedAjaxKeys.clear();
    _syncedAjaxBytesKeys.clear();
    _syncedAjaxMetaKeys.clear();
    _syncedWebviewKeys.clear();
    _syncedBrowserAwaitKeys.clear();
    _syncedVerificationKeys.clear();
    if (_runtime == null) return;
    try {
      _runtime!.evaluate(
          'globalThis.__ajaxCache = Object.create(null);'
          'globalThis.__ajaxBytesCache = Object.create(null);'
          'globalThis.__ajaxMetaCache = Object.create(null);'
          'globalThis.__webviewCache = Object.create(null);'
          'globalThis.__browserAwaitCache = Object.create(null);'
          'globalThis.__verificationCodeCache = Object.create(null);');
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
    return evalChecked(jsStr, bindings: bindings).value;
  }

  /// 与 [eval] 相同，但保留错误信息（失败时 [JsEvalOutcome.error] 非空）。
  JsEvalOutcome evalChecked(
    String jsStr, {
    Map<String, dynamic>? bindings,
  }) {
    try {
      final result = _evaluatePrepared(jsStr, bindings);
      if (result.isError) {
        final msg = result.stringResult;
        AppLog.instance.w('[书源JS] 执行失败: ${_brief(jsStr)} → $msg');
        return JsEvalOutcome('', error: msg.isEmpty ? '脚本执行失败' : msg);
      }
      var s = result.stringResult;
      if (s == 'null' || s == 'undefined' || s.isEmpty) {
        return const JsEvalOutcome('');
      }
      // 整数结果带 .0（QuickJS 按 double 返回）时规整，避免 URL 拼接出错。
      if (s.length > 2 && RegExp(r'^-?\d+\.0+$').hasMatch(s)) {
        s = s.substring(0, s.indexOf('.'));
      }
      return JsEvalOutcome(s);
    } catch (e) {
      AppLog.instance.w('[书源JS] 执行异常: ${_brief(jsStr)} → $e');
      return JsEvalOutcome('', error: '$e');
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
      _pushBrowserAwaitDeltas(activeCtx.browserAwaitCache);
      _pushVerificationDeltas(activeCtx.verificationCodeCache);
      // jsLib 预执行（按源，同引擎同内容只执行一次）：书源自定义函数/
      // 变量对所有后续脚本可见（legado SharedJsScope 等效）。
      // jsLib 为 JSON 对象时（`{"name":"https://.../lib.js"}`）按 legado
      // SharedJsScope：逐个下载绝对 URL 的脚本后依序执行；下载走确定性
      // 重放（本轮登记 ajaxPending 返回占位，settle 抓取后下轮真正执行）。
      if (activeCtx.jsLib.isNotEmpty && _jsLibApplied != activeCtx.jsLib) {
        if (activeCtx.jsLib.trimLeft().startsWith('{')) {
          final urls = _jsLibUrls(activeCtx.jsLib);
          if (urls != null) {
            // 空白下载结果视为失败（legado SharedJsScope 下载失败直接抛错、
            // 不缓存 scope）：只有全部脚本正文非空并执行成功才标记已应用，
            // 否则保留未应用状态，下个阶段/下次展开重新登记下载重试。
            var allReady = true;
            for (final u in urls) {
              final code = activeCtx.ajaxCache[u];
              if (code == null) {
                allReady = false;
                if (!activeCtx.ajaxPending.contains(u)) {
                  activeCtx.ajaxPending.add(u);
                }
              } else if (code.isEmpty) {
                allReady = false;
              }
            }
            if (allReady) {
              for (final u in urls) {
                final code = activeCtx.ajaxCache[u] ?? '';
                final r = _evalLibSource(code);
                if (r.isError) {
                  AppLog.instance.w('[书源JS] jsLib 下载脚本执行失败 $u: ${r.stringResult}');
                }
              }
              _jsLibApplied = activeCtx.jsLib;
            }
          } else {
            _jsLibApplied = activeCtx.jsLib;
            final r = _evalLibSource(activeCtx.jsLib);
            if (r.isError) {
              AppLog.instance.w('[书源JS] jsLib 执行失败: ${r.stringResult}');
            }
          }
        } else {
          _jsLibApplied = activeCtx.jsLib;
          final r = _evalLibSource(activeCtx.jsLib);
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
    //
    // 大脚本计时面包屑：QuickJS 同步执行在主 isolate，无中断手段——若卡死，
    // 起始行是最后一条日志（完成行缺失），据「输入长度 + 片段」定位肇事脚本。
    final Stopwatch? watch =
        jsStr.length >= 800 ? (Stopwatch()..start()) : null;
    if (watch != null) {
      AppLog.instance.i('[书源JS] 大脚本求值开始 长度=${jsStr.length} '
          '片段=${_brief(jsStr)}');
    }
    _seedDeterministicRandom(jsStr);
    final result = runtime.evaluate('eval(${jsonEncode(jsStr)})');
    if (watch != null) {
      AppLog.instance.i('[书源JS] 大脚本求值完成 长度=${jsStr.length} '
          '耗时=${watch.elapsedMilliseconds}ms 错误=${result.isError}');
    }
    // 排空必须先于一切早退（isError 也一样）：脚本中途抛错（ajax 占位符
    // 下游解析失败）同样产生 ajax 记录，settle 循环依赖它暖缓存重试；
    // 完成值 undefined/null 的纯写脚本同样产生写操作（2026-11-14 实测）。
    if (jsStr.contains('java.') || ShuyuanSourceContext.current != null) {
      _drainJavaBridge();
    }
    return result;
  }

  /// 书源脚本的随机源在重放轮之间必须可复现。
  ///
  /// legado 桥是同步的：一次求值就是一次真实请求，脚本里的随机 UUID、
  /// jsLib 签名算法里的 `Math.random()` 只影响这一次。确定性重放却要把
  /// 同一脚本跑多轮：若每轮随机序列不同，拼出的 URL/签名每轮都变，
  /// 占位符缓存永远无法命中（多跳握手在轮次预算内不收敛，发现页分类
  /// 直接报错）。这里按脚本内容散列定种子并逐次求值重置序列：同一脚本
  /// 跨轮同序列（可收敛），单次求值内仍逐次推进（同轮多次 randomUUID
  /// 互不相同）。种子只依赖脚本文本，跨阶段无关。
  void _seedDeterministicRandom(String jsStr) {
    var seed =
        (jsStr.hashCode ^ (jsStr.length * 2654435761)) & 0x7fffffff;
    if (seed == 0) seed = 1;
    try {
      runtime.evaluate(
        'globalThis.__shuyuanRng = $seed >>> 0;'
        'Math.random = function () {'
        '  var x = globalThis.__shuyuanRng >>> 0;'
        '  x ^= x << 13; x >>>= 0;'
        '  x ^= x >>> 17;'
        '  x ^= x << 5; x >>>= 0;'
        '  globalThis.__shuyuanRng = x;'
        '  return x / 4294967296;'
        '};',
      );
    } catch (_) {
      // 注入失败保持原生随机：脚本照常执行，只是重放可能不收敛。
    }
  }

  /// 执行 jsLib 源码；整段脚本解析失败（Rhino 专有语法）时按兼容写法
  /// 重试一次。仅在语法类错误且可改写时执行，避免把运行期错误误判为
  /// 脚本语法问题（鸿蒙 QuickJS 桥的错误文本无 `<eval>:` 定位，不能只靠
  /// 堆栈位置判定）。
  NexJsEvalResult _evalLibSource(String code) {
    final r = runtime.evaluate(code);
    if (!r.isError) return r;
    final msg = r.stringResult;
    if (!isLegacySyntaxFailure(msg)) return r;
    final adapted = adaptLegacyJs(code);
    if (identical(adapted, code)) return r;
    AppLog.instance.w('[书源JS] jsLib 含 Rhino 专有语法，按兼容写法重试');
    return runtime.evaluate(adapted);
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
      final activeCtx = ShuyuanSourceContext.current;
      for (final t in toasts) {
        if (t is Map) {
          final msg = t['msg']?.toString() ?? '';
          final long = t['long'] == true;
          if (msg.isEmpty) continue;
          if (activeCtx != null && activeCtx.deferFeedback) {
            activeCtx.deferredToasts.add((msg: msg, long: long));
            continue;
          }
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
    _syncedBrowserAwaitKeys.clear();
    _syncedVerificationKeys.clear();
  }
}
