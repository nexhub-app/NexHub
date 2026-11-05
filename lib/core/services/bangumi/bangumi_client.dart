/// Bangumi API 客户端（api.bgm.tv v0）。
///
/// - 强制可识别 User-Agent（Bangumi API 使用条款要求）；
/// - 有 token 时注入 `Authorization: Bearer`；
/// - 顺序节流（请求间隔 >= 300ms，无并发）防止触发限流；
/// - 429/5xx 指数退避重试（最多 2 次）；
/// - 统一错误封装 [BangumiApiException]。
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import 'bangumi_models.dart';
import 'bangumi_proxy_config.dart';

/// Bangumi API 错误。
class BangumiApiException implements Exception {
  final int? statusCode;
  final String message;

  /// 本次请求命中的主机（诊断用：区分官方域名与被反代 / 镜像改写后的域名）。
  ///
  /// 401 的报文由 Bangumi 原样返回时，host 能立刻分辨「令牌真被拒」与
  /// 「镜像没转发 Authorization 头」——后者只在镜像域名上复现。
  final String? host;

  /// 是否来自令牌端点（`/oauth/access_token`）的鉴权拒绝。
  ///
  /// 该端点的 400/401 表示 client 凭据或 refresh_token 本身失效，重试无用。
  final bool tokenEndpoint;

  /// 令牌端点返回的机器可读错误码（`invalid_grant` / `invalid_client` 等）。
  ///
  /// 与 [message] 分开保存：文案可能被本地化或改写，判定分支只认码。
  final String? oauthErrorCode;

  const BangumiApiException(
    this.statusCode,
    this.message, {
    this.host,
    this.tokenEndpoint = false,
    this.oauthErrorCode,
  });

  /// 是否为鉴权失败（token 无效 / 过期）。
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'BangumiApiException($statusCode): $message';
}

/// Bangumi API 客户端。
///
/// token 由外部（[BangumiAuth]）通过 [token] 属性注入；未登录时公开接口
/// （搜索 / 剧集）仍可匿名调用。
class BangumiClient {
  BangumiClient({Dio? dio, int maxAttempts = 3})
      : _dio = dio ?? _buildDio(),
        _maxAttempts = maxAttempts < 1 ? 1 : maxAttempts;

  static const String baseUrl = 'https://api.bgm.tv';

  /// Bangumi 要求 UA 标明应用与项目地址，便于滥用时联系。
  static const String userAgent =
      'nexhub/0.1.0 (Flutter; https://github.com/nexhub/nexhub)';

  /// 顺序请求最小间隔。
  static const Duration _minInterval = Duration(milliseconds: 300);

  /// 单请求最大尝试次数（429/5xx/网络错误重试；非核心调用方可调低快速失败）。
  final int _maxAttempts;

  final Dio _dio;

  /// 当前 Bearer token（null = 匿名）。
  String? token;

  /// 带 token 的请求收到 401 时的续期回调。
  ///
  /// 参数是本次失败请求命中的 host。返回 true 表示 token 已更新，[_request]
  /// 会用新 token 立即重试一次；返回 false 表示无法续期，保留原始 401。
  /// 由 [BangumiAuth] 注入。
  Future<bool> Function(String host)? onUnauthorized;

  /// 每次请求发出前的钩子（[BangumiAuth] 用它做「临近过期主动续期」）。
  ///
  /// 抛错被忽略——请求本身照常发出，真失败时仍由 401 分支兜底。
  Future<void> Function()? onBeforeRequest;

  /// 上一次请求完成时间（节流用）。
  DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 顺序化所有请求（无并发）。
  Future<void> _pending = Future<void>.value();

  static Dio _buildDio() {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      // 404（未收藏）等业务态码不抛异常，统一在 _request 内判定。
      validateStatus: (_) => true,
    ));
    // 注意：不需要在此安装 findProxy。ECH 透明接管由全局
    // `NetworkClientBuilder.proxyOverrideResolver` 承载（见 bangumi_ech_proxy.dart），
    // 它经 main.dart 的 [HttpOverrides.global] 覆盖本客户端在内的全部 dart:io
    // 流量。在此处另设 findProxy 反而会覆盖掉用户的代理配置。
    return dio;
  }

  /// 统一请求入口：顺序节流 + 退避重试 + 错误封装。
  Future<Response<dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    Set<int> allowedStatus = const <int>{},
  }) {
    final completer = _pending.then((_) async {
      // 主动续期：access_token 临近 / 已过期时先换新，避免每次过期都要
      // 先吃一个必然失败的 401（个人 token 无 refresh_token 时该钩子空转）。
      final before = onBeforeRequest;
      if (before != null) {
        try {
          await before();
        } catch (_) {
          /* 续期失败不阻断请求：401 分支会再判定一次 */
        }
      }
      // 节流：距上次请求不足最小间隔时等待。
      final wait = _minInterval - DateTime.now().difference(_lastRequestAt);
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
      // 相对路径（/v0/...）按代理配置拼接 API 基址；绝对 URL（吐槽 p1）
      // 原样使用，由调用方自行套用代理配置。
      final target =
          path.startsWith('http') ? path : '${BangumiProxyConfig.instance.apiBaseUrl}$path';
      final host = Uri.tryParse(target)?.host ?? '';
      Response<dynamic>? response;
      Object? lastError;
      int attempt = 0;
      bool refreshed = false;
      while (attempt < _maxAttempts) {
        if (attempt > 0) {
          // 指数退避：1s → 2s。
          await Future<void>.delayed(Duration(seconds: 1 << (attempt - 1)));
        }
        // 每轮先清空，避免上一轮已被判失败（5xx / 网络错误）的响应残留下来
        // 被当成最终结果返回。
        response = null;
        try {
          response = await _dio.request<dynamic>(
            target,
            queryParameters: query,
            data: body,
            options: Options(
              method: method,
              headers: <String, dynamic>{
                'User-Agent': userAgent,
                if (token != null && token!.isNotEmpty)
                  'Authorization': 'Bearer $token',
              },
            ),
          );
          lastError = null;
          final code = response.statusCode ?? 0;
          // token 失效：续期成功则用新 token 立即重试，且只续期一次
          // （continue 跳过 attempt 自增，重试不占用退避次数）。
          if (code == 401 &&
              !refreshed &&
              token != null &&
              token!.isNotEmpty &&
              onUnauthorized != null) {
            refreshed = true;
            if (await onUnauthorized!(host)) continue;
          }
          // 429/5xx 可重试，其余直接返回。
          if (code != 429 && code < 500) break;
        } on DioException catch (e) {
          lastError = e;
          response = null;
        }
        attempt++;
      }
      _lastRequestAt = DateTime.now();
      if (response == null) {
        throw BangumiApiException(
          null,
          lastError?.toString() ?? 'network error',
          host: host,
        );
      }
      final code = response.statusCode ?? 0;
      final ok = (code >= 200 && code < 300) || allowedStatus.contains(code);
      if (!ok) {
        String message = 'HTTP $code';
        final data = response.data;
        if (data is Map<String, dynamic>) {
          final desc = data['description'] ?? data['title'];
          if (desc is String && desc.isNotEmpty) message = desc;
        }
        throw BangumiApiException(code, message, host: host);
      }
      return response;
    });
    // 无论成败都推进队列，避免一次失败卡死后续请求。
    _pending = completer.then((_) {}, onError: (_) {});
    return completer;
  }

  /// 验证 token 并返回用户信息（GET /v0/me）。
  Future<BangumiMe> fetchMe() async {
    final res = await _request('GET', '/v0/me');
    final data = res.data;
    if (data is! Map<String, dynamic>) {
      throw const BangumiApiException(null, 'unexpected /v0/me response');
    }
    return BangumiMe.fromJson(data);
  }

  /// 官方 OAuth 端点基址（令牌端点兜底用，见 [_postTokenEndpoint]）。
  static const String _officialOauthBase = 'https://bgm.tv';

  /// 令牌端点（`/oauth/access_token`）统一入口：按「配置基址 → 官方基址」依次尝试。
  ///
  /// 镜像模式下 [BangumiProxyConfig.oauthBaseUrl] 指向镜像主站，而部分反代并不
  /// 转发 `/oauth/access_token`（或返回 HTML / 404 / 5xx）。此时续期永远失败，
  /// 表现为「access_token 过期后只能重新授权」——正是 401 反复出现的主因之一。
  /// 故任一基址成功即返回；仅当镜像侧明确拒绝（400/401/403，凭据或
  /// refresh_token 真失效）才直接上抛，不再换基址。
  Future<BangumiToken> _postTokenEndpoint(
    Map<String, String> form, {
    String? fallbackRefreshToken,
  }) async {
    final bases = <String>[];
    for (final base in <String>[
      BangumiProxyConfig.instance.oauthBaseUrl,
      _officialOauthBase,
    ]) {
      final normalized = base.trim().replaceAll(RegExp(r'/+$'), '');
      if (normalized.isNotEmpty && !bases.contains(normalized)) {
        bases.add(normalized);
      }
    }
    BangumiApiException? lastError;
    for (final base in bases) {
      try {
        return await _postTokenOnce(
          base,
          form,
          fallbackRefreshToken: fallbackRefreshToken,
        );
      } on BangumiApiException catch (e) {
        lastError = e;
        // 只有「OAuth 服务明确回了错误码」才说明该基址真的处理了请求，
        // 重试无意义；反代侧 404/5xx/HTML/401 登录页一律换下一个基址。
        if (e.oauthErrorCode != null) rethrow;
      }
    }
    throw lastError ??
        const BangumiApiException(null, 'token endpoint unreachable');
  }

  /// 向单个基址换取 token（表单编码 + UA，不带 Bearer）。
  Future<BangumiToken> _postTokenOnce(
    String base,
    Map<String, String> form, {
    String? fallbackRefreshToken,
  }) async {
    Response<dynamic> res;
    try {
      res = await _dio.post<dynamic>(
        '$base/oauth/access_token',
        data: form,
        options: Options(
          headers: <String, dynamic>{'User-Agent': userAgent},
          contentType: Headers.formUrlEncodedContentType,
        ),
      );
    } on DioException catch (e) {
      throw BangumiApiException(
        e.response?.statusCode,
        e.message ?? e.type.name,
        host: Uri.tryParse(base)?.host,
        tokenEndpoint: true,
      );
    }
    // 响应体不一定是 JSON（镜像返回 HTML 登录页 / 纯文本错误页），
    // 按 dynamic 解析再判定，避免类型转换异常掩盖真实原因。
    final raw = res.data;
    Map<dynamic, dynamic>? data;
    if (raw is Map) {
      data = raw;
    } else if (raw is String && raw.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) data = decoded;
      } catch (_) {
        /* 落到下面的「非 JSON 响应」分支 */
      }
    }
    if (data == null) {
      throw BangumiApiException(
        res.statusCode,
        'unexpected token response',
        host: Uri.tryParse(base)?.host,
        tokenEndpoint: true,
      );
    }
    final accessToken = data['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw BangumiApiException(
        res.statusCode,
        (data['error_description'] as String?) ??
            (data['error'] as String?) ??
            'missing access_token',
        host: Uri.tryParse(base)?.host,
        tokenEndpoint: true,
        oauthErrorCode: data['error'] as String?,
      );
    }
    return BangumiToken(
      accessToken: accessToken,
      refreshToken: (data['refresh_token'] as String?) ?? fallbackRefreshToken,
      expiresIn: (data['expires_in'] as num?)?.toInt(),
      scope: data['scope'] as String?,
    );
  }

  /// 用授权码换 token（`grant_type=authorization_code`）。
  ///
  /// 端点基址见 [_postTokenEndpoint]（镜像失败时回退官方）；成功返回
  /// [BangumiToken]，缺少 `access_token` 时按授权失败抛 [BangumiApiException]
  /// （附 `error_description`）。
  Future<BangumiToken> exchangeCodeForToken({
    required String clientId,
    required String clientSecret,
    required String code,
    required String redirectUri,
  }) {
    return _postTokenEndpoint(<String, String>{
      'grant_type': 'authorization_code',
      'client_id': clientId,
      'client_secret': clientSecret,
      'code': code,
      'redirect_uri': redirectUri,
    });
  }

  /// 用 refresh_token 续期（POST /oauth/access_token，grant_type=refresh_token）。
  ///
  /// 直连 [_dio]、不进 [_request] 的串行队列——401 续期回调在队列内执行，
  /// 走队列会自锁。
  ///
  /// 返回的 refresh_token 会与请求值不同（Bangumi 轮换），缺省时回退到原值。
  Future<BangumiToken> refreshToken({
    required String clientId,
    required String clientSecret,
    required String refreshToken,
    required String redirectUri,
  }) {
    return _postTokenEndpoint(
      <String, String>{
        'grant_type': 'refresh_token',
        'client_id': clientId,
        'client_secret': clientSecret,
        'refresh_token': refreshToken,
        'redirect_uri': redirectUri,
      },
      fallbackRefreshToken: refreshToken,
    );
  }

  /// 按关键字搜索条目（POST /v0/search/subjects），限定条目类型。
  Future<List<BangumiSubject>> searchSubjects(
    String keyword, {
    required List<int> types,
    int limit = 10,
  }) async {
    final res = await _request(
      'POST',
      '/v0/search/subjects',
      query: <String, dynamic>{'limit': limit},
      body: <String, dynamic>{
        'keyword': keyword,
        'filter': <String, dynamic>{'type': types},
      },
    );
    final data = res.data;
    if (data is! Map<String, dynamic>) return const <BangumiSubject>[];
    final list = data['data'];
    if (list is! List) return const <BangumiSubject>[];
    return list
        .whereType<Map<String, dynamic>>()
        .map(BangumiSubject.fromJson)
        .toList();
  }

  /// 拉取热门条目（POST /v0/search/subjects，`sort: heat` 按收藏人数排序）。
  ///
  /// 用于搜索热词等「无关键词、按类型浏览热门」的场景：keyword 恒为空串
  /// （浏览模式），[types] 限定条目类型，[tags] 为且关系标签过滤（如 `漫画`），
  /// [airDate] 为开播日期比较串（如 `>=2026-04-14`）。
  /// 匿名请求下服务端忽略 nsfw 过滤参数，R18 条目由调用方按
  /// [BangumiSubject.nsfw] 自行过滤。
  Future<List<BangumiSubject>> searchPopularSubjects({
    required List<int> types,
    List<String> tags = const <String>[],
    List<String> airDate = const <String>[],
    int limit = 15,
  }) async {
    final res = await _request(
      'POST',
      '/v0/search/subjects',
      query: <String, dynamic>{'limit': limit},
      body: <String, dynamic>{
        'keyword': '',
        'sort': 'heat',
        'filter': <String, dynamic>{
          'type': types,
          if (tags.isNotEmpty) 'tag': tags,
          if (airDate.isNotEmpty) 'air_date': airDate,
        },
      },
    );
    final data = res.data;
    if (data is! Map<String, dynamic>) return const <BangumiSubject>[];
    final list = data['data'];
    if (list is! List) return const <BangumiSubject>[];
    return list
        .whereType<Map<String, dynamic>>()
        .map(BangumiSubject.fromJson)
        .toList();
  }

  /// 拉取条目本篇剧集（GET /v0/episodes?subject_id=&type=0），分页拉全。
  Future<List<BangumiEpisode>> fetchEpisodes(int subjectId) async {
    final episodes = <BangumiEpisode>[];
    int offset = 0;
    const int pageSize = 100;
    while (true) {
      final res = await _request('GET', '/v0/episodes', query: <String, dynamic>{
        'subject_id': subjectId,
        'type': 0,
        'limit': pageSize,
        'offset': offset,
      });
      final data = res.data;
      if (data is! Map<String, dynamic>) break;
      final list = data['data'];
      if (list is! List) break;
      episodes.addAll(
          list.whereType<Map<String, dynamic>>().map(BangumiEpisode.fromJson));
      final total = (data['total'] as num?)?.toInt() ?? episodes.length;
      offset += pageSize;
      if (episodes.length >= total || list.isEmpty) break;
    }
    // 按 sort 升序，保证 index → 集数映射稳定。
    episodes.sort((a, b) => a.sort.compareTo(b.sort));
    return episodes;
  }

  /// 拉取条目详情（GET /v0/subjects/{id}），含站点评分、简介与标签。
  ///
  /// 公开接口（无需鉴权）；供详情页展示「来自网站」的评分与评价。
  Future<BangumiSubjectDetail> fetchSubject(int subjectId) async {
    final res = await _request('GET', '/v0/subjects/$subjectId');
    final data = res.data;
    if (data is! Map<String, dynamic>) {
      throw const BangumiApiException(null, 'unexpected subject response');
    }
    return BangumiSubjectDetail.fromJson(data);
  }

  /// 查询当前用户对某条目的收藏状态；未收藏返回 null（404）。
  Future<BangumiUserCollection?> fetchUserCollection(int subjectId) async {
    final res = await _request(
      'GET',
      '/v0/users/-/collections/$subjectId',
      allowedStatus: const <int>{404},
    );
    if (res.statusCode == 404) return null;
    final data = res.data;
    if (data is! Map<String, dynamic>) return null;
    return BangumiUserCollection.fromJson(data);
  }

  /// 拉取条目吐槽（GET /p1/subjects/{subject_id}/comments）。
  ///
  /// 使用 **Next API**（next.bgm.tv，镜像模式下为配置的主站域名），
  /// 非 v0 公开 API。v0 无 comments 端点；吐槽数据仅通过 p1 接口提供。
  /// 公开接口无需鉴权；分页取前 [limit] 条。
  Future<List<BangumiComment>> fetchSubjectComments(
    int subjectId, {
    int limit = 20,
  }) async {
    final res = await _request(
      'GET',
      '${BangumiProxyConfig.instance.nextBaseUrl}/p1/subjects/$subjectId/comments',
      query: <String, dynamic>{'limit': limit},
    );
    final data = res.data;
    if (data is! Map<String, dynamic>) return const <BangumiComment>[];
    final list = data['data'];
    if (list is! List) return const <BangumiComment>[];
    return list
        .whereType<Map<String, dynamic>>()
        .map(BangumiComment.fromJson)
        .toList();
  }

  /// 拉取角色与制作人员。
  ///
  /// 制作人员来源分两种环境，均兼容：
  /// - 真实 API：角色在 `/v0/subjects/{id}/characters`（返回 `{data:[...]}`），制作人员
  /// 在独立端点 `/v0/subjects/{id}/persons`（返回裸数组，条目带 `career` 职业字段，
  /// `relation` 为该作职位）；
  /// - 合并代理：部分反代把制作人员混入 `/characters` 响应，同样以 `career` 字段识别
  /// （真实 API 的角色不含 `career`）。
  ///
  /// 两端点分别兜底（任一侧失败不影响另一侧），`/persons` 结果强制判为制作人员，
  /// 按 id 去重合并，避免重复请求与限流。
  Future<({List<BangumiCharacter> characters, List<BangumiStaff> staff})>
      fetchCharactersAndStaff(int subjectId) async {
    final characters = <BangumiCharacter>[];
    final staffMap = <int, BangumiStaff>{};

    /// 从响应体中提取列表（兼容 `{data:[...]}` 包裹和裸数组两种格式）。
    List<dynamic>? extractList(dynamic raw) {
      if (raw is List) return raw;
      if (raw is Map<String, dynamic>) {
        final d = raw['data'];
        if (d is List) return d;
      }
      return null;
    }

    Future<void> ingest(dynamic raw, {bool forceStaff = false}) async {
      final list = extractList(raw);
      if (list == null) return;
      for (final item in list.whereType<Map<String, dynamic>>()) {
        // 带 career 职业字段（或明确来自 /persons）的条目视为制作人员，其余为角色。
        // 注意：Bangumi v0 API 字段名为 `career`（单数），非 `careers`。
        final isPerson = forceStaff || item['career'] is List;
        if (isPerson) {
          final s = BangumiStaff.fromJson(item);
          staffMap[s.id] = s;
        } else {
          characters.add(BangumiCharacter.fromJson(item));
        }
      }
    }

    // 角色（真实 API 仅角色；合并代理可能含 career 的制作人员）。
    try {
      final res = await _request('GET', '/v0/subjects/$subjectId/characters');
      await ingest(res.data);
    } catch (_) {
      /* 角色非核心，失败不阻断 */
    }

    // 制作人员（真实 API 独立端点，结果强制判为制作人员）。
    try {
      final res = await _request('GET', '/v0/subjects/$subjectId/persons');
      await ingest(res.data, forceStaff: true);
    } catch (_) {
      /* 制作人员非核心，失败不阻断 */
    }

    return (characters: characters, staff: staffMap.values.toList());
  }

  /// 拉取关联条目（GET /v0/subjects/{subject_id}/subjects）。
  ///
  /// 返回前传 / 续集 / 同系列等关联条目。响应可能是
  /// `{data:[...]}` 包裹结构或直接的数组，二者都兼容。
  Future<List<BangumiRelatedSubject>> fetchRelatedSubjects(
      int subjectId) async {
    final res = await _request('GET', '/v0/subjects/$subjectId/subjects');
    final data = res.data;
    List<dynamic>? list;
    if (data is Map<String, dynamic>) {
      final d = data['data'];
      if (d is List) list = d;
    } else if (data is List) {
      list = data;
    }
    if (list == null) return const <BangumiRelatedSubject>[];
    return list
        .whereType<Map<String, dynamic>>()
        .map(BangumiRelatedSubject.fromJson)
        .toList();
  }

  /// 新建 / 修改收藏（POST /v0/users/-/collections/{subject_id}）。
  ///
  /// 该端点对已存在的收藏同样生效（幂等更新），成功返回 202/204。
  Future<void> updateCollection(int subjectId, CollectionPayload payload) async {
    await _request(
      'POST',
      '/v0/users/-/collections/$subjectId',
      body: payload.toJson(),
    );
  }

  /// 部分更新收藏（PATCH /v0/users/-/collections/{subject_id}）。
  ///
  /// 仅携带变化字段；条目尚未收藏（404）时自动回退 POST 创建。
  Future<void> patchCollection(int subjectId, CollectionPayload payload) async {
    final res = await _request(
      'PATCH',
      '/v0/users/-/collections/$subjectId',
      body: payload.toJson(),
      allowedStatus: const <int>{404},
    );
    if (res.statusCode == 404) {
      await updateCollection(subjectId, payload);
    }
  }

  /// 读取当前用户对某条目的章节收藏状态，分页拉全
  /// （GET /v0/users/-/collections/{subject_id}/episodes）。
  ///
  /// 返回 episodeId → 章节收藏类型（0=未收藏 1=想看 2=看过 3=抛弃）；
  /// 条目未收藏（404）返回空表，供增量对比只标差集。
  Future<Map<int, int>> fetchCollectedEpisodes(int subjectId) async {
    final result = <int, int>{};
    int offset = 0;
    const int pageSize = 100;
    while (true) {
      final res = await _request(
        'GET',
        '/v0/users/-/collections/$subjectId/episodes',
        query: <String, dynamic>{'limit': pageSize, 'offset': offset},
        allowedStatus: const <int>{404},
      );
      if (res.statusCode == 404) return result;
      final data = res.data;
      if (data is! Map<String, dynamic>) break;
      final list = data['data'];
      if (list is! List) break;
      for (final item in list.whereType<Map<String, dynamic>>()) {
        final episode = item['episode'];
        final id = episode is Map<String, dynamic>
            ? (episode['id'] as num?)?.toInt() ?? 0
            : 0;
        if (id > 0) {
          result[id] = (item['type'] as num?)?.toInt() ?? 0;
        }
      }
      final total = (data['total'] as num?)?.toInt() ?? result.length;
      offset += pageSize;
      if (result.length >= total || list.isEmpty) break;
    }
    return result;
  }

  /// 分页拉取用户收藏列表（GET /v0/users/{username}/collections）。
  ///
  /// [subjectType] 限定条目类型；[collectionType] 限定收藏状态
  /// （[BangumiCollectionType] 五状态之一，null = 不限）。
  /// 用于「从 Bangumi 导入」按标题匹配建绑定与设置页收藏浏览。
  Future<List<BangumiUserCollection>> fetchUserCollections(
    String username, {
    required int subjectType,
    int? collectionType,
  }) async {
    final collections = <BangumiUserCollection>[];
    int offset = 0;
    const int pageSize = 50;
    while (true) {
      final res = await _request(
        'GET',
        '/v0/users/$username/collections',
        query: <String, dynamic>{
          'subject_type': subjectType,
          if (collectionType != null) 'type': collectionType,
          'limit': pageSize,
          'offset': offset,
        },
      );
      final data = res.data;
      if (data is! Map<String, dynamic>) break;
      final list = data['data'];
      if (list is! List) break;
      collections.addAll(list
          .whereType<Map<String, dynamic>>()
          .map(BangumiUserCollection.fromJson));
      final total = (data['total'] as num?)?.toInt() ?? collections.length;
      offset += pageSize;
      if (collections.length >= total || list.isEmpty) break;
    }
    return collections;
  }

  /// 批量标记剧集为看过（PATCH /v0/users/-/collections/{subject_id}/episodes）。
  ///
  /// 批量端点不可用（405/404）时回退逐集
  /// `PUT /v0/users/-/collections/-/episodes/{episode_id}`。
  Future<void> markEpisodesWatched(int subjectId, List<int> episodeIds) async {
    if (episodeIds.isEmpty) return;
    try {
      await _request(
        'PATCH',
        '/v0/users/-/collections/$subjectId/episodes',
        body: <String, dynamic>{
          'episode_id': episodeIds,
          'type': 2, // 2 = 看过
        },
      );
      return;
    } on BangumiApiException catch (e) {
      // 端点缺失时回退逐集标记；鉴权/参数错误直接上抛。
      if (e.statusCode != 404 && e.statusCode != 405) rethrow;
    }
    for (final id in episodeIds) {
      await _request(
        'PUT',
        '/v0/users/-/collections/-/episodes/$id',
        body: <String, dynamic>{'type': 2},
      );
    }
  }
}
