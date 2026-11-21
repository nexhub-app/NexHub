import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/audio_lyric.dart';
import 'package:nexhub/core/models/episode.dart';

void main() {
  group('parseAudioLyrics', () {
    test('空输入返回空列表', () {
      expect(parseAudioLyrics(null), isEmpty);
      expect(parseAudioLyrics(''), isEmpty);
      expect(parseAudioLyrics('  \n \r\n '), isEmpty);
    });

    test('基础 [mm:ss.xx] 行', () {
      final lines = parseAudioLyrics('[00:12.34]第一句');
      expect(lines, hasLength(1));
      expect(lines.single.timestampMs, 12340);
      expect(lines.single.text, '第一句');
    });

    test('无小数部分按整秒', () {
      final lines = parseAudioLyrics('[01:05]整秒');
      expect(lines.single.timestampMs, 65000);
    });

    test('毫秒位数 1/2/3 位分别放大', () {
      final one = parseAudioLyrics('[00:01.5]a');
      final two = parseAudioLyrics('[00:01.34]b');
      final three = parseAudioLyrics('[00:01.567]c');
      expect(one.single.timestampMs, 1500);
      expect(two.single.timestampMs, 1340);
      expect(three.single.timestampMs, 1567);
    });

    test('冒号分隔的 [mm:ss:SSS] 等价于小数分隔', () {
      final lines = parseAudioLyrics('[00:12:567]冒号');
      expect(lines.single.timestampMs, 12567);
    });

    test('分钟可到 3 位', () {
      final lines = parseAudioLyrics('[100:00.001]超长');
      expect(lines.single.timestampMs, 6000001);
    });

    test('同一行多时间戳各自展开且共用最后时间戳后的正文', () {
      final lines = parseAudioLyrics('[00:01.00][00:03.00]副歌');
      expect(lines, hasLength(2));
      expect(lines[0].timestampMs, 1000);
      expect(lines[1].timestampMs, 3000);
      expect(lines.every((l) => l.text == '副歌'), isTrue);
    });

    test('时间戳前的正文被丢弃，只取最后一个时间戳之后', () {
      final lines = parseAudioLyrics('前缀[00:02.00]正文');
      expect(lines.single.text, '正文');
    });

    test('无时间戳的行不产出条目', () {
      final lines = parseAudioLyrics('[ar:歌手]\n[00:01.00]有效\n纯文本');
      expect(lines, hasLength(1));
      expect(lines.single.text, '有效');
    });

    test('时间戳后为空的条目不产出', () {
      final lines = parseAudioLyrics('[00:01.00]\n[00:02.00]有词');
      expect(lines, hasLength(1));
      expect(lines.single.text, '有词');
    });

    test('乱序时间戳解析后按时间升序', () {
      final lines = parseAudioLyrics(
        '[00:30.00]三\n[00:10.00]一\n[00:20.00]二',
      );
      expect(lines.map((l) => l.text), <String>['一', '二', '三']);
    });

    test('相同时间戳保持输入顺序（稳定排序）', () {
      final lines = parseAudioLyrics(
        '[00:01.00]先\n[00:01.00]后',
      );
      expect(lines.map((l) => l.text), <String>['先', '后']);
    });

    test('CRLF 换行同样可解析', () {
      final lines = parseAudioLyrics('[00:01.00]一\r\n[00:02.00]二\r\n');
      expect(lines, hasLength(2));
      expect(lines[1].text, '二');
    });
  });

  group('VideoResult.lyric 序列化', () {
    test('往返保留歌词，缺省不落 JSON 键', () {
      const withLyric = VideoResult(
        url: 'https://example.com/a.mp3',
        lyric: '[00:01.00]词',
      );
      final json = withLyric.toJson();
      expect(json['lyric'], '[00:01.00]词');
      final restored = VideoResult.fromJson(json);
      expect(restored.lyric, '[00:01.00]词');

      const without = VideoResult(url: 'https://example.com/a.mp3');
      expect(without.toJson().containsKey('lyric'), isFalse);
      expect(VideoResult.fromJson(without.toJson()).lyric, isNull);
    });
  });
}
