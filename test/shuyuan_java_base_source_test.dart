/// `java` 对象双绑定语义回归：
/// - 规则求值期 java = AnalyzeRule：get 的特殊键（bookName/title）与
///   chapter → book → ruleData → source.put(v_) 非空链；put 写章节变量层；
/// - 登录/初始化脚本里 legado 的 java = BaseSource：getKey / getVariable /
///   putVariable / getLoginHeader / getLoginInfo 等必须可直接调用；
/// - 规则层变量取值链尾部读 source.put 的 `__v:` 命名空间。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_rule.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book_chapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  setUp(JsEngine.resetPoolForTest);

  group('java = AnalyzeRule（规则求值期）', () {
    late XiaoshuoBook book;
    late XiaoshuoBookChapter chapter;
    late ShuyuanSourceContext ctx;
    late AnalyzeRule rule;

    setUp(() {
      book = XiaoshuoBook(bookUrl: 'https://x.test/b', name: '书名甲');
      chapter = XiaoshuoBookChapter(
        bookUrl: 'https://x.test/b',
        url: 'https://x.test/b/1',
        title: '章节甲',
      );
      ctx = ShuyuanSourceContext('java-analyze')
        ..bookSourceUrl = 'https://x.test/source.json';
      rule = AnalyzeRule(book: book, chapter: chapter)..setContent('<p>x</p>');
    });

    test('特殊键 bookName/title 取自书/章节对象', () {
      ShuyuanSourceContext.run(ctx, () {
        expect(rule.getString("@js:java.get('bookName')"), '书名甲');
        expect(rule.getString("@js:java.get('title')"), '章节甲');
      });
    });

    test('变量链 chapter → book → ruleData → source(v_) 且空值不短路', () {
      book.putVariable('k', 'bookV');
      ctx.sourceVars['__v:k'] = 'srcV';
      ShuyuanSourceContext.run(ctx, () {
        chapter.putVariable('k', 'chapterV');
        expect(rule.getString("@js:java.get('k')"), 'chapterV');

        // 章节层空值不遮蔽书层（legado takeIf { isNotEmpty }）。
        chapter.putVariable('k', '');
        expect(rule.getString("@js:java.get('k')"), 'bookV');

        book.variableMap.remove('k');
        expect(rule.getString("@js:java.get('k')"), 'srcV');
      });
    });

    test('java.put 写章节变量层，同轮 get 命中新值', () {
      chapter.putVariable('k', 'stale');
      ShuyuanSourceContext.run(ctx, () {
        expect(
            rule.getString("@js:java.put('k', 'fresh'); java.get('k')"),
            'fresh');
      });
    });

    test('1 参 java.get 变量链优先，全空且像 URL 才发请求', () {
      book.putVariable('bookUrl', 'https://x.test/b');
      ShuyuanSourceContext.run(ctx, () {
        expect(rule.getString("@js:java.get('bookUrl')"), 'https://x.test/b');
      });
    });
  });

  group('java = BaseSource（登录/初始化脚本）', () {
    test('getKey/getVariable/putVariable 可直接调用', () async {
      final ctx = await ShuyuanSourceContext.forSource('java-bs-vars');
      ctx.bookSourceUrl = 'https://src.test';
      final engine = JsEngine.forSource('java-bs-vars');
      await ShuyuanSourceContext.run(ctx, () async {
        expect(engine.eval('java.getKey()'), 'https://src.test');
        engine.eval("java.putVariable('explore_state')");
        expect(ctx.sourceVars['__variable'], 'explore_state');
        expect(engine.eval('java.getVariable()'), 'explore_state');
      });
    });

    test('getLoginHeader/putLoginHeader 走 java 通道', () async {
      final ctx = await ShuyuanSourceContext.forSource('java-bs-header');
      final engine = JsEngine.forSource('java-bs-header');
      await ShuyuanSourceContext.run(ctx, () async {
        engine.eval("java.putLoginHeader('{\"Mode\":\"video\"}')");
        expect(ctx.loginHeaderRaw, '{"Mode":"video"}');
        expect(engine.eval('java.getLoginHeader()'), '{"Mode":"video"}');
        expect(engine.eval('java.getLoginHeaderMap().Mode'), 'video');
      });
    });

    test('getLoginInfo/getLoginInfoMap 与 getSource 可调用', () async {
      final ctx = await ShuyuanSourceContext.forSource('java-bs-info');
      ctx.bookSourceUrl = 'https://src.test';
      final engine = JsEngine.forSource('java-bs-info');
      await ShuyuanSourceContext.run(ctx, () async {
        engine.eval('java.putLoginInfo(JSON.stringify({u: "9"}))');
        expect(engine.eval('java.getLoginInfoMap().get("u")'), '9');
        expect(engine.eval('java.getLoginInfo()'), '{"u":"9"}');
        expect(engine.eval('java.getSource().getKey()'), 'https://src.test');
      });
    });
  });

  group('规则层变量取值链', () {
    test('get 读 source.put 写入的 __v: 命名空间', () {
      final ctx = ShuyuanSourceContext('rule-get-v');
      ctx.sourceVars['__v:mode'] = 'audio';
      final rule = AnalyzeRule()..setContent('x');
      ShuyuanSourceContext.run(ctx, () {
        expect(rule.get('mode'), 'audio');
      });
    });
  });
}
