/// 书源身份对齐 legado：`bookSourceUrl` 精确字符串 = 主键。
///
/// legado `BookSource` 以 `bookSourceUrl` 为 @PrimaryKey、`@Insert(REPLACE)`；
/// 仅尾斜杠 / `#` 片段 / 非 ASCII 字符不同的源是**不同书源**，必须同时存在。
/// 旧 id 生成按 URL 归一化（去 scheme、非字母数字折成 `_`、截断 60 字符），
/// 不同源会撞成同一 PluginConfig.id，被 SourceRepository 按 id 覆盖 →
/// 在线列表缺源。本测试锁定修复后的入库身份语义。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/core/services/source_repository.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

PluginConfig _legado(String name, String url, {int type = 0}) {
  return ShuyuanAdapter.toPluginConfig(ShuyuanSource.fromJson(<String, dynamic>{
    'bookSourceName': name,
    'bookSourceUrl': url,
    'bookSourceType': type,
    'enabled': true,
    'searchUrl': '/search?q={{key}}',
    'ruleSearch': <String, dynamic>{'bookList': 'class.item'},
  }));
}

List<String> _names(SourceRepository repo) =>
    repo.byType(SourceType.novelSource).map((c) => c.name).toList();

void main() {
  SharedPreferences.setMockInitialValues(<String, Object>{});

  group('书源身份 = bookSourceUrl 精确字符串（legado 主键）', () {
    test('尾斜杠 / # 后缀变体是不同的源，不再互相覆盖', () {
      final repo = SourceRepository();
      repo.addSource(_legado('拷贝轻说', 'https://www.mangacopy.com'));
      repo.addSource(_legado('拷贝漫画', 'https://www.mangacopy.com/'));
      repo.addSource(_legado('七猫甲', 'https://api-bc.wtzw.com#'));
      repo.addSource(_legado('七猫乙', 'https://api-bc.wtzw.com/'));

      expect(_names(repo), hasLength(4));
      expect(
        _names(repo),
        containsAll(<String>['拷贝轻说', '拷贝漫画', '七猫甲', '七猫乙']),
      );
      expect(repo.all.map((c) => c.id).toSet(), hasLength(4));
    });

    test('非 URL / 纯中文 bookSourceUrl 各自独立', () {
      final repo = SourceRepository();
      repo.addSource(_legado('企鹅源', '🐧'));
      repo.addSource(_legado('爱发电', '爱发电'));
      repo.addSource(_legado('订阅源', '订阅源'));
      repo.addSource(_legado('中文域名', 'https://你觉得还有网址?'));

      expect(_names(repo), hasLength(4));
      expect(repo.all.map((c) => c.id).toSet(), hasLength(4));
    });

    test('同一 bookSourceUrl 重复导入按 REPLACE 覆盖（不产生副本）', () {
      final repo = SourceRepository();
      repo.addSource(_legado('源名A', 'https://www.example.com/'));
      repo.addSource(_legado('源名B', 'https://www.example.com/'));

      expect(_names(repo), <String>['源名B']);
    });

    test('同一合集重复导入稳定：数量与 id 均不漂移', () {
      final repo = SourceRepository();
      final batch = <PluginConfig>[
        _legado('甲', 'https://a.example.com'),
        _legado('乙', 'https://a.example.com/'),
        _legado('丙', '🐧'),
        _legado('丁', '爱发电'),
      ];
      for (final c in batch) {
        repo.addSource(c);
      }
      final idsAfterFirst = repo.all.map((c) => c.id).toList();

      for (final c in batch) {
        repo.addSource(c);
      }
      expect(repo.all, hasLength(4));
      expect(repo.all.map((c) => c.id).toList(), idsAfterFirst);
    });

    test('旧方案已入库的 id 保持稳定，冲突的新源确定性补后缀', () {
      final legacy = _legado('旧源', 'https://www.example.com')
          .copyWith(id: 'xiaoshuo_www_example_com');
      final repo = SourceRepository(<PluginConfig>[legacy]);

      repo.addSource(_legado('新源', 'https://www.example.com/'));

      expect(repo.getById('xiaoshuo_www_example_com')?.name, '旧源');
      expect(_names(repo), hasLength(2));
      expect(_names(repo), containsAll(<String>['旧源', '新源']));
    });

    test('同 URL 已以其它 id 入库时复用原 id（不产生副本）', () {
      final source = _legado('乙', 'https://www.example.com/');
      final existing = source.copyWith(id: '${source.id}_deadbeef');
      final repo = SourceRepository(<PluginConfig>[existing]);

      repo.addSource(_legado('乙改名', 'https://www.example.com/'));

      expect(repo.all, hasLength(1));
      expect(repo.getById(existing.id), isNotNull);
      expect(repo.getById(existing.id)?.name, '乙改名');
    });

    test('仅前 60 字符相同的长 URL 源各自保留', () {
      // 旧 id 截断 60 字符：共同前缀 a*80 后仅尾字符不同 → 截断后同 id。
      final repo = SourceRepository();
      repo.addSource(_legado('长A', 'https://example.com/${'a' * 80}X'));
      repo.addSource(_legado('长B', 'https://example.com/${'a' * 80}Y'));

      expect(_names(repo), hasLength(2));
      expect(_names(repo), containsAll(<String>['长A', '长B']));
    });
  });

  group('addSources 批量导入与逐个 addSource 语义一致', () {
    test('混合变体合集：最终 id 序列与逐个导入完全一致', () {
      final batch = <PluginConfig>[
        _legado('甲', 'https://a.example.com'),
        _legado('乙', 'https://a.example.com/'),
        _legado('丙', '🐧'),
        _legado('丁', '爱发电'),
        // 与甲同 URL：应替换甲而非新增
        _legado('甲改名', 'https://a.example.com'),
        // 同归一化 id 的两个不同 URL（scheme 差异）：后者补后缀共存
        _legado('己1', 'https://c.example.com'),
        _legado('己2', 'http://c.example.com'),
      ];

      final seqRepo = SourceRepository();
      for (final c in batch) {
        seqRepo.addSource(c);
      }
      final batchRepo = SourceRepository();
      final saved = batchRepo.addSources(batch);

      expect(batchRepo.all.map((c) => c.id), seqRepo.all.map((c) => c.id));
      expect(batchRepo.all.map((c) => c.name), seqRepo.all.map((c) => c.name));
      expect(saved, batch.length);
    });

    test('同批同 URL 重复收敛为一个（首个 id），返回入库计数', () {
      final repo = SourceRepository();
      final saved = repo.addSources(<PluginConfig>[
        _legado('源A', 'https://www.example.com/'),
        _legado('源B', 'https://www.example.com/'),
        _legado('源C', 'https://other.example.com/'),
      ]);

      expect(saved, 2);
      expect(_names(repo), hasLength(2));
      expect(_names(repo), containsAll(<String>['源A', '源C']));
    });

    test('批量重复导入稳定：数量与 id 均不漂移', () {
      final batch = <PluginConfig>[
        _legado('甲', 'https://a.example.com'),
        _legado('乙', 'https://a.example.com/'),
        _legado('丙', '🐧'),
      ];
      final repo = SourceRepository();
      repo.addSources(batch);
      final idsAfterFirst = repo.all.map((c) => c.id).toList();

      repo.addSources(batch);
      expect(repo.all, hasLength(3));
      expect(repo.all.map((c) => c.id).toList(), idsAfterFirst);
    });

    test('版本保护：低版本不覆盖高版本，不计入返回值', () {
      final repo = SourceRepository();
      repo.addSource(_legado('高版本', 'https://www.example.com'));

      final saved = repo.addSources(<PluginConfig>[
        _legado('高版本', 'https://www.example.com'),
      ]);

      expect(saved, 0);
      expect(repo.all.map((c) => c.name), <String>['高版本']);
    });
  });
}
