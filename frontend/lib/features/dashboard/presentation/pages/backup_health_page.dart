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

class BackupHealthPage extends StatelessWidget {
  const BackupHealthPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SourcesCubit, SourcesState>(
      builder: (BuildContext context, SourcesState state) {
        if (state.status == SourcesStatus.loading && state.items.isEmpty) {
          return const LoadingStateView();
        }
        return FutureBuilder<_BackupHealthReport>(
          future: _load(context, state.items),
          builder:
              (
                BuildContext context,
                AsyncSnapshot<_BackupHealthReport> snapshot,
              ) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LoadingStateView();
                }
                if (snapshot.hasError) {
                  return ErrorStateView(message: snapshot.error.toString());
                }
                return _BackupHealthContent(
                  report: snapshot.data ?? const _BackupHealthReport.empty(),
                );
              },
        );
      },
    );
  }

  Future<_BackupHealthReport> _load(
    BuildContext context,
    List<Source> sources,
  ) async {
    final repository = SourceDataRepository(context.read<ApiClient>());
    final veSources = sources
        .where((source) => source.type == 'proxmox_ve')
        .toList();
    final pbsSources = sources
        .where((source) => source.type == 'proxmox_backup')
        .toList();
    final snapshots = <Map<String, Object?>>[];

    for (final source in pbsSources) {
      final data = await repository.loadProxmoxBackup(source.id);
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

    final guests = <_GuestBackupIssue>[];
    final allGuests = <Map<String, Object?>>[];
    final now = DateTime.now().toUtc();
    var totalGuests = 0;
    for (final source in veSources) {
      final data = await repository.loadProxmoxVe(source.id);
      final backupNamespaces = backupNamespacesFromStorageConfig(
        data.storageConfig,
        manualNamespace: source.backupNamespace,
      );
      final effectiveBackupNamespaces = backupNamespaces.isEmpty
          ? <String>[source.backupNamespace]
          : backupNamespaces.toList();
      for (final guest in data.vmResources.where(_isGuest)) {
        totalGuests += 1;
        final enrichedGuest = <String, Object?>{
          'source': source.name,
          'sourceId': source.id,
          'backupNamespace': source.backupNamespace,
          'backupNamespaces': effectiveBackupNamespaces,
          ...guest,
        };
        allGuests.add(enrichedGuest);
        final guestType = guest['type']?.toString() ?? '';
        final vmid = guest['vmid']?.toString() ?? '';
        final summary = analyzeGuestBackups(
          guestType: guestType,
          vmid: vmid,
          guestName: guest['name']?.toString() ?? '',
          backupNamespaces: effectiveBackupNamespaces,
          snapshots: snapshots,
          now: now,
        );
        final locationFreshness = analyzePbsBackupLocationFreshness(
          summary.matches,
        );
        final backupLocationLabels = locationFreshness.latestByLocation.values
            .map(
              (snapshot) =>
                  '${_backupLocationLabel(snapshot)}: '
                  '${_formatDateTime(snapshotTime(snapshot))}',
            )
            .where((location) => location.isNotEmpty)
            .toSet();
        if ((summary.status == BackupAgeStatus.ok ||
                summary.status == BackupAgeStatus.warning) &&
            locationFreshness.currentLocationCount >= 2) {
          continue;
        }
        guests.add(
          _GuestBackupIssue(
            sourceId: source.id,
            sourceName: source.name,
            node: guest['node']?.toString() ?? '',
            guestType: guestType,
            vmid: vmid,
            name: guest['name']?.toString() ?? '',
            guestStatus: guest['status']?.toString() ?? 'unknown',
            status: summary.status,
            problem: backupProblemDescription(
              summary,
              currentBackupLocationCount:
                  locationFreshness.currentLocationCount,
              totalBackupLocationCount:
                  locationFreshness.latestByLocation.length,
              now: now,
            ),
            backupLocationCount: locationFreshness.currentLocationCount,
            backupLocations: backupLocationLabels,
            latestBackupAt: summary.latestBackupAt,
          ),
        );
      }
    }

    guests.sort((a, b) {
      final statusCompare = a.status.index.compareTo(b.status.index);
      if (statusCompare != 0) {
        return -statusCompare;
      }
      return (a.latestBackupAt ?? DateTime(0)).compareTo(
        b.latestBackupAt ?? DateTime(0),
      );
    });

    return _BackupHealthReport(
      issues: guests,
      namespaceGaps: analyzeRootNamespaceGaps(
        guests: allGuests,
        snapshots: snapshots,
      ),
      totalGuests: totalGuests,
      pbsSources: pbsSources.length,
      snapshots: snapshots.length,
    );
  }
}

class _BackupHealthContent extends StatelessWidget {
  const _BackupHealthContent({required this.report});

  final _BackupHealthReport report;

  @override
  Widget build(BuildContext context) {
    final missing = report.issues
        .where((issue) => issue.status == BackupAgeStatus.missing)
        .length;
    final critical = report.issues
        .where((issue) => issue.status == BackupAgeStatus.critical)
        .length;
    final namespaceGaps = report.namespaceGaps.length;
    final insufficientLocations = report.issues
        .where((issue) => issue.backupLocationCount < 2)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const PageHeader(
          title: 'Backup health',
          subtitle: 'VM/LXC без backup или с backup старше 7 дней',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            MetricCard(
              label: 'Проблемы',
              value: report.issues.length.toString(),
              icon: Icons.report_problem_outlined,
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
              label: 'Старше 7 дней',
              value: critical.toString(),
              icon: Icons.schedule_outlined,
              color: critical == 0 ? AppColors.success : AppColors.danger,
            ),
            MetricCard(
              label: 'Меньше 2 мест',
              value: insufficientLocations.toString(),
              icon: Icons.copy_all_outlined,
              color: insufficientLocations == 0
                  ? AppColors.success
                  : AppColors.warning,
            ),
            MetricCard(
              label: 'Root без namespace',
              value: namespaceGaps.toString(),
              icon: Icons.drive_folder_upload_outlined,
              color: namespaceGaps == 0 ? AppColors.success : AppColors.warning,
            ),
            MetricCard(
              label: 'Всего VM/LXC',
              value: report.totalGuests.toString(),
              icon: Icons.memory_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _BackupStatusInfoCard(),
        const SizedBox(height: 16),
        _NamespaceGapTable(items: report.namespaceGaps),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Проблемные VM/LXC',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (report.issues.isEmpty)
                const EmptyState(
                  icon: Icons.verified_outlined,
                  text: 'Проблемных VM/LXC по backup не найдено.',
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SortableDataTable<_GuestBackupIssue>(
                    showCheckboxColumn: false,
                    initialSortColumnIndex: 8,
                    items: report.issues,
                    columns: <SortableDataColumn<_GuestBackupIssue>>[
                      SortableDataColumn<_GuestBackupIssue>(
                        label: 'status',
                        compare: (left, right) =>
                            compareText(left.statusLabel, right.statusLabel),
                      ),
                      SortableDataColumn<_GuestBackupIssue>(
                        label: 'проблема',
                        compare: (left, right) =>
                            compareText(left.problem, right.problem),
                      ),
                      SortableDataColumn<_GuestBackupIssue>(
                        label: 'места backup',
                        compare: (left, right) => left.backupLocationCount
                            .compareTo(right.backupLocationCount),
                      ),
                      SortableDataColumn<_GuestBackupIssue>(
                        label: 'source',
                        compare: (left, right) =>
                            compareText(left.sourceName, right.sourceName),
                      ),
                      SortableDataColumn<_GuestBackupIssue>(
                        label: 'node',
                        compare: (left, right) =>
                            compareText(left.node, right.node),
                      ),
                      SortableDataColumn<_GuestBackupIssue>(
                        label: 'vm/lxc',
                        compare: (left, right) => compareText(
                          '${left.guestType}/${left.vmid}',
                          '${right.guestType}/${right.vmid}',
                        ),
                      ),
                      SortableDataColumn<_GuestBackupIssue>(
                        label: 'name',
                        compare: (left, right) =>
                            compareText(left.name, right.name),
                      ),
                      SortableDataColumn<_GuestBackupIssue>(
                        label: 'vm status',
                        compare: (left, right) =>
                            compareText(left.guestStatus, right.guestStatus),
                      ),
                      SortableDataColumn<_GuestBackupIssue>(
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
                          DataCell(StatusChip(status: issue.statusLabel)),
                          DataCell(Text(issue.problem)),
                          DataCell(
                            Text(
                              'актуально ${issue.backupLocationCount} из 2'
                              '${issue.backupLocations.isEmpty ? '' : ' — ${issue.backupLocations.join(', ')}'}',
                            ),
                          ),
                          DataCell(Text(issue.sourceName)),
                          DataCell(Text(issue.node)),
                          DataCell(Text('${issue.guestType}/${issue.vmid}')),
                          DataCell(Text(issue.name)),
                          DataCell(StatusChip(status: issue.guestStatus)),
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

class _BackupStatusInfoCard extends StatelessWidget {
  const _BackupStatusInfoCard();

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
              'Backup status: ok — backup за последние 24 часа; '
              'warning — backup от 1 до 7 дней; critical — backup старше '
              '7 дней; missing — snapshots для VM/LXC не найдены. Для '
              'отказоустойчивости требуется минимум 2 места хранения с '
              'backup за одну и ту же дату.',
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

class _NamespaceGapTable extends StatelessWidget {
  const _NamespaceGapTable({required this.items});

  final List<BackupNamespaceGap> items;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Root backups без namespace',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Переходное состояние: backup найден в root namespace, но в '
            'namespace из PVE storage config для этой VM/LXC backup ещё не найден.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.mutedInk),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const EmptyState(
              icon: Icons.verified_outlined,
              text: 'Root-only backups для namespaced VM/LXC не найдены.',
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SortableDataTable<BackupNamespaceGap>(
                showCheckboxColumn: false,
                initialSortColumnIndex: 6,
                items: items,
                columns: <SortableDataColumn<BackupNamespaceGap>>[
                  SortableDataColumn<BackupNamespaceGap>(
                    label: 'source',
                    compare: (left, right) =>
                        compareText(left.sourceName, right.sourceName),
                  ),
                  SortableDataColumn<BackupNamespaceGap>(
                    label: 'node',
                    compare: (left, right) =>
                        compareText(left.node, right.node),
                  ),
                  SortableDataColumn<BackupNamespaceGap>(
                    label: 'vm/lxc',
                    compare: (left, right) =>
                        compareText(left.displayName, right.displayName),
                  ),
                  SortableDataColumn<BackupNamespaceGap>(
                    label: 'name',
                    compare: (left, right) =>
                        compareText(left.name, right.name),
                  ),
                  SortableDataColumn<BackupNamespaceGap>(
                    label: 'expected namespace',
                    compare: (left, right) => compareText(
                      left.expectedNamespaces.join(', '),
                      right.expectedNamespaces.join(', '),
                    ),
                  ),
                  SortableDataColumn<BackupNamespaceGap>(
                    label: 'root backups',
                    numeric: true,
                    compare: (left, right) =>
                        left.rootBackupCount.compareTo(right.rootBackupCount),
                  ),
                  SortableDataColumn<BackupNamespaceGap>(
                    label: 'root last backup',
                    compare: (left, right) => compareNullableDateTime(
                      left.rootLatestBackupAt,
                      right.rootLatestBackupAt,
                    ),
                  ),
                ],
                rowBuilder: (context, item) {
                  return DataRow(
                    onSelectChanged: (_) {
                      final query = item.name.isEmpty
                          ? ''
                          : '?name=${Uri.encodeQueryComponent(item.name)}';
                      context.go(
                        '/sources/${item.sourceId}/guests/'
                        '${item.guestType}/'
                        '${Uri.encodeComponent(item.node)}/'
                        '${item.vmid}$query',
                      );
                    },
                    cells: <DataCell>[
                      DataCell(Text(item.sourceName)),
                      DataCell(Text(item.node)),
                      DataCell(Text(item.displayName)),
                      DataCell(Text(item.name)),
                      DataCell(Text(item.expectedNamespaces.join(', '))),
                      DataCell(Text(item.rootBackupCount.toString())),
                      DataCell(Text(_formatDateTime(item.rootLatestBackupAt))),
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

class _BackupHealthReport {
  const _BackupHealthReport({
    required this.issues,
    required this.namespaceGaps,
    required this.totalGuests,
    required this.pbsSources,
    required this.snapshots,
  });

  const _BackupHealthReport.empty()
    : issues = const <_GuestBackupIssue>[],
      namespaceGaps = const <BackupNamespaceGap>[],
      totalGuests = 0,
      pbsSources = 0,
      snapshots = 0;

  final List<_GuestBackupIssue> issues;
  final List<BackupNamespaceGap> namespaceGaps;
  final int totalGuests;
  final int pbsSources;
  final int snapshots;
}

class _GuestBackupIssue {
  const _GuestBackupIssue({
    required this.sourceId,
    required this.sourceName,
    required this.node,
    required this.guestType,
    required this.vmid,
    required this.name,
    required this.guestStatus,
    required this.status,
    required this.problem,
    required this.backupLocationCount,
    required this.backupLocations,
    required this.latestBackupAt,
  });

  final String sourceId;
  final String sourceName;
  final String node;
  final String guestType;
  final String vmid;
  final String name;
  final String guestStatus;
  final BackupAgeStatus status;
  final String problem;
  final int backupLocationCount;
  final Set<String> backupLocations;
  final DateTime? latestBackupAt;

  String get statusLabel =>
      backupLocationCount < 2 &&
          (status == BackupAgeStatus.ok || status == BackupAgeStatus.warning)
      ? 'warning'
      : backupStatusLabel(status);
}

bool _isGuest(Map<String, Object?> item) {
  return item['type'] == 'qemu' || item['type'] == 'lxc';
}

String _backupLocationLabel(Map<String, Object?> snapshot) {
  final source = snapshot['backupSource']?.toString() ?? '';
  final datastore = snapshot['datastore']?.toString() ?? '';
  final namespace = snapshotNamespace(snapshot);
  final base = datastore.isEmpty ? source : '$source / $datastore';
  return namespace.isEmpty ? base : '$base / $namespace';
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
