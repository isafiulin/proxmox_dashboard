import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:frontend/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:frontend/features/users/presentation/cubit/users_cubit.dart';
import 'package:frontend/shared/widgets/app_button.dart';
import 'package:frontend/shared/widgets/app_card.dart';
import 'package:frontend/shared/widgets/app_text_field.dart';
import 'package:frontend/shared/widgets/page_header.dart';
import 'package:frontend/shared/widgets/status_chip.dart';
import 'package:go_router/go_router.dart';

class UsersPage extends StatelessWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final String? currentUserId = context.watch<AuthCubit>().state.user?.id;

    return BlocBuilder<UsersCubit, UsersState>(
      builder: (BuildContext context, UsersState state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            PageHeader(
              title: 'Администраторы',
              trailing: AppPrimaryButton(
                label: 'Добавить пользователя',
                icon: Icons.person_add_alt_1,
                onPressed: () => _addUser(context),
              ),
            ),
            const SizedBox(height: 16),
            AppCard(
              padding: EdgeInsets.zero,
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: state.items.length,
                separatorBuilder: (BuildContext context, int index) =>
                    const Divider(height: 1),
                itemBuilder: (BuildContext context, int index) {
                  final user = state.items[index];
                  final bool isCurrent = user.id == currentUserId;
                  return ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        user.displayName.characters.first.toUpperCase(),
                      ),
                    ),
                    title: Text(
                      '${user.displayName}${isCurrent ? ' · вы' : ''}',
                    ),
                    subtitle: Text('${user.email} · ${user.role}'),
                    trailing: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        StatusChip(
                          status: user.isActive ? 'active' : 'blocked',
                        ),
                        IconButton(
                          tooltip: user.isActive
                              ? 'Заблокировать'
                              : 'Разблокировать',
                          onPressed: isCurrent
                              ? null
                              : () {
                                  if (user.isActive) {
                                    context.read<UsersCubit>().deactivate(
                                      user.id,
                                    );
                                  } else {
                                    context.read<UsersCubit>().activate(
                                      user.id,
                                    );
                                  }
                                },
                          icon: Icon(
                            user.isActive
                                ? Icons.lock_outline
                                : Icons.lock_open_outlined,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addUser(BuildContext context) async {
    await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => BlocProvider<UsersCubit>.value(
        value: context.read<UsersCubit>(),
        child: const AddUserDialog(),
      ),
    );
  }
}

class AddUserDialog extends StatefulWidget {
  const AddUserDialog({super.key});

  @override
  State<AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<AddUserDialog> {
  final TextEditingController displayNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool loading = false;
  bool passwordVisible = false;
  String? error;

  @override
  void dispose() {
    displayNameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      await context.read<UsersCubit>().create(
        displayName: displayNameController.text.trim(),
        email: emailController.text.trim(),
        password: passwordController.text,
      );
      if (mounted) {
        context.pop(true);
      }
    } on Object catch (exception) {
      setState(() => error = exception.toString());
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Добавить пользователя'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AppTextField(controller: displayNameController, label: 'Имя'),
            const SizedBox(height: 12),
            AppTextField(controller: emailController, label: 'Email'),
            const SizedBox(height: 12),
            AppTextField(
              controller: passwordController,
              label: 'Временный пароль',
              obscureText: !passwordVisible,
              autofillHints: const <String>[],
              enableSuggestions: false,
              autocorrect: false,
              suffixIcon: PasswordVisibilityButton(
                visible: passwordVisible,
                onPressed: () =>
                    setState(() => passwordVisible = !passwordVisible),
              ),
            ),
            if (error != null) ...<Widget>[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: loading ? null : () => context.pop(false),
          child: const Text('Отмена'),
        ),
        AppPrimaryButton(
          label: 'Создать',
          icon: Icons.person_add_alt_1,
          onPressed: loading ? null : submit,
        ),
      ],
    );
  }
}
