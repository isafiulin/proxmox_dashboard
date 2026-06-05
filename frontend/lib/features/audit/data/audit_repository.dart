import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/features/audit/domain/audit_event.dart';

class AuditRepository {
  AuditRepository(this._api);

  final ApiClient _api;

  Future<List<AuditEvent>> latest() async {
    final Map<String, Object?> json = await _api.get('/audit-events');
    return ((json['items'] as List?) ?? <Object?>[])
        .map(
          (Object? item) => AuditEvent.fromJson(item! as Map<String, Object?>),
        )
        .toList();
  }
}
