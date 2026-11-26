/// legado 真值口径（`StringExtensions.kt`）供书源引擎复用。
library;

/// legado `String?.isTrue(nullIsTrue = false)`：
/// 空白 / **未 trim** 的字面 `null` 为假；忽略大小写的
/// `false|no|not|0|0.0` 为假；其余非空值（含 `" true "`、`" null "`、
/// `"是"`、`"vip"`）为真。
bool legadoIsTrue(String? value) {
  if (value == null) return false;
  final text = value.trim();
  if (text.isEmpty) return false;
  // legado 在 trim 前做精确 `this == "null"` 比较：`" null "` 不算 null，
  // 后续正则也不匹配假值，最终为 true。
  if (value == 'null') return false;
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
