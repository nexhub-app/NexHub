/// WebBook 正文多页并发池自测：
/// 保序返回、单项失败不影响他项、并发上限生效。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/web_book/web_book.dart';

void main() {
  group('WebBook.mapOrderedPool', () {
    test('结果按输入顺序返回（完成先后与顺序无关）', () async {
      // 首个 URL 延迟最大，仍应出现在结果首位。
      final result = await WebBook.mapOrderedPool<String>(
        ['a', 'b', 'c'],
        4,
        (url) async {
          final delay = switch (url) {
            'a' => const Duration(milliseconds: 60),
            'b' => const Duration(milliseconds: 20),
            _ => const Duration(milliseconds: 1),
          };
          await Future<void>.delayed(delay);
          return 'done-$url';
        },
      );
      expect(result, <String?>['done-a', 'done-b', 'done-c']);
    });

    test('单项抛错对应位为 null，其余照常完成', () async {
      final result = await WebBook.mapOrderedPool<String>(
        ['ok1', 'boom', 'ok2'],
        4,
        (url) async {
          if (url == 'boom') throw StateError('fail');
          return url;
        },
      );
      expect(result, <String?>['ok1', null, 'ok2']);
    });

    test('propagateErrors：任一项失败令整批失败（legado mapAsync）', () async {
      var lateRan = false;
      await expectLater(
        WebBook.mapOrderedPool<String>(
          ['boom', 'late'],
          2,
          (url) async {
            if (url == 'boom') throw StateError('fail');
            await Future<void>.delayed(const Duration(milliseconds: 5));
            lateRan = true;
            return url;
          },
          propagateErrors: true,
        ),
        throwsStateError,
      );
      expect(lateRan, isTrue, reason: '同批在飞请求照常完成后再抛出');
    });

    test('并发数不超过 limit', () async {
      var running = 0;
      var peak = 0;
      final result = await WebBook.mapOrderedPool<int>(
        List<String>.generate(12, (i) => 'u$i'),
        3,
        (url) async {
          running++;
          if (running > peak) peak = running;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          running--;
          return 1;
        },
      );
      expect(result.every((r) => r == 1), isTrue);
      expect(peak, lessThanOrEqualTo(3));
    });

    test('空列表直接返回空结果', () async {
      final result = await WebBook.mapOrderedPool<int>([], 4, (_) async => 1);
      expect(result, isEmpty);
    });
  });
}
