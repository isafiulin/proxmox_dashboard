import 'package:neotelecom_backend/core/extensions/iterable_extensions.dart';
import 'package:neotelecom_backend/core/store/app_store.dart';
import 'package:neotelecom_backend/features/audit/audit_service.dart';
import 'package:neotelecom_backend/features/users/user.dart';

class UsersService {
  UsersService(this._store, this._audit);

  final AppStore _store;
  final AuditService _audit;

  List<User> list() => List.unmodifiable(_store.users);

  User? byId(String id) =>
      _store.users.where((user) => user.id == id).firstOrNull;

  User? byEmail(String email) => _store.users
      .where((user) => user.email == email.toLowerCase())
      .firstOrNull;

  Future<User> create({
    required String actorUserId,
    required String email,
    required String displayName,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedDisplayName = displayName.trim();

    if (!_isValidEmail(normalizedEmail) ||
        normalizedDisplayName.isEmpty ||
        password.length < 8) {
      throw const UserInputException('invalid_user_payload');
    }
    if (byEmail(normalizedEmail) != null) {
      throw const UserInputException('email_already_exists');
    }

    final user = User.create(
        email: normalizedEmail,
        displayName: normalizedDisplayName,
        password: password);
    _store.users.add(user);
    _audit.record('user.create',
        actorUserId: actorUserId,
        targetId: user.id,
        details: {'email': normalizedEmail});
    await _store.save();
    return user;
  }

  Future<User> updateDisplayName({
    required String actorUserId,
    required String userId,
    required String displayName,
  }) async {
    final user = byId(userId);
    if (user == null) throw const UserInputException('user_not_found');

    final normalizedDisplayName = displayName.trim();
    if (normalizedDisplayName.isEmpty)
      throw const UserInputException('invalid_display_name');

    user.displayName = normalizedDisplayName;
    user.updatedAt = DateTime.now().toUtc();
    _audit.record('user.update', actorUserId: actorUserId, targetId: user.id);
    await _store.save();
    return user;
  }

  Future<User> changePassword({
    required String actorUserId,
    required String userId,
    required String password,
  }) async {
    final user = byId(userId);
    if (user == null) throw const UserInputException('user_not_found');
    if (password.length < 8)
      throw const UserInputException('password_too_short');

    user.setPassword(password);
    _audit.record('user.change_password',
        actorUserId: actorUserId, targetId: user.id);
    await _store.save();
    return user;
  }

  Future<User> activate(
      {required String actorUserId, required String userId}) async {
    final user = byId(userId);
    if (user == null) throw const UserInputException('user_not_found');

    user.isActive = true;
    user.updatedAt = DateTime.now().toUtc();
    _audit.record('user.activate', actorUserId: actorUserId, targetId: user.id);
    await _store.save();
    return user;
  }

  Future<User> deactivate(
      {required String actorUserId, required String userId}) async {
    final user = byId(userId);
    if (user == null) throw const UserInputException('user_not_found');

    final activeAdmins = _store.users
        .where((candidate) => candidate.isActive && candidate.role == 'admin')
        .length;
    if (user.id == actorUserId || activeAdmins <= 1) {
      throw const UserInputException('cannot_deactivate_last_admin');
    }

    user.isActive = false;
    user.updatedAt = DateTime.now().toUtc();
    _audit.record('user.deactivate',
        actorUserId: actorUserId, targetId: user.id);
    await _store.save();
    return user;
  }
}

bool _isValidEmail(String value) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);

class UserInputException implements Exception {
  const UserInputException(this.code);

  final String code;
}
