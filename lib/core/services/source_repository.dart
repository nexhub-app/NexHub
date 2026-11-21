import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/plugin_config.dart';
import 'config_loader.dart';
import '../../features/shuyuan/shuyuan_adapter.dart';
import '../../features/shuyuan/shuyuan_source_service.dart';
import '../../features/shuyuan/analyze/js_engine.dart';
import '../../features/shuyuan/analyze/source_context.dart';

/// 已加载的源仓库（内存级，持久化到 SharedPreferences）。
///
/// 负责：
/// - 按类型过滤
/// - 向上层提供 activeSources / getById
/// - 作为单一真源被 MediaApiService / 各模块浏览页消费
///
/// 应用同时运行「内置源」（打包资源 assets/plugins/builtin）与「用户导入的源」。
/// 内置源在启动时由 [loadBuiltins] 从资源包加载，用户导入/编辑/屏蔽状态持久化，
/// 二者按 id 合并（用户导入的版本优先，可覆盖同名内置源）。
///
/// 继承 [ChangeNotifier]：启用/禁用/隐藏等状态变更后通知 UI 刷新。
class SourceRepository extends ChangeNotifier {
  final List<PluginConfig> _imported;

  /// 内置源（启动时由 [loadBuiltins] 从资源包加载）。
  final List<PluginConfig> _configs = <PluginConfig>[];

  /// 被用户屏蔽（删除/隐藏）的内置源 id 集合（持久化）。
  final Set<String> _suppressedBuiltins = <String>{};

  /// 内置源资源文件名清单（assets/plugins/builtin/<name>.json）。
  /// 缺失的文件在 [loadBuiltins] 中静默跳过，补回文件后下次启动自动加载。
  static const List<String> _builtinAssetNames = <String>[
    'manga_baozimh',
    'manga_goda',
    'pms_dalvdm',
    'pms_girigirilove',
    'pms_m233',
    'novel_yamibo',
    'novel_biquge',
    'novel_linovelib',
    'novel_huanmengacg',
    // 注：曾预留演示用多线路源 demo_multi_line（3 条 HLS 测试流），
    // 但 assets 从未入库，只会触发"跳过（缺失或解析失败）"日志，故移除引用。
  ];

  static const String _builtinOverrideKey = 'source_builtin_overrides_v1';

  /// 可选初始源列表（测试注入用）。
  SourceRepository([List<PluginConfig> initial = const <PluginConfig>[]])
      : _imported = List<PluginConfig>.from(initial) {
    // 无痕判定反查钩子：ConfigLoader 按 sourceId 回退读取源配置自带的
    // stealthMode（HistoryManager 等无 PluginConfig 的场景与之口径一致）。
    ConfigLoader.instance.configResolver = getById;
  }

  /// 测试注入内置源（避免测试依赖资源包与书源解析器）。
  @visibleForTesting
  void seedBuiltinsForTest(List<PluginConfig> builtins) {
    _configs
      ..clear()
      ..addAll(builtins);
  }

  /// 全部源 = 未屏蔽的内置源（套用状态覆盖）+ 用户导入源（同名优先）。
  ///
  /// **内置源自动升级**：同名内置源 version 高于用户导入/编辑的副本时，
  /// 以内置新版为准（导入副本视为过期，不参与展示）。这样 App 内置源发新版
  /// （改 JSON + 提 version）后，用户无需手动删源重导即可生效；用户手动
  /// 导入的更新版本（version ≥ 内置）仍优先，尊重用户自定义。
  List<PluginConfig> get all {
    // 预计算过期的导入副本：内置 version > 导入 version 的 id 集合。
    final staleImports = <String>{};
    for (final c in _imported) {
      for (final b in _configs) {
        if (b.id == c.id && b.version > c.version) {
          staleImports.add(c.id);
          break;
        }
      }
    }
    final map = <String, PluginConfig>{};
    for (final c in _configs) {
      // 被屏蔽的内置（用户曾编辑/导入过）：内置新版时解除屏蔽恢复展示。
      if (_suppressedBuiltins.contains(c.id) && !staleImports.contains(c.id)) {
        continue;
      }
      var cfg = c;
      final ov = _stateOverrides[c.id];
      if (ov != null) {
        cfg = cfg.copyWith(
          enabled: ov['enabled'] as bool?,
          isHidden: ov['isHidden'] as bool?,
        );
      }
      map[c.id] = cfg;
    }
    // 用户导入/编辑过的版本覆盖同名内置源（内置新版胜出的过期副本除外）。
    for (final c in _imported) {
      if (staleImports.contains(c.id)) continue;
      map[c.id] = c;
    }
    return List<PluginConfig>.unmodifiable(_applyOrder(map.values.toList()));
  }

  /// 应用「自定义排序」：按 [_customOrder] 顺序，未记录的源按原始顺序追加在末尾。
  List<PluginConfig> _applyOrder(List<PluginConfig> list) {
    if (_customOrder.isEmpty) return list;
    final byId = <String, PluginConfig>{for (final c in list) c.id: c};
    final ordered = <PluginConfig>[];
    for (final id in _customOrder) {
      final c = byId[id];
      if (c != null) ordered.add(c);
    }
    for (final c in list) {
      if (!ordered.contains(c)) ordered.add(c);
    }
    return ordered;
  }

  /// 应用一次拖动排序结果（传入可见源的新 id 顺序）。
  Future<void> setSourceOrder(List<String> ids) async {
    _customOrder
      ..clear()
      ..addAll(ids);
    await _persistOrder();
    notifyListeners();
  }

  Future<void> _persistOrder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _orderKey,
      jsonEncode(<String, dynamic>{
        'order': _customOrder,
      }),
    );
  }

  List<PluginConfig> get importedSources =>
      List<PluginConfig>.unmodifiable(_imported);

  /// 年龄限制开关（true = 隐藏 [SourceAgeRating.mature] 源）。**默认开启**。
  ///
  /// 由 splash 从 `GeneralSettings.ageRestrictionEnabled` 注入、设置页切换时
  /// 调用 [setAgeRestrictionEnabled] 同步。此处不直接依赖设置单例，避免测试
  /// 环境触发 SharedPreferences 插件。
  bool _ageRestrictionEnabled = true;

  bool get ageRestrictionEnabled => _ageRestrictionEnabled;

  /// 更新年龄限制开关并广播（值未变化时空操作）。
  void setAgeRestrictionEnabled(bool value) {
    if (_ageRestrictionEnabled == value) return;
    _ageRestrictionEnabled = value;
    notifyListeners();
  }

  /// 该源当前是否因年龄限制被拦截。
  bool isAgeBlocked(PluginConfig config) =>
      _ageRestrictionEnabled && config.ageRating.isRestricted;

  /// 因年龄限制被隐藏的源（用于在源管理页提示数量）。
  List<PluginConfig> get ageBlockedSources =>
      all.where(isAgeBlocked).toList(growable: false);

  /// 活跃源（已启用 + 未弃用 + 未隐藏 + 未被年龄限制拦截）。
  List<PluginConfig> get activeSources => all
      .where((c) =>
          c.isEnabled && !c.isDeprecated && !c.isHidden && !isAgeBlocked(c))
      .toList();

  /// 按模块取活跃源。查询影视桶（animeSource）时一并返回视频/音频源
  /// （legado bookSourceType=4/1）——三者共用媒体播放管线与「媒体」栏。
  List<PluginConfig> byType(SourceType type) => activeSources
      .where((c) => c.type.mediaBucket == type.mediaBucket)
      .toList();

  PluginConfig? getById(String id) {
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// 批量解析混合源文本，返回可导入的 [PluginConfig] 列表（仅含校验通过者）。
  ///
  /// 支持输入形态：
  /// - 单个 PluginConfig（Map）
  /// - JSON 数组（PluginConfig 与通用书源格式可混排）
  /// - 单个通用书源格式对象（缺 `type` 字段）
  /// - 包装对象 `{"bookSources":[...]}` / `{"data":[...]}` 等
  /// - NDJSON（每行一个对象）
  /// - XML（书源 `<source>` / `<bookSource>`）
  ///
  /// 无法识别 / 转换 / 校验失败的源被**静默跳过，不整体抛异常**，
  /// 因此"一次导入小说 + 媒体 + 漫画"时个别坏源不会拖垮整批。
  static List<PluginConfig> parseMixedSources(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const <PluginConfig>[];
    final service = ShuyuanSourceService();
    try {
      return _parseMixedWithService(text, service);
    } finally {
      service.close();
    }
  }

  static List<PluginConfig> _parseMixedWithService(
    String text,
    ShuyuanSourceService service,
  ) {
    // 单对象（单个 PluginConfig 或单个书源）优先尝试
    final single = _tryParseOneWithService(text, service);
    if (single != null) return <PluginConfig>[single];

    final out = <PluginConfig>[];

    // JSON 数组（小说 + 媒体 + 漫画可混排）
    if (text.startsWith('[')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is List) {
          for (final e in decoded) {
            if (e is Map<String, dynamic>) {
              final c = _tryParseMapWithService(e, service);
              if (c != null) out.add(c);
            }
          }
        }
      } on Object {
        // 解析失败交给后续兜底
      }
    }

    // 包装对象：{"bookSources":[...]} / {"data":[...]} 等
    if (out.isEmpty && text.startsWith('{')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) {
          for (final key in const [
            'bookSources',
            'bookSource',
            'data',
            'sources',
            'items',
            'list',
          ]) {
            final arr = decoded[key];
            if (arr is List) {
              for (final e in arr) {
                if (e is Map<String, dynamic>) {
                  final c = _tryParseMapWithService(e, service);
                  if (c != null) out.add(c);
                }
              }
            }
          }
        }
      } on Object {
        // ignore
      }
    }

    // XML 书源
    if (out.isEmpty && text.startsWith('<')) {
      final list = service.parseSources(text);
      for (final s in list) {
        try {
          out.add(ShuyuanAdapter.toPluginConfig(s));
        } on Object {
          // skip
        }
      }
    }

    // NDJSON / 多对象拼接：按行尝试
    if (out.isEmpty) {
      for (final line in const LineSplitter().convert(text)) {
        final t = line.trim();
        if (t.isEmpty || !t.startsWith('{')) continue;
        final c = _tryParseOneWithService(t, service);
        if (c != null) out.add(c);
      }
    }

    return out;
  }

  /// 解析单个源文本（单 PluginConfig 或单书源）。失败返回 null。
  static PluginConfig? _tryParseOneWithService(
    String text,
    ShuyuanSourceService service,
  ) {
    final t = text.trim();
    if (t.isEmpty) return null;
    if (t.startsWith('<')) {
      final list = service.parseSources(t);
      if (list.isEmpty) return null;
      try {
        return ShuyuanAdapter.toPluginConfig(list.first);
      } on Object {
        return null;
      }
    }
    try {
      final json = jsonDecode(t) as Map<String, dynamic>;
      return _tryParseMapWithService(json, service);
    } on Object {
      return null;
    }
  }

  /// 解析单个对象：通用书源格式（缺 type）→ 转 PluginConfig；
  /// 否则按 PluginConfig 解析，校验失败返回 null。
  static PluginConfig? _tryParseMapWithService(
    Map<String, dynamic> json,
    ShuyuanSourceService service,
  ) {
    if (json['bookSourceName'] != null && !json.containsKey('type')) {
      try {
        final shuyuan = ShuyuanSource.fromJson(json);
        return ShuyuanAdapter.toPluginConfig(shuyuan);
      } on Object {
        return null;
      }
    }
    try {
      final config = PluginConfig.fromJson(json);
      return config.validate().isEmpty ? config : null;
    } on Object {
      return null;
    }
  }

  /// 测试注入用。
  factory SourceRepository.fromJsonList(List<Map<String, dynamic>> list) {
    return SourceRepository(list.map(PluginConfig.fromJson).toList());
  }

  static const String _importedKey = 'imported_sources_v1';
  static const String _stateOverridesKey = 'source_state_overrides_v1';
  static const String _orderKey = 'source_order_v1';

  /// 源状态覆盖（启用/隐藏），持久化到 SharedPreferences。
  /// key = sourceId, value = {enabled: bool, isHidden: bool}
  final Map<String, Map<String, dynamic>> _stateOverrides = {};

  /// 用户自定义的源排序（完整 id 顺序）。
  /// 仅记录出现在该列表里的 id；未记录的源按原始顺序追加在末尾。
  final List<String> _customOrder = <String>[];

  /// 添加用户导入的源。
  ///
  /// **版本覆盖规则**（与「源即插件」迭代工作流一致）：
  /// - 同名（id 相同）导入源按 `version` 决策：
  /// - 新版本 **≥** 已安装版本 → 替换（高版本升级 / 同版本重新导入以应用编辑）；
  /// - 新版本 **<** 已安装版本 → 跳过，**不覆盖**（防止误装旧版把新源冲掉）。
  /// 源作者发新版只需把 JSON 里的 `version` 调大，用户重新导入即自动升级。
  void addSource(PluginConfig config) {
    config = _withLegadoIdentity(config);
    // 重新导入一个「曾被屏蔽的内置源」时，取消屏蔽使其重新出现。
    if (_configs.any((c) => c.id == config.id) &&
        _suppressedBuiltins.contains(config.id)) {
      _unsuppressBuiltin(config.id);
    }
    final idx = _imported.indexWhere((c) => c.id == config.id);
    if (idx >= 0) {
      final existing = _imported[idx];
      if (config.version < existing.version) {
        debugPrint('[SourceRepository] skip import ${config.id}: '
            'v${config.version} < installed v${existing.version}');
        return; // 低版本不覆盖高版本
      }
      _imported[idx] = config; // 高版本或同版本 → 替换
      // 保留用户此前对该源设置的状态覆盖（启用/隐藏）。
      final override = _stateOverrides[config.id];
      if (override != null) {
        _applyOverride(
          config.id,
          enabled: override['enabled'] as bool?,
          isHidden: override['isHidden'] as bool?,
        );
      }
    } else {
      _imported.add(config);
    }
    _persistImported();
    notifyListeners();
  }

  /// 书源身份对齐 legado：`bookSourceUrl` 精确字符串即主键
  /// （BookSource @PrimaryKey + BookSourceDao REPLACE）。
  ///
  /// 旧 id 由 URL 归一化生成（去 scheme、非字母数字折叠、截断 60 字符），
  /// 仅尾斜杠/`#` 片段/非 ASCII 字符不同的源会撞成同一 id，被 [addSource]
  /// 按 id 覆盖而在在线列表中消失。入库时校正：
  /// - 同 URL 已入库 → 复用其 id（历史/进度中的 sourceId 引用不变）；
  /// - id 被另一个书源占用 → 确定性追加 URL 哈希后缀，重复导入收敛到同 id。
  PluginConfig _withLegadoIdentity(PluginConfig config) {
    final url = _shuyuanUrlOf(config);
    if (url == null) return config;

    for (final c in _imported) {
      if (c.id != config.id && _shuyuanUrlOf(c) == url) {
        return config.copyWith(id: c.id);
      }
    }
    for (final c in _configs) {
      if (c.id != config.id && _shuyuanUrlOf(c) == url) {
        return config.copyWith(id: c.id);
      }
    }

    final owner = _findByIdInRepo(config.id);
    if (owner == null) return config;
    final ownerUrl = _shuyuanUrlOf(owner);
    // 非书源占用或同一源：维持既有按 id 覆盖语义。
    if (ownerUrl == null || ownerUrl == url) return config;

    final suffixed = '${config.id}_${_shortUrlHash(url)}';
    final suffixedOwner = _findByIdInRepo(suffixed);
    if (suffixedOwner == null || _shuyuanUrlOf(suffixedOwner) == url) {
      return config.copyWith(id: suffixed);
    }
    return config.copyWith(id: '${config.id}_${_fullUrlHash(url)}');
  }

  PluginConfig? _findByIdInRepo(String id) {
    for (final c in _imported) {
      if (c.id == id) return c;
    }
    for (final c in _configs) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// 书源原始 `bookSourceUrl`（legado 身份键）；非书源返回 null。
  static String? _shuyuanUrlOf(PluginConfig config) {
    final xiaoshuo = config.selectors?['xiaoshuo'];
    if (xiaoshuo is! Map) return null;
    final url = xiaoshuo['bookSourceUrl'];
    return url is String && url.isNotEmpty ? url : null;
  }

  static String _shortUrlHash(String url) =>
      crypto.md5.convert(utf8.encode(url)).toString().substring(0, 8);

  static String _fullUrlHash(String url) =>
      crypto.md5.convert(utf8.encode(url)).toString();

  /// 用一份完整的新配置替换同名源（源编辑页保存入口）。
  ///
  /// 找不到同名 id 时直接追加（等同导入一个新源）。返回是否命中并替换了已有源。
  bool replaceSource(PluginConfig newConfig) {
    final idx = _imported.indexWhere((c) => c.id == newConfig.id);
    if (idx < 0) {
      _imported.add(newConfig);
    } else {
      _imported[idx] = newConfig;
    }
    // 编辑的是内置源 → 屏蔽原内置，使其被编辑后的版本取代（用户导入优先）。
    if (_configs.any((c) => c.id == newConfig.id)) {
      _suppressBuiltin(newConfig.id);
    }
    _persistImported();
    notifyListeners();
    return true;
  }

  /// Export user-imported sources as a JSON-serializable list.
  List<Map<String, dynamic>> exportToJson() =>
      _imported.map((c) => c.toJson()).toList();

  /// 更新源的 name/baseUrl 字段（兼容旧编辑入口）。
  ///
  /// 已导入源：直接更新 `_imported` 条目并持久化。
  bool updateSource(String id, {String? name, String? baseUrl}) {
    final idx = _imported.indexWhere((c) => c.id == id);
    if (idx < 0) {
      // 可能是内置源：提升为导入源（保留完整配置），并屏蔽原内置，使编辑生效。
      PluginConfig? builtin;
      for (final c in _configs) {
        if (c.id == id) {
          builtin = c;
          break;
        }
      }
      if (builtin != null) {
        final newSite = _newSite(builtin.site, baseUrl);
        final promoted = builtin.copyWith(
          name: name ?? builtin.name,
          site: newSite,
        );
        _imported.add(promoted);
        ConfigLoader.instance.retargetActiveMirrorIfDefault(
          builtin.id,
          builtin.site.baseUrl,
          newSite.baseUrl,
        );
        _suppressBuiltin(builtin.id);
        _persistImported();
        notifyListeners();
        return true;
      }
      return false;
    }
    final old = _imported[idx];
    final newSite = _newSite(old.site, baseUrl);
    _imported[idx] = old.copyWith(name: name ?? old.name, site: newSite);
    // 编辑主域名时，若当前激活镜像仍是旧主域名（用户未手动切到自定义镜像），
    // 则重定向到新主域名，使编辑立即生效；若已选自定义镜像则保持不变。
    ConfigLoader.instance
        .retargetActiveMirrorIfDefault(old.id, old.site.baseUrl, newSite.baseUrl);
    _persistImported();
    notifyListeners();
    return true;
  }

  /// 基于旧 [SiteConfig] 构造编辑后的站点配置，保留发布页/镜像等必要字段。
  SiteConfig _newSite(SiteConfig site, String? baseUrl) => SiteConfig(
        domain: site.domain,
        baseUrl: baseUrl ?? site.baseUrl,
        userAgent: site.userAgent,
        cookies: site.cookies,
        headers: site.headers,
        mirrors: site.mirrors,
        // 必须保留发布页配置，否则编辑后「从发布页提取镜像」失效
        publishPageUrl: site.publishPageUrl,
        publishMirrorSelector: site.publishMirrorSelector,
      );

  /// 删除源（删除确认入口）。返回是否实际删除了内容。
  bool removeSource(String id) {
    final had = _imported.any((c) => c.id == id);
    _imported.removeWhere((c) => c.id == id);
    // 释放该源的 JS 运行时（池化引擎）与持久化的登录态/变量：源已删除，
    // 不应继续占着原生 QuickJS 上下文或残留 cookie。
    JsEngine.evict(id);
    // fire-and-forget：删除是同步 API，持久化清理失败不影响主流程。
    ShuyuanSourceContext.forget(id);
    // 移除的是内置源（无论是否已提升为导入源）→ 屏蔽它，使其彻底消失。
    if (_configs.any((c) => c.id == id)) {
      _suppressBuiltin(id);
    }
    _stateOverrides.remove(id);
    _customOrder.remove(id);
    _persistImported();
    _persistStateOverrides();
    notifyListeners();
    return had;
  }

  /// Import sources from a parsed JSON list (merge, dedup by id via addSource).
  void importFromList(List<dynamic> items) {
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      addSource(PluginConfig.fromJson(item));
    }
  }

  /// 启动时从持久化层加载用户导入的源 + 状态覆盖。
  Future<void> loadImported() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_importedKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        var migrated = false;
        for (final e in list) {
          final configJson = e as Map<String, dynamic>;
          // 旧版适配器注入的默认 Referer 会随配置持久化，导致图片请求被
          // 签名 CDN 拒绝（封面全灰）。载入时清理并回写一次。
          if (ShuyuanAdapter.migrateLegacyInjectedReferer(configJson)) {
            migrated = true;
          }
          _imported.add(PluginConfig.fromJson(configJson));
        }
        if (migrated) await _persistImported();
      } catch (_) {
        // 损坏数据忽略
      }
    }

    // 加载状态覆盖并应用到内存中的源
    final stateRaw = prefs.getString(_stateOverridesKey);
    if (stateRaw != null) {
      try {
        final map = jsonDecode(stateRaw) as Map<String, dynamic>;
        _stateOverrides.addAll(
          map.map((k, v) => MapEntry(k, v as Map<String, dynamic>)),
        );
        _applyStateOverrides();
      } catch (_) {
        // 损坏数据忽略
      }
    }

    // 加载源排序 / 置顶
    final orderRaw = prefs.getString(_orderKey);
    if (orderRaw != null) {
      try {
        final m = jsonDecode(orderRaw) as Map<String, dynamic>;
        _customOrder
          ..clear()
          ..addAll(
            ((m['order'] as List?) ?? <dynamic>[])
                .map((e) => e.toString())
                .toList(),
          );
      } catch (_) {
        // 损坏数据忽略
      }
    }
    notifyListeners();
  }

  /// 启动时从资源包加载内置源（assets/plugins/builtin/<name>.json）。
  ///
  /// 缺失或解析失败的文件（如尚未补回的内置源）将被静默跳过，
  /// 补回文件后下次启动会自动加载。已屏蔽的内置源不会出现在 [all] 中。
  Future<void> loadBuiltins() async {
    // 先加载屏蔽集合（持久化于 SharedPreferences）。
    final prefs = await SharedPreferences.getInstance();
    final suppressedRaw = prefs.getString(_builtinOverrideKey);
    if (suppressedRaw != null) {
      try {
        final list = jsonDecode(suppressedRaw) as List<dynamic>;
        _suppressedBuiltins.clear();
        for (final e in list) {
          if (e is String) _suppressedBuiltins.add(e);
        }
      } catch (_) {
        // 损坏数据忽略
      }
    }

    _configs.clear();
    for (final name in _builtinAssetNames) {
      try {
        final raw = await rootBundle.loadString('plugins/builtin/$name.json');
        final parsed = SourceRepository.parseMixedSources(raw);
        if (parsed.isEmpty) {
          debugPrint('[SourceRepository] 内置源 $name 解析为空（格式不支持）');
          continue;
        }
        _configs.addAll(parsed);
      } on Object {
        debugPrint('[SourceRepository] 内置源 $name 跳过（缺失或解析失败）');
      }
    }
    notifyListeners();
  }

  void _suppressBuiltin(String id) {
    _suppressedBuiltins.add(id);
    _persistSuppressed();
  }

  void _unsuppressBuiltin(String id) {
    _suppressedBuiltins.remove(id);
    _persistSuppressed();
  }

  Future<void> _persistSuppressed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _builtinOverrideKey,
      jsonEncode(_suppressedBuiltins.toList()),
    );
  }

  /// 将状态覆盖应用到内存中的源（替换 _imported 中的条目）。
  void _applyStateOverrides() {
    for (final entry in _stateOverrides.entries) {
      final id = entry.key;
      final state = entry.value;
      final enabled = state['enabled'] as bool?;
      final isHidden = state['isHidden'] as bool?;
      _applyOverride(id, enabled: enabled, isHidden: isHidden);
    }
  }

  void _applyOverride(
    String id, {
    bool? enabled,
    bool? isHidden,
  }) {
    for (var i = 0; i < _imported.length; i++) {
      if (_imported[i].id == id) {
        _imported[i] = _imported[i].copyWith(
          enabled: enabled,
          isHidden: isHidden,
        );
        break;
      }
    }
  }

  /// 设置源的启用/禁用状态。
  Future<void> setEnabled(String id, bool enabled) async {
    _applyOverride(id, enabled: enabled);
    _stateOverrides[id] = <String, dynamic>{
      ..._stateOverrides[id] ?? <String, dynamic>{},
      'enabled': enabled,
    };
    await _persistStateOverrides();
    notifyListeners();
  }

  /// 设置源的隐藏/显示状态。
  Future<void> setHidden(String id, bool hidden) async {
    _applyOverride(id, isHidden: hidden);
    _stateOverrides[id] = <String, dynamic>{
      ..._stateOverrides[id] ?? <String, dynamic>{},
      'isHidden': hidden,
    };
    await _persistStateOverrides();
    notifyListeners();
  }

  Future<void> _persistImported() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _imported.map((c) => c.toJson()).toList();
    await prefs.setString(_importedKey, jsonEncode(list));
  }

  Future<void> _persistStateOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stateOverridesKey, jsonEncode(_stateOverrides));
  }
}
