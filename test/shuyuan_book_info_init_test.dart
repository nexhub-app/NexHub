/// legado BookInfo 对齐：`ruleBookInfo.init` 的求值结果（含 JS 返回的
/// JSON 文本）必须成为后续字段规则的求值内容；JS 单值规则 `getElement`
/// 原样返回（不得按列表规则截断成空）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/analyze/analyze_rule.dart';
import 'package:nexhub/features/shuyuan/model/book_source.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book.dart';
import 'package:nexhub/features/shuyuan/web_book/book_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  test('getElement：JS 规则返回 JSON 文本时原样返回该文本', () {
    final rule = AnalyzeRule()
      ..setContent('{"code":"0","data":{"bookName":"测试书"}}');
    final init =
        rule.getElement('<js>JSON.stringify(JSON.parse(result).data)</js>');
    expect(init, isA<String>());
    expect(init as String, contains('测试书'));
  });

  test('getElement：JS 规则返回对象时原样返回对象', () {
    final rule = AnalyzeRule()..setContent('{"a":{"b":"值"}}');
    final obj = rule.getElement('<js>JSON.parse(result).a</js>');
    expect(obj, isA<Map>());
    expect((obj as Map)['b'], '值');
  });

  test('BookInfo：init 返回 JSON 文本后 name/tocUrl 在该文本上求值', () {
    final source = XiaoshuoBookSource.fromJson(<String, dynamic>{
      'bookSourceName': 'init-test',
      'bookSourceUrl': 'https://x.test',
      'bookSourceType': 0,
      'ruleBookInfo': <String, dynamic>{
        'init':
            '<js>var o=JSON.parse(result).data; JSON.stringify({bookName:o.bookName,bookId:o.bookId})</js>',
        'name': r'$.bookName',
        'tocUrl': '<js>"/api/toc?bookId=" + JSON.parse(result).bookId</js>',
      },
    });
    final book = XiaoshuoBook(bookUrl: 'https://x.test/book/1', name: '');
    BookInfo.analyzeBookInfo(
      bookSource: source,
      book: book,
      baseUrl: 'https://x.test/book/1',
      redirectUrl: 'https://x.test/book/1',
      body: '{"code":"0","data":{"bookName":"测试书","bookId":"1001"}}',
    );
    expect(book.name, '测试书');
    expect(book.tocUrl, 'https://x.test/api/toc?bookId=1001');
  });
}
