// 图片请求头线上级回归锁：源声明 UA 与客户端提示不能自相矛盾。
//
// 通过 loopback HttpServer 抓取真实发出的头（同 http_fetcher_403_retry_test
// 范式：TestWidgetsFlutterBinding 默认装假 HttpClient，需置空 HttpOverrides）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/scraper/http_fetcher.dart';
import 'package:nexhub/core/services/config_loader.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  setUpAll(() {
    HttpOverrides.global = null;
    ConfigLoader.instance.setStealthMode(false);
  });

  late HttpServer server;
  final List<Map<String, List<String>>> captured =
      <Map<String, List<String>>>[];

  Future<String> startServer() async {
    captured.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final headers = <String, List<String>>{};
      req.headers.forEach((name, values) {
        headers[name.toLowerCase()] = values;
      });
      captured.add(headers);
      req.response.statusCode = 200;
      req.response.headers.set('content-type', 'image/webp');
      req.response.add(const <int>[1, 2, 3, 4]);
      await req.response.close();
    });
    return 'http://127.0.0.1:${server.port}/cover.webp';
  }

  Future<void> closeServer() => server.close(force: true);

  Future<void> fetch(String url, Map<String, String> headers) async {
    await HttpFetcher.instance
        .getBytesStream(url, headers: headers, fetchDest: 'image')
        .toList();
  }

  test('源声明 UA 时：图片请求不带客户端提示三家头，UA 为声明值', () async {
    final url = await startServer();
    try {
      const sourceUa = 'Mozilla/5.0 (Android)';
      await fetch(url, const <String, String>{
        'User-Agent': sourceUa,
        'Accept': 'image/webp,image/apng,image/jpeg,image/png,image/*,*/*;q=0.8',
      });
      expect(captured, hasLength(1));
      final headers = captured.single;
      expect(headers['user-agent'], <String>[sourceUa]);
      expect(headers.containsKey('sec-ch-ua'), isFalse);
      expect(headers.containsKey('sec-ch-ua-mobile'), isFalse);
      expect(headers.containsKey('sec-ch-ua-platform'), isFalse);
      // 资产请求的 Sec-Fetch 三件套仍齐全（残缺组合本身也是机器人指纹）。
      expect(headers['sec-fetch-dest'], <String>['image']);
      expect(headers['sec-fetch-mode'], <String>['no-cors']);
      expect(headers['sec-fetch-site'], <String>['cross-site']);
    } finally {
      await closeServer();
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('无源 UA 时：保留指纹档案客户端提示（既有行为不回退）', () async {
    final url = await startServer();
    try {
      await fetch(url, const <String, String>{});
      expect(captured, hasLength(1));
      final headers = captured.single;
      expect(headers['sec-ch-ua'], isNotNull);
      expect(headers['sec-ch-ua-mobile'], isNotNull);
      expect(headers['sec-ch-ua-platform'], isNotNull);
      expect(headers['user-agent'], isNotNull);
    } finally {
      await closeServer();
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('user-agent 大小写不敏感：服务端只收到一份 UA', () async {
    final url = await startServer();
    try {
      await fetch(url, const <String, String>{'user-agent': 'Lower/1.0'});
      expect(captured, hasLength(1));
      final headers = captured.single;
      expect(headers['user-agent'], <String>['Lower/1.0']);
      expect(headers.containsKey('sec-ch-ua'), isFalse);
    } finally {
      await closeServer();
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}
