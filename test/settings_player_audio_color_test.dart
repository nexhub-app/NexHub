// 音频播放按钮颜色设置 + RGB 自定义取色（源级守卫）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('settings player audio color', () {
    test('音频分组新增播放按钮颜色行（默认跟随主题）', () {
      final String src = _read(
        'lib/features/settings/presentation/settings_player_screen.dart',
      );
      expect(src, contains("'player.audioPlayButtonColor'"));
      expect(src, contains('audioPlayButtonColor: selected'));
      expect(src, contains('allowFollowTheme: true'));
      expect(src, contains('l10n.audioFollowTheme'));
      // 0 为「跟随主题」哨兵值，缩略色块用主题色 + 调色板图标提示。
      expect(src, contains('_settings.audioPlayButtonColor == 0'));
      expect(src, contains('Icons.palette_outlined'));
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

    test('音频播放键使用自定义色并按亮度取前景色', () {
      final String audioMode = _read(
        'lib/features/player/presentation/video_player_audio_mode.dart',
      );
      expect(audioMode, contains('final Color? customColor;'));
      expect(audioMode, contains('customColor: customPlayColor == 0'));
      expect(audioMode, contains('ThemeData.estimateBrightnessForColor'));
    });
  });
}
