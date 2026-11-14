// Java→Dart 正则兼容层的独立校验脚本（无需 Flutter，直接 dart 运行）：
//   E:/flutter/bin/cache/dart-sdk/bin/dart.exe tool/regex_check.dart
// 纯 dart:core/dart:io，不依赖包解析。
import 'dart:io' show exitCode;

import '../lib/features/shuyuan/analyze/regex_compat.dart';

void main() {
  var failed = 0;
  var total = 0;

  void eq(
    String input,
    String expectPattern, {
    bool cs = true,
    bool da = false,
    bool ml = false,
  }) {
    total++;
    final r = RegexCompat.translate(input);
    final pass = r.pattern == expectPattern &&
        r.caseSensitive == cs &&
        r.dotAll == da &&
        r.multiLine == ml;
    if (!pass) failed++;
    print('${pass ? "OK  " : "FAIL"} $input');
    if (!pass) {
      print('      got  pattern=${r.pattern} cs=${r.caseSensitive} '
          'da=${r.dotAll} ml=${r.multiLine}');
      print('      want pattern=$expectPattern cs=$cs da=$da ml=$ml');
    }
  }

  // 内联标志（仅开头）
  eq(r'(?i)笔奇部', '笔奇部', cs: false);
  eq(r'(?s)a.*b', 'a.*b', da: true);
  eq(r'(?im)x', 'x', cs: false, ml: true);
  eq(r'(?ismxu)y', 'y', cs: false, da: true, ml: true);
  eq(r'abc(?i)def', 'abc(?i)def'); // 中途标志不处理，保持原样
  eq(r'(?<name>x)', r'(?<name>x)'); // 命名分组不是标志，不误吞

  // \Q...\E
  eq(r'\Qa+b(c)\E', r'a\+b\(c\)');
  eq(r'\Q1.5\E-\Q2\E', r'1\.5-2'); // - 在类外不是特殊字符，不转义
  eq(r'x\Q[\E', r'x\[');

  // 占有量词 → 贪婪
  eq(r'[0-9]++', '[0-9]+');
  eq(r'\}++', r'\}+');
  eq(r'a*+', 'a*');
  eq(r'(a)?+', '(a)?');
  eq(r'a{2,3}++', 'a{2,3}+');
  eq(r'a+b', 'a+b'); // 普通 + 不受影响

  // 原子分组
  eq(r'(?>ab)c', '(?:ab)c');

  // \p{In…} / \p{Is…} / \p{Han}
  eq(r'[\p{InCJKUnifiedIdeographs}]', r'[\u4e00-\u9fff]');
  eq(r'\p{IsCJKUnifiedIdeographs}+', r'\u4e00-\u9fff+');
  eq(r'(?i)\p{Han}', r'\u4e00-\u9fff', cs: false);
  eq(r'\p{Unknown}', r'\p{Unknown}'); // 未收录保持原样

  // 无法翻译的保持原样（求值期报错，与旧行为一致）
  eq(r'(a)\1', r'(a)\1');

  // 功能验证：翻译后真的能编译并匹配（every：样例全部应命中）
  final cases = <String, List<String>>{
    r'(?i)笔奇部': ['笔奇部', '笔奇部ABC'],
    r'[\p{InCJKUnifiedIdeographs}]+': ['中文abc', '你好'],
    r'\Q1.5\E': ['1.5'],
    r'[0-9]++': ['123', 'abc456'],
  };
  for (final e in cases.entries) {
    total++;
    final r = RegexCompat.translate(e.key);
    final re = RegExp(
      r.pattern,
      caseSensitive: r.caseSensitive,
      dotAll: r.dotAll,
      multiLine: r.multiLine,
    );
    final pass = e.value.every((s) => re.hasMatch(s));
    if (!pass) failed++;
    print('${pass ? "OK  " : "FAIL"} 编译+匹配 ${e.key}');
  }

  print(failed == 0 ? 'ALL PASS ($total)' : 'FAILED $failed/$total');
  if (failed > 0) exitCode = 1;
}
