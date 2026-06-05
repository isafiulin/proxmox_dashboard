import 'package:equatable/equatable.dart';

class DashboardSummary extends Equatable {
  const DashboardSummary({
    required this.sources,
    required this.users,
    required this.guests,
    required this.criticalAlerts,
  });

  factory DashboardSummary.fromJson(Map<String, Object?> json) {
    return DashboardSummary(
      sources: json['sources'] as int? ?? 0,
      users: json['users'] as int? ?? 0,
      guests: json['guests'] as int? ?? 0,
      criticalAlerts: json['criticalAlerts'] as int? ?? 0,
    );
  }

  final int sources;
  final int users;
  final int guests;
  final int criticalAlerts;

  @override
  List<Object?> get props => [sources, users, guests, criticalAlerts];
}
