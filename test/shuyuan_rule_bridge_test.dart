/// 规则桥接线测试：
/// - `java.getElements / getElement / getString` 的重放求值 +
///   JS 侧 jsoup 风格包装（size/get/text/attr）；
/// - `java.setContent` / 带内容参数求值 / 取值分支多轮收敛；
/// - `@put` 的两种写法（legado 标准无括号 / 历史带括号）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_rule.dart';
import 'package:nexhub/features/shuyuan/analyze/source_context.dart';
import 'package:nexhub/features/shuyuan/analyze/source_rule.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book_chapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AnalyzeRule rule() => AnalyzeRule()
    ..setContent('<div class="i"><a href="/a">甲</a><a href="/b">乙</a></div>')
    ..setBaseUrl('https://x.test/');

  group('java.getElements / getElement / getStringList', () {
    test('getElements 返回可 size/get/text/attr 的列表', () {
      final r = rule();
      expect(r.getString("@js:java.getElements('.i a').size()"), '2');
      expect(r.getString("@js:java.getElements('.i a').get(1).text()"), '乙');
      expect(
          r.getString("@js:java.getElements('.i a').get(0).attr('href')"), '/a');
      expect(r.getString("@js:java.getElements('.i a').text()"), '甲\n乙');
    });

    test('getElement 取首个元素', () {
      final r = rule();
      expect(r.getString("@js:java.getElement('.i a').text()"), '甲');
    });

    test('getStringList 产出可直接使用的 JS 数组', () {
      final r = rule();
      expect(r.getString("@js:java.getStringList('.i a@text').length"), '2');
      expect(r.getString("@js:java.getStringList('.i a@text')[1]"), '乙');
    });

    test('getStringList 返回带 Java List 方法的列表（legado List<String>）', () {
      final r = rule();
      expect(
          r.getString("@js:var l=java.getStringList('.i a@text'); "
              "l.size()+'|'+l.get(1)+'|'+l.isEmpty()+'|'+l.toArray().length"),
          '2|乙|false|2');
    });

    test('规则未命中时返回空列表 / null，不抛错', () {
      final r = rule();
      expect(r.getString("@js:java.getElements('.nope').size()"), '0');
      // eval 会把字符串 "null" 归一化成空串，故用布尔判断而非 String(null)。
      expect(r.getString("@js:java.getElement('.nope') === null ? 'YES' : 'NO'"),
          'YES');
    });
  });

  group('元素包装的 jsoup 接口（outerHtml/select/children/abs:）', () {
    test('outerHtml 返回外层 HTML（legado Element.outerHtml）', () {
      final r = rule();
      expect(r.getString("@js:java.getElement('.i a').outerHtml()"),
          '<a href="/a">甲</a>');
    });

    test('select 含根自身，结果元素保留 abs: 绝对化', () {
      final r = rule();
      expect(r.getString("@js:java.getElement('.i').select('.i').size()"), '1');
      expect(
          r.getString("@js:java.getElement('.i').select('a').get(1).text()"),
          '乙');
      expect(r.getString("@js:java.getElement('.i a').attr('abs:href')"),
          'https://x.test/a');
      // 单元素 select 自身（jsoup Element.select 包含根匹配）。
      expect(r.getString("@js:java.getElement('.i a').select('a').size()"), '1');
    });

    test('children 返回直接子元素并可用 abs: 属性', () {
      final r = rule();
      expect(r.getString("@js:java.getElement('.i').children().size()"), '2');
      expect(
          r.getString("@js:java.getElement('.i').children().first().text()"),
          '甲');
      expect(
          r.getString(
              "@js:java.getElement('.i').children().get(1).attr('abs:href')"),
          'https://x.test/b');
    });

    test('相对路径按元素所在页面目录绝对化', () {
      final r = AnalyzeRule()
        ..setContent('<div class="i"><img src="imgs/x.png"></div>')
        ..setBaseUrl('https://x.test/dir/page.html');
      expect(r.getString("@js:java.getElement('.i img').attr('abs:src')"),
          'https://x.test/dir/imgs/x.png');
      expect(
          r.getString("@js:java.getElement('.i img').attr('src')"),
          'imgs/x.png');
    });
  });

  group('book 注入对象', () {
    test('读取当前书字段', () {
      final book = XiaoshuoBook(bookUrl: 'https://x.test/b', name: '书名');
      book.author = '作者甲';
      final ctx = ShuyuanSourceContext('book-read');
      final r = AnalyzeRule(book: book)..setContent('<p>x</p>');

      ShuyuanSourceContext.run(ctx, () {
        expect(r.getString('@js:book.name'), '书名');
        expect(r.getString('@js:book.author'), '作者甲');
        expect(r.getString('@js:book.bookUrl'), 'https://x.test/b');
      });
    });

    test('tocUrl/wordCount/type/origin 可读，type 为数值', () {
      final book = XiaoshuoBook(bookUrl: 'https://x.test/b', name: '书名');
      book
        ..tocUrl = 'https://x.test/b/catalog'
        ..wordCount = '12万'
        ..type = 2;
      final ctx = ShuyuanSourceContext('book-fields')
        ..bookSourceUrl = 'https://x.test/source.json';
      final r = AnalyzeRule(book: book)..setContent('<p>x</p>');

      ShuyuanSourceContext.run(ctx, () {
        expect(r.getString('@js:book.tocUrl'), 'https://x.test/b/catalog');
        expect(r.getString('@js:book.wordCount'), '12万');
        expect(r.getString('@js:book.type === 2 ? "IMG" : "OTHER"'), 'IMG');
        expect(r.getString('@js:book.origin'), 'https://x.test/source.json');
      });
    });

    test('脚本赋值回写当前书（空值不覆盖）', () {
      final book = XiaoshuoBook(bookUrl: 'https://x.test/b', name: '原标题');
      book.author = '原作者';
      final ctx = ShuyuanSourceContext('book-write');
      final r = AnalyzeRule(book: book)..setContent('<p>x</p>');

      ShuyuanSourceContext.run(ctx, () {
        r.getString("@js:book.name = '新标题'; book.name");
        expect(book.name, '新标题');
        // 空串不覆盖已有值（正文阶段的空壳书不能抹掉详情字段）。
        expect(r.getString("@js:book.author = ''; book.author"), '');
        expect(book.author, '原作者');
      });
    });
  });

  group('java 规则桥重放', () {
    test('动态规则（变量拼串）可求值', () {
      final r = rule();
      expect(r.getString("@js:var rule = '.i a@text'; java.getStringList(rule).length"),
          '2');
      expect(r.getString("@js:var sel = '.i a'; java.getString(sel + '@href')"),
          '/a\n/b');
    });

    test('带内容参数求值（getString/getStringList 第 2 参）', () {
      final r = rule();
      const html = '<div class="z"><a href="/z">丙</a></div>';
      expect(
          r.getString("@js:java.getString('.z a@text', '$html')"), '丙');
      expect(
          r.getString("@js:java.getStringList('.z a@href', '$html').length"),
          '1');
    });

    test('setContent 切换根内容，脚本内与脚本后都生效', () {
      final r = rule();
      expect(
          r.getString("@js:java.setContent('<div class=\"j\"><a href=\"/c\">丙</a></div>'); "
              "java.getString('.j a@text')"),
          '丙');
      // setContent 与 legado 一致：脚本结束后规则实例内容已切换。
      expect(r.getString('.j a@text'), '丙');
    });

    test('取值分支脚本多轮收敛', () {
      final r = rule();
      expect(
          r.getString("@js:var els = java.getElements('.i a'); "
              "els.size() > 0 ? els.get(1).text() : '空'"),
          '乙');
    });

    test('元素包装作为内容参数（近似其内部 HTML）', () {
      final r = rule();
      expect(
          r.getString("@js:var el = java.getElement('.i'); "
              "java.getString('a@href', el)"),
          '/a\n/b');
    });
  });

  group('变量读取链与实体还原', () {
    test('get 优先级：chapter → book → 本轮 put → 源变量', () {
      final ctx = ShuyuanSourceContext('get-chain');
      ctx.sourceVars['k'] = '源';
      ctx.sourceVars['onlySrc'] = 'S';
      ShuyuanSourceContext.run(ctx, () {
        final book = XiaoshuoBook(bookUrl: 'https://x.test/b', name: '书')
          ..putVariable('k', '书')
          ..putVariable('onlyBook', 'B');
        final chapter = XiaoshuoBookChapter(
          bookUrl: 'https://x.test/b',
          url: 'https://x.test/1',
          title: '章',
        )..putVariable('k', '章');
        final r = AnalyzeRule(book: book, chapter: chapter)
          ..setContent('<p>x</p>');
        expect(r.get('k'), '章');
        chapter.variableMap.remove('k');
        expect(r.get('k'), '书');
        expect(r.get('onlyBook'), 'B');
        expect(r.get('onlySrc'), 'S');
        expect(r.get('missing'), '');
        // @get 变量引用走同一链路。
        expect(r.getString('@get:{onlySrc}'), 'S');
      });
    });

    test('getString 结果做 HTML 实体还原（数字 + 命名全表）', () {
      final r = rule();
      expect(r.getString("@js:'&nbsp;&hellip;&#65;&#x42;&mdash;'"),
          '\u00A0…AB—');
      expect(r.getString("@js:'&amp;lt;&unknown;'"), '&lt;&unknown;');
    });
  });

  group('cookie 注入对象', () {
    test('setWebCookie 并入请求 cookie 罐', () {
      final ctx = ShuyuanSourceContext('cookie-web');
      ShuyuanSourceContext.run(ctx, () {
        final r = AnalyzeRule()..setContent('<p>x</p>');
        r.getString("@js:cookie.setWebCookie('https://a.test/x', 'sid=42')");
        expect(ctx.cookies['sid']?['value'], '42');
        expect(ctx.cookies['sid']?['host'], 'a.test');
        expect(r.getString("@js:cookie.getKey('https://a.test/', 'sid')"), '42');
      });
    });
  });

  group('@put 解析', () {
    test('无括号（legado 标准写法）', () {
      final r = SourceRule('@put:{bid:"h1@text"} tag.a@text');
      expect(r.putMap['bid'], 'h1@text');
      expect(r.rule.contains('@put'), isFalse);
    });

    test('带括号（历史写法）仍兼容', () {
      final r = SourceRule('@put:({bid:"h1@text"}) tag.a@text');
      expect(r.putMap['bid'], 'h1@text');
      expect(r.rule.contains('@put'), isFalse);
    });

    test('多个 @put 依次提取', () {
      final r = SourceRule('@put:{a:"x"}@put:{b:"y"} .list');
      expect(r.putMap, {'a': 'x', 'b': 'y'});
      expect(r.rule.contains('@put'), isFalse);
    });

    test('JSON 转义值还原（引号/换行/逗号）', () {
      final r = SourceRule(r'@put:{a:"x\"y",b:"l1\nl2",c:"p,q"} .z');
      expect(r.putMap['a'], 'x"y');
      expect(r.putMap['b'], 'l1\nl2');
      expect(r.putMap['c'], 'p,q');
    });
  });
}
