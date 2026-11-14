/// 书源导入全字段保真测试（P0-1）。
///
/// 锁定三层链路字段不丢：原始 JSON → ShuyuanSource（raw 整图）→
/// PluginConfig.selectors['xiaoshuo'] → 持久化往返 → 运行期
/// ShuyuanSource.fromJson → toBookSource()（XiaoshuoBookSource）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';

Map<String, dynamic> _fullLegadoSource() => {
      'bookSourceUrl': 'https://example.com/',
      'bookSourceName': '测试书源',
      'bookSourceGroup': '测试组',
      'bookSourceType': 0,
      'bookSourceComment': '注释',
      'bookUrlPattern': '.*example\\.com/book/\\d+.*',
      'customOrder': 7,
      'enabled': true,
      'enabledExplore': false,
      'enabledCookieJar': false,
      'jsLib': 'function hello(){return 1}',
      'concurrentRate': '3/1000',
      'header': {'Referer': 'https://example.com/', 'UA': 'test-ua'},
      'loginUrl': 'https://example.com/login',
      'loginUi': [
        {'name': '用户名', 'type': 'text'},
        {'name': '密码', 'type': 'password'},
      ],
      'loginCheckJs': 'if(result.code==500){result=null}',
      'coverDecodeJs': 'result',
      'variableComment': '变量说明',
      'lastUpdateTime': 1700000000000,
      'respondTime': 123456,
      'weight': 42,
      'exploreScreen': '分类',
      'searchUrl': '/search?kw={{key}}&p={{page}}',
      'exploreUrl': '分类A::/sort/1\n分类B::/sort/2',
      'ruleSearch': {'bookList': 'class.bookbox', 'name': 'tag.h3@text'},
      'ruleBookInfo': {'name': 'class.title@text'},
      'ruleToc': {'chapterList': 'class.listmain@tag.dd'},
      'ruleContent': {'content': 'id.content@textNodes'},
      'ruleExplore': {'bookList': 'class.bookbox'},
      // 模型未建模的自定义扩展字段：必须随 raw 整图存活。
      'myVendorField': {'a': 1},
    };

void main() {
  group('书源导入全字段保真（P0-1）', () {
    test('导入后 selectors[xiaoshuo] 含全部 legado 字段', () {
      final raw = _fullLegadoSource();
      final source = ShuyuanSource.fromJson(raw);
      final config = ShuyuanAdapter.toPluginConfig(source);
      final stored =
          config.selectors?['xiaoshuo'] as Map<String, dynamic>? ?? {};

      expect(stored['jsLib'], 'function hello(){return 1}');
      expect(stored['concurrentRate'], '3/1000');
      expect(stored['loginUrl'], 'https://example.com/login');
      expect(stored['loginCheckJs'], 'if(result.code==500){result=null}');
      expect(stored['coverDecodeJs'], 'result');
      expect(stored['variableComment'], '变量说明');
      expect(stored['weight'], 42);
      expect(stored['customOrder'], 7);
      expect(stored['bookUrlPattern'], '.*example\\.com/book/\\d+.*');
      expect(stored['enabledCookieJar'], false);
      expect(stored['enabledExplore'], false);
      expect(stored['lastUpdateTime'], 1700000000000);
      expect(stored['respondTime'], 123456);
      expect(stored['exploreScreen'], '分类');
      // 结构体字段（header/loginUi）：selectors 里保留原始对象/数组形态
      // （raw 整图），运行期模型层才归一化为 JSON 字符串（见下一用例）。
      expect(jsonEncode(stored['header']), contains('Referer'));
      expect(jsonEncode(stored['loginUi']), contains('password'));
      // 未建模的厂商自定义字段随 raw 整图存活。
      expect(stored['myVendorField'], {'a': 1});
    });

    test('持久化往返后运行期 toBookSource 拿到全部字段', () {
      final raw = _fullLegadoSource();
      final source = ShuyuanSource.fromJson(raw);
      final config = ShuyuanAdapter.toPluginConfig(source);

      // 模拟 SharedPreferences 的 JSON 往返。
      final persisted = jsonDecode(jsonEncode(config.toJson()))
          as Map<String, dynamic>;
      final restored = PluginConfig.fromJson(persisted);

      final runtimeSource = ShuyuanAdapter.fromPluginConfig(restored);
      expect(runtimeSource, isNotNull);
      final bookSource = runtimeSource!.toBookSource();

      expect(bookSource.jsLib, 'function hello(){return 1}');
      expect(bookSource.concurrentRate, '3/1000');
      expect(bookSource.loginUrl, 'https://example.com/login');
      expect(bookSource.loginCheckJs, 'if(result.code==500){result=null}');
      expect(bookSource.coverDecodeJs, 'result');
      expect(bookSource.variableComment, '变量说明');
      expect(bookSource.weight, 42);
      expect(bookSource.customOrder, 7);
      expect(bookSource.bookUrlPattern, '.*example\\.com/book/\\d+.*');
      expect(bookSource.enabledCookieJar, false);
      expect(bookSource.enabledExplore, false);
      expect(bookSource.exploreScreen, '分类');
      expect(bookSource.header, contains('Referer'));
      expect(bookSource.loginUi, contains('password'));
      // 规则实体解析不受整图保留影响。
      expect(bookSource.ruleSearch?.bookList, 'class.bookbox');
      expect(bookSource.ruleContent?.content, 'id.content@textNodes');
    });

    test('PluginConfig.enabledExplore 独立于 enabled', () {
      final raw = _fullLegadoSource()..['enabled'] = true;
      final config =
          ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(raw));
      expect(config.enabled, true);
      expect(config.enabledExplore, false);
    });

    test('旧存量数据（无 raw 的 15 字段 map）解析不回归', () {
      final legacy = <String, dynamic>{
        'bookSourceName': '旧源',
        'bookSourceUrl': 'https://old.example.com/',
        'bookSourceType': 0,
        'enabled': true,
        'header': 'legacy-ua',
        'searchUrl': '/s={{key}}',
        'ruleSearch': {'bookList': 'class.item'},
        'ruleToc': {'chapterList': 'tag.dd'},
        'ruleContent': {'content': 'id.content'},
      };
      final source = ShuyuanSource.fromJson(legacy);
      final config = ShuyuanAdapter.toPluginConfig(source);
      final restored = PluginConfig.fromJson(
        jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>,
      );
      final bookSource = ShuyuanAdapter.fromPluginConfig(restored)!.toBookSource();

      expect(bookSource.bookSourceName, '旧源');
      expect(bookSource.header, 'legacy-ua');
      expect(bookSource.ruleSearch?.bookList, 'class.item');
      // 缺省扩展字段回退模型默认值。
      expect(bookSource.enabledCookieJar, true);
      expect(bookSource.enabledExplore, true);
      expect(bookSource.respondTime, 180000);
    });

    test('header 为对象形态的源不再被静默跳过', () {
      final raw = _fullLegadoSource();
      final source = ShuyuanSource.fromJson(raw);
      expect(source.header, isNotNull);
      expect(source.isValid, true);
    });
  });
}
