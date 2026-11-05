/// 软件级公告（区别于源级公告 [SourceAnnouncementBanner]）。
///
/// 公告内容来自远程 GitHub 仓库的 JSON（raw 文件），随版本/运营随时更新；
/// 网络不可用时回退到打包资源 `assets/announcements.json`。已读过的公告 id
/// 持久化到 `shared_preferences`，下次启动不再弹窗——只有新增/未读的公告才会弹出。
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

/// 单条软件公告。
class SoftwareAnnouncement {
  final String id;
  final String date;
  final String title;
  final String titleEn;
  final String body;
  final String bodyEn;
  final String url;
  final String urlText;
  final String urlTextEn;

  const SoftwareAnnouncement({
    required this.id,
    required this.date,
    required this.title,
    required this.titleEn,
    required this.body,
    required this.bodyEn,
    this.url = '',
    this.urlText = '',
    this.urlTextEn = '',
  });

  factory SoftwareAnnouncement.fromJson(Map<String, dynamic> json) {
    return SoftwareAnnouncement(
      id: (json['id'] as String?) ?? '',
      date: (json['date'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      titleEn: (json['titleEn'] as String?) ?? (json['title'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      bodyEn: (json['bodyEn'] as String?) ?? (json['body'] as String?) ?? '',
      url: (json['url'] as String?) ?? '',
      urlText: (json['urlText'] as String?) ?? '',
      urlTextEn: (json['urlTextEn'] as String?) ?? (json['urlText'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'date': date,
        'title': title,
        'titleEn': titleEn,
        'body': body,
        'bodyEn': bodyEn,
        'url': url,
        'urlText': urlText,
        'urlTextEn': urlTextEn,
      };
}

/// 加载并追踪软件公告是否已读。
class SoftwareAnnouncementService {
  static const String _seenKey = 'software_announcement_seen_v1';

  /// 远程公告地址（jsDelivr 加速，对应 GitHub 仓库文件）。
  ///
  /// 默认指向本项目仓库的 `assets/announcements.json`：把公告文件推到仓库后，
  /// 应用即通过多源依次拉取最新版。国内 jsDelivr 常被墙/超时，故依次尝试
  /// jsDelivr → GitHub raw → 国内镜像，任一可用即用，避免「静默回退到打包旧文件」
  /// 导致 GitHub 新增公告不显示。若要托管到自己的仓库，改这里（或后续接入设置项）即可。
  static const String remoteUrl =
      'https://cdn.jsdelivr.net/gh/nexhub-app/nexhub@main/assets/announcements.json';

  /// GitHub raw 回退地址（jsDelivr 失败时使用）。
  static const String _rawFallbackUrl =
      'https://raw.githubusercontent.com/nexhub-app/nexhub/main/assets/announcements.json';

  /// 国内镜像（ghfast.top 反代 raw.githubusercontent），再兜底一次。
  static const String _mirrorFallbackUrl =
      'https://ghfast.top/https://raw.githubusercontent.com/nexhub-app/nexhub/main/assets/announcements.json';

  /// 网络不可用时的本地兜底资源。
  static const String _fallbackAsset = 'assets/announcements.json';

  /// 最后一次成功拉取的远程公告缓存键（远程全失败时回退，避免退回打包旧文件）。
  static const String _remoteCacheKey = 'software_announcement_remote_cache_v1';

  /// 共享的 HTTP 客户端：复用连接池，避免每次请求都新建 Dio（含新建
  /// HttpClient / DNS / TLS 握手，弱网下首包明显更慢）。
  ///
  /// 超时刻意收紧——公告属于「有则更好」的内容，宁可回退本地缓存，也不让
  /// 界面卡在网络上：4s 建连足以覆盖直连 jsDelivr / raw 被阻断时的等待。
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 4),
      sendTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 6),
      responseType: ResponseType.plain,
      headers: const <String, Object>{
        'Accept': 'application/json, text/plain, */*',
      },
    ),
  );

  static final SoftwareAnnouncementService instance =
      SoftwareAnnouncementService._();

  List<SoftwareAnnouncement> _all = const <SoftwareAnnouncement>[];
  Set<String> _seen = const <String>{};
  bool _loaded = false;

  /// 正在进行的远程拉取（单飞：并发调用复用同一请求，避免重复下载）。
  Future<bool>? _inflight;

  SoftwareAnnouncementService._();

  /// 本地数据（内存 / 上次成功缓存 / 打包资源）是否已就绪。
  ///
  /// 注意：为 true 不代表已联网刷新过，只表示「有内容可渲染」。
  bool get loaded => _loaded;

  /// 全部公告（含已读，保持清单顺序）。
  List<SoftwareAnnouncement> get all =>
      List<SoftwareAnnouncement>.unmodifiable(_all);

  /// 指定公告是否已读。
  bool isSeen(String id) => _seen.contains(id);

  /// 只读本地数据，不发起任何网络请求。
  ///
  /// 取值顺序：内存 → 上次成功拉取的缓存 → 打包资源。公告页先用它渲染首屏
  /// 做到「秒开」，再后台静默刷新；启动弹窗则用 [load] 等一次远程结果。
  Future<void> loadLocal() async {
    if (_all.isEmpty) {
      final cached = await _loadRemoteCache();
      if (cached != null && cached.isNotEmpty) {
        _all = cached;
      } else {
        try {
          _all = await _loadAsset();
        } on Object {
          _all = const <SoftwareAnnouncement>[];
        }
      }
    }
    if (!_loaded) {
      final prefs = await SharedPreferences.getInstance();
      _seen = (prefs.getStringList(_seenKey) ?? const <String>[]).toSet();
    }
    _loaded = true;
  }

  /// 本地优先 + 远程刷新（启动弹窗用：需要最新公告才能判断「未读」）。
  ///
  /// 远程全失败时静默保留 [loadLocal] 取到的内容，不会清空。
  Future<void> load() async {
    await loadLocal();
    await _pullRemote();
  }

  /// 重新拉取远程公告（公告页下拉刷新 / 手动刷新用）。
  ///
  /// 与 [load] 的区别：保留已读状态，只在拉取成功时替换内容，失败返回 false
  /// （调用方提示，不清空已有公告）。返回是否拿到了新数据。
  Future<bool> refresh() => _pullRemote();

  /// 远程拉取的单飞入口：同一时刻只允许一个请求在跑，重复调用复用同一结果。
  Future<bool> _pullRemote() {
    final inflight = _inflight;
    if (inflight != null) return inflight;
    final future = _pullRemoteOnce();
    _inflight = future;
    future.whenComplete(() {
      if (identical(_inflight, future)) _inflight = null;
    });
    return future;
  }

  Future<bool> _pullRemoteOnce() async {
    try {
      final parsed = await _fetchRemote();
      if (parsed.isEmpty) return false;
      // 先让内存生效，再落盘缓存（缓存失败也不影响本次展示）。
      _all = parsed;
      await _cacheRemote(parsed);
      return true;
    } on Object {
      // 远程全失败：保留现有内容（缓存 / 打包资源）。
      return false;
    }
  }

  /// 从远程解析公告清单：jsDelivr / GitHub raw / 国内镜像按**阶梯并发**竞速，
  /// 谁先返回有效清单就用谁。
  ///
  /// 之前是串行依次尝试，单个源超时叠加，最坏要等十几秒到几十秒才回退，公告页
  /// 因此长时间转圈。现在第一个源先发，若 [Duration] 内没结果再放出下一个：
  /// 网络正常时只发一个请求（不浪费三份流量），被墙时仍能快速兜底，
  /// 总耗时约等于「最先能用的那个源」的响应时间。
  Future<List<SoftwareAnnouncement>> _fetchRemote() async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final urls = <String>[
      '$remoteUrl?t=$ts',
      '$_rawFallbackUrl?t=$ts',
      '$_mirrorFallbackUrl?t=$ts',
    ];

    final completer = Completer<List<SoftwareAnnouncement>>();
    var pending = urls.length;

    void settle() {
      pending--;
      if (pending == 0 && !completer.isCompleted) {
        completer.completeError(
          StateError('all announcement sources failed'),
        );
      }
    }

    for (var i = 0; i < urls.length; i++) {
      final url = urls[i];
      final staggerMs = 600 * i;
      unawaited(() async {
        if (staggerMs > 0) {
          await Future<void>.delayed(Duration(milliseconds: staggerMs));
          // 前序源已成功：后面的源不再发起，省流量也省时间。
          if (completer.isCompleted) {
            settle();
            return;
          }
        }
        try {
          final result = await _fetchFromUrl(url);
          if (!completer.isCompleted) completer.complete(result);
        } on Object {
          // 单源失败：等其余源或由 settle 决定整体失败。
        } finally {
          settle();
        }
      }());
    }
    // 硬上限兜底：任一源卡在 DNS / 慢链路也不让整体拖过 8s（否则启动弹窗
    // 迟迟不出现）。到点后按失败处理，调用方保留本地内容。
    Timer(const Duration(seconds: 8), () {
      if (!completer.isCompleted) {
        completer.completeError(StateError('announcement fetch timed out'));
      }
    });
    return completer.future;
  }

  Future<List<SoftwareAnnouncement>> _fetchFromUrl(String url) async {
    final resp = await _dio.get<String>(url);
    final data = resp.data;
    if (data == null || data.trim().isEmpty) {
      throw StateError('empty remote announcement');
    }
    final decoded = jsonDecode(data);
    if (decoded is! List<dynamic>) {
      throw StateError('remote announcement is not a list');
    }
    final list = decoded
        .map((e) => SoftwareAnnouncement.fromJson(e as Map<String, dynamic>))
        .where((a) => a.id.isNotEmpty)
        .toList();
    if (list.isEmpty) throw StateError('remote announcement is empty');
    return list;
  }

  /// 从打包资源解析公告清单（回退用）。
  Future<List<SoftwareAnnouncement>> _loadAsset() async {
    final raw = await rootBundle.loadString(_fallbackAsset);
    final decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) return const <SoftwareAnnouncement>[];
    return decoded
        .map((e) => SoftwareAnnouncement.fromJson(e as Map<String, dynamic>))
        .where((a) => a.id.isNotEmpty)
        .toList();
  }

  /// 缓存最后一次成功拉取的远程公告到本地，供后续离线/全失败回退。
  Future<void> _cacheRemote(List<SoftwareAnnouncement> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(list.map((a) => a.toJson()).toList());
      await prefs.setString(_remoteCacheKey, json);
    } on Object {
      // 缓存失败不影响主流程。
    }
  }

  /// 读取上次成功缓存的远程公告；无则 null。
  Future<List<SoftwareAnnouncement>?> _loadRemoteCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_remoteCacheKey);
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) return null;
      return decoded
          .map((e) => SoftwareAnnouncement.fromJson(e as Map<String, dynamic>))
          .where((a) => a.id.isNotEmpty)
          .toList();
    } on Object {
      return null;
    }
  }

  /// 返回尚未读过的公告（按资源顺序）。
  List<SoftwareAnnouncement> unseen() =>
      _all.where((a) => !_seen.contains(a.id)).toList();

  /// 将指定公告标记为已读并持久化。
  Future<void> markSeen(List<String> ids) async {
    if (ids.isEmpty) return;
    final merged = <String>{..._seen, ...ids};
    _seen = merged;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_seenKey, merged.toList());
  }
}
