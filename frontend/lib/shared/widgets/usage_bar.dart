import 'package:flutter/material.dart';
import 'package:frontend/core/design/app_colors.dart';

class UsageBar extends StatelessWidget {
  const UsageBar({required this.value, this.label, super.key});

  final double value;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final normalized = value.clamp(0, 1).toDouble();
    final color = normalized >= 0.9
        ? AppColors.danger
        : normalized >= 0.75
        ? AppColors.warning
        : AppColors.success;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 8,
            value: normalized,
            backgroundColor: AppColors.surfaceAlt,
            color: color,
          ),
        ),
        if (label != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(label!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }
}
