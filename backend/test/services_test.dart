import 'dart:io';

import 'package:neotelecom_backend/core/security/credentials_cipher.dart';
import 'package:neotelecom_backend/core/store/json_store.dart';
import 'package:neotelecom_backend/features/integrations/proxmox_auth_header.dart';
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
      SourceConnectionTester(allowInsecureTls: true),
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

  test('source service rejects redfish while feature is disabled', () async {
    final actor = users.list().single;

    await expectLater(
      sources.create(
        actorUserId: actor.id,
        name: 'ilo-main',
        type: 'redfish',
        baseUrl: 'https://ilo.example.local',
        token: 'secret-token',
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
