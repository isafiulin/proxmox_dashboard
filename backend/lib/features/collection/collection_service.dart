import 'dart:async';

import 'package:neotelecom_backend/core/extensions/iterable_extensions.dart';
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
  final Map<String, Future<DataSnapshot>> _activeCollections = {};

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
    await Future.wait(
      List<Source>.from(_store.sources).map(
        (source) => _collectSourceOnce(
          actorUserId: actorUserId,
          source: source,
        ),
      ),
    );
    await _store.save();
  }

  Future<DataSnapshot> collectSource({
    required String actorUserId,
    required Source source,
  }) async {
    final snapshot = await _collectSourceOnce(
      actorUserId: actorUserId,
      source: source,
    );
    await _store.save();
    return snapshot;
  }

  Future<DataSnapshot> collectSourceById({
    required String actorUserId,
    required String sourceId,
  }) async {
    final source =
        _store.sources.where((item) => item.id == sourceId).firstOrNull;
    if (source == null) {
      throw const CollectionException('source_not_found');
    }
    return collectSource(actorUserId: actorUserId, source: source);
  }

  Future<Map<String, Object?>> redfishSnapshot(
    String sourceId, {
    required String actorUserId,
    bool refresh = false,
  }) async {
    final source =
        _store.sources.where((item) => item.id == sourceId).firstOrNull;
    if (source == null) {
      throw const CollectionException('source_not_found');
    }
    if (source.type != 'redfish' && source.type != 'old_ilo2') {
      throw const CollectionException('source_type_mismatch');
    }
    var snapshot = latestSuccessfulSnapshot(
      _store.dataSnapshots.where(
        (item) => !item.collectedAt.isBefore(source.updatedAt),
      ),
      sourceId,
      source.type,
    );
    if (snapshot == null && !refresh) {
      unawaited(_collectRedfishInBackground(actorUserId, sourceId));
      return <String, Object?>{
        '_snapshot': <String, Object?>{'collecting': true, 'stale': false},
      };
    }
    final latestAttempt = latest(sourceId: sourceId)
        .where(
          (item) =>
              item.sourceType == source.type &&
              !item.collectedAt.isBefore(source.updatedAt),
        )
        .firstOrNull;
    String? refreshError;
    if (latestAttempt != null &&
        latestAttempt.sourceType == source.type &&
        latestAttempt.status != 'ok' &&
        (snapshot == null ||
            latestAttempt.collectedAt.isAfter(snapshot.collectedAt))) {
      refreshError = latestAttempt.payload['error']?.toString();
    }
    if (refresh || snapshot == null) {
      final collected = await collectSourceById(
        actorUserId: actorUserId,
        sourceId: sourceId,
      );
      if (collected.status == 'ok') {
        snapshot = collected;
      } else {
        refreshError = collected.payload['error']?.toString();
      }
    }
    if (snapshot == null) {
      throw const CollectionException('redfish_unavailable');
    }
    return <String, Object?>{
      ...snapshot.payload,
      '_snapshot': <String, Object?>{
        'collectedAt': snapshot.collectedAt.toIso8601String(),
        'stale': refreshError != null,
        if (refreshError != null) 'refreshError': refreshError,
      },
    };
  }

  Future<void> _collectRedfishInBackground(
    String actorUserId,
    String sourceId,
  ) async {
    try {
      await collectSourceById(actorUserId: actorUserId, sourceId: sourceId);
    } on Object catch (error) {
      _logger.error(
        'collection.background_error',
        <String, Object?>{'sourceId': sourceId},
        error: error,
      );
    }
  }

  Future<DataSnapshot> _collectSourceOnce({
    required String actorUserId,
    required Source source,
  }) {
    final active = _activeCollections[source.id];
    if (active != null) {
      return active;
    }
    final request = _collectSource(actorUserId: actorUserId, source: source);
    _activeCollections[source.id] = request;
    return request.whenComplete(() => _activeCollections.remove(source.id));
  }

  Future<DataSnapshot> _collectSource({
    required String actorUserId,
    required Source source,
  }) async {
    final stopwatch = Stopwatch()..start();
    late final DataSnapshot snapshot;
    try {
      final payload = await _payloadFor(source);
      payload['collectionDurationMs'] = stopwatch.elapsedMilliseconds;
      snapshot = DataSnapshot.create(
        sourceId: source.id,
        sourceType: source.type,
        status: 'ok',
        payload: payload,
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
        payload: <String, Object?>{
          'error': error.toString(),
          'collectionDurationMs': stopwatch.elapsedMilliseconds,
        },
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
    return snapshot;
  }

  Future<Map<String, Object?>> _payloadFor(Source source) async {
    if (source.type == 'proxmox_ve') {
      final results = await Future.wait<Object?>(<Future<Object?>>[
        _infrastructure.proxmoxVeNodes(source.id),
        _infrastructure.proxmoxVeResources(source.id),
        _infrastructure.proxmoxVeTasks(source.id),
      ]);
      return <String, Object?>{
        'nodes': results[0],
        'resources': results[1],
        'tasks': results[2],
      };
    }
    if (source.type == 'proxmox_backup') {
      final results = await Future.wait<Object?>(<Future<Object?>>[
        _infrastructure.proxmoxBackupDatastores(source.id),
        _infrastructure.proxmoxBackupTasks(source.id),
      ]);
      return <String, Object?>{
        'datastores': results[0],
        'tasks': results[1],
      };
    }
    if (source.type == 'redfish') {
      return _infrastructure.redfishInventory(source.id);
    }
    if (source.type == 'old_ilo2') {
      return _infrastructure.oldIlo2Inventory(source.id);
    }
    throw StateError('unsupported_source_type: ${source.type}');
  }

  Future<void> prune({DateTime? now}) async {
    pruneExpiredSnapshots(_store.dataSnapshots, now: now);
    await _store.save();
  }

  Map<String, Object?> metrics() {
    final rows = <Map<String, Object?>>[];
    final dailyRows = <Map<String, Object?>>[];
    for (final source in _store.sources) {
      final snapshots = _store.dataSnapshots
          .where((snapshot) => snapshot.sourceId == source.id)
          .toList();
      final durations = snapshots
          .map(
            (snapshot) => int.tryParse(
              snapshot.payload['collectionDurationMs']?.toString() ?? '',
            ),
          )
          .whereType<int>()
          .toList();
      final failures =
          snapshots.where((snapshot) => snapshot.status != 'ok').length;
      rows.add(<String, Object?>{
        'sourceId': source.id,
        'sourceName': source.name,
        'sourceType': source.type,
        'polls': snapshots.length,
        'successes': snapshots.length - failures,
        'errors': failures,
        'averageDurationMs': durations.isEmpty
            ? null
            : durations.reduce((left, right) => left + right) ~/
                durations.length,
        'lastDurationMs': durations.isEmpty ? null : durations.last,
        'lastCollectedAt': snapshots.isEmpty
            ? null
            : (snapshots
                  ..sort(
                    (left, right) =>
                        right.collectedAt.compareTo(left.collectedAt),
                  ))
                .first
                .collectedAt
                .toIso8601String(),
        'status': source.status,
      });
      final byDay = <String, List<DataSnapshot>>{};
      for (final snapshot in snapshots) {
        final day = snapshot.collectedAt.toUtc().toIso8601String().substring(
              0,
              10,
            );
        byDay.putIfAbsent(day, () => <DataSnapshot>[]).add(snapshot);
      }
      for (final entry in byDay.entries) {
        final dayDurations = entry.value
            .map(
              (snapshot) => int.tryParse(
                snapshot.payload['collectionDurationMs']?.toString() ?? '',
              ),
            )
            .whereType<int>()
            .toList();
        dailyRows.add(<String, Object?>{
          'sourceId': source.id,
          'sourceName': source.name,
          'day': entry.key,
          'polls': entry.value.length,
          'errors':
              entry.value.where((snapshot) => snapshot.status != 'ok').length,
          'averageDurationMs': dayDurations.isEmpty
              ? null
              : dayDurations.reduce((left, right) => left + right) ~/
                  dayDurations.length,
        });
      }
    }
    dailyRows.sort(
      (left, right) =>
          (right['day'] as String).compareTo(left['day'] as String),
    );
    return <String, Object?>{
      'sources': rows,
      'daily': dailyRows,
      'totalPolls': rows.fold<int>(
        0,
        (sum, row) => sum + (row['polls'] as int),
      ),
      'totalErrors': rows.fold<int>(
        0,
        (sum, row) => sum + (row['errors'] as int),
      ),
    };
  }
}

class CollectionException implements Exception {
  const CollectionException(this.code);

  final String code;
}

DataSnapshot? latestSuccessfulSnapshot(
  Iterable<DataSnapshot> snapshots,
  String sourceId,
  String sourceType,
) {
  return snapshots
      .where(
        (snapshot) =>
            snapshot.sourceId == sourceId &&
            snapshot.sourceType == sourceType &&
            snapshot.status == 'ok',
      )
      .fold<DataSnapshot?>(
        null,
        (latest, snapshot) =>
            latest == null || snapshot.collectedAt.isAfter(latest.collectedAt)
                ? snapshot
                : latest,
      );
}

void pruneExpiredSnapshots(List<DataSnapshot> snapshots, {DateTime? now}) {
  final cutoff = (now ?? DateTime.now().toUtc()).subtract(snapshotRetention);
  snapshots.removeWhere((snapshot) => snapshot.collectedAt.isBefore(cutoff));
}
