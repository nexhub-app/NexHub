import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/local/local_content_manager.dart';
import '../../../core/local/local_content_actions.dart';
import '../../../core/models/bookshelf_filter.dart';
import '../../../core/models/media_item.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/navigation/app_navigator.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/widgets/bookshelf_content.dart';
import '../../../core/widgets/library_shell.dart';
import '../../../core/widgets/module_source_search_screen.dart';
import '../../../core/widgets/online_source_browser_screen.dart';
import '../../home/presentation/import_comic_screen.dart';
import '../../rss/presentation/rss_feed_list_screen.dart';
import '../../sources/presentation/collect_api_import_screen.dart';
import '../../sources/presentation/source_manager_screen.dart';
import 'manga_online_list_screen.dart';
import 'package:nexhub/core/navigation/app_page_route.dart';

/// Comic module home — 4-tab layout backed by [LibraryShell].
///
/// The sources tab is rendered inline (source list + collect-API import FAB)
/// rather than pushing a separate [SourceManagerScreen].
class ComicHomeScreen extends StatelessWidget {
  const ComicHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    void navigateToCollectApiImport() {
      Navigator.of(context).push(AppPageRoute<void>(
        builder: (_) => const CollectApiImportScreen(),
      ));
    }

    return LibraryShell(
      title: l10n.tabLibrary,
      emptyIcon: Icons.auto_stories_rounded,
      emptyMessage: l10n.emptyLocalComic,
      emptyActionLabel: l10n.emptyLocalComicAction,
      onEmptyAction: () => Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (_) => const ImportComicScreen(),
        ),
      ),
      onSearch: () => Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (_) => ModuleSourceSearchScreen(
            sourceType: SourceType.mangaSource,
            title: l10n.search,
            // 搜索结果含本地内容（导入/下载），本地条目直接进本地阅读器，
            // 在线条目照旧跳详情页。
            onItemTap: (MediaItem item, String? heroTag) =>
                openSearchResultEntry(
              context,
              item: item,
              heroTag: heroTag,
              onOnline: (it, tag) => AppNavigator.openContentDetail(
                context,
                item: it,
                heroTag: tag,
              ),
            ),
          ),
        ),
      ),
      libraryBodyBuilder: (LibrarySubTab subTab, BookshelfFilter filter) => BookshelfContent(
        sourceType: SourceType.mangaSource,
        subTab: subTab,
        filter: filter,
        emptyIcon: Icons.auto_stories_rounded,
        emptyMessage: l10n.emptyLocalComic,
        emptyActionLabel: l10n.emptyLocalComicAction,
        onEmptyAction: () => Navigator.of(context).push(
          AppPageRoute<void>(
            builder: (_) => const ImportComicScreen(),
          ),
        ),
        onItemTap: (MediaItem item) async {
          // 修复：本地导入/下载的漫画优先走阅读器本地模式，不再误跳在线详情页。
          final extra = item.extra;
          final localPath = extra == null ? null : extra['localPath'] as String?;
          final localKind = extra == null ? null : extra['localKind'] as String?;
          final filePaths =
              extra == null ? null : extra['filePaths'] as List<String>?;
          // B 阶段：聚合文件夹（多文件=多话），复用统一路由进入阅读器（目录/上下话可用）。
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
          // 已下载漫画 / 本地漫画目录：直接扫描作品文件夹（与导入目录同一套扫描），
          // 多话归档 / 散图都能解析全部内容、可切换话；也覆盖本地单文件导入。
          if (localPath != null && localPath.isNotEmpty) {
            final LocalMediaKind? kind = parseLocalMediaKind(localKind);
            if (kind == LocalMediaKind.images ||
                kind == LocalMediaKind.pdf) {
              await openDownloadedWorkFolder(
                context,
                id: item.id,
                title: item.title,
                sourceId: item.sourceId ?? '',
                coverUrl: item.coverUrl,
                workDir: localPath,
                kind: kind!,
              );
              return;
            }
          }
          AppNavigator.openContentDetail(context, item: item);
        },
      ),
      onlineBody: OnlineSourceBrowserScreen(
        sourceType: SourceType.mangaSource,
        onAddSource: navigateToCollectApiImport,
        onEnableRecommended:
            () => context.read<SourceRepository>().enableRecommendedSources(),
        onSourceTap: (PluginConfig source) => Navigator.of(context).push(
          AppPageRoute<void>(
            builder: (_) => MangaOnlineListScreen(
              initialSource: source,
              onAddSource: navigateToCollectApiImport,
              onEnableRecommended:
                  () => context.read<SourceRepository>().enableRecommendedSources(),
            ),
          ),
        ),
      ),
      subscribeBody:
          const RssFeedListScreen(moduleType: SourceType.mangaSource),
      sourcesBody: const _ComicSourcesBody(
        filterType: SourceType.mangaSource,
      ),
      categoryProvider: (LibrarySubTab subTab) =>
          BookshelfContent.categoriesFor(
              context, SourceType.mangaSource, subTab),
      historySourceType: SourceType.mangaSource,
      favoriteSourceType: SourceType.mangaSource,
    );
  }
}

class _ComicSourcesBody extends StatelessWidget {
  final SourceType filterType;

  const _ComicSourcesBody({
    required this.filterType,
  });

  @override
  Widget build(BuildContext context) {
    return SourceManagerScreen(
      filterType: filterType,
      embedded: true,
    );
  }
}
