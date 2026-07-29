import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/features/settings/data/settings_repository.dart';
import 'package:frontend/features/settings/domain/system_settings.dart';

part 'settings_state.dart';

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._repository) : super(SettingsState.initial());

  final SettingsRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(status: SettingsStatus.loading));
    try {
      emit(
        SettingsState(
          status: SettingsStatus.ready,
          settings: await _repository.load(),
        ),
      );
    } catch (_) {
      emit(state.copyWith(status: SettingsStatus.failure));
    }
  }

  Future<void> updateInterval(int minutes) async {
    emit(
      SettingsState(
        status: SettingsStatus.ready,
        settings: await _repository.updateInterval(minutes),
      ),
    );
  }

  Future<void> updateTelegram({
    required bool enabled,
    required String chatId,
    required String minimumSeverity,
    required bool notifyRecovery,
    String botToken = '',
    bool clearBotToken = false,
    required List<String> ignoredErrorPatterns,
  }) async {
    emit(state.copyWith(status: SettingsStatus.loading));
    try {
      emit(
        SettingsState(
          status: SettingsStatus.ready,
          settings: await _repository.updateTelegram(
            enabled: enabled,
            chatId: chatId,
            minimumSeverity: minimumSeverity,
            notifyRecovery: notifyRecovery,
            botToken: botToken,
            clearBotToken: clearBotToken,
            ignoredErrorPatterns: ignoredErrorPatterns,
          ),
        ),
      );
    } catch (_) {
      emit(state.copyWith(status: SettingsStatus.failure));
      rethrow;
    }
  }

  Future<void> testTelegram() => _repository.testTelegram();
}
