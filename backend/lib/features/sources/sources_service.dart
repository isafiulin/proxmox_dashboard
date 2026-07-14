import 'package:neotelecom_backend/core/extensions/iterable_extensions.dart';
import 'package:neotelecom_backend/core/security/credentials_cipher.dart';
import 'package:neotelecom_backend/core/store/app_store.dart';
import 'package:neotelecom_backend/features/audit/audit_service.dart';
import 'package:neotelecom_backend/features/sources/source.dart';
import 'package:neotelecom_backend/features/sources/source_connection_tester.dart';

class SourcesService {
  SourcesService(
    this._store,
    this._audit,
    this._credentialsCipher,
    this._connectionTester,
  );

  final AppStore _store;
  final AuditService _audit;
  final CredentialsCipher _credentialsCipher;
  final SourceConnectionTester _connectionTester;

  List<Source> list() => List.unmodifiable(_store.sources);

  Source? byId(String id) =>
      _store.sources.where((source) => source.id == id).firstOrNull;

  Future<Source> create({
    required String actorUserId,
    required String name,
    required String type,
    required String baseUrl,
    required String token,
    String backupNamespace = '',
  }) async {
    final normalizedName = name.trim();
    final normalizedUrl = baseUrl.trim();
    if (normalizedName.isEmpty ||
        !Source.allowedTypes.contains(type) ||
        !_isValidAbsoluteUrl(normalizedUrl)) {
      throw const SourceInputException('invalid_source_payload');
    }

    final source = Source.create(
        name: normalizedName,
        type: type,
        baseUrl: normalizedUrl,
        backupNamespace: backupNamespace.trim(),
        credential: await _credentialsCipher.encrypt(token.trim()));
    _store.sources.add(source);
    _audit.record('source.create',
        actorUserId: actorUserId, targetId: source.id, details: {'type': type});
    await _store.save();
    return source;
  }

  Future<Source> update({
    required String actorUserId,
    required String sourceId,
    String? name,
    String? type,
    String? baseUrl,
    String? token,
    String? backupNamespace,
  }) async {
    final source = byId(sourceId);
    if (source == null) throw const SourceInputException('source_not_found');

    if (name != null) source.name = name.trim();
    if (type != null) {
      if (!Source.allowedTypes.contains(type)) {
        throw const SourceInputException('invalid_source_payload');
      }
      source.type = type;
    }
    if (baseUrl != null) {
      final normalizedUrl = baseUrl.trim();
      if (!_isValidAbsoluteUrl(normalizedUrl))
        throw const SourceInputException('invalid_source_payload');
      source.baseUrl = normalizedUrl;
    }
    if (token != null && token.trim().isNotEmpty) {
      source.credential = await _credentialsCipher.encrypt(token.trim());
    }
    if (backupNamespace != null) {
      source.backupNamespace = backupNamespace.trim();
    }

    source.updatedAt = DateTime.now().toUtc();
    _audit.record('source.update',
        actorUserId: actorUserId,
        targetId: source.id,
        details: <String, Object?>{'type': source.type});
    await _store.save();
    return source;
  }

  Future<SourceTestResponse> test(
      {required String actorUserId, required String sourceId}) async {
    final source = byId(sourceId);
    if (source == null) throw const SourceInputException('source_not_found');

    final result = await _connectionTester.test(
      source,
      await _credentialsCipher.decrypt(source.credential),
    );
    source.status = result.status;
    source.lastSeenAt = DateTime.now().toUtc();
    _audit.record(
      'source.test',
      actorUserId: actorUserId,
      targetId: source.id,
      details: <String, Object?>{'ok': result.ok, 'message': result.message},
    );
    await _store.save();
    return SourceTestResponse(source: source, result: result);
  }

  Future<void> delete(
      {required String actorUserId, required String sourceId}) async {
    final source = byId(sourceId);
    if (source == null) throw const SourceInputException('source_not_found');

    _store.sources.removeWhere((candidate) => candidate.id == source.id);
    _audit.record('source.delete',
        actorUserId: actorUserId, targetId: source.id);
    await _store.save();
  }

  Future<String> credentialFor(String sourceId) async {
    final source = byId(sourceId);
    if (source == null) throw const SourceInputException('source_not_found');
    return _credentialsCipher.decrypt(source.credential);
  }
}

bool _isValidAbsoluteUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

class SourceInputException implements Exception {
  const SourceInputException(this.code);

  final String code;
}

class SourceTestResponse {
  const SourceTestResponse({required this.source, required this.result});

  final Source source;
  final ConnectionTestResult result;
}
