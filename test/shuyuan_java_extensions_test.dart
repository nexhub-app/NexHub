/// java.* 第一梯队桥测试（P0-2）：真 QuickJS 沙箱内验证
/// [javaExtensionsJsPrelude] 的纯计算函数与排空协议。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:nexhub/features/shuyuan/analyze/java_extensions.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';

void main() {
  // flutter_js 创建运行时需经 rootBundle 加载扩展资产（fetch polyfill），
  // 测试环境须先初始化绑定；真 QuickJS 还要求 PATH 含
  // pub cache flutter_js/windows/shared（见 test 环境约定）。
  TestWidgetsFlutterBinding.ensureInitialized();

  // QuickJS 预置脚本在引擎创建时注入；每个用例独立引擎隔离全局状态。
  JsEngine engine() => JsEngine();

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
}
