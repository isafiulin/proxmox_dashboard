import 'dart:io';

import 'package:neotelecom_backend/app.dart';
import 'package:neotelecom_backend/core/security/credentials_cipher.dart';
import 'package:neotelecom_backend/core/store/app_store.dart';
import 'package:neotelecom_backend/core/store/json_store.dart';
import 'package:neotelecom_backend/core/store/postgres_store.dart';

Future<void> main() async {
  final store = await _createStore();
  final app = await App.bootstrap(
    store: store,
    credentialsCipher: CredentialsCipher.fromEnvironment(),
  );

  final port = int.tryParse(Platform.environment['BACKEND_PORT'] ?? '') ?? 8080;
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);

  print('NeoTelecom backend listening on :$port');

  await for (final request in server) {
    await app.handle(request);
  }
}

Future<AppStore> _createStore() async {
  final driver = Platform.environment['STORE_DRIVER'] ?? 'json';
  if (driver == 'postgres') {
    final databaseUrl = Platform.environment['DATABASE_URL'];
    if (databaseUrl == null || databaseUrl.isEmpty) {
      throw StateError('DATABASE_URL is required when STORE_DRIVER=postgres');
    }
    return PostgresStore.connect(databaseUrl);
  }

  return JsonStore(
      File(Platform.environment['STORE_PATH'] ?? 'data/store.json'));
}
