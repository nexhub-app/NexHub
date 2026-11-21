/// 发现页脚本的 `result` 作用域隔离。
///
/// legado `BaseSource.evalJS` 每次求值使用独立绑定（不绑定 `result`），
/// 而 NexHub 把规则绑定作为全局 `var` 注入并跨 eval 存活。发现页脚本
/// 常用 `try { java.hexDecodeToString(result) ... } catch { 初始化 }`
/// 探测阶段；上一轮残留的 hex `result` 会让本该失败的分支“成功”，
/// 跳过 catch 里的初始化（`$`/`Arr` 等），整页脚本随后 ReferenceError。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';
import 'package:nexhub/features/shuyuan/web_book/web_book_types.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _loginJs = r'''
try {
  java.hexDecodeToString(result);
  throw new Error('try 分支继续');
} catch (e) {
  try {
    java.hexDecodeToString(result);
  } catch (e2) {
    $ = {启用: true};
  }
}
''';

const String _exploreJs = "@js:eval(String(source.loginUrl));\n"
    "JSON.stringify(\$.启用 ? [{title: '分类', url: '/c'}] : []);";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  setUp(() {
    JsEngine.resetPoolForTest();
    ShuyuanSourceContext.resetForTest();
  });

  test('发现页求值不继承上一轮泄露的 result', () {
    final ctx = ShuyuanSourceContext('explore-result-isolation')
      ..bindSource(XiaoshuoBookSource(
        bookSourceUrl: 'https://example.test',
        bookSourceName: '本地发现脚本隔离测试源',
        loginUrl: _loginJs,
      ));

    final kinds = ShuyuanSourceContext.run(ctx, () {
      // 模拟规则绑定作为全局 var 注入后残留的 result（前一次 URL 求值）。
      JsEngine.forSource('explore-result-isolation')
          .eval("var result = 'e4b8ade69687';");
      return parseExploreKinds(_exploreJs, baseUrl: 'https://example.test');
    });

    expect(kinds.map((k) => k.title).toList(), <String>['分类']);
  });
}
