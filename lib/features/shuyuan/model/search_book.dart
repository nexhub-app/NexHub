/// 搜索结果书籍模型：搜索/发现列表中的单本书籍。
library;

import 'xiaoshuo_book.dart';

class SearchBook {
  String bookUrl;
  String name;
  String author;
  String? coverUrl;
  String? kind;
  String? lastChapter;
  String? intro;
  String? tocUrl;
  String? wordCount;
  String? bookSourceUrl;
  String? bookSourceName;
  int type;

  SearchBook({
    required this.bookUrl,
    required this.name,
    this.author = '',
    this.coverUrl,
    this.kind,
    this.lastChapter,
    this.intro,
    this.tocUrl,
    this.wordCount,
    this.bookSourceUrl,
    this.bookSourceName,
    this.type = 0,
  });

  factory SearchBook.fromJson(Map<String, dynamic> json) {
    return SearchBook(
      bookUrl: json['bookUrl'] as String? ?? '',
      name: json['name'] as String? ?? '',
      author: json['author'] as String? ?? '',
      coverUrl: json['coverUrl'] as String?,
      kind: json['kind'] as String?,
      lastChapter: json['lastChapter'] as String?,
      intro: json['intro'] as String?,
      tocUrl: json['tocUrl'] as String?,
      wordCount: json['wordCount'] as String?,
      bookSourceUrl: json['bookSourceUrl'] as String?,
      bookSourceName: json['bookSourceName'] as String?,
      type: json['type'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'bookUrl': bookUrl,
        'name': name,
        'author': author,
        if (coverUrl != null) 'coverUrl': coverUrl,
        if (kind != null) 'kind': kind,
        if (lastChapter != null) 'lastChapter': lastChapter,
        if (intro != null) 'intro': intro,
        if (tocUrl != null) 'tocUrl': tocUrl,
        if (wordCount != null) 'wordCount': wordCount,
        if (bookSourceUrl != null) 'bookSourceUrl': bookSourceUrl,
        if (bookSourceName != null) 'bookSourceName': bookSourceName,
        'type': type,
      };

  /// 值相等：对齐 legado `SearchBook` 的自定义 equals——**仅按 bookUrl**
  /// 判定，列表去重（LinkedHashSet）保留首次出现的条目。
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SearchBook && bookUrl == other.bookUrl;

  @override
  int get hashCode => bookUrl.hashCode;

  XiaoshuoBook toBook() {
    return XiaoshuoBook(
      bookUrl: bookUrl,
      name: name,
      author: author,
      coverUrl: coverUrl,
      kind: kind,
      lastChapter: lastChapter,
      intro: intro,
      tocUrl: tocUrl,
      wordCount: wordCount,
      type: type,
    );
  }
}
