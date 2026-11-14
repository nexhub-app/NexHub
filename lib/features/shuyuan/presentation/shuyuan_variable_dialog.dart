/// 书源变量编辑对话框（P0-4 合并版：不再有独立书源管理页，变量编辑
/// 直接挂进源管理的源瓦片「编辑」菜单，仅对 legado 书源生效）。
library;

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../../../core/models/plugin_config.dart';
import '../../../core/theme/app_tokens.dart';
import '../shuyuan_variable_store.dart';

/// 读取书源 variableComment（selectors['xiaoshuo'] 原图内）。
String? shuyuanVariableComment(PluginConfig source) {
  final xiaoshuo = source.selectors?['xiaoshuo'];
  if (xiaoshuo is! Map<String, dynamic>) return null;
  final v = xiaoshuo['variableComment'];
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty ? null : s;
}

/// 是否为 legado 书源（含变量可编辑）。
bool isShuyuanSourceConfig(PluginConfig source) =>
    source.selectors?['xiaoshuo'] is Map<String, dynamic>;

/// 弹出源变量键值编辑器并保存（空表清除该源条目）。
Future<void> showShuyuanVariableEditor(
  BuildContext context,
  PluginConfig source,
) async {
  final l10n = AppLocalizations.of(context);
  final variableComment = shuyuanVariableComment(source);
  final existing = await ShuyuanVariableStore.load(source.id);
  if (!context.mounted) return;

  final keys = <TextEditingController>[
    for (final k in existing.keys) TextEditingController(text: k)
  ];
  final values = <TextEditingController>[
    for (final k in existing.keys) TextEditingController(text: existing[k] ?? '')
  ];

  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(l10n.bookSourceVarEdit),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (variableComment != null) ...<Widget>[
                Text(variableComment, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: AppTokens.spaceSm),
              ],
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: <Widget>[
                      for (var i = 0; i < keys.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: TextFormField(
                                  controller: keys[i],
                                  decoration: InputDecoration(
                                    isDense: true,
                                    labelText: l10n.bookSourceVarKey,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppTokens.spaceSm),
                              Expanded(
                                child: TextFormField(
                                  controller: values[i],
                                  decoration: InputDecoration(
                                    isDense: true,
                                    labelText: l10n.bookSourceVarValue,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: () => setDialogState(() {
                                  keys.removeAt(i);
                                  values.removeAt(i);
                                }),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => setDialogState(() {
                  keys.add(TextEditingController());
                  values.add(TextEditingController());
                }),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(l10n.bookSourceVarAdd),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child:
                Text(MaterialLocalizations.of(dialogContext).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child:
                Text(MaterialLocalizations.of(dialogContext).saveButtonLabel),
          ),
        ],
      ),
    ),
  );

  if (saved != true) {
    for (final c in keys) {
      c.dispose();
    }
    for (final c in values) {
      c.dispose();
    }
    return;
  }
  final vars = <String, String>{};
  for (var i = 0; i < keys.length; i++) {
    final k = keys[i].text.trim();
    if (k.isEmpty) continue;
    vars[k] = values[i].text;
  }
  await ShuyuanVariableStore.save(source.id, vars);
  for (final c in keys) {
    c.dispose();
  }
  for (final c in values) {
    c.dispose();
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(AppLocalizations.of(context).bookSourceVarSaved)),
  );
}
