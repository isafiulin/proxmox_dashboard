import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/core/design/app_colors.dart';
import 'package:frontend/features/sources/data/source_data_repository.dart';
import 'package:frontend/features/sources/domain/backup_analysis.dart';
import 'package:frontend/features/sources/domain/pbs_health.dart';
import 'package:frontend/features/sources/domain/source.dart';
import 'package:frontend/features/sources/presentation/cubit/sources_cubit.dart';
import 'package:frontend/shared/widgets/app_card.dart';
import 'package:frontend/shared/widgets/async_state_view.dart';
import 'package:frontend/shared/widgets/empty_state.dart';
import 'package:frontend/shared/widgets/metric_card.dart';
import 'package:frontend/shared/widgets/page_header.dart';
import 'package:frontend/shared/widgets/sortable_data_table.dart';
import 'package:frontend/shared/widgets/status_chip.dart';
import 'package:go_router/go_router.dart';

class BackupRedundancyPage extends StatelessWidget {
  const BackupRedundancyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SourcesCubit, SourcesState>(
      builder: (BuildContext context, SourcesState state) {
        if (state.status == SourcesStatus.loading && state.items.isEmpty) {
          return const LoadingStateView();
        }
        return FutureBuilder<_BackupRedundancyReport>(
          future: _load(context, state.items),
          builder:
              (
                BuildContext context,
                AsyncSnapshot<_BackupRedundancyReport> snapshot,
              ) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LoadingStateView();
                }
                if (snapshot.hasError) {
                  return ErrorStateView(message: snapshot.error.toString());
                }
                return _BackupRedundancyContent(
                  report:
                      snapshot.data ?? const _BackupRedundancyReport.empty(),
                );
              },
        );
      },
    );
  }

  Future<_BackupRedundancyReport> _load(
    BuildContext context,
    List<Source> sources,
  ) async {
    final repository = SourceDataRepository(context.read<ApiClient>());
    final pveSources = sources
        .where((source) => source.type == 'proxmox_ve')
        .toList();
    final pbsSources = sources
        .where((source) => source.type == 'proxmox_backup')
        .toList();
    final snapshots = <Map<String, Object?>>[];

    final pbsData = await Future.wait(
      pbsSources.map((source) => repository.loadProxmoxBackup(source.id)),
    );
    for (var index = 0; index < pbsSources.length; index += 1) {
      final source = pbsSources[index];
      final data = pbsData[index];
      snapshots.addAll(
        data.snapshots.map(
          (snapshot) => <String, Object?>{
            'backupSourceId': source.id,
            'backupSource': source.name,
            ...snapshot,
          },
        ),
      );
    }

    final issues = <_BackupRedundancyIssue>[];
    var totalGuests = 0;
    final pveData = await Future.wait(
      pveSources.map((source) => repository.loadProxmoxVe(source.id)),
    );
    for (var index = 0; index < pveSources.length; index += 1) {
      final source = pveSources[index];
      final data = pveData[index];
      final expectedNamespaces = backupNamespacesFromStorageConfig(
        data.storageConfig,
        manualNamespace: source.backupNamespace,
      );
      final effectiveNamespaces = expectedNamespaces.isEmpty
          ? const <String>{''}
          : expectedNamespaces;
      for (final guest in data.vmResources.where(_isGuest)) {
        totalGuests += 1;
        final guestType = guest['type']?.toString() ?? '';
        final vmid = guest['vmid']?.toString() ?? '';
        final summary = analyzeGuestBackups(
          guestType: guestType,
          vmid: vmid,
          guestName: guest['name']?.toString() ?? '',
          backupNamespaces: effectiveNamespaces,
          snapshots: snapshots,
        );
        final guestSnapshots = summary.matches;
        final backupSources = guestSnapshots
            .map((snapshot) => snapshot['backupSource']?.toString() ?? '')
            .where((sourceName) => sourceName.isNotEmpty)
            .toSet();
        final locationFreshness = analyzePbsBackupLocationFreshness(
          guestSnapshots,
        );
        final backupLocationLabels = locationFreshness.latestByLocation.values
            .map((snapshot) {
              final sourceName = snapshot['backupSource']?.toString() ?? '';
              final datastore = snapshot['datastore']?.toString() ?? '';
              final namespace = snapshotNamespace(snapshot);
              if (sourceName.isEmpty && datastore.isEmpty) {
                return '';
              }
              final base = datastore.isEmpty
                  ? sourceName
                  : '$sourceName / $datastore';
              final label = namespace.isEmpty ? base : '$base / $namespace';
              return '$label: ${_formatDateTime(snapshotTime(snapshot))}';
            })
            .where((location) => location.isNotEmpty)
            .toSet();
        if (locationFreshness.currentLocationCount >= 2) {
          continue;
        }
        issues.add(
          _BackupRedundancyIssue(
            sourceId: source.id,
            sourceName: source.name,
            node: guest['node']?.toString() ?? '',
            guestType: guestType,
            vmid: vmid,
            name: guest['name']?.toString() ?? '',
            guestStatus: guest['status']?.toString() ?? 'unknown',
            backupSources: backupSources,
            currentLocationCount: locationFreshness.currentLocationCount,
            backupLocations: backupLocationLabels,
            snapshotCount: guestSnapshots.length,
            latestBackupAt: summary.latestBackupAt,
          ),
        );
      }
    }

    issues.sort((a, b) {
      final sourceCompare = a.currentLocationCount.compareTo(
        b.currentLocationCount,
      );
      if (sourceCompare != 0) {
        return sourceCompare;
      }
      return (a.latestBackupAt ?? DateTime(0)).compareTo(
        b.latestBackupAt ?? DateTime(0),
      );
    });

    return _BackupRedundancyReport(
      issues: issues,
      totalGuests: totalGuests,
      pbsSources: pbsSources.length,
    );
  }
}

class _BackupRedundancyContent extends StatelessWidget {
  const _BackupRedundancyContent({required this.report});

  final _BackupRedundancyReport report;

  @override
  Widget build(BuildContext context) {
    final missing = report.issues
        .where((issue) => issue.currentLocationCount == 0)
        .length;
    final singleServer = report.issues
        .where((issue) => issue.currentLocationCount == 1)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const PageHeader(
          title: 'Backup redundancy',
          subtitle:
              'VM/LXC должны иметь backups минимум в двух разных местах хранения',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            MetricCard(
              label: 'Redundancy issues',
              value: report.issues.length.toString(),
              icon: Icons.security_outlined,
              color: report.issues.isEmpty
                  ? AppColors.success
                  : AppColors.danger,
            ),
            MetricCard(
              label: 'Без backup',
              value: missing.toString(),
              icon: Icons.backup_outlined,
              color: missing == 0 ? AppColors.success : AppColors.danger,
            ),
            MetricCard(
              label: 'Только 1 актуальное',
              value: singleServer.toString(),
              icon: Icons.warning_amber_outlined,
              color: singleServer == 0 ? AppColors.success : AppColors.warning,
            ),
            MetricCard(
              label: 'PBS источников',
              value: report.pbsSources.toString(),
              icon: Icons.storage_outlined,
            ),
            MetricCard(
              label: 'Всего VM/LXC',
              value: report.totalGuests.toString(),
              icon: Icons.memory_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _RedundancyInfoCard(),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'VM/LXC с недостаточной копией backup',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (report.issues.isEmpty)
                const EmptyState(
                  icon: Icons.verified_outlined,
                  text:
                      'Все найденные VM/LXC имеют backups минимум в двух местах.',
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SortableDataTable<_BackupRedundancyIssue>(
                    showCheckboxColumn: false,
                    items: report.issues,
                    columns: <SortableDataColumn<_BackupRedundancyIssue>>[
                      SortableDataColumn<_BackupRedundancyIssue>(
                        label: 'status',
                        compare: (left, right) =>
                            compareText(left.status, right.status),
                      ),
                      SortableDataColumn<_BackupRedundancyIssue>(
                        label: 'source',
                        compare: (left, right) =>
                            compareText(left.sourceName, right.sourceName),
                      ),
                      SortableDataColumn<_BackupRedundancyIssue>(
                        label: 'node',
                        compare: (left, right) =>
                            compareText(left.node, right.node),
                      ),
                      SortableDataColumn<_BackupRedundancyIssue>(
                        label: 'vm/lxc',
                        compare: (left, right) => compareText(
                          '${left.guestType}/${left.vmid}',
                          '${right.guestType}/${right.vmid}',
                        ),
                      ),
                      SortableDataColumn<_BackupRedundancyIssue>(
                        label: 'name',
                        compare: (left, right) =>
                            compareText(left.name, right.name),
                      ),
                      SortableDataColumn<_BackupRedundancyIssue>(
                        label: 'vm status',
                        compare: (left, right) =>
                            compareText(left.guestStatus, right.guestStatus),
                      ),
                      SortableDataColumn<_BackupRedundancyIssue>(
                        label: 'location count',
                        numeric: true,
                        compare: (left, right) => left.currentLocationCount
                            .compareTo(right.currentLocationCount),
                      ),
                      SortableDataColumn<_BackupRedundancyIssue>(
                        label: 'locations',
                        compare: (left, right) => compareText(
                          left.backupLocations.join(', '),
                          right.backupLocations.join(', '),
                        ),
                      ),
                      SortableDataColumn<_BackupRedundancyIssue>(
                        label: 'snapshots',
                        numeric: true,
                        compare: (left, right) =>
                            left.snapshotCount.compareTo(right.snapshotCount),
                      ),
                      SortableDataColumn<_BackupRedundancyIssue>(
                        label: 'last backup',
                        compare: (left, right) => compareNullableDateTime(
                          left.latestBackupAt,
                          right.latestBackupAt,
                        ),
                      ),
                    ],
                    rowBuilder: (context, issue) {
                      return DataRow(
                        onSelectChanged: (_) {
                          final query = issue.name.isEmpty
                              ? ''
                              : '?name=${Uri.encodeQueryComponent(issue.name)}';
                          context.go(
                            '/sources/${issue.sourceId}/guests/'
                            '${issue.guestType}/'
                            '${Uri.encodeComponent(issue.node)}/'
                            '${issue.vmid}$query',
                          );
                        },
                        cells: <DataCell>[
                          DataCell(StatusChip(status: issue.status)),
                          DataCell(Text(issue.sourceName)),
                          DataCell(Text(issue.node)),
                          DataCell(Text('${issue.guestType}/${issue.vmid}')),
                          DataCell(Text(issue.name)),
                          DataCell(StatusChip(status: issue.guestStatus)),
                          DataCell(Text(issue.currentLocationCount.toString())),
                          DataCell(Text(issue.backupLocations.join(', '))),
                          DataCell(Text(issue.snapshotCount.toString())),
                          DataCell(Text(_formatDateTime(issue.latestBackupAt))),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RedundancyInfoCard extends StatelessWidget {
  const _RedundancyInfoCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.info_outline, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Безопасное хранение требует минимум 2 разных места хранения: '
              'разные PBS или разные datastore внутри одного PBS. Если backup '
              'есть только в одном месте или второе место содержит backup за '
              'другую дату, VM/LXC не имеет актуальной независимой копии.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.mutedInk),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupRedundancyReport {
  const _BackupRedundancyReport({
    required this.issues,
    required this.totalGuests,
    required this.pbsSources,
  });

  const _BackupRedundancyReport.empty()
    : issues = const <_BackupRedundancyIssue>[],
      totalGuests = 0,
      pbsSources = 0;

  final List<_BackupRedundancyIssue> issues;
  final int totalGuests;
  final int pbsSources;
}

class _BackupRedundancyIssue {
  const _BackupRedundancyIssue({
    required this.sourceId,
    required this.sourceName,
    required this.node,
    required this.guestType,
    required this.vmid,
    required this.name,
    required this.guestStatus,
    required this.backupSources,
    required this.currentLocationCount,
    required this.backupLocations,
    required this.snapshotCount,
    required this.latestBackupAt,
  });

  final String sourceId;
  final String sourceName;
  final String node;
  final String guestType;
  final String vmid;
  final String name;
  final String guestStatus;
  final Set<String> backupSources;
  final int currentLocationCount;
  final Set<String> backupLocations;
  final int snapshotCount;
  final DateTime? latestBackupAt;

  String get status => currentLocationCount >= 2 ? 'ok' : 'critical';
}

bool _isGuest(Map<String, Object?> item) {
  return item['type'] == 'qemu' || item['type'] == 'lxc';
}

String _formatDateTime(DateTime? value) {
  if (value == null) {
    return 'не найден';
  }
  final local = value.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
