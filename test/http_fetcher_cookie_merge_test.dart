// HttpFetcher 显式 Cookie 头与 jar 合并语义回归锁。
//
// 背景：路由 headers / 脚本 __fetchHeaders 显式声明的 Cookie 此前会被
// _mergeHeaders 末尾的 jar 回带无条件覆盖——jar 一旦存有该站任何会话
// cookie（MacCMS 类站点每个页面都下发 PHPSESSID），显式头即整条丢失。
// 「挑战页内联 JS 写 cookie 后重试」类站点（挑战 cookie 只经
// document.cookie 写入浏览器，服务端从不用 Set-Cookie 下发）的二跳请求
// 因此永远带不上挑战令牌。
//
// 契约：jar 在前、显式在后，同名 cookie 以显式值为准；无显式 Cookie 时
// 行为完全不变（只回带 jar 会话 cookie）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:nexhub/core/scraper/http_fetcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // 裸 test() 不会自动初始化 Binding，而 HttpFetcher 单例的构造会触达
  // SharedPreferences 平台通道 → 显式初始化 + 打桩存储。
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  // syncCookies 会经 CookieStore 落盘（Hive）：测试进程内指向临时目录。
  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('hxq_cookie_merge_test').path);
  });

  HttpFetcher hf() => HttpFetcher.instance;

  // 独占假 host：jar 写入无清理钩子，用唯一 host 防用例间/文件间串味。
  const host = 'cookie-merge-test.example';
  const url = 'https://cookie-merge-test.example/search?a=1';

  test('jar 有会话 cookie 时，显式 Cookie 头不再被顶掉（按名合并）', () {
    hf().syncCookies(host, 'PHPSESSID=sess123; X_CACHE_KEY=k1');
    final merged = hf().debugMergedHeaders(
      url: url,
      extra: const <String, String>{'Cookie': 'challenge_token=t0k3n'},
    );
    expect(merged['Cookie'], contains('PHPSESSID=sess123'),
        reason: 'jar 会话 cookie 必须保留（部分站搜索依赖会话）');
    expect(merged['Cookie'], contains('challenge_token=t0k3n'),
        reason: '显式声明的挑战 cookie 必须到达线上请求头');
  });

  test('同名 cookie 显式值优先（新令牌覆盖 jar 里的过期同名值）', () {
    hf().syncCookies(host, 'challenge_token=stale');
    final merged = hf().debugMergedHeaders(
      url: url,
      extra: const <String, String>{'Cookie': 'challenge_token=fresh'},
    );
    expect(merged['Cookie'], 'challenge_token=fresh');
  });

  test('jar 无 cookie 时显式 Cookie 原样透传', () {
    final merged = hf().debugMergedHeaders(
      url: 'https://cookie-merge-fresh-test.example/x',
      extra: const <String, String>{'Cookie': 'a=1'},
    );
    expect(merged['Cookie'], 'a=1');
  });

  test('无显式 Cookie 时行为不变：只回带 jar 会话 cookie', () {
    hf().syncCookies(host, 'PHPSESSID=sess123');
    final merged = hf().debugMergedHeaders(url: url);
    expect(merged['Cookie'], 'PHPSESSID=sess123');
  });
}
