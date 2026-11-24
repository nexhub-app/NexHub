/// 阅读器段评面板：书源 `ruleReview` 的列表/发帖/回复/赞踩/删除界面。
///
/// 解析与动作全部经由 [MediaApiService] 的 `reviews`/`reviewQuotes`/
/// `reviewAction` 路由（书源引擎），本文件只负责展示与交互。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/plugin_config.dart';
import '../../../core/models/source_review.dart';
import '../../../core/scraper/media_api_service.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/app_log.dart';
import '../../../core/widgets/app_loading_indicator.dart';
import '../../../core/widgets/source_image.dart';
import 'package:nexhub/generated/app_localizations.dart';
import '../../shuyuan/model/rule_review.dart';
import '../../shuyuan/presentation/shuyuan_callback_host.dart';

/// 打开段评面板。[source] 必须是声明了 `ruleReview.reviewUrl` 的书源。
///
/// [paragraph] 非空 = 从某一段落打开（段落锚点，0 起）：面板默认只看本段，
/// 请求把段号绑给 `{{paragraph}}`；顶部可切回「全章」。
Future<void> showNovelReviewSheet(
  BuildContext context, {
  required PluginConfig source,
  required String novelId,
  required String chapterUrl,
  String? chapterTitle,
  int? paragraph,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext sheetContext) =>
        ChangeNotifierProvider<NovelReviewController>(
      create: (_) => NovelReviewController(
        api: sheetContext.read<MediaApiService>(),
        source: source,
        novelId: novelId,
        chapterUrl: chapterUrl,
        chapterTitle: chapterTitle,
        paragraph: paragraph,
      ),
      child: const NovelReviewSheet(),
    ),
  );
}

/// 段评面板状态：列表分页、发帖、回复、赞踩、删除。
class NovelReviewController extends ChangeNotifier {
  NovelReviewController({
    required this.api,
    required this.source,
    required this.novelId,
    required this.chapterUrl,
    this.chapterTitle,
    this.paragraph,
  });

  final MediaApiService api;
  final PluginConfig source;
  final String novelId;
  final String chapterUrl;
  final String? chapterTitle;

  /// 当前段落锚点（null = 全章）。切换时重新拉取（源可用 `{{paragraph}}`
  /// 收窄请求；不支持时段号只用于本地过滤/发帖携带）。
  int? paragraph;

  /// 源声明的段评规则（决定面板上出现哪些动作按钮），首次访问时解析一次。
  late final ReviewRule rule = shuyuanReviewRule(source) ?? ReviewRule();

  List<SourceReview> reviews = const <SourceReview>[];

  /// 面板可见条目：按段过滤时，源侧已给出段号（`paragraphRule`）的条目
  /// 只保留本段；段号为空的条目（源未标注段号、按 URL 收窄返回）一并保留。
  List<SourceReview> get visibleReviews {
    final int? scope = paragraph;
    if (scope == null) return reviews;
    return <SourceReview>[
      for (final r in reviews)
        if (r.paragraph == null || r.paragraph == scope) r,
    ];
  }

  /// 切换「全章 / 本段」并重新拉取。
  Future<void> setScope(int? scope) async {
    // 加载中不切范围：load() 对并发调用是 no-op，切了会留下「范围变了但
    // 列表没变」的错位状态。
    if (loading || paragraph == scope) return;
    paragraph = scope;
    quotes.clear();
    await load();
  }
  bool loading = false;
  bool posting = false;
  String? error;
  int page = 1;
  bool hasMore = false;

  /// 已展开的回复：段评序号 → 回复列表。
  final Map<int, List<SourceReview>> quotes = <int, List<SourceReview>>{};
  final Set<int> loadingQuotes = <int>{};

  Future<void> load({bool append = false}) async {
    if (loading) return;
    loading = true;
    if (!append) {
      error = null;
      page = 1;
    }
    notifyListeners();
    try {
      final result = await api.fetchChapterReviews(
        source,
        novelId: novelId,
        chapterUrl: chapterUrl,
        chapterTitle: chapterTitle,
        page: page,
        paragraph: paragraph,
      );
      reviews = append ? <SourceReview>[...reviews, ...result] : result;
      // 规则没给总数/游标：按「本页满 20 条」判定还有下一页。
      hasMore = result.length >= 20;
      if (append && result.isEmpty) hasMore = false;
    } catch (e) {
      AppLog.instance.w('[段评] 列表加载失败: $e');
      error = '$e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (loading || !hasMore) return;
    page += 1;
    await load(append: true);
  }

  Future<bool> post(String text) => _run(
        () => api.runReviewAction(
          source,
          action: 'post',
          text: text,
          novelId: novelId,
          chapterUrl: chapterUrl,
          chapterTitle: chapterTitle,
          paragraph: paragraph,
        ),
      );

  Future<bool> reply(SourceReview target, String text) => _run(
        () => api.runReviewAction(
          source,
          action: 'quote',
          text: text,
          target: target,
          novelId: novelId,
          chapterUrl: chapterUrl,
          chapterTitle: chapterTitle,
          paragraph: paragraph,
        ),
      );

  Future<bool> vote(SourceReview target, {required bool up}) => _run(
        () => api.runReviewAction(
          source,
          action: up ? 'voteUp' : 'voteDown',
          target: target,
          novelId: novelId,
          chapterUrl: chapterUrl,
          chapterTitle: chapterTitle,
        ),
      );

  Future<bool> delete(SourceReview target) => _run(
        () => api.runReviewAction(
          source,
          action: 'delete',
          target: target,
          novelId: novelId,
          chapterUrl: chapterUrl,
          chapterTitle: chapterTitle,
        ),
      );

  /// 展开/收起某条段评的回复（首次展开时拉取）。
  Future<void> toggleQuotes(SourceReview target) async {
    if (quotes.containsKey(target.index)) {
      quotes.remove(target.index);
      notifyListeners();
      return;
    }
    if (loadingQuotes.contains(target.index)) return;
    loadingQuotes.add(target.index);
    notifyListeners();
    try {
      final list = await api.fetchReviewQuotes(
        source,
        novelId: novelId,
        chapterUrl: chapterUrl,
        target: target,
        chapterTitle: chapterTitle,
      );
      quotes[target.index] = list;
    } catch (e) {
      AppLog.instance.w('[段评] 回复加载失败: $e');
      quotes[target.index] = const <SourceReview>[];
    } finally {
      loadingQuotes.remove(target.index);
      notifyListeners();
    }
  }

  Future<bool> _run(Future<bool> Function() action) async {
    if (posting) return false;
    posting = true;
    notifyListeners();
    var ok = false;
    try {
      ok = await action();
    } catch (e) {
      AppLog.instance.w('[段评] 动作失败: $e');
    } finally {
      posting = false;
      notifyListeners();
    }
    return ok;
  }
}

class NovelReviewSheet extends StatefulWidget {
  const NovelReviewSheet({super.key});

  @override
  State<NovelReviewSheet> createState() => _NovelReviewSheetState();
}

class _NovelReviewSheetState extends State<NovelReviewSheet> {
  final TextEditingController _composer = TextEditingController();
  final Map<int, TextEditingController> _replyControllers =
      <int, TextEditingController>{};
  int? _replyingTo;

  @override
  void initState() {
    super.initState();
    // 列表请求放到首帧后：更改通知不能在 provider 创建（构建期）触发。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<NovelReviewController>().load();
    });
  }

  @override
  void dispose() {
    _composer.dispose();
    for (final c in _replyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _replyControllerFor(int index) =>
      _replyControllers.putIfAbsent(index, TextEditingController.new);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final NovelReviewController c = context.watch<NovelReviewController>();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppTokens.spaceMd, AppTokens.spaceSm, AppTokens.spaceSm, 0),
            child: Row(
              children: <Widget>[
                const Icon(Icons.forum_outlined, size: 20),
                const SizedBox(width: AppTokens.spaceSm),
                Expanded(
                  child: Text(
                    l10n.novelReview,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: c.loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  tooltip: l10n.reloadChapter,
                  onPressed: c.loading ? null : () => c.load(),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
          if (c.rule.hasParagraphAnchor || c.paragraph != null)
            _buildScopeBar(context, c, l10n, scheme),
          const Divider(height: 1),
          Flexible(child: _buildList(context, c, l10n, scheme)),
          if (c.rule.canPost) _buildComposer(context, c, l10n, scheme),
        ],
      ),
    );
  }

  /// 段落锚点范围切换：全章 / 本段。
  Widget _buildScopeBar(
    BuildContext context,
    NovelReviewController c,
    AppLocalizations l10n,
    ColorScheme scheme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceMd, vertical: AppTokens.spaceXs),
      child: Row(
        children: <Widget>[
          ChoiceChip(
            label: Text(l10n.novelReviewScopeChapter),
            selected: c.paragraph == null,
            onSelected: (_) => c.setScope(null),
          ),
          const SizedBox(width: AppTokens.spaceSm),
          ChoiceChip(
            // 从段落进入时段号固定为入口段；源声明 paragraphRule 时也允许
            // 直接按段查看（段号来自入口/默认 0）。
            label: Text(l10n.novelReviewScopeParagraph((c.paragraph ?? 0) + 1)),
            selected: c.paragraph != null,
            onSelected: (_) => c.setScope(c.paragraph ?? 0),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    NovelReviewController c,
    AppLocalizations l10n,
    ColorScheme scheme,
  ) {
    if (c.loading && c.reviews.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AppTokens.spaceLg),
        child: AppLoadingIndicator(),
      );
    }
    if (c.error != null && c.reviews.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(l10n.novelReviewLoadFailed),
            const SizedBox(height: AppTokens.spaceSm),
            TextButton(onPressed: () => c.load(), child: Text(l10n.retry)),
          ],
        ),
      );
    }
    final List<SourceReview> items = c.visibleReviews;
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        child: Text(l10n.novelReviewEmpty,
            style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
      itemCount: items.length + (c.hasMore ? 1 : 0),
      itemBuilder: (BuildContext ctx, int i) {
        if (i >= items.length) {
          return Center(
            child: TextButton(
              onPressed: c.loading ? null : c.loadMore,
              child: Text(l10n.novelReviewLoadMore),
            ),
          );
        }
        final SourceReview review = items[i];
        return _buildReviewTile(context, c, review, l10n, scheme);
      },
    );
  }

  Widget _buildReviewTile(
    BuildContext context,
    NovelReviewController c,
    SourceReview review,
    AppLocalizations l10n,
    ColorScheme scheme,
  ) {
    final List<SourceReview>? quotes = c.quotes[review.index];
    final bool replying = _replyingTo == review.index;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTokens.spaceMd, AppTokens.spaceSm, AppTokens.spaceMd, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SourceImage(
                url: review.avatar.isEmpty ? null : review.avatar,
                source: c.source,
                width: 32,
                height: 32,
                radius: 16,
                fit: BoxFit.cover,
                errorWidget: Icon(Icons.person_rounded,
                    size: 20, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (review.postTime.isNotEmpty)
                      Text(
                        review.postTime,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    const SizedBox(height: 2),
                    SelectableText(review.content),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: AppTokens.spaceXs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        if (c.rule.canVote &&
                            ((c.rule.voteUpUrl ?? '').isNotEmpty))
                          _smallAction(
                            icon: Icons.thumb_up_outlined,
                            label: l10n.novelReviewVoteUp,
                            onTap: c.posting
                                ? null
                                : () => _runAction(
                                      context,
                                      () => c.vote(review, up: true),
                                    ),
                          ),
                        if (c.rule.canVote &&
                            ((c.rule.voteDownUrl ?? '').isNotEmpty))
                          _smallAction(
                            icon: Icons.thumb_down_outlined,
                            label: l10n.novelReviewVoteDown,
                            onTap: c.posting
                                ? null
                                : () => _runAction(
                                      context,
                                      () => c.vote(review, up: false),
                                    ),
                          ),
                        if ((c.rule.reviewQuoteUrl ?? '').isNotEmpty ||
                            c.rule.canQuote)
                          _smallAction(
                            icon: Icons.chat_bubble_outline_rounded,
                            label: (quotes == null || quotes.isEmpty)
                                ? l10n.novelReviewReply
                                : l10n.novelReviewQuotes(quotes.length),
                            onTap: c.loadingQuotes.contains(review.index)
                                ? null
                                : () => c.toggleQuotes(review),
                          ),
                        if (c.rule.canQuote)
                          _smallAction(
                            icon: Icons.reply_rounded,
                            label: l10n.novelReviewReply,
                            onTap: () => setState(() {
                              _replyingTo = replying ? null : review.index;
                            }),
                          ),
                        if (c.rule.canDelete)
                          _smallAction(
                            icon: Icons.delete_outline_rounded,
                            label: l10n.novelReviewDelete,
                            onTap: c.posting
                                ? null
                                : () => _confirmDelete(context, c, review, l10n),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (quotes != null && quotes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                  left: 40, top: AppTokens.spaceXs, bottom: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final SourceReview q in quotes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        q.postTime.isEmpty
                            ? q.content
                            : '${q.postTime}  ${q.content}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
          if (replying)
            Padding(
              padding: const EdgeInsets.only(left: 40, top: AppTokens.spaceXs),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _replyControllerFor(review.index),
                      minLines: 1,
                      maxLines: 3,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: l10n.novelReviewReplyHint,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send_rounded),
                    tooltip: l10n.novelReviewSend,
                    onPressed: c.posting
                        ? null
                        : () async {
                            final String text =
                                _replyControllerFor(review.index).text.trim();
                            if (text.isEmpty) return;
                            final bool ok = await c.reply(review, text);
                            if (!ok || !context.mounted) return;
                            _replyControllerFor(review.index).clear();
                            setState(() => _replyingTo = null);
                            await c.toggleQuotes(review);
                          },
                  ),
                ],
              ),
            ),
          const Divider(height: AppTokens.spaceLg),
        ],
      ),
    );
  }

  Widget _smallAction({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceXs, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14),
            const SizedBox(width: 2),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    NovelReviewController c,
    SourceReview review,
    AppLocalizations l10n,
  ) async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        content: Text(l10n.novelReviewDeleteConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.novelReviewDelete),
          ),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    final bool ok = await c.delete(review);
    if (!context.mounted) return;
    if (!ok) {
      _toast(context, l10n.novelReviewActionFailed);
      return;
    }
    await c.load();
  }

  Future<void> _runAction(
    BuildContext context,
    Future<bool> Function() action,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool ok = await action();
    if (!context.mounted) return;
    _toast(context, ok ? l10n.novelReviewPosted : l10n.novelReviewActionFailed);
  }

  void _toast(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _buildComposer(
    BuildContext context,
    NovelReviewController c,
    AppLocalizations l10n,
    ColorScheme scheme,
  ) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppTokens.spaceMd,
        AppTokens.spaceSm,
        AppTokens.spaceMd,
        AppTokens.spaceSm + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _composer,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.novelReviewPostHint,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: AppTokens.spaceSm),
          FilledButton(
            onPressed: c.posting
                ? null
                : () async {
                    final String text = _composer.text.trim();
                    if (text.isEmpty) return;
                    final bool ok = await c.post(text);
                    if (!context.mounted) return;
                    if (!ok) {
                      _toast(context, l10n.novelReviewActionFailed);
                      return;
                    }
                    _composer.clear();
                    _toast(context, l10n.novelReviewPosted);
                    await c.load();
                  },
            child: Text(l10n.novelReviewSend),
          ),
        ],
      ),
    );
  }
}
