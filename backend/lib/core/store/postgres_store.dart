import 'dart:convert';

import 'package:neotelecom_backend/core/store/app_store.dart';
import 'package:neotelecom_backend/features/collection/data_snapshot.dart';
import 'package:neotelecom_backend/features/settings/system_settings.dart';
import 'package:neotelecom_backend/features/sources/source.dart';
import 'package:neotelecom_backend/features/users/user.dart';
import 'package:postgres/postgres.dart';

class PostgresStore implements AppStore {
  PostgresStore(this._connection);

  final Connection _connection;
  Future<void> _saveQueue = Future<void>.value();
  String _savedSnapshotIds = '';

  @override
  final users = <User>[];

  @override
  final sources = <Source>[];

  @override
  final auditEvents = <Map<String, Object?>>[];

  @override
  final dataSnapshots = <DataSnapshot>[];

  @override
  SystemSettings settings = SystemSettings.defaults();

  static Future<PostgresStore> connect(String databaseUrl) async {
    final connection = await Connection.openFromUrl(databaseUrl);
    return PostgresStore(connection);
  }

  @override
  Future<void> load() async {
    await _migrate();
    await _loadUsers();
    await _loadSources();
    await _loadAuditEvents();
    await _loadDataSnapshots();
    await _loadSettings();
    _savedSnapshotIds = _snapshotIds();
  }

  @override
  Future<void> save() {
    final next = _saveQueue.then((_) => _save());
    _saveQueue = next.onError((_, __) {});
    return next;
  }

  Future<void> _save() async {
    final snapshotIds = _snapshotIds();
    final snapshotsChanged = snapshotIds != _savedSnapshotIds;
    await _connection.runTx((Session session) async {
      await session.execute('DELETE FROM audit_events');
      if (snapshotsChanged) {
        await session.execute('DELETE FROM data_snapshots');
      }
      await session.execute('DELETE FROM system_settings');
      await session.execute('DELETE FROM sources');
      await session.execute('DELETE FROM users');

      for (final User user in users) {
        await session.execute(
          Sql.named('''
            INSERT INTO users (
              id, email, display_name, role, password_salt, password_hash,
              is_active, last_login_at, created_at, updated_at
            ) VALUES (
              @id, @email, @displayName, @role, @passwordSalt, @passwordHash,
              @isActive, @lastLoginAt, @createdAt, @updatedAt
            )
          '''),
          parameters: <String, Object?>{
            'id': user.id,
            'email': user.email,
            'displayName': user.displayName,
            'role': user.role,
            'passwordSalt': user.passwordSalt,
            'passwordHash': user.passwordHash,
            'isActive': user.isActive,
            'lastLoginAt': user.lastLoginAt,
            'createdAt': user.createdAt,
            'updatedAt': user.updatedAt,
          },
        );
      }

      for (final Source source in sources) {
        await session.execute(
          Sql.named('''
            INSERT INTO sources (
              id, name, type, base_url,
              credential_ciphertext, credential_nonce, credential_mac,
              status,
              last_seen_at, created_at, updated_at
            ) VALUES (
              @id, @name, @type, @baseUrl,
              @credentialCiphertext, @credentialNonce, @credentialMac,
              @status,
              @lastSeenAt, @createdAt, @updatedAt
            )
          '''),
          parameters: <String, Object?>{
            'id': source.id,
            'name': source.name,
            'type': source.type,
            'baseUrl': source.baseUrl,
            'credentialCiphertext': source.credential.ciphertext,
            'credentialNonce': source.credential.nonce,
            'credentialMac': source.credential.mac,
            'status': source.status,
            'lastSeenAt': source.lastSeenAt,
            'createdAt': source.createdAt,
            'updatedAt': source.updatedAt,
          },
        );
      }

      for (final Map<String, Object?> event in auditEvents) {
        await session.execute(
          Sql.named('''
            INSERT INTO audit_events (
              id, action, actor_user_id, target_id, details, created_at
            ) VALUES (
              @id, @action, @actorUserId, @targetId, @details::jsonb, @createdAt
            )
          '''),
          parameters: <String, Object?>{
            'id': event['id'],
            'action': event['action'],
            'actorUserId': event['actorUserId'],
            'targetId': event['targetId'],
            'details': jsonEncode(event['details'] ?? <String, Object?>{}),
            'createdAt': DateTime.parse(event['createdAt']! as String),
          },
        );
      }

      if (snapshotsChanged) {
        for (final DataSnapshot snapshot in dataSnapshots) {
          await session.execute(
            Sql.named('''
            INSERT INTO data_snapshots (
              id, source_id, source_type, status, payload, collected_at
            ) VALUES (
              @id, @sourceId, @sourceType, @status, @payload::jsonb, @collectedAt
            )
          '''),
            parameters: <String, Object?>{
              'id': snapshot.id,
              'sourceId': snapshot.sourceId,
              'sourceType': snapshot.sourceType,
              'status': snapshot.status,
              'payload': jsonEncode(snapshot.payload),
              'collectedAt': snapshot.collectedAt,
            },
          );
        }
      }

      await session.execute(
        Sql.named('''
          INSERT INTO system_settings (id, data)
          VALUES ('singleton', @data::jsonb)
        '''),
        parameters: <String, Object?>{'data': jsonEncode(settings.toJson())},
      );
    });
    _savedSnapshotIds = snapshotIds;
  }

  String _snapshotIds() {
    // ponytail: snapshots are immutable today, so IDs are a sufficient dirty
    // check. Replace this with a revision counter if snapshot mutation appears.
    return dataSnapshots.map((snapshot) => snapshot.id).join('\n');
  }

  @override
  Future<bool> checkHealth() async {
    try {
      await _connection.execute('SELECT 1');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> close() => _connection.close();

  Future<void> _migrate() async {
    await _connection.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        email TEXT NOT NULL UNIQUE,
        display_name TEXT NOT NULL,
        role TEXT NOT NULL,
        password_salt TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        is_active BOOLEAN NOT NULL,
        last_login_at TIMESTAMPTZ NULL,
        created_at TIMESTAMPTZ NOT NULL,
        updated_at TIMESTAMPTZ NOT NULL
      )
    ''');
    await _connection.execute('''
      CREATE TABLE IF NOT EXISTS sources (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        base_url TEXT NOT NULL,
        credential_ciphertext TEXT NOT NULL DEFAULT '',
        credential_nonce TEXT NOT NULL DEFAULT '',
        credential_mac TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL,
        last_seen_at TIMESTAMPTZ NULL,
        created_at TIMESTAMPTZ NOT NULL,
        updated_at TIMESTAMPTZ NOT NULL
      )
    ''');
    await _connection.execute(
      "ALTER TABLE sources ADD COLUMN IF NOT EXISTS credential_ciphertext TEXT NOT NULL DEFAULT ''",
    );
    await _connection.execute(
      "ALTER TABLE sources ADD COLUMN IF NOT EXISTS credential_nonce TEXT NOT NULL DEFAULT ''",
    );
    await _connection.execute(
      "ALTER TABLE sources ADD COLUMN IF NOT EXISTS credential_mac TEXT NOT NULL DEFAULT ''",
    );
    await _connection.execute('''
      CREATE TABLE IF NOT EXISTS audit_events (
        id TEXT PRIMARY KEY,
        action TEXT NOT NULL,
        actor_user_id TEXT NOT NULL,
        target_id TEXT NOT NULL,
        details JSONB NOT NULL DEFAULT '{}'::jsonb,
        created_at TIMESTAMPTZ NOT NULL
      )
    ''');
    await _connection.execute(
      'CREATE INDEX IF NOT EXISTS audit_events_created_at_idx ON audit_events (created_at DESC)',
    );
    await _connection.execute('''
      CREATE TABLE IF NOT EXISTS data_snapshots (
        id TEXT PRIMARY KEY,
        source_id TEXT NOT NULL,
        source_type TEXT NOT NULL,
        status TEXT NOT NULL,
        payload JSONB NOT NULL DEFAULT '{}'::jsonb,
        collected_at TIMESTAMPTZ NOT NULL
      )
    ''');
    await _connection.execute(
      'CREATE INDEX IF NOT EXISTS data_snapshots_source_time_idx ON data_snapshots (source_id, collected_at DESC)',
    );
    await _connection.execute('''
      CREATE TABLE IF NOT EXISTS system_settings (
        id TEXT PRIMARY KEY,
        data JSONB NOT NULL DEFAULT '{}'::jsonb
      )
    ''');
  }

  Future<void> _loadUsers() async {
    final Result rows = await _connection.execute('''
      SELECT
        id,
        email,
        display_name AS "displayName",
        role,
        password_salt AS "passwordSalt",
        password_hash AS "passwordHash",
        is_active AS "isActive",
        last_login_at AS "lastLoginAt",
        created_at AS "createdAt",
        updated_at AS "updatedAt"
      FROM users
      ORDER BY created_at ASC
    ''');
    users
      ..clear()
      ..addAll(rows.map((ResultRow row) => User.fromJson(row.toColumnMap())));
  }

  Future<void> _loadSources() async {
    final Result rows = await _connection.execute('''
      SELECT
        id,
        name,
        type,
        base_url AS "baseUrl",
        credential_ciphertext AS "credentialCiphertext",
        credential_nonce AS "credentialNonce",
        credential_mac AS "credentialMac",
        status,
        last_seen_at AS "lastSeenAt",
        created_at AS "createdAt",
        updated_at AS "updatedAt"
      FROM sources
      ORDER BY created_at ASC
    ''');
    sources
      ..clear()
      ..addAll(rows.map((ResultRow row) => Source.fromJson(row.toColumnMap())));
  }

  Future<void> _loadAuditEvents() async {
    final Result rows = await _connection.execute('''
      SELECT
        id,
        action,
        actor_user_id AS "actorUserId",
        target_id AS "targetId",
        details::text AS details,
        created_at AS "createdAt"
      FROM audit_events
      ORDER BY created_at ASC
    ''');
    auditEvents
      ..clear()
      ..addAll(rows.map((ResultRow row) {
        final Map<String, Object?> map = row.toColumnMap();
        return <String, Object?>{
          'id': map['id'],
          'action': map['action'],
          'actorUserId': map['actorUserId'],
          'targetId': map['targetId'],
          'details':
              jsonDecode(map['details']! as String) as Map<String, Object?>,
          'createdAt':
              (map['createdAt']! as DateTime).toUtc().toIso8601String(),
        };
      }));
  }

  Future<void> _loadDataSnapshots() async {
    final Result rows = await _connection.execute('''
      SELECT
        id,
        source_id AS "sourceId",
        source_type AS "sourceType",
        status,
        payload::text AS payload,
        collected_at AS "collectedAt"
      FROM data_snapshots
      WHERE collected_at >= NOW() - INTERVAL '7 days'
      ORDER BY collected_at ASC
    ''');
    dataSnapshots
      ..clear()
      ..addAll(rows.map((ResultRow row) {
        final Map<String, Object?> map = row.toColumnMap();
        return DataSnapshot.fromJson(<String, Object?>{
          'id': map['id'],
          'sourceId': map['sourceId'],
          'sourceType': map['sourceType'],
          'status': map['status'],
          'payload':
              jsonDecode(map['payload']! as String) as Map<String, Object?>,
          'collectedAt':
              (map['collectedAt']! as DateTime).toUtc().toIso8601String(),
        });
      }));
  }

  Future<void> _loadSettings() async {
    final Result rows = await _connection.execute('''
      SELECT data::text AS data
      FROM system_settings
      WHERE id = 'singleton'
      LIMIT 1
    ''');
    if (rows.isEmpty) {
      settings = SystemSettings.defaults();
      return;
    }
    settings = SystemSettings.fromJson(
      jsonDecode(rows.first.toColumnMap()['data']! as String) as Map,
    );
  }
}
