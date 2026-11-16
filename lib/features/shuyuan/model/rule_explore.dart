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
      };
}
