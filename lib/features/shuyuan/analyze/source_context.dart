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

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ShuyuanSourceContext {
  ShuyuanSourceContext(this.sourceId);

  final String sourceId;

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

  /// 排空时标记：本次 eval 是否有 cookie 写（需持久化）。
  bool cookiesDirty = false;

  /// 排空时标记：源变量有写（需持久化）。
  bool sourceVarsDirty = false;

  // ── 作用域栈：WebBook 流程内 push/pop，JS 种子/排空读 current ──
  static final List<ShuyuanSourceContext> _stack = <ShuyuanSourceContext>[];

  static ShuyuanSourceContext? get current =>
      _stack.isEmpty ? null : _stack.last;

  static void push(ShuyuanSourceContext context) => _stack.add(context);

  static void pop() {
    if (_stack.isNotEmpty) _stack.removeLast();
  }

  /// 在上下文作用域内执行（空上下文直接执行，零开销）。
  static R run<R>(ShuyuanSourceContext? context, R Function() body) {
    if (context == null) return body();
    push(context);
    try {
      return body();
    } finally {
      pop();
    }
  }

  // ── 种子：注入 JS 的快照（必须深拷贝——若传活引用，JS 直改原表，
  // 排空 diff 恒为零差异，dirty/持久化标志永不触发） ──
  Map<String, dynamic> toSeed() => <String, dynamic>{
        'sourceId': sourceId,
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
        'ajaxCache': Map<String, String>.from(ajaxCache),
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

  static bool _hostMatch(String a, String b) {
    if (a.isEmpty || b.isEmpty) return true;
    return a == b ||
        a.endsWith('.$b') ||
        b.endsWith('.$a') ||
        a.endsWith(b) ||
        b.endsWith(a);
  }

  /// 取 host 匹配的 cookie 覆盖层（后缀匹配：cookie host 或请求 host 任一
  /// 为对方后缀即命中，兼容登录域与站点域不同的情况）。
  Map<String, String> cookiesForHost(String host) {
    final h = host.toLowerCase().trim();
    if (h.isEmpty || cookies.isEmpty) return const {};
    final out = <String, String>{};
    cookies.forEach((name, meta) {
      final ch = (meta['host'] ?? '').toLowerCase().trim();
      if (ch.isEmpty ||
          h == ch ||
          h.endsWith('.$ch') ||
          ch.endsWith('.$h') ||
          h.endsWith(ch) ||
          ch.endsWith(h)) {
        out[name] = meta['value'] ?? '';
      }
    });
    return out;
  }

  // ── cookie 覆盖层持久化（per sourceId） ──
  static const String _cookieStoreKey = 'shuyuan_source_cookies_v1';
  static Map<String, Map<String, Map<String, String>>>? _cookieCache;
  static final Set<String> _loadedSources = <String>{};

  /// 创建（或取缓存的）上下文；cookie 覆盖层从持久化装载一次。
  static Future<ShuyuanSourceContext> forSource(String sourceId) async {
    if (_loadedSources.contains(sourceId)) {
      // 已装载过：从既有静态缓存找（resolver 持有实例时通常不走这里）。
      return ShuyuanSourceContext(sourceId);
    }
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
    _loadedSources.add(sourceId);
    return ctx;
  }

  /// 排空后持久化 cookie 覆盖层（仅 dirty 时）。
  Future<void> persistIfNeeded() async {
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

  /// 测试隔离。
  static void resetForTest() {
    _stack.clear();
    _cookieCache = null;
    _loadedSources.clear();
  }
}
