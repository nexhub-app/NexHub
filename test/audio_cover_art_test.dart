// AudioCoverArt：音频模式封面的占位/加载兜底（无封面、加载中、加载失败
// 都显示音符占位，避免破图与视频黑屏）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexhub/features/player/presentation/audio_cover_art.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('AudioCoverArt', () {
    testWidgets('无封面 URL 显示音符占位', (WidgetTester tester) async {
      await tester
          .pumpWidget(_host(const AudioCoverArt(coverUrl: null, size: 200)));
      expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('空白封面 URL 同样走占位', (WidgetTester tester) async {
      await tester
          .pumpWidget(_host(const AudioCoverArt(coverUrl: '  ', size: 160)));
      expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('有封面 URL 时渲染网络图（测试环境加载失败回落占位）', (WidgetTester tester) async {
      await tester.pumpWidget(_host(
        const AudioCoverArt(
          coverUrl: 'https://example.invalid/cover.jpg',
          size: 200,
        ),
      ));
      // flutter_test 的 HttpOverrides 对网络图返回 400：errorBuilder 必须
      // 接住并把占位显示出来，不能把异常抛给框架。
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    });

    testWidgets('封面尺寸按参数布局', (WidgetTester tester) async {
      await tester
          .pumpWidget(_host(const AudioCoverArt(coverUrl: null, size: 240)));
      final Size size = tester.getSize(find.byType(AudioCoverArt));
      expect(size.width, 240);
      expect(size.height, 240);
    });
  });
}
