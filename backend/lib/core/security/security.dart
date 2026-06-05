import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

String randomToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64UrlEncode(bytes);
}

String hashPassword(String password, String salt) {
  return sha256.convert(utf8.encode('$salt:$password')).toString();
}

String hashToken(String token) {
  return sha256.convert(utf8.encode(token)).toString();
}
