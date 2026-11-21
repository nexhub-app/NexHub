// 音频播放按钮颜色设置（三选项：封面取色/应用主题/纯色）+ RGB 自定义取色。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/settings/player_settings.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('settings player audio color', () {
    test('播放按钮颜色三选项与背景一致（封面/主题/纯色）', () {
      expect(
        AudioPlayButtonColorMode.values,
        <AudioPlayButtonColorMode>[
          AudioPlayButtonColorMode.cover,
          AudioPlayButtonColorMode.theme,
          AudioPlayButtonColorMode.solid,
        ],
      );
      final String src = _read(
        'lib/features/settings/presentation/settings_player_screen.dart',
      );
      expect(src, contains('AudioPlayButtonColorMode.values.map((m)'));
      expect(src, contains("'player.audioPlayButtonColorMode'"));
      expect(src, contains('_settings.audioPlayButtonColorMode == m'));
      expect(src, contains('audioPlayButtonColorMode: m'));
      // 纯色模式才展开自定义取色行。
      expect(
        RegExp(r'visible: _settings\.audioPlayButtonColorMode ==\s*'
                r'AudioPlayButtonColorMode\.solid')
            .hasMatch(src),
        isTrue,
      );
      expect(src, contains("'player.audioPlayButtonColor'"));
      // 三选项文案复用背景三选项，不再有单独的「跟随主题」入口。
      expect(src, contains('l10n.audioBackgroundCover'));
      expect(src, contains('l10n.audioBackgroundTheme'));
      expect(src, contains('l10n.audioBackgroundSolid'));
      expect(src, isNot(contains('allowFollowTheme')));
      expect(src, isNot(contains('l10n.audioFollowTheme')));
      // 0 视为未设置：初始色与色块均回退主题容器色。
      expect(src, contains('_settings.audioPlayButtonColor == 0'));
      expect(src, contains('scheme.primaryContainer.toARGB32()'));
    });

    test('纯色背景与播放按钮共用 RGB 三通道取色弹窗', () {
      final String src = _read(
        'lib/features/settings/presentation/settings_player_screen.dart',
      );
      expect(src, contains('class _RgbColorDialog'));
      expect(src, contains("'audio_rgb_slider_r'"));
      expect(src, contains("'audio_rgb_slider_g'"));
      expect(src, contains("'audio_rgb_slider_b'"));
      expect(src, contains('divisions: 255'));
      expect(
        RegExp(r'Future<void> _pickAudioBackgroundColor[\s\S]*?_RgbColorDialog\(')
            .hasMatch(src),
        isTrue,
        reason: '纯色背景必须可 RGB 自定义，不再只给固定预设',
      );
      expect(
        RegExp(r'Future<void> _pickAudioPlayButtonColor[\s\S]*?_RgbColorDialog\(')
            .hasMatch(src),
        isTrue,
      );
    });

    test('音频播放键按模式取色：封面调色板 / 主题 / 纯色 + 亮度前景', () {
      final String audioMode = _read(
        'lib/features/player/presentation/video_player_audio_mode.dart',
      );
      expect(audioMode, contains('final Color? customColor;'));
      expect(audioMode, contains('final ColorScheme? palette;'));
      expect(audioMode, contains('customColor: solidColor'));
      expect(audioMode, contains('palette: coverPalette'));
      expect(audioMode, contains('final ColorScheme tones = palette ?? scheme;'));
      expect(audioMode, contains('ThemeData.estimateBrightnessForColor'));
    });
  });
}
