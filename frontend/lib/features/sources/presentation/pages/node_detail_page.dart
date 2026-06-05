import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/features/sources/data/source_data_repository.dart';
import 'package:frontend/features/sources/domain/backup_analysis.dart';
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
import 'package:url_launcher/url_launcher.dart';

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

        return FutureBuilder<_NodeDetailData>(
          future: _loadNodeDetail(
            context: context,
            source: source,
            sources: sourcesState.items,
            node: node,
          ),
          builder:
              (BuildContext context, AsyncSnapshot<_NodeDetailData> snapshot) {
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
                  data: data.proxmoxVe,
                  nodeVersion: data.nodeVersion,
                  nodeNetwork: data.nodeNetwork,
                  guestInterfaces: data.guestInterfaces,
                  backupSnapshots: data.backupSnapshots,
                );
              },
        );
      },
    );
  }

  Future<_NodeDetailData> _loadNodeDetail({
    required BuildContext context,
    required Source source,
    required List<Source> sources,
    required String node,
  }) async {
    final repository = SourceDataRepository(context.read<ApiClient>());
    final pveData = await repository.loadProxmoxVe(source.id);
    final nodeVersion = await repository.loadNodeVersion(
      sourceId: source.id,
      node: node,
    );
    final nodeNetwork = await repository.loadNodeNetwork(
      sourceId: source.id,
      node: node,
    );
    final backupSnapshots = <Map<String, Object?>>[];
    for (final pbsSource in sources.where(
      (Source item) => item.type == 'proxmox_backup',
    )) {
      final pbsData = await repository.loadProxmoxBackup(pbsSource.id);
      backupSnapshots.addAll(
        pbsData.snapshots.map(
          (snapshot) => <String, Object?>{
            'backupSource': pbsSource.name,
            ...snapshot,
          },
        ),
      );
    }

    final guests = pveData.vmResources.where((Map<String, Object?> guest) {
      return guest['node']?.toString() == node &&
          (guest['type'] == 'qemu' || guest['type'] == 'lxc');
    });
    final guestInterfaces = <String, List<Map<String, Object?>>>{};
    await Future.wait(
      guests.map((guest) async {
        final guestType = guest['type']?.toString() ?? '';
        final vmid = guest['vmid']?.toString() ?? '';
        if (guestType.isEmpty || vmid.isEmpty) {
          return;
        }
        guestInterfaces['$guestType/$vmid'] = await repository
            .loadGuestInterfaces(
              sourceId: source.id,
              node: node,
              guestType: guestType,
              vmid: vmid,
            );
      }),
    );

    return _NodeDetailData(
      proxmoxVe: pveData,
      nodeVersion: nodeVersion,
      nodeNetwork: nodeNetwork,
      guestInterfaces: guestInterfaces,
      backupSnapshots: backupSnapshots,
    );
  }
}

class _NodeDetailContent extends StatelessWidget {
  const _NodeDetailContent({
    required this.source,
    required this.node,
    required this.data,
    required this.nodeVersion,
    required this.nodeNetwork,
    required this.guestInterfaces,
    required this.backupSnapshots,
  });

  final Source source;
  final String node;
  final ProxmoxVeData data;
  final Map<String, Object?> nodeVersion;
  final List<Map<String, Object?>> nodeNetwork;
  final Map<String, List<Map<String, Object?>>> guestInterfaces;
  final List<Map<String, Object?>> backupSnapshots;

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
    final version = _nodeVersionLabel(nodeVersion);
    final nodeIp = _nodeIpAddress(nodeNetwork);
    final proxmoxNodeUrl = _proxmoxNodeUrl(source.baseUrl, node);

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
          trailing: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: proxmoxNodeUrl == null
                    ? null
                    : () => launchUrl(
                        proxmoxNodeUrl,
                        mode: LaunchMode.externalApplication,
                      ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Открыть в Proxmox'),
              ),
              StatusChip(status: nodeData['status']?.toString() ?? 'new'),
            ],
          ),
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
            MetricCard(
              label: 'PVE version',
              value: version,
              icon: Icons.info_outline,
            ),
            MetricCard(
              label: 'Node IP',
              value: nodeIp.isEmpty ? '-' : nodeIp,
              icon: Icons.lan_outlined,
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
        _NodeGuestTable(
          sourceId: source.id,
          node: node,
          guests: guests,
          guestInterfaces: guestInterfaces,
          backupSnapshots: backupSnapshots,
        ),
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
            'pveversion',
            'release',
          ],
        ),
      ],
    );
  }

  bool _sameNode(Map<String, Object?> item) => item['node']?.toString() == node;
}

class _NodeDetailData {
  const _NodeDetailData({
    required this.proxmoxVe,
    required this.nodeVersion,
    required this.nodeNetwork,
    required this.guestInterfaces,
    required this.backupSnapshots,
  });

  final ProxmoxVeData proxmoxVe;
  final Map<String, Object?> nodeVersion;
  final List<Map<String, Object?>> nodeNetwork;
  final Map<String, List<Map<String, Object?>>> guestInterfaces;
  final List<Map<String, Object?>> backupSnapshots;
}

class _NodeGuestTable extends StatefulWidget {
  const _NodeGuestTable({
    required this.sourceId,
    required this.node,
    required this.guests,
    required this.guestInterfaces,
    required this.backupSnapshots,
  });

  final String sourceId;
  final String node;
  final List<Map<String, Object?>> guests;
  final Map<String, List<Map<String, Object?>>> guestInterfaces;
  final List<Map<String, Object?>> backupSnapshots;

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

    final enrichedGuests = widget.guests.map((guest) {
      final guestType = guest['type']?.toString() ?? '';
      final vmid = guest['vmid']?.toString() ?? '';
      final backup = analyzeGuestBackups(
        guestType: guestType,
        vmid: vmid,
        snapshots: widget.backupSnapshots,
      );
      return <String, Object?>{
        ...guest,
        'ip': _guestIpAddress(widget.guestInterfaces['$guestType/$vmid']),
        'lastBackupAt': backup.latestBackupAt,
      };
    }).toList();
    const columns = <String>[
      'type',
      'vmid',
      'name',
      'status',
      'ip',
      'cpu',
      'mem',
      'lastBackupAt',
    ];
    final sortedGuests = sortTableRows(
      rows: enrichedGuests,
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
                    DataCell(Text(guest['ip']?.toString() ?? '-')),
                    DataCell(Text(formatPercent(_ratio(guest['cpu'])))),
                    DataCell(Text(_usedOfTotal(guest['mem'], guest['maxmem']))),
                    DataCell(Text(_formatDateTime(guest['lastBackupAt']))),
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

String _nodeVersionLabel(Map<String, Object?> version) {
  final pveVersion = version['version']?.toString() ?? '';
  final release = version['release']?.toString() ?? '';
  if (pveVersion.isEmpty && release.isEmpty) {
    return '-';
  }
  if (release.isEmpty || pveVersion.contains(release)) {
    return pveVersion;
  }
  return '$pveVersion / $release';
}

String _nodeIpAddress(List<Map<String, Object?>> network) {
  final candidates = network.where((item) {
    final address = item['address']?.toString() ?? '';
    final active = item['active']?.toString();
    return _isUsableIp(address) && active != '0';
  }).toList();
  candidates.sort((left, right) {
    final leftIface = left['iface']?.toString() ?? '';
    final rightIface = right['iface']?.toString() ?? '';
    final leftScore = leftIface.startsWith('vmbr') ? 0 : 1;
    final rightScore = rightIface.startsWith('vmbr') ? 0 : 1;
    return leftScore.compareTo(rightScore);
  });
  return candidates.isEmpty ? '' : candidates.first['address'].toString();
}

String _guestIpAddress(List<Map<String, Object?>>? interfaces) {
  if (interfaces == null || interfaces.isEmpty) {
    return '-';
  }
  final addresses = <String>[];
  for (final item in interfaces) {
    final ipAddresses = item['ip-addresses'];
    if (ipAddresses is List) {
      for (final ipAddress in ipAddresses.whereType<Map>()) {
        final address = ipAddress['ip-address']?.toString() ?? '';
        if (_isUsableIp(address)) {
          addresses.add(address);
        }
      }
    }
    for (final key in <String>['address', 'inet', 'inet6']) {
      final value = item[key]?.toString() ?? '';
      final address = value.split('/').first;
      if (_isUsableIp(address)) {
        addresses.add(address);
      }
    }
  }
  return addresses.isEmpty ? '-' : addresses.toSet().take(2).join(', ');
}

bool _isUsableIp(String value) {
  if (value.isEmpty ||
      value == '127.0.0.1' ||
      value == '::1' ||
      value.startsWith('fe80:') ||
      value.startsWith('169.254.')) {
    return false;
  }
  return value.contains('.') || value.contains(':');
}

Uri? _proxmoxNodeUrl(String baseUrl, String node) {
  final uri = Uri.tryParse(baseUrl);
  if (uri == null) {
    return null;
  }
  return uri.replace(fragment: 'v1:0:18:4:::::::${Uri.encodeComponent(node)}');
}

String _formatDateTime(Object? value) {
  if (value == null) {
    return '-';
  }
  final date = value is DateTime
      ? value.toLocal()
      : DateTime.tryParse('$value');
  if (date == null) {
    return '-';
  }
  String two(int input) => input.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} '
      '${two(date.hour)}:${two(date.minute)}';
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
