/// 书源图片/媒体请求头：legado 对页面与图片使用同一套 header
/// （`AnalyzeUrl(src, source = bookSource)` → `BaseSource.getHeaderMap` +
/// CookieStore），脚本式 header（`@js:`/`<js>`）在每次取图时用源上下文
/// 求值。NexHub 的静态 header 在适配期已映射到 SiteConfig/AntiHotlinking，
/// 这里补齐运行期才能确定的部分：脚本式 header 与登录 Cookie 覆盖层。
library;

import '../../../core/models/plugin_config.dart';
import '../model/book_source.dart';
import '../shuyuan_adapter.dart';
import 'analyze_url.dart';
import 'source_context.dart';

class ShuyuanImageHeaders {
  /// 注册到 core 层钩子（启动期调用一次）。
  static void register() {
    ShuyuanImageHeaderHooks.resolver = resolve;
  }

  /// 按源缓存解析结果：取图期每张图都会调用，`selectors['xiaoshuo']`
  /// 原图不变则复用（源更新会换 Map 实例，自动失效）。
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

  static bool _isScriptHeader(String header) {
    final lower = header.trimLeft().toLowerCase();
    return lower.startsWith('@js:') || lower.startsWith('<js>');
  }

  static Map<String, String>? resolve(PluginConfig config, String url) {
    if (!config.isShuyuanSource) return null;
    final bookSource = _bookSourceFor(config);
    if (bookSource == null) return null;
    final header = bookSource.header ?? '';
    final hasOverlay =
        ShuyuanSourceContext.persistedCookiesFor(config.id).isNotEmpty ||
            ShuyuanSourceContext.hasPersistedLoginHeaderFor(config.id);
    // 快路径：静态 header 的映射已就绪、无登录覆盖层、URL 无选项串时
    // 无需重建 AnalyzeUrl（封面列表每帧都会走到这里）。
    if (!_isScriptHeader(header) &&
        !hasOverlay &&
        !url.contains(',{')) {
      return null;
    }
    try {
      // 每次取图新建临时上下文：header 脚本可能读取 source 字段/jsLib，
      // 登录覆盖层（Cookie + 登录头）供 resolveRequestHeaders 合并且请求。
      final ctx = ShuyuanSourceContext(config.id)..bindSource(bookSource);
      ShuyuanSourceContext.seedPersistedAuth(ctx);
      return ShuyuanSourceContext.run(ctx, () {
        return AnalyzeUrl(url: url, source: bookSource)
            .resolveRequestHeaders();
      });
    } catch (_) {
      return null;
    }
  }
}
