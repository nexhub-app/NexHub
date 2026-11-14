/// 书源变量存储测试（P0-4）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/shuyuan_variable_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ShuyuanVariableStore.resetCacheForTest();
  });

  test('save/load 往返', () async {
    await ShuyuanVariableStore.save('src_a', {'token': 'abc', 'uid': '1'});
    final loaded = await ShuyuanVariableStore.load('src_a');
    expect(loaded, {'token': 'abc', 'uid': '1'});
  });

  test('put/get 单键与跨源隔离', () async {
    await ShuyuanVariableStore.put('src_a', 'k', 'v1');
    await ShuyuanVariableStore.put('src_b', 'k', 'v2');
    expect(await ShuyuanVariableStore.get('src_a', 'k'), 'v1');
    expect(await ShuyuanVariableStore.get('src_b', 'k'), 'v2');
    expect(await ShuyuanVariableStore.get('src_a', 'missing'), '');
  });

  test('空表保存清除条目', () async {
    await ShuyuanVariableStore.save('src_a', {'k': 'v'});
    await ShuyuanVariableStore.save('src_a', {});
    expect(await ShuyuanVariableStore.load('src_a'), isEmpty);
  });
}
