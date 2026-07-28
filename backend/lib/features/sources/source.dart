import 'package:neotelecom_backend/core/security/credentials_cipher.dart';
import 'package:neotelecom_backend/core/security/security.dart';

class Source {
  Source({
    required this.id,
    required this.name,
    required this.type,
    required this.baseUrl,
    required this.credential,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.backupNamespace = '',
    this.lastSeenAt,
  });

  factory Source.create({
    required String name,
    required String type,
    required String baseUrl,
    required EncryptedSecret credential,
    String backupNamespace = '',
  }) {
    final now = DateTime.now().toUtc();
    return Source(
      id: randomToken(),
      name: name,
      type: type,
      baseUrl: baseUrl,
      credential: credential,
      backupNamespace: backupNamespace,
      status: 'new',
      createdAt: now,
      updatedAt: now,
    );
  }

  factory Source.fromJson(Map<dynamic, dynamic> json) {
    return Source(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      baseUrl: json['baseUrl'] as String,
      credential: EncryptedSecret(
        ciphertext: (json['credentialCiphertext'] ??
            json['tokenCiphertext'] ??
            '') as String,
        nonce: (json['credentialNonce'] ?? json['tokenNonce'] ?? '') as String,
        mac: (json['credentialMac'] ?? json['tokenMac'] ?? '') as String,
      ),
      status: json['status'] as String,
      backupNamespace: json['backupNamespace']?.toString() ?? '',
      createdAt: _dateTimeFromJson(json['createdAt']!),
      updatedAt: _dateTimeFromJson(json['updatedAt']!),
      lastSeenAt: json['lastSeenAt'] == null
          ? null
          : _dateTimeFromJson(json['lastSeenAt']!),
    );
  }

  static const allowedTypes = {
    'proxmox_ve',
    'proxmox_backup',
    'redfish',
    'old_ilo2',
    'ipmi',
  };

  final String id;
  String name;
  String type;
  String baseUrl;
  EncryptedSecret credential;
  String backupNamespace;
  String status;
  final DateTime createdAt;
  DateTime updatedAt;
  DateTime? lastSeenAt;

  bool get hasToken => credential.hasValue;

  Map<String, Object?> toPublicJson() => {
        'id': id,
        'name': name,
        'type': type,
        'baseUrl': baseUrl,
        'backupNamespace': backupNamespace,
        'status': status,
        'hasToken': hasToken,
        'lastSeenAt': lastSeenAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  Map<String, Object?> toJson() => {
        ...toPublicJson(),
        'credentialCiphertext': credential.ciphertext,
        'credentialNonce': credential.nonce,
        'credentialMac': credential.mac,
      };
}

DateTime _dateTimeFromJson(Object value) {
  if (value is DateTime) return value.toUtc();
  return DateTime.parse(value as String).toUtc();
}
