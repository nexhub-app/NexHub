/// 书源封面字节解码（legado BookSource.coverDecodeJs / ImageUtils.decode）。
///
/// core 图片缓存层不依赖 features 层：启动期由 splash 注入
/// [ShuyuanImageDecodeHooks.coverResolver]（[register]），封面下载完成后
/// 在此按源规则解码原始字节。脚本绑定对齐 legado：
/// - `result`：原始字节的 JS 数字数组（可下标读写、可 `.length`）；
/// - `src`：图片地址；
/// - `book`：书目对象（封面路径无书目上下文，legado 同样传 null）。
///
/// 返回值按 legado「脚本结果即 ByteArray」还原：JS 数组完成值的字符串
/// 形态（`[1, 2, 255]` 或裸逗号串）逐项 `& 0xFF` 后转字节；非数字数组
/// （如返回字符串/对象）视为解码失败（legado 的 `as ByteArray` 同样会
/// 失败），返回 null，由图片加载层按失败处理并进入重试/逐出路径。
library;

import 'dart:typed_data';

import '../../../core/models/plugin_config.dart';
import '../../../core/utils/app_log.dart';
import '../model/book_source.dart';
import '../shuyuan_adapter.dart';
import 'js_engine.dart';
import 'source_context.dart';

class ShuyuanImageDecoder {
  /// 注册到 core 层钩子（启动期调用一次）。
  static void register() {
    ShuyuanImageDecodeHooks.coverResolver = decodeCover;
  }

  static final Map<String, (Object, XiaoshuoBookSource)> _cache = {};

  static XiaoshuoBookSource? _bookSourceFor(PluginConfig config) {
    final raw = config.selectors?['xiaoshuo'];
    if (raw is! Map<String, dynamic>) return null;
    final cached = _cache[config.id];
    if (cached != null && identical(cached.$1, raw)) return cached.$2;
    try {
      final source = ShuyuanAdapter.fromPluginConfig(config);
      if (source == null) return null;
      final bookSource = source.toBookSource();
      _cache[config.id] = (raw, bookSource);
      return bookSource;
    } catch (_) {
      return null;
    }
  }

  /// 封面字节解码：[bytes] 原样返回表示未声明规则；null 表示解码失败。
  static Uint8List? decodeCover(
    PluginConfig config,
    String url,
    Uint8List bytes,
  ) {
    if (!config.isShuyuanSource) return bytes;
    final source = _bookSourceFor(config);
    final rule = source?.coverDecodeJs;
    if (source == null || rule == null || rule.trim().isEmpty) return bytes;
    try {
      final engine = JsEngine.forSource(config.id);
      // 与 header 求值同款临时上下文：封面解码脚本可能读取 source 字段与
      // jsLib，也可能走 java.* 桥；登录覆盖层按持久化 Cookie 注入。
      final ctx = ShuyuanSourceContext(config.id)..bindSource(source);
      ShuyuanSourceContext.persistedCookiesFor(config.id).forEach((k, v) {
        ctx.cookies[k] = Map<String, String>.from(v);
      });
      final out = ShuyuanSourceContext.run(ctx, () {
        return engine.eval(rule, bindings: <String, dynamic>{
          'result': <int>[for (final b in bytes) b],
          'src': url,
          'book': null,
        });
      });
      final decoded = parseByteResult(out);
      if (decoded == null) {
        AppLog.instance.w('[书源封面] coverDecodeJs 未返回字节数组: '
            '源=${source.bookSourceName} url=$url');
      }
      return decoded;
    } catch (e) {
      AppLog.instance.w('[书源封面] coverDecodeJs 执行异常: '
          '源=${source.bookSourceName} url=$url → $e');
      return null;
    }
  }

  /// 解析 JS 完成值为字节数组。运行期数组完成值的字符串形态随 JS 运行时
  /// 而异：QuickJS/JS 引擎多为 `[1, 2, 255]`，部分环境为裸逗号串
  /// `1,2,255`——两种都接受。任何非整数项都视为失败（对应 legado
  /// `as ByteArray` 失败）；负值按 `& 0xFF` 归一（脚本位运算产物）。
  static Uint8List? parseByteResult(String result) {
    var s = result.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('[') && s.endsWith(']')) {
      s = s.substring(1, s.length - 1).trim();
      if (s.isEmpty) return Uint8List(0);
    }
    final parts = s.split(',');
    final out = Uint8List(parts.length);
    for (var i = 0; i < parts.length; i++) {
      final v = int.tryParse(parts[i].trim());
      if (v == null) return null;
      out[i] = v & 0xFF;
    }
    return out;
  }
}
