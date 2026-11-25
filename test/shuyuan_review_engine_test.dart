/// 段评引擎（书源 `ruleReview`）回归：规则模型往返、列表三条规则按序号
/// 对齐、正文片段净化、缺省规则不丢条目。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:nexhub/core/models/source_review.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_url.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';
import 'package:nexhub/features/shuyuan/model/rule_review.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';
import 'package:nexhub/features/shuyuan/web_book/book_review.dart';

const String _body = '''
<div id="list">
  <div class="item">
    <img src="https://img.test/a.jpg">
    <span class="time">1 分钟前</span>
    <p class="text">第一条&amp;段评</p>
  </div>
  <div class="item">
    <img src="https://img.test/b.jpg">
    <span class="time">2 分钟前</span>
    <p class="text">第二条<br>段评</p>
  </div>
  <div class="item">
    <span class="time">3 分钟前</span>
    <p class="text">第三条段评</p>
  </div>
</div>
''';

void main() {
  group('ReviewRule 模型', () {
    test('解析十个字段并可往返', () {
      final rule = ReviewRule.fromJson(<String, dynamic>{
        'reviewUrl': 'https://api.test/reviews?page={{page}}',
        'avatarRule': '#list .item img@src',
        'contentRule': '#list .item .text@text',
        'postTimeRule': '#list .item .time@text',
        'reviewQuoteUrl': r'https://api.test/quotes?id={{$.index}}',
        'voteUpUrl': 'https://api.test/vote/up',
        'voteDownUrl': 'https://api.test/vote/down',
        'postReviewUrl': 'https://api.test/post,{"method":"POST","body":"t={{key}}"}',
        'postQuoteUrl': r'https://api.test/quote?id={{$.index}}&t={{key}}',
        'deleteUrl': r'https://api.test/delete?id={{$.index}}',
        'paragraphRule': '#list .item .para@data-index',
        'voteUpCountRule': '#list .item .up@text',
        'voteDownCountRule': '#list .item .down@text',
      });
      expect(rule.hasList, isTrue);
      expect(rule.canPost, isTrue);
      expect(rule.canVote, isTrue);
      expect(rule.canDelete, isTrue);
      expect(rule.hasParagraphAnchor, isTrue);
      final round = ReviewRule.fromJson(rule.toJson());
      expect(round.contentRule, rule.contentRule);
      expect(round.postQuoteUrl, rule.postQuoteUrl);
    });

    test('缺省字段不影响能力判定', () {
      final rule = ReviewRule.fromJson(<String, dynamic>{
        'reviewUrl': 'https://api.test/reviews',
      });
      expect(rule.hasList, isFalse); // 缺 contentRule
      expect(rule.canPost, isFalse);
      expect(rule.canVote, isFalse);
    });
  });

  group('书源 ruleReview 装载', () {
    test('对象形态与 JSON 字符串形态都能解析', () {
      final fromObject = XiaoshuoBookSource.fromJson(<String, dynamic>{
        'bookSourceUrl': 'https://src.test',
        'bookSourceName': 'review-object',
        'ruleReview': <String, dynamic>{
          'reviewUrl': 'https://api.test/reviews',
          'contentRule': '#list .item@text',
        },
      });
      expect(fromObject.getReviewRule().hasList, isTrue);
      expect(fromObject.toJson()['ruleReview'], isA<Map<String, dynamic>>());

      final fromString = XiaoshuoBookSource.fromJson(<String, dynamic>{
        'bookSourceUrl': 'https://src.test',
        'bookSourceName': 'review-string',
        'ruleReview': '{"reviewUrl":"https://api.test/r","contentRule":"#x@text"}',
      });
      expect(fromString.getReviewRule().contentRule, '#x@text');
    });
  });

  group('段落锚点（`{{paragraph}}` / paragraphRule）', () {
    // 注：`{{paragraph}}` 走 JS 求值，flutter_js 在 VM 测试环境里不加载，
    // 这里只能验证 Dart 侧短路的占位符不受额外绑定影响；段落序号的真机行为
    // 由 device test 覆盖（`{{chapter.url}}` 同理）。
    test('额外绑定不影响 page/key 展开', () {
      final au = AnalyzeUrl(
        url: 'https://h.test/reviews?p={{page}}&k={{key}}',
        baseUrl: 'https://h.test/',
        page: 2,
        key: 'ab',
        extraBindings: <String, dynamic>{'paragraph': 3},
      );
      expect(au.url, 'https://h.test/reviews?p=2&k=ab');
    });

    test('paragraphRule 给条目打段号（含非纯数字文本）', () {
      final reviews = BookReview.parseReviews(
        rule: ReviewRule(
          reviewUrl: 'https://api.test/reviews',
          contentRule: '#list .item .text@text',
          paragraphRule: '#list .item .para@data-index',
        ),
        body: '<div id="list">'
            '<div class="item"><p class="text">甲</p>'
            '<span class="para" data-index="0"></span></div>'
            '<div class="item"><p class="text">乙</p>'
            '<span class="para" data-index="3"></span></div>'
            '<div class="item"><p class="text">丙</p>'
            '<span class="para" data-index="第7段"></span></div>'
            '</div>',
        baseUrl: 'https://src.test/c/1.html',
        redirectUrl: 'https://src.test/c/1.html',
      );
      expect(reviews.map((r) => r.paragraph), <int?>[0, 3, 7]);
      expect(reviews[1].context['paragraph'], 3);
    });

    test('按段请求（源未给段号）时段号回落到请求段', () {
      final reviews = BookReview.parseReviews(
        rule: ReviewRule(
          reviewUrl: 'https://api.test/reviews',
          contentRule: '#list .item .text@text',
        ),
        body: _body,
        baseUrl: 'https://src.test/c/1.html',
        redirectUrl: 'https://src.test/c/1.html',
        defaultParagraph: 5,
      );
      expect(reviews.every((r) => r.paragraph == 5), isTrue);
    });

    test('未声明 paragraphRule 且未指定段时条目无锚点', () {
      final reviews = BookReview.parseReviews(
        rule: ReviewRule(
          reviewUrl: 'https://api.test/reviews',
          contentRule: '#list .item .text@text',
        ),
        body: _body,
        baseUrl: 'https://src.test/c/1.html',
        redirectUrl: 'https://src.test/c/1.html',
      );
      expect(reviews.every((r) => r.paragraph == null), isTrue);
    });
  });

  group('赞/踩计数解析', () {
    test('计数规则按序号对齐，取首个数字', () {
      final reviews = BookReview.parseReviews(
        rule: ReviewRule(
          reviewUrl: 'https://api.test/reviews',
          contentRule: '.rv .content@text',
          voteUpCountRule: '.rv .up@text',
          voteDownCountRule: '.rv .down@text',
        ),
        body: '<div class="rv"><div class="content">甲</div>'
            '<span class="up">赞 12</span><span class="down">0</span></div>'
            '<div class="rv"><div class="content">乙</div>'
            '<span class="up">3</span><span class="down">踩 2</span></div>',
        baseUrl: 'https://src.test/c/1.html',
        redirectUrl: 'https://src.test/c/1.html',
      );
      expect(reviews[0].voteUp, 12);
      expect(reviews[0].voteDown, 0);
      expect(reviews[1].voteUp, 3);
      expect(reviews[1].voteDown, 2);
    });
  });

  group('段评气泡计数（按段分组）', () {
    test('按段号聚合，章级条目不计入', () {
      final counts = BookReview.countByParagraph(<SourceReview>[
        SourceReview(content: 'a', paragraph: 0),
        SourceReview(content: 'b', paragraph: 0),
        SourceReview(content: 'c', paragraph: 3),
        SourceReview(content: 'd'),
      ]);
      expect(counts, <int, int>{0: 2, 3: 1});
    });
  });

  group('适配器显式字段映射（无 raw 的书源）', () {
    test('段评与 legado 扩展字段都进 selectors，运行期可读', () {
      const ShuyuanSource src = ShuyuanSource(
        bookSourceName: 'no-raw',
        bookSourceUrl: 'https://src.test',
        ruleReview: <String, dynamic>{
          'reviewUrl': 'https://api.test/reviews',
          'contentRule': '#list .item@text',
        },
        loginUrl: 'https://src.test/login',
        jsLib: 'var a=1;',
        coverDecodeJs: 'result',
        eventListener: true,
        customButton: true,
        weight: 3,
      );
      final cfg = ShuyuanAdapter.toPluginConfig(src);
      final Object? raw = cfg.selectors?['xiaoshuo'];
      expect(raw, isA<Map>());
      final Map<String, dynamic> sel = Map<String, dynamic>.from(raw! as Map);
      expect(sel['ruleReview'], isA<Map>());
      expect((sel['ruleReview'] as Map)['contentRule'], '#list .item@text');
      expect(sel['loginUrl'], 'https://src.test/login');
      expect(sel['jsLib'], 'var a=1;');
      expect(sel['coverDecodeJs'], 'result');
      expect(sel['eventListener'], isTrue);
      expect(sel['customButton'], isTrue);
      expect(sel['weight'], 3);

      // 再回灌成书源：引擎能读到段评规则。
      final XiaoshuoBookSource bs =
          ShuyuanSource.fromJson(sel).toBookSource();
      expect(bs.getReviewRule().hasList, isTrue);
    });
  });

  group('段号/赞数按序号对齐（属性值重复）', () {
    test('同段多条时属性值不能去重（否则段号错位）', () {
      // 6 条段评的 data-p 是 0,0,2,2,4,4；引擎默认会去重成 3 个值。
      const String body = '''
<div class="rv" data-p="0"><div class="content">甲</div><span class="up">2</span></div>
<div class="rv" data-p="0"><div class="content">乙</div><span class="up">1</span></div>
<div class="rv" data-p="2"><div class="content">丙</div><span class="up">0</span></div>
<div class="rv" data-p="2"><div class="content">丁</div><span class="up">4</span></div>
<div class="rv" data-p="4"><div class="content">戊</div><span class="up">0</span></div>
<div class="rv" data-p="4"><div class="content">己</div><span class="up">6</span></div>
''';
      final reviews = BookReview.parseReviews(
        rule: ReviewRule(
          reviewUrl: 'https://api.test/reviews',
          contentRule: '.rv .content@text',
          paragraphRule: '.rv@data-p',
          voteUpCountRule: '.up@text',
        ),
        body: body,
        baseUrl: 'https://src.test/c/1.html',
        redirectUrl: 'https://src.test/c/1.html',
      );
      expect(reviews.map((r) => r.content), <String>['甲', '乙', '丙', '丁', '戊', '己']);
      expect(reviews.map((r) => r.paragraph), <int?>[0, 0, 2, 2, 4, 4]);
      expect(reviews.map((r) => r.voteUp), <int>[2, 1, 0, 4, 0, 6]);
      expect(BookReview.countByParagraph(reviews), <int, int>{0: 2, 2: 2, 4: 2});
    });
  });

  group('段评列表解析', () {
    test('三条列表规则按序号对齐', () {
      final reviews = BookReview.parseReviews(
        rule: ReviewRule(
          reviewUrl: 'https://api.test/reviews',
          contentRule: '#list .item .text@text',
          avatarRule: '#list .item img@src',
          postTimeRule: '#list .item .time@text',
        ),
        body: _body,
        baseUrl: 'https://src.test/c/1.html',
        redirectUrl: 'https://src.test/c/1.html',
      );
      expect(reviews.length, 3);
      expect(reviews[0].content, '第一条&段评');
      expect(reviews[0].avatar, 'https://img.test/a.jpg');
      expect(reviews[0].postTime, '1 分钟前');
      // <br> 的空白归一由 Jsoup 文案决定（空格或换行），只断言两段都在。
      expect(reviews[1].content, contains('第二条'));
      expect(reviews[1].content, contains('段评'));
      expect(reviews[2].avatar, isEmpty); // 缺头像的条目保留
      expect(reviews.map((r) => r.index), <int>[0, 1, 2]);
    });

    test('头像相对地址按页面地址绝对化', () {
      final reviews = BookReview.parseReviews(
        rule: ReviewRule(
          reviewUrl: 'https://api.test/reviews',
          contentRule: '#list .item .text@text',
          avatarRule: '#list .item img@src',
        ),
        body: '<div id="list"><div class="item">'
            '<img src="/avatar/1.png"><p class="text">甲</p></div></div>',
        baseUrl: 'https://src.test/c/1.html',
        redirectUrl: 'https://src.test/c/1.html',
      );
      expect(reviews.single.avatar, 'https://src.test/avatar/1.png');
    });

    test('条目上下文可供动作模板读取', () {
      final reviews = BookReview.parseReviews(
        rule: ReviewRule(
          reviewUrl: 'https://api.test/reviews',
          contentRule: '#list .item .text@text',
        ),
        body: _body,
        baseUrl: 'https://src.test/c/1.html',
        redirectUrl: 'https://src.test/c/1.html',
      );
      final SourceReview first = reviews.first;
      expect(first.context['content'], '第一条&段评');
      expect(first.context['index'], 0);
    });

    test('缺内容规则直接返回空列表（不抛异常）', () {
      final reviews = BookReview.parseReviews(
        rule: ReviewRule(reviewUrl: 'https://api.test/reviews'),
        body: _body,
        baseUrl: 'https://src.test/c/1.html',
        redirectUrl: 'https://src.test/c/1.html',
      );
      expect(reviews, isEmpty);
    });
  });
}
