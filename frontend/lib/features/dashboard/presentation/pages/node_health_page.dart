import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/features/dashboard/data/health_data_loader.dart';
import 'package:frontend/features/dashboard/domain/health_models.dart';
import 'package:frontend/features/snapshots/domain/resource_history.dart';
import 'package:frontend/features/snapshots/presentation/cubit/snapshots_cubit.dart';
import 'package:frontend/features/sources/domain/source.dart';
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

class NodeHealthPage extends StatelessWidget {
  const NodeHealthPage({super.key});

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
                return _NodeHealthContent(
                  data:
                      snapshot.data ??
                      const HealthRuntimeData(
                        nodes: <Map<String, Object?>>[],
                        guests: <Map<String, Object?>>[],
                        tasks: <Map<String, Object?>>[],
                        backupSnapshots: <Map<String, Object?>>[],
                        collectionErrors: <Map<String, Object?>>[],
                      ),
                  sources: state.items,
                );
              },
        );
      },
    );
  }
}

class _NodeHealthContent extends StatelessWidget {
  const _NodeHealthContent({required this.data, required this.sources});

  final HealthRuntimeData data;
  final List<Source> sources;

  @override
  Widget build(BuildContext context) {
    final report = buildNodeHealthReport(data.nodes);
    final history = buildResourceHistory(
      context.watch<SnapshotsCubit>().state.items,
    );
    final failedTasks = data.tasks
        .where((task) => task['status']?.toString().toUpperCase() == 'ERROR')
        .take(8)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const PageHeader(
          title: 'Node health',
          subtitle:
              'Состояние нод, нагрузка, ошибки интеграций и последние задачи',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            MetricCard(
              label: 'Ноды',
              value: report.total.toString(),
              icon: Icons.hub_outlined,
            ),
            MetricCard(
              label: 'Online',
              value: report.online.toString(),
              icon: Icons.check_circle_outline,
            ),
            MetricCard(
              label: 'Offline/unknown',
              value: report.offline.toString(),
              icon: Icons.warning_amber_outlined,
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
          ],
        ),
        const SizedBox(height: 16),
        _NodeCharts(history: history),
        const SizedBox(height: 16),
        _NodeRiskTable(nodes: report.nodes),
        const SizedBox(height: 16),
        _HealthErrorsCard(
          errors: data.collectionErrors,
          failedTasks: failedTasks,
        ),
      ],
    );
  }
}

class _NodeCharts extends StatelessWidget {
  const _NodeCharts({required this.history});

  final ResourceHistoryReport history;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final charts = <Widget>[
          ResourceLineChart(
            title: 'Ноды CPU history',
            points: history.nodeCpu,
            icon: Icons.speed_outlined,
          ),
          ResourceLineChart(
            title: 'Ноды RAM history',
            points: history.nodeRam,
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

class _NodeRiskTable extends StatelessWidget {
  const _NodeRiskTable({required this.nodes});

  final List<Map<String, Object?>> nodes;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Ноды под наблюдением',
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
                initialSortColumnIndex: 3,
                initialSortAscending: false,
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
                    compare: (left, right) =>
                        compareText(_nodeName(left), _nodeName(right)),
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
                    label: 'disk',
                    numeric: true,
                    compare: (left, right) =>
                        ratioPairValue(left['disk'], left['maxdisk']).compareTo(
                          ratioPairValue(right['disk'], right['maxdisk']),
                        ),
                  ),
                  SortableDataColumn<Map<String, Object?>>(
                    label: 'uptime',
                    numeric: true,
                    compare: (left, right) => _numValue(
                      left['uptime'],
                    ).compareTo(_numValue(right['uptime'])),
                  ),
                ],
                rowBuilder: (context, node) {
                  final cpu = ratioValue(node['cpu']);
                  final ram = ratioPairValue(node['mem'], node['maxmem']);
                  final disk = ratioPairValue(node['disk'], node['maxdisk']);
                  final nodeName = _nodeName(node);
                  return DataRow(
                    onSelectChanged:
                        nodeName.isEmpty || node['sourceId'] == null
                        ? null
                        : (_) {
                            context.go(
                              '/sources/${node['sourceId']}/nodes/'
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
                      DataCell(
                        StatusChip(
                          status:
                              '${formatPercent(cpu)} ${healthStatusForLoad(cpu)}',
                        ),
                      ),
                      DataCell(Text(formatPercent(ram))),
                      DataCell(Text(formatPercent(disk))),
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

String _nodeName(Map<String, Object?> node) {
  return node['node']?.toString() ?? node['name']?.toString() ?? '';
}

num _numValue(Object? value) {
  return num.tryParse(value?.toString() ?? '') ?? 0;
}

class _HealthErrorsCard extends StatelessWidget {
  const _HealthErrorsCard({required this.errors, required this.failedTasks});

  final List<Map<String, Object?>> errors;
  final List<Map<String, Object?>> failedTasks;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Ошибки и failed tasks',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (errors.isEmpty && failedTasks.isEmpty)
            const EmptyState(
              icon: Icons.verified_outlined,
              text: 'Ошибок интеграции и failed tasks не найдено.',
            )
          else ...<Widget>[
            ...errors.map(
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
                  '${task['source'] ?? ''} · ${task['node'] ?? ''} · ${task['user'] ?? ''}',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
