import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../models/plugin_config.dart';
import '../network/dio_image_file_service.dart';
import '../network/network_config_service.dart';
import '../theme/app_tokens.dart';
import '../scraper/http_fetcher.dart';
import '../local/local_content_manager.dart' show isDocUri;
import '../local/saf_bridge.dart' show resolveSafUri;

/// 统一源图片 widget：按源配置注入防盗链 headers，带缓存、失败重试、圆角、Hero。
///
/// 替代裸 `Image.network`：漫画源 / 影视源封面常因防盗链返回 403，必须携带
/// `Referer` / `User-Agent` / `Cookie` 等头才能正常加载（见 PluginConfig.antiHotlinking
/// 与 PluginConfig.site）。本地文件路径走 [Image.file]。
class SourceImage extends StatelessWidget {
  final String? url;
  final PluginConfig? source;
  final double? width;
  final double? height;
  final BoxFit fit;
  final String? heroTag;
  final double? radius;
  final Widget? placeholder;

  /// 加载失败时的自定义替代视图（如 favicon 回退通用图标）。
  /// 非 null 时替代内置的 broken-image + 重试 UI。
  final Widget? errorWidget;
  final bool enableRetry;

  /// 解码位图宽上限（像素， 资源/内存）：非 null 时按比例下采样解码
  /// （`ResizeImage` 语义，不放大小图）。条漫连续模式传入
  /// `min(2560, 屏幕物理像素 × 2)` 以限制长条漫的解码内存；null = 不限幅。
  final int? decodeCapWidthPx;

  /// 显式指定的 Referer（优先于源配置里的 [AntiHotlinkingConfig.referer]）。
  ///
  /// 用于「图片所在页面已知」的场景：RSS 正文内嵌图、文章详情页封面等。
  /// 这类图片的正确 Referer 是**文章页地址**，而不是图片自身域名——部分站点
  /// 按 Referer 校验，只带图片自身 origin 会被判为盗链返回 403。
  final String? refererOverride;

  /// 图片成功解码后回调（一次）。条漫阅读器借此在图片加载完成后移除占位高度，
  /// 避免 ConstrainedBox(minHeight) 在真实图高偏小时残留空白带（割裂感）。
  final VoidCallback? onLoadComplete;

  /// 图片自然尺寸回调（一次）：解码完成后回传原始像素宽高。
  /// 条漫阅读器借此缓存「真实图片高度」，未加载项也能用真实高度估算占位
  /// （体验项：占位高 / 纵向平移夹取均基于真实高度，经验值仅兜底）。
  final void Function(double width, double height)? onImageInfo;

  /// 解码完成回调（一次）：回传**所有权归调用方**的 [ui.Image] 克隆。
  ///
  /// 供漫画超分路径复用「SourceImage 已经解码好的同一张位图」——超分 shader
  /// 只能画已解码图像，若自己另起 provider 会绕过 [NexImageCacheManager] 磁盘
  /// 缓存与防盗链/重试逻辑（并可能与页面请求指纹不一致）。调用方负责在用完
  /// 或替换时 dispose 该克隆（`ImageInfo.dispose()` 只减引用计数，不会提前
  /// 释放仍被 Flutter 图片缓存持有的位图）。
  final void Function(ui.Image image)? onImageDecoded;

  const SourceImage({
    super.key,
    required this.url,
    this.source,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.heroTag,
    this.radius,
    this.placeholder,
    this.errorWidget,
    this.enableRetry = true,
    this.decodeCapWidthPx,
    this.refererOverride,
    this.onLoadComplete,
    this.onImageInfo,
    this.onImageDecoded,
  });

  bool get _isHttp =>
      url != null &&
      (url!.startsWith('http://') || url!.startsWith('https://'));

  /// 合并防盗链 headers：antiHotlinking.headers 起手 → site.headers →
  /// Referer / User-Agent / Cookie 字段（后者优先覆盖同名键）。
  ///
  /// 静态版：[resolveSourceImageBytes]（动态效果取字节）与 widget 共用，
  /// 保证两边请求指纹完全一致（缓存命中 / 防盗链行为不因入口不同而分叉）。
  static Map<String, String>? buildHeaders({
    required String url,
    PluginConfig? source,
    String? refererOverride,
  }) {
    final ah = source?.antiHotlinking;
    final site = source?.site;
    final ahHeaders = ah?.headers;
    final siteHeaders = site?.headers;
    final referer = ah?.referer;
    // UA 兜底：部分 CDN（如某源家族 CDN 域）无 UA 直接 403，而部分源
    // 的 site.userAgent 未配置。此时回退到 HttpFetcher 的浏览器 UA，保证
    // 图片请求与页面/API 请求的指纹一致（不写死任何站点）。
    final String? siteUa = site?.userAgent;
    final ua = (siteUa != null && siteUa.isNotEmpty)
        ? siteUa
        : HttpFetcher.instance.userAgentForUrl(url);
    final cookies = site?.cookies;
    final hasFields = (siteHeaders != null && siteHeaders.isNotEmpty) ||
        (ahHeaders != null && ahHeaders.isNotEmpty) ||
        (referer != null && referer.isNotEmpty) ||
        (refererOverride != null && refererOverride.isNotEmpty) ||
        (ua != null && ua.isNotEmpty) ||
        (cookies != null && cookies.isNotEmpty);
    if (!hasFields) return null;
    final Map<String, String> m = <String, String>{};
    if (ahHeaders != null) m.addAll(ahHeaders);
    if (siteHeaders != null) m.addAll(siteHeaders);
    if (referer != null && referer.isNotEmpty) {
      m['Referer'] = referer;
    }
    // 调用方显式指定的 Referer 覆盖源配置（文章页地址比图片域名更准确）。
    if (refererOverride != null && refererOverride.isNotEmpty) {
      m['Referer'] = refererOverride;
    }
    if (ua != null && ua.isNotEmpty) {
      m['User-Agent'] = ua;
    }
    if (cookies != null && cookies.isNotEmpty) {
      m['Cookie'] = cookies;
    }
    // 注入验证回灌的会话 Cookie：_guard 等反爬系统对图片同样校验会话，
    // 缺 Cookie 时封面图请求会被拦（403/空）导致「没有封面」。HttpFetcher
    // 在 WebView 过验证后已写入共享 jar，此处按域名取出回带。
    final synced = HttpFetcher.instance.cookieHeaderForUrl(url);
    if (synced != null && synced.isNotEmpty) {
      final existing = m['Cookie'];
      m['Cookie'] = (existing != null && existing.isNotEmpty)
          ? '$existing; $synced'
          : synced;
    }
    // 图片请求头修正：源 site.headers 常带 `Accept: application/json`（用于
    // API），漏到图片请求会让部分 CDN 按「伪装的图片请求」拒绝；改为图片专用
    // Accept。注意不声明 image/avif：Flutter 内置解码器不支持 AVIF，协商型
    // CDN 会按 Accept 返回 AVIF → 解码失败（与下载器/HttpFetcher 图片头对齐）。
    // 图片请求的 Accept 一律为图片形态：site.headers 若带页面级 Accept
    // （text/html 等）会构成「页面头 + 图片 URL」组合，部分 CDN 的 WAF 按
    // 该指纹判盗链/机器人直接 403（签名图片 CDN 实测）。
    m['Accept'] = 'image/webp,image/apng,image/jpeg,image/png,image/*,*/*;q=0.8';
    // 不做 Referer 兜底注入：签名 CDN（secure= 参数）按「无 Referer」设计，
    // 带 Referer 反而 403（签名图片 CDN 实测：无 Referer 200 / 带 Referer 403）。
    // 防盗链 Referer 由 antiHotlinking.referer / refererOverride 显式声明。
    return m;
  }

  Map<String, String>? _buildHeaders() => buildHeaders(
        url: url!,
        source: source,
        refererOverride: refererOverride,
      );

  Widget _defaultPlaceholder(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      color: scheme.surfaceContainerHighest,
      child: Icon(
        Icons.image_rounded,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? u = url;
    final double? r = radius;
    // 监听 Cookie 版本流：验证回灌 Cookie 后通知重取之前失败的封面。
    // 注意：版本自增只影响「加载失败过」的图片（见 _RetryableNetworkImageState
    // 的 _everFailed），已成功加载的图片不受 Cookie 变化影响——部分站点
    // （负载均衡粘滞 Cookie 每次响应轮换）会频繁自增版本，若全量重建缓存键
    // 会导致「图片不停刷新」。
    final Widget clipped = StreamBuilder<int>(
      stream: HttpFetcher.instance.cookieVersionStream,
      initialData: HttpFetcher.instance.cookieVersion,
      builder: (ctx, snap) {
        final int version = snap.data ?? HttpFetcher.instance.cookieVersion;
        final Widget core;
        if (u == null || u.isEmpty) {
          core = placeholder ?? _defaultPlaceholder(context);
        } else if (_isHttp) {
          core = _RetryableNetworkImage(
            url: u,
            headers: _buildHeaders(),
            source: source,
            cookieVersion: version,
            width: width,
            height: height,
            fit: fit,
            decodeCapWidthPx: decodeCapWidthPx,
            placeholder: placeholder ?? _defaultPlaceholder(context),
            errorWidget: errorWidget,
            enableRetry: enableRetry,
            onLoadComplete: onLoadComplete,
            onImageInfo: onImageInfo,
            onImageDecoded: onImageDecoded,
          );
        } else {
          core = _SafOrLocalImage(
            uriOrPath: u,
            width: width,
            height: height,
            fit: fit,
            decodeCapWidthPx: decodeCapWidthPx,
            placeholder: placeholder ?? _defaultPlaceholder(context),
            onLoadComplete: onLoadComplete,
            onImageInfo: onImageInfo,
            onImageDecoded: onImageDecoded,
          );
        }
        return r == null
            ? core
            : ClipRRect(borderRadius: BorderRadius.circular(r), child: core);
      },
    );
    return heroTag == null ? clipped : Hero(tag: heroTag!, child: clipped);
  }
}

/// 带指数退避重试的网络图片（最多 3 次：1s / 2s / 4s）。
class _RetryableNetworkImage extends StatefulWidget {
  final String url;
  final Map<String, String>? headers;
  final PluginConfig? source;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget placeholder;
  final Widget? errorWidget;
  final bool enableRetry;
  final int cookieVersion;
  final int? decodeCapWidthPx;
  final VoidCallback? onLoadComplete;
  final void Function(double width, double height)? onImageInfo;
  final void Function(ui.Image image)? onImageDecoded;

  const _RetryableNetworkImage({
    required this.url,
    this.headers,
    this.source,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    required this.placeholder,
    this.errorWidget,
    this.enableRetry = true,
    this.cookieVersion = 0,
    this.decodeCapWidthPx,
    this.onLoadComplete,
    this.onImageInfo,
    this.onImageDecoded,
  });

  @override
  State<_RetryableNetworkImage> createState() => _RetryableNetworkImageState();
}

class _RetryableNetworkImageState extends State<_RetryableNetworkImage> {
  static const int _maxRetries = 3;
  static const List<Duration> _backoff = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  int _retryKey = 0;
  int _retryCount = 0;
  bool _retrying = false;
  Timer? _timer;
  bool _notified = false;

  /// 是否经历过一次加载失败。
  ///
  /// Cookie 版本号（[widget.cookieVersion]）**只对失败过的图片生效**：
  /// 版本自增仅用于「验证回灌 Cookie 后重取之前因缺 Cookie 而失败的图」，
  /// 加载成功的图永不因 Cookie 变化重下。否则部分站点（负载均衡会话粘滞
  /// Cookie 如 SERVERID 每次响应轮换节点）会让每次页面请求都自增版本，
  /// 触发全部已加载图片换 cacheKey 重下 → 「图片不停刷新」死循环。
  bool _everFailed = false;

  /// 实际加载的 URL：`.avif` 加载/解码失败时自动降级为 `.webp` 变体重试。
  ///
  /// 背景：Flutter 内置解码器不支持 AVIF（仅 Android 12+ 走系统解码器），
  /// Windows/桌面端对 .avif 图「HTTP 200 下载成功 → Invalid image data 解码
  /// 失败 → 显示重试」。部分图床按扩展名钉死返回 AVIF（Accept 协商无效），
  /// 但同一资源路径存在 `.webp` 变体。故加载失败且 URL 以 .avif 结尾时，
  /// 自动改用 .webp 重取一次：安卓上 avif 能正常解码（不触发本回退，保持
  /// 更优压缩率）；webp 变体不存在的站点则与原先一样停在错误态（无回归）。
  late String _effectiveUrl = widget.url;
  bool _avifFallbackTried = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _RetryableNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _effectiveUrl = widget.url;
      _avifFallbackTried = false;
      _retryCount = 0;
      _retrying = false;
      _everFailed = false;
    }
  }

  /// `.avif`（可带 query）→ `.webp` 变体；非 avif URL 返回 null。
  static String? _avifToWebp(String url) {
    if (!RegExp(r'\.avif(\?.*)?$', caseSensitive: false).hasMatch(url)) {
      return null;
    }
    return url.replaceFirstMapped(
      RegExp(r'\.avif(\?.*)?$', caseSensitive: false),
      (Match m) => '.webp${m.group(1) ?? ''}',
    );
  }

  /// 加载/解码失败时尝试一次 avif→webp 降级（errorWidget 在 build 期回调，
  /// 用 postFrame 推迟 setState）。
  void _maybeFallbackAvif() {
    if (_avifFallbackTried) return;
    final String? swapped = _avifToWebp(_effectiveUrl);
    if (swapped == null) return;
    _avifFallbackTried = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _effectiveUrl = swapped;
        _retryCount = 0;
        _retryKey += 1;
      });
    });
  }

  void _retry() {
    if (!widget.enableRetry || _retrying || _retryCount >= _maxRetries) return;
    setState(() => _retrying = true);
    _timer = Timer(_backoff[_retryCount], () {
      if (!mounted) return;
      setState(() {
        _retrying = false;
        _retryCount += 1;
        _retryKey += 1;
      });
    });
  }

  // 图片成功解码后通知一次（帧后触发，避免在 build 期 setState）。
  void _notifyLoaded() {
    if (_notified) return;
    _notified = true;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => widget.onLoadComplete?.call());
  }

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      // key 不含 cookieVersion：版本自增仅应改变缓存键触发失败图重取，
      // 不应重挂整个 widget 状态（会丢 _everFailed/_retryCount 记录）。
      key: ValueKey<String>('$_effectiveUrl-$_retryKey'),
      imageUrl: _effectiveUrl,
      httpHeaders: widget.headers,
      // 统一走 Dio 网络层下载（NexImageCacheManager）：默认 HttpFileService 的
      // HttpClient 在启动早期创建后终身僵化（代理/DNS 档案加载前直连），代理
      // 环境下「文字正常、图片全挂」即源于此。
      cacheManager: NexImageCacheManager.forSource(widget.source),
      // 仅失败过的图把版本并入缓存键：版本自增 → 新缓存键 → 重取
      // （验证回灌 Cookie 自动刷新失败封面）。成功过的图缓存键恒定，
      // 任何 Cookie 轮换都不再触发已加载图片重下。
      cacheKey: _everFailed
          ? '$_effectiveUrl#v${widget.cookieVersion}'
          : _effectiveUrl,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      memCacheWidth: widget.decodeCapWidthPx,
      placeholder: (c, u) => widget.placeholder,
      errorWidget: (c, u, e) {
        _everFailed = true;
        _notifyLoaded();
        // avif 图在「不支持该格式的平台」上表现为解码失败：自动降级 .webp 重取。
        _maybeFallbackAvif();
        return widget.errorWidget ?? _buildError(context);
      },
      imageBuilder: (ctx, provider) {
        _notifyLoaded();
        // 回传自然尺寸（缓存命中，无重复下载）：供条漫占位/夹取基于真实高度估算。
        final ImageStream stream = provider.resolve(const ImageConfiguration());
        ImageStreamListener? listener;
        listener = ImageStreamListener(
          (ImageInfo info, bool _) {
            widget.onImageInfo?.call(
                info.image.width.toDouble(), info.image.height.toDouble());
            // 超分路径：交出位图的克隆（调用方负责 dispose）。clone 只加引用
            // 计数，不复制像素；不 clone 直接交出去会让 Flutter 图片缓存的
            // 释放与本 widget 的释放互相打架（提前释放 → 用已释放位图绘制）。
            final void Function(ui.Image image)? onDecoded =
                widget.onImageDecoded;
            if (onDecoded != null) {
              try {
                onDecoded(info.image.clone());
              } on Object {
                // 已释放 / 引擎不支持 clone：静默跳过（超分回退普通渲染）。
              }
            }
            stream.removeListener(listener!);
          },
          onError: (Object error, StackTrace? stackTrace) =>
              stream.removeListener(listener!),
        );
        stream.addListener(listener!);
        return Image(
          image: provider,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
        );
      },
    );
  }

  Widget _buildError(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool exhausted = _retryCount >= _maxRetries;
    return Semantics(
      label: l10n.imageLoadFailed,
      child: Container(
        width: widget.width,
        height: widget.height,
        color: scheme.surfaceContainerHighest,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.broken_image_rounded, color: scheme.onSurfaceVariant),
            if (widget.enableRetry) ...<Widget>[
              const SizedBox(height: AppTokens.spaceXs),
              if (_retrying)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.primary,
                  ),
                )
              else if (!exhausted)
                TextButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(l10n.retry),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 本地文件图片：补齐与网络图一致的「解码完成通知（onLoadComplete）」。
///
/// 原因：条漫阅读器对未加载 item 预留 `ConstrainedBox(minHeight: 屏宽×1.5)` 占位，
/// 必须在图片真正解码后移除该约束（令 showRealHeight=true），否则真实图高偏小时
/// 图片下方残留空白带（图片之间的缝隙）。网络图走 [_RetryableNetworkImage] 在
/// imageBuilder 内已通知；本地图此前走裸 `Image.file` 漏掉了通知，导致本地条漫
/// 永久保留占位 → 出现缝隙。此处用 loadingBuilder 在加载完成时（loadingProgress
/// 变 null）触发一次通知，与网络图行为对齐。
class _LocalFileImage extends StatefulWidget {
  final File file;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget placeholder;
  final int? decodeCapWidthPx;
  final VoidCallback? onLoadComplete;
  final void Function(double width, double height)? onImageInfo;
  final void Function(ui.Image image)? onImageDecoded;

  const _LocalFileImage({
    required this.file,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    required this.placeholder,
    this.decodeCapWidthPx,
    this.onLoadComplete,
    this.onImageInfo,
    this.onImageDecoded,
  });

  @override
  State<_LocalFileImage> createState() => _LocalFileImageState();
}

class _LocalFileImageState extends State<_LocalFileImage> {
  bool _notified = false;

  void _notifyLoaded() {
    if (_notified) return;
    _notified = true;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => widget.onLoadComplete?.call());
  }

  @override
  Widget build(BuildContext context) {
    // 解码限幅：非 null 时用 ResizeImage 按比例下采样解码位图
    // （不放大小图），限制长条漫原图的全尺寸解码内存。
    final ImageProvider provider = widget.decodeCapWidthPx == null
        ? FileImage(widget.file)
        : ResizeImage(
            FileImage(widget.file),
            width: widget.decodeCapWidthPx,
            allowUpscaling: false,
          );
    // 自然尺寸：用未限幅的 FileImage 取（ResizeImage 会返回下采样后的尺寸，
    // 不是原始像素），供条漫占位/夹取基于真实高度估算。
    final ImageStream stream = FileImage(widget.file).resolve(
      const ImageConfiguration(),
    );
    ImageStreamListener? listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        widget.onImageInfo
            ?.call(info.image.width.toDouble(), info.image.height.toDouble());
        stream.removeListener(listener!);
      },
      onError: (Object error, StackTrace? stackTrace) =>
          stream.removeListener(listener!),
    );
    stream.addListener(listener!);
    // 超分路径：交出**实际显示用**位图的克隆（限幅后尺寸与显示一致）。
    final void Function(ui.Image image)? onDecoded = widget.onImageDecoded;
    if (onDecoded != null) {
      final ImageStream displayStream =
          provider.resolve(const ImageConfiguration());
      ImageStreamListener? displayListener;
      displayListener = ImageStreamListener(
        (ImageInfo info, bool _) {
          try {
            onDecoded(info.image.clone());
          } on Object {
            // 已释放 / 不支持 clone：静默跳过。
          }
          displayStream.removeListener(displayListener!);
        },
        onError: (Object error, StackTrace? stackTrace) =>
            displayStream.removeListener(displayListener!),
      );
      displayStream.addListener(displayListener);
    }
    return Image(
      image: provider,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorBuilder: (c, e, s) => widget.placeholder,
      frameBuilder: (c, child, frame, wasSynchronouslyLoaded) {
        if (frame != null || wasSynchronouslyLoaded) {
          _notifyLoaded();
          return child;
        }
        return widget.placeholder;
      },
    );
  }
}

/// 本地/SAF 图片：先把 URI 解析为可读的本地文件路径，再交给 [_LocalFileImage]。
///
/// 为什么需要它：本地图片有两种来源——
/// - 真实文件路径（桌面 / 非 SAF）：[Image.file] 直接可读；
/// - Android SAF content://（或下载编码 `<treeUri>␟<rel>`）：[Image.file] 读不了，
/// 必须先经 [resolveSafUri] 落到应用私有缓存。
///
/// 此前 [gatherSafImages] 在「打开漫画」时把整本图片逐张拷贝到缓存，图片多则卡
/// 1~2s。改为**此处逐张懒解析**：只有真正要显示的图片（阅读器当前可见的几张）才
/// 触发拷贝，进入阅读器即刻可见，整本图片数不再影响打开速度。非 SAF 路径直接透传。
class _SafOrLocalImage extends StatefulWidget {
  final String uriOrPath;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget placeholder;
  final int? decodeCapWidthPx;
  final VoidCallback? onLoadComplete;
  final void Function(double width, double height)? onImageInfo;
  final void Function(ui.Image image)? onImageDecoded;

  const _SafOrLocalImage({
    required this.uriOrPath,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    required this.placeholder,
    this.decodeCapWidthPx,
    this.onLoadComplete,
    this.onImageInfo,
    this.onImageDecoded,
  });

  @override
  State<_SafOrLocalImage> createState() => _SafOrLocalImageState();
}

class _SafOrLocalImageState extends State<_SafOrLocalImage> {
  String? _resolved;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    // 非 SAF 路径（真实文件路径）直接可用，无需异步拷贝。
    if (!isDocUri(widget.uriOrPath)) {
      if (mounted) setState(() => _resolved = widget.uriOrPath);
      return;
    }
    try {
      final String r = await resolveSafUri(widget.uriOrPath);
      if (mounted) setState(() => _resolved = r);
    } on Object catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.placeholder;
    if (_resolved == null) return widget.placeholder;
    return _LocalFileImage(
      file: File(_resolved!),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      placeholder: widget.placeholder,
      decodeCapWidthPx: widget.decodeCapWidthPx,
      onLoadComplete: widget.onLoadComplete,
      onImageInfo: widget.onImageInfo,
      onImageDecoded: widget.onImageDecoded,
    );
  }
}

/// 解析源图片原始字节（漫画动态效果引擎的渲染输入）。
///
/// 与 [SourceImage] 完全同链路：
/// - http(s)：经 [NexImageCacheManager] 取文件——阅读器已显示的页面必然
///   已下载过，此处通常直接命中磁盘缓存（零网络请求）；未命中才经同一
///   Dio 网络层下载并落缓存，headers 与 widget 侧同源（[SourceImage.buildHeaders]）；
/// - 本地文件路径：直接读取；
/// - Android SAF content://：经 [resolveSafUri] 解析到可读路径后读取。
///
/// 返回 null = 取字节失败（下载失败 / 文件缺失 / 解析异常），调用方据此
/// 回退为静态显示。仅接受 http/https 与本地路径；其余 scheme 一律 null。
Future<Uint8List?> resolveSourceImageBytes({
  required String url,
  PluginConfig? source,
  String? refererOverride,
}) async {
  try {
    final bool isHttp =
        url.startsWith('http://') || url.startsWith('https://');
    if (isHttp) {
      final headers = SourceImage.buildHeaders(
        url: url,
        source: source,
        refererOverride: refererOverride,
      );
      // 1) 磁盘缓存命中即用（不触网）
      try {
        final cached =
            await NexImageCacheManager.forSource(source).getFileFromCache(url);
        final cachedFile = cached?.file;
        if (cachedFile != null) return await cachedFile.readAsBytes();
      } catch (_) {}
      // 2) 源级网络档案拉字节：与页面请求同路（ECH/mitm/代理/DNS 与源声明一致）。
      //    封面此前走全局档案直连，源级 ECH/代理源会出现「页面 200、封面 403」
      //    的割裂（CDN 按 TLS 指纹/通道拒直连）。
      final net = source != null
          ? NetworkConfigService.instance.effectiveFor(source)
          : NetworkConfigService.instance.globalProfile;
      try {
        final bytes = await HttpFetcher.instance.getBytes(
          url,
          headers: headers,
          net: net,
        );
        if (bytes.isNotEmpty) {
          // 3) 回填磁盘缓存（下轮 getFileFromCache / getSingleFile 命中）
          final lower = url.toLowerCase();
          final ext = lower.contains('.png')
              ? 'png'
              : lower.contains('.webp')
                  ? 'webp'
                  : lower.contains('.gif')
                      ? 'gif'
                      : 'jpg';
          unawaited(NexImageCacheManager.forSource(source).putFile(
            url,
            Uint8List.fromList(bytes),
            fileExtension: ext,
          ));
          return Uint8List.fromList(bytes);
        }
      } catch (_) {}
      // 4) 兜底：缓存管理器原路径（其 FileService 按全局档案发请求）
      final file = await NexImageCacheManager.forSource(source).getSingleFile(
        url,
        headers: headers,
      );
      return await file.readAsBytes();
    }
    if (isDocUri(url)) {
      final path = await resolveSafUri(url);
      final f = File(path);
      return f.existsSync() ? await f.readAsBytes() : null;
    }
    if (url.startsWith('file://')) {
      final f = File(Uri.parse(url).toFilePath());
      return f.existsSync() ? await f.readAsBytes() : null;
    }
    final f = File(url);
    return f.existsSync() ? await f.readAsBytes() : null;
  } on Object {
    return null;
  }
}
