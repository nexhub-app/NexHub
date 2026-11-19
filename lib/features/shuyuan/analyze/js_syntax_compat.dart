/// Rhino 书源脚本 → 标准 JS 的**兜底**语法兼容改写。
///
/// Legado 用 Rhino（含 E4X 扩展）求值书源脚本，部分公开书源利用了
/// Rhino 才接受的写法：
/// - E4X 后代访问 `data..item`（QuickJS 报 `expecting field name`）；
/// - 函数体内 `let/const` 重定义同名参数（Rhino 宽松放行，QuickJS 报
///   `invalid redefinition of parameter name`）。
///
/// 这些写法会让整段 jsLib 在 QuickJS 里解析失败、库函数全部不可见。
/// 本改写只在**原始脚本解析失败后**由引擎调用，正常脚本零改动。
/// 改写按词法状态进行：字符串 / 模板文本 / 注释 / 正则字面量一律原样
/// 保留，只处理代码位置的 `a..b` 与 `let/const`。
library;

const _regexPrefixChars = '([{,;:=!&|?+-*%^~<>';

const _regexPrefixWords = {
  'return',
  'typeof',
  'case',
  'in',
  'of',
  'new',
  'delete',
  'void',
  'instanceof',
  'do',
  'else',
  'yield',
  'await',
};

bool _isIdentChar(int c) =>
    (c >= 0x30 && c <= 0x39) || // 0-9
    (c >= 0x41 && c <= 0x5A) || // A-Z
    (c >= 0x61 && c <= 0x7A) || // a-z
    c == 0x5F || // _
    c == 0x24; // $

bool _isIdentStart(int c) =>
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A) ||
    c == 0x5F ||
    c == 0x24;

/// 把 Rhino 专有写法改写为标准 JS；无可改写内容时原样返回同一字符串。
String adaptLegacyJs(String source) {
  final n = source.length;
  final out = StringBuffer();
  var i = 0;
  var changed = false;

  // 代码/模板两种词法模式；模板插值 `${` 会临时回到代码模式。
  var inTemplate = false;
  var braceDepth = 0;
  final interpBraceStack = <int>[];

  // 上一个有效记号：''（脚本开头）、标识符用 'id'、标点用其字符。
  // 仅用于判定 `/` 是正则字面量还是除号。
  var lastTok = '';
  var lastWord = '';

  while (i < n) {
    final ch = source[i];

    if (inTemplate) {
      if (ch == '\\') {
        final end = i + 2 <= n ? i + 2 : n;
        out.write(source.substring(i, end));
        i = end;
        continue;
      }
      if (ch == '`') {
        out.write(ch);
        i++;
        inTemplate = false;
        lastTok = 'id';
        lastWord = '';
        continue;
      }
      if (ch == r'$' && i + 1 < n && source[i + 1] == '{') {
        out.write(r'${');
        i += 2;
        inTemplate = false;
        interpBraceStack.add(braceDepth);
        braceDepth = 0;
        lastTok = '{';
        lastWord = '';
        continue;
      }
      out.write(ch);
      i++;
      continue;
    }

    // 注释
    if (ch == '/' && i + 1 < n && source[i + 1] == '/') {
      final j = source.indexOf('\n', i);
      final end = j < 0 ? n : j;
      out.write(source.substring(i, end));
      i = end;
      continue;
    }
    if (ch == '/' && i + 1 < n && source[i + 1] == '*') {
      final j = source.indexOf('*/', i + 2);
      final end = j < 0 ? n : j + 2;
      out.write(source.substring(i, end));
      i = end;
      continue;
    }

    // 正则字面量（按前一记号启发式判定）
    if (ch == '/') {
      final prevAllowsRegex = lastTok.isEmpty ||
          (lastTok.length == 1 && _regexPrefixChars.contains(lastTok)) ||
          (lastTok == 'id' && _regexPrefixWords.contains(lastWord));
      if (prevAllowsRegex) {
        var j = i + 1;
        var inClass = false;
        while (j < n) {
          final c = source[j];
          if (c == '\\') {
            j += 2;
            continue;
          }
          if (c == '[') {
            inClass = true;
          } else if (c == ']') {
            inClass = false;
          } else if (c == '/' && !inClass) {
            j++;
            break;
          } else if (c == '\n') {
            break;
          }
          j++;
        }
        while (j < n && _isIdentChar(source.codeUnitAt(j))) {
          j++;
        }
        out.write(source.substring(i, j));
        i = j;
        lastTok = 'id';
        lastWord = '';
        continue;
      }
    }

    // 字符串
    if (ch == '"' || ch == "'") {
      var j = i + 1;
      while (j < n) {
        final c = source[j];
        if (c == '\\') {
          j += 2;
          continue;
        }
        j++;
        if (c == ch) break;
      }
      if (j > n) j = n;
      out.write(source.substring(i, j));
      i = j;
      lastTok = 'id';
      lastWord = '';
      continue;
    }

    if (ch == '`') {
      out.write(ch);
      i++;
      inTemplate = true;
      continue;
    }

    // E4X 后代访问：`a..b` → `a.b`（`...` 展开符保持）
    if (ch == '.') {
      if (i + 2 < n && source[i + 1] == '.' && source[i + 2] == '.') {
        out.write('...');
        i += 3;
        lastTok = '.';
        lastWord = '';
        continue;
      }
      final memberLike =
          lastTok == 'id' || lastTok == ')' || lastTok == ']' || lastTok == '}';
      if (i + 2 < n &&
          source[i + 1] == '.' &&
          memberLike &&
          _isIdentStart(source.codeUnitAt(i + 2))) {
        out.write('.');
        i += 2;
        changed = true;
        lastTok = '.';
        lastWord = '';
        continue;
      }
    }

    // 花括号（含模板插值收尾）
    if (ch == '{') {
      braceDepth++;
      out.write(ch);
      i++;
      lastTok = '{';
      lastWord = '';
      continue;
    }
    if (ch == '}') {
      if (braceDepth > 0) braceDepth--;
      if (braceDepth == 0 && interpBraceStack.isNotEmpty) {
        braceDepth = interpBraceStack.removeLast();
        out.write(ch);
        i++;
        inTemplate = true;
        continue;
      }
      out.write(ch);
      i++;
      lastTok = '}';
      lastWord = '';
      continue;
    }

    // 标识符/关键字
    if (_isIdentStart(source.codeUnitAt(i))) {
      var j = i + 1;
      while (j < n && _isIdentChar(source.codeUnitAt(j))) {
        j++;
      }
      var word = source.substring(i, j);
      // 属性名位置（`a.let`）保留原样；作为关键字声明时改写。
      if ((word == 'let' || word == 'const') && lastTok != '.') {
        word = 'var';
        changed = true;
      }
      out.write(word);
      i = j;
      lastTok = 'id';
      lastWord = word;
      continue;
    }

    // 数字（只为记号判定）
    if (ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39) {
      var j = i + 1;
      while (j < n && _isIdentChar(source.codeUnitAt(j))) {
        j++;
      }
      out.write(source.substring(i, j));
      i = j;
      lastTok = 'id';
      lastWord = '';
      continue;
    }

    if (ch.trim().isEmpty) {
      out.write(ch);
      i++;
      continue;
    }

    out.write(ch);
    i++;
    lastTok = ch;
    lastWord = '';
  }

  return changed ? out.toString() : source;
}
