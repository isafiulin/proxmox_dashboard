import 'package:frontend/features/sources/domain/backup_analysis.dart';

class NodeHealthReport {
  const NodeHealthReport({
    required this.nodes,
    required this.total,
    required this.online,
    required this.offline,
    required this.highCpu,
    required this.highRam,
  });

  final List<Map<String, Object?>> nodes;
  final int total;
  final int online;
  final int offline;
  final int highCpu;
  final int highRam;
}

class VmHealthReport {
  const VmHealthReport({
    required this.guests,
    required this.total,
    required this.running,
    required this.stopped,
    required this.highCpu,
    required this.highRam,
    required this.backupIssues,
  });

  final List<Map<String, Object?>> guests;
  final int total;
  final int running;
  final int stopped;
  final int highCpu;
  final int highRam;
  final int backupIssues;
}

NodeHealthReport buildNodeHealthReport(List<Map<String, Object?>> nodes) {
  var online = 0;
  var highCpu = 0;
  var highRam = 0;
  for (final node in nodes) {
    if (_status(node) == 'online') {
      online += 1;
    }
    if (_ratio(node['cpu']) >= 0.8) {
      highCpu += 1;
    }
    if (_ratioPair(node['mem'], node['maxmem']) >= 0.8) {
      highRam += 1;
    }
  }

  final sortedNodes = List<Map<String, Object?>>.from(nodes)
    ..sort((left, right) {
      final leftScore = _riskScore(left);
      final rightScore = _riskScore(right);
      return rightScore.compareTo(leftScore);
    });

  return NodeHealthReport(
    nodes: sortedNodes,
    total: nodes.length,
    online: online,
    offline: nodes.length - online,
    highCpu: highCpu,
    highRam: highRam,
  );
}

VmHealthReport buildVmHealthReport({
  required List<Map<String, Object?>> guests,
  required List<Map<String, Object?>> snapshots,
}) {
  var running = 0;
  var highCpu = 0;
  var highRam = 0;
  var backupIssues = 0;
  for (final guest in guests) {
    final status = _status(guest);
    if (status == 'running') {
      running += 1;
    }
    if (_ratio(guest['cpu']) >= 0.8) {
      highCpu += 1;
    }
    if (_ratioPair(guest['mem'], guest['maxmem']) >= 0.8) {
      highRam += 1;
    }
    final backupStatus = analyzeGuestBackups(
      guestType: guest['type']?.toString() ?? '',
      vmid: guest['vmid']?.toString() ?? '',
      guestName: guest['name']?.toString() ?? '',
      backupNamespace: guest['backupNamespace']?.toString() ?? '',
      backupNamespaces: guestBackupNamespaces(guest),
      snapshots: snapshots,
    ).status;
    if (backupStatus == BackupAgeStatus.critical ||
        backupStatus == BackupAgeStatus.missing) {
      backupIssues += 1;
    }
  }

  final sortedGuests = List<Map<String, Object?>>.from(guests)
    ..sort((left, right) {
      final leftScore = _riskScore(left);
      final rightScore = _riskScore(right);
      return rightScore.compareTo(leftScore);
    });

  return VmHealthReport(
    guests: sortedGuests,
    total: guests.length,
    running: running,
    stopped: guests.length - running,
    highCpu: highCpu,
    highRam: highRam,
    backupIssues: backupIssues,
  );
}

String healthStatusForLoad(double value) {
  if (value >= 0.9) {
    return 'critical';
  }
  if (value >= 0.75) {
    return 'warning';
  }
  return 'ok';
}

double ratioValue(Object? value) => _ratio(value);

double ratioPairValue(Object? used, Object? total) => _ratioPair(used, total);

String _status(Map<String, Object?> row) {
  return row['status']?.toString().toLowerCase() ?? '';
}

double _riskScore(Map<String, Object?> row) {
  final cpu = _ratio(row['cpu']);
  final ram = _ratioPair(row['mem'], row['maxmem']);
  final statusPenalty = switch (_status(row)) {
    'online' || 'running' => 0.0,
    _ => 1.0,
  };
  return statusPenalty + cpu + ram;
}

double _ratio(Object? value) {
  final parsed = double.tryParse(value?.toString() ?? '');
  if (parsed == null || parsed.isNaN || parsed.isInfinite) {
    return 0;
  }
  return parsed.clamp(0, 1).toDouble();
}

double _ratioPair(Object? used, Object? total) {
  final usedValue = double.tryParse(used?.toString() ?? '');
  final totalValue = double.tryParse(total?.toString() ?? '');
  if (usedValue == null || totalValue == null || totalValue <= 0) {
    return 0;
  }
  return (usedValue / totalValue).clamp(0, 1).toDouble();
}
