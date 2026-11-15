/// 书籍列表解析：依据书源 `ruleSearch` 或 `ruleExplore` 解析书籍列表
/// （书名/作者/封面/详情 URL/分类/最新章节），并提供通用 HTML 链接兜底解析。
library;

import 'dart:collection';

import 'package:html/parser.dart' as html_parser;

import '../analyze/analyze_rule.dart';
import '../analyze/source_context.dart';
import '../model/book_source.dart';
import '../model/search_book.dart';
import '../model/xiaoshuo_book.dart';
import 'book_info.dart';

class BookList {
  static String _currentCategoryName = '';
  static String _currentSourceName = '';
  static Set<String> _allCategoryNames = <String>{};

  /// 设置当前分类名（用于过滤同名项）
  static void setCurrentCategoryName(String name) {
    _currentCategoryName = name;
  }

  /// 获取当前分类名
  static String getCurrentCategoryName() {
    return _currentCategoryName;
  }

  /// 设置当前源名称
  static void setCurrentSourceName(String name) {
    _currentSourceName = name;
  }

  /// 设置全部分类名集合（用于过滤分类导航项）
  static void setAllCategoryNames(Set<String> names) {
    _allCategoryNames = names;
  }

  /// 清空分类名集合
  static void clearAllCategoryNames() {
    _allCategoryNames = <String>{};
  }

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

    setCurrentSourceName(bookSource.bookSourceName);

    String? bookListRule;
    String? nameRule;
    String? authorRule;
    String? coverUrlRule;
    String? bookUrlRule;
    String? kindRule;
    String? lastChapterRule;

    if (isSearch) {
      final rule = bookSource.getSearchRule();
      bookListRule = rule.bookList;
      nameRule = rule.bookName;
      authorRule = rule.bookAuthor;
      coverUrlRule = rule.bookCoverUrl;
      bookUrlRule = rule.bookUrl;
      kindRule = rule.bookKind;
      lastChapterRule = rule.bookLastChapter;
    } else {
      final exploreRule = bookSource.getExploreRule();
      if (exploreRule.bookList == null || exploreRule.bookList!.isEmpty) {
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
      } else {
        bookListRule = exploreRule.bookList;
        nameRule = exploreRule.bookName;
        authorRule = exploreRule.bookAuthor;
        coverUrlRule = exploreRule.bookCoverUrl;
        bookUrlRule = exploreRule.bookUrl;
        kindRule = exploreRule.bookKind;
        lastChapterRule = exploreRule.bookLastChapter;
      }
    }

    if (bookListRule == null || bookListRule.isEmpty) {
      return _parseGenericBookList(body, bookSource, baseUrl);
    }

    var reverse = false;
    var listRule = bookListRule;
    if (listRule.startsWith('-')) {
      reverse = true;
      listRule = listRule.substring(1);
    }
    if (listRule.startsWith('+')) {
      listRule = listRule.substring(1);
    }

    var books = <SearchBook>[];
    try {
      final elements = analyzeRule.getElements(listRule);

      // legado 语义（isSearch）：baseUrl 命中 bookUrlPattern → 整页按详情
      // 页解析（搜索直达详情页的源）。
      if (isSearch) {
        final pattern = bookSource.bookUrlPattern;
        if (pattern != null && pattern.isNotEmpty) {
          try {
            if (RegExp(pattern).hasMatch(baseUrl)) {
              final detail = _detailPageAsSearchBook(bookSource, body, baseUrl);
              return detail == null ? const <SearchBook>[] : [detail];
            }
          } catch (_) {}
        }
      }

      if (elements.isEmpty) {
        // legado 行为：列表为空且未声明 bookUrlPattern → 整页按详情解析
        //（声明了 ruleBookInfo.name 时字段更全）；否则通用解析兜底。
        final infoName = bookSource.ruleBookInfo?.name;
        if (infoName != null && infoName.isNotEmpty) {
          // 页级书名提取不到（如 API 返回空数组）时不产出条目：
          // 否则空名条目会带 baseUrl 作为 bookUrl 混入结果（legado
          // getInfoItem 同样以 name 非空为产出前提）。
          final detail = _detailPageAsSearchBook(bookSource, body, baseUrl);
          return detail == null ? const <SearchBook>[] : [detail];
        }
        return _parseGenericBookList(body, bookSource, baseUrl);
      }

      final ruleName = analyzeRule.splitSourceRule(nameRule ?? '');
      final ruleBookUrl = analyzeRule.splitSourceRule(bookUrlRule ?? '');
      final ruleAuthor = analyzeRule.splitSourceRule(authorRule ?? '');
      final ruleCoverUrl = analyzeRule.splitSourceRule(coverUrlRule ?? '');
      final ruleKind = analyzeRule.splitSourceRule(kindRule ?? '');
      final ruleLastChapter = analyzeRule.splitSourceRule(lastChapterRule ?? '');

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

      // 如果所有提取的书籍名称都为空，回退到通用解析
      if (books.isEmpty) {
        return _parseGenericBookList(body, bookSource, baseUrl);
      }

      final uniqueBooks = LinkedHashSet<SearchBook>.from(books);
      books.clear();
      books.addAll(uniqueBooks);

      if (reverse) {
        books = books.reversed.toList();
      }
    } catch (_) {}

    if (books.isEmpty) {
      return _parseGenericBookList(body, bookSource, baseUrl);
    }

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
  ) {
    String name = '';
    String author = '';
    String coverUrl = '';
    String bookUrl = '';
    String kind = '';
    String lastChapter = '';

    try {
      if (ruleName.isNotEmpty) {
        // 规则路径书名只做轻量清洗（对齐通用书源引擎语义）：去「作者:xxx /
        // xxx 著」尾缀 + 首尾分隔符。此前误用通用兜底的激进过滤（含
        // 「推荐/新书/热门/连载…」等子串即整条丢弃），会把正常书名错误过滤。
        name = formatBookNameLight(analyzeRule.getStringFromRules(ruleName));
      }
    } catch (_) {}

    if (name.isEmpty) {
      return null;
    }

    try {
      if (ruleAuthor.isNotEmpty) {
        author = formatBookAuthor(analyzeRule.getStringFromRules(ruleAuthor));
      }
    } catch (_) {}

    try {
      if (ruleKind.isNotEmpty) {
        final kinds = analyzeRule.getStringListFromRules(ruleKind);
        kind = kinds.join(',');
        if (kind.length > 1000) kind = kind.substring(0, 1000);
      }
    } catch (_) {}

    try {
      if (ruleLastChapter.isNotEmpty) {
        lastChapter = analyzeRule.getStringFromRules(ruleLastChapter);
      }
    } catch (_) {}

    try {
      if (ruleCoverUrl.isNotEmpty) {
        coverUrl = analyzeRule.getStringFromRules(ruleCoverUrl);
      }
    } catch (_) {}

    if (coverUrl.isNotEmpty) {
      // 处理协议相对 URL（如 //example.com/img.jpg）
      if (coverUrl.startsWith('//')) {
        coverUrl = 'https:$coverUrl';
      } else if (!coverUrl.startsWith('http')) {
        coverUrl = _getAbsoluteUrl(coverUrl, baseUrl);
      }
    }

    try {
      if (ruleBookUrl.isNotEmpty) {
        // legado getSearchItem：先 setRuleData(searchBook) 再求 bookUrl，
        // 使 URL 模板里的 `{{book.kind}}` 等读到当前条目已解析字段
        // （企鹅浏览 resourceId={{book.kind}}；无此绑定时模板展开为空）。
        final itemBook = XiaoshuoBook(bookUrl: '', name: name)
          ..author = author
          ..kind = kind
          ..coverUrl = coverUrl
          ..lastChapter = lastChapter;
        final prevBook = analyzeRule.book;
        analyzeRule.book = itemBook;
        try {
          bookUrl = analyzeRule.getStringFromRules(ruleBookUrl, isUrl: true);
        } finally {
          analyzeRule.book = prevBook;
        }
      }
    } catch (_) {}

    if (bookUrl.isEmpty) {
      bookUrl = baseUrl;
    } else if (!bookUrl.startsWith('http')) {
      bookUrl = _getAbsoluteUrl(bookUrl, baseUrl);
    }

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
      bookSourceUrl: bookSource.bookSourceUrl,
      bookSourceName: bookSource.bookSourceName,
      type: bookSource.bookSourceType,
    );
  }

  /// 规则路径书名轻量清洗（对齐通用书源引擎语义）：
  /// - 去「作者：xxx」/「xxx 著」尾缀（列表项书名常带）；
  /// - 去首尾分隔符并 trim。
  /// 不做任何关键词级丢弃——书源规则明确指向书名元素，信任源作者的规则；
  /// 激进的导航词过滤仅用于 [formatBookName]（通用兜底解析路径）。
  static String formatBookNameLight(String name) {
    if (name.isEmpty) return name;
    var result = name
        .replaceAll(RegExp(r'\s+作\s*者.*'), '')
        .replaceAll(RegExp(r'\s+\S+\s+著'), '')
        .replaceAll(RegExp(r'^\s*[-_—–|/\\]+\s*'), '')
        .replaceAll(RegExp(r'\s*[-_—–|/\\]+\s*$'), '')
        .trim();
    // 超长防御：正常书名不会超过 50 字，超长多为解析到整段文本。
    if (result.length > 80) result = result.substring(0, 80);
    return result;
  }

  /// 书名格式化：过滤分类导航/广告/品牌词，剥离方括号与分隔符。
  /// 仅用于通用兜底解析（[_parseGenericBookList]）——该路径从任意 <a> 标签
  /// 提取候选，必须激进过滤导航/品牌/分类词；规则路径请用
  /// [formatBookNameLight]。
  static String formatBookName(String name) {
    if (name.isEmpty) return name;

    // 过滤与当前分类名称相同的项
    if (_currentCategoryName.isNotEmpty && name == _currentCategoryName) {
      return '';
    }

    // 过滤与当前源名称相同的项
    if (_currentSourceName.isNotEmpty && name == _currentSourceName) {
      return '';
    }

    // 过滤全部分类名称
    if (_allCategoryNames.contains(name)) {
      return '';
    }

    // 过滤邮件地址
    if (name.contains('@')) {
      return '';
    }

    // 过滤 URL 格式文本
    if (name.contains('http://') || name.contains('https://') || name.contains('www.')) {
      return '';
    }

    // 过滤常见的非书籍内容
    final nonBookPatterns = [
      r'返回',
      r'首页',
      r'秒钟',
      r'秒后',
      r'正在跳转',
      r'请稍候',
      r'loading',
      r'下载APP',
      r'安装客户端',
      // 页面功能/导航文字
      r'足迹',
      r'版本感想',
      r'直达底部',
      r'返回顶部',
      r'回到顶部',
      r'顶部',
      r'底部',
      r'回到首页',
      r'返回首页',
      // 章节标题模式（如"第 76 章 真理论"）
      r'^第[零一二三四五六七八九十百千万0-9]+[章节话回]',
      // 导航链接
      r'^阅读$',
      r'^目录$',
      r'^加入书架',
      r'^书架$',
      r'^收藏本书',
      r'^推荐本书',
      r'^投推荐票',
      r'^TXT下载',
      r'^手机阅读',
      // 导航入口和品牌名称
      r'书库',
      r'全本',
      r'排行',
      r'榜单',
      r'热门',
      r'推荐',
      r'新书',
      r'完结',
      r'连载',
      r'免费',
      r'精品',
      r'精选',
      r'阅读历史',
      r'我的书架',
      r'我的收藏',
      r'更多',
      r'^完本$',
      r'^更新$',
      r'^分类$',
      r'^搜索$',
      r'^登录$',
      r'^注册$',
      r'^设置$',
    ];

    for (final pattern in nonBookPatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(name)) {
        return '';
      }
    }

    // 过滤品牌名称：文本长度 <= 4 且包含品牌关键词
    if (name.length <= 4) {
      if (RegExp(r'漫画|动漫|书吧|书城|书屋|读书|文库|阅读|小说|看书').hasMatch(name)) {
        return '';
      }
    }

    // 过滤常见短分类词（如 玄幻、言情、都市 等分类导航标签）
    if (name.length <= 4) {
      if (RegExp(r'^玄幻$|^奇幻$|^武侠$|^仙侠$|^都市$|^现实$|^历史$|^军事$|^悬疑$|^游戏$|^体育$|^科幻$|^轻小说$|^言情$|^同人$|^短篇$|^漫画$|^动漫$|^绘本$|^读物$|^文学$|^青春$|^校园$|^甜宠$|^古言$|^宫斗$|^穿越$|^重生$|^修真$|^洪荒$|^种田$|^系统$|^快穿$|^耽美$|^百合$|^架空$|^职场$|^娱乐$|^明星$|^影视$|^经典$|^畅销$|^新书$|^热门$|^完结$|^连载$|^全本$|^免费$|^精品$|^精选$').hasMatch(name)) {
        return '';
      }
    }

    // 过滤 1-2 个字符的常见导航用汉字
    if (name.length <= 2) {
      const navChars = '读阅看书章节卷部篇集话回阅览';
      if (name.length == 1 && navChars.contains(name)) {
        return '';
      }
      if (name.length == 2) {
        // 两个字符都是导航用单字也过滤
        if (navChars.contains(name[0]) && navChars.contains(name[1])) {
          return '';
        }
      }
    }

    // 过滤过短或过长的内容
    if (name.length < 2 || name.length > 50) {
      return '';
    }

    return name
        // 去除各类方括号及其内容：【】、[]、（）()、{}、<>、《》
        .replaceAll(
          RegExp(r'[【\[（\(｛{<《][^】\]）\)｝}>》]*[】\]）\)｝}>》]'),
          '',
        )
        // 去除开头/结尾的分隔符
        .replaceAll(RegExp(r'^\s*[-_—–|/\\]+\s*'), '')
        .replaceAll(RegExp(r'\s*[-_—–|/\\]+\s*$'), '')
        .trim();
  }

  /// 作者名格式化：剥离"作者："前缀、首尾分隔符。
  static String formatBookAuthor(String author) {
    if (author.isEmpty) return author;
    return author
        // 去除 "作者:" / "作者：" 前缀
        .replaceAll(RegExp(r'^\s*作\s*者\s*[:：]\s*'), '')
        // 去除开头可能残留的单个冒号
        .replaceAll(RegExp(r'^\s*[:：]\s*'), '')
        // 去除开头/结尾的分隔符
        .replaceAll(RegExp(r'^\s*[-_—–|/\\]+\s*'), '')
        .replaceAll(RegExp(r'\s*[-_—–|/\\]+\s*$'), '')
        .trim();
  }

  /// 通用书籍列表解析：当书源规则未配置或失败时，从 HTML <a> 标签提取候选。
  static List<SearchBook> _parseGenericBookList(
    String body,
    XiaoshuoBookSource bookSource,
    String baseUrl,
  ) {
    final document = html_parser.parse(body);
    final books = <SearchBook>[];

    final links = document.querySelectorAll('a[href]');
    for (final a in links) {
      final href = a.attributes['href'] ?? '';

      // 1. 过滤空链接、锚点、javascript
      if (href.isEmpty || href == '#' || href.startsWith('javascript:')) {
        continue;
      }

      // 2. 过滤 URL 路径为 / 或空的链接（首页链接）
      try {
        final uri = Uri.parse(href.startsWith('http')
            ? href
            : Uri.parse(baseUrl).resolve(href).toString());
        if (uri.path == '/' || uri.path.isEmpty) continue;
      } catch (_) {}

      final originalText = a.text.trim();

      // 过滤邮件地址
      if (originalText.contains('@')) continue;

      // 过滤 URL 格式文本
      if (originalText.contains('http://') ||
          originalText.contains('https://') ||
          originalText.contains('www.')) {
        continue;
      }

      // 3. 过滤分页元素
      if (RegExp(r'^\d+$').hasMatch(originalText)) continue;
      if (originalText == '>>' ||
          originalText == '<<' ||
          originalText == '>' ||
          originalText == '<') {
        continue;
      }
      if (originalText.contains('下一页') ||
          originalText.contains('上一页')) {
        continue;
      }

      // 4. 使用 formatBookName 过滤（已包含分类名、源名称、导航关键词等过滤）
      var text = formatBookName(originalText);
      if (text.isEmpty) continue;

      // 5. 使用 _isNonBookContent 进行更严格的过滤
      if (_isNonBookContent(originalText)) continue;

      // 优先从 <a> 内部查找 img 标签
      var img = a.querySelector('img');

      // 回退：如果 <a> 内没有 img，检查父元素中的 img（img 与 a 为兄弟节点的情况）
      img ??= a.parent?.querySelector('img');

      var cover = img?.attributes['src'] ??
          img?.attributes['data-src'] ??
          img?.attributes['data-original'] ??
          img?.attributes['lazy-src'] ??
          img?.attributes['data-lazy'] ??
          img?.attributes['data-lazy-src'] ??
          img?.attributes['original'] ??
          '';

      // 同时检查 srcset 属性（响应式图片）
      if (cover.isEmpty) {
        final srcset = img?.attributes['srcset'] ?? '';
        if (srcset.isNotEmpty) {
          // 取 srcset 中第一个 URL（格式："url1 1x, url2 2x"）
          final firstSrc =
              srcset.split(',').first.trim().split(' ').first.trim();
          if (firstSrc.isNotEmpty) {
            cover = firstSrc;
          }
        }
      }

      // 封面 URL 转换为绝对路径
      if (cover.isNotEmpty) {
        if (cover.startsWith('//')) {
          cover = 'https:$cover';
        } else if (!cover.startsWith('http')) {
          cover = _getAbsoluteUrl(cover, baseUrl);
        }
      }

      var link = href;
      if (!link.startsWith('http')) {
        link = _getAbsoluteUrl(link, baseUrl);
      }

      books.add(SearchBook(
        bookUrl: link,
        name: text,
        coverUrl: cover,
        bookSourceUrl: bookSource.bookSourceUrl,
        bookSourceName: bookSource.bookSourceName,
        type: bookSource.bookSourceType,
      ));
    }

    return books;
  }

  /// 严格非书籍内容判定：用于通用解析路径的二次过滤。
  static bool _isNonBookContent(String text) {
    // 过滤与当前分类名称相同的项
    if (_currentCategoryName.isNotEmpty && text == _currentCategoryName) {
      return true;
    }

    // 过滤与当前源名称相同的项
    if (_currentSourceName.isNotEmpty && text == _currentSourceName) {
      return true;
    }

    // 过滤全部分类名称
    if (_allCategoryNames.contains(text)) {
      return true;
    }

    // 过滤邮件地址（包含 @ 符号）
    if (text.contains('@')) {
      return true;
    }

    // 过滤 URL 格式文本
    if (text.contains('http://') ||
        text.contains('https://') ||
        text.contains('www.')) {
      return true;
    }

    // 过滤包含跳转/导航关键词的内容
    final nonBookPatterns = [
      r'返回',
      r'首页',
      r'秒钟',
      r'秒后',
      r'正在跳转',
      r'请稍候',
      r'loading',
      r'下载APP',
      r'安装',
      r'足迹',
      r'版本感想',
      r'直达底部',
      r'返回顶部',
      r'回到顶部',
      r'顶部',
      r'底部',
      r'回到首页',
      r'返回首页',
      r'^阅读$',
      r'^目录$',
      r'^加入书架',
      r'^书架$',
      r'^收藏本书',
      r'^推荐本书',
      r'^投推荐票',
      r'^TXT下载',
      r'^手机阅读',
      r'书库',
      r'全本',
      r'排行',
      r'榜单',
      r'热门',
      r'推荐',
      r'新书',
      r'完结',
      r'连载',
      r'免费',
      r'精品',
      r'精选',
      r'阅读历史',
      r'我的书架',
      r'我的收藏',
      r'更多',
      r'^Copyright',
      r'^ICP',
      r'^备案',
      r'^第[零一二三四五六七八九十百千万0-9]+[章节话回]',
    ];

    for (final pattern in nonBookPatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(text)) {
        return true;
      }
    }

    // 过滤品牌名称：文本长度 <= 4 且包含品牌关键词
    if (text.length <= 4) {
      if (RegExp(r'漫画|动漫|书吧|书城|书屋|读书|文库|阅读|小说|看书').hasMatch(text)) {
        return true;
      }
    }

    // 过滤常见短分类词（如 玄幻、言情、都市 等分类导航标签）
    if (text.length <= 4) {
      if (RegExp(r'^玄幻$|^奇幻$|^武侠$|^仙侠$|^都市$|^现实$|^历史$|^军事$|^悬疑$|^游戏$|^体育$|^科幻$|^轻小说$|^言情$|^武侠$|^同人$|^短篇$|^漫画$|^动漫$|^绘本$|^读物$|^文学$|^青春$|^校园$|^甜宠$|^古言$|^宫斗$|^穿越$|^重生$|^修真$|^洪荒$|^种田$|^系统$|^快穿$|^耽美$|^百合$|^架空$|^职场$|^娱乐$|^明星$|^影视$|^经典$|^畅销$|^新书$|^热门$|^完结$|^连载$|^全本$|^免费$|^精品$|^精选$').hasMatch(text)) {
        return true;
      }
    }

    // 过滤 1-2 个字符的常见导航用汉字
    if (text.length <= 2) {
      const navChars = '读阅看书章节卷部篇集话回阅览';
      if (text.length == 1 && navChars.contains(text)) {
        return true;
      }
      if (text.length == 2) {
        if (navChars.contains(text[0]) && navChars.contains(text[1])) {
          return true;
        }
      }
    }

    // 过滤纯数字、纯标点符号（但保留包含中文/英文的内容）
    if (RegExp(r'^[\d\s\p{P}]+$', unicode: true).hasMatch(text)) {
      if (!RegExp(r'[a-zA-Z\u4e00-\u9fff]').hasMatch(text)) {
        return true;
      }
    }

    // 过滤过短或过长的内容
    if (text.length < 2 || text.length > 50) {
      return true;
    }

    return false;
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

  static String _getAbsoluteUrl(String url, String baseUrl) {
    if (url.startsWith('http')) return url;
    if (baseUrl.isEmpty) return url;
    try {
      final base = Uri.parse(baseUrl);
      return base.resolve(url).toString();
    } catch (_) {
      return url;
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
      bookSourceUrl: bookSource.bookSourceUrl,
      bookSourceName: bookSource.bookSourceName,
    );
  }
}
