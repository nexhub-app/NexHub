/// 小说文本分页器（文档 8.2）。
///
/// 文字级分页渲染算法（用户指定三步，**不含**
/// `textBottomJustify` 底部对齐，末页保留自然排版）：
///
/// 1. **StaticLayout 按宽度折行（重要）**：用 [TextPainter]（等价 Android
/// `StaticLayout`）以 `maxWidth` 为约束把段落拆成适配宽度的视觉行
/// （[TextPainter.computeLineMetrics]），**不是按段落整段装箱**——这是排版
/// 关键：各页顶到页底、行数一致、段落可跨页断行。
/// 2. **逐字符列(TextColumn)定位**：每行记录每个字符的 x 坐标
/// （[NovelLine.charLefts]，由 [TextPainter.getBoxesForSelection] 复用段落级
/// [TextPainter] 一次算出），逐字符定位（列式记录每个字符 x 坐标），
/// 供「点哪读哪」精确命中。
/// 3. **可见高度填满 → 翻页**：逐行贪心装入页面，填满 [height] 才翻页。
library;

import 'package:flutter/widgets.dart';

import '../../../core/models/novel_block.dart';
import '../../../core/utils/app_log.dart';
import '../../../core/novel/novel_line_breaker.dart';
import '../../../core/novel/novel_reader_preferences.dart';
import '../../../core/theme/app_tokens.dart';

/// 单页中的一行文本（按行分页）。
///
/// 逐字符列（TextColumn）定位：每个字符的 x 坐标被
/// 记录下来（[charLefts]），供精确点击命中（点哪读到哪）与未来选区使用。
class NovelLine {
  /// 该行文本（首行已含 `　　` 缩进，续行无缩进）。
  final String text;

  /// 所属段落的全局下标（用于 TTS 高亮 / 点击跳转）。
  final int paragraphIndex;

  /// 是否为该段落的首行（仅首行带缩进）。
  final bool isFirstLine;

  /// 是否为该段落的末行（末行后需加段距）。
  final bool isLastLine;

  /// 逐字符列（TextColumn）定位：本行每个字符**左边缘**相对行首的 x 坐标。
  ///
  /// 由 [NovelPaginator._breakParagraph] 用 [TextPainter.getOffsetForCaret]
  /// 逐字符计算，命中测试 [hitTestCharOffset] 据此把点击 x 映射到精确字符下标。
  /// 长度一般为字符数；合字/组合字符可能合并为一个 box（不影响中文命中精度）。
  ///
  /// 长度一般为字符数；合字/组合字符可能合并为一个 box（不影响中文命中精度）。
  /// 默认空列表（极少数空行未携带，命中回退到段首）。
  final List<double> charLefts;

  /// 是否为章节标题行（来自 [NovelTextBlock.isHeading]）。渲染层据此
  /// 用更大字号 + 居中 + 加粗区分于正文行，让读者在翻页时也能立刻
  /// 看到「第N章」等章节分界。
  final bool isHeading;

  const NovelLine({
    required this.text,
    required this.paragraphIndex,
    this.isFirstLine = false,
    this.isLastLine = false,
    this.charLefts = const <double>[],
    this.isHeading = false,
  });

  /// 把行内某点的水平坐标 [dx]（相对行首左边缘）映射到精确字符下标。
  ///
  /// 等价于逐字符列命中测试：取命中字符中心点最近的字符。
  /// 用于「点哪读哪」——点击行内任意位置得到应跳转/朗读的字符位置。
  int hitTestCharOffset(double dx) {
    if (charLefts.isEmpty) return 0;
    if (dx <= charLefts.first) return 0;
    if (dx >= charLefts.last) return charLefts.length - 1;
    for (var i = 0; i < charLefts.length - 1; i++) {
      final mid = (charLefts[i] + charLefts[i + 1]) / 2;
      if (dx < mid) return i;
    }
    return charLefts.length - 1;
  }
}

/// 单页中的一个项：文本行或插图。
///
/// 翻页模式下插图[NovelImageItem]独占一页（fit contain 居中显示），不与其
/// 他文字挤在一页 —— 因为网络图片高度未知，混排会挤乱文字分页；独占成页
/// 既保证排版稳定，又能完整看图。
sealed class NovelPageItem {
  const NovelPageItem();
}

/// 文本行项（包装[NovelLine]，与插图项统一类型，便于分页器/渲染器遍历）。
class NovelTextLineItem extends NovelPageItem {
  final NovelLine line;

  /// 该行文本所属块在 [blocks] 中的下标（用于目录跳转定位页码）。
  final int blockIndex;

  const NovelTextLineItem(this.line, {this.blockIndex = 0});
}

/// 插图项：在翻页模式下独占一页显示。
class NovelImageItem extends NovelPageItem {
  final NovelImageBlock image;

  /// 该插图所属块在 [blocks] 中的下标（用于目录跳转定位页码）。
  final int blockIndex;

  const NovelImageItem(this.image, {this.blockIndex = 0});
}

/// 单页数据：该页包含的项列表（文本行 + 插图）。
typedef NovelPage = List<NovelPageItem>;

/// 分页结果。
class NovelPaginationResult {
  /// 分页后的页面列表（每页为一组视觉行）。
  final List<NovelPage> pages;

  /// 分页时使用的约束尺寸。
  final Size pageSize;

  const NovelPaginationResult({
    required this.pages,
    required this.pageSize,
  });

  /// 是否为空（无内容）。
  bool get isEmpty => pages.isEmpty;

  /// 找到包含指定块（[blockIndex]）的**第一页**页码（供目录跳转）。
  ///
  /// 遍历每页的每一项，返回首个块下标 ≥ [blockIndex] 的项所在页；
  /// 找不到则返回最后一页（块下标越界时回落到书末）。
  int pageIndexForBlock(int blockIndex) {
    for (var p = 0; p < pages.length; p++) {
      for (final item in pages[p]) {
        final int bi;
        if (item is NovelTextLineItem) {
          bi = item.blockIndex;
        } else if (item is NovelImageItem) {
          bi = item.blockIndex;
        } else {
          continue;
        }
        if (bi >= blockIndex) return p;
      }
    }
    return pages.isEmpty ? 0 : pages.length - 1;
  }
}

/// 文本分页器。
class NovelPaginator {
  NovelPaginator._();

  /// 章节标题行样式（分页测量与翻页渲染共用，两处必须一致）：
  /// 正文样式放大 1.4 倍 + 加粗 + 行高 1.4。
  ///
  /// 此前分页测量用正文样式断行、渲染却按标题样式放大绘制，标题行实际
  /// 宽度超出测量值 ~40%，在 `softWrap:false + clip` 下右侧字符被裁
  ///（「字符显示不全」的根因）；行高同理超出导致页底溢出。统一取样式后
  /// 测量与渲染逐字符一致。
  static TextStyle headingStyleOf(TextStyle bodyStyle) => bodyStyle.copyWith(
        fontSize: (bodyStyle.fontSize ?? 16) * 1.4,
        fontWeight: FontWeight.w700,
        height: 1.4,
      );

  /// 将章节正文分页。
  ///
  /// [blocks] — 章节正文块（文本段与插图共存，每段首行已含 `　　` 缩进）。
  /// [constraints] — 可用绘图区域约束。
  /// [prefs] — 阅读器偏好（字号 / 行距 / 段距 / 边距）。
  /// [context] — BuildContext（用于获取文本方向 / MediaQuery）。
  static NovelPaginationResult paginate({
    required List<NovelBlock> blocks,
    required BoxConstraints constraints,
    required NovelReaderPreferences prefs,
    required BuildContext context,
    String? chapterTitle,
    String? bookName,
  }) {
    final width = constraints.maxWidth - prefs.margin * 2;

    // 扣除页眉 + 页脚 + 两个间距开销（与 _NovelPageWidget 中 headerFooterStyle
    // 一致，fontSize 12），否则分页器高估可用高度导致满页内容溢出正文区。
    const chromeSpacing = AppTokens.spaceSm * 2;
    final headerFooterStyle = TextStyle(
      fontSize: 12,
      fontFamily: prefs.customFontPath != null
          ? NovelReaderPreferences.customLoadedFontFamily
          : prefs.fontFamily,
    );
    // Text 组件会把自身样式与环境 DefaultTextStyle 合并（显式字段覆盖、
    // 缺省字段继承——如主题 bodyMedium 的 height 会渗入页眉页脚行高，
    // 使其实际高度可能大于 fontSize）。探针必须按同样的合并语义测高，
    // 否则分页高估可用高度 ~O(10px)，满页底部行被裁（「字符显示不全」）。
    final chromeStyle =
        DefaultTextStyle.of(context).style.merge(headerFooterStyle);
    final chromeTp = TextPainter(
      text: TextSpan(text: 'M', style: chromeStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: width);
    final chromeHeight = chromeTp.height * 2 + chromeSpacing;
    chromeTp.dispose();

    final height = constraints.maxHeight - prefs.margin * 2 - chromeHeight;

    if (width <= 0 || height <= 0 || blocks.isEmpty) {
      return const NovelPaginationResult(
        pages: <NovelPage>[],
        pageSize: Size.zero,
      );
    }

    final style = prefs.resolveBodyTextStyle(const Color(0xFF000000));
    final dir = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);

    // 1) 把每个块拆成页项（文本行 or 插图项），保留原顺序。
    // 文本块用与正文渲染同一 TextPainter 布局，保证断行点一致；
    // 插图块转为 [NovelImageItem]，翻页时独占一页。
    final allItems = <NovelPageItem>[];
    var textBlockIndex = 0;
    var skippedInline = 0;
    for (var bi = 0; bi < blocks.length; bi++) {
      final block = blocks[bi];
      if (block is NovelTextBlock) {
        if (block.text.isEmpty) continue;
        // 章节标题块用标题样式折行（与渲染一致，见 [headingStyleOf]）：
        // 若按正文样式断行、渲染再放大，标题行会超宽被裁 + 超高溢出页底。
        final styleForBlock =
            block.isHeading ? headingStyleOf(style) : style;
        List<NovelLine> lines;
        if (prefs.lineBreakMode == NovelLineBreakMode.cjkStrict &&
            !block.isHeading) {
          // 中文逐字断行 + 禁首禁尾。标题行仍走原生折行
          // （标题短、居中展示，禁则意义不大且需与渲染层保持一致）。
          lines = _breakParagraphStrict(
            block.text,
            textBlockIndex,
            styleForBlock,
            width,
            dir,
            scaler,
            isHeading: block.isHeading,
          );
        } else {
          lines = _breakParagraph(
            block.text,
            textBlockIndex,
            styleForBlock,
            width,
            dir,
            scaler,
            isHeading: block.isHeading,
          );
        }
        for (final l in lines) {
          allItems.add(NovelTextLineItem(l, blockIndex: bi));
        }
        textBlockIndex++;
      } else if (block is NovelImageBlock) {
        // 行内可点击图标（源用内嵌小图做段评气泡）：不占页、不参与排版，
        // 由渲染层挂到前一段的段尾（与内置段评气泡同一槽位）。块下标不变，
        // 选区/TTS/段评锚点的坐标系不受影响。
        // 行内可点击图标 / 内联 SVG：都不占页（SVG 客户端解不了，占页只会是空白大图）。
        if (block.isInlineAction || block.isSvgIcon) {
          skippedInline++;
          continue;
        }
        allItems.add(NovelImageItem(block, blockIndex: bi));
      }
    }
    if (skippedInline > 0) {
      AppLog.instance.i('[正文图] 分页跳过行内图标 $skippedInline 个');
    }
    if (allItems.isEmpty) {
      return const NovelPaginationResult(
        pages: <NovelPage>[],
        pageSize: Size.zero,
      );
    }

    // 2) 精确行高（底层用 Paint.fontMetrics 度量，我们用 TextPainter.height）。
    // 对中文文本，TextPainter.height 已包含 ascent + descent + 行间距因子，
    // 与渲染引擎实际绘制高度一致。所有正文行等高。
    final measureTp = TextPainter(
      text: TextSpan(text: '中', style: style),
      textDirection: dir,
      textScaler: scaler,
    )..layout(maxWidth: width);
    final lineHeight = measureTp.height;
    measureTp.dispose();
    // 标题行按标题样式单独测高（比正文行高 ~1.4 倍），装箱时逐行取用。
    final headingProbe = TextPainter(
      text: TextSpan(text: '中', style: headingStyleOf(style)),
      textDirection: dir,
      textScaler: scaler,
    )..layout(maxWidth: width);
    final headingLineHeight = headingProbe.height;
    headingProbe.dispose();

    double lineHeightOf(NovelLine l) => l.isHeading ? headingLineHeight : lineHeight;

    // 3) 章节大标题仅在第一页顶部预留高度（#7）。
    final bool showTitle = prefs.showChapterTitleInBody &&
        prefs.titleAlign != NovelTitleAlign.hidden &&
        chapterTitle != null &&
        chapterTitle.isNotEmpty;
    var titleReserve = 0.0;
    if (showTitle) {
      final titleStyle = prefs.resolveTitleTextStyle();
      final mainTp = TextPainter(
        text: TextSpan(text: chapterTitle, style: titleStyle),
        textDirection: dir,
        textScaler: scaler,
        textWidthBasis: TextWidthBasis.longestLine,
      )..layout(maxWidth: width);
      var titleHeight = mainTp.height;
      mainTp.dispose();
      if (prefs.titleSegmentMode &&
          bookName != null &&
          bookName.isNotEmpty) {
        final subStyle = titleStyle.copyWith(
          fontSize: (titleStyle.fontSize ?? 18) * prefs.titleSubScale,
          height: prefs.titleSubLineSpacing,
        );
        final subTp = TextPainter(
          text: TextSpan(text: bookName, style: subStyle),
          textDirection: dir,
          textScaler: scaler,
          textWidthBasis: TextWidthBasis.longestLine,
        )..layout(maxWidth: width);
        titleHeight += prefs.titleSegmentSpacing + subTp.height;
        subTp.dispose();
      }
      titleHeight += prefs.titleTopMargin + prefs.titleBottomMargin;
      titleReserve = titleHeight + prefs.paragraphSpacing * 1.5;
    }

    // 4) 逐行贪心装箱 + 寡行控制（填满一页才翻页）。
    //
    // 核心逻辑：每行高度统一为 lineHeight；段落末行额外加段距。
    // 当一行装不下当前页时，检查把它推到下一页是否会产生「寡行」
    // （即下一页开头只有 1~2 行属于同一段落）。若是，则回退到该段落
    // 在当前页的起始位置，把整个段落剩余部分一起推到下一页，
    // 避免「某页顶部出现孤立的一两行」这种视觉不均。
    //
    // 结果：每页顶到页底、各页行数一致、段落可跨页断行、无孤立寡行。
    const int minWidowLines = 3; // 下页同段至少保留此数行才允许在当前行后断页
    final pages = <NovelPage>[];
    var current = <NovelPageItem>[];
    var used = titleReserve;
    for (var i = 0; i < allItems.length; i++) {
      final item = allItems[i];

      // 插图独占一页：先 flush 当前文字页，再加一个仅含图片的页。
      // 网络图片高度未知，混入文字页会挤乱分页；独占成页既排版稳定又能看图。
      if (item is NovelImageItem) {
        if (current.isNotEmpty) {
          pages.add(current);
          current = <NovelPageItem>[];
          used = 0;
        }
        pages.add(<NovelPageItem>[item]);
        continue;
      }

      final line = (item as NovelTextLineItem).line;
      final lineH =
          lineHeightOf(line) + (line.isLastLine ? prefs.paragraphSpacing : 0);

      // 当前页已放不下且不是空页 → 考虑翻页
      if (used + lineH > height && current.isNotEmpty) {
        // ── 寡行检测 ──
        // 统计当前行所属段落在「即将推入新页的部分」中有多少行：
        // 从 allItems[i] 开始往后数，直到遇到下一个段落的末行(isLastLine)
        // 或插图项（插图不是同段文字，应终止计数）。
        int upcomingLinesOfSamePara = 0;
        for (var j = i; j < allItems.length; j++) {
          final it = allItems[j];
          if (it is NovelImageItem) break;
          upcomingLinesOfSamePara++;
          if ((it as NovelTextLineItem).line.isLastLine) break; // 到了段落末尾
        }

        // 若即将推入新页的同段行数不足阈值 → 会产生寡行！
        // 回退策略：从 current 末尾倒退，找到本段在当前页的起始位置，
        // 把本段已装入的行也一起退出来，整段留给下一页。
        if (upcomingLinesOfSamePara < minWidowLines &&
            upcomingLinesOfSamePara > 0) {
          // 找到当前行所属段落 在 current 中的起始索引
          var paraStartInCurrent = current.length;
          while (paraStartInCurrent > 0) {
            final prev = current[paraStartInCurrent - 1];
            if (prev is NovelTextLineItem &&
                prev.line.paragraphIndex == line.paragraphIndex) {
              paraStartInCurrent--;
            } else {
              break;
            }
          }

          // 把本段已装入 current 的行退出来（连同 used 高度一起扣回）
          final deferred = <NovelPageItem>[];
          var deferredH = 0.0;
          while (current.length > paraStartInCurrent) {
            final removed = current.removeLast();
            deferred.insert(0, removed); // 保持顺序
            final removedLineH = removed is NovelTextLineItem
                ? lineHeightOf(removed.line) +
                    (removed.line.isLastLine ? prefs.paragraphSpacing : 0)
                : 0;
            used -= removedLineH;
            deferredH += removedLineH;
          }

          // 当前页到此结束（不含被回退的本段行）
          if (current.isNotEmpty) {
            pages.add(current);
          }
          current = deferred;
          // 回退行已在 current 中占据高度：新页必须从 deferredH 继续累计，
          // 而非从 0 开始。此前置 0 会把回退行的高度从记账中丢掉，新页
          // 继续按“空页”装行 → 整页超装一个段首块的高度，页底行被
          // SingleChildScrollView 裁切（「正文内容超出显示区域/字符显示不全」）。
          used = deferredH;
          // 不 continue! 下面会把 line(=deferred 的首行)正常加入 current
        } else {
          // 无寡行风险 → 正常翻页
          pages.add(current);
          current = <NovelPageItem>[];
          used = 0;
        }
      }

      current.add(item);
      used += lineH;
    }
    if (current.isNotEmpty) {
      pages.add(current);
    }

    return NovelPaginationResult(
      pages: pages,
      pageSize: Size(width, height),
    );
  }

  /// 用与正文渲染一致的 [TextPainter] 把段落拆成适配宽度的视觉行。
  ///
  /// 返回每行一个 [NovelLine]；首行标记 [NovelLine.isFirstLine]，末行标记
  /// [NovelLine.isLastLine]，便于渲染时加段距。段首 `　　` 已含在文本中，
  /// 因此只有首行带缩进，续行无缩进（与文字级分页的通用做法一致）。
  ///
  /// 实现：
  /// - **StaticLayout 按宽度折行**：[TextPainter] 以 `maxWidth` 布局，用
  /// [TextPainter.computeLineMetrics] 得到每行的高度，再用
  /// [TextPainter.getPositionForOffset] 在每行垂直中心、左边缘探测起始字符
  /// 偏移，从而切出整行文本（与渲染断行点完全一致）。
  /// - **逐字符列(charLefts) 计算**：每行逐字符用 [TextPainter.getOffsetForCaret]
  /// 取左边缘 x 坐标，供长按选区精确命中测试（[hitTestCharOffset]）。
  /// 开销 O(总字符数)，典型章节数百行可接受；大章节（数万行）亦在合理范围。
  static List<NovelLine> _breakParagraph(
    String para,
    int paraIndex,
    TextStyle style,
    double width,
    TextDirection dir,
    TextScaler scaler, {
    bool isHeading = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: para, style: style),
      textDirection: dir,
      textScaler: scaler,
    )..layout(maxWidth: width);

    final metrics = tp.computeLineMetrics();
    if (metrics.isEmpty) {
      tp.dispose();
      return <NovelLine>[];
    }

    // 逐行探测起始字符偏移：在每行垂直中心、左边缘 x=0 处取位置。
    final starts = <int>[];
    var top = 0.0;
    for (var i = 0; i < metrics.length; i++) {
      final y = top + metrics[i].height / 2;
      starts.add(tp.getPositionForOffset(Offset(0, y)).offset);
      top += metrics[i].height;
    }

    final lines = <NovelLine>[];
    for (var i = 0; i < metrics.length; i++) {
      final s = starts[i];
      final e = i + 1 < metrics.length ? starts[i + 1] : para.length;
      if (s >= e) continue;

      // 计算本行逐字符左边缘 x 坐标（用于长按选区精确命中测试）。
      // 用 getOffsetForCaret 逐字符取左边缘，开销 O(n) 每行；典型章
      // 节约数百行，数万行巨章也在可接受范围。
      final charLefts = <double>[];
      for (var ci = s; ci < e; ci++) {
        final caret = tp.getOffsetForCaret(TextPosition(offset: ci), Rect.zero);
        charLefts.add(caret.dx);
      }

      lines.add(NovelLine(
        text: para.substring(s, e),
        paragraphIndex: paraIndex,
        isFirstLine: i == 0,
        isLastLine: i == metrics.length - 1,
        isHeading: isHeading,
        charLefts: charLefts,
      ));
    }
    tp.dispose();
    return lines;
  }

  /// 中文逐字断行 + 禁首禁尾标点路径。
  ///
  /// 复用 [NovelLineBreaker] 的禁则切行结果，适配为 [NovelLine]
  /// （charLefts 已由断行器按整行布局重测，命中测试语义一致）。
  static List<NovelLine> _breakParagraphStrict(
    String para,
    int paraIndex,
    TextStyle style,
    double width,
    TextDirection dir,
    TextScaler scaler, {
    bool isHeading = false,
  }) {
    final broken = NovelLineBreaker.breakParagraph(para, style, width, dir, scaler);
    return <NovelLine>[
      for (var i = 0; i < broken.length; i++)
        NovelLine(
          text: broken[i].text,
          paragraphIndex: paraIndex,
          isFirstLine: i == 0,
          isLastLine: i == broken.length - 1,
          isHeading: isHeading,
          charLefts: broken[i].charLefts,
        ),
    ];
  }
}
