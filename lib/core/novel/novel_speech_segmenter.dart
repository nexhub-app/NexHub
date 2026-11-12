/// 小说 TTS 分句器（与 RuleBasedSpeechSegmenter 语义一致）。
///
/// 纯函数：输入段落文本，输出带角色标注的句子段序列。
/// 规则：
/// - **引号配对**：成对引号（「」『』“”‘’）内的内容视为对话，归属角色；
/// - **cue 判定**：开口引号前 ≤24 字符窗口内匹配「说道/心想/问/答/喊/说/道」
/// 等 cue（含冒号句式「XX说：」），提取说话人；无 cue 的引号归属「对话」；
/// - **旁白**：引号外的文本按标点（。！？；…）切成短句，role = 旁白；
/// - **不含引号的整段**：按标点分句，均视为旁白；
/// - 空段返回空列表。
///
/// 角色名解析（简化）：cue 匹配到的说话人取「前缀最长匹配」候选；
/// 引擎层用配置的音色表（角色名 → voice id）映射音色，未配置角色回退默认音色。
///
/// 性别推断（[SpeechGender]）：说话人已知性别（调用方传入 [knownGenders]
/// 角色卡平铺表）优先；其次 cue 窗口里的「她/他 + 动词」代词句式；
/// 再次说话人或窗口里的称谓词（姑娘/公子等）。判不出为 unknown，
/// 由路由层走默认音色。
library;

/// 单条 TTS 句段。
class SpeechSegment {
  /// 朗读文本（不含引号）。
  final String text;

  /// 角色标注：cue 解析出的说话人，或 [narratorRole]（旁白）/ [quoteRole]（对话）。
  final String role;

  final String sourceRole;

  /// 说话人性别（[SpeechGender]；旁白/判不出为 unknown）。
  final String gender;

  const SpeechSegment({
    required this.text,
    required this.role,
    required this.sourceRole,
    this.gender = SpeechGender.unknown,
  });

  SpeechSegment copyWith({String? role, String? gender}) => SpeechSegment(
        text: text,
        role: role ?? this.role,
        sourceRole: sourceRole,
        gender: gender ?? this.gender,
      );
}

/// 说话人性别常量。
abstract final class SpeechGender {
  static const String male = 'male';
  static const String female = 'female';
  static const String unknown = 'unknown';
}

/// 旁白角色名。
const String narratorRole = '旁白';

/// 无 cue 对话的默认角色名。
const String quoteRole = '对话';

/// 女性称谓词（说话人名或 cue 窗口命中即判女声）。
const List<String> kFemaleAddressTerms = <String>[
  '小妹妹', '妹妹', '小姑娘', '姑娘', '大小姐', '小姐', '女士', '女侠', '夫人',
  '娘子', '大姐姐', '姐姐', '阿姨', '大婶', '老奶奶', '奶奶', '婆婆', '大妈',
  '婶婶', '丫头', '小丫头', '丫鬟', '姑姑', '嫂子', '大娘', '婆姨', '女娃',
];

/// 男性称谓词（同上，判男声）。
const List<String> kMaleAddressTerms = <String>[
  '小弟弟', '弟弟', '小公子', '公子', '少爷', '先生', '小哥', '大哥', '大叔',
  '老爷', '爷爷', '老伯', '伯伯', '大爷', '叔叔', '老哥', '壮士', '侠士',
  '小子', '少年', '道长', '大师', '师父', '师傅', '掌柜', '官人', '相公',
  '郎君', '小生', '老朽', '老夫', '贫道', '洒家',
];

/// cue 关键词（说话/心理活动动词短语），用于匹配开口引号前的说话人。
const List<String> kSpeechCueWords = <String>[
  '说道',
  '说',
  '问道',
  '问',
  '答道',
  '回答',
  '答',
  '心想',
  '想',
  '喊道',
  '喊',
  '叫道',
  '笑道',
  '笑道：',
  '喃喃道',
  '低声道',
  '大声道',
  '沉声道',
  '冷声道',
  '叹道',
  '忙道',
];

/// 对话引号对（开/闭）。
const List<(String, String)> kQuotePairs = <(String, String)>[
  ('“', '”'),
  ('‘', '’'),
  ('「', '」'),
  ('『', '』'),
  ('"', '"'),
  ('\'', '\''),
];

/// 段落结束标点（旁白切句）。
const List<String> kSentencePunctuation = <String>['。', '！', '？', '…', '；'];

/// cue 词交替模式（长词优先，供代词性别推断复用；均为纯文字无需转义）。
final String cueAlternation = () {
  final cues = [...kSpeechCueWords]..sort((a, b) => b.length.compareTo(a.length));
  return cues.map(RegExp.escape).join('|');
}();

/// 把一段文本切分为 TTS 句段。
///
/// [text] 为原始段落。实现：先按引号对切分「旁白区/对话区」，对话区
/// 用 cue 提取角色并整体作为一句；旁白区按结束标点切句（role=旁白）。
///
/// [knownGenders] 为说话人 → 性别平铺表（调用方把角色卡的名字与别名
/// 都展平进来）；未命中时退回称谓词/代词推断。
List<SpeechSegment> segmentSpeech(String text,
    {Map<String, String> knownGenders = const <String, String>{}}) {
  if (text.isEmpty) return const <SpeechSegment>[];
  final segments = <SpeechSegment>[];

  // 1) 按引号配对扫描一次，收集对话区间。
  final quotes = <({int start, int end, String content, int windowStart})>[];
  var i = 0;
  while (i < text.length) {
    for (final (open, close) in kQuotePairs) {
      if (i + open.length <= text.length && text.startsWith(open, i)) {
        final closeIdx = text.indexOf(close, i + open.length);
        if (closeIdx > i) {
          final quoteStart = i;
          final quoteEnd = closeIdx + close.length;
          quotes.add((
            start: quoteStart,
            end: quoteEnd,
            content: text.substring(i + open.length, closeIdx),
            windowStart: (quoteStart - 24).clamp(0, quoteStart),
          ));
          i = quoteEnd;
          break;
        }
      }
    }
    i++;
  }

  // 2) 合并旁白区与对话区。
  var cursor = 0;
  for (final q in quotes) {
    // 引号前的旁白（剥离段尾「说话人+冒号」引导语，如 `小红说道：`——
    // 引导语属引号句的 cue 上下文，不单独朗读）。
    if (q.start > cursor) {
      final lead = _stripSpeechLead(text.substring(cursor, q.start));
      _appendNarration(lead, segments, knownGenders: knownGenders);
    }
    // 引号内容：用 cue 判角色。
    final role = _detectRole(text, q.windowStart, q.start, q.content);
    segments.add(SpeechSegment(
      text: q.content,
      role: role,
      sourceRole: role,
      gender: _detectGender(
        window: text.substring(q.windowStart, q.start),
        role: role,
        knownGenders: knownGenders,
      ),
    ));
    cursor = q.end;
  }
  if (cursor < text.length) {
    _appendNarration(text.substring(cursor), segments,
        knownGenders: knownGenders);
  }
  return segments;
}

/// 剥离旁白文本段尾的「说话人 + 冒号」发言引导语（如 `李四喊：`），
/// 仅当段尾命中 cue 词 + 冒号时剥掉；其余原样返回。
String _stripSpeechLead(String s) {
  final trimmed = s.trimRight();
  if (trimmed.isEmpty) return '';
  // 段尾匹配：[说话人 cue]+[：:]，说话人限 ≤12 字符。
  final match = RegExp(
          r'((?:[^。！？；：:]{0,12})(?:说道|说道|说|问道|问|答道|答|心想|想|喊道|喊|叫道|叫|笑道|道|忙道|低声|大声|沉声|冷声|叹道|喃喃道|低声道)[：:])\s*$')
      .firstMatch(trimmed);
  if (match == null) return trimmed;
  return trimmed.substring(0, match.start).trimRight();
}

/// 从开口引号前的窗口文本中匹配 cue，返回说话人角色名。
///
/// 匹配策略：窗口内找最后一个 cue 词，其前面（≤14 字符内）的连续非标点
/// 子串视为说话人；找不到 cue 返回 [quoteRole]。
String _detectRole(String full, int windowStart, int quoteStart, String content) {
  final window = full.substring(windowStart, quoteStart);
  // 找 cue 词在窗口中的最后出现（最靠近引号）。
  var bestCue = -1;
  var bestRoleCandidate = '';
  for (final cue in kSpeechCueWords) {
    final idx = window.lastIndexOf(cue);
    if (idx < 0) continue;
    // 说/问/想 等单字 cue 太宽泛：要求前面紧跟人名词或后跟冒号，
    // 否则跳过（避免把「不知道说什么」误判）。
    final before = window.substring(0, idx);
    // 提取说话人：cue 前最近的连续汉字/字母串。
    final candidate = _extractSpeaker(before);
    if (candidate.isEmpty) continue;
    if (idx > bestCue) {
      bestCue = idx;
      bestRoleCandidate = candidate;
    }
  }
  if (bestRoleCandidate.isNotEmpty) return bestRoleCandidate;
  // 冒号句式：`XX：` / `XX:` 直接前置人名。
  final colon = window.lastIndexOf('：');
  if (colon > 0) {
    final speaker = _extractSpeaker(window.substring(0, colon));
    if (speaker.isNotEmpty) return speaker;
  }
  return quoteRole;
}

/// 提取字符串末尾的连续说话人（汉字/字母/数字，长度 ≤ 12）。
String _extractSpeaker(String s) {
  var end = s.length;
  while (end > 0 && _isNameChar(s[end - 1])) {
    end--;
  }
  // 去掉紧邻的连接词（如「只见」「就听」）——简单起见保留最近 12 字符。
  final name = s.substring(end).trim();
  if (name.isEmpty || name.length > 12) {
    // 超长视为未命名词。
    if (name.length > 12) return '';
    return '';
  }
  return name;
}

bool _isNameChar(String c) {
  final code = c.codeUnitAt(0);
  // 中文字符范围（含扩展区常见字）+ ascii 字母数字。
  return (code >= 0x4E00 && code <= 0x9FFF) ||
      (code >= 0x3400 && code <= 0x4DBF) ||
      (c.codeUnits.length > 0 && RegExp(r'[A-Za-z0-9]').hasMatch(c)) ||
      (c == '·');
}

/// 旁白切句：按结束标点切短句。句首若命中「角色 + 冒号」句式
/// （如 `他说：xxx` / `小王心想：xxx`），以冒号前文本为角色、冒号后为
/// 内容切分（无引号句式也支持角色判定）。
void _appendNarration(String text, List<SpeechSegment> out,
    {Map<String, String> knownGenders = const <String, String>{}}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return;
  var start = 0;
  for (var i = 0; i < trimmed.length; i++) {
    if (kSentencePunctuation.contains(trimmed[i])) {
      _appendNarrationSentence(trimmed.substring(start, i + 1), out,
          knownGenders: knownGenders);
      start = i + 1;
    }
  }
  if (start < trimmed.length) {
    _appendNarrationSentence(trimmed.substring(start), out,
        knownGenders: knownGenders);
  }
}

/// 追加一条旁白句（或拆为角色+内容）。
void _appendNarrationSentence(String raw, List<SpeechSegment> out,
    {Map<String, String> knownGenders = const <String, String>{}}) {
  final s = raw.trim();
  if (s.isEmpty) return;
  // 冒号句式：[说话人][：:][内容]。说话人限 ≤12 字符、不含标点。
  final colon = s.indexOf(RegExp(r'[：:]'));
  if (colon > 0 && colon <= 12) {
    final maybeRole = s.substring(0, colon).trimRight();
    final content = s.substring(colon + 1).trim();
    if (maybeRole.isNotEmpty && content.isNotEmpty) {
      final role = _stripCueSuffix(maybeRole);
      // 必须真的剥掉了「说话 cue」才算「角色 + 内容」句式。
      // 否则普通句子里的冒号（如「他抬头看了看：天色不早了」）会被当成
      // 说话人前缀，冒号前的整段文字被吞掉——听感就是「每段开头缺字」。
      final bool hadCue = role != maybeRole.trim();
      // 角色名限 4 字以内：「老王叹了口气说：」这类是「动作 + 说」，
      // 若当成角色名会把「叹了口气」整段吞掉，宁可整句按旁白读。
      if (role.isNotEmpty && hadCue && role.length <= 4) {
        out.add(SpeechSegment(
          text: content,
          role: role,
          sourceRole: role,
          gender: _detectGender(
            window: s.substring(0, colon),
            role: role,
            knownGenders: knownGenders,
          ),
        ));
        return;
      }
    }
  }
  out.add(SpeechSegment(
    text: s,
    role: narratorRole,
    sourceRole: narratorRole,
  ));
}

/// 推断说话人性别。
///
/// 优先级：角色卡已知性别（[knownGenders]）> cue 窗口「她/他 + 动词」
/// 代词句式 > 说话人名内的称谓词 > 窗口文本内的称谓词。全部未命中
/// 返回 [SpeechGender.unknown]（路由层走默认/性别槽兜底）。
String _detectGender({
  required String window,
  required String role,
  required Map<String, String> knownGenders,
}) {
  // 1) 角色卡已知性别（名字精确命中）。
  final known = knownGenders[role.trim()];
  if (known == SpeechGender.male) return SpeechGender.male;
  if (known == SpeechGender.female) return SpeechGender.female;
  // 2) 代词句式：紧邻引号前出现「她/他 + cue 动词」。
  final pronounCue =
      RegExp('(她|他)([^。！？；，,]{0,6})($cueAlternation)[：:]?\$');
  final m = pronounCue.firstMatch(window.trimRight());
  if (m != null) {
    return m.group(1) == '她' ? SpeechGender.female : SpeechGender.male;
  }
  // 3) 说话人名本身是称谓（「姑娘」「公子」等）。
  final byRole = _genderByAddressTerms(role);
  if (byRole != SpeechGender.unknown) return byRole;
  // 4) cue 窗口内的称谓（「那位姑娘说道：」）。
  return _genderByAddressTerms(window);
}

/// 称谓词表判性别；未命中返回 unknown。
String _genderByAddressTerms(String text) {
  var female = false;
  var male = false;
  for (final t in kFemaleAddressTerms) {
    if (text.contains(t)) {
      female = true;
      break;
    }
  }
  for (final t in kMaleAddressTerms) {
    if (text.contains(t)) {
      male = true;
      break;
    }
  }
  // 两性称谓同时命中视为不可判（如「姐弟」）。
  if (female == male) return SpeechGender.unknown;
  return female ? SpeechGender.female : SpeechGender.male;
}

/// 去除说话人候选末尾的 cue 动词词尾（「说道/问/喊/心想」等），
/// 保留纯人名。按词长优先匹配（避免「说道」被「说」提前截断）。
String _stripCueSuffix(String candidate) {
  var name = candidate.trim();
  // 按长度降序尝试 cue 词尾。
  final cues = [...kSpeechCueWords]..sort((a, b) => b.length.compareTo(a.length));
  for (final cue in cues) {
    if (name.endsWith(cue)) {
      name = name.substring(0, name.length - cue.length).trim();
      break;
    }
  }
  return name;
}