import 'dart:io';

import 'core/http/http_helpers.dart';
import 'core/security/credentials_cipher.dart';
import 'core/store/app_store.dart';
import 'features/audit/audit_service.dart';
import 'features/auth/auth_service.dart';
import 'features/collection/collection_service.dart';
import 'features/dashboard/dashboard_service.dart';
import 'features/integrations/infrastructure_read_service.dart';
import 'features/integrations/proxmox_api_client.dart';
import 'features/settings/settings_service.dart';
import 'features/sources/source_connection_tester.dart';
import 'features/sources/sources_service.dart';
import 'features/users/user.dart';
import 'features/users/users_service.dart';

class App {
  App._({
    required this.store,
    required this.audit,
    required this.auth,
    required this.users,
    required this.sources,
    required this.dashboard,
    required this.infrastructure,
    required this.settings,
    required this.collection,
  });

  final AppStore store;
  final AuditService audit;
  final AuthService auth;
  final UsersService users;
  final SourcesService sources;
  final DashboardService dashboard;
  final InfrastructureReadService infrastructure;
  final SettingsService settings;
  final CollectionService collection;

  static Future<App> bootstrap({
    required AppStore store,
    required CredentialsCipher credentialsCipher,
  }) async {
    await store.load();
    final audit = AuditService(store.auditEvents);
    final users = UsersService(store, audit);
    final auth = AuthService(store, users, audit);
    final bool allowInsecureTls =
        (Platform.environment['ALLOW_INSECURE_TLS'] ?? 'true').toLowerCase() ==
            'true';
    final proxmoxClient = ProxmoxApiClient(allowInsecureTls: allowInsecureTls);
    final sourcesService = SourcesService(
      store,
      audit,
      credentialsCipher,
      SourceConnectionTester(allowInsecureTls: allowInsecureTls),
    );
    final infrastructure =
        InfrastructureReadService(sourcesService, proxmoxClient);
    final collection = CollectionService(store, infrastructure, audit);
    final app = App._(
      store: store,
      audit: audit,
      auth: auth,
      users: users,
      sources: sourcesService,
      dashboard: DashboardService(store),
      infrastructure: infrastructure,
      settings: SettingsService(store, audit),
      collection: collection,
    );
    await auth.bootstrapAdmin();
    await collection.prune();
    collection.start();
    return app;
  }

  Future<void> handle(HttpRequest request) async {
    applyDefaultHeaders(request);

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    try {
      await _route(request);
    } on AuthException catch (error) {
      await sendJson(request, {'error': error.code},
          statusCode: HttpStatus.unauthorized);
    } on UserInputException catch (error) {
      await sendJson(request, {'error': error.code},
          statusCode: _statusForInputError(error.code));
    } on SourceInputException catch (error) {
      await sendJson(request, {'error': error.code},
          statusCode: _statusForInputError(error.code));
    } on InfrastructureReadException catch (error) {
      await sendJson(request, {'error': error.code},
          statusCode: _statusForInputError(error.code));
    } on SettingsInputException catch (error) {
      await sendJson(request, {'error': error.code},
          statusCode: _statusForInputError(error.code));
    } on ProxmoxApiException catch (error) {
      await sendJson(request, {'error': error.message},
          statusCode: HttpStatus.badGateway);
    } catch (error, stackTrace) {
      stderr.writeln(error);
      stderr.writeln(stackTrace);
      await sendJson(request, {'error': 'internal_error'},
          statusCode: HttpStatus.internalServerError);
    }
  }

  Future<void> _route(HttpRequest request) async {
    final path = request.uri.path;
    final method = request.method;

    if (method == 'GET' && path == '/api/health') {
      return sendJson(request, {
        'status': 'ok',
        'service': 'neotelecom-backend',
        'version': '0.1.0',
        'time': DateTime.now().toUtc().toIso8601String(),
      });
    }

    if (method == 'POST' && path == '/api/auth/login') {
      final body = await readJson(request);
      final session = await auth.login(
          body['email'] as String? ?? '', body['password'] as String? ?? '');
      return sendJson(request,
          {'token': session.token, 'user': session.user.toPublicJson()});
    }

    final token = bearerToken(request);
    final currentUser = auth.authenticate(token);
    if (currentUser == null) {
      return sendJson(request, {'error': 'unauthorized'},
          statusCode: HttpStatus.unauthorized);
    }

    if (method == 'POST' && path == '/api/auth/logout') {
      await auth.logout(token!, currentUser);
      return sendJson(request, {'ok': true});
    }

    if (method == 'GET' && path == '/api/me') {
      return sendJson(request, {'user': currentUser.toPublicJson()});
    }

    if (method == 'PATCH' && path == '/api/me') {
      final body = await readJson(request);
      final user = await users.updateDisplayName(
        actorUserId: currentUser.id,
        userId: currentUser.id,
        displayName: body['displayName'] as String? ?? '',
      );
      return sendJson(request, {'user': user.toPublicJson()});
    }

    if (method == 'GET' && path == '/api/dashboard/summary') {
      return sendJson(request, dashboard.summary());
    }

    if (method == 'GET' && path == '/api/settings') {
      return sendJson(request, {'settings': settings.current.toJson()});
    }

    if (method == 'PATCH' && path == '/api/settings') {
      final body = await readJson(request);
      final updated = await settings.update(
        actorUserId: currentUser.id,
        collectionIntervalMinutes:
            body['collectionIntervalMinutes'] as int? ?? 30,
      );
      await collection.restart();
      return sendJson(request, {'settings': updated.toJson()});
    }

    if (method == 'GET' && path == '/api/users') {
      return sendJson(request,
          {'items': users.list().map((user) => user.toPublicJson()).toList()});
    }

    if (method == 'POST' && path == '/api/users') {
      final body = await readJson(request);
      final user = await users.create(
        actorUserId: currentUser.id,
        email: body['email'] as String? ?? '',
        displayName: body['displayName'] as String? ?? '',
        password: body['password'] as String? ?? '',
      );
      return sendJson(request, {'user': user.toPublicJson()},
          statusCode: HttpStatus.created);
    }

    final userAction =
        RegExp(r'^/api/users/([^/]+)/(activate|deactivate|change-password)$')
            .firstMatch(path);
    if (userAction != null && method == 'POST') {
      final userId = userAction.group(1)!;
      final action = userAction.group(2)!;
      final User user;
      if (action == 'activate') {
        user =
            await users.activate(actorUserId: currentUser.id, userId: userId);
      } else if (action == 'deactivate') {
        user =
            await users.deactivate(actorUserId: currentUser.id, userId: userId);
      } else {
        final body = await readJson(request);
        user = await users.changePassword(
          actorUserId: currentUser.id,
          userId: userId,
          password: body['password'] as String? ?? '',
        );
      }
      return sendJson(request, {'user': user.toPublicJson()});
    }

    final userPatch = RegExp(r'^/api/users/([^/]+)$').firstMatch(path);
    if (userPatch != null && method == 'PATCH') {
      final body = await readJson(request);
      final user = await users.updateDisplayName(
        actorUserId: currentUser.id,
        userId: userPatch.group(1)!,
        displayName: body['displayName'] as String? ?? '',
      );
      return sendJson(request, {'user': user.toPublicJson()});
    }

    if (method == 'GET' && path == '/api/sources') {
      return sendJson(request, {
        'items': sources.list().map((source) => source.toPublicJson()).toList()
      });
    }

    if (method == 'POST' && path == '/api/sources') {
      final body = await readJson(request);
      final source = await sources.create(
        actorUserId: currentUser.id,
        name: body['name'] as String? ?? '',
        type: body['type'] as String? ?? '',
        baseUrl: body['baseUrl'] as String? ?? '',
        token: body['token'] as String? ?? '',
      );
      return sendJson(request, {'source': source.toPublicJson()},
          statusCode: HttpStatus.created);
    }

    final sourceAction =
        RegExp(r'^/api/sources/([^/]+)/test$').firstMatch(path);
    if (sourceAction != null && method == 'POST') {
      final testResponse = await sources.test(
          actorUserId: currentUser.id, sourceId: sourceAction.group(1)!);
      return sendJson(request, {
        'ok': testResponse.result.ok,
        'status': testResponse.result.status,
        'message': testResponse.result.message,
        'source': testResponse.source.toPublicJson(),
      });
    }

    final sourcePatch = RegExp(r'^/api/sources/([^/]+)$').firstMatch(path);
    if (sourcePatch != null && method == 'PATCH') {
      final body = await readJson(request);
      final source = await sources.update(
        actorUserId: currentUser.id,
        sourceId: sourcePatch.group(1)!,
        name: body['name'] as String?,
        type: body['type'] as String?,
        baseUrl: body['baseUrl'] as String?,
        token: body['token'] as String?,
      );
      return sendJson(request, {'source': source.toPublicJson()});
    }

    if (sourcePatch != null && method == 'DELETE') {
      await sources.delete(
          actorUserId: currentUser.id, sourceId: sourcePatch.group(1)!);
      return sendJson(request, {'ok': true});
    }

    if (method == 'GET' && path == '/api/audit-events') {
      return sendJson(request, {'items': audit.latest()});
    }

    if (method == 'GET' && path == '/api/data-snapshots') {
      final String? sourceId = request.uri.queryParameters['sourceId'];
      return sendJson(request, {
        'items': collection
            .latest(sourceId: sourceId)
            .map((snapshot) => snapshot.toJson())
            .toList(),
      });
    }

    if (method == 'POST' && path == '/api/data-snapshots/collect') {
      await collection.collectAll(actorUserId: currentUser.id);
      return sendJson(request, {'ok': true});
    }

    final veRoute = RegExp(
      r'^/api/proxmox-ve/([^/]+)/(nodes|resources|node-resources|vm-resources|storage-resources|node-statuses|node-guests|node-storage|tasks)$',
    ).firstMatch(path);
    if (veRoute != null && method == 'GET') {
      final String sourceId = veRoute.group(1)!;
      final String dataType = veRoute.group(2)!;
      final Object? data = switch (dataType) {
        'nodes' => await infrastructure.proxmoxVeNodes(sourceId),
        'resources' => await infrastructure.proxmoxVeResources(sourceId),
        'node-resources' =>
          await infrastructure.proxmoxVeNodeResources(sourceId),
        'vm-resources' => await infrastructure.proxmoxVeVmResources(sourceId),
        'storage-resources' =>
          await infrastructure.proxmoxVeStorageResources(sourceId),
        'node-statuses' => await infrastructure.proxmoxVeNodeStatuses(sourceId),
        'node-guests' => await infrastructure.proxmoxVeNodeGuests(sourceId),
        'node-storage' => await infrastructure.proxmoxVeNodeStorage(sourceId),
        'tasks' => await infrastructure.proxmoxVeTasks(sourceId),
        _ => null,
      };
      return sendJson(request, {'data': data});
    }

    final veGuestRoute = RegExp(
      r'^/api/proxmox-ve/([^/]+)/nodes/([^/]+)/(qemu|lxc)/([^/]+)/status/current$',
    ).firstMatch(path);
    if (veGuestRoute != null && method == 'GET') {
      return sendJson(request, {
        'data': await infrastructure.proxmoxVeGuestStatus(
          veGuestRoute.group(1)!,
          Uri.decodeComponent(veGuestRoute.group(2)!),
          veGuestRoute.group(3)!,
          veGuestRoute.group(4)!,
        ),
      });
    }

    final pbsRoute = RegExp(
      r'^/api/proxmox-backup/([^/]+)/(datastores|tasks)$',
    ).firstMatch(path);
    if (pbsRoute != null && method == 'GET') {
      final String sourceId = pbsRoute.group(1)!;
      final String dataType = pbsRoute.group(2)!;
      final Object? data = switch (dataType) {
        'datastores' => await infrastructure.proxmoxBackupDatastores(sourceId),
        'tasks' => await infrastructure.proxmoxBackupTasks(sourceId),
        _ => null,
      };
      return sendJson(request, {'data': data});
    }

    final pbsSnapshotsRoute = RegExp(
      r'^/api/proxmox-backup/([^/]+)/datastores/([^/]+)/snapshots$',
    ).firstMatch(path);
    if (pbsSnapshotsRoute != null && method == 'GET') {
      return sendJson(request, {
        'data': await infrastructure.proxmoxBackupSnapshots(
          pbsSnapshotsRoute.group(1)!,
          Uri.decodeComponent(pbsSnapshotsRoute.group(2)!),
        ),
      });
    }

    return sendJson(request, {'error': 'not_found', 'path': path},
        statusCode: HttpStatus.notFound);
  }
}

int _statusForInputError(String code) {
  return switch (code) {
    'user_not_found' || 'source_not_found' => HttpStatus.notFound,
    'source_type_mismatch' ||
    'invalid_guest_type' ||
    'invalid_settings_payload' =>
      HttpStatus.badRequest,
    'email_already_exists' => HttpStatus.conflict,
    _ => HttpStatus.badRequest,
  };
}
