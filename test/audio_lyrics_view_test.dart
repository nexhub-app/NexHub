// AudioLyricsView：时间轴高亮、跟随滚动与点击跳转（音频歌词页核心交互）。
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexhub/core/models/audio_lyric.dart';
import 'package:nexhub/features/player/presentation/audio_lyrics_view.dart';

Widget _host({
  required List<AudioLyricLine> lines,
  required Stream<Duration> stream,
  Duration initial = Duration.zero,
  ValueChanged<int>? onSeekMs,
}) {
  return MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox(
        height: 400,
        child: AudioLyricsView(
          lines: lines,
          positionStream: stream,
          initialPosition: initial,
          onSeekMs: onSeekMs,
        ),
      ),
    ),
  );
}

const List<AudioLyricLine> _shortLines = <AudioLyricLine>[
  AudioLyricLine(0, '第一行'),
  AudioLyricLine(5000, '第二行'),
  AudioLyricLine(10000, '第三行'),
];

Text _textOf(WidgetTester tester, String line) =>
    tester.widget<Text>(find.text(line));

void main() {
  group('AudioLyricsView', () {
    testWidgets('按初始位置高亮当前行', (WidgetTester tester) async {
      final StreamController<Duration> positions =
          StreamController<Duration>.broadcast();
      addTearDown(positions.close);

      await tester.pumpWidget(_host(
        lines: _shortLines,
        stream: positions.stream,
        initial: const Duration(milliseconds: 6000),
      ));

      expect(_textOf(tester, '第二行').style?.color, Colors.white);
      expect(_textOf(tester, '第二行').style?.fontWeight, FontWeight.w600);
      expect(_textOf(tester, '第一行').style?.color, Colors.white54);
    });

    testWidgets('位置流推进后高亮跟随', (WidgetTester tester) async {
      final StreamController<Duration> positions =
          StreamController<Duration>.broadcast();
      addTearDown(positions.close);

      await tester.pumpWidget(_host(
        lines: _shortLines,
        stream: positions.stream,
      ));
      positions.add(const Duration(milliseconds: 10500));
      await tester.pumpAndSettle();

      expect(_textOf(tester, '第三行').style?.color, Colors.white);
      expect(_textOf(tester, '第一行').style?.color, Colors.white54);
    });

    testWidgets('点击歌词行回传该行时间戳', (WidgetTester tester) async {
      final StreamController<Duration> positions =
          StreamController<Duration>.broadcast();
      addTearDown(positions.close);
      int? seeked;

      await tester.pumpWidget(_host(
        lines: _shortLines,
        stream: positions.stream,
        onSeekMs: (int ms) => seeked = ms,
      ));
      await tester.tap(find.text('第二行'));

      expect(seeked, 5000);
    });

    testWidgets('无点击回调时行不可点击', (WidgetTester tester) async {
      final StreamController<Duration> positions =
          StreamController<Duration>.broadcast();
      addTearDown(positions.close);

      await tester.pumpWidget(_host(
        lines: _shortLines,
        stream: positions.stream,
      ));
      final InkWell row = tester.widget<InkWell>(
        find.ancestor(of: find.text('第二行'), matching: find.byType(InkWell)),
      );
      expect(row.onTap, isNull);
    });

    testWidgets('歌词行左对齐', (WidgetTester tester) async {
      final StreamController<Duration> positions =
          StreamController<Duration>.broadcast();
      addTearDown(positions.close);

      await tester.pumpWidget(_host(
        lines: _shortLines,
        stream: positions.stream,
      ));
      expect(_textOf(tester, '第一行').textAlign, isNot(TextAlign.center));
      expect(_textOf(tester, '第一行').style?.fontSize, greaterThanOrEqualTo(18));
    });

    testWidgets('高亮行自动滚入可视区', (WidgetTester tester) async {
      final StreamController<Duration> positions =
          StreamController<Duration>.broadcast();
      addTearDown(positions.close);
      final List<AudioLyricLine> lines = <AudioLyricLine>[
        for (int i = 0; i <= 30; i++) AudioLyricLine(i * 1000, '行 $i'),
      ];

      await tester.pumpWidget(_host(lines: lines, stream: positions.stream));
      expect(find.text('行 25'), findsNothing);

      positions.add(const Duration(seconds: 25));
      await tester.pumpAndSettle();

      expect(find.text('行 25'), findsOneWidget);
      expect(_textOf(tester, '行 25').style?.color, Colors.white);
    });
  });
}
