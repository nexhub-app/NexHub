/// 书源事件回调（legado `SourceCallBack`）的宿主侧效果消费。
///
/// 脚本里的 `java.open(name, url, title, origin)` / `java.copyText(text)`
/// 只产生请求；界面动作由本文件统一落地（对齐 md3 `RssJsExtensions.open`）：
/// - `login`：origin 指定源（缺省当前源）的登录入口；
/// - `search`：以 title 为关键字搜索，origin 限定搜索范围；
/// - `explore`：origin 指定源（缺省当前源）的发现页，url 为初始分类；
/// - `sort`/`rss`：RSS 专属，书源场景忽略。
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/models/plugin_config.dart';
import '../../../core/navigation/app_navigator.dart';
import '../../../core/navigation/app_page_route.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/utils/app_log.dart';
import '../../../core/widgets/module_source_search_screen.dart';
import '../model/rule_review.dart';
import '../../../generated/app_localizations.dart';
import '../../manga/presentation/manga_online_list_screen.dart';
import '../../media/presentation/media_online_list_screen.dart';
import '../../novel/presentation/novel_online_list_screen.dart';
import '../model/source_callback_result.dart';
import 'shuyuan_login_dialog.dart';

/// 消费一次回调产生的界面效果（剪贴板 + 打开的页面）。
Future<void> drainShuyuanCallbackEffects(
  BuildContext context,
  PluginConfig source,
  SourceCallbackResult result,
) async {
  if (result.copiedTexts.isNotEmpty) {
    await Clipboard.setData(ClipboardData(text: result.copiedTexts.last));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).shareCopied)),
    );
  }
  if (result.openRequests.isEmpty || !context.mounted) return;
  final SourceRepository repo = context.read<SourceRepository>();
  for (final Map<String, String> req in result.openRequests) {
    if (!context.mounted) return;
    final String name = (req['name'] ?? '').trim();
    final String url = (req['url'] ?? '').trim();
    final String title = (req['title'] ?? '').trim();
    final String origin = (req['origin'] ?? '').trim();
    switch (name) {
      case 'login':
        final PluginConfig target = _findTarget(repo, source, origin);
        await showShuyuanLogin(context, target);
      case 'search':
        // md3：title 为空时 search 分支不执行。
        if (title.isEmpty) continue;
        _openSearch(context, repo, source, origin, title);
      case 'explore':
        final PluginConfig target = _findTarget(repo, source, origin);
        _openExplore(context, target, url, title);
      case 'sort':
      case 'rss':
        AppLog.instance.i('[书源回调] 忽略 RSS 专属 open($name)');
      default:
        AppLog.instance.w('[书源回调] 未知 open 动作: $name');
    }
  }
}

/// md3：`origin?.let { getBookSource(o) } ?: 当前源`。
PluginConfig _findTarget(
  SourceRepository repo,
  PluginConfig current,
  String origin,
) {
  if (origin.isEmpty) return current;
  for (final PluginConfig c in repo.all) {
    if (_sameBaseUrl(c.site.baseUrl, origin)) return c;
  }
  return current;
}

bool _sameBaseUrl(String a, String b) =>
    a.replaceAll(RegExp(r'/+$'), '') == b.replaceAll(RegExp(r'/+$'), '');

/// 搜索页：origin 命中时只勾选该源（md3 searchScope），否则交给用户选择。
void _openSearch(
  BuildContext context,
  SourceRepository repo,
  PluginConfig current,
  String origin,
  String keyword,
) {
  PluginConfig? scope;
  if (origin.isNotEmpty) {
    for (final PluginConfig c in repo.all) {
      if (_sameBaseUrl(c.site.baseUrl, origin)) {
        scope = c;
        break;
      }
    }
  }
  final AppLocalizations l10n = AppLocalizations.of(context);
  Navigator.of(context).push(
    AppPageRoute<void>(
      builder: (_) => ModuleSourceSearchScreen(
        sourceType: (scope ?? current).type,
        title: l10n.search,
        initialQuery: keyword,
        startSingle: scope != null,
        initialSourceId: scope?.id,
        onItemTap: (item, heroTag) =>
            AppNavigator.openContentDetail(context, item: item, heroTag: heroTag),
      ),
    ),
  );
}

/// 发现页：按源类型路由到对应模块的在线列表；url 为空时落在源首页。
void _openExplore(
  BuildContext context,
  PluginConfig target,
  String url,
  String title,
) {
  final String? categoryUrl = url.isEmpty ? null : url;
  final String? categoryTitle = title.isEmpty ? null : title;
  final Widget page;
  switch (target.type) {
    case SourceType.mangaSource:
      page = MangaOnlineListScreen(
        initialSource: target,
        initialCategoryUrl: categoryUrl,
        initialCategoryTitle: categoryTitle,
      );
    case SourceType.novelSource:
      page = NovelOnlineListScreen(
        initialSource: target,
        initialCategoryUrl: categoryUrl,
        initialCategoryTitle: categoryTitle,
      );
    case SourceType.animeSource:
    case SourceType.videoSource:
    case SourceType.audioSource:
      page = MediaOnlineListScreen(
        initialSource: target,
        initialCategoryUrl: categoryUrl,
        initialCategoryTitle: categoryTitle,
      );
  }
  Navigator.of(context).push(AppPageRoute<void>(builder: (_) => page));
}

/// 书源是否声明了自定义按钮（md3 `BookSource.customButton`）。
bool shuyuanHasCustomButton(PluginConfig source) {
  final Object? xiaoshuo = source.selectors?['xiaoshuo'];
  return xiaoshuo is Map && xiaoshuo['customButton'] == true;
}

/// 书源声明的段评规则（`selectors['xiaoshuo'].ruleReview`），未声明返回 null。
///
/// 兼容对象与 JSON 字符串两种形态（部分源把整段规则存成字符串）。
ReviewRule? shuyuanReviewRule(PluginConfig source) {
  final Object? xiaoshuo = source.selectors?['xiaoshuo'];
  if (xiaoshuo is! Map) return null;
  final Object? raw = xiaoshuo['ruleReview'];
  try {
    if (raw is Map) {
      return ReviewRule.fromJson(Map<String, dynamic>.from(raw.cast<Object?, Object?>()));
    }
    if (raw is String && raw.trim().isNotEmpty) {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map) {
        return ReviewRule.fromJson(
            Map<String, dynamic>.from(decoded.cast<Object?, Object?>()));
      }
    }
  } catch (_) {}
  return null;
}

/// 书源是否可展示段评面板（声明了列表地址 + 内容规则）。
bool shuyuanHasReviewRule(PluginConfig source) =>
    shuyuanReviewRule(source)?.hasList ?? false;

/// 书源是否开启事件监听（md3 `BookSource.eventListener`）。
bool shuyuanHasEventListener(PluginConfig source) {
  final Object? xiaoshuo = source.selectors?['xiaoshuo'];
  return xiaoshuo is Map && xiaoshuo['eventListener'] == true;
}
