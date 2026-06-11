import 'package:flutter/material.dart';
import 'package:frontend/core/design/app_colors.dart';
import 'package:frontend/features/snapshots/domain/resource_history.dart';
import 'package:frontend/shared/formatters/value_formatters.dart';
import 'package:frontend/shared/widgets/app_card.dart';
import 'package:frontend/shared/widgets/empty_state.dart';

class ResourceLineChart extends StatefulWidget {
  const ResourceLineChart({
    required this.title,
    required this.points,
    required this.icon,
    this.description,
    this.now,
    super.key,
  });

  final String title;
  final List<ResourceHistoryPoint> points;
  final IconData icon;
  final String? description;
  final DateTime? now;

  @override
  State<ResourceLineChart> createState() => _ResourceLineChartState();
}

class _ResourceLineChartState extends State<ResourceLineChart> {
  _ChartRange _range = _ChartRange.week;

  @override
  Widget build(BuildContext context) {
    final points = _filterPoints(widget.points, _range, widget.now);
    final latest = points.isEmpty ? null : points.last.value;
    final min = points.isEmpty
        ? null
        : points.map((point) => point.value).reduce((a, b) => a < b ? a : b);
    final max = points.isEmpty
        ? null
        : points.map((point) => point.value).reduce((a, b) => a > b ? a : b);
    final range = points.length < 2
        ? ''
        : '${_formatShortDateTime(points.first.time)} - '
              '${_formatShortDateTime(points.last.time)}';
    return AppCard(
      child: SizedBox(
        height: 260,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(widget.icon, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  latest == null ? '-' : formatPercent(latest),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.description ?? _descriptionForTitle(widget.title),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.mutedInk),
                  ),
                ),
                const SizedBox(width: 12),
                _RangeSelector(
                  value: _range,
                  onChanged: (value) => setState(() => _range = value),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (points.length < 2)
              Expanded(
                child: EmptyState(
                  icon: Icons.show_chart_outlined,
                  text: points.isEmpty
                      ? 'За выбранный период нет истории.'
                      : 'Недостаточно истории для графика.',
                ),
              )
            else
              Expanded(
                child: Column(
                  children: <Widget>[
                    Expanded(
                      child: Row(
                        children: <Widget>[
                          const SizedBox(width: 36, child: _YAxisLabels()),
                          Expanded(
                            child: CustomPaint(
                              painter: _ResourceLineChartPainter(points),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        const SizedBox(width: 36),
                        Expanded(
                          child: Text(
                            range,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColors.mutedInk),
                          ),
                        ),
                        Text(
                          'min ${formatPercent(min ?? 0)} · max ${formatPercent(max ?? 0)}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.mutedInk),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RangeSelector extends StatelessWidget {
  const _RangeSelector({required this.value, required this.onChanged});

  final _ChartRange value;
  final ValueChanged<_ChartRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_ChartRange>(
      segments: const <ButtonSegment<_ChartRange>>[
        ButtonSegment<_ChartRange>(
          value: _ChartRange.today,
          label: Text('Сегодня'),
        ),
        ButtonSegment<_ChartRange>(
          value: _ChartRange.twoDays,
          label: Text('2 дня'),
        ),
        ButtonSegment<_ChartRange>(
          value: _ChartRange.week,
          label: Text('Неделя'),
        ),
      ],
      selected: <_ChartRange>{value},
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(
          Theme.of(context).textTheme.bodySmall,
        ),
      ),
      onSelectionChanged: (Set<_ChartRange> values) {
        if (values.isNotEmpty) {
          onChanged(values.first);
        }
      },
    );
  }
}

enum _ChartRange {
  today(Duration(days: 1)),
  twoDays(Duration(days: 2)),
  week(Duration(days: 7));

  const _ChartRange(this.duration);

  final Duration duration;
}

List<ResourceHistoryPoint> _filterPoints(
  List<ResourceHistoryPoint> points,
  _ChartRange range,
  DateTime? now,
) {
  if (points.isEmpty) {
    return points;
  }
  final from = (now ?? DateTime.now()).subtract(range.duration);
  return points
      .where((point) => !point.time.isBefore(from))
      .toList(growable: false);
}

class _YAxisLabels extends StatelessWidget {
  const _YAxisLabels();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: AppColors.mutedInk);
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Text('100%', style: style),
        Text('50%', style: style),
        Text('0%', style: style),
      ],
    );
  }
}

class _ResourceLineChartPainter extends CustomPainter {
  const _ResourceLineChartPainter(this.points);

  final List<ResourceHistoryPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    final linePaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          AppColors.primary.withValues(alpha: 0.22),
          AppColors.primary.withValues(alpha: 0.02),
        ],
      ).createShader(Offset.zero & size);

    for (final ratio in <double>[0, 0.5, 1]) {
      final y = size.height * (1 - ratio);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final path = Path();
    final fillPath = Path();
    for (var index = 0; index < points.length; index++) {
      final x = points.length == 1
          ? 0.0
          : (index / (points.length - 1)) * size.width;
      final y = (1 - points[index].value.clamp(0, 1)) * size.height;
      if (index == 0) {
        path.moveTo(x, y);
        fillPath
          ..moveTo(x, size.height)
          ..lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath
      ..lineTo(size.width, size.height)
      ..close();
    canvas
      ..drawPath(fillPath, fillPaint)
      ..drawPath(path, linePaint);

    final dotPaint = Paint()..color = AppColors.primaryDark;
    for (final point
        in points.take(1).followedBy(points.skip(points.length - 1))) {
      final index = points.indexOf(point);
      final x = points.length == 1
          ? 0.0
          : (index / (points.length - 1)) * size.width;
      final y = (1 - point.value.clamp(0, 1)) * size.height;
      canvas.drawCircle(Offset(x, y), 3.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ResourceLineChartPainter oldDelegate) {
    return oldDelegate.points != points;
  }
}

String _descriptionForTitle(String title) {
  final lower = title.toLowerCase();
  if (lower.contains('storage')) {
    return 'Средняя занятость storage по всем источникам за период.';
  }
  if (lower.contains('vm') || lower.contains('lxc')) {
    return 'Средняя нагрузка всех VM/LXC из собранных snapshots.';
  }
  if (lower.contains('нод')) {
    return 'Средняя нагрузка всех Proxmox нод из собранных snapshots.';
  }
  return 'Среднее значение по собранным snapshots.';
}

String _formatShortDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int input) => input.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
}
