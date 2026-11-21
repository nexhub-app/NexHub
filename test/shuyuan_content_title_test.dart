/// 正文标题规则（ruleContent.title）贯通：解析层 → MediaApiService。
///
/// 对照 legado BookContent：标题规则在页拼接后求值一次，命中后回写
/// BookChapter.title；结果带 `<img>` 地址尾巴时剥离为章节名（imgRegex），
/// 剥离后为空则回落到目录章节名。本地 HTTP 合成页面，不访问真实站点。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/core/resolver/resolver_registry.dart';
import 'package:nexhub/core/scraper/media_api_service.dart';
import 'package:nexhub/features/shuyuan/presentation/shuyuan_novel_resolver.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    registerShuyuanResolver(ShuyuanNovelResolver.new);
  });

  Future<(HttpServer, String)> startServer(Map<String, String> routes) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) {
      final body = routes[req.uri.path];
      req.response
        ..statusCode = body == null ? 404 : 200
        ..headers.contentType = ContentType.html
        ..write(body ?? '');
      req.response.close();
    });
    return (server, 'http://127.0.0.1:${server.port}');
  }

  PluginConfig sourceOf(String origin, {String? titleRule}) {
    return ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(
      <String, dynamic>{
        'bookSourceName': 'content-title',
        'bookSourceUrl': origin,
        'bookSourceType': 0,
        'ruleContent': <String, dynamic>{
          'content': '#c@html',
          if (titleRule != null) 'title': titleRule,
        },
      },
    ));
  }

  test('标题规则命中：fetchNovelContentDetailed 返回规则结果', () async {
    final (server, origin) = await startServer(<String, String>{
      '/c1.html': '<h1 class="t">第九章 风起</h1><div id="c">正文内容</div>',
    });
    final service = MediaApiService(ResolverRegistry.instance);
    final result = await service.fetchNovelContentDetailed(
      sourceOf(origin, titleRule: 'h1.t@text'),
      novelId: '1',
      chapterUrl: '$origin/c1.html',
      chapterTitle: '目录原名',
    );
    expect(result.title, '第九章 风起');
    expect(result.blocks, isNotEmpty);
    await server.close(force: true);
  });

  test('标题规则带图片地址尾巴：剥离为章节名（legado imgRegex）', () async {
    final (server, origin) = await startServer(<String, String>{
      '/c2.html':
          '<h1 class="t">第十章 云涌https://img.example.com/a.jpg</h1>'
              '<div id="c">正文</div>',
    });
    final service = MediaApiService(ResolverRegistry.instance);
    final result = await service.fetchNovelContentDetailed(
      sourceOf(origin, titleRule: 'h1.t@text'),
      novelId: '1',
      chapterUrl: '$origin/c2.html',
      chapterTitle: '目录原名',
    );
    expect(result.title, '第十章 云涌');
    await server.close(force: true);
  });

  test('标题规则只剩图片地址：回落到目录章节名', () async {
    final (server, origin) = await startServer(<String, String>{
      '/c3.html': '<h1 class="t">https://img.example.com/a.jpg</h1>'
          '<div id="c">正文</div>',
    });
    final service = MediaApiService(ResolverRegistry.instance);
    final result = await service.fetchNovelContentDetailed(
      sourceOf(origin, titleRule: 'h1.t@text'),
      novelId: '1',
      chapterUrl: '$origin/c3.html',
      chapterTitle: '目录原名',
    );
    expect(result.title, '目录原名');
    await server.close(force: true);
  });

  test('未声明标题规则：title 为 null（阅读器沿用目录名）', () async {
    final (server, origin) = await startServer(<String, String>{
      '/c4.html': '<h1 class="t">规则外标题</h1><div id="c">正文</div>',
    });
    final service = MediaApiService(ResolverRegistry.instance);
    final result = await service.fetchNovelContentDetailed(
      sourceOf(origin),
      novelId: '1',
      chapterUrl: '$origin/c4.html',
      chapterTitle: '目录原名',
    );
    expect(result.title, isNull);
    await server.close(force: true);
  });

  test('规则可读阅读进度：book.durChapterIndex/durChapterTitle', () async {
    final (server, origin) = await startServer(<String, String>{
      '/c5.html': '<div id="c">正文</div>',
    });
    final service = MediaApiService(ResolverRegistry.instance);
    final result = await service.fetchNovelContentDetailed(
      sourceOf(origin,
          titleRule: '@js:"#"+book.durChapterIndex+" "+book.durChapterTitle'),
      novelId: '1',
      chapterUrl: '$origin/c5.html',
      chapterTitle: '目录原名',
      durChapterIndex: 7,
      durChapterTitle: '进度章名',
    );
    // durChapterIndex 为数值（legado Book 字段是 Int），title 为字符串。
    expect(result.title, '#7 进度章名');
    await server.close(force: true);
  });
}
