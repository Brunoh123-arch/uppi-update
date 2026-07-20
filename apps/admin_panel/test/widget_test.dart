import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel/app.dart';

void main() {
  testWidgets('AdminPanelApp renders Supabase error screen when uninitialized', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const AdminPanelApp());

    // Verify that our Supabase error screen starts with the initialization failure message.
    expect(find.text('Falha de Inicialização'), findsOneWidget);
    expect(find.byIcon(Icons.report_problem_rounded), findsOneWidget);
  });
}
