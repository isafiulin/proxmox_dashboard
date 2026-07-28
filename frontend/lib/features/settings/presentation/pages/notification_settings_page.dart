import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/core/design/app_spacing.dart';
import 'package:frontend/features/settings/domain/system_settings.dart';
import 'package:frontend/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:frontend/shared/widgets/app_button.dart';
import 'package:frontend/shared/widgets/app_card.dart';
import 'package:frontend/shared/widgets/app_feedback.dart';
import 'package:frontend/shared/widgets/app_text_field.dart';
import 'package:frontend/shared/widgets/page_header.dart';
import 'package:frontend/shared/widgets/scrollable_page_frame.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  final _chatIdController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _initialized = false;
  bool _enabled = false;
  bool _hasStoredToken = false;
  bool _notifyRecovery = true;
  bool _tokenVisible = false;
  bool _clearToken = false;
  bool _saving = false;
  String _minimumSeverity = 'warning';

  @override
  void dispose() {
    _chatIdController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  void _apply(SystemSettings settings) {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _enabled = settings.telegramEnabled;
    _hasStoredToken = settings.hasTelegramBotToken;
    _chatIdController.text = settings.telegramChatId;
    _minimumSeverity = settings.telegramMinimumSeverity;
    _notifyRecovery = settings.telegramNotifyRecovery;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SettingsCubit, SettingsState>(
      listener: (context, state) {
        if (state.status == SettingsStatus.ready && !_initialized) {
          setState(() => _apply(state.settings));
        }
      },
      child: Builder(
        builder: (context) {
          final state = context.watch<SettingsCubit>().state;
          if (!_initialized && state.status == SettingsStatus.ready) {
            _apply(state.settings);
          }
          return ScrollablePageFrame(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const PageHeader(
                      title: 'Telegram-уведомления',
                      subtitle:
                          'Настройка бота, уровня аварий и компактной доставки без повторов.',
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _connectionCard(),
                    const SizedBox(height: AppSpacing.lg),
                    _rulesCard(),
                    const SizedBox(height: AppSpacing.lg),
                    _previewCard(),
                    const SizedBox(height: AppSpacing.xl),
                    Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.md,
                      children: <Widget>[
                        AppPrimaryButton(
                          label: _saving ? 'Сохранение...' : 'Сохранить',
                          icon: Icons.save_outlined,
                          onPressed: _saving ? null : () => _save(false),
                        ),
                        AppSecondaryButton(
                          label: 'Сохранить и проверить',
                          icon: Icons.send_outlined,
                          onPressed: _saving ? null : () => _save(true),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _connectionCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Отправлять уведомления в Telegram'),
            subtitle: const Text(
              'Сообщение приходит только при новой аварии, усилении уровня или восстановлении.',
            ),
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _tokenController,
            label: 'Токен бота',
            helperText: _hasStoredToken && !_clearToken
                ? 'Токен сохранён зашифрованно. Оставьте поле пустым, чтобы не менять.'
                : 'Получите токен у @BotFather.',
            obscureText: !_tokenVisible,
            enableSuggestions: false,
            autocorrect: false,
            prefixIcon: Icons.key_outlined,
            onChanged: (value) {
              if (value.isNotEmpty && _clearToken) {
                setState(() => _clearToken = false);
              }
            },
            suffixIcon: PasswordVisibilityButton(
              visible: _tokenVisible,
              onPressed: () => setState(() => _tokenVisible = !_tokenVisible),
            ),
          ),
          if (_hasStoredToken && !_clearToken) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _clearToken = true;
                  _enabled = false;
                  _tokenController.clear();
                }),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Удалить сохранённый токен'),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _chatIdController,
            label: 'Chat ID',
            helperText:
                'Для группы обычно отрицательный ID, например -1001234567890. Бот должен быть добавлен в чат.',
            keyboardType: TextInputType.text,
            prefixIcon: Icons.tag,
          ),
        ],
      ),
    );
  }

  Widget _rulesCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Правила отправки',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          DropdownButtonFormField<String>(
            initialValue: _minimumSeverity,
            decoration: const InputDecoration(labelText: 'Минимальный уровень'),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem(
                value: 'warning',
                child: Text('Warning и Critical'),
              ),
              DropdownMenuItem(
                value: 'critical',
                child: Text('Только Critical'),
              ),
            ],
            onChanged: (value) =>
                setState(() => _minimumSeverity = value ?? 'warning'),
          ),
          const SizedBox(height: AppSpacing.md),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Сообщать о восстановлении'),
            subtitle: const Text(
              'Когда проблема исчезнет, бот пришлёт одно короткое подтверждение.',
            ),
            value: _notifyRecovery,
            onChanged: (value) => setState(() => _notifyRecovery = value),
          ),
          const Divider(),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.filter_alt_outlined),
            title: Text('Защита от спама включена всегда'),
            subtitle: Text(
              'Неизменившаяся авария повторно не отправляется. За один опрос формируется одно сообщение на источник.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewCard() {
    return const AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Пример сообщения',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          SizedBox(height: AppSpacing.md),
          Text('🔴 Новая авария'),
          Text('Источник: mitris-server'),
          Text('Тип: old_ilo2'),
          Text('Время: 28.07.2026 23:23'),
          SizedBox(height: AppSpacing.sm),
          Text('🔴 Power Supply 1'),
          Text('🟡 System Power Supplies Not Redundant'),
          SizedBox(height: AppSpacing.sm),
          Text('✅ Восстановлено: 1'),
          Text('• Fan 2'),
        ],
      ),
    );
  }

  Future<void> _save(bool testAfterSave) async {
    final chatId = _chatIdController.text.trim();
    final token = _tokenController.text.trim();
    if (_enabled &&
        (chatId.isEmpty ||
            (token.isEmpty && (!_hasStoredToken || _clearToken)))) {
      showResultSnackBar(
        context,
        message: 'Для включения укажите токен бота и Chat ID.',
        success: false,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final cubit = context.read<SettingsCubit>();
      await cubit.updateTelegram(
        enabled: _enabled,
        chatId: chatId,
        minimumSeverity: _minimumSeverity,
        notifyRecovery: _notifyRecovery,
        botToken: token,
        clearBotToken: _clearToken,
      );
      final saved = cubit.state.settings;
      if (!mounted) {
        return;
      }
      setState(() {
        _hasStoredToken = saved.hasTelegramBotToken;
        _clearToken = false;
        _tokenController.clear();
      });
      if (testAfterSave) {
        await cubit.testTelegram();
      }
      if (!mounted) {
        return;
      }
      showResultSnackBar(
        context,
        message: testAfterSave
            ? 'Настройки сохранены, тестовое сообщение отправлено.'
            : 'Настройки Telegram сохранены.',
        success: true,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      showResultSnackBar(context, message: '$error', success: false);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}
