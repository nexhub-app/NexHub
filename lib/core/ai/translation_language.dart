/// 语言码归一与同语言启发式判定（Bing 免费翻译链路共用）。
library;

import 'dart:ui' show Locale;

/// 语言工具：常见语言名/码 → Bing 码，以及脚本占比判定。
abstract final class TranslationLanguage {
  /// Bing 支持且应用常见的语言码（小写比较）。
  static const Set<String> _bingCodes = <String>{
    'ar', 'bg', 'ca', 'cs', 'da', 'de', 'el', 'en', 'es', 'et', 'fa', 'fi',
    'fr', 'he', 'hi', 'hr', 'hu', 'id', 'it', 'ja', 'ko', 'lt', 'lv', 'ms',
    'nl', 'no', 'pl', 'pt', 'ro', 'ru', 'sk', 'sl', 'sr', 'sv', 'th', 'tr',
    'uk', 'vi', 'zh-Hans', 'zh-Hant',
  };

  static const Map<String, String> _names = <String, String>{
    '中文': 'zh-Hans',
    '简体中文': 'zh-Hans',
    '中文（简体）': 'zh-Hans',
    '中文(简体)': 'zh-Hans',
    '汉语': 'zh-Hans',
    '中文简体': 'zh-Hans',
    'simplified chinese': 'zh-Hans',
    '繁体中文': 'zh-Hant',
    '繁體中文': 'zh-Hant',
    '中文（繁體）': 'zh-Hant',
    '中文(繁體)': 'zh-Hant',
    '中文（繁体）': 'zh-Hant',
    'traditional chinese': 'zh-Hant',
    '英文': 'en',
    '英语': 'en',
    'english': 'en',
    '日文': 'ja',
    '日语': 'ja',
    '日語': 'ja',
    '日本語': 'ja',
    'japanese': 'ja',
    '韩文': 'ko',
    '韩语': 'ko',
    '韓語': 'ko',
    '한국어': 'ko',
    'korean': 'ko',
    '俄文': 'ru',
    '俄语': 'ru',
    'русский': 'ru',
    'russian': 'ru',
    '阿拉伯语': 'ar',
    '阿拉伯語': 'ar',
    'arabic': 'ar',
    '泰文': 'th',
    '泰语': 'th',
    'ไทย': 'th',
    'thai': 'th',
    '法文': 'fr',
    '法语': 'fr',
    'français': 'fr',
    'french': 'fr',
    '德文': 'de',
    '德语': 'de',
    'deutsch': 'de',
    'german': 'de',
    '西班牙语': 'es',
    '西班牙語': 'es',
    'español': 'es',
    'spanish': 'es',
    '葡萄牙语': 'pt',
    '葡萄牙語': 'pt',
    'português': 'pt',
    'portuguese': 'pt',
    '意大利语': 'it',
    '義大利語': 'it',
    'italiano': 'it',
    'italian': 'it',
    '越南语': 'vi',
    '越南語': 'vi',
    'tiếng việt': 'vi',
    'vietnamese': 'vi',
    '印尼语': 'id',
    '印尼語': 'id',
    'indonesian': 'id',
    '土耳其语': 'tr',
    '土耳其語': 'tr',
    'turkish': 'tr',
    '印地语': 'hi',
    '印地語': 'hi',
    'hindi': 'hi',
  };

  static final RegExp _urlPattern = RegExp(r'https?://\S+');
  static final RegExp _han = RegExp(r'[\u3400-\u4dbf\u4e00-\u9fff]');
  static final RegExp _kana = RegExp(r'[\u3040-\u30ff]');
  static final RegExp _hangul = RegExp(r'[\u1100-\u11ff\uac00-\ud7af]');
  static final RegExp _latin = RegExp(r'[A-Za-z]');

  /// 英文单词（≥2 个字母，避免把 "a" / 单个字母算作外文片段）。
  static final RegExp _latinWord = RegExp(r"[A-Za-z][A-Za-z'’-]+");
  static final RegExp _cyrillic = RegExp(r'[\u0400-\u04ff]');
  static final RegExp _arabic = RegExp(r'[\u0600-\u06ff]');
  static final RegExp _thai = RegExp(r'[\u0e00-\u0e7f]');
  static final RegExp _englishStopword = RegExp(
    r"\b(the|a|an|and|or|of|to|in|is|are|was|were|be|been|it|this|that|with|"
    r"for|on|as|at|by|from|you|your|we|our|they|their|he|she|his|her|i|my|"
    r"not|but|have|has|had|will|would|can|could|should|do|does|did|what|"
    r"which|who|how|why|when|where)\b",
    caseSensitive: false,
  );

  /// 用户填写的目标语言 / 语言码 → Bing 码；无法映射返回 null。
  static String? bingCode(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final lower = s.toLowerCase().replaceAll('_', '-');
    final named = _names[lower];
    if (named != null) return named;
    if (lower == 'zh' ||
        lower == 'zh-hans' ||
        lower == 'zh-cn' ||
        lower == 'zh-sg' ||
        lower == 'chs') {
      return 'zh-Hans';
    }
    if (lower == 'zh-hant' ||
        lower == 'zh-tw' ||
        lower == 'zh-hk' ||
        lower == 'zh-mo' ||
        lower == 'cht') {
      return 'zh-Hant';
    }
    if (lower.startsWith('zh')) {
      return lower.contains('hant') ||
              lower.contains('tw') ||
              lower.contains('hk') ||
              lower.contains('mo')
          ? 'zh-Hant'
          : 'zh-Hans';
    }
    final base = lower.split('-').first;
    for (final code in _bingCodes) {
      final c = code.toLowerCase();
      if (c == lower || c == base) return code;
    }
    return null;
  }

  /// 当前界面 Locale 的默认目标语言。
  static String preferredCodeForLocale(Locale locale) {
    final lang = locale.languageCode.toLowerCase();
    if (lang == 'zh') {
      final script = locale.scriptCode?.toLowerCase();
      final country = locale.countryCode?.toUpperCase();
      if (script == 'hant' ||
          country == 'TW' ||
          country == 'HK' ||
          country == 'MO') {
        return 'zh-Hant';
      }
      return 'zh-Hans';
    }
    return bingCode(lang) ?? 'en';
  }

  /// AI 提示词使用的可读语言名。
  static String readableName(String raw) {
    final code = bingCode(raw);
    return switch (code) {
      'zh-Hans' => '中文（简体）',
      'zh-Hant' => '中文（繁體）',
      'en' => '英文',
      'ja' => '日文',
      'ko' => '韩文',
      'ru' => '俄文',
      'ar' => '阿拉伯语',
      'th' => '泰语',
      'fr' => '法文',
      'de' => '德文',
      'es' => '西班牙语',
      'pt' => '葡萄牙语',
      'it' => '意大利语',
      'vi' => '越南语',
      'id' => '印尼语',
      'tr' => '土耳其语',
      'hi' => '印地语',
      _ => raw.trim().isEmpty ? '英文' : raw.trim(),
    };
  }

  /// 文本是否值得翻译：同语言、纯数字、URL、空串返回 false。
  ///
  /// 判定按「主导脚本」而不是「有没有目标语言字符」：中文标题里夹一句英文
  /// （中英混杂）过去会被当成「已是中文」整体跳过，现在只有真正纯中文才跳过。
  static bool shouldTranslate(String text, String target) {
    final cleaned = text.replaceAll(_urlPattern, '').trim();
    if (cleaned.isEmpty) return false;
    final code = bingCode(target) ?? target.trim().toLowerCase();
    final han = _count(cleaned, _han);
    final kana = _count(cleaned, _kana);
    final hangul = _count(cleaned, _hangul);
    final latin = _count(cleaned, _latin);
    final cyrillic = _count(cleaned, _cyrillic);
    final arabic = _count(cleaned, _arabic);
    final thai = _count(cleaned, _thai);
    final total = han + kana + hangul + latin + cyrillic + arabic + thai;
    if (total == 0) return false;
    double ratio(int n) => n / total;
    switch (code) {
      case 'zh-Hans':
      case 'zh-Hant':
        if (ratio(han) < 0.3) return true;
        // 中文主导：混排（中英 / 中日 / 中韩）仍需翻译，纯中文才跳过。
        return isMixedLanguage(text, target);
      case 'ja':
        if (kana == 0) return true;
        return isMixedLanguage(text, target);
      case 'ko':
        if (ratio(hangul) < 0.3) return true;
        return isMixedLanguage(text, target);
      case 'en':
        if (ratio(latin) >= 0.7 && _englishStopword.hasMatch(cleaned)) {
          // 英文明主导但混入成串中文（中英混杂）时仍需翻译。
          return isMixedLanguage(text, target);
        }
        return true;
      case 'ru':
        return ratio(cyrillic) < 0.5;
      case 'ar':
        return ratio(arabic) < 0.5;
      case 'th':
        return ratio(thai) < 0.5;
      default:
        return true;
    }
  }

  /// 目标语言之外是否夹带「成句的双语片段」。
  ///
  /// 只看「有没有外文字符」会误伤（中文标题带一个英文型号名并不需要翻译），
  /// 因此要求外文构成至少两个单词或两字假名/谚文，且字符占比达到下限。
  static bool isMixedLanguage(String text, String target) {
    final cleaned = text.replaceAll(_urlPattern, '').trim();
    if (cleaned.isEmpty) return false;
    final code = bingCode(target) ?? target.trim().toLowerCase();
    final han = _count(cleaned, _han);
    final kana = _count(cleaned, _kana);
    final hangul = _count(cleaned, _hangul);
    final latin = _count(cleaned, _latin);
    final cyrillic = _count(cleaned, _cyrillic);
    final arabic = _count(cleaned, _arabic);
    final thai = _count(cleaned, _thai);
    final total = han + kana + hangul + latin + cyrillic + arabic + thai;
    if (total == 0) return false;
    double share(int n) => n / total;
    final cjk = han + kana + hangul;
    final latinWords = _count(cleaned, _latinWord);
    switch (code) {
      case 'zh-Hans':
      case 'zh-Hant':
        // 没有中文的纯外文不算「混杂」，走 shouldTranslate 的常规占比判定。
        if (han < 2) return false;
        if (kana >= 2 || hangul >= 2) return true;
        return latinWords >= 2 && share(latin) >= 0.25;
      case 'en':
        return latinWords >= 1 && cjk >= 2 && share(cjk) >= 0.15;
      case 'ja':
        return kana >= 1 && latinWords >= 2 && share(latin) >= 0.25;
      case 'ko':
        return hangul >= 2 && latinWords >= 2 && share(latin) >= 0.25;
      default:
        return false;
    }
  }

  /// 混杂文本里占据主要地位的外文语言码（供翻译端点显式指定源语言用）。
  ///
  /// 中英混杂的标题会被翻译端点判为「已是目标语言」而原样回显，显式给出
  /// `from` 才能让它把外文片段真正译出来。无法判定时返回 null。
  static String? foreignSourceCode(String text, String target) {
    final cleaned = text.replaceAll(_urlPattern, '').trim();
    if (cleaned.isEmpty) return null;
    final code = bingCode(target) ?? target.trim().toLowerCase();
    final kana = _count(cleaned, _kana);
    final hangul = _count(cleaned, _hangul);
    final han = _count(cleaned, _han);
    final latinWords = _count(cleaned, _latinWord);
    switch (code) {
      case 'zh-Hans':
      case 'zh-Hant':
        if (kana >= 2) return 'ja';
        if (hangul >= 2) return 'ko';
        if (latinWords >= 2) return 'en';
        return null;
      case 'en':
        if (kana >= 2) return 'ja';
        if (hangul >= 2) return 'ko';
        if (han >= 2) return 'zh-Hans';
        return null;
      case 'ja':
      case 'ko':
        return latinWords >= 2 ? 'en' : null;
      default:
        return null;
    }
  }

  static int _count(String text, RegExp pattern) =>
      pattern.allMatches(text).length;
}
