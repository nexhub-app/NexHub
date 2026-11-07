/// 按固定网址浏览的列表页：用详情页抓到的真实作者/标签页链接，
/// 直接抓取该页 HTML 并用源的「列表解析器」解析成作品列表。
///
/// 对应需求：点作者/标签 = 在网站上点该作者/标签页（浏览式列表），
/// 而非关键词搜索。绕开站点拼音代号限制（不再用中文名拼搜索 URL），
/// 且源侧零改动——部分源的列表解析脚本本就解析任意含 /manga/
/// 链接的 HTML（服务端渲染，结构与首页一致）。
library;

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../models/media_item.dart';
import '../models/plugin_config.dart';
import '../network/network_config_service.dart';
import '../resolver/builtin_resolver.dart';
import '../resolver/script_resolver.dart';
import '../scraper/http_fetcher.dart';
import '../services/config_loader.dart';
import '../settings/layout_settings.dart';
import '../theme/app_tokens.dart';
import 'content_card.dart';

/// 用真实页面网址直接浏览该页内容（作者页 / 标签页 / 任意列表页）。
///
/// [seedUrl] 为详情页抓到的真实落地页链接（如
/// `https://<示例域名>/manga-author/pi-ka-pi`）。内部按页码追加翻页段，
/// 用源的列表解析器解析（脚本源走 [ScriptResolver.resolveFromHtml]，
/// 声明式源走 [BuiltinResolver.resolveFromUrl]），下滑自动加载更多。
class SourceUrlBrowseScreen extends StatefulWidget {
  const SourceUrlBrowseScreen({
    super.key,
    required this.source,
    required this.title,
    required this.seedUrl,
    required this.onItemTap,
  });

  final PluginConfig source;
  final String title;
  final String seedUrl;
  final void Function(MediaItem item, String? heroTag) onItemTap;

  @override
  State<SourceUrlBrowseScreen> createState() => _SourceUrlBrowseScreenState();
}

class _SourceUrlBrowseScreenState extends State<SourceUrlBrowseScreen> {
  final List<MediaItem> _items = <MediaItem>[];
  final ScrollController _scroll = ScrollController();
  int _page = 1;
  bool _loading = false;
  bool _initialLoaded = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final url = _pageUrl(widget.seedUrl, _page);
      final html = await HttpFetcher.instance.getHtml(
        url,
        referer: widget.source.antiHotlinking.referer,
        // 必须带上源的网络档案：源的 IP 钉死 / 免 SNI / 自定义 DNS 只有传了 net
        // 才生效，否则会出现「同一域名其他请求正常、这条却 Network unreachable」。
        net: NetworkConfigService.instance.effectiveFor(widget.source),
      );
      final List<MediaItem> pageItems = html.isEmpty
          ? const <MediaItem>[]
          : await _parse(source: widget.source, url: url, html: html, page: _page);
      if (!mounted) return;
      if (pageItems.isEmpty) {
        _hasMore = false;
      } else {
        _items.addAll(pageItems);
        _page += 1;
      }
      _initialLoaded = true;
      _error = null;
    } on Object catch (e) {
      if (!mounted) return;
      _initialLoaded = true;
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<MediaItem>> _parse({
    required PluginConfig source,
    required String url,
    required String html,
    required int page,
  }) async {
    final entry = _listEntry(source);
    if (source.parser.type == 'script' || source.parser.type == 'hybrid') {
      // 脚本源：App 在 Dart 侧抓到 HTML 后直接喂给列表解析脚本，
      // 脚本只解析传入的 html（不自己拼 URL），天然兼容任意列表页。
      final r = await ScriptResolver().resolveFromHtml(
        source,
        entry,
        html,
        vars: <String, String>{
          'baseUrl': ConfigLoader.instance.getActiveMirror(source),
          'page': '$page',
        },
      );
      return r is List<MediaItem> ? r : const <MediaItem>[];
    }
    // 声明式源：解析器自行抓取 URL 并套用列表选择器。
    final r = await BuiltinResolver().resolveFromUrl(
      source,
      entry,
      url,
      vars: <String, String>{'page': '$page'},
      baseUrl: ConfigLoader.instance.getActiveMirror(source),
    );
    return r is List<MediaItem> ? r : const <MediaItem>[];
  }

  /// 选取源的「列表解析入口」：优先用已有的 listing 覆盖 / 选择器 / 路由
  /// （explore > category > search > latest），保证用源自己的列表解析器。
  static String _listEntry(PluginConfig source) {
    for (final k in const <String>['explore', 'category', 'search', 'latest']) {
      if (source.parser.overrides?.containsKey(k) ?? false) return k;
      if (source.selectors?.containsKey(k) ?? false) return k;
      if (source.routes.containsKey(k)) return k;
    }
    return 'search';
  }

  /// 通用翻页：第 1 页用原网址；之后 URL 含 /page/N 则替换 N，否则按
  /// path 或 query 形式追加 page 参数（不写死任何站点格式）。
  static String _pageUrl(String seed, int page) {
    if (page <= 1) return seed;
    final uri = Uri.tryParse(seed);
    final hasQuery = uri != null && uri.queryParameters.isNotEmpty;
    final re = RegExp(r'/page/(\d+)(?=/|$)');
    if (re.hasMatch(seed)) {
      return seed.replaceFirstMapped(re, (m) => '/page/$page');
    }
    if (hasQuery) return '$seed${seed.contains('?') ? '&' : '?'}page=$page';
    return seed.endsWith('/') ? '${seed}page/$page' : '$seed/page/$page';
  }

  double _textAreaHeight(LayoutSettings layout) {
    if (!layout.showTitle && !layout.showAuthor) return 4;
    final lineHeight = layout.titleFontSize * 1.4;
    var lines = 0.0;
    if (layout.showTitle) lines += layout.titleMaxLines.toDouble();
    if (layout.showAuthor) lines += 1.0;
    if (layout.showProgress && layout.progressDisplay == ProgressDisplayMode.bar) {
      lines += 0.3;
    }
    return lineHeight * lines + 12;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final layout = LayoutSettingsStore.instance.settings;
    final bool busy = _loading;
    final bool footer = busy || (!_hasMore && _items.isNotEmpty);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _initialLoaded && _items.isEmpty
          ? Center(
              child: _error != null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(l10n.loadFailed),
                        const SizedBox(height: AppTokens.spaceMd),
                        ElevatedButton(
                          onPressed: () {
                            _error = null;
                            _initialLoaded = false;
                            _loadMore();
                          },
                          child: Text(l10n.retry),
                        ),
                      ],
                    )
                  : Text(l10n.emptyBrowse),
            )
          : LayoutBuilder(
              builder: (c, constraints) {
                final width = constraints.maxWidth;
                final cross = layout.layoutMode == LayoutMode.list
                    ? 1
                    : layout.gridColumns;
                final spacing = layout.gridSpacing;
                final itemW = layout.layoutMode == LayoutMode.list
                    ? width - AppTokens.spaceLg * 2
                    : (width - AppTokens.spaceLg * 2 - spacing * (cross - 1)) / cross;
                final childAspectRatio =
                    itemW / (itemW / AppTokens.coverAspectRatio + _textAreaHeight(layout));
                return GridView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(AppTokens.spaceLg),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cross,
                    mainAxisSpacing: spacing,
                    crossAxisSpacing: spacing,
                    childAspectRatio: childAspectRatio,
                  ),
                  itemCount: _items.length + (footer ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (i >= _items.length) {
                      if (busy) {
                        return const Center(
                            child: CircularProgressIndicator(strokeWidth: 2));
                      }
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppTokens.spaceLg),
                          child: Text(l10n.noMoreResults),
                        ),
                      );
                    }
                    final item = _items[i];
                    return ContentCard(
                      title: item.title,
                      coverUrl: item.coverUrl,
                      source: widget.source,
                      subtitle: layout.showAuthor ? item.author : null,
                      width: itemW,
                      heroTag: '${widget.title}-${item.id}',
                      onTap: () => widget.onItemTap(item, '${widget.title}-${item.id}'),
                    );
                  },
                );
              },
            ),
    );
  }
}
