import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/features/auth/domain/app_user.dart';

class UsersRepository {
  UsersRepository(this._api);

  final ApiClient _api;

  Future<List<AppUser>> list() async {
    final Map<String, Object?> json = await _api.get('/users');
    return ((json['items'] as List?) ?? <Object?>[])
        .map((Object? item) => AppUser.fromJson(item! as Map<String, Object?>))
        .toList();
  }

  Future<void> create({
    required String displayName,
    required String email,
    required String password,
  }) async {
    await _api.post(
      '/users',
      body: <String, Object?>{
        'displayName': displayName,
        'email': email,
        'password': password,
      },
    );
  }

  Future<void> activate(String id) => _api.post('/users/$id/activate');

  Future<void> deactivate(String id) => _api.post('/users/$id/deactivate');
}
