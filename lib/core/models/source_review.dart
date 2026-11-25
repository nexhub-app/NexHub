/// 段评条目（书源段评列表中的一条）。
///
/// 字段来自 [ReviewRule] 的三条列表规则按**序号对齐**取值：
/// `contentRule` → [content]、`avatarRule` → [avatar]、`postTimeRule` → [postTime]。
/// 规则缺省或长度不足时对应字段为空串（不丢条目）。
///
/// [context] 是该条目的模板上下文：动作地址（[ReviewRule.voteUpUrl] 等）里的
/// `{{$.字段}}` 从这里取值，缺省字段为 `content/avatar/postTime/index/paragraph`。
///
/// [paragraph] 是段落锚点（0 起，正文**块**下标，与朗读/分页同一口径）：
/// 由书源 `paragraphRule` 列表规则给出；未声明/解析失败为 null，
/// 表示该条段评只属于整章。
library;

class SourceReview {
  SourceReview({
    required this.content,
    this.avatar = '',
    this.postTime = '',
    this.index = 0,
    this.paragraph,
    this.voteUp = 0,
    this.voteDown = 0,
    Map<String, dynamic>? context,
  }) : context = <String, dynamic>{
          'content': content,
          'avatar': avatar,
          'postTime': postTime,
          'index': index,
          ...?context,
          'paragraph': paragraph ?? (context?['paragraph'] ?? ''),
          'voteUp': voteUp,
          'voteDown': voteDown,
        };

  /// 段评正文。
  final String content;

  /// 发布者头像地址（相对地址由规则层绝对化）。
  final String avatar;

  /// 发布时间（原样字符串，站点格式各异，由渲染层直接展示）。
  final String postTime;

  /// 在列表中的序号（0 起）。
  final int index;

  /// 段落锚点（0 起，**正文段落序号**，插图块不计入）；null = 未锚定（章级）。
  final int? paragraph;

  /// 赞数 / 踩数（源声明计数规则时非 0；0 表示未提供）。
  final int voteUp;
  final int voteDown;

  /// 模板上下文（`{{$.字段}}` 求值根）。
  final Map<String, dynamic> context;

  SourceReview copyWith({
    String? content,
    String? postTime,
    int? index,
    int? paragraph,
    int? voteUp,
    int? voteDown,
  }) {
    return SourceReview(
      content: content ?? this.content,
      avatar: avatar,
      postTime: postTime ?? this.postTime,
      index: index ?? this.index,
      paragraph: paragraph ?? this.paragraph,
      voteUp: voteUp ?? this.voteUp,
      voteDown: voteDown ?? this.voteDown,
      context: context,
    );
  }
}
