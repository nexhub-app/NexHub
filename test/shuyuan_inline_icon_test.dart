/// 正文插图 URL 选项（legado `<img src="url,{...}">`）回归：
/// 选项串必须剥离（否则带 JSON 尾的地址下载失败 → 裂图），
/// `style:"text"` + `click` 要识别成「可点击行内图标」。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexhub/core/models/novel_block.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book_chapter.dart';
import 'package:nexhub/features/shuyuan/web_book/book_content.dart';

XiaoshuoBookSource _source() => XiaoshuoBookSource.fromJson(<String, dynamic>{
      'bookSourceUrl': 'https://src.test',
      'bookSourceName': 'inline-icon',
      'ruleContent': <String, dynamic>{'content': '#c@html'},
    });

List<NovelBlock> _parse(String body) => BookContent.analyzeContent(
      bookSource: _source(),
      book: XiaoshuoBook(bookUrl: 'https://src.test/b', name: '书'),
      bookChapter: XiaoshuoBookChapter(
        bookUrl: 'https://src.test/b',
        url: 'https://src.test/c/1.html',
      ),
      baseUrl: 'https://src.test/c/1.html',
      redirectUrl: 'https://src.test/c/1.html',
      body: body,
    );

List<NovelImageBlock> _images(List<NovelBlock> blocks) =>
    blocks.whereType<NovelImageBlock>().toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('插图 URL 选项', () {
    test('style:TEXT + click → 行内可点击图标，地址剥离选项串', () {
      final blocks = _parse('<div id="c">第一段'
          r'''<img src="data:image/svg+xml;base64,AAAA,{"style":"TEXT","click":"java.showBrowser('u','')"}">'''
          '<p>第二段</p></div>');
      final images = _images(blocks);
      expect(images, hasLength(1));
      expect(images.single.url, 'data:image/svg+xml;base64,AAAA');
      expect(images.single.inline, isTrue);
      expect(images.single.clickScript, contains('showBrowser'));
      expect(images.single.isInlineAction, isTrue);
    });

    test('无 style/click 的选项（如 headers）只剥离，不当作图标', () {
      final blocks = _parse('<div id="c"><p>正文</p>'
          r'''<p><img src="https://cdn.test/a.jpg,{"headers":{"Referer":"https://x"}}"></p>'''
          '</div>');
      final images = _images(blocks);
      expect(images, hasLength(1));
      expect(images.single.url, 'https://cdn.test/a.jpg');
      expect(images.single.inline, isFalse);
      expect(images.single.clickScript, isNull);
      expect(images.single.isInlineAction, isFalse);
    });

    test('普通插图地址（实体反转义）行为不变', () {
      final blocks = _parse('<div id="c"><p>正文</p>'
          '<p><img src="https://cdn.test/a.jpg?x=1&amp;y=2"></p></div>');
      final images = _images(blocks);
      expect(images.single.url, 'https://cdn.test/a.jpg?x=1&y=2');
      expect(images.single.isInlineAction, isFalse);
    });

    test('SVG 图标只写了 click、漏了 style 时也按行内图标处理', () {
      final blocks = _parse('<div id="c"><p>正文</p>'
          r'''<p><img src="data:image/svg+xml;base64,BBBB,{"click":"java.showBrowser('u','')"}"></p>'''
          '</div>');
      final images = _images(blocks);
      expect(images.single.url, 'data:image/svg+xml;base64,BBBB');
      expect(images.single.inline, isFalse);
      expect(images.single.isInlineAction, isTrue);
    });

    test('内联 SVG 即使没有 click 也标记为 svg 图标（渲染层不占页）', () {
      final blocks = _parse('<div id="c"><p>正文</p>'
          '<p><img src="data:image/svg+xml;base64,CCCC"></p></div>');
      final images = _images(blocks);
      expect(images.single.isSvgIcon, isTrue);
      expect(images.single.isInlineAction, isFalse);
    });

    test('普通位图带 click 但没有 style:text 时仍按整块插图渲染', () {
      final blocks = _parse('<div id="c"><p>正文</p>'
          r'''<p><img src="https://cdn.test/b.jpg,{"click":"java.showBrowser('u','')"}"></p>'''
          '</div>');
      final images = _images(blocks);
      expect(images.single.url, 'https://cdn.test/b.jpg');
      expect(images.single.clickScript, contains('showBrowser'));
      expect(images.single.inline, isFalse);
      expect(images.single.isInlineAction, isFalse);
    });
  });
}
