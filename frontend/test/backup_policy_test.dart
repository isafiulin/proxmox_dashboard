import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/sources/domain/backup_policy.dart';

void main() {
  test('root job with max depth covers child namespace', () {
    expect(
      backupJobCovers(
        <String, Object?>{'store': 'main', 'ns': '', 'max-depth': 7},
        'main',
        'cluster-a/production',
      ),
      isTrue,
    );
    expect(
      backupJobCovers(
        <String, Object?>{'store': 'main', 'ns': '', 'max-depth': 0},
        'main',
        'cluster-a',
      ),
      isFalse,
    );
  });

  test('policy reports keep last one and missing verify and gc', () {
    final issues = analyzeBackupPolicy(
      sourceId: 'pbs-1',
      sourceName: 'PBS 1',
      namespaces: <Map<String, Object?>>[
        <String, Object?>{'datastore': 'main', 'namespace': 'cluster-a'},
      ],
      datastoreConfig: <Map<String, Object?>>[
        <String, Object?>{'name': 'main'},
      ],
      pruneJobs: <Map<String, Object?>>[
        <String, Object?>{
          'store': 'main',
          'ns': 'cluster-a',
          'keep-last': 1,
          'schedule': 'daily',
        },
      ],
      verifyJobs: const <Map<String, Object?>>[],
      gcJobs: const <Map<String, Object?>>[],
    );

    expect(
      issues.map((issue) => issue.type),
      containsAll(<BackupPolicyIssueType>[
        BackupPolicyIssueType.keepLastOne,
        BackupPolicyIssueType.missingVerify,
        BackupPolicyIssueType.missingGc,
      ]),
    );
  });
}
