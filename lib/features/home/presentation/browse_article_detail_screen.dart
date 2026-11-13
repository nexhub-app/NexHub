/// RSS article detail reader (Browse -> RSS -> feed detail -> article).
///
/// Renders the article HTML body in-app via [flutter_html] instead of stripping
/// tags to plain text. Supports reading settings (font size / line height /
/// night mode / justify / paragraph spacing / content width) persisted through
/// [ArticleReadingPreferencesNotifier]. A top-bar button triggers on-demand
/// full-text fetch from the source website.
library;

import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:file_picker/file_picker.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/article/article_reading_preferences.dart';
import '../../../core/settings/general_settings.dart';
import '../../../core/rss/rss_feed.dart';
import '../../../core/rss/rss_article_store.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_alert_dialog.dart';
import '../../../core/theme/reader_tokens.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/translatable_text.dart';
import '../../../core/widgets/source_image.dart';
import '../../../features/rss/presentation/rss_image_actions.dart';
import '../../../features/rss/presentation/rss_image_gallery.dart';
import '../../../features/rss/presentation/rss_inline_video_player.dart';
import '../../../features/rss/presentation/rss_video_player.dart'
    show isDirectMediaUrl, RssVideoPlayer;
import '../../browser/presentation/http_browser_screen.dart';
import '../../rss/presentation/rss_podcast_player.dart';
import '../../../core/widgets/app_glass_bar.dart';

/// Single RSS article detail reader page.
class BrowseArticleDetailScreen extends StatefulWidget {
  final RssItem item;

  /// 订阅源 ID（按需拉取网站解析用）。来自搜索/收藏等非订阅入口时为 null，
  /// 此时顶栏隐藏「拉取网站解析」按钮。
  final String? feedId;

  /// 上下篇导航上下文：来源列表页的全部条目与当前条目下标。
  /// 列表长度 ≤ 1 时不显示底部「上一篇 / 下一篇」导航条。
  final List<RssItem> contextItems;
  final int contextIndex;

  const BrowseArticleDetailScreen({
    super.key,
    required this.item,
    this.feedId,
    this.contextItems = const <RssItem>[],
    this.contextIndex = -1,
  });

  @override
  State<BrowseArticleDetailScreen> createState() =>
      _BrowseArticleDetailScreenState();
}

class _BrowseArticleDetailScreenState extends State<BrowseArticleDetailScreen> {
  late RssItem _item;
  bool _fetching = false;
  late int _navIndex;
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _navIndex = widget.contextIndex;
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// 当前文章的缓存键 feedId（无订阅入口时用 adhoc，仅影响离线缓存归档）。
  String get _effectiveFeedId =>
      (widget.feedId == null || widget.feedId!.isEmpty)
          ? 'adhoc'
          : widget.feedId!;

  /// 上下篇切换：标记已读 → 取缓存正文 → 替换正文并滚回顶部。
  Future<void> _navigateTo(RssItem item) async {
    final String feedId = _effectiveFeedId;
    unawaited(RssArticleStore.instance.markRead(feedId, item));
    final String? content =
        RssArticleStore.instance.getContent(feedId, item) ?? item.content;
    if (!mounted) return;
    setState(() {
      _item = item.copyWith(content: content ?? item.content);
      _navIndex = widget.contextItems.indexOf(item);
    });
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.jumpTo(0);
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '-';
    return GeneralSettingsStore.instance.settings.dateFormat.format(
      dt,
      withTime: true,
    );
  }

  Future<void> _openInBrowser(
      BuildContext context, AppLocalizations l10n) async {
    try {
      await launchUrl(Uri.parse(_item.url),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.loadFailed)),
        );
      }
    }
  }

  /// 按文章页地址把相对/协议相对地址绝对化（封面与画廊 rel 解析共用）。
  String _abs(String raw) {
    final Uri? base = Uri.tryParse(_item.url);
    if (base == null) return raw;
    return base.resolve(raw).toString();
  }

  /// 从 <img> 标签属性里挑出真图地址：优先懒加载属性（data-src /
  /// data-original / data-lazy-src），回退 src；跳过 data: 内联占位图。
  String? _pickImgUrl(Map<String, String> attrs) {
    for (final k in const [
      'data-src',
      'data-original',
      'data-lazy-src',
      'src',
    ]) {
      final v = attrs[k];
      if (v != null && v.isNotEmpty && !v.startsWith('data:')) return v;
    }
    return null;
  }

  /// 文章内链接点击：仅放行 http/https 外链，拦截 javascript:/data:/tel:/file:
  /// 等危险或不适配的 scheme。
  ///
  /// 此前两类写法会「点了没反应」（旧逻辑只看绝对地址，解析不出 scheme 就静默
  /// return，用户以为应用坏了）：
  /// - 协议相对地址 `//host/path` → 继承文章页协议补全；
  /// - 文档相对地址 `/path`、`./path` → 按文章页地址解析成绝对地址。
  /// 被拦截与打不开都给提示，不再静默吞掉。
  Future<void> _openLinkSafely(BuildContext context, String? url) async {
    if (url == null || url.isEmpty) return;
    final Uri? resolved = _resolveUrl(url);
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (resolved == null) {
      _toast(context, l10n.loadFailed);
      return;
    }
    final String scheme = resolved.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      _toast(context, l10n.rssLinkUnsupported);
      return;
    }
    try {
      await launchUrl(resolved, mode: LaunchMode.externalApplication);
    } on Object {
      _toast(context, l10n.loadFailed);
    }
  }

  /// 把 HTML 里的链接解析为绝对地址（协议相对与文档相对都覆盖）。
  Uri? _resolveUrl(String raw) {
    final String s = raw.trim();
    if (s.isEmpty) return null;
    final Uri? base = Uri.tryParse(_item.url);
    // 协议相对：//host/path → 继承文章页协议（缺省 https）。
    if (s.startsWith('//')) {
      return Uri.tryParse('${base?.scheme ?? 'https'}:$s');
    }
    final Uri? parsed = Uri.tryParse(s);
    if (parsed != null && parsed.hasScheme) return parsed;
    // 文档相对：必须参照文章页地址才解析得出绝对地址。
    if (base == null) return null;
    return base.resolve(s);
  }

  void _toast(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _showReadingSettingsSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        return Consumer<ArticleReadingPreferencesNotifier>(
          builder: (BuildContext ctx,
              ArticleReadingPreferencesNotifier notifier, _) {
            final prefs = notifier.prefs;
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppTokens.spaceLg,
                    AppTokens.spaceSm,
                    AppTokens.spaceLg,
                    AppTokens.spaceLg + MediaQuery.paddingOf(ctx).bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l10n.articleReadingSettings,
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      // —— 排版 ——
                      _ArticleSectionHeader(title: l10n.articleSecTypography),
                      Text(l10n.articleFontSize),
                      Row(
                        children: <Widget>[
                          const Text('A'),
                          Expanded(
                            child: Slider(
                              min: 12,
                              max: 24,
                              divisions: 12,
                              value: prefs.fontSize,
                              label: prefs.fontSize.toStringAsFixed(0),
                              onChangeStart: (_) => AppHaptics.light(),
                              onChanged: notifier.setFontSize,
                            ),
                          ),
                          const Text('A', style: TextStyle(fontSize: 22)),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      Text(l10n.articleLineHeight),
                      Slider(
                        min: 1.0,
                        max: 2.5,
                        divisions: 15,
                        value: prefs.lineHeight,
                        label: prefs.lineHeight.toStringAsFixed(1),
                        onChangeStart: (_) => AppHaptics.light(),
                        onChanged: notifier.setLineHeight,
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      // 夜间模式已同步应用主题，不再提供独立开关。
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.articleJustify),
                        value: prefs.justify,
                        onChanged: (_) {
                          _ == true
                              ? AppHaptics.toggleOn()
                              : AppHaptics.toggleOff();
                          notifier.setJustify(!prefs.justify);
                        },
                      ),
                      Text(l10n.articleParagraphSpacing),
                      Slider(
                        min: 0,
                        max: 24,
                        divisions: 12,
                        value: prefs.paragraphSpacing,
                        label: prefs.paragraphSpacing.toStringAsFixed(0),
                        onChangeStart: (_) => AppHaptics.light(),
                        onChanged: notifier.setParagraphSpacing,
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      Text(l10n.articleContentWidth),
                      SegmentedButton<int>(
                        segments: <ButtonSegment<int>>[
                          ButtonSegment(
                            value: 0,
                            label: Text(l10n.articleWidthNarrow),
                          ),
                          ButtonSegment(
                            value: 1,
                            label: Text(l10n.articleWidthNormal),
                          ),
                          ButtonSegment(
                            value: 2,
                            label: Text(l10n.articleWidthWide),
                          ),
                        ],
                        selected: <int>{prefs.contentWidthMode},
                        onSelectionChanged: (Set<int> s) =>
                            notifier.setContentWidthMode(s.first),
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      Text(l10n.articleFontFamily),
                      const SizedBox(height: AppTokens.spaceXs),
                      SegmentedButton<int>(
                        segments: <ButtonSegment<int>>[
                          ButtonSegment(
                            value: 0,
                            label: Text(l10n.fontSystem),
                          ),
                          ButtonSegment(
                            value: 1,
                            label: Text(l10n.fontSerif),
                          ),
                          ButtonSegment(
                            value: 2,
                            label: Text(l10n.fontMono),
                          ),
                        ],
                        selected: <int>{prefs.fontFamilyMode},
                        onSelectionChanged: (Set<int> s) {
                          AppHaptics.selectionClick();
                          notifier.setFontFamilyMode(s.first);
                        },
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      Text(l10n.articleLetterSpacing),
                      Slider(
                        min: -1,
                        max: 3,
                        divisions: 8,
                        value: prefs.letterSpacing,
                        label: prefs.letterSpacing.toStringAsFixed(1),
                        onChangeStart: (_) => AppHaptics.light(),
                        onChanged: notifier.setLetterSpacing,
                      ),
                      const Divider(),
                      // —— 文字样式 ——
                      _ArticleSectionHeader(title: l10n.articleSecTextStyle),
                      Text(l10n.articleMargin),
                      Slider(
                        min: 0,
                        max: 48,
                        divisions: 12,
                        value: prefs.margin,
                        label: prefs.margin.toStringAsFixed(0),
                        onChangeStart: (_) => AppHaptics.light(),
                        onChanged: notifier.setMargin,
                      ),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceXs,
                        runSpacing: 4,
                        children: <Widget>[
                          FilterChip(
                            label: Text(l10n.fontBold),
                            selected: prefs.fontBold,
                            onSelected: notifier.setFontBold,
                          ),
                          FilterChip(
                            label: Text(l10n.fontItalic),
                            selected: prefs.fontItalic,
                            onSelected: notifier.setFontItalic,
                          ),
                          FilterChip(
                            label: Text(l10n.articleFontUnderline),
                            selected: prefs.fontUnderline,
                            onSelected: notifier.setFontUnderline,
                          ),
                          if (prefs.fontUnderline)
                            FilterChip(
                              label: Text(l10n.articleUnderlineDashed),
                              selected: prefs.underlineDashed,
                              onSelected: notifier.setUnderlineDashed,
                            ),
                        ],
                      ),
                      if (prefs.fontUnderline) ...<Widget>[
                        const SizedBox(height: AppTokens.spaceSm),
                        Text(l10n.articleUnderlineThickness),
                        Slider(
                          min: 0.5,
                          max: 4,
                          divisions: 7,
                          value: prefs.underlineThickness,
                          label: prefs.underlineThickness.toStringAsFixed(1),
                          onChangeStart: (_) => AppHaptics.light(),
                          onChanged: notifier.setUnderlineThickness,
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: _ArticleColorSwatch(
                            color: prefs.underlineColor,
                          ),
                          title: Text(l10n.articleUnderlineColor),
                          trailing: const Icon(Icons.palette_rounded),
                          onTap: () async {
                            final int? v = await _pickArticleColor(ctx,
                                title: l10n.articleUnderlineColor);
                            if (v == null || !ctx.mounted) return;
                            if (v == -1) {
                              notifier.setUnderlineColor(null);
                            } else {
                              notifier.setUnderlineColor(v);
                            }
                          },
                        ),
                      ],
                      const Divider(),
                      // —— 颜色与背景 ——
                      _ArticleSectionHeader(title: l10n.articleSecColor),
                      Text(l10n.articleBackground),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          for (int i = 0;
                              i < ReaderTokens.bgPresets.length;
                              i++)
                            InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () {
                                AppHaptics.selectionClick();
                                notifier.setBgPresetIndex(i);
                              },
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: ReaderTokens.bgPresets[i],
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: prefs.bgPresetIndex == i
                                        ? Theme.of(ctx).colorScheme.primary
                                        : Colors.grey.shade400,
                                    width: prefs.bgPresetIndex == i ? 3 : 1,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceXs),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading:
                            _ArticleColorSwatch(color: prefs.customBgColor),
                        title: Text(l10n.articleTextColor),
                        subtitle: Text(l10n.articleBackground),
                        trailing: const Icon(Icons.palette_rounded),
                        onTap: () async {
                          final int? v = await _pickArticleColor(ctx,
                              title: l10n.articleBackground);
                          if (v == null || !ctx.mounted) return;
                          if (v == -1) {
                            notifier.setCustomBgColor(null);
                          } else {
                            notifier.setCustomBgColor(v);
                          }
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading:
                            _ArticleColorSwatch(color: prefs.customTextColor),
                        title: Text(l10n.articleTextColor),
                        trailing: const Icon(Icons.palette_rounded),
                        onTap: () async {
                          final int? v = await _pickArticleColor(ctx,
                              title: l10n.articleTextColor);
                          if (v == null || !ctx.mounted) return;
                          if (v == -1) {
                            notifier.setCustomTextColor(null);
                          } else {
                            notifier.setCustomTextColor(v);
                          }
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading:
                            _ArticleColorSwatch(color: prefs.emphasisColor),
                        title: Text(l10n.articleEmphasisColor),
                        trailing: const Icon(Icons.palette_rounded),
                        onTap: () async {
                          final int? v = await _pickArticleColor(ctx,
                              title: l10n.articleEmphasisColor);
                          if (v == null || !ctx.mounted) return;
                          if (v == -1) {
                            notifier.setEmphasisColor(null);
                          } else {
                            notifier.setEmphasisColor(v);
                          }
                        },
                      ),
                      const Divider(),
                      // —— 阴影 ——
                      _ArticleSectionHeader(title: l10n.articleSecShadow),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.articleShadow),
                        value: prefs.shadow,
                        onChanged: (bool v) {
                          v == true
                              ? AppHaptics.toggleOn()
                              : AppHaptics.toggleOff();
                          notifier.setShadow(v);
                        },
                      ),
                      if (prefs.shadow) ...<Widget>[
                        Text(l10n.articleShadowBlur),
                        Slider(
                          min: 0,
                          max: 12,
                          divisions: 12,
                          value: prefs.shadowBlur,
                          label: prefs.shadowBlur.toStringAsFixed(1),
                          onChangeStart: (_) => AppHaptics.light(),
                          onChanged: notifier.setShadowBlur,
                        ),
                        Text(l10n.articleShadowOffsetX),
                        Slider(
                          min: -6,
                          max: 6,
                          divisions: 12,
                          value: prefs.shadowOffsetX,
                          label: prefs.shadowOffsetX.toStringAsFixed(0),
                          onChangeStart: (_) => AppHaptics.light(),
                          onChanged: notifier.setShadowOffsetX,
                        ),
                        Text(l10n.articleShadowOffsetY),
                        Slider(
                          min: -6,
                          max: 6,
                          divisions: 12,
                          value: prefs.shadowOffsetY,
                          label: prefs.shadowOffsetY.toStringAsFixed(0),
                          onChangeStart: (_) => AppHaptics.light(),
                          onChanged: notifier.setShadowOffsetY,
                        ),
                      ],
                      const Divider(),
                      // —— 字体 ——
                      _ArticleSectionHeader(title: l10n.articleSecFont),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.font_download_rounded),
                        title: Text(l10n.articleChooseFont),
                        subtitle: prefs.customFontPath != null
                            ? Text(
                                prefs.customFontPath!
                                    .split(RegExp(r'[/\\]'))
                                    .last,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                        trailing: prefs.customFontPath != null
                            ? IconButton(
                                icon: const Icon(Icons.delete_rounded),
                                tooltip: l10n.articleClearFont,
                                onPressed: () =>
                                    notifier.setCustomFontPath(null),
                              )
                            : null,
                        onTap: () async {
                          String? path;
                          try {
                            final FilePickerResult? result =
                                await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: <String>['ttf', 'otf'],
                            );
                            path = result?.files.single.path;
                          } on Object {
                            path = null;
                          }
                          if (path == null || !ctx.mounted) return;
                          await _loadCustomFont(path);
                          notifier.setCustomFontPath(path);
                        },
                      ),
                      const Divider(),
                      // —— 标题样式 ——
                      _ArticleSectionHeader(title: l10n.articleSecTitle),
                      Text(l10n.articleTitleScale),
                      Slider(
                        min: 0.8,
                        max: 1.6,
                        divisions: 8,
                        value: prefs.titleFontScale,
                        label: prefs.titleFontScale.toStringAsFixed(2),
                        onChangeStart: (_) => AppHaptics.light(),
                        onChanged: notifier.setTitleFontScale,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.articleTitleBold),
                        value: prefs.titleBold,
                        onChanged: (bool v) {
                          v == true
                              ? AppHaptics.toggleOn()
                              : AppHaptics.toggleOff();
                          notifier.setTitleBold(v);
                        },
                      ),
                      const SizedBox(height: AppTokens.spaceXs),
                      Text(l10n.articleTitleAlign),
                      SegmentedButton<int>(
                        segments: <ButtonSegment<int>>[
                          ButtonSegment(
                            value: 0,
                            label: Text(l10n.alignLeft),
                          ),
                          ButtonSegment(
                            value: 1,
                            label: Text(l10n.alignCenter),
                          ),
                          ButtonSegment(
                            value: 2,
                            label: Text(l10n.alignRight),
                          ),
                        ],
                        selected: <int>{prefs.titleAlign},
                        onSelectionChanged: (Set<int> s) =>
                            notifier.setTitleAlign(s.first),
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _ArticleColorSwatch(color: prefs.titleColor),
                        title: Text(l10n.articleTitleColor),
                        trailing: const Icon(Icons.palette_rounded),
                        onTap: () async {
                          final int? v = await _pickArticleColor(ctx,
                              title: l10n.articleTitleColor);
                          if (v == null || !ctx.mounted) return;
                          if (v == -1) {
                            notifier.setTitleColor(null);
                          } else {
                            notifier.setTitleColor(v);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 按需拉取网站解析：抓取文章原站全文（启发式正文识别）并刷新正文。
  /// 成功/失败都有明确反馈（此前失败被静默吞掉，抓完还弹「正在抓取」）。
  Future<void> _fetchFull(BuildContext context, AppLocalizations l10n) async {
    if (_fetching) return;
    // 搜索/收藏等未带 feedId 的入口用伪 id 作缓存键（仅影响离线缓存归档，
    // 不影响本次展示），保证按钮在所有入口都可用。
    final String feedId = (widget.feedId == null || widget.feedId!.isEmpty)
        ? 'adhoc'
        : widget.feedId!;
    setState(() => _fetching = true);
    bool ok = false;
    try {
      ok = await RssArticleStore.instance.fetchFullText(feedId, _item);
      if (ok) {
        final String? content =
            RssArticleStore.instance.getContent(feedId, _item);
        if (content != null && mounted) {
          setState(() => _item = _item.copyWith(content: content));
        }
      }
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
    if (!mounted || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(ok ? l10n.rssFetchSucceeded : l10n.loadFailed)),
      );
  }

  /// 底部「上一篇 / 下一篇」导航条：仅当来源列表多于一条时显示。
  /// 切换不重建页面（保留阅读偏好与滚动状态语义），标记已读 + 滚回顶部。
  Widget? _buildArticleNavBar(BuildContext context, AppLocalizations l10n) {
    final items = widget.contextItems;
    if (items.length <= 1 || _navIndex < 0) return null;
    final scheme = Theme.of(context).colorScheme;
    final bool hasPrev = _navIndex > 0;
    final bool hasNext = _navIndex < items.length - 1;
    if (!hasPrev && !hasNext) return null;
    return BottomAppBar(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceSm,
        vertical: AppTokens.spaceXs,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: OutlinedButton.icon(
              onPressed:
                  hasPrev ? () => _navigateTo(items[_navIndex - 1]) : null,
              icon: const Icon(Icons.skip_previous_rounded, size: 18),
              label: Text(l10n.rssPrevArticle,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceSm),
            child: Text(
              '${_navIndex + 1}/${items.length}',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: OutlinedButton.icon(
              onPressed:
                  hasNext ? () => _navigateTo(items[_navIndex + 1]) : null,
              icon: const Icon(Icons.skip_next_rounded, size: 18),
              label: Text(l10n.rssNextArticle,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
      ),
    );
  }

  /// 文章附件区：音频（播客）走播放器，其余（视频/文件）以「打开附件」链接。
  Widget _buildEnclosureWidgets(BuildContext context, AppLocalizations l10n) {
    // 统一走 [RssEnclosure.isAudio]/[isVideo] 判定（含 MIME 缺失时按后缀归属），
    // 不再按 type 是否为 null 自造一套——否则 MIME 缺失的视频附件会被当音频。
    final audio = _item.enclosures.where((e) => e.isAudio).toList();
    final video = _item.enclosures.where((e) => e.isVideo).toList();
    final others =
        _item.enclosures.where((e) => !e.isAudio && !e.isVideo).toList();

    final children = <Widget>[];
    if (audio.isNotEmpty) {
      children.add(RssPodcastPlayer(enclosures: audio, pageUrl: _item.url));
    }
    if (video.isNotEmpty) {
      children.add(
        Card(
          margin: const EdgeInsets.only(top: AppTokens.spaceMd),
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.spaceMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.play_circle_rounded),
                    const SizedBox(width: AppTokens.spaceSm),
                    Text(l10n.rssAttachments,
                        style: Theme.of(context).textTheme.titleSmall),
                  ],
                ),
                const SizedBox(height: AppTokens.spaceSm),
                for (final enc in video)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.play_arrow_rounded),
                    title: Text(enc.title ?? enc.url),
                    subtitle: enc.type != null ? Text(enc.type!) : null,
                    onTap: () => _openVideo(context, enc.url),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    if (others.isNotEmpty) {
      children.add(
        Card(
          margin: const EdgeInsets.only(top: AppTokens.spaceMd),
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.spaceMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.attachment_rounded),
                    const SizedBox(width: AppTokens.spaceSm),
                    Text(l10n.rssAttachments,
                        style: Theme.of(context).textTheme.titleSmall),
                  ],
                ),
                const SizedBox(height: AppTokens.spaceSm),
                for (final enc in others)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.open_in_new_rounded),
                    title: Text(enc.title ?? enc.url),
                    subtitle: enc.type != null ? Text(enc.type!) : null,
                    onTap: () => _openAttachment(context, enc.url),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(children: children);
  }

  Future<void> _openAttachment(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final AppLocalizations? l10n = AppLocalizations.of(context);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted && l10n != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.loadFailed)),
        );
      }
    }
  }

  /// 打开全屏图片画廊（图片查看器）。
  void _openGallery(BuildContext context, List<String> images, int index) {
    if (images.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RssImageGallery(
          images: images,
          initialIndex: index,
          pageUrl: _item.url,
        ),
      ),
    );
  }

  /// 打开视频：直链媒体走 media_kit 原生播放器；嵌入页（B站/YouTube
  /// 等 iframe 地址）走应用内置浏览器——内嵌 InAppWebView 在 Windows 桌面
  /// 极易白屏，且内置浏览器带外部回退、与应用浏览链路一致。
  void _openVideo(BuildContext context, String url) {
    if (isDirectMediaUrl(url)) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RssVideoPlayer(
            url: url,
            title: _item.title,
            pageUrl: _item.url,
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HttpBrowserScreen(initialUrl: url),
        ),
      );
    }
  }

  /// 已加载过的自定义字族（幂等，避免重复 load 报错）。
  static final Set<String> _loadedFonts = <String>{};

  /// 从字体文件路径加载并注册字族（.ttf/.otf），渲染时经
  /// [ArticleReadingPreferences.customLoadedFontFamily] 间接引用。
  Future<void> _loadCustomFont(String path) async {
    if (_loadedFonts.contains(path)) return;
    try {
      final File file = File(path);
      if (!await file.exists()) return;
      final Uint8List bytes = await file.readAsBytes();
      final FontLoader loader =
          FontLoader(ArticleReadingPreferences.customLoadedFontFamily);
      loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      await loader.load();
      _loadedFonts.add(path);
    } on Object {
      // 加载失败不阻塞阅读，字族回退系统默认。
    }
  }

  /// 标题 h1-h6 样式：相对正文的倍数 × [ArticleReadingPreferences.titleFontScale]，
  /// 加粗 / 颜色 / 对齐可配（对齐小说阅读器标题排版）。
  Map<String, Style> _buildTitleStyles(
    ArticleReadingPreferences prefs,
    Color titleColor,
  ) {
    const List<double> scales = <double>[2.0, 1.5, 1.17, 1.0, 0.83, 0.67];
    final TextAlign? align = prefs.titleAlign == 1
        ? TextAlign.center
        : (prefs.titleAlign == 2 ? TextAlign.right : null);
    final Map<String, Style> out = <String, Style>{};
    for (var i = 0; i < scales.length; i++) {
      out['h${i + 1}'] = Style(
        fontSize: FontSize(prefs.fontSize * prefs.titleFontScale * scales[i]),
        fontWeight: prefs.titleBold ? FontWeight.bold : null,
        color: titleColor,
        textAlign: align,
      );
    }
    return out;
  }

  /// 颜色选择对话框：返回 `-1`=跟随默认、`>=0`=选中的 ARGB、`null`=取消。
  Future<int?> _pickArticleColor(
    BuildContext ctx, {
    required String title,
  }) async {
    final AppLocalizations l10n = AppLocalizations.of(ctx);
    const List<int> palette = <int>[
      0xFF000000,
      0xFFFFFFFF,
      0xFF9E9E9E,
      0xFF616161,
      0xFFF44336,
      0xFFE91E63,
      0xFF9C27B0,
      0xFF673AB7,
      0xFF3F51B5,
      0xFF2196F3,
      0xFF03A9F4,
      0xFF00BCD4,
      0xFF009688,
      0xFF4CAF50,
      0xFF8BC34A,
      0xFFFFEB3B,
      0xFFFFC107,
      0xFFFF9800,
      0xFFFF5722,
      0xFF795548,
    ];
    return showDialog<int>(
      context: ctx,
      builder: (BuildContext dctx) => AppAlertDialog(
        title: Text(title),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: <Widget>[
            for (final int c in palette)
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.of(dctx).pop(c),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(dctx).colorScheme.outlineVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        actions: <Widget>[
          TextButton.icon(
            onPressed: () => Navigator.of(dctx).pop(-1),
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: Text(l10n.colorFollowDefault),
          ),
        ],
      ),
    );
  }

  /// 从正文 HTML 提取所有图片地址（懒加载属性优先），按文章页地址绝对化
  /// （用于全屏画廊）。
  List<String> _extractImageUrls(String html) {
    if (html.isEmpty) return const <String>[];
    final Uri? base = Uri.tryParse(_item.url);
    final tags = RegExp(r'<img\b[^>]*>', caseSensitive: false).allMatches(html);
    final List<String> urls = <String>[];
    for (final t in tags) {
      final tag = t.group(0)!;
      String? best;
      for (final attr in const [
        'data-src',
        'data-original',
        'data-lazy-src',
        'src',
      ]) {
        final m = RegExp('$attr=["\']([^"\']+)["\']', caseSensitive: false)
            .firstMatch(tag);
        final v = m?.group(1);
        if (v != null && v.isNotEmpty && !v.startsWith('data:')) {
          best = v;
          break;
        }
      }
      if (best == null) continue;
      final abs = base != null ? base.resolve(best).toString() : best;
      // 视频地址不当图片：部分站点用 `<img src="xxx.mp4">` 承载视频帧，
      // 若放进图片画廊，点击只会打开图片查看器（视频被当图片、无法播放）。
      // 这类地址交给 [RssVideoPlayer] / 内置浏览器，而不是画廊。
      if (isDirectMediaUrl(abs)) continue;
      if (!urls.contains(abs)) urls.add(abs);
    }
    return urls;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String html = _item.content ?? _item.description ?? '';
    final List<String> imgUrls = _extractImageUrls(html);

    return Consumer<ArticleReadingPreferencesNotifier>(
      builder: (BuildContext context,
          ArticleReadingPreferencesNotifier notifier, _) {
        final prefs = notifier.prefs;
        // 夜间模式同步应用的夜间模式：跟随应用主题（ThemeController），
        // 不再使用 RSS 独立的 isNightMode 开关。
        final bool isNight = Theme.of(context).brightness == Brightness.dark;
        // 背景：自定义背景色优先，否则背景预设；夜间向黑压暗（对齐小说）。
        final Color bgBase = prefs.customBgColor != null
            ? Color(prefs.customBgColor!)
            : ReaderTokens.bgPresets[prefs.bgPresetIndex
                .clamp(0, ReaderTokens.bgPresets.length - 1)];
        final Color bg = isNight
            ? Color.lerp(bgBase, Colors.black, ReaderTokens.nightDarkenFactor)!
            : bgBase;
        // 正文色：自定义文字色优先，否则按背景亮度自动黑/白。
        final Color textColor = prefs.customTextColor != null
            ? Color(prefs.customTextColor!)
            : (bg.computeLuminance() > 0.5 ? Colors.black87 : Colors.white);
        final Color metaColor = textColor.withValues(alpha: 0.7);
        final TextAlign? justify = prefs.justify ? TextAlign.justify : null;

        // 自定义字体文件：已选则 fire-and-forget 加载（幂等），渲染用注册字族。
        final String? fontPath = prefs.customFontPath;
        if (fontPath != null && fontPath.isNotEmpty) {
          unawaited(_loadCustomFont(fontPath));
        }

        final Color titleColor = prefs.titleColor != null
            ? Color(prefs.titleColor!)
            : (prefs.emphasisColor != null
                ? Color(prefs.emphasisColor!)
                : textColor);

        final Style baseStyle = Style(
          fontSize: FontSize(prefs.fontSize),
          lineHeight: LineHeight(prefs.lineHeight),
          color: textColor,
          textAlign: justify,
          fontFamily: prefs.fontFamily,
          letterSpacing: prefs.letterSpacing,
          fontWeight: prefs.fontBold ? FontWeight.bold : null,
          fontStyle: prefs.fontItalic ? FontStyle.italic : null,
          textDecoration: prefs.fontUnderline ? TextDecoration.underline : null,
          textDecorationColor: prefs.underlineColor != null
              ? Color(prefs.underlineColor!)
              : null,
          textDecorationStyle: prefs.underlineDashed
              ? TextDecorationStyle.dashed
              : TextDecorationStyle.solid,
          textDecorationThickness: prefs.underlineThickness,
          textShadow: prefs.shadow
              ? <Shadow>[
                  Shadow(
                    color: textColor.withValues(alpha: 0.5),
                    blurRadius: prefs.shadowBlur,
                    offset: Offset(prefs.shadowOffsetX, prefs.shadowOffsetY),
                  ),
                ]
              : null,
        );

        final Map<String, Style> htmlStyle = <String, Style>{
          'body': baseStyle.copyWith(
            margin: Margins.zero,
            padding: HtmlPaddings.only(
              inlineStart: prefs.margin,
              inlineEnd: prefs.margin,
            ),
          ),
          'p': baseStyle.copyWith(
            margin: Margins(bottom: Margin(prefs.paragraphSpacing)),
          ),
          // 标题 h1-h6：相对正文倍数 × titleFontScale，颜色/对齐/加粗可配。
          ..._buildTitleStyles(prefs, titleColor),
        };

        // 所有入口都可用：无 feedId 时以 adhoc 键抓取（不入订阅源离线缓存）。
        final bool canFetch = _item.url.isNotEmpty && !_fetching;

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            title: AutoTranslatedText(
              text: _item.title,
              kind: TranslatableTextKind.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: <Widget>[
              if (canFetch || _fetching)
                AppIconButton(
                  icon: _fetching
                      ? Icons.hourglass_top_rounded
                      : Icons.cloud_download_rounded,
                  tooltip: l10n.rssFetchWebsite,
                  onPressed: canFetch ? () => _fetchFull(context, l10n) : null,
                ),
              AppIconButton(
                icon: Icons.text_fields_rounded,
                tooltip: l10n.articleReadingSettings,
                onPressed: () => _showReadingSettingsSheet(context),
              ),
              AppIconButton(
                icon: Icons.share_rounded,
                tooltip: l10n.share,
                onPressed: () {
                  unawaited(
                    Share.share('${_item.title}\n${_item.url}'),
                  );
                },
              ),
              AppIconButton(
                icon: Icons.open_in_browser_rounded,
                tooltip: l10n.articleDetailReadFull,
                onPressed: () => _openInBrowser(context, l10n),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openInBrowser(context, l10n),
            icon: const Icon(Icons.open_in_new_rounded),
            label: Text(l10n.articleDetailReadFull),
          ),
          bottomNavigationBar: _buildArticleNavBar(context, l10n),
          body: ListView(
            controller: _scrollCtrl,
            padding: context.pageInset(AppTokens.spaceLg),
            children: <Widget>[
              if (_item.author != null || _item.publishedAt != null)
                Row(
                  children: <Widget>[
                    if (_item.author != null)
                      Expanded(
                        child: Text(
                            '${l10n.articleDetailAuthor}：${_item.author}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: metaColor)),
                      ),
                    if (_item.publishedAt != null)
                      AnimatedBuilder(
                        animation: GeneralSettingsStore.instance,
                        builder: (context, _) => Text(
                          '${l10n.articleDetailPublishedAt}：${_formatDate(_item.publishedAt)}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: metaColor),
                        ),
                      ),
                  ],
                ),
              if (_item.author != null || _item.publishedAt != null)
                const SizedBox(height: AppTokens.spaceMd),
              if (_item.coverUrl != null)
                GestureDetector(
                  onTap: () =>
                      _openGallery(context, <String>[_abs(_item.coverUrl!)], 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                    // 封面同样走 SourceImage（带文章页 Referer + 重试）：
                    // AppCoverImage 无源配置时不注入 Referer，防盗链站点拿不到封面。
                    // 相对地址先按文章页地址绝对化，否则会被当成本地文件。
                    child: SourceImage(
                      url: _abs(_item.coverUrl!),
                      fit: BoxFit.cover,
                      refererOverride: _item.url.isNotEmpty ? _item.url : null,
                    ),
                  ),
                ),
              if (_item.coverUrl != null)
                const SizedBox(height: AppTokens.spaceMd),
              if (html.isNotEmpty)
                Center(
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(maxWidth: prefs.contentMaxWidth),
                    child: Html(
                      data: html,
                      style: htmlStyle,
                      // 渲染时彻底丢弃危险/追踪标签（HTML 消毒）；
                      // iframe 不在此丢弃——改由下方 Extension 渲染为「播放视频」按钮，
                      // 否则嵌入视频（YouTube/B 站等）会被整段跳过无法播放。
                      doNotRenderTheseTags: const <String>{
                        'script',
                        'object',
                        'embed',
                        'form',
                      },
                      // 自定义标签渲染：正文图片改走 [SourceImage]，默认的
                      // `Image.network` 不带 Referer / UA，防盗链站点一律 403。
                      extensions: <HtmlExtension>[
                        TagExtension(
                          tagsToExtend: <String>{'img'},
                          builder: (ExtensionContext ext) => _HtmlImage(
                            src: _pickImgUrl(ext.attributes),
                            pageUrl: _item.url,
                            images: imgUrls,
                          ),
                        ),
                        // <video> 标签：flutter_html 3.0 对 video 渲染支持有限，
                        // 直接改为「播放视频」按钮（取 src 或首个 <source src>），
                        // 点击走视频播放器 / 内置浏览器，避免被当作图片/空白跳过。
                        TagExtension(
                          tagsToExtend: <String>{'video'},
                          builder: (ExtensionContext ext) {
                            String src = ext.attributes['src'] ?? '';
                            if (src.isEmpty) {
                              for (final child in ext.elementChildren) {
                                if (child.localName == 'source') {
                                  final s = child.attributes['src'];
                                  if (s != null && s.isNotEmpty) {
                                    src = s;
                                    break;
                                  }
                                }
                              }
                            }
                            if (src.isEmpty) return const SizedBox.shrink();
                            final Uri? base = Uri.tryParse(_item.url);
                            final String url = base != null
                                ? base.resolve(src).toString()
                                : src;
                            // 直链媒体直接内嵌播放（16:9，带控制条/全屏）；
                            // 非直链（页面型地址）退回「播放视频」按钮走浏览器。
                            if (isDirectMediaUrl(url)) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: AppTokens.spaceSm),
                                child: RssInlineVideoPlayer(
                                  url: url,
                                  title: _item.title,
                                  pageUrl: _item.url,
                                ),
                              );
                            }
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: AppTokens.spaceSm),
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.play_circle_rounded),
                                label: Text(l10n.rssVideoPlay),
                                onPressed: () => _openVideo(context, url),
                              ),
                            );
                          },
                        ),
                        // iframe 嵌入视频：不渲染原始 iframe（XSS/追踪风险），改为
                        // 「播放视频」按钮，点击用应用内 WebView 播放。
                        TagExtension(
                          tagsToExtend: <String>{'iframe'},
                          builder: (ExtensionContext ext) {
                            final src = ext.attributes['src'] ?? '';
                            if (src.isEmpty) return const SizedBox.shrink();
                            final Uri? base = Uri.tryParse(_item.url);
                            final String url = base != null
                                ? base.resolve(src).toString()
                                : src;
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: AppTokens.spaceSm),
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.play_circle_rounded),
                                label: Text(l10n.rssVideoPlay),
                                onPressed: () => _openVideo(context, url),
                              ),
                            );
                          },
                        ),
                      ],
                      onLinkTap:
                          (String? url, Map<String, String> attributes, _) {
                        _openLinkSafely(context, url);
                      },
                    ),
                  ),
                )
              else
                AppEmptyState(
                    icon: Icons.article_rounded,
                    message: l10n.articleDetailEmpty),
              _buildEnclosureWidgets(context, l10n),
            ],
          ),
        );
      },
    );
  }
}

/// 正文内嵌图片。
///
/// 走 [SourceImage] 而非 flutter_html 默认的 `Image.network`：后者既不发
/// Referer 也不发 UA，防盗链站点一律返回 403，用户只看到加载不出来。
/// [SourceImage] 会带上**文章页** Referer（防盗链校验的是「被哪个页面引用」，
/// 用图片自身域名当 Referer 反而无效），并在失败时按指数退避重试三次。
///
/// 另外把相对图片地址按文章页地址解析为绝对地址——feed 正文里
/// `src="/img/a.png"` 这类相对写法相当常见，不解析必然加载不出来。
class _HtmlImage extends StatelessWidget {
  final String? src;
  final String pageUrl;
  final List<String> images;

  const _HtmlImage({
    required this.src,
    required this.pageUrl,
    required this.images,
  });

  @override
  Widget build(BuildContext context) {
    if (src == null || src!.isEmpty) return const SizedBox.shrink();
    final Uri? base = Uri.tryParse(pageUrl);
    final String url = base != null ? base.resolve(src!).toString() : src!;
    // 部分站点用 `<img src="xxx.mp4">` 承载视频帧：直链视频直接内嵌播放，
    // 不再当图片渲染（点击只会打开图片查看器）也不再跳按钮页。
    if (isDirectMediaUrl(url)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
        child: RssInlineVideoPlayer(
          url: url,
          pageUrl: pageUrl,
        ),
      );
    }
    final int index = images.indexOf(url);
    return GestureDetector(
      // 长按：保存 / 复制 / 分享（对齐漫画阅读器图片功能）。
      // MD3「Thunk」：长按呼出正文图片操作菜单。
      onLongPress: () {
        AppHaptics.thunk();
        unawaited(showRssImageActions(context, url: url, pageUrl: pageUrl));
      },
      onTap: () {
        if (images.isEmpty) return;
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => RssImageGallery(
              images: images,
              initialIndex: index < 0 ? 0 : index,
              pageUrl: pageUrl,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          child: SourceImage(
            url: url,
            fit: BoxFit.fitWidth,
            refererOverride: pageUrl.isNotEmpty ? pageUrl : null,
          ),
        ),
      ),
    );
  }
}

/// 阅读设置面板里颜色选择项的左侧色块：`null`（跟随默认）显示自动图标占位。
class _ArticleColorSwatch extends StatelessWidget {
  final int? color;

  const _ArticleColorSwatch({this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color != null ? Color(color!) : null,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: color == null
          ? const Icon(Icons.brightness_auto_rounded,
              size: 16, color: Colors.grey)
          : null,
    );
  }
}

/// 阅读设置面板的分节标题。
class _ArticleSectionHeader extends StatelessWidget {
  final String title;

  const _ArticleSectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.spaceMd),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
