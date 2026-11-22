/// 文件/归档族对等 legado `JsExtensions`：
/// `downloadFile`（含已废弃 hex 重载）/`readFile`/`readTxtFile`/
/// `deleteFile`/`unzipFile|unrarFile|un7zFile`/`getTxtInFolder`/
/// `getZipStringContent`/`importScript` 本地分支。
///
/// 沙箱内是虚拟文件系统 + 确定性重放：网络字节走 `__ajaxBytesCache`，
/// 解压/取包内条目/文本解码走宿主 settle（`__fileOpCache`）。测试全部为
/// 合成 zip 与十六进制向量，不访问网络。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';

const _utf8Text = '第一章 合成';
const _gbkText = '第二章 合成';

String _hex(List<int> bytes) =>
    bytes.map((b) => (b & 0xff).toRadixString(16).padLeft(2, '0')).join();

List<int> _zipBytes() {
  final archive = Archive();
  final a = utf8.encode(_utf8Text);
  final b = gbk.encode(_gbkText);
  archive.addFile(ArchiveFile('a.txt', a.length, a));
  archive.addFile(ArchiveFile('dir/b.txt', b.length, b));
  return ZipEncoder().encode(archive)!;
}

XiaoshuoBookSource _source() => XiaoshuoBookSource(
      bookSourceUrl: 'https://x.test/',
      bookSourceName: '文件归档合成测试源',
    );

/// 宿主重放循环：脚本里登记的文件族/网络待办 settle 后重跑，直到无待办。
Future<String> _run(
  JsEngine engine,
  ShuyuanSourceContext ctx,
  String js, {
  int maxPasses = 6,
}) async {
  final source = _source();
  var out = '';
  for (var pass = 0; pass < maxPasses; pass++) {
    out = engine.eval(js);
    if (ctx.fileOpPending.isEmpty &&
        ctx.ajaxPending.isEmpty &&
        ctx.ajaxBytesPending.isEmpty) {
      break;
    }
    await ShuyuanSourceContext.settleAjax(ctx, source);
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  setUp(() {
    JsEngine.resetPoolForTest();
    ShuyuanSourceContext.resetForTest();
  });

  test('downloadFile → unzipFile → readTxtFile（包内 UTF-8 与 GBK 文本）', () async {
    final e = JsEngine();
    final ctx = ShuyuanSourceContext('file-archive-zip');
    ctx.ajaxBytesCache['https://x.test/book.zip'] = base64Encode(_zipBytes());
    const js = '''
(function(){
  var p = java.downloadFile('https://x.test/book.zip');
  var dir = java.unzipFile(p);
  var a = java.readTxtFile(dir + '/a.txt');
  var b = java.readTxtFile(dir + '/dir/b.txt');
  return [p, dir, a, b].join('|');
})()''';
    final out = await ShuyuanSourceContext.run(ctx, () => _run(e, ctx, js));
    final parts = out.split('|');
    expect(parts[0], startsWith('shuyuan_cache/'));
    expect(parts[0], endsWith('.zip'));
    expect(parts[1], startsWith('ArchiveTemp/'));
    expect(parts[2], _utf8Text);
    expect(parts[3], _gbkText);
  });

  test('getTxtInFolder 换行连接全部文件并删除目录', () async {
    final e = JsEngine();
    final ctx = ShuyuanSourceContext('file-archive-folder');
    ctx.ajaxBytesCache['https://x.test/book.zip'] = base64Encode(_zipBytes());
    const js = '''
(function(){
  var p = java.downloadFile('https://x.test/book.zip');
  var dir = java.unzipFile(p);
  var all = java.getTxtInFolder(dir);
  var again = java.readTxtFile(dir + '/a.txt');
  return all + '#' + again;
})()''';
    final out = await ShuyuanSourceContext.run(ctx, () => _run(e, ctx, js));
    expect(out, '$_utf8Text\n$_gbkText#');
  });

  test('getZipStringContent：URL / hex 输入、显式 GBK、未命中空串', () async {
    final e = JsEngine();
    final ctx = ShuyuanSourceContext('file-archive-zip-content');
    ctx.ajaxBytesCache['https://x.test/book.zip'] = base64Encode(_zipBytes());
    final hex = _hex(_zipBytes());
    final js = '''
(function(){
  var u = java.getZipStringContent('https://x.test/book.zip', 'a.txt');
  var h = java.getZipStringContent('$hex', 'dir/b.txt', 'gbk');
  var m = java.getZipStringContent('$hex', 'none.txt');
  return [u, h, m].join('|');
})()''';
    final out = await ShuyuanSourceContext.run(ctx, () => _run(e, ctx, js));
    expect(out, '$_utf8Text|$_gbkText|');
  });

  test('downloadFile(hex,url) 旧签名 + type 选项 + readFile/deleteFile', () async {
    final e = JsEngine();
    final ctx = ShuyuanSourceContext('file-archive-legacy');
    final hex = _hex(_zipBytes());
    final expectedLen = utf8.encode(_utf8Text).length;
    final js = '''
(function(){
  var p = java.downloadFile('$hex', 'https://x.test/legacy,{"type":"zip"}');
  var dir = java.unzipFile(p);
  var arr = java.readFile(dir + '/a.txt') || [];
  var del = String(java.deleteFile(dir));
  var after = java.readTxtFile(dir + '/a.txt');
  return [p, String(arr.length), del, after].join('|');
})()''';
    final out = await ShuyuanSourceContext.run(ctx, () => _run(e, ctx, js));
    final parts = out.split('|');
    expect(parts[0], endsWith('.zip'));
    expect(parts[1], '$expectedLen');
    expect(parts[2], 'true');
    expect(parts[3], '');
  });

  test('非 zip 容器：unrarFile/un7zFile 不产内容也不崩', () async {
    final e = JsEngine();
    final ctx = ShuyuanSourceContext('file-archive-rar');
    final hex = _hex(<int>[1, 2, 3, 4, 5, 6, 7, 8]);
    final js = '''
(function(){
  var p = java.downloadFile('$hex', 'https://x.test/x.rar,{"type":"rar"}');
  var dir = java.unrarFile(p);
  var t = java.readTxtFile(dir + '/a.txt');
  var d2 = java.un7zFile(p);
  return [String(dir).indexOf('ArchiveTemp/') === 0, t, String(d2).length > 0]
      .join('|');
})()''';
    final out = await ShuyuanSourceContext.run(ctx, () => _run(e, ctx, js));
    expect(out, 'true||true');
  });

  test('readTxtFile 对下载的 GBK 文本自动回落解码（含显式 charset）', () async {
    final e = JsEngine();
    final ctx = ShuyuanSourceContext('file-archive-gbk');
    final hex = _hex(Uint8List.fromList(gbk.encode('中文内容')));
    final js = '''
(function(){
  var p = java.downloadFile('$hex', 'https://x.test/x.txt,{"type":"txt"}');
  var auto = java.readTxtFile(p);
  var explicit = java.readTxtFile(p, 'gbk');
  return auto + '#' + explicit;
})()''';
    final out = await ShuyuanSourceContext.run(ctx, () => _run(e, ctx, js));
    expect(out, '中文内容#中文内容');
  });
}
