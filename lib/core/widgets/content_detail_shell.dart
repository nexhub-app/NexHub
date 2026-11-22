import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import '../models/plugin_config.dart';
import '../theme/app_tokens.dart';
import 'app_animations.dart';
import 'app_card.dart';
import 'app_cover_image.dart';
import 'app_refresh_indicator.dart';
import 'detail_action_utils.dart';
import '../settings/general_settings.dart';
import 'source_image.dart';

/// 详情页统一骨架：Hero 大图 SliverAppBar + 元信息 chips + 操作行 +
/// 可展开简介 + 进度卡 + 章节/剧集列表 + 相关推荐。
///
/// 各内容模块详情页复用，禁止重复造轮子。
///
/// 详情页全面增强：改为 [StatefulWidget]，新增 [SliverAppBar] +
/// [FlexibleSpaceBar] Hero 大图 + 渐变遮罩；简介改 [AppCard] 包裹可展开/收起；
/// [RefreshIndicator] 包裹；新增 [appBarActions] / [onRefresh] / [fallbackIcon]。
class ContentDetailShell extends StatefulWidget {
  final String? coverUrl;
  final String title;
  final List<Widget> infoChips;
  final List<Widget> actions;
  final String? description;
  final Widget chaptersList;

  /// 选集 / 章节入口行标题（如「选集（24）」「章节目录（120）」）。
  /// 为空时回退 [AppLocalizations.chapterList]。
  final String? chaptersTitle;
  final Widget? recommendations;
  final String? heroTag;

  /// 源配置（用于封面防盗链 headers 注入）。
  final PluginConfig? source;

  /// 最后更新时间。
  final DateTime? updatedAt;

  /// 连载状态文本（如"连载中"/"已完结"），非空时在标题下渲染带图标的状态徽标。
  final String? statusText;

  /// 来源名称（源插件的 source.name），非空时在标题下渲染"来源：xxx"。
  final String? sourceName;

  /// 原站详情页 URL。非空时自动在操作行渲染「在应用内浏览」与
  /// 「在浏览器打开」两个按钮（带文字的 [OutlinedButton.icon] 样式），
  /// 三详情页共用，无需各自实现。
  final String? detailUrl;

  /// 题材标签区。
  final List<Widget>? tags;

  /// 点击封面回调（弹出全屏大图查看器）。
  final VoidCallback? onCoverTap;

  /// 进度卡，渲染在标签区之后、章节列表之前。
  final Widget? progressSection;

  /// Bangumi 评分/短评/同步卡。以入口行呈现，点击在底部弹窗中展开。
  final Widget? bangumiSection;

  /// 评论区（源驱动，M-comments）。以入口行呈现，点击在底部弹窗中展开。
  /// 源未声明 comments 配置段时传 null，不渲染评论入口。
  final Widget? commentsSection;

  // ─── 新增参数───

  /// SliverAppBar 右侧操作按钮（收藏 / 下载 / 分享 / 刷新 / 删除等）。
  final List<Widget>? appBarActions;

  /// 下拉刷新回调（非 null 时包裹 [RefreshIndicator]）。
  final Future<void> Function()? onRefresh;

  /// 封面为空时 SliverAppBar 背景显示的占位图标。
  final IconData fallbackIcon;

  const ContentDetailShell({
    super.key,
    this.coverUrl,
    required this.title,
    this.infoChips = const <Widget>[],
    this.actions = const <Widget>[],
    this.description,
    required this.chaptersList,
    this.chaptersTitle,
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
    this.appBarActions,
    this.onRefresh,
    this.fallbackIcon = Icons.movie_rounded,
  });

  @override
  State<ContentDetailShell> createState() => _ContentDetailShellState();
}

class _ContentDetailShellState extends State<ContentDetailShell> {
  bool _descriptionExpanded = false;

  String _formatDateTime(DateTime dt) {
    // 走全局「日期格式」设置，使设置页的日期格式修改对所有详情页生效。
    return GeneralSettingsStore.instance.settings.dateFormat.format(
      dt,
      withTime: true,
    );
  }

  /// 连载状态 → 图标映射。已完结类走 [Icons.check_circle_rounded]，连载中类走
  /// [Icons.autorenew_rounded]，其余（停更/暂停）走 [Icons.pause_circle_rounded]。
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

  /// 连载状态 → 颜色映射。已完结用主色，连载中用绿色系（tertiary），
  /// 停更用警示色。
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
    return scheme.tertiary;
  }

  /// 连载状态徽标：图标 + 文本，图标随状态切换。
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

  /// 操作行：页面自有按钮（续看 / 系列 / 等） + 详情页公用浏览按钮。
  ///
  /// 当 [detailUrl] 非空时自动追加「在应用内浏览」([Icons.travel_explore_rounded]) 与
  /// 「在浏览器打开」([Icons.open_in_new_rounded]) 两个带文字的 [OutlinedButton.icon]，
  /// 恢复用户习惯的样式，并下沉到骨架层供三详情页复用。
  List<Widget> _buildActionButtons(BuildContext context, AppLocalizations l10n) {
    final List<Widget> buttons = <Widget>[...widget.actions];
    final String? detailUrl = widget.detailUrl;
    if (detailUrl != null &&
        detailUrl.isNotEmpty &&
        !detailUrl.contains('{}')) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: () =>
              openInAppBrowser(context, detailUrl, source: widget.source),
          icon: const Icon(Icons.travel_explore_rounded),
          label: Text(l10n.openInAppBrowser),
        ),
      );
      buttons.add(
        OutlinedButton.icon(
          onPressed: () => openInExternalBrowser(context, detailUrl),
          icon: const Icon(Icons.open_in_new_rounded),
          label: Text(l10n.openInBrowser),
        ),
      );
    }
    if (buttons.isEmpty) return const <Widget>[];
    return <Widget>[
      const SizedBox(height: AppTokens.spaceMd),
      Wrap(
        spacing: AppTokens.spaceSm,
        runSpacing: AppTokens.spaceSm,
        children: buttons,
      ),
    ];
  }

  /// SliverAppBar 背景全屏封面 + 渐变遮罩。
  Widget _buildHeroBackground(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Widget fallback = Container(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(widget.fallbackIcon,
            size: 64,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.3)),
      ),
    );

    Widget image;
    if (widget.coverUrl != null && widget.coverUrl!.isNotEmpty) {
      final bool isHttp = widget.coverUrl!.startsWith('http://') ||
          widget.coverUrl!.startsWith('https://');
      if (isHttp) {
        image = SourceImage(
          url: widget.coverUrl,
          source: widget.source,
          isCover: true,
          fit: BoxFit.cover,
          radius: 0,
          placeholder: fallback,
        );
      } else {
        // Local file
        image = Image.file(
          File(widget.coverUrl!),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        );
      }
    } else {
      image = fallback;
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        image,
        // 渐变遮罩：顶部透明 → 底部接近 surface 色，确保标题文字可读
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

  /// 封面缩略图（信息行用）。紧凑档缩至 100dp 宽，减少行高失衡。
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

  /// 标题块（标题 + 状态徽标 + 来源行 + 更新时间；宽屏档追加 chips 与操作按钮）。
  ///
  /// 紧凑档标题降为 [TextTheme.titleLarge]，避免大字号在窄列频繁换行占高；
  /// chips / 操作按钮由 [_buildHeaderSection] 移到封面行下方全宽渲染。
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
        Text(
          widget.title,
          style: (isCompact ? textTheme.titleLarge : textTheme.headlineSmall)
              ?.copyWith(fontWeight: FontWeight.w600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        // 连载状态徽标（图标随状态切换）
        if (widget.statusText != null &&
            widget.statusText!.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppTokens.spaceSm),
          _buildStatusBadge(scheme, textTheme, widget.statusText!),
        ],
        // 来源
        if (widget.sourceName != null &&
            widget.sourceName!.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppTokens.spaceSm),
          Row(
            children: <Widget>[
              Icon(Icons.source_rounded,
                  size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppTokens.spaceXs),
              Flexible(
                child: Text(
                  '${l10n.sourceLabel}: ${widget.sourceName}',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
        if (isCompact) ...<Widget>[
          // 紧凑档：右列只保留基础信息，chips / 按钮下移全宽渲染。
          if (widget.updatedAt != null) ...<Widget>[
            const SizedBox(height: AppTokens.spaceSm),
            ListenableBuilder(
              listenable: GeneralSettingsStore.instance,
              builder: (BuildContext ctx, _) => Text(
                '${l10n.updatedAtLabel} ${_formatDateTime(widget.updatedAt!)}',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ] else ...<Widget>[
          const SizedBox(height: AppTokens.spaceMd),
          if (widget.infoChips.isNotEmpty)
            Wrap(
              spacing: AppTokens.spaceSm,
              runSpacing: AppTokens.spaceSm,
              children: widget.infoChips,
            ),
          if (widget.updatedAt != null) ...<Widget>[
            const SizedBox(height: AppTokens.spaceSm),
            ListenableBuilder(
              listenable: GeneralSettingsStore.instance,
              builder: (BuildContext ctx, _) => Text(
                '${l10n.updatedAtLabel} ${_formatDateTime(widget.updatedAt!)}',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          ..._buildActionButtons(context, l10n),
        ],
      ],
    );
  }

  /// 封面行整体。紧凑档为「封面行 + 全宽 chips + 全宽操作按钮」的 Column；
  /// 宽屏档为原有的单行 Row（chips / 按钮仍在右列）。
  Widget _buildHeaderSection(
    BuildContext context,
    AppLocalizations l10n, {
    required bool isCompact,
  }) {
    final Widget coverRow = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildSmallCover(isCompact: isCompact),
        const SizedBox(width: AppTokens.spaceLg),
        Expanded(
          child: _buildTitleBlock(context, l10n, isCompact: isCompact),
        ),
      ],
    );

    if (!isCompact) {
      return Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        child: coverRow,
      );
    }

    final List<Widget> actionButtons = _buildActionButtons(context, l10n);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 紧凑档收紧 Hero 图与头部信息的衔接（顶部 spaceMd、底部 0）。
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.spaceLg,
            AppTokens.spaceMd,
            AppTokens.spaceLg,
            0,
          ),
          child: coverRow,
        ),
        // chips 全宽渲染：Wrap 拥有整屏宽度，正常横排换行。
        if (widget.infoChips.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.spaceLg,
              AppTokens.spaceMd,
              AppTokens.spaceLg,
              0,
            ),
            child: Wrap(
              spacing: AppTokens.spaceSm,
              runSpacing: AppTokens.spaceSm,
              children: widget.infoChips,
            ),
          ),
        // 操作按钮全宽渲染：Wrap 有整屏宽度后按钮可自然并排。
        if (actionButtons.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceLg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: actionButtons,
            ),
          ),
        const SizedBox(height: AppTokens.spaceLg),
      ],
    );
  }

  /// 内容模块入口卡：把「选集/章节、Bangumi 评分与同步、评论、相关推荐」
  /// 折叠为 [AppCard] 内的入口行，点击后在底部弹窗中展开对应模块，避免
  /// 主页长滚动把选集推到底部。
  Widget _buildSectionEntries(BuildContext context, AppLocalizations l10n) {
    final List<Widget> tiles = <Widget>[
      _sectionEntry(
        context,
        icon: Icons.format_list_numbered_rounded,
        title: widget.chaptersTitle ?? l10n.chapterList,
        sheetChild: widget.chaptersList,
      ),
    ];
    if (widget.bangumiSection != null) {
      tiles.add(_sectionEntry(
        context,
        icon: Icons.star_rounded,
        title: l10n.bangumiRatingSync,
        sheetChild: widget.bangumiSection!,
      ));
    }
    if (widget.commentsSection != null) {
      tiles.add(_sectionEntry(
        context,
        icon: Icons.mode_comment_rounded,
        title: l10n.comments,
        sheetChild: widget.commentsSection!,
      ));
    }
    if (widget.recommendations != null) {
      tiles.add(_sectionEntry(
        context,
        icon: Icons.recommend_rounded,
        title: l10n.recommendations,
        sheetChild: widget.recommendations!,
      ));
    }
    final List<Widget> children = <Widget>[];
    for (int i = 0; i < tiles.length; i++) {
      if (i > 0) children.add(const Divider(height: 1, indent: 56));
      children.add(tiles[i]);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceLg,
        AppTokens.spaceSm,
        AppTokens.spaceLg,
        0,
      ),
      child: AppCard(
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }

  /// 单个入口行：图标 + 标题 + 右箭头，点击唤起底部弹窗。
  Widget _sectionEntry(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Widget sheetChild,
  }) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: scheme.primary),
      title: Text(title),
      trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
      onTap: () => _openSectionSheet(context, sheetChild),
    );
  }

  /// 底部弹窗：可拖拽、可滚动，承载入口对应的模块内容。
  void _openSectionSheet(BuildContext context, Widget child) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTokens.radiusLg)),
      ),
      builder: (_) => _DetailSectionSheet(child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;

    final scrollView = CustomScrollView(
      // 弹性滚动：下拉/触底带拉伸回弹手感，配合下拉刷新更灵动。
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: <Widget>[
        // ─── Hero SliverAppBar ───
        SliverAppBar(
          pinned: true,
          expandedHeight: 280,
          actions: widget.appBarActions,
          backgroundColor: scheme.surface,
          surfaceTintColor: Colors.transparent,
          flexibleSpace: FlexibleSpaceBar(
            // end 按右侧操作按钮数量预留（每个 IconButton 约 48dp），
            // 防止收起态标题滑入 AppBar 图标底下（窄屏 4-5 个图标时尤甚）。
            titlePadding: EdgeInsetsDirectional.only(
              start: AppTokens.spaceMd,
              bottom: AppTokens.spaceMd,
              end: AppTokens.spaceLg +
                  48.0 * (widget.appBarActions?.length ?? 0),
            ),
            title: Text(
              widget.title,
              style: textTheme.titleLarge?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
                // 渐变遮罩上的可读性保护：封面复杂时标题依然清晰。
                shadows: <Shadow>[
                  Shadow(blurRadius: 8, color: scheme.surface),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            background: _buildHeroBackground(context),
          ),
        ),

        // ─── 封面行（小封面 + 标题 + chips + 操作按钮）───
        // 按可用宽度分档：紧凑档（< compactBreakpoint）chips 与操作按钮
        // 移出右列、在封面行下方全宽渲染，避免窄列内竖排堆叠；
        // 宽屏档保持原有右列结构不变。
        SliverToBoxAdapter(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool isCompact =
                  constraints.maxWidth < AppTokens.compactBreakpoint;
              return _buildHeaderSection(context, l10n, isCompact: isCompact);
            },
          ),
        ),

        // ─── 简介区（AppCard 包裹，可展开/收起）───
        if (widget.description != null && widget.description!.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceLg),
              child: AppCard(
                child: Padding(
                  padding: const EdgeInsets.all(AppTokens.spaceMd),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        widget.description!,
                        style: textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                        maxLines: _descriptionExpanded ? null : 4,
                        overflow: _descriptionExpanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          // 紧凑密度：减少窄屏纵向空间浪费。
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => setState(
                            () => _descriptionExpanded =
                                !_descriptionExpanded,
                          ),
                          child: Text(
                            _descriptionExpanded
                                ? l10n.collapse
                                : l10n.expand,
                            style: textTheme.labelLarge?.copyWith(
                                  color: scheme.primary,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // ─── 标签区 ───
        if (widget.tags != null && widget.tags!.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceLg,
                  vertical: AppTokens.spaceSm),
              child: Wrap(
                spacing: AppTokens.spaceSm,
                runSpacing: AppTokens.spaceSm,
                children: widget.tags!,
              ),
            ),
          ),

        // ─── 进度卡 ───
        if (widget.progressSection != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spaceLg,
                AppTokens.spaceSm,
                AppTokens.spaceLg,
                AppTokens.spaceMd,
              ),
              child: widget.progressSection!,
            ),
          ),

        // ─── 内容模块入口（选集 / Bangumi / 评论 / 相关推荐 → 弹窗分流）───
        SliverToBoxAdapter(child: _buildSectionEntries(context, l10n)),
        const SliverToBoxAdapter(
            child: SizedBox(height: AppTokens.spaceLg)),
      ],
    );

    // 下拉刷新（弹性指示器）
    if (widget.onRefresh != null) {
      return AppRefreshIndicator(
        onRefresh: widget.onRefresh!,
        child: scrollView,
      );
    }
    return scrollView;
  }
}

/// 内容模块底部弹窗容器。不自带标题（各模块 widget 已含内部
/// 标题，避免双标题），仅提供拖拽把手 + 关闭按钮，内容区可滚动。
class _DetailSectionSheet extends StatelessWidget {
  final Widget child;
  const _DetailSectionSheet({required this.child});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double maxHeight = MediaQuery.of(context).size.height * 0.85;
    return AppSheetBody(
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                height: 40,
                child: Stack(
                  children: <Widget>[
                    Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding:
                            const EdgeInsets.only(top: AppTokens.spaceSm),
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: const Icon(Icons.close_rounded),
                        iconSize: 20,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.only(bottom: AppTokens.spaceLg),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
