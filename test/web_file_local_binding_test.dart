/// 文件类书源下载绑定：本地条目来源三元组、书籍归组、源文件匹配与
/// 「开始阅读」所指条目的选择规则，以及入库时字段保留。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/local/local_content_manager.dart';
import 'package:nexhub/features/shuyuan/analyze/web_file_local_binding.dart';
import 'package:shared_preferences/shared_preferences.dart';

LocalContentEntry _entry({
  String id = '/books/a.txt',
  String title = 'A',
  int addedAt = 1,
  String? sourceId,
  String? contentId,
  String? fileUrl,
  String? author,
}) =>
    LocalContentEntry(
      id: id,
      title: title,
      path: id,
      kind: LocalMediaKind.text,
      addedAt: addedAt,
      originSourceId: sourceId,
      originContentId: contentId,
      originFileUrl: fileUrl,
      author: author,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('来源绑定字段', () {
    test('JSON 往返保留来源三元组与作者', () {
      final LocalContentEntry e = _entry(
        sourceId: 'src-1',
        contentId: 'https://x.test/book/1',
        fileUrl: 'https://x.test/f/a.txt',
        author: '作者',
      );
      final LocalContentEntry back =
          LocalContentEntry.fromJson(e.toJson());
      expect(back.originSourceId, 'src-1');
      expect(back.originContentId, 'https://x.test/book/1');
      expect(back.originFileUrl, 'https://x.test/f/a.txt');
      expect(back.author, '作者');
    });

    test('copyWith 保留来源绑定', () {
      final LocalContentEntry e = _entry(
        sourceId: 's',
        contentId: 'c',
        fileUrl: 'u',
      );
      final LocalContentEntry renamed = e.copyWith(title: '新名');
      expect(renamed.title, '新名');
      expect(renamed.originSourceId, 's');
      expect(renamed.originFileUrl, 'u');
    });

    test('book 归组按 sourceId + contentId 过滤', () {
      final List<LocalContentEntry> all = <LocalContentEntry>[
        _entry(id: '/a', sourceId: 's1', contentId: 'c1'),
        _entry(id: '/b', sourceId: 's1', contentId: 'c2'),
        _entry(id: '/c', sourceId: 's2', contentId: 'c1'),
        _entry(id: '/d'),
      ];
      final List<LocalContentEntry> bound = boundWebBookEntries(
        all,
        sourceId: 's1',
        contentId: 'c1',
      );
      expect(bound.map((LocalContentEntry e) => e.id), <String>['/a']);
    });

    test('源文件匹配：同 URL 取最近导入的一条，未下载返回 null', () {
      final List<LocalContentEntry> bound = <LocalContentEntry>[
        _entry(id: '/old', addedAt: 5, fileUrl: 'u1'),
        _entry(id: '/new', addedAt: 9, fileUrl: 'u1'),
        _entry(id: '/other', addedAt: 99, fileUrl: 'u2'),
      ];
      expect(localEntryForWebFile(bound, 'u1')!.id, '/new');
      expect(localEntryForWebFile(bound, 'u3'), isNull);
    });
  });

  group('开始阅读所指条目', () {
    test('最近读过优先于最近下载', () {
      final List<LocalContentEntry> bound = <LocalContentEntry>[
        _entry(id: '/a', addedAt: 10),
        _entry(id: '/b', addedAt: 20),
      ];
      final LocalContentEntry? active = activeWebBookEntry(
        bound,
        viewedAt: (String id) => id == '/a' ? 100 : 0,
      );
      expect(active!.id, '/a');
    });

    test('都没读过取最近下载', () {
      final List<LocalContentEntry> bound = <LocalContentEntry>[
        _entry(id: '/a', addedAt: 10),
        _entry(id: '/b', addedAt: 20),
      ];
      final LocalContentEntry? active =
          activeWebBookEntry(bound, viewedAt: (_) => 0);
      expect(active!.id, '/b');
    });

    test('无本地书返回 null', () {
      expect(activeWebBookEntry(<LocalContentEntry>[], viewedAt: (_) => 1),
          isNull);
    });
  });

  group('LocalContentManager.add 保留绑定', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('新条目入库保留作者与来源三元组', () async {
      final LocalContentManager mgr = LocalContentManager();
      await mgr.add(_entry(
        id: '/books/new.txt',
        addedAt: 7,
        sourceId: 's',
        contentId: 'c',
        fileUrl: 'u',
        author: '作者',
      ));
      final LocalContentEntry stored = mgr.items.single;
      expect(stored.author, '作者');
      expect(stored.originSourceId, 's');
      expect(stored.originContentId, 'c');
      expect(stored.originFileUrl, 'u');
    });

    test('同路径旧条目重新下载时补绑来源并保留作者', () async {
      final LocalContentManager mgr = LocalContentManager();
      await mgr.add(_entry(id: '/books/same.txt', addedAt: 7));
      await mgr.add(_entry(
        id: '/books/same.txt',
        addedAt: 8,
        sourceId: 's',
        contentId: 'c',
        fileUrl: 'u',
        author: '作者',
      ));
      final LocalContentEntry stored = mgr.items.single;
      expect(stored.addedAt, 7, reason: '入库时间保持首次导入');
      expect(stored.author, '作者');
      expect(stored.originSourceId, 's');
      expect(stored.originContentId, 'c');
      expect(stored.originFileUrl, 'u');
    });
  });
}
