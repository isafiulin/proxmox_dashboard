import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';

void main() {
  testWidgets('renders splash while authentication is being restored', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const NeoTelecomApp());
    await tester.pump();

    expect(find.text('NeoTelecom'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}
