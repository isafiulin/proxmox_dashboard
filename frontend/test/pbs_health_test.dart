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
}
