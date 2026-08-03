import 'package:neotelecom_backend/core/security/credentials_cipher.dart';
import 'package:neotelecom_backend/features/collection/data_snapshot.dart';
import 'package:neotelecom_backend/features/notifications/notification_service.dart';
import 'package:neotelecom_backend/features/sources/source.dart';
import 'package:test/test.dart';

void main() {
  test('only reports new incidents, escalation, and recovery', () {
    final warning = _snapshot(<Map<String, Object?>>[
      _issue('fan', '1', 'Fan 1', 'Warning'),
    ]);
    final unchanged = incidentChange(
      warning,
      _snapshot(<Map<String, Object?>>[
        _issue('fan', '1', 'Fan 1', 'Warning'),
      ]),
      minimumSeverity: 'warning',
    );
    expect(unchanged.started, isEmpty);
    expect(unchanged.resolved, isEmpty);

    final escalated = incidentChange(
      warning,
      _snapshot(<Map<String, Object?>>[
        _issue('fan', '1', 'Fan 1', 'Critical'),
      ]),
      minimumSeverity: 'warning',
    );
    expect(escalated.started.single.severity, 'critical');

    final recovered = incidentChange(
      warning,
      _snapshot(const <Map<String, Object?>>[]),
      minimumSeverity: 'warning',
    );
    expect(recovered.resolved.single.label, 'Fan 1');

    final unavailable = incidentChange(
      warning,
      DataSnapshot.create(
        sourceId: 'source-1',
        sourceType: 'ipmi',
        status: 'critical',
        payload: <String, Object?>{'error': 'timeout'},
      ),
      minimumSeverity: 'warning',
    );
    expect(unavailable.started.single.key, 'collection');
    expect(unavailable.resolved, isEmpty);
  });

  test('message is compact and escapes Telegram HTML', () {
    final current = _snapshot(
      List<Map<String, Object?>>.generate(
        7,
        (index) => _issue(
          'sensor',
          '$index',
          index == 0 ? 'Temp <CPU>' : 'Sensor $index',
          index == 0 ? 'Critical' : 'Warning',
        ),
      ),
    );
    final message = buildTelegramIncidentMessage(
      source: Source.create(
        name: 'BMC & rack',
        type: 'ipmi',
        baseUrl: 'ipmi://192.0.2.1',
        credential: const EncryptedSecret.empty(),
      ),
      collectedAt: DateTime.utc(2026, 7, 28, 20, 15),
      change: incidentChange(null, current, minimumSeverity: 'warning'),
      includeRecovery: true,
    );

    expect(message, contains('BMC &amp; rack'));
    expect(message, contains('Temp &lt;CPU&gt;'));
    expect(message, contains('Время: 29.07.2026 02:15'));
    expect(message, contains('… и ещё 2'));
    expect(message, isNot(contains('Sensor 6')));
  });

  test('reports PVE resource, task, and backup incidents without repeats', () {
    final now = DateTime.utc(2026, 7, 29, 10);
    final current = DataSnapshot.create(
      sourceId: 'pve-1',
      sourceType: 'proxmox_ve',
      status: 'ok',
      payload: <String, Object?>{
        'resources': <Map<String, Object?>>[
          <String, Object?>{
            'type': 'node',
            'id': 'node/pve1',
            'name': 'pve1',
            'status': 'offline',
          },
          <String, Object?>{
            'type': 'qemu',
            'id': 'qemu/101',
            'vmid': 101,
            'name': 'database',
            'status': 'running',
            'cpu': 0.95,
            'mem': 50,
            'maxmem': 100,
          },
        ],
        'tasks': <Map<String, Object?>>[
          <String, Object?>{
            'upid': 'failed-task-1',
            'type': 'vzdump',
            'id': '101',
            'status': 'TASK ERROR: disk full',
            'endtime':
                now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch ~/
                    1000,
          },
        ],
      },
    );
    final backup = <String, Object?>{
      'backup-type': 'vm',
      'backup-id': 101,
      'namespace': '',
      'backup-time':
          now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000,
    };

    final first = incidentChange(
      null,
      current,
      minimumSeverity: 'warning',
      backupSnapshots: <Map<String, Object?>>[backup],
      now: now,
    );
    expect(
        first.started.map((item) => item.key),
        containsAll(<String>[
          'node:node/pve1:offline',
          'qemu:qemu/101:cpu',
          'task:failed-task-1',
        ]));
    expect(first.started.map((item) => item.key),
        isNot(contains('backup:qemu:101')));

    final unchanged = incidentChange(
      current,
      current,
      minimumSeverity: 'warning',
      backupSnapshots: <Map<String, Object?>>[backup],
      now: now,
    );
    expect(unchanged.started, isEmpty);
  });

  test('reports missing backup and PBS datastore/task failures', () {
    final now = DateTime.utc(2026, 7, 29, 10);
    final pve = DataSnapshot.create(
      sourceId: 'pve-1',
      sourceType: 'proxmox_ve',
      status: 'ok',
      payload: <String, Object?>{
        'resources': <Map<String, Object?>>[
          <String, Object?>{
            'type': 'lxc',
            'id': 'lxc/202',
            'vmid': 202,
            'name': 'dns',
            'status': 'running',
          },
        ],
      },
    );
    final pveChange = incidentChange(
      null,
      pve,
      minimumSeverity: 'warning',
      now: now,
    );
    expect(pveChange.started.single.key, 'backup:lxc:202');

    final pbs = DataSnapshot.create(
      sourceId: 'pbs-1',
      sourceType: 'proxmox_backup',
      status: 'ok',
      payload: <String, Object?>{
        'health': <String, Object?>{
          'datastores': <Map<String, Object?>>[
            <String, Object?>{'store': 'backup', 'used': 95, 'total': 100},
          ],
        },
        'tasks': <Map<String, Object?>>[
          <String, Object?>{
            'upid': 'sync-failed',
            'worker_type': 'syncjob',
            'worker_id': 'pbs2:backup',
            'status': 'sync failed',
            'endtime': now
                    .subtract(const Duration(minutes: 5))
                    .millisecondsSinceEpoch ~/
                1000,
          },
        ],
      },
    );
    final pbsChange = incidentChange(
      null,
      pbs,
      minimumSeverity: 'warning',
      now: now,
    );
    expect(
        pbsChange.started.map((item) => item.key),
        containsAll(<String>[
          'datastore:backup:disk',
          'task:sync-failed',
        ]));
  });
}

DataSnapshot _snapshot(List<Map<String, Object?>> issues) =>
    DataSnapshot.create(
      sourceId: 'source-1',
      sourceType: 'ipmi',
      status: 'ok',
      payload: <String, Object?>{'healthIssues': issues},
    );

Map<String, Object?> _issue(
  String type,
  String id,
  String name,
  String health,
) =>
    <String, Object?>{
      'resourceType': type,
      'resourceId': id,
      'name': name,
      'health': health,
    };
