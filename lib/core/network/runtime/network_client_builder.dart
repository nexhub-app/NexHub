/// 网络客户端构建器：把「有效档案 → 配置好的 HttpClient」的映射集中到一处。
///
/// 同时被全局 [NexHubHttpOverrides] 与 [HttpFetcher] 的多档案 Dio 复用，
/// 消除代理三模式 / connectionFactory / badCertificateCallback 的重复。
library;

import 'dart:async';
import 'dart:io';

import '../model/effective_network_profile.dart';
import '../model/network_config.dart';
import 'dns_resolver.dart';
import 'host_order_relay.dart';
import 'sni_policy.dart';
import 'system_proxy_resolver.dart';

/// 代理覆盖策略：返回非 null 时接管该 [Uri] 的代理决策，返回 null 则回落到
/// 档案自身的代理配置。见 [NetworkClientBuilder.proxyOverrideResolver]。
typedef ProxyOverrideResolver = String? Function(Uri uri);

/// 从 [EffectiveNetworkProfile] 构建 [HttpClient] 的单一入口。
class NetworkClientBuilder {
  const NetworkClientBuilder._();

  /// 代理路由扩展点：可插拔的「代理覆盖策略」。
  ///
  /// 返回非 null 即接管本次请求的代理决策（如 Bangumi ECH 本地代理）；
  /// 返回 null 表示不接管，回落到档案自身的代理配置。
  ///
  /// 实现者**必须**只对自己负责的目标域名返回非 null：对无关域名返回
  /// `'DIRECT'` 会吞掉用户配置的代理，属明确错误用法。同一时刻只应有一个
  /// 实现（当前由 BangumiEchProxy 在首次访问单例时注册）。
  ///
  /// 对应参考项目 Bangumi-master `utils/proxy/strategy.ts` 把
  /// `ech = isEchProxyRunning()` 组合进代理策略的做法。
  static ProxyOverrideResolver? proxyOverrideResolver;

  /// 构建配置好的 [HttpClient]。
  ///
  /// [proxyPassword] 为手动代理的密码（不入档案/JSON，由调用方从安全存储取），
  /// 仅在 manual 模式且有用户名时用于 `addProxyCredentials`。
  static HttpClient buildHttpClient(
    EffectiveNetworkProfile profile, {
    SecurityContext? ctx,
    String? proxyPassword,
  }) {
    final client = _rawHttpClient(ctx);
    // 保留原 HttpFetcher 的自签容忍（部分源使用非标准 SSL 配置）。
    client.badCertificateCallback = (cert, host, port) => true;

    _applyProxy(client, profile.proxy, proxyPassword,
        override: proxyOverrideResolver);

    if (profile.needsCustomConnection) {
      _applyCustomConnection(client, profile, ctx: ctx);
    }

    return client;
  }

  /// 把档案的代理配置解析为 `findProxy` 决策函数（纯函数，可单测）。
  ///
  /// 与 [buildHttpClient] 分离，是因为 `HttpClient.findProxy` 是
  /// setter-only、无法读回断言；把决策做成纯函数后，代理语义可直接被测试。
  static String Function(Uri) resolveProfileProxy(ProxyConfig proxy) {
    switch (proxy.mode) {
      case ProxyMode.direct:
        return (_) => 'DIRECT';
      case ProxyMode.system:
        // 桌面基于环境变量（尽力而为），并叠加 Windows 系统代理（注册表
        // ProxyEnable/ProxyServer，多数代理软件只写注册表不设环境变量）。
        return (uri) {
          final env = HttpClient.findProxyFromEnvironment(uri);
          if (env != 'DIRECT' && env.isNotEmpty) return env;
          final sys = SystemProxyResolver.rule;
          return sys.isEmpty ? 'DIRECT' : sys;
        };
      case ProxyMode.manual:
        if (proxy.host.isNotEmpty && proxy.port > 0) {
          final scheme =
              proxy.protocol == ProxyProtocol.socks5 ? 'SOCKS' : 'PROXY';
          final target = '$scheme ${proxy.host}:${proxy.port}';
          return (_) => target;
        }
        return (_) => 'DIRECT';
    }
  }

  /// 组合「覆盖策略 + 档案决策」为最终的 `findProxy` 决策函数（纯函数，可单测）。
  ///
  /// 覆盖策略优先，返回 null 时回落到档案决策——这是「覆盖策略绝不吞掉用户
  /// 代理配置」这一硬契约的可测试落点。
  static String Function(Uri) composeProxyResolver(
    ProxyConfig proxy, {
    ProxyOverrideResolver? override,
  }) {
    final base = resolveProfileProxy(proxy);
    if (override == null) return base;
    return (uri) => override(uri) ?? base(uri);
  }

  static void _applyProxy(
    HttpClient client,
    ProxyConfig proxy,
    String? proxyPassword, {
    ProxyOverrideResolver? override,
  }) {
    client.findProxy = composeProxyResolver(proxy, override: override);

    if (proxy.mode == ProxyMode.manual &&
        proxy.host.isNotEmpty &&
        proxy.port > 0 &&
        proxy.protocol == ProxyProtocol.http &&
        proxy.username.isNotEmpty) {
      client.addProxyCredentials(
        proxy.host,
        proxy.port,
        '',
        HttpClientBasicCredentials(
          proxy.username,
          proxyPassword ?? '',
        ),
      );
    }
  }

  /// 创建一个「绕过全局 [HttpOverrides]」的裸 [HttpClient]。
  ///
  /// 关键：本构建器同时是 [NexHubHttpOverrides] 的委托目标。若这里直接用
  /// `HttpClient()` 工厂，会再次命中 `HttpOverrides.global` → 回到本方法 →
  /// 无限递归 → `StackOverflowError`，导致全应用所有请求失败。故在无覆盖的
  /// zone 内创建真实客户端，彻底断开自引用。
  static HttpClient _rawHttpClient(SecurityContext? ctx) {
    return HttpOverrides.runWithHttpOverrides<HttpClient>(
      () => HttpClient(context: ctx),
      _RawHttpOverrides(),
    );
  }

  /// 自定义连接工厂：DNS/Hosts 定向 + 直连 HTTPS 的 TLS 接管。
  ///
  /// 关键契约（见 SDK `_ConnectionTarget.connect`）：connectionFactory 返回的
  /// socket 会被 HttpClient 原样使用——**https 直连时客户端不会再补做 TLS**，
  /// 工厂必须自行完成握手并返回已加密的 [SecureSocket]（此前返回裸 socket 会
  /// 把明文 HTTP 打到 443 端口）。
  ///
  /// TLS 在裸 socket 上以 [SniPolicy] 解析出的名字完成：
  /// - 不覆盖：SNI = 请求域名（与默认路径一致）；
  /// - 自定义：SNI = 配置域名（证书失配由 onBadCertificate 容忍）；
  /// - `-` 免 SNI：host 传 IP 字面量，引擎不发送 server_name 扩展。
  ///
  /// 走外部代理（proxyHost != null）时由 HttpClient 自己做 CONNECT 隧道 + TLS
  /// （SNI=目标域名），本工厂只负责把 TCP 连到（可能被 hosts/DNS 覆盖的）代理
  /// 地址，SNI 覆盖在该路径不可用。
  static void _applyCustomConnection(
    HttpClient client,
    EffectiveNetworkProfile profile, {
    SecurityContext? ctx,
  }) {
    client.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) {
      // 有代理时 connectionFactory 收到的是代理主机；否则为目标主机。
      final targetHost = proxyHost ?? uri.host;
      // uri.port 在未显式给端口时为 0，须按 scheme 回落默认端口；
      // 显式端口必须原样保留（否则带端口的源地址会连到 443/80 上）。
      final defaultPort = uri.scheme == 'https' ? 443 : 80;
      final targetPort =
          proxyPort ?? (uri.port != 0 ? uri.port : defaultPort);
      final tlsDirect = proxyHost == null && uri.scheme == 'https';
      final sniOverride =
          tlsDirect ? SniPolicy.resolve(profile.sni, uri.host) : null;

      // DNS/Hosts 定向 TCP：解析结果为空时回退原域名交给系统解析。
      Future<ConnectionTask<Socket>> tcpTask() => DnsResolver.instance
          .resolve(targetHost, profile.dns, profile.hosts)
          .then((addresses) => addresses.isEmpty
              ? Socket.startConnect(targetHost, targetPort)
              : _connectFirstReachable(targetHost, targetPort, addresses));

      if (!tlsDirect) return tcpTask();

      // https 直连：工厂必须交回已握手的 SecureSocket（见方法注释的契约）。
      //
      // 通道形态：经 [HostOrderRelay] 中转——HttpClient 把明文 HTTP/1.1 报文
      // 写给桥，桥把请求头重写为浏览器线形态（`Host` 大写名 + 请求行后第一
      // 位；头名 Title-Case）后再拨号真目标。SDK 头存储为 HashMap（头名强制
      // 小写、顺序由哈希定），应用层无法控制；部分 Cloudflare 站点对该形态做
      // 指纹检测（小写/非首位的 host → 403）。参考 OkHttp 系客户端（天然
      // Host 首位 + Title-Case）从不触发该指纹。桥不做域名特判：Host 首位
      // 是 RFC 9112 规范形态，对普通站点无副作用。
      final host = uri.host;
      Future<Socket> dialTarget(String relayHost, int relayPort) async {
        final task = await tcpTask();
        final raw = await task.socket;
        // Dart 的 SecureSocket.secure(host:) 同时决定 SNI 与证书校验名；
        // host 传 IP 字面量时引擎不发送 SNI 扩展（免 SNI 模式的实现基础）。
        final tlsName = switch (sniOverride) {
          null => host,
          '' => raw.remoteAddress.host,
          _ => sniOverride,
        };
        return SecureSocket.secure(
          raw,
          host: tlsName,
          context: ctx,
          // 与 client.badCertificateCallback=true 对齐：容忍自签，以及
          // 自定义 SNI 与证书名的必然失配。
          onBadCertificate: (_) => true,
        );
      }

      // 桥自身不可用（bind/连接失败等）时退回旧直连路径，不放大故障面。
      Future<ConnectionTask<Socket>> connectViaRelay() async {
        try {
          return await HostOrderRelay.instance.attach(dialTarget);
        } on Object {
          final socketFuture = dialTarget(host, targetPort);
          return ConnectionTask.fromSocket(socketFuture, () {
            // 拨号完成前取消：完成后销毁，防泄漏。
            unawaited(socketFuture.then<void>((s) => s.destroy(),
                onError: (Object _) {}));
          });
        }
      }

      return connectViaRelay();
    };
  }

  /// 从解析结果中逐个尝试连接，直到成功；全部失败则回退系统解析原域名直连。
  ///
  /// 修复「浏览器能开、应用超时」：DNS 常返回多个 IP（CDN / 多线机房），
  /// 其中部分地址不可达（被投毒 / 机房屏蔽 / 仅某个 IP 可达）。此前只连
  /// `addresses.first`，第一个不可达就整体连接超时；这里按顺序逐个尝试，
  /// 任意一个成功即建连成功（与浏览器的多 IP 回退行为一致）。
  static Future<ConnectionTask<Socket>> _connectFirstReachable(
    String host,
    int port,
    List<InternetAddress> addresses,
  ) async {
    Object? lastErr;
    for (final addr in addresses) {
      try {
        final task = await Socket.startConnect(addr, port);
        // 等待本次连接结果：成功即返回（调用方后续 await socket 已完成）；
        // 失败则记录并尝试下一个地址。
        await task.socket;
        return task;
      } on Object catch (e) {
        lastErr = e;
      }
    }
    // 全部候选失败：回退系统解析原域名直连（行为同旧路径，尽量不丢）。
    try {
      return await Socket.startConnect(host, port);
    } on Object catch (e) {
      // 兜底失败：抛出原始（更可读）的连接错误。
      throw lastErr ?? e;
    }
  }
}

/// 空覆盖：`createHttpClient` 沿用基类实现（直接创建真实客户端），
/// 供 [NetworkClientBuilder._rawHttpClient] 在 zone 内临时替换全局覆盖，避免递归。
class _RawHttpOverrides extends HttpOverrides {}
