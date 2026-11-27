/// 请求参数编码的字符集注册表（对齐 Java `Charset.forName` 的可用集合）。
///
/// 为什么需要：`searchUrl` 的 `{{key}}` 与 POST 表单必须按源声明的 charset
/// 取字节。旧实现只认 GBK 系，其余标签一律回落 UTF-8——Big5/ISO-8859 站点
/// 收到的就是 UTF-8 乱码，搜索无结果且没有任何提示。
///
/// 语义对齐 legado（`EncoderUtils` → `String.toByteArray(charset)`）：
/// - 已知标签按其编码取字节；
/// - 未知/不支持的标签**显式报错**（Java 抛 `UnsupportedCharsetException`），
///   不再静默当 UTF-8 处理；
/// - 标签按 Java 别名表归一（大小写、`_`/`-`、`cp936`、`utf8` 等）。
library;

import 'dart:convert';

import 'package:enough_convert/big5.dart' show Big5Codec;
import 'package:enough_convert/koi8.dart';
import 'package:enough_convert/latin.dart';
import 'package:enough_convert/windows.dart';
import 'package:fast_gbk/fast_gbk.dart';

/// 未知/不支持的字符集（对齐 Java `UnsupportedCharsetException`）。
class ShuyuanUnsupportedCharsetException implements Exception {
  ShuyuanUnsupportedCharsetException(this.label, [this.reason]);

  final String label;
  final String? reason;

  @override
  String toString() =>
      '不支持的字符集：$label${reason == null ? '' : '（$reason）'}';
}

class ShuyuanCharset {
  ShuyuanCharset._();

  /// Java 别名 → 规范名。`Charset.forName` 本身大小写不敏感，且接受大量
  /// 历史别名；这里只收书源实际会写到的部分。
  static const Map<String, String> _aliases = <String, String>{
    'utf8': 'utf-8',
    'unicode-1-1-utf-8': 'utf-8',
    'ascii': 'us-ascii',
    'iso646-us': 'us-ascii',
    'iso-ir-6': 'us-ascii',
    'latin1': 'iso-8859-1',
    'l1': 'iso-8859-1',
    'cp819': 'iso-8859-1',
    'iso8859-1': 'iso-8859-1',
    'latin2': 'iso-8859-2',
    'iso8859-2': 'iso-8859-2',
    'latin3': 'iso-8859-3',
    'iso8859-3': 'iso-8859-3',
    'latin4': 'iso-8859-4',
    'iso8859-4': 'iso-8859-4',
    'latin5': 'iso-8859-9',
    'iso8859-9': 'iso-8859-9',
    'latin6': 'iso-8859-10',
    'iso8859-10': 'iso-8859-10',
    'latin7': 'iso-8859-13',
    'iso8859-13': 'iso-8859-13',
    'latin8': 'iso-8859-14',
    'iso8859-14': 'iso-8859-14',
    'latin9': 'iso-8859-15',
    'iso8859-15': 'iso-8859-15',
    'latin10': 'iso-8859-16',
    'iso8859-16': 'iso-8859-16',
    'gb2312': 'gbk',
    'gb-2312': 'gbk',
    'gb_2312-80': 'gbk',
    'gb18030': 'gb18030',
    'cp936': 'gbk',
    'ms936': 'gbk',
    'windows-936': 'gbk',
    'x-gbk': 'gbk',
    'big5-hkscs': 'big5',
    'cp950': 'big5',
    'windows-950': 'big5',
    'koi8r': 'koi8-r',
    'koi8u': 'koi8-u',
    'utf16': 'utf-16',
    'utf16le': 'utf-16le',
    'utf16be': 'utf-16be',
    'unicode': 'utf-16',
    'unicodefffe': 'utf-16be',
  };

  /// 归一标签（小写、`_`→`-`）；空返回 null。
  static String? normalize(String? label) {
    if (label == null) return null;
    final s = label.trim().toLowerCase().replaceAll('_', '-');
    if (s.isEmpty) return null;
    final alias = _aliases[s] ?? _aliases[s.replaceAll('-', '')];
    if (alias != null) return alias;
    final win = RegExp(r'^(?:windows|cp)(125[0-6])$').firstMatch(s);
    if (win != null) return 'windows-${win.group(1)}';
    final iso = RegExp(r'^iso8859-(\d+)$').firstMatch(s);
    if (iso != null) return 'iso-8859-${iso.group(1)}';
    return s;
  }

  /// 按标签取字节；未知标签抛 [ShuyuanUnsupportedCharsetException]。
  static List<int> encode(String value, String? label) {
    final cs = normalize(label);
    if (cs == null || cs == 'utf-8') return utf8.encode(value);
    switch (cs) {
      case 'us-ascii':
        return ascii.encode(value);
      case 'gbk':
        return gbk.encode(value);
      case 'gb18030':
        return _gb18030Bytes(value);
      case 'big5':
        return const Big5Codec().encode(value);
      case 'iso-8859-1':
        return latin1.encode(value);
      case 'iso-8859-2':
        return const Latin2Codec().encode(value);
      case 'iso-8859-3':
        return const Latin3Codec().encode(value);
      case 'iso-8859-4':
        return const Latin4Codec().encode(value);
      case 'iso-8859-9':
        return const Latin5Codec().encode(value);
      case 'iso-8859-10':
        return const Latin6Codec().encode(value);
      case 'iso-8859-13':
        return const Latin7Codec().encode(value);
      case 'iso-8859-14':
        return const Latin8Codec().encode(value);
      case 'iso-8859-15':
        return const Latin9Codec().encode(value);
      case 'iso-8859-16':
        return const Latin10Codec().encode(value);
      case 'windows-1250':
        return const Windows1250Codec().encode(value);
      case 'windows-1251':
        return const Windows1251Codec().encode(value);
      case 'windows-1252':
        return const Windows1252Codec().encode(value);
      case 'windows-1253':
        return const Windows1253Codec().encode(value);
      case 'windows-1254':
        return const Windows1254Codec().encode(value);
      case 'windows-1255':
        return const Windows1255Codec().encode(value);
      case 'windows-1256':
        return const Windows1256Codec().encode(value);
      case 'koi8-r':
        return const Koi8rCodec().encode(value);
      case 'koi8-u':
        return const Koi8uCodec().encode(value);
      case 'utf-16':
        return _utf16Bytes(value, littleEndian: true, withBom: true);
      case 'utf-16le':
        return _utf16Bytes(value, littleEndian: true, withBom: false);
      case 'utf-16be':
        return _utf16Bytes(value, littleEndian: false, withBom: false);
    }
    // shift_jis / euc-jp / euc-kr 等 Dart 生态缺编码器的字符集：显式失败，
    // 让源作者看到「不支持的字符集」而不是拿到一串 UTF-8 乱码去猜。
    throw ShuyuanUnsupportedCharsetException(label ?? cs);
  }

  /// GB18030：GBK 子集直接用 fast_gbk；超出 GBK 的字符（四字节区）显式
  /// 报错——没有映射表时硬编码四字节序列会发出错误字节，比报错更难排查。
  static List<int> _gb18030Bytes(String value) {
    try {
      return gbk.encode(value);
    } on Object {
      throw ShuyuanUnsupportedCharsetException(
        'gb18030',
        '字符超出 GBK 子集，四字节区未实现',
      );
    }
  }

  static List<int> _utf16Bytes(
    String value, {
    required bool littleEndian,
    required bool withBom,
  }) {
    final out = <int>[];
    if (withBom) {
      out.addAll(
          littleEndian ? const <int>[0xFF, 0xFE] : const <int>[0xFE, 0xFF]);
    }
    for (final u in value.codeUnits) {
      if (littleEndian) {
        out
          ..add(u & 0xFF)
          ..add((u >> 8) & 0xFF);
      } else {
        out
          ..add((u >> 8) & 0xFF)
          ..add(u & 0xFF);
      }
    }
    return out;
  }
}
