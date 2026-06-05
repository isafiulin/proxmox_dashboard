class DataSnapshot {
  const DataSnapshot({
    required this.id,
    required this.sourceId,
    required this.sourceType,
    required this.status,
    required this.payload,
    required this.collectedAt,
  });

  factory DataSnapshot.fromJson(Map<String, Object?> json) {
    return DataSnapshot(
      id: json['id'] as String? ?? '',
      sourceId: json['sourceId'] as String? ?? '',
      sourceType: json['sourceType'] as String? ?? '',
      status: json['status'] as String? ?? 'unknown',
      payload: json['payload'] as Map<String, Object?>? ?? <String, Object?>{},
      collectedAt:
          DateTime.tryParse(json['collectedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final String id;
  final String sourceId;
  final String sourceType;
  final String status;
  final Map<String, Object?> payload;
  final DateTime collectedAt;

  String? get error => payload['error']?.toString();
}
