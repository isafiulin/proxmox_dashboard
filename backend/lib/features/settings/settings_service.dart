import 'package:neotelecom_backend/core/store/app_store.dart';
import 'package:neotelecom_backend/features/audit/audit_service.dart';
import 'package:neotelecom_backend/features/settings/system_settings.dart';

class SettingsService {
  SettingsService(this._store, this._audit);

  final AppStore _store;
  final AuditService _audit;

  SystemSettings get current => _store.settings;

  Future<SystemSettings> update({
    required String actorUserId,
    required int collectionIntervalMinutes,
  }) async {
    if (collectionIntervalMinutes < 5 || collectionIntervalMinutes > 1440) {
      throw const SettingsInputException('invalid_settings_payload');
    }

    _store.settings.collectionIntervalMinutes = collectionIntervalMinutes;
    _audit.record(
      'settings.update',
      actorUserId: actorUserId,
      targetId: 'system',
      details: <String, Object?>{
        'collectionIntervalMinutes': collectionIntervalMinutes,
      },
    );
    await _store.save();
    return _store.settings;
  }
}

class SettingsInputException implements Exception {
  const SettingsInputException(this.code);

  final String code;
}
