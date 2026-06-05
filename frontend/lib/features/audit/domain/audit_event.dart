import 'package:equatable/equatable.dart';

class AuditEvent extends Equatable {
  const AuditEvent({
    required this.action,
    required this.targetId,
    required this.createdAt,
  });

  factory AuditEvent.fromJson(Map<String, Object?> json) {
    return AuditEvent(
      action: json['action'] as String? ?? '',
      targetId: json['targetId'] as String? ?? '',
      createdAt: json['createdAt'] as String? ?? '',
    );
  }

  final String action;
  final String targetId;
  final String createdAt;

  String get localCreatedAt {
    final parsed = DateTime.tryParse(createdAt);
    if (parsed == null) {
      return createdAt;
    }
    final local = parsed.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    final offset = local.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final offsetHours = two(offset.inHours.abs());
    final offsetMinutes = two(offset.inMinutes.abs() % 60);
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)} '
        'UTC$sign$offsetHours:$offsetMinutes';
  }

  @override
  List<Object?> get props => <Object?>[action, targetId, createdAt];
}
