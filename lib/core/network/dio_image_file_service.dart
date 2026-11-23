/// 图片下载统一收编到应用网络层（HttpFetcher/Dio）的缓存管理器。
///
/// 为什么不用 flutter_cache_manager 默认的 HttpFileService（package:http →
/// `dart:io HttpClient`）：DefaultCacheManager 是全局单例，其 HttpClient 在
/// **首次图片请求时创建一次并终身复用**，且创建时机早于网络档案从磁盘加载
/// （splash 渲染后才 `NetworkConfigService.load()`）。早期以默认档案（直连、
/// 无代理、无 DNS/SNI 覆盖）创建的客户端永远不会重建——此后即使档案加载完成，
/// 所有图片仍按「直连」发出；而页面/接口请求走 Dio 每次按当前档案取连接，
/// 于是出现「RSS 文字正常、封面/图片全部加载失败」的割裂现象（代理/DNS 用户
/// 必现）。音频（libmpv 自主联网）同理不吃应用代理，另行注入。
///
/// 本文件服务把图片字节下载改为每次调用 [HttpFetcher.getBytesStream]：
/// 按当前全局档案取 Dio（代理/DNS/SNI/Cookie/UA 与页面请求完全一致，档案
/// 变更即时生效），防盗链头（Referer/UA/Cookie）仍由调用方（SourceImage）
/// 经 headers 传入并合并。磁盘缓存结构沿用 flutter_cache_manager，缓存键
/// 与旧 DefaultCacheManager 不同（`nexCachedImageData`），升级后首次会重新
/// 下载一次图片，属可接受的一次性成本。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

import '../models/plugin_config.dart';
import '../scraper/http_fetcher.dart';
import '../utils/app_log.dart';
import '../utils/image_decrypt_registry.dart';
import 'model/effective_network_profile.dart';
import 'network_config_service.dart';

/// 全应用统一图片缓存管理器（SourceImage 专用入口）。
class NexImageCacheManager extends CacheManager {
  static const String key = 'nexCachedImageData';

  static final NexImageCacheManager instance = NexImageCacheManager._(key, null);

  /// 按源取管理器：源非 null 时其图片请求走该源的有效网络档案
  /// （ECH/mitm/代理与页面同路）。缓存目录按源隔离（源图片本就源专属）。
  ///
  /// [cover]=true 时另建一份封面专用管理器：书源 `coverDecodeJs` 只作用于
  /// 封面字节（legado ImageUtils.decode isCover 分支），与正文插图共用缓存
  /// 会让「已解码封面 → 正文图被误当封面解码」互相污染，故缓存目录与
  /// 解码上下文一起按封面拆分。
  static final Map<String, NexImageCacheManager> _byKey = <String, NexImageCacheManager>{};

  static NexImageCacheManager forSource(
    PluginConfig? source, {
    bool cover = false,
  }) {
    if (source == null) return instance;
    final k = cover ? '${key}_${source.id}_cover' : '${key}_${source.id}';
    return _byKey.putIfAbsent(k, () {
      return NexImageCacheManager._(k, () {
        try {
          return NetworkConfigService.instance.effectiveFor(source);
        } on Object {
          return NetworkConfigService.instance.globalProfile;
        }
      }, source: source, cover: cover);
    });
  }

  NexImageCacheManager._(
    String cacheKey,
    EffectiveNetworkProfile? Function()? netProvider, {
    PluginConfig? source,
    bool cover = false,
  }) : super(Config(
          cacheKey,
          stalePeriod: const Duration(days: 30),
          maxNrOfCacheObjects: 5000,
          fileService: DioImageFileService(
            netProvider: netProvider,
            decodeSource: source,
            decodeCover: cover,
          ),
        ));
}

/// 基于 HttpFetcher（Dio）的图片文件服务：每次请求都按**当前**全局网络档案
/// 取连接，不存在「早期创建、终身僵化」的 HttpClient。
///
/// 源级网络档案（netProvider）：SourceImage 按源传入提供者后，封面请求走该源的
/// 有效档案（ECH/mitm/代理/DNS 与页面请求同路）。此前固定用全局档案——源级
/// 开启 ECH 的源会出现「页面 200、封面 403」的割裂（CDN 按 TLS 通道指纹拒绝
/// Dart 直连）。
class DioImageFileService extends FileService {
  /// 失败日志上限：图片列表一屏几十张，网络断开时逐张记录会刷爆运行日志；
  /// 数十条足以定位「哪批 URL / 什么错误」。
  static const int _maxLoggedFailures = 30;

  /// 响应头到达的超时：超过视为连接僵死，按失败处理（WebHelper 会向上抛，
  /// SourceImage 的重试按钮接管）。
  static const Duration _headerTimeout = Duration(seconds: 30);

  /// 首包超时：响应头已到但正文迟迟不来（连接被吊起/网关半开），按失败处理，
  /// 否则占位图会永远转圈。
  static const Duration _bodyProbeTimeout = Duration(seconds: 15);

  /// 正文无数据超时（与 legado 的 read/callTimeout=60s 对齐）：首包到达后若
  /// 连续这么久没有新字节，终止下载并按失败上报，避免永久停在学习态。
  static const Duration _bodyStallTimeout = Duration(seconds: 60);

  /// 首包探测保留的字节数：判类只需开头一小段。
  static const int _headProbeLimit = 512;

  static int _loggedFailures = 0;

  /// 源级网络档案提供者（每次请求动态取，档案变更即时生效）。
  final EffectiveNetworkProfile? Function()? netProvider;

  /// 封面解码上下文：非 null 且 [decodeCover] 为 true 时按源
  /// `coverDecodeJs` 解码下载字节（legado ImageUtils.decode isCover 分支）。
  final PluginConfig? decodeSource;
  final bool decodeCover;

  DioImageFileService({
    this.netProvider,
    this.decodeSource,
    this.decodeCover = false,
  });

  /// 聚合完整字节流（仅解密分支使用：AES-CBC 需要 IV + 完整密文体）。
  static Future<Uint8List> _collect(Stream<List<int>> stream) async {
    final BytesBuilder b = BytesBuilder(copy: false);
    await for (final List<int> chunk in stream) {
      b.add(chunk);
    }
    return b.takeBytes();
  }

  static bool _isWhitespace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

  /// 正文首包是否可能为图片。
  ///
  /// 与 legado「解码不通过就不写入图片文件」对齐的下载层闸门：任何 2xx 正文
  /// 都会被缓存层持久化（stalePeriod 30 天），若把 HTML 拦截页/验证页/错误
  /// JSON 当图片缓存，之后每次重试都命中坏文件、永远无法恢复。这里只拒绝
  /// **明确以文本标记/JSON 开头**的响应，其余（图片魔数、未知二进制）一律
  /// 放行交给解码器——图床把 JPEG 标成 `text/html` 或声明缺失的情况真实存在，
  /// 宁放勿错杀。SVG 也放行：它由解码器判失败并进入逐出+重试路径。
  @visibleForTesting
  static bool isLikelyImagePayload(List<int> head) {
    if (head.isEmpty) return false;
    int i = 0;
    // UTF-8 BOM
    if (head.length >= 3 &&
        head[0] == 0xEF &&
        head[1] == 0xBB &&
        head[2] == 0xBF) {
      i = 3;
    }
    while (i < head.length && _isWhitespace(head[i])) {
      i++;
    }
    if (i >= head.length) return true; // 仅空白：交给解码器判定
    final int c0 = head[i];
    if (c0 == 0x7B || c0 == 0x5B) return false; // { [ → JSON 正文
    if (c0 != 0x3C) return true; // 非 '<' → 二进制（图片魔数等）
    // 取首个标签名：跳过 / ! ? 与空白（<> 注释/doctype/xml 声明 → 非 svg）
    int j = i + 1;
    while (j < head.length &&
        (head[j] == 0x2F ||
            head[j] == 0x21 ||
            head[j] == 0x3F ||
            _isWhitespace(head[j]))) {
      j++;
    }
    final StringBuffer tag = StringBuffer();
    while (j < head.length && tag.length < 8) {
      final int ch = head[j];
      final bool alnum = (ch >= 0x41 && ch <= 0x5A) ||
          (ch >= 0x61 && ch <= 0x7A) ||
          (ch >= 0x30 && ch <= 0x39);
      if (!alnum) break;
      tag.writeCharCode(ch);
      j++;
    }
    return tag.toString().toLowerCase() == 'svg';
  }

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    int statusCode = 0;
    int? contentLength;
    final Map<String, String> responseHeaders = <String, String>{};

    // 响应头到达前到达的字节先进缓冲（正常为空：onHeaders 在首个分块前回调），
    // 头到达后统一灌入 [body]，之后的分块由订阅直接转发。
    final StreamController<List<int>> body = StreamController<List<int>>();
    final List<List<int>> earlyChunks = <List<int>>[];
    bool headersArrived = false;
    final Completer<void> headersWaiter = Completer<void>();
    // 首包探测：拿到第一个正文分块（或流结束/出错）才向下游返回响应。
    final Completer<void> bodyStarted = Completer<void>();
    final List<int> headProbe = <int>[];
    Object? probeError;
    Timer? stallTimer;
    StreamSubscription<Uint8List>? sub;

    // 正文停滞看门狗：首包到达后连续无数据即终止下载并向上报错，避免图片
    // 永远停在加载态（对齐 legado 的 OkHttp read/callTimeout=60s）。
    void armStallWatchdog() {
      stallTimer?.cancel();
      stallTimer = Timer(_bodyStallTimeout, () {
        if (body.isClosed) return;
        unawaited(sub?.cancel());
        body.addError(TimeoutException(
            '图片正文中断（${_bodyStallTimeout.inSeconds}s 无数据）',
            _bodyStallTimeout));
        unawaited(body.close());
      });
    }

    try {
      final Stream<Uint8List> raw = HttpFetcher.instance.getBytesStream(
        url,
        headers: headers,
        net: netProvider?.call() ??
            NetworkConfigService.instance.globalProfile,
        fetchDest: 'image',
        onHeaders: (Map<String, List<String>> h) {
          h.forEach((String k, List<String> v) {
            if (v.isNotEmpty) responseHeaders[k.toLowerCase()] = v.first;
          });
          contentLength =
              int.tryParse(responseHeaders['content-length'] ?? '');
          headersArrived = true;
          for (final List<int> chunk in earlyChunks) {
            body.add(chunk);
          }
          earlyChunks.clear();
          if (!headersWaiter.isCompleted) headersWaiter.complete();
        },
        onStatusCode: (int code) => statusCode = code,
      );
      sub = raw.listen(
        (Uint8List chunk) {
          if (!bodyStarted.isCompleted) bodyStarted.complete();
          if (headProbe.length < _headProbeLimit) {
            headProbe.addAll(chunk.take(_headProbeLimit - headProbe.length));
          }
          if (body.isClosed) return;
          if (headersArrived) {
            body.add(chunk);
            armStallWatchdog();
          } else {
            earlyChunks.add(chunk);
          }
        },
        onError: (Object e, StackTrace st) {
          probeError ??= e;
          stallTimer?.cancel();
          if (!bodyStarted.isCompleted) bodyStarted.complete();
          if (!headersWaiter.isCompleted) headersWaiter.completeError(e, st);
          // 下游已取消/关闭后到达的错误不能转发（控制器抛 StateError）。
          if (!body.isClosed) body.addError(e, st);
        },
        onDone: () {
          if (!bodyStarted.isCompleted) bodyStarted.complete();
          stallTimer?.cancel();
          if (!body.isClosed) body.close();
        },
      );
      await headersWaiter.future.timeout(_headerTimeout);
      if (statusCode < 200 || statusCode >= 300) {
        throw HttpException('HTTP $statusCode',
            uri: Uri.tryParse(url));
      }
      // 正文首包到达前不向下游返回：空响应/僵死正文在这里就判失败，而不是让
      // 缓存层保存一个空文件、让占位图永远转圈。
      await bodyStarted.future.timeout(_bodyProbeTimeout);
      final Object? firstChunkError = probeError;
      if (firstChunkError != null) {
        throw firstChunkError;
      }
      if (headProbe.isEmpty) {
        throw HttpException('图片响应为空', uri: Uri.tryParse(url));
      }
      final Uri? uri = Uri.tryParse(url);
      final bool encrypted =
          uri != null && ImageBytesDecryptRegistry.matchFor(uri) != null;
      // 书源字节解码（legado ImageUtils.decode）：封面走 coverDecodeJs，
      // 正文插图走 ruleContent.imageDecode。密文图片可能以任意字节开头
      // （含 '<'/'{'），不能走 isLikelyImagePayload 的明文闸门；改为缓冲
      // 全量字节交给 shuyuan 层解码，解码结果再交给缓存层（磁盘缓存明文）。
      // 正文分支仅在源确实声明 imageDecode 时启用，其余源保持流式下载。
      final Uint8List? Function(PluginConfig, String, Uint8List)? sourceDecode;
      if (!encrypted && decodeSource != null) {
        if (decodeCover) {
          sourceDecode = ShuyuanImageDecodeHooks.coverResolver;
        } else if (ShuyuanImageDecodeHooks.contentResolver != null &&
            (ShuyuanImageDecodeHooks.contentApplies?.call(decodeSource!) ??
                false)) {
          sourceDecode = ShuyuanImageDecodeHooks.contentResolver;
        } else {
          sourceDecode = null;
        }
      } else {
        sourceDecode = null;
      }
      // 非图片正文（拦截页/错误 JSON）直接判失败：与 legado「解码不通过绝不
      // 写入图片文件」对齐。否则坏文件会被缓存 30 天，之后每次重试都命中它，
      // 表现为封面/图片永久无法加载。
      if (!encrypted && sourceDecode == null && !isLikelyImagePayload(headProbe)) {
        throw HttpException('非图片响应（拦截页/错误页）', uri: uri);
      }
      if (sourceDecode != null) {
        final Uint8List fetched = await _collect(body.stream);
        stallTimer?.cancel();
        final Uint8List? plain = sourceDecode(decodeSource!, url, fetched);
        if (plain == null) {
          throw HttpException(
              decodeCover ? '封面解码失败（coverDecodeJs）' : '图片解码失败（imageDecode）',
              uri: uri);
        }
        return HttpGetResponse(http.StreamedResponse(
          Stream<Uint8List>.value(plain),
          statusCode,
          contentLength: plain.length,
          headers: responseHeaders,
        ));
      }
      // 源声明式图片解密（imageTransform）：命中注册 host 时缓冲全量字节解密
      // 后再交给缓存层（磁盘缓存的是明文，保存/分享自动继承）。未命中的源
      // 走原流式路径，零额外开销。
      if (encrypted) {
        final Uint8List cipher = await _collect(body.stream);
        stallTimer?.cancel();
        final Uint8List plain = ImageBytesDecryptRegistry.decrypt(uri, cipher);
        return HttpGetResponse(http.StreamedResponse(
          Stream<Uint8List>.value(plain),
          statusCode,
          contentLength: plain.length,
          headers: responseHeaders,
        ));
      }
      // 下游取消（缓存被丢弃/重试）时同步掐断底层下载与看门狗，避免连接空转。
      body.onCancel = () {
        stallTimer?.cancel();
        unawaited(sub?.cancel());
      };
      armStallWatchdog();
      return HttpGetResponse(http.StreamedResponse(
        body.stream,
        statusCode,
        contentLength: contentLength,
        headers: responseHeaders,
      ));
    } on Object catch (e) {
      stallTimer?.cancel();
      await sub?.cancel();
      // 不能 await：失败路径上 body.stream 可能从未被订阅（响应尚未返回给
      // 缓存层），无监听者的 close() 其 future 永不完成，会把它上面的调用方
      // 永久挂起（历史上的「图片一直加载」就包括这一条）。
      if (!body.isClosed) unawaited(body.close());
      if (_loggedFailures < _maxLoggedFailures) {
        _loggedFailures++;
        AppLog.instance.w('图片加载失败(HTTP $statusCode): $url — $e');
      }
      rethrow;
    }
  }
}
