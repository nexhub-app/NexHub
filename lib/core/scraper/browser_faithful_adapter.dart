/// 浏览器一致的 HTTP 客户端适配器（Dio [HttpClientAdapter] 实现）。
///
/// ## 为什么需要它
/// Dart 自带的 `HttpClient`（Dio 默认 [IOHttpClientAdapter] 的底层）在发起请求时：
/// 1. 把所有请求头名**强制小写**；
/// 2. 把 `Host` 头**固定排在最后**，且顺序无法干预。
///
/// 部分 Cloudflare 站点（如笔趣阁 m.biqubu3.com）会据此做**静态机器指纹拦截**：
/// 只要头名不是浏览器风格的 Title-Case、或 `Host` 不在首行，就直接返回
/// 403「Just a moment...」挑战壳——**即使不带任何 Cookie，浏览器风格的请求也能
/// 直接拿到 200 正文**。因此这类拦截不是「过一次 WebView 验证就能解决」的交互式
/// 挑战，而是请求指纹本身不对；Dio 直连每次都会被重新拦，表现为「验证完仍解析
/// 不到内容 / 一直加载」。
///
/// 本适配器绕过 `HttpClient`，直接用 [SecureSocket]/[Socket] 手写 HTTP/1.1 请求，
/// 完全控制头名大小写与顺序（`Host` 首行 + Title-Case），从而通过上述指纹检测。
///
/// ## 覆盖范围与回落
/// 仅接管 `http`/`https` 直连（无系统代理场景，与书源 [AnalyzeUrl] 现状一致）。
/// 无法处理或出现异常时回落到内置 [IOHttpClientAdapter]，避免破坏既有行为。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

class BrowserFaithfulHttpClientAdapter implements HttpClientAdapter {
  BrowserFaithfulHttpClientAdapter({HttpClientAdapter? fallback})
      : _fallback = fallback ?? IOHttpClientAdapter();

  /// 请求级自定义建连 IP（legado `UrlOption.dnsIp` 语义）：书源链路把
  /// `Options.extra` 里的本键传给适配器后，socket 直连该 IP（TLS SNI 与
  /// Host 头仍用原域名）；原生源不带此键，行为不变。
  static const String dnsIpExtraKey = 'syDnsIp';

  final HttpClientAdapter _fallback;

  /// 状态码属于「需要跟随的重定向」。
  static const Set<int> _redirectCodes = {301, 302, 303, 307, 308};

  /// 请求头的浏览器规范顺序（`Host` 恒定首行，其余按 Chrome 常见次序）。
  /// 未列出的头统一追加到末尾（保持插入序）。
  static const List<String> _canonicalOrder = <String>[
    'host',
    'connection',
    'user-agent',
    'accept',
    'accept-language',
    'accept-encoding',
    'referer',
    'cookie',
    'content-type',
    'content-length',
  ];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final uri = options.uri;
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      return _fallback.fetch(options, requestStream, cancelFuture);
    }

    // 收集请求体（POST 等）。
    List<int>? body;
    if (requestStream != null) {
      final chunks = <int>[];
      await for (final c in requestStream) {
        chunks.addAll(c);
      }
      body = chunks;
    }

    // 归一化入参头（小写键便于查找/去重；输出时再 Title-Case）。
    final headers = <String, String>{};
    options.headers.forEach((k, v) {
      if (v != null) headers[k.toString().toLowerCase()] = v.toString();
    });

    final connectTimeout = options.connectTimeout ?? const Duration(seconds: 15);
    final receiveTimeout = options.receiveTimeout ?? const Duration(seconds: 30);
    final maxRedirects = options.followRedirects ? options.maxRedirects : 0;
    final dnsIp = options.extra?[dnsIpExtraKey] as String?;

    try {
      var currentUri = uri;
      var method = options.method.toUpperCase();
      var curBody = body;
      var redirectCount = 0;
      final redirectRecords = <RedirectRecord>[];

      while (true) {
        final resp = await _perform(
          currentUri,
          method,
          headers,
          curBody,
          connectTimeout,
          receiveTimeout,
          dnsIp,
        );

        final isRedirect = _redirectCodes.contains(resp.status);
        if (isRedirect &&
            resp.location != null &&
            resp.location!.isNotEmpty &&
            redirectCount < maxRedirects) {
          redirectCount++;
          final next = _resolveLocation(currentUri, resp.location!);
          redirectRecords.add(RedirectRecord(resp.status, method, next));
          // 301/302/303 → 浏览器改用 GET 且丢弃请求体，307/308 保持原样。
          if (resp.status == 301 || resp.status == 302 || resp.status == 303) {
            method = 'GET';
            curBody = null;
            headers.remove('content-type');
            headers.remove('content-length');
          }
          headers.remove('host'); // 交给 _perform 按新 host 重算。
          currentUri = next;
          continue;
        }

        return ResponseBody.fromBytes(
          resp.body,
          resp.status,
          headers: resp.headers,
          isRedirect: redirectCount > 0,
          statusMessage: resp.reason,
        )..redirects = redirectRecords;
      }
    } on Object {
      // 任何异常（TLS/解析/超时等）回落到内置适配器，保证不比现状更差。
      return _fallback.fetch(options, requestStream, cancelFuture);
    }
  }

  /// 建连：默认按 URI host 走系统 DNS；携带 dnsIp 时（legado 自定义 DNS）
  /// socket 直连指定 IP，HTTPS 再以原域名做 SNI/证书握手。
  Future<Socket> _connect(
    Uri uri,
    String host,
    int port,
    Duration connectTimeout,
    String? dnsIp,
  ) async {
    final ip = _firstIp(dnsIp);
    if (ip == null) {
      return uri.scheme == 'https'
          ? SecureSocket.connect(
              host,
              port,
              timeout: connectTimeout,
              onBadCertificate: (_) => true,
              supportedProtocols: const ['http/1.1'],
            )
          : Socket.connect(host, port, timeout: connectTimeout);
    }
    final raw = await Socket.connect(ip, port, timeout: connectTimeout);
    if (uri.scheme != 'https') return raw;
    return SecureSocket.secure(
      raw,
      host: host,
      onBadCertificate: (_) => true,
      supportedProtocols: const ['http/1.1'],
    );
  }

  /// 从逗号分隔的 dnsIp 串中取第一个可解析 IP（legado `parseIpsFromString`）；
  /// 全部不可解析时返回 null，回落系统 DNS。
  static String? _firstIp(String? dnsIp) {
    if (dnsIp == null || dnsIp.trim().isEmpty) return null;
    for (final part in dnsIp.split(',')) {
      final text = part.trim();
      if (text.isEmpty) continue;
      final addr = InternetAddress.tryParse(text);
      if (addr != null) return addr.address;
    }
    return null;
  }

  Future<_RawResponse> _perform(
    Uri uri,
    String method,
    Map<String, String> headers,
    List<int>? body,
    Duration connectTimeout,
    Duration receiveTimeout,
    String? dnsIp,
  ) async {
    final host = uri.host;
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    final Socket socket = await _connect(uri, host, port, connectTimeout, dnsIp);

    try {
      socket.add(_buildRequest(uri, method, headers, body));
      await socket.flush();

      final all = <int>[];
      // 逐块读取直到服务端关闭连接（我们发送 Connection: close）。
      // 用 per-gap 超时兜底，避免坏连接永久挂起。
      await socket
          .timeout(receiveTimeout, onTimeout: (sink) => sink.close())
          .forEach(all.addAll);

      return _parseResponse(Uint8List.fromList(all));
    } finally {
      socket.destroy();
    }
  }

  Uint8List _buildRequest(
    Uri uri,
    String method,
    Map<String, String> headers,
    List<int>? body,
  ) {
    final path = _requestTarget(uri);
    final hostValue = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;

    // 复制一份可消费的头表；强制补齐浏览器风格的必备头。
    final pending = Map<String, String>.from(headers);
    pending['host'] = hostValue;
    pending['connection'] = 'close';
    // 只声明我们能解码的编码，避免服务端用 br/zstd 导致无法解压。
    pending['accept-encoding'] = 'gzip, deflate';
    if (body != null) {
      pending['content-length'] = '${body.length}';
    }

    final sb = StringBuffer()..write('$method $path HTTP/1.1\r\n');
    final written = <String>{};
    void emit(String lowerName) {
      final value = pending[lowerName];
      if (value == null || written.contains(lowerName)) return;
      sb.write('${_titleCase(lowerName)}: $value\r\n');
      written.add(lowerName);
    }

    for (final name in _canonicalOrder) {
      emit(name);
    }
    // 其余自定义头按原插入序追加。
    for (final name in pending.keys) {
      emit(name);
    }
    sb.write('\r\n');

    final headBytes = ascii.encode(sb.toString());
    if (body == null || body.isEmpty) return Uint8List.fromList(headBytes);
    return Uint8List.fromList([...headBytes, ...body]);
  }

  String _requestTarget(Uri uri) {
    final path = uri.path.isEmpty ? '/' : uri.path;
    return uri.query.isEmpty ? path : '$path?${uri.query}';
  }

  _RawResponse _parseResponse(Uint8List raw) {
    final sep = _indexOfHeaderEnd(raw);
    if (sep < 0) {
      // 没有完整头（异常响应）——当作空体 502 交给上层判定。
      return const _RawResponse(
        502,
        <String, List<String>>{},
        <int>[],
        null,
        'Bad Gateway',
      );
    }
    final headText = latin1.decode(raw.sublist(0, sep));
    List<int> bodyBytes = raw.sublist(sep + 4);

    final lines = headText.split('\r\n');
    final statusLine = lines.isNotEmpty ? lines.first : 'HTTP/1.1 502';
    final statusParts = statusLine.split(' ');
    final status = statusParts.length >= 2 ? int.tryParse(statusParts[1]) ?? 0 : 0;
    final reason =
        statusParts.length >= 3 ? statusParts.sublist(2).join(' ') : null;

    final headers = <String, List<String>>{};
    for (final line in lines.skip(1)) {
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      final name = line.substring(0, idx).trim().toLowerCase();
      final value = line.substring(idx + 1).trim();
      headers.putIfAbsent(name, () => <String>[]).add(value);
    }

    // Transfer-Encoding: chunked → 先解块。
    final te = headers['transfer-encoding']?.join(',').toLowerCase() ?? '';
    if (te.contains('chunked')) {
      bodyBytes = _dechunk(bodyBytes);
    }

    // Content-Encoding: gzip/deflate → 解压。
    final ce = headers['content-encoding']?.join(',').toLowerCase() ?? '';
    if (ce.contains('gzip')) {
      bodyBytes = _tryDecode(() => gzip.decode(bodyBytes), bodyBytes);
    } else if (ce.contains('deflate')) {
      bodyBytes = _tryDecode(
        () => zlib.decode(bodyBytes),
        // 部分服务端发原始 deflate（无 zlib 包裹）→ 退一步用 raw inflate。
        _tryDecode(
          () => ZLibDecoder(raw: true).convert(bodyBytes),
          bodyBytes,
        ),
      );
    }

    final location = headers['location']?.first;
    return _RawResponse(
      status,
      headers,
      bodyBytes,
      location,
      reason,
    );
  }

  List<int> _tryDecode(List<int> Function() decode, List<int> fallback) {
    try {
      return decode();
    } on Object {
      return fallback;
    }
  }

  /// 解 HTTP chunked 传输编码。
  Uint8List _dechunk(List<int> data) {
    final out = <int>[];
    var i = 0;
    while (i < data.length) {
      // 读取块长度行（十六进制，可能带 `;扩展`）。
      final lineEnd = _indexOfCRLF(data, i);
      if (lineEnd < 0) break;
      final sizeLine = latin1.decode(data.sublist(i, lineEnd));
      final semi = sizeLine.indexOf(';');
      final hex = (semi >= 0 ? sizeLine.substring(0, semi) : sizeLine).trim();
      final size = int.tryParse(hex, radix: 16);
      if (size == null) break;
      i = lineEnd + 2;
      if (size == 0) break; // 终止块。
      if (i + size > data.length) {
        out.addAll(data.sublist(i));
        break;
      }
      out.addAll(data.sublist(i, i + size));
      i += size + 2; // 跳过块尾 CRLF。
    }
    return Uint8List.fromList(out);
  }

  int _indexOfHeaderEnd(List<int> data) {
    for (var i = 0; i + 3 < data.length; i++) {
      if (data[i] == 13 &&
          data[i + 1] == 10 &&
          data[i + 2] == 13 &&
          data[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  int _indexOfCRLF(List<int> data, int from) {
    for (var i = from; i + 1 < data.length; i++) {
      if (data[i] == 13 && data[i + 1] == 10) return i;
    }
    return -1;
  }

  Uri _resolveLocation(Uri base, String location) {
    try {
      return base.resolve(location);
    } on Object {
      return base;
    }
  }

  /// 把小写头名转成浏览器风格 Title-Case（如 `user-agent` → `User-Agent`）。
  static String _titleCase(String lower) {
    return lower
        .split('-')
        .map((p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}')
        .join('-');
  }

  @override
  void close({bool force = false}) => _fallback.close(force: force);
}

class _RawResponse {
  const _RawResponse(
    this.status,
    this.headers,
    this.body,
    this.location,
    this.reason,
  );

  final int status;
  final Map<String, List<String>> headers;
  final List<int> body;
  final String? location;
  final String? reason;
}
