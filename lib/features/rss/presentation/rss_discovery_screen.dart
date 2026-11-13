/// 从网站自动发现 RSS / Atom 订阅源。
///
/// 入口：RSS 订阅列表页右上角「更多」菜单。流程：
/// 1. 输入站点地址（首页 URL）；
/// 2. 抓取首页 HTML，抽取 `<link rel="alternate">` 声明的 feed；
/// 3. 若首页没声明，按常见路径（/feed、/rss.xml…）逐个探测并用解析器验证；
/// 4. 列出候选（可多选）直接添加订阅。
///
/// 网络请求一律走全局网络档案（铁律）：`HttpFetcher.getHtml(url, net: globalProfile)`。
library;

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/network/network_config_service.dart';
import '../../../core/rss/rss_feed_discovery.dart';
import '../../../core/rss/rss_manager.dart';
import '../../../core/scraper/http_fetcher.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/app_animations.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../features/settings/presentation/widgets/settings_widgets.dart';
import '../../../core/widgets/app_glass_bar.dart';

class RssDiscoveryScreen extends StatefulWidget {
  const RssDiscoveryScreen({super.key});

  @override
  State<RssDiscoveryScreen> createState() => _RssDiscoveryScreenState();
}

class _RssDiscoveryScreenState extends State<RssDiscoveryScreen> {
  final TextEditingController _urlCtrl = TextEditingController();
  bool _busy = false;
  String? _error;
  List<RssFeedCandidate> _candidates = const <RssFeedCandidate>[];
  final Set<String> _selected = {};
  bool _probing = false;

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _discover(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final raw = _urlCtrl.text.trim();
    if (raw.isEmpty || _busy) return;

    // 规整 URL：补协议前缀，否则 HttpClient 会报格式错误。
    var url = raw;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    final base = Uri.tryParse(url);
    if (base == null || !base.hasAbsolutePath && base.host.isEmpty) {
      setState(() => _error = l10n.rssDiscoverInvalidUrl);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _candidates = const <RssFeedCandidate>[];
      _selected.clear();
      _probing = false;
    });

    try {
      final html = await HttpFetcher.instance.getHtml(
        url,
        net: NetworkConfigService.instance.globalProfile,
      );
      // 第 1 步：首页 link 声明。
      final fromLink = RssFeedDiscovery.fromHtml(html, url);
      if (fromLink.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _candidates = fromLink;
          _selected.addAll(fromLink.map((c) => c.url));
          _busy = false;
        });
        return;
      }

      // 第 2 步：首页未声明，探测常见 feed 路径。
      await _probeCommonPaths(context, url);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _probing = false;
        _error = l10n.rssDiscoverFailed(e.toString());
      });
    }
  }

  Future<void> _probeCommonPaths(BuildContext context, String baseUrl) async {
    final l10n = AppLocalizations.of(context);
    final seen = <String>{};
    final found = <RssFeedCandidate>[];
    if (!mounted) return;
    setState(() => _probing = true);
    for (final path in RssFeedDiscovery.commonPaths) {
      if (!mounted) return;
      final uri = Uri.parse(baseUrl).resolve(path);
      try {
        final text = await HttpFetcher.instance.getHtml(
          uri.toString(),
          net: NetworkConfigService.instance.globalProfile,
        );
        final title = RssFeedDiscovery.validateFeedText(text);
        if (title != null) {
          final abs = uri.toString();
          if (seen.add(abs)) {
            found.add(RssFeedCandidate(
              url: abs,
              title: title,
              type: RssFeedDiscovery.typeFromUrl(abs),
              source: 'probe',
            ));
            if (mounted) {
              setState(() {
                _candidates = List<RssFeedCandidate>.of(found);
                _selected.add(abs);
              });
            }
          }
        }
      } on Object {
        // 单条路径探测失败（404 / 网络）直接跳过，继续下一条。
      }
    }
    if (!mounted) return;
    setState(() {
      _probing = false;
      _busy = false;
    });
    if (found.isEmpty && mounted) {
      setState(() => _error = l10n.rssDiscoverNone);
    }
  }

  Future<void> _addSelected(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final manager = context.read<RssManager>();
    var added = 0;
    for (final c in _candidates) {
      if (!_selected.contains(c.url)) continue;
      await manager.addFeed(url: c.url, title: c.title);
      added++;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.rssDiscoverAdded(added))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.rssDiscoverTitle)),
      body: ListView(
        padding: context.pageInset(AppTokens.spaceMd),
        children: <Widget>[
          AppListTile(
            leading: const SettingsLeadingIcon(icon: Icons.language_rounded),
            title: Text(l10n.rssDiscoverDesc),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
            child: TextField(
              controller: _urlCtrl,
              decoration: InputDecoration(
                hintText: l10n.rssDiscoverInputHint,
                prefixIcon: const Icon(Icons.link_rounded),
                border: const OutlineInputBorder(),
                suffixIcon: _busy
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
              keyboardType: TextInputType.url,
              onSubmitted: (_) => _discover(context),
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
            child: FilledButton(
              onPressed: _busy ? null : () => _discover(context),
              child: Text(
                  _probing ? l10n.rssDiscoverProbing : l10n.rssDiscoverButton),
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: AppTokens.spaceMd),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
              child: Text(_error!, style: TextStyle(color: scheme.error)),
            ),
          ],
          if (_candidates.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppTokens.spaceMd),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
              child: Row(
                children: <Widget>[
                  Text(l10n.rssDiscoverFound(_candidates.length),
                      style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      _selected.length == _candidates.length
                          ? _selected.clear()
                          : _selected.addAll(_candidates.map((c) => c.url));
                    }),
                    child: Text(_selected.length == _candidates.length
                        ? l10n.deselectAll
                        : l10n.selectAll),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTokens.spaceXs),
            ..._candidates.asMap().entries.map((entry) {
              final i = entry.key;
              final c = entry.value;
              final on = _selected.contains(c.url);
              return Entrance(
                index: i < 8 ? i : 8,
                onceKey: 'disc:${c.url}',
                child: CheckboxListTile(
                  value: on,
                  onChanged: (v) {
                    v == true ? AppHaptics.toggleOn() : AppHaptics.toggleOff();
                    setState(() {
                      v == true
                          ? _selected.add(c.url)
                          : _selected.remove(c.url);
                    });
                  },
                  title: Text(c.title ?? c.url,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${c.source == 'link' ? l10n.rssDiscoverFromLink : l10n.rssDiscoverFromProbe} · ${c.url}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              );
            }),
            const SizedBox(height: AppTokens.spaceMd),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
              child: FilledButton(
                onPressed:
                    _selected.isEmpty ? null : () => _addSelected(context),
                child: Text(l10n.rssDiscoverAddSelected(_selected.length)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
