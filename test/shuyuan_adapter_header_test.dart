/// 书源声明式 header → PluginConfig → 图片请求头 的映射回归测试。
///
/// legado 源的 `header` 同时作用于页面请求（AnalyzeUrl）与图片请求
/// （Glide fetcher 全量带头）。NexHub 的图片通道是 SourceImage，
/// 它只读 PluginConfig.site / antiHotlinking——若适配器不映射 header，
/// 图片请求会丢 UA/Referer/Cookie/自定义头，被 CDN 按指纹拦截（封面 403）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/widgets/source_image.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('书源 header 映射到图片请求头', () {
    test('UA + Cookie + Referer 全量下发，且不在 site.headers 重复', () {
      final cfg = ShuyuanAdapter.toPluginConfig(_source({
        'header': '{"User-Agent":"okhttp/4.9.2","Cookie":"sid=1",'
            '"Referer":"http://ref.example/"}',
      }));
      final siteKeys = (cfg.site.headers ?? const {}).keys
          .map((k) => k.toLowerCase())
          .toSet();
      expect(siteKeys.intersection({'user-agent', 'cookie', 'referer'}),
          isEmpty);

      final h = SourceImage.buildHeaders(
        url: 'http://img.example/1s.jpg',
        source: cfg,
      )!;
      expect(h['User-Agent'], 'okhttp/4.9.2');
      expect(h['Cookie'], 'sid=1');
      expect(h['Referer'], 'http://ref.example/');
    });

    test('自定义业务头原样进入 site.headers 并随图片请求下发', () {
      final cfg = ShuyuanAdapter.toPluginConfig(_source({
        'header': '{"client-name":"app.demo","Authorization":"Bearer x"}',
      }));
      expect(cfg.site.headers?['client-name'], 'app.demo');
      final h = SourceImage.buildHeaders(
        url: 'http://img.example/1s.jpg',
        source: cfg,
      )!;
      expect(h['client-name'], 'app.demo');
      expect(h['Authorization'], 'Bearer x');
    });

    test('未声明 Referer 时回落 baseUrl（既有行为）', () {
      final cfg = ShuyuanAdapter.toPluginConfig(_source({
        'header': '{"User-Agent":"okhttp/4.9.2"}',
      }));
      final h = SourceImage.buildHeaders(
        url: 'http://img.example/1s.jpg',
        source: cfg,
      )!;
      expect(h['Referer'], 'http://src.example');
    });

    test('宽松 JSON（单引号）也能解析', () {
      final cfg = ShuyuanAdapter.toPluginConfig(_source({
        'header': "{'User-Agent':'okhttp/4.9.2','client-brand':'vivo'}",
      }));
      expect(cfg.site.userAgent, 'okhttp/4.9.2');
      expect(cfg.site.headers?['client-brand'], 'vivo');
    });

    test('脚本式 header 不产生静态映射（请求期由 AnalyzeUrl 求值）', () {
      final src = _source({
        'header': '@js:\nJSON.stringify({"User-Agent":"x"})',
      });
      final cfg = ShuyuanAdapter.toPluginConfig(src);
      expect(cfg.site.userAgent ?? '', isEmpty);
      expect(cfg.site.headers ?? const {}, isEmpty);
    });

    test('无 header 声明时图片头仍带 baseUrl Referer', () {
      final cfg = ShuyuanAdapter.toPluginConfig(_source({}));
      final h = SourceImage.buildHeaders(
        url: 'http://img.example/1s.jpg',
        source: cfg,
      )!;
      expect(h['Referer'], 'http://src.example');
    });
  });
}
