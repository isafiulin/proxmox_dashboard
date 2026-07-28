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
      _listOptional('/proxmox-ve/$sourceId/storage-config'),
      _list('/proxmox-ve/$sourceId/resources'),
      _list('/proxmox-ve/$sourceId/tasks'),
    ]);

    final nodes = results[0];
    final nodeResources = results[1];
    final vmResources = results[2];
    final storageResources = results[3];
    final storageConfig = results[4];
    final resources = results[5];
    final tasks = results[6];
    final nodeStatuses = await _listOptional(
      '/proxmox-ve/$sourceId/node-statuses',
    );
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
      nodes: _withSourceId(
        _mergeNodeMetrics(
          nodes: nodes,
          nodeResources: nodeResources,
          nodeStatuses: nodeStatuses,
        ),
        sourceId,
      ),
      nodeResources: _withSourceId(nodeResources, sourceId),
      vmResources: _withSourceId(effectiveVmResources, sourceId),
      storageResources: _withSourceId(effectiveStorageResources, sourceId),
      storageConfig: _withSourceId(storageConfig, sourceId),
      resources: _withSourceId(mergedResources, sourceId),
      tasks: _withSourceId(tasks, sourceId),
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

  Future<Map<String, Object?>> loadNodeVersion({
    required String sourceId,
    required String node,
  }) {
    return _mapOptional(
      '/proxmox-ve/$sourceId/nodes/${Uri.encodeComponent(node)}/version',
    );
  }

  Future<List<Map<String, Object?>>> loadStorageConfig(String sourceId) {
    return _listOptional('/proxmox-ve/$sourceId/storage-config');
  }

  Future<List<Map<String, Object?>>> loadNodeNetwork({
    required String sourceId,
    required String node,
  }) {
    return _listOptional(
      '/proxmox-ve/$sourceId/nodes/${Uri.encodeComponent(node)}/network',
    );
  }

  Future<List<Map<String, Object?>>> loadGuestInterfaces({
    required String sourceId,
    required String node,
    required String guestType,
    required String vmid,
  }) {
    return _guestInterfacesOptional(
      '/proxmox-ve/$sourceId/nodes/${Uri.encodeComponent(node)}/$guestType/$vmid/interfaces',
    );
  }

  Future<ProxmoxBackupData> loadProxmoxBackup(String sourceId) async {
    final results = await Future.wait<Object>(<Future<Object>>[
      _list('/proxmox-backup/$sourceId/datastores'),
      _list('/proxmox-backup/$sourceId/tasks'),
      _mapOptional('/proxmox-backup/$sourceId/health'),
    ]);
    final datastores = results[0] as List<Map<String, Object?>>;
    final tasks = results[1] as List<Map<String, Object?>>;
    final health = results[2] as Map<String, Object?>;
    final List<Map<String, Object?>> snapshots = <Map<String, Object?>>[];
    final List<Map<String, Object?>> namespaceRows = <Map<String, Object?>>[];
    final datastoreResults = await Future.wait(
      datastores.map((datastore) async {
        final store = datastore['store']?.toString() ?? '';
        if (store.isEmpty) {
          return const (
            namespaces: <Map<String, Object?>>[],
            snapshots: <Map<String, Object?>>[],
          );
        }
        final namespaces = await _backupNamespaces(sourceId, store);
        final snapshotBatches = await Future.wait(
          namespaces.map((namespace) async {
            final path =
                '/proxmox-backup/$sourceId/datastores/${Uri.encodeComponent(store)}/snapshots'
                '${namespace.isEmpty ? '' : '?namespace=${Uri.encodeQueryComponent(namespace)}'}';
            final datastoreSnapshots = await _list(path);
            return datastoreSnapshots
                .map(
                  (snapshot) => <String, Object?>{
                    'datastore': store,
                    'namespace': namespace,
                    ...snapshot,
                  },
                )
                .toList();
          }),
        );
        return (
          namespaces: namespaces
              .map(
                (namespace) => <String, Object?>{
                  'datastore': store,
                  'namespace': namespace.isEmpty ? 'root' : namespace,
                },
              )
              .toList(),
          snapshots: snapshotBatches.expand((batch) => batch).toList(),
        );
      }),
    );
    for (final result in datastoreResults) {
      namespaceRows.addAll(result.namespaces);
      snapshots.addAll(result.snapshots);
    }

    return ProxmoxBackupData(
      datastores: _withSourceId(datastores, sourceId),
      tasks: _withSourceId(tasks, sourceId),
      snapshots: _withSourceId(snapshots, sourceId),
      namespaces: _withSourceId(namespaceRows, sourceId),
      datastoreUsage: _withSourceId(_mapList(health['datastores']), sourceId),
      verifyJobs: _withSourceId(_mapList(health['verifyJobs']), sourceId),
      pruneJobs: _withSourceId(_mapList(health['pruneJobs']), sourceId),
      gcJobs: _withSourceId(_mapList(health['gcJobs']), sourceId),
      syncJobs: _withSourceId(_mapList(health['syncJobs']), sourceId),
      datastoreConfig: _withSourceId(
        _mapList(health['datastoreConfig']),
        sourceId,
      ),
      healthErrors: _withSourceId(_mapList(health['errors']), sourceId),
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
    if (source.type == 'redfish' ||
        source.type == 'old_ilo2' ||
        source.type == 'ipmi') {
      return SourceRuntimeData(
        redfish: await loadRedfish(source.id, sourceType: source.type),
      );
    }
    return const SourceRuntimeData();
  }

  Future<RedfishData> loadRedfish(
    String sourceId, {
    bool refresh = false,
    String sourceType = 'redfish',
  }) async {
    final prefix = switch (sourceType) {
      'old_ilo2' => 'old-ilo2',
      'ipmi' => 'ipmi',
      _ => 'redfish',
    };
    final path = '/$prefix/$sourceId/inventory';
    final json = refresh ? await _api.post(path) : await _api.get(path);
    final data = _stringMap(json['data']);
    final snapshot = _stringMap(data['_snapshot']);
    final thermal = _mapList(data['thermal']);
    final power = _mapList(data['power']);
    final temperatures = _mapList(data['temperatures']);
    final fans = _mapList(data['fans']);
    final powerSupplies = _mapList(data['powerSupplies']);
    return RedfishData(
      identity: _stringMap(data['identity']),
      systems: _withSourceId(_mapList(data['systems']), sourceId),
      processors: _withSourceId(_mapList(data['processors']), sourceId),
      memory: _withSourceId(_mapList(data['memory']), sourceId),
      chassis: _withSourceId(_mapList(data['chassis']), sourceId),
      managers: _withSourceId(_mapList(data['managers']), sourceId),
      temperatures: temperatures.isNotEmpty
          ? _withSourceId(temperatures, sourceId)
          : _nestedRows(thermal, 'Temperatures', sourceId),
      fans: fans.isNotEmpty
          ? _withSourceId(fans, sourceId)
          : _nestedRows(thermal, 'Fans', sourceId),
      powerControl: _withSourceId(_mapList(data['powerControl']), sourceId),
      powerSupplies: powerSupplies.isNotEmpty
          ? _withSourceId(powerSupplies, sourceId)
          : _nestedRows(power, 'PowerSupplies', sourceId),
      storageControllers: _withSourceId(
        _mapList(data['storageControllers']),
        sourceId,
      ),
      volumes: _withSourceId(_mapList(data['volumes']), sourceId),
      drives: _withSourceId(_mapList(data['drives']), sourceId),
      ethernetInterfaces: _withSourceId(
        _mapList(data['ethernetInterfaces']),
        sourceId,
      ),
      networkInterfaces: _withSourceId(
        _mapList(data['networkInterfaces']),
        sourceId,
      ),
      networkAdapters: _withSourceId(
        _mapList(data['networkAdapters']),
        sourceId,
      ),
      boards: _withSourceId(_mapList(data['boards']), sourceId),
      discreteSensors: _withSourceId(
        _mapList(data['discreteSensors']),
        sourceId,
      ),
      thresholdSensors: _withSourceId(
        _mapList(data['thresholdSensors']),
        sourceId,
      ),
      firmware: _withSourceId(_mapList(data['firmware']), sourceId),
      logEntries: _withSourceId(_mapList(data['logEntries']), sourceId),
      healthIssues: _withSourceId(_mapList(data['healthIssues']), sourceId),
      errors: _withSourceId(_mapList(data['errors']), sourceId),
      collectedAt: DateTime.tryParse(snapshot['collectedAt']?.toString() ?? ''),
      collecting: snapshot['collecting'] == true,
      stale: snapshot['stale'] == true,
      refreshError: snapshot['refreshError']?.toString(),
    );
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

  Future<List<String>> _backupNamespaces(
    String sourceId,
    String datastore,
  ) async {
    final namespaces = <String>{''};
    final rows = await _listOptional(
      '/proxmox-backup/$sourceId/datastores/${Uri.encodeComponent(datastore)}/namespaces',
    );
    for (final row in rows) {
      final namespace =
          row['ns']?.toString() ??
          row['namespace']?.toString() ??
          row['path']?.toString() ??
          '';
      if (namespace.isNotEmpty) {
        namespaces.add(namespace);
      }
    }
    return namespaces.toList();
  }

  Future<Map<String, Object?>> _mapOptional(String path) async {
    try {
      final Map<String, Object?> json = await _api.get(path);
      final Object? data = json['data'];
      if (data is Map) {
        return data.cast<String, Object?>();
      }
    } catch (_) {
      return <String, Object?>{};
    }
    return <String, Object?>{};
  }

  Future<List<Map<String, Object?>>> _guestInterfacesOptional(
    String path,
  ) async {
    try {
      final Map<String, Object?> json = await _api.get(path);
      final Object? data = json['data'];
      final Object? interfaces = data is Map ? data['result'] : data;
      if (interfaces is! List) {
        return <Map<String, Object?>>[];
      }
      return interfaces
          .whereType<Map>()
          .map((Map<dynamic, dynamic> item) => item.cast<String, Object?>())
          .toList();
    } catch (_) {
      return <Map<String, Object?>>[];
    }
  }
}

class SourceRuntimeData {
  const SourceRuntimeData({this.proxmoxVe, this.proxmoxBackup, this.redfish});

  final ProxmoxVeData? proxmoxVe;
  final ProxmoxBackupData? proxmoxBackup;
  final RedfishData? redfish;
}

class RedfishData {
  const RedfishData({
    required this.identity,
    required this.systems,
    required this.processors,
    required this.memory,
    required this.chassis,
    required this.managers,
    required this.temperatures,
    required this.fans,
    required this.powerControl,
    required this.powerSupplies,
    required this.storageControllers,
    required this.volumes,
    required this.drives,
    required this.ethernetInterfaces,
    required this.networkInterfaces,
    required this.networkAdapters,
    required this.boards,
    required this.discreteSensors,
    required this.thresholdSensors,
    required this.firmware,
    required this.logEntries,
    required this.healthIssues,
    required this.errors,
    required this.collectedAt,
    required this.collecting,
    required this.stale,
    required this.refreshError,
  });

  final Map<String, Object?> identity;
  final List<Map<String, Object?>> systems;
  final List<Map<String, Object?>> processors;
  final List<Map<String, Object?>> memory;
  final List<Map<String, Object?>> chassis;
  final List<Map<String, Object?>> managers;
  final List<Map<String, Object?>> temperatures;
  final List<Map<String, Object?>> fans;
  final List<Map<String, Object?>> powerControl;
  final List<Map<String, Object?>> powerSupplies;
  final List<Map<String, Object?>> storageControllers;
  final List<Map<String, Object?>> volumes;
  final List<Map<String, Object?>> drives;
  final List<Map<String, Object?>> ethernetInterfaces;
  final List<Map<String, Object?>> networkInterfaces;
  final List<Map<String, Object?>> networkAdapters;
  final List<Map<String, Object?>> boards;
  final List<Map<String, Object?>> discreteSensors;
  final List<Map<String, Object?>> thresholdSensors;
  final List<Map<String, Object?>> firmware;
  final List<Map<String, Object?>> logEntries;
  final List<Map<String, Object?>> healthIssues;
  final List<Map<String, Object?>> errors;
  final DateTime? collectedAt;
  final bool collecting;
  final bool stale;
  final String? refreshError;
}

class ProxmoxVeData {
  const ProxmoxVeData({
    required this.nodes,
    required this.nodeResources,
    required this.vmResources,
    required this.storageResources,
    required this.storageConfig,
    required this.resources,
    required this.tasks,
  });

  final List<Map<String, Object?>> nodes;
  final List<Map<String, Object?>> nodeResources;
  final List<Map<String, Object?>> vmResources;
  final List<Map<String, Object?>> storageResources;
  final List<Map<String, Object?>> storageConfig;
  final List<Map<String, Object?>> resources;
  final List<Map<String, Object?>> tasks;
}

class ProxmoxBackupData {
  const ProxmoxBackupData({
    required this.datastores,
    required this.tasks,
    required this.snapshots,
    required this.namespaces,
    required this.datastoreUsage,
    required this.verifyJobs,
    required this.pruneJobs,
    required this.gcJobs,
    required this.syncJobs,
    required this.datastoreConfig,
    required this.healthErrors,
  });

  final List<Map<String, Object?>> datastores;
  final List<Map<String, Object?>> tasks;
  final List<Map<String, Object?>> snapshots;
  final List<Map<String, Object?>> namespaces;
  final List<Map<String, Object?>> datastoreUsage;
  final List<Map<String, Object?>> verifyJobs;
  final List<Map<String, Object?>> pruneJobs;
  final List<Map<String, Object?>> gcJobs;
  final List<Map<String, Object?>> syncJobs;
  final List<Map<String, Object?>> datastoreConfig;
  final List<Map<String, Object?>> healthErrors;
}

List<Map<String, Object?>> _mapList(Object? value) {
  if (value is! List) {
    return <Map<String, Object?>>[];
  }
  return value
      .whereType<Map>()
      .map((item) => item.cast<String, Object?>())
      .toList();
}

Map<String, Object?> _stringMap(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};

List<Map<String, Object?>> _nestedRows(
  List<Map<String, Object?>> parents,
  String key,
  String sourceId,
) => _withSourceId(
  parents.expand((parent) => _mapList(parent[key])).toList(),
  sourceId,
);

List<Map<String, Object?>> _withSourceId(
  List<Map<String, Object?>> rows,
  String sourceId,
) =>
    rows.map((row) => <String, Object?>{'sourceId': sourceId, ...row}).toList();

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
