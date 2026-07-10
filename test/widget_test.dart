import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synologynotesenhanceds_enhanced/app.dart';

void main() {
  testWidgets('App smoke test — login screen renders', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: SynologyNoteApp()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Synology Notes Enhanced'), findsWidgets);
  });
}
