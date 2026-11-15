/// 独立导入预览页 —— 本地导入 / 网络多源导入共用的批量勾选确认页。
///
/// 「源管理」解析出候选源后推入本页：整页只保留一条顶栏 + 文件列表 +
/// 底部确认栏，不再与源管理页的多层导航叠放；确认后 [Navigator.pop]
/// 回传选中的有效源列表，由调用方完成入库与提示。
library;

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../../../core/models/plugin_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/app_glass_bar.dart';

/// 导入预览项 —— 扫描到的单个候选源信息。
class ImportPreviewItem {
  final String path;
  final String fileName;
  final PluginConfig? config;
  final SourceType? type;
  final bool isValid;
  final String? error;

  ImportPreviewItem({
    required this.path,
    required this.fileName,
    required this.config,
    this.type,
    required this.isValid,
    this.error,
  });
}

/// [SourceType] → 本地化分类标签（源管理页与导入预览页共用）。
String importTypeLabel(SourceType type, AppLocalizations l10n) {
  switch (type) {
    case SourceType.novelSource:
      return l10n.sourceCategoryNovel;
    case SourceType.animeSource:
      return l10n.sourceCategoryMedia;
    case SourceType.videoSource:
      return l10n.sourceTypeVideo;
    case SourceType.audioSource:
      return l10n.sourceTypeAudio;
    case SourceType.mangaSource:
      return l10n.sourceCategoryComic;
  }
}

/// 批量勾选导入预览页。确认时 pop 回传选中的有效项列表。
class SourceImportPreviewScreen extends StatefulWidget {
  /// 候选源列表（含解析失败项，失败项仅作展示）。
  final List<ImportPreviewItem> items;

  /// 专属类型过滤（null = 显示全部类型）。
  final SourceType? filterType;

  /// 类型筛选时被跳过的其他类型源数量（用于提示横幅）。
  final int skippedByTypeCount;

  /// 因年龄限制被拦截（未进入本页）的 18+ 源数量。
  final int ageBlockedCount;

  const SourceImportPreviewScreen({
    super.key,
    required this.items,
    this.filterType,
    this.skippedByTypeCount = 0,
    this.ageBlockedCount = 0,
  });

  @override
  State<SourceImportPreviewScreen> createState() =>
      _SourceImportPreviewScreenState();
}

class _SourceImportPreviewScreenState extends State<SourceImportPreviewScreen> {
  /// 初始默认全选所有有效项。
  late Set<int> _selected = widget.items
      .asMap()
      .entries
      .where((e) => e.value.isValid)
      .map((e) => e.key)
      .toSet();

  int get _validCount => widget.items.where((e) => e.isValid).length;

  void _toggle(int index, bool? value) {
    value == true ? AppHaptics.toggleOn() : AppHaptics.toggleOff();
    setState(() {
      if (value == true) {
        _selected.add(index);
      } else {
        _selected.remove(index);
      }
    });
  }

  /// 确认导入：回传选中的有效项。
  void _confirm() {
    final selected = widget.items
        .asMap()
        .entries
        .where((e) => _selected.contains(e.key) && e.value.isValid)
        .map((e) => e.value)
        .toList();
    Navigator.of(context).pop(selected);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.importPreviewTitle(widget.items.length)),
        actions: <Widget>[
          if (_validCount > 0) ...<Widget>[
            TextButton(
              onPressed: () => setState(() {
                _selected = widget.items
                    .asMap()
                    .entries
                    .where((e) => e.value.isValid)
                    .map((e) => e.key)
                    .toSet();
              }),
              child: Text(l10n.selectAll),
            ),
            TextButton(
              onPressed: () => setState(() => _selected = <int>{}),
              child: Text(l10n.deselectAll),
            ),
          ],
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (widget.ageBlockedCount > 0)
            _buildBanner(
              scheme: scheme,
              color: scheme.errorContainer.withValues(alpha: 0.5),
              iconColor: scheme.onErrorContainer,
              textColor: scheme.onErrorContainer,
              icon: Icons.lock_rounded,
              text: l10n.ageBlockedImportHint(widget.ageBlockedCount),
              withTopPadding: true,
            ),
          // 类型筛选提示：在专属类型页导入时，仅导入该类型源
          if (widget.filterType != null)
            _buildBanner(
              scheme: scheme,
              color: AppTheme.cardContainer(scheme),
              iconColor: scheme.onSurfaceVariant,
              textColor: scheme.onSurfaceVariant,
              icon: Icons.filter_alt_rounded,
              text: widget.skippedByTypeCount > 0
                  ? l10n.importTypeFiltered(widget.skippedByTypeCount)
                  : l10n.importTypeOnly(
                      importTypeLabel(widget.filterType!, l10n)),
            ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: context.pageInset(AppTokens.spaceSm),
              itemCount: widget.items.length,
              itemBuilder: (context, i) {
                final item = widget.items[i];
                final isSelected = _selected.contains(i);
                return Card(
                  margin: const EdgeInsets.only(bottom: AppTokens.spaceXs),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.spaceSm,
                      vertical: AppTokens.spaceXs,
                    ),
                    leading: Checkbox(
                      value: isSelected && item.isValid,
                      onChanged: item.isValid ? (v) => _toggle(i, v) : null,
                    ),
                    title: Text(
                      item.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (item.isValid) ...<Widget>[
                          Text(
                            item.config?.name ?? '',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.primary),
                          ),
                          if (item.type != null)
                            Text(
                              '${l10n.sourceType}：${importTypeLabel(item.type!, l10n)}',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                            ),
                        ] else ...<Widget>[
                          Text(
                            item.error ?? l10n.sourceImportInvalid,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.error),
                          ),
                        ],
                      ],
                    ),
                    trailing: Icon(
                      item.isValid
                          ? Icons.check_circle_rounded
                          : Icons.error_rounded,
                      color: item.isValid
                          ? AppStatusColors.ok(scheme)
                          : scheme.error,
                      size: 20,
                    ),
                  ),
                );
              },
            ),
          ),
          // 底部操作栏
          Container(
            padding: context.pageInset(AppTokens.spaceMd),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.3)),
              ),
            ),
            child: Row(
              children: <Widget>[
                Text(
                  l10n.importSelectedCount(_selected.length),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _selected.isNotEmpty ? _confirm : null,
                  icon: const Icon(Icons.file_download_rounded, size: 18),
                  label: Text(l10n.confirmImport),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 页首提示横幅（18+ 拦截 / 类型过滤共用布局）。
  Widget _buildBanner({
    required ColorScheme scheme,
    required Color color,
    required Color iconColor,
    required Color textColor,
    required IconData icon,
    required String text,
    bool withTopPadding = false,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppTokens.spaceMd,
        withTopPadding ? AppTokens.spaceMd : 0,
        AppTokens.spaceMd,
        0,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceMd,
          vertical: AppTokens.spaceSm,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: AppTokens.spaceXs),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: textColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
