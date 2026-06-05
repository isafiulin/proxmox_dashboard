class GuestBackupSummary {
  const GuestBackupSummary({
    required this.matches,
    required this.status,
    this.latestBackupAt,
    this.latestSnapshot,
  });

  final List<Map<String, Object?>> matches;
  final BackupAgeStatus status;
  final DateTime? latestBackupAt;
  final Map<String, Object?>? latestSnapshot;
}

class BackupCoverageReport {
  const BackupCoverageReport({
    required this.guests,
    required this.dailyCounts,
    required this.totalSnapshots,
    required this.protectedGuests,
    required this.totalSizeBytes,
  });

  final List<BackupGuestReport> guests;
  final List<BackupDayCount> dailyCounts;
  final int totalSnapshots;
  final int protectedGuests;
  final double totalSizeBytes;

  int get totalGuests => guests.length;
}

class BackupGuestReport {
  const BackupGuestReport({
    required this.backupType,
    required this.backupId,
    required this.datastores,
    required this.count,
    required this.totalSizeBytes,
    required this.averageInterval,
    this.latestBackupAt,
  });

  final String backupType;
  final String backupId;
  final Set<String> datastores;
  final int count;
  final double totalSizeBytes;
  final Duration? averageInterval;
  final DateTime? latestBackupAt;

  String get displayName => '$backupType/$backupId';
}

class BackupDayCount {
  const BackupDayCount({required this.day, required this.count});

  final DateTime day;
  final int count;
}

class BackupScheduleReport {
  const BackupScheduleReport({
    required this.items,
    required this.calendarDays,
    required this.calendarEntries,
    required this.totalSnapshots,
  });

  final List<BackupScheduleItem> items;
  final List<BackupCalendarDay> calendarDays;
  final List<BackupCalendarEntry> calendarEntries;
  final int totalSnapshots;

  int get protectedGuests => items.length;
}

class BackupScheduleItem {
  const BackupScheduleItem({
    required this.backupType,
    required this.backupId,
    required this.count,
    required this.typicalHour,
    required this.weekdayCounts,
    required this.datastores,
    required this.averageInterval,
    this.latestBackupAt,
  });

  final String backupType;
  final String backupId;
  final int count;
  final int typicalHour;
  final Map<int, int> weekdayCounts;
  final Set<String> datastores;
  final Duration? averageInterval;
  final DateTime? latestBackupAt;

  String get displayName => '$backupType/$backupId';
}

class BackupCalendarDay {
  const BackupCalendarDay({
    required this.day,
    required this.count,
    this.entries = const <BackupCalendarEntry>[],
  });

  final DateTime day;
  final int count;
  final List<BackupCalendarEntry> entries;
}

class BackupCalendarEntry {
  const BackupCalendarEntry({
    required this.backupType,
    required this.backupId,
    required this.backupAt,
    required this.datastore,
    required this.backupSource,
  });

  final String backupType;
  final String backupId;
  final DateTime backupAt;
  final String datastore;
  final String backupSource;

  String get displayName => '$backupType/$backupId';
}

enum BackupAgeStatus { ok, warning, critical, missing }

BackupScheduleReport analyzeBackupSchedule(
  List<Map<String, Object?>> snapshots, {
  DateTime? now,
  int days = 14,
}) {
  final currentDay = _startOfDay((now ?? DateTime.now()).toLocal());
  final firstDay = currentDay.subtract(Duration(days: days - 1));
  final calendarCounts = <DateTime, int>{
    for (var index = 0; index < days; index++)
      firstDay.add(Duration(days: index)): 0,
  };
  final entriesByDay = <DateTime, List<BackupCalendarEntry>>{};
  final calendarEntries = <BackupCalendarEntry>[];
  final calendarEventGroups = <String, _BackupCalendarEventGroup>{};
  final byGuest = <String, List<Map<String, Object?>>>{};

  for (final snapshot in snapshots) {
    final backupType = snapshot['backup-type']?.toString() ?? '';
    final backupId = snapshot['backup-id']?.toString() ?? '';
    if (backupType.isEmpty || backupId.isEmpty) {
      continue;
    }

    final localTime = snapshotTime(snapshot).toLocal();
    final eventKey =
        '$backupType/$backupId/${localTime.toUtc().millisecondsSinceEpoch}';
    final eventGroup = calendarEventGroups.putIfAbsent(
      eventKey,
      () => _BackupCalendarEventGroup(
        backupType: backupType,
        backupId: backupId,
        backupAt: localTime,
      ),
    );
    eventGroup.add(
      backupSource: snapshot['backupSource']?.toString() ?? '',
      datastore: snapshot['datastore']?.toString() ?? '',
    );
    byGuest.putIfAbsent(
      '$backupType/$backupId',
      () => <Map<String, Object?>>[],
    );
    byGuest['$backupType/$backupId']!.add(snapshot);
  }

  for (final eventGroup in calendarEventGroups.values) {
    final entry = eventGroup.toEntry();
    final localDay = _startOfDay(entry.backupAt);
    calendarEntries.add(entry);
    entriesByDay.putIfAbsent(localDay, () => <BackupCalendarEntry>[]);
    entriesByDay[localDay]!.add(entry);
    if (!localDay.isBefore(firstDay) && !localDay.isAfter(currentDay)) {
      calendarCounts[localDay] = (calendarCounts[localDay] ?? 0) + 1;
    }
  }

  final items =
      byGuest.entries.map((entry) {
        final snapshots = entry.value
          ..sort((a, b) => snapshotTime(b).compareTo(snapshotTime(a)));
        final backupEvents = _uniqueSnapshotsByBackupTime(snapshots);
        final latest = backupEvents.isEmpty
            ? null
            : snapshotTime(backupEvents.first);
        final first = backupEvents.isEmpty
            ? null
            : snapshotTime(backupEvents.last);
        final hourCounts = <int, int>{};
        final weekdayCounts = <int, int>{};
        for (final snapshot in backupEvents) {
          final local = snapshotTime(snapshot).toLocal();
          hourCounts[local.hour] = (hourCounts[local.hour] ?? 0) + 1;
          weekdayCounts[local.weekday] =
              (weekdayCounts[local.weekday] ?? 0) + 1;
        }
        final averageInterval =
            latest == null || first == null || backupEvents.length < 2
            ? null
            : Duration(
                milliseconds:
                    latest.difference(first).inMilliseconds ~/
                    (backupEvents.length - 1),
              );
        final parts = entry.key.split('/');
        return BackupScheduleItem(
          backupType: parts.first,
          backupId: parts.length > 1 ? parts[1] : '',
          count: backupEvents.length,
          typicalHour: _mostCommon(hourCounts),
          weekdayCounts: weekdayCounts,
          datastores: snapshots
              .map((snapshot) => snapshot['datastore']?.toString() ?? '')
              .where((datastore) => datastore.isNotEmpty)
              .toSet(),
          averageInterval: averageInterval,
          latestBackupAt: latest,
        );
      }).toList()..sort((a, b) {
        final hourCompare = a.typicalHour.compareTo(b.typicalHour);
        if (hourCompare != 0) {
          return hourCompare;
        }
        return a.displayName.compareTo(b.displayName);
      });

  return BackupScheduleReport(
    items: items,
    calendarDays: calendarCounts.entries
        .map(
          (entry) => BackupCalendarDay(
            day: entry.key,
            count: entry.value,
            entries: entriesByDay[entry.key] ?? const <BackupCalendarEntry>[],
          ),
        )
        .toList(),
    calendarEntries: calendarEntries
      ..sort((left, right) => left.backupAt.compareTo(right.backupAt)),
    totalSnapshots: snapshots.length,
  );
}

List<Map<String, Object?>> _uniqueSnapshotsByBackupTime(
  List<Map<String, Object?>> snapshots,
) {
  final seen = <int>{};
  final result = <Map<String, Object?>>[];
  for (final snapshot in snapshots) {
    final time = snapshotTime(snapshot).toUtc().millisecondsSinceEpoch;
    if (seen.add(time)) {
      result.add(snapshot);
    }
  }
  return result;
}

class _BackupCalendarEventGroup {
  _BackupCalendarEventGroup({
    required this.backupType,
    required this.backupId,
    required this.backupAt,
  });

  final String backupType;
  final String backupId;
  final DateTime backupAt;
  final Set<String> backupSources = <String>{};
  final Set<String> datastores = <String>{};

  void add({required String backupSource, required String datastore}) {
    if (backupSource.isNotEmpty) {
      backupSources.add(backupSource);
    }
    if (datastore.isNotEmpty) {
      datastores.add(datastore);
    }
  }

  BackupCalendarEntry toEntry() {
    return BackupCalendarEntry(
      backupType: backupType,
      backupId: backupId,
      backupAt: backupAt,
      datastore: datastores.join(', '),
      backupSource: backupSources.join(', '),
    );
  }
}

BackupCoverageReport analyzeBackupCoverage(
  List<Map<String, Object?>> snapshots,
) {
  final byGuest = <String, List<Map<String, Object?>>>{};
  final byDay = <DateTime, int>{};
  var totalSizeBytes = 0.0;

  for (final snapshot in snapshots) {
    final backupType = snapshot['backup-type']?.toString() ?? '';
    final backupId = snapshot['backup-id']?.toString() ?? '';
    if (backupType.isEmpty || backupId.isEmpty) {
      continue;
    }

    final time = snapshotTime(snapshot);
    final day = DateTime(time.year, time.month, time.day);
    byDay[day] = (byDay[day] ?? 0) + 1;
    byGuest.putIfAbsent(
      '$backupType/$backupId',
      () => <Map<String, Object?>>[],
    );
    byGuest['$backupType/$backupId']!.add(snapshot);
    totalSizeBytes += _snapshotSize(snapshot);
  }

  final guests =
      byGuest.entries.map((entry) {
        final snapshots = entry.value
          ..sort((a, b) => snapshotTime(b).compareTo(snapshotTime(a)));
        final latest = snapshots.isEmpty ? null : snapshotTime(snapshots.first);
        final first = snapshots.isEmpty ? null : snapshotTime(snapshots.last);
        final averageInterval =
            latest == null || first == null || snapshots.length < 2
            ? null
            : Duration(
                milliseconds:
                    latest.difference(first).inMilliseconds ~/
                    (snapshots.length - 1),
              );
        final parts = entry.key.split('/');
        return BackupGuestReport(
          backupType: parts.first,
          backupId: parts.length > 1 ? parts[1] : '',
          datastores: snapshots
              .map((snapshot) => snapshot['datastore']?.toString() ?? '')
              .where((datastore) => datastore.isNotEmpty)
              .toSet(),
          count: snapshots.length,
          totalSizeBytes: snapshots.fold<double>(
            0,
            (sum, snapshot) => sum + _snapshotSize(snapshot),
          ),
          averageInterval: averageInterval,
          latestBackupAt: latest,
        );
      }).toList()..sort((a, b) {
        final latestCompare = (b.latestBackupAt ?? DateTime(0)).compareTo(
          a.latestBackupAt ?? DateTime(0),
        );
        if (latestCompare != 0) {
          return latestCompare;
        }
        return a.displayName.compareTo(b.displayName);
      });

  final dailyCounts =
      byDay.entries
          .map((entry) => BackupDayCount(day: entry.key, count: entry.value))
          .toList()
        ..sort((a, b) => a.day.compareTo(b.day));

  return BackupCoverageReport(
    guests: guests,
    dailyCounts: dailyCounts,
    totalSnapshots: snapshots.length,
    protectedGuests: guests.where((guest) => guest.count > 0).length,
    totalSizeBytes: totalSizeBytes,
  );
}

GuestBackupSummary analyzeGuestBackups({
  required String guestType,
  required String vmid,
  required List<Map<String, Object?>> snapshots,
  DateTime? now,
}) {
  final expectedBackupType = guestType == 'lxc' ? 'ct' : 'vm';
  final matches = snapshots.where((snapshot) {
    return snapshot['backup-id']?.toString() == vmid &&
        snapshot['backup-type']?.toString() == expectedBackupType;
  }).toList();

  matches.sort((a, b) {
    return snapshotTime(b).compareTo(snapshotTime(a));
  });

  if (matches.isEmpty) {
    return const GuestBackupSummary(
      matches: <Map<String, Object?>>[],
      status: BackupAgeStatus.missing,
    );
  }

  final latest = matches.first;
  final latestAt = snapshotTime(latest);
  final age = (now ?? DateTime.now().toUtc()).difference(latestAt);
  final status = switch (age.inHours) {
    <= 24 => BackupAgeStatus.ok,
    <= 168 => BackupAgeStatus.warning,
    _ => BackupAgeStatus.critical,
  };

  return GuestBackupSummary(
    matches: matches,
    latestBackupAt: latestAt,
    latestSnapshot: latest,
    status: status,
  );
}

String backupStatusLabel(BackupAgeStatus status) {
  return switch (status) {
    BackupAgeStatus.ok => 'ok',
    BackupAgeStatus.warning => 'warning',
    BackupAgeStatus.critical => 'critical',
    BackupAgeStatus.missing => 'missing',
  };
}

String backupStatusDescription(BackupAgeStatus status) {
  return switch (status) {
    BackupAgeStatus.ok => 'Последний backup был в течение 24 часов.',
    BackupAgeStatus.warning => 'Последний backup был от 1 до 7 дней назад.',
    BackupAgeStatus.critical => 'Последний backup старше 7 дней.',
    BackupAgeStatus.missing => 'Snapshots для этой VM/LXC не найдены.',
  };
}

DateTime snapshotTime(Map<String, Object?> snapshot) {
  final value = snapshot['backup-time'];
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
  }
  if (value is double) {
    return DateTime.fromMillisecondsSinceEpoch(
      (value * 1000).round(),
      isUtc: true,
    );
  }
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  return parsed?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

double _snapshotSize(Map<String, Object?> snapshot) {
  return double.tryParse(snapshot['size']?.toString() ?? '') ?? 0;
}

DateTime _startOfDay(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

int _mostCommon(Map<int, int> counts) {
  if (counts.isEmpty) {
    return 0;
  }
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final countCompare = b.value.compareTo(a.value);
      if (countCompare != 0) {
        return countCompare;
      }
      return a.key.compareTo(b.key);
    });
  return entries.first.key;
}
