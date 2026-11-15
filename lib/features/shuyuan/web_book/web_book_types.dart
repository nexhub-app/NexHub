/// WebBook 公共类型：发现分类、发现结果、正文结果、URL 条目，以及多级 URL 解析。
library;

import 'dart:convert';

import '../../../core/models/novel_block.dart';
import '../analyze/js_engine.dart';
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

String _executeExploreJs(String jsCode) {
  // 引擎优先：动态分类脚本常依赖 java.ajax / 源变量 / jsLib 现算 URL，
  // 正则启发式只能捞到脚本里写死的字面量（还会把占位符当 URL）。
  // 引擎不可用（未打包 QuickJS）或脚本无返回值时才用启发式兜底。
  final engineResult = _executeExploreJsInEngine(jsCode);
  if (engineResult.isNotEmpty) {
    return engineResult;
  }
  return _parseExploreJsByRegex(jsCode);
}

String _executeExploreJsInEngine(String jsCode) {
  JsEngine? jsEngine;
  try {
    jsEngine = JsEngine();
    // 与 legado `evalJS(jsStr).toString()` 对齐：先取脚本自身的完成值
    // （末尾表达式的值），无值再退回 `result` 变量。脚本以字符串返回时
    // 原样使用（常见写法 `JSON.stringify(list)`），否则序列化为 JSON。
    final wrapped = '(function () {\n'
        '  var __v = eval(${jsonEncode(jsCode)});\n'
        '  if (__v === undefined || __v === null) {\n'
        '    __v = (typeof result !== "undefined") ? result : "";\n'
        '  }\n'
        '  if (typeof __v === "string") return __v;\n'
        '  return JSON.stringify(__v);\n'
        '})()';
    final jsResult = jsEngine.eval(wrapped);
    if (jsResult.isNotEmpty && jsResult != '[]') {
      final trimmed = jsResult.trim();
      // 只接受「像分类数据」的返回值：JSON 数组或含 `名称::URL` 的多行文本。
      // 脚本末尾的标量（赋值表达式完成值，如 `个人中心 = 1` → "1"）不是
      // 分类，直接丢弃让启发式兜底，避免生成 url="1" 的假 Tab。
      if (trimmed.startsWith('[') || trimmed.contains('::')) {
        return _parseJsResult(jsResult);
      }
    }
    return '';
  } catch (_) {
    return '';
  } finally {
    jsEngine?.dispose();
  }
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
