import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/core/design/app_colors.dart';
import 'package:frontend/features/sources/data/source_data_repository.dart';
import 'package:frontend/features/sources/domain/backup_analysis.dart';
import 'package:frontend/features/sources/domain/source.dart';
import 'package:frontend/features/sources/presentation/cubit/sources_cubit.dart';
import 'package:frontend/features/sources/presentation/detail_cubit/source_detail_cubit.dart';
import 'package:frontend/shared/formatters/value_formatters.dart';
import 'package:frontend/shared/tables/table_sorting.dart';
import 'package:frontend/shared/widgets/app_card.dart';
import 'package:frontend/shared/widgets/async_state_view.dart';
import 'package:frontend/shared/widgets/empty_state.dart';
import 'package:frontend/shared/widgets/generic_data_section.dart';
import 'package:frontend/shared/widgets/metric_card.dart';
import 'package:frontend/shared/widgets/page_header.dart';
import 'package:frontend/shared/widgets/status_chip.dart';
import 'package:frontend/shared/widgets/usage_bar.dart';
import 'package:go_router/go_router.dart';

class SourceDetailPage extends StatelessWidget {
  const SourceDetailPage({required this.sourceId, super.key});

  final String sourceId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SourcesCubit, SourcesState>(
      builder: (BuildContext context, SourcesState sourcesState) {
        final Source? source = sourcesState.items
            .where((Source source) => source.id == sourceId)
            .firstOrNull;

        if (source == null) {
          return const EmptyCardState(
            icon: Icons.storage_outlined,
            text: 'Источник не найден.',
          );
        }

        return BlocProvider<SourceDetailCubit>(
          create: (BuildContext context) =>
              SourceDetailCubit(SourceDataRepository(context.read<ApiClient>()))
                ..load(source),
          child: _SourceDetailContent(source: source),
        );
      },
    );
  }
}

class _SourceDetailContent extends StatelessWidget {
  const _SourceDetailContent({required this.source});

  final Source source;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        PageHeader(
          leading: OutlinedButton.icon(
            onPressed: () => context.go('/sources'),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Назад'),
          ),
          title: source.name,
          subtitle: source.baseUrl,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(_iconForSource(source.type), color: AppColors.primary),
              const SizedBox(width: 12),
              StatusChip(status: source.status),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Обновить данные',
                onPressed: () => context.read<SourceDetailCubit>().load(source),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        BlocBuilder<SourceDetailCubit, SourceDetailState>(
          builder: (BuildContext context, SourceDetailState state) {
            if (state.status == SourceDetailStatus.loading &&
                state.data == null) {
              return const LoadingStateView();
            }
            if (state.error != null) {
              return ErrorStateView(message: state.error!);
            }
            if (source.type == 'proxmox_ve') {
              return _ProxmoxVeSections(
                sourceId: source.id,
                data: state.data?.proxmoxVe,
              );
            }
            if (source.type == 'proxmox_backup') {
              return _ProxmoxBackupSections(data: state.data?.proxmoxBackup);
            }
            if (source.type == 'redfish') {
              return _RedfishSections(data: state.data?.redfish);
            }
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }
}

class _RedfishSections extends StatelessWidget {
  const _RedfishSections({required this.data});

  final RedfishData? data;

  @override
  Widget build(BuildContext context) {
    final identity = data?.identity ?? <String, Object?>{};
    final system = data?.systems.firstOrNull;
    final status = system?['Status'];
    final health = status is Map ? status['Health']?.toString() : null;
    final totalMemoryMiB =
        data?.memory.fold<int>(
          0,
          (total, row) =>
              total + (int.tryParse(row['CapacityMiB']?.toString() ?? '') ?? 0),
        ) ??
        0;
    return Column(
      children: <Widget>[
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: <Widget>[
            MetricCard(
              label: 'Модель',
              value: identity['model']?.toString() ?? 'unknown',
              icon: Icons.developer_board_outlined,
            ),
            MetricCard(
              label: 'Power',
              value: system?['PowerState']?.toString() ?? 'unknown',
              icon: Icons.power_settings_new,
            ),
            MetricCard(
              label: 'Health',
              value: health ?? 'unknown',
              icon: Icons.health_and_safety_outlined,
            ),
            MetricCard(
              label: 'CPU / RAM',
              value:
                  '${data?.processors.length ?? 0} / ${(totalMemoryMiB / 1024).toStringAsFixed(0)} GiB',
              icon: Icons.memory_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Текущие неисправности',
          rows: data?.healthIssues ?? <Map<String, Object?>>[],
          preferredColumns: const <String>[
            'resourceType',
            'name',
            'health',
            'state',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Процессоры',
          rows: data?.processors ?? <Map<String, Object?>>[],
          preferredColumns: const <String>[
            'Manufacturer',
            'Model',
            'Socket',
            'TotalCores',
            'TotalThreads',
            'MaxSpeedMHz',
            'Status',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Память',
          rows: data?.memory ?? <Map<String, Object?>>[],
          preferredColumns: const <String>[
            'DeviceLocator',
            'Manufacturer',
            'CapacityMiB',
            'OperatingSpeedMhz',
            'MemoryDeviceType',
            'Status',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Температуры',
          rows: data?.temperatures ?? <Map<String, Object?>>[],
          preferredColumns: const <String>[
            'Name',
            'ReadingCelsius',
            'UpperThresholdCritical',
            'UpperThresholdFatal',
            'Status',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Вентиляторы',
          rows: data?.fans ?? <Map<String, Object?>>[],
          preferredColumns: const <String>[
            'Name',
            'Reading',
            'ReadingUnits',
            'Status',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Блоки питания',
          rows: data?.powerSupplies ?? <Map<String, Object?>>[],
          preferredColumns: const <String>[
            'Name',
            'Model',
            'LineInputVoltage',
            'PowerInputWatts',
            'PowerOutputWatts',
            'PowerCapacityWatts',
            'Status',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'RAID-контроллеры',
          rows: data?.storageControllers ?? <Map<String, Object?>>[],
          preferredColumns: const <String>[
            'Name',
            'Model',
            'FirmwareVersion',
            'SpeedGbps',
            'MemorySizeMiB',
            'Status',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'RAID volumes',
          rows: data?.volumes ?? <Map<String, Object?>>[],
          preferredColumns: const <String>[
            'Name',
            'VolumeName',
            'VolumeRaidLevel',
            'CapacityBytes',
            'AccessPolicy',
            'Status',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Физические диски',
          rows: data?.drives ?? <Map<String, Object?>>[],
          preferredColumns: const <String>[
            'Name',
            'Manufacturer',
            'Model',
            'MediaType',
            'Protocol',
            'CapacityBytes',
            'TemperatureCelsius',
            'HoursOfPoweredUp',
            'FirmwareStatus',
            'FailurePredicted',
            'Status',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Сетевые порты',
          rows: data?.ethernetInterfaces ?? <Map<String, Object?>>[],
          preferredColumns: const <String>[
            'Id',
            'MACAddress',
            'SpeedMbps',
            'LinkStatus',
            'InterfaceEnabled',
            'Status',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Сетевые адаптеры',
          rows: data?.networkAdapters ?? <Map<String, Object?>>[],
          preferredColumns: const <String>[
            'Name',
            'Manufacturer',
            'Model',
            'Status',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Firmware inventory',
          rows: data?.firmware ?? <Map<String, Object?>>[],
          preferredColumns: const <String>[
            'Name',
            'Version',
            'Updateable',
            'Status',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Последние события BMC',
          rows: data?.logEntries ?? <Map<String, Object?>>[],
          preferredColumns: const <String>[
            'Created',
            'normalizedSeverity',
            'Message',
            'MessageId',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Платы',
          rows: data?.boards ?? <Map<String, Object?>>[],
          preferredColumns: const <String>[
            'Name',
            'Manufacturer',
            'Model',
            'Status',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'BMC discrete sensors (raw)',
          rows: data?.discreteSensors ?? <Map<String, Object?>>[],
          preferredColumns: const <String>['Name', 'Status'],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'BMC threshold sensors (raw)',
          rows: data?.thresholdSensors ?? <Map<String, Object?>>[],
          preferredColumns: const <String>[
            'Name',
            'ReadingValue',
            'ReadingUnits',
            'Status',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'BMC controller',
          rows: data?.managers ?? <Map<String, Object?>>[],
          preferredColumns: const <String>[
            'Name',
            'Model',
            'FirmwareVersion',
            'DateTime',
            'DateTimeLocalOffset',
            'Status',
          ],
        ),
        if (data?.errors.isNotEmpty == true) ...<Widget>[
          const SizedBox(height: 16),
          GenericDataSection(
            title: 'Redfish API errors',
            rows: data!.errors,
            preferredColumns: const <String>[
              'operation',
              'path',
              'statusCode',
              'message',
            ],
          ),
        ],
      ],
    );
  }
}

class _ProxmoxVeSections extends StatelessWidget {
  const _ProxmoxVeSections({required this.sourceId, required this.data});

  final String sourceId;
  final ProxmoxVeData? data;

  @override
  Widget build(BuildContext context) {
    final nodes = data?.nodes ?? <Map<String, Object?>>[];
    final resources = data?.resources ?? <Map<String, Object?>>[];
    final vmResources = data?.vmResources ?? <Map<String, Object?>>[];
    final guests = (vmResources.isNotEmpty ? vmResources : resources)
        .where(
          (Map<String, Object?> resource) =>
              resource['type'] == 'qemu' || resource['type'] == 'lxc',
        )
        .toList();

    return Column(
      children: <Widget>[
        _NodeOverview(sourceId: sourceId, nodes: nodes, guests: guests),
        const SizedBox(height: 16),
        _GuestList(sourceId: sourceId, guests: guests),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Raw nodes',
          rows: nodes,
          preferredColumns: const <String>[
            'node',
            'status',
            'cpu',
            'mem',
            'maxmem',
            'uptime',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Raw resources',
          rows: resources,
          preferredColumns: const <String>[
            'type',
            'vmid',
            'name',
            'node',
            'status',
            'cpu',
            'mem',
            'maxmem',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Storage',
          rows: data?.storageResources ?? <Map<String, Object?>>[],
          preferredColumns: const <String>[
            'storage',
            'node',
            'status',
            'disk',
            'maxdisk',
            'plugintype',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Storage config и PBS namespaces',
          rows: data?.storageConfig ?? <Map<String, Object?>>[],
          preferredColumns: const <String>[
            'storage',
            'type',
            'server',
            'datastore',
            'namespace',
            'nodes',
            'content',
            'disable',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Последние задачи',
          rows: data?.tasks ?? <Map<String, Object?>>[],
          preferredColumns: const <String>[
            'type',
            'node',
            'user',
            'status',
            'starttime',
            'endtime',
          ],
        ),
      ],
    );
  }
}

class _NodeOverview extends StatelessWidget {
  const _NodeOverview({
    required this.sourceId,
    required this.nodes,
    required this.guests,
  });

  final String sourceId;
  final List<Map<String, Object?>> nodes;
  final List<Map<String, Object?>> guests;

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) {
      return const EmptyCardState(
        icon: Icons.hub_outlined,
        text: 'Ноды пока не найдены.',
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final columns = constraints.maxWidth > 1100
            ? 3
            : constraints.maxWidth > 720
            ? 2
            : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: nodes.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 190,
          ),
          itemBuilder: (BuildContext context, int index) {
            final node = nodes[index];
            final nodeName = node['node']?.toString() ?? '';
            final nodeGuests = guests
                .where(
                  (Map<String, Object?> guest) =>
                      guest['node']?.toString() == nodeName,
                )
                .length;
            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: nodeName.isEmpty
                  ? null
                  : () => context.go(
                      '/sources/$sourceId/nodes/${Uri.encodeComponent(nodeName)}',
                    ),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Icon(
                          Icons.hub_outlined,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            nodeName,
                            style: Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        StatusChip(status: node['status']?.toString() ?? 'new'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    UsageBar(
                      value: _ratio(node['cpu']),
                      label: 'CPU ${formatPercent(_ratio(node['cpu']))}',
                    ),
                    const SizedBox(height: 12),
                    UsageBar(
                      value: _ratioPair(node['mem'], node['maxmem']),
                      label:
                          'RAM ${formatPercent(_ratioPair(node['mem'], node['maxmem']))}',
                    ),
                    const Spacer(),
                    Row(
                      children: <Widget>[
                        Text(
                          'VM/LXC: $nodeGuests',
                          style: const TextStyle(color: AppColors.mutedInk),
                        ),
                        const Spacer(),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _GuestList extends StatefulWidget {
  const _GuestList({required this.sourceId, required this.guests});

  final String sourceId;
  final List<Map<String, Object?>> guests;

  @override
  State<_GuestList> createState() => _GuestListState();
}

class _GuestListState extends State<_GuestList> {
  int _sortColumnIndex = 3;
  bool _sortAscending = true;

  @override
  Widget build(BuildContext context) {
    if (widget.guests.isEmpty) {
      return const EmptyCardState(
        icon: Icons.memory_outlined,
        text: 'VM/LXC пока не найдены.',
      );
    }

    const columns = <String>[
      'type',
      'vmid',
      'name',
      'node',
      'status',
      'cpu',
      'mem',
    ];
    final sortedGuests = sortTableRows(
      rows: widget.guests,
      column: columns[_sortColumnIndex],
      ascending: _sortAscending,
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('VM/LXC', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              sortColumnIndex: _sortColumnIndex,
              sortAscending: _sortAscending,
              columns: columns.indexed
                  .map(
                    ((int, String) entry) => DataColumn(
                      label: Text(entry.$2),
                      onSort: (int columnIndex, bool ascending) {
                        setState(() {
                          _sortColumnIndex = columnIndex;
                          _sortAscending = ascending;
                        });
                      },
                    ),
                  )
                  .toList(),
              rows: sortedGuests.map((Map<String, Object?> guest) {
                final guestType = guest['type']?.toString() ?? '';
                final node = guest['node']?.toString() ?? '';
                final vmid = guest['vmid']?.toString() ?? '';
                final name = guest['name']?.toString() ?? '';
                return DataRow(
                  onSelectChanged: (_) {
                    final query = name.isEmpty
                        ? ''
                        : '?name=${Uri.encodeQueryComponent(name)}';
                    context.go(
                      '/sources/${widget.sourceId}/guests/$guestType/'
                      '${Uri.encodeComponent(node)}/$vmid$query',
                    );
                  },
                  cells: <DataCell>[
                    DataCell(Text(guestType)),
                    DataCell(Text(vmid)),
                    DataCell(Text(name)),
                    DataCell(Text(node)),
                    DataCell(
                      StatusChip(status: guest['status']?.toString() ?? 'new'),
                    ),
                    DataCell(Text(formatPercent(_ratio(guest['cpu'])))),
                    DataCell(Text(_usedOfTotal(guest['mem'], guest['maxmem']))),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProxmoxBackupSections extends StatelessWidget {
  const _ProxmoxBackupSections({required this.data});

  final ProxmoxBackupData? data;

  @override
  Widget build(BuildContext context) {
    final snapshots = data?.snapshots ?? <Map<String, Object?>>[];
    final report = analyzeBackupCoverage(snapshots);
    final coverageRows = report.guests.map((guest) {
      return <String, Object?>{
        'guest': guest.displayName,
        'namespace': guest.namespace.isEmpty ? 'root' : guest.namespace,
        'backup-type': guest.backupType,
        'backup-id': guest.backupId,
        'snapshots': guest.count,
        'last-backup': _formatDateTime(guest.latestBackupAt),
        'avg-interval': _formatDuration(guest.averageInterval),
        'total-size': formatBytes(guest.totalSizeBytes),
        'datastores': guest.datastores.join(', '),
      };
    }).toList();

    return Column(
      children: <Widget>[
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            MetricCard(
              label: 'VM/LXC с backup',
              value: report.protectedGuests.toString(),
              icon: Icons.verified_outlined,
            ),
            MetricCard(
              label: 'Snapshots',
              value: report.totalSnapshots.toString(),
              icon: Icons.inventory_2_outlined,
            ),
            MetricCard(
              label: 'Datastores',
              value: (data?.datastores.length ?? 0).toString(),
              icon: Icons.storage_outlined,
            ),
            MetricCard(
              label: 'Объем snapshots',
              value: formatBytes(report.totalSizeBytes),
              icon: Icons.data_usage_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _BackupActivityChart(days: report.dailyCounts),
        const SizedBox(height: 16),
        _BackupTopGuestsChart(guests: report.guests),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'VM/LXC backup coverage',
          rows: coverageRows,
          preferredColumns: const <String>[
            'guest',
            'namespace',
            'snapshots',
            'last-backup',
            'avg-interval',
            'total-size',
            'datastores',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Datastores',
          rows: data?.datastoreUsage.isNotEmpty == true
              ? data!.datastoreUsage
              : data?.datastores ?? <Map<String, Object?>>[],
          preferredColumns: const <String>[
            'store',
            'used',
            'avail',
            'total',
            'comment',
            'gc-status',
            'maintenance-mode',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Datastore namespaces',
          rows: data?.namespaces ?? <Map<String, Object?>>[],
          preferredColumns: const <String>['datastore', 'namespace'],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Verify jobs',
          rows: data?.verifyJobs ?? <Map<String, Object?>>[],
          preferredColumns: const <String>[
            'id',
            'store',
            'ns',
            'schedule',
            'comment',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Prune / GC jobs',
          rows: <Map<String, Object?>>[
            ...?data?.pruneJobs.map(
              (row) => <String, Object?>{'job-type': 'prune', ...row},
            ),
            ...?data?.gcJobs.map(
              (row) => <String, Object?>{'job-type': 'gc', ...row},
            ),
          ],
          preferredColumns: const <String>[
            'job-type',
            'id',
            'store',
            'ns',
            'schedule',
            'comment',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Sync jobs',
          rows: data?.syncJobs ?? <Map<String, Object?>>[],
          preferredColumns: const <String>[
            'id',
            'store',
            'ns',
            'schedule',
            'remote',
            'remote-store',
            'remote-ns',
            'comment',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Snapshots',
          rows: data?.snapshots ?? <Map<String, Object?>>[],
          preferredColumns: const <String>[
            'datastore',
            'namespace',
            'backup-type',
            'backup-id',
            'backup-time',
            'size',
            'verification',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Задачи PBS',
          rows: data?.tasks ?? <Map<String, Object?>>[],
          preferredColumns: const <String>[
            'worker_type',
            'worker_id',
            'user',
            'status',
            'starttime',
            'endtime',
          ],
        ),
      ],
    );
  }
}

class _BackupActivityChart extends StatelessWidget {
  const _BackupActivityChart({required this.days});

  final List<BackupDayCount> days;

  @override
  Widget build(BuildContext context) {
    final visibleDays = days.length > 14
        ? days.sublist(days.length - 14)
        : days;
    final maxCount = visibleDays.fold<int>(
      0,
      (max, day) => day.count > max ? day.count : max,
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Backup активность по дням',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (visibleDays.isEmpty)
            const EmptyState(
              icon: Icons.bar_chart_outlined,
              text: 'Snapshots пока не найдены.',
            )
          else
            ...visibleDays.map(
              (day) => _HorizontalBarRow(
                label: _formatDay(day.day),
                value: day.count,
                ratio: maxCount == 0 ? 0 : day.count / maxCount,
              ),
            ),
        ],
      ),
    );
  }
}

class _BackupTopGuestsChart extends StatelessWidget {
  const _BackupTopGuestsChart({required this.guests});

  final List<BackupGuestReport> guests;

  @override
  Widget build(BuildContext context) {
    final topGuests = List<BackupGuestReport>.from(guests)
      ..sort((a, b) => b.count.compareTo(a.count));
    final visibleGuests = topGuests.take(10).toList();
    final maxCount = visibleGuests.fold<int>(
      0,
      (max, guest) => guest.count > max ? guest.count : max,
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Топ VM/LXC по количеству backups',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (visibleGuests.isEmpty)
            const EmptyState(
              icon: Icons.bar_chart_outlined,
              text: 'Snapshots пока не найдены.',
            )
          else
            ...visibleGuests.map(
              (guest) => _HorizontalBarRow(
                label: guest.displayName,
                value: guest.count,
                ratio: maxCount == 0 ? 0 : guest.count / maxCount,
              ),
            ),
        ],
      ),
    );
  }
}

class _HorizontalBarRow extends StatelessWidget {
  const _HorizontalBarRow({
    required this.label,
    required this.value,
    required this.ratio,
  });

  final String label;
  final int value;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 120,
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 10,
                value: ratio.clamp(0, 1).toDouble(),
                backgroundColor: AppColors.surfaceAlt,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 48,
            child: Text(
              value.toString(),
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _iconForSource(String type) {
  return switch (type) {
    'proxmox_ve' => Icons.memory_outlined,
    'proxmox_backup' => Icons.backup_outlined,
    _ => Icons.developer_board_outlined,
  };
}

double _ratio(Object? value) {
  final parsed = double.tryParse(value?.toString() ?? '');
  if (parsed == null || parsed.isNaN || parsed.isInfinite) {
    return 0;
  }
  return parsed.clamp(0, 1).toDouble();
}

double _ratioPair(Object? current, Object? max) {
  final currentValue = double.tryParse(current?.toString() ?? '');
  final maxValue = double.tryParse(max?.toString() ?? '');
  if (currentValue == null || maxValue == null || maxValue <= 0) {
    return 0;
  }
  return (currentValue / maxValue).clamp(0, 1).toDouble();
}

String _usedOfTotal(Object? used, Object? total) {
  final usedText = formatBytes(used);
  final totalText = formatBytes(total);
  if (usedText.isEmpty && totalText.isEmpty) {
    return '';
  }
  return '$usedText / $totalText';
}

String _formatDateTime(DateTime? value) {
  if (value == null) {
    return '';
  }
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String _formatDay(DateTime value) {
  final local = value.toLocal();
  return '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

String _formatDuration(Duration? value) {
  if (value == null) {
    return '';
  }
  final days = value.inDays;
  final hours = value.inHours.remainder(24);
  if (days > 0) {
    return '${days}d ${hours}h';
  }
  if (value.inHours > 0) {
    return '${value.inHours}h';
  }
  return '${value.inMinutes}m';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final Iterator<T> iterator = this.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    return iterator.current;
  }
}
