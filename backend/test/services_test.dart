import 'dart:io';

import 'package:neotelecom_backend/core/security/credentials_cipher.dart';
import 'package:neotelecom_backend/core/store/json_store.dart';
import 'package:neotelecom_backend/core/store/postgres_store.dart';
import 'package:neotelecom_backend/core/logging/app_logger.dart';
import 'package:neotelecom_backend/features/integrations/proxmox_auth_header.dart';
import 'package:neotelecom_backend/features/integrations/redfish_api_client.dart';
import 'package:neotelecom_backend/features/audit/audit_service.dart';
import 'package:neotelecom_backend/features/auth/auth_service.dart';
import 'package:neotelecom_backend/features/collection/collection_service.dart';
import 'package:neotelecom_backend/features/collection/data_snapshot.dart';
import 'package:neotelecom_backend/features/sources/source_connection_tester.dart';
import 'package:neotelecom_backend/features/sources/sources_service.dart';
import 'package:neotelecom_backend/features/users/users_service.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late JsonStore store;
  late AuditService audit;
  late UsersService users;
  late AuthService auth;
  late SourcesService sources;
  late CredentialsCipher credentialsCipher;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('neotelecom_backend_test_');
    store = JsonStore(File('${tempDir.path}/store.json'));
    await store.load();
    audit = AuditService(store.auditEvents);
    credentialsCipher = CredentialsCipher('test-credentials-key');
    users = UsersService(store, audit);
    auth = AuthService(store, users, audit);
    sources = SourcesService(
      store,
      audit,
      credentialsCipher,
      SourceConnectionTester(
        allowInsecureTls: true,
        redfishClient: RedfishApiClient(
          allowInsecureTls: true,
          logger: const AppLogger(enabled: false),
        ),
      ),
    );
    await auth.bootstrapAdmin();
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('bootstrap creates one active admin user', () {
    expect(users.list(), hasLength(1));
    expect(users.list().single.email, 'admin@example.local');
    expect(users.list().single.role, 'admin');
    expect(users.list().single.isActive, isTrue);
  });

  test('login returns session for bootstrap admin', () async {
    final session = await auth.login('admin@example.local', 'admin12345');

    expect(session.token, isNotEmpty);
    expect(session.user.email, 'admin@example.local');
    expect(auth.authenticate(session.token), isNotNull);
  });

  test('admin can create another admin user', () async {
    final actor = users.list().single;
    final created = await users.create(
      actorUserId: actor.id,
      email: 'ops@example.local',
      displayName: 'Ops Admin',
      password: 'password123',
    );

    expect(created.role, 'admin');
    expect(users.list(), hasLength(2));
    expect(audit.latest().first['action'], 'user.create');
  });

  test('cannot deactivate current or last admin', () async {
    final actor = users.list().single;

    await expectLater(
      users.deactivate(actorUserId: actor.id, userId: actor.id),
      throwsA(isA<UserInputException>()),
    );
  });

  test('source service validates and stores infrastructure source', () async {
    final actor = users.list().single;
    final source = await sources.create(
      actorUserId: actor.id,
      name: 'pve-main',
      type: 'proxmox_ve',
      baseUrl: 'https://pve.example.local:8006',
      token: 'secret-token',
    );

    expect(source.name, 'pve-main');
    expect(source.hasToken, isTrue);
    expect(await sources.credentialFor(source.id), 'secret-token');
    expect(sources.list(), hasLength(1));
  });

  test('source service rejects invalid URL', () async {
    final actor = users.list().single;

    await expectLater(
      sources.create(
        actorUserId: actor.id,
        name: 'broken',
        type: 'proxmox_ve',
        baseUrl: 'not-a-url',
        token: '',
      ),
      throwsA(isA<SourceInputException>()),
    );
  });

  test('source service accepts HTTPS redfish source with basic credentials',
      () async {
    final actor = users.list().single;

    final source = await sources.create(
      actorUserId: actor.id,
      name: 'ibmc-main',
      type: 'redfish',
      baseUrl: 'https://ibmc.example.local',
      token: 'monitor:secret-password',
    );

    expect(source.type, 'redfish');
    expect(await sources.credentialFor(source.id), 'monitor:secret-password');
  });

  test('source service validates redfish transport and credentials', () async {
    final actor = users.list().single;

    await expectLater(
      sources.create(
        actorUserId: actor.id,
        name: 'ibmc-main',
        type: 'redfish',
        baseUrl: 'http://ibmc.example.local',
        token: 'monitor:secret-password',
      ),
      throwsA(isA<SourceInputException>()),
    );
    await expectLater(
      sources.create(
        actorUserId: actor.id,
        name: 'ibmc-main',
        type: 'redfish',
        baseUrl: 'https://ibmc.example.local',
        token: 'missing-password-separator',
      ),
      throwsA(isA<SourceInputException>()),
    );
  });

  test('collection retention keeps only the last seven days', () {
    final now = DateTime.utc(2026, 6, 4, 12);
    final snapshots = <DataSnapshot>[
      DataSnapshot(
        id: 'old',
        sourceId: 'source-1',
        sourceType: 'proxmox_ve',
        status: 'ok',
        payload: const <String, Object?>{},
        collectedAt: now.subtract(const Duration(days: 8)),
      ),
      DataSnapshot(
        id: 'edge',
        sourceId: 'source-1',
        sourceType: 'proxmox_ve',
        status: 'ok',
        payload: const <String, Object?>{},
        collectedAt: now.subtract(const Duration(days: 7)),
      ),
      DataSnapshot(
        id: 'new',
        sourceId: 'source-1',
        sourceType: 'proxmox_ve',
        status: 'ok',
        payload: const <String, Object?>{},
        collectedAt: now.subtract(const Duration(minutes: 30)),
      ),
    ];

    pruneExpiredSnapshots(snapshots, now: now);

    expect(snapshots.map((snapshot) => snapshot.id), <String>['edge', 'new']);
  });

  test('incremental store writes only records not saved before', () {
    final rows = <Map<String, Object?>>[
      <String, Object?>{'id': 'old'},
      <String, Object?>{'id': 'new'},
    ];

    expect(
      unsavedItems(rows, <String>{'old'}, (row) => row['id']),
      <Map<String, Object?>>[
        <String, Object?>{'id': 'new'},
      ],
    );
  });

  test('redfish dashboard selects newest successful snapshot', () {
    final older = DataSnapshot(
      id: 'older',
      sourceId: 'bmc-1',
      sourceType: 'redfish',
      status: 'ok',
      payload: const <String, Object?>{'model': 'old'},
      collectedAt: DateTime.utc(2026, 6, 4, 10),
    );
    final failed = DataSnapshot(
      id: 'failed',
      sourceId: 'bmc-1',
      sourceType: 'redfish',
      status: 'critical',
      payload: const <String, Object?>{'error': 'connection reset'},
      collectedAt: DateTime.utc(2026, 6, 4, 11),
    );
    final newer = DataSnapshot(
      id: 'newer',
      sourceId: 'bmc-1',
      sourceType: 'redfish',
      status: 'ok',
      payload: const <String, Object?>{'model': 'new'},
      collectedAt: DateTime.utc(2026, 6, 4, 12),
    );

    expect(
      latestSuccessfulSnapshot(
        <DataSnapshot>[older, failed, newer],
        'bmc-1',
        'redfish',
      )?.id,
      'newer',
    );
  });

  test('proxmox auth header uses PBS token separator', () {
    expect(
      proxmoxAuthHeader(
        sourceType: 'proxmox_ve',
        credential: 'root@pam!testing=secret',
      ),
      'PVEAPIToken=root@pam!testing=secret',
    );
    expect(
      proxmoxAuthHeader(
        sourceType: 'proxmox_backup',
        credential: 'root@pam!testing=secret',
      ),
      'PBSAPIToken=root@pam!testing:secret',
    );
    expect(
      proxmoxAuthHeader(
        sourceType: 'proxmox_backup',
        credential: 'root@pam!testing:secret',
      ),
      'PBSAPIToken=root@pam!testing:secret',
    );
  });
}
