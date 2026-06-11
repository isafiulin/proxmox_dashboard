import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/snapshots/domain/resource_history.dart';
import 'package:frontend/shared/widgets/resource_line_chart.dart';

void main() {
  testWidgets('filters chart points by selected time range', (tester) async {
    final now = DateTime(2026, 6, 11, 12);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResourceLineChart(
            title: 'Ноды CPU',
            icon: Icons.speed_outlined,
            now: now,
            points: <ResourceHistoryPoint>[
              ResourceHistoryPoint(
                time: now.subtract(const Duration(days: 6)),
                value: 0.2,
              ),
              ResourceHistoryPoint(
                time: now.subtract(const Duration(days: 3)),
                value: 0.4,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('20%'), findsNothing);
    expect(find.text('40%'), findsOneWidget);

    await tester.tap(find.text('Сегодня'));
    await tester.pumpAndSettle();

    expect(find.text('-'), findsOneWidget);
    expect(find.text('За выбранный период нет истории.'), findsOneWidget);
  });
}
