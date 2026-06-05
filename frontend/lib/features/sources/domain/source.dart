import 'package:equatable/equatable.dart';

class Source extends Equatable {
  const Source({
    required this.id,
    required this.name,
    required this.type,
    required this.baseUrl,
    required this.status,
    required this.hasToken,
  });

  factory Source.fromJson(Map<String, Object?> json) {
    return Source(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      baseUrl: json['baseUrl'] as String,
      status: json['status'] as String,
      hasToken: json['hasToken'] as bool? ?? false,
    );
  }

  final String id;
  final String name;
  final String type;
  final String baseUrl;
  final String status;
  final bool hasToken;

  @override
  List<Object?> get props => [id, name, type, baseUrl, status, hasToken];
}
