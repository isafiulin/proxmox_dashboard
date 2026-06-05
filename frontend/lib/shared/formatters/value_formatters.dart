String formatPercent(double value) => '${(value * 100).round()}%';

String formatBytes(Object? value) {
  final bytes = double.tryParse(value?.toString() ?? '');
  if (bytes == null || bytes.isNaN || bytes.isInfinite) {
    return '';
  }
  const units = <String>['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var size = bytes.abs();
  var unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex += 1;
  }
  final signed = bytes < 0 ? -size : size;
  final decimals = unitIndex == 0 || signed.abs() >= 10 ? 0 : 1;
  return '${signed.toStringAsFixed(decimals)} ${units[unitIndex]}';
}

String formatSeconds(Object? value) {
  final seconds = int.tryParse(value?.toString() ?? '');
  if (seconds == null) {
    return '';
  }
  final duration = Duration(seconds: seconds);
  final days = duration.inDays;
  final hours = duration.inHours.remainder(24);
  final minutes = duration.inMinutes.remainder(60);
  if (days > 0) {
    return '${days}d ${hours}h';
  }
  if (hours > 0) {
    return '${hours}h ${minutes}m';
  }
  return '${minutes}m';
}

String formatUnixTimestamp(Object? value) {
  final timestamp = num.tryParse(value?.toString() ?? '');
  if (timestamp == null) {
    return '';
  }
  final date = DateTime.fromMillisecondsSinceEpoch((timestamp * 1000).round());
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}:'
      '${date.second.toString().padLeft(2, '0')}';
}

String formatTableValue(String column, Object? value) {
  if (value == null) {
    return '';
  }
  if (_timestampColumns.contains(column)) {
    return formatUnixTimestamp(value);
  }
  if (_byteColumns.contains(column)) {
    return formatBytes(value);
  }
  if (_percentColumns.contains(column)) {
    final parsed = double.tryParse(value.toString());
    return parsed == null ? value.toString() : formatPercent(parsed);
  }
  if (column == 'uptime') {
    return formatSeconds(value);
  }
  if (value is double) {
    return value.toStringAsFixed(value.abs() >= 10 ? 0 : 2);
  }
  return value.toString();
}

const _timestampColumns = <String>{'starttime', 'endtime', 'backup-time'};

const _byteColumns = <String>{
  'disk',
  'maxdisk',
  'diskread',
  'diskwrite',
  'mem',
  'maxmem',
  'netin',
  'netout',
  'size',
  'used',
  'total',
  'avail',
  'free',
};

const _percentColumns = <String>{'cpu', 'used_fraction'};
