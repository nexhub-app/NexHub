/// 文件类书源（legado bookSourceType=3）的文件下载、本地书导入与选择弹层。
///
/// 对照 md3 `BookInfoViewModel.loadWebFile` / `handleWebFileSelection`：
/// 书籍文件直接落盘为「书名 作者：作者.后缀」并入库；归档下载后解压出
/// 小说文件，单条直接导入、多条弹出选择；其余格式提示未识别。
/// 下载完成只入库不打开，由调用方（详情页）刷新文件列表后自行决定阅读。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../../core/local/archive_extractor.dart'
    show extractNovelFilesFromArchive;
import '../../../core/local/local_content_manager.dart'
    show LocalContentEntry, LocalContentManager, LocalMediaKind;
import '../../../core/local/local_novel_parser.dart' show LocalNovelParser;
import '../../../core/models/plugin_config.dart';
import '../../../core/models/web_file_item.dart';
import '../../../core/scraper/media_api_service.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../generated/app_localizations.dart';
import '../analyze/web_file_naming.dart';

/// 下载并导入结果：互斥的三种终态。
class _WebFileImportStage {
  const _WebFileImportStage.unsupported()
      : bookPath = null,
        archivePaths = null;

  const _WebFileImportStage.book(String path)
      : bookPath = path,
        archivePaths = null;

  const _WebFileImportStage.archive(List<String> paths)
      : bookPath = null,
        archivePaths = paths;

  final String? bookPath;
  final List<String>? archivePaths;

  bool get isUnsupported => bookPath == null && archivePaths == null;
}

/// 下载并入库源文件列表中的一项（不打开书籍，停留原页面）。
///
/// 返回入库的本地条目；取消归档内选择、格式未识别或下载失败返回 null
/// （失败与未识别均已用 SnackBar 提示）。下载成功后回显「已下载」提示。
Future<LocalContentEntry?> downloadShuyuanWebFile(
  BuildContext context, {
  required PluginConfig source,
  required String contentId,
  required String bookName,
  required String bookAuthor,
  required WebFileItem file,
}) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final MediaApiService service = context.read<MediaApiService>();
  final _WebFileImportStage stage;
  try {
    stage = await _runWithProgress(
      context,
      l10n,
      () => _downloadToLocal(
        service,
        source: source,
        picked: file,
        bookName: bookName,
        bookAuthor: bookAuthor,
      ),
    );
  } on Object catch (e) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.importFailed('$e'))),
    );
    return null;
  }
  if (!context.mounted) return null;

  if (stage.isUnsupported) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.unrecognizedFile(file.name))),
    );
    return null;
  }

  String? importPath = stage.bookPath;
  final List<String>? archivePaths = stage.archivePaths;
  if (importPath == null && archivePaths != null && archivePaths.isNotEmpty) {
    if (archivePaths.length == 1) {
      importPath = archivePaths.first;
    } else {
      final int? index = await _pickArchiveEntry(context, archivePaths, l10n);
      if (index != null && index >= 0 && index < archivePaths.length) {
        importPath = archivePaths[index];
      }
    }
  }
  if (importPath == null || !context.mounted) return null;

  final LocalContentEntry entry = await _registerEntry(
    context,
    importPath,
    originSourceId: source.id,
    originContentId: contentId,
    originFileUrl: file.url,
  );
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.sourceWebFileDownloaded(p.basename(importPath))),
      ),
    );
  }
  return entry;
}

/// 弹出文件列表并下载选中项；取消返回 null。
Future<LocalContentEntry?> pickAndDownloadShuyuanWebFile(
  BuildContext context, {
  required PluginConfig source,
  required String contentId,
  required String bookName,
  required String bookAuthor,
  required List<WebFileItem> files,
}) async {
  if (files.isEmpty) return null;
  final AppLocalizations l10n = AppLocalizations.of(context);
  final WebFileItem? picked = await _pickFile(context, files, l10n);
  if (picked == null || !context.mounted) return null;
  return downloadShuyuanWebFile(
    context,
    source: source,
    contentId: contentId,
    bookName: bookName,
    bookAuthor: bookAuthor,
    file: picked,
  );
}

/// 单文件尚未下载时的确认弹窗：确认返回 true。
Future<bool> confirmShuyuanWebFileDownload(
  BuildContext context, {
  required WebFileItem file,
}) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(l10n.download),
      content: Text(l10n.sourceWebFileDownloadPrompt(file.name)),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.download),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// 下载并把文件落到应用支持目录。
///
/// 书籍文件按「书名 作者：作者.后缀」命名；归档写入 `web_archives/`
/// 解压后删除归档本体（解压产物才是书库本体）。
Future<_WebFileImportStage> _downloadToLocal(
  MediaApiService service, {
  required PluginConfig source,
  required WebFileItem picked,
  required String bookName,
  required String bookAuthor,
}) async {
  final Uint8List bytes = await service.downloadWebFile(source, picked.url);
  final Directory support = await getApplicationSupportDirectory();
  final String name = picked.name;

  if (isWebBookFile(name)) {
    final String exportName = webBookExportName(
      bookName: bookName,
      author: bookAuthor,
      suffix: webFileSuffix(name),
    );
    final Directory dir =
        Directory(p.join(support.path, 'novel_imports', 'web_files'));
    await dir.create(recursive: true);
    final File target = File(p.join(dir.path, exportName));
    await target.writeAsBytes(bytes, flush: true);
    return _WebFileImportStage.book(target.path);
  }

  if (isWebArchiveFile(name)) {
    final Directory dir =
        Directory(p.join(support.path, 'novel_imports', 'web_archives'));
    await dir.create(recursive: true);
    final File archive =
        File(p.join(dir.path, sanitizeWebFileName(p.basename(name))));
    await archive.writeAsBytes(bytes, flush: true);
    try {
      final List<String> paths =
          await extractNovelFilesFromArchive(archive.path);
      return _WebFileImportStage.archive(paths);
    } finally {
      try {
        await archive.delete();
      } on Object {
        // 归档仅作解压中转，删除失败不影响已解压的书文件。
      }
    }
  }

  return const _WebFileImportStage.unsupported();
}

/// 入库本地书（书名/作者按导出文件名解析），并写入下载来源绑定。
Future<LocalContentEntry> _registerEntry(
  BuildContext context,
  String path, {
  required String originSourceId,
  required String originContentId,
  required String originFileUrl,
}) async {
  final String displayBase = webArchiveEntryDisplayName(p.basename(path));
  final ({String name, String? author}) parsed =
      LocalNovelParser.analyzeNameAuthor(displayBase);
  final LocalContentEntry entry = LocalContentEntry(
    id: path,
    title: parsed.name,
    path: path,
    kind: LocalMediaKind.text,
    addedAt: DateTime.now().millisecondsSinceEpoch,
    author: parsed.author,
    originSourceId: originSourceId,
    originContentId: originContentId,
    originFileUrl: originFileUrl,
  );
  await context.read<LocalContentManager>().add(entry);
  return entry;
}

Future<WebFileItem?> _pickFile(
  BuildContext context,
  List<WebFileItem> files,
  AppLocalizations l10n,
) {
  return showModalBottomSheet<WebFileItem>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.spaceMd,
              0,
              AppTokens.spaceMd,
              AppTokens.spaceSm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.sourceWebFilesTitle,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: files.length,
              itemBuilder: (BuildContext ctx, int i) {
                final WebFileItem f = files[i];
                final bool archive = isWebArchiveFile(f.name);
                return ListTile(
                  leading: Icon(
                    archive
                        ? Icons.folder_zip_rounded
                        : Icons.description_rounded,
                  ),
                  title: Text(
                    f.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.of(ctx).pop(f),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

/// 归档内多本书时选择一本（返回下标；取消为 null）。
Future<int?> _pickArchiveEntry(
  BuildContext context,
  List<String> paths,
  AppLocalizations l10n,
) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.spaceMd,
              0,
              AppTokens.spaceMd,
              AppTokens.spaceSm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.sourceWebFilesTitle,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: paths.length,
              itemBuilder: (BuildContext ctx, int i) => ListTile(
                leading: const Icon(Icons.menu_book_rounded),
                title: Text(
                  webArchiveEntryDisplayName(p.basename(paths[i])),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.of(ctx).pop(i),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// 下载/解压期间显示不可取消的进度弹层。
Future<T> _runWithProgress<T>(
  BuildContext context,
  AppLocalizations l10n,
  Future<T> Function() task,
) async {
  final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (BuildContext ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: <Widget>[
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: AppTokens.spaceMd),
            Expanded(child: Text(l10n.sourceWebFileImporting)),
          ],
        ),
      ),
    ),
  );
  try {
    return await task();
  } finally {
    // showDialog 同步压栈，任务再快也只会弹掉进度层本身。
    navigator.pop();
  }
}
