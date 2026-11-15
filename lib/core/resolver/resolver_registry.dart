/// 解析器注册表：按 [PluginConfig.parser] 类型 / hybrid overrides / WebView 需求自动选择解析器。
///
/// 关键约束：选择结果由 parser 声明决定，**与注册顺序无关**（spec 验收第 2 条）。
///
/// 额外分支：当 PluginConfig.selectors['xiaoshuo'] 为 Map（书源，
/// 由 ShuyuanAdapter 写入）时，路由到 ShuyuanNovelResolver。
library;

import '../models/category_entry.dart';
import '../models/explore_kind.dart';
import '../models/plugin_config.dart';
import 'builtin_resolver.dart';
import 'script_resolver.dart';
import 'source_resolver.dart';
import 'webview_resolver.dart';

/// 声明式解析器类型集合：[ParserConfig.type] 命中即视为「无脚本、靠选择器解析」。
///
/// `useWebview==true` 的声明式源必须路由到 [WebViewResolver] 触发
/// [WebViewHtmlRequest]，由 UI 渲染后回灌 HTML 给 [BuiltinResolver] 解析；
/// 否则会被错误路由到 [BuiltinResolver] 直接抓 HTTP（拿到 JS 未渲染的骨架 HTML）。
const Set<String> _declarativeTypes = <String>{
  'builtin',
  'xpath',
  'jsonpath',
  'css',
};

class ResolverRegistry {
  ResolverRegistry._();

  static final ResolverRegistry instance = ResolverRegistry._();

  /// 判断是否为书源（由 ShuyuanAdapter 写入的 markers）。
  bool _isShuyuanSource(PluginConfig source) {
    return source.selectors?['xiaoshuo'] is Map<String, dynamic>;
  }

  /// 计算某 API 实际使用的解析类型（builtin | script | webview），与注册顺序无关。
  ///
  /// 路由模型对齐旧应用（[E:\project\nexhub]）：`useWebview==true` 仅表示
  /// **视频路由需要 WebView 嗅探/渲染**，列表/详情/选集等非视频路由始终走
  /// 直连 HTTP（[BuiltinResolver] / [ScriptResolver]）。旧应用的
  /// `WebViewResolver.canResolve` 仅对 `video`/`episode`/`*video*` 返回 true，
  /// 正是此意。
  ///
  /// 优先级：
  /// 1. `useWebview==true` 且 [ParserConfig.type] ∈ [_declarativeTypes]
  /// （builtin/xpath/jsonpath/css）**且为视频路由** → `'webview'`
  /// （触发 [WebViewHtmlRequest]，由 UI 渲染后回灌 HTML 给
  /// [BuiltinResolver] 解析视频）。非视频路由不进此分支。
  /// 2. `useWebview==true` 且 hybrid + override.type=='script' → `'script'`
  /// （保留脚本路径，[ScriptResolver] 内部自抓取，无需 WebView）。
  /// 3. `useWebview==true` 且 hybrid + override.type ∈ {webview, webview-html}
  /// → `'webview'`。
  /// 4. 其余沿用原 default 行为（声明式/无 override 的 hybrid 路由走
  /// [BuiltinResolver] 直连 HTTP）。
  String effectiveResolverType(PluginConfig source, String apiName) {
    // 视频路由判定：对齐旧应用 WebViewResolver.canResolve（video/episode/
    // *video*）。useWebview 仅对视频路由启用 WebView；非视频路由一律直连
    // HTTP，避免反爬页上内嵌浏览器崩溃、反复弹验证、列表为空（用户反馈的
    // 5 类症状根因）。
    final lower = apiName.toLowerCase();
    final isVideoRoute =
        lower == 'video' || lower == 'episode' || lower.contains('video');

    // 优先级 1：声明式源 + useWebview + 视频路由 → 'webview'。覆盖
    // 部分声明式源的视频嗅探；非视频路由
    // 不进此分支，改走下方 builtin（直连 HTTP 抓服务端渲染 HTML）。
    if (source.useWebview &&
        _declarativeTypes.contains(source.parser.type) &&
        isVideoRoute) {
      return 'webview';
    }
    // 优先级 2/3：hybrid + useWebview 时按 override.type 路由（effectiveTypeFor
    // 已返回 override.type；script → ScriptResolver 内部感知 useWebview 并抛
    // WebViewHtmlRequest；webview/webview-html → WebViewResolver）。
    final t = source.parser.effectiveTypeFor(apiName);
    if (t == 'script') return 'script';
    // 顶层 webview / webview-html 均路由到 WebViewResolver（后者抛
    // WebViewHtmlRequest 走渲染后抽取，前者抛抽取/验证异常）。
    if (t == 'webview' || t == 'webview-html') return 'webview';
    if (t == 'hybrid') {
      final override = source.parser.overrides?[apiName];
      if (override?.type == 'script') return 'script';
      if (override?.type == 'webview' || override?.type == 'webview-html') {
        return 'webview';
      }
      // 无 script/webview override 的 hybrid 路由（如部分动漫源的
      // latest/detail/episodes）按声明式（CSS/XPath）选择器解析，直接走
      // BuiltinResolver 抓 HTTP。这类 MacCMS 源为服务端渲染，直连即可拿到
      // 完整 HTML；此前强制 WebView 渲染回灌反而会触发内嵌浏览器在反爬页上
      // 崩溃（用户反馈「点击采集本页渲染内容卡崩」），且取回的 HTML 也未必含
      // 内容。脚本 override 路由（如视频）已在上方路由到 ScriptResolver 自抓取。
      return 'builtin';
    }
    // 优先级 4：其余沿用原 default 行为。
    return 'builtin';
  }

  /// 查找合适的解析器。
  SourceResolver find(PluginConfig source, String apiName) {
    // 书源路由到 ShuyuanNovelResolver（不走 builtin/script/webview）
    if (_isShuyuanSource(source)) {
      return _shuyuanResolver;
    }
    final type = effectiveResolverType(source, apiName);
    switch (type) {
      case 'script':
        return ScriptResolver();
      case 'webview':
        return const WebViewResolver();
      default:
        return const BuiltinResolver();
    }
  }

  /// 渲染后 HTML 回灌（含书源）。
  ///
  /// 供 [MediaApiService._resolveFromRenderedHtml] 在识别为书源时调用，
  /// 内部路由到 [_LazyShuyuanResolver.resolveRenderedHtml]，避免错误地走
  /// [BuiltinResolver]（书源无 selectors 形式规则，否则渲染 HTML 解析为空）。
  /// 非书源不应调用本方法（由调用方直接处理 Builtin/Script）。
  Future<dynamic> resolveRenderedHtml(
    PluginConfig source,
    String apiName,
    String html, {
    Map<String, String> vars = const {},
  }) {
    if (_isShuyuanSource(source)) {
      return _shuyuanResolver.resolveRenderedHtml(source, apiName, html, vars: vars);
    }
    throw UnsupportedError('resolveRenderedHtml 仅支持书源，收到 apiName=$apiName');
  }

  /// 解析书源的发现分类（含 `<js>` 动态分类）。
  ///
  /// 书源的分类声明在 `selectors['xiaoshuo'].exploreUrl`，支持 `名称::URL`
  /// 多行、JSON 数组与 `<js>`/`@js:` 动态生成等多种格式，只有书源引擎
  /// （[ExploreCategoriesCapable]）能完整解析；静态正则解析会漏掉动态分类，
  /// 导致这类源「分类页没有任何 Tab」。
  ///
  /// 引擎未注册（测试环境）或解析失败时返回空列表，由调用方回退静态解析。
  ///
  /// 异步：动态分类脚本可发 `java.ajax`，需要宿主一轮或多轮抓取后重放，
  /// 才能在脚本里拿到真实响应（legado `evalJS` 的阻塞 ajax 等效）。
  Future<List<CategoryEntry>> resolveExploreCategories(
    PluginConfig source,
  ) async {
    if (_isShuyuanSource(source)) {
      try {
        return await _shuyuanResolver.resolveExploreCategories(source);
      } on Object {
        return const <CategoryEntry>[];
      }
    }
    return const <CategoryEntry>[];
  }

  /// 解析书源发现页的完整选项栏（分类 / 输入框 / 按钮 / 开关 / 下拉）。
  ///
  /// 非书源返回空结果（调用方回退普通导航）；书源解析失败时 [error] 非空。
  Future<ExploreKindsResult> resolveExploreKinds(
    PluginConfig source, {
    bool refresh = false,
  }) async {
    if (!_isShuyuanSource(source)) {
      return const ExploreKindsResult();
    }
    try {
      return await _shuyuanResolver
          .resolveExploreKinds(source, refresh: refresh);
    } on Object catch (e) {
      return ExploreKindsResult(error: '$e');
    }
  }

  /// 持久化发现页选项栏的单个值（text/toggle/select）。
  Future<void> setExploreKindValue(
    PluginConfig source,
    String title,
    String value,
  ) {
    if (!_isShuyuanSource(source)) return Future<void>.value();
    return _shuyuanResolver.setExploreKindValue(source, title, value);
  }

  /// 执行发现页选项的 action 脚本（java.ajax/webView 走确定性重放）。
  Future<ExploreKindActionResult> executeExploreKindAction(
    PluginConfig source,
    ExploreKind kind,
  ) {
    if (!_isShuyuanSource(source)) {
      return Future<ExploreKindActionResult>.value(
          const ExploreKindActionResult());
    }
    return _shuyuanResolver.executeExploreKindAction(source, kind);
  }
}

// 惰性单例：书源解析器（WebBook 内部维护 XiaoshuoHttp，
// 复用静态 Dio 实例，单例化避免每次解析都重建）。
final _LazyShuyuanResolver _shuyuanResolver = _LazyShuyuanResolver();

class _LazyShuyuanResolver
    implements
        SourceResolver,
        RenderedHtmlCapable,
        ExploreCategoriesCapable,
        ExploreKindsCapable {
  RenderedHtmlCapable? _inner;

  @override
  Future<dynamic> resolve(
    PluginConfig source,
    String apiName, {
    Map<String, String> vars = const {},
    void Function(List<dynamic>)? onProgress,
  }) {
    _inner ??= _createShuyuanResolver() as RenderedHtmlCapable;
    return (_inner! as SourceResolver)
        .resolve(source, apiName, vars: vars, onProgress: onProgress);
  }

  /// 渲染后 HTML 回灌转发：委托真正的书源解析器（[ShuyuanNovelResolver]）解析，
  /// 让 WebView 过验证后拿回的 HTML 能正确走 WebBook 规则解析，而非 BuiltinResolver。
  @override
  Future<dynamic> resolveRenderedHtml(
    PluginConfig source,
    String apiName,
    String html, {
    Map<String, String> vars = const {},
  }) {
    _inner ??= _createShuyuanResolver() as RenderedHtmlCapable;
    return _inner!.resolveRenderedHtml(source, apiName, html, vars: vars);
  }

  /// 发现分类解析转发：委托书源引擎完整解析（含动态分类）。
  @override
  Future<List<CategoryEntry>> resolveExploreCategories(PluginConfig source) {
    final inner = _inner ??= _createShuyuanResolver() as RenderedHtmlCapable;
    if (inner is ExploreCategoriesCapable) {
      return (inner as ExploreCategoriesCapable)
          .resolveExploreCategories(source);
    }
    return Future<List<CategoryEntry>>.value(const <CategoryEntry>[]);
  }

  @override
  Future<ExploreKindsResult> resolveExploreKinds(
    PluginConfig source, {
    bool refresh = false,
  }) {
    final inner = _inner ??= _createShuyuanResolver() as RenderedHtmlCapable;
    if (inner is ExploreKindsCapable) {
      return (inner as ExploreKindsCapable)
          .resolveExploreKinds(source, refresh: refresh);
    }
    return Future<ExploreKindsResult>.value(const ExploreKindsResult());
  }

  @override
  Future<void> setExploreKindValue(
    PluginConfig source,
    String title,
    String value,
  ) {
    final inner = _inner ??= _createShuyuanResolver() as RenderedHtmlCapable;
    if (inner is ExploreKindsCapable) {
      return (inner as ExploreKindsCapable)
          .setExploreKindValue(source, title, value);
    }
    return Future<void>.value();
  }

  @override
  Future<ExploreKindActionResult> executeExploreKindAction(
    PluginConfig source,
    ExploreKind kind,
  ) {
    final inner = _inner ??= _createShuyuanResolver() as RenderedHtmlCapable;
    if (inner is ExploreKindsCapable) {
      return (inner as ExploreKindsCapable)
          .executeExploreKindAction(source, kind);
    }
    return Future<ExploreKindActionResult>.value(
        const ExploreKindActionResult());
  }

  SourceResolver _createShuyuanResolver() {
    // 延迟导入避免循环依赖：ShuyuanNovelResolver 依赖 WebBook，而 WebBook
    // 不依赖 core/resolver，所以这里通过 dynamic 调用避免顶层 import 循环。
    // ignore: avoid_dynamic_calls
    final lib = _importShuyuanResolver();
    return lib;
  }

  SourceResolver _importShuyuanResolver() {
    // 通过具名工厂从 features/shuyuan 引入，避免在 core 中硬编码 feature 路径。
    return _ShuyuanResolverFactory.create();
  }
}

/// 由 features/shuyuan 提供的解析器工厂（在 main.dart 启动期注入实现，
/// 避免 core 反向依赖 feature 层）。
class _ShuyuanResolverFactory {
  static SourceResolver Function()? factory;

  static SourceResolver create() {
    final f = factory;
    if (f == null) {
      throw StateError(
        'ShuyuanResolverFactory not registered. Call registerShuyuanResolver(...) at app startup.',
      );
    }
    return f();
  }
}

/// 公开入口：在 app 启动期（如 splash_screen.dart 的 _initialize）注入
/// 书源解析器实现，避免 core 反向依赖 feature 层。
/// 调用示例：`registerShuyuanResolver(ShuyuanNovelResolver.new);`
void registerShuyuanResolver(SourceResolver Function() factory) {
  _ShuyuanResolverFactory.factory = factory;
}

/// 能直接解析「渲染后 HTML」的解析器（用于 WebView 过验证后回灌）。
///
/// 普通声明式/脚本源由 [BuiltinResolver]/[ScriptResolver] 已实现同名方法；
/// 书源解析器（[ShuyuanNovelResolver]）通过本接口声明该能力，使
/// [_LazyShuyuanResolver] / [MediaApiService] 能在回灌时正确分派，而非误用
/// [BuiltinResolver]（书源无 selectors 形式规则）。
abstract class RenderedHtmlCapable {
  Future<dynamic> resolveRenderedHtml(
    PluginConfig source,
    String apiName,
    String html, {
    Map<String, String> vars = const {},
  });
}

/// 能解析「发现分类」的解析器（书源引擎）。
///
/// 书源的发现分类（exploreUrl）支持 `名称::URL`、JSON 数组、`<js>` 动态
/// 生成等格式，只有书源引擎能完整解析；本接口让 core 层
/// （[ResolverRegistry.resolveExploreCategories]）无需反向依赖 feature 层
/// 即可获取分类列表。
abstract class ExploreCategoriesCapable {
  /// 动态分类（`<js>`）可能依赖 `java.ajax` 等宿主能力，故为异步；静态
  /// 声明（文本 / JSON）实现可直接返回已完成 Future。
  Future<List<CategoryEntry>> resolveExploreCategories(PluginConfig source);
}

/// 发现页选项栏能力：解析完整选项、持久化选项值、执行选项 action。
abstract class ExploreKindsCapable {
  Future<ExploreKindsResult> resolveExploreKinds(
    PluginConfig source, {
    bool refresh = false,
  });

  Future<void> setExploreKindValue(
    PluginConfig source,
    String title,
    String value,
  );

  Future<ExploreKindActionResult> executeExploreKindAction(
    PluginConfig source,
    ExploreKind kind,
  );
}
