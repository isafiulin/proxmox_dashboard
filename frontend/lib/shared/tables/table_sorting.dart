int compareTableValues(Object? left, Object? right) {
  if (left == null && right == null) {
    return 0;
  }
  if (left == null) {
    return 1;
  }
  if (right == null) {
    return -1;
  }

  final leftNumber = num.tryParse(left.toString());
  final rightNumber = num.tryParse(right.toString());
  if (leftNumber != null && rightNumber != null) {
    return leftNumber.compareTo(rightNumber);
  }

  return left.toString().toLowerCase().compareTo(
    right.toString().toLowerCase(),
  );
}

List<Map<String, Object?>> sortTableRows({
  required List<Map<String, Object?>> rows,
  required String column,
  required bool ascending,
}) {
  final sortedRows = List<Map<String, Object?>>.from(rows)
    ..sort((Map<String, Object?> left, Map<String, Object?> right) {
      final comparison = compareTableValues(left[column], right[column]);
      return ascending ? comparison : -comparison;
    });
  return sortedRows;
}
