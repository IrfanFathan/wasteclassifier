import 'package:flutter_test/flutter_test.dart';
import 'package:wasteclassifier/main.dart';

void main() {
  testWidgets('App startup smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const WasteClassifierApp());
    expect(find.byType(WasteClassifierApp), findsOneWidget);
  });
}
