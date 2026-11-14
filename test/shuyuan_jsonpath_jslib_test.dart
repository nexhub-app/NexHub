/// JSONPath 全集（切片/过滤/函数）+ jsLib 预执行测试（P1-4）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_json.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('JSONPath 切片', () {
    const doc = '{"list":[1,2,3,4,5]}';
    test('正向切片 [0:2]', () {
      expect(AnalyzeByJson(doc).getList(r'$.list[0:2]'), [1, 2]);
    });
    test('负数下标 [-2:]', () {
      expect(AnalyzeByJson(doc).getList(r'$.list[-2:]'), [4, 5]);
    });
    test('带步长 [::2]', () {
      expect(AnalyzeByJson(doc).getList(r'$.list[::2]'), [1, 3, 5]);
    });
    test('区间中段 [1:4]', () {
      expect(AnalyzeByJson(doc).getList(r'$.list[1:4]'), [2, 3, 4]);
    });
  });

  group('JSONPath 过滤', () {
    const doc = '{"books":['
        '{"title":"A","price":10,"cover":""},'
        '{"title":"B","price":25,"cover":"c.jpg"},'
        '{"title":"C","price":30}]}';
    test('数值比较 [?(@.price>20)]', () {
      expect(AnalyzeByJson(doc).getList(r'$.books[?(@.price>20)].title'),
          ['B', 'C']);
    });
    test('相等 [?(@.title==\'A\')]', () {
      expect(AnalyzeByJson(doc).getList(r"$.books[?(@.title=='A')].price"),
          [10]);
    });
    test('字段存在 [?(@.cover)]', () {
      expect(AnalyzeByJson(doc).getList(r'$.books[?(@.cover)].title'), ['B']);
    });
    test('组合通配后过滤后取字段', () {
      expect(
          AnalyzeByJson(doc)
              .getList(r'$.books[?(@.price>=25)].title'),
          ['B', 'C']);
    });
  });

  group('JSONPath 函数与 length', () {
    test('length()', () {
      final a = AnalyzeByJson('{"list":[1,2,3]}');
      final p1 = r'$.list';
      final p2 = r'$.list.length()';
      final p3 = r'$.list.length';
      // ignore: avoid_print
      print('[探针] list=${a.getString(p1).replaceAll("\n", "|")} '
          'len=${a.getString(p2).replaceAll("\n", "|")} '
          'lenNoParen=${a.getString(p3).replaceAll("\n", "|")}');
      expect(a.getString(r'$.list.length()'), '3');
    });
    test('.length 数组友好化', () {
      expect(AnalyzeByJson('{"list":[1,2,3]}').getString(r'$.list.length'),
          '3');
    });
    test('max/min/sum', () {
      expect(AnalyzeByJson('{"n":[4,9,1]}').getString(r'$.n.max()'), '9');
      expect(AnalyzeByJson('{"n":[4,9,1]}').getString(r'$.n.min()'), '1');
      expect(AnalyzeByJson('{"n":[4,9,1]}').getString(r'$.n.sum()'), '14');
    });
  });

  group('jsLib 预执行', () {
    test('jsLib 定义的函数对后续脚本可见', () {
      final ctx = ShuyuanSourceContext('src_1')
        ..jsLib = 'function hello(n){ return "H" + n; }';
      ShuyuanSourceContext.run(ctx, () {
        final e = JsEngine();
        expect(e.eval("hello('i')"), 'Hi');
      });
    });

    test('jsLib 定义的变量参与签名计算', () {
      final ctx = ShuyuanSourceContext('src_1')
        ..jsLib = 'var APPKEY = "abc123";';
      ShuyuanSourceContext.run(ctx, () {
        final e = JsEngine();
        expect(e.eval('"k=" + APPKEY'), 'k=abc123');
      });
    });

    test('jsLib 报错不阻断后续脚本', () {
      final ctx = ShuyuanSourceContext('src_1')..jsLib = 'this.is.bad();';
      ShuyuanSourceContext.run(ctx, () {
        final e = JsEngine();
        expect(e.eval('"ok"'), 'ok');
      });
    });

    test('同引擎同内容只执行一次', () {
      var count = 0;
      final ctx = ShuyuanSourceContext('src_1')
        ..jsLib = 'globalThis.__jsLibRuns = (globalThis.__jsLibRuns || 0) + 1;';
      ShuyuanSourceContext.run(ctx, () {
        final e = JsEngine();
        e.eval('"a"');
        e.eval('"b"');
        count = int.tryParse(e.eval('globalThis.__jsLibRuns || 0')) ?? 0;
      });
      expect(count, 1);
    });
  });
}
