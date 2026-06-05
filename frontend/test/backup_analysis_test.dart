import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/sources/domain/backup_analysis.dart';

void main() {
  test(
    'matches qemu guest with vm backup snapshots and computes age status',
    () {
      final now = DateTime.utc(2026, 6, 4, 12);
      final summary = analyzeGuestBackups(
        guestType: 'qemu',
        vmid: '101',
        now: now,
        snapshots: <Map<String, Object?>>[
          <String, Object?>{
            'backup-type': 'vm',
            'backup-id': '101',
            'backup-time': now
                .subtract(const Duration(hours: 12))
                .secondsSinceEpoch,
          },
          <String, Object?>{
            'backup-type': 'ct',
            'backup-id': '101',
            'backup-time': now
                .subtract(const Duration(hours: 1))
                .secondsSinceEpoch,
          },
        ],
      );

      expect(summary.matches, hasLength(1));
      expect(summary.status, BackupAgeStatus.ok);
    },
  );

  test('returns missing when guest has no backup snapshots', () {
    final summary = analyzeGuestBackups(
      guestType: 'lxc',
      vmid: '202',
      snapshots: const <Map<String, Object?>>[],
    );

    expect(summary.status, BackupAgeStatus.missing);
  });

  test('builds backup coverage report by guest and day', () {
    final first = DateTime.utc(2026, 6, 4, 1);
    final second = DateTime.utc(2026, 6, 5, 1);

    final report = analyzeBackupCoverage(<Map<String, Object?>>[
      <String, Object?>{
        'datastore': 'pbs-main',
        'backup-type': 'vm',
        'backup-id': '101',
        'backup-time': first.secondsSinceEpoch,
        'size': 1024,
      },
      <String, Object?>{
        'datastore': 'pbs-main',
        'backup-type': 'vm',
        'backup-id': '101',
        'backup-time': second.secondsSinceEpoch,
        'size': 2048,
      },
      <String, Object?>{
        'datastore': 'pbs-fast',
        'backup-type': 'ct',
        'backup-id': '202',
        'backup-time': second.secondsSinceEpoch,
        'size': 4096,
      },
    ]);

    expect(report.totalSnapshots, 3);
    expect(report.protectedGuests, 2);
    expect(report.totalSizeBytes, 7168);
    expect(report.dailyCounts.map((day) => day.count), <int>[1, 2]);
    final vmReport = report.guests.singleWhere(
      (guest) => guest.displayName == 'vm/101',
    );
    expect(vmReport.count, 2);
    expect(vmReport.latestBackupAt, second);
    expect(vmReport.averageInterval, const Duration(days: 1));
  });

  test('builds backup schedule report from snapshots', () {
    final now = DateTime(2026, 6, 7, 12);
    final first = DateTime.utc(2026, 6, 5, 2);
    final second = DateTime.utc(2026, 6, 6, 2);
    final third = DateTime.utc(2026, 6, 7, 3);

    final report = analyzeBackupSchedule(
      <Map<String, Object?>>[
        <String, Object?>{
          'backup-type': 'vm',
          'backup-id': '101',
          'backup-time': first.secondsSinceEpoch,
          'datastore': 'pbs-main',
          'backupSource': 'PBS-1',
        },
        <String, Object?>{
          'backup-type': 'vm',
          'backup-id': '101',
          'backup-time': first.secondsSinceEpoch,
          'datastore': 'pbs-reserve',
          'backupSource': 'PBS-1',
        },
        <String, Object?>{
          'backup-type': 'vm',
          'backup-id': '101',
          'backup-time': second.secondsSinceEpoch,
          'datastore': 'pbs-main',
        },
        <String, Object?>{
          'backup-type': 'ct',
          'backup-id': '202',
          'backup-time': third.secondsSinceEpoch,
          'datastore': 'pbs-fast',
        },
      ],
      now: now,
      days: 3,
    );

    expect(report.totalSnapshots, 4);
    expect(report.calendarDays.map((day) => day.count), <int>[1, 1, 1]);
    expect(report.calendarEntries.map((entry) => entry.displayName), <String>[
      'vm/101',
      'vm/101',
      'ct/202',
    ]);
    expect(report.calendarEntries.first.datastore, 'pbs-main, pbs-reserve');
    expect(report.calendarEntries.first.backupSource, 'PBS-1');
    final vmSchedule = report.items.singleWhere(
      (item) => item.displayName == 'vm/101',
    );
    expect(vmSchedule.count, 2);
    expect(vmSchedule.typicalHour, first.toLocal().hour);
    expect(vmSchedule.averageInterval, const Duration(days: 1));
    expect(vmSchedule.datastores, <String>{'pbs-main', 'pbs-reserve'});
  });
}

extension on DateTime {
  int get secondsSinceEpoch => millisecondsSinceEpoch ~/ 1000;
}
