/// Book / BookChapter 变量序列化权威（审计 M27）：
/// 直接改 `variableMap`（WebBook 的 putIfAbsent/addAll、脚本直改）后
/// toJson→fromJson 不能丢变量；只有 `variableMap` 的早期载荷也要能读回。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book.dart';
import 'package:nexhub/features/shuyuan/model/xiaoshuo_book_chapter.dart';

void main() {
  test('Book：直接改 variableMap 后往返仍保留变量', () {
    final book = XiaoshuoBook(bookUrl: 'https://x/book', name: 'B');
    // 模拟 WebBook/BookInfo 的直接 map 写入（不走 putVariable）。
    book.variableMap['token'] = 'abc';
    final json = jsonDecode(jsonEncode(book.toJson())) as Map<String, dynamic>;
    expect(json['variable'], isNotNull,
        reason: '序列化前要把 variable 对齐成当前 map');
    final back = XiaoshuoBook.fromJson(json);
    expect(back.getVariable('token'), 'abc');
  });

  test('Book：只有 variableMap 的载荷也能读回', () {
    final back = XiaoshuoBook.fromJson(<String, dynamic>{
      'bookUrl': 'https://x/book',
      'name': 'B',
      'variableMap': <String, String>{'k': 'v'},
    });
    expect(back.getVariable('k'), 'v');
  });

  test('Book：variable 与 variableMap 同时存在时以 variable 为准', () {
    final back = XiaoshuoBook.fromJson(<String, dynamic>{
      'bookUrl': 'https://x/book',
      'name': 'B',
      'variable': jsonEncode(<String, String>{'k': 'fromVariable'}),
      'variableMap': <String, String>{'k': 'fromMap'},
    });
    expect(back.getVariable('k'), 'fromVariable');
  });

  test('BookChapter：直接改 variableMap 后往返仍保留变量', () {
    final chapter = XiaoshuoBookChapter(
      bookUrl: 'https://x/book',
      url: 'https://x/c1',
      title: '第一章',
      index: 0,
    );
    chapter.variableMap['sign'] = 's1';
    final json =
        jsonDecode(jsonEncode(chapter.toJson())) as Map<String, dynamic>;
    expect(json['variable'], isNotNull);
    final back = XiaoshuoBookChapter.fromJson(json);
    expect(back.getVariable('sign'), 's1');
  });
}
