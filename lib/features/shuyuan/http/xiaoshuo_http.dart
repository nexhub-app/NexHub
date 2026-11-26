/// 书源 HTTP 抓取器（遗留、未接入现行链路）。
///
/// 现行书源请求统一走 [AnalyzeUrl]（共享 cookie / 限流 / 验证判定 / 阶段
/// 缓存）；本类只保留 `<500` 状态码、固定 UA 与 15/30s 超时的旧语义，全仓
/// 无调用方。保留仅为避免历史引用编译失败，新代码不得使用。
library;

import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

@Deprecated('遗留包装层，未被现行书源链路使用；请使用 AnalyzeUrl')
class XiaoshuoHttp {
  late final Dio _dio;

  static const _chineseEncodings = ['gbk', 'gb18030', 'gb2312', 'big5'];

  XiaoshuoHttp() : _dio = Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _dio.options.validateStatus = (status) => status != null && status < 500;
    _dio.options.headers.addAll({
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    });

    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      return client;
    };
  }

  Future<String> fetchHtml(
    String url, {
    Map<String, String>? headers,
    String? referer,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw Exception('Invalid URL: $url');
    }

    final response = await _dio.get<List<int>>(
      url,
      options: Options(
        headers: {
          ...?headers,
          if (referer != null) 'Referer': referer,
        },
        responseType: ResponseType.bytes,
      ),
    );

    if (response.statusCode != 200 || response.data == null) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final bytes = response.data!;
    if (bytes.isEmpty) return '';

    String? charset;
    final contentType = response.headers.value('content-type') ?? '';
    final charsetMatch =
        RegExp(r'charset=([^\s;]+)', caseSensitive: false).firstMatch(contentType);
    if (charsetMatch != null) charset = charsetMatch.group(1);

    if (charset == null) {
      final headLen = min(4096, bytes.length);
      final headAscii = String.fromCharCodes(
        bytes.sublist(0, headLen).map((b) => b < 128 ? b : 0x20),
      );
      final idx = headAscii.toLowerCase().indexOf('charset=');
      if (idx != -1) {
        final after = headAscii.substring(idx + 8).trimLeft();
        final m = RegExp(r'^([a-zA-Z0-9_-]+)').firstMatch(after);
        if (m != null) charset = m.group(1);
      }
    }

    if (charset != null && charset.toLowerCase() != 'utf-8') {
      final resolved = _resolveEncoding(charset);
      if (resolved != null) {
        try {
          return resolved.decode(bytes);
        } catch (_) {}
      }
    }

    final utf8Str = utf8.decode(bytes, allowMalformed: true);
    if (_hasReplacementChars(utf8Str)) {
      for (final encName in _chineseEncodings) {
        final enc = Encoding.getByName(encName);
        if (enc != null) {
          try {
            final decoded = enc.decode(bytes);
            if (!_hasReplacementChars(decoded)) return decoded;
          } catch (_) {}
        }
      }
    }

    return utf8Str;
  }

  Document parseHtml(String html) {
    return html_parser.parse(html);
  }

  Encoding? _resolveEncoding(String name) {
    var enc = Encoding.getByName(name);
    if (enc != null) return enc;
    final lower = name.toLowerCase().trim();
    if (lower == 'gbk' || lower == 'gb_2312' || lower == 'gb2312' ||
        lower == 'gb2312-80' || lower == 'gb_2312-80' ||
        lower == 'csgb2312' || lower == 'csiso58bgb231280') {
      return Encoding.getByName('gbk') ?? Encoding.getByName('gb18030');
    }
    return null;
  }

  bool _hasReplacementChars(String s) {
    var count = 0;
    final limit = s.length < 8000 ? s.length : 8000;
    for (var i = 0; i < limit; i++) {
      if (s.codeUnitAt(i) == 0xFFFD) count++;
      if (count > 5) return true;
    }
    return false;
  }

  void close() {
    _dio.close();
  }
}
