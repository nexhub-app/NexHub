/// Bangumi 账户与收藏浏览设置页。
///
/// - 账户登录：个人 Access Token 输入与验证（token 存 secure storage）、
/// 登录状态展示与登出；
/// - 浏览 Bangumi 收藏：登录后按五状态（想看 / 在看 / 看过 / 搁置 / 抛弃）
/// 筛选查看远端收藏条目信息（[BangumiCollectionBrowser]）。
/// 单条同步与绑定 / 评分入口下沉到详情页 Bangumi 卡片与书架长按菜单。
library;

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/bangumi/bangumi_auth.dart';
import '../../../core/services/bangumi/bangumi_ech_proxy.dart';
import '../../../core/services/bangumi/bangumi_oauth_config.dart';
import '../../../core/services/bangumi/bangumi_proxy_config.dart';
import '../../../core/theme/app_tokens.dart';
import 'widgets/settings_widgets.dart';
import '../../../core/widgets/bangumi_collection_browser.dart';
import '../../../core/widgets/app_glass_bar.dart';

class SettingsBangumiScreen extends StatefulWidget {
  const SettingsBangumiScreen({super.key});

  @override
  State<SettingsBangumiScreen> createState() => _SettingsBangumiScreenState();
}

class _SettingsBangumiScreenState extends State<SettingsBangumiScreen> {
  final TextEditingController _tokenController = TextEditingController();
  bool _verifying = false;
  bool _oauthing = false;

  // ── 代理 / 镜像配置 ──
  final TextEditingController _mainSiteController = TextEditingController();
  final TextEditingController _apiController = TextEditingController();
  final TextEditingController _imageController = TextEditingController();
  BangumiProxyMode _proxyMode = BangumiProxyMode.direct;

  /// 展示用连接模式：本平台无 ECH 引擎（iOS / Web）时，历史 ECH 选择
  /// 回落为直连——设置项已隐藏，避免 SegmentedButton 选中值不在候选中触发断言。
  BangumiProxyMode get _effectiveProxyMode =>
      (!BangumiEchProxy.platformSupported && _proxyMode == BangumiProxyMode.ech)
          ? BangumiProxyMode.direct
          : _proxyMode;

  @override
  void initState() {
    super.initState();
    final cfg = BangumiProxyConfig.instance;
    _proxyMode = cfg.mode;
    _mainSiteController.text = cfg.mainSite;
    _apiController.text = cfg.api;
    _imageController.text = cfg.image;
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _mainSiteController.dispose();
    _apiController.dispose();
    _imageController.dispose();
    super.dispose();
  }

  /// 保存代理 / 镜像设置到本地存储并同步全局实例。
  ///
  /// 仅镜像模式的域名输入框走这里；连接模式本身由 [_switchProxyMode] 即时生效。
  Future<void> _saveProxy(AppLocalizations l10n) async {
    await _persistConfig(_proxyMode);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.bangumiProxySaved)),
    );
  }

  Future<void> _persistConfig(BangumiProxyMode mode) {
    return BangumiProxyConfig(
      mode: mode,
      mainSite: _mainSiteController.text.trim(),
      api: _apiController.text.trim(),
      image: _imageController.text.trim(),
    ).save();
  }

  /// 切换连接模式：直连 / 镜像 / ECH 三选一（对齐参考项目 `setProxyMode`）。
  ///
  /// 与镜像域名不同，模式本身**即时生效并持久化**：
  /// - 切到 ECH：先持久化模式，再走 [BangumiEchProxy.applyEchScope] 按三套并集
  ///   重算（启动引擎或热更新作用域）。引擎没能跑起来（平台未打包原生引擎 /
  ///   启动失败）则回退到原模式并提示——避免「显示 ECH 实际直连」的割裂状态；
  /// - 离开 ECH：同样重算并集——应用级 / 源级 ECH 还开着时引擎继续跑，
  ///   三套全关则由 applyEchScope 停掉引擎。
  Future<void> _switchProxyMode(BangumiProxyMode mode) async {
    if (mode == _proxyMode) return;
    final l10n = AppLocalizations.of(context);
    final previous = _proxyMode;
    setState(() => _proxyMode = mode);
    await _persistConfig(mode);

    if (mode == BangumiProxyMode.ech || previous == BangumiProxyMode.ech) {
      await BangumiEchProxy.instance.applyEchScope();
    }

    if (mode == BangumiProxyMode.ech &&
        !BangumiEchProxy.instance.isEchProxyRunning() &&
        mounted) {
      // 启动失败 → 回退原模式（重算作用域，清掉刚才并进去的 bangumi 域）。
      setState(() => _proxyMode = previous);
      await _persistConfig(previous);
      await BangumiEchProxy.instance.applyEchScope();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.bangumiEchUnavailable)),
      );
      return;
    }

    // 刷新 ECH 状态行（运行中（端口 x）/ 未运行）。
    if (mounted) setState(() {});
  }

  Future<void> _verifyToken(AppLocalizations l10n) async {
    final auth = context.read<BangumiAuth>();
    final token = _tokenController.text.trim();
    if (token.isEmpty) return;
    setState(() => _verifying = true);
    try {
      await auth.saveToken(token);
      _tokenController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.bangumiTokenSaved)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.bangumiTokenInvalid)),
      );
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  /// OAuth 2.0 授权码登录：打开浏览器 → 深链回调 → 保存 token。
  Future<void> _loginWithOAuth(AppLocalizations l10n) async {
    setState(() => _oauthing = true);
    try {
      final auth = context.read<BangumiAuth>();
      await auth.loginWithOAuth(context);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.loginSuccess)),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      final msg = e.message == 'bangumi oauth not configured'
          ? l10n.bangumiOauthNotConfigured
          : l10n.bangumiOauthFailed;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.bangumiOauthFailed)),
      );
    } finally {
      if (mounted) setState(() => _oauthing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // 订阅 BangumiAuth 直接响应 login/logout（之前订阅 SyncService 取 auth
    // 字段是不会重建的，导致 logout 后 UI 不刷新）。SyncService 仅在「同步中」
    // 状态需要，用 read 拿即可。
    final auth = context.watch<BangumiAuth>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.bangumiSettings)),
      body: ListView(
        padding: context.pageInset(AppTokens.spaceLg),
        children: <Widget>[
          // ───── 账号区 ─────
          Text(l10n.bangumiAccount, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppTokens.spaceMd),
          if (auth.isLoggedIn) ...<Widget>[
            SettingsTile(
              icon: Icons.account_circle_rounded,
              title: l10n.bangumiLoggedInAs(auth.displayName ?? ''),
              subtitle: (auth.username != null && auth.username!.isNotEmpty)
                  ? '@${auth.username}'
                  : null,
              trailing: TextButton(
                onPressed: () => auth.logout(),
                child: Text(l10n.logoutAction),
              ),
            ),
          ] else ...<Widget>[
            // 会话因鉴权失败被清空（refresh_token 失效 / 个人 token 被拒）时
            // 明确提示重新授权，避免用户以为是网络问题反复重试。
            if (auth.sessionExpired) ...<Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.error_outline_rounded,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: AppTokens.spaceXs),
                  Expanded(
                    child: Text(
                      l10n.loginExpired,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.spaceSm),
            ],
            // 诊断明细（令牌指纹 / 命中域名）：与官网令牌管理页对照用，
            // 属技术信息，保留原文不翻译。
            if (auth.lastAuthError != null && auth.lastAuthError!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
                child: Text(
                  auth.lastAuthError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            // ── OAuth 2.0 授权登录（推荐）──
            FilledButton.icon(
              onPressed: _oauthing ? null : () => _loginWithOAuth(l10n),
              icon: _oauthing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login_rounded),
              label: Text(l10n.bangumiLoginWithOAuth),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              BangumiOAuthConfig.configured
                  ? l10n.bangumiOauthHint
                  : l10n.bangumiOauthNotConfigured,
              style: theme.textTheme.bodySmall?.copyWith(
                color: BangumiOAuthConfig.configured
                    ? null
                    : theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: AppTokens.spaceLg),
            const Divider(),
            const SizedBox(height: AppTokens.spaceMd),
            TextField(
              controller: _tokenController,
              decoration: InputDecoration(
                labelText: l10n.bangumiTokenHint,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.key_rounded),
              ),
              obscureText: true,
            ),
            const SizedBox(height: AppTokens.spaceMd),
            FilledButton.icon(
              onPressed: _verifying ? null : () => _verifyToken(l10n),
              icon: _verifying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_user_rounded),
              label: Text(l10n.bangumiTokenVerify),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            TextButton.icon(
              onPressed: () => launchUrl(
                Uri.parse('https://next.bgm.tv/demo/access-token'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: Text(l10n.bangumiGetToken),
            ),
          ],
          // ───── 代理 / 镜像设置 ─────
          const SizedBox(height: AppTokens.spaceXl),
          const Divider(),
          const SizedBox(height: AppTokens.spaceMd),
          Text(l10n.bangumiProxyTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppTokens.spaceMd),
          // ── 连接模式：直连 / 镜像 / ECH 三选一（对齐参考项目 ProxyMode）──
          // 无原生 ECH 引擎的平台（iOS / Web）隐藏 ECH 选项，历史选择回落直连。
          SegmentedButton<BangumiProxyMode>(
            segments: <ButtonSegment<BangumiProxyMode>>[
              ButtonSegment<BangumiProxyMode>(
                value: BangumiProxyMode.direct,
                label: Text(l10n.bangumiProxyDirect),
                icon: const Icon(Icons.lan_rounded),
              ),
              ButtonSegment<BangumiProxyMode>(
                value: BangumiProxyMode.mirror,
                label: Text(l10n.bangumiProxyMirror),
                icon: const Icon(Icons.dns_rounded),
              ),
              if (BangumiEchProxy.platformSupported)
                ButtonSegment<BangumiProxyMode>(
                  value: BangumiProxyMode.ech,
                  label: Text(l10n.bangumiProxyEch),
                  icon: const Icon(Icons.enhanced_encryption_rounded),
                ),
            ],
            selected: <BangumiProxyMode>{_effectiveProxyMode},
            onSelectionChanged: (s) => _switchProxyMode(s.first),
          ),
          if (_proxyMode == BangumiProxyMode.mirror) ...<Widget>[
            const SizedBox(height: AppTokens.spaceMd),
            Text(l10n.bangumiProxyHint, style: theme.textTheme.bodySmall),
            const SizedBox(height: AppTokens.spaceMd),
            TextField(
              controller: _mainSiteController,
              decoration: InputDecoration(
                labelText: l10n.bangumiProxyMainSite,
                hintText: 'next.bgm.tv',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.home_rounded),
              ),
            ),
            const SizedBox(height: AppTokens.spaceMd),
            TextField(
              controller: _apiController,
              decoration: InputDecoration(
                labelText: l10n.bangumiProxyApi,
                hintText: 'api.bgm.tv',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.cloud_rounded),
              ),
            ),
            const SizedBox(height: AppTokens.spaceMd),
            TextField(
              controller: _imageController,
              decoration: InputDecoration(
                labelText: l10n.bangumiProxyImage,
                hintText: 'lain.bgm.tv',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.image_rounded),
              ),
            ),
            const SizedBox(height: AppTokens.spaceMd),
            FilledButton.icon(
              onPressed: () => _saveProxy(l10n),
              icon: const Icon(Icons.save_rounded),
              label: Text(l10n.save),
            ),
          ],
          if (_effectiveProxyMode == BangumiProxyMode.ech) ...<Widget>[
            const SizedBox(height: AppTokens.spaceMd),
            Text(l10n.bangumiEchProxyHint, style: theme.textTheme.bodySmall),
            const SizedBox(height: AppTokens.spaceSm),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                BangumiEchProxy.instance.isEchProxyRunning()
                    ? Icons.check_circle_rounded
                    : Icons.error_outline_rounded,
                color: BangumiEchProxy.instance.isEchProxyRunning()
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
              ),
              title: Text(l10n.bangumiEchStatus),
              subtitle: Text(
                BangumiEchProxy.instance.isEchProxyRunning()
                    ? l10n.bangumiEchProxyRunning(
                        BangumiEchProxy.instance.getEchProxyPort())
                    : l10n.bangumiEchProxyIdle,
              ),
            ),
          ],
          // ───── 浏览 Bangumi 收藏（登录后可用）─────
          if (auth.isLoggedIn) ...<Widget>[
            const SizedBox(height: AppTokens.spaceXl),
            const Divider(),
            const SizedBox(height: AppTokens.spaceMd),
            Text(l10n.bangumiBrowseCollection,
                style: theme.textTheme.titleMedium),
            const SizedBox(height: AppTokens.spaceMd),
            const BangumiCollectionBrowser(),
          ],
        ],
      ),
    );
  }
}
