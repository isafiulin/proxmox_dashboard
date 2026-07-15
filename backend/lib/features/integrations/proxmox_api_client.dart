import 'dart:convert';
import 'dart:io';

import 'package:neotelecom_backend/core/logging/app_logger.dart';
import 'package:neotelecom_backend/features/integrations/proxmox_auth_header.dart';
import 'package:neotelecom_backend/features/sources/source.dart';

class ProxmoxApiClient {
  ProxmoxApiClient({required this.allowInsecureTls, required this.logger});

  final bool allowInsecureTls;
  final AppLogger logger;

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
      throw ProxmoxApiException(
        'source_credentials_missing',
        sourceId: source.id,
        sourceType: source.type,
        path: path,
      );
    }

    final Uri uri = _uriFor(source.baseUrl, path);
    final HttpClient client = HttpClient();
    final stopwatch = Stopwatch()..start();
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
        logger.info('integration.proxmox_request', <String, Object?>{
          'sourceId': source.id,
          'sourceType': source.type,
          'path': path,
          'statusCode': response.statusCode,
          'durationMs': stopwatch.elapsedMilliseconds,
        });
        return json['data'];
      }

      logger.warning('integration.proxmox_request_failed', <String, Object?>{
        'sourceId': source.id,
        'sourceType': source.type,
        'path': path,
        'statusCode': response.statusCode,
        'durationMs': stopwatch.elapsedMilliseconds,
      });
      throw ProxmoxApiException(
        'HTTP ${response.statusCode}: ${json['errors'] ?? json['message'] ?? body}',
        sourceId: source.id,
        sourceType: source.type,
        path: path,
        statusCode: response.statusCode,
      );
    } on Object catch (error) {
      if (error is! ProxmoxApiException) {
        logger.error(
          'integration.proxmox_request_error',
          <String, Object?>{
            'sourceId': source.id,
            'sourceType': source.type,
            'path': path,
            'durationMs': stopwatch.elapsedMilliseconds,
          },
          error: error,
        );
      }
      if (error is ProxmoxApiException) {
        rethrow;
      }
      throw ProxmoxApiException(
        'integration_request_failed: $error',
        sourceId: source.id,
        sourceType: source.type,
        path: path,
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
  const ProxmoxApiException(
    this.message, {
    this.sourceId,
    this.sourceType,
    this.path,
    this.statusCode,
  });

  final String message;
  final String? sourceId;
  final String? sourceType;
  final String? path;
  final int? statusCode;
}
