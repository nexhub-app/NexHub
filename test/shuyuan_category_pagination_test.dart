/// 书源发现分类页翻页语义（legado ExploreShowViewModel 对等）：
/// - 跨页按 bookUrl（MediaItem.id）去重，保留首次出现；
/// - 空页 / 全重复页自动连翻，最多 3 页（间隔 500ms），之后视为到底。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexhub/core/models/category_entry.dart';
import 'package:nexhub/core/models/media_item.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/core/services/source_repository.dart';
import 'package:nexhub/core/widgets/online_content_list_screen.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

PluginConfig _source() =>
    ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(<String, dynamic>{
      'bookSourceName': '翻页测试源',
      'bookSourceUrl': 'https://paging.test',
      'bookSourceType': 0,
      'enabled': true,
      'exploreUrl': '分类一::/cat1',
      'ruleExplore': <String, dynamic>{
        'bookList': '#list li.item',
        'name': 'a@text',
        'bookUrl': 'a@href',
      },
    }));

MediaItem _item(String id, {String? title}) =>
    MediaItem(id: id, title: title ?? '书$id');

Widget _app({
  required List<MediaItem> Function(int page) pageItems,
  required List<int> calls,
  String categoryId = '/cat1',
}) {
  final source = _source();
  return ChangeNotifierProvider<SourceRepository>.value(
    value: SourceRepository.fromJsonList(const <Map<String, dynamic>>[]),
    child: MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: OnlineContentListScreen(
        title: '翻页测试',
        sources: <PluginConfig>[source],
        fetchItems: (
          PluginConfig s, {
          String? category,
          int page = 1,
          String? extractedUrl,
          String? renderedHtml,
          Map<String, String> vars = const <String, String>{},
        }) async {
          calls.add(page);
          return pageItems(page);
        },
        fetchCategories: (PluginConfig s) async => <CategoryEntry>[
          CategoryEntry(id: categoryId, title: '分类一'),
        ],
        onItemTap: (MediaItem item, String? heroTag) {},
      ),
    ),
  );
}

Future<void> _pumpSteps(
  WidgetTester tester,
  int steps, {
  Duration step = const Duration(milliseconds: 300),
}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(step);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('appendUniqueCategoryItems（legado 跨页 bookUrl 去重）', () {
    test('跨页重复只保留首次出现，返回新增数量', () {
      final target = <MediaItem>[_item('/book/a'), _item('/book/b')];
      final added = appendUniqueCategoryItems(target, <MediaItem>[
        _item('/book/a'),
        _item('/book/c'),
        _item('/book/b'),
      ]);
      expect(added, 1);
      expect(target.map((e) => e.id).toList(), <String>[
        '/book/a',
        '/book/b',
        '/book/c',
      ]);
    });

    test('页内重复同样去重', () {
      final target = <MediaItem>[];
      final added = appendUniqueCategoryItems(target, <MediaItem>[
        _item('/book/a'),
        _item('/book/a'),
      ]);
      expect(added, 1);
      expect(target.map((e) => e.id).toList(), <String>['/book/a']);
    });

    test('id 为空的空壳条目按 heroKey 稳定兜底去重', () {
      final target = <MediaItem>[
        const MediaItem(id: '', title: '同名', detailUrl: '/same'),
      ];
      final added = appendUniqueCategoryItems(target, <MediaItem>[
        const MediaItem(id: '', title: '同名', detailUrl: '/same'),
        const MediaItem(id: '', title: '异名', detailUrl: '/same'),
      ]);
      expect(added, 1);
      expect(target.map((e) => e.title).toList(), <String>['同名', '异名']);
    });
  });

  group('书源分类页自动连翻', () {
    testWidgets('首屏空页自动翻到有内容页并展示条目', (tester) async {
      final calls = <int>[];
      await tester.pumpWidget(_app(
        calls: calls,
        pageItems: (page) => switch (page) {
          1 => <MediaItem>[],
          2 => <MediaItem>[],
          3 => <MediaItem>[_item('/book/c')],
          _ => <MediaItem>[],
        },
      ));
      await _pumpSteps(tester, 20);

      // 页 1 空页触发一次冷启动重试（1→1），随后自动连翻到页 2、页 3。
      expect(calls, containsAllInOrder(<int>[1, 2, 3]));
      expect(find.text('书/book/c'), findsOneWidget);
    });

    testWidgets('连续空页最多连翻 3 页后停止，不再请求后续页', (tester) async {
      final calls = <int>[];
      await tester.pumpWidget(_app(
        calls: calls,
        pageItems: (page) => <MediaItem>[],
      ));
      await _pumpSteps(tester, 24);

      // 页 1（含一次冷启动重试）→ 页 2 → 页 3，之后视为到底。
      expect(calls, containsAllInOrder(<int>[1, 2, 3]));
      expect(calls, isNot(contains(4)));
    });
  });

  group('supportsPageSelectionRuleUrl（legado canJumpPage 静态判定）', () {
    test('表达式 / 脚本 / 备选页语法可跳页', () {
      expect(supportsPageSelectionRuleUrl('/cat?page={{page}}'), isTrue);
      expect(supportsPageSelectionRuleUrl('/cat?page={{ page + 1 }}'), isTrue);
      expect(
          supportsPageSelectionRuleUrl('/cat?p=<js>"/x?p="+page</js>'), isTrue);
      expect(supportsPageSelectionRuleUrl('@js:"/cat?p="+page'), isTrue);
      expect(supportsPageSelectionRuleUrl('@js:cond ? page : 1'), isTrue);
      expect(supportsPageSelectionRuleUrl('/list<,_2,_3>.html'), isTrue);
      expect(supportsPageSelectionRuleUrl('/cat?p=<page>'), isTrue);
      expect(supportsPageSelectionRuleUrl('/cat?p=《page》'), isTrue);
    });

    test('非页码引用不触发（属性访问 / 对象键 / 本地声明 / 字符串）', () {
      expect(supportsPageSelectionRuleUrl('/cat1'), isFalse);
      expect(supportsPageSelectionRuleUrl('   '), isFalse);
      expect(supportsPageSelectionRuleUrl('/cat?p={{key}}'), isFalse);
      expect(supportsPageSelectionRuleUrl('/cat?p={{obj.page}}'), isFalse);
      expect(supportsPageSelectionRuleUrl('@js:obj.page'), isFalse);
      expect(supportsPageSelectionRuleUrl('@js:{page: 1}'), isFalse);
      expect(supportsPageSelectionRuleUrl('@js:{"page": 1}'), isFalse);
      expect(supportsPageSelectionRuleUrl('@js:"page".length'), isFalse);
      expect(supportsPageSelectionRuleUrl('@js:var page = 3; "/cat?p=" + page'),
          isFalse);
    });
  });

  group('书源分类页码直跳', () {
    testWidgets('分类 URL 不含页码语法时不显示页码入口', (tester) async {
      final calls = <int>[];
      await tester.pumpWidget(_app(
        calls: calls,
        pageItems: (page) => <MediaItem>[_item('/book/p$page')],
      ));
      await _pumpSteps(tester, 20);

      expect(find.byTooltip('跳转页码'), findsNothing);
    });

    testWidgets('显示当前页码，跳页后请求目标页并更新页码', (tester) async {
      final calls = <int>[];
      await tester.pumpWidget(_app(
        categoryId: '/cat1?page={{page}}',
        calls: calls,
        pageItems: (page) => <MediaItem>[_item('/book/p$page')],
      ));
      await _pumpSteps(tester, 20);

      expect(calls, <int>[1]);
      expect(find.byTooltip('跳转页码'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('1')),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('跳转页码'));
      await _pumpSteps(tester, 3);
      await tester.enterText(find.byType(TextField), '3');
      await tester.tap(find.text('确认'));
      await _pumpSteps(tester, 20);

      expect(calls, contains(3));
      expect(find.text('书/book/p3'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('3')),
        findsOneWidget,
      );
    });
  });
}
