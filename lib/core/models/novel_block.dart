/// 章节正文块：文本段或插图。
///
/// 解析层（[BookContent]）从章节 HTML 中提取 `<img>` 并转为 [NovelImageBlock]，
/// 与其相邻的文本段一起保留在原有顺序，使阅读器能图文混排显示插图。
///
/// 此前正文被压成 `List<String>` 纯文本、`BookContent` 在清洗阶段直接删除了
/// `<img>` 标签，导致插图永远无法显示。引入块模型后，文本与插图作为一等
/// 公民共存于同一列表，渲染层按类型分别处理。
library;

import 'package:nexhub/core/models/plugin_config.dart';

/// 章节正文的一个块：要么是一段文本，要么是一张插图。
abstract class NovelBlock {
  const NovelBlock();
}

/// 文本段（对应原 `List<String>` 中的一个段落，首行已含 `　　` 缩进）。
///
/// [isHeading] 标记该段为「章节标题」，渲染层会用更大的字号/居中/加粗
/// 区分于正文段落。本地 EPUB（`localEpubPath`）的章节标题就是用这个标志
/// 插入正文的，否则 55 章的内容连成一片、滚动时看不到章节分界。
class NovelTextBlock extends NovelBlock {
  final String text;

  /// 是否为章节标题块（用更大字号 + 居中 + 加粗渲染）。
  final bool isHeading;

  const NovelTextBlock(this.text, {this.isHeading = false});

  @override
  bool operator ==(Object other) =>
      other is NovelTextBlock &&
      other.text == text &&
      other.isHeading == isHeading;

  @override
  int get hashCode => Object.hash(text, isHeading);
}

/// 媒体块（legado bookSourceType=1 音频 / 4 视频源）：章节正文即媒体直链。
///
/// 渲染层显示播放卡片；点击拉起播放器（directUrl 直链模式）。
class NovelMediaBlock extends NovelBlock {
  final String url;

  /// 'audio' | 'video'（legado bookSourceType 1/4）。
  final String kind;

  const NovelMediaBlock(this.url, {required this.kind});

  bool get isValid => url.startsWith('http://') || url.startsWith('https://');

  @override
  bool operator ==(Object other) =>
      other is NovelMediaBlock && other.url == url && other.kind == kind;

  @override
  int get hashCode => Object.hash(url, kind);
}

/// 一次正文抓取结果：图文块列表 + 源 `ruleContent.title` 产生的章节名。
///
/// legado 在全部页拼接后求值一次标题规则并回写 `BookChapter.title`；
/// [title] 为 null 表示未声明规则 / 规则未命中 / 结果为空，
/// 调用方应沿用目录章节名。
class NovelContentResult {
  final List<NovelBlock> blocks;
  final String? title;

  const NovelContentResult(this.blocks, {this.title});
}

/// 插图块：章节正文中的一张图片。
///
/// [url] 已是解析层拼好的绝对地址（含 baseUrl 归一化）。
/// [source] 透传给 [SourceImage] 以注入书源防盗链 headers（Referer/Cookie 等）。
/// [style] 透传书源 `ruleContent.imageStyle`（CSS 字符串，如 `max-width:100%`），
/// 渲染层据此约束图片显示方式（未声明则为 null，走默认行为）。
class NovelImageBlock extends NovelBlock {
  final String url;
  final PluginConfig? source;
  final String? style;

  /// 图片 URL 尾部选项里的 `click` 脚本（legado `<img src="url,{...}">`）：
  /// 源用「内嵌小图 + 点击动作」实现正文里的段评气泡/话题入口。非空时
  /// 渲染层把它当可点击图标处理，点击执行该脚本（多在脚本里调
  /// `java.showBrowser(url, html)` 打开源自带的页面）。
  final String? clickScript;

  /// 是否为**行内**图标（选项 `style:"text"/"inline"`）：不按插图排版，
  /// 作为段尾小标记（约一行高）。
  final bool inline;

  const NovelImageBlock(
    this.url, {
    this.source,
    this.style,
    this.clickScript,
    this.inline = false,
  });

  /// 是否为内联 SVG 图标（Flutter 不解 SVG，按插图渲染只会得到破图/整页空白）。
  bool get isSvgIcon => url.startsWith('data:image/svg');

  /// 是否按「可点击行内图标」处理。
  ///
  /// 判据：有 `click`，且（`style` 声明为 text/inline，或地址是内联 SVG）。
  /// 后者兜底源里常见的「SVG 图标 + click 但漏写 style」——这类地址当插图
  /// 渲染既解码不了（Flutter 不解 SVG）也点不动，只会变成一张大破图。
  bool get isInlineAction {
    final String? click = clickScript?.trim();
    if (click == null || click.isEmpty) return false;
    return inline || isSvgIcon;
  }

  /// 是否为可显示的图片地址（http/https 或 data:image 内联）。
  bool get isValid =>
      url.startsWith('http://') ||
      url.startsWith('https://') ||
      url.startsWith('data:image');

  @override
  bool operator ==(Object other) =>
      other is NovelImageBlock &&
      other.url == url &&
      other.clickScript == clickScript &&
      other.inline == inline;

  @override
  int get hashCode => Object.hash(url, clickScript, inline);
}
