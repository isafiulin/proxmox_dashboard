import 'package:flutter/material.dart';
import 'package:frontend/core/design/app_colors.dart';
import 'package:frontend/features/snapshots/domain/resource_history.dart';
import 'package:frontend/shared/formatters/value_formatters.dart';
import 'package:frontend/shared/widgets/app_card.dart';
import 'package:frontend/shared/widgets/empty_state.dart';

class ResourceLineChart extends StatelessWidget {
  const ResourceLineChart({
    required this.title,
    required this.points,
    required this.icon,
    super.key,
  });

  final String title;
  final List<ResourceHistoryPoint> points;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final latest = points.isEmpty ? null : points.last.value;
    return AppCard(
      child: SizedBox(
        height: 220,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
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
            const SizedBox(height: 12),
            if (points.length < 2)
              const Expanded(
                child: EmptyState(
                  icon: Icons.show_chart_outlined,
                  text: 'Недостаточно истории для графика.',
                ),
              )
            else
              Expanded(
                child: CustomPaint(
                  painter: _ResourceLineChartPainter(points),
                  child: const SizedBox.expand(),
                ),
              ),
          ],
        ),
      ),
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
