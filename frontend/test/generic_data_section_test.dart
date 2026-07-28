import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/shared/widgets/generic_data_section.dart';

void main() {
  testWidgets('collapsed data section expands from its header', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GenericDataSection(
            title: 'Память',
            rows: <Map<String, Object?>>[
              <String, Object?>{'DeviceLocator': 'DIMM000'},
            ],
            preferredColumns: <String>['DeviceLocator'],
            collapsible: true,
            initiallyExpanded: false,
          ),
        ),
      ),
    );

    expect(find.text('DIMM000'), findsNothing);

    await tester.tap(find.text('Память'));
    await tester.pump();

    expect(find.text('DIMM000'), findsOneWidget);
  });
}
