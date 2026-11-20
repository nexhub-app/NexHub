/// 小说下载处理器。
///
/// 按章节拉取正文段落与插图 → 逐章落盘为纯文本 TXT。目录组织与通用离线
/// 阅读器：每部作品一个文件夹，内部每章一个 `NNNNN_章节标题.txt`（序号取自
/// 章节全局编号，保证跨批次顺序一致且不重名），插图存入同目录 `images/`
/// 子目录、以本地路径内联于正文。逐章独立文件从根源消除「分批下载同名覆盖、
/// 只能打开一章」的问题。EPUB 格式仍打包为整本单文件（legacy）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show md5;

import '../models/episode.dart';
import '../models/novel_block.dart';
import '../models/plugin_config.dart';
import '../local/local_novel_parser.dart' show kNexhubImgMarker;
import '../novel/novel_chinese_converter.dart';
import '../novel/novel_export_template.dart';
import '../novel/novel_highlight_manager.dart';
import '../ai/translation_options_store.dart';
import '../novel/novel_translation_manager.dart';
import '../scraper/http_fetcher.dart';
import '../scraper/media_api_service.dart';
import '../utils/app_log.dart';
import 'download_file_system.dart';
import 'download_handler.dart';
import 'download_task.dart';
import 'epub_builder.dart';

/// 小说下载处理器。
class NovelDownloadHandler implements DownloadHandler {
  NovelDownloadHandler({
    required this.service,
    required this.fs,
    required this.source,
    required this.novelId,
    required this.chapters,
    this.format = DownloadFormat.epub,
    this.bookTitle = '',
    this.author,
    this.concurrency = 1,
    this.convertMode = ChineseConvertMode.none,
    this.includeHighlights = false,
    this.includeTranslations = false,
    this.exportTemplate,
    this.coverUrl,
    this.templateStore,
  });

  final MediaApiService service;
  final DownloadFileSystem fs;
  final PluginConfig source;
  final String novelId;
  final List<Episode> chapters;
  final DownloadFormat format;
  final String bookTitle;
  final String? author;

  /// 章节并行拉取数（来自下载设置「线程数」），<=1 退化为顺序下载。
  final int concurrency;

  /// 繁简转换模式：落盘前对文本块应用与阅读器一致的转换，
  /// 保证「阅读器内开繁→简后，离线缓存与显示相同」。默认不转换。
  final ChineseConvertMode convertMode;

  /// 是否把本书划线/批注作为附录附带进导出（EPUB 追加一章，
  /// TXT 追加一个划线文件）。默认关闭，调用方显式开启。
  final bool includeHighlights;

  /// 是否把已缓存的章节译文（段落翻译）作为附录附带进导出。
  /// 仅包含有译文的章节；默认关闭，调用方显式开启。
  final bool includeTranslations;

  /// 导出模板（显式传入优先；为 null 时下载开始时从
  /// [templateStore] 异步载入全局模板）。
  final NovelExportTemplate? exportTemplate;

  /// 网络封面地址（嵌入 EPUB 封面页用；与落盘的 cover.jpg 无关，
  /// 因为封面在 handler.download 之后才写盘，EPUB 构建期需自行获取）。
  final String? coverUrl;

  /// 模板存储（默认全局单例，测试可注入内存实现）。
  final NovelExportTemplateStore? templateStore;

  @override
  Future<DownloadResult> download(
    DownloadTask task, {
    DownloadProgressCallback? onProgress,
    DownloadCancelledCheck? isCancelled,
  }) async {
    final workDir = task.localPath!;
    await fs.createDir(workDir);
    final imagesDir = fs.join(workDir, 'images');
    await fs.createDir(imagesDir);

    // 并行拉取各章正文块（保留顺序），再逐章落盘（含插图下载）。
    //
    // 进度分段：抓取占前 80%、写盘与插图占后 20%。抓取完由写盘进度直接
    // 接管，消除旧实现「抓取报 100% → 写盘又回到 0%」的进度回跳。
    const fetchSpan = 0.8;
    const writeSpan = 1.0 - fetchSpan;
    final List<List<NovelBlock>?> fetched =
        List<List<NovelBlock>?>.filled(chapters.length, null);
    final idxList = [for (var i = 0; i < chapters.length; i++) i];
    Future<void> fetchAllChapters() => runPool(concurrency, idxList, (i) async {
      _throwIfCancelled(isCancelled);
      final ch = chapters[i];
      try {
        final nextUrl = i + 1 < chapters.length ? chapters[i + 1].url : null;
        fetched[i] = await service.fetchNovelContent(
          source,
          novelId: novelId,
          chapterUrl: ch.url,
          nextChapterUrl: nextUrl,
        );
      } on Object catch (e) {
        // 单章抓取失败不影响整体：置 null，后续跳过该章（写空文件会触发
        // SAF 空内容拒绝 → 整个下载失败）。与 media handler 逐集捕获一致。
        AppLog.instance.w('[小说章节抓取失败] ${task.title} 第${i + 1}章: $e');
        fetched[i] = null;
      }
    }, onItemDone: (completed, total) {
      // 抓取阶段真实进度（每完成一章）映射进前 80% 区间。
      reportOverallProgress(
          onProgress, fetchSpan * completed / total, chapters.length);
    });
    if (chapters.length == 1) {
      // 单章抓取是一次原子请求，期间没有真实进度信号 → 渐近估计填充
      // 0%→80% 区间，避免整个网络等待期停在 0%、完成瞬间跳 100%。
      await estimateOpaqueProgress(
        fetchAllChapters,
        onValue: (v) => reportOverallProgress(
            onProgress, fetchSpan * v, chapters.length),
      );
    } else {
      await fetchAllChapters();
    }

    // 章节文件路径（下标对齐 chapters）
    // 与 media/comic handler 的语义一致，供阅读器跨批次聚合时正确对齐。
    final List<String> chapterFilePaths =
        List<String>.filled(chapters.length, '');
    var anyContent = false;
    for (var i = 0; i < chapters.length; i++) {
      _throwIfCancelled(isCancelled);
      final ch = chapters[i];
      final blocks = fetched[i] ?? const <NovelBlock>[];
      final seq = ch.number ?? (i + 1);
      final buffer = StringBuffer();
      for (var bIdx = 0; bIdx < blocks.length; bIdx++) {
        final b = blocks[bIdx];
        // 章内块进度（文本块/插图块）映射进后 20% 区间：插图逐张下载时
        // 进度随之逐渐增加；纯文本章写盘极快，瞬时走完属真实情况。
        reportOverallProgress(
            onProgress,
            fetchSpan + writeSpan * (i + bIdx / blocks.length) / chapters.length,
            chapters.length);
        if (b is NovelTextBlock) {
          if (b.text.trim().isNotEmpty) {
            buffer.writeln(convertChinese(b.text, convertMode));
            buffer.writeln();
          }
        } else if (b is NovelImageBlock) {
          // 插图内联：下载到本地 images/ 并写入占位行（绝对/SAF 路径），
          // 阅读器识别后走本地文件渲染（[SourceImage] 已支持本地路径）。
          if (b.isValid) {
            final local = await _downloadImage(b.url, imagesDir, source);
            if (local != null) {
              buffer.writeln('$kNexhubImgMarker$local');
              buffer.writeln();
            }
          }
        }
      }
      if (buffer.isEmpty) {
        // 该章内容为空（源抓取失败/被拦截）：跳过，不写空文件。SAF 文件系统
        // 会拒绝写入空内容（writeBytes 校验），直接写空文件会抛异常 → 整个
        // 下载失败 → 作品目录被清理（表现为"文件夹没有内容"）。
        reportOverallProgress(onProgress,
            fetchSpan + writeSpan * (i + 1) / chapters.length, chapters.length);
        continue;
      }
      anyContent = true;
      final fileName = '${_pad5(seq)}_${_sanitize(ch.title)}.txt';
      final filePath = fs.join(workDir, fileName);
      await fs.writeString(filePath, buffer.toString());
      chapterFilePaths[i] = filePath;
      reportOverallProgress(onProgress,
          fetchSpan + writeSpan * (i + 1) / chapters.length, chapters.length);
    }

    // 全部章节正文与插图都为空（源正文抓取失败/被反盗链拦截）→ 明确报错，
    // 否则产出的 TXT 只有空文件 → 打开报「本地文件读取失败」且无从排查。
    if (!anyContent) {
      AppLog.instance.e('[小说下载失败] ${task.title}: 未获取到任何章节内容 '
          '(${chapters.length} 章全部为空)');
      throw Exception(
          '未能获取到任何章节内容，可能被源拦截或章节地址已失效');
    }

    // EPUB 格式：保持整本单文件 legacy（逐章 TXT 为默认推荐格式）。
    if (format == DownloadFormat.epub) {
      // 解析导出模板（显式传入优先，否则读全局存储）。
      final NovelExportTemplate tpl = exportTemplate ??
          await (templateStore ?? NovelExportTemplateStore.instance).load();
      // 封面字节（模板开启 + 有网络封面时获取；失败降级为无封面页）。
      EpubImage? coverImage;
      if (tpl.includeCover && coverUrl != null && coverUrl!.isNotEmpty) {
        try {
          final Map<String, String> headers = <String, String>{
            ...?source.fetchHeadersFor(coverUrl!),
            'Accept': 'image/jpeg,image/png,image/webp,image/gif,*/*;q=0.8',
          };
          final coverBytes = await HttpFetcher.instance
              .getBytes(coverUrl!, headers: headers);
          if (coverBytes.isNotEmpty) {
            coverImage = EpubImage(
              href: 'Images/cover${_extFromUrl(coverUrl!)}',
              data: Uint8List.fromList(coverBytes),
            );
          }
        } on Object {
          coverImage = null;
        }
      }
      final introHtml = (tpl.includeIntro && tpl.intro.trim().isNotEmpty)
          ? renderIntroHtml(tpl.intro,
              bookTitle: bookTitle.isNotEmpty ? bookTitle : task.title,
              author: author)
          : null;

      final metadata = EpubMetadata(
        title: bookTitle.isNotEmpty ? bookTitle : task.title,
        author: author,
      );
      // 内嵌插图：正文里的插图块下载后写入 EPUB 资源并在 XHTML 内
      // 引用，图文小说导出不再丢图。按 URL 去重（跨章同图只存一份字节），
      // 单张下载失败降级跳过（与 TXT 插图路径一致），不阻塞整本导出。
      final images = <String, EpubImage>{}; // url → 资源（名字 = 哈希+扩展名）
      Future<String?> imageRef(String url) async {
        final existing = images[url];
        if (existing != null) return existing.href;
        try {
          final Map<String, String> headers = <String, String>{
            ...?source.fetchHeadersFor(url),
            'Accept': 'image/jpeg,image/png,image/webp,image/gif,*/*;q=0.8',
          };
          final bytes =
              await HttpFetcher.instance.getBytes(url, headers: headers);
          if (bytes.isEmpty) return null;
          final href = 'Images/${_hash(url)}${_extFromUrl(url)}';
          images[url] =
              EpubImage(href: href, data: Uint8List.fromList(bytes));
          return href;
        } on Object {
          return null;
        }
      }

      final epubChapters = <EpubChapter>[];
      for (var i = 0; i < chapters.length; i++) {
        _throwIfCancelled(isCancelled);
        final parts = <String>[];
        for (final b in fetched[i] ?? const <NovelBlock>[]) {
          if (b is NovelTextBlock) {
            if (b.text.trim().isNotEmpty) {
              parts.add('<p>${_escape(convertChinese(b.text, convertMode))}</p>');
            }
          } else if (b is NovelImageBlock && b.isValid) {
            final ref = await imageRef(b.url);
            if (ref != null) {
              parts.add('<div><img src="$ref" alt=""/></div>');
            }
          }
        }
        epubChapters.add(EpubChapter(
          title: chapters[i].title,
          content: parts.join('\n'),
        ));
      }
      if (epubChapters.isEmpty ||
          epubChapters.every((c) => c.content.trim().isEmpty)) {
        throw Exception(
            '未能获取到任何章节内容，可能被源拦截或章节地址已失效');
      }

      // 划线 / 批注附带为书末附录章节（仅当开启且存在划线时）。
      if (includeHighlights) {
        final highlights = await _loadHighlights();
        final html = NovelDownloadHandler.highlightsToEpubHtml(highlights);
        if (html != null) {
          epubChapters.add(EpubChapter(
            title: NovelDownloadHandler.highlightsTitle,
            content: html,
          ));
        }
      }

      // 已缓存译文附带为书末附录章节（仅当开启且存在翻译缓存时）。
      if (includeTranslations) {
        final translations = await _loadTranslations();
        final html = NovelDownloadHandler.translationsToEpubHtml(
          translations,
          layout: await _exportLayout(),
        );
        if (html != null) {
          epubChapters.add(EpubChapter(
            title: NovelDownloadHandler.translationsTitle,
            content: html,
          ));
        }
      }

      final bytes = EpubBuilder.build(
        metadata: metadata,
        chapters: epubChapters,
        images: images.values.toList(growable: false),
        css: tpl.customCss.trim().isEmpty ? null : tpl.customCss,
        coverImage: coverImage,
        introHtml: introHtml,
      );
      final safeTitle =
          _sanitize(bookTitle.isNotEmpty ? bookTitle : task.title);
      final epubPath = fs.join(workDir, '$safeTitle.epub');
      await fs.writeBytes(epubPath, bytes);
      return DownloadResult(
          workPath: workDir, chapterFilePaths: <String>[epubPath]);
    }

    // TXT 逐章文件：chapterFilePaths 即本次逐章落盘的文件（供阅读器跨批次聚合）。
    // workPath 必须是**作品目录**（与 media/comic handler 一致）——`_executeDownload`
    // 会把 result.workPath 覆盖进 task.localPath，若这里返回文件路径会导致
    // localPath 变成 `.txt` 文件，后续在 `localPath` 下写 meta.json/cover.jpg
    // 时 SAF 报 "Parent document isn't a directory"。
    // 划线 / 批注附带为独立文件（不进入 chapterFilePaths，避免被
    // 跨批次聚合误识别为章节）。
    if (includeHighlights) {
      final highlights = await _loadHighlights();
      if (highlights.isNotEmpty) {
        final highlightsPath =
            fs.join(workDir, '${NovelDownloadHandler.highlightsTitle}.txt');
        await fs.writeString(
            highlightsPath, NovelDownloadHandler.highlightsToTxt(highlights));
      }
    }
    // 已缓存译文附带为独立文件（不进入 chapterFilePaths）。
    if (includeTranslations) {
      final translations = await _loadTranslations();
      if (translations.isNotEmpty) {
        final path =
            fs.join(workDir, '${NovelDownloadHandler.translationsTitle}.txt');
        await fs.writeString(
            path,
            NovelDownloadHandler.translationsToTxt(translations,
                layout: await _exportLayout()));
      }
    }
    return DownloadResult(workPath: workDir, chapterFilePaths: chapterFilePaths);
  }

  /// 译文附录排版模式（译文优先 / 原文优先 / 双语对照）。
  /// 读取失败回落「译文优先」。
  Future<String> _exportLayout() async {
    try {
      return await TranslationOptionsStore().getNovelExportLayout();
    } on Object {
      return 'translationFirst';
    }
  }

  String _pad5(int n) => n.toString().padLeft(5, '0');

  /// 取消检查：命中用户取消时抛出 [DownloadCancelledException] 中止下载。
  /// 在每章抓取/落盘前调用，避免取消后仍在拉取与写盘（修复 132）。
  void _throwIfCancelled(DownloadCancelledCheck? isCancelled) {
    if (isCancelled?.call() ?? false) {
      throw const DownloadCancelledException();
    }
  }

  String _sanitize(String s) {
    final clean = s
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
    return clean.isEmpty ? 'chapter' : clean;
  }

  static String _escape(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  /// 下载插图到 [imagesDir]，按 URL 哈希命名（跨章同图去重复用）。
  /// 返回本地绝对路径（或 Android SAF 编码路径）；失败返回 null（插图降级跳过）。
  Future<String?> _downloadImage(
    String url,
    String imagesDir,
    PluginConfig? source,
  ) async {
    try {
      final name = '${_hash(url)}${_extFromUrl(url)}';
      final path = fs.join(imagesDir, name);
      if (await fs.exists(path)) return path; // 已存在（同图复用）
      final Map<String, String> headers = <String, String>{
        ...?source?.fetchHeadersFor(url),
        'Accept': 'image/jpeg,image/png,image/webp,image/gif,*/*;q=0.8',
      };
      final bytes = await HttpFetcher.instance.getBytes(url, headers: headers);
      if (bytes.isEmpty) return null;
      await fs.writeBytes(path, Uint8List.fromList(bytes));
      return path;
    } on Object {
      return null;
    }
  }

  /// 从 URL 取图片扩展名（校验为常见图片格式，否则回退 .jpg）。
  String _extFromUrl(String url) {
    final idx = url.lastIndexOf('.');
    if (idx > 0 && idx < url.length - 1) {
      final e = url.substring(idx).toLowerCase().split('?').first;
      if (const <String>[
        '.jpg',
        '.jpeg',
        '.png',
        '.webp',
        '.gif',
        '.bmp'
      ].contains(e)) {
        return e;
      }
    }
    return '.jpg';
  }

  /// URL 的 MD5 十六进制（32 位），用作插图文件名，跨源/跨章唯一且稳定。
  String _hash(String s) {
    final d = md5.convert(utf8.encode(s)).bytes;
    final sb = StringBuffer();
    for (final b in d) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  // ─────────────────── 划线附带 ───────────────────

  /// 把模板简介文本渲染为简介页 HTML 片段：`{book}` / `{author}`
  /// 占位符替换后按空行分段、逐段转义为 `<p>`。
  static String renderIntroHtml(String intro,
      {required String bookTitle, String? author}) {
    final text = intro
        .replaceAll('{book}', bookTitle)
        .replaceAll('{author}', author ?? '');
    final paragraphs = <String>[];
    for (final raw in text.split(RegExp(r'\n\s*\n'))) {
      final p = raw.trim();
      if (p.isEmpty) continue;
      paragraphs.add('<p>${_escape(p)}</p>');
    }
    return paragraphs.join('\n');
  }

  /// 读取本书全部章节译文缓存（异常返回空列表，不影响导出主流程）。
  Future<List<NovelChapterTranslation>> _loadTranslations() async {
    try {
      return await NovelTranslationManager().listForNovel(novelId);
    } on Object {
      return const <NovelChapterTranslation>[];
    }
  }

  /// 译文导出标题（EPUB 章节名 / TXT 文件名共用）。
  static const String translationsTitle = '_段落翻译';

  /// 排版：把「原文/译文」序列按排版模式展平为段落列表。
  ///
  /// - translationFirst（默认）：仅译文（原文优先模式在无原文时同样回落）；
  /// - sourceFirst：仅原文；
  /// - bilingual：逐段「原文 + 译文」。
  static List<String> _layoutParagraphs(
    NovelChapterTranslation t,
    String layout,
  ) {
    final sources = t.sources;
    final hasSources =
        sources != null && sources.length == t.translations.length;
    switch (layout) {
      case 'sourceFirst':
        if (!hasSources) return t.translations;
        return sources;
      case 'bilingual':
        final out = <String>[];
        for (var i = 0; i < t.translations.length; i++) {
          if (hasSources && sources![i].trim().isNotEmpty) {
            out.add(sources[i]);
          }
          out.add(t.translations[i]);
        }
        return out;
      default:
        return t.translations;
    }
  }

  /// 把译文缓存渲染为 EPUB 附录 HTML：每章一节（章名加粗），段内
  /// 按 排版模式输出；空列表返回 null（不追加附录）。
  static String? translationsToEpubHtml(
      List<NovelChapterTranslation> translations,
      {String layout = 'translationFirst'}) {
    final parts = <String>[];
    for (final t in translations) {
      if (t.translations.isEmpty) continue;
      final buf = StringBuffer();
      buf.write('<span style="font-weight:bold">'
          '${_escape(t.chapterTitle.isEmpty ? t.chapterId : t.chapterTitle)}'
          '</span><br/>');
      for (final paragraph in _layoutParagraphs(t, layout)) {
        buf.write('<p>${_escape(paragraph)}</p>');
      }
      parts.add(buf.toString());
    }
    if (parts.isEmpty) return null;
    return '<hr/>${parts.join('<hr/>')}';
  }

  /// 译文缓存的 TXT 版本：每节「【章名】+ 逐行（按 排版模式）」，
  /// 节间空行分隔。
  static String translationsToTxt(List<NovelChapterTranslation> translations,
      {String layout = 'translationFirst'}) {
    final buffer = StringBuffer();
    buffer.writeln('书内段落译文（导出附录）');
    buffer.writeln('======================');
    buffer.writeln();
    for (final t in translations) {
      final title =
          t.chapterTitle.isNotEmpty ? t.chapterTitle : t.chapterId;
      buffer.writeln('【$title】');
      for (final paragraph in _layoutParagraphs(t, layout)) {
        buffer.writeln(paragraph);
      }
      buffer.writeln();
    }
    return buffer.toString();
  }

  /// 读取本书全部划线 / 批注（按章节顺序、创建时间升序）。
  /// 异常（Hive 未初始化等）返回空列表，不影响导出主流程。
  Future<List<NovelHighlight>> _loadHighlights() async {
    try {
      return await NovelHighlightManager().listFor(novelId);
    } on Object {
      return const <NovelHighlight>[];
    }
  }

  /// 划线导出标题（EPUB 章节名 / TXT 文件名前缀共用）。
  static const String highlightsTitle = '_划线批注';

  /// 把划线列表渲染为 EPUB 章节 HTML。<p> 逐条：章节名 — 划线内容，
  /// 笔记以斜体附注；空列表返回 null（不追加章节）。
  static String? highlightsToEpubHtml(List<NovelHighlight> highlights) {
    return _highlightsToEpubHtml(highlights);
  }

  static String? _highlightsToEpubHtml(List<NovelHighlight> highlights) {
    final parts = <String>[];
    for (final h in highlights) {
      final chapter = h.chapterTitle.isNotEmpty
          ? '<span style="font-weight:bold">${_escape(h.chapterTitle)}</span><br/>'
          : '';
      var text = '${chapter}${_escape(h.quote)}';
      if (h.note != null && h.note!.isNotEmpty) {
        text += '<br/><i>备注：${_escape(h.note!)}</i>';
      }
      parts.add('<p>$text</p>');
    }
    if (parts.isEmpty) return null;
    return parts.join('\n');
  }

  /// TXT 划线文件内容：每条「章节名 / 划线 / 备注」，行间空行分隔。
  static String highlightsToTxt(List<NovelHighlight> highlights) {
    return _highlightsToTxt(highlights);
  }

  static String _highlightsToTxt(List<NovelHighlight> highlights) {
    final buffer = StringBuffer();
    buffer.writeln('书内划线与批注（导出附录）');
    buffer.writeln('======================');
    buffer.writeln();
    for (final h in highlights) {
      if (h.chapterTitle.isNotEmpty) {
        buffer.writeln('【${h.chapterTitle}】');
      }
      buffer.writeln(h.quote);
      if (h.note != null && h.note!.isNotEmpty) {
        buffer.writeln('备注：${h.note}');
      }
      buffer.writeln();
    }
    return buffer.toString();
  }
}
