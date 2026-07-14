import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/core/design/app_colors.dart';
import 'package:frontend/features/sources/data/source_data_repository.dart';
import 'package:frontend/features/sources/domain/backup_analysis.dart';
import 'package:frontend/features/sources/domain/source.dart';
import 'package:frontend/features/sources/presentation/cubit/sources_cubit.dart';
import 'package:frontend/shared/formatters/value_formatters.dart';
import 'package:frontend/shared/widgets/app_card.dart';
import 'package:frontend/shared/widgets/async_state_view.dart';
import 'package:frontend/shared/widgets/generic_data_section.dart';
import 'package:frontend/shared/widgets/metric_card.dart';
import 'package:frontend/shared/widgets/page_header.dart';
import 'package:frontend/shared/widgets/status_chip.dart';
import 'package:frontend/shared/widgets/usage_bar.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class GuestDetailPage extends StatelessWidget {
  const GuestDetailPage({
    required this.sourceId,
    required this.node,
    required this.guestType,
    required this.vmid,
    required this.name,
    super.key,
  });

  final String sourceId;
  final String node;
  final String guestType;
  final String vmid;
  final String name;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SourcesCubit, SourcesState>(
      builder: (BuildContext context, SourcesState sourcesState) {
        final Source? source = sourcesState.items
            .where((Source source) => source.id == sourceId)
            .firstOrNull;

        if (source == null) {
          return const EmptyCardState(
            icon: Icons.memory_outlined,
            text: 'Источник не найден.',
          );
        }

        return FutureBuilder<_GuestDetailData>(
          future: _load(context, sourcesState.items),
          builder:
              (BuildContext context, AsyncSnapshot<_GuestDetailData> snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LoadingStateView();
                }
                if (snapshot.hasError) {
                  return ErrorStateView(message: snapshot.error.toString());
                }
                final data = snapshot.data;
                if (data == null) {
                  return const EmptyCardState(
                    icon: Icons.memory_outlined,
                    text: 'Данных по VM/LXC пока нет.',
                  );
                }

                return _GuestDetailContent(
                  source: source,
                  node: node,
                  guestType: guestType,
                  vmid: vmid,
                  name: name,
                  data: data,
                );
              },
        );
      },
    );
  }

  Future<_GuestDetailData> _load(
    BuildContext context,
    List<Source> sources,
  ) async {
    final repository = SourceDataRepository(context.read<ApiClient>());
    final currentSource = sources
        .where((Source source) => source.id == sourceId)
        .firstOrNull;
    final storageConfig = await repository.loadStorageConfig(sourceId);
    final backupNamespaces = backupNamespacesFromStorageConfig(
      storageConfig,
      manualNamespace: currentSource?.backupNamespace ?? '',
    );
    final status = await repository.loadGuestStatus(
      sourceId: sourceId,
      node: node,
      guestType: guestType,
      vmid: vmid,
    );
    final interfaces = await repository.loadGuestInterfaces(
      sourceId: sourceId,
      node: node,
      guestType: guestType,
      vmid: vmid,
    );
    final snapshots = <Map<String, Object?>>[];
    for (final source in sources.where(
      (Source source) => source.type == 'proxmox_backup',
    )) {
      final backupData = await repository.loadProxmoxBackup(source.id);
      snapshots.addAll(
        backupData.snapshots.map(
          (Map<String, Object?> snapshot) => <String, Object?>{
            'backupSource': source.name,
            ...snapshot,
          },
        ),
      );
    }
    return _GuestDetailData(
      status: status,
      interfaces: interfaces,
      backupSummary: analyzeGuestBackups(
        guestType: guestType,
        vmid: vmid,
        guestName: name,
        backupNamespace: currentSource?.backupNamespace ?? '',
        backupNamespaces: backupNamespaces.isEmpty ? null : backupNamespaces,
        snapshots: snapshots,
      ),
    );
  }
}

class _GuestDetailContent extends StatelessWidget {
  const _GuestDetailContent({
    required this.source,
    required this.node,
    required this.guestType,
    required this.vmid,
    required this.name,
    required this.data,
  });

  final Source source;
  final String node;
  final String guestType;
  final String vmid;
  final String name;
  final _GuestDetailData data;

  @override
  Widget build(BuildContext context) {
    final status = data.status;
    final cpu = _ratio(status['cpu']);
    final mem = _ratioPair(status['mem'], status['maxmem']);
    final disk = _ratioPair(status['disk'], status['maxdisk']);
    final backupSummary = data.backupSummary;
    final ipAddress = _guestIpAddress(data.interfaces);
    final proxmoxGuestUrl = _proxmoxGuestUrl(source.baseUrl, guestType, vmid);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        PageHeader(
          leading: OutlinedButton.icon(
            onPressed: () => context.go(
              '/sources/${source.id}/nodes/${Uri.encodeComponent(node)}',
            ),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Назад'),
          ),
          title: name.isEmpty ? '$guestType/$vmid' : name,
          subtitle: '${source.name} / $node / $guestType $vmid',
          trailing: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: proxmoxGuestUrl == null
                    ? null
                    : () => launchUrl(
                        proxmoxGuestUrl,
                        mode: LaunchMode.externalApplication,
                      ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Открыть в Proxmox'),
              ),
              StatusChip(status: status['status']?.toString() ?? 'new'),
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
              icon: Icons.speed_outlined,
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
              label: 'Backup',
              value: backupStatusLabel(backupSummary.status),
              icon: Icons.backup_outlined,
            ),
            MetricCard(label: 'IP', value: ipAddress, icon: Icons.lan_outlined),
          ],
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Ресурсы', style: Theme.of(context).textTheme.titleMedium),
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
        _BackupSummaryCard(summary: backupSummary),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Raw status',
          rows: <Map<String, Object?>>[status],
          preferredColumns: const <String>[
            'status',
            'name',
            'uptime',
            'cpu',
            'mem',
            'maxmem',
            'disk',
            'maxdisk',
            'netin',
            'netout',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Network interfaces',
          rows: data.interfaces,
          preferredColumns: const <String>[
            'name',
            'hardware-address',
            'ip-addresses',
            'iface',
            'address',
            'inet',
            'inet6',
          ],
        ),
      ],
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

class _BackupSummaryCard extends StatelessWidget {
  const _BackupSummaryCard({required this.summary});

  final GuestBackupSummary summary;

  @override
  Widget build(BuildContext context) {
    final latest = summary.latestBackupAt;
    final latestText = latest == null ? 'backup не найден' : _localDate(latest);
    return Column(
      children: <Widget>[
        AppCard(
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Backup состояние',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      latestText,
                      style: const TextStyle(color: AppColors.mutedInk),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      backupStatusDescription(summary.status),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.mutedInk,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      backupMatchDescription(summary.matchQuality),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: summary.matchQuality == BackupMatchQuality.idOnly
                            ? AppColors.warning
                            : summary.matchQuality ==
                                  BackupMatchQuality.nameMismatch
                            ? AppColors.danger
                            : AppColors.mutedInk,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              StatusChip(status: backupStatusLabel(summary.status)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Найденные snapshots',
          rows: summary.matches,
          preferredColumns: const <String>[
            'backupSource',
            'datastore',
            'namespace',
            'backup-type',
            'backup-id',
            'backup-time',
            'size',
          ],
        ),
      ],
    );
  }
}

class _GuestDetailData {
  const _GuestDetailData({
    required this.status,
    required this.interfaces,
    required this.backupSummary,
  });

  final Map<String, Object?> status;
  final List<Map<String, Object?>> interfaces;
  final GuestBackupSummary backupSummary;
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

String _localDate(DateTime value) {
  final local = value.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String _guestIpAddress(List<Map<String, Object?>> interfaces) {
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

Uri? _proxmoxGuestUrl(String baseUrl, String guestType, String vmid) {
  final uri = Uri.tryParse(baseUrl);
  if (uri == null || vmid.isEmpty) {
    return null;
  }
  final proxmoxType = guestType == 'lxc' ? 'lxc' : 'qemu';
  final resource = Uri.encodeComponent('$proxmoxType/$vmid');
  return uri.replace(fragment: 'v1:0:=$resource:4:::::::21');
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
