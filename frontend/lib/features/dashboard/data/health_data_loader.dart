import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/features/sources/data/source_data_repository.dart';
import 'package:frontend/features/sources/domain/source.dart';

class HealthRuntimeData {
  const HealthRuntimeData({
    required this.nodes,
    required this.guests,
    required this.tasks,
    required this.backupSnapshots,
    required this.collectionErrors,
  });

  final List<Map<String, Object?>> nodes;
  final List<Map<String, Object?>> guests;
  final List<Map<String, Object?>> tasks;
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
  final snapshots = <Map<String, Object?>>[];
  final errors = <Map<String, Object?>>[];

  for (final source in sources) {
    try {
      if (source.type == 'proxmox_ve') {
        final data = await repository.loadProxmoxVe(source.id);
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
              ...guest,
            },
          ),
        );
        tasks.addAll(
          data.tasks.map(
            (task) => <String, Object?>{'source': source.name, ...task},
          ),
        );
      }
      if (source.type == 'proxmox_backup') {
        final data = await repository.loadProxmoxBackup(source.id);
        snapshots.addAll(
          data.snapshots.map(
            (snapshot) => <String, Object?>{
              'backupSource': source.name,
              ...snapshot,
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
    backupSnapshots: snapshots,
    collectionErrors: errors,
  );
}
