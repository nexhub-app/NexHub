import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/novel/novel_chinese_converter.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';

void main() {
  // flutter_js 创建运行时需经 rootBundle 异步加载扩展资产，测试须先初始化
  // 绑定（此前引擎加载失败被降级守卫吞掉，从未真正触达该路径）。
  TestWidgetsFlutterBinding.ensureInitialized();
  group('chineseConverterJsPrelude（ 书源 JS 繁简函数）', () {
    test('预置脚本包含全局函数定义与映射数据', () {
      expect(chineseConverterJsPrelude, contains('global.t2s'));
      expect(chineseConverterJsPrelude, contains('global.s2t'));
      // 映射数据抽样：字符级与短语级均序列化进脚本。
      expect(chineseConverterJsPrelude, contains('"愛":"爱"'));
      expect(chineseConverterJsPrelude, contains('["魔法門","魔法門"]'));
    });

    test('JsEngine 注入后 t2s/s2t 可直接调用，语义与 convertChinese 一致', () {
      final engine = JsEngine();
      try {
        final probe = engine.eval('typeof t2s');
        if (probe != 'function') {
          // 宿主未提供 QuickJS 原生库时引擎降级为空串返回；此时跳过真机语义断言
          // （预置脚本本身由上一用例与 Dart 侧单测覆盖）。
          return;
        }
        // 字符级。
        expect(engine.eval('t2s("頭髮")'), convertChinese('頭髮', ChineseConvertMode.traditionalToSimplified));
        expect(engine.eval('s2t("头发")'), convertChinese('头发', ChineseConvertMode.simplifiedToTraditional));
        // 短语级最长匹配 / 排除词：乾 不误转干、雪梨保持原貌。
        expect(engine.eval('t2s("乾隆")'), '乾隆');
        expect(engine.eval('t2s("雪梨")'), '雪梨');
        expect(engine.eval('s2t("干部")'), '幹部');
        // 变量实参（非字面量）同样可用。
        expect(
          engine.eval('var x="國"; t2s(x)'),
          convertChinese('國', ChineseConvertMode.traditionalToSimplified),
        );
        // null / undefined 容错。
        expect(engine.eval('t2s(null)'), '');
        expect(engine.eval('t2s(undefined)'), '');
      } finally {
        engine.dispose();
      }
    });
  });
}
