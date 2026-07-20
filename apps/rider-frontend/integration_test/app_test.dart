import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rider_flutter/main.dart' as app;
import 'package:rider_flutter/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Uppi E2E Application Boot Test', () {
    testWidgets('Verify App Launches and Renders Splash/Main Tree', (WidgetTester tester) async {
      // 1. Boot the application from its main entry point
      app.main();

      // 2. Pump the widget tree and wait for the application to boot
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // 3. Verify that the main MyApp widget is in the widget tree
      expect(find.byType(MyApp), findsOneWidget);
      
      print('E2E validation successful: Uppi launched successfully.');
    });
  });
}
