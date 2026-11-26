/// 章节模型：承载章节 URL、标题、索引及卷/VIP/付费标记。
library;

import 'dart:convert';

class XiaoshuoBookChapter {
  String bookUrl;
  String url;
  String title;
  int index;
  bool isVolume;
  bool isVip;
  bool isPay;
  String? tag;
  String? wordCount;

  /// 段评图标地址（legado `reviewImg`）。
  String? reviewImg;

  /// 目录页最终地址，用于拼接相对章节地址（legado `BookChapter.baseUrl`）。
  String? baseUrl;
  String? variable;
  Map<String, String> variableMap = {};

  // ── legado `BookChapter` 扩展字段（F3）──
  /// 目录层级（EPUB/多级目录用，0 = 一级）。
  int tocLevel;

  /// 章节真实资源地址（音频/文件类书源；legado `BookChapter.resourceUrl`）。
  String? resourceUrl;

  /// 正文在源文件中的起止偏移（EPUB/本地文件续读定位）。
  int start;
  int end;
  String? startFragmentId;
  String? endFragmentId;

  XiaoshuoBookChapter({
    required this.bookUrl,
    this.url = '',
    this.title = '',
    this.index = 0,
    this.isVolume = false,
    this.isVip = false,
    this.isPay = false,
    this.tag,
    this.wordCount,
    this.reviewImg,
    this.baseUrl,
    this.variable,
    this.tocLevel = 0,
    this.resourceUrl,
    this.start = 0,
    this.end = 0,
    this.startFragmentId,
    this.endFragmentId,
  });

  factory XiaoshuoBookChapter.fromJson(Map<String, dynamic> json) {
    final chapter = XiaoshuoBookChapter(
      bookUrl: json['bookUrl'] as String? ?? '',
      url: json['url'] as String? ?? '',
      title: json['title'] as String? ?? '',
      index: json['index'] as int? ?? 0,
      isVolume: json['isVolume'] as bool? ?? false,
      isVip: json['isVip'] as bool? ?? false,
      isPay: json['isPay'] as bool? ?? false,
      tag: json['tag'] as String?,
      wordCount: json['wordCount'] as String?,
      reviewImg: json['reviewImg'] as String?,
      baseUrl: json['baseUrl'] as String?,
      variable: json['variable'] as String?,
      tocLevel: json['tocLevel'] as int? ?? 0,
      resourceUrl: json['resourceUrl'] as String?,
      start: json['start'] as int? ?? 0,
      end: json['end'] as int? ?? 0,
      startFragmentId: json['startFragmentId'] as String?,
      endFragmentId: json['endFragmentId'] as String?,
    );
    // 只有 `variable` 串的旧数据：回填变量表（目录期 @put 的签名参数）。
    chapter._ensureVariableMap();
    return chapter;
  }

  Map<String, dynamic> toJson() => {
        'bookUrl': bookUrl,
        'url': url,
        'title': title,
        'index': index,
        'isVolume': isVolume,
        'isVip': isVip,
        'isPay': isPay,
        if (tag != null) 'tag': tag,
        if (wordCount != null) 'wordCount': wordCount,
        if (reviewImg != null) 'reviewImg': reviewImg,
        if (baseUrl != null) 'baseUrl': baseUrl,
        if (variable != null) 'variable': variable,
        if (tocLevel != 0) 'tocLevel': tocLevel,
        if (resourceUrl != null) 'resourceUrl': resourceUrl,
        if (start != 0) 'start': start,
        if (end != 0) 'end': end,
        if (startFragmentId != null) 'startFragmentId': startFragmentId,
        if (endFragmentId != null) 'endFragmentId': endFragmentId,
      };

  /// 对齐 legado `BookChapter.getAbsoluteURL()`：
  /// `,{...}` 选项段不参与地址拼接，拼接后原样接回。
  String getAbsoluteURL({String? redirectUrl}) {
    final base = (baseUrl != null && baseUrl!.isNotEmpty)
        ? baseUrl!
        : (redirectUrl ?? '');
    // 二级目录解析的卷链接为空 返回目录页的链接
    if (isVolume && title.isNotEmpty && url.startsWith(title)) return base;
    final match = _paramPattern.firstMatch(url);
    final urlBefore = match == null ? url : url.substring(0, match.start);
    final absolute = resolveAgainst(base, urlBefore);
    if (match == null) return absolute;
    return '$absolute,${url.substring(match.end)}';
  }

  /// 写入章节变量（legado `BookChapter.putVariable`）：`null` 删除键，
  /// 其余写入后立即把 `variable`（唯一入库字段）同步为 JSON 串。
  void putVariable(String key, String? value) {
    if (value == null) {
      variableMap.remove(key);
    } else {
      variableMap[key] = value;
    }
    variable = variableMap.isEmpty ? null : jsonEncode(variableMap);
  }

  void _ensureVariableMap() {
    if (variableMap.isNotEmpty) return;
    final raw = variable;
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((k, v) {
          if (v != null) variableMap[k.toString()] = v.toString();
        });
      }
    } catch (_) {}
  }

  String getVariable(String key) {
    _ensureVariableMap();
    return variableMap[key] ?? '';
  }

  /// 章节标题展示形态（对齐 legado `BookChapter.getDisplayTitle` 的清洗段）：
  /// 去掉 `\r\n` 换行并把连续空白折叠为单个空格；目录/阅读器统一走这里，
  /// 避免源把标题写成多行时界面出现断行。
  ///
  /// 繁简转换与用户替换规则属阅读器偏好，仍在展示层按当前偏好叠加
  /// （本方法只做与偏好无关的清洗，保持模型层无 UI 依赖）。
  String getDisplayTitle() => title.replaceAll(_newlinePattern, '').trim();

  static final RegExp _paramPattern = RegExp(r'\s*,\s*(?=\{)');

  static final RegExp _newlinePattern = RegExp(r'\r\n|\r|\n');

  /// 任意 `data:` URI 原样保留（不能按相对路径拼接）。
  /// 旧实现只认 `data:...;base64,`，`data:text/plain,...` 会被 Uri.resolve
  /// 当相对地址改写。
  static final RegExp _dataUriPattern = RegExp(r'^data:', caseSensitive: false);

  /// 对齐 legado `NetworkUtils.getAbsoluteURL(baseURL, relativePath)`。
  static String resolveAgainst(String base, String relative) {
    final rel = relative.trim();
    if (base.isEmpty) return rel;
    final comma = base.indexOf(',');
    final baseForParse = comma >= 0 ? base.substring(0, comma) : base;
    final baseUri = Uri.tryParse(baseForParse);
    if (baseUri == null || !baseUri.hasScheme) return rel;
    final lower = rel.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) return rel;
    if (_dataUriPattern.hasMatch(rel)) return rel;
    if (rel.startsWith('javascript')) return '';
    try {
      return baseUri.resolve(rel).toString();
    } catch (_) {
      return rel;
    }
  }
}
