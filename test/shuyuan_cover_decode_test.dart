/// E5 书源封面解码（coverDecodeJs）回归：
/// - 规则在源 JS 引擎中求值，绑定 result（字节数组）/src/book；
/// - 返回数组按 `& 0xFF` 还原字节；非数组/异常按解码失败返回 null；
/// - 未声明规则时原样返回，非书源源不参与；
/// - core 钩子注册后可直接调用（图片缓存层入口）。
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/features/shuyuan/analyze/image_decoder.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

PluginConfig _config({String? coverDecodeJs, String? jsLib}) {
  final raw = <String, dynamic>{
    'bookSourceUrl': 'https://cover.test/',
    'bookSourceName': 'cover-test',
    'bookSourceType': 0,
    if (coverDecodeJs != null) 'coverDecodeJs': coverDecodeJs,
    if (jsLib != null) 'jsLib': jsLib,
  };
  return ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(raw));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  setUp(() {
    ShuyuanSourceContext.resetForTest();
    ShuyuanImageDecodeHooks.coverResolver = null;
  });

  test('运行时数组完成值两种形态都可解析（解码协议前提）', () {
    final out = JsEngine().eval('var x = [1, 2, 255]; x');
    expect(ShuyuanImageDecoder.parseByteResult(out),
        Uint8List.fromList(<int>[1, 2, 255]));
    expect(ShuyuanImageDecoder.parseByteResult('1,2,255'),
        Uint8List.fromList(<int>[1, 2, 255]));
    expect(ShuyuanImageDecoder.parseByteResult('[0, 255]'),
        Uint8List.fromList(<int>[0, 255]));
  });

  group('parseByteResult', () {
    test('负值按 & 0xFF 归一', () {
      expect(ShuyuanImageDecoder.parseByteResult('0,255,-1,-128'),
          Uint8List.fromList(<int>[0, 255, 255, 128]));
      expect(ShuyuanImageDecoder.parseByteResult('[-1]'),
          Uint8List.fromList(<int>[255]));
    });

    test('空数组 → 空字节；空串/非数字项按失败处理', () {
      expect(ShuyuanImageDecoder.parseByteResult('[]'), Uint8List(0));
      expect(ShuyuanImageDecoder.parseByteResult(''), isNull);
      expect(ShuyuanImageDecoder.parseByteResult('1,abc'), isNull);
      expect(ShuyuanImageDecoder.parseByteResult('[1, abc]'), isNull);
      expect(ShuyuanImageDecoder.parseByteResult('[object Object]'), isNull);
    });
  });

  group('decodeCover', () {
    test('未声明规则时原样返回', () {
      final config = _config();
      final bytes = Uint8List.fromList(<int>[1, 2, 3]);
      expect(ShuyuanImageDecoder.decodeCover(config, 'https://x/c.jpg', bytes),
          same(bytes));
    });

    test('非书源源不参与（原样返回）', () {
      const config = PluginConfig(
        id: 'native-1',
        name: '原生源',
        type: SourceType.mangaSource,
        site: SiteConfig(domain: 'x.test', baseUrl: 'https://x.test'),
        parser: ParserConfig(type: 'builtin'),
      );
      final bytes = Uint8List.fromList(<int>[9]);
      expect(ShuyuanImageDecoder.decodeCover(config, 'https://x/c.jpg', bytes),
          same(bytes));
    });

    test('XOR 规则逐字节解码', () {
      final config = _config(
        coverDecodeJs: 'for (var i = 0; i < result.length; i++) {'
            ' result[i] = result[i] ^ 51; } result',
      );
      final bytes = Uint8List.fromList(<int>[0, 1, 127, 255]);
      final out =
          ShuyuanImageDecoder.decodeCover(config, 'https://x/c.jpg', bytes);
      expect(out, Uint8List.fromList(<int>[51, 50, 76, 204]));
    });

    test('恒等规则 result 原样返回', () {
      final config = _config(coverDecodeJs: 'result');
      final bytes = Uint8List.fromList(<int>[7, 8, 9]);
      final out =
          ShuyuanImageDecoder.decodeCover(config, 'https://x/c.jpg', bytes);
      expect(out, bytes);
    });

    test('规则可读取 src 与 jsLib', () {
      final config = _config(
        jsLib: 'function keyOf(u) { return u.length; }',
        coverDecodeJs: 'result.map(function (b) { return b ^ keyOf(src); })',
      );
      final bytes = Uint8List.fromList(<int>[0, 0]);
      final out = ShuyuanImageDecoder.decodeCover(
          config, 'https://x/c.jpg', bytes); // src 长度 15
      expect(out, Uint8List.fromList(<int>[15, 15]));
    });

    test('返回非数组按解码失败（null）', () {
      final config = _config(coverDecodeJs: '"not-bytes"');
      final bytes = Uint8List.fromList(<int>[1]);
      expect(
          ShuyuanImageDecoder.decodeCover(config, 'https://x/c.jpg', bytes),
          isNull);
    });

    test('脚本抛异常按解码失败（null）', () {
      final config = _config(coverDecodeJs: 'book.name.length');
      final bytes = Uint8List.fromList(<int>[1]);
      expect(
          ShuyuanImageDecoder.decodeCover(config, 'https://x/c.jpg', bytes),
          isNull);
    });
  });

  test('register 后 core 钩子可用并走同一解码', () {
    ShuyuanImageDecoder.register();
    final resolver = ShuyuanImageDecodeHooks.coverResolver;
    expect(resolver, isNotNull);
    final config = _config(coverDecodeJs: 'result');
    final bytes = Uint8List.fromList(<int>[4, 5]);
    expect(resolver!(config, 'https://x/c.jpg', bytes), bytes);
  });
}
