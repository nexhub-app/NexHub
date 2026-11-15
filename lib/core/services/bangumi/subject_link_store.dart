/// contentId → Bangumi subject 绑定存储与自动解析。
///
/// 三级解析：
/// 1. 缓存命中（Hive box `bangumi_subject_links`）直接返回；
/// 2. 标题搜索 + 相似度打分：高置信自动采用并写缓存，低置信返回候选；
/// 3. 手动绑定：UI 选定后写缓存（长期有效）。
///
/// value 为 JSON `{subjectId, forcedType}`，forcedType 为绑定面板手动
/// 选定的收藏状态覆盖（null = 自动判定；兼容旧字段 forceCollect）。
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:hive/hive.dart';

import '../../models/plugin_config.dart';
import 'bangumi_client.dart';
import 'bangumi_models.dart';

/// 归一化标题相似度打分（0-1），供搜索候选置信度判定与单测使用。
///
/// 规则：小写、去空白后，完全相等 = 1；否则按「1 - 编辑距离/较长串长度」。
double bangumiTitleSimilarity(String a, String b) {
  final na = _normalizeTitle(a);
  final nb = _normalizeTitle(b);
  if (na.isEmpty || nb.isEmpty) return 0;
  if (na == nb) return 1;
  final int maxLen = math.max(na.length, nb.length);
  return 1 - _levenshtein(na, nb) / maxLen;
}

String _normalizeTitle(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'\s+'), '');

int _levenshtein(String a, String b) {
  final m = a.length, n = b.length;
  if (m == 0) return n;
  if (n == 0) return m;
  var prev = List<int>.generate(n + 1, (i) => i);
  var curr = List<int>.filled(n + 1, 0);
  for (int i = 1; i <= m; i++) {
    curr[0] = i;
    for (int j = 1; j <= n; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      curr[j] = math.min(
        math.min(curr[j - 1] + 1, prev[j] + 1),
        prev[j - 1] + cost,
      );
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[n];
}

/// 单条绑定记录。
class SubjectLink {
  final int subjectId;

  /// 手动状态覆盖（[BangumiCollectionType] 五状态之一），
  /// null = 同步时自动判定。
  final int? forcedType;

  const SubjectLink({required this.subjectId, this.forcedType});

  Map<String, dynamic> toJson() => <String, dynamic>{
        'subjectId': subjectId,
        if (forcedType != null) 'forcedType': forcedType,
      };

  /// 旧版 `forceCollect: true` 迁移为 `forcedType = collect`。
  factory SubjectLink.fromJson(Map<String, dynamic> json) => SubjectLink(
        subjectId: (json['subjectId'] as num?)?.toInt() ?? 0,
        forcedType: (json['forcedType'] as num?)?.toInt() ??
            (json['forceCollect'] == true
                ? BangumiCollectionType.collect
                : null),
      );
}

/// 自动解析结果。
class SubjectResolveResult {
  /// 已确定的绑定（缓存命中或高置信自动采用）。
  final SubjectLink? link;

  /// 低置信候选列表（需用户手动确认），link 非空时为空。
  final List<BangumiSubject> candidates;

  const SubjectResolveResult({this.link, this.candidates = const []});

  bool get resolved => link != null;
}

/// contentId → subjectId 绑定存储。
class SubjectLinkStore {
  SubjectLinkStore({required BangumiClient client, Box<dynamic>? box})
      : _client = client,
        _box = box;

  /// Hive box 名。
  static const String boxName = 'bangumi_subject_links';

  /// 高置信相似度阈值（≥ 该值自动采用）。
  static const double highConfidence = 0.85;

  final BangumiClient _client;
  final Box<dynamic>? _box;

  Future<Box<dynamic>> _openBox() async {
    if (_box != null) return _box;
    if (Hive.isBoxOpen(boxName)) return Hive.box(boxName);
    return Hive.openBox(boxName);
  }

  /// 读取绑定（无绑定返回 null）。
  Future<SubjectLink?> get(String contentId) async {
    final box = await _openBox();
    final raw = box.get(contentId);
    if (raw is! String || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final link = SubjectLink.fromJson(json);
      return link.subjectId > 0 ? link : null;
    } on Object {
      return null;
    }
  }

  /// 写入绑定（手动绑定 / 高置信自动采用）。
  Future<void> put(String contentId, SubjectLink link) async {
    final box = await _openBox();
    await box.put(contentId, jsonEncode(link.toJson()));
  }

  /// 解除绑定。
  Future<void> remove(String contentId) async {
    final box = await _openBox();
    await box.delete(contentId);
  }

  /// [SourceType] → Bangumi 搜索 type 过滤。
  ///
  /// animeSource 同时覆盖动画与三次元（影视与动漫共用 animeSource）。
  static List<int> searchTypesFor(SourceType type) => switch (type) {
        SourceType.animeSource ||
        SourceType.videoSource ||
        SourceType.audioSource =>
          const <int>[
            BangumiSubjectType.anime,
            BangumiSubjectType.real,
          ],
        SourceType.mangaSource ||
        SourceType.novelSource =>
          const <int>[BangumiSubjectType.book],
      };

  /// 三级解析：缓存 → 标题搜索（高置信自动采用）→ 候选返回。
  Future<SubjectResolveResult> resolve(
    String contentId,
    String title,
    SourceType sourceType,
  ) async {
    final cached = await get(contentId);
    if (cached != null) return SubjectResolveResult(link: cached);

    final candidates = await _client.searchSubjects(
      title,
      types: searchTypesFor(sourceType),
    );
    if (candidates.isEmpty) return const SubjectResolveResult();

    // 取候选中相似度最高者（name 与 name_cn 取更高分）。
    BangumiSubject best = candidates.first;
    double bestScore = 0;
    for (final c in candidates) {
      final score = math.max(
        bangumiTitleSimilarity(title, c.name),
        bangumiTitleSimilarity(title, c.nameCn),
      );
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    if (bestScore >= highConfidence) {
      final link = SubjectLink(subjectId: best.id);
      await put(contentId, link);
      return SubjectResolveResult(link: link);
    }
    return SubjectResolveResult(candidates: candidates);
  }
}
