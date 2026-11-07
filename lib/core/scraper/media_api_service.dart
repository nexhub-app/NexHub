/// 媒体 API 服务（Facade）。
///
/// 仅委托 [ResolverRegistry]，不再包含任何站点特定逻辑。
/// 站点解析能力全部下沉到 Builtin/Script/WebView Resolver 或源内嵌脚本。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/category_entry.dart';
import '../models/episode.dart';
import '../models/media_item.dart';
import '../models/novel_block.dart';
import '../models/plugin_config.dart';
import '../resolver/builtin_resolver.dart';
import '../resolver/resolver_registry.dart';
import '../resolver/script_resolver.dart';
import '../resolver/webview_resolver.dart';
import '../services/config_loader.dart';
import 'collect_api_parser.dart';
import 'http_fetcher.dart';

class MediaApiService {
  const MediaApiService(this.registry, {this.scriptResolver});

  final ResolverRegistry registry;

  /// 可注入的脚本解析器（测试用 FakeJsEngine 验证回灌分流）。
  /// 缺省时每次按需新建无状态 [ScriptResolver]（生产路径）。
  final ScriptResolver? scriptResolver;

  Future<List<MediaItem>> fetchApiResults(
    PluginConfig source,
    String apiName, {
    Map<String, String> vars = const {},
    String? extractedUrl,
    String? renderedHtml,
  }) async {
    // 通用路由覆盖钩子（共创式）：调用方可在 `vars` 里放特殊键 `__route`，
    // 覆盖按 category 推断出的 [apiName]。用途：
    // 1. 动态筛选：某筛选分组声明了独立路由（如某源的 `tagSearch`），
    // 选中标签后需切到该路由而非默认 `category`；
    // 2. 首页多板块：某板块声明 `route`（如 `latest` / `rank` / `explore`），
    // 让首页各榜单各自走对应路由。
    // 该键只是「传输约定」，替换 apiName 后即从 vars 剔除，绝不透传给源 URL，
    // 因此对既有源零影响，也无需任何站点特定逻辑。
    var effectiveApi = apiName;
    var effectiveVars = vars;
    if (vars.containsKey('__route')) {
      final override = vars['__route'];
      effectiveVars = Map<String, String>.from(vars)..remove('__route');
      if (override != null &&
          override.isNotEmpty &&
          source.routes.containsKey(override)) {
        effectiveApi = override;
      }
    }
    // 渲染后抽取回灌：WebView 取回的渲染 HTML 复用源选择器或脚本解析，
    // 不再重新触发 WebViewResolver（否则会无限循环渲染、列表永远为空）。
    // hybrid + script override 源（如某示例源）需要把 HTML 喂给脚本
    // 而不是按 selectors 解析；其余声明式源沿用 BuiltinResolver。
    if (renderedHtml != null && renderedHtml.isNotEmpty) {
      // 记录渲染来源 URL，使 WebViewHtmlCache 按「源+路由+URL」维度缓存，
      // 避免 show 各筛选条件 / search 各关键词互相串味（复用同一份陈旧 HTML）。
      final base = ConfigLoader.instance.getActiveMirror(source);
      final renderedUrl = source.resolveRouteUrl(
        effectiveApi,
        activeBaseUrl: base,
        vars: effectiveVars,
      );
      final r = await _resolveFromRenderedHtml(
        source,
        effectiveApi,
        renderedHtml,
        vars: effectiveVars,
        url: renderedUrl,
      );
      return _asItems(r);
    }
    // 验证/抽取流程回灌：WebView 抽取到的真实地址直接复用源选择器解析，
    // 不再重新触发 WebViewResolver（否则会无限循环抽取、列表永远为空）。
    if (extractedUrl != null && extractedUrl.isNotEmpty) {
      // 按源类型派发到正确解析器（hybrid/script 走 ScriptResolver，声明式走
      // BuiltinResolver），避免一律走 BuiltinResolver 导致脚本源抓不到数据。
      if (source.parser.type == 'script' || source.parser.type == 'hybrid') {
        final r = await (scriptResolver ?? ScriptResolver()).resolve(
          source,
          effectiveApi,
          vars: <String, String>{
            ...effectiveVars,
            '__extractedUrl': extractedUrl,
          },
        );
        return _asItems(r);
      }
      final r = await const BuiltinResolver().resolveFromUrl(
        source,
        effectiveApi,
        extractedUrl,
        vars: effectiveVars,
      );
      return _asItems(r);
    }
    // 预解析 URL 回灌（源即插件通用通道）：调用方在 vars 里放 `__extractedUrl`
    // 即表示"已拿到真实可抓取的页面地址"，交给对应解析器（含 hybrid/script
    // 脚本源）直接抓取解析，而不是按路由模板拼 URL。用途："点作者/标签即检索"时，
    // 用详情页抓到的真实落地页链接（如 /manga-author/da-yuan-roron）绕过站点拼音
    // 代号限制。该键仅作传输约定，取出后即从 vars 剔除，不污染脚本上下文。
    final String? preUrl = effectiveVars['__extractedUrl'];
    if (preUrl != null && preUrl.isNotEmpty) {
      final Map<String, String> resolverVars =
          Map<String, String>.from(effectiveVars)..remove('__extractedUrl');
      final r = await registry.find(source, effectiveApi).resolve(
            source,
            effectiveApi,
            vars: <String, String>{...resolverVars, '__extractedUrl': preUrl},
          );
      return _asItems(r);
    }
    final r = await registry.find(source, effectiveApi).resolve(
          source,
          effectiveApi,
          vars: effectiveVars,
        );
    final items = _asItems(r);
    debugPrint(
      '[MediaApiService] fetchApiResults apiName=$effectiveApi count=${items.length}',
    );
    return items;
  }

  /// 拉取某源的分类列表。
  ///
  /// 综合策略：
  /// 1. 静态分类：当源在 `category.categoryEntries` 声明了静态分类列表时，
  /// 直接返回该列表（适用于无 MacCMS API 的 HTML/JSON 爬虫源）；
  /// 2. MacCMS 采集 API 动态分类：当源声明 `category.dynamicCategories` 且存在
  /// `ac=list`/`ac=videolist` 风格路由时，取回该路由 JSON 的 `class` 数组，
  /// 交由 [CollectApiParser.parseCategories] 解析为 [CategoryEntry] 列表；
  /// 3. 其余情况返回空列表（分类栏随之隐藏）。
  ///
  /// 说明：解析器契约 [SourceResolver.resolve] 只返回结构化业务对象（如
  /// `List<MediaItem>`），无法直接拿到含 `class` 的原始 JSON，故此处通过
  /// [HttpFetcher] 取回原始 JSON 再交给 [CollectApiParser]，属通用 MacCMS 处理，
  /// 不含任何站点特定逻辑。
  Future<List<CategoryEntry>> fetchCategories(PluginConfig source) async {
    // 0. 书源（通用书源格式 / shuyuan）：分类声明在 selectors['xiaoshuo'].exploreUrl，
    // 形如「玄幻小说::https://...\n修真小说::https://...」、JSON 数组或
    // `<js>` 动态生成。优先经书源引擎（registry 注入）完整解析——静态正则
    // 解析会跳过含 `<js>` 的 exploreUrl，导致这类源没有任何分类 Tab；
    // 引擎不可用或解析为空时回退静态解析。
    final xiaoshuo = source.selectors?['xiaoshuo'];
    if (xiaoshuo is Map) {
      final engineEntries =
          registry.resolveExploreCategories(source);
      if (engineEntries.isNotEmpty) return engineEntries;
      if (xiaoshuo['exploreUrl'] is String) {
        final entries =
            _parseShuyuanExploreUrl(xiaoshuo['exploreUrl'] as String);
        if (entries.isNotEmpty) return entries;
      }
    }

    // 0.5 动态分类路由（通用通道）：源声明 `categories` 路由（script / jsonpath
    // 均可，解析器自行取数，含鉴权两跳等任意流程），返回 [{id,title}] 列表。
    // 分类集合来自站点接口（源头动态下发），静态 categoryEntries 作为失败兜底。
    // 完全由源声明驱动，不含任何站点逻辑。
    if (source.routes.containsKey('categories')) {
      try {
        final r =
            await registry.find(source, 'categories').resolve(source, 'categories');
        final entries = <CategoryEntry>[];
        if (r is List) {
          for (final e in r) {
            // ScriptResolver 的 default 转换把脚本返回的 [{id,title}] 强转成
            // MediaItem（仅 id/title 有意义）；builtin 路径同样落此结构。
            if (e is! MediaItem) continue;
            final id = e.id.trim();
            final title = e.title.trim();
            if (id.isEmpty || title.isEmpty) continue;
            entries.add(CategoryEntry(id: id, title: title));
          }
        }
        if (entries.isNotEmpty) return entries;
      } on Object {
        // 动态分类失败 → 落到下方静态声明，分类 Tab 不整体失效。
      }
    }

    // 1. 声明式静态分类：selectors.category.categories（如某漫画源）。
    final selCat = source.selectors?['category'];
    if (selCat is Map<String, dynamic>) {
      final cats = selCat['categories'];
      if (cats is List && cats.isNotEmpty) {
        final entries = <CategoryEntry>[];
        for (final e in cats) {
          if (e is! Map) continue;
          final id = (e['id'] ?? '').toString();
          final title = (e['name'] ?? e['title'] ?? '').toString();
          if (title.isEmpty) continue;
          entries.add(CategoryEntry(id: id, title: title));
        }
        if (entries.isNotEmpty) return entries;
      }

      // 2. 声明式 MacCMS 动态分类：selectors.category.dynamicCategories
      // （如 hhzyapi 动漫），走既有采集 API 动态分类路径。
      final dyn = selCat['dynamicCategories'];
      final dynamicCategories = dyn is bool
          ? dyn
          : dyn is String
              ? dyn == 'true'
              : false;
      if (dynamicCategories) {
        final entries = await _fetchCollectCategories(source);
        if (entries.isNotEmpty) return entries;
      }
    }

    // 3. 兜底：顶层 category.*（既有行为）。
    final staticEntries = source.category.categoryEntries;
    if (staticEntries.isNotEmpty) {
      return staticEntries
          .map((e) => CategoryEntry(
                id: e['id'] ?? '',
                // 兼容 `name`：`CategoryEntry.fromJson` 已支持 name/title/
                // type_name 多种写法，静态分类声明同样应容错，否则源写了
                // `name` 时会得到一批空白 Tab（字段名不匹配导致）。
                title: e['title'] ?? e['name'] ?? '',
              ))
          .toList(growable: false);
    }
    if (!source.category.dynamicCategories) return const <CategoryEntry>[];
    return _fetchCollectCategories(source);
  }

  /// 解析某源的首页板块列表（共创式：源自行声明 `homeSections`）。
  ///
  /// - 源声明了 `homeSections` → 原样返回（顺序即竖向堆叠顺序）。
  /// - 未声明 → 回退单块「最新更新」（有 latest 路由用 latest，否则 explore），
  /// 与旧版首页行为一致，保证既有源零改动仍可用。
  ///
  /// 说明：板块的实际内容抓取仍由调用方（UI）复用 [fetchApiResults] 完成，
  /// 以复用其 WebView 验证 / 渲染回灌流程；此处只负责解析板块配置，不发网络。
  List<HomeSectionConfig> resolveHomeSections(PluginConfig source) {
    if (source.homeSections.isNotEmpty) return source.homeSections;
    // 兜底：源未显式声明 homeSections 时，从「分类」自动生成首页板块。
    // 分类已作为 Tab 栏显示，但首页板块是「竖向堆叠的榜单」，二者维度不同；
    // 自动生成可让既有源（尤其用户早已导入、无 homeSections 的旧源）也拥有
    // 多板块首页，无需重新导入。源显式声明 homeSections 时优先使用（上方已判断）。
    return _autoHomeSections(source);
  }

  /// 兜底首页板块生成：源未声明 [PluginConfig.homeSections] 时，
  /// 从其静态分类（selectors.category.categories）自动派生竖向堆叠板块。
  ///
  /// 设计要点（与「共创式/源即插件」一致）：
  /// - 顶部恒为「最新更新」（latest 优先，缺失用 explore），对应旧版单块行为；
  /// - 其余每个非汇总分类生成一块，复用 `category` 路由 + {category} 占位符；
  /// - 跳过「全部/汇总」类项（这些本就是分类 Tab 首项，不应再成为板块）；
  /// - 分类过多时截断（默认 8 块），避免首页过长；
  /// - 全程同步、不触发网络，保证冷启动即可见。
  ///
  /// 返回空列表的极端情况（既无 latest/explore 也无 category 路由）交由 UI 空态处理。
  List<HomeSectionConfig> _autoHomeSections(PluginConfig source) {
    final sections = <HomeSectionConfig>[];

    // 1. 顶部「最新更新」。
    if (source.routes.containsKey('latest')) {
      sections.add(const HomeSectionConfig(id: 'latest', route: 'latest'));
    } else if (source.routes.containsKey('explore')) {
      sections.add(const HomeSectionConfig(id: 'explore', route: 'explore'));
    }

    // 2. 每个分类一块（需存在 category 路由）。
    if (source.routes.containsKey('category')) {
      final selCat = source.selectors?['category'];
      final rawCats = selCat is Map ? selCat['categories'] : null;
      if (rawCats is List) {
        var added = 0;
        const maxCatSections = 8;
        for (final e in rawCats) {
          if (e is! Map) continue;
          final id = (e['id'] ?? '').toString();
          final title = (e['name'] ?? e['title'] ?? '').toString();
          if (id.isEmpty || title.isEmpty) continue;
          // 跳过「全部/汇总」类项：这些本就是分类 Tab 首项，不应再成为板块。
          final lower = title.toLowerCase();
          if (id == 'manga' ||
              id == 'all' ||
              id == '0' ||
              title == '全部' ||
              lower == 'all' ||
              lower.contains('all')) {
            continue;
          }
          if (added >= maxCatSections) break;
          sections.add(HomeSectionConfig(
            id: 'cat_$id',
            route: 'category',
            title: title,
            params: <String, String>{'category': id},
          ));
          added++;
        }
      }
    }

    return sections;
  }

  /// 解析某源的动态筛选分组（共创式：源自行声明 `filters`）。
  ///
  /// - 源声明了 `filters.groups` → 原样返回。
  /// - 未声明 → 从「标签」自动兜底生成筛选分组（**不含分类组**，
  /// 因为分类已作为 Tab 栏显示，筛选项再重复就多余了）：
  /// 1. 标签组：仅当源含 `tagSearch` 路由且 `selectors.category.tags` 非空时生成，
  /// param 从 tagSearch 路由占位符推断（缺省 `keyword`）。
  ///
  /// 兜底分组 `title` 留空，由 UI 按 `id` 映射到 l10n 文案（避免 Dart 硬编码中文）。
  Future<List<FilterGroupConfig>> resolveFilterGroups(
    PluginConfig source,
    String categoryId,
  ) async {
    final declared = source.filters;
    if (declared != null && !declared.isEmpty) {
      // 按当前分类取筛选分组：声明了 byCategory 覆盖则用它（实现「每个分类
      // 筛选各不相同」），否则用全局 groups。再防御性剔除 'category' 组——
      // 分类已作为 Tab 栏显示，筛选面板再重复就多余（真机反馈 #19）。
      return declared
          .groupsFor(categoryId)
          .where((g) => g.id != 'category')
          .toList();
    }

    final groups = <FilterGroupConfig>[];

    // 注意：不再从 fetchCategories 生成"分类"筛选组——这些分类已作为 Tab 栏显示，
    // 再在筛选面板重复只会让用户困惑（真机反馈 #19）。
    // 如果源确实需要独立的"分类"筛选（与 Tab 不同维度的），应在 JSON 里显式声明 filters。

    final selCat = source.selectors?['category'];
    if (selCat is Map &&
        selCat['tags'] is List &&
        source.routes.containsKey('tagSearch')) {
      final tags = <FilterOptionConfig>[];
      for (final t in (selCat['tags'] as List)) {
        if (t is! Map) continue;
        final label = (t['name'] ?? t['title'] ?? '').toString();
        if (label.isEmpty) continue;
        // 标签筛选的 value 必须用站点真实 slug（注入 tagSearch 路由的 {keyword}），
        // 例如某源「古风」真实 slug 是 "gufeng"（无连字符），而非 "gu-feng"；
        // 带连字符或中文名的地址在某些源上返回空壳，导致「筛选解析不到内容/不准确」。
        // label 用中文显示名，保证面板上看到的是人话。
        final id = (t['id'] ?? '').toString();
        final value = id.isNotEmpty ? id : label;
        tags.add(FilterOptionConfig(
          value: value,
          label: label,
        ));
      }
      if (tags.isNotEmpty) {
        groups.add(FilterGroupConfig(
          id: 'tag',
          route: 'tagSearch',
          param: _routePlaceholder(source, 'tagSearch') ?? 'keyword',
          options: tags,
        ));
      }
    }

    return groups;
  }

  /// 取路由 URL 中首个非 `page` 占位符名（如 `{category}` → `category`）。
  /// 用于兜底筛选时推断选项值该代入哪个占位符，不含任何站点特定逻辑。
  String? _routePlaceholder(PluginConfig source, String routeName) {
    final route = source.routes[routeName];
    if (route == null) return null;
    for (final m in RegExp(r'\{(\w+)\}').allMatches(route.url)) {
      final name = m.group(1);
      if (name != null && name != 'page') return name;
    }
    return null;
  }

  /// 走 MacCMS 采集列表路由抓取动态分类（class 数组）。
  Future<List<CategoryEntry>> _fetchCollectCategories(PluginConfig source) async {
    final apiName = _pickCollectListRoute(source);
    if (apiName == null) return const <CategoryEntry>[];
    final base = ConfigLoader.instance.getActiveMirror(source);
    final url = source.resolveRouteUrl(
      apiName,
      activeBaseUrl: base,
      vars: <String, String>{'page': '1'},
    );
    try {
      final json = await HttpFetcher.instance.getJson(
        url,
        referer: source.antiHotlinking.referer ?? base,
      );
      return CollectApiParser.parseCategories(json);
    } on Object {
      // 抓取/解析失败时回退为空分类，不影响内容列表加载。
      return const <CategoryEntry>[];
    }
  }

  /// 解析书源 exploreUrl 的「标题::URL」分类约定（按 \n 或 && 分行）。
  ///
  /// 例：`玄幻小说::https://x.com/xuanhuan/\n修真小说::https://x.com/xiuzhen/`。
  /// 含 `<js>` 的动态分类首版无法解析，跳过；其余纯文本行按 `::` 拆出
  /// 标题与 URL，URL 作为分类 id（供 ShuyuanNovelResolver 回传 exploreCategory）。
  /// 解析书源探索 URL 为分类条目列表。
  ///
  /// 支持两种格式：
  /// - `name::url` 多行/`&&` 分隔
  /// - JSON 数组：`[{"title":"分类名","url":"..."}, ...]`
  ///
  /// 含 `<js>` 的动态分类首版无法解析，跳过。
  static List<CategoryEntry> _parseShuyuanExploreUrl(String exploreUrl) {
    final trimmed = exploreUrl.trim();
    // JSON 数组格式：`[{"title":"..." ,"url":"..."}, ...]`
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      try {
        final decoded = _jsonDecodeAsList(trimmed);
        if (decoded.isNotEmpty) {
          final entries = <CategoryEntry>[];
          for (final item in decoded) {
            if (item is! Map) continue;
            final title = _stringField(item, 'title') ??
                _stringField(item, 'name') ??
                '';
            final url = _stringField(item, 'url') ?? '';
            if (title.isEmpty || url.isEmpty) continue;
            entries.add(CategoryEntry(id: url, title: title));
          }
          if (entries.isNotEmpty) return entries;
        }
      } catch (_) {
        // JSON 解析失败，回退到 name::url 格式解析
      }
    }
    // name::url 格式（多行或 && 分隔）
    final entries = <CategoryEntry>[];
    for (final rawLine in trimmed.split(RegExp(r'\n|&&'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.contains('<js>')) continue; // 首版不支持动态分类脚本
      final idx = line.indexOf('::');
      if (idx < 0) continue;
      final title = line.substring(0, idx).trim();
      final url = line.substring(idx + 2).trim();
      if (title.isEmpty || url.isEmpty) continue;
      entries.add(CategoryEntry(id: url, title: title));
    }
    return entries;
  }

  /// 安全地将 JSON 字符串解析为 List。
  static List<dynamic> _jsonDecodeAsList(String json) {
    final parsed = _jsonDecode(json);
    if (parsed is List) return parsed;
    return const [];
  }

  /// 安全地将 JSON 字符串解析为任意类型。
  static dynamic _jsonDecode(String json) {
    try {
      return jsonDecode(json);
    } catch (_) {
      return null;
    }
  }

  /// 安全地从 Map 中提取字符串字段。
  static String? _stringField(Map map, String key) {
    final v = map[key];
    if (v is String && v.isNotEmpty) return v;
    return null;
  }

  /// 选择加载某分类时应使用的路由名（统一三列表页逻辑，避免重复实现）。
  ///
  /// 优先级：
  /// 1. `category` 非空且源声明了 `category` 路由 → 用 `category`；
  /// 2. 否则 `category` 非空且声明了 `explore` 路由 → 用 `explore`；
  /// 3. 否则回退首页路由（优先 `latest`，缺失时取 routes 首键）。
  ///
  /// 首页 Tab 以 `category = null` 调用，恒走第 3 项回到 `latest`。
  static String routeForCategory(PluginConfig source, String? category) {
    final hasCategory = category != null && category.isNotEmpty;
    if (hasCategory && source.routes.containsKey('category')) {
      return 'category';
    }
    if (hasCategory && source.routes.containsKey('explore')) {
      return 'explore';
    }
    return source.routes.containsKey('latest')
        ? 'latest'
        : (source.routes.isEmpty ? 'latest' : source.routes.keys.first);
  }

  Future<MediaItem> fetchDetail(PluginConfig source, String id,
      {String? detailUrl, String? renderedHtml}) async {
    if (renderedHtml != null && renderedHtml.isNotEmpty) {
      final r = await _resolveFromRenderedHtml(
        source,
        'detail',
        renderedHtml,
        vars: <String, String>{
          'id': id,
          if (detailUrl != null) 'detailUrl': detailUrl,
        },
      );
      return r as MediaItem;
    }
    final r = await registry.find(source, 'detail').resolve(
          source,
          'detail',
          vars: <String, String>{
            'id': id,
            if (detailUrl != null) 'detailUrl': detailUrl,
          },
        );
    return r as MediaItem;
  }

  Future<List<Episode>> fetchEpisodes(
    PluginConfig source,
    String id, {
    String? title,
    String? detailUrl,
    String? renderedHtml,
  }) async {
    if (renderedHtml != null && renderedHtml.isNotEmpty) {
      final r = await _resolveFromRenderedHtml(
        source,
        'episodes',
        renderedHtml,
        vars: <String, String>{
          'id': id,
          if (title != null) 'title': title,
          if (detailUrl != null) 'detailUrl': detailUrl,
        },
      );
      return _asEpisodes(r);
    }
    final r = await registry.find(source, 'episodes').resolve(
          source,
          'episodes',
          vars: <String, String>{
            'id': id,
            if (title != null) 'title': title,
            if (detailUrl != null) 'detailUrl': detailUrl,
          },
        );
    return _asEpisodes(r);
  }

  /// 漫画章节列表（复用 Episode 结构承载 id/title/url）。
  Future<List<Episode>> fetchChapters(PluginConfig source, String id,
      {String? renderedHtml}) async {
    if (renderedHtml != null && renderedHtml.isNotEmpty) {
      final r = await _resolveFromRenderedHtml(
        source,
        'chapters',
        renderedHtml,
        vars: <String, String>{'id': id},
      );
      return _asEpisodes(r);
    }
    final r = await registry.find(source, 'chapters').resolve(
          source,
          'chapters',
          vars: <String, String>{'id': id},
        );
    return _asEpisodes(r);
  }

  /// 小说章节列表（按 `toc` 路由解析，复用 Episode 结构）。
  ///
  /// [onProgress] 为可选渐进回调：超长书目录需多页串行抓取时，解析器会分批
  /// 回传中间章节（如首页 + 每页增量），调用方据此先渲染首屏、后台续抓，
  /// 避免整页被长目录阻塞。最终仍返回合并后的完整列表。
  Future<List<Episode>> fetchNovelChapters(
    PluginConfig source,
    String id, {
    String? renderedHtml,
    void Function(List<Episode>)? onProgress,
  }) async {
    final apiName = source.routes.containsKey('toc') ? 'toc' : 'chapters';
    if (renderedHtml != null && renderedHtml.isNotEmpty) {
      final r = await _resolveFromRenderedHtml(
        source,
        apiName,
        renderedHtml,
        vars: <String, String>{'id': id},
      );
      return _asEpisodes(r);
    }
    final r = await registry.find(source, apiName).resolve(
          source,
          apiName,
          vars: <String, String>{'id': id},
          onProgress: onProgress == null
              ? null
              : (batch) => onProgress(batch.cast<Episode>()),
        );
    return _asEpisodes(r);
  }

  /// 漫画章节图片（按 `images` 路由解析，返回图片 URL 列表）。
  ///
  /// [comicId] 注入 `{id}`/`{mid}`，[chapterId] 注入 `{cid}`。
  Future<List<String>> fetchImages(
    PluginConfig source, {
    required String comicId,
    required String chapterId,
    String? renderedHtml,
  }) async {
    // 章节 id 通常为 "mid@cid" 形式（部分源），从中提取数值型 mid/cid；
    // 同时保留原始 chapterId 供源脚本按需回退使用。
    String mid = comicId;
    String cid = chapterId;
    final atIdx = chapterId.indexOf('@');
    if (atIdx > 0) {
      mid = chapterId.substring(0, atIdx);
      cid = chapterId.substring(atIdx + 1);
    }
    final imagesVars = <String, String>{
      'id': comicId,
      'mid': mid,
      'cid': cid,
      'chapterId': chapterId,
    };
    if (renderedHtml != null && renderedHtml.isNotEmpty) {
      final r = await _resolveFromRenderedHtml(
        source,
        'images',
        renderedHtml,
        vars: imagesVars,
      );
      return _asStrings(r);
    }
    final r = await registry.find(source, 'images').resolve(
          source,
          'images',
          vars: imagesVars,
        );
    return _asStrings(r);
  }

  Future<VideoResult> fetchVideoUrl(PluginConfig source, String episodeUrl,
      {String? renderedHtml}) async {
    if (renderedHtml != null && renderedHtml.isNotEmpty) {
      final r = await _resolveFromRenderedHtml(
        source,
        'video',
        renderedHtml,
        vars: <String, String>{'url': episodeUrl},
      );
      return r as VideoResult;
    }
    final r = await registry.find(source, 'video').resolve(
          source,
          'video',
          vars: <String, String>{'url': episodeUrl},
        );
    return r as VideoResult;
  }

  /// 小说章节正文（按 `content` 路由解析，返回图文块列表）。
  ///
  /// [novelId] 注入 `{id}`，[chapterUrl] 注入 `{chapter}`/`{url}`。
  /// 返回 [List<NovelBlock>]：文本段与插图共存，供阅读器图文混排。
  Future<List<NovelBlock>> fetchNovelContent(
    PluginConfig source, {
    required String novelId,
    required String chapterUrl,
    String? renderedHtml,
  }) async {
    if (renderedHtml != null && renderedHtml.isNotEmpty) {
      final r = await _resolveFromRenderedHtml(
        source,
        'content',
        renderedHtml,
        vars: <String, String>{
          'id': novelId,
          'chapter': chapterUrl,
          'url': chapterUrl,
        },
      );
      return _asBlocks(r);
    }
    final r = await registry.find(source, 'content').resolve(
          source,
          'content',
          vars: <String, String>{
            'id': novelId,
            'chapter': chapterUrl,
            'url': chapterUrl,
          },
        );
    return _asBlocks(r);
  }

  List<MediaItem> _asItems(dynamic r) {
    if (r is List<MediaItem>) return r;
    if (r is List) return [for (final e in r) if (e is MediaItem) e];
    return const [];
  }

  List<Episode> _asEpisodes(dynamic r) {
    if (r is List<Episode>) return r;
    if (r is List) return [for (final e in r) if (e is Episode) e];
    return const [];
  }

  List<NovelBlock> _asBlocks(dynamic r) {
    if (r is List<NovelBlock>) return r;
    if (r is List<String>) return [for (final e in r) NovelTextBlock(e)];
    if (r is List) {
      return [
        for (final e in r)
          if (e is NovelBlock)
            e
          else if (e is String)
            NovelTextBlock(e),
      ];
    }
    return const [];
  }

  List<String> _asStrings(dynamic r) {
    if (r is List<String>) return r;
    if (r is List) return [for (final e in r) if (e is String) e];
    return const [];
  }

  /// 判断源对指定 API 是否为 hybrid + script override（如某示例源）。
  ///
  /// 此类源的脚本期望把渲染后 HTML 作为 `raw` 参数传入（替代脚本内
  /// `ctx.http.get(url)` 抓未渲染 HTML 的路径），因此回灌 renderedHtml 时
  /// 必须路由到 [ScriptResolver.resolveFromHtml]，而非 [BuiltinResolver]
  /// 按 selectors 解析（hybrid + script 源的 selectors 不可靠/缺失）。
  bool _isHybridScriptSource(PluginConfig source, String apiName) {
    if (source.parser.type != 'hybrid') return false;
    final override = source.parser.overrides?[apiName];
    return override?.type == 'script';
  }

  /// 渲染后 HTML 回灌分流：按源类型选择 resolver。
  ///
  /// - hybrid + script override → [ScriptResolver.resolveFromHtml]
  /// （把 HTML 作为 `raw` 喂给脚本入口）。
  /// - 其余（builtin/xpath/jsonpath/css 等）→ [BuiltinResolver.resolveFromHtml]
  /// （按 selectors 解析）。
  ///
  /// 不再触发 `WebViewResolver` 或 `ScriptResolver.resolve`，避免回灌循环。
  Future<dynamic> _resolveFromRenderedHtml(
    PluginConfig source,
    String apiName,
    String renderedHtml, {
    Map<String, String> vars = const {},
    String? url,
  }) {
    // 缓存本次验证回灌的渲染 HTML：同 (源, 路由, URL) 后续请求（刷新 / 重新进入 /
    // 切选集）可直接复用，不再反复弹验证页（修复「多个页面需要验证多次」）。
    // 缓存维度为 (source.id, apiName, url)：[url] 非空时不同 URL（如 show 各筛选
    // 条件 / search 各关键词）各自独立缓存；[url] 为 null（detail/episodes 等
    // 逐资源路由未透传）回退「每路由仅缓存一份」的旧行为，向后兼容。
    WebViewHtmlCache.set(source.id, apiName, renderedHtml, url: url);
    // 书源（xiaoshuo）回灌：必须用其专属解析器（WebBook 静态分析器）解析渲染后
    // HTML，不能路由到 BuiltinResolver（书源无 selectors 形式规则，否则解析为空）。
    if (source.selectors?['xiaoshuo'] is Map<String, dynamic>) {
      return registry.resolveRenderedHtml(source, apiName, renderedHtml, vars: vars);
    }
    // 回灌分流：
    // - hybrid + script override → [ScriptResolver.resolveFromHtml]（把渲染后
    // HTML 作为 `raw` 喂给脚本入口）；
    // - 顶层 `parser.type == 'script'`（非 hybrid 的动漫脚本源）同样必须走脚本解析：这类源 useWebview 触发 WebView 取回
    // 渲染 HTML 后，若误路由到 [BuiltinResolver]，会因脚本源无可用 selectors
    // 而解析为空列表（「媒体解析不到内容」的根因之一）。故此处一并覆盖。
    // - 其余（builtin/xpath/jsonpath/css 等声明式源）→ [BuiltinResolver
    // .resolveFromHtml] 按 selectors 解析渲染后 HTML。
    final useScript =
        source.parser.type == 'script' || _isHybridScriptSource(source, apiName);
    if (useScript) {
      return (scriptResolver ?? ScriptResolver())
          .resolveFromHtml(source, apiName, renderedHtml, vars: vars);
    }
    return const BuiltinResolver()
        .resolveFromHtml(source, apiName, renderedHtml, vars: vars);
  }

  /// 在源路由中找一个 MacCMS 采集列表（`ac=list`/`ac=videolist`）风格的路由名。
  ///
  /// 优先 latest/explore/category 等列表路由，再回退到任意命中采集列表的路由；
  /// `ac=detail` 不返回 `class` 数组，故不纳入。
  String? _pickCollectListRoute(PluginConfig source) {
    const preferred = <String>['latest', 'explore', 'category'];
    for (final name in preferred) {
      final route = source.routes[name];
      if (route != null && _isCollectListUrl(route.url)) {
        return name;
      }
    }
    for (final entry in source.routes.entries) {
      if (_isCollectListUrl(entry.value.url)) {
        return entry.key;
      }
    }
    return null;
  }

  bool _isCollectListUrl(String url) =>
      url.contains('ac=list') || url.contains('ac=videolist');
}
