/// 段评规则：书源 `ruleReview` 段（legado `data.entities.rule.ReviewRule`）。
///
/// 字段语义与基准同名，缺省为 null（源未声明该能力）：
/// - [reviewUrl] 段评列表地址（可含 `{{page}}`/`{{key}}` 与 URL 选项串）；
/// - [contentRule] 段评内容（列表规则，逐项一条段评）；
/// - [avatarRule] 发布者头像（列表规则，与内容按序号对齐）；
/// - [postTimeRule] 发布时间（列表规则，与内容按序号对齐）；
/// - [reviewQuoteUrl] 某条段评的回复列表地址（`{{$.字段}}` 读条目上下文）；
/// - [voteUpUrl]/[voteDownUrl]/[postReviewUrl]/[postQuoteUrl]/[deleteUrl]
///   动作地址，`{{key}}` 承载用户输入文本（与搜索同一条编码通道）。
/// - [paragraphRule]（NexHub 扩展）：章级列表里「段号」的列表规则，用于把
///   段评锚定到具体段落；不声明时段评只在章级面板展示（无段落锚点）。
library;

class ReviewRule {
  String? reviewUrl;
  String? avatarRule;
  String? contentRule;
  String? postTimeRule;
  String? reviewQuoteUrl;
  String? voteUpUrl;
  String? voteDownUrl;
  String? postReviewUrl;
  String? postQuoteUrl;
  String? deleteUrl;

  /// 段号列表规则（NexHub 扩展，基准无此字段）：取值按序号与内容对齐，
  /// 解析为整数（0 起）；单条解析失败即视为「无锚点」。
  String? paragraphRule;

  ReviewRule({
    this.reviewUrl,
    this.avatarRule,
    this.contentRule,
    this.postTimeRule,
    this.reviewQuoteUrl,
    this.voteUpUrl,
    this.voteDownUrl,
    this.postReviewUrl,
    this.postQuoteUrl,
    this.deleteUrl,
    this.paragraphRule,
  });

  /// 是否声明了段评列表（列表 URL + 内容规则缺一不可）。
  bool get hasList =>
      (reviewUrl ?? '').trim().isNotEmpty &&
      (contentRule ?? '').trim().isNotEmpty;

  /// 是否可发帖/回复。
  bool get canPost => (postReviewUrl ?? '').trim().isNotEmpty;

  /// 是否可对某条段评发回复。
  bool get canQuote => (postQuoteUrl ?? '').trim().isNotEmpty;

  /// 是否可投票（赞/踩任一存在即可）。
  bool get canVote =>
      (voteUpUrl ?? '').trim().isNotEmpty ||
      (voteDownUrl ?? '').trim().isNotEmpty;

  bool get canDelete => (deleteUrl ?? '').trim().isNotEmpty;

  /// 是否声明了段落锚点（`paragraphRule`）。
  bool get hasParagraphAnchor => (paragraphRule ?? '').trim().isNotEmpty;

  factory ReviewRule.fromJson(Map<String, dynamic> json) {
    String? pick(String key) {
      final Object? v = json[key];
      if (v == null) return null;
      final s = v.toString();
      return s.isEmpty ? null : s;
    }

    return ReviewRule(
      reviewUrl: pick('reviewUrl'),
      avatarRule: pick('avatarRule'),
      contentRule: pick('contentRule'),
      postTimeRule: pick('postTimeRule'),
      reviewQuoteUrl: pick('reviewQuoteUrl'),
      voteUpUrl: pick('voteUpUrl'),
      voteDownUrl: pick('voteDownUrl'),
      postReviewUrl: pick('postReviewUrl'),
      postQuoteUrl: pick('postQuoteUrl'),
      deleteUrl: pick('deleteUrl'),
      paragraphRule: pick('paragraphRule'),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (reviewUrl != null) 'reviewUrl': reviewUrl,
        if (avatarRule != null) 'avatarRule': avatarRule,
        if (contentRule != null) 'contentRule': contentRule,
        if (postTimeRule != null) 'postTimeRule': postTimeRule,
        if (reviewQuoteUrl != null) 'reviewQuoteUrl': reviewQuoteUrl,
        if (voteUpUrl != null) 'voteUpUrl': voteUpUrl,
        if (voteDownUrl != null) 'voteDownUrl': voteDownUrl,
        if (postReviewUrl != null) 'postReviewUrl': postReviewUrl,
        if (postQuoteUrl != null) 'postQuoteUrl': postQuoteUrl,
        if (deleteUrl != null) 'deleteUrl': deleteUrl,
        if (paragraphRule != null) 'paragraphRule': paragraphRule,
      };
}
