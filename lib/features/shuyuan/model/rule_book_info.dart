/// 书籍详情规则：书源 `ruleBookInfo` 段，定义书籍信息页的解析规则。
library;

class BookInfoRule {
  String? init;
  String? name;
  String? author;
  String? intro;
  String? kind;
  String? lastChapter;
  String? updateTime;
  String? coverUrl;
  String? tocUrl;
  String? wordCount;
  String? canReName;
  String? downloadUrls;
  String? bookStatus;
  String? recommendations;
  String? relatedBooks;

  BookInfoRule({
    this.init,
    this.name,
    this.author,
    this.intro,
    this.kind,
    this.lastChapter,
    this.updateTime,
    this.coverUrl,
    this.tocUrl,
    this.wordCount,
    this.canReName,
    this.downloadUrls,
    this.bookStatus,
    this.recommendations,
    this.relatedBooks,
  });

  factory BookInfoRule.fromJson(Map<String, dynamic> json) {
    return BookInfoRule(
      init: json['init'] as String?,
      name: json['name'] as String?,
      author: json['author'] as String?,
      intro: json['intro'] as String?,
      kind: json['kind'] as String?,
      lastChapter: json['lastChapter'] as String?,
      updateTime: json['updateTime'] as String?,
      coverUrl: json['coverUrl'] as String?,
      tocUrl: json['tocUrl'] as String?,
      wordCount: json['wordCount'] as String?,
      canReName: json['canReName'] as String?,
      downloadUrls: json['downloadUrls'] as String?,
      bookStatus: json['bookStatus'] as String?,
      recommendations: json['recommendations'] as String?,
      relatedBooks: json['relatedBooks'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (init != null) 'init': init,
        if (name != null) 'name': name,
        if (author != null) 'author': author,
        if (intro != null) 'intro': intro,
        if (kind != null) 'kind': kind,
        if (lastChapter != null) 'lastChapter': lastChapter,
        if (updateTime != null) 'updateTime': updateTime,
        if (coverUrl != null) 'coverUrl': coverUrl,
        if (tocUrl != null) 'tocUrl': tocUrl,
        if (wordCount != null) 'wordCount': wordCount,
        if (canReName != null) 'canReName': canReName,
        if (downloadUrls != null) 'downloadUrls': downloadUrls,
        if (bookStatus != null) 'bookStatus': bookStatus,
        if (recommendations != null) 'recommendations': recommendations,
        if (relatedBooks != null) 'relatedBooks': relatedBooks,
      };
}
