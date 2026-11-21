/// 文件类书源的可下载文件条目（legado `BookInfoWebFile`）。
library;

class WebFileItem {
  /// 原始下载地址模板（含 URL 选项/脚本），下载时重新求值。
  final String url;

  /// 展示与后缀判定用文件名（URL/响应头解析结果或书籍兜底命名）。
  final String name;

  const WebFileItem({required this.url, required this.name});

  factory WebFileItem.fromJson(Map<String, dynamic> json) => WebFileItem(
        url: json['url'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'url': url,
        'name': name,
      };
}
