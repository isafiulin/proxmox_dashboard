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

  Future<SystemSettings> updateTelegram({
    required bool enabled,
    required String chatId,
    required String minimumSeverity,
    required bool notifyRecovery,
    String botToken = '',
    bool clearBotToken = false,
    required List<String> ignoredErrorPatterns,
  }) async {
    final json = await _api.patch(
      '/settings',
      body: <String, Object?>{
        'telegramEnabled': enabled,
        'telegramChatId': chatId,
        'telegramMinimumSeverity': minimumSeverity,
        'telegramNotifyRecovery': notifyRecovery,
        if (botToken.isNotEmpty) 'telegramBotToken': botToken,
        if (clearBotToken) 'clearTelegramBotToken': true,
        'ignoredErrorPatterns': ignoredErrorPatterns,
      },
    );
    return SystemSettings.fromJson(
      json['settings'] as Map<String, Object?>? ?? <String, Object?>{},
    );
  }

  Future<void> testTelegram() => _api.post('/settings/telegram/test');
}
