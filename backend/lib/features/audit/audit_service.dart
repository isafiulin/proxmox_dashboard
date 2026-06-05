import 'package:neotelecom_backend/core/security/security.dart';

class AuditService {
  AuditService(this.events);

  final List<Map<String, Object?>> events;

  void record(
    String action, {
    required String actorUserId,
    required String targetId,
    Map<String, Object?> details = const {},
  }) {
    events.add({
      'id': randomToken(),
      'action': action,
      'actorUserId': actorUserId,
      'targetId': targetId,
      'details': details,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  List<Map<String, Object?>> latest({int limit = 100}) =>
      events.reversed.take(limit).toList();
}
