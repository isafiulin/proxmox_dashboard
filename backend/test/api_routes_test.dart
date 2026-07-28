import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:neotelecom_backend/app.dart';
import 'package:neotelecom_backend/core/logging/app_logger.dart';
import 'package:neotelecom_backend/core/security/credentials_cipher.dart';
import 'package:neotelecom_backend/core/store/json_store.dart';
import 'package:test/test.dart';

void main() {
  late ApiTestHarness harness;

  setUp(() async {
    harness = await ApiTestHarness.start();
  });

  tearDown(() async {
    await harness.close();
  });

  test('rejects unauthenticated protected route', () async {
    final TestResponse response = await harness.request('GET', '/users');

    expect(response.statusCode, HttpStatus.unauthorized);
    expect(response.json['error'], 'unauthorized');
  });

  test('health returns observability metadata without auth', () async {
    final TestResponse response = await harness.request('GET', '/health');

    expect(response.statusCode, HttpStatus.ok);
    expect(response.json['status'], 'ok');
    expect(response.json['service'], 'neotelecom-backend');
    expect(response.json['storeDriver'], 'json');
    expect(response.json['databaseStatus'], 'ok');
    expect(response.json['backendVersion'], isA<String>());
    expect(response.json['frontendVersion'], isA<String>());
    expect(response.json['backendVersion'], '0.3.6');
    expect(response.json['frontendVersion'], '1.2.2+11');
    expect(response.json['gitCommit'], isA<String>());
    expect(response.json['uptimeSeconds'], isA<int>());
    expect(response.json['collectionIntervalMinutes'], isA<int>());
  });

  test('login returns current admin user', () async {
    final TestResponse response = await harness.request(
      'POST',
      '/auth/login',
      body: <String, Object?>{
        'email': 'admin@example.local',
        'password': 'admin12345',
      },
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(response.json['token'], isNotEmpty);
    expect((response.json['user']! as Map<String, Object?>)['role'], 'admin');
  });

  test('JSON responses are UTF-8 encoded', () async {
    final String token = await harness.loginToken();
    final TestResponse response = await harness.request(
      'POST',
      '/users',
      token: token,
      body: <String, Object?>{
        'email': 'unicode@example.local',
        'displayName': 'Оператор · Бишкек',
        'password': 'password123',
      },
    );

    expect(response.statusCode, HttpStatus.created);
    expect(
      (response.json['user']! as Map<String, Object?>)['displayName'],
      'Оператор · Бишкек',
    );
  });

  test('authenticated admin can create user and source', () async {
    final String token = await harness.loginToken();

    final TestResponse userResponse = await harness.request(
      'POST',
      '/users',
      token: token,
      body: <String, Object?>{
        'email': 'ops@example.local',
        'displayName': 'Ops',
        'password': 'password123',
      },
    );
    expect(userResponse.statusCode, HttpStatus.created);

    final TestResponse sourceResponse = await harness.request(
      'POST',
      '/sources',
      token: token,
      body: <String, Object?>{
        'name': 'pve-main',
        'type': 'proxmox_ve',
        'baseUrl': 'https://pve.example.local:8006',
        'token': 'secret-token',
      },
    );
    expect(sourceResponse.statusCode, HttpStatus.created);

    final TestResponse sourcesResponse =
        await harness.request('GET', '/sources', token: token);
    final List<Object?> items = sourcesResponse.json['items']! as List<Object?>;
    expect(items, hasLength(1));
  });

  test('authenticated admin can update settings and own profile', () async {
    final String token = await harness.loginToken();

    final TestResponse settingsResponse = await harness.request(
      'PATCH',
      '/settings',
      token: token,
      body: <String, Object?>{
        'collectionIntervalMinutes': 15,
        'telegramEnabled': false,
        'telegramBotToken': '123456789:abcdefghijklmnopqrstuvwx',
        'telegramChatId': '-1001234567890',
        'telegramMinimumSeverity': 'critical',
        'telegramNotifyRecovery': true,
      },
    );
    expect(settingsResponse.statusCode, HttpStatus.ok);
    expect(
      (settingsResponse.json['settings']!
          as Map<String, Object?>)['collectionIntervalMinutes'],
      15,
    );
    final settings = settingsResponse.json['settings']! as Map<String, Object?>;
    expect(settings['hasTelegramBotToken'], isTrue);
    expect(settings['telegramChatId'], '-1001234567890');
    expect(settings['telegramMinimumSeverity'], 'critical');
    expect(settings, isNot(contains('telegramBotTokenCiphertext')));
    expect(settings.toString(), isNot(contains('abcdefghijklmnopqrstuvwx')));

    final TestResponse profileResponse = await harness.request(
      'PATCH',
      '/me',
      token: token,
      body: <String, Object?>{'displayName': 'Root Admin'},
    );
    expect(profileResponse.statusCode, HttpStatus.ok);
    expect(
      (profileResponse.json['user']! as Map<String, Object?>)['displayName'],
      'Root Admin',
    );
  });

  test('authenticated admin can read collection metrics', () async {
    final String token = await harness.loginToken();
    final response = await harness.request(
      'GET',
      '/collection-metrics',
      token: token,
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(response.json['sources'], isA<List<Object?>>());
    expect(response.json['totalPolls'], isA<int>());
    expect(response.json['totalErrors'], isA<int>());
  });

  test('telegram test requires saved bot configuration', () async {
    final token = await harness.loginToken();
    final response = await harness.request(
      'POST',
      '/settings/telegram/test',
      token: token,
    );

    expect(response.statusCode, HttpStatus.badGateway);
    expect(response.json['error'], 'telegram_not_configured');
  });

  test('authenticated admin can edit source metadata', () async {
    final String token = await harness.loginToken();

    final TestResponse sourceResponse = await harness.request(
      'POST',
      '/sources',
      token: token,
      body: <String, Object?>{
        'name': 'pve-main',
        'type': 'proxmox_ve',
        'baseUrl': 'https://pve.example.local:8006',
        'token': 'secret-token',
      },
    );
    final source = sourceResponse.json['source']! as Map<String, Object?>;

    final TestResponse updateResponse = await harness.request(
      'PATCH',
      '/sources/${source['id']}',
      token: token,
      body: <String, Object?>{
        'name': 'pve-renamed',
        'type': 'proxmox_backup',
        'baseUrl': 'https://pve2.example.local:8006',
        'token': '',
      },
    );
    expect(updateResponse.statusCode, HttpStatus.ok);
    expect(
      (updateResponse.json['source']! as Map<String, Object?>)['name'],
      'pve-renamed',
    );
    expect(
      (updateResponse.json['source']! as Map<String, Object?>)['type'],
      'proxmox_backup',
    );
  });
}

class ApiTestHarness {
  ApiTestHarness._({
    required this.tempDir,
    required this.server,
    required this.baseUri,
    required this.serverSubscription,
  });

  final Directory tempDir;
  final HttpServer server;
  final Uri baseUri;
  final Future<void> serverSubscription;

  static Future<ApiTestHarness> start() async {
    final Directory tempDir =
        await Directory.systemTemp.createTemp('neotelecom_api_test_');
    final JsonStore store = JsonStore(File('${tempDir.path}/store.json'));
    final App app = await App.bootstrap(
      store: store,
      storeDriver: 'json',
      credentialsCipher: CredentialsCipher('test-credentials-key'),
      logger: const AppLogger(enabled: false),
    );
    final HttpServer server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final Uri baseUri =
        Uri.parse('http://${server.address.host}:${server.port}/api');

    return ApiTestHarness._(
      tempDir: tempDir,
      server: server,
      baseUri: baseUri,
      serverSubscription: _serve(server, app),
    );
  }

  Future<void> close() async {
    await server.close(force: true);
    await serverSubscription.catchError((Object _) {});
    await tempDir.delete(recursive: true);
  }

  Future<String> loginToken() async {
    final TestResponse response = await request(
      'POST',
      '/auth/login',
      body: <String, Object?>{
        'email': 'admin@example.local',
        'password': 'admin12345',
      },
    );
    return response.json['token']! as String;
  }

  Future<TestResponse> request(
    String method,
    String path, {
    String? token,
    Map<String, Object?> body = const <String, Object?>{},
  }) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client.openUrl(
        method,
        baseUri.replace(path: '${baseUri.path}$path'),
      );
      request.headers.contentType = ContentType.json;
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (method != 'GET') {
        request.write(jsonEncode(body));
      }
      final HttpClientResponse response = await request.close();
      final String rawBody = await utf8.decoder.bind(response).join();
      return TestResponse(
        statusCode: response.statusCode,
        json: rawBody.isEmpty
            ? <String, Object?>{}
            : jsonDecode(rawBody) as Map<String, Object?>,
      );
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> _serve(HttpServer server, App app) async {
    await for (final HttpRequest request in server) {
      await app.handle(request);
    }
  }
}

class TestResponse {
  const TestResponse({required this.statusCode, required this.json});

  final int statusCode;
  final Map<String, Object?> json;
}
