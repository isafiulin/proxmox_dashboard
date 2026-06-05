import 'package:neotelecom_backend/core/security/security.dart';

class User {
  User({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    required this.passwordSalt,
    required this.passwordHash,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.lastLoginAt,
  });

  factory User.create({
    required String email,
    required String displayName,
    required String password,
  }) {
    final salt = randomToken();
    final now = DateTime.now().toUtc();
    return User(
      id: randomToken(),
      email: email.toLowerCase(),
      displayName: displayName,
      role: 'admin',
      passwordSalt: salt,
      passwordHash: hashPassword(password, salt),
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory User.fromJson(Map<dynamic, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['displayName'] as String,
      role: json['role'] as String,
      passwordSalt: json['passwordSalt'] as String,
      passwordHash: json['passwordHash'] as String,
      isActive: json['isActive'] as bool,
      createdAt: _dateTimeFromJson(json['createdAt']!),
      updatedAt: _dateTimeFromJson(json['updatedAt']!),
      lastLoginAt: json['lastLoginAt'] == null
          ? null
          : _dateTimeFromJson(json['lastLoginAt']!),
    );
  }

  final String id;
  final String email;
  String displayName;
  final String role;
  String passwordSalt;
  String passwordHash;
  bool isActive;
  final DateTime createdAt;
  DateTime updatedAt;
  DateTime? lastLoginAt;

  bool verifyPassword(String password) =>
      hashPassword(password, passwordSalt) == passwordHash;

  void setPassword(String password) {
    passwordSalt = randomToken();
    passwordHash = hashPassword(password, passwordSalt);
    updatedAt = DateTime.now().toUtc();
  }

  Map<String, Object?> toPublicJson() => {
        'id': id,
        'email': email,
        'displayName': displayName,
        'role': role,
        'isActive': isActive,
        'lastLoginAt': lastLoginAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  Map<String, Object?> toJson() => {
        ...toPublicJson(),
        'passwordSalt': passwordSalt,
        'passwordHash': passwordHash,
      };
}

DateTime _dateTimeFromJson(Object value) {
  if (value is DateTime) return value.toUtc();
  return DateTime.parse(value as String).toUtc();
}
