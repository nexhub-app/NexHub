/// 软件级公告（区别于源级公告 [SourceAnnouncementBanner]）。
///
/// 公告内容来自远程 GitHub 仓库的 JSON（raw 文件），随版本/运营随时更新；
/// 网络不可用时回退到打包资源 `assets/announcements.json`。已读过的公告 id
/// 持久化到 `shared_preferences`，下次启动不再弹窗——只有新增/未读的公告才会弹出。
library;

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

  static final SoftwareAnnouncementService instance =
      SoftwareAnnouncementService._();

  List<SoftwareAnnouncement> _all = const <SoftwareAnnouncement>[];
  Set<String> _seen = const <String>{};
  bool _loaded = false;

  SoftwareAnnouncementService._();

  /// 是否已至少加载过一次（公告页据此决定要不要等网络）。
  bool get loaded => _loaded;

  /// 全部公告（含已读，保持清单顺序）。
  List<SoftwareAnnouncement> get all =>
      List<SoftwareAnnouncement>.unmodifiable(_all);

  /// 指定公告是否已读。
  bool isSeen(String id) => _seen.contains(id);

  /// 优先拉取远程 JSON（多源依次尝试）；全部失败则回退到「上次成功缓存」，
  /// 仍无则回退打包资源。已读过的公告 id 持久化到 shared_preferences。
  Future<void> load() async {
    List<SoftwareAnnouncement>? parsed;
    try {
      parsed = await _fetchRemote();
    } on Object {
      // 远程全失败：尝试回退。
      parsed = null;
    }
    if (parsed != null) {
      _all = parsed;
      await _cacheRemote(parsed);
    } else {
      final cached = await _loadRemoteCache();
      if (cached != null) {
        _all = cached;
      } else {
        try {
          _all = await _loadAsset();
        } on Object {
          _all = const <SoftwareAnnouncement>[];
        }
      }
    }

    final prefs = await SharedPreferences.getInstance();
    _seen = (prefs.getStringList(_seenKey) ?? const <String>[]).toSet();
    _loaded = true;
  }

  /// 重新拉取远程公告（公告页下拉刷新 / 手动刷新用）。
  ///
  /// 与 [load] 的区别：保留已读状态与现有列表，只在拉取成功时替换内容，
  /// 失败返回 false（调用方提示，不清空已有公告）。返回是否有新数据。
  Future<bool> refresh() async {
    try {
      final parsed = await _fetchRemote();
      if (parsed.isEmpty) return false;
      _all = parsed;
      await _cacheRemote(parsed);
      return true;
    } on Object {
      return false;
    }
  }

  /// 从远程解析公告清单：依次尝试 jsDelivr → GitHub raw → 国内镜像。
  /// 每个 URL 追加时间戳查询破除 CDN/代理缓存，确保拿到最新文件。
  Future<List<SoftwareAnnouncement>> _fetchRemote() async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final urls = <String>[
      '$remoteUrl?t=$ts',
      '$_rawFallbackUrl?t=$ts',
      '$_mirrorFallbackUrl?t=$ts',
    ];
    for (final url in urls) {
      try {
        final result = await _fetchFromUrl(url);
        if (result.isNotEmpty) return result;
      } on Object {
        // 该源失败：尝试下一个。
      }
    }
    throw Exception('all announcement sources failed');
  }

  Future<List<SoftwareAnnouncement>> _fetchFromUrl(String url) async {
    final resp = await Dio().get<String>(
      url,
      options: Options(
        receiveTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 8),
      ),
    );
    final data = resp.data;
    if (data == null || data.trim().isEmpty) {
      throw Exception('empty remote announcement');
    }
    final decoded = jsonDecode(data);
    if (decoded is! List<dynamic>) {
      throw Exception('remote announcement is not a list');
    }
    return decoded
        .map((e) => SoftwareAnnouncement.fromJson(e as Map<String, dynamic>))
        .where((a) => a.id.isNotEmpty)
        .toList();
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
