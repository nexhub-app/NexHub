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
/// - 网络族（ajax/connect/get/post）、WebView 族、文件族等 P1 再接入，
///   当前未定义 → 调用抛 TypeError → 既有 `[书源JS]` 日志兜底，行为安全。
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
/// 与变量快照（避免每次规则求值残留）。须用 globalThis——本表达式在
/// 顶层求值，IIFE 内的 `global` 参数不可见。
const String javaDrainExpr = r'''
JSON.stringify({t:(globalThis.__javaToasts||[]).splice(0),l:(globalThis.__javaLogs||[]).splice(0),v:globalThis.__javaVars||{}})
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

  function timeFormat(t) {
    var d = new Date(Number(t));
    if (isNaN(d.getTime())) return t == null ? '' : String(t);
    return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()) +
        ' ' + pad2(d.getHours()) + ':' + pad2(d.getMinutes()) + ':' + pad2(d.getSeconds());
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
