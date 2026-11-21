import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/local/local_content_actions.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/scraper/media_api_service.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/widgets/module_source_search_screen.dart';
import '../../../core/widgets/online_content_list_screen.dart';
import '../../verification/presentation/verification_handler.dart';
import '../../../core/navigation/app_navigator.dart';
import 'package:nexhub/core/navigation/app_page_route.dart';

/// 小说在线浏览页（Phase 2）。
///
/// 复用通用 [OnlineContentListScreen]，仅配置源类型与点击行为，不重复实现列表 UI。
class NovelOnlineListScreen extends StatelessWidget {
  const NovelOnlineListScreen(
      {super.key,
      this.initialSource,
      this.initialCategoryUrl,
      this.initialCategoryTitle,
      this.onAddSource});

  final PluginConfig? initialSource;
  final String? initialCategoryUrl;
  final String? initialCategoryTitle;
  final VoidCallback? onAddSource;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<SourceRepository>();
    final service = context.read<MediaApiService>();
    final sources = repo.byType(SourceType.novelSource);
    final l10n = AppLocalizations.of(context);

    return OnlineContentListScreen(
      title: 'novel',
      sources: sources,
      initialSource: initialSource,
      initialCategoryUrl: initialCategoryUrl,
      initialCategoryTitle: initialCategoryTitle,
      onAddSource: onAddSource,
      verificationHandler: handleVerificationRequest,
      emptyIcon: Icons.menu_book_rounded,
      fetchItems: (PluginConfig source,
              {String? category,
              int page = 1,
              String? extractedUrl,
              String? renderedHtml,
              Map<String, String> vars = const <String, String>{}}) =>
          service.fetchApiResults(
        source,
        MediaApiService.routeForCategory(source, category),
        extractedUrl: extractedUrl,
        renderedHtml: renderedHtml,
        vars: <String, String>{
          'page': '$page',
          if (category != null) 'category': category,
          ...vars,
        },
      ),
      fetchCategories: service.fetchCategories,
      resolveHomeSections: service.resolveHomeSections,
      resolveFilters: service.resolveFilterGroups,
      onItemTap: (item, heroTag) => AppNavigator.openContentDetail(
        context,
        item: item,
        heroTag: heroTag,
      ),
      // 搜索按钮：默认只勾选进入搜索页面的源（当前在线浏览的源）。
      onSearch: (PluginConfig? current) => Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (_) => ModuleSourceSearchScreen(
            sourceType: SourceType.novelSource,
            title: l10n.search,
            startSingle: current != null,
            initialSourceId: current?.id,
            // 搜索结果含本地内容（导入/下载），本地条目直接进本地阅读器。
            onItemTap: (item, heroTag) => openSearchResultEntry(
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
    );
  }
}
