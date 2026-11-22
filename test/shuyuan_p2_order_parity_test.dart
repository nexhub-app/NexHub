/// legado P2 对等批回归（对照 md3）：
/// - A2 `AnalyzeUrl(baseUrl)` 携带 `,{...}` URL 选项串时先截断再绝对化；
/// - A5 WebView 分支合并 URL 选项 headers 与调用方显式 headers；
/// - B4 `getStringList` 按换行拆分保留空串项；B5 `isUrl` 基准为 redirectUrl；
/// - C1 详情求值顺序（kind 的 `@put` 对后续 lastChapter/intro 可见）；
/// - C3 `BookInfoRule.relatedBooks` JSON 往返；
/// - C15 标题规则图片尾巴写入章节 `imgUrl`（legado reviewImg）；
/// - E8 ajax 失败缓存 legado stackTraceStr 文本（`java` 前缀），供
///   `startsWith("java")` 类源判定失败。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexhub/features/shuyuan/analyze/analyze_rule.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_url.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/analyze/webview_fetcher.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';
import 'package:nexhub/features/shuyuan/model/rule_book_info.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book_chapter.dart';
import 'package:nexhub/features/shuyuan/web_book/book_content.dart';
import 'package:nexhub/features/shuyuan/web_book/book_info.dart';

XiaoshuoBookSource _source({Map<String, dynamic>? content}) {
  return XiaoshuoBookSource.fromJson(<String, dynamic>{
    'bookSourceUrl': 'https://src.test',
    'bookSourceName': 'p2-order-test',
    'bookSourceType': 0,
    if (content != null) 'ruleContent': content,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ShuyuanSourceContext.resetForTest();
    ShuyuanWebviewFetcher.debugFetchOverride = null;
  });
  tearDown(() => ShuyuanWebviewFetcher.debugFetchOverride = null);

  group('A2 baseUrl 选项串截断', () {
    test('baseUrl 携带 ,{...} 时不卷进相对地址', () {
      final au = AnalyzeUrl(
        url: 'book/1.html',
        baseUrl: 'http://h.test/dir/,{"headers":{"X-A":"1"}}',
      );
      expect(au.url, 'http://h.test/dir/book/1.html');
      // baseUrl 之后由请求 URL 回填（origin 口径），选项串不得混入。
      expect(au.baseUrl, isNot(contains(',{')));
    });
  });

  group('A5 WebView 请求头并集', () {
    test('URL 选项 headers 与显式 headers 都透传给 WebView', () async {
      Map<String, String>? seen;
      ShuyuanWebviewFetcher.debugFetchOverride = ({
        String? html,
        String? url,
        String? js,
        int delayMs = 0,
        Map<String, String>? headers,
        String? sourceRegex,
        String? overrideUrlRegex,
      }) async {
        seen = headers;
        return const ShuyuanWebviewResult(
          html: '<div id="c">渲染正文</div>',
          finalUrl: 'https://web.test/final',
        );
      };
      final source = XiaoshuoBookSource.fromJson(<String, dynamic>{
        'bookSourceUrl': 'https://web.test',
        'bookSourceName': 'wv-p2',
        'bookSourceType': 0,
        'header': '{"X-From":"source"}',
      });
      final ctx = ShuyuanSourceContext('src_wv_p2');
      final out = await ShuyuanSourceContext.run(ctx, () {
        final a = AnalyzeUrl(
          url:
              'https://web.test/page,{"webView":true,"headers":{"X-Url":"urlopt"}}',
          baseUrl: 'https://web.test',
          source: source,
        );
        return a.getStrResponse(headers: <String, String>{'X-Extra': 'explicit'});
      });
      expect(out, contains('渲染正文'));
      expect(seen?['X-From'], 'source');
      expect(seen?['X-Url'], 'urlopt');
      expect(seen?['X-Extra'], 'explicit');
    });
  });

  group('B4/B5 字符串列表与 URL 基准', () {
    test('getStringList 按换行拆分保留空行项', () {
      final rule = AnalyzeRule()..setContent('<p>x</p>');
      expect(rule.getStringList(r"@js:'a\n\nb'"), <String>['a', '', 'b']);
    });

    test('isUrl：redirectUrl 缺失时保留相对形态', () {
      final rule = AnalyzeRule()
        ..setContent('<a href="/book/1.html">书</a>')
        ..setBaseUrl('http://h.test/');
      expect(rule.getString('a@href', isUrl: true), '/book/1.html');
    });

    test('isUrl：相对地址按 redirectUrl 解析', () {
      final rule = AnalyzeRule()
        ..setContent('<a href="book/1.html">书</a>')
        ..setBaseUrl('http://h.test/')
        ..setRedirectUrl('http://h.test/dir/page.html');
      expect(
          rule.getString('a@href', isUrl: true), 'http://h.test/dir/book/1.html');
    });

    test('isUrl：空结果回落 baseUrl（legado getString 空值分支）', () {
      final rule = AnalyzeRule()
        ..setContent('<a href="/x">书</a>')
        ..setBaseUrl('http://h.test/');
      expect(rule.getString('a.nomatch@href', isUrl: true), 'http://h.test/');
    });
  });

  group('C1 详情求值顺序', () {
    test('kind 的 @put 对后续 lastChapter/intro 可见', () {
      final source = XiaoshuoBookSource.fromJson(<String, dynamic>{
        'bookSourceName': 'order-test',
        'bookSourceUrl': 'https://x.test',
        'bookSourceType': 0,
        'ruleBookInfo': <String, dynamic>{
          'kind': 'span.kind@text@put:{kc:"span.last@text"}',
          'lastChapter': '@get:{kc}',
          'intro': '@get:{kc}',
        },
      });
      final book = XiaoshuoBook(bookUrl: 'https://x.test/book/1', name: '');
      BookInfo.analyzeBookInfo(
        bookSource: source,
        book: book,
        baseUrl: 'https://x.test/book/1',
        redirectUrl: 'https://x.test/book/1',
        body: '<span class="kind">玄幻</span>'
            '<span class="last">第9章 完</span>',
      );
      expect(book.kind, '玄幻');
      expect(book.lastChapter, '第9章 完');
      expect(book.intro, contains('第9章'));
    });
  });

  group('C3 relatedBooks', () {
    test('fromJson/toJson 往返保留', () {
      final rule = BookInfoRule.fromJson(<String, dynamic>{
        'relatedBooks': 'div.rec@text',
      });
      expect(rule.relatedBooks, 'div.rec@text');
      expect(rule.toJson()['relatedBooks'], 'div.rec@text');
    });
  });

  group('C15 标题图片尾巴', () {
    test('imgRegex 命中的图片写入章节 imgUrl', () {
      final chapter = XiaoshuoBookChapter(
        bookUrl: 'https://src.test/book/1.html',
        url: 'https://src.test/c/1.html',
        title: '目录原名',
      );
      BookContent.analyzeContent(
        bookSource:
            _source(content: <String, dynamic>{
          'content': '#c@html',
          'title': 'h1@text',
        }),
        book: XiaoshuoBook(
            bookUrl: 'https://src.test/book/1.html', name: '', author: ''),
        bookChapter: chapter,
        baseUrl: 'https://src.test/c/1.html',
        redirectUrl: 'https://src.test/c/1.html',
        body: '<h1>第十章 云涌https://img.example.com/a.jpg</h1>'
            '<div id="c">正文</div>',
      );
      expect(chapter.title, '第十章 云涌');
      expect(chapter.imgUrl, 'https://img.example.com/a.jpg');
    });
  });

  group('E8 ajax 失败返回 stackTraceStr 文本', () {
    test('deadline 到期：缓存 java 前缀失败文本', () async {
      final source = _source();
      final ctx = ShuyuanSourceContext('src_e8_deadline');
      const key = 'https://e8.invalid/x';
      ctx.ajaxPending.add(key);
      await ShuyuanSourceContext.settleAjax(
        ctx,
        source,
        deadline: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      expect(ctx.ajaxCache[key],
          startsWith(ShuyuanSourceContext.ajaxFailurePrefix));
      expect(ctx.ajaxCache[key]!.startsWith('java'), isTrue);
    });

    test('请求异常：缓存异常文本而非空串', () async {
      final source = _source();
      final ctx = ShuyuanSourceContext('src_e8_error');
      // 本机特权端口无监听：连接立即被拒，不依赖外部网络。
      const key = 'http://127.0.0.1:1/e8';
      ctx.ajaxPending.add(key);
      final fetched = await ShuyuanSourceContext.settleAjax(ctx, source);
      expect(fetched, 1);
      expect(ctx.ajaxCache[key],
          startsWith(ShuyuanSourceContext.ajaxFailurePrefix));
      expect(ctx.ajaxBytesCache.containsKey(key), isFalse);
    });
  });
}
