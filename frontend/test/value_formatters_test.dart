import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/shared/formatters/value_formatters.dart';

void main() {
  test('formats bytes as human readable units', () {
    expect(formatBytes(15709073408), '15 GB');
    expect(formatBytes(3358298472448), '3.1 TB');
    expect(formatBytes(389386240), '371 MB');
  });

  test('formats table byte columns without scientific notation', () {
    expect(formatTableValue('disk', 3358298472448), '3.1 TB');
    expect(formatTableValue('maxmem', 8388608000), '7.8 GB');
  });

  test('formats proxmox task timestamps as local date time', () {
    final date = DateTime(2026, 6, 5, 14, 30, 12);
    final timestamp = date.millisecondsSinceEpoch ~/ 1000;

    expect(formatTableValue('starttime', timestamp), '2026-06-05 14:30:12');
    expect(formatTableValue('endtime', timestamp), '2026-06-05 14:30:12');
    expect(formatTableValue('backup-time', timestamp), '2026-06-05 14:30:12');
  });
}
