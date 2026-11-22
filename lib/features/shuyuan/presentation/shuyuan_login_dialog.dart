/// legado 书源登录入口（P2-1）。
///
/// loginUrl 形态分派：
/// - URL（非脚本）→ [ShuyuanBrowserScreen]，完成时回传 Cookie 至
///   书源上下文覆盖层（per-source overlay）；
/// - `@js:`/`<js>` 脚本 → loginUi（RowUi）表单收集值写入 ctx.loginInfo →
///   执行脚本（mini-settle：脚本内 java.ajax 走确定性重放）。
///
/// loginCheckJs 校验由 WebBook 五个入口对首响应消费
/// （AnalyzeUrl.applyLoginCheck，code==500 → ShuyuanLoginRequiredException）。
library;

import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../../../core/models/plugin_config.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/navigation/app_page_route.dart';
import '../analyze/js_engine.dart';
import '../analyze/source_context.dart';
import '../shuyuan_source_service.dart';
import 'shuyuan_browser_screen.dart';
import 'shuyuan_interactive.dart';
import 'shuyuan_variable_dialog.dart' show isShuyuanSourceConfig;

/// 提取书源的 loginUrl（selectors['xiaoshuo'] 原图内）。
String? shuyuanLoginUrl(PluginConfig source) {
  if (!isShuyuanSourceConfig(source)) return null;
  final xiaoshuo = source.selectors!['xiaoshuo'] as Map<String, dynamic>;
  final v = xiaoshuo['loginUrl'];
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty ? null : s;
}

/// 提取书源的 loginUi（RowUi 数组，JSON 字符串或数组形态）。
List<Map<String, dynamic>> shuyuanLoginUi(PluginConfig source) {
  if (!isShuyuanSourceConfig(source)) return const [];
  final xiaoshuo = source.selectors!['xiaoshuo'] as Map<String, dynamic>;
  final v = xiaoshuo['loginUi'];
  if (v == null) return const [];
  try {
    final decoded = v is String
        ? (v.trim().isEmpty ? null : jsonDecode(v))
        : v;
    if (decoded is List) {
      return [
        for (final e in decoded)
          if (e is Map) Map<String, dynamic>.from(e.cast<String, dynamic>()),
      ];
    }
  } catch (_) {}
  return const [];
}

/// 书源登录入口：按 loginUrl 形态分派（应用内浏览器 / 表单脚本）。
Future<void> showShuyuanLogin(BuildContext context, PluginConfig source) async {
  final loginUrl = shuyuanLoginUrl(source);
  if (loginUrl == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('该源未声明登录方式（loginUrl）')),
    );
    return;
  }
  final isScript =
      loginUrl.startsWith('@js:') || loginUrl.contains('<js>');
  if (!isScript) {
    // URL 形态：应用内浏览器登录，完成时回传 Cookie 覆盖层。
    final ctx = await ShuyuanSourceContext.forSource(source.id);
    if (!context.mounted) return;
    final outcome = await Navigator.of(context).push<ShuyuanBrowserOutcome>(
      AppPageRoute<ShuyuanBrowserOutcome>(
        builder: (_) => ShuyuanBrowserScreen(
          url: loginUrl,
          title: source.name,
          source: source,
        ),
      ),
    );
    if (outcome != null) {
      for (final e in outcome.cookieHeaders.entries) {
        ctx.syncCookies(e.key, e.value);
      }
      await ctx.persistIfNeeded();
    }
    return;
  }
  await _runFormLogin(context, source, loginUrl);
}

Future<void> _runFormLogin(
  BuildContext context,
  PluginConfig source,
  String loginUrl,
) async {
  final l10n = AppLocalizations.of(context);
  final xiaoshuo = source.selectors!['xiaoshuo'] as Map<String, dynamic>;
  final loginUi = shuyuanLoginUi(source);

  final ctx = await ShuyuanSourceContext.forSource(source.id);
  final vcRaw = xiaoshuo['variableComment'];
  final variableComment = vcRaw == null ? '' : '$vcRaw'.trim();
  final fields = <(TextEditingController, String)>[]; // (controller, name)
  for (final row in loginUi) {
    final name = '${row['name'] ?? ''}'.trim();
    if (name.isEmpty) continue;
    final type = '${row['type'] ?? 'text'}'.toLowerCase();
    if (type == 'button' || type == 'label') continue;
    fields.add((
      TextEditingController(
          text: ctx.loginInfo[name] ?? '${row['default'] ?? ''}'),
      name,
    ));
  }

  if (!context.mounted) return;
  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(l10n.bookSourceLogin),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (variableComment.isNotEmpty) ...<Widget>[
                Text(variableComment,
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: AppTokens.spaceSm),
              ],
              if (fields.isEmpty)
                Text(l10n.bookSourceLoginNoForm,
                    style: Theme.of(context).textTheme.bodySmall),
              for (var i = 0; i < fields.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
                  child: TextField(
                    controller: fields[i].$1,
                    obscureText: _isPassword(loginUi, fields[i].$2),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: fields[i].$2,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
                MaterialLocalizations.of(dialogContext).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.bookSourceLoginSubmit),
          ),
        ],
      ),
    ),
  );
  if (saved != true) return;

  // 表单值写入 ctx.loginInfo（登录脚本经 source.getLoginInfoMap 读取）。
  for (final (ctrl, name) in fields) {
    ctx.loginInfo[name] = ctrl.text;
  }

  // 执行登录脚本（mini-settle：java.ajax 走确定性重放）。
  final bookSource = ShuyuanSource.fromJson(
    Map<String, dynamic>.from(
        source.selectors!['xiaoshuo'] as Map<String, dynamic>),
  ).toBookSource();
  final js = loginUrl.startsWith('@js:')
      ? loginUrl.substring(4)
      : _extractJsBody(loginUrl);
  ctx.bindSource(bookSource);
  final engine = JsEngine.forSource(source.id);
  // 每次登录都重新抓取：清掉上次尝试的 ajax 缓存（宿主表 + JS 全局），
  // 否则重试会命中旧响应（典型是上次失败留下的登录页）。
  ctx.clearStageCaches();
  engine.resetReplayCaches();

  // 必须包在上下文作用域里：登录脚本靠 source.getLoginInfoMap() 取表单值，
  // syOp 的 ajax 记录也只有存在活动 ctx 时才回放进 ajaxPending。旧实现未包，
  // 结果是「表单值读不到 + 永远不发请求 + 还弹成功」。
  final ok = await ShuyuanSourceContext.run(ctx, () async {
    var deadline = DateTime.now().add(const Duration(seconds: 120));
    for (var pass = 0; pass < 10; pass++) {
      ctx.ajaxPending.clear();
      ctx.webviewPending.clear();
      final out = engine.eval(js);
      if (ctx.ajaxPending.isEmpty &&
          ctx.fileOpPending.isEmpty &&
          ctx.webviewPending.isEmpty &&
          !hasPendingInteractive(ctx)) {
        // 有输出，或本轮确实发过请求并重放过，才算执行成功。
        return pass > 0 || out.isNotEmpty;
      }
      if (!DateTime.now().isBefore(deadline)) return false;
      final interactive = await settleShuyuanInteractive(
        ctx,
        bookSource,
        pluginSource: source,
        openBrowsers: true,
      );
      deadline = deadline.add(interactive.waited);
      final fetched = interactive.fetched +
          await ShuyuanSourceContext.settleAjax(ctx, bookSource) +
          await ShuyuanSourceContext.settleWebview(ctx);
      // 本轮没有任何新进展：不再空转到预算耗尽。
      if (fetched == 0) return pass > 0 || out.isNotEmpty;
    }
    return false;
  });
  await ctx.persistIfNeeded();

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(ok ? l10n.bookSourceLoginSubmitted : l10n.failed)),
  );
}

bool _isPassword(List<Map<String, dynamic>> loginUi, String name) {
  for (final row in loginUi) {
    if ('${row['name'] ?? ''}'.trim() == name) {
      return '${row['type'] ?? ''}'.toLowerCase() == 'password';
    }
  }
  return false;
}

String _extractJsBody(String s) {
  final start = s.indexOf('<js>');
  final end = s.lastIndexOf('</js>');
  if (start >= 0 && end > start) return s.substring(start + 4, end);
  return s;
}
