/// 搜索规则：书源 `ruleSearch` 段，定义搜索结果列表的解析规则。
library;

class SearchRule {
  String? bookList;
  String? bookName;
  String? bookAuthor;
  String? bookUrl;
  String? bookCoverUrl;
  String? bookKind;
  String? bookLastChapter;
  String? bookIntro;
  String? bookWordCount;
  String? checkKeyWord;

  SearchRule({
    this.bookList,
    this.bookName,
    this.bookAuthor,
    this.bookUrl,
    this.bookCoverUrl,
    this.bookKind,
    this.bookLastChapter,
    this.bookIntro,
    this.bookWordCount,
    this.checkKeyWord,
  });

  factory SearchRule.fromJson(Map<String, dynamic> json) {
    // legado 原文键名（name/author/coverUrl/kind/lastChapter/intro/
    // wordCount）与内部命名兼容：优先采用 legado 原名，缺失时回退内部名，
    // 保证两类书源都能正确解析。
    String? pick(String legado, String internal) {
      final v = json[legado] as String?;
      if (v != null && v.isNotEmpty) return v;
      return json[internal] as String?;
    }
    return SearchRule(
      bookList: json['bookList'] as String?,
      bookName: pick('name', 'bookName'),
      bookAuthor: pick('author', 'bookAuthor'),
      bookUrl: json['bookUrl'] as String?,
      bookCoverUrl: pick('coverUrl', 'bookCoverUrl'),
      bookKind: pick('kind', 'bookKind'),
      bookLastChapter: pick('lastChapter', 'bookLastChapter'),
      bookIntro: pick('intro', 'bookIntro'),
      bookWordCount: pick('wordCount', 'bookWordCount'),
      checkKeyWord: json['checkKeyWord'] as String?,
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
        if (checkKeyWord != null) 'checkKeyWord': checkKeyWord,
      };
}
