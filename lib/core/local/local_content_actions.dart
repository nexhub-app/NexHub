/// 本地导入内容的通用操作（打开 / 重命名 / 删除）。
///
/// 供导入历史列表（[ContentImportScreen]）与各媒体书架「本地」分段
/// （[bookshelf_content] 的 [_LocalBookshelf]）复用，避免重复实现弹窗逻辑。
library;

import 'dart:async' show unawaited;
import 'dart:io';

import 'package:nexhub/core/utils/app_log.dart';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:nexhub/core/download/download_manager.dart';
import 'package:nexhub/core/download/download_task.dart';
import 'package:nexhub/core/local/local_content_manager.dart';
import 'package:nexhub/core/local/saf_bridge.dart'
    show
        safBaseName,
        gatherSafImages,
        listFolderFilesByKindSaf,
        scanComicFolderSaf;
import 'package:nexhub/core/models/episode.dart';
import 'package:nexhub/core/models/media_item.dart';
import 'package:nexhub/core/navigation/app_page_route.dart';
import 'package:nexhub/core/settings/general_settings.dart';
import 'package:nexhub/features/home/presentation/local_media_viewer.dart';
import 'package:nexhub/features/manga/presentation/comic_reader_screen.dart';
import 'package:nexhub/features/novel/presentation/novel_reader_screen.dart';
import 'package:nexhub/features/player/presentation/video_player_screen.dart';
import 'package:nexhub/generated/app_localizations.dart';
import '../utils/app_haptics.dart';

/// 收集本地漫画图片路径：目录→按名排序的图片列表；单图文件→单元素列表。
/// 不含 cbz/zip（交给漫画阅读器内部解压）。无图片返回空列表。
///
/// 返回的**是 SAF content:// 文档 URI（或真实文件路径），不是已落缓存的本地路径**。
/// [gatherSafImages] 只收集 URI、不预先拷贝，真正的落缓存（[resolveSafUri]）由
/// 阅读器逐张显示时按需进行（见 [SourceImage]），从而打开含大量图片的文件夹时
/// 不再因整本逐张拷贝而卡 1~2s。
Future<List<String>> gatherLocalComicImages(String path) async {
  if (isDocUri(path)) return gatherSafImages(path);
  final f = File(path);
  if (await f.exists()) return <String>[path];
  final dir = Directory(path);
  if (await dir.exists()) {
    final imgs = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((x) => isImageFile(x.path))
        .map((x) => x.path)
        .toList()
      ..sort();
    if (imgs.isEmpty) {
      // 目录存在但没扫到任何图片：记警告日志，避免「点开无反应 + 日志为空」。
      AppLog.instance.w('[本地漫画图片收集] 目录存在但未发现任何图片: $path');
    }
    return imgs;
  }
  // 路径既不是文件也不是目录：记错误日志，便于排查「文件夹打不开」。
  AppLog.instance.e('[本地漫画图片收集] 路径不存在（既非文件也非目录）: $path');
  return const <String>[];
}

/// 由聚合文件夹的子文件列表构造合成章节列表（每文件 = 一章/一话）。
///
/// 标题取文件名（去扩展名），id 用文件路径，url 留空（本地），
/// number 为 1-based。供本地聚合条目（`LocalContentEntry.filePaths` /
/// 浏览本地聚合文件）传给阅读器，复用其在线章节导航（目录/上下章）。
List<Episode> buildLocalChapterList(List<String> paths) {
  final List<Episode> chapters = <Episode>[];
  for (int i = 0; i < paths.length; i++) {
    final path = paths[i];
    // SAF content:// 文件 URI 的 basename 是 URL 编码的 document id（形如
    // primary%3ADownload%2Ftxt%2F第1章.txt），直接用 p.basenameWithoutExtension
    // 会得到编码串；先经 safBaseName 还原真实文件名再取标题。
    final rawName = isDocUri(path) ? safBaseName(path) : path;
    final title = p.basenameWithoutExtension(rawName);
    chapters.add(Episode(
      id: path,
      title: title.isEmpty ? path : title,
      url: '',
      number: i + 1,
    ));
  }
  return chapters;
}

/// 打开本地导入内容。
///
/// 路由规则（与浏览本地 [BrowseLocalScreen._openFile] 保持一致）：
/// - PDF → 漫画阅读器（逐页渲染成图）。
/// - 漫画图片（文件夹散图 / 单图 / .cbz/.cbr/.cbt/.zip/.rar/.7z/.cb7）→ 漫画阅读器
/// （多格式解压，[extractArchiveImages] 支持 RAR 系与 7z）；目录走 [LocalMediaViewer]。
/// - 小说 .txt → 小说阅读器；.epub → 小说阅读器（解析章节）；其余文本格式走通用查看器。
/// - 其它 → 通用 [LocalMediaViewer]。
Future<void> openLocalEntry(BuildContext context, LocalContentEntry e) async {
  final bool remember = GeneralSettingsStore.instance.settings.rememberPosition;
  // 聚合文件夹：每个文件=一章/一话，传合成章节列表给阅读器（B 阶段）。
  if (e.filePaths != null && e.filePaths!.isNotEmpty) {
    final chapters = buildLocalChapterList(e.filePaths!);
    if (e.kind == LocalMediaKind.text) {
      await Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (_) => NovelReaderScreen(
            novelId: e.id,
            title: e.title,
            sourceId: '',
            coverUrl: e.coverUrl,
            chapters: chapters,
            localChapterPaths: e.filePaths,
            restoreProgress: remember,
          ),
        ),
      );
      return;
    }
    if (e.kind == LocalMediaKind.images) {
      _pushComicReader(
        context,
        e,
        remember,
        localArchivePaths: e.filePaths,
        chapters: chapters,
      );
      return;
    }
  }
  if (e.kind == LocalMediaKind.pdf) {
    _pushComicReader(context, e, remember, localPdfPath: e.path);
    return;
  }
  if (e.kind == LocalMediaKind.images) {
    final lower = e.path.toLowerCase();
    // 漫画归档（cbz/cbr/cbt/zip/rar/7z/cb7）全部交给阅读器多格式解压，不再把
    // .cbr/.rar 当「不支持」甩给兜底查看器。
    if (const <String>[
      '.cbz',
      '.cbr',
      '.cbt',
      '.zip',
      '.rar',
      '.7z',
      '.cb7',
    ].any((ext) => lower.endsWith(ext))) {
      _pushComicReader(context, e, remember, localCbzPath: e.path);
    } else {
      // try/catch 兜底：任何残留异常都记日志，避免「点开无反应 + 运行日志为空」。
      List<String> imgs;
      try {
        imgs = await gatherLocalComicImages(e.path);
      } on Object catch (err) {
        AppLog.instance.eWithStack('[本地漫画图片收集失败] path=${e.path}', err);
        imgs = const <String>[];
      }
      if (!context.mounted) return;
      if (imgs.isNotEmpty) {
        _pushComicReader(context, e, remember, localImages: imgs);
      } else {
        _pushLocalMediaViewer(context, e);
      }
    }
    return;
  }
  if (e.kind == LocalMediaKind.text) {
    final lower = e.path.toLowerCase();
    final titleLower = e.title.toLowerCase();
    // SAF 选中的文件是 content:// URI，无扩展名，仅按 path 判断会漏判 →
    // 「无法打开 TXT」。显示名（f.name / 文件夹名）保留扩展名，作为兜底判断。
    final bool isEpub =
        lower.endsWith('.epub') || titleLower.endsWith('.epub');
    final bool isTxt = lower.endsWith('.txt') || titleLower.endsWith('.txt');
    if (isEpub) {
      // await 到阅读器关闭：调用方（详情页）返回后刷新本地阅读进度。
      await Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (_) => NovelReaderScreen(
            novelId: e.id,
            title: e.title,
            sourceId: '',
            coverUrl: e.coverUrl,
            chapters: const <Episode>[],
            localEpubPath: e.path,
            restoreProgress: remember,
          ),
        ),
      );
      return;
    }
    // .txt 或扩展名缺失（content:// 无扩展名）：默认按 txt 处理，交给阅读器
    // resolveSafUri 后按内容解析（本地小说绝大多数为 txt）。
    await Navigator.of(context).push(
      AppPageRoute<void>(
      builder: (_) => NovelReaderScreen(
        novelId: e.id,
        title: e.title,
        sourceId: '',
        coverUrl: e.coverUrl,
        chapters: const <Episode>[],
        localTextPath: e.path,
        restoreProgress: remember,
      ),
      ),
    );
    return;
  }
  _pushLocalMediaViewer(context, e);
}

/// 打开「已下载作品」：直接扫描作品文件夹（与「导入目录」同一套扫描函数），
/// 把磁盘上实际存在的文件全部解析出来，聚合进阅读器/播放器。
///
/// 分批下载、旧数据、下载记录缺失都不影响——扫到什么就能看什么、切什么，
/// 打开行为与「导入目录文件」完全一致。
///
/// - 视频：扫描 .mp4/.ts/… 构建完整集列表进播放器（可上下集切换）。
/// - 小说：扫描 .txt/.epub 按章聚合进阅读器（可切章；epub 内部章节自动展开）。
/// - 漫画：扫描归档按话聚合；folder 模式取子目录为话；散图整目录交给阅读器收集。
/// [initialIndex] 非 null 表示用户从文件列表【点选】了某一话/集（0 起），打开后
/// 定位到该项——此时阅读器不恢复存档章（restoreProgress=false），否则点选会被
/// 上次存档拉回另一话（「点回之前读的话却进不去/进度丢失」的根因）；点选的
/// 恰是存档在读话时仍会恢复页码（阅读器 _init 的 restoreProgress=false 分支）。
/// null（默认，打开作品入口）= 继续阅读语义：恢复到上次读到的章 + 页。
/// [coverUrl] 作品封面（下载封面本地路径或远程 URL）：阅读器写浏览历史时
/// 随条目落库；不传则历史条目无封面——下载作品的历史记录只剩首字占位图。
Future<void> openDownloadedWorkFolder(
  BuildContext context, {
  required String id,
  required String title,
  required String sourceId,
  required String workDir,
  required LocalMediaKind kind,
  int? initialIndex,
  String? coverUrl,
}) async {
  final bool remember = GeneralSettingsStore.instance.settings.rememberPosition;
  // 点选入口（initialIndex 非 null）：不恢复存档章，尊重点选；继续阅读入口恢复。
  final bool restore = remember && initialIndex == null;

  // 视频：本地内容机制不处理视频，单独走播放器（完整集列表，连播/上下集切换）。
  if (kind == LocalMediaKind.video) {
    List<String> files = const <String>[];
    try {
      files = isDocUri(workDir)
          ? await listFolderFilesByKindSaf(workDir, LocalMediaKind.video)
          : listFolderFilesByKind(workDir, LocalMediaKind.video);
    } on Object {
      // 目录不可读（如单文件路径）：保持空列表，走单文件播放回退。
    }
    if (!context.mounted) return;
    // 扫描不到（单文件导入 / 空目录）：回退为单文件播放，不弹失败。
    if (files.isEmpty) {
      Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (_) => VideoPlayerScreen(
            title: title,
            episode: Episode(id: 'local', title: title, url: workDir),
            sourceId: sourceId,
            itemId: id,
            localUri: workDir,
            restoreProgress: remember,
          ),
        ),
      );
      return;
    }
    final List<Episode> eps = <Episode>[
      for (var i = 0; i < files.length; i++)
        Episode(
          id: 'local_$i',
          title: safBaseName(files[i]),
          url: files[i],
          number: i + 1,
        ),
    ];
    final int start = (initialIndex ?? 0).clamp(0, eps.length - 1);
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => VideoPlayerScreen(
          title: title,
          episode: eps[start],
          sourceId: sourceId,
          itemId: id,
          episodes: eps,
          initialEpisodeIndex: start,
          localUri: eps[start].url,
          // 视频的 restoreProgress 只控制「本集播放位置」seek，不影响集选择：
          // 点选入口同样恢复该集进度。
          restoreProgress: remember,
        ),
      ),
    );
    return;
  }

  // 小说/漫画：扫描作品文件夹。
  List<String> filePaths = const <String>[];
  try {
    filePaths = await _scanWorkDirFiles(workDir, kind);
  } on Object {
    // 扫描失败（单文件路径等）：保持空列表，走单文件/散图回退。
  }
  if (!context.mounted) return;

  // 聚合模式（每文件一章/一话）：直接构造阅读器，支持从点选章节进入。
  if (filePaths.isNotEmpty) {
    final List<Episode> chapters = buildLocalChapterList(filePaths);
    final int start = (initialIndex ?? 0).clamp(0, chapters.length - 1);
    if (kind == LocalMediaKind.text) {
      Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (_) => NovelReaderScreen(
            novelId: id,
            title: title,
            sourceId: sourceId,
            coverUrl: coverUrl,
            chapters: chapters,
            localChapterPaths: filePaths,
            initialChapterIndex: start,
            restoreProgress: restore,
          ),
        ),
      );
      return;
    }
    if (kind == LocalMediaKind.images || kind == LocalMediaKind.pdf) {
      // folder 模式：每话一个子目录（非归档文件）；否则每话一个归档文件。
      final bool isDirs = filePaths.every((p) {
        final dir = Directory(p);
        try {
          if (dir.existsSync()) return true;
        } on Object {/* SAF URI 不抛 */}
        final lower = p.toLowerCase();
        return !const <String>[
          '.cbz', '.cbr', '.cbt', '.zip', '.rar', '.7z', '.cb7', '.pdf',
        ].any((ext) => lower.endsWith(ext));
      });
      Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (_) => ComicReaderScreen(
            comicId: id,
            title: title,
            sourceId: sourceId,
            coverUrl: coverUrl,
            chapters: chapters,
            localChapterDirs: isDirs ? filePaths : null,
            localArchivePaths: isDirs ? null : filePaths,
            initialChapterIndex: start,
            restoreProgress: restore,
          ),
        ),
      );
      return;
    }
  }

  // 无聚合文件（扫描失败 / 空目录 / 单文件导入）：
  // - SAF 作品文件夹：先尝试收集「纯散图」（无归档/其它文件时整目录交给阅读器，
  // 与真实路径 openLocalEntry → gatherLocalComicImages 行为一致）；仍无内容
  // 才提示。绝不把文件夹当文件去 resolveSafUri（会报"该路径是一个文件夹"）。
  // - 真实路径：保留原 openLocalEntry 单文件/散图回退（兼容单文件导入）。
  if (!isDocUri(workDir)) {
    await openLocalEntry(
      context,
      LocalContentEntry(
        id: id,
        title: title,
        path: workDir,
        kind: kind,
        addedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    return;
  }

  // SAF 作品文件夹扫描不到归档/其它文件，可能是「纯散图」目录（每张图 = 一页）。
  // 收集散图（content:// URI，懒解析）进漫画阅读器，与真实路径走 openLocalEntry
  // 时 gatherLocalComicImages 的行为一致；确实没有任何可读图片才提示。
  if (kind == LocalMediaKind.images || kind == LocalMediaKind.pdf) {
    final List<String> looseImages = await gatherSafImages(workDir);
    if (!context.mounted) return;
    if (looseImages.isNotEmpty) {
      _pushComicReader(
        context,
        LocalContentEntry(
          id: id,
          title: title,
          path: workDir,
          kind: kind,
          addedAt: DateTime.now().millisecondsSinceEpoch,
        ),
        remember,
        localImages: looseImages,
      );
      return;
    }
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('未在该文件夹中找到可读取的内容')),
    );
  }
}

/// 扫描作品文件夹内容（与「导入目录」完全同一套扫描函数）：
/// 小说 → .txt/.epub；漫画 → 归档 + 其它（每文件一话），无归档时取一级子目录
/// （folder 散图模式，每子目录一话）；纯散图返回空（交由 [openLocalEntry] 收集）。
Future<List<String>> _scanWorkDirFiles(
  String workDir,
  LocalMediaKind kind,
) async {
  if (kind == LocalMediaKind.text) {
    return isDocUri(workDir)
        ? await listFolderFilesByKindSaf(workDir, LocalMediaKind.text)
        : listFolderFilesByKind(workDir, LocalMediaKind.text);
  }
  if (kind == LocalMediaKind.images || kind == LocalMediaKind.pdf) {
    if (isDocUri(workDir)) {
      final r = await scanComicFolderSaf(workDir);
      if (r.archives.isNotEmpty || r.others.isNotEmpty) {
        return <String>[...r.archives, ...r.others];
      }
      return <String>[]; // SAF 下 folder 子目录模式暂不支持（归档模式正常）。
    }
    final r = scanComicFolder(workDir);
    // 有归档文件（cbz/zip/rar）：每归档一章，优先使用。
    if (r.archives.isNotEmpty) {
      return r.archives;
    }
    // 无归档但有子目录（典型漫画下载：每话一子目录）：优先子目录列表。
    final dir = Directory(workDir);
    if (dir.existsSync()) {
      final List<String> subDirs = dir
          .listSync()
          .whereType<Directory>()
          .map((d) => d.path)
          .toList()
        ..sort();
      if (subDirs.isNotEmpty) return subDirs;
    }
    // 无归档、无子目录：回落零散图片文件（松散图片单章模式）。
    return r.others;
  }
  return <String>[];
}

/// 将书架透传的 kind 名（[LocalMediaKind.name]）解析回枚举；无效返回 null。
LocalMediaKind? parseLocalMediaKind(String? name) {
  if (name == null) return null;
  for (final k in LocalMediaKind.values) {
    if (k.name == name) return k;
  }
  return null;
}

/// 打开搜索结果条目：本地导入/下载条目（[MediaItem.extra] 带
/// `localPath`/`filePaths`）直接进入本地阅读器/播放器，其余条目走
/// 在线详情页（[onOnline] 回调，由调用方决定跳转与 heroTag）。
///
/// 供各模块搜索页复用——搜索结果现在并入本地内容，点击行为须与书架一致
/// （本地内容不再误跳在线详情页）。
Future<void> openSearchResultEntry(
  BuildContext context, {
  required MediaItem item,
  String? heroTag,
  required void Function(MediaItem item, String? heroTag) onOnline,
}) async {
  final extra = item.extra;
  final localPath = extra == null ? null : extra['localPath'] as String?;
  final localKind = extra == null ? null : extra['localKind'] as String?;
  final filePaths =
      extra == null ? null : extra['filePaths'] as List<String>?;
  // 聚合文件夹（多文件=多章/话/集）：复用统一路由进入阅读器/播放器。
  if (filePaths != null && filePaths.isNotEmpty) {
    final kind = parseLocalMediaKind(localKind);
    if (kind != null) {
      openLocalAggregatedEntry(
        context,
        id: item.id,
        title: item.title,
        kind: kind,
        filePaths: filePaths,
      );
      return;
    }
  }
  // 本地导入单文件 / 已下载作品文件夹：扫描文件夹聚合进阅读器/播放器。
  if (localPath != null && localPath.isNotEmpty) {
    final kind = parseLocalMediaKind(localKind);
    if (kind != null) {
      await openDownloadedWorkFolder(
        context,
        id: item.id,
        title: item.title,
        sourceId: item.sourceId ?? '',
        coverUrl: item.coverUrl,
        workDir: localPath,
        kind: kind,
      );
      return;
    }
  }
  onOnline(item, heroTag);
}

/// 打开聚合本地条目（B 阶段：文件夹导入，多文件 = 多章/多话）。
///
/// 供首页各模块书架 onItemTap 复用，避免在每个 home 屏重复路由。
void openLocalAggregatedEntry(
  BuildContext context, {
  required String id,
  required String title,
  required LocalMediaKind kind,
  required List<String> filePaths,
}) {
  final remember = GeneralSettingsStore.instance.settings.rememberPosition;
  final chapters = buildLocalChapterList(filePaths);
  if (kind == LocalMediaKind.text) {
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => NovelReaderScreen(
          novelId: id,
          title: title,
          sourceId: '',
          chapters: chapters,
          localChapterPaths: filePaths,
          restoreProgress: remember,
        ),
      ),
    );
    return;
  }
  if (kind == LocalMediaKind.images || kind == LocalMediaKind.pdf) {
    _pushComicReader(
      context,
      LocalContentEntry(
        id: id,
        title: title,
        path: filePaths.first,
        kind: kind,
        addedAt: DateTime.now().millisecondsSinceEpoch,
        filePaths: filePaths,
      ),
      remember,
      localArchivePaths: filePaths,
      chapters: chapters,
    );
    return;
  }
  _pushLocalMediaViewer(
    context,
    LocalContentEntry(
      id: id,
      title: title,
      path: filePaths.first,
      kind: kind,
      addedAt: DateTime.now().millisecondsSinceEpoch,
      filePaths: filePaths,
    ),
  );
}

void _pushComicReader(
  BuildContext context,
  LocalContentEntry e,
  bool remember, {
  List<String>? localImages,
  String? localCbzPath,
  String? localPdfPath,
  List<String>? localArchivePaths,
  List<Episode> chapters = const <Episode>[],
}) {
  Navigator.of(context).push(
    AppPageRoute<void>(
      builder: (_) => ComicReaderScreen(
        comicId: e.id,
        title: e.title,
        sourceId: '',
        coverUrl: e.coverUrl,
        chapters: chapters,
        localImages: localImages,
        localCbzPath: localCbzPath,
        localPdfPath: localPdfPath,
        localArchivePaths: localArchivePaths,
        restoreProgress: remember,
      ),
    ),
  );
}

void _pushLocalMediaViewer(BuildContext context, LocalContentEntry e) {
  Navigator.of(context).push(
    AppPageRoute<void>(
      builder: (_) => LocalMediaViewer(
        title: e.title,
        kind: e.kind,
        uri: e.path,
      ),
    ),
  );
}

/// 重命名本地导入条目（仅改记录中的标题，不影响磁盘文件名）。
Future<void> renameLocalEntry(BuildContext context, LocalContentEntry e) async {
  final l10n = AppLocalizations.of(context);
  final controller = TextEditingController(text: e.title);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.renameGroup),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(hintText: l10n.renameHint),
        autofocus: true,
        onSubmitted: (v) => Navigator.of(ctx).pop(v),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text),
          child: Text(l10n.ok),
        ),
      ],
    ),
  );
  if (result != null && result.trim().isNotEmpty) {
    await context.read<LocalContentManager>().rename(e.id, result.trim());
  }
}

/// 删除本地导入条目：仅删记录，或连同磁盘文件（整个文件夹）一起删。
Future<void> deleteLocalEntry(BuildContext context, LocalContentEntry e) async {
  final l10n = AppLocalizations.of(context);
  final bool? choice = await showDialog<bool?>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.deleteConfirmTitle),
      content: Text(e.title),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.deleteRecordOnly),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.deleteRecordAndFile),
        ),
      ],
    ),
  );
  if (choice != null) {
    await context
        .read<LocalContentManager>()
        .remove(e.id, deleteFile: choice);
  }
}

/// 长按弹出的操作菜单（打开 / 重命名 / 删除）。
///
/// 用底部抽屉承载，符合应用弹层规范（[isScrollControlled] + 限高）。
void showLocalEntryActions(BuildContext context, LocalContentEntry e) {
    // MD3「Thunk」：长按呼出条目操作菜单。
    AppHaptics.thunk();
  final l10n = AppLocalizations.of(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.open_in_new_rounded),
            title: Text(l10n.contentImportOpened),
            onTap: () {
              Navigator.of(ctx).pop();
              openLocalEntry(context, e);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_rounded),
            title: Text(l10n.renameGroup),
            onTap: () {
              Navigator.of(ctx).pop();
              unawaited(renameLocalEntry(context, e));
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_rounded),
            title: Text(l10n.delete),
            onTap: () {
              Navigator.of(ctx).pop();
              unawaited(deleteLocalEntry(context, e));
            },
          ),
        ],
      ),
    ),
  );
}

/// 已下载完成任务的通用操作菜单（书架「本地」段：下载项用）。
///
/// 提供「打开 / 重命名 / 删除」，删除支持「仅删记录 / 记录+文件」。
/// [onOpen] 由调用方决定打开方式（本地阅读器 / 在线详情页）。
void showDownloadedEntryActions(
  BuildContext context,
  DownloadTask t, {
  required VoidCallback onOpen,
}) {
  // MD3「Thunk」：长按呼出条目操作菜单。
  AppHaptics.thunk();
  final l10n = AppLocalizations.of(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.open_in_new_rounded),
            title: Text(l10n.contentImportOpened),
            onTap: () {
              Navigator.of(ctx).pop();
              onOpen();
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_rounded),
            title: Text(l10n.renameGroup),
            onTap: () {
              Navigator.of(ctx).pop();
              unawaited(renameDownloadedEntry(context, t));
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_rounded),
            title: Text(l10n.delete),
            onTap: () {
              Navigator.of(ctx).pop();
              unawaited(confirmDeleteDownloaded(context, t));
            },
          ),
        ],
      ),
    ),
  );
}

/// 重命名已下载任务的显示标题（仅改记录，不动磁盘文件）。
Future<void> renameDownloadedEntry(BuildContext context, DownloadTask t) async {
  final l10n = AppLocalizations.of(context);
  final controller = TextEditingController(text: t.title);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.renameGroup),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(hintText: l10n.renameHint),
        autofocus: true,
        onSubmitted: (v) => Navigator.of(ctx).pop(v),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text),
          child: Text(l10n.ok),
        ),
      ],
    ),
  );
  if (result != null && result.trim().isNotEmpty) {
    await context
        .read<DownloadManager>()
        .renameCompleted(t.id, result.trim());
  }
}

/// 删除已下载任务前的二次确认（仅删记录 / 记录+文件）。
///
/// 「删除记录与文件」会连记录带整个作品文件夹（递归）一起删。
Future<void> confirmDeleteDownloaded(BuildContext context, DownloadTask t) async {
  final l10n = AppLocalizations.of(context);
  final bool? choice = await showDialog<bool?>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.deleteConfirmTitle),
      content: Text(t.title),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.deleteRecordOnly),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.deleteRecordAndFile),
        ),
      ],
    ),
  );
  if (choice != null) {
    await context
        .read<DownloadManager>()
        .removeCompleted(t.id, deleteFiles: choice);
  }
}
