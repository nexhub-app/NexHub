/// 漫画下载处理器（文档 /）。
///
/// 按章节拉取图片 URL → 下载图片字节 → 打包 CBZ（或散图文件夹）。
library;

import 'dart:typed_data';

import '../models/episode.dart';
import '../models/plugin_config.dart';
import '../scraper/http_fetcher.dart';
import '../scraper/media_api_service.dart';
import '../utils/app_log.dart';
import '../utils/image_decrypt_registry.dart';
import 'cbz_builder.dart';
import 'download_file_system.dart';
import 'download_handler.dart';
import 'download_task.dart';

/// 漫画下载处理器。
class ComicDownloadHandler implements DownloadHandler {
  ComicDownloadHandler({
    required this.service,
    required this.fs,
    required this.source,
    required this.comicId,
    required this.chapters,
    this.format = DownloadFormat.cbz,
    this.concurrency = 1,
  });

  final MediaApiService service;
  final DownloadFileSystem fs;
  final PluginConfig source;
  final String comicId;
  final List<Episode> chapters;
  final DownloadFormat format;

  /// 章内图片并行下载数（来自下载设置「线程数」），<=1 退化为顺序下载。
  final int concurrency;

  @override
  Future<DownloadResult> download(
    DownloadTask task, {
    DownloadProgressCallback? onProgress,
    DownloadCancelledCheck? isCancelled,
  }) async {
    // 作品目录（由 DownloadManager 在 task.localPath 约定为该目录）。
    final basePath = task.localPath!;
    await fs.createDir(basePath);

    // 逐话文件/目录路径：下标对齐 chapters（缺则为空串，供上层跳过未下载话）。
    final List<String> chapterPaths = List<String>.filled(chapters.length, '');

    // 单页散图模式（folder / jpg / png）：每话一个子目录，话内图片按线程数并行下载。
    if (format == DownloadFormat.folder ||
        format == DownloadFormat.jpg ||
        format == DownloadFormat.png) {
      final ext = format == DownloadFormat.png ? 'png' : 'jpg';
      var writtenTotal = 0;
      for (var i = 0; i < chapters.length; i++) {
        _throwIfCancelled(isCancelled);
        final ch = chapters[i];
        // 话目录按「全局序号_标题」命名（与视频一致带序号保证分批不互相覆盖，
        // 同时带章节标题便于文件管理器识别；标题为空时退化为纯序号）。
        final seq = ch.number ?? (i + 1);
        final titlePart = _sanitizeTitle(
          task.chapterTitles.length > i ? task.chapterTitles[i] : '',
        );
        final chDir = fs.join(
          basePath,
          titlePart.isEmpty ? _pad(seq) : '${_pad(seq)}_$titlePart',
        );
        await fs.createDir(chDir);
        final images = await service.fetchImages(
          source,
          comicId: comicId,
          chapterId: ch.id,
        );
        final idxList = [for (var j = 0; j < images.length; j++) j];
        var writtenThis = 0;
        await runPool(concurrency, idxList, (j) async {
          final bytes = await _fetchImageBytes(
            images[j],
            referer: _subresourceReferer(ch.url, images[j]),
          );
          if (bytes != null) {
            await fs.writeBytes(
              fs.join(chDir, '${_pad(j + 1)}.$ext'),
              bytes,
            );
            writtenThis++;
          }
        }, onItemDone: (completed, total) {
          onProgress?.call(i, chapters.length, completed / total);
        });
        if (writtenThis > 0) {
          chapterPaths[i] = chDir;
          writtenTotal += writtenThis;
        }
        onProgress?.call(i + 1, chapters.length, 0.0);
      }
      // 一张都没写进 → 明确报错，避免"只有空文件夹"的假完成。
      if (writtenTotal == 0) {
        AppLog.instance.e('[漫画下载失败] ${task.title}: 0 张图写入');
        throw Exception('未能获取到任何图片，可能被源反盗链拦截或图片地址已失效');
      }
      return DownloadResult(workPath: basePath, chapterFilePaths: chapterPaths);
    }

    // CBZ 模式：每话单独打包为一个 .cbz（按序 NNN.cbz），话内图片按线程数并行下载。
    // 取代原先"整本单 cbz"，使同部作品多批下载各话独立、阅读器可逐话打开与切换。
    var wroteChapters = 0;
    for (var i = 0; i < chapters.length; i++) {
      _throwIfCancelled(isCancelled);
      final ch = chapters[i];
      // 话序号取「全局序号」：单话/分批下载时文件名与整本下载一致，
      // 避免第二批下载用本地 1..N 覆盖第一批文件（内容在管理器里对不上）。
      final seq = ch.number ?? (i + 1);
      final images = await service.fetchImages(
        source,
        comicId: comicId,
        chapterId: ch.id,
      );
      final pageBytes = List<Uint8List?>.filled(images.length, null);
      final idxList = [for (var j = 0; j < images.length; j++) j];
      await runPool(concurrency, idxList, (j) async {
        pageBytes[j] = await _fetchImageBytes(
          images[j],
          referer: _subresourceReferer(ch.url, images[j]),
        );
      }, onItemDone: (completed, total) {
        onProgress?.call(i, chapters.length, completed / total);
      });
      final List<CbzPage> chPages = <CbzPage>[];
      for (var j = 0; j < pageBytes.length; j++) {
        final bytes = pageBytes[j];
        if (bytes != null) {
          chPages.add(CbzPage(
            filename: '${_pad(chPages.length + 1)}.jpg',
            bytes: bytes,
          ));
        }
      }
      // 该话无图 → 跳过（不入 chapterPaths），避免"空 cbz"或假完成。
      if (chPages.isEmpty) {
        onProgress?.call(i + 1, chapters.length, 0.0);
        continue;
      }
      // 拦截图检测（沿用原整本逻辑，改为按话）：全部页平均 <20KB 基本可判定
      // 源统一返回了占位图/错误页（如某源曾出现的 ~5.8KB 拦截图）。
      final int total =
          chPages.map((p) => p.bytes.length).fold(0, (a, b) => a + b);
      final double avg = total / chPages.length;
      if (avg < 20 * 1024) {
        final Uint8List first = chPages.first.bytes;
        final String head = first.length >= 4
            ? first
                .take(4)
                .map((x) => x.toRadixString(16).padLeft(2, '0'))
                .join()
            : 'short';
        AppLog.instance.e('[漫画下载失败] ${task.title} 第${i + 1}话: '
            '图片疑似被源拦截 (平均 ${(avg ~/ 1024)}KB/张, 首字节 0x$head)');
        onProgress?.call(i + 1, chapters.length, 0.0);
        continue;
      }
      final cbzBytes = CbzBuilder.build(pages: chPages);
      // 文件名 = 序号_章节标题.cbz（标题含非法文件名字符时清洗）。
      final String titlePart = _sanitizeTitle(task.chapterTitles.length > i
          ? task.chapterTitles[i]
          : '');
      final String cbzName = titlePart.isEmpty
          ? '${_pad(seq)}.cbz'
          : '${_pad(seq)}_$titlePart.cbz';
      final cbzPath = fs.join(basePath, cbzName);
      await fs.writeBytes(cbzPath, cbzBytes);
      chapterPaths[i] = cbzPath;
      wroteChapters++;
      onProgress?.call(i + 1, chapters.length, 0.0);
    }

    if (wroteChapters == 0) {
      AppLog.instance.e('[漫画下载失败] ${task.title}: 未获取到任何话');
      throw Exception('未能获取到任何章节，可能被源拦截或章节地址已失效');
    }
    return DownloadResult(workPath: basePath, chapterFilePaths: chapterPaths);
  }

  /// 取消检查：命中用户取消时抛出 [DownloadCancelledException] 中止下载。
  /// 在每话开始前调用，避免取消后仍在拉取/写盘（修复 132）。
  void _throwIfCancelled(DownloadCancelledCheck? isCancelled) {
    if (isCancelled?.call() ?? false) {
      throw const DownloadCancelledException();
    }
  }

  /// 取图 Referer：书源（规则引擎）源不做页面推导——对齐 legado
  /// `BookHelp.saveImageFile` 的 `AnalyzeUrl(src, source = bookSource)`，
  /// 只带源声明的 UA/Referer。按章节页推导仅限原生漫画源。
  String? _subresourceReferer(String chapterPageUrl, String imageUrl) {
    if (source.isShuyuanSource) return null;
    return HttpFetcher.refererForSubresource(chapterPageUrl, imageUrl);
  }

  Future<Uint8List?> _fetchImageBytes(String url, {String? referer}) async {
    try {
      // 必须带与在线取图一致的防盗链头（Referer/Cookie/UA），否则防盗链源
      // 回 HTML 错误页（200）→ 存成 .jpg 后解码失败 → "图片已损坏"。
      // Accept 显式去掉 image/avif：Flutter 内置解码器不支持 AVIF，声明了
      // avif 的协商 CDN 会返回 AVIF → 下载的图打不开（在线走缓存管理器无此头）。
      // referer（章节页 URL 推导）非空时优先——部分站点按「图片↔所属章节页」
      // 绑定校验 Referer，固定站点级 Referer 会被拒（400/403）。
      final Map<String, String> headers = <String, String>{
        ...?source.fetchHeadersFor(url),
        'Accept': 'image/jpeg,image/png,image/webp,image/gif,*/*;q=0.8',
        if (referer != null && referer.isNotEmpty) 'Referer': referer,
      };
      final bytes =
          await HttpFetcher.instance.getBytes(url, headers: headers);
      if (bytes.isEmpty || _looksLikeHtml(bytes)) return null;
      // 源声明式图片解密（imageTransform）：下载即落明文，本地阅读无需再解。
      final Uri? uri = Uri.tryParse(url);
      if (uri != null && ImageBytesDecryptRegistry.matchFor(uri) != null) {
        return ImageBytesDecryptRegistry.decrypt(uri, Uint8List.fromList(bytes));
      }
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  /// 仅拒绝 HTML/纯文本（防盗链错误页），其余二进制一律接受——
  /// 覆盖 JPEG/PNG/GIF/BMP/WebP/AVIF 等全部格式，避免把合法图片误判丢弃
  /// 导致「下载不到内容」。
  static bool _looksLikeHtml(List<int> b) {
    var i = 0;
    while (i < b.length &&
        (b[i] == 0x20 || b[i] == 0x09 || b[i] == 0x0D || b[i] == 0x0A)) {
      i++;
    }
    if (i >= b.length) return true;
    if (b[i] != 0x3C /* '<' */) return false;
    final int end = i + 8 < b.length ? i + 8 : b.length;
    final head = String.fromCharCodes(b.sublist(i, end)).toUpperCase();
    return head.startsWith('<!DOCTYPE') ||
        head.startsWith('<HTML') ||
        head.startsWith('<HEAD') ||
        head.startsWith('<BODY');
  }

  /// 清洗文件名非法字符（/ \ : * ? " < > |），若结果为空返回空串。
  static String _sanitizeTitle(String title) {
    final String cleaned = title.replaceAll(
      RegExp(r'[/\\:*?"<>|]'),
      '',
    ).trim();
    return cleaned;
  }

  static String _pad(int n, [int width = 4]) =>
      n.toString().padLeft(width, '0');
}
