/// 书源章节购买动作的共享 UI 流程（小说 / 漫画阅读器共用）。
///
/// 对齐 legado `ReadBookViewModel.confirmPayAction`：确认 → 执行 payAction
/// → 绝对 URL 打开支付页 / 真值视为已购买（由调用方清正文缓存并重载）。
library;

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../models/plugin_config.dart';
import '../scraper/media_api_service.dart';
import '../widgets/detail_action_utils.dart' show openInAppBrowser;
import 'novel_pay_result.dart';

/// 弹确认框并执行书源购买动作。
///
/// 返回 null 表示用户取消或执行失败（失败已用 SnackBar 提示）；
/// [NovelPayOutcome.openUrl] 时支付页已由本函数打开。
Future<NovelPayResult?> confirmAndRunNovelPay(
  BuildContext context, {
  required MediaApiService service,
  required PluginConfig source,
  required String novelId,
  required String chapterUrl,
  required String chapterTitle,
}) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(l10n.novelPayChapterTitle),
      content: Text(l10n.novelPayChapterConfirm),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.confirm),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return null;
  try {
    final NovelPayResult result = await service.payNovelChapter(
      source,
      novelId: novelId,
      chapterUrl: chapterUrl,
      chapterTitle: chapterTitle,
    );
    if (result.outcome == NovelPayOutcome.openUrl) {
      final String url = result.url ?? '';
      if (url.isNotEmpty && context.mounted) {
        openInAppBrowser(context, url, source: source);
      }
    }
    return result;
  } on Object catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.novelPayChapterFailed}: $e')),
      );
    }
    return null;
  }
}
