/// 在线源浏览页 —— 在线 Tab 的入口。
///
/// 展示当前模块所有已配置的源列表（图标 + 名称 + 地址 + 状态），
/// 点击某个源后进入该源的分类/内容浏览页（[OnlineContentListScreen]）。
///
/// 书源（legado 格式）在此对齐 legado 发现页交互：点击源行就地展开，
/// 在源下方加载「选项栏」（分类 / 输入框 / 按钮 / 开关 / 下拉），
/// 点击分类直接进入对应分类列表；非书源维持原导航行为。
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/models/explore_kind.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/scraper/media_api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_glass_bar.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/detail_action_utils.dart';
import '../../../core/widgets/explore_kinds_panel.dart';
import '../../../core/services/source_repository.dart';

class OnlineSourceBrowserScreen extends StatefulWidget {
  /// 当前模块过滤类型
  final SourceType sourceType;
  final IconData emptyIcon;

  /// 点击某个源时的回调（非书源 / 书源无 exploreUrl）
  final void Function(PluginConfig source) onSourceTap;

  /// 点击书源选项栏里的分类（未传时回退 [onSourceTap]）。
  final void Function(PluginConfig source, String categoryUrl, String title)?
      onCategoryTap;

  final VoidCallback? onAddSource;

  /// 列表顶部前置的媒体服务器入口行（每台服务器一个）。
  /// 未配置服务器时传空列表 / null → 完全隐藏（在线列表回到纯源列表）。
  /// 仅需要的模块传入（当前为影视模块）。
  final List<Widget>? mediaServerTiles;

  const OnlineSourceBrowserScreen({
    super.key,
    required this.sourceType,
    this.emptyIcon = Icons.language_rounded,
    required this.onSourceTap,
    this.onCategoryTap,
    this.onAddSource,
    this.mediaServerTiles,
  });

  @override
  State<OnlineSourceBrowserScreen> createState() =>
      _OnlineSourceBrowserScreenState();
}

class _OnlineSourceBrowserScreenState extends State<OnlineSourceBrowserScreen> {
  /// 当前展开的源 id（同时只展开一个，避免长列表被多个面板撑开）。
  String? _expandedId;

  /// 已解析的选项栏结果（按源缓存，折叠后不丢）。
  final Map<String, ExploreKindsResult> _kinds = <String, ExploreKindsResult>{};

  /// 正在加载选项栏的源 id。
  final Set<String> _loading = <String>{};

  /// 加载期间被合并的刷新请求（见 [_loadKinds]）。
  final Set<String> _reloadQueued = <String>{};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final repo = context.watch<SourceRepository>();
    final sources = repo.byType(widget.sourceType);
    final tiles = widget.mediaServerTiles ?? const <Widget>[];

    final Widget body;
    if (sources.isEmpty && tiles.isEmpty) {
      body = AppEmptyState(
        icon: widget.emptyIcon,
        message: l10n.emptySources,
        actionLabel: l10n.addSource,
        onAction: widget.onAddSource,
      );
    } else {
      final Widget list = ListView.builder(
        // 行首图标可点：移动端避让玻璃底栏。
        padding:
            const EdgeInsets.all(AppTokens.spaceMd) + context.glassBarInset,
        itemCount: tiles.length + sources.length,
        itemBuilder: (context, i) {
          // 媒体服务器入口行前置（每台服务器一个；未配置时不占位）。
          if (i < tiles.length) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
              child: tiles[i],
            );
          }
          final int idx = i - tiles.length;
          final source = sources[idx];
          // 每行一段与面板同色的底色（常驻面板提供整体圆角，行段在此
          // 之上无缝相融），行间发丝分隔线。
          final bool first = idx == 0;
          final bool last = idx == sources.length - 1;
          final bool expandable = _hasExplore(source);
          final bool expanded = expandable && _expandedId == source.id;
          final Widget? statusChip = _buildStatusChip(source, scheme, l10n);
          return Material(
            color: AppTheme.cardContainer(scheme),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                top: first
                    ? const Radius.circular(AppTokens.radiusLg)
                    : Radius.zero,
                bottom: last
                    ? const Radius.circular(AppTokens.radiusLg)
                    : Radius.zero,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: <Widget>[
                if (!first)
                  const Divider(
                    height: 1,
                    thickness: 1,
                    indent: AppTokens.spaceLg,
                    endIndent: AppTokens.spaceLg,
                  ),
                ListTile(
                  onTap: () => _openSource(context, source),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceLg,
                    vertical: AppTokens.spaceXs,
                  ),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _sourceColor(source.type, scheme)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                    ),
                    child: Icon(
                      _sourceIcon(source.type),
                      color: _sourceColor(source.type, scheme),
                      size: 22,
                    ),
                  ),
                  title: Row(
                    children: <Widget>[
                      _buildAgeDot(source, scheme, l10n),
                      const SizedBox(width: AppTokens.spaceSm),
                      Expanded(
                        child: Text(
                          source.name,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: statusChip == null
                      ? null
                      : Padding(
                          padding:
                              const EdgeInsets.only(top: AppTokens.spaceXs),
                          child: statusChip,
                        ),
                  trailing: IconButton(
                    icon: const Icon(Icons.open_in_new_rounded),
                    tooltip: l10n.openSourceWebsite,
                    onPressed: () =>
                        openInAppBrowser(context, source.site.baseUrl,
                            source: source),
                  ),
                ),
                if (expanded)
                  ExploreKindsPanel(
                    result: _kinds[source.id],
                    loading: _loading.contains(source.id),
                    onRefresh: () => _loadKinds(source, refresh: true),
                    onOpenUrl: (kind) => _openKindUrl(source, kind),
                    onValueChanged: (kind, value) =>
                        _setKindValue(source, kind, value),
                    onRunAction: (kind) => _runKindAction(source, kind),
                  ),
              ],
            ),
          );
        },
      );
      // 视口圆角裁剪：滚动中屏幕边缘始终圆滑；卡底只由源行分段自绘——
      // 有源的地方铺色、没有的地方不铺（短列表贴合内容高度）。
      // 媒体服务器入口卡独立于源卡之外，不并入连体卡。
      body = ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        child: list,
      );
    }

    return body;
  }

  /// 书源是否声明了 exploreUrl（有发现页选项栏可展开）。
  bool _hasExplore(PluginConfig source) {
    final xiaoshuo = source.selectors?['xiaoshuo'];
    if (xiaoshuo is! Map) return false;
    final v = xiaoshuo['exploreUrl'];
    return v is String && v.trim().isNotEmpty;
  }

  void _openSource(BuildContext context, PluginConfig source) {
    if (!_hasExplore(source)) {
      widget.onSourceTap(source);
      return;
    }
    if (_expandedId == source.id) {
      setState(() => _expandedId = null);
      return;
    }
    setState(() => _expandedId = source.id);
    if (_kinds[source.id] == null && !_loading.contains(source.id)) {
      unawaited(_loadKinds(source));
    }
  }

  Future<void> _loadKinds(PluginConfig source, {bool refresh = false}) async {
    if (_loading.contains(source.id)) {
      // 加载期间到达的刷新请求不能丢：置位后由本次加载结束时补跑，
      // 否则「选择后紧接着再改」的第二次刷新被静默丢弃，界面停在旧值。
      if (refresh) _reloadQueued.add(source.id);
      return;
    }
    final service = context.read<MediaApiService>();
    setState(() {
      _loading.add(source.id);
      if (refresh) _kinds.remove(source.id);
    });
    try {
      final result =
          await service.resolveExploreKinds(source, refresh: refresh);
      if (!mounted) return;
      setState(() => _kinds[source.id] = result);
    } finally {
      if (mounted) {
        setState(() => _loading.remove(source.id));
        if (_reloadQueued.remove(source.id)) {
          unawaited(_loadKinds(source, refresh: true));
        }
      }
    }
  }

  void _openKindUrl(PluginConfig source, ExploreKind kind) {
    final url = kind.url;
    if (url == null || url.isEmpty) return;
    final title = kind.title.isNotEmpty ? kind.title : url;
    final handler = widget.onCategoryTap;
    if (handler != null) {
      handler(source, url, title);
    } else {
      widget.onSourceTap(source);
    }
  }

  /// 选项值（text/toggle/select）落盘并同步本地快照，立即回显。
  Future<void> _setKindValue(
      PluginConfig source, ExploreKind kind, String value) async {
    final current = _kinds[source.id];
    if (current != null) {
      _kinds[source.id] = ExploreKindsResult(
        items: <ExploreKindItem>[
          for (final it in current.items)
            if (identical(it.kind, kind) || it.kind.title == kind.title)
              ExploreKindItem(
                kind: it.kind,
                displayName: it.displayName,
                value: value,
              )
            else
              it,
        ],
        infoMap: current.infoMap,
      );
      setState(() {});
    }
    // 必须等落盘完成再执行 action：脚本读的是持久化的 infoMap。
    await context
        .read<MediaApiService>()
        .setExploreKindValue(source, kind.title, value);
  }

  Future<void> _runKindAction(PluginConfig source, ExploreKind kind) async {
    final service = context.read<MediaApiService>();
    final ExploreKindActionResult result;
    try {
      result = await service.executeExploreKindAction(source, kind);
    } catch (_) {
      // 对齐 legado evalButtonClick：action 脚本异常只记日志、不向界面抛出；
      // 这里静默返回，后续改选/展开等操作不受影响。
      return;
    }
    if (!mounted) return;
    for (final open in result.openRequests) {
      if (open.url.isEmpty) continue;
      openInAppBrowser(context, open.url, source: source);
      if (!mounted) return;
    }
    if (result.copiedTexts.isNotEmpty) {
      await Clipboard.setData(
          ClipboardData(text: result.copiedTexts.last));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).shareCopied)),
      );
    }
    if (result.refreshKinds) {
      await _loadKinds(source, refresh: true);
    }
  }

  /// 仅失效源显示徽章；健康源不再占位（状态由名称前的分级色点表达）。
  Widget? _buildStatusChip(
      PluginConfig source, ColorScheme scheme, AppLocalizations l10n) {
    if (!source.isEnabled || source.isDeprecated) {
      return Chip(
        label: Text(l10n.deprecated,
            style: TextStyle(fontSize: 11, color: scheme.error)),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero,
      );
    }
    return null;
  }

  /// 年龄分级色点（替代原分级徽章）：general=中性灰 / teen=琥珀 / mature=红。
  Widget _buildAgeDot(
      PluginConfig source, ColorScheme scheme, AppLocalizations l10n) {
    final (Color color, String label) = switch (source.ageRating) {
      SourceAgeRating.general => (scheme.outline, l10n.ageRatingGeneral),
      SourceAgeRating.teen => (scheme.tertiary, l10n.ageRatingTeen),
      SourceAgeRating.mature => (scheme.error, l10n.ageRatingMature),
    };
    return Semantics(
      label: label,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }

  static Color _sourceColor(SourceType type, ColorScheme scheme) {
    if (type == SourceType.novelSource) return scheme.primary;
    if (type.isMediaFamily) return scheme.tertiary;
    return scheme.secondary; // mangaSource
  }

  static IconData _sourceIcon(SourceType type) {
    if (type == SourceType.novelSource) return Icons.menu_book_rounded;
    if (type == SourceType.videoSource) return Icons.movie_rounded;
    if (type == SourceType.audioSource) return Icons.headphones_rounded;
    if (type == SourceType.animeSource) return Icons.movie_rounded;
    return Icons.auto_stories_rounded; // mangaSource
  }
}
