String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

class DataSnapshot {
  DataSnapshot({
    required this.id,
    required this.sourceId,
    required this.sourceType,
    required this.status,
    required this.payload,
    required this.collectedAt,
  });

  factory DataSnapshot.create({
    required String sourceId,
    required String sourceType,
    required String status,
    required Map<String, Object?> payload,
  }) {
    return DataSnapshot(
      id: _newId(),
      sourceId: sourceId,
      sourceType: sourceType,
      status: status,
      payload: payload,
      collectedAt: DateTime.now().toUtc(),
    );
  }

  factory DataSnapshot.fromJson(Map<dynamic, dynamic> json) {
    return DataSnapshot(
      id: json['id'] as String,
      sourceId: json['sourceId'] as String,
      sourceType: json['sourceType'] as String,
      status: json['status'] as String,
      payload: Map<String, Object?>.from(json['payload'] as Map? ?? const {}),
      collectedAt: DateTime.parse(json['collectedAt'] as String).toUtc(),
    );
  }

  final String id;
  final String sourceId;
  final String sourceType;
  final String status;
  final Map<String, Object?> payload;
  final DateTime collectedAt;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'sourceId': sourceId,
        'sourceType': sourceType,
        'status': status,
        'payload': payload,
        'collectedAt': collectedAt.toUtc().toIso8601String(),
      };
}
