import 'package:equatable/equatable.dart';

class SystemSettings extends Equatable {
  const SystemSettings({required this.collectionIntervalMinutes});

  factory SystemSettings.defaults() =>
      const SystemSettings(collectionIntervalMinutes: 30);

  factory SystemSettings.fromJson(Map<String, Object?> json) {
    return SystemSettings(
      collectionIntervalMinutes:
          json['collectionIntervalMinutes'] as int? ?? 30,
    );
  }

  final int collectionIntervalMinutes;

  Map<String, Object?> toJson() => <String, Object?>{
    'collectionIntervalMinutes': collectionIntervalMinutes,
  };

  @override
  List<Object?> get props => <Object?>[collectionIntervalMinutes];
}
