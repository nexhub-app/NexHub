/// 网络配置服务：全局网络配置的单例状态源 + 有效档案计算。
///
/// - 持有当前 [NetworkConfig] 与解密后的代理密码；
/// - `globalProfile` 缓存全局有效档案；
/// - `effectiveFor(source)` 逐方面合并（用户覆盖 > 源文件 network 块 > 全局 > 默认）；
/// - 变更时清 DNS 缓存 + 重建 HttpFetcher 连接池，配置即时生效。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/plugin_config.dart';
import '../scraper/http_fetcher.dart';
import 'model/effective_network_profile.dart';
import 'model/network_config.dart';
import 'model/source_network_config.dart';
import 'runtime/dns_resolver.dart';
import 'runtime/network_client_builder.dart';
import 'runtime/sni_policy.dart';
import 'runtime/system_proxy_resolver.dart';
import 'source_network_override_store.dart';

/// 网络配置服务（ChangeNotifier 单例 + Provider）。
class NetworkConfigService extends ChangeNotifier {
  NetworkConfigService._();
  static final NetworkConfigService instance = NetworkConfigService._();

  static const String _prefsKey = 'network_config_v1';
  static const String _passwordKey = 'network_proxy_password';

  NetworkConfig _config = NetworkConfig.defaults;
  String? _proxyPassword;
  bool _loaded = false;
  EffectiveNetworkProfile? _globalProfileCache;

  NetworkConfig get config => _config;
  String? get proxyPassword => _proxyPassword;
  bool get loaded => _loaded;

  /// 全局有效档案（缓存，配置变更时失效）。
  EffectiveNetworkProfile get globalProfile =>
      _globalProfileCache ??= EffectiveNetworkProfile.fromConfig(_config);

  /// 从持久化加载（幂等）。
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        _config = NetworkConfig.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      }
    } on Object catch (e) {
      debugPrint('NetworkConfigService.load config failed: $e');
      _config = NetworkConfig.defaults;
    }
    try {
      _proxyPassword =
          await const FlutterSecureStorage().read(key: _passwordKey);
    } on Object catch (e) {
      debugPrint('NetworkConfigService.load password failed: $e');
    }
    _loaded = true;
    _globalProfileCache = null;
    // 桌面「跟随系统代理」：异步探测一次（Windows 注册表），缓存后供
    // findProxy 同步回调使用；失败保持 DIRECT，不阻断启动。
    unawaited(SystemProxyResolver.refresh());
    notifyListeners();
  }

  /// 更新配置（可选更新代理密码）。
  Future<void> update(NetworkConfig config, {String? password}) async {
    _config = config;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(config.toJson()));
    } on Object catch (e) {
      debugPrint('NetworkConfigService.update persist failed: $e');
    }
    if (password != null) {
      _proxyPassword = password;
      try {
        await const FlutterSecureStorage()
            .write(key: _passwordKey, value: password);
      } on Object catch (e) {
        debugPrint('NetworkConfigService.update password failed: $e');
      }
    }
    _onChanged();
  }

  /// 恢复默认网络设置。
  Future<void> resetToDefaults() async {
    _config = NetworkConfig.defaults;
    _proxyPassword = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
      await const FlutterSecureStorage().delete(key: _passwordKey);
    } on Object catch (e) {
      debugPrint('NetworkConfigService.resetToDefaults failed: $e');
    }
    _onChanged();
  }

  void _onChanged() {
    _loaded = true;
    _globalProfileCache = null;
    DnsResolver.instance.clearCache();
    HttpFetcher.instance.rebuildAll();
    notifyListeners();
    _notifyEffectiveConfigListeners();
  }

  /// 源级覆盖（[SourceNetworkOverrideStore]）变更后调用：
  /// 清 DNS 缓存 + 逐出旧连接池，使该源的新档案即时生效。
  void onSourceOverrideChanged() {
    DnsResolver.instance.clearCache();
    HttpFetcher.instance.rebuildAll();
    notifyListeners();
    _notifyEffectiveConfigListeners();
  }

  /// 有效档案变更后的附加回调。
  ///
  /// 供「需要跟随全局 / 源级网络配置变化，但不属于本层抽象」的子系统订阅——
  /// 目前是 `BangumiEchProxy`：三套 ECH 作用域里的**应用级**取自 [config]、
  /// **源级**取自各源的 `network.ech`，配置一变就必须把新作用域下发给原生引擎，
  /// 否则用户改了 ECH 开关要等下次冷启动才生效。
  ///
  /// 用回调而不是让本层直接引用具体实现：既避免 network 层反向依赖业务实现，
  /// 也避免 `network_config_service` ↔ `bangumi_ech_proxy` 互相 import。
  final List<void Function()> _effectiveConfigListeners = <void Function()>[];

  /// 注册有效档案变更回调（本层不去重，幂等由调用方保证）。
  void addEffectiveConfigListener(void Function() listener) {
    _effectiveConfigListeners.add(listener);
  }

  void _notifyEffectiveConfigListeners() {
    for (final listener in _effectiveConfigListeners) {
      try {
        listener();
      } on Object catch (e) {
        // 单个订阅者异常不得影响其余订阅者：配置本身已经落盘。
        debugPrint('NetworkConfigService listener failed: $e');
      }
    }
  }

  /// 计算某源的有效档案：source==null → 全局；否则逐方面合并覆盖。
  EffectiveNetworkProfile effectiveFor(PluginConfig? source) {
    if (source == null) return globalProfile;
    final userOverride = SourceNetworkOverrideStore.instance.get(source.id);
    final fileOverride = source.network;
    final merged = _mergeOverrides(userOverride, fileOverride);
    if (merged == null || merged.isEmpty) return globalProfile;
    return EffectiveNetworkProfile.fromConfig(_config, override: merged);
  }

  /// 逐方面合并两个覆盖：用户覆盖某方面非 null 则优先，否则用源文件方面。
  SourceNetworkConfig? _mergeOverrides(
    SourceNetworkConfig? user,
    SourceNetworkConfig? file,
  ) {
    if (user == null) return file;
    if (file == null) return user;
    return SourceNetworkConfig(
      proxy: user.proxy ?? file.proxy,
      dns: user.dns ?? file.dns,
      hosts: user.hosts ?? file.hosts,
      sni: user.sni ?? file.sni,
      ech: user.ech ?? file.ech,
    );
  }

  // ---- 测试方法（供 UI 探测） ----

  /// 测试代理连通性：经给定配置构建的 client 请求探测 URL。
  /// 返回 (成功, 延迟ms)。
  Future<(bool, int)> testProxy(
    NetworkConfig config, {
    String? password,
    String probeUrl = 'https://www.gstatic.com/generate_204',
  }) async {
    final profile = EffectiveNetworkProfile.fromConfig(config);
    final client = NetworkClientBuilder.buildHttpClient(
      profile,
      proxyPassword: password ?? _proxyPassword,
    );
    final sw = Stopwatch()..start();
    try {
      final req = await client
          .getUrl(Uri.parse(probeUrl))
          .timeout(const Duration(seconds: 10));
      final resp = await req.close().timeout(const Duration(seconds: 10));
      await resp.drain<void>();
      sw.stop();
      final ok = resp.statusCode >= 200 && resp.statusCode < 400;
      return (ok, sw.elapsedMilliseconds);
    } on Object catch (e) {
      debugPrint('NetworkConfigService.testProxy failed: $e');
      sw.stop();
      return (false, sw.elapsedMilliseconds);
    } finally {
      client.close(force: true);
    }
  }

  /// 测试 DNS 解析：返回 (解析到的 IP 列表, 耗时ms)。
  Future<(List<String>, int)> testDns(
    String host,
    DnsConfig cfg,
    List<HostsEntry> hosts,
  ) async {
    final sw = Stopwatch()..start();
    try {
      final addrs = await DnsResolver.instance.resolve(host, cfg, hosts);
      sw.stop();
      return (addrs.map((a) => a.address).toList(), sw.elapsedMilliseconds);
    } on Object catch (e) {
      debugPrint('NetworkConfigService.testDns failed: $e');
      sw.stop();
      return (<String>[], sw.elapsedMilliseconds);
    }
  }

  /// 测试 DoH 端点：对样例域名经 DoH 解析。返回 (成功, 延迟ms)。
  Future<(bool, int)> testDoh(
    String dohUrl, {
    String sampleHost = 'www.cloudflare.com',
  }) async {
    final cfg = DnsConfig(
      mode: DnsMode.doh,
      dohUrl: dohUrl,
      cacheEnabled: false,
    );
    final (ips, ms) = await testDns(sampleHost, cfg, const <HostsEntry>[]);
    return (ips.isNotEmpty, ms);
  }

  /// 测试 SNI 握手：按档案 DNS/Hosts 定向 TCP，并按 [SniPolicy] 完成真实 TLS
  /// 握手（覆盖 / 免 SNI / 正常三种形态与运行时一致）。
  /// [override] 为源级覆盖（与 [effectiveFor] 同一合并语义）。
  /// 返回 (成功, 延迟ms, 实际使用的 TLS 名；免 SNI 为 `-`)。
  Future<(bool, int, String)> testSni(
    String host,
    NetworkConfig config, {
    SourceNetworkConfig? override,
  }) async {
    final profile = EffectiveNetworkProfile.fromConfig(
      config,
      override: override,
    );
    final sni = SniPolicy.resolve(profile.sni, host);
    String tlsName = sni ?? host;
    final sw = Stopwatch()..start();
    try {
      final addresses =
          await DnsResolver.instance.resolve(host, profile.dns, profile.hosts);
      if (addresses.isEmpty) {
        return (false, sw.elapsedMilliseconds, tlsName);
      }
      final socket = await Socket.connect(
        addresses.first,
        443,
        timeout: const Duration(seconds: 8),
      );
      try {
        tlsName = switch (sni) {
          null => host,
          '' => socket.remoteAddress.host,
          _ => sni,
        };
        await SecureSocket.secure(
          socket,
          host: tlsName,
          onBadCertificate: (_) => true,
        );
        sw.stop();
        return (
          true,
          sw.elapsedMilliseconds,
          sni == '' ? SniPolicy.noSniToken : tlsName,
        );
      } finally {
        socket.destroy();
      }
    } on Object catch (e) {
      debugPrint('NetworkConfigService.testSni($host) failed: $e');
      sw.stop();
      return (false, sw.elapsedMilliseconds, tlsName);
    }
  }
}
