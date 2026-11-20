/// 书源验证码输入弹窗（java.getVerificationCode 对等）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';

class ShuyuanVerificationCodeScreen extends StatefulWidget {
  const ShuyuanVerificationCodeScreen({
    super.key,
    required this.imageUrl,
    this.title,
    this.imageHeaders = const <String, String>{},
    this.imageBuilder,
  });

  final String imageUrl;
  final String? title;
  final Map<String, String> imageHeaders;
  final Widget Function(BuildContext context, String imageUrl)? imageBuilder;

  /// 打开验证码输入弹窗；取消返回 null，确认返回 trim 后的文本。
  static Future<String?> show(
    BuildContext context, {
    required String imageUrl,
    String? title,
    Map<String, String> imageHeaders = const <String, String>{},
    Widget Function(BuildContext context, String imageUrl)? imageBuilder,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => ShuyuanVerificationCodeScreen(
        imageUrl: imageUrl,
        title: title,
        imageHeaders: imageHeaders,
        imageBuilder: imageBuilder,
      ),
    );
  }

  /// data:image/...;base64 解码；非 data 图片返回 null。
  static Uint8List? decodeDataImage(String url) {
    if (!url.startsWith('data:')) return null;
    final comma = url.indexOf(',');
    if (comma <= 5) return null;
    final meta = url.substring(5, comma).toLowerCase();
    if (!meta.startsWith('image/')) return null;
    if (!meta.endsWith(';base64')) return null;
    try {
      return base64Decode(url.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  @override
  State<ShuyuanVerificationCodeScreen> createState() =>
      _ShuyuanVerificationCodeScreenState();
}

class _ShuyuanVerificationCodeScreenState
    extends State<ShuyuanVerificationCodeScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final builder = widget.imageBuilder;
    final bytes =
        ShuyuanVerificationCodeScreen.decodeDataImage(widget.imageUrl);
    final Widget image = builder != null
        ? builder(context, widget.imageUrl)
        : bytes != null
            ? Image.memory(bytes, height: 120, fit: BoxFit.contain)
            : Image.network(
                widget.imageUrl,
                headers: widget.imageHeaders,
                height: 120,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.broken_image_outlined),
              );
    return AlertDialog(
      title: Text(widget.title ?? l10n.verificationCodeTitle),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            image,
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.verificationCodeHint,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }

  void _submit() {
    Navigator.of(context).pop<String>(_controller.text.trim());
  }
}
