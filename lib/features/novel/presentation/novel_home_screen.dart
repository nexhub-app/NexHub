import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/local/local_content_manager.dart';
import '../../../core/local/local_content_actions.dart';
import '../../../core/models/bookshelf_filter.dart';
import '../../../core/models/media_item.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/widgets/bookshelf_content.dart';
import '../../../core/widgets/library_shell.dart';
import '../../../core/widgets/module_source_search_screen.dart';
import '../../../core/widgets/online_source_browser_screen.dart';
import '../../home/presentation/import_novel_screen.dart';
import '../../rss/presentation/rss_feed_list_screen.dart';
import '../../sources/presentation/collect_api_import_screen.dart';
import '../../sources/presentation/source_manager_screen.dart';
import '../../../core/navigation/app_navigator.dart';
import 'novel_online_list_screen.dart';
import 'package:nexhub/core/navigation/app_page_route.dart';

/// Novel module home — 4-tab layout backed by [LibraryShell].
///
/// The sources tab is rendered inline (source list + collect-API import FAB)
/// rather than pushing a separate [SourceManagerScreen].
class NovelHomeScreen extends StatelessWidget {
  const NovelHomeScreen({super.key});

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
      emptyIcon: Icons.menu_book_rounded,
      emptyMessage: l10n.emptyLocalNovel,
      emptyActionLabel: l10n.emptyLocalNovelAction,
      onEmptyAction: () => Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (_) => const ImportNovelScreen(),
        ),
      ),
      onSearch: () => Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (_) => ModuleSourceSearchScreen(
            sourceType: SourceType.novelSource,
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
        sourceType: SourceType.novelSource,
        subTab: subTab,
        filter: filter,
        emptyIcon: Icons.menu_book_rounded,
        emptyMessage: l10n.emptyLocalNovel,
        emptyActionLabel: l10n.emptyLocalNovelAction,
        onEmptyAction: () => Navigator.of(context).push(
          AppPageRoute<void>(
            builder: (_) => const ImportNovelScreen(),
          ),
        ),
        onItemTap: (MediaItem item) async {
          // 修复（小说段）：本地导入/下载的小说优先走本地阅读，不跳在线详情页。
          final extra = item.extra;
          final localPath = extra == null ? null : extra['localPath'] as String?;
          final localKind = extra == null ? null : extra['localKind'] as String?;
          final filePaths =
              extra == null ? null : extra['filePaths'] as List<String>?;
          // B 阶段：聚合文件夹（多文件=多章），复用统一路由进入阅读器（目录/上下章可用）。
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
          // 已下载小说：作品文件夹即内容，直接扫描文件夹（与导入目录同一套扫描），
          // 逐章 .txt / 整本 epub 都能解析全部内容、可切换章节；也覆盖本地单文件导入。
          if (localPath != null && localPath.isNotEmpty && localKind == 'text') {
            await openDownloadedWorkFolder(
              context,
              id: item.id,
              title: item.title,
              sourceId: item.sourceId ?? '',
              coverUrl: item.coverUrl,
              workDir: localPath,
              kind: LocalMediaKind.text,
            );
            return;
          }
          AppNavigator.openContentDetail(context, item: item);
        },
      ),
      onlineBody: OnlineSourceBrowserScreen(
        sourceType: SourceType.novelSource,
        onAddSource: navigateToCollectApiImport,
        onEnableRecommended:
            () => context.read<SourceRepository>().enableRecommendedSources(),
        onSourceTap: (PluginConfig source) => Navigator.of(context).push(
          AppPageRoute<void>(
            builder: (_) => NovelOnlineListScreen(
              initialSource: source,
              onAddSource: navigateToCollectApiImport,
              onEnableRecommended:
                  () => context.read<SourceRepository>().enableRecommendedSources(),
            ),
          ),
        ),
      ),
      subscribeBody:
          const RssFeedListScreen(moduleType: SourceType.novelSource),
      sourcesBody: const _NovelSourcesBody(
        filterType: SourceType.novelSource,
      ),
      categoryProvider: (LibrarySubTab subTab) =>
          BookshelfContent.categoriesFor(
              context, SourceType.novelSource, subTab),
      historySourceType: SourceType.novelSource,
      favoriteSourceType: SourceType.novelSource,
    );
  }
}

class _NovelSourcesBody extends StatelessWidget {
  final SourceType filterType;

  const _NovelSourcesBody({
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
