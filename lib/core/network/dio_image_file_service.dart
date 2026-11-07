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
  static final Map<String, NexImageCacheManager> _byKey = <String, NexImageCacheManager>{};

  static NexImageCacheManager forSource(PluginConfig? source) {
    if (source == null) return instance;
    final k = '${key}_${source.id}';
    return _byKey.putIfAbsent(k, () {
      return NexImageCacheManager._(k, () {
        try {
          return NetworkConfigService.instance.effectiveFor(source);
        } on Object {
          return NetworkConfigService.instance.globalProfile;
        }
      });
    });
  }

  NexImageCacheManager._(String cacheKey, EffectiveNetworkProfile? Function()? netProvider)
      : super(Config(
          cacheKey,
          stalePeriod: const Duration(days: 30),
          maxNrOfCacheObjects: 5000,
          fileService: DioImageFileService(netProvider: netProvider),
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

  static int _loggedFailures = 0;

  /// 源级网络档案提供者（每次请求动态取，档案变更即时生效）。
  final EffectiveNetworkProfile? Function()? netProvider;

  DioImageFileService({EffectiveNetworkProfile? Function()? netProvider})
      : netProvider = netProvider;

  /// 聚合完整字节流（仅解密分支使用：AES-CBC 需要 IV + 完整密文体）。
  static Future<Uint8List> _collect(Stream<List<int>> stream) async {
    final BytesBuilder b = BytesBuilder(copy: false);
    await for (final List<int> chunk in stream) {
      b.add(chunk);
    }
    return b.takeBytes();
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
    StreamSubscription<Uint8List>? sub;

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
          if (body.isClosed) return;
          if (headersArrived) {
            body.add(chunk);
          } else {
            earlyChunks.add(chunk);
          }
        },
        onError: (Object e, StackTrace st) {
          if (!headersWaiter.isCompleted) headersWaiter.completeError(e, st);
          // 下游已取消/关闭后到达的错误不能转发（控制器抛 StateError）。
          if (!body.isClosed) body.addError(e, st);
        },
        onDone: () {
          if (!body.isClosed) body.close();
        },
      );
      await headersWaiter.future.timeout(_headerTimeout);
      if (statusCode < 200 || statusCode >= 300) {
        throw HttpException('HTTP $statusCode',
            uri: Uri.tryParse(url));
      }
      // 源声明式图片解密（imageTransform）：命中注册 host 时缓冲全量字节解密
      // 后再交给缓存层（磁盘缓存的是明文，保存/分享自动继承）。未命中的源
      // 走原流式路径，零额外开销。
      final Uri? uri = Uri.tryParse(url);
      if (uri != null && ImageBytesDecryptRegistry.matchFor(uri) != null) {
        final Uint8List cipher = await _collect(body.stream);
        final Uint8List plain = ImageBytesDecryptRegistry.decrypt(uri, cipher);
        return HttpGetResponse(http.StreamedResponse(
          Stream<Uint8List>.value(plain),
          statusCode,
          contentLength: plain.length,
          headers: responseHeaders,
        ));
      }
      // 下游取消（缓存被丢弃/重试）时同步掐断底层下载，避免连接空转。
      body.onCancel = () => sub?.cancel();
      return HttpGetResponse(http.StreamedResponse(
        body.stream,
        statusCode,
        contentLength: contentLength,
        headers: responseHeaders,
      ));
    } on Object catch (e) {
      await sub?.cancel();
      if (!body.isClosed) await body.close();
      if (_loggedFailures < _maxLoggedFailures) {
        _loggedFailures++;
        AppLog.instance.w('图片加载失败(HTTP $statusCode): $url — $e');
      }
      rethrow;
    }
  }
}
