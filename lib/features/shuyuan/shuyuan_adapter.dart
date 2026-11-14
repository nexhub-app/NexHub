/// 书源到 PluginConfig 的适配器：保留原始规则在 `selectors['xiaoshuo']`
/// 中供 ShuyuanNovelResolver 回写为 XiaoshuoBookSource，同时声明 search/detail/
/// toc/content/explore 路由供 MediaApiService 调度。
///
/// 与旧版（xiaoshuo_adapter）差异：
/// - `PluginType.novelSource` → `SourceType.novelSource`
/// - `parser` 字段在新 PluginConfig 中为必填，默认 `ParserConfig(type: 'builtin')`
/// 但被 ResolverRegistry 识别为 xiaoshuo 源时改走 ShuyuanNovelResolver
/// - 不再把书源规则强制降级为 CSS 选择器，而是原样保留完整规则
library;

import '../../core/models/plugin_config.dart';
import 'shuyuan_source_service.dart';

class ShuyuanAdapter {
  /// 将书源转换为 PluginConfig。
  static PluginConfig toPluginConfig(ShuyuanSource source) {
    final baseUrl = source.bookSourceUrl;
    final routes = <String, RouteConfig>{};

    // 路由声明：URL 留空，由 ShuyuanNovelResolver 通过 WebBook/AnalyzeUrl
    // 自行根据 XiaoshuoBookSource.searchUrl/exploreUrl 等字段解析。
    if (source.searchUrl != null && source.searchUrl!.isNotEmpty) {
      routes['search'] = const RouteConfig(url: '', method: 'GET');
    }
    if (source.ruleBookInfo != null) {
      routes['detail'] = const RouteConfig(url: '', method: 'GET');
    }
    if (source.ruleToc != null) {
      routes['toc'] = const RouteConfig(url: '', method: 'GET');
      routes['chapters'] = const RouteConfig(url: '', method: 'GET');
    }
    if (source.ruleContent != null) {
      routes['content'] = const RouteConfig(url: '', method: 'GET');
    }
    if (source.exploreUrl != null && source.exploreUrl!.isNotEmpty) {
      routes['explore'] = const RouteConfig(url: '', method: 'GET');
      // 没有 searchUrl 时，发现页可作为 latest 回退
      if (!routes.containsKey('search')) {
        routes['search'] = const RouteConfig(url: '', method: 'GET');
      }
    }

    // 'latest' 路由：发现页列表的默认入口（NovelOnlineListScreen 优先调用
    // 'latest'，若缺省则取 routes.keys.first，可能误调到 'search'）。
    // ShuyuanNovelResolver 在 'latest' 上回退到 exploreBook。
    if (routes.containsKey('explore') && !routes.containsKey('latest')) {
      routes['latest'] = const RouteConfig(url: '', method: 'GET');
    } else if (!routes.containsKey('latest') && routes.isNotEmpty) {
      routes['latest'] = routes.values.first;
    }

    // 选择器：优先整图保留原始书源 JSON（P0 导入保真——jsLib/登录三件套/
    // concurrentRate/权重等全部字段随 selectors['xiaoshuo'] 持久化，运行期
    // ShuyuanSource.fromJson 原样解析，未来 legado 新增字段也无需改本层）；
    // 旧存量数据（无 raw）回退到显式字段映射，行为与历史版本一致。
    final Map<String, dynamic> xiaoshuoSelectors;
    final raw = source.raw;
    if (raw != null) {
      xiaoshuoSelectors = Map<String, dynamic>.from(raw);
      // 归一化兜底：运行期链路依赖的关键键确保存在且与解析结果一致
      // （tocUrl 是 fromJson 的合成解析值，原始 JSON 可能没有顶层 tocUrl）。
      xiaoshuoSelectors['bookSourceName'] = source.bookSourceName;
      xiaoshuoSelectors['bookSourceUrl'] = source.bookSourceUrl;
      xiaoshuoSelectors['bookSourceType'] = source.bookSourceType;
      xiaoshuoSelectors['enabled'] = source.enabled;
      if (source.tocUrl != null && source.tocUrl!.isNotEmpty) {
        xiaoshuoSelectors['tocUrl'] = source.tocUrl;
      }
    } else {
      xiaoshuoSelectors = {
        'bookSourceName': source.bookSourceName,
        'bookSourceUrl': source.bookSourceUrl,
        'bookSourceType': source.bookSourceType,
        'bookSourceGroup': source.bookSourceGroup,
        'bookSourceComment': source.bookSourceComment,
        'enabled': source.enabled,
        'header': source.header,
        'searchUrl': source.searchUrl,
        'exploreUrl': source.exploreUrl,
        'tocUrl': source.tocUrl,
        'ruleSearch': source.ruleSearch,
        'ruleBookInfo': source.ruleBookInfo,
        'ruleToc': source.ruleToc,
        'ruleContent': source.ruleContent,
        'ruleExplore': source.ruleExplore,
      };
    }
    final selectors = <String, dynamic>{
      'xiaoshuo': xiaoshuoSelectors,
    };

    // 反盗链：用书源 baseUrl 作为默认 Referer（书源 header 字段也透传到
    // AnalyzeUrl 中由 getStrResponse 处理）。
    final antiHotlinking = AntiHotlinkingConfig(referer: baseUrl);

    // 动态筛选：源声明的 `filters` 原样转为 PluginConfig.filters，
    // MediaApiService.resolveFilterGroups 据此显示发现页筛选按钮。
    final declaredFilters = source.filters;
    final filterConfig = declaredFilters != null
        ? SourceFilterConfig.fromJson(
            Map<String, dynamic>.from(declaredFilters))
        : const SourceFilterConfig();

    final homeSections = source.homeSections
            ?.map((e) => HomeSectionConfig.fromJson(
                Map<String, dynamic>.from(e)))
            .toList(growable: false) ??
        const <HomeSectionConfig>[];

    return PluginConfig(
      id: 'xiaoshuo_${_urlToId(baseUrl)}',
      name: source.bookSourceName,
      // 源分发（P2-4）：bookSourceType=2（图片/漫画）→ 漫画模块消费；
      // 其余（0 文本/1 音频/4 视频）暂留小说模块书架形态。
      type: source.bookSourceType == 2
          ? SourceType.mangaSource
          : SourceType.novelSource,
      responseType: 'html',
      site: SiteConfig(
        domain: Uri.tryParse(baseUrl)?.host ?? baseUrl,
        baseUrl: baseUrl,
      ),
      parser: const ParserConfig(type: 'builtin'),
      routes: routes,
      selectors: selectors,
      antiHotlinking: antiHotlinking,
      filters: filterConfig,
      homeSections: homeSections,
      enabled: source.enabled,
      // legado 语义：发现页与搜索可独立开关（enabledExplore 缺省回退 enabled，
      // 与历史行为一致）。
      enabledExplore: source.enabledExplore ?? source.enabled,
    );
  }

  /// 从 PluginConfig 反向恢复 XiaoshuoBookSource（供 ShuyuanNovelResolver 使用）。
  static ShuyuanSource? fromPluginConfig(PluginConfig config) {
    final xiaoshuo = config.selectors?['xiaoshuo'];
    if (xiaoshuo is! Map<String, dynamic>) return null;
    return ShuyuanSource.fromJson(xiaoshuo);
  }

  /// 判断 PluginConfig 是否为书源（ShuyuanNovelResolver 应处理）。
  static bool isShuyuanSource(PluginConfig config) {
    return config.selectors?['xiaoshuo'] is Map<String, dynamic>;
  }

  static String _urlToId(String url) {
    final id = url
        .replaceAll(RegExp(r'https?://'), '')
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (id.isEmpty) return 'unknown';
    return id.substring(0, 60.clamp(0, id.length));
  }
}
