/// 书源章节购买动作（legado `ruleContent.payAction`）的执行结果。
///
/// 对齐 legado `MangaReaderActionPaymentResult`：
/// - [NovelPayOutcome.openUrl]：payAction 返回绝对 URL → 打开支付页；
/// - [NovelPayOutcome.refreshed]：payAction 返回真值 → 已购买，正文缓存
///   失效并重新抓取。
library;

enum NovelPayOutcome {
  openUrl,
  refreshed,
}

class NovelPayResult {
  final NovelPayOutcome outcome;

  /// 仅 [NovelPayOutcome.openUrl] 时非空。
  final String? url;

  const NovelPayResult._(this.outcome, {this.url});

  factory NovelPayResult.openUrl(String url) =>
      NovelPayResult._(NovelPayOutcome.openUrl, url: url);

  factory NovelPayResult.refreshed() =>
      const NovelPayResult._(NovelPayOutcome.refreshed);
}
