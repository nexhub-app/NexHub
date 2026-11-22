/// java.createAsymmetricCrypto（RSA）对等测试。
///
/// 固定向量由本地 JCE（JDK）生成，覆盖 legado AsymmetricCrypto 的常用路径：
/// 默认 "RSA"（= RSA/ECB/PKCS1Padding）公私钥双向、NoPadding、字符串密文
/// hex/base64 识别、超过单块上限的分块，OAEP-SHA* 固定向量（MGF1 同主摘要，
/// 与 Android Conscrypt 默认一致）、签名方向的 OAEP 拒绝、非 RSA 变换报错，
/// 以及私钥运算改由宿主计算后的耗时。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';

String _hexOf(String text) =>
    utf8.encode(text).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

String _b64OfHex(String hex) {
  final bytes = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return base64Encode(bytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  JsEngine engine() => JsEngine();

  // 2048-bit 固定密钥（X.509 SPKI / PKCS#8）与密文（本地 JCE 生成，未入库）。
  const pubB64 = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAwBTSHU4Z96PigKrhb0ITr1Kh'
      'hHAYaeLZBXuvBf3KIbbg6BT916joi7gMaeoJJXuyvtOrxTxPrzfY16q94DF6pp5JnURW'
      'UCvIKhir53gOnwQag5LJWKPtbA3Ij36QRV92fT3fY5CRw9hm0qVu09/LdHE7N5jn49AR'
      'hWO/O4MUqs3nXxEWlXvX3pp0pj5bS/QAbC9+cQd32BQ6s+4agrTEw7oyW4hYGRFDaqlh'
      'tz1FgGw8pY6zCVCgmDanoMDAGYCIHT6FpApfYmdNlzPdHUaO7qSUuC2FM6zJIq/swZfA'
      'qzJzMccg5OkXaOCO1OETEtbzxw4MJ2GwStW7kbXpmvruUQIDAQAB';
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
      'uOXXbhHOre/jiQ50iOZZx2g+BLILYy73gtZgZSEpdx1jbrNCmAq7r48PUiPMBi99qA/P'
      'wCCfDkkD2iiv7di8YGEMMpJjmrriAL3MS/jL6akDRn7jqzJNAoGBAMYJF/Ytg0gXLqtq'
      'JD9pxZ+vqzIsLbqyh9+4/AF+LNHBkG0q0pTkvrKJkUjwfWH5cXQOej0US3SoPRO4Y7T4'
      '7KQ7UuRaJdcxRGTmljuzMnwzOS6r8hfynOrlNVR4bGSFSylXNaoL8gLo4R5WniXRafjS'
      'ApeKdn9BdzcybxAJPvLdAoGAcWavbxna9CybrBJxdGX5UYuoNwSGMannrbHihA8HxHUt'
      'Io36VsxvSTf+D8UWJeilxFnU5iHIOU+cvXFRFULUZCjTjClVTHCqgwtEwVN0S3R8L+mo'
      'IG8Oe5+kEPytEIdF0xybpfCtf8chMkpmJ0hisEU+iZy1lJhx6wdV7OBuK+A=';
  // 私钥加密（PKCS#1 type 1）→ 公钥解密。
  const ctPriv1Hex =
      '2b6dde2223747bc9fab083c10162e5df06a6fccf372f19e74d5e18ac87b4543045ad'
      '19ec3506e4009c8442b6c09015ed7801a3981ec73dfbfa0060ebfdd668885540b9fb'
      '056b154e109ebe194be0ab5846dc095c22704bd1e42f01ccf93429bc9a79d00b7cfb'
      '5a17db4567514f5a9c976e7e40839e7fa5c64cfeca232226ae723eb04dad2fa8c0cb'
      '680ea0fa4babe95a03b8fb3887a93ff6680c5bb03f8f4a5e4e6af402f942db31daeb'
      '249daf637aeb72ac00f29272e3036f33c63e86df992f21e576e3facee1fa6e512de6'
      'fca10721c7ff8667fa8297a7c840811e9e15bfbc6669d74848500771681d1095b11a'
      '7fd1be5da010ec870b6a58ffdec2d0aebe83';
  // 公钥加密（PKCS#1 type 2）→ 私钥解密。
  const ctPub2Hex =
      'a4d6fcfa4dc952871c1ea4de12cad099e91e8c44ea7c15aa0b2113c0d7cc37458d46'
      '5b0b0c255a537ce5cad2e5e80af35e3d2f0df59425a4f1e054e439630dcda4a3fc90'
      'd0a6d5645a327a1dc3a25082b0e9b0f0628225e6de28b4c736fbf811e001b64781bd'
      'ba42e8779644943ef84b8f62662e0e6506c3d6b7c75b8721644d25d8b87fafdb5bd6'
      '4a53ec95d799c20c8e168533d2ebeeabdedd8c5f271bf2a4faf647a851f2de0fb8e3'
      'b07bed56c388326b6ca14ce1bc1317584d35510c9f0317d78c6436ca440b84af4a02'
      '98eaf17ce2a75603e419e76b976ad27ef290426984ea3e031548517bed125a741bdc'
      '6472ecea138c7d6984ac5c1e2bc30687cf1b';
  // NoPadding 私钥加密 256 字节原始块（首字节 0，保证小于模数）。
  const ctRawHex =
      '45cc393eb747b44ed89e8e446e98006ee919dd00eec7e012f576bd1fec3d76ca8a55'
      '461e6310c8d0498be99762dee8db9e530dd9b8874bb61d4c8f45c4466d45ecdb5d1f'
      '641480f9aefa47b604cb3419375a12d61eaccd13c564ac167dc4dd91733d6d4f56c8'
      'cb0c63000789abd25a9356a0588f03562319bdc92391853f21ab4ff81318206d42f2'
      '460abe01bc3dbd4b7faab86d8baae898aabd22375c375e4f6933968d207b72dfbdcd'
      'ac07b189d22e00b5ffc2ccb354d8b03219c7257f3de7b977732399ad9725fb01ead1'
      'f87cb92a62d6b1b1c43fce4433ca5ea40bef919478836803fc5fa53e74041178f35d'
      '77e0c7af2428c4d90dbd6be8f01418949b8a';
  // 300 字节明文按 245 字节分块（2 块）后的私钥加密结果。
  const ctLongHex =
      '33a5a445010e120bb24236099a7e32e3affb717884a9052eb74c2fd9876c8f27f411'
      '0f2faedf644ede69aab21269d822fc4bcbdeb86b04e5c5c3be189f559667278f9819'
      'f2a5346e241b4e2bed4bbf8851058c842eedd5cd21b4228a68d5658fce4c834cdb0c'
      '8a5c1ae331083a350ccdadd6f3f8a8912afa7293199ad22699e3c283cd1c848f0d28'
      '7505d051edb9e12ea2e6f0d9a4b679de468c334fde0e216e1b2c9b49935eef40edad'
      '65b87874018ec10229eb60a3b2b2b1e1ffb5be9fefaba6c44595e9182eea1eab848f'
      '1246bd5e4a751ad259d1097c81b2d24780c14ee32482f91589d5ec50049f0ff92251'
      'd0ca64637c588fc834a4b341155898e8c54a992b7571d770c8cac1093409c0d56f25'
      '8110b3b9f3d73dfdc218a5a03a90a9a86e95030c8a96948ba833c4a7179b543d2748'
      '1ccc5544ab301b37718c0eff0095207981ba83cd5a28a97c49ce0644f54af94d4547'
      '02bf1e4568429647bd595cc18c5cdd8543e58cbae093b6db980df463bc14581ba8bd'
      'b638dbc503ce0e91982a63f91c59d6e9dcc9cbf057bf3194b86a72515254c775cf17'
      '30a6ee5750b373fe3386a7297a981b50b0291fb629eaaabcfbe92ae332b012d8512f'
      'bad19934c0a78c6221f5811cdefa2c709109f1f7532b5850366af2a77de46fc7d996'
      '6d8a8582c6d58ea9f381dac0a2f0f08751bee777100f0bf27b55416accac83c78512'
      '77cf';

  // OAEP 固定向量：公钥加密、私钥解密；MGF1 与主摘要相同（Conscrypt 口径）。
  const ctOaepPadding =
      '10ba879c389978776944d1f62d01724edb3ab261334eafb406f0a55f43e2482d3274'
      'd2a017208ad45476bd9dabfb107526c39d4e5f5d963a7f1ff5794d0d769b1888d16'
      'b32cb402902c5bb0ef05a9b64205eec3ee727e1873e222ef8463558b0e59c5f138fb'
      '4dd75f3c838fe6b09fe4ab510311ec9592e926512aab3a7a76a78456db57ed623fb1'
      '8bcb3946a1e5a0c9719be21391005aff95933a038990a0bfa282c534a7bb02bf45a0'
      '4dc6f3a36b203b80a4a88e7211146209d8edf56b1588279e40619818e57292b6ffed'
      '4e49b92a2c83ea597327e5fbaa490181294530e29f6b96a86d2bf557429690fe6d28'
      'd704e08a6e461cf6adbf11aa455285cad1a9a';
  const ctOaepSha1 =
      '7987bd0b8bece8224b5bbec805e31674e6dc680b0950b50603aa15dab185c9fdfde'
      '157a71e243af22ce472c0c6c9d16c576da0e3a72c06d5e27ee2d2893334c38434fba'
      '279d72e45b428838ebf601357f6d09fa528e0d813804df844df1769488f31b824655'
      'c43392ed58d7da1caca1cb0f7be2a20bc9237585df5c14d38a0c3f834f88964f7a15'
      'b7d1d79d4988894f1889619f3c250008e12dd7bb21de4caf9fba1d58313d5a95875c'
      'a1d75c29caf1243a1d165998cda7c364b055a6a65bfc819fc6df9fff823ce67eb722'
      '65aa8c3487c026bd7e7947430d72d36dbfe63ab736f49cbb9dc92a004028eb5296ed'
      '0a4cda38584c5c93cb025795082ee9e09c410';
  const ctOaepSha224 =
      '7ff2247ee524309e9198676347f56cd8834a0466b20328d98d92408509c9eb5616e'
      '5862ca27fbaff561bf48e4a3d7ad1c3b305e9b9e04edb37d4013eac1e5074d260eb0'
      '7258cb54005d407f80829cf056678d9700e925f06ebe54b48e1f47411d5222cccc38'
      '3a5b60e9c34a38a7341a38608eb1058c371e20465b3e48852045918d738b8f62ac19'
      '7ea348c3c2bd4535b6b22ceb92045e70b6241e2990ed02f8ce94788385d4158da29e'
      'a0148c124f649e7ffe4703061d1882be6dc9d771e3404535cbe49280ceda44266d04'
      '14b761bfdf573eddcca29a1874b83ee443e057e7f8cb96edaf6048ef565aacbe232d'
      '0bce00f2632ac7bc67913634b51936eccf185';
  const ctOaepSha256 =
      'a6cfdbd8c7597eab18d8a0916fe837cb53fa1b9a90eedf0f8304f5c5bb2f905995f'
      'b71c4102ec380063e7265bee5a9a1886d9141e9f75d09046308395097757da9098a4'
      '5f8002ded9cc0e6124ce766fba73eac6704bcfa654f96fff110717f396a90a724c22'
      'f76c75d828bd00b1d666c1c716de09b951052496244bb786e6b18dadd1fb683a6f7d'
      'dc77562276f618380811a84010ff27dfb08d00e63c855adad2c76c65a2ce8ed696dc'
      '214e4b89a596257963407cd1f540b90800ca8d2fa0570e322d5a34b6e79f84f9d9b6'
      '5ce88a35c27b870f1fecc99a8316e69ade234fa34b8763260ef5e7df95b89fd7ba2a'
      '892061304612acc388da27c48d1f2694b4d9e';
  const ctOaepSha384 =
      '501375d4f077298ebad817efc0a75d8f3e6d5f41d31a9fc705ecc22a3865847439'
      '205012a1cb309e0b7a7913682ea474448dc5920d04401d8c7920891ebfdbf807a456'
      'b04d359d5e2e5860e757eb7ba873ceb61998c724f21ead5d006ac93b6bc752d9fe72'
      '2c1b06a5f83f5b66db92270c76654533f5bd6174afe3fb4b495ec4cced07eafe2736'
      '6afed429473775476cb28da8065e0edf16e54029d0eae6a287b534f6782599546c3a'
      'f39ec6e95d5e3084cd93e7f2656bf1a59fb95df8fe1285900dbf249547e5949589f7'
      'b3709cf3b5b64bdef1a0eeaf2dc389494ea7c7a3bc1c9ae02f605df5162ff973600a'
      '95122a6f79dc77111591645b5cf683ef2f2808';
  const ctOaepSha512 =
      '460fbebbb128492e77bc3011365b117e5ff4c745bbd9a625290c5958a21913dc630'
      '2b21616e093253b6e4730d0e2cec79e299d989162df7ab7994d3203c9dbd2855bcd'
      'e5f0a5b0f0d0da9031e9c83dbc793df1ba52cae47fffd7646af3aa7d3b06fa4df8e8'
      '3e28e8c7f5ffeae0a16b374c54ee3201789e6a887e850bda323df41ae6beec6e27a6'
      '0adaaf0d3f50542841e142160244abab9aedcc295823de17694d2fb0dc77fd657246'
      '594904d4c4a350f6b61818217dda38c8e913f16fe23701448993ba10a68f92e8f189'
      'd020e0a25d72eb116cbf231e783167b447e8abc2109de95c873805dc2f27fd5b23ff'
      '0c8f899166c8b6423a7d2e22e9b8f7709a4c05';
  // 独立实现（Node/OpenSSL）生成的 SHA-256 + MGF1-SHA256 密文。
  const ctNodeOaepSha256 =
      '0f6ec8056d661a2ce0cc4b345af90183e3e57ff6687ab04546af0d3197c9a877f41b'
      'c82ca52da7aab74021e0cb4ef71ca7ebc4721bcbcf79bb0e22b69281f13e4e7a5943'
      'a1e04a4540692e175a92a2916f48f466b26032624a67586a0312cf03f12122db1118'
      '706caee78785c4f9b1c18499d51a969d1729f187d147bf5569024be534e9beed90f3'
      '5cfda79fafaa85351fdbcc59e4b98dcbb252286f913f1bfa0880cab3073d42c1f4d4'
      'c64a71797933da5be6106d7aa9c3dd29dda1e57cc20e9d80280a73fe5ec7360b9a9'
      'bb45df99b173f5e7b61f5ffb82a485e748750e268ff1d4739c0880e332e785db2f8c'
      '2823ce42cee5c32c9046135e9534626d17e3b';

  const plain = '中文测试ABC123';
  final longText =
      List.generate(300, (i) => String.fromCharCode(65 + i % 26)).join();

  group('java.createAsymmetricCrypto（RSA）', () {
    test('乐读小说形态：SPKI 公钥链式 decryptStr 解私钥加密块', () {
      final e = engine();
      expect(
          e.eval("java.createAsymmetricCrypto('RSA')"
              ".setPublicKey(java.base64DecodeToByteArray('$pubB64'))"
              ".decryptStr('$ctPriv1Hex')"),
          plain);
    });

    test('字符串密文 hex/base64 自动识别；decryptHex/decryptBase64 显式入口', () {
      final e = engine();
      final ctB64 = _b64OfHex(ctPriv1Hex);
      final out = e.eval("(function(){"
          "var c=java.createAsymmetricCrypto('RSA/ECB/PKCS1Padding');"
          "c.setPublicKey(java.base64DecodeToByteArray('$pubB64'));"
          "return [c.decryptStr('$ctPriv1Hex'), c.decryptStr('$ctB64'),"
          "java.hexEncodeToString(c.decryptHex('$ctPriv1Hex')),"
          "java.hexEncodeToString(c.decryptBase64('$ctB64'))].join('|');"
          "})()");
      expect(out, [plain, plain, _hexOf(plain), _hexOf(plain)].join('|'));
    });

    test('公钥加密→私钥解密成功；公钥解 type 2 块按 JCE 报错为空', () {
      final e = engine();
      expect(
          e.eval("java.createAsymmetricCrypto('RSA')"
              ".setPrivateKey(java.base64DecodeToByteArray('$privB64'))"
              ".decryptStr('$ctPub2Hex', false)"),
          plain);
      expect(
          e.eval("java.createAsymmetricCrypto('RSA')"
              ".setPublicKey(java.base64DecodeToByteArray('$pubB64'))"
              ".decryptStr('$ctPub2Hex')"),
          '');
    });

    test('NoPadding 原始块字节一致（公钥解私钥加密）', () {
      final e = engine();
      final rawHex =
          '00${List.generate(254, (i) => (i + 2).toRadixString(16).padLeft(2, '0')).join()}00';
      expect(
          e.eval("java.createAsymmetricCrypto('RSA/ECB/NoPadding')"
              ".setPublicKey(java.base64DecodeToByteArray('$pubB64'))"
              ".decryptHex('$ctRawHex').length"),
          '256');
      expect(
          e.eval("(function(){"
              "var c=java.createAsymmetricCrypto('RSA/ECB/NoPadding');"
              "c.setPublicKey(java.base64DecodeToByteArray('$pubB64'));"
              "return java.hexEncodeToString(c.decryptHex('$ctRawHex'));"
              "})()"),
          rawHex);
    });

    test('NoPadding 短块左补零（Conscrypt 口径），往返保留尾部数据', () {
      final e = engine();
      final out = e.eval("(function(){"
          "var c=java.createAsymmetricCrypto('RSA/ECB/NoPadding');"
          "c.setPublicKey(java.base64DecodeToByteArray('$pubB64'));"
          "c.setPrivateKey(java.base64DecodeToByteArray('$privB64'));"
          "var ct=c.encrypt('abc');"
          "var pt=c.decrypt(ct, false);"
          "return [ct.length, pt.length, pt[253]&0xff, pt[254]&0xff,"
          "pt[255]&0xff].join('|');"
          "})()");
      expect(out, '256|256|97|98|99');
    });

    test('解密分块：300 字节两块的密文按 keySize 逐块还原', () {
      final e = engine();
      expect(
          e.eval("java.createAsymmetricCrypto('RSA')"
              ".setPublicKey(java.base64DecodeToByteArray('$pubB64'))"
              ".decryptStr('$ctLongHex')"),
          longText);
    });

    test('加密分块：超过 k-11 字节拆块且可被私钥还原', () {
      final e = engine();
      final out = e.eval("(function(){"
          "var c=java.createAsymmetricCrypto('RSA');"
          "c.setPublicKey(java.base64DecodeToByteArray('$pubB64'));"
          "c.setPrivateKey(java.base64DecodeToByteArray('$privB64'));"
          "var enc=c.encryptBase64('$longText');"
          "return enc.length + '|' + c.decryptStr(enc, false);"
          "})()");
      final parts = out.split('|');
      expect(parts[0], '684'); // 2 x 256 字节 → base64 684 字符
      expect(parts[1], longText);
    });

    test('未设密钥的调用按异常吞掉（eval 为空串）', () {
      final e = engine();
      expect(
          e.eval("java.createAsymmetricCrypto('RSA').decryptStr('AAAA')"), '');
      expect(
          e.eval("java.createAsymmetricCrypto("
                  "'RSA/ECB/OAEPWithSHA-256AndMGF1Padding').decryptStr('AAAA')"),
          '');
    });

    test('无效密钥 / 坏填充按 JCE 抛错（规则求值为空）', () {
      final e = engine();
      expect(
          e.eval("(function(){"
              "var c=java.createAsymmetricCrypto('RSA');"
              "c.setPublicKey(java.base64DecodeToByteArray('AAAA'));"
              "return 'ok';})()"),
          '');
      final zeroBlock = List.filled(128, '00').join();
      expect(
          e.eval("java.createAsymmetricCrypto('RSA')"
              ".setPublicKey(java.base64DecodeToByteArray('$pubB64'))"
              ".decryptStr('$zeroBlock')"),
          '');
    });

    test('私钥运算由宿主导出（毫秒级，不再是秒级）', () {
      final e = engine();
      final watch = Stopwatch()..start();
      final out = e.eval("java.createAsymmetricCrypto('RSA')"
          ".setPrivateKey(java.base64DecodeToByteArray('$privB64'))"
          ".decryptStr('$ctPub2Hex', false)");
      watch.stop();
      // ignore: avoid_print
      print('TIMING host priv-decrypt: ${watch.elapsedMilliseconds}ms');
      expect(out, plain);
      expect(watch.elapsedMilliseconds, lessThan(5000));
    });
  });

  group('java.createAsymmetricCrypto（OAEP）', () {
    test('OAEP-SHA* 固定向量解密（MGF1 同主摘要）', () {
      final e = engine();
      final vectors = <String, String>{
        'RSA/ECB/OAEPPadding': ctOaepPadding,
        'RSA/ECB/OAEPWithSHA-1AndMGF1Padding': ctOaepSha1,
        'RSA/ECB/OAEPWithSHA-224AndMGF1Padding': ctOaepSha224,
        'RSA/ECB/OAEPWithSHA-256AndMGF1Padding': ctOaepSha256,
        'RSA/ECB/OAEPWithSHA-384AndMGF1Padding': ctOaepSha384,
        'RSA/ECB/OAEPWithSHA-512AndMGF1Padding': ctOaepSha512,
      };
      vectors.forEach((transform, ct) {
        expect(
            e.eval("java.createAsymmetricCrypto('$transform')"
                ".setPrivateKey(java.base64DecodeToByteArray('$privB64'))"
                ".decryptStr('$ct', false)"),
            plain,
            reason: transform);
      });
    });

    test('独立实现（OpenSSL）的 SHA-256 密文可解', () {
      final e = engine();
      expect(
          e.eval("java.createAsymmetricCrypto("
                  "'RSA/ECB/OAEPWithSHA-256AndMGF1Padding')"
              ".setPrivateKey(java.base64DecodeToByteArray('$privB64'))"
              ".decryptStr('$ctNodeOaepSha256', false)"),
          plain);
    });

    test('OAEP 加密→私钥解密，单块 344 字符 base64', () {
      final e = engine();
      final out = e.eval("(function(){"
          "var c=java.createAsymmetricCrypto("
          "'RSA/ECB/OAEPWithSHA-256AndMGF1Padding');"
          "c.setPublicKey(java.base64DecodeToByteArray('$pubB64'));"
          "c.setPrivateKey(java.base64DecodeToByteArray('$privB64'));"
          "var enc=c.encryptBase64('$plain');"
          "return enc.length + '|' + c.decryptStr(enc, false);"
          "})()");
      expect(out, '344|$plain');
    });

    test('OAEP 按 k-2h-2 分块（SHA-1 单块 214 字节）；签名方向被拒绝', () {
      final e = engine();
      final text215 = List.filled(215, 'b').join();
      final split = e.eval("(function(){"
          "var c=java.createAsymmetricCrypto("
          "'RSA/ECB/OAEPWithSHA-1AndMGF1Padding');"
          "c.setPublicKey(java.base64DecodeToByteArray('$pubB64'));"
          "c.setPrivateKey(java.base64DecodeToByteArray('$privB64'));"
          "var enc=c.encryptBase64('$text215');"
          "return enc.length + '|' + c.decryptStr(enc, false);"
          "})()");
      expect(split, '684|$text215');
      final privEnc = e.eval("(function(){"
          "var c=java.createAsymmetricCrypto('RSA/ECB/OAEPPadding');"
          "c.setPublicKey(java.base64DecodeToByteArray('$pubB64'));"
          "c.setPrivateKey(java.base64DecodeToByteArray('$privB64'));"
          "try { c.encryptBase64('x', false); } catch (err) { return ''+err; }"
          "return 'no-error';})()");
      expect(privEnc, contains('Only public keys may be used to encrypt'));
      final pubDec = e.eval("(function(){"
          "var c=java.createAsymmetricCrypto("
          "'RSA/ECB/OAEPWithSHA-256AndMGF1Padding');"
          "c.setPublicKey(java.base64DecodeToByteArray('$pubB64'));"
          "c.setPrivateKey(java.base64DecodeToByteArray('$privB64'));"
          "try { c.decryptStr('$ctOaepSha256'); } catch (err) { return ''+err; }"
          "return 'no-error';})()");
      expect(pubDec, contains('Only private keys may be used to decrypt'));
    });

    test('非 RSA 变换按 NoSuchAlgorithmException 抛出（不再静默空对象）', () {
      final e = engine();
      final msg = e.eval("(function(){"
          "try { java.createAsymmetricCrypto('EC').decrypt('AA'); }"
          "catch (err) { return ''+err; }"
          "return 'no-error';})()");
      expect(msg, contains('NoSuchAlgorithmException'));
    });
  });
}
