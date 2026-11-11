/// 小说朗读（TTS）位置持久化（按 novelId 记录）。
///
/// 与阅读进度分开存：阅读进度记的是「看到哪」，朗读位置记的是「读到哪」。
/// 两者常常不一致（边听边翻、只听不看的场景），混存会互相覆盖。
/// 退出朗读/离开阅读器后重进，从这里恢复朗读起点。
library;

import 'dart:convert';

import '../comic/models/reader_preferences.dart'
    show PrefsBackend, SharedPrefsBackend;

/// 单部小说的朗读位置。
class NovelTtsPosition {
  const NovelTtsPosition({
    required this.chapterIndex,
    required this.paragraphIndex,
    required this.updatedAt,
  });

  /// 章节目录下标。
  final int chapterIndex;

  /// 章内正文块下标（与排版块一一对应，插图块也占一位）。
  final int paragraphIndex;

  final DateTime updatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'chapterIndex': chapterIndex,
        'paragraphIndex': paragraphIndex,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory NovelTtsPosition.fromJson(Map<String, dynamic> json) =>
      NovelTtsPosition(
        chapterIndex: (json['chapterIndex'] as num?)?.toInt() ?? 0,
        paragraphIndex: (json['paragraphIndex'] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['updatedAt'] as num?)?.toInt() ?? 0,
        ),
      );
}

/// 朗读位置的读写入口（单例，内部带缓存）。
class NovelTtsProgressStore {
  NovelTtsProgressStore({PrefsBackend? backend})
      : _backend = backend ?? const SharedPrefsBackend();

  static final NovelTtsProgressStore instance = NovelTtsProgressStore();

  final PrefsBackend _backend;
  final Map<String, NovelTtsPosition?> _cache = {};

  static const String prefix = 'novel_tts_pos_';

  /// 读取上次朗读位置（无记录返回 null）。
  Future<NovelTtsPosition?> get(String novelId) async {
    if (_cache.containsKey(novelId)) return _cache[novelId];
    final raw = await _backend.get('$prefix$novelId');
    if (raw == null || raw.isEmpty) {
      _cache[novelId] = null;
      return null;
    }
    try {
      final pos = NovelTtsPosition.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
      _cache[novelId] = pos;
      return pos;
    } on Object {
      _cache[novelId] = null;
      return null;
    }
  }

  /// 保存朗读位置（章节或段落未变化时不写盘）。
  Future<void> save(
    String novelId,
    int chapterIndex,
    int paragraphIndex,
  ) async {
    final prev = _cache[novelId];
    if (prev != null &&
        prev.chapterIndex == chapterIndex &&
        prev.paragraphIndex == paragraphIndex) {
      return;
    }
    final pos = NovelTtsPosition(
      chapterIndex: chapterIndex,
      paragraphIndex: paragraphIndex,
      updatedAt: DateTime.now(),
    );
    _cache[novelId] = pos;
    await _backend.set('$prefix$novelId', jsonEncode(pos.toJson()));
  }

  /// 清除（如清除阅读进度时一并清）。
  Future<void> clear(String novelId) async {
    _cache.remove(novelId);
    // PrefsBackend 没有 remove：写空串，读取时按「无记录」处理。
    await _backend.set('$prefix$novelId', '');
  }
}
