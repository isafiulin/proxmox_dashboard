import 'package:neotelecom_backend/features/collection/data_snapshot.dart';
import 'package:neotelecom_backend/features/notifications/notification_service.dart';
import 'package:neotelecom_backend/features/settings/error_filter.dart';
import 'package:test/test.dart';

void main() {
  test('filters matching task rows without removing unrelated failures', () {
    final payload = <String, Object?>{
      'tasks': <Map<String, Object?>>[
        <String, Object?>{
          'type': 'aptupdate',
          'status': "command 'apt-get update' failed: exit code 100",
        },
        <String, Object?>{'type': 'vzdump', 'status': 'disk full'},
      ],
      'resources': <Map<String, Object?>>[
        <String, Object?>{'name': 'aptupdate-worker'},
      ],
    };

    final filtered = filterIgnoredErrors(payload, <String>['APTUPDATE']) as Map;

    expect(filtered['tasks'], hasLength(1));
    expect((filtered['tasks'] as List).single['type'], 'vzdump');
    expect(filtered['resources'], hasLength(1));
  });

  test('ignored task creates neither Telegram alarm nor recovery', () {
    DataSnapshot snapshot() => DataSnapshot.create(
          sourceId: 'pve-1',
          sourceType: 'proxmox_ve',
          status: 'ok',
          payload: <String, Object?>{
            'tasks': <Map<String, Object?>>[
              <String, Object?>{
                'upid': 'apt-1',
                'type': 'aptupdate',
                'status': "command 'apt-get update' failed: exit code 100",
                'endtime': DateTime.now().millisecondsSinceEpoch ~/ 1000,
              },
            ],
          },
        );

    final first = incidentChange(
      null,
      snapshot(),
      minimumSeverity: 'warning',
      ignoredErrorPatterns: <String>['aptupdate'],
    );
    final next = incidentChange(
      snapshot(),
      DataSnapshot.create(
        sourceId: 'pve-1',
        sourceType: 'proxmox_ve',
        status: 'ok',
        payload: <String, Object?>{},
      ),
      minimumSeverity: 'warning',
      ignoredErrorPatterns: <String>['aptupdate'],
    );

    expect(first.started, isEmpty);
    expect(next.resolved, isEmpty);
  });
}
