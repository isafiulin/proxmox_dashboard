import 'dart:convert';
import 'dart:io';

import 'package:neotelecom_backend/features/integrations/proxmox_auth_header.dart';
import 'package:neotelecom_backend/features/sources/source.dart';

class SourceConnectionTester {
  SourceConnectionTester({required this.allowInsecureTls});

  final bool allowInsecureTls;

  Future<ConnectionTestResult> test(Source source, String credential) async {
    if (source.type == 'proxmox_ve') {
      return _testProxmox(source, credential);
    }
    if (source.type == 'proxmox_backup') {
      return _testProxmox(source, credential);
    }
    if (source.type == 'redfish') {
      return const ConnectionTestResult(
        ok: false,
        status: 'unknown',
        message: 'Redfish/iLO connection test is not implemented yet.',
      );
    }

    return const ConnectionTestResult(
      ok: false,
      status: 'critical',
      message: 'Unsupported source type.',
    );
  }

  Future<ConnectionTestResult> _testProxmox(
    Source source,
    String credential,
  ) async {
    if (credential.isEmpty) {
      return const ConnectionTestResult(
        ok: false,
        status: 'critical',
        message: 'API token is missing.',
      );
    }

    final uri = Uri.parse(source.baseUrl).replace(path: '/api2/json/version');
    final client = HttpClient();
    if (allowInsecureTls) {
      client.badCertificateCallback = (_, __, ___) => true;
    }

    try {
      final request =
          await client.getUrl(uri).timeout(const Duration(seconds: 10));
      request.headers
        ..set(
          HttpHeaders.authorizationHeader,
          proxmoxAuthHeader(sourceType: source.type, credential: credential),
        )
        ..set(HttpHeaders.acceptHeader, ContentType.json.mimeType);

      final response =
          await request.close().timeout(const Duration(seconds: 20));
      final body = await utf8.decoder.bind(response).join();
      Map<String, Object?> json = <String, Object?>{};
      try {
        json = body.isEmpty
            ? <String, Object?>{}
            : jsonDecode(body) as Map<String, Object?>;
      } on FormatException {
        // ponytail: Proxmox auth errors may be plain text, while successful
        // responses are required to use the documented JSON envelope.
        if (response.statusCode >= 200 && response.statusCode < 300) rethrow;
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = json['data'];
        return ConnectionTestResult(
          ok: true,
          status: 'ok',
          message: data is Map
              ? 'Connected. Version: ${data['version'] ?? 'unknown'}'
              : 'Connected.',
        );
      }

      return ConnectionTestResult(
        ok: false,
        status: 'critical',
        message:
            'HTTP ${response.statusCode}: ${json['errors'] ?? json['message'] ?? body}',
      );
    } on Object catch (error) {
      return ConnectionTestResult(
        ok: false,
        status: 'critical',
        message: error.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }
}

class ConnectionTestResult {
  const ConnectionTestResult({
    required this.ok,
    required this.status,
    required this.message,
  });

  final bool ok;
  final String status;
  final String message;
}
