import 'package:flutter/material.dart';

typedef RowBuilder<T> = DataRow Function(BuildContext context, T item);
typedef SortComparator<T> = int Function(T left, T right);

class SortableDataColumn<T> {
  const SortableDataColumn({
    required this.label,
    required this.compare,
    this.numeric = false,
  });

  final String label;
  final SortComparator<T> compare;
  final bool numeric;
}

class SortableDataTable<T> extends StatefulWidget {
  const SortableDataTable({
    required this.columns,
    required this.items,
    required this.rowBuilder,
    this.initialSortColumnIndex = 0,
    this.initialSortAscending = true,
    this.showCheckboxColumn = true,
    super.key,
  });

  final List<SortableDataColumn<T>> columns;
  final List<T> items;
  final RowBuilder<T> rowBuilder;
  final int initialSortColumnIndex;
  final bool initialSortAscending;
  final bool showCheckboxColumn;

  @override
  State<SortableDataTable<T>> createState() => _SortableDataTableState<T>();
}

class _SortableDataTableState<T> extends State<SortableDataTable<T>> {
  late int _sortColumnIndex;
  late bool _sortAscending;

  @override
  void initState() {
    super.initState();
    _sortColumnIndex = widget.initialSortColumnIndex;
    _sortAscending = widget.initialSortAscending;
  }

  @override
  void didUpdateWidget(covariant SortableDataTable<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_sortColumnIndex >= widget.columns.length) {
      _sortColumnIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sortedItems = List<T>.from(widget.items);
    if (widget.columns.isNotEmpty) {
      final comparator = widget.columns[_sortColumnIndex].compare;
      sortedItems.sort((T left, T right) {
        final result = comparator(left, right);
        return _sortAscending ? result : -result;
      });
    }

    return DataTable(
      showCheckboxColumn: widget.showCheckboxColumn,
      sortColumnIndex: widget.columns.isEmpty ? null : _sortColumnIndex,
      sortAscending: _sortAscending,
      columns: widget.columns.indexed.map(((int, SortableDataColumn<T>) entry) {
        return DataColumn(
          label: Text(entry.$2.label),
          numeric: entry.$2.numeric,
          onSort: (int columnIndex, bool ascending) {
            setState(() {
              _sortColumnIndex = columnIndex;
              _sortAscending = ascending;
            });
          },
        );
      }).toList(),
      rows: sortedItems
          .map((T item) => widget.rowBuilder(context, item))
          .toList(),
    );
  }
}

int compareNullableDateTime(DateTime? left, DateTime? right) {
  if (left == null && right == null) {
    return 0;
  }
  if (left == null) {
    return 1;
  }
  if (right == null) {
    return -1;
  }
  return left.compareTo(right);
}

int compareText(String left, String right) {
  return left.toLowerCase().compareTo(right.toLowerCase());
}
