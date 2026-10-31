/// 软件公告页 —— 设置里的公告入口。
///
/// 启动弹窗只展示「未读」公告，读过即不再打扰；本页提供常驻入口，
/// 随时回看历史公告（含版本更新说明、运营通知）。内容与弹窗同源
/// （[SoftwareAnnouncementService]，远程多源 + 本地缓存兜底）。
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/software_announcement_service.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/app_animations.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_glass_bar.dart';

class SettingsAnnouncementsScreen extends StatefulWidget {
  const SettingsAnnouncementsScreen({super.key});

  @override
  State<SettingsAnnouncementsScreen> createState() =>
      _SettingsAnnouncementsScreenState();
}

class _SettingsAnnouncementsScreenState
    extends State<SettingsAnnouncementsScreen> {
  List<SoftwareAnnouncement> _items = const <SoftwareAnnouncement>[];
  bool _loading = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = SoftwareAnnouncementService.instance;
    if (!service.loaded) {
      await service.load();
    }
    if (!mounted) return;
    setState(() {
      _items = _sorted(service.all);
      _loading = false;
    });
    // 打开即视为已读：避免下次启动重复弹出同一批公告。
    unawaited(service.markSeen(<String>[for (final a in _items) a.id]));
    unawaited(_refresh(silent: true));
  }

  /// 按日期倒序（`yyyy-MM-dd` 可直接字符串比较），无日期的排在最后。
  List<SoftwareAnnouncement> _sorted(List<SoftwareAnnouncement> list) {
    final out = List<SoftwareAnnouncement>.of(list);
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_refreshing) return;
    if (!silent && mounted) setState(() => _refreshing = true);
    final ok = await SoftwareAnnouncementService.instance.refresh();
    if (!mounted) return;
    setState(() {
      _refreshing = false;
      if (ok) _items = _sorted(SoftwareAnnouncementService.instance.all);
    });
    if (!ok && !silent) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).loadFailed),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appAnnouncement),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.maybePop(context),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.refresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            onPressed: _refreshing
                ? null
                : () {
                    AppHaptics.selectionClick();
                    unawaited(_refresh());
                  },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _refresh(),
              child: ListView(
                padding: context.pageInset(AppTokens.spaceLg),
                physics: const AlwaysScrollableScrollPhysics(),
                children: <Widget>[
                  if (_items.isEmpty)
                    _EmptyAnnouncement(l10n: l10n)
                  else
                    for (var i = 0; i < _items.length; i++)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: i == _items.length - 1
                              ? 0
                              : AppTokens.spaceMd,
                        ),
                        child: Entrance(
                          onceKey: 'announcement_${_items[i].id}',
                          index: i,
                          child: _AnnouncementCard(item: _items[i]),
                        ),
                      ),
                ],
              ),
            ),
    );
  }
}

/// 单条公告卡：日期 + 标题 + 正文 + 可选外链。
class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.item});

  final SoftwareAnnouncement item;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final bool isZh = Localizations.localeOf(context).languageCode == 'zh';
    final String title = isZh ? item.title : item.titleEn;
    final String body = isZh ? item.body : item.bodyEn;
    final String urlText = isZh ? item.urlText : item.urlTextEn;

    return AppCard(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (item.date.isNotEmpty)
            Text(
              item.date,
              style: textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          if (item.date.isNotEmpty) const SizedBox(height: AppTokens.spaceXs),
          Text(
            title,
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (body.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              body,
              style: textTheme.bodySmall?.copyWith(height: 1.55),
            ),
          ],
          if (item.url.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppTokens.spaceSm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => _openUrl(item.url),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(
                  urlText.trim().isEmpty ? item.url : urlText,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 空态：公告清单为空（首次安装且离线时可出现）。
class _EmptyAnnouncement extends StatelessWidget {
  const _EmptyAnnouncement({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceXl * 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.campaign_outlined,
            size: 56,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          Text(
            l10n.announcementsEmpty,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

Future<void> _openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  try {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  } catch (_) {
    // 外链打开失败静默忽略。
  }
}
