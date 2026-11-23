/// P2-2 引擎小件测试：replaceRegex 多形态。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/web_book/book_content.dart';

void main() {
  // flutter_js 运行时创建需经 rootBundle 加载扩展资产（见测试环境约定）。
  TestWidgetsFlutterBinding.ensureInitialized();
  group('replaceRegex 多形态', () {
    test('单条 pattern##replacement', () {
      final out = BookContent.applyReplaceRules(
          '第一章 aaa\n第二章 bbb', r'aaa##AAA');
      expect(out, contains('AAA'));
      expect(out, isNot(contains('aaa')));
    });

    test('多行多规则依序应用', () {
      final out = BookContent.applyReplaceRules(
        'AAA\nBBB\nCCC',
        'AAA##XX\nBBB##YY',
      );
      expect(out, 'XX\nYY\nCCC');
    });

    test('replacement 含 ## 不被误分割', () {
      final out = BookContent.applyReplaceRules('x=y', 'x##y##z');
      // parts.sublist(1).join('##') → replacement = 'y##z'
      expect(out, 'y##z=y'); // 仅替换 x，'=y' 尾巴保留
    });

    test('legado 形态 `##regex[##replacement]`（空选择器整串替换）', () {
      // md3：replaceRegex 行按 `##` 拆分，[0] 选择器为空 → 正文原样作为
      // 替换目标；[1] 是正则，[2] 是替换文本（缺省为空串）。
      expect(BookContent.applyReplaceRules('abc danger x', '##danger'), 'abc  x');
      expect(BookContent.applyReplaceRules('a1b22c', r'##\d+##数'), 'a数b数c');
    });

    test('空 pattern 行跳过（防 RegExp(\'\') 撑爆正文）', () {
      final out = BookContent.applyReplaceRules('abc', '##');
      expect(out, 'abc');
    });

    test('@js: 净化脚本（result=正文）', () {
      final out = BookContent.applyReplaceRules(
        'Hello World',
        "@js:\nresult.replace('World', 'QuickJS');",
      );
      expect(out, 'Hello QuickJS');
    });
  });
}
