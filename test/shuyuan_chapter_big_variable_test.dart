/// 章节大变量（legado `RuleBigDataHelp` 章节级存储）语义测试。
///
/// 覆盖阈值分流、普通表 → 大变量表 → 空串的读取优先级，以及删除语义：
/// 大变量不进 `variable`（唯一入库字段），但同一进程内跨规则/跨阶段可读。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book_chapter.dart';

void main() {
  final big = 'x' * XiaoshuoBookChapter.bigVariableThreshold;

  test('小变量进普通表并同步 variable', () {
    final ch = XiaoshuoBookChapter(bookUrl: 'b', url: 'u');
    ch.putVariable('token', 'abc');
    expect(ch.variableMap['token'], 'abc');
    expect(ch.bigVariableMap, isEmpty);
    expect(jsonDecode(ch.variable!), {'token': 'abc'});
    expect(ch.getVariable('token'), 'abc');
  });

  test('达到阈值转大变量，variable 不再序列化它', () {
    final ch = XiaoshuoBookChapter(bookUrl: 'b', url: 'u');
    ch.putVariable('blob', big);
    expect(ch.bigVariableMap['blob'], big);
    expect(ch.variableMap, isEmpty);
    expect(ch.variable, isNull);
    expect(ch.getVariable('blob'), big);
    expect(ch.getBigVariable('blob'), big);
  });

  test('同键小值覆盖大值，大值覆盖小值都清理另一侧', () {
    final ch = XiaoshuoBookChapter(bookUrl: 'b', url: 'u');
    ch.putVariable('k', big);
    ch.putVariable('k', 'small');
    expect(ch.variableMap['k'], 'small');
    expect(ch.bigVariableMap, isEmpty);
    ch.putVariable('k', big);
    expect(ch.variableMap, isEmpty);
    expect(ch.bigVariableMap['k'], big);
    expect(ch.getVariable('k'), big);
  });

  test('null 删除两侧，读回空串', () {
    final ch = XiaoshuoBookChapter(bookUrl: 'b', url: 'u');
    ch.putVariable('k', big);
    ch.putVariable('k', null);
    expect(ch.bigVariableMap, isEmpty);
    expect(ch.getVariable('k'), '');
    expect(ch.getBigVariable('k'), isNull);
  });

  test('putBigVariable 不写 variable，序列化后旧数据仍可读', () {
    final ch = XiaoshuoBookChapter(bookUrl: 'b', url: 'u');
    ch.putBigVariable('lyric', big);
    expect(ch.variable, isNull);
    expect(ch.getVariable('lyric'), big);
    // 旧数据（只有 variable 串）：回填普通表，大变量不参与。
    final restored = XiaoshuoBookChapter.fromJson(<String, dynamic>{
      'bookUrl': 'b',
      'url': 'u',
      'variable': jsonEncode({'k': 'v'}),
    });
    expect(restored.getVariable('k'), 'v');
    expect(restored.bigVariableMap, isEmpty);
  });
}
