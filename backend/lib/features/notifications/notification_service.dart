import 'dart:async';
import 'dart:convert';

import 'package:neotelecom_backend/core/logging/app_logger.dart';
import 'package:neotelecom_backend/core/security/credentials_cipher.dart';
import 'package:neotelecom_backend/core/store/app_store.dart';
import 'package:neotelecom_backend/features/collection/data_snapshot.dart';
import 'package:neotelecom_backend/features/notifications/telegram_bot_client.dart';
import 'package:neotelecom_backend/features/sources/source.dart';

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
}) {
  final before = <String, Incident>{
    for (final incident in _incidents(previous, minimumSeverity))
      incident.key: incident,
  };
  final after = <String, Incident>{
    for (final incident in _incidents(current, minimumSeverity))
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

List<Incident> _incidents(DataSnapshot? snapshot, String minimumSeverity) {
  if (snapshot == null) return const <Incident>[];
  if (snapshot.status != 'ok') {
    return const <Incident>[
      Incident(
        key: 'collection',
        label: 'Источник недоступен или сбор данных завершился ошибкой',
        severity: 'critical',
      ),
    ];
  }
  final rows = snapshot.payload['healthIssues'];
  if (rows is! List) return const <Incident>[];
  final minimum = _severityRank(minimumSeverity);
  return rows
      .whereType<Map>()
      .map((row) {
        final severity = _normalizedSeverity(row['health']?.toString());
        final type = row['resourceType']?.toString() ?? 'resource';
        final id =
            row['resourceId']?.toString() ?? row['name']?.toString() ?? '';
        final name = row['name']?.toString();
        return Incident(
          key: '$type:$id',
          label: name == null || name.isEmpty ? '$type $id' : name,
          severity: severity,
        );
      })
      .where((incident) => _severityRank(incident.severity) >= minimum)
      .toList();
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
