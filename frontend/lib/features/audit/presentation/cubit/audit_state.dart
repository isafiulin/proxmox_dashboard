part of 'audit_cubit.dart';

enum AuditStatus { initial, loading, ready, failure }

class AuditState extends Equatable {
  const AuditState({
    this.status = AuditStatus.initial,
    this.items = const <AuditEvent>[],
    this.error,
  });

  final AuditStatus status;
  final List<AuditEvent> items;
  final String? error;

  AuditState copyWith({
    AuditStatus? status,
    List<AuditEvent>? items,
    String? error,
  }) {
    return AuditState(
      status: status ?? this.status,
      items: items ?? this.items,
      error: error,
    );
  }

  @override
  List<Object?> get props => <Object?>[status, items, error];
}
