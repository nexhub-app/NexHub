/// WebBook 公共类型：发现分类、发现结果、正文结果、URL 条目，以及多级 URL 解析。
library;

import 'dart:convert';

import '../../../core/models/explore_kind.dart';
import '../../../core/models/novel_block.dart';
import '../analyze/js_engine.dart';
import '../analyze/source_context.dart';
import '../model/xiaoshuo_book.dart';

/// 发现分类。
class ExploreCategory {
  final String name;
  final String url;

  ExploreCategory({required this.name, required this.url});
}

/// 发现结果（书籍列表 + 子分类）。
class ExploreResult {
  final List<XiaoshuoBook> books;
  final List<ExploreCategory> subCategories;

  ExploreResult({required this.books, required this.subCategories});
}

/// 章节正文结果。
class BookContentResult {
  /// 兼容字段：纯文本拼接（旧消费方可能仍读取）。新链路使用 [blocks]。
  final String content;

  /// 图文块列表：文本段与插图按原顺序共存，供阅读器图文混排。
  final List<NovelBlock> blocks;

  final String? error;

  BookContentResult({
    this.content = '',
    this.blocks = const [],
    this.error,
  });
}

/// URL 条目（名称 + URL）。
class UrlEntry {
  final String name;
  final String url;

  UrlEntry({required this.name, required this.url});
}

/// 解析多级 URL 字符串（发现页配置）。
///
/// 支持格式：
/// - `分类名::URL`（以 `::` 分隔名称与 URL，多行/`&&` 分隔多条）
/// - 纯 URL
/// - `@js:` / `<js>...</js>` JavaScript 表达式（返回多级 URL 字符串）
List<UrlEntry> parseMultiLevelUrls(String multiLineUrl) {
  final entries = <UrlEntry>[];
  final trimmedInput = multiLineUrl.trim();

  final isJsExpression = trimmedInput.startsWith('@js:') ||
      (trimmedInput.startsWith('<js>') && trimmedInput.contains('</js>'));

  if (isJsExpression) {
    String jsCode;
    if (trimmedInput.startsWith('@js:')) {
      jsCode = trimmedInput.substring(4);
    } else {
      final startIdx = trimmedInput.indexOf('<js>') + 4;
      final endIdx = trimmedInput.lastIndexOf('</js>');
      jsCode = trimmedInput.substring(startIdx, endIdx);
    }

    final jsResult = _executeExploreJs(jsCode);

    if (jsResult.isNotEmpty) {
      return parseMultiLevelUrls(jsResult);
    }
    return entries;
  }

  final segments = trimmedInput.split(RegExp(r'&&|\n'));

  for (final segment in segments) {
    var trimmed = segment.trim();
    if (trimmed.isEmpty) continue;

    if ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
        (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
      trimmed = trimmed.substring(1, trimmed.length - 1).trim();
    }

    if (trimmed.isEmpty) continue;

    final segIsJs = trimmed.startsWith('@js:') ||
        (trimmed.startsWith('<js>') && trimmed.contains('</js>'));
    if (segIsJs) {
      String jsCode;
      if (trimmed.startsWith('@js:')) {
        jsCode = trimmed.substring(4);
      } else {
        final startIdx = trimmed.indexOf('<js>') + 4;
        final endIdx = trimmed.lastIndexOf('</js>');
        jsCode = trimmed.substring(startIdx, endIdx);
      }
      final jsResult = _executeExploreJs(jsCode);
      if (jsResult.isNotEmpty) {
        entries.addAll(parseMultiLevelUrls(jsResult));
      }
      continue;
    }

    String name = '';
    String url = trimmed;

    final colonColonMatch = trimmed.indexOf('::');
    if (colonColonMatch >= 0) {
      name = trimmed.substring(0, colonColonMatch).trim();
      url = trimmed.substring(colonColonMatch + 2).trim();
    }

    final backtickMatch = RegExp(r'`([^`]+)`').firstMatch(url);
    if (backtickMatch != null) {
      url = backtickMatch.group(1)!.trim();
    }

    final quoteMatch = RegExp(r'''["']([^"']+)["']''').firstMatch(url);
    if (quoteMatch != null) {
      final extracted = quoteMatch.group(1)!.trim();
      if (extracted.startsWith('http') ||
          extracted.startsWith('/') ||
          extracted.contains('.')) {
        url = extracted;
      }
    }

    url = url.replaceAll(RegExp(r'[,;]+$'), '').trim();

    if (url.isNotEmpty) {
      entries.add(UrlEntry(name: name, url: url));
    }
  }

  return entries;
}

String _executeExploreJs(String jsCode, {Map<String, String>? infoMap}) {
  // 引擎优先：动态分类脚本常依赖 java.ajax / 源变量 / jsLib 现算 URL，
  // 正则启发式只能捞到脚本里写死的字面量（还会把占位符当 URL）。
  // 引擎不可用（未打包 QuickJS）或脚本无返回值时才用启发式兜底。
  final jsRaw = _evalExploreJsRaw(jsCode, infoMap: infoMap);
  if (jsRaw.isNotEmpty && jsRaw != '[]') {
    // 只接受「像分类数据」的返回值：JSON 数组或含 `名称::URL` 的多行文本。
    // 脚本末尾的标量（赋值表达式完成值，如 `个人中心 = 1` → "1"）不是
    // 分类，直接丢弃让启发式兜底，避免生成 url="1" 的假 Tab。
    if (_looksLikeKinds(jsRaw)) return _parseJsResult(jsRaw);
  }
  final fallback = _parseExploreJsByRegex(jsCode);
  if (fallback.isNotEmpty) return fallback;
  return '';
}

bool _looksLikeKinds(String s) {
  final t = s.trim();
  return t.startsWith('[') || t.contains('::');
}

/// 执行 exploreUrl 的 JS 片段，返回脚本原始结果（JSON 数组原样保留）。
///
/// 与 legado `evalJS(jsStr).toString()` 对齐：先取脚本自身的完成值
/// （末尾表达式的值），无值再退回 `result` 变量。脚本以字符串返回时
/// 原样使用（常见写法 `JSON.stringify(list)`），否则序列化为 JSON。
String _evalExploreJsRaw(String jsCode, {Map<String, String>? infoMap}) {
  final ctx = ShuyuanSourceContext.current;
  final jsEngine = JsEngine.forSource(ctx?.sourceId);
  try {
    final wrapped = '(function () {\n'
        '  var __v = eval(${jsonEncode(_applyRhinoSyntaxCompat(jsCode))});\n'
        '  if (__v === undefined || __v === null) {\n'
        '    __v = (typeof result !== "undefined") ? result : "";\n'
        '  }\n'
        '  if (typeof __v === "string") return __v;\n'
        '  return JSON.stringify(__v);\n'
        '})()';
    final bindings = infoMap == null
        ? null
        : <String, dynamic>{'infoMap': Map<String, String>.from(infoMap)};
    return jsEngine.eval(wrapped, bindings: bindings).trim();
  } catch (_) {
    return '';
  } finally {
    // 池化引擎按源复用（保留 __ajaxCache / 预置脚本）；无上下文时独立实例。
    if (ctx == null) jsEngine.dispose();
  }
}

/// 兼容 legado Rhino 引擎接受、但标准 JS（QuickJS）拒绝的两种写法：
///
/// 1. 不带括号的箭头参数解构：`.map([a,b] => ...)` → `.map(([a,b]) => ...)`；
/// 2. 无分号 ASI：函数表达式 / 箭头赋值块 `}` 后换行接 `[`（数组字面量语
///    句）时按 Rhino 语义断句补 `;`——否则标准 JS 会把 `[` 解析成函数对象
///    的下标访问，得到 `undefined.map(...)`。
///
/// 字符串 / 模板文本 / 注释 / 正则字面量内的内容原样保留。
String _applyRhinoSyntaxCompat(String src) {
  if (!src.contains('[')) return src;
  final ranges = _protectedJsRanges(src);
  final bracePairs = _jsBracePairs(src, ranges);
  final out = StringBuffer();
  var i = 0;
  var r = 0;
  while (i < src.length) {
    while (r < ranges.length && ranges[r].$2 <= i) {
      r++;
    }
    if (r < ranges.length && i == ranges[r].$1) {
      out.write(src.substring(ranges[r].$1, ranges[r].$2));
      i = ranges[r].$2;
      continue;
    }
    if (src[i] == '[') {
      final end = _skipBalancedJs(src, i);
      if (end > i) {
        var j = end;
        while (j < src.length && _isJsSpace(src[j])) {
          j++;
        }
        if (j + 1 < src.length && src[j] == '=' && src[j + 1] == '>') {
          out.write('(');
          out.write(src.substring(i, end));
          out.write(')');
          i = end;
          continue;
        }
      }
    } else if (src[i] == '}') {
      final open = bracePairs[i];
      if (open != null && _isFunctionBodyBrace(src, open)) {
        var j = i + 1;
        var sawNewline = false;
        while (j < src.length && _isJsSpace(src[j])) {
          if (src[j] == '\n') sawNewline = true;
          j++;
        }
        if (sawNewline && j < src.length && src[j] == '[') {
          out.write('};');
          i++;
          continue;
        }
      }
    }
    out.write(src[i]);
    i++;
  }
  return out.toString();
}

/// 代码区（跳过字符串/注释/正则）内的花括号配对：`}` 下标 → `{` 下标。
Map<int, int> _jsBracePairs(String src, List<(int, int)> ranges) {
  final pairs = <int, int>{};
  final stack = <int>[];
  var i = 0;
  var r = 0;
  while (i < src.length) {
    while (r < ranges.length && ranges[r].$2 <= i) {
      r++;
    }
    if (r < ranges.length && i == ranges[r].$1) {
      i = ranges[r].$2;
      continue;
    }
    if (src[i] == '{') {
      stack.add(i);
    } else if (src[i] == '}' && stack.isNotEmpty) {
      pairs[i] = stack.removeLast();
    }
    i++;
  }
  return pairs;
}

/// `{` 是否为函数体（箭头函数体或 `function(...) {`），用于 ASI 断句判断。
bool _isFunctionBodyBrace(String src, int openPos) {
  final from = openPos > 300 ? openPos - 300 : 0;
  final prefix = src.substring(from, openPos);
  if (RegExp(r'=>\s*$').hasMatch(prefix)) return true;
  return RegExp(r'function\b[^(){}]*\([^(){}]*\)\s*$').hasMatch(prefix);
}

bool _isJsSpace(String c) =>
    c == ' ' || c == '\t' || c == '\r' || c == '\n';

/// 字符串 / 模板 / 注释 / 正则字面量的区间（左闭右开），供改写器跳过。
List<(int, int)> _protectedJsRanges(String src) {
  final ranges = <(int, int)>[];
  var i = 0;
  while (i < src.length) {
    final c = src[i];
    int? end;
    if (c == "'" || c == '"') {
      end = _skipQuotedJs(src, i);
    } else if (c == '`') {
      end = _skipTemplateJs(src, i);
    } else if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      final nl = src.indexOf('\n', i);
      end = nl < 0 ? src.length : nl;
    } else if (c == '/' && i + 1 < src.length && src[i + 1] == '*') {
      final close = src.indexOf('*/', i + 2);
      end = close < 0 ? src.length : close + 2;
    } else if (c == '/' && _jsRegexAllowedAt(src, i)) {
      end = _skipRegexJs(src, i);
    }
    if (end != null && end > i) {
      ranges.add((i, end));
      i = end;
    } else {
      i++;
    }
  }
  return ranges;
}

int _skipQuotedJs(String src, int start) {
  final quote = src[start];
  var i = start + 1;
  while (i < src.length) {
    final c = src[i];
    if (c == '\\') {
      i += 2;
    } else if (c == quote) {
      return i + 1;
    } else {
      i++;
    }
  }
  return src.length;
}

int _skipTemplateJs(String src, int start) {
  var i = start + 1;
  while (i < src.length) {
    final c = src[i];
    if (c == '\\') {
      i += 2;
    } else if (c == '`') {
      return i + 1;
    } else if (c == r'$' && i + 1 < src.length && src[i + 1] == '{') {
      final end = _skipBalancedJs(src, i + 1);
      i = end > i ? end : i + 2;
    } else {
      i++;
    }
  }
  return src.length;
}

/// 跳过配对括号，返回闭括号后的下标（未闭合或参数非法时返回 -1）。
int _skipBalancedJs(String src, int openIndex) {
  const pairs = {'[': ']', '(': ')', '{': '}'};
  final open = src[openIndex];
  final close = pairs[open];
  if (close == null) return -1;
  var depth = 1;
  var i = openIndex + 1;
  while (i < src.length) {
    final c = src[i];
    if (c == "'" || c == '"') {
      i = _skipQuotedJs(src, i);
    } else if (c == '`') {
      i = _skipTemplateJs(src, i);
    } else if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      final nl = src.indexOf('\n', i);
      i = nl < 0 ? src.length : nl;
    } else if (c == '/' && i + 1 < src.length && src[i + 1] == '*') {
      final end = src.indexOf('*/', i + 2);
      i = end < 0 ? src.length : end + 2;
    } else if (c == open) {
      depth++;
      i++;
    } else if (c == close) {
      depth--;
      i++;
      if (depth == 0) return i;
    } else {
      i++;
    }
  }
  return -1;
}

bool _jsRegexAllowedAt(String src, int slashIndex) {
  var k = slashIndex - 1;
  while (k >= 0 && _isJsSpace(src[k])) {
    k--;
  }
  if (k < 0) return true;
  final c = src[k];
  if ('=(:,;[!&|?{}+-*%<>~^'.contains(c)) return true;
  final isIdentChar = RegExp(r'[A-Za-z0-9_$]').hasMatch(c);
  if (!isIdentChar) return false;
  var w = k;
  while (w >= 0 && RegExp(r'[A-Za-z0-9_$]').hasMatch(src[w])) {
    w--;
  }
  const keywords = {
    'return', 'typeof', 'instanceof', 'in', 'of', 'new', 'delete', //
    'void', 'case', 'do', 'else', 'yield', 'await',
  };
  return keywords.contains(src.substring(w + 1, k + 1));
}

int _skipRegexJs(String src, int start) {
  var i = start + 1;
  var inClass = false;
  while (i < src.length) {
    final c = src[i];
    if (c == '\\') {
      i += 2;
    } else if (c == '[') {
      inClass = true;
      i++;
    } else if (c == ']') {
      inClass = false;
      i++;
    } else if (c == '/' && !inClass) {
      i++;
      while (i < src.length && RegExp(r'[a-zA-Z]').hasMatch(src[i])) {
        i++;
      }
      return i;
    } else if (c == '\n') {
      return i;
    } else {
      i++;
    }
  }
  return src.length;
}

/// 提取整串 exploreUrl 的 JS 体（`@js:` 前缀 / `<js>...</js>` 包裹）。
String? _extractWholeJsBody(String s) {
  if (s.startsWith('@js:')) return s.substring(4);
  if (s.startsWith('<js>') && s.contains('</js>')) {
    final start = s.indexOf('<js>') + 4;
    final end = s.lastIndexOf('</js>');
    if (end > start) return s.substring(start, end);
  }
  return null;
}

/// 解析 exploreUrl 为完整选项列表（legado BookSource.exploreKinds 等效）。
///
/// 支持形态：
/// - 整串 `@js:` / `<js>`：脚本返回 JSON 数组或 `名称::URL` 多行文本；
/// - JSON 数组：保留 type/action/chars/default/viewName/style 全部字段；
/// - 文本：`名称::URL` 以 `&&` / 换行分隔（可混入分段 JS）。
///
/// JS 求值时以 [infoMap] 作为全局绑定（toggle/select 当前值可参与 URL
/// 拼装）。JSON 声明非法时抛出 [FormatException]，由调用方展示为错误项。
List<ExploreKind> parseExploreKinds(
  String exploreUrl, {
  Map<String, String>? infoMap,
}) {
  var ruleStr = exploreUrl.trim();
  if (ruleStr.isEmpty) return const <ExploreKind>[];
  final jsBody = _extractWholeJsBody(ruleStr);
  if (jsBody != null) {
    final raw = _evalExploreJsRaw(jsBody, infoMap: infoMap);
    if (raw.isEmpty || raw == '[]') return const <ExploreKind>[];
    ruleStr = raw.trim();
  }
  if (ruleStr.startsWith('[')) {
    return _parseKindsJson(ruleStr);
  }
  return _parseKindsText(ruleStr, infoMap: infoMap);
}

List<ExploreKind> _parseKindsJson(String raw) {
  try {
    final decoded = jsonDecode(_repairJsonRawNewlines(raw));
    if (decoded is! List) {
      throw const FormatException('exploreUrl JSON 不是数组');
    }
    return <ExploreKind>[
      for (final e in decoded)
        if (e is Map) ExploreKind.fromJson(Map<String, dynamic>.from(e)),
    ];
  } on FormatException {
    rethrow;
  } catch (e) {
    throw FormatException('exploreUrl JSON 解析失败: $e');
  }
}

List<ExploreKind> _parseKindsText(
  String raw, {
  Map<String, String>? infoMap,
}) {
  final kinds = <ExploreKind>[];
  for (final segment in raw.split(RegExp(r'&&|\n'))) {
    var trimmed = segment.trim();
    if (trimmed.isEmpty) continue;
    if ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
        (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
      trimmed = trimmed.substring(1, trimmed.length - 1).trim();
    }
    if (trimmed.isEmpty) continue;

    final segJs = _extractWholeJsBody(trimmed);
    if (segJs != null) {
      final segResult = _evalExploreJsRaw(segJs, infoMap: infoMap);
      if (segResult.isNotEmpty) {
        kinds.addAll(parseExploreKinds(segResult, infoMap: infoMap));
      }
      continue;
    }

    String name = '';
    String url = trimmed;
    final colonColon = trimmed.indexOf('::');
    if (colonColon >= 0) {
      name = trimmed.substring(0, colonColon).trim();
      url = trimmed.substring(colonColon + 2).trim();
    }

    final backtickMatch = RegExp(r'`([^`]+)`').firstMatch(url);
    if (backtickMatch != null) url = backtickMatch.group(1)!.trim();

    final quoteMatch = RegExp(r'''["']([^"']+)["']''').firstMatch(url);
    if (quoteMatch != null) {
      final extracted = quoteMatch.group(1)!.trim();
      if (extracted.startsWith('http') ||
          extracted.startsWith('/') ||
          extracted.contains('.')) {
        url = extracted;
      }
    }
    url = url.replaceAll(RegExp(r'[,;]+$'), '').trim();
    if (url.isEmpty && name.isEmpty) continue;
    kinds.add(ExploreKind(
      title: name.isEmpty ? url : name,
      url: url.isEmpty ? null : url,
    ));
  }
  return kinds;
}

/// 修复 JSON 字符串里的裸换行（书源 JSON 常见：字符串值直接断行）。
String _repairJsonRawNewlines(String s) {
  final out = StringBuffer();
  var inString = false;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == '"') {
      // 统计前缀反斜杠数：偶数为真实字符串边界，奇数为转义引号。
      var bs = 0;
      var j = i - 1;
      while (j >= 0 && s[j] == '\\') {
        bs++;
        j--;
      }
      if (bs.isEven) inString = !inString;
      out.write(c);
    } else if (inString && (c == '\n' || c == '\r')) {
      out.write(c == '\n' ? r'\n' : r'\r');
    } else {
      out.write(c);
    }
  }
  return out.toString();
}

String _parseExploreJsByRegex(String jsCode) {
  final entries = <String>[];
  final seen = <String>{};

  final jsonPattern = RegExp(r'\[\s*\{');
  if (jsonPattern.hasMatch(jsCode)) {
    final objPattern = RegExp(
        "\\{\\s*[\"'](?:title|name)[\"']\\s*:\\s*[\"']([^\"']+)[\"']\\s*,\\s*[\"']url[\"']\\s*:\\s*[\"']([^\"']+)[\"']");
    for (final match in objPattern.allMatches(jsCode)) {
      final title = match.group(1) ?? '';
      final url = match.group(2) ?? '';
      if (title.isNotEmpty && url.isNotEmpty && !_isCodeKeyword(title)) {
        final entry = '$title::$url';
        if (!seen.contains(entry)) {
          seen.add(entry);
          entries.add(entry);
        }
      }
    }
    final objPatternReverse = RegExp(
        "\\{\\s*[\"']url[\"']\\s*:\\s*[\"']([^\"']+)[\"']\\s*,\\s*[\"'](?:title|name)[\"']\\s*:\\s*[\"']([^\"']+)[\"']");
    for (final match in objPatternReverse.allMatches(jsCode)) {
      final url = match.group(1) ?? '';
      final title = match.group(2) ?? '';
      if (title.isNotEmpty && url.isNotEmpty && !_isCodeKeyword(title)) {
        final entry = '$title::$url';
        if (!seen.contains(entry)) {
          seen.add(entry);
          entries.add(entry);
        }
      }
    }
  }

  if (entries.isNotEmpty) {
    return entries.join('\n');
  }

  final pairPattern = RegExp(r"""['\"]([^'\"]{2,})['\"]\s*,\s*['\"]([^'\"]+)['\"]""");

  for (final match in pairPattern.allMatches(jsCode)) {
    final first = match.group(1) ?? '';
    final second = match.group(2) ?? '';

    if (!second.startsWith('/')) {
      continue;
    }

    if (_isCodeKeyword(first)) {
      continue;
    }
    if (first.contains('[') || first.contains(']')) {
      continue;
    }

    final entry = '$first::$second';
    if (!seen.contains(entry)) {
      seen.add(entry);
      entries.add(entry);
    }
  }

  if (entries.isNotEmpty) {
    return entries.join('\n');
  }

  final pushPattern = RegExp(r"""push\s*\(\s*['\"]([^'\"]+)['\"]\s*,\s*['\"]([^'\"]+)['\"]""");
  for (final match in pushPattern.allMatches(jsCode)) {
    final title = match.group(1) ?? '';
    final url = match.group(2) ?? '';
    if (title.isNotEmpty && url.isNotEmpty && !_isCodeKeyword(title)) {
      final entry = '$title::$url';
      if (!seen.contains(entry)) {
        seen.add(entry);
        entries.add(entry);
      }
    }
  }

  if (entries.isNotEmpty) {
    return entries.join('\n');
  }

  final varPattern = RegExp(r'(?:var|let|const)\s+\w+\s*=\s*(\[)');
  for (final match in varPattern.allMatches(jsCode)) {
    final startBracket = match.start + match.group(0)!.length - 1;
    int depth = 0;
    int endBracket = -1;
    for (int j = startBracket; j < jsCode.length; j++) {
      if (jsCode[j] == '[') depth++;
      if (jsCode[j] == ']') {
        depth--;
        if (depth == 0) {
          endBracket = j;
          break;
        }
      }
    }
    if (endBracket > startBracket) {
      final arrayContent = jsCode.substring(startBracket + 1, endBracket);
      final pairPattern = RegExp(r"""['\"]([^'\"]{2,})['\"]\s*,\s*['\"]([^'\"]+)['\"]""");
      for (final pairMatch in pairPattern.allMatches(arrayContent)) {
        final first = pairMatch.group(1) ?? '';
        final second = pairMatch.group(2) ?? '';
        if (second.startsWith('/') && !_isCodeKeyword(first)) {
          final entry = '$first::$second';
          if (!seen.contains(entry)) {
            seen.add(entry);
            entries.add(entry);
          }
        }
      }
    }
  }

  if (entries.isNotEmpty) {
    return entries.join('\n');
  }

  return '';
}

bool _isCodeKeyword(String s) {
  const keywords = [
    'function', 'var ', 'let ', 'const ', 'push', 'result',
    'return', 'typeof', 'undefined', 'JSON', 'String',
    'Number', 'Boolean', 'Array', 'Object', 'this', 'new',
    'if', 'else', 'for', 'while', 'do', 'switch', 'case',
    'try', 'catch', 'finally', 'throw', 'class', 'extends',
    'import', 'export', 'default', 'async', 'await',
  ];
  final lower = s.toLowerCase();
  for (final keyword in keywords) {
    if (lower.contains(keyword.toLowerCase())) return true;
  }
  return false;
}

String _parseJsResult(String jsonStr) {
  try {
    final entries = <String>[];

    final trimmed = jsonStr.trim();
    if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) {
      return jsonStr;
    }

    final arrayContent = trimmed.substring(1, trimmed.length - 1).trim();
    if (arrayContent.isEmpty) return '';

    final objectPattern = RegExp(r'\{[^{}]*\}');
    final matches = objectPattern.allMatches(arrayContent);

    for (final match in matches) {
      final objStr = match.group(0)!;
      final titleMatch = RegExp(r'"title"\s*:\s*"([^"]*)"').firstMatch(objStr);
      final urlMatch = RegExp(r'"url"\s*:\s*"([^"]*)"').firstMatch(objStr);

      if (titleMatch != null && urlMatch != null) {
        final title = titleMatch.group(1) ?? '';
        final url = urlMatch.group(1) ?? '';
        if (url.isNotEmpty) {
          entries.add('$title::$url');
        }
      }
    }

    return entries.join('\n');
  } catch (_) {
    return jsonStr;
  }
}
