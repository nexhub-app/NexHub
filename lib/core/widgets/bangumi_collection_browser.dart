/// 设置页「浏览 Bangumi 收藏」组件。
///
/// 按条目类型（动画 / 三次元 / 书籍）与收藏状态（想看 / 在看 / 看过 / 搁置 /
/// 抛弃）筛选，拉取当前登录用户的 Bangumi 收藏列表并展示条目名称、评分与短评；
/// 点击列表项唤起 [showBangumiSubjectSheet] 查看来自 Bangumi 的条目信息。
library;

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../services/bangumi/bangumi_client.dart';
import '../services/bangumi/bangumi_models.dart';
import '../services/bangumi/bangumi_sync_service.dart';
import '../theme/app_tokens.dart';
import '../utils/app_haptics.dart';
import 'bangumi_subject_sheet.dart';
import 'desktop_horizontal_scroll.dart';

class BangumiCollectionBrowser extends StatefulWidget {
  const BangumiCollectionBrowser({super.key});

  @override
  State<BangumiCollectionBrowser> createState() =>
      _BangumiCollectionBrowserState();
}

class _BangumiCollectionBrowserState extends State<BangumiCollectionBrowser> {
  int _subjectType = BangumiSubjectType.anime;
  int _collectionType = BangumiCollectionType.wish;
  List<BangumiUserCollection> _items = const <BangumiUserCollection>[];
  bool _loading = false;
  bool _failed = false;
  bool _loadedOnce = false;

  /// 失败时的具体原因（如 HTTP 401 / 用户不存在 / 网络错误），
  /// 展示在失败态供诊断“无法获取内容”的真实成因。
  String? _errorDetail;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final service = context.read<BangumiSyncService>();
    setState(() {
      _loading = true;
      _failed = false;
      _errorDetail = null;
    });
    try {
      // 用户名缺失（旧版升级 / secure storage 曾读失败）时用已存 token
      // 重新拉取 /v0/me 恢复，避免静默无输出。
      var username = service.auth.username;
      if (username == null || username.isEmpty) {
        await service.auth.refreshProfile();
        username = service.auth.username;
      }
      if (username == null || username.isEmpty) {
        throw StateError('missing bangumi username');
      }
      List<BangumiUserCollection> items;
      try {
        items = await service.client.fetchUserCollections(
          username,
          subjectType: _subjectType,
          collectionType: _collectionType,
        );
      } on BangumiApiException catch (e) {
        // 404 = 用户不存在。API 规范：设置自定义用户名后无法再用数字 UID
        // 访问该路径，本地缓存的用户名可能已过期 —— 强制刷新 /v0/me
        // 拿最新用户名重试一次，仍失败才上报。
        if (e.statusCode != 404) rethrow;
        await service.auth.refreshProfile();
        final fresh = service.auth.username;
        if (fresh == null || fresh.isEmpty || fresh == username) rethrow;
        items = await service.client.fetchUserCollections(
          fresh,
          subjectType: _subjectType,
          collectionType: _collectionType,
        );
      }
      if (mounted) setState(() => _items = items);
    } on BangumiApiException catch (e) {
      // 鉴权失败 / 用户不存在 / 参数错误：展示状态码与描述供诊断。
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        final expired = service.auth.sessionExpired;
        setState(() {
          _failed = true;
          if (e.isUnauthorized && expired) {
            // 续期已被服务端拒绝、本地凭证已清空 → 引导重新授权，
            // 而不是把「access token has been expired」原文甩给用户。
            _errorDetail = l10n.loginExpired;
          } else if (e.isUnauthorized) {
            // 仍持令牌却被拒：带上命中主机，便于区分「令牌真失效」与
            // 「镜像反代没转发 Authorization 头」。
            _errorDetail = 'HTTP ${e.statusCode}: ${e.message}'
                '${e.host == null || e.host!.isEmpty ? '' : ' @${e.host}'}';
          } else {
            _errorDetail =
                e.statusCode != null ? 'HTTP ${e.statusCode}: ${e.message}' : e.message;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _errorDetail = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadedOnce = true;
        });
      }
    }
  }

  void _selectSubjectType(int type) {
    if (_subjectType == type) return;
    setState(() => _subjectType = type);
    _load();
  }

  void _selectCollectionType(int type) {
    if (_collectionType == type) return;
    setState(() => _collectionType = type);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ───── 条目类型筛选 ─────
        Wrap(
          spacing: AppTokens.spaceSm,
          children: <Widget>[
            _typeChip(l10n.bangumiSubjectTypeAnime, BangumiSubjectType.anime),
            _typeChip(l10n.bangumiSubjectTypeReal, BangumiSubjectType.real),
            _typeChip(l10n.bangumiSubjectTypeBook, BangumiSubjectType.book),
          ],
        ),
        const SizedBox(height: AppTokens.spaceSm),
        // ───── 收藏状态筛选（固定一排，横向滚动）─────
        DesktopHorizontalScroll(
          builder: (context, controller) => SingleChildScrollView(
            controller: controller,
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                _statusChip(l10n.bangumiStateWish, BangumiCollectionType.wish),
                const SizedBox(width: AppTokens.spaceSm),
                _statusChip(l10n.bangumiStateDoing, BangumiCollectionType.doing),
                const SizedBox(width: AppTokens.spaceSm),
                _statusChip(
                    l10n.bangumiStateCollect, BangumiCollectionType.collect),
                const SizedBox(width: AppTokens.spaceSm),
                _statusChip(l10n.bangumiStateOnHold, BangumiCollectionType.onHold),
                const SizedBox(width: AppTokens.spaceSm),
                _statusChip(
                    l10n.bangumiStateDropped, BangumiCollectionType.dropped),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppTokens.spaceMd),
        // ───── 结果 ─────
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(AppTokens.spaceLg),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_failed)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      l10n.bangumiLoadFailed,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(onPressed: _load, child: Text(l10n.retry)),
                ],
              ),
              if (_errorDetail != null && _errorDetail!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppTokens.spaceXs),
                  child: Text(
                    _errorDetail!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
            ],
          )
        else if (_loadedOnce && _items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppTokens.spaceMd),
            child: Text(
              l10n.bangumiCollectionEmpty,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          )
        else
          ..._items.map((c) => _CollectionTile(collection: c)),
      ],
    );
  }

  Widget _typeChip(String label, int type) => ChoiceChip(
        label: Text(label),
        selected: _subjectType == type,
        onSelected: (_) {
          AppHaptics.selectionClick();
          _selectSubjectType(type);
        },
      );

  Widget _statusChip(String label, int type) => ChoiceChip(
        label: Text(label),
        selected: _collectionType == type,
        onSelected: (_) {
          AppHaptics.selectionClick();
          _selectCollectionType(type);
        },
      );
}

/// 单条收藏项：封面 + 名称 + 站点评分 / 短评 + 我的评分，点击查看条目信息。
class _CollectionTile extends StatelessWidget {
  final BangumiUserCollection collection;

  const _CollectionTile({required this.collection});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    // 副标题：优先短评，其次站点平均分。
    Widget? subtitle;
    if (collection.comment.isNotEmpty) {
      subtitle = Text(
        collection.comment,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    } else if (collection.subjectScore > 0) {
      subtitle = Text(
        '${l10n.bangumiSiteRating} '
        '${collection.subjectScore.toStringAsFixed(1)}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _buildCover(theme),
      title: Text(
        collection.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: subtitle,
      trailing: collection.rate > 0
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.star_rounded, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: AppTokens.spaceXxs),
                Text('${collection.rate}', style: theme.textTheme.bodyMedium),
              ],
            )
          : null,
      onTap: () =>
          showBangumiSubjectSheet(context, subjectId: collection.subjectId),
    );
  }

  /// 封面缩略图（无封面时回退图标占位）。
  Widget _buildCover(ThemeData theme) {
    final placeholder = Container(
      width: 40,
      height: 56,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.subject_rounded,
        size: 20,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    final image = collection.subjectImage;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      child: (image != null && image.isNotEmpty)
          ? Image.network(
              image,
              width: 40,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => placeholder,
            )
          : placeholder,
    );
  }
}
