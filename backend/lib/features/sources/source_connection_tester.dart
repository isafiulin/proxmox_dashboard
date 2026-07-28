import 'dart:convert';
import 'dart:io';

import 'package:neotelecom_backend/features/integrations/proxmox_auth_header.dart';
import 'package:neotelecom_backend/features/integrations/redfish_api_client.dart';
import 'package:neotelecom_backend/features/integrations/old_ilo2_client.dart';
import 'package:neotelecom_backend/features/integrations/ipmi_client.dart';
import 'package:neotelecom_backend/features/sources/source.dart';

class SourceConnectionTester {
  SourceConnectionTester({
    required this.allowInsecureTls,
    required RedfishApiClient redfishClient,
    OldIlo2Client? oldIlo2Client,
    IpmiClient? ipmiClient,
  })  : _redfishClient = redfishClient,
        _oldIlo2Client = oldIlo2Client,
        _ipmiClient = ipmiClient;

  final bool allowInsecureTls;
  final RedfishApiClient _redfishClient;
  final OldIlo2Client? _oldIlo2Client;
  final IpmiClient? _ipmiClient;

  Future<ConnectionTestResult> test(Source source, String credential) async {
    if (source.type == 'proxmox_ve') {
      return _testProxmox(source, credential);
    }
    if (source.type == 'proxmox_backup') {
      return _testProxmox(source, credential);
    }
    if (source.type == 'redfish') {
      return _testRedfish(source, credential);
    }
    if (source.type == 'old_ilo2') {
      return _testOldIlo2(source, credential);
    }
    if (source.type == 'ipmi') {
      return _testIpmi(source, credential);
    }

    return const ConnectionTestResult(
      ok: false,
      status: 'critical',
      message: 'Unsupported source type.',
    );
  }

  Future<ConnectionTestResult> _testIpmi(
    Source source,
    String credential,
  ) async {
    final client = _ipmiClient;
    if (client == null) {
      return const ConnectionTestResult(
        ok: false,
        status: 'critical',
        message: 'IPMI client is not configured.',
      );
    }
    try {
      final output = await client.controllerInfo(source, credential);
      final product = RegExp(r'Product Name\s*:\s*(.+)')
          .firstMatch(output)
          ?.group(1)
          ?.trim();
      return ConnectionTestResult(
        ok: true,
        status: 'ok',
        message: 'Connected over IPMI${product == null ? '' : '. $product'}',
      );
    } on Object catch (error) {
      return ConnectionTestResult(
        ok: false,
        status: 'critical',
        message: error.toString(),
      );
    }
  }

  Future<ConnectionTestResult> _testOldIlo2(
    Source source,
    String credential,
  ) async {
    final client = _oldIlo2Client;
    if (client == null) {
      return const ConnectionTestResult(
        ok: false,
        status: 'critical',
        message: 'Old iLO 2 client is not configured.',
      );
    }
    try {
      final output = await client.systemSummary(source, credential);
      final model = RegExp(r'name=(.+)').firstMatch(output)?.group(1)?.trim();
      return ConnectionTestResult(
        ok: true,
        status: 'ok',
        message: 'Connected to old iLO 2${model == null ? '' : '. $model'}',
      );
    } on Object catch (error) {
      return ConnectionTestResult(
        ok: false,
        status: 'critical',
        message: error.toString(),
      );
    }
  }

  Future<ConnectionTestResult> _testRedfish(
    Source source,
    String credential,
  ) async {
    try {
      final root = await _redfishClient.get(
        source,
        credential,
        '/redfish/v1/',
      );
      final version = root['RedfishVersion']?.toString() ?? 'unknown';
      if (root['Systems'] is! Map || root['Chassis'] is! Map) {
        return const ConnectionTestResult(
          ok: false,
          status: 'critical',
          message: 'Redfish Service Root has no Systems or Chassis links.',
        );
      }
      return ConnectionTestResult(
        ok: true,
        status: 'ok',
        message: 'Connected. Redfish version: $version',
      );
    } on Object catch (error) {
      return ConnectionTestResult(
        ok: false,
        status: 'critical',
        message: error.toString(),
      );
    }
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
