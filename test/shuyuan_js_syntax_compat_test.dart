/// Rhino 兼容改写与 jsLib 解析兜底的回归测试。
///
/// Legado 用 Rhino 解析书源脚本，Rhino 接受 E4X 后代访问（`a..b`）以及
/// 宽松的 `let/const` 参数重定义；QuickJS 会整段解析失败导致 jsLib 全部
/// 失效。引擎在**原始脚本解析失败时**才按词法安全地改写，正常脚本零改动。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/java_extensions.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/js_syntax_compat.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('adaptLegacyJs', () {
    test('参数重定义的 let/const 改为 var', () {
      expect(
        adaptLegacyJs('function f(bu){ let bu = 1; return bu; }'),
        'function f(bu){ var bu = 1; return bu; }',
      );
      expect(
        adaptLegacyJs('function g(o){ const o = 2; return o; }'),
        'function g(o){ var o = 2; return o; }',
      );
      // 属性名/字符串里的 let/const 不是关键字，不能改。
      expect(adaptLegacyJs('a.let + b.const'), 'a.let + b.const');
      expect(adaptLegacyJs('x = "let const"'), 'x = "let const"');
    });

    test('E4X 后代访问 a..b 改写为 a.b', () {
      expect(adaptLegacyJs('return data..item_null.text'),
          'return data.item_null.text');
      expect(adaptLegacyJs('x[0]..name'), 'x[0].name');
      // 展开运算符不受影响。
      expect(adaptLegacyJs('h(...args)'), 'h(...args)');
      expect(adaptLegacyJs('const a = [...xs, ...ys];'),
          'var a = [...xs, ...ys];');
      // 可选链/普通成员访问不受影响。
      expect(adaptLegacyJs('a?.b.c'), 'a?.b.c');
    });

    test('字符串/模板/注释/正则内容保持原样', () {
      const src = '''
let s = 'a..b let';
let t = "c..d const";
let u = `e..f \${ok..name}`;
// g..h let
/* i..j const */
let re = /k..l/g;
''';
      final out = adaptLegacyJs(src);
      expect(out, contains("'a..b let'"));
      expect(out, contains('"c..d const"'));
      expect(out, contains('`e..f '));
      expect(out, contains('ok.name')); // 模板插值内部是代码
      expect(out, contains('// g..h let'));
      expect(out, contains('/* i..j const */'));
      expect(out, contains('/k..l/g'));
    });

    test('无 Rhino 语法的脚本原样返回', () {
      const src = 'function f(a){ var b = a; return b; }';
      expect(adaptLegacyJs(src), src);
    });
  });

  group('Rhino 语法失败识别', () {
    test('鸿蒙原生桥无 <eval> 定位的报错也进入兼容改写', () {
      // 鸿蒙 QuickJS 桥只回纯错误文本（无堆栈定位）；这是真机 jsLib
      // 整段失效的根因：旧判据要求 `<eval>:`，兜底改写从未触发。
      expect(
        isLegacySyntaxFailure(
            'SyntaxError: invalid redefinition of parameter name'),
        isTrue,
      );
      expect(isLegacySyntaxFailure('SyntaxError: expecting field name'), isTrue);
      // flutter_js 带定位的报错保持原判据兼容。
      expect(
        isLegacySyntaxFailure('SyntaxError: <eval>:12: invalid ...'),
        isTrue,
      );
    });

    test('运行期错误不触发兼容改写', () {
      expect(isLegacySyntaxFailure('TypeError: must be called with new'),
          isFalse);
      expect(
        isLegacySyntaxFailure("ReferenceError: 'sourceHelper' is not defined"),
        isFalse,
      );
      expect(
        isLegacySyntaxFailure("SyntaxError: unexpected token: '__AJAX_1__'"),
        isFalse,
      );
    });
  });

  group('JsEngine jsLib 解析兜底', () {
    setUp(() {
      HttpOverrides.global = null;
      JsEngine.resetPoolForTest();
      JavaFeedback.onLog = null;
      JavaFeedback.onToast = null;
    });

    test('含 Rhino 语法的 jsLib 解析失败后自动改写并全局可见', () async {
      final ctx = await ShuyuanSourceContext.forSource('compat-jslib-test');
      ctx.jsLib = '''
function legacyProbe(){ var o = {name: 'ok'}; return o..name; }
function shadowProbe(x){ let x = 2; return x; }
const libConst = 7;
''';
      await ShuyuanSourceContext.run(ctx, () async {
        final engine = JsEngine.forSource('compat-jslib-test');
        expect(engine.eval('legacyProbe()'), 'ok');
        expect(engine.eval('shadowProbe(1)'), '2');
        expect(engine.eval('libConst + 1'), '8');
      });
    });

    test('正常 jsLib 不被改写（严格语义保留）', () async {
      final ctx = await ShuyuanSourceContext.forSource('compat-jslib-ok');
      ctx.jsLib = 'function plainProbe(){ return "plain"; }';
      await ShuyuanSourceContext.run(ctx, () async {
        final engine = JsEngine.forSource('compat-jslib-ok');
        expect(engine.eval('plainProbe()'), 'plain');
      });
    });
  });
}
