/// 发现页选项栏（ExploreKind）解析与 6 栅格布局测试。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/explore_kind.dart';
import 'package:nexhub/features/shuyuan/web_book/web_book_types.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('Rhino 宽松箭头解构（[@js:] 需要引擎执行）', () {
    test('裸数组解构参数 [...]=> 补括号后正常执行', () {
      const js = '''
sort=[];
push=(title,url,grow)=>sort.push({title:title,url:url,style:{layout_flexGrow:grow}});
[["男频",["都市","玄幻"]],["女频",["言情"]]].map([group,list]=>{
  push(group,"https://x.com/g?name="+group,1);
  list.map((title,i)=>{
    push(title,"https://x.com/l?name="+title+"&i="+i,0.25);
  });
});
JSON.stringify(sort);
''';
      final kinds = parseExploreKinds('@js:\n$js');
      expect(kinds.map((k) => k.title).toList(),
          ['男频', '都市', '玄幻', '女频', '言情']);
      // URL 按脚本拼接结果输出（正则兜底拿不到动态值）。
      expect(kinds[1].url, 'https://x.com/l?name=都市&i=0');
      expect(kinds[0].style.layoutFlexGrow, 1);
      expect(kinds[1].style.layoutFlexGrow, 0.25);
    });

    test('箭头赋值块 } 后换行接 [ 按 Rhino 语义断句', () {
      const js = '''
sort=[];
push=(t,u)=>sort.push({title:t,url:u});
fn = (a)=>{
  return a;
}

[["A","https://e.com/a"],["B","https://e.com/b"]].map([t,u]=>{
  push(t,u);
});
JSON.stringify(sort);
''';
      final kinds = parseExploreKinds('@js:\n$js');
      expect(kinds.map((k) => k.title).toList(), ['A', 'B']);
      expect(kinds[1].url, 'https://e.com/b');
    });

    test('字符串 / 模板文本里的 ]=> 不被改写', () {
      const js = r'''
sort=[];
push=(title,url)=>sort.push({title:title,url:url});
t = "a[b]=>c";
u = `x ${"p[0]=>q"} y`;
push(t,"https://e.com/1");
push(u,"https://e.com/2");
JSON.stringify(sort);
''';
      final kinds = parseExploreKinds('@js:\n$js');
      expect(kinds.length, 2);
      expect(kinds[0].title, 'a[b]=>c');
      expect(kinds[1].title, 'x p[0]=>q y');
    });
  });

  group('infoMap Java Map 兼容（@js: 脚本内读写与保存）', () {
    test('infoMap.get/save 可调用，返回值照常解析', () {
      const js = '''
const list = [];
const selected = infoMap.get("频道") || "男生";
list.push({title: selected, url: "/m"});
infoMap.save();
JSON.stringify(list);
''';
      final kinds = parseExploreKinds('@js:$js', infoMap: {'频道': '女生'});
      expect(kinds.single.title, '女生');
      expect(kinds.single.url, '/m');
    });

    test('infoMap 下标缺省为 undefined，get 缺省为 null', () {
      const js = '''
var a = infoMap["不存在"];
var b = infoMap.get("不存在");
JSON.stringify([{title: typeof a + "|" + String(b), url: "/u"}]);
''';
      final kinds = parseExploreKinds('@js:$js', infoMap: const {});
      expect(kinds.single.title, 'undefined|null');
    });

    test('infoMap.put/remove/saveNow 与下标写入回写宿主表', () {
      final infoMap = <String, String>{'已有': 'v'};
      const js = '''
infoMap.put("新增", "x");
infoMap["下标"] = "y";
infoMap.remove("已有");
infoMap.saveNow();
JSON.stringify([{title: "t", url: "/u"}]);
''';
      final kinds = parseExploreKinds('@js:$js', infoMap: infoMap);
      expect(kinds.single.url, '/u');
      expect(infoMap, {'新增': 'x', '下标': 'y'});
    });

    test('脚本抛错时宿主 infoMap 不被改写', () {
      final infoMap = <String, String>{'保留': '1'};
      const js = 'infoMap.put("bad", "x"); notAFunction(); JSON.stringify([]);';
      final kinds = parseExploreKinds('@js:$js', infoMap: infoMap);
      expect(kinds, isEmpty);
      expect(infoMap, {'保留': '1'});
    });
  });

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

    test('GSON 宽松：单引号与裸键（神凑轻说样式）', () {
      const json = "[{'title':'文库分类','url':'','style':{layout_flexGrow:1,"
          "layout_flexBasisPercent:1}},\n"
          "{'title':'电击文库','url':'/list.php?class=1&page={{page}}',"
          "style:{layout_flexGrow:1,layout_flexBasisPercent:0.25}}]";
      final kinds = parseExploreKinds(json);
      expect(kinds.map((k) => k.title).toList(), ['文库分类', '电击文库']);
      expect(kinds[1].url, '/list.php?class=1&page={{page}}');
      expect(kinds[1].style.layoutFlexBasisPercent, 0.25);
    });

    test('GSON 宽松：尾逗号（起点样式）', () {
      const json = '[\n'
          '{"title":"男频","url":"","style":{"layout_flexGrow":1}},\n'
          '{"title":"月票榜","url":"/rank?page={{page}}",'
          '"style":{"layout_flexGrow":1}},\n'
          ']';
      final kinds = parseExploreKinds(json);
      expect(kinds.map((k) => k.title).toList(), ['男频', '月票榜']);
      expect(kinds[1].url, '/rank?page={{page}}');
    });

    test('GSON 宽松：单引号字符串含裸换行的 @js URL', () {
      const json = r'''[
{'title':'推荐','url':'@js:
time=Date.now();
"https://a.com/rank?t="+time;','style':{layout_flexGrow:1}}]''';
      final kinds = parseExploreKinds(json);
      expect(kinds.single.title, '推荐');
      expect(kinds.single.url, contains('@js:'));
      expect(kinds.single.url, contains('time=Date.now()'));
    });

    test('GSON 宽松：值缺开引号（番茄样式）', () {
      const json = '{"title": 女生频道","url": "/girl","style":'
          '{"layout_flexGrow": 1}}';
      final kinds =
          parseExploreKinds('[$json]');
      expect(kinds.single.title, '女生频道');
      expect(kinds.single.url, '/girl');
    });

    test('GSON 宽松：注释剔除', () {
      const json = '[\n'
          '// 男频榜单\n'
          '{"title":"周榜","url":"/week","style":{"layout_flexGrow":1}} /* 尾注 */\n'
          ']';
      final kinds = parseExploreKinds(json);
      expect(kinds.single.title, '周榜');
    });

    test('GSON 宽松：单引号字符串内的 \\\' 转义（嵌套 JSON 参数）', () {
      // 社区源把 URL 里的嵌套 JSON 头整段转义：{\'headers\':\'{\"UA\":...}\'}。
      const json = r'''[
{'title':'分类一','url':'/list?q={\'headers\':\'{\"User-Agent\": \"Mozilla/5.0\"}\'}'},
{'title':'分类二','url':'/x2'}
]''';
      final kinds = parseExploreKinds(json);
      expect(kinds.map((k) => k.title).toList(), ['分类一', '分类二']);
      expect(kinds[0].url,
          r'''/list?q={'headers':'{"User-Agent": "Mozilla/5.0"}'}''');
    });

    test('GSON 宽松：双引号字符串内的 \\\' 转义（GSON 同样接受）', () {
      const json = r'''[{"title":"it\'s","url":"/x"}]''';
      final kinds = parseExploreKinds(json);
      expect(kinds.single.title, "it's");
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
