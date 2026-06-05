import 'package:frontend/features/snapshots/domain/data_snapshot.dart';

class ResourceHistoryPoint {
  const ResourceHistoryPoint({required this.time, required this.value});

  final DateTime time;
  final double value;
}

class ResourceHistoryReport {
  const ResourceHistoryReport({
    required this.nodeCpu,
    required this.nodeRam,
    required this.guestCpu,
    required this.guestRam,
    required this.storageUsage,
  });

  final List<ResourceHistoryPoint> nodeCpu;
  final List<ResourceHistoryPoint> nodeRam;
  final List<ResourceHistoryPoint> guestCpu;
  final List<ResourceHistoryPoint> guestRam;
  final List<ResourceHistoryPoint> storageUsage;

  bool get isEmpty =>
      nodeCpu.isEmpty &&
      nodeRam.isEmpty &&
      guestCpu.isEmpty &&
      guestRam.isEmpty &&
      storageUsage.isEmpty;
}

ResourceHistoryReport buildResourceHistory(List<DataSnapshot> snapshots) {
  final pveSnapshots =
      snapshots
          .where((snapshot) => snapshot.sourceType == 'proxmox_ve')
          .toList()
        ..sort((left, right) => left.collectedAt.compareTo(right.collectedAt));

  final nodeCpu = <ResourceHistoryPoint>[];
  final nodeRam = <ResourceHistoryPoint>[];
  final guestCpu = <ResourceHistoryPoint>[];
  final guestRam = <ResourceHistoryPoint>[];
  final storageUsage = <ResourceHistoryPoint>[];

  for (final snapshot in pveSnapshots) {
    final resources = _resourceRows(snapshot);
    final nodes = resources.where((row) => row['type'] == 'node').toList();
    final guests = resources
        .where((row) => row['type'] == 'qemu' || row['type'] == 'lxc')
        .toList();
    final storage = resources.where((row) => row['type'] == 'storage').toList();

    _addAverage(nodeCpu, snapshot.collectedAt, nodes, _cpuRatio);
    _addAverage(nodeRam, snapshot.collectedAt, nodes, _memoryRatio);
    _addAverage(guestCpu, snapshot.collectedAt, guests, _cpuRatio);
    _addAverage(guestRam, snapshot.collectedAt, guests, _memoryRatio);
    _addAverage(storageUsage, snapshot.collectedAt, storage, _diskRatio);
  }

  return ResourceHistoryReport(
    nodeCpu: nodeCpu,
    nodeRam: nodeRam,
    guestCpu: guestCpu,
    guestRam: guestRam,
    storageUsage: storageUsage,
  );
}

List<Map<String, Object?>> _resourceRows(DataSnapshot snapshot) {
  final resources = snapshot.payload['resources'];
  if (resources is! List) {
    return const <Map<String, Object?>>[];
  }
  return resources
      .whereType<Map>()
      .map((row) => row.cast<String, Object?>())
      .toList();
}

void _addAverage(
  List<ResourceHistoryPoint> points,
  DateTime time,
  List<Map<String, Object?>> rows,
  double Function(Map<String, Object?> row) valueFor,
) {
  final values = rows
      .map(valueFor)
      .where((value) => value.isFinite && !value.isNaN)
      .toList();
  if (values.isEmpty) {
    return;
  }
  final average = values.reduce((left, right) => left + right) / values.length;
  points.add(ResourceHistoryPoint(time: time, value: average.clamp(0, 1)));
}

double _cpuRatio(Map<String, Object?> row) {
  return double.tryParse(row['cpu']?.toString() ?? '') ?? double.nan;
}

double _memoryRatio(Map<String, Object?> row) {
  return _ratioPair(row['mem'], row['maxmem']);
}

double _diskRatio(Map<String, Object?> row) {
  return _ratioPair(row['disk'], row['maxdisk']);
}

double _ratioPair(Object? used, Object? total) {
  final usedValue = double.tryParse(used?.toString() ?? '');
  final totalValue = double.tryParse(total?.toString() ?? '');
  if (usedValue == null || totalValue == null || totalValue <= 0) {
    return double.nan;
  }
  return usedValue / totalValue;
}
