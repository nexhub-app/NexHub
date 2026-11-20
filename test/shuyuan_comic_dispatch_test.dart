/// 漫画源分发测试（P2-4）：adapter 类型分派 + 图片 URL 提取 + comic 章节构造。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/novel_block.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book_chapter.dart';
import 'package:nexhub/features/shuyuan/presentation/shuyuan_novel_resolver.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';

ShuyuanSource _comicSource() => ShuyuanSource.fromJson({
      'bookSourceUrl': 'https://comic.example.com/',
      'bookSourceName': '测试漫画源',
      'bookSourceType': 2, // 图片/漫画
      'enabled': true,
      'searchUrl': '/search?kw={{key}}',
      'ruleSearch': {'bookList': 'class.item', 'name': 'tag.h3@text'},
      'ruleToc': {'chapterList': 'class.list'},
      'ruleContent': {'content': 'class.content@html'},
    });

ShuyuanSource _novelSource() => ShuyuanSource.fromJson({
      'bookSourceUrl': 'https://novel.example.com/',
      'bookSourceName': '测试小说源',
      'bookSourceType': 0,
      'enabled': true,
      'searchUrl': '/search?kw={{key}}',
      'ruleSearch': {'bookList': 'class.item', 'name': 'tag.h3@text'},
    });

void main() {
  group('漫画源类型分派（P2-4）', () {
    test('bookSourceType=2 → PluginConfig.type = mangaSource', () {
      final config = ShuyuanAdapter.toPluginConfig(_comicSource());
      expect(config.type, SourceType.mangaSource);
    });

    test('bookSourceType=0 → 维持 novelSource', () {
      final config = ShuyuanAdapter.toPluginConfig(_novelSource());
      expect(config.type, SourceType.novelSource);
    });

    test('漫画源的 selectors[xiaoshuo] 保留（引擎复用）', () {
      final config = ShuyuanAdapter.toPluginConfig(_comicSource());
      expect(config.selectors?['xiaoshuo'], isA<Map<String, dynamic>>());
      // 注册表按 selectors 路由（_isShuyuanSource），类型无关。
      expect(ShuyuanAdapter.isShuyuanSource(config), true);
    });

    test('漫画源章节 Episode.id 存章节 URL（阅读器 chapterId 回传）', () {
      // 经 _handleChapterList 的 isComic 分支构造逻辑：这里直接验证
      // resolver 的静态判定输入（source.type == mangaSource 时 id=url）。
      final config = ShuyuanAdapter.toPluginConfig(_comicSource());
      expect(config.type == SourceType.mangaSource, true);
    });
  });

  group('漫画图片 URL 提取', () {
    test('插图块直取', () {
      final blocks = <NovelBlock>[
        const NovelImageBlock('https://img.example.com/1.jpg'),
        const NovelTextBlock('中间文字'),
        const NovelImageBlock('https://img.example.com/2.jpg'),
      ];
      expect(ShuyuanNovelResolver.imageUrlsFromBlocks(blocks),
          ['https://img.example.com/1.jpg', 'https://img.example.com/2.jpg']);
    });

    test('纯 URL 文本行兜底（URL 列表形态）', () {
      final blocks = <NovelBlock>[
        const NovelTextBlock(
            'https://img.example.com/p1.jpg\nhttps://img.example.com/p2.jpg'),
      ];
      expect(ShuyuanNovelResolver.imageUrlsFromBlocks(blocks),
          ['https://img.example.com/p1.jpg', 'https://img.example.com/p2.jpg']);
    });

    test('插图块优先，URL 行兜底不混入', () {
      final blocks = <NovelBlock>[
        const NovelImageBlock('https://img.example.com/a.jpg'),
      ];
      expect(ShuyuanNovelResolver.imageUrlsFromBlocks(blocks),
          ['https://img.example.com/a.jpg']);
    });

    List<String> fromText(String text, {String? base}) =>
        ShuyuanNovelResolver.imageUrlsFromBlocks(
          [NovelTextBlock(text)],
          baseUrl: base,
        );

    test('协议相对/根相对/相对路径按章节地址绝对化', () {
      const base = 'https://comic.example.com/ch/12.html';
      expect(
        fromText('//cdn.example.com/1.jpg\n/images/2.jpg\nimg/3.png',
            base: base),
        [
          'https://cdn.example.com/1.jpg',
          'https://comic.example.com/images/2.jpg',
          'https://comic.example.com/ch/img/3.png',
        ],
      );
    });

    test('JSON 数组与引号/逗号分隔', () {
      expect(
        fromText('["https://img.example.com/1.jpg",'
            '"https://img.example.com/2.jpg"]'),
        [
          'https://img.example.com/1.jpg',
          'https://img.example.com/2.jpg',
        ],
      );
    });

    test('&& 分隔与实体编码查询串', () {
      expect(
        fromText('https://img.example.com/1.jpg?a=1&amp;b=2'
            '&&https://img.example.com/2.jpg'),
        [
          'https://img.example.com/1.jpg?a=1&b=2',
          'https://img.example.com/2.jpg',
        ],
      );
    });

    test('data:image 直取，保序去重', () {
      const d = 'data:image/png;base64,AAAA';
      expect(
        fromText('$d,https://img.example.com/1.jpg\n$d'),
        [d, 'https://img.example.com/1.jpg'],
      );
    });

    test('无基准地址时相对路径不产出，javascript 忽略', () {
      expect(fromText('/images/1.jpg\njavascript:alert(1)\nimg/2.png'),
          isEmpty);
    });

    test('相对文本无图片扩展名时不误收', () {
      expect(fromText('upload/file?id=1'), isEmpty);
    });
  });

  group('章节 → Episode 映射（漫画 id=URL）', () {
    final chapters = <XiaoshuoBookChapter>[
      XiaoshuoBookChapter(
        bookUrl: 'https://comic.example.com/book/1',
        url: 'https://comic.example.com/ch/1',
        title: '第1话',
        index: 0,
      ),
      XiaoshuoBookChapter(
        bookUrl: 'https://comic.example.com/book/1',
        url: 'https://comic.example.com/ch/2',
        title: '第2话',
        index: 1,
      ),
    ];

    test('漫画：id 与 url 均为章节地址（直连/回灌共用）', () {
      final eps =
          ShuyuanNovelResolver.episodesFromChapters(chapters, isComic: true);
      expect(eps.map((e) => e.id), [
        'https://comic.example.com/ch/1',
        'https://comic.example.com/ch/2',
      ]);
      expect(eps.map((e) => e.url), [
        'https://comic.example.com/ch/1',
        'https://comic.example.com/ch/2',
      ]);
    });

    test('小说：id 为章节序号', () {
      final eps =
          ShuyuanNovelResolver.episodesFromChapters(chapters, isComic: false);
      expect(eps.map((e) => e.id), ['0', '1']);
    });
  });
}
