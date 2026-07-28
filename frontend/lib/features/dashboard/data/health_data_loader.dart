import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/features/sources/data/source_data_repository.dart';
import 'package:frontend/features/sources/domain/backup_analysis.dart';
import 'package:frontend/features/sources/domain/source.dart';

class HealthRuntimeData {
  const HealthRuntimeData({
    required this.nodes,
    required this.guests,
    required this.tasks,
    required this.storageResources,
    required this.backupSnapshots,
    required this.collectionErrors,
  });

  final List<Map<String, Object?>> nodes;
  final List<Map<String, Object?>> guests;
  final List<Map<String, Object?>> tasks;
  final List<Map<String, Object?>> storageResources;
  final List<Map<String, Object?>> backupSnapshots;
  final List<Map<String, Object?>> collectionErrors;
}

Future<HealthRuntimeData> loadHealthRuntimeData(
  BuildContext context,
  List<Source> sources,
) async {
  final repository = SourceDataRepository(context.read<ApiClient>());
  final nodes = <Map<String, Object?>>[];
  final guests = <Map<String, Object?>>[];
  final tasks = <Map<String, Object?>>[];
  final storageResources = <Map<String, Object?>>[];
  final snapshots = <Map<String, Object?>>[];
  final errors = <Map<String, Object?>>[];
  final healthSources = sources
      .where(
        (source) =>
            source.type == 'proxmox_ve' || source.type == 'proxmox_backup',
      )
      .toList(growable: false);

  final runtimeData = await Future.wait(
    healthSources.map((source) async {
      try {
        return await repository.load(source);
      } catch (error) {
        errors.add(<String, Object?>{
          'source': source.name,
          'type': source.type,
          'error': error.toString(),
        });
        return const SourceRuntimeData();
      }
    }),
  );

  for (var index = 0; index < healthSources.length; index += 1) {
    final source = healthSources[index];
    final runtime = runtimeData[index];
    try {
      if (source.type == 'proxmox_ve') {
        final data = runtime.proxmoxVe;
        if (data == null) {
          continue;
        }
        final backupNamespaces = backupNamespacesFromStorageConfig(
          data.storageConfig,
          manualNamespace: source.backupNamespace,
        );
        final effectiveBackupNamespaces = backupNamespaces.isEmpty
            ? <String>[source.backupNamespace]
            : backupNamespaces.toList();
        nodes.addAll(
          data.nodes.map(
            (node) => <String, Object?>{
              'source': source.name,
              'sourceId': source.id,
              ...node,
            },
          ),
        );
        guests.addAll(
          data.vmResources.map(
            (guest) => <String, Object?>{
              'source': source.name,
              'sourceId': source.id,
              'backupNamespace': source.backupNamespace,
              'backupNamespaces': effectiveBackupNamespaces,
              ...guest,
            },
          ),
        );
        tasks.addAll(
          data.tasks.map(
            (task) => <String, Object?>{'source': source.name, ...task},
          ),
        );
        storageResources.addAll(
          data.storageResources.map(
            (storage) => <String, Object?>{
              'source': source.name,
              'sourceId': source.id,
              ...storage,
            },
          ),
        );
      }
      if (source.type == 'proxmox_backup') {
        final data = runtime.proxmoxBackup;
        if (data == null) {
          continue;
        }
        snapshots.addAll(
          data.snapshots.map(
            (snapshot) => <String, Object?>{
              'backupSource': source.name,
              ...snapshot,
            },
          ),
        );
        tasks.addAll(
          data.tasks.map(
            (task) => <String, Object?>{
              'source': source.name,
              'sourceId': source.id,
              'sourceType': source.type,
              ...task,
            },
          ),
        );
        storageResources.addAll(
          data.datastoreUsage.map(
            (storage) => <String, Object?>{
              'source': source.name,
              'sourceId': source.id,
              'node': 'PBS',
              'storage': storage['store'] ?? storage['name'],
              'disk': storage['used'],
              'maxdisk': storage['total'],
              ...storage,
            },
          ),
        );
      }
    } catch (error) {
      errors.add(<String, Object?>{
        'source': source.name,
        'type': source.type,
        'error': error.toString(),
      });
    }
  }

  return HealthRuntimeData(
    nodes: nodes,
    guests: guests
        .where((guest) => guest['type'] == 'qemu' || guest['type'] == 'lxc')
        .toList(),
    tasks: tasks,
    storageResources: storageResources,
    backupSnapshots: snapshots,
    collectionErrors: errors,
  );
}
