import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/ai/translation_language.dart';

void main() {
  test('常见目标语言映射到 Bing 语言码', () {
    expect(TranslationLanguage.bingCode('中文'), 'zh-Hans');
    expect(TranslationLanguage.bingCode('简体中文'), 'zh-Hans');
    expect(TranslationLanguage.bingCode('繁體中文'), 'zh-Hant');
    expect(TranslationLanguage.bingCode('English'), 'en');
    expect(TranslationLanguage.bingCode('日语'), 'ja');
    expect(TranslationLanguage.bingCode('한국어'), 'ko');
    expect(TranslationLanguage.bingCode('zh-TW'), 'zh-Hant');
    expect(TranslationLanguage.bingCode('fr'), 'fr');
    expect(TranslationLanguage.bingCode('未知语言'), isNull);
  });

  test('界面 Locale 映射', () {
    expect(TranslationLanguage.preferredCodeForLocale(const Locale('zh')),
        'zh-Hans');
    expect(
      TranslationLanguage.preferredCodeForLocale(const Locale('zh', 'TW')),
      'zh-Hant',
    );
    expect(TranslationLanguage.preferredCodeForLocale(const Locale('en')), 'en');
    expect(TranslationLanguage.preferredCodeForLocale(const Locale('ja')), 'ja');
  });

  test('同语言启发式跳过', () {
    expect(TranslationLanguage.shouldTranslate('这是中文标题', '中文'), isFalse);
    expect(TranslationLanguage.shouldTranslate('これは日本語です', '中文'), isTrue);
    expect(TranslationLanguage.shouldTranslate('これは日本語です', '日语'), isFalse);
    expect(TranslationLanguage.shouldTranslate('안녕하세요', '韩语'), isFalse);
    expect(
      TranslationLanguage.shouldTranslate(
          'Hello world, this is a test', 'English'),
      isFalse,
    );
    expect(
      TranslationLanguage.shouldTranslate(
          'Hello world, this is a test', '中文'),
      isTrue,
    );
    expect(TranslationLanguage.shouldTranslate('Привет мир', '俄语'), isFalse);
    expect(TranslationLanguage.shouldTranslate('مرحبا بالعالم', '阿拉伯语'), isFalse);
    expect(TranslationLanguage.shouldTranslate('สวัสดีชาวโลก', '泰语'), isFalse);
  });

  test('纯数字 / URL / 空串不翻译', () {
    expect(TranslationLanguage.shouldTranslate('12345', '中文'), isFalse);
    expect(
      TranslationLanguage.shouldTranslate('https://example.com/a', '中文'),
      isFalse,
    );
    expect(TranslationLanguage.shouldTranslate('   ', '中文'), isFalse);
  });

  test('可读语言名用于 AI 提示词', () {
    expect(TranslationLanguage.readableName('zh-Hans'), '中文（简体）');
    expect(TranslationLanguage.readableName('en'), '英文');
  });

  test('中英混杂文本仍然翻译', () {
    expect(
      TranslationLanguage.shouldTranslate('进击的巨人 Attack on Titan', '中文'),
      isTrue,
    );
    expect(
      TranslationLanguage.shouldTranslate('名侦探柯南 Detective Conan', '中文'),
      isTrue,
    );
    expect(
      TranslationLanguage.shouldTranslate('海贼王 The Movie', 'English'),
      isTrue,
    );
    expect(TranslationLanguage.isMixedLanguage('进击的巨人 Attack on Titan', '中文'),
        isTrue);
    expect(TranslationLanguage.isMixedLanguage('海贼王 The Movie', 'English'), isTrue);
  });

  test('混入零散外文不算混杂，避免无谓翻译', () {
    // 纯中文标题：不带外文、只带型号缩写与数字。
    expect(TranslationLanguage.shouldTranslate('这是中文标题', '中文'), isFalse);
    expect(TranslationLanguage.shouldTranslate('第 12 集 全 24 集', '中文'),
        isFalse);
    expect(TranslationLanguage.shouldTranslate('由 MAPPA 制作', '中文'), isFalse);
    expect(TranslationLanguage.isMixedLanguage('这是中文标题', '中文'), isFalse);
    // 纯外文（无中文）不是「混杂」，走常规占比判定。
    expect(TranslationLanguage.isMixedLanguage('Hello world', '中文'), isFalse);
  });

  test('混杂文本可给出外文源语言码', () {
    expect(
      TranslationLanguage.foreignSourceCode('进击的巨人 Attack on Titan', '中文'),
      'en',
    );
    expect(
      TranslationLanguage.foreignSourceCode('海贼王 One Piece', 'English'),
      'zh-Hans',
    );
    expect(TranslationLanguage.foreignSourceCode('这是中文标题', '中文'), isNull);
  });

  test('标签里单个英文词也判为混排', () {
    // 标签是短语：一个成词英文就够，不必等两个英文单词。
    expect(
      TranslationLanguage.shouldTranslate('奇幻 Fantasy', '中文', label: true),
      isTrue,
    );
    expect(
      TranslationLanguage.shouldTranslate('校园生活 School', '中文', label: true),
      isTrue,
    );
    expect(
      TranslationLanguage.isMixedLanguage('奇幻 Fantasy', '中文', label: true),
      isTrue,
    );
    expect(
      TranslationLanguage.foreignSourceCode('奇幻 Fantasy', '中文', label: true),
      'en',
    );
    // 正文（非标签）保持严格阈值，避免中文标题被无谓翻译。
    expect(TranslationLanguage.isMixedLanguage('奇幻 Fantasy', '中文'), isFalse);
    expect(
      TranslationLanguage.shouldTranslate('校园生活 School', '中文'),
      isFalse,
    );
    expect(TranslationLanguage.foreignSourceCode('奇幻 Fantasy', '中文'), isNull);
  });

  test('纯大写短缩写的标签不触发翻译', () {
    for (final tag in <String>['画师CG', 'TV番剧', 'AI解码', 'TL 百合', 'JM 主站']) {
      expect(
        TranslationLanguage.shouldTranslate(tag, '中文', label: true),
        isFalse,
        reason: tag,
      );
    }
    expect(TranslationLanguage.hasTranslatableLatinWord('画师CG'), isFalse);
    expect(TranslationLanguage.hasTranslatableLatinWord('奇幻 Fantasy'), isTrue);
    expect(TranslationLanguage.hasTranslatableLatinWord('非H'), isFalse);
  });
}
