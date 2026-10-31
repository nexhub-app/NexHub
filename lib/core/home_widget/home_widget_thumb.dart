/// 卡片封面缩略图（Base64 data URI）。
///
/// 为什么不用文件路径：鸿蒙 ArkTS 卡片是独立沙盒进程，卡片里的 `Image` **不支持
/// file:// 路径、也不支持 PixelMap**，只认三种源：`$r()`、`$rawfile()`、Base64
/// 字符串。所以封面必须以 Base64 data URI 交给卡片。
///
/// 180×240：大卡封面约 200dp 宽，这个分辨率缩放后不糊；再大 base64 会撑爆
/// preferences 单值与 Binder 传输（8 条约 140KB，已是安全上限附近）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';

import '../utils/app_log.dart';

class HomeWidgetThumb {
  HomeWidgetThumb._();

  static const int _width = 240;
  static const int _height = 320;

  /// path → data URI 的内存缓存（封面路径不变就复用，避免每次刷新重编码）。
  static final Map<String, String> _cache = <String, String>{};

  /// 生成封面缩略图；失败返回空串（卡片显示占位区域）。
  static Future<String> dataUri(String? path) async {
    if (path == null || path.isEmpty) return '';
    final String? cached = _cache[path];
    if (cached != null) return cached;
    try {
      final ui.Image? source = await _decode(path);
      if (source == null) return '';
      final ui.Image scaled = await _render(source);
      source.dispose();
      final ByteData? bytes =
          await scaled.toByteData(format: ui.ImageByteFormat.png);
      scaled.dispose();
      if (bytes == null) return '';
      final String uri =
          'data:image/png;base64,${base64Encode(bytes.buffer.asUint8List())}';
      // 只保留最近 8 张，避免长列表把内存撑大。
      if (_cache.length >= 8) _cache.remove(_cache.keys.first);
      _cache[path] = uri;
      return uri;
    } on Object catch (e) {
      AppLog.instance.w('[桌面卡片] 生成封面缩略图失败 $path: $e');
      return '';
    }
  }

  static Future<ui.Image?> _decode(String path) async {
    final File file = File(path);
    if (!file.existsSync()) return null;
    try {
      final ui.Codec codec =
          await ui.instantiateImageCodec(await file.readAsBytes());
      final ui.FrameInfo frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } on Object {
      return null;
    }
  }

  /// 等比铺满缩略图框（centerCrop）。
  static Future<ui.Image> _render(ui.Image source) async {
    final Rect dst =
        Rect.fromLTWH(0, 0, _width.toDouble(), _height.toDouble());
    final double iw = source.width.toDouble();
    final double ih = source.height.toDouble();
    final double scale = math.max(_width / iw, _height / ih);
    final Rect src = Rect.fromLTWH(
      (iw - _width / scale) / 2,
      (ih - _height / scale) / 2,
      _width / scale,
      _height / scale,
    );
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder, dst);
    canvas.drawImageRect(
      source,
      src,
      dst,
      Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(_width, _height);
    picture.dispose();
    return image;
  }
}
