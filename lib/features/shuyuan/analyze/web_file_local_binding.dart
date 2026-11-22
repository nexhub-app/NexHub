/// 文件类书源：本地导入条目与在线书籍 / 源文件的绑定规则（纯函数，可单测）。
///
/// 下载时在 [LocalContentEntry] 写入来源三元组
/// （[LocalContentEntry.originSourceId] / [LocalContentEntry.originContentId] /
/// [LocalContentEntry.originFileUrl]）；详情页据此把本地书回挂到在线书籍，
/// 标记「已下载」、决定「开始阅读 / 继续阅读」指向哪一本本地书。
library;

import '../../../core/local/local_content_manager.dart' show LocalContentEntry;

/// 该条目是否由指定书籍（源 + 内容 ID）下载而来。
bool isWebBookOrigin(
  LocalContentEntry entry, {
  required String sourceId,
  required String contentId,
}) =>
    entry.originSourceId == sourceId && entry.originContentId == contentId;

/// 属于该书籍的全部本地条目（保持传入顺序）。
List<LocalContentEntry> boundWebBookEntries(
  Iterable<LocalContentEntry> all, {
  required String sourceId,
  required String contentId,
}) =>
    all
        .where((LocalContentEntry e) =>
            isWebBookOrigin(e, sourceId: sourceId, contentId: contentId))
        .toList(growable: false);

/// 源文件对应的本地条目；未下载返回 null。
///
/// 同一文件 URL 理论上只有一条（入库按路径去重）；若历史数据出现多条，
/// 取最近导入的一条。
LocalContentEntry? localEntryForWebFile(
  List<LocalContentEntry> bound,
  String fileUrl,
) {
  LocalContentEntry? best;
  for (final LocalContentEntry e in bound) {
    if (e.originFileUrl != fileUrl) continue;
    if (best == null || e.addedAt > best.addedAt) best = e;
  }
  return best;
}

/// 「开始阅读 / 继续阅读」指向的本地条目。
///
/// 优先最近读过（[viewedAt] 最大，来自浏览历史）；都没读过时取最近导入
/// （[LocalContentEntry.addedAt] 最大）。无条目返回 null。
LocalContentEntry? activeWebBookEntry(
  List<LocalContentEntry> bound, {
  required int Function(String entryId) viewedAt,
}) {
  if (bound.isEmpty) return null;
  LocalContentEntry? bestRead;
  int bestReadAt = 0;
  for (final LocalContentEntry e in bound) {
    final int at = viewedAt(e.id);
    if (at > bestReadAt) {
      bestReadAt = at;
      bestRead = e;
    }
  }
  if (bestRead != null) return bestRead;
  LocalContentEntry? latest;
  for (final LocalContentEntry e in bound) {
    if (latest == null || e.addedAt > latest.addedAt) latest = e;
  }
  return latest;
}
