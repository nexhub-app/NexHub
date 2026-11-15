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
JSON.stringify({t:(globalThis.__javaToasts||[]).splice(0),l:(globalThis.__javaLogs||[]).splice(0),v:globalThis.__javaVars||{}})
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
        bookVars: {}, bookInfo: {}, cookies: {}, loginInfo: {}, loginHeader: {},
        cache: {} };
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
  function syOp(op, a, b) {
    var v = global.__javaVars;
    if (!v || typeof v !== 'object') {
      v = {};
      global.__javaVars = v;
    }
    __syopN++;
    v['__syop_' + __syopN] = JSON.stringify({ op: op, a: a == null ? '' : a, b: b == null ? '' : b });
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
  };

  var source = {
    getKey: function () { return syCtx().sourceKey || syCtx().sourceId; },
    getVariable: function (k) {
      var c = syCtx();
      if (k == null || k === '') return c.sourceVars['__variable'] || '';
      return c.sourceVars[String(k)] || '';
    },
    putVariable: function (k, v) {
      if (k == null) return v;
      syCtx().sourceVars[String(k)] = String(v == null ? '' : v);
      syOp('sourceVar', k, v);
      return v;
    },
    setVariable: function (v) {
      return source.putVariable('__variable', v);
    },
    getLoginInfoMap: function () { return syCtx().loginInfo; },
    putLoginInfo: function (m) {
      syOp('loginInfo', JSON.stringify(m || {}), '');
      return null;
    },
    removeLoginInfo: function (k) {
      syOp('loginInfoDel', String(k), '');
      return null;
    },
    getLoginHeaderMap: function () { return syCtx().loginHeader; },
    getLoginHeader: function () {
      var parts = [];
      for (var k in syCtx().loginHeader) {
        parts.push(k + ': ' + syCtx().loginHeader[k]);
      }
      return parts.join('\n');
    },
    putLoginHeader: function (m) {
      syOp('loginHeader', JSON.stringify(m || {}), '');
      return null;
    },
    removeLoginHeader: function (k) {
      syOp('loginHeaderDel', String(k), '');
      return null;
    },
    refreshExplore: function () {
      syOp('refreshKinds', '', '');
      return true;
    },
    refreshJSLib: function () { return true; },
    refreshBookUrl: function () { return true; },
  };

  var book = {
    getVariable: function (k) { return syCtx().bookVars[String(k)] || ''; },
    putVariable: function (k, v) {
      syCtx().bookVars[String(k)] = String(v == null ? '' : v);
      syOp('bookVar', k, v);
      return v;
    },
    setVariable: function (v) { return book.putVariable('__variable', v); },
  };
  ['name', 'author', 'bookUrl', 'intro', 'kind', 'coverUrl', 'lastChapter']
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

  var cache = {
    put: function (k, v, saveTime) {
      syCtx().cache[String(k)] = String(v == null ? '' : v);
      syOp('cachePut', k, v);
      return null;
    },
    get: function (k) {
      var v = syCtx().cache[String(k)];
      return v == null ? '' : v;
    },
    delete: function (k) {
      delete syCtx().cache[String(k)];
      syOp('cacheDel', k, '');
      return null;
    },
    putMemory: function (k, v) { return cache.put(k, v); },
    getMemory: function (k) { return cache.get(k); },
    deleteMemory: function (k) { return cache.delete(k); },
    putFile: function (k, v) { return cache.put(k, v); },
    getFile: function (k) { return cache.get(k); },
  };

  // legado `source.key` 属性 = 书源 URL（脚本大量使用，只读）。
  Object.defineProperty(source, 'key', {
    get: function () { return syCtx().sourceKey || syCtx().sourceId; },
  });
  // legado `source.<field>` 只读属性（脚本直接读源配置：书源备注里的共享
  // 签名代码、登录脚本源码、请求头等）。
  Object.defineProperty(source, 'bookSourceUrl', {
    get: function () { return syCtx().sourceKey || syCtx().sourceId; },
  });
  ['bookSourceName', 'bookSourceGroup', 'bookSourceComment', 'header',
   'loginUrl', 'jsLib'].forEach(function (f) {
    Object.defineProperty(source, f, {
      get: function () {
        var m = syCtx().sourceMeta || {};
        return m[f] == null ? '' : String(m[f]);
      },
    });
  });
  ['bookSourceType', 'customOrder', 'lastUpdateTime', 'weight']
      .forEach(function (f) {
    Object.defineProperty(source, f, {
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
  if (global.java) {
    global.java.__ajaxReq = function (url) {
      var key = String(url == null ? '' : url);
      var c = global.__ajaxCache;
      if (c && c[key] != null) {
        return c[key];
      }
      syOp('ajax', key, '');
      global.__ajaxN = (global.__ajaxN || 0) + 1;
      return '__AJAX_' + global.__ajaxN + '__';
    };
    global.java.ajax = function (url, callTimeout) {
      return global.java.__ajaxReq(url);
    };
    global.java.ajaxAll = function (urlList, skipRateLimit) {
      var arr = urlList;
      if (typeof urlList === 'string') arr = [urlList];
      var mk = function (b) {
        return { body: function () { return b; },
          code: function () { return b ? 200 : 0; },
          headers: function () { return {}; } };
      };
      var out = [];
      for (var i = 0; arr && i < arr.length; i++) {
        out.push(mk(global.java.__ajaxReq(arr[i])));
      }
      return out;
    };
    global.java.connect = function (urlStr, header, callTimeout) {
      var body = global.java.__ajaxReq(urlStr);
      return { body: function () { return body; },
        code: function () { return body ? 200 : 0; },
        headers: function () { return {}; },
        bodyBytes: function () { return String(body || '').split('').map(function (c) { return c.charCodeAt(0) & 0xff; }) } };
    };
    // get 分派（legado 两个重载）：
    // - 2 参及以上 → HTTP GET（JsExtensions.get(url, headers)）；
    // - 1 参 → **变量优先**，取不到且形如 URL 才发请求。
    // 变量优先很关键：`java.get('bookUrl')` 的值本身就是 URL，按「看起来
    // 像 URL 就发请求」会把它误当接口（旧逻辑即如此）。
    global.java.get = function (a, b, c) {
      if (arguments.length >= 2) {
        return global.java.connect(a);
      }
      var s = String(a == null ? '' : a);
      var v = global.__javaVars;
      if (v && v[s] != null) return String(v[s]);
      if (/^https?:\/\//i.test(s)) return global.java.connect(s);
      return '';
    };
    // POST 记录组合键 url||POST||body（宿主 settle 拆分后组装选项串）。
    global.java.post = function (urlStr, bodyStr, headers, timeout) {
      return global.java.connect(urlStr + (bodyStr ? '||POST||' + bodyStr : ''));
    };
    global.java.head = function (urlStr, headers, timeout) {
      return global.java.connect(urlStr);
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
                var finalUrl = req._url;
                if (req._url.indexOf(',{') < 0 && Object.keys(opts).length > 0) {
                  finalUrl = req._url + ',' + JSON.stringify(opts);
                }
                var key = isPost && form
                    ? finalUrl + '||POST||' + form
                    : finalUrl;
                var bodyText = global.java.__ajaxReq(key);
                var code = bodyText ? 200 : 0;
                return {
                  body: function () { return bodyText; },
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
                  statusMessage: function () { return code === 200 ? 'OK' : ''; },
                  headers: function () { return {}; },
                  contentType: function () { return ''; },
                  charset: function () { return 'UTF-8'; },
                };
              },
            };
            return req;
          },
        },
      },
    };
    // java.webView(html, url, js)：无头 WebView 加载页面 / 注入 html、执行 js
    // 后返回整页 HTML。同步沙箱内不能真开 WebView，故与 ajax 同款重放：
    // 首轮记录 op 返回占位符，宿主 settle 抓取后写入 __webviewCache，重放命中。
    global.java.webView = function (html, url, js) {
      var h = html == null ? '' : String(html);
      var u = url == null ? '' : String(url);
      var j = js == null ? '' : String(js);
      if (!h && !u) return '';
      // 键用内容哈希：html/js 可能很长，不能直接当键存放/传输。
      var key = 'wv:' + syHash(h + '\u0001' + u + '\u0001' + j) + ':' +
          (h.length + u.length + j.length);
      var c = global.__webviewCache;
      if (c && c[key] != null) return c[key];
      syOp('webview', key, JSON.stringify([h, u, j]));
      global.__wvN = (global.__wvN || 0) + 1;
      return '__WEBVIEW_' + global.__wvN + '__';
    };
    // cacheFile(url) + readTxtFile(path)：脚本注入的常用组合
    // （`eval(java.cacheFile('https://x/sign.js'))`）。
    // 内容走 __ajaxReq 的确定性重放；按「虚拟路径」存取——真实文件族
    // （readFile/unzipFile）未实现，这里不给磁盘路径，避免误导调用方。
    global.__cacheFiles = global.__cacheFiles || Object.create(null);
    global.java.cacheFile = function (url, saveTime) {
      var u = String(url == null ? '' : url);
      if (!u) return '';
      // 先把 url 喂给 __ajaxReq：命中缓存返回真内容，未命中记录请求返回占位。
      var content = global.java.__ajaxReq(u);
      var path = 'shuyuan_cache:' + syHash(u) + ':' + u.length;
      global.__cacheFiles[path] = content;
      return path;
    };
    global.java.readTxtFile = function (path, charsetName) {
      var p = String(path == null ? '' : path);
      var files = global.__cacheFiles;
      if (files && files[p] != null) return files[p];
      // 传入的是 URL 而非路径时按内容抓取处理（legado 同样接受 URL）。
      if (/^https?:\/\//i.test(p)) {
        return global.java.readTxtFile(global.java.cacheFile(p));
      }
      return '';
    };
    // ── UI 操作族（发现页选项 action / 登录脚本） ──
    // legado 脚本可在 action 里直接打开浏览器、刷新选项栏、复制文本；
    // 同步沙箱内不能真开界面，统一记 op 由宿主排空后执行。
    global.java.startBrowser = function (url, title, html) {
      var u = String(url == null ? '' : url);
      if (u) syOp('browserOpen', u, title == null ? '' : String(title));
      return null;
    };
    global.java.startBrowserAwait = function (url, title) {
      global.java.startBrowser(url, title);
      // legado 返回响应对象；同步沙箱无真实响应，给空壳避免脚本 TypeError。
      return { body: function () { return ''; },
        code: function () { return 0; },
        headers: function () { return {}; } };
    };
    global.java.openUrl = function (url, mimeType) {
      global.java.startBrowser(url, '');
      return true;
    };
    global.java.refreshExplore = function () {
      syOp('refreshKinds', '', '');
      return true;
    };
    global.java.copyText = function (text) {
      var t = String(text == null ? '' : text);
      syOp('copyText', t, '');
      return t;
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
    var clean = String(s == null ? '' : s).replace(/[^A-Za-z0-9+/]/g, '');
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

  // legado 语义：UTC 时间 + sh（时区偏移秒）后按 format 取 UTC 分量。
  function timeFormatUTC(t, format, sh) {
    var d = new Date(Number(t) + (Number(sh) || 0) * 1000);
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

  // ── 章节号解析（阿拉伯优先，中文数字兜底，含两/拾佰仟萬） ──
  var CN_NUM = { '零': 0, '〇': 0, '一': 1, '壹': 1, '二': 2, '两': 2, '貳': 2, '贰': 2,
    '三': 3, '叁': 3, '四': 4, '肆': 4, '五': 5, '伍': 5, '六': 6, '陆': 6,
    '七': 7, '柒': 7, '八': 8, '捌': 8, '九': 9, '玖': 9 };
  var CN_UNIT = { '十': 10, '拾': 10, '百': 100, '佰': 100, '千': 1000, '仟': 1000 };

  function cnToArabic(s) {
    var total = 0, section = 0, digit = 0;
    for (var i = 0; i < s.length; i++) {
      var ch = s.charAt(i);
      if (CN_NUM[ch] !== undefined) {
        digit = CN_NUM[ch];
      } else if (CN_UNIT[ch] !== undefined) {
        section += (digit === 0 ? 1 : digit) * CN_UNIT[ch];
        digit = 0;
      } else if (ch === '万' || ch === '萬') {
        section = (section + digit) * 10000;
        total += section;
        section = 0;
        digit = 0;
      } else {
        return null;
      }
    }
    return total + section + digit;
  }

  function toNumChapter(v) {
    var str = String(v == null ? '' : v);
    var m = str.match(/\d+(\.\d+)?/);
    if (m) {
      var n = parseFloat(m[0]);
      if (!isNaN(n)) return n;
    }
    var m2 = str.match(/[零〇一二三四五六七八九十百千万兩两壹贰叁肆伍陆柒捌玖拾佰仟萬]+/);
    if (m2) {
      var v2 = cnToArabic(m2[0]);
      if (v2 !== null && !isNaN(v2)) return v2;
    }
    return -1;
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
    global.__javaToasts.push({ msg: String(msg == null ? '' : msg), long: !!long });
  }
  function pushLog(msg) {
    if (!global.__javaLogs) global.__javaLogs = [];
    global.__javaLogs.push(String(msg == null ? '' : msg));
  }

  // ── 元素包装（java.getElements / getElement 的返回值） ──
  // 宿主按规则把节点序列化成 {t:text, h:html, ot:ownText, a:attrs, j:json}
  // 由本函数包装成 jsoup 风格的轻量对象：脚本里常见的
  // `list.size() / list.get(i) / el.text() / el.html() / el.attr('href')`
  // 都能工作；属性同时挂成直读字段（el.href）。`.select()` 需要同步回调
  // 宿主按选择器再查，沙箱内做不到，故不提供（调用会抛错，走脚本兜底）。
  function __wrapEl(o) {
    var el = {
      text: function () { return o.t || ''; },
      html: function () { return o.h || ''; },
      ownText: function () { return o.ot || ''; },
      attr: function (k) { return (o.a && o.a[k]) || ''; },
      toString: function () { return o.t || ''; },
      json: o.j
    };
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

  function __javaElements(arr) {
    var list = [];
    var src = arr || [];
    for (var i = 0; i < src.length; i++) list.push(__wrapEl(src[i]));
    list.size = function () { return list.length; };
    list.get = function (i) { return list[i]; };
    list.first = function () { return list[0]; };
    list.last = function () { return list[list.length - 1]; };
    list.text = function () {
      var out = [];
      for (var i = 0; i < list.length; i++) out.push(list[i].text());
      return out.join('\n');
    };
    return list;
  }

  global.__javaElements = __javaElements;

  // ── AES（ECB / CBC；PKCS5/7 或 NoPadding） ──
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

  /// AES 主流程：返回字节数组（有符号口径），参数非法返回 null。
  function aesRun(encrypt, data, key, mode, pad, iv) {
    var ks = aesKeyExpand(key);
    if (!ks) return null;
    var out = [];
    var i;
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

  /// transformation 解析：不支持的模式（CTR/GCM/CFB/OFB）返回 null。
  function aesParseTf(transformation, hasIv) {
    var t = String(transformation || '').toUpperCase();
    if (t.indexOf('/CTR') >= 0 || t.indexOf('/GCM') >= 0 ||
        t.indexOf('/CFB') >= 0 || t.indexOf('/OFB') >= 0) {
      return null;
    }
    var mode = t.indexOf('/ECB') >= 0 ? 'ECB'
        : (t.indexOf('/CBC') >= 0 ? 'CBC' : (hasIv ? 'CBC' : 'ECB'));
    var pad = t.indexOf('NOPADDING') < 0;
    return { mode: mode, pad: pad };
  }

  function aesDecodeInput(str) {
    var s = String(str == null ? '' : str).trim();
    // 十六进制形态（长度是 32 的整数倍 = 16 字节的整数倍）按 hex 解析，
    // 其余按 base64。条件收紧到 32 的倍数，避免把恰好全为 hex 字符的
    // base64 串误判（如 32 位纯十六进制的密文很常见，但 base64 很少）。
    var isHex = s.length > 0 && s.length % 32 === 0 && /^[0-9a-fA-F]+$/.test(s);
    var bytes = isHex ? hexToBytes(s) : bytesFromB64(s);
    var norm = bytes.map(function (b) { return b & 0xff; });
    if (norm.length % 16 !== 0 && isHex) {
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
    if (tf.mode === 'CBC' && (ivBytes == null || ivBytes.length !== 16)) {
      return null;
    }
    var data = encrypt
        ? utf8Encode(String(str == null ? '' : str))
        : aesDecodeInput(str);
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
    var m = String(mode == null ? '' : mode).toUpperCase() === 'ECB'
        ? 'ECB' : 'CBC';
    var pad = String(padding == null ? '' : padding).toUpperCase()
        .indexOf('NOPADDING') < 0;
    if (m === 'CBC' && iv.length !== 16) return '';
    var input = encrypt ? utf8Encode(String(data == null ? '' : data))
        : aesDecodeInput(data);
    var out = aesRun(encrypt, input, key, m, pad, m === 'CBC' ? iv : null);
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

  // ── TTF（字体反爬：queryTTF / replaceFont） ──
  // 纯 JS 解析 sfnt 表（head/maxp/cmap[format 4|12]/loca/glyf），按「字形轮廓
  // 字节」做字符映射——与 legado QueryTTF 的 glyf 比较口径一致。
  // 输入仅支持 base64 / 字节数组；URL 需要二进制抓取（重放协议），暂不支持
  // （返回 null → replaceFont 原样返回，不产出乱码）。
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

  // ── SymmetricCrypto（legado java.createSymmetricCrypto） ──
  // transformation 形如 "AES/CBC/PKCS5Padding"；key/iv/data 支持字符串或
  // 字节数组（legado ByteArray 有符号口径）。不支持的算法/模式（DES、
  // AES/CTR 等）返回空结果，避免给出错误明文。
  function makeSymmetricCrypto(transformation, key, iv) {
    var empty = {
      decrypt: function () { return []; },
      decryptStr: function () { return ''; },
      encrypt: function () { return []; },
      encryptBase64: function () { return ''; },
      encryptHex: function () { return ''; },
    };
    var keyBytes = anyToBytes(key);
    var ivBytes = (iv == null || iv === '') ? null : anyToBytes(iv);
    var tf = aesParseTf(transformation, ivBytes != null);
    if (!tf) return empty;
    if (tf.mode === 'CBC' && (ivBytes == null || ivBytes.length !== 16)) {
      return empty;
    }
    function run(encrypt, bytes) {
      return aesRun(encrypt, bytes, keyBytes, tf.mode, tf.pad, ivBytes);
    }
    return {
      decrypt: function (data) {
        var bytes = (data && typeof data === 'object' &&
            typeof data.length === 'number')
            ? anyToBytes(data)
            : aesDecodeInput(data);
        var out = run(false, bytes);
        return out == null ? [] : out;
      },
      decryptStr: function (data) {
        var bytes = (data && typeof data === 'object' &&
            typeof data.length === 'number')
            ? anyToBytes(data)
            : aesDecodeInput(data);
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

  var java = {
    // 加密/编码
    md5Encode: function (s) { return bytesToHex(md5Bytes(utf8Encode(String(s == null ? '' : s)))); },
    md5Encode16: function (s) { var h = java.md5Encode(s); return h.length >= 24 ? h.substring(8, 24) : h; },
    base64Encode: function (s) { return b64FromBytes(utf8Encode(String(s == null ? '' : s))); },
    base64Decode: function (s) { return utf8Decode(bytesFromB64(s)); },
    base64DecodeToByteArray: function (s) { return bytesFromB64(s); },
    hexEncodeToString: function (v) { return bytesToHex(anyToBytes(v)); },
    hexDecodeToString: function (s) { return utf8Decode(hexToBytes(s)); },
    hexDecodeToByteArray: function (s) { return hexToBytes(s); },
    // AES：encode 输出 base64；decode 系列接受 base64 或 hex，输出字符串/字节数组。
    // transformation 形如 "AES/CBC/PKCS5Padding"、"AES/ECB/NoPadding"；
    // CTR/GCM/CFB/OFB 未实现（返回空，避免给出错误结果）。
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
    // legado SymmetricCrypto 对象形态（百度小说等用链式 decryptStr）。
    createSymmetricCrypto: makeSymmetricCrypto,
    // 字体反爬：解析 TTF（base64 / 字节数组），返回可查询字形轮廓的字体对象。
    queryTTF: function (data, useCache) {
      try {
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
      if (!global.__javaVars || typeof global.__javaVars !== 'object') {
        global.__javaVars = {};
      }
      global.__javaVars[String(k)] = v == null ? '' : String(v);
      return v;
    },
  };

  global.java = java;
})(globalThis);
''';
