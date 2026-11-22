/// 章节正文解析：依据书源 `ruleContent` 解析章节正文，支持规则替换、
/// fallback 选择器探测、广告清理与 HTML 标签剥离。
library;

import 'package:html/parser.dart' as html_parser;

import 'package:meta/meta.dart';

import '../../../core/models/novel_block.dart';
import '../../../core/utils/app_log.dart';
import '../analyze/analyze_rule.dart';
import '../analyze/js_engine.dart';
import '../analyze/regex_compat.dart';
import '../model/book_source.dart';
import '../model/rule_content.dart';
import '../model/xiaoshuo_book.dart';
import '../model/xiaoshuo_book_chapter.dart';

class BookContent {
  // 复用同一 QuickJS 运行时（按需创建），避免每次解析正文都重建运行时。
  static JsEngine? _jsEngineHolder;
  static JsEngine get _jsEngine {
    _jsEngineHolder ??= JsEngine();
    return _jsEngineHolder!;
  }

  // 预编译正则
  static final _brRegex = RegExp(r'<br\s*/?\s*>', caseSensitive: false);
  static final _pOpenRegex = RegExp(r'<p[^>]*>');
  static final _pCloseRegex = RegExp(r'</p>');
  static final _htmlTagRegex = RegExp(r'<[^>]*>');
  // CSS flex `order` 乱序反爬检测：匹配带 style="...order:N..." 的 <p> 段落。
  static final _cssOrderPRegex = RegExp(
    r'<p[^>]*\bstyle="[^"]*\border:\s*(\d+)[^"]*"[^>]*>([\s\S]*?)</p>',
    caseSensitive: false,
  );
  static final _crlfRegex = RegExp(r'\r\n');
  static final _crRegex = RegExp(r'\r');
  static final _whitespaceRegex = RegExp(r'[ \t]+');

  // 内容选择器列表（静态常量）
  static const _contentSelectors = [
    '#content', '.chapter-content', '.read-content', '#chaptercontent',
    '.novel-content', '.content', '#BookText', '#booktext',
    '.text-content', '#content-body', '.book-content', '.article-content',
    '#chapter-content', '.chapter_text', '#txt', '.readtext',
    '.bookreadercontent', '#BookContent', '.BookContent',
    '.content-body', '#readcontent', '.nr_nr', '#nr1',
    '.readcontent', '#content_1', '#content_2', '#content1',
    '.chaptercontent', '.novelcontent', '#novelcontent',
    '.read_content', '#read_content', '.book_content',
    '#book_content', '.article-content', '#article-content',
    '.article_content', '.chapter_content', '#chapter_content',
    '.chaptertext', '#txtcontent', '.txt-content', '#txt-content',
    '.read-content', '#read-content', '.readcontent',
    '#readcontent', '.text-content', '#text-content',
    '.booktext', '#booktext', '.book-text', '#book-text',
    '.bookreader-content', '#bookreader-content',
    '.article', '#article', '.post-content', '#post-content',
    '.entry-content', '#entry-content', '.story-content',
    '#story-content', '.novel-content', '#novel-content',
    '.chapterbody', '#chapterbody', '.text-body', '#text-body',
    'div[id*="content"]', 'div[class*="content"]',
    'div[id*="Content"]', 'div[class*="Content"]',
    'div[id*="chapter"]', 'div[class*="chapter"]',
    'div[id*="Chapter"]', 'div[class*="Chapter"]',
    'div[id*="text"]', 'div[class*="text"]',
    'div[id*="Text"]', 'div[class*="Text"]',
    'div[id*="read"]', 'div[class*="read"]',
    'div[id*="Read"]', 'div[class*="Read"]',
    'div[id*="novel"]', 'div[class*="novel"]',
    'div[id*="book"]', 'div[class*="book"]',
    'main', 'article', 'section',
    '.main-content', '#main-content',
    '.page-content', '#page-content',
    '.post', '.entry', '.single-post',
  ];

  // 广告清理选择器
  static const _adSelectors = [
    'script', 'style', 'ins', 'iframe',
    '.ad', '.ads', '.adv', '.advert',
    '[id*="ad"]', '[class*="ad"]',
  ];

  // 合并后的广告选择器（预编译，单次 DOM 遍历使用）
  static final _adSelectorCombined = _adSelectors.join(',');

  // 跳过模式（预编译）
  static final _skipPatterns = [
    RegExp(r'^(首页|主页|书库|书架|排行|榜单|分类|搜索|登录|注册)'),
    RegExp(r'^(返回|回到顶部|返回顶部)'),
    RegExp(r'^(广告|推广|点击|注册|下载|APP|微信|QQ)'),
    RegExp(r'^(Copyright|ICP|备案)'),
    RegExp(r'^\d+$'),
    RegExp(r'^(>>|<<|>|<|下一页|上一页|更多)$'),
  ];

  // 广告关键词
  static const _adKeywords = [
    '广告', '推广', '点击', '注册', '登录', '充值',
    '微信', 'QQ', '群', '公众号', '小程序',
    '兴趣部', '全本小说', '免费阅读', '最新章节',
  ];

  // 整行广告关键词（仅用于"短行"匹配，避免误删正文中含常见词如"点击/微信"的段落）。
  static const int _adLineMaxLength = 40;
  static const List<String> _adLineKeywords = <String>[
    '广告', '推广', '充值', '兴趣部', '全本小说',
    '免费阅读', '最新章节', '请收藏', '手机阅读', '下载APP',
    '全文阅读', '笔趣阁', 'app下载', '安卓版',
  ];

  // 内容 fallback 选择器：当书源规则未命中或结果为空时尝试
  static const _fallbackSelectors = [
    '#content',
    '.chapter-content',
    '.read-content',
    '#chaptercontent',
    '.novel-content',
    '.content',
    '#BookText',
    '#booktext',
    '.text-content',
    '#content-body',
    '.book-content',
    '.article-content',
    '#chapter-content',
    '#readcontent',
    '.readcontent',
    '#txt',
    '.txt-content',
    '#txt-content',
    '.post-content',
    '#post-content',
    '.entry-content',
    '#entry-content',
    'article',
    'main',
  ];

  static List<NovelBlock> analyzeContent({
    required XiaoshuoBookSource bookSource,
    required XiaoshuoBook book,
    required XiaoshuoBookChapter bookChapter,
    required String baseUrl,
    required String? redirectUrl,
    required String body,
    String? nextChapterUrl,
    bool mediaSource = false,
    bool processTitle = true,
  }) {
    // legado WebBook.getContent：一级目录（卷章，URL 为标题占位）不解析正文
    // 规则，直接返回 `tag ?: ""`；阅读器调用方已过滤卷章，此处兜底避免误抓取。
    if (bookChapter.isVolume && bookChapter.url.startsWith(bookChapter.title)) {
      final tag = bookChapter.tag ?? '';
      return tag.isEmpty
          ? const <NovelBlock>[]
          : <NovelBlock>[NovelTextBlock(tag)];
    }

    final contentRule = bookSource.getContentRule();
    final analyzeRule = AnalyzeRule(book: book, chapter: bookChapter)
      ..setContent(body, baseUrl)
      ..setBaseUrl(baseUrl)
      ..setRedirectUrl(redirectUrl ?? baseUrl)
      ..setNextChapterUrl(nextChapterUrl);

    String content = '';

    final watch = Stopwatch()..start();
    if (contentRule.content != null && contentRule.content!.isNotEmpty) {
      content = _getContent(analyzeRule, contentRule.content!);
    }
    AppLog.instance.i('[书源正文] 规则求值 源=${bookSource.bookSourceName} '
        '输入=${body.length} 输出=${content.length} '
        '耗时=${watch.elapsedMilliseconds}ms');

    // 正文规则提取结果日志：空结果 → 规则未命中 / JS 失败（真机排查关键）。
    if (content.trim().isEmpty) {
      AppLog.instance.w('[书源正文] 规则提取为空: 源=${bookSource.bookSourceName} '
          'url=$redirectUrl content规则=${contentRule.content ?? '(空)'}');
    } else {
      AppLog.instance.d('[书源正文] 规则命中: 源=${bookSource.bookSourceName} '
          '${content.length}字符 url=$redirectUrl');
    }

    if (processTitle) applyChapterTitle(analyzeRule, contentRule, bookChapter);

    // 音/视频源（legado bookSourceType=1/4，BookContent.analyzeContent 同款
    // 分支）：正文即媒体直链或 DASH/MPD 清单文本，不做 fallback 选择器、
    // HTML 剥离与分块（MPD 的 XML 会被当标签删光 → 播放器拿不到地址）。
    if (mediaSource) {
      if (contentRule.replaceRegex != null &&
          contentRule.replaceRegex!.isNotEmpty) {
        content = content.split('\n').map((line) => line.trim()).join('\n');
        content = applyReplaceRules(content, contentRule.replaceRegex!,
            analyzeRule: analyzeRule);
      }
      final mediaText = content.trim();
      return mediaText.isEmpty
          ? const <NovelBlock>[]
          : <NovelBlock>[NovelTextBlock(mediaText)];
    }

    // 如果 primary selector 未命中或结果为空，尝试 fallback selector 列表
    if (content.trim().isEmpty) {
      content = _tryFallbackSelectors(analyzeRule);
    }

    if (content.trim().isEmpty) {
      content = _extractGenericContent(body);
    }

    // 通用反爬：还原 CSS flex `order` 乱序段落（详见 _reorderCssOrderParagraphs）。
    // 必须在 HTML 剥离(_formatContent)之前，此时 content 仍含 <p style="order:N"> 标签。
    content = _reorderCssOrderParagraphs(content);

    // 若抽取结果是 HTML（如 @html），在应用 replaceRegex 前先把 <br>/<p> 边界
    // 规整为换行，使 line-anchored 的 replaceRegex 能按行匹配导航/广告文本，
    // 表现与 @textNodes 抽取后的纯文本一致（笔趣阁多页一致性修复）。
    // 必须在 _reorderCssOrderParagraphs 之后，避免破坏 order 乱序还原所需的 <p> 标签。
    if (content.contains('<')) {
      content = content
          .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'<p[^>]*>', caseSensitive: false), '\n');
    }

    if (contentRule.replaceRegex != null && contentRule.replaceRegex!.isNotEmpty) {
      // 逐行 trim 后应用替换规则（对齐 legado：逐行 trim）
      content = content.split('\n').map((line) => line.trim()).join('\n');
      watch.reset();
      content = applyReplaceRules(content, contentRule.replaceRegex!,
          analyzeRule: analyzeRule);
      if (watch.elapsedMilliseconds >= 500) {
        AppLog.instance.i('[书源正文] 替换规则 源=${bookSource.bookSourceName} '
            '长度=${content.length} 耗时=${watch.elapsedMilliseconds}ms');
      }
    }

    // 内容清洗：块级剥离 HTML + 按段提取插图 + 按段去除广告行。
    var blocks = _formatToBlocks(content, baseUrl, redirectUrl ?? baseUrl);
    blocks = _cleanContentAdsBlocks(blocks);

    // legado ruleContent.imageDecode：对正文插图 URL 做 JS 解码（部分站点用 JS
    // 混淆图片地址，需还原真实 URL 才能加载）。仅源声明 imageDecode 时生效，
    // 解码失败则保留原 URL（不丢图）。
    if (contentRule.imageDecode != null && contentRule.imageDecode!.isNotEmpty) {
      blocks = _decodeImageUrls(blocks, contentRule.imageDecode!);
    }
    // legado ruleContent.imageStyle：把图片 CSS 样式（如 max-width:100%）绑到
    // 插图块，供渲染层按样式约束显示。仅源声明时生效，缺省不影响任何源。
    if (contentRule.imageStyle != null && contentRule.imageStyle!.isNotEmpty) {
      final style = contentRule.imageStyle!;
      blocks = blocks.map((b) => b is NovelImageBlock
          ? NovelImageBlock(b.url, source: b.source, style: style)
          : b).toList();
    }

    // legado HtmlFormatter.formatKeepImg 对正文每一段统一补两个全角空格
    // （与 replaceRegex 是否声明无关）；幂等剥离源自带缩进后再统一加。
    if (blocks.isNotEmpty) {
      blocks = _applyIndentBlocks(blocks);
    }

    return blocks;
  }

  static final RegExp _chapterImgRegex =
      RegExp(r'^(.*)((?:data|https?):[\s\S]+)$');

  /// legado BookContent 外层标题规则：在页拼接后求值一次；命中
  /// `图片地址` 尾巴时剥离为章节名（图片部分 legado 存入 reviewImg，
  /// NexHub 章节模型无该字段，丢弃）。
  ///
  /// 返回实际生效的章节名（未声明规则 / 未命中 / 结果为空返回 null），
  /// 供 `BookContentResult.title` 透传到阅读器。
  static String? applyChapterTitle(
    AnalyzeRule analyzeRule,
    ContentRule contentRule,
    XiaoshuoBookChapter bookChapter,
  ) {
    final titleRule = contentRule.title;
    if (titleRule == null || titleRule.isEmpty) return null;
    try {
      var title = analyzeRule.getString(titleRule);
      if (title.isEmpty) return null;
      final match = _chapterImgRegex.firstMatch(title);
      if (match != null) {
        final beforeImg = match.group(1) ?? '';
        title = beforeImg.isNotEmpty ? beforeImg : bookChapter.title;
      }
      if (title.isEmpty) return null;
      bookChapter.title = title;
      return title;
    } catch (_) {
      return null;
    }
  }

  /// legado BookContent 外层 subContent：all 页拼接后对首页响应求值一次，
  /// 作为附加正文追加（http 开头时先抓取）。legado 随后才对整段跑
  /// replaceRegex/缩进，这里对附加段单独复现这两个后处理。
  static List<NovelBlock> formatAppendedContent({
    required String content,
    required ContentRule contentRule,
    required String baseUrl,
    required String redirectUrl,
    required AnalyzeRule analyzeRule,
  }) {
    var text = content;
    final replaceRule = contentRule.replaceRegex;
    final hasReplace = replaceRule != null && replaceRule.isNotEmpty;
    if (hasReplace) {
      text = text.split('\n').map((line) => line.trim()).join('\n');
      text = applyReplaceRules(text, replaceRule, analyzeRule: analyzeRule);
    }
    var blocks = _formatToBlocks(text, baseUrl, redirectUrl);
    blocks = _cleanContentAdsBlocks(blocks);
    if (hasReplace && blocks.isNotEmpty) {
      blocks = _applyIndentBlocks(blocks);
    }
    return blocks;
  }

  static String _getContent(AnalyzeRule analyzeRule, String contentRule) {
    try {
      return analyzeRule.getString(contentRule, unescape: false);
    } catch (_) {
      return '';
    }
  }

  /// fallback selector 探测
  static String _tryFallbackSelectors(AnalyzeRule analyzeRule) {
    for (final selector in _fallbackSelectors) {
      try {
        final value = analyzeRule.getString(selector, unescape: false);
        if (value.trim().isNotEmpty) {
          return value;
        }
      } catch (_) {}
    }
    return '';
  }

  /// 内容广告清理（块级）：按文本段匹配广告关键词与跳过模式，删除广告文本块；
  /// 插图块原样保留（插图不是广告行）。
  static List<NovelBlock> _cleanContentAdsBlocks(List<NovelBlock> blocks) {
    final out = <NovelBlock>[];
    for (final b in blocks) {
      if (b is NovelImageBlock) {
        out.add(b);
        continue;
      }
      if (b is! NovelTextBlock) continue;
      final trimmed = b.text.trim();
      if (trimmed.isEmpty) continue;

      // 跳过导航 / 版权等整行模式（始终移除）。
      bool isAd = false;
      for (final pattern in _skipPatterns) {
        if (pattern.hasMatch(trimmed)) {
          isAd = true;
          break;
        }
      }
      if (isAd) continue;

      // 仅对"短行"做广告关键词匹配，避免正文中出现"点击/微信"等常见词被整段误删。
      if (trimmed.length <= _adLineMaxLength) {
        for (final keyword in _adLineKeywords) {
          if (trimmed.contains(keyword)) {
            isAd = true;
            break;
          }
        }
      }
      if (isAd) continue;

      out.add(b);
    }
    return out;
  }

  /// 段落缩进（幂等）：仅作用于文本块，插图块原样保留。
  ///
  /// 先去掉行首已有的全角/半角缩进，再统一加一个全角空格，避免源 HTML
  /// 已带首行缩进时与引擎缩进叠加（笔趣阁 #nr1@html 多页一致性修复）。
  static List<NovelBlock> _applyIndentBlocks(List<NovelBlock> blocks) {
    return [
      for (final b in blocks)
        if (b is NovelImageBlock)
          b
        else if (b is NovelTextBlock)
          NovelTextBlock(_indentParagraph(b.text))
        else
          b,
    ];
  }

  /// 幂等加首行缩进：去掉行首已有缩进后统一加一个全角空格。
  static String _indentParagraph(String text) {
    final stripped = text.replaceFirst(RegExp(r'^[　\s\t]+'), '');
    return '　　$stripped';
  }

  /// 还原 CSS flex `order` 乱序反爬。
  ///
  /// 部分站点（如 PTCMS 系）把正文 `<p>` 在 HTML 源码中打乱顺序，再给每个
  /// 段落设 `style="order:N"`，容器用 `display:flex;flex-direction:column`，
  /// 让浏览器在**视觉上**按 order 升序重排。直接抽取文本会得到乱序正文。
  ///
  /// 本方法是**通用能力**：仅当检测到 3 个以上带 `order:N` 的 `<p>` 段落时
  /// 才触发，按 order 升序重排后重新拼成 `<p>...</p>`，交给 [_formatContent]
  /// 继续剥离标签。对不含该模式的普通站点零副作用（直接原样返回）。
  /// 不依赖任何具体站点/域名，符合"源即插件、引擎只做通用处理"的架构。
  static String _reorderCssOrderParagraphs(String htmlContent) {
    if (htmlContent.isEmpty || !htmlContent.contains('order:')) {
      return htmlContent;
    }
    final matches = _cssOrderPRegex.allMatches(htmlContent).toList();
    if (matches.length < 3) return htmlContent; // 未命中乱序模式，原样返回
    final items = <MapEntry<int, String>>[];
    for (final m in matches) {
      final order = int.tryParse(m.group(1) ?? '');
      if (order == null) continue;
      items.add(MapEntry(order, m.group(2) ?? ''));
    }
    if (items.length < 3) return htmlContent;
    items.sort((a, b) => a.key.compareTo(b.key));
    return items.map((e) => '<p>${e.value}</p>').join('\n');
  }

  /// HTML → 图文块：剥离标签得到文本段，同时把 `<img>` 提取为插图块。
  ///
  /// 逐块（按 <br>/<p> 边界切分）处理：每块先提取内部插图（src / data-src /
  /// data-original 懒加载，拼 baseUrl 绝对化），再文本化（剥离标签 + 解码实体
  /// + 规整空白）。插图块追加在所属文本段之后，保留图文混排位置。
  /// 此前 _formatContent 用 [_htmlTagRegex] 把 <img> 连同所有标签一起删除，插图
  /// 永远丢失 —— 这是"小说阅读器看不到插图"的根因。
  static List<NovelBlock> _formatToBlocks(
    String content,
    String baseUrl,
    String redirectUrl,
  ) {
    if (content.isEmpty) return const [];

    // 先把残留的 <br>/<p> 边界规整成换行（与旧 _formatContent 一致）。
    content = content
        .replaceAll(_brRegex, '\n')
        .replaceAll(_pOpenRegex, '\n')
        .replaceAll(_pCloseRegex, '\n');

    final rawLines = content.split('\n');
    final blocks = <NovelBlock>[];
    for (final rawLine in rawLines) {
      // 1) 提取本块内插图（懒加载属性优先，回退 src）。
      final imgs = _extractImageUrls(rawLine, baseUrl, redirectUrl);
      // 2) 文本化：剥离标签 + 解码实体 + 规整空白。
      var text = rawLine.replaceAll(_htmlTagRegex, '');
      text = _decodeEntities(text);
      text = text
          .replaceAll(_crlfRegex, '\n')
          .replaceAll(_crRegex, '\n')
          .replaceAll(_whitespaceRegex, ' ')
          .trim();
      if (text.isNotEmpty) {
        blocks.add(NovelTextBlock(text));
      }
      for (final img in imgs) {
        blocks.add(NovelImageBlock(img));
      }
    }
    return blocks;
  }

  /// legado `HtmlFormatter.formatImagePattern` 的逐字移植，三档按序：
  /// 1. `src` 含 `{...}`（URL 选项 JSON 内部带引号，普通属性正则会被截断）；
  /// 2. `data-src|src`（懒加载约定，贪婪前缀使后出现的属性优先）；
  /// 3. 任意 `data-*`。
  /// 用最终页 URL（redirectUrl）解析相对路径，避免拼到错误域名。
  static final RegExp _formatImagePattern = RegExp(
    '<img[^>]*\\ssrc\\s*=\\s*[\'"]([^\'"{}>]*\\{(?:[^{}]|\\{[^}>]+\\})+\\})[\'"][^>]*>'
    '|<img[^>]*\\s(?:data-src|src)\\s*=\\s*[\'"]([^\'">]+)[\'"][^>]*>'
    '|<img[^>]*\\sdata-[^=>]*=\\s*[\'"]([^\'">]*)[\'"][^>]*>',
    caseSensitive: false,
  );

  static List<String> _extractImageUrls(
    String block,
    String baseUrl,
    String redirectUrl,
  ) {
    final urls = <String>[];
    for (final m in _formatImagePattern.allMatches(block)) {
      final src = m.group(1) ?? m.group(2) ?? m.group(3) ?? '';
      if (src.isEmpty) continue;
      // legado formatKeepImg 之后整段执行 unescapeHtml4，图片地址中的
      // `&amp;` 等实体会还原；图块提前抽取，这里补同一次解码。
      final abs = _toAbsoluteUrl(
          AnalyzeRule.unescapeHtml(src), baseUrl, redirectUrl);
      if (_looksLikeImage(abs)) urls.add(abs);
    }
    return urls;
  }

  /// 相对路径转绝对 URL：优先用最终页地址（redirectUrl），回退 baseUrl。
  /// 复用 [AnalyzeRule.absoluteUrl] 的 legado 语义（data:/javascript: 特判、
  /// URL 选项 `,{...}` 原样保留）。
  static String _toAbsoluteUrl(String src, String baseUrl, String redirectUrl) {
    final base = redirectUrl.isNotEmpty ? redirectUrl : baseUrl;
    return AnalyzeRule.absoluteUrl(base, src);
  }

  /// 过滤明显非插图的占位图（1px 透明图、loading 动画、spacer 等）。
  ///
  /// 与通用书源规范一致：保留所有非占位符的 URL（包括无扩展名 CDN 图床），
  /// 仅过滤明显是占位图/loading 图的 URL。此前要求扩展名（.jpg/.png 等），
  /// 导致无扩展名图床 URL 被误过滤，插图永远无法显示。
  static bool _looksLikeImage(String url) {
    if (url.startsWith('data:image')) return true;
    final lower = url.toLowerCase();
    if (lower.contains('1x1') ||
        lower.contains('loading') ||
        lower.contains('placeholder') ||
        lower.contains('spacer') ||
        lower.contains('pixel') ||
        lower.contains('blank')) {
      return false;
    }
    // 只要不是明显占位图就可以通过。不再要求 URL 含图片扩展名，
    // 兼容 CDN 图床的无扩展名 URL（如 https://cdn.example.com/image?id=123）。
    return true;
  }

  /// 对正文插图块逐个应用 [decodeJs] 解码 URL（legado `result` 绑定单图 URL，
  /// 脚本返回真实地址）。解码结果非空才替换，异常/空结果保留原 URL。
  static List<NovelBlock> _decodeImageUrls(
    List<NovelBlock> blocks,
    String decodeJs,
  ) {
    final out = <NovelBlock>[];
    for (final b in blocks) {
      if (b is! NovelImageBlock) {
        out.add(b);
        continue;
      }
      var url = b.url;
      try {
        final decoded =
            _jsEngine.eval(decodeJs, bindings: <String, dynamic>{'result': url});
        if (decoded.isNotEmpty) url = decoded;
      } catch (_) {}
      out.add(NovelImageBlock(url, source: b.source, style: b.style));
    }
    return out;
  }

  /// 解码 HTML 实体并对齐 legado `HtmlFormatter` 的空白归一：
  /// `&nbsp;/&ensp;/&emsp;` → 半角空格，`&thinsp;/&zwnj;/&zwj;` 与其
  /// Unicode 形态删除；随后完整 HTML4 反转义（legado 正文在格式化后执行
  /// `StringEscapeUtils.unescapeHtml4`）。
  static String _decodeEntities(String text) {
    if (!text.contains('&') &&
        !text.contains('\u00A0') &&
        !text.contains('\u2002') &&
        !text.contains('\u2003') &&
        !text.contains('\u2009') &&
        !text.contains('\u200C') &&
        !text.contains('\u200D')) {
      return text;
    }
    return AnalyzeRule.unescapeHtml(text)
        .replaceAll('\u00A0', ' ')
        .replaceAll('\u2002', ' ')
        .replaceAll('\u2003', ' ')
        .replaceAll(RegExp('[\u2009\u200C\u200D]'), '');
  }

  static String _extractGenericContent(String body) {
    final document = html_parser.parse(body);

    // 一次性移除所有广告元素，避免重复操作
    _removeAdsFromDocument(document);

    String bestContent = '';
    double bestScore = 0.0;

    // 优先使用高质量选择器（前 20 个覆盖 90% 的场景）
    final prioritySelectors = _contentSelectors.take(20);

    for (final selector in prioritySelectors) {
      try {
        final el = document.querySelector(selector);
        if (el != null) {
          var text = el.text.trim();
          if (text.isNotEmpty) {
            final score = _calculateContentScoreFast(text);
            if (score > bestScore) {
              bestScore = score;
              bestContent = text;
              // 高质量内容立即返回，不继续遍历剩余 CSS 选择器
              if (bestScore >= 0.7) return bestContent;
            }
          }
        }
      } catch (_) {}
    }

    // 如果最佳内容质量不达标，尝试从 body 直接提取
    if (bestContent.isEmpty || bestScore < 0.2) {
      final bodyEl = document.querySelector('body');
      if (bodyEl != null) {
        var bodyText = _cleanBodyContent(bodyEl.text.trim());
        if (bodyText.length > bestContent.length) {
          bestContent = bodyText;
        }
      }
    }

    return bestContent;
  }

  /// DOM 广告移除
  static void _removeAdsFromDocument(dynamic document) {
    try {
      final ads = document.querySelectorAll(_adSelectorCombined);
      for (final ad in ads) {
        ad.remove();
      }
    } catch (_) {}
  }

  /// 内容评分：综合长度、中文密度、广告关键词命中
  static double _calculateContentScoreFast(String text) {
    if (text.isEmpty) return 0.0;

    final length = text.length;

    // 长度评分（权重更高）
    double lengthScore = 0.0;
    if (length >= 500) {
      lengthScore = 1.0;
    } else if (length >= 300) {
      lengthScore = 0.8;
    } else if (length >= 150) {
      lengthScore = 0.6;
    } else if (length >= 80) {
      lengthScore = 0.4;
    } else {
      lengthScore = 0.1;
    }

    // 简单的文本密度检查（使用字符串操作替代正则）
    int chineseCount = 0;
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (code >= 0x4e00 && code <= 0x9fa5) {
        chineseCount++;
      }
    }
    final density = chineseCount / length;
    double densityScore = 0.0;
    if (density >= 0.4) {
      densityScore = 1.0;
    } else if (density >= 0.25) {
      densityScore = 0.7;
    } else if (density >= 0.15) {
      densityScore = 0.4;
    } else {
      densityScore = 0.2;
    }

    // 简化的广告检测（只查前 100 个字符）
    final preview = text.length > 100 ? text.substring(0, 100) : text;
    int adCount = 0;
    for (final keyword in _adKeywords) {
      if (preview.contains(keyword)) {
        adCount++;
      }
    }
    double adScore = 1.0;
    if (adCount > 3) {
      adScore = 0.3;
    } else if (adCount > 1) {
      adScore = 0.7;
    }

    // 综合评分（简化算法）
    return (lengthScore * 0.5 + densityScore * 0.3 + adScore * 0.2).clamp(0.0, 1.0);
  }

  /// body 文本清洗
  static String _cleanBodyContent(String text) {
    final lines = text.split('\n');
    final cleanedLines = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      // 仅按跳过模式过滤；保留短行（如对话"啊。""……"），避免正文残缺。
      bool shouldSkip = false;
      for (final pattern in _skipPatterns) {
        if (pattern.hasMatch(trimmed)) {
          shouldSkip = true;
          break;
        }
      }
      if (!shouldSkip) {
        cleanedLines.add(trimmed);
      }
    }
    return cleanedLines.join('\n');
  }

  /// 替换规则应用（legado replaceRegex 常见形态）：
  /// - `@js:`/`<js>` 净化脚本 → 规则引擎求值（result=正文）；
  /// - 多行多规则：每行一条 `pattern##replacement`（replacement 可含 ##），
  ///   依序应用；空 pattern 行跳过（防 RegExp('') 撑爆正文）。
  /// multiLine: true 让 ^...$ 锚点支持每行边界匹配。
  ///
  /// [analyzeRule] 为正文页规则实例时，JS 分支复用其 book/chapter/baseUrl
  /// 绑定（legado 的 replaceRegex 在正文 AnalyzeRule 上求值）。
  @visibleForTesting
  static String applyReplaceRules(
    String content,
    String replaceRegex, {
    AnalyzeRule? analyzeRule,
  }) {
    final rr = replaceRegex.trim();
    if (rr.startsWith('@js:') || rr.contains('<js>')) {
      final ar = analyzeRule ?? (AnalyzeRule()..setContent(content));
      final out = ar.getString(rr, mContent: content);
      return out.isEmpty ? content : out;
    }
    var out = content;
    for (final line in rr.split('\n')) {
      final rule = line.trim();
      if (rule.isEmpty) continue;
      final parts = rule.split('##');
      final pattern = parts[0];
      final replacement = parts.length >= 2 ? parts.sublist(1).join('##') : '';
      if (pattern.isEmpty) continue;
      try {
        // Java→Dart 正则兼容：(?i) 等内联标志原先会直接抛错被吞掉。
        final compat = RegexCompat.translate(pattern);
        out = out.replaceAll(
            RegExp(
              compat.pattern,
              multiLine: true,
              caseSensitive: compat.caseSensitive,
              dotAll: compat.dotAll,
            ),
            replacement);
      } catch (_) {}
    }
    return out;
  }
}
