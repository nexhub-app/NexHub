/// R34 对齐：JSONPath 并集、未知语法不部分求值、`{$.field}` 失败保留
/// 字面量、getList 标量不包装。
///
/// legado（AnalyzeByJSonPath.kt + jayway）：
/// - `[0,2]` / `['a','b']` 是 jayway 原生并集（保序）；
/// - 未知语法抛 PathNotFoundException → 调用方 catch → 空结果（NexHub
///   此前按已知前缀部分求值，产出的是错误数据）；
/// - `RuleAnalyzer.innerRule` 只在求值成功（非空）时替换，失败占位符
///   按字面量保留；
/// - getList 单段强制 `read<ArrayList<Any>>`：定路标量映射失败 → 空列表。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_json.dart';

void main() {
  const doc = '''
  {"books":[{"title":"A","price":10},{"title":"B","price":20},
            {"title":"C","price":30}],
   "names":["x","y","z"],"meta":{"a":1,"b":2}}''';
  final json = AnalyzeByJson(doc);

  group('并集', () {
    test('下标并集 [0,2] 保序', () {
      expect(json.getList(r'$.books[0,2].title'), ['A', 'C']);
    });
    test('键名并集', () {
      expect(json.getList(r"$.meta['a','b']"), [1, 2]);
    });
    test('下标并集含负数', () {
      expect(json.getList(r'$.names[0,-1]'), ['x', 'z']);
    });
  });

  group('未知语法不部分求值', () {
    test('顶层逗号：整条按不支持处理（legado jayway 抛异常 → 空结果）', () {
      expect(json.getList(r'$.books[0].price,@.x'), []);
    });
    test('括号不闭合：不再按前缀求值', () {
      expect(json.getList(r'$.books[0'), []);
    });
    test('getObject 同口径', () {
      expect(json.getObject(r'$.books[0].price,@.x'), isNull);
    });
  });

  group(r'{$.field} 内层替换', () {
    test('命中字段：替换', () {
      expect(json.getString(r'id={$.meta.a}'), 'id=1');
    });
    test('全部占位符失败：legado 返回空串（直接路径读取兜底亦失败）', () {
      // innerRule 无任何成功替换 → 返回 "" → getString 落到对整条规则的
      // 直接 JSONPath 读取 → 同样无命中 → ""。
      expect(json.getString(r'id={$.meta.missing}'), '');
    });
    test('混合命中与缺失', () {
      expect(json.getString(r'x={$.meta.a} y={$.meta.zz}'),
          r'x=1 y={$.meta.zz}');
    });
  });

  group('getList 标量不包装', () {
    test('定路标量 → 空列表（legado read<ArrayList> 映射失败）', () {
      expect(json.getList(r'$.books[0].price'), []);
    });
    test('定路 Map → 空列表', () {
      expect(json.getList(r'$.meta'), []);
    });
    test('getObject 仍是标量', () {
      expect(json.getObject(r'$.books[0].price'), 10);
    });
    test('不定段结果保持列表', () {
      expect(json.getList(r'$.books[?(@.price>10)].title'), ['B', 'C']);
      expect(json.getList(r'$.books[*].title'), ['A', 'B', 'C']);
    });
  });
}
