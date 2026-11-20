/// 正文停止点：MediaApiService → resolver → WebBook 的 nextChapterUrl 透传。
/// 本地 HTTP 合成三页，第三页属于下一章，必须在拉取前停止。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/novel_block.dart';
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
    // 书源解析器在 main 启动期注入；单测需手动注册才能经
    // MediaApiService/ResolverRegistry 路由到 ShuyuanNovelResolver。
    registerShuyuanResolver(ShuyuanNovelResolver.new);
  });

  test('fetchNovelContent 在下一章地址前停止；缺省时继续跟随', () async {
    final paths = <String>[];
    final routes = <String, String>{
      '/c1.html':
          '<div id="c">第一页</div><a class="next" href="/c1_2.html">下一页</a>',
      '/c1_2.html':
          '<div id="c">第二页</div><a class="next" href="/c1_3.html">下一页</a>',
      '/c1_3.html': '<div id="c">下一章正文</div>',
    };
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) {
      paths.add(req.uri.path);
      final body = routes[req.uri.path];
      req.response
        ..statusCode = body == null ? 404 : 200
        ..headers.contentType = ContentType.html
        ..write(body ?? '');
      req.response.close();
    });
    final origin = 'http://127.0.0.1:${server.port}';
    final config = ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(
      <String, dynamic>{
        'bookSourceName': 'stop-point',
        'bookSourceUrl': origin,
        'bookSourceType': 0,
        'ruleContent': <String, dynamic>{
          'content': '#c@html',
          'nextContentUrl': 'a.next@href',
        },
      },
    ));
    final service = MediaApiService(ResolverRegistry.instance);

    final blocks = await service.fetchNovelContent(
      config,
      novelId: '1',
      chapterUrl: '$origin/c1.html',
      nextChapterUrl: '$origin/c1_3.html',
    );
    final text = <String>[
      for (final b in blocks)
        if (b is NovelTextBlock) b.text.trim(),
    ];
    expect(text, <String>['第一页', '第二页']);
    expect(paths, <String>['/c1.html', '/c1_2.html']);

    paths.clear();
    await service.fetchNovelContent(
      config,
      novelId: '1',
      chapterUrl: '$origin/c1.html',
    );
    expect(paths, contains('/c1_3.html'));
  });
}
