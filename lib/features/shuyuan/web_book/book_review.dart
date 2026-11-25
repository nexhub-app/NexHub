/// 段评解析与动作（legado `BookSource.ruleReview: ReviewRule`）。
///
/// 列表：`reviewUrl` 取回响应体后，用 `contentRule`/`avatarRule`/`postTimeRule`
/// 三条**列表规则**取值并按序号对齐（基准 ReviewRule 没有「条目容器」字段，
/// 三条规则本身就是列表规则）。
///
/// 动作：`voteUpUrl`/`voteDownUrl`/`postReviewUrl`/`postQuoteUrl`/`deleteUrl`
/// 都是 URL 模板，交给 [AnalyzeUrl] 走与搜索/正文相同的通道（`<js>`/`@js:`、
/// URL 选项串、源 header、Cookie、登录头全套生效）。用户输入文本经
/// `key` 绑定 `{{key}}`，与搜索关键词同一条编码通道（GBK 源按 GBK 编码）。
/// 条目级地址里的 `{{$.字段}}` 从 [SourceReview.context] 取值。
library;

import '../../../core/models/source_review.dart';
import '../../../core/utils/app_log.dart';
import '../analyze/analyze_rule.dart';
import '../analyze/analyze_url.dart';
import '../model/book_source.dart';
import '../model/rule_review.dart';
import '../model/xiaoshuo_book.dart';
import '../model/xiaoshuo_book_chapter.dart';

class BookReview {
  BookReview._();

  /// 拉取段评列表。[page] 供 `reviewUrl` 里的 `{{page}}` 使用；
  /// [paragraph] 非空时绑定 `{{paragraph}}`（段落锚点，0 起），供
  /// 「按段落取段评」的源把请求收窄到本段。
  static Future<List<SourceReview>> fetchReviews({
    required XiaoshuoBookSource bookSource,
    XiaoshuoBook? book,
    XiaoshuoBookChapter? chapter,
    String? baseUrl,
    int page = 1,
    int? paragraph,
  }) async {
    final rule = bookSource.getReviewRule();
    if (!rule.hasList) return const <SourceReview>[];
    final base = _resolveBase(baseUrl, chapter, book, bookSource);
    try {
      final analyze = AnalyzeUrl(
        url: rule.reviewUrl!.trim(),
        baseUrl: base,
        source: bookSource,
        ruleData: book,
        chapter: chapter,
        page: page,
        extraBindings: paragraph == null
            ? null
            : <String, dynamic>{'paragraph': paragraph, 'index': paragraph},
      );
      final body = await analyze.getStrResponse();
      if (body.isEmpty) return const <SourceReview>[];
      return parseReviews(
        rule: rule,
        body: body,
        book: book,
        chapter: chapter,
        baseUrl: base,
        redirectUrl: analyze.lastFinalUrl ?? analyze.url,
        defaultParagraph: paragraph,
      );
    } catch (e) {
      AppLog.instance.w('[段评] 列表请求失败: 源=${bookSource.bookSourceName} → $e');
      return const <SourceReview>[];
    }
  }

  /// 解析段评列表响应体（与网络分离，便于单测/离线复用）。
  static List<SourceReview> parseReviews({
    required ReviewRule rule,
    required String body,
    XiaoshuoBook? book,
    XiaoshuoBookChapter? chapter,
    required String baseUrl,
    String? redirectUrl,
    int? defaultParagraph,
  }) {
    final contentRule = (rule.contentRule ?? '').trim();
    if (body.isEmpty || contentRule.isEmpty) return const <SourceReview>[];
    final analyzeRule = AnalyzeRule(book: book, chapter: chapter)
      ..setContent(body, baseUrl)
      ..setBaseUrl(baseUrl)
      ..setRedirectUrl(redirectUrl ?? baseUrl);
    final List<String> contents;
    final List<String> avatars;
    final List<String> times;
    final List<String> paragraphs;
    final List<String> upCounts;
    final List<String> downCounts;
    try {
      contents = analyzeRule.getStringList(contentRule);
      avatars = _listOrEmpty(analyzeRule, rule.avatarRule, isUrl: true);
      times = _listOrEmpty(analyzeRule, rule.postTimeRule);
      // 段号/赞数必须与内容**按序号一一对应**：属性取值默认会去重
      // （legado 语义），6 条段评的 data-p=0,0,2,2,4,4 会被压成 3 个值，
      // 对齐后段号全错位 —— 这里显式保留重复值。
      paragraphs = rule.hasParagraphAnchor
          ? _listOrEmpty(analyzeRule, rule.paragraphRule, keepDuplicate: true)
          : const <String>[];
      upCounts = _listOrEmpty(analyzeRule, rule.voteUpCountRule,
          keepDuplicate: true);
      downCounts = _listOrEmpty(analyzeRule, rule.voteDownCountRule,
          keepDuplicate: true);
    } catch (e) {
      AppLog.instance.w('[段评] 列表规则求值失败: $e');
      return const <SourceReview>[];
    }
    final out = <SourceReview>[];
    for (var i = 0; i < contents.length; i++) {
      final content = _plainText(contents[i]);
      if (content.isEmpty) continue;
      final int? anchor = i < paragraphs.length
          ? _parseParagraph(paragraphs[i])
          : defaultParagraph;
      out.add(SourceReview(
        content: content,
        avatar: i < avatars.length ? avatars[i] : '',
        postTime: i < times.length ? _plainText(times[i]) : '',
        index: out.length,
        paragraph: anchor,
        voteUp: i < upCounts.length ? _firstInt(upCounts[i]) ?? 0 : 0,
        voteDown: i < downCounts.length ? _firstInt(downCounts[i]) ?? 0 : 0,
      ));
    }
    return out;
  }

  /// 拉取某条段评的回复列表（`reviewQuoteUrl`，条目上下文供 `{{$.字段}}`）。
  static Future<List<SourceReview>> fetchQuotes({
    required XiaoshuoBookSource bookSource,
    required SourceReview target,
    XiaoshuoBook? book,
    XiaoshuoBookChapter? chapter,
    String? baseUrl,
  }) async {
    final rule = bookSource.getReviewRule();
    final raw = (rule.reviewQuoteUrl ?? '').trim();
    if (raw.isEmpty) return const <SourceReview>[];
    final base = _resolveBase(baseUrl, chapter, book, bookSource);
    try {
      final analyze = AnalyzeUrl(
        url: raw,
        baseUrl: base,
        source: bookSource,
        ruleData: book,
        chapter: chapter,
        itemContext: target.context,
      );
      final body = await analyze.getStrResponse();
      if (body.isEmpty) return const <SourceReview>[];
      return parseReviews(
        rule: rule,
        body: body,
        book: book,
        chapter: chapter,
        baseUrl: base,
        redirectUrl: analyze.lastFinalUrl ?? analyze.url,
      );
    } catch (e) {
      AppLog.instance.w('[段评] 回复列表请求失败: 源=${bookSource.bookSourceName} → $e');
      return const <SourceReview>[];
    }
  }

  /// 发表段评（`postReviewUrl`），[text] 经 `{{key}}` 注入。
  static Future<bool> postReview({
    required XiaoshuoBookSource bookSource,
    required String text,
    XiaoshuoBook? book,
    XiaoshuoBookChapter? chapter,
    String? baseUrl,
    int? paragraph,
  }) {
    return _action(
      bookSource: bookSource,
      urlRule: bookSource.getReviewRule().postReviewUrl,
      text: text,
      paragraph: paragraph,
      book: book,
      chapter: chapter,
      baseUrl: baseUrl,
    );
  }

  /// 回复某条段评（`postQuoteUrl`），[text] 经 `{{key}}` 注入。
  static Future<bool> postQuote({
    required XiaoshuoBookSource bookSource,
    required SourceReview target,
    required String text,
    XiaoshuoBook? book,
    XiaoshuoBookChapter? chapter,
    String? baseUrl,
    int? paragraph,
  }) {
    return _action(
      bookSource: bookSource,
      urlRule: bookSource.getReviewRule().postQuoteUrl,
      text: text,
      target: target,
      paragraph: paragraph,
      book: book,
      chapter: chapter,
      baseUrl: baseUrl,
    );
  }

  /// 点赞/点踩（`voteUpUrl`/`voteDownUrl`）。
  static Future<bool> vote({
    required XiaoshuoBookSource bookSource,
    required SourceReview target,
    required bool up,
    XiaoshuoBook? book,
    XiaoshuoBookChapter? chapter,
    String? baseUrl,
  }) {
    return _action(
      bookSource: bookSource,
      urlRule: up
          ? bookSource.getReviewRule().voteUpUrl
          : bookSource.getReviewRule().voteDownUrl,
      target: target,
      book: book,
      chapter: chapter,
      baseUrl: baseUrl,
    );
  }

  /// 删除自己的段评（`deleteUrl`）。
  static Future<bool> deleteReview({
    required XiaoshuoBookSource bookSource,
    required SourceReview target,
    XiaoshuoBook? book,
    XiaoshuoBookChapter? chapter,
    String? baseUrl,
  }) {
    return _action(
      bookSource: bookSource,
      urlRule: bookSource.getReviewRule().deleteUrl,
      target: target,
      book: book,
      chapter: chapter,
      baseUrl: baseUrl,
    );
  }

  /// 动作统一执行：URL 模板 → [AnalyzeUrl] → 响应非空即视为成功。
  ///
  /// [skipPageCache] 必须开：动作不能命中阶段缓存里的旧响应（否则重复投票/
  /// 连续发帖都会拿到第一次的结果）。
  static Future<bool> _action({
    required XiaoshuoBookSource bookSource,
    required String? urlRule,
    String? text,
    SourceReview? target,
    int? paragraph,
    XiaoshuoBook? book,
    XiaoshuoBookChapter? chapter,
    String? baseUrl,
  }) async {
    final raw = (urlRule ?? '').trim();
    if (raw.isEmpty) return false;
    final base = _resolveBase(baseUrl, chapter, book, bookSource);
    try {
      final analyze = AnalyzeUrl(
        url: raw,
        baseUrl: base,
        source: bookSource,
        ruleData: book,
        chapter: chapter,
        key: (text ?? '').isEmpty ? null : text,
        itemContext: target?.context,
        skipPageCache: true,
        extraBindings: paragraph == null
            ? null
            : <String, dynamic>{'paragraph': paragraph, 'index': paragraph},
      );
      final body = await analyze.getStrResponse();
      if (body.trim().isEmpty) {
        AppLog.instance.w('[段评] 动作响应为空: 源=${bookSource.bookSourceName} url=${analyze.url}');
        return false;
      }
      return true;
    } catch (e) {
      AppLog.instance.w('[段评] 动作执行失败: 源=${bookSource.bookSourceName} → $e');
      return false;
    }
  }

  /// 段评按段落计数（段落锚点气泡用）：`paragraph → 条数`。
  ///
  /// 只统计有段号的条目（`paragraphRule` 给出或按段请求时回落）；段号为空的
  /// 条目属于章级，不进气泡。阅读器每章拉一次列表即可得到全章气泡分布。
  static Map<int, int> countByParagraph(List<SourceReview> reviews) {
    final out = <int, int>{};
    for (final r in reviews) {
      final p = r.paragraph;
      if (p == null || p < 0) continue;
      out[p] = (out[p] ?? 0) + 1;
    }
    return out;
  }

  /// 文本里的首个整数（"赞 12" / "12" / "12 条" 都能取到）；无数字返回 null。
  static int? _firstInt(String raw) {
    final m = RegExp(r'\d+').firstMatch(raw.trim());
    if (m == null) return null;
    return int.tryParse(m.group(0)!);
  }

  /// 段号文本 → 0 起序号；非数字（如「第3段」）提取首个数字；
  /// 仍无法识别返回 null（视为章级段评）。
  static int? _parseParagraph(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final direct = int.tryParse(text);
    if (direct != null) return direct < 0 ? null : direct;
    final m = RegExp(r'\d+').firstMatch(text);
    if (m == null) return null;
    final v = int.tryParse(m.group(0)!);
    return (v == null || v < 0) ? null : v;
  }

  static List<String> _listOrEmpty(
    AnalyzeRule analyzeRule,
    String? rule, {
    bool isUrl = false,
    bool keepDuplicate = false,
  }) {
    final r = (rule ?? '').trim();
    if (r.isEmpty) return const <String>[];
    try {
      return analyzeRule.getStringList(r,
          isUrl: isUrl, keepDuplicate: keepDuplicate);
    } catch (_) {
      return const <String>[];
    }
  }

  /// 段评正文可能是 HTML 片段：换行类标签转换行，其余标签剥离，实体反转义。
  static String _plainText(String raw) {
    if (raw.isEmpty) return '';
    var text = raw;
    if (text.contains('<')) {
      text = text
          .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
          .replaceAll(
              RegExp(r'</(?:div|p|li|dd|h\d)>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'<[^>]*>'), '');
    }
    text = AnalyzeRule.unescapeHtml(text);
    return text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
  }

  static String _resolveBase(
    String? baseUrl,
    XiaoshuoBookChapter? chapter,
    XiaoshuoBook? book,
    XiaoshuoBookSource bookSource,
  ) {
    final candidates = <String?>[
      baseUrl,
      chapter?.url,
      book?.tocUrl,
      book?.bookUrl,
      bookSource.bookSourceUrl,
    ];
    for (final c in candidates) {
      final v = (c ?? '').trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }
}
