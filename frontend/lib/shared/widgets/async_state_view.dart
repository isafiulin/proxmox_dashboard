import 'package:flutter/material.dart';
import 'package:frontend/core/design/app_colors.dart';
import 'package:frontend/shared/widgets/app_card.dart';
import 'package:frontend/shared/widgets/empty_state.dart';

class LoadingStateView extends StatelessWidget {
  const LoadingStateView({this.rows = 3, super.key});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SkeletonLine(width: 240, height: 28),
        const SizedBox(height: 16),
        const Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            _SkeletonMetric(),
            _SkeletonMetric(),
            _SkeletonMetric(),
            _SkeletonMetric(),
          ],
        ),
        const SizedBox(height: 16),
        ...List<Widget>.generate(rows, (int index) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: _SkeletonCard(),
          );
        }),
      ],
    );
  }
}

class ErrorStateView extends StatelessWidget {
  const ErrorStateView({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

class EmptyCardState extends StatelessWidget {
  const EmptyCardState({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: EmptyState(icon: icon, text: text),
    );
  }
}

class _SkeletonMetric extends StatelessWidget {
  const _SkeletonMetric();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 220,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SkeletonLine(width: 96, height: 12),
            SizedBox(height: 14),
            _SkeletonLine(width: 72, height: 26),
          ],
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SkeletonLine(width: 180, height: 18),
          SizedBox(height: 18),
          _SkeletonLine(width: double.infinity, height: 12),
          SizedBox(height: 10),
          _SkeletonLine(width: double.infinity, height: 12),
          SizedBox(height: 10),
          _SkeletonLine(width: 260, height: 12),
        ],
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.border.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
