import 'dart:async';
import 'dart:io';

import 'package:neotelecom_backend/app.dart';
import 'package:neotelecom_backend/core/logging/app_logger.dart';
import 'package:neotelecom_backend/core/security/credentials_cipher.dart';
import 'package:neotelecom_backend/core/store/app_store.dart';
import 'package:neotelecom_backend/core/store/json_store.dart';
import 'package:neotelecom_backend/core/store/postgres_store.dart';

Future<void> main() async {
  final logger = AppLogger(
    enabled: (Platform.environment['LOG_ENABLED'] ?? 'true').toLowerCase() !=
        'false',
  );
  final storeDriver = Platform.environment['STORE_DRIVER'] ?? 'json';
  final store = await _createStore(storeDriver);
  final app = await App.bootstrap(
    store: store,
    storeDriver: storeDriver,
    credentialsCipher: CredentialsCipher.fromEnvironment(),
    logger: logger,
  );

  final port = int.tryParse(Platform.environment['BACKEND_PORT'] ?? '') ?? 8080;
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);

  logger.info('backend.started', <String, Object?>{
    'port': port,
    'storeDriver': storeDriver,
  });

  await for (final request in server) {
    // ponytail: requests are independent; App.handle owns error responses.
    // Keep this concurrent unless mutable request-scoped state is introduced.
    unawaited(app.handle(request));
  }
}

Future<AppStore> _createStore(String driver) async {
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
