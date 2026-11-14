/// 规则引擎门面：按规则模式（CSS/XPath/JSON/JS/正则）分派到对应解析器，
/// 支持 `##` 正则替换、`@put` 变量、`<js>`/`@js:` 内嵌脚本与 `&&/||/%%` 复合规则。
library;

import 'dart:convert';

import 'package:html/dom.dart';
import '../../../core/utils/app_log.dart';
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

  AnalyzeByJsoup? _analyzeByJsoup;
  AnalyzeByXPath? _analyzeByXPath;
  AnalyzeByJson? _analyzeByJson;
  JsEngine? _jsEngine;

  final Map<String, String> _variables = {};
  final Map<String, List<SourceRule>> _stringRuleCache = {};

  AnalyzeRule({this.book, this.chapter});

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
    _variables[key] = value;
    if (key == 'title' && chapter != null) {
      chapter!.title = value;
    }
  }

  String get(String key) {
    switch (key) {
      case 'bookName':
        return book?.name ?? '';
      case 'title':
        return chapter?.title ?? '';
      default:
        return _variables[key] ?? book?.getVariable(key) ?? chapter?.getVariable(key) ?? '';
    }
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
        final st = _makeUpRule(sourceRule, result);
        if (st.rule.isNotEmpty) {
          result = _executeRuleElements(result, sourceRule, single: true);
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

    if (allInOne && ruleStr.startsWith(': ')) {
      mMode = Mode.regex;
      start = 1;
    }

    // 不再预分割 &&，让 AnalyzeByJsoup 内部处理 &&/||/%%
    final trimmed = ruleStr.substring(start).trim();
    if (trimmed.isEmpty) return [];

    // 处理 JS 模式
    final jsPattern = RegExp(r'<js>([\w\W]*?)</js>|@js:([\w\W]*)', caseSensitive: false);
    final matches = jsPattern.allMatches(trimmed).toList();

    if (matches.isEmpty) {
      ruleList.add(SourceRule(trimmed, mMode, isJson));
    } else {
      var segStart = 0;
      for (final match in matches) {
        if (match.start > segStart) {
          final tmp = trimmed.substring(segStart, match.start).trim();
          if (tmp.isNotEmpty) {
            ruleList.add(SourceRule(tmp, mMode, isJson));
          }
        }
        final jsContent = match.group(2) ?? match.group(1) ?? '';
        ruleList.add(SourceRule(jsContent, Mode.js, isJson));
        segStart = match.end;
      }
      if (trimmed.length > segStart) {
        final tmp = trimmed.substring(segStart).trim();
        if (tmp.isNotEmpty) {
          ruleList.add(SourceRule(tmp, mMode, isJson));
        }
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
          } else {
            result = _executeRule(result, sourceRule.mode, st.rule, isUrl: isUrl);
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
    if (result is String) {
      return result.split('\n').where((s) => s.isNotEmpty).toList();
    }
    if (result is List) {
      return result.map((e) => e.toString()).toList();
    }
    return [result.toString()];
  }

  List<dynamic> _getElementsFromRules(List<SourceRule> ruleList) {
    if (ruleList.isEmpty) return [];
    var result = content;

    for (final sourceRule in ruleList) {
      _putAll(sourceRule.putMap);
      result = _executeRuleElements(result, sourceRule);
      if (result == null) continue;
    }

    if (result == null) return [];
    if (result is List) return result;
    return [];
  }

  dynamic _executeRule(dynamic result, Mode mode, String rule, {bool isUrl = false}) {
    switch (mode) {
      case Mode.js:
        return _evalJs(rule, result);
      case Mode.regex:
        return rule;
      case Mode.json:
        final analyzer = _getJsonAnalyzer(result);
        return analyzer.getString(rule);
      case Mode.xpath:
        final analyzer = _getXPathAnalyzer(result);
        return analyzer.getString(rule);
      case Mode.defaultMode:
        final analyzer = _getJsoupAnalyzer(result);
        if (isUrl) {
          return analyzer.getString0(rule);
        }
        return analyzer.getString(rule);
    }
  }

  dynamic _executeRuleElements(dynamic result, SourceRule sourceRule, {bool single = false}) {
    final st = _makeUpRule(sourceRule, result);
    final rule = st.rule;

    switch (sourceRule.mode) {
      case Mode.js:
        final jsResult = _evalJs(rule, result);
        if (jsResult is List) return jsResult;
        return [];
      case Mode.regex:
        if (result is String) {
          return AnalyzeByRegex.getElements(result, rule);
        }
        return [];
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

  String _evalJs(String jsStr, dynamic result, {Map<String, dynamic>? extraBindings}) {
    try {
      // 按源复用引擎：同一书源的列表/详情/目录/正文共用一套运行时与
      // jsLib 全局，避免逐章重建 QuickJS。无活动上下文（如离线单测）
      // 时退化为独立实例。
      _jsEngine ??= JsEngine.forSource(
          ShuyuanSourceContext.current?.sourceId);
      final bindings = <String, dynamic>{
        // `java` 对象由 java_extensions 预置脚本提供（引擎侧跳过同名绑定）；
        // 变量表经 __javaVars 种子注入（动态 java.get 可读），脚本内 java.put
        // 的写入在 eval 后由 takeJavaVars 排空回写（对齐 legado java.put/get
        // 跨规则段共享变量的语义；字面量参数仍走 _expandJavaBridge 宿主内联）。
        'result': result,
        'baseUrl': baseUrl ?? '',
        'src': content?.toString() ?? '',
        'title': chapter?.title ?? '',
        // 每轮都重置变量快照（不能因为当前为空就跳过）：引擎已按源池化，
        // 会跨书/跨章存活；若沿用上一轮的 __javaVars，`java.get` 会读到
        // 别的书的变量。put 的写回仍经 takeJavaVars → put 进 _variables。
        '__javaVars': Map<String, String>.from(_variables),
        if (extraBindings != null) ...extraBindings,
      };
      final activeCtx = ShuyuanSourceContext.current;
      final target = book;
      // book 字段 → JS 种子：脚本里 `book.name/author/…` 读到的是当前书。
      if (activeCtx != null && target != null) {
        activeCtx.bookInfo
          ..['name'] = target.name
          ..['author'] = target.author
          ..['bookUrl'] = target.bookUrl
          ..['intro'] = target.intro ?? ''
          ..['kind'] = target.kind ?? ''
          ..['coverUrl'] = target.coverUrl ?? ''
          ..['lastChapter'] = target.lastChapter ?? '';
      }
      final out = _jsEngine!.eval(_expandJavaBridge(jsStr), bindings: bindings);
      final javaVars = _jsEngine!.takeJavaVars();
      javaVars.forEach(put);
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

  String evalJs(String jsStr, dynamic result, {Map<String, dynamic>? extraBindings}) {
    return _evalJs(jsStr, result, extraBindings: extraBindings);
  }

  // ── 内嵌表达式（{{...}} / @get:{...}）求值期替换 ──

  /// 内嵌表达式与变量引用的切分模式（对齐通用书源格式语义）。
  static final RegExp _evalPattern = RegExp(
    r'@get:\{[^}]+?\}|\{\{[\w\W]*?\}\}',
    caseSensitive: false,
  );

  /// 计算规则的生效状态：替换 `{{...}}` 内嵌表达式与 `@get:{...}` 变量
  /// 引用后，再分割 `##` 正则替换段。
  ///
  /// 不修改缓存的 [SourceRule]（规则列表按规则串缓存、跨元素复用），
  /// 每次求值返回独立的生效状态。
  _RuleState _makeUpRule(SourceRule sourceRule, dynamic result) {
    if (!sourceRule.hasInnerRule) {
      return _RuleState(
        sourceRule.rule,
        sourceRule.replaceRegex,
        sourceRule.replacement,
        sourceRule.replaceFirst,
        sourceRule.templateMode,
      );
    }
    if (sourceRule.mode == Mode.js) {
      // js 脚本体：仅展开内嵌表达式（{{$.x}}/@ 内嵌走规则引擎对当前上下文
      // 求值，{{key}}/{{page}} 等走 JS），展开后的脚本体交回执行；不做 ##
      // 分割（脚本体无正则替换后缀语义）、无模板模式（脚本必须执行）。
      final replacedJs = _replaceInnerRules(sourceRule.rawRule, result);
      return _RuleState(replacedJs, '', '', false, false);
    }
    final replaced = _replaceInnerRules(sourceRule.rawRule, result);
    final parts = replaced.split('##');
    return _RuleState(
      parts[0].trim(),
      parts.length > 1 ? parts[1] : '',
      parts.length > 2 ? parts[2] : '',
      parts.length > 3,
      sourceRule.templateMode,
    );
  }

  /// 替换规则串中的全部内嵌表达式：
  /// - `@get:{key}` → 变量取值；
  /// - `{{规则}}`（`@`/`$.`/`$[`/`//` 开头）→ 按规则对当前内容求值；
  /// - `{{JS 表达式}}` → JS 求值（绑定 result/baseUrl 等宿主上下文）。
  String _replaceInnerRules(String ruleStr, dynamic result) {
    return ruleStr.replaceAllMapped(_evalPattern, (m) {
      final token = m.group(0)!;
      if (token.length > 6 &&
          token.substring(0, 5).toLowerCase() == '@get:') {
        final key = token.substring(6, token.length - 1);
        return get(key);
      }
      final expr = token.substring(2, token.length - 2).trim();
      if (_isRuleExpr(expr)) {
        return getString(expr);
      }
      return _formatJsNumberText(_evalJs(expr, result));
    });
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

  // ── 宿主桥接调用展开 ──

  static final RegExp _javaGetStringSingle =
      RegExp(r"java\.getString\(\s*'([^']*)'\s*\)");
  static final RegExp _javaGetStringDouble =
      RegExp(r'java\.getString\(\s*"([^"]*)"\s*\)');
  static final RegExp _javaGetStringListSingle =
      RegExp(r"java\.getStringList\(\s*'([^']*)'\s*\)");
  static final RegExp _javaGetStringListDouble =
      RegExp(r'java\.getStringList\(\s*"([^"]*)"\s*\)');
  static final RegExp _javaGetElementsSingle =
      RegExp(r"java\.getElements\(\s*'([^']*)'\s*\)");
  static final RegExp _javaGetElementsDouble =
      RegExp(r'java\.getElements\(\s*"([^"]*)"\s*\)');
  static final RegExp _javaGetElementSingle =
      RegExp(r"java\.getElement\(\s*'([^']*)'\s*\)");
  static final RegExp _javaGetElementDouble =
      RegExp(r'java\.getElement\(\s*"([^"]*)"\s*\)');

  /// 节点 → JS 字面量：`{t:文本, h:内部HTML, ot:自身文本, a:属性表}`。
  /// 由预置脚本的 `__javaElements` 包装成 jsoup 风格对象（size/get/text/
  /// html/attr）；JSON 模式的元素额外带 `j`（原始对象）供字段直读。
  String _elementsJsLiteral(List<dynamic> elements) {
    final out = <Map<String, dynamic>>[];
    for (final e in elements) {
      if (e is Element) {
        out.add(<String, dynamic>{
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
        });
      } else if (e is Map) {
        out.add(<String, dynamic>{'t': e.toString(), 'j': e});
      } else {
        out.add(<String, dynamic>{'t': e?.toString() ?? ''});
      }
    }
    return jsonEncode(out);
  }

  /// 宿主桥接调用展开：`java.getString/getStringList/getElements/getElement`
  /// 需要「按规则求值」，JS 沙箱内无法同步回调宿主，故在求值前内联为结果。
  ///
  /// 注意：**不要**在此内联 `java.get(...)`。运行时已提供 `java.get`
  /// （变量读取 + 单参 URL GET + 双参 HTTP 重载），宿主内联只会抢在它前面
  /// 把 `java.get('https://…')` 替换成空串（旧实现即因此让 API 源的
  /// `java.get(url).body()` 全部返回空）。
  ///
  /// 仅支持**字面量**规则（单/双引号无转义）；动态规则（变量拼出来的串）
  /// 仍会落到运行时缺失函数 → TypeError → 该段返回空（可被日志定位）。
  String _expandJavaBridge(String jsExpr) {
    if (!jsExpr.contains('java.')) return jsExpr;
    var out = jsExpr;
    // 长名优先：getStringList / getElements / getElement 先于 getString 处理，
    // 避免前缀被短规则截断（当前正则带 `\(`，其实不会误匹配，仍保持顺序）。
    out = out.replaceAllMapped(
        _javaGetStringListSingle, (m) => jsonEncode(getStringList(m.group(1) ?? '')));
    out = out.replaceAllMapped(
        _javaGetStringListDouble, (m) => jsonEncode(getStringList(m.group(1) ?? '')));
    out = out.replaceAllMapped(
        _javaGetElementsSingle,
        (m) => '__javaElements(${_elementsJsLiteral(getElements(m.group(1) ?? ''))})');
    out = out.replaceAllMapped(
        _javaGetElementsDouble,
        (m) => '__javaElements(${_elementsJsLiteral(getElements(m.group(1) ?? ''))})');
    out = out.replaceAllMapped(
        _javaGetElementSingle,
        (m) =>
            '(__javaElements(${_elementsJsLiteral(getElements(m.group(1) ?? ''))})[0] || null)');
    out = out.replaceAllMapped(
        _javaGetElementDouble,
        (m) =>
            '(__javaElements(${_elementsJsLiteral(getElements(m.group(1) ?? ''))})[0] || null)');
    out = out.replaceAllMapped(
        _javaGetStringSingle, (m) => jsonEncode(getString(m.group(1) ?? '')));
    out = out.replaceAllMapped(
        _javaGetStringDouble, (m) => jsonEncode(getString(m.group(1) ?? '')));
    return out;
  }

  String _replaceRegex(String result, _RuleState st) {
    if (st.replaceRegex.isEmpty) return result;
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
        return result.replaceFirstMapped(regex, expand);
      }
      return result.replaceAllMapped(regex, expand);
    } catch (_) {
      try {
        if (st.replaceFirst) {
          final index = result.indexOf(st.replaceRegex);
          if (index >= 0) {
            return result.substring(0, index) +
                st.replacement +
                result.substring(index + st.replaceRegex.length);
          }
          return '';
        }
        return result.replaceAll(st.replaceRegex, st.replacement);
      } catch (_) {
        return result;
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
    if (url.isEmpty) return baseUrl ?? '';
    if (url.startsWith('http')) return url;
    if (baseUrl == null || baseUrl!.isEmpty) return url;
    try {
      final base = Uri.parse(baseUrl!);
      return base.resolve(url).toString();
    } catch (_) {
      return url;
    }
  }

  String _unescapeHtml(String str) {
    return str
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');
  }

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
