/// Bangumi token 自动续期回归测试。
///
/// 覆盖：
/// - [BangumiClient] 带 token 的请求收到 401 时触发续期回调，成功后用新
///   token 立即重试一次；
/// - 续期失败 / 匿名请求不重试，401 原样抛出；
/// - [BangumiAuth] 收到 401 后用 refresh_token 换取新 access_token 并落盘，
///   无 refresh_token（个人 token 登录）时不访问 token 端点。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/services/bangumi/bangumi_auth.dart';
import 'package:nexhub/core/services/bangumi/bangumi_client.dart';

/// 可编程 Dio 适配器：按 [handler] 返回响应，并记录每个请求。
class _RouteAdapter implements HttpClientAdapter {
  _RouteAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int statusCode, Map<String, dynamic> body) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );
}

String _pathOf(RequestOptions options) =>
    Uri.tryParse(options.path)?.path ?? options.path;

/// 与生产 [BangumiClient._buildDio] 一致：非 2xx 也返回响应而不抛异常。
Dio _dioWith(_RouteAdapter adapter) => Dio(
      BaseOptions(validateStatus: (_) => true),
    )..httpClientAdapter = adapter;

/// 内存版安全存储：不触碰平台通道。
class _MemoryStorage extends FlutterSecureStorage {
  final Map<String, String> data = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    data.remove(key);
  }
}

void main() {
  group('令牌净化与迁移', () {
    test('去掉换行 / 零宽字符 / 引号 / 重复 Bearer 前缀', () {
      expect(BangumiAuth.sanitizeToken('  abc123  '), 'abc123');
      expect(BangumiAuth.sanitizeToken('abc\n123'), 'abc123');
      expect(BangumiAuth.sanitizeToken('abc\u200B123'), 'abc123');
      expect(BangumiAuth.sanitizeToken('\uFEFFabc123'), 'abc123');
      expect(BangumiAuth.sanitizeToken('"abc123"'), 'abc123');
      expect(BangumiAuth.sanitizeToken('Bearer abc123'), 'abc123');
      expect(BangumiAuth.sanitizeToken('bearer abc123'), 'abc123');
      expect(BangumiAuth.sanitizeToken('token=abc123'), 'abc123');
      // 中文输入法的全角字母数字。
      expect(BangumiAuth.sanitizeToken('ａｂｃ１２３'), 'abc123');
      // 以 bearer 开头但不是请求头的令牌本体不应被砍。
      expect(BangumiAuth.sanitizeToken('bearerabc123'), 'bearerabc123');
      expect(BangumiAuth.sanitizeToken('  '), '');
    });

    test('冷启动读取时净化历史脏令牌并写回', () async {
      final adapter = _RouteAdapter((_) => _json(200, <String, dynamic>{
            'id': 1,
            'username': 'tester',
            'nickname': 'Tester',
          }));
      final storage = _MemoryStorage()
        // 旧版本直接存粘贴原文：带首尾空格 + 零宽字符 + 换行。
        ..data['bangumi_access_token'] = ' stale-token\u200B\n'
        ..data['bangumi_username'] = 'tester';
      final client = BangumiClient(dio: _dioWith(adapter));
      final auth = BangumiAuth(client: client, storage: storage);
      await auth.init();

      expect(auth.isLoggedIn, isTrue);
      expect(client.token, 'stale-token');
      expect(storage.data['bangumi_access_token'], 'stale-token');
    });
  });

  group('BangumiClient 401 续期重试', () {
    test('续期成功后用新 token 立即重试一次', () async {
      var calls = 0;
      final adapter = _RouteAdapter((options) {
        calls++;
        if (calls == 1) {
          return _json(401, <String, dynamic>{
            'description': "access token has been expired or doesn't exist",
          });
        }
        return _json(200, <String, dynamic>{
          'id': 1,
          'username': 'tester',
          'nickname': 'Tester',
        });
      });
      final client = BangumiClient(dio: _dioWith(adapter))
        ..token = 'stale-token';
      var refreshCalls = 0;
      String? reportedHost;
      client.onUnauthorized = (host) async {
        refreshCalls++;
        reportedHost = host;
        client.token = 'fresh-token';
        return true;
      };

      final me = await client.fetchMe();

      expect(me.username, 'tester');
      expect(refreshCalls, 1);
      expect(reportedHost, 'api.bgm.tv');
      expect(adapter.requests, hasLength(2));
      expect(
        adapter.requests.first.headers['Authorization'],
        'Bearer stale-token',
      );
      expect(
        adapter.requests.last.headers['Authorization'],
        'Bearer fresh-token',
      );
    });

    test('续期失败时不再重试，401 原样抛出', () async {
      final adapter = _RouteAdapter(
        (_) => _json(401, <String, dynamic>{
          'description': "access token has been expired or doesn't exist",
        }),
      );
      final client = BangumiClient(dio: _dioWith(adapter))
        ..token = 'stale-token';
      var refreshCalls = 0;
      client.onUnauthorized = (_) async {
        refreshCalls++;
        return false;
      };

      await expectLater(
        client.fetchMe(),
        throwsA(
          isA<BangumiApiException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.host, 'host', 'api.bgm.tv'),
        ),
      );
      expect(refreshCalls, 1);
      expect(adapter.requests, hasLength(1));
    });

    test('匿名请求的 401 不触发续期', () async {
      final adapter = _RouteAdapter(
        (_) => _json(401, <String, dynamic>{'description': 'unauthorized'}),
      );
      final client = BangumiClient(dio: _dioWith(adapter));
      var refreshCalls = 0;
      client.onUnauthorized = (_) async {
        refreshCalls++;
        return true;
      };

      await expectLater(
        client.fetchMe(),
        throwsA(
          isA<BangumiApiException>()
              .having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
      expect(refreshCalls, 0);
      expect(adapter.requests, hasLength(1));
    });
  });

  group('BangumiAuth 401 自动续期', () {
    test('用 refresh_token 换新 access_token 并重试原请求', () async {
      var meCalls = 0;
      RequestOptions? tokenRequest;
      final adapter = _RouteAdapter((options) {
        final path = _pathOf(options);
        if (path == '/oauth/access_token') {
          tokenRequest = options;
          return _json(200, <String, dynamic>{
            'access_token': 'fresh-token',
            'refresh_token': 'refresh-new',
            'expires_in': 604800,
          });
        }
        if (path == '/v0/me') {
          meCalls++;
          if (meCalls == 1) {
            return _json(401, <String, dynamic>{
              'description': "access token has been expired or doesn't exist",
            });
          }
          return _json(200, <String, dynamic>{
            'id': 1,
            'username': 'tester',
            'nickname': 'Tester',
          });
        }
        return _json(404, <String, dynamic>{});
      });
      final storage = _MemoryStorage()
        ..data['bangumi_access_token'] = 'stale-token'
        ..data['bangumi_username'] = 'tester'
        ..data['bangumi_refresh_token'] = 'refresh-old'
        // 过期时间在远方：走「收到 401 再续期」，而非提前续期。
        ..data['bangumi_expires_at'] =
            '${DateTime.now().add(const Duration(days: 5)).millisecondsSinceEpoch}';
      final client = BangumiClient(dio: _dioWith(adapter));
      final auth = BangumiAuth(client: client, storage: storage);
      await auth.init();
      expect(auth.isLoggedIn, isTrue);
      expect(auth.sessionExpired, isFalse);

      await auth.refreshProfile();

      expect(meCalls, 2);
      expect(client.token, 'fresh-token');
      expect(storage.data['bangumi_access_token'], 'fresh-token');
      expect(storage.data['bangumi_refresh_token'], 'refresh-new');
      expect(
        adapter.requests.map(_pathOf),
        <String>['/v0/me', '/oauth/access_token', '/v0/me'],
      );
      final form = tokenRequest!.data as Map<String, String>;
      expect(form['grant_type'], 'refresh_token');
      expect(form['refresh_token'], 'refresh-old');
    });

    test('临近过期先主动续期，首个请求不再吃 401', () async {
      var meCalls = 0;
      final adapter = _RouteAdapter((options) {
        final path = _pathOf(options);
        if (path == '/oauth/access_token') {
          return _json(200, <String, dynamic>{
            'access_token': 'fresh-token',
            'refresh_token': 'refresh-new',
            'expires_in': 604800,
          });
        }
        if (path == '/v0/me') {
          meCalls++;
          return _json(200, <String, dynamic>{
            'id': 1,
            'username': 'tester',
            'nickname': 'Tester',
          });
        }
        return _json(404, <String, dynamic>{});
      });
      final storage = _MemoryStorage()
        ..data['bangumi_access_token'] = 'stale-token'
        ..data['bangumi_username'] = 'tester'
        ..data['bangumi_refresh_token'] = 'refresh-old'
        ..data['bangumi_expires_at'] = '1'; // 已过期
      final client = BangumiClient(dio: _dioWith(adapter));
      final auth = BangumiAuth(client: client, storage: storage);
      await auth.init();

      await auth.refreshProfile();

      expect(meCalls, 1);
      expect(
        adapter.requests.map(_pathOf),
        <String>['/oauth/access_token', '/v0/me'],
      );
      expect(
        adapter.requests
            .firstWhere((r) => _pathOf(r) == '/v0/me')
            .headers['Authorization'],
        'Bearer fresh-token',
      );
    });

    test('refresh_token 被服务端拒绝时清空会话并标记过期', () async {
      final adapter = _RouteAdapter((options) {
        final path = _pathOf(options);
        if (path == '/oauth/access_token') {
          return _json(400, <String, dynamic>{
            'error': 'invalid_grant',
            'error_description': 'Refresh token has been expired',
          });
        }
        return _json(401, <String, dynamic>{
          'description': "access token has been expired or doesn't exist",
        });
      });
      final storage = _MemoryStorage()
        ..data['bangumi_access_token'] = 'stale-token'
        ..data['bangumi_username'] = 'tester'
        ..data['bangumi_refresh_token'] = 'refresh-dead'
        ..data['bangumi_expires_at'] =
            '${DateTime.now().add(const Duration(days: 5)).millisecondsSinceEpoch}';
      final client = BangumiClient(dio: _dioWith(adapter));
      final auth = BangumiAuth(client: client, storage: storage);
      await auth.init();

      await expectLater(
        auth.refreshProfile(),
        throwsA(isA<BangumiApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)),
      );

      // 会话已清空：UI 会切回登录态并提示重新授权，不再停在必然 401 的死角。
      expect(auth.isLoggedIn, isFalse);
      expect(auth.sessionExpired, isTrue);
      expect(auth.lastAuthError, contains('Refresh token'));
      expect(storage.data['bangumi_access_token'], isNull);
      expect(storage.data['bangumi_refresh_token'], isNull);
      expect(client.token, isNull);
    });

    test('无 refresh_token 时不访问 token 端点，401 原样抛出', () async {
      final adapter = _RouteAdapter(
        (_) => _json(401, <String, dynamic>{
          'description': "access token has been expired or doesn't exist",
        }),
      );
      final storage = _MemoryStorage()
        ..data['bangumi_access_token'] = 'personal-token'
        ..data['bangumi_username'] = 'tester';
      final client = BangumiClient(dio: _dioWith(adapter));
      final auth = BangumiAuth(client: client, storage: storage);
      await auth.init();

      await expectLater(
        auth.refreshProfile(),
        throwsA(
          isA<BangumiApiException>()
              .having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
      expect(adapter.requests.map(_pathOf), <String>['/v0/me']);
      // 个人 token 被官方 API 明确拒绝 → 同样清空会话（避免假装在线）。
      expect(auth.isLoggedIn, isFalse);
      expect(auth.sessionExpired, isTrue);
    });
  });
}
