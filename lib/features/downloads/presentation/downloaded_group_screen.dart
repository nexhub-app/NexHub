import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/download/download_manager.dart';
import '../../../core/download/download_task.dart';
import '../../../core/local/local_content_actions.dart'    show openDownloadedWorkFolder;
import '../../../core/local/local_content_manager.dart'
    show
        LocalMediaKind,
        isDocUri,
        listFolderFilesByKind,
        scanComicFolder;
import '../../../core/local/saf_bridge.dart'
    show safBaseName, listFolderFilesByKindSaf, scanComicFolderSaf;
import '../../../core/services/source_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_cover_image.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../home/presentation/local_media_viewer.dart';
import 'package:nexhub/core/widgets/app_alert_dialog.dart';

/// 已下载内容分组详情（下载页 → 点击合并作品）。
///
/// 同一部作品可能分多批下载，本页按 [contentId] + [sourceId] 聚合全部批次，
/// 头部展示合并信息（封面 / 标题 / 总章节数 / 批次数量），下方逐批列出各批次
/// 章节并可打开对应本地产物。根据 [DownloadFormat] 映射到 [LocalMediaKind]
/// 复用 [LocalMediaViewer]，避免重复造轮子。
class DownloadedGroupScreen extends StatefulWidget {
  final String contentId;
  final String? sourceId;
  const DownloadedGroupScreen({
    super.key,
    required this.contentId,
    this.sourceId,
  });

  @override
  State<DownloadedGroupScreen> createState() => _DownloadedGroupScreenState();
}

class _DownloadedGroupScreenState extends State<DownloadedGroupScreen> {
  String get contentId => widget.contentId;
  String? get sourceId => widget.sourceId;

  /// 扫描作品文件夹得到的实际内容文件（按文件名排序，每个文件 = 一章/一话/一集）。
  /// 不依赖下载记录（[DownloadTask.chapterFilePaths]），直接以磁盘为事实来源，
  /// 分批下载的所有内容都会出现在这里。
  List<String> _scanFiles = const <String>[];
  bool _scanning = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final manager = context.read<DownloadManager>();
    final batches = manager.tasksForContent(
      contentId,
      sourceId,
      includeArchived: false,
    );
    if (batches.isEmpty) return;
    final DownloadTask lead = batches.last;
    final LocalMediaKind kind = _kindFor(lead.format);
    final List<String> files = await _scanWorkDir(lead.localPath ?? '', kind);
    if (!mounted) return;
    setState(() {
      _scanFiles = files;
      _scanning = false;
    });
  }

  /// 扫描作品目录，按媒体类型过滤并排序（与「导入目录」用同一套扫描函数：
  /// [listFolderFilesByKind] / [listFolderFilesByKindSaf] 递归扫描，
  /// [scanComicFolder] / [scanComicFolderSaf] 区分散图/归档）。
  Future<List<String>> _scanWorkDir(String workDir, LocalMediaKind kind) async {
    if (workDir.isEmpty) return <String>[];
    switch (kind) {
      case LocalMediaKind.text:
        return isDocUri(workDir)
            ? await listFolderFilesByKindSaf(workDir, LocalMediaKind.text)
            : listFolderFilesByKind(workDir, LocalMediaKind.text);
      case LocalMediaKind.video:
        return isDocUri(workDir)
            ? await listFolderFilesByKindSaf(workDir, LocalMediaKind.video)
            : listFolderFilesByKind(workDir, LocalMediaKind.video);
      case LocalMediaKind.images:
      case LocalMediaKind.pdf:
        return _scanComic(workDir);
    }
  }

  /// 漫画：归档 + 其它非图片文件 = 每话一个（与导入目录一致）；仅散图时整个
  /// 文件夹作为一个条目（交给阅读器实时收集图片）。
  Future<List<String>> _scanComic(String workDir) async {
    if (isDocUri(workDir)) {
      final r = await scanComicFolderSaf(workDir);
      final chapterFiles = <String>[...r.archives, ...r.others];
      if (chapterFiles.isNotEmpty) return chapterFiles;
      return <String>[workDir];
    }
    final r = scanComicFolder(workDir);
    final chapterFiles = <String>[...r.archives, ...r.others];
    if (chapterFiles.isNotEmpty) return chapterFiles;
    return <String>[workDir];
  }

  /// 章节显示名：SAF 编码路径还原真实文件名后去扩展名。
  String _titleFor(String path) {
    final rawName = isDocUri(path) ? safBaseName(path) : path;
    final dot = rawName.lastIndexOf('.');
    final t = dot > 0 ? rawName.substring(0, dot) : rawName;
    return t.isEmpty ? path : t;
  }

  LocalMediaKind _kindFor(DownloadFormat f) => switch (f) {
        DownloadFormat.cbz => LocalMediaKind.images,
        DownloadFormat.folder => LocalMediaKind.images,
        DownloadFormat.jpg => LocalMediaKind.images,
        DownloadFormat.png => LocalMediaKind.images,
        DownloadFormat.epub => LocalMediaKind.text,
        DownloadFormat.txt => LocalMediaKind.text,
        DownloadFormat.video => LocalMediaKind.video,
      };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final manager = context.watch<DownloadManager>();
    final List<DownloadTask> batches = manager.tasksForContent(
      contentId,
      sourceId,
      includeArchived: false,
    );

    if (batches.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.downloadedContent)),
        body: const AppEmptyState(
          icon: Icons.download_done_rounded,
          message: '',
        ),
      );
    }

    // 合并信息：取最新批次的标题/封面/格式；章节数 = 扫描到的实际文件数。
    final DownloadTask lead = batches.last;
    final int totalChapters = _scanFiles.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(lead.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          AppIconButton(
            icon: Icons.delete_rounded,
            tooltip: l10n.delete,
            onPressed: () => _confirmDelete(context, manager, l10n),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.spaceLg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 110,
                    child: AppCoverImage(
                      coverUrl: lead.localCoverPath ?? lead.coverUrl,
                      source: (widget.sourceId?.isNotEmpty ?? false)
                          ? context
                              .read<SourceRepository>()
                              .getById(widget.sourceId!)
                          : null,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: AppTokens.spaceMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(lead.title,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: AppTokens.spaceSm),
                        Text(
                          '${l10n.downloadedGroupChapters}：$totalChapters',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                        const SizedBox(height: AppTokens.spaceXs),
                        Text(
                          '${l10n.downloadedGroupFormat}：${lead.format.label}',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                        if (batches.length > 1) ...<Widget>[
                          const SizedBox(height: AppTokens.spaceXs),
                          Text(
                            l10n.downloadBatches(batches.length),
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 扫描作品文件夹得到的实际文件列表（每个文件 = 一章/一话/一集）。
          if (_scanning)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_scanFiles.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  l10n.localFileLoadFailed,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final path = _scanFiles[i];
                  return AppListTile(
                    leading: CircleAvatar(
                      backgroundColor: scheme.primaryContainer,
                      foregroundColor: scheme.primary,
                      child: Text('${i + 1}'),
                    ),
                    title: Text(_titleFor(path),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: AppIconButton(
                      icon: Icons.open_in_new_rounded,
                      tooltip: l10n.downloadedGroupOpen,
                      onPressed: () => _open(context, lead, i),
                    ),
                  );
                },
                childCount: _scanFiles.length,
              ),
            ),
          SliverPadding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + AppTokens.spaceMd,
            ),
          ),
        ],
      ),
    );
  }

  /// 打开扫描出的某个内容文件（index 对齐 [_scanFiles]）。
  ///
  /// 不依赖下载记录（[DownloadTask.chapterFilePaths]），直接把作品文件夹交给
  /// [openDownloadedWorkFolder]：扫描磁盘实际文件构建完整章节/集/话列表，
  /// 保证分批下载 / 旧数据都能解析到全部内容并切换。
  Future<void> _open(BuildContext context, DownloadTask task, int index) async {
    final LocalMediaKind kind = _kindFor(task.format);
    final String workDir = task.localPath ?? '';
    if (workDir.isEmpty || !context.mounted) return;
    await openDownloadedWorkFolder(
      context,
      id: task.contentId,
      title: task.title,
      sourceId: task.sourceId ?? '',
      coverUrl: task.localCoverPath ?? task.coverUrl,
      workDir: workDir,
      kind: kind,
      initialIndex: index,
    );
  }

  /// SAF 视频：先把编码路径解析为真实缓存文件，校验有效性后，再交给全功能播放器打开。
  ///
  /// 直链写出 `.mp4`、HLS 拼接写出 `.ts`，打开时只能拿到按集序号（硬编码 `.mp4`），
  /// 故先枚举目录按 `NNN.<videoExt>` 命中真实扩展名；命中不到则退而求其次扫描
  /// 目录里任意视频文件，避免 HLS 的 `.ts` 被错当成不存在的 `.mp4` 而打开失败。
  ///
  /// 任何一步失败（解析不到 / 文件为空 / 不是有效视频）都**明确报错并弹提示**，
  /// 不再「点开无反应 / 无限缓冲」让用户摸不着头脑。
  Future<void> _confirmDelete(
    BuildContext context,
    DownloadManager manager,
    AppLocalizations l10n,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(l10n.delete),
        content: Text(l10n.downloadedGroupDeleteConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.deleteRecordAndFile),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await manager.cancelContent(contentId, deleteFiles: true);
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}
