import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/features/sources/data/source_data_repository.dart';
import 'package:frontend/features/sources/domain/source.dart';
import 'package:frontend/features/sources/presentation/cubit/sources_cubit.dart';
import 'package:frontend/shared/formatters/value_formatters.dart';
import 'package:frontend/shared/tables/table_sorting.dart';
import 'package:frontend/shared/widgets/app_card.dart';
import 'package:frontend/shared/widgets/async_state_view.dart';
import 'package:frontend/shared/widgets/generic_data_section.dart';
import 'package:frontend/shared/widgets/metric_card.dart';
import 'package:frontend/shared/widgets/page_header.dart';
import 'package:frontend/shared/widgets/status_chip.dart';
import 'package:frontend/shared/widgets/usage_bar.dart';
import 'package:go_router/go_router.dart';

class NodeDetailPage extends StatelessWidget {
  const NodeDetailPage({required this.sourceId, required this.node, super.key});

  final String sourceId;
  final String node;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SourcesCubit, SourcesState>(
      builder: (BuildContext context, SourcesState sourcesState) {
        final Source? source = sourcesState.items
            .where((Source source) => source.id == sourceId)
            .firstOrNull;

        if (source == null) {
          return const EmptyCardState(
            icon: Icons.hub_outlined,
            text: 'Источник не найден.',
          );
        }

        return FutureBuilder<ProxmoxVeData>(
          future: SourceDataRepository(
            context.read<ApiClient>(),
          ).loadProxmoxVe(sourceId),
          builder:
              (BuildContext context, AsyncSnapshot<ProxmoxVeData> snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LoadingStateView();
                }
                if (snapshot.hasError) {
                  return ErrorStateView(message: snapshot.error.toString());
                }
                final data = snapshot.data;
                if (data == null) {
                  return const EmptyCardState(
                    icon: Icons.hub_outlined,
                    text: 'Данных по ноде пока нет.',
                  );
                }
                return _NodeDetailContent(
                  source: source,
                  node: node,
                  data: data,
                );
              },
        );
      },
    );
  }
}

class _NodeDetailContent extends StatelessWidget {
  const _NodeDetailContent({
    required this.source,
    required this.node,
    required this.data,
  });

  final Source source;
  final String node;
  final ProxmoxVeData data;

  @override
  Widget build(BuildContext context) {
    final nodeData = data.nodes.where(_sameNode).firstOrNull;
    if (nodeData == null) {
      return const EmptyCardState(
        icon: Icons.hub_outlined,
        text: 'Нода не найдена в ответе Proxmox.',
      );
    }

    final guests = data.vmResources
        .where(
          (Map<String, Object?> guest) =>
              guest['node']?.toString() == node &&
              (guest['type'] == 'qemu' || guest['type'] == 'lxc'),
        )
        .toList();
    final storage = data.storageResources
        .where((Map<String, Object?> item) => item['node']?.toString() == node)
        .toList();
    final tasks = data.tasks
        .where((Map<String, Object?> item) => item['node']?.toString() == node)
        .toList();
    final cpu = _ratio(nodeData['cpu']);
    final mem = _ratioPair(nodeData['mem'], nodeData['maxmem']);
    final disk = _ratioPair(nodeData['disk'], nodeData['maxdisk']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        PageHeader(
          leading: OutlinedButton.icon(
            onPressed: () => context.go('/sources/${source.id}'),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Назад'),
          ),
          title: node,
          subtitle: source.name,
          trailing: StatusChip(status: nodeData['status']?.toString() ?? 'new'),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            MetricCard(
              label: 'CPU',
              value: formatPercent(cpu),
              icon: Icons.speed,
            ),
            MetricCard(
              label: 'RAM',
              value: formatPercent(mem),
              icon: Icons.memory_outlined,
            ),
            MetricCard(
              label: 'Disk',
              value: formatPercent(disk),
              icon: Icons.storage_outlined,
            ),
            MetricCard(
              label: 'VM/LXC',
              value: guests.length.toString(),
              icon: Icons.developer_board_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Нагрузка', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              _UsageRow(label: 'CPU', value: cpu),
              const SizedBox(height: 12),
              _UsageRow(label: 'RAM', value: mem),
              const SizedBox(height: 12),
              _UsageRow(label: 'Disk', value: disk),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _NodeGuestTable(sourceId: source.id, node: node, guests: guests),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Storage ноды',
          rows: storage,
          preferredColumns: const <String>[
            'storage',
            'status',
            'disk',
            'maxdisk',
            'plugintype',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Последние задачи ноды',
          rows: tasks,
          preferredColumns: const <String>[
            'type',
            'user',
            'status',
            'starttime',
            'endtime',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Raw node data',
          rows: <Map<String, Object?>>[nodeData],
          preferredColumns: const <String>[
            'node',
            'status',
            'cpu',
            'mem',
            'maxmem',
            'disk',
            'maxdisk',
            'uptime',
          ],
        ),
      ],
    );
  }

  bool _sameNode(Map<String, Object?> item) => item['node']?.toString() == node;
}

class _NodeGuestTable extends StatefulWidget {
  const _NodeGuestTable({
    required this.sourceId,
    required this.node,
    required this.guests,
  });

  final String sourceId;
  final String node;
  final List<Map<String, Object?>> guests;

  @override
  State<_NodeGuestTable> createState() => _NodeGuestTableState();
}

class _NodeGuestTableState extends State<_NodeGuestTable> {
  int _sortColumnIndex = 1;
  bool _sortAscending = true;

  @override
  Widget build(BuildContext context) {
    if (widget.guests.isEmpty) {
      return const EmptyCardState(
        icon: Icons.memory_outlined,
        text: 'На этой ноде VM/LXC пока не найдены.',
      );
    }

    const columns = <String>['type', 'vmid', 'name', 'status', 'cpu', 'mem'];
    final sortedGuests = sortTableRows(
      rows: widget.guests,
      column: columns[_sortColumnIndex],
      ascending: _sortAscending,
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'VM/LXC на ноде',
            style: Theme.of(context).textTheme.titleMedium,
          ),
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
                final vmid = guest['vmid']?.toString() ?? '';
                final name = guest['name']?.toString() ?? '';
                return DataRow(
                  onSelectChanged: (_) {
                    final query = name.isEmpty
                        ? ''
                        : '?name=${Uri.encodeQueryComponent(name)}';
                    context.go(
                      '/sources/${widget.sourceId}/guests/$guestType/'
                      '${Uri.encodeComponent(widget.node)}/$vmid$query',
                    );
                  },
                  cells: <DataCell>[
                    DataCell(Text(guestType)),
                    DataCell(Text(vmid)),
                    DataCell(Text(name)),
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

class _UsageRow extends StatelessWidget {
  const _UsageRow({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 64,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(
          child: UsageBar(value: value, label: formatPercent(value)),
        ),
      ],
    );
  }
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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    return iterator.current;
  }
}
