/// JS 沙箱异步入口的 Phase3 解析回归：async 入口 + crypto 桥，无网络、确定性。
///
/// 本质规律（沉淀口径，无真实站点）：
/// - flutter_js 的 FFI QuickJS 把挂起 JS Promise 包成 pending Dart Future，
///   stringResult 为 "Instance of 'Future<dynamic>'" 且 isPromise 恒 false；
/// - Strategy B 的 async IIFE 重跑 + handlePromise（await rawResult + 20ms 泵）
///   是唯一把该形态落地为 JSON 字符串的通道；
/// - 同步入口不进 Phase3，直接走 Phase2 的严格 JSON 字符串路径。
///
/// 运行（需真 QuickJS DLL 在 PATH）：
/// PATH="/c/Users/yukai/AppData/Local/Pub/Cache/hosted/pub.flutter-io.cn/flutter_js-0.8.7/windows/shared:$PATH" \
///   flutter test test/js_async_entry_phase3_test.dart
library;

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/resolver/js_context.dart';

class _StaticBridge implements JsHostBridge {
  const _StaticBridge();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  String md5(String s) => crypto.md5.convert(utf8.encode(s)).toString();
}

FlutterJsEngine _engine() => FlutterJsEngine(const _StaticBridge(),
    baseUrl: 'https://site.example');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('同步入口：Phase2 直接返回严格 JSON（不进 Phase3）', () async {
    final engine = _engine();
    final out = await engine.run('function f(raw, context) { return {a: 1}; }',
        'f', <dynamic>['x']);
    expect(out, isA<Map<dynamic, dynamic>>());
    expect((out as Map)['a'], 1);
  });

  test('async 入口：await context.crypto.md5 后返回对象，经 Phase3 落地', () async {
    final engine = _engine();
    // async 入口内部走 crypto 桥（Dart 侧 md5 无网络）→ Promise settle →
    // Strategy B（Dart-Future 识别 + handlePromise）必须拿到字符串化结果。
    const script = '''
function parseList(raw, context) {
  return context.crypto.md5(String(raw || '')).then(function (h) {
    return { kind: 'meta', hash: h, echo: raw };
  });
}
''';
    final out = await engine.run(script, 'parseList', <dynamic>['hello']);
    expect(out, isA<Map<dynamic, dynamic>>());
    final map = out as Map<dynamic, dynamic>;
    expect(map['kind'], 'meta');
    expect(map['echo'], 'hello');
    expect(map['hash'], crypto.md5.convert(utf8.encode('hello')).toString(),
        reason: 'md5 桥往返结果应与 Dart 侧基准一致');
  });

  test('async 入口返回 List：Phase3 后仍解码为 List', () async {
    final engine = _engine();
    const script = '''
function parseEpisodes(raw, context) {
  return context.crypto.md5('x').then(function () {
    return [{id: '1', url: 'u1'}, {id: '2', url: 'u2'}];
  });
}
''';
    final out = await engine.run(script, 'parseEpisodes', <dynamic>['']);
    expect(out, isA<List<dynamic>>());
    expect((out as List).length, 2);
  });

  test('async 入口抛错：Phase3 落地为 null（不炸整页）', () async {
    final engine = _engine();
    const script = '''
function parseDetail(raw, context) {
  return context.crypto.md5('x').then(function () {
    throw new Error('boom');
  });
}
''';
    final out = await engine.run(script, 'parseDetail', <dynamic>['']);
    expect(out, isNull,
        reason: 'Phase3-B 的 IIFE catch 应返回 JSON.stringify(null)');
  });
}
