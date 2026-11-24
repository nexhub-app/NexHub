/// 对等扫描 P2（A3/A4/A5/A6/A7/A8/B3/B4/B5/B6/B7/C3/C4/C9/C10/C11/D4/
/// E5/E6/E7/E8/F2/F3/F4）回归：
/// - A3 `java.ruleUrl` 在 URL 模板求值期可见；
/// - A4 重定向不改写 `url` 字段；A5 非 2xx 也按 retry 重发；
/// - A7 参数编码只生成 `encodedQuery`/`encodedForm`，不改写 url/body；
/// - B3 `@put` 走 chapter→book 链且不改章节标题；B4 空规则段不执行解析器；
/// - B5 `##` 替换支持 `$N`（多位）与 `${name}`；B6 `##rule##` 走引擎语义；
/// - B7 数字实体可缺分号；C3 详情无条件覆盖 tocUrl；
/// - C4/C9 文件/音频判据走 BookType 位语义；C10 `pageParam` 接线；
/// - C11 发现分类脚本失败生成 ERROR 条目；D4 搜索变量按条目隔离；
/// - E5/E6/E7/E8 java/cookie/source/book 方法面；F2/F3/F4 模型字段。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexhub/features/shuyuan/analyze/analyze_rule.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_url.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';
import 'package:nexhub/features/shuyuan/model/search_book.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book_chapter.dart';
import 'package:nexhub/features/shuyuan/web_book/book_content.dart';
import 'package:nexhub/features/shuyuan/web_book/book_info.dart';
import 'package:nexhub/features/shuyuan/web_book/web_book.dart';

XiaoshuoBookSource _source({
  Map<String, dynamic>? info,
  Map<String, dynamic>? explore,
  int type = 0,
}) {
  return XiaoshuoBookSource.fromJson(<String, dynamic>{
    'bookSourceUrl': 'https://src.test',
    'bookSourceName': 'p2-round5-test',
    'bookSourceType': type,
    if (info != null) 'ruleBookInfo': info,
    if (explore != null) 'ruleExplore': explore,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  group('A3 java.ruleUrl 在 URL 模板求值期可见', () {
    test('{{java.ruleUrl}} 读到的是模板本身而非空串', () {
      final au = AnalyzeUrl(
        url: 'https://a.test/p?u={{java.ruleUrl.indexOf("a.test")}}',
        baseUrl: 'https://a.test',
      );
      // 旧实现此时 ruleUrl 尚未赋值 → indexOf 返回 -1。
      expect(au.url, 'https://a.test/p?u=8');
    });

    test('ruleUrl 字段是模板展开、选项剥离前的形态', () {
      final au = AnalyzeUrl(
        url: 'https://a.test/s?wd=x,{"method":"POST"}',
        baseUrl: 'https://a.test',
      );
      expect(au.ruleUrl, contains('{"method":"POST"}'));
      expect(au.url, isNot(contains('"method"')));
    });
  });

  group('A7 参数编码只生成派生值', () {
    test('GET query 按 charset 编码，url 字段保持原文', () {
      final au = AnalyzeUrl(
        url: 'https://a.test/s?wd=中文,{"charset":"gbk"}',
        baseUrl: 'https://a.test',
      );
      expect(au.url, contains('中文'));
      expect(au.urlNoQuery, 'https://a.test/s');
      expect(au.encodedQuery, 'wd=%D6%D0%CE%C4');
    });

    test('POST form 生成 encodedForm，body 保持原文', () {
      final au = AnalyzeUrl(
        url: 'https://a.test/api,{"method":"POST","body":"wd=中文"}',
        baseUrl: 'https://a.test',
      );
      expect(au.body, 'wd=中文');
      expect(au.encodedForm, 'wd=%E4%B8%AD%E6%96%87');
      expect(au.urlNoQuery, 'https://a.test/api');
    });
  });

  group('A4/A5 重定向与非 2xx 重试', () {
    late HttpServer server;
    late int hits500;

    setUp(() async {
      hits500 = 0;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        final path = req.uri.path;
        if (path == '/redir') {
          req.response
            ..statusCode = 302
            ..headers.set(HttpHeaders.locationHeader, '/final');
          req.response.close();
          return;
        }
        if (path == '/boom') {
          hits500++;
          req.response
            ..statusCode = 500
            ..headers.contentType = ContentType.html
            ..write('<html><body>server error page</body></html>');
          req.response.close();
          return;
        }
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write('<html><body>final page</body></html>');
        req.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('302 后 url 字段不变，最终地址在 lastFinalUrl', () async {
      final base = 'http://127.0.0.1:${server.port}';
      final au = AnalyzeUrl(url: '$base/redir', baseUrl: base);
      final body = await au.getStrResponse();
      expect(body, contains('final page'));
      expect(au.url, '$base/redir');
      expect(au.lastFinalUrl, '$base/final');
    });

    test('retry>0 时 500 也会重发，最终返回最后一次响应体', () async {
      final base = 'http://127.0.0.1:${server.port}';
      final au = AnalyzeUrl(
        url: '$base/boom,{"retry":1}',
        baseUrl: base,
      );
      final body = await au.getStrResponse();
      expect(body, contains('server error page'));
      expect(hits500, 2);
    });
  });

  group('B3 @put 链与章节标题', () {
    test('@put:{title:...} 只写章节变量，不改章节标题', () {
      final book = XiaoshuoBook(bookUrl: 'https://src.test/b1', name: '书');
      final chapter = XiaoshuoBookChapter(
        bookUrl: 'https://src.test/b1',
        url: 'https://src.test/c1',
        title: '原标题',
      );
      final rule = AnalyzeRule(book: book, chapter: chapter)
        ..setContent('<p class="t">中间变量</p>');
      // put 的值本身是规则（legado putRule：put(key, getString(value))）。
      rule.getString('@put:{title:".t"}');
      expect(chapter.title, '原标题');
      expect(chapter.variableMap['title'], '中间变量');
      // get('title') 优先章节标题（legado 同口径）。
      expect(rule.get('title'), '原标题');
    });

    test('无 chapter 时写入 book 变量表（可被 @get 读回）', () {
      final book = XiaoshuoBook(bookUrl: '', name: '');
      final rule = AnalyzeRule(book: book)..setContent('<p class="t">42</p>');
      rule.getString('@put:{gid:".t"}');
      expect(book.variableMap['gid'], '42');
      expect(rule.get('gid'), '42');
    });
  });

  group('B4 getStringList 空规则段', () {
    test('只有 @put 的规则段不执行解析器，保留上一步结果', () {
      final rule = AnalyzeRule()..setContent('<p class="t">v</p>');
      final out = rule.getStringList('@put:{k:".t"}');
      // 空规则段跳过解析器 → 结果仍是原内容（旧实现对空规则跑了一次
      // 解析器，得到空列表）。
      expect(out, <String>['<p class="t">v</p>']);
      expect(rule.get('k'), 'v');
    });
  });

  group('B5 ## 替换分组展开', () {
    test(r'$10 取第 10 组（多位组号）', () {
      final rule = AnalyzeRule()..setContent('abcdefghij');
      final out = rule.getString(r'##(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)##$10##');
      expect(out, 'j');
    });

    test(r'${name} 命名分组与 \$ 转义', () {
      final rule = AnalyzeRule()..setContent('价格123元');
      // 3 段形态（无第 4 段）→ 整章替换，保留命中之外的文本。
      final out = rule.getString(r'##(?<num>\d+)##[${num}]');
      expect(out, '价格[123]元');
      final escaped = AnalyzeRule().getString(r'##x##\$1##' , mContent: 'x');
      expect(escaped, r'$1');
    });

    test('组号超出时回退到可命中的更短组号', () {
      final rule = AnalyzeRule()..setContent('ab');
      final out = rule.getString(r'##(a)(b)##$13##');
      expect(out, 'a');
    });
  });

  group('B6 replaceRegex 走 SourceRule 语义', () {
    test('##pattern##replacement 整章替换全部命中', () {
      final out = BookContent.applyReplaceRules('a1\nb2', r'##(\d)##x');
      expect(out, 'ax\nbx');
    });

    test('第 4 段（##pattern##replacement##）只保留首个命中的替换结果', () {
      final out = BookContent.applyReplaceRules('a1\nb2', r'##(\d)##x##');
      expect(out, 'x');
    });

    test('多行规则逐行应用（NexHub 扩展）', () {
      final out = BookContent.applyReplaceRules('a\nb', '##a##A\n##b##B');
      expect(out, 'A\nB');
    });

    test('裸正则按「删除命中」处理（内置源在用）', () {
      final out = BookContent.applyReplaceRules('正文\n广告行\n更多正文', r'^广告.*$');
      expect(out, '正文\n\n更多正文');
    });
  });

  group('B7 数字实体缺分号', () {
    test('&#65 与 &#x1F600; 都能还原', () {
      expect(AnalyzeRule.unescapeHtml('&#65&#66'), 'AB');
      expect(AnalyzeRule.unescapeHtml('&#x1F600;'), '😀');
      expect(AnalyzeRule.unescapeHtml('&amp;'), '&');
    });

    test('&#123abc 不当实体处理', () {
      expect(AnalyzeRule.unescapeHtml('&#123abc'), '&#123abc');
    });
  });

  group('C3 详情无条件覆盖 tocUrl', () {
    test('tocUrl 规则为空 → 覆盖为 baseUrl（不保留搜索旧值）', () {
      final book = XiaoshuoBook(bookUrl: 'https://detail.test/b/1', name: '')
        ..tocUrl = 'https://old.test/wrong-toc';
      BookInfo.analyzeBookInfo(
        bookSource: _source(info: <String, dynamic>{'init': ''}),
        book: book,
        baseUrl: 'https://detail.test/b/1',
        redirectUrl: 'https://detail.test/b/1',
        body: '<html><body><h1>书名</h1></body></html>',
      );
      expect(book.tocUrl, 'https://detail.test/b/1');
      expect(book.tocHtml, isNotNull);
    });
  });

  group('C4/C9 类型判据走 BookType 位语义', () {
    test('isWebFileBook 兼容编号 3 与 webFile 位 128', () {
      expect((XiaoshuoBook(bookUrl: 'u', name: '')..type = 3).isWebFileBook,
          isTrue);
      expect((XiaoshuoBook(bookUrl: 'u', name: '')..type = 128).isWebFileBook,
          isTrue);
      expect(
          (XiaoshuoBook(bookUrl: 'u', name: '')..type = 8 + 128).isWebFileBook,
          isTrue);
      expect((XiaoshuoBook(bookUrl: 'u', name: '')..type = 0).isWebFileBook,
          isFalse);
    });

    test('isAudioBook 兼容编号 1 与 audio 位 32', () {
      expect((XiaoshuoBook(bookUrl: 'u', name: '')..type = 1).isAudioBook,
          isTrue);
      expect((XiaoshuoBook(bookUrl: 'u', name: '')..type = 32).isAudioBook,
          isTrue);
      expect((XiaoshuoBook(bookUrl: 'u', name: '')..type = 0).isAudioBook,
          isFalse);
    });
  });

  group('C10 ExploreRule.pageParam 接线', () {
    test('分类地址不带页码规则时按 pageParam 追加', () {
      final src = _source(explore: <String, dynamic>{
        'bookList': 'body',
        'pageParam': 'p',
      });
      expect(WebBook.withPageParam(src, 'https://a.test/list?type=1', 3),
          'https://a.test/list?type=1&p=3');
      expect(WebBook.withPageParam(src, 'https://a.test/list?p=1', 2),
          'https://a.test/list?p=2');
      // 第一页不改地址。
      expect(WebBook.withPageParam(src, 'https://a.test/list', 1),
          'https://a.test/list');
    });

    test('已带页码规则/选项串的地址不改写', () {
      final src = _source(explore: <String, dynamic>{'bookList': 'body'});
      expect(WebBook.withPageParam(src, 'https://a.test/l?page={{page}}', 2),
          'https://a.test/l?page={{page}}');
      expect(WebBook.withPageParam(src, 'https://a.test/l?page=<page>', 2),
          'https://a.test/l?page=<page>');
      expect(
          WebBook.withPageParam(src, 'https://a.test/l,{"method":"POST"}', 2),
          'https://a.test/l,{"method":"POST"}');
    });
  });

  group('C11 发现分类脚本失败生成 ERROR 条目', () {
    test('@js: 抛错时返回不可浏览的 ERROR 项', () {
      final src = XiaoshuoBookSource.fromJson(<String, dynamic>{
        'bookSourceUrl': 'https://src.test',
        'bookSourceName': 'p2-error',
        'exploreUrl': '@js:throw new Error("boom")',
      });
      final kinds = WebBook().getExploreKinds(src);
      expect(kinds, hasLength(1));
      expect(kinds.first.title, startsWith('ERROR:'));
      expect(kinds.first.isBrowsable, isFalse);
    });
  });

  group('D4 搜索变量按条目隔离', () {
    test('前一条 @put 不被后一条 @get 读到', () {
      final first = XiaoshuoBook(bookUrl: '', name: '');
      final rule = AnalyzeRule()..setContent('<p class="t">a</p>');
      rule.book = first;
      rule.getString('@put:{gid:".t"}');
      expect(rule.get('gid'), 'a');

      final second = XiaoshuoBook(bookUrl: '', name: '');
      rule.book = second;
      expect(rule.get('gid'), '');
    });
  });

  group('E5/E6/E7/E8 JS 方法面与属性面', () {
    String js(String code) => (AnalyzeRule()..setContent('')).getString('@js:$code');

    test('E5 java 归档/字体/配置方法名齐全', () {
      final out = js('['
          'typeof java.getZipByteArrayContent,'
          'typeof java.getRarByteArrayContent,'
          'typeof java.getRarStringContent,'
          'typeof java.get7zByteArrayContent,'
          'typeof java.get7zStringContent,'
          'typeof java.unArchiveFile,'
          'typeof java.queryBase64TTF,'
          'typeof java.getReadBookConfigMap,'
          'typeof java.getThemeConfigMap,'
          'typeof java.getThemeMode].join("|")');
      expect(out, 'function|function|function|function|function|function|'
          'function|function|function|function');
    });

    test('E5 配置 Map 可解析，主题模式缺省 day', () {
      final out = js('[JSON.parse(java.getReadBookConfigMap()).textSize,'
          'JSON.parse(java.getThemeConfigMap()).themeName,'
          'java.getThemeMode()].join("|")');
      expect(out, '20|MD3-Day|day');
    });

    test('E6 cookie replaceCookie/cookieToMap/mapToCookie/clear', () {
      final out = js(
          'cookie.setCookie("https://a.test/p", "a=1");'
          'cookie.replaceCookie("https://a.test/p", "b=2");'
          'var c1 = cookie.getCookie("https://a.test/p");'
          'var m = cookie.cookieToMap(c1);'
          'var s = cookie.mapToCookie(m);'
          'cookie.clear();'
          'var c2 = cookie.getCookie("https://a.test/p");'
          '[c1, m["a"], m["b"], s.indexOf("a=1") >= 0, c2].join("|")');
      expect(out, 'a=1; b=2|1|2|true|');
    });

    test('E7 source.getHeaderMap 与属性面存在', () {
      final out = js('[typeof source.getHeaderMap, typeof source, '
          'String(source.coverDecodeJs), String(source.concurrentRate), '
          'String(source.bookUrlPattern)].join("|")');
      expect(out, 'function|object|||');
    });

    test('E8 book.variable 读写落到变量表，durChapterIndex 可写', () {
      final out = js(
          'book.variable = JSON.stringify({gid: "9"});'
          'var g = book.getVariable("gid");'
          'book.durChapterIndex = 5;'
          '[g, book.durChapterIndex, typeof book.durChapterIndex,'
          'book.canUpdate, book.originName].join("|")');
      expect(out, '9|5|number|false|');
    });
  });

  group('F2/F3/F4 模型字段', () {
    test('XiaoshuoBook 新字段 JSON 往返', () {
      final book = XiaoshuoBook(bookUrl: 'https://a.test/b', name: '书')
        ..origin = 'https://src.test'
        ..originName = '源名'
        ..originOrder = 3
        ..fixedType = 8
        ..totalChapterNum = 120
        ..latestChapterTitle = '最新章'
        ..latestChapterTime = 1700000000000
        ..durChapterIndex = 4
        ..durChapterTitle = '第5章'
        ..durChapterPos = 10
        ..group = '分组'
        ..customTag = '标签'
        ..customIntro = '简介'
        ..customCoverUrl = 'https://a.test/c.jpg'
        ..canUpdate = false;
      final back = XiaoshuoBook.fromJson(book.toJson());
      expect(back.origin, 'https://src.test');
      expect(back.originName, '源名');
      expect(back.originOrder, 3);
      expect(back.fixedType, 8);
      expect(back.totalChapterNum, 120);
      expect(back.latestChapterTitle, '最新章');
      expect(back.latestChapterTime, 1700000000000);
      expect(back.durChapterIndex, 4);
      expect(back.durChapterTitle, '第5章');
      expect(back.durChapterPos, 10);
      expect(back.group, '分组');
      expect(back.customTag, '标签');
      expect(back.customIntro, '简介');
      expect(back.customCoverUrl, 'https://a.test/c.jpg');
      expect(back.canUpdate, isFalse);
    });

    test('XiaoshuoBookChapter 扩展字段 JSON 往返', () {
      final ch = XiaoshuoBookChapter(bookUrl: 'b', url: 'c', title: 't')
        ..tocLevel = 2
        ..resourceUrl = 'https://a.test/a.mp3'
        ..start = 1
        ..end = 9
        ..startFragmentId = 'sf'
        ..endFragmentId = 'ef';
      final back = XiaoshuoBookChapter.fromJson(ch.toJson());
      expect(back.tocLevel, 2);
      expect(back.resourceUrl, 'https://a.test/a.mp3');
      expect(back.start, 1);
      expect(back.end, 9);
      expect(back.startFragmentId, 'sf');
      expect(back.endFragmentId, 'ef');
    });

    test('SearchBook/XiaoshuoBook 的 updateTime 可承载列表更新时间', () {
      final sb = SearchBook(bookUrl: 'u', name: 'n');
      final book = sb.toBook()..updateTime = '2026-11-24';
      expect(book.updateTime, '2026-11-24');
      expect(XiaoshuoBook.fromJson(book.toJson()).updateTime, '2026-11-24');
    });
  });
}
