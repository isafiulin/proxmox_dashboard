import 'package:equatable/equatable.dart';

class AppUser extends Equatable {
  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    required this.isActive,
  });

  factory AppUser.fromJson(Map<String, Object?> json) {
    return AppUser(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['displayName'] as String,
      role: json['role'] as String,
      isActive: json['isActive'] as bool,
    );
  }

  final String id;
  final String email;
  final String displayName;
  final String role;
  final bool isActive;

  @override
  List<Object?> get props => [id, email, displayName, role, isActive];
}
