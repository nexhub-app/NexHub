/// 书源事件回调（legado `SourceCallBack`）的执行结果。
///
/// md3 `callBackBtn` 语义：
/// - 脚本返回假值 → 执行默认动作（`noCall`）；
/// - 返回真值 → 不执行默认动作；
/// - 脚本异常 → 仅记日志，默认动作**不**执行。
///
/// 因此 [runDefault] 只在「无异常且返回假值」时为 true。
class SourceCallbackResult {
  const SourceCallbackResult({
    required this.runDefault,
    this.value = '',
    this.error,
    this.openRequests = const <Map<String, String>>[],
    this.copiedTexts = const <String>[],
    this.tocUrl = '',
  });

  /// 是否执行调用方提供的默认动作。
  final bool runDefault;

  /// 脚本返回值文本（null 归一为空串）。
  final String value;

  /// 脚本异常信息；非空时默认动作不执行。
  final String? error;

  /// 脚本经 `java.open(...)` 请求的宿主界面动作
  /// （`name` = login/search/explore，附 `url`/`title`/`origin`）。
  final List<Map<String, String>> openRequests;

  /// 脚本经 `java.copyText(...)` 写入剪贴板的文本（按调用顺序）。
  final List<String> copiedTexts;

  /// 回调后书对象的 tocUrl（md3 `clickCopyTocUrl` 的默认动作来源）。
  final String tocUrl;
}
