/// Windows / 桌面「跟随系统代理」发现器。
///
/// 背景：`HttpClient.findProxyFromEnvironment` 只读 `HTTP(S)_PROXY` 环境变量，
/// 而多数代理软件（Clash/v2ray 等）只写 Windows 注册表
/// `HKCU\...\Internet Settings`（`ProxyEnable` / `ProxyServer`），默认不设环境变量。
/// 于是「跟随系统代理」模式在实际使用中恒为 DIRECT——参考实现的桌面端做法是
/// 显式读注册表拿到代理规则，再交给 `findProxy`。
///
/// 本类只做「一次性探测 + 内存缓存」：`findProxy` 是同步回调，无法在回调里跑异步
/// 进程；调用方在启动完成 / 网络设置变更时调 [refresh] 即可（失败保持 DIRECT，
/// 绝不阻断业务）。解析失败的 PAC/自动配置脚本不处理（返回 DIRECT），由用户改用
/// 手动代理模式填写 host:port。
library;

import 'dart:io';

import '../../utils/app_log.dart';

class SystemProxyResolver {
  SystemProxyResolver._();

  /// 解析出的代理规则（`PROXY host:port` / `DIRECT` / 空串=尚未探测）。
  static String _rule = '';

  static String get rule => _rule;

  /// 是否已探测过。
  static bool get loaded => _rule.isNotEmpty;

  /// 探测系统代理（Windows 读注册表；其他桌面尽力读环境变量）。
  static Future<void> refresh() async {
    if (!Platform.isWindows) {
      _rule = 'DIRECT';
      return;
    }
    try {
      final enabledResult = await Process.run('reg', <String>[
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v',
        'ProxyEnable',
      ]);
      final enabled = enabledResult.exitCode == 0 &&
          RegExp(r'ProxyEnable\s+REG_DWORD\s+0x1', caseSensitive: false)
              .hasMatch(enabledResult.stdout.toString());
      if (!enabled) {
        _rule = 'DIRECT';
        return;
      }
      final serverResult = await Process.run('reg', <String>[
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v',
        'ProxyServer',
      ]);
      final raw = RegExp(r'ProxyServer\s+REG_SZ\s+(.+)', caseSensitive: false)
          .firstMatch(serverResult.stdout.toString())
          ?.group(1)
          ?.trim();
      _rule = parseProxyServerValue(raw) ?? 'DIRECT';
      AppLog.instance.i('系统代理: $_rule');
    } on Object catch (e) {
      _rule = 'DIRECT';
      AppLog.instance.w('系统代理探测失败，按直连处理: $e');
    }
  }

  /// 解析注册表 `ProxyServer` 的值：
  /// - `127.0.0.1:7890` → `PROXY 127.0.0.1:7890`
  /// - `http=127.0.0.1:7890;https=127.0.0.1:7890;socks=...` → 取 https，其次 http
  /// - 空/PAC → null（DIRECT）
  static String? parseProxyServerValue(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    if (value.contains('://') || value.toLowerCase().endsWith('.pac')) {
      // PAC / 完整 URL：findProxy 无法直接消费，交回 DIRECT。
      return null;
    }
    if (!value.contains('=')) {
      return _toProxy(value, 'PROXY');
    }
    String? https;
    String? http;
    String? socks;
    for (final part in value.split(';')) {
      final idx = part.indexOf('=');
      if (idx <= 0) continue;
      final scheme = part.substring(0, idx).trim().toLowerCase();
      final addr = part.substring(idx + 1).trim();
      if (addr.isEmpty) continue;
      if (scheme == 'https') {
        https ??= addr;
      } else if (scheme == 'http') {
        http ??= addr;
      } else if (scheme == 'socks') {
        socks ??= addr;
      }
    }
    final chosen = https ?? http;
    if (chosen != null) return _toProxy(chosen, 'PROXY');
    if (socks != null) return _toProxy(socks, 'SOCKS');
    return null;
  }

  static String? _toProxy(String hostPort, String scheme) {
    final hp = hostPort.trim();
    if (hp.isEmpty) return null;
    // 注册表里可能带协议前缀（http://host:port），剥掉。
    final cleaned = hp.replaceFirst(RegExp(r'^[a-zA-Z]+://'), '');
    if (!cleaned.contains(':')) return null;
    return '$scheme $cleaned';
  }
}
