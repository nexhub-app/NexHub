/// 书籍数据模型：承载书籍详情、目录 URL、变量等运行时状态。
library;

class XiaoshuoBook {
  String bookUrl;
  String name;
  String author;
  String? coverUrl;
  String? intro;
  String? kind;
  int type;
  String? tocUrl;
  String? wordCount;
  String? lastChapter;
  String? bookInfoHtml;
  String? tocHtml;
  Map<String, String> variableMap = {};
  bool isFavorite;
  String? bookStatus;
  String? updateTime;
  List<String>? recommendations;

  /// 文件类书源（legado bookSourceType=3）的下载地址列表：
  /// `ruleBookInfo.downloadUrls` 按 isUrl 求值的结果（多个链接返回多条）。
  List<String>? downloadUrls;

  /// 目录反转标记（legado `Book.reverseToc`）：由书源 `reverseToc` 字段控制。
  bool reverseToc;

  XiaoshuoBook({
    required this.bookUrl,
    required this.name,
    this.author = '',
    this.coverUrl,
    this.intro,
    this.kind,
    this.type = 0,
    this.tocUrl,
    this.wordCount,
    this.lastChapter,
    this.bookInfoHtml,
    this.tocHtml,
    this.isFavorite = false,
    this.bookStatus,
    this.updateTime,
    this.recommendations,
    this.downloadUrls,
    this.reverseToc = false,
  });

  factory XiaoshuoBook.fromJson(Map<String, dynamic> json) {
    return XiaoshuoBook(
      bookUrl: json['bookUrl'] as String? ?? '',
      name: json['name'] as String? ?? '',
      author: json['author'] as String? ?? '',
      coverUrl: json['coverUrl'] as String?,
      intro: json['intro'] as String?,
      kind: json['kind'] as String?,
      type: json['type'] as int? ?? 0,
      tocUrl: json['tocUrl'] as String?,
      wordCount: json['wordCount'] as String?,
      lastChapter: json['lastChapter'] as String?,
      bookInfoHtml: json['bookInfoHtml'] as String?,
      tocHtml: json['tocHtml'] as String?,
      isFavorite: json['isFavorite'] as bool? ?? false,
      bookStatus: json['bookStatus'] as String?,
      updateTime: json['updateTime'] as String?,
      recommendations: (json['recommendations'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      downloadUrls: (json['downloadUrls'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      reverseToc: json['reverseToc'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'bookUrl': bookUrl,
        'name': name,
        'author': author,
        if (coverUrl != null) 'coverUrl': coverUrl,
        if (intro != null) 'intro': intro,
        if (kind != null) 'kind': kind,
        'type': type,
        if (tocUrl != null) 'tocUrl': tocUrl,
        if (wordCount != null) 'wordCount': wordCount,
        if (lastChapter != null) 'lastChapter': lastChapter,
        if (variableMap.isNotEmpty) 'variableMap': variableMap,
        'isFavorite': isFavorite,
        if (bookStatus != null) 'bookStatus': bookStatus,
        if (updateTime != null) 'updateTime': updateTime,
        if (recommendations != null) 'recommendations': recommendations,
        if (downloadUrls != null) 'downloadUrls': downloadUrls,
        if (reverseToc) 'reverseToc': reverseToc,
      };

  void putVariable(String key, String value) {
    variableMap[key] = value;
  }

  String getVariable(String key) {
    return variableMap[key] ?? '';
  }

  bool get isOnLineTxt => type == 0 && bookUrl.startsWith('http');
}
