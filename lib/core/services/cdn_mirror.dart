/// GitHub 资源的多源兜底拉取（jsDelivr → GitHub raw → 国内反代镜像）。
///
/// 官方源库清单（`index.json`）与库内各源文件（`rawUrl`）都挂在 jsDelivr 上，
/// 而国内 jsDelivr 常被墙/超时——单一地址失败会让「源库」整页打不开，日志里
/// 只剩一串 `DioExceptionType.unknown`。这里把同一个 GitHub 路径派生成多个
/// 可达地址，**阶梯竞速**取最先返回的有效结果：网络正常时只发出第一个请求
/// （不浪费流量），被墙时才逐步放出后备源。
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../network/network_config_service.dart';
import '../network/runtime/network_client_builder.dart';

/// 拉取结果：[text] 正文，[url] 实际可用的地址（清单里的相对路径要据此解析）。
typedef CdnFetchResult = ({String text, String url});

/// GitHub 资源多源拉取器。
class CdnMirror {
  CdnMirror._();

  /// `https://cdn.jsdelivr.net/gh/<owner>/<repo>@<ref>/<path>`
  static final RegExp _jsdelivr = RegExp(
    r'^https?://cdn\.jsdelivr\.net/gh/([^/]+)/([^/@]+)@([^/]+)/(.+)$',
  );

  /// `https://raw.githubusercontent.com/<owner>/<repo>/<ref>/<path>`
  static final RegExp _raw = RegExp(
    r'^https?://raw\.githubusercontent\.com/([^/]+)/([^/]+)/([^/]+)/(.+)$',
  );

  static const String _rawPrefix = 'https://raw.githubusercontent.com/';

  /// 国内反代（直接拼在原始 raw 地址前面）。
  static const String _mirrorPrefix = 'https://ghfast.top/';

  /// 候选之间的启动间隔：正常网络只发第一个，被墙时才逐级放出后备。
  static const int _staggerMs = 600;

  /// 整体硬上限：任一候选卡在 DNS / 慢链路也不让页面一直转圈。
  static const Duration _hardTimeout = Duration(seconds: 12);

  /// 构造一次性客户端：CDN 属「拉配置」场景，超时要比抓源站激进得多
  /// （[HttpFetcher] 的 15s 连接 + 3 次重试在墙前会干等 45s）。
  ///
  /// 但**连接池必须走全局网络档案**（[NetworkConfigService.globalProfile]）：
  /// 国内很多用户靠全局代理访问 GitHub/jsDelivr，裸 [HttpClient] 会绕开代理，
  /// 加了镜像兜底也照样连不上。每次拉取重建，保证改代理后立即生效。
  static Dio _newDio() {
    final Dio dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 4),
        sendTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 8),
        responseType: ResponseType.plain,
        headers: const <String, Object>{
          'Accept': 'application/json, text/plain, */*',
        },
      ),
    );
    try {
      final service = NetworkConfigService.instance;
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () => NetworkClientBuilder.buildHttpClient(
          service.globalProfile,
          proxyPassword: service.proxyPassword,
        ),
      );
    } on Object {
      // 档案未就绪（启动早期）/构建失败：回退裸客户端，不阻断兜底链路。
    }
    return dio;
  }

  /// 同内容候选地址：原地址 → GitHub raw → 国内反代（去重，首个恒为入参）。
  ///
  /// 非 GitHub/jsDelivr 地址（用户自建源库）原样返回单元素，不改变既有行为。
  static List<String> candidates(String url) {
    final List<String> out = <String>[url];
    void add(String u) {
      if (!out.contains(u)) out.add(u);
    }

    final jsdelivr = _jsdelivr.firstMatch(url);
    if (jsdelivr != null) {
      final String raw = '$_rawPrefix${jsdelivr[1]}/${jsdelivr[2]}/'
          '${jsdelivr[3]}/${jsdelivr[4]}';
      add(raw);
      add('$_mirrorPrefix$raw');
      return out;
    }

    final raw = _raw.firstMatch(url);
    if (raw != null) {
      add('$_mirrorPrefix$url');
      add('https://cdn.jsdelivr.net/gh/${raw[1]}/${raw[2]}@${raw[3]}/${raw[4]}');
    }
    return out;
  }

  /// 拉取文本（JSON / HTML 通用），候选间阶梯竞速，全部失败才抛错。
  static Future<CdnFetchResult> fetch(String url) {
    final List<String> urls = candidates(url);
    // 同一次拉取的多个候选共用一个客户端（复用连接池 / 代理配置）。
    final Dio dio = _newDio();
    final Completer<CdnFetchResult> completer = Completer<CdnFetchResult>();
    var pending = urls.length;

    void settle() {
      pending--;
      if (pending == 0 && !completer.isCompleted) {
        completer.completeError(StateError('所有候选地址均不可用：$url'));
      }
    }

    for (var i = 0; i < urls.length; i++) {
      final String candidate = urls[i];
      unawaited(() async {
        if (i > 0) {
          await Future<void>.delayed(Duration(milliseconds: _staggerMs * i));
          if (completer.isCompleted) {
            settle();
            return;
          }
        }
        try {
          final Response<String> resp = await dio.get<String>(candidate);
          final String? data = resp.data;
          if (data == null || data.trim().isEmpty) {
            throw StateError('empty body');
          }
          if (!completer.isCompleted) {
            completer.complete((text: data, url: candidate));
          }
        } on Object {
          // 单候选失败：等其余候选，或由 settle 判定整体失败。
        } finally {
          settle();
        }
      }());
    }

    final Timer timer = Timer(_hardTimeout, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('拉取超时：$url'));
      }
    });
    return completer.future.whenComplete(timer.cancel);
  }
}
