/// 书源 URL 后缀语义（legado AnalyzeUrl 对等）：
/// 书源地址允许携带 `##备注` 后缀且原样保存在 bookSourceUrl 中（legado 的
/// getKey() 同样不剥离）。请求头默认集只允许机器可编码的纯文本：这里验证
/// 引擎不再把带非 ASCII 后缀的 bookSourceUrl 注入 `Referer`，否则请求在
/// 发送前就因头值非法失败——发现页选项栏/分类/列表在真机上全部为空。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/presentation/shuyuan_novel_resolver.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';

String _exploreScript(String local) => '''
@js:(function(){
  var data = JSON.parse(java.ajax('$local/api/kinds'));
  var out = [{"title":"全部","url":"$local/api/list"}];
  for (var i = 0; i < data.groups.length; i++) {
    out.push({"title": data.groups[i], "url": "$local/api/list?g=" + data.groups[i]});
  }
  return JSON.stringify(out);
})()
''';

PluginConfig _source(String local) =>
    ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(<String, dynamic>{
      'bookSourceName': '后缀测试源',
      // 与真实书源一致：地址尾部带 `##` 备注（含非 ASCII 文本）。
      'bookSourceUrl': '$local##备注',
      'bookSourceType': 0,
      'enabled': true,
      'header': '{"User-Agent":"Mozilla/5.0 (Linux; Android 13)"}',
      'exploreUrl': _exploreScript(local),
      'ruleExplore': <String, dynamic>{
        'bookList': r'$.items[*]',
        'name': r'$.name',
        'bookUrl': r'$.url',
      },
    }));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ShuyuanSourceContext.resetForTest();
    JsEngine.resetPoolForTest();
  });

  tearDown(() {
    JsEngine.resetPoolForTest();
  });

  test('带非 ASCII ##后缀的书源可正常请求并生成选项栏/分类/列表', () async {
    final seenReferers = <String?>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final local = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      seenReferers.add(req.headers.value('referer'));
      req.response.headers.contentType =
          ContentType('application', 'json', charset: 'utf-8');
      if (req.uri.path == '/api/kinds') {
        req.response.write(jsonEncode(<String, dynamic>{
          'groups': <String>['分组A'],
        }));
      } else if (req.uri.path == '/api/list') {
        req.response.write(jsonEncode(<String, dynamic>{
          'items': <dynamic>[
            <String, dynamic>{'name': '条目一', 'url': '$local/book/1'},
          ],
        }));
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });

    try {
      final cfg = _source(local);
      final resolver = ShuyuanNovelResolver();

      // 下拉选项栏（在线页展开后的可选栏）。
      final kinds = await resolver.resolveExploreKinds(cfg);
      expect(kinds.error, isNull);
      expect(kinds.items.map((e) => e.displayName), containsAll(<String>[
        '全部',
        '分组A',
      ]));

      // 可浏览分类（分类 Tab / 分类入口）。
      final entries = await resolver.resolveExploreCategories(cfg);
      expect(entries.map((e) => e.title), containsAll(<String>['全部', '分组A']));

      // 分类列表阶段：同样的带后缀书源地址，请求仍须成功。
      final items = await resolver.resolve(
        cfg,
        'explore',
        vars: <String, String>{'category': '$local/api/list', 'page': '1'},
      );
      expect((items as List).length, 1);

      // 关键回归：默认请求头不得注入带非 ASCII 后缀的 Referer。
      expect(seenReferers, isNotEmpty);
      expect(seenReferers.every((r) => r == null), isTrue);
    } finally {
      await server.close(force: true);
    }
  });
}
