import 'package:equatable/equatable.dart';

class SourceTestResult extends Equatable {
  const SourceTestResult({
    required this.ok,
    required this.status,
    required this.message,
  });

  factory SourceTestResult.fromJson(Map<String, Object?> json) {
    return SourceTestResult(
      ok: json['ok'] as bool? ?? false,
      status: json['status'] as String? ?? 'unknown',
      message: json['message'] as String? ?? '',
    );
  }

  final bool ok;
  final String status;
  final String message;

  @override
  List<Object?> get props => <Object?>[ok, status, message];
}
