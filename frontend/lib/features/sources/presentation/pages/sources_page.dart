import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/design/app_colors.dart';
import 'package:frontend/features/dashboard/presentation/pages/overview_page.dart';
import 'package:frontend/features/sources/domain/source.dart';
import 'package:frontend/features/sources/domain/source_test_result.dart';
import 'package:frontend/features/sources/presentation/cubit/sources_cubit.dart';
import 'package:frontend/shared/widgets/app_button.dart';
import 'package:frontend/shared/widgets/app_card.dart';
import 'package:frontend/shared/widgets/app_feedback.dart';
import 'package:frontend/shared/widgets/app_text_field.dart';
import 'package:frontend/shared/widgets/async_state_view.dart';
import 'package:frontend/shared/widgets/page_header.dart';
import 'package:frontend/shared/widgets/status_chip.dart';
import 'package:go_router/go_router.dart';

class SourcesPage extends StatelessWidget {
  const SourcesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SourcesCubit, SourcesState>(
      builder: (BuildContext context, SourcesState state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            PageHeader(
              title: 'Подключения к инфраструктуре',
              trailing: AppPrimaryButton(
                label: 'Добавить источник',
                icon: Icons.add,
                onPressed: () => _addSource(context),
              ),
            ),
            const SizedBox(height: 16),
            if (state.status == SourcesStatus.loading && state.items.isEmpty)
              const LoadingStateView()
            else if (state.items.isEmpty)
              const EmptyCardState(
                icon: Icons.storage_outlined,
                text: 'Источники пока не добавлены.',
              )
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: state.items.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final source = state.items[index];
                    return ListTile(
                      onTap: () => context.go('/sources/${source.id}'),
                      leading: Icon(
                        sourceIcon(source.type),
                        color: AppColors.primary,
                      ),
                      title: Text(source.name),
                      subtitle: Text(
                        '${sourceTypeLabel(source.type)} · ${source.baseUrl}',
                      ),
                      trailing: Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          StatusChip(status: source.status),
                          IconButton(
                            tooltip: 'Проверить',
                            onPressed: () => _testSource(context, source.id),
                            icon: const Icon(Icons.network_check),
                          ),
                          IconButton(
                            tooltip: 'Редактировать',
                            onPressed: () => _editSource(context, source),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Копировать',
                            onPressed: () => _copySource(context, source),
                            icon: const Icon(Icons.copy_outlined),
                          ),
                          IconButton(
                            tooltip: 'Удалить',
                            onPressed: () =>
                                context.read<SourcesCubit>().remove(source.id),
                            icon: const Icon(Icons.delete_outline),
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

  Future<void> _addSource(BuildContext context) async {
    final bool? created = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => BlocProvider<SourcesCubit>.value(
        value: context.read<SourcesCubit>(),
        child: const SourceDialog(),
      ),
    );
    if (created == true && context.mounted) {
      await context.read<SourcesCubit>().load();
    }
  }

  Future<void> _editSource(BuildContext context, Source source) async {
    final bool? updated = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => BlocProvider<SourcesCubit>.value(
        value: context.read<SourcesCubit>(),
        child: SourceDialog(source: source),
      ),
    );
    if (updated == true && context.mounted) {
      await context.read<SourcesCubit>().load();
    }
  }

  Future<void> _copySource(BuildContext context, Source source) async {
    final bool? created = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => BlocProvider<SourcesCubit>.value(
        value: context.read<SourcesCubit>(),
        child: SourceDialog(source: source, copying: true),
      ),
    );
    if (created == true && context.mounted) {
      await context.read<SourcesCubit>().load();
    }
  }

  Future<void> _testSource(BuildContext context, String sourceId) async {
    final SourceTestResult result = await context.read<SourcesCubit>().test(
      sourceId,
    );
    if (!context.mounted) {
      return;
    }

    showResultSnackBar(context, message: result.message, success: result.ok);
  }
}

class SourceDialog extends StatefulWidget {
  const SourceDialog({this.source, this.copying = false, super.key});

  final Source? source;
  final bool copying;

  @override
  State<SourceDialog> createState() => _SourceDialogState();
}

class _SourceDialogState extends State<SourceDialog> {
  late final TextEditingController nameController;
  late final TextEditingController urlController;
  late final TextEditingController backupNamespaceController;
  final TextEditingController tokenController = TextEditingController();
  late String type;
  bool loading = false;
  bool tokenVisible = false;
  String? error;

  bool get editing => widget.source != null && !widget.copying;

  String get _urlForSubmit {
    final value = urlController.text.trim();
    if (value.isEmpty || value.contains('://')) {
      return value;
    }
    if (type == 'ipmi') {
      return 'ipmi://$value';
    }
    if (type == 'old_ilo2') {
      return 'ssh://$value';
    }
    return value;
  }

  void _selectType(String nextType) {
    final current = urlController.text.trim();
    final currentDefault = _defaultUrlForType(type);
    setState(() {
      type = nextType;
      if (current.isEmpty ||
          current == currentDefault ||
          current == 'https://') {
        urlController.text = _defaultUrlForType(nextType);
        urlController.selection = TextSelection.collapsed(
          offset: urlController.text.length,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    final Source? source = widget.source;
    nameController = TextEditingController(text: source?.name ?? '');
    urlController = TextEditingController(text: source?.baseUrl ?? 'https://');
    backupNamespaceController = TextEditingController(
      text: source?.backupNamespace ?? '',
    );
    type = source?.type ?? 'proxmox_ve';
  }

  @override
  void dispose() {
    nameController.dispose();
    urlController.dispose();
    backupNamespaceController.dispose();
    tokenController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final backupNamespace = type == 'proxmox_ve'
          ? backupNamespaceController.text.trim()
          : '';
      if (editing) {
        await context.read<SourcesCubit>().update(
          id: widget.source!.id,
          name: nameController.text.trim(),
          type: type,
          baseUrl: _urlForSubmit,
          token: tokenController.text.trim(),
          backupNamespace: backupNamespace,
        );
      } else {
        await context.read<SourcesCubit>().create(
          name: nameController.text.trim(),
          type: type,
          baseUrl: _urlForSubmit,
          token: tokenController.text.trim(),
          backupNamespace: backupNamespace,
        );
      }
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
      title: Text(
        editing
            ? 'Редактировать источник'
            : widget.copying
            ? 'Копировать источник'
            : 'Добавить источник',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _sourceTypeChip(
                    value: 'proxmox_ve',
                    label: 'Proxmox VE',
                    icon: Icons.memory_outlined,
                  ),
                  _sourceTypeChip(
                    value: 'proxmox_backup',
                    label: 'Backup',
                    icon: Icons.backup_outlined,
                  ),
                  _sourceTypeChip(
                    value: 'redfish',
                    label: 'Redfish',
                    icon: Icons.developer_board_outlined,
                  ),
                  _sourceTypeChip(
                    value: 'old_ilo2',
                    label: 'iLO 2',
                    icon: Icons.dns_outlined,
                  ),
                  _sourceTypeChip(
                    value: 'ipmi',
                    label: 'IPMI',
                    icon: Icons.sensors_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              AppTextField(controller: nameController, label: 'Название'),
              const SizedBox(height: 12),
              AppTextField(
                controller: urlController,
                label: type == 'old_ilo2'
                    ? 'SSH URL'
                    : type == 'ipmi'
                    ? 'IPMI URL'
                    : 'Base URL',
                helperText: type == 'old_ilo2'
                    ? 'Формат: ssh://192.168.55.10'
                    : type == 'ipmi'
                    ? 'Формат: ipmi://192.168.2.206'
                    : null,
              ),
              const SizedBox(height: 12),
              if (type == 'proxmox_ve') ...<Widget>[
                AppTextField(
                  controller: backupNamespaceController,
                  label: 'Backup namespace',
                  helperText:
                      'PBS namespace этого PVE кластера. Пусто = root namespace.',
                ),
                const SizedBox(height: 12),
              ],
              AppTextField(
                controller: tokenController,
                label: type == 'redfish' || type == 'old_ilo2' || type == 'ipmi'
                    ? 'Логин и пароль'
                    : 'API token',
                helperText: editing
                    ? 'Оставьте пустым, чтобы не менять credentials.'
                    : type == 'redfish' || type == 'old_ilo2' || type == 'ipmi'
                    ? 'Формат: username:password'
                    : 'PVE: user@realm!tokenid=secret · PBS: user@realm!tokenid:secret',
                obscureText: !tokenVisible,
                autofillHints: const <String>[],
                enableSuggestions: false,
                autocorrect: false,
                suffixIcon: PasswordVisibilityButton(
                  visible: tokenVisible,
                  onPressed: () => setState(() => tokenVisible = !tokenVisible),
                ),
              ),
              if (error != null) ...<Widget>[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: loading ? null : () => context.pop(false),
          child: const Text('Отмена'),
        ),
        AppPrimaryButton(
          label: editing ? 'Сохранить' : 'Добавить',
          icon: editing ? Icons.save_outlined : Icons.add,
          onPressed: loading ? null : submit,
        ),
      ],
    );
  }

  Widget _sourceTypeChip({
    required String value,
    required String label,
    required IconData icon,
  }) {
    return ChoiceChip(
      selected: type == value,
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onSelected: (_) => _selectType(value),
    );
  }
}

String _defaultUrlForType(String type) => switch (type) {
  'ipmi' => 'ipmi://',
  'old_ilo2' => 'ssh://',
  _ => 'https://',
};
