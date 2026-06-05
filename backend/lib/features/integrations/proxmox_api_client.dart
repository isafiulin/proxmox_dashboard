import 'dart:convert';
import 'dart:io';

import 'package:neotelecom_backend/features/integrations/proxmox_auth_header.dart';
import 'package:neotelecom_backend/features/sources/source.dart';

class ProxmoxApiClient {
  ProxmoxApiClient({required this.allowInsecureTls});

  final bool allowInsecureTls;

  Future<Object?> getVe(Source source, String credential, String path) {
    return _get(source, credential, path);
  }

  Future<Object?> getBackup(Source source, String credential, String path) {
    return _get(source, credential, path);
  }

  Future<Object?> _get(
    Source source,
    String credential,
    String path,
  ) async {
    if (credential.isEmpty) {
      throw const ProxmoxApiException('source_credentials_missing');
    }

    final Uri uri = _uriFor(source.baseUrl, path);
    final HttpClient client = HttpClient();
    if (allowInsecureTls) {
      client.badCertificateCallback = (_, __, ___) => true;
    }

    try {
      final HttpClientRequest request =
          await client.getUrl(uri).timeout(const Duration(seconds: 10));
      request.headers
        ..set(
          HttpHeaders.authorizationHeader,
          proxmoxAuthHeader(sourceType: source.type, credential: credential),
        )
        ..set(HttpHeaders.acceptHeader, ContentType.json.mimeType);

      final HttpClientResponse response =
          await request.close().timeout(const Duration(seconds: 30));
      final String body = await utf8.decoder.bind(response).join();
      final Map<String, Object?> json = body.isEmpty
          ? <String, Object?>{}
          : jsonDecode(body) as Map<String, Object?>;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return json['data'];
      }

      throw ProxmoxApiException(
        'HTTP ${response.statusCode}: ${json['errors'] ?? json['message'] ?? body}',
      );
    } finally {
      client.close(force: true);
    }
  }
}

Uri _uriFor(String baseUrl, String path) {
  final base = Uri.parse(baseUrl);
  final relative = Uri.parse(path);
  return base.replace(path: relative.path, query: relative.query);
}

class ProxmoxApiException implements Exception {
  const ProxmoxApiException(this.message);

  final String message;
}
