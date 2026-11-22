/// 文件类书源详情页接线（源码级）：目录=源文件列表、开始阅读先下载、
/// 进度跟随本地文件、下载不自动打开。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final String detail = File(
    'lib/features/media/presentation/content_detail_screen.dart',
  ).readAsStringSync();
  final String picker = File(
    'lib/features/shuyuan/presentation/shuyuan_web_file_picker.dart',
  ).readAsStringSync();
  final String actions = File(
    'lib/core/local/local_content_actions.dart',
  ).readAsStringSync();

  group('详情页文件源', () {
    test('目录替换为源文件列表（带计数、已下载标记与下载/打开行操作）', () {
      expect(detail, contains('sourceWebFilesTitleWithCount'));
      expect(detail, contains('onTapChapter: _onWebFileAction'));
      expect(detail, contains('onDownloadChapter: _onWebFileAction'));
      expect(detail, contains('localEntryForWebFile(webBookLocals'));
      expect(detail, contains('unitWord: l10n.unitWordFile'));
    });

    test('按钮语义不变：未下载先提示下载，不再打开文件选择列表当按钮', () {
      expect(detail, contains('hasWebLocalProgress ? l10n.continueReading'));
      // 单文件确认弹窗、多文件文件列表选择。
      expect(detail, contains('confirmShuyuanWebFileDownload'));
      expect(detail, contains('pickAndDownloadShuyuanWebFile'));
      // 下载后停留在详情页；按钮再次点击才进入阅读。
      expect(detail, contains('_onWebReadPressed'));
      expect(detail, isNot(contains('openShuyuanWebFilePicker')));
    });

    test('详情进度跟随本地文件（本地进度卡 + 阅读历史时间）', () {
      expect(detail, contains('NovelProgressManager().get(active.id)'));
      expect(detail, contains('_refreshWebProgress'));
      expect(detail, contains('ProgressKind.reading'));
      expect(detail, contains('sourceType: SourceType.novelSource'));
      expect(detail, contains('await openLocalEntry(context, entry)'));
    });
  });

  group('文件下载器', () {
    test('下载只入库不打开，写入来源三元组', () {
      expect(picker, contains('originSourceId: originSourceId'));
      expect(picker, contains('originContentId: originContentId'));
      expect(picker, contains('originFileUrl: originFileUrl'));
      expect(picker, isNot(contains('openLocalEntry')));
      expect(picker, isNot(contains('openShuyuanWebFilePicker')));
    });

    test('本地书打开等待阅读器关闭（返回后刷新进度）', () {
      expect(
        actions,
        contains('await Navigator.of(context).push('),
        reason: '文本/EPUB 打开必须 await，详情页返回后才能刷新本地进度',
      );
    });
  });
}
