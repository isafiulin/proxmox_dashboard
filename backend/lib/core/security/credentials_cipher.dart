import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

class CredentialsCipher {
  CredentialsCipher(String keyMaterial)
      : _secretKey = SecretKey(sha256.convert(utf8.encode(keyMaterial)).bytes);

  factory CredentialsCipher.fromEnvironment() {
    final keyMaterial = Platform.environment['CREDENTIALS_ENCRYPTION_KEY'];
    if (keyMaterial == null || keyMaterial.length < 16) {
      throw StateError(
        'CREDENTIALS_ENCRYPTION_KEY must be set and contain at least 16 characters',
      );
    }
    return CredentialsCipher(keyMaterial);
  }

  final _algorithm = AesGcm.with256bits();
  final SecretKey _secretKey;

  Future<EncryptedSecret> encrypt(String value) async {
    if (value.isEmpty) {
      return const EncryptedSecret.empty();
    }

    final secretBox = await _algorithm.encrypt(
      utf8.encode(value),
      secretKey: _secretKey,
    );

    return EncryptedSecret(
      ciphertext: base64Encode(secretBox.cipherText),
      nonce: base64Encode(secretBox.nonce),
      mac: base64Encode(secretBox.mac.bytes),
    );
  }

  Future<String> decrypt(EncryptedSecret secret) async {
    if (!secret.hasValue) return '';

    final clearBytes = await _algorithm.decrypt(
      SecretBox(
        base64Decode(secret.ciphertext),
        nonce: base64Decode(secret.nonce),
        mac: Mac(base64Decode(secret.mac)),
      ),
      secretKey: _secretKey,
    );

    return utf8.decode(clearBytes);
  }
}

class EncryptedSecret {
  const EncryptedSecret({
    required this.ciphertext,
    required this.nonce,
    required this.mac,
  });

  const EncryptedSecret.empty()
      : ciphertext = '',
        nonce = '',
        mac = '';

  final String ciphertext;
  final String nonce;
  final String mac;

  bool get hasValue =>
      ciphertext.isNotEmpty && nonce.isNotEmpty && mac.isNotEmpty;
}
