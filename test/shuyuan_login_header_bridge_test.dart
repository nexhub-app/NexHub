/// source.getLoginHeader/putLoginHeader 等桥接的 legado 语义回归。
///
/// 部分书源的发现页把选项值写进"登录头"通道：`putLoginHeader("#" + JSON)`
/// 存原始字符串，脚本再用 `getLoginHeader()` 取回自行 parse（`#` 是书源
/// 私有约定，legado 原样保存）。桥接若按 Map 处理会丢掉该值，导致选择后
/// 刷新发现页读不到新值、内容不随选择变化。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/java_extensions.dart';
import 'package:nexhub/features/shuyuan/analyze/js_engine.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  setUp(() {
    HttpOverrides.global = null;
    JsEngine.resetPoolForTest();
    JavaFeedback.onLog = null;
    JavaFeedback.onToast = null;
  });

  Future<(ShuyuanSourceContext, JsEngine)> ctxEngine(String id) async {
    final ctx = await ShuyuanSourceContext.forSource(id);
    return (ctx, JsEngine.forSource(id));
  }

  test('putLoginHeader 字符串按 legado 原样存取（含 # 私有前缀）', () async {
    final (ctx, engine) = await ctxEngine('login-header-raw');
    await ShuyuanSourceContext.run(ctx, () async {
      engine.eval(
          'source.putLoginHeader("#" + JSON.stringify({searchselect: "🎥视频"}))');
      expect(ctx.loginHeaderRaw, '#{"searchselect":"🎥视频"}');
      // '#' 前缀不是合法 JSON：legado getLoginHeaderMap() 解析失败 → 空表。
      expect(ctx.loginHeader, isEmpty);
      expect(engine.eval('String(source.getLoginHeader())'),
          '#{"searchselect":"🎥视频"}');
      expect(
          engine.eval(
              r'JSON.parse(String(source.getLoginHeader()).replace(/^#/, "")).searchselect'),
          '🎥视频');
    });
  });

  test('JSON 头字符串落盘并同步请求头 map', () async {
    final (ctx, engine) = await ctxEngine('login-header-json');
    await ShuyuanSourceContext.run(ctx, () async {
      engine.eval('source.putLoginHeader(JSON.stringify({Mode: "video"}))');
      expect(ctx.loginHeaderRaw, '{"Mode":"video"}');
      expect(ctx.loginHeader['Mode'], 'video');
      expect(engine.eval('source.getLoginHeaderMap().Mode'), 'video');
    });
  });

  test('getLoginInfoMap 提供 Java Map 方法并写回宿主', () async {
    final (ctx, engine) = await ctxEngine('login-info-map');
    await ShuyuanSourceContext.run(ctx, () async {
      engine.eval('source.putLoginInfo(JSON.stringify({u: "1"}))');
      expect(ctx.loginInfo['u'], '1');
      expect(engine.eval('source.getLoginInfoMap().get("u")'), '1');
      expect(engine.eval('source.getLoginInfoMap().get("missing") === null'),
          'true');
      engine.eval('source.getLoginInfoMap().put("t", "2")');
      expect(ctx.loginInfo['t'], '2');
      expect(engine.eval('source.getLoginInfoMap().get("t")'), '2');
    });
  });
}
