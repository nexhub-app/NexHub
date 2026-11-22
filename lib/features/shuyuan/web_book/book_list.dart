/// 书籍列表解析：依据书源 `ruleSearch` 或 `ruleExplore` 解析书籍列表
/// （书名/作者/封面/详情 URL/分类/最新章节）。
///
/// 对齐 legado BookList：规则命中为空时按「整页详情」解析（搜索直达详情 /
/// 列表规则失效），不再从任意 `<a>` 标签猜测书籍——猜测会把导航链接当书，
/// 表现为「点开是另一本书/首页」。
library;

import 'dart:collection';

import 'package:html/parser.dart' as html_parser;

import '../analyze/analyze_rule.dart';
import '../analyze/html_formatter.dart';
import '../analyze/source_context.dart';
import '../analyze/string_utils.dart';
import '../model/book_source.dart';
import '../model/search_book.dart';
import '../model/xiaoshuo_book.dart';
import 'book_info.dart';

class BookList {
  static List<SearchBook> analyzeBookList({
    required XiaoshuoBookSource bookSource,
    required String baseUrl,
    required String body,
    required bool isSearch,
    String? searchKey,
    Map<String, String>? ruleData,
  }) {
    // 登录墙拦截：部分书源（如八一中文 81txt）的搜索接口被服务端「登录/验证码」
    // 拦截，返回的其实是登录页而非结果。若不拦截，下方的通用兜底解析会把登录页
    // 导航（如「玄幻修真」「重生穿越」）误当成书籍。命中登录墙直接返回空列表，
    // 让上层显示「无结果」而非垃圾数据。该判断仅针对真正的登录墙（标题含登录且
    // 页面存在密码框/验证码），正常结果页不会误伤。
    if (_isLoginWall(body)) {
      return const <SearchBook>[];
    }

    final ruleDataObj = ruleData != null
        ? (XiaoshuoBook(bookUrl: '', name: '')..variableMap.addAll(ruleData))
        : null;
    final analyzeRule = AnalyzeRule(book: ruleDataObj)
      ..setContent(body, baseUrl)
      ..setBaseUrl(baseUrl)
      ..setRedirectUrl(baseUrl);

    String? bookListRule;
    String? nameRule;
    String? authorRule;
    String? coverUrlRule;
    String? bookUrlRule;
    String? kindRule;
    String? lastChapterRule;
    String? introRule;
    String? wordCountRule;

    if (isSearch) {
      final rule = bookSource.getSearchRule();
      bookListRule = rule.bookList;
      nameRule = rule.bookName;
      authorRule = rule.bookAuthor;
      coverUrlRule = rule.bookCoverUrl;
      bookUrlRule = rule.bookUrl;
      kindRule = rule.bookKind;
      lastChapterRule = rule.bookLastChapter;
      introRule = rule.bookIntro;
      wordCountRule = rule.bookWordCount;
    } else {
      final exploreRule = bookSource.getExploreRule();
      // legado `isNullOrBlank()`：空白串（仅空格/换行）同样视为未配置。
      if (exploreRule.bookList == null ||
          exploreRule.bookList!.trim().isEmpty) {
        // legado 行为：绝大多数书源只配置 ruleSearch，发现/分类页直接复用
        // ruleSearch 解析（legado 官方即如此）。若 ruleExplore 未配置（空），
        // 回退到 ruleSearch，避免发现页因空规则而解析不到任何内容——
        // 这是「导入的书源在在线浏览页什么都没有」的主因之一。
        final searchRule = bookSource.getSearchRule();
        bookListRule = searchRule.bookList;
        nameRule = searchRule.bookName;
        authorRule = searchRule.bookAuthor;
        coverUrlRule = searchRule.bookCoverUrl;
        bookUrlRule = searchRule.bookUrl;
        kindRule = searchRule.bookKind;
        lastChapterRule = searchRule.bookLastChapter;
        introRule = searchRule.bookIntro;
        wordCountRule = searchRule.bookWordCount;
      } else {
        bookListRule = exploreRule.bookList;
        nameRule = exploreRule.bookName;
        authorRule = exploreRule.bookAuthor;
        coverUrlRule = exploreRule.bookCoverUrl;
        bookUrlRule = exploreRule.bookUrl;
        kindRule = exploreRule.bookKind;
        lastChapterRule = exploreRule.bookLastChapter;
        introRule = exploreRule.bookIntro;
        wordCountRule = exploreRule.bookWordCount;
      }
    }

    // legado：列表规则缺失等价于空规则（getElements("") → 空集合），
    // 随后走「列表为空」分支按整页详情解析，不做链接猜测。
    var reverse = false;
    var listRule = bookListRule ?? '';
    if (listRule.startsWith('-')) {
      reverse = true;
      listRule = listRule.substring(1);
    }
    if (listRule.startsWith('+')) {
      listRule = listRule.substring(1);
    }

    var books = <SearchBook>[];
    try {
      // legado 语义（isSearch）：baseUrl 命中 bookUrlPattern → 整页按详情
      // 页解析（搜索直达详情页的源），且先于 bookList 规则求值——命中时
      // 不执行列表规则（规则可能带副作用或抛错）。legado 用
      // `String.matches`（整串匹配），部分匹配会把普通列表页误判成详情页。
      if (isSearch) {
        final pattern = bookSource.bookUrlPattern;
        if (pattern != null && pattern.isNotEmpty) {
          try {
            if (_fullMatch(pattern, baseUrl)) {
              final detail = _detailPageAsSearchBook(bookSource, body, baseUrl);
              return detail == null ? const <SearchBook>[] : [detail];
            }
          } catch (_) {}
        }
      }

      final elements = analyzeRule.getElements(listRule);

      if (elements.isEmpty) {
        // legado：列表为空且未声明 bookUrlPattern → 整页按详情解析
        //（getInfoItem 以 name 非空为产出前提，解析不出书名则无结果）。
        if ((bookSource.bookUrlPattern ?? '').isEmpty) {
          final detail = _detailPageAsSearchBook(bookSource, body, baseUrl);
          return detail == null ? const <SearchBook>[] : [detail];
        }
        return const <SearchBook>[];
      }

      final ruleName = analyzeRule.splitSourceRule(nameRule ?? '');
      final ruleBookUrl = analyzeRule.splitSourceRule(bookUrlRule ?? '');
      final ruleAuthor = analyzeRule.splitSourceRule(authorRule ?? '');
      final ruleCoverUrl = analyzeRule.splitSourceRule(coverUrlRule ?? '');
      final ruleKind = analyzeRule.splitSourceRule(kindRule ?? '');
      final ruleLastChapter = analyzeRule.splitSourceRule(lastChapterRule ?? '');
      final ruleIntro = analyzeRule.splitSourceRule(introRule ?? '');
      final ruleWordCount = analyzeRule.splitSourceRule(wordCountRule ?? '');

      for (final element in elements) {
        analyzeRule.setContent(element);
        final book = _extractSearchBook(
          analyzeRule,
          bookSource,
          baseUrl,
          ruleName,
          ruleAuthor,
          ruleCoverUrl,
          ruleBookUrl,
          ruleKind,
          ruleLastChapter,
          ruleIntro,
          ruleWordCount,
        );
        if (book != null && book.name.isNotEmpty) {
          books.add(book);
          // 暂存条目上下文：API 返回的 URL 字段含 {{\$.field}} 模板时，
          // 详情/目录阶段 AnalyzeUrl 以此为求值根（ruleData 贯通）。
          if (ShuyuanSourceContext.current != null &&
              book.bookUrl.isNotEmpty) {
            ShuyuanSourceContext.current!.bookItemContext[book.bookUrl] =
                element;
          }
        }
      }

      // legado：全部条目书名为空时直接返回空列表，不回退到链接猜测。
      final uniqueBooks = LinkedHashSet<SearchBook>.from(books);
      books.clear();
      books.addAll(uniqueBooks);

      if (reverse) {
        books = books.reversed.toList();
      }
    } catch (_) {}

    return books;
  }

  static SearchBook? _extractSearchBook(
    AnalyzeRule analyzeRule,
    XiaoshuoBookSource bookSource,
    String baseUrl,
    List<dynamic> ruleName,
    List<dynamic> ruleAuthor,
    List<dynamic> ruleCoverUrl,
    List<dynamic> ruleBookUrl,
    List<dynamic> ruleKind,
    List<dynamic> ruleLastChapter,
    List<dynamic> ruleIntro,
    List<dynamic> ruleWordCount,
  ) {
    // legado getSearchItem：先 setRuleData(searchBook) 再逐字段求值，规则里
    // 的 `{{$.field}}`/`{{book.field}}` 读到的是**当前条目**已解析字段
    //（旧实现只在求 bookUrl 时绑定，书名/简介阶段的模板读不到）。
    final itemBook = XiaoshuoBook(bookUrl: '', name: '')
      ..type = bookSource.bookSourceType;
    final prevBook = analyzeRule.book;
    analyzeRule.book = itemBook;
    try {
      var name = '';
      try {
        if (ruleName.isNotEmpty) {
          // legado BookList.getInfoItem：BookHelp.formatBookName（仅剥离作者
          // 尾巴 + ASCII 空白修剪），详情阶段同口径。
          name = StringUtils.formatBookName(
              analyzeRule.getStringFromRules(ruleName));
        }
      } catch (_) {}

      if (name.isEmpty) {
        return null;
      }
      itemBook.name = name;

      var author = '';
      try {
        if (ruleAuthor.isNotEmpty) {
          author = StringUtils.formatBookAuthor(
              analyzeRule.getStringFromRules(ruleAuthor));
          itemBook.author = author;
        }
      } catch (_) {}

      var kind = '';
      try {
        if (ruleKind.isNotEmpty) {
          kind = analyzeRule.getStringListFromRules(ruleKind).join(',');
          if (kind.length > 1000) kind = kind.substring(0, 1000);
          itemBook.kind = kind;
        }
      } catch (_) {}

      // 与 legado getSearchItem 求值顺序一致：
      // name → author → kind → wordCount → lastChapter → intro → cover → url。
      var wordCount = '';
      try {
        if (ruleWordCount.isNotEmpty) {
          wordCount =
              StringUtils.wordCountFormat(analyzeRule.getStringFromRules(ruleWordCount));
          itemBook.wordCount = wordCount;
        }
      } catch (_) {}

      var lastChapter = '';
      try {
        if (ruleLastChapter.isNotEmpty) {
          lastChapter = analyzeRule.getStringFromRules(ruleLastChapter);
          // legado SearchBook.init：最新章标题截断 200。
          if (lastChapter.length > 200) {
            lastChapter = lastChapter.substring(0, 200);
          }
          itemBook.lastChapter = lastChapter;
        }
      } catch (_) {}

      var intro = '';
      try {
        if (ruleIntro.isNotEmpty) {
          // legado：HtmlFormatter.format(getString(ruleIntro)).take(5000)
          intro =
              HtmlFormatter.formatIntro(analyzeRule.getStringFromRules(ruleIntro));
          itemBook.intro = intro;
        }
      } catch (_) {}

      var coverUrl = '';
      try {
        if (ruleCoverUrl.isNotEmpty) {
          coverUrl = analyzeRule.getStringFromRules(ruleCoverUrl).trim();
          if (coverUrl.isNotEmpty) {
            // legado NetworkUtils.getAbsoluteURL(baseUrl, it)：按页面协议
            // 解析协议相对地址（//host/x 在 http 页保持 http，不再硬编码 https）。
            coverUrl = _getAbsoluteUrl(coverUrl, baseUrl);
            itemBook.coverUrl = coverUrl;
          }
        }
      } catch (_) {}

      var bookUrl = '';
      try {
        if (ruleBookUrl.isNotEmpty) {
          // legado getString(urlRule, isUrl=true)：空结果回落 baseUrl。
          bookUrl =
              analyzeRule.getStringFromRules(ruleBookUrl, isUrl: true).trim();
        }
      } catch (_) {}
      if (bookUrl.isEmpty) {
        bookUrl = baseUrl;
      } else {
        bookUrl = _getAbsoluteUrl(bookUrl, baseUrl);
      }
      itemBook.bookUrl = bookUrl;

      // 变量贯通：把本条 @put/java.put 写入的变量按书暂存，详情/目录/正文
      // 阶段注入 variableMap 后 @get/java.get 可读（legado 书对象随书携带
      // variableMap；本应用阶段间只传 bookUrl）。
      final ctx = ShuyuanSourceContext.current;
      if (ctx != null && bookUrl.isNotEmpty && analyzeRule.variables.isNotEmpty) {
        ctx.bookItemVars[bookUrl] =
            Map<String, String>.from(analyzeRule.variables);
      }

      return SearchBook(
        bookUrl: bookUrl,
        name: name,
        author: author,
        coverUrl: coverUrl,
        kind: kind,
        lastChapter: lastChapter,
        intro: intro.isEmpty ? null : intro,
        wordCount: wordCount.isEmpty ? null : wordCount,
        bookSourceUrl: bookSource.bookSourceUrl,
        bookSourceName: bookSource.bookSourceName,
        type: bookSource.bookSourceType,
      );
    } finally {
      analyzeRule.book = prevBook;
    }
  }

  /// legado `String.matches`：整串匹配（而非任意位置命中）。
  static bool _fullMatch(String pattern, String input) {
    final match = RegExp(pattern).matchAsPrefix(input);
    return match != null && match.end == input.length;
  }

  /// 判断页面是否为「登录墙」（服务端要求登录/验证码才能访问）。
  ///
  /// 用于搜索/发现场景：当书源接口被鉴权拦截、返回登录页而非内容时，
  /// 避免把登录页导航/品牌词误解析成书籍结果。
  ///
  /// 判定（需同时满足，降低误伤）：
  /// 1. `<title>` 含登录/登陆/注册/sign in/log in/会员 等关键词；
  /// 2. 页面存在密码输入框或验证码（验证码图/「验证码」字样/captcha）。
  /// 正常结果页通常只在页脚带一个「登录」按钮、标题不含「登录」且结果区无
  /// 密码框，因此不会被误判。
  static bool _isLoginWall(String body) {
    if (body.isEmpty) return false;
    final doc = html_parser.parse(body);
    final title = doc.querySelector('title')?.text ?? '';
    final t = title.toLowerCase();
    final loginInTitle = t.contains('登录') ||
        t.contains('登陆') ||
        t.contains('log in') ||
        t.contains('sign in') ||
        t.contains('会员登录') ||
        t.contains('用户登录');
    if (!loginInTitle) return false;

    final hasPassword =
        doc.querySelector('input[type="password"]') != null ||
            doc.querySelector('input[type=password]') != null;
    final hasCaptcha = body.contains('验证码') ||
        body.toLowerCase().contains('captcha') ||
        doc.querySelector('img[src*=captcha]') != null ||
        doc.querySelector('img[src*=code]') != null;
    return hasPassword || hasCaptcha;
  }

  /// 对齐 legado `NetworkUtils.getAbsoluteURL(baseUrl, url)`：
  /// 空串回落 baseUrl；http(s) 原样；javascript 链接返回空；其余（含
  /// `//host/path` 协议相对地址）按 baseUrl 解析（保留页面协议）。
  static String _getAbsoluteUrl(String url, String baseUrl) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return baseUrl;
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return trimmed;
    }
    if (lower.startsWith('javascript')) return '';
    if (baseUrl.isEmpty) return trimmed;
    try {
      final base = Uri.parse(baseUrl);
      return base.resolve(trimmed).toString();
    } catch (_) {
      return trimmed;
    }
  }

  /// 整页按详情页解析为单本 SearchBook（legado getInfoItem 的整页形态：
  /// 搜索直达详情页 / 列表为空且未声明 bookUrlPattern 的回退）。
  static SearchBook? _detailPageAsSearchBook(
    XiaoshuoBookSource bookSource,
    String body,
    String baseUrl,
  ) {
    final book = XiaoshuoBook(bookUrl: baseUrl, name: '');
    BookInfo.analyzeBookInfo(
      bookSource: bookSource,
      book: book,
      baseUrl: baseUrl,
      redirectUrl: baseUrl,
      body: body,
    );
    if (book.name.isEmpty) return null;
    return SearchBook(
      bookUrl: book.bookUrl.isNotEmpty ? book.bookUrl : baseUrl,
      name: book.name,
      author: book.author,
      coverUrl: book.coverUrl,
      kind: book.kind,
      lastChapter: book.lastChapter,
      intro: book.intro,
      tocUrl: book.tocUrl,
      wordCount: book.wordCount,
      bookSourceUrl: bookSource.bookSourceUrl,
      bookSourceName: bookSource.bookSourceName,
      type: bookSource.bookSourceType,
    );
  }
}
