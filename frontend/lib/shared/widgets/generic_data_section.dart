import 'package:flutter/material.dart';
import 'package:frontend/shared/formatters/value_formatters.dart';
import 'package:frontend/shared/tables/table_sorting.dart';
import 'package:frontend/shared/widgets/app_card.dart';
import 'package:frontend/shared/widgets/empty_state.dart';
import 'package:go_router/go_router.dart';

class GenericDataSection extends StatefulWidget {
  const GenericDataSection({
    required this.title,
    required this.rows,
    required this.preferredColumns,
    this.collapsible = false,
    this.initiallyExpanded = true,
    super.key,
  });

  final String title;
  final List<Map<String, Object?>> rows;
  final List<String> preferredColumns;
  final bool collapsible;
  final bool initiallyExpanded;

  @override
  State<GenericDataSection> createState() => _GenericDataSectionState();
}

class _GenericDataSectionState extends State<GenericDataSection> {
  int? _sortColumnIndex;
  bool _sortAscending = true;
  late bool _expanded = widget.initiallyExpanded;

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
          InkWell(
            onTap: widget.collapsible
                ? () => setState(() => _expanded = !_expanded)
                : null,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${widget.rows.length}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (widget.collapsible) ...<Widget>[
                  const SizedBox(width: 8),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ],
            ),
          ),
          if (_expanded) ...<Widget>[
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
                    final path = _drillDownPath(row);
                    return DataRow(
                      onSelectChanged: path == null
                          ? null
                          : (_) => context.go(path),
                      cells: columns
                          .map(
                            (String column) => DataCell(
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 220,
                                ),
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
        ],
      ),
    );
  }
}

String? _drillDownPath(Map<String, Object?> row) {
  final sourceId =
      row['sourceId']?.toString() ?? row['backupSourceId']?.toString() ?? '';
  if (sourceId.isEmpty) {
    return null;
  }
  final node = row['node']?.toString() ?? '';
  final type = row['type']?.toString() ?? '';
  final vmid = row['vmid']?.toString() ?? '';
  if (node.isNotEmpty && vmid.isNotEmpty && (type == 'qemu' || type == 'lxc')) {
    final name = row['name']?.toString() ?? '';
    final query = name.isEmpty ? '' : '?name=${Uri.encodeQueryComponent(name)}';
    return '/sources/$sourceId/guests/$type/'
        '${Uri.encodeComponent(node)}/$vmid$query';
  }
  if (node.isNotEmpty && node != 'PBS') {
    return '/sources/$sourceId/nodes/${Uri.encodeComponent(node)}';
  }
  return '/sources/$sourceId';
}
