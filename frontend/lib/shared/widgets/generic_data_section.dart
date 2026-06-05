import 'package:flutter/material.dart';
import 'package:frontend/shared/formatters/value_formatters.dart';
import 'package:frontend/shared/tables/table_sorting.dart';
import 'package:frontend/shared/widgets/app_card.dart';
import 'package:frontend/shared/widgets/empty_state.dart';

class GenericDataSection extends StatefulWidget {
  const GenericDataSection({
    required this.title,
    required this.rows,
    required this.preferredColumns,
    super.key,
  });

  final String title;
  final List<Map<String, Object?>> rows;
  final List<String> preferredColumns;

  @override
  State<GenericDataSection> createState() => _GenericDataSectionState();
}

class _GenericDataSectionState extends State<GenericDataSection> {
  int? _sortColumnIndex;
  bool _sortAscending = true;

  @override
  Widget build(BuildContext context) {
    final List<String> columns = widget.preferredColumns
        .where(
          (String column) => widget.rows.any(
            (Map<String, Object?> row) => row.containsKey(column),
          ),
        )
        .toList();
    final sortIndex = _sortColumnIndex;
    final visibleRows = sortIndex == null || sortIndex >= columns.length
        ? List<Map<String, Object?>>.from(widget.rows)
        : sortTableRows(
            rows: widget.rows,
            column: columns[sortIndex],
            ascending: _sortAscending,
          );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (widget.rows.isEmpty || columns.isEmpty)
            const EmptyState(
              icon: Icons.table_rows_outlined,
              text: 'Данных пока нет.',
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                sortColumnIndex: _sortColumnIndex,
                sortAscending: _sortAscending,
                columns: columns.indexed
                    .map(
                      ((int, String) entry) => DataColumn(
                        label: Text(entry.$2),
                        onSort: (int columnIndex, bool ascending) {
                          setState(() {
                            _sortColumnIndex = columnIndex;
                            _sortAscending = ascending;
                          });
                        },
                      ),
                    )
                    .toList(),
                rows: visibleRows.take(100).map((Map<String, Object?> row) {
                  return DataRow(
                    cells: columns
                        .map(
                          (String column) => DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 220),
                              child: Text(
                                formatTableValue(column, row[column]),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
