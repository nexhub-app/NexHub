/// 源变量 API 对齐：legado `BaseSource.putVariable(variable)` 为单参，
/// 写入整段源变量（`getVariable()` 读回）；两参写法是本地扩展（键值存储）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('source.putVariable 单参写入整段变量，getVariable() 原样读回', () async {
    final ctx = ShuyuanSourceContext('src-var-api')
      ..bookSourceUrl = 'https://example.com';
    await ShuyuanSourceContext.run(ctx, () async {
      final engine = JsEngine();
      engine.eval(
          'source.putVariable(JSON.stringify({classicDiscovery:{view:"library",group:2}}));');
      final out = engine.eval('String(source.getVariable())');
      expect(out, contains('"classicDiscovery"'));
      expect(out, contains('"library"'));
      expect(ctx.sourceVars['__variable'], contains('"classicDiscovery"'));
    });
  });

  test('source.putVariable(key, value) 两参扩展仍写入单独键', () async {
    final ctx = ShuyuanSourceContext('src-var-api2')
      ..bookSourceUrl = 'https://example.com';
    await ShuyuanSourceContext.run(ctx, () async {
      final engine = JsEngine();
      engine.eval('source.putVariable("k1", "v1");');
      expect(ctx.sourceVars['k1'], 'v1');
      expect(engine.eval('String(source.getVariable("k1"))'), 'v1');
    });
  });
}
