class SystemSettings {
  SystemSettings({required this.collectionIntervalMinutes});

  factory SystemSettings.defaults() =>
      SystemSettings(collectionIntervalMinutes: 30);

  factory SystemSettings.fromJson(Map<dynamic, dynamic> json) {
    return SystemSettings(
      collectionIntervalMinutes:
          json['collectionIntervalMinutes'] as int? ?? 30,
    );
  }

  int collectionIntervalMinutes;

  Map<String, Object?> toJson() => <String, Object?>{
        'collectionIntervalMinutes': collectionIntervalMinutes,
      };
}
