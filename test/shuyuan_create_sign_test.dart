/// `java.createSign(algorithm)` 对等 legado `help/crypto/Sign.kt`：
/// keyAlgorithm 推导、链式 setter、ByteArray/String 密钥装载、
/// sign/signHex/verify、缺密钥与不支持算法的异常口径。
/// 期望签名向量由 JDK `Signature`（fresh RSA-1024）离线生成。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// fresh RSA-1024 PKCS#8 私钥（JDK 生成，签名向量与该私钥配对）。
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

/// data = 'hello sign 中文'（UTF-8），JDK Signature 输出（PKCS#1 v1.5）。
const _expectedSigs = {
  'MD5withRSA':
      'BQMs7Q6gyGFFP7zvdfhZCtSyg73u9dFVSOwgIWjhxy/20yrepD6EFgSlmjkp3HNx7Co'
          'PncYtLSKw0GKO7phpln82nie94UrAIf47SyLV+OjZLjkdNp6tf60IGBVo9SF+qBEHNft'
          'd5pdyU6KWKltVPAwOCo5Mlzj9kJOtljsEd8Q=',
  'SHA1withRSA':
      'Et3iCn0+Zs8zFQzEW3dN+2uDjv1h69cJ/mZzAsyO8dzavZ7Q1Ow+YMYZx+VY14EHQfl3'
          '4FlWGAtbk5vrMzvLjQNLkgzU42LQNbIRh1/1wtCgJBmRRQ2LRbreMpUS8rfVm8pZ62Kw'
          'TuR5qnZkMVw9Ul5i82ufdG4aXaQviGQlL/o=',
  'SHA256withRSA':
      'rHEg8lXydVnUAPxOf8RaNiRCXcL8BtvJhj7HbPCmoLTh8LSg9dYDpNkii3Qq82Aa9jxb'
          'XuT0ML3iDBbQ6/MAQb/c+moxUZS9gCZQmUEB5XBsZCnaumVBHds+Uq+o5S9KGuyGbxR/'
          'Dk5RXk8EDstQDKbF9E0f++YDG2X7HQb8MNM=',
};

String _hexOf(String b64) => base64Decode(b64)
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

String _bytes(List<int> b) => '[${b.join(',')}]';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  JsEngine engine() => JsEngine();

  setUp(ShuyuanSourceContext.resetForTest);

  test('三种 withRSA 的 sign/signHex 与 JDK 向量一致', () {
    final e = engine();
    final priv = _bytes(base64Decode(_privB64));
    for (final algo in _expectedSigs.keys) {
      final sig = e.eval('''
(function(){
  var s = java.createSign("$algo").setPrivateKey($priv);
  return Packages.java.util.Base64.getEncoder()
      .encodeToString(s.sign("hello sign 中文"));
})()''');
      expect(sig, _expectedSigs[algo], reason: algo);
      // signHex 与 sign 同口径（hex 即 JDK 向量的字节序列）。
      expect(
          e.eval('''
(function(){
  var s = java.createSign("$algo").setPrivateKey($priv);
  return s.signHex("hello sign 中文");
})()'''),
          _hexOf(_expectedSigs[algo]!),
          reason: algo);
    }
  });

  test('setter 链式返回同一对象；字节数组入参与字符串一致', () {
    final e = engine();
    final priv = _bytes(base64Decode(_privB64));
    expect(
        e.eval('(function(){'
            'var s=java.createSign("SHA256withRSA");'
            'return String(s.setPrivateKey($priv)===s);})()'),
        'true');
    final expected = _expectedSigs['SHA256withRSA'];
    expect(
        e.eval('''
(function(){
  var s = java.createSign("SHA256withRSA").setPrivateKey($priv);
  return Packages.java.util.Base64.getEncoder().encodeToString(
      s.sign(String("hello sign 中文").getBytes("UTF-8")));
})()'''),
        expected);
  });

  test('verify：原文通过，篡改消息/签名失败，公钥可复验', () {
    final e = engine();
    final priv = _bytes(base64Decode(_privB64));
    final pub = _bytes(base64Decode(_pubB64));
    final sigB64 = _expectedSigs['SHA256withRSA']!;
    expect(
        e.eval('''
(function(){
  var pub = java.createSign("SHA256withRSA").setPublicKey($pub);
  var der = Packages.java.util.Base64.getDecoder().decode("$sigB64");
  return String(pub.verify("hello sign 中文", der));
})()'''),
        'true');
    expect(
        e.eval('''
(function(){
  var pub = java.createSign("SHA256withRSA").setPublicKey($pub);
  var der = Packages.java.util.Base64.getDecoder().decode("$sigB64");
  return String(pub.verify("hello sign 中文!", der));
})()'''),
        'false');
    expect(
        e.eval('''
(function(){
  var pub = java.createSign("SHA256withRSA").setPublicKey($pub);
  var der = Packages.java.util.Base64.getDecoder().decode("$sigB64");
  der[10] = (der[10] + 1) % 256;
  return String(pub.verify("hello sign 中文", der));
})()'''),
        'false');
    // 先签后验：同一对象装载私钥签名，公钥对象复核。
    expect(
        e.eval('''
(function(){
  var s = java.createSign("MD5withRSA").setPrivateKey($priv);
  var pub = java.createSign("MD5withRSA").setPublicKey($pub);
  return String(pub.verify("hello sign 中文", s.sign("hello sign 中文")));
})()'''),
        'true');
  });

  test('缺密钥异常口径与 legado 一致', () {
    final e = engine();
    expect(
        e.eval('(function(){try{'
            'java.createSign("SHA256withRSA").sign("x");'
            'return "no";}catch(e){return String(e);}})()'),
        contains('Private key is required for signing'));
    expect(
        e.eval('(function(){try{'
            'java.createSign("SHA256withRSA").verify("x", [1,2]);'
            'return "no";}catch(e){return String(e);}})()'),
        contains('Public key is required for verification'));
  });

  test('非 RSA 族：构造可用，装载密钥/运算抛 NoSuchAlgorithmException', () {
    final e = engine();
    expect(
        e.eval('(function(){try{'
            'var s=java.createSign("SHA256withECDSA");'
            's.setPrivateKey([1,2,3]);'
            'return "no";}catch(e){return String(e);}})()'),
        contains('NoSuchAlgorithmException'));
    expect(
        e.eval('(function(){try{'
            'java.createSign("MD5withDSA").setPublicKey([1,2,3]);'
            'return "no";}catch(e){return String(e);}})()'),
        contains('NoSuchAlgorithmException'));
    // 非法 RSA DER：setter 抛 InvalidKeySpecException。
    expect(
        e.eval('(function(){try{'
            'java.createSign("SHA256withRSA").setPrivateKey([1,2,3]);'
            'return "no";}catch(e){return String(e);}})()'),
        contains('InvalidKeySpecException'));
  });

  test('算法名大小写不敏感（Signature.getInstance 语义）', () {
    final e = engine();
    final priv = _bytes(base64Decode(_privB64));
    expect(
        e.eval('''
(function(){
  var s = java.createSign("sha256withrsa").setPrivateKey($priv);
  return Packages.java.util.Base64.getEncoder()
      .encodeToString(s.sign("hello sign 中文"));
})()'''),
        _expectedSigs['SHA256withRSA']);
  });
}
