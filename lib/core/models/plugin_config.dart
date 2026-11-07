/// 源配置模型（PluginConfig）——共创式源码系统的单一自描述单元。
///
/// 一份 JSON 即一个源：声明式 selectors 或内嵌 JS 脚本，社区只写 JSON 即可贡献源，
/// 无需改 Dart、无需重编译。兼容 animeSource / mangaSource / novelSource 三种类型。
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../network/model/source_network_config.dart';
import '../utils/image_decrypt_registry.dart';

/// 源内容类型，决定解析/浏览/详情/播放的统一语义。
enum SourceType {
  animeSource,
  mangaSource,
  novelSource;

  static SourceType? parse(String? raw) {
    return switch (raw) {
      'animeSource' => animeSource,
      'mangaSource' => mangaSource,
      'novelSource' => novelSource,
      _ => null,
    };
  }

  String get apiName {
    return switch (this) {
      SourceType.animeSource => 'animeSource',
      SourceType.mangaSource => 'mangaSource',
      SourceType.novelSource => 'novelSource',
    };
  }
}

/// 源年龄分级（三档）。源 JSON 通过顶层 `ageRating` 字段自行声明；
/// 未声明时按 [general] 处理（最宽松，不受年龄限制开关影响）。
///
/// ```json
/// { "ageRating": "mature" }
/// ```
enum SourceAgeRating {
  /// 全年龄：任何用户均可浏览。
  general,

  /// 青少年（16+）：可能含轻度暴力 / 擦边内容。
  teen,

  /// 成人（18+）：明确的成人 / 限制级内容，年龄限制开启时会被隐藏。
  mature;

  /// 解析源 JSON 中的取值，兼容常见别名写法；无法识别时回退 [general]。
  static SourceAgeRating parse(dynamic raw) {
    if (raw is SourceAgeRating) return raw;
    if (raw == null) return SourceAgeRating.general;
    final String v = raw.toString().trim().toLowerCase();
    if (v.isEmpty) return SourceAgeRating.general;
    return switch (v) {
      'general' || 'all' || 'g' || 'everyone' || 'allages' || '0' || 'safe' =>
        SourceAgeRating.general,
      'teen' || 't' || '13' || '13+' || 'pg13' || 'pg-13' || 'youth' ||
      '16' || '16+' || '1' =>
        SourceAgeRating.teen,
      'mature' || 'm' || 'adult' || '18' || '18+' || 'r18' || 'r-18' ||
      'nsfw' || 'restricted' || '2' =>
        SourceAgeRating.mature,
      _ => SourceAgeRating.general,
    };
  }

  String get apiName {
    return switch (this) {
      SourceAgeRating.general => 'general',
      SourceAgeRating.teen => 'teen',
      SourceAgeRating.mature => 'mature',
    };
  }

  /// 是否属于「年龄限制」内容（开启年龄限制时应被隐藏）。
  bool get isRestricted => this == SourceAgeRating.mature;
}

/// 网络收藏配置（可选 `webFavorite` 段）——源站自有的书架 / 收藏夹。
///
/// 与应用内本地收藏相互独立：本地收藏存在设备上，网络收藏存在源站账号下。
/// 全部为声明式配置，应用不内置任何站点逻辑：
///
/// ```json
/// "webFavorite": {
/// "title": "我的书架",
/// "route": "webFavorite",
/// "url": "/user/bookshelf",
/// "addUrl": "/user/favorite/add?id={id}",
/// "requireLogin": true
/// }
/// ```
///
/// - [route] / [addRoute] 指向 `routes` 中的键，由解析器按常规管线抓取；
/// - [url] / [addUrl] 为网页入口，未提供 route 时以内置浏览器打开，
/// 支持 `{id}` `{detailUrl}` `{title}` 占位符。
class WebFavoriteConfig {
  /// 总开关。声明了该段即默认启用；置 false 可临时停用而不删配置。
  final bool enabled;

  /// 入口标题；为空时使用本地化默认文案「网络收藏」。
  final String? title;

  /// 收藏列表 route 键（在 `routes` 中定义）。
  final String? route;

  /// 收藏页网页地址（无 [route] 时使用，内置浏览器打开）。
  final String? url;

  /// 「加入收藏」route 键。
  final String? addRoute;

  /// 「加入收藏」网页地址模板（无 [addRoute] 时使用）。
  final String? addUrl;

  /// 是否需要先登录源站（仅用于提示，不阻断操作）。
  final bool requireLogin;

  /// 解析收藏列表所用的「列表解析入口」（`parser.overrides` 里的键，如
  /// `search`/`category`/`explore`/`latest`）。收藏页的画廊列表 DOM 通常与搜索
  /// 结果一致，故多数源应设为 `search`；不填则按
  /// explore → category → search → latest 回退。声明式，不内置站点逻辑。
  final String? listEntry;

  /// 是否启用「多文件夹」：为 true 时，从收藏页 HTML 用源的
  /// `parser.overrides.folders` 解析出文件夹列表（标题 + 链接 + favcat 序号），
  /// 网络收藏 Tab 顶栏出现文件夹切换条；「加入网络收藏」也会弹出文件夹选择。
  final bool folders;

  /// 选夹添加配置：声明后「加入网络收藏」会弹出文件夹选择并 POST 到源站，
  /// 而非单纯打开网页。完全声明式，不内置任何站点逻辑。
  final WebFavoriteAddConfig? add;

  const WebFavoriteConfig({
    this.enabled = true,
    this.title,
    this.route,
    this.url,
    this.addRoute,
    this.addUrl,
    this.requireLogin = false,
    this.listEntry,
    this.folders = false,
    this.add,
  });

  factory WebFavoriteConfig.fromJson(Map<String, dynamic> json) =>
      WebFavoriteConfig(
        enabled: json['enabled'] as bool? ?? true,
        title: json['title'] as String?,
        route: json['route'] as String?,
        url: json['url'] as String?,
        addRoute: json['addRoute'] as String?,
        addUrl: json['addUrl'] as String?,
        requireLogin: json['requireLogin'] as bool? ?? false,
        listEntry: json['listEntry'] as String?,
        folders: json['folders'] as bool? ?? false,
        add: json['add'] is Map
            ? WebFavoriteAddConfig.fromJson(
                Map<String, dynamic>.from(json['add'] as Map))
            : null,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'enabled': enabled,
        if (title != null) 'title': title,
        if (route != null) 'route': route,
        if (url != null) 'url': url,
        if (addRoute != null) 'addRoute': addRoute,
        if (addUrl != null) 'addUrl': addUrl,
        'requireLogin': requireLogin,
        if (listEntry != null) 'listEntry': listEntry,
        if (folders) 'folders': folders,
        if (add != null) 'add': add!.toJson(),
      };
}

/// 网络收藏文件夹（源站书架分组），由源的 `parser.overrides.folders` 解析得到。
class WebFavoriteFolder {
  /// 显示名（如 e-hentai 用户自定义收藏夹名）。
  final String title;

  /// 该文件夹的浏览链接（相对基址或绝对地址）。
  final String url;

  /// favcat 序号（用于「加入收藏」POST 的 `{folder}` 占位符替换）。
  final String value;

  /// 该文件夹内的条目数（源解析可选返回，为 null 时 UI 不显示）。
  final int? count;

  const WebFavoriteFolder(
    this.title,
    this.url,
    this.value, {
    this.count,
  });
}

/// 选夹添加配置（声明式）：「加入网络收藏」时弹出文件夹选择，POST 到 [url]。
///
/// [url] 支持 `{detailUrl}` `{id}` `{title}` `{folder}` 占位符；
/// [fields] 表单字段同样支持 `{folder}`（运行时替换为选中的 favcat 序号）。
/// 例（e-hentai）：
/// `{"url":"{detailUrl}","method":"POST","contentType":"form",
/// "fields":{"favcat":"{folder}","favnote":"","apply":"Add to Favorites"}}`。
///
/// JSON API 类源站（提交前要先换 id、要带鉴权头、要读响应判成功）无法用静态
/// 表单描述，此时改用 [route]：指向 `routes` 中的一个脚本端点，由源脚本自行
/// 完成多步请求（可复用 meta 协议的链式跳转与 `comments.login` 鉴权头）。
class WebFavoriteAddConfig {
  /// 提交地址模板（支持占位符）。
  final String? url;

  /// 脚本端点键（`routes` 中的键）。非空时优先于 [url]，走脚本解析器执行。
  ///
  /// 脚本收到的 vars 含 `id` / `title` / `detailUrl` / `baseUrl`。
  final String? route;

  /// 提交方法，目前仅支持 `POST`。
  final String method;

  /// 内容类型：`form` = application/x-www-form-urlencoded。
  final String contentType;

  /// 表单字段；值里的 `{folder}` 会被替换为选中的 favcat 序号。
  final Map<String, String> fields;

  const WebFavoriteAddConfig({
    this.url,
    this.route,
    this.method = 'POST',
    this.contentType = 'form',
    this.fields = const <String, String>{},
  });

  factory WebFavoriteAddConfig.fromJson(Map<String, dynamic> json) =>
      WebFavoriteAddConfig(
        url: json['url'] as String?,
        route: json['route'] as String?,
        method: json['method'] as String? ?? 'POST',
        contentType: json['contentType'] as String? ?? 'form',
        fields: (json['fields'] as Map?)?.map(
              (k, v) => MapEntry(k as String, v as String),
            ) ??
            const <String, String>{},
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (url != null) 'url': url,
        if (route != null) 'route': route,
        'method': method,
        'contentType': contentType,
        'fields': fields,
      };
}

/// 镜像配置（站点主域失效时切换）。
class MirrorConfig {
  final String name;
  final String domain;
  final String baseUrl;

  const MirrorConfig({
    required this.name,
    required this.domain,
    required this.baseUrl,
  });

  factory MirrorConfig.fromJson(Map<String, dynamic> json) => MirrorConfig(
        name: json['name'] as String? ?? '',
        domain: json['domain'] as String? ?? '',
        baseUrl: json['baseUrl'] as String? ?? json['domain'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'domain': domain,
        'baseUrl': baseUrl,
      };
}

/// 站点配置：域名、基址、UA、Cookie、请求头、镜像列表。
class SiteConfig {
  final String domain;
  final String baseUrl;
  final String? userAgent;
  final String? cookies;
  final Map<String, String>? headers;
  final List<MirrorConfig> mirrors;

  /// 发布页地址（站点主域失效时的导航页，可从中提取备用镜像）。
  final String? publishPageUrl;

  /// 发布页镜像提取规则：正则字符串或 CSS 选择器（nullable）。
  final String? publishMirrorSelector;

  const SiteConfig({
    required this.domain,
    required this.baseUrl,
    this.userAgent,
    this.cookies,
    this.headers,
    this.mirrors = const [],
    this.publishPageUrl,
    this.publishMirrorSelector,
  });

  factory SiteConfig.fromJson(Map<String, dynamic> json) => SiteConfig(
        domain: json['domain'] as String? ?? '',
        baseUrl: json['baseUrl'] as String? ?? json['domain'] as String? ?? '',
        userAgent: json['userAgent'] as String?,
        cookies: json['cookies'] as String?,
        headers: (json['headers'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ),
        mirrors: (json['mirrors'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>()
                .map((e) => MirrorConfig.fromJson(e))
                .toList() ??
            const [],
        publishPageUrl: json['publishPageUrl'] as String?,
        publishMirrorSelector: json['publishMirrorSelector'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'domain': domain,
        'baseUrl': baseUrl,
        if (userAgent != null) 'userAgent': userAgent,
        if (cookies != null) 'cookies': cookies,
        if (headers != null) 'headers': headers,
        'mirrors': mirrors.map((e) => e.toJson()).toList(),
        if (publishPageUrl != null) 'publishPageUrl': publishPageUrl,
        if (publishMirrorSelector != null)
          'publishMirrorSelector': publishMirrorSelector,
      };
}

/// 单个路由（latest/explore/category/search/detail/episodes/video/chapters/images/...）。
class RouteConfig {
  final String url;
  final String method;
  final Map<String, String>? headers;
  final Map<String, String>? params;

  /// POST 请求体模板（声明后 method 视为 post）。占位符 `{var}` 同 URL 规则
  /// 直替（不做 URL 编码），供 JSON API 源声明 `{"episode_id":{url}}` 之类的
  /// JSON 体；未声明时 POST 沿用旧机制（URL 查询串拆 form 体）。
  final String? body;
  final String? responseType; // json | html
  final ParserOverride? parser; // 路由级解析覆盖

  const RouteConfig({
    required this.url,
    this.method = 'get',
    this.headers,
    this.params,
    this.body,
    this.responseType,
    this.parser,
  });

  /// 兼容字符串写法：`"https://x/search?q={keyword}"` 与对象写法。
  factory RouteConfig.fromJson(dynamic json) {
    if (json is String) {
      return RouteConfig(url: json);
    }
    final map = json as Map<String, dynamic>;
    return RouteConfig(
      url: map['url'] as String,
      method: map['method'] as String? ?? 'get',
      headers: (map['headers'] as Map?)?.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
      params: (map['params'] as Map?)?.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
      body: map['body'] as String?,
      responseType: map['responseType'] as String?,
      parser: map['parser'] == null
          ? null
          : ParserOverride.fromJson(map['parser'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'method': method,
        if (headers != null) 'headers': headers,
        if (params != null) 'params': params,
        if (body != null) 'body': body,
        if (responseType != null) 'responseType': responseType,
        if (parser != null) 'parser': parser!.toJson(),
      };
}

/// 解析覆盖（hybrid 模式下针对某个 API 单独指定解析方式）。
///
/// golden 源常见写法：`"overrides": { "<api>": { "function": "parseX", "script": "…", "type": "script" } }`。
/// 旧版解析器用 `entrypoints`（Map<api, 函数名>）表达同样的意图；这里同时兼容两种写法：
/// - [function]：针对「当前 api」直接声明的函数名（golden 覆盖写法）。
/// - [entrypoints]：api→函数名 的映射（旧版写法）。
/// 解析时优先 [function]，回退 [entrypoints][apiName]，再回退 apiName 本身（见 ScriptResolver）。
class ParserOverride {
  final String type; // builtin | script
  final Map<String, String>? entrypoints;
  final String? script;
  final String? function; // golden 覆盖写法：此 override 针对当前 api 的入口函数名

  const ParserOverride({
    required this.type,
    this.entrypoints,
    this.script,
    this.function,
  });

  factory ParserOverride.fromJson(Map<String, dynamic> json) => ParserOverride(
        type: json['type'] as String? ?? 'builtin',
        entrypoints: (json['entrypoints'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ),
        script: json['script'] as String?,
        function: json['function'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        if (entrypoints != null) 'entrypoints': entrypoints,
        if (script != null) 'script': script,
        if (function != null) 'function': function,
      };
}

/// 解析器配置：builtin / hybrid / script + 内嵌脚本 + 路由级 overrides。
class ParserConfig {
  final String type; // builtin | hybrid | script
  final Map<String, String>? entrypoints;
  final String? script;
  final Map<String, ParserOverride>? overrides;

  const ParserConfig({
    required this.type,
    this.entrypoints,
    this.script,
    this.overrides,
  });

  factory ParserConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ParserConfig(type: 'builtin');
    return ParserConfig(
      type: json['type'] as String? ?? 'builtin',
      entrypoints: (json['entrypoints'] as Map?)?.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
      script: json['script'] as String?,
      overrides: (json['overrides'] as Map?)?.map(
        (k, v) => MapEntry(
          k.toString(),
          ParserOverride.fromJson(v as Map<String, dynamic>),
        ),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        if (entrypoints != null) 'entrypoints': entrypoints,
        if (script != null) 'script': script,
        if (overrides != null)
          'overrides': overrides!.map((k, v) => MapEntry(k, v.toJson())),
      };

  /// 解析某 API 时实际使用的解析类型（考虑 hybrid overrides）。
  String effectiveTypeFor(String apiName) {
    if (type == 'hybrid' && overrides != null) {
      final o = overrides![apiName];
      if (o != null) return o.type;
    }
    return type;
  }
}

/// 分类配置（MacCMS 动态分类从 `class` 推断；静态分类从 `categoryEntries` 读取）。
class CategoryConfig {
  final bool dynamicCategories;
  final String? categories; // JSONPath / CSS
  final String? id;
  final String? title;
  /// 静态分类列表（适用于无 MacCMS API 的 HTML/JSON 爬虫源）。
  ///
  /// 当 [dynamicCategories] 为 false 且此列表非空时，[MediaApiService.fetchCategories]
  /// 直接返回此列表，分类条即可默认显示。每项形如 `{"id":"1","title":"动作"}`。
  final List<Map<String, String>> categoryEntries;

  const CategoryConfig({
    this.dynamicCategories = false,
    this.categories,
    this.id,
    this.title,
    this.categoryEntries = const <Map<String, String>>[],
  });

  factory CategoryConfig.fromJson(Map<String, dynamic>? json) => CategoryConfig(
        dynamicCategories: json?['dynamicCategories'] as bool? ?? false,
        categories: json?['categories'] as String?,
        id: json?['id'] as String?,
        title: json?['title'] as String?,
        categoryEntries: (json?['categoryEntries'] as List<dynamic>?)
                ?.map((e) => Map<String, String>.from(e as Map))
                .toList(growable: false) ??
            const <Map<String, String>>[],
      );

  Map<String, dynamic> toJson() => {
        'dynamicCategories': dynamicCategories,
        if (categories != null) 'categories': categories,
        if (id != null) 'id': id,
        if (title != null) 'title': title,
        if (categoryEntries.isNotEmpty) 'categoryEntries': categoryEntries,
      };
}

/// 首页板块配置（共创式：源自行声明首页要展示的多个板块）。
///
/// 每个板块复用源已有的 [RouteConfig]（如 latest / category / explore）与对应
/// 解析器，配合 [params] 做占位符替换。这样"网站首页有几个榜单/分区"完全由源
/// 决定，app 只负责竖向堆叠渲染，绝不写死站点逻辑。
///
/// 向后兼容：源未声明 `homeSections` 时，[MediaApiService] 回退为单块「最新更新」
/// （即调用 `latest` 路由），与旧行为一致。
class HomeSectionConfig {
  /// 板块唯一标识（同一源内不重复），也用于「查看更多」跳转定位。
  final String id;

  /// 板块标题（用户可见）。为空时 UI 用 [id] 兜底。
  final String title;

  /// 该板块调用的路由名（须存在于 `routes` 中，如 latest/category/explore）。
  final String route;

  /// 路由占位符替换值（如 `{"category":"hots"}` 替换 `{category}`）。
  final Map<String, String> params;

  /// 展示样式提示：grid（网格，默认）| rank（排行，带序号）| scroll（横向滑动）。
  final String style;

  /// 板块最多展示条目数（0 = 不限制，取解析结果全部）。
  final int limit;

  /// 是否显示「查看更多」入口（跳转到该 route 的完整列表页）。
  final bool more;

  const HomeSectionConfig({
    required this.id,
    this.title = '',
    required this.route,
    this.params = const <String, String>{},
    this.style = 'grid',
    this.limit = 12,
    this.more = true,
  });

  factory HomeSectionConfig.fromJson(Map<String, dynamic> json) =>
      HomeSectionConfig(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        route: json['route'] as String? ?? 'latest',
        params: (json['params'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            ) ??
            const <String, String>{},
        style: json['style'] as String? ?? 'grid',
        limit: (json['limit'] as num?)?.toInt() ?? 12,
        more: json['more'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        if (title.isNotEmpty) 'title': title,
        'route': route,
        if (params.isNotEmpty) 'params': params,
        'style': style,
        'limit': limit,
        'more': more,
      };
}

/// 单个筛选选项（值 + 展示标签）。
class FilterOptionConfig {
  /// 选项值，用于替换该分组 [FilterGroupConfig.param] 对应的占位符。
  final String value;

  /// 用户可见标签。
  final String label;

  const FilterOptionConfig({required this.value, required this.label});

  factory FilterOptionConfig.fromJson(Map<String, dynamic> json) =>
      FilterOptionConfig(
        value: (json['value'] ?? json['id'] ?? '').toString(),
        label: (json['label'] ?? json['name'] ?? json['value'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {'value': value, 'label': label};
}

/// 单个筛选分组（如「地区」「题材」「排序」）。
///
/// 选中某选项后，app 以 [route]（缺省用 [SourceFilterConfig.route]）调用对应路由，
/// 并把选项 [FilterOptionConfig.value] 代入 [param] 占位符。筛选维度完全由源声明，
/// 修复旧版「筛选按钮写死年份/地区/排序/状态」的问题。
class FilterGroupConfig {
  final String id;
  final String title;

  /// 该分组驱动的路由名（缺省继承 [SourceFilterConfig.route]）。
  final String? route;

  /// 该分组选项值要代入的路由占位符名（如 `category` / `keyword` / `sort`）。
  final String param;

  /// 是否允许多选（默认单选）。
  final bool multiSelect;

  final List<FilterOptionConfig> options;

  const FilterGroupConfig({
    required this.id,
    this.title = '',
    this.route,
    required this.param,
    this.multiSelect = false,
    this.options = const <FilterOptionConfig>[],
  });

  factory FilterGroupConfig.fromJson(Map<String, dynamic> json) =>
      FilterGroupConfig(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        route: json['route'] as String?,
        param: json['param'] as String? ?? 'category',
        multiSelect: json['multiSelect'] as bool? ?? false,
        options: (json['options'] as List<dynamic>?)
                ?.whereType<Map>()
                .map((e) =>
                    FilterOptionConfig.fromJson(Map<String, dynamic>.from(e)))
                .toList(growable: false) ??
            const <FilterOptionConfig>[],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        if (title.isNotEmpty) 'title': title,
        if (route != null) 'route': route,
        'param': param,
        if (multiSelect) 'multiSelect': multiSelect,
        'options': options.map((e) => e.toJson()).toList(),
      };
}

/// 源级筛选配置（若干筛选分组的集合）。
///
/// 向后兼容：源未声明 `filters` 时，[MediaApiService] 可从 `selectors.category`
/// 的 categories + tags 自动兜底生成筛选分组，使既有源无需改 JSON 也能获得动态筛选。
class SourceFilterConfig {
  /// 各分组缺省驱动的路由名。
  final String route;

  /// 全局筛选分组（站点的统一维度，或作为未声明分类覆盖时的兜底）。
  final List<FilterGroupConfig> groups;

  /// 按分类 id 的筛选分组覆盖（如 dalvdm：热门新番无年份、动漫大全/电影有年份）。
  /// key 为分类 [CategoryEntry.id]（如 "23"/"20"/"24"）。命中时优先用它，
  /// 否则回退 [groups]。实现「每个分类筛选各不相同」而无需在 Dart 写死。
  final Map<String, List<FilterGroupConfig>> byCategory;

  /// 按分类 id 的默认筛选值（用户未选时由源声明补齐，用户选中值优先覆盖）。
  /// 用于 MacCMS 等「show 路由第 1 页需带默认 sort/year」的站点：
  /// 如 233动漫国漫(2) 真值链接恒带 sort=hits、year=2026，用户不手动选这些维度时，
  /// 若不补齐会让 show 路由拼出空 sort/year 段，服务端重写规则不匹配 → 筛选无结果。
  /// key 为分类 id（如 "2"）；value 为「占位符名→默认值」映射（如 {sort:hits,year:2026}）。
  /// 仅作用于声明了的分类，其余分类返回空（不强行套用全局默认，避免破坏
  /// 剧场/美漫/特摄等「sort/year 本就应为空」的分类）。
  final Map<String, Map<String, String>> defaults;

  const SourceFilterConfig({
    this.route = 'category',
    this.groups = const <FilterGroupConfig>[],
    this.byCategory = const <String, List<FilterGroupConfig>>{},
    this.defaults = const <String, Map<String, String>>{},
  });

  /// 取某分类的筛选分组；声明了分类覆盖且命中则返回它，否则回退全局 [groups]。
  List<FilterGroupConfig> groupsFor(String categoryId) {
    if (categoryId.isNotEmpty && byCategory.containsKey(categoryId)) {
      return byCategory[categoryId]!;
    }
    return groups;
  }

  /// 取某分类的默认筛选值（用户未选时由源声明补齐，如国漫 sort=hits/year=2026）。
  /// 用户选中值优先于默认（合并在调用方 [_categoryPageVars] 处理）。
  Map<String, String> defaultsFor(String categoryId) {
    if (categoryId.isNotEmpty && defaults.containsKey(categoryId)) {
      return Map<String, String>.from(defaults[categoryId]!);
    }
    return const <String, String>{};
  }

  bool get isEmpty => groups.isEmpty && byCategory.isEmpty;

  factory SourceFilterConfig.fromJson(Map<String, dynamic> json) =>
      SourceFilterConfig(
        route: json['route'] as String? ?? 'category',
        groups: (json['groups'] as List<dynamic>?)
                ?.whereType<Map>()
                .map((e) =>
                    FilterGroupConfig.fromJson(Map<String, dynamic>.from(e)))
                .toList(growable: false) ??
            const <FilterGroupConfig>[],
        byCategory: (json['byCategory'] as Map<Object?, Object?>?)?.map(
              (k, v) => MapEntry(
                k.toString(),
                (v as List<dynamic>)
                    .whereType<Map>()
                    .map((e) =>
                        FilterGroupConfig.fromJson(Map<String, dynamic>.from(e)))
                    .toList(growable: false),
              ),
            ) ??
            const <String, List<FilterGroupConfig>>{},
        defaults: (json['defaults'] as Map<Object?, Object?>?)?.map(
              (k, v) => MapEntry(
                k.toString(),
                (v as Map<Object?, Object?>)
                    .map((ik, iv) => MapEntry(ik.toString(), iv.toString())),
              ),
            ) ??
            const <String, Map<String, String>>{},
      );

  Map<String, dynamic> toJson() => {
        'route': route,
        'groups': groups.map((e) => e.toJson()).toList(),
        if (byCategory.isNotEmpty)
          'byCategory': byCategory
              .map((k, v) => MapEntry(k, v.map((e) => e.toJson()).toList())),
        if (defaults.isNotEmpty)
          'defaults': defaults.map((k, v) => MapEntry(k, Map<String, String>.from(v))),
      };
}

/// 反盗链配置（补 Referer / 指定 UA 等）。
class AntiHotlinkingConfig {
  final String? referer;
  final Map<String, String>? headers;
  /// 部分源要求携带特定 User-Agent 才能绕开
  /// 反盗链。旧模型只读了 referer，丢失 userAgent 导致这类源请求被拒。
  final String? userAgent;

  const AntiHotlinkingConfig({this.referer, this.headers, this.userAgent});

  factory AntiHotlinkingConfig.fromJson(Map<String, dynamic>? json) =>
      AntiHotlinkingConfig(
        referer: json?['referer'] as String?,
        headers: (json?['headers'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ),
        userAgent: json?['userAgent'] as String?,
      );
}

/// 源声明式图片字节变换配置（`imageTransform` 段）。
///
/// 部分源站对**图片字节本身**加密（浏览器端由站点自带 JS 解密渲染），
/// 无论怎么配防盗链头拿到的都是密文。此类源在本段声明「按 host 匹配 +
/// 解密方式」，引擎在图片下载层统一解密（见 [ImageBytesDecryptRegistry]）。
/// 密钥/算法全部来自源 JSON，引擎不写死任何站点逻辑（源即插件）。
class ImageTransformConfig {
  /// 需要解密的图片 CDN host 列表（精确 host 匹配，忽略大小写）。
  final List<String> matchHosts;

  /// 解密规则。当前支持 `algo: "aes-cbc"` +
  /// `ivSource: "prefixBytes"`（密文文件前 ivLength 字节为 IV）+ PKCS7。
  final Map<String, dynamic> decrypt;

  const ImageTransformConfig({
    this.matchHosts = const <String>[],
    this.decrypt = const <String, dynamic>{},
  });

  factory ImageTransformConfig.fromJson(Map<String, dynamic>? json) {
    final dynamic decryptRaw = json?['decrypt'];
    return ImageTransformConfig(
      matchHosts: (json?['matchHosts'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const <String>[],
      decrypt: decryptRaw is Map
          ? Map<String, dynamic>.from(decryptRaw)
          : const <String, dynamic>{},
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'matchHosts': matchHosts,
        'decrypt': decrypt,
      };
}

/// WebView 验证配置。
class WebviewConfig {
  final bool adblock;
  final int timeoutSeconds;

  /// 源声明的 WebView 专用 UA（如移动 Chrome UA）。无头渲染抓取
  /// （SilentHtmlCapture）用它替代默认桌面 UA，供「仅移动端可见」的页面
  /// 按移动浏览器渲染。null 时维持引擎默认。
  final String? extraUserAgent;

  const WebviewConfig({
    this.adblock = true,
    this.timeoutSeconds = 20,
    this.extraUserAgent,
  });

  factory WebviewConfig.fromJson(Map<String, dynamic>? json) => WebviewConfig(
        adblock: json?['adblock'] as bool? ?? true,
        timeoutSeconds: json?['timeoutSeconds'] as int? ?? 20,
        extraUserAgent: json?['extraUserAgent'] as String?,
      );
}

/// 评论登录配置（comments.login 段）。
///
/// - [url]：WebView 登录页地址。
/// - [checkCookie]：Cookie 中出现该键名即视为已登录（快速判断）。
/// - [checkUrl] + [loggedInSelector]：可选的探测端点二次确认
/// （GET checkUrl，选择器命中非空即登录有效）。
/// - [sendTokenAs]：受保护请求（收藏/个人页等）如何附加 Authorization 头。
/// 完全由源声明驱动，不写死站点：
/// - null/其他 → 不额外追加，仅靠 HttpFetcher 自动注入的 Cookie（如 sessionid）。
/// - "bearer" → 追加 `Authorization: Bearer <checkCookie 对应 Cookie 值>`
/// （少数源用此格式）。
/// - "key" → 追加 `Authorization: <authScheme 默认 Key> <手动填写的 apiKey>`。
/// 值的来源是用户在登录面板粘贴、持久化在 [SourceKeyStore] 的密钥
/// （key 名见 [apiKeyParam]），而非 Cookie——适合「登录只给
/// access_token、收藏却要单独 API Key」的站点（其 v2 API 明确「用 Key
/// <api_key>，不是 Bearer」，401 报文已证实）。
/// - [authScheme]：仅 [sendTokenAs]=='key' 时生效，Authorization 头前缀
/// （默认 "Key"）。用于兼容不同前缀的源，不写死。
/// - [apiKeyParam]：仅 [sendTokenAs]=='key' 时生效，手动密钥在 [SourceKeyStore]
/// 中的参数名（默认 "apiKey"），按 `sourceId:apiKeyParam` 存储。
class CommentsLoginConfig {
  final String? url;
  final String? checkCookie;
  final String? checkUrl;
  final String? loggedInSelector;
  final String? sendTokenAs;
  final String? authScheme;
  final String? apiKeyParam;

  const CommentsLoginConfig({
    this.url,
    this.checkCookie,
    this.checkUrl,
    this.loggedInSelector,
    this.sendTokenAs,
    this.authScheme,
    this.apiKeyParam,
  });

  factory CommentsLoginConfig.fromJson(Map<String, dynamic> json) =>
      CommentsLoginConfig(
        url: json['url'] as String?,
        checkCookie: json['checkCookie'] as String?,
        checkUrl: json['checkUrl'] as String?,
        loggedInSelector: json['loggedInSelector'] as String?,
        sendTokenAs: json['sendTokenAs'] as String?,
        authScheme: json['authScheme'] as String?,
        apiKeyParam: json['apiKeyParam'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (url != null) 'url': url,
        if (checkCookie != null) 'checkCookie': checkCookie,
        if (checkUrl != null) 'checkUrl': checkUrl,
        if (loggedInSelector != null) 'loggedInSelector': loggedInSelector,
        if (sendTokenAs != null) 'sendTokenAs': sendTokenAs,
        if (authScheme != null) 'authScheme': authScheme,
        if (apiKeyParam != null) 'apiKeyParam': apiKeyParam,
      };
}

/// 评论配置（可选 comments 段）——源声明评论路由与登录方式。
///
/// - [routes]：复用 [RouteConfig]，仅 `list` 必需；`replies` / `post` /
/// `reply` / `like` / `report` 均可选——未声明的操作对应按钮不渲染。
/// - [selectors]：声明式选择器（JSONPath / CSS / XPath，与顶层 selectors
/// 同引擎）：items / commentId / author / avatar / content / time /
/// likeCount / replyCount / success 等。
/// - [login]：登录方式声明，缺省表示源不支持登录（只读评论）。
/// - [provider]：预留扩展点，默认 `source`；`bangumi` 本期仅解析不实现。
///
/// 源未声明该段（[PluginConfig.comments] 为 null）时，详情页完全不渲染
/// 任何评论 UI 元素；旧源 JSON 无需修改，零破坏向后兼容。
class CommentsConfig {
  final String provider; // source | bangumi（预留）
  final Map<String, RouteConfig> routes;
  final Map<String, dynamic>? selectors;
  final CommentsLoginConfig? login;

  const CommentsConfig({
    this.provider = 'source',
    this.routes = const {},
    this.selectors,
    this.login,
  });

  factory CommentsConfig.fromJson(Map<String, dynamic> json) {
    final routesMap = <String, RouteConfig>{};
    final rawRoutes = json['routes'] as Map?;
    if (rawRoutes != null) {
      rawRoutes.forEach((k, v) {
        routesMap[k.toString()] = RouteConfig.fromJson(v);
      });
    }
    return CommentsConfig(
      provider: json['provider'] as String? ?? 'source',
      routes: routesMap,
      selectors: json['selectors'] as Map<String, dynamic>?,
      login: json['login'] is Map
          ? CommentsLoginConfig.fromJson(
              Map<String, dynamic>.from(json['login'] as Map))
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'routes': routes.map((k, v) => MapEntry(k, v.toJson())),
        if (selectors != null) 'selectors': selectors,
        if (login != null) 'login': login!.toJson(),
      };

  /// 是否声明了必需的列表路由（未声明则评论功能不可用）。
  bool get hasList => routes.containsKey('list');

  /// 某操作路由是否已声明（未声明 → 对应按钮不渲染）。
  bool hasRoute(String name) => routes.containsKey(name);

  /// 是否支持登录（声明了 login.url / checkCookie，或走 API Key（sendTokenAs:"key"））。
  /// 三类任一成立即视为支持登录——否则纯 API Key 源（无 url/checkCookie）会在源管理 /
  /// 镜像 / 面板入口被错误隐藏，用户点不进登录面板。
  bool get supportsLogin =>
      login != null &&
      (login!.url != null ||
          login!.checkCookie != null ||
          login!.sendTokenAs == 'key');
}

/// 源公告（可选 announcement 段）。
///
/// 源作者可在 JSON 里声明一段公告（如「本站已换域名」「近期维护」），应用在
/// 该源的相关页面以横幅展示。为 null 时该源无公告。契合「源即插件」理念——
/// 公告完全由源自行声明，app 不写死任何站点文案。
class AnnouncementConfig {
  final String title;
  final String? body;
  final String? url;
  final int? updatedAt; // Unix 秒

  const AnnouncementConfig({
    required this.title,
    this.body,
    this.url,
    this.updatedAt,
  });

  factory AnnouncementConfig.fromJson(Map<String, dynamic> json) =>
      AnnouncementConfig(
        title: json['title'] as String? ?? '',
        body: json['body'] as String?,
        url: json['url'] as String?,
        updatedAt: (json['updatedAt'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': title,
        if (body != null) 'body': body,
        if (url != null) 'url': url,
        if (updatedAt != null) 'updatedAt': updatedAt,
      };
}

/// 将源 JSON 里的 version 规范为 int（缺省 1）。
/// 支持 int / 数字 / "12" / "1.3.0"（取首段），方便源作者用简单递增整数版本号。
int _coerceVersion(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    final first = v.split('.').first;
    return int.tryParse(first) ?? 1;
  }
  return 1;
}

/// 源声明式 CDN 图床发现（可选 cdn 段）。
///
/// 部分站点把图片放在多个子域图床（形如 i1-i4 / t1-t4），其中
/// 某些子域在特定网络下不可达。源在此声明 CDN 列表端点（如 /api/v2/cdn），
/// 引擎拉取 server 列表后 **逐个探活选取可达图床**，注入脚本上下文
/// `context.cdnImage` / `context.cdnThumb`，供脚本拼图片 URL。
///
/// 这是通用的「源声明端点、引擎选路」机制，不写死任何站点逻辑；连通性仍由
/// App 网络设置（代理 / VPN）负责，引擎只从站点自己返回的列表里挑一个能通的。
/// 与现有 mirrors 路由同源思路。源未声明该段时 [PluginConfig.cdn] 为 null，
/// 脚本回退到 `i3/t3.{激活镜像域}`（与旧行为一致）。
class CdnConfig {
  /// CDN 列表端点：相对 [SiteConfig.baseUrl] 或绝对 URL。
  final String url;
  /// 响应里「图片服务器数组」的键，默认 `image_servers`。
  final String imageServers;
  /// 响应里「缩略图服务器数组」的键，默认 `thumb_servers`。
  final String thumbServers;
  /// 探活全失败时图片基（含协议，无尾斜杠）。缺省按 `i3.{激活镜像域}` 推导。
  final String? imageFallback;
  /// 探活全失败时缩略图基。缺省按 `t3.{激活镜像域}` 推导。
  final String? thumbFallback;

  const CdnConfig({
    required this.url,
    this.imageServers = 'image_servers',
    this.thumbServers = 'thumb_servers',
    this.imageFallback,
    this.thumbFallback,
  });

  factory CdnConfig.fromJson(Map<String, dynamic> json) => CdnConfig(
        url: json['url'] as String,
        imageServers: json['imageServers'] as String? ?? 'image_servers',
        thumbServers: json['thumbServers'] as String? ?? 'thumb_servers',
        imageFallback: json['imageFallback'] as String?,
        thumbFallback: json['thumbFallback'] as String?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'url': url,
        'imageServers': imageServers,
        'thumbServers': thumbServers,
        if (imageFallback != null) 'imageFallback': imageFallback,
        if (thumbFallback != null) 'thumbFallback': thumbFallback,
      };
}

/// 完整源配置（PluginConfig）。
class PluginConfig {
  final String id;
  final String name;
  /// 源作者名（可选）。用于源详情页展示与溯源 / 致谢，不参与解析逻辑。
  final String? author;
  final SourceType type;
  final String? responseType; // json | html
  final bool useWebview;
  final SiteConfig site;
  final ParserConfig parser;
  final Map<String, RouteConfig> routes;
  final Map<String, dynamic>? selectors; // 声明式选择器（JSONPath / CSS / XPath）
  final CategoryConfig category;
  /// 首页多板块配置（源自行声明）。为空 → 回退单块「最新更新」。
  final List<HomeSectionConfig> homeSections;
  /// 动态筛选配置（源自行声明）。为 null → 服务层从 category+tags 兜底生成。
  final SourceFilterConfig? filters;
  final bool stealthMode;
  final AntiHotlinkingConfig antiHotlinking;
  /// 源级媒体域名改写（可选 `mediaHostRewrite` 段）：`{"原host": "目标host"}`。
  /// 适用于「签名 CDN 禁 Referer / 主 CDN 对直连拒绝」的场景——封面等媒体 URL
  /// 的 host 按映射改写后再加载（对齐参考实现的备用 CDN 做法，纯数据声明）。
  final Map<String, String>? mediaHostRewrite;
  final WebviewConfig webviewConfig;
  /// 评论配置（可选）。为 null → 详情页不渲染任何评论 UI。
  final CommentsConfig? comments;
  final bool deprecated;
  final bool enabled;
  final bool enabledExplore;
  final bool isHidden;
  final String? migrationMessage;
  final String? engine; // 保留字段，校验器不消费
  /// 源级网络覆盖（可选 `network` 块）。为 null → 该源完全继承全局网络配置。
  final SourceNetworkConfig? network;
  /// 源公告（可选 `announcement` 段）。为 null → 该源无公告。
  final AnnouncementConfig? announcement;
  /// 网络收藏（可选 `webFavorite` 段）。为 null → 该源不提供源站收藏入口，
  /// 在线浏览不显示「网络收藏」Tab，收藏按钮也不显示网络收藏选项。
  final WebFavoriteConfig? webFavorite;
  /// 源声明式 CDN 图床发现（可选 `cdn` 段）。为 null → 脚本回退 i3/t3 旧行为。
  final CdnConfig? cdn;
  /// 源声明式图片字节变换（可选 `imageTransform` 段）。为 null → 图片按原文加载。
  final ImageTransformConfig? imageTransform;
  /// 源年龄分级（可选 `ageRating` 字段，缺省 [SourceAgeRating.general]）。
  final SourceAgeRating ageRating;
  /// 源版本号（整数，缺省 1）。导入时 **≥ 已安装版本** 才覆盖（高版本升级 /
  /// 同版本刷新），**< 已安装版本** 不覆盖（防止误装旧版冲掉新源）。
  final int version;

  const PluginConfig({
    required this.id,
    required this.name,
    this.author,
    required this.type,
    this.responseType,
    this.useWebview = false,
    required this.site,
    required this.parser,
    this.routes = const {},
    this.selectors,
    this.category = const CategoryConfig(),
    this.homeSections = const <HomeSectionConfig>[],
    this.filters,
    this.stealthMode = false,
    this.antiHotlinking = const AntiHotlinkingConfig(),
    this.mediaHostRewrite,
    this.webviewConfig = const WebviewConfig(),
    this.comments,
    this.deprecated = false,
    this.enabled = true,
    this.enabledExplore = true,
    this.isHidden = false,
    this.migrationMessage,
        this.engine,
        this.network,
        this.announcement,
        this.webFavorite,
        this.cdn,
        this.imageTransform,
        this.ageRating = SourceAgeRating.general,
        this.version = 1,
      });

  /// 构造与阅读器在线取图一致的防盗链 headers（Referer / 指定 UA / Cookie），
  /// 供下载路径复用（防盗链源在缺头时返回 HTML 错误页或 ~5KB 占位图）。
  ///
  /// 与 [SourceImage] 的在线头保持同一套规则，关键差异点：
  /// **源未配置显式 Referer 时默认补同源 Referer**（图片 URL 自己的 origin），
  /// 大量 CDN 靠同源 Referer 防跨站盗链，缺失即被拦（下载曾因此拿到全同的
  /// 5.8KB 占位图）。[url] 用于计算该兜底 Referer。
  Map<String, String>? fetchHeadersFor(String url) {
    final AntiHotlinkingConfig ah = antiHotlinking;
    final SiteConfig siteCfg = site;
    final Map<String, String>? ahHeaders = ah.headers;
    final Map<String, String>? siteHeaders = siteCfg.headers;
    final String? referer = ah.referer;
    final String? ua = siteCfg.userAgent;
    final String? cookies = siteCfg.cookies;
    final Map<String, String> m = <String, String>{};
    if (ahHeaders != null) m.addAll(ahHeaders);
    if (siteHeaders != null) m.addAll(siteHeaders);
    if (referer != null && referer.isNotEmpty) m['Referer'] = referer;
    if (ua != null && ua.isNotEmpty) m['User-Agent'] = ua;
    if (cookies != null && cookies.isNotEmpty) m['Cookie'] = cookies;
    // 默认补 Referer：优先源站 origin（某源图 CDN 要求同源域名，
    // 否则间歇性 403），源站取不到再回退图片 URL 自身 origin。
    if (!m.containsKey('Referer')) {
      final String? origin = _fallbackRefererOrigin(url);
      if (origin != null) m['Referer'] = origin;
    }
    if (m.isEmpty) return null;
    return m;
  }

  /// 计算兜底 Referer 的 origin：优先源站 [SiteConfig.baseUrl] 的 origin
  /// （大部分防盗链 CDN 只认源站同源），取不到再回退图片 URL 自身 origin。
  String? _fallbackRefererOrigin(String url) {
    String? fromSite;
    try {
      final siteOrigin = Uri.tryParse(site.baseUrl)?.origin;
      if (siteOrigin != null && siteOrigin.isNotEmpty) {
        fromSite = siteOrigin;
      }
    } catch (_) {
      fromSite = null;
    }
    if (fromSite != null) return fromSite;
    try {
      return Uri.parse(url).origin;
    } catch (_) {
      return null;
    }
  }

  factory PluginConfig.fromJson(Map<String, dynamic> json) {
    final type = SourceType.parse(json['type'] as String?);
    if (type == null) {
      throw const PluginConfigException('unknown source type');
    }
    final routesMap = <String, RouteConfig>{};
    final rawRoutes = json['routes'] as Map?;
    if (rawRoutes != null) {
      rawRoutes.forEach((k, v) {
        routesMap[k.toString()] = RouteConfig.fromJson(v);
      });
    }
    final config = PluginConfig(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      author: json['author'] as String?,
      type: type,
      responseType: json['responseType'] as String?,
      useWebview: json['useWebview'] as bool? ?? false,
      site: SiteConfig.fromJson(json['site'] as Map<String, dynamic>),
      parser: ParserConfig.fromJson(json['parser'] as Map<String, dynamic>?),
      routes: routesMap,
      selectors: json['selectors'] as Map<String, dynamic>?,
      category: CategoryConfig.fromJson(json['category'] as Map<String, dynamic>?),
      homeSections: (json['homeSections'] as List<dynamic>?)
              ?.whereType<Map>()
              .map((e) => HomeSectionConfig.fromJson(
                  Map<String, dynamic>.from(e)))
              .toList(growable: false) ??
          const <HomeSectionConfig>[],
      filters: json['filters'] is Map
          ? SourceFilterConfig.fromJson(
              Map<String, dynamic>.from(json['filters'] as Map))
          : null,
      stealthMode: json['stealthMode'] as bool? ?? false,
      antiHotlinking:
          AntiHotlinkingConfig.fromJson(json['antiHotlinking'] as Map<String, dynamic>?),
      mediaHostRewrite: (json['mediaHostRewrite'] as Map?)
          ?.map((k, v) => MapEntry(k.toString(), v.toString())),
      webviewConfig: WebviewConfig.fromJson(json['webviewConfig'] as Map<String, dynamic>?),
      comments: json['comments'] is Map
          ? CommentsConfig.fromJson(
              Map<String, dynamic>.from(json['comments'] as Map))
          : null,
      deprecated: json['deprecated'] as bool? ?? false,
      enabled: json['enabled'] as bool? ?? true,
      enabledExplore: json['enabledExplore'] as bool? ?? true,
      isHidden: json['isHidden'] as bool? ?? false,
      migrationMessage: json['migrationMessage'] as String?,
      engine: json['engine'] as String?,
      network: json['network'] is Map
          ? SourceNetworkConfig.fromJson(
              Map<String, dynamic>.from(json['network'] as Map))
          : null,
      announcement: json['announcement'] is Map
          ? AnnouncementConfig.fromJson(
              Map<String, dynamic>.from(json['announcement'] as Map))
          : null,
      webFavorite: json['webFavorite'] is Map
          ? WebFavoriteConfig.fromJson(
              Map<String, dynamic>.from(json['webFavorite'] as Map))
          : null,
      cdn: json['cdn'] is Map
          ? CdnConfig.fromJson(Map<String, dynamic>.from(json['cdn'] as Map))
          : null,
      imageTransform: json['imageTransform'] is Map
          ? ImageTransformConfig.fromJson(
              Map<String, dynamic>.from(json['imageTransform'] as Map))
          : null,
      ageRating: SourceAgeRating.parse(json['ageRating']),
      version: _coerceVersion(json['version']),
    );
    // 解析到 imageTransform 即按 host 注册图片解密规则（幂等；源更新自然覆盖）。
    // fromJson 是所有源进 App 的唯一入口（内置解析 / Hive 回灌 / 导入更新）。
    final ImageTransformConfig? it = config.imageTransform;
    if (it != null && it.matchHosts.isNotEmpty) {
      final ImageDecryptRule? rule = imageDecryptRuleFromJson(it.decrypt);
      if (rule != null) {
        ImageBytesDecryptRegistry.register(hosts: it.matchHosts, rule: rule);
      }
    }
    return config;
  }

  /// 从 JSON 字符串构造。
  factory PluginConfig.fromJsonString(String source) =>
      PluginConfig.fromJson(jsonDecode(source) as Map<String, dynamic>);

  Map<String, dynamic> toJson() => {
        'id': id,
        'version': version,
        'name': name,
        if (author != null) 'author': author,
        'type': type.apiName,
        if (responseType != null) 'responseType': responseType,
        'useWebview': useWebview,
        'site': site.toJson(),
        'parser': parser.toJson(),
        'routes': routes.map((k, v) => MapEntry(k, v.toJson())),
        if (selectors != null) 'selectors': selectors,
        'category': category.toJson(),
        if (homeSections.isNotEmpty)
          'homeSections': homeSections.map((e) => e.toJson()).toList(),
        if (filters != null) 'filters': filters!.toJson(),
        'stealthMode': stealthMode,
        'antiHotlinking': {
          'referer': antiHotlinking.referer,
          if (antiHotlinking.userAgent != null)
            'userAgent': antiHotlinking.userAgent,
        },
        if (mediaHostRewrite != null) 'mediaHostRewrite': mediaHostRewrite,
        'webviewConfig': {
          'adblock': webviewConfig.adblock,
          'timeoutSeconds': webviewConfig.timeoutSeconds,
        },
        if (comments != null) 'comments': comments!.toJson(),
        'deprecated': deprecated,
        'enabled': enabled,
        'enabledExplore': enabledExplore,
        'isHidden': isHidden,
        if (migrationMessage != null) 'migrationMessage': migrationMessage,
        if (network != null) 'network': network!.toJson(),
        if (announcement != null) 'announcement': announcement!.toJson(),
        if (webFavorite != null) 'webFavorite': webFavorite!.toJson(),
        if (cdn != null) 'cdn': cdn!.toJson(),
        if (imageTransform != null) 'imageTransform': imageTransform!.toJson(),
        'ageRating': ageRating.apiName,
      };

  bool get isDeprecated => deprecated;
  bool get isEnabled => enabled;

  /// 是否可在「在线浏览」展示网络收藏入口（列表 route 或网页 URL 至少有一个）。
  bool get hasWebFavoriteBrowse {
    final WebFavoriteConfig? wf = webFavorite;
    if (wf == null || !wf.enabled) return false;
    final String? r = wf.route;
    if (r != null && r.isNotEmpty && routes.containsKey(r)) return true;
    return (wf.url ?? '').isNotEmpty;
  }

  /// 是否可在详情页 / 阅读器 / 播放器提供「加入网络收藏」选项。
  bool get hasWebFavoriteAdd {
    final WebFavoriteConfig? wf = webFavorite;
    if (wf == null || !wf.enabled) return false;
    final String? r = wf.addRoute;
    if (r != null && r.isNotEmpty && routes.containsKey(r)) return true;
    if ((wf.addUrl ?? '').isNotEmpty) return true;
    // 未单独声明「加入」入口时，退化为打开收藏页让用户自行操作。
    return hasWebFavoriteBrowse;
  }

  /// 复制并修改部分字段（用于启用/禁用/隐藏等状态变更，以及编辑内置源提升）。
  PluginConfig copyWith({
    String? id,
    String? name,
    String? author,
    SiteConfig? site,
    bool? enabled,
    bool? enabledExplore,
    bool? isHidden,
    bool? deprecated,
    String? migrationMessage,
    SourceNetworkConfig? network,
    AnnouncementConfig? announcement,
    WebFavoriteConfig? webFavorite,
    SourceAgeRating? ageRating,
    int? version,
  }) =>
      PluginConfig(
        id: id ?? this.id,
        name: name ?? this.name,
        author: author ?? this.author,
        type: type,
        responseType: responseType,
        useWebview: useWebview,
        site: site ?? this.site,
        parser: parser,
        routes: routes,
        selectors: selectors,
        category: category,
        homeSections: homeSections,
        filters: filters,
        stealthMode: stealthMode,
        antiHotlinking: antiHotlinking,
        webviewConfig: webviewConfig,
        comments: comments,
        deprecated: deprecated ?? this.deprecated,
        enabled: enabled ?? this.enabled,
        enabledExplore: enabledExplore ?? this.enabledExplore,
        isHidden: isHidden ?? this.isHidden,
        migrationMessage: migrationMessage ?? this.migrationMessage,
        engine: engine,
        network: network ?? this.network,
        announcement: announcement ?? this.announcement,
        webFavorite: webFavorite ?? this.webFavorite,
        ageRating: ageRating ?? this.ageRating,
        version: version ?? this.version,
      );

  /// 必填字段校验，返回错误列表（空 = 通过）。
  List<String> validate() {
    final errors = <String>[];
    if (id.isEmpty) errors.add('missing: id');
    if (name.isEmpty) errors.add('missing: name');
    if (site.baseUrl.isEmpty) errors.add('missing: site.baseUrl');
    if (type == SourceType.animeSource && !routes.containsKey('latest')) {
      errors.add('animeSource requires route "latest"');
    }
    // 源级 network 块校验（作为警告汇总，不阻断启用）。
    final net = network;
    if (net != null) {
      for (final key in net.validate()) {
        errors.add('network: $key');
      }
    }
    return errors;
  }

  /// 解析路由 URL：替换 {page}/{keyword}/{id}/{category}/{cid}/{mid}/{chapterId}
  /// 等占位符，相对路径按 activeBaseUrl 补全；绝对 URL 替换 host 指向新镜像
  /// （镜像切换后 route 指向新镜像）。
  String resolveRouteUrl(
    String apiName, {
    required String activeBaseUrl,
    Map<String, String> vars = const {},
  }) {
    // 评论路由命名空间：`comments.list` / `comments.post` 等查找
    // comments.routes，占位符替换 / 镜像切换 / 相对路径补全全部复用。
    final route = _routeFor(apiName);
    if (route == null) {
      throw PluginConfigException('route not found: $apiName');
    }
    var url = route.url;
    // video 路由通常为 `{url}` 直通：调用方已传入播放页绝对地址时直接返回，
    // 否则会被 activeBaseUrl 前缀拼接成 `https://base/https://episode` 双 host 坏链，
    // 导致播放页抓取失败、解析不到视频源。此修复对所有源通用，不针对特定站点。
    if (apiName == 'video' && url.trim() == '{url}') {
      final rawUrl = vars['url'];
      if (rawUrl != null && rawUrl.isNotEmpty) {
        // 绝对地址（含 host）直接返回，避免被 activeBaseUrl 前缀成双 host 坏链
        // （如 `https://base/https://episode`），导致播放页抓取失败、解析不到视频。
        if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
          return rawUrl;
        }
        // 根相对地址（如 `/anime/.../play/1.html`，233 动漫播放页即此类）：
        // base 先去掉尾斜杠再拼接，否则会出现 `https://host//anime/...` 双斜杠
        // 坏链，播放器拿到错误地址 → 0×0 黑屏。对齐下方通用拼接逻辑但提前返回，
        // 避免先拼成 `host/{url}` 再 replaceAll('{url}', '/anime/...') 产生双斜杠。
        final base = activeBaseUrl.endsWith('/')
            ? activeBaseUrl.substring(0, activeBaseUrl.length - 1)
            : activeBaseUrl;
        if (rawUrl.startsWith('/')) {
          return '$base$rawUrl';
        }
        // 纯相对地址：基于 base 目录 resolve。
        return Uri.parse(base.endsWith('/') ? base : '$base/')
            .resolve(rawUrl)
            .toString();
      }
    }
    // {detailUrl} 直通：模板仅为 {detailUrl} 且值已是绝对地址（HTML 源的列表
    // a@href 常直接给绝对链接）时直接返回。否则模板会先被 activeBaseUrl 前缀，
    // 再替换出 `https://base/http://real` 双 host 坏链，详情/选集必 404。
    // 与上方 video 路由 {url} 特判同一思路，对所有源通用，不针对特定站点。
    if (url.trim() == '{detailUrl}') {
      final du = vars['detailUrl'];
      if (du != null && du.isNotEmpty) {
        if (du.startsWith('http://') || du.startsWith('https://')) {
          return _upgradeSameHostHttps(du, activeBaseUrl);
        }
        final base = activeBaseUrl.endsWith('/')
            ? activeBaseUrl.substring(0, activeBaseUrl.length - 1)
            : activeBaseUrl;
        return du.startsWith('/') ? '$base$du' : '$base/$du';
      }
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      // 绝对 URL：替换 host 指向新镜像（保留 path/query）
      url = _replaceHost(url, activeBaseUrl);
    } else {
      final base = activeBaseUrl.endsWith('/')
          ? activeBaseUrl.substring(0, activeBaseUrl.length - 1)
          : activeBaseUrl;
      url = url.startsWith('/') ? '$base$url' : '$base/$url';
    }
    vars.forEach((k, v) {
      // 数组参数展开：模板形如 `tags[]={tags}`（参数名后带 `[]` 再跟同名占位符）。
      // 部分站点高级搜索是数组语义（每个选中值一个独立参数 `tags[]=a&tags[]=b`）；
      // 多选筛选的多个值在 vars 中以逗号连接传入，若按普通占位符整体编码会被
      // 当成单个不存在的值 → 搜索恒零结果。这里拆开后逐值编码展开。必须先于
      // 下方普通编码规则处理——逗号会被 encodeComponent 成 %2C 导致无法拆分。
      // 空值时连同前导 & 整段移除，避免残留 `tags[]=` 空参数被服务器误解。
      // 数组 token 必须与模板字面严格同形：`tags[]={tags}`（含 = 号）。
      final arrayToken = '$k[]={$k}';
      if (url.contains(arrayToken)) {
        if (v.isEmpty) {
          // 空多选：优先移除「前导 & + 整段」（tags 非 query 首参的常见形态），
          // 剩余（tags 为 query 首参形态）再移除占位段本身，随后清理由此产生的
          // 悬空连接符（?& → ?、&& → &、尾部 &），避免残留空参数被服务器误解。
          url = url.replaceAll('&$k[]{$k}', '');
          if (url.contains(arrayToken)) {
            url = url.replaceAll(arrayToken, '');
          }
          url = url
              .replaceAll('?&', '?')
              .replaceAll('&&', '&')
              .replaceAll(RegExp(r'&$'), '');
        } else {
          // 非空：逐值 encodeComponent（tag 值含中日文/空格/特殊符号），以
          // `&k[]=v` 形式接到首个值上，展开为重复参数数组。
          final expanded = v
              .split(',')
              .map((p) => Uri.encodeComponent(p))
              .join('&$k[]=');
          url = url.replaceAll(arrayToken, '$k[]=$expanded');
        }
        return;
      }
      // 用户搜索词等自由文本必须 URL 编码：否则中文关键词（如「海贼王」）原样
      // 塞进查询串会导致 GET 请求非法 / 被服务器误解 → 搜索返回错乱或空
      // （中文站「作品搜索内容不正确」「主演搜索不全」的根因）。
      // 此外，筛选值也可能是中文（如 MacCMS 站 genre=「奇幻」直接作为路径段
      // `/show/2--hits-奇幻--...html`）：服务端期望 %E5%A5%87%E5%B9%BB 编码形式，
      // 原样插入中文会导致匹配失败返回空列表（「筛选无结果」的通用根因）。
      // 规则：keyword 恒编码；其余占位符仅当值含非 ASCII 字符且不是 URL/路径
      // （不含 '/' 与 ':'）时编码——避免误编码 {url}/{detailUrl} 等整段地址。
      // 用 encodeComponent（空格→%20）兼顾查询串与路径段两种落点。
      final String value;
      if (apiName == 'show' &&
          k == 'page' &&
          (v == '1' || v == '0')) {
        // MacCMS show 路由第 1 页段为空：真值形如 /show/2--hits-奇幻--------2026.html
        // （page 段为空段，共 8 连字符）。若注入 "1" 会拼出 -----1---，服务端重写
        // 规则不匹配 → 返回空/404，筛选无结果。仅作用于 show 路由，避免影响
        // latest 等查询串分页（那些需保留 page=1）。第 2 页起 page>=2 正常保留。
        value = '';
      } else if (k == 'keyword') {
        value = Uri.encodeComponent(v);
      } else if (v.contains(RegExp(r'[^\x00-\x7F]')) &&
          !v.contains('/') &&
          !v.contains(':')) {
        value = Uri.encodeComponent(v);
      } else {
        value = v;
      }
      // 「显式可选整段参数」：占位符带 `?` 后缀（`&meta_tags={class?}`，参数名
      // 与占位符名可不同），值为空时整段移除（`?` 首参形态移除后由 cleanup
      // 回收悬空符）。用于 PostgREST 等严格 API——空值参数 `k=` 会被判 400，
      // 而整段缺席即「不过滤」。不带 `?` 的普通 `{k}` 空值仍按旧语义保留
      // `k=`（MacCMS 等模板依赖空值参数在线）。值含中文时走 encodeComponent，
      // 恰好把值内花括号一并编码（`cs.{奇幻}` → `cs.%7B…%7D`），不会与占位符
      // cleanup 冲突，也不会残留字面 `{}`。
      if (v.isEmpty) {
        final optional = RegExp(
            '[&?]([A-Za-z0-9_%\\-\\[\\]]+)=\\{${RegExp.escape(k)}\\?\\}');
        final m = optional.firstMatch(url);
        if (m != null) {
          url = url.replaceRange(
            m.start,
            m.end,
            m.group(0)!.startsWith('?') ? '?' : '',
          );
          return;
        }
      }
      url = url
          .replaceAll('{$k}', value)
          .replaceAll('{$k?}', value);
    });
    // 可选占位符兜底：vars 完全缺失该键（源未声明 defaults 且用户未碰筛选）
    // 时上方循环不会访问它，`{k?}` 原样残留——整段移除对应可选参数，
    // 避免 cleanup 只清占位符却留下 `k=` 空段（PostgREST 400）。
    url = url.replaceAll(
        RegExp(r'&[A-Za-z0-9_%\-\[\]]+=\{[A-Za-z_][A-Za-z0-9_]*\?\}'), '');
    url = url.replaceAll(
        RegExp(r'\?[A-Za-z0-9_%\-\[\]]+=\{[A-Za-z_][A-Za-z0-9_]*\?\}'), '?');
    // 占位符数值运算：`{page-1}` / `{page+1}` / `{page*30-30}` 这类写法。
    // 用途一：相当多站点的分页参数从 0 开始（第 1 页是 `page=0`），而引擎统一
    // 从 1 开始计数。没有偏移语法时源只能自造变量名（引擎不认）或干脆错位
    // ——表现为「永远看不到第 1 页 / 翻页重复」。
    // 用途二：JSON API 普遍用 offset 分页（`offset=(page-1)*limit`），而页码
    // 占位符只有页号，需要一次乘法才能在 URL 里直接算出 offset。这是通用需求
    // （分页是绝大多数列表端点的标配），故在占位符解析层支持，不针对任何站点。
    url = _applyPlaceholderOffsets(url, vars);
    // 兼容旧版「采集api」导出的源：详情/选集路由常用 {season_id}/{sid}/{avid}
    // 占位，而新解析器统一用 {id}。旧应用能正常解析正是靠这些别名映射。
    // 不映射会导致占位被清空成 "...&id=" 从而「详情页空」。
    // 注意：必须无条件执行别名映射——上一版把这段放进 `if (idVal != null)`
    // 里，导致调用方只传 {id} 时 {season_id} 永远不被替换，cleanup 后变成
    // `/detail/id/.html` 这种坏 URL，详情页静默失败（历史记录点进去灰屏的根因）。
    final idVal = vars['id'];
    if (idVal != null && idVal.isNotEmpty) {
      url = url
          .replaceAll('{season_id}', idVal)
          .replaceAll('{sid}', idVal)
          .replaceAll('{avid}', idVal);
    }
    // 详情路由兜底：若仍有未替换的占位符（如调用方只传了 {id} 而 URL 用了
    // {season_id}），且本次携带了 detailUrl，则直接用真实详情地址替换，避免
    // 构造出坏 URL。历史记录条目常只有 detailUrl 这一个可用标识，这条兜底能让
    // 「从历史点进去」的详情页稳定加载，而非灰屏。
    if (apiName == 'detail' && url.contains('{')) {
      final detailUrl = vars['detailUrl'];
      if (detailUrl != null && detailUrl.isNotEmpty) {
        url = _upgradeSameHostHttps(detailUrl, activeBaseUrl);
      }
    }
    // 播放/剧集兜底：若仍有未替换占位符（如 video 路由 /play{season_id}-1-
    // {episode_id}/ 只拿到 {url} 而 season_id/episode_id 缺失），且携带了完整的
    // 剧集地址 url（含所属线路的播放页），直接使用它，避免被 cleanup 清成
    // /play-1-/ 这种坏地址。这让「剧集 url 即播放页（含线路）」的多线路场景对
    // 所有源通用生效，而无需给每个源写死 season_id/episode_id 拆解规则。
    if (url.contains('{')) {
      final rawUrl = vars['url'];
      if (rawUrl != null && rawUrl.isNotEmpty) {
        if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
          url = rawUrl;
        } else if (rawUrl.startsWith('/')) {
          final b = activeBaseUrl.endsWith('/')
              ? activeBaseUrl.substring(0, activeBaseUrl.length - 1)
              : activeBaseUrl;
          url = '$b$rawUrl';
        }
      }
    }
    // Clean up unreplaced placeholders (e.g. {category} when loading home
    // page without a category). Prevents malformed URLs like
    // /vodshow/{category}--------1---.html which cause 404/error pages
    // and silent empty-list failures.
    // 注意：正则用 `[^}]*` 以兼容空占位符 `{}`，避免残留花括号污染 URL。
    url = url.replaceAll(RegExp(r'\{[^}]*\}'), '');
    // 数组参数兜底：vars 完全缺失该键时（用户没碰筛选组），上方数组分支根本
    // 不执行，cleanup 只清掉 {tags} 占位却留下 `tags[]=` 空参数。仅匹配「等号
    // 后无值」（后随 & 或串尾）的空数组参数——必须锚定，否则会把已展开的
    // tags[]=v1&tags[]=v2 的参数名前缀也吃掉，值被粘到前一个参数上（实测翻车）。
    url = url.replaceAll(
        RegExp(r'&[A-Za-z0-9_%\-\[\]]+\[]=(?=&|$)'), ''); // 中间参数（带前导 &）
    url = url.replaceAll(
        RegExp(r'\?[A-Za-z0-9_%\-\[\]]+\[]=(?=&)'), '?'); // query 首参、后面还有参数
    url = url.replaceAll(
        RegExp(r'\?[A-Za-z0-9_%\-\[\]]+\[]=$'), ''); // query 首参且为唯一参数（$ 锚定，不动带值的）
    url = url.replaceAll('?&', '?'); // 上一步替换产生的悬空连接符
    debugPrint('[PluginConfig] resolveRouteUrl: apiName=$apiName finalUrl=$url');
    return url;
  }

  /// 路由 body 模板占位符直替：`{var}` → 原始值（不做 URL 编码——body 不是
  /// URL）。body 本身是花括号密集的 JSON，清理未命中占位符时**不能**沿用
  /// URL 的 `\{[^}]*\}` 贪婪清理（会把整个 JSON 体当占位符吞掉），只清理
  /// 「裸单词占位符」`\{[A-Za-z_]\w*\}`——JSON 键/值永远带引号，不会误伤。
  /// 供 BuiltinResolver 构造 POST 请求体（路由声明 `body` 的 JSON API 源，
  /// 如 `{"action":"fallback","episode_id":{url}}`）。
  static String interpolateRouteBody(String template, Map<String, String> vars) {
    var body = template;
    vars.forEach((k, v) {
      body = body.replaceAll('{$k}', v);
    });
    return body.replaceAll(RegExp(r'\{[A-Za-z_][A-Za-z0-9_]*\}'), '');
  }

  /// 处理 `{name±N}` / `{name*N±M}` 形式的占位符数值运算（如 `{page-1}`、
  /// `{page*30-30}`）。
  ///
  /// 运算符只支持 `+` `-` `*` `/` 后接非负整数，按书写顺序从左到右依次求值
  /// （不做优先级，语义直观可预测）。左折叠即可覆盖两类真实需求：
  /// - 0 基分页：`{page-1}`；
  /// - offset 分页：`{page*30-30}`（第 n 页 → offset=(n-1)*30）。
  ///
  /// 仅对「变量值为纯整数」时生效；非数值（如关键词）保持原样交由后续
  /// cleanup 处理，避免误伤。结果为负则夹到 0（站点不接受负页码 / 负 offset）。
  static String _applyPlaceholderOffsets(
      String url, Map<String, String> vars) {
    final re = RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)((?:[*/+-]\d+)+)\}');
    return url.replaceAllMapped(re, (m) {
      final raw = vars[m.group(1)];
      final base = int.tryParse(raw?.trim() ?? '');
      if (base == null) return m.group(0)!; // 非数值：原样保留
      var value = base;
      for (final step in RegExp(r'([*/+-])(\d+)').allMatches(m.group(2)!)) {
        final n = int.parse(step.group(2)!);
        final op = step.group(1)!;
        if (op == '+') {
          value = value + n;
        } else if (op == '-') {
          value = value - n;
        } else if (op == '*') {
          value = value * n;
        } else if (op == '/' && n != 0) {
          value = value ~/ n;
        }
      }
      return (value < 0 ? 0 : value).toString();
    });
  }

  /// 将 [originalUrl] 的 scheme+host 替换为 [newBaseUrl] 的 scheme+host，
  /// 保留原 URL 的 path/query/fragment。
  ///
  /// 关键：必须用字符串方式仅替换「scheme://host[:port]」前缀，**不能**走
  /// `Uri.parse(...).toString()`——后者会把 query 里的 `{page}`/`{id}` 等占位符
  /// 重新编码成 `%7Bpage%7D`，导致后续 `replaceAll('{page}', v)` 永远匹配不到，
  /// 占位符原样留在 URL 里（如 `page=%7Bpage%7D`），站点收到非法参数返回错误页，
  /// 解析器拿到 HTML 而非 JSON → 列表/详情/选集/图片全部解析为空。这是「媒体与
  /// 漫画都解析不到内容」的根因之一。
  static String _replaceHost(String originalUrl, String newBaseUrl) {
    try {
      final base = Uri.parse(newBaseUrl);
      final scheme = base.scheme.isNotEmpty ? base.scheme : 'https';
      final host = base.host;
      // 镜像站通常为标准端口：新基址是 80/443/0 时省略端口（丢弃原 URL 的非标准
      // 端口，避免拼出 mirror.com:8080 这类错址）；新基址带非标准端口则保留。
      final newPort = base.port;
      final portStr =
          (newPort == 0 || newPort == 80 || newPort == 443) ? '' : ':$newPort';
      final match = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]*)://([^/:?#]+)(:\d+)?');
      return originalUrl.replaceFirstMapped(match, (_) => '$scheme://$host$portStr');
    } catch (_) {
      // URL 解析失败，返回原 URL
      return originalUrl;
    }
  }

  /// 同源 http→https 升级：站点列表页常给 `http://` 绝对链接，而多数站点
  /// http 端口不通/劣化（实测 http 直连超时、https 正常），进详情/选集必超时。
  /// 仅当 detailUrl 的 host 与当前基址一致且基址是 https 时升级；外链 host
  /// 不动（可能是真 http 资源）。
  static String _upgradeSameHostHttps(String url, String activeBaseUrl) {
    if (!url.startsWith('http://')) return url;
    try {
      final base = Uri.parse(activeBaseUrl);
      final du = Uri.parse(url);
      if (base.scheme == 'https' && du.host == base.host) {
        return url.replaceFirst('http://', 'https://');
      }
    } catch (_) {
      // URL 解析失败，返回原 URL
    }
    return url;
  }

  /// 路由查找：`comments.` 前缀指向 [comments] 段声明的评论路由，
  /// 其余走主 [routes] 表。
  RouteConfig? _routeFor(String apiName) {
    if (apiName.startsWith('comments.')) {
      return comments?.routes[apiName.substring('comments.'.length)];
    }
    return routes[apiName];
  }

  /// 路由级声明的 responseType，缺省回退到顶层。
  String? responseTypeFor(String apiName) =>
      _routeFor(apiName)?.responseType ?? responseType;
}

/// 源配置解析异常（校验/路由缺失）。
class PluginConfigException implements Exception {
  final String message;
  const PluginConfigException(this.message);
  @override
  String toString() => 'PluginConfigException: $message';
}
