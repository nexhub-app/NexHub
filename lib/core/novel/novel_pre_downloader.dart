/// 小说阅读中预下载器（跨类型对齐）。
///
/// 阅读进度越过阈值后，后台串行抓取后续 N 章正文并缓存：
/// - 内存 Map 提供会话内即时命中；
/// - Hive box `novel_pre_downloads` 持久化（键 = `novelId::chapterId`，
/// 值 = 块级 JSON），重开阅读器离线仍可读已预下载章节。
///
/// 缓存粒度：文本段与插图 URL（[NovelImageBlock.source] 不序列化，命中时
/// 由调用方按当前源回填防盗链 headers）。
library;

import 'dart:convert';

import 'package:hive/hive.dart';

import '../models/episode.dart' show Episode;
import '../models/novel_block.dart';
import '../models/plugin_config.dart' show PluginConfig;
import '../scraper/media_api_service.dart';
import '../utils/app_log.dart';

/// 预下载器（每次 new 一个实例即可；Hive box 懒打开）。
class NovelPreDownloader {
  static const String boxName = 'novel_pre_downloads';

  /// 会话内缓存：`novelId::chapterId` → 块列表。
  final Map<String, List<NovelBlock>> _memory = <String, List<NovelBlock>>{};

  /// 正在预下载的章节键集合（防止重复请求）。
  final Set<String> _inFlight = <String>{};

  Future<Box<dynamic>> _openBox() async {
    if (Hive.isBoxOpen(boxName)) return Hive.box(boxName);
    return Hive.openBox(boxName);
  }

  static String _key(String novelId, String chapterId) =>
      '$novelId::$chapterId';

  /// 读取缓存（内存优先，未命中查 Hive）；未缓存返回 null。
  Future<List<NovelBlock>?> cached(String novelId, String chapterId) async {
    final String key = _key(novelId, chapterId);
    final List<NovelBlock>? mem = _memory[key];
    if (mem != null) return mem;
    try {
      final Box<dynamic> box = await _openBox();
      final Object? raw = box.get(key);
      if (raw is! String || raw.isEmpty) return null;
      final List<NovelBlock> blocks = _decode(raw);
      _memory[key] = blocks;
      return blocks;
    } on Object catch (e) {
      AppLog.instance.w('[预下载] 读取缓存失败 $key: $e');
      return null;
    }
  }

  /// 判断是否存在缓存（读盘）。
  Future<bool> has(String novelId, String chapterId) async {
    final String key = _key(novelId, chapterId);
    if (_memory.containsKey(key)) return true;
    try {
      final Box<dynamic> box = await _openBox();
      final Object? raw = box.get(key);
      return raw is String && raw.isNotEmpty;
    } on Object {
      return false;
    }
  }

  /// 后台预下载从 [startIndex] 起的至多 [count] 章（串行，失败即停）。
  ///
  /// 返回实际成功下载的章节数（跳过缓存 / 抓取失败的章不计入）。
  /// 仅在命中缓存或正在下载时跳过；静默失败（不打扰阅读），写日志备查。
  Future<int> preDownload({
    required MediaApiService service,
    required PluginConfig source,
    required String novelId,
    required List<Episode> chapters,
    required int startIndex,
    required int count,
  }) async {
    int downloaded = 0;
    for (int i = startIndex; i < chapters.length && downloaded < count; i++) {
      final Episode chapter = chapters[i];
      final String key = _key(novelId, chapter.id);
      if (_memory.containsKey(key) || _inFlight.contains(key)) {
        continue;
      }
      if (await has(novelId, chapter.id)) continue;
      _inFlight.add(key);
      try {
        final String? nextUrl =
            i + 1 < chapters.length ? chapters[i + 1].url : null;
        final List<NovelBlock> blocks = await service.fetchNovelContent(
          source,
          novelId: novelId,
          chapterUrl: chapter.url,
          nextChapterUrl: nextUrl,
        );
        _memory[key] = blocks;
        await _persist(key, blocks);
        downloaded++;
      } on Object catch (e) {
        AppLog.instance.w('[预下载] 章节抓取失败 ${chapter.title}: $e');
        break; // 连续失败不再继续，避免流量/请求风暴。
      } finally {
        _inFlight.remove(key);
      }
    }
    return downloaded;
  }

  /// 删除单章缓存（购买成功后强制重取正文；内存 + Hive 同步清理）。
  Future<void> dropChapter(String novelId, String chapterId) async {
    final String key = _key(novelId, chapterId);
    _memory.remove(key);
    try {
      final Box<dynamic> box = await _openBox();
      await box.delete(key);
    } on Object catch (e) {
      AppLog.instance.w('[预下载] 删除缓存失败 $key: $e');
    }
  }

  /// 按作品清空缓存（预下载设置关闭 / 源切换时可调用清理）。
  Future<void> clearForNovel(String novelId) async {
    _memory.removeWhere((k, _) => k.startsWith('$novelId::'));
    try {
      final Box<dynamic> box = await _openBox();
      final List<dynamic> keys = box.keys
          .where((k) => k is String && k.startsWith('$novelId::'))
          .toList();
      for (final Object k in keys) {
        await box.delete(k);
      }
    } on Object {
      // 清理失败忽略。
    }
  }

  Future<void> _persist(String key, List<NovelBlock> blocks) async {
    try {
      final Box<dynamic> box = await _openBox();
      await box.put(
        key,
        jsonEncode(blocks.map(_encode).toList()),
      );
    } on Object catch (e) {
      AppLog.instance.w('[预下载] 持久化失败 $key: $e');
    }
  }

  static Map<String, dynamic> _encode(NovelBlock block) {
    if (block is NovelImageBlock) {
      return <String, dynamic>{
        't': 'img',
        'url': block.url,
        'style': block.style,
      };
    }
    final NovelTextBlock text = block as NovelTextBlock;
    return <String, dynamic>{
      't': 'text',
      'text': text.text,
      'heading': text.isHeading,
    };
  }

  static List<NovelBlock> _decode(String raw) {
    final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
    return list.map<NovelBlock>((dynamic e) {
      final Map<String, dynamic> m = e as Map<String, dynamic>;
      if (m['t'] == 'img') {
        return NovelImageBlock(
          m['url'] as String? ?? '',
          style: m['style'] as String?,
        );
      }
      return NovelTextBlock(
        m['text'] as String? ?? '',
        isHeading: m['heading'] as bool? ?? false,
      );
    }).toList();
  }
}