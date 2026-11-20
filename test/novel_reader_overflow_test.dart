// 回归测试：「正文内容超出显示区域（字符显示不全）」。
//
// 两处历史根因（均已修复，此处防回归）：
// 1. 分页器寡行回退后 `used = 0`，回退行高度从记账中丢失 → 整页超装
// 一个段首块高度，页底行被 SingleChildScrollView 裁切（大溢出 68~222px）。
// 2. 页眉/页脚高度探针未与环境 DefaultTextStyle 合并（Text 组件的合并
// 语义会让主题 bodyMedium 的 height 渗入，行高 12 → 17），分页高估
// 可用高度 ~10px，满页底部行被裁。
//
// 验证方式：逐页翻页，实测滚动视口高度 vs 内容列实际高度、正文行右缘
// vs 视口右缘，任何一页超限即失败。
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:nexhub/core/favorites/favorites_manager.dart';
import 'package:nexhub/core/models/episode.dart';
import 'package:nexhub/core/models/novel_block.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/core/resolver/resolver_registry.dart';
import 'package:nexhub/core/scraper/media_api_service.dart';
import 'package:nexhub/core/services/source_repository.dart';
import 'package:nexhub/features/novel/presentation/novel_reader_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeNovelMediaApiService extends MediaApiService {
  _FakeNovelMediaApiService() : super(ResolverRegistry.instance);

  @override
  Future<List<NovelBlock>> fetchNovelContent(
    PluginConfig source, {
    required String novelId,
    required String chapterUrl,
    String? nextChapterUrl,
    String? renderedHtml,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // 长段 + 短段 + 章节标题混合：既触发跨页断行与寡行回退，也覆盖
    // 标题行高（headingStyleOf）与段距路径。
    return <NovelBlock>[
      const NovelTextBlock('第一章 试炼之地', isHeading: true),
      for (var i = 0; i < 30; i++) ...<NovelBlock>[
        NovelTextBlock('　　第$i 段：主角走进了一片幽暗的森林，四周弥漫着薄雾，'
            '远处的山峦在月光下若隐若现，他握紧了手中的长剑，警惕地观察着'
            '周围的动静，脚步声在寂静的夜里显得格外清晰，仿佛有什么东西'
            '正在暗中窥伺着他的一举一动，危险随时可能降临到他的身上。'
            '这是一段很长的文字用来撑出多行多页的分页效果，继续描述故事'
            '情节的发展与人物心理的变化，让文本足够长以便测试分页边界。'),
        if (i % 3 == 0) const NovelTextBlock('　　短段。'),
        if (i % 5 == 0)
          const NovelTextBlock('小节标题：风起', isHeading: true),
      ],
    ];
  }
}

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.path);
    await Hive.openBox('novel_notes');
    await Hive.openBox('novel_bookmarks');
    // 预下载缓存 box：预打开避免阅读器 _loadChapter 内 Hive.openBox
    // 的后台任务阻塞 pumpAndSettle（与 novel_reader_test 同模式）。
    await Hive.openBox('novel_pre_downloads');
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
  });

  Future<void> pumpReader(
    WidgetTester tester,
    String prefsJson, {
    double textScale = 1.0,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'novel_prefs_n1': prefsJson,
    });
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;

    final source = PluginConfig.fromJson(<String, dynamic>{
      'id': 'nsrc1',
      'name': 'NS',
      'type': 'novelSource',
      'responseType': 'html',
      'site': {
        'domain': 'https://example.com',
        'baseUrl': 'https://example.com',
      },
      'parser': {'type': 'builtin'},
      'routes': {
        'toc': '/book/{id}/toc',
        'content': '/book/{id}/{chapter}',
      },
      'selectors': {
        'chapters': 'li.chapter',
        'content': '#content',
      },
    });
    final repo = SourceRepository(<PluginConfig>[source]);
    final service = _FakeNovelMediaApiService();
    final favorites = FavoritesManager();
    await favorites.init();
    const chapters = <Episode>[
      Episode(id: 'ch1', title: '第1章 开端', url: '/ch1'),
    ];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<MediaApiService>.value(value: service),
          ChangeNotifierProvider<SourceRepository>.value(value: repo),
          ChangeNotifierProvider<FavoritesManager>.value(value: favorites),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          builder: textScale == 1.0
              ? null
              : (BuildContext ctx, Widget? child) => MediaQuery(
                    data: MediaQuery.of(ctx)
                        .copyWith(textScaler: TextScaler.linear(textScale)),
                    child: child!,
                  ),
          home: const NovelReaderScreen(
            novelId: 'n1',
            title: '测试小说',
            sourceId: 'nsrc1',
            chapters: chapters,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 校验当前页：内容列高度 ≤ 滚动视口高度（页底不裁行），
  /// 正文行右缘 ≤ 视口右缘（右侧不裁字）。
  void expectPageFits(WidgetTester tester, String label) {
    final scroll = find.byType(SingleChildScrollView);
    expect(scroll, findsOneWidget, reason: '[$label] 未找到正文滚动区');
    final viewportH = tester.getSize(scroll).height;
    final contentCol =
        find.descendant(of: scroll, matching: find.byType(Column)).first;
    final contentH = tester.getSize(contentCol).height;
    expect(contentH, lessThanOrEqualTo(viewportH + 0.5),
        reason: '[$label] 页面内容高度 $contentH 超出滚动视口 $viewportH '
            '→ 页底行被裁（字符显示不全）');

    final scrollRect = tester.getRect(scroll);
    double maxRight = 0;
    for (final t in find.byType(Text).evaluate()) {
      final tr = tester.getRect(find.byWidget(t.widget));
      if (tr.top >= scrollRect.top && tr.bottom <= scrollRect.bottom) {
        if (tr.right > maxRight) maxRight = tr.right;
      }
    }
    expect(maxRight, lessThanOrEqualTo(scrollRect.right + 0.5),
        reason: '[$label] 正文行右缘 $maxRight 超出显示区 ${scrollRect.right} '
            '→ 右侧字符被裁');
  }

  Future<void> flipThrough(WidgetTester tester, String label, int pages) async {
    expectPageFits(tester, '$label-p1');
    for (var i = 2; i <= pages; i++) {
      await tester.tapAt(const Offset(700, 600)); // 右侧点击区 = 下一页
      await tester.pumpAndSettle();
      expectPageFits(tester, '$label-p$i');
    }
  }

  testWidgets('默认偏好：各页内容不得超出显示区域', (tester) async {
    await pumpReader(tester, '{"pageAnimation":"none"}');
    await flipThrough(tester, 'default', 5);
  });

  testWidgets('大字号+小行距+字距：各页内容不得超出显示区域', (tester) async {
    await pumpReader(tester,
        '{"pageAnimation":"none","fontSize":28.0,"lineHeight":1.2,'
        '"letterSpacing":2.0,"margin":12.0,"paragraphSpacing":4.0}');
    await flipThrough(tester, 'big-tight', 5);
  });

  testWidgets('系统字体缩放 1.3x：各页内容不得超出显示区域', (tester) async {
    await pumpReader(tester, '{"pageAnimation":"none"}', textScale: 1.3);
    await flipThrough(tester, 'scale1.3', 4);
  });

  testWidgets('短段+大段距：各页内容不得超出显示区域', (tester) async {
    await pumpReader(tester,
        '{"pageAnimation":"none","paragraphSpacing":24.0,"margin":6.0}');
    await flipThrough(tester, 'short-paras', 4);
  });
}
