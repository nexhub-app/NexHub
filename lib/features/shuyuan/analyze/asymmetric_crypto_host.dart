/// legado `java.createAsymmetricCrypto` 的宿主侧运算。
///
/// 书源 JS 运行在 QuickJS 沙箱里：没有 BigInt，纯 JS 私钥模幂在 2048 位
/// 密钥上要约 14 秒。脚本侧因此只按（变换/方向/密钥/数据）登记操作并返回
/// 类型占位，[JsEngine] 排空后用 Dart BigInt 在这里计算并回填缓存。
///
/// 语义对齐 JCE / Android Conscrypt：
/// - RSA PKCS#1 v1.5（公钥加密/私钥解密 type 2，私钥加密/公钥解密 type 1）；
/// - NoPadding：单块输入不足密钥长度时左侧补零（两个提供者都是补零而非
///   抛错），超过块长才报 IllegalBlockSize；
/// - OAEP：SHA-1/224/256/384/512，默认 MGF1 与主摘要相同、空标签
///   （Conscrypt 的 `OAEP` 构造把 mgf1Md 置为 defaultMd），私钥加密与
///   公钥解密按签名语义被拒绝；
/// - 分块宽度同 legado AsymmetricCrypto：加密 k-11 / k-2h-2 / k，解密 k。
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/digests/sha1.dart';
import 'package:pointycastle/digests/sha224.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/digests/sha384.dart';
import 'package:pointycastle/digests/sha512.dart';

class AsymmetricCryptoHost {
  static final Random _random = Random.secure();

  /// [op] 字段：`t` 变换名、`o` encrypt/decrypt、`u` 1=用公钥、
  /// `n/e/d/p/q` 密钥参数 hex、`data` 输入 hex。
  ///
  /// 返回 `{'v': 输出 hex}` 或 `{'e': 异常文本}`；脚本重放时按 `e` 抛出，
  /// 供 try/catch 感知与 JCE 同名的异常语义。
  static Map<String, String> execute(Map<String, dynamic> op) {
    try {
      return {'v': _hex(_execute(op))};
    } on _AsymError catch (e) {
      return {'e': e.message};
    } catch (e) {
      return {'e': 'Exception: $e'};
    }
  }

  static Uint8List _execute(Map<String, dynamic> op) {
    final transform = (op['t']?.toString() ?? '').trim();
    final name = transform.isEmpty ? 'RSA' : transform;
    final parts = name.toUpperCase().split('/');
    if (parts[0] != 'RSA') {
      throw _AsymError(
          'NoSuchAlgorithmException: Cannot find any provider supporting $name');
    }
    final scheme = _Scheme.parse(parts.length >= 3 ? parts[2] : 'PKCS1PADDING');
    final encrypt = op['o']?.toString() == 'encrypt';
    final usePub = op['u']?.toString() == '1';
    final key = _RsaKey.fromOp(op);

    if (scheme.kind == _Padding.oaep) {
      if (encrypt && !usePub) {
        throw const _AsymError(
            'InvalidKeyException: Only public keys may be used to encrypt');
      }
      if (!encrypt && usePub) {
        throw const _AsymError(
            'InvalidKeyException: Only private keys may be used to decrypt');
      }
    }

    final data = _fromHex(op['data']?.toString() ?? '');
    final k = key.k;
    if (encrypt) {
      final blockSize = scheme.encryptBlockSize(k);
      if (blockSize < 1) {
        throw _AsymError(
            'InvalidKeyException: Key is too small for ${scheme.label}');
      }
      final out = BytesBuilder(copy: false);
      if (data.isEmpty) {
        out.add(_encryptBlock(key, scheme, Uint8List(0), usePub));
      } else {
        for (var off = 0; off < data.length; off += blockSize) {
          out.add(_encryptBlock(
              key, scheme, Uint8List.sublistView(data, off, min(off + blockSize, data.length)), usePub));
        }
      }
      return out.toBytes();
    }

    if (data.isEmpty && scheme.kind != _Padding.raw) {
      throw const _AsymError('BadPaddingException: Decryption error');
    }
    final out = BytesBuilder(copy: false);
    for (var off = 0; off < data.length; off += k) {
      final end = min(off + k, data.length);
      if (end - off != k && scheme.kind != _Padding.raw) {
        throw const _AsymError('BadPaddingException: Decryption error');
      }
      out.add(_decryptBlock(
          key, scheme, Uint8List.sublistView(data, off, end), usePub));
    }
    if (data.isEmpty) return Uint8List(k);
    return out.toBytes();
  }

  static Uint8List _encryptBlock(
      _RsaKey key, _Scheme scheme, Uint8List chunk, bool usePub) {
    final k = key.k;
    final Uint8List em;
    switch (scheme.kind) {
      case _Padding.raw:
        if (chunk.length > k) {
          throw _AsymError('IllegalBlockSizeException: '
              'Data must not be longer than $k bytes');
        }
        em = _leftPad(chunk, k);
      case _Padding.pkcs1:
        if (chunk.length > k - 11) {
          throw _AsymError('IllegalBlockSizeException: '
              'Data must not be longer than ${k - 11} bytes');
        }
        em = _pkcs1Pad(chunk, k, usePub ? 2 : 1);
      case _Padding.oaep:
        final blockSize = scheme.encryptBlockSize(k);
        if (chunk.length > blockSize) {
          throw _AsymError('IllegalBlockSizeException: '
              'Data must not be longer than $blockSize bytes');
        }
        em = _oaepEncode(chunk, k, scheme);
    }
    return _fixedBytes(_pow(_bigFromBytes(em), key, usePub), k);
  }

  static Uint8List _decryptBlock(
      _RsaKey key, _Scheme scheme, Uint8List chunk, bool usePub) {
    final k = key.k;
    switch (scheme.kind) {
      case _Padding.raw:
        final em = _fixedBytes(
            _pow(_bigFromBytes(_leftPad(chunk, k)), key, usePub), k);
        return em;
      case _Padding.pkcs1:
        final em = _fixedBytes(_pow(_bigFromBytes(chunk), key, usePub), k);
        return _pkcs1Unpad(em, usePub ? 1 : 2);
      case _Padding.oaep:
        final em = _fixedBytes(_pow(_bigFromBytes(chunk), key, usePub), k);
        return _oaepDecode(em, scheme);
    }
  }

  static BigInt _pow(BigInt c, _RsaKey key, bool usePub) {
    final n = key.n;
    if (c >= n) {
      throw const _AsymError('BadPaddingException: Message is larger than modulus');
    }
    if (usePub) return c.modPow(key.e, n);
    final d = key.d;
    if (d == null) {
      throw const _AsymError('InvalidKeyException: RSA private key not set');
    }
    final p = key.p, q = key.q;
    if (p != null && q != null && p > BigInt.one && q > BigInt.one && p * q == n) {
      final m1 = c.modPow(d % (p - BigInt.one), p);
      final m2 = c.modPow(d % (q - BigInt.one), q);
      final h = (m1 - m2) * q.modInverse(p) % p;
      return m2 + h * q;
    }
    return c.modPow(d, n);
  }

  // ── PKCS#1 v1.5 ──
  static Uint8List _pkcs1Pad(Uint8List data, int k, int type) {
    final psLen = k - 3 - data.length;
    final em = Uint8List(k);
    em[1] = type;
    if (type == 1) {
      em.fillRange(2, 2 + psLen, 0xff);
    } else {
      final ps = _randomBytes(psLen);
      for (var i = 0; i < psLen; i++) {
        em[2 + i] = 1 + ps[i] % 255;
      }
    }
    em[2 + psLen] = 0;
    em.setRange(3 + psLen, k, data);
    return em;
  }

  static Uint8List _pkcs1Unpad(Uint8List em, int type) {
    if (em.length < 11 || em[0] != 0 || em[1] != type) {
      throw const _AsymError('BadPaddingException: Decryption error');
    }
    var i = 2;
    while (i < em.length && em[i] != 0) {
      i++;
    }
    if (i >= em.length || i - 2 < 8) {
      throw const _AsymError('BadPaddingException: Decryption error');
    }
    return Uint8List.sublistView(em, i + 1);
  }

  // ── OAEP（RFC 3447，空标签；MGF1 默认同主摘要） ──
  static Uint8List _oaepEncode(Uint8List message, int k, _Scheme scheme) {
    final digest = scheme.digest!;
    final hLen = digest().digestSize;
    final lHash = digest().process(Uint8List(0));
    final dbLen = k - hLen - 1;
    final psLen = dbLen - hLen - 1 - message.length;
    final db = Uint8List(dbLen);
    db.setRange(0, hLen, lHash);
    db[hLen + psLen] = 0x01;
    db.setRange(hLen + psLen + 1, dbLen, message);

    final seed = _randomBytes(hLen);
    final dbMask = _mgf1(digest, seed, dbLen);
    final maskedDb = Uint8List(dbLen);
    for (var i = 0; i < dbLen; i++) {
      maskedDb[i] = db[i] ^ dbMask[i];
    }
    final seedMask = _mgf1(digest, maskedDb, hLen);
    final em = Uint8List(k);
    for (var i = 0; i < hLen; i++) {
      em[1 + i] = seed[i] ^ seedMask[i];
    }
    em.setRange(1 + hLen, k, maskedDb);
    return em;
  }

  static Uint8List _oaepDecode(Uint8List em, _Scheme scheme) {
    final digest = scheme.digest!;
    final hLen = digest().digestSize;
    final k = em.length;
    if (k < 2 * hLen + 2 || em[0] != 0) {
      throw const _AsymError('BadPaddingException: Decryption error');
    }
    final maskedSeed = Uint8List.sublistView(em, 1, 1 + hLen);
    final maskedDb = Uint8List.sublistView(em, 1 + hLen);
    final seedMask = _mgf1(digest, maskedDb, hLen);
    final seed = Uint8List(hLen);
    for (var i = 0; i < hLen; i++) {
      seed[i] = maskedSeed[i] ^ seedMask[i];
    }
    final dbMask = _mgf1(digest, seed, maskedDb.length);
    final db = Uint8List(maskedDb.length);
    for (var i = 0; i < db.length; i++) {
      db[i] = maskedDb[i] ^ dbMask[i];
    }
    final lHash = digest().process(Uint8List(0));
    for (var i = 0; i < hLen; i++) {
      if (db[i] != lHash[i]) {
        throw const _AsymError('BadPaddingException: Decryption error');
      }
    }
    var i = hLen;
    while (i < db.length && db[i] == 0) {
      i++;
    }
    if (i >= db.length || db[i] != 0x01) {
      throw const _AsymError('BadPaddingException: Decryption error');
    }
    return Uint8List.sublistView(db, i + 1);
  }

  static Uint8List _mgf1(
      Digest Function() digest, Uint8List seed, int len) {
    final out = Uint8List(len);
    final input = Uint8List(seed.length + 4)..setRange(0, seed.length, seed);
    var written = 0;
    var counter = 0;
    while (written < len) {
      input[seed.length] = (counter >> 24) & 0xff;
      input[seed.length + 1] = (counter >> 16) & 0xff;
      input[seed.length + 2] = (counter >> 8) & 0xff;
      input[seed.length + 3] = counter & 0xff;
      final block = digest().process(input);
      final take = min(block.length, len - written);
      out.setRange(written, written + take, block);
      written += take;
      counter++;
    }
    return out;
  }

  static Uint8List _randomBytes(int len) {
    final out = Uint8List(len);
    for (var i = 0; i < len; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }

  // ── 工具 ──
  static Uint8List _leftPad(Uint8List data, int k) {
    if (data.length >= k) return data;
    final out = Uint8List(k);
    out.setRange(k - data.length, k, data);
    return out;
  }

  static BigInt _bigFromBytes(Uint8List bytes) {
    if (bytes.isEmpty) return BigInt.zero;
    return BigInt.parse(_hex(bytes), radix: 16);
  }

  static Uint8List _fixedBytes(BigInt value, int len) {
    final out = Uint8List(len);
    var x = value;
    final mask = BigInt.from(0xff);
    for (var i = len - 1; i >= 0; i--) {
      out[i] = (x & mask).toInt();
      x = x >> 8;
    }
    if (x != BigInt.zero) {
      throw const _AsymError('BadPaddingException: Message is larger than modulus');
    }
    return out;
  }

  static String _hex(Uint8List bytes) {
    final out = StringBuffer();
    for (final b in bytes) {
      out.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return out.toString();
  }

  static Uint8List _fromHex(String hexStr) {
    final clean = hexStr.replaceAll(RegExp('[^0-9a-fA-F]'), '');
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static BigInt? _bigFromHex(String? hexStr) {
    if (hexStr == null || hexStr.isEmpty) return null;
    return BigInt.parse(hexStr, radix: 16);
  }
}

enum _Padding { pkcs1, raw, oaep }

class _Scheme {
  final _Padding kind;
  final Digest Function()? _digestFactory;
  final String label;

  const _Scheme._(this.kind, this.label, [this._digestFactory]);

  Digest Function()? get digest => _digestFactory;

  static _Scheme parse(String paddingUpper) {
    switch (paddingUpper) {
      case 'PKCS1PADDING':
      case 'PKCS1':
        return const _Scheme._(_Padding.pkcs1, 'PKCS1Padding');
      case 'NOPADDING':
        return const _Scheme._(_Padding.raw, 'NoPadding');
      case 'OAEPPADDING':
        return _Scheme._(_Padding.oaep, 'OAEPPadding', () => SHA1Digest());
    }
    if (paddingUpper.startsWith('OAEPWITH') &&
        paddingUpper.endsWith('ANDMGF1PADDING')) {
      final md = paddingUpper.substring(8, paddingUpper.length - 14);
      final factory = _digestFor(md);
      if (factory != null) {
        return _Scheme._(_Padding.oaep, paddingUpper, factory);
      }
    }
    throw _AsymError(
        'NoSuchPaddingException: padding not supported: $paddingUpper');
  }

  static Digest Function()? _digestFor(String name) {
    switch (name.replaceAll('-', '')) {
      case 'SHA1':
        return () => SHA1Digest();
      case 'SHA224':
        return () => SHA224Digest();
      case 'SHA256':
        return () => SHA256Digest();
      case 'SHA384':
        return () => SHA384Digest();
      case 'SHA512':
        return () => SHA512Digest();
    }
    return null;
  }

  int encryptBlockSize(int k) {
    switch (kind) {
      case _Padding.raw:
        return k;
      case _Padding.pkcs1:
        return k - 11;
      case _Padding.oaep:
        final hLen = _digestFactory!().digestSize;
        return k - 2 * hLen - 2;
    }
  }
}

class _RsaKey {
  final BigInt n;
  final BigInt e;
  final BigInt? d;
  final BigInt? p;
  final BigInt? q;

  const _RsaKey(this.n, this.e, this.d, this.p, this.q);

  int get k => (n.bitLength + 7) >> 3;

  static _RsaKey fromOp(Map<String, dynamic> op) {
    final n = AsymmetricCryptoHost._bigFromHex(op['n']?.toString());
    final e = AsymmetricCryptoHost._bigFromHex(op['e']?.toString());
    if (n == null || e == null) {
      throw const _AsymError('InvalidKeyException: RSA key not set');
    }
    return _RsaKey(
      n,
      e,
      AsymmetricCryptoHost._bigFromHex(op['d']?.toString()),
      AsymmetricCryptoHost._bigFromHex(op['p']?.toString()),
      AsymmetricCryptoHost._bigFromHex(op['q']?.toString()),
    );
  }
}

class _AsymError implements Exception {
  final String message;
  const _AsymError(this.message);
}
