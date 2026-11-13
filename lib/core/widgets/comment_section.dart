/// 详情页评论区（源驱动，M-comments）。
///
/// 仅当源声明 `comments` 配置段时由详情页注入 [ContentDetailShell] 的
/// `commentsSection` 槽位渲染；`source.comments == null` 时详情页
/// 完全不渲染任何评论 UI 元素。
///
/// - 头部：评论计数 + 写评论（已登录且声明 post 路由）/「登录后评论」入口，
/// 登录态切换用 [AnimatedSwitcher]。
/// - 预览最多 3 条顶层评论，超出显示「查看全部」→ push [CommentListScreen]。
/// - [CommentTile] 供本区与全量评论页共用：点赞/回复/举报按 comments.routes
/// 声明条件渲染；未登录点击引导登录；内联回复缩进展示可展开。
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../auth/source_auth_manager.dart';
import '../comments/comment_api_service.dart';
import '../models/plugin_config.dart';
import '../navigation/app_page_route.dart';
import '../theme/app_tokens.dart';
import '../utils/app_haptics.dart';
import 'app_animations.dart';
import 'app_card.dart';
import 'app_shimmer.dart';
import 'comment_list_screen.dart';
import 'source_login_sheet.dart';
import 'translatable_text.dart';

/// 详情页评论区。
class CommentSection extends StatefulWidget {
  final PluginConfig source;
  final String contentId;
  final CommentApiService service;

  const CommentSection({
    super.key,
    required this.source,
    required this.contentId,
    this.service = const CommentApiService(),
  });

  @override
  State<CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends State<CommentSection> {
  CommentPage? _page;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page =
          await widget.service.fetchComments(widget.source, widget.contentId);
      if (!mounted) return;
      setState(() {
        _page = page;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  bool get _canPost => widget.source.comments?.routes['post'] != null;

  Future<void> _writeComment() async {
    final posted = await showCommentComposerSheet(
      context,
      source: widget.source,
      contentId: widget.contentId,
      service: widget.service,
    );
    if (!mounted) return;
    if (posted == true) {
      _load();
    } else if (posted == false) {
      // 编辑器内捕获 CommentAuthRequiredException → 登录已失效。
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).loginExpired)),
      );
      showSourceLoginSheet(context, source: widget.source);
    }
  }

  /// 头部动作：已登录（且声明 post 路由）显示「写评论」；未登录显示
  /// 「登录后评论」引导；登录态切换用 AnimatedSwitcher。
  Widget _buildHeaderAction(bool loggedIn, AppLocalizations l10n) {
    final Widget child;
    if (loggedIn) {
      child = _canPost
          ? TextButton.icon(
              key: const ValueKey<String>('write'),
              onPressed: _writeComment,
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: Text(l10n.writeComment),
            )
          : const SizedBox.shrink(key: ValueKey<String>('none'));
    } else {
      child = TextButton.icon(
        key: const ValueKey<String>('login'),
        onPressed: () =>
            showSourceLoginSheet(context, source: widget.source),
        icon: const Icon(Icons.login_rounded, size: 18),
        label: Text(l10n.loginToComment),
      );
    }
    return AnimatedSwitcher(duration: AppTokens.durBase, child: child);
  }

  Widget _buildBody(bool loggedIn, AppLocalizations l10n, ThemeData theme) {
    if (_loading) return const _CommentSkeleton();
    if (_failed) {
      return Column(
        children: <Widget>[
          Text(
            l10n.commentsLoadFailed,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          OutlinedButton(onPressed: _load, child: Text(l10n.retry)),
        ],
      );
    }
    final comments = _page?.comments ?? const <SourceComment>[];
    if (comments.isEmpty) {
      return Column(
        children: <Widget>[
          Text(
            l10n.emptyComments,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (loggedIn && _canPost) ...<Widget>[
            const SizedBox(height: AppTokens.spaceSm),
            OutlinedButton(
              onPressed: _writeComment,
              child: Text(l10n.beFirstToComment),
            ),
          ],
        ],
      );
    }
    final preview = comments.take(3).toList();
    final hasMore = (_page?.hasMore ?? false) || comments.length > 3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final c in preview)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
            child: CommentTile(
              source: widget.source,
              comment: c,
              service: widget.service,
            ),
          ),
        if (hasMore)
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(
              AppPageRoute<void>(
                builder: (_) => CommentListScreen(
                  source: widget.source,
                  contentId: widget.contentId,
                  service: widget.service,
                ),
              ),
            ),
            child: Text(l10n.viewAllComments),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final bool loggedIn =
        context.watch<SourceAuthManager>().isLoggedIn(widget.source);
    final int? count = _page?.comments.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceLg,
        AppTokens.spaceMd,
        AppTokens.spaceLg,
        AppTokens.spaceMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  count == null ? l10n.comments : l10n.commentsCount(count),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              _buildHeaderAction(loggedIn, l10n),
            ],
          ),
          const SizedBox(height: AppTokens.spaceSm),
          _buildBody(loggedIn, l10n, theme),
        ],
      ),
    );
  }
}

/// 加载态骨架：3 张微光占位卡。
///
/// 每张卡按索引错开 [AppShimmer.phase]（0 / 0.15 / 0.30），形成自上而下
/// 的呼吸波，替代此前静态灰块的僵硬观感。
class _CommentSkeleton extends StatelessWidget {
  const _CommentSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List<Widget>.generate(3, (int i) {
        final double phase = i * 0.15;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
          child: AppCard(
            child: Row(
              children: <Widget>[
                AppShimmer(
                  width: 32,
                  height: 32,
                  shape: BoxShape.circle,
                  phase: phase,
                ),
                const SizedBox(width: AppTokens.spaceSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      AppShimmer(
                        width: 96,
                        height: 12,
                        borderRadius: AppTokens.radiusSm,
                        phase: phase,
                      ),
                      const SizedBox(height: AppTokens.spaceXs),
                      AppShimmer(
                        height: 12,
                        borderRadius: AppTokens.radiusSm,
                        phase: phase + 0.05,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// 单条评论卡片（评论区与全量评论页共用）。
///
/// 操作行按 `comments.routes` 声明条件渲染：点赞（like）、回复（reply）、
/// 举报（report，PopupMenuButton）。未登录点击任一操作 → 打开登录面板；
/// 登录失效（[CommentAuthRequiredException]）→ 提示并引导重新登录。
class CommentTile extends StatefulWidget {
  final PluginConfig source;
  final SourceComment comment;
  final CommentApiService service;

  const CommentTile({
    super.key,
    required this.source,
    required this.comment,
    this.service = const CommentApiService(),
  });

  @override
  State<CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<CommentTile> {
  /// 点赞乐观状态（站点不返回「是否已赞」时点赞为无状态动作，仅本地标记）。
  bool _liked = false;
  int? _likeCount;

  /// 正文展开态（超 6 行折叠）。
  bool _contentExpanded = false;

  /// 内联回复展开态（默认最多 2 条）。
  bool _repliesExpanded = false;

  /// routes.replies 分页拉取的追加回复。
  final List<SourceComment> _remoteReplies = <SourceComment>[];
  int _replyPage = 1;
  bool _remoteHasMore = true;
  bool _loadingReplies = false;

  Map<String, RouteConfig> get _routes =>
      widget.source.comments?.routes ?? const <String, RouteConfig>{};

  @override
  void initState() {
    super.initState();
    _likeCount = widget.comment.likeCount;
  }

  /// 登录门卫：未登录打开登录面板并返回 false。
  bool _requireLogin() {
    final auth = context.read<SourceAuthManager>();
    if (auth.isLoggedIn(widget.source)) return true;
    showSourceLoginSheet(context, source: widget.source);
    return false;
  }

  /// 登录失效：提示并引导重新登录。
  void _onAuthExpired(AppLocalizations l10n) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.loginExpired)));
    showSourceLoginSheet(context, source: widget.source);
  }

  Future<void> _like(AppLocalizations l10n) async {
    if (_liked || !_requireLogin()) return;
    // MD3「Toggle」：点赞 → tick。
    AppHaptics.toggleOn();
    // 乐观更新：先 +1，失败回滚。
    setState(() {
      _liked = true;
      _likeCount = (_likeCount ?? 0) + 1;
    });
    var ok = false;
    try {
      ok = await widget.service
          .likeComment(widget.source, widget.comment.id);
    } on CommentAuthRequiredException {
      _rollbackLike();
      _onAuthExpired(l10n);
      return;
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      _rollbackLike();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.likeFailed)));
      }
    }
  }

  void _rollbackLike() {
    if (!mounted) return;
    setState(() {
      _liked = false;
      _likeCount = (_likeCount ?? 1) - 1;
    });
  }

  Future<void> _reply() async {
    if (!_requireLogin()) return;
    final posted = await showCommentComposerSheet(
      context,
      source: widget.source,
      replyToCommentId: widget.comment.id,
      service: widget.service,
    );
    if (posted == false && mounted) {
      _onAuthExpired(AppLocalizations.of(context));
    }
  }

  Future<void> _report(AppLocalizations l10n) async {
    if (!_requireLogin()) return;
    var ok = false;
    try {
      ok = await widget.service
          .reportComment(widget.source, widget.comment.id);
    } on CommentAuthRequiredException {
      _onAuthExpired(l10n);
      return;
    } catch (_) {
      ok = false;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? l10n.reportSuccess : l10n.reportFailed)),
      );
    }
  }

  /// 「查看更多回复」：先展开内联回复，routes.replies 存在时继续分页拉取。
  Future<void> _loadMoreReplies() async {
    if (!_repliesExpanded) {
      setState(() => _repliesExpanded = true);
      return;
    }
    if (_routes['replies'] == null || _loadingReplies || !_remoteHasMore) {
      return;
    }
    setState(() => _loadingReplies = true);
    try {
      final page = await widget.service.fetchReplies(
        widget.source,
        widget.comment.id,
        page: _replyPage,
      );
      if (!mounted) return;
      setState(() {
        _replyPage++;
        _remoteReplies.addAll(page.comments);
        _remoteHasMore = page.hasMore && page.comments.isNotEmpty;
        _loadingReplies = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _remoteHasMore = false;
          _loadingReplies = false;
        });
      }
    }
  }

  Widget _buildAvatar(ThemeData theme) {
    final url = widget.comment.avatarUrl;
    if (url != null && url.startsWith('http')) {
      return CircleAvatar(
        radius: 16,
        backgroundColor: theme.colorScheme.primaryContainer,
        backgroundImage: CachedNetworkImageProvider(url),
      );
    }
    return CircleAvatar(
      radius: 16,
      backgroundColor: theme.colorScheme.primaryContainer,
      child: Icon(
        Icons.person_rounded,
        size: 18,
        color: theme.colorScheme.onPrimaryContainer,
      ),
    );
  }

  /// 正文：超 6 行折叠展开（按字符数/换行数启发式判断是否需要折叠按钮）。
  Widget _buildContent(AppLocalizations l10n, ThemeData theme) {
    final text = widget.comment.content;
    final bool collapsible =
        text.length > 120 || '\n'.allMatches(text).length >= 6;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        BilingualTranslatedText(
          text: text,
          kind: TranslatableTextKind.comment,
          style: theme.textTheme.bodyMedium,
          maxLines: _contentExpanded ? null : 6,
          overflow:
              _contentExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
        ),
        if (collapsible)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () =>
                  setState(() => _contentExpanded = !_contentExpanded),
              child: Text(_contentExpanded ? l10n.collapse : l10n.expand),
            ),
          ),
      ],
    );
  }

  /// 操作行：点赞 / 回复 / 举报，均按路由声明条件渲染。
  Widget _buildActions(AppLocalizations l10n, ThemeData theme) {
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      children: <Widget>[
        if (_routes['like'] != null)
          InkWell(
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            onTap: () => _like(l10n),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceXs,
                vertical: 2,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AnimatedSwitcher(
                    duration: AppTokens.durBase,
                    transitionBuilder:
                        (Widget child, Animation<double> anim) =>
                            ScaleTransition(
                      scale: CurvedAnimation(
                        parent: anim,
                        curve: AppCurves.springStrong,
                      ),
                      child: child,
                    ),
                    child: Icon(
                      _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      key: ValueKey<bool>(_liked),
                      size: 16,
                      color: _liked ? theme.colorScheme.primary : muted,
                    ),
                  ),
                  if (_likeCount != null) ...<Widget>[
                    const SizedBox(width: AppTokens.spaceXs),
                    Text(
                      '$_likeCount',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: muted),
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (_routes['reply'] != null) ...<Widget>[
          const SizedBox(width: AppTokens.spaceSm),
          TextButton.icon(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: muted,
            ),
            onPressed: _reply,
            icon: const Icon(Icons.chat_bubble_rounded, size: 16),
            label: Text(l10n.replyComment),
          ),
        ],
        const Spacer(),
        if (_routes['report'] != null)
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz_rounded, size: 18, color: muted),
            onSelected: (_) => _report(l10n),
            itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'report',
                child: Text(l10n.reportAction),
              ),
            ],
          ),
      ],
    );
  }

  /// 内联回复：缩进展示，默认最多 2 条 + 「查看更多回复」展开
  /// （AnimatedSize 过渡；routes.replies 存在时可继续分页拉取）。
  Widget _buildReplies(AppLocalizations l10n, ThemeData theme) {
    final inline = widget.comment.replies;
    final int declared = widget.comment.replyCount ?? inline.length;
    if (inline.isEmpty && (declared == 0 || _routes['replies'] == null)) {
      return const SizedBox.shrink();
    }
    final visible = _repliesExpanded
        ? <SourceComment>[...inline, ..._remoteReplies]
        : inline.take(2).toList();
    final bool showMoreButton = !_repliesExpanded
        ? (inline.length > 2 ||
            (_routes['replies'] != null && declared > inline.length))
        : (_routes['replies'] != null &&
            _remoteHasMore &&
            declared > visible.length);
    return AnimatedSize(
      duration: AppTokens.durBase,
      curve: AppCurves.smooth,
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(
          left: AppTokens.spaceXl,
          top: AppTokens.spaceSm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final r in visible)
              Padding(
                padding: const EdgeInsets.only(bottom: AppTokens.spaceXs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            r.author,
                            style: theme.textTheme.labelMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (r.timeText != null)
                          Text(
                            r.timeText!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    BilingualTranslatedText(
                      text: r.content,
                      kind: TranslatableTextKind.comment,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            if (_loadingReplies)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppTokens.spaceXs),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (showMoreButton)
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _loadMoreReplies,
                child: Text(l10n.viewMoreReplies),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _buildAvatar(theme),
              const SizedBox(width: AppTokens.spaceSm),
              Expanded(
                child: Text(
                  widget.comment.author,
                  style: theme.textTheme.labelLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.comment.timeText != null)
                Text(
                  widget.comment.timeText!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceSm),
          _buildContent(l10n, theme),
          _buildActions(l10n, theme),
          _buildReplies(l10n, theme),
        ],
      ),
    );
  }
}

/// 评论编辑器底部面板。
///
/// [contentId] 非空发布顶层评论（post 路由）；[replyToCommentId] 非空回复
/// 某评论（reply 路由）。返回 `true` 表示发布成功（调用方可刷新列表）；
/// 返回 `false` 表示登录已失效（调用方提示并引导重新登录）；null 为取消。
Future<bool?> showCommentComposerSheet(
  BuildContext context, {
  required PluginConfig source,
  String? contentId,
  String? replyToCommentId,
  CommentApiService service = const CommentApiService(),
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTokens.radiusLg),
      ),
    ),
    builder: (BuildContext ctx) => _CommentComposerSheet(
      source: source,
      contentId: contentId,
      replyToCommentId: replyToCommentId,
      service: service,
    ),
  );
}

class _CommentComposerSheet extends StatefulWidget {
  final PluginConfig source;
  final String? contentId;
  final String? replyToCommentId;
  final CommentApiService service;

  const _CommentComposerSheet({
    required this.source,
    required this.contentId,
    required this.replyToCommentId,
    required this.service,
  });

  @override
  State<_CommentComposerSheet> createState() => _CommentComposerSheetState();
}

class _CommentComposerSheetState extends State<_CommentComposerSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _submitting) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _submitting = true);
    var ok = false;
    try {
      if (widget.replyToCommentId != null) {
        ok = await widget.service
            .postReply(widget.source, widget.replyToCommentId!, text);
      } else {
        ok = await widget.service
            .postComment(widget.source, widget.contentId ?? '', text);
      }
    } on CommentAuthRequiredException {
      if (!mounted) return;
      Navigator.of(context).pop(false);
      return;
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.commentPublishSuccess)),
      );
      Navigator.of(context).pop(true);
    } else {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.commentPublishFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final bool canSubmit = _controller.text.trim().isNotEmpty && !_submitting;
    return AppSheetBody(
      child: Padding(
        // 键盘避让：随 viewInsets 抬升。
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.spaceMd,
              AppTokens.spaceSm,
              AppTokens.spaceMd,
              AppTokens.spaceMd,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  widget.replyToCommentId != null
                      ? l10n.replyComment
                      : l10n.writeComment,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppTokens.spaceMd),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  maxLines: 5,
                  maxLength: 500,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: l10n.commentHint,
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppTokens.radiusMd),
                    ),
                  ),
                ),
                const SizedBox(height: AppTokens.spaceSm),
                FilledButton(
                  onPressed: canSubmit ? _submit : null,
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.commentPublish),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
