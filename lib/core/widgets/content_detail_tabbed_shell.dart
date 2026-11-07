/// 详情页统一骨架 · 标签页版（详情页重构 Phase 3）。
///
/// 结构（用户定稿方案）：
///
/// ```text
/// ┌──────────────────────────────┐
/// │ Hero 大图（滚动收起 + 吸顶） │ ← SliverAppBar + FlexibleSpaceBar
/// │ ┗ 浮层主操作（续看/续读） │ ← 随收起淡出，收起后不可点
/// ├──────────────────────────────┤
/// │ 详情 │Bangumi│选集│评论│推荐 │ ← 吸顶 TabBar
/// ├──────────────────────────────┤
/// │ TabBarView 内容 │
/// └──────────────────────────────┘
/// ```
///
/// 与旧 [ContentDetailShell] 的差异：
/// * 旧版把「选集 / Bangumi / 评论 / 推荐」折叠成入口行 → 点击弹底部弹窗；
/// 新版改为一级标签页，选集不再需要两次点击才能到达。
/// * 主操作从信息行下方上移到 Hero 浮层，首屏即可触达。
/// * 「在应用内浏览 / 在浏览器打开」等次级操作保留在「详情」标签内，
/// 避免 Hero 浮层堆砌按钮。
///
/// API 与 [ContentDetailShell] 保持一致，便于三套详情页机械迁移；
/// 新增 [chaptersTabLabel] 用于区分「选集」（影视）与「章节目录」（漫画/小说）。
library;

import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../models/plugin_config.dart';
import '../settings/detail_appearance_settings.dart';
import '../theme/app_tokens.dart';
import 'app_animations.dart';
import 'app_card.dart';
import 'bangumi_sync_dialog.dart';
import 'app_cover_image.dart';
import 'app_refresh_indicator.dart';
import 'translatable_text.dart';
import 'detail_action_utils.dart';
import '../settings/general_settings.dart';
import 'source_image.dart';

/// TabBar 高度（Material 3 默认 48，这里显式声明以便 Hero 浮层避让）。
const double _kTabBarHeight = 48;

/// Hero 大图展开高度（含 TabBar）。
const double _kHeroExpandedHeight = 320;

class ContentDetailTabbedShell extends StatefulWidget {
  final String? coverUrl;
  final String title;

  /// 元信息 chips（作者 / 导演 / 演员 / 字数 等），渲染在「详情」标签内。
  final List<Widget> infoChips;

  /// **主操作**（续看 / 续读 / 从头开始 / 系列 等），渲染为 Hero 浮层。
  final List<Widget> actions;

  final String? description;

  /// 「选集」标签内容（一般为 `ChapterListSection`）。
  final Widget chaptersList;

  /// 选集区块内标题（如「选集（24）」），渲染在标签页内容顶部。
  final String? chaptersTitle;

  /// 选集**标签名**（影视传「选集」，漫画/小说传「章节目录」）。
  /// 为空回退 [AppLocalizations.chapterList]。
  final String? chaptersTabLabel;

  /// 「推荐」标签内容；null 时不渲染该标签。
  final Widget? recommendations;

  final String? heroTag;

  /// 源配置（用于封面防盗链 headers 注入）。
  final PluginConfig? source;

  final DateTime? updatedAt;

  /// 连载状态文本（如「连载中」/「已完结」）。
  final String? statusText;

  /// 来源名称（源插件的 source.name）。
  final String? sourceName;

  /// 原站详情页 URL。非空时在「详情」标签自动追加应用内浏览 / 外部浏览器按钮。
  final String? detailUrl;

  final List<Widget>? tags;
  final VoidCallback? onCoverTap;

  /// 进度卡，渲染在「详情」标签内。
  final Widget? progressSection;

  /// 「Bangumi」标签内容；null 时不渲染该标签（源未声明即不渲染）。
  final Widget? bangumiSection;

  /// 「评论」标签内容；null 时不渲染该标签（源未声明 comments 即不渲染）。
  final Widget? commentsSection;

  /// 已解析的 Bangumi subjectId（由 Bangumi 标签页上抛）；非空时底栏显示「同步」按钮。
  final ValueNotifier<int?>? bangumiSubjectId;

  /// 同步弹窗所需的内容标识（与 [bangumiSubjectId] 配套）。
  final String? bangumiContentId;
  final SourceType? bangumiSourceType;

  /// AppBar 右侧操作按钮（收藏 / 下载 / 分享 / 刷新 / 删除等）。
  final List<Widget>? appBarActions;

  /// 返回钮回调（非 null 时 SliverAppBar 用它替代默认路由返回）。
  /// 双栏详情栏内嵌模式经此把「返回」转为「收起详情栏」。
  final VoidCallback? onBack;

  /// 下拉刷新回调。
  final Future<void> Function()? onRefresh;

  /// 封面为空时的占位图标。
  final IconData fallbackIcon;

  /// 全局提示条（如小说「目录仅部分加载 / 来自缓存」警告）。
  ///
  /// 渲染在「详情」与「选集」两个标签内容的顶部——它描述的是目录完整性，
  /// 放这两处最贴近用户视线；不做全页浮层以免遮挡 Hero。
  final Widget? banner;

  const ContentDetailTabbedShell({
    super.key,
    this.coverUrl,
    required this.title,
    this.infoChips = const <Widget>[],
    this.actions = const <Widget>[],
    this.description,
    required this.chaptersList,
    this.chaptersTitle,
    this.chaptersTabLabel,
    this.recommendations,
    this.heroTag,
    this.source,
    this.updatedAt,
    this.statusText,
    this.sourceName,
    this.detailUrl,
    this.tags,
    this.onCoverTap,
    this.progressSection,
    this.bangumiSection,
    this.commentsSection,
    this.bangumiSubjectId,
    this.bangumiContentId,
    this.bangumiSourceType,
    this.appBarActions,
    this.onBack,
    this.onRefresh,
    this.fallbackIcon = Icons.movie_rounded,
    this.banner,
  });

  @override
  State<ContentDetailTabbedShell> createState() =>
      _ContentDetailTabbedShellState();
}

class _ContentDetailTabbedShellState extends State<ContentDetailTabbedShell>
    with TickerProviderStateMixin {
  bool _descriptionExpanded = false;

  TabController? _tabController;

  /// 当前标签集合（用于判断异步数据到达后是否需要重建 controller）。
  List<_TabKind> _tabs = const <_TabKind>[];

  @override
  void initState() {
    super.initState();
    _syncTabs();
  }

  @override
  void didUpdateWidget(covariant ContentDetailTabbedShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 推荐 / Bangumi / 评论区可能异步到达，标签数量随之变化。
    _syncTabs();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  /// 依据当前可用区块重算标签集合；数量变化时重建 [TabController]
  /// 并尽量保留用户当前所在标签（按 [_TabKind] 而非下标匹配）。
  void _syncTabs() {
    final next = <_TabKind>[
      _TabKind.details,
      if (widget.bangumiSection != null) _TabKind.bangumi,
      _TabKind.chapters,
      if (widget.commentsSection != null) _TabKind.comments,
      if (widget.recommendations != null) _TabKind.recommendations,
    ];
    if (_listEquals(next, _tabs) && _tabController != null) return;

    final _TabKind? current = (_tabController != null &&
            _tabs.isNotEmpty &&
            _tabController!.index < _tabs.length)
        ? _tabs[_tabController!.index]
        : null;
    final int initialIndex =
        current == null ? 0 : next.indexOf(current).clamp(0, next.length - 1);

    _tabController?.dispose();
    _tabs = next;
    _tabController = TabController(
      length: next.length,
      vsync: this,
      initialIndex: initialIndex,
    );
  }

  static bool _listEquals(List<_TabKind> a, List<_TabKind> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ────────────────────────── Hero ──────────────────────────

  String _formatDateTime(DateTime dt) {
    // 走全局「日期格式」设置，使设置页的日期格式修改对所有详情页生效。
    return GeneralSettingsStore.instance.settings.dateFormat.format(
      dt,
      withTime: true,
    );
  }

  /// 连载状态 → 图标映射（与旧骨架保持一致，避免视觉回归）。
  IconData _statusIcon(String status) {
    final s = status.toLowerCase();
    if (s.contains('完') ||
        s.contains('结') ||
        s.contains('complete') ||
        s.contains('finish') ||
        s.contains('end')) {
      return Icons.check_circle_rounded;
    }
    if (s.contains('连载') ||
        s.contains('更新') ||
        s.contains('ongoing') ||
        s.contains('serial') ||
        s.contains('publish')) {
      return Icons.autorenew_rounded;
    }
    if (s.contains('停') ||
        s.contains('暂') ||
        s.contains('pause') ||
        s.contains('hiatus')) {
      return Icons.pause_circle_rounded;
    }
    return Icons.info_rounded;
  }

  Color _statusColor(ColorScheme scheme, String status) {
    final s = status.toLowerCase();
    if (s.contains('完') ||
        s.contains('结') ||
        s.contains('complete') ||
        s.contains('finish') ||
        s.contains('end')) {
      return scheme.primary;
    }
    if (s.contains('停') ||
        s.contains('暂') ||
        s.contains('pause') ||
        s.contains('hiatus')) {
      return scheme.error;
    }
    // 其余（如源直接给的「102集」这类非状态文本）统一强调色，
    // 与详情页胶囊的用色语言保持一致。
    return scheme.primary;
  }

  Widget _buildStatusBadge(
    ColorScheme scheme,
    TextTheme textTheme,
    String status,
  ) {
    final Color color = _statusColor(scheme, status);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceSm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(_statusIcon(status), size: 14, color: color),
          const SizedBox(width: AppTokens.spaceXs),
          Text(
            status,
            style: textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Hero 背景：全屏封面 + 双段渐变遮罩（顶部压暗保证 AppBar 图标可读，
  /// 底部渐隐到 surface 保证标题 / 浮层按钮可读）。
  ///
  /// 注意：「封面模糊背景」开启时本层保持原样（清晰封面，不模糊）——
  /// 模糊的是 [_DetailPageBackdrop] 那层整页背景，两者互不混用。
  Widget _buildHeroImage(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Widget fallback = Container(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          widget.fallbackIcon,
          size: 64,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
        ),
      ),
    );

    Widget image;
    final String? url = widget.coverUrl;
    if (url != null && url.isNotEmpty) {
      final bool isHttp = url.startsWith('http://') || url.startsWith('https://');
      image = isHttp
          ? SourceImage(
              url: url,
              source: widget.source,
              fit: BoxFit.cover,
              radius: 0,
              placeholder: fallback,
            )
          : Image.file(
              File(url),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback,
            );
    } else {
      image = fallback;
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        image,
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                scheme.surface.withValues(alpha: 0.0),
                scheme.surface.withValues(alpha: 0.35),
                scheme.surface.withValues(alpha: 0.92),
              ],
              stops: const <double>[0.35, 0.65, 1.0],
            ),
          ),
        ),
      ],
    );
  }

  /// Hero 视差层：收起过程中封面以更慢的速度跟随（下移 + 微放大），
  /// 与容器收起形成速度差，产生纵深感。
  ///
  /// [t] 为展开度（1 = 完全展开，0 = 完全收起）。放大是必要的：只平移会在
  /// 顶部露出空白，`scale` 抵消位移带来的裸露区域。位移与缩放量都刻意压得
  /// 很小（≤ 20px / 6%），属于「适度增强」而非炫技。
  Widget _buildHeroParallax(BuildContext context, double t) {
    const double kShift = 20;
    const double kZoom = 0.06;
    final double p = 1 - t; // 收起进度
    return Transform.translate(
      offset: Offset(0, p * kShift),
      child: Transform.scale(
        scale: 1 + p * kZoom,
        child: _buildHeroImage(context),
      ),
    );
  }

  // ────────────────────────── 「详情」标签 ──────────────────────────

  /// 底部吸底操作条（选项 C）：左侧主操作（续看 / 播放 / 阅读 + 系列），
  /// 右侧图标（应用内打开 / 外部打开 / 分享）。详情 tab 不再重复放置浏览按钮。
  ///
  /// [widget.actions] 由详情页传入（主操作）；浏览 / 分享按 [widget.detailUrl]
  /// 动态出现。整体常驻可见，不随 Hero 收起而消失，操作永远可达。
  Widget _buildBottomActionBar(BuildContext context, AppLocalizations l10n) {
    final String? url = widget.detailUrl;
    final bool hasUrl = url != null && url.isNotEmpty && !url.contains('{}');

    // Bangumi 同步按钮（样式与播放主操作一致：FilledButton.icon），
    // 与主操作（播放/阅读）置于同一行、紧邻其右侧。
    final bool syncReady = widget.bangumiSubjectId != null &&
        widget.bangumiContentId != null &&
        widget.bangumiSourceType != null;
    final Widget? syncButton = syncReady
        ? ValueListenableBuilder<int?>(
            valueListenable: widget.bangumiSubjectId!,
            builder: (BuildContext ctx, int? sid, _) => sid == null
                ? const SizedBox.shrink()
                : FilledButton.icon(
                    onPressed: () => showBangumiSyncDialog(
                      context,
                      subjectId: sid,
                      title: widget.title,
                      contentId: widget.bangumiContentId!,
                      sourceType: widget.bangumiSourceType!,
                    ),
                    icon: const Icon(Icons.sync_rounded, size: 18),
                    label: Text(l10n.bangumiSync),
                  ),
          )
        : null;

    final List<Widget> actions = <Widget>[
      ...widget.actions,
      if (syncButton != null) syncButton,
    ];

    final List<Widget> right = <Widget>[
      if (hasUrl)
        _CircleIconButton(
          tooltip: l10n.openInAppBrowser,
          icon: Icons.travel_explore_rounded,
          onPressed: () => openInAppBrowser(context, url, source: widget.source),
        ),
      if (hasUrl)
        _CircleIconButton(
          tooltip: l10n.openInBrowser,
          icon: Icons.open_in_new_rounded,
          onPressed: () => openInExternalBrowser(context, url),
        ),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceMd,
          vertical: AppTokens.spaceSm,
        ),
        child: Row(
          children: <Widget>[
            if (actions.isNotEmpty)
              Expanded(
                child: Wrap(
                  spacing: AppTokens.spaceSm,
                  runSpacing: AppTokens.spaceXs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions,
                ),
              ),
            if (actions.isNotEmpty)
              const SizedBox(width: AppTokens.spaceSm),
            ...right,
          ],
        ),
      ),
    );
  }

  Widget _buildSmallCover({required bool isCompact}) {
    final double width = isCompact ? 100 : 110;
    final Widget cover = AppCoverImage(
      coverUrl: widget.coverUrl,
      source: widget.source,
      title: widget.title,
      width: width,
      height: width / AppTokens.coverAspectRatio,
      heroTag: widget.heroTag,
    );
    if (widget.onCoverTap != null) {
      return GestureDetector(onTap: widget.onCoverTap, child: cover);
    }
    return cover;
  }

  /// 标题块：标题 + 状态徽标 + 来源 + 更新时间。
  Widget _buildTitleBlock(
    BuildContext context,
    AppLocalizations l10n, {
    required bool isCompact,
  }) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AutoTranslatedText(
          text: widget.title,
          kind: TranslatableTextKind.title,
          style: (isCompact ? textTheme.titleLarge : textTheme.headlineSmall)
              ?.copyWith(fontWeight: FontWeight.w600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (widget.statusText != null && widget.statusText!.isNotEmpty) ...[
          const SizedBox(height: AppTokens.spaceSm),
          _buildStatusBadge(scheme, textTheme, widget.statusText!),
        ],
        if (widget.sourceName != null && widget.sourceName!.isNotEmpty) ...[
          const SizedBox(height: AppTokens.spaceSm),
          Row(
            children: <Widget>[
              Icon(Icons.source_rounded,
                  size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppTokens.spaceXs),
              Flexible(
                child: Text(
                  '${l10n.sourceLabel}: ${widget.sourceName}',
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
        if (widget.updatedAt != null) ...[
          const SizedBox(height: AppTokens.spaceSm),
          ListenableBuilder(
            listenable: GeneralSettingsStore.instance,
            builder: (BuildContext ctx, _) => Text(
              '${l10n.updatedAtLabel} ${_formatDateTime(widget.updatedAt!)}',
              style: textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ],
    );
  }

  /// 「详情」标签正文：封面行 + chips + 简介 + 标签 + 进度卡 + 次级操作。
  Widget _buildDetailsTab(BuildContext context, AppLocalizations l10n) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    // 胶囊统一强调色：详情页内的元信息 / 题材标签 chips 从「白底描边」
    // 改为强调色浅底 + 强调色文字 + 强调色描边（动态取色开启时随封面
    // 变化）。copyWith 保留全局 chipTheme 的形状与内边距。
    final ChipThemeData accentChips = ChipTheme.of(context).copyWith(
      backgroundColor: scheme.primary.withValues(alpha: 0.10),
      side: BorderSide(color: scheme.primary.withValues(alpha: 0.30)),
      labelStyle: textTheme.labelLarge?.copyWith(color: scheme.primary),
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
    final bool isCompact =
        constraints.maxWidth < AppTokens.compactBreakpoint;

    return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 封面行
            Entrance(
              offset: 12,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.spaceLg,
                  AppTokens.spaceLg,
                  AppTokens.spaceLg,
                  0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _buildSmallCover(isCompact: isCompact),
                    const SizedBox(width: AppTokens.spaceLg),
                    Expanded(
                      child:
                          _buildTitleBlock(context, l10n, isCompact: isCompact),
                    ),
                  ],
                ),
              ),
            ),

            // 元信息 chips（全宽渲染，窄屏也能正常横排换行）
            if (widget.infoChips.isNotEmpty)
              Entrance(
                delay: const Duration(milliseconds: 40),
                offset: 12,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.spaceLg,
                    AppTokens.spaceMd,
                    AppTokens.spaceLg,
                    0,
                  ),
                  child: ChipTheme(
                    data: accentChips,
                    child: Wrap(
                      spacing: AppTokens.spaceSm,
                      runSpacing: AppTokens.spaceSm,
                      children: widget.infoChips,
                    ),
                  ),
                ),
              ),

            // 题材标签（上移，置于简介之前）
            if (widget.tags != null && widget.tags!.isNotEmpty)
              Entrance(
                delay: const Duration(milliseconds: 80),
                offset: 12,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.spaceLg,
                    AppTokens.spaceMd,
                    AppTokens.spaceLg,
                    0,
                  ),
                  child: ChipTheme(
                    data: accentChips,
                    child: Wrap(
                      spacing: AppTokens.spaceSm,
                      runSpacing: AppTokens.spaceSm,
                      children: widget.tags!,
                    ),
                  ),
                ),
              ),

            // 简介（可展开 / 收起，置于标签之后）
            if (widget.description != null && widget.description!.isNotEmpty)
              Entrance(
                delay: const Duration(milliseconds: 120),
                offset: 12,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.spaceLg,
                    AppTokens.spaceMd,
                    AppTokens.spaceLg,
                    0,
                  ),
                  child: AppCard(
                    child: Padding(
                      padding: const EdgeInsets.all(AppTokens.spaceMd),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          AnimatedSize(
                            duration: AppTokens.durBase,
                            curve: AppCurves.smooth,
                            alignment: Alignment.topCenter,
                            child: BilingualTranslatedText(
                              text: widget.description!,
                              kind: TranslatableTextKind.summary,
                              style: textTheme.bodyMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                              maxLines: _descriptionExpanded ? null : 4,
                              overflow: _descriptionExpanded
                                  ? TextOverflow.visible
                                  : TextOverflow.ellipsis,
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => setState(() =>
                                  _descriptionExpanded = !_descriptionExpanded),
                              child: Text(
                                _descriptionExpanded
                                    ? l10n.collapse
                                    : l10n.expand,
                                style: textTheme.labelLarge
                                    ?.copyWith(color: scheme.primary),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // 进度卡
            if (widget.progressSection != null)
              Entrance(
                delay: const Duration(milliseconds: 160),
                offset: 12,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.spaceLg,
                    AppTokens.spaceMd,
                    AppTokens.spaceLg,
                    0,
                  ),
                  child: widget.progressSection!,
                ),
              ),

          ],
        );
      },
    );
  }

  // ────────────────────────── 组装 ──────────────────────────

  /// 标签正文容器：注入 [SliverOverlapInjector] 抵消吸顶头部占位，
  /// 并用 [PageStorageKey] 保留各标签自己的滚动位置。
  ///
  /// [withBanner] 为 true 时在正文上方插入 [ContentDetailTabbedShell.banner]。
  Widget _tabPage(String storageKey, Widget child, {bool withBanner = false}) {
    final Widget? banner = withBanner ? widget.banner : null;
    return Builder(
      builder: (BuildContext ctx) => CustomScrollView(
        key: PageStorageKey<String>(storageKey),
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: <Widget>[
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(ctx),
          ),
          if (banner != null) SliverToBoxAdapter(child: banner),
          SliverToBoxAdapter(child: child),
          const SliverToBoxAdapter(
            child: SizedBox(height: AppTokens.spaceXl),
          ),
        ],
      ),
    );
  }

  String _tabLabel(_TabKind kind, AppLocalizations l10n) {
    return switch (kind) {
      _TabKind.details => l10n.details,
      // Bangumi 是专有名词，不做本地化。
      _TabKind.bangumi => 'Bangumi',
      _TabKind.chapters => widget.chaptersTabLabel ?? l10n.chapterList,
      _TabKind.comments => l10n.comments,
      _TabKind.recommendations => l10n.recommendations,
    };
  }

  Widget _tabContent(_TabKind kind, AppLocalizations l10n) {
    return switch (kind) {
      _TabKind.details => _tabPage(
          'detail',
          _buildDetailsTab(context, l10n),
          withBanner: true,
        ),
      _TabKind.bangumi => _tabPage(
          'bangumi',
          Padding(
            padding: const EdgeInsets.all(AppTokens.spaceLg),
            child: widget.bangumiSection ?? const SizedBox.shrink(),
          ),
        ),
      _TabKind.chapters => _tabPage(
          'chapters',
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceLg,
              vertical: AppTokens.spaceMd,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (widget.chaptersTitle != null &&
                    widget.chaptersTitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
                    child: Text(
                      widget.chaptersTitle!,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                widget.chaptersList,
              ],
            ),
          ),
          withBanner: true,
        ),
      _TabKind.comments => _tabPage(
          'comments',
          Padding(
            padding: const EdgeInsets.all(AppTokens.spaceLg),
            child: widget.commentsSection ?? const SizedBox.shrink(),
          ),
        ),
      _TabKind.recommendations => _tabPage(
          'recommend',
          Padding(
            padding: const EdgeInsets.all(AppTokens.spaceLg),
            child: widget.recommendations ?? const SizedBox.shrink(),
          ),
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TabController controller = _tabController!;

    // 「详情页外观 → 封面模糊背景」：白色页面背景替换为模糊封面铺底
    // （关闭时保持原白色背景）。Hero 仍自绘清晰封面（两者不混）；
    // 开关 / 强度变化由详情页外层的 ListenableBuilder 触发整页重建，
    // 这里直接读当前设置即可。
    final DetailAppearanceSettings appearance =
        DetailAppearanceStore.instance.settings;
    final bool backdropOn = appearance.blurredBackgroundEnabled &&
        widget.coverUrl != null &&
        widget.coverUrl!.isNotEmpty;

    final double topPadding = MediaQuery.of(context).padding.top;
    // flexibleSpace 的高度范围（不含 TabBar）：
    // 收起时 = topPadding + toolbarHeight，展开时 = expandedHeight - tabBarHeight。
    final double flexibleMinHeight = topPadding + kToolbarHeight;
    const double flexibleMaxHeight = _kHeroExpandedHeight - _kTabBarHeight;
    final double flexibleRange =
        (flexibleMaxHeight - flexibleMinHeight).clamp(1.0, 1e6);

    final Widget nested = NestedScrollView(
      headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
        return <Widget>[
          SliverOverlapAbsorber(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            sliver: SliverAppBar(
              pinned: true,
              expandedHeight: _kHeroExpandedHeight,
              // 标题完全由 FlexibleSpaceBar background 接管：
              // 展开态 → 自定义 Positioned 标题（Hero 内下部）
              // 收起态 → 自定义 Positioned 标题（toolbar 内居中）
              leading: widget.onBack != null
                  ? BackButton(onPressed: widget.onBack)
                  : null,
              actions: widget.appBarActions,
              // 模糊背景开启时，顶栏 / 标签栏改为半透明纱面——收起后与整页
              // 模糊背景衔接（隐约透出背景图），不再是白色实心条；展开态
              // 本层被 Hero 封面盖住，透明度不影响观感。关闭时保持原实色。
              backgroundColor: backdropOn
                  ? scheme.surface.withValues(alpha: 0.78)
                  : scheme.surface,
              surfaceTintColor: Colors.transparent,
              // 半透明栏位上投影显脏（与玻璃栏位同理），纱面态不叠加阴影。
              forceElevated: innerBoxIsScrolled && !backdropOn,
              flexibleSpace: LayoutBuilder(
                builder: (BuildContext ctx, BoxConstraints c) {
                  // 展开度 t：1 = 完全展开，0 = 完全收起。
                  final double t =
                      ((c.maxHeight - flexibleMinHeight) / flexibleRange)
                          .clamp(0.0, 1.0);

                  // ── 展开态标题（Hero 背景层）──
                  // t > 0.5 时显示，随折叠上移 + 淡出；t ≤ 0.5 完全隐藏。
                  final double expandOpacity =
                      ((t - 0.50) / 0.35).clamp(0.0, 1.0);
                  final bool showExpandTitle = expandOpacity > 0.01;

                  // ── 收起态标题（toolbar 内）──
                  // t < 0.4 时显示，随收起渐显。
                  final double collapseOpacity =
                      ((0.40 - t) / 0.40).clamp(0.0, 1.0);
                  final bool showCollapseTitle = collapseOpacity > 0.01;

                  return FlexibleSpaceBar(
                    // 不再使用 FlexibleSpaceBar.title，改用 background Stack
                    // 中的自定义 Positioned，避免被 safeBottom 下推。
                    title: null,
                    background: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        _buildHeroParallax(context, t),
                        // 展开态自定义标题：定位在 Hero 区域下部，
                        // 收起过程中上移并淡出；完全收起后(t≤0.5)隐藏。
                        if (showExpandTitle)
                          Positioned(
                            // 左侧回退键(56)减去部分内缩；右侧紧凑留白。
                            left: 52.0,
                            right: 12.0 +
                                24.0 *
                                    (widget.appBarActions?.length ?? 0),
                            // 展开态(t=1)：bottom≈52dp，贴近内容区；
                            // 收起过程 bottom 渐增（跟随收缩上移）；
                            // 同时 opacity 渐隐。
                            bottom: _kHeroExpandedHeight *
                                    (0.163 + 0.28 * (1 - t)),
                            child: Opacity(
                              opacity: expandOpacity,
                              child: AutoTranslatedText(
                                text: widget.title,
                                kind: TranslatableTextKind.title,
                                style: textTheme.headlineSmall?.copyWith(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w700,
                                  shadows: <Shadow>[
                                    Shadow(
                                      blurRadius: 14,
                                      color: scheme.surface
                                          .withValues(alpha: 0.75),
                                    ),
                                    Shadow(
                                      blurRadius: 5,
                                      color: scheme.shadow
                                          .withValues(alpha: 0.25),
                                    ),
                                  ],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        // 收起态标题：固定在 toolbar 区域内，与返回键同行。
                        if (showCollapseTitle)
                          Positioned(
                            left: 56.0,
                            right: 48.0,
                            top: topPadding,
                            bottom: 0.0,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Opacity(
                                opacity: collapseOpacity,
                                child: AutoTranslatedText(
                                  text: widget.title,
                                  kind: TranslatableTextKind.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              bottom: TabBar(
                controller: controller,
                isScrollable: _tabs.length > 3,
                tabAlignment:
                    _tabs.length > 3 ? TabAlignment.start : TabAlignment.fill,
                dividerColor: Colors.transparent,
                labelColor: scheme.primary,
                unselectedLabelColor: scheme.onSurfaceVariant,
                indicatorSize: TabBarIndicatorSize.label,
                // 纯文字标签：5 个标签同时带图标会在 48dp 内挤压溢出，
                // 且与「不堆砌」的设计取向相悖。
                tabs: <Widget>[
                  for (final _TabKind kind in _tabs)
                    Tab(
                      height: _kTabBarHeight,
                      child: Text(
                        _tabLabel(kind, l10n),
                        style: textTheme.labelLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ];
      },
      body: TabBarView(
        controller: controller,
        // 弹簧手感：切换标签时带轻微惯性，与全局动效语言一致。
        physics: const BouncingScrollPhysics(),
        children: <Widget>[
          for (final _TabKind kind in _tabs) _tabContent(kind, l10n),
        ],
      ),
    );

    final Widget bar = _buildBottomActionBar(context, l10n);
    final Widget body = Column(
      children: <Widget>[
        Expanded(child: nested),
        bar,
      ],
    );
    final Widget content;
    if (widget.onRefresh != null) {
      content = AppRefreshIndicator(onRefresh: widget.onRefresh!, child: body);
    } else {
      content = body;
    }
    if (!backdropOn) return content;
    // 背景层固定不随内容滚动（blur 只算一次），内容 / 底栏浮在其上。
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        _DetailPageBackdrop(
          url: widget.coverUrl!,
          source: widget.source,
          sigma: appearance.backgroundBlurSigma,
        ),
        content,
      ],
    );
  }
}

/// 「详情页外观 → 封面模糊背景」整页背景层。
///
/// 把页面原来的白色背景（Scaffold surface）替换为封面（或 detail 回填后的
/// 封面）的高斯模糊铺底：模糊图整页可见，上面叠一层随深度轻微加重的
/// 底色纱罩，保证正文 / 列表文本可读；Hero 仍是独立的清晰封面层，与本层
/// 互不混用。关闭该设置时不挂载本层，页面保持原白色背景。
class _DetailPageBackdrop extends StatelessWidget {
  final String url;
  final PluginConfig? source;
  final double sigma;

  const _DetailPageBackdrop({
    required this.url,
    required this.source,
    required this.sigma,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool isHttp =
        url.startsWith('http://') || url.startsWith('https://');
    final Widget image = isHttp
        ? SourceImage(
            url: url,
            source: source,
            fit: BoxFit.cover,
            radius: 0,
          )
        : Image.file(File(url), fit: BoxFit.cover);
    // ClipRect 限定滤镜作用域；ImageFilter.blur 边缘为 clamp 采样，
    // 重度模糊也不会露出透明毛边。
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: image,
          ),
          // 纱罩：顶部（Hero 区身后，本就被清晰封面盖住）最透，往下轻微
          // 加重到底色——模糊图全程可感，正文仍可读。
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const <double>[0.0, 0.30, 1.0],
                colors: <Color>[
                  scheme.surface.withValues(alpha: 0.25),
                  scheme.surface.withValues(alpha: 0.55),
                  scheme.surface.withValues(alpha: 0.82),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 底栏圆形图标按钮（带按压缩放反馈，增加灵动感）。
class _CircleIconButton extends StatefulWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _CircleIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  State<_CircleIconButton> createState() => _CircleIconButtonState();
}

class _CircleIconButtonState extends State<_CircleIconButton> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.88),
      onTapUp: (_) => setState(() => _scale = 1.0),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Tooltip(
          message: widget.tooltip,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.surfaceContainerHighest,
            ),
            child: Icon(widget.icon, size: 20, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// 标签种类。用类型而非下标标识，便于异步区块到达后保留用户当前标签。
enum _TabKind {
  details,
  bangumi,
  chapters,
  comments,
  recommendations,
}
