import 'dart:convert';
import 'dart:io';

import 'package:neotelecom_backend/core/logging/app_logger.dart';
import 'package:neotelecom_backend/features/integrations/proxmox_auth_header.dart';
import 'package:neotelecom_backend/features/sources/source.dart';

class ProxmoxApiClient {
  ProxmoxApiClient({required this.allowInsecureTls, required this.logger}) {
    if (allowInsecureTls) {
      _client.badCertificateCallback = (_, __, ___) => true;
    }
  }

  final bool allowInsecureTls;
  final AppLogger logger;
  final HttpClient _client = HttpClient();
  final Map<String, ({DateTime storedAt, Object? data})> _cache = {};
  final Map<String, Future<Object?>> _activeRequests = {};

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
  ) {
    if (credential.isEmpty) {
      return Future<Object?>.error(ProxmoxApiException(
        'source_credentials_missing',
        sourceId: source.id,
        sourceType: source.type,
        path: path,
      ));
    }

    final cacheKey =
        '${source.id}\u0001${source.updatedAt.microsecondsSinceEpoch}\u0001$path';
    final cached = _cache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.storedAt) <
            const Duration(seconds: 15)) {
      return Future<Object?>.value(cached.data);
    }
    final activeRequest = _activeRequests[cacheKey];
    if (activeRequest != null) return activeRequest;

    final request = _request(source, credential, path);
    _activeRequests[cacheKey] = request;
    return request.then((data) {
      _cache[cacheKey] = (storedAt: DateTime.now(), data: data);
      return data;
    }).whenComplete(() => _activeRequests.remove(cacheKey));
  }

  Future<Object?> _request(
    Source source,
    String credential,
    String path,
  ) async {
    final Uri uri = _uriFor(source.baseUrl, path);
    final stopwatch = Stopwatch()..start();

    try {
      final HttpClientRequest request =
          await _client.getUrl(uri).timeout(const Duration(seconds: 10));
      request.headers
        ..set(
          HttpHeaders.authorizationHeader,
          proxmoxAuthHeader(sourceType: source.type, credential: credential),
        )
        ..set(HttpHeaders.acceptHeader, ContentType.json.mimeType);

      final HttpClientResponse response =
          await request.close().timeout(const Duration(seconds: 30));
      final String body = await utf8.decoder.bind(response).join();
      Map<String, Object?> json = <String, Object?>{};
      try {
        json = body.isEmpty
            ? <String, Object?>{}
            : jsonDecode(body) as Map<String, Object?>;
      } on FormatException {
        // ponytail: Proxmox can return plain text for auth failures; successful
        // responses must remain JSON because all callers consume `data`.
        if (response.statusCode >= 200 && response.statusCode < 300) rethrow;
      }

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
