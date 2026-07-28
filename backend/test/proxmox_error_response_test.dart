import 'dart:io';

import 'package:neotelecom_backend/core/logging/app_logger.dart';
import 'package:neotelecom_backend/core/security/credentials_cipher.dart';
import 'package:neotelecom_backend/features/integrations/proxmox_api_client.dart';
import 'package:neotelecom_backend/features/integrations/redfish_api_client.dart';
import 'package:neotelecom_backend/features/sources/source.dart';
import 'package:neotelecom_backend/features/sources/source_connection_tester.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late Future<void> serving;
  late Source source;
  var responseStatus = HttpStatus.unauthorized;
  var responseBody = 'authentication failed - invalid credentials';
  var requestCount = 0;

  setUp(() async {
    responseStatus = HttpStatus.unauthorized;
    responseBody = 'authentication failed - invalid credentials';
    requestCount = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    serving = () async {
      await for (final request in server) {
        requestCount += 1;
        request.response
          ..statusCode = responseStatus
          ..write(responseBody);
        await request.response.close();
      }
    }();
    final now = DateTime.now().toUtc();
    source = Source(
      id: 'pbs-test',
      name: 'PBS',
      type: 'proxmox_backup',
      baseUrl: 'http://${server.address.host}:${server.port}',
      credential: const EncryptedSecret(ciphertext: '', nonce: '', mac: ''),
      status: 'new',
      createdAt: now,
      updatedAt: now,
    );
  });

  tearDown(() async {
    await server.close(force: true);
    await serving;
  });

  test('API client preserves status and plain-text Proxmox auth error',
      () async {
    final client = ProxmoxApiClient(
      allowInsecureTls: false,
      logger: const AppLogger(enabled: false),
    );

    await expectLater(
      client.getBackup(source, 'root@pam!api:wrong', '/api2/json/version'),
      throwsA(
        isA<ProxmoxApiException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having(
              (error) => error.message,
              'message',
              contains('authentication failed - invalid credentials'),
            ),
      ),
    );
  });

  test('connection test reports plain-text Proxmox auth error', () async {
    final result = await SourceConnectionTester(
      allowInsecureTls: false,
      redfishClient: RedfishApiClient(
        allowInsecureTls: false,
        logger: const AppLogger(enabled: false),
      ),
    ).test(source, 'root@pam!api:wrong');

    expect(result.ok, isFalse);
    expect(result.message, contains('HTTP 401'));
    expect(
      result.message,
      contains('authentication failed - invalid credentials'),
    );
  });

  test('API client combines and briefly caches identical requests', () async {
    responseStatus = HttpStatus.ok;
    responseBody = '{"data":[{"node":"pbs"}]}';
    final client = ProxmoxApiClient(
      allowInsecureTls: false,
      logger: const AppLogger(enabled: false),
    );

    final results = await Future.wait(<Future<Object?>>[
      client.getBackup(source, 'root@pam!api:secret', '/api2/json/nodes'),
      client.getBackup(source, 'root@pam!api:secret', '/api2/json/nodes'),
    ]);
    await client.getBackup(
      source,
      'root@pam!api:secret',
      '/api2/json/nodes',
    );

    expect(results, hasLength(2));
    expect(requestCount, 1);
  });
}
