/// 漫画页翻译控制器（漫画翻译功能的大脑）。
///
/// 职责：
/// - 持有「翻译开关」与逐页翻译状态（按图片 URL 索引），翻页时由阅读器
/// 调用 [ensureTranslated] 触发当前页翻译；
/// - 图片获取：本地路径直接读文件；网络 URL 走 [NexImageCacheManager]
/// （命中磁盘缓存零流量，未命中带防盗链 headers 下载）；
/// - 图片预处理：超过上限时经 [AiImageResizer] 下采样再编码，控制请求体积；
/// - 调用 [ComicTranslationPipeline]（单次视觉翻译 + 校验纠错 + 两阶段兜底），
/// 结果经 [ComicTranslationManager] 持久化（`comicId|章|页|语言` 键）；
/// - 部分翻译先展示可用条目，延迟后台补译（跨会话最多 2 次）；
/// - **并发信号量**：快速连续翻页时网络请求并发上限 2，防止瞬时打爆
/// 接口限流；缓存命中路径不占槽位；
/// - 错误归一化：catch 处统一转 [TranslationException] 可读文案，
/// 原始异常细节仅入 [AppLog]。
///
/// 状态以 [Listenable]（ChangeNotifier）暴露，[MangaPageImage] 内嵌的
/// 覆盖层监听后按千分比坐标把译文渲染到原图对应位置上。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Size;
// NexImageCacheManager 复用阅读器同款图片磁盘缓存（同 URL 不重复下载）。
import 'package:nexhub/core/network/dio_image_file_service.dart';

import '../../../core/ai/glossary_manager.dart';
import '../../../core/ai/image_resizer.dart';
import '../../../core/ai/prompt_builder.dart';
import '../../../core/ai/translation_exception.dart';
import '../../../core/ai/translation_options_store.dart';
import '../../../core/ai/vision_translation_client.dart';
import '../../../core/comic/comic_translation_manager.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/scraper/http_fetcher.dart';
import '../../../core/utils/app_log.dart';
import '../../novel/domain/novel_summary_service.dart';
import '../../novel/domain/novel_summary_settings.dart';
import '../domain/comic_context_builder.dart';
import '../domain/comic_translation_pipeline.dart';

/// 单页翻译状态。
enum ComicPageTranslationStatus { idle, loading, done, error }

class ComicPageTranslationState {
  final ComicPageTranslationStatus status;
  final ComicPageTranslation? data;

  /// 图片自然尺寸（像素）：OCR 解码 / 缓存命中后的微缩解码获得，
  /// 覆盖层据此把千分比坐标映射到实际显示矩形。
  final Size naturalSize;
  final String? error;

  const ComicPageTranslationState({
    this.status = ComicPageTranslationStatus.idle,
    this.data,
    this.naturalSize = Size.zero,
    this.error,
  });

  ComicPageTranslationState copyWith({
    ComicPageTranslationStatus? status,
    ComicPageTranslation? data,
    Size? naturalSize,
    String? error,
  }) =>
      ComicPageTranslationState(
        status: status ?? this.status,
        data: data ?? this.data,
        naturalSize: naturalSize ?? this.naturalSize,
        error: error,
      );
}

class ComicTranslationController extends ChangeNotifier {
  ComicTranslationController({
    required this.comicId,
    PluginConfig? source,
    ComicTranslationManager? manager,
    VisionTranslationClient? client,
    ComicTranslationPipeline? pipeline,
    GlossaryManager? glossary,
    TranslationOptionsStore? options,
  })  : _source = source,
        _manager = manager ?? ComicTranslationManager(),
        _pipeline = pipeline ?? ComicTranslationPipeline(client: client),
        _glossary = glossary ?? GlossaryManager(),
        _options = options ?? TranslationOptionsStore();

  /// 请求图片长边上限（像素）：视觉模型对超大图会截断细节，
  /// 长边压到 1600 在识别精度与请求体积（token / 流量）间取得平衡。
  static const int _kMaxSide = 1600;

  /// 原始字节直接发送的上限：超过才走解码下采样（绝大多数漫画页 < 4MB）。
  static const int _kDirectSendLimitBytes = 6 * 1024 * 1024;

  /// 全局并发上限：快速连续翻页时在途视觉请求最多 2 个，
  /// 避免瞬时并发触发上游 429/限流。缓存命中不占槽位。
  static const int _kMaxConcurrent = 2;

  final String comicId;
  final ComicTranslationManager _manager;
  final ComicTranslationPipeline _pipeline;
  final GlossaryManager _glossary;
  final TranslationOptionsStore _options;

  /// 术语表生效条目（会话内加载一次；语言回落主目标语言）。
  List<GlossaryEntry>? _glossaryEntries;

  /// 网络图下载防盗链 headers 所需的源配置（阅读器异步加载源后补传）。
  PluginConfig? get source => _source;
  PluginConfig? _source;

  /// 阅读器加载到源配置后更新（initState 时源尚未就绪）。
  void updateSource(PluginConfig? s) => _source = s;

  /// 当前章节页 URL（阅读器翻章时更新）：OCR 拉图 Referer 按浏览器
  /// referrer-policy 从它推导（部分站点按图片↔章节页绑定校验 Referer）。
  String? _chapterPageUrl;

  /// 阅读器翻章时同步当前章节页 URL（best-effort，空值回退源级 Referer）。
  void updateChapterPageUrl(String? url) => _chapterPageUrl = url;

  bool _enabled = false;
  bool _langLoaded = false;
  String _targetLang = 'zh';

  /// 按图片 URL 索引的翻译状态（覆盖层据此渲染）。
  final Map<String, ComicPageTranslationState> _states =
      <String, ComicPageTranslationState>{};

  /// 进行中的请求（防同页重复触发）。
  final Set<String> _inFlight = <String>{};

  /// 部分结果后台补译去重（同一页同时只跑一个补译）。
  final Set<String> _partialRetryInFlight = <String>{};

  /// 部分结果后台补译上限（跨会话累计，存于缓存 retries 字段）。
  static const int _maxPartialRetries = 2;

  /// 后台补译定时器（dispose 时统一取消，避免回调打到已销毁的控制器）。
  final Set<Timer> _timers = <Timer>{};
  bool _disposed = false;

  // ── 并发信号量──
  int _active = 0;
  final List<void Function()> _waiters = <void Function()>[];

  @override
  void dispose() {
    _disposed = true;
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  bool get enabled => _enabled;

  ComicPageTranslationState stateFor(String url) =>
      _states[url] ?? const ComicPageTranslationState();

  /// 轻量信号量：并发达到 [_kMaxConcurrent] 时排队等待，槽位释放按
  /// 先到先得唤醒。仅网络请求段使用；缓存命中不经过此门。
  Future<T> _withSlot<T>(Future<T> Function() task) async {
    while (_active >= _kMaxConcurrent) {
      final completer = Completer<void>();
      _waiters.add(completer.complete);
      await completer.future;
    }
    _active++;
    try {
      return await task();
    } finally {
      _active--;
      if (_waiters.isNotEmpty) _waiters.removeAt(0)();
    }
  }

  /// 开关翻译。开启时读取目标语言配置（一次），由阅读器随后对当前页
  /// 调用 [ensureTranslated]。
  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    if (value && !_langLoaded) {
      _targetLang = await NovelSummarySettings.instance
          .getComicTranslationTargetLanguage();
      _langLoaded = true;
    }
    notifyListeners();
  }

  /// 确保某页已翻译：缓存命中直接回填状态（不占并发槽位）；否则经
  /// 信号量排队发起 OCR+翻译。
  Future<void> ensureTranslated(
    String url, {
    required String chapterKey,
    required int pageIndex,
    bool force = false,
  }) async {
    if (!_enabled || url.isEmpty) return;
    if (!_langLoaded) {
      // 开关与翻页可能同时触发；先确定目标语言，避免用默认值查错缓存。
      _targetLang = await NovelSummarySettings.instance
          .getComicTranslationTargetLanguage();
      _langLoaded = true;
    }
    final existing = _states[url];
    if (!force &&
        existing != null &&
        (existing.status == ComicPageTranslationStatus.loading ||
            existing.status == ComicPageTranslationStatus.done)) {
      return;
    }
    if (_inFlight.contains(url)) return;
    _inFlight.add(url);
    _states[url] =
        (existing ?? const ComicPageTranslationState()).copyWith(
      status: ComicPageTranslationStatus.loading,
    );
    notifyListeners();
    try {
      await _manager.init();
      if (!force) {
        final cached = await _manager.load(
          comicId: comicId,
          chapterKey: chapterKey,
          pageIndex: pageIndex,
          lang: _targetLang,
          expectedImageUrl: url,
        );
        if (cached != null) {
          _states[url] = ComicPageTranslationState(
            status: ComicPageTranslationStatus.done,
            data: cached,
            naturalSize: existing?.naturalSize ?? Size.zero,
          );
          // 空页缓存无解码机会，仍需补自然尺寸（供覆盖层坐标映射）。
          if (_states[url]!.naturalSize == Size.zero) {
            unawaited(_fillNaturalSize(url));
          }
          if (cached.status == ComicTranslationStatus.partial) {
            _schedulePartialRetry(url, chapterKey, pageIndex, cached);
          }
          return;
        }
      }
      // 网络请求段受并发信号量约束。
      final result =
          await _withSlot(() => _translatePage(url, chapterKey, pageIndex));
      final translation = ComicPageTranslation(
        imageUrl: url,
        lang: _targetLang,
        segments: result.segments,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        status: result.status,
      );
      _states[url] = ComicPageTranslationState(
        status: ComicPageTranslationStatus.done,
        data: translation,
        naturalSize: result.naturalSize,
      );
      // 空结果（无文字页）同样缓存，避免翻回来重复请求。
      await _saveTranslation(chapterKey, pageIndex, translation);
      if (result.status == ComicTranslationStatus.partial) {
        _schedulePartialRetry(url, chapterKey, pageIndex, translation);
      }
    } on Object catch (e) {
      // 用户可见文案归一化，原始细节仅入日志。
      AppLog.instance.w('[漫画翻译] 页面翻译失败 url=$url: $e');
      _states[url] = (_states[url] ?? const ComicPageTranslationState())
          .copyWith(
        status: ComicPageTranslationStatus.error,
        error: TranslationException.from(e).message,
      );
    } finally {
      _inFlight.remove(url);
      notifyListeners();
    }
  }

  Future<void> _saveTranslation(
    String chapterKey,
    int pageIndex,
    ComicPageTranslation translation,
  ) async {
    try {
      await _manager.save(
        comicId: comicId,
        chapterKey: chapterKey,
        pageIndex: pageIndex,
        lang: _targetLang,
        translation: translation,
      );
      // 保存后惰性裁剪缓存容量。
      unawaited(_manager.trimToLimit(ComicTranslationManager.defaultMaxEntries));
    } on Object {
      // 缓存写失败不影响显示。
    }
  }

  /// 缓存命中路径补自然尺寸（微缩解码极廉价；失败静默保持 zero）。
  Future<void> _fillNaturalSize(String url) async {
    Size size = Size.zero;
    try {
      size = await AiImageResizer.decodeSize(await _loadImageBytes(url));
    } on Object {
      return;
    }
    if (size == Size.zero) return;
    final s = _states[url];
    if (s == null || s.status != ComicPageTranslationStatus.done) return;
    _states[url] = s.copyWith(naturalSize: size);
    notifyListeners();
  }

  /// 重试某页（错误态/部分结果覆盖层的重试按钮）：跳过缓存强制重新请求。
  Future<void> retry(
    String url, {
    required String chapterKey,
    required int pageIndex,
  }) async {
    _states.remove(url);
    notifyListeners();
    await ensureTranslated(
      url,
      chapterKey: chapterKey,
      pageIndex: pageIndex,
      force: true,
    );
  }

  /// 部分结果后台补译：先让当前页展示已译部分，延迟 4s 再整页重试一次。
  ///
  /// 只有译文条数确实增加才覆盖当前状态；无论是否变好都累计 retries
  /// （持久化到缓存，跨会话封顶 [_maxPartialRetries]）。
  void _schedulePartialRetry(
    String url,
    String chapterKey,
    int pageIndex,
    ComicPageTranslation current,
  ) {
    if (_disposed ||
        current.retries >= _maxPartialRetries ||
        !_enabled ||
        _partialRetryInFlight.contains(url)) {
      return;
    }
    _partialRetryInFlight.add(url);
    late final Timer timer;
    timer = Timer(const Duration(seconds: 4), () async {
      _timers.remove(timer);
      ComicPageTranslation? next;
      try {
        if (!_enabled) return;
        final state = _states[url];
        if (state == null ||
            state.status != ComicPageTranslationStatus.done ||
            !identical(state.data, current)) {
          return;
        }
        final result = await _withSlot(
          () => _translatePage(url, chapterKey, pageIndex),
        );
        final retries = current.retries + 1;
        final improved = result.segments
                .where((s) => s.translation.trim().isNotEmpty)
                .length >
            current.translatedCount;
        if (!improved) {
          // 没变好：只记录次数并停止本轮，避免同一页反复烧请求。
          await _saveTranslation(
            chapterKey,
            pageIndex,
            _copyWithRetries(current, retries),
          );
          return;
        }
        final updated = ComicPageTranslation(
          imageUrl: url,
          lang: _targetLang,
          segments: result.segments,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          status: result.status,
          retries: retries,
        );
        final latest = _states[url];
        if (latest == null ||
            latest.status != ComicPageTranslationStatus.done ||
            !identical(latest.data, current)) {
          return;
        }
        _states[url] = latest.copyWith(data: updated);
        notifyListeners();
        await _saveTranslation(chapterKey, pageIndex, updated);
        if (updated.status == ComicTranslationStatus.partial) {
          next = updated;
        }
      } on Object catch (e) {
        AppLog.instance.w('[漫画翻译] 部分结果补译失败 url=$url: $e');
      } finally {
        _partialRetryInFlight.remove(url);
      }
      // 在去重集合释放后再排下一次，否则会被自身拦截。
      if (next != null) {
        _schedulePartialRetry(url, chapterKey, pageIndex, next);
      }
    });
    _timers.add(timer);
  }

  static ComicPageTranslation _copyWithRetries(
    ComicPageTranslation t,
    int retries,
  ) =>
      ComicPageTranslation(
        imageUrl: t.imageUrl,
        lang: t.lang,
        segments: t.segments,
        updatedAt: t.updatedAt,
        version: t.version,
        status: t.status,
        retries: retries,
      );

  Future<({
    List<VisionTextSegment> segments,
    Size naturalSize,
    ComicTranslationStatus status
  })> _translatePage(String url, String chapterKey, int pageIndex) async {
    final settings = NovelSummarySettings.instance;
    final List<NovelSummaryConfig> endpointCfgs =
        await settings.getComicTranslationEndpoints();
    final endpoints = <AiEndpointConfig>[
      for (final c in endpointCfgs)
        if (c.baseUrl.trim().isNotEmpty)
          AiEndpointConfig(baseUrl: c.baseUrl, apiKey: c.apiKey, model: c.model),
    ];
    if (endpoints.isEmpty) {
      throw const TranslationException('未配置 AI 接口：请先在 设置 → AI 配置 中填写'
          '通用接口或漫画翻译专用接口（需支持视觉的模型）');
    }
    final lang = _langLoaded
        ? _targetLang
        : await settings.getComicTranslationTargetLanguage();
    _targetLang = lang;
    _langLoaded = true;

    // 术语表（作品级回落全局；语言回落主目标语言）+ 风格预设。
    try {
      final master =
          await settings.getTranslationTargetLanguage();
      _glossaryEntries ??= await _glossary.effectiveEntriesWithFallback(
          comicId, lang, master);
    } on Object {
      _glossaryEntries ??= const <GlossaryEntry>[];
    }
    final glossary = _glossaryEntries ?? const <GlossaryEntry>[];
    String style = TranslationStyle.standard.name;
    try {
      style = (await _options.effectiveStyle(comicId)).name;
    } on Object {
      // 风格读取失败按标准风格。
    }
    final contextPairs = await ComicContextBuilder.collect(
      manager: _manager,
      comicId: comicId,
      chapterKey: chapterKey,
      pageIndex: pageIndex,
      lang: lang,
    );

    final bytes = await _loadImageBytes(url);
    final natural = await AiImageResizer.decodeSize(bytes);
    Uint8List sendBytes = bytes;
    String mime = _guessMime(url);
    if (bytes.lengthInBytes > _kDirectSendLimitBytes) {
      // 超大图：下采样重编码（codec 释放已收口在 AiImageResizer）。
      final Uint8List? resized =
          await AiImageResizer.resizeToLimit(bytes, maxSide: _kMaxSide);
      if (resized != null) {
        sendBytes = resized;
        mime = 'image/png';
      }
    }
    final outcome = await _pipeline.translatePage(ComicTranslationRequest(
      endpoints: endpoints,
      imageBytes: sendBytes,
      mimeType: mime,
      targetLang: lang,
      glossary: glossary,
      style: TranslationStyle.fromStorage(style),
      contextPairs: contextPairs,
    ));
    final segments = outcome.segments;
    // 术语冲突检测（仅日志，不阻断显示）。
    if (glossary.isNotEmpty && segments.isNotEmpty) {
      try {
        for (final w in GlossaryManager.detectConflicts(
          glossary,
          <String>[for (final s in segments) s.text],
          <String>[for (final s in segments) s.translation],
        )) {
          AppLog.instance.w('[漫画翻译][术语冲突] $w');
        }
      } on Object {
        // 检测失败不影响主流程。
      }
    }
    return (
      segments: segments,
      naturalSize: natural,
      status: outcome.status,
    );
  }

  /// 取图片字节：网络 URL 走缓存管理器（含防盗链 headers），本地路径直读。
  Future<Uint8List> _loadImageBytes(String url) async {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      // 与 SourceImage 同一缓存（nexCachedImageData）：DefaultCacheManager
      // 的 HttpClient 启动早期创建后不随网络档案更新（僵化直连）。
      final File file = await NexImageCacheManager.instance.getSingleFile(
        url,
        headers: _buildHeaders(url),
      );
      return file.readAsBytes();
    }
    final File f = File(url);
    return f.readAsBytes();
  }

  /// 与 [SourceImage] 一致的防盗链 headers（antiHotlinking → site →
  /// Referer / UA / Cookie），保证 OCR 拉图与阅读器显示同一指纹。
  Map<String, String>? _buildHeaders(String url) {
    final ah = source?.antiHotlinking;
    final site = source?.site;
    final ahHeaders = ah?.headers;
    final siteHeaders = site?.headers;
    // 书源（规则引擎）源只带源声明的头：对齐 legado 取图的
    // AnalyzeUrl(src, source = bookSource) 语义，不做章节页 Referer 推导。
    final bool declaredOnly = source?.isShuyuanSource ?? false;
    final referer = declaredOnly
        ? ah?.referer
        : HttpFetcher.refererForSubresource(_chapterPageUrl, url) ??
            ah?.referer;
    final siteUa = site?.userAgent;
    final ua = (siteUa != null && siteUa.isNotEmpty)
        ? siteUa
        : HttpFetcher.instance.userAgentForUrl(url);
    final cookies = site?.cookies;
    final bool hasFields =
        (siteHeaders != null && siteHeaders.isNotEmpty) ||
            (ahHeaders != null && ahHeaders.isNotEmpty) ||
            (referer != null && referer.isNotEmpty) ||
            ua.isNotEmpty ||
            (cookies != null && cookies.isNotEmpty);
    if (!hasFields) return null;
    final Map<String, String> m = <String, String>{};
    if (ahHeaders != null) m.addAll(ahHeaders);
    if (siteHeaders != null) m.addAll(siteHeaders);
    if (referer != null && referer.isNotEmpty) m['Referer'] = referer;
    if (ua.isNotEmpty) m['User-Agent'] = ua;
    if (cookies != null && cookies.isNotEmpty) m['Cookie'] = cookies;
    return m;
  }

  static String _guessMime(String url) {
    final lower = url.toLowerCase().split('?').first;
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }
}
