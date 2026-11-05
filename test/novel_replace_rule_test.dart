/// 替换（正文净化）规则回归测试。
///
/// 覆盖：全局规则命中、仅本书/仅本源的范围过滤、作用位置过滤、
/// 关闭的规则不生效、纯文本规则按字面替换。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/novel/novel_replace_rule.dart';

NovelReplaceRule _rule({
  String pattern = '',
  String replacement = '',
  String scope = 'content',
  String applyTo = 'all',
  String applyToValue = '',
  bool isRegex = true,
  bool isEnabled = true,
  int order = 0,
}) =>
    NovelReplaceRule(
      pattern: pattern,
      replacement: replacement,
      scope: scope,
      applyTo: applyTo,
      applyToValue: applyToValue,
      isRegex: isRegex,
      isEnabled: isEnabled,
      order: order,
    );

void main() {
  group('NovelReplaceRuleSet.apply', () {
    test('全局规则对所有书籍生效', () {
      final set = NovelReplaceRuleSet(
        bookId: NovelReplaceRuleSet.globalId,
        rules: [_rule(pattern: r'^广告.*$', order: 10)],
      );
      expect(set.apply('广告：点这里', bookId: 'b1'), '');
      expect(set.apply('广告：点这里', bookId: 'b2', sourceId: 's1'), '');
    });

    test('仅本书规则只命中指定书籍', () {
      final set = NovelReplaceRuleSet(
        bookId: NovelReplaceRuleSet.globalId,
        rules: [
          _rule(
            pattern: '第\\d+章',
            replacement: '',
            applyTo: 'book',
            applyToValue: 'b1',
          ),
        ],
      );
      expect(set.apply('第12章 风起', bookId: 'b1'), ' 风起');
      expect(set.apply('第12章 风起', bookId: 'b2'), '第12章 风起');
    });

    test('仅本源规则只命中指定源', () {
      final set = NovelReplaceRuleSet(
        bookId: NovelReplaceRuleSet.globalId,
        rules: [
          _rule(
            pattern: '本站',
            applyTo: 'source',
            applyToValue: 's1',
          ),
        ],
      );
      expect(set.apply('本站提示', bookId: 'b1', sourceId: 's1'), '提示');
      expect(set.apply('本站提示', bookId: 'b1', sourceId: 's2'), '本站提示');
    });

    test('作用位置过滤：标题规则不作用于正文', () {
      final set = NovelReplaceRuleSet(
        bookId: NovelReplaceRuleSet.globalId,
        rules: [_rule(pattern: '风起', scope: 'title')],
      );
      expect(set.apply('风起', scopeFilter: 'content'), '风起');
      expect(set.apply('风起', scopeFilter: 'title'), '');
    });

    test('关闭的规则与总开关关闭时都不生效', () {
      final disabledRule = NovelReplaceRuleSet(
        bookId: NovelReplaceRuleSet.globalId,
        rules: [_rule(pattern: '广告', isEnabled: false)],
      );
      expect(disabledRule.apply('广告'), '广告');

      final disabledSet = NovelReplaceRuleSet(
        bookId: NovelReplaceRuleSet.globalId,
        enabled: false,
        rules: [_rule(pattern: '广告')],
      );
      expect(disabledSet.apply('广告'), '广告');
    });

    test('纯文本规则按字面替换，正则规则按模式替换', () {
      final set = NovelReplaceRuleSet(
        bookId: NovelReplaceRuleSet.globalId,
        rules: [
          _rule(pattern: '（求票）', isRegex: false, order: 10),
          _rule(pattern: '\\s+', replacement: ' ', order: 20),
        ],
      );
      expect(set.apply('正文（求票）  结尾'), '正文 结尾');
    });

    test('多条规则按 order 顺序执行', () {
      final set = NovelReplaceRuleSet(
        bookId: NovelReplaceRuleSet.globalId,
        rules: [
          _rule(pattern: 'A', replacement: 'B', isRegex: false, order: 20),
          _rule(pattern: 'B', replacement: 'C', isRegex: false, order: 10),
        ],
      );
      expect(set.apply('A'), 'B');
    });
  });
}
