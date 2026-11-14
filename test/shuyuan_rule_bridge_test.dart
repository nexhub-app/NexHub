/// 规则桥接线测试：
/// - `java.getElements / getElement / getStringList` 的宿主内联 +
///   JS 侧 jsoup 风格包装（size/get/text/attr）；
/// - `@put` 的两种写法（legado 标准无括号 / 历史带括号）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_rule.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/analyze/source_rule.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AnalyzeRule rule() => AnalyzeRule()
    ..setContent('<div class="i"><a href="/a">甲</a><a href="/b">乙</a></div>')
    ..setBaseUrl('https://x.test/');

  group('java.getElements / getElement / getStringList', () {
    test('getElements 返回可 size/get/text/attr 的列表', () {
      final r = rule();
      expect(r.getString("@js:java.getElements('.i a').size()"), '2');
      expect(r.getString("@js:java.getElements('.i a').get(1).text()"), '乙');
      expect(
          r.getString("@js:java.getElements('.i a').get(0).attr('href')"), '/a');
      expect(r.getString("@js:java.getElements('.i a').text()"), '甲\n乙');
    });

    test('getElement 取首个元素', () {
      final r = rule();
      expect(r.getString("@js:java.getElement('.i a').text()"), '甲');
    });

    test('getStringList 产出可直接使用的 JS 数组', () {
      final r = rule();
      expect(r.getString("@js:java.getStringList('.i a@text').length"), '2');
      expect(r.getString("@js:java.getStringList('.i a@text')[1]"), '乙');
    });

    test('规则未命中时返回空列表 / null，不抛错', () {
      final r = rule();
      expect(r.getString("@js:java.getElements('.nope').size()"), '0');
      // eval 会把字符串 "null" 归一化成空串，故用布尔判断而非 String(null)。
      expect(r.getString("@js:java.getElement('.nope') === null ? 'YES' : 'NO'"),
          'YES');
    });
  });

  group('book 注入对象', () {
    test('读取当前书字段', () {
      final book = XiaoshuoBook(bookUrl: 'https://x.test/b', name: '书名');
      book.author = '作者甲';
      final ctx = ShuyuanSourceContext('book-read');
      final r = AnalyzeRule(book: book)..setContent('<p>x</p>');

      ShuyuanSourceContext.run(ctx, () {
        expect(r.getString('@js:book.name'), '书名');
        expect(r.getString('@js:book.author'), '作者甲');
        expect(r.getString('@js:book.bookUrl'), 'https://x.test/b');
      });
    });

    test('脚本赋值回写当前书（空值不覆盖）', () {
      final book = XiaoshuoBook(bookUrl: 'https://x.test/b', name: '原标题');
      book.author = '原作者';
      final ctx = ShuyuanSourceContext('book-write');
      final r = AnalyzeRule(book: book)..setContent('<p>x</p>');

      ShuyuanSourceContext.run(ctx, () {
        r.getString("@js:book.name = '新标题'; book.name");
        expect(book.name, '新标题');
        // 空串不覆盖已有值（正文阶段的空壳书不能抹掉详情字段）。
        expect(r.getString("@js:book.author = ''; book.author"), '');
        expect(book.author, '原作者');
      });
    });
  });

  group('@put 解析', () {
    test('无括号（legado 标准写法）', () {
      final r = SourceRule('@put:{bid:"h1@text"} tag.a@text');
      expect(r.putMap['bid'], 'h1@text');
      expect(r.rule.contains('@put'), isFalse);
    });

    test('带括号（历史写法）仍兼容', () {
      final r = SourceRule('@put:({bid:"h1@text"}) tag.a@text');
      expect(r.putMap['bid'], 'h1@text');
      expect(r.rule.contains('@put'), isFalse);
    });

    test('多个 @put 依次提取', () {
      final r = SourceRule('@put:{a:"x"}@put:{b:"y"} .list');
      expect(r.putMap, {'a': 'x', 'b': 'y'});
      expect(r.rule.contains('@put'), isFalse);
    });
  });
}
