/// 文件类书源（legado bookSourceType=3）的下载列表与本地书导入。
///
/// 对照 md3 `BookInfoViewModel.loadWebFile` / `handleWebFileSelection`：
/// 书籍文件直接落盘为「书名 作者：作者.后缀」并入库；归档下载后解压出
/// 小说文件，单条直接导入、多条弹出选择；其余格式提示未识别。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../../core/local/archive_extractor.dart'
    show extractNovelFilesFromArchive;
import '../../../core/local/local_content_actions.dart' show openLocalEntry;
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

/// 弹出下载列表；选中后下载、落盘、导入本地书并打开。
Future<void> openShuyuanWebFilePicker(
  BuildContext context, {
  required PluginConfig source,
  required String bookName,
  required String bookAuthor,
  required List<WebFileItem> files,
}) async {
  if (files.isEmpty) return;
  final AppLocalizations l10n = AppLocalizations.of(context);
  final WebFileItem? picked = await _pickFile(context, files, l10n);
  if (picked == null || !context.mounted) return;

  final MediaApiService service = context.read<MediaApiService>();
  final _WebFileImportStage stage;
  try {
    stage = await _runWithProgress(
      context,
      l10n,
      () => _downloadToLocal(
        service,
        source: source,
        picked: picked,
        bookName: bookName,
        bookAuthor: bookAuthor,
      ),
    );
  } on Object catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.importFailed('$e'))),
    );
    return;
  }
  if (!context.mounted) return;

  if (stage.isUnsupported) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.unrecognizedFile(picked.name))),
    );
    return;
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
  if (importPath == null || !context.mounted) return;

  await _registerAndOpen(context, importPath);
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

/// 入库并打开本地书（书名/作者按导出文件名解析）。
Future<void> _registerAndOpen(BuildContext context, String path) async {
  final String displayBase =
      webArchiveEntryDisplayName(p.basename(path));
  final ({String name, String? author}) parsed =
      LocalNovelParser.analyzeNameAuthor(displayBase);
  final LocalContentEntry entry = LocalContentEntry(
    id: path,
    title: parsed.name,
    path: path,
    kind: LocalMediaKind.text,
    addedAt: DateTime.now().millisecondsSinceEpoch,
    author: parsed.author,
  );
  await context.read<LocalContentManager>().add(entry);
  if (!context.mounted) return;
  await openLocalEntry(context, entry);
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
