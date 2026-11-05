/// Bangumi 账号认证（个人 Access Token 路径 + OAuth 2.0 发布形态）。
///
/// - token 与用户名存 [FlutterSecureStorage]；
/// - `saveToken` 先调 `/v0/me` 校验有效性再落盘；
/// - OAuth 完整形态见 [loginWithOAuth]：引导浏览器授权 → 深链回调取 code →
/// 换 access_token + refresh_token（均存安全存储，refresh 用以续期）；
/// - 401 生命周期：请求前主动续期（临近过期）→ 收到 401 再续期一次并重试 →
/// 续期被服务端明确拒绝时清空本地会话（[sessionExpired]），交 UI 引导重新授权。
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'bangumi_client.dart';
import 'bangumi_models.dart';
import 'bangumi_oauth_browser.dart';
import 'bangumi_oauth_config.dart';
import 'bangumi_proxy_config.dart';

/// Bangumi 认证管理器——全应用单例（Provider 注入）。
class BangumiAuth extends ChangeNotifier {
  BangumiAuth({
    required BangumiClient client,
    FlutterSecureStorage? storage,
  })  : _client = client,
        _storage = storage ?? const FlutterSecureStorage() {
    // 所有 Bangumi API 请求共用本 client：
    // - 请求前：access_token 临近过期则先续期，避免必然失败的首个 401；
    // - 收到 401：用 refresh_token 续期，成功后由 client 用新 token 自动重试。
    _client.onUnauthorized = _refreshOnUnauthorized;
    _client.onBeforeRequest = _ensureFreshToken;
  }

  static const String _tokenKey = 'bangumi_access_token';
  static const String _usernameKey = 'bangumi_username';
  static const String _nicknameKey = 'bangumi_nickname';
  static const String _refreshTokenKey = 'bangumi_refresh_token';
  static const String _expiresAtKey = 'bangumi_expires_at';

  /// 提前续期窗口：距过期不足该时长即主动换新（7 天有效期里留半天余量）。
  static const Duration _refreshSkew = Duration(hours: 12);

  /// 官方 API 主机（判断「令牌被服务端拒绝」而非「镜像丢鉴权头」）。
  static const String _officialApiHost = 'api.bgm.tv';

  final BangumiClient _client;
  final FlutterSecureStorage _storage;

  String? _token;
  String? _username;
  String? _nickname;

  /// OAuth refresh_token（用于 [refresh] 续期）。
  String? _refreshToken;

  /// access_token 过期时刻（毫秒时间戳），null = 未知/不过期。
  int? _expiresAt;

  /// 进行中的续期（并发 401 共用同一次刷新）。
  Future<void>? _refreshing;

  /// 会话是否已被判定失效（续期被服务端拒绝 / 个人 token 被官方拒绝）。
  ///
  /// 置位时本地凭证已清空，UI 可据此提示「重新授权」而不是停留在
  /// 「看着已登录、每次请求都 401」的死角。
  bool _sessionExpired = false;

  String? _lastAuthError;

  bool get isLoggedIn => _token != null && _token!.isNotEmpty;

  /// 会话是否因鉴权失败被清空（提示重新登录用）。
  bool get sessionExpired => _sessionExpired;

  /// 会话失效的具体原因（诊断用，可能为服务端原文）。
  String? get lastAuthError => _lastAuthError;

  /// 登录名（API 路径用，如拉取用户收藏列表）。
  String? get username => _username;

  /// 展示名：优先昵称，缺省回退登录名。
  String? get displayName =>
      (_nickname != null && _nickname!.isNotEmpty) ? _nickname : _username;

  /// OAuth refresh_token（空表示非 OAuth 登录，无法续期）。
  String? get refreshToken => _refreshToken;

  /// access_token 是否已过期（基于 [expiresAt]）；未知时视为未过期。
  bool get isExpired =>
      _expiresAt != null &&
      DateTime.now().millisecondsSinceEpoch >= _expiresAt!;

  /// 是否已进入提前续期窗口（过期前 [_refreshSkew] 内）。
  bool get _nearExpiry {
    final at = _expiresAt;
    if (at == null) return false;
    return DateTime.now().millisecondsSinceEpoch + _refreshSkew.inMilliseconds >=
        at;
  }

  /// 冷启动恢复已存 token（注入 client 后通知 UI）。
  ///
  /// 历史版本直接存了用户粘贴的原文，可能带换行 / 零宽字符——这类值在
  /// 请求头里合法、服务端却认不出（回 401「doesn't exist」）。读取时净化
  /// 一次并写回，老用户不必重新粘贴。
  Future<void> init() async {
    try {
      _token = await _storage.read(key: _tokenKey);
      _username = await _storage.read(key: _usernameKey);
      _nickname = await _storage.read(key: _nicknameKey);
      _refreshToken = await _storage.read(key: _refreshTokenKey);
      final expiresRaw = await _storage.read(key: _expiresAtKey);
      _expiresAt = int.tryParse(expiresRaw ?? '');
    } catch (_) {
      // secure storage 不可用（如桌面端缺 keyring）时按未登录处理。
      _token = null;
      _username = null;
      _nickname = null;
      _refreshToken = null;
      _expiresAt = null;
    }
    final raw = _token;
    if (raw != null && raw.isNotEmpty) {
      final normalized = sanitizeToken(raw);
      if (normalized != raw) {
        _token = normalized.isEmpty ? null : normalized;
        if (_token != null) await _writeQuietly(_tokenKey, _token!);
      }
    }
    // refresh_token 同样可能是粘贴 / 旧版本遗留的脏值，一并净化。
    final refreshRaw = _refreshToken;
    if (refreshRaw != null && refreshRaw.isNotEmpty) {
      final normalized = sanitizeToken(refreshRaw);
      if (normalized != refreshRaw) {
        _refreshToken = normalized.isEmpty ? null : normalized;
        if (_refreshToken != null) {
          await _writeQuietly(_refreshTokenKey, _refreshToken!);
        }
      }
    }
    _sessionExpired = false;
    _lastAuthError = null;
    _client.token = _token;
    notifyListeners();
  }

  /// 落盘会话（token / 用户名 / 昵称）。refresh_token 与过期时间由调用方另行写入。
  ///
  /// 写安全存储失败（桌面端 keyring 抖动 / 权限异常）不回退内存态：内存中的
  /// token 已可用，写盘失败只影响下次冷启动，不该让本次登录 / 续期算作失败。
  Future<void> _persistSession({
    required String token,
    required String username,
    String? nickname,
  }) async {
    _token = token;
    _username = username;
    _nickname = nickname;
    _client.token = token;
    await _writeQuietly(_tokenKey, token);
    await _writeQuietly(_usernameKey, username);
    if (nickname != null) {
      await _writeQuietly(_nicknameKey, nickname);
    }
    notifyListeners();
  }

  /// 安全存储写入（吞掉平台异常）。
  Future<void> _writeQuietly(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      /* 落盘失败不影响本次会话 */
    }
  }

  /// 安全存储删除（吞掉平台异常）。
  Future<void> _deleteQuietly(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {
      /* 忽略 */
    }
  }

  /// 校验并保存个人 Access Token。
  ///
  /// 先用该 token 调 `/v0/me`，通过后才持久化；校验失败抛
  /// [BangumiApiException]（401 = token 无效）。
  ///
  /// 粘贴值先经 [sanitizeToken] 净化：从网页复制的令牌常带换行、零宽字符、
  /// 包裹引号或连 `Bearer ` 前缀一起复制，服务端会当成「不认识的令牌」回 401
  /// （原文 `access token has been expired or doesn't exist`，与真过期无法区分）。
  ///
  /// 个人 token 不带 refresh_token，无法续期：落盘时一并清掉上一个 OAuth
  /// 会话残留的 refresh_token / 过期时间，避免校验期的 401 拿旧账号的
  /// refresh_token 换出另一个账号的 token（串号 + 后续请求错乱）。
  Future<void> saveToken(String token) async {
    final normalized = sanitizeToken(token);
    if (normalized.isEmpty) {
      throw const BangumiApiException(401, 'empty token');
    }
    final previous = _client.token;
    final previousRefresh = _refreshToken;
    final previousExpiresAt = _expiresAt;
    _client.token = normalized;
    _refreshToken = null;
    _expiresAt = null;
    try {
      final me = await _client.fetchMe();
      await _persistSession(
        token: normalized,
        username: me.username,
        nickname: me.nickname,
      );
      await _deleteQuietly(_refreshTokenKey);
      await _deleteQuietly(_expiresAtKey);
      _sessionExpired = false;
      _lastAuthError = null;
      notifyListeners();
    } catch (_) {
      _client.token = previous;
      _refreshToken = previousRefresh;
      _expiresAt = previousExpiresAt;
      rethrow;
    }
  }

  /// 净化令牌字符串：去掉复制粘贴带进来的杂质。
  ///
  /// 处理：零宽字符（U+200B–U+200D、U+FEFF）、包裹与内嵌引号（含中文引号）、
  /// 误带的 `Bearer ` / `token=` 前缀，最后去掉全部空白（含换行 / 制表符）。
  ///
  /// 前缀只在**后面跟空白**时才剥（`Bearer xxx`）；令牌本身是 base64 风格串，
  /// 有极小概率以 `bearer` 开头，不能无条件砍。
  static String sanitizeToken(String raw) {
    var value = raw;
    // 零宽字符（正则的 \s 不覆盖它们，是「令牌看着对却 401」的常见元凶）。
    value = value.replaceAll(RegExp('[\u200B-\u200F\u202A-\u202E\uFEFF]'), '');
    // 包裹 / 内嵌引号。
    value = value.replaceAll(RegExp('["\'\u2018\u2019\u201C\u201D]'), '');
    value = value.trim();
    // 误把请求头一起复制进来（`Bearer <token>` / `token=<token>`）。
    value = value.replaceFirst(
      RegExp(r'^bearer\s+', caseSensitive: false),
      '',
    );
    value = value.replaceFirst(
      RegExp(r'^token\s*=\s*', caseSensitive: false),
      '',
    );
    // 中文输入法可能把字母数字转成全角（Ａ-Ｚ / ０-９），折回半角。
    value = value.replaceAllMapped(
      RegExp('[\uFF01-\uFF5E]'),
      (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0xFEE0),
    );
    // 其余全部空白（含 \r\n\t、不断行空格、全角空格）。
    return value.replaceAll(RegExp(r'\s+'), '');
  }

  /// 当前令牌的指纹（首尾各 4 位 + 总长度），用于和官网对照而不泄露明文。
  String? get tokenFingerprint {
    final t = _token;
    if (t == null || t.isEmpty) return null;
    if (t.length <= 8) return 'len${t.length}';
    return '${t.substring(0, 4)}…${t.substring(t.length - 4)} len${t.length}';
  }

  /// OAuth 2.0 授权码登录（发布形态）。
  ///
  /// 流程：用嵌入式 [InAppWebView] Dialog 打开 `https://bgm.tv/oauth/authorize`
  /// → 用户授权后 Bangumi 回跳 `nexhub://oauth/callback?code=...`，由 WebView
  /// 直接截获（对话框由应用完全掌控生命周期，不会因系统/浏览器窗口返回手势导致
  /// 界面一直转圈）→ 用 code 换 access_token，再走与 [saveToken] 相同的存储路径
  /// （并额外存 refresh_token 与过期时间）。
  ///
  /// 前置条件：已在 [BangumiOAuthConfig] 填入 Client ID / Secret，否则抛
  /// [StateError]。用户取消授权 / 关闭浏览器返回 null 时抛 [StateError]。
  Future<void> loginWithOAuth(BuildContext context) async {
    if (!BangumiOAuthConfig.configured) {
      throw StateError('bangumi oauth not configured');
    }
    final state = _randomState();
    // 授权页与令牌端点必须同源：镜像模式下走配置的主站域名，否则会出现
    // 「授权走官方、换 token 走镜像」的割裂（官方域名不可达时登录必失败）。
    final authorizeUrl =
        Uri.parse('${BangumiProxyConfig.instance.oauthBaseUrl}/oauth/authorize')
            .replace(queryParameters: <String, String>{
      'client_id': BangumiOAuthConfig.clientId,
      'response_type': 'code',
      'redirect_uri': BangumiOAuthConfig.redirectUri,
      if (BangumiOAuthConfig.scopes.isNotEmpty)
        'scope': BangumiOAuthConfig.scopes.join(' '),
      'state': state,
    }).toString();

    final code = await openBangumiOAuthBrowser(
      context: context,
      authorizeUrl: authorizeUrl,
      redirectScheme: BangumiOAuthConfig.redirectUri,
    );
    // 用户取消 / 关闭浏览器：code 为空，按失败处理（由调用方捕获并提示）。
    if (code == null || code.isEmpty) {
      throw StateError('bangumi oauth cancelled');
    }
    final token = await _client.exchangeCodeForToken(
      clientId: BangumiOAuthConfig.clientId,
      clientSecret: BangumiOAuthConfig.clientSecret,
      code: code,
      redirectUri: BangumiOAuthConfig.redirectUri,
    );
    await _adoptOAuthToken(token);
  }

  /// 落盘 OAuth 换回的令牌（先装 refresh_token，再校验 /v0/me）。
  ///
  /// 顺序很关键：refresh_token 必须在 `/v0/me` 校验**之前**生效，
  /// 否则校验请求若因时钟偏差拿到 401，续期分支拿不到 refresh_token，
  /// 登录会以 401 失败——用户看到的就是「刚授权完就提示 token 已过期」。
  Future<void> _adoptOAuthToken(BangumiToken token) async {
    final previous = _client.token;
    final previousRefresh = _refreshToken;
    final previousExpiresAt = _expiresAt;
    _client.token = token.accessToken;
    // 直接取自本次授权结果（不回退上一个会话的 refresh_token，避免串号）。
    _refreshToken = token.refreshToken;
    _expiresAt = token.expiresIn != null
        ? DateTime.now()
            .add(Duration(seconds: token.expiresIn!))
            .millisecondsSinceEpoch
        : null;
    try {
      final me = await _client.fetchMe();
      // 校验期间可能已续期：以 client 当前 token 为准落盘。
      final current = _client.token ?? token.accessToken;
      await _persistSession(
        token: current,
        username: me.username,
        nickname: me.nickname,
      );
      if (_refreshToken != null && _refreshToken!.isNotEmpty) {
        await _writeQuietly(_refreshTokenKey, _refreshToken!);
      }
      if (_expiresAt != null) {
        await _writeQuietly(_expiresAtKey, _expiresAt!.toString());
      }
      _sessionExpired = false;
      _lastAuthError = null;
      notifyListeners();
    } catch (_) {
      _client.token = previous;
      _refreshToken = previousRefresh;
      _expiresAt = previousExpiresAt;
      rethrow;
    }
  }

  /// 用 refresh_token 续期 access_token。
  ///
  /// 非 OAuth 登录（_refreshToken 为空）时直接返回，不做任何操作。
  /// 并发调用共用同一次刷新，避免轮换后的 refresh_token 被并发请求作废。
  Future<void> refresh() {
    final pending = _refreshing;
    if (pending != null) return pending;
    final future = _doRefresh().whenComplete(() => _refreshing = null);
    _refreshing = future;
    return future;
  }

  /// [BangumiClient.onBeforeRequest] 钩子：临近过期时先续期。
  ///
  /// 无 refresh_token（个人 token）或未临近过期时是空操作，不产生额外请求。
  Future<void> _ensureFreshToken() async {
    if (!isLoggedIn) return;
    final refreshToken = _refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return;
    if (!_nearExpiry) return;
    try {
      await refresh();
    } on BangumiApiException catch (e) {
      // 与 401 分支同样的判定：续期被明确拒绝即视为会话失效。
      if (_isSessionFatal(e)) await _expireSession(e.message);
    } catch (_) {
      // 网络 / 解析失败：不阻断本次请求，真鉴权问题由 401 分支统一处置。
    }
  }

  /// [BangumiClient.onUnauthorized] 回调：续期成功返回 true。
  ///
  /// 判定顺序（尽量自愈，不轻易清会话）：
  /// 1. 令牌被粘贴污染（含空白 / 零宽字符 / 重复 `Bearer`）→ 净化后若与当前
  ///    值不同，直接用净化值重试一次。服务端对这类值回的就是「不认识的令牌」，
  ///    与「真过期」同一条 401 文案，靠这一步区分；
  /// 2. 有 refresh_token → 续期一次，被令牌端点明确拒绝（400/401/403）才判定
  ///    会话失效；
  /// 3. 无 refresh_token（个人 token）→ 仅当拒绝来自官方 API 主机才判定失效，
  ///    镜像反代丢鉴权头之类的环境问题不清会话，避免误登出。
  Future<bool> _refreshOnUnauthorized(String host) async {
    final current = _token;
    if (current != null && current.isNotEmpty) {
      final normalized = sanitizeToken(current);
      if (normalized != current && normalized.isNotEmpty) {
        _token = normalized;
        _client.token = normalized;
        await _writeQuietly(_tokenKey, normalized);
        return true; // 让 client 用净化后的令牌重试
      }
    }
    final refreshToken = _refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      if (host == _officialApiHost) {
        await _expireSession('token rejected by server', host: host);
      }
      return false;
    }
    try {
      await refresh();
      return true;
    } on BangumiApiException catch (e) {
      if (_isSessionFatal(e)) {
        await _expireSession(e.message, host: host);
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 续期失败是否属于「会话确实失效」。
  ///
  /// `invalid_client` 是构建期 OAuth 凭据缺失 / 错误（`--dart-define` 未注入），
  /// 与用户会话无关，不能据此清空凭证——否则换个构建就把登录态清掉。
  bool _isSessionFatal(BangumiApiException e) {
    if (e.oauthErrorCode == 'invalid_client') return false;
    final code = e.statusCode;
    return code == 400 || code == 401 || code == 403;
  }

  /// 续期：用 refresh_token 换新 access_token 并落盘。
  Future<void> _doRefresh() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return;
    final token = await _client.refreshToken(
      clientId: BangumiOAuthConfig.clientId,
      clientSecret: BangumiOAuthConfig.clientSecret,
      refreshToken: refreshToken,
      redirectUri: BangumiOAuthConfig.redirectUri,
    );
    _token = token.accessToken;
    _client.token = token.accessToken;
    _refreshToken = token.refreshToken ?? refreshToken;
    _expiresAt = token.expiresIn != null
        ? DateTime.now()
            .add(Duration(seconds: token.expiresIn!))
            .millisecondsSinceEpoch
        : null;
    _sessionExpired = false;
    _lastAuthError = null;
    await _writeQuietly(_tokenKey, _token!);
    await _writeQuietly(_refreshTokenKey, _refreshToken!);
    if (_expiresAt != null) {
      await _writeQuietly(_expiresAtKey, _expiresAt!.toString());
    }
    notifyListeners();
  }

  /// 判定会话失效：清空本地凭证并记录原因（供 UI 提示重新授权）。
  ///
  /// 诊断串里带令牌指纹与命中主机，方便与官网 token 管理页对照——「官网显示
  /// 2027 年有效、App 却 401」时，指纹能立刻确认 App 存的是不是同一个令牌。
  Future<void> _expireSession(String reason, {String? host}) async {
    if (_token == null || _token!.isEmpty) return;
    final fingerprint = tokenFingerprint;
    // 凭证类型对排查很关键：OAuth 会话（7 天 + refresh 续期）与个人令牌
    // （有效期至用户设定日，如官网看到的 2027）是两条互不相干的凭证。
    final kind = (_refreshToken != null && _refreshToken!.isNotEmpty)
        ? 'oauth'
        : 'personal';
    _lastAuthError = <String>[
      reason,
      'kind=$kind',
      if (host != null && host.isNotEmpty) host,
      if (fingerprint != null) 'token $fingerprint',
    ].join(' · ');
    _sessionExpired = true;
    await _clearCredentials();
    notifyListeners();
  }

  /// 用已存 token 重新拉取 `/v0/me`，补齐 / 刷新用户名与昵称。
  ///
  /// 冷启动后若本地未存 username（旧版本升级、secure storage 曾读失败），
  /// 可借此恢复；未登录时直接返回，网络 / 鉴权失败上抛供调用方处理。
  Future<void> refreshProfile() async {
    if (!isLoggedIn) return;
    final me = await _client.fetchMe();
    _username = me.username;
    _nickname = me.nickname;
    await _writeQuietly(_usernameKey, me.username);
    await _writeQuietly(_nicknameKey, me.nickname);
    notifyListeners();
  }

  /// 退出登录：清除本地凭证。
  Future<void> logout() async {
    _sessionExpired = false;
    _lastAuthError = null;
    await _clearCredentials();
    notifyListeners();
  }

  /// 清空内存与存储中的全部凭证（不改动 [sessionExpired] 标记）。
  Future<void> _clearCredentials() async {
    _token = null;
    _username = null;
    _nickname = null;
    _refreshToken = null;
    _expiresAt = null;
    _client.token = null;
    await _deleteQuietly(_tokenKey);
    await _deleteQuietly(_usernameKey);
    await _deleteQuietly(_nicknameKey);
    await _deleteQuietly(_refreshTokenKey);
    await _deleteQuietly(_expiresAtKey);
  }

  /// 生成随机 state（防 CSRF），base36 时间戳 + 随机数。
  String _randomState() {
    final r = Random();
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final rand = r.nextInt(1 << 32).toRadixString(36);
    return '$ts-$rand';
  }
}
