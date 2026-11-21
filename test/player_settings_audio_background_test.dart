// PlayerSettings 音频背景字段：默认值、copyWith 与 JSON 往返/容错。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/settings/player_settings.dart';

void main() {
  group('PlayerSettings audio background', () {
    test('默认封面取色 + 默认深色底', () {
      const PlayerSettings settings = PlayerSettings();
      expect(settings.audioBackgroundMode, AudioBackgroundMode.cover);
      expect(settings.audioBackgroundColor, 0xFF1C1C24);
      expect(settings.audioPlayButtonColor, 0);
    });

    test('copyWith 只改指定字段', () {
      const PlayerSettings settings = PlayerSettings();
      final PlayerSettings solid = settings.copyWith(
        audioBackgroundMode: AudioBackgroundMode.solid,
        audioBackgroundColor: 0xFF101820,
        audioPlayButtonColor: 0xFF3366CC,
      );
      expect(solid.audioBackgroundMode, AudioBackgroundMode.solid);
      expect(solid.audioBackgroundColor, 0xFF101820);
      expect(solid.audioPlayButtonColor, 0xFF3366CC);
      expect(solid.decodeMode, settings.decodeMode);
      expect(solid.playbackSpeed, settings.playbackSpeed);
    });

    test('toJson / fromJson 往返保持字段', () {
      const PlayerSettings settings = PlayerSettings(
        audioBackgroundMode: AudioBackgroundMode.theme,
        audioBackgroundColor: 0xFF14201A,
        audioPlayButtonColor: 0xFF993322,
      );
      final PlayerSettings restored =
          PlayerSettings.fromJson(settings.toJson());
      expect(restored.audioBackgroundMode, AudioBackgroundMode.theme);
      expect(restored.audioBackgroundColor, 0xFF14201A);
      expect(restored.audioPlayButtonColor, 0xFF993322);
    });

    test('旧数据缺字段时回落默认', () {
      final PlayerSettings restored =
          PlayerSettings.fromJson(<String, dynamic>{'playbackSpeed': 1.5});
      expect(restored.audioBackgroundMode, AudioBackgroundMode.cover);
      expect(restored.audioBackgroundColor, 0xFF1C1C24);
      expect(restored.audioPlayButtonColor, 0);
      expect(restored.playbackSpeed, 1.5);
    });

    test('非法背景模式回落 cover', () {
      final PlayerSettings restored = PlayerSettings.fromJson(
        <String, dynamic>{'audioBackgroundMode': 'bogus'},
      );
      expect(restored.audioBackgroundMode, AudioBackgroundMode.cover);
    });
  });
}
