/// 卡片背景图预渲染。
///
/// 为什么在 Flutter 侧画：系统卡片（Android RemoteViews / 鸿蒙 ArkTS Form）都
/// 不能对网络图做实时高斯模糊，也不可能在卡片里跑 Flutter。所以由本应用把
/// 「底色 + 封面 + 模糊 + 不透明度」直接合成一张不透明 PNG，原生只当图片显示。
///
/// 输出固定 512×512：卡片最大档 4×4 约 250dp，512px 在高密度屏上已足够，
/// 再大只会增加 Binder / PixelMap 传输开销。
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/app_log.dart';
import 'home_widget_settings.dart';

class HomeWidgetBackground {
  HomeWidgetBackground._();

  /// 画布边长（px）。
  static const int _canvasSize = 512;

  /// 上次渲染的参数指纹与产物路径，避免每 3 秒一次刷新都重画。
  static String? _lastKey;
  static String? _lastPath;

  /// 确保背景图存在，返回文件绝对路径；无背景时返回 null。
  ///
  /// [coverPath] 为空或解码失败时会退化成纯底色（不抛错）。
  /// [cardBg] 是 App 内 `AppTheme.cardContainer` 的同源底色：三种模式的
  /// 最底层都用它，保证卡片底色与统计页卡片一致（而不是死白/死黑）。
  static Future<String?> ensure({
    required WidgetBackgroundMode mode,
    required String? coverPath,
    required double blurSigma,
    required double opacity,
    required bool isDark,
    required Color themeColor,
    required Color cardBg,
  }) async {
    final String key = '${mode.name}|${coverPath ?? ''}|'
        '${blurSigma.toStringAsFixed(1)}|${opacity.toStringAsFixed(2)}|$isDark|'
        '${themeColor.toARGB32()}|${cardBg.toARGB32()}';
    final String? cached = _lastPath;
    if (key == _lastKey && cached != null && File(cached).existsSync()) {
      return cached;
    }
    try {
      final ui.Image image = await _compose(
        mode: mode,
        coverPath: coverPath,
        blurSigma: blurSigma,
        opacity: opacity,
        isDark: isDark,
        themeColor: themeColor,
        cardBg: cardBg,
      );
      final String? path = await _persist(image);
      image.dispose();
      _lastKey = key;
      _lastPath = path;
      return path;
    } on Object catch (e) {
      AppLog.instance.w('[桌面卡片] 渲染背景失败: $e');
      return null;
    }
  }

  static Future<ui.Image> _compose({
    required WidgetBackgroundMode mode,
    required String? coverPath,
    required double blurSigma,
    required double opacity,
    required bool isDark,
    required Color themeColor,
    required Color cardBg,
  }) async {
    final double size = _canvasSize.toDouble();
    final Rect bounds = Rect.fromLTWH(0, 0, size, size);
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder, bounds);

    // 1. 底色：与 App 内 AppCard 同源（cardContainer，主色微染）。
    //    不再是死白/死黑 —— 用户在统计页看到的卡片底色就是这一层。
    canvas.drawRect(bounds, Paint()..color = cardBg);

    // 2. 主题色渐变（theme 模式的主视觉；cover/none 模式不出渐变，
    //    让卡片底色干净得和 App 内卡片一样）。
    if (mode == WidgetBackgroundMode.theme) {
      final Rect gradientRect = bounds;
      canvas.drawRect(
        gradientRect,
        Paint()
          ..shader = ui.Gradient.linear(
            gradientRect.topLeft,
            gradientRect.bottomRight,
            <Color>[
              themeColor.withValues(alpha: isDark ? 0.20 : 0.14),
              themeColor.withValues(alpha: isDark ? 0.06 : 0.03),
            ],
          ),
      );
    }

    // 3. 封面层：模糊 + 按不透明度合成（saveLayer 的 paint alpha 控制整层不透明度）。
    if (mode == WidgetBackgroundMode.cover && coverPath != null) {
      final ui.Image? cover = await _decode(coverPath);
      if (cover != null) {
        final Paint layerPaint = Paint()
          ..color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0))
          ..imageFilter = blurSigma > 0
              ? ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma)
              : null;
        canvas.saveLayer(bounds, layerPaint);
        _drawCoverCrop(canvas, cover, bounds);
        canvas.restore();
        cover.dispose();
      }
    }

    // 4. 底部压暗：封面模式下卡片文字都在下半部分，压一层自下而上的黑渐变
    //    保证对比度（浅色封面时尤其明显，否则白字会糊在图上）。
    if (mode == WidgetBackgroundMode.cover) {
      canvas.drawRect(
        bounds,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, size),
            Offset(0, size * 0.35),
            const <Color>[Color(0x66000000), Color(0x00000000)],
          ),
      );
    }

    final ui.Picture picture = recorder.endRecording();
    final ui.Image image =
        await picture.toImage(_canvasSize, _canvasSize);
    picture.dispose();
    return image;
  }

  /// 等比铺满（centerCrop）：短边撑满画布，长边居中裁掉。
  static void _drawCoverCrop(Canvas canvas, ui.Image image, Rect dst) {
    final double iw = image.width.toDouble();
    final double ih = image.height.toDouble();
    if (iw <= 0 || ih <= 0) return;
    final double scale = math.max(dst.width / iw, dst.height / ih);
    final double w = iw * scale;
    final double h = ih * scale;
    final Rect src = Rect.fromLTWH(
      (iw - dst.width / scale) / 2,
      (ih - dst.height / scale) / 2,
      dst.width / scale,
      dst.height / scale,
    );
    canvas.drawImageRect(
      image,
      src,
      Rect.fromLTWH(
        (dst.width - w) / 2,
        (dst.height - h) / 2,
        w,
        h,
      ),
      Paint()..filterQuality = ui.FilterQuality.medium,
    );
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
    } on Object catch (e) {
      AppLog.instance.w('[桌面卡片] 解码封面失败 $path: $e');
      return null;
    }
  }

  static Future<String?> _persist(ui.Image image) async {
    final ByteData? data =
        await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    final Directory dir = await getApplicationSupportDirectory();
    final Directory target = Directory('${dir.path}/home_widget');
    if (!target.existsSync()) target.createSync(recursive: true);
    final File out = File('${target.path}/bg.png');
    await out.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return out.path;
  }
}
