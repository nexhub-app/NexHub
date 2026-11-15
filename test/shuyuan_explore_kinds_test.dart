/// 发现页选项栏（ExploreKind）解析与 6 栅格布局测试。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/explore_kind.dart';
import 'package:nexhub/features/shuyuan/web_book/web_book_types.dart';

ExploreKindItem item({
  String title = 'x',
  double grow = 0,
  double basis = -1,
  bool wrap = false,
}) {
  return ExploreKindItem(
    kind: ExploreKind(
      title: title,
      url: 'https://example.com/$title',
      style: ExploreKindStyle(
        layoutFlexGrow: grow,
        layoutFlexBasisPercent: basis,
        layoutWrapBefore: wrap,
      ),
    ),
    displayName: title,
  );
}

void main() {
  group('parseExploreKinds', () {
    test('JSON 保留 type/action/chars/default/viewName/style', () {
      const json = '''
[
  {"title":"玄幻","url":"/x1"},
  {"title":"搜索","type":"text","action":"java.refreshExplore()","default":"斗破"},
  {"title":"榜单","type":"button","action":"java.startBrowser('https://a','A')"},
  {"title":"完结","type":"toggle","chars":["全部","完结","连载"],"default":"完结","style":{"layout_justifySelf":"right"}},
  {"title":"排序","type":"select","chars":["最新","最热"],"style":{"layout_flexBasisPercent":0.5,"layout_wrapBefore":true}},
  {"title":"显示名","url":"/x2","viewName":"'自定'"},
  {"title":"分组标题","url":""}
]''';
      final kinds = parseExploreKinds(json);
      expect(kinds.length, 7);
      expect(kinds[0].recognizedType, ExploreKindType.url);
      expect(kinds[0].isBrowsable, true);
      expect(kinds[1].recognizedType, ExploreKindType.text);
      expect(kinds[1].action, 'java.refreshExplore()');
      expect(kinds[1].defaultValue, '斗破');
      expect(kinds[2].recognizedType, ExploreKindType.button);
      expect(kinds[3].recognizedType, ExploreKindType.toggle);
      expect(kinds[3].chars, ['全部', '完结', '连载']);
      expect(kinds[3].style.layoutJustifySelf, 'right');
      expect(kinds[4].recognizedType, ExploreKindType.select);
      expect(kinds[4].style.layoutFlexBasisPercent, 0.5);
      expect(kinds[4].style.layoutWrapBefore, true);
      expect(kinds[5].viewName, "'自定'");
      expect(kinds[6].isBrowsable, false);
    });

    test('未知 type 按静态条目处理，缺失 type 视为 url', () {
      const json = '''
[
  {"title":"a","url":"/a"},
  {"title":"b","url":"/b","type":"webview"}
]''';
      final kinds = parseExploreKinds(json);
      expect(kinds[0].recognizedType, ExploreKindType.url);
      expect(kinds[1].recognizedType, isNull);
      expect(kinds[1].isBrowsable, false);
    });

    test('文本形态：名称::URL / 纯 URL / 分段引号', () {
      const text = '''
玄幻::https://a.com/xh
"都市::https://a.com/ds"&&https://a.com/all
''';
      final kinds = parseExploreKinds(text);
      expect(kinds.length, 3);
      expect(kinds[0].title, '玄幻');
      expect(kinds[0].url, 'https://a.com/xh');
      expect(kinds[1].title, '都市');
      expect(kinds[2].title, 'https://a.com/all');
      expect(kinds[2].isBrowsable, true);
    });

    test('JSON 字符串值含裸换行仍可解析', () {
      const json = '[\n  {"title":"多行","url":"https://a.com/x\n?p=1"}\n]';
      final kinds = parseExploreKinds(json);
      expect(kinds.single.title, '多行');
      expect(kinds.single.url, 'https://a.com/x\n?p=1');
    });

    test('非法 JSON 抛 FormatException', () {
      expect(() => parseExploreKinds('[{bad json}]'),
          throwsA(isA<FormatException>()));
    });
  });

  group('layoutExploreKindRows', () {
    test('默认跨 2 列，三个一行', () {
      final rows = layoutExploreKindRows(
          <ExploreKindItem>[item(title: 'a'), item(title: 'b'), item(title: 'c')]);
      expect(rows.length, 1);
      expect(rows.single.map((e) => e.span).toList(), <int>[2, 2, 2]);
    });

    test('单列行尾补齐到整行', () {
      final rows = layoutExploreKindRows(<ExploreKindItem>[
        item(title: 'a'),
        item(title: 'b'),
        item(title: 'c'),
        item(title: 'd'),
      ]);
      expect(rows.length, 2);
      expect(rows[0].map((e) => e.span).toList(), <int>[2, 2, 2]);
      expect(rows[1].single.span, 6);
    });

    test('不等宽行的剩余列全部补给最后一列', () {
      // [2,2] 后放不下 flexGrow 的 3：先补齐 [3,3]，再让 3 跨列独占一行补齐到 6。
      final rows = layoutExploreKindRows(<ExploreKindItem>[
        item(title: 'a'),
        item(title: 'b'),
        item(title: 'c', grow: 1),
      ]);
      expect(rows.length, 2);
      expect(rows[0].map((e) => e.span).toList(), <int>[3, 3]);
      expect(rows[1].single.span, 6);
    });

    test('basisPercent 与 wrapBefore', () {
      final rows = layoutExploreKindRows(<ExploreKindItem>[
        item(title: 'half', basis: 0.5),
        item(title: 'full', wrap: true),
        item(title: 'half2', basis: 0.5),
      ]);
      expect(rows.length, 3);
      expect(rows[0].single.span, 6);
      expect(rows[1].single.span, 6);
      expect(rows[2].single.span, 6);
    });
  });
}
