/// concurrentRate 限速器（legado ConcurrentRateLimiter 等效，书源侧包装）。
///
/// 格式：`"N"` = 每 N ms 最多 1 次；`"limit/interval"` = interval 毫秒内
/// 最多 limit 次。按源（key=书源 URL）独立计数；AnalyzeUrl 请求前调用
/// [gate]，超限则等待到窗口放行。仅书源链路使用，媒体源零影响。
library;

class ConcurrentRateLimiter {
  ConcurrentRateLimiter._();

  /// 固定窗口计数（legado `ConcurrentRateLimiter` 模型）：每个 key 记录
  /// 窗口起点与窗口内已放行的次数，到 interval 重置。
  ///
  /// 旧实现是滑动窗口（移除 interval 前的命中），比基准更平滑、峰值更低；
  /// 但源的 concurrentRate 是按固定窗口调的（基准在窗口边界允许
  /// 「上一窗末尾 + 下一窗开头」连续 2×limit 次），对齐后与基准行为一致。
  static final Map<String, _RateWindow> _windows = <String, _RateWindow>{};

  /// 运行时覆盖（legado `BaseSource.putConcurrent` → ConcurrentRateLimiter
  /// 共享记录表）：脚本可在运行期调整本源并发率，覆盖源声明值直到进程结束。
  static final Map<String, String> _overrides = <String, String>{};

  /// 写入运行期并发率。`次数/毫秒` 或 `毫秒` 形态且数值有效才生效；
  /// 非法值忽略（对齐 legado `compute` 解析失败保留原记录的语义）。
  static void updateConcurrentRate(String key, String rate) {
    final r = rate.trim();
    if (r.isEmpty) return;
    final slash = r.indexOf('/');
    bool valid;
    if (slash > 0) {
      final limit = int.tryParse(r.substring(0, slash)) ?? 0;
      final interval = int.tryParse(r.substring(slash + 1)) ?? 0;
      valid = limit > 0 && interval > 0;
    } else {
      valid = (int.tryParse(r) ?? 0) > 0;
    }
    if (valid) _overrides[key] = r;
  }

  /// 生效并发率：运行期覆盖优先，其次源声明值。
  static String? effectiveRate(String? declared, String key) =>
      _overrides[key] ?? declared;

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

    var now = DateTime.now();
    final window = _windows.putIfAbsent('$key|$r', () => _RateWindow(now));
    if (now.difference(window.start) >= interval) {
      window.start = now;
      window.count = 0;
    }
    if (window.count >= limit) {
      // 窗口已满：等到本窗口结束再放行，并开启新窗口（计数器归零）。
      final wait = interval - now.difference(window.start);
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
      now = DateTime.now();
      window.start = now;
      window.count = 0;
    }
    window.count++;
    // 防泄漏：key 数量过多时清理已过期的窗口。
    if (_windows.length > 512) {
      _windows.removeWhere((_, w) => now.difference(w.start) > interval * 4);
    }
  }
}

/// 固定窗口计数：起点时间 + 窗口内放行次数。
class _RateWindow {
  _RateWindow(this.start);

  DateTime start;
  int count = 0;
}
