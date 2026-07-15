class PbsVerifyItem {
  const PbsVerifyItem({
    required this.backupSourceId,
    required this.backupSource,
    required this.datastore,
    required this.namespace,
    required this.backupType,
    required this.backupId,
    required this.backupTime,
    required this.state,
    required this.reason,
  });

  final String backupSourceId;
  final String backupSource;
  final String datastore;
  final String namespace;
  final String backupType;
  final String backupId;
  final DateTime? backupTime;
  final String state;
  final String reason;

  String get backupGroup => '$backupType/$backupId';
}

List<PbsVerifyItem> buildPbsVerifyItems(List<Map<String, Object?>> snapshots) {
  final items = snapshots.map((snapshot) {
    final verification = snapshot['verification'];
    final verificationMap = verification is Map ? verification : null;
    final rawState =
        verificationMap?['state'] ??
        snapshot['verify-state'] ??
        snapshot['verification-state'] ??
        (verification is String ? verification : null);
    final state = _normalizeVerifyState(rawState?.toString() ?? 'unverified');
    final reason =
        verificationMap?['message']?.toString() ??
        verificationMap?['upid']?.toString() ??
        snapshot['verify-error']?.toString() ??
        '';
    return PbsVerifyItem(
      backupSourceId: snapshot['backupSourceId']?.toString() ?? '',
      backupSource: snapshot['backupSource']?.toString() ?? '',
      datastore: snapshot['datastore']?.toString() ?? '',
      namespace: snapshot['namespace']?.toString() ?? '',
      backupType: snapshot['backup-type']?.toString() ?? '',
      backupId: snapshot['backup-id']?.toString() ?? '',
      backupTime: _timestamp(snapshot['backup-time']),
      state: state,
      reason: reason,
    );
  }).toList();
  items.sort((left, right) {
    final stateCompare = _verifyRisk(
      right.state,
    ).compareTo(_verifyRisk(left.state));
    if (stateCompare != 0) {
      return stateCompare;
    }
    return (right.backupTime ?? DateTime(0)).compareTo(
      left.backupTime ?? DateTime(0),
    );
  });
  return items;
}

bool isFailedPbsTask(Map<String, Object?> task) {
  if (task['endtime'] == null) {
    return false;
  }
  final status = task['status']?.toString().trim().toLowerCase() ?? '';
  return status.isNotEmpty && status != 'ok' && status != 'unknown';
}

bool isPbsMaintenanceTask(Map<String, Object?> task) {
  final type = task['worker_type']?.toString().toLowerCase() ?? '';
  return type.contains('verify') ||
      type.contains('prune') ||
      type.contains('garbage') ||
      type == 'gc';
}

String pbsBackupLocation(Map<String, Object?> snapshot) {
  final source =
      snapshot['backupSourceId']?.toString().trim().isNotEmpty == true
      ? snapshot['backupSourceId'].toString().trim()
      : snapshot['backupSource']?.toString().trim() ?? '';
  final datastore = snapshot['datastore']?.toString().trim() ?? '';
  final namespace = snapshot['namespace']?.toString().trim() ?? '';
  return '$source\u0001$datastore\u0001$namespace';
}

String _normalizeVerifyState(String value) {
  final state = value.trim().toLowerCase();
  if (state == 'ok' || state == 'verified') {
    return 'ok';
  }
  if (state.contains('fail') || state.contains('error')) {
    return 'critical';
  }
  return 'unverified';
}

int _verifyRisk(String state) => switch (state) {
  'critical' => 2,
  'unverified' => 1,
  _ => 0,
};

DateTime? _timestamp(Object? value) {
  final seconds = int.tryParse(value?.toString() ?? '');
  if (seconds == null || seconds <= 0) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}
