import 'package:neotelecom_backend/core/logging/app_logger.dart';
import 'package:neotelecom_backend/features/integrations/proxmox_api_client.dart';
import 'package:neotelecom_backend/features/sources/source.dart';
import 'package:neotelecom_backend/features/sources/sources_service.dart';

class InfrastructureReadService {
  InfrastructureReadService(this._sources, this._client, this._logger);

  final SourcesService _sources;
  final ProxmoxApiClient _client;
  final AppLogger _logger;

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

  Future<Object?> proxmoxBackupSnapshots(
      String sourceId, String datastore) async {
    final Source source = _requireSource(sourceId, 'proxmox_backup');
    return _client.getBackup(
      source,
      await _sources.credentialFor(source.id),
      '/api2/json/admin/datastore/$datastore/snapshots',
    );
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
