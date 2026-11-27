/// 书籍数据模型：承载书籍详情、目录 URL、变量等运行时状态。
library;

import 'dart:convert';

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

  // ── legado `Book` 实体字段（F2：书源脚本 `book.<field>` 的读写面）──
  /// 书源地址（legado `Book.origin`）；与 bookSourceUrl 同义但随书持久化。
  String? origin;

  /// 书源名称（legado `Book.originName`）。
  String? originName;

  /// 书源排序权重（legado `Book.originOrder`）。
  int originOrder;

  /// 变量 JSON 串（legado `Book.variable`）：variableMap 的序列化形态。
  String? variable;

  /// 书籍分类位掩码（legado `Book.fixedType`）：0 表示跟随书源类型。
  int fixedType;

  /// 目录章节总数（legado `Book.totalChapterNum`）。
  int totalChapterNum;

  /// 最新章节标题（legado `Book.latestChapterTitle`，与 lastChapter 同源）。
  String? latestChapterTitle;

  /// 最新章节时间戳（legado `Book.latestChapterTime`）。
  int latestChapterTime;

  /// 阅读进度：章节序号/标题/位置（legado `Book.durChapter*`）。
  int durChapterIndex;
  String durChapterTitle;
  int durChapterPos;

  /// 分组 / 自定义标签 / 自定义简介 / 自定义封面（legado `Book.group` 等）。
  String? group;
  String? customTag;
  String? customIntro;
  String? customCoverUrl;

  /// 是否允许更新（legado `Book.canUpdate`）。
  bool canUpdate;

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
    this.origin,
    this.originName,
    this.originOrder = 0,
    this.variable,
    this.fixedType = 0,
    this.totalChapterNum = 0,
    this.latestChapterTitle,
    this.latestChapterTime = 0,
    this.durChapterIndex = 0,
    this.durChapterTitle = '',
    this.durChapterPos = 0,
    this.group,
    this.customTag,
    this.customIntro,
    this.customCoverUrl,
    this.canUpdate = true,
  });

  factory XiaoshuoBook.fromJson(Map<String, dynamic> json) {
    final book = XiaoshuoBook(
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
      origin: json['origin'] as String?,
      originName: json['originName'] as String?,
      originOrder: json['originOrder'] as int? ?? 0,
      variable: json['variable'] as String?,
      fixedType: json['fixedType'] as int? ?? 0,
      totalChapterNum: json['totalChapterNum'] as int? ?? 0,
      latestChapterTitle: json['latestChapterTitle'] as String?,
      latestChapterTime: json['latestChapterTime'] as int? ?? 0,
      durChapterIndex: json['durChapterIndex'] as int? ?? 0,
      durChapterTitle: json['durChapterTitle'] as String? ?? '',
      durChapterPos: json['durChapterPos'] as int? ?? 0,
      group: json['group'] as String?,
      customTag: json['customTag'] as String?,
      customIntro: json['customIntro'] as String?,
      customCoverUrl: json['customCoverUrl'] as String?,
      canUpdate: json['canUpdate'] as bool? ?? true,
    );
    // 只有 `variable` 串的旧存档：回填变量表，目录/正文期的 @get 才命中。
    book._ensureVariableMap();
    return book;
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
        if (origin != null) 'origin': origin,
        if (originName != null) 'originName': originName,
        if (originOrder != 0) 'originOrder': originOrder,
        if (variable != null) 'variable': variable,
        if (fixedType != 0) 'fixedType': fixedType,
        if (totalChapterNum != 0) 'totalChapterNum': totalChapterNum,
        if (latestChapterTitle != null) 'latestChapterTitle': latestChapterTitle,
        if (latestChapterTime != 0) 'latestChapterTime': latestChapterTime,
        if (durChapterIndex != 0) 'durChapterIndex': durChapterIndex,
        if (durChapterTitle.isNotEmpty) 'durChapterTitle': durChapterTitle,
        if (durChapterPos != 0) 'durChapterPos': durChapterPos,
        if (group != null) 'group': group,
        if (customTag != null) 'customTag': customTag,
        if (customIntro != null) 'customIntro': customIntro,
        if (customCoverUrl != null) 'customCoverUrl': customCoverUrl,
        if (!canUpdate) 'canUpdate': canUpdate,
      };

  /// 写入变量（对齐 legado `RuleDataInterface.putVariable`）：
  /// - `null` = 删除该键（源用「置空即删除」写法时不再残留旧值）；
  /// - 其余写入内存表，并把 `variable`（legado 唯一入库字段）同步成 JSON
  ///   串，保证 variableMap 与序列化形态一致（旧实现只写 map，落盘后丢
  ///   目录期 `@put` 的签名参数）。
  ///
  /// 大变量（≥10000 字符）NexHub 仍驻内存：legado 转存文件是为了避开 JVM
  /// 单机长驻的内存压力，Flutter 侧同步文件 IO 会阻塞解析所在的 UI
  /// isolate（真机卡顿），取舍见审计文档。
  void putVariable(String key, String? value) {
    if (value == null) {
      variableMap.remove(key);
    } else {
      variableMap[key] = value;
    }
    _syncVariableJson();
  }

  /// `variable` 与 `variableMap` 对齐（空表时清空 `variable`）。
  void _syncVariableJson() {
    variable = variableMap.isEmpty ? null : jsonEncode(variableMap);
  }

  /// 旧存档/备份只有 `variable` JSON：读取时回填内存表。
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

  bool get isOnLineTxt => type == 0 && bookUrl.startsWith('http');

  // ── 类型判定（legado `BookType` 位掩码 vs 本应用 0..4 编号的兼容层）──
  //
  // 本应用的历史编号：0 文本 / 1 音频 / 2 图片 / 3 文件 / 4 视频；
  // legado 是位掩码：4 视频 / 8 文本 / 32 音频 / 64 图片 / 128 文件源。
  // 书源仍可能用 `bookSourceType` 编号落库，故两个口径都认。
  bool _hasBit(int bit) => (type & bit) == bit;

  /// 文件类书源（legado `Book.isWebFile`）。
  bool get isWebFileBook => type == 3 || _hasBit(128);

  /// 在线文本（legado `Book.isOnLineTxt`：text 位且非本地）。
  bool get isOnLineTxtBook =>
      type == 0 ? bookUrl.startsWith('http') : _hasBit(8);

  /// 有声书（legado `Book.isAudio`）。
  bool get isAudioBook => type == 1 || _hasBit(32);

  /// 视频书（legado `Book.isVideo`）。
  bool get isVideoBook => type == 4 || _hasBit(4);
}
