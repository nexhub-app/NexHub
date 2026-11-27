import 'dart:io';
import 'package:material_ui/material_ui.dart';
import '../local/local_content_manager.dart' show isDocUri;
import '../local/saf_bridge.dart' show resolveSafUri;
import '../models/plugin_config.dart';
import '../theme/app_tokens.dart';
import 'source_image.dart';

/// 统一封面图：支持 http(s) 远程图与本地文件路径，含占位图、阴影、Hero。
///
/// 当 [source] 非空时，远程图委托给 [SourceImage]（注入防盗链 headers、
/// 带缓存与重试），并跳过自身装饰以避免双重 ClipRRect / Hero。
/// 当 [source] 为空时，保持原有兼容行为（无防盗链注入）。
class AppCoverImage extends StatelessWidget {
  final String? coverUrl;
  final double? width;
  final double? height;
  final double? radius;
  final BoxFit fit;
  final String? heroTag;
  final PluginConfig? source;

  /// 标题（封面为空时用于渲染首字占位图，避免纯灰块）。
  final String? title;
  const AppCoverImage({
    super.key,
    this.coverUrl,
    this.width,
    this.height,
    this.radius,
    this.fit = BoxFit.cover,
    this.heroTag,
    this.source,
    this.title,
  });

  /// 归一化后的封面地址：
  /// - 协议相对路径（`//cdn.xxx/cover.jpg`，部分源 cover 字段原样返回）补全
  ///   为 https，避免被误判成本地路径交给 `Image.file`（必然渲染失败占位）。
  /// - 空串归 null，走首字占位图分支。
  String? get _effectiveUrl {
    final String raw = coverUrl?.trim() ?? '';
    if (raw.isEmpty) return null;
    if (raw.startsWith('//')) return 'https:$raw';
    return raw;
  }

  bool get _isFile {
    final String? url = _effectiveUrl;
    return url != null && !url.startsWith('http');
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double r = radius ?? AppTokens.coverRadius;
    final String? effectiveUrl = _effectiveUrl;

    // 有源配置的远程图：直接委托 SourceImage（内部处理防盗链/圆角/Hero/占位），避免双重装饰。
    if (source != null && effectiveUrl != null && !_isFile) {
      return SourceImage(
        url: effectiveUrl,
        source: source,
        isCover: true,
        width: width,
        height: height,
        fit: fit,
        radius: radius,
        heroTag: heroTag,
      );
    }

    final Widget placeholder = SizedBox(
      width: width,
      height: height,
      child: Container(
        color: scheme.surfaceContainerHighest,
        child: Icon(Icons.image_rounded,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
      ),
    );

    final Widget image;
    if (effectiveUrl == null) {
      image = _letterPlaceholder(context);
    } else if (_isFile) {
      final String path = effectiveUrl;
      // SAF 编码路径（content://…␟…）无法被 dart:io 直读，须先 resolveSafUri
      // 落缓存再显示（否则 FileImage 抛 PathNotFoundException 崩溃）。
      if (isDocUri(path) || path.contains('␟')) {
        image = FutureBuilder<String>(
          future: resolveSafUri(path),
          builder: (context, snap) {
            final String? p = snap.data;
            if (snap.hasError || p == null || p.isEmpty) {
              // 解析失败/源为空：显示占位而非崩溃。
              return placeholder;
            }
            return Image.file(
              File(p),
              width: width,
              height: height,
              fit: fit,
              frameBuilder: _frame(placeholder),
              errorBuilder: (c, e, s) => placeholder,
            );
          },
        );
      } else {
        image = Image.file(
          File(path),
          width: width,
          height: height,
          fit: fit,
          frameBuilder: _frame(placeholder),
          errorBuilder: (c, e, s) => placeholder,
        );
      }
    } else {
      // 无源配置的远程图：用 SourceImage 但不传 radius/hero（由外层 AppCoverImage 装饰）。
      image = SourceImage(
        url: effectiveUrl,
        source: null,
        width: width,
        height: height,
        fit: fit,
        placeholder: placeholder,
      );
    }

    final Widget decorated = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        boxShadow: AppShadows.cover(scheme),
        color: scheme.surfaceContainerHighest,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: image,
      ),
    );

    return heroTag != null ? Hero(tag: heroTag!, child: decorated) : decorated;
  }

  /// 封面为空时的占位图：有标题则渲染首字 + 主题色，无标题才退回纯灰图标。
  Widget _letterPlaceholder(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String ch =
        (title != null && title!.trim().isNotEmpty) ? title!.trim()[0] : '';
    if (ch.isEmpty) {
      return SizedBox(
        width: width,
        height: height,
        child: Container(
          color: scheme.surfaceContainerHighest,
          child: Icon(Icons.image_rounded,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
        ),
      );
    }
    // 占位色块全取主题派生色（容器色族 + 主色族），背景/前景成对取，
    // 保证对比度且深浅色自适应，零 Material 默认色板，降低 AI 感。
    final List<(Color, Color)> palette = <(Color, Color)>[
      (scheme.primaryContainer, scheme.onPrimaryContainer),
      (scheme.secondaryContainer, scheme.onSecondaryContainer),
      (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      (scheme.primary, scheme.onPrimary),
      (scheme.tertiary, scheme.onTertiary),
      (scheme.secondary, scheme.onSecondary),
    ];
    final int hash = title!.codeUnits.fold(0, (int a, int b) => a + b);
    final (Color bg, Color fg) = palette[hash % palette.length];
    return SizedBox(
      width: width,
      height: height,
      child: Container(
        color: bg,
        child: Center(
          child: Text(
            ch,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: fg,
                  fontSize: (width ?? 120) * 0.4,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ),
    );
  }

  ImageFrameBuilder _frame(Widget placeholder) =>
      (c, Widget child, int? frame, _) => frame == null ? placeholder : child;
}
