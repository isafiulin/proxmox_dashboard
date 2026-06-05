import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/features/auth/domain/app_user.dart';
import 'package:frontend/features/auth/domain/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _authTokenKey = 'auth.token';

class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  Future<Session> login(String email, String password) async {
    final session = Session.fromJson(
      await _api.post(
        '/auth/login',
        body: {'email': email, 'password': password},
      ),
    );
    _api.authToken = session.token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_authTokenKey, session.token);
    return session;
  }

  Future<Session?> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_authTokenKey);
    if (token == null || token.isEmpty) {
      return null;
    }
    _api.authToken = token;
    final json = await _api.get('/me');
    final user = json['user'];
    if (user is! Map<String, Object?>) {
      await clearSession();
      return null;
    }
    return Session(token: token, user: AppUser.fromJson(user));
  }

  Future<AppUser> updateProfile({required String displayName}) async {
    final json = await _api.patch(
      '/me',
      body: <String, Object?>{'displayName': displayName},
    );
    return AppUser.fromJson(json['user'] as Map<String, Object?>);
  }

  Future<void> logout() async {
    try {
      await _api.post('/auth/logout');
    } finally {
      await clearSession();
    }
  }

  Future<void> clearSession() async {
    _api.authToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authTokenKey);
  }
}
