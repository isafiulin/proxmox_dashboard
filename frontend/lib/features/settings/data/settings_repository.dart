import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/features/settings/domain/system_settings.dart';

class SettingsRepository {
  SettingsRepository(this._api);

  final ApiClient _api;

  Future<SystemSettings> load() async {
    final json = await _api.get('/settings');
    return SystemSettings.fromJson(
      json['settings'] as Map<String, Object?>? ?? <String, Object?>{},
    );
  }

  Future<SystemSettings> updateInterval(int minutes) async {
    final json = await _api.patch(
      '/settings',
      body: <String, Object?>{'collectionIntervalMinutes': minutes},
    );
    return SystemSettings.fromJson(
      json['settings'] as Map<String, Object?>? ?? <String, Object?>{},
    );
  }
}
