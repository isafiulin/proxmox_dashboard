import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/dashboard/domain/health_models.dart';

void main() {
  test('builds node health summary', () {
    final report = buildNodeHealthReport(<Map<String, Object?>>[
      <String, Object?>{
        'node': 'n1',
        'status': 'online',
        'cpu': 0.9,
        'mem': 90,
        'maxmem': 100,
      },
      <String, Object?>{
        'node': 'n2',
        'status': 'offline',
        'cpu': 0.1,
        'mem': 10,
        'maxmem': 100,
      },
    ]);

    expect(report.total, 2);
    expect(report.online, 1);
    expect(report.offline, 1);
    expect(report.highCpu, 1);
    expect(report.highRam, 1);
  });

  test('builds vm health summary with backup issues', () {
    final report = buildVmHealthReport(
      guests: <Map<String, Object?>>[
        <String, Object?>{
          'type': 'qemu',
          'vmid': '101',
          'status': 'running',
          'cpu': 0.2,
          'mem': 50,
          'maxmem': 100,
        },
        <String, Object?>{
          'type': 'lxc',
          'vmid': '202',
          'status': 'stopped',
          'cpu': 0.85,
          'mem': 90,
          'maxmem': 100,
        },
      ],
      snapshots: <Map<String, Object?>>[
        <String, Object?>{
          'backup-type': 'vm',
          'backup-id': '101',
          'backup-time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
      ],
    );

    expect(report.total, 2);
    expect(report.running, 1);
    expect(report.stopped, 1);
    expect(report.highCpu, 1);
    expect(report.highRam, 1);
    expect(report.backupIssues, 1);
  });
}
