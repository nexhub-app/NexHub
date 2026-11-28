/// XML 内容解析为 package:html DOM（审计 R26）。
///
/// legado 在 `AnalyzeByJSoup.parse` / `AnalyzeByXPath.strToJXDocument` 里
/// 检测 `<?xml` 声明并用 `Jsoup.parse(src, Parser.xmlParser())` 解析：
/// 标签/属性大小写保留、自闭合、CDATA、命名空间前缀都按 XML 语义处理。
/// NexHub 此前一律走 HTML parser（小写化 + 容错修复），XML 树结构会被改写。
///
/// package:html 没有 XML 模式，这里用 package:xml 解析后**转换为
/// package:html 节点树**，让现有 CSS/XPath 引擎、AnalyzeRule 链式规则、
/// JS 桥的 DOM 消费面完全复用。解析失败回落 null（调用方走 HTML parser，
/// 与 legado `runCatching` 的回落一致）。
///
/// 转换规则（对齐 jsoup xmlParser 实测行为）：
/// - 标签名/属性名保留原样（含命名空间前缀 `feed:entry`，规则直接用
///   前缀名选择）；
/// - CDATA 归一为文本节点；注释保留；处理指令/文档类型声明丢弃；
/// - 实体引用由 package:xml 解码为明文文本。
library;

import 'package:html/dom.dart' as html;
import 'package:xml/xml.dart' as xml;

/// 输入以 `<?xml` 声明开头（大小写不敏感）时按 XML 解析并转换 DOM；
/// 返回 null 表示「不是 XML」或「XML 解析失败」，调用方回落 HTML parser。
///
/// [trimLeading] 与 legado 两处调用点保持一致：AnalyzeByJSoup 对**原文**
/// 判定 `startsWith("<?xml", true)`（不 trim），AnalyzeByXPath 对
/// `trim()` 后的文本判定。
html.Document? tryParseXmlDocument(String src, {bool trimLeading = false}) {
  var t = src;
  if (trimLeading) t = t.trimLeft();
  if (t.length < 5) return null;
  final head = t.substring(0, 5).toLowerCase();
  if (head != '<?xml') return null;
  try {
    final xmlDoc = xml.XmlDocument.parse(src);
    final doc = html.Document();
    for (final node in xmlDoc.children) {
      _appendNode(doc, node, doc);
    }
    // 无元素根（只剩声明/注释）：按解析失败处理，回落 HTML。
    if (xmlDocumentRootElement(doc) == null) return null;
    return doc;
  } catch (_) {
    return null;
  }
}

/// 文档根元素。package:html 的 `Document.documentElement` 是
/// `querySelector('html')`（字面名匹配），对 `<rss>` 之类的 XML 根返回
/// null——这里按首元素子节点取。
html.Element? xmlDocumentRootElement(html.Document doc) {
  for (final child in doc.nodes) {
    if (child is html.Element) return child;
  }
  return null;
}

void _appendNode(html.Node parent, xml.XmlNode node, html.Document doc) {
  if (node is xml.XmlElement) {
    final el = html.Element.tag(node.name.qualified);
    for (final attr in node.attributes) {
      el.attributes[attr.name.qualified] = attr.value;
    }
    parent.append(el);
    for (final child in node.children) {
      _appendNode(el, child, doc);
    }
    return;
  }
  if (node is xml.XmlText) {
    final text = node.value;
    if (text.isNotEmpty) parent.append(html.Text(text));
    return;
  }
  if (node is xml.XmlCDATA) {
    final text = node.value;
    if (text.isNotEmpty) parent.append(html.Text(text));
    return;
  }
  if (node is xml.XmlComment) {
    parent.append(html.Comment(node.value));
    return;
  }
  // 处理指令 / 声明 / 文档类型：规则消费面用不到，跳过。
}
