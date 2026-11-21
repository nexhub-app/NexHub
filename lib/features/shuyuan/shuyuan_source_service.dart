/// 书源导入服务：解析书源 JSON / XML / 文本批量格式，
/// 输出 [ShuyuanSource] 列表，供 [ShuyuanAdapter] 转换为 [PluginConfig]。
///
/// 支持格式：
/// - JSON 数组（最常见）：`[{ "bookSourceUrl": ... }, ...]`
/// - JSON 单对象：`{ "bookSourceUrl": ... }`
/// - JSON 包装：`{ "bookSources": [...] }`
/// - XML：`<sources><source>...</source></sources>`
/// - NDJSON（每行一个对象）
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import 'model/book_source.dart';
import 'model/rule_book_info.dart';
import 'model/rule_content.dart';
import 'model/rule_explore.dart';
import 'model/rule_search.dart';
import 'model/rule_toc.dart';

/// 书源原始数据（与 XiaoshuoBookSource 区别：保持 Map 形态，
/// 便于在 adapter 阶段一并保存到 PluginConfig.selectors['xiaoshuo']
/// 实现完整规则回写）。
class ShuyuanSource {
  final String bookSourceName;
  final String bookSourceUrl;
  final int bookSourceType;
  final String? bookSourceGroup;
  final String? bookSourceComment;
  final bool enabled;
  final String? searchUrl;
  final String? exploreUrl;
  final String? header;
  final String? tocUrl;
  final Map<String, dynamic>? ruleSearch;
  final Map<String, dynamic>? ruleBookInfo;
  final Map<String, dynamic>? ruleToc;
  final Map<String, dynamic>? ruleContent;
  final Map<String, dynamic>? ruleExplore;

  // ── legado 扩展字段（P0 导入保真）：此前导入链路只透传 15 个字段，jsLib/
  // 登录三件套/并发限速/权重等在入库时全部丢失。类型容错见 [_asInt]/[_asJsString]。
  final String? bookUrlPattern;
  final int customOrder;
  final bool? enabledExplore;
  final String? jsLib;
  final bool? enabledCookieJar;
  final String? concurrentRate;
  final String? loginUrl;
  final String? loginUi;
  final String? loginCheckJs;
  final String? coverDecodeJs;
  final String? variableComment;
  final int lastUpdateTime;
  final int respondTime;
  final int weight;
  final String? exploreScreen;

  /// 事件回调开关（legado BookSource.eventListener）：为 true 且
  /// callBackJs 非空时，客户端事件（阅读开始/换章/详情页点击/自定义
  /// 按钮等）才执行源脚本；脚本返回假值则回退默认动作。
  final bool eventListener;

  /// 自定义按钮显隐（legado BookSource.customButton）：详情页/阅读器
  /// 的「自定义按钮」入口按此字段展示。
  final bool customButton;

  /// 原始书源 JSON 整图（导入保真的根本保证：任何 legado 字段——含本模型
  /// 尚未建模的未知扩展——都随 selectors['xiaoshuo'] 持久化，运行期
  /// [ShuyuanSource.fromJson] 可再次完整解析）。
  final Map<String, dynamic>? raw;

  /// 动态筛选分组（共创式：源自行声明 `filters`，驱动发现页筛选按钮与
  /// PTCMS 分类 URL 拼装）。原样透传到 PluginConfig.filters。
  final Map<String, dynamic>? filters;

  /// 首页多板块配置（共创式：源自行声明 `homeSections`，驱动首页竖向堆叠
  /// 渲染）。原样透传到 PluginConfig.homeSections。
  final List<Map<String, dynamic>>? homeSections;

  const ShuyuanSource({
    required this.bookSourceName,
    required this.bookSourceUrl,
    this.bookSourceType = 0,
    this.bookSourceGroup,
    this.bookSourceComment,
    this.enabled = true,
    this.searchUrl,
    this.exploreUrl,
    this.header,
    this.tocUrl,
    this.ruleSearch,
    this.ruleBookInfo,
    this.ruleToc,
    this.ruleContent,
    this.ruleExplore,
    this.bookUrlPattern,
    this.customOrder = 0,
    this.enabledExplore,
    this.jsLib,
    this.enabledCookieJar,
    this.concurrentRate,
    this.loginUrl,
    this.loginUi,
    this.loginCheckJs,
    this.coverDecodeJs,
    this.variableComment,
    this.lastUpdateTime = 0,
    this.respondTime = 180000,
    this.weight = 0,
    this.exploreScreen,
    this.eventListener = false,
    this.customButton = false,
    this.raw,
    this.filters,
    this.homeSections,
  });

  bool get isValid =>
      bookSourceName.isNotEmpty &&
      bookSourceUrl.isNotEmpty &&
      (ruleSearch != null ||
          ruleToc != null ||
          ruleContent != null ||
          ruleExplore != null);

  /// 转换为 XiaoshuoBookSource（供 WebBook 直接消费）。
  XiaoshuoBookSource toBookSource() {
    return XiaoshuoBookSource(
      bookSourceUrl: bookSourceUrl,
      bookSourceName: bookSourceName,
      bookSourceGroup: bookSourceGroup,
      bookSourceType: bookSourceType,
      bookSourceComment: bookSourceComment,
      enabled: enabled,
      header: header,
      searchUrl: searchUrl,
      exploreUrl: exploreUrl,
      ruleSearch:
          ruleSearch != null ? SearchRule.fromJson(ruleSearch!) : null,
      ruleBookInfo: ruleBookInfo != null
          ? BookInfoRule.fromJson(ruleBookInfo!)
          : null,
      ruleToc: ruleToc != null ? TocRule.fromJson(ruleToc!) : null,
      ruleContent:
          ruleContent != null ? ContentRule.fromJson(ruleContent!) : null,
      ruleExplore:
          ruleExplore != null ? ExploreRule.fromJson(ruleExplore!) : null,
      // legado 扩展字段（P0 导入保真）：运行期引擎可用的前提。
      bookUrlPattern: bookUrlPattern,
      customOrder: customOrder,
      enabledExplore: enabledExplore ?? enabled,
      jsLib: jsLib,
      enabledCookieJar: enabledCookieJar ?? true,
      concurrentRate: concurrentRate,
      loginUrl: loginUrl,
      loginUi: loginUi,
      loginCheckJs: loginCheckJs,
      coverDecodeJs: coverDecodeJs,
      variableComment: variableComment,
      lastUpdateTime: lastUpdateTime,
      respondTime: respondTime,
      weight: weight,
      exploreScreen: exploreScreen,
      eventListener: eventListener,
      customButton: customButton,
    );
  }

  factory ShuyuanSource.fromJson(Map<String, dynamic> json) {
    String? resolveTocUrl() {
      final topToc = json['tocUrl'];
      if (topToc is String && topToc.isNotEmpty) return topToc;
      if (topToc is Map) {
        for (final k in ['url', 'tocUrl', 'value', 'rule']) {
          final v = topToc[k];
          if (v is String && v.isNotEmpty) return v;
        }
      }
      final bookInfo = _parseRuleDynamic(json['ruleBookInfo']);
      if (bookInfo != null) {
        final tUrl = bookInfo['tocUrl'];
        if (tUrl is String && tUrl.isNotEmpty) return tUrl;
      }
      return null;
    }

    return ShuyuanSource(
      bookSourceName: json['bookSourceName'] as String? ?? '',
      bookSourceUrl: json['bookSourceUrl'] as String? ?? '',
      bookSourceType: _asInt(json['bookSourceType']) ?? 0,
      bookSourceGroup: json['bookSourceGroup'] as String?,
      bookSourceComment: json['bookSourceComment'] as String?,
      enabled: json['enabled'] as bool? ?? true,
      searchUrl: json['searchUrl'] as String?,
      exploreUrl: json['exploreUrl'] as String?,
      // 部分社区源把 header 写成对象形态（{"Referer": ...}），统一转 JSON
      // 字符串；此前 `as String?` 会抛 TypeError 导致整源被静默跳过。
      header: _asJsString(json['header']),
      tocUrl: resolveTocUrl(),
      ruleSearch: _parseRuleDynamic(json['ruleSearch']),
      ruleBookInfo: _parseRuleDynamic(json['ruleBookInfo']),
      ruleToc: _parseRuleDynamic(json['ruleToc']),
      ruleContent: _parseRuleDynamic(json['ruleContent']),
      ruleExplore: _parseRuleDynamic(json['ruleExplore']),
      bookUrlPattern: json['bookUrlPattern'] as String?,
      customOrder: _asInt(json['customOrder']) ?? 0,
      enabledExplore: json['enabledExplore'] as bool?,
      jsLib: _asJsString(json['jsLib']),
      enabledCookieJar: json['enabledCookieJar'] as bool?,
      concurrentRate: _asJsString(json['concurrentRate']),
      loginUrl: _asJsString(json['loginUrl']),
      loginUi: _asJsString(json['loginUi']),
      loginCheckJs: _asJsString(json['loginCheckJs']),
      coverDecodeJs: _asJsString(json['coverDecodeJs']),
      variableComment: _asJsString(json['variableComment']),
      lastUpdateTime: _asInt(json['lastUpdateTime']) ?? 0,
      respondTime: _asInt(json['respondTime']) ?? 180000,
      weight: _asInt(json['weight']) ?? 0,
      exploreScreen: _asJsString(json['exploreScreen']),
      eventListener: json['eventListener'] == true,
      customButton: json['customButton'] == true,
      // 整图保留原始 JSON：导入不丢字段（含未知扩展）的根本保证。
      raw: json,
      filters: _parseRuleDynamic(json['filters']),
      homeSections: _parseHomeSections(json['homeSections']),
    );
  }

  Map<String, dynamic> toJson() => {
        'bookSourceName': bookSourceName,
        'bookSourceUrl': bookSourceUrl,
        'bookSourceType': bookSourceType,
        if (bookSourceGroup != null) 'bookSourceGroup': bookSourceGroup,
        if (bookSourceComment != null) 'bookSourceComment': bookSourceComment,
        'enabled': enabled,
        if (searchUrl != null) 'searchUrl': searchUrl,
        if (exploreUrl != null) 'exploreUrl': exploreUrl,
        if (header != null) 'header': header,
        if (tocUrl != null) 'tocUrl': tocUrl,
        if (ruleSearch != null) 'ruleSearch': ruleSearch,
        if (ruleBookInfo != null) 'ruleBookInfo': ruleBookInfo,
        if (ruleToc != null) 'ruleToc': ruleToc,
        if (ruleContent != null) 'ruleContent': ruleContent,
        if (ruleExplore != null) 'ruleExplore': ruleExplore,
        if (bookUrlPattern != null) 'bookUrlPattern': bookUrlPattern,
        if (customOrder != 0) 'customOrder': customOrder,
        if (enabledExplore != null) 'enabledExplore': enabledExplore,
        if (jsLib != null) 'jsLib': jsLib,
        if (enabledCookieJar != null) 'enabledCookieJar': enabledCookieJar,
        if (concurrentRate != null) 'concurrentRate': concurrentRate,
        if (loginUrl != null) 'loginUrl': loginUrl,
        if (loginUi != null) 'loginUi': loginUi,
        if (loginCheckJs != null) 'loginCheckJs': loginCheckJs,
        if (coverDecodeJs != null) 'coverDecodeJs': coverDecodeJs,
        if (variableComment != null) 'variableComment': variableComment,
        if (lastUpdateTime != 0) 'lastUpdateTime': lastUpdateTime,
        if (respondTime != 180000) 'respondTime': respondTime,
        if (weight != 0) 'weight': weight,
        if (exploreScreen != null) 'exploreScreen': exploreScreen,
        if (eventListener) 'eventListener': eventListener,
        if (customButton) 'customButton': customButton,
        if (filters != null) 'filters': filters,
        if (homeSections != null) 'homeSections': homeSections,
      };
}

/// int 容错解析：legado JSON 里数值字段可能来成 num/double/字符串。
int? _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

/// 结构体容错转字符串：legado 的 header/loginUi 等字段允许字符串或
/// 对象/数组形态，运行期模型统一按 String 承载——结构体 jsonEncode 后
/// 原样透传，避免 `as String?` 抛 TypeError 导致整源被静默跳过。
String? _asJsString(dynamic v) {
  if (v == null) return null;
  if (v is String) return v.isEmpty ? null : v;
  if (v is Map || v is List) {
    try {
      return json.encode(v);
    } catch (_) {
      return v.toString();
    }
  }
  return v.toString();
}

List<Map<String, dynamic>>? _parseHomeSections(dynamic val) {
  if (val == null) return null;
  if (val is List) {
    final result = <Map<String, dynamic>>[];
    for (final item in val) {
      if (item is Map<String, dynamic>) {
        result.add(item);
      } else if (item is Map) {
        result.add(Map<String, dynamic>.from(item.cast<String, dynamic>()));
      }
    }
    if (result.isNotEmpty) return result;
  }
  return null;
}

Map<String, dynamic>? _parseRuleDynamic(dynamic val) {
  if (val == null) return null;
  if (val is Map<String, dynamic>) return val;
  if (val is Map) return Map<String, dynamic>.from(val.cast<String, dynamic>());
  if (val is String) {
    final s = val.trim();
    if (s.isEmpty) return null;
    try {
      final decoded = json.decode(s);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded.cast<String, dynamic>());
      }
    } catch (_) {
      // 不是 JSON 字符串
    }
  }
  if (val is List) {
    for (final item in val) {
      if (item is Map<String, dynamic>) return item;
      if (item is Map) {
        return Map<String, dynamic>.from(item.cast<String, dynamic>());
      }
      if (item is String) {
        try {
          final decoded = json.decode(item);
          if (decoded is Map<String, dynamic>) return decoded;
          if (decoded is Map) {
            return Map<String, dynamic>.from(decoded.cast<String, dynamic>());
          }
        } catch (_) {}
      }
    }
  }
  return null;
}

class ShuyuanSourceService {
  final Dio _dio;

  ShuyuanSourceService()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          // 关键：强制以纯文本返回，避免服务端标 application/json 时 Dio 自动
          // 把响应体解码成 List/Map，导致 response.data 不再是 String，
          // 后续 _parseSourceContent 的 .trim() 抛 TypeError → 网络导入「解析不到任何内容」。
          responseType: ResponseType.plain,
          validateStatus: (status) => status != null && status < 500,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Accept': '*/*',
          },
        ));

  /// 从 URL 抓取书源列表。
  Future<List<ShuyuanSource>> fetchSourcesFromUrl(String url) async {
    final resolvedUrl = _resolveUrl(url);
    final response = await _dio.get<dynamic>(resolvedUrl);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    // 统一为字符串：responseType=plain 时已是 String；若个别环境仍返回
    // 已解码对象（List/Map），重新序列化回 JSON 文本再交给解析器。
    final raw = response.data;
    final content = _coerceToString(raw);
    return parseSourcesInBackground(content);
  }

  /// 将 Dio 响应体统一转为字符串：已解码对象重新序列化为 JSON 文本。
  static String _coerceToString(dynamic raw) {
    if (raw == null) return '';
    if (raw is String) return raw;
    if (raw is List || raw is Map) {
      try {
        return json.encode(raw);
      } catch (_) {
        return raw.toString();
      }
    }
    return raw.toString();
  }

  /// 从本地文件读取书源列表。
  Future<List<ShuyuanSource>> fetchSourcesFromFile(String filePath) async {
    final file = File(filePath);
    final content = await file.readAsString();
    return parseSourcesInBackground(content);
  }

  /// 解析书源内容字符串。
  List<ShuyuanSource> parseSources(String content) {
    return _parseSourceContent(content);
  }

  /// 后台 isolate 版解析：社区书源文件可达数 MB、上千源，主线程
  /// jsonDecode + 逐源转换是秒级冻结，导入页统一走本入口。
  ///
  /// 解析为纯函数（无网络、无共享状态），跨 isolate 安全。
  static Future<List<ShuyuanSource>> parseSourcesInBackground(
    String content,
  ) =>
      compute(_parseSourcesIsolate, content);

  static List<ShuyuanSource> _parseSourcesIsolate(String content) =>
      ShuyuanSourceService().parseSources(content);

  /// 处理 `xiaoshuo://import/bookSource?src=...` 形式的导入 URL。
  String _resolveUrl(String url) {
    if (url.startsWith('xiaoshuo://') || url.startsWith('shuyuan://')) {
      try {
        final uri = Uri.parse(url);
        final src = uri.queryParameters['src'];
        if (src != null && src.isNotEmpty) {
          return Uri.decodeFull(src);
        }
      } catch (_) {}

      final match = RegExp(r'src=([^&]+)').firstMatch(url);
      if (match != null) {
        return Uri.decodeFull(match.group(1)!);
      }
    }
    return url;
  }

  List<ShuyuanSource> _parseSourceContent(dynamic content) {
    var text = _coerceToString(content).replaceAll('\uFEFF', '').trim();

    // 兼容粘贴站常见的 ```json ... ``` 代码围栏：取出围栏内的 JSON 文本。
    final fenceMatch = RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false)
        .firstMatch(text);
    if (fenceMatch != null) {
      final inner = fenceMatch.group(1)!.trim();
      if (inner.isNotEmpty) text = inner;
    }

    if (text.isEmpty) return const <ShuyuanSource>[];

    if (text.startsWith('<')) {
      return _parseXml(text);
    }

    if (text.startsWith('[')) {
      return _parseJsonArray(text);
    }

    if (text.startsWith('{')) {
      final single = _parseSingleSource(text);
      return single != null ? [single] : <ShuyuanSource>[];
    }

    // 兜底：从内容中提取首个 JSON 数组（部分页面把书源包在 <pre>/script 里）
    final jsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(text);
    if (jsonMatch != null) {
      return _parseJsonArray(jsonMatch.group(0)!);
    }

    // 兜底：按行解析 NDJSON
    final sources = <ShuyuanSource>[];
    for (final line in LineSplitter.split(content)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('{')) {
        final s = _parseSingleSource(trimmed);
        if (s != null) sources.add(s);
      }
    }
    return sources;
  }

  List<ShuyuanSource> _parseJsonArray(String jsonStr) {
    try {
      final decoded = json.decode(jsonStr);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map((e) => ShuyuanSource.fromJson(e))
            .toList();
      }

      if (decoded is Map<String, dynamic>) {
        // 常见包装键
        for (final key in ['bookSources', 'bookSource', 'data', 'sources', 'items']) {
          if (decoded.containsKey(key)) {
            final arr = decoded[key];
            if (arr is List) {
              return arr
                  .whereType<Map<String, dynamic>>()
                  .map((e) => ShuyuanSource.fromJson(e))
                  .toList();
            }
          }
        }
        // 视为单个书源对象
        return [ShuyuanSource.fromJson(decoded)];
      }
    } catch (_) {}
    return <ShuyuanSource>[];
  }

  ShuyuanSource? _parseSingleSource(String jsonStr) {
    try {
      final decoded = json.decode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        return ShuyuanSource.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  List<ShuyuanSource> _parseXml(String xmlStr) {
    final sources = <ShuyuanSource>[];
    try {
      final document = XmlDocument.parse(xmlStr);
      final elements = document.findAllElements('source').toList()
        ..addAll(document.findAllElements('bookSource'));
      for (final el in elements) {
        final map = <String, dynamic>{};
        for (final child in el.childElements) {
          final tag = child.name.local;
          final val = child.innerText;
          if (val.isNotEmpty) map[tag] = val;
        }
        if (map.isNotEmpty) {
          sources.add(ShuyuanSource.fromJson(map));
        }
      }
    } catch (_) {}
    return sources;
  }

  void close() {
    _dio.close();
  }
}
