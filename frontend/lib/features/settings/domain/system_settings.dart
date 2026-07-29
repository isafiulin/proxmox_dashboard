import 'package:equatable/equatable.dart';

class SystemSettings extends Equatable {
  const SystemSettings({
    required this.collectionIntervalMinutes,
    required this.telegramEnabled,
    required this.hasTelegramBotToken,
    required this.telegramChatId,
    required this.telegramMinimumSeverity,
    required this.telegramNotifyRecovery,
    required this.ignoredErrorPatterns,
  });

  factory SystemSettings.defaults() => const SystemSettings(
    collectionIntervalMinutes: 30,
    telegramEnabled: false,
    hasTelegramBotToken: false,
    telegramChatId: '',
    telegramMinimumSeverity: 'warning',
    telegramNotifyRecovery: true,
    ignoredErrorPatterns: <String>['aptupdate'],
  );

  factory SystemSettings.fromJson(Map<String, Object?> json) {
    return SystemSettings(
      collectionIntervalMinutes:
          json['collectionIntervalMinutes'] as int? ?? 30,
      telegramEnabled: json['telegramEnabled'] as bool? ?? false,
      hasTelegramBotToken: json['hasTelegramBotToken'] as bool? ?? false,
      telegramChatId: json['telegramChatId']?.toString() ?? '',
      telegramMinimumSeverity:
          json['telegramMinimumSeverity']?.toString() ?? 'warning',
      telegramNotifyRecovery: json['telegramNotifyRecovery'] as bool? ?? true,
      ignoredErrorPatterns:
          (json['ignoredErrorPatterns'] as List?)
              ?.map((value) => value.toString())
              .toList(growable: false) ??
          const <String>['aptupdate'],
    );
  }

  final int collectionIntervalMinutes;
  final bool telegramEnabled;
  final bool hasTelegramBotToken;
  final String telegramChatId;
  final String telegramMinimumSeverity;
  final bool telegramNotifyRecovery;
  final List<String> ignoredErrorPatterns;

  Map<String, Object?> toJson() => <String, Object?>{
    'collectionIntervalMinutes': collectionIntervalMinutes,
    'telegramEnabled': telegramEnabled,
    'hasTelegramBotToken': hasTelegramBotToken,
    'telegramChatId': telegramChatId,
    'telegramMinimumSeverity': telegramMinimumSeverity,
    'telegramNotifyRecovery': telegramNotifyRecovery,
    'ignoredErrorPatterns': ignoredErrorPatterns,
  };

  @override
  List<Object?> get props => <Object?>[
    collectionIntervalMinutes,
    telegramEnabled,
    hasTelegramBotToken,
    telegramChatId,
    telegramMinimumSeverity,
    telegramNotifyRecovery,
    ignoredErrorPatterns,
  ];
}
