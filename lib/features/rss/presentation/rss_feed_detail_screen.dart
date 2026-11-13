/// RSS 订阅源详情页——展示某订阅源的条目列表（文档 + -3）。
///
/// 改造点（-3）：
/// - 抓取成功后写入本地条目缓存（断网也能看列表）；失败时回退离线缓存。
/// - 点开文章自动标记已读，并后台抓取全文缓存（之后可离线读）。
/// - 每篇可收藏（星标切换）；已读整条置灰。
/// - 顶部「全部标为已读」+ 筛选（全部 / 未读 / 收藏）。
library;

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:nexhub/core/navigation/app_page_route.dart';

import '../../../core/rss/rss_feed.dart';
import '../../../core/rss/rss_manager.dart';
import '../../../core/rss/rss_article_store.dart';
import '../../../core/comic/models/reader_preferences.dart'
    show PrefsBackend, SharedPrefsBackend;
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/app_animations.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_error_state.dart';
import '../../../core/widgets/app_loading_indicator.dart';
import '../../../core/widgets/app_refresh_indicator.dart';
import '../../../core/widgets/app_search_field.dart';
import '../../home/presentation/browse_article_detail_screen.dart';
import 'rss_article_tiles.dart';
import '../../../core/widgets/app_glass_bar.dart';

enum _RssFilter { all, unread, favorites }

class RssFeedDetailScreen extends StatefulWidget {
  final RssFeed feed;

  const RssFeedDetailScreen({super.key, required this.feed});

  @override
  State<RssFeedDetailScreen> createState() => _RssFeedDetailScreenState();
}

class _RssFeedDetailScreenState extends State<RssFeedDetailScreen> {
  ParsedFeed? _parsed;
  bool _loading = true;
  bool _offline = false;
  String? _error;
  _RssFilter _filter = _RssFilter.all;
  String _query = '';
  final TextEditingController _searchCtrl = TextEditingController();

  /// 订阅列表排版样式（RssListLayoutMode：0=列表 / 1=卡片 / 2=紧凑 / 3=大图）。
  int _listLayout = RssListLayoutMode.list;

  /// 排序模式（RssSortMode：0=源顺序（最新在前）/ 1=最旧在前 / 2=未读优先）。
  int _sortMode = 0;

  final RssArticleStore _store = RssArticleStore.instance;
  final PrefsBackend _prefsBackend = const SharedPrefsBackend();
  static const String _sortModeKey = 'rss_sort_mode_v1';

  @override
  void initState() {
    super.initState();
    _loadListLayout();
    _loadSortMode();
    _loadFeed();
  }

  Future<void> _loadSortMode() async {
    try {
      final v = await _prefsBackend.get(_sortModeKey);
      final parsed = v == null ? null : int.tryParse(v);
      if (parsed != null && mounted) setState(() => _sortMode = parsed);
    } on Object {
      // 读取失败忽略，回退默认排序。
    }
  }

  Future<void> _setSortMode(int mode) async {
    if (_sortMode == mode) return;
    setState(() => _sortMode = mode);
    try {
      await _prefsBackend.set(_sortModeKey, mode.toString());
    } on Object {
      // 持久化失败忽略，内存态已生效。
    }
  }

  Future<void> _loadListLayout() async {
    final int mode = await RssListLayoutMode.load(_prefsBackend);
    if (mounted) setState(() => _listLayout = mode);
  }

  Future<void> _setListLayout(int mode) async {
    if (_listLayout == mode) return;
    setState(() => _listLayout = mode);
    await RssListLayoutMode.save(_prefsBackend, mode);
  }

  /// 按文章页地址把相对/协议相对封面地址绝对化（卡片缩略图用）。
  String _absUrl(String raw, String baseUrl) {
    final Uri? base = Uri.tryParse(baseUrl);
    if (base == null) return raw;
    return base.resolve(raw).toString();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFeed() async {
    final manager = context.read<RssManager>();
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _offline = false;
      });
    }
    await _store.init();
    // 旧内容优先缓存到本地（除非在详情页面刷新）：有缓存先立即展示，
    // 避免慢网/断网时列表空白；随后后台刷新替换为最新内容。
    final cached = _store.getFeedItems(widget.feed.id);
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _parsed = ParsedFeed(title: widget.feed.title, items: cached);
        _loading = false;
      });
    }
    try {
      final result = await manager.fetchFeed(widget.feed);
      if (mounted) {
        await _store.cacheFeed(widget.feed.id, result.items);
        setState(() {
          _parsed = result;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        if (_parsed != null) {
          // 已有缓存展示中（可能正是上面刚展示的）：保持，仅标记离线态。
          setState(() => _offline = true);
        } else {
          final cached = _store.getFeedItems(widget.feed.id);
          if (cached.isNotEmpty) {
            setState(() {
              _parsed = ParsedFeed(title: widget.feed.title, items: cached);
              _loading = false;
              _offline = true;
            });
          } else {
            setState(() {
              _error = e.toString();
              _loading = false;
            });
          }
        }
      }
    }
  }

  List<RssItem> get _visibleItems {
    final items = _parsed?.items ?? const <RssItem>[];
    final filtered = switch (_filter) {
      _RssFilter.all => items,
      _RssFilter.unread =>
        items.where((i) => !_store.isRead(widget.feed.id, i)).toList(),
      _RssFilter.favorites =>
        items.where((i) => _store.isFavorite(widget.feed.id, i)).toList(),
    };
    final q = _query.trim().toLowerCase();
    final matched = q.isEmpty
        ? filtered
        // 站内搜索：标题或摘要含关键字（忽略大小写与 HTML 标签）。
        : filtered.where((i) {
            final hay =
                '${i.title} ${_stripHtml(i.description ?? '')}'.toLowerCase();
            return hay.contains(q);
          }).toList();
    return _applySort(matched);
  }

  /// 排序：0=源顺序（feed 通常最新在前） / 1=最旧在前 / 2=未读优先（组内保序）。
  /// publishedAt 为空的条目按「最旧」处理（沉底），避免 null 比较异常。
  List<RssItem> _applySort(List<RssItem> items) {
    switch (_sortMode) {
      case 1:
        final sorted = List<RssItem>.of(items);
        sorted.sort((a, b) {
          final aa = a.publishedAt;
          final bb = b.publishedAt;
          if (aa == null && bb == null) return 0;
          if (aa == null) return 1;
          if (bb == null) return -1;
          return aa.compareTo(bb);
        });
        return sorted;
      case 2:
        final unread = <RssItem>[];
        final read = <RssItem>[];
        for (final i in items) {
          (_store.isRead(widget.feed.id, i) ? read : unread).add(i);
        }
        return <RssItem>[...unread, ...read];
      case 0:
      default:
        return items;
    }
  }

  Future<void> _onOpen(RssItem item) async {
    // 导航上下文取打开时刻的可见列表（未读筛选下按所见顺序连读）。
    final navItems = List<RssItem>.of(_visibleItems);
    final navIndex = navItems.indexOf(item);
    await _store.markRead(widget.feed.id, item);
    final content = _store.getContent(widget.feed.id, item) ?? item.content;
    if (mounted) {
      setState(() {}); // 反映已读置灰（返回后可见）
      Navigator.of(context).push(
        AppPageRoute<void>(
          builder: (_) => BrowseArticleDetailScreen(
            item: item.copyWith(content: content),
            feedId: widget.feed.id,
            contextItems: navItems,
            contextIndex: navIndex,
          ),
        ),
      );
    }
    // 后台抓取全文并缓存，下次离线可读（按源开关控制）。
    if (widget.feed.autoFetchFullText) {
      _store.fetchFullText(widget.feed.id, item);
    }
  }

  Future<void> _onToggleFavorite(RssItem item) async {
    // MD3「Toggle」：文章收藏开关切换 → tick。
    _store.isFavorite(widget.feed.id, item)
        ? AppHaptics.toggleOff()
        : AppHaptics.toggleOn();
    final fav = await _store.toggleFavorite(widget.feed.id, item);
    if (mounted) {
      setState(() {});
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                fav ? l10n.rssArticleFavorited : l10n.rssArticleUnfavorited)),
      );
    }
  }

  Future<void> _onMarkAllRead() async {
    final items = _parsed?.items ?? const <RssItem>[];
    if (items.isEmpty) return;
    await _store.markAllRead(widget.feed.id, items);
    if (mounted) {
      setState(() {});
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.rssMarkedAllRead)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final manager = context.watch<RssManager>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.feed.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.done_all_rounded),
            tooltip: l10n.rssMarkAllRead,
            onPressed: _onMarkAllRead,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: l10n.retry,
            onPressed: _loadFeed,
          ),
          // 按源开关：打开文章时自动抓取原站全文（手动「拉取网站解析」不受限）。
          IconButton(
            icon: Icon(
              Icons.read_more_rounded,
              color: widget.feed.autoFetchFullText
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
            ),
            tooltip: l10n.rssAutoFetchFullText,
            onPressed: () async {
              AppHaptics.selectionClick();
              await manager.updateFeed(
                widget.feed.copyWith(
                  autoFetchFullText: !widget.feed.autoFetchFullText,
                ),
              );
              if (mounted) setState(() {});
            },
          ),
          // 列表排序：最新在前 / 最旧在前 / 未读优先。
          PopupMenuButton<int>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: l10n.rssSort,
            onSelected: _setSortMode,
            itemBuilder: (BuildContext context) => <PopupMenuEntry<int>>[
              for (final e in <MapEntry<int, String>>[
                MapEntry(0, l10n.rssSortNewest),
                MapEntry(1, l10n.rssSortOldest),
                MapEntry(2, l10n.rssSortUnreadFirst),
              ])
                PopupMenuItem<int>(
                  value: e.key,
                  child: Row(
                    children: <Widget>[
                      if (_sortMode == e.key)
                        const Icon(Icons.check_rounded, size: 18)
                      else
                        const SizedBox(width: 18),
                      const SizedBox(width: AppTokens.spaceSm),
                      Text(e.value),
                    ],
                  ),
                ),
            ],
          ),
          // 订阅列表排版样式：列表 / 卡片 / 紧凑 / 大图。
          RssListLayoutAction(layout: _listLayout, onSelected: _setListLayout),
        ],
      ),
      body: Column(
        children: <Widget>[
          _buildFilterBar(context, l10n),
          // 站内搜索：标题/摘要关键字过滤（仅过滤已加载条目，断网也能搜）。
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.spaceMd,
              0,
              AppTokens.spaceMd,
              AppTokens.spaceXs,
            ),
            child: AppSearchField(
              controller: _searchCtrl,
              hint: l10n.rssSearchHint,
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          if (_offline)
            // 离线横幅淡入上滑弹出，避免突然跳出一条横条。
            Entrance(
              offset: 8,
              fromScale: 1.0,
              duration: AppTokens.durBase,
              child: Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceMd,
                  vertical: AppTokens.spaceSm,
                ),
                child: Text(
                  l10n.rssOfflineCached,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
          Expanded(child: _buildBody(context, l10n)),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final chips = <_RssFilter, String>{
      _RssFilter.all: l10n.rssShowAll,
      _RssFilter.unread: l10n.rssShowUnread,
      _RssFilter.favorites: l10n.rssFavorites,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMd,
        vertical: AppTokens.spaceXs,
      ),
      child: Wrap(
        spacing: AppTokens.spaceSm,
        children: chips.entries.map((entry) {
          final selected = _filter == entry.key;
          return AppTapScale(
            // 芯片按下缩一下、松手弹回，切换筛选有手感。
            scale: 0.92,
            duration: AppTokens.durFast,
            child: FilterChip(
              label: Text(entry.value),
              selected: selected,
              onSelected: (_) => setState(() => _filter = entry.key),
              checkmarkColor: scheme.onPrimary,
              selectedColor: scheme.primary,
              labelStyle: TextStyle(
                color: selected ? scheme.onPrimary : scheme.onSurface,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: AppLoadingIndicator());
    }
    if (_error != null) {
      return AppErrorState(
        message: l10n.loadFailed,
        onRetry: _loadFeed,
      );
    }
    final items = _visibleItems;
    if (items.isEmpty) {
      return AppEmptyState(
        icon: Icons.article_rounded,
        message: _query.trim().isNotEmpty
            ? l10n.rssSearchNoResult
            : l10n.emptyRssItems,
      );
    }
    final Widget list = AppRefreshIndicator(
      onRefresh: _loadFeed,
      child: ListView.separated(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: context.pageInset(AppTokens.spaceMd),
        itemCount: items.length,
        separatorBuilder: (_, __) => _listLayout == 0
            ? const Divider(height: 1)
            : const SizedBox.shrink(),
        itemBuilder: (context, i) {
          final item = items[i];
          // 首屏逐条交错入场（最多 8 条，避免长列表延迟累积）；
          // onceKey 保证滚动回来不再重播。
          return Entrance(
            index: i < 8 ? i : 8,
            offset: 12,
            fromScale: 0.98,
            onceKey: 'rss:${widget.feed.id}:${item.url}',
            child: _buildItemTile(context, item),
          );
        },
      ),
    );
    // 排版/排序切换时列表淡入微滑过渡，切换不突兀。
    return AnimatedSwitcher(
      duration: AppTokens.durBase,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (Widget child, Animation<double> anim) =>
          FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.015),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey<String>('layout:$_listLayout:sort:$_sortMode'),
        child: list,
      ),
    );
  }

  /// 按当前排版样式分发到具体渲染（样式实现在共享的 rss_article_tiles）。
  Widget _buildItemTile(BuildContext context, RssItem item) {
    final read = _store.isRead(widget.feed.id, item);
    return buildRssArticleTile(
      context,
      _listLayout,
      RssArticleTileData(
        item: item,
        read: read,
        favorite: _store.isFavorite(widget.feed.id, item),
        coverUrl:
            item.coverUrl != null ? _absUrl(item.coverUrl!, item.url) : null,
        excerpt:
            item.description != null ? _stripHtml(item.description!) : null,
        author: item.author,
        dateText:
            item.publishedAt != null ? _formatDate(item.publishedAt!) : null,
        onOpen: () => _onOpen(item),
        onToggleFavorite: () => _onToggleFavorite(item),
      ),
    );
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
