import 'package:neotelecom_backend/core/security/credentials_cipher.dart';
import 'package:neotelecom_backend/features/settings/error_filter.dart';

class SystemSettings {
  SystemSettings({
    required this.collectionIntervalMinutes,
    required this.telegramEnabled,
    required this.telegramBotToken,
    required this.telegramChatId,
    required this.telegramMinimumSeverity,
    required this.telegramNotifyRecovery,
    required this.ignoredErrorPatterns,
  });

  factory SystemSettings.defaults() => SystemSettings(
        collectionIntervalMinutes: 30,
        telegramEnabled: false,
        telegramBotToken: const EncryptedSecret.empty(),
        telegramChatId: '',
        telegramMinimumSeverity: 'warning',
        telegramNotifyRecovery: true,
        ignoredErrorPatterns: defaultIgnoredErrorPatterns,
      );

  factory SystemSettings.fromJson(Map<dynamic, dynamic> json) {
    return SystemSettings(
      collectionIntervalMinutes:
          json['collectionIntervalMinutes'] as int? ?? 30,
      telegramEnabled: json['telegramEnabled'] as bool? ?? false,
      telegramBotToken: EncryptedSecret(
        ciphertext: json['telegramBotTokenCiphertext']?.toString() ?? '',
        nonce: json['telegramBotTokenNonce']?.toString() ?? '',
        mac: json['telegramBotTokenMac']?.toString() ?? '',
      ),
      telegramChatId: json['telegramChatId']?.toString() ?? '',
      telegramMinimumSeverity:
          json['telegramMinimumSeverity']?.toString() ?? 'warning',
      telegramNotifyRecovery: json['telegramNotifyRecovery'] as bool? ?? true,
      ignoredErrorPatterns: normalizeIgnoredErrorPatterns(
        json['ignoredErrorPatterns'] is List
            ? json['ignoredErrorPatterns'] as List
            : defaultIgnoredErrorPatterns,
      ),
    );
  }

  int collectionIntervalMinutes;
  bool telegramEnabled;
  EncryptedSecret telegramBotToken;
  String telegramChatId;
  String telegramMinimumSeverity;
  bool telegramNotifyRecovery;
  List<String> ignoredErrorPatterns;

  Map<String, Object?> toJson() => <String, Object?>{
        'collectionIntervalMinutes': collectionIntervalMinutes,
        'telegramEnabled': telegramEnabled,
        'telegramBotTokenCiphertext': telegramBotToken.ciphertext,
        'telegramBotTokenNonce': telegramBotToken.nonce,
        'telegramBotTokenMac': telegramBotToken.mac,
        'telegramChatId': telegramChatId,
        'telegramMinimumSeverity': telegramMinimumSeverity,
        'telegramNotifyRecovery': telegramNotifyRecovery,
        'ignoredErrorPatterns': ignoredErrorPatterns,
      };

  Map<String, Object?> toPublicJson() => <String, Object?>{
        'collectionIntervalMinutes': collectionIntervalMinutes,
        'telegramEnabled': telegramEnabled,
        'hasTelegramBotToken': telegramBotToken.hasValue,
        'telegramChatId': telegramChatId,
        'telegramMinimumSeverity': telegramMinimumSeverity,
        'telegramNotifyRecovery': telegramNotifyRecovery,
        'ignoredErrorPatterns': ignoredErrorPatterns,
      };
}
