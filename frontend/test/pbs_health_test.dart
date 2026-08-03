import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/sources/domain/pbs_health.dart';

void main() {
  test('different datastore or namespace is a different backup location', () {
    final first = pbsBackupLocation(<String, Object?>{
      'backupSourceId': 'pbs-1',
      'datastore': 'main',
      'namespace': 'cluster-a',
    });
    final secondDatastore = pbsBackupLocation(<String, Object?>{
      'backupSourceId': 'pbs-1',
      'datastore': 'reserve',
      'namespace': 'cluster-a',
    });
    final secondNamespace = pbsBackupLocation(<String, Object?>{
      'backupSourceId': 'pbs-1',
      'datastore': 'main',
      'namespace': 'cluster-b',
    });

    expect(<String>{first, secondDatastore, secondNamespace}, hasLength(3));
  });

  test('only locations with the newest backup date are current', () {
    final current = DateTime.utc(2026, 8, 3, 1);
    final freshness = analyzePbsBackupLocationFreshness(<Map<String, Object?>>[
      <String, Object?>{
        'backupSourceId': 'pbs-1',
        'datastore': 'main',
        'backup-time': current.millisecondsSinceEpoch ~/ 1000,
      },
      <String, Object?>{
        'backupSourceId': 'pbs-2',
        'datastore': 'reserve',
        'backup-time':
            current.subtract(const Duration(days: 1)).millisecondsSinceEpoch ~/
            1000,
      },
    ]);

    expect(freshness.latestByLocation, hasLength(2));
    expect(freshness.currentLocationCount, 1);
    expect(freshness.latestBackupAt, current);
  });

  test('two locations on the same backup date are current', () {
    final current = DateTime.utc(2026, 8, 3, 16);
    final freshness = analyzePbsBackupLocationFreshness(<Map<String, Object?>>[
      <String, Object?>{
        'backupSourceId': 'pbs-1',
        'datastore': 'main',
        'backup-time': current.millisecondsSinceEpoch ~/ 1000,
      },
      <String, Object?>{
        'backupSourceId': 'pbs-2',
        'datastore': 'reserve',
        'backup-time':
            current
                .subtract(const Duration(hours: 12))
                .millisecondsSinceEpoch ~/
            1000,
      },
    ]);

    expect(freshness.currentLocationCount, 2);
  });

  test('verify state reads PBS verification object and failure reason', () {
    final items = buildPbsVerifyItems(<Map<String, Object?>>[
      <String, Object?>{
        'backupSource': 'pbs-main',
        'datastore': 'store-a',
        'namespace': 'cluster-a',
        'backup-type': 'vm',
        'backup-id': '100',
        'backup-time': 1700000000,
        'verification': <String, Object?>{
          'state': 'failed',
          'message': 'checksum mismatch',
        },
      },
    ]);

    expect(items.single.state, 'critical');
    expect(items.single.reason, 'checksum mismatch');
    expect(items.single.backupGroup, 'vm/100');
  });

  test('overview alarm ignores stale tasks and reader connection resets', () {
    final now = DateTime.utc(2026, 7, 28, 12);

    expect(
      isPbsTaskAlarm(<String, Object?>{
        'worker_type': 'reader',
        'status': 'connection error: connection reset',
        'endtime':
            now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch ~/
            1000,
      }, now: now),
      isFalse,
    );
    expect(
      isPbsTaskAlarm(<String, Object?>{
        'worker_type': 'verify',
        'status': 'checksum mismatch',
        'endtime':
            now.subtract(const Duration(days: 2)).millisecondsSinceEpoch ~/
            1000,
      }, now: now),
      isFalse,
    );
    expect(
      isPbsTaskAlarm(<String, Object?>{
        'worker_type': 'verify',
        'status': 'checksum mismatch',
        'endtime':
            now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch ~/
            1000,
      }, now: now),
      isTrue,
    );
  });
}
