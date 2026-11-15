/// 搜索热词仓库（Bangumi 实时获取，多级兜底）。
///
/// 打开搜索面板时按 TTL 刷新，数据优先级：
/// 1. **Bangumi 注目榜 + 实时热门**——按模块从 bgm.tv 拉真实热门：优先抓频道页
///    （bgm.tv/anime、bgm.tv/book）的「注目榜」区块（最近 30 日标记，取条目 ID），
///    中文名经 v0 详情接口补全并持久缓存；注目页拿不到再走 v0 搜索接口按收藏
///    人数排序（`sort: heat`，响应自带 name_cn）。全部走应用既有代理/ECH 链路，
///    零维护自动更新。
/// 2. 本地兜底——上次成功缓存（SharedPreferences）→ 打包资源 →「暂无热词」。
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' show parse;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/plugin_config.dart';
import '../services/bangumi/bangumi_client.dart';
import '../services/bangumi/bangumi_models.dart';
import '../services/bangumi/bangumi_proxy_config.dart';
import '../utils/app_log.dart';

/// 按模块分组的搜索热词（ChangeNotifier，数据变化时通知 UI 重建）。
class HotSearchKeywords extends ChangeNotifier {
  HotSearchKeywords._();

  static final HotSearchKeywords instance = HotSearchKeywords._();

  /// 离线兜底打包资源（与 Bangumi 数据同结构：`{模块名: [热词...]}`）。
  static const String _fallbackAsset = 'assets/builtin/hot_search_keywords.json';

  /// 上次成功拉取的热词缓存键（Bangumi 全失败时回退，避免退回打包旧数据）。
  static const String _remoteCacheKey = 'hot_search_keywords_remote_cache_v1';

  /// 上次成功拉取时间戳（毫秒，TTL 判定用）。
  static const String _lastFetchKey = 'hot_search_keywords_last_fetch_v1';

  /// 远程刷新间隔：面板打开时超过该间隔才重新拉取。
  static const Duration refreshInterval = Duration(minutes: 30);

  /// 失败重试退避（内存级）：离线时避免每次打开面板都慢超时。
  static const Duration _retryInterval = Duration(minutes: 5);

  /// 单模块热词数量上限（容错：防止异常数据撑爆面板）。
  static const int maxKeywordsPerModule = 30;

  /// 条目 ID → 中文名缓存键（注目榜页面无中文名，经详情接口补全后持久化）。
  static const String _cnNameCacheKey = 'hot_search_keywords_cn_map_v1';

  /// 单轮单频道最多补全的中文名条数（首次运行防请求过多，稳态全走缓存）。
  static const int _cnFetchBudgetPerChannel = 15;

  Map<String, List<String>> _data = const <String, List<String>>{};
  bool _bootstrapped = false;
  int? _lastFetchMs;
  DateTime? _lastAttempt;
  Map<int, String>? _cnNameCache;

  /// 本地兜底数据是否已就绪（就绪前 UI 可显示加载态）。
  bool get bootstrapped => _bootstrapped;

  /// 返回 [type] 模块的热词（无数据时空列表，同步返回）。
  List<String> forModule(SourceType type) =>
      _data[type.name] ?? const <String>[];

  /// 打开搜索面板时调用：确保本地数据就绪，并按 TTL 决定是否拉取远程。
  Future<void> load() async {
    if (!_bootstrapped) {
      final prefs = await SharedPreferences.getInstance();
      _lastFetchMs = prefs.getInt(_lastFetchKey);
      final cached = _parsePrefsCache(prefs.getString(_remoteCacheKey));
      _data = cached ?? await _loadAssetSafely();
      _bootstrapped = true;
      AppLog.instance.i(
        '[热搜] 本地数据就绪（${cached != null ? '缓存' : '打包词'}，'
        '${_data.length} 个模块）',
      );
      notifyListeners();
    }
    final DateTime now = DateTime.now();
    final DateTime? attempt = _lastAttempt;
    if (attempt != null && now.difference(attempt) < _retryInterval) return;
    final int? lastFetch = _lastFetchMs;
    if (lastFetch != null &&
        now.millisecondsSinceEpoch - lastFetch < refreshInterval.inMilliseconds) {
      return;
    }
    await refresh();
  }

  /// 立即拉取 Bangumi 实时热词（无视 TTL，供手动刷新与 TTL 到期后的内部调用）。
  Future<void> refresh() async {
    _lastAttempt = DateTime.now();
    final Map<String, List<String>>? remote = await _fetchBangumiLiveGuarded();

    if (remote == null || remote.isEmpty) {
      AppLog.instance.w('[热搜] Bangumi 未取到数据，沿用本地数据');
      return;
    }
    final String summary = remote.keys
        .map((String k) => '$k×${remote[k]!.length}')
        .join(', ');
    AppLog.instance.i('[热搜] 已更新（来源=Bangumi）: $summary');
    await _persist(remote);
    if (_mapsEqual(remote, _data)) return;
    _data = remote;
    notifyListeners();
  }

  /// 解析热词 JSON：`{模块名: [热词...]}`。
  ///
  /// 容错规则：非法 JSON / 非 Map 返回空表；过滤空串并按出现顺序去重；
  /// 每模块截断到 [maxKeywordsPerModule]。
  static Map<String, List<String>> parseKeywordsJson(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on Object {
      return const <String, List<String>>{};
    }
    if (decoded is! Map) return const <String, List<String>>{};
    final result = <String, List<String>>{};
    decoded.forEach((Object? key, Object? value) {
      if (key is! String || key.isEmpty || value is! List) return;
      final seen = <String>{};
      final words = <String>[];
      for (final Object? item in value) {
        if (item is! String) continue;
        final word = item.trim();
        if (word.isEmpty || !seen.add(word)) continue;
        words.add(word);
        if (words.length >= maxKeywordsPerModule) break;
      }
      if (words.isEmpty) return;
      result[key] = List<String>.unmodifiable(words);
    });
    return Map<String, List<String>>.unmodifiable(result);
  }

  /// 打包资源兜底（缺失/损坏时返回空表，UI 显示「暂无热词」）。
  Future<Map<String, List<String>>> _loadAssetSafely() async {
    try {
      final String raw = await rootBundle.loadString(_fallbackAsset);
      return parseKeywordsJson(raw);
    } on Object {
      return const <String, List<String>>{};
    }
  }

  /// 解析持久化的远程缓存；无/损坏返回 null（交由打包资源兜底）。
  Map<String, List<String>>? _parsePrefsCache(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parsed = parseKeywordsJson(raw);
    return parsed.isEmpty ? null : parsed;
  }

  /// 成功拉取后持久化缓存与时间戳（失败不影响主流程）。
  Future<void> _persist(Map<String, List<String>> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(
        data.map((k, v) => MapEntry<String, dynamic>(k, v)),
      );
      await prefs.setString(_remoteCacheKey, json);
      _lastFetchMs = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(_lastFetchKey, _lastFetchMs!);
    } on Object {
      // 持久化失败不影响本次展示。
    }
  }

  // --- Bangumi 注目榜 + 实时热门（唯一网络数据源） ---

  /// Bangumi 单模块拉取条数。
  static const int _bangumiWordLimit = 15;

  /// 按模块从 Bangumi 拉实时热门（任一模块成功即用）。
  ///
  /// 网络层失败（离线 / 无法连接）立即放弃整轮，把失败成本压到一次请求；
  /// 单页/单查询失败只影响当前模块，其余继续。注目频道页结果在本轮内
  /// 复用（漫画与小说的兜底共用 /book 页，只抓一次）。
  Future<Map<String, List<String>>?> _fetchBangumiLive() async {
    final Dio dio = _buildBangumiDio();
    final client = BangumiClient(dio: dio, maxAttempts: 1);
    final featured = <String, List<String>>{};
    final result = <String, List<String>>{};
    for (final SourceType type in SourceType.values) {
      try {
        final List<String> words =
            await _bangumiWordsForModule(client, dio, type, featured);
        if (words.isNotEmpty) result[type.name] = words;
      } on BangumiApiException catch (e) {
        // statusCode 为 null = 网络层异常（连接失败/超时）：视为离线，整轮放弃。
        if (e.statusCode == null) {
          AppLog.instance.w('[热搜] Bangumi 网络不可达，放弃本轮（${e.message}）');
          return null;
        }
        // HTTP 层失败：跳过该模块，其余继续。
        AppLog.instance.w('[热搜] Bangumi HTTP ${e.statusCode}，跳过当前模块');
      }
    }
    return result.isEmpty ? null : result;
  }

  Future<Map<String, List<String>>?> _fetchBangumiLiveGuarded() async {
    try {
      return await _fetchBangumiLive();
    } on Object {
      // Bangumi 兜底任何意外失败都不影响既有缓存/打包资源兜底链。
      return null;
    }
  }

  /// 单模块候选阶梯：注目频道页 → 搜索查询，依次尝试取第一个非空结果。
  Future<List<String>> _bangumiWordsForModule(
    BangumiClient client,
    Dio dio,
    SourceType type,
    Map<String, List<String>> featured,
  ) async {
    for (final BangumiHotStep step in bangumiLadderFor(type, DateTime.now())) {
      final String? channel = step.featuredChannel;
      if (channel != null) {
        if (!featured.containsKey(channel)) {
          featured[channel] = await _fetchFeaturedWords(client, dio, channel);
        }
        if (featured[channel]!.isNotEmpty) return featured[channel]!;
        continue;
      }
      final BangumiHotQuery? q = step.query;
      if (q == null) continue;
      try {
        final subjects = await client.searchPopularSubjects(
          types: q.types,
          tags: q.tags,
          airDate: q.airDate,
          limit: _bangumiWordLimit,
        );
        final words = subjectsToWords(subjects);
        if (words.isNotEmpty) return words;
        AppLog.instance.d('[热搜] 搜索档无结果（types=${q.types}, tags=${q.tags}）');
      } on BangumiApiException catch (e) {
        if (e.statusCode == null) rethrow;
        AppLog.instance.w('[热搜] 搜索档失败（tags=${q.tags}）: HTTP ${e.statusCode}');
      }
    }
    return const <String>[];
  }

  /// 抓频道页「注目榜」条目（最近 30 日标记）。
  ///
  /// 页面上只有日文原名（无中文名），故仅提取**条目 ID 与排序**，中文名经
  /// [BangumiClient.fetchSubject] 补全（带持久缓存，见 [_resolveFeaturedWords]）。
  /// 任何失败（网络/非 200/结构变化）返回空列表，由后续搜索阶梯接管。
  Future<List<String>> _fetchFeaturedWords(
    BangumiClient client,
    Dio dio,
    String channel,
  ) async {
    try {
      final resp = await dio.get<String>(
        '${BangumiProxyConfig.instance.mainSiteBaseUrl}$channel',
        options: Options(
          responseType: ResponseType.plain,
          headers: <String, dynamic>{'User-Agent': BangumiClient.userAgent},
        ),
      );
      final String? body = resp.data;
      if (resp.statusCode != 200 || body == null || body.isEmpty) {
        AppLog.instance.w('[热搜] 注目页 $channel HTTP ${resp.statusCode}');
        return const <String>[];
      }
      final List<({int id, String name})> subjects =
          parseFeaturedSubjects(body);
      if (subjects.isEmpty) {
        AppLog.instance.w('[热搜] 注目页 $channel 解析 0 条（页面结构可能变化）');
        return const <String>[];
      }
      final List<String> words = await _resolveFeaturedWords(client, subjects);
      if (words.isEmpty) {
        AppLog.instance.w('[热搜] 注目页 $channel 解析 0 条（页面结构可能变化）');
      } else {
        AppLog.instance.d('[热搜] 注目页 $channel 解析 ${words.length} 条');
      }
      return words;
    } on Object catch (e) {
      AppLog.instance.w('[热搜] 注目页 $channel 抓取失败: $e');
      return const <String>[];
    }
  }

  /// 注目榜条目 → 热词：逐条经 v0 详情接口取中文名（name_cn）。
  ///
  /// ID→中文名持久缓存（注目榜变化慢，稳态几乎全部命中缓存、零请求）；
  /// 单条获取失败回退页面上的日文名，不中断整轮。每轮每频道最多补全
  /// [_cnFetchBudgetPerChannel] 条，防止首次运行请求过多。
  Future<List<String>> _resolveFeaturedWords(
    BangumiClient client,
    List<({int id, String name})> subjects,
  ) async {
    final Map<int, String> cnCache = await _loadCnNameCache();
    int fetchBudget = _cnFetchBudgetPerChannel;
    final seen = <String>{};
    final words = <String>[];
    for (final subject in subjects) {
      final int id = subject.id;
      final String name = subject.name;
      String? cn = cnCache[id];
      if (cn == null) {
        if (fetchBudget <= 0) {
          // 本轮补全预算用尽：未解析条目跳过，下一轮继续。
          continue;
        }
        fetchBudget--;
        try {
          final detail = await client.fetchSubject(id);
          cn = detail.nameCn.isNotEmpty ? detail.nameCn : detail.name;
        } on Object catch (e) {
          AppLog.instance.w('[热搜] 条目 $id 中文名获取失败: $e');
          cn = name;
        }
        cnCache[id] = cn;
        await _saveCnNameCache();
      }
      final String word = cn.trim();
      if (word.isEmpty || !seen.add(word)) continue;
      words.add(word);
      if (words.length >= maxKeywordsPerModule) break;
    }
    return words;
  }

  /// 加载条目 ID → 中文名缓存（内存缓存优先，首次从 SharedPreferences 读）。
  Future<Map<int, String>> _loadCnNameCache() async {
    final Map<int, String>? cached = _cnNameCache;
    if (cached != null) return cached;
    Map<int, String> loaded = <int, String>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_cnNameCacheKey);
      if (raw != null && raw.isNotEmpty) {
        final Object? decoded = jsonDecode(raw);
        if (decoded is Map) {
          loaded = decoded.map((Object? k, Object? v) => MapEntry<int, String>(
                int.parse(k.toString()),
                v.toString(),
              ));
        }
      }
    } on Object {
      // 损坏数据忽略，按空缓存继续。
    }
    _cnNameCache = loaded;
    return loaded;
  }

  /// 持久化条目 ID → 中文名缓存（失败不影响主流程，下次重写）。
  Future<void> _saveCnNameCache() async {
    final Map<int, String>? cache = _cnNameCache;
    if (cache == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cnNameCacheKey,
        jsonEncode(cache.map((int k, String v) => MapEntry(k.toString(), v))),
      );
    } on Object {
      // 缓存写失败不影响本轮展示。
    }
  }

  /// 解析频道页 HTML 中的注目榜条目（ID + 页面显示名）。
  ///
  /// 选择器：`.featuredItems .mainItem`，行内首个 `/subject/` 链接即条目
  /// （href 含 ID）；页面显示名为日文原名（title 属性或链接文本），中文名
  /// 由调用方经详情接口补全。按 ID 去重保序，截断到 [maxKeywordsPerModule]。
  @visibleForTesting
  static List<({int id, String name})> parseFeaturedSubjects(String html) {
    final List<dom.Element> rows;
    try {
      rows = parse(html).querySelectorAll('.featuredItems .mainItem');
    } on Object {
      return const <({int id, String name})>[];
    }
    final seenIds = <int>{};
    final result = <({int id, String name})>[];
    for (final dom.Element row in rows) {
      int? id;
      String fallback = '';
      String name = '';
      for (final dom.Element a
          in row.querySelectorAll('a[href^="/subject/"]')) {
        final match =
            RegExp(r'/subject/(\d+)').firstMatch(a.attributes['href'] ?? '');
        if (match == null) continue;
        id ??= int.parse(match.group(1)!);
        if (name.isEmpty) {
          final String text = a.text.trim();
          if (text.isNotEmpty) {
            name = text;
          } else if (fallback.isEmpty) {
            fallback = (a.attributes['title'] ?? '').trim();
          }
        }
        if (name.isNotEmpty) break;
      }
      final int resolvedId = id ?? 0;
      final String resolvedName = (name.isNotEmpty ? name : fallback).trim();
      if (resolvedId <= 0 || resolvedName.isEmpty) continue;
      if (!seenIds.add(resolvedId)) continue;
      result.add((id: resolvedId, name: resolvedName));
      if (result.length >= maxKeywordsPerModule) break;
    }
    return result;
  }

  /// 热词专用 Bangumi Dio：短超时快速失败（网络层失败会立即放弃整轮）。
  Dio _buildBangumiDio() => Dio(BaseOptions(
        baseUrl: BangumiClient.baseUrl,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        // 4xx/5xx 不抛 DioException，由 [BangumiClient._request] 统一判定。
        validateStatus: (_) => true,
      ));

  /// Bangumi 条目 → 热词：过滤 R18 与空名，中文名优先，去重保序并截断。
  @visibleForTesting
  static List<String> subjectsToWords(List<BangumiSubject> subjects) {
    final seen = <String>{};
    final words = <String>[];
    for (final BangumiSubject s in subjects) {
      if (s.nsfw) continue;
      final String word = s.displayName.trim();
      if (word.isEmpty || !seen.add(word)) continue;
      words.add(word);
      if (words.length >= maxKeywordsPerModule) break;
    }
    return words;
  }

  /// 单模块的 Bangumi 候选阶梯（纯函数，[now] 便于测试）。
  ///
  /// - 动画：`/anime` 注目榜 → 近 180 天开播热门新番 → 全站热门动画；
  /// - 漫画：`/book` 注目榜（书籍混排，热书以漫画为主）→「漫画」标签 → 全站书籍；
  /// - 小说：「网络小说」标签 → 「轻小说」标签 → `/book` 注目榜 → 全站书籍
  ///   （搜索在前：避免与漫画模块的注目词完全重复）。
  @visibleForTesting
  static List<BangumiHotStep> bangumiLadderFor(SourceType type, DateTime now) {
    final String cutoff = now
        .subtract(const Duration(days: 180))
        .toIso8601String()
        .substring(0, 10);
    const allBooks = BangumiHotStep.search(
      BangumiHotQuery(types: <int>[BangumiSubjectType.book]),
    );
    return switch (type) {
      SourceType.animeSource ||
      SourceType.videoSource ||
      SourceType.audioSource =>
        <BangumiHotStep>[
          const BangumiHotStep.featured('/anime'),
          BangumiHotStep.search(
            BangumiHotQuery(
              types: const <int>[BangumiSubjectType.anime],
              airDate: <String>['>=$cutoff'],
            ),
          ),
          const BangumiHotStep.search(
            BangumiHotQuery(types: <int>[BangumiSubjectType.anime]),
          ),
        ],
      SourceType.mangaSource => <BangumiHotStep>[
          const BangumiHotStep.featured('/book'),
          const BangumiHotStep.search(
            BangumiHotQuery(
              types: <int>[BangumiSubjectType.book],
              tags: <String>['漫画'],
            ),
          ),
          allBooks,
        ],
      SourceType.novelSource => <BangumiHotStep>[
          const BangumiHotStep.search(
            BangumiHotQuery(
              types: <int>[BangumiSubjectType.book],
              tags: <String>['网络小说'],
            ),
          ),
          const BangumiHotStep.search(
            BangumiHotQuery(
              types: <int>[BangumiSubjectType.book],
              tags: <String>['轻小说'],
            ),
          ),
          const BangumiHotStep.featured('/book'),
          allBooks,
        ],
    };
  }

  static bool _mapsEqual(
    Map<String, List<String>> a,
    Map<String, List<String>> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final MapEntry<String, List<String>> e in a.entries) {
      if (!listEquals<String>(b[e.key], e.value)) return false;
    }
    return true;
  }
}

/// 一档 Bangumi 热门查询参数（纯数据，供阶梯降级与测试）。
class BangumiHotQuery {
  /// 条目类型（[BangumiSubjectType] 常量）。
  final List<int> types;

  /// 且关系标签过滤（如 `漫画`）。
  final List<String> tags;

  /// 开播日期比较串（如 `>=2026-04-14`）。
  final List<String> airDate;

  const BangumiHotQuery({
    required this.types,
    this.tags = const <String>[],
    this.airDate = const <String>[],
  });
}

/// 阶梯中的一档候选：注目频道页抓取或搜索查询（二选一，纯数据便于测试）。
class BangumiHotStep {
  /// 频道页路径（如 `/anime`）——非空时抓该页「注目榜」名称。
  final String? featuredChannel;

  /// 搜索查询——非空时走 [BangumiClient.searchPopularSubjects]。
  final BangumiHotQuery? query;

  const BangumiHotStep.featured(this.featuredChannel) : query = null;

  const BangumiHotStep.search(this.query) : featuredChannel = null;
}
