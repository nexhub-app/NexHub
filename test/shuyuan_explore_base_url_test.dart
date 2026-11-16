/// exploreUrl / viewName / action 脚本的 `baseUrl` 绑定测试。
///
/// legado `BaseSource.evalJS` 把 `baseUrl` 绑定为书源 URL（getKey()），
/// `exploreKinds()`、ExploreKind viewName / action 全部经该入口求值。
/// 视频源的动态分类几乎都写成 `baseUrl + '/api.php/provide/vod/?ac=list'`，
/// 缺失绑定会让整段脚本 ReferenceError，发现页一个分类都没有。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/features/shuyuan/presentation/shuyuan_novel_resolver.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';
import 'package:nexhub/features/shuyuan/web_book/web_book_types.dart';
import 'package:shared_preferences/shared_preferences.dart';

PluginConfig makeConfig({required String exploreUrl, int type = 4}) {
  return ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(<String, dynamic>{
    'bookSourceName': '本地视频测试源',
    'bookSourceUrl': 'https://video.example.com',
    'bookSourceType': type,
    'enabled': true,
    'exploreUrl': exploreUrl,
  }));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('parseExploreKinds 的 baseUrl 绑定', () {
    test('整串 @js: 可读取 baseUrl', () {
      final kinds = parseExploreKinds(
        "@js:JSON.stringify([{title:'电影', url: baseUrl + '/list?cat=1'}])",
        baseUrl: 'https://video.example.com',
      );
      expect(kinds.single.title, '电影');
      expect(kinds.single.url, 'https://video.example.com/list?cat=1');
    });

    test('<js> 包裹形态可读取 baseUrl', () {
      final kinds = parseExploreKinds(
        "<js>JSON.stringify([{title:'剧集', url: baseUrl + '/list?cat=2'}])</js>",
        baseUrl: 'https://video.example.com',
      );
      expect(kinds.single.url, 'https://video.example.com/list?cat=2');
    });

    test('@JS: / <JS> 前缀忽略大小写（legado startsWith(..., true)）', () {
      final kinds = parseExploreKinds(
        "@JS:JSON.stringify([{title:'电影', url: baseUrl + '/list?cat=1'}])",
        baseUrl: 'https://video.example.com',
      );
      expect(kinds.single.url, 'https://video.example.com/list?cat=1');
      final wrapped = parseExploreKinds(
        "<JS>JSON.stringify([{title:'电影', url: baseUrl + '/list?cat=1'}])</JS>",
        baseUrl: 'https://video.example.com',
      );
      expect(wrapped.single.url, 'https://video.example.com/list?cat=1');
    });

    test('分段 @js: 可读取 baseUrl', () {
      final kinds = parseExploreKinds(
        "静态::/list?cat=4&&"
        "@js:JSON.stringify([{title:'综艺', url: baseUrl + '/list?cat=3'}])",
        baseUrl: 'https://video.example.com',
      );
      expect(kinds.length, 2);
      expect(kinds[0].url, '/list?cat=4');
      expect(kinds[1].url, 'https://video.example.com/list?cat=3');
    });

    test('baseUrl 与 infoMap 同时可用', () {
      final kinds = parseExploreKinds(
        "@js:JSON.stringify([{title:'动画', url: baseUrl + '/list?area=' + infoMap.area}])",
        baseUrl: 'https://video.example.com',
        infoMap: const <String, String>{'area': 'jp'},
      );
      expect(kinds.single.url, 'https://video.example.com/list?area=jp');
    });
  });

  group('resolveExploreKinds 的 baseUrl 绑定', () {
    test('viewName 脚本可读取 baseUrl', () async {
      final cfg = makeConfig(
        exploreUrl: '[{"title":"标签","url":"/l",'
            "\"viewName\":\"baseUrl.replace('https://', '')\"}]",
      );
      final result = await ShuyuanNovelResolver().resolveExploreKinds(cfg);
      expect(result.error, isNull);
      expect(result.items.single.displayName, 'video.example.com');
    });

    test('action 脚本可读取 baseUrl', () async {
      final cfg = makeConfig(
        exploreUrl: '[{"title":"按钮","type":"button",'
            "\"action\":\"java.copyText(baseUrl + '/act')\"}]",
      );
      final resolver = ShuyuanNovelResolver();
      final kinds = await resolver.resolveExploreKinds(cfg);
      final action = await resolver.executeExploreKindAction(
          cfg, kinds.items.single.kind);
      expect(action.copiedTexts, <String>['https://video.example.com/act']);
    });
  });
}
