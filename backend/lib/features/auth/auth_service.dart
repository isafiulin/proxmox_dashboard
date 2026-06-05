import 'dart:io';

import 'package:neotelecom_backend/core/security/security.dart';
import 'package:neotelecom_backend/core/store/app_store.dart';
import 'package:neotelecom_backend/features/audit/audit_service.dart';
import 'package:neotelecom_backend/features/users/user.dart';
import 'package:neotelecom_backend/features/users/users_service.dart';

class AuthService {
  AuthService(this._store, this._users, this._audit);

  final AppStore _store;
  final UsersService _users;
  final AuditService _audit;
  final _sessions = <String, String>{};

  Future<void> bootstrapAdmin() async {
    if (_store.users.isNotEmpty) return;

    final email =
        Platform.environment['BOOTSTRAP_ADMIN_EMAIL'] ?? 'admin@example.local';
    final password =
        Platform.environment['BOOTSTRAP_ADMIN_PASSWORD'] ?? 'admin12345';
    final displayName =
        Platform.environment['BOOTSTRAP_ADMIN_DISPLAY_NAME'] ?? 'Administrator';

    final user =
        User.create(email: email, displayName: displayName, password: password);
    _store.users.add(user);
    _audit.record('user.bootstrap',
        actorUserId: user.id, targetId: user.id, details: {'email': email});
    await _store.save();
  }

  Future<AuthSession> login(String email, String password) async {
    final user = _users.byEmail(email.trim().toLowerCase());
    if (user == null || !user.isActive || !user.verifyPassword(password)) {
      throw const AuthException('invalid_credentials');
    }

    user.lastLoginAt = DateTime.now().toUtc();
    final token = randomToken();
    _sessions[token] = user.id;
    _audit.record('auth.login', actorUserId: user.id, targetId: user.id);
    await _store.save();

    return AuthSession(token: token, user: user);
  }

  Future<void> logout(String token, User user) async {
    _sessions.remove(token);
    _audit.record('auth.logout', actorUserId: user.id, targetId: user.id);
    await _store.save();
  }

  User? authenticate(String? token) {
    if (token == null) return null;
    final userId = _sessions[token];
    if (userId == null) return null;
    final user = _users.byId(userId);
    if (user == null || !user.isActive) return null;
    return user;
  }
}

class AuthSession {
  const AuthSession({required this.token, required this.user});

  final String token;
  final User user;
}

class AuthException implements Exception {
  const AuthException(this.code);

  final String code;
}
