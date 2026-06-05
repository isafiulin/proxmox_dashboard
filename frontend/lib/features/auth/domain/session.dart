import 'package:frontend/features/auth/domain/app_user.dart';

class Session {
  const Session({required this.token, required this.user});

  factory Session.fromJson(Map<String, Object?> json) {
    return Session(
      token: json['token'] as String,
      user: AppUser.fromJson(json['user'] as Map<String, Object?>),
    );
  }

  final String token;
  final AppUser user;
}
