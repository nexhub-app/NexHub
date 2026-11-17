// 历史配置迁移回归锁：旧适配器把 bookSourceUrl 兜底注入为持久化的
// antiHotlinking.referer，导致图片/播放请求始终带来源头（legado 语义只透传
// 源声明的 header），签名 CDN 按「来源不一致」拒绝 → 封面全灰。适配器修复
// 只作用于新导入，载入时迁移负责清理存量配置。
import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/shuyuan_adapter.dart';

Map<String, dynamic> config({
  String bookSourceUrl = 'https://src.example.test',
  String baseUrl = 'https://src.example.test',
  Object? header = '{"User-Agent":"Source/1.0"}',
  String? referer = 'https://src.example.test',
}) =>
    <String, dynamic>{
      'id': 'xiaoshuo_src_example_test',
      'name': 'probe',
      'site': <String, dynamic>{'baseUrl': baseUrl},
      'antiHotlinking': <String, dynamic>{
        if (referer != null) 'referer': referer,
        'userAgent': 'Source/1.0',
      },
      'selectors': <String, dynamic>{
        'xiaoshuo': <String, dynamic>{
          'bookSourceUrl': bookSourceUrl,
          'header': header,
        },
      },
    };

void main() {
  test('注入值等于 bookSourceUrl 且源未声明 Referer → 清理并保留 userAgent', () {
    final json = config();
    expect(ShuyuanAdapter.migrateLegacyInjectedReferer(json), isTrue);
    final anti = json['antiHotlinking'] as Map<String, dynamic>;
    expect(anti.containsKey('referer'), isFalse);
    expect(anti['userAgent'], 'Source/1.0');
  });

  test('注入值等于 site.baseUrl（尾斜杠差异）同样清理', () {
    final json = config(
      bookSourceUrl: 'https://src.example.test/',
      referer: 'https://src.example.test',
    );
    expect(ShuyuanAdapter.migrateLegacyInjectedReferer(json), isTrue);
    expect(
      (json['antiHotlinking'] as Map<String, dynamic>).containsKey('referer'),
      isFalse,
    );
  });

  test('源自己声明了 Referer → 保留（可能是防盗链必需）', () {
    final json = config(
      header: '{"Referer":"https://src.example.test/","User-Agent":"Source/1.0"}',
    );
    expect(ShuyuanAdapter.migrateLegacyInjectedReferer(json), isFalse);
    expect(
      (json['antiHotlinking'] as Map<String, dynamic>)['referer'],
      'https://src.example.test',
    );
  });

  test('脚本式 header 无法静态判定 → 保留', () {
    final json = config(header: '@js:({"User-Agent": "Source/1.0"})');
    expect(ShuyuanAdapter.migrateLegacyInjectedReferer(json), isFalse);
    expect(
      (json['antiHotlinking'] as Map<String, dynamic>)['referer'],
      'https://src.example.test',
    );
  });

  test('显式配置的其它 Referer 不误伤', () {
    final json = config(referer: 'https://other.example.test/');
    expect(ShuyuanAdapter.migrateLegacyInjectedReferer(json), isFalse);
    expect(
      (json['antiHotlinking'] as Map<String, dynamic>)['referer'],
      'https://other.example.test/',
    );
  });

  test('非书源配置不触碰', () {
    final json = config();
    (json['selectors'] as Map<String, dynamic>).remove('xiaoshuo');
    expect(ShuyuanAdapter.migrateLegacyInjectedReferer(json), isFalse);
    expect(
      (json['antiHotlinking'] as Map<String, dynamic>)['referer'],
      'https://src.example.test',
    );
  });

  test('幂等：迁移后再次调用不再报告变更', () {
    final json = config();
    expect(ShuyuanAdapter.migrateLegacyInjectedReferer(json), isTrue);
    expect(ShuyuanAdapter.migrateLegacyInjectedReferer(json), isFalse);
  });
}
