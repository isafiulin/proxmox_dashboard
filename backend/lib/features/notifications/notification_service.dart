import 'dart:async';
import 'dart:convert';

import 'package:neotelecom_backend/core/logging/app_logger.dart';
import 'package:neotelecom_backend/core/security/credentials_cipher.dart';
import 'package:neotelecom_backend/core/store/app_store.dart';
import 'package:neotelecom_backend/features/collection/data_snapshot.dart';
import 'package:neotelecom_backend/features/notifications/telegram_bot_client.dart';
import 'package:neotelecom_backend/features/sources/source.dart';
import 'package:neotelecom_backend/features/settings/error_filter.dart';

class NotificationService {
  NotificationService(
    this._store,
    this._credentialsCipher,
    this._telegram,
    this._logger,
  );

  final AppStore _store;
  final CredentialsCipher _credentialsCipher;
  final TelegramBotClient _telegram;
  final AppLogger _logger;
  final List<_PendingNotification> _pending = <_PendingNotification>[];
  Timer? _batchTimer;

  Future<void> testTelegram() async {
    final settings = _store.settings;
    if (!settings.telegramBotToken.hasValue ||
        settings.telegramChatId.isEmpty) {
      throw const TelegramException('telegram_not_configured');
    }
    await _telegram.sendMessage(
      token: await _credentialsCipher.decrypt(settings.telegramBotToken),
      chatId: settings.telegramChatId,
      message: '<b>✅ NeoTelecom: Telegram подключён</b>\n\n'
          'Тестовое уведомление доставлено. Аварии будут приходить одним '
          'компактным сообщением при изменении состояния.',
    );
  }

  Future<void> onSnapshot({
    required Source source,
    required DataSnapshot snapshot,
    required DataSnapshot? previous,
  }) async {
    final settings = _store.settings;
    if (!settings.telegramEnabled ||
        !settings.telegramBotToken.hasValue ||
        settings.telegramChatId.isEmpty) {
      return;
    }
    final change = incidentChange(
      previous,
      snapshot,
      minimumSeverity: settings.telegramMinimumSeverity,
      backupSnapshots: _latestBackupSnapshots(_store),
      backupNamespace: source.backupNamespace,
      ignoredErrorPatterns: settings.ignoredErrorPatterns,
    );
    if (change.started.isEmpty &&
        (!settings.telegramNotifyRecovery || change.resolved.isEmpty)) {
      return;
    }
    _pending.add(
      _PendingNotification(
        source: source,
        collectedAt: snapshot.collectedAt,
        change: change,
      ),
    );
    // ponytail: a short process-local debounce turns one parallel polling
    // cycle into one Telegram message. A durable queue is the upgrade path.
    _batchTimer ??= Timer(const Duration(seconds: 2), () {
      _batchTimer = null;
      final batch = List<_PendingNotification>.from(_pending);
      _pending.clear();
      unawaited(_sendBatch(batch));
    });
  }

  Future<void> _sendBatch(List<_PendingNotification> batch) async {
    final settings = _store.settings;
    if (batch.isEmpty ||
        !settings.telegramEnabled ||
        !settings.telegramBotToken.hasValue ||
        settings.telegramChatId.isEmpty) {
      return;
    }
    try {
      await _telegram.sendMessage(
        token: await _credentialsCipher.decrypt(settings.telegramBotToken),
        chatId: settings.telegramChatId,
        message: _buildTelegramBatchMessage(
          batch,
          includeRecovery: settings.telegramNotifyRecovery,
        ),
      );
    } on Object catch (error) {
      // Notification transport must never turn a successful poll into failure.
      _logger.warning('notification.telegram_error', <String, Object?>{
        'sourceIds': batch.map((item) => item.source.id).toList(),
        'error': error is TelegramException ? error.code : 'unknown',
      });
    }
  }
}

class _PendingNotification {
  const _PendingNotification({
    required this.source,
    required this.collectedAt,
    required this.change,
  });

  final Source source;
  final DateTime collectedAt;
  final IncidentChange change;
}

class Incident {
  const Incident({
    required this.key,
    required this.label,
    required this.severity,
  });

  final String key;
  final String label;
  final String severity;
}

class IncidentChange {
  const IncidentChange({required this.started, required this.resolved});

  final List<Incident> started;
  final List<Incident> resolved;
}

IncidentChange incidentChange(
  DataSnapshot? previous,
  DataSnapshot current, {
  required String minimumSeverity,
  List<Map<String, Object?>> backupSnapshots = const <Map<String, Object?>>[],
  String backupNamespace = '',
  DateTime? now,
  List<String> ignoredErrorPatterns = const <String>[],
}) {
  final before = <String, Incident>{
    for (final incident in _incidents(
      previous,
      minimumSeverity,
      backupSnapshots: backupSnapshots,
      backupNamespace: backupNamespace,
      now: now,
      ignoredErrorPatterns: ignoredErrorPatterns,
    ))
      incident.key: incident,
  };
  final after = <String, Incident>{
    for (final incident in _incidents(
      current,
      minimumSeverity,
      backupSnapshots: backupSnapshots,
      backupNamespace: backupNamespace,
      now: now,
      ignoredErrorPatterns: ignoredErrorPatterns,
    ))
      incident.key: incident,
  };
  final started = after.values
      .where(
        (incident) =>
            !before.containsKey(incident.key) ||
            _severityRank(incident.severity) >
                _severityRank(before[incident.key]!.severity),
      )
      .toList()
    ..sort(_incidentSort);
  final resolved = current.status == 'ok'
      ? (before.values
          .where((incident) => !after.containsKey(incident.key))
          .toList()
        ..sort(_incidentSort))
      : <Incident>[];
  return IncidentChange(started: started, resolved: resolved);
}

String buildTelegramIncidentMessage({
  required Source source,
  required DateTime collectedAt,
  required IncidentChange change,
  required bool includeRecovery,
}) {
  final lines = <String>[];
  if (change.started.isNotEmpty) {
    final critical = change.started
        .where((incident) => incident.severity == 'critical')
        .length;
    lines.add(
      critical > 0
          ? '<b>🔴 Новая авария</b>'
          : '<b>🟡 Новое предупреждение</b>',
    );
  } else {
    lines.add('<b>✅ Состояние восстановлено</b>');
  }
  lines
    ..add('Источник: <b>${_escape(source.name)}</b>')
    ..add('Тип: ${_escape(source.type)}')
    ..add('Время: ${_formatTime(collectedAt)}');

  if (change.started.isNotEmpty) {
    lines.add('');
    for (final incident in change.started.take(5)) {
      final icon = incident.severity == 'critical' ? '🔴' : '🟡';
      lines.add('$icon ${_escape(incident.label)}');
    }
    if (change.started.length > 5) {
      lines.add('… и ещё ${change.started.length - 5}');
    }
  }
  if (includeRecovery && change.resolved.isNotEmpty) {
    lines
      ..add('')
      ..add('✅ Восстановлено: ${change.resolved.length}');
    for (final incident in change.resolved.take(3)) {
      lines.add('• ${_escape(incident.label)}');
    }
    if (change.resolved.length > 3) {
      lines.add('… и ещё ${change.resolved.length - 3}');
    }
  }
  return lines.join('\n');
}

String _buildTelegramBatchMessage(
  List<_PendingNotification> batch, {
  required bool includeRecovery,
}) {
  if (batch.length == 1) {
    final item = batch.single;
    return buildTelegramIncidentMessage(
      source: item.source,
      collectedAt: item.collectedAt,
      change: item.change,
      includeRecovery: includeRecovery,
    );
  }
  final startedCount = batch.fold<int>(
    0,
    (sum, item) => sum + item.change.started.length,
  );
  final resolvedCount = batch.fold<int>(
    0,
    (sum, item) => sum + item.change.resolved.length,
  );
  final hasCritical = batch.any(
    (item) => item.change.started.any(
      (incident) => incident.severity == 'critical',
    ),
  );
  final latestAt = batch
      .map((item) => item.collectedAt)
      .reduce((left, right) => left.isAfter(right) ? left : right);
  final lines = <String>[
    startedCount > 0
        ? '<b>${hasCritical ? '🔴' : '🟡'} Новые события: $startedCount</b>'
        : '<b>✅ Состояние восстановлено</b>',
    'Источников с изменениями: ${batch.length}',
    'Время: ${_formatTime(latestAt)}',
  ];
  var detailsLeft = 8;
  for (final item in batch.where((item) => item.change.started.isNotEmpty)) {
    if (detailsLeft == 0) break;
    lines
      ..add('')
      ..add('<b>${_escape(item.source.name)}</b>');
    for (final incident in item.change.started.take(detailsLeft)) {
      final icon = incident.severity == 'critical' ? '🔴' : '🟡';
      lines.add('$icon ${_escape(incident.label)}');
      detailsLeft -= 1;
    }
  }
  final shownStarted = 8 - detailsLeft;
  if (startedCount > shownStarted) {
    lines.add('… и ещё ${startedCount - shownStarted}');
  }
  if (includeRecovery && resolvedCount > 0) {
    lines
      ..add('')
      ..add('✅ Восстановлено: $resolvedCount');
  }
  return lines.join('\n');
}

List<Incident> _incidents(
  DataSnapshot? snapshot,
  String minimumSeverity, {
  required List<Map<String, Object?>> backupSnapshots,
  required String backupNamespace,
  required DateTime? now,
  required List<String> ignoredErrorPatterns,
}) {
  if (snapshot == null) return const <Incident>[];
  if (snapshot.status != 'ok') {
    if (matchesIgnoredError(snapshot.payload, ignoredErrorPatterns)) {
      return const <Incident>[];
    }
    return const <Incident>[
      Incident(
        key: 'collection',
        label: 'Источник недоступен или сбор данных завершился ошибкой',
        severity: 'critical',
      ),
    ];
  }
  final incidents = <Incident>[];
  final payload = (filterIgnoredErrors(
    snapshot.payload,
    ignoredErrorPatterns,
  ) as Map)
      .cast<String, Object?>();
  final rows = payload['healthIssues'];
  if (rows is List) {
    incidents.addAll(rows.whereType<Map>().map((row) {
      final severity = _normalizedSeverity(row['health']?.toString());
      final type = row['resourceType']?.toString() ?? 'resource';
      final id = row['resourceId']?.toString() ?? row['name']?.toString() ?? '';
      final name = row['name']?.toString();
      return Incident(
        key: '$type:$id',
        label: name == null || name.isEmpty ? '$type $id' : name,
        severity: severity,
      );
    }));
  }
  if (snapshot.sourceType == 'proxmox_ve') {
    incidents.addAll(_proxmoxVeIncidents(
      DataSnapshot(
        id: snapshot.id,
        sourceId: snapshot.sourceId,
        sourceType: snapshot.sourceType,
        status: snapshot.status,
        payload: payload,
        collectedAt: snapshot.collectedAt,
      ),
      backupSnapshots: backupSnapshots,
      backupNamespace: backupNamespace,
      now: now,
    ));
  } else if (snapshot.sourceType == 'proxmox_backup') {
    incidents.addAll(_proxmoxBackupIncidents(
      DataSnapshot(
        id: snapshot.id,
        sourceId: snapshot.sourceId,
        sourceType: snapshot.sourceType,
        status: snapshot.status,
        payload: payload,
        collectedAt: snapshot.collectedAt,
      ),
      now: now,
    ));
  }
  final minimum = _severityRank(minimumSeverity);
  return incidents
      .where((incident) => _severityRank(incident.severity) >= minimum)
      .toList();
}

List<Incident> _proxmoxVeIncidents(
  DataSnapshot snapshot, {
  required List<Map<String, Object?>> backupSnapshots,
  required String backupNamespace,
  required DateTime? now,
}) {
  final incidents = <Incident>[];
  final resources = _maps(snapshot.payload['resources']);
  for (final resource in resources) {
    final type = resource['type']?.toString() ?? '';
    final id = resource['id']?.toString() ?? resource['vmid']?.toString() ?? '';
    final name = resource['name']?.toString() ?? id;
    final status = resource['status']?.toString().toLowerCase() ?? '';
    if (type == 'node' && status.isNotEmpty && status != 'online') {
      incidents.add(Incident(
        key: 'node:$id:offline',
        label: 'Нода $name недоступна',
        severity: 'critical',
      ));
    }
    if (type == 'node' ||
        ((type == 'qemu' || type == 'lxc') && status == 'running')) {
      _addRatioIncident(incidents, '$type:$id:cpu', '$name: CPU ≥ 90%',
          _ratio(resource['cpu']));
      _addRatioIncident(
        incidents,
        '$type:$id:ram',
        '$name: RAM ≥ 90%',
        _ratioPair(resource['mem'], resource['maxmem']),
      );
    }
    if (type == 'storage') {
      _addRatioIncident(
        incidents,
        'storage:$id:disk',
        'Storage $name заполнен ≥ 90%',
        _ratioPair(resource['disk'], resource['maxdisk']),
      );
    }
    if ((type == 'qemu' || type == 'lxc') && status == 'running') {
      final backup = _backupIncident(
        resource,
        backupSnapshots,
        backupNamespace: backupNamespace,
        storageConfig: _maps(snapshot.payload['storageConfig']),
        now: now,
      );
      if (backup != null) incidents.add(backup);
    }
  }
  incidents.addAll(_failedTaskIncidents(_maps(snapshot.payload['tasks']), now));
  return incidents;
}

List<Incident> _proxmoxBackupIncidents(DataSnapshot snapshot, {DateTime? now}) {
  final incidents = _failedTaskIncidents(_maps(snapshot.payload['tasks']), now);
  final health = snapshot.payload['health'];
  if (health is Map) {
    for (final datastore in _maps(health['datastores'])) {
      final name = (datastore['store'] ?? datastore['name'])?.toString() ?? '';
      _addRatioIncident(
        incidents,
        'datastore:$name:disk',
        'PBS datastore $name заполнен ≥ 90%',
        _ratioPair(datastore['used'], datastore['total']),
      );
    }
    for (final error in _maps(health['errors'])) {
      final area = error['area']?.toString() ?? 'PBS';
      incidents.add(Incident(
        key: 'pbs-health:$area:${error['status'] ?? error['error'] ?? ''}',
        label: '$area: ${error['error'] ?? error['status'] ?? 'ошибка'}',
        severity: 'critical',
      ));
    }
  }
  return incidents;
}

List<Incident> _failedTaskIncidents(
  List<Map<String, Object?>> tasks,
  DateTime? now,
) {
  final current = (now ?? DateTime.now()).toUtc();
  return tasks.where((task) {
    if (task['endtime'] == null) return false;
    final status = task['status']?.toString().trim().toLowerCase() ?? '';
    if (status.isEmpty || status == 'ok' || status == 'unknown') return false;
    final ended = int.tryParse(task['endtime']?.toString() ?? '');
    return ended == null ||
        current.difference(DateTime.fromMillisecondsSinceEpoch(
              ended * 1000,
              isUtc: true,
            )) <=
            const Duration(hours: 24);
  }).map((task) {
    final type = (task['worker_type'] ?? task['type'])?.toString() ?? 'task';
    final target = (task['worker_id'] ?? task['id'])?.toString() ?? '';
    final key = task['upid']?.toString() ?? '$type:$target:${task['endtime']}';
    return Incident(
      key: 'task:$key',
      label: '$type $target: ${task['status']}',
      severity: 'critical',
    );
  }).toList();
}

Incident? _backupIncident(
  Map<String, Object?> guest,
  List<Map<String, Object?>> snapshots, {
  required String backupNamespace,
  required List<Map<String, Object?>> storageConfig,
  required DateTime? now,
}) {
  final type = guest['type']?.toString() ?? '';
  final vmid = guest['vmid']?.toString() ?? '';
  final name = guest['name']?.toString() ?? '$type/$vmid';
  final backupType = type == 'lxc' ? 'ct' : 'vm';
  final namespaces = <String>{};
  if (backupNamespace.trim().isNotEmpty) namespaces.add(backupNamespace.trim());
  for (final storage in storageConfig) {
    final storageType =
        (storage['type'] ?? storage['plugintype'])?.toString().toLowerCase() ??
            '';
    if (storageType != 'pbs' && storageType != 'proxmox-backup') continue;
    final namespace =
        (storage['namespace'] ?? storage['ns'] ?? storage['backup-ns'])
                ?.toString()
                .trim() ??
            '';
    if (namespace.isNotEmpty && namespace != '/') namespaces.add(namespace);
  }
  if (namespaces.isEmpty) namespaces.add('');
  final matches = snapshots.where((row) {
    final namespace = (row['namespace'] ?? row['ns'] ?? row['backup-ns'])
            ?.toString()
            .trim() ??
        '';
    return row['backup-type']?.toString() == backupType &&
        row['backup-id']?.toString() == vmid &&
        namespaces.contains(namespace);
  }).toList();
  final key = 'backup:$type:$vmid';
  if (matches.isEmpty) {
    return Incident(
      key: key,
      label: '$name ($type/$vmid): backup не найден',
      severity: 'critical',
    );
  }
  final latestSeconds = matches
      .map((row) => int.tryParse(row['backup-time']?.toString() ?? '') ?? 0)
      .reduce((left, right) => left > right ? left : right);
  final age = (now ?? DateTime.now()).toUtc().difference(
        DateTime.fromMillisecondsSinceEpoch(latestSeconds * 1000, isUtc: true),
      );
  if (age > const Duration(days: 7)) {
    return Incident(
        key: key, label: '$name: backup старше 7 дней', severity: 'critical');
  }
  if (age > const Duration(hours: 24)) {
    return Incident(
        key: key, label: '$name: backup старше 24 часов', severity: 'warning');
  }
  return null;
}

void _addRatioIncident(
  List<Incident> incidents,
  String key,
  String label,
  double value,
) {
  if (value >= 0.9) {
    incidents.add(Incident(key: key, label: label, severity: 'critical'));
  }
}

double _ratio(Object? value) => double.tryParse(value?.toString() ?? '') ?? 0;

double _ratioPair(Object? used, Object? total) {
  final totalValue = double.tryParse(total?.toString() ?? '') ?? 0;
  final usedValue = double.tryParse(used?.toString() ?? '') ?? 0;
  return totalValue <= 0 ? 0 : usedValue / totalValue;
}

List<Map<String, Object?>> _maps(Object? value) => value is List
    ? value.whereType<Map>().map((row) => row.cast<String, Object?>()).toList()
    : const <Map<String, Object?>>[];

List<Map<String, Object?>> _latestBackupSnapshots(AppStore store) {
  final result = <Map<String, Object?>>[];
  for (final source
      in store.sources.where((item) => item.type == 'proxmox_backup')) {
    final snapshots = store.dataSnapshots
        .where((item) =>
            item.sourceId == source.id &&
            item.sourceType == source.type &&
            item.status == 'ok' &&
            !item.collectedAt.isBefore(source.updatedAt))
        .toList()
      ..sort((left, right) => right.collectedAt.compareTo(left.collectedAt));
    if (snapshots.isNotEmpty)
      result.addAll(_maps(snapshots.first.payload['snapshots']));
  }
  return result;
}

String _normalizedSeverity(String? value) {
  final lower = value?.toLowerCase() ?? '';
  return lower.contains('critical') || lower.contains('error')
      ? 'critical'
      : 'warning';
}

int _severityRank(String value) => value == 'critical' ? 2 : 1;

int _incidentSort(Incident left, Incident right) {
  final severity =
      _severityRank(right.severity).compareTo(_severityRank(left.severity));
  return severity != 0 ? severity : left.label.compareTo(right.label);
}

String _escape(String value) => const HtmlEscape().convert(value);

String _formatTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}
