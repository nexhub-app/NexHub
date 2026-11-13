/// 全局 RSS 站内搜索 —— 一次搜索所有已订阅源的文章（-5）。
///
/// 数据来源：各订阅源的本地条目缓存（`rss_feed_cache_v1`，由 [RssArticleStore] 维护）。
/// 即「搜已加载过的内容」，离线也能用；未抓取过的源不会出现命中（引导用户先打开该源）。
///
/// 与 feed 详情页的「本源搜索」互补：本页是跨源汇总，详情页是单源内过滤。
/// 列表排版与订阅源详情页共享同一套样式与偏好（rss_article_tiles）。
library;

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/core/comic/models/reader_preferences.dart'
    show PrefsBackend, SharedPrefsBackend;
import 'package:nexhub/core/navigation/app_page_route.dart';
import 'package:nexhub/core/theme/app_tokens.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:nexhub/core/rss/rss_article_store.dart';
import 'package:nexhub/core/rss/rss_feed.dart';
import 'package:nexhub/core/rss/rss_manager.dart';
import 'package:nexhub/core/widgets/app_animations.dart';
import 'package:nexhub/core/widgets/app_empty_state.dart';
import 'package:nexhub/core/widgets/app_search_field.dart';
import 'package:provider/provider.dart';

import '../../home/presentation/browse_article_detail_screen.dart';
import 'rss_article_tiles.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/app_glass_bar.dart';

/// 一条聚合搜索结果：来自哪个订阅源 + 哪篇文章。
class _SearchHit {
  final RssFeed feed;
  final RssItem item;
  const _SearchHit({required this.feed, required this.item});
}

class RssSearchScreen extends StatefulWidget {
  const RssSearchScreen({super.key});

  @override
  State<RssSearchScreen> createState() => _RssSearchScreenState();
}

class _RssSearchScreenState extends State<RssSearchScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final PrefsBackend _prefsBackend = const SharedPrefsBackend();
  String _query = '';
  bool _loading = true;
  List<_SearchHit> _all = const <_SearchHit>[];
  int _listLayout = RssListLayoutMode.list;

  @override
  void initState() {
    super.initState();
    _loadLayout();
    _buildIndex();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadLayout() async {
    final int mode = await RssListLayoutMode.load(_prefsBackend);
    if (mounted) setState(() => _listLayout = mode);
  }

  Future<void> _setLayout(int mode) async {
    if (_listLayout == mode) return;
    setState(() => _listLayout = mode);
    await RssListLayoutMode.save(_prefsBackend, mode);
  }

  /// 聚合所有订阅源的本地缓存条目（一次性建内存索引）。
  Future<void> _buildIndex() async {
    setState(() => _loading = true);
    final manager = context.read<RssManager>();
    await RssArticleStore.instance.init();
    final hits = <_SearchHit>[];
    for (final feed in manager.feeds) {
      for (final item in RssArticleStore.instance.getFeedItems(feed.id)) {
        hits.add(_SearchHit(feed: feed, item: item));
      }
    }
    if (mounted) {
      setState(() {
        _all = hits;
        _loading = false;
      });
    }
  }

  List<_SearchHit> get _results {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all.where((h) {
      final hay = '${h.item.title} ${_stripHtml(h.item.description ?? '')} '
              '${h.feed.title}'
          .toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  String _stripHtml(String html) => html
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// 相对封面地址按文章页绝对化（与详情页一致，否则相对地址加载不出）。
  String _abs(String raw, String baseUrl) {
    final Uri? base = Uri.tryParse(baseUrl);
    if (base == null) return raw;
    return base.resolve(raw).toString();
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Future<void> _toggleFavorite(_SearchHit hit) async {
    // MD3「Toggle」：文章收藏开关切换 → tick。
    RssArticleStore.instance.isFavorite(hit.feed.id, hit.item)
        ? AppHaptics.toggleOff()
        : AppHaptics.toggleOn();
    await RssArticleStore.instance.toggleFavorite(hit.feed.id, hit.item);
    if (mounted) setState(() {});
  }

  /// 打开命中文章并携带结果列表作为上下篇导航上下文。
  Future<void> _open(
      _SearchHit hit, int index, List<_SearchHit> results) async {
    final navItems = results.map<RssItem>((h) => h.item).toList();
    await RssArticleStore.instance.markRead(hit.feed.id, hit.item);
    final content =
        RssArticleStore.instance.getContent(hit.feed.id, hit.item) ??
            hit.item.content;
    if (!mounted) return;
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => BrowseArticleDetailScreen(
          item: hit.item.copyWith(content: content),
          feedId: hit.feed.id,
          contextItems: navItems,
          contextIndex: index,
        ),
      ),
    );
    if (hit.feed.autoFetchFullText) {
      RssArticleStore.instance.fetchFullText(hit.feed.id, hit.item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final results = _results;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.rssSearchTitle),
        actions: <Widget>[
          RssListLayoutAction(layout: _listLayout, onSelected: _setLayout),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.spaceMd,
              AppTokens.spaceSm,
              AppTokens.spaceMd,
              AppTokens.spaceXs,
            ),
            child: AppSearchField(
              controller: _ctrl,
              hint: l10n.rssSearchHint,
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _ctrl.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceMd,
              vertical: AppTokens.spaceXxs,
            ),
            child: Row(
              children: <Widget>[
                Text(
                  _loading
                      ? l10n.rssSearchBuilding
                      : l10n.rssSearchCount(results.length, _all.length),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(l10n.retry),
                  onPressed: _buildIndex,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : results.isEmpty
                    ? AppEmptyState(
                        icon: Icons.search_off_rounded,
                        message: _query.trim().isNotEmpty
                            ? l10n.rssSearchNoResult
                            : l10n.rssSearchEmpty,
                      )
                    : ListView.separated(
                        padding: context.pageInset(AppTokens.spaceMd),
                        itemCount: results.length,
                        separatorBuilder: (_, __) =>
                            _listLayout == RssListLayoutMode.list
                                ? const Divider(height: 1)
                                : const SizedBox.shrink(),
                        itemBuilder: (_, i) {
                          final hit = results[i];
                          final store = RssArticleStore.instance;
                          return Entrance(
                            index: i < 8 ? i : 8,
                            onceKey: 'rsssrch:${hit.feed.id}:${hit.item.url}',
                            child: buildRssArticleTile(
                              context,
                              _listLayout,
                              RssArticleTileData(
                                item: hit.item,
                                read: store.isRead(hit.feed.id, hit.item),
                                favorite:
                                    store.isFavorite(hit.feed.id, hit.item),
                                coverUrl: hit.item.coverUrl != null &&
                                        hit.item.url.isNotEmpty
                                    ? _abs(hit.item.coverUrl!, hit.item.url)
                                    : hit.item.coverUrl,
                                excerpt: _stripHtml(hit.item.description ?? ''),
                                sourceLabel: hit.feed.title,
                                dateText: hit.item.publishedAt != null
                                    ? _formatDate(hit.item.publishedAt!)
                                    : null,
                                onOpen: () => _open(hit, i, results),
                                onToggleFavorite: () => _toggleFavorite(hit),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
