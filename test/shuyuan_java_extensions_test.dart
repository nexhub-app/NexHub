/// java.* 第一梯队桥测试（P0-2）：真 QuickJS 沙箱内验证
/// [javaExtensionsJsPrelude] 的纯计算函数与排空协议。
library;

import 'dart:convert';
import 'dart:io';

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

    test('hexDecode 严格对齐 legado：空串为空，null/奇数/非法字符抛错', () {
      final e = engine();
      expect(e.eval("java.hexDecodeToString('')"), '');
      const probe = "(function(){try{java.hexDecodeToString(%s);"
          "return 'ok';}catch(e){return 'throw';}})()";
      expect(e.eval(probe.replaceAll('%s', "'abc'")), 'throw',
          reason: '奇数长度');
      expect(e.eval(probe.replaceAll('%s', "'zz'")), 'throw', reason: '非法字符');
      expect(e.eval(probe.replaceAll('%s', "'0g'")), 'throw', reason: '半合法对');
      expect(e.eval(probe.replaceAll('%s', 'null')), 'throw', reason: 'null');
      expect(e.eval(probe.replaceAll('%s', 'undefined')), 'throw',
          reason: 'undefined');
      expect(
          e.eval("(function(){try{java.hexDecodeToByteArray('0g');"
              "return 'ok';}catch(e){return 'throw';}})()"),
          'throw');
    });

    test('encodeURI 为 Java URLEncoder 口径（空格→+）', () {
      final e = engine();
      expect(e.eval("java.encodeURI('a b&c=中文')"), 'a+b%26c%3D%E4%B8%AD%E6%96%87');
      expect(e.eval("java.encodeURI('abc-._*')"), 'abc-._*');
    });
  });

  group('java.* 字符串/时间/杂项', () {
    test('toNumChapter 对齐 legado：String? 语义与 (第)(.+?)(章) 重写', () {
      final e = engine();
      // legado 只替换命中段并原样返回未命中串；null 入参返回 null。
      expect(e.eval("String(java.toNumChapter('第123章'))"), '第123章');
      expect(e.eval("String(java.toNumChapter('第一百二十三章'))"), '第123章');
      expect(e.eval("String(java.toNumChapter('第两千零五章'))"), '第2005章');
      expect(e.eval("String(java.toNumChapter('第壹佰贰拾叁章'))"), '第123章');
      // 命中段前后的文本不保留（legado 只拼接三个分组）。
      expect(e.eval("String(java.toNumChapter('正文 第12章 风起'))"), '第12章');
      expect(e.eval("String(java.toNumChapter('十二章'))"), '十二章');
      expect(e.eval("String(java.toNumChapter('12.5话'))"), '12.5话');
      expect(e.eval("String(java.toNumChapter('番外'))"), '番外');
      expect(e.eval('java.toNumChapter(null) === null'), 'true');
      expect(e.eval('java.toNumChapter(undefined) === null'), 'true');
    });

    test('strToBytes / bytesToStr 默认 UTF-8（含 charset 重载）', () {
      final e = engine();
      // Java byte[] 为有符号字节（UTF-8「中」= E4 B8 AD → -28,-72,-83）。
      expect(e.eval("JSON.stringify(java.strToBytes('中'))"), '[-28,-72,-83]');
      expect(e.eval("java.bytesToStr(java.strToBytes('中文ab'))"), '中文ab');
      expect(e.eval("java.bytesToStr([-28,-72,-83])"), '中');
      expect(
        e.eval("java.bytesToStr(java.strToBytes('x', 'UTF-8'), 'UTF-8')"),
        'x',
      );
      expect(e.eval("java.bytesToStr(java.strToBytes(''), 'GBK')"), '');
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

    test('timeFormatUTC 时区偏移按毫秒换算（legado sh:Int 即毫秒）', () {
      final e = engine();
      expect(e.eval("java.timeFormatUTC(1700000000000, 'yyyy-MM-dd HH:mm:ss', 0)"),
          '2023-11-14 22:13:20');
      // SimpleTimeZone(sh) 的 sh 为毫秒：28800000 = +8 小时。
      expect(e.eval("java.timeFormatUTC(1700000000000, 'yyyy-MM-dd HH:mm:ss', 28800000)"),
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

    test('toast 前缀为书源名（legado 源标签 + 冒号 + 消息）', () {
      final toasts = <String>[];
      JavaFeedback.onToast = (msg, {bool long = false}) => toasts.add(msg);
      try {
        final ctx = ShuyuanSourceContext('src-toast')
          ..bindSource(XiaoshuoBookSource(
            bookSourceUrl: 'https://toast.test',
            bookSourceName: '测试源',
          ));
        final e = engine();
        ShuyuanSourceContext.run(
            ctx, () => e.eval("java.toast('提示'); java.longToast('长提示')"));
        expect(toasts, ['测试源: 提示', '测试源: 长提示']);
      } finally {
        JavaFeedback.onToast = null;
      }
    });

    test('java.ajax callTimeout 记入 ajaxTimeouts 供宿主 settle 使用', () {
      final ctx = ShuyuanSourceContext('src-timeout');
      final e = engine();
      final out = ShuyuanSourceContext.run(
          ctx, () => e.eval("java.ajax('https://slow.test/a', 3000)"));
      expect(out, contains('__AJAX_'));
      expect(ctx.ajaxPending, contains('https://slow.test/a'));
      expect(ctx.ajaxTimeouts['https://slow.test/a'], 3000);
      // 未传 callTimeout 不落表（宿主用默认超时）。
      ShuyuanSourceContext.run(
          ctx, () => e.eval("java.ajax('https://slow.test/b')"));
      expect(ctx.ajaxTimeouts.containsKey('https://slow.test/b'), isFalse);
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

  group('source.* / cache.* 变量语义', () {
    test('source.get 缺省返回空串，put 后同轮可读（legado BaseSource）', () {
      final e = engine();
      expect(e.eval("source.get('missing')"), '');
      expect(
        e.eval("source.put('explore_mode', 'novel'); "
            "source.get('explore_mode')"),
        'novel',
      );
      // put 返回写入值（legado `fun put(key, value): String`）。
      expect(e.eval("source.put('k', 'v')"), 'v');
    });

    test('source.put 经排空落源变量，下一轮种子可见', () {
      final ctx = ShuyuanSourceContext('src-put');
      final e = engine();
      ShuyuanSourceContext.run(
          ctx, () => e.eval("source.put('mode', 'ai')"));
      expect(ctx.sourceVars['__v:mode'], 'ai');
      final out = ShuyuanSourceContext.run(
          ctx, () => e.eval("source.get('mode')"));
      expect(out, 'ai');
      // put/get 与 putVariable/getVariable 命名空间隔离。
      expect(
        ShuyuanSourceContext.run(
            ctx, () => e.eval("source.putVariable('mode', 'var'); "
                "source.get('mode') + '|' + source.getVariable('mode')")),
        'ai|var',
      );
    });

    test('cache.get/getFile/getMemory 缺失返回 null（legado CacheManager）', () {
      final e = engine();
      expect(e.eval("cache.get('nope') === null ? 'NULL' : 'OTHER'"), 'NULL');
      expect(
          e.eval("cache.getFile('nope') === null ? 'NULL' : 'OTHER'"), 'NULL');
      expect(
          e.eval("cache.getMemory('nope') === null ? 'NULL' : 'OTHER'"),
          'NULL');
      // JSON.parse(null) 合法（源脚本用它探测缓存），JSON.parse('') 抛错。
      expect(e.eval("JSON.parse(cache.getFile('nope')) === null ? 'OK' : 'NO'"),
          'OK');
      expect(e.eval("cache.put('k', 'v'); cache.get('k')"), 'v');
    });

    test('source.getTag / java.getTag 返回书源名（legado BaseSource）', () {
      final ctx = ShuyuanSourceContext('src-tag')
        ..bindSource(XiaoshuoBookSource(
          bookSourceUrl: 'https://tag.test',
          bookSourceName: '测试源',
        ));
      final e = engine();
      expect(ShuyuanSourceContext.run(ctx, () => e.eval('source.getTag()')),
          '测试源');
      expect(ShuyuanSourceContext.run(ctx, () => e.eval('java.getTag()')),
          '测试源');
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

    test('NIST SP 800-38A AES-128 CTR / OFB / CFB128 向量', () {
      final e = engine();
      const key = '2b7e151628aed2a6abf7158809cf4f3c';
      // F.3.13 CTR 用 f0f1…feff；F.5.1 OFB / F.4.1 CFB 用 0001…0e0f。
      const ctrIv = 'f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff';
      const blockIv = '000102030405060708090a0b0c0d0e0f';
      const plain = '6bc1bee22e409f96e93d7e117393172a'
          'ae2d8a571e03ac9c9eb76fac45af8e51'
          '30c81c46a35ce411e5fbc1191a0a52ef'
          'f69f2445df4f9b17ad2b417be66c3710';
      // F.3.13 CTR-AES128.Encrypt
      expect(
          e.eval("__aesModeHexTest('$key', '$ctrIv', '$plain', 'CTR', true)"),
          '874d6191b620e3261bef6864990db6ce'
          '9806f66b7970fdff8617187bb9fffdff'
          '5ae4df3edbd5d35e5b4f09020db03eab'
          '1e031dda2fbe03d1792170a0f3009cee');
      // F.5.1 OFB-AES128.Encrypt
      expect(
          e.eval("__aesModeHexTest('$key', '$blockIv', '$plain', 'OFB', true)"),
          '3b3fd92eb72dad20333449f8e83cfb4a'
          '7789508d16918f03f53c52dac54ed825'
          '9740051e9c5fecf64344f7a82260edcc'
          '304c6528f659c77866a510d9c1d6ae5e');
      // F.4.1 CFB128-AES128.Encrypt
      expect(
          e.eval("__aesModeHexTest('$key', '$blockIv', '$plain', 'CFB128', true)"),
          '3b3fd92eb72dad20333449f8e83cfb4a'
          'c8a64537a0b3a93fcde3cdad9f1ce58b'
          '26751f67a3cbb140b1808cf187a4f4df'
          'c04b05357c5d1c0eeac4c66f9ff7f2e6');
      // 解密回到明文。
      expect(
          e.eval("__aesModeHexTest('$key', '$ctrIv', "
              "'874d6191b620e3261bef6864990db6ce', 'CTR', false)"),
          '6bc1bee22e409f96e93d7e117393172a');
    });

    test('java.aesEncode/aesDecode 支持 CTR/CFB/OFB 流模式', () {
      final e = engine();
      const key = '0123456789abcdef';
      const iv = 'abcdef0123456789';
      for (final mode in ['CTR', 'CFB', 'OFB']) {
        final cipher = e.eval("java.aesEncode('中文abc123', '$key', "
            "'AES/$mode/PKCS5Padding', '$iv')");
        expect(cipher, isNotEmpty, reason: mode);
        expect(
            e.eval("java.aesDecodeToString('$cipher', '$key', "
                "'AES/$mode/PKCS5Padding', '$iv')"),
            '中文abc123',
            reason: mode);
      }
      // 非法 GCM 输入仍返回空（密文须含 16 字节 tag）。
      expect(
          e.eval("java.aesDecodeToString('AAAA', '0123456789abcdef', "
              "'AES/GCM/NoPadding', 'abcdef0123456789')"),
          '');
    });
  });

  group('java.* AES-GCM', () {
    const nistKey = 'feffe9928665731c6d6a8f9467308308';
    const nistIv = 'cafebabefacedbaddecaf888';
    const nistPlain = 'd9313225f88406e5a55909c5aff5269a'
        '86a7a9531534f7da2e4c303d8a318a72'
        '1c3c0c95956809532fcf0e2449a6b525'
        'b16aedf5aa0de657ba637b391aafd255';
    const nistCipherWithTag = '42831ec2217774244b7221b784d0d49c'
        'e3aa212f2c02a4e035c17e2329aca12e'
        '21d514b25466931c7d8f6a5aac84aa05'
        '1ba30b396a0aac973d58e091473f5985'
        '4d5c2af327cd64a62cf35abd2ba6fab4';

    test('NIST SP 800-38D Test Case 2（单块零明文）', () {
      final e = engine();
      const key = '00000000000000000000000000000000';
      const iv = '000000000000000000000000';
      const ctTag = '0388dace60b6a392f328c2b971b2fe78'
          'ab6e47d42cec13bdf53a67b21257bddf';
      expect(
          e.eval("__aesGcmHexTest('$key', '$iv', "
              "'00000000000000000000000000000000', true)"),
          ctTag);
      expect(
          e.eval("__aesGcmHexTest('$key', '$iv', '$ctTag', false)"),
          '00000000000000000000000000000000');
    });

    test('NIST SP 800-38D Test Case 3（60 字节明文，非整块尾部）', () {
      final e = engine();
      expect(
          e.eval("__aesGcmHexTest('$nistKey', '$nistIv', '$nistPlain', true)"),
          nistCipherWithTag);
      expect(
          e.eval(
              "__aesGcmHexTest('$nistKey', '$nistIv', '$nistCipherWithTag', false)"),
          nistPlain);
    });

    test('tag 被篡改时解密返回空（不做无校验解密）', () {
      final e = engine();
      final bad = '${nistCipherWithTag.substring(0, nistCipherWithTag.length - 1)}0';
      expect(
          e.eval("__aesGcmHexTest('$nistKey', '$nistIv', '$bad', false)"), '');
    });

    test('Cipher + SecretKeySpec + GCMParameterSpec（Java 互操作路径）', () {
      final e = engine();
      String cipher({required bool encrypt, required String input}) {
        final mode = encrypt ? 1 : 2;
        return e.eval(
            "var c = Packages.javax.crypto.Cipher.getInstance("
            "'AES/GCM/NoPadding');"
            "c.init($mode, new Packages.javax.crypto.spec.SecretKeySpec("
            "java.hexDecodeToByteArray('$nistKey'), 'AES'),"
            " new Packages.javax.crypto.spec.GCMParameterSpec(128, "
            "java.hexDecodeToByteArray('$nistIv')));"
            "java.hexEncodeToString(c.doFinal("
            "java.hexDecodeToByteArray('$input')))");
      }

      expect(cipher(encrypt: true, input: nistPlain), nistCipherWithTag);
      expect(
          cipher(encrypt: false, input: nistCipherWithTag), nistPlain);
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

    test('URL 输入走二进制重放：未命中登记 ajaxBytes，命中后解析', () {
      const url = 'https://cdn.example/font.ttf';
      final ctx = ShuyuanSourceContext('src-ttf-url');
      final e = engine();
      final first = ShuyuanSourceContext.run(
          ctx,
          () => e.eval(
              "java.queryTTF('$url') === null ? 'NULL' : 'FONT'"));
      expect(first, 'NULL');
      expect(ctx.ajaxBytesPending, contains(url));
      // 模拟宿主 settle 命中：二进制进缓存后同源下一轮可解析。
      ctx.ajaxBytesCache[url] = base64Encode(
          File('assets/fonts/SmileySans-Oblique.ttf').readAsBytesSync());
      final second = ShuyuanSourceContext.run(
          ctx,
          () => e.eval("var f = java.queryTTF('$url'); "
              "f === null ? 'NULL' : String(f.numGlyphs)"));
      expect(int.tryParse(second) ?? 0, greaterThan(100));
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

    test('SHA-384 / SHA-512 标准向量与 HMAC 交叉验证', () {
      final e = engine();
      expect(e.eval("java.digestHex('abc', 'SHA-384')"),
          'cb00753f45a35e8bb5a03d699ac65007272c32ab0eded163'
          '1a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7');
      expect(e.eval("java.digestHex('abc', 'SHA-512')"),
          'ddaf35a193617abacc417349ae20413112e6fa4e89a97ea2'
          '0a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd'
          '454d4423643ce80e2a9ac94fa54ca49f');
      const msg = 'The quick brown fox jumps over the lazy dog';
      expect(
          e.eval("java.HMacHex('$msg', 'HmacSHA512', 'key')"),
          crypto.Hmac(crypto.sha512, utf8.encode('key'))
              .convert(utf8.encode(msg))
              .toString());
      expect(
          e.eval("java.HMacHex('$msg', 'HmacSHA384', 'key')"),
          crypto.Hmac(crypto.sha384, utf8.encode('key'))
              .convert(utf8.encode(msg))
              .toString());
    });

    test('不支持的算法返回空串', () {
      final e = engine();
      expect(e.eval("java.digestHex('abc', 'SM3')"), '');
      expect(e.eval("java.HMacHex('abc', 'HmacSM3', 'k')"), '');
    });

    test('base64 flags（android.util.Base64 口径）', () {
      final e = engine();
      // 默认 NO_WRAP；DEFAULT(0) 按 76 字符换行、末尾带行分隔符。
      const sixty = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final noWrap = e.eval("java.base64Encode('$sixty')");
      expect(noWrap.length, 80);
      expect(noWrap.contains('\n'), false);
      final wrapped = e.eval("java.base64Encode('$sixty', 0)");
      expect(wrapped, '${noWrap.substring(0, 76)}\n${noWrap.substring(76)}\n');
      expect(e.eval("java.base64Encode('$sixty', 4)"),
          '${noWrap.substring(0, 76)}\r\n${noWrap.substring(76)}\r\n');
      // NO_PADDING 去掉尾部 '='；未加 NO_WRAP 时仍带行尾分隔符（AOSP 口径）。
      expect(e.eval("java.base64Encode('ab')"), 'YWI=');
      expect(e.eval("java.base64Encode('ab', 1)"), 'YWI\n');
      expect(e.eval("java.base64Encode('ab', 3)"), 'YWI');
      // URL_SAFE 用 -/_；与 NO_PADDING 组合无填充。
      expect(
          e.eval("Packages.android.util.Base64.encodeToString("
              "java.hexDecodeToByteArray('fbff'), 11)"),
          '-_8');
      expect(
          e.eval("Packages.android.util.Base64.encodeToString("
              "java.hexDecodeToByteArray('fbff'), 2)"),
          '+/8=');
      // 解码宽容：url-safe 字母表、缺填充、空白。
      expect(e.eval("JSON.stringify(java.base64DecodeToByteArray('-_8'))"),
          '[-5,-1]');
      expect(e.eval("JSON.stringify(java.base64DecodeToByteArray(' YWJj '))"),
          '[97,98,99]');
      expect(
          e.eval("java.base64DecodeToByteArray('   ') === null ? 'NULL' : 'X'"),
          'NULL');
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

    test('DES/3DES CTR/CFB/OFB 往返（含非整块 NoPadding）', () {
      final e = engine();
      // 分组模式（PKCS5）往返。
      for (final algo in ['DES', 'DESede']) {
        for (final mode in ['CTR', 'CFB', 'OFB']) {
          final key = algo == 'DESede'
              ? '123456789012345678901234'
              : '12345678';
          final cipher = e.eval("java.createSymmetricCrypto("
              "'$algo/$mode/PKCS5Padding', '$key', 'abcdefgh')"
              ".encryptBase64('中文abc123')");
          expect(cipher, isNotEmpty, reason: '$algo/$mode');
          expect(
              e.eval("java.createSymmetricCrypto("
                  "'$algo/$mode/PKCS5Padding', '$key', 'abcdefgh')"
                  ".decryptStr('$cipher')"),
              '中文abc123',
              reason: '$algo/$mode');
        }
      }
      // CFB/OFB/CTR NoPadding 允许非整块长度（流模式）。
      for (final mode in ['CTR', 'CFB', 'OFB']) {
        final hex = e.eval("java.createSymmetricCrypto("
            "'DES/$mode/NoPadding', '12345678', 'abcdefgh')"
            ".encryptHex('abcdefghijklm')");
        expect(hex.length, 26, reason: mode); // 13 字节 → 26 hex
        expect(
            e.eval("java.createSymmetricCrypto("
                "'DES/$mode/NoPadding', '12345678', 'abcdefgh')"
                ".decryptStr(java.hexDecodeToByteArray('$hex'))"),
            'abcdefghijklm',
            reason: mode);
      }
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

    test('refresh* / sleep / showBrowser 可调用', () {
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
      // refreshTocUrl/refreshContent 已是可执行语义（宿主排空 / 忽略），
      // 不再记「不支持」；showBrowser 仍无宿主动作，记一次运行日志。
      expect(
          logs, contains('[java.showBrowser] 当前运行时不支持该操作，已忽略'));
      expect(logs,
          isNot(contains('[java.refreshTocUrl] 当前运行时不支持该操作，已忽略')));
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
