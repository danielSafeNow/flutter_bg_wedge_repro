import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_bg_wedge_repro/main.dart';

void main() {
  testWidgets('App launches without crashing', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const WedgeReproApp());

    // Verify that the app title appears.
    expect(find.text('BG Wedge Repro'), findsOneWidget);
  });
}