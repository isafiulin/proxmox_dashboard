import 'package:neotelecom_backend/core/security/credentials_cipher.dart';
import 'package:neotelecom_backend/core/store/app_store.dart';
import 'package:neotelecom_backend/features/audit/audit_service.dart';
import 'package:neotelecom_backend/features/settings/system_settings.dart';
import 'package:neotelecom_backend/features/settings/error_filter.dart';

class SettingsService {
  SettingsService(this._store, this._audit, this._credentialsCipher);

  final AppStore _store;
  final AuditService _audit;
  final CredentialsCipher _credentialsCipher;

  SystemSettings get current => _store.settings;

  Future<SystemSettings> update({
    required String actorUserId,
    required int collectionIntervalMinutes,
    required bool telegramEnabled,
    required String telegramChatId,
    required String telegramMinimumSeverity,
    required bool telegramNotifyRecovery,
    required List<String> ignoredErrorPatterns,
    String? telegramBotToken,
    bool clearTelegramBotToken = false,
  }) async {
    if (collectionIntervalMinutes < 5 || collectionIntervalMinutes > 1440) {
      throw const SettingsInputException('invalid_settings_payload');
    }
    final patterns = normalizeIgnoredErrorPatterns(ignoredErrorPatterns);
    if (patterns.length > 100 ||
        patterns.any((pattern) => pattern.length > 200)) {
      throw const SettingsInputException('invalid_error_filters');
    }

    final chatId = telegramChatId.trim();
    final token = telegramBotToken?.trim() ?? '';
    if (!const <String>{'warning', 'critical'}
            .contains(telegramMinimumSeverity) ||
        (chatId.isNotEmpty &&
            !RegExp(r'^(?:-?\d+|@[A-Za-z0-9_]{5,})$').hasMatch(chatId)) ||
        (token.isNotEmpty &&
            !RegExp(r'^\d+:[A-Za-z0-9_-]{20,}$').hasMatch(token))) {
      throw const SettingsInputException('invalid_telegram_settings');
    }

    var encryptedToken = _store.settings.telegramBotToken;
    if (clearTelegramBotToken) {
      encryptedToken = const EncryptedSecret.empty();
    } else if (token.isNotEmpty) {
      encryptedToken = await _credentialsCipher.encrypt(token);
    }
    if (telegramEnabled && (!encryptedToken.hasValue || chatId.isEmpty)) {
      throw const SettingsInputException('invalid_telegram_settings');
    }

    _store.settings.collectionIntervalMinutes = collectionIntervalMinutes;
    _store.settings.telegramEnabled = telegramEnabled;
    _store.settings.telegramBotToken = encryptedToken;
    _store.settings.telegramChatId = chatId;
    _store.settings.telegramMinimumSeverity = telegramMinimumSeverity;
    _store.settings.telegramNotifyRecovery = telegramNotifyRecovery;
    _store.settings.ignoredErrorPatterns = patterns;
    _audit.record(
      'settings.update',
      actorUserId: actorUserId,
      targetId: 'system',
      details: <String, Object?>{
        'collectionIntervalMinutes': collectionIntervalMinutes,
        'telegramEnabled': telegramEnabled,
        'telegramChatId': chatId,
        'telegramMinimumSeverity': telegramMinimumSeverity,
        'telegramNotifyRecovery': telegramNotifyRecovery,
        'ignoredErrorPatterns': patterns,
        'telegramBotTokenChanged': token.isNotEmpty || clearTelegramBotToken,
      },
    );
    await _store.save();
    return _store.settings;
  }
}

class SettingsInputException implements Exception {
  const SettingsInputException(this.code);

  final String code;
}
