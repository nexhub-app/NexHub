/// OPML 导入 / 导出页。
///
/// 入口：设置 → 配置与网络 → RSS 订阅（全局）页右上角「更多」菜单。
/// 功能：
/// - 导入：① 从本机文件（.opml / .xml）选择；② 粘贴 OPML 文本。
/// 解析后弹出预览，可勾选要导入的订阅，确认后批量入库（去重、分组取并）。
/// - 导出：生成 OPML 2.0 文本，写入应用文档目录并调用系统分享（备份 / 迁移）。
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/widgets/app_alert_dialog.dart';
import '../../../core/rss/rss_manager.dart';
import '../../../core/rss/rss_opml.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/app_animations.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../features/settings/presentation/widgets/settings_widgets.dart';
import '../../../core/widgets/app_glass_bar.dart';

class RssOpmlScreen extends StatefulWidget {
  const RssOpmlScreen({super.key});

  @override
  State<RssOpmlScreen> createState() => _RssOpmlScreenState();
}

class _RssOpmlScreenState extends State<RssOpmlScreen> {
  bool _exporting = false;

  /// 从文件导入 OPML。
  Future<void> _importFromFile(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['opml', 'xml'],
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    String text;
    try {
      text = await File(path).readAsString();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.rssOpmlParseFailed(e.toString()))));
      return;
    }
    _parseAndPreview(context, text, l10n);
  }

  /// 粘贴文本导入 OPML。
  Future<void> _importFromText(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AppAlertDialog(
        title: Text(l10n.rssOpmlImportText),
        content: TextField(
          controller: ctrl,
          maxLines: 12,
          minLines: 6,
          decoration: InputDecoration(
            hintText: l10n.rssOpmlPasteHint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(ctrl.text),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    _parseAndPreview(context, text, l10n);
  }

  /// 解析并展示导入预览（勾选 → 批量入库）。
  Future<void> _parseAndPreview(
    BuildContext context,
    String text,
    AppLocalizations l10n,
  ) async {
    final manager = context.read<RssManager>();
    OpmlParseResult parsed;
    try {
      parsed = RssOpml.parse(text);
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.rssOpmlParseFailed(e.toString()))));
      return;
    }
    if (parsed.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.rssOpmlEmpty)),
      );
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTokens.radiusLg)),
      ),
      builder: (_) => _OpmlImportPreviewSheet(
        entries: parsed.entries,
        skipped: parsed.skipped,
        manager: manager,
      ),
    );
  }

  /// 导出 OPML 并经系统分享。
  Future<void> _export(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final manager = context.read<RssManager>();
    if (manager.feeds.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.rssOpmlEmpty)),
      );
      return;
    }
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final xml = RssOpml.build(manager.feeds, docTitle: 'NexHub RSS');
      final dir = await getApplicationDocumentsDirectory();
      final outDir = Directory('${dir.path}/nexhub');
      await outDir.create(recursive: true);
      final file = File(
        '${outDir.path}/nexhub_rss_${DateTime.now().millisecondsSinceEpoch}.opml',
      );
      await file.writeAsString(xml);
      if (!mounted) return;
      await Share.shareXFiles(<XFile>[XFile(file.path)]);
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.rssOpmlTitle)),
      body: ListView(
        padding: context.pageInset(AppTokens.spaceMd),
        children: <Widget>[
          Entrance(
            index: 0,
            offset: 12,
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(l10n.rssOpmlImportTitle,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: AppTokens.spaceXs),
                  Text(l10n.rssOpmlImportDesc,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: AppTokens.spaceSm),
                  AppListTile(
                    leading: const SettingsLeadingIcon(
                        icon: Icons.upload_file_rounded),
                    title: Text(l10n.rssOpmlImportFile),
                    subtitle: Text(l10n.rssOpmlImportFileDesc),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _importFromFile(context),
                  ),
                  AppListTile(
                    leading:
                        const SettingsLeadingIcon(icon: Icons.paste_rounded),
                    title: Text(l10n.rssOpmlImportText),
                    subtitle: Text(l10n.rssOpmlImportTextDesc),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _importFromText(context),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          Entrance(
            index: 1,
            offset: 12,
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(l10n.rssOpmlExportTitle,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: AppTokens.spaceXs),
                  Text(l10n.rssOpmlExportDesc,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: AppTokens.spaceSm),
                  AppListTile(
                    leading:
                        const SettingsLeadingIcon(icon: Icons.download_rounded),
                    title: Text(l10n.rssOpmlExport),
                    subtitle: Text(l10n.rssOpmlExportDesc2),
                    trailing: _exporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right_rounded),
                    onTap: _exporting ? null : () => _export(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// OPML 导入预览底部面板：勾选要导入的订阅，确认批量入库。
class _OpmlImportPreviewSheet extends StatefulWidget {
  final List<OpmlEntry> entries;
  final int skipped;
  final RssManager manager;

  const _OpmlImportPreviewSheet({
    required this.entries,
    required this.skipped,
    required this.manager,
  });

  @override
  State<_OpmlImportPreviewSheet> createState() =>
      _OpmlImportPreviewSheetState();
}

class _OpmlImportPreviewSheetState extends State<_OpmlImportPreviewSheet> {
  late final Set<String> _selected;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // 默认全选（导入通常是要整份订阅）。
    _selected = <String>{for (final e in widget.entries) e.xmlUrl};
  }

  Future<void> _confirm() async {
    final l10n = AppLocalizations.of(context);
    if (_busy) return;
    setState(() => _busy = true);
    var imported = 0;
    for (final entry in widget.entries) {
      if (!_selected.contains(entry.xmlUrl)) continue;
      await widget.manager.addFeed(
        url: entry.xmlUrl,
        title: entry.title,
        groups: entry.categories,
      );
      imported++;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.rssOpmlImported(imported))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return AppSheetBody(
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.spaceMd,
                  AppTokens.spaceSm,
                  AppTokens.spaceMd,
                  0,
                ),
                child: Text(l10n.rssOpmlImportPreviewTitle,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.spaceMd,
                  AppTokens.spaceXs,
                  AppTokens.spaceMd,
                  AppTokens.spaceSm,
                ),
                child: Text(
                  widget.skipped > 0
                      ? l10n.rssOpmlPreviewSummarySkipped(_selected.length,
                          widget.entries.length, widget.skipped)
                      : l10n.rssOpmlPreviewSummary(
                          _selected.length, widget.entries.length),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.entries.length,
                  itemBuilder: (ctx, i) {
                    final e = widget.entries[i];
                    final on = _selected.contains(e.xmlUrl);
                    return Entrance(
                      index: i < 8 ? i : 8,
                      onceKey: 'opmlprev:${e.xmlUrl}',
                      child: CheckboxListTile(
                        value: on,
                        onChanged: (v) {
                          v == true
                              ? AppHaptics.toggleOn()
                              : AppHaptics.toggleOff();
                          setState(() {
                            v == true
                                ? _selected.add(e.xmlUrl)
                                : _selected.remove(e.xmlUrl);
                          });
                        },
                        title: Text(e.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: e.categories.isNotEmpty
                            ? Text(l10n.rssOpmlCategory(e.categories.join('、')),
                                maxLines: 1, overflow: TextOverflow.ellipsis)
                            : null,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppTokens.spaceMd),
                child: FilledButton(
                  onPressed: _busy ? null : _confirm,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.rssOpmlConfirmImport),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
