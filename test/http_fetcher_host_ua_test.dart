// HttpFetcher 宿主级 UA 覆盖链路测试（v27 修复回归锁）。
//
// 背景：验证屏 / 登录屏通过 `registerHostUserAgent` 把「完整浏览器 UA」注册到
// 宿主；Cloudflare 的 cf_clearance 与 turnstile 通过态绑定**验证时那个 UA**。
// 此前只有图片 / 播放器 / WebView 走 `userAgentForUrl` 读到该覆盖，HTML/JSON
// 抓取走 `_mergeHeaders` 的指纹档案 UA（且被源 JSON 声明的 bot UA 覆盖）——
// 两套 UA 并存 ⇒ 会话对抓取请求失效 ⇒ 每次点击都跳转验证（用户问题①）。
//
// 注意：单例必须在测试运行期取（`HttpFetcher.instance` 的构造会触达
// AdvancedSettingsStore → SharedPreferences 平台通道，在 main() 顶层求值会
// 报 "Binding has not yet been initialized"）；因此统一走惰性函数 `hf()`。
import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/scraper/http_fetcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // 裸 test()（非 testWidgets）不会自动初始化 Binding，而 HttpFetcher 单例的
  // 构造会触达 SharedPreferences 平台通道 → 必须显式初始化 + 打桩存储。
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(const <String, Object>{});

  HttpFetcher hf() => HttpFetcher.instance;

  setUp(() => hf().debugClearHostUserAgents());
  tearDown(() => hf().debugClearHostUserAgents());

  const url = 'https://hanime1.me/watch?v=408357';
  const browserUa =
      'Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  test('注册宿主 UA 后，真实请求头用该 UA（而非指纹档案 UA）', () {
    hf().registerHostUserAgent('hanime1.me', browserUa);
    final merged = hf().debugMergedHeaders(url: url);
    expect(merged['User-Agent'], browserUa,
        reason: 'cf_clearance 绑定验证时 UA，抓取请求必须复用同一 UA');
  });

  test('宿主 UA 生效时不再声明 Sec-Ch-Ua 三家头（UA 与品牌不能自相矛盾）', () {
    hf().registerHostUserAgent('hanime1.me', browserUa);
    final merged = hf().debugMergedHeaders(url: url);
    expect(merged.containsKey('Sec-Ch-Ua'), isFalse);
    expect(merged.containsKey('Sec-Ch-Ua-Mobile'), isFalse);
    expect(merged.containsKey('Sec-Ch-Ua-Platform'), isFalse);
  });

  test('无注册时回落指纹档案 UA，并配套三家客户端提示头', () {
    final merged = hf().debugMergedHeaders(url: url);
    expect(merged['User-Agent'], isNotEmpty);
    expect(merged['User-Agent'], hf().userAgentForUrl(url),
        reason: '抓取头与 userAgentForUrl 必须同源');
    expect(merged['Sec-Ch-Ua'], isNotNull);
    expect(merged['Sec-Ch-Ua-Mobile'], isNotNull);
    expect(merged['Sec-Ch-Ua-Platform'], isNotNull);
  });

  test('三处 UA 一致契约：合并头 == userAgentForUrl（有覆盖时）', () {
    hf().registerHostUserAgent('hanime1.me', browserUa);
    expect(hf().debugMergedHeaders(url: url)['User-Agent'],
        hf().userAgentForUrl(url));
  });

  test('宿主 UA 只作用于注册的那个 host', () {
    hf().registerHostUserAgent('hanime1.me', browserUa);
    final other = hf().debugMergedHeaders(url: 'https://example.com/x');
    expect(other['User-Agent'], isNot(browserUa));
  });

  test('Referer 与请求级 extra 头照常透传（清理 UA 不牵连来源头）', () {
    hf().registerHostUserAgent('hanime1.me', browserUa);
    final merged = hf().debugMergedHeaders(
      referer: 'https://hanime1.me/',
      extra: const <String, String>{'X-Test': 'v'},
      url: url,
    );
    expect(merged['Referer'], 'https://hanime1.me/');
    expect(merged['X-Test'], 'v');
    expect(merged['User-Agent'], browserUa, reason: 'extra 无 UA 时不夺权');
  });

  test('请求级 extra 声明 UA 时仍优先（v27 起源 JSON 不再声明，故不触发）', () {
    final merged = hf().debugMergedHeaders(
      extra: const <String, String>{'User-Agent': 'Custom/1.0'},
      url: url,
    );
    expect(merged['User-Agent'], 'Custom/1.0',
        reason: '这是 v27 前 bot UA 覆盖基础头的机制，源侧已移除该声明');
  });

  test('请求级显式 UA 偏离指纹档案（源声明移动端 UA）时撤下 Sec-Ch-Ua 三家头', () {
    const sourceUa = 'Mozilla/5.0 (Android)';
    final merged = hf().debugMergedHeaders(
      extra: const <String, String>{'User-Agent': sourceUa},
      url: 'https://img.example-cdn.test/thumbs/1/a_webp',
    );
    expect(merged['User-Agent'], sourceUa);
    expect(merged.containsKey('Sec-Ch-Ua'), isFalse);
    expect(merged.containsKey('Sec-Ch-Ua-Mobile'), isFalse);
    expect(merged.containsKey('Sec-Ch-Ua-Platform'), isFalse,
        reason: 'UA 与客户端提示品牌自相矛盾是显眼的自动化特征，严格 CDN 会按伪装请求拒绝');
  });

  test('请求级 UA 与指纹档案一致（图片兜底 UA）时保留客户端提示', () {
    final profileUa = hf().userAgentForUrl(url);
    final merged = hf().debugMergedHeaders(
      extra: <String, String>{'User-Agent': profileUa},
      url: url,
    );
    expect(merged['User-Agent'], profileUa);
    expect(merged['Sec-Ch-Ua'], isNotNull);
    expect(merged['Sec-Ch-Ua-Mobile'], isNotNull);
    expect(merged['Sec-Ch-Ua-Platform'], isNotNull,
        reason: '无源 UA 的常规图片请求不能因本次修复丢头');
  });

  test('user-agent 头名大小写不敏感：归一为单一 User-Agent 头', () {
    final merged = hf().debugMergedHeaders(
      extra: const <String, String>{'user-agent': 'Source/1.0 (Linux; Android)'},
      url: url,
    );
    final uaKeys = merged.keys
        .where((k) => k.toLowerCase() == 'user-agent')
        .toList();
    expect(uaKeys, <String>['User-Agent'], reason: '同一请求不能发出两份 UA 头');
    expect(merged['User-Agent'], 'Source/1.0 (Linux; Android)');
    expect(merged.containsKey('Sec-Ch-Ua'), isFalse);
  });
}
