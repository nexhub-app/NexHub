/// concurrentRate 限速器（legado ConcurrentRateLimiter 等效，书源侧包装）。
///
/// 格式：`"N"` = 每 N ms 最多 1 次；`"limit/interval"` = interval 毫秒内
/// 最多 limit 次。按源（key=书源 URL）独立计数；AnalyzeUrl 请求前调用
/// [gate]，超限则等待到窗口放行。仅书源链路使用，媒体源零影响。
library;

class ConcurrentRateLimiter {
  ConcurrentRateLimiter._();

  static final Map<String, List<DateTime>> _hits = <String, List<DateTime>>{};

  /// 请求前调用：按 [rate] 规则对 [key]（书源标识）限速，必要时等待。
  static Future<void> gate(String? rate, String key) async {
    if (rate == null || rate.trim().isEmpty) return;
    final r = rate.trim();
    int limit;
    Duration interval;
    final slash = r.indexOf('/');
    if (slash > 0) {
      limit = int.tryParse(r.substring(0, slash)) ?? 0;
      interval =
          Duration(milliseconds: int.tryParse(r.substring(slash + 1)) ?? 0);
    } else {
      final n = int.tryParse(r) ?? 0;
      if (n <= 0) return;
      limit = 1;
      interval = Duration(milliseconds: n);
    }
    if (limit <= 0 || interval.inMilliseconds <= 0) return;

    final now = DateTime.now();
    final times = _hits.putIfAbsent('$key|$r', () => <DateTime>[]);
    times.removeWhere((t) => now.difference(t) > interval);
    if (times.length >= limit) {
      final wait = interval - now.difference(times.first);
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
    }
    times.add(DateTime.now());
    // 防泄漏：key 数量过多时清理无条目的 key。
    if (_hits.length > 512) {
      _hits.removeWhere((_, v) => v.isEmpty);
    }
  }
}
