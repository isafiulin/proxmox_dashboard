import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:frontend/features/audit/presentation/cubit/audit_cubit.dart';
import 'package:frontend/features/dashboard/presentation/cubit/dashboard_cubit.dart';
import 'package:frontend/features/snapshots/domain/data_snapshot.dart';
import 'package:frontend/features/snapshots/domain/resource_history.dart';
import 'package:frontend/features/snapshots/presentation/cubit/snapshots_cubit.dart';
import 'package:frontend/features/sources/domain/source.dart';
import 'package:frontend/features/sources/presentation/cubit/sources_cubit.dart';
import 'package:frontend/features/users/presentation/cubit/users_cubit.dart';
import 'package:frontend/shared/widgets/app_card.dart';
import 'package:frontend/shared/widgets/async_state_view.dart';
import 'package:frontend/shared/widgets/empty_state.dart';
import 'package:frontend/shared/widgets/metric_card.dart';
import 'package:frontend/shared/widgets/resource_line_chart.dart';
import 'package:frontend/shared/widgets/status_chip.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardCubit, DashboardState>(
      builder: (BuildContext context, DashboardState dashboardState) {
        if (dashboardState.status == DashboardStatus.loading &&
            dashboardState.summary == null) {
          return const LoadingStateView();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: <Widget>[
                MetricCard(
                  label: 'Источники',
                  value: '${dashboardState.summary?.sources ?? 0}',
                  icon: Icons.storage_outlined,
                ),
                BlocBuilder<UsersCubit, UsersState>(
                  builder: (BuildContext context, UsersState state) {
                    return MetricCard(
                      label: 'Пользователи',
                      value: '${state.items.length}',
                      icon: Icons.people_outline,
                    );
                  },
                ),
                MetricCard(
                  label: 'VM/LXC',
                  value: '${dashboardState.summary?.guests ?? 0}',
                  icon: Icons.memory_outlined,
                ),
                MetricCard(
                  label: 'Критичные события',
                  value: '${dashboardState.summary?.criticalAlerts ?? 0}',
                  icon: Icons.warning_amber_outlined,
                ),
              ],
            ),
            const SizedBox(height: 24),
            const _CollectionHistory(),
            const SizedBox(height: 24),
            const _ResourceHistorySection(),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool wide = constraints.maxWidth > 900;
                if (wide) {
                  return const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(child: _RecentSources()),
                      SizedBox(width: 16),
                      Expanded(child: _RecentAudit()),
                    ],
                  );
                }
                return const Column(
                  children: <Widget>[
                    _RecentSources(),
                    SizedBox(height: 16),
                    _RecentAudit(),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _ResourceHistorySection extends StatelessWidget {
  const _ResourceHistorySection();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SnapshotsCubit, SnapshotsState>(
      builder: (BuildContext context, SnapshotsState state) {
        final report = buildResourceHistory(state.items);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'История ресурсов',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (report.isEmpty)
              const AppCard(
                child: EmptyState(
                  icon: Icons.show_chart_outlined,
                  text: 'История ресурсов появится после нескольких сборов.',
                ),
              )
            else
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final wide = constraints.maxWidth > 980;
                  final charts = <Widget>[
                    ResourceLineChart(
                      title: 'Ноды CPU',
                      points: report.nodeCpu,
                      icon: Icons.speed_outlined,
                    ),
                    ResourceLineChart(
                      title: 'Ноды RAM',
                      points: report.nodeRam,
                      icon: Icons.memory_outlined,
                    ),
                    ResourceLineChart(
                      title: 'VM/LXC CPU',
                      points: report.guestCpu,
                      icon: Icons.developer_board_outlined,
                    ),
                    ResourceLineChart(
                      title: 'VM/LXC RAM',
                      points: report.guestRam,
                      icon: Icons.memory,
                    ),
                    ResourceLineChart(
                      title: 'Storage usage',
                      points: report.storageUsage,
                      icon: Icons.storage_outlined,
                    ),
                  ];
                  if (!wide) {
                    return Column(
                      children: charts
                          .map(
                            (chart) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: chart,
                            ),
                          )
                          .toList(),
                    );
                  }
                  return GridView.builder(
                    itemCount: charts.length,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          mainAxisExtent: 220,
                        ),
                    itemBuilder: (BuildContext context, int index) =>
                        charts[index],
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

class _CollectionHistory extends StatelessWidget {
  const _CollectionHistory();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: BlocBuilder<SnapshotsCubit, SnapshotsState>(
        builder: (BuildContext context, SnapshotsState state) {
          final latest = state.items.isEmpty ? null : state.items.first;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'История сбора',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: state.status == SnapshotsStatus.loading
                        ? null
                        : () => context.read<SnapshotsCubit>().collectNow(),
                    icon: const Icon(Icons.sync_outlined),
                    label: const Text('Собрать сейчас'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  MetricCard(
                    label: 'Снимков за 7 дней',
                    value: state.items.length.toString(),
                    icon: Icons.history_outlined,
                  ),
                  MetricCard(
                    label: 'Последний сбор',
                    value: latest == null
                        ? '-'
                        : _formatDateTime(latest.collectedAt),
                    icon: Icons.schedule_outlined,
                  ),
                  MetricCard(
                    label: 'Статус',
                    value: latest?.status ?? '-',
                    icon: Icons.fact_check_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (state.items.isEmpty)
                const EmptyState(
                  icon: Icons.history_outlined,
                  text: 'Исторические snapshots пока не собраны.',
                )
              else
                ...state.items.take(6).map(_SnapshotTile.new),
            ],
          );
        },
      ),
    );
  }
}

class _SnapshotTile extends StatelessWidget {
  const _SnapshotTile(this.snapshot);

  final DataSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(_sourceIcon(snapshot.sourceType)),
      title: Text(
        '${_sourceTypeLabel(snapshot.sourceType)} · ${snapshot.status}',
      ),
      subtitle: Text(snapshot.error ?? _formatDateTime(snapshot.collectedAt)),
      trailing: StatusChip(status: snapshot.status),
    );
  }
}

class _RecentSources extends StatelessWidget {
  const _RecentSources();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: BlocBuilder<SourcesCubit, SourcesState>(
        builder: (BuildContext context, SourcesState state) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Источники', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              if (state.items.isEmpty)
                const EmptyState(
                  icon: Icons.storage_outlined,
                  text: 'Добавьте Proxmox VE или Proxmox Backup Server.',
                )
              else
                ...state.items.take(5).map(_SourceTile.new),
            ],
          );
        },
      ),
    );
  }
}

IconData _sourceIcon(String type) {
  return switch (type) {
    'proxmox_ve' => Icons.memory_outlined,
    'proxmox_backup' => Icons.backup_outlined,
    _ => Icons.storage_outlined,
  };
}

String _sourceTypeLabel(String type) {
  return switch (type) {
    'proxmox_ve' => 'Proxmox VE',
    'proxmox_backup' => 'Proxmox Backup',
    _ => type,
  };
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)} '
      '${two(local.hour)}:${two(local.minute)}';
}

class _SourceTile extends StatelessWidget {
  const _SourceTile(this.source);

  final Source source;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(sourceIcon(source.type)),
      title: Text(source.name),
      subtitle: Text('${sourceTypeLabel(source.type)} · ${source.baseUrl}'),
      trailing: StatusChip(status: source.status),
    );
  }
}

class _RecentAudit extends StatelessWidget {
  const _RecentAudit();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: BlocBuilder<AuditCubit, AuditState>(
        builder: (BuildContext context, AuditState state) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Последний аудит',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (state.items.isEmpty)
                const EmptyState(
                  icon: Icons.fact_check_outlined,
                  text: 'Событий пока нет.',
                )
              else
                ...state.items
                    .take(6)
                    .map(
                      (event) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: const Icon(Icons.history),
                        title: Text(event.action),
                        subtitle: Text(event.createdAt),
                      ),
                    ),
            ],
          );
        },
      ),
    );
  }
}

IconData sourceIcon(String type) {
  return switch (type) {
    'proxmox_ve' => Icons.memory_outlined,
    'proxmox_backup' => Icons.backup_outlined,
    'redfish' => Icons.developer_board_outlined,
    _ => Icons.storage_outlined,
  };
}

String sourceTypeLabel(String type) {
  return switch (type) {
    'proxmox_ve' => 'Proxmox VE',
    'proxmox_backup' => 'Proxmox Backup Server',
    'redfish' => 'iLO / Redfish',
    _ => type,
  };
}
