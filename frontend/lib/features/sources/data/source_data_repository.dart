import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/features/sources/domain/source.dart';

class SourceDataRepository {
  SourceDataRepository(this._api);

  final ApiClient _api;

  Future<ProxmoxVeData> loadProxmoxVe(String sourceId) async {
    final results = await Future.wait(<Future<List<Map<String, Object?>>>>[
      _list('/proxmox-ve/$sourceId/nodes'),
      _list('/proxmox-ve/$sourceId/node-resources'),
      _list('/proxmox-ve/$sourceId/vm-resources'),
      _list('/proxmox-ve/$sourceId/storage-resources'),
      _list('/proxmox-ve/$sourceId/resources'),
      _list('/proxmox-ve/$sourceId/tasks'),
    ]);

    final nodes = results[0];
    final nodeResources = results[1];
    final vmResources = results[2];
    final storageResources = results[3];
    final resources = results[4];
    final tasks = results[5];
    final nodeStatuses = _nodesHaveMetrics(nodes) || nodeResources.isNotEmpty
        ? <Map<String, Object?>>[]
        : await _listOptional('/proxmox-ve/$sourceId/node-statuses');
    final nodeGuests = vmResources.isNotEmpty
        ? <Map<String, Object?>>[]
        : await _listOptional('/proxmox-ve/$sourceId/node-guests');
    final nodeStorage = storageResources.isNotEmpty
        ? <Map<String, Object?>>[]
        : await _listOptional('/proxmox-ve/$sourceId/node-storage');
    final effectiveVmResources = vmResources.isNotEmpty
        ? vmResources
        : nodeGuests;
    final effectiveStorageResources = storageResources.isNotEmpty
        ? storageResources
        : nodeStorage;
    final mergedResources = <Map<String, Object?>>[
      if (resources.any(
        (item) => item['type'] == 'qemu' || item['type'] == 'lxc',
      ))
        ...resources
      else
        ...effectiveVmResources,
    ];

    return ProxmoxVeData(
      nodes: _mergeNodeMetrics(
        nodes: nodes,
        nodeResources: nodeResources,
        nodeStatuses: nodeStatuses,
      ),
      nodeResources: nodeResources,
      vmResources: effectiveVmResources,
      storageResources: effectiveStorageResources,
      resources: mergedResources,
      tasks: tasks,
    );
  }

  Future<Map<String, Object?>> loadGuestStatus({
    required String sourceId,
    required String node,
    required String guestType,
    required String vmid,
  }) async {
    final Map<String, Object?> json = await _api.get(
      '/proxmox-ve/$sourceId/nodes/${Uri.encodeComponent(node)}/$guestType/$vmid/status/current',
    );
    final Object? data = json['data'];
    if (data is Map) {
      return data.cast<String, Object?>();
    }
    return <String, Object?>{};
  }

  Future<ProxmoxBackupData> loadProxmoxBackup(String sourceId) async {
    final List<Map<String, Object?>> datastores = await _list(
      '/proxmox-backup/$sourceId/datastores',
    );
    final List<Map<String, Object?>> tasks = await _list(
      '/proxmox-backup/$sourceId/tasks',
    );
    final List<Map<String, Object?>> snapshots = <Map<String, Object?>>[];

    for (final Map<String, Object?> datastore in datastores) {
      final String? store = datastore['store'] as String?;
      if (store == null || store.isEmpty) {
        continue;
      }
      final List<Map<String, Object?>> datastoreSnapshots = await _list(
        '/proxmox-backup/$sourceId/datastores/${Uri.encodeComponent(store)}/snapshots',
      );
      snapshots.addAll(
        datastoreSnapshots.map(
          (Map<String, Object?> snapshot) => <String, Object?>{
            'datastore': store,
            ...snapshot,
          },
        ),
      );
    }

    return ProxmoxBackupData(
      datastores: datastores,
      tasks: tasks,
      snapshots: snapshots,
    );
  }

  Future<SourceRuntimeData> load(Source source) async {
    if (source.type == 'proxmox_ve') {
      return SourceRuntimeData(proxmoxVe: await loadProxmoxVe(source.id));
    }
    if (source.type == 'proxmox_backup') {
      return SourceRuntimeData(
        proxmoxBackup: await loadProxmoxBackup(source.id),
      );
    }
    return const SourceRuntimeData();
  }

  Future<List<Map<String, Object?>>> _list(String path) async {
    final Map<String, Object?> json = await _api.get(path);
    final Object? data = json['data'];
    if (data is! List) {
      return <Map<String, Object?>>[];
    }
    return data
        .whereType<Map>()
        .map((Map<dynamic, dynamic> item) => item.cast<String, Object?>())
        .toList();
  }

  Future<List<Map<String, Object?>>> _listOptional(String path) async {
    try {
      return await _list(path);
    } catch (_) {
      return <Map<String, Object?>>[];
    }
  }
}

class SourceRuntimeData {
  const SourceRuntimeData({this.proxmoxVe, this.proxmoxBackup});

  final ProxmoxVeData? proxmoxVe;
  final ProxmoxBackupData? proxmoxBackup;
}

bool _nodesHaveMetrics(List<Map<String, Object?>> nodes) {
  return nodes.any(
    (node) =>
        node.containsKey('cpu') ||
        node.containsKey('mem') ||
        node.containsKey('maxmem') ||
        node.containsKey('disk') ||
        node.containsKey('maxdisk'),
  );
}

class ProxmoxVeData {
  const ProxmoxVeData({
    required this.nodes,
    required this.nodeResources,
    required this.vmResources,
    required this.storageResources,
    required this.resources,
    required this.tasks,
  });

  final List<Map<String, Object?>> nodes;
  final List<Map<String, Object?>> nodeResources;
  final List<Map<String, Object?>> vmResources;
  final List<Map<String, Object?>> storageResources;
  final List<Map<String, Object?>> resources;
  final List<Map<String, Object?>> tasks;
}

class ProxmoxBackupData {
  const ProxmoxBackupData({
    required this.datastores,
    required this.tasks,
    required this.snapshots,
  });

  final List<Map<String, Object?>> datastores;
  final List<Map<String, Object?>> tasks;
  final List<Map<String, Object?>> snapshots;
}

List<Map<String, Object?>> _mergeNodeMetrics({
  required List<Map<String, Object?>> nodes,
  required List<Map<String, Object?>> nodeResources,
  required List<Map<String, Object?>> nodeStatuses,
}) {
  final resourcesByNode = <String, Map<String, Object?>>{};
  for (final resource in nodeResources) {
    final nodeName =
        resource['node']?.toString() ?? resource['name']?.toString() ?? '';
    if (nodeName.isNotEmpty) {
      resourcesByNode[nodeName] = resource;
    }
  }
  final statusesByNode = <String, Map<String, Object?>>{};
  for (final status in nodeStatuses) {
    final nodeName = status['node']?.toString() ?? '';
    if (nodeName.isNotEmpty) {
      statusesByNode[nodeName] = _normalizeNodeStatus(status);
    }
  }

  return nodes.map((node) {
    final nodeName = node['node']?.toString() ?? '';
    final resource = resourcesByNode[nodeName];
    final status = statusesByNode[nodeName];
    return <String, Object?>{
      ...?resource,
      ...?status,
      ...node,
      if (resource?['cpu'] != null) 'cpu': resource?['cpu'],
      if (status?['cpu'] != null) 'cpu': status?['cpu'],
      if (resource?['mem'] != null) 'mem': resource?['mem'],
      if (resource?['maxmem'] != null) 'maxmem': resource?['maxmem'],
      if (status?['mem'] != null) 'mem': status?['mem'],
      if (status?['maxmem'] != null) 'maxmem': status?['maxmem'],
      if (resource?['disk'] != null) 'disk': resource?['disk'],
      if (resource?['maxdisk'] != null) 'maxdisk': resource?['maxdisk'],
      if (status?['disk'] != null) 'disk': status?['disk'],
      if (status?['maxdisk'] != null) 'maxdisk': status?['maxdisk'],
    };
  }).toList();
}

Map<String, Object?> _normalizeNodeStatus(Map<String, Object?> status) {
  final memory = status['memory'];
  final rootfs = status['rootfs'];
  final normalized = <String, Object?>{...status};
  if (memory is Map) {
    normalized['mem'] = memory['used'];
    normalized['maxmem'] = memory['total'];
  }
  if (rootfs is Map) {
    normalized['disk'] = rootfs['used'];
    normalized['maxdisk'] = rootfs['total'];
  }
  return normalized;
}
