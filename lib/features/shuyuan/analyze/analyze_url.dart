/// URL 解析器：处理书源 URL 中的 `{{key}}`/`{{page}}`/`{{...JS...}}` 占位符、
/// `,{"method":"POST","body":"...","charset":"gbk"}` 选项后缀、`<js>`/`@js:` 内嵌脚本，
/// 并执行 HTTP 请求（含 GBK 等字符集解码与重定向跟随）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'concurrent_rate_limiter.dart';
import 'package:dio/io.dart';
import 'package:fast_gbk/fast_gbk.dart';
import '../../../core/utils/app_log.dart';
import 'analyze_rule.dart';
import 'js_engine.dart';
import 'webview_fetcher.dart';
import '../../../core/scraper/browser_faithful_adapter.dart';
import '../../../core/scraper/verification_detector.dart';
import '../../../core/scraper/http_fetcher.dart';
import '../model/xiaoshuo_book.dart';
import '../model/xiaoshuo_book_chapter.dart';
import '../model/book_source.dart';
import 'source_context.dart';

class AnalyzeUrl {
  String url;
  String? baseUrl;
  XiaoshuoBookSource? source;
  XiaoshuoBook? ruleData;

  /// 搜索条目上下文（API 返回的 URL 字段含 {{\$.field}} 模板时，URL 级
  /// 规则求值的根）。由 WebBook 从搜索阶段暂存、详情/目录阶段传入。
  Object? itemContext;
  XiaoshuoBookChapter? chapter;
  int page;
  String? key;
  String? speakText;
  int? speakSpeed;

  final Map<String, String> headerMap = {};
  String? body;
  String? method;
  String? charset;
  int retry = 0;
  bool useWebView = false;
  String? webJs;
  String? bodyJs;
  String? proxy;
  String? dnsIp;
  String? requestType;
  int webViewDelayTime = 0;

  /// 构造时的原始 URL 模板（`initUrl()` 重新解析的起点）。
  late final String _rawUrl;

  /// legado `AnalyzeUrl.ruleUrl`：`<js>`/`{{}}` 展开后、选项后缀剥离前的
  /// 形态。loginCheckJs 里 `java.ruleUrl` 读它（重试请求定位用）。
  String ruleUrl = '';

  /// 请求头替换模式（legado `headerMapF` 语义）：true 时请求头只由
  /// [headerMap] + 显式 headers 参数组成，不再叠加默认 UA/Accept、
  /// 源 header 与登录头；Cookie 通道保留（legado `setCookie()` 在
  /// headerMapF 下仍合并 CookieStore，显式 Cookie 优先）。
  bool _headerMapReplaced = false;

  /// 本实例最后一次真实抓取写入的阶段缓存键。loginCheck 重取同一地址前
  /// 移除它：legado 的 `java.getStrResponse()` 是真实请求，不能命中首取
  /// 写入的阶段缓存（否则重取原样返回旧墙页）。
  String? _lastCacheKey;

  /// 最近一次 [getStrResponse] 的原始响应字节（未解码）。
  /// `org.jsoup…bodyAsBytes()` 的 settle 重放需要无损二进制
  /// （AES 密文按 UTF-8 容错解码会丢字节，无法还原明文）。
  Uint8List? lastResponseBytes;

  /// 最近一次真实请求的响应元数据（settle 回放给 java.connect/get/post/head：
  /// `statusCode()` / `headers()` / `header("Location")` / `cookies()` /
  /// `.raw().request().url()` 都依赖它）。页面缓存命中时为 null（无新请求）。
  int? lastStatusCode;
  Map<String, List<String>>? lastResponseHeaders;
  String? lastFinalUrl;

  /// URL 选项 `followRedirects`：`java.get/post/head` 对齐 legado 的
  /// Jsoup `followRedirects(false)`（302 响应头 Location 是搜索 URL 的
  /// 常见来源）；`java.connect`/`java.ajax` 走默认跟随（重定向后的最终
  /// 地址是 `raw().request().url()` 的基址发现来源）。null = 跟随。
  bool? followRedirects;

  /// URL 内 JS 的求值器（同一 AnalyzeUrl 内复用，连同其 JS 引擎）。
  /// 一个 URL 模板常有多个 `{{...}}`，旧实现每个都 new AnalyzeRule →
  /// new QuickJS 运行时且从不释放。
  AnalyzeRule? _urlRule;

  // 静态 Dio 实例提升性能
  static final Dio _dio = Dio()
    ..options.connectTimeout = const Duration(seconds: 15)
    ..options.receiveTimeout = const Duration(seconds: 30)
    ..options.validateStatus =
        ((status) => status != null && status >= 200 && status < 300)
    // 书源直连链路改用浏览器一致的原始请求（Host 首行 + Title-Case
    // 头名）：部分 Cloudflare 站（如笔趣阁）会按 Dart HttpClient 固定的「小写
    // 头名 + Host 排末行」机器指纹直接返回 403 挑战壳，使验证无法通过。
    ..httpClientAdapter = BrowserFaithfulHttpClientAdapter();

  AnalyzeUrl({
    required this.url,
    this.baseUrl,
    this.source,
    this.ruleData,
    this.itemContext,
    this.chapter,
    this.page = 1,
    this.key,
    this.speakText,
    this.speakSpeed,
    Map<String, String>? headerMapF,
  }) {
    _rawUrl = url;
    // legado AnalyzeUrl init：baseUrl 命中 URL 选项串即截断，后续任何
    // `getAbsoluteURL(baseUrl, …)` 都不会把 `,{...}` 卷进基准路径。
    final baseOption = RegExp(r',\s*\{').firstMatch(baseUrl ?? '');
    if (baseOption != null) {
      baseUrl = baseUrl!.substring(0, baseOption.start);
    }
    if (headerMapF != null) {
      _headerMapReplaced = true;
      headerMap.addAll(headerMapF);
      if (headerMapF.containsKey('proxy')) {
        proxy = headerMapF['proxy'];
        headerMap.remove('proxy');
      }
    }

    _initUrl();
  }

  void _initUrl() {
    analyzeJs();
    replaceKeyPageJs();
    ruleUrl = url;
    analyzeUrl();
  }

  /// legado `AnalyzeUrl.initUrl()` 的再解析：回到原始模板重新展开。
  /// loginCheckJs 里脚本在重试请求前调用，通常是让模板重新读当前会话
  /// 状态（时间戳/随机数参数）；同步 JS 内无法回跳宿主，由宿主在求值前
  /// 按脚本声明预执行一次。
  void reinitUrl() {
    url = _rawUrl;
    _initUrl();
  }

  void analyzeJs() {
    final jsPattern = RegExp(r'<js>([\w\W]*?)</js>|@js:([\w\W]*)', caseSensitive: false);
    final matches = jsPattern.allMatches(url).toList();
    var start = 0;
    var result = url;

    for (final match in matches) {
      if (match.start > start) {
        final segment = url.substring(start, match.start).trim();
        if (segment.isNotEmpty) {
          result = segment.replaceAll('@result', result);
        }
      }
      final jsCode = match.group(2) ?? match.group(1) ?? '';
      final jsResult = _evalJs(jsCode, result);
      result = jsResult;
      start = match.end;
    }

    if (url.length > start) {
      final segment = url.substring(start).trim();
      if (segment.isNotEmpty) {
        result = segment.replaceAll('@result', result);
      }
    }

    url = result;
  }

  void replaceKeyPageJs() {
    if (url.contains('{{') && url.contains('}}')) {
      final jsPattern = RegExp(r'\{\{([\w\W]*?)\}\}');
      url = url.replaceAllMapped(jsPattern, (match) {
        final expr = match.group(1)!;
        if (expr == 'page') {
          return page.toString();
        }
        if (expr == 'key') {
          // 占位符替换为「原始关键词」而非预编码值：编码统一延迟到
          // [analyzeUrl] 之后按源声明的 charset 处理（GBK 站点按 GBK 编码，
          // 其余按 UTF-8），避免 GBK 站点收到 UTF-8 乱码而搜索无结果。
          return key ?? '';
        }
        final trimmed = expr.trim();
        // 规则形态（$. / $[ / @ / // 开头）→ 规则引擎对 itemContext 求值
        // （legado makeUpRule isRule 路由；API 返回的模板 URL 字段依赖此
        // 通道解析 bid/sourceId 等条目字段）。
        if (itemContext != null &&
            (trimmed.startsWith(r'$.') ||
                trimmed.startsWith(r'$[') ||
                trimmed.startsWith('@') ||
                trimmed.startsWith('//'))) {
          final ar = AnalyzeRule()..setContent(itemContext);
          return ar.getString(trimmed);
        }
        final jsResult = _evalJs(expr, url);
        return jsResult;
      });
    }

    // 通用书源格式兼容：搜索/发现 URL 普遍使用尖括号占位符
    // `<searchKey>`/`<key>`/`<page>`（部分老源用中文书名号《searchKey》/《page》）。
    // 同样替换为原始关键词，编码延后统一处理。
    if (key != null && key!.isNotEmpty) {
      url = url
          .replaceAll('<searchKey>', key!)
          .replaceAll('<key>', key!)
          .replaceAll('《searchKey》', key!)
          .replaceAll('《key》', key!);
    }
    url = url.replaceAll('<page>', page.toString());
    url = url.replaceAll('《page》', page.toString());

    // 兜底：确保任何残留的 {{key}}/{{page}} 被替换（极少见，
    // 仅当上面的正则未覆盖时触发）。
    if (key != null && key!.isNotEmpty) {
      url = url.replaceAll('{{key}}', key!);
    }
    url = url.replaceAll('{{page}}', page.toString());

    // legado 页数备选写法 `<a,b,c>`：按页取第 page 段，超出取最后一段
    // （如分页路径 `/list<,_2,_3>.html` → 第 1 页 /list.html、第 2 页
    // /list_2.html、第 3 页起 /list_3.html）。须在 `<page>` 字面量替换之后，
    // 否则 `<page>` 会被当作只有一个备选段。
    url = url.replaceAllMapped(RegExp(r'<(.*?)>'), (m) {
      final pages = m.group(1)!.split(',');
      final picked = page - 1 < pages.length ? pages[page - 1] : pages.last;
      return picked.trim();
    });
  }

  void analyzeUrl() {
    final originalUrl = url;
    final paramPattern = RegExp(r',\s*\{');
    final paramMatch = paramPattern.firstMatch(originalUrl);
    final urlNoOption = paramMatch != null ? originalUrl.substring(0, paramMatch.start) : originalUrl;

    // 对齐 legado AnalyzeUrl.analyzeUrl：先绝对化再解析选项，选项 js 看到
    // 的是绝对地址与刷新后的 baseUrl；js 结果直接采用，不再二次绝对化。
    url = _getAbsoluteUrl(urlNoOption);
    final legadoBase = _getBaseUrl(url);
    if (legadoBase != null) baseUrl = legadoBase;

    if (paramMatch != null && urlNoOption.length != originalUrl.length) {
      final optionStr = originalUrl.substring(paramMatch.end - 1);
      final option = parseJsonLenient(optionStr);
      if (option != null) {
        method = option['method']?.toString();
        // body 可为字符串或 JSON 对象/数组（QQ 等 API 源的
        // `"body":{"key":"{{key}}"}` 写法）：对象须按 JSON 序列化，
        // 此前 toString() 产出 Dart Map 字面量 `{key: value}` 导致服务端
        // 解析失败 → API 型源搜索全空。
        final rawBody = option['body'];
        if (rawBody is String) {
          body = rawBody;
        } else if (rawBody != null) {
          body = jsonEncode(rawBody);
        }
        charset = option['charset']?.toString();
        retry = option['retry'] ?? 0;
        // legado URL 选项键是 `webView`；`useWebView` 是历史兼容写法。
        final wvRaw = option['webView'] ?? option['useWebView'];
        useWebView = wvRaw == true || '$wvRaw' == 'true';
        webJs = option['webJs']?.toString();
        bodyJs = option['bodyJs']?.toString();
        dnsIp = option['dnsIp']?.toString();
        requestType = option['type']?.toString();
        // legado `max(0, option.webViewDelayTime ?: 0)`：页面加载后额外等待。
        final wvDelay = option['webViewDelayTime'];
        webViewDelayTime = wvDelay is num
            ? wvDelay.toInt()
            : int.tryParse('${wvDelay ?? ''}'.trim()) ?? 0;
        if (webViewDelayTime < 0) webViewDelayTime = 0;
        final frRaw = option['followRedirects'];
        if (frRaw != null) {
          followRedirects = frRaw == true || '$frRaw' == 'true';
        }

        final headers = option['headers'];
        if (headers is Map) {
          for (final entry in headers.entries) {
            headerMap[entry.key.toString()] = entry.value.toString();
          }
        } else if (headers is String && headers.trim().isNotEmpty) {
          // legado UrlOption.getHeaderMap 兼容字符串形态：`"headers":
          // "{Referer:'https://x'}"`（单引号伪 JSON，社区源常见）。
          final decoded = parseJsonLenient(headers);
          if (decoded != null) {
            for (final entry in decoded.entries) {
              headerMap[entry.key.toString()] = entry.value.toString();
            }
          }
        }

        // 内部标记：JS 垫片（java.connect/get/post/head、Jsoup）声明本次
        // 请求按 legado headerMapF 的替换语义发头。
        if (option['_syHeaderMode'] == 'replace') {
          _headerMapReplaced = true;
        }

        final js = option['js']?.toString();
        if (js != null && js.isNotEmpty) {
          url = _evalJs(js, url);
        }
      }
    }

    // 参数编码放在最后（legado analyzeQuery/analyzeFields 次序）。绝对化
    // 由 [_getAbsoluteUrl] 保留原始 query，非 ASCII 值不会被提前转成
    // UTF-8 百分号编码，GBK 站点仍按源声明 charset 编码。
    _encodeRequestParams();
  }

  /// 按源声明的字符集对请求参数编码，逐行对齐 legado
  /// `AnalyzeUrl.analyzeQuery/analyzeFields/encodeParams`：
  /// - GET query：整串已是「query 安全字符 + 合法 `%XX`」则原样，否则按
  ///   字符逐个百分号编码（安全 ASCII 保留，其余取 charset 字节）；
  ///   `charset=escape` 走 JS escape 编码。
  /// - POST form：声明了 Content-Type 时 legado 不做 form 编码；否则按 `&`
  ///   拆分逐键值编码（已编码判定/escape/URLEncoder 三态与 legado 一致）。
  /// - GBK 系站点按 GBK 取字节，其余 UTF-8。
  void _encodeRequestParams() {
    final cs = _normalizeCharset(charset);
    final isPost = method?.toUpperCase() == 'POST';

    if (isPost) {
      final b = body;
      if (b == null || b.isEmpty) return;
      if (_looksLikeStructuredBody(b)) {
        // JSON/XML 请求体：按原文发送，仅补 JSON 的 Content-Type。
        if (b.trimLeft().startsWith('{')) {
          headerMap.putIfAbsent('Content-Type', () => 'application/json');
        }
        return;
      }
      // legado analyzeFields 仅在未声明 Content-Type 时执行。
      if (_headerValue(headerMap, 'Content-Type') != null) return;
      body = _encodeFormLegado(b, cs);
      headerMap.putIfAbsent(
          'Content-Type', () => 'application/x-www-form-urlencoded');
      return;
    }

    // GET：仅编码 query 段（path 由源模板给出，保持原样）。
    final qIdx = url.indexOf('?');
    if (qIdx < 0) return;
    final base = url.substring(0, qIdx);
    final query = url.substring(qIdx + 1);
    if (query.isEmpty) return;
    if (cs == 'escape') {
      url = '$base?${_encodeFormLegado(query, cs)}';
      return;
    }
    // legado `NetworkUtils.encodedQuery`：整串无需编码时原样保留
    // （ASCII 安全字符之外的空格/引号等仍会按 charset 编码）。
    if (_encodedQuery(query)) return;
    url = '$base?${_encodeQueryLegado(query, cs)}';
  }

  /// JSON / XML 请求体判定（这类体不做 form 编码，按原文发送）。
  bool _looksLikeStructuredBody(String b) {
    final t = b.trimLeft();
    return t.startsWith('{') || t.startsWith('[') || t.startsWith('<');
  }

  /// legado `NetworkUtils.encodedQuery`：全部字符为 query 安全字符或合法
  /// `%XX` 序列时视为已编码。
  bool _encodedQuery(String s) {
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c < 128 && _queryNoEncodeChars.contains(s[i])) continue;
      if (c == 0x25 &&
          i + 2 < s.length &&
          _isHexDigit(s.codeUnitAt(i + 1)) &&
          _isHexDigit(s.codeUnitAt(i + 2))) {
        i += 2;
        continue;
      }
      return false;
    }
    return true;
  }

  /// legado `encodeQueryParams`：安全字符原样，其余按字符取 charset 字节
  /// 百分号编码（大写十六进制）。
  String _encodeQueryLegado(String query, String? charsetLower) {
    final sb = StringBuffer();
    for (var i = 0; i < query.length; i++) {
      final ch = query[i];
      final c = query.codeUnitAt(i);
      if (c < 128 && _querySafeChars.contains(ch)) {
        sb.write(ch);
      } else {
        for (final b in _charsetBytes(ch, charsetLower)) {
          sb.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
        }
      }
    }
    return sb.toString();
  }

  /// legado `AnalyzeUrl.encodeParams` 通用分支（POST form / escape query）。
  String _encodeFormLegado(String form, String? rawCharset) {
    final checkEncoded = rawCharset == null || rawCharset.isEmpty;
    final escapeMode = rawCharset == 'escape';
    String encodeValue(String value) {
      if (checkEncoded && _encodedForm(value)) return value;
      if (escapeMode) return _jsEscape(value);
      return _urlEncodeForm(value, rawCharset);
    }

    final out = <String>[];
    for (final pair in form.split('&')) {
      final eq = pair.indexOf('=');
      if (eq < 0) {
        out.add(encodeValue(pair));
      } else {
        out.add('${encodeValue(pair.substring(0, eq))}'
            '=${encodeValue(pair.substring(eq + 1))}');
      }
    }
    return out.join('&');
  }

  /// legado `NetworkUtils.encodedForm`：全为 form 安全字符（字母数字与
  /// `*-._`）或合法 `%XX` 时视为已编码。
  bool _encodedForm(String s) {
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c < 128 && _formNoEncodeChars.contains(s[i])) continue;
      if (c == 0x25 &&
          i + 2 < s.length &&
          _isHexDigit(s.codeUnitAt(i + 1)) &&
          _isHexDigit(s.codeUnitAt(i + 2))) {
        i += 2;
        continue;
      }
      return false;
    }
    return true;
  }

  bool _isHexDigit(int c) =>
      (c >= 0x30 && c <= 0x39) ||
      (c >= 0x41 && c <= 0x46) ||
      (c >= 0x61 && c <= 0x66);

  /// Java `URLEncoder.encode`：字母数字与 `.-*_` 保留，空格转 `+`，其余
  /// 按 charset 字节编码（大写十六进制）。
  String _urlEncodeForm(String value, String? charsetLower) {
    final sb = StringBuffer();
    for (final b in _charsetBytes(value, charsetLower)) {
      final keep = (b >= 0x30 && b <= 0x39) ||
          (b >= 0x41 && b <= 0x5a) ||
          (b >= 0x61 && b <= 0x7a) ||
          b == 0x2e ||
          b == 0x2d ||
          b == 0x2a ||
          b == 0x5f;
      if (keep) {
        sb.writeCharCode(b);
      } else if (b == 0x20) {
        sb.write('+');
      } else {
        sb.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return sb.toString();
  }

  /// legado `EncoderUtils.escape`：字母数字保留，其余按 UTF-16 code unit
  /// 转 `%0x` / `%xx` / `%uXXXX`（小写十六进制，与 legado 一致）。
  String _jsEscape(String value) {
    final sb = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      final code = value.codeUnitAt(i);
      final isAlnum = (code >= 0x30 && code <= 0x39) ||
          (code >= 0x41 && code <= 0x5a) ||
          (code >= 0x61 && code <= 0x7a);
      if (isAlnum) {
        sb.write(value[i]);
        continue;
      }
      final prefix = code < 16 ? '%0' : (code < 256 ? '%' : '%u');
      sb.write('$prefix${code.toRadixString(16)}');
    }
    return sb.toString();
  }

  /// 按声明字符集取字节（GBK 系用 GBK，其余 UTF-8；GBK 失败回退 UTF-8）。
  List<int> _charsetBytes(String value, String? charsetLower) {
    final lower = charsetLower?.toLowerCase();
    if (lower == 'gbk' || lower == 'gb2312' || lower == 'gb18030') {
      try {
        return gbk.encode(value);
      } catch (_) {}
    }
    return utf8.encode(value);
  }

  static const String _queryNoEncodeChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
      'abcdefghijklmnopqrstuvwxyz'
      '0123456789'
      r'!$&()*+,-./:;=?@[\]^_`{|}~';

  static const String _querySafeChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
      'abcdefghijklmnopqrstuvwxyz'
      '0123456789'
      r'_.-~!$%&()*+,/:;=?@[\]^`{|}';

  static const String _formNoEncodeChars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789*-._';

  String _getAbsoluteUrl(String urlStr) {
    // 对齐 legado NetworkUtils.getAbsoluteURL：先 trim（`{{js}}\n/path`
    // 类模板替换后残留换行，直接 resolve 会被编码成 `/%0A/path` → 400）、
    // `http` / `data:` 原样、`javascript` 开头返回空串，其余按 base 解析。
    // `//host` 协议相对地址由 Uri.resolve 保留页面协议。
    urlStr = urlStr.trim();
    final base = baseUrl;
    if (base == null || base.isEmpty) return urlStr;
    if (urlStr.startsWith('http')) return urlStr;
    if (urlStr.startsWith('data:')) return urlStr;
    if (urlStr.startsWith('javascript')) return '';
    // legado 解析 base 前按首个逗号截断（URL 选项后缀残留）。
    final baseNoOption = base.split(',').first;
    // legado 用 java.net.URL(base, relative)：只解析 path，query/fragment
    // 原样保留。Dart Uri.resolve 会把整串重新百分号编码（GBK 查询值会被
    // 改成 UTF-8 字节），故拆出 path 交给 Uri，query/fragment 原样回拼。
    final q = urlStr.indexOf('?');
    final h = urlStr.indexOf('#');
    var split = -1;
    if (q >= 0 && h >= 0) {
      split = q < h ? q : h;
    } else if (q >= 0) {
      split = q;
    } else if (h >= 0) {
      split = h;
    }
    final pathPart = split >= 0 ? urlStr.substring(0, split) : urlStr;
    final suffix = split >= 0 ? urlStr.substring(split) : '';
    if (pathPart.isEmpty && suffix.isEmpty) return baseNoOption;
    try {
      final baseUri = Uri.parse(baseNoOption);
      if (pathPart.isEmpty) {
        // `#frag`：保留 base 查询；`?query`：替换 base 查询。
        if (suffix.startsWith('#')) return '$baseNoOption$suffix';
        return '${baseNoOption.split('#').first}$suffix';
      }
      return '${baseUri.resolve(pathPart)}$suffix';
    } catch (_) {
      return urlStr;
    }
  }

  /// legado `NetworkUtils.getBaseUrl`：http(s) 取下标 9 起首个 `/` 之前的
  /// 部分（保留端口）；其余协议返回 null（保持原 baseUrl）。
  static String? _getBaseUrl(String u) {
    final lower = u.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return null;
    }
    final idx = u.indexOf('/', 9);
    return idx == -1 ? u : u.substring(0, idx);
  }

  String _evalJs(String jsCode, String currentResult) {
    try {
      final analyzeRule = _urlRule ??= AnalyzeRule(book: ruleData, chapter: chapter);
      // baseUrl 可能在绝对化后被刷新、或 reinitUrl 后变化，每次求值前同步。
      analyzeRule.setBaseUrl(baseUrl);
      // URL 内 JS 的宿主绑定（对齐 legado AnalyzeUrl.evalJS）：
      // 分页偏移（`page-1`）、关键词处理等表达式依赖 page/key。
      return analyzeRule.evalJs(jsCode, currentResult, extraBindings: {
        'page': page,
        'key': key ?? '',
        'speakText': speakText ?? '',
      });
    } catch (_) {
      return currentResult;
    }
  }

  bool get _isValidHttpUrl {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return false;
    }
    try {
      final uri = Uri.parse(url);
      return uri.host.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// 组装声明型请求头（源 header + URL 选项 headers + 登录头 + Cookie），
  /// **不发起网络请求**。供视频/音频直链解析：播放器拉 m3u8/分片必须带
  /// 同一套 Referer/UA/Cookie，否则 CDN 403 全程黑屏。
  Map<String, String> resolveRequestHeaders() {
    final out = <String, String>{};
    if (!_headerMapReplaced &&
        source?.header != null &&
        source!.header!.isNotEmpty) {
      try {
        _parseHeader(source!.header!)
            .forEach((k, v) => _putHeader(out, k, v));
      } catch (_) {}
    }
    headerMap.forEach((k, v) => _putHeader(out, k, v));
    final activeCtx = ShuyuanSourceContext.current;
    if (activeCtx != null) {
      if (!_headerMapReplaced) {
        activeCtx.loginHeader.forEach((k, v) {
          if (k.isNotEmpty && v.isNotEmpty) _putHeader(out, k, v);
        });
      }
      final reqHost = Uri.tryParse(url)?.host ?? '';
      final overlay = activeCtx.cookiesForHost(reqHost);
      if (overlay.isNotEmpty) {
        final overlayStr =
            overlay.entries.map((e) => '${e.key}=${e.value}').join('; ');
        _putHeader(out, 'Cookie',
            _mergeCookieStrings(_headerValue(out, 'Cookie'), overlayStr));
      }
    }
    final sharedCookie = HttpFetcher.instance.cookieHeaderForUrl(url);
    if (sharedCookie != null && sharedCookie.isNotEmpty) {
      _putHeader(out, 'Cookie',
          _mergeCookieStrings(_headerValue(out, 'Cookie'), sharedCookie));
    }
    // 待重放占位符的头部对播放器无意义，剔除而不是把占位符发给 CDN。
    out.removeWhere((_, v) => _hasReplayPlaceholder(v));
    return out;
  }

  Future<String> getStrResponse({
    String? jsStr,
    String? sourceRegex,
    Map<String, String>? headers,
  }) async {
    // legado `AnalyzeUrl.getStrResponseAwait`：声明 URL 选项 `type` 时响应体
    // 改为原始字节的 hex 字符串（音频等二进制内容），且不走 WebView、不做
    // jsStr/sourceRegex/bodyJs 文本后处理。
    final typeHex = requestType != null && requestType!.trim().isNotEmpty;

    // legado `getByteArrayIfDataUri`：`data:…;base64,<载荷>` 不发起 HTTP 请求，
    // 直接取 base64 解码字节（type 选项存在时返回字节 hex）。视频/音频源常把
    // 章节地址写成 data: 携带 aid&cid 等参数，正文脚本再 hexDecodeToString 还原。
    if (url.startsWith('data:')) {
      final dataBytes = _decodeDataUri(url);
      if (dataBytes != null) {
        lastStatusCode = 200;
        lastFinalUrl = url;
        lastResponseBytes = dataBytes;
        return typeHex
            ? _toHex(dataBytes)
            : utf8.decode(dataBytes, allowMalformed: true);
      }
    }

    if (!_isValidHttpUrl) {
      throw Exception('Invalid URL: $url');
    }
    // 元数据随请求走：缓存命中/失败分支不得复用上一条请求的状态。
    lastStatusCode = null;
    lastResponseHeaders = null;
    lastFinalUrl = null;

    // 阶段级页面缓存：settle 重放会整段重跑，命中则直接返回上一次的响应
    // （含 jsStr/sourceRegex 后处理结果，故 key 里带上这两项）。
    // 无活动上下文（离线调用/测试）时不缓存。
    // WebView 分支不拼请求头；HTTP 分支的 key 在请求头组装完成后再算
    // （源 header 的 @js 结果会影响响应，必须进 key，否则重放拿到错页）。
    final activeCtx = ShuyuanSourceContext.current;
    final webviewCacheKey =
        activeCtx == null ? null : _pageCacheKey(jsStr, sourceRegex);
    if (useWebView && !typeHex && activeCtx != null && webviewCacheKey != null) {
      final hit = activeCtx.pageCache[webviewCacheKey];
      if (hit != null) {
        AppLog.instance.d('[书源HTTP] 阶段缓存命中 $url');
        return hit;
      }
    }

    // legado URL 选项 `webView:true`：页面必须经 WebView 渲染——直连拿到的
    // 多半是 JS 壳。渲染成功直接用渲染 HTML；失败/命中挑战页 → 抛 WebView
    // 异常走可见浏览器回灌（与源级 useWebview 同一条用户路径）。
    // 无头取源失败且平台不支持时也走同一回灌，不会静默返回壳页。
    if (useWebView && !typeHex) {
      // legado BackstageWebView：`javaScript = webJs ?: jsStr` ——
      // URL 选项 webJs 优先，其次调用方传入的页内取值脚本（正文 webJs）。
      // 源 header 与 per-source Cookie 覆盖层透传给 WebView，页面写下的
      // Cookie 回写覆盖层（不写全局 jar）。
      final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
      final webHeaders = <String, String>{};
      if (!_headerMapReplaced) {
        try {
          webHeaders['User-Agent'] = HttpFetcher.instance.userAgentForUrl(url);
        } catch (_) {}
        final rawHeader = source?.header ?? '';
        if (rawHeader.isNotEmpty) {
          try {
            final sourceHeader = _parseHeader(rawHeader);
            // 与下方 HTTP 分支同款语义：源 header 的 User-Agent 必须生效，
            // 且要大小写不敏感地覆盖宿主 UA（源常写成 `user-agent`）。
            // 直接 addAll 会让两个大小写不同的键并存 → WebView 用哪个不确定，
            // registerHostUserAgent 注册到 HttpFetcher 的也仍是宿主 UA。
            String? sourceUa;
            for (final key in sourceHeader.keys.toList()) {
              if (key.toLowerCase() == 'user-agent') {
                sourceUa = sourceHeader.remove(key);
                break;
              }
            }
            if (sourceUa != null && sourceUa.isNotEmpty) {
              webHeaders['User-Agent'] = sourceUa;
            }
            sourceHeader.forEach((k, v) => _putHeader(webHeaders, k, v));
          } catch (_) {}
        }
      }
      // legado BackstageWebView 的 headerMap = 源 header（或 headerMapF）
      // + URL 选项 headers 的并集；显式 headers 参数与 HTTP 分支同序补上。
      headerMap.forEach((k, v) => _putHeader(webHeaders, k, v));
      if (headers != null) {
        headers.forEach((k, v) => _putHeader(webHeaders, k, v));
      }
      if (activeCtx != null) {
        if (host.isNotEmpty) {
          final overlay = activeCtx.cookiesForHost(host);
          if (overlay.isNotEmpty) {
            _putHeader(
                webHeaders,
                'Cookie',
                _mergeCookieStrings(_headerValue(webHeaders, 'Cookie'),
                    overlay.entries.map((e) => '${e.key}=${e.value}').join('; ')));
          }
        }
        if (!_headerMapReplaced && activeCtx.loginHeader.isNotEmpty) {
          activeCtx.loginHeader
              .forEach((k, v) => _putHeader(webHeaders, k, v));
        }
      }
      // 与下方 HTTP 分支同款护栏：源 header 的 @js 可能调用 java.ajax，首轮
      // 拿到的是 __AJAX_n__ 占位符（`__WEBVIEW_n__` 同理）。带着占位符进
      // WebView 既取不到真页，还会把占位符 UA 按 host 注册进 HttpFetcher
      // 污染后续请求——注册/抓取前提前抛出让外层 settle 重放。
      if (webHeaders.values.any(_hasReplayPlaceholder)) {
        throw Exception('请求头含待重放占位符，等待 settle 抓取：$url');
      }
      final ua = _headerValue(webHeaders, 'User-Agent');
      if (host.isNotEmpty && ua != null && ua.isNotEmpty) {
        HttpFetcher.instance.registerHostUserAgent(host, ua);
      }
      final result = await ShuyuanWebviewFetcher.fetch(
        url: url,
        js: webJs ?? jsStr,
        delayMs: webViewDelayTime,
        headers: webHeaders,
      ).timeout(const Duration(seconds: 60));
      final rendered = result?.html ?? '';
      if (rendered.isEmpty) {
        throw VerificationRequiredException(
          url: url,
          body: '',
          statusCode: null,
          preferWebView: true,
          webJs: webJs,
        );
      }
      if (activeCtx != null && result != null) {
        for (final e in result.cookieHeaders.entries) {
          activeCtx.syncCookies(e.key, e.value);
        }
      }
      // 采用渲染后的最终 URL（与 HTTP 分支 `lastFinalUrl = response.realUri`
      // 同语义）：settleAjax 元数据重放与「最终 URL」约定都依赖它。只接受
      // 绝对 http(s) + 非空 host；空值、about:、data: 一律忽略。不改 `url`
      // 字段——请求地址保持源声明值。
      final renderedFinalUrl = result?.finalUrl.trim() ?? '';
      if (renderedFinalUrl.isNotEmpty) {
        final finalUri = Uri.tryParse(renderedFinalUrl);
        if (finalUri != null &&
            (finalUri.scheme == 'http' || finalUri.scheme == 'https') &&
            finalUri.host.isNotEmpty) {
          lastFinalUrl = renderedFinalUrl;
        }
      }
      if (_looksLikeVerificationChallenge(rendered)) {
        throw VerificationRequiredException(
          url: url,
          body: rendered,
          statusCode: null,
          preferWebView: true,
          webJs: webJs,
        );
      }
      var out = rendered;
      if (sourceRegex != null && sourceRegex.isNotEmpty) {
        try {
          final regex = RegExp(sourceRegex, dotAll: true);
          final m = regex.firstMatch(out);
          if (m != null) out = m.groupCount > 0 ? (m.group(1) ?? out) : out;
        } catch (_) {}
      }
      if (activeCtx != null && webviewCacheKey != null) {
        activeCtx.pageCachePut(webviewCacheKey, out);
      }
      lastResponseBytes = Uint8List.fromList(utf8.encode(out));
      return out;
    }

    final requestHeaders = <String, String>{};
    if (!_headerMapReplaced) {
      // 全应用统一 UA（中心真源）：过验证的 UA 与后续 HttpFetcher 重试的
      // UA 必须一致，否则反爬把 Cookie 绑定到 UA+IP，UA 漂移 → Cookie 失效
      // → 验证死循环。最终 UA：默认中心化指纹 UA；若源 header 显式声明 UA
      // （如移动端 UA），则改用源的 UA——移动站点加固反爬后会拒绝桌面 UA。
      // 无论哪种 UA，都按 host 注册到 HttpFetcher，保证 WebView 验证与后续
      // 重试复用同一 UA → 会话 Cookie 绑定一致，避免验证死循环。
      //
      // 默认头不注入 Referer（legado AnalyzeUrl 同样只补 UA/Accept）；源要用
      // 参考来源须在 header 里显式声明。bookSourceUrl 允许携带 `##备注` 后缀
      // 且原样保存，把整串当默认 Referer 会因非 ASCII 头值让请求发送失败。
      requestHeaders['User-Agent'] =
          HttpFetcher.instance.userAgentForUrl(url);
      requestHeaders['Accept'] =
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8';
      requestHeaders['Accept-Language'] = 'zh-CN,zh;q=0.9,en;q=0.8';

      if (source?.header != null && source!.header!.isNotEmpty) {
        try {
          final sourceHeader = _parseHeader(source!.header!);
          // 源 header 的 User-Agent 必须生效（尊重「源即插件」：源作者配的
          // UA 即意图）。提取后按 host 注册到 HttpFetcher，使 WebView 验证
          // 复用同一 UA。
          String? sourceUa;
          for (final key in sourceHeader.keys.toList()) {
            if (key.toLowerCase() == 'user-agent') {
              sourceUa = sourceHeader.remove(key);
              break;
            }
          }
          if (sourceUa != null && sourceUa.isNotEmpty) {
            requestHeaders['User-Agent'] = sourceUa;
            final host = Uri.tryParse(url)?.host;
            if (host != null && host.isNotEmpty) {
              HttpFetcher.instance.registerHostUserAgent(host, sourceUa);
            }
          }
          sourceHeader.forEach((k, v) => _putHeader(requestHeaders, k, v));
        } catch (_) {}
      }
    }

    // URL 选项 headers（书源 searchUrl 的 `,{"headers":{...}}` 声明 + POST
    // Content-Type 补全）此前从未并入实际请求，源声明的请求头全部丢失；
    // 此处统一并入（选项头在源 header 之后、显式 headers 参数之前生效）。
    // 替换模式下它是唯一来源（headerMapF 已在构造时并入 headerMap）。
    if (headerMap.isNotEmpty) {
      headerMap.forEach((k, v) => _putHeader(requestHeaders, k, v));
    }

    if (headers != null) {
      headers.forEach((k, v) => _putHeader(requestHeaders, k, v));
    }

    // 注入对象上下文（P1-2）：登录头合并（source.putLoginHeader 语义）+
    // per-source cookie 覆盖层按 host 合并（书源命名空间隔离——三通道设计，
    // 只读合并进本次请求，不写全局罐）。activeCtx 已在函数入口取过。
    // 覆盖层先于共享罐合并：显式 Cookie > per-source 覆盖层 > 共享罐。
    // 替换模式跳过登录头（legado headerMapF 已完全替换登录头来源）。
    if (activeCtx != null) {
      if (!_headerMapReplaced) {
        activeCtx.loginHeader.forEach((k, v) {
          if (k.isNotEmpty && v.isNotEmpty) _putHeader(requestHeaders, k, v);
        });
      }
      _mergeCtxCookieOverlay(requestHeaders, url, activeCtx);
    }

    // 复用 HttpFetcher 共享 Cookie 存储：验证系统在 WebView（内置浏览器）里被
    // 通过后，会话 Cookie 已由 HttpBrowserScreen 同步进 HttpFetcher；AnalyzeUrl
    // 用独立 Dio，不读那个 jar，若不回带，验证重试仍会被反爬系统拦截（之前
    // 幻梦ACG「系统安全验证」即因此反复返空列表 / 「该分类暂无内容」）。
    // 首次请求时 jar 为空 → 此步为空操作，无副作用。
    final sharedCookie = HttpFetcher.instance.cookieHeaderForUrl(url);
    if (sharedCookie != null && sharedCookie.isNotEmpty) {
      _putHeader(
          requestHeaders,
          'Cookie',
          _mergeCookieStrings(
              _headerValue(requestHeaders, 'Cookie'), sharedCookie));
    }

    // 源 header 的 @js 可能调用 java.ajax：首轮拿到的是 __AJAX_n__ 占位符，
    // 真实请求必须等 settle 抓取回填后重放。带着占位符发请求只会得到
    // 401/空页，整条链路归零——此处提前抛出让外层 settle 循环重放。
    if (requestHeaders.values.any(_hasReplayPlaceholder)) {
      throw Exception('请求头含待重放占位符，等待 settle 抓取：$url');
    }

    // HTTP 分支阶段缓存：请求头（含源 header 的 @js 求值结果）参与 key，
    // 避免 settle 重放时把旧头取到的响应错配给新头请求。
    final cacheKey = activeCtx == null
        ? null
        : _pageCacheKey(jsStr, sourceRegex, requestHeaders);
    if (activeCtx != null && cacheKey != null) {
      final hit = activeCtx.pageCache[cacheKey];
      if (hit != null) {
        AppLog.instance.d('[书源HTTP] 阶段缓存命中 $url');
        return hit;
      }
    }

    String body;
    try {
      // 同 host 节流 + 验证冷却（复用 HttpFetcher 闸门）：书源链路用独立 Dio，
      // 若不过闸门，目录分页/详情/推荐背靠背连发会触发 Cloudflare 临时挑战
      // （笔趣阁反代即因此循环弹验证）。长目录变慢由渐进批次保障首屏体验。
      await HttpFetcher.instance.runGate(url);
      AppLog.instance.d('[书源HTTP] ${method?.toUpperCase() ?? 'GET'} $url');

      // 代理：源声明的 proxy 字段此前解析但未使用；此处落地——非空时改用带
      // IOHttpClientAdapter(findProxy) 的临时 Dio 发起本次请求，不影响全局默认 Dio。
      final Dio dio = proxy != null && proxy!.isNotEmpty
          ? (Dio()
            ..httpClientAdapter = IOHttpClientAdapter(
              createHttpClient: () {
                final client = HttpClient();
                client.findProxy = (_) => 'PROXY $proxy';
                return client;
              },
            ))
          : _dio;

      Options buildOptions() => Options(
            headers: requestHeaders,
            responseType: ResponseType.bytes,
            followRedirects: followRedirects ?? true,
            // 不跟随重定向时 3xx 是正常结果（Location 头即脚本要的答案），
            // 不能按错误抛出。
            validateStatus: (status) => status != null &&
                (status >= 200 && status < 300 ||
                    (followRedirects == false && status >= 300 && status < 400)),
          );

      // concurrentRate 限速（legado ConcurrentRateLimiter 等效，书源侧
      // 包装——按源计数，媒体源链路零影响）。运行期 putConcurrent 覆盖优先。
      final rateKey = source?.bookSourceUrl ?? url;
      await ConcurrentRateLimiter.gate(
          ConcurrentRateLimiter.effectiveRate(source?.concurrentRate, rateKey),
          rateKey);

      Response<List<int>>? response;
      var attempt = 0;
      var cookiePrimed = false;
      while (true) {
        try {
          final m = method?.toUpperCase();
          if (m == 'POST') {
            response = await dio.post<List<int>>(
              url,
              data: this.body,
              options: buildOptions(),
            );
          } else if (m == 'HEAD') {
            response = await dio.head<List<int>>(
              url,
              options: buildOptions(),
            );
          } else {
            response = await dio.get<List<int>>(
              url,
              options: buildOptions(),
            );
          }
          break;
        } on DioException catch (e) {
          // HTTP 412 风控（缺站点会话 Cookie）：先访问站点根域取首页下发的
          // 种子 Cookie（浏览器同款会话建立方式），并把新 Cookie 并入请求头，
          // 再原请求重试一次。站点根按上下文去重；取不到 Cookie 不重试。
          if (e.response?.statusCode == 412 &&
              !cookiePrimed &&
              (source?.enabledCookieJar ?? false) &&
              await _primeSessionCookies(dio, url, requestHeaders, activeCtx)) {
            cookiePrimed = true;
            continue;
          }
          // retry：书源 URL 选项声明的重试次数（网络异常/连接失败重试；
          // 验证挑战异常不在此层——由下方挑战检测分支处理）。
          attempt += 1;
          if (attempt > retry) rethrow;
        }
      }

      final bytes = Uint8List.fromList(response.data ?? <int>[]);
      lastResponseBytes = bytes;
      lastStatusCode = response.statusCode;
      lastResponseHeaders = response.headers.map;
      lastFinalUrl = response.realUri.toString();
      _storeResponseCookies(activeCtx, url, response.headers.map);
      final contentType = _extractHeaderValue(
        response.headers['content-type'],
      );
      final effectiveCs = _normalizeCharset(charset) ??
          _extractCharsetFromContentType(contentType) ??
          _extractCharsetFromMeta(bytes);
      body = typeHex
          ? _toHex(bytes)
          : _decodeBody(bytes, charset, contentType);
      AppLog.instance.d(
          '[书源HTTP] ← ${response.statusCode} ${body.length}字符 '
          'charset=${typeHex ? 'hex' : (effectiveCs ?? 'utf8-容错')}');

      // 解码后统一检测「验证/反爬挑战页」（覆盖 Cloudflare、以及 PTCMS 等站点
      // 自带的「系统安全验证」等）。命中则抛 [VerificationRequiredException]，
      // 交由既有 WebView 验证回灌流程过验证，而非静默返回空结果或抛普通异常被上层吞掉。
      // webJs 选项（legado 语义）：页面内容需在 WebView 内执行取值脚本
      // 才能得到正文——抛 WebView 渲染回灌请求（脚本经异常携带）。
      // type=hex 的二进制响应不做文本挑战检测。
      if (!typeHex && webJs != null && webJs!.trim().isNotEmpty) {
        throw VerificationRequiredException(
          url: url,
          body: body,
          statusCode: response.statusCode,
          preferWebView: true,
          webJs: webJs,
        );
      }

      if (!typeHex && _looksLikeVerificationChallenge(body)) {
        throw VerificationRequiredException(
          url: url,
          body: body,
          statusCode: response.statusCode,
          preferWebView: useWebView,
          webJs: webJs,
        );
      }

      if (response.statusCode != null && response.statusCode! >= 400) {
        throw Exception('请求失败：HTTP ${response.statusCode}，URL：$url');
      }

      // legado AnalyzeUrl：XML 响应且正文未带声明时补 `<?xml version="1.0"?>`；
      // 原实现该分支先于 bodyJs 命中（补声明时不执行 bodyJs）。
      final isXmlResponse = contentType != null &&
          RegExp(r'(application|text)/\w*\+?xml.*').hasMatch(contentType);
      if (!typeHex &&
          isXmlResponse &&
          !body.trim().toLowerCase().startsWith('<?xml')) {
        body = '<?xml version="1.0"?>$body';
      } else if (!typeHex && bodyJs != null && bodyJs!.trim().isNotEmpty) {
        // legado bodyJs：响应体作为 `result` 再过一遍 JS（JSON 解包等）。
        body = _evalJs(bodyJs!, body);
      }

      if (response.redirects.isNotEmpty) {
        url = response.redirects.last.location.toString();
      }
    } on DioException catch (e) {
      AppLog.instance.w('[书源HTTP] Dio异常 ${e.response?.statusCode} $url');
      final status = e.response?.statusCode;
      // 错误响应（403 挑战页 / 重定向等）同样可能携带 Set-Cookie
      //（如防爬系统在挑战页下发校验 cookie），先落库再判定异常类型，
      // 让后续验证重试/下一请求能回放（legado 拦截器对状态码无差别保存）。
      _storeResponseCookies(activeCtx, url, e.response?.headers.map);
      // 非 2xx 也可能是「验证 / 反爬挑战页」：PTCMS「系统安全验证」常以 403
      // 返回挑战 HTML，此时 validateStatus 已拒收、请求体被丢给上层前必须先过
      // 一遍挑战检测；否则异常类型不对（普通 Exception 而非
      // VerificationRequiredException），验证链路不会触发 → 列表空 + 不跳 WebView。
      final errData = e.response?.data;
      if (errData is List<int> && errData.isNotEmpty) {
        final decoded = _decodeBody(
          Uint8List.fromList(errData),
          charset,
          _extractHeaderValue(e.response?.headers['content-type']),
        );
        if (_looksLikeVerificationChallenge(decoded)) {
          throw VerificationRequiredException(
            url: url,
            body: decoded,
            statusCode: status,
          );
        }
      }
      // 状态码 401/403 一律按验证处理（与 VerificationDetector 语义对齐）：
      // CF 临时挑战可能返回短壳/空体 403，不命中挑战特征也必须进验证流程，
      // 否则从历史/浏览任一入口撞 403 都成死错误（无验证入口、一直加载）。
      if (status == 401 || status == 403) {
        throw VerificationRequiredException(
          url: url,
          body: '',
          statusCode: status,
        );
      }
      throw Exception('网络请求失败[$status]：$url，${e.message}');
    } catch (e) {
      // 关键：验证异常必须原样透传，绝不能包成普通 Exception。否则上层
      // VerificationNavigator.isVerificationError 判定失败 → 不跳 WebView，
      // 列表解析空壳 → 没封面、也不触发验证（幻梦ACG _guard 滑块挑战即此坑）。
      if (e is VerificationRequiredException) rethrow;
      // 登录失效同理：类型透传供上层识别并引导用户完成书源登录。
      if (e is ShuyuanLoginRequiredException) rethrow;
      throw Exception('网络请求失败：$url，${e.toString()}');
    }

    // legado：jsStr 仅在 WebView 路径作为页内脚本消费（Java 直连分支不处理），
    // 此处保持一致；sourceRegex 在直连分支继续应用（NexHub 既有扩展语义）。
    if (!typeHex && sourceRegex != null && sourceRegex.isNotEmpty) {
      try {
        final regex = RegExp(sourceRegex, dotAll: true);
        final match = regex.firstMatch(body);
        if (match != null) {
          if (match.groupCount > 0) {
            body = match.group(1) ?? body;
          } else {
            body = match.group(0) ?? body;
          }
        }
      } catch (_) {}
    }

    if (activeCtx != null && cacheKey != null) {
      _lastCacheKey = cacheKey;
      activeCtx.pageCachePut(cacheKey, body);
    }
    return body;
  }

  /// 入口级 loginCheck（legado WebBook 五个 await 入口的 `check` 语义）：
  /// 书源声明 loginCheckJs 时，对**首响应**求值一次并返回可能被改写的响应体。
  /// 仅在 WebBook 入口调用——分页、目录翻页、loginCheck 内部重取都不再触发，
  /// 且脚本看到的 `url()`/`headers()` 是本次响应的最终地址与真实响应头。
  Future<String> applyLoginCheck(String body) async {
    final checkJs = source?.loginCheckJs;
    if (checkJs == null || checkJs.trim().isEmpty) return body;
    // 首取刚写入的阶段缓存先撤掉：检查脚本里的 getStrResponse() 必须走
    // 真实重取（legado 无阶段缓存），否则只会拿回同一个响应。
    final staged = _lastCacheKey;
    if (staged != null) {
      _lastCacheKey = null;
      ShuyuanSourceContext.current?.pageCacheRemove(staged);
    }
    final outcome = await _runLoginCheck(
      checkJs,
      lastStatusCode ?? 200,
      body,
      responseUrl: lastFinalUrl ?? url,
      responseHeaders: lastResponseHeaders,
    );
    if (outcome.code == 500) {
      throw ShuyuanLoginRequiredException(
          url: url, sourceName: source?.bookSourceName ?? '');
    }
    return outcome.body ?? body;
  }

  /// 阶段缓存键：同 URL 但 method/body/请求头/后处理不同时不能复用。
  String _pageCacheKey(String? jsStr, String? sourceRegex,
      [Map<String, String>? headers]) {
    final m = method?.toUpperCase() ?? 'GET';
    final h = headers == null || headers.isEmpty
        ? ''
        : ((headers.entries.toList()
                  ..sort((a, b) => a.key.toLowerCase().compareTo(
                      b.key.toLowerCase())))
                .map((e) => '${e.key.toLowerCase()}:${e.value}')
                .join('\n'));
    return '$m\n$url\n${body ?? ''}\n${jsStr ?? ''}\n${sourceRegex ?? ''}\n'
        '${followRedirects == false ? 'noredir' : ''}\n$h';
  }

  /// 响应 Set-Cookie 落库（legado `CookieManager.saveResponse` 对等）。
  ///
  /// 无活动上下文（离线调用/非书源链路）时不写：cookie 只进 per-source
  /// 覆盖层，绝不写全局 HttpFetcher 罐（三通道隔离红线）。
  static void _storeResponseCookies(ShuyuanSourceContext? ctx, String url,
      Map<String, List<String>>? headers) {
    if (ctx == null) return;
    final setCookies = _setCookieHeaders(headers);
    if (setCookies == null || setCookies.isEmpty) return;
    ctx.applyResponseCookies(url, setCookies);
    // 持久化沿用排空同一入口（fire-and-forget，下一请求读内存镜像）。
    ctx.persistIfNeeded();
  }

  /// 取响应头里的全部 Set-Cookie 值（Dio 可能合并为单值逗号串，也可能是
  /// 多值列表；键大小写不敏感）。
  static List<String>? _setCookieHeaders(Map<String, List<String>>? headers) {
    if (headers == null) return null;
    for (final e in headers.entries) {
      if (e.key.toLowerCase() != 'set-cookie') continue;
      if (e.value.isEmpty) return null;
      // Dio 默认把多个 Set-Cookie 收进列表；个别适配器合并成单个逗号串时
      // 不能按逗号拆分（Expires 也含逗号），整串交给解析器按分号处理即可。
      return e.value;
    }
    return null;
  }

  /// 合并两段 Cookie 字符串；**首参（显式 Cookie）优先**。
  ///
  /// 对齐 legado `AnalyzeUrl.setCookie()`：`mergeCookies(jarCookie,
  /// headerMap["Cookie"])`——同名 Cookie 由后者（URL 选项/源 header 的
  /// 显式值）覆盖罐里的值，即「urlOption 临时 cookie > 数据库 cookie」。
  /// 签名类源把与 Cookie 绑定的签名头（如 Secret）和当时的 Cookie 值一起
  /// 放进 URL 选项：若让罐里轮换后的新值覆盖显式旧值，服务端会因
  /// 「签名与 Cookie 不一致」直接拒绝（200 + 业务错误码），整条链路失败。
  static String _mergeCookieStrings(String? existing, String incoming) {
    if (existing == null || existing.trim().isEmpty) return incoming;
    final merged = <String, String>{};
    final parts = <String>[
      ...incoming.split(';'),
      ...existing.split(';'),
    ];
    for (final part in parts) {
      final pair = part.trim();
      if (pair.isEmpty) continue;
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      merged[pair.substring(0, eq).trim()] = pair.substring(eq + 1).trim();
    }
    if (merged.isEmpty) return incoming;
    return merged.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// per-source cookie 覆盖层按 host 并入请求头（请求组装与 412 种子 Cookie
  /// 重试共用；只读合并，不写全局罐）。
  static void _mergeCtxCookieOverlay(
    Map<String, String> requestHeaders,
    String url,
    ShuyuanSourceContext? ctx,
  ) {
    if (ctx == null) return;
    final overlay = ctx.cookiesForHost(Uri.tryParse(url)?.host ?? '');
    if (overlay.isEmpty) return;
    final overlayStr =
        overlay.entries.map((e) => '${e.key}=${e.value}').join('; ');
    _putHeader(
        requestHeaders,
        'Cookie',
        _mergeCookieStrings(_headerValue(requestHeaders, 'Cookie'), overlayStr));
  }

  /// HTTP 412 风控的通用会话建立：访问站点根域（IP/localhost 用同源根），
  /// 把首页 Set-Cookie 落进 per-source cookie 覆盖层，并并入重试请求头。
  ///
  /// 返回 true 表示拿到了对该请求 host 生效的新 Cookie，调用方可重试一次。
  /// 同一上下文同一根域只尝试一次；根域请求失败或未下发 Cookie 返回 false，
  /// 避免「412 → 首页 → 仍 412」的循环放大请求。
  static Future<bool> _primeSessionCookies(
    Dio dio,
    String failingUrl,
    Map<String, String> requestHeaders,
    ShuyuanSourceContext? ctx,
  ) async {
    if (ctx == null) return false;
    final rootUrl = _siteRootUrlOf(failingUrl);
    if (rootUrl == null) return false;
    if (!ctx.cookiePrimedRoots.add(rootUrl)) return false;
    final host = Uri.tryParse(failingUrl)?.host.toLowerCase() ?? '';
    final before = ctx.cookiesForHost(host);
    try {
      final resp = await dio.get<List<int>>(
        rootUrl,
        options: Options(
          headers: <String, String>{
            'User-Agent': _headerValue(requestHeaders, 'User-Agent') ??
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                    'AppleWebKit/537.36 (KHTML, like Gecko) '
                    'Chrome/120.0.0.0 Safari/537.36',
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
          },
          responseType: ResponseType.bytes,
          followRedirects: true,
          validateStatus: (_) => true,
        ),
      );
      _storeResponseCookies(ctx, rootUrl, resp.headers.map);
    } catch (_) {
      return false;
    }
    final after = ctx.cookiesForHost(host);
    if (after.isEmpty) return false;
    final changed = after.length != before.length ||
        after.entries.any((e) => before[e.key] != e.value);
    if (!changed) return false;
    _mergeCtxCookieOverlay(requestHeaders, failingUrl, ctx);
    return true;
  }

  /// 请求 URL 的站点根：域名取可注册域（含常见二级后缀），IP/localhost
  /// 取同源。用于 412 种子 Cookie 预处理。
  static String? _siteRootUrlOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    final scheme = uri.scheme.isEmpty ? 'https' : uri.scheme;
    final host = uri.host.toLowerCase();
    final isIp = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host) ||
        host.contains(':') ||
        host == 'localhost';
    if (isIp) {
      final port = uri.hasPort ? ':${uri.port}' : '';
      return '$scheme://$host$port/';
    }
    final labels = host.split('.');
    if (labels.length <= 2) return '$scheme://$host/';
    const twoLabelSuffixes = <String>{
      'com.cn', 'net.cn', 'org.cn', 'gov.cn', 'edu.cn', 'ac.cn',
      'com.hk', 'com.tw', 'co.uk', 'org.uk', 'co.jp', 'co.kr',
      'com.au', 'com.sg', 'com.br', 'com.mx',
    };
    final tail2 = labels.sublist(labels.length - 2).join('.');
    final take = twoLabelSuffixes.contains(tail2) ? 3 : 2;
    return '$scheme://${labels.sublist(labels.length - take).join('.')}/';
  }

  /// 大小写不敏感的请求头写入：同名旧键先移除，避免 `User-Agent` 与
  /// `user-agent` 并存（Dio 合并顺序不确定 → 源声明的 UA 可能失效）。
  static void _putHeader(Map<String, String> target, String key, String value) {
    final lower = key.toLowerCase();
    target.removeWhere((k, _) => k.toLowerCase() == lower);
    target[key] = value;
  }

  /// 大小写不敏感的请求头读取。
  static String? _headerValue(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == lower) return e.value;
    }
    return null;
  }

  static bool _hasReplayPlaceholder(String v) =>
      v.contains('__AJAX_') || v.contains('__WEBVIEW_');

  /// `data:…;base64,<载荷>` 载荷解码（legado `getByteArrayIfDataUri` 等效）：
  /// 对齐 Android `Base64.DEFAULT` 的容错——忽略空白、补齐缺失的 `=` 填充；
  /// 非 base64 形式或载荷非法时返回 null。
  static Uint8List? _decodeDataUri(String dataUrl) {
    const marker = ';base64,';
    final idx = dataUrl.indexOf(marker);
    if (idx < 0) return null;
    var payload = dataUrl.substring(idx + marker.length);
    payload = payload.replaceAll(RegExp(r'\s'), '');
    final rem = payload.length % 4;
    if (rem == 1) return null;
    if (rem != 0) payload = payload.padRight(payload.length + (4 - rem), '=');
    try {
      return base64.decode(payload);
    } catch (_) {
      return null;
    }
  }

  /// 原始字节转小写 hex（对齐 legado `ByteArray.toHexString`）。
  static String _toHex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  /// JSON 宽松解析（对齐 legado Gson lenient）：社区源把 URL 选项/header
  /// 写成单引号、裸键、尾逗号或带注释的形式，严格 json.decode 会整段
  /// 失败 → method/body/headers 全部丢失。先严格解析，失败再修复重试。
  static Map<String, dynamic>? parseJsonLenient(String raw) {
    final v = decodeJsonLenient(raw);
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  /// 宽松 JSON 解码（legado 侧等价 GSON 宽松模式：单引号、裸键、裸字符串
  /// 值、尾逗号、`//` 与 `/* */` 注释）。严格解码失败后按修复文本重试。
  static Object? decodeJsonLenient(String raw) {
    try {
      return json.decode(raw);
    } catch (_) {}
    try {
      return json.decode(_repairJson(raw));
    } catch (_) {
      return null;
    }
  }

  /// 宽松 JSON 文本修复（单引号→双引号、裸键/裸字符串值补引号、尾逗号与
  /// 注释剔除）；供其它内嵌 JSON（如发现页 kinds）在严格解码失败后复用。
  static String repairJsonLenient(String raw) => _repairJson(raw);

  /// 宽松 JSON 修复：单引号→双引号、裸键/裸字符串值补引号、尾逗号与
  /// `//`/`/* */` 注释剔除；字符串内部内容保持不变。
  static String _repairJson(String s) {
    final out = StringBuffer();
    final stack = <String>[];
    var i = 0;
    var inStr = false;
    var quote = '';
    var prev = '';
    while (i < s.length) {
      final c = s[i];
      if (inStr) {
        if (c == '\\' && i + 1 < s.length) {
          final next = s[i + 1];
          // GSON 宽松模式对单/双引号字符串都接受 `\'` 转义（社区源把嵌套
          // JSON 写成 `{\'headers\':\'{\"UA\":\"...\"}\'}`）。JSON 里单引号
          // 无需转义，必须丢掉反斜杠，否则严格 jsonDecode 报
          // "Unrecognized string escape" 导致整页发现页不可用。
          if (next == "'") {
            out.write("'");
          } else {
            out.write(c);
            out.write(next);
          }
          i += 2;
          continue;
        }
        if (c == quote) {
          inStr = false;
          out.write('"');
          i++;
          continue;
        }
        if (c == '"' && quote == "'") {
          out.write(r'\"');
        } else {
          out.write(c);
        }
        i++;
        continue;
      }
      if (c == '"' || c == "'") {
        inStr = true;
        quote = c;
        out.write('"');
        i++;
        continue;
      }
      if (c == '/' && i + 1 < s.length) {
        if (s[i + 1] == '/') {
          final nl = s.indexOf('\n', i);
          i = nl < 0 ? s.length : nl;
          continue;
        }
        if (s[i + 1] == '*') {
          final end = s.indexOf('*/', i + 2);
          i = end < 0 ? s.length : end + 2;
          continue;
        }
      }
      if (c == '{' || c == '[') {
        stack.add(c);
        out.write(c);
        prev = c;
        i++;
        continue;
      }
      if (c == '}' || c == ']') {
        if (stack.isNotEmpty) stack.removeLast();
        out.write(c);
        prev = c;
        i++;
        continue;
      }
      if (c == ',') {
        var j = i + 1;
        while (j < s.length && ' \t\r\n'.contains(s[j])) {
          j++;
        }
        if (j < s.length && (s[j] == '}' || s[j] == ']')) {
          i++;
          continue;
        }
        out.write(c);
        prev = c;
        i++;
        continue;
      }
      if (c == ':') {
        out.write(c);
        prev = ':';
        i++;
        continue;
      }
      if (' \t\r\n'.contains(c)) {
        out.write(c);
        i++;
        continue;
      }
      final topIsObj = stack.isNotEmpty && stack.last == '{';
      if (topIsObj && (prev == '{' || prev == ',')) {
        var j = i;
        while (j < s.length && RegExp(r'[A-Za-z0-9_$-]').hasMatch(s[j])) {
          j++;
        }
        var k = j;
        while (k < s.length && ' \t\r\n'.contains(s[k])) {
          k++;
        }
        if (j > i && k < s.length && s[k] == ':') {
          out.write('"${s.substring(i, j)}"');
          i = j;
          continue;
        }
      }
      if (prev == ':') {
        var j = i;
        while (j < s.length && !',}] \t\r\n'.contains(s[j])) {
          j++;
        }
        var token = s.substring(i, j);
        // 残缺 JSON 常见「值缺开引号但保留闭引号」（如 `"title": 文本"`）：
        // 去掉悬空尾引号再整体补引号，否则会补出 `"文本""`。
        if (token.endsWith('"')) {
          token = token.substring(0, token.length - 1);
        }
        if (token == 'true' || token == 'false' || token == 'null' ||
            num.tryParse(token) != null) {
          out.write(token);
        } else {
          out.write('"$token"');
        }
        i = j;
        prev = 'v';
        continue;
      }
      out.write(c);
      prev = c;
      i++;
    }
    return out.toString();
  }

  Map<String, String> _parseHeader(String headerStr) {
    var text = headerStr.trim();
    // 源 header 本身是规则表达式（legado BaseSource.getHeaderMap 语义）：
    // `@js:` / `<js>...</js>` 整串求值出 JSON。优++ 源普遍用它设移动端 UA
    // 与 Referer；直接把 `@js:` 字面量按行解析会得到 `@js` 伪头 + 带引号的
    // 假键值，真实 UA 丢失 → 站点按桌面模板返回（幻梦轻说列表为 0 条）。
    final lower = text.toLowerCase();
    if (lower.startsWith('@js:')) {
      text = _evalSourceHeaderJs(text.substring(4));
    } else if (lower.startsWith('<js>') && lower.contains('</js>')) {
      text = _evalSourceHeaderJs(text.substring(4, lower.lastIndexOf('</js>')));
    }

    final headers = <String, String>{};
    final decoded = parseJsonLenient(text);
    if (decoded != null) {
      for (final entry in decoded.entries) {
        headers[entry.key.toString()] = entry.value.toString();
      }
      return headers;
    }

    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final colonIndex = trimmed.indexOf(': ');
      if (colonIndex > 0) {
        final key = trimmed.substring(0, colonIndex).trim();
        final value = trimmed.substring(colonIndex + 1).trim();
        headers[key] = value;
      }
    }
    return headers;
  }

  /// 源 header 的脚本求值：绑定 `baseUrl`（源根地址，legado `getKey()` 等效），
  /// 脚本完成值作为 JSON 文本返回。求值失败返回空串（调用方退回默认头）。
  String _evalSourceHeaderJs(String code) {
    final ctx = ShuyuanSourceContext.current;
    final engine = JsEngine.forSource(ctx?.sourceId);
    try {
      final base = (source?.bookSourceUrl.isNotEmpty ?? false)
          ? source!.bookSourceUrl
          : (baseUrl ?? '');
      return engine.eval(code, bindings: {'baseUrl': base}).trim();
    } catch (_) {
      return '';
    } finally {
      if (ctx == null) engine.dispose();
    }
  }

  /// 字符集解码优先级：
  /// 1. URL 选项中的 charset
  /// 2. HTTP Content-Type 中的 charset
  /// 3. HTML `<meta charset="...">` / `<meta http-equiv="Content-Type" ... charset=...>`
  /// 声明（许多 GBK 系站点只写 meta，Content-Type 不带 charset，缺此探测会
  /// 全部按 UTF-8 容错解码 → 中文乱码）
  /// 4. UTF-8 容错解码
  String _decodeBody(Uint8List bytes, String? optionCharset, String? contentType) {
    final effectiveCharset = _normalizeCharset(optionCharset) ??
        _extractCharsetFromContentType(contentType) ??
        _extractCharsetFromMeta(bytes);

    if (effectiveCharset != null) {
      final lower = effectiveCharset.toLowerCase();
      if (lower == 'gbk' || lower == 'gb2312' || lower == 'gb18030') {
        return gbk.decode(bytes);
      }
      if (lower == 'big5') {
        // Dart 内置不支持 Big5，先按 UTF-8 容错解码，避免直接崩溃
        return utf8.decode(bytes, allowMalformed: true);
      }
    }

    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 从 HTML 头部探测 `<meta charset>` / `http-equiv="Content-Type"` 声明的字符集。
  ///
  /// 只扫描前 4KB（charset 声明总在 <head> 开头），按 ASCII 子集读取原始字节
  /// 避免在未解码前引入额外依赖；扫描区即使含非 ASCII 字节也只会被当作
  /// 乱码字符，不影响 charset 关键字匹配。
  static String? _extractCharsetFromMeta(Uint8List bytes) {
    final limit = bytes.length < 4096 ? bytes.length : 4096;
    // 仅取 ASCII 可读字符拼接，中文/双字节原文会被丢弃（charset 关键字是 ASCII）。
    final buf = StringBuffer();
    for (var i = 0; i < limit; i++) {
      final c = bytes[i];
      if (c >= 0x20 && c < 0x7f) {
        buf.writeCharCode(c);
      }
    }
    final head = buf.toString();
    if (!head.contains('charset', 0)) return null;
    // 双引号字符串转义（raw 字符串里 \' 会提前终止字面量）。
    final m = RegExp(
      "charset\\s*=\\s*[\"']?\\s*([a-zA-Z0-9_-]+)",
      caseSensitive: false,
    ).firstMatch(head);
    return m?.group(1)?.trim().toLowerCase();
  }

  String? _normalizeCharset(String? charset) {
    if (charset == null || charset.trim().isEmpty) {
      return null;
    }
    return charset.trim().toLowerCase();
  }

  /// 从 Content-Type 提取 charset，如 `text/html; charset=gbk` -> `gbk`。
  String? _extractCharsetFromContentType(String? contentType) {
    if (contentType == null || contentType.isEmpty) {
      return null;
    }
    final match = RegExp(r'charset\s*=\s*([^\s;]+)', caseSensitive: false)
        .firstMatch(contentType);
    return match?.group(1)?.trim().toLowerCase();
  }

  String? _extractHeaderValue(List<String>? values) {
    if (values == null || values.isEmpty) {
      return null;
    }
    return values.first;
  }

  /// 识别「验证 / 反爬挑战页」（仅挑战页有、正常内容页绝不会出现的特征）。
  ///
  /// 覆盖两类场景：
  /// 1) Cloudflare 挑战页：用精确主动特征（零误杀），正常小说页不可能包含；
  /// 2) 非 Cloudflare 的站点自带验证系统（如 PTCMS 的「系统安全验证」）：
  /// 用「标题/短体验证信号」综合判定，并对弱信号加长度闸门，避免把正常
  /// 大内容页（含 footer「账号安全验证」链接等）误判为验证页。
  ///
  /// 命中即抛 [VerificationRequiredException]，交由既有 WebView 验证回灌流程过验证，
  /// 而非静默返回空结果或抛普通异常被上层吞掉。
  static bool _looksLikeVerificationChallenge(String body) {
    if (body.isEmpty) return false;
    final lower = body.toLowerCase();

    // 1) 精确 Cloudflare 主动特征（零误杀，正常内容页绝不含）。
    const cfMarkers = <String>[
      'just a moment',
      'enable javascript and cookies to continue',
      'cf-mitigated',
      '__cf_chl',
      'attention required! | cloudflare',
    ];
    if (cfMarkers.any(lower.contains)) return true;

    // 2) 通用验证/反爬挑战页识别。
    final title = _extractTitle(lower);
    final titleHasVerify = title.contains('验证') ||
        title.contains('verify') ||
        title.contains('安全验证');

    // 强特征：基本只出现在验证/反爬挑战页（如 PTCMS「系统安全验证」、geetest 滑块）。
    // 这类特征在正常小说列表页极不可能出现，命中即判，不依赖长度闸门。
    const strongBody = <String>[
      '系统安全验证',
      '请完成安全验证',
      '请滑动完成验证',
      '请拖动滑块',
      '人机验证',
      '滑动验证',
      '滑块验证',
      'verify you are human',
      'confirm you are human',
      'secapi',
      'geetest',
      // PTCMS 系「_guard」滑块反爬：真实返回体只有一行
      // `<script src="/_guard/html.js?js=slider_html"></script>`（HTTP 200，
      // 无标题、无「验证」字样）。裸正文不含任何上述特征，故需单独识别其脚本路径。
      // 用 `_guard/` 而非裸 `_guard`，避免误匹配正常页内 `_guardMode` 之类变量。
      '_guard/',
      'slider_html',
    ];
    if (strongBody.any(lower.contains)) return true;

    // 弱特征：可能出现在正常页 footer（如「账号安全验证」链接），仅在页面较小
    // 且标题也带验证词时才判，避免误伤正常大内容页。
    const weakBody = <String>[
      '安全验证',
      '安全校验',
      '验证系统',
      '请验证',
      '滑块',
    ];
    final weakHits = weakBody.where(lower.contains).length;
    final isSmall = body.length <= 65536; // 64KB 长度闸门
    if (isSmall && titleHasVerify && weakHits >= 1) return true;

    return false;
  }

  /// 从 HTML 中提取 <title> 文本（小写），用于验证页标题特征判定。
  static String _extractTitle(String lowerBody) {
    final start = lowerBody.indexOf('<title');
    if (start < 0) return '';
    final gt = lowerBody.indexOf('>', start);
    if (gt < 0) return '';
    final end = lowerBody.indexOf('</title>', gt);
    if (end < 0) return '';
    return lowerBody.substring(gt + 1, end).trim();
  }

  /// loginCheckJs 求值：`result` 按 legado 的 StrResponse 鸭子类型构造。
  /// 源脚本普遍写 `result.body()` / `result.url()` / `result.code()`（方法
  /// 调用），旧包装把 `body` 设成字符串属性导致 `result.body()` 抛
  /// TypeError 整条脚本中断。这里：
  /// - `body()` 返回正文；`body` 本身也可当字符串用（绑定了
  ///   `match/includes/trim` 等 String.prototype 方法与 toString）；
  /// - `url()/code()/message()/headers()` 齐备；
  /// - 赋值 `result.code = 500`（覆盖函数属性）或直接 `return 500` /
  ///   `return '500'` / `result = '500'` 仍可声明登录失效。
  ///
  /// 对齐 legado 把 `java` 绑定为 AnalyzeUrl 的求值环境：脚本可经
  /// `java.getStrResponse()` 重取当前地址（`java.initUrl()` 提前重解析
  /// 模板），返回值替换 `result`；重取的响应体同样回传宿主替换原响应。
  /// 重取走沙箱确定性重放（首轮记 op，宿主抓取后重放命中缓存），因此
  /// 检查被改写为多轮循环——仅当本轮没有新增请求（或抓取无进展）才收敛。
  Future<_LoginCheckOutcome> _runLoginCheck(
    String js,
    int statusCode,
    String body, {
    String? responseUrl,
    Map<String, List<String>>? responseHeaders,
  }) async {
    try {
      // 复用 per-source 引擎：loginCheckJs 每次请求都会求值，不能每次新建
      // QuickJS 运行时。上下文种子由 JsEngine.eval 统一注入。
      final activeCtx = ShuyuanSourceContext.current;
      final engine = JsEngine.forSource(activeCtx?.sourceId);
      // `java.initUrl()`：legado 在调用点同步重解析 URL 模板；同步沙箱
      // 无法回跳宿主，改为求值前预解析一次（脚本声明即生效）。
      if (js.contains('initUrl(')) {
        reinitUrl();
      }
      final seed = jsonEncode(<String, dynamic>{
        'ruleUrl': ruleUrl,
        'url': url,
        'headers': resolveRequestHeaders(),
        'method': method?.toUpperCase() ?? '',
        'body': this.body ?? '',
      });
      // legado 里检查脚本拿到的是 StrResponse：url() 为重定向后的最终地址，
      // headers() 为真实响应头（多值头取第一条，Java Map.get 同形）。
      final lcHeaders = <String, String>{};
      responseHeaders?.forEach((k, v) {
        if (v.isNotEmpty) lcHeaders[k] = v.first;
      });
      final base = (source?.bookSourceUrl ?? '').isNotEmpty
          ? source!.bookSourceUrl
          : (baseUrl?.isNotEmpty ?? false)
              ? baseUrl!
              : url;
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      var code = statusCode;
      String? bodyOverride;
      for (var pass = 0; pass < 4; pass++) {
        final before = activeCtx == null
            ? const <String>{}
            : <String>{
                ...activeCtx.ajaxPending,
                ...activeCtx.ajaxBytesPending,
              };
        final wrapped = 'var __lcBody = ${jsonEncode(body)};\n'
            'var __lcUrl = ${jsonEncode(responseUrl ?? url)};\n'
            'var result = new String(__lcBody);\n'
            'result.__code = $statusCode;\n'
            'result.body = (function () {\n'
            '  var f = function () { return __lcBody; };\n'
            '  f.toString = f.valueOf = function () { return __lcBody; };\n'
            '  var names = Object.getOwnPropertyNames(String.prototype);\n'
            '  for (var i = 0; i < names.length; i++) {\n'
            '    var k = names[i];\n'
            '    if (k === "constructor") continue;\n'
            '    try {\n'
            '      var d = Object.getOwnPropertyDescriptor(String.prototype, k);\n'
            '      if (d && typeof d.value === "function") f[k] = d.value.bind(__lcBody);\n'
            '    } catch (e) {}\n'
            '  }\n'
            '  try { Object.defineProperty(f, "length", { value: __lcBody.length }); } catch (e) {}\n'
            '  return f;\n'
            '})();\n'
            'result.code = function () { return result.__code; };\n'
            'result.url = function () { return __lcUrl; };\n'
            'result.message = function () { return ""; };\n'
            'result.headers = function () {\n'
            '  var m = ${jsonEncode(lcHeaders)};\n'
            '  Object.defineProperty(m, "get", { value: function (n) {\n'
            '    var l = String(n).toLowerCase();\n'
            '    for (var k in m) if (k.toLowerCase() === l) return m[k];\n'
            '    return null;\n'
            '  }, enumerable: false });\n'
            '  return m;\n'
            '};\n'
            'globalThis.__syLoginBegin(${jsonEncode(seed)});\n'
            'var __lcCode = null;\n'
            'var __lcBodyOut = null;\n'
            'var __lcOut;\n'
            'var __lcSrc = ${jsonEncode(js.trim())};\n'
            'try {\n'
            // legado 取脚本完成值（Rhino eval）：尾表达式为 `result` 时即鸭子
            // 响应，尾语句为 `java.getStrResponse()` 时其返回值直接替换响应。
            '  try {\n'
            '    __lcOut = eval(__lcSrc);\n'
            '  } catch (__lcE) {\n'
            // 顶层 `return` 在 eval 中是语法错误（Rhino 脚本常写）：改按函数
            // 体编译，绑定 result 参数后取其返回值。语法错误发生在编译期，
            // 此处重试不会重复执行已产生副作用的语句。
            '    if (__lcE && __lcE.name === "SyntaxError") {\n'
            '      __lcOut = new Function("result", __lcSrc)(result);\n'
            '    } else { throw __lcE; }\n'
            '  }\n'
            '  if (__lcOut !== null && typeof __lcOut === "object") {\n'
            '    try {\n'
            '      __lcCode = (typeof __lcOut.code === "function")\n'
            '        ? __lcOut.code() : __lcOut.code;\n'
            '    } catch (e) {}\n'
            '    if (typeof __lcOut.body === "function") {\n'
            '      try { __lcBodyOut = String(__lcOut.body()); } catch (e) {}\n'
            '    } else if (typeof __lcOut.body === "string") {\n'
            '      __lcBodyOut = __lcOut.body;\n'
            '    }\n'
            '  } else if (__lcOut !== undefined) {\n'
            '    __lcCode = __lcOut;\n'
            '  }\n'
            '} finally {\n'
            '  globalThis.__syLoginEnd();\n'
            '}\n'
            'JSON.stringify({o: __lcCode, b: __lcBodyOut})';
        final r = engine.eval(wrapped,
            bindings: {'baseUrl': base, 'key': key ?? '', 'page': page});
        final parsed = _parseLoginCheckResult(r, statusCode);
        code = parsed.code;
        if (parsed.body != null && !_hasReplayPlaceholder(parsed.body!)) {
          bodyOverride = parsed.body;
        }
        if (activeCtx == null) break;
        final after = <String>{
          ...activeCtx.ajaxPending,
          ...activeCtx.ajaxBytesPending,
        };
        final hasNewRequests = after.difference(before).isNotEmpty;
        if (!hasNewRequests) break;
        if (!DateTime.now().isBefore(deadline)) break;
        final fetched = await ShuyuanSourceContext.settleAjax(
          activeCtx,
          source!,
          deadline: deadline,
        );
        if (fetched == 0) break;
      }
      return _LoginCheckOutcome(code, bodyOverride);
    } catch (_) {
      return _LoginCheckOutcome(statusCode, null);
    }
  }

  /// 解析检查脚本的 JSON 结果；非法状态码维持原状态码（避免把正文里
  /// 出现的数字误判成登录状态）。
  static _LoginCheckOutcome _parseLoginCheckResult(
      String r, int statusCode) {
    if (r.isEmpty) return _LoginCheckOutcome(statusCode, null);
    final decoded = jsonDecode(r);
    if (decoded is! Map) return _LoginCheckOutcome(statusCode, null);
    final raw = decoded['o'];
    int? code;
    if (raw is int) {
      code = raw;
    } else if (raw is num) {
      code = raw.toInt();
    } else if (raw is String) {
      code = int.tryParse(raw.trim());
    }
    if (code == null || code < 100 || code > 599) {
      return _LoginCheckOutcome(statusCode, null);
    }
    final rawBody = decoded['b'];
    return _LoginCheckOutcome(
        code, rawBody is String ? rawBody : null);
  }
}

/// loginCheckJs 求值结果：状态码 + 可选的改写响应体（legado 中检查脚本
/// 返回的 StrResponse 会替换原响应继续参与解析）。
class _LoginCheckOutcome {
  const _LoginCheckOutcome(this.code, this.body);

  final int code;
  final String? body;
}

/// loginCheckJs 判定未登录（legado 语义：code==500）。上层据此引导用户
/// 前往源管理完成登录。
class ShuyuanLoginRequiredException implements Exception {
  ShuyuanLoginRequiredException({required this.url, required this.sourceName});

  final String url;
  final String sourceName;

  @override
  String toString() =>
      '书源「$sourceName」需要登录（loginCheckJs 判定未登录）：$url';
}
