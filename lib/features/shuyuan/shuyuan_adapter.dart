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

import 'dart:convert';

import '../../core/models/plugin_config.dart';
import 'analyze/analyze_url.dart';
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
      // 关联书籍模块（legado RelatedBooks）：详情页「猜你喜欢」区经
      // related 路由加载；未声明模块的源不暴露该路由。
      final relatedBooks = source.ruleBookInfo!['relatedBooks']?.toString();
      if (relatedBooks != null && relatedBooks.trim().isNotEmpty) {
        routes['related'] = const RouteConfig(url: '', method: 'GET');
      }
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
      // 显式字段映射（无 raw 的来源：代码内置源、历史存量）。列表必须与
      // [ShuyuanSource] 建模字段同步——漏一个字段，该源转成 PluginConfig 后
      // 运行期就读不到它（段评规则、登录三件套、并发限速、事件回调都曾因此丢失）。
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
        'exploreScreen': source.exploreScreen,
        'tocUrl': source.tocUrl,
        'ruleSearch': source.ruleSearch,
        'ruleBookInfo': source.ruleBookInfo,
        'ruleToc': source.ruleToc,
        'ruleContent': source.ruleContent,
        'ruleExplore': source.ruleExplore,
        'ruleReview': source.ruleReview,
        'homepageModules': source.homepageModules,
        'bookUrlPattern': source.bookUrlPattern,
        'customOrder': source.customOrder,
        'enabledExplore': source.enabledExplore,
        'jsLib': source.jsLib,
        'enabledCookieJar': source.enabledCookieJar,
        'concurrentRate': source.concurrentRate,
        'loginUrl': source.loginUrl,
        'loginUi': source.loginUi,
        'loginCheckJs': source.loginCheckJs,
        'coverDecodeJs': source.coverDecodeJs,
        'variableComment': source.variableComment,
        'lastUpdateTime': source.lastUpdateTime,
        'respondTime': source.respondTime,
        'weight': source.weight,
        'eventListener': source.eventListener,
        'customButton': source.customButton,
      };
    }
    final selectors = <String, dynamic>{
      'xiaoshuo': xiaoshuoSelectors,
    };

    // 书源 header → SiteConfig / AntiHotlinking：legado 对页面与图片/播放
    // 请求使用同一套 header（BaseSource.getHeaderMap 贯穿 AnalyzeUrl 全链路）。
    // 页面请求由 AnalyzeUrl 读原始 header；图片（SourceImage）与播放器读
    // PluginConfig.site / antiHotlinking。不映射会出现「页面 200、封面 403」
    // 的请求指纹割裂（UA 声明丢失被站点 WAF 拦），是在线浏览封面大面积
    // 缺失的主因之一。`@js:`/`<js>` 形式 script header 留到请求期由
    // AnalyzeUrl 求值（此处无活动源上下文，加载全部源时执行脚本会拖慢启动）。
    final declaredHeader = _parseDeclaredHeader(source.header);
    String? headerOf(String name) {
      for (final entry in declaredHeader.entries) {
        if (entry.key.toLowerCase() == name) return entry.value;
      }
      return null;
    }

    final declaredUa = headerOf('user-agent');
    final declaredCookie = headerOf('cookie');
    final declaredReferer = headerOf('referer') ?? headerOf('referrer');
    // UA/Cookie/Referer 由 SiteConfig / AntiHotlinking 的显式字段承载
    // （SourceImage.buildHeaders 会统一覆盖），此处剔除避免同名重复请求头。
    final siteHeaders = <String, String>{
      for (final entry in declaredHeader.entries)
        if (!const <String>{'user-agent', 'cookie', 'referer', 'referrer'}
            .contains(entry.key.toLowerCase()))
          entry.key: entry.value,
    };

    // 反盗链：只透传书源声明的 Referer。legado BaseSource.getHeaderMap 只补
    // UA、不补 Referer；页面请求已按同语义不带默认 Referer，图片/播放若在此
    // 兜底注入 baseUrl 会重新造成指纹割裂——签名图片 CDN（secure= 参数）按
    // 「无 Referer」设计，带 Referer 反而 403，封面（列表/详情）灰屏。
    final antiHotlinking = AntiHotlinkingConfig(
      referer: declaredReferer,
      userAgent: declaredUa,
    );

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
      // 源分发：bookSourceType=2（图片/漫画）→ 漫画模块；
      // 1（音频）/4（视频）→ 媒体栏（走媒体播放管线）；
      // 0 文本与 3 文件暂留小说模块书架形态。
      type: switch (source.bookSourceType) {
        2 => SourceType.mangaSource,
        1 => SourceType.audioSource,
        4 => SourceType.videoSource,
        _ => SourceType.novelSource,
      },
      responseType: 'html',
      site: SiteConfig(
        domain: Uri.tryParse(baseUrl)?.host ?? baseUrl,
        baseUrl: baseUrl,
        userAgent: declaredUa,
        cookies: declaredCookie,
        headers: siteHeaders.isEmpty ? null : siteHeaders,
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

  /// 历史迁移：旧版适配器在源未声明 Referer 时把 `bookSourceUrl` 兜底写入
  /// `antiHotlinking.referer`，该值随配置持久化。这与 legado 语义（只透传
  /// 源声明的 header，不注入任何默认 Referer）不符：携带来源头的图片/播放
  /// 请求会被签名 CDN 按「来源不一致」拒绝——列表与 API 正常，封面/播放却
  /// 全部失败。适配器修复只作用于新导入，已入库配置必须在载入时清理一次。
  ///
  /// 判定条件（全部满足才清理，避免误伤手工配置）：
  /// - 是书源（`selectors['xiaoshuo']` 存在）；
  /// - 存量 Referer 等于 `bookSourceUrl` 或 `site.baseUrl`（旧适配器注入值）；
  /// - 原始源 JSON 的 header 未声明 Referer（脚本式 header 无法静态判定，保留）。
  ///
  /// 原地修改 [configJson]，返回是否发生变更（调用方据此决定回写持久层）。
  static bool migrateLegacyInjectedReferer(Map<String, dynamic> configJson) {
    final selectors = configJson['selectors'];
    if (selectors is! Map) return false;
    final xiaoshuo = selectors['xiaoshuo'];
    if (xiaoshuo is! Map) return false;
    final anti = configJson['antiHotlinking'];
    if (anti is! Map) return false;
    final referer = anti['referer'];
    if (referer is! String || referer.trim().isEmpty) return false;

    String trimSlash(Object? v) =>
        v is String ? v.trim().replaceAll(RegExp(r'/+$'), '') : '';
    final target = trimSlash(referer);
    if (target.isEmpty) return false;
    final bookUrl = trimSlash(xiaoshuo['bookSourceUrl']);
    final site = configJson['site'];
    final baseUrl = site is Map ? trimSlash(site['baseUrl']) : '';
    final isInjected = (bookUrl.isNotEmpty && bookUrl == target) ||
        (baseUrl.isNotEmpty && baseUrl == target);
    if (!isInjected) return false;

    final header = xiaoshuo['header'];
    if (header != null) {
      var text = '';
      if (header is String) {
        text = header;
      } else if (header is Map || header is List) {
        try {
          text = json.encode(header);
        } catch (_) {
          text = header.toString();
        }
      } else {
        text = header.toString();
      }
      final lower = text.trim().toLowerCase();
      // 脚本式 header 可能在运行期算出 Referer，无法静态判定 → 保留。
      if (lower.startsWith('@js:') || lower.startsWith('<js>')) return false;
      // 源自己声明了 Referer → 保留。
      if (lower.contains('referer') || lower.contains('referrer')) return false;
    }

    anti.remove('referer');
    return true;
  }

  /// 解析书源声明的 header（legado 的 JSON 字符串，宽松接受单引号/裸键）。
  /// 脚本式 header（`@js:` / `<js>`）与非 JSON 文本返回空表（请求期由
  /// AnalyzeUrl 处理，行为与映射前一致）。
  static Map<String, String> _parseDeclaredHeader(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return const <String, String>{};
    final lower = text.toLowerCase();
    if (lower.startsWith('@js:') || lower.startsWith('<js>')) {
      return const <String, String>{};
    }
    final parsed = AnalyzeUrl.parseJsonLenient(text);
    if (parsed == null) return const <String, String>{};
    final out = <String, String>{};
    parsed.forEach((key, value) {
      if (value == null) return;
      out[key.toString()] = value.toString();
    });
    return out;
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
