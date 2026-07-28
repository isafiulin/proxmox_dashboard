import 'dart:convert';
import 'dart:io';

import 'package:neotelecom_backend/core/store/app_store.dart';
import 'package:neotelecom_backend/features/collection/data_snapshot.dart';
import 'package:neotelecom_backend/features/settings/system_settings.dart';
import 'package:neotelecom_backend/features/sources/source.dart';
import 'package:neotelecom_backend/features/users/user.dart';

class JsonStore implements AppStore {
  JsonStore(this.file);

  final File file;
  Future<void> _saveQueue = Future<void>.value();
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

  @override
  Future<void> load() async {
    if (!await file.exists()) return;
    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, Object?>;
    users
      ..clear()
      ..addAll(((decoded['users'] as List?) ?? [])
          .whereType<Map>()
          .map(User.fromJson));
    sources
      ..clear()
      ..addAll(((decoded['sources'] as List?) ?? [])
          .whereType<Map>()
          .map(Source.fromJson));
    auditEvents
      ..clear()
      ..addAll(((decoded['auditEvents'] as List?) ?? [])
          .whereType<Map>()
          .map((event) => Map<String, Object?>.from(event)));
    dataSnapshots
      ..clear()
      ..addAll(((decoded['dataSnapshots'] as List?) ?? [])
          .whereType<Map>()
          .map(DataSnapshot.fromJson));
    settings = SystemSettings.fromJson(
      decoded['settings'] as Map? ?? const <String, Object?>{},
    );
  }

  @override
  Future<void> save() {
    final next = _saveQueue.then((_) => _save());
    _saveQueue = next.onError((_, __) {});
    return next;
  }

  Future<void> _save() async {
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert({
      'users': users.map((user) => user.toJson()).toList(),
      'sources': sources.map((source) => source.toJson()).toList(),
      'auditEvents': auditEvents,
      'dataSnapshots':
          dataSnapshots.map((snapshot) => snapshot.toJson()).toList(),
      'settings': settings.toJson(),
    }));
  }

  @override
  Future<bool> checkHealth() async => true;
}
