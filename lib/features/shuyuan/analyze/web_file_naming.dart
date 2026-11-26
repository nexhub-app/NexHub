/// 文件类书源（legado bookSourceType=3）的下载链接文件名解析与格式分类。
///
/// 对照 md3 `UrlUtil.getFileName`：
/// - URL 路径末段后缀合法（1-5 位字母数字，且非 php/html）时直接用该文件名；
/// - 否则发 HEAD 请求，依次尝试 `Content-Disposition` 的 filename/filename*、
///   未跟随重定向的 `Location`；
/// - 全部失败返回 null，由调用方按「书名 作者：xx.后缀」兜底命名。
library;

import 'dart:convert';

import 'package:fast_gbk/fast_gbk.dart';

import 'analyze_url.dart';

/// md3 `AppPattern.bookFileRegex`：本地书库认可的书籍文件。
final RegExp _bookFilePattern = RegExp(
  r'\.(txt|epub|umd|pdf|mobi|azw3|azw|md|markdown)$',
  caseSensitive: false,
);

/// md3 `AppPattern.archiveFileRegex`：可解压归档。
final RegExp _archiveFilePattern =
    RegExp(r'\.(zip|cbz|rar|7z)$', caseSensitive: false);

/// md3 `UrlUtil.fileSuffixRegex`：后缀只允许字母数字。
final RegExp _validSuffixPattern = RegExp(r'^[a-z\d]+$', caseSensitive: false);

/// md3 `UrlUtil.unExpectFileSuffixs`：动态页面不算文件名。
const Set<String> _unexpectedSuffixes = <String>{'php', 'html'};

bool isWebBookFile(String name) => _bookFilePattern.hasMatch(name);

bool isWebArchiveFile(String name) => _archiveFilePattern.hasMatch(name);

/// 文件名后缀（不含点，小写）。
String webFileSuffix(String name) {
  final int dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

/// md3 `UrlUtil.getSuffix(name)`：非法后缀回退 `ext`。
String webFileSuffixOrExt(String name) {
  final String suffix = webFileSuffix(name);
  if (suffix.isEmpty ||
      suffix.length > 5 ||
      !_validSuffixPattern.hasMatch(suffix)) {
    return 'ext';
  }
  return suffix;
}

/// 从 URL 末段取文件名；后缀不合法（空/超长/含非字母数字/php/html）返回 null。
String? webFileNameFromPath(String url) {
  final int query = url.indexOf('?');
  final String noQuery = query >= 0 ? url.substring(0, query) : url;
  final int fragment = noQuery.indexOf('#');
  final String noFragment =
      fragment >= 0 ? noQuery.substring(0, fragment) : noQuery;
  final int slash = noFragment.lastIndexOf('/');
  final String segment =
      slash >= 0 ? noFragment.substring(slash + 1) : noFragment;
  if (segment.isEmpty) return null;
  final String suffix = webFileSuffix(segment);
  if (suffix.isEmpty ||
      suffix.length > 5 ||
      !_validSuffixPattern.hasMatch(suffix) ||
      _unexpectedSuffixes.contains(suffix)) {
    return null;
  }
  return segment;
}

/// 解析 `Content-Disposition`：支持 `filename="x"` 与
/// `filename*=UTF-8''x`（多段时取首个命中）。
String? webFileNameFromContentDisposition(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  for (final String part in raw.split(';')) {
    if (!part.contains('filename')) continue;
    final int eq = part.indexOf('=');
    final String value =
        (eq >= 0 ? part.substring(eq + 1) : part.substring('filename'.length))
            .trim()
            .replaceAll(RegExp('^"'), '')
            .replaceAll(RegExp(r'"$'), '');
    if (part.contains('filename*')) {
      // RFC 5987/6266：`charset'lang'percent-encoded`，字符集由参数声明，
      // 不能固定按 UTF-8 解码（legado `UrlUtil.getFileName` 用参数 charset）。
      final int firstQuote = value.indexOf("'");
      final int secondQuote =
          firstQuote < 0 ? -1 : value.indexOf("'", firstQuote + 1);
      if (firstQuote < 0 || secondQuote < 0) return value;
      final String cs = value.substring(0, firstQuote).trim().toLowerCase();
      final String encoded = value.substring(secondQuote + 1);
      return _decodeRfc5987(encoded, cs);
    }
    if (value.isNotEmpty) return value;
  }
  return null;
}

/// 解码 RFC 5987 `ext-value`：按参数声明的字符集解释百分号字节。
///
/// 仅覆盖实际会出现的字符集；未知字符集按 UTF-8 容错，保持旧行为。
String _decodeRfc5987(String encoded, String charset) {
  final bytes = <int>[];
  for (var i = 0; i < encoded.length; i++) {
    final ch = encoded.codeUnitAt(i);
    if (ch == 0x25 && i + 2 < encoded.length) { // '%'
      final v = int.tryParse(encoded.substring(i + 1, i + 3), radix: 16);
      if (v != null) {
        bytes.add(v);
        i += 2;
        continue;
      }
    }
    bytes.add(ch & 0xff);
  }
  switch (charset) {
    case 'iso-8859-1':
    case 'latin1':
    case 'us-ascii':
      return latin1.decode(bytes, allowInvalid: true);
    case 'gbk':
    case 'gb2312':
    case 'gb18030':
    case 'cp936':
      return gbk.decode(bytes, allowMalformed: true);
    default:
      return utf8.decode(bytes, allowMalformed: true);
  }
}

String? _headerValue(Map<String, List<String>>? headers, String key) {
  if (headers == null) return null;
  for (final MapEntry<String, List<String>> e in headers.entries) {
    if (e.key.toLowerCase() == key && e.value.isNotEmpty) return e.value.first;
  }
  return null;
}

/// md3 `UrlUtil.getFileName(AnalyzeUrl)`：路径名 → HEAD 响应头 → null。
Future<String?> resolveWebFileName(AnalyzeUrl analyzeUrl) async {
  // data: URL 无路径文件名，直接走兜底命名。
  if (analyzeUrl.url.startsWith('data:')) return null;
  final String? fromPath = webFileNameFromPath(analyzeUrl.url);
  if (fromPath != null) return fromPath;
  try {
    final AnalyzeUrl head = AnalyzeUrl(
      url: analyzeUrl.url,
      baseUrl: analyzeUrl.baseUrl,
      source: analyzeUrl.source,
      ruleData: analyzeUrl.ruleData,
      itemContext: analyzeUrl.itemContext,
    )
      ..method = 'HEAD'
      // md3 禁止跟随重定向，Location 头才是真实文件地址。
      ..followRedirects = false;
    await head.getStrResponse();
    final String? disposition =
        _headerValue(head.lastResponseHeaders, 'content-disposition');
    final String? fromDisposition =
        webFileNameFromContentDisposition(disposition);
    if (fromDisposition != null && fromDisposition.isNotEmpty) {
      return fromDisposition;
    }
    final String? location = _headerValue(head.lastResponseHeaders, 'location');
    final String? redirect = location ??
        (head.lastFinalUrl != null && head.lastFinalUrl != analyzeUrl.url
            ? head.lastFinalUrl
            : null);
    if (redirect != null && redirect.isNotEmpty) {
      final String decoded = Uri.decodeComponent(redirect);
      return webFileNameFromPath(redirect) ?? webFileNameFromPath(decoded);
    }
  } catch (_) {
    // HEAD 失败按 md3 的 runCatching 语义：无文件名，交给兜底命名。
  }
  return null;
}

/// 文件名局部非法字符（Windows/部分 SAF 拒绝）替换为下划线。
String sanitizeWebFileName(String name) =>
    name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

/// 解压归档内文件名的展示名：去掉 [extractNovelFilesFromArchive] 写入的
/// 「条目路径 hash_」前缀（`12345_书名.txt` → `书名.txt`）。
String webArchiveEntryDisplayName(String fileName) =>
    fileName.replaceFirst(RegExp(r'^-?\d+_'), '');

/// md3 `Book.getExportFileName(suffix)` 默认模板：`$name 作者：$author.$suffix`。
/// 文件名局部非法字符（Windows/部分 SAF 拒绝）替换为下划线。
String webBookExportName({
  required String bookName,
  required String author,
  required String suffix,
}) {
  final String useSuffix = suffix.isEmpty ? 'txt' : suffix;
  return sanitizeWebFileName('$bookName 作者：$author.$useSuffix');
}
