// AudioLyricsView：时间轴高亮、跟随滚动与点击跳转（音频歌词页核心交互）。
library;

import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

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

    testWidgets('静置时当前行位于视口垂直中线', (WidgetTester tester) async {
      final StreamController<Duration> positions =
          StreamController<Duration>.broadcast();
      addTearDown(positions.close);
      final List<AudioLyricLine> lines = <AudioLyricLine>[
        for (int i = 0; i <= 30; i++) AudioLyricLine(i * 1000, '行 $i'),
      ];

      await tester.pumpWidget(_host(
        lines: lines,
        stream: positions.stream,
        initial: const Duration(seconds: 10),
      ));
      await tester.pumpAndSettle();

      final ScrollableState scrollable =
          tester.state<ScrollableState>(find.byType(Scrollable));
      // 顶部对称留白 400/2−72/2=164：第 10 行中心停在视口中线，滚动量 = 10×72。
      const double expected = 10 * 72;
      expect(
        scrollable.position.pixels,
        moreOrLessEquals(expected, epsilon: 0.5),
      );
    });

    testWidgets('首行也能停在视口中线', (WidgetTester tester) async {
      final StreamController<Duration> positions =
          StreamController<Duration>.broadcast();
      addTearDown(positions.close);
      final List<AudioLyricLine> lines = <AudioLyricLine>[
        for (int i = 0; i <= 30; i++) AudioLyricLine(i * 1000, '行 $i'),
      ];

      await tester.pumpWidget(_host(lines: lines, stream: positions.stream));
      await tester.pumpAndSettle();

      final double mid = tester.getCenter(find.byType(AudioLyricsView)).dy;
      expect(
        tester.getCenter(find.text('行 0')).dy,
        moreOrLessEquals(mid, epsilon: 1),
      );
      final ScrollableState scrollable =
          tester.state<ScrollableState>(find.byType(Scrollable));
      expect(scrollable.position.pixels, lessThan(1));
    });

    testWidgets('末行也能停在视口中线', (WidgetTester tester) async {
      final StreamController<Duration> positions =
          StreamController<Duration>.broadcast();
      addTearDown(positions.close);
      final List<AudioLyricLine> lines = <AudioLyricLine>[
        for (int i = 0; i <= 30; i++) AudioLyricLine(i * 1000, '行 $i'),
      ];

      await tester.pumpWidget(_host(
        lines: lines,
        stream: positions.stream,
        initial: const Duration(seconds: 30),
      ));
      await tester.pumpAndSettle();

      final double mid = tester.getCenter(find.byType(AudioLyricsView)).dy;
      expect(
        tester.getCenter(find.text('行 30')).dy,
        moreOrLessEquals(mid, epsilon: 1),
      );
      final ScrollableState scrollable =
          tester.state<ScrollableState>(find.byType(Scrollable));
      expect(
        scrollable.position.pixels,
        moreOrLessEquals(scrollable.position.maxScrollExtent, epsilon: 0.5),
      );
    });

    testWidgets('滚动停止约 3 秒后自动回中', (WidgetTester tester) async {
      final StreamController<Duration> positions =
          StreamController<Duration>.broadcast();
      addTearDown(positions.close);
      final List<AudioLyricLine> lines = <AudioLyricLine>[
        for (int i = 0; i <= 30; i++) AudioLyricLine(i * 1000, '行 $i'),
      ];

      await tester.pumpWidget(_host(lines: lines, stream: positions.stream));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await tester.pumpAndSettle();
      final ScrollableState scrollable =
          tester.state<ScrollableState>(find.byType(Scrollable));
      expect(scrollable.position.pixels, greaterThan(100),
          reason: '翻动后允许暂时不居中');

      // 静置 3 秒后当前行自动回到中线（第 0 行回中即顶部极限 0）。
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, lessThan(1));
    });

    testWidgets('滚轮翻动后停稳约 3 秒同样回中', (WidgetTester tester) async {
      final StreamController<Duration> positions =
          StreamController<Duration>.broadcast();
      addTearDown(positions.close);
      final List<AudioLyricLine> lines = <AudioLyricLine>[
        for (int i = 0; i <= 30; i++) AudioLyricLine(i * 1000, '行 $i'),
      ];

      await tester.pumpWidget(_host(lines: lines, stream: positions.stream));
      await tester.pumpAndSettle();

      final TestPointer pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.hover(tester.getCenter(find.byType(ListView))),
      );
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 300)));
      await tester.pumpAndSettle();

      final ScrollableState scrollable =
          tester.state<ScrollableState>(find.byType(Scrollable));
      expect(scrollable.position.pixels, greaterThan(100),
          reason: '滚轮翻动后允许暂时不居中');

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, lessThan(1));
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
