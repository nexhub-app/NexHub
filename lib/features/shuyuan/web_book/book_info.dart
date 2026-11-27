/// 书籍详情解析：依据书源 `ruleBookInfo` 解析书名/作者/简介/封面/目录 URL 等字段。
library;

import '../model/book_source.dart';
import '../model/xiaoshuo_book.dart';
import '../analyze/analyze_rule.dart';
import '../analyze/html_formatter.dart';
import '../analyze/source_context.dart';
import '../analyze/string_utils.dart';
import '../../../core/scraper/verification_detector.dart'
    show SourceResolveException;
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
      // legado `BookInfo`：init 是详情解析的**强制前置**——`setContent(
      // getElement(init))` 在未命中时由 `AnalyzeRule.setContent` 断言失败。
      // 旧实现未命中/异常只记日志并保留整页，会在错误 DOM 上产出伪书名、
      // 伪简介与错误 tocUrl，调用方却拿到「成功」。
      final initContent = analyzeRule.getElement(bookInfoRule.init!);
      if (initContent == null) {
        throw SourceResolveException(
          sourceId: bookSource.bookSourceUrl,
          apiName: 'bookInfo.init',
          message: '详情 init 规则未命中：${bookInfoRule.init}',
        );
      }
      analyzeRule.setContent(initContent);
      AppLog.instance
          .d('[书源详情] init规则命中: ${initContent.toString().length}字符');
    }

    // 对照 legado BookInfo：仅当书源声明了 ruleBookInfo.canReName 时才允许
    // 覆盖已有书名/作者（旧实现取反：规则为空反而允许覆盖）。
    final canReNameFlag =
        canReName && (bookInfoRule.canReName?.isNotEmpty ?? false);

    if (bookInfoRule.name != null && bookInfoRule.name!.isNotEmpty) {
      // legado BookInfo.getName：name 规则**不包 try/catch**——脚本异常令
      // 整次详情解析失败，不能吞成「成功但缺书名」。
      final name =
          StringUtils.formatBookName(analyzeRule.getString(bookInfoRule.name!));
      if (name.isNotEmpty && (canReNameFlag || book.name.isEmpty)) {
        book.name = name;
      }
    }

    if (bookInfoRule.author != null && bookInfoRule.author!.isNotEmpty) {
      // 同 name：author 规则异常向上传播（legado 同口径）。
      final author = StringUtils.formatBookAuthor(
          analyzeRule.getString(bookInfoRule.author!));
      if (author.isNotEmpty && (canReNameFlag || book.author.isEmpty)) {
        book.author = author;
      }
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

    // 求值顺序对齐 legado BookInfo：分类 → 字数 → 最新章节 → 简介 → 封面。
    // 详情规则常以 @put/@get 串联字段，先后顺序决定谁能读到谁的中间变量。
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

    // 对照 legado BookInfo：文件类书源没有目录，详情阶段解析下载地址列表；
    // 为空直接失败（md3 抛「下载链接为空」），否则用户会看到一个没有任何
    // 可读文件的详情页。
    //
    // 判据用 `Book.isWebFile`（BookType 位掩码 128，可与 text 位并存），
    // 旧实现只看 `bookSourceType == 3`：组合类型（如 text|webFile）或书对象
    // 的 type 被改过时会走错分支（下载链接 vs 目录）。
    final bool isWebFile =
        book.isWebFileBook || bookSource.bookSourceType == 3;
    if (isWebFile) {
      final urls = analyzeRule.getStringList(
        bookInfoRule.downloadUrls,
        isUrl: true,
      );
      book.downloadUrls =
          urls.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      AppLog.instance.d('[书源详情] 文件下载链接='
          '${(book.downloadUrls ?? const <String>[]).length}条');
      if (book.downloadUrls == null || book.downloadUrls!.isEmpty) {
        throw SourceResolveException(
          sourceId: bookSource.bookSourceUrl,
          apiName: 'bookInfo',
          message: '下载链接为空',
        );
      }
    } else {
      // 对照 legado BookInfo：**无条件**用详情规则覆盖 tocUrl
      //（`book.tocUrl = getString(infoRule.tocUrl, isUrl = true)`）——
      // 规则为空/未命中时得到空串，随后回退 baseUrl。旧实现「规则为空就
      // 保留搜索阶段旧值」，搜索给了错误 tocUrl 时会一路用错地址。
      // 规则异常同样不吞（legado getString 不包 try）：错误地址比失败更危险。
      book.tocUrl = analyzeRule.getString(bookInfoRule.tocUrl ?? '', isUrl: true);

      // 对照 legado BookInfo：目录地址回落到详情页**原始** URL（baseUrl）；
      // 回落到详情页自身时，详情响应体即目录页 HTML，缓存进 tocHtml 供目录
      // 阶段直接解析（省一次请求，也覆盖详情页只有一次性 Cookie/签名的站点）。
      if (book.tocUrl == null || book.tocUrl!.isEmpty) {
        book.tocUrl = baseUrl;
      }
      if (book.tocUrl == baseUrl) {
        book.tocHtml = body;
      }
    }

    // 超集字段（legado BookInfo 无此项）排在 tocUrl/downloadUrls 之后求值：
    // 与基准的求值顺序一致，@put 变量链在目录地址求值完成后再消费。
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

}
