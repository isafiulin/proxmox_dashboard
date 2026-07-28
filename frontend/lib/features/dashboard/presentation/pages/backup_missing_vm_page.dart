import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/design/app_colors.dart';
import 'package:frontend/features/dashboard/data/health_data_loader.dart';
import 'package:frontend/features/sources/domain/backup_analysis.dart';
import 'package:frontend/features/sources/domain/source.dart';
import 'package:frontend/features/sources/presentation/cubit/sources_cubit.dart';
import 'package:frontend/shared/formatters/value_formatters.dart';
import 'package:frontend/shared/widgets/app_card.dart';
import 'package:frontend/shared/widgets/async_state_view.dart';
import 'package:frontend/shared/widgets/empty_state.dart';
import 'package:frontend/shared/widgets/metric_card.dart';
import 'package:frontend/shared/widgets/page_header.dart';
import 'package:frontend/shared/widgets/sortable_data_table.dart';
import 'package:go_router/go_router.dart';

class BackupMissingVmPage extends StatelessWidget {
  const BackupMissingVmPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SourcesCubit, SourcesState>(
      builder: (BuildContext context, SourcesState state) {
        if (state.status == SourcesStatus.loading && state.items.isEmpty) {
          return const LoadingStateView();
        }
        return FutureBuilder<BackupMissingGuestsReport>(
          future: _load(context, state.items),
          builder:
              (
                BuildContext context,
                AsyncSnapshot<BackupMissingGuestsReport> snapshot,
              ) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LoadingStateView();
                }
                if (snapshot.hasError) {
                  return ErrorStateView(message: snapshot.error.toString());
                }
                final report =
                    snapshot.data ??
                    const BackupMissingGuestsReport(
                      items: <BackupMissingGuestItem>[],
                      totalBackupGroups: 0,
                      deployedGuests: 0,
                    );
                return _BackupMissingVmContent(report: report);
              },
        );
      },
    );
  }

  Future<BackupMissingGuestsReport> _load(
    BuildContext context,
    List<Source> sources,
  ) async {
    final data = await loadHealthRuntimeData(context, sources);
    return analyzeMissingBackupGuests(
      snapshots: data.backupSnapshots,
      guests: data.guests,
    );
  }
}

class _BackupMissingVmContent extends StatelessWidget {
  const _BackupMissingVmContent({required this.report});

  final BackupMissingGuestsReport report;

  @override
  Widget build(BuildContext context) {
    final withCandidates = report.items
        .where((item) => item.candidates.isNotEmpty)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const PageHeader(
          title: 'Backup missing VM',
          subtitle:
              'PBS backups без уверенного совпадения с текущими VM/LXC на PVE',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            MetricCard(
              label: 'Orphan backup groups',
              value: report.missingGroups.toString(),
              icon: Icons.report_gmailerrorred_outlined,
              color: report.missingGroups == 0
                  ? AppColors.success
                  : AppColors.danger,
            ),
            MetricCard(
              label: 'PBS groups',
              value: report.totalBackupGroups.toString(),
              icon: Icons.backup_outlined,
            ),
            MetricCard(
              label: 'Deployed VM/LXC',
              value: report.deployedGuests.toString(),
              icon: Icons.developer_board_outlined,
            ),
            MetricCard(
              label: 'Name candidates',
              value: withCandidates.toString(),
              icon: Icons.manage_search_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _MissingBackupInfoCard(),
        const SizedBox(height: 16),
        _MissingBackupTable(items: report.items),
      ],
    );
  }
}

class _MissingBackupInfoCard extends StatelessWidget {
  const _MissingBackupInfoCard();

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
              'Экран ищет backup groups в PBS, которые не совпали с '
              'текущими VM/LXC. Если в snapshot есть PBS notes/comment, '
              'имя тоже участвует в проверке, чтобы одинаковые VMID из '
              'разных кластеров не смешивались.',
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

class _MissingBackupTable extends StatelessWidget {
  const _MissingBackupTable({required this.items});

  final List<BackupMissingGuestItem> items;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'PBS backups без текущей VM/LXC',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const EmptyState(
              icon: Icons.verified_outlined,
              text: 'Orphan backups не найдены.',
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SortableDataTable<BackupMissingGuestItem>(
                showCheckboxColumn: false,
                initialSortColumnIndex: 4,
                initialSortAscending: false,
                items: items,
                columns: <SortableDataColumn<BackupMissingGuestItem>>[
                  SortableDataColumn<BackupMissingGuestItem>(
                    label: 'backup',
                    compare: (left, right) =>
                        compareText(left.displayName, right.displayName),
                  ),
                  SortableDataColumn<BackupMissingGuestItem>(
                    label: 'namespace',
                    compare: (left, right) =>
                        compareText(left.namespace, right.namespace),
                  ),
                  SortableDataColumn<BackupMissingGuestItem>(
                    label: 'pbs name',
                    compare: (left, right) =>
                        compareText(left.snapshotName, right.snapshotName),
                  ),
                  SortableDataColumn<BackupMissingGuestItem>(
                    label: 'sources',
                    compare: (left, right) => compareText(
                      left.backupSources.join(', '),
                      right.backupSources.join(', '),
                    ),
                  ),
                  SortableDataColumn<BackupMissingGuestItem>(
                    label: 'datastores',
                    compare: (left, right) => compareText(
                      left.datastores.join(', '),
                      right.datastores.join(', '),
                    ),
                  ),
                  SortableDataColumn<BackupMissingGuestItem>(
                    label: 'last backup',
                    compare: (left, right) => compareNullableDateTime(
                      left.latestBackupAt,
                      right.latestBackupAt,
                    ),
                  ),
                  SortableDataColumn<BackupMissingGuestItem>(
                    label: 'events',
                    numeric: true,
                    compare: (left, right) => left.count.compareTo(right.count),
                  ),
                  SortableDataColumn<BackupMissingGuestItem>(
                    label: 'size',
                    numeric: true,
                    compare: (left, right) =>
                        left.totalSizeBytes.compareTo(right.totalSizeBytes),
                  ),
                  SortableDataColumn<BackupMissingGuestItem>(
                    label: 'possible match',
                    compare: (left, right) => compareText(
                      _candidateText(left.candidates),
                      _candidateText(right.candidates),
                    ),
                  ),
                ],
                rowBuilder:
                    (BuildContext context, BackupMissingGuestItem item) {
                      final candidate = item.candidates.isEmpty
                          ? null
                          : item.candidates.first;
                      return DataRow(
                        onSelectChanged: candidate == null
                            ? null
                            : (_) => _openCandidate(context, candidate),
                        cells: <DataCell>[
                          DataCell(Text(item.displayName)),
                          DataCell(Text(_namespaceLabel(item.namespace))),
                          DataCell(
                            Text(
                              item.snapshotName.isEmpty
                                  ? '-'
                                  : item.snapshotName,
                            ),
                          ),
                          DataCell(Text(_joinSet(item.backupSources))),
                          DataCell(Text(_joinSet(item.datastores))),
                          DataCell(Text(_formatDateTime(item.latestBackupAt))),
                          DataCell(Text(item.count.toString())),
                          DataCell(Text(formatBytes(item.totalSizeBytes))),
                          DataCell(_CandidateCell(candidates: item.candidates)),
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

class _CandidateCell extends StatelessWidget {
  const _CandidateCell({required this.candidates});

  final List<BackupMissingGuestCandidate> candidates;

  @override
  Widget build(BuildContext context) {
    if (candidates.isEmpty) {
      return const Text('-');
    }
    final candidate = candidates.first;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Text(
        '${candidate.name.isEmpty ? candidate.displayName : candidate.name} '
        '(${candidate.sourceName} / ${candidate.node} / '
        '${candidate.displayName}, ${candidate.reason})',
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

void _openCandidate(
  BuildContext context,
  BackupMissingGuestCandidate candidate,
) {
  final query = candidate.name.isEmpty
      ? ''
      : '?name=${Uri.encodeQueryComponent(candidate.name)}';
  context.go(
    '/sources/${candidate.sourceId}/guests/'
    '${candidate.guestType}/${Uri.encodeComponent(candidate.node)}/'
    '${candidate.vmid}$query',
  );
}

String _candidateText(List<BackupMissingGuestCandidate> candidates) {
  if (candidates.isEmpty) {
    return '';
  }
  final candidate = candidates.first;
  return '${candidate.name} ${candidate.sourceName} ${candidate.node}';
}

String _joinSet(Set<String> values) {
  return values.isEmpty ? '-' : values.join(', ');
}

String _namespaceLabel(String namespace) {
  return namespace.isEmpty ? 'root' : namespace;
}

String _formatDateTime(DateTime? value) {
  if (value == null) {
    return '-';
  }
  final local = value.toLocal();
  String two(int input) => input.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
