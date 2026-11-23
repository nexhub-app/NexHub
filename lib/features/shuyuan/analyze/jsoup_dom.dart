/// org.jsoup.Jsoup.parse 纯 JS 互操作层：容错 HTML 解析 + CSS 选择器子集。
///
/// Rhino 源码可直接调用 jsoup：`Jsoup.parse(html).select(selector)` 后接
/// Element/Elements 的 text/attr/html/first/get/size/forEach 等。QuickJS
/// 无 Java 运行时，这里用纯 ES 实现同形对象：
/// - 容错 HTML 解析（未闭合标签、常见隐式闭合、script/style 原文）；
/// - CSS 选择器：tag/#id/.class/[attr 及运算符]/后代/`>`/`+`/`~`/`,`，
///   以及 :first-child/:nth-child()/:contains()/:not()/:has()/:eq() 等常用伪类；
/// - Element/Elements 常用方法，语义按 jsoup 习惯（text 空白折叠、
///   attr 缺省空串、Elements 支持 get/size/first/last/eachText）。
///
/// 注入顺序在 org/jsoup 连接链之后（[javaExtensionsJsPrelude] →
/// [sourceContextJsPrelude] → 本预置脚本），因此这里只补 parse 能力，
/// 不重复定义 connect。
library;

const String jsoupDomJsPrelude = r'''
(function (global) {
  "use strict";

  if (!global.org) global.org = {};
  if (!global.org.jsoup) global.org.jsoup = {};
  if (!global.org.jsoup.Jsoup) global.org.jsoup.Jsoup = {};
  var Jsoup = global.org.jsoup.Jsoup;
  if (typeof Jsoup.parse === "function") return;

  // ── 标签分类 ──
  var VOID = {area:1, base:1, br:1, col:1, embed:1, hr:1, img:1, input:1,
    link:1, meta:1, param:1, source:1, track:1, wbr:1};
  var BLOCK = {address:1, article:1, aside:1, blockquote:1, div:1, dl:1,
    dd:1, dt:1, fieldset:1, figcaption:1, figure:1, footer:1, form:1, h1:1,
    h2:1, h3:1, h4:1, h5:1, h6:1, header:1, hr:1, li:1, main:1, nav:1,
    ol:1, p:1, pre:1, section:1, table:1, tbody:1, td:1, tfoot:1, th:1,
    thead:1, tr:1, ul:1};
  var CLOSES = {
    li: {li:1}, td: {td:1, th:1}, th: {td:1, th:1}, tr: {tr:1},
    option: {option:1}, dt: {dt:1, dd:1}, dd: {dt:1, dd:1},
    thead: {tbody:1, tfoot:1}, tbody: {tbody:1, tfoot:1},
    tfoot: {tbody:1}, select: {option:1}
  };

  var ENT = {amp:"&", lt:"<", gt:">", quot:"\"", apos:"'", nbsp:"\u00a0",
    copy:"\u00a9", reg:"\u00ae", hellip:"\u2026", mdash:"\u2014",
    ndash:"\u2013", middot:"\u00b7", ldquo:"\u201c", rdquo:"\u201d",
    lsquo:"\u2018", rsquo:"\u2019"};

  function unescapeHtml(s) {
    return String(s).replace(/&(#x?[0-9a-fA-F]+|[a-zA-Z]+);/g,
      function (m, e) {
        if (e.charAt(0) === "#") {
          var code = (e.charAt(1) === "x" || e.charAt(1) === "X")
            ? parseInt(e.substring(2), 16) : parseInt(e.substring(1), 10);
          try { return String.fromCodePoint(code); } catch (_) { return m; }
        }
        var v = ENT[e.toLowerCase()];
        return v != null ? v : m;
      });
  }

  function escapeText(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  function escapeAttr(s) {
    return String(s).replace(/&/g, "&amp;").replace(/"/g, "&quot;")
      .replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

  function normText(s) {
    return String(s).replace(/\u00a0/g, " ").replace(/\s+/g, " ").trim();
  }

  // ── 节点 ──
  var orderSeq = 0;

  function SyNode(kind, tag, attrs, parent) {
    this.__kind = kind;
    this.__tag = tag || "";
    this.__attrs = attrs || {};
    this.__children = [];
    this.__parent = parent || null;
    this.__order = 0;
  }

  function textNode(text, data) {
    return {__kind: "text", __text: String(text), __data: !!data,
      __parent: null};
  }

  function parentEl(node) {
    var p = node.__parent;
    return p && p.__kind === "el" ? p : null;
  }

  function prevEl(node) {
    var p = node.__parent;
    if (!p) return null;
    var idx = p.__children.indexOf(node);
    for (var i = idx - 1; i >= 0; i--) {
      if (p.__children[i].__kind === "el") return p.__children[i];
    }
    return null;
  }

  function nextEl(node) {
    var p = node.__parent;
    if (!p) return null;
    var idx = p.__children.indexOf(node);
    for (var i = idx + 1; i < p.__children.length; i++) {
      if (p.__children[i].__kind === "el") return p.__children[i];
    }
    return null;
  }

  function hasVisibleText(root) {
    var stack = [root];
    while (stack.length) {
      var n = stack.pop();
      if (n.__kind === "text") {
        if (!n.__data && /\S/.test(n.__text)) return true;
        continue;
      }
      for (var i = 0; i < n.__children.length; i++) stack.push(n.__children[i]);
    }
    return false;
  }

  function dataOf(root) {
    var out = [];
    (function walk(n) {
      if (n.__kind === "text") {
        if (n.__data) out.push(n.__text);
        return;
      }
      for (var i = 0; i < n.__children.length; i++) walk(n.__children[i]);
    })(root);
    return out.join("");
  }

  function allDesc(root) {
    var out = [];
    var stack = [root];
    while (stack.length) {
      var n = stack.pop();
      if (n.__kind !== "el" && n.__kind !== "doc") continue;
      for (var i = n.__children.length - 1; i >= 0; i--) {
        var c = n.__children[i];
        if (c.__kind === "el") {
          out.push(c);
          stack.push(c);
        }
      }
    }
    out.sort(function (a, b) { return a.__order - b.__order; });
    return out;
  }

  function docOf(node) {
    var n = node;
    while (n && n.__kind !== "doc") n = n.__parent;
    return n || node;
  }

  // ── HTML 解析（容错） ──
  function findTagEnd(s, from) {
    var quote = 0;
    for (var i = from; i < s.length; i++) {
      var c = s.charAt(i);
      if (quote) {
        if (c === quote) quote = 0;
        continue;
      }
      if (c === "\"" || c === "'") { quote = c; continue; }
      if (c === ">") return i;
    }
    return -1;
  }

  function parseAttrs(rest, attrs) {
    var re = /([^\s=\/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g;
    var m;
    while ((m = re.exec(rest))) {
      var name = String(m[1]).toLowerCase();
      if (!name) continue;
      var val = m[2] != null ? m[2] : (m[3] != null ? m[3] :
        (m[4] != null ? m[4] : ""));
      attrs[name] = unescapeHtml(val);
    }
  }

  function parseHtml(html) {
    var src = String(html == null ? "" : html);
    var doc = new SyNode("doc", "#document", {});
    var stack = [doc];

    function top() { return stack[stack.length - 1]; }

    function addText(parent, text, data) {
      if (!text) return;
      var node = textNode(data ? text : unescapeHtml(text), data);
      node.__parent = parent;
      parent.__children.push(node);
    }

    function closeForStart(tag) {
      while (stack.length > 1) {
        var t = top();
        if (t.__tag === "p" && BLOCK[tag]) { stack.pop(); continue; }
        var set = CLOSES[tag];
        if (set && set[t.__tag]) { stack.pop(); continue; }
        break;
      }
    }

    function closeTag(name) {
      for (var i = stack.length - 1; i > 0; i--) {
        if (stack[i].__tag === name) {
          stack.length = i;
          return;
        }
      }
    }

    var i = 0;
    var n = src.length;
    while (i < n) {
      var lt = src.indexOf("<", i);
      if (lt < 0) {
        addText(top(), src.substring(i), false);
        break;
      }
      if (lt > i) addText(top(), src.substring(i, lt), false);
      if (src.substring(lt, lt + 4) === "<!--") {
        var ce = src.indexOf("-->", lt + 4);
        i = ce < 0 ? n : ce + 3;
        continue;
      }
      if (src.charAt(lt + 1) === "!" || src.charAt(lt + 1) === "?") {
        var de = src.indexOf(">", lt + 2);
        i = de < 0 ? n : de + 1;
        continue;
      }
      var gt = findTagEnd(src, lt + 1);
      if (gt < 0) {
        addText(top(), src.substring(lt), false);
        break;
      }
      var raw = src.substring(lt + 1, gt);
      i = gt + 1;
      if (!raw) continue;
      if (raw.charAt(0) === "/") {
        var endName = raw.substring(1).replace(/^\s+/, "").split(/\s/)[0]
          .toLowerCase();
        if (endName) closeTag(endName);
        continue;
      }
      var selfClose = /\/\s*$/.test(raw);
      if (selfClose) raw = raw.replace(/\/\s*$/, "");
      var tm = /^\s*([^\s\/>]+)/.exec(raw);
      if (!tm) continue;
      var tag = tm[1].toLowerCase();
      var attrs = {};
      parseAttrs(raw.substring(tm[0].length), attrs);
      closeForStart(tag);
      var el = new SyNode("el", tag, attrs, top());
      el.__order = ++orderSeq;
      top().__children.push(el);
      if (selfClose || VOID[tag]) continue;
      stack.push(el);
      if (tag === "script" || tag === "style" || tag === "textarea" ||
          tag === "title") {
        var lower = src.toLowerCase();
        var closeAt = lower.indexOf("</" + tag, i);
        var contentEnd = closeAt < 0 ? n : closeAt;
        addText(el, src.substring(i, contentEnd), tag === "script" ||
          tag === "style");
        if (closeAt >= 0) {
          var cgt = src.indexOf(">", closeAt);
          i = cgt < 0 ? n : cgt + 1;
        } else {
          i = n;
        }
        stack.pop();
      }
    }
    return doc;
  }

  function parseFragmentNodes(html) {
    var doc = parseHtml(html);
    var out = doc.__children.slice();
    for (var i = 0; i < out.length; i++) out[i].__parent = null;
    return out;
  }

  function detach(node) {
    var p = node.__parent;
    if (!p) return node;
    var idx = p.__children.indexOf(node);
    if (idx >= 0) p.__children.splice(idx, 1);
    node.__parent = null;
    return node;
  }

  function insertNodes(ref, nodes, after) {
    var p = ref.__parent;
    if (!p) return;
    var idx = p.__children.indexOf(ref);
    if (idx < 0) return;
    if (after) idx += 1;
    for (var i = 0; i < nodes.length; i++) {
      nodes[i].__parent = p;
      p.__children.splice(idx + i, 0, nodes[i]);
    }
  }

  // ── 文本与序列化 ──
  function textOf(node) {
    var out = [];
    (function walk(n) {
      if (n.__kind === "text") {
        if (!n.__data) out.push(n.__text);
        return;
      }
      if (n.__kind === "el") {
        if (n.__tag === "script" || n.__tag === "style") return;
        if (n.__tag === "br") { out.push(" "); return; }
        var block = BLOCK[n.__tag];
        if (block) out.push(" ");
        for (var i = 0; i < n.__children.length; i++) {
          walk(n.__children[i]);
        }
        if (block) out.push(" ");
        return;
      }
      for (var j = 0; j < n.__children.length; j++) walk(n.__children[j]);
    })(node);
    return normText(out.join(""));
  }

  function ownTextOf(el) {
    var out = [];
    for (var i = 0; i < el.__children.length; i++) {
      var c = el.__children[i];
      if (c.__kind === "text" && !c.__data) out.push(c.__text);
    }
    return normText(out.join(""));
  }

  function serialize(node) {
    if (node.__kind === "text") {
      var ptag = node.__parent ? node.__parent.__tag : "";
      if (node.__data || ptag === "script" || ptag === "style") {
        return node.__text;
      }
      return escapeText(node.__text);
    }
    if (node.__kind === "doc") {
      var docOut = [];
      for (var i = 0; i < node.__children.length; i++) {
        docOut.push(serialize(node.__children[i]));
      }
      return docOut.join("");
    }
    var attrs = "";
    for (var k in node.__attrs) {
      if (!Object.prototype.hasOwnProperty.call(node.__attrs, k)) continue;
      attrs += " " + k + "=\"" + escapeAttr(node.__attrs[k]) + "\"";
    }
    var inner = [];
    for (var j = 0; j < node.__children.length; j++) {
      inner.push(serialize(node.__children[j]));
    }
    return "<" + node.__tag + attrs + ">" + inner.join("") + "</" +
      node.__tag + ">";
  }

  // ── CSS 选择器 ──
  function splitTop(s, sep) {
    var out = [];
    var start = 0;
    var depth = 0;
    var quote = 0;
    for (var i = 0; i < s.length; i++) {
      var c = s.charAt(i);
      if (quote) {
        if (c === quote) quote = 0;
        continue;
      }
      if (c === "\"" || c === "'") { quote = c; continue; }
      if (c === "[" || c === "(") { depth++; continue; }
      if (c === "]" || c === ")") { if (depth > 0) depth--; continue; }
      if (c === sep && depth === 0) {
        out.push(s.substring(start, i));
        start = i + 1;
      }
    }
    out.push(s.substring(start));
    return out;
  }

  function readIdent(s, i) {
    var out = "";
    while (i < s.length) {
      var c = s.charAt(i);
      if (c === "\\") {
        if (i + 1 < s.length) { out += s.charAt(i + 1); i += 2; continue; }
        break;
      }
      if (/[A-Za-z0-9_\-\u00a0-\uffff]/.test(c)) { out += c; i++; continue; }
      break;
    }
    return {name: out, next: i};
  }

  function matchBracket(s, i) {
    var depth = 0;
    var quote = 0;
    for (var j = i; j < s.length; j++) {
      var c = s.charAt(j);
      if (quote) {
        if (c === quote) quote = 0;
        continue;
      }
      if (c === "\"" || c === "'") { quote = c; continue; }
      if (c === "[") depth++;
      else if (c === "]") {
        depth--;
        if (depth === 0) return j;
      }
    }
    return -1;
  }

  function matchParen(s, i) {
    var depth = 0;
    var quote = 0;
    for (var j = i; j < s.length; j++) {
      var c = s.charAt(j);
      if (quote) {
        if (c === quote) quote = 0;
        continue;
      }
      if (c === "\"" || c === "'") { quote = c; continue; }
      if (c === "(") depth++;
      else if (c === ")") {
        depth--;
        if (depth === 0) return j;
      }
    }
    return -1;
  }

  function unquote(v) {
    var s = String(v == null ? "" : v).trim();
    if (s.length >= 2 &&
        ((s.charAt(0) === "\"" && s.charAt(s.length - 1) === "\"") ||
         (s.charAt(0) === "'" && s.charAt(s.length - 1) === "'"))) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }

  function parseAttrExpr(inner) {
    var m = /^\s*([^\s~|^$*!=\]]+)\s*(?:(!=|\^=|\$=|\*=|~=|\|=|=)\s*(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)'|([^\s\]]*))\s*(?:[iIsS]\s*)?)?\s*$/
      .exec(inner);
    if (!m) return null;
    var val = m[3] != null ? m[3] : (m[4] != null ? m[4] :
      (m[5] != null ? m[5] : ""));
    val = val.replace(/\\(.)/g, "$1");
    return {name: String(m[1]).toLowerCase(), op: m[2] || null, value: val};
  }

  function parseCompound(s) {
    var c = {tag: "*", id: "", classes: [], attrs: [], pseudos: [],
      coll: []};
    var i = 0;
    while (i < s.length) {
      var ch = s.charAt(i);
      if (ch === "*") { i++; continue; }
      if (ch === "#") {
        var rid = readIdent(s, i + 1);
        c.id = rid.name;
        i = rid.next;
        continue;
      }
      if (ch === ".") {
        var rcls = readIdent(s, i + 1);
        if (rcls.name) c.classes.push(rcls.name);
        i = rcls.next;
        continue;
      }
      if (ch === "[") {
        var bend = matchBracket(s, i);
        if (bend < 0) break;
        var a = parseAttrExpr(s.substring(i + 1, bend));
        if (a) c.attrs.push(a);
        i = bend + 1;
        continue;
      }
      if (ch === ":") {
        i++;
        if (s.charAt(i) === ":") i++;
        var rp = readIdent(s, i);
        var name = rp.name.toLowerCase();
        i = rp.next;
        var arg = null;
        if (s.charAt(i) === "(") {
          var pend = matchParen(s, i);
          if (pend < 0) break;
          arg = s.substring(i + 1, pend);
          i = pend + 1;
        }
        if (name === "eq" || name === "lt" || name === "gt" ||
            name === "first" || name === "last") {
          c.coll.push({name: name, arg: arg});
        } else {
          c.pseudos.push({name: name, arg: arg});
        }
        continue;
      }
      var rt = readIdent(s, i);
      if (rt.name) {
        c.tag = rt.name.toLowerCase();
        i = rt.next;
        continue;
      }
      i++;
    }
    return c;
  }

  function parseGroup(text) {
    var s = String(text);
    var parts = [];
    var i = 0;
    var pending = "";
    var first = true;
    while (i < s.length) {
      var hadSpace = false;
      while (i < s.length && /\s/.test(s.charAt(i))) {
        hadSpace = true;
        i++;
      }
      if (i >= s.length) break;
      var ch = s.charAt(i);
      if (ch === ">" || ch === "+" || ch === "~") {
        pending = ch;
        i++;
        continue;
      }
      var start = i;
      var depth = 0;
      var quote = 0;
      while (i < s.length) {
        var c = s.charAt(i);
        if (quote) {
          if (c === quote) quote = 0;
          i++;
          continue;
        }
        if (c === "\"" || c === "'") { quote = c; i++; continue; }
        if (c === "[" || c === "(") { depth++; i++; continue; }
        if (c === "]" || c === ")") { if (depth > 0) depth--; i++; continue; }
        if (depth === 0 && (c === ">" || c === "+" || c === "~")) break;
        if (depth === 0 && /\s/.test(c)) break;
        i++;
      }
      if (i === start) { i++; continue; }
      var comb = first ? null : (pending || (hadSpace ? " " : " "));
      parts.push({c: parseCompound(s.substring(start, i)), comb: comb});
      first = false;
      pending = "";
    }
    return parts;
  }

  function nthMatch(idx, expr) {
    var e = String(expr == null ? "" : expr).replace(/\s+/g, "").toLowerCase();
    if (!e) return false;
    if (e === "odd") return idx % 2 === 1;
    if (e === "even") return idx % 2 === 0;
    var m = /^([+-]?\d*)n([+-]\d+)?$/.exec(e);
    if (m) {
      var a = m[1] === "" || m[1] === "+" ? 1 :
        (m[1] === "-" ? -1 : parseInt(m[1], 10));
      var b = m[2] ? parseInt(m[2], 10) : 0;
      if (a === 0) return idx === b;
      var k = (idx - b) / a;
      return k >= 0 && Math.floor(k) === k;
    }
    return idx === parseInt(e, 10);
  }

  function elemIndex(el, fromEnd, ofType) {
    var p = el.__parent;
    if (!p) return 0;
    var list = [];
    for (var i = 0; i < p.__children.length; i++) {
      var c = p.__children[i];
      if (c.__kind !== "el") continue;
      if (ofType && c.__tag !== el.__tag) continue;
      list.push(c);
    }
    var idx = list.indexOf(el);
    if (idx < 0) return 0;
    return fromEnd ? list.length - idx : idx + 1;
  }

  function hasClass(el, name) {
    var cls = el.__attrs["class"];
    if (cls == null) return false;
    var parts = String(cls).split(/\s+/);
    return parts.indexOf(name) >= 0;
  }

  function matchAttr(el, a) {
    var v = el.__attrs[a.name];
    if (a.op == null) return v != null;
    var s = v == null ? "" : String(v);
    var t = a.value;
    if (a.op === "=") return v != null && s === t;
    if (a.op === "!=") return v == null || s !== t;
    if (a.op === "^=") return s.indexOf(t) === 0;
    if (a.op === "$=") {
      return t.length <= s.length && s.substring(s.length - t.length) === t;
    }
    if (a.op === "*=") return s.indexOf(t) >= 0;
    if (a.op === "~=") return (" " + s + " ").indexOf(" " + t + " ") >= 0;
    if (a.op === "|=") return s === t || s.indexOf(t + "-") === 0;
    return false;
  }

  function matchPseudo(el, p) {
    var name = p.name;
    var arg = p.arg == null ? "" : p.arg;
    if (name === "first-child") return !prevEl(el);
    if (name === "last-child") return !nextEl(el);
    if (name === "only-child") return !prevEl(el) && !nextEl(el);
    if (name === "first-of-type") return elemIndex(el, false, true) === 1;
    if (name === "last-of-type") {
      return elemIndex(el, true, true) === 1;
    }
    if (name === "only-of-type") {
      return elemIndex(el, false, true) === 1 &&
        elemIndex(el, true, true) === 1;
    }
    if (name === "nth-child") return nthMatch(elemIndex(el, false, false), arg);
    if (name === "nth-last-child") {
      return nthMatch(elemIndex(el, true, false), arg);
    }
    if (name === "nth-of-type") return nthMatch(elemIndex(el, false, true), arg);
    if (name === "nth-last-of-type") {
      return nthMatch(elemIndex(el, true, true), arg);
    }
    if (name === "empty") {
      for (var i = 0; i < el.__children.length; i++) {
        var c = el.__children[i];
        if (c.__kind === "el") return false;
        if (c.__kind === "text" && !c.__data && normText(c.__text)) return false;
      }
      return true;
    }
    if (name === "contains") {
      return textOf(el).toLowerCase().indexOf(unquote(arg).toLowerCase()) >= 0;
    }
    if (name === "has") return select(el, arg).length > 0;
    if (name === "not") {
      var all = select(docOf(el), arg);
      return all.indexOf(el) < 0;
    }
    if (name === "matches") {
      try { return new RegExp(unquote(arg)).test(textOf(el)); }
      catch (_) { return false; }
    }
    if (name === "root") return !parentEl(el) || el.__parent.__kind === "doc";
    if (name === "header") return /^h[1-6]$/.test(el.__tag);
    return false;
  }

  function matchCompound(el, c) {
    if (c.tag !== "*" && el.__tag !== c.tag) return false;
    if (c.id && String(el.__attrs["id"] || "") !== c.id) return false;
    for (var i = 0; i < c.classes.length; i++) {
      if (!hasClass(el, c.classes[i])) return false;
    }
    for (var j = 0; j < c.attrs.length; j++) {
      if (!matchAttr(el, c.attrs[j])) return false;
    }
    for (var k = 0; k < c.pseudos.length; k++) {
      if (!matchPseudo(el, c.pseudos[k])) return false;
    }
    return true;
  }

  function matchParts(el, parts) {
    var last = parts.length - 1;
    if (!matchCompound(el, parts[last].c)) return false;
    var cur = el;
    for (var i = last; i > 0; i--) {
      var comb = parts[i].comb;
      var prev = parts[i - 1].c;
      if (comb === ">") {
        cur = parentEl(cur);
        if (!cur || !matchCompound(cur, prev)) return false;
      } else if (comb === "+") {
        cur = prevEl(cur);
        if (!cur || !matchCompound(cur, prev)) return false;
      } else if (comb === "~") {
        var s = prevEl(cur);
        var found = null;
        while (s) {
          if (matchCompound(s, prev)) { found = s; break; }
          s = prevEl(s);
        }
        if (!found) return false;
        cur = found;
      } else {
        var p = parentEl(cur);
        var hit = null;
        while (p) {
          if (matchCompound(p, prev)) { hit = p; break; }
          p = parentEl(p);
        }
        if (!hit) return false;
        cur = hit;
      }
    }
    return true;
  }

  function applyColl(list, coll) {
    var out = list;
    for (var i = 0; i < coll.length; i++) {
      var p = coll[i];
      var n = parseInt(p.arg, 10);
      if (p.name === "first") out = out.slice(0, 1);
      else if (p.name === "last") out = out.slice(Math.max(0, out.length - 1));
      else if (p.name === "eq") {
        var idx = n < 0 ? out.length + n : n;
        out = idx >= 0 && idx < out.length ? [out[idx]] : [];
      } else if (p.name === "lt") {
        var m = n < 0 ? out.length + n : n;
        out = out.slice(0, Math.max(0, m));
      } else if (p.name === "gt") {
        var g = n < 0 ? out.length + n : n;
        out = out.slice(Math.max(0, g + 1));
      }
    }
    return out;
  }

  function select(root, selector) {
    var sel = String(selector == null ? "" : selector).trim();
    if (!sel) return elements([]);
    var groups = splitTop(sel, ",");
    var all = allDesc(root);
    // jsoup Collector 从根开始匹配：Element.select 包含元素自身（Document 不参与）。
    if (root.__kind === "el") all.unshift(root);
    var out = [];
    for (var i = 0; i < groups.length; i++) {
      var g = groups[i].trim();
      if (!g) continue;
      var parts = parseGroup(g);
      if (!parts.length) continue;
      var cand = [];
      for (var j = 0; j < all.length; j++) {
        if (matchParts(all[j], parts)) cand.push(all[j]);
      }
      cand = applyColl(cand, parts[parts.length - 1].c.coll);
      out = out.concat(cand);
    }
    out.sort(function (a, b) { return a.__order - b.__order; });
    var uniq = [];
    for (var k = 0; k < out.length; k++) {
      if (uniq.indexOf(out[k]) < 0) uniq.push(out[k]);
    }
    return elements(uniq);
  }

  // ── Element / Document 方法 ──
  function firstByTag(root, tag) {
    var all = allDesc(root);
    for (var i = 0; i < all.length; i++) {
      if (all[i].__tag === tag) return all[i];
    }
    return null;
  }

  var NodeProto = {
    select: function (sel) { return select(this, sel); },
    selectFirst: function (sel) {
      var list = select(this, sel);
      return list.length ? list[0] : null;
    },
    is: function (sel) {
      var all = select(docOf(this), sel);
      return all.indexOf(this) >= 0;
    },
    text: function () { return textOf(this); },
    ownText: function () { return ownTextOf(this); },
    attr: function (key, value) {
      var k = String(key == null ? "" : key).toLowerCase();
      if (k.indexOf("abs:") === 0) k = k.substring(4);
      if (arguments.length >= 2) {
        this.__attrs[k] = String(value == null ? "" : value);
        return this;
      }
      var v = this.__attrs[k];
      return v == null ? "" : String(v);
    },
    hasAttr: function (key) {
      return Object.prototype.hasOwnProperty.call(
        this.__attrs, String(key).toLowerCase());
    },
    html: function (value) {
      if (arguments.length >= 1) {
        this.__children = [];
        var nodes = parseFragmentNodes(value);
        for (var i = 0; i < nodes.length; i++) {
          nodes[i].__parent = this;
          this.__children.push(nodes[i]);
        }
        return this;
      }
      var out = [];
      for (var j = 0; j < this.__children.length; j++) {
        out.push(serialize(this.__children[j]));
      }
      return out.join("");
    },
    outerHtml: function () { return serialize(this); },
    id: function () { return String(this.__attrs["id"] || ""); },
    hasClass: function (name) { return hasClass(this, String(name)); },
    classNames: function () {
      var cls = this.__attrs["class"];
      return cls == null ? [] : String(cls).split(/\s+/).filter(function (s) {
        return !!s;
      });
    },
    getElementsByClass: function (name) {
      return select(this, "." + String(name));
    },
    getElementsByTag: function (tag) {
      return select(this, String(tag));
    },
    getElementById: function (id) {
      var list = select(this, "#" + String(id));
      return list.length ? list[0] : null;
    },
    parent: function () { return parentEl(this); },
    parents: function () {
      var out = [];
      var p = parentEl(this);
      while (p) {
        out.push(p);
        p = parentEl(p);
      }
      return elements(out);
    },
    children: function () {
      var out = [];
      for (var i = 0; i < this.__children.length; i++) {
        if (this.__children[i].__kind === "el") out.push(this.__children[i]);
      }
      return elements(out);
    },
    child: function (i) {
      var kids = this.children();
      var idx = i < 0 ? kids.length + i : i;
      return kids[idx] || null;
    },
    tagName: function () { return this.__tag; },
    nodeName: function () {
      return this.__kind === "doc" ? "#document" : this.__tag.toUpperCase();
    },
    nextElementSibling: function () { return nextEl(this); },
    previousElementSibling: function () { return prevEl(this); },
    nextElementSiblings: function () {
      var out = [this];
      var n = nextEl(this);
      while (n) { out.push(n); n = nextEl(n); }
      return elements(out);
    },
    previousElementSiblings: function () {
      var out = [this];
      var n = prevEl(this);
      while (n) { out.push(n); n = prevEl(n); }
      return elements(out);
    },
    firstElementSibling: function () {
      var p = parentEl(this);
      return p ? p.firstElementChild() : this;
    },
    lastElementSibling: function () {
      var p = parentEl(this);
      return p ? p.lastElementChild() : this;
    },
    firstElementChild: function () {
      for (var i = 0; i < this.__children.length; i++) {
        if (this.__children[i].__kind === "el") return this.__children[i];
      }
      return null;
    },
    lastElementChild: function () {
      for (var i = this.__children.length - 1; i >= 0; i--) {
        if (this.__children[i].__kind === "el") return this.__children[i];
      }
      return null;
    },
    // jsoup 1.16 `siblingElements()`，1.17+ 更名 `siblings()`（不含自身）。
    siblingElements: function () {
      var out = [];
      var p = this.__parent;
      if (p) {
        for (var i = 0; i < p.__children.length; i++) {
          var c = p.__children[i];
          if (c.__kind === "el" && c !== this) out.push(c);
        }
      }
      return elements(out);
    },
    siblings: function () { return this.siblingElements(); },
    // jsoup 1.16 `elementSiblingIndex()`（元素子序列下标），1.17+ `siblingIndex()`。
    elementSiblingIndex: function () {
      var p = this.__parent;
      if (!p) return 0;
      var idx = 0;
      for (var i = 0; i < p.__children.length; i++) {
        var c = p.__children[i];
        if (c.__kind !== "el") continue;
        if (c === this) return idx;
        idx++;
      }
      return 0;
    },
    siblingIndex: function () { return this.elementSiblingIndex(); },
    hasText: function () { return hasVisibleText(this); },
    data: function () { return dataOf(this); },
    className: function () { return String(this.__attrs["class"] || ""); },
    addClass: function (name) {
      var n = String(name);
      if (n && !hasClass(this, n)) {
        var cur = this.__attrs["class"];
        this.__attrs["class"] = cur == null || cur === "" ? n : cur + " " + n;
      }
      return this;
    },
    removeClass: function (name) {
      var n = String(name);
      var cur = this.__attrs["class"];
      if (cur != null && n) {
        var kept = String(cur).split(/\s+/).filter(function (s) {
          return !!s && s !== n;
        });
        this.__attrs["class"] = kept.join(" ");
      }
      return this;
    },
    toggleClass: function (name) {
      return hasClass(this, String(name))
        ? this.removeClass(name) : this.addClass(name);
    },
    remove: function () { detach(this); return this; },
    before: function (html) {
      insertNodes(this, parseFragmentNodes(html), false);
      return this;
    },
    after: function (html) {
      insertNodes(this, parseFragmentNodes(html), true);
      return this;
    },
    append: function (html) {
      var nodes = parseFragmentNodes(html);
      for (var i = 0; i < nodes.length; i++) {
        nodes[i].__parent = this;
        this.__children.push(nodes[i]);
      }
      return this;
    },
    prepend: function (html) {
      var nodes = parseFragmentNodes(html);
      for (var i = nodes.length - 1; i >= 0; i--) {
        nodes[i].__parent = this;
        this.__children.unshift(nodes[i]);
      }
      return this;
    },
    val: function (value) {
      if (arguments.length >= 1) {
        this.__attrs["value"] = String(value == null ? "" : value);
        return this;
      }
      return String(this.__attrs["value"] || "");
    },
    body: function () {
      return firstByTag(this, "body") || this;
    },
    head: function () {
      return firstByTag(this, "head") || this;
    },
    title: function () {
      var t = firstByTag(this, "title");
      return t ? textOf(t) : "";
    },
    toString: function () { return serialize(this); }
  };

  function SyElement() {}
  SyElement.prototype = NodeProto;
  // 解析出的节点对象统一挂到 NodeProto（构造器仅用于类型归属）。
  function attachProto(node) {
    Object.setPrototypeOf(node, NodeProto);
    return node;
  }

  var _parseHtmlBase = parseHtml;
  parseHtml = function (html) {
    var doc = _parseHtmlBase(html);
    (function walk(n) {
      attachProto(n);
      if (n.__children) {
        for (var i = 0; i < n.__children.length; i++) walk(n.__children[i]);
      }
    })(doc);
    return doc;
  };

  // ── Elements（Array 子类，jsoup 习惯方法） ──
  var ElementsProto = Object.create(Array.prototype);
  ElementsProto.size = function () { return this.length; };
  ElementsProto.get = function (i) {
    var idx = i < 0 ? this.length + i : i;
    return idx >= 0 && idx < this.length ? this[idx] : null;
  };
  ElementsProto.first = function () {
    return this.length ? this[0] : null;
  };
  ElementsProto.last = function () {
    return this.length ? this[this.length - 1] : null;
  };
  ElementsProto.isEmpty = function () { return this.length === 0; };
  ElementsProto.text = function () {
    var out = [];
    for (var i = 0; i < this.length; i++) {
      var t = textOf(this[i]);
      if (t) out.push(t);
    }
    return out.join(" ");
  };
  ElementsProto.eachText = function () {
    var out = [];
    for (var i = 0; i < this.length; i++) {
      if (this[i].hasText()) out.push(textOf(this[i]));
    }
    return out;
  };
  ElementsProto.eachAttr = function (name) {
    var out = [];
    for (var i = 0; i < this.length; i++) {
      if (this[i].hasAttr(name)) out.push(this[i].attr(name));
    }
    return out;
  };
  ElementsProto.attr = function (name, value) {
    if (arguments.length >= 2) {
      for (var i = 0; i < this.length; i++) this[i].attr(name, value);
      return this;
    }
    for (var j = 0; j < this.length; j++) {
      if (this[j].hasAttr(name)) return this[j].attr(name);
    }
    return "";
  };
  ElementsProto.hasAttr = function (name) {
    for (var i = 0; i < this.length; i++) {
      if (this[i].hasAttr(name)) return true;
    }
    return false;
  };
  ElementsProto.removeAttr = function (name) {
    var n = String(name).toLowerCase();
    for (var i = 0; i < this.length; i++) delete this[i].__attrs[n];
    return this;
  };
  ElementsProto.addClass = function (name) {
    for (var i = 0; i < this.length; i++) this[i].addClass(name);
    return this;
  };
  ElementsProto.removeClass = function (name) {
    for (var i = 0; i < this.length; i++) this[i].removeClass(name);
    return this;
  };
  ElementsProto.toggleClass = function (name) {
    for (var i = 0; i < this.length; i++) this[i].toggleClass(name);
    return this;
  };
  ElementsProto.hasClass = function (name) {
    for (var i = 0; i < this.length; i++) {
      if (this[i].hasClass(name)) return true;
    }
    return false;
  };
  ElementsProto.hasText = function () {
    for (var i = 0; i < this.length; i++) {
      if (this[i].hasText()) return true;
    }
    return false;
  };
  ElementsProto.val = function (value) {
    if (arguments.length >= 1) {
      for (var i = 0; i < this.length; i++) this[i].val(value);
      return this;
    }
    return this.length ? this[0].val() : "";
  };
  ElementsProto.html = function () {
    var out = [];
    for (var i = 0; i < this.length; i++) out.push(this[i].html());
    return out.join("\n");
  };
  ElementsProto.outerHtml = function () {
    var out = [];
    for (var i = 0; i < this.length; i++) out.push(this[i].outerHtml());
    return out.join("\n");
  };
  ElementsProto.select = function (sel) {
    var out = [];
    for (var i = 0; i < this.length; i++) {
      var sub = select(this[i], sel);
      for (var j = 0; j < sub.length; j++) {
        if (out.indexOf(sub[j]) < 0) out.push(sub[j]);
      }
    }
    out.sort(function (a, b) { return a.__order - b.__order; });
    return elements(out);
  };
  ElementsProto.selectFirst = function (sel) {
    var list = this.select(sel);
    return list.length ? list[0] : null;
  };
  ElementsProto.eq = function (i) {
    var el = this.get(i);
    return elements(el ? [el] : []);
  };
  ElementsProto.not = function (sel) {
    var out = [];
    for (var i = 0; i < this.length; i++) {
      if (!this[i].is(sel)) out.push(this[i]);
    }
    return elements(out);
  };
  ElementsProto.has = function (sel) {
    var out = [];
    for (var i = 0; i < this.length; i++) {
      if (this[i].select(sel).length) out.push(this[i]);
    }
    return elements(out);
  };
  ElementsProto.is = function (sel) {
    for (var i = 0; i < this.length; i++) {
      if (this[i].is(sel)) return true;
    }
    return false;
  };
  ElementsProto.parents = function () {
    var out = [];
    for (var i = 0; i < this.length; i++) {
      var ps = this[i].parents();
      for (var j = 0; j < ps.length; j++) {
        if (out.indexOf(ps[j]) < 0) out.push(ps[j]);
      }
    }
    return elements(out);
  };
  // jsoup Elements.next/nextAll/prev/prevAll：逐个元素取元素兄弟；
  // prev 方向为逆文档序（最近者在前），带查询时只保留匹配项。
  function siblingWalk(list, next, all, query) {
    var out = [];
    var sel = query == null ? null : String(query);
    for (var i = 0; i < list.length; i++) {
      var e = list[i];
      do {
        var sib = next ? nextEl(e) : prevEl(e);
        if (!sib) break;
        if (!sel || sib.is(sel)) out.push(sib);
        e = sib;
      } while (all);
    }
    return elements(out);
  }
  ElementsProto.next = function (query) {
    return siblingWalk(this, true, false, query);
  };
  ElementsProto.nextAll = function (query) {
    return siblingWalk(this, true, true, query);
  };
  ElementsProto.prev = function (query) {
    return siblingWalk(this, false, false, query);
  };
  ElementsProto.prevAll = function (query) {
    return siblingWalk(this, false, true, query);
  };
  // java.util.List（legado 侧 Elements 即 ArrayList）常用判定。
  ElementsProto.contains = function (el) { return this.indexOf(el) >= 0; };
  ElementsProto.asList = function () { return this.slice(); };
  ElementsProto.remove = function (arg) {
    if (typeof arg === "number") {
      var idx = arg < 0 ? this.length + arg : arg;
      if (idx < 0 || idx >= this.length) return null;
      return this.splice(idx, 1)[0];
    }
    var at = this.indexOf(arg);
    if (at < 0) return false;
    this.splice(at, 1);
    return true;
  };
  ElementsProto.toString = function () { return this.outerHtml(); };

  function elements(list) {
    var arr = [];
    if (list) {
      for (var i = 0; i < list.length; i++) arr.push(list[i]);
    }
    Object.setPrototypeOf(arr, ElementsProto);
    return arr;
  }

  // ── 入口 ──
  Jsoup.parse = function (html, baseUri) {
    return attachProto(parseHtml(html));
  };
  Jsoup.parseBodyFragment = function (html, baseUri) {
    return Jsoup.parse(html, baseUri);
  };
})(globalThis);
''';
