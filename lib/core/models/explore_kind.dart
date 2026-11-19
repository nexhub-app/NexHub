/// 发现页「选项栏」模型：对齐 legado ExploreKind 与 FlexChildStyle。
///
/// 书源 exploreUrl 由 JSON 数组声明时，每个条目除了 `title`/`url` 还可能
/// 带 `type`（url/text/button/toggle/select）、`action`（点击执行的 JS）、
/// `chars`（toggle/select 选项）、`default`、`viewName`（显示名，可含 JS）
/// 与 `style`（flex 布局参数）。旧实现只保留 title/url，选项栏条目被整体
/// 丢弃——发现页看起来「分类不全」。
library;

/// 选项类型（未知类型的条目在 UI 上按静态文本展示；缺失 type 视为 url）。
enum ExploreKindType { url, text, button, toggle, select }

/// 单条选项在 6 栅格行里的 flex 布局参数（legado FlexChildStyle）。
class ExploreKindStyle {
  final double layoutFlexGrow;
  final double layoutFlexShrink;
  final String layoutAlignSelf;
  final double layoutFlexBasisPercent;
  final bool layoutWrapBefore;

  /// toggle 的选中值放在显示名左侧还是右侧（非 "right" 即左侧）。
  final String layoutJustifySelf;

  const ExploreKindStyle({
    this.layoutFlexGrow = 0,
    this.layoutFlexShrink = 1,
    this.layoutAlignSelf = 'auto',
    this.layoutFlexBasisPercent = -1,
    this.layoutWrapBefore = false,
    this.layoutJustifySelf = 'auto',
  });

  factory ExploreKindStyle.fromJson(Map<String, dynamic> json) {
    double d(String key, double fallback) {
      final v = json[key];
      if (v is num) return v.toDouble();
      return double.tryParse('${v ?? ''}') ?? fallback;
    }

    bool b(String key, bool fallback) {
      final v = json[key];
      if (v is bool) return v;
      if (v is num) return v != 0;
      final s = '${v ?? ''}'.trim().toLowerCase();
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
      return fallback;
    }

    String s(String key, String fallback) {
      final v = json[key];
      if (v == null) return fallback;
      final out = '$v'.trim();
      return out.isEmpty ? fallback : out;
    }

    return ExploreKindStyle(
      layoutFlexGrow: d('layout_flexGrow', 0),
      layoutFlexShrink: d('layout_flexShrink', 1),
      layoutAlignSelf: s('layout_alignSelf', 'auto'),
      layoutFlexBasisPercent: d('layout_flexBasisPercent', -1),
      layoutWrapBefore: b('layout_wrapBefore', false),
      layoutJustifySelf: s('layout_justifySelf', 'auto'),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'layout_flexGrow': layoutFlexGrow,
        'layout_flexShrink': layoutFlexShrink,
        'layout_alignSelf': layoutAlignSelf,
        'layoutFlexBasisPercent': layoutFlexBasisPercent,
        'layout_wrapBefore': layoutWrapBefore,
        'layout_justifySelf': layoutJustifySelf,
      };
}

/// 发现页的一条选项（分类 / 输入框 / 按钮 / 开关 / 下拉）。
class ExploreKind {
  final String title;
  final String? url;
  final String type;
  final String? action;
  final List<String> chars;
  final String? defaultValue;
  final String? viewName;
  final ExploreKindStyle style;

  const ExploreKind({
    required this.title,
    this.url,
    this.type = 'url',
    this.action,
    this.chars = const <String>[],
    this.defaultValue,
    this.viewName,
    this.style = const ExploreKindStyle(),
  });

  factory ExploreKind.fromJson(Map<String, dynamic> json) {
    final rawTitle = json['title'] ?? json['name'];
    final title = rawTitle == null ? '' : '$rawTitle'.trim();
    final rawUrl = json['url'];
    final url = rawUrl == null ? null : '$rawUrl'.trim();
    final rawChars = json['chars'];
    final chars = <String>[
      if (rawChars is List)
        for (final c in rawChars)
          if (c != null) '$c',
    ];
    final rawStyle = json['style'];
    return ExploreKind(
      title: title,
      url: (url == null || url.isEmpty) ? null : url,
      type: '${json['type'] ?? 'url'}'.trim().toLowerCase(),
      action: _optString(json['action']),
      chars: chars,
      defaultValue: _optString(json['default']),
      viewName: _optString(json['viewName']),
      style: rawStyle is Map
          ? ExploreKindStyle.fromJson(
              Map<String, dynamic>.from(rawStyle))
          : const ExploreKindStyle(),
    );
  }

  static String? _optString(Object? v) {
    if (v == null) return null;
    final s = '$v';
    return s.trim().isEmpty ? null : s;
  }

  /// 与 [ExploreKind.fromJson] 键名一致，供发现页缓存往返
  /// （legado 同样把 exploreKinds 的 JSON 持久化到 ACache）。
  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': title,
        if (url != null) 'url': url,
        'type': type,
        if (action != null) 'action': action,
        if (chars.isNotEmpty) 'chars': chars,
        if (defaultValue != null) 'default': defaultValue,
        if (viewName != null) 'viewName': viewName,
        'style': style.toJson(),
      };

  /// 缺失 type 视为 url；未知 type 返回 null（按静态条目展示）。
  ExploreKindType? get recognizedType => switch (type) {
        '' || 'url' => ExploreKindType.url,
        'text' => ExploreKindType.text,
        'button' => ExploreKindType.button,
        'toggle' => ExploreKindType.toggle,
        'select' => ExploreKindType.select,
        _ => null,
      };

  bool get isBrowsable =>
      recognizedType == ExploreKindType.url &&
      url != null &&
      url!.trim().isNotEmpty;

  ExploreKind copyWith({String? title, String? url, String? viewName}) {
    return ExploreKind(
      title: title ?? this.title,
      url: url ?? this.url,
      type: type,
      action: action,
      chars: chars,
      defaultValue: defaultValue,
      viewName: viewName ?? this.viewName,
      style: style,
    );
  }
}

/// 单条选项的解析结果（显示名与当前值已按 infoMap 求值）。
class ExploreKindItem {
  final ExploreKind kind;

  /// 最终显示名（viewName 求值结果，缺省为 title）。
  final String displayName;

  /// 当前值：text 为输入内容；toggle/select 为选中项；其余为空串。
  final String value;

  const ExploreKindItem({
    required this.kind,
    required this.displayName,
    this.value = '',
  });
}

/// 布局行：一行内若干（条目, 跨列数）。
class ExploreKindRowItem {
  final ExploreKindItem item;
  final int span;

  const ExploreKindRowItem(this.item, this.span);
}

/// 6 栅格 flex 布局（移植自 legado calculateExploreKindRows）。
///
/// 跨列规则：wrapBefore 或 basisPercent >= 1 → 整行；basisPercent > 0 →
/// round(span*pct)（1..span）；flexGrow > 0 → 3；其余 → 2。
/// 行尾补齐：等宽多列时均分剩余列，否则全部加到最后一列。
List<List<ExploreKindRowItem>> layoutExploreKindRows(
  List<ExploreKindItem> items, {
  int maxSpan = 6,
}) {
  final rows = <List<ExploreKindRowItem>>[];
  var current = <ExploreKindRowItem>[];
  var currentSpan = 0;

  void fillTail() {
    if (current.isEmpty) return;
    final remain = maxSpan - currentSpan;
    if (remain <= 0) return;
    final allSame = current.map((e) => e.span).toSet().length == 1;
    if (allSame && current.length > 1) {
      final addEach = remain ~/ current.length;
      var extra = remain % current.length;
      for (var i = 0; i < current.length; i++) {
        var add = addEach;
        if (extra > 0) {
          extra -= 1;
          add += 1;
        }
        final old = current[i];
        current[i] = ExploreKindRowItem(old.item, old.span + add);
      }
    } else {
      final last = current.last;
      current[current.length - 1] =
          ExploreKindRowItem(last.item, last.span + remain);
    }
    currentSpan += remain;
  }

  for (final item in items) {
    final style = item.kind.style;
    final int span;
    if (style.layoutWrapBefore || style.layoutFlexBasisPercent >= 1.0) {
      span = maxSpan;
    } else if (style.layoutFlexBasisPercent > 0) {
      span = (maxSpan * style.layoutFlexBasisPercent)
          .round()
          .clamp(1, maxSpan)
          .toInt();
    } else if (style.layoutFlexGrow > 0) {
      span = 3;
    } else {
      span = 2;
    }
    if ((style.layoutWrapBefore && current.isNotEmpty) ||
        currentSpan + span > maxSpan) {
      fillTail();
      rows.add(current);
      current = <ExploreKindRowItem>[];
      currentSpan = 0;
    }
    current.add(ExploreKindRowItem(item, span));
    currentSpan += span;
    if (currentSpan >= maxSpan) {
      rows.add(current);
      current = <ExploreKindRowItem>[];
      currentSpan = 0;
    }
  }
  if (current.isNotEmpty) {
    fillTail();
    rows.add(current);
  }
  return rows;
}

/// 一次选项栏解析的完整结果。
class ExploreKindsResult {
  final List<ExploreKindItem> items;

  /// 解析后的 infoMap（含自动补写的 toggle/select 默认值）。
  final Map<String, String> infoMap;

  /// 解析失败信息（脚本异常 / 配置非法）。非空时 [items] 为空。
  final String? error;

  const ExploreKindsResult({
    this.items = const <ExploreKindItem>[],
    this.infoMap = const <String, String>{},
    this.error,
  });
}

/// 选项 action 执行后请求宿主的浏览器动作（java.startBrowser / openUrl）。
class ExploreKindOpenRequest {
  final String url;
  final String title;

  const ExploreKindOpenRequest({required this.url, this.title = ''});
}

/// 选项 action 执行结果：脚本可能要打开浏览器、刷新选项栏或复制文本。
class ExploreKindActionResult {
  final List<ExploreKindOpenRequest> openRequests;
  final bool refreshKinds;
  final List<String> copiedTexts;

  const ExploreKindActionResult({
    this.openRequests = const <ExploreKindOpenRequest>[],
    this.refreshKinds = false,
    this.copiedTexts = const <String>[],
  });
}
