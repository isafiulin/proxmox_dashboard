part of 'dashboard_cubit.dart';

enum DashboardStatus { initial, loading, ready, failure }

class DashboardState extends Equatable {
  const DashboardState({
    this.status = DashboardStatus.initial,
    this.summary,
    this.error,
  });

  final DashboardStatus status;
  final DashboardSummary? summary;
  final String? error;

  DashboardState copyWith({
    DashboardStatus? status,
    DashboardSummary? summary,
    String? error,
  }) {
    return DashboardState(
      status: status ?? this.status,
      summary: summary ?? this.summary,
      error: error,
    );
  }

  @override
  List<Object?> get props => [status, summary, error];
}
