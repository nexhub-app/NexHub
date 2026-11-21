import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:nexhub/core/comic/models/reader_preferences.dart'
    show InMemoryBackend;
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

/// 小说阅读器测试：注入 [FakeNovelMediaApiService] 提供固定段落列表，
/// 绕过 widget 测试环境下的 HttpClient 桩。
class FakeNovelMediaApiService extends MediaApiService {
  FakeNovelMediaApiService() : super(ResolverRegistry.instance);

  @override
  Future<List<NovelBlock>> fetchNovelContent(
    PluginConfig source, {
    required String novelId,
    required String chapterUrl,
    String? nextChapterUrl,
    String? renderedHtml,
    String? chapterTitle,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return const <NovelBlock>[
      NovelTextBlock('这是第一段文字，用于测试小说阅读器的文本分页功能。'),
      NovelTextBlock('第二段内容继续展开，描述着主角在异世界的冒险经历。'),
      NovelTextBlock('第三段描写了一场激烈的战斗场景，剑光闪烁，魔法飞舞。'),
      NovelTextBlock('第四段转入平静的日常，主角与伙伴们在酒馆中休息。'),
      NovelTextBlock('第五段是本章的高潮，主角终于面对了最终的敌人。'),
      NovelTextBlock('最后一段为结尾，留下悬念，引向下一章的故事发展。'),
    ];
  }

  @override
  Future<NovelContentResult> fetchNovelContentDetailed(
    PluginConfig source, {
    required String novelId,
    required String chapterUrl,
    String? nextChapterUrl,
    String? renderedHtml,
    String? chapterTitle,
  }) async {
    final blocks = await fetchNovelContent(
      source,
      novelId: novelId,
      chapterUrl: chapterUrl,
      nextChapterUrl: nextChapterUrl,
      renderedHtml: renderedHtml,
      chapterTitle: chapterTitle,
    );
    // 模拟源声明了 `ruleContent.title`：阅读器应以规则结果覆盖目录章节名。
    return NovelContentResult(blocks, title: '正文规则标题');
  }
}

void main() {
  setUpAll(() async {
    // NovelNoteManager / NovelBookmarkManager 依赖 Hive box，测试前需初始化。
    // 用每次运行唯一的临时目录（同 comic 阅读器测试）：固定路径会在多文件
    // 并发/先后运行时争抢同名 .lock 文件。
    Hive.init(
      Directory.systemTemp.createTempSync('novel_reader_hive').path,
    );
    // 预先打开 box，使 NovelNoteManager.init() 走 isBoxOpen 快路径同步返回，
    // 避免 Hive.openBox() 在 _init() 中创建的异步计时器干扰 pumpAndSettle。
    await Hive.openBox('novel_notes');
    await Hive.openBox('novel_bookmarks');
    // 预下载缓存 box：同样预打开，避免阅读器 _loadChapter 里 Hive.openBox
    // 的后台任务阻塞 pumpAndSettle（读缓存走 isBoxOpen 快路径返回 null）。
    await Hive.openBox('novel_pre_downloads');
  });

  // 不做 Hive.deleteFromDisk()：其内部的异步文件 I/O 在 testWidgets 文件的
  // teardown 阶段可能永不完成；目录是本次运行唯一的临时目录，交给系统清理。

  testWidgets('reader renders content and toggles UI', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'novel_prefs_n1':
          '{"pageAnimation":"slide","fontSize":18.0,"lineHeight":1.8,"margin":24.0,"paragraphSpacing":16.0,"bgPresetIndex":2}',
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
    final service = FakeNovelMediaApiService();
    // FilePrefsBackend 走 dart:io，testWidgets 的 fake-async 区域等不到
    // 真实 I/O 完成；测试注入内存后端，避免 init() 无限挂起。
    final favorites = FavoritesManager(backend: InMemoryBackend());
    await favorites.init();
    const chapters = <Episode>[
      Episode(id: 'ch1', title: '第1章 开端', url: '/ch1'),
      Episode(id: 'ch2', title: '第2章 冒险', url: '/ch2'),
    ];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<MediaApiService>.value(value: service),
          ChangeNotifierProvider<SourceRepository>.value(value: repo),
          ChangeNotifierProvider<FavoritesManager>.value(value: favorites),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          supportedLocales: <Locale>[Locale('zh'), Locale('en')],
          localizationsDelegates: <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: NovelReaderScreen(
            novelId: 'n1',
            title: '测试小说',
            sourceId: 'nsrc1',
            chapters: chapters,
          ),
        ),
      ),
    );

    // 等待异步加载完成。
    await tester.pumpAndSettle();

    // 验证小说内容已加载（页面中应包含段落文字）。
    expect(find.textContaining('第一段文字'), findsOneWidget);

    // 边距回归（漂移修复）：正文首行左边缘必须精确等于设定 margin=24，
    // 不得因 SingleChildScrollView 收缩包裹 + Column 居中而随内容宽度漂移。
    expect(tester.getTopLeft(find.textContaining('第一段文字')).dx, 24.0);

    // 正文滚动区必须占满视口宽度（800），验证不再随内容收缩包裹。
    expect(tester.getSize(find.byType(SingleChildScrollView)).width, 800.0);

    // 点击中心切换阅读器控件显隐。
    await tester.tapAt(const Offset(400, 600));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    // 标题规则贯通：控制栏章节副标题应显示源规则产生的章节名。
    expect(find.textContaining('正文规则标题'), findsWidgets);

    // 再次点击中心收起控件。
    await tester.tapAt(const Offset(400, 600));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
  });
}
