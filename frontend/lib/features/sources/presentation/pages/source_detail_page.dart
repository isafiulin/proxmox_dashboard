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
import 'package:url_launcher/url_launcher.dart';

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
    final isHardware = source.type == 'redfish' || source.type == 'old_ilo2';
    final controllerUrl = isHardware
        ? _controllerBrowserUri(source.baseUrl)
        : null;
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
              if (isHardware) ...<Widget>[
                OutlinedButton.icon(
                  onPressed: controllerUrl == null
                      ? null
                      : () => launchUrl(
                          controllerUrl,
                          mode: LaunchMode.externalApplication,
                        ),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Открыть iLO/iBMC'),
                ),
                const SizedBox(width: 12),
              ],
              Icon(_iconForSource(source.type), color: AppColors.primary),
              const SizedBox(width: 12),
              StatusChip(status: source.status),
              const SizedBox(width: 8),
              IconButton(
                tooltip: isHardware ? 'Опросить BMC сейчас' : 'Обновить данные',
                onPressed: () => context.read<SourceDetailCubit>().load(
                  source,
                  refreshRedfish: isHardware,
                ),
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
            if (isHardware) {
              return _RedfishSections(data: state.data?.redfish);
            }
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }
}

Uri? _controllerBrowserUri(String baseUrl) {
  final uri = Uri.tryParse(baseUrl.trim());
  if (uri != null && uri.scheme == 'ssh' && uri.host.isNotEmpty) {
    return Uri(scheme: 'https', host: uri.host);
  }
  if (uri == null ||
      !uri.hasAuthority ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return uri;
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
    final leftSections = <Widget>[
      _redfishSection('Процессоры', data?.processors, const <String>[
        'Manufacturer',
        'Model',
        'Socket',
        'TotalCores',
        'TotalThreads',
        'MaxSpeedMHz',
        'Status',
      ]),
      _redfishSection('Память', data?.memory, const <String>[
        'DeviceLocator',
        'Manufacturer',
        'CapacityMiB',
        'OperatingSpeedMhz',
        'MemoryDeviceType',
        'Status',
      ]),
      _redfishSection(
        'RAID-контроллеры',
        data?.storageControllers,
        const <String>[
          'Name',
          'Model',
          'FirmwareVersion',
          'SpeedGbps',
          'MemorySizeMiB',
          'Status',
        ],
      ),
      _redfishSection('RAID volumes', data?.volumes, const <String>[
        'Name',
        'VolumeName',
        'VolumeRaidLevel',
        'CapacityBytes',
        'AccessPolicy',
        'Status',
      ]),
      _redfishSection('Физические диски', data?.drives, const <String>[
        'Name',
        'Manufacturer',
        'Model',
        'MediaType',
        'Protocol',
        'CapacityBytes',
        'TemperatureCelsius',
        'FailurePredicted',
        'Status',
      ]),
      _redfishSection('Firmware inventory', data?.firmware, const <String>[
        'Name',
        'Version',
        'Updateable',
        'Status',
      ]),
    ];
    final rightSections = <Widget>[
      _redfishSection('Температуры', data?.temperatures, const <String>[
        'Name',
        'ReadingCelsius',
        'UpperThresholdCritical',
        'UpperThresholdFatal',
        'Status',
      ]),
      _redfishSection('Вентиляторы', data?.fans, const <String>[
        'Name',
        'Reading',
        'ReadingUnits',
        'Status',
      ]),
      _redfishSection('Блоки питания', data?.powerSupplies, const <String>[
        'Name',
        'Model',
        'LineInputVoltage',
        'PowerInputWatts',
        'PowerOutputWatts',
        'PowerCapacityWatts',
        'Status',
      ]),
      _redfishSection('Последние события BMC', data?.logEntries, const <String>[
        'Created',
        'normalizedSeverity',
        'Message',
        'MessageId',
      ]),
      _redfishSection('Сетевые порты', data?.ethernetInterfaces, const <String>[
        'Id',
        'MACAddress',
        'SpeedMbps',
        'LinkStatus',
        'InterfaceEnabled',
        'Status',
      ]),
      _redfishSection('Сетевые адаптеры', data?.networkAdapters, const <String>[
        'Name',
        'Manufacturer',
        'Model',
        'Status',
      ]),
      _redfishSection('Платы', data?.boards, const <String>[
        'Name',
        'Manufacturer',
        'Model',
        'Status',
      ]),
      _redfishSection(
        'BMC discrete sensors (raw)',
        data?.discreteSensors,
        const <String>['Name', 'Status'],
      ),
      _redfishSection(
        'BMC threshold sensors (raw)',
        data?.thresholdSensors,
        const <String>['Name', 'ReadingValue', 'ReadingUnits', 'Status'],
      ),
      _redfishSection('BMC controller', data?.managers, const <String>[
        'Name',
        'Model',
        'FirmwareVersion',
        'DateTime',
        'DateTimeLocalOffset',
        'Status',
      ]),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppCard(
          child: Row(
            children: <Widget>[
              Icon(
                data?.stale == true
                    ? Icons.warning_amber_outlined
                    : Icons.schedule_outlined,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  data?.stale == true
                      ? 'Показан последний успешный snapshot. Новое обновление BMC завершилось ошибкой.'
                      : data?.collecting == true
                      ? 'Первый сбор BMC выполняется в фоне. Обновите страницу через несколько секунд.'
                      : data?.collectedAt == null
                      ? 'Ожидается первый сбор BMC.'
                      : 'Данные собраны: ${_formatDateTime(data!.collectedAt)}',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _HardwareStatusStrip(
          model: identity['model']?.toString() ?? 'unknown',
          power: system?['PowerState']?.toString() ?? 'unknown',
          health: health ?? 'unknown',
          cpuAndRam:
              '${data?.processors.length ?? 0} CPU · ${(totalMemoryMiB / 1024).toStringAsFixed(0)} GiB',
        ),
        const SizedBox(height: 16),
        _HardwareOverview(data: data),
        const SizedBox(height: 16),
        _TemperatureDashboard(rows: data?.temperatures ?? const []),
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
          collapsible: true,
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
            collapsible: true,
          ),
        ],
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            if (constraints.maxWidth >= 1100) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: _sectionColumn(leftSections)),
                  const SizedBox(width: 16),
                  Expanded(child: _sectionColumn(rightSections)),
                ],
              );
            }
            return _sectionColumn(<Widget>[...leftSections, ...rightSections]);
          },
        ),
      ],
    );
  }
}

class _HardwareStatusStrip extends StatelessWidget {
  const _HardwareStatusStrip({
    required this.model,
    required this.power,
    required this.health,
    required this.cpuAndRam,
  });

  final String model;
  final String power;
  final String health;
  final String cpuAndRam;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _StatusMetric(
        label: 'Модель сервера',
        value: model,
        icon: Icons.dns_outlined,
        color: AppColors.primary,
      ),
      _StatusMetric(
        label: 'Питание',
        value: power,
        icon: Icons.power_settings_new,
        color: power.toLowerCase() == 'on'
            ? AppColors.success
            : AppColors.warning,
      ),
      _StatusMetric(
        label: 'Общее состояние',
        value: health,
        icon: Icons.health_and_safety_outlined,
        color: _healthColor(health),
      ),
      _StatusMetric(
        label: 'Вычислительные ресурсы',
        value: cpuAndRam,
        icon: Icons.memory_outlined,
        color: AppColors.primaryDark,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Row(
            children: <Widget>[
              for (var index = 0; index < cards.length; index += 1) ...[
                if (index > 0) const SizedBox(width: 12),
                Expanded(child: cards[index]),
              ],
            ],
          );
        }
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards
              .map(
                (card) => SizedBox(
                  width: constraints.maxWidth >= 560
                      ? (constraints.maxWidth - 12) / 2
                      : constraints.maxWidth,
                  child: card,
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _StatusMetric extends StatelessWidget {
  const _StatusMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 106,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: color.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(label, style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 8),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(icon, color: Colors.white70, size: 40),
        ],
      ),
    );
  }
}

class _HardwareOverview extends StatelessWidget {
  const _HardwareOverview({required this.data});

  final RedfishData? data;

  @override
  Widget build(BuildContext context) {
    final resources = <Map<String, Object?>>[
      ...?data?.processors,
      ...?data?.memory,
      ...?data?.fans,
      ...?data?.powerSupplies,
      ...?data?.storageControllers,
      ...?data?.drives,
    ];
    final healthy = resources.where((row) => _rowHealth(row) == 'OK').length;
    final ratio = resources.isEmpty ? 0.0 : healthy / resources.length;
    final health = data?.systems.firstOrNull?['Status'];
    final overall = health is Map ? health['Health']?.toString() : null;
    final componentRows = <({String name, IconData icon, String status})>[
      (
        name: 'Процессоры',
        icon: Icons.memory_outlined,
        status: _aggregateHealth(data?.processors),
      ),
      (
        name: 'Память',
        icon: Icons.view_module_outlined,
        status: _aggregateHealth(data?.memory),
      ),
      (
        name: 'Вентиляторы',
        icon: Icons.air,
        status: _aggregateHealth(data?.fans),
      ),
      (
        name: 'Блоки питания',
        icon: Icons.electrical_services_outlined,
        status: _aggregateHealth(data?.powerSupplies),
      ),
      (
        name: 'RAID и диски',
        icon: Icons.storage_outlined,
        status: _aggregateHealth(<Map<String, Object?>>[
          ...?data?.storageControllers,
          ...?data?.drives,
        ]),
      ),
      (
        name: 'Сетевые порты',
        icon: Icons.lan_outlined,
        status: _aggregateHealth(data?.ethernetInterfaces),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final summary = AppCard(
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 118,
                height: 118,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: ratio,
                        strokeWidth: 13,
                        strokeCap: StrokeCap.round,
                        color: _healthColor(overall),
                        backgroundColor: AppColors.border,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          '${(ratio * 100).round()}%',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const Text(
                          'исправно',
                          style: TextStyle(color: AppColors.mutedInk),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Общий статус',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      overall ?? 'unknown',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: _healthColor(overall),
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$healthy из ${resources.length} компонентов без ошибок',
                      style: const TextStyle(color: AppColors.mutedInk),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
        final components = AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Состояние компонентов',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: componentRows.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 230,
                  mainAxisExtent: 66,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemBuilder: (context, index) {
                  final item = componentRows[index];
                  final color = _healthColor(item.status);
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: color.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(item.icon, color: color, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                item.status,
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
        if (constraints.maxWidth >= 1000) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(flex: 2, child: summary),
              const SizedBox(width: 16),
              Expanded(flex: 3, child: components),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[summary, const SizedBox(height: 16), components],
        );
      },
    );
  }
}

class _TemperatureDashboard extends StatelessWidget {
  const _TemperatureDashboard({required this.rows});

  final List<Map<String, Object?>> rows;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.device_thermostat_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Температурные датчики',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                '${rows.length}',
                style: const TextStyle(color: AppColors.mutedInk),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (rows.isEmpty)
            const EmptyState(
              icon: Icons.device_thermostat_outlined,
              text: 'Температурные датчики не найдены.',
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rows.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 245,
                mainAxisExtent: 112,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemBuilder: (context, index) =>
                  _TemperatureGauge(row: rows[index]),
            ),
        ],
      ),
    );
  }
}

class _TemperatureGauge extends StatelessWidget {
  const _TemperatureGauge({required this.row});

  final Map<String, Object?> row;

  @override
  Widget build(BuildContext context) {
    final reading =
        _number(row['ReadingCelsius']) ?? _number(row['ReadingValue']) ?? 0;
    final critical =
        _number(row['UpperThresholdCritical']) ??
        _number(row['UpperThresholdFatal']);
    final ratio = critical == null || critical <= 0
        ? 0.0
        : (reading / critical).clamp(0.0, 1.0);
    final color = _temperatureColor(row, reading, critical);
    final name =
        row['Name']?.toString() ?? 'Temperature ${row['MemberId'] ?? ''}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 66,
            height: 66,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: ratio,
                    strokeWidth: 7,
                    strokeCap: StrokeCap.round,
                    color: color,
                    backgroundColor: AppColors.border,
                  ),
                ),
                Text(
                  '${reading.toStringAsFixed(0)}°',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 5),
                Text(
                  critical == null
                      ? _rowHealth(row)
                      : 'critical ${critical.toStringAsFixed(0)}°C',
                  style: const TextStyle(
                    color: AppColors.mutedInk,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _aggregateHealth(List<Map<String, Object?>>? rows) {
  if (rows == null || rows.isEmpty) {
    return 'Нет данных';
  }
  final health = rows.map(_rowHealth).toList();
  if (health.any((value) => value == 'CRITICAL')) {
    return 'Critical';
  }
  if (health.any((value) => value == 'WARNING')) {
    return 'Warning';
  }
  if (health.every((value) => value == 'OK')) {
    return 'OK';
  }
  return 'Unknown';
}

String _rowHealth(Map<String, Object?> row) {
  final status = row['Status'];
  final value = status is Map
      ? status['Health'] ?? status['HealthRollup'] ?? status['State']
      : status;
  final normalized = value?.toString().trim().toUpperCase() ?? '';
  if (normalized == 'OK' || normalized == 'ENABLED' || normalized == 'NORMAL') {
    return 'OK';
  }
  if (normalized.contains('CRITICAL') || normalized.contains('FAILED')) {
    return 'CRITICAL';
  }
  if (normalized.contains('WARN') || normalized.contains('DEGRADED')) {
    return 'WARNING';
  }
  return 'UNKNOWN';
}

Color _healthColor(String? value) {
  final normalized = value?.trim().toLowerCase() ?? '';
  if (normalized == 'ok' || normalized == 'normal' || normalized == 'enabled') {
    return AppColors.success;
  }
  if (normalized.contains('critical') ||
      normalized.contains('failed') ||
      normalized.contains('error')) {
    return AppColors.danger;
  }
  if (normalized.contains('warn') || normalized.contains('degraded')) {
    return AppColors.warning;
  }
  return AppColors.mutedInk;
}

Color _temperatureColor(
  Map<String, Object?> row,
  double reading,
  double? critical,
) {
  final health = _rowHealth(row);
  if (health == 'CRITICAL' || (critical != null && reading >= critical)) {
    return AppColors.danger;
  }
  if (health == 'WARNING' || (critical != null && reading >= critical * 0.85)) {
    return AppColors.warning;
  }
  return AppColors.success;
}

double? _number(Object? value) => double.tryParse(value?.toString() ?? '');

Widget _redfishSection(
  String title,
  List<Map<String, Object?>>? rows,
  List<String> columns, {
  bool expanded = false,
}) {
  return GenericDataSection(
    title: title,
    rows: rows ?? <Map<String, Object?>>[],
    preferredColumns: columns,
    collapsible: true,
    initiallyExpanded: expanded,
  );
}

Widget _sectionColumn(List<Widget> sections) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      for (var index = 0; index < sections.length; index += 1) ...<Widget>[
        if (index > 0) const SizedBox(height: 16),
        sections[index],
      ],
    ],
  );
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
