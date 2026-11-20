/// 图片下载「正文闸门」单测（与 legado「解码不通过就不落盘」对齐）。
///
/// 背景：缓存层会把任何 2xx 正文持久化 30 天。若拦截页/错误 JSON 被当作图片
/// 缓存，后续每次重试都命中坏文件，图片永久无法加载。下载层必须在返回响应
/// 前识别非图片正文并判失败。本测试覆盖：
/// - 分类器：HTML/JSON 拒绝；图片魔数（即使 Content-Type 撒谎）放行；SVG 放行；
/// - 真实本地 HTTP 往返：HTML、JSON、空正文 → get() 抛错；真 PNG → 正常返回。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/network/dio_image_file_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 1×1 透明 PNG（合法图片字节）。
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGA'
  'hKmMIQAAAABJRU5ErkJggg==',
);

List<int> _bytes(String s) => utf8.encode(s);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isLikelyImagePayload 分类', () {
    test('图片魔数放行（JPEG / PNG / GIF / WEBP）', () {
      expect(
          DioImageFileService.isLikelyImagePayload(
              <int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46]),
          isTrue);
      expect(DioImageFileService.isLikelyImagePayload(_png), isTrue);
      expect(DioImageFileService.isLikelyImagePayload(_bytes('GIF89a...')),
          isTrue);
      expect(
          DioImageFileService.isLikelyImagePayload(
              _bytes('RIFF\u0000\u0000\u0000\u0000WEBPVP8 ')),
          isTrue);
    });

    test('HTML 拦截页拒绝（含 BOM / 前置空白 / doctype / 注释）', () {
      expect(DioImageFileService.isLikelyImagePayload(_bytes('<!DOCTYPE html>')),
          isFalse);
      expect(DioImageFileService.isLikelyImagePayload(_bytes('\n  <html>')),
          isFalse);
      expect(DioImageFileService.isLikelyImagePayload(_bytes('<!-- x -->')),
          isFalse);
      expect(
          DioImageFileService.isLikelyImagePayload(<int>[
            0xEF, 0xBB, 0xBF, // UTF-8 BOM
            ..._bytes('<html><body>forbidden</body></html>'),
          ]),
          isFalse);
    });

    test('JSON 错误响应拒绝', () {
      expect(
          DioImageFileService.isLikelyImagePayload(
              _bytes('{"code":403,"msg":"forbidden"}')),
          isFalse);
      expect(DioImageFileService.isLikelyImagePayload(_bytes('[{"a":1}]')),
          isFalse);
    });

    test('SVG 放行（交给解码器判失败并进入逐出+重试路径）', () {
      expect(
          DioImageFileService.isLikelyImagePayload(
              _bytes('<svg xmlns="http://www.w3.org/2000/svg"/>')),
          isTrue);
    });

    test('空正文不是图片', () {
      expect(DioImageFileService.isLikelyImagePayload(<int>[]), isFalse);
    });
  });

  group('DioImageFileService.get 正文闸门（本地 HTTP）', () {
    late HttpServer server;
    late String base;

    setUpAll(() async {
      // flutter_test 可能安装网络桩；本组需要真实 localhost 往返。
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues(<String, Object>{});
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}';
      server.listen((HttpRequest req) async {
        final HttpResponse res = req.response;
        switch (req.uri.path) {
          case '/html':
            res.headers.contentType = ContentType.html;
            res.write('<!DOCTYPE html><html><body>blocked</body></html>');
            break;
          case '/json':
            res.headers.contentType = ContentType.json;
            res.write('{"code":403,"msg":"forbidden"}');
            break;
          case '/empty':
            break;
          case '/png-lying-ct':
            // Content-Type 撒谎成 html，但正文是真 PNG：必须放行。
            res.headers.contentType = ContentType.html;
            res.add(_png);
            break;
          case '/png':
            res.headers.contentType = ContentType('image', 'png');
            res.add(_png);
            break;
          default:
            res.statusCode = 404;
            res.write('not found');
        }
        await res.close();
      });
    });

    tearDownAll(() async {
      await server.close(force: true);
    });

    test('HTML 拦截页：200 也判失败', () async {
      final DioImageFileService svc = DioImageFileService();
      await expectLater(
        svc.get('$base/html'),
        throwsA(isA<HttpException>()),
      );
    });

    test('JSON 错误响应：200 也判失败', () async {
      final DioImageFileService svc = DioImageFileService();
      await expectLater(
        svc.get('$base/json'),
        throwsA(isA<HttpException>()),
      );
    });

    test('空正文：判失败（不缓存空文件）', () async {
      final DioImageFileService svc = DioImageFileService();
      await expectLater(
        svc.get('$base/empty'),
        throwsA(isA<HttpException>()),
      );
    });

    test('真 PNG 且 Content-Type 撒谎：放行且字节完整', () async {
      final DioImageFileService svc = DioImageFileService();
      final FileServiceResponse resp = await svc.get('$base/png-lying-ct');
      final BytesBuilder b = BytesBuilder(copy: false);
      await for (final List<int> chunk in resp.content) {
        b.add(chunk);
      }
      expect(resp.statusCode, 200);
      expect(b.takeBytes(), equals(_png));
    });

    test('真 PNG 正常 Content-Type：放行', () async {
      final DioImageFileService svc = DioImageFileService();
      final FileServiceResponse resp = await svc.get('$base/png');
      final BytesBuilder b = BytesBuilder(copy: false);
      await for (final List<int> chunk in resp.content) {
        b.add(chunk);
      }
      expect(b.takeBytes(), equals(_png));
    });

    test('HTTP 404 仍按状态码判失败', () async {
      final DioImageFileService svc = DioImageFileService();
      await expectLater(
        svc.get('$base/missing'),
        throwsA(isA<HttpException>()),
      );
    });
  });
}
