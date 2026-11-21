import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/shuyuan_source_service.dart';

/// 文件类书源（legado bookSourceType=3）的有效性判定回归锁：
/// 这类源没有搜索/目录/正文规则，详情阶段直接由 ruleBookInfo 给出
/// downloadUrls 文件列表——仅有 ruleBookInfo 也必须判为有效，否则
/// 导入预览整批判死、源管理不显示（2026-11-21 修复）。
void main() {
  test('文件类书源（仅 ruleBookInfo.downloadUrls）判为有效', () {
    final source = ShuyuanSource.fromJson(<String, dynamic>{
      'bookSourceName': '文件源',
      'bookSourceUrl': 'https://example.com/file-source.json',
      'bookSourceType': 3,
      'ruleBookInfo': <String, dynamic>{
        'downloadUrls': '.downloadUrls@textNodes',
      },
    });
    expect(source.bookSourceType, 3);
    expect(source.isValid, isTrue);
  });

  test('文本书源原有判定不受影响', () {
    final withSearch = ShuyuanSource.fromJson(<String, dynamic>{
      'bookSourceName': '文本源',
      'bookSourceUrl': 'https://example.com/text.json',
      'bookSourceType': 0,
      'ruleSearch': <String, dynamic>{'bookList': '.item'},
    });
    expect(withSearch.isValid, isTrue);

    final noRules = ShuyuanSource.fromJson(<String, dynamic>{
      'bookSourceName': '空壳源',
      'bookSourceUrl': 'https://example.com/empty.json',
    });
    expect(noRules.isValid, isFalse);
  });

  test('缺名称或缺地址仍判无效', () {
    final noName = ShuyuanSource.fromJson(<String, dynamic>{
      'bookSourceUrl': 'https://example.com/a.json',
      'ruleBookInfo': <String, dynamic>{},
    });
    final noUrl = ShuyuanSource.fromJson(<String, dynamic>{
      'bookSourceName': '无名',
      'ruleBookInfo': <String, dynamic>{},
    });
    expect(noName.isValid, isFalse);
    expect(noUrl.isValid, isFalse);
  });
}
