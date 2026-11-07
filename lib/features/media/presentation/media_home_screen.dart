import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/models/bookshelf_filter.dart';
import '../../../core/models/media_item.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/services/media_server/media_server_auth.dart';
import '../../../core/services/media_server/media_server_client.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/widgets/bookshelf_content.dart';
import '../../../core/local/local_content_actions.dart'
    show openDownloadedWorkFolder, openSearchResultEntry;
import '../../../core/local/local_content_manager.dart'
    show LocalMediaKind;
import '../../../core/widgets/library_shell.dart';
import '../../../core/widgets/module_source_search_screen.dart';
import '../../../core/widgets/online_source_browser_screen.dart';
import '../../home/presentation/import_media_screen.dart';
import '../../media_server/media_server_detail_screen.dart';
import '../../media_server/media_server_widgets.dart';
import '../../rss/presentation/rss_feed_list_screen.dart';
import '../../sources/presentation/collect_api_import_screen.dart';
import '../../sources/presentation/source_manager_screen.dart';
import '../../../core/navigation/app_navigator.dart';
import 'media_online_list_screen.dart';
import 'package:nexhub/core/navigation/app_page_route.dart';

/// Media module home — 4-tab layout backed by [LibraryShell].
///
/// The sources tab is rendered inline (source list + collect-API import FAB)
/// rather than pushing a separate [SourceManagerScreen].
class MediaHomeScreen extends StatelessWidget {
  const MediaHomeScreen({super.key});

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
      libraryTabLabel: l10n.tabMediaLibrary,
      emptyIcon: Icons.movie_rounded,
      emptyMessage: l10n.emptyLocalMedia,
      emptyActionLabel: l10n.emptyLocalMediaAction,
      onEmptyAction: () => Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (_) => const ImportMediaScreen(),
        ),
      ),
      onSearch: () => Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (_) => ModuleSourceSearchScreen(
            sourceType: SourceType.animeSource,
            title: l10n.search,
            // 搜索结果含本地内容（导入/下载），本地条目直接进本地播放器，
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
        sourceType: SourceType.animeSource,
        subTab: subTab,
        filter: filter,
        emptyIcon: Icons.movie_rounded,
        emptyMessage: l10n.emptyLocalMedia,
        emptyActionLabel: l10n.emptyLocalMediaAction,
        onEmptyAction: () => Navigator.of(context).push(
          AppPageRoute<void>(
            builder: (_) => const ImportMediaScreen(),
          ),
        ),
        onItemTap: (MediaItem item) async {
          // 媒体服务器历史条目（detailUrl = ms:<serverId>:<itemId>）
          // 按凭据路由到对应详情页；服务器已删除时提示不可达。
          if (item.detailUrl?.startsWith('ms:') == true) {
            final parts = item.detailUrl!.split(':');
            if (parts.length >= 3) {
              final serverId = parts[1];
              final itemId = parts.sublist(2).join(':');
              final auth = context.read<MediaServerAuth>();
              final server = auth.servers
                  .where((s) => s.id == serverId)
                  .firstOrNull;
              if (server == null || !server.loggedIn) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.mediaServerUnreachable)),
                );
                return;
              }
              final token = await auth.tokenOf(server.id);
              final deviceId = await auth.deviceId();
              if (!context.mounted) return;
              Navigator.of(context).push(
                AppPageRoute<void>(
                  builder: (_) => MediaServerDetailScreen(
                    client: MediaServerClientBase.createServerClient(
                      server,
                      deviceId: deviceId,
                      token: token,
                    ),
                    itemId: itemId,
                  ),
                ),
              );
              return;
            }
          }
          // 修复（影视段）：本地导入/下载的视频优先走本地播放，不跳在线详情页。
          final extra = item.extra;
          final localPath = extra == null ? null : extra['localPath'] as String?;
          final localKind = extra == null ? null : extra['localKind'] as String?;
          // 已下载视频 / 本地视频目录：直接扫描作品文件夹（与导入目录同一套扫描），
          // 多集都能解析全部内容、可上下集切换；单文件导入回退单集播放。
          if (localPath != null && localPath.isNotEmpty && localKind == 'video') {
            await openDownloadedWorkFolder(
              context,
              id: item.id,
              title: item.title,
              sourceId: item.sourceId ?? '',
              workDir: localPath,
              kind: LocalMediaKind.video,
            );
            return;
          }
          AppNavigator.openContentDetail(context, item: item);
        },
      ),
      onlineBody: Consumer<MediaServerAuth>(
        builder: (context, mediaServerAuth, _) => OnlineSourceBrowserScreen(
          sourceType: SourceType.animeSource,
          // 每台已配置服务器一个入口行；未配置时列表完全隐藏（不占位）。
          mediaServerTiles: <Widget>[
            for (final s in mediaServerAuth.servers)
              MediaServerBrowseTile(server: s),
          ],
          onAddSource: navigateToCollectApiImport,
          onEnableRecommended:
              () => context.read<SourceRepository>().enableRecommendedSources(),
          onSourceTap: (PluginConfig source) => Navigator.of(context).push(
            AppPageRoute<void>(
              builder: (_) => MediaOnlineListScreen(
                initialSource: source,
                onAddSource: navigateToCollectApiImport,
                onEnableRecommended: () =>
                    context.read<SourceRepository>().enableRecommendedSources(),
              ),
            ),
          ),
        ),
      ),
      subscribeBody:
          const RssFeedListScreen(moduleType: SourceType.animeSource),
      sourcesBody: const _MediaSourcesBody(
        filterType: SourceType.animeSource,
        mediaServerSection: MediaServerSourceSection(),
      ),
      categoryProvider: (LibrarySubTab subTab) =>
          BookshelfContent.categoriesFor(
              context, SourceType.animeSource, subTab),
      historySourceType: SourceType.animeSource,
      favoriteSourceType: SourceType.animeSource,
    );
  }
}

class _MediaSourcesBody extends StatelessWidget {
  final SourceType filterType;

  /// 源列表顶部的媒体服务器配置区块（仅影视模块）。
  final MediaServerSourceSection? mediaServerSection;

  const _MediaSourcesBody({
    required this.filterType,
    this.mediaServerSection,
  });

  @override
  Widget build(BuildContext context) {
    return SourceManagerScreen(
      filterType: filterType,
      embedded: true,
      mediaServerSection: mediaServerSection,
    );
  }
}
