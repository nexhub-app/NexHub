/// P1 第六/七批桥面测试：R38 自动密钥对、R48 SHA-224/384/512withRSA、
/// X10 重放中间轮一次性副作用去重、R41 类型化 Map 键、R47 注册类
/// （BigInteger / Mac / SimpleDateFormat / Date / URLEncoder）。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/java_extensions.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _privB64 =
    'MIICdwIBADANBgkqhkiG9w0BAQEFAASCAmEwggJdAgEAAoGBAMOLYF+PlfKlvo6zDkGB'
    'T+JmbnpF+m+0AOXbXvhIvF3Ynz3ysEVSeRpztbENrSWuCQJLmNLC8Zq9lBwLUcBtwKV4'
    'yyZ5M2qRHuXqJzCVJmteS9/+/hsx2dCpKG9It069W173i8LgebRWr7JBlDcNgnIFMhZV'
    'DTOomtxG4rWQ2AqZAgMBAAECgYAPcBN9t+JIs9klfvFjLohWAWw7bwbkhruDahxHUca9'
    'SfrYcy6Dao1xDy2K+t9umBzR95HrIcTdSJZG2IXtwTxyMGutSVrOQ+PbAng4dMOZqfkz'
    'vYGaQKhsBk6sueRNNeh1USlzH3kjuXB4q68IhkPTJEUob6nL5vmRUyCu2Oyj+QJBAMxE'
    'lhFZxwWyCn6ZzT91NhuuQBU0B779EOsJSBQhh7eafpLtvzcUMFmCfEe0ldX4YUFiygae'
    'tWL5BPcDakLekk8CQQD1ETdklHy4JcMPj55DlJangiEEJO4HwhiRwTFFW1ayWYFp7EZQ'
    'Bqf6/WjU+j0bncmC+oHNFY2SctJtwbUbuuKXAkEAkR6o/uqpWoKCsi7SgqLjLgc9v9KX'
    'LjjcLB8L9kFcCjTYd8owbxEIyI7LfKXvTXSIo8trfAiFFSuVO2hRtfAqQQJAMB5FRhZx'
    'tqaTeka0yIgwXIuMeAfYROWzdUr9paSdjT9NzcJ6u9PSv9Fp+Ad6YCXHH1SYj/AfcBXj'
    'g3F5Ygx72QJBAJLFkV8ouNHpr6XR5DSB2TjdwVTqvGR3vRHah4BtkVEjUTJ6dzBPQORp'
    'FwPf1Ik2JByPfT79D7hhCkl6IYUBir8=';
const _pubB64 =
    'MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDDi2Bfj5Xypb6Osw5BgU/iZm56Rfpv'
    'tADl2174SLxd2J898rBFUnkac7WxDa0lrgkCS5jSwvGavZQcC1HAbcCleMsmeTNqkR7l'
    '6icwlSZrXkvf/v4bMdnQqShvSLdOvVte94vC4Hm0Vq+yQZQ3DYJyBTIWVQ0zqJrcRuK1'
    'kNgKmQIDAQAB';

String _hexOf(String b64) => base64Decode(b64)
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  setUp(ShuyuanSourceContext.resetForTest);

  group('R38 构造期自动密钥对', () {
    test('未 setKey 直接加密产出真实密文（重放轮取回真值）', () {
      final e = JsEngine();
      final out = e.eval('''
(function () {
  var c = java.createAsymmetricCrypto('RSA');
  var enc = c.encryptBase64('自动密钥');
  if (!enc || enc.length < 100) return 'EMPTY';
  var back = c.decryptStr(enc, false);
  return back === '自动密钥' ? 'ROUNDTRIP' : 'MISMATCH';
})()
''');
      expect(out, 'ROUNDTRIP');
      e.dispose();
    });

    test('同引擎两次构造拿到不同密钥：自解成功、互解被拒', () {
      final e = JsEngine();
      final out = e.eval('''
(function () {
  var c1 = java.createAsymmetricCrypto('RSA');
  var c2 = java.createAsymmetricCrypto('RSA');
  // 两实例构造序号不同 → 不同密钥：互解应失败，自解应成功。
  var enc = c1.encryptBase64('往返');
  var self = c1.decryptStr(enc, false);
  var cross = 'DECRYPTED';
  try {
    cross = c2.decryptStr(enc, false);
  } catch (err) { cross = 'REJECTED'; }
  return JSON.stringify({ self: self, cross: cross });
})()
''');
      final decoded = jsonDecode(out) as Map<String, dynamic>;
      expect(decoded['self'], '往返');
      expect(decoded['cross'], 'REJECTED');
      e.dispose();
    });

    test('publicKey.encoded 为合法 X.509（长度与结构）', () {
      final e = JsEngine();
      final out = e.eval('''
(function () {
  var c = java.createAsymmetricCrypto('RSA');
  var enc = c.encryptBase64('der');
  var spki = c.publicKey.encoded;
  return JSON.stringify({
    head: spki[0] & 0xff,
    len: spki.length,
  });
})()
''');
      final decoded = jsonDecode(out) as Map<String, dynamic>;
      expect(decoded['head'], 0x30); // DER SEQUENCE
      expect(decoded['len'] as int, greaterThan(200)); // 2048 位 SPKI ≈ 294
      e.dispose();
    });
  });

  group('R48 SHA-224/384/512withRSA', () {
    test('sign 与 verify 互验（384/512/224 三族）', () {
      final e = JsEngine();
      final out = e.eval('''
(function () {
  var results = {};
  ['SHA224withRSA', 'SHA384withRSA', 'SHA512withRSA'].forEach(function (name) {
    var s = java.createSign(name);
    s.setPrivateKey(java.base64DecodeToByteArray('$_privB64'));
    var sig = s.sign('hello sign 中文');
    var v = java.createSign(name);
    v.setPublicKey(java.base64DecodeToByteArray('$_pubB64'));
    results[name] = v.verify('hello sign 中文', sig) &&
        !v.verify('hello sign 中文X', sig);
  });
  return JSON.stringify(results);
})()
''');
      expect(out,
          '{"SHA224withRSA":true,"SHA384withRSA":true,"SHA512withRSA":true}');
      e.dispose();
    });

    test('digestHex 家族：SHA224/384/512 可用', () {
      final e = JsEngine();
      final out = e.eval('''
(function () {
  return JSON.stringify({
    sha224: java.digestHex('abc', 'SHA-224'),
    sha384: java.digestHex('abc', 'SHA-384'),
    sha512: java.digestHex('abc', 'SHA-512'),
  });
})()
''');
      final decoded = jsonDecode(out) as Map<String, dynamic>;
      // NIST 向量。
      expect(decoded['sha224'],
          '23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7');
      expect(decoded['sha384'],
          'cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed'
              '8086072ba1e7cc2358baeca134c825a7');
      expect(decoded['sha512'],
          'ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a'
              '2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f');
      e.dispose();
    });
  });

  group('X10 重放中间轮副作用去重', () {
    test('toast 只在最终轮提交一次', () {
      final e = JsEngine();
      final toasts = <String>[];
      final prev = JavaFeedback.onToast;
      JavaFeedback.onToast = (msg, {long = false}) => toasts.add(msg);
      try {
        e.eval('''
java.toast('你好');
var c = java.createAsymmetricCrypto('RSA');
c.encryptHex('x');
''');
      } finally {
        JavaFeedback.onToast = prev;
      }
      expect(toasts, ['你好']);
      e.dispose();
    });
  });

  group('R41 类型化 Map 键', () {
    test('数字键与字符串键互不坍缩，对象键按身份', () {
      final e = JsEngine();
      final out = e.eval('''
(function () {
  var m = new Packages.java.util.HashMap();
  m.put(1, '数字一');
  m.put('1', '字符串一');
  var obj = { x: 1 };
  m.put(obj, '对象');
  return JSON.stringify({
    num: m.get(1),
    str: m.get('1'),
    obj: m.get(obj),
    other: m.get({ x: 1 }),
    size: m.size(),
    keyTypes: Object.prototype.toString.call(m.keySet()[0]),
  });
})()
''');
      final decoded = jsonDecode(out) as Map<String, dynamic>;
      expect(decoded['num'], '数字一');
      expect(decoded['str'], '字符串一');
      expect(decoded['obj'], '对象');
      expect(decoded['other'], isNull); // 不同实例 ≠ Java equals
      expect(decoded['size'], 3);
      e.dispose();
    });

    test('put 覆盖旧值返回旧值，keySet 保插入序', () {
      final e = JsEngine();
      final out = e.eval('''
(function () {
  var m = new Packages.java.util.LinkedHashMap();
  m.put('a', 1);
  m.put('b', 2);
  var old = m.put('a', 9);
  return JSON.stringify({
    old: old,
    a: m.get('a'),
    keys: m.keySet(),
  });
})()
''');
      final decoded = jsonDecode(out) as Map<String, dynamic>;
      expect(decoded['old'], 1);
      expect(decoded['a'], 9);
      expect(decoded['keys'], ['a', 'b']);
      e.dispose();
    });
  });

  group('R47 注册类', () {
    test('BigInteger 算术与 modPow', () {
      final e = JsEngine();
      final out = e.eval('''
(function () {
  var BI = Packages.java.math.BigInteger;
  var a = new BI('12345678901234567890');
  var b = new BI('2');
  var pow = new BI(2).modPow(new BI(10), new BI(1000));
  return JSON.stringify({
    mul: a.multiply(b).toString(),
    add: a.add(new BI('10')).toString(),
    sub: a.subtract(new BI('1')).toString(),
    mod: a.mod(new BI('97')).toString(),
    modPow: pow.toString(),
    hex: new BI('ff', 16).toString(10),
    back: new BI('255').toString(16),
  });
})()
''');
      final decoded = jsonDecode(out) as Map<String, dynamic>;
      expect(decoded['mul'], '24691357802469135780');
      expect(decoded['add'], '12345678901234567900');
      expect(decoded['sub'], '12345678901234567889');
      expect(decoded['mod'], '3');
      expect(decoded['modPow'], '24');
      expect(decoded['hex'], '255');
      expect(decoded['back'], 'ff');
      e.dispose();
    });

    test('javax.crypto.Mac HMAC-SHA256 与向量一致', () {
      final e = JsEngine();
      final out = e.eval('''
(function () {
  var mac = Packages.javax.crypto.Mac.getInstance('HmacSHA256');
  mac.init(new Packages.javax.crypto.spec.SecretKeySpec(
      java.strToBytes('key'), 'HmacSHA256'));
  return JSON.stringify(Array.prototype.map.call(
      mac.doFinal(java.strToBytes('hello')), function (b) { return b; }));
})()
''');
      final decoded = (jsonDecode(out) as List).cast<int>();
      final expected = crypto.Hmac(crypto.sha256, utf8.encode('key'))
          .convert(utf8.encode('hello'))
          .bytes;
      final actualSigned = expected.map((b) => b > 127 ? b - 256 : b).toList();
      expect(decoded, actualSigned);
      e.dispose();
    });

    test('URLEncoder/URLDecoder（Java 空格→+ 口径）', () {
      final e = JsEngine();
      final out = e.eval('''
(function () {
  var enc = Packages.java.net.URLEncoder.encode('a b&c=中文', 'UTF-8');
  return JSON.stringify({
    enc: enc,
    back: Packages.java.net.URLDecoder.decode(enc, 'UTF-8'),
  });
})()
''');
      final decoded = jsonDecode(out) as Map<String, dynamic>;
      expect(decoded['enc'], 'a+b%26c%3D%E4%B8%AD%E6%96%87');
      expect(decoded['back'], 'a b&c=中文');
      e.dispose();
    });

    test('SimpleDateFormat 数字字段格式化', () {
      final e = JsEngine();
      // QuickJS 沙箱 Date 按本机时区渲染；环境时区不可控（本机/CI 可能是
      // UTC），构造用 UTC 时间戳并把预期也按 UTC 计算，两边必然一致。
      final utc = DateTime.utc(2026, 3, 7, 8, 9, 10, 123);
      final ts = utc.millisecondsSinceEpoch;
      final out = e.eval('''
(function () {
  var f = new Packages.java.text.SimpleDateFormat('yyyy-MM-dd HH:mm:ss.SSS');
  return f.format(new Packages.java.util.Date($ts));
})()
''');
      String p2(int n) => n < 10 ? '0$n' : '$n';
      final expected =
          '${utc.year}-${p2(utc.month)}-${p2(utc.day)} '
          '${p2(utc.hour)}:${p2(utc.minute)}:${p2(utc.second)}'
          '.${utc.millisecond.toString().padLeft(3, '0')}';
      expect(out, expected);
      e.dispose();
    });
  });
}
