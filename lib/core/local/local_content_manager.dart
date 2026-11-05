/// 本地内容管理：导入历史的持久化与本地文件的类型识别。
///
/// 供 browse_local / content_import 复用，集中「本地媒体类型」单一真源，
/// 避免各 feature 自行散布扩展名判断逻辑。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' show Directory, File, FileSystemException;

import 'package:media_kit/media_kit.dart';

import '../player/player_runtime.dart';
import 'package:nexhub/core/local/archive_extractor.dart';
import 'package:nexhub/core/local/local_novel_parser.dart';
import 'package:nexhub/core/local/pdf_util.dart';
import 'package:nexhub/core/platform/ohos_public_storage.dart'
    show isOhosDocPath;
import 'package:nexhub/core/storage/platform_path_compat.dart'
    show isPathSupportedOnThisPlatform;
import 'package:nexhub/core/utils/app_log.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地可播放/可读的媒体类型。
enum LocalMediaKind {
  video,
  images,
  text,
  pdf;

  String get apiName => name;

  static LocalMediaKind? parse(String? raw) {
    if (raw == null) return null;
    for (final k in LocalMediaKind.values) {
      if (k.name == raw) return k;
    }
    return null;
  }
}

/// 按扩展名识别本地文件媒体类型（目录交给 [classifyFolderByContent]）。
///
/// 白名单覆盖核心场景并扩展示例常见格式：漫画 cbz/cbr/cbt/zip/rar/7z/cb7、
/// 小说 txt/epub/umd/mobi/fb2/md/azw3、视频 mp4/mkv/mov/webm/avi/flv/m4v/ts/
/// wmv/mpg/mpeg/rmvb、图片 jpg/jpeg/png/webp/gif/bmp。扩展名匹配大小写不敏感。
LocalMediaKind? classifyByPath(String path) {
  final ext = p.extension(path).toLowerCase();
  if (<String>['.txt', '.epub', '.umd', '.mobi', '.fb2', '.md', '.azw3']
      .contains(ext)) {
    return LocalMediaKind.text;
  }
  if (<String>[
    '.cbz',
    '.cbr',
    '.cbt',
    '.zip',
    '.rar',
    '.7z',
    '.cb7',
  ].contains(ext)) {
    return LocalMediaKind.images;
  }
  if (<String>[
    '.mp4',
    '.mkv',
    '.mov',
    '.webm',
    '.avi',
    '.flv',
    '.m4v',
    '.ts',
    '.wmv',
    '.mpg',
    '.mpeg',
    '.rmvb',
    '.m3u8',
  ].contains(ext)) {
    return LocalMediaKind.video;
  }
  if (<String>['.pdf'].contains(ext)) {
    return LocalMediaKind.pdf;
  }
  if (<String>[
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
  ].contains(ext)) {
    return LocalMediaKind.images;
  }
  return null;
}

/// 判断路径是否为 Android SAF URI（content://）。
///
/// 安卓分区存储下，文件夹导入应统一走 [pickFolderPath]（内部 `saf.pickDirectory`）
/// 拿到 content:// tree URI；这类 URI 无法用 dart:io 的 [Directory]/[File] 直接
/// 访问（`Directory.list` 在真实路径下会"exists 成功却列不出文件"或抛
/// [FileSystemException]），需通过 SAF 插件读取。注意 `file_picker.getDirectoryPath`
/// 在部分设备返回的是真实路径（非 content://），拿到后必须据此分支处理，不能假设
/// 一定是 SAF。调用方应给出明确提示而非静默失败——这是「选择目录却导入不了」的深层根因。
bool isAndroidSafUri(String path) => path.startsWith('content://');

/// 是否为需先解析落缓存才能用 dart:io 读取的「文档路径」：
/// Android SAF（`content://`）或鸿蒙公共目录（`ohosdoc://`）。
bool isDocUri(String path) => isAndroidSafUri(path) || isOhosDocPath(path);

/// SAF content:// 条目的封面计算由 [saf_bridge] 注入（避免与 local_content_manager
/// 形成循环依赖）。[computeLocalCover] 遇到 SAF URI 时转发给此函数，未注入则回退 null。
Future<String?> Function(String, LocalMediaKind)? _safCoverResolver;

void registerSafCoverResolver(Future<String?> Function(String, LocalMediaKind) fn) {
  _safCoverResolver = fn;
}

/// 本次会话内生成视频封面失败过的路径，避免 [computeLocalCover] 回填时
/// 反复创建 media_kit Player 拖慢启动（失败多为解码/平台不支持，重试无意义）。
final Set<String> _failedVideoCoverTries = <String>{};

/// 递归扫描目录，按里面真实文件的多数扩展名决定 [LocalMediaKind]。
///
/// 实现：不再一刀切标 images。混合目录按多数决定；空目录或全未识别
/// 返回 null。目录不可读时抛 [FileSystemException]，由调用方走 l10n 提示。
/// 注意：Android SAF URI（content://）无法用 dart:io 列举，会抛
/// [FileSystemException]；调用方应先用 [isAndroidSafUri] 拦截并给出明确提示。
LocalMediaKind? classifyFolderByContent(String dirPath) {
  if (isAndroidSafUri(dirPath)) {
    throw FileSystemException(
      'Android SAF URI cannot be listed via dart:io Directory.list',
      dirPath,
    );
  }
  final dir = Directory(dirPath);
  final counts = <LocalMediaKind, int>{};
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final kind = classifyByPath(entity.path);
    if (kind == null) continue;
    counts[kind] = (counts[kind] ?? 0) + 1;
  }
  if (counts.isEmpty) {
    // 目录为空或没有可识别的媒体文件：记警告日志，便于排查「导入/打开无反应」。
    AppLog.instance.w('[本地类型识别] 目录为空或无已识别媒体文件: $dirPath');
    return null;
  }
  final sorted = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return sorted.first.key;
}

bool isImageFile(String path) =>
    classifyByPath(path) == LocalMediaKind.images;

/// 漫画归档扩展名（进入阅读器 / 取封面首图）：ZIP/CBZ、TAR/CBT、7z/CB7、RAR/CBR。
///
/// 覆盖 .cbr/.rar/.7z 等原 [archive] 包 [ZipDecoder] 不支持的格式；这些格式现由
/// [extractArchiveImages]（基于 [koni_archive] 纯 Dart）解压。
const List<String> _kComicArchiveExts = <String>[
  '.cbz',
  '.cbr',
  '.cbt',
  '.zip',
  '.rar',
  '.7z',
  '.cb7',
];

bool isComicArchive(String lowerPath) =>
    _kComicArchiveExts.any((e) => lowerPath.endsWith(e));

/// 漫画扫描时忽略的非媒体扩展名：这些文件（配置/元数据/文档/字幕/音视频等）出现于
/// 漫画文件夹内不应被当作「独立一话」。漫画页只可能是图片或归档，`.json`/`.txt`/
/// `.xml`/`.ts` 等显然不是漫画内容，误识别会导致阅读器尝试把文本/视频当图片打开而失败。
const List<String> kComicIgnoreExts = <String>[
  // 文本 / 文档 / 配置 / 元数据
  '.json', '.xml', '.txt', '.md', '.nfo', '.ini', '.cfg', '.conf',
  '.log', '.bak', '.tmp', '.part', '.db', '.sqlite', '.torrent',
  // 字幕
  '.srt', '.ass', '.ssa', '.vtt', '.sub', '.smi',
  // 音频
  '.mp3', '.m4a', '.aac', '.flac', '.wav', '.ogg', '.wma',
  // 视频（绝不可能是漫画页）
  '.mp4', '.mkv', '.mov', '.webm', '.avi', '.flv', '.m4v', '.ts',
  '.wmv', '.mpg', '.mpeg', '.rmvb',
];

/// 判断文件是否应被漫画扫描忽略（扩展名命中 [kComicIgnoreExts]）。
bool isComicIgnored(String lowerPath) =>
    kComicIgnoreExts.any((e) => lowerPath.endsWith(e));

/// 自然排序比较器：把字符串切成「数字段 / 非数字段」交替序列，数字段按数值比较
/// （"第2章" < "第10章"），非数字段按字典序。用于文件夹聚合时维持
/// 章节 / 话的文件顺序，避免纯字典序把 10 排到 2 前面。
int naturalCompare(String a, String b) {
  final List<String> ap = _splitNatural(a);
  final List<String> bp = _splitNatural(b);
  final int n = ap.length < bp.length ? ap.length : bp.length;
  for (int i = 0; i < n; i++) {
    final int? ax = int.tryParse(ap[i]);
    final int? bx = int.tryParse(bp[i]);
    final int c;
    if (ax != null && bx != null) {
      c = ax.compareTo(bx);
    } else {
      c = ap[i].compareTo(bp[i]);
    }
    if (c != 0) return c;
  }
  return ap.length.compareTo(bp.length);
}

List<String> _splitNatural(String s) {
  final List<String> parts = <String>[];
  final re = RegExp(r'(\d+|\D+)');
  for (final m in re.allMatches(s)) {
    parts.add(m.group(0)!);
  }
  return parts;
}

/// 递归扫描文件夹，收集指定媒体类型的真实文件路径，并按 [naturalCompare] 排序。
///
/// 目录不可读（如 Android SAF URI，`dart:io` 无法列举）会抛 [FileSystemException]，
/// 由调用方走 l10n 提示。桌面端真实路径可正常枚举；手机端文件夹聚合随下载那一期
/// （SAF 目录列举）一起支持。
List<String> listFolderFilesByKind(String dir, LocalMediaKind kind) {
  final dirObj = Directory(dir);
  final List<String> files = dirObj
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((f) => classifyByPath(f.path) == kind)
      .map((f) => f.path)
      .toList();
  files.sort(naturalCompare);
  return files;
}

/// 扫描漫画文件夹，区分「散图」与「漫画归档（含 PDF）」，分别自然排序返回。
///
/// - 散图（jpg/png/webp/gif/bmp）：整部漫画的一页页，导入为单条（路径=文件夹）。
/// - 归档（cbz/cbr/cbt/zip/rar/7z/cb7/pdf）：每个文件 = 一话，导入为聚合条目
/// （[LocalContentEntry.filePaths]），对应 B 阶段第 5 点。
/// 目录不可读抛 [FileSystemException]，由调用方走 l10n 提示。
({List<String> rawImages, List<String> archives, List<String> others})
    scanComicFolder(String dir) {
  final dirObj = Directory(dir);
  final List<String> raw = <String>[];
  final List<String> arch = <String>[];
  final List<String> other = <String>[];
  for (final entity in dirObj.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final ext = p.extension(entity.path).toLowerCase();
    if (<String>['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp']
        .contains(ext)) {
      raw.add(entity.path);
    } else     if (<String>[
          '.cbz',
          '.cbr',
          '.cbt',
          '.zip',
          '.rar',
          '.7z',
          '.cb7',
          '.pdf',
        ].contains(ext)) {
      arch.add(entity.path);
    } else if (isComicIgnored(ext)) {
      // 忽略配置/元数据/文档/音视频等非漫画文件，不当作漫画章节。
    } else {
      // 非图片、非已知归档的其它文件（如非常规归档/文档），也作为独立一话。
      other.add(entity.path);
    }
  }
  raw.sort(naturalCompare);
  arch.sort(naturalCompare);
  other.sort(naturalCompare);
  if (raw.isEmpty && arch.isEmpty && other.isEmpty) {
    // 目录下既无散图、也无归档/其它文件：记警告日志，便于排查「打开漫画文件夹无反应」。
    AppLog.instance.w('[本地漫画扫描] 目录未发现图片/归档/其它文件: $dir');
  }
  return (rawImages: raw, archives: arch, others: other);
}

/// 计算本地内容的封面路径：取「第一张图片」作为封面（用户建议）。
///
/// - 单图文件：直接返回其路径。
/// - 图片目录：返回按名排序后的第一张松散图片。
/// - 文件夹内的 .cbz/.zip：取目录内排序第一的压缩包，解压其首图作为封面。
/// - .cbz / .zip 文件：仅解压第一张图到应用私有目录 `local_covers/` 并引用，
/// 避免每次进列表都全量解压（落盘缓存）。
/// - 视频 / 文本（非 images）：无封面，返回 null。
/// 任何异常均返回 null（封面回退占位图），不阻断导入流程。
Future<String?> computeLocalCover(String path, LocalMediaKind kind) async {
  // SAF content:// URI 无法用 dart:io 处理，转发给 saf_bridge 的 SAF 枚举/解析版。
  if (isAndroidSafUri(path)) {
    final resolver = _safCoverResolver;
    if (resolver != null) return await resolver(path, kind);
    return null;
  }
  // PDF 封面：渲染首页为图片（失败回退占位）。
  if (kind == LocalMediaKind.pdf) {
    return await extractPdfCover(path);
  }
  // EPUB 封面：从压缩包提取封面图（bug 115）。
  if (kind == LocalMediaKind.text &&
      path.toLowerCase().endsWith('.epub')) {
    final cover = await LocalNovelParser.extractCover(path);
    if (cover != null) return cover;
  }
  // 视频：优先用文件夹内已有封面（poster/folder/cover… 或同名图），
  // 没有再截首帧生成（本地导入视频无封面问题）。
  if (kind == LocalMediaKind.video) {
    final folderCover = _findFolderCover(path);
    if (folderCover != null) return folderCover;
    return await extractVideoThumbnail(path);
  }
  if (kind != LocalMediaKind.images) return null;
  try {
    final lower = path.toLowerCase();
    if (isComicArchive(lower)) {
      return await _extractFirstImageFromArchive(path);
    }
    final f = File(path);
    if (await f.exists()) return path; // 单图文件
    final dir = Directory(path);
    if (await dir.exists()) {
      // 优先取目录内松散图片（按名排序第一张）。
      final loose = dir
          .listSync()
          .whereType<File>()
          .where((x) => isImageFile(x.path))
          .map((x) => x.path)
          .toList()
        ..sort();
      if (loose.isNotEmpty) return loose.first;
      // 否则取目录内第一个漫画归档，解压其首图作为封面（多格式）。
      final archives = dir
          .listSync()
          .whereType<File>()
          .where((x) => isComicArchive(x.path.toLowerCase()))
          .map((x) => x.path)
          .toList()
        ..sort();
      if (archives.isNotEmpty) {
        return await _extractFirstImageFromArchive(archives.first);
      }
    }
  } catch (_) {
    return null;
  }
  return null;
}

/// 本地视频文件夹内常见封面文件名（不含扩展名，按优先级，不区分大小写）。
const List<String> kFolderCoverNames = <String>[
  'poster',
  'folder',
  'cover',
  'fanart',
  'albumart',
  'thumbnail',
  'backdrop',
  'artwork',
  'banner',
  'landscape',
];

/// 若视频所在文件夹存在封面图，返回其路径；否则返回 null。
///
/// 扫描父目录：先按常见封面名（poster/folder/cover…）+ 图片扩展名匹配，
/// 再回退到「与视频同名（去扩展名）的图片」，如 ep01.mp4 → ep01.jpg。
/// 命中即直接使用，避免无谓的截帧解码开销。
String? _findFolderCover(String videoPath) {
  try {
    final dir = Directory(p.dirname(videoPath));
    if (!dir.existsSync()) return null;
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => isImageFile(f.path))
        .toList();
    if (files.isEmpty) return null;
    final byName = <String, String>{};
    for (final f in files) {
      byName[p.basenameWithoutExtension(f.path).toLowerCase()] = f.path;
    }
    for (final name in kFolderCoverNames) {
      final hit = byName[name];
      if (hit != null) return hit;
    }
    final base = p.basenameWithoutExtension(videoPath).toLowerCase();
    final same = byName[base];
    if (same != null) return same;
    return null;
  } on Object {
    return null;
  }
}

/// 为本地视频生成首帧缩略图，落盘到 `local_covers/video_<hash>.jpg` 并返回路径；
/// 任意失败（解码失败 / 平台不支持）返回 null，由 UI 回退占位图，不阻断导入。
///
/// 复用 media_kit 的 [Player.screenshot] 截首帧，避免引入额外依赖。位于此而非
/// 播放器内部，是因为导入流程（browse_local / content_import）需要在无播放页的
/// 情况下为视频生成封面。无视频画面（Web / 部分平台）时安全回退 null。
///
/// 注意：**必须播放态截图**。旧实现 `play: false` + 轮询 `stream.position`，
/// 但 mpv 暂停态下 time-pos 不推进，等待恒超时 → 截帧拿不到帧、缓存无封面。
/// 现改为静音播放约 1.2s（解码管线活跃）后 seek 到 1s 处截图，稳定可靠。
///
/// 注意：media_kit 的 NativePlayer 初始化时默认设置 mpv 选项 `vid=no`（禁用
/// 视频轨道解码），仅在 [VideoController] attach 时才改回 `vid=auto`。本函数
/// 无 VideoController，必须显式启用视频轨道，否则 `screenshot()`（mpv
/// screenshot-raw）取不到任何视频帧、恒返回空 → 封面从未写入缓存（本地导入
/// 视频无封面根因）。Web 平台无 NativePlayer，保持回退 null。
Future<String?> extractVideoThumbnail(String path) async {
  Player? player;
  try {
    PlayerRuntime.ensureInitialized();
    player = Player(configuration: const PlayerConfiguration(muted: true));
    try {
      final platform = player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty('vid', 'auto');
      }
    } on Object {
      // 平台不支持 mpv 属性设置（如 Web）或属性无效，忽略，截图回退 null。
    }
    await player.open(Media(path), play: true);
    // 等时长就绪 = 元数据解析成功（暂停态也会更新，作为打开成功的信号）。
    final Completer<void> ready = Completer<void>();
    late final StreamSubscription<Duration?> sub;
    sub = player.stream.duration.listen((Duration? d) {
      if (!ready.isCompleted && d != null && d > Duration.zero) {
        sub.cancel();
        ready.complete();
      }
    });
    await ready.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => sub.cancel(),
    );
    // 播放约 1.2s，确保首帧 / 关键帧已解码并渲染，截图稳定。
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    // 跳到 1s 处取帧，避开黑屏开场。
    await player.seek(const Duration(seconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final Uint8List? bytes = await player.screenshot(format: 'image/jpeg');
    if (bytes == null) {
      // 返回空（无视频轨道 / 解码失败）也记入失败集合：否则每次启动
      // _backfillMissingCovers 都会对同一视频重建 Player 播 1.5s，拖慢启动。
      _failedVideoCoverTries.add(path);
      AppLog.instance.w('[本地视频封面] 截帧返回空: $path');
      return null;
    }
    final dir = await getApplicationDocumentsDirectory();
    final coverDir = Directory(p.join(dir.path, 'local_covers'));
    await coverDir.create(recursive: true);
    final target =
        File(p.join(coverDir.path, 'video_${path.hashCode}.jpg'));
    await target.writeAsBytes(bytes);
    AppLog.instance.i('[本地视频封面] 生成成功: $path -> ${target.path}');
    return target.path;
  } on Object catch (e, st) {
    _failedVideoCoverTries.add(path);
    AppLog.instance.eWithStack('[本地视频封面] 缩略图生成失败: $path', e, st);
    return null;
  } finally {
    await player?.dispose();
  }
}

/// 仅解压漫画归档内自然排序第一张图片到 `local_covers/` 缓存目录，返回其路径。
///
/// 委托 [extractFirstArchiveImage]（基于 [koni_archive]，纯 Dart 支持
/// ZIP/CBZ、TAR/CBT、7z/CB7、RAR/CBR 含 RAR5），使 .cbr/.rar/.7z 的封面也能
/// 正常生成。任何异常返回 null（封面回退占位图），不阻断导入流程。
Future<String?> _extractFirstImageFromArchive(String path) async {
  try {
    final tmp = await extractFirstArchiveImage(path);
    final dir = await getApplicationDocumentsDirectory();
    final coverDir = Directory(p.join(dir.path, 'local_covers'));
    await coverDir.create(recursive: true);
    final ext = p.extension(tmp).isEmpty ? '.jpg' : p.extension(tmp);
    final target = File(p.join(coverDir.path, '${path.hashCode}_cover$ext'));
    await File(tmp).copy(target.path);
    return target.path;
  } on Object {
    return null;
  }
}

/// 单条本地导入记录。
class LocalContentEntry {
  final String id;
  final String title;
  final String path;
  final LocalMediaKind kind;
  final int addedAt;

  /// 封面图路径（本地文件绝对路径）。导入时取「第一张图片」并落盘缓存；
  /// 无封面（视频/文本/无图）为 null，由 UI 回退占位图。
  final String? coverUrl;

  /// 聚合文件夹导入时的子文件列表（按文件名字自然排序）。
  ///
  /// 非空表示此条目是「一本书 / 一部漫画」：文件夹内每个文件 = 一章 / 一话，
  /// 阅读器据此展示目录并可点选跳转。单文件导入或散图文件夹导入为 null
  /// （散图文件夹由阅读器实时扫描目录内图片，无需预存列表）。
  final List<String>? filePaths;

  /// 作者（仅小说条目）：导入期从文件名自动解析（`《书名》作者：xx` 等
  /// 常见命名），EPUB 元数据优先。解析不出为 null。
  final String? author;

  const LocalContentEntry({
    required this.id,
    required this.title,
    required this.path,
    required this.kind,
    required this.addedAt,
    this.coverUrl,
    this.filePaths,
    this.author,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'path': path,
        'kind': kind.apiName,
        'addedAt': addedAt,
        'coverUrl': coverUrl,
        'filePaths': filePaths,
        'author': author,
      };

  factory LocalContentEntry.fromJson(Map<String, dynamic> json) => LocalContentEntry(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        path: json['path'] as String? ?? '',
        kind: LocalMediaKind.parse(json['kind'] as String?) ?? LocalMediaKind.text,
        addedAt: json['addedAt'] as int? ?? 0,
        coverUrl: json['coverUrl'] as String?,
        filePaths: (json['filePaths'] as List?)
            ?.map((e) => e as String)
            .toList(),
        author: json['author'] as String?,
      );

  /// 浅拷贝并覆盖部分字段（用于重命名等）。
  LocalContentEntry copyWith({
    String? id,
    String? title,
    String? path,
    LocalMediaKind? kind,
    int? addedAt,
    String? coverUrl,
    List<String>? filePaths,
    String? author,
  }) =>
      LocalContentEntry(
        id: id ?? this.id,
        title: title ?? this.title,
        path: path ?? this.path,
        kind: kind ?? this.kind,
        addedAt: addedAt ?? this.addedAt,
        coverUrl: coverUrl ?? this.coverUrl,
        filePaths: filePaths ?? this.filePaths,
        author: author ?? this.author,
      );
}

/// 本地导入历史管理（SharedPreferences 持久化）。
///
/// 继承 [ChangeNotifier] 以便书架等 UI 订阅导入列表变化（修复）：
/// 之前的实现由各导入页本地实例化且未调用 [init]，导致 `add` 写入时
/// `_items` 为空 → `_persist` 覆盖旧记录，重启后导入历史丢失。
/// 现统一在 splash 创建单例、注册为 Provider，导入页通过 `context.read` 复用。
class LocalContentManager extends ChangeNotifier {
  static const String _key = 'local_imports_v1';

  final List<LocalContentEntry> _items = <LocalContentEntry>[];

  /// 倒序的导入历史（最新在前）。
  List<LocalContentEntry> get items => List.unmodifiable(_items);

  /// 加载持久化数据。
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _items
        ..clear()
        ..addAll(list.map((e) => LocalContentEntry.fromJson(e as Map<String, dynamic>)));
      notifyListeners();
      // 回填历史条目的封面：早于「取第一张图当封面」逻辑导入的漫画（images 类）
      // 持久化时 coverUrl 为 null，加载后从不补算 → 书架一直显示空白/占位。
      // 这里对缺封面的图片类条目补算首图并写回，UI 端（Image.file）随即显示。
      await _backfillMissingCovers();
    } catch (_) {
      // 损坏数据忽略
    }
  }

  /// 为缺封面的历史条目补算封面并持久化。
  ///
  /// 处理图片类（取首图）、视频类（media_kit 截首帧）、PDF（渲染首页）、
  /// EPUB（从压缩包提取封面图）且 `coverUrl == null` 的条目；补算失败
  ///（损坏包 / 解码失败）静默跳过，保持 null 由 UI 回退占位。
  Future<void> _backfillMissingCovers() async {
    var dirty = false;
    for (var i = 0; i < _items.length; i++) {
      final e = _items[i];
      if (e.coverUrl != null) continue;
      // 外来平台路径（导入其他平台备份带进来的）在本机根本不存在：逐个尝试只
      // 会拖慢启动（视频还要建 Player 截帧），直接跳过、保留占位图。
      if (!isPathSupportedOnThisPlatform(e.path)) continue;
      // 仅补图片、视频、PDF、EPUB（text+.epub）；其余类型无封面。
      final bool isEpub = e.kind == LocalMediaKind.text &&
          e.path.toLowerCase().endsWith('.epub');
      if (e.kind != LocalMediaKind.images &&
          e.kind != LocalMediaKind.video &&
          e.kind != LocalMediaKind.pdf &&
          !isEpub) {
        continue;
      }
      // 本会话已失败过的视频跳过，避免启动时反复创建 Player 拖慢启动。
      if (e.kind == LocalMediaKind.video &&
          _failedVideoCoverTries.contains(e.path)) {
        continue;
      }
      final cover = await computeLocalCover(e.path, e.kind);
      if (cover == null) continue;
      _items[i] = LocalContentEntry(
        id: e.id,
        title: e.title,
        path: e.path,
        kind: e.kind,
        addedAt: e.addedAt,
        coverUrl: cover,
        // 补封面时保留聚合文件列表，避免把「一本书/一部漫画」降级成单文件。
        filePaths: e.filePaths,
      );
      dirty = true;
    }
    if (dirty) {
      await _persist();
      notifyListeners();
    }
  }

  /// 新增一条导入记录（去重：相同 path 不重复添加）。
  ///
  /// 若条目未带封面，自动计算并落盘缓存封面（取第一张图片），见
  /// [computeLocalCover]。旧版本持久化记录无 `coverUrl` 字段时同样在
  /// 重新导入时补全。
  Future<void> add(LocalContentEntry entry) async {
    final existingIndex = _items.indexWhere((e) => e.path == entry.path);
    if (existingIndex >= 0) {
      // 已存在同路径：不重复添加，但若旧记录缺封面（图片类）或缺聚合文件列表
      // （早期版本 add 丢弃 filePaths 的历史缺陷），借这次重新导入补全，兑现
      // 「重新导入时修复旧记录」的承诺。
      final existing = _items[existingIndex];
      final bool needFilePaths =
          entry.filePaths != null && entry.filePaths!.isNotEmpty;
      final bool needCover = existing.coverUrl == null &&
          (existing.kind == LocalMediaKind.images ||
              existing.kind == LocalMediaKind.video);
      if (needFilePaths || needCover) {
        final String? coverUrl = existing.coverUrl ??
            await computeLocalCover(existing.path, existing.kind);
        _items[existingIndex] = LocalContentEntry(
          id: existing.id,
          title: entry.title.isEmpty ? existing.title : entry.title,
          path: existing.path,
          kind: entry.kind,
          addedAt: existing.addedAt,
          coverUrl: coverUrl,
          filePaths: needFilePaths ? entry.filePaths : existing.filePaths,
        );
        await _persist();
        notifyListeners();
      }
      return;
    }
    final String? coverUrl = entry.coverUrl ??
        await computeLocalCover(entry.path, entry.kind);
    final covered = LocalContentEntry(
      id: entry.id,
      title: entry.title,
      path: entry.path,
      kind: entry.kind,
      addedAt: entry.addedAt,
      coverUrl: coverUrl,
      // 聚合导入（文件夹=一本书/一部漫画）必须保留子文件列表，否则打开时
      // 被当作单文件，SAF 目录 URI 会报「该路径是一个文件夹」。
      filePaths: entry.filePaths,
    );
    _items.insert(0, covered);
    await _persist();
    notifyListeners();
  }

  /// 重命名一条记录（仅改显示标题，不改原始文件路径）。
  Future<void> rename(String id, String newTitle) async {
    final idx = _items.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;
    _items[idx] = _items[idx].copyWith(title: trimmed);
    await _persist();
    notifyListeners();
  }

  /// 移除一条记录。
  ///
  /// [deleteFile] 为 true 时同时删除磁盘上的文件 / 目录（Android SAF 的
  /// `content://` 路径无法用 dart:io 删除，自动跳过仅删记录）。
  Future<void> remove(String id, {bool deleteFile = false}) async {
    final entry = _items.cast<LocalContentEntry?>().firstWhere(
          (e) => e?.id == id,
          orElse: () => null,
        );
    _items.removeWhere((e) => e.id == id);
    if (deleteFile && entry != null) {
      await _deleteFileAt(entry.path);
    }
    await _persist();
    notifyListeners();
  }

  /// 删除磁盘上的本地文件 / 目录；SAF 路径或删除失败均静默忽略（记录已移除）。
  Future<void> _deleteFileAt(String path) async {
    if (isAndroidSafUri(path)) return;
    try {
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
        return;
      }
      final d = Directory(path);
      if (await d.exists()) {
        await d.delete(recursive: true);
      }
    } on Object {
      // 删除失败不影响记录移除结果。
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _items.map((e) => e.toJson()).toList();
    await prefs.setString(_key, jsonEncode(list));
  }
}
