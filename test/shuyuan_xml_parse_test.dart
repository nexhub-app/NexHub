/// R26 对齐：`<?xml` 开头的内容走 XML 语义解析（legado xmlParser）。
///
/// legado AnalyzeByJSoup.parse / AnalyzeByXPath.strToJXDocument：检测
/// `<?xml` 声明 → `Jsoup.parse(src, Parser.xmlParser())`——标签/属性
/// 大小写保留、自闭合、CDATA、命名空间前缀按 XML 树结构处理；解析失败
/// 回落 HTML parser（runCatching）。此前 NexHub 一律 HTML parser，XML
/// 树被 HTML 容错规则改写（自闭合被吞、CDATA 当子元素解析）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_jsoup.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_xpath.dart';

void main() {
  group('XML 树结构', () {
    test('自闭合兄弟节点不被 HTML 容错改写', () {
      const src =
          '<?xml version="1.0"?><rss><a/><b>第二项</b></rss>';
      final nodes = AnalyzeByXPath(src).getElements('//b');
      expect(nodes, hasLength(1));
      final parent = (nodes.first.parentNode)!;
      expect(parent.localName, 'rss');
    });

    test('CDATA 内容不解析为子元素', () {
      const src = '<?xml version="1.0"?><t><![CDATA[<b>原文</b>]]></t>';
      expect(AnalyzeByJsoup(src).getString('t'), '<b>原文</b>');
      expect(AnalyzeByXPath(src).getElements('//b'), isEmpty);
    });

    test('标签大小写保留（xpath 名字测试大小写敏感）', () {
      const src =
          '<?xml version="1.0"?><BookList><Book>名</Book></BookList>';
      expect(AnalyzeByXPath(src).getString('/BookList/Book'), '名');
    });

    test('命名空间前缀名可直接选择', () {
      const src =
          '<?xml version="1.0"?><feed:entry>你好</feed:entry>';
      expect(AnalyzeByXPath(src).getString('/feed:entry'), '你好');
    });

    test('实体引用解码', () {
      const src = '<?xml version="1.0"?><t>A&amp;B</t>';
      expect(AnalyzeByJsoup(src).getString('t'), 'A&B');
    });

    test('属性大小写保留且取值大小写不敏感（jsoup attr 语义）', () {
      const src =
          '<?xml version="1.0"?><item Title="名字" lang="zh"/>';
      expect(AnalyzeByJsoup(src).getString('item@title'), '名字');
    });

    test('XML 解析失败回落 HTML parser（legado runCatching）', () {
      const src = '<?xml version="1.0"?><a><b>未闭合';
      final nodes = AnalyzeByXPath(src).getElements('//b');
      expect(nodes, hasLength(1));
    });
  });

  group('非 XML 内容不受影响', () {
    test('无声明 HTML 走原 HTML parser', () {
      const src = '<div class="c">正文</div>';
      expect(AnalyzeByJsoup(src).getString('.c'), '正文');
    });

    test('xml 声明之外的 HTML 内容仍可容错解析', () {
      // HTML 语义的未闭合标签在有 xml 声明但 XML 解析失败时回落 HTML。
      const src = '<?xml version="1.0"?><div class="c"><p>x<p>y</div>';
      expect(AnalyzeByJsoup(src).getString('.c'), isNotEmpty);
    });
  });
}
