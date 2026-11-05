/// Bangumi 详情页卡片（详情页重构后行为）。
///
/// 不再要求本地收藏即可展示：进入即按 [contentId]/[title] 经
/// [SubjectLinkStore.resolve] 解析 Bangumi 条目，命中后直接展示来自 Bangumi
/// 的评分 / 简介 / 标签，并在其下方提供内联同步面板（收藏状态 / 隐藏 / 进度 /
/// 评价 / 一键同步），直接写回 Bangumi（无需经过收藏流程）。
library;

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../favorites/favorites_manager.dart';
import '../models/plugin_config.dart';
import '../services/bangumi/bangumi_client.dart';
import '../services/bangumi/bangumi_models.dart';
import '../services/bangumi/bangumi_sync_service.dart';
import '../services/bangumi/subject_link_store.dart';
import '../theme/app_tokens.dart';
import '../utils/app_haptics.dart';
import 'app_card.dart';
import 'bangumi_bind_sheet.dart';
import 'bangumi_subject_sheet.dart';

/// 解析状态机。
enum _ResolveState { loading, resolved, candidates, noMatch, error }

class BangumiDetailCard extends StatefulWidget {
  final String contentId;
  final String title;
  final SourceType sourceType;

  const BangumiDetailCard({
    super.key,
    required this.contentId,
    required this.title,
    required this.sourceType,
  });

  @override
  State<BangumiDetailCard> createState() => _BangumiDetailCardState();
}

class _BangumiDetailCardState extends State<BangumiDetailCard> {
  _ResolveState _state = _ResolveState.loading;
  SubjectLink? _link;
  BangumiSubjectDetail? _detail;
  BangumiUserCollection? _remote;

  /// 低置信候选（需用户手动确认绑定）。
  List<BangumiSubject> _candidates = const <BangumiSubject>[];
  bool _loadingDetail = false;
  bool _detailFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 三步解析：缓存 → 标题搜索高置信自动采用 → 候选返回。
  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _state = _ResolveState.loading;
      _detailFailed = false;
      _remote = null;
    });
    final BangumiSyncService service = context.read<BangumiSyncService>();
    try {
      final result = await service.linkStore.resolve(
        widget.contentId,
        widget.title,
        widget.sourceType,
      );
      if (!mounted) return;
      if (result.link != null) {
        _link = result.link;
        _state = _ResolveState.resolved;
        // 详情（公开）与远端收藏（需登录）并行拉取。
        await Future.wait(<Future<void>>[
          _fetchDetail(result.link!.subjectId),
          _fetchRemote(result.link!.subjectId),
        ]);
      } else if (result.candidates.isNotEmpty) {
        _candidates = result.candidates;
        _state = _ResolveState.candidates;
      } else {
        _state = _ResolveState.noMatch;
      }
    } catch (_) {
      if (!mounted) return;
      _state = _ResolveState.error;
    }
    if (mounted) setState(() {});
  }

  Future<void> _fetchDetail(int subjectId) async {
    final BangumiSyncService service = context.read<BangumiSyncService>();
    setState(() => _loadingDetail = true);
    try {
      final detail = await service.client.fetchSubject(subjectId);
      if (mounted) setState(() => _detail = detail);
    } catch (_) {
      if (mounted) setState(() => _detailFailed = true);
    } finally {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  Future<void> _fetchRemote(int subjectId) async {
    final BangumiSyncService service = context.read<BangumiSyncService>();
    try {
      final remote = await service.client.fetchUserCollection(subjectId);
      if (mounted) setState(() => _remote = remote);
    } catch (_) {
      if (mounted) setState(() => _remote = null);
    }
  }

  /// 打开绑定面板（手动搜索 / 重新绑定），关闭后重新解析。
  Future<void> _rebind() async {
    await showBangumiBindSheet(
      context,
      contentId: widget.contentId,
      sourceType: widget.sourceType,
    );
    if (mounted) await _load();
  }

  Future<void> _bindCandidate(BangumiSubject subject) async {
    final BangumiSyncService service = context.read<BangumiSyncService>();
    await service.linkStore.put(
      widget.contentId,
      SubjectLink(subjectId: subject.id),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildSubjectArea(context, l10n, theme),
          if (_state == _ResolveState.resolved && _link != null) ...<Widget>[
            const Divider(height: 1),
            _BangumiSyncPanel(
              // key 绑定 subjectId：换条目时整体重建，避免丢失用户编辑态的歧义。
              key: ValueKey<int>(_link!.subjectId),
              subjectId: _link!.subjectId,
              contentId: widget.contentId,
              sourceType: widget.sourceType,
              initialRemote: _remote,
            ),
          ],
        ],
      ),
    );
  }

  /// 依据解析状态分派主体区域。
  Widget _buildSubjectArea(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    switch (_state) {
      case _ResolveState.loading:
        return const Padding(
          padding: EdgeInsets.all(AppTokens.spaceMd),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      case _ResolveState.error:
        return _rowWithRetry(
          l10n,
          theme,
          l10n.bangumiLoadFailed,
          _load,
        );
      case _ResolveState.candidates:
        return _buildCandidates(l10n, theme);
      case _ResolveState.noMatch:
        return _rowWithAction(
          l10n,
          theme,
          l10n.bangumiNoMatch,
          l10n.bangumiManualBind,
          _rebind,
        );
      case _ResolveState.resolved:
        return _buildResolvedHeader(context, l10n, theme);
    }
  }

  Widget _rowWithRetry(
    AppLocalizations l10n,
    ThemeData theme,
    String message,
    VoidCallback onRetry,
  ) =>
      Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton(onPressed: onRetry, child: Text(l10n.retry)),
          ],
        ),
      );

  Widget _rowWithAction(
    AppLocalizations l10n,
    ThemeData theme,
    String message,
    String actionLabel,
    VoidCallback onAction,
  ) =>
      Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.link_rounded, size: 16),
              label: Text(actionLabel),
            ),
          ],
        ),
      );

  /// 低置信候选：列出候选供用户点选绑定。
  Widget _buildCandidates(AppLocalizations l10n, ThemeData theme) => Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              l10n.bangumiConfirmBind,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppTokens.spaceSm),
            for (final c in _candidates.take(5))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: c.image != null
                    ? ClipRRect(
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusSm),
                        child: Image.network(
                          c.image!,
                          width: 32,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.tv_rounded),
                        ),
                      )
                    : const Icon(Icons.tv_rounded),
                title: Text(
                  c.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  <String>[
                    if (c.name != c.displayName) c.name,
                    if (c.date != null) c.date!,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: TextButton(
                  onPressed: () => _bindCandidate(c),
                  child: Text(l10n.bangumiBindSubject),
                ),
              ),
            const SizedBox(height: AppTokens.spaceSm),
            OutlinedButton.icon(
              onPressed: _rebind,
              icon: const Icon(Icons.search_rounded, size: 16),
              label: Text(l10n.bangumiManualBind),
            ),
          ],
        ),
      );

  /// 已解析：展示来自 Bangumi 的评分 / 简介 / 标签。
  Widget _buildResolvedHeader(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    if (_loadingDetail) {
      return const Padding(
        padding: EdgeInsets.all(AppTokens.spaceMd),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_detailFailed || _detail == null) {
      return _rowWithRetry(
        l10n,
        theme,
        l10n.bangumiLoadFailed,
        () => _fetchDetail(_link!.subjectId),
      );
    }

    final detail = _detail!;
    final rating = detail.rating;
    final col = detail.collection;
    final ColorScheme scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppTokens.spaceXs,
        horizontal: AppTokens.spaceSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ───── 标题行 + 跳转 / 重新绑定 ─────
          Row(
            children: <Widget>[
              if (detail.image != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                  child: Image.network(
                    detail.image!,
                    width: 48,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.tv_rounded),
                  ),
                )
              else
                const Icon(Icons.tv_rounded),
              const SizedBox(width: AppTokens.spaceSm),
              Expanded(
                child: Text(
                  detail.displayName,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                tooltip: l10n.bangumiViewOnWeb,
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    showBangumiSubjectSheet(context, subjectId: detail.id),
              ),
              IconButton(
                icon: const Icon(Icons.link_rounded, size: 18),
                tooltip: l10n.bangumiManualBind,
                visualDensity: VisualDensity.compact,
                onPressed: _rebind,
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceXs),
          // ───── 评分 + 排名 ─────
          if (rating.hasScore)
            Row(
              children: <Widget>[
                Icon(Icons.star_rounded, color: scheme.primary, size: 22),
                const SizedBox(width: AppTokens.spaceXs),
                Text(
                  rating.score.toStringAsFixed(1),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: AppTokens.spaceSm),
                if (rating.rank > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(AppTokens.radiusFull),
                    ),
                    child: Text(
                      '#${rating.rank}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const Spacer(),
                Text(
                  l10n.bangumiRatingUsers(rating.total),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            )
          else
            Text(
              l10n.bangumiNoRating,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          // ───── 收藏统计（横排紧凑）─────
          if (col.total > 0) ...<Widget>[
            const SizedBox(height: AppTokens.spaceXs),
            Wrap(
              spacing: AppTokens.spaceMd,
              runSpacing: AppTokens.spaceXs,
              children: <Widget>[
                if (col.wish > 0)
                  _StatChip(
                    label: l10n.bangumiCollectionWish(col.wish),
                    icon: Icons.favorite_rounded,
                    scheme: scheme,
                  ),
                if (col.doing > 0)
                  _StatChip(
                    label: l10n.bangumiCollectionDoing(col.doing),
                    icon: Icons.play_circle_rounded,
                    scheme: scheme,
                  ),
                if (col.collect > 0)
                  _StatChip(
                    label: l10n.bangumiCollectionCollect(col.collect),
                    icon: Icons.check_circle_rounded,
                    scheme: scheme,
                  ),
              ],
            ),
          ],
          // ───── 元信息行（话数 · 放送日期）─────
          if (detail.eps > 0 || detail.airDate != null) ...<Widget>[
            const SizedBox(height: AppTokens.spaceXs),
            Row(
              children: <Widget>[
                if (detail.eps > 0)
                  Text(
                    l10n.bangumiEps(detail.eps),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                if (detail.eps > 0 && detail.airDate != null)
                  Text('  ·  ', style: theme.textTheme.bodySmall),
                if (detail.airDate != null)
                  Text(
                    l10n.bangumiAirDate(detail.airDate!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
          // ───── 简介 ─────
          if (detail.summary.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              detail.summary.trim(),
              style: theme.textTheme.bodyMedium,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          // ───── 用户标签 ─────
          if (detail.tags.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppTokens.spaceSm),
            Wrap(
              spacing: AppTokens.spaceSm,
              runSpacing: AppTokens.spaceXs,
              children: detail.tags
                  .take(6)
                  .map(
                    (t) => Chip(
                      label: Text(t),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: AppTokens.spaceXs),
          Text(
            l10n.bangumiFromBangumi,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 内联同步面板：直接写回 Bangumi，无需本地收藏。
///
/// 字段：收藏状态（想看/在看/看过/搁置/抛弃）、隐藏收藏、进度（已看集/章）、
/// 评价（评分 + 短评）；「从 Bangumi 拉取」回填远端状态，「保存并同步」推送到
/// Bangumi（未登录时仅本地保存）。
class _BangumiSyncPanel extends StatefulWidget {
  final int subjectId;
  final String contentId;
  final SourceType sourceType;
  final BangumiUserCollection? initialRemote;

  const _BangumiSyncPanel({
    super.key,
    required this.subjectId,
    required this.contentId,
    required this.sourceType,
    this.initialRemote,
  });

  @override
  State<_BangumiSyncPanel> createState() => _BangumiSyncPanelState();
}

class _BangumiSyncPanelState extends State<_BangumiSyncPanel> {
  late int _type;
  late bool _private;
  late int _progress;
  late int _rating;
  final TextEditingController _commentController = TextEditingController();
  bool _saving = false;
  bool _pulling = false;

  @override
  void initState() {
    super.initState();
    final BangumiUserCollection? r = widget.initialRemote;
    _type = r?.type ?? BangumiCollectionType.wish;
    _private = r?.isPrivate ?? false;
    _progress = r?.epStatus ?? 0;
    _rating = r?.rate ?? 0;
    _commentController.text = r?.comment ?? '';
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  BangumiSyncService get _service => context.read<BangumiSyncService>();

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// 本地最佳努力持久化（未收藏时静默跳过，不影响 Bangumi 推送）。
  Future<void> _persistLocal() async {
    final String comment = _commentController.text.trim();
    try {
      await context.read<FavoritesManager>().updateBangumiMeta(
            widget.contentId,
            widget.sourceType,
            myRating: _rating,
            myComment: comment.isNotEmpty ? comment : null,
          );
    } catch (_) {
      // 未收藏或写入失败均可忽略。
    }
  }

  Future<void> _pull() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _pulling = true);
    try {
      final remote =
          await _service.client.fetchUserCollection(widget.subjectId);
      if (!mounted) return;
      if (remote == null) {
        _showSnack(l10n.bangumiPullEmpty);
      } else {
        setState(() {
          _type = remote.type;
          _private = remote.isPrivate;
          _progress = remote.epStatus;
          _rating = remote.rate;
          _commentController.text = remote.comment;
        });
        _showSnack(l10n.bangumiPullDone);
      }
    } on BangumiApiException catch (e) {
      // 鉴权失败单列提示（令牌被拒 / 会话已失效），其余仍按同步失败处理。
      if (mounted) {
        _showSnack(e.isUnauthorized ? l10n.loginExpired : l10n.bangumiSyncFailed);
      }
    } catch (_) {
      if (mounted) _showSnack(l10n.bangumiSyncFailed);
    } finally {
      if (mounted) setState(() => _pulling = false);
    }
  }

  Future<void> _save() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    final String comment = _commentController.text.trim();
    final payload = CollectionPayload(
      type: _type,
      rate: _rating,
      comment: comment.isNotEmpty ? comment : null,
      epStatus: _progress > 0 ? _progress : null,
      private: _private,
    );
    try {
      await _persistLocal();
      if (_service.auth.isLoggedIn) {
        // patchCollection 在条目未收藏（404）时自动回退 POST 创建。
        await _service.client.patchCollection(widget.subjectId, payload);
        if (mounted) _showSnack(l10n.bangumiSyncDone);
      } else {
        if (mounted) _showSnack(l10n.bangumiSavedLocal);
      }
    } on BangumiApiException catch (e) {
      if (mounted) {
        _showSnack(e.isUnauthorized ? l10n.loginExpired : l10n.bangumiSyncFailed);
      }
    } catch (_) {
      if (mounted) _showSnack(l10n.bangumiSyncFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    final List<(int, String)> types = <(int, String)>[
      (BangumiCollectionType.wish, l10n.bangumiStateWish),
      (BangumiCollectionType.doing, l10n.bangumiStateDoing),
      (BangumiCollectionType.collect, l10n.bangumiStateCollect),
      (BangumiCollectionType.onHold, l10n.bangumiStateOnHold),
      (BangumiCollectionType.dropped, l10n.bangumiStateDropped),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceMd,
        AppTokens.spaceSm,
        AppTokens.spaceMd,
        AppTokens.spaceMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            l10n.bangumiSyncOptions,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppTokens.spaceSm),
          // ───── 收藏状态 ─────
          Text(
            l10n.bangumiCollectionStatus,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppTokens.spaceXs),
          Wrap(
            spacing: AppTokens.spaceXs,
            runSpacing: AppTokens.spaceXs,
            children: <Widget>[
              for (final (int value, String label) in types)
                ChoiceChip(
                  label: Text(label),
                  selected: _type == value,
                  onSelected: (_) => setState(() => _type = value),
                ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceSm),
          // ───── 隐藏收藏 ─────
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.bangumiHideCollection),
            value: _private,
            onChanged: (bool v) {
              v == true ? AppHaptics.toggleOn() : AppHaptics.toggleOff();
              setState(() => _private = v);
            },
            dense: true,
          ),
          // ───── 进度 ─────
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.bangumiProgress,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.remove_rounded),
                onPressed: _progress > 0
                    ? () => setState(() => _progress--)
                    : null,
              ),
              SizedBox(
                width: 36,
                child: Text(
                  '$_progress',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_rounded),
                onPressed: () => setState(() => _progress++),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceXs),
          // ───── 评价 ─────
          Row(
            children: <Widget>[
              Text(
                l10n.bangumiMyRating,
                style: theme.textTheme.bodyMedium,
              ),
              Expanded(
                child: Slider(
                  value: _rating.toDouble(),
                  min: 0,
                  max: 10,
                  divisions: 10,
                  label: _rating > 0 ? '$_rating' : l10n.bangumiRatingNone,
                  onChangeStart: (_) => AppHaptics.light(),
                  onChanged: (double v) => setState(() => _rating = v.round()),
                ),
              ),
              SizedBox(
                width: 24,
                child: Text(
                  _rating > 0 ? '$_rating' : '-',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          TextField(
            controller: _commentController,
            decoration: InputDecoration(
              labelText: l10n.bangumiMyComment,
              hintText: l10n.bangumiCommentHint,
              border: const OutlineInputBorder(),
            ),
            maxLines: 2,
            maxLength: 200,
          ),
          const SizedBox(height: AppTokens.spaceSm),
          // ───── 操作按钮 ─────
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pulling ? null : _pull,
                  icon: _pulling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_download_rounded, size: 16),
                  label: Text(l10n.bangumiPullFromRemote),
                ),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded, size: 16),
                  label: Text(l10n.bangumiSaveSync),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 收藏统计小标签（图标 + 文字，紧凑风格）。
class _StatChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final ColorScheme scheme;

  const _StatChip({
    required this.label,
    required this.icon,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: AppTokens.spaceXxs),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
