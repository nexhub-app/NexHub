/// WebView Cookie 读取：最终页与起始页相关域的 Cookie 头（host → `name=value; ...`）。
///
/// 可见浏览器（ShuyuanBrowserScreen）与无头取源（ShuyuanWebviewFetcher）共用
/// 同一套分层读取，避免两处实现漂移：无头侧旧实现只查 `scheme://host`，服务端
/// 未显式声明 `Path` 的会话 Cookie（默认挂在请求目录，如 `/user`）会漏掉。
library;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 读取最终页与起始页相关域的 Cookie 头（host → `name=value; ...`）。
///
/// 三层读取，逐层兜底：
/// 1. **全页地址**：最终地址与起始地址（仅 http/https）各按完整 URL 取一次
///    `getCookies(url)`。Android 走 `android.webkit.CookieManager.getCookie(url)`，
///    Windows 走 CDP `Network.getCookies(urls:)`，二者都按路径匹配——服务端未
///    显式声明 `Path` 的会话 Cookie 默认挂在请求目录（如 `/user`），只有带 path
///    的页面地址才取得到，站点根地址取不到。
/// 2. **站点根**：同一地址再以 `scheme://host` 查一次兜底，覆盖全页地址查询
///    为空或抛错的情形，也保持原先「按域读取」的语义不变。
/// 3. **全量枚举**：`getAllCookies()` 只在 Apple 平台有实现（Android/Windows
///    抛 `UnimplementedError`，此处忽略），按 Cookie 自身域归组后只保留与最终
///    域/起始域相关者（排除 Cloudflare 挑战域等无关 Cookie）。
///
/// 同一 host 并入同一个桶；去重见 [_CookieBucket]。输出顺序由查询顺序
/// （全页地址 → 站点根 → 全量枚举）决定，保持稳定。
///
/// 只读：返回给调用方，不写入任何全局 Cookie jar。
Future<Map<String, String>> readWebviewCookieHeaders({
  required CookieManager manager,
  required InAppWebViewController controller,
  required String finalUrl,
  required String startUrl,
}) async {
  // key 为 host 小写；value 保留首个出现时的 host 大小写用于输出。
  final buckets = <String, _CookieBucket>{};
  // 已查询过的完整 URL（全页地址与站点根共用），同一地址只查一次。
  final queried = <String>{};
  for (final raw in <String>[finalUrl, startUrl]) {
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) continue;
    if (uri.scheme != 'http' && uri.scheme != 'https') continue;
    final bucket = buckets.putIfAbsent(
        uri.host.toLowerCase(), () => _CookieBucket(uri.host));
    // 全页地址在前（携带 path），站点根在后兜底。
    for (final url in <String>[
      uri.toString(),
      '${uri.scheme}://${uri.host}',
    ]) {
      if (!queried.add(url)) continue;
      try {
        final cookies = await manager.getCookies(
          url: WebUri(url),
          webViewController: controller,
        );
        for (final c in cookies) {
          bucket.add(c);
        }
      } catch (_) {}
    }
  }

  if (buckets.isNotEmpty) {
    final targetHosts = buckets.keys.toList(growable: false);
    bool isRelated(String host) => targetHosts.any(
        (th) => host == th || host.endsWith('.$th') || th.endsWith('.$host'));
    try {
      final all = await manager.getAllCookies();
      for (final c in all) {
        final rawDomain = (c.domain ?? '').trim().toLowerCase();
        final host =
            rawDomain.startsWith('.') ? rawDomain.substring(1) : rawDomain;
        if (host.isNotEmpty && !isRelated(host)) continue;
        // host-only Cookie（无 Domain）归入最终域，避免被漏掉。
        final key = host.isEmpty ? targetHosts.first : host;
        buckets.putIfAbsent(key, () => _CookieBucket(key)).add(c);
      }
    } catch (_) {
      // getAllCookies 在 Android/Windows 未实现（原生无全量接口），忽略：
      // 上面的全页地址 + 站点根读取已尽力覆盖。
    }
  }

  return <String, String>{
    for (final b in buckets.values)
      if (b.header.isNotEmpty) b.displayHost: b.header,
  };
}

/// 单 host 的 Cookie 头累积器：按插入顺序拼接 `name=value`。
///
/// 两级去重：先以「名字 + 域 + 路径」标识同一个 Cookie（Android 兼容路径解析
/// 可能不带域/路径，此时退化为按名去重），再对每个名字只保留首个值——查询顺序
/// （全页地址 → 站点根 → 全量枚举）即优先级，避免多层查询把同一 Cookie 写两遍，
/// 也避免同名多 path 拼出 `sid=a; sid=b` 这类不稳定输出。
class _CookieBucket {
  _CookieBucket(this.displayHost);

  final String displayHost;
  final List<String> _pairs = <String>[];
  final Set<String> _identities = <String>{};
  final Set<String> _names = <String>{};

  /// 收录一个 Cookie；同身份或同名的后来者直接丢弃。值为空按原语义跳过。
  void add(Cookie c) {
    final value = c.value?.toString() ?? '';
    if (value.isEmpty) return;
    final domain = (c.domain ?? '').trim().toLowerCase();
    final path = (c.path ?? '').trim();
    if (!_identities.add('${c.name}\u0000$domain\u0000$path')) return;
    if (!_names.add(c.name)) return;
    _pairs.add('${c.name}=$value');
  }

  String get header => _pairs.join('; ');
}
