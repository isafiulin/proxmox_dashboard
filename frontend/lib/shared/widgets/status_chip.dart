import 'package:flutter/material.dart';
import 'package:frontend/core/design/app_colors.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({required this.status, super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalizedStatus = status.toLowerCase();
    final color = switch (normalizedStatus) {
      'active' ||
      'ok' ||
      'online' ||
      'running' ||
      'available' ||
      'enabled' => AppColors.success,
      'blocked' ||
      'critical' ||
      'error' ||
      'failed' ||
      'offline' ||
      'stopped' => AppColors.danger,
      'new' || 'unknown' || 'missing' => AppColors.mutedInk,
      _ => AppColors.warning,
    };

    return SizedBox(
      width: 128,
      child: Chip(
        avatar: Icon(Icons.circle, size: 10, color: color),
        label: Text(status, overflow: TextOverflow.ellipsis),
        visualDensity: VisualDensity.compact,
        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
