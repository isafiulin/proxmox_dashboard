import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/core/design/app_colors.dart';
import 'package:frontend/features/sources/presentation/cubit/sources_cubit.dart';
import 'package:frontend/shared/widgets/app_card.dart';
import 'package:frontend/shared/widgets/async_state_view.dart';
import 'package:frontend/shared/widgets/empty_state.dart';
import 'package:frontend/shared/widgets/generic_data_section.dart';
import 'package:frontend/shared/widgets/metric_card.dart';
import 'package:frontend/shared/widgets/page_header.dart';
import 'package:frontend/shared/widgets/sortable_data_table.dart';
import 'package:frontend/shared/widgets/status_chip.dart';
import 'package:go_router/go_router.dart';

class CollectionMetricsPage extends StatelessWidget {
  const CollectionMetricsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SourcesCubit, SourcesState>(
      builder: (context, state) => FutureBuilder<_CollectionMetrics>(
        future: _load(context),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingStateView();
          }
          if (snapshot.hasError) {
            return ErrorStateView(message: snapshot.error.toString());
          }
          return _content(
            context,
            snapshot.data ?? const _CollectionMetrics.empty(),
          );
        },
      ),
    );
  }

  Future<_CollectionMetrics> _load(BuildContext context) async {
    final json = await context.read<ApiClient>().get('/collection-metrics');
    final rawSources = json['sources'];
    final sources = rawSources is List
        ? rawSources
              .whereType<Map>()
              .map((row) => row.cast<String, Object?>())
              .toList()
        : <Map<String, Object?>>[];
    final rawDaily = json['daily'];
    final daily = rawDaily is List
        ? rawDaily
              .whereType<Map>()
              .map((row) => row.cast<String, Object?>())
              .toList()
        : <Map<String, Object?>>[];
    return _CollectionMetrics(
      sources: sources,
      daily: daily,
      totalPolls: int.tryParse(json['totalPolls']?.toString() ?? '') ?? 0,
      totalErrors: int.tryParse(json['totalErrors']?.toString() ?? '') ?? 0,
    );
  }

  Widget _content(BuildContext context, _CollectionMetrics metrics) {
    final successRate = metrics.totalPolls == 0
        ? 0
        : (metrics.totalPolls - metrics.totalErrors) / metrics.totalPolls;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const PageHeader(
          title: 'Collection metrics',
          subtitle:
              'Опросы источников, ошибки и длительность за текущие 7 дней',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            MetricCard(
              label: 'Sources',
              value: '${metrics.sources.length}',
              icon: Icons.dns_outlined,
            ),
            MetricCard(
              label: 'Polls',
              value: '${metrics.totalPolls}',
              icon: Icons.sync_outlined,
            ),
            MetricCard(
              label: 'Errors',
              value: '${metrics.totalErrors}',
              icon: Icons.error_outline,
              color: metrics.totalErrors == 0
                  ? AppColors.success
                  : AppColors.danger,
            ),
            MetricCard(
              label: 'Success rate',
              value: '${(successRate * 100).round()}%',
              icon: Icons.query_stats_outlined,
              color: successRate >= 0.99
                  ? AppColors.success
                  : successRate >= 0.9
                  ? AppColors.warning
                  : AppColors.danger,
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppCard(
          child: metrics.sources.isEmpty
              ? const EmptyState(
                  icon: Icons.query_stats_outlined,
                  text: 'Метрики появятся после первого backend polling.',
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SortableDataTable<Map<String, Object?>>(
                    showCheckboxColumn: false,
                    initialSortColumnIndex: 5,
                    initialSortAscending: false,
                    columns: <SortableDataColumn<Map<String, Object?>>>[
                      _textColumn('source', 'sourceName'),
                      _textColumn('type', 'sourceType'),
                      _textColumn('status', 'status'),
                      _numberColumn('polls', 'polls'),
                      _numberColumn('errors', 'errors'),
                      _numberColumn('avg ms', 'averageDurationMs'),
                      _numberColumn('last ms', 'lastDurationMs'),
                      _textColumn('last collected', 'lastCollectedAt'),
                    ],
                    items: metrics.sources,
                    rowBuilder: (context, row) => DataRow(
                      onSelectChanged: (_) =>
                          context.go('/sources/${row['sourceId']}'),
                      cells: <DataCell>[
                        DataCell(Text(row['sourceName']?.toString() ?? '')),
                        DataCell(Text(row['sourceType']?.toString() ?? '')),
                        DataCell(
                          StatusChip(
                            status: row['status']?.toString() ?? 'unknown',
                          ),
                        ),
                        DataCell(Text(row['polls']?.toString() ?? '0')),
                        DataCell(Text(row['errors']?.toString() ?? '0')),
                        DataCell(
                          Text(row['averageDurationMs']?.toString() ?? '-'),
                        ),
                        DataCell(
                          Text(row['lastDurationMs']?.toString() ?? '-'),
                        ),
                        DataCell(Text(_date(row['lastCollectedAt']))),
                      ],
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 16),
        GenericDataSection(
          title: 'История polling по дням',
          rows: metrics.daily,
          preferredColumns: const <String>[
            'day',
            'sourceName',
            'polls',
            'errors',
            'averageDurationMs',
          ],
        ),
      ],
    );
  }
}

SortableDataColumn<Map<String, Object?>> _textColumn(
  String label,
  String key,
) => SortableDataColumn(
  label: label,
  compare: (a, b) =>
      compareText(a[key]?.toString() ?? '', b[key]?.toString() ?? ''),
);

SortableDataColumn<Map<String, Object?>> _numberColumn(
  String label,
  String key,
) => SortableDataColumn(
  label: label,
  numeric: true,
  compare: (a, b) => _number(a[key]).compareTo(_number(b[key])),
);

num _number(Object? value) => num.tryParse(value?.toString() ?? '') ?? 0;

String _date(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) {
    return '-';
  }
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} '
      '${two(date.hour)}:${two(date.minute)}';
}

class _CollectionMetrics {
  const _CollectionMetrics({
    required this.sources,
    required this.daily,
    required this.totalPolls,
    required this.totalErrors,
  });

  const _CollectionMetrics.empty()
    : sources = const <Map<String, Object?>>[],
      daily = const <Map<String, Object?>>[],
      totalPolls = 0,
      totalErrors = 0;

  final List<Map<String, Object?>> sources;
  final List<Map<String, Object?>> daily;
  final int totalPolls;
  final int totalErrors;
}
