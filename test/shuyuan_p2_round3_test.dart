/// 第三轮 P2（N8–N17）回归：
/// N8 legado isTrue 口径、N9 webView 真值范围、N10 retry 宽容解析、
/// N11 UTF-8 BOM 剥离、N13 dnsIp 指定 IP 建连、N16 formatJs 实体字段回写、
/// N15 登录 UI RowUi 行类型。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexhub/core/models/novel_block.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_url.dart';
import 'package:nexhub/features/shuyuan/analyze/image_decoder.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book_chapter.dart';
import 'package:nexhub/features/shuyuan/presentation/shuyuan_login_dialog.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';
import 'package:nexhub/features/shuyuan/web_book/book_chapter_list.dart';
import 'package:nexhub/features/shuyuan/web_book/book_content.dart';

Future<HttpServer> _startServer(
    Future<void> Function(HttpRequest req) handler) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(handler);
  return server;
}

String _origin(HttpServer server) =>
    'http://${server.address.address}:${server.port}';

XiaoshuoBookSource _source(Map<String, dynamic> toc) {
  return XiaoshuoBookSource.fromJson(<String, dynamic>{
    'bookSourceUrl': 'https://p2.test',
    'bookSourceName': 'p2-test',
    'bookSourceType': 0,
    'ruleToc': toc,
  });
}

XiaoshuoBook _book(String bookUrl) =>
    XiaoshuoBook(bookUrl: bookUrl, name: '测试书');

AnalyzeUrl _url(String url) => AnalyzeUrl(url: url);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ShuyuanSourceContext.resetForTest();
  });

  group('N8 isTrue 口径', () {
    final source = _source(<String, dynamic>{
      'chapterList': '#list .vol, #list a',
      'chapterName': 'text',
      'chapterUrl': '@href',
      'isVolume': '@data-v',
      'isVip': '@data-vip',
      'isPay': '@data-pay',
    });
    const html = '''
<div id="list">
  <span class="vol" data-v="yes">第一卷</span>
  <a href="/b/1.html" data-vip=" true " data-pay="是">第1章</a>
  <a href="/b/2.html" data-vip="no" data-pay="0.0">第2章</a>
  <a href="/b/3.html" data-vip="vip">第3章</a>
</div>''';

    test('yes/带空白/是/vip 为真，no/0.0 为假', () {
      final chapters = BookChapterList.analyzeChapterList(
        bookSource: source,
        book: _book('https://p2.test/book/'),
        baseUrl: 'https://p2.test/book/',
        redirectUrl: 'https://p2.test/book/',
        body: html,
      );
      expect(chapters.length, 4);
      expect(chapters[0].isVolume, isTrue, reason: '"yes" 应为卷');
      expect(chapters[1].isVip, isTrue, reason: '" true " 应为 VIP');
      expect(chapters[1].isPay, isTrue, reason: '"是" 应为付费');
      expect(chapters[2].isVip, isFalse, reason: '"no" 非 VIP');
      expect(chapters[2].isPay, isFalse, reason: '"0.0" 非付费');
      expect(chapters[3].isVip, isTrue, reason: '"vip" 应为 VIP');
    });
  });

  group('N9 webView 真值范围', () {
    test('webView:1 / "1" / "yes" 为真', () {
      expect(_url('https://t.test/list,{"webView":1}').useWebView, isTrue);
      expect(_url('https://t.test/list,{"webView":"1"}').useWebView, isTrue);
      expect(_url('https://t.test/list,{"webView":"yes"}').useWebView, isTrue);
    });

    test('webView:false / "false" / "" 为假', () {
      expect(_url('https://t.test/list,{"webView":false}').useWebView, isFalse);
      expect(
          _url('https://t.test/list,{"webView":"false"}').useWebView, isFalse);
      expect(_url('https://t.test/list,{"webView":""}').useWebView, isFalse);
      expect(_url('https://t.test/list').useWebView, isFalse);
    });
  });

  group('N10 retry 宽容解析', () {
    test('字符串数字解析为重试次数，不再抛 TypeError', () {
      expect(_url('https://t.test/list,{"retry":"3"}').retry, 3);
      expect(_url('https://t.test/list,{"retry":2}').retry, 2);
    });

    test('非数字/空值回落 0', () {
      expect(_url('https://t.test/list,{"retry":"abc"}').retry, 0);
      expect(_url('https://t.test/list,{"retry":""}').retry, 0);
      expect(_url('https://t.test/list').retry, 0);
    });
  });

  group('N11 UTF-8 BOM 剥离', () {
    test('BOM 先剥离再按 charset 解码（legado removeUTF8BOM）', () async {
      final server = await _startServer((req) async {
        req.response.headers.contentType =
            ContentType('text', 'html', charset: 'gbk');
        req.response.add(<int>[0xEF, 0xBB, 0xBF]);
        req.response.add(gbk.encode('你好'));
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));
      final body =
          await AnalyzeUrl(url: '${_origin(server)}/bom').getStrResponse();
      expect(body, '你好', reason: 'BOM 字节不得进入 GBK 解码结果');
    });
  });

  group('N13 dnsIp 指定 IP 建连', () {
    test('不可解析域名按 dnsIp 建连，Host 头保持原域名', () async {
      var seenHost = '';
      final server = await _startServer((req) async {
        seenHost = req.headers.value('host') ?? '';
        req.response
          ..headers.contentType = ContentType.html
          ..write('<html><body><div id="ok">命中</div></body></html>');
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));
      final port = server.port;
      final url = 'http://p2-dns-unresolvable.test:$port/page,'
          '{"dnsIp":"127.0.0.1"}';
      final ctx = ShuyuanSourceContext('p2-dns');
      final body = await ShuyuanSourceContext.run(
          ctx, () => AnalyzeUrl(url: url).getStrResponse());
      expect(body, contains('命中'));
      expect(seenHost, 'p2-dns-unresolvable.test:$port');
    });
  });

  group('N17 ruleReview / homepageModules 透传', () {
    final json = <String, dynamic>{
      'bookSourceUrl': 'https://p2.test',
      'bookSourceName': 'p2-n17',
      'ruleToc': <String, dynamic>{'chapterList': '#list a'},
      'ruleReview': <String, dynamic>{
        'reviewUrl': '@href',
        'reviewList': '.comment',
      },
      'homepageModules':
          '[{"key":"banner","type":"banner","title":"推荐"}]',
    };

    test('XiaoshuoBookSource fromJson/toJson 往返保留', () {
      // 动态访问：字段未建模时以 NoSuchMethod 失败（RED），建模后按实名生效。
      final src = XiaoshuoBookSource.fromJson(json) as dynamic;
      expect(src.ruleReview, isNotNull);
      expect((src.ruleReview as Map)['reviewUrl'], '@href');
      expect(src.homepageModules, contains('"type":"banner"'));
      final out = (src as XiaoshuoBookSource).toJson();
      expect(out['ruleReview'], isA<Map<String, dynamic>>());
      expect((out['ruleReview'] as Map<String, dynamic>)['reviewList'],
          '.comment');
      expect(out['homepageModules'],
          '[{"key":"banner","type":"banner","title":"推荐"}]');
    });

    test('ShuyuanSource 导入/导出/toBookSource 均保留', () {
      final parsed = ShuyuanSource.fromJson(json) as dynamic;
      expect(parsed.ruleReview, isNotNull);
      expect(parsed.homepageModules, contains('banner'));
      final exported = (parsed as ShuyuanSource).toJson();
      expect(exported['ruleReview'], isNotNull);
      expect(exported['homepageModules'], contains('banner'));
      final model = (parsed).toBookSource() as dynamic;
      expect(model.ruleReview, isNotNull);
      expect(model.homepageModules, contains('banner'));
    });
  });

  group('N16 formatJs 实体字段回写', () {
    test('chapter.url/tag/baseUrl/isVip/isPay/index/卷 直改落回宿主', () {
      final chapter = XiaoshuoBookChapter(
        bookUrl: 'https://p2.test/book/1',
        url: '/old/1.html',
        title: '第一章',
        baseUrl: 'https://p2.test/old/',
      );
      // legado 绑定的是 BookChapter 实体：脚本直改字段必须持久化。
      BookChapterList.applyFormatJs([chapter], '''
        chapter.url = '/new/1.html';
        chapter.tag = '最新';
        chapter.baseUrl = 'https://p2.test/new/';
        chapter.isVip = true;
        chapter.isPay = true;
        chapter.isVolume = true;
        chapter.index = 9;
        void 0;
      ''');
      expect(chapter.url, '/new/1.html');
      expect(chapter.tag, '最新');
      expect(chapter.baseUrl, 'https://p2.test/new/');
      expect(chapter.isVip, isTrue);
      expect(chapter.isPay, isTrue);
      expect(chapter.isVolume, isTrue);
      expect(chapter.index, 9);
      expect(chapter.title, '第一章', reason: '未改标题不应变化');
    });

    test('chapter.title 直改生效，脚本返回值最后覆盖标题', () {
      final a = XiaoshuoBookChapter(bookUrl: '', url: '/1', title: '甲');
      final b = XiaoshuoBookChapter(bookUrl: '', url: '/2', title: '乙');
      BookChapterList.applyFormatJs([a, b],
          "(title === '甲') ? (chapter.title = '脚本甲', null) "
          ": (chapter.title = '脚本乙', '返回乙')");
      expect(a.title, '脚本甲');
      expect(b.title, '返回乙', reason: '返回值优先于脚本内直改');
    });

    test('未修改字段不被回读弄脏（baseUrl/tag 保持 null）', () {
      final chapter = XiaoshuoBookChapter(bookUrl: '', url: '/1', title: '甲');
      BookChapterList.applyFormatJs([chapter], 'null');
      expect(chapter.baseUrl, isNull);
      expect(chapter.tag, isNull);
      expect(chapter.url, '/1');
      expect(chapter.title, '甲');
    });
  });

  group('N12 imageDecode 字节解密语义', () {
    PluginConfig config({String? imageDecode}) =>
        ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(<String, dynamic>{
          'bookSourceUrl': 'https://p2-img.test/',
          'bookSourceName': 'p2-img',
          'bookSourceType': 0,
          'ruleContent': <String, dynamic>{
            'content': '#content',
            if (imageDecode != null) 'imageDecode': imageDecode,
          },
        }));

    tearDown(() {
      ShuyuanImageDecodeHooks.coverResolver = null;
      ShuyuanImageDecodeHooks.contentResolver = null;
      ShuyuanImageDecodeHooks.contentApplies = null;
    });

    test('绑定 result 字节数组，返回值按字节还原', () {
      // legado ImageUtils.decode：result 是图片 bytes，脚本返回解密后 bytes。
      final cfg = config(
          imageDecode: 'var out = [];'
              'for (var i = 0; i < result.length; i++) out.push(result[i] ^ 255);'
              'out');
      final decoded = ShuyuanImageDecoder.decodeContent(
          cfg, 'https://p2-img.test/a.jpg', Uint8List.fromList(<int>[0, 1, 254]));
      expect(decoded, Uint8List.fromList(<int>[255, 254, 1]));
    });

    test('未声明规则原样返回；返回非字节按失败处理', () {
      final bytes = Uint8List.fromList(<int>[1, 2, 3]);
      final plain = config();
      expect(ShuyuanImageDecoder.decodeContent(plain, 'u', bytes), same(bytes));
      // legado `as ByteArray` 失败 → 解码失败（不把字符串当 URL 使用）。
      final bad = config(imageDecode: "'https://rewritten.test/x.jpg'");
      expect(ShuyuanImageDecoder.decodeContent(bad, 'u', bytes), isNull);
    });

    test('register 后 core 钩子可用且按源声明门控', () {
      ShuyuanImageDecoder.register();
      expect(ShuyuanImageDecodeHooks.coverResolver, isNotNull);
      expect(ShuyuanImageDecodeHooks.contentResolver, isNotNull);
      expect(ShuyuanImageDecodeHooks.contentApplies?.call(config()), isFalse);
      expect(
          ShuyuanImageDecodeHooks.contentApplies
              ?.call(config(imageDecode: 'result')),
          isTrue);
    });

    test('正文解析阶段不再把 imageDecode 当 URL 改写器', () {
      final source = ShuyuanSource.fromJson(<String, dynamic>{
        'bookSourceUrl': 'https://p2-img.test/',
        'bookSourceName': 'p2-img',
        'bookSourceType': 0,
        'ruleContent': <String, dynamic>{
          'content': '#c@html',
          'imageDecode': "'https://rewritten.test/x.jpg'",
        },
      }).toBookSource();
      final blocks = BookContent.analyzeContent(
        bookSource: source,
        book: _book('https://p2-img.test/book/1.html'),
        bookChapter: XiaoshuoBookChapter(
            bookUrl: 'https://p2-img.test/book/1.html',
            url: 'https://p2-img.test/c/1.html',
            title: '第1章'),
        baseUrl: 'https://p2-img.test/c/1.html',
        redirectUrl: 'https://p2-img.test/c/1.html',
        body: '<div id="c">文字<img src="https://cdn.test/a.jpg"></div>',
      );
      final images = blocks.whereType<NovelImageBlock>().toList();
      expect(images.single.url, 'https://cdn.test/a.jpg');
    });
  });

  group('N14 ajaxAll 并发与 skipRateLimit', () {
    final inFlight = <int>[0];
    final maxInFlight = <int>[0];

    XiaoshuoBookSource source(String rate) =>
        XiaoshuoBookSource.fromJson(<String, dynamic>{
          'bookSourceUrl': 'https://p2-ajax.test',
          'bookSourceName': 'p2-ajax',
          'bookSourceType': 0,
          'concurrentRate': rate,
          'ruleToc': <String, dynamic>{'chapterList': '#list a'},
        });

    Future<HttpServer> slowServer() => _startServer((req) async {
          inFlight[0]++;
          if (inFlight[0] > maxInFlight[0]) maxInFlight[0] = inFlight[0];
          try {
            await Future<void>.delayed(const Duration(milliseconds: 1200));
            req.response
              ..headers.contentType = ContentType.html
              ..write('B:${req.uri.path}');
            await req.response.close();
          } finally {
            inFlight[0]--;
          }
        });

    // 宿主 HttpFetcher 有 800ms 同 host 最小间隔（全局防封节流）；
    // 预热一次把上一测试残留的间隔耗掉，测量段从干净窗口开始。
    Future<void> warmUp(String origin, XiaoshuoBookSource src) async {
      await AnalyzeUrl(
        url: '$origin/warmup',
        baseUrl: src.bookSourceUrl,
        source: src,
        skipRateLimit: true,
      ).getStrResponse();
    }

    test('ajaxAll 并发抓取（保序），skipRateLimit 绕过 concurrentRate', () async {
      inFlight[0] = 0;
      maxInFlight[0] = 0;
      final server = await slowServer();
      addTearDown(() => server.close(force: true));
      final origin = _origin(server);
      // 1200ms 处理 > 800ms host 间隔 → 并发时两请求在途重叠。
      final src = source('3000');
      await warmUp(origin, src);
      final ctx = ShuyuanSourceContext('p2-ajax-skip');
      ctx.bindSource(src);
      ShuyuanSourceContext.run(ctx, () {
        JsEngine.forSource('p2-ajax-skip').eval(
            "java.ajaxAll(['$origin/a', '$origin/b'], true); 'ok'");
      });
      expect(ctx.ajaxPending.length, 2);
      final sw = Stopwatch()..start();
      await ShuyuanSourceContext.settleAjax(ctx, src);
      sw.stop();
      // 并发+跳限流 ≈ 800+1200=2000ms；不跳限流 ≈ 3000+1200=4200ms。
      expect(maxInFlight[0], greaterThanOrEqualTo(2),
          reason: 'ajaxAll 应并发抓取（两请求在途重叠）');
      expect(sw.elapsedMilliseconds, lessThan(3000),
          reason: 'skipRateLimit 应绕过 concurrentRate 的 3000ms 窗口');
      // ajaxAll 返回数组按下标保序，缓存按各自 URL 命中。
      expect(ctx.ajaxCache['$origin/a'], 'B:/a');
      expect(ctx.ajaxCache['$origin/b'], 'B:/b');
    });

    test('未 skip 时 concurrentRate 仍生效', () async {
      inFlight[0] = 0;
      maxInFlight[0] = 0;
      final server = await slowServer();
      addTearDown(() => server.close(force: true));
      final origin = _origin(server);
      final src = source('3000');
      await warmUp(origin, src);
      final ctx = ShuyuanSourceContext('p2-ajax-gate');
      ctx.bindSource(src);
      ShuyuanSourceContext.run(ctx, () {
        JsEngine.forSource('p2-ajax-gate').eval(
            "java.ajaxAll(['$origin/c', '$origin/d']); 'ok'");
      });
      final sw = Stopwatch()..start();
      await ShuyuanSourceContext.settleAjax(ctx, src);
      sw.stop();
      // 未 skip 的批请求：第二个被 3000ms 窗口扣住 → 总耗时 ≈ 4200ms。
      expect(sw.elapsedMilliseconds, greaterThan(3200),
          reason: '并发不等于跳限流：未 skip 的批请求仍受 concurrentRate 约束');
      expect(ctx.ajaxCache['$origin/c'], 'B:/c');
      expect(ctx.ajaxCache['$origin/d'], 'B:/d');
    });
  });

  group('N15 登录 UI RowUi 行类型', () {
    List<Map<String, dynamic>> loginUiRows() => <Map<String, dynamic>>[
          <String, dynamic>{
            'name': '线路',
            'type': 'select',
            'chars': <String>['A', 'B', 'C'],
            'action': 'java.ajax("https://x.test/line")',
          },
          <String, dynamic>{
            'name': '记住',
            'type': 'toggle',
            'chars': <String>['☑', '☐'],
            'default': '☐',
          },
          <String, dynamic>{
            'name': '账号',
            'type': 'password',
            'default': 'def-u',
          },
          <String, dynamic>{'name': '发送验证码', 'type': 'button'},
        ];

    test('行解析与 toggle/select 默认值（legado buildForm 口径）', () {
      final rows = shuyuanLoginRows(loginUiRows());
      expect(rows.map((r) => r.type).toList(),
          <String>['select', 'toggle', 'password', 'button']);
      expect(rows.first.chars, <String>['A', 'B', 'C']);
      expect(rows.first.action, contains('/line'));

      final values = shuyuanLoginRowDefaults(rows, <String, String>{'账号': 'saved'});
      expect(values['线路'], 'A', reason: 'toggle/select 空值：default 缺省取 chars.first');
      expect(values['记住'], '☐', reason: 'default 优先于 chars.first');
      expect(values['账号'], 'saved', reason: '已保存值优先于 default');
      expect(values.containsKey('发送验证码'), isFalse, reason: 'button 不产值');
      // 已存在非空值时不被默认值覆盖。
      final kept = shuyuanLoginRowDefaults(rows, <String, String>{'线路': 'C'});
      expect(kept['线路'], 'C');
    });

    test('viewName 单引号字面量与脚本求值（空结果回落 name）', () {
      final literal = ShuyuanLoginRow(
          name: 'k', type: 'text', viewName: "'手机号'");
      expect(shuyuanLoginRowTitle(literal, (_) => '不应求值'), '手机号');
      final script =
          ShuyuanLoginRow(name: 'k', type: 'text', viewName: 'result.user');
      expect(shuyuanLoginRowTitle(script, (_) => '用户'), '用户');
      expect(shuyuanLoginRowTitle(script, (_) => ''), 'k');
      expect(shuyuanLoginRowTitle(script, null), 'k');
      final plain = ShuyuanLoginRow(name: '账号', type: 'text');
      expect(shuyuanLoginRowTitle(plain, (_) => 'x'), '账号');
    });

    test('toggle 按 chars 循环（含未匹配值回落到首项）', () {
      expect(shuyuanLoginToggleNext('☑', <String>['☑', '☐']), '☐');
      expect(shuyuanLoginToggleNext('☐', <String>['☑', '☐']), '☑');
      expect(shuyuanLoginToggleNext('', <String>['1', '2']), '1');
      expect(shuyuanLoginToggleNext('x', <String>['1', '2']), '1');
    });

    testWidgets('表单渲染 text/password/toggle/select/button 并回写值', (tester) async {
      final rows = shuyuanLoginRows(loginUiRows());
      final values = shuyuanLoginRowDefaults(rows, <String, String>{});
      final acted = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ShuyuanLoginForm(
            rows: rows,
            values: values,
            onAction: (row) async => acted.add(row.name),
          ),
        ),
      ));

      // text/password：密码行 obscureText，输入写回 values。
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).obscureText,
          isTrue);
      await tester.enterText(find.byType(TextField), 'u2');
      expect(values['账号'], 'u2');

      // toggle：点击在 chars 间循环并触发 action。
      expect(find.text('☐记住'), findsOneWidget);
      await tester.tap(find.text('☐记住'));
      await tester.pump();
      expect(values['记住'], '☑');
      expect(find.text('☑记住'), findsOneWidget);
      expect(acted, contains('记住'));

      // select：点开菜单选 B，回写并触发 action。
      expect(find.textContaining('线路'), findsOneWidget);
      await tester.tap(find.textContaining('线路'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('B').last);
      await tester.pumpAndSettle();
      expect(values['线路'], 'B');
      expect(acted, contains('线路'));

      // button：点击触发 action。
      await tester.tap(find.text('发送验证码'));
      await tester.pump();
      expect(acted, contains('发送验证码'));
    });

    test('行 action 脚本带 result 绑定并经 mini-settle 发真实请求', () async {
      final hits = <String>[];
      final server = await _startServer((req) async {
        hits.add(req.uri.toString());
        req.response
          ..headers.contentType = ContentType.html
          ..write('ok');
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));
      final origin = _origin(server);

      final shuyuanJson = <String, dynamic>{
        'bookSourceUrl': 'https://p2-login.test',
        'bookSourceName': 'p2-login',
        'bookSourceType': 0,
        'ruleToc': <String, dynamic>{'chapterList': '#list a'},
      };
      final bookSource =
          ShuyuanSource.fromJson(shuyuanJson).toBookSource();
      final cfg = ShuyuanAdapter.toPluginConfig(
          ShuyuanSource.fromJson(shuyuanJson));
      final ctx = ShuyuanSourceContext('p2-login-act');
      ctx.bindSource(bookSource);
      final engine = JsEngine.forSource('p2-login-act');
      final row = ShuyuanLoginRow(
        name: '发送验证码',
        type: 'button',
        action: "java.ajax('$origin/act?u=' + result.user);",
      );
      final ok = await evalShuyuanLoginScript(
        ctx,
        engine,
        bookSource,
        cfg,
        "var helper = 'h';\n${row.action}",
        bindings: <String, dynamic>{
          'result': <String, String>{'user': 'u1'},
          'isLongClick': false,
        },
      );
      expect(ok, isTrue);
      expect(hits, contains('/act?u=u1'),
          reason: 'action 脚本应能读 result 绑定并发起真实请求');
    });
  });
}
