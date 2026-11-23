/// legado 真值口径（`StringExtensions.kt`）供书源引擎复用。
library;

/// legado `String?.isTrue(nullIsTrue = false)`：
/// 空白 / 字面 `null` 为假；忽略大小写的 `false|no|not|0|0.0` 为假；
/// 其余非空值（含 `"true"`、`"yes"`、`"是"`、`"vip"`、带空白）为真。
bool legadoIsTrue(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty || text == 'null') return false;
  return !RegExp(r'^(?:false|no|not|0|0\.0)$', caseSensitive: false)
      .hasMatch(text);
}

/// legado `UrlOption.useWebView()`：`null`/空串/布尔 false/字符串 `"false"`
/// 为假，其余（`"1"`、`1`、`"yes"`、非空对象等）为真。
bool legadoUseWebView(Object? raw) {
  if (raw == null || raw == false) return false;
  if (raw is String) {
    return raw.isNotEmpty && raw != 'false';
  }
  return true;
}
