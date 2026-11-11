import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synologynotesenhanceds_enhanced/app.dart';

/// Lets the launch splash overlay (900ms hold + fade) clear before tapping.
Future<void> _pastSplash(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
}

/// Renders the login screen at real phone sizes (logical pts + safe-area
/// insets) and checks nothing overflows and every sign-in control fits on
/// screen without scrolling — including with the optional remote-address and
/// 2FA fields expanded.
void main() {
  const phones = {
    'iPhone 16 Plus': (Size(430, 932), EdgeInsets.only(top: 59, bottom: 34)),
    'iPhone SE': (Size(375, 667), EdgeInsets.only(top: 20)),
  };

  for (final entry in phones.entries) {
    final (size, insets) = entry.value;
    for (final scale in [1.0, 1.3]) {
      testWidgets('${entry.key} @${scale}x text: fits without scrolling',
          (tester) async {
        tester.view
          ..physicalSize = size * 3
          ..devicePixelRatio = 3
          ..padding = FakeViewPadding(
              top: insets.top * 3, bottom: insets.bottom * 3)
          ..platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.reset();
          tester.platformDispatcher.clearAllTestValues();
        });

        await tester.pumpWidget(const ProviderScope(child: SynologyNoteApp()));
        await _pastSplash(tester);

        // Expand everything optional.
        await tester.tap(find.text('Remote address'));
        await tester.tap(find.text('Two-factor'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull); // no RenderFlex overflow
        expect(find.widgetWithText(TextFormField, 'Remote Address'),
            findsOneWidget);

        final screen = Offset.zero & size;
        for (final label in [
          'NAS Address', 'Port', 'Remote Address', 'Username', 'Password',
          'Authenticator Code',
        ]) {
          final rect = tester.getRect(find.widgetWithText(TextFormField, label));
          expect(screen.contains(rect.topLeft) && screen.contains(rect.bottomRight),
              isTrue, reason: '$label offscreen: $rect');
        }
        final connect = tester.getRect(find.text('Connect'));
        expect(connect.bottom <= size.height - insets.bottom, isTrue,
            reason: 'Connect button offscreen: $connect');
        if (entry.key == 'iPhone 16 Plus') {
          final offline = tester.getRect(find.text('Continue Offline'));
          expect(offline.bottom <= size.height - insets.bottom, isTrue,
              reason: 'Offline button offscreen: $offline');
          // Uses the full width on a phone (no sliver of overlay at the side).
          final field =
              tester.getRect(find.widgetWithText(TextFormField, 'Username'));
          expect(field.width, greaterThan(size.width - 60));
        }
      }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
    }
  }

  testWidgets('remote address field is hidden until toggled on',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SynologyNoteApp()));
    await _pastSplash(tester);
    expect(find.widgetWithText(TextFormField, 'Remote Address'), findsNothing);
    await tester.tap(find.text('Remote address'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Remote Address'), findsOneWidget);
  });
}
