/// 小说书源数据模型，承载书源元信息与各路由规则。
library;

import 'dart:convert';

import 'rule_search.dart';
import 'rule_toc.dart';
import 'rule_content.dart';
import 'rule_book_info.dart';
import 'rule_explore.dart';
import 'rule_review.dart';

class XiaoshuoBookSource {
  String bookSourceUrl;
  String bookSourceName;
  String? bookSourceGroup;
  int bookSourceType;
  String? bookUrlPattern;
  int customOrder;
  bool enabled;
  bool enabledExplore;
  String? jsLib;
  bool enabledCookieJar;
  String? concurrentRate;
  String? header;
  String? loginUrl;
  String? loginUi;
  String? loginCheckJs;
  String? coverDecodeJs;
  String? bookSourceComment;
  String? variableComment;
  int lastUpdateTime;
  int respondTime;
  int weight;
  String? exploreUrl;
  String? exploreScreen;
  bool eventListener;
  bool customButton;
  ExploreRule? ruleExplore;
  String? searchUrl;
  SearchRule? ruleSearch;
  BookInfoRule? ruleBookInfo;
  TocRule? ruleToc;
  ContentRule? ruleContent;

  /// 段评规则（legado `BookSource.ruleReview: ReviewRule?`）。
  ///
  /// 以原始 Map 承载（导入/导出往返不丢未知字段），需要按字段取值时用
  /// [getReviewRule] 解析为 [ReviewRule]；渲染层阅读器「段评」面板消费。
  Map<String, dynamic>? ruleReview;

  /// 首页模块定义（legado `BookSource.homepageModules: String?`，JSON 数组
  /// 文本）：原样保留，避免源数据往返损坏。
  String? homepageModules;

  /// 解析器配置（保留字段）。
  Map<String, dynamic>? parserConfig;

  /// 子分类检测开关。
  bool subCategoryDetection;

  /// 过滤关键词。
  List<String> filterKeywords;

  /// 子分类 URL 模式。
  List<String> subCategoryPatterns;

  XiaoshuoBookSource({
    this.bookSourceUrl = '',
    this.bookSourceName = '',
    this.bookSourceGroup,
    this.bookSourceType = 0,
    this.bookUrlPattern,
    this.customOrder = 0,
    this.enabled = true,
    this.enabledExplore = true,
    this.jsLib,
    this.enabledCookieJar = true,
    this.concurrentRate,
    this.header,
    this.loginUrl,
    this.loginUi,
    this.loginCheckJs,
    this.coverDecodeJs,
    this.bookSourceComment,
    this.variableComment,
    this.lastUpdateTime = 0,
    this.respondTime = 180000,
    this.weight = 0,
    this.exploreUrl,
    this.exploreScreen,
    this.eventListener = false,
    this.customButton = false,
    this.ruleExplore,
    this.searchUrl,
    this.ruleSearch,
    this.ruleBookInfo,
    this.ruleToc,
    this.ruleContent,
    this.ruleReview,
    this.homepageModules,
    this.parserConfig,
    this.subCategoryDetection = true,
    this.filterKeywords = const [],
    this.subCategoryPatterns = const [],
  });

  String get key => bookSourceUrl;
  String get tag => bookSourceName;

  /// 有效源判据：含任一可解析规则即可。
  ///
  /// `ruleBookInfo` 必须计入——文件类源（`bookSourceType=3`）只有
  /// `ruleBookInfo.downloadUrls`，旧判据会把它整条判为无效，与
  /// `ShuyuanSource.isValid` 口径分裂（导入可用、运行期被拒）。
  bool get isValid =>
      bookSourceName.isNotEmpty &&
      bookSourceUrl.isNotEmpty &&
      (ruleSearch != null ||
          ruleBookInfo != null ||
          ruleToc != null ||
          ruleContent != null ||
          ruleExplore != null);

  SearchRule getSearchRule() {
    ruleSearch ??= SearchRule();
    return ruleSearch!;
  }

  ExploreRule getExploreRule() {
    ruleExplore ??= ExploreRule();
    return ruleExplore!;
  }

  BookInfoRule getBookInfoRule() {
    ruleBookInfo ??= BookInfoRule();
    return ruleBookInfo!;
  }

  TocRule getTocRule() {
    ruleToc ??= TocRule();
    return ruleToc!;
  }

  ContentRule getContentRule() {
    ruleContent ??= ContentRule();
    return ruleContent!;
  }

  ReviewRule getReviewRule() =>
      ReviewRule.fromJson(ruleReview ?? const <String, dynamic>{});

  factory XiaoshuoBookSource.fromJson(Map<String, dynamic> json) {
    return XiaoshuoBookSource(
      bookSourceUrl: json['bookSourceUrl'] as String? ?? '',
      bookSourceName: json['bookSourceName'] as String? ?? '',
      bookSourceGroup: json['bookSourceGroup'] as String?,
      bookSourceType: json['bookSourceType'] as int? ?? 0,
      bookUrlPattern: json['bookUrlPattern'] as String?,
      customOrder: json['customOrder'] as int? ?? 0,
      enabled: json['enabled'] as bool? ?? true,
      enabledExplore: json['enabledExplore'] as bool? ?? true,
      jsLib: json['jsLib'] as String?,
      enabledCookieJar: json['enabledCookieJar'] as bool? ?? true,
      concurrentRate: json['concurrentRate']?.toString(),
      header: json['header'] as String?,
      loginUrl: json['loginUrl'] as String?,
      loginUi: json['loginUi'] as String?,
      loginCheckJs: json['loginCheckJs'] as String?,
      coverDecodeJs: json['coverDecodeJs'] as String?,
      bookSourceComment: json['bookSourceComment'] as String?,
      variableComment: json['variableComment'] as String?,
      lastUpdateTime: json['lastUpdateTime'] as int? ?? 0,
      respondTime: json['respondTime'] as int? ?? 180000,
      weight: json['weight'] as int? ?? 0,
      exploreUrl: json['exploreUrl'] as String?,
      exploreScreen: json['exploreScreen'] as String?,
      eventListener: json['eventListener'] as bool? ?? false,
      customButton: json['customButton'] as bool? ?? false,
      ruleExplore: _parseExploreRule(json['ruleExplore']),
      searchUrl: json['searchUrl'] as String?,
      ruleSearch: _parseSearchRule(json['ruleSearch']),
      ruleBookInfo: _parseBookInfoRule(json['ruleBookInfo']),
      ruleToc: _parseTocRule(json['ruleToc']),
      ruleContent: _parseContentRule(json['ruleContent']),
      ruleReview: _parseRuleDynamic(json['ruleReview']),
      homepageModules: _parseModulesString(json['homepageModules']),
      parserConfig: json['parser'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['parser'] as Map)
          : null,
      subCategoryDetection: json['subCategoryDetection'] as bool? ?? true,
      filterKeywords: _parseStringList(json['filterKeywords']),
      subCategoryPatterns: _parseStringList(json['subCategoryPatterns']),
    );
  }

  Map<String, dynamic> toJson() => {
        'bookSourceUrl': bookSourceUrl,
        'bookSourceName': bookSourceName,
        if (bookSourceGroup != null) 'bookSourceGroup': bookSourceGroup,
        'bookSourceType': bookSourceType,
        if (bookUrlPattern != null) 'bookUrlPattern': bookUrlPattern,
        'customOrder': customOrder,
        'enabled': enabled,
        'enabledExplore': enabledExplore,
        if (jsLib != null) 'jsLib': jsLib,
        'enabledCookieJar': enabledCookieJar,
        if (concurrentRate != null) 'concurrentRate': concurrentRate,
        if (header != null) 'header': header,
        if (loginUrl != null) 'loginUrl': loginUrl,
        if (loginUi != null) 'loginUi': loginUi,
        if (loginCheckJs != null) 'loginCheckJs': loginCheckJs,
        if (coverDecodeJs != null) 'coverDecodeJs': coverDecodeJs,
        if (bookSourceComment != null) 'bookSourceComment': bookSourceComment,
        if (variableComment != null) 'variableComment': variableComment,
        'lastUpdateTime': lastUpdateTime,
        'respondTime': respondTime,
        'weight': weight,
        if (exploreUrl != null) 'exploreUrl': exploreUrl,
        if (exploreScreen != null) 'exploreScreen': exploreScreen,
        if (eventListener) 'eventListener': eventListener,
        if (customButton) 'customButton': customButton,
        if (ruleExplore != null) 'ruleExplore': ruleExplore!.toJson(),
        if (searchUrl != null) 'searchUrl': searchUrl,
        if (ruleSearch != null) 'ruleSearch': ruleSearch!.toJson(),
        if (ruleBookInfo != null) 'ruleBookInfo': ruleBookInfo!.toJson(),
        if (ruleToc != null) 'ruleToc': ruleToc!.toJson(),
        if (ruleContent != null) 'ruleContent': ruleContent!.toJson(),
        if (ruleReview != null) 'ruleReview': ruleReview,
        if (homepageModules != null) 'homepageModules': homepageModules,
        if (parserConfig != null) 'parser': parserConfig,
        'subCategoryDetection': subCategoryDetection,
        if (filterKeywords.isNotEmpty) 'filterKeywords': filterKeywords,
        if (subCategoryPatterns.isNotEmpty)
          'subCategoryPatterns': subCategoryPatterns,
      };

  static ExploreRule? _parseExploreRule(dynamic val) {
    final map = _parseRuleDynamic(val);
    if (map is Map<String, dynamic>) return ExploreRule.fromJson(map);
    return null;
  }

  static SearchRule? _parseSearchRule(dynamic val) {
    final map = _parseRuleDynamic(val);
    if (map is Map<String, dynamic>) return SearchRule.fromJson(map);
    return null;
  }

  static BookInfoRule? _parseBookInfoRule(dynamic val) {
    final map = _parseRuleDynamic(val);
    if (map is Map<String, dynamic>) return BookInfoRule.fromJson(map);
    return null;
  }

  static TocRule? _parseTocRule(dynamic val) {
    final map = _parseRuleDynamic(val);
    if (map is Map<String, dynamic>) return TocRule.fromJson(map);
    return null;
  }

  static ContentRule? _parseContentRule(dynamic val) {
    final map = _parseRuleDynamic(val);
    if (map is Map<String, dynamic>) return ContentRule.fromJson(map);
    return null;
  }
}

List<String> _parseStringList(dynamic val) {
  if (val == null) return const [];
  if (val is List) {
    return val.whereType<String>().toList();
  }
  if (val is String) {
    return val.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }
  return const [];
}

dynamic _parseRuleDynamic(dynamic val) {
  if (val == null) return null;
  if (val is Map<String, dynamic>) return val;
  if (val is Map) return Map<String, dynamic>.from(val.cast());
  if (val is String && val.isNotEmpty) {
    try {
      // JSON 字符串解析：部分 Legado 书源将规则存储为 JSON 字符串而非 Map
      final decoded = jsonDecode(val);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded.cast());
    } catch (_) {}
  }
  if (val is List) {
    for (final item in val) {
      if (item is Map<String, dynamic>) return item;
      if (item is Map) return Map<String, dynamic>.from(item.cast());
    }
  }
  return null;
}

/// legado `homepageModules` 是 JSON 数组字符串；容错接受对象/数组形态，
/// 统一转为字符串承载（结构体原样序列化，避免 as String 抛 TypeError）。
String? _parseModulesString(dynamic val) {
  if (val == null) return null;
  if (val is String) return val.isEmpty ? null : val;
  if (val is Map || val is List) {
    try {
      return jsonEncode(val);
    } catch (_) {
      return val.toString();
    }
  }
  return val.toString();
}
