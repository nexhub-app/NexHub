/// 书源图片字节解码（legado ImageUtils.decode）：封面走
/// `BookSource.coverDecodeJs`，正文插图走 `ContentRule.imageDecode`。
///
/// core 图片缓存层不依赖 features 层：启动期由 splash 注入
/// [ShuyuanImageDecodeHooks]（[register]），图片下载完成后在此按源规则
/// 解码原始字节。脚本绑定对齐 legado：
/// - `result`：原始字节的 JS 数字数组（可下标读写、可 `.length`）；
/// - `src`：图片地址；
/// - `book`：书目对象（图片缓存层无书目上下文，legado 封面分支同样传 null）。
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
import '../model/xiaoshuo_book.dart';
import '../shuyuan_adapter.dart';
import 'js_engine.dart';
import 'source_context.dart';

class ShuyuanImageDecoder {
  /// 注册到 core 层钩子（启动期调用一次）。
  static void register() {
    ShuyuanImageDecodeHooks.coverResolver = decodeCover;
    ShuyuanImageDecodeHooks.contentResolver = decodeContent;
    ShuyuanImageDecodeHooks.contentApplies = contentApplies;
  }

  /// 源是否声明 `ruleContent.imageDecode`（core 层缓冲/流式门控）。
  /// 直接读模型字段而不调 `getContentRule()`——后者会懒建规则对象，
  /// 把「未声明任何正文规则」的源误变成有规则。
  static bool contentApplies(PluginConfig config) {
    if (!config.isShuyuanSource) return false;
    final rule = _bookSourceFor(config)?.ruleContent?.imageDecode;
    return rule != null && rule.trim().isNotEmpty;
  }

  static final Map<String, (Object, XiaoshuoBookSource)> _cache = {};

  /// 源最近一次正文解析用的书目（legado `ImageUtils.decode` 的 `book` 绑定：
  /// 正文插图路径把当前 Book 传给脚本，脚本按 `book.name`/`book.variable`
  /// 等分支解密）。
  ///
  /// 图片解码发生在展示期，拿不到解析期的书目上下文，故按源记最近一本；
  /// 同源同时只读多本时可能取到最近打开的一本，仅脚本读 `book.*` 时可见
  /// （旧实现恒为 null，这类分支必然走错）。
  static final Map<String, XiaoshuoBook> _activeBooks = {};

  /// 记录某源当前解析的书目（正文解析入口调用）。
  static void rememberActiveBook(String configId, XiaoshuoBook? book) {
    if (book == null) return;
    _activeBooks[configId] = book;
    if (_activeBooks.length > 16) {
      _activeBooks.remove(_activeBooks.keys.first);
    }
  }

  /// `book` 绑定值：字段镜像对齐 legado Book 实体常用面；无记录返回 null。
  static Map<String, dynamic>? _bookBinding(PluginConfig config) {
    final book = _activeBooks[config.id];
    if (book == null) return null;
    return <String, dynamic>{
      'name': book.name,
      'author': book.author,
      'bookUrl': book.bookUrl,
      'intro': book.intro ?? '',
      'kind': book.kind ?? '',
      'coverUrl': book.coverUrl ?? '',
      'lastChapter': book.lastChapter ?? '',
      'tocUrl': book.tocUrl ?? '',
      'wordCount': book.wordCount ?? '',
      'origin': book.origin ?? '',
      'originName': book.originName ?? '',
      'type': book.type,
      'variable': book.variable ?? '',
    };
  }

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
      // jsLib，也可能走 java.* 桥；登录覆盖层（Cookie + 登录头）按持久化注入。
      final ctx = ShuyuanSourceContext(config.id)..bindSource(source);
      ShuyuanSourceContext.seedPersistedAuth(ctx);
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

  /// 正文插图字节解码（legado `ContentRule.imageDecode`）：绑定
  /// `result`（原始字节的 JS 数字数组）/`src`/`book`（源最近一次正文解析
  /// 的书目快照，见 [rememberActiveBook]）；返回字节数组为解码结果，
  /// 未声明规则原样返回，其余/异常按解码失败返回 null。
  static Uint8List? decodeContent(
    PluginConfig config,
    String url,
    Uint8List bytes,
  ) {
    if (!config.isShuyuanSource) return bytes;
    final source = _bookSourceFor(config);
    final rule = source?.ruleContent?.imageDecode;
    if (source == null || rule == null || rule.trim().isEmpty) return bytes;
    try {
      final engine = JsEngine.forSource(config.id);
      final ctx = ShuyuanSourceContext(config.id)..bindSource(source);
      ShuyuanSourceContext.seedPersistedAuth(ctx);
      final out = ShuyuanSourceContext.run(ctx, () {
        return engine.eval(rule, bindings: <String, dynamic>{
          'result': <int>[for (final b in bytes) b],
          'src': url,
          // legado 正文插图路径把当前 Book 传给脚本（封面分支恒 null）。
          'book': _bookBinding(config),
        });
      });
      final decoded = parseByteResult(out);
      if (decoded == null) {
        AppLog.instance.w('[书源图片] imageDecode 未返回字节数组: '
            '源=${source.bookSourceName} url=$url');
      }
      return decoded;
    } catch (e) {
      AppLog.instance.w('[书源图片] imageDecode 执行异常: '
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
