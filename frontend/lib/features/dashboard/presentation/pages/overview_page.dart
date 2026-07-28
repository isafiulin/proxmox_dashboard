import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:frontend/core/design/app_colors.dart';
import 'package:frontend/features/audit/presentation/cubit/audit_cubit.dart';
import 'package:frontend/features/dashboard/data/health_data_loader.dart';
import 'package:frontend/features/dashboard/domain/health_models.dart';
import 'package:frontend/features/dashboard/presentation/cubit/dashboard_cubit.dart';
import 'package:frontend/features/snapshots/domain/data_snapshot.dart';
import 'package:frontend/features/snapshots/domain/resource_history.dart';
import 'package:frontend/features/snapshots/presentation/cubit/snapshots_cubit.dart';
import 'package:frontend/features/sources/domain/backup_analysis.dart';
import 'package:frontend/features/sources/domain/pbs_health.dart';
import 'package:frontend/features/sources/domain/source.dart';
import 'package:frontend/features/sources/presentation/cubit/sources_cubit.dart';
import 'package:frontend/features/users/presentation/cubit/users_cubit.dart';
import 'package:frontend/shared/formatters/value_formatters.dart';
import 'package:frontend/shared/widgets/app_card.dart';
import 'package:frontend/shared/widgets/async_state_view.dart';
import 'package:frontend/shared/widgets/empty_state.dart';
import 'package:frontend/shared/widgets/metric_card.dart';
import 'package:frontend/shared/widgets/resource_line_chart.dart';
import 'package:frontend/shared/widgets/status_chip.dart';
import 'package:go_router/go_router.dart';

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
                      color: AppColors.primaryDark,
                    );
                  },
                ),
                MetricCard(
                  label: 'VM/LXC',
                  value: '${dashboardState.summary?.guests ?? 0}',
                  icon: Icons.memory_outlined,
                  color: AppColors.success,
                ),
                MetricCard(
                  label: 'Критичные события',
                  value: '${dashboardState.summary?.criticalAlerts ?? 0}',
                  icon: Icons.warning_amber_outlined,
                  color: (dashboardState.summary?.criticalAlerts ?? 0) == 0
                      ? AppColors.success
                      : AppColors.danger,
                ),
              ],
            ),
            const SizedBox(height: 24),
            const _SuperCriticalAlarms(),
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

class _SuperCriticalAlarms extends StatefulWidget {
  const _SuperCriticalAlarms();

  @override
  State<_SuperCriticalAlarms> createState() => _SuperCriticalAlarmsState();
}

class _SuperCriticalAlarmsState extends State<_SuperCriticalAlarms> {
  _AlarmCategory _category = _AlarmCategory.all;
  List<Source>? _loadedSources;
  Future<HealthRuntimeData>? _healthFuture;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SourcesCubit, SourcesState>(
      builder: (BuildContext context, SourcesState state) {
        if (state.items.isEmpty) {
          return const SizedBox.shrink();
        }
        if (!identical(_loadedSources, state.items)) {
          _loadedSources = state.items;
          _healthFuture = loadHealthRuntimeData(context, state.items);
        }
        return FutureBuilder<HealthRuntimeData>(
          future: _healthFuture,
          builder:
              (
                BuildContext context,
                AsyncSnapshot<HealthRuntimeData> snapshot,
              ) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const AppCard(child: LoadingStateView());
                }
                if (snapshot.hasError) {
                  return ErrorStateView(message: snapshot.error.toString());
                }
                final data = snapshot.data;
                final alarms = data == null
                    ? <_CriticalAlarm>[]
                    : _buildCriticalAlarms(data);
                final visible = _category == _AlarmCategory.all
                    ? alarms
                    : alarms
                          .where((alarm) => alarm.category == _category)
                          .toList();
                return AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Icon(Icons.priority_high_outlined),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Super critical alarms',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          StatusChip(
                            status: alarms.isEmpty
                                ? 'ok'
                                : '${alarms.length} critical',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _AlarmCategory.values.map((category) {
                          return FilterChip(
                            label: Text(category.label),
                            selected: _category == category,
                            onSelected: (_) =>
                                setState(() => _category = category),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      if (visible.isEmpty)
                        const EmptyState(
                          icon: Icons.verified_outlined,
                          text: 'Alarm-ов в этой категории сейчас нет.',
                        )
                      else
                        _CriticalAlarmList(alarms: visible),
                    ],
                  ),
                );
              },
        );
      },
    );
  }
}

class _CriticalAlarmList extends StatelessWidget {
  const _CriticalAlarmList({required this.alarms});

  final List<_CriticalAlarm> alarms;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 560),
      child: Scrollbar(
        child: SingleChildScrollView(
          child: Column(children: alarms.map(_CriticalAlarmTile.new).toList()),
        ),
      ),
    );
  }
}

class _CriticalAlarmTile extends StatelessWidget {
  const _CriticalAlarmTile(this.alarm);

  final _CriticalAlarm alarm;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(alarm.icon, color: Colors.redAccent),
      title: Text(alarm.title),
      subtitle: Text(alarm.subtitle),
      trailing: const StatusChip(status: 'critical'),
      onTap: alarm.path == null ? null : () => context.go(alarm.path!),
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
                          mainAxisExtent: 260,
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

class _CriticalAlarm {
  const _CriticalAlarm({
    required this.priority,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.category,
    this.path,
  });

  final int priority;
  final IconData icon;
  final String title;
  final String subtitle;
  final _AlarmCategory category;
  final String? path;
}

List<_CriticalAlarm> _buildCriticalAlarms(HealthRuntimeData data) {
  final alarms = <_CriticalAlarm>[];

  for (final error in data.collectionErrors) {
    alarms.add(
      _CriticalAlarm(
        priority: 0,
        icon: Icons.cloud_off_outlined,
        title: 'Ошибка сбора: ${error['source'] ?? 'source'}',
        subtitle: error['error']?.toString() ?? 'Интеграция не ответила.',
        category: _AlarmCategory.integration,
      ),
    );
  }

  for (final guest in data.guests) {
    final status = guest['status']?.toString().toLowerCase() ?? '';
    final source = guest['source']?.toString() ?? '';
    final node = guest['node']?.toString() ?? '';
    final guestType = guest['type']?.toString() ?? '';
    final vmid = guest['vmid']?.toString() ?? '';
    final name = guest['name']?.toString() ?? '';
    final label = name.isEmpty
        ? '$guestType/$vmid'
        : '$name ($guestType/$vmid)';
    final path = _guestPath(guest);

    final backupSummary = analyzeGuestBackups(
      guestType: guestType,
      vmid: vmid,
      guestName: name,
      backupNamespace: guest['backupNamespace']?.toString() ?? '',
      backupNamespaces: guestBackupNamespaces(guest),
      snapshots: data.backupSnapshots,
    );
    if (status == 'running' &&
        backupSummary.status == BackupAgeStatus.missing) {
      alarms.add(
        _CriticalAlarm(
          priority: 1,
          icon: Icons.backup_outlined,
          title: '$label работает без backup',
          subtitle: '$source / $node · snapshots для VM/LXC не найдены',
          category: _AlarmCategory.backup,
          path: path,
        ),
      );
    }

    _addRatioAlarm(
      alarms,
      priority: 3,
      icon: Icons.speed_outlined,
      title: '$label CPU >= 90%',
      subtitle: '$source / $node · ${formatPercent(ratioValue(guest['cpu']))}',
      value: ratioValue(guest['cpu']),
      path: path,
      category: _AlarmCategory.resource,
    );
    _addRatioAlarm(
      alarms,
      priority: 3,
      icon: Icons.memory_outlined,
      title: '$label RAM >= 90%',
      subtitle:
          '$source / $node · ${formatPercent(ratioPairValue(guest['mem'], guest['maxmem']))}',
      value: ratioPairValue(guest['mem'], guest['maxmem']),
      path: path,
      category: _AlarmCategory.resource,
    );
  }

  for (final node in data.nodes) {
    final source = node['source']?.toString() ?? '';
    final nodeName = node['node']?.toString() ?? '';
    final path = _nodePath(node);
    _addRatioAlarm(
      alarms,
      priority: 2,
      icon: Icons.hub_outlined,
      title: 'Нода $nodeName CPU >= 90%',
      subtitle: '$source · ${formatPercent(ratioValue(node['cpu']))}',
      value: ratioValue(node['cpu']),
      path: path,
      category: _AlarmCategory.resource,
    );
    _addRatioAlarm(
      alarms,
      priority: 2,
      icon: Icons.memory_outlined,
      title: 'Нода $nodeName RAM >= 90%',
      subtitle:
          '$source · ${formatPercent(ratioPairValue(node['mem'], node['maxmem']))}',
      value: ratioPairValue(node['mem'], node['maxmem']),
      path: path,
      category: _AlarmCategory.resource,
    );
  }

  for (final storage in data.storageResources) {
    final usage = ratioPairValue(storage['disk'], storage['maxdisk']);
    final nodeName = storage['node']?.toString() ?? '';
    final storageName = storage['storage']?.toString() ?? 'storage';
    _addRatioAlarm(
      alarms,
      priority: 2,
      icon: Icons.storage_outlined,
      title: 'Storage $storageName >= 90%',
      subtitle:
          '${storage['source'] ?? ''} / $nodeName · ${formatPercent(usage)} · '
          '${formatBytes(storage['disk'])} / ${formatBytes(storage['maxdisk'])}',
      value: usage,
      path: _nodePath(storage),
      category: _AlarmCategory.resource,
    );
  }

  for (final task in data.tasks.where(isPbsTaskAlarm)) {
    final sourceId = task['sourceId']?.toString() ?? '';
    final workerType = task['worker_type']?.toString() ?? 'task';
    alarms.add(
      _CriticalAlarm(
        priority: 1,
        icon: Icons.task_alt_outlined,
        title: 'PBS task failed: $workerType',
        subtitle:
            '${task['source'] ?? ''} · ${task['worker_id'] ?? ''} · ${task['status'] ?? ''}',
        category: isPbsMaintenanceTask(task)
            ? _AlarmCategory.backup
            : _AlarmCategory.integration,
        path: sourceId.isEmpty ? '/pbs-health' : '/sources/$sourceId',
      ),
    );
  }

  alarms.sort((left, right) {
    final priorityCompare = left.priority.compareTo(right.priority);
    if (priorityCompare != 0) {
      return priorityCompare;
    }
    return left.title.compareTo(right.title);
  });
  return alarms;
}

void _addRatioAlarm(
  List<_CriticalAlarm> alarms, {
  required int priority,
  required IconData icon,
  required String title,
  required String subtitle,
  required double value,
  required String? path,
  required _AlarmCategory category,
}) {
  if (value >= 0.9) {
    alarms.add(
      _CriticalAlarm(
        priority: priority,
        icon: icon,
        title: title,
        subtitle: subtitle,
        category: category,
        path: path,
      ),
    );
  }
}

enum _AlarmCategory {
  all('All'),
  backup('Backup'),
  resource('Resource'),
  integration('Integration');

  const _AlarmCategory(this.label);

  final String label;
}

String? _nodePath(Map<String, Object?> row) {
  final sourceId = row['sourceId']?.toString() ?? '';
  final node = row['node']?.toString() ?? '';
  if (sourceId.isEmpty || node.isEmpty) {
    return null;
  }
  return '/sources/$sourceId/nodes/${Uri.encodeComponent(node)}';
}

String? _guestPath(Map<String, Object?> row) {
  final sourceId = row['sourceId']?.toString() ?? '';
  final guestType = row['type']?.toString() ?? '';
  final node = row['node']?.toString() ?? '';
  final vmid = row['vmid']?.toString() ?? '';
  if (sourceId.isEmpty || guestType.isEmpty || node.isEmpty || vmid.isEmpty) {
    return null;
  }
  final name = row['name']?.toString() ?? '';
  final query = name.isEmpty ? '' : '?name=${Uri.encodeQueryComponent(name)}';
  return '/sources/$sourceId/guests/$guestType/'
      '${Uri.encodeComponent(node)}/$vmid$query';
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
    'old_ilo2' => Icons.dns_outlined,
    'ipmi' => Icons.sensors_outlined,
    _ => Icons.storage_outlined,
  };
}

String sourceTypeLabel(String type) {
  return switch (type) {
    'proxmox_ve' => 'Proxmox VE',
    'proxmox_backup' => 'Proxmox Backup Server',
    'redfish' => 'BMC / Redfish',
    'old_ilo2' => 'Old HP iLO 2',
    'ipmi' => 'IPMI 2.0',
    _ => type,
  };
}
