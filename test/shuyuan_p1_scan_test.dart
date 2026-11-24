/// 对等扫描 P1（A1/A2/B2/C1/C2/D1/E1/E2/E3）回归：
/// A1 字符集探测（无声明 GBK/Big5 统计识别、Big5 解码表）、
/// A2 webJs 只在 WebView 分支消费、B2 NativeObject 单段快捷路径、
/// C1 目录单页内不做提前去重、C2 广告清理移到整章替换之后、
/// D1 详情扩展字段不插进 tocUrl 的 @put 链、E1 cache 数值/内存 getter、
/// E2 src/result 绑定 jsoup 元素对象、E3 听书 URL 绑定。
library;

import 'dart:convert';
import 'dart:io';

import 'package:enough_convert/big5.dart' show Big5Codec;
import 'package:fast_gbk/fast_gbk.dart' show gbk;
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' show Element;
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexhub/core/models/novel_block.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_rule.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_url.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book_chapter.dart';
import 'package:nexhub/features/shuyuan/web_book/book_chapter_list.dart';
import 'package:nexhub/features/shuyuan/web_book/book_content.dart';
import 'package:nexhub/features/shuyuan/web_book/book_info.dart';

const String _gbkText = '这是一段中文测试文本，用于验证字符集识别是否正确。';
const String _big5Text = '這是一段中文測試文本，用於驗證字符集識別是否正確。';

XiaoshuoBookSource _source({
  Map<String, dynamic>? info,
  Map<String, dynamic>? content,
  Map<String, dynamic>? toc,
}) {
  return XiaoshuoBookSource.fromJson(<String, dynamic>{
    'bookSourceUrl': 'https://src.test',
    'bookSourceName': 'p1-scan-test',
    if (info != null) 'ruleBookInfo': info,
    if (content != null) 'ruleContent': content,
    if (toc != null) 'ruleToc': toc,
  });
}

XiaoshuoBook _book(String bookUrl) =>
    XiaoshuoBook(bookUrl: bookUrl, name: '', author: '');

XiaoshuoBookChapter _chapter(String url) =>
    XiaoshuoBookChapter(bookUrl: 'https://src.test/book/1.html', url: url);

List<String> _texts(List<NovelBlock> blocks) => <String>[
      for (final b in blocks)
        if (b is NovelTextBlock) b.text,
    ];

Future<HttpServer> _startServer({
  Map<String, ({List<int> bytes, String contentType})> byteRoutes = const {},
  Map<String, String> textRoutes = const {},
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) {
    final bin = byteRoutes[req.uri.path];
    if (bin != null) {
      req.response
        ..statusCode = 200
        ..headers.set(HttpHeaders.contentTypeHeader, bin.contentType)
        ..add(bin.bytes);
      req.response.close();
      return;
    }
    final body = textRoutes[req.uri.path];
    req.response
      ..statusCode = body == null ? 404 : 200
      ..headers.contentType = ContentType.html
      ..write(body ?? '');
    req.response.close();
  });
  return server;
}

String _origin(HttpServer server) =>
    'http://${server.address.address}:${server.port}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('A1 字符集探测', () {
    test('无声明 GBK：按字节统计识别并正确解码', () async {
      const html =
          '<html><head><title>t</title></head><body><p>$_gbkText</p></body></html>';
      final server = await _startServer(byteRoutes: {
        '/gbk': (bytes: gbk.encode(html), contentType: 'text/html'),
      });
      try {
        final au = AnalyzeUrl(
          url: '${_origin(server)}/gbk',
          baseUrl: _origin(server),
        );
        expect(await au.getStrResponse(), contains(_gbkText));
      } finally {
        await server.close(force: true);
      }
    });

    test('Big5（Content-Type 声明）：按 Big5 解码表解码', () async {
      const html =
          '<html><head><title>t</title></head><body><p>$_big5Text</p></body></html>';
      final server = await _startServer(byteRoutes: {
        '/big5-ct': (
          bytes: const Big5Codec().encode(html),
          contentType: 'text/html; charset=big5',
        ),
      });
      try {
        final au = AnalyzeUrl(
          url: '${_origin(server)}/big5-ct',
          baseUrl: _origin(server),
        );
        expect(await au.getStrResponse(), contains(_big5Text));
      } finally {
        await server.close(force: true);
      }
    });

    test('Big5（meta 声明）：按 Big5 解码表解码', () async {
      const html = '<html><head><meta charset="big5"><title>t</title></head>'
          '<body><p>$_big5Text</p></body></html>';
      final server = await _startServer(byteRoutes: {
        '/big5-meta': (
          bytes: const Big5Codec().encode(html),
          contentType: 'text/html',
        ),
      });
      try {
        final au = AnalyzeUrl(
          url: '${_origin(server)}/big5-meta',
          baseUrl: _origin(server),
        );
        expect(await au.getStrResponse(), contains(_big5Text));
      } finally {
        await server.close(force: true);
      }
    });

    test('Big5（无声明）：统计识别优先 Big5 而非 GBK 乱码', () async {
      const html =
          '<html><head><title>t</title></head><body><p>$_big5Text</p></body></html>';
      final server = await _startServer(byteRoutes: {
        '/big5': (
          bytes: const Big5Codec().encode(html),
          contentType: 'text/html',
        ),
      });
      try {
        final au = AnalyzeUrl(
          url: '${_origin(server)}/big5',
          baseUrl: _origin(server),
        );
        expect(await au.getStrResponse(), contains(_big5Text));
      } finally {
        await server.close(force: true);
      }
    });

    test('无声明 UTF-8：原样解码（回归）', () async {
      const html =
          '<html><head><title>t</title></head><body><p>$_gbkText</p></body></html>';
      final server = await _startServer(byteRoutes: {
        '/utf8': (
          bytes: utf8.encode(html),
          contentType: 'text/html',
        ),
      });
      try {
        final au = AnalyzeUrl(
          url: '${_origin(server)}/utf8',
          baseUrl: _origin(server),
        );
        expect(await au.getStrResponse(), contains(_gbkText));
      } finally {
        await server.close(force: true);
      }
    });
  });

  group('A2 webJs 消费条件', () {
    test('仅声明 webJs（无 webView）：直连返回原始响应体', () async {
      final server = await _startServer(textRoutes: {
        '/page.html': '<html><body><div id="c">正文内容直接返回</div></body></html>',
      });
      try {
        final au = AnalyzeUrl(
          url: '${_origin(server)}/page.html,'
              '{"webJs":"document.body.innerText"}',
          baseUrl: _origin(server),
        );
        final body = await au.getStrResponse();
        expect(body, contains('正文内容直接返回'));
      } finally {
        await server.close(force: true);
      }
    });
  });

  group('B2 NativeObject 单段快捷路径', () {
    AnalyzeRule rule() => AnalyzeRule()
      ..setContent(<String, dynamic>{
        'name': '旧名',
        'tags': <String>['甲', '乙'],
      }, 'https://src.test/');

    test(r'$.name / @js:/ 字段直读', () {
      expect(rule().getString(r'$.name'), '旧名');
      expect(rule().getString('@js:result.name'), '旧名');
      expect(rule().getString('name'), '旧名');
    });

    test('多段规则只执行第一段（legado ruleList.first）', () {
      expect(rule().getString("name@js:result + '!'"), '旧名');
      expect(rule().getStringList('tags@js:result.slice(0,1)'), <String>['甲', '乙']);
    });

    test('{{}} 模板展开保持超集行为', () {
      expect(rule().getString('{{result.name}}'), '旧名');
    });

    test('列表取值（键直读与 JSONPath）', () {
      expect(rule().getStringList('tags'), <String>['甲', '乙']);
      expect(rule().getStringList(r'$.tags'), <String>['甲', '乙']);
    });
  });

  group('C1 目录单页内不提前去重', () {
    test('同一页重复链接全部入列（合并层再去重）', () {
      final source = _source(toc: <String, dynamic>{
        'chapterList': '#list a',
        'chapterName': 'text',
        'chapterUrl': '@href',
      });
      final chapters = BookChapterList.analyzeChapterList(
        bookSource: source,
        book: _book('https://src.test/book/1.html'),
        baseUrl: 'https://src.test/book/1.html',
        redirectUrl: 'https://src.test/book/1.html',
        body: '<div id="list">'
            '<a href="/c1">A1</a><a href="/c1">A1</a><a href="/c2">A2</a>'
            '</div>',
        getNextUrl: false,
        applyReverse: false,
      );
      expect(chapters.map((c) => c.url), <String>[
        'https://src.test/c1',
        'https://src.test/c1',
        'https://src.test/c2',
      ]);
    });
  });

  group('C2 广告清理位于整章替换之后', () {
    const adLine = '请收藏本站最新网址';

    test('延迟后处理：正文解析阶段保留广告行', () {
      final source = _source(content: <String, dynamic>{
        'content': '#txt@html',
      });
      final blocks = BookContent.analyzeContent(
        bookSource: source,
        book: _book('https://src.test/book/1.html'),
        bookChapter: _chapter('https://src.test/book/1.html'),
        baseUrl: 'https://src.test/book/1.html',
        redirectUrl: null,
        body: '<div id="txt"><p>第一段</p><p>$adLine</p></div>',
        deferChapterPostProcess: true,
      );
      expect(_texts(blocks), contains(adLine));
    });

    test('subContent 提取不删广告行（留给整章后处理）', () {
      final blocks = BookContent.extractAppendedBlocks(
        content: '<p>追加段落</p><p>$adLine</p>',
        baseUrl: 'https://src.test/book/1.html',
        redirectUrl: 'https://src.test/book/1.html',
      );
      expect(_texts(blocks), contains(adLine));
    });

    test('replaceRegex 先执行，替换后的广告行不再命中关键词', () {
      final source = _source(content: <String, dynamic>{
        'replaceRegex': '请收藏##已替换',
      });
      final blocks = BookContent.extractAppendedBlocks(
        content: '<p>第一段</p><p>$adLine</p>',
        baseUrl: 'https://src.test/book/1.html',
        redirectUrl: 'https://src.test/book/1.html',
      );
      final out = BookContent.finalizeChapter(
        blocks: blocks,
        contentRule: source.getContentRule(),
        analyzeRule: AnalyzeRule()..setContent(''),
        mediaSource: false,
      );
      expect(_texts(out), <String>['　　第一段', '　　已替换本站最新网址']);
    });

    test('无 replaceRegex：最终章清洗删除广告行并保留正文缩进', () {
      final source = _source(content: <String, dynamic>{});
      final blocks = BookContent.extractAppendedBlocks(
        content: '<p>第一段</p><p>$adLine</p>',
        baseUrl: 'https://src.test/book/1.html',
        redirectUrl: 'https://src.test/book/1.html',
      );
      final out = BookContent.finalizeChapter(
        blocks: blocks,
        contentRule: source.getContentRule(),
        analyzeRule: AnalyzeRule()..setContent(''),
        mediaSource: false,
      );
      expect(_texts(out), <String>['　　第一段']);
    });
  });

  group('D1 详情扩展字段不插入 tocUrl 的 @put 链', () {
    test('tocUrl 先于 updateTime 求值；扩展字段仍解析（超集保留）', () {
      final source = _source(info: <String, dynamic>{
        'tocUrl': '@get:{toc}',
        'updateTime': '#ut@text@put:{toc:"#tocLink@href"}',
        'bookStatus': '#bs@text',
        'recommendations': '#recs a@text',
      });
      final book = _book('https://src.test/book/1.html');
      const body = '<span id="ut">2026-01-01</span>'
          '<span id="bs">连载</span>'
          '<div id="recs"><a>推荐书</a></div>'
          '<a id="tocLink" href="https://put.test/toc">目录</a>';
      BookInfo.analyzeBookInfo(
        bookSource: source,
        book: book,
        baseUrl: 'https://src.test/book/1.html',
        redirectUrl: 'https://src.test/book/1.html',
        body: body,
      );
      expect(book.tocUrl, 'https://src.test/book/1.html');
      expect(book.tocHtml, body);
      expect(book.updateTime, '2026-01-01');
      expect(book.bookStatus, '连载');
      expect(book.recommendations, <String>['推荐书']);
    });
  });

  group('E1 cache 数值/内存 getter', () {
    test('getFromMemory/getInt/getLong/getDouble/getFloat/getByteArray', () {
      final rule = AnalyzeRule()..setContent('');
      final out = rule.getString(
          '@js:cache.put("k", 12); cache.put("f", "1.5"); '
          '[cache.getInt("k"), cache.getLong("k"), cache.getDouble("f"), '
          'cache.getFloat("f"), cache.getInt("missing"), '
          'cache.putMemory("m", "mem"), cache.getFromMemory("m"), '
          'cache.getFromMemory("nope"), cache.getByteArray("k")].join("|")');
      expect(out, '12|12|1.5|1.5|||mem||');
    });
  });

  group('E2 src / result 绑定元素对象', () {
    final doc = html_parser.parse('<div id="book">'
        '<span class="n">书名</span><a href="/toc">目录</a></div>');

    test('Element 内容：src.text() / src.select() / result.attr()', () {
      final root = doc.getElementById('book')!;
      final rule = AnalyzeRule()..setContent(root, 'https://src.test/');
      final text = rule.getString('@js:src.text()');
      expect(text, contains('书名'));
      expect(text, contains('目录'));
      expect(rule.getString("@js:src.select('a').attr('href')"), '/toc');
      expect(rule.getString("@js:result.attr('id')"), 'book');
    });

    test('List<Element> 内容：size() / get(i)', () {
      final List<Element> els = doc.querySelectorAll('span.n, a');
      final rule = AnalyzeRule()..setContent(els, 'https://src.test/');
      expect(rule.getString('@js:String(result.size())'), '2');
      expect(rule.getString('@js:result.get(0).text()'), '书名');
      expect(rule.getString("@js:result.get(1).attr('href')"), '/toc');
    });
  });

  group('E3 听书 URL 绑定', () {
    test('currentToneID/currentSpeakerName/currentEmotionName/Tag/speakSpeed',
        () {
      final au = AnalyzeUrl(
        url: 'https://api.test/tts?tone={{currentToneID}}'
            '&sn={{currentSpeakerName}}&en={{currentEmotionName}}'
            '&et={{currentEmotionTag}}&sp={{speakSpeed}}&p={{page}}',
        baseUrl: 'https://api.test/',
        page: 3,
        speakText: '文本',
        speakSpeed: 7,
        currentToneID: 'tone-1',
        currentSpeakerName: 'speaker-1',
        currentEmotionName: 'happy',
        currentEmotionTag: 'tag-9',
      );
      expect(au.ruleUrl, contains('tone=tone-1'));
      expect(au.ruleUrl, contains('sn=speaker-1'));
      expect(au.ruleUrl, contains('en=happy'));
      expect(au.ruleUrl, contains('et=tag-9'));
      expect(au.ruleUrl, contains('sp=7'));
      expect(au.ruleUrl, contains('p=3'));
    });
  });
}
