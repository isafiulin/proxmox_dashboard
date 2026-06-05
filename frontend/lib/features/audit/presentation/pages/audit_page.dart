import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:frontend/features/audit/presentation/cubit/audit_cubit.dart';
import 'package:frontend/shared/widgets/app_card.dart';
import 'package:frontend/shared/widgets/async_state_view.dart';

class AuditPage extends StatelessWidget {
  const AuditPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuditCubit, AuditState>(
      builder: (BuildContext context, AuditState state) {
        if (state.items.isEmpty) {
          return const EmptyCardState(
            icon: Icons.fact_check_outlined,
            text: 'Аудит пока пуст.',
          );
        }

        return AppCard(
          padding: EdgeInsets.zero,
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: state.items.length,
            separatorBuilder: (BuildContext context, int index) =>
                const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) {
              final event = state.items[index];
              return ListTile(
                leading: const Icon(Icons.history),
                title: Text(event.action),
                subtitle: Text(event.localCreatedAt),
                trailing: Text(
                  event.targetId.substring(
                    0,
                    event.targetId.length.clamp(0, 8),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
