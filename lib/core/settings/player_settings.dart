/// 播放器默认设置模型（全局默认值，播放时可临时覆盖）。
///
/// 持久化到 SharedPreferences（key: `player_settings_v1`），
/// 复用 [PrefsBackend] 抽象以便测试注入。
library;

import 'dart:convert';

import '../comic/models/reader_preferences.dart';

/// 解码模式。
enum DecodeMode { auto, sw, hw, hwPlus }

/// 音频通道。
enum AudioChannel { auto, stereo, mono }

/// 画面比例。
enum PlayerAspectRatio { defaultRatio, ratio43, ratio169, fill }

/// 播放器锁定方向（项 1：合并旧 playerDefaultOrientation + 锁方向）。
///
/// [followVideo]：按视频宽高自动切横竖（竖视频锁竖屏 / 横视频锁横屏），
/// 默认值；[auto]：不锁定，跟随系统旋转设置。
enum PlayerLockOrientation { auto, portrait, landscape, followVideo }

/// 播放器左右拖动 Seek 区间倍率。
enum SeekMultiplier { half, normal, double }

/// 超分辨率 shader 档位：off 关闭 / performance 效率 / quality 质量。
enum UpscaleShaderMode { off, performance, quality }

/// 播放器默认设置。
class PlayerSettings {
  final DecodeMode decodeMode;
  final AudioChannel audioChannel;
  final PlayerAspectRatio aspectRatio;
  final double playbackSpeed;
  final bool autoPlayNext;
  /// 自动选线路（默认开启）：进入剧集时优先用「按集记忆」选过的线路；
  /// 播放卡死/失败后自动轮换到其它候选线路重试，不弹「链接失效」让用户手点。
  final bool autoSelectLine;
  /// 自动连播倒计时秒数：播完一集后弹「N 秒后播放下一集」可取消，
  /// 0 = 立即连播（保持旧行为）。
  final int autoPlayCountdownSeconds;
  final double subtitleFontSize;
  final PlayerLockOrientation lockOrientation;
  final SeekMultiplier seekMultiplier;
  final bool longPressSpeedUp;
  /// 长按加速时切换到的自定义倍速（默认 2.0x）。
  final double longPressSpeed;
  final double defaultVolume;
  final String screenshotSavePath;
  /// 隐藏控制栏后底部是否保留细进度条（默认开启）。
  final bool showBottomProgress;
  final double subtitleScale;
  final double subtitleBorderSize;
  final double subtitleShadowOffset;
  final String subtitleColor;
  final String subtitleBorderColor;
  final String subtitleShadowColor;
  final String subtitlePosition;
  final String subtitleAssMode;
  final int subtitleDelayMs;
  final bool subtitleVisible;
  /// 超分辨率 shader 档位（默认关闭）。
  final UpscaleShaderMode upscaleShader;

  const PlayerSettings({
    this.decodeMode = DecodeMode.auto,
    this.audioChannel = AudioChannel.auto,
    this.aspectRatio = PlayerAspectRatio.defaultRatio,
    this.playbackSpeed = 1.0,
    this.autoPlayNext = true,
    this.autoSelectLine = true,
    this.autoPlayCountdownSeconds = 0,
    this.subtitleFontSize = 16.0,
    this.lockOrientation = PlayerLockOrientation.followVideo,
    this.seekMultiplier = SeekMultiplier.normal,
    this.longPressSpeedUp = true,
    this.longPressSpeed = 2.0,
    this.defaultVolume = 100.0,
    this.screenshotSavePath = '',
    this.showBottomProgress = true,
    this.subtitleScale = 1.0,
    this.subtitleBorderSize = 1.5,
    this.subtitleShadowOffset = 2.0,
    this.subtitleColor = 'FFFFFF',
    this.subtitleBorderColor = '000000',
    this.subtitleShadowColor = '000000',
    this.subtitlePosition = 'bottom',
    this.subtitleAssMode = 'yes',
    this.subtitleDelayMs = 0,
    this.subtitleVisible = true,
    this.upscaleShader = UpscaleShaderMode.off,
  });

  PlayerSettings copyWith({
    DecodeMode? decodeMode,
    AudioChannel? audioChannel,
    PlayerAspectRatio? aspectRatio,
    double? playbackSpeed,
    bool? autoPlayNext,
    bool? autoSelectLine,
    int? autoPlayCountdownSeconds,
    double? subtitleFontSize,
    PlayerLockOrientation? lockOrientation,
    SeekMultiplier? seekMultiplier,
    bool? longPressSpeedUp,
    double? longPressSpeed,
    double? defaultVolume,
    String? screenshotSavePath,
    bool? showBottomProgress,
    double? subtitleScale,
    double? subtitleBorderSize,
    double? subtitleShadowOffset,
    String? subtitleColor,
    String? subtitleBorderColor,
    String? subtitleShadowColor,
    String? subtitlePosition,
    String? subtitleAssMode,
    int? subtitleDelayMs,
    bool? subtitleVisible,
    UpscaleShaderMode? upscaleShader,
  }) =>
      PlayerSettings(
        decodeMode: decodeMode ?? this.decodeMode,
        audioChannel: audioChannel ?? this.audioChannel,
        aspectRatio: aspectRatio ?? this.aspectRatio,
        playbackSpeed: playbackSpeed ?? this.playbackSpeed,
        autoPlayNext: autoPlayNext ?? this.autoPlayNext,
        autoSelectLine: autoSelectLine ?? this.autoSelectLine,
        autoPlayCountdownSeconds:
            autoPlayCountdownSeconds ?? this.autoPlayCountdownSeconds,
        subtitleFontSize: subtitleFontSize ?? this.subtitleFontSize,
        lockOrientation: lockOrientation ?? this.lockOrientation,
        seekMultiplier: seekMultiplier ?? this.seekMultiplier,
        longPressSpeedUp: longPressSpeedUp ?? this.longPressSpeedUp,
        longPressSpeed: longPressSpeed ?? this.longPressSpeed,
        defaultVolume: defaultVolume ?? this.defaultVolume,
        screenshotSavePath: screenshotSavePath ?? this.screenshotSavePath,
        showBottomProgress: showBottomProgress ?? this.showBottomProgress,
        subtitleScale: subtitleScale ?? this.subtitleScale,
        subtitleBorderSize: subtitleBorderSize ?? this.subtitleBorderSize,
        subtitleShadowOffset:
            subtitleShadowOffset ?? this.subtitleShadowOffset,
        subtitleColor: subtitleColor ?? this.subtitleColor,
        subtitleBorderColor: subtitleBorderColor ?? this.subtitleBorderColor,
        subtitleShadowColor: subtitleShadowColor ?? this.subtitleShadowColor,
        subtitlePosition: subtitlePosition ?? this.subtitlePosition,
        subtitleAssMode: subtitleAssMode ?? this.subtitleAssMode,
        subtitleDelayMs: subtitleDelayMs ?? this.subtitleDelayMs,
        subtitleVisible: subtitleVisible ?? this.subtitleVisible,
        upscaleShader: upscaleShader ?? this.upscaleShader,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'decodeMode': decodeMode.name,
        'audioChannel': audioChannel.name,
        'aspectRatio': aspectRatio.name,
        'playbackSpeed': playbackSpeed,
        'autoPlayNext': autoPlayNext,
        'autoSelectLine': autoSelectLine,
        'autoPlayCountdownSeconds': autoPlayCountdownSeconds,
        'subtitleFontSize': subtitleFontSize,
        'lockOrientation': lockOrientation.name,
        'seekMultiplier': seekMultiplier.name,
        'longPressSpeedUp': longPressSpeedUp,
        'longPressSpeed': longPressSpeed,
        'defaultVolume': defaultVolume,
        'screenshotSavePath': screenshotSavePath,
        'showBottomProgress': showBottomProgress,
        'subtitleScale': subtitleScale,
        'subtitleBorderSize': subtitleBorderSize,
        'subtitleShadowOffset': subtitleShadowOffset,
        'subtitleColor': subtitleColor,
        'subtitleBorderColor': subtitleBorderColor,
        'subtitleShadowColor': subtitleShadowColor,
        'subtitlePosition': subtitlePosition,
        'subtitleAssMode': subtitleAssMode,
        'subtitleDelayMs': subtitleDelayMs,
        'subtitleVisible': subtitleVisible,
        'upscaleShader': upscaleShader.name,
      };

  factory PlayerSettings.fromJson(Map<String, dynamic> json) {
    DecodeMode decodeMode = DecodeMode.auto;
    if (json['decodeMode'] is String) {
      decodeMode = DecodeMode.values.firstWhere(
        (e) => e.name == json['decodeMode'],
        orElse: () => DecodeMode.auto,
      );
    }
    AudioChannel audioChannel = AudioChannel.auto;
    if (json['audioChannel'] is String) {
      audioChannel = AudioChannel.values.firstWhere(
        (e) => e.name == json['audioChannel'],
        orElse: () => AudioChannel.auto,
      );
    }
    PlayerAspectRatio aspectRatio = PlayerAspectRatio.defaultRatio;
    if (json['aspectRatio'] is String) {
      aspectRatio = PlayerAspectRatio.values.firstWhere(
        (e) => e.name == json['aspectRatio'],
        orElse: () => PlayerAspectRatio.defaultRatio,
      );
    }
    // 缺失 / 非法值回退到默认「跟随视频」，老用户已持久化过的选择不受影响。
    PlayerLockOrientation lockOrientation = PlayerLockOrientation.followVideo;
    if (json['lockOrientation'] is String) {
      lockOrientation = PlayerLockOrientation.values.firstWhere(
        (e) => e.name == json['lockOrientation'],
        orElse: () => PlayerLockOrientation.followVideo,
      );
    }
    SeekMultiplier seekMultiplier = SeekMultiplier.normal;
    if (json['seekMultiplier'] is String) {
      seekMultiplier = SeekMultiplier.values.firstWhere(
        (e) => e.name == json['seekMultiplier'],
        orElse: () => SeekMultiplier.normal,
      );
    }
    UpscaleShaderMode upscaleShader = UpscaleShaderMode.off;
    if (json['upscaleShader'] is String) {
      upscaleShader = UpscaleShaderMode.values.firstWhere(
        (e) => e.name == json['upscaleShader'],
        orElse: () => UpscaleShaderMode.off,
      );
    }
    return PlayerSettings(
      decodeMode: decodeMode,
      audioChannel: audioChannel,
      aspectRatio: aspectRatio,
      playbackSpeed: (json['playbackSpeed'] as num?)?.toDouble() ?? 1.0,
      autoPlayNext: json['autoPlayNext'] as bool? ?? true,
      autoSelectLine: json['autoSelectLine'] as bool? ?? true,
      autoPlayCountdownSeconds:
          (json['autoPlayCountdownSeconds'] as num?)?.toInt() ?? 0,
      subtitleFontSize:
          (json['subtitleFontSize'] as num?)?.toDouble() ?? 16.0,
      lockOrientation: lockOrientation,
      seekMultiplier: seekMultiplier,
      longPressSpeedUp: json['longPressSpeedUp'] as bool? ?? true,
      longPressSpeed:
          (json['longPressSpeed'] as num?)?.toDouble() ?? 2.0,
      defaultVolume:
          (json['defaultVolume'] as num?)?.toDouble() ?? 100.0,
      screenshotSavePath:
          json['screenshotSavePath'] as String? ?? '',
      showBottomProgress: json['showBottomProgress'] as bool? ?? true,
      subtitleScale:
          (json['subtitleScale'] as num?)?.toDouble() ?? 1.0,
      subtitleBorderSize:
          (json['subtitleBorderSize'] as num?)?.toDouble() ?? 1.5,
      subtitleShadowOffset:
          (json['subtitleShadowOffset'] as num?)?.toDouble() ?? 2.0,
      subtitleColor: json['subtitleColor'] as String? ?? 'FFFFFF',
      subtitleBorderColor:
          json['subtitleBorderColor'] as String? ?? '000000',
      subtitleShadowColor:
          json['subtitleShadowColor'] as String? ?? '000000',
      subtitlePosition:
          json['subtitlePosition'] as String? ?? 'bottom',
      subtitleAssMode: json['subtitleAssMode'] as String? ?? 'yes',
      subtitleDelayMs: json['subtitleDelayMs'] as int? ?? 0,
      subtitleVisible: json['subtitleVisible'] as bool? ?? true,
      upscaleShader: upscaleShader,
    );
  }
}

/// 播放器设置持久化存储（key: `player_settings_v1`）。
class PlayerSettingsStore {
  static const String _key = 'player_settings_v1';

  final PrefsBackend _backend;

  PlayerSettingsStore({PrefsBackend? backend})
      : _backend = backend ?? const SharedPrefsBackend();

  Future<PlayerSettings> load() async {
    final raw = await _backend.get(_key);
    if (raw == null || raw.isEmpty) return const PlayerSettings();
    try {
      return PlayerSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } on Object {
      return const PlayerSettings();
    }
  }

  Future<void> save(PlayerSettings settings) async {
    await _backend.set(_key, jsonEncode(settings.toJson()));
  }
}

/// 按剧集记忆的播放器设置覆盖（key: `episode_player_settings_v1`）。
///
/// 播放器内弹窗（更多菜单 / 快捷行）修改的音画参数属于「该视频的单独设置」，
/// 只持久化**用户实际改过的字段**；读取时与全局 [PlayerSettings] 合并——
/// 覆盖字段优先，其余字段跟随全局默认。清除覆盖后回到「跟随全局」。
///
/// 值结构：`{"<itemId>": {"decodeMode": "hw", "playbackSpeed": 2.0, ...}}`。
class EpisodePlayerSettingsStore {
  static const String _key = 'episode_player_settings_v1';

  final PrefsBackend _backend;

  EpisodePlayerSettingsStore({PrefsBackend? backend})
      : _backend = backend ?? const SharedPrefsBackend();

  Future<Map<String, dynamic>> _loadAll() async {
    final raw = await _backend.get(_key);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } on Object {
      // 数据损坏时按空处理，不影响播放。
    }
    return <String, dynamic>{};
  }

  /// 读取某剧集已覆盖的字段（无覆盖返回空 Map）。
  Future<Map<String, dynamic>> loadOverrides(String itemId) async {
    final all = await _loadAll();
    final value = all[itemId];
    return value is Map<String, dynamic> ? value : <String, dynamic>{};
  }

  /// 合并全局设置：覆盖字段优先，其余取全局默认值。
  Future<PlayerSettings> loadMerged(
    PlayerSettings global,
    String itemId,
  ) async {
    final overrides = await loadOverrides(itemId);
    if (overrides.isEmpty) return global;
    return PlayerSettings.fromJson(
      <String, dynamic>{...global.toJson(), ...overrides},
    );
  }

  /// 写入某剧集的单个覆盖字段（只存用户实际改过的项）。
  Future<void> setField(String itemId, String field, Object? value) async {
    final all = await _loadAll();
    final overrides =
        all[itemId] is Map<String, dynamic>
            ? all[itemId]! as Map<String, dynamic>
            : <String, dynamic>{};
    overrides[field] = value;
    all[itemId] = overrides;
    await _backend.set(_key, jsonEncode(all));
  }

  /// 清除某剧集全部覆盖，恢复跟随全局默认。
  Future<void> clearOverrides(String itemId) async {
    final all = await _loadAll();
    all.remove(itemId);
    await _backend.set(_key, jsonEncode(all));
  }
}

/// 按「源 + 剧集」记忆用户手动选中的播放线路名（手动选源记忆）。
///
/// 仅存用户实际手动切换过的线路；读取不到时回退到自动选线路逻辑。
/// 存线路**名**而非索引：线路列表由源声明、顺序可能随源更新变化，
/// 按名匹配比按索引更稳健。
///
/// 值结构：`{"<sourceId>::<episodeId>": "<lineName>"}`。
class LineSelectionStore {
  static const String _key = 'episode_line_selection_v1';

  final PrefsBackend _backend;

  LineSelectionStore({PrefsBackend? backend})
      : _backend = backend ?? const SharedPrefsBackend();

  String _mk(String sourceId, String episodeId) => '$sourceId::$episodeId';

  Future<Map<String, dynamic>> _loadAll() async {
    final raw = await _backend.get(_key);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } on Object {
      // 数据损坏按空处理。
    }
    return <String, dynamic>{};
  }

  /// 读取某剧集记忆的线路名；无记忆返回 null。
  Future<String?> getSelectedLine(String sourceId, String episodeId) async {
    final all = await _loadAll();
    final value = all[_mk(sourceId, episodeId)];
    return value is String ? value : null;
  }

  /// 写入某剧集选中的线路名。
  Future<void> setSelectedLine(
    String sourceId,
    String episodeId,
    String lineName,
  ) async {
    final all = await _loadAll();
    all[_mk(sourceId, episodeId)] = lineName;
    await _backend.set(_key, jsonEncode(all));
  }

  /// 清除某剧集的记忆（恢复自动选线路）。
  Future<void> clear(String sourceId, String episodeId) async {
    final all = await _loadAll();
    all.remove(_mk(sourceId, episodeId));
    await _backend.set(_key, jsonEncode(all));
  }
}
