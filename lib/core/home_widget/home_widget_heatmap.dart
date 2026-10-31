/// 当月打卡月历预渲染（按月排布，对齐 App 统计页热力图）。
///
/// 与背景图同一思路：系统卡片画不了复杂图形，由 Flutter 直接画成带透明通道的
/// PNG，卡片只当图片显示。透明底让卡片底色（含背景图）能透出来。
///
/// 排布：7 列（周一~周日）+ 表头 + 月首偏移空格，与统计页「热力图」弹窗同一
/// 套月历语言；未来日期不画（透明）。输出按 3x 屏物理像素取尺寸（cell 88px），
/// 卡片端 ImageFit.Contain 接近 1:1 显示，避免拉伸发虚。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/app_log.dart';

class HomeWidgetHeatmap {
  HomeWidgetHeatmap._();

  static const double _cell = 88;
  static const double _gap = 12;
  static const double _headerH = 44;
  static const double _legendH = 40;
  static const double _legendGap = 14;
  static const double _cellRadius = 16;
  static const double _todayStroke = 4;

  static String? _lastKey;
  static String? _lastPath;
  static String _lastBase64 = '';

  /// 生成/复用热力图，返回文件路径；失败返回 null（卡片就只显示文字）。
  ///
  /// [monthDailyMinutes]：当月每日分钟数，index = 日期 - 1，长度 = 当月天数。
  /// [today]：今天几号（之后的日期不画）。[weekdayLabels]：周一~周日表头文案。
  /// [legendLess] / [legendMore]：底部图例「少 / 多」文案（统计页同款图例）。
  static Future<String?> ensure({
    required List<int> monthDailyMinutes,
    required int today,
    required List<String> weekdayLabels,
    required String legendLess,
    required String legendMore,
    required Color themeColor,
    required bool isDark,
  }) async {
    final String key = '${monthDailyMinutes.join(",")}|$today|'
        '${weekdayLabels.join(",")}|$legendLess|$legendMore|'
        '${themeColor.toARGB32()}|$isDark';
    final String? cached = _lastPath;
    if (key == _lastKey && cached != null && File(cached).existsSync()) {
      return cached;
    }
    _lastBase64 = '';
    try {
      final ui.Image image = await _compose(
        monthDailyMinutes: monthDailyMinutes,
        today: today,
        weekdayLabels: weekdayLabels,
        legendLess: legendLess,
        legendMore: legendMore,
        themeColor: themeColor,
        isDark: isDark,
      );
      final String? path = await _persist(image);
      image.dispose();
      _lastKey = key;
      _lastPath = path;
      return path;
    } on Object catch (e) {
      AppLog.instance.w('[桌面卡片] 渲染热力图失败: $e');
      return null;
    }
  }

  static Future<ui.Image> _compose({
    required List<int> monthDailyMinutes,
    required int today,
    required List<String> weekdayLabels,
    required String legendLess,
    required String legendMore,
    required Color themeColor,
    required bool isDark,
  }) async {
    final int daysInMonth = monthDailyMinutes.length;
    // 月首偏移：DateTime.weekday 1=Mon..7=Sun → 周一开头的表头前空几格。
    final DateTime now = DateTime.now();
    final int offset = DateTime(now.year, now.month, 1).weekday - 1;
    final int rows = ((offset + daysInMonth) / 7).ceil();
    final int maxMinutes = monthDailyMinutes.fold(0, (int a, int b) => a > b ? a : b);
    // 空档要比 App 内更明显一点：卡片缩略场景下 0.08 几乎不可见，
    // 会让人误以为「整月只有几天有记录」。
    final double emptyAlpha = isDark ? 0.20 : 0.16;

    final double width = 7 * _cell + 6 * _gap;
    final double height = _headerH +
        _gap +
        rows * _cell +
        (rows - 1) * _gap +
        _legendGap +
        _legendH;
    final Rect bounds = Rect.fromLTWH(0, 0, width, height);
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder, bounds);

    // 表头：周一 ~ 周日。
    for (int c = 0; c < 7; c++) {
      final String label = c < weekdayLabels.length ? weekdayLabels[c] : '';
      if (label.isEmpty) continue;
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: themeColor.withValues(alpha: 0.55),
            fontSize: 32,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final double cx = c * (_cell + _gap) + (_cell - tp.width) / 2;
      tp.paint(canvas, Offset(cx, (_headerH - tp.height) / 2));
    }

    // 月历格子：色块 + 格内日期数字（对齐统计页热力图，避免像纯日历）。
    for (int day = 1; day <= daysInMonth; day++) {
      final int slot = offset + day - 1;
      final int col = slot % 7;
      final int row = slot ~/ 7;
      // 未来日期不画：月底剩下的格子留透明，一眼能看出「已过多少天」。
      if (day > today) continue;
      final int minutes = (day - 1) < monthDailyMinutes.length
          ? monthDailyMinutes[day - 1]
          : 0;
      final bool hasRecord = minutes > 0 && maxMinutes > 0;
      final double alpha = !hasRecord
          ? emptyAlpha
          : (0.28 + 0.62 * (minutes / maxMinutes)).clamp(0.28, 0.95);
      final Rect cellRect = Rect.fromLTWH(
        col * (_cell + _gap),
        _headerH + _gap + row * (_cell + _gap),
        _cell,
        _cell,
      );
      final RRect rrect = RRect.fromRectAndRadius(
        cellRect,
        const Radius.circular(_cellRadius),
      );
      // 半透明：透出卡片底色（card_bg 会随系统深浅变），浅色/深色都协调。
      canvas.drawRRect(rrect, Paint()..color = themeColor.withValues(alpha: alpha));
      // 格内日期数字：有记录白字（深色格），无记录同色淡字（对齐统计页）。
      final TextPainter dayTp = TextPainter(
        text: TextSpan(
          text: '$day',
          style: TextStyle(
            color: hasRecord
                ? Colors.white.withValues(alpha: 0.95)
                : themeColor.withValues(alpha: 0.6),
            fontSize: 30,
            fontWeight: hasRecord ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      dayTp.paint(
        canvas,
        Offset(
          cellRect.center.dx - dayTp.width / 2,
          cellRect.center.dy - dayTp.height / 2,
        ),
      );
      dayTp.dispose();
      // 今天：实色描边强调。
      if (day == today) {
        canvas.drawRRect(
          rrect.deflate(_todayStroke / 2),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = _todayStroke
            ..color = themeColor,
        );
      }
    }

    // 底部图例：少 ▢▢▢▢ 多（统计页同款四档色阶）。
    final double legendY = height - _legendH;
    TextPainter legendText(String s) {
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            color: themeColor.withValues(alpha: 0.6),
            fontSize: 26,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      return tp;
    }

    final TextPainter lessTp = legendText(legendLess);
    final TextPainter moreTp = legendText(legendMore);
    const double swatch = 26;
    final double legendW = lessTp.width +
        12 +
        4 * swatch +
        3 * 8 +
        12 +
        moreTp.width;
    double lx = (width - legendW) / 2;
    final double ly = legendY + (_legendH - swatch) / 2;
    lessTp.paint(canvas, Offset(lx, legendY + (_legendH - lessTp.height) / 2));
    lx += lessTp.width + 12;
    for (final double t in const <double>[0.0, 0.3, 0.6, 1.0]) {
      final double a = t <= 0 ? emptyAlpha : 0.28 + 0.62 * t;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(lx, ly, swatch, swatch),
          const Radius.circular(6),
        ),
        Paint()..color = themeColor.withValues(alpha: a.clamp(0.0, 0.95)),
      );
      lx += swatch + 8;
    }
    moreTp.paint(canvas, Offset(lx, legendY + (_legendH - moreTp.height) / 2));
    lessTp.dispose();
    moreTp.dispose();

    final ui.Picture picture = recorder.endRecording();
    final ui.Image image =
        await picture.toImage(width.round(), height.round());
    picture.dispose();
    return image;
  }

  /// 最近一次生成的热力图 Base64 data URI（未生成时为空串）。
  static String get lastBase64 => _lastBase64;

  static Future<String?> _persist(ui.Image image) async {
    final ByteData? data =
        await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    final Directory dir = await getApplicationSupportDirectory();
    final Directory target = Directory('${dir.path}/home_widget');
    if (!target.existsSync()) target.createSync(recursive: true);
    final Uint8List bytes = data.buffer.asUint8List();
    final File out = File('${target.path}/heatmap.png');
    await out.writeAsBytes(bytes, flush: true);
    // 卡片（鸿蒙）拿不到文件路径，只能收 Base64 data URI。
    _lastBase64 = 'data:image/png;base64,${base64Encode(bytes)}';
    return out.path;
  }
}
