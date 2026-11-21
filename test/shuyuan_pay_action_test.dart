/// 书源章节购买动作（legado `ruleContent.payAction`）回归。
///
/// 对照 md3 `ReadBookViewModel.confirmPayAction` / `MangaReaderActionRepository`：
/// payAction 以本章上下文直接编译执行；绝对 URL → 打开支付页；真值 → 已购买；
/// 其余（空/false）→ 失败。同时校验 Episode 透传 VIP/已购标记与单章缓存清理。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:nexhub/core/models/episode.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/core/novel/novel_pay_result.dart';
import 'package:nexhub/core/novel/novel_pre_downloader.dart';
import 'package:nexhub/core/resolver/resolver_registry.dart';
import 'package:nexhub/core/scraper/media_api_service.dart';
import 'package:nexhub/core/scraper/verification_detector.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book_chapter.dart';
import 'package:nexhub/features/shuyuan/presentation/shuyuan_novel_resolver.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

PluginConfig _sourceOf({String? payAction}) =>
    ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(<String, dynamic>{
      'bookSourceName': 'pay-action',
      'bookSourceUrl': 'https://src.example.com',
      'bookSourceType': 0,
      'ruleContent': <String, dynamic>{
        'content': '#c@text',
        if (payAction != null) 'payAction': payAction,
      },
    }));

const Map<String, String> _vars = <String, String>{
  'id': 'https://src.example.com/book/1',
  'bookUrl': 'https://src.example.com/book/1',
  'chapter': 'https://src.example.com/c/1.html',
  'url': 'https://src.example.com/c/1.html',
  'chapterTitle': '第九章',
};

Future<NovelPayResult> _pay(PluginConfig source) async {
  final dynamic r = await ShuyuanNovelResolver().resolve(
    source,
    'pay',
    vars: _vars,
  );
  return r as NovelPayResult;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ShuyuanSourceContext.resetForTest();
    JsEngine.resetPoolForTest();
    registerShuyuanResolver(ShuyuanNovelResolver.new);
  });

  group('payAction 语义', () {
    test('返回绝对 URL：打开支付页', () async {
      final r = await _pay(_sourceOf(
        payAction: '"https://pay.example.com/checkout?u=" + chapter.url',
      ));
      expect(r.outcome, NovelPayOutcome.openUrl);
      expect(
        r.url,
        'https://pay.example.com/checkout?u=https://src.example.com/c/1.html',
      );
    });

    test('返回 true：视为已购买（正文需重载）', () async {
      final r = await _pay(_sourceOf(payAction: 'true'));
      expect(r.outcome, NovelPayOutcome.refreshed);
    });

    test('返回非 false 文本：按 legado isTrue 也视为已购买', () async {
      final r = await _pay(_sourceOf(payAction: '"paid"'));
      expect(r.outcome, NovelPayOutcome.refreshed);
    });

    test('返回 false：失败', () async {
      await expectLater(
        _pay(_sourceOf(payAction: 'false')),
        throwsA(isA<SourceResolveException>()),
      );
    });

    test('返回 0.0：按 legado isTrue 为失败', () async {
      await expectLater(
        _pay(_sourceOf(payAction: '"0.0"')),
        throwsA(isA<SourceResolveException>()),
      );
    });

    test('未声明 payAction：失败', () async {
      await expectLater(
        _pay(_sourceOf()),
        throwsA(isA<SourceResolveException>()),
      );
    });

    test('脚本可读 book/chapter 绑定并透传书籍 URL', () async {
      final service = MediaApiService(ResolverRegistry.instance);
      final r = await service.payNovelChapter(
        _sourceOf(
          payAction:
              '"https://pay.example.com/x?b=" + book.bookUrl + "&v=" + chapter.isVip',
        ),
        novelId: 'https://src.example.com/book/1',
        chapterUrl: 'https://src.example.com/c/1.html',
        chapterTitle: '第九章',
      );
      expect(
        r.url,
        'https://pay.example.com/x?b=https://src.example.com/book/1&v=true',
      );
    });
  });

  group('购买入口判定', () {
    test('canPayNovelChapter 依据规则声明', () {
      final service = MediaApiService(ResolverRegistry.instance);
      expect(service.canPayNovelChapter(_sourceOf(payAction: 'true')), isTrue);
      expect(service.canPayNovelChapter(_sourceOf()), isFalse);
      const plain = PluginConfig(
        id: 'plain',
        name: 'plain',
        type: SourceType.novelSource,
        site: SiteConfig(
          domain: 'plain.example',
          baseUrl: 'http://plain.example',
        ),
        parser: ParserConfig(type: 'builtin'),
      );
      expect(service.canPayNovelChapter(plain), isFalse);
    });

    test('episodesFromChapters 透传 isVip/isPay', () {
      final List<Episode> eps = ShuyuanNovelResolver.episodesFromChapters(
        <XiaoshuoBookChapter>[
          XiaoshuoBookChapter(
            bookUrl: 'b',
            url: 'u1',
            title: 't1',
            index: 0,
            isVip: true,
          ),
          XiaoshuoBookChapter(
            bookUrl: 'b',
            url: 'u2',
            title: 't2',
            index: 1,
            isPay: true,
          ),
        ],
        isComic: false,
      );
      expect(eps[0].isVip, isTrue);
      expect(eps[0].isPay, isFalse);
      expect(eps[1].isVip, isFalse);
      expect(eps[1].isPay, isTrue);
    });
  });

  group('购买后缓存清理', () {
    late Directory dir;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('novel_pay_test');
      Hive.init(dir.path);
    });

    tearDownAll(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('dropChapter 同时清内存与 Hive', () async {
      final box = await Hive.openBox<dynamic>(NovelPreDownloader.boxName);
      await box.put('n1::c1', '[{"t":"text","text":"旧正文"}]');
      final dl = NovelPreDownloader();
      expect(await dl.cached('n1', 'c1'), isNotNull);
      await dl.dropChapter('n1', 'c1');
      expect(await dl.has('n1', 'c1'), isFalse);
      expect(box.get('n1::c1'), isNull);
    });
  });
}
