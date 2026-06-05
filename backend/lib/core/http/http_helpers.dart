import 'dart:convert';
import 'dart:io';

Future<Map<String, Object?>> readJson(HttpRequest request) async {
  final rawBody = await utf8.decoder.bind(request).join();
  if (rawBody.trim().isEmpty) return {};
  final decoded = jsonDecode(rawBody);
  if (decoded is Map<String, Object?>) return decoded;
  throw const FormatException('Expected JSON object');
}

Future<void> sendJson(
  HttpRequest request,
  Map<String, Object?> body, {
  int statusCode = HttpStatus.ok,
}) async {
  request.response.statusCode = statusCode;
  request.response.write(jsonEncode(body));
  await request.response.close();
}

void applyDefaultHeaders(HttpRequest request) {
  request.response.headers
    ..set(HttpHeaders.contentTypeHeader, ContentType.json.mimeType)
    ..set('X-Content-Type-Options', 'nosniff')
    ..set('Access-Control-Allow-Origin', '*')
    ..set('Access-Control-Allow-Methods', 'GET,POST,PATCH,DELETE,OPTIONS')
    ..set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
}

String? bearerToken(HttpRequest request) {
  final authorization = request.headers.value(HttpHeaders.authorizationHeader);
  if (authorization == null || !authorization.startsWith('Bearer '))
    return null;
  return authorization.substring('Bearer '.length);
}
