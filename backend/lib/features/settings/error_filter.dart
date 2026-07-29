import 'dart:convert';

const defaultIgnoredErrorPatterns = <String>['aptupdate'];

List<String> normalizeIgnoredErrorPatterns(Iterable<Object?> values) => values
    .map((value) => value.toString().trim())
    .where((value) => value.isNotEmpty)
    .toSet()
    .toList(growable: false);

bool matchesIgnoredError(Object? value, List<String> patterns) {
  if (patterns.isEmpty) return false;
  final text = (value is String ? value : jsonEncode(value)).toLowerCase();
  return patterns.any((pattern) => text.contains(pattern.toLowerCase()));
}

Object? filterIgnoredErrors(
  Object? value,
  List<String> patterns, {
  bool rootListContainsErrors = false,
}) {
  if (patterns.isEmpty) return value;
  if (value is List) {
    final rows = rootListContainsErrors
        ? value.where((row) => !matchesIgnoredError(row, patterns))
        : value;
    return rows
        .map((row) => filterIgnoredErrors(row, patterns))
        .toList(growable: false);
  }
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key.toString(): _filterEntry(
          entry.key.toString(),
          entry.value,
          patterns,
        ),
    };
  }
  return value;
}

Object? _filterEntry(String key, Object? value, List<String> patterns) {
  final errorRows = const <String>{'tasks', 'healthissues', 'errors'}
      .contains(key.toLowerCase());
  return filterIgnoredErrors(
    value,
    patterns,
    rootListContainsErrors: errorRows,
  );
}
