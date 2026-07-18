class GuestBackupSummary {
  const GuestBackupSummary({
    required this.matches,
    required this.status,
    this.matchQuality = BackupMatchQuality.idOnly,
    this.nameMismatchSnapshots = const <Map<String, Object?>>[],
    this.latestBackupAt,
    this.latestSnapshot,
  });

  final List<Map<String, Object?>> matches;
  final BackupAgeStatus status;
  final BackupMatchQuality matchQuality;
  final List<Map<String, Object?>> nameMismatchSnapshots;
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
    this.namespace = '',
    this.latestBackupAt,
  });

  final String backupType;
  final String backupId;
  final Set<String> datastores;
  final int count;
  final double totalSizeBytes;
  final Duration? averageInterval;
  final String namespace;
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
    this.namespace = '',
    this.latestBackupAt,
  });

  final String backupType;
  final String backupId;
  final int count;
  final int typicalHour;
  final Map<int, int> weekdayCounts;
  final Set<String> datastores;
  final Duration? averageInterval;
  final String namespace;
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
    this.namespace = '',
  });

  final String backupType;
  final String backupId;
  final DateTime backupAt;
  final String datastore;
  final String backupSource;
  final String namespace;

  String get displayName => '$backupType/$backupId';
}

class BackupMissingGuestsReport {
  const BackupMissingGuestsReport({
    required this.items,
    required this.totalBackupGroups,
    required this.deployedGuests,
  });

  final List<BackupMissingGuestItem> items;
  final int totalBackupGroups;
  final int deployedGuests;

  int get missingGroups => items.length;
}

class BackupMissingGuestItem {
  const BackupMissingGuestItem({
    required this.backupType,
    required this.backupId,
    required this.snapshotName,
    required this.namespace,
    required this.backupSources,
    required this.datastores,
    required this.count,
    required this.totalSizeBytes,
    required this.candidates,
    this.latestBackupAt,
  });

  final String backupType;
  final String backupId;
  final String snapshotName;
  final String namespace;
  final Set<String> backupSources;
  final Set<String> datastores;
  final int count;
  final double totalSizeBytes;
  final DateTime? latestBackupAt;
  final List<BackupMissingGuestCandidate> candidates;

  String get displayName => '$backupType/$backupId';
}

class BackupNamespaceGap {
  const BackupNamespaceGap({
    required this.sourceId,
    required this.sourceName,
    required this.node,
    required this.guestType,
    required this.vmid,
    required this.name,
    required this.expectedNamespaces,
    required this.rootLatestBackupAt,
    required this.rootBackupCount,
  });

  final String sourceId;
  final String sourceName;
  final String node;
  final String guestType;
  final String vmid;
  final String name;
  final Set<String> expectedNamespaces;
  final DateTime? rootLatestBackupAt;
  final int rootBackupCount;

  String get displayName => '$guestType/$vmid';
}

class BackupMissingGuestCandidate {
  const BackupMissingGuestCandidate({
    required this.sourceId,
    required this.sourceName,
    required this.node,
    required this.guestType,
    required this.vmid,
    required this.name,
    required this.reason,
    required this.score,
  });

  final String sourceId;
  final String sourceName;
  final String node;
  final String guestType;
  final String vmid;
  final String name;
  final String reason;
  final int score;

  String get displayName => '$guestType/$vmid';
}

enum BackupAgeStatus { ok, warning, critical, missing }

enum BackupMatchQuality { nameConfirmed, idOnly, nameMissing, nameMismatch }

BackupMissingGuestsReport analyzeMissingBackupGuests({
  required List<Map<String, Object?>> snapshots,
  required List<Map<String, Object?>> guests,
}) {
  final deployedGuests = guests
      .where((guest) {
        return guest['type'] == 'qemu' || guest['type'] == 'lxc';
      })
      .map(_BackupGuestIdentity.fromGuest)
      .toList();
  final deployedByBackupKey = <String, List<_BackupGuestIdentity>>{};
  for (final guest in deployedGuests) {
    for (final backupKey in guest.backupKeys) {
      deployedByBackupKey.putIfAbsent(
        backupKey,
        () => <_BackupGuestIdentity>[],
      );
      deployedByBackupKey[backupKey]!.add(guest);
    }
  }

  final groups = <String, List<Map<String, Object?>>>{};
  for (final snapshot in snapshots) {
    final backupType = snapshot['backup-type']?.toString() ?? '';
    final backupId = snapshot['backup-id']?.toString() ?? '';
    if (backupType.isEmpty || backupId.isEmpty) {
      continue;
    }
    final namespace = snapshotNamespace(snapshot);
    final name = _normalizeName(_snapshotName(snapshot));
    final groupKey = name.isEmpty
        ? _backupKey(namespace, backupType, backupId)
        : '${_backupKey(namespace, backupType, backupId)}/$name';
    groups.putIfAbsent(groupKey, () => <Map<String, Object?>>[]);
    groups[groupKey]!.add(snapshot);
  }

  final items = <BackupMissingGuestItem>[];
  for (final group in groups.values) {
    group.sort(
      (left, right) => snapshotTime(right).compareTo(snapshotTime(left)),
    );
    final latest = group.first;
    final backupType = latest['backup-type']?.toString() ?? '';
    final backupId = latest['backup-id']?.toString() ?? '';
    final snapshotName = _snapshotName(latest);
    final normalizedSnapshotName = _normalizeName(snapshotName);
    final backupKey = _backupKey(
      snapshotNamespace(latest),
      backupType,
      backupId,
    );
    final exactCandidates =
        deployedByBackupKey[backupKey] ?? const <_BackupGuestIdentity>[];
    final hasExactMatch = exactCandidates.any((guest) {
      if (normalizedSnapshotName.isEmpty) {
        return true;
      }
      return guest.normalizedName == normalizedSnapshotName;
    });
    if (hasExactMatch) {
      continue;
    }

    items.add(
      BackupMissingGuestItem(
        backupType: backupType,
        backupId: backupId,
        snapshotName: snapshotName,
        namespace: snapshotNamespace(latest),
        backupSources: group
            .map((snapshot) => snapshot['backupSource']?.toString() ?? '')
            .where((value) => value.isNotEmpty)
            .toSet(),
        datastores: group
            .map((snapshot) => snapshot['datastore']?.toString() ?? '')
            .where((value) => value.isNotEmpty)
            .toSet(),
        count: group.length,
        totalSizeBytes: group.fold<double>(
          0,
          (sum, snapshot) => sum + _snapshotSize(snapshot),
        ),
        latestBackupAt: snapshotTime(latest),
        candidates: _missingGuestCandidates(
          snapshotName: snapshotName,
          backupKey: backupKey,
          guests: deployedGuests,
        ),
      ),
    );
  }

  items.sort((left, right) {
    final latestCompare = _compareNullableDateTime(
      right.latestBackupAt,
      left.latestBackupAt,
    );
    if (latestCompare != 0) {
      return latestCompare;
    }
    return left.displayName.compareTo(right.displayName);
  });

  return BackupMissingGuestsReport(
    items: items,
    totalBackupGroups: groups.length,
    deployedGuests: deployedGuests.length,
  );
}

List<BackupMissingGuestCandidate> _missingGuestCandidates({
  required String snapshotName,
  required String backupKey,
  required List<_BackupGuestIdentity> guests,
}) {
  final normalizedSnapshotName = _normalizeName(snapshotName);
  final candidates = <BackupMissingGuestCandidate>[];
  for (final guest in guests) {
    var score = 0;
    var reason = '';
    if (normalizedSnapshotName.isNotEmpty &&
        guest.normalizedName.isNotEmpty &&
        (guest.normalizedName.contains(normalizedSnapshotName) ||
            normalizedSnapshotName.contains(guest.normalizedName))) {
      score = 100;
      reason = 'name match';
    } else if (guest.backupKeys.contains(backupKey)) {
      score = 60;
      reason = 'same backup id';
    }
    if (score == 0) {
      continue;
    }
    candidates.add(
      BackupMissingGuestCandidate(
        sourceId: guest.sourceId,
        sourceName: guest.sourceName,
        node: guest.node,
        guestType: guest.guestType,
        vmid: guest.vmid,
        name: guest.name,
        reason: reason,
        score: score,
      ),
    );
  }
  candidates.sort((left, right) {
    final scoreCompare = right.score.compareTo(left.score);
    if (scoreCompare != 0) {
      return scoreCompare;
    }
    return left.name.toLowerCase().compareTo(right.name.toLowerCase());
  });
  return candidates.take(3).toList();
}

class _BackupGuestIdentity {
  const _BackupGuestIdentity({
    required this.sourceId,
    required this.sourceName,
    required this.node,
    required this.guestType,
    required this.vmid,
    required this.name,
    required this.namespaces,
  });

  factory _BackupGuestIdentity.fromGuest(Map<String, Object?> guest) {
    final guestType = guest['type']?.toString() ?? '';
    final vmid = guest['vmid']?.toString() ?? '';
    final namespaces = _guestBackupNamespaces(guest);
    return _BackupGuestIdentity(
      sourceId: guest['sourceId']?.toString() ?? '',
      sourceName: guest['source']?.toString() ?? '',
      node: guest['node']?.toString() ?? '',
      guestType: guestType,
      vmid: vmid,
      name: guest['name']?.toString() ?? '',
      namespaces: namespaces.isEmpty ? const <String>{''} : namespaces,
    );
  }

  final String sourceId;
  final String sourceName;
  final String node;
  final String guestType;
  final String vmid;
  final String name;
  final Set<String> namespaces;

  String get backupType => guestType == 'lxc' ? 'ct' : 'vm';
  Iterable<String> get backupKeys =>
      namespaces.map((namespace) => _backupKey(namespace, backupType, vmid));
  String get normalizedName => _normalizeName(name);
}

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

    final namespace = snapshotNamespace(snapshot);
    final localTime = snapshotTime(snapshot).toLocal();
    final eventKey =
        '${_backupKey(namespace, backupType, backupId)}/${localTime.toUtc().millisecondsSinceEpoch}';
    final eventGroup = calendarEventGroups.putIfAbsent(
      eventKey,
      () => _BackupCalendarEventGroup(
        namespace: namespace,
        backupType: backupType,
        backupId: backupId,
        backupAt: localTime,
      ),
    );
    eventGroup.add(
      backupSource: snapshot['backupSource']?.toString() ?? '',
      datastore: snapshot['datastore']?.toString() ?? '',
    );
    final guestKey = _backupKey(namespace, backupType, backupId);
    byGuest.putIfAbsent(guestKey, () => <Map<String, Object?>>[]);
    byGuest[guestKey]!.add(snapshot);
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
        final parts = _parseBackupKey(entry.key);
        return BackupScheduleItem(
          namespace: parts.namespace,
          backupType: parts.backupType,
          backupId: parts.backupId,
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
    required this.namespace,
    required this.backupType,
    required this.backupId,
    required this.backupAt,
  });

  final String namespace;
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
      namespace: namespace,
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
    final guestKey = _backupKey(
      snapshotNamespace(snapshot),
      backupType,
      backupId,
    );
    byGuest.putIfAbsent(guestKey, () => <Map<String, Object?>>[]);
    byGuest[guestKey]!.add(snapshot);
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
        final parts = _parseBackupKey(entry.key);
        return BackupGuestReport(
          namespace: parts.namespace,
          backupType: parts.backupType,
          backupId: parts.backupId,
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
  String guestName = '',
  String backupNamespace = '',
  Iterable<String>? backupNamespaces,
  DateTime? now,
}) {
  final expectedBackupType = guestType == 'lxc' ? 'ct' : 'vm';
  final expectedNamespaces = (backupNamespaces ?? <String>[backupNamespace])
      .map((namespace) => namespace.trim())
      .toSet();
  if (expectedNamespaces.isEmpty) {
    expectedNamespaces.add('');
  }
  final idMatches = snapshots.where((snapshot) {
    return snapshot['backup-id']?.toString() == vmid &&
        snapshot['backup-type']?.toString() == expectedBackupType &&
        expectedNamespaces.contains(snapshotNamespace(snapshot));
  }).toList();

  final normalizedGuestName = _normalizeName(guestName);
  final namedSnapshots = idMatches
      .where((snapshot) => _snapshotName(snapshot).isNotEmpty)
      .toList();
  final nameConfirmedMatches = normalizedGuestName.isEmpty
      ? <Map<String, Object?>>[]
      : namedSnapshots.where((snapshot) {
          final snapshotName = _normalizeName(_snapshotName(snapshot));
          return snapshotName.contains(normalizedGuestName) ||
              normalizedGuestName.contains(snapshotName);
        }).toList();
  final nameMismatchSnapshots = normalizedGuestName.isEmpty
      ? <Map<String, Object?>>[]
      : namedSnapshots.where((snapshot) {
          final snapshotName = _normalizeName(_snapshotName(snapshot));
          return !snapshotName.contains(normalizedGuestName) &&
              !normalizedGuestName.contains(snapshotName);
        }).toList();
  final unnamedMatches = idMatches
      .where(
        (snapshot) =>
            _snapshotName(snapshot).isEmpty &&
            _hasExpectedGuestConfig(snapshot, expectedBackupType),
      )
      .toList();
  final hasNameMismatch =
      normalizedGuestName.isNotEmpty &&
      namedSnapshots.isNotEmpty &&
      nameConfirmedMatches.isEmpty;
  final List<Map<String, Object?>> matches;
  if (nameConfirmedMatches.isNotEmpty) {
    matches = nameConfirmedMatches;
  } else if (!hasNameMismatch && unnamedMatches.isNotEmpty) {
    // ponytail: PBS sometimes has no VM name/comment; VMID+namespace is the
    // fallback until we persist an explicit PVE-cluster-to-PBS mapping.
    matches = unnamedMatches;
  } else if (normalizedGuestName.isEmpty) {
    matches = idMatches;
  } else {
    matches = <Map<String, Object?>>[];
  }
  final matchQuality = nameConfirmedMatches.isNotEmpty
      ? BackupMatchQuality.nameConfirmed
      : hasNameMismatch
      ? BackupMatchQuality.nameMismatch
      : unnamedMatches.isNotEmpty
      ? BackupMatchQuality.nameMissing
      : BackupMatchQuality.idOnly;

  matches.sort((a, b) {
    return snapshotTime(b).compareTo(snapshotTime(a));
  });

  if (matches.isEmpty || hasNameMismatch) {
    return GuestBackupSummary(
      matches: <Map<String, Object?>>[],
      status: BackupAgeStatus.missing,
      matchQuality: matchQuality,
      nameMismatchSnapshots: nameMismatchSnapshots,
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
    matchQuality: matchQuality,
    nameMismatchSnapshots: nameMismatchSnapshots,
    status: status,
  );
}

List<BackupNamespaceGap> analyzeRootNamespaceGaps({
  required List<Map<String, Object?>> guests,
  required List<Map<String, Object?>> snapshots,
}) {
  final gaps = <BackupNamespaceGap>[];
  for (final guest in guests.where((guest) {
    return guest['type'] == 'qemu' || guest['type'] == 'lxc';
  })) {
    final expectedNamespaces = _guestBackupNamespaces(
      guest,
    ).where((namespace) => namespace.isNotEmpty).toSet();
    if (expectedNamespaces.isEmpty) {
      continue;
    }

    final guestType = guest['type']?.toString() ?? '';
    final vmid = guest['vmid']?.toString() ?? '';
    final guestName = guest['name']?.toString() ?? '';
    final expectedSummary = analyzeGuestBackups(
      guestType: guestType,
      vmid: vmid,
      guestName: guestName,
      backupNamespaces: expectedNamespaces,
      snapshots: snapshots,
    );
    if (expectedSummary.matches.isNotEmpty) {
      continue;
    }

    final rootSummary = analyzeGuestBackups(
      guestType: guestType,
      vmid: vmid,
      guestName: guestName,
      backupNamespaces: const <String>[''],
      snapshots: snapshots,
    );
    if (rootSummary.matches.isEmpty) {
      continue;
    }

    gaps.add(
      BackupNamespaceGap(
        sourceId: guest['sourceId']?.toString() ?? '',
        sourceName: guest['source']?.toString() ?? '',
        node: guest['node']?.toString() ?? '',
        guestType: guestType,
        vmid: vmid,
        name: guestName,
        expectedNamespaces: expectedNamespaces,
        rootLatestBackupAt: rootSummary.latestBackupAt,
        rootBackupCount: rootSummary.matches.length,
      ),
    );
  }

  gaps.sort((a, b) {
    final latestCompare = (a.rootLatestBackupAt ?? DateTime(0)).compareTo(
      b.rootLatestBackupAt ?? DateTime(0),
    );
    if (latestCompare != 0) {
      return latestCompare;
    }
    return a.displayName.compareTo(b.displayName);
  });
  return gaps;
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

String backupMatchDescription(BackupMatchQuality quality) {
  return switch (quality) {
    BackupMatchQuality.nameConfirmed =>
      'Backup подтвержден по VMID и имени VM/LXC в PBS notes.',
    BackupMatchQuality.idOnly =>
      'Backup сопоставлен по PBS namespace и VMID. Для одинаковых VMID в разных кластерах namespace должен быть задан в источнике PVE.',
    BackupMatchQuality.nameMissing =>
      'Backup сопоставлен по PBS namespace и VMID. Имя VM/LXC в PBS notes отсутствует, поэтому это менее сильное совпадение.',
    BackupMatchQuality.nameMismatch =>
      'Найден snapshot с таким VMID, но PBS notes указывают другое имя VM/LXC. Backup не засчитан, чтобы не смешать разные кластеры.',
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

String snapshotNamespace(Map<String, Object?> snapshot) {
  for (final key in <String>['namespace', 'ns', 'backup-ns']) {
    final value = snapshot[key]?.toString().trim() ?? '';
    if (value.isNotEmpty && value != '/') {
      return value;
    }
  }
  return '';
}

Set<String> backupNamespacesFromStorageConfig(
  List<Map<String, Object?>> storageConfig, {
  String manualNamespace = '',
}) {
  final namespaces = <String>{};
  final manual = manualNamespace.trim();
  if (manual.isNotEmpty) {
    namespaces.add(manual);
  }
  for (final storage in storageConfig) {
    final type = storage['type']?.toString().toLowerCase() ?? '';
    final plugin = storage['plugintype']?.toString().toLowerCase() ?? '';
    final isPbs =
        type == 'pbs' ||
        plugin == 'pbs' ||
        type == 'proxmox-backup' ||
        plugin == 'proxmox-backup';
    if (!isPbs) {
      continue;
    }
    final namespace =
        storage['namespace']?.toString() ??
        storage['ns']?.toString() ??
        storage['backup-ns']?.toString() ??
        '';
    final normalized = namespace.trim();
    if (normalized.isNotEmpty && normalized != '/') {
      namespaces.add(normalized);
    }
  }
  return namespaces;
}

Set<String> guestBackupNamespaces(Map<String, Object?> guest) {
  return _guestBackupNamespaces(guest);
}

Set<String> _guestBackupNamespaces(Map<String, Object?> guest) {
  final rawNamespaces = guest['backupNamespaces'];
  if (rawNamespaces is Iterable) {
    final namespaces = rawNamespaces
        .map((namespace) => namespace.toString().trim())
        .where((namespace) => namespace.isNotEmpty)
        .toSet();
    return namespaces.isEmpty ? const <String>{''} : namespaces;
  }

  final namespace = guest['backupNamespace']?.toString().trim() ?? '';
  return namespace.isEmpty ? const <String>{''} : <String>{namespace};
}

String _backupKey(String namespace, String backupType, String backupId) {
  return '${namespace.trim()}\u0001$backupType\u0001$backupId';
}

({String namespace, String backupType, String backupId}) _parseBackupKey(
  String key,
) {
  final parts = key.split('\u0001');
  return (
    namespace: parts.isNotEmpty ? parts[0] : '',
    backupType: parts.length > 1 ? parts[1] : '',
    backupId: parts.length > 2 ? parts[2] : '',
  );
}

double _snapshotSize(Map<String, Object?> snapshot) {
  return double.tryParse(snapshot['size']?.toString() ?? '') ?? 0;
}

bool _hasExpectedGuestConfig(
  Map<String, Object?> snapshot,
  String expectedBackupType,
) {
  final files = snapshot['files'];
  if (files is! Iterable) {
    return true;
  }

  final expectedConfig = expectedBackupType == 'ct'
      ? 'pct.conf.blob'
      : 'qemu-server.conf.blob';
  for (final file in files) {
    final filename = file is Map
        ? file['filename']?.toString() ?? ''
        : file.toString();
    if (filename == expectedConfig) {
      return true;
    }
  }
  return false;
}

String _snapshotName(Map<String, Object?> snapshot) {
  for (final key in <String>['comment', 'notes', 'note']) {
    final value = snapshot[key]?.toString() ?? '';
    if (value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return '';
}

String _normalizeName(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё]+'), '');
}

int _compareNullableDateTime(DateTime? left, DateTime? right) {
  if (left == null && right == null) {
    return 0;
  }
  if (left == null) {
    return 1;
  }
  if (right == null) {
    return -1;
  }
  return left.compareTo(right);
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
