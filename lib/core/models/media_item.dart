/// 通用内容项模型。动漫/影视/漫画/小说共用同一结构，
/// 通过 [sourceType] 区分语义，避免为每种类型复制一套几乎相同的字段。
library;

import 'plugin_config.dart';

class MediaItem {
  final String id;
  final String title;
  final String? coverUrl;
  final String? detailUrl;
  final String? sourceId;
  final SourceType? sourceType;
  final String? description;
  final String? author;
  final String? director;
  final String? actors;
  final String? year;
  final List<String>? tags;
  final String? status; // 连载中 / 已完结
  final DateTime? updatedAt;
  final Map<String, dynamic>? extra;

  /// 字数（小说专属，如 "30万字" 或 "150000"）。
  final String? wordCount;

  /// Bangumi 番剧 ID（预留，供未来 Bangumi 集成使用）。
  final int? bangumiId;

  /// 系列的季列表（仅当源 detail 路由声明 `seasons` 选择器时填充）。
  /// 每个 [MediaItem] 表示一季，复用同一模型承载 id/title/cover/episodeCount。
  final List<MediaItem>? seasons;

  /// 季的剧集数（用于季卡片角标展示；null 表示未知）。
  final int? episodeCount;

  /// 详情页解析出的作者落地页链接（相对或绝对 URL）。用于"点作者名即按该作者检索"，
  /// 避免用中文作者名去撞站点拼音代号导致检索为空（多数漫画站作者页按拼音 slug 键控）。
  final String? authorUrl;

  /// 详情页解析出的标签落地页链接列表（相对或绝对 URL）。用于"点标签即按该标签检索"。
  final List<String>? tagUrls;

  const MediaItem({
    required this.id,
    required this.title,
    this.coverUrl,
    this.detailUrl,
    this.sourceId,
    this.sourceType,
    this.description,
    this.author,
    this.director,
    this.actors,
    this.year,
    this.tags,
    this.status,
    this.updatedAt,
    this.extra,
    this.wordCount,
    this.bangumiId,
    this.seasons,
    this.episodeCount,
    this.authorUrl,
    this.tagUrls,
  });

  MediaItem copyWith({
    String? id,
    String? title,
    String? coverUrl,
    String? detailUrl,
    String? sourceId,
    SourceType? sourceType,
    String? description,
    String? author,
    String? director,
    String? actors,
    String? year,
    List<String>? tags,
    String? status,
    DateTime? updatedAt,
    Map<String, dynamic>? extra,
    String? wordCount,
    int? bangumiId,
    List<MediaItem>? seasons,
    int? episodeCount,
    String? authorUrl,
    List<String>? tagUrls,
  }) =>
      MediaItem(
        id: id ?? this.id,
        title: title ?? this.title,
        coverUrl: coverUrl ?? this.coverUrl,
        detailUrl: detailUrl ?? this.detailUrl,
        sourceId: sourceId ?? this.sourceId,
        sourceType: sourceType ?? this.sourceType,
        description: description ?? this.description,
        author: author ?? this.author,
        director: director ?? this.director,
        actors: actors ?? this.actors,
        year: year ?? this.year,
        tags: tags ?? this.tags,
        status: status ?? this.status,
        updatedAt: updatedAt ?? this.updatedAt,
        extra: extra ?? this.extra,
        wordCount: wordCount ?? this.wordCount,
        bangumiId: bangumiId ?? this.bangumiId,
        seasons: seasons ?? this.seasons,
        episodeCount: episodeCount ?? this.episodeCount,
        authorUrl: authorUrl ?? this.authorUrl,
        tagUrls: tagUrls ?? this.tagUrls,
      );

  /// 跨字段搜索匹配（标题/作者/导演/演员/标签），供 ModuleSearchScreen 复用。
  bool matchesQuery(String query, {String? field}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    // 归一化：去掉空格，使"金庸"能匹配"金庸 著"、"金 庸"也能匹配"金庸"。
    final qNorm = q.replaceAll(RegExp(r'\s+'), '');
    final titleN = title.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final authorN =
        (author ?? '').toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final directorN =
        (director ?? '').toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final actorsN =
        (actors ?? '').toLowerCase().replaceAll(RegExp(r'\s+'), '');
    // 标签按逗号/顿号拆分后逐项归一化匹配（兼容"玄幻,武侠"这类多值）。
    final tagNorms = (tags ?? [])
        .expand((t) => t.split(RegExp(r'[,，、/|]')))
        .map((t) => t.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ''))
        .where((t) => t.isNotEmpty)
        .toList();
    final haystacks = <String>[
      titleN,
      authorN,
      directorN,
      actorsN,
      ...tagNorms,
    ];
    switch (field) {
      case 'title':
        return titleN.contains(qNorm);
      case 'author':
        return authorN.contains(qNorm);
      case 'director':
        return directorN.contains(qNorm);
      case 'actors':
        return actorsN.contains(qNorm);
      case 'tags':
        return tagNorms.any((t) => t.contains(qNorm));
      default:
        return haystacks.any((s) => s.contains(qNorm));
    }
  }
}

/// Hero 标签的条目键：id 为空时退回 sourceId+detailUrl+title 的稳定哈希。
///
/// 背景：选择器失效的源会把列表抓成「空壳条目」（id 为空），多张空壳卡共用
/// `'${前缀}-'` 同一 Hero 标签，页面转场扫描时抛 "There are multiple heroes
/// that share the same tag within a subtree"（crash_log 中 media- / search-
/// 系列错误的直接根因）。稳定哈希兜底保证同一条目跨重建仍可 Hero 配对，
/// 不同空壳条目几乎不会撞键。
extension MediaItemHeroKey on MediaItem {
  String heroKey() {
    final id = this.id;
    if (id.isNotEmpty) return id;
    final seed = '${sourceId ?? ''}|${detailUrl ?? ''}|$title';
    return 'h${seed.hashCode.abs().toRadixString(36)}';
  }
}
