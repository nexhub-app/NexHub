/// @js: 脚本体内嵌表达式展开测试（P1-1）。
///
/// 对齐 legado makeUpRule 语义：@js: 脚本体里的 {{$.xxx}} / {{@get}} 等
/// 规则形态内嵌在脚本执行【前】由规则引擎对当前上下文求值（实测来源：
/// 全免小说类签名源 `t="appid=..&bid={{$.sourceId}}.."` + java.md5Encode
/// 签名，此前字面量直传导致服务端拒签）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:nexhub/features/shuyuan/analyze/analyze_rule.dart';

void main() {
  // flutter_js 运行时创建需经 rootBundle 加载扩展资产；真 QuickJS 另需
  // PATH 含 pub cache flutter_js/windows/shared（测试环境约定）。
  TestWidgetsFlutterBinding.ensureInitialized();
  test('@js: 脚本体 {{\$.sourceId}} 执行前按规则展开并参与签名', () {
    const item = '{"sourceId":"abc123","title":"书名"}';
    final ar = AnalyzeRule()..setContent(item, 'https://x.com/');
    const jsRule = '@js:\n'
        't="appid=qm&bid={{\$.sourceId}}&t=1";\n'
        'sign=java.md5Encode(t);\n'
        '"u?" + sign;';
    final out = ar.getString(jsRule);
    final expectedT = 'appid=qm&bid=abc123&t=1';
    final expectedSign =
        crypto.md5.convert(utf8.encode(expectedT)).toString();
    expect(out, 'u?$expectedSign');
  });

  test('js 脚本必须执行而非被模板模式劫持为字面量', () {
    const item = '{"sourceId":"s1"}';
    final ar = AnalyzeRule()..setContent(item, 'https://x.com/');
    // 含 {{}} 的脚本：输出应是计算结果，不是脚本文本本身。
    final out = ar.getString('@js:\nt="bid={{\$.sourceId}}";\nt.length;');
    // "bid=s1".length == 6
    expect(out, '6');
  });

  test('{{key}}/{{page}} 类非规则内嵌仍走 JS 求值', () {
    const item = '{"a":1}';
    final ar = AnalyzeRule()..setContent(item, 'https://x.com/');
    final out = ar.getString('@js:"page=" + {{1+2}};');
    expect(out, 'page=3');
  });

  test('无内嵌表达式的 @js: 行为不变', () {
    const item = '{"a":1}';
    final ar = AnalyzeRule()..setContent(item, 'https://x.com/');
    expect(ar.getString('@js:"plain"'), 'plain');
  });
}
