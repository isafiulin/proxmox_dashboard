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
    expect(message, contains('… и ещё 2'));
    expect(message, isNot(contains('Sensor 6')));
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
