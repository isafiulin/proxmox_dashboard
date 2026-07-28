import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/core/design/app_colors.dart';
import 'package:frontend/features/sources/data/source_data_repository.dart';
import 'package:frontend/features/sources/domain/pbs_health.dart';
import 'package:frontend/features/sources/domain/source.dart';
import 'package:frontend/features/sources/presentation/cubit/sources_cubit.dart';
import 'package:frontend/shared/widgets/app_card.dart';
import 'package:frontend/shared/widgets/app_text_field.dart';
import 'package:frontend/shared/widgets/async_state_view.dart';
import 'package:frontend/shared/widgets/empty_state.dart';
import 'package:frontend/shared/widgets/metric_card.dart';
import 'package:frontend/shared/widgets/page_header.dart';
import 'package:frontend/shared/widgets/sortable_data_table.dart';
import 'package:frontend/shared/widgets/status_chip.dart';
import 'package:go_router/go_router.dart';

class PbsVerifyPage extends StatefulWidget {
  const PbsVerifyPage({super.key});

  @override
  State<PbsVerifyPage> createState() => _PbsVerifyPageState();
}

class _PbsVerifyPageState extends State<PbsVerifyPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _state = 'all';
  String _sourcesKey = '';
  Future<List<PbsVerifyItem>>? _itemsFuture;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SourcesCubit, SourcesState>(
      builder: (context, state) {
        final sourcesKey = identityHashCode(state.items).toString();
        if (_itemsFuture == null || _sourcesKey != sourcesKey) {
          _sourcesKey = sourcesKey;
          _itemsFuture = _load(context, state.items);
        }
        return FutureBuilder<List<PbsVerifyItem>>(
          future: _itemsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LoadingStateView();
            }
            if (snapshot.hasError) {
              return ErrorStateView(message: snapshot.error.toString());
            }
            final all = snapshot.data ?? const <PbsVerifyItem>[];
            final visible = all.where((item) {
              final query = _query.trim().toLowerCase();
              final matchesState = _state == 'all' || item.state == _state;
              final matchesQuery =
                  query.isEmpty ||
                  <String>[
                    item.backupSource,
                    item.datastore,
                    item.namespace,
                    item.backupGroup,
                    item.reason,
                  ].join(' ').toLowerCase().contains(query);
              return matchesState && matchesQuery;
            }).toList();
            return _content(context, all, visible);
          },
        );
      },
    );
  }

  Future<List<PbsVerifyItem>> _load(
    BuildContext context,
    List<Source> sources,
  ) async {
    final repository = SourceDataRepository(context.read<ApiClient>());
    final snapshots = <Map<String, Object?>>[];
    for (final source in sources.where(
      (item) => item.type == 'proxmox_backup',
    )) {
      final data = await repository.loadProxmoxBackup(source.id);
      snapshots.addAll(
        data.snapshots.map(
          (snapshot) => <String, Object?>{
            'backupSourceId': source.id,
            'backupSource': source.name,
            ...snapshot,
          },
        ),
      );
    }
    return buildPbsVerifyItems(snapshots);
  }

  Widget _content(
    BuildContext context,
    List<PbsVerifyItem> all,
    List<PbsVerifyItem> visible,
  ) {
    final ok = all.where((item) => item.state == 'ok').length;
    final failed = all.where((item) => item.state == 'critical').length;
    final unverified = all.where((item) => item.state == 'unverified').length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const PageHeader(
          title: 'PBS verify state',
          subtitle: 'Целостность snapshots по всем PBS, datastore и namespace',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            MetricCard(
              label: 'Verified',
              value: '$ok',
              icon: Icons.verified,
              color: AppColors.success,
            ),
            MetricCard(
              label: 'Verify failed',
              value: '$failed',
              icon: Icons.error_outline,
              color: failed == 0 ? AppColors.success : AppColors.danger,
            ),
            MetricCard(
              label: 'Not verified',
              value: '$unverified',
              icon: Icons.help_outline,
              color: unverified == 0 ? AppColors.success : AppColors.warning,
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Row(
            children: <Widget>[
              Expanded(
                child: AppTextField(
                  controller: _searchController,
                  label: 'PBS, datastore, namespace или backup group',
                  prefixIcon: Icons.search,
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _state,
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'all', child: Text('Все состояния')),
                  DropdownMenuItem(value: 'critical', child: Text('Failed')),
                  DropdownMenuItem(
                    value: 'unverified',
                    child: Text('Not verified'),
                  ),
                  DropdownMenuItem(value: 'ok', child: Text('OK')),
                ],
                onChanged: (value) => setState(() => _state = value ?? 'all'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          child: visible.isEmpty
              ? const EmptyState(
                  icon: Icons.fact_check_outlined,
                  text: 'Snapshots с такими фильтрами не найдены.',
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SortableDataTable<PbsVerifyItem>(
                    showCheckboxColumn: false,
                    columns: <SortableDataColumn<PbsVerifyItem>>[
                      SortableDataColumn(
                        label: 'state',
                        compare: (a, b) => compareText(a.state, b.state),
                      ),
                      SortableDataColumn(
                        label: 'PBS',
                        compare: (a, b) =>
                            compareText(a.backupSource, b.backupSource),
                      ),
                      SortableDataColumn(
                        label: 'datastore',
                        compare: (a, b) =>
                            compareText(a.datastore, b.datastore),
                      ),
                      SortableDataColumn(
                        label: 'namespace',
                        compare: (a, b) =>
                            compareText(a.namespace, b.namespace),
                      ),
                      SortableDataColumn(
                        label: 'backup group',
                        compare: (a, b) =>
                            compareText(a.backupGroup, b.backupGroup),
                      ),
                      SortableDataColumn(
                        label: 'backup time',
                        compare: (a, b) =>
                            compareNullableDateTime(a.backupTime, b.backupTime),
                      ),
                      SortableDataColumn(
                        label: 'reason / UPID',
                        compare: (a, b) => compareText(a.reason, b.reason),
                      ),
                    ],
                    items: visible,
                    rowBuilder: (context, item) => DataRow(
                      onSelectChanged: (_) =>
                          context.go('/sources/${item.backupSourceId}'),
                      cells: <DataCell>[
                        DataCell(StatusChip(status: item.state)),
                        DataCell(Text(item.backupSource)),
                        DataCell(Text(item.datastore)),
                        DataCell(
                          Text(
                            item.namespace.isEmpty ? 'root' : item.namespace,
                          ),
                        ),
                        DataCell(Text(item.backupGroup)),
                        DataCell(Text(_date(item.backupTime))),
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 360),
                            child: Text(
                              item.reason.isEmpty ? '-' : item.reason,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

String _date(DateTime? value) {
  if (value == null) {
    return '-';
  }
  final local = value.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
