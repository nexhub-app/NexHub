/// 规则引擎门面：按规则模式（CSS/XPath/JSON/JS/正则）分派到对应解析器，
/// 支持 `##` 正则替换、`@put` 变量、`<js>`/`@js:` 内嵌脚本与 `&&/||/%%` 复合规则。
library;

import 'dart:convert';

import 'package:html/dom.dart';
import '../../../core/utils/app_log.dart';
import 'html4_entities.dart';
import 'source_rule.dart';
import 'analyze_jsoup.dart';
import 'analyze_xpath.dart';
import 'analyze_json.dart';
import 'analyze_regex.dart';
import 'regex_compat.dart';
import 'js_engine.dart';
import 'source_context.dart';
import '../model/xiaoshuo_book.dart';
import '../model/xiaoshuo_book_chapter.dart';

class AnalyzeRule {
  XiaoshuoBook? book;
  XiaoshuoBookChapter? chapter;
  String? baseUrl;
  String? redirectUrl;
  String? nextChapterUrl;
  dynamic content;
  bool isJson = false;

  /// 对齐 legado AnalyzeRule.isRegex：列表规则以 `:` 开头（AllInOne 正则）
  /// 后，同一实例的后续规则默认按正则模式求值（`$N` 分组引用依赖此模式）。
  bool _isRegex = false;

  AnalyzeByJsoup? _analyzeByJsoup;
  AnalyzeByXPath? _analyzeByXPath;
  AnalyzeByJson? _analyzeByJson;
  JsEngine? _jsEngine;

  final Map<String, String> _variables = {};
  final Map<String, List<SourceRule>> _stringRuleCache = {};

  AnalyzeRule({this.book, this.chapter}) {
    // legado 的规则变量表就是书对象的 variableMap（跨搜索/详情/目录/正文
    // 阶段共享）：以传入书为种子初始化，搜索阶段 `@put:{gid:...}` /
    // java.put 写入的变量，后续阶段 `@get:{gid}` / java.get 才读得到
    // （API 型源把 gid/nid 等签名参数写在搜索阶段，目录/正文 URL 依赖）。
    final bookVars = book?.variableMap;
    if (bookVars != null && bookVars.isNotEmpty) {
      _variables.addAll(bookVars);
    }
  }

  /// 本规则实例当前的变量表快照（`@put` / JS java.put 的写入）。
  /// 供各解析阶段结束后把变量回写暂存（跨阶段贯通）。
  Map<String, String> get variables => _variables;

  AnalyzeRule setContent(dynamic newContent, [String? newBaseUrl]) {
    content = newContent;
    if (newContent is! Node) {
      isJson = _isJsonString(newContent?.toString() ?? '');
    } else {
      isJson = false;
    }
    if (newBaseUrl != null) baseUrl = newBaseUrl;
    _analyzeByJsoup = null;
    _analyzeByXPath = null;
    _analyzeByJson = null;
    return this;
  }

  AnalyzeRule setBaseUrl(String? url) {
    if (url != null) baseUrl = url;
    return this;
  }

  String? setRedirectUrl(String url) {
    try {
      redirectUrl = url;
    } catch (_) {}
    return redirectUrl;
  }

  AnalyzeRule setChapter(XiaoshuoBookChapter? ch) {
    chapter = ch;
    return this;
  }

  AnalyzeRule setNextChapterUrl(String? url) {
    nextChapterUrl = url;
    return this;
  }

  void put(String key, String value) {
    if (key == 'title' && chapter != null) {
      chapter!.title = value;
    }
    // legado AnalyzeRule.put：chapter → book → ruleData → source。目录逐条
    // 复用同一个规则实例时，若写入实例级变量表，本章 @put 会污染后续章节
    //（跨章串扰）。有章节绑定就必须落到本章 variableMap。
    final ch = chapter;
    if (ch != null) {
      ch.putVariable(key, value);
      return;
    }
    _variables[key] = value;
  }

  String get(String key) {
    switch (key) {
      case 'bookName':
        if (book != null) return book!.name;
        break;
      case 'title':
        if (chapter != null) return chapter!.title;
        break;
    }
    // legado AnalyzeRule.get：chapter → book → ruleData → source，空值不
    // 短路（`takeIf { it.isNotEmpty() }`），源级变量也能被 `@get` 读到。
    String nonEmpty(String? v) => (v != null && v.isNotEmpty) ? v : '';
    final fromChapter = nonEmpty(chapter?.getVariable(key));
    if (fromChapter.isNotEmpty) return fromChapter;
    final fromBook = nonEmpty(book?.getVariable(key));
    if (fromBook.isNotEmpty) return fromBook;
    final local = nonEmpty(_variables[key]);
    if (local.isNotEmpty) return local;
    final sourceVars = ShuyuanSourceContext.current?.sourceVars;
    // legado 链尾是 source.get(key)（BaseSource 的 v_ 命名空间 =
    // 本实现的 `__v:` 前缀，source.put 写入处）；无前缀的源变量是
    // NexHub 扩展通道，作为最后兜底保留。
    final fromSourcePut = nonEmpty(sourceVars?['__v:$key']);
    if (fromSourcePut.isNotEmpty) return fromSourcePut;
    return nonEmpty(sourceVars?[key]);
  }

  List<String> getStringList(String? ruleStr, {bool isUrl = false}) {
    if (ruleStr == null || ruleStr.isEmpty) return [];
    final ruleList = _splitSourceRuleCache(ruleStr);
    return _getStringListFromRules(ruleList, isUrl: isUrl);
  }

  String getString(String? ruleStr, {bool unescape = true, bool isUrl = false, dynamic mContent}) {
    if (ruleStr == null || ruleStr.isEmpty) return '';
    final ruleList = _splitSourceRuleCache(ruleStr);
    return _getStringFromRules(ruleList, unescape: unescape, isUrl: isUrl, mContent: mContent);
  }

  String getStringFromRules(List<dynamic> ruleList, {bool unescape = true, bool isUrl = false, dynamic mContent}) {
    if (ruleList.isEmpty) return '';
    final sourceRules = ruleList.whereType<SourceRule>().toList();
    return _getStringFromRules(sourceRules, unescape: unescape, isUrl: isUrl, mContent: mContent);
  }

  List<String> getStringListFromRules(List<dynamic> ruleList, {bool isUrl = false}) {
    if (ruleList.isEmpty) return [];
    final sourceRules = ruleList.whereType<SourceRule>().toList();
    return _getStringListFromRules(sourceRules, isUrl: isUrl);
  }

  List<dynamic> getElements(String ruleStr) {
    if (ruleStr.isEmpty) return [];
    final ruleList = splitSourceRule(ruleStr, allInOne: true);
    return _getElementsFromRules(ruleList);
  }

  dynamic getElement(String ruleStr) {
    if (ruleStr.isEmpty) return null;
    var result = content;
    final ruleList = splitSourceRule(ruleStr, allInOne: true);
    if (result != null && ruleList.isNotEmpty) {
      for (final sourceRule in ruleList) {
        _putAll(sourceRule.putMap);
        if (result == null) continue;
        // 对齐 legado getElement：每条规则只 makeUpRule 一次，并把展开后
        // 的规则文本交给执行器（此前执行器内部会再 makeUp 一次）。
        final st = _makeUpRule(sourceRule, result);
        if (st.rule.isNotEmpty) {
          result = _executeRuleElements(result, sourceRule,
              single: true, prepared: st);
        }
        if (result != null && st.replaceRegex.isNotEmpty) {
          result = _replaceRegex(result.toString(), st);
        }
      }
    }
    return result;
  }

  List<SourceRule> _splitSourceRuleCache(String ruleStr) {
    return _stringRuleCache.putIfAbsent(ruleStr, () => splitSourceRule(ruleStr));
  }

  List<SourceRule> splitSourceRule(String? ruleStr, {bool allInOne = false}) {
    if (ruleStr == null || ruleStr.isEmpty) return [];
    final ruleList = <SourceRule>[];
    Mode mMode = Mode.defaultMode;
    var start = 0;

    if (allInOne && ruleStr.startsWith(':')) {
      // legado：仅首字符为 `:` 时为 AllInOne 正则（`:` 与伪类选择器冲突，
      // 只用于列表规则）；一旦进入正则模式，本实例后续规则沿用。
      mMode = Mode.regex;
      _isRegex = true;
      start = 1;
    } else if (_isRegex) {
      mMode = Mode.regex;
    }

    // 不再预分割 &&，让 AnalyzeByJsoup 内部处理 &&/||/%%
    final trimmed = ruleStr.substring(start).trim();
    if (trimmed.isEmpty) return [];

    // 处理 JS 模式
    final jsPattern = RegExp(r'<js>([\w\W]*?)</js>|@js:([\w\W]*)', caseSensitive: false);
    final matches = jsPattern.allMatches(trimmed).toList();

    var segStart = 0;
    for (final match in matches) {
      if (match.start > segStart) {
        final tmp = trimmed.substring(segStart, match.start).trim();
        if (tmp.isNotEmpty) {
          ruleList.add(SourceRule(tmp, mMode, isJson));
        }
      }
      final rawJs = match.group(2) ?? match.group(1) ?? '';
      // `@js:代码##match##replace###`：`##` 起是 legado 的正则替换尾，
      // 不能吞进脚本体。紧贴 `@js:`（空脚本）表示「对前段结果直接做正则
      // 替换」；若整段交给 JS 求值会 SyntaxError → 规则恒为空（社区源
      // 合成封面 URL 的高频写法）。
      var jsContent = rawJs;
      var tail = '';
      if (match.group(2) != null) {
        final idx = rawJs.indexOf('##');
        if (idx >= 0) {
          tail = rawJs.substring(idx);
          jsContent = rawJs.substring(0, idx);
        }
      }
      // 空脚本体不产出 JS 段（避免把上一段结果求值成空串），仅保留替换尾。
      if (jsContent.trim().isNotEmpty || tail.isEmpty) {
        ruleList.add(SourceRule(jsContent, Mode.js, isJson));
      }
      if (tail.isNotEmpty) {
        ruleList.add(SourceRule(tail, mMode, isJson));
      }
      segStart = match.end;
    }

    // 处理后台 WebView JS（`@webjs:`）：legado 在 JS 扫描后再扫一遍，
    // 两轮共用同一个起点，末尾残余只补一次。
    final webJsPattern = RegExp(r'@webjs:([\w\W]{5,})', caseSensitive: false);
    for (final match in webJsPattern.allMatches(trimmed)) {
      if (match.start < segStart) continue;
      if (match.start > segStart) {
        final tmp = trimmed.substring(segStart, match.start).trim();
        if (tmp.isNotEmpty) {
          ruleList.add(SourceRule(tmp, mMode, isJson));
        }
      }
      ruleList.add(SourceRule(match.group(1)!, Mode.webJs, isJson));
      segStart = match.end;
    }

    if (trimmed.length > segStart) {
      final tmp = trimmed.substring(segStart).trim();
      if (tmp.isNotEmpty) {
        ruleList.add(SourceRule(tmp, mMode, isJson));
      }
    }

    return ruleList;
  }

  String _getStringFromRules(List<SourceRule> ruleList, {bool unescape = true, bool isUrl = false, dynamic mContent}) {
    if (ruleList.isEmpty) return '';
    var result = mContent ?? content;
    if (result != null && ruleList.isNotEmpty) {
      for (final sourceRule in ruleList) {
        _putAll(sourceRule.putMap);
        final st = _makeUpRule(sourceRule, result);
        if (result == null) continue;
        if (st.rule.isNotEmpty || st.replaceRegex.isEmpty) {
          if (st.templateMode) {
            // 模板模式：内嵌表达式替换后的整串即结果。
            result = st.rule;
          } else {
            result = _executeRule(result, sourceRule.mode, st.rule, isUrl: isUrl);
          }
        }
        if (result != null && st.replaceRegex.isNotEmpty) {
          result = _replaceRegex(result.toString(), st);
        }
      }
    }
    result ??= '';
    var resultStr = result.toString();
    if (unescape && resultStr.contains('&')) {
      resultStr = _unescapeHtml(resultStr);
    }
    if (isUrl) {
      if (resultStr.trim().isEmpty) {
        return baseUrl ?? '';
      }
      return _getAbsoluteUrl(resultStr);
    }
    return resultStr;
  }

  List<String> _getStringListFromRules(List<SourceRule> ruleList, {bool isUrl = false}) {
    if (ruleList.isEmpty) return [];
    var result = content;
    if (content != null && ruleList.isNotEmpty) {
      for (final sourceRule in ruleList) {
        _putAll(sourceRule.putMap);
        final st = _makeUpRule(sourceRule, result);
        if (result == null) continue;
        if (st.rule.isNotEmpty || st.replaceRegex.isEmpty) {
          if (st.templateMode) {
            result = st.rule;
          } else if (sourceRule.mode == Mode.js && st.rule.trim().isNotEmpty) {
            // legado evalJS 列表语境：JS 直接返回数组时逐个条目作为列表项
            //（nextTocUrl 常见写法 `let list = [...]; list`）。空数组必须
            // 产出空列表——字符串化成 "[]" 会被绝对化成假分页地址并多抓
            // 一次 404 页面。
            final js = _evalJs(st.rule, result, structured: true);
            if (js is List) {
              result = js
                  .map((e) => e == null ? '' : e.toString())
                  .where((s) => s.isNotEmpty)
                  .toList();
            } else {
              result = js ?? '';
            }
          } else if (sourceRule.mode == Mode.webJs && st.rule.trim().isNotEmpty) {
            // legado getStringList：WebJs 结果先按 JSON 字符串数组解析，
            // 解析失败按原串（后续再按换行切分）。
            final raw = _evalWebJs(st.rule, result);
            result = _parseWebJsStringList(raw) ?? raw;
          } else {
            result = _executeRule(result, sourceRule.mode, st.rule,
                isUrl: isUrl, single: false);
          }
        }
        if (result != null && st.replaceRegex.isNotEmpty) {
          if (result is List) {
            result = result.map((o) => _replaceRegex(o.toString(), st)).toList();
          } else {
            result = _replaceRegex(result.toString(), st);
          }
        }
      }
    }
    if (result == null) return [];
    List<String> out;
    if (result is String) {
      // legado getStringList：按换行拆分但保留空串项（调用方按索引对齐时
      // 依赖占位空行；isUrl 分支另行过滤空项）。
      out = result.split('\n');
    } else if (result is List) {
      out = result.map((e) => e.toString()).toList();
    } else {
      out = [result.toString()];
    }
    if (isUrl) {
      // legado AnalyzeRule.getStringList(isUrl)：逐项绝对化并按出现顺序去重
      // （nextTocUrl 多选器/并集规则常重复命中同一页）。
      final seen = <String>{};
      out = [
        for (final u in out)
          if (u.trim().isNotEmpty) _getAbsoluteUrl(u)
      ].where(seen.add).toList();
    }
    return out;
  }

  List<dynamic> _getElementsFromRules(List<SourceRule> ruleList) {
    if (ruleList.isEmpty) return [];
    var result = content;

    for (final sourceRule in ruleList) {
      _putAll(sourceRule.putMap);
      // legado getElements 不执行 makeUpRule：列表规则按原始文本进入各
      // 模式解析（`$N`/`{{}}` 展开只在 getString/getElement 路径发生）。
      result = _executeRuleElements(result, sourceRule, makeUp: false);
      if (result == null) continue;
    }

    if (result == null) return [];
    if (result is List) return result;
    return [];
  }

  dynamic _executeRule(dynamic result, Mode mode, String rule,
      {bool isUrl = false, bool single = true}) {
    switch (mode) {
      case Mode.js:
        // legado 空脚本（如 `规则@js:`）等价于不转换，直接透传上游结果。
        if (rule.trim().isEmpty) return result;
        return _evalJs(rule, result);
      case Mode.webJs:
        if (rule.trim().isEmpty) return result;
        return _evalWebJs(rule, result);
      case Mode.regex:
        return rule;
      case Mode.json:
        final analyzer = _getJsonAnalyzer(result);
        return analyzer.getString(rule);
      case Mode.xpath:
        final analyzer = _getXPathAnalyzer(result);
        return analyzer.getString(rule);
      case Mode.defaultMode:
        // legado AnalyzeRule 对 NativeObject/LinkedTreeMap 内容按「字段名
        // 直读」：JS 列表规则返回对象数组时，chapterName `text` /
        // chapterUrl `href` 等默认模式规则读的是对象字段，而非 CSS。
        // 页面体不是 JSON（HTML 上由脚本组装对象）时规则按默认模式切分，
        // 若落到 CSS 引擎会恒空 → 整页 0 章。`@` 开头的属性/方法写法在
        // 对象上无意义（legado 同样取不到），保持空串。
        if (result is Map) {
          final key = rule.trim();
          if (key.isEmpty || key.startsWith('@')) return '';
          return _getJsonAnalyzer(result).getString(key);
        }
        final analyzer = _getJsoupAnalyzer(result);
        if (isUrl) {
          // legado getStringList 的 Default 分支走 getStringList（全部命中）；
          // 单值 getString 走 getString0（首个），避免多值按换行拼成假 URL。
          return single ? analyzer.getString0(rule) : analyzer.getStringList(rule);
        }
        return analyzer.getString(rule);
    }
  }

  dynamic _executeRuleElements(
      dynamic result, SourceRule sourceRule,
      {bool single = false, bool makeUp = true, _RuleState? prepared}) {
    final st = prepared ??
        (makeUp
            ? _makeUpRule(sourceRule, result)
            : _RuleState(
                sourceRule.rule,
                sourceRule.replaceRegex,
                sourceRule.replacement,
                sourceRule.replaceFirst,
                sourceRule.templateMode,
              ));
    final rule = st.rule;

    switch (sourceRule.mode) {
      case Mode.js:
        // 空脚本体透传（`规则@js:` 等），非空才做结构化求值。
        if (rule.trim().isEmpty) return result;
        // 目录/列表类 JS 规则常返回对象数组（如按卷组装 {name,url,volume}）。
        // 字符串结果无法还原对象，须走结构化求值（JSON 回传）。
        final jsResult = _evalJs(rule, result, structured: true);
        // legado getElement（single）：JS 完成值原样返回——init 规则返回
        // `JSON.stringify(...)` 文本时必须保留该文本（截断成空列表会让
        // 后续字段规则在 `[]` 上求值，整本详情解析全空）。
        if (single) return jsResult;
        // legado getElements：JS 段结果原样交给下一段规则。`<js>…</js>` 后
        // 跟 JSONPath 的组合规则（API 型目录源）依赖 JS 返回的 JSON 字符串
        // 透传；仅返回列表时直接作为元素集合。此前非 List 一律丢成空，
        // 组合规则恒 0 元素 → 目录整页为空。
        if (jsResult is List) return jsResult;
        if (jsResult is String) return jsResult;
        return [];
      case Mode.webJs:
        // legado getElement：结果按 JSON 对象解析；getElements：按 JSON
        // 对象数组解析。解析失败分别得到 null / 空列表。
        if (rule.trim().isEmpty) return result;
        final raw = _evalWebJs(rule, result);
        if (single) return _parseWebJsElement(raw);
        return _parseWebJsElements(raw) ?? const [];
      case Mode.regex:
        if (result is String) {
          // legado AnalyzeByRegex.getElements：每次命中产出「整串+全部分组」
          // 的分组数组，供 chapterName/chapterUrl 的 `$N` 规则取值。
          if (single) return AnalyzeByRegex.getElement(result, rule);
          return AnalyzeByRegex.getElements(result, rule);
        }
        return single ? null : [];
      case Mode.json:
        final analyzer = _getJsonAnalyzer(result);
        // single（getElement/init 规则）：返回对象本身；列表规则返回元素数组。
        return single ? analyzer.getObject(rule) : analyzer.getList(rule);
      case Mode.xpath:
        final analyzer = _getXPathAnalyzer(result);
        return analyzer.getElements(rule);
      case Mode.defaultMode:
        final analyzer = _getJsoupAnalyzer(result);
        return analyzer.getElements(rule);
    }
  }

  AnalyzeByJsoup _getJsoupAnalyzer(dynamic content) {
    if (_analyzeByJsoup == null || _analyzeByJsoup!.content != content) {
      _analyzeByJsoup = AnalyzeByJsoup(content);
    }
    return _analyzeByJsoup!;
  }

  AnalyzeByXPath _getXPathAnalyzer(dynamic content) {
    if (_analyzeByXPath == null || _analyzeByXPath!.content != content) {
      _analyzeByXPath = AnalyzeByXPath(content);
    }
    return _analyzeByXPath!;
  }

  AnalyzeByJson _getJsonAnalyzer(dynamic content) {
    if (_analyzeByJson == null || _analyzeByJson!.content != content) {
      _analyzeByJson = AnalyzeByJson(content);
    }
    return _analyzeByJson!;
  }

  dynamic _evalJs(String jsStr, dynamic result,
      {Map<String, dynamic>? extraBindings, bool structured = false}) {
    try {
      // 按源复用引擎：同一书源的列表/详情/目录/正文共用一套运行时与
      // jsLib 全局，避免逐章重建 QuickJS。无活动上下文（如离线单测）
      // 时退化为独立实例。
      _jsEngine ??= JsEngine.forSource(
          ShuyuanSourceContext.current?.sourceId);
      final activeCtx = ShuyuanSourceContext.current;
      final target = book;
      // 书变量层同步：JS `book.getVariable` 读的是 ctx.bookVars 种子；
      // 与 Dart 书对象 variableMap 保持一致（覆盖换书残留）。
      if (activeCtx != null && target != null) {
        activeCtx.bookVars
          ..clear()
          ..addAll(target.variableMap);
      }
      // 种子顺序对齐 legado get 链：源变量 < 书变量 < 规则层变量 < 章节变量
      //（chapter 优先命中；规则层变量表里可能残留书种子，不能压过本章）。
      final seedJavaVars = <String, String>{
        ...?activeCtx?.sourceVars,
        ...?book?.variableMap,
        ..._variables,
        ...?chapter?.variableMap,
      };
      final bindings = <String, dynamic>{
        // `java` 对象由 java_extensions 预置脚本提供（引擎侧跳过同名绑定）；
        // 变量表经 __javaVars 种子注入（动态 java.get 可读），脚本内 java.put
        // 的写入在 eval 后由 takeJavaVars 排空回写（对齐 legado java.put/get
        // 跨规则段共享变量的语义）。
        'result': result,
        'baseUrl': baseUrl ?? '',
        'src': content?.toString() ?? '',
        'title': chapter?.title ?? '',
        // 对照 legado AnalyzeRule JS bindings：脚本可直接读 chapter.* /
        // nextChapterUrl（目录规则按章求值、正文规则拼下一章地址均依赖）。
        'chapter': _chapterSeed(chapter),
        'nextChapterUrl': nextChapterUrl ?? '',
        // 对照 legado AnalyzeRule bindings：小说源无 RSS 文章对象（md3 为
        // rssArticle=null），fromBookInfo 标记详情页求值（NexHub 不区分）。
        'rssArticle': null,
        'fromBookInfo': false,
        // 每轮都重置变量快照（不能因为当前为空就跳过）：引擎已按源池化，
        // 会跨书/跨章存活；若沿用上一轮的 __javaVars，`java.get` 会读到
        // 别的书的变量。
        '__javaVars': seedJavaVars,
        if (extraBindings != null) ...extraBindings,
      };
      // book 字段 → JS 种子：脚本里 `book.name/author/…` 读到的是当前书。
      if (activeCtx != null && target != null) {
        activeCtx.bookInfo
          ..['name'] = target.name
          ..['author'] = target.author
          ..['bookUrl'] = target.bookUrl
          ..['intro'] = target.intro ?? ''
          ..['kind'] = target.kind ?? ''
          ..['coverUrl'] = target.coverUrl ?? ''
          ..['lastChapter'] = target.lastChapter ?? ''
          ..['tocUrl'] = target.tocUrl ?? ''
          ..['wordCount'] = target.wordCount ?? ''
          ..['type'] = '${target.type}'
          ..['origin'] = activeCtx.bookSourceUrl;
      }
      final out = _evalJsWithRuleBridge(jsStr, bindings, structured: structured);
      final javaVars = _jsEngine!.takeJavaVars();
      // 只回写 JS 实际改动的键：__javaVars 同时是种子表，整表 put 会把
      // 章节/书/源变量灌进规则层变量表（后续 get 链顺序失真、跨阶段残留）。
      javaVars.forEach((k, v) {
        if (seedJavaVars[k] != v) put(k, v);
      });
      // JS 里直接改 `chapter.variableMap[...]`（legado 绑定的是 BookChapter
      // 实体）同样回写本章；java.put 已随 __javaVars 差量落盘，这里只补齐
      // 快照上的直改，避免脚本改完变量下一段规则读不到。
      final chapterVars = _jsEngine!.takeJavaChapterVars();
      final boundChapter = chapter;
      if (boundChapter != null) {
        chapterVars.forEach((k, v) {
          if (boundChapter.variableMap[k] != v) {
            boundChapter.putVariable(k, v);
          }
        });
      }
      // JS 里 `book.name = '…'` 等字段写入回写当前书（空值不覆盖——
      // 正文解析阶段 book 是空壳，避免把详情阶段已解析的字段抹掉）。
      if (activeCtx != null && target != null) {
        void apply(String key, void Function(String value) setter) {
          final value = activeCtx.bookInfo[key];
          if (value != null && value.isNotEmpty) setter(value);
        }

        apply('name', (v) => target.name = v);
        apply('author', (v) => target.author = v);
        apply('bookUrl', (v) => target.bookUrl = v);
        apply('intro', (v) => target.intro = v);
        apply('kind', (v) => target.kind = v);
        apply('coverUrl', (v) => target.coverUrl = v);
        apply('lastChapter', (v) => target.lastChapter = v);
        apply('tocUrl', (v) => target.tocUrl = v);
        apply('wordCount', (v) => target.wordCount = v);
      }
      // 注入对象 book 变量回写：JS 里 book.putVariable 的写入镜像到当前书
      // （variableMap），规则层 @get/{book.getVariable} 即可读到。
      if (activeCtx != null &&
          activeCtx.bookVars.isNotEmpty &&
          target != null) {
        activeCtx.bookVars.forEach((k, v) {
          if (k == '__variable') return;
          target.putVariable(k, v);
        });
      }
      return out;
    } catch (e) {
      // JS 引擎调用本身抛异常（极少见）时记录到运行日志，便于真机排查
      // 「书源 JS 规则不生效」。失败返回空串维持既有行为。
      final brief = jsStr.replaceAll('\n', ' ').trim();
      AppLog.instance.w('[书源JS] 调用异常: '
          '${brief.length > 120 ? '${brief.substring(0, 120)}…' : brief} → $e');
      return '';
    }
  }

  /// `@webjs:` 规则求值：后台 WebView 加载当前内容页、注入 `window.result`
  /// 后执行脚本，取脚本结果字符串。
  ///
  /// QuickJS 沙箱无法同步等待 WebView，沿用 java.webView 的确定性重放：
  /// 首轮登记待抓取并返回空串，宿主 settleWebview 抓到结果后整段规则重跑
  /// 即可命中 [ShuyuanSourceContext.webviewCache]。
  String _evalWebJs(String jsStr, dynamic result) {
    final ctx = ShuyuanSourceContext.current;
    if (ctx == null) return '';
    final html = content?.toString() ?? '';
    final url = baseUrl ?? '';
    final resultJson = _webJsResultJson(result);
    final key = _webJsCacheKey(html, url, jsStr, resultJson);
    final cached = ctx.webviewCache[key];
    if (cached != null) return cached;
    // 参数位与 settleWebview 对齐：
    // [html, url, js, delayMs, window.result, sourceRegex, overrideUrlRegex]
    ctx.webviewArgs[key] = <String>[html, url, jsStr, '0', resultJson, '', ''];
    if (!ctx.webviewPending.contains(key)) {
      ctx.webviewPending.add(key);
    }
    return '';
  }

  static String _webJsCacheKey(
      String html, String url, String js, String resultJson) {
    final sig = '$html\u0001$url\u0001$js\u0001$resultJson';
    return 'webjs:${sig.hashCode}:${sig.length}';
  }

  /// 对齐 legado `GSON.toJson(result)`：JS 内 `window.result` 读取的是
  /// 上一段规则的结果，字符串保持为 JSON 字符串（带引号）。
  static String _webJsResultJson(dynamic result) {
    if (result == null) return 'null';
    try {
      return jsonEncode(result);
    } catch (_) {
      try {
        return jsonEncode(result.toString());
      } catch (_) {
        return 'null';
      }
    }
  }

  /// legado getStringList WebJs：先按 JSON 字符串数组解析，失败返回 null
  /// 表示按原串继续处理。
  static List<String>? _parseWebJsStringList(String raw) {
    final t = raw.trim();
    if (!t.startsWith('[')) return null;
    try {
      final decoded = jsonDecode(t);
      if (decoded is! List) return null;
      return decoded.map((e) => e == null ? '' : e.toString()).toList();
    } catch (_) {
      return null;
    }
  }

  /// legado getElement WebJs：JSON 对象 → Map，失败 null。
  static Map<String, dynamic>? _parseWebJsElement(String raw) {
    try {
      final decoded = jsonDecode(raw.trim());
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  /// legado getElements WebJs：JSON 对象数组 → 元素列表，失败 null。
  static List<Map<String, dynamic>>? _parseWebJsElements(String raw) {
    final t = raw.trim();
    if (!t.startsWith('[')) return null;
    try {
      final decoded = jsonDecode(t);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  /// JS 内 `java.getString/getStringList/getElement(s)/setContent` 的重放求值。
  ///
  /// 对齐 legado：`java` 即 AnalyzeRule 本身，脚本可同步按规则取值。QuickJS
  /// 沙箱无法同步回宿主，故脚本先记待办（占位返回），宿主按调用顺序求值后
  /// 写回缓存重跑；依赖取值分支的脚本最多 [_jsRuleReplayRounds] 轮收敛。
  /// 每轮开始把内容恢复到脚本入口快照（脚本内 setContent 的切换只在 op
  /// 回放中生效），结束后保留最后一轮 setContent 的内容，与 legado 一致。
  dynamic _evalJsWithRuleBridge(String jsStr, Map<String, dynamic> bindings,
      {bool structured = false}) {
    final engine = _jsEngine!;
    final entryContent = content;
    final entryBaseUrl = baseUrl;
    final entryRedirect = redirectUrl;
    final entryJson = isJson;
    // 缓存按「本次求值的内容快照」有效，跨规则求值必须清空（引擎按源池化）。
    // 嵌套求值（桥回放中某条规则又触发 @js）不能清空外层缓存与根内容版本，
    // 否则外层待办键每轮都变，永远不收敛。
    final topLevel = _jsReplayDepth == 0;
    _jsReplayDepth++;
    try {
      if (topLevel) engine.resetRuleReplay();
      dynamic out;
      var pendingRounds = 0;
      for (var round = 0; round <= _jsRuleReplayRounds; round++) {
        if (round > 0) {
          content = entryContent;
          baseUrl = entryBaseUrl;
          redirectUrl = entryRedirect;
          isJson = entryJson;
          _analyzeByJsoup = null;
          _analyzeByXPath = null;
          _analyzeByJson = null;
        }
        engine.beginRuleRound();
        out = structured
            ? engine.evalStructured(jsStr, bindings: bindings)
            : engine.eval(jsStr, bindings: bindings);
        final ops = engine.takeRuleOps();
        if (ops.isEmpty) break;
        pendingRounds = round + 1;
        _applyJavaRuleOps(ops, engine);
      }
      if (pendingRounds > _jsRuleReplayRounds) {
        AppLog.instance.w('[书源JS] java 规则桥重放未收敛'
            '（>$_jsRuleReplayRounds 轮），结果可能不完整');
      }
      return out;
    } finally {
      _jsReplayDepth--;
    }
  }

  /// 规则桥重放嵌套深度（见 [_evalJsWithRuleBridge] 的 topLevel 说明）。
  int _jsReplayDepth = 0;

  static const int _jsRuleReplayRounds = 4;

  /// 顺序回放待办：set 切换当前内容；get 在宿主侧求值并写入 JS 缓存。
  /// get 的待办键（kind|isUrl|内容签名|规则）由预置脚本生成，原样回填。
  void _applyJavaRuleOps(List<Map<String, dynamic>> ops, JsEngine engine) {
    final fills = <String, String>{};
    for (final op in ops) {
      if (op['op'] == 'set') {
        final c = _jsRuleContentToDart(op['c']);
        if (c == null) continue;
        final b = op['b']?.toString() ?? '';
        setContent(c, b.isEmpty ? null : b);
        continue;
      }
      final key = op['key']?.toString() ?? '';
      if (key.isEmpty) continue;
      final kind = op['k']?.toString() ?? 's';
      final rule = op['r']?.toString() ?? '';
      final isUrl = op['u'] == 1;
      final mContent = _jsRuleContentToDart(op['c']);
      fills[key] = _resolveJavaRuleOp(kind, rule, mContent, isUrl);
    }
    if (fills.isNotEmpty) engine.fillRuleCache(fills);
  }

  /// JS 侧内容参数 → 宿主内容：字符串原样；元素包装取其内部 HTML
  /// （legado 持有 Element 本身；根元素自身属性选择器会丢失，见局限）；
  /// JSON 对象直接作为 JSON 内容求值。
  dynamic _jsRuleContentToDart(dynamic c) {
    if (c == null) return null;
    if (c is Map) {
      final v = c['v'];
      final k = c['k']?.toString();
      if (k == 'j') return v;
      return v?.toString() ?? '';
    }
    return c.toString();
  }

  /// 按 kind 求值：s=字符串、l=字符串列表、e=元素列表、g=首个元素。
  /// 结果统一序列化为 JS 缓存值（字符串/JSON 数组），由预置脚本还原类型。
  String _resolveJavaRuleOp(
      String kind, String rule, dynamic mContent, bool isUrl) {
    String run(dynamic Function() fn) {
      try {
        final value = fn();
        if (kind == 'l') {
          return jsonEncode(value is List ? value : const []);
        }
        if (kind == 'e') {
          return _elementsJsLiteral(value is List ? value : const []);
        }
        if (kind == 'g') {
          // CSS/XPath 的 single 求值仍返回元素集合（legado getElement 同），
          // JS 侧 getElement 语义取首个；正则单值（分组数组）不拆。
          var one = value;
          if (one is List && (one.isEmpty || one.first is Element)) {
            one = one.isEmpty ? null : one.first;
          }
          return _elementsJsLiteral(one == null ? const [] : [one]);
        }
        return value?.toString() ?? '';
      } catch (e) {
        AppLog.instance.w('[书源JS] java 规则桥求值失败: $rule → $e');
        return kind == 's' ? '' : '[]';
      }
    }

    if (kind == 's') {
      return run(() => getString(rule, isUrl: isUrl, mContent: mContent));
    }
    if (mContent == null) {
      if (kind == 'l') return run(() => getStringList(rule, isUrl: isUrl));
      if (kind == 'e') return run(() => getElements(rule));
      return run(() => getElement(rule));
    }
    final saved = content;
    final savedJson = isJson;
    final savedBase = baseUrl;
    setContent(mContent);
    try {
      if (kind == 'l') return run(() => getStringList(rule, isUrl: isUrl));
      if (kind == 'e') return run(() => getElements(rule));
      return run(() => getElement(rule));
    } finally {
      content = saved;
      isJson = savedJson;
      baseUrl = savedBase;
      _analyzeByJsoup = null;
      _analyzeByXPath = null;
      _analyzeByJson = null;
    }
  }

  String evalJs(String jsStr, dynamic result, {Map<String, dynamic>? extraBindings}) {
    return _evalJs(jsStr, result, extraBindings: extraBindings);
  }

  /// JS 绑定的 chapter 快照（legado 直接绑定 BookChapter 对象，脚本按
  /// `chapter.title/url/isVip…` 读取当前章节；这里按同名字段镜像）。
  Map<String, dynamic>? _chapterSeed(XiaoshuoBookChapter? ch) {
    if (ch == null) return null;
    final chBaseUrl = ch.baseUrl;
    return <String, dynamic>{
      'title': ch.title,
      'url': ch.url,
      'bookUrl': ch.bookUrl,
      // legado 绑定的是 BookChapter 实体，baseUrl 是章节自带字段；
      // 老数据缺失时退回当前解析页地址。
      'baseUrl': (chBaseUrl != null && chBaseUrl.isNotEmpty)
          ? chBaseUrl
          : (redirectUrl ?? baseUrl ?? ''),
      'index': ch.index,
      'tag': ch.tag ?? '',
      'isVolume': ch.isVolume,
      'isVip': ch.isVip,
      'isPay': ch.isPay,
      'variableMap': Map<String, String>.from(ch.variableMap),
    };
  }

  // ── 规则参数化求值（$N 分组 / {{...}} / @get:{...}）──

  /// 计算规则的生效状态：按参数段重建规则文本，再分割 `##` 正则替换段。
  ///
  /// 对齐 legado `SourceRule.makeUpRule`：分组参数从当前正则命中项的
  /// 分组数组取 `N` 号元素；内嵌表达式按规则/JS 求值；`@get:` 取变量。
  /// 不修改缓存的 [SourceRule]（跨元素复用），每次返回独立状态。
  _RuleState _makeUpRule(SourceRule sourceRule, dynamic result) {
    if (!sourceRule.hasParams) {
      return _RuleState(
        sourceRule.rule,
        sourceRule.replaceRegex,
        sourceRule.replacement,
        sourceRule.replaceFirst,
        sourceRule.templateMode,
      );
    }
    final buf = StringBuffer();
    for (final param in sourceRule.params) {
      final type = param.type;
      if (type > 0) {
        // legado：(result as? List)?.let { this[regType] } ?: 字面量
        if (result is List) {
          if (result.length > type) {
            buf.write(result[type]?.toString() ?? '');
          }
        } else {
          buf.write(param.text);
        }
      } else if (type == RuleParam.innerType) {
        final expr = param.text.trim();
        if (_isRuleExpr(expr)) {
          buf.write(getString(expr));
        } else {
          buf.write(_formatJsNumberText(_evalJs(expr, result)));
        }
      } else if (type == RuleParam.getType) {
        buf.write(get(param.text));
      } else {
        buf.write(param.text);
      }
    }
    final parts = buf.toString().split('##');
    return _RuleState(
      parts[0].trim(),
      parts.length > 1 ? parts[1] : '',
      parts.length > 2 ? parts[2] : '',
      parts.length > 3,
      false,
    );
  }

  /// 内嵌表达式是否为规则（而非 JS 表达式）。
  static bool _isRuleExpr(String expr) {
    return expr.startsWith('@') ||
        expr.startsWith('\$.') ||
        expr.startsWith('\$[') ||
        expr.startsWith('//');
  }

  /// JS 数值结果整型化：引擎把整数算式结果返回为 `19.0` 形式时去掉
  /// 小数位（URL 分页偏移等场景不能带 `.0`）。
  static String _formatJsNumberText(String s) {
    if (s.length > 2 && RegExp(r'^-?\d+\.0+$').hasMatch(s)) {
      return s.substring(0, s.indexOf('.'));
    }
    return s;
  }

  /// 节点 → JS 字面量：`{t:文本, h:内部HTML, ot:自身文本, a:属性表, o:外层HTML,
  /// u:页面地址, g:标签名, p:元素子序号路径, r:根序号}`，载荷为
  /// `{r:[根HTML...], els:[...]}`。由预置脚本的 `__javaElements` 包装成
  /// jsoup 风格对象：读取类方法直接取字面量，树遍历（parent/parents/
  /// siblings/next/prev/select/children）用「根 HTML + 路径」在沙箱内定位到
  /// 同一 jsoup DOM 节点（对应 legado 里 Rhino 直调 jsoup 的上下文语义）；
  /// 根 HTML 超体积上限时省略 r/p，遍历降级为空，其余读取不受影响。
  /// JSON 模式的元素额外带 `j`（原始对象）供字段直读。
  String _elementsJsLiteral(List<dynamic> elements) {
    final base = redirectUrl ?? baseUrl ?? '';
    final roots = <String>[];
    final rootIndex = <Element, int>{};
    final els = <Map<String, dynamic>>[];
    for (final e in elements) {
      if (e is Element) {
        final lit = <String, dynamic>{
          't': e.text.trim(),
          'h': e.innerHtml,
          'ot': e.nodes
              .whereType<Text>()
              .map((n) => n.text.trim())
              .where((s) => s.isNotEmpty)
              .join(' '),
          'a': <String, String>{
            for (final entry in e.attributes.entries)
              entry.key.toString(): entry.value,
          },
          'o': e.outerHtml,
          'u': base,
          'g': (e.localName ?? '').toLowerCase(),
        };
        final root = _elementRootPath(e);
        if (root != null) {
          final html = root.$1.outerHtml;
          if (html.length <= _jsElementRootMax) {
            final id = rootIndex.putIfAbsent(root.$1, () {
              roots.add(html);
              return roots.length - 1;
            });
            lit['r'] = id;
            lit['p'] = root.$2;
          }
        }
        els.add(lit);
      } else if (e is Map) {
        els.add(<String, dynamic>{'t': e.toString(), 'j': e});
      } else {
        els.add(<String, dynamic>{'t': e?.toString() ?? ''});
      }
    }
    return jsonEncode(<String, dynamic>{'r': roots, 'els': els});
  }

  /// 元素在文档中的元素子序号路径（文档根在前）。游离/片段树返回 null
  /// （沙箱侧无法用整页 HTML 复原其上下文）。
  (Element, List<int>)? _elementRootPath(Element e) {
    final path = <int>[];
    Element cur = e;
    while (true) {
      final parent = cur.parentNode;
      if (parent == null) return null;
      final idx = parent.children.indexOf(cur);
      if (idx < 0) return null;
      path.insert(0, idx);
      if (parent is Document) return (cur, path);
      if (parent is Element) {
        cur = parent;
        continue;
      }
      return null;
    }
  }

  /// 单个规则载荷附带的根 HTML 体积上限（字符）；超限不带 DOM 上下文。
  static const int _jsElementRootMax = 512 * 1024;

  String _replaceRegex(String result, _RuleState st) {
    if (st.replaceRegex.isEmpty) return result;
    // 大输入计时面包屑：catastrophic 回溯会让本同步调用无限阻塞主 isolate，
    // 起始行即卡点证据（完成行缺失 = 卡在本次替换）。
    final watch = result.length >= 20000 ? (Stopwatch()..start()) : null;
    if (watch != null) {
      AppLog.instance.i('[书源JS] 替换规则开始 输入=${result.length} '
          '规则=${st.replaceRegex.length}字符');
    }
    String finish(String out) {
      if (watch != null) {
        AppLog.instance.i('[书源JS] 替换规则完成 输出=${out.length} '
            '耗时=${watch.elapsedMilliseconds}ms');
      }
      return out;
    }

    try {
      // Java→Dart 正则兼容：`(?i)` 内联标志、\Q..\E、占有量词、\p{In…} 等。
      // 翻译不了的（如反向引用）保持原样，求值失败仍走既有 catch。
      final compat = RegexCompat.translate(st.replaceRegex);
      final regex = RegExp(
        compat.pattern,
        caseSensitive: compat.caseSensitive,
        dotAll: compat.dotAll,
        multiLine: compat.multiLine,
      );
      String expand(Match m) => _expandReplacement(m, st.replacement);
      if (st.replaceFirst) {
        // legado `##match##replace###`：只保留「首个匹配子串替换后」的结果，
        // 匹配之外的前后缀全部丢弃；无匹配则整条为空。此前按全串
        // replaceFirst 处理，合成封面/URL 规则会残留尾部（如 `...s.jpghtml`）。
        final m = regex.firstMatch(result);
        if (m == null) return finish('');
        return finish(expand(m));
      }
      return finish(result.replaceAllMapped(regex, expand));
    } catch (_) {
      try {
        if (st.replaceFirst) {
          // 与 legado 一致：正则编译失败时直接返回替换模板本身。
          final index = result.indexOf(st.replaceRegex);
          return finish(index >= 0 ? st.replacement : '');
        }
        return finish(result.replaceAll(st.replaceRegex, st.replacement));
      } catch (_) {
        return finish(result);
      }
    }
  }

  /// 展开 `##` 正则替换中的 `$1`..`$9` 分组引用（`$0` 为整串）。
  /// Dart 的字符串替换不展开 `$N`，须显式映射。
  static String _expandReplacement(Match m, String replacement) {
    if (!replacement.contains(r'$')) return replacement;
    return replacement.replaceAllMapped(RegExp(r'\$(\d)'), (rm) {
      final idx = int.parse(rm.group(1)!);
      if (idx == 0) return m.group(0) ?? '';
      if (idx <= m.groupCount) return m.group(idx) ?? '';
      return '';
    });
  }

  String _getAbsoluteUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return baseUrl ?? '';
    // legado `NetworkUtils.getAbsoluteURL(redirectUrl, str)`：相对地址固定
    // 按响应最终 URL 解析；redirectUrl 缺失时保持相对形态（不回落到
    // baseUrl，否则会把本应判空的结果拼成看似合法的地址）。
    // 请求被 302 到其他目录时，按请求 URL 解析会把分页/子页链接拼到旧
    // 路径 → 404，目录只出首页。
    return absoluteUrl(redirectUrl, trimmed);
  }

  /// 对照 legado `NetworkUtils.getAbsoluteURL(baseURL, relativePath)`：
  /// 绝对 URL / `data:` 原样返回、`javascript:` 归空，相对路径按 [base]
  /// 解析；[base] 为空时原样返回。
  ///
  /// URL 选项后缀 `,{...}`（method/body/headers 等）须原样保留：
  /// Uri.resolve 会把 `{`/`"` 百分号转义成 `%7B`/`%22`，AnalyzeUrl 识别不出
  /// 选项 → POST 退化为 GET → 空响应（百度小说等把目录/正文 POST 描述符
  /// 拼在 URL 里的 API 源，目录/正文恒为空）。
  static String absoluteUrl(String? base, String url) {
    final trimmed = url.trim();
    if (trimmed.startsWith('data:')) return trimmed;
    if (trimmed.startsWith('javascript')) return '';
    if (trimmed.startsWith('http')) return trimmed;
    if (base == null || base.isEmpty) return trimmed;
    var pathPart = trimmed;
    var optionPart = '';
    final optionMatch = RegExp(r',\s*\{').firstMatch(trimmed);
    if (optionMatch != null) {
      pathPart = trimmed.substring(0, optionMatch.start);
      optionPart = trimmed.substring(optionMatch.start);
    }
    try {
      final parsedBase = Uri.parse(base);
      return '${parsedBase.resolve(pathPart)}$optionPart';
    } catch (_) {
      return trimmed;
    }
  }

  /// HTML 实体还原，对齐 legado `StringEscapeUtils.unescapeHtml4`：
  /// 命名实体仅还原 Apache HTML4 全集（252 项，区分大小写、不含 apos），
  /// HTML5 专有实体 / 大小写变体原样保留；数字实体按 Apache 语义解析
  /// （允许 0 与代理区码点，非法码点 > 0x10FFFF 抛 [ArgumentError]，
  /// 超出 int32 的溢出值视为解析失败、原样保留）。
  static final RegExp _entityPattern =
      RegExp(r'&(?:#\d+|#[xX][0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);');

  static String unescapeHtml(String str) {
    if (!str.contains('&')) return str;
    return str.replaceAllMapped(_entityPattern, (m) {
      final entity = m.group(0)!;
      final body = entity.substring(1, entity.length - 1);
      if (body.startsWith('#')) {
        final hex = body.length > 1 && (body[1] == 'x' || body[1] == 'X');
        final digits = body.substring(hex ? 2 : 1);
        final code = int.tryParse(digits, radix: hex ? 16 : 10);
        if (code == null || code > 0x7FFFFFFF) return entity;
        if (code > 0x10FFFF) {
          throw ArgumentError('Invalid Unicode code point: $code');
        }
        return String.fromCharCode(code);
      }
      final codePoint = html4NamedEntities[body];
      return codePoint == null ? entity : String.fromCharCode(codePoint);
    });
  }

  String _unescapeHtml(String str) => unescapeHtml(str);

  bool _isJsonString(String str) {
    final trimmed = str.trim();
    return (trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'));
  }

  void _putAll(Map<String, String> map) {
    for (final entry in map.entries) {
      put(entry.key, getString(entry.value));
    }
  }
}

/// 规则求值期的生效状态：[SourceRule] 的规则串经内嵌表达式替换、
/// `##` 正则替换段分割后的最终形态。
class _RuleState {
  final String rule;
  final String replaceRegex;
  final String replacement;
  final bool replaceFirst;
  final bool templateMode;

  _RuleState(this.rule, this.replaceRegex, this.replacement, this.replaceFirst,
      this.templateMode);
}
