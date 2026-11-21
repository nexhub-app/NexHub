/// 剧集 / 章节统一模型（媒体叫「集」，漫画/小说叫「章」）。
/// 同一结构承载播放地址与所属播放线路。
library;

class Episode {
  final String id;
  final String title;
  final String url;
  final String? lineName; // 网站播放线路名（线路一/二/三…）

  /// 弹弹play 剧集 ID（由弹幕自动匹配填充，best-effort）。
  final int? dandanplayEpisodeId;

  /// Bilibili 弹幕 cid（由弹幕自动匹配填充，best-effort）。
  final int? bilibiliCid;

  /// Bangumi 番剧 ID（预留，供未来 Bangumi 集成使用）。
  final int? bangumiId;

  /// Direct danmaku URL (filled at detail route stage, best-effort).
  /// Takes highest priority in DanmakuRepository fallback chain.
  final String? danmakuUrl;

  /// 章节/剧集上传时间（用于排序"按更新时间"）。
  final DateTime? updatedAt;

  /// 章节/剧集序号（用于"显示序号"和"按序号排序"）。
  final int? number;

  /// 书源章节是否为 VIP 章节（legado BookChapter.isVip）。
  final bool isVip;

  /// 书源章节是否已购买（legado BookChapter.isPay）。
  final bool isPay;

  const Episode({
    required this.id,
    required this.title,
    required this.url,
    this.lineName,
    this.dandanplayEpisodeId,
    this.bilibiliCid,
    this.bangumiId,
    this.danmakuUrl,
    this.updatedAt,
    this.number,
    this.isVip = false,
    this.isPay = false,
  });

  /// 复制并覆盖部分字段（弹幕自动匹配时用于生成带 ID 的新实例）。
  Episode copyWith({
    String? id,
    String? title,
    String? url,
    String? lineName,
    int? dandanplayEpisodeId,
    int? bilibiliCid,
    int? bangumiId,
    String? danmakuUrl,
    DateTime? updatedAt,
    int? number,
    bool? isVip,
    bool? isPay,
  }) =>
      Episode(
        id: id ?? this.id,
        title: title ?? this.title,
        url: url ?? this.url,
        lineName: lineName ?? this.lineName,
        dandanplayEpisodeId: dandanplayEpisodeId ?? this.dandanplayEpisodeId,
        bilibiliCid: bilibiliCid ?? this.bilibiliCid,
        bangumiId: bangumiId ?? this.bangumiId,
        danmakuUrl: danmakuUrl ?? this.danmakuUrl,
        updatedAt: updatedAt ?? this.updatedAt,
        number: number ?? this.number,
        isVip: isVip ?? this.isVip,
        isPay: isPay ?? this.isPay,
      );

  factory Episode.fromJson(Map<String, dynamic> json) => Episode(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        url: json['url'] as String? ?? '',
        lineName: json['lineName'] as String?,
        dandanplayEpisodeId: (json['dandanplayEpisodeId'] as num?)?.toInt(),
        bilibiliCid: (json['bilibiliCid'] as num?)?.toInt(),
        bangumiId: (json['bangumiId'] as num?)?.toInt(),
        danmakuUrl: json['danmakuUrl'] as String?,
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'] as String)
            : null,
        number: (json['number'] as num?)?.toInt(),
        isVip: json['isVip'] as bool? ?? false,
        isPay: json['isPay'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'url': url,
        if (lineName != null) 'lineName': lineName,
        if (dandanplayEpisodeId != null) 'dandanplayEpisodeId': dandanplayEpisodeId,
        if (bilibiliCid != null) 'bilibiliCid': bilibiliCid,
        if (bangumiId != null) 'bangumiId': bangumiId,
        if (danmakuUrl != null) 'danmakuUrl': danmakuUrl,
        if (updatedAt != null)
          'updatedAt': updatedAt!.toIso8601String(),
        if (number != null) 'number': number,
        if (isVip) 'isVip': isVip,
        if (isPay) 'isPay': isPay,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Episode &&
          other.id == id &&
          other.url == url &&
          other.lineName == lineName;

  @override
  int get hashCode => Object.hash(id, url, lineName);
}

/// 单条可播放线路（同一剧集可能有多条 CDN / 镜像地址，供播放器「线路」切换）。
class VideoLine {
  final String name;
  final String url;
  final Map<String, String>? headers;

  const VideoLine({required this.name, required this.url, this.headers});

  factory VideoLine.fromJson(Map<String, dynamic> json) => VideoLine(
        name: json['name'] as String? ?? '',
        url: json['url'] as String,
        headers: (json['headers'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'url': url,
        if (headers != null) 'headers': headers,
      };
}

/// 视频解析结果（直链 MP4/M3U8 / DASH 等）。
class VideoResult {
  final String url;
  final String? type; // mp4 | m3u8 | dash | ...

  /// 播放该地址所需的 HTTP 请求头（反盗链 Referer / UA 等）。
  /// 抓取 m3u8 文本时需要带，播放器真正打开地址（mpv 拉分片）时
  /// 同样必须带上，否则 CDN（如 v5.lbv*.com）返回 403，解不出任何帧 → 黑屏。
  final Map<String, String>? headers;

  /// 同源多线路（不同 CDN / 镜像地址）。非空时播放器以此填充「线路」列表，
  /// 用户在播放页「选集 / 线路」面板中切换；为空则回退到单一 [url]。
  /// 由解析器在源提供多地址时填充（共创式：不针对单个源写死）。
  final List<VideoLine> lines;

  /// 内嵌歌词（LRC 文本）。音频源在正文 `subContent` 里产出，解析层随
  /// 直链一并回传；播放器据此呈现带时间轴的歌词。非音频/无歌词为 null。
  final String? lyric;

  const VideoResult({
    required this.url,
    this.type,
    this.headers,
    this.lines = const <VideoLine>[],
    this.lyric,
  });

  factory VideoResult.fromJson(Map<String, dynamic> json) => VideoResult(
        url: json['url'] as String,
        type: json['type'] as String?,
        headers: (json['headers'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ),
        lines: (json['lines'] as List?)
                ?.map((e) => VideoLine.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const <VideoLine>[],
        lyric: json['lyric'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        if (type != null) 'type': type,
        if (headers != null) 'headers': headers,
        if (lines.isNotEmpty)
          'lines': lines.map((l) => l.toJson()).toList(),
        if (lyric != null) 'lyric': lyric,
      };
}
