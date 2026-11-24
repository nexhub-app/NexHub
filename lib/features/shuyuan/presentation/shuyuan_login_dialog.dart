/// legado 书源登录入口（P2-1）。
///
/// loginUrl 形态分派：
/// - URL（非脚本）→ [ShuyuanBrowserScreen]，完成时回传 Cookie 至
///   书源上下文覆盖层（per-source overlay）；
/// - `@js:`/`<js>` 脚本 → loginUi（RowUi）表单收集值写入 ctx.loginInfo →
///   执行脚本（mini-settle：脚本内 java.ajax 走确定性重放）。
///
/// 表单行按 legado `RowUi` 类型渲染（text/password/button/toggle/select），
/// 行 action 以 `loginJs + action` 求值（绑定 result/isLongClick），
/// viewName 支持单引号字面量与脚本求值。
///
/// loginCheckJs 校验由 WebBook 五个入口对首响应消费
/// （AnalyzeUrl.applyLoginCheck，code==500 → ShuyuanLoginRequiredException）。
library;

import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/plugin_config.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/navigation/app_page_route.dart';
import '../analyze/js_engine.dart';
import '../analyze/source_context.dart';
import '../model/book_source.dart';
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

/// 登录表单行（legado `RowUi`：type/action/chars/default/viewName/style）。
class ShuyuanLoginRow {
  ShuyuanLoginRow({
    required this.name,
    required this.type,
    this.action,
    this.chars = const <String>[],
    this.defaultValue,
    this.viewName,
    this.flexGrow = 0,
    this.flexBasisPercent = -1,
    this.wrapBefore = false,
    this.justifySelf = 'auto',
  }) : title = name;

  final String name;

  /// text / password / button / toggle / select（未知类型按文本行渲染）。
  final String type;
  final String? action;
  final List<String> chars;
  final String? defaultValue;
  final String? viewName;
  final double flexGrow;
  final double flexBasisPercent;
  final bool wrapBefore;
  final String justifySelf;

  /// viewName 解析后的显示名（[shuyuanLoginRowTitle] 写入）。
  String title;

  static ShuyuanLoginRow fromJson(Map<String, dynamic> row) {
    final style = row['style'];
    final styleMap =
        style is Map ? style.cast<dynamic, dynamic>() : const <dynamic, dynamic>{};
    double numOf(String key, double fallback) {
      final v = styleMap[key];
      if (v is num) return v.toDouble();
      return double.tryParse('${v ?? ''}') ?? fallback;
    }

    return ShuyuanLoginRow(
      name: '${row['name'] ?? ''}'.trim(),
      type: '${row['type'] ?? 'text'}'.trim().toLowerCase(),
      action: row['action'] == null ? null : '${row['action']}',
      chars: <String>[
        for (final c in (row['chars'] as List?) ?? const <dynamic>[])
          if (c != null) '$c',
      ],
      defaultValue: row['default'] == null ? null : '${row['default']}',
      viewName: row['viewName'] == null ? null : '${row['viewName']}',
      flexGrow: numOf('layout_flexGrow', 0),
      flexBasisPercent: numOf('layout_flexBasisPercent', -1),
      wrapBefore: styleMap['layout_wrapBefore'] == true,
      justifySelf: '${styleMap['layout_justifySelf'] ?? 'auto'}',
    );
  }
}

/// loginUi 原始行 → 表单行（名字为空的行丢弃，对齐「无名行不产值」）。
List<ShuyuanLoginRow> shuyuanLoginRows(List<Map<String, dynamic>> ui) => <
    ShuyuanLoginRow>[
  for (final row in ui)
    if ('${row['name'] ?? ''}'.trim().isNotEmpty)
      ShuyuanLoginRow.fromJson(row),
];

/// 表单初始值（legado buildForm/getLoginInfoMap 口径）：
/// toggle/select 已有非空值优先，否则 `default`，再否则 `chars.first`；
/// 文本类已有值优先，否则 `default`。button/label 不产值。
Map<String, String> shuyuanLoginRowDefaults(
  List<ShuyuanLoginRow> rows,
  Map<String, String> saved,
) {
  final values = <String, String>{};
  for (final row in rows) {
    if (row.type == 'button' || row.type == 'label') continue;
    final existing = saved[row.name];
    if (row.type == 'toggle' || row.type == 'select') {
      values[row.name] = (existing != null && existing.isNotEmpty)
          ? existing
          : (row.defaultValue ??
              (row.chars.isNotEmpty ? row.chars.first : ''));
    } else {
      values[row.name] = existing ?? row.defaultValue ?? '';
    }
  }
  return values;
}

/// 行显示名（legado `SourceLoginViewModel.resolveTitle`）：
/// 3..19 长度且首尾单引号 → 字面量去引号；否则脚本求值，空结果回落 name。
String shuyuanLoginRowTitle(
  ShuyuanLoginRow row,
  String? Function(String script)? evaluate,
) {
  final viewName = row.viewName;
  if (viewName == null || viewName.isEmpty) return row.name;
  if (viewName.length >= 3 &&
      viewName.length <= 19 &&
      viewName.startsWith("'") &&
      viewName.endsWith("'")) {
    return viewName.substring(1, viewName.length - 1);
  }
  final out = evaluate?.call(viewName);
  return (out == null || out.isEmpty) ? row.name : out;
}

/// toggle 点击循环：当前值在 chars 的下一项（未匹配时回落首项）。
String shuyuanLoginToggleNext(String current, List<String> chars) {
  final options = chars.isEmpty ? const <String>['chars', 'is null'] : chars;
  final index = options.indexOf(current);
  return options[index < 0 ? 0 : (index + 1) % options.length];
}

const int _loginFormMaxSpan = 6;

/// 行分组布局（legado `calculateFlexRows` 移植，maxSpan=6）：
/// 文本行整行独占（basisPercent=1 + wrapBefore），其余行按
/// style 的 flexGrow/basisPercent/wrapBefore 拼行。
List<List<(ShuyuanLoginRow, int)>> shuyuanLoginRowsLayout(
  List<ShuyuanLoginRow> rows, {
  int maxSpan = _loginFormMaxSpan,
}) {
  final result = <List<(ShuyuanLoginRow, int)>>[];
  var current = <(ShuyuanLoginRow, int)>[];
  var currentSpan = 0;

  void fillTail() {
    if (current.isEmpty) return;
    final remain = maxSpan - currentSpan;
    if (remain <= 0) return;
    final spans = current.map((e) => e.$2).toSet();
    if (spans.length == 1 && current.length > 1) {
      final addEach = remain ~/ current.length;
      var extra = remain % current.length;
      for (var i = 0; i < current.length; i++) {
        var add = addEach;
        if (extra > 0) {
          extra -= 1;
          add += 1;
        }
        current[i] = (current[i].$1, current[i].$2 + add);
      }
    } else {
      current[current.length - 1] =
          (current.last.$1, current.last.$2 + remain);
    }
    currentSpan += remain;
  }

  for (final row in rows) {
    final isTextRow = !<String>{'button', 'select', 'toggle'}.contains(row.type);
    final int span;
    if (isTextRow || row.wrapBefore || row.flexBasisPercent >= 1) {
      span = maxSpan;
    } else if (row.flexBasisPercent > 0) {
      span = (maxSpan * row.flexBasisPercent).round().clamp(1, maxSpan);
    } else if (row.flexGrow > 0) {
      span = 3;
    } else {
      span = 2;
    }
    if ((row.wrapBefore && current.isNotEmpty) ||
        (currentSpan + span > maxSpan)) {
      fillTail();
      result.add(current);
      current = <(ShuyuanLoginRow, int)>[];
      currentSpan = 0;
    }
    current.add((row, span));
    currentSpan += span;
    if (currentSpan >= maxSpan) {
      result.add(current);
      current = <(ShuyuanLoginRow, int)>[];
      currentSpan = 0;
    }
  }
  if (current.isNotEmpty) {
    fillTail();
    result.add(current);
  }
  return result;
}

/// 登录表单控件（legado `SourceLoginFormSheet` 行渲染口径）。
///
/// [values] 是调用方持有的可变表：控件用其初始化，改动直接写回。
/// [onAction] 对应 legado `runRowAction`（text 行输入完成、toggle/select
/// 值变化、button 点击均触发）。
class ShuyuanLoginForm extends StatefulWidget {
  const ShuyuanLoginForm({
    super.key,
    required this.rows,
    required this.values,
    this.onAction,
  });

  final List<ShuyuanLoginRow> rows;
  final Map<String, String> values;
  final Future<void> Function(ShuyuanLoginRow row)? onAction;

  @override
  State<ShuyuanLoginForm> createState() => _ShuyuanLoginFormState();
}

class _ShuyuanLoginFormState extends State<ShuyuanLoginForm> {
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    for (final row in widget.rows) {
      if (_isTextRow(row)) {
        _controllers[row.name] =
            TextEditingController(text: widget.values[row.name] ?? '');
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  static bool _isTextRow(ShuyuanLoginRow row) =>
      !<String>{'button', 'select', 'toggle'}.contains(row.type);

  @override
  Widget build(BuildContext context) {
    final layout = shuyuanLoginRowsLayout(widget.rows);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final group in layout)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
            child: Row(
              children: <Widget>[
                for (var i = 0; i < group.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: AppTokens.spaceSm),
                  Expanded(
                    flex: group[i].$2,
                    child: _buildRow(context, group[i].$1),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildRow(BuildContext context, ShuyuanLoginRow row) {
    final current = widget.values[row.name] ?? '';
    if (row.type == 'button') {
      return FilledButton.tonal(
        onPressed: () => widget.onAction?.call(row),
        child: Text(row.title),
      );
    }
    if (row.type == 'toggle') {
      final text = row.justifySelf == 'right'
          ? '${row.title}$current'
          : '$current${row.title}';
      return OutlinedButton(
        onPressed: () {
          final next = shuyuanLoginToggleNext(current, row.chars);
          setState(() => widget.values[row.name] = next);
          widget.onAction?.call(row);
        },
        child: Text(text, overflow: TextOverflow.ellipsis),
      );
    }
    if (row.type == 'select') {
      final options = row.chars;
      return PopupMenuButton<String>(
        tooltip: '',
        onSelected: (value) {
          if (value == current) return;
          setState(() => widget.values[row.name] = value);
          widget.onAction?.call(row);
        },
        itemBuilder: (_) => <PopupMenuEntry<String>>[
          for (final option in options)
            PopupMenuItem<String>(value: option, child: Text(option)),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Expanded(
                child: Text(
                  '${row.title} $current',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.arrow_drop_down, size: 18),
            ],
          ),
        ),
      );
    }
    final controller = _controllers[row.name];
    if (controller == null) return const SizedBox.shrink();
    return TextField(
      controller: controller,
      obscureText: row.type == 'password',
      onChanged: (value) => widget.values[row.name] = value,
      onSubmitted: (_) => widget.onAction?.call(row),
      decoration: InputDecoration(isDense: true, labelText: row.title),
    );
  }
}

/// 登录脚本求值（mini-settle：脚本内 java.ajax 走确定性重放）。
/// 供登录提交与行 action 共用；[bindings] 同 [JsEngine.eval]。
Future<bool> evalShuyuanLoginScript(
  ShuyuanSourceContext ctx,
  JsEngine engine,
  XiaoshuoBookSource bookSource,
  PluginConfig pluginSource,
  String script, {
  Map<String, dynamic>? bindings,
}) async {
  return ShuyuanSourceContext.run(ctx, () async {
    var deadline = DateTime.now().add(const Duration(seconds: 120));
    for (var pass = 0; pass < 10; pass++) {
      ctx.ajaxPending.clear();
      ctx.webviewPending.clear();
      final out = engine.eval(script, bindings: bindings);
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
        pluginSource: pluginSource,
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
  final rows = shuyuanLoginRows(shuyuanLoginUi(source));

  final ctx = await ShuyuanSourceContext.forSource(source.id);
  final vcRaw = xiaoshuo['variableComment'];
  final variableComment = vcRaw == null ? '' : '$vcRaw'.trim();

  final bookSource = ShuyuanSource.fromJson(
    Map<String, dynamic>.from(xiaoshuo),
  ).toBookSource();
  ctx.bindSource(bookSource);
  final engine = JsEngine.forSource(source.id);
  final js = loginUrl.startsWith('@js:')
      ? loginUrl.substring(4)
      : _extractJsBody(loginUrl);

  // 行显示名（legado viewName）：字面量直接取下；其余拼 loginJs 求值
  // （绑定 result），空结果回落 name。
  final values = shuyuanLoginRowDefaults(rows, ctx.loginInfo);
  for (final row in rows) {
    row.title = shuyuanLoginRowTitle(row, (script) {
      try {
        return ShuyuanSourceContext.run(
          ctx,
          () => engine.eval(
            js.isEmpty ? script : '$js\n$script',
            bindings: <String, dynamic>{
              'result': Map<String, String>.from(values),
            },
          ),
        );
      } catch (_) {
        return null;
      }
    });
  }

  if (!context.mounted) return;
  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.bookSourceLogin),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (variableComment.isNotEmpty) ...<Widget>[
                Text(variableComment,
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: AppTokens.spaceSm),
              ],
              if (!rows.any((r) => r.type != 'button' && r.type != 'label'))
                Text(l10n.bookSourceLoginNoForm,
                    style: Theme.of(context).textTheme.bodySmall),
              ShuyuanLoginForm(
                rows: rows,
                values: values,
                onAction: (row) => _runRowAction(
                  context,
                  ctx,
                  engine,
                  bookSource,
                  source,
                  js,
                  row,
                  values,
                ),
              ),
            ],
          ),
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
  );
  if (saved != true) return;

  // 表单值写入 ctx.loginInfo（登录脚本经 source.getLoginInfoMap 读取），
  // 并标记为待持久化：重启后表单预填值仍在（legado putLoginInfo 落盘）。
  for (final row in rows) {
    if (row.type == 'button' || row.type == 'label') continue;
    ctx.loginInfo[row.name] = values[row.name] ?? '';
  }
  ctx.loginDirty = true;

  // 执行登录脚本（mini-settle：java.ajax 走确定性重放）。
  // 每次登录都重新抓取：清掉上次尝试的 ajax 缓存（宿主表 + JS 全局），
  // 否则重试会命中旧响应（典型是上次失败留下的登录页）。
  ctx.clearStageCaches();
  engine.resetReplayCaches();
  final ok =
      await evalShuyuanLoginScript(ctx, engine, bookSource, source, js);
  await ctx.persistIfNeeded();

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(ok ? l10n.bookSourceLoginSubmitted : l10n.failed)),
  );
}

/// 执行 loginUi 行 action（legado `SourceLoginViewModel.runRowAction`）：
/// http(s) 绝对地址 → 系统浏览器打开；否则执行 `loginJs + "\n" + action`，
/// 绑定 result（当前表单值）与 isLongClick，脚本内 java.ajax 走 mini-settle。
Future<void> _runRowAction(
  BuildContext context,
  ShuyuanSourceContext ctx,
  JsEngine engine,
  XiaoshuoBookSource bookSource,
  PluginConfig source,
  String loginJs,
  ShuyuanLoginRow row,
  Map<String, String> values,
) async {
  final action = row.action?.trim();
  if (action == null || action.isEmpty) return;
  // legado isAbsUrl 仅认 http(s)：绝对地址交给系统浏览器。
  if (action.startsWith('http://') || action.startsWith('https://')) {
    try {
      await launchUrl(Uri.parse(action), mode: LaunchMode.externalApplication);
    } catch (_) {}
    return;
  }
  ctx.clearStageCaches();
  engine.resetReplayCaches();
  final script = loginJs.isEmpty ? action : '$loginJs\n$action';
  await evalShuyuanLoginScript(
    ctx,
    engine,
    bookSource,
    source,
    script,
    bindings: <String, dynamic>{
      'result': Map<String, String>.from(values),
      'isLongClick': false,
    },
  );
  await ctx.persistIfNeeded();
}

String _extractJsBody(String s) {
  final start = s.indexOf('<js>');
  final end = s.lastIndexOf('</js>');
  if (start >= 0 && end > start) return s.substring(start + 4, end);
  return s;
}
