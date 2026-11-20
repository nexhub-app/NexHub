/// 交互浏览器纯逻辑：data: URL 内联与 host 解析。真实 WebView 人工验证。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/features/shuyuan/presentation/shuyuan_browser_screen.dart';

void main() {
  test('data: 文本文档还原 HTML', () {
    expect(
      ShuyuanBrowserScreen.dataUrlToHtml(
          'data:text/html;charset=utf-8,%3Cdiv%3Ehi%3C/div%3E'),
      '<div>hi</div>',
    );
  });

  test('data: 图片包成 img；普通 URL 返回 null', () {
    expect(
      ShuyuanBrowserScreen.dataUrlToHtml('data:image/png;base64,AAAA'),
      contains('<img src="data:image/png;base64,AAAA"'),
    );
    expect(ShuyuanBrowserScreen.dataUrlToHtml('https://x.test/'), isNull);
  });

  test('finalUrl：about 与空值回退到打开地址', () {
    expect(
      ShuyuanBrowserScreen.resolveFinalUrl('about:blank', 'https://x.test/login'),
      'https://x.test/login',
    );
    expect(
      ShuyuanBrowserScreen.resolveFinalUrl('about:srcdoc', 'data:text/html,hi'),
      'data:text/html,hi',
    );
    expect(ShuyuanBrowserScreen.resolveFinalUrl(null, 'https://x.test/'),
        'https://x.test/');
    expect(ShuyuanBrowserScreen.resolveFinalUrl('  ', 'https://x.test/'),
        'https://x.test/');
  });

  test('finalUrl：真实 http(s) 地址保持原样', () {
    expect(
      ShuyuanBrowserScreen.resolveFinalUrl(
          'https://x.test/user/login', 'https://x.test/'),
      'https://x.test/user/login',
    );
  });
}
