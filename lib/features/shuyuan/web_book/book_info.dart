/// 书籍详情解析：依据书源 `ruleBookInfo` 解析书名/作者/简介/封面/目录 URL 等字段。
library;

import '../model/book_source.dart';
import '../model/xiaoshuo_book.dart';
import '../analyze/analyze_rule.dart';
import '../analyze/html_formatter.dart';
import '../analyze/source_context.dart';
import '../analyze/string_utils.dart';
import '../../../core/utils/app_log.dart';

class BookInfo {
  static void analyzeBookInfo({
    required XiaoshuoBookSource bookSource,
    required XiaoshuoBook book,
    required String baseUrl,
    required String? redirectUrl,
    required String body,
    bool canReName = true,
  }) {
    // 变量贯通：注入搜索/发现阶段暂存的本书变量（gid/nid 等），
    // 详情规则里的 @get / tocUrl 模板求值才能取到。
    final stageVars = ShuyuanSourceContext.current?.bookItemVars[book.bookUrl];
    if (stageVars != null && stageVars.isNotEmpty) {
      book.variableMap.addAll(stageVars);
    }
    final bookInfoRule = bookSource.getBookInfoRule();
    final analyzeRule = AnalyzeRule(book: book)
      ..setContent(body, baseUrl)
      ..setBaseUrl(baseUrl)
      ..setRedirectUrl(redirectUrl ?? baseUrl);

    if (bookInfoRule.init != null && bookInfoRule.init!.isNotEmpty) {
      try {
        final initContent = analyzeRule.getElement(bookInfoRule.init!);
        if (initContent != null) {
          analyzeRule.setContent(initContent);
          AppLog.instance
              .d('[书源详情] init规则命中: ${initContent.toString().length}字符');
        } else {
          AppLog.instance.w('[书源详情] init规则未命中: ${bookInfoRule.init}');
        }
      } catch (e) {
        AppLog.instance.w('[书源详情] init规则异常: ${bookInfoRule.init} → $e');
      }
    }

    // 对照 legado BookInfo：仅当书源声明了 ruleBookInfo.canReName 时才允许
    // 覆盖已有书名/作者（旧实现取反：规则为空反而允许覆盖）。
    final canReNameFlag =
        canReName && (bookInfoRule.canReName?.isNotEmpty ?? false);

    if (bookInfoRule.name != null && bookInfoRule.name!.isNotEmpty) {
      try {
        final name = _formatBookName(analyzeRule.getString(bookInfoRule.name!));
        if (name.isNotEmpty && (canReNameFlag || book.name.isEmpty)) {
          book.name = name;
        }
      } catch (_) {}
    }

    if (bookInfoRule.author != null && bookInfoRule.author!.isNotEmpty) {
      try {
        final author = _formatBookAuthor(analyzeRule.getString(bookInfoRule.author!));
        if (author.isNotEmpty && (canReNameFlag || book.author.isEmpty)) {
          book.author = author;
        }
      } catch (_) {}
    }

    if (bookInfoRule.kind != null && bookInfoRule.kind!.isNotEmpty) {
      try {
        final kinds = analyzeRule.getStringList(bookInfoRule.kind!);
        if (kinds.isNotEmpty) {
          book.kind = kinds.join(',');
          if (book.kind!.length > 1000) book.kind = book.kind!.substring(0, 1000);
        }
      } catch (_) {}
    }

    if (bookInfoRule.lastChapter != null && bookInfoRule.lastChapter!.isNotEmpty) {
      try {
        final lastChapter = analyzeRule.getString(bookInfoRule.lastChapter!);
        if (lastChapter.isNotEmpty) {
          book.lastChapter = lastChapter;
        }
      } catch (_) {}
    }

    if (bookInfoRule.intro != null && bookInfoRule.intro!.isNotEmpty) {
      try {
        // legado BookInfo：带渲染指令前缀（<usehtml>/<md>/<useweb>）的简介
        // 原样保留（源作者用其承载交互标记），其余经 HtmlFormatter 转纯文本
        // 并截断 5000；旧实现直接把 HTML 塞给 UI。
        final intro = analyzeRule.getString(bookInfoRule.intro!);
        final introTrim = intro.trimLeft();
        if (introTrim.startsWith('<usehtml>') ||
            introTrim.startsWith('<md>') ||
            introTrim.startsWith('<useweb>')) {
          book.intro = introTrim;
        } else {
          final formatted = HtmlFormatter.formatIntro(introTrim);
          if (formatted.isNotEmpty) book.intro = formatted;
        }
      } catch (_) {}
    }

    if (bookInfoRule.bookStatus != null && bookInfoRule.bookStatus!.isNotEmpty) {
      try {
        final bookStatus = analyzeRule.getString(bookInfoRule.bookStatus!);
        if (bookStatus.isNotEmpty) {
          book.bookStatus = bookStatus;
        }
      } catch (_) {}
    }

    if (bookInfoRule.updateTime != null && bookInfoRule.updateTime!.isNotEmpty) {
      try {
        final updateTime = analyzeRule.getString(bookInfoRule.updateTime!);
        if (updateTime.isNotEmpty) {
          book.updateTime = updateTime;
        }
      } catch (_) {}
    }

    if (bookInfoRule.wordCount != null && bookInfoRule.wordCount!.isNotEmpty) {
      try {
        // legado BookInfo：wordCountFormat 归一（12000 → 1.2万字）。
        final wordCount =
            StringUtils.wordCountFormat(analyzeRule.getString(bookInfoRule.wordCount!));
        if (wordCount.isNotEmpty) {
          book.wordCount = wordCount;
        }
      } catch (_) {}
    }

    if (bookInfoRule.recommendations != null &&
        bookInfoRule.recommendations!.isNotEmpty) {
      try {
        final recommendations =
            analyzeRule.getStringList(bookInfoRule.recommendations!);
        if (recommendations.isNotEmpty) {
          book.recommendations = recommendations
              .where((s) => s.trim().isNotEmpty)
              .map((s) => s.trim())
              .toList();
        }
      } catch (_) {}
    }

    if (bookInfoRule.coverUrl != null && bookInfoRule.coverUrl!.isNotEmpty) {
      try {
        // 对照 legado BookInfo：封面规则**不带** isUrl（isUrl 对空结果会
        // 回退成 baseUrl，凭空造出假封面）；只在命中非空时按 redirectUrl
        // 拼绝对地址，保留源站返回的相对路径/协议相对地址。
        final rawCover = analyzeRule.getString(bookInfoRule.coverUrl!).trim();
        if (rawCover.isNotEmpty) {
          book.coverUrl = AnalyzeRule.absoluteUrl(redirectUrl ?? baseUrl, rawCover);
        }
      } catch (_) {}
    }

    if (bookInfoRule.tocUrl != null && bookInfoRule.tocUrl!.isNotEmpty) {
      try {
        final tocUrl = analyzeRule.getString(bookInfoRule.tocUrl!, isUrl: true);
        if (tocUrl.isNotEmpty) {
          book.tocUrl = tocUrl;
        }
      } catch (_) {}
    }

    // 对照 legado BookInfo：目录地址回落到详情页**原始** URL（baseUrl）；
    // 回落到详情页自身时，详情响应体即目录页 HTML，缓存进 tocHtml 供目录
    // 阶段直接解析（省一次请求，也覆盖详情页只有一次性 Cookie/签名的站点）。
    if (book.tocUrl == null || book.tocUrl!.isEmpty) {
      book.tocUrl = baseUrl;
    }
    if (book.tocUrl == baseUrl) {
      book.tocHtml = body;
    }

    // 变量回写：详情规则新 @put/java.put 的变量并入暂存，供目录/正文
    // 阶段继续读取。
    final ctx = ShuyuanSourceContext.current;
    if (ctx != null && book.bookUrl.isNotEmpty &&
        analyzeRule.variables.isNotEmpty) {
      ctx.bookItemVars[book.bookUrl] =
          Map<String, String>.from(analyzeRule.variables);
    }

    // 汇总日志：书名/作者/简介/封面/目录URL 最终结果（便于真机排查
    // 「详情页解析不全」——哪一项为空一目了然）。
    AppLog.instance.d('[书源详情] 源=${bookSource.bookSourceName} '
        '书名=${book.name.isEmpty ? '(空)' : book.name} '
        '作者=${book.author.isEmpty ? '(空)' : book.author} '
        '简介=${(book.intro ?? '').length}字符 '
        '封面=${(book.coverUrl ?? '').isEmpty ? '(空)' : book.coverUrl} '
        'toc=${(book.tocUrl ?? '').isEmpty ? '(空)' : book.tocUrl}');
  }

  // legado AppPattern.nameRegex/authorRegex 的 Java `\s` 语义：只含
  // 半角空白（Dart `\s` 额外含 U+3000，直接用会多删全角空格内容）。
  static final RegExp _nameRegex = RegExp(
      r'[ \t\n\x0B\f\r]+作[ \t\n\x0B\f\r]*者[\s\S]*|'
      r'[ \t\n\x0B\f\r]+[^ \t\n\x0B\f\r]+[ \t\n\x0B\f\r]+著');
  static final RegExp _authorRegex = RegExp(
      r'^[ \t\n\x0B\f\r]*作[ \t\n\x0B\f\r]*者[:： \t\n\x0B\f\r]+|'
      r'[ \t\n\x0B\f\r]+著');

  /// legado `BookHelp.formatBookName`：仅剥离作者尾巴，再按
  /// `trim { it <= ' ' }`（ASCII 空白）修剪，保留全角空格。
  static String _formatBookName(String name) {
    if (name.isEmpty) return name;
    return _trimAscii(name.replaceAll(_nameRegex, ''));
  }

  /// legado `BookHelp.formatBookAuthor`。
  static String _formatBookAuthor(String author) {
    if (author.isEmpty) return author;
    return _trimAscii(author.replaceAll(_authorRegex, ''));
  }

  static String _trimAscii(String s) {
    var start = 0;
    var end = s.length;
    while (start < end && s.codeUnitAt(start) <= 0x20) {
      start++;
    }
    while (end > start && s.codeUnitAt(end - 1) <= 0x20) {
      end--;
    }
    return s.substring(start, end);
  }
}
