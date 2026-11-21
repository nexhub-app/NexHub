/// 书源图片/媒体请求头的运行期求值回归。
///
/// legado 对页面与图片共用 `AnalyzeUrl(src, source = bookSource)`：脚本式
/// header（`@js:`/`<js>`）与 CookieStore 会话在每个取图请求上重新求值。
/// NexHub 静态 header 在适配期已映射，本层补齐动态部分；同时约束快路径
/// （静态 header 且无登录覆盖层时不得重建 AnalyzeUrl / 启动 JS）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/core/widgets/source_image.dart';
import 'package:nexhub/features/shuyuan/analyze/image_request_headers.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

ShuyuanSource _source(Map<String, dynamic> extra) => ShuyuanSource.fromJson({
      'bookSourceName': '测试源',
      'bookSourceUrl': 'http://src.example',
      'bookSourceType': 0,
      'searchUrl': '/search?q={{key}}',
      'ruleSearch': {'bookList': '.item', 'name': 'a@text'},
      ...extra,
    });

PluginConfig _plainConfig() => const PluginConfig(
      id: 'plain',
      name: 'plain',
      type: SourceType.novelSource,
      site: SiteConfig(domain: 'plain.example', baseUrl: 'http://plain.example'),
      parser: ParserConfig(type: 'builtin'),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ShuyuanSourceContext.resetForTest();
    JsEngine.resetPoolForTest();
    ShuyuanImageHeaders.register();
  });

  tearDown(() {
    ShuyuanImageHeaderHooks.resolver = null;
  });

  group('书源图片请求头运行期求值', () {
    test('非书源源不触发求值', () {
      expect(
        ShuyuanImageHeaders.resolve(
            _plainConfig(), 'http://img.example/1.jpg'),
        isNull,
      );
    });

    test('静态 header 走快路径（不求值、不返回重复头）', () {
      final cfg = ShuyuanAdapter.toPluginConfig(_source({
        'header': '{"User-Agent":"okhttp/4.9.2","Cookie":"sid=1"}',
      }));
      expect(
        ShuyuanImageHeaders.resolve(cfg, 'http://img.example/1.jpg'),
        isNull,
      );
    });

    test('脚本式 header 在取图期求值（含自定义业务头）', () {
      final cfg = ShuyuanAdapter.toPluginConfig(_source({
        'header': '@js:'
            'JSON.stringify({"User-Agent":"agent-9","x-token":"tk-1"})',
      }));
      final h = ShuyuanImageHeaders.resolve(
          cfg, 'http://img.example/1.jpg');
      expect(h, isNotNull);
      expect(h!['User-Agent'], 'agent-9');
      expect(h['x-token'], 'tk-1');
    });

    test('登录 Cookie 覆盖层按 host 合并进图片请求', () async {
      final cfg = ShuyuanAdapter.toPluginConfig(_source({
        'header': '@js:JSON.stringify({"User-Agent":"agent-9"})',
      }));
      SharedPreferences.setMockInitialValues(<String, Object>{
        'shuyuan_source_cookies_v1': '{"${cfg.id}":{"sid":'
            '{"value":"v1","host":"img.example"}}}',
      });
      ShuyuanSourceContext.resetForTest();
      await ShuyuanSourceContext.warmCookieCache();
      expect(ShuyuanSourceContext.persistedCookiesFor(cfg.id), isNotEmpty);

      final h = ShuyuanImageHeaders.resolve(
          cfg, 'http://img.example/1.jpg');
      expect(h?['Cookie'], 'sid=v1');
      // 非覆盖 host 不带该 Cookie。
      final other = ShuyuanImageHeaders.resolve(
          cfg, 'http://other.example/1.jpg');
      expect(other?.containsKey('Cookie') ?? false, isFalse);
    });

    test('fetchHeadersFor 合并动态头并覆盖同名静态头', () {
      final cfg = ShuyuanAdapter.toPluginConfig(_source({
        'header': '@js:'
            'JSON.stringify({"User-Agent":"agent-9","Referer":"http://r.example/"})',
      }));
      final h = cfg.fetchHeadersFor('http://img.example/1.jpg')!;
      expect(h['User-Agent'], 'agent-9');
      expect(h['Referer'], 'http://r.example/');
    });

    test('SourceImage.buildHeaders 仅对书源源合并动态头', () {
      ShuyuanImageHeaderHooks.resolver =
          (config, url) => <String, String>{'x-dyn': '1'};
      final shuyuan = ShuyuanAdapter.toPluginConfig(_source({
        'header': '{"User-Agent":"okhttp/4.9.2"}',
      }));
      final h = SourceImage.buildHeaders(
        url: 'http://img.example/1.jpg',
        source: shuyuan,
      )!;
      expect(h['x-dyn'], '1');

      final plain = SourceImage.buildHeaders(
        url: 'http://img.example/1.jpg',
        source: _plainConfig(),
      );
      expect(plain?.containsKey('x-dyn') ?? false, isFalse);
    });
  });
}
