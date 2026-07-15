import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/features/sources/data/source_data_repository.dart';
import 'package:frontend/features/sources/domain/backup_policy.dart';
import 'package:frontend/features/sources/domain/source.dart';
import 'package:frontend/features/sources/presentation/cubit/sources_cubit.dart';
import 'package:frontend/shared/widgets/app_card.dart';
import 'package:frontend/shared/widgets/async_state_view.dart';
import 'package:frontend/shared/widgets/empty_state.dart';
import 'package:frontend/shared/widgets/generic_data_section.dart';
import 'package:frontend/shared/widgets/metric_card.dart';
import 'package:frontend/shared/widgets/page_header.dart';
import 'package:frontend/shared/widgets/sortable_data_table.dart';
import 'package:frontend/shared/widgets/status_chip.dart';
import 'package:go_router/go_router.dart';

class BackupPolicyPage extends StatelessWidget {
  const BackupPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SourcesCubit, SourcesState>(
      builder: (context, state) => FutureBuilder<_PolicyReport>(
        future: _load(context, state.items),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingStateView();
          }
          if (snapshot.hasError) {
            return ErrorStateView(message: snapshot.error.toString());
          }
          return _PolicyContent(
            report: snapshot.data ?? const _PolicyReport.empty(),
          );
        },
      ),
    );
  }

  Future<_PolicyReport> _load(
    BuildContext context,
    List<Source> sources,
  ) async {
    final repository = SourceDataRepository(context.read<ApiClient>());
    final issues = <BackupPolicyIssue>[];
    final jobs = <Map<String, Object?>>[];
    final integrationErrors = <Map<String, Object?>>[];
    var scopes = 0;
    for (final source in sources.where(
      (item) => item.type == 'proxmox_backup',
    )) {
      final data = await repository.loadProxmoxBackup(source.id);
      final policyErrors = data.healthErrors.where((row) {
        return const <String>{
          'verify_jobs',
          'prune_jobs',
          'datastore_config',
        }.contains(row['operation']?.toString());
      }).toList();
      integrationErrors.addAll(
        policyErrors.map(
          (row) => <String, Object?>{'source': source.name, ...row},
        ),
      );
      scopes += data.namespaces.length;
      if (policyErrors.isEmpty) {
        issues.addAll(
          analyzeBackupPolicy(
            sourceId: source.id,
            sourceName: source.name,
            namespaces: data.namespaces,
            datastoreConfig: data.datastoreConfig,
            pruneJobs: data.pruneJobs,
            verifyJobs: data.verifyJobs,
            gcJobs: data.gcJobs,
          ),
        );
      }
      for (final entry in <(String, List<Map<String, Object?>>)>[
        ('verify', data.verifyJobs),
        ('prune', data.pruneJobs),
        ('gc', data.gcJobs),
        ('sync', data.syncJobs),
      ]) {
        jobs.addAll(
          entry.$2.map(
            (job) => <String, Object?>{
              'sourceId': source.id,
              'source': source.name,
              'job-type': entry.$1,
              ...job,
            },
          ),
        );
      }
    }
    return _PolicyReport(
      issues: issues,
      jobs: jobs,
      scopes: scopes,
      integrationErrors: integrationErrors,
    );
  }
}

class _PolicyContent extends StatelessWidget {
  const _PolicyContent({required this.report});

  final _PolicyReport report;

  @override
  Widget build(BuildContext context) {
    final critical = report.issues
        .where((issue) => issue.status == 'critical')
        .length;
    final warning = report.issues.length - critical;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const PageHeader(
          title: 'Backup policy / retention',
          subtitle:
              'Покрытие namespace политиками prune, verify и GC по всем PBS',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            MetricCard(
              label: 'Policy scopes',
              value: '${report.scopes}',
              icon: Icons.account_tree_outlined,
            ),
            MetricCard(
              label: 'Critical',
              value: '$critical',
              icon: Icons.error_outline,
            ),
            MetricCard(
              label: 'Warnings',
              value: '$warning',
              icon: Icons.warning_amber_outlined,
            ),
            MetricCard(
              label: 'Jobs',
              value: '${report.jobs.length}',
              icon: Icons.schedule_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Источники без доступа к policy config',
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
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Policy issues',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (report.issues.isEmpty)
                const EmptyState(
                  icon: Icons.verified_outlined,
                  text: 'Проблемы retention и coverage не найдены.',
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SortableDataTable<BackupPolicyIssue>(
                    showCheckboxColumn: false,
                    columns: <SortableDataColumn<BackupPolicyIssue>>[
                      SortableDataColumn(
                        label: 'status',
                        compare: (a, b) => compareText(a.status, b.status),
                      ),
                      SortableDataColumn(
                        label: 'PBS',
                        compare: (a, b) =>
                            compareText(a.sourceName, b.sourceName),
                      ),
                      SortableDataColumn(
                        label: 'datastore',
                        compare: (a, b) =>
                            compareText(a.datastore, b.datastore),
                      ),
                      SortableDataColumn(
                        label: 'namespace',
                        compare: (a, b) =>
                            compareText(a.namespace, b.namespace),
                      ),
                      SortableDataColumn(
                        label: 'issue',
                        compare: (a, b) =>
                            compareText(a.type.name, b.type.name),
                      ),
                      SortableDataColumn(
                        label: 'details',
                        compare: (a, b) => compareText(a.message, b.message),
                      ),
                    ],
                    items: report.issues,
                    rowBuilder: (context, issue) => DataRow(
                      onSelectChanged: (_) =>
                          context.go('/sources/${issue.sourceId}'),
                      cells: <DataCell>[
                        DataCell(StatusChip(status: issue.status)),
                        DataCell(Text(issue.sourceName)),
                        DataCell(Text(issue.datastore)),
                        DataCell(
                          Text(
                            issue.namespace.isEmpty ? 'root' : issue.namespace,
                          ),
                        ),
                        DataCell(Text(issue.type.name)),
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Text(issue.message),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Все PBS jobs',
          rows: report.jobs,
          preferredColumns: const <String>[
            'source',
            'job-type',
            'id',
            'store',
            'ns',
            'max-depth',
            'schedule',
            'keep-last',
            'keep-daily',
            'keep-weekly',
            'keep-monthly',
            'outdated-after',
            'remote',
            'remote-store',
          ],
        ),
      ],
    );
  }
}

class _PolicyReport {
  const _PolicyReport({
    required this.issues,
    required this.jobs,
    required this.scopes,
    required this.integrationErrors,
  });

  const _PolicyReport.empty()
    : issues = const <BackupPolicyIssue>[],
      jobs = const <Map<String, Object?>>[],
      scopes = 0,
      integrationErrors = const <Map<String, Object?>>[];

  final List<BackupPolicyIssue> issues;
  final List<Map<String, Object?>> jobs;
  final int scopes;
  final List<Map<String, Object?>> integrationErrors;
}
