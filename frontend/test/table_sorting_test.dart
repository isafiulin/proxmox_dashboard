import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/shared/tables/table_sorting.dart';

void main() {
  test('sorts numeric table values as numbers', () {
    final rows = <Map<String, Object?>>[
      <String, Object?>{'vmid': '140'},
      <String, Object?>{'vmid': 2},
      <String, Object?>{'vmid': '11'},
    ];

    final sorted = sortTableRows(rows: rows, column: 'vmid', ascending: true);

    expect(sorted.map((Map<String, Object?> row) => row['vmid']), <Object?>[
      2,
      '11',
      '140',
    ]);
  });

  test('sorts text table values case-insensitively', () {
    final rows = <Map<String, Object?>>[
      <String, Object?>{'name': 'saturn'},
      <String, Object?>{'name': 'Jupiter'},
      <String, Object?>{'name': 'mercury'},
    ];

    final sorted = sortTableRows(rows: rows, column: 'name', ascending: true);

    expect(sorted.map((Map<String, Object?> row) => row['name']), <Object?>[
      'Jupiter',
      'mercury',
      'saturn',
    ]);
  });
}
