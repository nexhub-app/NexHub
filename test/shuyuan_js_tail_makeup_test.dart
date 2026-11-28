/// R3 对齐：`@js:代码##match##replace###` 的替换尾不再提前切分。
///
/// legado（AnalyzeRule.kt:553-562/720-779）把 `@js:` 整段（含替换尾）
/// 作为单个 Mode.Js 规则：尾部 `@get:{}`/`{{}}` 在本段 makeUpRule 阶段
/// 以前段结果为上下文展开后拼回整串，再拆 `##` 分出替换正则与替换文本；
/// JS 只对 `##` 前的脚本体求值，替换正则作用于 JS 输出。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_rule.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('尾参 @get:{x} 在 makeUp 阶段展开并落入替换文本', () {
    final ar = AnalyzeRule()..setContent('<div>c</div>', 'https://x.com/');
    ar.put('x', r'$1!');
    // 脚本体 'abc' 求值 → "abc"；替换正则 `(a)`、替换文本 = x 的展开值 `$1!`
    // → 分组 1 = 'a' → 'a!bc'。
    final out = ar.getString(r"@js:'abc'##(a)##@get:{x}");
    expect(out, r'a!bc');
  });

  test('未赋值的尾参 @get:{x} 展开为空串', () {
    final ar = AnalyzeRule()..setContent('<div>c</div>', 'https://x.com/');
    expect(ar.getString(r"@js:'abc'##(a)##@get:{x}"), 'bc');
  });

  test('尾参 {{\$.field}} 按前段内容展开（非 JS 输出）', () {
    final ar = AnalyzeRule()..setContent('{"name":"N"}', 'https://x.com/');
    // 旧实现把尾拆成独立规则段、以 JS 输出（'q'）为上下文求值 {{$.name}}
    // → 空串；legado 里尾参展开发生在 JS 执行前、上下文是前段内容。
    final out = ar.getString("@js:'q'##q##{{" r'$.name' '}}');
    expect(out, 'N');
  });

  test('无参替换尾的端到端结果不变', () {
    final ar = AnalyzeRule()..setContent('<div>c</div>', 'https://x.com/');
    expect(ar.getString("@js:'abc'##b##B"), 'aBc');
    // `###` 只保留首个匹配替换后的子串（既有 replaceFirst 语义）。
    expect(ar.getString("@js:'abc'##b##B###"), 'B');
  });

  test('空脚本体 + 替换尾保持「对前段结果直接替换」超集语义', () {
    // legado 中空 JS 段产出 null；社区源高频写法是 `@js:##match##replace`
    // 表示对前段结果做正则替换，此处按既有超集保留。
    final ar = AnalyzeRule()..setContent('a1b2', 'https://x.com/');
    expect(ar.getString(r'@js:##\d##X'), 'aXbX');
  });

  test('非参化 JS 段的列表规则仍按脚本体进入求值', () {
    final ar = AnalyzeRule()
      ..setContent('<li>1</li><li>2</li>', 'https://x.com/');
    // JS 转义 \n：脚本体返回 "a\nb"，替换后 "A\nb"，按行拆分。
    final out = ar.getStringList(r"@js:'a\nb'##a##A");
    expect(out, ['A', 'b']);
  });
}
