/// LRC 歌词解析（对齐 legado md3 `AudioPlayViewModel.parseAudioLyrics`）。
library;

/// 一行带时间戳的歌词（同一行多时间戳会展开成多条）。
class AudioLyricLine {
  final int timestampMs;
  final String text;

  const AudioLyricLine(this.timestampMs, this.text);
}

/// `[mm:ss]` / `[mm:ss.SSS]` / `[mm:ss:SSS]`；分钟 1-3 位，毫秒 1-3 位。
final RegExp _timestampPattern =
    RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?]');

/// 解析 LRC 文本：逐行取时间戳，正文取最后一个时间戳之后的部分；
/// 同一条目多时间戳各自成行，最后按时间稳定排序。
List<AudioLyricLine> parseAudioLyrics(String? lyric) {
  if (lyric == null || lyric.trim().isEmpty) return const <AudioLyricLine>[];
  final indexed = <(int, AudioLyricLine)>[];
  for (final String line in lyric.split(RegExp(r'\r\n|\r|\n'))) {
    final List<RegExpMatch> matches = _timestampPattern.allMatches(line).toList();
    final String text = matches.isEmpty
        ? line.trim()
        : line.substring(matches.last.end).trim();
    if (text.isEmpty) continue;
    for (final RegExpMatch match in matches) {
      final int? minutes = int.tryParse(match.group(1)!);
      final int? seconds = int.tryParse(match.group(2)!);
      if (minutes == null || seconds == null) continue;
      final String fraction = match.group(3) ?? '';
      final int millis = switch (fraction.length) {
        0 => 0,
        1 => int.parse(fraction) * 100,
        2 => int.parse(fraction) * 10,
        _ => int.parse(fraction.substring(0, 3)),
      };
      indexed.add((
        indexed.length,
        AudioLyricLine((minutes * 60 + seconds) * 1000 + millis, text),
      ));
    }
  }
  indexed.sort((a, b) {
    final int byTime = a.$2.timestampMs.compareTo(b.$2.timestampMs);
    return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
  });
  return <AudioLyricLine>[for (final (_, AudioLyricLine l) in indexed) l];
}
