/// 漫画正文 java.ajax 多轮重放收敛回归（全合成源 + 本地 HTTP）。
///
/// 覆盖此前真实源暴露的链路：正文规则在 JS 内用 java.ajax 发 POST 分页循环，
/// 首轮返回占位符 → 重放轮次逐批取回并重算，直到图片列表收敛；同时
/// nextContentUrl 返回**下一章**地址时必须被同章分页闸门拦住（不抓下一章页）。
/// 不访问任何站点。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/presentation/shuyuan_novel_resolver.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';

class _ReqRecord {
  _ReqRecord(this.method, this.path, this.headers, this.body);
  final String method;
  final String path;
  final Map<String, String> headers;
  final String body;
}

/// 合成正文规则：从章节地址取 aid/cid，POST 分页拉图，拼 <img> 块。
String _contentRule(String base) => '''
@js:
(function() {
    var m = String(baseUrl).match(/\\/chapter\\/(\\d+)\\/(\\d+)\\.html/);
    if (!m) return '未匹配章节ID';
    var aid = m[1], cid = m[2];

    var api = '$base/api/pics';
    var hdrs = {
        'X-Requested-With': 'XMLHttpRequest',
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'Referer': String(baseUrl)
    };

    function fetchBatch(offset) {
        var body = 'id=' + cid + '&aid=' + aid + '&offset=' + offset + '&limit=5';
        var opts = { method: 'POST', body: body, headers: hdrs, charset: 'utf-8' };
        var resp = java.ajax(api + ',' + JSON.stringify(opts));
        if (resp && typeof resp.body === 'function') resp = resp.body();
        try {
            return JSON.parse(String(resp));
        } catch (e) {
            return null;
        }
    }

    var first = fetchBatch(0);
    if (!first || !first.data || !first.data.pic) {
        return '首屏解析失败';
    }
    var total = first.data.total || first.data.pic.length;
    var all = first.data.pic.slice();
    var offset = 5;
    while (offset < total) {
        var r = fetchBatch(offset);
        if (!r || !r.data || !r.data.pic || !r.data.pic.length) break;
        all = all.concat(r.data.pic);
        offset += 5;
    }

    var imgs = '';
    for (var i = 0; i < all.length; i++) {
        var u = all[i].pic;
        if (!u) continue;
        imgs += '<img src="' + u + '" style="width:100%;display:block;">';
    }
    return imgs || '无图片';
})()
''';

/// 合成 nextContentUrl：ajax 取当前页，解析 next 后返回**另一章节**地址。
String _nextContentRule(String base) => '''
@js:
(function() {
    var m = String(baseUrl).match(/\\/chapter\\/(\\d+)\\/(\\d+)\\.html/);
    if (!m) return '';
    var html = String(java.ajax(String(baseUrl)));
    var next = html.match(/next\\s*:\\s*(\\d+)/);
    if (next && next[1] && next[1] !== '0') {
        return '$base/chapter/' + m[1] + '/' + next[1] + '.html';
    }
    return '';
})()
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    HttpOverrides.global = null;
    JsEngine.resetPoolForTest();
    ShuyuanSourceContext.resetForTest();
  });

  test('正文 POST 分页循环多轮重放收敛，且下一章页不被抓取', () async {
    const chapterPath = '/chapter/9001/500.html';
    const nextChapterPath = '/chapter/9001/501.html';
    const total = 12;

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final base = 'http://${server.address.address}:${server.port}';
    final records = <_ReqRecord>[];
    final picRequests = <String, String>{};

    server.listen((req) async {
      final chunks = <int>[];
      await for (final c in req) {
        chunks.addAll(c);
      }
      final body = utf8.decode(chunks, allowMalformed: true);
      records.add(_ReqRecord(
        req.method,
        req.uri.toString(),
        <String, String>{
          'user-agent': req.headers.value('user-agent') ?? '',
          'origin': req.headers.value('origin') ?? '',
          'referer': req.headers.value('referer') ?? '',
          'x-requested-with': req.headers.value('x-requested-with') ?? '',
          'content-type': req.headers.value('content-type') ?? '',
        },
        body,
      ));
      final res = req.response;
      if (req.uri.path == '/api/pics' && req.method == 'POST') {
        final form = Uri.splitQueryString(body);
        picRequests[form['offset'] ?? '?'] = form.toString();
        final offset = int.tryParse(form['offset'] ?? '') ?? 0;
        final limit = int.tryParse(form['limit'] ?? '') ?? 5;
        final pics = <Map<String, dynamic>>[];
        for (var i = offset; i < offset + limit && i < total; i++) {
          pics.add(<String, dynamic>{
            'pic': '$base/pic/${form['aid']}_${form['id']}/$i.jpg',
          });
        }
        res.headers.contentType =
            ContentType('application', 'json', charset: 'utf-8');
        res.write(jsonEncode(<String, dynamic>{
          'data': <String, dynamic>{
            'pic': pics,
            'offset': offset,
            'limit': limit,
            'total': total,
          },
          'code': 1,
        }));
      } else if (req.uri.path == chapterPath) {
        res.headers.contentType = ContentType.html;
        res.write('<html><body><script>var next = 501;</script></body></html>');
      } else {
        res.statusCode = 404;
        res.write('nf');
      }
      await res.close();
    });

    final cfg = ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(
      <String, dynamic>{
        'bookSourceName': '合成漫画源',
        'bookSourceUrl': base,
        'bookSourceType': 2,
        'enabled': true,
        'enabledCookieJar': true,
        'header': jsonEncode(<String, String>{
          'User-Agent': 'ParityTestUA/1.0',
          'Referer': '$base/',
        }),
        'ruleContent': <String, dynamic>{
          'content': _contentRule(base),
          'nextContentUrl': _nextContentRule(base),
        },
      },
    ));

    final resolver = ShuyuanNovelResolver();
    final chapterUrl = '$base$chapterPath';
    var urls = <String>[];
    Object? error;
    try {
      final out = await resolver.resolve(
        cfg,
        'images',
        vars: <String, String>{
          'id': '$base/book/9001/',
          'mid': '',
          'cid': chapterUrl,
          'chapterId': chapterUrl,
        },
      );
      urls = (out as List).cast<String>();
    } on Object catch (e) {
      error = e;
    } finally {
      JsEngine.resetReplayCachesFor(cfg.id);
      await server.close(force: true);
    }

    expect(error, isNull);
    expect(urls.length, total);
    expect(urls.first, '$base/pic/9001_500/0.jpg');
    expect(urls.last, '$base/pic/9001_500/11.jpg');

    // 分页请求按 0/5/10 批次发起，POST 方法与规则内声明的头生效。
    expect(picRequests.keys.toSet(), <String>{'0', '5', '10'});
    final postReqs =
        records.where((r) => r.path == '/api/pics').toList();
    expect(postReqs, isNotEmpty);
    expect(postReqs.first.method, 'POST');
    expect(postReqs.first.headers['user-agent'], 'ParityTestUA/1.0');
    expect(postReqs.first.headers['referer'], chapterUrl);
    expect(postReqs.first.headers['x-requested-with'], 'XMLHttpRequest');
    expect(postReqs.first.body, contains('limit=5'));

    // 章节页本身只取一次（nextContentUrl 的 java.ajax），来源为源声明 Referer。
    final pageGets = records.where((r) => r.path == chapterPath).toList();
    expect(pageGets, hasLength(1));
    expect(pageGets.single.headers['referer'], '$base/');

    // 下一章地址必须被同章分页闸门拦住（不同章节根，不抓取）。
    expect(records.any((r) => r.path == nextChapterPath), isFalse);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
