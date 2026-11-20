/// 验证码弹窗：输入回传、取消 null、data: 图片解码。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:nexhub/features/shuyuan/presentation/shuyuan_verification_code_screen.dart';

void main() {
  testWidgets('输入验证码并确认返回文本', (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                result = await ShuyuanVerificationCodeScreen.show(
                  context,
                  imageUrl: 'https://img.test/c.png',
                  imageBuilder: (_, __) => const SizedBox(width: 120, height: 40),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField), ' A1B2 ');
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();
    expect(result, 'A1B2');
  });

  testWidgets('取消返回 null', (tester) async {
    String? result = 'sentinel';
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                result = await ShuyuanVerificationCodeScreen.show(
                  context,
                  imageUrl: 'https://img.test/c.png',
                  imageBuilder: (_, __) => const SizedBox(width: 120, height: 40),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  test('data:image base64 解码；非 data 返回 null', () {
    expect(
      ShuyuanVerificationCodeScreen.decodeDataImage(
          'data:image/png;base64,AAAA'),
      <int>[0, 0, 0],
    );
    expect(
      ShuyuanVerificationCodeScreen.decodeDataImage('https://x.test/a.png'),
      isNull,
    );
  });
}
