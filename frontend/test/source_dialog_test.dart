import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/sources/domain/source.dart';
import 'package:frontend/features/sources/presentation/pages/sources_page.dart';

void main() {
  testWidgets('copy source keeps metadata and clears credentials', (
    tester,
  ) async {
    const source = Source(
      id: 'redfish-1',
      name: 'coder151',
      type: 'redfish',
      baseUrl: 'https://192.168.5.57/',
      status: 'ok',
      hasToken: true,
    );

    await tester.pumpWidget(
      const MaterialApp(home: SourceDialog(source: source, copying: true)),
    );

    expect(find.text('Копировать источник'), findsOneWidget);
    expect(find.text('coder151'), findsOneWidget);
    expect(find.text('https://192.168.5.57/'), findsOneWidget);

    final fields = tester.widgetList<EditableText>(find.byType(EditableText));
    expect(fields.last.controller.text, isEmpty);
  });
}
