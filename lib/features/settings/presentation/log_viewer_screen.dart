/// 运行日志查看页（设置 → 高级 → 运行日志）。
///
/// 展示 [AppLog] 本次运行期的滚动日志：详细日志开关开启时的网络请求/响应
/// （`[HTTP] ...`）、Flutter 错误等。1 秒轮询刷新（[AppLog] 非 ChangeNotifier）。
/// 支持复制全部 / 导出文件（发给开发者）/ 清空。与「崩溃日志」（持久化）互补。
///
/// 正文必须为**单个可选中文本块**：此前每行一个 `SelectableText`（ListView.builder），
/// 长按选择跨不过 widget 边界，一次只能复制一行。
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../../../core/widgets/app_alert_dialog.dart';
import '../../../core/widgets/app_animations.dart';
import '../../../core/debug/log_export.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/app_log.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_glass_bar.dart';

class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  List<String> _entries = const <String>[];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _reload();
    // 1s 轮询：下载/请求进行时日志持续追加。
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _reload() {
    final List<String> next = AppLog.instance.entries;
    if (!mounted) return;
    if (identical(next, _entries) || _same(next)) return;
    setState(() => _entries = next);
  }

  bool _same(List<String> a) {
    if (a.length != _entries.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != _entries[i]) return false;
    }
    return true;
  }

  Future<void> _copyAll(AppLocalizations l10n) async {
    if (_entries.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _entries.join('\n')));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.logCopied)),
      );
    }
  }

  /// 导出日志文件：打包为带环境信息头的 txt，经系统分享 / 另存为发出。
  Future<void> _export(AppLocalizations l10n) async {
    if (_entries.isEmpty) return;
    final bool ok = await LogExport.export(
      kind: 'runtime',
      content: _entries.join('\n'),
    );
    if (!ok || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.logExportDone)),
    );
  }

  Future<void> _clear(AppLocalizations l10n) async {
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AppAlertDialog(
            title: Text(l10n.crashLogClear),
            content: Text(l10n.confirmActionHint),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l10n.confirm),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    AppLog.instance.clear();
    setState(() => _entries = const <String>[]);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.runtimeLog),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.crashLogCopyAll,
            icon: const Icon(Icons.copy_all_rounded),
            onPressed: () => _copyAll(l10n),
          ),
          IconButton(
            tooltip: l10n.logExportFile,
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: _entries.isEmpty ? null : () => _export(l10n),
          ),
          IconButton(
            tooltip: l10n.crashLogClear,
            icon: const Icon(Icons.delete_sweep_rounded),
            onPressed: () => _clear(l10n),
          ),
        ],
      ),
      body: _entries.isEmpty
          ? AppEmptyState(
              icon: Icons.article_rounded,
              message: l10n.logEmpty,
            )
          : SingleChildScrollView(
              padding: context.pageInset(AppTokens.spaceMd),
              child: AppSheetBody(
                // 单个可选中文本块：长按选择 / 拖动手柄可跨行选中任意
                // 连续内容，复制不再被限制在单行内。
                child: SelectableText(
                  _entries.join('\n'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        height: 1.4,
                      ),
                ),
              ),
            ),
    );
  }
}
