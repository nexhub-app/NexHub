/// 音频模式封面：网络封面图 + 加载/失败占位。
///
/// 无封面 URL、加载中、加载失败三种情况统一显示音符占位图标，
/// 避免音频播放页出现视频黑屏或破图。独立成公共组件以便单测直接泵。
library;

import 'package:material_ui/material_ui.dart';

class AudioCoverArt extends StatelessWidget {
  final String? coverUrl;
  final double size;

  const AudioCoverArt({super.key, required this.coverUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    final String url = coverUrl?.trim() ?? '';
    final Widget placeholder = Container(
      color: Colors.white10,
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.32,
        color: Colors.white38,
      ),
    );
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.white10,
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Colors.black45,
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: url.isEmpty
          ? placeholder
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => placeholder,
              loadingBuilder:
                  (BuildContext _, Widget child, ImageChunkEvent? progress) =>
                      progress == null ? child : placeholder,
            ),
    );
  }
}
