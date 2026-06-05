import 'dart:async';

import 'package:neotelecom_backend/core/store/app_store.dart';
import 'package:neotelecom_backend/core/logging/app_logger.dart';
import 'package:neotelecom_backend/features/audit/audit_service.dart';
import 'package:neotelecom_backend/features/collection/data_snapshot.dart';
import 'package:neotelecom_backend/features/integrations/infrastructure_read_service.dart';
import 'package:neotelecom_backend/features/sources/source.dart';

const snapshotRetention = Duration(days: 7);

class CollectionService {
  CollectionService(
    this._store,
    this._infrastructure,
    this._audit,
    this._logger,
  );

  final AppStore _store;
  final InfrastructureReadService _infrastructure;
  final AuditService _audit;
  final AppLogger _logger;
  Timer? _timer;

  void start() {
    _timer?.cancel();
    final interval = Duration(
      minutes: _store.settings.collectionIntervalMinutes,
    );
    _timer = Timer.periodic(interval, (_) => collectAll(actorUserId: 'system'));
  }

  Future<void> restart() async {
    start();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  List<DataSnapshot> latest({String? sourceId, int limit = 100}) {
    final snapshots = _store.dataSnapshots
        .where((snapshot) => sourceId == null || snapshot.sourceId == sourceId)
        .toList()
      ..sort((a, b) => b.collectedAt.compareTo(a.collectedAt));
    return snapshots.take(limit).toList(growable: false);
  }

  Future<void> collectAll({required String actorUserId}) async {
    for (final Source source in List<Source>.from(_store.sources)) {
      await collectSource(actorUserId: actorUserId, source: source);
    }
  }

  Future<DataSnapshot> collectSource({
    required String actorUserId,
    required Source source,
  }) async {
    final stopwatch = Stopwatch()..start();
    late final DataSnapshot snapshot;
    try {
      snapshot = DataSnapshot.create(
        sourceId: source.id,
        sourceType: source.type,
        status: 'ok',
        payload: await _payloadFor(source),
      );
      source.status = 'ok';
      source.lastSeenAt = snapshot.collectedAt;
      _logger.info('collection.source_ok', <String, Object?>{
        'sourceId': source.id,
        'sourceType': source.type,
        'durationMs': stopwatch.elapsedMilliseconds,
      });
    } on Object catch (error) {
      snapshot = DataSnapshot.create(
        sourceId: source.id,
        sourceType: source.type,
        status: 'critical',
        payload: <String, Object?>{'error': error.toString()},
      );
      source.status = 'critical';
      _logger.error(
        'collection.source_error',
        <String, Object?>{
          'sourceId': source.id,
          'sourceType': source.type,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
        error: error,
      );
    }

    _store.dataSnapshots.add(snapshot);
    pruneExpiredSnapshots(_store.dataSnapshots);
    _audit.record(
      'collection.snapshot',
      actorUserId: actorUserId,
      targetId: source.id,
      details: <String, Object?>{'status': snapshot.status},
    );
    await _store.save();
    return snapshot;
  }

  Future<Map<String, Object?>> _payloadFor(Source source) async {
    if (source.type == 'proxmox_ve') {
      return <String, Object?>{
        'nodes': await _infrastructure.proxmoxVeNodes(source.id),
        'resources': await _infrastructure.proxmoxVeResources(source.id),
        'tasks': await _infrastructure.proxmoxVeTasks(source.id),
      };
    }
    if (source.type == 'proxmox_backup') {
      return <String, Object?>{
        'datastores': await _infrastructure.proxmoxBackupDatastores(source.id),
        'tasks': await _infrastructure.proxmoxBackupTasks(source.id),
      };
    }
    return <String, Object?>{'status': 'not_implemented'};
  }

  Future<void> prune({DateTime? now}) async {
    pruneExpiredSnapshots(_store.dataSnapshots, now: now);
    await _store.save();
  }
}

void pruneExpiredSnapshots(List<DataSnapshot> snapshots, {DateTime? now}) {
  final cutoff = (now ?? DateTime.now().toUtc()).subtract(snapshotRetention);
  snapshots.removeWhere((snapshot) => snapshot.collectedAt.isBefore(cutoff));
}
