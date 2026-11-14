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
      // 注入对象上下文种子（cookie/source/book/cache）：活动作用域存在时
      // 每轮 eval 注入快照，写回经排空协议（__shuyuanCtx.c）落回宿主。
      final activeCtx = ShuyuanSourceContext.current;
      if (activeCtx != null) {
        runtime.evaluate(
            'var __shuyuanCtx = ${_toJsValue(activeCtx.toSeed())};');
        // jsLib 预执行（按源，同引擎同内容只执行一次）：书源自定义函数/
        // 变量对所有后续脚本可见（legado SharedJsScope 等效）。
        if (activeCtx.jsLib.isNotEmpty && _jsLibApplied != activeCtx.jsLib) {
          _jsLibApplied = activeCtx.jsLib;
          final r = runtime.evaluate(activeCtx.jsLib);
          if (r.isError) {
            AppLog.instance.w('[书源JS] jsLib 执行失败: ${r.stringResult}');
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
      final result = runtime.evaluate(jsStr);
      // 排空必须先于一切早退（isError 也一样）：脚本中途抛错（ajax 占位符
      // 下游解析失败）同样产生 ajax 记录，settle 循环依赖它暖缓存重试；
      // 完成值 undefined/null 的纯写脚本同样产生写操作（2026-11-14 实测）。
      if (jsStr.contains('java.') || ShuyuanSourceContext.current != null) {
        _drainJavaBridge();
      }
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
      vars.forEach((k, v) {
        final key = k.toString();
        if (key.startsWith('__syop_')) {
          try {
            final decoded = jsonDecode(v?.toString() ?? '');
            if (decoded is Map<String, dynamic>) syops.add(decoded);
          } catch (_) {}
          return;
        }
        if (v != null) cleanVars[key] = v.toString();
      });
      _lastJavaVars = cleanVars;
      if (syops.isNotEmpty) {
        // 已消费的 __syop_* 条目必须从 JS 侧 __javaVars 对象中清除——
        // 否则每轮排空重复投递旧操作（无 bindings 重播种的流程里
        // __javaVars 对象跨 eval 持久）。
        runtime.evaluate(
            'if (globalThis.__javaVars) { for (var k in globalThis.__javaVars) '
            '{ if (String(k).indexOf("__syop_") === 0) '
            'delete globalThis.__javaVars[k]; } }');
        final ctx = ShuyuanSourceContext.current;
        if (ctx != null) {
          ctx.applyOps(syops);
          // cookie 覆盖层持久化（fire-and-forget：下一轮种子取内存镜像）。
          ctx.persistIfNeeded();
        }
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

  void dispose() {
    _runtime?.dispose();
    _runtime = null;
    // 运行时重建后需重新注入预置脚本。
    _preludeInjected = false;
  }
}
