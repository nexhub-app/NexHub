/// java.* 第一梯队桥测试（P0-2）：真 QuickJS 沙箱内验证
/// [javaExtensionsJsPrelude] 的纯计算函数与排空协议。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:nexhub/features/shuyuan/analyze/analyze_rule.dart';
import 'package:nexhub/features/shuyuan/analyze/java_extensions.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';

void main() {
  // flutter_js 创建运行时需经 rootBundle 加载扩展资产（fetch polyfill），
  // 测试环境须先初始化绑定；真 QuickJS 还要求 PATH 含
  // pub cache flutter_js/windows/shared（见 test 环境约定）。
  TestWidgetsFlutterBinding.ensureInitialized();

  // QuickJS 预置脚本在引擎创建时注入；每个用例独立引擎隔离全局状态。
  JsEngine engine() => JsEngine();

  group('source.* 属性快照', () {
    test('bindSource 后脚本可读源配置字段（legado BookSource 属性）', () {
      final ctx = ShuyuanSourceContext('src-meta')
        ..bindSource(XiaoshuoBookSource(
          bookSourceUrl: 'https://a.com',
          bookSourceName: '测试源',
          bookSourceComment: 'url = "x";',
          header: '{"UA":"t"}',
          loginUrl: '@js:login()',
        ));
      final e = engine();
      final out = ShuyuanSourceContext.run(
        ctx,
        () => e.eval('source.bookSourceComment + "|" + source.bookSourceName '
            '+ "|" + source.bookSourceUrl + "|" + source.bookSourceType'),
      );
      expect(out, 'url = "x";|测试源|https://a.com|0');
    });

    test('未装填时属性返回空串 / 0，不抛错', () {
      final ctx = ShuyuanSourceContext('src-empty');
      final e = engine();
      expect(
        ShuyuanSourceContext.run(ctx, () => e.eval('source.bookSourceComment')),
        '',
      );
      expect(
        ShuyuanSourceContext.run(
            ctx, () => e.eval('String(source.bookSourceType)')),
        '0',
      );
    });
  });

  group('java.* 加密/编码族', () {
    test('md5Encode 标准 RFC 1321 向量', () {
      final e = engine();
      expect(e.eval("java.md5Encode('')"), 'd41d8cd98f00b204e9800998ecf8427e');
      expect(e.eval("java.md5Encode('abc')"), '900150983cd24fb0d6963f7d28e17f72');
      expect(e.eval("java.md5Encode('The quick brown fox jumps over the lazy dog')"),
          '9e107d9d372bb6826bd81d3542a419d6');
    });

    test('md5Encode 中文与 Dart crypto 交叉验证', () {
      final e = engine();
      const s = '中文abc123';
      final expected = crypto.md5.convert(utf8.encode(s)).toString();
      expect(e.eval("java.md5Encode('$s')"), expected);
    });

    test('md5Encode16 取 8-24 位', () {
      final e = engine();
      expect(e.eval("java.md5Encode16('abc')"), '3cd24fb0d6963f7d');
    });

    test('base64 编解码（UTF-8）', () {
      final e = engine();
      expect(e.eval("java.base64Encode('abc')"), 'YWJj');
      expect(e.eval("java.base64Encode('中文')"), '5Lit5paH');
      expect(e.eval("java.base64Decode('5Lit5paH')"), '中文');
      // 容忍换行/空白（legado base64Decode 常见输入形态）。
      expect(e.eval("java.base64Decode('5Lit\\n5paH')"), '中文');
      expect(e.eval("JSON.stringify(java.base64DecodeToByteArray('abc='))"),
          '[105,-73]');
    });

    test('hex 编解码', () {
      final e = engine();
      expect(e.eval("java.hexEncodeToString('中文')"), 'e4b8ade69687');
      expect(e.eval("java.hexDecodeToString('e4b8ade69687')"), '中文');
      expect(e.eval("JSON.stringify(java.hexDecodeToByteArray('00ff10'))"),
          '[0,-1,16]'); // 有符号（legado ByteArray 口径）
      expect(e.eval("java.hexEncodeToString(java.hexDecodeToByteArray('e4b8ad'))"),
          'e4b8ad');
    });

    test('encodeURI 为 Java URLEncoder 口径（空格→+）', () {
      final e = engine();
      expect(e.eval("java.encodeURI('a b&c=中文')"), 'a+b%26c%3D%E4%B8%AD%E6%96%87');
      expect(e.eval("java.encodeURI('abc-._*')"), 'abc-._*');
    });
  });

  group('java.* 字符串/时间/杂项', () {
    test('toNumChapter 阿拉伯与中文数字', () {
      final e = engine();
      expect(e.eval("java.toNumChapter('第123章')"), '123');
      expect(e.eval("java.toNumChapter('第一百二十三章')"), '123');
      expect(e.eval("java.toNumChapter('第两千零五章')"), '2005');
      expect(e.eval("java.toNumChapter('十二章')"), '12');
      expect(e.eval("java.toNumChapter('12.5话')"), '12.5');
      expect(e.eval("java.toNumChapter('番外')"), '-1');
    });

    test('timeFormat 与 Dart Date 一致（本地或 UTC 时区均可）', () {
      final e = engine();
      const millis = 1700000000000;
      String p2(int n) => n < 10 ? '0$n' : '$n';
      // legado 口径：yyyy/MM/dd HH:mm（无秒、斜杠分隔）。
      String fmt(DateTime d) =>
          '${d.year}/${p2(d.month)}/${p2(d.day)} ${p2(d.hour)}:${p2(d.minute)}';
      // 测试环境 QuickJS 的时区可能为 UTC，与 Dart 本地时区不一致：
      // 两种口径都视为正确（时区语义已在 timeFormatUTC 用例中锁定）。
      final localExpected = fmt(DateTime.fromMillisecondsSinceEpoch(millis));
      final utcExpected = fmt(
          DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true));
      expect(e.eval('java.timeFormat($millis)'), anyOf(localExpected, utcExpected));
      // 纯数字字符串按时间戳处理。
      expect(e.eval("java.timeFormat('$millis')"),
          anyOf(localExpected, utcExpected));
    });

    test('timeFormat 支持时间字符串入参，无法解析时原样返回', () {
      final e = engine();
      expect(e.eval("java.timeFormat('2024-01-02 03:04:05')"), '2024/01/02 03:04');
      expect(e.eval("java.timeFormat('')"), '');
      expect(e.eval("java.timeFormat('不是时间')"), '不是时间');
    });

    test('timeFormatUTC 按时区偏移秒换算', () {
      final e = engine();
      expect(e.eval("java.timeFormatUTC(1700000000000, 'yyyy-MM-dd HH:mm:ss', 0)"),
          '2023-11-14 22:13:20');
      expect(e.eval("java.timeFormatUTC(1700000000000, 'yyyy-MM-dd HH:mm:ss', 28800)"),
          '2023-11-15 06:13:20');
    });

    test('randomUUID 形态与 androidId 稳定', () {
      final e = engine();
      final uuid = e.eval('java.randomUUID()');
      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
            .hasMatch(uuid),
        true,
      );
      final id1 = e.eval('java.androidId()');
      final id2 = e.eval('java.androidId()');
      expect(id1, isNotEmpty);
      expect(id1, id2);
    });

    test('htmlFormat 保留 img、块级转换行', () {
      final e = engine();
      expect(
        e.eval(
            r'''java.htmlFormat('<p>你好<br>世界</p><img src="a.jpg"><span>x</span>')'''),
        '你好\n世界\n<img src="a.jpg">x',
      );
    });

    test('t2s 复用繁简预置函数', () {
      final e = engine();
      expect(e.eval("java.t2s('愛')"), '爱');
    });
  });

  group('java.* 排空协议', () {
    test('log 返回原值、toast/log 由宿主收取', () {
      final toasts = <String>[];
      final logs = <String>[];
      JavaFeedback.onToast = (msg, {bool long = false}) => toasts.add(msg);
      JavaFeedback.onLog = (msg) => logs.add(msg);
      try {
        final e = engine();
        final echoed = e.eval("java.log('chain') + '!'");
        expect(echoed, 'chain!');
        e.eval("java.toast('提示A'); java.longToast('提示B'); java.log('日志C')");
        expect(toasts, ['提示A', '提示B']);
        expect(logs, contains('日志C'));
      } finally {
        JavaFeedback.onToast = null;
        JavaFeedback.onLog = null;
      }
    });

    test('put 写入经 takeJavaVars 排空，get 动态读取', () {
      final e = engine();
      final out = e.eval("java.put('k1','v1'); java.put('k2','v2'); java.get('k1')");
      expect(out, 'v1');
      expect(e.takeJavaVars(), {'k1': 'v1', 'k2': 'v2'});
      // 排空后清空。
      expect(e.takeJavaVars(), isEmpty);
    });

    test('宿主变量表经 __javaVars 种子对动态 get 可见', () {
      final e = engine();
      final out = e.eval(
        "java.get('seeded')",
        bindings: {'__javaVars': {'seeded': 'yes'}},
      );
      expect(out, 'yes');
    });

    test('宿主传入的 java 字符串占位不覆盖预置对象', () {
      final e = engine();
      final out = e.eval(
        "java.md5Encode('abc')",
        bindings: {'java': 'legacy-string', 'result': 'x'},
      );
      expect(out, '900150983cd24fb0d6963f7d28e17f72');
    });
  });

  group('java.* AES', () {
    test('FIPS-197 AES-128 ECB 向量', () {
      final e = engine();
      expect(
          e.eval("__aesHexTest('000102030405060708090a0b0c0d0e0f', '', "
              "'00112233445566778899aabbccddeeff', true)"),
          '69c4e0d86a7b0430d8cdb78070b4c55a');
      expect(
          e.eval("__aesHexTest('000102030405060708090a0b0c0d0e0f', '', "
              "'69c4e0d86a7b0430d8cdb78070b4c55a', false)"),
          '00112233445566778899aabbccddeeff');
    });

    test('NIST SP 800-38A AES-128-CBC 第一块', () {
      final e = engine();
      expect(
          e.eval("__aesHexTest('2b7e151628aed2a6abf7158809cf4f3c', "
              "'000102030405060708090a0b0c0d0e0f', "
              "'6bc1bee22e409f96e93d7e117393172a', true)"),
          '7649abac8119b246cee98e9b12e9197d');
    });

    test('CBC/PKCS5 中文明文往返', () {
      final e = engine();
      const key = '0123456789abcdef';
      const iv = 'abcdef0123456789';
      final cipher = e.eval(
          "java.aesEncode('中文abc123', '$key', 'AES/CBC/PKCS5Padding', '$iv')");
      expect(cipher, isNotEmpty);
      expect(
          e.eval("java.aesBase64DecodeToString('$cipher', '$key', "
              "'AES/CBC/PKCS5Padding', '$iv')"),
          '中文abc123');
    });

    test('不支持的 transformation 返回空，不给错误结果', () {
      final e = engine();
      expect(
          e.eval("java.aesDecodeToString('AAAA', '0123456789abcdef', "
              "'AES/GCM/NoPadding', 'abcdef0123456789')"),
          '');
    });
  });

  group('java.* 字体反爬', () {
    test('非法输入返回 null，replaceFont 原样返回', () {
      final e = engine();
      expect(
          e.eval("java.queryTTF('not-base64') === null ? 'YES' : 'NO'"), 'YES');
      expect(e.eval('typeof java.queryTTF'), 'function');
      expect(e.eval('typeof java.replaceFont'), 'function');
      expect(e.eval("java.replaceFont('abc', null, null, false)"), 'abc');
    });
  });

  group('java.* 摘要与 HMAC（JsEncodeUtils）', () {
    test('digestHex SHA-1 / SHA-256 标准向量', () {
      final e = engine();
      expect(e.eval("java.digestHex('abc', 'SHA-1')"),
          'a9993e364706816aba3e25717850c26c9cd0d89d');
      expect(e.eval("java.digestHex('abc', 'SHA-256')"),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(e.eval("java.digestHex('abc', 'MD5')"),
          '900150983cd24fb0d6963f7d28e17f72');
    });

    test('digestHex 中文与 Dart crypto 交叉验证', () {
      final e = engine();
      const s = '中文abc123';
      expect(e.eval("java.digestHex('$s', 'SHA-256')"),
          crypto.sha256.convert(utf8.encode(s)).toString());
      expect(e.eval("java.digestHex('$s', 'SHA-1')"),
          crypto.sha1.convert(utf8.encode(s)).toString());
    });

    test('digestBase64Str', () {
      final e = engine();
      expect(e.eval("java.digestBase64Str('abc', 'SHA-256')"),
          base64Encode(crypto.sha256.convert(utf8.encode('abc')).bytes));
    });

    test('HMacHex HmacMD5/HmacSHA1/HmacSHA256 标准向量', () {
      final e = engine();
      const msg = 'The quick brown fox jumps over the lazy dog';
      expect(e.eval("java.HMacHex('$msg', 'HmacMD5', 'key')"),
          '80070713463e7749b90c2dc24911e275');
      expect(e.eval("java.HMacHex('$msg', 'HmacSHA1', 'key')"),
          'de7c9b85b8b78aa6bc8a7a36f70a90701c9db4d9');
      expect(e.eval("java.HMacHex('$msg', 'HmacSHA256', 'key')"),
          'f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8');
    });

    test('HMacBase64 与 hex 同源', () {
      final e = engine();
      const msg = 'The quick brown fox jumps over the lazy dog';
      final hex = e.eval("java.HMacHex('$msg', 'HmacSHA256', 'key')");
      final b64 = e.eval("java.HMacBase64('$msg', 'HmacSHA256', 'key')");
      final expected = base64Encode([
        for (var i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ]);
      expect(b64, expected);
    });

    test('不支持的算法返回空串', () {
      final e = engine();
      expect(e.eval("java.digestHex('abc', 'SHA-512')"), '');
      expect(e.eval("java.HMacHex('abc', 'HmacSHA512', 'k')"), '');
    });
  });

  group('java.* DES / 3DES', () {
    test('FIPS 46-3 DES-ECB 标准向量', () {
      final e = engine();
      expect(
          e.eval("__desHexTest('133457799BBCDFF1', '', "
              "'0123456789ABCDEF', true, false)"),
          '85e813540f0ab405');
      expect(
          e.eval("__desHexTest('133457799BBCDFF1', '', "
              "'85E813540F0AB405', false, false)"),
          '0123456789abcdef');
    });

    test('FIPS 81 DES-CBC 第一块', () {
      final e = engine();
      expect(
          e.eval("__desHexTest('0123456789ABCDEF', '1234567890ABCDEF', "
              "'4E6F772069732074', true, false)"),
          'e5c7cdde872bf27c');
    });

    test('NIST SP 800-67 3DES 标准向量', () {
      final e = engine();
      const key =
          '0123456789ABCDEF23456789ABCDEF01456789ABCDEF0123';
      expect(
          e.eval("__desHexTest('$key', '', '5468652071756663', true, true)"),
          'a826fd8ce53b855f');
      expect(
          e.eval("__desHexTest('$key', '', 'A826FD8CE53B855F', false, true)"),
          '5468652071756663');
    });

    test('DESede 三钥相同退化为 DES（密钥编排自检）', () {
      final e = engine();
      expect(
          e.eval("__desHexTest('133457799BBCDFF1' + '133457799BBCDFF1' + "
              "'133457799BBCDFF1', '', '0123456789ABCDEF', true, true)"),
          '85e813540f0ab405');
    });

    test('desEncodeToBase64String/desBase64DecodeToString 往返', () {
      final e = engine();
      final cipher = e.eval("java.desEncodeToBase64String('中文abc123', "
          "'12345678', 'DES/CBC/PKCS5Padding', 'abcdefgh')");
      expect(cipher, isNotEmpty);
      expect(
          e.eval("java.desBase64DecodeToString('$cipher', '12345678', "
              "'DES/CBC/PKCS5Padding', 'abcdefgh')"),
          '中文abc123');
    });

    test('DES 单块十六进制密文（16 个 hex 字符）可解', () {
      final e = engine();
      final hex = e.eval("java.createSymmetricCrypto("
          "'DES/ECB/NoPadding', '133457799BBCDFF1').encryptHex('abcdefgh')");
      expect(hex, isNotEmpty);
      expect(
          e.eval("java.desDecodeToString('$hex', '133457799BBCDFF1', "
              "'DES/ECB/NoPadding', '')"),
          'abcdefgh');
    });

    test('tripleDES* API 往返（含 base64 密钥变体）', () {
      final e = engine();
      const key = '123456789012345678901234';
      final cipher = e.eval("java.tripleDESEncodeBase64Str('hello 3des', "
          "'$key', 'CBC', 'PKCS5Padding', 'abcdefgh')");
      expect(cipher, isNotEmpty);
      expect(
          e.eval("java.tripleDESDecodeStr('$cipher', '$key', "
              "'CBC', 'PKCS5Padding', 'abcdefgh')"),
          'hello 3des');
      final keyB64 = base64Encode(utf8.encode(key));
      final cipher2 = e.eval("java.tripleDESEncodeArgsBase64Str('args 3des', "
          "'$keyB64', 'CBC', 'PKCS5Padding', 'abcdefgh')");
      expect(
          e.eval("java.tripleDESDecodeArgsBase64Str('$cipher2', '$keyB64', "
              "'CBC', 'PKCS5Padding', 'abcdefgh')"),
          'args 3des');
    });

    test('DES 密钥不足 8 字节返回空', () {
      final e = engine();
      expect(
          e.eval("java.createSymmetricCrypto("
              "'DES/ECB/PKCS5Padding', 'short').encryptBase64('x')"),
          '');
    });
  });

  group('java.* 环境别名', () {
    test('getWebViewUA / getUserAgent 返回 UA 常量', () {
      final e = engine();
      final ua = e.eval('java.getWebViewUA()');
      expect(ua, contains('Mozilla/5.0'));
      expect(ua, contains('Android'));
      expect(e.eval('java.getUserAgent()'), ua);
    });

    test('refresh* / sleep / showBrowser 无操作可调用', () {
      final e = engine();
      final logs = <String>[];
      final prev = JavaFeedback.onLog;
      JavaFeedback.onLog = logs.add;
      try {
        expect(
            e.eval("java.sleep(10); java.refreshTocUrl(); "
                "java.refreshContent(); java.showBrowser('x'); 'ok'"),
            'ok');
      } finally {
        JavaFeedback.onLog = prev;
      }
      // 不支持的宿主动作各记一次运行日志，便于真机排查。
      expect(logs, contains('[java.refreshTocUrl] 当前运行时不支持该操作，已忽略'));
    });

    test('toURL 解析 host/origin/pathname/searchParams', () {
      final e = engine();
      expect(
          e.eval("var u = java.toURL('/x?k=v&m=1', 'https://a.test/'); "
              "u.host + '|' + u.origin + '|' + u.pathname + '|' + u.searchParams.k"),
          'a.test|https://a.test|/x|v');
    });

    test('getVerificationCode 返回空串（无 UI 能力）', () {
      final e = engine();
      expect(e.eval("java.getVerificationCode('https://a.test/img')"), '');
    });
  });

  group('java.* Elements 包装补齐', () {
    test('toArray / isEmpty（jsoup Elements 接口）', () {
      const html = '<div class="i"><a href="/a">甲</a><a href="/b">乙</a></div>';
      final r = AnalyzeRule()
        ..setContent(html)
        ..setBaseUrl('https://x.test/');
      expect(
          r.getString("@js:var l = java.getElements('.i a'); "
              "l.isEmpty() ? 'E' : String(l.toArray().length)"),
          '2');
      expect(
          r.getString("@js:java.getElements('.nope').isEmpty() ? 'YES' : 'NO'"),
          'YES');
    });
  });
}
