/// 内置（声明式）解析器：依据 route + selectors 直接解析，无脚本依赖。
/// 支持 JSON（JSONPath）、HTML（CSS / `a@href` / `//` XPath）。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:html/dom.dart';

import '../danmaku/dandanplay_matcher.dart';
import '../models/episode.dart';
import '../models/media_item.dart';
import '../models/plugin_config.dart';
import '../network/model/effective_network_profile.dart';
import '../network/network_config_service.dart';
import '../scraper/collect_api_parser.dart';
import '../scraper/http_fetcher.dart';
import '../services/config_loader.dart';
import '../utils/html_utils.dart';
import '../utils/json_path.dart';
import 'image_extractor.dart';
import 'm3u8_ad_filter.dart';
import 'm3u8_parser.dart';
import 'source_resolver.dart';
import 'video_extractor.dart';
import 'video_source_cache.dart';

/// video 路由解析结果 TTL 缓存（避免对同一 m3u8 重复抓取/过滤）。
final VideoSourceCache _videoCache = VideoSourceCache();

/// 清空已解析视频地址缓存。
///
/// 播放器「视频链接已失效」重试时调用：缓存里可能存着已过期的签名直链，
/// 不清缓存会反复拿到旧 URL 而「假死」。清空后重试会重新解析拿到新链接。
/// 该缓存 TTL 仅 5 分钟且为内存态，全量清空影响可忽略。
void clearResolvedVideoCache() => _videoCache.clear();

class BuiltinResolver implements SourceResolver {
  /// 可选弹幕匹配器：episodes 路由阶段按番剧名自动填充 dandanplayEpisodeId。
  /// 为 null 时使用 [DandanplayMatcher.defaultInstance]（懒加载）。
  const BuiltinResolver({this.danmakuMatcher});

  final DandanplayMatcher? danmakuMatcher;

  @override
  Future<dynamic> resolve(
    PluginConfig source,
    String apiName, {
    Map<String, String> vars = const {},
    void Function(List<dynamic>)? onProgress,
  }) async {
    final base = ConfigLoader.instance.getActiveMirror(source);
    final url =
        source.resolveRouteUrl(apiName, activeBaseUrl: base, vars: vars);
    return resolveFromUrl(source, apiName, url, vars: vars, baseUrl: base);
  }

  /// 通用解析入口：对给定 [url] 发起请求并按响应类型解析。
  ///
  /// 抽出以便复用：[WebViewResolver] 触发验证后，调用方可用 WebView 抽取到的
  /// 真实地址 [url] 再次解析（详见 [MediaApiService.fetchApiResults] 的
  /// [extractedUrl] 参数），从而修复「浏览器能打开但解析不到内容」的问题。
  Future<dynamic> resolveFromUrl(
    PluginConfig source,
    String apiName,
    String url, {
    Map<String, String> vars = const {},
    String? baseUrl,
  }) async {
    // 响应类型缺省推断：声明式 HTML 源（xpath / css / html）默认按 HTML 解析；
    // 其余（jsonpath / hybrid / 未声明）默认 JSON。原代码无脑回退 'json'，会导致
    // xpath 源在「直连 HTTP 解析」（关掉 useWebview 走 BuiltinResolver）时把
    // HTML 当 JSON 解析、列表永远为空。
    final rt = source.responseTypeFor(apiName) ?? _defaultResponseType(source);
    // 源级网络覆盖：计算一次有效档案，显式沿调用链下传（无 Zone）。
    final net = NetworkConfigService.instance.effectiveFor(source);
    final referer = source.antiHotlinking.referer ?? (baseUrl ?? url);
    // 反盗链指定 UA（部分 xpath 源）。
    final ua = source.antiHotlinking.userAgent;
    final Map<String, String>? ahHeaders =
        (ua != null && ua.isNotEmpty) ? <String, String>{'User-Agent': ua} : null;
    // 通用请求头合并：站点级（site.headers）与路由级（route.headers）声明头
    // 显式并入（路由级优先）。供 API 型源携带鉴权头（如 Supabase PostgREST /
    // Edge Functions 的 apikey），防盗链 UA 仅在未被显式声明时兜底。
    Map<String, String> effectiveHeaders() => <String, String>{
          ...?ahHeaders,
          ...?source.site.headers,
          ...?source.routes[apiName]?.headers,
        };
    // 通用 POST 路由：源可声明 `method: "post"`，或声明 `body` 模板（隐含
    // post）。未声明 body 时沿用旧机制：把已解析 URL 的查询串拆成
    // application/x-www-form-urlencoded 表单体发 POST（如 MacCMS 模板的
    // /ds_api/vod 接口只收 POST 表单）。机制对所有源通用，不写死任何站点。
    final routeCfg = source.routes[apiName];
    final isPost = (routeCfg?.method.toLowerCase() ?? 'get') == 'post' ||
        (routeCfg?.body?.isNotEmpty ?? false);
    if (rt == 'json') {
      dynamic result;
      try {
        final dynamic json;
        if (isPost) {
          if (apiName == 'week') {
            // 周更列表：ds_api/vod 单页仅 40 条，翻数页凑足一周各开播日的样本，
            // 避免周期表某些星期因单页采样偏差长期为空。
            json = await _fetchWeekJson(url, referer, ahHeaders, net: net);
          } else {
            final bodyTpl = routeCfg?.body;
            final headers = effectiveHeaders();
            if (bodyTpl != null && bodyTpl.isNotEmpty) {
              // 通用：路由声明 body 模板 → 占位符直替后原样作为请求体发送
              // （JSON API 源；Content-Type 由源 headers 声明，默认 json）。
              final data = PluginConfig.interpolateRouteBody(bodyTpl, vars);
              json = await HttpFetcher.instance.postJson(
                url,
                headers: <String, String>{
                  'Content-Type': 'application/json',
                  ...headers,
                },
                data: data,
                referer: referer,
                net: net,
              );
            } else {
              final split = _splitFormUrl(url);
              json = await HttpFetcher.instance.postJson(
                split.$1,
                headers: <String, String>{
                  'Content-Type': 'application/x-www-form-urlencoded',
                  ...headers,
                },
                data: split.$2,
                referer: referer,
                net: net,
              );
            }
          }
        } else {
          json = await HttpFetcher.instance
              .getJson(url, referer: referer, headers: effectiveHeaders(), net: net);
        }
        result = _withDetailUrlFallback(
          _parseJson(source, apiName, json, url, baseUrl: baseUrl ?? url),
          apiName,
          url,
        );
      } on FormatException {
        // 视频路由偶尔直接返回 m3u8 / 直链（而非 JSON）。
        // 此时 jsonDecode 会抛 FormatException；不要让它炸掉整页，
        // 直接把路由 URL 当可播放地址透出，交给 _maybeEnhanceVideo
        // （m3u8 抓取/选流/带请求头）正常处理。非 video 路由则原样上抛。
        if (apiName == 'video') {
          result = VideoResult(url: url);
        } else {
          rethrow;
        }
      }
      final enhanced = await _maybeEnhanceVideo(apiName, result, source,
          baseUrl: baseUrl ?? url, referer: referer, net: net);
      return _enrichDanmakuIfEpisodes(enhanced, vars);
    }
    final String html;
    if (isPost) {
      final bodyTpl = routeCfg?.body;
      final headers = effectiveHeaders();
      if (bodyTpl != null && bodyTpl.isNotEmpty) {
        html = await HttpFetcher.instance.post(
          url,
          headers: <String, String>{
            'Content-Type': 'application/json',
            ...headers,
          },
          data: PluginConfig.interpolateRouteBody(bodyTpl, vars),
          referer: referer,
          net: net,
        );
      } else {
        final split = _splitFormUrl(url);
        html = await HttpFetcher.instance.postForm(
          split.$1,
          data: split.$3,
          referer: referer,
          headers: headers,
          net: net,
        );
      }
    } else {
      html = await HttpFetcher.instance
          .getHtml(url, referer: referer, headers: ahHeaders, net: net);
    }
    // 诊断：筛选结果为空时，先看 URL 和 HTML 标题/长度
    final titleMatch = RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false)
        .firstMatch(html);
    debugPrint(
      '[BuiltinResolver] apiName=$apiName url=$url '
      'htmlLen=${html.length} '
      'title=${titleMatch?.group(1)?.trim() ?? '(no title)'}',
    );
    final result = _withDetailUrlFallback(
      _parseHtml(source, apiName, html, baseUrl: baseUrl ?? url),
      apiName,
      url,
    );
    final enhanced = await _maybeEnhanceVideo(apiName, result, source,
        baseUrl: baseUrl ?? url, referer: referer, net: net);
    return _enrichDanmakuIfEpisodes(enhanced, vars);
  }

  /// 渲染后抽取入口：直接对渲染后的 [html] 用既有选择器解析（不再重新抓取）。
  ///
  /// 用于 WebView 加载页面、JS 渲染完成后取回整页 HTML 的场景
  /// （[WebViewHtmlRequest]）。[baseUrl] 用于补全相对链接，缺省回退源主域。
  /// 复用与 [resolveFromUrl] 相同的 `_parseHtml` + 视频增强 + 弹幕补全，
  /// 因此无需为 webview-html 源编写任何额外解析逻辑。
  Future<dynamic> resolveFromHtml(
    PluginConfig source,
    String apiName,
    String html, {
    Map<String, String> vars = const {},
    String? baseUrl,
  }) async {
    final effectiveBase = baseUrl ?? source.site.baseUrl;
    final net = NetworkConfigService.instance.effectiveFor(source);
    debugPrint(
      '[BuiltinResolver] resolveFromHtml 进入 apiName=$apiName '
      'htmlLen=${html.length} base=$effectiveBase',
    );
    dynamic result;
    try {
      result = _parseHtml(source, apiName, html, baseUrl: effectiveBase);
    } on Object catch (e, st) {
      debugPrint('[BuiltinResolver] resolveFromHtml 解析异常 apiName=$apiName: $e\n$st');
      rethrow;
    }
    final enhanced = await _maybeEnhanceVideo(
      apiName,
      result,
      source,
      baseUrl: effectiveBase,
      referer: source.antiHotlinking.referer ?? effectiveBase,
      net: net,
    );
    return _enrichDanmakuIfEpisodes(enhanced, vars);
  }

  /// 把「已解析的路由 URL」拆成 POST 表单请求三元组：
  /// (基础地址, urlencoded 表单体, 表单键值对)。
  ///
  /// 源 JSON 里 POST 路由沿用与 GET 相同的 `?k={v}&...` 模板写法（复用
  /// resolveRouteUrl 的占位符替换/清理），引擎在发请求前把查询串转为表单体。
  /// 值统一 Uri.encodeComponent：兼容中文筛选值（如 area=中国）。
  static (String, String, Map<String, String>) _splitFormUrl(String url) {
    final i = url.indexOf('?');
    if (i < 0) return (url, '', const <String, String>{});
    final base = url.substring(0, i);
    final form = <String, String>{};
    for (final pair in url.substring(i + 1).split('&')) {
      if (pair.isEmpty) continue;
      final j = pair.indexOf('=');
      final k = j < 0 ? pair : pair.substring(0, j);
      final v = j < 0 ? '' : pair.substring(j + 1);
      if (k.isEmpty) continue;
      // 先尽力解码（keyword 等已被 resolveRouteUrl 编码过），失败按原文。
      String dec(String s) {
        try {
          return Uri.decodeComponent(s);
        } catch (_) {
          return s;
        }
      }

      form[dec(k)] = dec(v);
    }
    final body = form.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return (base, body, form);
  }

  /// 周更列表多页聚合：ds_api/vod 单页仅 40 条，翻数页凑足一周各开播日的样本，
  /// 避免周期表某些星期因单页采样偏差长期为空。返回 `{ 'list': [...] }` 形状
  /// 交给 [_parseJson] 的 week 分支统一解析（并注入开播日 updatedAt）。
  Future<dynamic> _fetchWeekJson(
    String url,
    String referer,
    Map<String, String>? ahHeaders, {
    EffectiveNetworkProfile? net,
  }) async {
    final split = _splitFormUrl(url);
    final base = split.$1;
    final headers = <String, String>{
      'Content-Type': 'application/x-www-form-urlencoded',
      ...?ahHeaders,
    };
    final all = <dynamic>[];
    for (var p = 1; p <= 3; p++) {
      final form = Map<String, String>.from(split.$3);
      form['page'] = p.toString();
      final body = form.entries
          .map((e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');
      try {
        final j = await HttpFetcher.instance.postJson(
          base,
          headers: headers,
          data: body,
          referer: referer,
          net: net,
        );
        final list = j is Map ? j['list'] : null;
        if (list is List && list.isNotEmpty) {
          all.addAll(list);
          if (list.length < 40) break; // 已到末页
        } else {
          break;
        }
      } catch (_) {
        break; // 某页失败则停止翻页，已聚合部分仍可用
      }
    }
    return <String, dynamic>{'list': all};
  }

  /// 响应类型缺省值：声明式 HTML 源（xpath / css / html）按 HTML 解析，
  /// 其余按 JSON。仅当源未显式声明 [PluginConfig.responseTypeFor] 时生效。
  static String _defaultResponseType(PluginConfig source) {
    final t = source.parser.type;
    if (t == 'xpath' || t == 'css' || t == 'html') return 'html';
    return 'json';
  }

  /// detail 路由兜底：若解析出的 [MediaItem] 没有 [detailUrl]，
  /// 用实际发起请求的 URL 填充。这样所有声明式源只要 detail 路由能被请求，
  /// 详情页就一定有原站链接可供「应用内浏览 / 外部浏览器打开」，无需源额外声明
  /// detailUrl 选择器（共创式：不针对单个源写死）。
  dynamic _withDetailUrlFallback(
    dynamic result,
    String apiName,
    String url,
  ) {
    if (apiName == 'detail' && result is MediaItem) {
      final du = result.detailUrl;
      if (du == null || du.isEmpty || du.contains('{}')) {
        // 仅当请求 URL 自身有效（非空、无未解析占位符）时才兜底使用。
        if (url.isNotEmpty && !url.contains('{}')) {
          return result.copyWith(detailUrl: url);
        }
      }
    }
    return result;
  }

  /// 若结果是剧集列表，尝试按番剧名填充弹幕 ID；否则原样返回。
  Future<dynamic> _enrichDanmakuIfEpisodes(
    dynamic result,
    Map<String, String> vars,
  ) async {
    if (result is! List<Episode>) return result;
    return _enrichDanmaku(result, vars);
  }

  /// 按番剧名（vars['title']）搜索弹弹play 并填充 dandanplayEpisodeId。
  ///
  /// 全流程 best-effort：网络错误 / 超时 / 未配置均静默跳过，
  /// 返回原列表（可能附带已匹配的 ID）。
  Future<List<Episode>> _enrichDanmaku(
    List<Episode> episodes,
    Map<String, String> vars,
  ) async {
    final title = vars['title'];
    if (title == null || title.isEmpty) return episodes;
    try {
      final matcher = danmakuMatcher ?? DandanplayMatcher.defaultInstance;
      final map = await matcher
          .matchEpisodes(title, episodes)
          .timeout(const Duration(seconds: 12));
      if (map.isEmpty) return episodes;
      return <Episode>[
        for (int i = 0; i < episodes.length; i++)
          map.containsKey(i)
              ? episodes[i].copyWith(dandanplayEpisodeId: map[i])
              : episodes[i],
      ];
    } on Object {
      // 弹幕匹配失败：静默跳过，不影响主流程。
      return episodes;
    }
  }

  /// video 路由出口增强：VideoExtractor 抽 URL → 若是 m3u8 则
  /// M3u8Parser + filterAds → TTL 缓存。非 video 路由原样透传。
  /// 公开 API 签名不变，仅内部增强。
  Future<dynamic> _maybeEnhanceVideo(
    String apiName,
    dynamic result,
    PluginConfig source, {
    required String baseUrl,
    required String? referer,
    EffectiveNetworkProfile? net,
  }) async {
    if (apiName != 'video' || result is! VideoResult) return result;
    return _enhanceVideoResult(result, source,
        baseUrl: baseUrl, referer: referer, net: net);
  }

  /// 对单个 [VideoResult] 做 m3u8 广告过滤与缓存。
  Future<VideoResult> _enhanceVideoResult(
    VideoResult raw,
    PluginConfig source, {
    required String baseUrl,
    required String? referer,
    EffectiveNetworkProfile? net,
  }) async {
    final cacheKey = '${source.id}:${raw.url}';
    // 重解析前批量清理过期项，防止过期项堆积。
    _videoCache.clearExpired();
    final cached = _videoCache.get(cacheKey);
    if (cached != null) return cached;

    var enhanced = raw;
    final type = raw.type ?? _guessType(raw.url);
    if (type == 'm3u8' && _isHttpUrl(raw.url)) {
      try {
        enhanced = await _resolveM3u8(raw, referer: referer, net: net);
      } catch (_) {
        // m3u8 抓取/解析失败时回退原始 URL，保证可播放。
        enhanced = raw;
      }
    }
    // 附加播放所需请求头（Referer / UA 等），让 mpv 拉分片时与
    // 抓取 m3u8 文本时带同样的头，避免 CDN 403 导致黑屏。
    final out = _withVideoHeaders(enhanced, source, referer);
    // 多线路（raw.lines）与单线路地址同属一次解析结果，必须原样带回，
    // 否则 m3u8 解析分支重建 VideoResult 时会把 lines 丢掉，导致「线路」面板失效。
    final withLines = VideoResult(
      url: out.url,
      type: out.type,
      headers: out.headers,
      lines: raw.lines,
    );
    _videoCache.set(cacheKey, withLines);
    return withLines;
  }

  /// 为 [VideoResult] 附加播放所需 HTTP 请求头。
  ///
  /// 与抓取 m3u8 文本时一致地携带 [referer]（来自源反盗链配置或 baseUrl）
  /// 与 [PluginConfig.antiHotlinking] 指定的 UA / 额外头。播放器真正打开
  /// 地址（mpv 拉分片）时必须带上，否则 CDN（如 v5.lbv*.com）返回
  /// 403、解不出任何帧、画面全黑（日志见 VideoOutput.Resize rect 0x0）。
  VideoResult _withVideoHeaders(
    VideoResult result,
    PluginConfig source,
    String? referer,
  ) {
    final ah = source.antiHotlinking;
    final headers = <String, String>{};
    if (ah.userAgent != null && ah.userAgent!.isNotEmpty) {
      headers['User-Agent'] = ah.userAgent!;
    }
    if (referer != null && referer.isNotEmpty) {
      headers['Referer'] = referer;
    }
    if (ah.headers != null) headers.addAll(ah.headers!);
    if (headers.isEmpty) return result;
    return VideoResult(
      url: result.url,
      type: result.type,
      headers: headers,
      lines: result.lines,
    );
  }

  /// 抓取并解析 m3u8：master 选最高清晰度，media 过滤广告后生成 data URI。
  Future<VideoResult> _resolveM3u8(
    VideoResult raw, {
    required String? referer,
    EffectiveNetworkProfile? net,
  }) async {
    final content =
        await HttpFetcher.instance.getHtml(raw.url, referer: referer, net: net);
    final parsed = M3u8Parser.parse(content, baseUrl: raw.url);

    // Master playlist：选最高带宽变体 URL 返回（缓存与播放器后续处理）。
    if (parsed.isMaster && parsed.variants.isNotEmpty) {
      final best = parsed.variants
          .reduce((a, b) => a.bandwidth >= b.bandwidth ? a : b);
      return VideoResult(url: best.url, type: 'm3u8');
    }

    // Media playlist：过滤广告，若有移除则生成自包含 data URI。
    if (parsed.segments.isNotEmpty) {
      final filtered = filterAds(parsed.segments);
      if (filtered.length < parsed.segments.length) {
        return VideoResult(
          url: _buildMediaPlaylistDataUri(filtered),
          type: 'm3u8',
        );
      }
    }

    // 无广告或无分片：原样返回。
    return raw;
  }

  /// 将过滤后的分片序列化为绝对 URL 的 media playlist data URI。
  String _buildMediaPlaylistDataUri(List<M3u8Segment> segments) {
    final buffer = StringBuffer();
    buffer.writeln('#EXTM3U');
    buffer.writeln('#EXT-X-VERSION:3');
    final maxDuration = segments.fold<int>(
      0,
      (m, s) => s.duration.ceil() > m ? s.duration.ceil() : m,
    );
    buffer.writeln('#EXT-X-TARGETDURATION:$maxDuration');
    for (final s in segments) {
      buffer.writeln('#EXTINF:${s.duration},');
      buffer.writeln(s.url);
    }
    buffer.writeln('#EXT-X-ENDLIST');
    final encoded = base64Encode(utf8.encode(buffer.toString()));
    return 'data:application/vnd.apple.mpegurl;base64,$encoded';
  }

  bool _isHttpUrl(String url) =>
      url.startsWith('http://') || url.startsWith('https://');

  // ---- JSON ----

  dynamic _parseJson(
    PluginConfig source,
    String apiName,
    dynamic json,
    String url, {
    required String baseUrl,
  }) {
    final isCollect = CollectApiParser.looksLikeCollectApi(url) ||
        (json is Map && json['list'] != null && json['class'] != null);
    debugPrint('[BuiltinResolver] _parseJson: apiName=$apiName isCollect=$isCollect url=$url');
    if (isCollect) {
      if (apiName == 'detail' || apiName == 'episodes') {
        final list = (json is Map && json['list'] is List && json['list'].isNotEmpty)
            ? json['list'].first
            : json;
        debugPrint('[BuiltinResolver] isCollect detail/episodes: listType=${list.runtimeType} hasVodPlayUrl=${list is Map ? list['vod_play_url'] : 'N/A'}');
        if (apiName == 'detail') {
          return CollectApiParser.parseDetail(json, source);
        }
        return CollectApiParser.splitPlayLines(
          list['vod_play_from'],
          list['vod_play_url'],
        );
      }
      return CollectApiParser.parseList(json, source);
    }
    final sel = source.selectors ?? const <String, dynamic>{};
    switch (apiName) {
      case 'detail':
        return _itemFromJsonSelector(
            json, _subSel(sel, 'detail', sel), source,
            baseUrl: baseUrl);
      case 'episodes':
      case 'chapters':
        return _episodesFromJsonSelector(json, sel, source);
      case 'images':
        return _imagesFromJsonSelector(json, sel, baseUrl: baseUrl);
      case 'video':
        return _videoFromJsonSelector(json, sel);
      case 'week':
        // 周期表专用：列表项按真实开播星期（藏在 status 如 "45|周日" 中）注入
        // updatedAt，使 OnlineScheduleSection 按开播日而非最后更新时间分组。
        final items = _itemsFromJsonSelector(
            json, _subSel(sel, 'week', sel), source,
            baseUrl: baseUrl);
        return [
          for (final it in items) it.copyWith(updatedAt: _airingDateFor(it)),
        ];
      default:
        // 与 _parseHtml 保持一致：非 list 类 API（latest/explore/category/
        // search）也按 apiName 提取分组选择器（selectors.{apiName}.{list,...}），
        // 否则 grouped JSON 源会因为 sel['list'] 为 null 而回退到默认 `$.list`，
        // 解析为空列表。无该子键时 _subSel 回退到 sel 本身，向后兼容扁平写法。
        return _itemsFromJsonSelector(
            json,
            _subSel(sel, apiName, _searchSelFallback(sel, apiName)),
            source,
            baseUrl: baseUrl);
    }
  }

  /// 解析漫画图片列表（JSON）：`images` 可为 JSONPath 字符串或
  /// `{ list, url }` 对象，返回图片 URL 列表。结果经 ImageExtractor 清洗
  /// （绝对 URL 补全 + 广告/占位图过滤 + 去重）。
  List<String> _imagesFromJsonSelector(
    dynamic json,
    Map<String, dynamic> sel, {
    required String baseUrl,
  }) {
    final imgSel = sel['images'];
    List<String> raw;
    if (imgSel is Map) {
      final listPath = imgSel['list'] as String? ?? '\$.images';
      final items = JsonPath.eval(listPath, json);
      if (items is List) {
        raw = <String>[
          for (final it in items)
            if (it is Map)
              _js(it, imgSel['url'] ?? 'url')
              else it?.toString() ?? ''
        ].where((s) => s.isNotEmpty).toList();
      } else {
        raw = const <String>[];
      }
    } else if (imgSel is String) {
      final r = JsonPath.eval(imgSel, json);
      if (r is List) {
        raw = <String>[
          for (final it in r)
            if (it is Map) (it['url']?.toString() ?? '') else it?.toString() ?? ''
        ].where((s) => s.isNotEmpty).toList();
      } else {
        raw = const <String>[];
      }
    } else {
      raw = const <String>[];
    }
    final abs = <String>[
      for (final u in raw) ImageExtractor.toAbsolute(u, baseUrl),
    ];
    return ImageExtractor.filterImages(abs);
  }

  List<MediaItem> _itemsFromJsonSelector(
    dynamic json,
    Map<String, dynamic> sel,
    PluginConfig source, {
    required String baseUrl,
  }) {
    final listPath = sel['list'] as String? ?? '\$.list';
    final items = JsonPath.eval(listPath, json);
    if (items is! List) return const [];
    return [
      for (final it in items)
        if (it is Map) _itemFromJsonSelector(it, sel, source, baseUrl: baseUrl),
    ];
  }

  MediaItem _itemFromJsonSelector(
    dynamic item,
    Map<String, dynamic> sel,
    PluginConfig source, {
    required String baseUrl,
  }) {
    String pick(String key) {
      final p = sel[key];
      if (p == null) return '';
      if (p is! String) return '';
      final v = JsonPath.eval(p, item);
      return v?.toString() ?? '';
    }

    final base = MediaItem(
      id: pick('id'),
      title: pick('title'),
      coverUrl: _absoluteCoverUrl(pick('cover'), baseUrl, source),
      detailUrl: pick('detailUrl').isNotEmpty ? pick('detailUrl') : pick('detail'),
      sourceId: source.id,
      sourceType: source.type,
      description: pick('description').isNotEmpty ? pick('description') : pick('intro'),
      author: pick('author'),
      // JSONPath 源同样解析导演/主演，供「按导演/主演检索」客户端过滤使用。
      director: pick('director').isNotEmpty ? pick('director') : null,
      actors: pick('actors').isNotEmpty ? pick('actors') : null,
      status: pick('status'),
      tags: _tags(pick('tags')),
      updatedAt: _parseDateTime(pick('updatedAt')),
      episodeCount: int.tryParse(pick('episodeCount')),
      wordCount: pick('wordCount').isNotEmpty ? pick('wordCount') : null,
    );

    // 解析季列表（可选）：源 selectors 中声明 `seasons` 子选择器时，
    // 按相同 item 选择器模式递归解析为 List<MediaItem>。未声明则保持 null。
    final seasonsSel = sel['seasons'];
    if (seasonsSel is Map) {
      final sub = Map<String, dynamic>.from(seasonsSel);
      final listPath = sub['list'] as String? ?? '\$.seasons';
      final items = JsonPath.eval(listPath, item);
      if (items is List) {
        final seasons = <MediaItem>[
          for (final s in items)
            if (s is Map)
              _itemFromJsonSelector(s, sub, source, baseUrl: baseUrl),
        ];
        if (seasons.isNotEmpty) return base.copyWith(seasons: seasons);
      }
    }
    return base;
  }

  List<Episode> _episodesFromJsonSelector(
    dynamic json,
    Map<String, dynamic> sel,
    PluginConfig source,
  ) {
    // episodes / chapters 两个 API 共用本方法；selector 键可能是
    // `episodes` 或 `chapters`，二者皆兼容。
    final epSel = sel['episodes'] ?? sel['chapters'];
    if (epSel is Map) {
      final listPath = epSel['list'] as String? ?? '\$.list';
      final items = JsonPath.eval(listPath, json);
      if (items is List) {
        return [
          for (final it in items)
            if (it is Map)
              Episode(
                id: _js(it, epSel['id'] ?? 'id'),
                title: _js(it, epSel['title'] ?? 'title'),
                url: _js(it, epSel['url'] ?? 'url'),
                updatedAt: _parseDateTime(_js(it, epSel['updatedAt'] ?? 'updatedAt')),
                number: _parseInt(_js(it, epSel['number'] ?? 'number')),
              ),
        ];
      }
    }
    final raw = epSel is String ? JsonPath.eval(epSel, json) : null;
    if (raw is List) {
      return [
        for (final it in raw)
          if (it is Map)
            Episode(
              id: it['id']?.toString() ?? '',
              title: it['title']?.toString() ?? '',
              url: it['url']?.toString() ?? '',
              updatedAt: _parseDateTime(it['updatedAt']),
              number: _parseInt(it['number']),
            ),
      ];
    }
    return const [];
  }

  dynamic _videoFromJsonSelector(dynamic json, Map<String, dynamic> sel) {
    final v = sel['video'];
    if (v is String) {
      final url = JsonPath.eval(v, json);
      return _videoResult(url?.toString() ?? '');
    }
    if (v is Map) {
      return _videoResult(
        JsonPath.eval(v['url'] ?? 'url', json)?.toString() ?? '',
        type: v['type'] as String?,
      );
    }
    return _videoResult('');
  }

  VideoResult _videoResult(String url, {String? type}) =>
      VideoResult(url: url, type: type ?? _guessType(url));

  // ---- HTML ----

  dynamic _parseHtml(
    PluginConfig source,
    String apiName,
    String html, {
    required String baseUrl,
  }) {
    final sel = source.selectors ?? const <String, dynamic>{};
    // Extract sub-selectors per apiName (e.g. selectors.latest.{list,id,title,
    // cover}), aligning with the JSON path's _subSel behaviour. certain sources
    // group each API's selectors under its apiName; without extraction
    // sel['list'] / sel['id'] are null and downstream helpers fall back to
    // the default CSS selectors, producing empty MediaItem fields. When the
    // sub-map is absent (flat selector shape) we fall back to sel itself,
    // preserving backward compatibility.
    // 字段搜索路由（searchByAuthor / searchByTag / ...）若未单独声明选择器，
    // 自动复用 `search` 分组的 selectors（源即插件：解析规则只写一处）。
    final sub = _subSel(sel, apiName, _searchSelFallback(sel, apiName));
    switch (apiName) {
      case 'detail':
        return _itemFromHtmlSelector(html, sub, source, baseUrl);
      case 'episodes':
      case 'chapters':
        // episodes/chapters share selectors: prefer the sub-map keyed by the
        // current apiName; if absent, fall back to the other one, then to the
        // top-level sel. This keeps compatibility with sources that only
        // declare one of episodes/chapters while routing both apiNames here.
        final epSub = _subSel(sel, apiName,
            _subSel(sel, 'episodes', _subSel(sel, 'chapters', sel)));
        return _episodesFromHtmlSelector(html, epSub, source);
      case 'images':
        return _imagesFromHtmlSelector(html, sub, baseUrl: baseUrl);
      case 'video':
        return _videoFromHtmlSelector(html, sub, baseUrl: baseUrl);
      case 'week':
        return _weekFromHtmlSelector(html, sub, source, baseUrl);
      default:
        return _itemsFromHtmlSelector(html, sub, source, baseUrl);
    }
  }

  List<MediaItem> _itemsFromHtmlSelector(
    String html,
    Map<String, dynamic> sel,
    PluginConfig source, [
    String? baseUrl,
  ]) {
    final listSel = sel['list'] as String? ?? 'div.item';
    final elements = HtmlUtils.elements(html, listSel);
    debugPrint('[BuiltinResolver] listSel=$listSel elements=${elements.length}');
    // 通用垃圾卡过滤：id 与 title 同时为空的条目不进列表（广告占位卡、
    // 无法取到关键信息的卡片等）。对齐既有解析器「字段取不到即跳过」
    // 的语义（如 `?.let(::add)`），不针对任何特定站点/广告域名特判。
    final items = <MediaItem>[
      for (final el in elements) _itemFromElement(el, sel, source, baseUrl),
    ];
    final filtered =
        items.where((it) => it.id.isNotEmpty || it.title.isNotEmpty).toList();
    final dropped = items.length - filtered.length;
    if (dropped > 0) {
      debugPrint('[BuiltinResolver] dropped $dropped empty cards (id+title both blank)');
    }
    return filtered;
  }

  /// 周更列表解析（「周期表」Tab 专用）。
  ///
  /// 站点 `/week` 页面含 7 个天块（如 `ul.week-content[data-key="N"]`，
  /// N=0..6 对应周一..周日），每个天块内含若干 `<li>` 条目。逐块解析并把
  /// 该块的星期几写入每项的 [MediaItem.updatedAt]，使 [OnlineScheduleSection]
  /// 能按 `updatedAt.weekday` 正确分组到 周一..周日。日期的年月日无关紧要，
  /// 仅星期几参与分组。
  List<MediaItem> _weekFromHtmlSelector(
    String html,
    Map<String, dynamic> sel,
    PluginConfig source, [
    String? baseUrl,
  ]) {
    final blocksSel = sel['dayBlocks'] as String? ?? 'ul.week-content';
    final dayAttr = sel['dayIndexAttr'] as String? ?? 'data-key';
    final itemSel = sel['item'] as String? ?? 'li';
    final blocks = HtmlUtils.elements(html, blocksSel);
    final items = <MediaItem>[];
    for (final block in blocks) {
      final dayIdx = int.tryParse(block.attributes[dayAttr] ?? '');
      if (dayIdx == null || dayIdx < 0 || dayIdx > 6) continue;
      final date = _dateForWeekday(dayIdx);
      for (final el in block.querySelectorAll(itemSel)) {
        final it = _itemFromElement(el, sel, source, baseUrl);
        // updatedAt 由天块星期几注入（selectors.week 不声明 updatedAt）。
        items.add(it.updatedAt == null ? it.copyWith(updatedAt: date) : it);
      }
    }
    return items;
  }

  /// 星期索引(0=周一 … 6=周日) → 本周对应星期几的日期。
  ///
  /// 仅用于周期表分组，年份/月份不影响结果（[OnlineScheduleSection] 只看 weekday）。
  DateTime _dateForWeekday(int dayIndex) {
    final now = DateTime.now();
    // 本周周一（DateTime.weekday=1）零点。
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    return monday.add(Duration(days: dayIndex));
  }

  /// 从条目的 [MediaItem.status]（如 "45|周日"）解析开播星期几，
  /// 返回本周对应日期；无法解析时保留原 updatedAt。用于「周期表」按真实
  /// 开播日分组（而非最后更新时间）。站点把开播星期写在集数后面，如
  /// "12|周六21:15" → 周六。
  DateTime? _airingDateFor(MediaItem it) {
    final wd = _parseCnWeekday(it.status);
    if (wd == null) return it.updatedAt;
    return _dateForWeekday(wd);
  }

  /// 解析中文星期（周一…周日）为索引 0…6（0=周一），与 [_dateForWeekday] 对齐。
  static int? _parseCnWeekday(String? s) {
    if (s == null || s.isEmpty) return null;
    const map = <String, int>{
      '周一': 0,
      '周二': 1,
      '周三': 2,
      '周四': 3,
      '周五': 4,
      '周六': 5,
      '周日': 6,
    };
    for (final e in map.entries) {
      if (s.contains(e.key)) return e.value;
    }
    return null;
  }

  MediaItem _itemFromHtmlSelector(
    String html,
    Map<String, dynamic> sel,
    PluginConfig source, [
    String? baseUrl,
  ]) {
    final root = HtmlUtils.parse(html);
    return _itemFromElement(root.documentElement!, sel, source, baseUrl);
  }

  /// 按顶层逗号拆分复合选择器（保护引号、括号与方括号内的逗号，
  /// 如 `substring-after(x, ',')`、`[data-x="1,2"]` 不被误切）。
  List<String> _splitTopLevel(String p) {
    final out = <String>[];
    final buf = StringBuffer();
    var depth = 0;
    var inSingle = false;
    var inDouble = false;
    for (var i = 0; i < p.length; i++) {
      final c = p[i];
      if (inSingle) {
        buf.write(c);
        if (c == "'") inSingle = false;
      } else if (inDouble) {
        buf.write(c);
        if (c == '"') inDouble = false;
      } else if (c == "'" || c == '"') {
        if (c == "'") {
          inSingle = true;
        } else {
          inDouble = true;
        }
        buf.write(c);
      } else if (c == '(' || c == '[') {
        depth++;
        buf.write(c);
      } else if (c == ')' || c == ']') {
        if (depth > 0) depth--;
        buf.write(c);
      } else if (c == ',' && depth == 0) {
        final part = buf.toString().trim();
        if (part.isNotEmpty) out.add(part);
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    final tail = buf.toString().trim();
    if (tail.isNotEmpty) out.add(tail);
    return out;
  }

  /// 解析单个选择器分支：
  /// - `@attr`（无 CSS 前缀）→ 列表元素自身属性（list 选中 `<a>` 卡时取
  ///   自身 href；`@text`/`@text()` → 自身文本）；
  /// - XPath（`//a/@href`、`./@data-href` 等）→ HtmlUtils 引擎；
  /// - `css@attr` → 首个匹配元素的属性；
  /// - 纯 css → 首个匹配元素的文本。
  String _pickBranch(Element el, String Function() elHtml, String branch) {
    if (branch.startsWith('@')) {
      final a = branch.substring(1);
      if (a == 'text' || a == 'text()') return el.text.trim();
      return el.attributes[a] ?? '';
    }
    if (HtmlUtils.isXPath(branch)) {
      return HtmlUtils.query(elHtml(), branch) ?? '';
    }
    final at = branch.indexOf('@');
    if (at >= 0) {
      final css = branch.substring(0, at).trim();
      final a = branch.substring(at + 1).trim();
      if (css.isEmpty) return el.attributes[a] ?? '';
      return el.querySelector(css)?.attributes[a] ?? '';
    }
    return el.querySelector(branch)?.text.trim() ?? '';
  }

  MediaItem _itemFromElement(
    Element el,
    Map<String, dynamic> sel,
    PluginConfig source, [
    String? baseUrl,
  ]) {
    // Lazily serialised only when an XPath field selector is encountered
    // (some sources use relative XPath like `./a/@title` which cannot be
    // evaluated via querySelector). Cached to avoid re-serialising per field.
    String? elHtmlCache;
    String elHtml() => elHtmlCache ??= el.outerHtml;

    String pick(String key, {bool attr = false}) {
      final p = sel[key];
      if (p == null) return '';
      if (p is! String) return '';
      // 按顶层逗号拆成多分支逐支解析（css@attr / css / @attr / XPath 可混合），
      // 取第一个非空结果。此前整串交给一次 querySelector，导致
      // `video#player@poster, meta[property="og:image"]@content` 这类混合
      // @attr 组合整体失效（详情页封面/描述等字段缺失的根因）。
      for (final branch in _splitTopLevel(p)) {
        final v = _pickBranch(el, elHtml, branch);
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    // 多值字段取全部匹配节点并以「, 」连接（导演/主演/类型等常有多个）。
    // 关键修复：pick() 走 HtmlUtils.query 只取首个节点，导致多位演员/多个类型
    // 只剩第一个；这里改用 queryAll / querySelectorAll 取齐所有值。
    String pickJoined(String key) {
      final p = sel[key];
      if (p == null || p is! String || p.isEmpty) return '';
      // 与 pick() 同构：按顶层逗号拆多分支，逐支取齐所有值后合并去重。
      List<String> vals = <String>[];
      for (final branch in _splitTopLevel(p)) {
        List<String> part;
        if (branch.startsWith('@')) {
          final a = branch.substring(1);
          final v = (a == 'text' || a == 'text()') ? el.text : (el.attributes[a] ?? '');
          part = v.trim().isEmpty ? const <String>[] : <String>[v.trim()];
        } else if (HtmlUtils.isXPath(branch)) {
          part = HtmlUtils.queryAll(elHtml(), branch);
        } else {
          final at = branch.indexOf('@');
          if (at >= 0) {
            final css = branch.substring(0, at).trim();
            final a = branch.substring(at + 1).trim();
            part = css.isEmpty
                ? (el.attributes.containsKey(a)
                    ? <String>[el.attributes[a] ?? '']
                    : const <String>[])
                : el.querySelectorAll(css).map((e) => e.attributes[a] ?? '').toList();
          } else {
            part = el.querySelectorAll(branch).map((e) => e.text.trim()).toList();
          }
        }
        vals.addAll(part);
      }
      // 多分支去重（保持顺序）：如 `.title, .video-title` 命中同一节点的
      // 两支时只保留一份。
      final seen = <String>{};
      return vals
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && seen.add(s))
          .toList()
          .join(', ');
    }

    String? nullIfEmpty(String s) => s.isEmpty ? null : s;

    final id = pick('id');
    final explicitDetailUrl = pick('detailUrl', attr: true).isNotEmpty
        ? pick('detailUrl', attr: true)
        : pick('detail', attr: true);
    final derivedDetailUrl = _detailUrlFromId(id, source);
    final detailUrl = explicitDetailUrl.isNotEmpty
        ? explicitDetailUrl
        : (derivedDetailUrl ?? '');

    final base = MediaItem(
      id: id,
      title: pick('title'),
      coverUrl: _absoluteCoverUrl(pick('cover', attr: true), baseUrl, source),
      detailUrl: detailUrl.isNotEmpty ? detailUrl : null,
      sourceId: source.id,
      sourceType: source.type,
      description: pick('description').isNotEmpty ? pick('description') : pick('intro'),
      author: nullIfEmpty(pickJoined('author')),
      director: nullIfEmpty(pickJoined('director')),
      actors: nullIfEmpty(pickJoined('actors')),
      year: nullIfEmpty(pick('year')),
      status: pick('status'),
      // tags 用 pickJoined 取齐所有类型/标签节点后再按分隔符拆分，
      // 兼容「单节点逗号串」（meta keywords）与「多节点链接」两种写法。
      tags: _tags(pickJoined('tags')),
      updatedAt: _parseDateTime(pick('updatedAt')),
      episodeCount: int.tryParse(pick('episodeCount')),
      wordCount: pick('wordCount').isNotEmpty ? pick('wordCount') : null,
    );

    // 解析季列表（可选）：源 selectors 中声明 `seasons` 子选择器时，
    // 按 CSS 选择器取出季元素并递归解析为 List<MediaItem>。
    final seasonsSel = sel['seasons'];
    if (seasonsSel is Map) {
      final sub = Map<String, dynamic>.from(seasonsSel);
      final listSel = sub['list'] as String? ?? 'div.season';
      final elements = el.querySelectorAll(listSel);
      if (elements.isNotEmpty) {
        final seasons = <MediaItem>[
          for (final s in elements) _itemFromElement(s, sub, source, baseUrl),
        ];
        if (seasons.isNotEmpty) return base.copyWith(seasons: seasons);
      }
    }
    return base;
  }

  List<Episode> _episodesFromHtmlSelector(
    String html,
    Map<String, dynamic> sel,
    PluginConfig source,
  ) {
    // Selector shapes (priority high→low):
    // 1. Nested map: sel = {episodes: {list, title, id, url}} or {chapters:...}
    //    (either as the extracted sub-map from _parseHtml, or nested in place).
    // 2. Flat legacy string: sel = {episodes: "div.chapter a"} — wins over
    //    shape 3 even when a top-level `list` string exists (that string
    //    belongs to the JSON list APIs, not the HTML episode selector).
    // 3. Extracted sub-map only: sel = {list, title, url} (no episodes key).
    final epSelRaw = sel['episodes'] ?? sel['chapters'];
    String listSel;
    Map<String, dynamic> fieldSel;
    if (epSelRaw is Map) {
      final m = Map<String, dynamic>.from(epSelRaw);
      listSel = m['list'] as String? ?? 'div.chapter a';
      fieldSel = m;
    } else if (epSelRaw is String && epSelRaw.isNotEmpty) {
      // 扁平旧形态（字符串选择器）必须优先于下方「已提取子表」分支：
      // 声明了顶层 `list`（JSONPath 列表源的 `$.list`）的源，其字符串形态
      // 的 episodes 选择器此前会被 sel['list'] 劫持成 HTML 列表选择器
      // （`$.list` 不是合法 CSS → querySelectorAll 抛 FormatException →
      // 详情页剧集解析直接失败）。
      listSel = epSelRaw;
      fieldSel = const <String, dynamic>{};
    } else if (sel['list'] is String || sel['lineList'] is String) {
      // Sub-map already extracted by _parseHtml.
      listSel = sel['list'] as String? ?? 'div.chapter a';
      fieldSel = sel;
    } else {
      // Flat shape or string selector only.
      listSel = epSelRaw as String? ?? 'div.chapter a';
      fieldSel = const <String, dynamic>{};
    }

    // 线路模式（影视多线路：繁中/简中/线路一…）：源声明 `lineList` 时，按线路容器
    // 分组解析，每条线路的剧集写入 Episode.lineName，供 UI 分组展示、避免多线路
    // 剧集混在一起看起来「重复」。`lineName` 为平行选择器（与线路容器同序），
    // 取到的名字去除尾部数字徽标（如「繁中4」→「繁中」）。向后兼容：无 lineList
    // 时走原扁平逻辑。
    final lineListSel = fieldSel['lineList'];
    if (lineListSel is String && lineListSel.isNotEmpty) {
      final containers = HtmlUtils.elements(html, lineListSel);
      final lineNameSel = fieldSel['lineName'];
      final lineNames = (lineNameSel is String && lineNameSel.isNotEmpty)
          ? HtmlUtils.queryAll(html, lineNameSel).map(_cleanLineName).toList()
          : const <String>[];
      final innerListSel = fieldSel['list'] as String? ?? './/a';
      final result = <Episode>[];
      for (var i = 0; i < containers.length; i++) {
        final cHtml = containers[i].outerHtml;
        final lineName = i < lineNames.length ? lineNames[i] : '';
        for (final el in HtmlUtils.elements(cHtml, innerListSel)) {
          final ep = _episodeFromElement(el, fieldSel);
          result.add(lineName.isEmpty ? ep : ep.copyWith(lineName: lineName));
        }
      }
      if (result.isNotEmpty) return result;
      // 线路容器解析为空则回退到扁平逻辑，避免整源无剧集。
    }

    final elements = HtmlUtils.elements(html, listSel);
    return [
      for (final el in elements)
        _episodeFromElement(el, fieldSel),
    ];
  }

  /// 清理线路名：去掉尾部的数字徽标与空白（macCMS 线路 tab 常带集数徽标，
  /// 如「繁中4」「简中4」→「繁中」「简中」）。仅去除 ASCII 数字，保留中文数字
  /// 命名（如「线路一」）。
  String _cleanLineName(String raw) =>
      raw.replaceAll(RegExp(r'[\s\d]+$'), '').trim();

  /// 从 item id 推导 detailUrl（通用兜底，共创式）。
  ///
  /// 很多源（尤其漫画源）的列表选择器把 `id` 设为 `a@href`，直接拿到相对详情
  /// 路径（如 `/manga/xxx`），但并未声明 `detailUrl`/`detail` 选择器。此时若
  /// detail 路由再拼一次前缀会得到错误 URL。这里直接识别 id 为 URL/路径时，
  /// 用 id 自身作为 detailUrl（相对路径补 base host）。
  String? _detailUrlFromId(String id, PluginConfig source) {
    if (id.isEmpty) return null;
    if (id.startsWith('http://') || id.startsWith('https://')) return id;
    if (id.startsWith('/')) {
      final base = ConfigLoader.instance.getActiveMirror(source);
      final b = base.endsWith('/')
          ? base.substring(0, base.length - 1)
          : base;
      return '$b$id';
    }
    return null;
  }

  /// Episode element may itself be an <a> or contain one; unify href / title
  /// extraction. When [sel] declares id/title/url selectors (XPath or
  /// `css@attr` form, as in some sources), they take precedence over the <a>
  /// fallback so per-source extraction rules win.
  Episode _episodeFromElement(Element el, Map<String, dynamic> sel) {
    // Lazily serialised only when an XPath field selector is encountered
    // (some sources use relative XPath like `./@href`, `./text()` which cannot
    // be evaluated via querySelector). Cached to avoid re-serialising per
    // field.
    String? elHtmlCache;
    String elHtml() => elHtmlCache ??= el.outerHtml;

    String pick(String key) {
      final p = sel[key];
      if (p is! String) return '';
      for (final branch in _splitTopLevel(p)) {
        final v = _pickBranch(el, elHtml, branch);
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    final a = el.querySelector('a');
    final target = a ?? el;
    final fallbackHref = target.attributes['href'] ?? '';
    final fallbackTitle = (a?.text.trim() ?? el.text.trim());
    final pickedUrl = pick('url');
    final pickedTitle = pick('title');
    final pickedId = pick('id');
    final href = pickedUrl.isNotEmpty ? pickedUrl : fallbackHref;
    final title = pickedTitle.isNotEmpty ? pickedTitle : fallbackTitle;
    final id =
        pickedId.isNotEmpty ? pickedId : (href.isNotEmpty ? href : title);
    return Episode(
      id: id,
      title: title,
      url: href,
      updatedAt: _parseDateTime(pick('updatedAt')),
      number: _parseInt(pick('number')),
    );
  }

  /// 解析漫画图片列表（HTML）：`images` 支持 `img@data-src` 形式的属性选择器、
  /// 普通 CSS 选择器（读取 src / data-src），或对象形式 `{ config: {...} }`
  /// 委托 ImageExtractor.getPageUrls 处理懒加载/分页。结果经 ImageExtractor
  /// 清洗（绝对 URL 补全 + 广告/占位图过滤 + 去重）。
  List<String> _imagesFromHtmlSelector(
    String html,
    Map<String, dynamic> sel, {
    required String baseUrl,
  }) {
    final imgSel = sel['images'];
    List<String> raw;
    if (imgSel is Map && imgSel['config'] is Map) {
      raw = ImageExtractor.getPageUrls(
        html,
        Map<String, dynamic>.from(imgSel['config'] as Map),
        baseUrl: baseUrl,
      );
    } else {
      final selStr = imgSel is String ? imgSel : 'img';
      String css = selStr;
      String? attr;
      if (selStr.contains('@')) {
        css = selStr.substring(0, selStr.indexOf('@')).trim();
        attr = selStr.substring(selStr.indexOf('@') + 1).trim();
      }
      final elements = HtmlUtils.elements(html, css);
      raw = <String>[
        for (final el in elements) _imageAttr(el, attr),
      ].where((s) => s.isNotEmpty).toList();
    }
    final abs = <String>[
      for (final u in raw) ImageExtractor.toAbsolute(u, baseUrl),
    ];
    return ImageExtractor.filterImages(abs);
  }

  String _imageAttr(Element el, String? attr) {
    final img = el.querySelector('img');
    final target = img ?? el;
    if (attr != null) {
      return target.attributes[attr] ?? '';
    }
    return target.attributes['src'] ??
        target.attributes['data-src'] ??
        target.attributes['data-original'] ??
        '';
  }

  /// 解析 HTML video 路由：selector 优先（支持 `css@attr` 形式），
  /// 无 selector 或无命中时回退到 [VideoExtractor] 从 `<video>` /
  /// `<iframe>` / `<source>` 标签抽取首个视频 URL。
  dynamic _videoFromHtmlSelector(
    String html,
    Map<String, dynamic> sel, {
    required String baseUrl,
  }) {
    final v = sel['video'];
    if (v is String && v.contains('@')) {
      final css = v.substring(0, v.indexOf('@')).trim();
      final attr = v.substring(v.indexOf('@') + 1).trim();
      final els = HtmlUtils.elements(html, css);
      if (els.isNotEmpty) {
        final src = els.first.attributes[attr] ?? '';
        if (src.isNotEmpty) {
          return _videoResult(_toAbsolute(src, baseUrl));
        }
      }
    }
    final extracted = VideoExtractor.extract(html, baseUrl: baseUrl);
    if (extracted.isNotEmpty) {
      final first = extracted.first;
      return VideoResult(url: first.url, type: _guessType(first.url));
    }
    return _videoResult('');
  }

  /// 封面相对路径补全为绝对 URL。
  ///
  /// MacCMS 等源的 `vod_pic` 常返回根相对路径（`/upload/vod/x.webp`）；
  /// 不补全会流入 UI 层（AppCoverImage/SourceImage 以 `http` 前缀区分
  /// 网络图与本地文件图），相对路径被当作本地文件渲染，封面永远空白。
  /// 以本次请求实际使用的 baseUrl（活动镜像）为基准补全；已是绝对地址、
  /// 非 http(s) 特殊 scheme（data: 等）或取不到基准时原样返回。
  /// 补全后按源声明的 [PluginConfig.mediaHostRewrite] 改写媒体域名（签名 CDN
  /// 禁 Referer / 主 CDN 拒直连等场景的备用域切换，映射表由源 JSON 声明）。
  String? _absoluteCoverUrl(String? raw, String? baseUrl, [PluginConfig? source]) {
    var s = raw?.trim() ?? '';
    if (s.isEmpty) return null;
    if (s.startsWith('http://') || s.startsWith('https://')) {
      return _rewriteMediaHost(s, source);
    }
    if (!s.startsWith('/') && !s.startsWith('//')) return s;
    if (baseUrl == null || baseUrl.isEmpty) return s;
    try {
      return _rewriteMediaHost(_toAbsolute(s, baseUrl), source);
    } on Object {
      return s;
    }
  }

  /// 按源声明的 mediaHostRewrite 映射改写 URL 的 host（精确匹配，大小写不敏感）。
  String? _rewriteMediaHost(String? url, PluginConfig? source) {
    final rewrite = source?.mediaHostRewrite;
    if (rewrite == null || rewrite.isEmpty || url == null || url.isEmpty) return url;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    final target = rewrite[uri.host.toLowerCase()];
    if (target == null || target.isEmpty) return url;
    try {
      return uri.replace(host: target).toString();
    } on Object {
      return url;
    }
  }

  /// 将相对 URL 基于 baseUrl 解析为绝对 URL。
  String _toAbsolute(String url, String baseUrl) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('//')) {
      final baseUri = Uri.parse(baseUrl);
      return '${baseUri.scheme}:$url';
    }
    if (url.startsWith('/')) {
      final baseUri = Uri.parse(baseUrl);
      return '${baseUri.scheme}://${baseUri.host}$url';
    }
    final dir = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return Uri.parse(dir).resolve(url).toString();
  }

  // ---- helpers ----

  Map<String, dynamic> _subSel(
    Map<String, dynamic> sel,
    String key,
    Map<String, dynamic> fallback,
  ) {
    final sub = sel[key];
    return sub is Map<String, dynamic> ? sub : fallback;
  }

  /// 字段搜索路由（searchByAuthor / searchByTag / searchByDirector /
  /// searchByActor / searchByWork）的 selectors 兜底。
  ///
  /// 源只需声明 `searchByXxx` 的路由 URL（指向站点搜索端点，字段值作 keyword），
  /// 无需重复粘贴 `search` 的选择器：当该 apiName 未单独声明选择器分组时，
  /// 自动复用 `selectors['search']`，实现真正的源端按字段检索且不重复配置
  /// （源即插件：解析规则只写一处）。非 searchBy* 路由或不存在 search 分组时，
  /// 回退到 [fallback]（顶层 selectors），保持既有行为。
  Map<String, dynamic> _searchSelFallback(
    Map<String, dynamic> sel,
    String apiName,
  ) {
    if (apiName != 'search' && apiName.startsWith('searchBy')) {
      final searchSel = sel['search'];
      if (searchSel is Map<String, dynamic>) return searchSel;
    }
    return sel;
  }

  String _js(dynamic item, dynamic path) {
    if (path is! String) return '';
    // JSONPath 形式（`$.a.b`）走求值器；相对键（如 `url`）直接取字段。
    if (path.startsWith('\$')) {
      final v = JsonPath.eval(path, item);
      return v?.toString() ?? '';
    }
    if (item is Map) {
      final v = item[path];
      return v?.toString() ?? '';
    }
    return '';
  }

  List<String>? _tags(String s) {
    if (s.isEmpty) return null;
    // 去重保序：详情页同一组标签锚点常在页面出现多次（如打驴动漫详情页
    // /vod/search/class/ 链接渲染两遍），pickJoined 会取齐全部节点导致
    // 「动画,热门新番,动画,热门新番」标签翻倍。用 LinkedHashSet 语义去重。
    final seen = <String>{};
    return s
        .split(RegExp(r'[,，/、|\s]+'))
        .where((t) => t.isNotEmpty && seen.add(t))
        .toList();
  }

  String _guessType(String url) {
    if (url.contains('.m3u8')) return 'm3u8';
    if (url.contains('.mp4')) return 'mp4';
    if (url.contains('manifest') || url.contains('mpd')) return 'dash';
    return 'unknown';
  }

  /// 解析 ISO/通用日期字符串或毫秒/秒级时间戳。
  DateTime? _parseDateTime(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is int) {
      if (v > 9999999999) return DateTime.fromMillisecondsSinceEpoch(v);
      return DateTime.fromMillisecondsSinceEpoch(v * 1000);
    }
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }
}
