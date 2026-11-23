/// 关联书籍（`ruleBookInfo.relatedBooks`）加载。
///
/// 对齐 legado RelatedBooks：声明是 JSON 数组 `[{key,title,url}]`，每个模块
/// 以发现列表规则解析一组书籍；模块并行请求，过滤当前书自身，单个模块
/// 失败或过滤后为空时丢弃该模块、不影响其他模块。
library;

import 'dart:convert';

import '../analyze/analyze_url.dart';
import '../model/book_source.dart';
import '../model/xiaoshuo_book.dart';
import 'web_book.dart';

class RelatedBookModule {
  RelatedBookModule({
    required this.key,
    required this.title,
    required this.url,
    required this.resolvedUrl,
    required this.books,
  });

  final String key;
  final String title;
  final String url;
  final String resolvedUrl;
  final List<XiaoshuoBook> books;
}

class RelatedBooks {
  static Future<List<RelatedBookModule>> load({
    required XiaoshuoBook book,
    required XiaoshuoBookSource source,
  }) async {
    final defs = _parseDefinitions(source.getBookInfoRule().relatedBooks);
    if (defs.isEmpty) return const <RelatedBookModule>[];
    final webBook = WebBook();
    final modules = await Future.wait(<Future<RelatedBookModule?>>[
      for (final def in defs) _loadModule(webBook, source, book, def),
    ]);
    return <RelatedBookModule>[for (final m in modules) if (m != null) m];
  }

  static Future<RelatedBookModule?> _loadModule(
    WebBook webBook,
    XiaoshuoBookSource source,
    XiaoshuoBook book,
    Map<String, dynamic> def,
  ) async {
    // legado：仅去掉首尾空白，不能删除 JS 字符串/关键字之间的空格。
    final url = (def['url']?.toString() ?? '').trim();
    if (url.isEmpty) return null;
    try {
      final (resolvedUrl, books) = await webBook.exploreBookWithResolvedUrl(
        source: source,
        url: url,
        ruleData: book,
      );
      final filtered = books.where((b) => b.bookUrl != book.bookUrl).toList();
      if (filtered.isEmpty) return null;
      final title = def['title']?.toString() ?? '';
      return RelatedBookModule(
        key: def['key']?.toString() ?? title,
        title: title,
        url: url,
        resolvedUrl: resolvedUrl,
        books: filtered,
      );
    } on Object {
      return null;
    }
  }

  static List<Map<String, dynamic>> _parseDefinitions(String? modulesJson) {
    final raw = modulesJson?.trim() ?? '';
    if (raw.isEmpty) return const <Map<String, dynamic>>[];
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      // 书源 JSON 常见单引号/裸键/尾逗号，按 legado GSON 宽松口径重试。
      try {
        decoded = jsonDecode(AnalyzeUrl.repairJsonLenient(raw));
      } on FormatException {
        return const <Map<String, dynamic>>[];
      }
    }
    if (decoded is! List) return const <Map<String, dynamic>>[];
    return <Map<String, dynamic>>[
      for (final e in decoded)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
  }
}
