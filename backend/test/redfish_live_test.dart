import 'dart:io';

import 'package:neotelecom_backend/core/logging/app_logger.dart';
import 'package:neotelecom_backend/core/security/credentials_cipher.dart';
import 'package:neotelecom_backend/features/integrations/redfish_api_client.dart';
import 'package:neotelecom_backend/features/sources/source.dart';
import 'package:test/test.dart';

void main() {
  final baseUrl = Platform.environment['REDFISH_TEST_URL'] ?? '';
  final credential = Platform.environment['REDFISH_TEST_CREDENTIAL'] ?? '';

  test(
    'reads inventory from a live Redfish server',
    () async {
      final now = DateTime.now().toUtc();
      final source = Source(
        id: 'live-redfish',
        name: 'Live Redfish',
        type: 'redfish',
        baseUrl: baseUrl,
        credential: const EncryptedSecret(ciphertext: '', nonce: '', mac: ''),
        status: 'new',
        createdAt: now,
        updatedAt: now,
      );
      final inventory = await RedfishApiClient(
        allowInsecureTls: true,
        logger: const AppLogger(enabled: false),
      ).inventory(source, credential);

      expect(inventory['systems'], isNotEmpty);
      expect(inventory['chassis'], isNotEmpty);
      expect(inventory['managers'], isNotEmpty);
      expect(inventory['processors'], isA<List<Object?>>());
      expect(inventory['memory'], isA<List<Object?>>());
      expect(inventory['drives'], isA<List<Object?>>());
      expect(inventory['logEntries'], isA<List<Object?>>());
    },
    skip: baseUrl.isEmpty || credential.isEmpty
        ? 'Set REDFISH_TEST_URL and REDFISH_TEST_CREDENTIAL to run.'
        : false,
  );
}
