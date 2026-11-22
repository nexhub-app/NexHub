/// P2 边界语义对齐批回归（对照 legado md3）：
/// - `formatBookName/Author` 精确口径（列表与详情同源，去分隔符/80 字截断已移除）；
/// - HtmlFormatter Java `\s`（ASCII 空白）缩进语义；
/// - Jsoup ownText / XPATH text() 的 ASCII 空白折叠（保留 U+3000）；
/// - 插图正则三档（brace 选项 → data-src|src 后位优先 → 任意 data-*）；
/// - 卷章正文早退（`tag` 即正文）；
/// - XML 响应自动补 `<?xml version="1.0"?>`；
/// - ExploreRule.pageParam JSON 往返。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexhub/core/models/novel_block.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_jsoup.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_url.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_xpath.dart';
import 'package:nexhub/features/shuyuan/analyze/html_formatter.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/analyze/string_utils.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';
import 'package:nexhub/features/shuyuan/model/rule_explore.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book_chapter.dart';
import 'package:nexhub/features/shuyuan/web_book/book_content.dart';
import 'package:nexhub/features/shuyuan/web_book/book_list.dart';

XiaoshuoBookSource _source({
  Map<String, dynamic>? search,
  Map<String, dynamic>? content,
}) {
  return XiaoshuoBookSource.fromJson(<String, dynamic>{
    'bookSourceUrl': 'https://src.test',
    'bookSourceName': 'p2-test',
    'bookSourceType': 0,
    if (search != null) 'ruleSearch': search,
    if (content != null) 'ruleContent': content,
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

List<String> _images(List<NovelBlock> blocks) => <String>[
      for (final b in blocks)
        if (b is NovelImageBlock) b.url,
    ];

List<String> _chapterImages(String body) => _images(BookContent.analyzeContent(
      bookSource: _source(content: <String, dynamic>{'content': '#c@html'}),
      book: _book('https://src.test/book/1.html'),
      bookChapter: _chapter('https://src.test/c/1.html'),
      baseUrl: 'https://src.test/c/1.html',
      redirectUrl: 'https://src.test/c/1.html',
      body: body,
    ));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('StringUtils 归一（legado BookHelp/AppPattern）', () {
    test('formatBookName：去作者尾巴，仅 ASCII 修剪', () {
      expect(StringUtils.formatBookName('书名 作者：张三'), '书名');
      expect(StringUtils.formatBookName('书名 李四 著'), '书名');
      expect(StringUtils.formatBookName('  书名  '), '书名');
      // Java `\s` 不含 U+3000：全角空格既不作分隔也保留在结果里。
      expect(StringUtils.formatBookName('书名\u3000'), '书名\u3000');
      expect(StringUtils.formatBookName('书名\u3000作者：张三'),
          '书名\u3000作者：张三');
    });

    test('formatBookAuthor：去「作者：」前缀与「 著」尾巴', () {
      expect(StringUtils.formatBookAuthor('作者：李四 著'), '李四');
      expect(StringUtils.formatBookAuthor('作者:王五'), '王五');
      expect(StringUtils.formatBookAuthor('\u3000作者甲'), '\u3000作者甲');
    });

    test('trimAscii：只修剪 <= 0x20', () {
      expect(StringUtils.trimAscii(' \t书名\r\n'), '书名');
      expect(StringUtils.trimAscii('\u3000书名\u3000'), '\u3000书名\u3000');
    });
  });

  group('BookList 列表阶段书名/作者精确归一', () {
    test('保留分隔符与全角空格，不截断长书名', () {
      final source = _source(search: <String, dynamic>{
        'bookList': '#list li.item',
        'name': 'a.name@text',
        'author': 'span.author@text',
        'bookUrl': 'a.name@href',
      });
      final longName = '长' * 90;
      final html = '<ul id="list">'
          '<li class="item"><a class="name" href="/book/1">书名 作者：张三</a>'
          '<span class="author">作者：李四 著</span></li>'
          '<li class="item"><a class="name" href="/book/2">--书名--</a>'
          '<span class="author">--乙--</span></li>'
          '<li class="item"><a class="name" href="/book/3">$longName</a></li>'
          '</ul>';
      final ctx = ShuyuanSourceContext('p2-list')..bindSource(source);
      final books = ShuyuanSourceContext.run(
        ctx,
        () => BookList.analyzeBookList(
          bookSource: source,
          baseUrl: 'https://src.test/list',
          body: html,
          isSearch: true,
          searchKey: 'x',
        ),
      );
      expect(books.length, 3);
      expect(books[0].name, '书名');
      expect(books[0].author, '李四');
      // 旧实现（formatBookNameLight）会去首尾分隔符、截断 80 字；legado 不。
      expect(books[1].name, '--书名--');
      expect(books[1].author, '--乙--');
      expect(books[2].name.length, 90);
    });

    test('全角空格结尾的书名在列表阶段保留', () {
      final source = _source(search: <String, dynamic>{
        'bookList': '#list li.item',
        'name': "@js:'书名\u3000'",
        'bookUrl': 'a.name@href',
      });
      const html = '<ul id="list"><li class="item">'
          '<a class="name" href="/book/1">x</a></li></ul>';
      final ctx = ShuyuanSourceContext('p2-list2')..bindSource(source);
      final books = ShuyuanSourceContext.run(
        ctx,
        () => BookList.analyzeBookList(
          bookSource: source,
          baseUrl: 'https://src.test/list',
          body: html,
          isSearch: true,
          searchKey: 'x',
        ),
      );
      expect(books.single.name, '书名\u3000');
    });
  });

  group('HtmlFormatter Java `\\s` 语义', () {
    test('仅折叠/修剪 ASCII 空白，U+3000 原样保留', () {
      expect(HtmlFormatter.format('第一段\u3000'), '第一段\u3000');
      expect(HtmlFormatter.format('第一段  '), '第一段');
      expect(HtmlFormatter.format('第一段\n第二段'), '第一段\n　　第二段');
    });

    test('外层标签先变换行：首段两轮缩进、末尾保留段末缩进（JDK 实测）', () {
      expect(
        HtmlFormatter.format('<p>第一段</p><p>第二段</p>'),
        '　　　　第一段\n　　第二段\n　　',
      );
    });
  });

  group('选择器文本空白（jsoup ownText / XML normalize-space）', () {
    test('Jsoup ownText：ASCII 空白折叠，U+3000 不折叠', () {
      const html = '<div id="w">'
          '<p id="a">甲\n乙<i>注</i></p>'
          '<p id="b">甲\u3000乙</p>'
          '</div>';
      final a = AnalyzeByJsoup(html);
      expect(a.getStringList('p:containsown(甲 乙)@id'), <String>['a']);
      expect(a.getStringList('text.甲 乙@id'), <String>['a']);
    });

    test('XPATH text()：ASCII 空白折叠，U+3000 保留', () {
      final x = AnalyzeByXPath(
          '<div id="a">甲\n乙</div><div id="b">甲\u3000乙</div>');
      expect(x.getStringList('//div/text()'), <String>['甲 乙', '甲\u3000乙']);
      expect(x.getString('normalize-space(//div[2]/text())'), '甲\u3000乙');
    });
  });

  group('BookContent 插图抽取（legado formatImagePattern）', () {
    test('data-src|src 后位属性优先（贪婪前缀）', () {
      expect(
        _chapterImages(
            '<div id="c"><img src="a.jpg" data-src="b.jpg"></div>'),
        <String>['https://src.test/c/b.jpg'],
      );
      expect(
        _chapterImages(
            '<div id="c"><img data-src="b.jpg" src="a.jpg"></div>'),
        <String>['https://src.test/c/a.jpg'],
      );
    });

    test('src 优先于 data-original；仅 data-* 时取最后一个 data 属性', () {
      expect(
        _chapterImages(
            '<div id="c"><img src="a.jpg" data-original="b.jpg"></div>'),
        <String>['https://src.test/c/a.jpg'],
      );
      expect(
        _chapterImages('<div id="c"><img data-original="b.jpg"></div>'),
        <String>['https://src.test/c/b.jpg'],
      );
      expect(
        _chapterImages('<div id="c"><img data-x="x.jpg" data-y="y.jpg"></div>'),
        <String>['https://src.test/c/y.jpg'],
      );
      expect(
        _chapterImages("<div id=\"c\"><img data-src='b.jpg'></div>"),
        <String>['https://src.test/c/b.jpg'],
      );
    });

    test('brace 模板 URL：实体反转义 + URL 选项保留 + 相对地址绝对化', () {
      expect(
        _chapterImages('<div id="c"><img src="/img/a.jpg,{&quot;headers&quot;:'
            '{&quot;Referer&quot;:&quot;https://x&quot;}}"></div>'),
        <String>[
          'https://src.test/img/a.jpg,'
              '{"headers":{"Referer":"https://x"}}'
        ],
      );
    });
  });

  group('卷章正文早退（legado WebBook.getContent）', () {
    test('URL 为标题占位时返回 tag 原文，不解析规则', () {
      final source = _source(content: <String, dynamic>{'content': '#c@html'});
      final chapter = _chapter('第3卷 风起7')
        ..title = '第3卷 风起'
        ..isVolume = true
        ..tag = ' 卷简介 ';
      final blocks = BookContent.analyzeContent(
        bookSource: source,
        book: _book('https://src.test/book/1.html'),
        bookChapter: chapter,
        baseUrl: 'https://src.test/toc.html',
        redirectUrl: 'https://src.test/toc.html',
        body: '<div id="c">不应解析</div>',
      );
      expect(_texts(blocks), <String>[' 卷简介 ']);
    });

    test('tag 为空时返回空块', () {
      final source = _source(content: <String, dynamic>{'content': '#c@html'});
      final chapter = _chapter('第3卷 风起7')
        ..title = '第3卷 风起'
        ..isVolume = true;
      final blocks = BookContent.analyzeContent(
        bookSource: source,
        book: _book('https://src.test/book/1.html'),
        bookChapter: chapter,
        baseUrl: 'https://src.test/toc.html',
        redirectUrl: 'https://src.test/toc.html',
        body: '<div id="c">不应解析</div>',
      );
      expect(blocks, isEmpty);
    });

    test('普通章节不受影响', () {
      final source = _source(content: <String, dynamic>{'content': '#c@html'});
      final chapter = _chapter('https://src.test/c/1.html')..title = '第1章';
      final blocks = BookContent.analyzeContent(
        bookSource: source,
        book: _book('https://src.test/book/1.html'),
        bookChapter: chapter,
        baseUrl: 'https://src.test/c/1.html',
        redirectUrl: 'https://src.test/c/1.html',
        body: '<div id="c">正文</div>',
      );
      expect(_texts(blocks), <String>['　　正文']);
    });
  });

  group('AnalyzeUrl XML 响应补声明', () {
    late HttpServer server;

    Future<HttpServer> start() async {
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      s.listen((req) {
        final path = req.uri.path;
        final body = <String, String>{
          '/xml': '<root><item/></root>',
          '/decl': '<?xml version="1.0"?><root/>',
          '/html': '<root/>',
        }[path];
        final type = <String, String>{
          '/xml': 'text/xml; charset=utf-8',
          '/decl': 'application/xml',
          '/html': 'text/html',
        }[path];
        req.response
          ..statusCode = body == null ? 404 : 200
          ..headers.set(HttpHeaders.contentTypeHeader, type ?? 'text/plain')
          ..write(body ?? '');
        req.response.close();
      });
      return s;
    }

    String origin() =>
        'http://${server.address.address}:${server.port}';

    tearDown(() => server.close(force: true));

    test('XML 无声明补全，已有声明与非 XML 不动', () async {
      server = await start();
      final base = origin();
      final noDecl = AnalyzeUrl(url: '$base/xml', baseUrl: base);
      expect(await noDecl.getStrResponse(),
          '<?xml version="1.0"?><root><item/></root>');
      final hasDecl = AnalyzeUrl(url: '$base/decl', baseUrl: base);
      expect(await hasDecl.getStrResponse(),
          '<?xml version="1.0"?><root/>');
      final htmlType = AnalyzeUrl(url: '$base/html', baseUrl: base);
      expect(await htmlType.getStrResponse(), '<root/>');
    });
  });

  group('字段保真', () {
    test('ExploreRule.pageParam fromJson/toJson 往返', () {
      final rule = ExploreRule.fromJson(<String, dynamic>{
        'bookList': '#list li',
        'pageParam': 'pageNo',
      });
      expect(rule.pageParam, 'pageNo');
      expect(rule.toJson()['pageParam'], 'pageNo');

      final source = XiaoshuoBookSource.fromJson(<String, dynamic>{
        'bookSourceUrl': 'https://e.test',
        'bookSourceName': 'e',
        'bookSourceType': 0,
        'ruleExplore': <String, dynamic>{'pageParam': 'p'},
      });
      expect(source.ruleExplore!.pageParam, 'p');
      expect(
        (source.toJson()['ruleExplore'] as Map)['pageParam'],
        'p',
      );
    });

    test('_isShuyuanSource 与源能力判定同口径（Map<String, dynamic>）', () {
      final screen = File(
        'lib/core/widgets/online_content_list_screen.dart',
      ).readAsStringSync();
      expect(screen, contains("xiaoshuo is Map<String, dynamic>"));
      final registry =
          File('lib/core/models/plugin_config.dart').readAsStringSync();
      expect(registry, contains("selectors?['xiaoshuo'] is Map<String, dynamic>"));
    });
  });
}
