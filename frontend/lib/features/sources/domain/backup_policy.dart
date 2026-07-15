enum BackupPolicyIssueType {
  keepLastOne,
  missingPrune,
  missingVerify,
  missingGc,
  infrequentVerify,
  uncoveredNamespace,
}

class BackupPolicyIssue {
  const BackupPolicyIssue({
    required this.type,
    required this.sourceId,
    required this.sourceName,
    required this.datastore,
    required this.namespace,
    required this.message,
  });

  final BackupPolicyIssueType type;
  final String sourceId;
  final String sourceName;
  final String datastore;
  final String namespace;
  final String message;

  String get status => switch (type) {
    BackupPolicyIssueType.keepLastOne ||
    BackupPolicyIssueType.infrequentVerify => 'warning',
    _ => 'critical',
  };
}

List<BackupPolicyIssue> analyzeBackupPolicy({
  required String sourceId,
  required String sourceName,
  required List<Map<String, Object?>> namespaces,
  required List<Map<String, Object?>> datastoreConfig,
  required List<Map<String, Object?>> pruneJobs,
  required List<Map<String, Object?>> verifyJobs,
  required List<Map<String, Object?>> gcJobs,
}) {
  final scopes = namespaces.isEmpty
      ? datastoreConfig.map(
          (row) => <String, Object?>{
            'datastore': _store(row),
            'namespace': 'root',
          },
        )
      : namespaces;
  final issues = <BackupPolicyIssue>[];
  for (final scope in scopes) {
    final datastore = _store(scope);
    if (datastore.isEmpty) {
      continue;
    }
    final rawNamespace = scope['namespace']?.toString().trim() ?? '';
    final namespace = rawNamespace == 'root' ? '' : rawNamespace;
    final config = datastoreConfig
        .where((row) => _store(row) == datastore)
        .firstOrNull;
    final matchingPrune = pruneJobs
        .where((job) => backupJobCovers(job, datastore, namespace))
        .toList();
    final matchingVerify = verifyJobs
        .where((job) => backupJobCovers(job, datastore, namespace))
        .toList();
    final hasLegacyPrune = _hasText(config?['prune-schedule']);
    final hasGc =
        gcJobs.any((job) => _store(job) == datastore) ||
        _hasText(config?['gc-schedule']);

    void add(BackupPolicyIssueType type, String message) {
      issues.add(
        BackupPolicyIssue(
          type: type,
          sourceId: sourceId,
          sourceName: sourceName,
          datastore: datastore,
          namespace: namespace,
          message: message,
        ),
      );
    }

    if (matchingPrune.isEmpty && !hasLegacyPrune) {
      add(BackupPolicyIssueType.missingPrune, 'Prune schedule не найден.');
    }
    if (matchingVerify.isEmpty) {
      add(BackupPolicyIssueType.missingVerify, 'Verify job не найден.');
    }
    if (!hasGc) {
      add(BackupPolicyIssueType.missingGc, 'GC schedule не найден.');
    }
    if (matchingPrune.any(_hasKeepLastOne) || _hasKeepLastOne(config ?? {})) {
      add(
        BackupPolicyIssueType.keepLastOne,
        'keep-last=1 оставляет только одну последнюю точку восстановления.',
      );
    }
    if (matchingVerify.any(_verifyIsInfrequent)) {
      add(
        BackupPolicyIssueType.infrequentVerify,
        'Verify запускается без schedule или re-verify позже 30 дней.',
      );
    }
    if (matchingPrune.isEmpty && matchingVerify.isEmpty) {
      add(
        BackupPolicyIssueType.uncoveredNamespace,
        'Namespace не покрыт ни prune, ни verify job.',
      );
    }
  }
  return issues;
}

bool backupJobCovers(
  Map<String, Object?> job,
  String datastore,
  String namespace,
) {
  if (_store(job) != datastore) {
    return false;
  }
  final jobNamespace =
      job['ns']?.toString().trim() ?? job['namespace']?.toString().trim() ?? '';
  if (jobNamespace.isEmpty) {
    return namespace.isEmpty || _maxDepth(job) > 0;
  }
  if (namespace == jobNamespace) {
    return true;
  }
  if (!namespace.startsWith('$jobNamespace/')) {
    return false;
  }
  final extraDepth =
      namespace.split('/').length - jobNamespace.split('/').length;
  return extraDepth <= _maxDepth(job);
}

int _maxDepth(Map<String, Object?> job) {
  return int.tryParse(job['max-depth']?.toString() ?? '') ?? 7;
}

String _store(Map<String, Object?> row) =>
    row['store']?.toString() ??
    row['datastore']?.toString() ??
    row['name']?.toString() ??
    '';

bool _hasKeepLastOne(Map<String, Object?> row) =>
    int.tryParse(row['keep-last']?.toString() ?? '') == 1;

bool _verifyIsInfrequent(Map<String, Object?> row) {
  final outdatedAfter = int.tryParse(row['outdated-after']?.toString() ?? '');
  return !_hasText(row['schedule']) ||
      (outdatedAfter != null && outdatedAfter > 30);
}

bool _hasText(Object? value) => value?.toString().trim().isNotEmpty == true;
