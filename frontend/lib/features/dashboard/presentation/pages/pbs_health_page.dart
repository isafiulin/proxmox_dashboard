import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/core/design/app_colors.dart';
import 'package:frontend/features/sources/data/source_data_repository.dart';
import 'package:frontend/features/sources/domain/pbs_health.dart';
import 'package:frontend/features/sources/domain/source.dart';
import 'package:frontend/features/sources/presentation/cubit/sources_cubit.dart';
import 'package:frontend/shared/formatters/value_formatters.dart';
import 'package:frontend/shared/widgets/app_card.dart';
import 'package:frontend/shared/widgets/async_state_view.dart';
import 'package:frontend/shared/widgets/empty_state.dart';
import 'package:frontend/shared/widgets/generic_data_section.dart';
import 'package:frontend/shared/widgets/metric_card.dart';
import 'package:frontend/shared/widgets/page_header.dart';
import 'package:frontend/shared/widgets/sortable_data_table.dart';
import 'package:frontend/shared/widgets/status_chip.dart';
import 'package:go_router/go_router.dart';

class PbsHealthPage extends StatelessWidget {
  const PbsHealthPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SourcesCubit, SourcesState>(
      builder: (context, state) {
        if (state.status == SourcesStatus.loading && state.items.isEmpty) {
          return const LoadingStateView();
        }
        return FutureBuilder<_PbsHealthReport>(
          future: _load(context, state.items),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LoadingStateView();
            }
            if (snapshot.hasError) {
              return ErrorStateView(message: snapshot.error.toString());
            }
            return _PbsHealthContent(
              report: snapshot.data ?? const _PbsHealthReport.empty(),
            );
          },
        );
      },
    );
  }

  Future<_PbsHealthReport> _load(
    BuildContext context,
    List<Source> sources,
  ) async {
    final repository = SourceDataRepository(context.read<ApiClient>());
    final stores = <Map<String, Object?>>[];
    final failedTasks = <Map<String, Object?>>[];
    final jobs = <Map<String, Object?>>[];
    final integrationErrors = <Map<String, Object?>>[];
    var pbsCount = 0;
    final pbsSources = sources
        .where((item) => item.type == 'proxmox_backup')
        .toList();
    final pbsData = await Future.wait(
      pbsSources.map((source) => repository.loadProxmoxBackup(source.id)),
    );
    for (var index = 0; index < pbsSources.length; index += 1) {
      final source = pbsSources[index];
      final data = pbsData[index];
      pbsCount += 1;
      integrationErrors.addAll(
        data.healthErrors.map(
          (row) => <String, Object?>{'source': source.name, ...row},
        ),
      );
      final usageRows = data.datastoreUsage.isEmpty
          ? data.datastores
          : data.datastoreUsage;
      stores.addAll(
        usageRows.map(
          (row) => <String, Object?>{
            'sourceId': source.id,
            'source': source.name,
            ...row,
          },
        ),
      );
      failedTasks.addAll(
        data.tasks
            .where(isFailedPbsTask)
            .map(
              (row) => <String, Object?>{
                'sourceId': source.id,
                'source': source.name,
                ...row,
              },
            ),
      );
      for (final entry in <(String, List<Map<String, Object?>>)>[
        ('verify', data.verifyJobs),
        ('prune', data.pruneJobs),
        ('gc', data.gcJobs),
        ('sync', data.syncJobs),
      ]) {
        jobs.addAll(
          entry.$2.map(
            (row) => <String, Object?>{
              'sourceId': source.id,
              'source': source.name,
              'jobType': entry.$1,
              ...row,
            },
          ),
        );
      }
    }
    return _PbsHealthReport(
      pbsCount: pbsCount,
      stores: stores,
      failedTasks: failedTasks,
      jobs: jobs,
      integrationErrors: integrationErrors,
    );
  }
}

class _PbsHealthContent extends StatelessWidget {
  const _PbsHealthContent({required this.report});

  final _PbsHealthReport report;

  @override
  Widget build(BuildContext context) {
    final highUsage = report.stores.where((row) => _usage(row) >= 0.9).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const PageHeader(
          title: 'PBS health',
          subtitle:
              'Заполнение datastore, ошибки задач и расписания обслуживания',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            MetricCard(
              label: 'PBS',
              value: report.pbsCount.toString(),
              icon: Icons.dns_outlined,
            ),
            MetricCard(
              label: 'Datastores',
              value: report.stores.length.toString(),
              icon: Icons.storage_outlined,
            ),
            MetricCard(
              label: 'Usage >= 90%',
              value: highUsage.toString(),
              icon: Icons.data_usage_outlined,
              color: highUsage == 0 ? AppColors.success : AppColors.danger,
            ),
            MetricCard(
              label: 'Failed tasks',
              value: report.failedTasks.length.toString(),
              icon: Icons.error_outline,
              color: report.failedTasks.isEmpty
                  ? AppColors.success
                  : AppColors.danger,
            ),
            MetricCard(
              label: 'Maintenance jobs',
              value: report.jobs.length.toString(),
              icon: Icons.schedule_outlined,
              color: AppColors.primaryDark,
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Datastore usage',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (report.stores.isEmpty)
                const EmptyState(
                  icon: Icons.storage_outlined,
                  text: 'PBS datastore не найдены или API недоступен.',
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SortableDataTable<Map<String, Object?>>(
                    showCheckboxColumn: false,
                    columns: <SortableDataColumn<Map<String, Object?>>>[
                      SortableDataColumn(
                        label: 'source',
                        compare: (a, b) => compareText(
                          a['source']?.toString() ?? '',
                          b['source']?.toString() ?? '',
                        ),
                      ),
                      SortableDataColumn(
                        label: 'datastore',
                        compare: (a, b) =>
                            compareText(_storeName(a), _storeName(b)),
                      ),
                      SortableDataColumn(
                        label: 'status',
                        compare: (a, b) => _usage(a).compareTo(_usage(b)),
                      ),
                      SortableDataColumn(
                        label: 'used',
                        compare: (a, b) =>
                            _number(a['used']).compareTo(_number(b['used'])),
                      ),
                      SortableDataColumn(
                        label: 'total',
                        compare: (a, b) =>
                            _number(a['total']).compareTo(_number(b['total'])),
                      ),
                    ],
                    items: report.stores,
                    rowBuilder: (context, row) => DataRow(
                      onSelectChanged: (_) =>
                          context.go('/sources/${row['sourceId']}'),
                      cells: <DataCell>[
                        DataCell(Text(row['source']?.toString() ?? '')),
                        DataCell(Text(_storeName(row))),
                        DataCell(
                          StatusChip(
                            status: _usage(row) >= 0.9
                                ? 'critical'
                                : _usage(row) >= 0.75
                                ? 'warning'
                                : 'ok',
                          ),
                        ),
                        DataCell(Text(formatBytes(row['used']))),
                        DataCell(Text(formatBytes(row['total']))),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'PBS API errors',
          rows: report.integrationErrors,
          preferredColumns: const <String>[
            'source',
            'operation',
            'statusCode',
            'path',
            'message',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Failed PBS tasks',
          rows: report.failedTasks,
          preferredColumns: const <String>[
            'source',
            'worker_type',
            'worker_id',
            'status',
            'starttime',
            'endtime',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Verify / prune / GC / sync jobs',
          rows: report.jobs,
          preferredColumns: const <String>[
            'source',
            'jobType',
            'id',
            'store',
            'ns',
            'schedule',
            'comment',
          ],
        ),
      ],
    );
  }
}

class _PbsHealthReport {
  const _PbsHealthReport({
    required this.pbsCount,
    required this.stores,
    required this.failedTasks,
    required this.jobs,
    required this.integrationErrors,
  });

  const _PbsHealthReport.empty()
    : pbsCount = 0,
      stores = const <Map<String, Object?>>[],
      failedTasks = const <Map<String, Object?>>[],
      jobs = const <Map<String, Object?>>[],
      integrationErrors = const <Map<String, Object?>>[];

  final int pbsCount;
  final List<Map<String, Object?>> stores;
  final List<Map<String, Object?>> failedTasks;
  final List<Map<String, Object?>> jobs;
  final List<Map<String, Object?>> integrationErrors;
}

double _number(Object? value) => double.tryParse(value?.toString() ?? '') ?? 0;

double _usage(Map<String, Object?> row) {
  final total = _number(row['total']);
  return total <= 0 ? 0 : (_number(row['used']) / total).clamp(0, 1);
}

String _storeName(Map<String, Object?> row) =>
    row['store']?.toString() ?? row['name']?.toString() ?? '';
