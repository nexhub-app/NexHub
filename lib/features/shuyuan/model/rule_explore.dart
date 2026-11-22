/// 发现规则：书源 `ruleExplore` 段，定义发现页书列表的解析规则。
library;

class ExploreRule {
  String? bookList;
  String? bookName;
  String? bookAuthor;
  String? bookUrl;
  String? bookCoverUrl;
  String? bookKind;
  String? bookLastChapter;
  String? bookIntro;
  String? bookWordCount;
  /// legado `ExploreRule.pageParam`：发现页翻页参数名，留空按 page 处理。
  /// 仅用于「详情标签/分类跳转发现页」自动追加页码，NexHub 暂无该入口，
  /// 保留字段避免导入导出丢失。
  String? pageParam;

  ExploreRule({
    this.bookList,
    this.bookName,
    this.bookAuthor,
    this.bookUrl,
    this.bookCoverUrl,
    this.bookKind,
    this.bookLastChapter,
    this.bookIntro,
    this.bookWordCount,
    this.pageParam,
  });

  factory ExploreRule.fromJson(Map<String, dynamic> json) {
    // 与 SearchRule 一致：兼容 legado 原文键名（name/author/coverUrl/
    // kind/lastChapter/intro/wordCount）与内部命名（bookName/...），原名优先。
    String? pick(String legado, String internal) {
      final v = json[legado] as String?;
      if (v != null && v.isNotEmpty) return v;
      return json[internal] as String?;
    }
    return ExploreRule(
      bookList: json['bookList'] as String?,
      bookName: pick('name', 'bookName'),
      bookAuthor: pick('author', 'bookAuthor'),
      bookUrl: json['bookUrl'] as String?,
      bookCoverUrl: pick('coverUrl', 'bookCoverUrl'),
      bookKind: pick('kind', 'bookKind'),
      bookLastChapter: pick('lastChapter', 'bookLastChapter'),
      bookIntro: pick('intro', 'bookIntro'),
      bookWordCount: pick('wordCount', 'bookWordCount'),
      pageParam: json['pageParam'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (bookList != null) 'bookList': bookList,
        if (bookName != null) 'bookName': bookName,
        if (bookAuthor != null) 'bookAuthor': bookAuthor,
        if (bookUrl != null) 'bookUrl': bookUrl,
        if (bookCoverUrl != null) 'bookCoverUrl': bookCoverUrl,
        if (bookKind != null) 'bookKind': bookKind,
        if (bookLastChapter != null) 'bookLastChapter': bookLastChapter,
        if (bookIntro != null) 'bookIntro': bookIntro,
        if (bookWordCount != null) 'bookWordCount': bookWordCount,
        if (pageParam != null) 'pageParam': pageParam,
      };
}
