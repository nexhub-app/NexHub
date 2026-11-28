/// legado `java.*` JS 桥第一梯队（P0-2）：纯计算函数在 QuickJS 沙箱内
/// 以 JS 原生实现（同步语义，零宿主桥接，符合「JS 沙箱必须同步执行」硬规则）。
///
/// 架构：
/// - 本库输出 [javaExtensionsJsPrelude]，由 JsEngine 在运行时创建时与繁简
///   转换预置脚本一并注入，定义全局 `java` 对象；
/// - 涉及宿主交互的三类调用走「排空协议」：`java.toast/longToast` 推入
///   `__javaToasts` 队列、`java.log/logType` 推入 `__javaLogs` 队列、
///   `java.put` 写入 `__javaVars`，由 JsEngine.eval 结束后统一收取
///   （见 [JavaFeedback] 与 `JsEngine.takeJavaVars`）；
/// - 网络族（ajax/connect/get/post/head）与 WebView 走「确定性重放」：
///   首轮返回占位符并记录请求，宿主 settle 后写入增量缓存再重放；
/// - 纯计算族（md5/base64/hex/AES/TTF 解析与字体还原）全部在 JS 内同步实现；
/// - 文件族支持 `cacheFile(url)` + `readTxtFile(path)`（脚本注入常用组合，
///   内容走 ajax 重放、按虚拟路径存取）；readFile/unzipFile 等二进制文件族
///   尚未接入 → 调用抛 TypeError → 既有 `[书源JS]` 日志兜底，行为安全。
///
/// 语义对齐 legado JsExtensions.kt / JsEncodeUtils.kt（UTF-8 恒定；
/// encodeURI 为 Java URLEncoder 口径：空格→`+`）。
library;

/// java.* 排空的宿主回调。UI 层可挂 SnackBar 等呈现；缺省回退运行日志。
abstract final class JavaFeedback {
  /// 源脚本调用 `java.toast/longToast` 时触发（long=长吐司）。
  static void Function(String msg, {bool long})? onToast;

  /// 源脚本调用 `java.log/logType` 时触发。
  static void Function(String msg)? onLog;
}

/// JsEngine.eval 结束后执行的排空表达式：一次取走本轮 toast/日志队列
/// 与变量快照（避免每次规则求值残留），并带出注入对象上下文（cookie/
/// source/book/cache 的写回）。须用 globalThis——本表达式在顶层求值，
/// IIFE 内的 `global` 参数不可见。
const String javaDrainExpr = r'''
JSON.stringify({t:(globalThis.__javaToasts||[]).splice(0),l:(globalThis.__javaLogs||[]).splice(0),v:globalThis.__javaVars||{},d:(globalThis.__javaDeleted||[]).splice(0),c:(globalThis.chapter&&globalThis.chapter.variableMap)||null,cd:(globalThis.chapter&&globalThis.chapter.__syDeleted||[]).splice(0),bc:(globalThis.chapter&&globalThis.chapter.__syBigVariables)||null,bd:(globalThis.chapter&&globalThis.chapter.__syBigDeleted||[]).splice(0)})
''';

/// 注入对象预置脚本（P1-2）：cookie / source / book / cache 四对象，
/// 读写全部经 `__shuyuanCtx`（宿主经 ShuyuanSourceContext 种子注入、
/// eval 后排空回写），语义对齐 legado BookSourceCookieStore / BaseSource /
/// CacheManager。
const String sourceContextJsPrelude = r'''
(function (global) {
  'use strict';

  function syCtx() {
    if (!global.__shuyuanCtx || typeof global.__shuyuanCtx !== 'object') {
      global.__shuyuanCtx = { sourceId: '', sourceVars: {}, sourceMeta: {},
        temporaryVars: {},
        bookVars: {}, bookInfo: {}, cookies: {}, loginInfo: {}, loginHeader: {},
        cache: {}, cacheBytes: {} };
    }
    return global.__shuyuanCtx;
  }

  function syHost(u) {
    var s = String(u || '');
    var m = s.match(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\/([^\/?#]+)/);
    var host = m ? m[1] : (s.indexOf('/') >= 0 ? s.substring(0, s.indexOf('/')) : s);
    host = String(host).split('@').pop().split(':')[0].toLowerCase();
    return host;
  }

  // syHostMatch(cookieHost, requestHost)：cookie 是否应随该请求下发。
  // 与宿主 ShuyuanSourceContext.hostMatches 同口径——请求 host 等于
  // cookie host 或是其子域才命中；两端都 endsWith 的旧写法会让
  // `evil-example.com` 收走 `example.com` 的登录 cookie。
  function syHostMatch(cookieHost, requestHost) {
    var ch = String(cookieHost || '').toLowerCase();
    var h = String(requestHost || '').toLowerCase();
    if (!ch || !h) return true;
    return h === ch || h.endsWith('.' + ch);
  }

  /// djb2 变体：把可能很长的 html/js 压成短键（webView 的重放缓存键）。
  function syHash(s) {
    var h = 5381;
    for (var i = 0; i < s.length; i++) {
      h = ((h * 33) ^ s.charCodeAt(i)) >>> 0;
    }
    return h.toString(16);
  }

  // ── 写操作日志：所有注入对象的可变操作显式记 op（宿主排空回放），
  // 本地同步改一份工作副本供同轮 eval 内读取。
  // 通道注意：ops 必须走 __javaVars（var 绑定种子通道，宿主排空已验证
  // 可靠）；__shuyuanOps 直挂 globalThis 的方案在排空求值里读不到
  // （排空视野无裸 global 别名、且 global.X 赋值属性不可见——实测）。 ──
  var __syopN = 0;
  function syOp(op, a, b, c) {
    var v = global.__javaVars;
    if (!v || typeof v !== 'object') {
      v = {};
      global.__javaVars = v;
    }
    __syopN++;
    var rec = { op: op, a: a == null ? '' : a, b: b == null ? '' : b };
    if (c != null) rec.c = c;
    v['__syop_' + __syopN] = JSON.stringify(rec);
  }

  var cookie = {
    // getKey(tag, key)：取 tag（URL/书源 key）下名为 key 的 cookie 值。
    getKey: function (url, key) {
      var ctx = syCtx(); var host = syHost(url); var found = '';
      for (var name in ctx.cookies) {
        var meta = ctx.cookies[name];
        if (!meta) continue;
        if (String(name) === String(key) &&
            syHostMatch(syHost(meta.host), host)) {
          found = meta.value || '';
        }
      }
      return found;
    },
    getCookie: function (url, key) {
      var ctx = syCtx(); var host = syHost(url);
      var parts = [];
      for (var name in ctx.cookies) {
        var meta = ctx.cookies[name];
        if (!meta) continue;
        if (syHostMatch(syHost(meta.host), host)) {
          parts.push(name + '=' + (meta.value || ''));
        }
      }
      var header = parts.join('; ');
      if (key != null && key !== '') {
        var esc = String(key).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        var m = header.match(new RegExp('(?:^|;\\s*)' + esc + '=([^;]*)'));
        return m ? m[1] : '';
      }
      return header;
    },
    setCookie: function (url, cookieStr) {
      var ctx = syCtx(); var host = syHost(url);
      String(cookieStr == null ? '' : cookieStr).split(/;\s*/).forEach(function (p) {
        var i = p.indexOf('=');
        if (i <= 0) return;
        var name = p.substring(0, i).trim();
        var value = p.substring(i + 1).trim();
        if (name) {
          ctx.cookies[name] = { value: value, host: host };
          syOp('setCookie', url, name + '=' + value);
        }
      });
      return null;
    },
    removeCookie: function (url) {
      var ctx = syCtx(); var host = syHost(url);
      for (var name in ctx.cookies) {
        var meta = ctx.cookies[name];
        if (!meta) continue;
        if (syHostMatch(syHost(meta.host), host)) {
          delete ctx.cookies[name];
        }
      }
      syOp('removeCookie', url, '');
      return null;
    },
    // legado 老版本脚本常用：写 WebView cookie；无内嵌 WebView 时并入
    // 请求 cookie 罐（对后续 ajax 生效，比原语义更宽但不破坏脚本）。
    setWebCookie: function (url, cookieStr) {
      return cookie.setCookie(url, cookieStr);
    },
    // legado `CookieStore.replaceCookie`：与已有 Cookie **合并**写入
    //（同 key 以新值覆盖，其余保留）。登录脚本刷新会话时高频使用。
    replaceCookie: function (url, cookieStr) {
      var u = String(url == null ? '' : url);
      var incoming = String(cookieStr == null ? '' : cookieStr);
      if (!u || !incoming) return null;
      var oldCookie = cookie.getCookie(u);
      var merged = cookie.cookieToMap(oldCookie + '; ' + incoming);
      return cookie.setCookie(u, cookie.mapToCookie(merged));
    },
    // legado `CookieStore.cookieToMap(cookie: String)`：Cookie 串 → 键值表。
    cookieToMap: function (cookieStr) {
      var map = {};
      var s = String(cookieStr == null ? '' : cookieStr);
      if (!s) return map;
      s.split(/;\s*/).forEach(function (pair) {
        if (!pair) return;
        var eq = pair.indexOf('=');
        if (eq <= 0) return;
        var k = pair.substring(0, eq).trim();
        var v = pair.substring(eq + 1).trim();
        // legado：值非空，或字面量 "null" 才收录。
        if (v !== '' || v === 'null') map[k] = v;
      });
      return map;
    },
    // legado `CookieStore.mapToCookie`：键值表 → `k=v; k2=v2`。
    mapToCookie: function (map) {
      if (map == null || typeof map !== 'object') return null;
      var parts = [];
      for (var k in map) {
        if (map[k] == null) continue;
        parts.push(k + '=' + String(map[k]));
      }
      return parts.length ? parts.join('; ') : null;
    },
    // legado `CookieStore.clear()`：清空本源 cookie 覆盖层。
    clear: function () {
      var ctx = syCtx();
      var names = Object.keys(ctx.cookies);
      for (var i = 0; i < names.length; i++) delete ctx.cookies[names[i]];
      syOp('removeCookie', '', '');
      return null;
    },
  };

  var source = {
    getKey: function () { return syCtx().sourceKey || syCtx().sourceId; },
    // legado `BaseSource.getTag()`：小说源返回 bookSourceName。
    getTag: function () {
      var meta = syCtx().sourceMeta;
      return meta && meta.bookSourceName != null
        ? String(meta.bookSourceName) : '';
    },
    // legado BaseSource.get/put：CacheManager 持久化的键值对
    // （`v_<getKey()>_<key>`）。get 缺省返回空串；put 返回写入值。
    // 键加 `__v:` 前缀与 putVariable 的源变量命名空间隔离。
    get: function (k) {
      var v = syCtx().sourceVars['__v:' + String(k)];
      return v == null ? '' : v;
    },
    put: function (k, v) {
      var s = String(v == null ? '' : v);
      syCtx().sourceVars['__v:' + String(k)] = s;
      syOp('sourceVar', '__v:' + k, s);
      return s;
    },
    getVariable: function (k) {
      var c = syCtx();
      // legado BaseSource.getVariable：temporaryVariable 优先于持久源变量
      //（审计 M18：首页模块 args 以临时变量进入发现请求）。
      var t = c.temporaryVars;
      if (k == null || k === '') {
        return (t && t['__variable'] != null)
            ? t['__variable']
            : (c.sourceVars['__variable'] || '');
      }
      return (t && t[String(k)] != null)
          ? t[String(k)]
          : (c.sourceVars[String(k)] || '');
    },
    putVariable: function (k, v) {
      // legado BaseSource.putVariable(variable) 是单参：写入整段源变量，
      // 与 getVariable()/setVariable() 同一存储（发现页设置状态、登录数据
      // 都走这条通道）。两参写法是本实现的键值扩展，保留兼容。
      if (arguments.length < 2) {
        // legado BaseSource.putVariable(variable: String?)：null 删除整段源变量。
        if (k == null) {
          delete syCtx().sourceVars['__variable'];
          syOp('sourceVarDel', '__variable', '');
          return null;
        }
        var whole = String(k);
        syCtx().sourceVars['__variable'] = whole;
        syOp('sourceVar', '__variable', whole);
        return whole;
      }
      if (k == null) return v;
      var key = String(k);
      // legado BaseSource.putVariable(k, null)：删除键，不能写空串占位。
      if (v == null) {
        delete syCtx().sourceVars[key];
        syOp('sourceVarDel', key, '');
        return null;
      }
      syCtx().sourceVars[key] = String(v);
      syOp('sourceVar', key, v);
      return v;
    },
    setVariable: function (v) {
      return source.putVariable(v);
    },
    // legado getLoginInfoMap 返回 Java HashMap：脚本常用 .get/.put。
    getLoginInfoMap: function () {
      var c = syCtx();
      var m = {};
      for (var k in c.loginInfo) m[k] = c.loginInfo[k];
      var emit = function () { syOp('loginInfo', JSON.stringify(m), ''); };
      var def = function (n, f) {
        try { Object.defineProperty(m, n, { value: f, enumerable: false }); }
        catch (e) { m[n] = f; }
      };
      def('get', function (k) {
        var v = m[String(k)];
        return v === undefined ? null : v;
      });
      def('put', function (k, v) {
        var s = String(v == null ? '' : v);
        m[String(k)] = s;
        c.loginInfo[String(k)] = s;
        emit();
        return v;
      });
      def('containsKey', function (k) {
        return Object.prototype.hasOwnProperty.call(m, String(k));
      });
      def('remove', function (k) {
        var s = String(k);
        delete m[s];
        delete c.loginInfo[s];
        emit();
        return null;
      });
      def('isEmpty', function () {
        for (var x in m) return false;
        return true;
      });
      return m;
    },
    // legado BaseSource.getLoginInfo：登录信息整段 JSON 字符串（无信息 null）。
    getLoginInfo: function () {
      var c = syCtx();
      var has = false;
      var o = {};
      for (var k in c.loginInfo) {
        o[k] = c.loginInfo[k];
        has = true;
      }
      return has ? JSON.stringify(o) : null;
    },
    putLoginInfo: function (m) {
      var c = syCtx();
      var obj = m;
      if (typeof obj === 'string') {
        try { obj = JSON.parse(obj); } catch (e) { obj = null; }
      }
      if (obj && typeof obj === 'object') {
        for (var k in c.loginInfo) delete c.loginInfo[k];
        for (var k in obj) c.loginInfo[k] = String(obj[k] == null ? '' : obj[k]);
      }
      // legado putLoginInfo(String)：存整段 JSON；宿主按 JSON 落表。
      syOp('loginInfo', JSON.stringify(m == null ? '' : m), '');
      return true;
    },
    removeLoginInfo: function (k) {
      var c = syCtx();
      if (k == null || k === '') {
        for (var x in c.loginInfo) delete c.loginInfo[x];
      } else {
        delete c.loginInfo[String(k)];
      }
      syOp('loginInfoDel', k == null ? '' : String(k), '');
      return null;
    },
    // legado getLoginHeader()：原样返回最近一次 putLoginHeader 的字符串
    // （可能是书源私有格式，如 `#` 前缀 + JSON），由脚本自行解析。
    getLoginHeader: function () { return syCtx().loginHeaderRaw || ''; },
    getLoginHeaderMap: function () {
      var c = syCtx();
      var raw = c.loginHeaderRaw || '';
      if (raw) {
        try {
          var m = JSON.parse(raw);
          if (m && typeof m === 'object') return m;
        } catch (e) {}
        return {};
      }
      return c.loginHeader;
    },
    putLoginHeader: function (m) {
      var c = syCtx();
      var raw;
      if (typeof m === 'string') {
        raw = m;
      } else {
        var merged = {};
        for (var k in c.loginHeader) merged[k] = c.loginHeader[k];
        if (m && typeof m === 'object') {
          for (var k in m) merged[k] = String(m[k] == null ? '' : m[k]);
        }
        raw = JSON.stringify(merged);
      }
      c.loginHeaderRaw = raw;
      for (var k in c.loginHeader) delete c.loginHeader[k];
      try {
        var parsed = JSON.parse(raw);
        if (parsed && typeof parsed === 'object') {
          for (var k in parsed) {
            c.loginHeader[k] = String(parsed[k] == null ? '' : parsed[k]);
          }
        }
      } catch (e) {}
      syOp('loginHeader', JSON.stringify(raw), '');
      return null;
    },
    removeLoginHeader: function () {
      var c = syCtx();
      c.loginHeaderRaw = '';
      for (var k in c.loginHeader) delete c.loginHeader[k];
      syOp('loginHeaderDel', '', '');
      return null;
    },
    refreshExplore: function () {
      syOp('refreshKinds', '', '');
      return true;
    },
    // legado BaseSource.refreshJSLib：清除 jsLib 作用域，下次求值重新执行
    // （SharedJsScope.remove）。
    refreshJSLib: function () { syOp('refreshJSLib', '', ''); return true; },
    refreshBookUrl: function () { return true; },
    // legado BaseSource.putConcurrent：运行期调整本源并发率
    // （ConcurrentRateLimiter.updateConcurrentRate(getKey(), value)）。
    putConcurrent: function (value) {
      syOp('concurrentRate', String(value == null ? '' : value), '');
      return null;
    },
  };

  var book = {
    getVariable: function (k) { return syCtx().bookVars[String(k)] || ''; },
    putVariable: function (k, v) {
      var key = String(k);
      // legado BaseBook.putVariable(k, null)：删除键。
      if (v == null) {
        delete syCtx().bookVars[key];
        syOp('bookVarDel', key, '');
        return null;
      }
      syCtx().bookVars[key] = String(v);
      syOp('bookVar', key, v);
      return v;
    },
    setVariable: function (v) { return book.putVariable('__variable', v); },
  };
  ['name', 'author', 'bookUrl', 'intro', 'kind', 'coverUrl', 'lastChapter',
   'tocUrl', 'wordCount', 'origin', 'durChapterTitle',
   // E8：legado `Book` 其余字符串字段（脚本读 `book.originName` 分支、
   // 写 `book.latestChapterTitle` 修正最新章节等）。
   'originName', 'latestChapterTitle', 'infoHtml', 'tocHtml', 'group',
   'customTag', 'customIntro', 'customCoverUrl']
      .forEach(function (f) {
        Object.defineProperty(book, f, {
          get: function () { return syCtx().bookInfo[f] || ''; },
          set: function (v) {
            var s = String(v == null ? '' : v);
            syCtx().bookInfo[f] = s;
            // 书字段写入须走排空 op 才能到达宿主书对象（AnalyzeRule 在
            // eval 后按 bookInfo 回写）；JS 侧 syCtx 只是种子副本。
            syOp('bookField', f, s);
          },
        });
      });
  // E8：legado `Book.variable`（变量整段 JSON 串）。读写都落到
  // bookVars（= variableMap），与 putVariable/getVariable 同一存储。
  Object.defineProperty(book, 'variable', {
    get: function () {
      var c = syCtx();
      var o = {};
      for (var k in c.bookVars) o[k] = c.bookVars[k];
      return JSON.stringify(o);
    },
    set: function (v) {
      var c = syCtx();
      var parsed = null;
      if (typeof v === 'string') {
        try { parsed = JSON.parse(v); } catch (e) { parsed = null; }
      } else if (v && typeof v === 'object') {
        parsed = v;
      }
      // 整段替换：旧键中不在新串里的必须发删除事件，否则宿主 variableMap
      // 残留旧键，后续 getVariable 仍能读到。
      var removed = [];
      for (var k in c.bookVars) removed.push(k);
      for (var i = 0; i < removed.length; i++) delete c.bookVars[removed[i]];
      var kept = {};
      if (parsed && typeof parsed === 'object') {
        for (var key in parsed) {
          var s = String(parsed[key] == null ? '' : parsed[key]);
          c.bookVars[key] = s;
          kept[key] = true;
          syOp('bookVar', key, s);
        }
      }
      for (var j = 0; j < removed.length; j++) {
        if (!kept[removed[j]]) syOp('bookVarDel', removed[j], '');
      }
      return v;
    },
  });
  // E8：legado 数值字段可写（脚本按章修正进度/总数）。
  ['originOrder', 'totalChapterNum', 'latestChapterTime', 'durChapterPos',
   'fixedType']
      .forEach(function (f) {
        Object.defineProperty(book, f, {
          get: function () {
            var v = syCtx().bookInfo[f];
            var n = parseInt(v, 10);
            return isNaN(n) ? 0 : n;
          },
          set: function (v) {
            var s = String(parseInt(v, 10) || 0);
            syCtx().bookInfo[f] = s;
            syOp('bookField', f, s);
          },
        });
      });
  // E8：legado 布尔字段。
  ['canUpdate', 'reverseToc'].forEach(function (f) {
    Object.defineProperty(book, f, {
      get: function () {
        var v = syCtx().bookInfo[f];
        return v == null ? false : String(v) === 'true';
      },
      set: function (v) {
        var s = v ? 'true' : 'false';
        syCtx().bookInfo[f] = s;
        syOp('bookField', f, s);
      },
    });
  });
  // legado Book.type 是 Int（位掩码：4 视频 / 8 文本 / 32 音频 / 64 图片 /
  // 128 文件），脚本常做位比较；脚本也可写（`book.type = 8|128`）。
  Object.defineProperty(book, 'type', {
    get: function () {
      var v = syCtx().bookInfo.type;
      var n = parseInt(v, 10);
      return isNaN(n) ? 0 : n;
    },
    set: function (v) {
      var s = String(parseInt(v, 10) || 0);
      syCtx().bookInfo.type = s;
      syOp('bookField', 'type', s);
    },
  });
  // legado Book.durChapterIndex 也是 Int（阅读进度章序号）；规则里参与
  // 数值比较/拼接，按数字返回，缺省 0。durChapterTitle 按字符串字段处理
  // （见上方字段表）。E8：基准是实体字段，脚本可写（按章校正进度）。
  Object.defineProperty(book, 'durChapterIndex', {
    get: function () {
      var v = syCtx().bookInfo.durChapterIndex;
      var n = parseInt(v, 10);
      return isNaN(n) ? 0 : n;
    },
    set: function (v) {
      var s = String(parseInt(v, 10) || 0);
      syCtx().bookInfo.durChapterIndex = s;
      syOp('bookField', 'durChapterIndex', s);
    },
  });

  // legado AnalyzeRule.get(key)：特殊键 bookName/title 优先，其余按
  // chapter → book → ruleData → source.get(v_ 命名空间) 非空链取值。
  // 空值不短路（`takeIf { it.isNotEmpty() }`），后面的层仍可命中。
  function syRuleGet(k) {
    var key = String(k == null ? '' : k);
    if (key === 'bookName') {
      return String(book.name == null ? '' : book.name);
    }
    var ch = global.chapter;
    if (key === 'title' && ch != null) {
      return String(ch.title == null ? '' : ch.title);
    }
    if (ch != null && ch.variableMap && ch.variableMap[key] != null) {
      var cv = String(ch.variableMap[key]);
      if (cv !== '') return cv;
    }
    var bv = String(book.getVariable(key) || '');
    if (bv !== '') return bv;
    var rv = global.__javaVars;
    if (rv && rv[key] != null) {
      var s = String(rv[key]);
      if (s !== '') return s;
    }
    var sv = syCtx().sourceVars['__v:' + key];
    return sv == null ? '' : String(sv);
  }

  // legado CacheManager.getInt/getLong：String.toIntOrNull 口径（非整数值
  // 返回 null，而不是 0/截断）。
  function __cacheToInt(v) {
    if (v == null) return null;
    var s = String(v).trim();
    return /^-?\d+$/.test(s) ? parseInt(s, 10) : null;
  }
  // getDouble/getFloat：toDoubleOrNull 口径。
  function __cacheToDouble(v) {
    if (v == null) return null;
    var s = String(v).trim();
    if (s === '') return null;
    var n = Number(s);
    return isNaN(n) ? null : n;
  }
  var cache = {
    put: function (k, v, saveTime) {
      // legado `CacheManager.put(key, value: Any)`：byte[] 与 String 分表存储。
      // 二进制走独立的 base64 字节表（宿主 `cacheBytes`），文本表保持
      // Map<String,String> 契约不变。
      if (v != null && typeof v === 'object' && typeof v.length === 'number') {
        // Base64 编码器在第二段预置脚本里（`global.__syB64FromBytes`），
        // 跨作用域只能走全局；缺省时退化为不缓存（不能抛错中断脚本）。
        var enc = global.__syB64FromBytes;
        if (typeof enc !== 'function') return null;
        var raw = [];
        for (var bi = 0; bi < v.length; bi++) raw.push(v[bi] & 0xff);
        var b64 = enc(raw);
        var cb = syCtx().cacheBytes || (syCtx().cacheBytes = {});
        cb[String(k)] = b64;
        // 同键换类型：旧文本值必须同轮失效（legado 单表覆盖）。
        delete syCtx().cache[String(k)];
        syOp('cachePutBytes', k, b64);
        return null;
      }
      var s = String(v == null ? '' : v);
      syCtx().cache[String(k)] = s;
      if (syCtx().cacheBytes) delete syCtx().cacheBytes[String(k)];
      // 传字符串快照：宿主 cache 是 Map<String,String>，对象直传会在排空
      // 时类型失配；同时保证占位符守卫看到的就是最终缓存值。
      // saveTime 单位秒（legado CacheManager：0/缺省 = 永久）。
      syOp('cachePut', k, s, saveTime);
      return null;
    },
    get: function (k) {
      var v = syCtx().cache[String(k)];
      // legado CacheManager.get 返回 String?（缺省 null）：源脚本用
      // `obj === undefined` / `JSON.parse(cache.get(...))` 探测缓存，
      // 返回空串会让 JSON.parse('') 抛 SyntaxError 中断整个发现页脚本。
      // 字节条目在 legado 里是 ByteArray，`get` 取不到文本 → null。
      if (v == null) return null;
      return v;
    },
    // legado CacheManager 数值/内存族（内存层与磁盘层同源：本实现 put 后
    // 两处都写，数值 getter 直接按字符串解析，缺失/非数值返回 null）。
    getFromMemory: function (k) { return cache.getMemory(k); },
    getInt: function (k) { return __cacheToInt(cache.get(k)); },
    getLong: function (k) { return __cacheToInt(cache.get(k)); },
    getDouble: function (k) { return __cacheToDouble(cache.get(k)); },
    getFloat: function (k) { return __cacheToDouble(cache.get(k)); },
    // legado `CacheManager.getByteArray(key): ByteArray?`：命中返回字节副本
    // （有符号 byte[]，与 readFile/bodyAsBytes 同口径），否则 null。
    getByteArray: function (k) {
      var cb = syCtx().cacheBytes;
      var b64 = cb ? cb[String(k)] : null;
      if (b64 == null) return null;
      return syB64ToBytes(b64);
    },
    delete: function (k) {
      delete syCtx().cache[String(k)];
      var cb = syCtx().cacheBytes;
      if (cb) delete cb[String(k)];
      syOp('cacheDel', k, '');
      return null;
    },
    putMemory: function (k, v) { return cache.put(k, v); },
    getMemory: function (k) { return cache.get(k); },
    deleteMemory: function (k) { return cache.delete(k); },
    putFile: function (k, v, saveTime) { return cache.put(k, v, saveTime); },
    getFile: function (k) { return cache.get(k); },
  };

  // legado `source.key` 属性 = 书源 URL（脚本大量使用，只读）。
  // legado `BaseSource.getHeaderMap(userAgent, hasLoginHeader)`：源 header
  // + 登录头合并后的请求头表。脚本常用它基于源头做二次加工（签名头、
  // 覆盖 UA 再 post）。源 header 为 `@js:`/`<js>` 时交给宿主求值（走规则桥
  // 重放：首轮登记、下一轮拿到真值），不能再把脚本串当字面 JSON 解析。
  source.getHeaderMap = function () {
    var c = syCtx();
    var raw = String((c.sourceMeta && c.sourceMeta.header) || '');
    var out = {};
    var key = 'h|0|r0|' + raw;
    var cache = global.__javaRuleCache;
    var resolved = null;
    if (raw && cache && cache[key] !== undefined) {
      try {
        resolved = JSON.parse(String(cache[key]));
      } catch (e) {
        resolved = null;
      }
    }
    if (raw && resolved == null) {
      var seen = global.__javaRuleSeen;
      if (!seen) seen = global.__javaRuleSeen = Object.create(null);
      if (!seen[key]) {
        seen[key] = true;
        var pend = global.__javaRulePending;
        if (!pend) pend = global.__javaRulePending = [];
        pend.push({ op: 'get', k: 'h', r: raw, c: null, u: 0, key: key });
      }
      // 首轮占位：仍是字面 header（动态 header 由下一轮填充）。
      resolved = {};
      var literal = raw.trim();
      if (literal) {
        try {
          var o = JSON.parse(literal);
          if (o && typeof o === 'object') resolved = o;
        } catch (e) {}
      }
    }
    for (var k in resolved) out[k] = String(resolved[k]);
    for (var lk in c.loginHeader) out[lk] = c.loginHeader[lk];
    return out;
  };
  Object.defineProperty(source, 'key', {
    get: function () { return syCtx().sourceKey || syCtx().sourceId; },
  });
  // legado `source.<field>` 只读属性（脚本直接读源配置：书源备注里的共享
  // 签名代码、登录脚本源码、请求头等）。
  Object.defineProperty(source, 'bookSourceUrl', {
    get: function () { return syCtx().sourceKey || syCtx().sourceId; },
  });
  ['bookSourceName', 'bookSourceGroup', 'bookSourceComment', 'header',
   'loginUrl', 'jsLib',
   // E7：脚本高频读取的其余源字段（coverDecodeJs 封面解密、concurrentRate
   // 并发率、searchUrl/exploreUrl 规则、bookUrlPattern 详情判定、
   // bookSourceType 源类型、customOrder/weight 排序、lastUpdateTime）。
   'coverDecodeJs', 'concurrentRate', 'searchUrl', 'exploreUrl',
   'bookUrlPattern', 'ruleReview', 'customOrder', 'weight',
   'lastUpdateTime'].forEach(function (f) {
    // `configurable: true`：下面还有一轮数值字段（bookSourceType /
    // customOrder / weight / lastUpdateTime）会覆盖同名属性。缺省
    // configurable=false 时第二次 defineProperty 抛 TypeError，整段预置
    // 脚本中断 → java.ajax / global.source / global.book 全部不注入。
    Object.defineProperty(source, f, {
      configurable: true,
      get: function () {
        var m = syCtx().sourceMeta || {};
        return m[f] == null ? '' : String(m[f]);
      },
    });
  });
  ['bookSourceType', 'customOrder', 'lastUpdateTime', 'weight']
      .forEach(function (f) {
    Object.defineProperty(source, f, {
      configurable: true,
      get: function () {
        var m = syCtx().sourceMeta || {};
        var v = m[f];
        return v == null ? 0 : v;
      },
    });
  });

  global.cookie = cookie;
  global.source = source;
  global.book = book;
  global.cache = cache;
  // java 预置脚本（另一 IIFE）读取书源名的通道（toast 前缀/java.getTag）。
  global.__sySourceTag = function () { return source.getTag(); };

  // ── 家族式书源的顶层助手函数 ──
  // 这批书源的 jsLib 历史上在共享作用域里声明 put/login/name/n/k/l 等全局
  // 助手，loginUrl / exploreUrl 脚本直接调用（例如登录数据初始化 catch
  // 分支里的 put($$$)）。现行部分远端 jsLib 已不再声明这些助手，脚本在
  // 初始化处即抛 ReferenceError，源变量永不写入，发现页分类/选项解析为 0。
  // 仅在未定义时兜底；jsLib/脚本自带的同名声明（后加载）始终覆盖。
  if (typeof global.put === 'undefined') {
    global.put = function (data) {
      return global.source.setVariable(JSON.stringify(data, null, '\t'));
    };
  }
  if (typeof global.login === 'undefined') {
    global.login = function (e) {
      if (e === undefined) { return; }
      global.java.longToast(e);
    };
    // 标记为兜底实现：登录确认（legado confirm 的 `typeof login=='function'`
    // 判定）必须区分「源脚本真的声明了 login()」与「这里补的 toast 兜底」，
    // 否则未声明 login() 的源会被当成登录成功。
    global.login.__syFallback = true;
  }
  if (typeof global.name === 'undefined') {
    global.name = function (e) {
      if (typeof global.n !== 'function') { e = 0; }
      return String(global.x[e]) + ' ' + String(global.$$$.urls[e]);
    };
  }
  // n/k/l：生成 n 个换行 / 空格 / 空串（家族式源排版提示文案用）。
  if (typeof global.n === 'undefined') {
    global.n = function (e) {
      var s = '\n';
      for (var i = 1; i < e; i++) { s += '\n'; }
      return s;
    };
  }
  if (typeof global.k === 'undefined') {
    global.k = function (e) {
      var s = ' ';
      for (var i = 1; i < e; i++) { s += ' '; }
      return s;
    };
  }
  if (typeof global.l === 'undefined') {
    global.l = function (e) {
      var s = '';
      for (var i = 1; i < e; i++) { s += ''; }
      return s;
    };
  }

  // ── java.* 网络族（N 阶段确定性重放协议）——挂到 javaExtensions 预置的
  // java 对象上（本预置库后注入，syOp/syCtx 在本 IIFE 作用域内可用）。
  // 同步沙箱内无法真发请求：ajax 记录请求（op 'ajax' → 宿主 settle 循环
  // 抓取）并返回占位符 __AJAX_N__；宿主抓取后由 JsEngine 增量推送进
  // 全局 __ajaxCache，重放时缓存命中直出真响应。URL 为完整 AnalyzeUrl 串
  // （含 ,{options} 选项）时宿主按同口径解析执行。
  // 注意：缓存故意挂在 __shuyuanCtx 之外——ctx 每轮 eval 都重建，若缓存
  // 随 ctx 走，只能整表重灌（长目录 O(n²)）。
  global.__ajaxCache = global.__ajaxCache || Object.create(null);
  global.__ajaxBytesCache = global.__ajaxBytesCache || Object.create(null);
  global.__ajaxMetaCache = global.__ajaxMetaCache || Object.create(null);
  // base64 → 字节数组（有符号口径，与 java.base64DecodeToByteArray 一致）。
  var __syB64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  var __syB64Rev = Object.create(null);
  for (var __sbi = 0; __sbi < 64; __sbi++) __syB64Rev[__syB64.charAt(__sbi)] = __sbi;
  function syB64ToBytes(s) {
    var clean = String(s == null ? '' : s).replace(/[^A-Za-z0-9+/]/g, '');
    var out = [];
    var buf = 0, bits = 0;
    for (var i = 0; i < clean.length; i++) {
      buf = ((buf << 6) | __syB64Rev[clean.charAt(i)]) & 0xffffff;
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        var b = (buf >> bits) & 0xff;
        out.push(b > 127 ? b - 256 : b);
      }
    }
    return out;
  }
  global.__webviewCache = global.__webviewCache || Object.create(null);

  // ── 响应对象与请求头选项（legado StrResponse / Jsoup Response 口径） ──
  // 同步沙箱里响应元数据（状态码/响应头/最终 URL/Set-Cookie）只能由宿主
  // settle 抓取时记录、经 __ajaxMetaCache 增量重放。脚本侧的高频用法：
  // `java.post(url, body, head).header("Location")`（搜索 302 跳转）、
  // `java.post(...).cookies()`（登录 Set-Cookie）、
  // `java.connect(key).raw().request().url()`（重定向后基址发现）。
  function syMetaOf(key) {
    var m = global.__ajaxMetaCache && global.__ajaxMetaCache[key];
    if (m == null) return null;
    try { return typeof m === 'string' ? JSON.parse(m) : m; } catch (e) { return null; }
  }
  function syHeaderGet(headers, name) {
    if (!headers) return '';
    var lower = String(name == null ? '' : name).toLowerCase();
    for (var k in headers) {
      if (String(k).toLowerCase() !== lower) continue;
      var v = headers[k];
      if (v && typeof v === 'object' && v.length != null) {
        return v.length ? String(v[0]) : '';
      }
      return String(v);
    }
    return '';
  }
  // headers 入参归一：Map 对象或 JSON 字符串（legado connect 的 header 参数
  // 是字符串；社区源也有手写单引号伪 JSON，正则兜底取值）。
  function syParseHeaders(h) {
    if (h == null) return null;
    if (typeof h === 'string') {
      var s = h.trim();
      if (!s) return null;
      try {
        var o = JSON.parse(s);
        if (o && typeof o === 'object') return o;
      } catch (e) {}
      var out = {}, re = /([A-Za-z0-9_\-]+)\s*:\s*(?:'([^']*)'|"([^"]*)")/g, m;
      while ((m = re.exec(s))) out[m[1]] = m[2] != null ? m[2] : m[3];
      return Object.keys(out).length ? out : null;
    }
    if (typeof h === 'object') {
      var keys = Object.keys(h);
      if (!keys.length) return null;
      var copy = {};
      for (var i = 0; i < keys.length; i++) copy[keys[i]] = String(h[keys[i]]);
      return copy;
    }
    return null;
  }
  // 把 headers/额外选项合进 URL 的 `,{...}` 选项串（legado 语义：URL 选项
  // 里的 headers 在 connect 的 header 参数之后写入 → 选项优先）。
  function syWithHeaders(url, headers, extra) {
    var u = String(url == null ? '' : url);
    var h = syParseHeaders(headers);
    if (!h && !extra) return u;
    var optIdx = u.indexOf(',{');
    var opts = null;
    if (optIdx >= 0) {
      try { opts = JSON.parse(u.substring(optIdx + 1)); } catch (e) { opts = null; }
      if (!opts || typeof opts !== 'object') return u; // 选项串不规范：保持原样
    }
    if (!opts) opts = {};
    if (h) {
      var merged = {}, k;
      for (k in h) merged[k] = h[k];
      var oh = opts.headers;
      if (typeof oh === 'string') oh = syParseHeaders(oh);
      if (oh && typeof oh === 'object') {
        for (k in oh) merged[k] = String(oh[k]);
      }
      opts.headers = merged;
    }
    if (extra) {
      for (var ek in extra) opts[ek] = extra[ek];
    }
    var base = optIdx >= 0 ? u.substring(0, optIdx) : u;
    return base + ',' + JSON.stringify(opts);
  }
  // Jsoup/StrResponse 的 headers()：Map 形态 + Java Map 的 get()，
  // 多值头（set-cookie）取第一条。
  function syHeadersMap(headers) {
    var m = {};
    if (headers && typeof headers === 'object') {
      for (var k in headers) {
        var v = headers[k];
        if (v && typeof v === 'object' && v.length != null) {
          m[k] = v.length ? String(v[0]) : '';
        } else {
          m[k] = String(v);
        }
      }
    }
    Object.defineProperty(m, 'get', {
      value: function (name) { return syHeaderGet(headers, name); },
      enumerable: false,
    });
    return m;
  }
  // Jsoup Response.cookies()：返回 Java Map 形态（脚本普遍 `String(ck)` 后
  // 用正则取 `{a=b, c=d}`），同时提供 get()。
  function syCookiesOf(headers) {
    var m = {};
    var list = headers && (headers['set-cookie'] || headers['Set-Cookie']);
    if (typeof list === 'string') list = [list];
    if (list && list.length != null) {
      for (var i = 0; i < list.length; i++) {
        var seg = String(list[i]).split(';')[0];
        var eq = seg.indexOf('=');
        if (eq > 0) m[seg.substring(0, eq).trim()] = seg.substring(eq + 1).trim();
      }
    }
    Object.defineProperty(m, 'get', {
      value: function (name) {
        if (m[name] != null) return m[name];
        var lower = String(name).toLowerCase();
        for (var kk in m) if (kk.toLowerCase() === lower) return m[kk];
        return null;
      },
      enumerable: false,
    });
    Object.defineProperty(m, 'toString', {
      value: function () {
        var parts = [];
        for (var kk in m) parts.push(kk + '=' + m[kk]);
        return '{' + parts.join(', ') + '}';
      },
      enumerable: false,
    });
    return m;
  }
  function syMethodOf(key) {
    var i = key.indexOf(',{');
    if (i >= 0) {
      try {
        var o = JSON.parse(key.substring(i + 1));
        if (o && o.method) return String(o.method).toUpperCase();
      } catch (e) {}
    }
    return key.indexOf('||POST||') >= 0 ? 'POST' : 'GET';
  }
  // StrResponse.body 在 legado 是 String（属性 + body() 方法双形态都可用）。
  // 用「可调用值 + 绑定 String.prototype 方法 + length 属性」模拟：
  // `res.body`、`String(res.body)`、`res.body()`、`res.body.substring(1)`、
  // `res.body.length` 全部可用。
  function syStringCallable(text) {
    var t = text == null ? '' : String(text);
    var f = function () { return t; };
    f.toString = f.valueOf = function () { return t; };
    try {
      var names = Object.getOwnPropertyNames(String.prototype);
      for (var i = 0; i < names.length; i++) {
        var k = names[i];
        if (k === 'constructor') continue;
        try {
          var d = Object.getOwnPropertyDescriptor(String.prototype, k);
          if (d && typeof d.value === 'function') f[k] = d.value.bind(t);
        } catch (e) {}
      }
      Object.defineProperty(f, 'length', { value: t.length });
    } catch (e) {}
    return f;
  }
  // java.connect/get/post/head 的统一返回对象：StrResponse 与 Jsoup Response
  // 的超集（body()/code()/headers()/header()/cookies()/url()/raw()…）。
  function syResp(key, bodyText) {
    var meta = syMetaOf(key);
    var code = meta && meta.code != null ? Number(meta.code)
      : (bodyText ? 200 : 0);
    var finalUrl = meta && meta.url ? String(meta.url) : '';
    var headers = (meta && meta.headers) || {};
    var resp = {
      body: syStringCallable(bodyText),
      bodyAsBytes: function () {
        var c = global.__ajaxBytesCache;
        var b64 = c && c[key];
        if (b64 == null) {
          syOp('ajaxBytes', key, '');
          return [];
        }
        return syB64ToBytes(b64);
      },
      code: function () { return code; },
      statusCode: function () { return code; },
      message: function () { return code >= 200 && code < 300 ? 'OK' : String(code); },
      statusMessage: function () { return code >= 200 && code < 300 ? 'OK' : ''; },
      headers: function () { return syHeadersMap(headers); },
      header: function (name) { return syHeaderGet(headers, name); },
      cookies: function () { return syCookiesOf(headers); },
      url: function () { return finalUrl; },
      // Jsoup Response 形态：连接响应可直接 .parse()/.get() 得到 Document
      // （`Jsoup.connect(url).get().select(...)` 与 `java.get(url).parse()`）。
      parse: function () {
        var J = global.org && global.org.jsoup && global.org.jsoup.Jsoup;
        if (!J || typeof J.parse !== "function") {
          throw new Error('org.jsoup.Jsoup.parse 未注入');
        }
        return J.parse(String(bodyText), finalUrl);
      },
      get: function () { return resp.parse(); },
      isSuccessful: function () { return code >= 200 && code < 300; },
      method: function () { return syMethodOf(key); },
      charset: function () { return 'UTF-8'; },
      contentType: function () { return syHeaderGet(headers, 'content-type'); },
      raw: function () {
        return {
          request: function () {
            return { url: function () { return finalUrl; } };
          },
          code: function () { return code; },
          headers: function () { return syHeadersMap(headers); },
        };
      },
    };
    return resp;
  }
  // 交互式重放的响应对象：与 syResp 同形，供 startBrowserAwait 返回。
  function syAwaitResp(body, code, finalUrl, headers) {
    var text = body == null ? '' : String(body);
    var h = headers || {};
    return {
      body: syStringCallable(text),
      code: function () { return Number(code) || 0; },
      statusCode: function () { return Number(code) || 0; },
      headers: function () { return syHeadersMap(h); },
      header: function (n) { return syHeaderGet(h, n); },
      cookies: function () { return syCookiesOf(h); },
      url: function () { return finalUrl == null ? '' : String(finalUrl); },
      toString: function () { return text; },
    };
  }

  if (global.java) {
    // legado 的 `java` 有两种绑定：规则求值期是 AnalyzeRule（get/put 变量
    // 语义），登录/初始化脚本里是 BaseSource 本身（getKey/getVariable/
    // getLoginHeader…）。沙箱共用一套 java 对象：把 BaseSource 面挂上来，
    // 两类脚本都能跑。同名方法保留 AnalyzeRule 版（get/put 见分派）。
    ['getKey', 'getTag', 'getVariable', 'putVariable', 'setVariable',
     'getLoginInfo', 'getLoginInfoMap', 'putLoginInfo', 'removeLoginInfo',
     'getLoginHeader', 'getLoginHeaderMap', 'putLoginHeader',
     'removeLoginHeader', 'refreshJSLib', 'refreshBookUrl',
     'putConcurrent'].forEach(function (n) {
      if (typeof global.java[n] !== 'function') {
        global.java[n] = function () {
          return global.source[n].apply(global.source, arguments);
        };
      }
    });
    global.java.getSource = function () { return global.source; };
    // 确定性重放的会话语义：legado 桥同步执行，同一脚本内对同一 URL 的
    // 多次 java.ajax 是多次真实请求。这里按「每次顶层求值内的同键调用
    // 序号」拆键：第 1 次用原始键、第 n 次追加 `||DUP||n`，宿主 settle
    // 对每个键各抓一次；重放轮计数器复位 → 同脚本仍生成同一组键命中缓存。
    global.java.__ajaxReq = function (url, timeoutMs, batch, skipRateLimit) {
      var raw = String(url == null ? '' : url);
      var seq = global.__ajaxCallSeq;
      if (!seq) seq = global.__ajaxCallSeq = Object.create(null);
      var n = (seq[raw] || 0) + 1;
      seq[raw] = n;
      var key = n === 1 ? raw : raw + '||DUP||' + n;
      var c = global.__ajaxCache;
      if (c && c[key] != null) {
        return c[key];
      }
      // legado ajax/connect 的 callTimeout（毫秒）：随请求键记入 op，宿主
      // settle 时按该键的超时发起真实请求（缺省用宿主默认）。
      var to = (timeoutMs === undefined || timeoutMs === null)
        ? '' : String(timeoutMs);
      // 批请求标记随 op 透传给宿主 settle：`b`=批（并发抓取，保序），
      // `b1`=批且跳过 concurrentRate 限流（legado ajaxAll 的
      // `getStrResponseAwait(skipRateLimit = true)`），`s`=串行（普通
      // java.ajax/get/post/head/connect：legado 每次调用阻塞完成后才继续，
      // 后一个请求依赖前一个写入的 cookie/token，不能并发）。
      syOp('ajax', key, to,
          batch ? (skipRateLimit ? 'b1' : 'b') : 's');
      global.__ajaxN = (global.__ajaxN || 0) + 1;
      return '__AJAX_' + global.__ajaxN + '__';
    };
    global.java.ajax = function (url, callTimeout) {
      // legado `JsExtensions.ajax` 是同步阻塞调用，脚本内的多次 ajax 严格
      // 串行；只有显式 ajaxAll 才并发（batch=true）。
      return global.java.__ajaxReq(url, callTimeout, false);
    };
    global.java.ajaxAll = function (urlList, skipRateLimit) {
      var arr = urlList;
      if (typeof urlList === 'string') arr = [urlList];
      var out = [];
      for (var i = 0; arr && i < arr.length; i++) {
        out.push(syResp(arr[i],
            global.java.__ajaxReq(arr[i], undefined, true, skipRateLimit)));
      }
      return out;
    };
    global.java.connect = function (urlStr, header, callTimeout) {
      // legado JsExtensions.connect(url, header)：headerMapF 整体替换请求头。
      // 仅在 header 解析成功时进入替换模式（解析失败仍回退源 header）。
      var h = syParseHeaders(header);
      var key = syWithHeaders(urlStr, header,
          h ? { _syHeaderMode: 'replace' } : null);
      return syResp(key, global.java.__ajaxReq(key, callTimeout));
    };
    // get 分派（legado 两个重载）：
    // - 2 参及以上 → HTTP GET（JsExtensions.get(url, headers)，Jsoup 口径：
    //   不跟随重定向、headers 是 Map，timeout 缺省 30000ms）；
    // - 1 参 → **AnalyzeRule 变量链优先**（bookName/title 特殊键 +
    //   chapter → book → ruleData → source.put 命名空间），链路全空且
    //   形如 URL 才发请求。变量优先很关键：`java.get('bookUrl')` 的值
    //   本身就是 URL，按「看起来像 URL 就发请求」会把它误当接口。
    global.java.get = function (a, b, c) {
      if (arguments.length >= 2) {
        var key = syWithHeaders(a, b,
            { followRedirects: false, _syHeaderMode: 'replace' });
        var to = (c === undefined || c === null) ? 30000 : c;
        return syResp(key, global.java.__ajaxReq(key, to));
      }
      var s = String(a == null ? '' : a);
      var v = syRuleGet(s);
      if (v !== '') return v;
      if (/^https?:\/\//i.test(s)) {
        var key2 = syWithHeaders(s, null,
            { followRedirects: false, _syHeaderMode: 'replace' });
        return syResp(key2, global.java.__ajaxReq(key2));
      }
      return '';
    };
    // POST 记录组合键 url||POST||body（宿主 settle 拆分后组装选项串；
    // 选项串在标记之前，headers/followRedirects 随 URL 一起保留）。
    // legado Jsoup requestBody 语义：body 原样字节发送，不做表单重编码、
    // 不自动补 Content-Type；空 body 也是 POST，不降级为 GET。
    global.java.post = function (urlStr, bodyStr, headers, timeout) {
      var keyUrl = syWithHeaders(urlStr, headers,
          { followRedirects: false, _syHeaderMode: 'replace', _syRawBody: true });
      var b = bodyStr == null ? '' : String(bodyStr);
      var key = keyUrl + '||POST||' + b;
      var to = (timeout === undefined || timeout === null) ? 30000 : timeout;
      return syResp(key, global.java.__ajaxReq(key, to));
    };
    global.java.head = function (urlStr, headers, timeout) {
      var key = syWithHeaders(urlStr, headers,
          { followRedirects: false, method: 'HEAD', _syHeaderMode: 'replace' });
      var to = (timeout === undefined || timeout === null) ? 30000 : timeout;
      return syResp(key, global.java.__ajaxReq(key, to));
    };
    // legado JsExtensions.importScript：取远端/本地脚本文本（远程 jsLib 里的
    // Reload 等助手靠它加载发现页规则）。沿用 ajax 确定性重放：首轮返回
    // 占位符，宿主 settle 抓取后重放得到脚本正文。
    // 空内容必须抛错（legado "内容获取失败或者为空"）：返回空串会让
    // `eval(String(Reload(...)))` 变成 eval("") 的“成功空结果”，发现页被
    // 误判为无分类并持久缓存，网络抖动一次即永久失效。
    global.java.importScript = function (path) {
      var key = String(path == null ? '' : path);
      // legado：http(s) 走 cacheFile（网络重放），其余按私有数据目录相对
      // 路径读虚拟文本表。
      var body;
      if (/^https?:\/\//i.test(key)) {
        body = String(global.java.readTxtFile(global.java.cacheFile(key)));
      } else {
        body = String(global.java.readTxtFile(key));
      }
      if (!body || !body.trim()) {
        throw new Error(key + ' 内容获取失败或者为空');
      }
      return body;
    };
    global.java.getStrResponse = function (urlStr) {
      return global.java.connect(urlStr);
    };
    // ── org.jsoup.Jsoup（legado 脚本直接调 Java 库的高频写法） ──
    // 只实现书源里实际用到的 connect 链：ignoreContentType/ignoreHttpErrors/
    // timeout/header(s)/cookie/userAgent/referrer/method/data 全部返回自身，
    // execute() 经 __ajaxReq 走与 java.ajax 相同的确定性重放（POST 用
    // `url||POST||body` 组合键，settle 拆分后发起真实表单请求）。
    // bodyAsBytes() 走二进制重放 __ajaxBytesCache（base64），避免密文被
    // 文本解码破坏；首轮返回空数组并记录待抓取。
    global.org = {
      jsoup: {
        Jsoup: {
          connect: function (url) {
            var u = String(url == null ? '' : url);
            var req = {
              _headers: Object.create(null),
              _data: [],
              _method: '',
              _url: u,
              ignoreContentType: function () { return req; },
              ignoreHttpErrors: function () { return req; },
              validateTLSCertificates: function () { return req; },
              followRedirects: function () { return req; },
              maxBodySize: function () { return req; },
              timeout: function () { return req; },
              postDataCharset: function () { return req; },
              parser: function () { return req; },
              header: function (k, v) { req._headers[String(k)] = String(v); return req; },
              headers: function (m) {
                if (m && typeof m === 'object') {
                  for (var k in m) req._headers[String(k)] = String(m[k]);
                }
                return req;
              },
              cookie: function (k, v) {
                var prev = req._headers['Cookie'];
                req._headers['Cookie'] = (prev ? prev + '; ' : '') + k + '=' + v;
                return req;
              },
              userAgent: function (v) { req._headers['User-Agent'] = String(v); return req; },
              referrer: function (v) { req._headers['Referer'] = String(v); return req; },
              method: function (m) { req._method = String(m || '').toUpperCase(); return req; },
              data: function (a, b) {
                if (a && typeof a === 'object') {
                  for (var k in a) req._data.push(k + '=' + a[k]);
                } else {
                  req._data.push(String(a) + '=' + String(b));
                }
                return req;
              },
              execute: function () {
                var opts = Object.create(null);
                var hasHeaders = false;
                for (var hk in req._headers) { hasHeaders = true; break; }
                if (hasHeaders) opts.headers = req._headers;
                var isPost = req._method === 'POST' || req._data.length > 0;
                var form = req._data.join('&');
                if (isPost && !form) opts.method = 'POST';
                // legado Jsoup 直连只发显式设置的头（不叠加源 header/默认头）。
                opts._syHeaderMode = 'replace';
                var finalUrl = syWithHeaders(req._url, null, opts);
                var key = isPost && form
                    ? finalUrl + '||POST||' + form
                    : finalUrl;
                return syResp(key, global.java.__ajaxReq(key));
              },
              // jsoup Connection 的快捷方法：执行后直接把响应体解析成
              // Document（`Jsoup.connect(url).get().select(...)`）。
              get: function () { return req.execute().parse(); },
              post: function () { return req.execute().parse(); },
            };
            return req;
          },
        },
      },
    };
    if (global.__syOrgJson) global.org.json = global.__syOrgJson;
    // java.webView 家族（legado JsExtensions.webView / webViewGetSource /
    // webViewGetOverrideUrl）：无头 WebView 加载页面 / 注入 html、执行 js
    // 后返回结果。同步沙箱内不能真开 WebView，故与 ajax 同款重放：
    // 首轮记录 op 返回占位符，宿主 settle 抓取后写入 __webviewCache，重放命中。
    // sourceRegex（资源 URL 嗅探）与 overrideUrlRegex（跳转 URL 拦截）由宿主
    // 在 settleWebview 里分别按 args[5]/args[6] 解读；cacheFirst 是 legado 的
    // Android WebView cacheMode 开关，重放宿主无缓存层，接受但不参与。
    function syWebviewReplay(prefix, html, url, js, delayTime, sourceRegex,
        overrideUrlRegex, sp, op, cacheFirst) {
      var h = html == null ? '' : String(html);
      var u = url == null ? '' : String(url);
      var j = js == null ? '' : String(js);
      var src = sourceRegex == null ? '' : String(sourceRegex);
      var ovr = overrideUrlRegex == null ? '' : String(overrideUrlRegex);
      var delay = parseInt(delayTime, 10);
      if (!(delay > 0)) delay = 0;
      if (!h && !u) return '';
      // 键用内容哈希：html/js 可能很长，不能直接当键存放/传输。嗅探正则
      // 参与键，避免同页面不同嗅探目标（或与整页 HTML 结果）互相命中。
      // delayTime/cacheFirst 同样影响 WebView 实际返回（等待时长、缓存
      // 策略），必须进键，否则参数不同的调用会互相命中旧结果。
      var cf = cacheFirst ? 1 : 0;
      var sig = h + '\u0001' + u + '\u0001' + j + '\u0001' +
          src + '\u0001' + ovr + '\u0001' + String(delay) + '\u0001' + cf;
      var key = prefix + syHash(sig) + ':' + sig.length;
      var c = global.__webviewCache;
      if (c && c[key] != null) return c[key];
      syOp('webview', key, JSON.stringify(
          [h, u, j, String(delay), '', src, ovr]));
      global.__wvN = (global.__wvN || 0) + 1;
      return sp + (global.__wvN) + op;
    }
    global.java.webView = function (html, url, js) {
      return syWebviewReplay('wv:', html, url, js, 0, '', '', '__WEBVIEW_', '__', false);
    };
    // webViewGetSource(html, url, js, sourceRegex, cacheFirst, delayTime)：
    // 返回 WebView 内嗅探到的资源 URL（如视频真实地址）。
    global.java.webViewGetSource = function (html, url, js, sourceRegex,
        cacheFirst, delayTime) {
      return syWebviewReplay('wvs:', html, url, js, delayTime, sourceRegex,
          '', '__WEBVIEW_SRC_', '__', cacheFirst);
    };
    // webViewGetOverrideUrl(html, url, js, overrideUrlRegex, cacheFirst, delayTime)：
    // 返回被 shouldOverrideUrlLoading 拦截的跳转 URL。
    global.java.webViewGetOverrideUrl = function (html, url, js,
        overrideUrlRegex, cacheFirst, delayTime) {
      return syWebviewReplay('wvo:', html, url, js, delayTime, '',
          overrideUrlRegex, '__WEBVIEW_OVR_', '__', cacheFirst);
    };
    // java.getReadBookConfig()/getThemeConfig()：legado 返回当前阅读/主题
    // 配置的 GSON JSON 串。宿主未注入实时配置（E9 能力面）时返回 legado
    // 默认值（day 主题 + 默认排版），保证调用方 JSON.parse 后字段齐全、
    // 不会因函数缺失整段规则失败。
    global.java.getReadBookConfig = function () {
      var cfg = {
        name: '默认',
        bgStr: '#EEEEEE',
        bgStrNight: '#000000',
        bgStrEInk: '#FFFFFF',
        bgAlpha: 100,
        bgType: 0,
        bgTypeNight: 0,
        bgTypeEInk: 0,
        textFont: '',
        titleFont: '',
        headerFont: '',
        footerFont: '',
        headerFontSize: 12,
        footerFontSize: 12,
        applyHeaderStyle: true,
        textBold: 500,
        textSize: 20,
        textItalic: false,
        textShadow: false,
        shadowRadius: 16,
        shadowDx: 1,
        shadowDy: 1,
        letterSpacing: 0.1,
        lineSpacingExtra: 12,
        paragraphSpacing: 2,
        paragraphIndent: '\u3000\u3000',
        titleMode: 0,
        titleSize: 4,
        titleSizeRelative: null,
        titleTopSpacing: 0,
        titleBottomSpacing: 0,
        titleBold: 500,
        titleLineSpacingExtra: 12,
        titleLineSpacingSub: 12,
        titleSegType: 0,
        titleSegScaling: 1,
        titleSegDistance: 4,
        titleSegFlag: '',
        underline: false,
        underlinePadding: 10,
        underlineHeight: 1,
        underlineExtend: false,
        underlineColor: '#3E3D3B',
        underlineColorNight: '#ADADAD',
        dottedLine: false,
        dottedBase: 6,
        dottedRatio: 6,
        paddingBottom: 6,
        paddingLeft: 16,
        paddingRight: 16,
        paddingTop: 6,
        showHeaderLine: false,
        showFooterLine: true,
        pageAnim: 0,
        pageAnimSpeed: 2,
        textColor: '#3E3D3B',
        textColorNight: '#ADADAD',
        textColorEInk: '#000000',
        textAccentColor: '#834E00',
        textAccentColorNight: '#FE4D55',
        textAccentColorEInk: '#000000'
      };
      // 宿主可经 ShuyuanSourceContext.readConfigJson 注入实时排版配置
      //（阅读器偏好经 ReaderConfigBridge 写入）。注入值是「部分字段」：
      // 逐键覆盖到上面的 legado 默认配置上，脚本 JSON.parse 后字段仍齐全。
      var injected = syCtx().readConfigJson;
      if (injected) {
        try {
          var o = JSON.parse(String(injected));
          if (o && typeof o === 'object') {
            for (var k in o) cfg[k] = o[k];
          }
        } catch (e) {}
      }
      return JSON.stringify(cfg);
    };
    global.java.getReadBookConfigMap = function () {
      try {
        return JSON.parse(global.java.getReadBookConfig());
      } catch (e) {
        return {};
      }
    };
    global.java.getThemeConfig = function () {
      var cfg = {
        themeName: 'MD3-Day',
        isNightTheme: false,
        primaryColor: '#795548',
        accentColor: '#E53935',
        backgroundColor: '#F5F5F5',
        bottomBackground: '#EEEEEE',
        backgroundImgPath: null,
        backgroundImgBlur: 0
      };
      var injected = syCtx().themeConfigJson;
      if (injected) {
        try {
          var o = JSON.parse(String(injected));
          if (o && typeof o === 'object') {
            for (var k in o) cfg[k] = o[k];
          }
        } catch (e) {}
      }
      return JSON.stringify(cfg);
    };
    global.java.getThemeConfigMap = function () {
      try {
        return JSON.parse(global.java.getThemeConfig());
      } catch (e) {
        return {};
      }
    };
    // legado getThemeMode：dy/day/night/eInk 模式名。宿主未注入时按默认
    // day 主题返回（与 getThemeConfig 的 isNightTheme=false 一致）。
    global.java.getThemeMode = function () {
      var m = syCtx().themeMode;
      return m == null || m === '' ? 'day' : String(m);
    };
    // ── 文件/归档族（legado JsExtensions）──
    // 同步沙箱没有真实磁盘：虚拟文件系统 = 文本表 __cacheFiles（path→text）
    // + 字节表 __fsBytes（path→base64）。网络字节沿用 __ajaxBytesCache 的
    // 确定性重放；解压/包内取条目/文本解码经宿主 settle（__fileOpCache，
    // 键=运算描述，结果下轮直接命中，纯本地不占网络预算）。
    global.__cacheFiles = global.__cacheFiles || Object.create(null);
    global.__fsBytes = global.__fsBytes || Object.create(null);
    global.__fileOpCache = global.__fileOpCache || Object.create(null);
    // cacheFile(url) + readTxtFile(path)：脚本注入的常用组合
    // （`eval(java.cacheFile('https://x/sign.js'))`）。内容走 __ajaxReq
    // 的确定性重放，按「虚拟路径」存文本表。
    global.java.cacheFile = function (url, saveTime) {
      var u = String(url == null ? '' : url);
      if (!u) return '';
      // 先把 url 喂给 __ajaxReq：命中缓存返回真内容，未命中记录请求返回占位。
      var content = global.java.__ajaxReq(u);
      var path = 'shuyuan_cache:' + syHash(u) + ':' + u.length;
      global.__cacheFiles[path] = content;
      return path;
    };

    function syMd5Hex16(s) {
      // 实现挂在 javaExtensions 预置（另一 IIFE）的 global 工具上。
      return global.__syMd5Hex16(String(s));
    }
    // legado downloadFile 路径后缀：AnalyzeUrl 选项里的 type，否则 URL 后缀。
    function syUrlSuffix(url) {
      var u = String(url == null ? '' : url);
      var optIdx = u.indexOf(',{');
      if (optIdx >= 0) {
        try {
          var o = JSON.parse(u.substring(optIdx + 1));
          if (o && typeof o.type === 'string' && o.type) {
            var t = String(o.type).replace(/[^A-Za-z0-9]/g, '');
            if (t) return t;
          }
        } catch (e) {}
        u = u.substring(0, optIdx);
      }
      u = u.split('#')[0].split('?')[0];
      var slash = u.lastIndexOf('/');
      var name = slash >= 0 ? u.substring(slash + 1) : u;
      var dot = name.lastIndexOf('.');
      if (dot < 0 || dot === name.length - 1) return 'bin';
      return name.substring(dot + 1).replace(/[^A-Za-z0-9]/g, '') || 'bin';
    }
    // 字节文件按需解码：命中 __cacheFiles 直接返回；否则以内容哈希为键
    // 登记宿主解码（严格 UTF-8 → GBK 回落），结果缓存进虚拟文本表。
    function syFsText(path) {
      var files = global.__cacheFiles;
      if (files[path] != null) return files[path];
      var b64 = global.__fsBytes[path];
      if (b64 == null) return null;
      var key = 'tx:' + syMd5Hex16(b64) + '|';
      var cache = global.__fileOpCache;
      var r = cache && cache[key];
      if (r != null) {
        try {
          var o = JSON.parse(r);
          if (o && typeof o.t === 'string') {
            files[path] = o.t;
            return o.t;
          }
        } catch (e) {}
        return '';
      }
      syOp('fileOp', key, JSON.stringify([b64, '']));
      return '';
    }
    function syUnarchive(zipPath) {
      var p = String(zipPath == null ? '' : zipPath);
      if (!p) return '';
      var name = p.substring(p.lastIndexOf('/') + 1);
      var folder = 'ArchiveTemp/' + syMd5Hex16(name);
      var b64 = global.__fsBytes[p];
      if (b64 == null) return folder;
      var opKey = 'uz:' + folder + ':' + syMd5Hex16(b64);
      var cache = global.__fileOpCache;
      var r = cache && cache[opKey];
      if (r != null) {
        try {
          var entries = JSON.parse(r);
          for (var n in entries) {
            var e = entries[n] || {};
            var child = folder + '/' + n;
            if (e.b != null) global.__fsBytes[child] = e.b;
            if (e.t != null) global.__cacheFiles[child] = e.t;
          }
        } catch (err) {}
        return folder;
      }
      syOp('fileOp', opKey, JSON.stringify([b64]));
      return folder;
    }
    // legado DownloadFile：返回虚拟相对路径；字节未落表时先登记二进制重放
    // （占位轮返回路径，下一轮重放命中后 downloadFile/unzipFile 再取到内容）。
    global.java.downloadFile = function (a, b) {
      if (b != null) {
        // 已废弃的 downloadFile(hexContent, url)：内容即完整 hex 字节。
        var url = String(b == null ? '' : b);
        var path = 'shuyuan_cache/' + syMd5Hex16(url) + '.' + syUrlSuffix(url);
        global.__fsBytes[path] = global.__syB64FromBytes(
            global.__syHexToBytes(String(a == null ? '' : a))
                .map(function (x) { return x & 0xff; }));
        return path;
      }
      var u = String(a == null ? '' : a);
      if (!u) return '';
      var p = 'shuyuan_cache/' + syMd5Hex16(u) + '.' + syUrlSuffix(u);
      var cached = global.__ajaxBytesCache && global.__ajaxBytesCache[u];
      if (cached != null) {
        global.__fsBytes[p] = cached;
        return p;
      }
      syOp('ajaxBytes', u, '');
      return p;
    };
    global.java.readFile = function (path) {
      var b64 = global.__fsBytes[String(path == null ? '' : path)];
      if (b64 == null) return null;
      return syB64ToBytes(b64);
    };
    global.java.readTxtFile = function (path, charsetName) {
      var p = String(path == null ? '' : path);
      if (!p) return '';
      // 传入 URL 而非路径时先缓存再读（legado 同样接受 URL）。
      if (/^https?:\/\//i.test(p)) p = global.java.cacheFile(p);
      var cs = charsetName == null ? '' : String(charsetName);
      var files = global.__cacheFiles;
      if (files[p] != null) return files[p];
      var b64 = global.__fsBytes[p];
      if (b64 == null) return '';
      var key = 'tx:' + syMd5Hex16(b64 + '|' + cs) + '|' + cs;
      var cache = global.__fileOpCache;
      var r = cache && cache[key];
      if (r != null) {
        try {
          var o = JSON.parse(r);
          if (o && typeof o.t === 'string') {
            if (!cs) files[p] = o.t;
            return o.t;
          }
        } catch (e) {}
        return '';
      }
      syOp('fileOp', key, JSON.stringify([b64, cs]));
      return '';
    };
    global.java.deleteFile = function (path) {
      var p = String(path == null ? '' : path);
      if (!p) return false;
      var hit = false;
      var maps = [global.__fsBytes, global.__cacheFiles];
      for (var mi = 0; mi < maps.length; mi++) {
        var m = maps[mi];
        if (!m) continue;
        var keys = Object.keys(m);
        for (var i = 0; i < keys.length; i++) {
          var k = keys[i];
          if (k === p || k.indexOf(p + '/') === 0) {
            delete m[k];
            hit = true;
          }
        }
      }
      return hit;
    };
    global.java.unzipFile = function (p) { return syUnarchive(p); };
    global.java.unrarFile = function (p) { return syUnarchive(p); };
    global.java.un7zFile = function (p) { return syUnarchive(p); };
    // legado getTxtInFolder：逐文件读文本、换行连接，随后删除整个目录。
    global.java.getTxtInFolder = function (path) {
      var p = String(path == null ? '' : path);
      if (!p) return '';
      var prefix = p.replace(/\/+$/, '') + '/';
      var parts = [];
      var seen = Object.create(null);
      var maps = [global.__cacheFiles, global.__fsBytes];
      for (var mi = 0; mi < maps.length; mi++) {
        var m = maps[mi];
        if (!m) continue;
        var keys = Object.keys(m);
        for (var i = 0; i < keys.length; i++) {
          var k = keys[i];
          if (seen[k] || k.indexOf(prefix) !== 0) continue;
          seen[k] = true;
          if (mi === 0) {
            parts.push(m[k]);
          } else {
            var t = syFsText(k);
            parts.push(t == null ? '' : t);
          }
        }
      }
      global.java.deleteFile(p);
      return parts.join('\n');
    };
    // legado getZipStringContent：url 支持绝对 URL（二进制重放）或 hex 串，
    // 返回包内指定路径文件的文本（未命中返回空串）。
    global.java.getZipStringContent = function (url, entry, charsetName) {
      var u = String(url == null ? '' : url);
      var e = String(entry == null ? '' : entry);
      if (!e) return '';
      var cs = charsetName == null ? '' : String(charsetName);
      var b64 = null;
      if (/^https?:\/\//i.test(u)) {
        b64 = global.__ajaxBytesCache && global.__ajaxBytesCache[u];
        if (b64 == null) {
          syOp('ajaxBytes', u, '');
          return '';
        }
      } else {
        var bytes = global.__syHexToBytes(u);
        if (!bytes.length) return '';
        b64 = global.__syB64FromBytes(bytes.map(function (x) { return x & 0xff; }));
      }
      var key = 'zc:' + syMd5Hex16(b64) + ':' + e + '|' + cs;
      var cache = global.__fileOpCache;
      var r = cache && cache[key];
      if (r != null) {
        try {
          var o = JSON.parse(r);
          if (o && typeof o.t === 'string') return o.t;
        } catch (err) {}
        return '';
      }
      syOp('fileOp', key, JSON.stringify([b64, e, cs]));
      return '';
    };
    // legado getZipByteArrayContent：同上的「包内取条目」，返回字节数组
    // （有符号口径，与 java.base64DecodeToByteArray 一致）。未命中返回空数组。
    global.java.getZipByteArrayContent = function (url, entry) {
      var u = String(url == null ? '' : url);
      var e = String(entry == null ? '' : entry);
      if (!e) return [];
      var b64 = null;
      if (/^https?:\/\//i.test(u)) {
        b64 = global.__ajaxBytesCache && global.__ajaxBytesCache[u];
        if (b64 == null) {
          syOp('ajaxBytes', u, '');
          return [];
        }
      } else {
        var bytes = global.__syHexToBytes(u);
        if (!bytes.length) return [];
        b64 = global.__syB64FromBytes(bytes.map(function (x) { return x & 0xff; }));
      }
      var key = 'zc:' + syMd5Hex16(b64) + ':' + e + '|';
      var cache = global.__fileOpCache;
      var r = cache && cache[key];
      if (r != null) {
        try {
          var o = JSON.parse(r);
          if (o && typeof o.b === 'string') return syB64ToBytes(o.b);
        } catch (err) {}
        return [];
      }
      syOp('fileOp', key, JSON.stringify([b64, e, '']));
      return [];
    };
    // legado RAR/7z 取条目族：宿主解包器只支持 zip，签名保留（脚本调用不再
    // 抛 TypeError），实际走同一「zip 条目」通道；不支持的格式返回空，
    // 与宿主解包失败同口径（legado 抛异常由脚本 try/catch 吞掉）。
    global.java.getRarByteArrayContent = function (url, entry) {
      return global.java.getZipByteArrayContent(url, entry);
    };
    global.java.getRarStringContent = function (url, entry, charsetName) {
      return global.java.getZipStringContent(url, entry, charsetName);
    };
    global.java.get7zByteArrayContent = function (url, entry) {
      return global.java.getZipByteArrayContent(url, entry);
    };
    global.java.get7zStringContent = function (url, entry, charsetName) {
      return global.java.getZipStringContent(url, entry, charsetName);
    };
    // legado unArchiveFile(path)：通用解包入口（按扩展名分派到对应解包器）。
    global.java.unArchiveFile = function (p) { return syUnarchive(p); };
    // legado queryBase64TTF(base64)：Base64 字体直接建字体对象（queryTTF
    // 已支持 base64 输入，等同转发）。
    global.java.queryBase64TTF = function (b64) {
      return global.java.queryTTF(b64, true);
    };
    // ── UI 操作族（发现页选项 action / 登录脚本） ──
    // legado 脚本可在 action 里直接打开浏览器、刷新选项栏、复制文本；
    // 同步沙箱内不能真开界面，统一记 op 由宿主排空后执行。
    global.java.startBrowser = function (url, title, html) {
      var u = String(url == null ? '' : url);
      var t = title == null ? '' : String(title);
      var h = html == null ? '' : String(html);
      if (u || h) syOp('browserOpen', u, JSON.stringify([t, h]));
      return null;
    };
    // legado startBrowserAwait：打开浏览器并等待用户点「完成」。
    // refetchAfterSuccess=false 返回 WebView outerHTML；其余返回原 URL
    // 重新请求的响应。缓存由宿主 settle 写入（JSON 载荷）。
    global.java.startBrowserAwait = function (url, title, refetchAfterSuccess, html) {
      var u = String(url == null ? '' : url);
      var t = title == null ? '' : String(title);
      var h = html == null ? '' : String(html);
      var refetch = refetchAfterSuccess === false ? 0 : 1;
      if (!u && !h) return syAwaitResp('', 0, '', {});
      var key = 'ba:' + syHash(h + '\u0001' + u + '\u0001' + refetch) + ':' +
          (h.length + u.length);
      var c = global.__browserAwaitCache;
      if (c && c[key] != null) {
        try {
          var o = JSON.parse(c[key]);
          return syAwaitResp(o.body || '', o.code || 0, o.url || '', o.headers || {});
        } catch (e) {}
      }
      syOp('browserAwait', key, JSON.stringify([u, t, String(refetch), h]));
      return syAwaitResp('', 0, '', {});
    };
    global.java.openUrl = function (url, mimeType) {
      global.java.startBrowser(url, '');
      return true;
    };
    // legado SourceLoginJsExtensions.open(name, url, title, origin)：
    // 回调脚本用 login → 源登录、search → 按关键字搜索、explore → 打开发现页。
    // 同步沙箱不改界面，记 op 由宿主在求值结束后按 name 排空。
    // origin 缺省为当前源（md3 `origin ?: source`）。
    global.java.open = function (name, url, title, origin) {
      var n = String(name == null ? '' : name);
      if (!n) return null;
      syOp('open', JSON.stringify([
        n,
        url == null ? '' : String(url),
        title == null ? '' : String(title),
        origin == null ? '' : String(origin),
      ]), '');
      return null;
    };
    global.java.refreshExplore = function () {
      syOp('refreshKinds', '', '');
      return true;
    };
    // legado SourceLoginJsExtensions（登录/发现页 action 的 java 对象）：
    // - reLoginView：重载登录视图；发现页场景等价 refreshExplore（reUiView
    //   → 选项栏整栏重取）。
    // - upLoginData：登录数据推给界面，沙箱无登录界面，忽略。
    // - refreshBookInfo/refreshBookToc/refreshContent：书页刷新事件，
    //   沙箱无对应界面，忽略但保持可调用——缺失会让 action 脚本在调用处
    //   抛 TypeError，后续的 refreshExplore 等语句永不执行。
    global.java.reLoginView = function (deltaUp) {
      syOp('refreshKinds', '', '');
      return true;
    };
    global.java.upLoginData = function (data) { return null; };
    global.java.refreshBookInfo = function () { return null; };
    global.java.refreshBookToc = function () { return null; };
    global.java.refreshContent = function () { return null; };
    // legado AnalyzeRule.refreshTocUrl（仅 preUpdateJs 语义）：目录抓取前
    // 重新解析详情页以更新 book.tocUrl。同步沙箱不能就地请求，记 op 由
    // 宿主在 preUpdateJs 结束后按需重取详情。
    global.java.refreshTocUrl = function () {
      syOp('refreshTocUrl', '', '');
      return null;
    };
    // legado AnalyzeRule.reGetBook（审计 T3）：preUpdateJs 内按书名/作者
    // 重新精确搜索并改写 bookUrl，再重取详情（书名换源/换签名的源靠它）。
    // 宿主在目录阶段消费该 op；其他阶段调用无人消费（legado 抛
    // IllegalStateException，此处按 no-op 记录偏差，不在已完成的脚本上回溯抛错）。
    global.java.reGetBook = function () {
      var book = global.book;
      syOp('reGetBook', JSON.stringify({
        name: book && book.name != null ? String(book.name) : '',
        author: book && book.author != null ? String(book.author) : '',
      }), '');
      return null;
    };
    // ── loginCheckJs 的 AnalyzeUrl 面 ──
    // legado 在 loginCheckJs 里把 `java` 绑定为 AnalyzeUrl 本身（不是
    // AnalyzeRule）：脚本可读 ruleUrl/url/headerMap，调用 initUrl() 重解析
    // 模板、getStrResponse() 重取当前地址。沙箱按每次求值注入 __syLogin
    // 状态复刻这一段，求值结束即清除（不影响其他规则上下文）。
    global.__syLoginBegin = function (seedJson) {
      var s = {};
      try { s = JSON.parse(seedJson) || {}; } catch (e) {}
      var hm = {};
      var src = s.headers || {};
      for (var k in src) hm[k] = String(src[k]);
      Object.defineProperty(hm, 'get', {
        value: function (n) { var v = hm[String(n)]; return v == null ? null : v; },
        enumerable: false,
      });
      Object.defineProperty(hm, 'put', {
        value: function (n, v) {
          hm[String(n)] = v == null ? '' : String(v);
          return v;
        },
        enumerable: false,
      });
      Object.defineProperty(hm, 'putAll', {
        value: function (o) {
          if (o && typeof o === 'object') {
            for (var k2 in o) hm[String(k2)] = o[k2] == null ? '' : String(o[k2]);
          }
        },
        enumerable: false,
      });
      Object.defineProperty(hm, 'remove', {
        value: function (n) { var v = hm[String(n)]; delete hm[String(n)]; return v; },
        enumerable: false,
      });
      Object.defineProperty(hm, 'containsKey', {
        value: function (n) { return hm[String(n)] != null; },
        enumerable: false,
      });
      Object.defineProperty(hm, 'toString', {
        value: function () {
          var p = [];
          for (var k3 in hm) p.push(k3 + '=' + hm[k3]);
          return '{' + p.join(', ') + '}';
        },
        enumerable: false,
      });
      global.__syLogin = {
        ruleUrl: s.ruleUrl == null ? '' : String(s.ruleUrl),
        url: s.url == null ? '' : String(s.url),
        method: s.method == null ? '' : String(s.method),
        body: s.body == null ? '' : String(s.body),
        options: (s.options && typeof s.options === 'object') ? s.options : null,
        headerMap: hm,
      };
    };
    global.__syLoginEnd = function () { global.__syLogin = null; };
    Object.defineProperty(global.java, 'ruleUrl', {
      configurable: true,
      get: function () {
        // loginCheckJs 环境优先（宿主在重解析前注入完整快照）；其余场景
        // 由 AnalyzeUrl 每轮求值注入当前 ruleUrl（legado 绑定 `java = this`
        // 即 AnalyzeUrl 实体，`java.ruleUrl` 恒可读）。
        if (global.__syLogin) return global.__syLogin.ruleUrl;
        return global.__syRuleUrl == null ? '' : String(global.__syRuleUrl);
      },
    });
    Object.defineProperty(global.java, 'url', {
      configurable: true,
      get: function () { return global.__syLogin ? global.__syLogin.url : ''; },
    });
    Object.defineProperty(global.java, 'headerMap', {
      configurable: true,
      get: function () { return global.__syLogin ? global.__syLogin.headerMap : {}; },
    });
    global.java.initUrl = function () {
      // legado 在脚本执行到调用点时同步重解析 URL 模板。同步沙箱无法回跳
      // 宿主，记 op 由 `_runLoginCheck` 在求值结束后重解析并重放本轮（旧实现
      // 按脚本文本预扫描 `initUrl(`，注释或未执行分支里的调用也会生效）。
      if (global.__syLogin) {
        syOp('initUrl', '', '');
        return null;
      }
      if (!global.__initUrlLogged) {
        global.__initUrlLogged = true;
        global.java.log('[java.initUrl] 非 loginCheckJs 环境无 URL 可重解析，已忽略');
      }
      return null;
    };
    var __syGetStrResponseBase = global.java.getStrResponse;
    global.java.getStrResponse = function (jsStr, sourceRegex) {
      var st = global.__syLogin;
      if (!st) {
        return __syGetStrResponseBase
          ? __syGetStrResponseBase.apply(null, arguments) : '';
      }
      // legado 在同一 AnalyzeUrl 实例上重取：构造期的 URL 选项（proxy/dnsIp/
      // retry/webView/webJs/bodyJs/type/charset…）全部保留。宿主把快照放进
      // seed.options，这里原样叠加（headers 由脚本当前 headerMap 提供）。
      var extra = null;
      if (st.options) {
        try {
          extra = JSON.parse(JSON.stringify(st.options));
        } catch (e) {
          extra = null;
        }
      }
      if (st.method && st.method !== 'GET') {
        extra = extra || {};
        extra.method = st.method;
        if (st.body) extra.body = st.body;
      }
      // legado `getStrResponseAwait(jsStr, sourceRegex)`：jsStr 只在 WebView
      // 分支作为页内脚本执行（等价 URL 选项 webJs）；sourceRegex 交给
      // BackstageWebView 资源层嗅探（宿主解析 `_sySourceRegex`）。
      var js = jsStr == null ? '' : String(jsStr);
      if (js.trim() !== '' && extra && extra.webView) {
        extra.webJs = js;
      }
      var rx = sourceRegex == null ? '' : String(sourceRegex);
      if (rx.trim() !== '') {
        extra = extra || {};
        extra._sySourceRegex = rx;
      }
      var key = syWithHeaders(st.url, st.headerMap, extra);
      return syResp(key, global.java.__ajaxReq(key));
    };
    global.java.getResponse = function () {
      if (global.__syLogin) return global.java.getStrResponse();
      if (!global.__getResponseLogged) {
        global.__getResponseLogged = true;
        global.java.log('[java.getResponse] 非 loginCheckJs 环境无当前请求，已忽略');
      }
      return null;
    };
    global.java.copyText = function (text) {
      var t = String(text == null ? '' : text);
      syOp('copyText', t, '');
      return t;
    };
    // legado getVerificationCode(imageUrl)：弹验证码输入并返回用户文本。
    // 首轮记 op 返回空串；宿主缓存输入值后重放。取消/空输入缓存空串。
    global.java.getVerificationCode = function (imageUrl) {
      var u = String(imageUrl == null ? '' : imageUrl);
      if (!u) return '';
      var key = 'vc:' + syHash(u) + ':' + u.length;
      var c = global.__verificationCodeCache;
      if (c && c[key] != null) return c[key];
      syOp('verificationCode', key, u);
      return '';
    };
  }
})(globalThis);
''';

/// java.* 第一梯队预置脚本。纯 ES 实现（QuickJS 无 TextEncoder/btoa），
/// 全部函数同步返回；UTF-8 编解码自行实现。
const String javaExtensionsJsPrelude = r'''
(function (global) {
  'use strict';

  // ── UTF-8 字节编解码（含代理对合并） ──
  function utf8Encode(str) {
    var out = [];
    for (var i = 0; i < str.length; i++) {
      var c = str.charCodeAt(i);
      if (c >= 0xd800 && c <= 0xdbff && i + 1 < str.length) {
        var c2 = str.charCodeAt(i + 1);
        if (c2 >= 0xdc00 && c2 <= 0xdfff) {
          c = 0x10000 + ((c - 0xd800) << 10) + (c2 - 0xdc00);
          i++;
        }
      }
      if (c < 0x80) out.push(c);
      else if (c < 0x800) out.push(0xc0 | (c >> 6), 0x80 | (c & 63));
      else if (c < 0x10000) out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
      else out.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
    }
    return out;
  }

  function utf8Decode(bytes) {
    var out = '';
    var i = 0;
    while (i < bytes.length) {
      var b = bytes[i++] & 0xff; // 兼容有符号字节数组（legado ByteArray 口径）
      if (b < 0x80) out += String.fromCharCode(b);
      else if (b < 0xe0) out += String.fromCharCode(((b & 31) << 6) | (bytes[i++] & 63));
      else if (b < 0xf0) out += String.fromCharCode(((b & 15) << 12) | ((bytes[i++] & 63) << 6) | (bytes[i++] & 63));
      else {
        var cp = ((b & 7) << 18) | ((bytes[i++] & 63) << 12) | ((bytes[i++] & 63) << 6) | (bytes[i++] & 63);
        cp -= 0x10000;
        out += String.fromCharCode(0xd800 + (cp >> 10), 0xdc00 + (cp & 0x3ff));
      }
    }
    return out;
  }

  // ── Base64 ──
  var B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  var B64REV = {};
  for (var _i = 0; _i < 64; _i++) B64REV[B64.charAt(_i)] = _i;

  function b64FromBytes(bytes) {
    var out = '';
    for (var i = 0; i < bytes.length; i += 3) {
      var b1 = bytes[i];
      var hasB2 = i + 1 < bytes.length;
      var hasB3 = i + 2 < bytes.length;
      var b2 = hasB2 ? bytes[i + 1] : 0;
      var b3 = hasB3 ? bytes[i + 2] : 0;
      out += B64.charAt(b1 >> 2);
      out += B64.charAt(((b1 & 3) << 4) | (b2 >> 4));
      out += hasB2 ? B64.charAt(((b2 & 15) << 2) | (b3 >> 6)) : '=';
      out += hasB3 ? B64.charAt(b3 & 63) : '=';
    }
    return out;
  }

  function bytesFromB64(s) {
    // 宽容口径同 Hutool Base64.decode：忽略空白/非法字符、接受 url-safe 字母表、
    // 缺失填充。legado base64ToByteArray 即走 Hutool。
    var clean = String(s == null ? '' : s)
        .replace(/-/g, '+').replace(/_/g, '/')
        .replace(/[^A-Za-z0-9+/]/g, '');
    var out = [];
    var buf = 0, bits = 0;
    for (var i = 0; i < clean.length; i++) {
      buf = ((buf << 6) | B64REV[clean.charAt(i)]) & 0xffffff;
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        out.push(signedByte((buf >> bits) & 0xff));
      }
    }
    return out;
  }

  // android.util.Base64 标志位：NO_PADDING=1、NO_WRAP=2、CRLF=4、
  // URL_SAFE=8。DEFAULT(0) 按 76 字符换行且末尾带行分隔符。
  function b64EncodeFlags(bytes, flags) {
    var f = flags == null ? 2 : (flags | 0);
    var out = b64FromBytes(bytes.map(function (b) { return b & 0xff; }));
    if (f & 8) out = out.replace(/\+/g, '-').replace(/\//g, '_');
    if (f & 1) out = out.replace(/=+$/, '');
    if (!(f & 2) && out.length > 0) {
      var sep = (f & 4) ? '\r\n' : '\n';
      var wrapped = '';
      for (var i = 0; i < out.length; i += 76) {
        wrapped += out.substring(i, i + 76) + sep;
      }
      out = wrapped;
    }
    return out;
  }

  // 字节数组对外统一 legado ByteArray 有符号口径（-128..127）。
  function signedByte(v) { return v > 127 ? v - 256 : v; }

  // ── Hex ──
  function bytesToHex(bytes) {
    var out = '';
    for (var i = 0; i < bytes.length; i++) {
      var b = bytes[i] & 0xff;
      out += (b < 16 ? '0' : '') + b.toString(16);
    }
    return out;
  }

  function hexToBytes(s) {
    var h = String(s == null ? '' : s).replace(/[^0-9a-fA-F]/g, '');
    var out = [];
    for (var i = 0; i + 1 < h.length; i += 2) {
      out.push(signedByte(parseInt(h.charAt(i) + h.charAt(i + 1), 16)));
    }
    return out;
  }

  // legado `String.hexToByteArray()`（CryptoUtils.kt）：null 抛异常、长度
  // 必须为偶数、每两位必须是合法十六进制，否则抛异常。脚本常用
  // try { java.hexDecodeToString(result) } catch 做能力/阶段探测，宽松
  // 解码会把本该失败的分支当成功，跳过 catch 里的初始化。
  function hexStrictBytes(s) {
    if (s === null || s === undefined) {
      throw new TypeError('hexDecode: null');
    }
    var h = String(s);
    if (h.length % 2 !== 0) {
      throw new Error('hexDecode: odd length ' + h.length);
    }
    var out = [];
    for (var i = 0; i < h.length; i += 2) {
      var pair = h.substring(i, i + 2);
      if (!/^[0-9a-fA-F]{2}$/.test(pair)) {
        throw new Error('hexDecode: invalid pair ' + pair);
      }
      out.push(signedByte(parseInt(pair, 16)));
    }
    return out;
  }

  function anyToBytes(v) {
    if (v && typeof v === 'object' && typeof v.length === 'number') {
      var arr = [];
      for (var i = 0; i < v.length; i++) arr.push(v[i] & 0xff);
      return arr;
    }
    return utf8Encode(String(v == null ? '' : v));
  }

  // ── MD5（RFC 1321，K 表由 sin 构造避免手抄错误） ──
  function md5Bytes(bytes) {
    var K = [];
    for (var i = 0; i < 64; i++) {
      K[i] = Math.floor(Math.abs(Math.sin(i + 1)) * 4294967296);
    }
    var S = [7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
             5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
             4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
             6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21];

    var msg = [];
    for (var k = 0; k < bytes.length; k++) msg.push(bytes[k] & 0xff); // 容错有符号输入
    var bitLen = bytes.length * 8;
    msg.push(0x80);
    while (msg.length % 64 !== 56) msg.push(0);
    for (var n = 0; n < 8; n++) {
      var shift = n * 8;
      var val = Math.floor(bitLen / Math.pow(2, shift)) % 256;
      msg.push(val);
    }

    function rotl(x, c) { return ((x << c) | (x >>> (32 - c))) & 0xffffffff; }

    var a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;
    for (var chunk = 0; chunk < msg.length; chunk += 64) {
      var M = [];
      for (var j = 0; j < 16; j++) {
        var o = chunk + j * 4;
        M[j] = (msg[o] | (msg[o + 1] << 8) | (msg[o + 2] << 16) | (msg[o + 3] << 24)) >>> 0;
      }
      var A = a0, B = b0, C = c0, D = d0;
      for (var r = 0; r < 64; r++) {
        var F, g;
        if (r < 16) { F = (B & C) | (~B & D); g = r; }
        else if (r < 32) { F = (D & B) | (~D & C); g = (5 * r + 1) % 16; }
        else if (r < 48) { F = B ^ C ^ D; g = (3 * r + 5) % 16; }
        else { F = C ^ (B | ~D); g = (7 * r) % 16; }
        var sum = (F + A + K[r] + M[g]) & 0xffffffff;
        A = D; D = C; C = B;
        B = (B + rotl(sum, S[r])) & 0xffffffff;
      }
      a0 = (a0 + A) & 0xffffffff;
      b0 = (b0 + B) & 0xffffffff;
      c0 = (c0 + C) & 0xffffffff;
      d0 = (d0 + D) & 0xffffffff;
    }
    var out = [];
    [a0, b0, c0, d0].forEach(function (w) {
      out.push(w & 0xff, (w >>> 8) & 0xff, (w >>> 16) & 0xff, (w >>> 24) & 0xff);
    });
    return out;
  }

  // ── 时间 ──
  function pad2(n) { return n < 10 ? '0' + n : '' + n; }

  // legado timeFormat：`yyyy/MM/dd HH:mm`（无秒、斜杠分隔）。
  // 两个重载都支持：毫秒时间戳（num / 纯数字串）与时间字符串
  // （"2024-01-02 03:04:05" / "2024/01/02"）。解析失败时原样返回，
  // 避免把源里的占位文本吃掉。
  function timeFormat(t) {
    var ms;
    if (typeof t === 'number') {
      ms = t;
    } else if (typeof t === 'string') {
      var s = t.trim();
      if (s === '') return '';
      if (/^\d+$/.test(s)) {
        ms = Number(s);
      } else {
        // QuickJS 的 Date.parse 只保证 ISO 格式，"2024-01-02 03:04:05"
        // 这类 legado 常见入参会得到 NaN，需自行拆分后再构造 Date。
        var m = s.match(
            /^(\d{4})[-\/年](\d{1,2})[-\/月](\d{1,2})日?(?:[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2}))?)?/);
        if (!m) return s;
        var parsed = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]),
            Number(m[4] || 0), Number(m[5] || 0), Number(m[6] || 0));
        if (isNaN(parsed.getTime())) return s;
        ms = parsed.getTime();
      }
    } else {
      return t == null ? '' : String(t);
    }
    var d = new Date(ms);
    if (isNaN(d.getTime())) return String(t);
    return d.getFullYear() + '/' + pad2(d.getMonth() + 1) + '/' + pad2(d.getDate()) +
        ' ' + pad2(d.getHours()) + ':' + pad2(d.getMinutes());
  }

  // legado 语义：SimpleTimeZone(sh, "UTC") + Date(time)——`sh` 是**毫秒**
  // 原始偏移（SimpleTimeZone 构造参数单位），按 UTC 分量输出 format。
  function timeFormatUTC(t, format, sh) {
    var d = new Date(Number(t) + (Number(sh) || 0));
    if (isNaN(d.getTime())) return '';
    var f = String(format || 'yyyy-MM-dd HH:mm:ss');
    return f
        .replace(/yyyy/g, d.getUTCFullYear())
        .replace(/MM/g, pad2(d.getUTCMonth() + 1))
        .replace(/dd/g, pad2(d.getUTCDate()))
        .replace(/HH/g, pad2(d.getUTCHours()))
        .replace(/mm/g, pad2(d.getUTCMinutes()))
        .replace(/ss/g, pad2(d.getUTCSeconds()));
  }

  // ── URL 编码（Java URLEncoder 口径：空格→'+'，.-*_ 保留） ──
  function encoderEncode(str) {
    var bytes = utf8Encode(String(str == null ? '' : str));
    var out = '';
    for (var i = 0; i < bytes.length; i++) {
      var b = bytes[i];
      if ((b >= 0x61 && b <= 0x7a) || (b >= 0x41 && b <= 0x5a) || (b >= 0x30 && b <= 0x39) ||
          b === 0x2e || b === 0x2d || b === 0x2a || b === 0x5f) {
        out += String.fromCharCode(b);
      } else if (b === 0x20) {
        out += '+';
      } else {
        out += '%' + (b < 16 ? '0' : '') + b.toString(16).toUpperCase();
      }
    }
    return out;
  }

  // ── 章节号解析（legado StringUtils.stringToInt / chineseNumToInt 口径） ──
  var CN_MAP = (function () {
    var m = {};
    var digits = '零一二三四五六七八九十';
    for (var i = 0; i < digits.length; i++) m[digits.charAt(i)] = i;
    var upper = '〇壹贰叁肆伍陆柒捌玖拾';
    for (var j = 0; j < upper.length; j++) m[upper.charAt(j)] = j;
    m['两'] = 2;
    m['百'] = 100;
    m['佰'] = 100;
    m['千'] = 1000;
    m['仟'] = 1000;
    m['万'] = 10000;
    m['亿'] = 100000000;
    return m;
  })();

  // legado StringUtils.fullToHalf：全角空格→半角，全角 ASCII 区回退 65248。
  function fullToHalf(input) {
    var out = '';
    for (var i = 0; i < input.length; i++) {
      var code = input.charCodeAt(i);
      if (code === 12288) out += ' ';
      else if (code >= 65281 && code <= 65374) {
        out += String.fromCharCode(code - 65248);
      } else out += input.charAt(i);
    }
    return out;
  }

  // legado StringUtils.chineseNumToInt（含 亿/万 进位与「一千二」尾数规则）。
  function chineseNumToInt(chNum) {
    var result = 0, tmp = 0, billion = 0;
    for (var i = 0; i < chNum.length; i++) {
      var num = CN_MAP[chNum.charAt(i)];
      if (num === undefined) return -1;
      var prev = i > 0 ? CN_MAP[chNum.charAt(i - 1)] : undefined;
      if (num === 100000000) {
        result += tmp;
        result *= num;
        billion = billion * 100000000 + result;
        result = 0;
        tmp = 0;
      } else if (num === 10000) {
        result += tmp;
        result *= num;
        tmp = 0;
      } else if (num >= 10) {
        if (tmp === 0) tmp = 1;
        result += num * tmp;
        tmp = 0;
      } else {
        tmp = (i >= 2 && i === chNum.length - 1 &&
            prev !== undefined && prev > 10)
            ? num * prev / 10
            : tmp * 10 + num;
      }
    }
    return result + tmp + billion;
  }

  // legado StringUtils.stringToInt：全半角归一 + ASCII 空白剔除后按整数
  // 解析，失败再按中文数字解析（失败 -1）。Java 的 \s 只含 ASCII 空白，
  // 不能直接用 JS 的 \s（会吞掉全角空格之外的其他 Unicode 空白）。
  function stringToInt(str) {
    if (str == null) return -1;
    var num = fullToHalf(String(str)).replace(/[\t\n\x0b\f\r ]+/g, '');
    if (/^[+-]?\d+$/.test(num)) {
      var n = parseInt(num, 10);
      if (!isNaN(n) && n >= -2147483648 && n <= 2147483647) return n;
    }
    return chineseNumToInt(num);
  }

  // legado JsExtensions.toNumChapter：返回 String?（null 入参 → null；
  // 命中 `(第)(.+?)(章)` 时把中段转数字，未命中原样返回）。
  function toNumChapter(v) {
    if (v === null || v === undefined) return null;
    var str = String(v);
    var m = str.match(/(第)(.+?)(章)/);
    if (!m) return str;
    return m[1] + stringToInt(m[2]) + m[3];
  }

  // ── HTML 净化（formatKeepImg 近似：保留 <img>，块级标签转换行） ──
  function htmlFormat(v) {
    var s = String(v == null ? '' : v);
    s = s.replace(/<\s*script[\s\S]*?<\s*\/\s*script\s*>/gi, '');
    s = s.replace(/<\s*style[\s\S]*?<\s*\/\s*style\s*>/gi, '');
    s = s.replace(/<\s*br\s*\/?\s*>/gi, '\n');
    s = s.replace(/<\s*\/\s*(p|div|h[1-6]|li|tr)\s*>/gi, '\n');
    var imgs = [];
    s = s.replace(/<\s*img[^>]*>/gi, function (m0) {
      imgs.push(m0);
      return '\u0000' + imgs.length + '\u0000';
    });
    s = s.replace(/<[^>]+>/g, '');
    s = s.replace(/\u0000(\d+)\u0000/g, function (m0, idx) {
      return imgs[Number(idx) - 1] || '';
    });
    return s;
  }

  function randomUUID() {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
      var r = (Math.random() * 16) | 0;
      var v = c === 'x' ? r : ((r & 0x3) | 0x8);
      return v.toString(16);
    });
  }

  // 设备标识：宿主可经 __ANDROID_ID__ 种子注入稳定值；缺省取引擎生命周期内
  // 稳定的随机串（legado 用它做登录信息加密 key，仅需稳定性不需真实性）。
  var ANDROID_ID = (global.__ANDROID_ID__ != null && global.__ANDROID_ID__ !== '')
      ? String(global.__ANDROID_ID__)
      : randomUUID().replace(/-/g, '');

  // ── 排空队列 ──
  function pushToast(msg, long) {
    if (!global.__javaToasts) global.__javaToasts = [];
    // legado JsExtensions.toast：`"${getSource()?.getTag()}: $msg"`。
    var tag = typeof global.__sySourceTag === 'function'
      ? String(global.__sySourceTag() || '') : '';
    var text = (tag ? tag + ': ' : '') + String(msg == null ? '' : msg);
    global.__javaToasts.push({ msg: text, long: !!long });
  }
  function pushLog(msg) {
    if (!global.__javaLogs) global.__javaLogs = [];
    global.__javaLogs.push(String(msg == null ? '' : msg));
  }

  // ── 元素包装（java.getElements / getElement 的返回值） ──
  // 宿主字面量：单元素 {t:text, h:html, ot:ownText, a:attrs, o:outerHtml,
  // u:baseUrl, j:json}；kind 'e'/'g' 的载荷为
  // {r:[根HTML...], els:[元素字面量 + g:tagName, p:元素子序号路径, r:根序号]}。
  // r/p 用于在沙箱里把元素定位回与 select/children 相同的 jsoup DOM 节点
  // （对应 legado 里 Rhino 直调 jsoup 的上下文语义），parent(s)/siblings/
  // next/prev 等遍历依赖它；宿主未附带上下文（r/p 缺省，如根节点超体积
  // 上限）时这些遍历返回空，其余读取方法不受影响。
  function __elCtx(roots) {
    return { roots: roots || [], docs: [], nodes: {} };
  }

  function __elDoc(ctx, ri) {
    if (ctx.docs[ri] !== undefined) return ctx.docs[ri];
    var html = ctx.roots[ri];
    var doc = null;
    var Jsoup = global.org && global.org.jsoup && global.org.jsoup.Jsoup;
    if (html && Jsoup && typeof Jsoup.parse === 'function') {
      try { doc = Jsoup.parse(String(html), ''); } catch (e) { doc = null; }
    }
    ctx.docs[ri] = doc;
    return doc;
  }

  function __cxNode(ctx, o) {
    if (!ctx || !o || !o.p) return null;
    var ri = o.r || 0;
    var key = ri + ':' + o.p.join('.');
    if (ctx.nodes[key] !== undefined) return ctx.nodes[key];
    var n = __elDoc(ctx, ri);
    if (n) {
      for (var i = 0; i < o.p.length; i++) {
        var kids = n.children();
        n = kids.get ? kids.get(o.p[i]) : kids[o.p[i]];
        if (!n) break;
      }
      // 双端解析器结构不一致时按标签名兜底校验，不一致视为无上下文，
      // 避免把兄弟/父级错认成别的元素。
      if (n && o.g && String(n.tagName()).toLowerCase() !==
          String(o.g).toLowerCase()) n = null;
    }
    ctx.nodes[key] = n || null;
    return n || null;
  }

  function __nodePath(n) {
    var path = [];
    var cur = n;
    while (cur && cur.__parent) {
      var par = cur.__parent;
      var idx = 0;
      for (var i = 0; i < par.__children.length; i++) {
        var c = par.__children[i];
        if (c.__kind !== 'el') continue;
        if (c === cur) break;
        idx++;
      }
      path.unshift(idx);
      if (par.__kind === 'doc') break;
      cur = par;
    }
    return path;
  }

  function __elLiteral(n, base) {
    var attrs = {};
    var raw = n.__attrs || {};
    for (var k in raw) attrs[k] = raw[k];
    return {
      t: n.text(), h: n.html(), ot: n.ownText(), o: n.outerHtml(),
      a: attrs, u: base == null ? '' : String(base),
      g: n.tagName(), p: __nodePath(n), r: 0
    };
  }

  // 沙箱节点 → 包装列表；ctx 直接以节点所在文档为种子（不再解析根 HTML），
  // 路径可再定位，节点同一性保证 contains/indexOf 跨列表可用。
  function __wrapNodes(nodes, base) {
    var arr = [];
    var doc = null;
    if (nodes) {
      for (var i = 0; i < nodes.length; i++) {
        var n = nodes.get ? nodes.get(i) : nodes[i];
        if (!n || n.__kind !== 'el') continue;
        if (!doc) {
          var d = n;
          while (d && d.__kind !== 'doc') d = d.__parent;
          doc = d || null;
          if (!doc) continue;
        }
        arr.push(__elLiteral(n, base));
      }
    }
    if (!doc || !arr.length) return __javaElements([]);
    var ctx = __elCtx([]);
    ctx.docs[0] = doc;
    return __javaElements({ r: [], els: arr }, ctx);
  }

  function __wrapEl(o, ctx) {
    function nav() { return __cxNode(ctx, o); }
    function one(n) {
      if (!n) return null;
      var l = __wrapNodes([n], o.u);
      return l.length ? l[0] : null;
    }
    function many(nodes) { return __wrapNodes(nodes, o.u); }
    var el = {
      __javaEl: true,
      text: function () { return o.t || ''; },
      html: function () { return o.h || ''; },
      ownText: function () { return o.ot || ''; },
      outerHtml: function () { return o.o != null ? o.o : (o.h || ''); },
      attr: function (k, value) {
        var name = String(k == null ? '' : k);
        var abs = name.indexOf('abs:') === 0;
        if (abs) name = name.substring(4);
        if (arguments.length >= 2) {
          if (!o.a) o.a = {};
          o.a[name] = String(value == null ? '' : value);
          return el;
        }
        var raw = (o.a && o.a[name] != null) ? String(o.a[name]) : '';
        return abs ? syAbsUrl(raw, o.u) : raw;
      },
      hasAttr: function (k) {
        var name = String(k == null ? '' : k);
        if (name.indexOf('abs:') === 0) name = name.substring(4);
        return !!(o.a && Object.prototype.hasOwnProperty.call(o.a, name));
      },
      removeAttr: function (k) {
        var name = String(k == null ? '' : k);
        if (name.indexOf('abs:') === 0) name = name.substring(4);
        if (o.a) delete o.a[name];
        return el;
      },
      id: function () {
        return (o.a && o.a['id'] != null) ? String(o.a['id']) : '';
      },
      className: function () {
        return (o.a && o.a['class'] != null) ? String(o.a['class']) : '';
      },
      classNames: function () {
        var cls = o.a && o.a['class'];
        if (cls == null) return [];
        return String(cls).split(/\s+/).filter(function (s) { return !!s; });
      },
      hasClass: function (name) {
        return el.classNames().indexOf(String(name)) >= 0;
      },
      addClass: function (name) {
        var n = String(name);
        if (n && !el.hasClass(n)) {
          var cur = el.className();
          el.attr('class', cur ? cur + ' ' + n : n);
        }
        return el;
      },
      removeClass: function (name) {
        var n = String(name);
        var kept = el.classNames().filter(function (s) { return s !== n; });
        if (o.a) o.a['class'] = kept.join(' ');
        return el;
      },
      toggleClass: function (name) {
        return el.hasClass(name) ? el.removeClass(name) : el.addClass(name);
      },
      tagName: function () { return o.g ? String(o.g) : ''; },
      val: function (value) {
        if (arguments.length >= 1) return el.attr('value', value);
        return el.attr('value');
      },
      hasText: function () { return /\S/.test(String(o.t || '')); },
      data: function () {
        var n = nav();
        return n ? n.data() : '';
      },
      select: function (sel) {
        var n = nav();
        if (!n) return __wrapElSelect(o, sel);
        return many(n.select(String(sel == null ? '' : sel)));
      },
      selectFirst: function (sel) {
        var l = el.select(sel);
        return l.length ? l[0] : null;
      },
      children: function () {
        var n = nav();
        if (n) return many(n.children());
        var doc = __wrapElDoc(o);
        var roots = doc ? doc.children() : null;
        var root = (roots && roots.length) ? roots.get(0) : null;
        return root ? __wrapNodes(root.children(), o.u) : __javaElements([]);
      },
      child: function (i) { return el.children().get(i); },
      firstElementChild: function () {
        var n = nav();
        return n ? one(n.firstElementChild()) : null;
      },
      lastElementChild: function () {
        var n = nav();
        return n ? one(n.lastElementChild()) : null;
      },
      parent: function () {
        var n = nav();
        return n ? one(n.parent()) : null;
      },
      parents: function () {
        var n = nav();
        return n ? many(n.parents()) : __javaElements([]);
      },
      siblingElements: function () {
        var n = nav();
        return n ? many(n.siblingElements()) : __javaElements([]);
      },
      siblings: function () { return el.siblingElements(); },
      elementSiblingIndex: function () {
        var n = nav();
        return n ? n.elementSiblingIndex() : 0;
      },
      siblingIndex: function () { return el.elementSiblingIndex(); },
      nextElementSibling: function () {
        var n = nav();
        return n ? one(n.nextElementSibling()) : null;
      },
      previousElementSibling: function () {
        var n = nav();
        return n ? one(n.previousElementSibling()) : null;
      },
      nextElementSiblings: function () {
        var n = nav();
        return n ? many(n.nextElementSiblings()) : __javaElements([]);
      },
      previousElementSiblings: function () {
        var n = nav();
        return n ? many(n.previousElementSiblings()) : __javaElements([]);
      },
      firstElementSibling: function () {
        var n = nav();
        return n ? one(n.firstElementSibling()) : el;
      },
      lastElementSibling: function () {
        var n = nav();
        return n ? one(n.lastElementSibling()) : el;
      },
      toString: function () { return o.t || ''; },
      json: o.j
    };
    function lit() { return o; }
    function navFn() { return nav(); }
    try {
      Object.defineProperty(el, '__lit', {
        value: lit, enumerable: false, configurable: true
      });
      Object.defineProperty(el, '__nav', {
        value: navFn, enumerable: false, configurable: true
      });
    } catch (e) {
      el.__lit = lit;
      el.__nav = navFn;
    }
    var a = o.a || {};
    for (var k in a) {
      if (el[k] === undefined) el[k] = a[k];
    }
    if (o.j && typeof o.j === 'object') {
      for (var jk in o.j) {
        if (el[jk] === undefined) el[jk] = o.j[jk];
      }
    }
    return el;
  }

  // 绝对化（jsoup `abs:` 属性语义）：已是绝对地址原样返回；协议相对
  // `//host/x` 继承 base 的 scheme；根相对 `/x` 取 base 的 origin；其余按
  // base 目录拼接并归一 `.`/`..`。base 缺失时原样返回。
  function syAbsUrl(raw, base) {
    var s = String(raw == null ? '' : raw);
    if (!s) return '';
    if (/^[a-zA-Z][a-zA-Z0-9+.\-]*:/.test(s)) return s;
    var b = String(base == null ? '' : base).replace(/[?#].*$/, '');
    if (!b) return s;
    if (s.indexOf('//') === 0) {
      var sm = /^([a-zA-Z][a-zA-Z0-9+.\-]*:)/.exec(b);
      return (sm ? sm[1] : 'http:') + s;
    }
    var om = /^([a-zA-Z][a-zA-Z0-9+.\-]*:\/\/[^\/]*)/.exec(b);
    if (s.charAt(0) === '/') return (om ? om[1] : b) + s;
    var joined = b.replace(/[^\/]*$/, '') + s;
    var origin = '';
    var rest = joined;
    var jm = /^([a-zA-Z][a-zA-Z0-9+.\-]*:\/\/[^\/]*)(.*)$/.exec(joined);
    if (jm) { origin = jm[1]; rest = jm[2]; }
    var parts = rest.split('/');
    var segs = [];
    for (var i = 0; i < parts.length; i++) {
      var seg = parts[i];
      if (seg === '..') {
        if (segs.length > 1) segs.pop();
      } else if (seg !== '.') {
        segs.push(seg);
      }
    }
    var path = segs.join('/');
    if (path.charAt(0) !== '/') path = '/' + path;
    return origin + path;
  }

  // 用外层 HTML 重新解析出文档（select/children 的 jsoup 语义载体：
  // doc 的唯一元素子节点即原元素，doc.select 因此包含根自身，与 jsoup
  // Element.select 一致）。
  function __wrapElDoc(o) {
    var html = o.o != null ? o.o : (o.h || '');
    if (!html) return null;
    var Jsoup = global.org && global.org.jsoup && global.org.jsoup.Jsoup;
    if (!Jsoup || typeof Jsoup.parse !== 'function') return null;
    return Jsoup.parse(String(html), o.u == null ? '' : String(o.u));
  }

  function __wrapElSelect(o, sel) {
    var doc = __wrapElDoc(o);
    if (!doc) return __javaElements([]);
    return __wrapNodes(doc.select(String(sel == null ? '' : sel)), o.u);
  }

  // 元素列表（jsoup Elements / legado ArrayList<Element> 同形接口）。
  // v 兼容纯字面量数组与宿主新载荷 {r:[根HTML...], els:[...]}；
  // 无上下文（r/p 缺省）时选择器按 outerHtml 重解析兜底，
  // 遍历族（parents/siblings/next/prev）返回空。
  function __decorateElements(list) {
    function nodesOf(el) { return el && el.__nav ? el.__nav() : null; }
    function litOf(el) { return el && el.__lit ? el.__lit() : null; }
    function base() {
      var l = list.length ? litOf(list[0]) : null;
      return l && l.u != null ? l.u : '';
    }
    function wrapN(n) {
      if (!n) return null;
      var l = __wrapNodes([n], base());
      return l.length ? l[0] : null;
    }
    function elIs(el, sel) {
      var n = nodesOf(el);
      if (n) return n.is(String(sel));
      var o = litOf(el);
      if (!o) return false;
      var doc = __wrapElDoc(o);
      var root = doc ? doc.children().get(0) : null;
      return root ? root.is(String(sel)) : false;
    }
    function siblingsWalk(next, all, query) {
      var out = [];
      var sel = (query == null || query === '') ? null : String(query);
      for (var i = 0; i < list.length; i++) {
        var e = nodesOf(list[i]);
        if (!e) continue;
        do {
          e = next ? e.nextElementSibling() : e.previousElementSibling();
          if (!e) break;
          if (!sel || e.is(sel)) out.push(wrapN(e));
        } while (all);
      }
      return __decorateElements(out);
    }
    list.size = function () { return list.length; };
    list.get = function (i) {
      var idx = i < 0 ? list.length + i : i;
      return idx >= 0 && idx < list.length ? list[idx] : null;
    };
    list.first = function () { return list.length ? list[0] : null; };
    list.last = function () {
      return list.length ? list[list.length - 1] : null;
    };
    list.isEmpty = function () { return list.length === 0; };
    list.toArray = function () { return list.slice(); };
    list.asList = function () { return list.slice(); };
    list.contains = function (x) {
      if (list.indexOf(x) >= 0) return true;
      var xn = nodesOf(x);
      if (!xn) return false;
      for (var i = 0; i < list.length; i++) {
        if (nodesOf(list[i]) === xn) return true;
      }
      return false;
    };
    list.text = function () {
      var out = [];
      for (var i = 0; i < list.length; i++) out.push(list[i].text());
      return out.join('\n');
    };
    list.html = function () {
      var out = [];
      for (var i = 0; i < list.length; i++) out.push(list[i].html());
      return out.join('\n');
    };
    list.outerHtml = function () {
      var out = [];
      for (var i = 0; i < list.length; i++) out.push(list[i].outerHtml());
      return out.join('\n');
    };
    list.eachText = function () {
      var out = [];
      for (var i = 0; i < list.length; i++) {
        if (list[i].hasText()) out.push(list[i].text());
      }
      return out;
    };
    list.eachAttr = function (name) {
      var out = [];
      for (var i = 0; i < list.length; i++) {
        if (list[i].hasAttr(name)) out.push(list[i].attr(name));
      }
      return out;
    };
    list.attr = function (name, value) {
      if (arguments.length >= 2) {
        for (var i = 0; i < list.length; i++) list[i].attr(name, value);
        return list;
      }
      for (var j = 0; j < list.length; j++) {
        if (list[j].hasAttr(name)) return list[j].attr(name);
      }
      return '';
    };
    list.hasAttr = function (name) {
      for (var i = 0; i < list.length; i++) {
        if (list[i].hasAttr(name)) return true;
      }
      return false;
    };
    list.removeAttr = function (name) {
      for (var i = 0; i < list.length; i++) list[i].removeAttr(name);
      return list;
    };
    list.addClass = function (name) {
      for (var i = 0; i < list.length; i++) list[i].addClass(name);
      return list;
    };
    list.removeClass = function (name) {
      for (var i = 0; i < list.length; i++) list[i].removeClass(name);
      return list;
    };
    list.toggleClass = function (name) {
      for (var i = 0; i < list.length; i++) list[i].toggleClass(name);
      return list;
    };
    list.hasClass = function (name) {
      for (var i = 0; i < list.length; i++) {
        if (list[i].hasClass(name)) return true;
      }
      return false;
    };
    list.hasText = function () {
      for (var i = 0; i < list.length; i++) {
        if (list[i].hasText()) return true;
      }
      return false;
    };
    list.val = function (value) {
      if (arguments.length >= 1) {
        for (var i = 0; i < list.length; i++) list[i].val(value);
        return list;
      }
      return list.length ? list[0].val() : '';
    };
    list.select = function (sel) {
      var out = [];
      var seen = [];
      var q = String(sel == null ? '' : sel);
      for (var i = 0; i < list.length; i++) {
        var l = list[i].select(q);
        for (var j = 0; j < l.length; j++) {
          var n = nodesOf(l[j]);
          if (n) {
            if (seen.indexOf(n) >= 0) continue;
            seen.push(n);
          }
          out.push(l[j]);
        }
      }
      return __decorateElements(out);
    };
    list.selectFirst = function (sel) {
      var l = list.select(sel);
      return l.length ? l[0] : null;
    };
    list.eq = function (i) {
      var el = list.get(i);
      return __decorateElements(el ? [el] : []);
    };
    list.not = function (sel) {
      var out = [];
      for (var i = 0; i < list.length; i++) {
        if (!elIs(list[i], sel)) out.push(list[i]);
      }
      return __decorateElements(out);
    };
    list.has = function (sel) {
      var out = [];
      for (var i = 0; i < list.length; i++) {
        if (list[i].select(sel).length) out.push(list[i]);
      }
      return __decorateElements(out);
    };
    list.is = function (sel) {
      for (var i = 0; i < list.length; i++) {
        if (elIs(list[i], sel)) return true;
      }
      return false;
    };
    list.parents = function () {
      var out = [];
      var seen = [];
      for (var i = 0; i < list.length; i++) {
        var n = nodesOf(list[i]);
        if (!n) continue;
        var ps = n.parents();
        for (var j = 0; j < ps.length; j++) {
          var p = ps.get(j);
          if (seen.indexOf(p) >= 0) continue;
          seen.push(p);
          out.push(wrapN(p));
        }
      }
      return __decorateElements(out);
    };
    list.next = function (query) {
      return siblingsWalk(true, false, query);
    };
    list.nextAll = function (query) {
      return siblingsWalk(true, true, query);
    };
    list.prev = function (query) {
      return siblingsWalk(false, false, query);
    };
    list.prevAll = function (query) {
      return siblingsWalk(false, true, query);
    };
    list.remove = function (arg) {
      if (typeof arg === 'number') {
        var idx = arg < 0 ? list.length + arg : arg;
        if (idx < 0 || idx >= list.length) return null;
        return list.splice(idx, 1)[0];
      }
      var at = list.indexOf(arg);
      if (at < 0) return false;
      list.splice(at, 1);
      return true;
    };
    list.toString = function () { return list.outerHtml(); };
    return list;
  }

  function __javaElements(v, ctxSeed) {
    var payload = null;
    var els = v || [];
    if (v && !Array.isArray(v) && v.els) {
      payload = v;
      els = v.els || [];
    }
    var ctx = ctxSeed || (payload ? __elCtx(payload.r || []) : null);
    var list = [];
    for (var i = 0; i < els.length; i++) list.push(__wrapEl(els[i], ctx));
    return __decorateElements(list);
  }

  global.__javaElements = __javaElements;

  // java.getStringList 返回 legado 的 List<String>：脚本除下标/长度外还常
  // 调 `.size()/.get(i)/.isEmpty()/.toArray()`。Array 上挂这些方法
  // （非枚举，不干扰 join/JSON/遍历），元素统一成字符串。
  function __javaStringList(arr) {
    var list = arr ? arr.slice() : [];
    for (var i = 0; i < list.length; i++) {
      list[i] = list[i] == null ? '' : String(list[i]);
    }
    var methods = {
      size: function () { return list.length; },
      get: function (i) {
        var idx = i < 0 ? list.length + i : i;
        return idx >= 0 && idx < list.length ? list[idx] : null;
      },
      isEmpty: function () { return list.length === 0; },
      toArray: function () { return list.slice(); },
    };
    for (var name in methods) {
      try {
        Object.defineProperty(list, name, {
          value: methods[name], enumerable: false, configurable: true,
        });
      } catch (e) {
        list[name] = methods[name];
      }
    }
    return list;
  }

  // ── AES（ECB / CBC / GCM；PKCS5/7 或 NoPadding；GCM 自带 tag） ──
  // 纯 JS 实现：同步沙箱内无法回调宿主做加解密，且 QuickJS 没有 WebCrypto。
  // S-box 由 GF(2^8) 逆元 + 仿射变换程序生成（比手抄 256 项可靠），
  // 算法按 FIPS-197 实现，测试用 NIST SP 800-38A / FIPS-197 向量锁定。
  var AES_SBOX = [];
  var AES_INV_SBOX = [];
  (function () {
    function rot8(x, n) { return ((x << n) | (x >>> (8 - n))) & 0xff; }
    var p = 1, q = 1;
    do {
      // p *= 3（GF(2^8)），按 uint8 截断
      p = (p ^ (p << 1) ^ ((p & 0x80) ? 0x1b : 0)) & 0xff;
      // q /= 3（等价乘 0xf6）：中间步骤不能提前截断
      q ^= q << 1;
      q ^= q << 2;
      q ^= q << 4;
      q &= 0xff;
      if (q & 0x80) q ^= 0x09;
      var x = (q ^ rot8(q, 1) ^ rot8(q, 2) ^ rot8(q, 3) ^ rot8(q, 4)) & 0xff;
      AES_SBOX[p] = (x ^ 0x63) & 0xff;
    } while (p !== 1);
    AES_SBOX[0] = 0x63;
    for (var i = 0; i < 256; i++) AES_INV_SBOX[AES_SBOX[i]] = i;
  })();

  function gmul(a, b) {
    var r = 0;
    for (var i = 0; i < 8; i++) {
      if (b & 1) r ^= a;
      var hi = a & 0x80;
      a = (a << 1) & 0xff;
      if (hi) a ^= 0x1b;
      b >>= 1;
    }
    return r & 0xff;
  }

  function aesKeyExpand(key) {
    var nk = key.length >> 2;
    if (key.length !== 16 && key.length !== 24 && key.length !== 32) return null;
    var nr = nk + 6;
    var w = new Array(4 * (nr + 1));
    var i;
    for (i = 0; i < nk; i++) {
      w[i] = ((key[4 * i] << 24) | (key[4 * i + 1] << 16) |
          (key[4 * i + 2] << 8) | key[4 * i + 3]) >>> 0;
    }
    var rcon = 1;
    for (i = nk; i < 4 * (nr + 1); i++) {
      var t = w[i - 1];
      if (i % nk === 0) {
        t = ((t << 8) | (t >>> 24)) >>> 0;
        t = ((AES_SBOX[(t >>> 24) & 0xff] << 24) |
            (AES_SBOX[(t >>> 16) & 0xff] << 16) |
            (AES_SBOX[(t >>> 8) & 0xff] << 8) |
            AES_SBOX[t & 0xff]) >>> 0;
        t = (t ^ (rcon << 24)) >>> 0;
        rcon = ((rcon << 1) ^ ((rcon & 0x80) ? 0x1b : 0)) & 0xff;
      } else if (nk > 6 && i % nk === 4) {
        t = ((AES_SBOX[(t >>> 24) & 0xff] << 24) |
            (AES_SBOX[(t >>> 16) & 0xff] << 16) |
            (AES_SBOX[(t >>> 8) & 0xff] << 8) |
            AES_SBOX[t & 0xff]) >>> 0;
      }
      w[i] = (w[i - nk] ^ t) >>> 0;
    }
    return { w: w, nr: nr };
  }

  function aesAddRoundKey(s, w, round) {
    for (var c = 0; c < 4; c++) {
      var word = w[round * 4 + c];
      s[4 * c] ^= (word >>> 24) & 0xff;
      s[4 * c + 1] ^= (word >>> 16) & 0xff;
      s[4 * c + 2] ^= (word >>> 8) & 0xff;
      s[4 * c + 3] ^= word & 0xff;
    }
  }

  function aesShiftRows(s, inv) {
    var t = s.slice();
    for (var r = 1; r < 4; r++) {
      for (var c = 0; c < 4; c++) {
        var src = inv ? (c - r + 4) % 4 : (c + r) % 4;
        s[r + 4 * c] = t[r + 4 * src];
      }
    }
  }

  function aesMixColumns(s, inv) {
    for (var c = 0; c < 4; c++) {
      var a0 = s[4 * c], a1 = s[4 * c + 1], a2 = s[4 * c + 2], a3 = s[4 * c + 3];
      if (inv) {
        s[4 * c] = gmul(a0, 14) ^ gmul(a1, 11) ^ gmul(a2, 13) ^ gmul(a3, 9);
        s[4 * c + 1] = gmul(a0, 9) ^ gmul(a1, 14) ^ gmul(a2, 11) ^ gmul(a3, 13);
        s[4 * c + 2] = gmul(a0, 13) ^ gmul(a1, 9) ^ gmul(a2, 14) ^ gmul(a3, 11);
        s[4 * c + 3] = gmul(a0, 11) ^ gmul(a1, 13) ^ gmul(a2, 9) ^ gmul(a3, 14);
      } else {
        s[4 * c] = gmul(a0, 2) ^ gmul(a1, 3) ^ a2 ^ a3;
        s[4 * c + 1] = a0 ^ gmul(a1, 2) ^ gmul(a2, 3) ^ a3;
        s[4 * c + 2] = a0 ^ a1 ^ gmul(a2, 2) ^ gmul(a3, 3);
        s[4 * c + 3] = gmul(a0, 3) ^ a1 ^ a2 ^ gmul(a3, 2);
      }
    }
  }

  function aesCryptBlock(input, w, nr, encrypt) {
    var s = input.slice();
    aesAddRoundKey(s, w, encrypt ? 0 : nr);
    for (var r = 1; r < nr; r++) {
      if (encrypt) {
        for (var i = 0; i < 16; i++) s[i] = AES_SBOX[s[i]];
        aesShiftRows(s, false);
        aesMixColumns(s, false);
        aesAddRoundKey(s, w, r);
      } else {
        aesShiftRows(s, true);
        for (var j = 0; j < 16; j++) s[j] = AES_INV_SBOX[s[j]];
        aesAddRoundKey(s, w, nr - r);
        aesMixColumns(s, true);
      }
    }
    if (encrypt) {
      for (var k = 0; k < 16; k++) s[k] = AES_SBOX[s[k]];
      aesShiftRows(s, false);
      aesAddRoundKey(s, w, nr);
    } else {
      aesShiftRows(s, true);
      for (var m = 0; m < 16; m++) s[m] = AES_INV_SBOX[s[m]];
      aesAddRoundKey(s, w, 0);
    }
    return s;
  }

  /// GCM 末块：[0]64 || [lenBits]64（AAD 恒为空，SunJCE 常见用法）。
  function gcmLenBlock(bits) {
    var hi = Math.floor(bits / 4294967296);
    var lo = bits % 4294967296;
    return [0, 0, 0, 0, 0, 0, 0, 0,
      (hi >>> 24) & 255, (hi >>> 16) & 255, (hi >>> 8) & 255, hi & 255,
      (lo >>> 24) & 255, (lo >>> 16) & 255, (lo >>> 8) & 255, lo & 255];
  }

  /// GHASH 的 128 位 GF(2) 乘法（NIST SP 800-38D 4.1，MSB-first）。
  function gcmGhashMul(x, y) {
    var z = new Array(16);
    var v = y.slice();
    var i, j;
    for (i = 0; i < 16; i++) z[i] = 0;
    for (i = 0; i < 128; i++) {
      if ((x[i >> 3] >>> (7 - (i & 7))) & 1) {
        for (j = 0; j < 16; j++) z[j] ^= v[j];
      }
      var lsb = v[15] & 1;
      for (j = 15; j > 0; j--) {
        v[j] = ((v[j] >>> 1) | ((v[j - 1] & 1) << 7)) & 0xff;
      }
      v[0] = (v[0] >>> 1) & 0xff;
      if (lsb) v[0] ^= 0xe1;
    }
    return z;
  }

  function gcmGhash(h, data) {
    var y = new Array(16);
    var i, j;
    for (i = 0; i < 16; i++) y[i] = 0;
    for (i = 0; i < data.length; i += 16) {
      var blk = data.slice(i, i + 16);
      for (j = blk.length; j < 16; j++) blk.push(0);
      for (j = 0; j < 16; j++) y[j] ^= blk[j] & 0xff;
      y = gcmGhashMul(y, h);
    }
    return y;
  }

  /// AES-GCM：加密输出 ciphertext||tag，解密校验 tag（不符返回 null）。
  /// 96 位 IV 走 J0=IV||0^31||1；其余长度按 800-38D 用 GHASH 派生。
  function gcmRun(encrypt, data, key, iv, tagLenBits) {
    var ks = aesKeyExpand(key);
    if (!ks) return null;
    var tagLen = Math.floor((tagLenBits == null ? 128 : tagLenBits) / 8);
    if (tagLen < 4 || tagLen > 16) return null;
    if (!iv || iv.length === 0) return null;
    var i, j;
    var zero = new Array(16);
    for (i = 0; i < 16; i++) zero[i] = 0;
    var h = aesCryptBlock(zero, ks.w, ks.nr, true);
    var j0;
    if (iv.length === 12) {
      j0 = [];
      for (i = 0; i < 12; i++) j0.push(iv[i] & 0xff);
      j0.push(0, 0, 0, 1);
    } else {
      var ivb = [];
      for (i = 0; i < iv.length; i++) ivb.push(iv[i] & 0xff);
      while (ivb.length % 16 !== 0) ivb.push(0);
      j0 = gcmGhash(h, ivb.concat(gcmLenBlock(iv.length * 8)));
    }
    var body = [];
    for (i = 0; i < data.length; i++) body.push(data[i] & 0xff);
    var tag = null;
    if (!encrypt) {
      if (body.length < tagLen) return null;
      tag = body.slice(body.length - tagLen);
      body = body.slice(0, body.length - tagLen);
    }
    var ctr = j0.slice();
    var out = [];
    for (i = 0; i < body.length; i += 16) {
      // inc32：只递增末 4 字节。
      for (j = 15; j >= 12; j--) {
        ctr[j] = (ctr[j] + 1) & 0xff;
        if (ctr[j] !== 0) break;
      }
      var ek = aesCryptBlock(ctr, ks.w, ks.nr, true);
      var blk = body.slice(i, i + 16);
      for (j = 0; j < blk.length; j++) out.push(blk[j] ^ ek[j]);
    }
    var ct = encrypt ? out : body;
    var gd = ct.slice();
    while (gd.length % 16 !== 0) gd.push(0);
    var s = gcmGhash(h, gd.concat(gcmLenBlock(ct.length * 8)));
    var ej0 = aesCryptBlock(j0.slice(), ks.w, ks.nr, true);
    var full = [];
    for (i = 0; i < 16; i++) full.push((s[i] ^ ej0[i]) & 0xff);
    if (!encrypt) {
      var diff = 0;
      for (i = 0; i < tagLen; i++) diff |= tag[i] ^ full[i];
      if (diff !== 0) return null;
      return out.map(signedByte);
    }
    for (i = 0; i < tagLen; i++) out.push(full[i]);
    return out.map(signedByte);
  }

  /// CTR/OFB/CFB 流模式通用实现（JCE 口径）；encBlock 为分组加密函数
  /// （无填充，输入输出等长）。CFB 段长取 mode 尾随位数（'CFB' 缺省按
  /// 整块）；pad=true 时按分组填充/去填充。
  function streamCipherRun(encrypt, data, mode, pad, iv, blockSize, encBlock) {
    if (!iv || iv.length !== blockSize) return null;
    var seg = blockSize;
    if (mode.indexOf('CFB') === 0 && mode.length > 3) {
      var bits = parseInt(mode.substring(3), 10);
      if (!(bits > 0) || bits % 8 !== 0 || bits > blockSize * 8) return null;
      seg = bits / 8;
    }
    var buf = data.slice();
    var i, j;
    if (encrypt && pad) {
      var n = blockSize - (buf.length % blockSize);
      for (i = 0; i < n; i++) buf.push(n);
    }
    if (!encrypt && pad && buf.length % blockSize !== 0) return null;
    var out = [];
    if (mode === 'CTR') {
      var ctr = iv.map(function (b) { return b & 0xff; });
      for (i = 0; i < buf.length; i += blockSize) {
        var ksBlock = encBlock(ctr.slice());
        for (j = blockSize - 1; j >= 0; j--) {
          ctr[j] = (ctr[j] + 1) & 0xff;
          if (ctr[j] !== 0) break;
        }
        var blk = buf.slice(i, i + blockSize);
        for (j = 0; j < blk.length; j++) out.push(blk[j] ^ ksBlock[j]);
      }
    } else if (mode === 'OFB') {
      var reg = iv.map(function (b) { return b & 0xff; });
      for (i = 0; i < buf.length; i += blockSize) {
        reg = encBlock(reg.slice());
        var blk2 = buf.slice(i, i + blockSize);
        for (j = 0; j < blk2.length; j++) out.push(blk2[j] ^ reg[j]);
      }
    } else {
      var reg2 = iv.map(function (b) { return b & 0xff; });
      for (i = 0; i < buf.length; i += seg) {
        var chunk = buf.slice(i, i + seg);
        var eb = encBlock(reg2.slice());
        var produced = [];
        for (j = 0; j < chunk.length; j++) {
          produced.push(chunk[j] ^ eb[j]);
          out.push(produced[j]);
        }
        var feed = encrypt ? produced : chunk;
        reg2 = reg2.slice(feed.length).concat(feed);
      }
    }
    if (pad && !encrypt) {
      if (out.length === 0) return null;
      var padLen = out[out.length - 1];
      if (padLen < 1 || padLen > blockSize) return null;
      for (i = 0; i < padLen; i++) {
        if (out[out.length - 1 - i] !== padLen) return null;
      }
      out = out.slice(0, out.length - padLen);
    }
    return out.map(signedByte);
  }

  /// AES 主流程：返回字节数组（有符号口径），参数非法返回 null。
  function aesRun(encrypt, data, key, mode, pad, iv) {
    if (mode === 'GCM') return gcmRun(encrypt, data, key, iv, 128);
    var ks = aesKeyExpand(key);
    if (!ks) return null;
    var out = [];
    var i;
    if (mode === 'CTR' || mode === 'OFB' || mode.indexOf('CFB') === 0) {
      return streamCipherRun(encrypt, data, mode, pad, iv, 16,
          function (b) { return aesCryptBlock(b, ks.w, ks.nr, true); });
    }
    if (encrypt) {
      var buf = data.slice();
      if (pad) {
        var n = 16 - (buf.length % 16);
        for (i = 0; i < n; i++) buf.push(n);
      } else if (buf.length % 16 !== 0) {
        return null;
      }
      var prev = mode === 'CBC' ? iv : null;
      if (mode === 'CBC' && (!prev || prev.length !== 16)) return null;
      for (i = 0; i < buf.length; i += 16) {
        var blk = buf.slice(i, i + 16);
        if (prev) for (var j = 0; j < 16; j++) blk[j] ^= prev[j];
        var enc = aesCryptBlock(blk, ks.w, ks.nr, true);
        for (var k = 0; k < 16; k++) out.push(enc[k]);
        prev = enc;
      }
      return out.map(signedByte);
    }
    if (data.length % 16 !== 0) return null;
    var prevC = mode === 'CBC' ? iv : null;
    if (mode === 'CBC' && (!prevC || prevC.length !== 16)) return null;
    var plain = [];
    for (i = 0; i < data.length; i += 16) {
      var cb = data.slice(i, i + 16);
      var dec = aesCryptBlock(cb, ks.w, ks.nr, false);
      for (var q = 0; q < 16; q++) plain.push(dec[q] ^ (prevC ? prevC[q] : 0));
      if (prevC) prevC = cb;
    }
    if (pad) {
      var padLen = plain[plain.length - 1];
      if (padLen < 1 || padLen > 16) return null;
      for (i = 0; i < padLen; i++) {
        if (plain[plain.length - 1 - i] !== padLen) return null;
      }
      plain = plain.slice(0, plain.length - padLen);
    }
    return plain.map(signedByte);
  }

  /// transformation 解析：支持 ECB/CBC/CTR/CFB/OFB/GCM（CFB 缺省段长按
  /// 分组整块，mode 为 'CFB'；显式 'CFB8'/'CFB128' 等保留位数）。
  /// 与 legado SymmetricCryptoAndroid 一致：无 `/` 的算法名补
  /// ECB/PKCS5Padding（`"DES"` 即 `"DES/ECB/PKCS5Padding"`）。
  function aesParseTf(transformation, hasIv) {
    var raw = String(transformation || '');
    var t = raw.toUpperCase();
    if (t.indexOf('/GCM') >= 0) {
      // Java GCM 无填充，tag 长度由 GCMParameterSpec 决定（缺省 128）。
      return { mode: 'GCM', pad: false };
    }
    var pad = t.indexOf('NOPADDING') < 0;
    if (t.indexOf('/CTR') >= 0) return { mode: 'CTR', pad: pad };
    if (t.indexOf('/OFB') >= 0) return { mode: 'OFB', pad: pad };
    var mCfb = /\/CFB(\d*)/.exec(t);
    if (mCfb) {
      return { mode: mCfb[1] ? ('CFB' + mCfb[1]) : 'CFB', pad: pad };
    }
    var mode = t.indexOf('/ECB') >= 0 ? 'ECB'
        : (t.indexOf('/CBC') >= 0 ? 'CBC'
        : (raw.indexOf('/') < 0 ? 'ECB' : (hasIv ? 'CBC' : 'ECB')));
    return { mode: mode, pad: pad };
  }

  function aesDecodeInput(str, blockSize) {
    return cipherDecodeInput(str, blockSize || 16);
  }

  /// 密文输入解析（legado SymmetricCryptoAndroid.decrypt：hex 优先，其余
  /// base64）。hex 判定按块长收紧（整块字节数），避免把恰为 hex 字符集的
  /// base64 串误判；[blockSize] 为分组字节数（AES=16，DES=8）。
  function cipherDecodeInput(str, blockSize) {
    var s = String(str == null ? '' : str).trim();
    var hexUnit = blockSize * 2;
    var isHex = s.length > 0 && s.length % hexUnit === 0 && /^[0-9a-fA-F]+$/.test(s);
    var bytes = isHex ? hexToBytes(s) : bytesFromB64(s);
    var norm = bytes.map(function (b) { return b & 0xff; });
    if (norm.length % blockSize !== 0 && isHex) {
      norm = bytesFromB64(s).map(function (b) { return b & 0xff; });
    }
    return norm;
  }

  function aesCall(encrypt, str, key, transformation, ivStr) {
    var keyBytes = utf8Encode(String(key == null ? '' : key));
    var ivBytes = ivStr == null || ivStr === ''
        ? null : utf8Encode(String(ivStr));
    var tf = aesParseTf(transformation, ivBytes != null);
    if (!tf) return null;
    if (tf.mode !== 'ECB' && tf.mode !== 'GCM' &&
        (ivBytes == null || ivBytes.length !== 16)) {
      return null;
    }
    var stream = tf.mode === 'CTR' || tf.mode === 'OFB' ||
        tf.mode.indexOf('CFB') === 0;
    var data = encrypt
        ? utf8Encode(String(str == null ? '' : str))
        : aesDecodeInput(str, stream ? 1 : 16);
    if (!encrypt && data.length === 0) return null;
    return aesRun(encrypt, data, keyBytes, tf.mode, tf.pad, ivBytes);
  }

  // key/iv 以 base64 传入的 AES 变体（legado aesDecodeArgsBase64Str /
  // aesEncodeArgsBase64Str）：transformation 由 mode+padding 拼成。
  function aesArgsBase64(encrypt, data, keyB64, mode, padding, ivB64) {
    var key = bytesFromB64(String(keyB64 == null ? '' : keyB64))
        .map(function (b) { return b & 0xff; });
    var iv = bytesFromB64(String(ivB64 == null ? '' : ivB64))
        .map(function (b) { return b & 0xff; });
    // legado 拼 "AES/${mode}/${padding}" 后走 createSymmetricCrypto，
    // 模式可为 ECB/CBC/CTR/CFB/OFB。
    var tf = aesParseTf('AES/' + String(mode == null ? 'CBC' : mode) + '/' +
        String(padding == null ? 'PKCS5Padding' : padding), iv.length > 0);
    if (!tf) return '';
    if (tf.mode !== 'ECB' && tf.mode !== 'GCM' && iv.length !== 16) return '';
    var stream = tf.mode === 'CTR' || tf.mode === 'OFB' ||
        tf.mode.indexOf('CFB') === 0;
    var input = encrypt ? utf8Encode(String(data == null ? '' : data))
        : aesDecodeInput(data, stream ? 1 : 16);
    var out = aesRun(encrypt, input, key, tf.mode, tf.pad, iv);
    if (out == null) return '';
    return encrypt ? b64FromBytes(out.map(function (b) { return b & 0xff; }))
        : utf8Decode(out);
  }

  // 测试用：十六进制入出，ivHex 为空串表示 ECB。
  global.__aesHexTest = function (keyHex, ivHex, dataHex, encrypt) {
    var key = hexToBytes(keyHex).map(function (b) { return b & 0xff; });
    var data = hexToBytes(dataHex).map(function (b) { return b & 0xff; });
    var iv = ivHex ? hexToBytes(ivHex).map(function (b) { return b & 0xff; }) : null;
    var out = aesRun(!!encrypt, data, key, iv ? 'CBC' : 'ECB', false, iv);
    return out == null ? '' : bytesToHex(out);
  };

  global.__aesGcmHexTest = function (keyHex, ivHex, dataHex, encrypt,
      tagBits) {
    var key = hexToBytes(keyHex).map(function (b) { return b & 0xff; });
    var iv = hexToBytes(ivHex).map(function (b) { return b & 0xff; });
    var data = hexToBytes(dataHex).map(function (b) { return b & 0xff; });
    var out = gcmRun(!!encrypt, data, key, iv, tagBits || 128);
    return out == null ? '' : bytesToHex(out);
  };

  // 测试用：CTR/OFB/CFB 流模式十六进制入出（mode 形如 'CTR'/'OFB'/'CFB128'）。
  global.__aesModeHexTest = function (keyHex, ivHex, dataHex, mode, encrypt) {
    var key = hexToBytes(keyHex).map(function (b) { return b & 0xff; });
    var iv = hexToBytes(ivHex).map(function (b) { return b & 0xff; });
    var data = hexToBytes(dataHex).map(function (b) { return b & 0xff; });
    var out = aesRun(!!encrypt, data, key, String(mode), false, iv);
    return out == null ? '' : bytesToHex(out);
  };

  global.__desModeHexTest = function (keyHex, ivHex, dataHex, mode, encrypt,
      triple) {
    var key = hexToBytes(keyHex).map(function (b) { return b & 0xff; });
    var iv = hexToBytes(ivHex).map(function (b) { return b & 0xff; });
    var data = hexToBytes(dataHex).map(function (b) { return b & 0xff; });
    var out = desRun(!!encrypt, data, key, String(mode), false, iv, !!triple);
    return out == null ? '' : bytesToHex(out);
  };

  global.__desHexTest = function (keyHex, ivHex, dataHex, encrypt, triple) {
    var key = hexToBytes(keyHex).map(function (b) { return b & 0xff; });
    var data = hexToBytes(dataHex).map(function (b) { return b & 0xff; });
    var iv = ivHex ? hexToBytes(ivHex).map(function (b) { return b & 0xff; }) : null;
    var out = desRun(!!encrypt, data, key, iv ? 'CBC' : 'ECB', false, iv, !!triple);
    return out == null ? '' : bytesToHex(out);
  };

  // ── TTF（字体反爬：queryTTF / replaceFont） ──
  // 纯 JS 解析 sfnt 表（head/maxp/cmap[format 4|12]/loca/glyf），按「字形轮廓
  // 字节」做字符映射——与 legado QueryTTF 的 glyf 比较口径一致。
  // 输入支持 base64 / 字节数组 / http(s) URL；URL 走二进制重放
  // （__ajaxBytesCache）：未命中登记后返回 null（本轮 replaceFont 原样返回），
  // 下一轮重放命中再解析。
  //
  // 本 IIFE 先于注入对象预置脚本执行，syOp 尚不存在；按同一排空协议
  // （__javaVars 的 __syop_* 键）自行登记。
  var __syopJN = 0;
  function syJavaOp(op, a, b) {
    var v = global.__javaVars;
    if (!v || typeof v !== 'object') {
      v = {};
      global.__javaVars = v;
    }
    __syopJN++;
    v['__syop_j' + __syopJN] = JSON.stringify(
        { op: op, a: a == null ? '' : a, b: b == null ? '' : b });
  }
  var __ttfCache = {};

  function b64ToU8(s) {
    var v = bytesFromB64(s);
    var u = new Uint8Array(v.length);
    for (var i = 0; i < v.length; i++) u[i] = v[i] & 0xff;
    return u;
  }

  function ttfBytes(data) {
    if (data == null) return null;
    if (typeof data === 'string') {
      var s = String(data);
      var comma = s.indexOf('base64,');
      if (comma >= 0) s = s.substring(comma + 7);
      s = s.replace(/[\s\r\n]/g, '');
      if (s.length < 16) return null;
      return b64ToU8(s);
    }
    if (typeof data === 'object' && typeof data.length === 'number') {
      var u = new Uint8Array(data.length);
      for (var i = 0; i < data.length; i++) u[i] = data[i] & 0xff;
      return u;
    }
    return null;
  }

  function ttfU8(b, o) { return b[o] & 0xff; }
  function ttfU16(b, o) { return (ttfU8(b, o) << 8) | ttfU8(b, o + 1); }
  function ttfI16(b, o) {
    var v = ttfU16(b, o);
    return (v & 0x8000) ? v - 0x10000 : v;
  }
  function ttfU32(b, o) {
    return (((ttfU8(b, o) << 24) | (ttfU8(b, o + 1) << 16) |
        (ttfU8(b, o + 2) << 8) | ttfU8(b, o + 3)) >>> 0);
  }
  function ttfTag(b, o) {
    return String.fromCharCode(ttfU8(b, o), ttfU8(b, o + 1),
        ttfU8(b, o + 2), ttfU8(b, o + 3));
  }
  function ttfHash(bytes) {
    var h = 2166136261;
    for (var i = 0; i < bytes.length; i++) {
      h ^= bytes[i];
      h = (h * 16777619) >>> 0;
    }
    return bytes.length + ':' + h.toString(16);
  }

  function ttfParse(bytes) {
    if (!bytes || bytes.length < 12) return null;
    var numTables = ttfU16(bytes, 4);
    if (numTables <= 0 || numTables > 64) return null;
    var tables = {};
    for (var i = 0; i < numTables; i++) {
      var o = 12 + i * 16;
      if (o + 16 > bytes.length) break;
      tables[ttfTag(bytes, o)] = {
        offset: ttfU32(bytes, o + 8),
        length: ttfU32(bytes, o + 12),
      };
    }
    var head = tables['head'], maxp = tables['maxp'];
    var cmap = tables['cmap'], loca = tables['loca'], glyf = tables['glyf'];
    if (!head || !maxp || !cmap || !loca || !glyf) return null;

    var numGlyphs = ttfU16(bytes, maxp.offset + 4);
    if (numGlyphs <= 0) return null;
    var locFormat = ttfI16(bytes, head.offset + 50);

    // cmap：优先 format 12（含增补平面），否则 format 4（BMP）
    var map = {};
    var count = 0;
    var nSub = ttfU16(bytes, cmap.offset + 2);
    var best = -1, bestFmt = 0;
    for (var s = 0; s < nSub; s++) {
      var rec = cmap.offset + 4 + s * 8;
      if (rec + 8 > bytes.length) break;
      var sub = cmap.offset + ttfU32(bytes, rec + 4);
      if (sub + 2 > bytes.length) continue;
      var fmt = ttfU16(bytes, sub);
      if (fmt === 12 && bestFmt < 12) { best = sub; bestFmt = 12; }
      else if (fmt === 4 && bestFmt < 4) { best = sub; bestFmt = 4; }
    }
    if (best < 0) return null;

    if (bestFmt === 12) {
      var nGroups = ttfU32(bytes, best + 12);
      for (var g = 0; g < nGroups && count < 0x20000; g++) {
        var go = best + 16 + g * 12;
        if (go + 12 > bytes.length) break;
        var sc = ttfU32(bytes, go);
        var ec = ttfU32(bytes, go + 4);
        var sg = ttfU32(bytes, go + 8);
        if (ec < sc || ec - sc > 0x10000) continue;
        for (var c = sc; c <= ec; c++) {
          map[c] = sg + (c - sc);
          count++;
        }
      }
    } else {
      var segX2 = ttfU16(bytes, best + 6);
      var segs = segX2 >> 1;
      var endO = best + 14;
      var startO = endO + segX2 + 2;
      var deltaO = startO + segX2;
      var rangeO = deltaO + segX2;
      for (var k = 0; k < segs && count < 0x20000; k++) {
        var endC = ttfU16(bytes, endO + k * 2);
        var startC = ttfU16(bytes, startO + k * 2);
        var delta = ttfU16(bytes, deltaO + k * 2);
        var ro = ttfU16(bytes, rangeO + k * 2);
        if (startC > endC) continue;
        for (var cc = startC; cc <= endC; cc++) {
          if (cc === 0xffff) break;
          var gid;
          if (ro === 0) {
            gid = (cc + delta) & 0xffff;
          } else {
            var gi = rangeO + k * 2 + ro + (cc - startC) * 2;
            if (gi + 2 > bytes.length) continue;
            gid = ttfU16(bytes, gi);
            if (gid !== 0) gid = (gid + delta) & 0xffff;
          }
          if (gid) {
            map[cc] = gid;
            count++;
          }
        }
      }
    }
    if (count === 0) return null;

    function locaAt(idx) {
      var off = loca.offset + (locFormat === 0 ? idx * 2 : idx * 4);
      if (off + (locFormat === 0 ? 2 : 4) > bytes.length) return -1;
      return locFormat === 0 ? ttfU16(bytes, off) * 2 : ttfU32(bytes, off);
    }

    function glyfOf(gid) {
      if (!gid || gid >= numGlyphs) return null;
      var s = locaAt(gid);
      var e = locaAt(gid + 1);
      if (s < 0 || e <= s) return null;
      var start = glyf.offset + s;
      var end = glyf.offset + e;
      if (start < 0 || end > bytes.length) return null;
      return bytes.subarray(start, end);
    }

    var reverse = null;

    return {
      numGlyphs: numGlyphs,
      getGlyphId: function (cp) { return map[cp] || 0; },
      getGlyfByUnicode: function (cp) { return glyfOf(map[cp]); },
      hashOf: function (g) { return ttfHash(g); },
      getUnicodeByGlyf: function (g) {
        if (!g || !g.length) return -1;
        if (!reverse) {
          reverse = {};
          for (var code in map) {
            var gg = glyfOf(map[code]);
            if (gg && gg.length) {
              var hh = ttfHash(gg);
              if (reverse[hh] === undefined) reverse[hh] = Number(code);
            }
          }
        }
        var h2 = ttfHash(g);
        return reverse[h2] === undefined ? -1 : reverse[h2];
      },
    };
  }

  function ttfFromCodePoint(cp) {
    if (cp <= 0xffff) return String.fromCharCode(cp);
    cp -= 0x10000;
    return String.fromCharCode(0xd800 + (cp >> 10), 0xdc00 + (cp & 0x3ff));
  }

  function ttfReplaceFont(text, errFont, okFont, filter) {
    var s = String(text == null ? '' : text);
    if (!errFont || !okFont || !s) return s;
    var out = '';
    var i = 0;
    while (i < s.length) {
      var cp = s.charCodeAt(i);
      var step = 1;
      if (cp >= 0xd800 && cp <= 0xdbff && i + 1 < s.length) {
        var lo = s.charCodeAt(i + 1);
        if (lo >= 0xdc00 && lo <= 0xdfff) {
          cp = 0x10000 + ((cp - 0xd800) << 10) + (lo - 0xdc00);
          step = 2;
        }
      }
      var g = errFont.getGlyfByUnicode(cp);
      var u = (g && g.length) ? okFont.getUnicodeByGlyf(g) : -1;
      if (u >= 0) {
        out += ttfFromCodePoint(u);
      } else if (!filter) {
        out += ttfFromCodePoint(cp);
      }
      i += step;
    }
    return out;
  }

  // ── DES / DESede（legado createSymmetricCrypto("DES/CBC/PKCS5Padding")）──
  // FIPS 46-3 纯 JS 实现（位数组口径）；ECB/CBC + PKCS5/NoPadding。
  var DES_IP = [58,50,42,34,26,18,10,2,60,52,44,36,28,20,12,4,
    62,54,46,38,30,22,14,6,64,56,48,40,32,24,16,8,
    57,49,41,33,25,17,9,1,59,51,43,35,27,19,11,3,
    61,53,45,37,29,21,13,5,63,55,47,39,31,23,15,7];
  var DES_FP = [40,8,48,16,56,24,64,32,39,7,47,15,55,23,63,31,
    38,6,46,14,54,22,62,30,37,5,45,13,53,21,61,29,
    36,4,44,12,52,20,60,28,35,3,43,11,51,19,59,27,
    34,2,42,10,50,18,58,26,33,1,41,9,49,17,57,25];
  var DES_E = [32,1,2,3,4,5,4,5,6,7,8,9,8,9,10,11,12,13,12,13,14,15,16,17,
    16,17,18,19,20,21,20,21,22,23,24,25,24,25,26,27,28,29,28,29,30,31,32,1];
  var DES_P = [16,7,20,21,29,12,28,17,1,15,23,26,5,18,31,10,
    2,8,24,14,32,27,3,9,19,13,30,6,22,11,4,25];
  var DES_PC1 = [57,49,41,33,25,17,9,1,58,50,42,34,26,18,10,2,59,51,43,35,
    27,19,11,3,60,52,44,36,63,55,47,39,31,23,15,7,62,54,46,38,30,22,
    14,6,61,53,45,37,29,21,13,5,28,20,12,4];
  var DES_PC2 = [14,17,11,24,1,5,3,28,15,6,21,10,23,19,12,4,26,8,16,7,27,20,
    13,2,41,52,31,37,47,55,30,40,51,45,33,48,44,49,39,56,34,53,46,42,50,36,
    29,32];
  var DES_SHIFTS = [1,1,2,2,2,2,2,2,1,2,2,2,2,2,2,1];
  var DES_S = [
    [14,4,13,1,2,15,11,8,3,10,6,12,5,9,0,7,0,15,7,4,14,2,13,1,10,6,12,11,
      9,5,3,8,4,1,14,8,13,6,2,11,15,12,9,7,3,10,5,0,15,12,8,2,4,9,1,7,
      5,11,3,14,10,0,6,13],
    [15,1,8,14,6,11,3,4,9,7,2,13,12,0,5,10,3,13,4,7,15,2,8,14,12,0,1,10,
      6,9,11,5,0,14,7,11,10,4,13,1,5,8,12,6,9,3,2,15,13,8,10,1,3,15,4,2,
      11,6,7,12,0,5,14,9],
    [10,0,9,14,6,3,15,5,1,13,12,7,11,4,2,8,13,7,0,9,3,4,6,10,2,8,5,14,
      12,11,15,1,13,6,4,9,8,15,3,0,11,1,2,12,5,10,14,7,1,10,13,0,6,9,8,7,
      4,15,14,3,11,5,2,12],
    [7,13,14,3,0,6,9,10,1,2,8,5,11,12,4,15,13,8,11,5,6,15,0,3,4,7,2,12,
      1,10,14,9,10,6,9,0,12,11,7,13,15,1,3,14,5,2,8,4,3,15,0,6,10,1,13,8,
      9,4,5,11,12,7,2,14],
    [2,12,4,1,7,10,11,6,8,5,3,15,13,0,14,9,14,11,2,12,4,7,13,1,5,0,15,10,
      3,9,8,6,4,2,1,11,10,13,7,8,15,9,12,5,6,3,0,14,11,8,12,7,1,14,2,13,
      6,15,0,9,10,4,5,3],
    [12,1,10,15,9,2,6,8,0,13,3,4,14,7,5,11,10,15,4,2,7,12,9,5,6,1,13,14,
      0,11,3,8,9,14,15,5,2,8,12,3,7,0,4,10,1,13,11,6,4,3,2,12,9,5,15,10,
      11,14,1,7,6,0,8,13],
    [4,11,2,14,15,0,8,13,3,12,9,7,5,10,6,1,13,0,11,7,4,9,1,10,14,3,5,12,
      2,15,8,6,1,4,11,13,12,3,7,14,10,15,6,8,0,5,9,2,6,11,13,8,1,4,10,7,
      9,5,0,15,14,2,3,12],
    [13,2,8,4,6,15,11,1,10,9,3,14,5,0,12,7,1,15,13,8,10,3,7,4,12,5,6,11,
      0,14,9,2,7,11,4,1,9,12,14,2,0,6,10,13,15,3,5,8,2,1,14,7,4,10,8,13,
      15,12,9,0,3,5,6,11]
  ];

  function desBytesToBits(bytes) {
    var bits = [];
    for (var i = 0; i < bytes.length; i++) {
      for (var b = 7; b >= 0; b--) bits.push((bytes[i] >> b) & 1);
    }
    return bits;
  }

  function desBitsToBytes(bits) {
    var out = [];
    for (var i = 0; i < bits.length; i += 8) {
      var v = 0;
      for (var b = 0; b < 8; b++) v = (v << 1) | (bits[i + b] || 0);
      out.push(v);
    }
    return out;
  }

  function desPermute(bits, table) {
    var out = [];
    for (var i = 0; i < table.length; i++) out.push(bits[table[i] - 1]);
    return out;
  }

  function desKeySchedule(keyBytes) {
    var keyBits = desBytesToBits(keyBytes.slice(0, 8));
    var cd = desPermute(keyBits, DES_PC1);
    var c = cd.slice(0, 28), d = cd.slice(28);
    var subkeys = [];
    for (var r = 0; r < 16; r++) {
      for (var s = 0; s < DES_SHIFTS[r]; s++) {
        c.push(c.shift());
        d.push(d.shift());
      }
      subkeys.push(desPermute(c.concat(d), DES_PC2));
    }
    return subkeys;
  }

  function desFeistel(r, subkey) {
    var e = desPermute(r, DES_E);
    for (var i = 0; i < 48; i++) e[i] ^= subkey[i];
    var out = [];
    for (var b = 0; b < 8; b++) {
      var o = b * 6;
      var row = (e[o] << 1) | e[o + 5];
      var col = (e[o + 1] << 3) | (e[o + 2] << 2) | (e[o + 3] << 1) | e[o + 4];
      var v = DES_S[b][row * 16 + col];
      out.push((v >> 3) & 1, (v >> 2) & 1, (v >> 1) & 1, v & 1);
    }
    return desPermute(out, DES_P);
  }

  function desCryptBits(blockBits, subkeys, decrypt) {
    var ip = desPermute(blockBits, DES_IP);
    var l = ip.slice(0, 32), r = ip.slice(32);
    for (var i = 0; i < 16; i++) {
      var sk = subkeys[decrypt ? 15 - i : i];
      var f = desFeistel(r, sk);
      var next = [];
      for (var j = 0; j < 32; j++) next.push(l[j] ^ f[j]);
      l = r;
      r = next;
    }
    return desPermute(r.concat(l), DES_FP);
  }

  /// DES/DESede 主流程（8 字节块）：返回有符号字节数组，参数非法返回 null。
  function desRun(encrypt, data, key, mode, pad, iv, triple) {
    var keyLen = triple ? (key.length >= 24 ? 24 : 16) : 8;
    if (key.length < keyLen) return null;
    var ks1 = desKeySchedule(key.slice(0, 8));
    var ks2 = triple ? desKeySchedule(key.slice(8, 16)) : null;
    var ks3 = triple
        ? desKeySchedule(key.slice(keyLen >= 24 ? 16 : 0, keyLen >= 24 ? 24 : 8))
        : null;
    function cryptBlock(bytes8, decrypt) {
      var bits = desBytesToBits(bytes8);
      if (!triple) return desBitsToBytes(desCryptBits(bits, ks1, decrypt));
      // DESede = E_k1 → D_k2 → E_k3（解密反向）；各步保持位数组形态。
      var b2 = decrypt
          ? desCryptBits(bits, ks3, true)
          : desCryptBits(bits, ks1, false);
      var b3 = desCryptBits(b2, ks2, !decrypt);
      return desBitsToBytes(
          decrypt ? desCryptBits(b3, ks1, true) : desCryptBits(b3, ks3, false));
    }
    if (mode === 'CTR' || mode === 'OFB' || mode.indexOf('CFB') === 0) {
      return streamCipherRun(encrypt, data, mode, pad, iv, 8,
          function (b) { return cryptBlock(b, false); });
    }
    var out = [];
    var i;
    if (encrypt) {
      var buf = data.slice();
      if (pad) {
        var n = 8 - (buf.length % 8);
        for (i = 0; i < n; i++) buf.push(n);
      } else if (buf.length % 8 !== 0) {
        return null;
      }
      var prev = mode === 'CBC' ? iv : null;
      if (mode === 'CBC' && (!prev || prev.length !== 8)) return null;
      for (i = 0; i < buf.length; i += 8) {
        var blk = buf.slice(i, i + 8);
        if (prev) for (var j = 0; j < 8; j++) blk[j] ^= prev[j];
        var enc = cryptBlock(blk, false);
        for (var k = 0; k < 8; k++) out.push(enc[k]);
        prev = enc;
      }
      return out.map(signedByte);
    }
    if (data.length % 8 !== 0) return null;
    var prevC = mode === 'CBC' ? iv : null;
    if (mode === 'CBC' && (!prevC || prevC.length !== 8)) return null;
    var plain = [];
    for (i = 0; i < data.length; i += 8) {
      var cb = data.slice(i, i + 8);
      var dec = cryptBlock(cb, true);
      for (var q = 0; q < 8; q++) plain.push(dec[q] ^ (prevC ? prevC[q] : 0));
      if (prevC) prevC = cb;
    }
    if (pad) {
      var padLen = plain[plain.length - 1];
      if (padLen < 1 || padLen > 8) return null;
      for (i = 0; i < padLen; i++) {
        if (plain[plain.length - 1 - i] !== padLen) return null;
      }
      plain = plain.slice(0, plain.length - padLen);
    }
    return plain.map(signedByte);
  }

  // ── SymmetricCrypto（legado java.createSymmetricCrypto） ──
  // transformation 形如 "AES/CBC/PKCS5Padding" / "DES/ECB/PKCS5Padding" /
  // "DESede/CBC/PKCS5Padding"；支持 ECB/CBC/CTR/CFB/OFB（GCM 仅 AES）。
  // key/iv/data 支持字符串或字节数组（legado ByteArray 有符号口径）。
  function makeSymmetricCrypto(transformation, key, iv) {
    var empty = {
      decrypt: function (data) { return []; },
      decryptStr: function (data) { return ''; },
      encrypt: function (str) { return []; },
      encryptBase64: function (str) { return ''; },
      encryptHex: function (str) { return ''; },
    };
    var algo = String(transformation == null ? '' : transformation)
        .split('/')[0].toUpperCase();
    // legado `SymmetricCryptoAndroid`：key 为 null 时走 KeyGenerator 生成
    // 随机密钥（AES 128 / DES 64 / DESede 192），不是空密钥。
    var keyBytes;
    if (key == null) {
      var keyLen = (algo === 'DES') ? 8
          : (algo === 'DESEDE' || algo === 'TRIPLEDES') ? 24 : 16;
      keyBytes = [];
      for (var ki = 0; ki < keyLen; ki++) {
        keyBytes.push((Math.random() * 256) | 0);
      }
    } else {
      keyBytes = anyToBytes(key);
    }
    var ivBytes = (iv == null || iv === '') ? null : anyToBytes(iv);
    var tf = aesParseTf(transformation, ivBytes != null);
    if (!tf) return empty;
    var blockSize = 16;
    var run;
    var stream = tf.mode === 'CTR' || tf.mode === 'OFB' ||
        tf.mode.indexOf('CFB') === 0;
    var hexUnit = stream ? 1 : blockSize;
    if (algo === 'DES' || algo === 'DESEDE' || algo === 'TRIPLEDES') {
      var triple = algo !== 'DES';
      blockSize = 8;
      hexUnit = stream ? 1 : blockSize;
      // legado SymmetricCryptoAndroid.normalizedKey：DES 取前 8 字节，
      // DESede 取前 24 字节；DESede 另接受 16 字节双密钥形态。
      if (triple ? (keyBytes.length < 16) : (keyBytes.length < 8)) return empty;
      if (tf.mode !== 'ECB' && tf.mode !== 'GCM' &&
          (ivBytes == null || ivBytes.length !== 8)) {
        return empty;
      }
      run = function (encrypt, bytes) {
        return desRun(encrypt, bytes, keyBytes, tf.mode, tf.pad, ivBytes, triple);
      };
    } else {
      if (tf.mode !== 'ECB' && tf.mode !== 'GCM' &&
          (ivBytes == null || ivBytes.length !== 16)) {
        return empty;
      }
      run = function (encrypt, bytes) {
        return aesRun(encrypt, bytes, keyBytes, tf.mode, tf.pad, ivBytes);
      };
    }
    return {
      decrypt: function (data) {
        var bytes = (data && typeof data === 'object' &&
            typeof data.length === 'number')
            ? anyToBytes(data)
            : cipherDecodeInput(data, hexUnit);
        var out = run(false, bytes);
        return out == null ? [] : out;
      },
      decryptStr: function (data) {
        var bytes = (data && typeof data === 'object' &&
            typeof data.length === 'number')
            ? anyToBytes(data)
            : cipherDecodeInput(data, hexUnit);
        var out = run(false, bytes);
        return out == null ? '' : utf8Decode(out);
      },
      encrypt: function (str) {
        var out = run(true, utf8Encode(String(str == null ? '' : str)));
        return out == null ? [] : out;
      },
      encryptBase64: function (str) {
        var out = run(true, utf8Encode(String(str == null ? '' : str)));
        return out == null ? ''
            : b64FromBytes(out.map(function (b) { return b & 0xff; }));
      },
      encryptHex: function (str) {
        var out = run(true, utf8Encode(String(str == null ? '' : str)));
        return out == null ? '' : bytesToHex(out);
      },
    };
  }

  // ── AsymmetricCrypto（legado java.createAsymmetricCrypto） ──
  // 密钥编码对齐 JCE：公钥 X.509 SPKI（X509EncodedKeySpec）、私钥 PKCS#8
  // （PKCS8EncodedKeySpec），另宽容接受裸 PKCS#1 DER。运算与填充在宿主侧
  // 完成（JCE/Conscrypt 口径：PKCS#1 v1.5、NoPadding、OAEP-SHA*，OAEP
  // 默认 MGF1 同主摘要、空标签；分块宽度同 legado）。QuickJS 无 BigInt，
  // 纯 JS 私钥模幂要数秒，故与规则桥同用确定性重放：脚本按（变换/方向/
  // 密钥/数据）登记待办并返回类型占位，JsEngine 在宿主用 Dart BigInt
  // 计算后回填 __asymCache 并重跑，本轮命中缓存即得真值。本节的大数实现
  // 仅供下方 Signature（SHA256withRSA）验签使用。
  function bnTrim(a) {
    var n = a.length;
    while (n > 1 && a[n - 1] === 0) n--;
    if (n !== a.length) a.length = n;
    return a;
  }

  // 无符号大端字节 → 小端 2^16 limb。
  function bnFromBytes(bytes) {
    var limbs = [];
    var i = bytes.length;
    while (i > 0) {
      var lo = bytes[--i] & 0xff;
      var hi = i > 0 ? (bytes[--i] & 0xff) : 0;
      limbs.push((hi << 8) | lo);
    }
    if (limbs.length === 0) limbs.push(0);
    return bnTrim(limbs);
  }

  // limb → 定长大端无符号字节（RSA 块长度）。
  function bnToBytes(bn, len) {
    var le = [];
    for (var i = 0; i < bn.length; i++) {
      le.push(bn[i] & 0xff);
      le.push((bn[i] >>> 8) & 0xff);
    }
    if (len == null) len = le.length;
    if (le.length > len) throw new Error('Integer too large');
    var out = [];
    for (var j = len - 1; j >= 0; j--) {
      out.push(j < le.length ? le[j] : 0);
    }
    return out;
  }

  function bnBitLength(a) {
    return (a.length - 1) * 16 + (32 - Math.clz32(a[a.length - 1]));
  }

  function bnCmp(a, b) {
    var la = a.length, lb = b.length;
    while (la > 1 && a[la - 1] === 0) la--;
    while (lb > 1 && b[lb - 1] === 0) lb--;
    if (la !== lb) return la < lb ? -1 : 1;
    for (var i = la - 1; i >= 0; i--) {
      if (a[i] !== b[i]) return a[i] < b[i] ? -1 : 1;
    }
    return 0;
  }

  function bnSub(a, b) {
    var r = [];
    var borrow = 0;
    for (var i = 0; i < a.length; i++) {
      var v = a[i] - (i < b.length ? b[i] : 0) - borrow;
      if (v < 0) {
        v += 65536;
        borrow = 1;
      } else {
        borrow = 0;
      }
      r.push(v);
    }
    return bnTrim(r);
  }

  function bnDoubleMod(a, n) {
    var r = [];
    var carry = 0;
    for (var i = 0; i < a.length; i++) {
      var v = a[i] * 2 + carry;
      r.push(v & 0xffff);
      carry = v >>> 16;
    }
    if (carry) r.push(carry);
    bnTrim(r);
    if (bnCmp(r, n) >= 0) r = bnSub(r, n);
    return r;
  }

  function bnModInverse16(a) {
    var t = 0, newT = 1, r = 65536, newR = a;
    while (newR !== 0) {
      var q = Math.floor(r / newR);
      var tmp = t - q * newT;
      t = newT;
      newT = tmp;
      tmp = r - q * newR;
      r = newR;
      newR = tmp;
    }
    return t < 0 ? t + 65536 : t;
  }

  // Montgomery 上下文：R = 2^(16k) mod n，R2 = R^2 mod n（32k 次翻倍，
  // 每个密钥只建一次）。
  function montContext(n) {
    if ((n[0] & 1) === 0) throw new Error('RSA modulus must be odd');
    var k = n.length;
    var n0inv = (65536 - bnModInverse16(n[0])) & 0xffff;
    var r = [1];
    for (var i = 0; i < 16 * k; i++) r = bnDoubleMod(r, n);
    var r2 = r;
    for (var i = 0; i < 16 * k; i++) r2 = bnDoubleMod(r2, n);
    return { n: n, n0inv: n0inv, R: r, R2: r2 };
  }

  // CIOS Montgomery 乘法（HAC 14.36，结果 < 2n，减一次）。
  function montMul(a, b, n, n0inv) {
    var k = n.length;
    var t = new Array(k + 2);
    for (var i = 0; i < t.length; i++) t[i] = 0;
    for (var i = 0; i < k; i++) {
      var bi = i < b.length ? b[i] : 0;
      var carry = 0;
      for (var j = 0; j < k; j++) {
        var aj = j < a.length ? a[j] : 0;
        var uv = t[j] + aj * bi + carry;
        t[j] = uv & 0xffff;
        carry = Math.floor(uv / 65536);
      }
      var sum = t[k] + carry;
      t[k] = sum & 0xffff;
      t[k + 1] = Math.floor(sum / 65536);

      var m = (t[0] * n0inv) & 0xffff;
      var uv0 = t[0] + m * n[0];
      var c = Math.floor(uv0 / 65536);
      for (var j = 1; j < k; j++) {
        var uv2 = t[j] + m * n[j] + c;
        t[j - 1] = uv2 & 0xffff;
        c = Math.floor(uv2 / 65536);
      }
      var s2 = t[k] + c;
      t[k - 1] = s2 & 0xffff;
      t[k] = t[k + 1] + Math.floor(s2 / 65536);
    }
    var r = [];
    for (var idx = 0; idx <= k; idx++) r.push(t[idx]);
    if (r[k] !== 0 || bnCmp(r, n) >= 0) r = bnSub(r, n);
    return bnTrim(r);
  }

  function bnModPow(base, exp, ctx) {
    var n = ctx.n, n0inv = ctx.n0inv;
    if (bnCmp(base, n) >= 0) {
      throw new Error('Message is larger than modulus');
    }
    if (bnCmp(exp, [0]) === 0) return [1];
    var x = montMul(base, ctx.R2, n, n0inv);
    var acc = ctx.R.slice();
    for (var i = exp.length - 1; i >= 0; i--) {
      var limb = exp[i];
      for (var b = 15; b >= 0; b--) {
        acc = montMul(acc, acc, n, n0inv);
        if ((limb >>> b) & 1) acc = montMul(acc, x, n, n0inv);
      }
    }
    return montMul(acc, [1], n, n0inv);
  }

  // ── DER（X.509 SPKI / PKCS#8 / 裸 PKCS#1） ──
  function derRead(bytes, pos) {
    if (pos < 0 || pos + 2 > bytes.length) return null;
    var tag = bytes[pos] & 0xff;
    var len = bytes[pos + 1] & 0xff;
    var p = pos + 2;
    if (len & 0x80) {
      var cnt = len & 0x7f;
      if (cnt === 0 || cnt > 4 || p + cnt > bytes.length) return null;
      len = 0;
      for (var i = 0; i < cnt; i++) len = len * 256 + (bytes[p++] & 0xff);
    }
    if (p + len > bytes.length) return null;
    return { tag: tag, start: p, end: p + len, next: p + len };
  }

  function derChildren(bytes, node) {
    var out = [];
    var p = node.start;
    while (p < node.end) {
      var child = derRead(bytes, p);
      if (!child || child.next > node.end) return null;
      out.push(child);
      p = child.next;
    }
    return out;
  }

  function derIntBytes(bytes, node) {
    if (!node || node.tag !== 0x02) return null;
    var out = [];
    for (var i = node.start; i < node.end; i++) out.push(bytes[i] & 0xff);
    while (out.length > 1 && out[0] === 0) out.shift();
    return out.length ? out : null;
  }

  function rsaPublicFromSeq(bytes, seq) {
    var kids = derChildren(bytes, seq);
    if (!kids || kids.length < 2) return null;
    var n = derIntBytes(bytes, kids[0]);
    var e = derIntBytes(bytes, kids[1]);
    return (n && e) ? { n: n, e: e } : null;
  }

  function rsaParsePublicKey(bytes) {
    var top = derRead(bytes, 0);
    if (!top || top.tag !== 0x30) return null;
    var kids = derChildren(bytes, top);
    if (!kids || kids.length === 0) return null;
    // 裸 PKCS#1 RSAPublicKey：SEQUENCE { INTEGER n, INTEGER e }。
    if (kids[0].tag === 0x02) return rsaPublicFromSeq(bytes, top);
    // X.509 SPKI：SEQUENCE { AlgorithmIdentifier, BIT STRING }。
    if (kids[0].tag !== 0x30) return null;
    var bit = null;
    for (var i = 1; i < kids.length; i++) {
      if (kids[i].tag === 0x03) { bit = kids[i]; break; }
    }
    if (!bit || bit.start >= bit.end || (bytes[bit.start] & 0xff) !== 0) {
      return null;
    }
    var inner = derRead(bytes, bit.start + 1);
    if (!inner || inner.tag !== 0x30) return null;
    return rsaPublicFromSeq(bytes, inner);
  }

  function rsaPrivateFromSeq(bytes, seq) {
    var kids = derChildren(bytes, seq);
    if (!kids || kids.length < 4 || kids[0].tag !== 0x02) return null;
    var n = derIntBytes(bytes, kids[1]);
    var e = derIntBytes(bytes, kids[2]);
    var d = derIntBytes(bytes, kids[3]);
    if (!n || !e || !d) return null;
    // CRT 参数（p, q）供宿主侧私钥运算加速；缺失时退回 d 模幂。
    var p = kids.length > 4 ? derIntBytes(bytes, kids[4]) : null;
    var q = kids.length > 5 ? derIntBytes(bytes, kids[5]) : null;
    return { n: n, e: e, d: d, p: p, q: q };
  }

  function rsaParsePrivateKey(bytes) {
    var top = derRead(bytes, 0);
    if (!top || top.tag !== 0x30) return null;
    var kids = derChildren(bytes, top);
    if (!kids || kids.length === 0) return null;
    // 裸 PKCS#1 RSAPrivateKey：version INTEGER 后紧跟 modulus INTEGER；
    // PKCS#8 的第二项是 AlgorithmIdentifier SEQUENCE。
    if (kids[0].tag === 0x02 && kids.length >= 2 && kids[1].tag === 0x02) {
      return rsaPrivateFromSeq(bytes, top);
    }
    var oct = null;
    for (var i = 1; i < kids.length; i++) {
      if (kids[i].tag === 0x04) { oct = kids[i]; break; }
    }
    if (!oct) return null;
    var inner = derRead(bytes, oct.start);
    if (!inner || inner.tag !== 0x30) return null;
    return rsaPrivateFromSeq(bytes, inner);
  }

  // ── PKCS#1 v1.5（JCE 口径：公钥加密/私钥解密为 type 2，私钥加密/
  // 公钥解密为 type 1） ──
  function rsaPkcs1Pad(data, k, blockType) {
    if (data.length > k - 11) {
      throw new Error('Data must not be longer than ' + (k - 11) + ' bytes');
    }
    var em = [0x00, blockType];
    var psLen = k - 3 - data.length;
    for (var i = 0; i < psLen; i++) {
      em.push(blockType === 1
          ? 0xff : 1 + Math.floor(Math.random() * 255));
    }
    em.push(0x00);
    for (var j = 0; j < data.length; j++) em.push(data[j] & 0xff);
    return em;
  }

  // 宿主排空协议（与 java 规则桥同构）：脚本登记 op，引擎计算后回填。
  global.__asymReset = function () {
    global.__asymCache = Object.create(null);
    global.__asymPending = [];
    global.__asymSeen = Object.create(null);
  };
  global.__asymDrain = function () {
    var p = global.__asymPending || [];
    global.__asymPending = [];
    global.__asymSeen = Object.create(null);
    return JSON.stringify(p);
  };
  global.__asymFill = function (json) {
    var c = global.__asymCache;
    if (!c) c = global.__asymCache = Object.create(null);
    var m = JSON.parse(json);
    for (var k in m) c[k] = m[k];
  };

  function asymKeyHex(v) { return v ? bytesToHex(v) : ''; }

  // ── DER 编码（生成密钥对的 X.509 SPKI / PKCS#1 导出）──
  // legado 的 crypto.publicKey.encoded 是 X.509 SubjectPublicKeyInfo；
  // 私钥按两素数 PKCS#1 RSAPrivateKey 编码（dp/dq/qinv 为可选成员，
  // 缺省合法），Java KeyFactory 可直接消费。
  function derLen(n) {
    if (n < 0x80) return [n];
    var out = [];
    var v = n;
    while (v > 0) { out.unshift(v & 0xff); v = Math.floor(v / 256); }
    return [0x80 | out.length].concat(out);
  }
  function derTlv(tag, content) {
    return [tag].concat(derLen(content.length), content);
  }
  function derUint(bytes) {
    var i = 0;
    while (i < bytes.length && (bytes[i] & 0xff) === 0) i++;
    var b = bytes.slice(i);
    if (b.length === 0) b = [0];
    if ((b[0] & 0x80) !== 0) b = [0].concat(b);
    return derTlv(0x02, b);
  }
  function derSeqOf(parts) {
    var out = [];
    for (var i = 0; i < parts.length; i++) {
      out = out.concat(parts[i]);
    }
    return derTlv(0x30, out);
  }
  var RSA_OID = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01];
  function rsaSpkiDer(key) {
    var pkcs1 = derSeqOf([derUint(key.n), derUint(key.e)]);
    return derSeqOf([
      derSeqOf([derTlv(0x06, RSA_OID), derTlv(0x05, [])]),
      derTlv(0x03, [0x00].concat(pkcs1)),
    ]);
  }
  function rsaPkcs1PrivateDer(key) {
    return derSeqOf([
      derUint([0]),
      derUint(key.n), derUint(key.e), derUint(key.d),
      derUint(key.p), derUint(key.q),
    ]);
  }

  function makeAsymmetricCrypto(transformation) {
    var name = String(transformation == null || transformation === ''
        ? 'RSA' : transformation);
    var keyAlg = name.toUpperCase().split('/')[0];
    // legado 构造时 KeyPairGenerator/KeyFactory 用算法名；非 RSA 的 Cipher
    // （EC/DSA 明文族）在 JCE 里没有实现，运算时抛 NoSuchAlgorithmException
    // （Conscrypt：Cannot find any provider supporting ...）。
    if (keyAlg !== 'RSA') {
      var boom = function () {
        throw new Error('NoSuchAlgorithmException: '
            + 'Cannot find any provider supporting ' + name);
      };
      var stub = {
        setPublicKey: function () { return stub; },
        setPrivateKey: function () { return stub; },
        decrypt: boom,
        decryptStr: boom,
        decryptHex: boom,
        decryptBase64: boom,
        encrypt: boom,
        encryptHex: boom,
        encryptBase64: boom,
      };
      return stub;
    }

    var publicKey = null;
    var privateKey = null;
    var genPending = false;
    var genCacheKey = null;

    // legado（AsymmetricCrypto.kt:26-30）：构造即 `KeyPairGenerator
    // .generateKeyPair()`，setPublicKey/setPrivateKey 只是替换。生成走宿主
    // op（pointycastle RSAKeyGenerator）：首轮按调用序号登记 genkey，
    // 宿主生成后回填 __asymCache，重放轮命中同一把密钥（审计 R38）。
    (function () {
      var cache = global.__asymCache;
      if (!cache) cache = global.__asymCache = Object.create(null);
      var seq = global.__asymGenSeq || 0;
      global.__asymGenSeq = seq + 1;
      genCacheKey = name + '|genkey|' + seq;
      var hit = cache[genCacheKey];
      if (hit) {
        if (hit.e) throw new Error(hit.e);
        var kp = JSON.parse(utf8Decode(hexToBytes(hit.v)));
        publicKey = {
          n: hexToBytes(kp.n), e: hexToBytes(kp.e),
        };
        privateKey = {
          n: hexToBytes(kp.n), e: hexToBytes(kp.e), d: hexToBytes(kp.d),
          p: hexToBytes(kp.p), q: hexToBytes(kp.q),
        };
        return;
      }
      var seen = global.__asymSeen;
      if (!seen) seen = global.__asymSeen = Object.create(null);
      if (!seen[genCacheKey]) {
        seen[genCacheKey] = true;
        var pend = global.__asymPending;
        if (!pend) pend = global.__asymPending = [];
        pend.push({ k: genCacheKey, gen: 1, t: name });
      }
      genPending = true;
    })();

    // 命中宿主结果；未命中则按（变换/方向/密钥/数据）登记待办并返回 null。
    // 随机填充（PKCS#1 PS / OAEP seed）只在宿主算一次，重放轮稳定。
    function run(op, usePublicKey, data) {
      var key = usePublicKey ? publicKey : privateKey;
      if (!key) {
        // 构造期自动密钥尚未回填：按待结算占位（重放轮取真值），与
        // ajax/webjs 占位协议一致；无自动密钥时才是真实异常。
        if (genPending) return null;
        throw new Error('InvalidKeyException: RSA '
            + (usePublicKey ? 'public' : 'private') + ' key not set');
      }
      var dataHex = bytesToHex(data);
      var keySig = asymKeyHex(key.n) + '|' + asymKeyHex(key.e) + '|'
          + asymKeyHex(key.d) + '|' + asymKeyHex(key.p) + '|' + asymKeyHex(key.q);
      var cacheKey = name + '|' + op + '|' + (usePublicKey ? 1 : 0) + '|'
          + ruleHash(keySig + '#' + dataHex);
      var cache = global.__asymCache;
      if (!cache) cache = global.__asymCache = Object.create(null);
      if (cache[cacheKey] !== undefined) {
        var hit = cache[cacheKey];
        if (hit.e) throw new Error(hit.e);
        return hexToBytes(hit.v);
      }
      var seen = global.__asymSeen;
      if (!seen) seen = global.__asymSeen = Object.create(null);
      if (!seen[cacheKey]) {
        seen[cacheKey] = true;
        var pend = global.__asymPending;
        if (!pend) pend = global.__asymPending = [];
        pend.push({
          k: cacheKey,
          t: name,
          o: op,
          u: usePublicKey ? 1 : 0,
          n: asymKeyHex(key.n),
          e: asymKeyHex(key.e),
          d: asymKeyHex(key.d),
          p: asymKeyHex(key.p),
          q: asymKeyHex(key.q),
          data: dataHex
        });
      }
      return null;
    }

    // Kotlin `usePublicKey: Boolean? = true`：仅显式 false/null 走私钥。
    function usePubFlag(v) {
      return v === undefined || v === true;
    }

    // legado decode(String)：偶数长度且全 hex → hex，其余 base64。
    function decodeInput(data) {
      if (data && typeof data === 'object' && typeof data.length === 'number') {
        return anyToBytes(data);
      }
      var s = String(data == null ? '' : data);
      var isHex = s.length % 2 === 0 && /^[0-9a-fA-F]*$/.test(s);
      return isHex
          ? hexToBytes(s).map(function (b) { return b & 0xff; })
          : bytesFromB64(s).map(function (b) { return b & 0xff; });
    }

    function bytesOrEmpty(op, usePublicKey, data) {
      var out = run(op, usePublicKey, data);
      return out == null ? [] : out;
    }

    var api = {
      // legado PublicKey/PrivateKey 对象：encoded = DER 字节（X.509 SPKI /
      // PKCS#1 私钥），脚本可把公钥上送服务端做协商。
      getPublicKey: function () {
        return publicKey
            ? { algorithm: 'RSA', format: 'X.509',
                encoded: rsaSpkiDer(publicKey) }
            : null;
      },
      getPrivateKey: function () {
        return privateKey
            ? { algorithm: 'RSA', format: 'PKCS#1',
                encoded: rsaPkcs1PrivateDer(privateKey) }
            : null;
      },
      setPublicKey: function (key) {
        publicKey = rsaParsePublicKey(anyToBytes(key));
        if (!publicKey) throw new Error('InvalidKeySpecException: invalid RSA public key');
        return api;
      },
      setPrivateKey: function (key) {
        privateKey = rsaParsePrivateKey(anyToBytes(key));
        if (!privateKey) throw new Error('InvalidKeySpecException: invalid RSA private key');
        return api;
      },
      decrypt: function (data, usePublicKey) {
        return bytesOrEmpty('decrypt', usePubFlag(usePublicKey), decodeInput(data));
      },
      decryptStr: function (data, usePublicKey) {
        var out = run('decrypt', usePubFlag(usePublicKey), decodeInput(data));
        return out == null ? '' : utf8Decode(out);
      },
      decryptHex: function (data, usePublicKey) {
        return bytesOrEmpty('decrypt', usePubFlag(usePublicKey),
            hexToBytes(String(data == null ? '' : data))
                .map(function (b) { return b & 0xff; }));
      },
      decryptBase64: function (data, usePublicKey) {
        return bytesOrEmpty('decrypt', usePubFlag(usePublicKey),
            bytesFromB64(String(data == null ? '' : data))
                .map(function (b) { return b & 0xff; }));
      },
      encrypt: function (data, usePublicKey) {
        return bytesOrEmpty('encrypt', usePubFlag(usePublicKey), anyToBytes(data));
      },
      encryptHex: function (data, usePublicKey) {
        var out = run('encrypt', usePubFlag(usePublicKey), anyToBytes(data));
        return out == null ? '' : bytesToHex(out);
      },
      encryptBase64: function (data, usePublicKey) {
        var out = run('encrypt', usePubFlag(usePublicKey), anyToBytes(data));
        return out == null
            ? '' : b64FromBytes(out.map(function (b) { return b & 0xff; }));
      },
    };
    // legado Kotlin 属性形态：crypto.publicKey / crypto.privateKey。
    Object.defineProperty(api, 'publicKey', {
      get: function () { return api.getPublicKey(); },
      configurable: true,
    });
    Object.defineProperty(api, 'privateKey', {
      get: function () { return api.getPrivateKey(); },
      configurable: true,
    });
    return api;
  }

  // ── 规则求值桥（java.getString/getStringList/getElement/getElements/setContent）──
  // legado 的 java 就是 AnalyzeRule 本身，JS 内同步回调宿主求值；QuickJS 沙箱
  // 不能同步回宿主，改为「确定性重放」协议：首轮把这些调用按序记入
  // __javaRulePending 并返回类型占位（''/[]/空 Elements/null），宿主排空后
  // 按 op 顺序在宿主侧求值（set 切换内容、get 求规则），把结果写回
  // __javaRuleCache，再重跑脚本——本轮命中缓存即拿到真值。脚本若依赖取值
  // 分支（如 `len>0 ? A : B`），宿主可再排空重跑，最多数轮收敛。
  function ruleHash(s) {
    var h = 5381;
    for (var i = 0; i < s.length; i++) h = ((h * 33) ^ s.charCodeAt(i)) >>> 0;
    return h.toString(16) + ':' + s.length;
  }

  // 求值内容参数：null=用当前根内容；字符串=HTML/文本；元素包装=其内部 HTML
  // （legado 直接持有 Element，这里按 HTML 近似，选择器语义一致；对根元素
  // 自身属性的规则会丢失，见局限记录）；对象=JSON 内容。
  function ruleContentArg(x) {
    if (x === undefined || x === null) return null;
    if (typeof x === 'string') return { k: 's', v: x };
    if (typeof x === 'object' && x.__javaEl) return { k: 'h', v: x.html() };
    if (typeof x === 'object') return { k: 'j', v: x };
    return { k: 's', v: String(x) };
  }

  // 规则桥缓存键的「可变状态」部分：变量表 + 章节变量 + 当前书籍身份。
  // legado 的 java 就是 AnalyzeRule 实体，同一脚本内 put 后再 getString
  // 会真实重新求值；只按 rule/content 建键会把旧值当本轮结果返回。
  function ruleStateSig() {
    var parts = [];
    var v = global.__javaVars;
    if (v && typeof v === 'object') {
      var keys = [];
      for (var k in v) {
        if (Object.prototype.hasOwnProperty.call(v, k)) keys.push(k);
        }
      keys.sort();
      for (var i = 0; i < keys.length; i++) {
        parts.push('v' + keys[i] + '=' + String(v[keys[i]]));
      }
    }
    var ch = global.chapter;
    if (ch != null && ch.variableMap && typeof ch.variableMap === 'object') {
      var ck = [];
      for (var c in ch.variableMap) {
        if (Object.prototype.hasOwnProperty.call(ch.variableMap, c)) ck.push(c);
      }
      ck.sort();
      for (var j = 0; j < ck.length; j++) {
        parts.push('c' + ck[j] + '=' + String(ch.variableMap[ck[j]]));
      }
    }
    var bk = global.book;
    if (bk != null && bk.bookUrl != null) parts.push('b=' + String(bk.bookUrl));
    return parts.length ? ruleHash(parts.join('\u0003')) : '0';
  }

  function ruleCall(kind, rule, content, isUrl) {
    rule = rule == null ? '' : String(rule);
    var cArg = ruleContentArg(content);
    var cKey;
    if (cArg === null) {
      cKey = 'r' + (global.__javaRootSig || 0);
    } else if (cArg.k === 's') {
      cKey = 's' + ruleHash(cArg.v);
    } else if (cArg.k === 'h') {
      cKey = 'h' + ruleHash(cArg.v);
    } else {
      cKey = 'j' + ruleHash(JSON.stringify(cArg.v));
    }
    var key = kind + '|' + (isUrl ? 1 : 0) + '|' + ruleStateSig() + '|' +
      cKey + '|' + rule;
    var cache = global.__javaRuleCache;
    if (cache && cache[key] !== undefined) {
      var v = cache[key];
      if (typeof v === 'string') {
        if (kind === 'l' || kind === 'e' || kind === 'g') {
          try { v = JSON.parse(v); } catch (e) { v = []; }
        }
      }
      if (kind === 'l') return __javaStringList(v || []);
      if (kind === 'e') return __javaElements(v || []);
      if (kind === 'g') return __javaElements(v || []).first();
      return String(v == null ? '' : v);
    }
    var seen = global.__javaRuleSeen;
    if (!seen) seen = global.__javaRuleSeen = Object.create(null);
    if (!seen[key]) {
      seen[key] = true;
      var pend = global.__javaRulePending;
      if (!pend) pend = global.__javaRulePending = [];
      pend.push({ op: 'get', k: kind, r: rule, c: cArg, u: isUrl ? 1 : 0, key: key });
    }
    if (kind === 'l') return __javaStringList([]);
    if (kind === 'e') return __javaElements([]);
    if (kind === 'g') return null;
    return '';
  }

  global.__javaRuleReset = function () {
    global.__javaRuleCache = Object.create(null);
    global.__javaRulePending = [];
    global.__javaRuleSeen = Object.create(null);
    global.__javaRootSig = 0;
  };
  // 每轮重放开始：根内容版本归零，保证同一脚本各轮的缓存键一致
  // （脚本内 setContent 的调用顺序固定；跨求值由 __javaRuleReset 清缓存）。
  global.__javaRuleRound = function () {
    global.__javaRootSig = 0;
  };
  global.__javaRuleDrain = function () {
    var p = global.__javaRulePending || [];
    global.__javaRulePending = [];
    global.__javaRuleSeen = Object.create(null);
    return JSON.stringify(p);
  };
  global.__javaRuleFill = function (json) {
    var c = global.__javaRuleCache;
    if (!c) c = global.__javaRuleCache = Object.create(null);
    var m = JSON.parse(json);
    for (var k in m) c[k] = m[k];
  };

  // ── SHA-1 / SHA-256 / SHA-384 / SHA-512 / HMAC ──
  // （digestHex / digestBase64Str / HMacHex / HMacBase64）
  // QuickJS 无 WebCrypto，按 FIPS 180-4 纯 JS 实现（字节数组输入输出）。
  function sha1Bytes(bytes) {
    var ml = bytes.length * 8;
    var msg = bytes.slice();
    msg.push(0x80);
    while (msg.length % 64 !== 56) msg.push(0);
    var hi = Math.floor(ml / 0x100000000);
    msg.push((hi >>> 24) & 0xff, (hi >>> 16) & 0xff, (hi >>> 8) & 0xff, hi & 0xff);
    msg.push((ml >>> 24) & 0xff, (ml >>> 16) & 0xff, (ml >>> 8) & 0xff, ml & 0xff);
    var h0 = 0x67452301, h1 = 0xefcdab89, h2 = 0x98badcfe,
        h3 = 0x10325476, h4 = 0xc3d2e1f0;
    var w = new Array(80);
    for (var i = 0; i < msg.length; i += 64) {
      for (var t = 0; t < 16; t++) {
        w[t] = ((msg[i + 4 * t] << 24) | (msg[i + 4 * t + 1] << 16) |
            (msg[i + 4 * t + 2] << 8) | msg[i + 4 * t + 3]) >>> 0;
      }
      for (t = 16; t < 80; t++) {
        var x = w[t - 3] ^ w[t - 8] ^ w[t - 14] ^ w[t - 16];
        w[t] = ((x << 1) | (x >>> 31)) >>> 0;
      }
      var a = h0, b = h1, c = h2, d = h3, e = h4;
      for (t = 0; t < 80; t++) {
        var f, k;
        if (t < 20) { f = (b & c) | (~b & d); k = 0x5a827999; }
        else if (t < 40) { f = b ^ c ^ d; k = 0x6ed9eba1; }
        else if (t < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8f1bbcdc; }
        else { f = b ^ c ^ d; k = 0xca62c1d6; }
        var tmp = ((((a << 5) | (a >>> 27)) >>> 0) + (f >>> 0) + e + k + w[t]) >>> 0;
        e = d; d = c; c = ((b << 30) | (b >>> 2)) >>> 0; b = a; a = tmp;
      }
      h0 = (h0 + a) >>> 0; h1 = (h1 + b) >>> 0; h2 = (h2 + c) >>> 0;
      h3 = (h3 + d) >>> 0; h4 = (h4 + e) >>> 0;
    }
    var out = [];
    [h0, h1, h2, h3, h4].forEach(function (h) {
      out.push((h >>> 24) & 0xff, (h >>> 16) & 0xff, (h >>> 8) & 0xff, h & 0xff);
    });
    return out;
  }

  var SHA256_K = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
  ];

  function sha256Bytes(bytes) {
    return sha256Core(bytes, [0x6a09e667, 0xbb67ae85, 0x3c6ef372,
      0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19], 8);
  }

  // SHA-224：SHA-256 换初值 + 截断 28 字节（FIPS 180-4）。
  function sha224Bytes(bytes) {
    return sha256Core(bytes, [0xc1059ed8, 0x367cd507, 0x3070dd17, 0xf70e5939,
      0xffc00b31, 0x68581511, 0x64f98fa7, 0xbefa4fa4], 7);
  }

  function sha256Core(bytes, initH, outWords) {
    var ml = bytes.length * 8;
    var msg = bytes.slice();
    msg.push(0x80);
    while (msg.length % 64 !== 56) msg.push(0);
    var hi = Math.floor(ml / 0x100000000);
    msg.push((hi >>> 24) & 0xff, (hi >>> 16) & 0xff, (hi >>> 8) & 0xff, hi & 0xff);
    msg.push((ml >>> 24) & 0xff, (ml >>> 16) & 0xff, (ml >>> 8) & 0xff, ml & 0xff);
    var H = initH.slice();
    var w = new Array(64);
    for (var i = 0; i < msg.length; i += 64) {
      var t;
      for (t = 0; t < 16; t++) {
        w[t] = ((msg[i + 4 * t] << 24) | (msg[i + 4 * t + 1] << 16) |
            (msg[i + 4 * t + 2] << 8) | msg[i + 4 * t + 3]) >>> 0;
      }
      for (t = 16; t < 64; t++) {
        var s0 = ((w[t - 15] >>> 7) | (w[t - 15] << 25)) ^
            ((w[t - 15] >>> 18) | (w[t - 15] << 14)) ^ (w[t - 15] >>> 3);
        var s1 = ((w[t - 2] >>> 17) | (w[t - 2] << 15)) ^
            ((w[t - 2] >>> 19) | (w[t - 2] << 13)) ^ (w[t - 2] >>> 10);
        w[t] = (w[t - 16] + (s0 >>> 0) + w[t - 7] + (s1 >>> 0)) >>> 0;
      }
      var a = H[0], b = H[1], c = H[2], d = H[3],
          e = H[4], f = H[5], g = H[6], h = H[7];
      for (t = 0; t < 64; t++) {
        var S1 = ((e >>> 6) | (e << 26)) ^ ((e >>> 11) | (e << 21)) ^
            ((e >>> 25) | (e << 7));
        var ch = (e & f) ^ (~e & g);
        var temp1 = (h + (S1 >>> 0) + (ch >>> 0) + SHA256_K[t] + w[t]) >>> 0;
        var S0 = ((a >>> 2) | (a << 30)) ^ ((a >>> 13) | (a << 19)) ^
            ((a >>> 22) | (a << 10));
        var maj = (a & b) ^ (a & c) ^ (b & c);
        var temp2 = ((S0 >>> 0) + (maj >>> 0)) >>> 0;
        h = g; g = f; f = e; e = (d + temp1) >>> 0;
        d = c; c = b; b = a; a = (temp1 + temp2) >>> 0;
      }
      H[0] = (H[0] + a) >>> 0; H[1] = (H[1] + b) >>> 0;
      H[2] = (H[2] + c) >>> 0; H[3] = (H[3] + d) >>> 0;
      H[4] = (H[4] + e) >>> 0; H[5] = (H[5] + f) >>> 0;
      H[6] = (H[6] + g) >>> 0; H[7] = (H[7] + h) >>> 0;
    }
    var out = [];
    for (var j = 0; j < outWords; j++) {
      out.push((H[j] >>> 24) & 0xff, (H[j] >>> 16) & 0xff,
          (H[j] >>> 8) & 0xff, H[j] & 0xff);
    }
    return out;
  }

  // SHA-384/512：64 位字用 [高32, 低32] 对表示（FIPS 180-4）。
  var SHA512_K = [
    0x428a2f98, 0xd728ae22, 0x71374491, 0x23ef65cd, 0xb5c0fbcf, 0xec4d3b2f,
    0xe9b5dba5, 0x8189dbbc, 0x3956c25b, 0xf348b538, 0x59f111f1, 0xb605d019,
    0x923f82a4, 0xaf194f9b, 0xab1c5ed5, 0xda6d8118, 0xd807aa98, 0xa3030242,
    0x12835b01, 0x45706fbe, 0x243185be, 0x4ee4b28c, 0x550c7dc3, 0xd5ffb4e2,
    0x72be5d74, 0xf27b896f, 0x80deb1fe, 0x3b1696b1, 0x9bdc06a7, 0x25c71235,
    0xc19bf174, 0xcf692694, 0xe49b69c1, 0x9ef14ad2, 0xefbe4786, 0x384f25e3,
    0x0fc19dc6, 0x8b8cd5b5, 0x240ca1cc, 0x77ac9c65, 0x2de92c6f, 0x592b0275,
    0x4a7484aa, 0x6ea6e483, 0x5cb0a9dc, 0xbd41fbd4, 0x76f988da, 0x831153b5,
    0x983e5152, 0xee66dfab, 0xa831c66d, 0x2db43210, 0xb00327c8, 0x98fb213f,
    0xbf597fc7, 0xbeef0ee4, 0xc6e00bf3, 0x3da88fc2, 0xd5a79147, 0x930aa725,
    0x06ca6351, 0xe003826f, 0x14292967, 0x0a0e6e70, 0x27b70a85, 0x46d22ffc,
    0x2e1b2138, 0x5c26c926, 0x4d2c6dfc, 0x5ac42aed, 0x53380d13, 0x9d95b3df,
    0x650a7354, 0x8baf63de, 0x766a0abb, 0x3c77b2a8, 0x81c2c92e, 0x47edaee6,
    0x92722c85, 0x1482353b, 0xa2bfe8a1, 0x4cf10364, 0xa81a664b, 0xbc423001,
    0xc24b8b70, 0xd0f89791, 0xc76c51a3, 0x0654be30, 0xd192e819, 0xd6ef5218,
    0xd6990624, 0x5565a910, 0xf40e3585, 0x5771202a, 0x106aa070, 0x32bbd1b8,
    0x19a4c116, 0xb8d2d0c8, 0x1e376c08, 0x5141ab53, 0x2748774c, 0xdf8eeb99,
    0x34b0bcb5, 0xe19b48a8, 0x391c0cb3, 0xc5c95a63, 0x4ed8aa4a, 0xe3418acb,
    0x5b9cca4f, 0x7763e373, 0x682e6ff3, 0xd6b2b8a3, 0x748f82ee, 0x5defb2fc,
    0x78a5636f, 0x43172f60, 0x84c87814, 0xa1f0ab72, 0x8cc70208, 0x1a6439ec,
    0x90befffa, 0x23631e28, 0xa4506ceb, 0xde82bde9, 0xbef9a3f7, 0xb2c67915,
    0xc67178f2, 0xe372532b, 0xca273ece, 0xea26619c, 0xd186b8c7, 0x21c0c207,
    0xeada7dd6, 0xcde0eb1e, 0xf57d4f7f, 0xee6ed178, 0x06f067aa, 0x72176fba,
    0x0a637dc5, 0xa2c898a6, 0x113f9804, 0xbef90dae, 0x1b710b35, 0x131c471b,
    0x28db77f5, 0x23047d84, 0x32caab7b, 0x40c72493, 0x3c9ebe0a, 0x15c9bebc,
    0x431d67c4, 0x9c100d4c, 0x4cc5d4be, 0xcb3e42b6, 0x597f299c, 0xfc657e2a,
    0x5fcb6fab, 0x3ad6faec, 0x6c44198c, 0x4a475817
  ];

  function sha64Ror(a, n) {
    if (n < 32) {
      return [((a[0] >>> n) | (a[1] << (32 - n))) >>> 0,
              ((a[1] >>> n) | (a[0] << (32 - n))) >>> 0];
    }
    if (n === 32) return [a[1], a[0]];
    var m = n - 32;
    return [((a[1] >>> m) | (a[0] << (32 - m))) >>> 0,
            ((a[0] >>> m) | (a[1] << (32 - m))) >>> 0];
  }

  function sha64Shr(a, n) {
    if (n < 32) {
      return [a[0] >>> n, ((a[1] >>> n) | (a[0] << (32 - n))) >>> 0];
    }
    return [0, a[0] >>> (n - 32)];
  }

  function sha64Xor(a, b) {
    return [(a[0] ^ b[0]) >>> 0, (a[1] ^ b[1]) >>> 0];
  }

  function sha64Add(a, b) {
    var lo = (a[1] >>> 0) + (b[1] >>> 0);
    var hi = (a[0] >>> 0) + (b[0] >>> 0) + (lo > 0xffffffff ? 1 : 0);
    return [hi >>> 0, lo >>> 0];
  }

  function sha512Core(bytes, is384) {
    var ml = bytes.length * 8;
    var msg = bytes.slice();
    msg.push(0x80);
    while (msg.length % 128 !== 112) msg.push(0);
    var hi = Math.floor(ml / 0x100000000);
    msg.push(0, 0, 0, 0, 0, 0, 0, 0,
        (hi >>> 24) & 0xff, (hi >>> 16) & 0xff, (hi >>> 8) & 0xff, hi & 0xff,
        (ml >>> 24) & 0xff, (ml >>> 16) & 0xff, (ml >>> 8) & 0xff, ml & 0xff);
    var H = is384
        ? [0xcbbb9d5d, 0xc1059ed8, 0x629a292a, 0x367cd507,
           0x9159015a, 0x3070dd17, 0x152fecd8, 0xf70e5939,
           0x67332667, 0xffc00b31, 0x8eb44a87, 0x68581511,
           0xdb0c2e0d, 0x64f98fa7, 0x47b5481d, 0xbefa4fa4]
        : [0x6a09e667, 0xf3bcc908, 0xbb67ae85, 0x84caa73b,
           0x3c6ef372, 0xfe94f82b, 0xa54ff53a, 0x5f1d36f1,
           0x510e527f, 0xade682d1, 0x9b05688c, 0x2b3e6c1f,
           0x1f83d9ab, 0xfb41bd6b, 0x5be0cd19, 0x137e2179];
    var w = new Array(160);
    for (var i = 0; i < msg.length; i += 128) {
      var t;
      for (t = 0; t < 16; t++) {
        w[2 * t] = ((msg[i + 8 * t] << 24) | (msg[i + 8 * t + 1] << 16) |
            (msg[i + 8 * t + 2] << 8) | msg[i + 8 * t + 3]) >>> 0;
        w[2 * t + 1] = ((msg[i + 8 * t + 4] << 24) |
            (msg[i + 8 * t + 5] << 16) | (msg[i + 8 * t + 6] << 8) |
            msg[i + 8 * t + 7]) >>> 0;
      }
      for (t = 16; t < 80; t++) {
        var w15 = [w[2 * (t - 15)], w[2 * (t - 15) + 1]];
        var w2 = [w[2 * (t - 2)], w[2 * (t - 2) + 1]];
        var s0 = sha64Xor(sha64Xor(sha64Ror(w15, 1), sha64Ror(w15, 8)),
            sha64Shr(w15, 7));
        var s1 = sha64Xor(sha64Xor(sha64Ror(w2, 19), sha64Ror(w2, 61)),
            sha64Shr(w2, 6));
        var acc = sha64Add(
            sha64Add([w[2 * (t - 16)], w[2 * (t - 16) + 1]], s0),
            sha64Add([w[2 * (t - 7)], w[2 * (t - 7) + 1]], s1));
        w[2 * t] = acc[0];
        w[2 * t + 1] = acc[1];
      }
      var a = [H[0], H[1]], b = [H[2], H[3]], c = [H[4], H[5]],
          d = [H[6], H[7]], e = [H[8], H[9]], f = [H[10], H[11]],
          g = [H[12], H[13]], h = [H[14], H[15]];
      for (t = 0; t < 80; t++) {
        var S1 = sha64Xor(sha64Xor(sha64Ror(e, 14), sha64Ror(e, 18)),
            sha64Ror(e, 41));
        var ch = sha64Xor(
            [(e[0] & f[0]) >>> 0, (e[1] & f[1]) >>> 0],
            [(~e[0] & g[0]) >>> 0, (~e[1] & g[1]) >>> 0]);
        var t1 = sha64Add(
            sha64Add(sha64Add(h, S1),
                sha64Add(ch, [SHA512_K[2 * t], SHA512_K[2 * t + 1]])),
            [w[2 * t], w[2 * t + 1]]);
        var S0 = sha64Xor(sha64Xor(sha64Ror(a, 28), sha64Ror(a, 34)),
            sha64Ror(a, 39));
        var maj = sha64Xor(sha64Xor(
            [(a[0] & b[0]) >>> 0, (a[1] & b[1]) >>> 0],
            [(a[0] & c[0]) >>> 0, (a[1] & c[1]) >>> 0]),
            [(b[0] & c[0]) >>> 0, (b[1] & c[1]) >>> 0]);
        var t2 = sha64Add(S0, maj);
        h = g; g = f; f = e; e = sha64Add(d, t1);
        d = c; c = b; b = a; a = sha64Add(t1, t2);
      }
      var vars = [a, b, c, d, e, f, g, h];
      for (var v = 0; v < 8; v++) {
        var sum = sha64Add([H[2 * v], H[2 * v + 1]], vars[v]);
        H[2 * v] = sum[0];
        H[2 * v + 1] = sum[1];
      }
    }
    var out = [];
    var words = is384 ? 6 : 8;
    for (var j = 0; j < words; j++) {
      out.push((H[2 * j] >>> 24) & 0xff, (H[2 * j] >>> 16) & 0xff,
          (H[2 * j] >>> 8) & 0xff, H[2 * j] & 0xff);
      out.push((H[2 * j + 1] >>> 24) & 0xff, (H[2 * j + 1] >>> 16) & 0xff,
          (H[2 * j + 1] >>> 8) & 0xff, H[2 * j + 1] & 0xff);
    }
    return out;
  }

  function sha512Bytes(bytes) { return sha512Core(bytes, false); }
  function sha384Bytes(bytes) { return sha512Core(bytes, true); }

  function digestBytes(algo, bytes) {
    var a = String(algo == null ? '' : algo).toUpperCase().replace(/-/g, '');
    if (a === 'MD5') return md5Bytes(bytes);
    if (a === 'SHA1') return sha1Bytes(bytes);
    if (a === 'SHA224') return sha224Bytes(bytes);
    if (a === 'SHA256') return sha256Bytes(bytes);
    if (a === 'SHA384') return sha384Bytes(bytes);
    if (a === 'SHA512') return sha512Bytes(bytes);
    return null;
  }

  function hmacBytes(algo, keyBytes, dataBytes) {
    var a = String(algo == null ? '' : algo).toUpperCase().replace(/-/g, '');
    var hash;
    if (a.indexOf('HMAC') === 0) a = a.substring(4);
    if (a === 'MD5') hash = md5Bytes;
    else if (a === 'SHA1') hash = sha1Bytes;
    else if (a === 'SHA224') hash = sha224Bytes;
    else if (a === 'SHA256') hash = sha256Bytes;
    else if (a === 'SHA384') hash = sha384Bytes;
    else if (a === 'SHA512') hash = sha512Bytes;
    else return null;
    var block = (a === 'SHA384' || a === 'SHA512') ? 128 : 64;
    var key = keyBytes.slice();
    if (key.length > block) key = hash(key);
    while (key.length < block) key.push(0);
    var ipad = [], opad = [];
    for (var i = 0; i < block; i++) {
      ipad.push(key[i] ^ 0x36);
      opad.push(key[i] ^ 0x5c);
    }
    var inner = hash(ipad.concat(dataBytes));
    return hash(opad.concat(inner));
  }

  // legado `MessageDigest/Mac.getInstance` 对未知算法抛 NoSuchAlgorithmException；
  // NexHub 旧实现返回 null → 调用方拿到空串继续拼签名，错误被静默放大。
  function requireDigestBytes(algo, bytes) {
    var out = digestBytes(algo, bytes);
    if (out == null) {
      throw new Error('NoSuchAlgorithmException: ' + String(algo == null ? '' : algo));
    }
    return out;
  }

  function requireHmacBytes(algo, keyBytes, dataBytes) {
    var out = hmacBytes(algo, keyBytes, dataBytes);
    if (out == null) {
      throw new Error('NoSuchAlgorithmException: ' + String(algo == null ? '' : algo));
    }
    return out;
  }

  // ── Rhino Java 互操作（Packages / JavaImporter）──
  //
  // legado 用 Rhino 执行书源脚本，脚本可直接 `new JavaImporter()` 导入
  // `Packages.javax.crypto` 等 Java 类。QuickJS 没有 Java 运行时，这里按
  // 语料实际用到的类提供纯 JS 等价物：
  // - javax.crypto.Cipher / SecretKeySpec / IvParameterSpec → 复用下方 AES/DES
  // - java.util.Base64 / Arrays / UUID / LinkedHashMap · java.lang.String
  // - java.io 字节流、java.util.zip.GZIPInputStream（纯 JS inflate）
  // - android.util.Base64 / TextUtils / Build、hutool Base64/DigestUtil/…
  // - okhttp3（Request/OkHttpClient/Response）→ java.connect 确定性重放
  // - org.jsoup.Jsoup（转发 sourceContext 预置的 connect 链）、StrResponse
  // 未注册的类保持不存在（调用抛 TypeError 进运行日志），不伪造成功结果。

  // 字节数组统一转换成无符号（Java 内部运算口径）；对外返回有符号。
  function juBytes(v) {
    if (v && typeof v === 'object' && typeof v.length === 'number') {
      var out = [];
      for (var i = 0; i < v.length; i++) out.push(v[i] & 0xff);
      return out;
    }
    return utf8Encode(String(v == null ? '' : v));
  }
  function jsBytes(v) { return juBytes(v).map(signedByte); }

  function jmark(cls, name) {
    try {
      Object.defineProperty(cls, '__javaClass', { value: true });
      Object.defineProperty(cls, '__javaName', { value: name });
      if (typeof cls.getName !== 'function') {
        Object.defineProperty(cls, 'getName', {
          value: function () { return name; },
          enumerable: false,
          configurable: true,
        });
      }
    } catch (e) {}
    return cls;
  }
  function jpkg(classes, subs) {
    var o = {};
    var list = {};
    var k;
    if (classes) {
      for (k in classes) { o[k] = classes[k]; list[k] = classes[k]; }
    }
    if (subs) {
      for (k in subs) o[k] = subs[k];
    }
    Object.defineProperty(o, '__classes', { value: list });
    return o;
  }
  function jcopyInto(target, pkg) {
    var list = pkg && pkg.__classes;
    if (!list) return;
    for (var k in list) target[k] = list[k];
  }

  // java.lang.String：`String(byte[])` 按 UTF-8 解码（legado 恒 UTF-8）；
  // 无 new 时返回 JS 字符串原语，new 时返回带 toString/getBytes 的对象。
  function jStringOf(v) {
    if (v == null) return String(v);
    if (typeof v === 'object') {
      if (v.__jstr != null) return String(v.__jstr);
      if (typeof v.length === 'number' && typeof v !== 'function') {
        return utf8Decode(v);
      }
    }
    return String(v);
  }
  function JavaString(v) {
    if (this instanceof JavaString) {
      this.__jstr = jStringOf(v);
      return;
    }
    return jStringOf(v);
  }
  jmark(JavaString, 'java.lang.String');
  JavaString.prototype.toString = function () { return this.__jstr; };
  JavaString.prototype.valueOf = function () { return this.__jstr; };
  JavaString.prototype.getBytes = function (charset) {
    return jsBytes(this.__jstr);
  };
  JavaString.prototype.length = function () { return this.__jstr.length; };
  JavaString.prototype.equals = function (o) {
    return this.__jstr === String(o == null ? '' : o);
  };
  JavaString.prototype.equalsIgnoreCase = function (o) {
    return this.__jstr.toLowerCase() ===
        String(o == null ? '' : o).toLowerCase();
  };
  JavaString.prototype.contains = function (o) {
    return this.__jstr.indexOf(String(o == null ? '' : o)) >= 0;
  };
  JavaString.prototype.indexOf = function (o) {
    return this.__jstr.indexOf(String(o == null ? '' : o));
  };
  JavaString.prototype.substring = function (a, b) {
    return b == null ? this.__jstr.substring(a) : this.__jstr.substring(a, b);
  };
  JavaString.prototype.trim = function () { return this.__jstr.trim(); };
  JavaString.prototype.toLowerCase = function () {
    return this.__jstr.toLowerCase();
  };
  JavaString.prototype.toUpperCase = function () {
    return this.__jstr.toUpperCase();
  };
  JavaString.prototype.replace = function (a, b) {
    return this.__jstr.split(String(a)).join(String(b));
  };
  // 原语字符串也要支持 `.getBytes()`（`String("x").getBytes()` 经 with 作用域
  // 解到 JavaString 后返回原语）。仅新增方法，不改既有行为。
  try {
    if (!String.prototype.getBytes) {
      Object.defineProperty(String.prototype, 'getBytes', {
        value: function (charset) { return jsBytes(String(this)); },
        enumerable: false,
        configurable: true,
        writable: true,
      });
    }
  } catch (e) {}

  // ── java.util.Base64（Java 8）与 android.util.Base64 ──
  function jB64Decoder(urlSafe) {
    return {
      decode: function (s) {
        var str = String(s == null ? '' : s);
        if (urlSafe) str = str.replace(/-/g, '+').replace(/_/g, '/');
        return bytesFromB64(str);
      },
    };
  }
  function jB64Encoder(urlSafe) {
    var enc = {
      encodeToString: function (b) {
        var s = b64FromBytes(juBytes(b));
        if (urlSafe) {
          s = s.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
        }
        return s;
      },
      withoutPadding: function () { return enc; },
    };
    enc.encode = function (b) { return jsBytes(enc.encodeToString(b)); };
    return enc;
  }
  var JavaBase64 = jmark(function JavaBase64() {},
      'java.util.Base64');
  JavaBase64.getDecoder = function () { return jB64Decoder(false); };
  JavaBase64.getEncoder = function () { return jB64Encoder(false); };
  JavaBase64.getUrlDecoder = function () { return jB64Decoder(true); };
  JavaBase64.getUrlEncoder = function () { return jB64Encoder(true); };
  JavaBase64.getMimeDecoder = function () { return jB64Decoder(false); };
  JavaBase64.getMimeEncoder = function () { return jB64Encoder(false); };

  var AndroidBase64 = jmark(function AndroidBase64() {},
      'android.util.Base64');
  AndroidBase64.DEFAULT = 0;
  AndroidBase64.NO_PADDING = 1;
  AndroidBase64.NO_WRAP = 2;
  AndroidBase64.CRLF = 4;
  AndroidBase64.URL_SAFE = 8;
  AndroidBase64.NO_CLOSE = 16;
  AndroidBase64.decode = function (s, flags) {
    var str = String(s == null ? '' : s);
    if ((flags || 0) & 8) str = str.replace(/-/g, '+').replace(/_/g, '/');
    return bytesFromB64(str);
  };
  AndroidBase64.encodeToString = function (b, flags) {
    return b64EncodeFlags(juBytes(b), flags == null ? 2 : flags);
  };
  AndroidBase64.encode = function (b, flags) {
    return jsBytes(AndroidBase64.encodeToString(b, flags));
  };

  // ── java.util.Arrays ──
  var JavaArrays = jmark(function JavaArrays() {}, 'java.util.Arrays');
  JavaArrays.copyOfRange = function (src, from, to) {
    var a = juBytes(src);
    var out = [];
    for (var i = from; i < to; i++) {
      out.push(i >= 0 && i < a.length ? signedByte(a[i]) : 0);
    }
    return out;
  };
  JavaArrays.copyOf = function (src, len) {
    var a = juBytes(src);
    var out = [];
    for (var i = 0; i < len; i++) {
      out.push(i < a.length ? signedByte(a[i]) : 0);
    }
    return out;
  };
  // Java `Arrays.fill(a, v)` / `Arrays.fill(a, from, to, v)`：按参数个数分派，
  // 区间写只改 [from, to)，不能把整数组填满。
  JavaArrays.fill = function (arr) {
    if (!arr || typeof arr.length !== 'number') return arr;
    if (arguments.length >= 4) {
      var from = arguments[1] | 0;
      var to = arguments[2] | 0;
      var val = arguments[3];
      var start = from < 0 ? 0 : from;
      var end = to > arr.length ? arr.length : to;
      for (var i = start; i < end; i++) arr[i] = val;
      return arr;
    }
    var v = arguments[1];
    for (var j = 0; j < arr.length; j++) arr[j] = v;
    return arr;
  };
  JavaArrays.equals = function (a, b) {
    var x = juBytes(a), y = juBytes(b);
    if (x.length !== y.length) return false;
    for (var i = 0; i < x.length; i++) if (x[i] !== y[i]) return false;
    return true;
  };
  JavaArrays.toString = function (a) {
    var arr = [];
    for (var i = 0; a && i < a.length; i++) arr.push(String(a[i]));
    return '[' + arr.join(', ') + ']';
  };
  // Java `Arrays.sort(a)` / `Arrays.sort(a, cmp)`：Comparator 可以是 JS 函数
  // 或带 `compare` 的 Java 风格对象；无 Comparator 时按 Java 自然序
  // （数值升序 / 字符串字典序），不再固定 `x-y`。
  JavaArrays.sort = function (a, comparator) {
    if (!a || typeof a.sort !== 'function') return a;
    var cmp = null;
    if (typeof comparator === 'function') {
      cmp = comparator;
    } else if (comparator && typeof comparator.compare === 'function') {
      cmp = function (x, y) { return comparator.compare(x, y); };
    }
    if (cmp != null) {
      a.sort(function (x, y) {
        var r = cmp(x, y);
        return r < 0 ? -1 : (r > 0 ? 1 : 0);
      });
      return a;
    }
    a.sort(function (x, y) {
      if (typeof x === 'number' && typeof y === 'number') {
        return x < y ? -1 : (x > y ? 1 : 0);
      }
      var sx = String(x), sy = String(y);
      return sx < sy ? -1 : (sx > sy ? 1 : 0);
    });
    return a;
  };
  JavaArrays.asList = function () {
    return Array.prototype.slice.call(arguments);
  };

  // ── java.util.UUID / Map / List ──
  var JavaUUID = jmark(function JavaUUID(v) {
    if (this instanceof JavaUUID) {
      this.__u = v == null ? randomUUID() : String(v);
    }
  }, 'java.util.UUID');
  JavaUUID.randomUUID = function () { return new JavaUUID(null); };
  JavaUUID.fromString = function (s) { return new JavaUUID(s); };
  JavaUUID.prototype.toString = function () { return this.__u; };
  JavaUUID.prototype.valueOf = function () { return this.__u; };

  // Java Map 键身份对齐 java.util（Rhino 直连真实集合）：**严格相等**——
  // Integer 1 与 String '1' 是两个键，对象键按引用身份。旧实现把键全部
  // String 化，数字键与对象键互相坍缩（审计 R41）。插入序保留
  // （LinkedHashMap 语义）。
  function JavaMap(init) {
    if (!(this instanceof JavaMap)) return new JavaMap(init);
    this.__e = [];
    if (init && typeof init === 'object') {
      if (init instanceof JavaMap) {
        for (var i = 0; i < init.__e.length; i++) {
          this.__e.push({ k: init.__e[i].k, v: init.__e[i].v });
        }
      } else if (typeof init.length !== 'number') {
        for (var j in init) this.__e.push({ k: j, v: init[j] });
      }
    }
  }
  jmark(JavaMap, 'java.util.LinkedHashMap');
  JavaMap.prototype.__find = function (k) {
    for (var i = 0; i < this.__e.length; i++) {
      if (this.__e[i].k === k) return i;
    }
    return -1;
  };
  JavaMap.prototype.put = function (k, v) {
    var i = this.__find(k);
    if (i >= 0) {
      var old = this.__e[i].v;
      this.__e[i].v = v;
      return old == null ? null : old;
    }
    this.__e.push({ k: k, v: v });
    return null;
  };
  JavaMap.prototype.putAll = function (m) {
    if (m instanceof JavaMap) {
      for (var i = 0; i < m.__e.length; i++) {
        this.put(m.__e[i].k, m.__e[i].v);
      }
    } else if (m && typeof m === 'object') {
      for (var k in m) this.put(k, m[k]);
    }
    return null;
  };
  JavaMap.prototype.get = function (k) {
    var i = this.__find(k);
    return i >= 0 ? (this.__e[i].v == null ? null : this.__e[i].v) : null;
  };
  JavaMap.prototype.getOrDefault = function (k, d) {
    var i = this.__find(k);
    return i >= 0 && this.__e[i].v != null ? this.__e[i].v : d;
  };
  JavaMap.prototype.containsKey = function (k) {
    return this.__find(k) >= 0;
  };
  JavaMap.prototype.containsValue = function (v) {
    for (var i = 0; i < this.__e.length; i++) {
      if (this.__e[i].v === v) return true;
    }
    return false;
  };
  JavaMap.prototype.remove = function (k) {
    var i = this.__find(k);
    if (i < 0) return null;
    var v = this.__e[i].v;
    this.__e.splice(i, 1);
    return v == null ? null : v;
  };
  JavaMap.prototype.clear = function () { this.__e = []; };
  JavaMap.prototype.size = function () { return this.__e.length; };
  JavaMap.prototype.isEmpty = function () { return this.__e.length === 0; };
  JavaMap.prototype.keySet = function () {
    var ks = [];
    for (var i = 0; i < this.__e.length; i++) ks.push(this.__e[i].k);
    return ks;
  };
  JavaMap.prototype.values = function () {
    var vs = [];
    for (var i = 0; i < this.__e.length; i++) vs.push(this.__e[i].v);
    return vs;
  };
  JavaMap.prototype.forEach = function (fn) {
    for (var i = 0; i < this.__e.length; i++) {
      fn(this.__e[i].k, this.__e[i].v);
    }
    return null;
  };
  JavaMap.prototype.entrySet = function () {
    var entries = this.__e;
    return entries.map(function (e) {
      return {
        getKey: function () { return e.k; },
        getValue: function () { return e.v; },
        toString: function () { return e.k + '=' + e.v; },
      };
    });
  };
  JavaMap.prototype.toString = function () {
    var parts = [];
    for (var i = 0; i < this.__e.length; i++) {
      parts.push(String(this.__e[i].k) + '=' + this.__e[i].v);
    }
    return '{' + parts.join(', ') + '}';
  };
  JavaMap.prototype.toJSON = function () {
    var o = {};
    for (var i = 0; i < this.__e.length; i++) {
      o[String(this.__e[i].k)] = this.__e[i].v;
    }
    return o;
  };

  function JavaList(init) {
    if (!(this instanceof JavaList)) return new JavaList(init);
    this.__a = [];
    if (init && typeof init.length === 'number') {
      for (var i = 0; i < init.length; i++) this.__a.push(init[i]);
    }
  }
  jmark(JavaList, 'java.util.ArrayList');
  JavaList.prototype.add = function (v) { this.__a.push(v); return true; };
  JavaList.prototype.get = function (i) { return this.__a[i]; };
  JavaList.prototype.size = function () { return this.__a.length; };
  JavaList.prototype.isEmpty = function () { return this.__a.length === 0; };
  JavaList.prototype.toArray = function () { return this.__a.slice(); };
  JavaList.prototype.toJSON = function () { return this.__a.slice(); };
  JavaList.prototype.toString = function () {
    return '[' + this.__a.join(', ') + ']';
  };

  // legado/Rhino 直接暴露真实 java.util.Set（去重语义）。旧实现把
  // HashSet/Set 映射到 JavaList，`add` 永远追加 —— 依赖 Set 去重的脚本
  // （关键词合并、URL 池、标签集合）会拿到重复项。
  function JavaSet(init) {
    if (!(this instanceof JavaSet)) return new JavaSet(init);
    this.__a = [];
    if (init && typeof init.length === 'number') {
      for (var i = 0; i < init.length; i++) this.add(init[i]);
    }
  }
  jmark(JavaSet, 'java.util.HashSet');
  JavaSet.prototype.__indexOf = function (v) {
    for (var i = 0; i < this.__a.length; i++) {
      if (this.__a[i] === v) return i;
    }
    return -1;
  };
  JavaSet.prototype.add = function (v) {
    if (this.__indexOf(v) >= 0) return false;
    this.__a.push(v);
    return true;
  };
  JavaSet.prototype.addAll = function (coll) {
    var changed = false;
    if (coll && typeof coll.length === 'number') {
      for (var i = 0; i < coll.length; i++) {
        if (this.add(coll[i])) changed = true;
      }
    }
    return changed;
  };
  JavaSet.prototype.contains = function (v) { return this.__indexOf(v) >= 0; };
  JavaSet.prototype.remove = function (v) {
    var i = this.__indexOf(v);
    if (i < 0) return false;
    this.__a.splice(i, 1);
    return true;
  };
  JavaSet.prototype.size = function () { return this.__a.length; };
  JavaSet.prototype.isEmpty = function () { return this.__a.length === 0; };
  JavaSet.prototype.clear = function () { this.__a = []; };
  JavaSet.prototype.toArray = function () { return this.__a.slice(); };
  JavaSet.prototype.toJSON = function () { return this.__a.slice(); };
  JavaSet.prototype.iterator = function () {
    var a = this.__a;
    var i = 0;
    return {
      hasNext: function () { return i < a.length; },
      next: function () { return a[i++]; },
    };
  };
  JavaSet.prototype.forEach = function (fn) {
    for (var i = 0; i < this.__a.length; i++) fn(this.__a[i]);
  };
  JavaSet.prototype.toString = function () {
    return '[' + this.__a.join(', ') + ']';
  };

  // ── java.lang.System / Thread ──
  var JavaSystem = jmark({
    currentTimeMillis: function () { return Date.now(); },
    nanoTime: function () { return Date.now() * 1e6; },
    getProperty: function (k) {
      return String(k == null ? '' : k) === 'line.separator' ? '\n' : '';
    },
    getenv: function () { return ''; },
    arraycopy: function (src, sp, dst, dp, len) {
      for (var i = 0; i < len; i++) dst[dp + i] = src[sp + i];
      return null;
    },
    exit: function () { return null; },
    gc: function () { return null; },
  }, 'java.lang.System');
  var JavaThread = jmark({
    sleep: function (ms) { return null; },
    yield: function () { return null; },
    currentThread: function () {
      return { getName: function () { return 'main'; } };
    },
  }, 'java.lang.Thread');

  // ── java.net.URL（值对象；不触网，openStream/openConnection 显式抛错）──
  function JavaNetURL(url) {
    if (!(this instanceof JavaNetURL)) return new JavaNetURL(url);
    var s = String(url == null ? '' : url).trim();
    var m = s.match(
        /^([a-zA-Z][a-zA-Z0-9+.-]*):\/\/([^\/?#]*)([^?#]*)(?:\?([^#]*))?(?:#(.*))?$/);
    if (!m) throw new Error('Malformed URL: ' + s);
    this.href = s;
    this.protocol = m[1].toLowerCase();
    this.authority = m[2];
    var at = this.authority.lastIndexOf('@');
    var hostPort = at >= 0 ? this.authority.substring(at + 1) : this.authority;
    this.userInfo = at >= 0 ? this.authority.substring(0, at) : null;
    var colon = hostPort.lastIndexOf(':');
    var port = -1;
    var host = hostPort;
    if (colon >= 0) {
      var p = parseInt(hostPort.substring(colon + 1), 10);
      if (!isNaN(p)) {
        port = p;
        host = hostPort.substring(0, colon);
      }
    }
    this.host = host;
    this.port = port;
    this.path = m[3] || '';
    this.query = m[4] == null ? null : m[4];
    this.ref = m[5] == null ? null : m[5];
  }
  jmark(JavaNetURL, 'java.net.URL');
  JavaNetURL.prototype.getProtocol = function () { return this.protocol; };
  JavaNetURL.prototype.getHost = function () { return this.host; };
  JavaNetURL.prototype.getPort = function () { return this.port; };
  JavaNetURL.prototype.getDefaultPort = function () {
    return this.protocol === 'https' ? 443
        : (this.protocol === 'http' ? 80 : -1);
  };
  JavaNetURL.prototype.getPath = function () { return this.path; };
  JavaNetURL.prototype.getQuery = function () { return this.query; };
  JavaNetURL.prototype.getRef = function () { return this.ref; };
  JavaNetURL.prototype.getAuthority = function () { return this.authority; };
  JavaNetURL.prototype.getUserInfo = function () { return this.userInfo; };
  JavaNetURL.prototype.getFile = function () {
    return this.path + (this.query == null ? '' : '?' + this.query);
  };
  JavaNetURL.prototype.toString = function () { return this.href; };
  JavaNetURL.prototype.toExternalForm = function () { return this.href; };
  JavaNetURL.prototype.toURI = function () {
    var href = this.href;
    return { toString: function () { return href; } };
  };
  JavaNetURL.prototype.openStream = function () {
    throw new Error('java.net.URL.openStream is not supported');
  };
  JavaNetURL.prototype.openConnection = function () {
    throw new Error('java.net.URL.openConnection is not supported');
  };

  // ── android.text.TextUtils / android.os.Build ──
  var AndroidTextUtils = jmark({
    isEmpty: function (s) { return s == null || String(s).length === 0; },
    isNotEmpty: function (s) { return s != null && String(s).length > 0; },
    equals: function (a, b) { return String(a == null ? '' : a) === String(b == null ? '' : b); },
    join: function (sep, items) {
      var arr = [];
      for (var i = 1; i < arguments.length; i++) {
        var x = arguments[i];
        if (x && typeof x.length === 'number') {
          for (var j = 0; j < x.length; j++) arr.push(String(x[j]));
        } else {
          arr.push(String(x));
        }
      }
      return arr.join(String(sep));
    },
  }, 'android.text.TextUtils');
  var AndroidBuildVersion = {
    RELEASE: '14',
    SDK_INT: 34,
    CODENAME: 'REL',
  };
  var AndroidBuild = jmark({
    MODEL: 'Pixel 7',
    MANUFACTURER: 'Google',
    BRAND: 'google',
    DEVICE: 'panther',
    PRODUCT: 'panther',
    HARDWARE: 'panther',
    ID: 'AP1A.240505.004',
    FINGERPRINT: 'google/panther/panther:14/AP1A.240505.004/1:user/release-keys',
    VERSION: AndroidBuildVersion,
  }, 'android.os.Build');

  // ── java.io 字节流 ──
  function ByteArrayOutputStream(size) {
    if (!(this instanceof ByteArrayOutputStream)) {
      return new ByteArrayOutputStream(size);
    }
    this.__a = [];
  }
  jmark(ByteArrayOutputStream, 'java.io.ByteArrayOutputStream');
  ByteArrayOutputStream.prototype.write = function (b, off, len) {
    if (b == null) return null;
    if (typeof b === 'number') { this.__a.push(b & 0xff); return null; }
    var o = off == null ? 0 : off;
    var n = len == null ? b.length - o : len;
    for (var i = 0; i < n; i++) {
      var idx = o + i;
      if (idx >= 0 && idx < b.length) this.__a.push(b[idx] & 0xff);
    }
    return null;
  };
  ByteArrayOutputStream.prototype.toByteArray = function () {
    return this.__a.map(signedByte);
  };
  ByteArrayOutputStream.prototype.toString = function (charset) {
    return utf8Decode(this.__a);
  };
  ByteArrayOutputStream.prototype.size = function () { return this.__a.length; };
  ByteArrayOutputStream.prototype.reset = function () { this.__a = []; };
  ByteArrayOutputStream.prototype.flush = function () { return null; };
  ByteArrayOutputStream.prototype.close = function () { return null; };

  function ByteArrayInputStream(bytes) {
    if (!(this instanceof ByteArrayInputStream)) {
      return new ByteArrayInputStream(bytes);
    }
    this.__a = juBytes(bytes);
    this.__p = 0;
  }
  jmark(ByteArrayInputStream, 'java.io.ByteArrayInputStream');
  ByteArrayInputStream.prototype.read = function (b, off, len) {
    if (b == null) {
      return this.__p < this.__a.length ? signedByte(this.__a[this.__p++]) : -1;
    }
    var o = off == null ? 0 : off;
    var n = len == null ? b.length - o : len;
    var avail = this.__a.length - this.__p;
    if (avail <= 0) return -1;
    if (n > avail) n = avail;
    for (var i = 0; i < n; i++) {
      b[o + i] = signedByte(this.__a[this.__p + i]);
    }
    this.__p += n;
    return n;
  };
  ByteArrayInputStream.prototype.available = function () {
    return this.__a.length - this.__p;
  };
  ByteArrayInputStream.prototype.close = function () { return null; };

  // ── DEFLATE（RFC 1951）/ GZIP（RFC 1952）纯 JS 解压 ──
  function inflateRaw(data) {
    var pos = 0;
    var bitBuf = 0;
    var bitCnt = 0;
    function bits(n) {
      while (bitCnt < n) {
        if (pos >= data.length) throw new Error('deflate: unexpected end');
        bitBuf |= (data[pos++] & 0xff) << bitCnt;
        bitCnt += 8;
      }
      var v = bitBuf & ((1 << n) - 1);
      bitBuf >>>= n;
      bitCnt -= n;
      return v;
    }
    function buildTree(lengths) {
      var blCount = [];
      var i, l;
      for (i = 0; i <= 15; i++) blCount[i] = 0;
      for (i = 0; i < lengths.length; i++) {
        if (lengths[i] > 0) blCount[lengths[i]]++;
      }
      var nextCode = [];
      var code = 0;
      for (l = 1; l <= 15; l++) {
        code = (code + blCount[l - 1]) << 1;
        nextCode[l] = code;
      }
      var table = [];
      var maxLen = 0;
      for (l = 1; l <= 15; l++) {
        table[l] = {};
        if (blCount[l] > 0) maxLen = l;
      }
      for (var sym = 0; sym < lengths.length; sym++) {
        var ln = lengths[sym];
        if (!ln) continue;
        table[ln][nextCode[ln]++] = sym;
      }
      return { t: table, max: maxLen };
    }
    function decodeSym(tree) {
      var code = 0;
      for (var l = 1; l <= tree.max; l++) {
        code = (code << 1) | bits(1);
        var s = tree.t[l][code];
        if (s !== undefined) return s;
      }
      throw new Error('deflate: bad huffman code');
    }
    var LEN_BASE = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
      35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258];
    var LEN_EXTRA = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
      3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];
    var DIST_BASE = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129,
      193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193,
      12289, 16385, 24577];
    var DIST_EXTRA = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
      7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13];
    var out = [];
    function inflateBlock(litTree, distTree) {
      for (;;) {
        var sym = decodeSym(litTree);
        if (sym < 256) {
          out.push(sym);
        } else if (sym === 256) {
          return;
        } else {
          var li = sym - 257;
          if (li < 0 || li >= LEN_BASE.length) {
            throw new Error('deflate: bad length code');
          }
          var len = LEN_BASE[li] +
              (LEN_EXTRA[li] ? bits(LEN_EXTRA[li]) : 0);
          var ds = decodeSym(distTree);
          if (ds < 0 || ds >= DIST_BASE.length) {
            throw new Error('deflate: bad distance code');
          }
          var dist = DIST_BASE[ds] +
              (DIST_EXTRA[ds] ? bits(DIST_EXTRA[ds]) : 0);
          if (dist > out.length) throw new Error('deflate: distance too far');
          for (var k = 0; k < len; k++) out.push(out[out.length - dist]);
        }
      }
    }
    var fixedLit = null;
    var fixedDist = null;
    var last = 0;
    while (!last) {
      last = bits(1);
      var type = bits(2);
      if (type === 0) {
        bitBuf = 0;
        bitCnt = 0;
        var rawLen = (data[pos] & 0xff) | ((data[pos + 1] & 0xff) << 8);
        pos += 4;
        for (var i = 0; i < rawLen; i++) out.push(data[pos++] & 0xff);
      } else if (type === 1) {
        if (!fixedLit) {
          var fl = [];
          for (var s = 0; s < 288; s++) {
            fl.push(s < 144 ? 8 : (s < 256 ? 9 : (s < 280 ? 7 : 8)));
          }
          var fd = [];
          for (var d = 0; d < 32; d++) fd.push(5);
          fixedLit = buildTree(fl);
          fixedDist = buildTree(fd);
        }
        inflateBlock(fixedLit, fixedDist);
      } else if (type === 2) {
        var hlit = bits(5) + 257;
        var hdist = bits(5) + 1;
        var hclen = bits(4) + 4;
        var order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];
        var clLen = [];
        for (var ci = 0; ci < 19; ci++) clLen.push(0);
        for (var cj = 0; cj < hclen; cj++) clLen[order[cj]] = bits(3);
        var clTree = buildTree(clLen);
        var lens = [];
        while (lens.length < hlit + hdist) {
          var cs = decodeSym(clTree);
          if (cs < 16) {
            lens.push(cs);
          } else if (cs === 16) {
            var prev = lens.length ? lens[lens.length - 1] : 0;
            var rep = 3 + bits(2);
            while (rep-- > 0) lens.push(prev);
          } else if (cs === 17) {
            var rep2 = 3 + bits(3);
            while (rep2-- > 0) lens.push(0);
          } else {
            var rep3 = 11 + bits(7);
            while (rep3-- > 0) lens.push(0);
          }
        }
        if (lens.length !== hlit + hdist) {
          throw new Error('deflate: bad code lengths');
        }
        inflateBlock(buildTree(lens.slice(0, hlit)),
            buildTree(lens.slice(hlit, hlit + hdist)));
      } else {
        throw new Error('deflate: invalid block type');
      }
    }
    return out;
  }

  function gzipDecompress(data) {
    var b = juBytes(data);
    if (b.length < 18 || b[0] !== 0x1f || b[1] !== 0x8b || b[2] !== 8) {
      throw new Error('GZIPInputStream: not in gzip format');
    }
    var flags = b[3];
    var p = 10;
    if (flags & 4) {
      var xlen = (b[p] & 0xff) | ((b[p + 1] & 0xff) << 8);
      p += 2 + xlen;
    }
    if (flags & 8) { while (p < b.length && b[p] !== 0) p++; p++; }
    if (flags & 16) { while (p < b.length && b[p] !== 0) p++; p++; }
    if (flags & 2) p += 2;
    return inflateRaw(b.slice(p, b.length - 8));
  }

  var __crc32Table = null;
  function crc32Bytes(bytes) {
    if (!__crc32Table) {
      __crc32Table = [];
      for (var n = 0; n < 256; n++) {
        var c = n;
        for (var k = 0; k < 8; k++) {
          c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
        }
        __crc32Table[n] = c >>> 0;
      }
    }
    var crc = 0xffffffff;
    for (var i = 0; i < bytes.length; i++) {
      crc = (crc >>> 8) ^ __crc32Table[(crc ^ bytes[i]) & 0xff];
    }
    return (crc ^ 0xffffffff) >>> 0;
  }

  // 只用 stored（不压缩）块封装 gzip：无需压缩算法，输出仍满足 RFC 1952，
  // 服务器与 GZIPInputStream 都能正常解压（hutool ZipUtil.gzip 语义）。
  function gzipBytes(data) {
    var b = juBytes(data);
    var out = [0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 0xff];
    var p = 0;
    do {
      var n = Math.min(65535, b.length - p);
      var finalBlock = (p + n >= b.length) ? 1 : 0;
      out.push(finalBlock, n & 0xff, (n >> 8) & 0xff,
          (~n) & 0xff, ((~n) >> 8) & 0xff);
      for (var i = 0; i < n; i++) out.push(b[p + i] & 0xff);
      p += n;
    } while (p < b.length);
    var crc = crc32Bytes(b);
    var len = b.length;
    out.push(crc & 0xff, (crc >>> 8) & 0xff, (crc >>> 16) & 0xff,
        (crc >>> 24) & 0xff);
    out.push(len & 0xff, (len >>> 8) & 0xff, (len >>> 16) & 0xff,
        (len >>> 24) & 0xff);
    return out.map(signedByte);
  }

  function GZIPInputStream(inp) {
    if (!(this instanceof GZIPInputStream)) return new GZIPInputStream(inp);
    this.__in = inp;
    this.__buf = null;
    this.__p = 0;
  }
  jmark(GZIPInputStream, 'java.util.zip.GZIPInputStream');
  GZIPInputStream.prototype.__load = function () {
    if (this.__buf) return;
    var inp = this.__in;
    var all = [];
    if (inp && inp.__a && inp.__p != null) {
      all = inp.__a.slice(inp.__p);
    } else if (inp && typeof inp.read === 'function') {
      var chunk = [];
      for (;;) {
        var n = inp.read(chunk, 0, 8192);
        if (n <= 0) break;
        for (var i = 0; i < n; i++) all.push(chunk[i] & 0xff);
      }
    } else {
      all = juBytes(inp);
    }
    this.__buf = gzipDecompress(all);
  };
  GZIPInputStream.prototype.read = function (b, off, len) {
    this.__load();
    if (b == null) {
      return this.__p < this.__buf.length
          ? signedByte(this.__buf[this.__p++]) : -1;
    }
    var o = off == null ? 0 : off;
    var n = len == null ? b.length - o : len;
    var avail = this.__buf.length - this.__p;
    if (avail <= 0) return -1;
    if (n > avail) n = avail;
    for (var i = 0; i < n; i++) b[o + i] = signedByte(this.__buf[this.__p + i]);
    this.__p += n;
    return n;
  };
  GZIPInputStream.prototype.available = function () {
    if (!this.__buf) return 1;
    return this.__buf.length - this.__p;
  };
  GZIPInputStream.prototype.close = function () { return null; };

  // ── hutool（书源实际导入的包：core.util / core.codec / crypto.digest）──
  var HutoolBase64 = jmark(function HutoolBase64() {},
      'cn.hutool.core.codec.Base64');
  HutoolBase64.encode = function (s) {
    return b64FromBytes(juBytes(s));
  };
  HutoolBase64.decodeStr = function (s) {
    var str = s && typeof s === 'object' && typeof s.length === 'number'
        ? String.fromCharCode.apply(null, juBytes(s)) : String(s == null ? '' : s);
    return utf8Decode(bytesFromB64(str));
  };
  HutoolBase64.decode = HutoolBase64.decodeStr;

  var HutoolDigestUtil = jmark(function HutoolDigestUtil() {},
      'cn.hutool.crypto.digest.DigestUtil');
  function hutoolDigest(algo, data) {
    var bytes = data && typeof data === 'object' && typeof data.length === 'number'
        ? juBytes(data) : utf8Encode(String(data == null ? '' : data));
    return digestBytes(algo, bytes);
  }
  HutoolDigestUtil.md5Hex = function (s) {
    var o = hutoolDigest('MD5', s);
    return o == null ? '' : bytesToHex(o);
  };
  HutoolDigestUtil.sha1Hex = function (s) {
    var o = hutoolDigest('SHA1', s);
    return o == null ? '' : bytesToHex(o);
  };
  HutoolDigestUtil.sha256Hex = function (s) {
    var o = hutoolDigest('SHA256', s);
    return o == null ? '' : bytesToHex(o);
  };
  HutoolDigestUtil.md5 = function (s) {
    var o = hutoolDigest('MD5', s);
    return o == null ? [] : o.map(signedByte);
  };
  HutoolDigestUtil.sha256 = function (s) {
    var o = hutoolDigest('SHA256', s);
    return o == null ? [] : o.map(signedByte);
  };

  var HutoolStrUtil = jmark(function HutoolStrUtil() {},
      'cn.hutool.core.util.StrUtil');
  HutoolStrUtil.isEmpty = function (s) {
    return s == null || String(s).length === 0;
  };
  HutoolStrUtil.isNotEmpty = function (s) {
    return s != null && String(s).length > 0;
  };
  HutoolStrUtil.isBlank = function (s) {
    return s == null || String(s).trim().length === 0;
  };
  HutoolStrUtil.isNotBlank = function (s) {
    return s != null && String(s).trim().length > 0;
  };
  HutoolStrUtil.reverse = function (s) {
    return String(s == null ? '' : s).split('').reverse().join('');
  };
  HutoolStrUtil.utf8Str = function (b) { return utf8Decode(juBytes(b)); };
  HutoolStrUtil.equal = function (a, b, ignoreCase) {
    var x = String(a == null ? '' : a), y = String(b == null ? '' : b);
    return ignoreCase ? x.toLowerCase() === y.toLowerCase() : x === y;
  };
  HutoolStrUtil.format = function (pattern) {
    var args = Array.prototype.slice.call(arguments);
    var i = 1;
    return String(pattern == null ? '' : pattern).replace(/\{\}/g, function () {
      return i < args.length ? String(args[i++]) : '{}';
    });
  };

  var HutoolZipUtil = jmark(function HutoolZipUtil() {},
      'cn.hutool.core.util.ZipUtil');
  HutoolZipUtil.gzip = function (data, charset) {
    return gzipBytes(data);
  };
  HutoolZipUtil.unGzip = function (data) {
    return gzipDecompress(data).map(signedByte);
  };

  // ── javax.crypto（Cipher 复用既有 AES/DES 纯 JS 实现）──
  function SecretKeySpec(key, algo) {
    if (!(this instanceof SecretKeySpec)) {
      return new SecretKeySpec(key, algo);
    }
    this.__k = juBytes(key);
    this.__algo = String(algo == null ? '' : algo);
  }
  jmark(SecretKeySpec, 'javax.crypto.spec.SecretKeySpec');
  SecretKeySpec.prototype.getEncoded = function () {
    return this.__k.map(signedByte);
  };
  SecretKeySpec.prototype.getAlgorithm = function () { return this.__algo; };

  function IvParameterSpec(iv) {
    if (!(this instanceof IvParameterSpec)) return new IvParameterSpec(iv);
    this.__iv = juBytes(iv);
  }
  jmark(IvParameterSpec, 'javax.crypto.spec.IvParameterSpec');
  IvParameterSpec.prototype.getIV = function () {
    return this.__iv.map(signedByte);
  };

  function GCMParameterSpec(tLen, iv) {
    if (!(this instanceof GCMParameterSpec)) {
      return new GCMParameterSpec(tLen, iv);
    }
    this.__tlen = Number(tLen == null ? 128 : tLen);
    this.__iv = juBytes(iv);
  }
  jmark(GCMParameterSpec, 'javax.crypto.spec.GCMParameterSpec');
  GCMParameterSpec.prototype.getTLen = function () { return this.__tlen; };
  GCMParameterSpec.prototype.getIV = function () {
    return this.__iv.map(signedByte);
  };

  function Cipher() {
    this.__tf = '';
    this.__mode = 0;
    this.__key = null;
    this.__iv = null;
    this.__tagBits = 128;
  }
  jmark(Cipher, 'javax.crypto.Cipher');
  Cipher.ENCRYPT_MODE = 1;
  Cipher.DECRYPT_MODE = 2;
  Cipher.getInstance = function (tf) {
    var c = new Cipher();
    c.__tf = String(tf == null ? '' : tf);
    return c;
  };
  Cipher.prototype.init = function (mode, key, iv) {
    this.__mode = Number(mode);
    if (key && key.__k != null) {
      this.__key = key.__k;
    } else {
      this.__key = juBytes(key);
    }
    if (iv == null) {
      this.__iv = null;
    } else if (iv.__tlen != null) {
      this.__iv = iv.__iv;
      this.__tagBits = iv.__tlen;
    } else if (iv.__iv != null) {
      this.__iv = iv.__iv;
    } else {
      this.__iv = juBytes(iv);
    }
    return null;
  };
  Cipher.prototype.getBlockSize = function () {
    var algo = this.__tf.split('/')[0].toUpperCase();
    return (algo === 'DES' || algo === 'DESEDE' || algo === 'TRIPLEDES')
        ? 8 : 16;
  };
  Cipher.prototype.getAlgorithm = function () { return this.__tf; };
  Cipher.prototype.doFinal = function (data) {
    var tf = aesParseTf(this.__tf, this.__iv != null);
    if (!tf) throw new Error('Cipher: unsupported transformation ' + this.__tf);
    var algo = this.__tf.split('/')[0].toUpperCase();
    var input = juBytes(data);
    var out;
    if (algo === 'AES') {
      out = tf.mode === 'GCM'
          ? gcmRun(this.__mode === 1, input, this.__key, this.__iv,
              this.__tagBits)
          : aesRun(this.__mode === 1, input, this.__key, tf.mode, tf.pad,
              this.__iv);
    } else if (algo === 'DES' || algo === 'DESEDE' ||
        algo === 'TRIPLEDES') {
      out = desRun(this.__mode === 1, input, this.__key, tf.mode, tf.pad,
          this.__iv, algo !== 'DES');
    } else {
      throw new Error('Cipher: unsupported algorithm ' + algo);
    }
    if (out == null) throw new Error('Cipher: bad block size or padding');
    return out.map(signedByte);
  };

  // ── java.security（RSA 签名：SHA256withRSA）──
  function X509EncodedKeySpec(bytes) {
    if (!(this instanceof X509EncodedKeySpec)) {
      return new X509EncodedKeySpec(bytes);
    }
    this.__b = juBytes(bytes);
  }
  jmark(X509EncodedKeySpec, 'java.security.spec.X509EncodedKeySpec');
  X509EncodedKeySpec.prototype.getEncoded = function () {
    return this.__b.map(signedByte);
  };

  function PKCS8EncodedKeySpec(bytes) {
    if (!(this instanceof PKCS8EncodedKeySpec)) {
      return new PKCS8EncodedKeySpec(bytes);
    }
    this.__b = juBytes(bytes);
  }
  jmark(PKCS8EncodedKeySpec, 'java.security.spec.PKCS8EncodedKeySpec');
  PKCS8EncodedKeySpec.prototype.getEncoded = function () {
    return this.__b.map(signedByte);
  };

  var JavaKeyFactory = jmark(function JavaKeyFactory() {},
      'java.security.KeyFactory');
  JavaKeyFactory.getInstance = function (algo) {
    return {
      generatePublic: function (spec) {
        var key = rsaParsePublicKey(juBytes(spec.__b));
        if (!key) throw new Error('Invalid RSA public key');
        return { __rsaPub: key };
      },
      generatePrivate: function (spec) {
        var key = rsaParsePrivateKey(juBytes(spec.__b));
        if (!key) throw new Error('Invalid RSA private key');
        return { __rsaPriv: key };
      },
    };
  };

  // JCE `DigestInfo` DER 前缀（RFC 8017 §9.2 note 1）+ 对应摘要。
  var rsaDigestInfos = {
    MD5WITHRSA: {
      prefix: [0x30, 0x20, 0x30, 0x0c, 0x06, 0x08, 0x2a, 0x86, 0x48,
        0x86, 0xf7, 0x0d, 0x02, 0x05, 0x05, 0x00, 0x04, 0x10],
      hash: md5Bytes,
    },
    SHA1WITHRSA: {
      prefix: [0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03,
        0x02, 0x1a, 0x05, 0x00, 0x04, 0x14],
      hash: sha1Bytes,
    },
    SHA256WITHRSA: {
      prefix: [0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48,
        0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20],
      hash: sha256Bytes,
    },
    // JCE 摘要族补齐（审计 R48）：SHA-224/384/512withRSA 的 DigestInfo
    // 前缀按 RFC 8017 §9.2 注 1。
    SHA224WITHRSA: {
      prefix: [0x30, 0x2d, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48,
        0x01, 0x65, 0x03, 0x04, 0x02, 0x04, 0x05, 0x00, 0x04, 0x1c],
      hash: sha224Bytes,
    },
    SHA384WITHRSA: {
      prefix: [0x30, 0x41, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48,
        0x01, 0x65, 0x03, 0x04, 0x02, 0x02, 0x05, 0x00, 0x04, 0x30],
      hash: sha384Bytes,
    },
    SHA512WITHRSA: {
      prefix: [0x30, 0x51, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48,
        0x01, 0x65, 0x03, 0x04, 0x02, 0x03, 0x05, 0x00, 0x04, 0x40],
      hash: sha512Bytes,
    },
  };

  function rsaSignPkcs1(key, data, info) {
    if (!key || !key.n || !key.d) throw new Error('RSA private key not set');
    var n = bnFromBytes(key.n);
    var ctx = montContext(n);
    var k = Math.ceil(bnBitLength(n) / 8);
    var di = info.prefix.concat(info.hash(juBytes(data)));
    var em = rsaPkcs1Pad(di, k, 1);
    var s = bnModPow(bnFromBytes(em), bnFromBytes(key.d), ctx);
    return bnToBytes(s, k).map(signedByte);
  }

  // PKCS#1 v1.5 验签：公钥模幂还原 EM 后逐段比对填充与 DigestInfo
  // （与 rsaSignPkcs1 共用摘要函数，签名/验签口径一致）。
  function rsaVerifyPkcs1(pub, msgBytes, sigBytes, info) {
    if (!pub || !pub.n || !pub.e) throw new Error('RSA public key not set');
    var n = bnFromBytes(pub.n);
    var e = bnFromBytes(pub.e);
    var k = Math.ceil(bnBitLength(n) / 8);
    var em = bnModPow(bnFromBytes(juBytes(sigBytes)), e, montContext(n));
    var emBytes = bnToBytes(em, k);
    // EM = 0x00 0x01 FF..FF 0x00 || DigestInfo
    if (emBytes.length !== k || emBytes[0] !== 0 || emBytes[1] !== 1) {
      return false;
    }
    var i = 2;
    while (i < emBytes.length && emBytes[i] === 0xFF) i++;
    if (i < 10 || i >= emBytes.length || emBytes[i] !== 0) return false;
    var offset = i + 1;
    if (emBytes.length - offset !== info.prefix.length + info.hash(juBytes([])).length) {
      return false;
    }
    for (var j = 0; j < info.prefix.length; j++) {
      if (emBytes[offset + j] !== info.prefix[j]) return false;
    }
    var digest = info.hash(juBytes(msgBytes));
    for (var q = 0; q < digest.length; q++) {
      if (emBytes[offset + info.prefix.length + q] !== digest[q]) return false;
    }
    return true;
  }

  var JavaSignature = jmark(function JavaSignature() {},
      'java.security.Signature');
  JavaSignature.getInstance = function (algo) {
    var name = String(algo == null ? '' : algo).toUpperCase()
        .replace(/-/g, '');
    var sig = {
      __parts: [],
      initSign: function (key) {
        if (!key || !key.__rsaPriv) throw new Error('Signature: private key required');
        sig.__key = key;
        sig.__parts = [];
        return null;
      },
      initVerify: function (key) {
        var pub = key && key.__rsaPub;
        if (!pub && key && key.__rsaPriv) {
          pub = { n: key.__rsaPriv.n, e: key.__rsaPriv.e };
        }
        if (!pub) throw new Error('Signature: public key required');
        sig.__key = pub;
        sig.__parts = [];
        return null;
      },
      update: function (b, off, len) {
        var arr = juBytes(b);
        if (len != null) arr = arr.slice(off || 0, (off || 0) + len);
        for (var i = 0; i < arr.length; i++) sig.__parts.push(arr[i]);
        return null;
      },
      sign: function () {
        var info = rsaDigestInfos[name];
        if (info == null) {
          throw new Error('Signature: unsupported algorithm ' + algo);
        }
        return rsaSignPkcs1(sig.__key.__rsaPriv, sig.__parts, info);
      },
      verify: function (sigBytes) {
        var info = rsaDigestInfos[name];
        if (info == null) {
          throw new Error('Signature: unsupported algorithm ' + algo);
        }
        if (!sig.__key || !sig.__key.n || !sig.__key.e) {
          throw new Error('Signature: public key required');
        }
        var ok = rsaVerifyPkcs1(sig.__key, sig.__parts, juBytes(sigBytes), info);
        sig.__parts = [];
        return ok;
      },
    };
    return sig;
  };

  // legado `Sign`（help/crypto/Sign.kt）：KeyFactory/Signature 的 RSA 族子集。
  // keyAlgorithm 推导与 Sign.kt 一致：algorithm 截 '/' 前、小写后找最后一个
  // 'with' 取后缀，ECDSA 归 EC。EC/DSA 族签名运算未实现，调用时抛
  // NoSuchAlgorithmException（构造与链式 setter 前段保持可用）。
  function makeSign(algorithm) {
    var name = String(algorithm == null ? '' : algorithm);
    var base = name.split('/')[0];
    var sep = base.toLowerCase().lastIndexOf('with');
    var keyName = sep >= 0 ? base.substring(sep + 4) : base;
    var keyAlg = keyName.toLowerCase() === 'ecdsa' ? 'EC' : keyName;
    var info = keyAlg.toUpperCase() === 'RSA'
        ? rsaDigestInfos[name.toUpperCase().replace(/-/g, '')] : null;
    var privateKey = null;
    var publicKey = null;
    function unsupported() {
      throw new Error('NoSuchAlgorithmException: '
          + 'Cannot find any provider supporting ' + name);
    }
    function toBytes(v) {
      return typeof v === 'string' ? utf8Encode(v) : juBytes(v);
    }
    var obj = {
      setPrivateKey: function (key) {
        if (info == null) unsupported();
        privateKey = rsaParsePrivateKey(toBytes(key));
        if (!privateKey) throw new Error('InvalidKeySpecException: RSA private key');
        return obj;
      },
      setPublicKey: function (key) {
        if (info == null) unsupported();
        publicKey = rsaParsePublicKey(toBytes(key));
        if (!publicKey) throw new Error('InvalidKeySpecException: RSA public key');
        return obj;
      },
      sign: function (data) {
        if (info == null) unsupported();
        if (!privateKey) {
          throw new Error('IllegalArgumentException: '
              + 'Private key is required for signing');
        }
        return rsaSignPkcs1(privateKey, toBytes(data), info);
      },
      signHex: function (data) {
        return bytesToHex(obj.sign(data));
      },
      verify: function (data, signature) {
        if (info == null) unsupported();
        if (!publicKey) {
          throw new Error('IllegalArgumentException: '
              + 'Public key is required for verification');
        }
        return rsaVerifyPkcs1(publicKey, toBytes(data), toBytes(signature), info);
      },
    };
    return obj;
  }

  // 文件族虚拟路径工具：sourceContext 预置（另一个 IIFE）的文件族段经
  // global 复用这里的 UTF-8/MD5/HEX/Base64 实现，避免两份漂移。
  global.__syMd5Hex16 = function (s) {
    return bytesToHex(md5Bytes(utf8Encode(String(s)))).substring(0, 16);
  };
  global.__syHexToBytes = hexToBytes;
  global.__syB64FromBytes = b64FromBytes;

  var JavaMessageDigest = jmark(function JavaMessageDigest() {},
      'java.security.MessageDigest');
  JavaMessageDigest.getInstance = function (algo) {
    var md = {
      __parts: [],
      update: function (b, off, len) {
        var arr = juBytes(b);
        if (len != null) arr = arr.slice(off || 0, (off || 0) + len);
        for (var i = 0; i < arr.length; i++) md.__parts.push(arr[i]);
        return null;
      },
      digest: function () {
        var out = digestBytes(String(algo == null ? '' : algo), md.__parts);
        md.__parts = [];
        return out == null ? [] : out.map(signedByte);
      },
      getAlgorithm: function () { return String(algo == null ? '' : algo); },
      reset: function () { md.__parts = []; return null; },
    };
    return md;
  };

  // ── okhttp3（网络走 java.connect 的确定性重放）──
  function OkHttpMediaType(s) {
    if (!(this instanceof OkHttpMediaType)) return new OkHttpMediaType(s);
    this.__s = String(s == null ? '' : s);
  }
  jmark(OkHttpMediaType, 'okhttp3.MediaType');
  OkHttpMediaType.parse = function (s) { return new OkHttpMediaType(s); };
  OkHttpMediaType.get = OkHttpMediaType.parse;
  OkHttpMediaType.prototype.toString = function () { return this.__s; };

  function OkHttpRequestBody(body, mt) {
    if (!(this instanceof OkHttpRequestBody)) {
      return new OkHttpRequestBody(body, mt);
    }
    // 二进制体保留原始字节（legado `RequestBody.create(mediaType, byte[])`
    // 原样发送）：先做 UTF-8 容错解码再回编码会破坏密文/签名载荷。
    if (body && body.length != null && typeof body !== 'string') {
      this.__bytes = juBytes(body).map(function (x) { return x & 0xff; });
      this.__text = null;
    } else {
      this.__bytes = null;
      this.__text = String(body == null ? '' : body);
    }
    this.__mt = mt;
  }
  jmark(OkHttpRequestBody, 'okhttp3.RequestBody');
  OkHttpRequestBody.create = function (a, b) {
    var body = a, mt = b;
    if (a instanceof OkHttpMediaType) { mt = a; body = b; }
    return new OkHttpRequestBody(body, mt);
  };
  OkHttpRequestBody.prototype.toString = function () {
    if (this.__text == null) this.__text = utf8Decode(this.__bytes || []);
    return this.__text;
  };
  OkHttpRequestBody.prototype.contentType = function () {
    return this.__mt || null;
  };

  function OkHttpRequest() {
    this.__url = '';
    this.__method = 'GET';
    this.__body = null;
    this.__headers = {};
  }
  jmark(OkHttpRequest, 'okhttp3.Request');
  OkHttpRequest.prototype.url = function () { return this.__url; };

  function OkHttpRequestBuilder() {
    if (!(this instanceof OkHttpRequestBuilder)) return new OkHttpRequestBuilder();
    this.__r = new OkHttpRequest();
  }
  jmark(OkHttpRequestBuilder, 'okhttp3.Request.Builder');
  OkHttpRequest.Builder = OkHttpRequestBuilder;
  OkHttpRequestBuilder.prototype.url = function (u) {
    this.__r.__url = String(u == null ? '' : u);
    return this;
  };
  OkHttpRequestBuilder.prototype.addHeader = function (k, v) {
    this.__r.__headers[String(k)] = String(v == null ? '' : v);
    return this;
  };
  OkHttpRequestBuilder.prototype.header = function (k, v) {
    this.__r.__headers[String(k)] = String(v == null ? '' : v);
    return this;
  };
  OkHttpRequestBuilder.prototype.removeHeader = function (k) {
    delete this.__r.__headers[String(k)];
    return this;
  };
  OkHttpRequestBuilder.prototype.headers = function (m) {
    if (m && typeof m === 'object') {
      for (var k in m) this.__r.__headers[String(k)] = String(m[k]);
    }
    return this;
  };
  OkHttpRequestBuilder.prototype.get = function () {
    this.__r.__method = 'GET';
    return this;
  };
  OkHttpRequestBuilder.prototype.head = function () {
    this.__r.__method = 'HEAD';
    return this;
  };
  OkHttpRequestBuilder.prototype.post = function (body) {
    this.__r.__method = 'POST';
    this.__r.__body = body;
    return this;
  };
  OkHttpRequestBuilder.prototype.put = function (body) {
    this.__r.__method = 'PUT';
    this.__r.__body = body;
    return this;
  };
  OkHttpRequestBuilder.prototype.delete = function (body) {
    this.__r.__method = 'DELETE';
    this.__r.__body = body == null ? null : body;
    return this;
  };
  OkHttpRequestBuilder.prototype.method = function (m, body) {
    this.__r.__method = String(m == null ? 'GET' : m).toUpperCase();
    this.__r.__body = body == null ? null : body;
    return this;
  };
  OkHttpRequestBuilder.prototype.build = function () { return this.__r; };

  function jMergeUrlOpts(url, opts) {
    var u = String(url == null ? '' : url);
    var idx = u.indexOf(',{');
    if (idx >= 0) {
      var merged = null;
      try { merged = JSON.parse(u.substring(idx + 1)); } catch (e) { merged = null; }
      if (!merged || typeof merged !== 'object') return u;
      for (var k in opts) merged[k] = opts[k];
      return u.substring(0, idx) + ',' + JSON.stringify(merged);
    }
    for (var ck in opts) return u + ',' + JSON.stringify(opts);
    return u;
  }

  function okExecute(req) {
    var url = String(req.__url || '');
    if (!url) throw new Error('okhttp: Request.url must be set');
    var method = String(req.__method || 'GET').toUpperCase();
    var body = null;
    var bodyB64 = null;
    var bodyType = null;
    if (req.__body != null) {
      var rb = req.__body;
      if (rb && typeof rb.contentType === 'function') {
        bodyType = rb.contentType();
      }
      // 二进制 RequestBody 走 base64 通道：文本通道会按 UTF-8 容错解码，
      // 密文/签名载荷一旦损坏，服务端只回鉴权失败，规则层看不到原因。
      if (rb && rb.__bytes) {
        bodyB64 = b64FromBytes(rb.__bytes);
      } else {
        body = rb && rb.__text != null ? String(rb.__text) : String(rb);
      }
    }
    var headers = {};
    var hasHeaders = false;
    for (var k in req.__headers) {
      headers[k] = req.__headers[k];
      hasHeaders = true;
    }
    // OkHttp 会把 RequestBody 的媒体类型写进 Content-Type（FormBody /
    // MultipartBody 依赖这一点）；显式 header 优先。
    if (bodyType != null && headers['Content-Type'] == null) {
      headers['Content-Type'] = String(bodyType);
      hasHeaders = true;
    }
    var opts = {};
    if (hasHeaders) opts.headers = headers;
    if (method !== 'GET') opts.method = method;
    if (bodyB64 != null) opts._syBodyB64 = bodyB64;
    else if (body != null) opts.body = body;
    var merged = jMergeUrlOpts(url, opts);
    // POST 沿用宿主约定的 `url||POST||body` 组合键（settle 拆分后发 POST）；
    // 二进制体已进选项串（`_syBodyB64`），不再拼进键。
    var key = method === 'POST' && body != null
        ? merged + '||POST||' + body : merged;
    var base = global.java && global.java.connect
        ? global.java.connect(key) : null;
    if (!base) throw new Error('okhttp: network bridge unavailable');
    return new OkHttpResponse(key, base);
  }

  function OkHttpResponse(key, base) {
    this.__key = key;
    this.__r = base;
  }
  jmark(OkHttpResponse, 'okhttp3.Response');
  OkHttpResponse.prototype.code = function () { return this.__r.code(); };
  OkHttpResponse.prototype.isSuccessful = function () {
    return this.__r.isSuccessful();
  };
  OkHttpResponse.prototype.message = function () { return this.__r.message(); };
  OkHttpResponse.prototype.header = function (name) {
    return this.__r.header(name);
  };
  OkHttpResponse.prototype.headers = function () {
    var m = this.__r.headers();
    var names = [];
    for (var k in m) names.push(k);
    return {
      names: function () { return names; },
      get: function (n) {
        return m.get ? m.get(n) : (m[n] == null ? null : m[n]);
      },
      values: function (n) {
        var v = m.get ? m.get(n) : m[n];
        return v == null ? [] : [v];
      },
      toString: function () { return String(m); },
    };
  };
  OkHttpResponse.prototype.request = function () {
    var u = this.__r.url ? this.__r.url() : this.__key;
    return { url: function () { return u; }, method: function () { return ''; } };
  };
  OkHttpResponse.prototype.body = function () {
    var r = this.__r;
    return {
      string: function () { return String(r.body()); },
      bytes: function () {
        return r.bodyAsBytes ? r.bodyAsBytes() : jsBytes(r.body());
      },
      contentLength: function () { return juBytes(r.body()).length; },
      contentType: function () { return null; },
      close: function () { return null; },
      toString: function () { return String(r.body()); },
    };
  };
  OkHttpResponse.prototype.toString = function () {
    return String(this.__r.body());
  };
  OkHttpResponse.prototype.close = function () { return null; };

  function OkHttpCall(client, req) {
    this.__client = client;
    this.__req = req;
  }
  jmark(OkHttpCall, 'okhttp3.Call');
  OkHttpCall.prototype.execute = function () { return okExecute(this.__req); };
  OkHttpCall.prototype.isExecuted = function () { return true; };
  OkHttpCall.prototype.cancel = function () { return null; };

  function OkHttpClient() {}
  jmark(OkHttpClient, 'okhttp3.OkHttpClient');
  OkHttpClient.prototype.newCall = function (req) {
    return new OkHttpCall(this, req);
  };
  OkHttpClient.prototype.newBuilder = function () { return this; };

  // ── org.jsoup / StrResponse ──
  var JsoupShim = jmark(function JsoupShim() {}, 'org.jsoup.Jsoup');
  JsoupShim.connect = function (url) {
    if (global.org && global.org.jsoup && global.org.jsoup.Jsoup) {
      return global.org.jsoup.Jsoup.connect(url);
    }
    throw new Error('Jsoup.connect: 需要在书源上下文中运行');
  };
  // `Packages.org.jsoup.Jsoup.parse` 与顶层 `org.jsoup.Jsoup.parse` 同源：
  // parse 的纯 JS 实现由 jsoup_dom.dart 预置脚本挂到 global.org 上。
  JsoupShim.parse = function (html, baseUri) {
    var J = global.org && global.org.jsoup && global.org.jsoup.Jsoup;
    if (J && typeof J.parse === 'function') return J.parse(html, baseUri);
    throw new Error('Jsoup.parse: 需要在书源上下文中运行');
  };
  JsoupShim.parseBodyFragment = function (html, baseUri) {
    return JsoupShim.parse(html, baseUri);
  };
  var JsoupConnection = {
    Method: {
      GET: 'GET', POST: 'POST', PUT: 'PUT', DELETE: 'DELETE',
      PATCH: 'PATCH', HEAD: 'HEAD', OPTIONS: 'OPTIONS', TRACE: 'TRACE',
    },
  };
  jmark(JsoupConnection, 'org.jsoup.Connection');

  function LegadoStrResponse(url, body) {
    if (!(this instanceof LegadoStrResponse)) {
      return new LegadoStrResponse(url, body);
    }
    this.__u = String(url == null ? '' : url);
    this.__b = String(body == null ? '' : body);
  }
  jmark(LegadoStrResponse, 'io.legado.app.help.http.StrResponse');
  LegadoStrResponse.prototype.body = function () { return this.__b; };
  LegadoStrResponse.prototype.bodyAsBytes = function () {
    return jsBytes(this.__b);
  };
  LegadoStrResponse.prototype.code = function () { return 200; };
  LegadoStrResponse.prototype.message = function () { return 'OK'; };
  LegadoStrResponse.prototype.isSuccessful = function () { return true; };
  LegadoStrResponse.prototype.url = function () { return this.__u; };
  LegadoStrResponse.prototype.charset = function () { return 'UTF-8'; };
  LegadoStrResponse.prototype.header = function (name) { return ''; };
  LegadoStrResponse.prototype.headers = function () {
    var m = {};
    Object.defineProperty(m, 'get', {
      value: function (n) { return null; },
      enumerable: false,
    });
    return m;
  };
  LegadoStrResponse.prototype.cookies = function () {
    var m = {};
    Object.defineProperty(m, 'get', {
      value: function (n) { return null; },
      enumerable: false,
    });
    return m;
  };
  LegadoStrResponse.prototype.raw = function () {
    var u = this.__u;
    return {
      request: function () { return { url: function () { return u; } }; },
      code: function () { return 200; },
      headers: function () { return {}; },
    };
  };
  LegadoStrResponse.prototype.toString = function () { return this.__b; };

  // ── JSON 类库面（org.json / fastjson / Gson）──
  //
  // Android 平台脚本常用 `importClass(Packages.org.json.JSONObject)` 或
  // fastjson/Gson 处理 JSON。这里用原生 JSON 实现同语义的读写方法，
  // 取值口径对齐 Android `org.json`（数值/布尔可解析字符串会被转换，
  // 缺失键 get* 抛 JSONException、opt* 取默认值）。未实现的方法保持不存在。

  function jJsonError(msg) { return new Error('JSONException: ' + msg); }
  function jJsonOwn(m, k) { return Object.prototype.hasOwnProperty.call(m, k); }
  function jJsonParseText(s) {
    var str = String(s == null ? '' : s);
    try {
      return JSON.parse(str);
    } catch (e) {
      throw jJsonError('Unterminated or malformed JSON value');
    }
  }
  function jJsonParseObjectText(s) {
    var v = jJsonParseText(s);
    if (v == null || typeof v !== 'object' || Array.isArray(v)) {
      throw jJsonError('Value ' + String(s) + ' cannot be converted to JSONObject');
    }
    return v;
  }
  function jJsonParseArrayText(s) {
    var v = jJsonParseText(s);
    if (!Array.isArray(v)) {
      throw jJsonError('Value ' + String(s) + ' cannot be converted to JSONArray');
    }
    return v;
  }
  function jJsonToNumber(v) {
    if (typeof v === 'number') return v;
    if (v != null && typeof v === 'object' && v instanceof Number) return Number(v);
    if (typeof v === 'string') {
      var n = parseFloat(v);
      return isNaN(n) ? null : n;
    }
    return null;
  }
  function jJsonToInt(v) {
    var n = jJsonToNumber(v);
    return n == null ? null : (n < 0 ? Math.ceil(n) : Math.floor(n));
  }
  function jJsonToBool(v) {
    if (typeof v === 'boolean') return v;
    if (typeof v === 'string') {
      var s = v.toLowerCase();
      if (s === 'true') return true;
      if (s === 'false') return false;
    }
    return null;
  }

  function JSONObject(arg) {
    if (!(this instanceof JSONObject)) return new JSONObject(arg);
    this.__m = {};
    if (arg == null) return;
    if (typeof arg === 'string') {
      this.__m = jJsonParseObjectText(arg);
      return;
    }
    if (arg && typeof arg === 'object' && arg.__m && typeof arg.__m === 'object') {
      for (var k0 in arg.__m) {
        if (jJsonOwn(arg.__m, k0)) this.__m[k0] = arg.__m[k0];
      }
      return;
    }
    if (typeof arg === 'object' && !Array.isArray(arg)) {
      for (var k in arg) {
        if (jJsonOwn(arg, k)) this.__m[k] = arg[k];
      }
      return;
    }
    throw jJsonError('Value ' + String(arg) + ' cannot be converted to JSONObject');
  }
  jmark(JSONObject, 'org.json.JSONObject');
  JSONObject.prototype.get = function (name) {
    var key = String(name);
    if (!jJsonOwn(this.__m, key)) throw jJsonError('No value for ' + key);
    return this.__m[key] == null ? null : this.__m[key];
  };
  JSONObject.prototype.opt = function (name) {
    var key = String(name);
    if (!jJsonOwn(this.__m, key)) return null;
    return this.__m[key] == null ? null : this.__m[key];
  };
  JSONObject.prototype.has = function (name) {
    return jJsonOwn(this.__m, String(name));
  };
  JSONObject.prototype.containsKey = function (name) { return this.has(name); };
  JSONObject.prototype.isNull = function (name) {
    var key = String(name);
    return !jJsonOwn(this.__m, key) || this.__m[key] == null;
  };
  JSONObject.prototype.getString = function (name) {
    var v = this.get(name);
    if (v == null) throw jJsonError(name + ' is null');
    return typeof v === 'string' ? v : String(v);
  };
  JSONObject.prototype.optString = function (name, fallback) {
    var v = this.opt(name);
    if (v == null) return fallback == null ? '' : String(fallback);
    return typeof v === 'string' ? v : String(v);
  };
  JSONObject.prototype.getInt = function (name) {
    var n = jJsonToInt(this.get(name));
    if (n == null) throw jJsonError(name + ' is not an int');
    return n;
  };
  JSONObject.prototype.optInt = function (name, fallback) {
    var n = jJsonToInt(this.opt(name));
    return n == null ? (fallback == null ? 0 : fallback) : n;
  };
  JSONObject.prototype.getLong = function (name) {
    var n = jJsonToInt(this.get(name));
    if (n == null) throw jJsonError(name + ' is not a long');
    return n;
  };
  JSONObject.prototype.optLong = function (name, fallback) {
    return this.optInt(name, fallback == null ? 0 : fallback);
  };
  JSONObject.prototype.getInteger = function (name) {
    return jJsonToInt(this.opt(name));
  };
  JSONObject.prototype.getIntValue = function (name) {
    return this.optInt(name, 0);
  };
  JSONObject.prototype.getDouble = function (name) {
    var n = jJsonToNumber(this.get(name));
    if (n == null) throw jJsonError(name + ' is not a double');
    return n;
  };
  JSONObject.prototype.optDouble = function (name, fallback) {
    var n = jJsonToNumber(this.opt(name));
    return n == null ? (fallback == null ? NaN : fallback) : n;
  };
  JSONObject.prototype.getBoolean = function (name) {
    var b = jJsonToBool(this.get(name));
    if (b == null) throw jJsonError(name + ' is not a boolean');
    return b;
  };
  JSONObject.prototype.optBoolean = function (name, fallback) {
    var b = jJsonToBool(this.opt(name));
    return b == null ? (fallback == null ? false : fallback) : b;
  };
  JSONObject.prototype.getBooleanValue = function (name) {
    return this.optBoolean(name, false);
  };
  JSONObject.prototype.getJSONObject = function (name) {
    var v = this.get(name);
    if (v == null || typeof v !== 'object' || Array.isArray(v)) {
      throw jJsonError(name + ' is not a JSONObject');
    }
    return new JSONObject(v);
  };
  JSONObject.prototype.optJSONObject = function (name) {
    var v = this.opt(name);
    return (v != null && typeof v === 'object' && !Array.isArray(v))
        ? new JSONObject(v) : null;
  };
  JSONObject.prototype.getJSONArray = function (name) {
    var v = this.get(name);
    if (!Array.isArray(v)) throw jJsonError(name + ' is not a JSONArray');
    return new JSONArray(v);
  };
  JSONObject.prototype.optJSONArray = function (name) {
    var v = this.opt(name);
    return Array.isArray(v) ? new JSONArray(v) : null;
  };
  JSONObject.prototype.put = function (name, value) {
    this.__m[String(name)] = value;
    return this;
  };
  JSONObject.prototype.remove = function (name) {
    var key = String(name);
    if (!jJsonOwn(this.__m, key)) return null;
    var v = this.__m[key];
    delete this.__m[key];
    return v == null ? null : v;
  };
  JSONObject.prototype.keys = function () {
    var keys = Object.keys(this.__m);
    var i = 0;
    return {
      hasNext: function () { return i < keys.length; },
      next: function () { return keys[i++]; },
      remove: function () { throw new Error('UnsupportedOperationException'); },
    };
  };
  JSONObject.prototype.keySet = function () { return Object.keys(this.__m); };
  JSONObject.prototype.names = function () { return Object.keys(this.__m); };
  JSONObject.prototype.length = function () { return Object.keys(this.__m).length; };
  JSONObject.prototype.size = function () { return Object.keys(this.__m).length; };
  JSONObject.prototype.isEmpty = function () {
    return Object.keys(this.__m).length === 0;
  };
  JSONObject.prototype.toString = function () { return JSON.stringify(this.__m); };
  JSONObject.prototype.toJSON = function () { return this.__m; };

  function JSONArray(arg) {
    if (!(this instanceof JSONArray)) return new JSONArray(arg);
    this.__a = [];
    if (arg == null) return;
    if (typeof arg === 'string') {
      this.__a = jJsonParseArrayText(arg);
      return;
    }
    if (arg && typeof arg === 'object' && Array.isArray(arg.__a)) {
      for (var i0 = 0; i0 < arg.__a.length; i0++) this.__a.push(arg.__a[i0]);
      return;
    }
    if (typeof arg === 'object' && typeof arg.length === 'number') {
      for (var i = 0; i < arg.length; i++) this.__a.push(arg[i]);
      return;
    }
    throw jJsonError('Value ' + String(arg) + ' cannot be converted to JSONArray');
  }
  jmark(JSONArray, 'org.json.JSONArray');
  function jJsonIndex(a, i, strict) {
    var idx = jJsonToInt(i);
    if (idx == null || idx < 0 || idx >= a.length) {
      if (strict !== false) {
        throw jJsonError('Index ' + i + ' out of range [0..' + a.length + ')');
      }
      return null;
    }
    return idx;
  }
  JSONArray.prototype.get = function (i) {
    var idx = jJsonIndex(this.__a, i);
    return this.__a[idx] == null ? null : this.__a[idx];
  };
  JSONArray.prototype.opt = function (i) {
    var idx = jJsonIndex(this.__a, i, false);
    if (idx == null) return null;
    return this.__a[idx] == null ? null : this.__a[idx];
  };
  JSONArray.prototype.isNull = function (i) {
    var idx = jJsonIndex(this.__a, i, false);
    return idx == null || this.__a[idx] == null;
  };
  JSONArray.prototype.getString = function (i) {
    var v = this.get(i);
    if (v == null) throw jJsonError(i + ' is null');
    return typeof v === 'string' ? v : String(v);
  };
  JSONArray.prototype.optString = function (i, fallback) {
    var v = this.opt(i);
    if (v == null) return fallback == null ? '' : String(fallback);
    return typeof v === 'string' ? v : String(v);
  };
  JSONArray.prototype.getInt = function (i) {
    var n = jJsonToInt(this.get(i));
    if (n == null) throw jJsonError(i + ' is not an int');
    return n;
  };
  JSONArray.prototype.optInt = function (i, fallback) {
    var n = jJsonToInt(this.opt(i));
    return n == null ? (fallback == null ? 0 : fallback) : n;
  };
  JSONArray.prototype.getLong = function (i) {
    var n = jJsonToInt(this.get(i));
    if (n == null) throw jJsonError(i + ' is not a long');
    return n;
  };
  JSONArray.prototype.getDouble = function (i) {
    var n = jJsonToNumber(this.get(i));
    if (n == null) throw jJsonError(i + ' is not a double');
    return n;
  };
  JSONArray.prototype.getBoolean = function (i) {
    var b = jJsonToBool(this.get(i));
    if (b == null) throw jJsonError(i + ' is not a boolean');
    return b;
  };
  JSONArray.prototype.getJSONObject = function (i) {
    var v = this.get(i);
    if (v == null || typeof v !== 'object' || Array.isArray(v)) {
      throw jJsonError(i + ' is not a JSONObject');
    }
    return new JSONObject(v);
  };
  JSONArray.prototype.optJSONObject = function (i) {
    var v = this.opt(i);
    return (v != null && typeof v === 'object' && !Array.isArray(v))
        ? new JSONObject(v) : null;
  };
  JSONArray.prototype.getJSONArray = function (i) {
    var v = this.get(i);
    if (!Array.isArray(v)) throw jJsonError(i + ' is not a JSONArray');
    return new JSONArray(v);
  };
  JSONArray.prototype.optJSONArray = function (i) {
    var v = this.opt(i);
    return Array.isArray(v) ? new JSONArray(v) : null;
  };
  JSONArray.prototype.put = function (a, b) {
    if (arguments.length > 1) {
      var idx = jJsonToInt(a);
      if (idx == null || idx < 0 || idx > this.__a.length) {
        throw jJsonError('Index ' + a + ' out of range [0..' + this.__a.length + ']');
      }
      if (idx === this.__a.length) this.__a.push(b);
      else this.__a[idx] = b;
      return this;
    }
    this.__a.push(a);
    return this;
  };
  JSONArray.prototype.remove = function (i) {
    var idx = jJsonIndex(this.__a, i, false);
    if (idx == null) return null;
    var out = this.__a.splice(idx, 1);
    return out.length ? (out[0] == null ? null : out[0]) : null;
  };
  JSONArray.prototype.length = function () { return this.__a.length; };
  JSONArray.prototype.size = function () { return this.__a.length; };
  JSONArray.prototype.toString = function () { return JSON.stringify(this.__a); };
  JSONArray.prototype.toJSON = function () { return this.__a; };

  var FastjsonJSON = jmark(function FastjsonJSON() {},
      'com.alibaba.fastjson.JSON');
  FastjsonJSON.parse = function (s) {
    var v = jJsonParseText(s);
    if (Array.isArray(v)) return new JSONArray(v);
    if (v != null && typeof v === 'object') return new JSONObject(v);
    return v;
  };
  FastjsonJSON.parseObject = function (s) {
    return new JSONObject(jJsonParseObjectText(s));
  };
  FastjsonJSON.parseArray = function (s) {
    return new JSONArray(jJsonParseArrayText(s));
  };
  FastjsonJSON.toJSONString = function (o) {
    return JSON.stringify(o == null ? null : o);
  };

  function Gson() {}
  jmark(Gson, 'com.google.gson.Gson');
  Gson.prototype.toJson = function (o) {
    return JSON.stringify(o == null ? null : o);
  };
  Gson.prototype.fromJson = function (s) {
    return jJsonParseText(s);
  };
  function GsonBuilder() {}
  jmark(GsonBuilder, 'com.google.gson.GsonBuilder');
  GsonBuilder.prototype.create = function () { return new Gson(); };
  var GsonJsonParser = jmark(function GsonJsonParser() {},
      'com.google.gson.JsonParser');
  GsonJsonParser.parseString = function (s) { return jJsonParseText(s); };
  GsonJsonParser.parse = GsonJsonParser.parseString;

  // 注册类查找：`java.lang.Class.forName(类全名)`，命中返回已注册的类。
  function JavaClass() {}
  jmark(JavaClass, 'java.lang.Class');
  JavaClass.forName = function (name) {
    var parts = String(name == null ? '' : name).split('.');
    var cur = Packages;
    for (var i = 0; i < parts.length; i++) {
      if (cur == null || typeof cur !== 'object') { cur = null; break; }
      cur = cur[parts[i]];
    }
    if (!cur || !cur.__javaName) {
      throw new Error('ClassNotFoundException: ' + String(name));
    }
    return cur;
  };

  // ── okhttp3 FormBody / MultipartBody（body 自带 Content-Type）──
  function jFormEncode(s) {
    return encodeURIComponent(String(s == null ? '' : s)).replace(/%20/g, '+');
  }
  function OkHttpFormBody(pairs) {
    this.__text = '';
    for (var i = 0; i < pairs.length; i++) {
      if (i > 0) this.__text += '&';
      // addEncoded 的键值已编码：原样输出，不能再 encode 一次（legado
      // OkHttp FormBody.Builder.addEncoded 语义）。
      var enc = pairs[i][2] === true;
      var k = enc ? String(pairs[i][0]) : jFormEncode(pairs[i][0]);
      var v = enc ? String(pairs[i][1]) : jFormEncode(pairs[i][1]);
      this.__text += k + '=' + v;
    }
  }
  jmark(OkHttpFormBody, 'okhttp3.FormBody');
  OkHttpFormBody.prototype.contentType = function () {
    return new OkHttpMediaType('application/x-www-form-urlencoded');
  };
  OkHttpFormBody.prototype.toString = function () { return this.__text; };
  function OkHttpFormBodyBuilder() {
    if (!(this instanceof OkHttpFormBodyBuilder)) {
      return new OkHttpFormBodyBuilder();
    }
    this.__pairs = [];
  }
  jmark(OkHttpFormBodyBuilder, 'okhttp3.FormBody.Builder');
  OkHttpFormBody.Builder = OkHttpFormBodyBuilder;
  OkHttpFormBodyBuilder.prototype.add = function (k, v) {
    this.__pairs.push([String(k), String(v == null ? '' : v), false]);
    return this;
  };
  OkHttpFormBodyBuilder.prototype.addEncoded = function (k, v) {
    this.__pairs.push([String(k), String(v == null ? '' : v), true]);
    return this;
  };
  OkHttpFormBodyBuilder.prototype.build = function () {
    return new OkHttpFormBody(this.__pairs.slice());
  };

  function jMpQuote(s) {
    return String(s == null ? '' : s)
        .replace(/"/g, '%22').replace(/\r/g, '%0D').replace(/\n/g, '%0A');
  }
  function jMpPart(headers, body) {
    return { __headers: headers, __body: String(body == null ? '' : body) };
  }
  function OkHttpMultipartBody(parts, type) {
    var baseType = type ? String(type) : 'multipart/form-data';
    // 边界由 parts 内容派生：同一脚本跨重放轮构建出同一 body（可命中缓存）。
    var sig = baseType;
    for (var i = 0; i < parts.length; i++) {
      sig += '|' + JSON.stringify(parts[i].__headers) + '|' + parts[i].__body;
    }
    this.__boundary =
        '----NexHubBoundary' + bytesToHex(md5Bytes(utf8Encode(sig))).substring(0, 16);
    this.__text = '';
    for (var j = 0; j < parts.length; j++) {
      this.__text += '--' + this.__boundary + '\r\n';
      var hs = parts[j].__headers;
      for (var h = 0; h < hs.length; h++) {
        this.__text += hs[h][0] + ': ' + hs[h][1] + '\r\n';
      }
      this.__text += '\r\n' + parts[j].__body + '\r\n';
    }
    this.__text += '--' + this.__boundary + '--\r\n';
    this.__type = baseType + '; boundary=' + this.__boundary;
  }
  jmark(OkHttpMultipartBody, 'okhttp3.MultipartBody');
  OkHttpMultipartBody.prototype.contentType = function () {
    return new OkHttpMediaType(this.__type);
  };
  OkHttpMultipartBody.prototype.toString = function () { return this.__text; };
  function OkHttpMultipartBodyBuilder() {
    if (!(this instanceof OkHttpMultipartBodyBuilder)) {
      return new OkHttpMultipartBodyBuilder();
    }
    this.__parts = [];
    this.__type = 'multipart/form-data';
  }
  jmark(OkHttpMultipartBodyBuilder, 'okhttp3.MultipartBody.Builder');
  OkHttpMultipartBody.Builder = OkHttpMultipartBodyBuilder;
  OkHttpMultipartBodyBuilder.prototype.setType = function (mt) {
    this.__type = String(mt == null ? '' : mt);
    return this;
  };
  OkHttpMultipartBodyBuilder.prototype.addFormDataPart = function (name, a, b) {
    var cd = 'form-data; name="' + jMpQuote(name) + '"';
    if (arguments.length > 2) {
      var body = b;
      var headers = [['Content-Disposition',
          cd + '; filename="' + jMpQuote(a) + '"']];
      var ct = body && typeof body.contentType === 'function'
          ? body.contentType() : null;
      if (ct != null) headers.push(['Content-Type', String(ct)]);
      this.__parts.push(jMpPart(headers, body && body.__text != null
          ? body.__text : body));
    } else {
      this.__parts.push(jMpPart([['Content-Disposition', cd]], a));
    }
    return this;
  };
  OkHttpMultipartBodyBuilder.prototype.addPart = function (body, headers) {
    var hs = [];
    var ct = body && typeof body.contentType === 'function'
        ? body.contentType() : null;
    if (ct != null) hs.push(['Content-Type', String(ct)]);
    this.__parts.push(jMpPart(hs, body && body.__text != null
        ? body.__text : body));
    return this;
  };
  OkHttpMultipartBodyBuilder.prototype.build = function () {
    return new OkHttpMultipartBody(this.__parts.slice(), this.__type);
  };

  // ── java.math.BigInteger（审计 R47：书源 RSA/ID 编码常用）──
  // 16 位 limb 小端数组复用 RSA 预置的 bn* 运算；符号单独保存。
  function bigAddMag(a, b) {
    var r = [];
    var carry = 0;
    var n = Math.max(a.length, b.length);
    for (var i = 0; i < n; i++) {
      var v = (i < a.length ? a[i] : 0) + (i < b.length ? b[i] : 0) + carry;
      r.push(v & 0xffff);
      carry = v >>> 16;
    }
    if (carry > 0) r.push(carry);
    return bnTrim(r);
  }
  function bigMulMag(a, b) {
    if ((a.length === 1 && a[0] === 0) || (b.length === 1 && b[0] === 0)) {
      return [0];
    }
    var r = new Array(a.length + b.length);
    for (var i = 0; i < r.length; i++) r[i] = 0;
    for (var x = 0; x < a.length; x++) {
      var carry = 0;
      for (var y = 0; y < b.length; y++) {
        var t = r[x + y] + a[x] * b[y] + carry;
        r[x + y] = t & 0xffff;
        carry = Math.floor(t / 65536);
      }
      var z = x + b.length;
      while (carry > 0) {
        var t2 = r[z] + carry;
        r[z] = t2 & 0xffff;
        carry = Math.floor(t2 / 65536);
        z++;
      }
    }
    return bnTrim(r);
  }
  // 长除法：二进制移位减（脚本量级足够；a、b 均非负）。
  function bigDivRemMag(a, b) {
    if (bnCmp(b, [0]) === 0) {
      throw new Error('ArithmeticException: / by zero');
    }
    if (bnCmp(a, b) < 0) return [[0], a.slice()];
    var rem = a.slice();
    var shift = bnBitLength(a) - bnBitLength(b);
    var quo = [];
    var shifted = b.slice();
    while (shift-- > 0) shifted = bigShl1(shifted);
    for (var i = bnBitLength(a) - bnBitLength(b); i >= 0; i--) {
      if (bnCmp(rem, shifted) >= 0) {
        rem = bnSub(rem, shifted);
        quo[Math.floor(i / 16)] = (quo[Math.floor(i / 16)] || 0)
            | (1 << (i % 16));
      }
      shifted = bigShr1(shifted);
    }
    if (quo.length === 0) quo.push(0);
    return [bnTrim(quo), bnTrim(rem)];
  }
  function bigShl1(a) {
    var r = [];
    var carry = 0;
    for (var i = 0; i < a.length; i++) {
      var v = ((a[i] << 1) | carry) & 0xffff;
      carry = (a[i] >>> 15) & 1;
      r.push(v);
    }
    if (carry > 0) r.push(carry);
    return bnTrim(r);
  }
  function bigShr1(a) {
    var r = [];
    for (var i = 0; i < a.length; i++) {
      var hi = i + 1 < a.length ? a[i + 1] : 0;
      r.push(((a[i] >>> 1) | ((hi & 1) << 15)) & 0xffff);
    }
    return bnTrim(r);
  }
  function bigToStringMag(a, radix) {
    if (bnCmp(a, [0]) === 0) return '0';
    var digits = '0123456789abcdefghijklmnopqrstuvwxyz';
    var out = [];
    var cur = a.slice();
    while (bnCmp(cur, [0]) !== 0) {
      var parts = bigDivRemMag(cur, [radix]);
      out.push(digits[parts[1][0] % radix]);
      cur = parts[0];
    }
    return out.reverse().join('');
  }
  function bigFromStringMag(s, radix) {
    var a = [0];
    var rad = [radix];
    for (var i = 0; i < s.length; i++) {
      var d = digitsOf(s.charAt(i), radix);
      if (d < 0) throw new Error('NumberFormatException: ' + s);
      a = bigAddMag(bigMulMag(a, rad), [d]);
    }
    return a;
  }
  function digitsOf(c, radix) {
    var digits = '0123456789abcdefghijklmnopqrstuvwxyz';
    var i = digits.indexOf(String(c).toLowerCase());
    return i >= 0 && i < radix ? i : -1;
  }

  var JavaBigInteger = jmark(function BigInteger(v, radix) {
    if (!(this instanceof JavaBigInteger)) {
      return new JavaBigInteger(v, radix);
    }
    this.__neg = false;
    this.__a = [0];
    if (v instanceof JavaBigInteger) {
      this.__neg = v.__neg;
      this.__a = v.__a.slice();
      return;
    }
    if (typeof v === 'number') {
      if (v < 0) { this.__neg = true; v = -v; }
      this.__a = bnFromBytes(bnToBytes([v & 0xffff, Math.floor(v / 65536) & 0xffff], 4));
      return;
    }
    if (v && typeof v.length === 'number' && typeof v !== 'string') {
      this.__a = bnFromBytes(juBytes(v));
      return;
    }
    var s = String(v == null ? '0' : v).trim();
    if (s.charAt(0) === '-') { this.__neg = true; s = s.substring(1); }
    else if (s.charAt(0) === '+') s = s.substring(1);
    var rad = radix == null ? 10 : (typeof radix === 'number' ? radix : parseInt(radix, 10) || 10);
    if (rad === 16 && s.substring(0, 2).toLowerCase() === '0x') s = s.substring(2);
    this.__a = bigFromStringMag(s, rad);
    if (bnCmp(this.__a, [0]) === 0) this.__neg = false;
  }, 'java.math.BigInteger');
  JavaBigInteger.prototype.__with = function (neg, mag) {
    var o = new JavaBigInteger(0);
    o.__a = mag;
    o.__neg = neg && bnCmp(mag, [0]) !== 0;
    return o;
  };
  JavaBigInteger.prototype.abs = function () {
    return this.__with(false, this.__a);
  };
  JavaBigInteger.prototype.negate = function () {
    return this.__with(!this.__neg, this.__a);
  };
  JavaBigInteger.prototype.add = function (v) {
    var b = new JavaBigInteger(v == null ? '0' : v);
    if (this.__neg === b.__neg) return this.__with(this.__neg, bigAddMag(this.__a, b.__a));
    var c = bnCmp(this.__a, b.__a);
    if (c === 0) return new JavaBigInteger(0);
    if (c > 0) return this.__with(this.__neg, bnSub(this.__a, b.__a));
    return this.__with(b.__neg, bnSub(b.__a, this.__a));
  };
  JavaBigInteger.prototype.subtract = function (v) {
    return this.add(new JavaBigInteger(v == null ? '0' : v).negate());
  };
  JavaBigInteger.prototype.multiply = function (v) {
    var b = new JavaBigInteger(v == null ? '0' : v);
    return this.__with(this.__neg !== b.__neg, bigMulMag(this.__a, b.__a));
  };
  JavaBigInteger.prototype.divide = function (v) {
    var b = new JavaBigInteger(v == null ? '0' : v);
    var q = bigDivRemMag(this.__a, b.__a)[0];
    return this.__with(this.__neg !== b.__neg && bnCmp(q, [0]) !== 0, q);
  };
  JavaBigInteger.prototype.remainder = function (v) {
    var b = new JavaBigInteger(v == null ? '0' : v);
    var r = bigDivRemMag(this.__a, b.__a)[1];
    return this.__with(this.__neg, r);
  };
  JavaBigInteger.prototype.mod = function (v) {
    var b = new JavaBigInteger(v == null ? '0' : v);
    if (b.__neg) throw new Error('ArithmeticException: modulus not positive');
    var r = bigDivRemMag(this.__a, b.__a)[1];
    if (this.__neg && bnCmp(r, [0]) !== 0) r = bnSub(b.__a, r);
    return this.__with(false, r);
  };
  JavaBigInteger.prototype.modPow = function (exp, m) {
    var e = new JavaBigInteger(exp == null ? '0' : exp);
    var mod = new JavaBigInteger(m == null ? '0' : m);
    if (mod.__neg) throw new Error('ArithmeticException: modulus not positive');
    if (e.__neg) throw new Error('ArithmeticException: negative exponent');
    // 通用平方-乘取模（Montgomery 形态要求奇模数；java.math.BigInteger
    // 对偶模数同样支持）。
    if (bnCmp(mod.__a, [1]) === 0) return this.__with(false, [0]);
    var out = new JavaBigInteger(1);
    var base = this.mod(mod);
    var expLimbs = e.__a.slice();
    var bits = bnBitLength(expLimbs);
    for (var i = 0; i < bits; i++) {
      if ((expLimbs[Math.floor(i / 16)] >>> (i % 16)) & 1) {
        out = out.multiply(base).mod(mod);
      }
      base = base.multiply(base).mod(mod);
    }
    return out;
  };
  JavaBigInteger.prototype.compareTo = function (v) {
    var b = new JavaBigInteger(v == null ? '0' : v);
    if (this.__neg !== b.__neg) return this.__neg ? -1 : 1;
    var c = bnCmp(this.__a, b.__a);
    return this.__neg ? -c : c;
  };
  JavaBigInteger.prototype.equals = function (v) {
    if (!(v instanceof JavaBigInteger)) return false;
    return v.__neg === this.__neg && bnCmp(this.__a, v.__a) === 0;
  };
  JavaBigInteger.prototype.intValue = function () {
    var v = this.__a[0] + this.__a[1] * 65536;
    return this.__neg ? -v : v;
  };
  JavaBigInteger.prototype.longValue = function () { return this.intValue(); };
  JavaBigInteger.prototype.toByteArray = function () {
    var bytes = bnToBytes(this.__a);
    if (this.__neg) {
      // 负数：简单按补码近似（书源场景基本无负数），最高位若为 0 补 0xff。
      for (var i = 0; i < bytes.length; i++) bytes[i] = (~bytes[i] + 1) & 0xff;
    }
    return bytes.map(signedByte);
  };
  JavaBigInteger.prototype.toString = function (radix) {
    var rad = radix == null ? 10 : (typeof radix === 'number' ? radix : parseInt(radix, 10) || 10);
    var s = bigToStringMag(this.__a, rad);
    return (this.__neg ? '-' : '') + s;
  };
  JavaBigInteger.prototype.toJSON = function () { return this.toString(); };

  // ── java.util.Date / java.text.SimpleDateFormat（时间戳格式化）──
  var JavaDate = jmark(function Date(v) {
    if (!(this instanceof JavaDate)) return new JavaDate(v);
    if (v == null) this.__t = Date.now();
    else if (typeof v === 'number') this.__t = Math.floor(v);
    else this.__t = Date.parse(String(v)) || Date.now();
  }, 'java.util.Date');
  JavaDate.prototype.getTime = function () { return this.__t; };
  JavaDate.prototype.setTime = function (t) { this.__t = Math.floor(Number(t) || 0); };
  JavaDate.prototype.before = function (o) {
    return this.__t < (o && o.__t != null ? o.__t : 0);
  };
  JavaDate.prototype.after = function (o) {
    return this.__t > (o && o.__t != null ? o.__t : 0);
  };
  JavaDate.prototype.toString = function () {
    return new Date(this.__t).toISOString()
        .replace('T', ' ').replace('Z', ' GMT');
  };

  // 仅支持数字字段组合（yyyy yy MM dd HH hh mm ss SSS），按 Java
  // SimpleDateFormat 的字母连续段解析；引号段按字面量。
  var JavaSimpleDateFormat = jmark(function SimpleDateFormat(pattern) {
    if (!(this instanceof JavaSimpleDateFormat)) {
      return new SimpleDateFormat(pattern);
    }
    this.__p = String(pattern == null ? '' : pattern);
  }, 'java.text.SimpleDateFormat');
  JavaSimpleDateFormat.prototype.format = function (v) {
    var t = v instanceof JavaDate ? v.__t
        : (typeof v === 'number' ? Math.floor(v) : Date.parse(String(v)) || Date.now());
    var d = new Date(t);
    var map = {
      yyyy: d.getFullYear(),
      yy: ('' + d.getFullYear()).substring(2),
      MM: pad2(d.getMonth() + 1),
      dd: pad2(d.getDate()),
      HH: pad2(d.getHours()),
      hh: pad2((d.getHours() % 12) === 0 ? 12 : d.getHours() % 12),
      mm: pad2(d.getMinutes()),
      ss: pad2(d.getSeconds()),
      SSS: ('00' + d.getMilliseconds()).slice(-3),
    };
    var out = '';
    var i = 0;
    var p = this.__p;
    while (i < p.length) {
      var c = p.charAt(i);
      if (c === "'") {
        var end = p.indexOf("'", i + 1);
        if (end < 0) { out += p.substring(i + 1); break; }
        out += p.substring(i + 1, end);
        i = end + 1;
        continue;
      }
      var run = '';
      while (i < p.length && p.charAt(i) === c) { run += c; i++; }
      if (map[run] !== undefined) {
        out += String(map[run]);
      } else if (run.length === 1 && 'yMdHhmsS'.indexOf(c) >= 0) {
        out += String(map[pad2KeyOf(c, run)]);
      } else {
        out += run;
      }
    }
    return out;
  };
  function pad2(n) { return (n < 10 ? '0' : '') + n; }
  function pad2KeyOf(c, run) {
    var names = { y: 'yyyy', M: 'MM', d: 'dd', H: 'HH', h: 'hh',
      m: 'mm', s: 'ss', S: 'SSS' };
    return names[c];
  }

  // ── javax.crypto.Mac（HMAC 实例，审计 R47）──
  var JavaMac = jmark(function Mac() {}, 'javax.crypto.Mac');
  JavaMac.getInstance = function (algo) {
    var a = String(algo == null ? '' : algo);
    var norm = a.toUpperCase().replace(/-/g, '');
    if (norm.indexOf('HMAC') !== 0) {
      throw new Error('NoSuchAlgorithmException: '
          + 'Cannot find any provider supporting ' + a);
    }
    var keyBytes = null;
    var mac = {
      init: function (keySpec) {
        var k = keySpec instanceof SecretKeySpec
            ? keySpec.__k : juBytes(keySpec);
        if (k == null) {
          throw new Error('InvalidKeyException: no key');
        }
        keyBytes = k.map(function (x) { return x & 0xff; });
        return null;
      },
      doFinal: function (data) {
        if (keyBytes == null) {
          throw new Error('InvalidKeyException: MAC not initialized');
        }
        var bytes = data == null ? [] : juBytes(data);
        var out = hmacBytes(norm, keyBytes, bytes);
        if (out == null) {
          throw new Error('NoSuchAlgorithmException: '
              + 'Cannot find any provider supporting ' + a);
        }
        return out.map(signedByte);
      },
      getAlgorithm: function () { return a; },
      reset: function () { return null; },
    };
    return mac;
  };

  // ── java.net.URLEncoder / URLDecoder ──
  var JavaURLEncoder = jmark(function URLEncoder() {}, 'java.net.URLEncoder');
  JavaURLEncoder.encode = function (s, charset) {
    var cs = String(charset == null ? 'UTF-8' : charset).toUpperCase();
    if (cs !== 'UTF-8' && cs !== 'UTF8') {
      throw new Error('UnsupportedEncodingException: ' + charset);
    }
    return encoderEncode(s);
  };
  var JavaURLDecoder = jmark(function URLDecoder() {}, 'java.net.URLDecoder');
  JavaURLDecoder.decode = function (s, charset) {
    var cs = String(charset == null ? 'UTF-8' : charset).toUpperCase();
    if (cs !== 'UTF-8' && cs !== 'UTF8') {
      throw new Error('UnsupportedEncodingException: ' + charset);
    }
    var src = String(s == null ? '' : s).replace(/\+/g, ' ');
    try {
      return decodeURIComponent(src);
    } catch (_) {
      // 非法 % 序列按字面量保留（与 Java URLDecoder 宽容路径一致）。
      return src.replace(/%([0-9a-fA-F]{2})/g, function (m, h) {
        try { return decodeURIComponent(m); } catch (_) { return m; }
      });
    }
  };

  // ── 包树 ──
  var P_java_util_zip = jpkg({ GZIPInputStream: GZIPInputStream });
  var P_java_lang = jpkg({
    String: JavaString,
    System: JavaSystem,
    Thread: JavaThread,
    Class: JavaClass,
  });
  var P_java_math = jpkg({ BigInteger: JavaBigInteger });
  var P_java_text = jpkg({ SimpleDateFormat: JavaSimpleDateFormat });
  var P_java_util = jpkg({
    Base64: JavaBase64,
    Arrays: JavaArrays,
    UUID: JavaUUID,
    Date: JavaDate,
    LinkedHashMap: JavaMap,
    HashMap: JavaMap,
    Map: JavaMap,
    ArrayList: JavaList,
    LinkedList: JavaList,
    List: JavaList,
    HashSet: JavaSet,
    LinkedHashSet: JavaSet,
    Set: JavaSet,
  }, { zip: P_java_util_zip });
  var P_java_io = jpkg({
    ByteArrayOutputStream: ByteArrayOutputStream,
    ByteArrayInputStream: ByteArrayInputStream,
  });
  var P_java_security_spec = jpkg({
    X509EncodedKeySpec: X509EncodedKeySpec,
    PKCS8EncodedKeySpec: PKCS8EncodedKeySpec,
  });
  var P_java_security = jpkg({
    KeyFactory: JavaKeyFactory,
    Signature: JavaSignature,
    MessageDigest: JavaMessageDigest,
  }, { spec: P_java_security_spec });
  var P_java_net = jpkg({
    URL: JavaNetURL,
    URLEncoder: JavaURLEncoder,
    URLDecoder: JavaURLDecoder,
  });
  var P_javax_crypto_spec = jpkg({
    SecretKeySpec: SecretKeySpec,
    IvParameterSpec: IvParameterSpec,
    GCMParameterSpec: GCMParameterSpec,
  });
  var P_javax_crypto = jpkg({ Cipher: Cipher, Mac: JavaMac },
      { spec: P_javax_crypto_spec });
  var P_android_os = jpkg({ Build: AndroidBuild });
  var P_android_text = jpkg({ TextUtils: AndroidTextUtils });
  var P_android_util = jpkg({ Base64: AndroidBase64 });
  var P_okhttp3 = jpkg({
    Request: OkHttpRequest,
    RequestBody: OkHttpRequestBody,
    MediaType: OkHttpMediaType,
    FormBody: OkHttpFormBody,
    MultipartBody: OkHttpMultipartBody,
    OkHttpClient: OkHttpClient,
    Response: OkHttpResponse,
    Call: OkHttpCall,
  });
  var P_hutool_util = jpkg({
    StrUtil: HutoolStrUtil,
    ZipUtil: HutoolZipUtil,
  });
  var P_hutool_codec = jpkg({ Base64: HutoolBase64 });
  var P_hutool_digest = jpkg({ DigestUtil: HutoolDigestUtil });
  var P_org_jsoup = jpkg({
    Jsoup: JsoupShim,
    Connection: JsoupConnection,
  });
  var P_legado_http = jpkg({ StrResponse: LegadoStrResponse });
  var P_org_json = jpkg({ JSONObject: JSONObject, JSONArray: JSONArray });
  var P_com_fastjson = jpkg({
    JSON: FastjsonJSON,
    JSONObject: JSONObject,
    JSONArray: JSONArray,
  });
  var P_com_gson = jpkg({
    Gson: Gson,
    GsonBuilder: GsonBuilder,
    JsonParser: GsonJsonParser,
  });

  var Packages = {
    java: {
      lang: P_java_lang,
      util: P_java_util,
      math: P_java_math,
      text: P_java_text,
      io: P_java_io,
      security: P_java_security,
      net: P_java_net,
    },
    javax: { crypto: P_javax_crypto },
    android: {
      os: P_android_os,
      text: P_android_text,
      util: P_android_util,
    },
    okhttp3: P_okhttp3,
    cn: {
      hutool: {
        core: { util: P_hutool_util, codec: P_hutool_codec },
        crypto: { digest: P_hutool_digest },
      },
    },
    com: {
      alibaba: { fastjson: P_com_fastjson },
      google: { gson: P_com_gson },
    },
    org: { jsoup: P_org_jsoup, json: P_org_json },
    io: {
      legado: { app: { help: { http: P_legado_http } } },
    },
  };

  function JavaImporter() {
    if (!(this instanceof JavaImporter)) {
      var obj = Object.create(JavaImporter.prototype);
      JavaImporter.apply(obj, arguments);
      return obj;
    }
    if (arguments.length > 0) this.importPackage.apply(this, arguments);
  }
  JavaImporter.prototype.importPackage = function () {
    for (var i = 0; i < arguments.length; i++) {
      jcopyInto(this, arguments[i]);
    }
    return this;
  };
  JavaImporter.prototype.importClass = function (cls) {
    if (cls && cls.__javaName) {
      this[cls.__javaName.split('.').pop()] = cls;
    }
    return this;
  };

  global.Packages = Packages;
  // Rhino 顶层包名（org/com 直接可见）：`org.json.JSONObject`、
  // `com.alibaba.fastjson.JSON` 等写法不经 Packages 也能解析。
  // `org.jsoup` 由书源上下文预置在 global.org 上，这里只导出待合并的引用。
  global.com = {
    alibaba: { fastjson: P_com_fastjson },
    google: { gson: P_com_gson },
  };
  global.__syOrgJson = P_org_json;
  global.JavaImporter = JavaImporter;
  // Rhino 顶层 importPackage/importClass（语料中基本用 JavaImporter，这里
  // 保留兼容；不覆盖已存在的同名全局，避免把 String 等 JS 内建顶掉）。
  global.importPackage = function () {
    for (var i = 0; i < arguments.length; i++) {
      var list = arguments[i] && arguments[i].__classes;
      if (!list) continue;
      for (var k in list) {
        if (global[k] === undefined) global[k] = list[k];
      }
    }
    return null;
  };
  global.importClass = function (cls) {
    if (cls && cls.__javaName) {
      var simple = cls.__javaName.split('.').pop();
      if (global[simple] === undefined) global[simple] = cls;
    }
    return null;
  };

  var java = {
    // 加密/编码
    md5Encode: function (s) { return bytesToHex(md5Bytes(utf8Encode(String(s == null ? '' : s)))); },
    md5Encode16: function (s) { var h = java.md5Encode(s); return h.length >= 24 ? h.substring(8, 24) : h; },
    // 摘要/HMAC（JsEncodeUtils.digestHex/HMacHex/HMacBase64；算法为 JCE 名：
    // MD5/SHA-1/SHA-256 等）。legado 走 MessageDigest.getInstance，未知算法
    // 抛 NoSuchAlgorithmException；这里同样显式报错，不再返回可被误用的空串。
    digestHex: function (data, algorithm) {
      var out = requireDigestBytes(algorithm, utf8Encode(String(data == null ? '' : data)));
      return bytesToHex(out);
    },
    digestBase64Str: function (data, algorithm) {
      var out = requireDigestBytes(algorithm, utf8Encode(String(data == null ? '' : data)));
      return b64FromBytes(out.map(function (b) { return b & 0xff; }));
    },
    HMacHex: function (data, algorithm, key) {
      var out = requireHmacBytes(algorithm,
          utf8Encode(String(key == null ? '' : key)),
          utf8Encode(String(data == null ? '' : data)));
      return bytesToHex(out);
    },
    HMacBase64: function (data, algorithm, key) {
      var out = requireHmacBytes(algorithm,
          utf8Encode(String(key == null ? '' : key)),
          utf8Encode(String(data == null ? '' : data)));
      return b64FromBytes(out.map(function (b) { return b & 0xff; }));
    },
    // JsExtensions.base64Encode 默认 flags=2（NO_WRAP）；显式传入时按
    // android.util.Base64 标志位处理（NO_PADDING/NO_WRAP/CRLF/URL_SAFE）。
    base64Encode: function (s, flags) {
      return b64EncodeFlags(utf8Encode(String(s == null ? '' : s)), flags);
    },
    // base64Decode(str[, charset|flags])：解码宽容（同 Hutool）；charset
    // 重载保留签名，非 UTF-8 按 UTF-8 处理；flags 不影响解码。
    base64Decode: function (s, charsetOrFlags) {
      return utf8Decode(bytesFromB64(s));
    },
    // 空白输入返回 null（legado base64DecodeToByteArray 口径）。
    base64DecodeToByteArray: function (s, flags) {
      if (s == null || String(s).trim() === '') return null;
      return bytesFromB64(s);
    },
    // legado JsExtensions.strToBytes/bytesToStr：默认 UTF-8，字节按 Java
    // byte[]（有符号）口径。charset 重载保留签名；沙箱无多字符集编解码，
    // 非 UTF-8 名称按 UTF-8 处理（与 StrResponse.charset / encodeURI 同口径）。
    strToBytes: function (s, charset) {
      return utf8Encode(String(s == null ? '' : s)).map(signedByte);
    },
    bytesToStr: function (bytes, charset) {
      return utf8Decode(juBytes(bytes));
    },
    hexEncodeToString: function (v) { return bytesToHex(anyToBytes(v)); },
    hexDecodeToString: function (s) { return utf8Decode(hexStrictBytes(s)); },
    hexDecodeToByteArray: function (s) { return hexStrictBytes(s); },
    // AES：encode 输出 base64；decode 系列接受 base64 或 hex，输出字符串/字节数组。
    // transformation 形如 "AES/CBC/PKCS5Padding"、"AES/ECB/NoPadding"；
    // 支持 ECB/CBC/CTR/CFB/OFB/GCM（CFB 缺省 128 位段）。
    aesEncode: function (str, key, transformation, iv) {
      var out = aesCall(true, str, key, transformation, iv);
      return out == null ? ''
          : b64FromBytes(out.map(function (b) { return b & 0xff; }));
    },
    aesDecode: function (str, key, transformation, iv) {
      var out = aesCall(false, str, key, transformation, iv);
      return out == null ? [] : out;
    },
    aesDecodeToString: function (str, key, transformation, iv) {
      var out = aesCall(false, str, key, transformation, iv);
      return out == null ? '' : utf8Decode(out);
    },
    aesBase64DecodeToString: function (str, key, transformation, iv) {
      var out = aesCall(false, str, key, transformation, iv);
      return out == null ? '' : utf8Decode(out);
    },
    // legado 旧版 AES 别名（JsEncodeUtils 系列）：encode 系输出 base64 字符串
    // 或字节数组，decode 系与 aesDecode 同口径（base64/hex 自适应）。
    aesEncodeToString: function (str, key, transformation, iv) {
      return java.aesEncode(str, key, transformation, iv);
    },
    aesEncodeToBase64String: function (str, key, transformation, iv) {
      return java.aesEncode(str, key, transformation, iv);
    },
    aesEncodeToByteArray: function (str, key, transformation, iv) {
      var out = aesCall(true, str, key, transformation, iv);
      return out == null ? [] : out;
    },
    aesEncodeToBase64ByteArray: function (str, key, transformation, iv) {
      return utf8Encode(java.aesEncode(str, key, transformation, iv))
          .map(signedByte);
    },
    aesDecodeToByteArray: function (str, key, transformation, iv) {
      var out = aesCall(false, str, key, transformation, iv);
      return out == null ? [] : out;
    },
    aesBase64DecodeToByteArray: function (str, key, transformation, iv) {
      var out = aesCall(false, str, key, transformation, iv);
      return out == null ? [] : out;
    },
    // key/iv 为 base64 编码的变体（aesDecodeArgsBase64Str 等）。
    aesDecodeArgsBase64Str: function (data, keyB64, mode, padding, ivB64) {
      return aesArgsBase64(false, data, keyB64, mode, padding, ivB64);
    },
    aesEncodeArgsBase64Str: function (data, keyB64, mode, padding, ivB64) {
      return aesArgsBase64(true, data, keyB64, mode, padding, ivB64);
    },
    // DES/3DES 旧 API（legado JsEncodeUtils，内部同 createSymmetricCrypto）。
    desEncodeToBase64String: function (data, key, transformation, iv) {
      return java.createSymmetricCrypto(transformation, key, iv)
          .encryptBase64(data);
    },
    // legado 此处为 `String(encrypt(data))`（Java 字节数组 toString，实际
    // 无可用语义）；按加密后 base64 返回，便于脚本继续处理。
    desEncodeToString: function (data, key, transformation, iv) {
      return java.createSymmetricCrypto(transformation, key, iv)
          .encryptBase64(data);
    },
    desDecodeToString: function (data, key, transformation, iv) {
      return java.createSymmetricCrypto(transformation, key, iv)
          .decryptStr(data);
    },
    desBase64DecodeToString: function (data, key, transformation, iv) {
      return java.createSymmetricCrypto(transformation, key, iv)
          .decryptStr(data);
    },
    tripleDESEncodeBase64Str: function (data, key, mode, padding, iv) {
      return java.createSymmetricCrypto(
          'DESede/' + mode + '/' + padding, key, iv).encryptBase64(data);
    },
    tripleDESDecodeStr: function (data, key, mode, padding, iv) {
      return java.createSymmetricCrypto(
          'DESede/' + mode + '/' + padding, key, iv).decryptStr(data);
    },
    tripleDESEncodeArgsBase64Str: function (data, keyB64, mode, padding, iv) {
      return java.createSymmetricCrypto(
          'DESede/' + mode + '/' + padding,
          bytesFromB64(String(keyB64 == null ? '' : keyB64))
              .map(function (b) { return b & 0xff; }),
          iv).encryptBase64(data);
    },
    tripleDESDecodeArgsBase64Str: function (data, keyB64, mode, padding, iv) {
      return java.createSymmetricCrypto(
          'DESede/' + mode + '/' + padding,
          bytesFromB64(String(keyB64 == null ? '' : keyB64))
              .map(function (b) { return b & 0xff; }),
          iv).decryptStr(data);
    },
    // legado SymmetricCrypto 对象形态（百度小说等用链式 decryptStr）。
    createSymmetricCrypto: makeSymmetricCrypto,
    // legado AsymmetricCrypto 对象形态（乐读小说用 setPublicKey + decryptStr）；
    // 运算经宿主排空协议（__asymDrain/__asymFill）完成，见 JsEngine。
    createAsymmetricCrypto: makeAsymmetricCrypto,
    // legado Sign 对象形态（java.createSign(algorithm)，MD5/SHA1/SHA256withRSA）。
    createSign: makeSign,
    // 字体反爬：解析 TTF（base64 / 字节数组 / http(s) URL），返回可查询
    // 字形轮廓的字体对象。
    queryTTF: function (data, useCache) {
      try {
        if (typeof data === 'string' && /^https?:\/\//i.test(data)) {
          var url = String(data);
          var cached = global.__ajaxBytesCache &&
              global.__ajaxBytesCache[url];
          if (cached == null) {
            syJavaOp('ajaxBytes', url, '');
            return null;
          }
          if (cached === '') return null;
          data = cached;
        }
        var bytes = ttfBytes(data);
        if (!bytes || bytes.length < 12) return null;
        var key = ttfHash(bytes);
        if (useCache !== false && __ttfCache[key]) return __ttfCache[key];
        var font = ttfParse(bytes);
        if (font && useCache !== false) __ttfCache[key] = font;
        return font;
      } catch (e) {
        return null;
      }
    },
    // 按字形轮廓把「错误字体渲染的文本」还原为「正确字体对应的字符」。
    // filter=true 时删除错误字体里不存在的字符（legado 同口径）。
    replaceFont: function (text, errFont, okFont, filter) {
      try {
        return ttfReplaceFont(text, errFont, okFont, !!filter);
      } catch (e) {
        return String(text == null ? '' : text);
      }
    },
    // 字符串/URL/HTML
    encodeURI: function (s, enc) { return encoderEncode(s); },
    htmlFormat: function (s) { return htmlFormat(s); },
    toNumChapter: function (s) { return toNumChapter(s); },
    t2s: function (s) { return typeof global.t2s === 'function' ? global.t2s(s) : s; },
    s2t: function (s) { return typeof global.s2t === 'function' ? global.s2t(s) : s; },
    // 时间
    timeFormat: function (t) { return timeFormat(t); },
    timeFormatUTC: function (t, f, sh) { return timeFormatUTC(t, f, sh); },
    // 设备/杂项
    randomUUID: function () { return randomUUID(); },
    androidId: function () { return ANDROID_ID; },
    // 日志/提示（宿主排空；log 返回原值以便链式）
    log: function (m) { pushLog(m); return m; },
    logType: function (m) { pushLog(m); return m; },
    toast: function (m) { pushToast(m, false); },
    longToast: function (m) { pushToast(m, true); },
    // 变量：get 读宿主种子+本轮 put 的快照；put 仅供宿主排空回写变量表
    get: function (k) {
      var v = global.__javaVars;
      return v && v[k] != null ? String(v[k]) : '';
    },
    put: function (k, v) {
      var key = String(k);
      // legado `putVariable(key, null)` = 删除该键：登记删除表，宿主排空后
      // 从变量表移除（旧实现把 null 写成空串，"置空即删除"的源读回空值仍
      // 算命中）。
      if (v == null) {
        if (!global.__javaDeleted || !global.__javaDeleted.length) {
          global.__javaDeleted = [];
        }
        global.__javaDeleted.push(key);
        if (global.__javaVars && typeof global.__javaVars === 'object') {
          delete global.__javaVars[key];
        }
        var chDel = global.chapter;
        if (chDel != null && chDel.variableMap &&
            typeof chDel.variableMap === 'object') {
          delete chDel.variableMap[key];
        }
        return null;
      }
      var s = String(v);
      // legado AnalyzeRule.put：有章节时先写章节 variableMap，随后
      // java.get 的 chapter 层优先命中新值；无章节由宿主排空写 ruleData。
      var ch = global.chapter;
      if (ch != null && ch.variableMap && typeof ch.variableMap === 'object') {
        ch.variableMap[key] = s;
      }
      if (!global.__javaVars || typeof global.__javaVars !== 'object') {
        global.__javaVars = {};
      }
      global.__javaVars[key] = s;
      return v;
    },
    // ── 规则求值桥（确定性重放，见 ruleCall 注释）──
    getString: function (rule, mContent, isUrl) {
      var u = typeof mContent === 'boolean' ? mContent : !!isUrl;
      var c = typeof mContent === 'boolean' ? null : mContent;
      return ruleCall('s', rule, c, u);
    },
    getStringList: function (rule, mContent, isUrl) {
      var u = typeof mContent === 'boolean' ? mContent : !!isUrl;
      var c = typeof mContent === 'boolean' ? null : mContent;
      return ruleCall('l', rule, c, u);
    },
    getElement: function (rule, mContent) {
      return ruleCall('g', rule, mContent, false);
    },
    getElements: function (rule) {
      return ruleCall('e', rule, null, false);
    },
    setContent: function (content, baseUrl) {
      global.__javaRootSig = (global.__javaRootSig || 0) + 1;
      var pend = global.__javaRulePending;
      if (!pend) pend = global.__javaRulePending = [];
      pend.push({
        op: 'set',
        c: ruleContentArg(content),
        b: baseUrl == null ? '' : String(baseUrl)
      });
      return java;
    },
    // ── 设备/环境别名与无操作族（沙箱无对应能力，保持可调用不抛错）──
    getWebViewUA: function () { return WEBVIEW_UA; },
    getUserAgent: function () { return WEBVIEW_UA; },
    webview: function (html, url, js) { return java.webView(html, url, js); },
    ajaxTestAll: function (urlList, timeout) { return java.ajaxAll(urlList); },
    sleep: function (ms) { return null; },
    toURL: function (url, baseUrl) {
      try { return makeJsUrl(url, baseUrl); } catch (e) { return null; }
    },
    refreshTocUrl: function () { return unsupported('refreshTocUrl'); },
    refreshContent: function () { return unsupported('refreshContent'); },
    refreshBookUrl: function () { return unsupported('refreshBookUrl'); },
    refreshExplore: function () { return unsupported('refreshExplore'); },
    initUrl: function () { return unsupported('initUrl'); },
    openVideoPlayer: function () { return unsupported('openVideoPlayer'); },
    // legado showBrowser(url, html, js?, options?)：在内置浏览器打开页面；
    // html 非空时按「注入内容 + url 作基址」加载（源用它渲染自带的段评/话题页）。
    // 第 3 个参数是页面内注入脚本（七猫系源写 `window.qmpcRun = run;` 这类
    // 桥接），这里把它并进 html 尾部一起注入；第 4 个参数是页面状态 JSON，
    // 当前浏览器没有状态通道，忽略。与 startBrowser 共用宿主动作通道。
    showBrowser: function (url, html, js, options) {
      var u = String(url == null ? '' : url);
      var h = String(html == null ? '' : html);
      var script = String(js == null ? '' : js);
      if (script) {
        var tag = '<scr' + 'ipt>' + script + '</scr' + 'ipt>';
        if (/<\/body>/i.test(h)) {
          h = h.replace(/<\/body>/i, tag + '</body>');
        } else {
          h = h + tag;
        }
      }
      if (!u && !h) return null;
      // 本 IIFE 在注入对象预置脚本之前执行，syOp 尚未定义（直调会
      // ReferenceError 让点击静默失败）；按同一排空协议用本段的 syJavaOp。
      syJavaOp('browserOpen', u, JSON.stringify(['', h]));
      return null;
    },
    // ── java.net 包（URL 值语义，不触网）──
    net: P_java_net,
  };

  // 固定 UA（legado getWebViewUA 读取系统 WebView 默认 UA；沙箱内用
  // Chrome 移动端 UA 常量近似，脚本多用于 UA 指纹拼接）。
  var WEBVIEW_UA = 'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
      + '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  // 无宿主动作可执行的 API：每次引擎对同名调用只记一次运行日志，便于排查
  // 「书源依赖刷新/播放器回调」类问题。
  var __unsupportedLogged = Object.create(null);
  function unsupported(name) {
    if (!__unsupportedLogged[name]) {
      __unsupportedLogged[name] = true;
      pushLog('[java.' + name + '] 当前运行时不支持该操作，已忽略');
    }
    return null;
  }

  // JsURL 等价物（toURL）：host/origin/pathname/searchParams。
  function makeJsUrl(url, baseUrl) {
    var s = String(url == null ? '' : url);
    if (baseUrl) {
      var b = String(baseUrl);
      if (!/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(s)) {
        var m = b.match(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\/[^\/]+/);
        var origin0 = m ? m[0] : b.replace(/\/$/, '');
        if (s.indexOf('/') === 0) s = origin0 + s;
        else s = origin0 + '/' + s;
      }
    }
    var mm = s.match(/^([a-zA-Z][a-zA-Z0-9+.-]*):\/\/([^\/?#]+)([^?#]*)(?:\?([^#]*))?/);
    if (!mm) return null;
    var proto = mm[1], hostPort = mm[2], path = mm[3] || '';
    var host = hostPort.split('@').pop().split(':')[0];
    var searchParams = Object.create(null);
    var q = mm[4] || '';
    if (q) {
      var parts = q.split('&');
      for (var i = 0; i < parts.length; i++) {
        var kv = parts[i].split('=');
        var k = decodeURIComponent(kv[0] || '');
        var v = kv.length > 1 ? decodeURIComponent(kv.slice(1).join('=')) : '';
        searchParams[k] = v;
      }
    }
    return {
      host: host,
      origin: proto + '://' + hostPort,
      pathname: path,
      searchParams: searchParams
    };
  }

  // ── 章节实体方法（legado BookChapter / RuleDataInterface） ──
  // legado 把 BookChapter 实体直接绑成脚本里的 `chapter`，脚本可调用
  // getVariable/putVariable/getBigVariable/putBigVariable/getAbsoluteURL/
  // getFileName。NexHub 绑定的是字段快照对象，这里按同名方法补齐语义；
  // 由 JsEngine 在注入 chapter 绑定后调用安装（每次绑定都是新对象）。
  // Kotlin String.trim() 的空白口径（JS trim 覆盖 Unicode 空白）。
  function syTrimUrl(s) {
    return String(s == null ? '' : s).trim();
  }

  // legado NetworkUtils.getAbsoluteURL(baseURL, relativePath)。
  function __syChapterAbsUrl(raw, base) {
    var rel = syTrimUrl(raw);
    var b0 = String(base == null ? '' : base);
    if (!b0) return rel;
    var b = b0.split(',')[0];
    if (!/^[a-zA-Z][a-zA-Z0-9+.\-]*:\/\//.test(b)) return rel;
    if (/^https?:\/\//i.test(rel)) return rel;
    if (/^data:.*?;base64,/.test(rel)) return rel;
    if (rel.indexOf('javascript') === 0) return '';
    // Java URL(base, rel)：带 scheme 的 spec 直接成绝对地址。
    if (/^[a-zA-Z][a-zA-Z0-9+.\-]*:/.test(rel)) return rel;
    if (rel.charAt(0) === '?') return b.replace(/[?#].*$/, '') + rel;
    if (rel.charAt(0) === '#') return b.replace(/#.*$/, '') + rel;
    return syAbsUrl(rel, b);
  }

  function __syInstallChapterHelpers() {
    var ch = global.chapter;
    if (!ch || typeof ch !== 'object') return;
    if (ch.__syChapterHelpers) return;
    try {
      Object.defineProperty(ch, '__syChapterHelpers', {
        value: true, enumerable: false, configurable: true
      });
    } catch (e) {
      ch.__syChapterHelpers = true;
    }
    if (!ch.variableMap || typeof ch.variableMap !== 'object') {
      ch.variableMap = {};
    }
    // 大变量表随快照注入（宿主 XiaoshuoBookChapter.bigVariableMap），本轮
    // 新增/删除经 `__syBigDeleted` 差异回传——大变量只在 JS 闭包里时，
    // 下一条规则、下一页正文和 formatJs 都读不到。
    if (!ch.__syBigVariables || typeof ch.__syBigVariables !== 'object') {
      ch.__syBigVariables = {};
    }
    if (!ch.__syBigDeleted || !Array.isArray(ch.__syBigDeleted)) {
      ch.__syBigDeleted = [];
    }
    // 普通变量删除集：drain 回传，宿主按集合 putVariable(k, null)。
    if (!ch.__syDeleted || !Array.isArray(ch.__syDeleted)) {
      ch.__syDeleted = [];
    }
    var big = ch.__syBigVariables;
    function has(o, k) { return Object.prototype.hasOwnProperty.call(o, k); }
    function delBig(k) {
      if (has(big, k)) {
        delete big[k];
        ch.__syBigDeleted.push(k);
      }
    }
    function markDeleted(k) {
      if (ch.__syDeleted.indexOf(k) < 0) ch.__syDeleted.push(k);
    }
    function unmarkDeleted(k) {
      var i = ch.__syDeleted.indexOf(k);
      if (i >= 0) ch.__syDeleted.splice(i, 1);
    }
    // BookChapter.putVariable：null 删键；>=10000 转 big；恒返回 true（覆写基类）。
    ch.putVariable = function (key, value) {
      var k = String(key == null ? '' : key);
      if (value == null) {
        delete ch.variableMap[k];
        delBig(k);
        markDeleted(k);
        return true;
      }
      var s = String(value);
      if (s.length < 10000) {
        delBig(k);
        unmarkDeleted(k);
        ch.variableMap[k] = s;
        return true;
      }
      delete ch.variableMap[k];
      unmarkDeleted(k);
      if (!has(big, k)) ch.__syBigDeleted.push(k);
      big[k] = s;
      return true;
    };
    // RuleDataInterface.getVariable：表 → big → ''。
    ch.getVariable = function (key) {
      var k = String(key == null ? '' : key);
      if (has(ch.variableMap, k)) return ch.variableMap[k];
      if (has(big, k)) return big[k];
      return '';
    };
    ch.putBigVariable = function (key, value) {
      var k = String(key == null ? '' : key);
      if (value == null) delBig(k);
      else big[k] = String(value);
    };
    ch.getBigVariable = function (key) {
      var k = String(key == null ? '' : key);
      return has(big, k) ? big[k] : null;
    };
    // BookChapter.getAbsoluteURL：`,{...}` 选项段不参与拼接，原样接回。
    ch.getAbsoluteURL = function () {
      var u = String(ch.url == null ? '' : ch.url);
      var b = String(ch.baseUrl == null ? '' : ch.baseUrl);
      var title = String(ch.title == null ? '' : ch.title);
      if (ch.isVolume && u.indexOf(title) === 0) return b;
      var m = /\s*,\s*(?=\{)/.exec(u);
      var before = m ? u.substring(0, m.index) : u;
      var abs = __syChapterAbsUrl(before, b);
      if (!m) return abs;
      return abs + ',' + u.substring(m.index + m[0].length);
    };
    // BookChapter.getFileName：`%05d-<md5前16>.<suffix>`，默认 nb。
    ch.getFileName = function (suffix) {
      var idx = Number(ch.index);
      if (!isFinite(idx)) idx = 0;
      var num = String(Math.trunc(idx));
      while (num.length < 5) num = '0' + num;
      var title = String(ch.title == null ? '' : ch.title);
      var md5 = java.md5Encode(title);
      var short = md5.length >= 24 ? md5.substring(8, 24) : md5;
      var sfx = (suffix === undefined || suffix === null)
        ? 'nb' : String(suffix);
      return num + '-' + short + '.' + sfx;
    };
  }

  global.__syInstallChapterHelpers = __syInstallChapterHelpers;
  global.__syChapterAbsUrl = __syChapterAbsUrl;

  global.java = java;
})(globalThis);
''';
