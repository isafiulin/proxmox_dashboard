import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/api/api_client.dart';
import 'package:frontend/core/design/app_colors.dart';
import 'package:frontend/features/sources/data/source_data_repository.dart';
import 'package:frontend/features/sources/domain/backup_analysis.dart';
import 'package:frontend/features/sources/domain/source.dart';
import 'package:frontend/features/sources/presentation/cubit/sources_cubit.dart';
import 'package:frontend/shared/widgets/app_card.dart';
import 'package:frontend/shared/widgets/async_state_view.dart';
import 'package:frontend/shared/widgets/empty_state.dart';
import 'package:frontend/shared/widgets/metric_card.dart';
import 'package:frontend/shared/widgets/page_header.dart';
import 'package:frontend/shared/widgets/sortable_data_table.dart';
import 'package:go_router/go_router.dart';

const double _calendarWeekdayHeaderHeight = 18;
const double _calendarGridGap = 6;
const double _calendarGridTopGap = 8;
const double _calendarDayTileHeight = 52;
const double _calendarViewportHeight =
    _calendarWeekdayHeaderHeight +
    _calendarGridTopGap +
    (_calendarDayTileHeight * 6) +
    (_calendarGridGap * 5) +
    12;

class BackupSchedulePage extends StatelessWidget {
  const BackupSchedulePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SourcesCubit, SourcesState>(
      builder: (BuildContext context, SourcesState state) {
        if (state.status == SourcesStatus.loading && state.items.isEmpty) {
          return const LoadingStateView();
        }
        return FutureBuilder<_BackupScheduleData>(
          future: _load(context, state.items),
          builder:
              (
                BuildContext context,
                AsyncSnapshot<_BackupScheduleData> snapshot,
              ) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LoadingStateView();
                }
                if (snapshot.hasError) {
                  return ErrorStateView(message: snapshot.error.toString());
                }
                return _BackupScheduleContent(
                  data: snapshot.data ?? const _BackupScheduleData.empty(),
                );
              },
        );
      },
    );
  }

  Future<_BackupScheduleData> _load(
    BuildContext context,
    List<Source> sources,
  ) async {
    final repository = SourceDataRepository(context.read<ApiClient>());
    final pveSources = sources
        .where((source) => source.type == 'proxmox_ve')
        .toList();
    final pbsSources = sources
        .where((source) => source.type == 'proxmox_backup')
        .toList();
    final snapshots = <Map<String, Object?>>[];
    final targets = <String, _ScheduleTarget>{};

    for (final source in pveSources) {
      final data = await repository.loadProxmoxVe(source.id);
      final backupNamespaces = backupNamespacesFromStorageConfig(
        data.storageConfig,
        manualNamespace: source.backupNamespace,
      );
      final effectiveNamespaces = backupNamespaces.isEmpty
          ? const <String>{''}
          : backupNamespaces;
      for (final guest in data.vmResources.where(_isGuest)) {
        final guestType = guest['type']?.toString() ?? '';
        final backupType = guestType == 'lxc' ? 'ct' : 'vm';
        final vmid = guest['vmid']?.toString() ?? '';
        if (vmid.isEmpty) {
          continue;
        }
        for (final namespace in effectiveNamespaces) {
          targets[_scheduleKey(namespace, backupType, vmid)] = _ScheduleTarget(
            sourceId: source.id,
            sourceName: source.name,
            backupNamespace: namespace,
            node: guest['node']?.toString() ?? '',
            guestType: guestType,
            vmid: vmid,
            name: guest['name']?.toString() ?? '',
          );
        }
      }
    }

    for (final source in pbsSources) {
      final data = await repository.loadProxmoxBackup(source.id);
      snapshots.addAll(
        data.snapshots.map(
          (snapshot) => <String, Object?>{
            'backupSource': source.name,
            ...snapshot,
          },
        ),
      );
    }

    return _BackupScheduleData(
      pbsSources: pbsSources.length,
      report: analyzeBackupSchedule(snapshots),
      targets: targets,
    );
  }
}

class _BackupScheduleContent extends StatelessWidget {
  const _BackupScheduleContent({required this.data});

  final _BackupScheduleData data;

  @override
  Widget build(BuildContext context) {
    final activeDays = data.report.calendarEntries
        .map((entry) => _startOfDay(entry.backupAt))
        .toSet()
        .length;
    final regularItems = data.report.items
        .where((item) => item.averageInterval != null)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const PageHeader(
          title: 'Backup schedule',
          subtitle: 'Фактическое расписание по PBS snapshots за последние дни',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            MetricCard(
              label: 'VM/LXC с backup',
              value: data.report.protectedGuests.toString(),
              icon: Icons.backup_outlined,
            ),
            MetricCard(
              label: 'Snapshots',
              value: data.report.totalSnapshots.toString(),
              icon: Icons.inventory_2_outlined,
            ),
            MetricCard(
              label: 'Активных дней',
              value: activeDays.toString(),
              icon: Icons.calendar_month_outlined,
            ),
            MetricCard(
              label: 'С интервалом',
              value: regularItems.toString(),
              icon: Icons.repeat_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _ScheduleInfoCard(),
        const SizedBox(height: 16),
        _BackupCalendar(
          entries: data.report.calendarEntries,
          scheduleItems: data.report.items,
          targets: data.targets,
        ),
        const SizedBox(height: 16),
        _ScheduleTable(items: data.report.items, targets: data.targets),
      ],
    );
  }
}

class _ScheduleInfoCard extends StatelessWidget {
  const _ScheduleInfoCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.info_outline, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Это не raw-конфигурация jobs из Proxmox, а восстановленное '
              'расписание по фактическим PBS snapshots: типичное время, '
              'дни запуска и средний интервал между backup.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.mutedInk),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupCalendar extends StatefulWidget {
  const _BackupCalendar({
    required this.entries,
    required this.scheduleItems,
    required this.targets,
  });

  final List<BackupCalendarEntry> entries;
  final List<BackupScheduleItem> scheduleItems;
  final Map<String, _ScheduleTarget> targets;

  @override
  State<_BackupCalendar> createState() => _BackupCalendarState();
}

class _BackupCalendarState extends State<_BackupCalendar> {
  static const int _initialPage = 1200;

  late final PageController _controller;
  late DateTime _anchorMonth;
  late DateTime _visibleMonth;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final latest = widget.entries.isEmpty
        ? DateTime.now()
        : widget.entries.last.backupAt;
    _anchorMonth = DateTime(latest.year, latest.month);
    _visibleMonth = _anchorMonth;
    _selectedDay = _startOfDay(latest);
    _controller = PageController(initialPage: _initialPage);
  }

  @override
  void didUpdateWidget(covariant _BackupCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entries.isEmpty && widget.entries.isNotEmpty) {
      final latest = widget.entries.last.backupAt;
      setState(() {
        _anchorMonth = DateTime(latest.year, latest.month);
        _visibleMonth = _anchorMonth;
        _selectedDay = _startOfDay(latest);
      });
      _controller.jumpToPage(_initialPage);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eventsByDay = _eventsByDay(
      actualEntries: widget.entries,
      scheduleItems: widget.scheduleItems,
      visibleMonth: _visibleMonth,
    );
    final selectedEntries =
        eventsByDay[_startOfDay(_selectedDay)] ?? <_CalendarEvent>[];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Календарь backup activity',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Предыдущий месяц',
                onPressed: () => _controller.previousPage(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                ),
                icon: const Icon(Icons.chevron_left),
              ),
              SizedBox(
                width: 150,
                child: Text(
                  _formatMonth(_visibleMonth),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Следующий месяц',
                onPressed: () => _controller.nextPage(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                ),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (widget.entries.isEmpty && widget.scheduleItems.isEmpty)
            const EmptyState(
              icon: Icons.calendar_month_outlined,
              text: 'Backup events пока не найдены.',
            )
          else ...<Widget>[
            SizedBox(
              height: _calendarViewportHeight,
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (int page) {
                  setState(() {
                    _visibleMonth = DateTime(
                      _anchorMonth.year,
                      _anchorMonth.month + page - _initialPage,
                    );
                  });
                },
                itemBuilder: (BuildContext context, int page) {
                  final month = DateTime(
                    _anchorMonth.year,
                    _anchorMonth.month + page - _initialPage,
                  );
                  return _MonthGrid(
                    month: month,
                    eventsByDay: _eventsByDay(
                      actualEntries: widget.entries,
                      scheduleItems: widget.scheduleItems,
                      visibleMonth: month,
                    ),
                    selectedDay: _selectedDay,
                    onSelectDay: (DateTime day) =>
                        setState(() => _selectedDay = day),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            _DayBackupList(
              day: _selectedDay,
              entries: selectedEntries,
              targets: widget.targets,
            ),
          ],
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.eventsByDay,
    required this.selectedDay,
    required this.onSelectDay,
  });

  final DateTime month;
  final Map<DateTime, List<_CalendarEvent>> eventsByDay;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final days = _calendarMonthDays(month);
    final maxCount = eventsByDay.entries
        .where(
          (entry) =>
              entry.key.year == month.year && entry.key.month == month.month,
        )
        .fold<int>(
          0,
          (max, entry) => entry.value.length > max ? entry.value.length : max,
        );

    return Column(
      children: <Widget>[
        const Row(
          children: <Widget>[
            _WeekdayHeader('Mon'),
            _WeekdayHeader('Tue'),
            _WeekdayHeader('Wed'),
            _WeekdayHeader('Thu'),
            _WeekdayHeader('Fri'),
            _WeekdayHeader('Sat'),
            _WeekdayHeader('Sun'),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: _calendarGridGap,
              crossAxisSpacing: _calendarGridGap,
              mainAxisExtent: _calendarDayTileHeight,
            ),
            itemCount: days.length,
            itemBuilder: (BuildContext context, int index) {
              final day = days[index];
              final events =
                  eventsByDay[_startOfDay(day)] ?? const <_CalendarEvent>[];
              final selected = _isSameDay(day, selectedDay);
              final inMonth = day.month == month.month;
              final plannedOnly =
                  events.isNotEmpty && events.every((event) => event.planned);
              final intensity = maxCount == 0 ? 0.0 : events.length / maxCount;
              return _CalendarDayTile(
                day: day,
                count: events.length,
                intensity: intensity,
                plannedOnly: plannedOnly,
                selected: selected,
                inMonth: inMonth,
                onTap: () => onSelectDay(_startOfDay(day)),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SizedBox(
        height: _calendarWeekdayHeaderHeight,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.mutedInk,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _CalendarDayTile extends StatelessWidget {
  const _CalendarDayTile({
    required this.day,
    required this.count,
    required this.intensity,
    required this.plannedOnly,
    required this.selected,
    required this.inMonth,
    required this.onTap,
  });

  final DateTime day;
  final int count;
  final double intensity;
  final bool plannedOnly;
  final bool selected;
  final bool inMonth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = count == 0
        ? AppColors.surfaceAlt
        : Color.lerp(
            AppColors.surfaceAlt,
            plannedOnly ? AppColors.primary : AppColors.success,
            intensity,
          )!;
    final foreground = intensity > 0.55 ? Colors.white : AppColors.ink;
    final opacity = inMonth ? 1.0 : 0.35;

    return Tooltip(
      message:
          '${_formatDate(day)}: $count ${plannedOnly ? 'planned ' : ''}backup events',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: background.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      day.day.toString(),
                      style: TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    count.toString(),
                    style: TextStyle(
                      color: foreground,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                'events',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: foreground, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayBackupList extends StatelessWidget {
  const _DayBackupList({
    required this.day,
    required this.entries,
    required this.targets,
  });

  final DateTime day;
  final List<_CalendarEvent> entries;
  final Map<String, _ScheduleTarget> targets;

  @override
  Widget build(BuildContext context) {
    final sortedEntries = List<_CalendarEvent>.from(entries)
      ..sort((a, b) => a.backupAt.compareTo(b.backupAt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '${_formatDate(day)} · ${sortedEntries.length} backup events',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (sortedEntries.isEmpty)
          const EmptyState(
            icon: Icons.event_busy_outlined,
            text: 'В этот день backup events не найдены.',
          )
        else
          ...sortedEntries.map((entry) {
            final target =
                targets[_scheduleKey(
                  entry.namespace,
                  entry.backupType,
                  entry.backupId,
                )];
            final title = target == null || target.name.isEmpty
                ? entry.displayName
                : target.name;
            final location = target == null
                ? _backupLabel(entry.displayName, entry.namespace)
                : '${_backupLabel(entry.displayName, entry.namespace)} · ${target.sourceName} / ${target.node}';
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              isThreeLine: target != null,
              leading: Icon(
                entry.planned
                    ? Icons.event_available_outlined
                    : Icons.backup_outlined,
              ),
              title: Text(title),
              subtitle: Text(
                '$location\n'
                '${_formatTime(entry.backupAt)} · '
                '${entry.planned
                    ? 'planned'
                    : entry.backupSource.isEmpty
                    ? 'PBS'
                    : entry.backupSource}'
                '${entry.datastore.isEmpty ? '' : ' · ${entry.datastore}'}',
              ),
              trailing: target == null ? null : const Icon(Icons.chevron_right),
              onTap: target == null
                  ? null
                  : () {
                      final query = target.name.isEmpty
                          ? ''
                          : '?name=${Uri.encodeQueryComponent(target.name)}';
                      context.go(
                        '/sources/${target.sourceId}/guests/'
                        '${target.guestType}/'
                        '${Uri.encodeComponent(target.node)}/'
                        '${target.vmid}$query',
                      );
                    },
            );
          }),
      ],
    );
  }
}

class _ScheduleTable extends StatelessWidget {
  const _ScheduleTable({required this.items, required this.targets});

  final List<BackupScheduleItem> items;
  final Map<String, _ScheduleTarget> targets;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'VM/LXC расписание',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const EmptyState(
              icon: Icons.backup_outlined,
              text: 'Backup snapshots пока не найдены.',
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SortableDataTable<BackupScheduleItem>(
                showCheckboxColumn: false,
                initialSortColumnIndex: 5,
                items: items,
                columns: <SortableDataColumn<BackupScheduleItem>>[
                  SortableDataColumn<BackupScheduleItem>(
                    label: 'vm/lxc',
                    compare: (left, right) =>
                        compareText(left.displayName, right.displayName),
                  ),
                  SortableDataColumn<BackupScheduleItem>(
                    label: 'namespace',
                    compare: (left, right) =>
                        compareText(left.namespace, right.namespace),
                  ),
                  SortableDataColumn<BackupScheduleItem>(
                    label: 'name',
                    compare: (left, right) => compareText(
                      targets[_itemKey(left)]?.name ?? '',
                      targets[_itemKey(right)]?.name ?? '',
                    ),
                  ),
                  SortableDataColumn<BackupScheduleItem>(
                    label: 'cluster',
                    compare: (left, right) => compareText(
                      targets[_itemKey(left)]?.sourceName ?? '',
                      targets[_itemKey(right)]?.sourceName ?? '',
                    ),
                  ),
                  SortableDataColumn<BackupScheduleItem>(
                    label: 'node',
                    compare: (left, right) => compareText(
                      targets[_itemKey(left)]?.node ?? '',
                      targets[_itemKey(right)]?.node ?? '',
                    ),
                  ),
                  SortableDataColumn<BackupScheduleItem>(
                    label: 'events',
                    numeric: true,
                    compare: (left, right) => left.count.compareTo(right.count),
                  ),
                  SortableDataColumn<BackupScheduleItem>(
                    label: 'typical time',
                    compare: (left, right) =>
                        left.typicalHour.compareTo(right.typicalHour),
                  ),
                  SortableDataColumn<BackupScheduleItem>(
                    label: 'days',
                    compare: (left, right) => compareText(
                      _weekdaySummary(left.weekdayCounts),
                      _weekdaySummary(right.weekdayCounts),
                    ),
                  ),
                  SortableDataColumn<BackupScheduleItem>(
                    label: 'avg interval',
                    numeric: true,
                    compare: (left, right) => _durationMillis(
                      left.averageInterval,
                    ).compareTo(_durationMillis(right.averageInterval)),
                  ),
                  SortableDataColumn<BackupScheduleItem>(
                    label: 'last backup',
                    compare: (left, right) => compareNullableDateTime(
                      left.latestBackupAt,
                      right.latestBackupAt,
                    ),
                  ),
                  SortableDataColumn<BackupScheduleItem>(
                    label: 'datastores',
                    compare: (left, right) => compareText(
                      left.datastores.join(', '),
                      right.datastores.join(', '),
                    ),
                  ),
                ],
                rowBuilder: (context, item) {
                  final target = targets[_itemKey(item)];
                  return DataRow(
                    onSelectChanged: target == null
                        ? null
                        : (_) {
                            final query = target.name.isEmpty
                                ? ''
                                : '?name=${Uri.encodeQueryComponent(target.name)}';
                            context.go(
                              '/sources/${target.sourceId}/guests/'
                              '${target.guestType}/'
                              '${Uri.encodeComponent(target.node)}/'
                              '${target.vmid}$query',
                            );
                          },
                    cells: <DataCell>[
                      DataCell(
                        Text(_backupLabel(item.displayName, item.namespace)),
                      ),
                      DataCell(Text(_namespaceLabel(item.namespace))),
                      DataCell(Text(target?.name ?? '-')),
                      DataCell(Text(target?.sourceName ?? '-')),
                      DataCell(Text(target?.node ?? '-')),
                      DataCell(Text(item.count.toString())),
                      DataCell(
                        Text(
                          '${item.typicalHour.toString().padLeft(2, '0')}:00',
                        ),
                      ),
                      DataCell(Text(_weekdaySummary(item.weekdayCounts))),
                      DataCell(Text(_formatDuration(item.averageInterval))),
                      DataCell(Text(_formatDateTime(item.latestBackupAt))),
                      DataCell(Text(item.datastores.join(', '))),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _BackupScheduleData {
  const _BackupScheduleData({
    required this.pbsSources,
    required this.report,
    required this.targets,
  });

  const _BackupScheduleData.empty()
    : pbsSources = 0,
      report = const BackupScheduleReport(
        items: <BackupScheduleItem>[],
        calendarDays: <BackupCalendarDay>[],
        calendarEntries: <BackupCalendarEntry>[],
        totalSnapshots: 0,
      ),
      targets = const <String, _ScheduleTarget>{};

  final int pbsSources;
  final BackupScheduleReport report;
  final Map<String, _ScheduleTarget> targets;
}

class _ScheduleTarget {
  const _ScheduleTarget({
    required this.sourceId,
    required this.sourceName,
    required this.backupNamespace,
    required this.node,
    required this.guestType,
    required this.vmid,
    required this.name,
  });

  final String sourceId;
  final String sourceName;
  final String backupNamespace;
  final String node;
  final String guestType;
  final String vmid;
  final String name;
}

class _CalendarEvent {
  const _CalendarEvent({
    required this.namespace,
    required this.backupType,
    required this.backupId,
    required this.displayName,
    required this.backupAt,
    required this.backupSource,
    required this.datastore,
    required this.planned,
  });

  factory _CalendarEvent.actual(BackupCalendarEntry entry) {
    return _CalendarEvent(
      namespace: entry.namespace,
      backupType: entry.backupType,
      backupId: entry.backupId,
      displayName: entry.displayName,
      backupAt: entry.backupAt,
      backupSource: entry.backupSource,
      datastore: entry.datastore,
      planned: false,
    );
  }

  factory _CalendarEvent.planned({
    required BackupScheduleItem item,
    required DateTime day,
  }) {
    return _CalendarEvent(
      namespace: item.namespace,
      backupType: item.backupType,
      backupId: item.backupId,
      displayName: item.displayName,
      backupAt: DateTime(day.year, day.month, day.day, item.typicalHour),
      backupSource: '',
      datastore: item.datastores.join(', '),
      planned: true,
    );
  }

  final String namespace;
  final String backupType;
  final String backupId;
  final String displayName;
  final DateTime backupAt;
  final String backupSource;
  final String datastore;
  final bool planned;
}

bool _isGuest(Map<String, Object?> item) {
  return item['type'] == 'qemu' || item['type'] == 'lxc';
}

String _scheduleKey(String namespace, String backupType, String backupId) {
  return '${namespace.trim()}\u0001$backupType\u0001$backupId';
}

String _itemKey(BackupScheduleItem item) {
  return _scheduleKey(item.namespace, item.backupType, item.backupId);
}

String _backupLabel(String displayName, String namespace) {
  return namespace.isEmpty ? displayName : '$namespace / $displayName';
}

String _namespaceLabel(String namespace) {
  return namespace.isEmpty ? 'root' : namespace;
}

Map<DateTime, List<_CalendarEvent>> _eventsByDay({
  required List<BackupCalendarEntry> actualEntries,
  required List<BackupScheduleItem> scheduleItems,
  required DateTime visibleMonth,
}) {
  final result = <DateTime, List<_CalendarEvent>>{};
  for (final entry in actualEntries) {
    final day = _startOfDay(entry.backupAt);
    result.putIfAbsent(day, () => <_CalendarEvent>[]);
    result[day]!.add(_CalendarEvent.actual(entry));
  }

  final today = _startOfDay(DateTime.now());
  for (final day in _calendarMonthDays(visibleMonth)) {
    final normalizedDay = _startOfDay(day);
    if (!normalizedDay.isAfter(today)) {
      continue;
    }
    for (final item in scheduleItems) {
      if (!item.weekdayCounts.containsKey(normalizedDay.weekday)) {
        continue;
      }
      result.putIfAbsent(normalizedDay, () => <_CalendarEvent>[]);
      result[normalizedDay]!.add(
        _CalendarEvent.planned(item: item, day: normalizedDay),
      );
    }
  }
  return result;
}

String _formatDateTime(DateTime? value) {
  if (value == null) {
    return '-';
  }
  final local = value.toLocal();
  return '${_formatDate(local)} ${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String _formatDate(DateTime value) {
  return '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

String _formatTime(DateTime value) {
  return '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

String _formatMonth(DateTime value) {
  const months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[value.month - 1]} ${value.year}';
}

String _formatDuration(Duration? value) {
  if (value == null) {
    return '-';
  }
  if (value.inDays > 0) {
    return '${value.inDays}d ${value.inHours.remainder(24)}h';
  }
  if (value.inHours > 0) {
    return '${value.inHours}h';
  }
  return '${value.inMinutes}m';
}

String _weekdaySummary(Map<int, int> weekdayCounts) {
  if (weekdayCounts.isEmpty) {
    return '-';
  }
  final entries = weekdayCounts.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return entries
      .map((entry) => '${_weekdayLabel(entry.key)} ${entry.value}')
      .join(', ');
}

String _weekdayLabel(int weekday) {
  return switch (weekday) {
    DateTime.monday => 'Mon',
    DateTime.tuesday => 'Tue',
    DateTime.wednesday => 'Wed',
    DateTime.thursday => 'Thu',
    DateTime.friday => 'Fri',
    DateTime.saturday => 'Sat',
    DateTime.sunday => 'Sun',
    _ => '-',
  };
}

List<DateTime> _calendarMonthDays(DateTime month) {
  final first = DateTime(month.year, month.month);
  final firstGridDay = first.subtract(Duration(days: first.weekday - 1));
  return List<DateTime>.generate(
    42,
    (index) => firstGridDay.add(Duration(days: index)),
  );
}

DateTime _startOfDay(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

bool _isSameDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

int _durationMillis(Duration? value) {
  return value?.inMilliseconds ?? 0;
}
