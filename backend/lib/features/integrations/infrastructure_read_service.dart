import 'package:neotelecom_backend/core/logging/app_logger.dart';
import 'package:neotelecom_backend/features/integrations/proxmox_api_client.dart';
import 'package:neotelecom_backend/features/integrations/redfish_api_client.dart';
import 'package:neotelecom_backend/features/sources/source.dart';
import 'package:neotelecom_backend/features/sources/sources_service.dart';

class InfrastructureReadService {
  InfrastructureReadService(
    this._sources,
    this._client,
    this._redfishClient,
    this._logger,
  );

  final SourcesService _sources;
  final ProxmoxApiClient _client;
  final RedfishApiClient _redfishClient;
  final AppLogger _logger;
  final Map<String, ({DateTime storedAt, Object? data})> _backupSnapshotCache =
      {};
  final Map<String, Future<Object?>> _backupSnapshotRequests = {};

  Future<Map<String, Object?>> redfishInventory(String sourceId) async {
    final source = _requireSource(sourceId, 'redfish');
    return _redfishClient.inventory(
      source,
      await _sources.credentialFor(source.id),
    );
  }

  Future<Object?> proxmoxVeNodes(String sourceId) async {
    final Source source = _requireSource(sourceId, 'proxmox_ve');
    return _client.getVe(
        source, await _sources.credentialFor(source.id), '/api2/json/nodes');
  }

  Future<Object?> proxmoxVeResources(String sourceId) async {
    final Source source = _requireSource(sourceId, 'proxmox_ve');
    return _client.getVe(source, await _sources.credentialFor(source.id),
        '/api2/json/cluster/resources');
  }

  Future<Object?> proxmoxVeNodeResources(String sourceId) async {
    final Source source = _requireSource(sourceId, 'proxmox_ve');
    return _client.getVe(source, await _sources.credentialFor(source.id),
        '/api2/json/cluster/resources?type=node');
  }

  Future<Object?> proxmoxVeVmResources(String sourceId) async {
    final Source source = _requireSource(sourceId, 'proxmox_ve');
    return _client.getVe(source, await _sources.credentialFor(source.id),
        '/api2/json/cluster/resources?type=vm');
  }

  Future<Object?> proxmoxVeStorageResources(String sourceId) async {
    final Source source = _requireSource(sourceId, 'proxmox_ve');
    return _client.getVe(source, await _sources.credentialFor(source.id),
        '/api2/json/cluster/resources?type=storage');
  }

  Future<Object?> proxmoxVeStorageConfig(String sourceId) async {
    final Source source = _requireSource(sourceId, 'proxmox_ve');
    return _client.getVe(
      source,
      await _sources.credentialFor(source.id),
      '/api2/json/storage',
    );
  }

  Future<Object?> proxmoxVeNodeStatuses(String sourceId) async {
    final Source source = _requireSource(sourceId, 'proxmox_ve');
    final credential = await _sources.credentialFor(source.id);
    final nodes = await _nodeNames(source, credential);
    final statuses = <Map<String, Object?>>[];
    for (final node in nodes) {
      try {
        final status = await _client.getVe(
          source,
          credential,
          '/api2/json/nodes/${Uri.encodeComponent(node)}/status',
        );
        if (status is Map) {
          statuses.add(<String, Object?>{
            'node': node,
            ...status.cast<String, Object?>(),
          });
        }
      } on ProxmoxApiException catch (error) {
        _logger.warning('integration.node_status_skipped', <String, Object?>{
          'sourceId': source.id,
          'node': node,
          'error': error.message,
        });
        // Keep the cluster page usable when a token has partial node access.
      }
    }
    return statuses;
  }

  Future<Object?> proxmoxVeNodeGuests(String sourceId) async {
    final Source source = _requireSource(sourceId, 'proxmox_ve');
    final credential = await _sources.credentialFor(source.id);
    final nodes = await _nodeNames(source, credential);
    final guests = <Map<String, Object?>>[];
    for (final node in nodes) {
      guests
        ..addAll(await _nodeGuestList(source, credential, node, 'qemu'))
        ..addAll(await _nodeGuestList(source, credential, node, 'lxc'));
    }
    return guests;
  }

  Future<Object?> proxmoxVeNodeStorage(String sourceId) async {
    final Source source = _requireSource(sourceId, 'proxmox_ve');
    final credential = await _sources.credentialFor(source.id);
    final nodes = await _nodeNames(source, credential);
    final storage = <Map<String, Object?>>[];
    for (final node in nodes) {
      try {
        final data = await _client.getVe(
          source,
          credential,
          '/api2/json/nodes/${Uri.encodeComponent(node)}/storage',
        );
        if (data is List) {
          storage.addAll(
            data.whereType<Map>().map(
                  (item) => <String, Object?>{
                    'node': node,
                    ...item.cast<String, Object?>(),
                  },
                ),
          );
        }
      } on ProxmoxApiException catch (error) {
        _logger.warning('integration.node_storage_skipped', <String, Object?>{
          'sourceId': source.id,
          'node': node,
          'error': error.message,
        });
        // Keep the cluster page usable when a token has partial node access.
      }
    }
    return storage;
  }

  Future<Object?> proxmoxVeTasks(String sourceId) async {
    final Source source = _requireSource(sourceId, 'proxmox_ve');
    return _client.getVe(source, await _sources.credentialFor(source.id),
        '/api2/json/cluster/tasks');
  }

  Future<Object?> proxmoxVeNodeVersion(String sourceId, String node) async {
    final Source source = _requireSource(sourceId, 'proxmox_ve');
    return _client.getVe(
      source,
      await _sources.credentialFor(source.id),
      '/api2/json/nodes/${Uri.encodeComponent(node)}/version',
    );
  }

  Future<Object?> proxmoxVeNodeNetwork(String sourceId, String node) async {
    final Source source = _requireSource(sourceId, 'proxmox_ve');
    return _client.getVe(
      source,
      await _sources.credentialFor(source.id),
      '/api2/json/nodes/${Uri.encodeComponent(node)}/network',
    );
  }

  Future<Object?> proxmoxVeGuestInterfaces(
      String sourceId, String node, String guestType, String vmid) async {
    final Source source = _requireSource(sourceId, 'proxmox_ve');
    if (guestType != 'qemu' && guestType != 'lxc') {
      throw const InfrastructureReadException('invalid_guest_type');
    }
    final credential = await _sources.credentialFor(source.id);
    final path = guestType == 'qemu'
        ? '/api2/json/nodes/${Uri.encodeComponent(node)}/qemu/$vmid/agent/network-get-interfaces'
        : '/api2/json/nodes/${Uri.encodeComponent(node)}/lxc/$vmid/interfaces';
    return _client.getVe(source, credential, path);
  }

  Future<List<String>> _nodeNames(Source source, String credential) async {
    final data = await _client.getVe(source, credential, '/api2/json/nodes');
    if (data is! List) {
      return <String>[];
    }
    return data
        .whereType<Map>()
        .map((node) => node['node']?.toString() ?? '')
        .where((node) => node.isNotEmpty)
        .toList();
  }

  Future<List<Map<String, Object?>>> _nodeGuestList(
    Source source,
    String credential,
    String node,
    String guestType,
  ) async {
    final Object? data;
    try {
      data = await _client.getVe(
        source,
        credential,
        '/api2/json/nodes/${Uri.encodeComponent(node)}/$guestType',
      );
    } on ProxmoxApiException catch (error) {
      _logger.warning('integration.node_guest_list_skipped', <String, Object?>{
        'sourceId': source.id,
        'node': node,
        'guestType': guestType,
        'error': error.message,
      });
      return <Map<String, Object?>>[];
    }
    if (data is! List) {
      return <Map<String, Object?>>[];
    }
    return data.whereType<Map>().map((item) {
      return <String, Object?>{
        'node': node,
        'type': guestType,
        ...item.cast<String, Object?>(),
      };
    }).toList();
  }

  Future<Object?> proxmoxVeGuestStatus(
      String sourceId, String node, String guestType, String vmid) async {
    final Source source = _requireSource(sourceId, 'proxmox_ve');
    if (guestType != 'qemu' && guestType != 'lxc') {
      throw const InfrastructureReadException('invalid_guest_type');
    }
    return _client.getVe(source, await _sources.credentialFor(source.id),
        '/api2/json/nodes/$node/$guestType/$vmid/status/current');
  }

  Future<Object?> proxmoxBackupDatastores(String sourceId) async {
    final Source source = _requireSource(sourceId, 'proxmox_backup');
    return _client.getBackup(source, await _sources.credentialFor(source.id),
        '/api2/json/admin/datastore');
  }

  Future<Object?> proxmoxBackupTasks(String sourceId) async {
    final Source source = _requireSource(sourceId, 'proxmox_backup');
    return _client.getBackup(source, await _sources.credentialFor(source.id),
        '/api2/json/nodes/localhost/tasks?limit=250');
  }

  Future<Object?> proxmoxBackupHealth(String sourceId) async {
    final Source source = _requireSource(sourceId, 'proxmox_backup');
    final credential = await _sources.credentialFor(source.id);
    final errors = <Map<String, Object?>>[];
    final results = await Future.wait<
        List<Map<String, Object?>>>(<Future<List<Map<String, Object?>>>>[
      _optionalBackupList(
        source,
        credential,
        '/api2/json/status/datastore-usage',
        'datastore_usage',
        errors,
      ),
      _optionalBackupList(
        source,
        credential,
        '/api2/json/config/verify',
        'verify_jobs',
        errors,
      ),
      _optionalBackupList(
        source,
        credential,
        '/api2/json/config/prune',
        'prune_jobs',
        errors,
      ),
      _optionalBackupList(
        source,
        credential,
        '/api2/json/config/sync',
        'sync_jobs',
        errors,
      ),
      _optionalBackupList(
        source,
        credential,
        '/api2/json/config/datastore',
        'datastore_config',
        errors,
      ),
    ]);
    final datastores = results[0];
    final verifyJobs = results[1];
    final pruneJobs = results[2];
    final syncJobs = results[3];
    final datastoreConfig = results[4];
    final gcJobs = datastoreConfig
        .where(
            (row) => row['gc-schedule']?.toString().trim().isNotEmpty == true)
        .toList();
    return <String, Object?>{
      'datastores': datastores,
      'verifyJobs': verifyJobs,
      'pruneJobs': pruneJobs,
      'gcJobs': gcJobs,
      'syncJobs': syncJobs,
      'datastoreConfig': datastoreConfig,
      'errors': errors,
    };
  }

  Future<Object?> proxmoxBackupNamespaces(
      String sourceId, String datastore) async {
    final Source source = _requireSource(sourceId, 'proxmox_backup');
    return _client.getBackup(
      source,
      await _sources.credentialFor(source.id),
      '/api2/json/admin/datastore/$datastore/namespace?max-depth=7',
    );
  }

  Future<Object?> proxmoxBackupSnapshots(String sourceId, String datastore,
      {String namespace = ''}) async {
    final Source source = _requireSource(sourceId, 'proxmox_backup');
    final normalizedNamespace = namespace.trim();
    final cacheKey = '$sourceId\u0001$datastore\u0001$normalizedNamespace';
    final cached = _backupSnapshotCache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.storedAt) <
            const Duration(seconds: 30)) {
      return cached.data;
    }
    final activeRequest = _backupSnapshotRequests[cacheKey];
    if (activeRequest != null) {
      return activeRequest;
    }

    final nsQuery = normalizedNamespace.isEmpty
        ? ''
        : '?ns=${Uri.encodeQueryComponent(normalizedNamespace)}';
    final request = () async {
      return _client.getBackup(
        source,
        await _sources.credentialFor(source.id),
        '/api2/json/admin/datastore/$datastore/snapshots$nsQuery',
      );
    }();
    _backupSnapshotRequests[cacheKey] = request;
    try {
      final data = await request;
      _backupSnapshotCache[cacheKey] = (
        storedAt: DateTime.now(),
        data: data,
      );
      return data;
    } finally {
      _backupSnapshotRequests.remove(cacheKey);
    }
  }

  Future<List<Map<String, Object?>>> _optionalBackupList(
    Source source,
    String credential,
    String path,
    String operation,
    List<Map<String, Object?>> errors,
  ) async {
    try {
      final data = await _client.getBackup(source, credential, path);
      if (data is! List) {
        return <Map<String, Object?>>[];
      }
      return data
          .whereType<Map>()
          .map((item) => item.cast<String, Object?>())
          .toList();
    } on ProxmoxApiException catch (error) {
      errors.add(<String, Object?>{
        'operation': operation,
        'message': error.message,
        'path': error.path ?? path,
        'statusCode': error.statusCode,
      });
      _logger.warning('integration.pbs_health_skipped', <String, Object?>{
        'sourceId': source.id,
        'operation': operation,
        'error': error.message,
      });
      return <Map<String, Object?>>[];
    }
  }

  Source _requireSource(String sourceId, String type) {
    final Source? source = _sources.byId(sourceId);
    if (source == null) {
      throw const InfrastructureReadException('source_not_found');
    }
    if (source.type != type) {
      throw const InfrastructureReadException('source_type_mismatch');
    }
    return source;
  }
}

class InfrastructureReadException implements Exception {
  const InfrastructureReadException(this.code);

  final String code;
}
