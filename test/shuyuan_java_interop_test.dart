/// Rhino Java 互操作 shim 对等测试（第二梯队）。
///
/// 覆盖书源语料里高频出现的 Java 库调用：JavaImporter/with 作用域、java.lang
/// String 字节语义、javax.crypto Cipher、java.util（Base64/Arrays/UUID/Map）、
/// hutool、GZIP、java.security（SHA256withRSA/MessageDigest）、okhttp3
/// 确定性重放。全部为合成向量，不访问网络；RSA 期望签名与 GZIP 字节由
/// 本机 Node（OpenSSL/zlib）生成。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  setUp(ShuyuanSourceContext.resetForTest);

  JsEngine engine() => JsEngine();

  test('wtzw 形态：JavaImporter + with 内 AES-CBC 解密', () {
    final out = engine().eval(r'''
var javaImport = new JavaImporter();
javaImport.importPackage(
    Packages.java.lang,
    Packages.javax.crypto.spec,
    Packages.javax.crypto,
    Packages.java.util
);
with(javaImport) {
    function decode(content) {
        var ivEncData = Base64.getDecoder().decode(String(content));
        var key = SecretKeySpec(String("242ccb8230d709e1").getBytes(), "AES");
        var iv = IvParameterSpec(Arrays.copyOfRange(ivEncData, 0, 16));
        var chipher = Cipher.getInstance("AES/CBC/PKCS5Padding");
        chipher.init(2, key, iv);
        return String(chipher.doFinal(Arrays.copyOfRange(ivEncData, 16, ivEncData.length)));
    }
}
decode("MDEyMzQ1Njc4OWFiY2RlZuCtWaP+bXnYobfA0AObzf1hm/Y0GYfxs/Ntn1tGl4k8");
''');
    expect(out, '中文测试ABC123');
  });

  test('with 块内声明的函数跨 eval 可见（jsLib 语义）', () {
    final e = engine();
    e.eval(r'''
var im = new JavaImporter();
im.importPackage(Packages.java.lang, Packages.java.util);
with (im) {
    function b64len(s) { return String(Base64.getDecoder().decode(s).length); }
}
''');
    // 5Lit5paH = 中文，UTF-8 6 字节，Java byte[].length 为 6。
    expect(e.eval('b64len("5Lit5paH")'), '6');
  });

  test('java.lang.String 字节语义与 Base64', () {
    final e = engine();
    expect(
        e.eval('Packages.java.lang.String('
            'Packages.java.util.Base64.getDecoder().decode("5Lit5paH"))'),
        '中文');
    expect(
        e.eval('new Packages.java.lang.String('
            'Packages.java.util.Base64.getDecoder().decode("5Lit5paH"))'
            '.toString()'),
        '中文');
    expect(e.eval('String("中文").getBytes().length'), '6');
    expect(
        e.eval('Packages.java.util.Base64.getEncoder().encodeToString('
            'String("中文").getBytes())'),
        '5Lit5paH');
    expect(e.eval('String(Packages.java.util.Arrays.copyOfRange('
        '[1,2,3,4,5],1,3))'), '2,3');
  });

  test('Cipher AES 加解密往返与不支持算法降级', () {
    final e = engine();
    final out = e.eval(r'''
(function(){
  var key = new Packages.javax.crypto.spec.SecretKeySpec(
      String("242ccb8230d709e1").getBytes(), "AES");
  var iv = new Packages.javax.crypto.spec.IvParameterSpec(
      String("0123456789abcdef").getBytes());
  var enc = Packages.javax.crypto.Cipher.getInstance("AES/CBC/PKCS5Padding");
  enc.init(1, key, iv);
  var ct = enc.doFinal(String("中文测试ABC123").getBytes());
  var dec = Packages.javax.crypto.Cipher.getInstance("AES/CBC/PKCS5Padding");
  dec.init(2, key, iv);
  return new Packages.java.lang.String(dec.doFinal(ct)).toString();
})()''');
    expect(out, '中文测试ABC123');
    expect(
        e.eval('Packages.javax.crypto.Cipher'
            '.getInstance("SM4/ECB/PKCS5Padding").doFinal("x")'),
        '');
  });

  test('设备与集合类：UUID/TextUtils/Build/Thread/System/LinkedHashMap', () {
    final e = engine();
    expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-'
                r'[0-9a-f]{12}$')
            .hasMatch(e.eval('String(Packages.java.util.UUID.randomUUID())')),
        true);
    expect(
        e.eval('String(Packages.android.text.TextUtils.isEmpty(null))'),
        'true');
    expect(e.eval('Packages.android.text.TextUtils.join("-", ["a","b"])'),
        'a-b');
    expect(e.eval('Packages.android.os.Build.MODEL'), 'Pixel 7');
    expect(e.eval('Packages.java.lang.Thread.sleep(5)'), '');
    expect(
        RegExp(r'^\d{13}$')
            .hasMatch(e.eval('Packages.java.lang.System.currentTimeMillis()')),
        true);
    expect(
        e.eval('JSON.stringify('
            'new Packages.java.util.LinkedHashMap({a:1,b:"x"}))'),
        '{"a":1,"b":"x"}');
  });

  test('hutool：Base64/DigestUtil/StrUtil', () {
    final e = engine();
    expect(e.eval('Packages.cn.hutool.core.codec.Base64.encode("中文")'),
        '5Lit5paH');
    expect(
        e.eval('Packages.cn.hutool.core.codec.Base64.decodeStr("5Lit5paH")'),
        '中文');
    expect(
        e.eval('Packages.cn.hutool.crypto.digest.DigestUtil.md5Hex("abc")'),
        e.eval('java.md5Encode("abc")'));
    expect(
        e.eval('Packages.cn.hutool.crypto.digest.DigestUtil.sha256Hex("abc")'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    expect(e.eval('Packages.cn.hutool.core.util.StrUtil.reverse("abc中文")'),
        '文中cba');
  });

  test('GZIP：GZIPInputStream 解压 Node zlib 产物', () {
    final e = engine();
    // zlib.gzipSync('中文测试ABC123-' × 40 + 'tail', level 9)
    const gzB64 =
        'H4sIAAAAAAACCnuyY+2zae3Ptna/WD/V0cnZ0MhY98mo0KjQcBcqSczMAQAom0Ri/AIAAA==';
    final out = e.eval('''
(function(){
  var bytes = Packages.java.util.Base64.getDecoder().decode("$gzB64");
  var gz = new Packages.java.util.zip.GZIPInputStream(
      new Packages.java.io.ByteArrayInputStream(bytes));
  var buf = String(" ").getBytes();
  var out = new Packages.java.io.ByteArrayOutputStream();
  for (;;) {
    var n = gz.read(buf);
    if (n > 0) out.write(buf, 0, n); else { gz.close(); break; }
  }
  return out.toString();
})()''');
    expect(out, '中文测试ABC123-' * 40 + 'tail');
  });

  test('GZIP：ZipUtil.gzip 产物可被 Dart gzip 解压', () {
    final b64 = engine().eval(r'''
Packages.java.util.Base64.getEncoder().encodeToString(
    Packages.cn.hutool.core.util.ZipUtil.gzip("gzip 往返 ok"))''');
    expect(utf8.decode(gzip.decode(base64Decode(b64))), 'gzip 往返 ok');
  });

  test('java.security：SHA256withRSA 与 MessageDigest', () {
    // 2048-bit PKCS#8 私钥（与 asymmetric 测试同钥），期望签名由 Node
    // crypto.sign('sha256') 生成（PKCS#1 v1.5 确定性）。
    const privB64 = 'MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDAFNIdThn3o+KAquFv'
        'QhOvUqGEcBhp4tkFe68F/cohtuDoFP3XqOiLuAxp6gkle7K+06vFPE+vN9jXqr3gMXqm'
        'nkmdRFZQK8gqGKvneA6fBBqDkslYo+1sDciPfpBFX3Z9Pd9jkJHD2GbSpW7T38t0cTs3'
        'mOfj0BGFY787gxSqzedfERaVe9femnSmPltL9ABsL35xB3fYFDqz7hqCtMTDujJbiFgZ'
        'EUNqqWG3PUWAbDyljrMJUKCYNqegwMAZgIgdPoWkCl9iZ02XM90dRo7upJS4LYUzrMki'
        'r+zBl8CrMnMxxyDk6Rdo4I7U4RMS1vPHDgwnYbBK1buRtema+u5RAgMBAAECggEAA9pH'
        'Dpxq6+snF2KWC/e80lbrc28WJkWNCc2dyJZ7D+sNnsoQ/1rdczP5V8SAc3aEMsynFNkt'
        'VfveRxEfJtiHN8FUA6oDuy7toF6HUCi5zlm0OHBgxnzfPbwXCj3FIgcUptVvXh1ftxhn'
        'k5EK5IgIGilNQUO5Xvnk6BKEmup5pyVaLm/m5S/S2hEJNKiWrVDO/lf9P/4rt0eQIIkc'
        '/zxr4a8df9QjBYV8QUCrvuO7mbW944O7H7Bx1RXDod/icGl5M6xBvqWI78hndRi+3LR/'
        'RNktK2WISKbZobtnZBmd1T7gyIr5I7KVS5OrnkLuOpQJkMz/7JG3WTl1Z2CvKk5pewKB'
        'gQDIkZFm6olP7P4fSEEM5AkTSJHSTh+F5Q1Aa2gvLkjHgZEF/EnI5ALCFXdun6INXaPH'
        '920lf3GO2TCotvbqFAMoC6i82ClcD9L8wjnJ8UqWJz1Qy5oosZBGMCtpPtHAXsUi2oJi'
        'RSGSM9dNc+prMG0+kMdo68XpH/IqLLx2FcYuFwKBgQD1KsSpIFbq5gt7sfeX2HyKLRCO'
        'opSmAZRJoAROY9KyjQsMcZ8vW+h5mAJVVQ3t8msNtFb8LC7Qyn6y7vIvjJEF3txM2zW2'
        'oFDimlE74mVWSheC6WuY2Fwjy6hr2QvuBNChkUEbMeWDbFoi6d0lNHLVR7GDFeWaxqE6'
        '9Pm8Kgwv1wKBgFP7sDi56HlRMS+EH8j4C1zJvFWlZMm6GYxp7Rwkc1EmzcUF2ReHcig2'
        'uOXXbhHOre/jiQ50iOZZx2g+BLILYy73gtZgZSEpdx1jbrNCmAq7r48PUiPMBi99aA/P'
        'wCCfDkkD2iiv7di8YGEMMpJjmrriAL3MS/jL6akDRn7jqzJNAoGBAMYJF/Ytg0gXLqtq'
        'JD9pxZ+vqzIsLbqyh9+4/AF+LNHBkG0q0pTkvrKJkUjwfWH5cXQOej0US3SoPRO4Y7T4'
        '7KQ7UuRaJdcxRGTmljuzMnwzOS6r8hfynOrlNVR4bGSFSylXNaoL8gLo4R5WniXRafjS'
        'ApeKdn9BdzcybxAJPvLdAoGAcWavbxna9CybrBJxdGX5UYuoNwSGMannrbHihA8HxHUt'
        'Io36VsxvSTf+D8UWJeilxFnU5iHIOU+cvXFRFULUZCjTjClVTHCqgwtEwVN0S3R8L+mo'
        'IG8Oe5+kEPytEIdF0xybpfCtf8chMkpmJ0hisEU+iZy1lJhx6wdV7OBuK+A=';
    const expectedSig =
        'AzM1s9F9S81qcwtEOF2YIGY4LcCAeHNmh551UrKJJ+pkHw7sYQ0jGipvdn4CQW3Y3YG2'
        'dXpm7S1hy7dOUB/61K7+AjbYDoxYrFjEVDT+9Q2gyAfWNo8JRqxKyHtxGye74cPwI00s'
        'YDa6Nu6O3zNH6EEOg50Wkz6QEZX5g8xFkX7BZTIKQ0Z7Hm/ORgZ+gMkX3xwT9FlWqlxd'
        'YT2t4jvwtS6TfDMOEZCxhIFcU1BIlVaZO94Owv+vjLIEbcbfDBh3m/ZuT3UH/GiCiJ+M'
        'ifi75YZ7CmzIBvHKnVSE9KQdoOskqQXTCBuIcR+X8MZnt7vuDbUUX9bV5h7SfMHX151S'
        'PA==';
    final der = <int>[...base64Decode(privB64)];
    final e = engine();
    final sig = e.eval('''
(function(){
  var k = Packages.java.security.KeyFactory.getInstance("RSA")
      .generatePrivate(new Packages.java.security.spec.PKCS8EncodedKeySpec(
          [${der.join(',')}]));
  var s = Packages.java.security.Signature.getInstance("SHA256withRSA");
  s.initSign(k);
  s.update(String("hello sign 中文").getBytes("UTF-8"));
  return Packages.java.util.Base64.getEncoder().encodeToString(s.sign());
})()''');
    expect(sig, expectedSig);
    expect(
        e.eval('(function(){'
            'var md=Packages.java.security.MessageDigest.getInstance("SHA-256");'
            'md.update(String("abc").getBytes("UTF-8"));'
            'return Packages.java.util.Base64.getEncoder()'
            '.encodeToString(md.digest());})()'),
        'ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=');
  });

  test('okhttp3：GET 缓存命中与 POST 组合重放键', () {
    final ctx = ShuyuanSourceContext('src_1')
      ..ajaxCache['https://x.com/ok'] = 'OKBODY';
    ctx.ajaxMetaCache['https://x.com/ok'] = jsonEncode({
      'code': 200,
      'url': 'https://x.com/ok',
      'headers': {
        'content-type': ['application/json'],
      },
    });
    ShuyuanSourceContext.run(ctx, () {
      final e = engine();
      expect(
          e.eval('(function(){'
              'var r=new Packages.okhttp3.Request.Builder()'
              '.url("https://x.com/ok").get().build();'
              'return new Packages.okhttp3.OkHttpClient()'
              '.newCall(r).execute().body().string();})()'),
          'OKBODY');
      expect(
          e.eval('(function(){'
              'var r=new Packages.okhttp3.Request.Builder()'
              '.url("https://x.com/ok").build();'
              'var p=new Packages.okhttp3.OkHttpClient()'
              '.newCall(r).execute();'
              'return p.code()+"|"+p.header("Content-Type")'
              '+"|"+p.headers().names().join(",");})()'),
          '200|application/json|content-type');
      final ph = e.eval('''
(function(){
  var r = new Packages.okhttp3.Request.Builder().url("https://x.com/post")
      .post(Packages.okhttp3.RequestBody.create('{"a":1}',
          Packages.okhttp3.MediaType.parse("application/json"))).build();
  return new Packages.okhttp3.OkHttpClient().newCall(r).execute().body().string();
})()''');
      expect(RegExp(r'^__AJAX_\d+__$').hasMatch(ph), true, reason: ph);
      expect(ctx.ajaxPending.single,
          allOf(contains('||POST||{"a":1}'), contains('"method":"POST"')));
    });
  });
}
