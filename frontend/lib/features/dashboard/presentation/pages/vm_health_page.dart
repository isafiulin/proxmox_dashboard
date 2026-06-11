import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/features/dashboard/data/health_data_loader.dart';
import 'package:frontend/features/dashboard/domain/health_models.dart';
import 'package:frontend/features/snapshots/domain/resource_history.dart';
import 'package:frontend/features/snapshots/presentation/cubit/snapshots_cubit.dart';
import 'package:frontend/features/sources/domain/backup_analysis.dart';
import 'package:frontend/features/sources/presentation/cubit/sources_cubit.dart';
import 'package:frontend/shared/formatters/value_formatters.dart';
import 'package:frontend/shared/widgets/app_card.dart';
import 'package:frontend/shared/widgets/async_state_view.dart';
import 'package:frontend/shared/widgets/empty_state.dart';
import 'package:frontend/shared/widgets/metric_card.dart';
import 'package:frontend/shared/widgets/page_header.dart';
import 'package:frontend/shared/widgets/resource_line_chart.dart';
import 'package:frontend/shared/widgets/sortable_data_table.dart';
import 'package:frontend/shared/widgets/status_chip.dart';
import 'package:go_router/go_router.dart';

class VmHealthPage extends StatelessWidget {
  const VmHealthPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SourcesCubit, SourcesState>(
      builder: (BuildContext context, SourcesState state) {
        if (state.status == SourcesStatus.loading && state.items.isEmpty) {
          return const LoadingStateView();
        }
        return FutureBuilder<HealthRuntimeData>(
          future: loadHealthRuntimeData(context, state.items),
          builder:
              (
                BuildContext context,
                AsyncSnapshot<HealthRuntimeData> snapshot,
              ) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LoadingStateView();
                }
                if (snapshot.hasError) {
                  return ErrorStateView(message: snapshot.error.toString());
                }
                return _VmHealthContent(
                  data:
                      snapshot.data ??
                      const HealthRuntimeData(
                        nodes: <Map<String, Object?>>[],
                        guests: <Map<String, Object?>>[],
                        tasks: <Map<String, Object?>>[],
                        storageResources: <Map<String, Object?>>[],
                        backupSnapshots: <Map<String, Object?>>[],
                        collectionErrors: <Map<String, Object?>>[],
                      ),
                );
              },
        );
      },
    );
  }
}

class _VmHealthContent extends StatelessWidget {
  const _VmHealthContent({required this.data});

  final HealthRuntimeData data;

  @override
  Widget build(BuildContext context) {
    final report = buildVmHealthReport(
      guests: data.guests,
      snapshots: data.backupSnapshots,
    );
    final history = buildResourceHistory(
      context.watch<SnapshotsCubit>().state.items,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const PageHeader(
          title: 'VM health',
          subtitle: 'Состояние VM/LXC, нагрузка, backup-сигналы и риски',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            MetricCard(
              label: 'VM/LXC',
              value: report.total.toString(),
              icon: Icons.developer_board_outlined,
            ),
            MetricCard(
              label: 'Running',
              value: report.running.toString(),
              icon: Icons.play_circle_outline,
            ),
            MetricCard(
              label: 'Stopped/other',
              value: report.stopped.toString(),
              icon: Icons.pause_circle_outline,
            ),
            MetricCard(
              label: 'CPU > 80%',
              value: report.highCpu.toString(),
              icon: Icons.speed_outlined,
            ),
            MetricCard(
              label: 'RAM > 80%',
              value: report.highRam.toString(),
              icon: Icons.memory_outlined,
            ),
            MetricCard(
              label: 'Backup issues',
              value: report.backupIssues.toString(),
              icon: Icons.backup_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _VmCharts(history: history),
        const SizedBox(height: 16),
        _NodeCapacityTable(
          nodes: data.nodes,
          storageResources: data.storageResources,
        ),
        const SizedBox(height: 16),
        _VmRiskTable(guests: report.guests, snapshots: data.backupSnapshots),
        const SizedBox(height: 16),
        _VmSignalCard(data: data),
      ],
    );
  }
}

class _VmCharts extends StatelessWidget {
  const _VmCharts({required this.history});

  final ResourceHistoryReport history;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final charts = <Widget>[
          ResourceLineChart(
            title: 'VM/LXC CPU history',
            points: history.guestCpu,
            icon: Icons.speed_outlined,
          ),
          ResourceLineChart(
            title: 'VM/LXC RAM history',
            points: history.guestRam,
            icon: Icons.memory_outlined,
          ),
        ];
        if (constraints.maxWidth > 900) {
          return Row(
            children: <Widget>[
              Expanded(child: charts[0]),
              const SizedBox(width: 12),
              Expanded(child: charts[1]),
            ],
          );
        }
        return Column(
          children: <Widget>[charts[0], const SizedBox(height: 12), charts[1]],
        );
      },
    );
  }
}

class _NodeCapacityTable extends StatelessWidget {
  const _NodeCapacityTable({
    required this.nodes,
    required this.storageResources,
  });

  final List<Map<String, Object?>> nodes;
  final List<Map<String, Object?>> storageResources;

  @override
  Widget build(BuildContext context) {
    final storageByNode = <String, List<Map<String, Object?>>>{};
    for (final storage in storageResources) {
      final key = _nodeKey(
        storage['sourceId']?.toString() ?? '',
        storage['node']?.toString() ?? '',
      );
      storageByNode.putIfAbsent(key, () => <Map<String, Object?>>[]);
      storageByNode[key]!.add(storage);
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Фактические ресурсы нод',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (nodes.isEmpty)
            const EmptyState(
              icon: Icons.hub_outlined,
              text: 'Ноды пока не найдены.',
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SortableDataTable<Map<String, Object?>>(
                showCheckboxColumn: false,
                initialSortColumnIndex: 1,
                items: nodes,
                columns: <SortableDataColumn<Map<String, Object?>>>[
                  SortableDataColumn<Map<String, Object?>>(
                    label: 'source',
                    compare: (left, right) => compareText(
                      left['source']?.toString() ?? '',
                      right['source']?.toString() ?? '',
                    ),
                  ),
                  SortableDataColumn<Map<String, Object?>>(
                    label: 'node',
                    compare: (left, right) => compareText(
                      left['node']?.toString() ?? '',
                      right['node']?.toString() ?? '',
                    ),
                  ),
                  SortableDataColumn<Map<String, Object?>>(
                    label: 'status',
                    compare: (left, right) => compareText(
                      left['status']?.toString() ?? 'unknown',
                      right['status']?.toString() ?? 'unknown',
                    ),
                  ),
                  SortableDataColumn<Map<String, Object?>>(
                    label: 'cpu model',
                    compare: (left, right) =>
                        compareText(_cpuModel(left), _cpuModel(right)),
                  ),
                  SortableDataColumn<Map<String, Object?>>(
                    label: 'cores/threads',
                    numeric: true,
                    compare: (left, right) =>
                        _cpuThreads(left).compareTo(_cpuThreads(right)),
                  ),
                  SortableDataColumn<Map<String, Object?>>(
                    label: 'ram total',
                    numeric: true,
                    compare: (left, right) => _number(
                      left['maxmem'],
                    ).compareTo(_number(right['maxmem'])),
                  ),
                  SortableDataColumn<Map<String, Object?>>(
                    label: 'ram used',
                    numeric: true,
                    compare: (left, right) =>
                        _number(left['mem']).compareTo(_number(right['mem'])),
                  ),
                  SortableDataColumn<Map<String, Object?>>(
                    label: 'root disk',
                    numeric: true,
                    compare: (left, right) => _number(
                      left['maxdisk'],
                    ).compareTo(_number(right['maxdisk'])),
                  ),
                  SortableDataColumn<Map<String, Object?>>(
                    label: 'storage',
                    numeric: true,
                    compare: (left, right) => _nodeStorage(storageByNode, left)
                        .length
                        .compareTo(_nodeStorage(storageByNode, right).length),
                  ),
                  SortableDataColumn<Map<String, Object?>>(
                    label: 'storage types',
                    compare: (left, right) => compareText(
                      _storageTypes(_nodeStorage(storageByNode, left)),
                      _storageTypes(_nodeStorage(storageByNode, right)),
                    ),
                  ),
                  SortableDataColumn<Map<String, Object?>>(
                    label: 'storage usage',
                    compare: (left, right) => compareText(
                      _storageSummary(_nodeStorage(storageByNode, left)),
                      _storageSummary(_nodeStorage(storageByNode, right)),
                    ),
                  ),
                  SortableDataColumn<Map<String, Object?>>(
                    label: 'uptime',
                    numeric: true,
                    compare: (left, right) => _number(
                      left['uptime'],
                    ).compareTo(_number(right['uptime'])),
                  ),
                ],
                rowBuilder: (BuildContext context, Map<String, Object?> node) {
                  final nodeName = node['node']?.toString() ?? '';
                  final storages = _nodeStorage(storageByNode, node);
                  return DataRow(
                    onSelectChanged: (_) {
                      context.go(
                        '/sources/${node['sourceId'] ?? ''}/nodes/'
                        '${Uri.encodeComponent(nodeName)}',
                      );
                    },
                    cells: <DataCell>[
                      DataCell(Text(node['source']?.toString() ?? '')),
                      DataCell(Text(nodeName)),
                      DataCell(
                        StatusChip(
                          status: node['status']?.toString() ?? 'unknown',
                        ),
                      ),
                      DataCell(Text(_cpuModel(node))),
                      DataCell(Text(_cpuShape(node))),
                      DataCell(Text(formatBytes(node['maxmem']))),
                      DataCell(Text(_usedOfTotal(node['mem'], node['maxmem']))),
                      DataCell(
                        Text(_usedOfTotal(node['disk'], node['maxdisk'])),
                      ),
                      DataCell(Text(storages.length.toString())),
                      DataCell(Text(_storageTypes(storages))),
                      DataCell(Text(_storageSummary(storages))),
                      DataCell(Text(formatSeconds(node['uptime']))),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

String _nodeKey(String sourceId, String node) => '$sourceId/$node';

List<Map<String, Object?>> _nodeStorage(
  Map<String, List<Map<String, Object?>>> storageByNode,
  Map<String, Object?> node,
) {
  return storageByNode[_nodeKey(
        node['sourceId']?.toString() ?? '',
        node['node']?.toString() ?? '',
      )] ??
      const <Map<String, Object?>>[];
}

String _cpuModel(Map<String, Object?> node) {
  final cpuinfo = node['cpuinfo'];
  if (cpuinfo is Map) {
    for (final key in <String>['model', 'cpumodel', 'type']) {
      final value = cpuinfo[key]?.toString() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
  }
  for (final key in <String>['cpu-model', 'cpumodel', 'model']) {
    final value = node[key]?.toString() ?? '';
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '-';
}

String _cpuShape(Map<String, Object?> node) {
  final sockets = _cpuInfoNumber(node, 'sockets');
  final cores = _cpuInfoNumber(node, 'cores');
  final cpus = _cpuThreads(node);
  if (cores > 0 && cpus > 0) {
    final prefix = sockets > 0 ? '$sockets socket · ' : '';
    return '$prefix$cores cores · $cpus threads';
  }
  if (cpus > 0) {
    return '$cpus threads';
  }
  return '-';
}

int _cpuThreads(Map<String, Object?> node) {
  final cpus = _cpuInfoNumber(node, 'cpus');
  if (cpus > 0) {
    return cpus;
  }
  final cores = _cpuInfoNumber(node, 'cores');
  final sockets = _cpuInfoNumber(node, 'sockets');
  if (cores > 0 && sockets > 0) {
    return cores * sockets;
  }
  return cores;
}

int _cpuInfoNumber(Map<String, Object?> node, String key) {
  final cpuinfo = node['cpuinfo'];
  if (cpuinfo is Map) {
    final value = int.tryParse(cpuinfo[key]?.toString() ?? '');
    if (value != null) {
      return value;
    }
  }
  return int.tryParse(node[key]?.toString() ?? '') ?? 0;
}

String _storageTypes(List<Map<String, Object?>> storages) {
  final types =
      storages
          .map(
            (storage) =>
                storage['plugintype']?.toString() ??
                storage['type']?.toString() ??
                '',
          )
          .where((type) => type.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  return types.isEmpty ? '-' : types.join(', ');
}

String _storageSummary(List<Map<String, Object?>> storages) {
  final withSize = storages.where((storage) {
    return _number(storage['disk']) > 0 || _number(storage['maxdisk']) > 0;
  }).toList();
  if (withSize.isEmpty) {
    return '-';
  }
  final total = withSize.fold<double>(
    0,
    (sum, storage) => sum + _number(storage['maxdisk']),
  );
  final used = withSize.fold<double>(
    0,
    (sum, storage) => sum + _number(storage['disk']),
  );
  return '${_usedOfTotal(used, total)} · ${withSize.length} with size';
}

String _usedOfTotal(Object? used, Object? total) {
  final usedValue = _number(used);
  final totalValue = _number(total);
  if (usedValue <= 0 && totalValue <= 0) {
    return '-';
  }
  if (totalValue <= 0) {
    return formatBytes(usedValue);
  }
  final ratio = totalValue == 0 ? 0 : usedValue / totalValue;
  return '${formatBytes(usedValue)} / ${formatBytes(totalValue)} '
      '(${formatPercent(ratio.clamp(0, 1).toDouble())})';
}

double _number(Object? value) {
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

class _VmRiskTable extends StatelessWidget {
  const _VmRiskTable({required this.guests, required this.snapshots});

  final List<Map<String, Object?>> guests;
  final List<Map<String, Object?>> snapshots;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'VM/LXC под наблюдением',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (guests.isEmpty)
            const EmptyState(
              icon: Icons.developer_board_outlined,
              text: 'VM/LXC пока не найдены.',
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SortableDataTable<Map<String, Object?>>(
                showCheckboxColumn: false,
                initialSortColumnIndex: 5,
                initialSortAscending: false,
                items: guests,
                columns: <SortableDataColumn<Map<String, Object?>>>[
                  SortableDataColumn<Map<String, Object?>>(
                    label: 'source',
                    compare: (left, right) => compareText(
                      left['source']?.toString() ?? '',
                      right['source']?.toString() ?? '',
                    ),
                  ),
                  SortableDataColumn<Map<String, Object?>>(
                    label: 'node',
                    compare: (left, right) => compareText(
                      left['node']?.toString() ?? '',
                      right['node']?.toString() ?? '',
                    ),
                  ),
                  SortableDataColumn<Map<String, Object?>>(
                    label: 'vm/lxc',
                    compare: (left, right) =>
                        compareText(_guestLabel(left), _guestLabel(right)),
                  ),
                  SortableDataColumn<Map<String, Object?>>(
                    label: 'name',
                    compare: (left, right) => compareText(
                      left['name']?.toString() ?? '',
                      right['name']?.toString() ?? '',
                    ),
                  ),
                  SortableDataColumn<Map<String, Object?>>(
                    label: 'status',
                    compare: (left, right) => compareText(
                      left['status']?.toString() ?? 'unknown',
                      right['status']?.toString() ?? 'unknown',
                    ),
                  ),
                  SortableDataColumn<Map<String, Object?>>(
                    label: 'cpu',
                    numeric: true,
                    compare: (left, right) => ratioValue(
                      left['cpu'],
                    ).compareTo(ratioValue(right['cpu'])),
                  ),
                  SortableDataColumn<Map<String, Object?>>(
                    label: 'ram',
                    numeric: true,
                    compare: (left, right) => ratioPairValue(
                      left['mem'],
                      left['maxmem'],
                    ).compareTo(ratioPairValue(right['mem'], right['maxmem'])),
                  ),
                  SortableDataColumn<Map<String, Object?>>(
                    label: 'backup',
                    compare: (left, right) => compareText(
                      backupStatusLabel(_backupStatus(left, snapshots)),
                      backupStatusLabel(_backupStatus(right, snapshots)),
                    ),
                  ),
                ],
                rowBuilder: (context, guest) {
                  final guestType = guest['type']?.toString() ?? '';
                  final vmid = guest['vmid']?.toString() ?? '';
                  final node = guest['node']?.toString() ?? '';
                  final name = guest['name']?.toString() ?? '';
                  final cpu = ratioValue(guest['cpu']);
                  final ram = ratioPairValue(guest['mem'], guest['maxmem']);
                  final backupStatus = _backupStatus(guest, snapshots);
                  return DataRow(
                    onSelectChanged: (_) {
                      final query = name.isEmpty
                          ? ''
                          : '?name=${Uri.encodeQueryComponent(name)}';
                      context.go(
                        '/sources/${guest['sourceId'] ?? ''}/guests/'
                        '$guestType/${Uri.encodeComponent(node)}/$vmid$query',
                      );
                    },
                    cells: <DataCell>[
                      DataCell(Text(guest['source']?.toString() ?? '')),
                      DataCell(Text(node)),
                      DataCell(Text('$guestType/$vmid')),
                      DataCell(Text(name)),
                      DataCell(
                        StatusChip(
                          status: guest['status']?.toString() ?? 'unknown',
                        ),
                      ),
                      DataCell(Text(formatPercent(cpu))),
                      DataCell(Text(formatPercent(ram))),
                      DataCell(
                        StatusChip(status: backupStatusLabel(backupStatus)),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

String _guestLabel(Map<String, Object?> guest) {
  return '${guest['type'] ?? ''}/${guest['vmid'] ?? ''}';
}

BackupAgeStatus _backupStatus(
  Map<String, Object?> guest,
  List<Map<String, Object?>> snapshots,
) {
  return analyzeGuestBackups(
    guestType: guest['type']?.toString() ?? '',
    vmid: guest['vmid']?.toString() ?? '',
    guestName: guest['name']?.toString() ?? '',
    snapshots: snapshots,
  ).status;
}

class _VmSignalCard extends StatelessWidget {
  const _VmSignalCard({required this.data});

  final HealthRuntimeData data;

  @override
  Widget build(BuildContext context) {
    final failedTasks = data.tasks
        .where((task) => task['status']?.toString().toUpperCase() == 'ERROR')
        .take(8)
        .toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Сигналы', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (data.collectionErrors.isEmpty && failedTasks.isEmpty)
            const EmptyState(
              icon: Icons.verified_outlined,
              text: 'Ошибок интеграции и failed tasks не найдено.',
            )
          else ...<Widget>[
            ...data.collectionErrors.map(
              (error) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.error_outline),
                title: Text(error['source']?.toString() ?? ''),
                subtitle: Text(error['error']?.toString() ?? ''),
              ),
            ),
            ...failedTasks.map(
              (task) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.task_alt_outlined),
                title: Text(task['type']?.toString() ?? 'task'),
                subtitle: Text(
                  '${task['source'] ?? ''} · ${task['node'] ?? ''} · '
                  '${task['user'] ?? ''}',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
