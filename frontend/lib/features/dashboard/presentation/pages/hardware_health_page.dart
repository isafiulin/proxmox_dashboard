import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/features/sources/data/source_data_repository.dart';
import 'package:frontend/features/sources/domain/source.dart';
import 'package:frontend/features/sources/presentation/cubit/sources_cubit.dart';
import 'package:frontend/shared/widgets/async_state_view.dart';
import 'package:frontend/shared/widgets/generic_data_section.dart';
import 'package:frontend/shared/widgets/metric_card.dart';
import 'package:frontend/shared/widgets/page_header.dart';

class HardwareHealthPage extends StatelessWidget {
  const HardwareHealthPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SourcesCubit, SourcesState>(
      builder: (context, state) {
        final sources = state.items
            .where(
              (source) => source.type == 'redfish' || source.type == 'old_ilo2',
            )
            .toList();
        if (state.status == SourcesStatus.loading && sources.isEmpty) {
          return const LoadingStateView();
        }
        if (sources.isEmpty) {
          return const EmptyCardState(
            icon: Icons.developer_board_outlined,
            text: 'BMC-серверы пока не добавлены.',
          );
        }
        return FutureBuilder<_HardwareReport>(
          future: _load(context, sources),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LoadingStateView();
            }
            if (snapshot.hasError) {
              return ErrorStateView(message: snapshot.error.toString());
            }
            return _HardwareHealthContent(
              report: snapshot.data ?? const _HardwareReport.empty(),
            );
          },
        );
      },
    );
  }

  Future<_HardwareReport> _load(
    BuildContext context,
    List<Source> sources,
  ) async {
    final repository = SourceDataRepository(context.read<ApiClient>());
    final loaded = await Future.wait(
      sources.map((source) async {
        try {
          return _LoadedRedfish(
            source: source,
            data: await repository.loadRedfish(
              source.id,
              sourceType: source.type,
            ),
          );
        } on Object catch (error) {
          return _LoadedRedfish(source: source, error: error.toString());
        }
      }),
    );
    return _HardwareReport.fromLoaded(loaded);
  }
}

class _HardwareHealthContent extends StatelessWidget {
  const _HardwareHealthContent({required this.report});

  final _HardwareReport report;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const PageHeader(
          title: 'Hardware health',
          subtitle: 'Физические серверы, текущие неисправности и события BMC',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: <Widget>[
            MetricCard(
              label: 'Серверы',
              value: '${report.servers.length}',
              icon: Icons.dns_outlined,
            ),
            MetricCard(
              label: 'Critical сейчас',
              value: '${report.criticalIssues}',
              icon: Icons.error_outline,
            ),
            MetricCard(
              label: 'Warning сейчас',
              value: '${report.warningIssues}',
              icon: Icons.warning_amber_outlined,
            ),
            MetricCard(
              label: 'Проблемные события',
              value: '${report.problemEvents.length}',
              icon: Icons.event_note_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Серверы',
          rows: report.servers,
          preferredColumns: const <String>[
            'source',
            'model',
            'serialNumber',
            'powerState',
            'health',
            'collectionState',
            'collectedAt',
            'processors',
            'memoryGiB',
            'issues',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Текущие неисправности оборудования',
          rows: report.healthIssues,
          preferredColumns: const <String>[
            'source',
            'resourceType',
            'name',
            'health',
            'state',
          ],
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'Последние проблемные события',
          rows: report.problemEvents,
          preferredColumns: const <String>[
            'source',
            'Created',
            'normalizedSeverity',
            'Message',
            'MessageId',
            'occurrences',
          ],
        ),
        if (report.integrationErrors.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          GenericDataSection(
            title: 'Ошибки интеграции BMC',
            rows: report.integrationErrors,
            preferredColumns: const <String>[
              'source',
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

class _LoadedRedfish {
  const _LoadedRedfish({required this.source, this.data, this.error});

  final Source source;
  final RedfishData? data;
  final String? error;
}

class _HardwareReport {
  const _HardwareReport({
    required this.servers,
    required this.healthIssues,
    required this.problemEvents,
    required this.integrationErrors,
  });

  const _HardwareReport.empty()
    : servers = const <Map<String, Object?>>[],
      healthIssues = const <Map<String, Object?>>[],
      problemEvents = const <Map<String, Object?>>[],
      integrationErrors = const <Map<String, Object?>>[];

  factory _HardwareReport.fromLoaded(List<_LoadedRedfish> loaded) {
    final servers = <Map<String, Object?>>[];
    final issues = <Map<String, Object?>>[];
    final eventGroups = <String, Map<String, Object?>>{};
    final errors = <Map<String, Object?>>[];
    for (final item in loaded) {
      final data = item.data;
      if (data == null) {
        errors.add(<String, Object?>{
          'sourceId': item.source.id,
          'source': item.source.name,
          'operation': 'inventory',
          'message': item.error,
        });
        continue;
      }
      final system = data.systems.firstOrNull;
      final status = system?['Status'];
      final health = status is Map ? status['Health'] : null;
      final memoryMiB = data.memory.fold<int>(
        0,
        (total, row) =>
            total + (int.tryParse(row['CapacityMiB']?.toString() ?? '') ?? 0),
      );
      servers.add(<String, Object?>{
        'sourceId': item.source.id,
        'source': item.source.name,
        'model': data.identity['model'],
        'serialNumber': data.identity['serialNumber'],
        'powerState': system?['PowerState'],
        'health': health,
        'collectionState': data.collecting ? 'collecting' : 'ready',
        'collectedAt': data.collectedAt?.toLocal().toString(),
        'processors': data.processors.length,
        'memoryGiB': memoryMiB / 1024,
        'issues': data.healthIssues.length,
      });
      issues.addAll(
        data.healthIssues.map(
          (row) => <String, Object?>{'source': item.source.name, ...row},
        ),
      );
      for (final row in data.logEntries.where(
        (row) => _isProblemLevel(row['normalizedSeverity']),
      )) {
        final signature = row['MessageId']?.toString().trim().isNotEmpty == true
            ? row['MessageId'].toString()
            : row['Message']?.toString() ?? '';
        final key = '${item.source.id}\u0001$signature';
        final previous = eventGroups[key];
        final occurrences =
            (int.tryParse(previous?['occurrences']?.toString() ?? '') ?? 0) + 1;
        if (previous == null ||
            (row['Created']?.toString() ?? '').compareTo(
                  previous['Created']?.toString() ?? '',
                ) >
                0) {
          eventGroups[key] = <String, Object?>{
            'source': item.source.name,
            ...row,
            'occurrences': occurrences,
          };
        } else {
          previous['occurrences'] = occurrences;
        }
      }
      errors.addAll(
        data.errors.map(
          (row) => <String, Object?>{'source': item.source.name, ...row},
        ),
      );
      if (data.stale) {
        errors.add(<String, Object?>{
          'source': item.source.name,
          'operation': 'refresh',
          'message': data.refreshError ?? 'Не удалось обновить данные BMC.',
        });
      }
    }
    final events = eventGroups.values.toList()
      ..sort(
        (left, right) => (right['Created']?.toString() ?? '').compareTo(
          left['Created']?.toString() ?? '',
        ),
      );
    return _HardwareReport(
      servers: servers,
      healthIssues: issues,
      problemEvents: events,
      integrationErrors: errors,
    );
  }

  final List<Map<String, Object?>> servers;
  final List<Map<String, Object?>> healthIssues;
  final List<Map<String, Object?>> problemEvents;
  final List<Map<String, Object?>> integrationErrors;

  int get criticalIssues => healthIssues
      .where((row) => row['health']?.toString().toLowerCase() == 'critical')
      .length;

  int get warningIssues => healthIssues
      .where((row) => row['health']?.toString().toLowerCase() == 'warning')
      .length;
}

bool _isProblemLevel(Object? value) {
  final level = value?.toString().toLowerCase() ?? '';
  return level == 'critical' || level == 'warning';
}
