/// 章节目录解析：依据书源 `ruleToc` 解析章节列表（标题、URL、卷/VIP/付费标记）。
library;

import '../../../core/utils/app_log.dart';
import '../analyze/js_engine.dart';
import '../analyze/analyze_rule.dart';
import '../analyze/source_context.dart';
import '../model/book_source.dart';
import '../model/xiaoshuo_book.dart';
import '../model/xiaoshuo_book_chapter.dart';

class BookChapterList {
  /// [nextUrlsOut] 非空时回填本页 `ruleToc.nextTocUrl` 解析出的后续目录页
  /// 绝对 URL（对齐 legado：先取下一页列表，再解析章节；首页/串行跟随页
  /// 会继续提取，并发模式传 [getNextUrl]=false 不提取）。
  static List<XiaoshuoBookChapter> analyzeChapterList({
    required XiaoshuoBookSource bookSource,
    required XiaoshuoBook book,
    required String baseUrl,
    required String? redirectUrl,
    required String body,
    List<String>? nextUrlsOut,
    bool getNextUrl = true,
    bool applyReverse = true,
  }) {
    final tocRule = bookSource.getTocRule();
    final analyzeRule = AnalyzeRule(book: book)
      ..setContent(body, redirectUrl ?? baseUrl)
      ..setBaseUrl(baseUrl)
      ..setRedirectUrl(redirectUrl ?? baseUrl);

    final nextTocRule = tocRule.nextTocUrl;
    if (getNextUrl &&
        nextUrlsOut != null &&
        nextTocRule != null &&
        nextTocRule.isNotEmpty) {
      try {
        final redirect = redirectUrl ?? baseUrl;
        for (final raw in analyzeRule.getStringList(nextTocRule, isUrl: true)) {
          final url = raw.trim();
          if (url.isEmpty || url == redirect || url == baseUrl) continue;
          final lower = url.toLowerCase();
          if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
            continue;
          }
          if (!nextUrlsOut.contains(url)) nextUrlsOut.add(url);
        }
      } catch (_) {}
    }

    var chapters = <XiaoshuoBookChapter>[];
    // URL 去重：避免目录页中"最新章节预览"等栏与正式列表重复收录同一章节，
    // 也防止跨书链接被错误计入。通用能力，仅按绝对 URL 去重，不影响正常多章节。
    final seenUrls = <String>{};

    var listRule = tocRule.chapterList ?? '';
    var reverse = false;
    if (listRule.startsWith('-')) {
      reverse = true;
      listRule = listRule.substring(1);
    }
    if (listRule.startsWith('+')) {
      listRule = listRule.substring(1);
    }

    if (listRule.isEmpty) {
      AppLog.instance.w('[书源目录] chapterList 规则为空: 源=${bookSource.bookSourceName}');
      return chapters;
    }

    try {
      var elements = analyzeRule.getElements(listRule);
      AppLog.instance.d('[书源目录] 源=${bookSource.bookSourceName} '
          '规则=$listRule → ${elements.length}个元素');

      if (elements.isEmpty) {
        AppLog.instance.w('[书源目录] 规则未命中任何元素: $listRule 源=${bookSource.bookSourceName}');
        return chapters;
      }

      // 排除选择器：在进入逐条解析前，先剔除落在"最新章节预览"/"推荐"等
      // 非正文容器内的元素。比 [chapterScope] URL 前缀过滤更彻底——这些元素
      // 根本不会进入后续的标题提取/URL去重/垃圾标题过滤流程。
      if (tocRule.excludeSelector != null &&
          tocRule.excludeSelector!.isNotEmpty) {
        try {
          final excluded = analyzeRule.getElements(tocRule.excludeSelector!);
          if (excluded.isNotEmpty) {
            // 收集被排除容器及其所有后代元素（O(n*m)，但目录页元素通常 < 500）
            final excludedSet = <dynamic>{};
            for (final ex in excluded) {
              excludedSet.add(ex);
              // queryAll('*') 获取所有后代
              final descendants = ex.querySelectorAll('*');
              for (final d in descendants) {
                excludedSet.add(d);
              }
            }
            if (excludedSet.isNotEmpty) {
              elements = elements
                  .where((el) => !excludedSet.contains(el))
                  .toList();
            }
          }
        } catch (_) {
          // 排除选择器解析失败时不影响主流程（降级为不过滤）
        }
      }

      final ruleName = analyzeRule.splitSourceRule(tocRule.chapterName ?? '');
      final ruleUrl = analyzeRule.splitSourceRule(tocRule.chapterUrl ?? '');
      final ruleIsVolume = analyzeRule.splitSourceRule(tocRule.isVolume ?? '');
      final ruleIsVip = analyzeRule.splitSourceRule(tocRule.isVip ?? '');
      final ruleIsPay = analyzeRule.splitSourceRule(tocRule.isPay ?? '');
      final ruleUpdateTime = analyzeRule.splitSourceRule(tocRule.updateTime ?? '');

      for (int i = 0; i < elements.length; i++) {
        // 逐条隔离：源规则对个别条目抛异常（典型是 @js 空值）时跳过该条，
        // 不吞掉后续章节——否则一条坏数据会让整页目录解析为 0 章。
        try {
          analyzeRule.setContent(elements[i]);
          analyzeRule.setBaseUrl(redirectUrl ?? baseUrl);

          final bookChapter = XiaoshuoBookChapter(
            bookUrl: book.bookUrl,
            url: '',
          );
          // 对照 legado BookChapterList：逐条元素先绑定当前 chapter 再求值，
          // 章节规则的 JS（@js / {{...}}）才能读到 chapter.title/url 等；
          // 也保证本章 @put 的变量归本章。
          analyzeRule.setChapter(bookChapter);

          try {
            if (ruleName.isNotEmpty) {
              bookChapter.title = analyzeRule.getStringFromRules(ruleName);
            }
          } catch (_) {}

          try {
            if (ruleUrl.isNotEmpty) {
              // legado getString(urlRule, isUrl=true)：空结果回落 baseUrl
              //（而非空串），章节 URL 缺失的判定因此落在下方 isEmpty 分支。
              bookChapter.url =
                  analyzeRule.getStringFromRules(ruleUrl, isUrl: true);
            }
          } catch (_) {}

          // 与 legado 求值顺序一致：title → url → tag → isVolume。
          try {
            if (ruleUpdateTime.isNotEmpty) {
              bookChapter.tag = analyzeRule.getStringFromRules(ruleUpdateTime);
            }
          } catch (_) {}

          // 卷标记须在 URL 兜底前求值：urlRule 缺失时卷条目 URL 为空，
          // 需用标题占位而非 baseUrl。
          try {
            if (ruleIsVolume.isNotEmpty) {
              final isVolume = analyzeRule.getStringFromRules(ruleIsVolume);
              if (isVolume.toLowerCase() == 'true' || isVolume == '1') {
                bookChapter.isVolume = true;
              }
            }
          } catch (_) {}

          if (bookChapter.url.isEmpty) {
            // 与 legado 一致：卷章节用标题+索引做 URL 占位，普通章节用
            // baseUrl 回退（不跳过，避免目录数丢失）。
            if (bookChapter.isVolume) {
              bookChapter.url = '${bookChapter.title}$i';
            } else {
              bookChapter.url = baseUrl;
            }
          }

          // 跨书过滤（源可配置 ruleToc.chapterScope = "bookDir"）：
          // 某些站点（如笔趣阁移动站）的目录页混入了"最新章节预览"等栏，
          // 其中包含指向【其他书籍】的章节链接。仅当章节 URL 与目录页同属一个
          // 书籍目录（前缀一致，含结尾斜线以区分 book_123 与 book_1234567）时
          // 才保留，剔除跨书链接。此为通用引擎能力，仅在源显式开启时生效，
          // 不影响其他源。
          //
          // 同时兼容绝对 URL（https://...）与相对路径（/book_N/...）两种格式：
          // getStringFromRules(isUrl:true) 通常会解析为绝对 URL，但某些解析路径
          // 可能返回相对路径，需双重校验。
          if (tocRule.chapterScope == 'bookDir' && baseUrl.isNotEmpty) {
            final prefix = _bookDirPrefix(baseUrl);
            if (prefix != null) {
              final absPrefix = '$prefix/';
              // 绝对 URL 前缀匹配
              if (bookChapter.url.startsWith(absPrefix)) {
                // 同一书 → 保留
              } else {
                // 相对路径兜底：从 baseUrl 和 chapterUrl 分别提取 /book_N 段比较
                final relMatch = _isSameBookDir(baseUrl, bookChapter.url);
                if (!relMatch) continue;
              }
            }
          }

          // 对照 legado：vip/pay 仅对标题非空的条目求值（少一次规则执行）。
          if (bookChapter.title.isNotEmpty) {
            try {
              if (ruleIsVip.isNotEmpty) {
                final isVip = analyzeRule.getStringFromRules(ruleIsVip);
                if (isVip.toLowerCase() == 'true' || isVip == '1') {
                  bookChapter.isVip = true;
                }
              }
            } catch (_) {}

            try {
              if (ruleIsPay.isNotEmpty) {
                final isPay = analyzeRule.getStringFromRules(ruleIsPay);
                if (isPay.toLowerCase() == 'true' || isPay == '1') {
                  bookChapter.isPay = true;
                }
              }
            } catch (_) {}

            // URL 去重：挡掉"最新章节预览"等重复收录；baseUrl 兜底条目
            // （无真实 URL 的卷/占位章节）不参与去重，避免多条被折叠成一条。
            if (bookChapter.url == baseUrl || seenUrls.add(bookChapter.url)) {
              chapters.add(bookChapter);
            }
          }
        } catch (_) {
          // 跳过坏条目，继续解析后续元素。
        }
      }
    } catch (_) {}

    // legado 的 `-` 前缀翻转作用于**合并后的整章列表**（多页目录时页序
    // 也要反转）。分页调用方传 applyReverse=false，由汇总层统一翻转。
    if (reverse && applyReverse) {
      final reversed = chapters.reversed.toList();
      chapters.clear();
      chapters.addAll(reversed);
    }

    // 汇总日志：解析出的章节数与首章信息（目录为空时据此判断是
    // 「规则未命中」还是「命中但被过滤/URL为空」）。
    if (chapters.isEmpty) {
      AppLog.instance.w('[书源目录] 解析出 0 章: 源=${bookSource.bookSourceName} '
          '规则=$listRule（元素存在但章节为空，多为 chapterUrl 规则未命中）');
    } else {
      final first = chapters.first;
      final firstUrl =
          first.url.length > 60 ? '${first.url.substring(0, 60)}…' : first.url;
      AppLog.instance.d('[书源目录] 源=${bookSource.bookSourceName} '
          '共${chapters.length}章 首章=[${first.title}] url=$firstUrl');
    }

    for (int i = 0; i < chapters.length; i++) {
      chapters[i].index = i;
    }

    // preUpdateJs 是「更新目录前」执行的脚本（legado WebBook.runPreUpdateJs），
    // 由目录抓取方在请求目录页之前调用；解析阶段不再二次执行。
    // formatJs 不在这里执行：legado 在合并/去重/倒序/重编号之后做一次
    // 全局遍历（见 [applyFormatJs]），分页解析阶段不能提前消耗 gInt 状态。
    return chapters;
  }

  /// legado ruleToc.formatJs：整份目录合并、去重、倒序、重编号后单次执行。
  ///
  /// 绑定 `gInt`（整轮只初始化一次，脚本内自增跨章节延续）、`index`（1 起）、
  /// `chapter`（章节实体字段快照）、`title`；脚本返回值非空时覆盖章节标题。
  static void applyFormatJs(
      List<XiaoshuoBookChapter> chapters, String? formatJs) {
    if (formatJs == null || formatJs.trim().isEmpty || chapters.isEmpty) {
      return;
    }
    // 与其余规则共用「按源池化」的 JS 运行时（jsLib 全局可用、同源跨阶段
    // 复用），无活动上下文时退化为独立实例。
    final engine = JsEngine.forSource(ShuyuanSourceContext.current?.sourceId);
    final bindings = <String, dynamic>{'gInt': 0};
    for (var i = 0; i < chapters.length; i++) {
      final ch = chapters[i];
      bindings['index'] = i + 1;
      // legado 绑定的是 BookChapter 实体（字段名 title/url/tag/...）；
      // name 是旧别名，两者都提供以兼容不同写法。
      bindings['chapter'] = <String, dynamic>{
        'name': ch.title,
        'title': ch.title,
        'url': ch.url,
        'tag': ch.tag,
        'index': i,
        'isVolume': ch.isVolume,
        'isVip': ch.isVip,
        'isPay': ch.isPay,
        'bookUrl': ch.bookUrl,
      };
      bindings['title'] = ch.title;
      try {
        final result = engine.eval(formatJs, bindings: bindings);
        if (result.isNotEmpty) {
          ch.title = result;
        }
      } catch (_) {
        // formatJs 失败不影响目录列表（保留原标题）
      }
      // gInt 只在首轮注入：后续轮若重复注入会重置脚本内的自增状态。
      bindings.remove('gInt');
    }
  }

  /// 计算目录页 URL 所属书籍目录前缀（不含结尾斜杠）。
  ///
  /// 例：`https://m.biqubu3.com/book_12345/` 或
  /// `https://m.biqubu3.com/book_12345/index.html`
  /// → `https://m.biqubu3.com/book_12345`。
  /// 调用方比对时追加 "/" 以区分 `book_123` 与 `book_1234567` 这类相邻 ID。
  /// 若无法解析则返回 null（此时不过滤，保持原行为）。
  static String? _bookDirPrefix(String url) {
    try {
      final u = Uri.parse(url);
      var path = u.path;
      if (path.endsWith('/')) path = path.substring(0, path.length - 1);
      final dot = path.lastIndexOf('.');
      final slash = path.lastIndexOf('/');
      // 若路径以文件结尾（如 index.html），取其所在目录
      if (dot > slash) path = path.substring(0, slash);
      if (path.isEmpty) return null;
      return '${u.scheme}://${u.host}$path';
    } catch (_) {
      return null;
    }
  }

  /// 从 URL 中提取 /book_NNNN 段（书籍目录标识），用于跨书过滤的相对路径
  /// 兜底比对。若 URL 中不含 /book_ 数字模式则返回 null（不判定为跨书）。
  ///
  /// 例：`/book_4656/1.html` → `book_4656`
  /// `/book_4656/` → `book_4656`
  /// `https://m.biqubu3.com/book_4656/1.html` → `book_4656`
  /// `/search.php` → null
  static String? _extractBookDirSegment(String url) {
    final match = RegExp(r'/book_(\d+)').firstMatch(url);
    return match?.group(0)?.substring(1); // 去掉前导 '/' → "book_4656"
  }

  /// 判断 [baseUrl]（目录页）与 [chapterUrl]（章节链接）是否属于同一书籍目录。
  /// 双重策略：先尝试绝对/相对路径的 /book_N 段比较；都失败则剔除（默认不过滤
  /// 不确定的链接，避免「最新章节预览」等跨书栏目中的非标准 URL 被误放行）。
  static bool _isSameBookDir(String baseUrl, String chapterUrl) {
    final baseSeg = _extractBookDirSegment(baseUrl);
    final chSeg = _extractBookDirSegment(chapterUrl);
    if (baseSeg != null && chSeg != null) return baseSeg == chSeg;
    // 无法从任一 URL 提取 book_N 段 → 剔除（安全侧：宁可少收录也不混入跨书链接）
    return false;
  }
}
